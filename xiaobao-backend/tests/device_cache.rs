use axum::{
    Router,
    body::{Body, to_bytes},
    http::{HeaderMap, Request, StatusCode},
};
use chrono::NaiveDate;
use rusqlite::Connection;
use serde_json::{Value, json};
use std::{path::Path, sync::Arc};
use tower::ServiceExt;
use xiaobao_backend::{AppState, app, provider::DemoProvider};

fn server(path: Option<&Path>) -> Router {
    let provider = Arc::new(DemoProvider::new(
        NaiveDate::from_ymd_opt(2026, 11, 18).unwrap(),
    ));
    app(match path {
        Some(p) => AppState::with_session_db(provider, p).unwrap(),
        None => AppState::new(provider),
    })
}
async fn request(
    app: &Router,
    method: &str,
    path: &str,
    bearer: &str,
    tag: &str,
    body: Value,
) -> (StatusCode, HeaderMap, Value) {
    let mut req = Request::builder()
        .method(method)
        .uri(format!("/api/v1/{path}"));
    if !bearer.is_empty() {
        req = req.header("authorization", format!("Bearer {bearer}"));
    }
    if !tag.is_empty() {
        req = req.header("if-none-match", tag);
    }
    let req = if body.is_null() {
        req.body(Body::empty())
    } else {
        req.header("content-type", "application/json")
            .body(Body::from(body.to_string()))
    }
    .unwrap();
    let (head, body) = app.clone().oneshot(req).await.unwrap().into_parts();
    let bytes = to_bytes(body, 1 << 20).await.unwrap();
    if head.status == StatusCode::NOT_MODIFIED {
        assert!(bytes.is_empty());
    }
    (
        head.status,
        head.headers,
        if bytes.is_empty() {
            Value::Null
        } else {
            serde_json::from_slice(&bytes).unwrap()
        },
    )
}
async fn login(app: &Router, profile: &str, remember: bool) -> Value {
    let (s, h, v) = request(
        app,
        "POST",
        "demo/sessions",
        "",
        "",
        json!({"profile":profile,"remember":remember}),
    )
    .await;
    assert_eq!(s, 201);
    assert_eq!(h["cache-control"], "no-store");
    v["data"].clone()
}
async fn refresh(app: &Router, token: &str) -> (StatusCode, HeaderMap, Value) {
    request(
        app,
        "POST",
        "session/refresh",
        "",
        "",
        json!({"refresh_token":token}),
    )
    .await
}

