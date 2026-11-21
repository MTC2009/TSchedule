#[path = "api/portal_pages.rs"]
mod portal_pages;

use axum::{
    Router,
    body::{Body, to_bytes},
    http::{Request, StatusCode},
};
use chrono::{Datelike, NaiveDate};
use serde_json::{Value, json};
use std::sync::Arc;
use tower::ServiceExt;
use xiaobao_backend::{AppState, app, provider::DemoProvider};

fn server() -> Router {
    app(AppState::new(Arc::new(DemoProvider::new(
        NaiveDate::from_ymd_opt(2026, 11, 18).unwrap(),
    ))))
}

async fn call(
    server: &Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut request = Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        request = request.header("authorization", format!("bEaReR {token}"));
    }
    let body = if let Some(body) = body {
        request = request.header("content-type", "application/json");
        Body::from(body.to_string())
    } else {
        Body::empty()
    };
    let response = server
        .clone()
        .oneshot(request.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let cached_route = [
        "courses",
        "schedule",
        "calendar",
        "grades",
        "attendance",
        "work",
        "work-statistics",
        "resources",
    ]
    .contains(
        &uri.split('?')
            .next()
            .unwrap()
            .trim_start_matches("/api/v1/")
            .split('/')
            .next()
            .unwrap(),
    );
    if method == "POST" && uri == "/api/v1/grades/sync" && status.is_success() {
        assert_eq!(response.headers()["cache-control"], "private, no-cache");
        assert_eq!(response.headers()["vary"], "Authorization");
    } else if method == "GET" && status == StatusCode::OK && cached_route {
        assert!(
            response.headers()["cache-control"]
                .to_str()
                .unwrap()
                .starts_with("private, max-age=")
        );
        assert!(response.headers().contains_key("etag"));
    } else {
        assert_eq!(response.headers()["cache-control"], "no-store");
    }
    let bytes = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
    let value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).expect("JSON response")
    };
    (status, value)
}

