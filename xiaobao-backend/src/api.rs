use crate::{
    AppState,
    auth::{CurrentStudent, Session},
    domain::*,
    grade_sync::GradeCursor,
    provider::ProviderError,
};
use axum::{
    Json,
    extract::{
        Path, Query, State,
        rejection::{JsonRejection, PathRejection, QueryRejection},
    },
    http::{HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Days, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Debug)]
pub(crate) struct ApiError {
    status: StatusCode,
    code: &'static str,
    message: String,
}

impl ApiError {
    pub fn new(status: StatusCode, code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status,
            code,
            message: message.into(),
        }
    }
    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, "invalid_request", message)
    }
    pub fn unauthorized() -> Self {
        Self::new(
            StatusCode::UNAUTHORIZED,
            "unauthorized",
            "A valid bearer session is required",
        )
    }
    pub fn not_found() -> Self {
        Self::new(StatusCode::NOT_FOUND, "not_found", "Record not found")
    }
    pub fn internal() -> Self {
        Self::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "internal_error",
            "Internal server error",
        )
    }
    pub fn capacity() -> Self {
        Self::new(
            StatusCode::TOO_MANY_REQUESTS,
            "session_capacity",
            "Demo session limit reached; sign out or wait for expiry",
        )
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (
            self.status,
            Json(json!({"error": {"code": self.code, "message": self.message}})),
        )
            .into_response()
    }
}

impl From<ProviderError> for ApiError {
    fn from(error: ProviderError) -> Self {
        match error {
            ProviderError::NotFound => Self::not_found(),
            ProviderError::Unavailable => Self::new(
                StatusCode::SERVICE_UNAVAILABLE,
                "source_unavailable",
                "School data is currently unavailable",
            ),
        }
    }
}

impl From<QueryRejection> for ApiError {
    fn from(error: QueryRejection) -> Self {
        Self::bad_request(error.body_text())
    }
}

impl From<PathRejection> for ApiError {
    fn from(error: PathRejection) -> Self {
        Self::bad_request(error.body_text())
    }
}

impl From<JsonRejection> for ApiError {
    fn from(error: JsonRejection) -> Self {
        let status = match error.status() {
            StatusCode::UNPROCESSABLE_ENTITY => StatusCode::BAD_REQUEST,
            other => other,
        };
        Self::new(status, "invalid_body", error.body_text())
    }
}

#[derive(Serialize)]
struct Metadata {
    source: &'static str,
    availability: &'static str,
    timezone: &'static str,
    generated_at: DateTime<Utc>,
}

#[derive(Serialize)]
struct Envelope<T> {
    meta: Metadata,
    data: T,
}

pub(crate) fn reply(
    source: &'static str,
    availability: &'static str,
    data: impl Serialize,
) -> Response {
    Json(Envelope {
        meta: Metadata {
            source,
            availability,
            timezone: "Asia/Shanghai",
            generated_at: Utc::now(),
        },
        data,
    })
    .into_response()
}

pub(crate) fn availability(empty: bool) -> &'static str {
    if empty { "empty" } else { "ready" }
}

pub(crate) fn check_course(student: &Student, course: Option<&str>) -> Result<(), ApiError> {
    if course.is_some_and(|id| !student.courses.iter().any(|course| course.id == id)) {
        return Err(ApiError::not_found());
    }
    Ok(())
}

