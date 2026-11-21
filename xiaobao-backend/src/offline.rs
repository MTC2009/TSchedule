use crate::{
    AppState,
    api::{ApiError, reply},
    auth::Session,
    domain::*,
    grade_sync::GradeCursor,
    provider::demo_slots,
};
use axum::{
    Json,
    extract::{State, rejection::JsonRejection},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::{Deserialize, Serialize};
use serde_json::value::{RawValue, to_raw_value};
use sha2::{Digest, Sha256};
use std::{collections::BTreeMap, sync::Arc};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Part {
    Courses,
    Timetable,
    Events,
    Attendance,
    Tasks,
    Exams,
    Evaluations,
    Resources,
    Grades,
}

/// Construct once per authorized source publication. Checks read only the version index.
pub struct OfflineCatalog {
    subject: String,
    version: String,
    versions: BTreeMap<Part, String>,
    bodies: BTreeMap<Part, Box<RawValue>>,
}

#[derive(Serialize)]
struct Timetable<'a> {
    rotation: &'a Rotation,
    days: Vec<Vec<Period<'a>>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    teaching_slots: Option<&'a [Vec<TeachingSlot>]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    school_calendar: Option<&'a PublishedSchoolCalendar>,
}
#[derive(Serialize)]
struct Period<'a> {
    course_id: &'a str,
    room: Option<&'a str>,
    start: u32,
    end: u32,
}
#[derive(Serialize)]
struct Attendance<'a> {
    coverage: DateRange,
    course_ids: Vec<&'a str>,
    records: &'a [AttendanceRecord],
}

fn digest(subject: &str, label: &[u8], body: &[u8]) -> String {
    let mut hash = Sha256::new();
    for field in [
        b"xiaobao-offline-v1".as_slice(),
        subject.as_bytes(),
        label,
        body,
    ] {
        hash.update((field.len() as u64).to_be_bytes());
        hash.update(field);
    }
    format!("{:x}", hash.finalize())
}

impl OfflineCatalog {
    pub fn new(subject: &str, bodies: BTreeMap<Part, Box<RawValue>>) -> Self {
        let versions: BTreeMap<_, _> = bodies
            .iter()
            .map(|(&part, body)| {
                (
                    part,
                    digest(
                        subject,
                        &serde_json::to_vec(&part).expect("module name"),
                        body.get().as_bytes(),
                    ),
                )
            })
            .collect();
        let version = digest(
            subject,
            b"manifest",
            &serde_json::to_vec(&versions).expect("version index"),
        );
        Self {
            subject: subject.to_owned(),
            version,
            versions,
            bodies,
        }
    }

    pub(crate) fn revision(&self) -> &str {
        &self.version
    }

    pub(crate) fn demo(student: &Student) -> Self {
        let days = (1..=student.rotation.cycle_length())
            .map(|day| {
                demo_slots(&student.courses, day)
                    .map(|(c, slot)| Period {
                        course_id: &c.id,
                        room: c.room.as_deref(),
                        start: slot.start,
                        end: slot.end,
                    })
                    .collect()
            })
            .collect();
        let work = |kind| {
            student
                .work
                .iter()
                // Older clients have no term selector in the offline Work views.
                .filter(|w| {
                    w.kind == kind
                        && w.term
                            .as_deref()
                            .is_none_or(|term| term == student.profile.term)
                })
                .collect::<Vec<_>>()
        };
        fn raw(value: impl Serialize) -> Box<RawValue> {
            to_raw_value(&value).expect("normalized student data")
        }
        Self::new(
            &student.profile.id,
            BTreeMap::from([
                (Part::Courses, raw(&student.courses)),
                (
                    Part::Timetable,
                    raw(Timetable {
                        rotation: &student.rotation,
                        days,
                        teaching_slots: student.teaching_slots.as_deref(),
                        school_calendar: student.rotation.school_calendar(),
                    }),
                ),
                (Part::Events, raw(&student.events)),
                (
                    Part::Attendance,
                    raw(Attendance {
                        coverage: student.attendance_coverage,
                        course_ids: student.courses.iter().map(|c| c.id.as_str()).collect(),
                        records: &student.attendance,
                    }),
                ),
                (Part::Tasks, raw(work(WorkKind::Task))),
                (Part::Exams, raw(work(WorkKind::Exam))),
                (Part::Evaluations, raw(work(WorkKind::Evaluation))),
                (Part::Resources, raw(&student.resources)),
                (
                    Part::Grades,
                    raw(student.grades.changes(&GradeCursor::default())),
                ),
            ]),
        )
    }
}

async fn catalog(state: &AppState, session: &Session) -> Result<Arc<OfflineCatalog>, ApiError> {
    let data = state.provider.offline_catalog(&session.subject).await?;
    if data.subject != session.subject {
        return Err(ApiError::internal());
    }
    Ok(data)
}

#[derive(Serialize)]
struct Bundle<'a, T> {
    version: &'a str,
    parts: T,
}

fn private(mut response: Response) -> Response {
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("private, no-cache"),
    );
    response
        .headers_mut()
        .append(header::VARY, HeaderValue::from_static("Authorization"));
    response
}

pub(crate) async fn versions(
    State(state): State<AppState>,
    session: Session,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    let data = catalog(&state, &session).await?;
    let tag = format!("\"{}\"", data.version);
    let same = headers
        .get_all(header::IF_NONE_MATCH)
        .iter()
        .filter_map(|v| v.to_str().ok())
        .flat_map(|v| v.split(','))
        .map(str::trim)
        .any(|v| v == "*" || v.strip_prefix("W/").unwrap_or(v) == tag);
    let mut response = if same {
        StatusCode::NOT_MODIFIED.into_response()
    } else {
        reply(
            state.provider.source(),
            "ready",
            Bundle {
                version: &data.version,
                parts: &data.versions,
            },
        )
    };
    response.headers_mut().insert(
        header::ETAG,
        HeaderValue::from_str(&format!("W/{tag}")).expect("hex version"),
    );
    Ok(private(response))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Selection {
    version: String,
    parts: Vec<Part>,
}

pub(crate) async fn download(
    State(state): State<AppState>,
    session: Session,
    input: Result<Json<Selection>, JsonRejection>,
) -> Result<Response, ApiError> {
    let request = input?.0;
    let data = catalog(&state, &session).await?;
    if request.version != data.version {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "version_changed",
            "Check the current version and retry",
        ));
    }
    if request.parts.is_empty() {
        return Err(ApiError::bad_request("Select at least one module"));
    }
    let mut parts = BTreeMap::new();
    for id in request.parts {
        let body = data.bodies.get(&id).ok_or_else(ApiError::not_found)?;
        if parts.insert(id, body).is_some() {
            return Err(ApiError::bad_request("Duplicate module"));
        }
    }
    Ok(private(reply(
        state.provider.source(),
        "ready",
        Bundle {
            version: &data.version,
            parts,
        },
    )))
}
