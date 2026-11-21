use chrono::{DateTime, Datelike, Days, FixedOffset, NaiveDate, Utc, Weekday};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub fn school_offset() -> FixedOffset {
    FixedOffset::east_opt(8 * 3600).expect("valid Shanghai UTC offset")
}

pub fn school_today() -> NaiveDate {
    Utc::now().with_timezone(&school_offset()).date_naive()
}

#[derive(Clone, Copy, Debug, Serialize)]
pub struct DateRange {
    pub from: NaiveDate,
    pub to: NaiveDate,
}

impl DateRange {
    pub fn new(from: NaiveDate, to: NaiveDate, max_days: i64) -> Result<Self, &'static str> {
        if !(2000..=2100).contains(&from.year()) || !(2000..=2100).contains(&to.year()) {
            return Err("Dates must be between 2000 and 2100");
        }
        if from > to || (to - from).num_days() >= max_days {
            return Err("Invalid date order or range too long");
        }
        Ok(Self { from, to })
    }

    pub fn contains(&self, date: NaiveDate) -> bool {
        self.from <= date && date <= self.to
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct Rotation {
    anchor_date: NaiveDate,
    anchor_day: u8,
    cycle_length: u8,
    closures: Vec<NaiveDate>,
    #[serde(skip)]
    school_calendar: Option<std::sync::Arc<PublishedSchoolCalendar>>,
}

/// A calendar date is not necessarily a day on which this division has class.
#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SchoolCalendarStatus {
    Teaching,
    NoClass,
    Weekend,
    Unpublished,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct SchoolCalendarDay {
    pub date: NaiveDate,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub day: Option<u8>,
    pub status: SchoolCalendarStatus,
    pub notices: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct PublishedSchoolCalendar {
    pub campus: String,
    pub academic_year: String,
    pub division: String,
    pub from: NaiveDate,
    pub through: NaiveDate,
    pub source_sha256: String,
    pub days: Vec<SchoolCalendarDay>,
}

impl PublishedSchoolCalendar {
    pub(crate) fn valid(&self, cycle_length: u8) -> bool {
        let count = (self.through - self.from).num_days() + 1;
        (1..=366).contains(&count)
            && self.days.len() == count as usize
            && self
                .days
                .iter()
                .zip(self.from.iter_days())
                .all(|(row, date)| {
                    row.date == date
                        && row.day.is_none_or(|day| (1..=cycle_length).contains(&day))
                        && match row.status {
                            SchoolCalendarStatus::Teaching => row.day.is_some(),
                            SchoolCalendarStatus::NoClass => true,
                            SchoolCalendarStatus::Weekend | SchoolCalendarStatus::Unpublished => {
                                row.day.is_none()
                            }
                        }
                })
    }

    fn at(&self, date: NaiveDate) -> Option<&SchoolCalendarDay> {
        usize::try_from((date - self.from).num_days())
            .ok()
            .and_then(|index| self.days.get(index))
    }

    fn day(&self, date: NaiveDate) -> SchoolCalendarDay {
        self.at(date).cloned().unwrap_or_else(|| SchoolCalendarDay {
            date,
            day: None,
            status: SchoolCalendarStatus::Unpublished,
            notices: vec![],
        })
    }
}

/* Rotation is the fallback for sources without a dated publication. */
impl Rotation {
    pub fn new(
        anchor_date: NaiveDate,
        anchor_day: u8,
        cycle_length: u8,
        mut closures: Vec<NaiveDate>,
    ) -> Result<Self, &'static str> {
        closures.sort_unstable();
        closures.dedup();
        if cycle_length == 0
            || !(1..=cycle_length).contains(&anchor_day)
            || !weekday(anchor_date)
            || closures.contains(&anchor_date)
        {
            return Err("Invalid school rotation anchor");
        }
        Ok(Self {
            anchor_date,
            anchor_day,
            cycle_length,
            closures,
            school_calendar: None,
        })
    }

    pub(crate) fn cycle_length(&self) -> u8 {
        self.cycle_length
    }

    pub(crate) fn set_school_calendar(
        &mut self,
        calendar: std::sync::Arc<PublishedSchoolCalendar>,
    ) {
        self.school_calendar = Some(calendar);
    }

    pub(crate) fn school_calendar(&self) -> Option<&PublishedSchoolCalendar> {
        self.school_calendar.as_deref()
    }

    pub(crate) fn calendar_day(&self, date: NaiveDate) -> Option<SchoolCalendarDay> {
        self.school_calendar().map(|calendar| calendar.day(date))
    }

    pub fn day(&self, date: NaiveDate) -> Option<u8> {
        if let Some(calendar) = self.school_calendar() {
            return calendar.at(date).and_then(|row| {
                (row.status == SchoolCalendarStatus::Teaching)
                    .then_some(row.day)
                    .flatten()
            });
        }
        if !weekday(date) || self.closures.contains(&date) {
            return None;
        }
        // Weekday index is O(1); only explicitly configured closures are scanned.
        fn index(date: NaiveDate) -> i64 {
            let monday = NaiveDate::from_ymd_opt(1970, 1, 5).expect("valid constant date");
            let days = (date - monday).num_days();
            days.div_euclid(7) * 5 + days.rem_euclid(7).min(5)
        }
        let mut distance = index(date) - index(self.anchor_date);
        for closed in self.closures.iter().filter(|d| weekday(**d)) {
            if self.anchor_date <= *closed && *closed < date {
                distance -= 1;
            }
            if date <= *closed && *closed < self.anchor_date {
                distance += 1;
            }
        }
        Some(
            (i64::from(self.anchor_day - 1) + distance).rem_euclid(i64::from(self.cycle_length))
                as u8
                + 1,
        )
    }
}

pub fn weekday(date: NaiveDate) -> bool {
    !matches!(date.weekday(), Weekday::Sat | Weekday::Sun)
}

#[derive(Clone, Debug, Serialize)]
pub struct Profile {
    pub id: String,
    pub name: String,
    pub reference_date: NaiveDate,
    pub term: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct Course {
    pub id: String,
    pub name: String,
    pub teacher: String,
    pub room: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct Lesson {
    pub id: String,
    pub course_id: String,
    pub start: DateTime<FixedOffset>,
    pub end: DateTime<FixedOffset>,
    pub room: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct Schedule<'a> {
    pub date: NaiveDate,
    pub day: Option<u8>,
    pub lessons: Vec<Lesson>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub teaching_slots: Option<&'a [TeachingSlot]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub calendar_day: Option<SchoolCalendarDay>,
}

/// Published teaching intervals in school-local minutes, not student enrollments.
#[derive(Clone, Copy, Debug, Serialize)]
pub struct TeachingSlot {
    pub start: u32,
    pub end: u32,
}

#[derive(Clone, Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Score {
    Numeric { earned: f64, possible: Option<f64> },
    Letter { value: String },
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum GradingStatus {
    Graded,
    Pending,
    Missing,
    Excused,
}

#[derive(Clone, Debug, Serialize)]
pub struct Assessment {
    pub id: String,
    pub title: String,
    pub date: NaiveDate,
    pub status: GradingStatus,
    pub score: Option<Score>,
    pub feedback: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub weight: Option<f64>,
}

#[derive(Clone, Debug, Serialize)]
pub struct CourseGrade {
    pub course_id: String,
    pub published_score: Option<Score>,
    pub published_gpa: Option<f64>,
    pub assessments: Vec<Assessment>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub class_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub class_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub published_letter_grade: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub first_published_at: Option<DateTime<FixedOffset>>,
}

#[derive(Clone, Debug, Serialize)]
pub struct Gradebook {
    pub term: String,
    pub published_gpa: Option<f64>,
    pub courses: Vec<CourseGrade>,
}

#[derive(Clone, Copy, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum WorkKind {
    Task,
    Exam,
    Evaluation,
}

#[derive(Clone, Copy, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum WorkStatus {
    Pending,
    Submitted,
    Completed,
}

#[derive(Clone, Debug, Serialize)]
pub struct Work {
    pub id: String,
    pub kind: WorkKind,
    pub course_id: Option<String>,
    pub title: String,
    pub due_at: DateTime<FixedOffset>,
    pub status: WorkStatus,
    pub description: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub published_at: Option<DateTime<FixedOffset>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub term: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub work_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub task: Option<TaskDetails>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub exam: Option<ExamDetails>,
}

#[derive(Clone, Debug, Serialize)]
pub struct TaskDetails {
    pub mode: Option<String>,
    pub grading_status: GradingStatus,
    pub score: Option<Score>,
    pub attachments: Vec<AttachmentMetadata>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub opens_at: Option<DateTime<FixedOffset>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub submission: Option<TaskSubmission>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub feedback: Option<TaskFeedback>,
}

#[derive(Clone, Debug, Serialize)]
pub struct TaskSubmission {
    pub submitted_at: Option<DateTime<FixedOffset>>,
    pub text: Option<String>,
    pub attachments: Vec<AttachmentMetadata>,
}

#[derive(Clone, Debug, Serialize)]
pub struct TaskFeedback {
    pub text: Option<String>,
    pub attachments: Vec<AttachmentMetadata>,
}

/// Display-only metadata; this does not confer file access or identify a remote URL.
#[derive(Clone, Debug, Serialize)]
pub struct AttachmentMetadata {
    pub name: String,
    pub size_bytes: Option<u64>,
}

#[derive(Clone, Debug, Serialize)]
pub struct ExamDetails {
    pub start: DateTime<FixedOffset>,
    pub end: DateTime<FixedOffset>,
    pub score: Option<Score>,
    pub results: Vec<ExamResult>,
}

#[derive(Clone, Debug, Serialize)]
pub struct ExamResult {
    pub course_id: String,
    pub score: Option<Score>,
}

#[derive(Clone, Copy, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ResourceScope {
    Shared,
    Personal,
}

