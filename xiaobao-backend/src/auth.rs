use crate::{AppState, api::ApiError, domain::Student};
use axum::{
    extract::FromRequestParts,
    http::{HeaderMap, request::Parts},
};
use chrono::{DateTime, Utc};
use serde::Serialize;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use uuid::Uuid;

#[derive(Clone)]
struct StoredSession {
    subject: String,
    expires: Instant,
}

pub(crate) struct Sessions {
    entries: Mutex<HashMap<String, StoredSession>>,
    ttl: Duration,
    capacity: usize,
}

#[derive(Serialize)]
pub(crate) struct IssuedSession {
    pub access_token: String,
    token_type: &'static str,
    expires_at: DateTime<Utc>,
}

impl Sessions {
    pub fn new(ttl: Duration, capacity: usize) -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
            ttl,
            capacity,
        }
    }
    pub fn issue(&self, subject: String) -> Result<IssuedSession, ApiError> {
        let now = Instant::now();
        let mut entries = self.entries.lock().map_err(|_| ApiError::internal())?;
        entries.retain(|_, session| session.expires > now);
        if entries.len() >= self.capacity {
            return Err(ApiError::capacity());
        }
        let access_token = Uuid::new_v4().to_string();
        entries.insert(
            access_token.clone(),
            StoredSession {
                subject,
                expires: now + self.ttl,
            },
        );
        Ok(IssuedSession {
            access_token,
            token_type: "Bearer",
            expires_at: Utc::now()
                + chrono::Duration::from_std(self.ttl).map_err(|_| ApiError::internal())?,
        })
    }
    fn subject(&self, token: &str) -> Result<String, ApiError> {
        let mut entries = self.entries.lock().map_err(|_| ApiError::internal())?;
        if let Some(session) = entries.get(token) {
            if session.expires > Instant::now() {
                return Ok(session.subject.clone());
            }
        }
        entries.remove(token);
        Err(ApiError::unauthorized())
    }
    pub fn revoke(&self, token: &str) -> Result<(), ApiError> {
        let removed = self
            .entries
            .lock()
            .map_err(|_| ApiError::internal())?
            .remove(token);
        if removed.is_some_and(|session| session.expires > Instant::now()) {
            Ok(())
        } else {
            Err(ApiError::unauthorized())
        }
    }
}

#[derive(Clone)]
pub(crate) struct Session {
    pub subject: String,
}

pub(crate) fn bearer(headers: &HeaderMap) -> Result<&str, ApiError> {
    let header = headers
        .get("authorization")
        .and_then(|h| h.to_str().ok())
        .ok_or_else(ApiError::unauthorized)?;
    let (scheme, token) = header.split_once(' ').ok_or_else(ApiError::unauthorized)?;
    if !scheme.eq_ignore_ascii_case("bearer") || token.is_empty() {
        return Err(ApiError::unauthorized());
    }
    Ok(token)
}

impl FromRequestParts<AppState> for Session {
    type Rejection = ApiError;
    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        if let Some(session) = parts.extensions.remove::<Self>() {
            return Ok(session);
        }
        let token = bearer(&parts.headers)?;
        Ok(Self {
            subject: if token.starts_with("xa_") {
                state.devices.subject(token).await?
            } else {
                state.sessions.subject(token)?
            },
        })
    }
}

pub(crate) struct CurrentStudent(pub Arc<Student>);

impl FromRequestParts<AppState> for CurrentStudent {
    type Rejection = ApiError;
    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let session = Session::from_request_parts(parts, state).await?;
        let student = state.provider.student(&session.subject).await?;
        if student.profile.id != session.subject {
            return Err(ApiError::internal());
        }
        Ok(Self(student))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn expired_sessions_are_rejected_and_reclaimed() {
        let sessions = Sessions::new(Duration::ZERO, 1);
        let first = sessions.issue("a".into()).unwrap();
        assert!(sessions.subject(&first.access_token).is_err());
        assert!(sessions.issue("b".into()).is_ok());
    }
    #[test]
    fn session_capacity_is_bounded_and_revocation_frees_space() {
        let sessions = Sessions::new(Duration::from_secs(60), 1);
        let first = sessions.issue("a".into()).unwrap();
        assert!(sessions.issue("b".into()).is_err());
        sessions.revoke(&first.access_token).unwrap();
        assert!(sessions.subject(&first.access_token).is_err());
        assert!(sessions.issue("b".into()).is_ok());
    }
}