pub(crate) async fn profiles(State(state): State<AppState>) -> Response {
    let profiles = state.provider.demo_profiles();
    reply(
        state.provider.source(),
        availability(profiles.is_empty()),
        profiles,
    )
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Login {
    profile: String,
    #[serde(default)]
    remember: bool,
}

pub(crate) async fn create_session(
    State(state): State<AppState>,
    body: Result<Json<Login>, JsonRejection>,
) -> Result<(StatusCode, Response), ApiError> {
    let login = body?.0;
    let profiles = state.provider.demo_profiles();
    if profiles.is_empty() {
        return Err(ApiError::new(
            StatusCode::NOT_IMPLEMENTED,
            "demo_disabled",
            "This data source does not support demo sessions",
        ));
    }
    if !profiles.iter().any(|profile| profile.id == login.profile) {
        return Err(ApiError::not_found());
    }
    let response = if login.remember {
        reply(
            state.provider.source(),
            "ready",
            state.devices.issue(login.profile).await?,
        )
    } else {
        reply(
            state.provider.source(),
            "ready",
            state.sessions.issue(login.profile)?,
        )
    };
    Ok((StatusCode::CREATED, response))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Refresh {
    refresh_token: String,
}

pub(crate) async fn refresh_session(
    State(state): State<AppState>,
    body: Result<Json<Refresh>, JsonRejection>,
) -> Result<Response, ApiError> {
    let pair = state.devices.refresh(body?.0.refresh_token).await?;
    Ok(reply(state.provider.source(), "ready", pair))
}

pub(crate) async fn logout(
    State(state): State<AppState>,
    headers: axum::http::HeaderMap,
) -> Result<StatusCode, ApiError> {
    let token = crate::auth::bearer(&headers)?;
    if token.starts_with("xa_") || token.starts_with("xr_") {
        state.devices.revoke(token).await?;
    } else {
        state.sessions.revoke(token)?;
    }
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn me(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
) -> Response {
    reply(
        state.provider.source(),
        "ready",
        json!({"profile": student.profile, "rotation": student.rotation}),
    )
}

pub(crate) async fn courses(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
) -> Response {
    reply(
        state.provider.source(),
        availability(student.courses.is_empty()),
        &student.courses,
    )
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct ScheduleQuery {
    date: Option<NaiveDate>,
}

pub(crate) async fn schedule(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
    query: Result<Query<ScheduleQuery>, QueryRejection>,
) -> Result<Response, ApiError> {
    let date = query?.date.unwrap_or_else(school_today);
    let range = DateRange::new(date, date, 1).map_err(ApiError::bad_request)?;
    let lessons = state.provider.lessons(&student.profile.id, range).await?;
    let day = student.rotation.day(date);
    Ok(reply(
        state.provider.source(),
        availability(lessons.is_empty()),
        Schedule {
            date,
            day,
            lessons,
            teaching_slots: day.and_then(|d| student.slots_for_day(d)),
            calendar_day: student.rotation.calendar_day(date),
        },
    ))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RangeQuery {
    from: Option<NaiveDate>,
    to: Option<NaiveDate>,
}

fn date_range(
    from: Option<NaiveDate>,
    to: Option<NaiveDate>,
    default: DateRange,
    max: i64,
) -> Result<DateRange, ApiError> {
    optional_date_range(from, to, max)?.map_or_else(
        || DateRange::new(default.from, default.to, max).map_err(ApiError::bad_request),
        Ok,
    )
}

pub(crate) fn optional_date_range(
    from: Option<NaiveDate>,
    to: Option<NaiveDate>,
    max: i64,
) -> Result<Option<DateRange>, ApiError> {
    match (from, to) {
        (Some(from), Some(to)) => DateRange::new(from, to, max)
            .map(Some)
            .map_err(ApiError::bad_request),
        (None, None) => Ok(None),
        _ => Err(ApiError::bad_request("Supply both from and to, or neither")),
    }
}

#[derive(Serialize)]
struct Calendar<'a> {
    range: DateRange,
    lessons: Vec<Lesson>,
    events: Vec<&'a CalendarEvent>,
    deadlines: Vec<&'a Work>,
}

pub(crate) async fn calendar(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
    query: Result<Query<RangeQuery>, QueryRejection>,
) -> Result<Response, ApiError> {
    let query = query?.0;
    let from = monday(school_today());
    let range = date_range(
        query.from,
        query.to,
        DateRange {
            from,
            to: from + Days::new(6),
        },
        42,
    )?;
    let lessons = state.provider.lessons(&student.profile.id, range).await?;
    let events: Vec<_> = student
        .events
        .iter()
        .filter(|event| {
            event.start.date_naive() <= range.to
                && (event.end > at(range.from, 0) || range.contains(event.start.date_naive()))
        })
        .collect();
    let deadlines: Vec<_> = student
        .work
        .iter()
        .filter(|work| range.contains(work.due_at.date_naive()))
        .collect();
    Ok(reply(
        state.provider.source(),
        availability(lessons.is_empty() && events.is_empty() && deadlines.is_empty()),
        Calendar {
            range,
            lessons,
            events,
            deadlines,
        },
    ))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct GradeQuery {
    term: Option<String>,
    course_id: Option<String>,
    class_type: Option<String>,
    q: Option<String>,
}

#[derive(Serialize)]
struct GradeSelection<'a> {
    term: &'a str,
    available_terms: Vec<&'a str>,
    published_gpa: Option<f64>,
    courses: Vec<&'a CourseGrade>,
}

pub(crate) async fn grades(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
    query: Result<Query<GradeQuery>, QueryRejection>,
) -> Result<Response, ApiError> {
    let query = query?.0;
    let current = student.grades.book();
    let terms = std::iter::once(current).chain(&student.grade_history);
    let selected = query.term.as_deref().unwrap_or(&current.term);
    let book = terms
        .clone()
        .find(|book| book.term == selected)
        .ok_or_else(ApiError::not_found)?;
    let course_id = query.course_id.as_deref();
    check_course(&student, course_id)?;
    let class_type = exact_filter(query.class_type.as_deref())?;
    let text = search(query.q.as_deref())?;
    let courses: Vec<_> = book
        .courses
        .iter()
        .filter(|grade| {
            course_id.is_none_or(|id| id == grade.course_id)
                && class_type.is_none_or(|kind| grade.class_type.as_deref() == Some(kind))
                && (text.is_empty()
                    || student.courses.iter().any(|course| {
                        course.id == grade.course_id && course.name.to_lowercase().contains(&text)
                    }))
        })
        .collect();
    Ok(reply(
        state.provider.source(),
        availability(courses.is_empty()),
        GradeSelection {
            term: &book.term,
            available_terms: terms.map(|book| book.term.as_str()).collect(),
            published_gpa: book.published_gpa,
            courses,
        },
    ))
}

pub(crate) async fn sync_grades(
    State(state): State<AppState>,
    session: Session,
    body: Result<Json<GradeCursor>, JsonRejection>,
) -> Result<Response, ApiError> {
    let cursor = body?.0;
    let snapshot = state
        .provider
        .grades_if_changed(&session.subject, cursor.version.as_deref())
        .await?;
    let mut response = match snapshot {
        None => StatusCode::NO_CONTENT.into_response(),
        Some(book) => {
            if book.subject != session.subject {
                return Err(ApiError::internal());
            }
            reply(
                state.provider.source(),
                availability(book.book().courses.is_empty()),
                book.changes(&cursor),
            )
        }
    };
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("private, no-cache"),
    );
    response
        .headers_mut()
        .insert(header::VARY, HeaderValue::from_static("Authorization"));
    Ok(response)
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Projection {
    current: f64,
    assessment: f64,
    weight: f64,
}

pub(crate) async fn project_score(
    _session: Session,
    body: Result<Json<Projection>, JsonRejection>,
) -> Result<Response, ApiError> {
    let input = body?.0;
    if ![input.current, input.assessment]
        .iter()
        .all(|score| score.is_finite() && (0.0..=100.0).contains(score))
        || !input.weight.is_finite()
        || !(0.0..=1.0).contains(&input.weight)
    {
        return Err(ApiError::bad_request(
            "Scores must be 0–100 and weight must be 0–1",
        ));
    }
    Ok(reply(
        "simulation",
        "ready",
        json!({
            "projected_score": input.current * (1.0 - input.weight) + input.assessment * input.weight,
            "assumption": "current represents all other work; assessment has the supplied fraction of the final score",
        }),
    ))
}

pub(crate) fn search(query: Option<&str>) -> Result<String, ApiError> {
    let query = query.unwrap_or_default();
    if query.chars().count() > 200 {
        return Err(ApiError::bad_request("Search is limited to 200 characters"));
    }
    Ok(query.trim().to_lowercase())
}

pub(crate) fn exact_filter(input: Option<&str>) -> Result<Option<&str>, ApiError> {
    input
        .map(|value| {
            let value = value.trim();
            if value.is_empty() || value.chars().count() > 200 {
                return Err(ApiError::bad_request("Filter must be 1–200 characters"));
            }
            Ok(value)
        })
        .transpose()
}

#[derive(Serialize)]
pub(crate) struct Page<'a, T> {
    items: &'a [T],
    total: usize,
    offset: usize,
    limit: usize,
}

pub(crate) fn page<T: Serialize>(
    source: &'static str,
    items: &[T],
    offset: Option<usize>,
    limit: Option<usize>,
) -> Result<Response, ApiError> {
    Ok(reply(
        source,
        availability(items.is_empty()),
        page_window(items, offset, limit)?,
    ))
}

/// The same window is used when a collection adds metadata to the standard page.
pub(crate) fn page_window<T>(
    items: &[T],
    offset: Option<usize>,
    limit: Option<usize>,
) -> Result<Page<'_, T>, ApiError> {
    let offset = offset.unwrap_or(0);
    let limit = limit.unwrap_or(30);
    if !(1..=100).contains(&limit) {
        return Err(ApiError::bad_request("Limit must be 1–100"));
    }
    let start = offset.min(items.len());
    let end = start + limit.min(items.len() - start);
    Ok(Page {
        items: &items[start..end],
        total: items.len(),
        offset,
        limit,
    })
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct ResourceQuery {
    scope: Option<ResourceScope>,
    kind: Option<ResourceKind>,
    q: Option<String>,
    content_q: Option<String>,
    shared_by_id: Option<String>,
    from: Option<NaiveDate>,
    to: Option<NaiveDate>,
    offset: Option<usize>,
    limit: Option<usize>,
}

pub(crate) async fn resources(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
    query: Result<Query<ResourceQuery>, QueryRejection>,
) -> Result<Response, ApiError> {
    let query = query?.0;
    let text = search(query.q.as_deref())?;
    let content = search(query.content_q.as_deref())?;
    let shared_by_id = exact_filter(query.shared_by_id.as_deref())?;
    let range = optional_date_range(query.from, query.to, 366)?;
    let mut items: Vec<_> = student
        .resources
        .iter()
        .filter(|item| {
            query.scope.is_none_or(|scope| item.scope == scope)
                && query.kind.is_none_or(|kind| item.kind == kind)
                && (text.is_empty() || item.title.to_lowercase().contains(&text))
                && (content.is_empty() || item.content.to_lowercase().contains(&content))
                && shared_by_id.is_none_or(|id| {
                    item.shared_by
                        .as_ref()
                        .is_some_and(|teacher| teacher.id == id)
                })
                && range.is_none_or(|range| {
                    item.shared_at.is_some_and(|at| {
                        range.contains(at.with_timezone(&school_offset()).date_naive())
                    })
                })
        })
        .collect();
    items.sort_by(|a, b| a.id.cmp(&b.id));
    page(state.provider.source(), &items, query.offset, query.limit)
}

pub(crate) async fn resource_detail(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
    path: Result<Path<String>, PathRejection>,
) -> Result<Response, ApiError> {
    let id = path?.0;
    let item = student
        .resources
        .iter()
        .find(|item| item.id == id)
        .ok_or_else(ApiError::not_found)?;
    Ok(reply(state.provider.source(), "ready", item))
}