#[tokio::test]
async fn restart_renew_retry_and_revoke_one_device() {
    let dir = std::env::temp_dir().join(uuid::Uuid::new_v4().to_string());
    let path = dir.join("sessions.sqlite3");
    let a = server(Some(&path));
    let first = login(&a, "demo-a", true).await;
    let token = first["access_token"].as_str().unwrap();
    let renewal = first["refresh_token"].as_str().unwrap();
    let other = login(&a, "demo-a", true).await;
    let ephemeral = login(&a, "demo-b", false).await;
    assert!(ephemeral.get("refresh_token").is_none());
    drop(a);

    let b = server(Some(&path));
    assert_eq!(
        request(
            &b,
            "GET",
            "me",
            ephemeral["access_token"].as_str().unwrap(),
            "",
            Value::Null
        )
        .await
        .0,
        401
    );
    assert_eq!(
        request(&b, "GET", "me", token, "", Value::Null).await.2["data"]["profile"]["id"],
        "demo-a"
    );
    assert_eq!(
        request(&b, "GET", "me", renewal, "", Value::Null).await.0,
        401
    );
    assert_eq!(refresh(&b, token).await.0, 401);
    let db = Connection::open(&path).unwrap();
    use sha2::{Digest, Sha256};
    let hash: [u8; 32] = Sha256::digest(renewal).into();
    let lengths: (i64, i64) = db
        .query_row(
            "SELECT length(refresh_hash),length(access_hash) FROM devices WHERE refresh_hash=?1",
            [hash],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(lengths, (32, 32));
    db.execute(
        "UPDATE devices SET access_until=0 WHERE refresh_hash=?1",
        [hash],
    )
    .unwrap();
    assert_eq!(
        request(&b, "GET", "grades", token, "", Value::Null).await.0,
        401
    );
    let (r1, r2) = tokio::join!(refresh(&b, renewal), refresh(&b, renewal));
    assert_eq!(r1.0, 200);
    assert_eq!(r2.0, 200);
    assert_eq!(r1.2["data"]["access_token"], r2.2["data"]["access_token"]);
    let new_access = r1.2["data"]["access_token"].as_str().unwrap();
    assert_eq!(
        request(&b, "GET", "grades", new_access, "", Value::Null)
            .await
            .0,
        200
    );
    assert_eq!(
        request(&b, "DELETE", "session", renewal, "", Value::Null)
            .await
            .0,
        204
    );
    assert_eq!(refresh(&b, renewal).await.0, 401);
    assert_eq!(
        request(&b, "GET", "grades", new_access, "", Value::Null)
            .await
            .0,
        401
    );
    let other_refresh = other["refresh_token"].as_str().unwrap();
    assert_eq!(refresh(&b, other_refresh).await.0, 200);
    db.execute("UPDATE devices SET idle_until=0", []).unwrap();
    assert_eq!(refresh(&b, other_refresh).await.0, 401);
    db.execute(
        "UPDATE devices SET idle_until=9223372036854775807, hard_until=0",
        [],
    )
    .unwrap();
    assert_eq!(refresh(&b, other_refresh).await.0, 401);
    drop(db);
    drop(b);
    std::fs::remove_dir_all(dir).unwrap();
}

#[tokio::test]
async fn validators_require_current_auth_and_match_only_the_same_snapshot_account_and_query() {
    let a = server(None);
    let alice = login(&a, "demo-a", false).await;
    let bob = login(&a, "demo-b", false).await;
    let token = alice["access_token"].as_str().unwrap();
    let path = "schedule?date=2026-11-18";
    let (s, h, _) = request(&a, "GET", path, token, "", Value::Null).await;
    assert_eq!(s, 200);
    assert_eq!(h["cache-control"], "private, max-age=300");
    assert_eq!(h["vary"], "Authorization");
    let tag = h["etag"].to_str().unwrap();
    let (s, h, _) = request(
        &a,
        "GET",
        path,
        token,
        &format!("\"other\", {tag}"),
        Value::Null,
    )
    .await;
    assert_eq!(s, 304);
    assert_eq!(h["etag"], tag);
    assert_eq!(
        request(
            &a,
            "GET",
            path,
            bob["access_token"].as_str().unwrap(),
            tag,
            Value::Null
        )
        .await
        .0,
        200
    );
    assert_eq!(
        request(
            &a,
            "GET",
            "schedule?date=2026-11-19",
            token,
            tag,
            Value::Null
        )
        .await
        .0,
        200
    );
    assert_eq!(
        request(&a, "GET", "resources/unknown", token, "*", Value::Null)
            .await
            .0,
        404
    );
    assert_eq!(
        request(&a, "GET", "courses", token, "", Value::Null)
            .await
            .1["cache-control"],
        "private, max-age=86400"
    );
    request(&a, "DELETE", "session", token, "", Value::Null).await;
    let (s, h, _) = request(&a, "GET", path, token, tag, Value::Null).await;
    assert_eq!(s, 401);
    assert_eq!(h["cache-control"], "no-store");
    let b = server(None);
    let alice = login(&b, "demo-a", false).await;
    assert_eq!(
        request(
            &b,
            "GET",
            path,
            alice["access_token"].as_str().unwrap(),
            tag,
            Value::Null
        )
        .await
        .0,
        200
    );
}

#[tokio::test]
async fn statistics_are_cached_only_for_the_same_account_and_filter() {
    let router = server(None);
    let a = login(&router, "demo-a", false).await;
    let b = login(&router, "demo-b", false).await;
    let token_a = a["access_token"].as_str().unwrap();
    let token_b = b["access_token"].as_str().unwrap();
    let uri = "work-statistics?kind=task";
    let (status, headers, data_a) = request(&router, "GET", uri, token_a, "", Value::Null).await;
    assert_eq!(status, 200);
    assert_eq!(headers["vary"], "Authorization");
    assert_eq!(headers["cache-control"], "private, max-age=300");
    let tag = headers["etag"].to_str().unwrap();
    assert_eq!(
        request(&router, "GET", uri, token_a, tag, Value::Null)
            .await
            .0,
        304
    );
    assert_eq!(
        request(&router, "GET", uri, "", tag, Value::Null).await.0,
        401
    );
    let (status, headers_b, data_b) = request(&router, "GET", uri, token_b, tag, Value::Null).await;
    assert_eq!(status, 200);
    assert_ne!(headers_b["etag"], tag);
    assert_ne!(data_a["data"], data_b["data"]);
    let (status, _, data) = request(
        &router,
        "GET",
        "work-statistics?kind=task&work_type=reading",
        token_a,
        tag,
        Value::Null,
    )
    .await;
    assert_eq!(status, 200);
    assert_eq!(data["data"]["total"], 1);
}

#[tokio::test]
async fn unchanged_queries_skip_the_student_data_source_and_a_new_revision_reloads_it() {
    use async_trait::async_trait;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering::SeqCst};
    use xiaobao_backend::{
        domain::{DateRange, Lesson, Profile, Student},
        provider::{ProviderError, SchoolProvider},
    };
    struct CountReads {
        inner: DemoProvider,
        reads: AtomicUsize,
        updated: AtomicBool,
    }
    #[async_trait]
    impl SchoolProvider for CountReads {
        fn source(&self) -> &'static str {
            "demo"
        }
        fn cache_revision(&self, _: &str) -> Option<&str> {
            Some(if self.updated.load(SeqCst) { "2" } else { "1" })
        }
        fn demo_profiles(&self) -> Vec<Profile> {
            self.inner.demo_profiles()
        }
        async fn student(&self, subject: &str) -> Result<Arc<Student>, ProviderError> {
            self.reads.fetch_add(1, SeqCst);
            self.inner.student(subject).await
        }
        async fn lessons(
            &self,
            subject: &str,
            range: DateRange,
        ) -> Result<Vec<Lesson>, ProviderError> {
            self.inner.lessons(subject, range).await
        }
    }
    let source = Arc::new(CountReads {
        inner: DemoProvider::new(NaiveDate::from_ymd_opt(2026, 11, 18).unwrap()),
        reads: AtomicUsize::new(0),
        updated: AtomicBool::new(false),
    });
    let router = app(AppState::new(source.clone()));
    let session = login(&router, "demo-a", false).await;
    let token = session["access_token"].as_str().unwrap();
    let (s, h, _) = request(&router, "GET", "grades", token, "", Value::Null).await;
    assert_eq!(s, 200);
    let tag = h["etag"].to_str().unwrap();
    assert_eq!(
        request(&router, "GET", "grades", token, tag, Value::Null)
            .await
            .0,
        304
    );
    assert_eq!(source.reads.load(SeqCst), 1);
    source.updated.store(true, SeqCst);
    assert_eq!(
        request(&router, "GET", "grades", token, tag, Value::Null)
            .await
            .0,
        200
    );
    assert_eq!(source.reads.load(SeqCst), 2);
}

