use super::{call, login, server};
use axum::http::StatusCode;
use serde_json::json;

#[tokio::test]
async fn grades_filter_published_history_without_inventing_gpa() {
    let router = server();
    let token = login(&router, "demo-a").await;
    let (status, response) = call(
        &router,
        "GET",
        "/api/v1/grades?term=2026-spring&class_type=teaching&q=MATHEMATICS",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let data = &response["data"];
    assert_eq!(data["term"], "2026-spring");
    assert_eq!(
        data["available_terms"],
        json!(["2026-autumn", "2026-spring"])
    );
    assert!(data["published_gpa"].is_null());
    assert_eq!(data["courses"].as_array().unwrap().len(), 1);
    let course = &data["courses"][0];
    assert_eq!(course["class_type"], "teaching");
    assert!(course["class_name"].is_string());
    assert!(course["published_letter_grade"].is_string());
    assert!(
        course["first_published_at"]
            .as_str()
            .unwrap()
            .starts_with("2026-01-01T")
    );
    assert_eq!(course["assessments"][0]["weight"], 0.25);
    assert!(course["published_gpa"].is_null());
}

#[tokio::test]
async fn attendance_categories_use_their_own_records_and_coverage() {
    let server = server();
    let token = login(&server, "demo-b").await;
    let daily = call(
        &server,
        "GET",
        "/api/v1/attendance?category=daily&from=2026-11-17&to=2026-11-18",
        Some(&token),
        None,
    )
    .await
    .1;
    assert_eq!(daily["meta"]["availability"], "ready");
    let data = &daily["data"];
    assert_eq!(data["category"], "daily");
    assert_eq!(data["by_course"], json!([]));
    assert_eq!(data["totals"]["total"], 2);
    assert!(data["records"].as_array().unwrap().iter().all(|r| {
        r["id"].as_str().unwrap().starts_with("demo-b-")
            && r["date"].is_string()
            && r["class_name"].is_string()
            && r.get("leave_status").is_some()
            && r.get("course_id").is_none()
    }));

    let activity = call(
        &server,
        "GET",
        "/api/v1/attendance?category=activity&from=2026-11-18&to=2026-11-20",
        Some(&token),
        None,
    )
    .await
    .1;
    assert_eq!(activity["meta"]["availability"], "partial");
    assert_eq!(activity["data"]["category"], "activity");
    let record = &activity["data"]["records"][0];
    assert!(record["activity_name"].is_string());
    assert!(record["start"].as_str().unwrap().starts_with("2026-11-18T"));
    assert!(record.get("class_name").is_none());
    assert_eq!(activity["data"]["totals"]["total"], 1);

    let empty = call(
        &server,
        "GET",
        "/api/v1/attendance?category=daily&from=2026-11-15&to=2026-11-15",
        Some(&token),
        None,
    )
    .await
    .1;
    assert_eq!(empty["meta"]["availability"], "empty");
    assert!(empty["data"]["totals"]["present_rate"].is_null());
}

#[tokio::test]
async fn task_statistics_use_the_actual_denominator_and_preserve_ungraded_work() {
    let server = server();
    let token = login(&server, "demo-a").await;
    let (code, response) = call(
        &server,
        "GET",
        "/api/v1/work-statistics?kind=task",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(code, StatusCode::OK);
    assert_eq!(response["data"]["total"], 2);
    let rows = response["data"]["items"].as_array().unwrap();
    assert!(rows[0]["score"].is_null());
    assert!(rows[0]["score_rate"].is_null());
    assert_eq!(rows[1]["score"]["possible"], 45.0);
    assert_eq!(rows[1]["score_rate"], 0.8);
}

#[tokio::test]
async fn library_filters_shared_metadata_without_leaking_other_students_items() {
    let server = server();
    let a = login(&server, "demo-a").await;
    let b = login(&server, "demo-b").await;
    let uri = "/api/v1/resources?scope=shared&shared_by_id=demo-a-teacher-0&from=2026-11-16&to=2026-11-16";
    let (status, response) = call(&server, "GET", uri, Some(&a), None).await;
    assert_eq!(status, StatusCode::OK);
    let data = &response["data"];
    assert_eq!(data["total"], 1);
    let item = &data["items"][0];
    assert!(item["shared_by"]["name"].is_string());
    assert!(
        item["shared_at"]
            .as_str()
            .unwrap()
            .starts_with("2026-11-16T")
    );
    assert_eq!(
        item["size_bytes"].as_u64().unwrap() as usize,
        item["content"].as_str().unwrap().len()
    );
    assert_eq!(
        call(&server, "GET", uri, Some(&b), None).await.1["data"]["total"],
        0
    );
    let personal = call(
        &server,
        "GET",
        "/api/v1/resources?scope=personal&content_q=a",
        Some(&a),
        None,
    )
    .await
    .1;
    assert_eq!(personal["data"]["total"], 1);
    assert!(personal["data"]["items"][0].get("shared_by").is_none());
}

#[tokio::test]
async fn the_task_detail_and_evaluation_list_use_account_work() {
    let router = server();
    let a = login(&router, "demo-a").await;
    let list = call(
        &router, "GET",
        "/api/v1/work?kind=task&term=2026-autumn&work_type=reading&task_mode=offline&from=2026-11-20&to=2026-11-20",
        Some(&a), None,
    ).await.1;
    assert_eq!(list["data"]["total"], 1);
    assert_eq!(list["data"]["current_term"], "2026-autumn");
    assert_eq!(
        list["data"]["available_terms"],
        json!(["2026-autumn", "2026-spring"])
    );
    let item = &list["data"]["items"][0];
    assert_eq!(item["title"].as_str(), Some("阅读记录"));
    let detail_path = format!("/api/v1/work/{}", item["id"].as_str().unwrap());
    let detail = call(&router, "GET", &detail_path, Some(&a), None).await.1;
    assert_eq!(detail["data"]["task"]["grading_status"], "graded");
    assert_eq!(detail["data"]["task"]["score"], item["task"]["score"]);
    assert!(detail["data"]["published_at"].is_string());
    assert!(detail["data"]["task"]["opens_at"].is_string());
    assert!(detail["data"]["task"]["submission"]["submitted_at"].is_string());
    assert!(detail["data"]["task"]["feedback"]["text"].is_string());
    assert!(
        detail["data"]["task"]["submission"]["attachments"][0]
            .get("url")
            .is_none()
    );
    assert!(
        detail["data"]["task"]["attachments"][0]
            .get("url")
            .is_none()
    );
    let stats = call(
        &router,
        "GET",
        "/api/v1/work-statistics?kind=task&term=2026-spring",
        Some(&a),
        None,
    )
    .await
    .1;
    assert_eq!(stats["data"]["items"][0]["score"]["type"], "letter");
    assert!(stats["data"]["items"][0]["score_rate"].is_null());
    for status in ["pending", "completed"] {
        let path = format!("/api/v1/work?kind=evaluation&status={status}");
        let evaluations = call(&router, "GET", &path, Some(&a), None).await.1;
        assert_eq!(evaluations["data"]["total"], 1);
        assert_eq!(evaluations["data"]["items"][0]["status"], status);
    }
}

#[tokio::test]
async fn a_historical_exam_has_multiple_subjects_and_course_scoped_statistics() {
    let router = server();
    let a = login(&router, "demo-a").await;
    let b = login(&router, "demo-b").await;
    let query = "term=2026-spring&kind=exam&work_type=checkpoint&from=2026-01-24&to=2026-01-24";
    let path = format!("/api/v1/work?{query}&course_id=demo-a-c1");
    let list = call(&router, "GET", &path, Some(&a), None).await.1;
    assert_eq!(list["data"]["total"], 1);
    let work_id = list["data"]["items"][0]["id"].as_str().unwrap();
    let detail_path = format!("/api/v1/work/{work_id}");
    let detail = call(&router, "GET", &detail_path, Some(&a), None).await.1;
    let exam = &detail["data"]["exam"];
    let subjects = exam["results"].as_array().unwrap();
    assert_eq!(subjects.len(), 2);
    assert_ne!(subjects[0]["course_id"], subjects[1]["course_id"]);
    assert_eq!(
        call(&router, "GET", &detail_path, Some(&b), None).await.0,
        StatusCode::NOT_FOUND
    );

    let stats_path = format!("/api/v1/work-statistics?{query}");
    let stats = call(&router, "GET", &stats_path, Some(&a), None).await.1;
    assert_eq!(stats["data"]["total"], 2);
    let rows = stats["data"]["items"].as_array().unwrap();
    for (row, subject) in rows.iter().zip(subjects) {
        let score = &subject["score"];
        assert_eq!(row["course_id"], subject["course_id"]);
        assert_eq!(row["work_id"], work_id);
        assert_eq!(row["at"], exam["start"]);
        assert_eq!(row["score"], *score);
        let expected = score["earned"].as_f64().unwrap() / score["possible"].as_f64().unwrap();
        assert!((row["score_rate"].as_f64().unwrap() - expected).abs() < 1e-12);
    }
    let path = format!("{stats_path}&course_id=demo-a-c1&limit=1");
    let filtered = call(&router, "GET", &path, Some(&a), None).await.1;
    assert_eq!(filtered["data"]["total"], 1);
    assert_eq!(filtered["data"]["items"][0]["course_id"], "demo-a-c1");
    assert_eq!(
        call(&router, "GET", &path, Some(&b), None).await.0,
        StatusCode::NOT_FOUND
    );
    let current = call(
        &router,
        "GET",
        "/api/v1/work-statistics?kind=exam",
        Some(&a),
        None,
    )
    .await
    .1;
    assert_eq!(current["meta"]["availability"], "empty");
}

#[tokio::test]
async fn portal_queries_reject_invalid_filters_and_non_read_methods() {
    let router = server();
    let session = login(&router, "demo-a").await;
    for path in [
        "/api/v1/work-statistics",
        "/api/v1/work-statistics?kind=evaluation",
        "/api/v1/work-statistics?kind=exam&limit=101",
        "/api/v1/work?kind=task&from=2026-11-01",
        "/api/v1/work?kind=task&term=%20",
        "/api/v1/resources?from=2026-11-02&to=2026-11-01",
    ] {
        let (status, error) = call(&router, "GET", path, Some(&session), None).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{path}");
        assert_eq!(error["error"]["code"], "invalid_request");
    }
    let path = "/api/v1/work-statistics?kind=task";
    assert_eq!(
        call(&router, "GET", path, None, None).await.0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        call(&router, "POST", path, Some(&session), None).await.0,
        StatusCode::METHOD_NOT_ALLOWED
    );
}
