mod statistics;

use crate::{
    AppState,
    api::{
        ApiError, Page, availability, check_course, exact_filter, optional_date_range, page,
        page_window, reply, search,
    },
    auth::CurrentStudent,
    domain::{Student, Work, WorkKind, WorkStatus, school_offset},
};
use axum::{
    extract::{
        Path, Query, State,
        rejection::{PathRejection, QueryRejection},
    },
    response::Response,
};
use chrono::{DateTime, FixedOffset, NaiveDate};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

#[derive(Serialize)]
struct TaskPage<'a> {
    #[serde(flatten)]
    page: Page<'a, &'a Work>,
    current_term: &'a str,
    available_terms: Vec<&'a str>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct WorkQuery {
    kind: Option<WorkKind>,
    status: Option<WorkStatus>,
    term: Option<String>,
    work_type: Option<String>,
    task_mode: Option<String>,
    course_id: Option<String>,
    from: Option<NaiveDate>,
    to: Option<NaiveDate>,
    q: Option<String>,
    offset: Option<usize>,
    limit: Option<usize>,
}

impl WorkQuery {
    fn matching<'a>(&self, student: &'a Student) -> Result<Vec<&'a Work>, ApiError> {
        let course_id = self.course_id.as_deref();
        check_course(student, course_id)?;
        let current_term = student.profile.term.as_str();
        let term = exact_filter(self.term.as_deref())?.unwrap_or(current_term);
        let work_type = exact_filter(self.work_type.as_deref())?;
        let task_mode = exact_filter(self.task_mode.as_deref())?;
        let text = search(self.q.as_deref())?;
        let range = optional_date_range(self.from, self.to, 366)?;
        Ok(student
            .work
            .iter()
            .filter(|item| {
                item.term.as_deref().unwrap_or(current_term) == term
                    && self.kind.is_none_or(|kind| item.kind == kind)
                    && self.status.is_none_or(|status| item.status == status)
                    && work_type.is_none_or(|kind| item.work_type.as_deref() == Some(kind))
                    && task_mode.is_none_or(|mode| {
                        item.task.as_ref().and_then(|task| task.mode.as_deref()) == Some(mode)
                    })
                    && course_id.is_none_or(|id| {
                        item.course_id.as_deref() == Some(id)
                            || item.exam.as_ref().is_some_and(|exam| {
                                exam.results.iter().any(|result| result.course_id == id)
                            })
                    })
                    && range.is_none_or(|range| {
                        range.contains(work_time(item).with_timezone(&school_offset()).date_naive())
                    })
                    && (text.is_empty() || item.title.to_lowercase().contains(&text))
            })
            .collect())
    }
}

fn work_time(item: &Work) -> DateTime<FixedOffset> {
    item.exam.as_ref().map_or(item.due_at, |exam| exam.start)
}

pub(crate) async fn list(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
    query: Result<Query<WorkQuery>, QueryRejection>,
) -> Result<Response, ApiError> {
    let query = query?.0;
    let mut items = query.matching(&student)?;
    // Keep the legacy list order; statistics are ordered by the date used on the chart.
    items.sort_by_key(|item| (item.due_at, &item.id));
    if query.kind == Some(WorkKind::Task) {
        let current_term = student.profile.term.as_str();
        // Find terms from this student's tasks, not from grades or the filtered page.
        let previous: BTreeSet<_> = student
            .work
            .iter()
            .filter(|item| item.kind == WorkKind::Task)
            .filter_map(|item| item.term.as_deref())
            .filter(|term| *term != current_term && !term.is_empty())
            .collect();
        let result = TaskPage {
            page: page_window(&items, query.offset, query.limit)?,
            current_term,
            available_terms: std::iter::once(current_term)
                .chain(previous.into_iter().rev())
                .collect(),
        };
        return Ok(reply(
            state.provider.source(),
            availability(items.is_empty()),
            result,
        ));
    }
    page(state.provider.source(), &items, query.offset, query.limit)
}

pub(crate) async fn detail(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
    path: Result<Path<String>, PathRejection>,
) -> Result<Response, ApiError> {
    let id = path?.0;
    let item = student
        .work
        .iter()
        .find(|item| item.id == id)
        .ok_or_else(ApiError::not_found)?;
    Ok(reply(state.provider.source(), "ready", item))
}

pub(crate) async fn statistics(
    State(state): State<AppState>,
    CurrentStudent(student): CurrentStudent,
    query: Result<Query<WorkQuery>, QueryRejection>,
) -> Result<Response, ApiError> {
    let query = query?.0;
    if !matches!(query.kind, Some(WorkKind::Task | WorkKind::Exam)) {
        return Err(ApiError::bad_request(
            "Statistics require kind=task or kind=exam",
        ));
    }
    let work = query.matching(&student)?;
    let mut rows = statistics::rows(&work, query.course_id.as_deref());
    rows.sort_by_key(|row| (row.at, row.work_id, row.course_id));
    page(state.provider.source(), &rows, query.offset, query.limit)
}