#[tokio::test]
async fn daily_and_offline_teaching_slots_are_the_same_source() {
    let app = server(None);
    let login = login(&app, "demo-b", false).await;
    let token = login["access_token"].as_str().unwrap();
    let (_, _, manifest) = request(&app, "GET", "offline/versions", token, "", Value::Null).await;
    let (status, _, offline) = request(
        &app,
        "POST",
        "offline/data",
        token,
        "",
        json!({"version":manifest["data"]["version"],"parts":["timetable"]}),
    )
    .await;
    assert_eq!(status, 200);
    let table = &offline["data"]["parts"]["timetable"];
    for date in ["2027-03-08", "2027-03-09"] {
        let (status, _, direct) = request(
            &app,
            "GET",
            &format!("schedule?date={date}"),
            token,
            "",
            Value::Null,
        )
        .await;
        assert_eq!(status, 200);
        let day = direct["data"]["day"].as_u64().unwrap() as usize;
        let slots = direct["data"]["teaching_slots"].as_array().unwrap();
        assert_eq!(slots, table["teaching_slots"][day - 1].as_array().unwrap());
        assert_eq!(
            slots
                .iter()
                .map(|s| (s["start"].as_u64().unwrap(), s["end"].as_u64().unwrap()))
                .collect::<Vec<_>>(),
            [
                (480, 560),
                (610, 650),
                (660, 700),
                (710, 750),
                (805, 845),
                (855, 895),
                (905, 945)
            ]
        );
        assert!(
            slots
                .windows(2)
                .all(|w| w[0]["end"].as_u64().unwrap() < w[1]["start"].as_u64().unwrap())
        );
    }
    let (_, _, rest) = request(
        &app,
        "GET",
        "schedule?date=2027-03-13",
        token,
        "",
        Value::Null,
    )
    .await;
    assert!(rest["data"].get("teaching_slots").is_none());
}

