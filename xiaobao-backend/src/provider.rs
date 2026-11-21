mod demo;

use crate::{domain::*, grade_sync::GradeSnapshot};
use async_trait::async_trait;
use chrono::NaiveDate;
use std::{collections::HashMap, sync::Arc};

use self::demo::make_student;

#[derive(Debug)]
pub enum ProviderError {
    NotFound,
    Unavailable,
}

#[async_trait]
pub trait SchoolProvider: Send + Sync {
    async fn offline_catalog(
        &self,
        _subject: &str,
    ) -> Result<Arc<crate::offline::OfflineCatalog>, ProviderError> {
        Err(ProviderError::Unavailable)
    }
    fn source(&self) -> &'static str;
    /// Must change whenever any advertised data, permissions or availability changes.
    /// Sources without a reliable revision use the default and send full responses.
    fn cache_revision(&self, _subject: &str) -> Option<&str> {
        None
    }
    /// Only demo providers expose selectable accounts. Real accounts require verified login.
    fn demo_profiles(&self) -> Vec<Profile> {
        Vec::new()
    }
    async fn student(&self, subject: &str) -> Result<Arc<Student>, ProviderError>;
    /// An upstream adapter can validate its grade revision before reading assessment details.
    async fn grades_if_changed(
        &self,
        subject: &str,
        version: Option<&str>,
    ) -> Result<Option<Arc<GradeSnapshot>>, ProviderError> {
        let student = self.student(subject).await?;
        if student.grades.subject != subject {
            return Err(ProviderError::Unavailable);
        }
        Ok((version != Some(student.grades.version())).then(|| Arc::clone(&student.grades)))
    }

    async fn lessons(&self, subject: &str, range: DateRange) -> Result<Vec<Lesson>, ProviderError>;
}

pub struct DemoProvider {
    students: HashMap<String, Arc<Student>>,
    offline: HashMap<String, Arc<crate::offline::OfflineCatalog>>,
}

impl DemoProvider {
    pub fn new(date: NaiveDate) -> Self {
        Self::build(date, None)
    }

    /// The published dates are real; the enrolled courses and times remain synthetic.
    pub fn with_hs_calendar(date: NaiveDate) -> Result<Self, &'static str> {
        let calendar: PublishedSchoolCalendar =
            serde_json::from_str(include_str!("provider/academic-calendar-hs-2026-2027.json"))
                .map_err(|_| "Could not decode the bundled HS calendar")?;
        if calendar.campus != "main" || calendar.division != "HS" || !calendar.valid(6) {
            return Err("Invalid bundled HS calendar");
        }
        Ok(Self::build(date, Some(Arc::new(calendar))))
    }

    fn build(date: NaiveDate, calendar: Option<Arc<PublishedSchoolCalendar>>) -> Self {
        let students: HashMap<_, _> = [
            make_student("demo-a", "学生 A", date, 0),
            make_student("demo-b", "学生 B", date, 1),
        ]
        .into_iter()
        .map(|mut student| {
            if let Some(calendar) = &calendar {
                student.rotation.set_school_calendar(Arc::clone(calendar));
            }
            (student.profile.id.clone(), Arc::new(student))
        })
        .collect();
        let offline = students
            .iter()
            .map(|(id, student)| {
                (
                    id.clone(),
                    Arc::new(crate::offline::OfflineCatalog::demo(student)),
                )
            })
            .collect();
        Self { students, offline }
    }
}

#[async_trait]
impl SchoolProvider for DemoProvider {
    async fn offline_catalog(
        &self,
        subject: &str,
    ) -> Result<Arc<crate::offline::OfflineCatalog>, ProviderError> {
        self.offline
            .get(subject)
            .cloned()
            .ok_or(ProviderError::NotFound)
    }
    fn cache_revision(&self, subject: &str) -> Option<&str> {
        if self
            .students
            .get(subject)?
            .rotation
            .school_calendar()
            .is_some()
        {
            self.offline.get(subject).map(|catalog| catalog.revision())
        } else {
            Some("demo-portal-v6")
        }
    }
    fn source(&self) -> &'static str {
        "demo"
    }
    fn demo_profiles(&self) -> Vec<Profile> {
        let mut profiles: Vec<_> = self.students.values().map(|s| s.profile.clone()).collect();
        profiles.sort_by(|a, b| a.id.cmp(&b.id));
        profiles
    }
    async fn student(&self, subject: &str) -> Result<Arc<Student>, ProviderError> {
        self.students
            .get(subject)
            .cloned()
            .ok_or(ProviderError::NotFound)
    }
    async fn lessons(&self, subject: &str, range: DateRange) -> Result<Vec<Lesson>, ProviderError> {
        let student = self.student(subject).await?;
        let courses = &student.courses;
        let mut lessons = Vec::new();
        if courses.is_empty() {
            return Ok(lessons);
        }
        for date in range.from.iter_days().take_while(|date| *date <= range.to) {
            let Some(day) = student.rotation.day(date) else {
                continue;
            };
            // Every lesson on this day has the same suffix; format it once.
            let date_label = date.to_string();
            for (course, slot) in demo_slots(courses, day) {
                let start = at(date, slot.start);
                let mut id = String::with_capacity(course.id.len() + 1 + date_label.len());
                id.push_str(&course.id);
                id.push(':');
                id.push_str(&date_label);
                lessons.push(Lesson {
                    id,
                    course_id: course.id.clone(),
                    start,
                    end: at(date, slot.end),
                    room: course.room.clone(),
                });
            }
        }
        Ok(lessons)
    }
}

// Campus bells, not enrollments. The opening double period is one block;
// recess and lunch are deliberately absent from the teaching-slot publication.
const CAMPUS_TEACHING_SLOTS: [TeachingSlot; 7] = [
    TeachingSlot {
        start: 480,
        end: 560,
    },
    TeachingSlot {
        start: 610,
        end: 650,
    },
    TeachingSlot {
        start: 660,
        end: 700,
    },
    TeachingSlot {
        start: 710,
        end: 750,
    },
    TeachingSlot {
        start: 805,
        end: 845,
    },
    TeachingSlot {
        start: 855,
        end: 895,
    },
    TeachingSlot {
        start: 905,
        end: 945,
    },
];

pub(crate) fn demo_slots(
    courses: &[Course],
    day: u8,
) -> impl Iterator<Item = (&Course, TeachingSlot)> {
    let shift = usize::from(day - 1) % courses.len().max(1);
    let (later, earlier) = courses.split_at(courses.len() - shift);
    earlier.iter().chain(later).zip(CAMPUS_TEACHING_SLOTS)
}

#[cfg(test)]
mod teaching_slot_tests {
    use super::*;

    #[test]
    fn a_sparse_roster_does_not_shorten_the_bell_table_or_require_it_to_read_lessons() {
        let date = NaiveDate::from_ymd_opt(2027, 4, 12).unwrap();
        let mut student = make_student("slot-check", "Student", date, 0);
        student.courses.truncate(2);
        assert_eq!(student.slots_for_day(2).unwrap().len(), 7);
        assert_eq!(demo_slots(&student.courses, 2).count(), 2);
        student.teaching_slots = None;
        assert!(student.slots_for_day(2).is_none());
        assert_eq!(demo_slots(&student.courses, 2).count(), 2);
    }
}