async fn login(server: &Router, profile: &str) -> String {
    let (status, response) = call(
        server,
        "POST",
        "/api/v1/demo/sessions",
        None,
        Some(json!({"profile": profile})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(response["meta"]["source"], "demo");
    assert_eq!(response["data"]["token_type"], "Bearer");
    response["data"]["access_token"].as_str().unwrap().into()
}

#[tokio::test]
async fn sessions_require_valid_bearer_and_can_be_revoked() {
    let server = server();
    assert_eq!(
        call(&server, "GET", "/health", None, None).await.0,
        StatusCode::OK
    );
    for token in [None, Some("invalid"), Some("")] {
        let (status, error) = call(&server, "GET", "/api/v1/me", token, None).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
        assert_eq!(error["error"]["code"], "unauthorized");
    }
    let token = login(&server, "demo-a").await;
    assert_eq!(
        call(&server, "GET", "/api/v1/me", Some(&token), None)
            .await
            .1["data"]["profile"]["id"],
        "demo-a"
    );
    assert_eq!(
        call(&server, "DELETE", "/api/v1/session", Some(&token), None).await,
        (StatusCode::NO_CONTENT, Value::Null)
    );
    assert_eq!(
        call(&server, "GET", "/api/v1/me", Some(&token), None)
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
}

#[tokio::test]
async fn demo_login_rejects_unknown_profiles_fields_and_oversized_bodies() {
    let server = server();
    for (body, expected) in [
        (json!({"profile": "not-a-student"}), StatusCode::NOT_FOUND),
        (
            json!({"profile": "demo-a", "password": "not-accepted"}),
            StatusCode::BAD_REQUEST,
        ),
        (
            json!({"profile": "a".repeat(9000)}),
            StatusCode::PAYLOAD_TOO_LARGE,
        ),
    ] {
        assert_eq!(
            call(&server, "POST", "/api/v1/demo/sessions", None, Some(body))
                .await
                .0,
            expected
        );
    }
}

#[tokio::test]
async fn student_data_and_detail_ids_are_isolated() {
    let server = server();
    let a = login(&server, "demo-a").await;
    let b = login(&server, "demo-b").await;
    assert_ne!(a, b);
    let courses_a = call(&server, "GET", "/api/v1/courses", Some(&a), None)
        .await
        .1;
    let courses_b = call(&server, "GET", "/api/v1/courses", Some(&b), None)
        .await
        .1;
    assert_eq!(courses_a["data"].as_array().unwrap().len(), 6);
    assert_eq!(courses_b["data"].as_array().unwrap().len(), 6);
    for course in courses_b["data"].as_array().unwrap() {
        assert!(course["id"].as_str().unwrap().starts_with("demo-b-"));
    }
    for uri in ["/api/v1/work/demo-a-w0", "/api/v1/resources/demo-a-r0"] {
        assert_eq!(
            call(&server, "GET", uri, Some(&a), None).await.0,
            StatusCode::OK
        );
        assert_eq!(
            call(&server, "GET", uri, Some(&b), None).await.0,
            StatusCode::NOT_FOUND
        );
    }
    assert_eq!(
        call(
            &server,
            "GET",
            "/api/v1/grades?course_id=demo-b-c0",
            Some(&a),
            None
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        call(
            &server,
            "GET",
            "/api/v1/work?student_id=demo-b",
            Some(&a),
            None
        )
        .await
        .0,
        StatusCode::BAD_REQUEST
    );
}

#[tokio::test]
async fn date_filters_reject_invalid_or_excessive_ranges() {
    let server = server();
    let token = login(&server, "demo-a").await;
    for uri in [
        "/api/v1/schedule?date=2026-02-30",
        "/api/v1/schedule?date=1800-01-01",
        "/api/v1/calendar?from=2026-11-18",
        "/api/v1/calendar?from=2026-11-19&to=2026-11-18",
        "/api/v1/calendar?from=2026-01-01&to=2026-02-12",
        "/api/v1/attendance?from=2025-01-01&to=2026-01-02",
        "/api/v1/attendance?category=unknown",
    ] {
        assert_eq!(
            call(&server, "GET", uri, Some(&token), None).await.0,
            StatusCode::BAD_REQUEST,
            "{uri}"
        );
    }
}

#[tokio::test]
async fn calendar_and_schedule_agree_and_weekends_have_no_rotation_day() {
    let server = server();
    let token = login(&server, "demo-a").await;
    let schedule = call(
        &server,
        "GET",
        "/api/v1/schedule?date=2026-11-18",
        Some(&token),
        None,
    )
    .await
    .1;
    let calendar = call(
        &server,
        "GET",
        "/api/v1/calendar?from=2026-11-18&to=2026-11-18",
        Some(&token),
        None,
    )
    .await
    .1;
    assert_eq!(schedule["data"]["lessons"], calendar["data"]["lessons"]);
    let events = calendar["data"]["events"].as_array().unwrap();
    assert!(
        events
            .iter()
            .any(|event| event["kind"] == "school_calendar" && event["all_day"] == true)
    );
    assert!(
        events
            .iter()
            .any(|event| event["kind"] == "activity" && event["all_day"] == false)
    );
    assert_eq!(schedule["data"]["day"], 3);
    let slots: Vec<_> = schedule["data"]["lessons"]
        .as_array()
        .unwrap()
        .iter()
        .map(|lesson| {
            (
                lesson["course_id"].as_str().unwrap(),
                lesson["start"].as_str().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        slots,
        [
            ("demo-a-c4", "2026-11-18T08:00:00+08:00"),
            ("demo-a-c5", "2026-11-18T10:10:00+08:00"),
            ("demo-a-c0", "2026-11-18T11:00:00+08:00"),
            ("demo-a-c1", "2026-11-18T11:50:00+08:00"),
            ("demo-a-c2", "2026-11-18T13:25:00+08:00"),
            ("demo-a-c3", "2026-11-18T14:15:00+08:00"),
        ]
    );
    let weekend = call(
        &server,
        "GET",
        "/api/v1/schedule?date=2026-11-21",
        Some(&token),
        None,
    )
    .await
    .1;
    assert!(weekend["data"]["day"].is_null());
    assert_eq!(weekend["data"]["lessons"], json!([]));
    assert_eq!(weekend["meta"]["availability"], "empty");
}

#[tokio::test]
async fn multiweek_calendar_keeps_lesson_ids_scoped_to_course_and_day() {
    let router = server();
    let token = login(&router, "demo-b").await;
    let (status, body) = call(
        &router,
        "GET",
        "/api/v1/calendar?from=2026-11-19&to=2026-12-30",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let lessons = body["data"]["lessons"].as_array().unwrap();
    assert_eq!(lessons.len(), 180); // Six classes per weekday over six weeks.
    let mut last_start = "";
    for lesson in lessons {
        let course = lesson["course_id"].as_str().unwrap();
        let start = lesson["start"].as_str().unwrap();
        let (day, _) = start.split_once('T').unwrap();
        let weekday = day.parse::<NaiveDate>().unwrap().weekday();
        assert!(weekday.number_from_monday() <= 5);
        assert!(course.starts_with("demo-b-"));
        assert_eq!(lesson["id"], format!("{course}:{day}"));
        assert!(last_start < start);
        last_start = start;
    }
}

#[tokio::test]
async fn grades_preserve_letter_pending_and_unknown_gpa() {
    let server = server();
    let token = login(&server, "demo-a").await;
    let (status, response) = call(
        &server,
        "GET",
        "/api/v1/grades?course_id=demo-a-c0",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(response["data"]["published_gpa"].is_null());
    assert_eq!(response["data"]["courses"].as_array().unwrap().len(), 1);
    let assessments = &response["data"]["courses"][0]["assessments"];
    assert_eq!(assessments[0]["score"]["type"], "numeric");
    assert_eq!(assessments[1]["score"]["type"], "letter");
    assert_eq!(assessments[2]["status"], "pending");
    assert!(assessments[2]["score"].is_null());
    assert_eq!(
        call(
            &server,
            "GET",
            "/api/v1/grades?term=unknown",
            Some(&token),
            None
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
}

#[tokio::test]
async fn attendance_summary_matches_records_and_course_totals() {
    let server = server();
    let token = login(&server, "demo-a").await;
    let response = call(&server, "GET", "/api/v1/attendance", Some(&token), None)
        .await
        .1;
    let data = &response["data"];
    let records = data["records"].as_array().unwrap();
    let totals = &data["totals"];
    let total = totals["total"].as_u64().unwrap();
    assert_eq!(total as usize, records.len());
    let mut sum = 0;
    for status in ["present", "late", "early", "absent"] {
        let count = records.iter().filter(|r| r["status"] == status).count() as u64;
        assert_eq!(totals[status], count);
        sum += count;
    }
    assert_eq!(sum, total);
    let by_course = data["by_course"].as_array().unwrap();
    let courses = call(&server, "GET", "/api/v1/courses", Some(&token), None)
        .await
        .1;
    let courses = courses["data"].as_array().unwrap();
    assert_eq!(by_course.len(), courses.len());
    for (group, course) in by_course.iter().zip(courses) {
        assert_eq!(group["course_id"], course["id"]);
        for status in ["present", "late", "early", "absent"] {
            let count = records
                .iter()
                .filter(|r| r["course_id"] == course["id"] && r["status"] == status)
                .count();
            assert_eq!(group["summary"][status], count);
        }
    }
    assert_eq!(
        data["by_course"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["summary"]["total"].as_u64().unwrap())
            .sum::<u64>(),
        total
    );
    assert_eq!(
        totals["present_rate"].as_f64().unwrap(),
        totals["present"].as_u64().unwrap() as f64 / total as f64
    );
    let filtered = call(
        &server,
        "GET",
        "/api/v1/attendance?course_id=demo-a-c1",
        Some(&token),
        None,
    )
    .await
    .1;
    assert!(
        filtered["data"]["records"]
            .as_array()
            .unwrap()
            .iter()
            .all(|r| r["course_id"] == "demo-a-c1")
    );
}

#[tokio::test]
async fn attendance_distinguishes_empty_partial_and_unavailable() {
    let server = server();
    let token = login(&server, "demo-a").await;
    let empty = call(
        &server,
        "GET",
        "/api/v1/attendance?from=2026-11-14&to=2026-11-15",
        Some(&token),
        None,
    )
    .await
    .1;
    assert_eq!(empty["meta"]["availability"], "empty");
    assert!(empty["data"]["totals"]["present_rate"].is_null());
    assert_eq!(empty["data"]["totals"]["total"], 0);
    let groups = empty["data"]["by_course"].as_array().unwrap();
    assert_eq!(groups.len(), 6);
    assert!(
        groups
            .iter()
            .all(|g| g["summary"]["total"] == 0 && g["summary"]["present_rate"].is_null())
    );
    let partial = call(
        &server,
        "GET",
        "/api/v1/attendance?from=2026-11-17&to=2026-11-20",
        Some(&token),
        None,
    )
    .await
    .1;
    assert_eq!(partial["meta"]["availability"], "partial");
    for uri in [
        "/api/v1/attendance?category=daily&from=2027-01-01&to=2027-01-10",
        "/api/v1/attendance?from=2027-01-01&to=2027-01-10",
    ] {
        let response = call(&server, "GET", uri, Some(&token), None).await.1;
        assert_eq!(response["meta"]["availability"], "unavailable");
        assert!(response["data"].is_null());
    }
}

#[tokio::test]
async fn collections_filter_and_paginate_without_changing_totals() {
    let server = server();
    let token = login(&server, "demo-a").await;
    let page = call(
        &server,
        "GET",
        "/api/v1/work?kind=task&offset=1&limit=1",
        Some(&token),
        None,
    )
    .await
    .1;
    assert_eq!(page["data"]["total"], 2);
    assert_eq!(page["data"]["items"].as_array().unwrap().len(), 1);
    assert_eq!(page["data"]["items"][0]["status"], "submitted");
    let tasks = call(
        &server,
        "GET",
        "/api/v1/work?kind=task&status=pending",
        Some(&token),
        None,
    )
    .await
    .1;
    assert_eq!(tasks["data"]["total"], 1);
    let search = call(
        &server,
        "GET",
        "/api/v1/resources?scope=shared&kind=document&q=MATHEMATICS",
        Some(&token),
        None,
    )
    .await
    .1;
    assert_eq!(search["data"]["total"], 1);
    let tail = call(
        &server,
        "GET",
        "/api/v1/work?offset=999",
        Some(&token),
        None,
    )
    .await
    .1;
    assert_eq!(tail["data"]["items"], json!([]));
    for uri in [
        "/api/v1/work?limit=0",
        "/api/v1/work?limit=101",
        "/api/v1/work?status=typo",
        "/api/v1/resources?kind=unknown",
    ] {
        assert_eq!(
            call(&server, "GET", uri, Some(&token), None).await.0,
            StatusCode::BAD_REQUEST
        );
    }
}

#[tokio::test]
async fn score_projection_is_explicit_validated_and_does_not_modify_grades() {
    let server = server();
    let token = login(&server, "demo-a").await;
    let before = call(&server, "GET", "/api/v1/grades", Some(&token), None)
        .await
        .1["data"]
        .clone();
    let body = json!({"current": 88, "assessment": 95, "weight": 0.3});
    let (status, response) = call(
        &server,
        "POST",
        "/api/v1/grades/project-score",
        Some(&token),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(response["meta"]["source"], "simulation");
    assert!((response["data"]["projected_score"].as_f64().unwrap() - 90.1).abs() < 1e-10);
    for body in [
        json!({"current":88,"assessment":95,"weight":30}),
        json!({"current":101,"assessment":95,"weight":0.3}),
    ] {
        assert_eq!(
            call(
                &server,
                "POST",
                "/api/v1/grades/project-score",
                Some(&token),
                Some(body)
            )
            .await
            .0,
            StatusCode::BAD_REQUEST
        );
    }
    assert_eq!(
        before,
        call(&server, "GET", "/api/v1/grades", Some(&token), None)
            .await
            .1["data"]
    );
}

#[tokio::test]
async fn route_errors_are_json() {
    let server = server();
    let token = login(&server, "demo-a").await;
    for (method, path, status) in [
        ("GET", "/does-not-exist", StatusCode::NOT_FOUND),
        ("POST", "/api/v1/me", StatusCode::METHOD_NOT_ALLOWED),
        ("GET", "/api/v1/work/%FF", StatusCode::BAD_REQUEST),
        ("GET", "/api/v1/resources/%FF", StatusCode::BAD_REQUEST),
    ] {
        let (actual, body) = call(&server, method, path, Some(&token), None).await;
        assert_eq!(actual, status);
        assert!(body["error"]["code"].is_string());
    }
}

#[tokio::test]
async fn grade_sync_sends_only_changed_courses_and_accepts_only_the_sessions_own_version() {
    let router = server();
    let route = "/api/v1/grades/sync";
    let first = login(&router, "demo-a").await;
    let second = login(&router, "demo-b").await;
    let (status, response) = call(&router, "POST", route, Some(&first), Some(json!({}))).await;
    assert_eq!(status, StatusCode::OK);
    let data = &response["data"];
    let full = call(&router, "GET", "/api/v1/grades", Some(&first), None)
        .await
        .1;
    assert_eq!(data["changed"], full["data"]["courses"]);
    let manifest = data["courses"].as_array().unwrap();
    assert_eq!(manifest.len(), 6);
    let known: serde_json::Map<_, _> = manifest
        .iter()
        .map(|c| {
            assert!(!c["name"].as_str().unwrap().is_empty());
            (
                c["course_id"].as_str().unwrap().to_owned(),
                c["revision"].clone(),
            )
        })
        .collect();
    let cursor = json!({"version": data["version"], "known": known});
    assert_eq!(
        call(&router, "POST", route, Some(&first), Some(cursor.clone())).await,
        (StatusCode::NO_CONTENT, Value::Null)
    );
    assert_eq!(
        call(&router, "POST", route, None, Some(cursor.clone()))
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    let other = call(&router, "POST", route, Some(&second), Some(cursor.clone()))
        .await
        .1;
    assert_ne!(other["data"]["version"], data["version"]);
    assert!(
        other["data"]["changed"]
            .as_array()
            .unwrap()
            .iter()
            .all(|c| c["course_id"].as_str().unwrap().starts_with("demo-b-"))
    );
    assert_eq!(other["data"]["changed"].as_array().unwrap().len(), 6);

    let id = manifest[2]["course_id"].as_str().unwrap();
    let mut behind = cursor;
    behind["version"] = json!("older-book");
    behind["known"][id] = json!("older-course");
    let delta = call(&router, "POST", route, Some(&first), Some(behind))
        .await
        .1;
    assert_eq!(delta["data"]["changed"], json!([data["changed"][2]]));
    assert_eq!(data["courses"], delta["data"]["courses"]);
}