#[derive(Clone, Copy, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ResourceKind {
    Document,
    Image,
    Video,
    Audio,
}

#[derive(Clone, Debug, Serialize)]
pub struct Resource {
    pub id: String,
    pub title: String,
    pub scope: ResourceScope,
    pub kind: ResourceKind,
    pub content: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub shared_by: Option<SharingTeacher>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub shared_at: Option<DateTime<FixedOffset>>,
}

#[derive(Clone, Debug, Serialize)]
pub struct SharingTeacher {
    pub id: String,
    pub name: String,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AttendanceCategory {
    #[default]
    Classroom,
    Daily,
    Activity,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AttendanceStatus {
    Present,
    Late,
    Early,
    Absent,
}

#[derive(Clone, Debug, Serialize)]
pub struct AttendanceRecord {
    pub id: String,
    pub course_id: String,
    pub date: NaiveDate,
    pub status: AttendanceStatus,
}

#[derive(Clone, Debug)]
pub struct AttendanceSeries<T> {
    pub coverage: DateRange,
    pub records: Vec<T>,
}

#[derive(Clone, Debug, Serialize)]
pub struct DailyAttendanceRecord {
    pub id: String,
    pub date: NaiveDate,
    pub class_name: String,
    pub status: AttendanceStatus,
    pub leave_status: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct ActivityAttendanceRecord {
    pub id: String,
    pub activity_name: String,
    pub start: DateTime<FixedOffset>,
    pub status: AttendanceStatus,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct AttendanceSummary {
    pub present: u32,
    pub late: u32,
    pub early: u32,
    pub absent: u32,
    pub total: u32,
    pub present_rate: Option<f64>,
}

impl AttendanceSummary {
    pub(crate) fn tally(&mut self, status: AttendanceStatus) {
        match status {
            AttendanceStatus::Present => self.present += 1,
            AttendanceStatus::Late => self.late += 1,
            AttendanceStatus::Early => self.early += 1,
            AttendanceStatus::Absent => self.absent += 1,
        }
        self.total += 1;
    }

    pub(crate) fn with_rate(mut self) -> Self {
        self.present_rate =
            (self.total > 0).then(|| f64::from(self.present) / f64::from(self.total));
        self
    }

    pub fn count<'a>(records: impl Iterator<Item = &'a AttendanceRecord>) -> Self {
        let mut result = Self::default();
        for item in records {
            result.tally(item.status);
        }
        result.with_rate()
    }
}

#[derive(Serialize)]
struct CourseAttendance<'a> {
    course_id: &'a str,
    summary: AttendanceSummary,
}

#[derive(Serialize)]
pub(crate) struct AttendanceReport<'a> {
    range: DateRange,
    coverage: DateRange,
    category: AttendanceCategory,
    totals: AttendanceSummary,
    by_course: Vec<CourseAttendance<'a>>,
    pub records: Vec<&'a AttendanceRecord>,
}

#[derive(Clone, Debug, Serialize)]
pub struct CalendarEvent {
    pub id: String,
    pub title: String,
    pub kind: String,
    pub start: DateTime<FixedOffset>,
    pub end: DateTime<FixedOffset>,
    pub all_day: bool,
}

/// A provider returns one account's normalized data, never a shared global student.
#[derive(Debug)]
pub struct Student {
    pub profile: Profile,
    pub rotation: Rotation,
    /// One slot list per rotation day. None means the source did not publish bell times.
    pub teaching_slots: Option<Vec<Vec<TeachingSlot>>>,
    pub courses: Vec<Course>,
    pub grades: std::sync::Arc<crate::grade_sync::GradeSnapshot>,
    pub grade_history: Vec<Gradebook>,
    pub work: Vec<Work>,
    pub resources: Vec<Resource>,
    pub attendance_coverage: DateRange,
    pub attendance: Vec<AttendanceRecord>,
    pub daily_attendance: Option<AttendanceSeries<DailyAttendanceRecord>>,
    pub activity_attendance: Option<AttendanceSeries<ActivityAttendanceRecord>>,
    pub events: Vec<CalendarEvent>,
}

impl Student {
    pub(crate) fn slots_for_day(&self, day: u8) -> Option<&[TeachingSlot]> {
        let table = self.teaching_slots.as_ref()?;
        if table.len() != usize::from(self.rotation.cycle_length()) {
            return None;
        }
        table
            .get(usize::from(day.checked_sub(1)?))
            .map(Vec::as_slice)
    }