#[tokio::test]
async fn published_hs_calendar_matches_daily_and_offline_without_projecting_outside_coverage() {
    let provider =
        DemoProvider::with_hs_calendar(NaiveDate::from_ymd_opt(2026, 11, 20).unwrap()).unwrap();
    let app = app(AppState::new(Arc::new(provider)));
    let session = login(&app, "demo-a", false).await;
    let token = session["access_token"].as_str().unwrap();
    let (status, _, manifest) =
        request(&app, "GET", "offline/versions", token, "", Value::Null).await;
    assert_eq!(status, 200);
    let (status, _, offline) = request(
        &app,
        "POST",
        "offline/data",
        token,
        "",
        json!({"version":manifest["data"]["version"],"parts":["timetable"]}),
    )
    .await;
    assert_eq!(status, 200);
    let calendar = &offline["data"]["parts"]["timetable"]["school_calendar"];
    assert_eq!(calendar["division"], "HS");
    assert_eq!(calendar["days"].as_array().unwrap().len(), 365);

    for (date, state, printed, effective) in [
        ("2027-03-26", "no_class", Value::Null, Value::Null),
        ("2027-04-23", "teaching", json!(2), json!(2)),
        ("2027-04-26", "no_class", json!(2), Value::Null),
        ("2027-04-27", "teaching", json!(3), json!(3)),
        ("2027-08-02", "unpublished", Value::Null, Value::Null),
    ] {
        let (status, _, body) = request(
            &app,
            "GET",
            &format!("schedule?date={date}"),
            token,
            "",
            Value::Null,
        )
        .await;
        assert_eq!(status, 200);
        let data = &body["data"];
        assert_eq!(data["day"], effective);
        assert_eq!(data["calendar_day"]["status"], state);
        assert_eq!(data["calendar_day"]["day"], printed);
        assert_eq!(
            data["lessons"].as_array().unwrap().len(),
            if effective.is_null() { 0 } else { 6 }
        );
        if let Some(row) = calendar["days"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["date"] == date)
        {
            assert_eq!(&data["calendar_day"], row);
        }
    }
}

#[tokio::test]
async fn offline_manifest_is_account_scoped_stable_across_restarts_and_pulls_only_selected_data() {
    let app = server(None);
    let alice = login(&app, "demo-a", false).await;
    let bob = login(&app, "demo-b", false).await;
    let a = alice["access_token"].as_str().unwrap();
    let b = bob["access_token"].as_str().unwrap();
    let (status, headers, first) =
        request(&app, "GET", "offline/versions", a, "", Value::Null).await;
    assert_eq!(status, 200);
    assert_eq!(headers["cache-control"], "private, no-cache");
    assert_eq!(headers["vary"], "Authorization");
    let tag = headers["etag"].to_str().unwrap();
    let metadata = &first["data"];
    assert_eq!(metadata["parts"].as_object().unwrap().len(), 9);
    assert!(
        metadata["parts"]
            .as_object()
            .unwrap()
            .values()
            .all(|v| v.as_str().unwrap().len() == 64)
    );
    assert_eq!(
        request(&app, "GET", "offline/versions", a, tag, Value::Null)
            .await
            .0,
        304
    );
    assert_eq!(
        request(&app, "GET", "offline/versions", "", tag, Value::Null)
            .await
            .0,
        401
    );
    assert_eq!(
        request(&app, "GET", "offline/versions", b, tag, Value::Null)
            .await
            .0,
        200
    );
    let query = json!({"version":metadata["version"],"parts":["attendance"]});
    let (status, _, packet) = request(&app, "POST", "offline/data", a, "", query.clone()).await;
    assert_eq!(status, 200);
    assert_eq!(
        packet["data"]["parts"]
            .as_object()
            .unwrap()
            .keys()
            .collect::<Vec<_>>(),
        ["attendance"]
    );
    let full = request(&app, "GET", "attendance", a, "", Value::Null)
        .await
        .2;
    assert_eq!(
        packet["data"]["parts"]["attendance"]["records"],
        full["data"]["records"]
    );
    assert_eq!(
        request(&app, "POST", "offline/data", b, "", query).await.0,
        409
    );
    for fields in [json!(["grades", "grades"]), json!(["password"]), json!([])] {
        assert_eq!(
            request(
                &app,
                "POST",
                "offline/data",
                a,
                "",
                json!({"version":metadata["version"],"parts":fields})
            )
            .await
            .0,
            400
        );
    }
    let restarted = server(None);
    let restored = login(&restarted, "demo-a", false).await;
    assert_eq!(
        request(
            &restarted,
            "GET",
            "offline/versions",
            restored["access_token"].as_str().unwrap(),
            tag,
            Value::Null
        )
        .await
        .0,
        304
    );
}

