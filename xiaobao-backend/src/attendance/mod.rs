use crate::{
    AppState,
    api::{ApiError, availability, check_course, optional_date_range, reply},
    auth::CurrentStudent,
    domain::{
        AttendanceCategory, AttendanceSeries, AttendanceStatus, AttendanceSummary, DateRange,
        school_offset,
    },
};
use axum::{
    extract::{Query, State, rejection::QueryRejection},
    response::Response,
};
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};

const MAX_RANGE_DAYS: i64 = 366;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct AttendanceQuery {
    from: Option<NaiveDate>,
    to: Option<NaiveDate>,
    #[serde(default)]
    category: AttendanceCategory,
    course_id: Option<String>,
}

#[derive(Serialize)]
struct CategoryReport<'a, T> {
    range: DateRange,
    coverage: DateRange,
    category: AttendanceCategory,
    totals: AttendanceSummary,
    by_course: [(); 0],
    records: Vec<&'a T>,
}

fn with_coverage<T: Serialize>(
    source: &'static str,
    range: Option<DateRange>,
    coverage: DateRange,
    build: impl FnOnce(DateRange) -> (T, bool),
) -> Result<Response, ApiError> {
    let range = match range {
        Some(range) => range,
        None => DateRange::new(coverage.from, coverage.to, MAX_RANGE_DAYS)
            .map_err(ApiError::bad_request)?,
    };
    if range.to < coverage.from || range.from > coverage.to {
        return Ok(reply(source, "unavailable", ()));
    }
    let (report, empty) = build(range);
    let status = if range.from < coverage.from || range.to > coverage.to {
        "partial"
    } else {
        availability(empty)
    };
    Ok(reply(source, status, report))
}

fn other_category<T: Serialize>(
    source: &'static str,
    range: Option<DateRange>,
    category: AttendanceCategory,
    series: Option<&AttendanceSeries<T>>,
    fields: impl Fn(&T) -> (NaiveDate, AttendanceStatus),
) -> Result<Response, ApiError> {
    let Some(series) = series else {
        return Ok(reply(source, "unavailable", ()));
    };
    with_coverage(source, range, series.coverage, |range| {
        let mut totals = AttendanceSummary::default();
        let mut records = Vec::new();
        for row in &series.records {
            let (date, status) = fields(row);
            if range.contains(date) && series.coverage.contains(date) {
                totals.tally(status);
                records.push(row);
            }
        }
        let empty = records.is_empty();
        (
            CategoryReport {
                range,
                coverage: series.coverage,
                category,
                totals: totals.with_rate(),
                // Daily and activity records do not belong to a course.
                by_course: [],
                records,
            },
            empty,
        )
    })
}

pub(crate) async fn read(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
    query: Result<Query<AttendanceQuery>, QueryRejection>,
) -> Result<Response, ApiError> {
    let query = query?.0;
    let course = query.course_id.as_deref();
    check_course(&student, course)?;
    let range = optional_date_range(query.from, query.to, MAX_RANGE_DAYS)?;
    let source = state.provider.source();
    if query.category != AttendanceCategory::Classroom && course.is_some() {
        // Keep the existing response for a class filter on a non-classroom category.
        return Ok(reply(source, "unavailable", ()));
    }
    match query.category {
        AttendanceCategory::Classroom => {
            with_coverage(source, range, student.attendance_coverage, |range| {
                let report = student.classroom_attendance(range, course);
                let empty = report.records.is_empty();
                (report, empty)
            })
        }
        AttendanceCategory::Daily => other_category(
            source,
            range,
            query.category,
            student.daily_attendance.as_ref(),
            |record| (record.date, record.status),
        ),
        AttendanceCategory::Activity => other_category(
            source,
            range,
            query.category,
            student.activity_attendance.as_ref(),
            |record| {
                (
                    record.start.with_timezone(&school_offset()).date_naive(),
                    record.status,
                )
            },
        ),
    }
}