    pub(crate) fn classroom_attendance(
        &self,
        range: DateRange,
        course_id: Option<&str>,
    ) -> AttendanceReport<'_> {
        let matches_course = |id: &str| course_id.is_none_or(|selected| id == selected);
        let mut records = Vec::new();
        let mut totals = AttendanceSummary::default();
        let mut per_course: HashMap<&str, AttendanceSummary> = HashMap::new();
        for record in &self.attendance {
            if range.contains(record.date) && matches_course(&record.course_id) {
                records.push(record);
                totals.tally(record.status);
                per_course
                    .entry(&record.course_id)
                    .or_default()
                    .tally(record.status);
            }
        }
        let by_course = self
            .courses
            .iter()
            .filter(|course| matches_course(&course.id))
            .map(|course| CourseAttendance {
                course_id: &course.id,
                summary: per_course
                    .get(course.id.as_str())
                    .cloned()
                    .unwrap_or_default()
                    .with_rate(),
            })
            .collect();
        AttendanceReport {
            range,
            coverage: self.attendance_coverage,
            category: AttendanceCategory::Classroom,
            totals: totals.with_rate(),
            by_course,
            records,
        }
    }
}

pub fn at(date: NaiveDate, minute: u32) -> DateTime<FixedOffset> {
    date.and_hms_opt(minute / 60, minute % 60, 0)
        .expect("valid internally generated lesson time")
        .and_local_timezone(school_offset())
        .single()
        .expect("fixed offset has no ambiguous times")
}