#[tokio::test]
async fn changing_attendance_alone_changes_only_its_module_and_the_manifest() {
    use std::collections::BTreeMap;
    use std::sync::atomic::{AtomicBool, Ordering};
    use xiaobao_backend::domain::{DateRange, Lesson, Profile, Student};
    use xiaobao_backend::offline::{OfflineCatalog, Part};
    use xiaobao_backend::provider::{ProviderError, SchoolProvider};
    struct Source {
        inner: DemoProvider,
        versions: [Arc<OfflineCatalog>; 2],
        revised: AtomicBool,
    }
    #[async_trait::async_trait]
    impl SchoolProvider for Source {
        fn source(&self) -> &'static str {
            "demo"
        }
        fn demo_profiles(&self) -> Vec<Profile> {
            self.inner.demo_profiles()
        }
        async fn offline_catalog(
            &self,
            subject: &str,
        ) -> Result<Arc<OfflineCatalog>, ProviderError> {
            if subject != "demo-a" {
                return Err(ProviderError::NotFound);
            }
            Ok(self.versions[usize::from(self.revised.load(Ordering::Relaxed))].clone())
        }
        async fn student(&self, _: &str) -> Result<Arc<Student>, ProviderError> {
            panic!("a version check must not materialize a student")
        }
        async fn lessons(&self, _: &str, _: DateRange) -> Result<Vec<Lesson>, ProviderError> {
            panic!("unexpected timetable read")
        }
    }
    let make = |record| {
        Arc::new(OfflineCatalog::new(
            "demo-a",
            BTreeMap::from([
                (
                    Part::Courses,
                    serde_json::value::to_raw_value(&json!(["Math"])).unwrap(),
                ),
                (
                    Part::Attendance,
                    serde_json::value::to_raw_value(&json!([record])).unwrap(),
                ),
            ]),
        ))
    };
    let source = Arc::new(Source {
        inner: DemoProvider::new(NaiveDate::from_ymd_opt(2026, 11, 18).unwrap()),
        versions: [make("absent"), make("present")],
        revised: AtomicBool::new(false),
    });
    let app = app(AppState::new(source.clone()));
    let auth = login(&app, "demo-a", false).await;
    let token = auth["access_token"].as_str().unwrap();
    let (_, headers, old) = request(&app, "GET", "offline/versions", token, "", Value::Null).await;
    source.revised.store(true, Ordering::Relaxed);
    let (status, _, next) = request(
        &app,
        "GET",
        "offline/versions",
        token,
        headers["etag"].to_str().unwrap(),
        Value::Null,
    )
    .await;
    assert_eq!(status, 200);
    assert_eq!(
        old["data"]["parts"]["courses"],
        next["data"]["parts"]["courses"]
    );
    assert_ne!(
        old["data"]["parts"]["attendance"],
        next["data"]["parts"]["attendance"]
    );
    assert_eq!(
        request(
            &app,
            "POST",
            "offline/data",
            token,
            "",
            json!({"version":old["data"]["version"],"parts":["attendance"]})
        )
        .await
        .0,
        409
    );
    let packet = request(
        &app,
        "POST",
        "offline/data",
        token,
        "",
        json!({"version":next["data"]["version"],"parts":["attendance"]}),
    )
    .await
    .2;
    assert_eq!(packet["data"]["parts"], json!({"attendance":["present"]}));
}
