use crate::api::ApiError;
use chrono::{DateTime, Utc};
use hmac::{Hmac, Mac};
use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{fs, path::Path, sync::Arc};
use tokio::sync::Mutex;
use uuid::Uuid;

const ACCESS: i64 = 15 * 60;
const IDLE: i64 = 30 * 24 * 3600;
const LIFETIME: i64 = 90 * 24 * 3600;

#[derive(Clone)]
pub(crate) struct Devices(Arc<Mutex<Connection>>);

#[derive(Serialize)]
pub(crate) struct DeviceTokens {
    access_token: String,
    token_type: &'static str,
    expires_at: DateTime<Utc>,
    refresh_token: String,
    refresh_expires_at: DateTime<Utc>,
}

impl From<rusqlite::Error> for ApiError {
    fn from(_: rusqlite::Error) -> Self {
        Self::internal()
    }
}

impl Devices {
    pub fn memory() -> Self {
        Self::init(Connection::open_in_memory().expect("SQLite in memory")).expect("device schema")
    }

    pub fn open(path: &Path, realm: &str) -> Result<Self, Box<dyn std::error::Error>> {
        if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
            let mut dir = fs::DirBuilder::new();
            #[cfg(unix)]
            {
                use std::os::unix::fs::DirBuilderExt;
                dir.mode(0o700);
            }
            dir.recursive(true).create(parent)?;
        }
        let mut file = fs::OpenOptions::new();
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            file.mode(0o600);
        }
        file.write(true).create(true).truncate(false).open(path)?;
        let mut db = Connection::open(path)?;
        let tx = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
        tx.execute_batch("CREATE TABLE IF NOT EXISTS session_realm(id INTEGER PRIMARY KEY CHECK(id=1), name TEXT NOT NULL)")?;
        tx.execute(
            "INSERT OR IGNORE INTO session_realm(id,name) VALUES (1,?1)",
            [realm],
        )?;
        let saved: String =
            tx.query_row("SELECT name FROM session_realm WHERE id=1", [], |row| {
                row.get(0)
            })?;
        if saved != realm {
            return Err("Use a separate session database for each identity provider".into());
        }
        tx.commit()?;
        Ok(Self::init(db)?)
    }

    fn init(db: Connection) -> rusqlite::Result<Self> {
        db.execute_batch("CREATE TABLE IF NOT EXISTS devices (
            refresh_hash BLOB PRIMARY KEY NOT NULL, subject TEXT NOT NULL, access_hash BLOB UNIQUE NOT NULL,
            access_until INTEGER NOT NULL, idle_until INTEGER NOT NULL, hard_until INTEGER NOT NULL
        )")?;
        Ok(Self(Arc::new(Mutex::new(db))))
    }

    async fn run<T: Send + 'static>(
        &self,
        op: impl FnOnce(&mut Connection) -> Result<T, ApiError> + Send + 'static,
    ) -> Result<T, ApiError> {
        let mut db = self.0.clone().lock_owned().await;
        tokio::task::spawn_blocking(move || op(&mut db))
            .await
            .map_err(|_| ApiError::internal())?
    }

    pub async fn issue(&self, subject: String) -> Result<DeviceTokens, ApiError> {
        self.run(move |db| {
            let now = Utc::now().timestamp();
            let tx = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
            tx.execute("DELETE FROM devices WHERE idle_until <= ?1 OR hard_until <= ?1", [now])?;
            if tx.query_row("SELECT COUNT(*) FROM devices", [], |r| r.get::<_, i64>(0))? >= 128 {
                return Err(ApiError::capacity());
            }
            let refresh = format!("xr_{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple());
            let pair = tokens(refresh, now + ACCESS, now + IDLE)?;
            tx.execute("INSERT INTO devices(refresh_hash,subject,access_hash,access_until,idle_until,hard_until) VALUES (?1,?2,?3,?4,?5,?6)",
                params![digest(&pair.refresh_token),subject,digest(&pair.access_token),now + ACCESS,now + IDLE,now + LIFETIME])?;
            tx.commit()?;
            Ok(pair)
        }).await
    }

    pub async fn refresh(&self, refresh: String) -> Result<DeviceTokens, ApiError> {
        if !refresh.starts_with("xr_") {
            return Err(ApiError::unauthorized());
        }
        self.run(move |db| {
            let now = Utc::now().timestamp();
            let hash = digest(&refresh);
            let tx = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
            let (current, hard): (i64,i64) = tx.query_row("SELECT access_until,hard_until FROM devices WHERE refresh_hash=?1 AND idle_until>?2 AND hard_until>?2",
                params![hash,now], |r| Ok((r.get(0)?,r.get(1)?))).optional()?.ok_or_else(ApiError::unauthorized)?;
            let expires = if current > now { current } else { (now + ACCESS).min(hard) };
            let idle = (now + IDLE).min(hard);
            let pair = tokens(refresh, expires, idle)?;
            tx.execute("UPDATE devices SET access_hash=?1,access_until=?2,idle_until=?3 WHERE refresh_hash=?4",
                params![digest(&pair.access_token),expires,idle,hash])?;
            tx.commit()?;
            Ok(pair)
        }).await
    }

    pub async fn subject(&self, access: &str) -> Result<String, ApiError> {
        let hash = digest(access);
        self.run(move |db| {
            db.prepare_cached("SELECT subject FROM devices WHERE access_hash=?1 AND access_until>?2 AND idle_until>?2 AND hard_until>?2")?
                .query_row(params![hash,Utc::now().timestamp()], |r| r.get(0)).optional()?
                .ok_or_else(ApiError::unauthorized)
        }).await
    }

    pub async fn revoke(&self, token: &str) -> Result<(), ApiError> {
        let hash = digest(token);
        self.run(move |db| {
            if db.execute(
                "DELETE FROM devices WHERE refresh_hash=?1 OR access_hash=?1",
                [hash],
            )? == 0
            {
                return Err(ApiError::unauthorized());
            }
            Ok(())
        })
        .await
    }
}

fn digest(token: &str) -> [u8; 32] {
    Sha256::digest(token.as_bytes()).into()
}

fn tokens(refresh: String, expires: i64, idle: i64) -> Result<DeviceTokens, ApiError> {
    // Repeating a refresh after a lost response returns the same still-valid access token.
    let mut mac =
        Hmac::<Sha256>::new_from_slice(refresh.as_bytes()).map_err(|_| ApiError::internal())?;
    mac.update(b"xiaobao/access/v1");
    mac.update(&expires.to_be_bytes());
    Ok(DeviceTokens {
        access_token: format!("xa_{:x}", mac.finalize().into_bytes()),
        token_type: "Bearer",
        expires_at: DateTime::from_timestamp(expires, 0).ok_or_else(ApiError::internal)?,
        refresh_token: refresh,
        refresh_expires_at: DateTime::from_timestamp(idle, 0).ok_or_else(ApiError::internal)?,
    })
}