pub fn monday(date: NaiveDate) -> NaiveDate {
    date - Days::new(u64::from(date.weekday().num_days_from_monday()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn date(day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 11, day).unwrap()
    }

    #[test]
    fn rotation_skips_weekends_and_closures_in_both_directions() {
        let rotation =
            Rotation::new(date(16), 1, 6, vec![date(13), date(17), date(17), date(21)]).unwrap();
        assert_eq!(rotation.day(date(12)), Some(6));
        assert_eq!(rotation.day(date(13)), None);
        assert_eq!(rotation.day(date(16)), Some(1));
        assert_eq!(rotation.day(date(17)), None);
        assert_eq!(rotation.day(date(18)), Some(2));
        assert_eq!(rotation.day(date(21)), None);
        assert_eq!(rotation.day(date(23)), Some(5));
        assert_eq!(rotation.day(date(25)), Some(1));
    }

    #[test]
    fn invalid_rotation_anchors_are_rejected() {
        assert!(Rotation::new(date(16), 0, 6, vec![]).is_err());
        assert!(Rotation::new(date(16), 1, 0, vec![]).is_err());
        assert!(Rotation::new(date(21), 1, 6, vec![]).is_err());
        assert!(Rotation::new(date(16), 1, 6, vec![date(16)]).is_err());
    }

    #[test]
    fn date_range_limits_are_inclusive() {
        assert!(DateRange::new(date(1), date(7), 7).is_ok());
        assert!(DateRange::new(date(1), date(8), 7).is_err());
        assert!(DateRange::new(date(8), date(1), 30).is_err());
        let old = NaiveDate::from_ymd_opt(1999, 12, 31).unwrap();
        assert!(DateRange::new(old, old, 1).is_err());
    }
}
