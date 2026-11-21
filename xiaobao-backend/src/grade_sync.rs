use crate::domain::{Course, CourseGrade, Gradebook};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;

#[derive(Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub(crate) struct GradeCursor {
    pub(crate) version: Option<String>,
    #[serde(default)]
    known: HashMap<String, String>,
}

#[derive(Debug, Serialize)]
struct CourseVersion {
    course_id: String,
    name: String,
    revision: String,
}

#[derive(Debug)]
pub struct GradeSnapshot {
    pub(crate) subject: String,
    book: Gradebook,
    roster: Vec<CourseVersion>,
    version: String,
}

#[derive(Serialize)]
pub(crate) struct GradeChanges<'a> {
    version: &'a str,
    term: &'a str,
    published_gpa: Option<f64>,
    courses: &'a [CourseVersion],
    changed: Vec<&'a CourseGrade>,
}

fn digest(value: impl Serialize) -> String {
    let bytes = serde_json::to_vec(&value).expect("serializable grade data");
    format!("{:x}", Sha256::digest(bytes))
}

impl GradeSnapshot {
    /// Build once when the source publishes a new immutable student snapshot.
    pub fn new(subject: &str, book: Gradebook, courses: &[Course]) -> Self {
        let roster: Vec<_> = book
            .courses
            .iter()
            .map(|grade| {
                let id = &grade.course_id;
                let name = courses.iter().find(|c| c.id == *id).map_or(id, |c| &c.name);
                CourseVersion {
                    course_id: id.clone(),
                    name: name.clone(),
                    revision: digest(("grade-v1", subject, &book.term, grade)),
                }
            })
            .collect();
        let version = digest((
            "gradebook-v1",
            subject,
            &book.term,
            book.published_gpa,
            &roster,
        ));
        Self {
            subject: subject.to_owned(),
            book,
            roster,
            version,
        }
    }

    pub fn version(&self) -> &str {
        &self.version
    }

    pub fn book(&self) -> &Gradebook {
        &self.book
    }

    pub(crate) fn changes(&self, cursor: &GradeCursor) -> GradeChanges<'_> {
        let changed = self
            .roster
            .iter()
            .zip(&self.book.courses)
            .filter(|(stamp, _)| cursor.known.get(&stamp.course_id) != Some(&stamp.revision))
            .map(|(_, grade)| grade)
            .collect();
        GradeChanges {
            version: &self.version,
            term: &self.book.term,
            published_gpa: self.book.published_gpa,
            courses: &self.roster,
            changed,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::provider::{DemoProvider, SchoolProvider};
    use chrono::NaiveDate;

    #[tokio::test]
    async fn revisions_follow_published_content_across_restarts_edits_and_term_changes() {
        let date = NaiveDate::from_ymd_opt(2026, 11, 18).unwrap();
        let student = DemoProvider::new(date).student("demo-a").await.unwrap();
        let first = &student.grades;
        let cursor = GradeCursor {
            version: Some(first.version.clone()),
            known: first
                .roster
                .iter()
                .map(|s| (s.course_id.clone(), s.revision.clone()))
                .collect(),
        };
        let next_day = DemoProvider::new(date.succ_opt().unwrap());
        assert!(
            next_day
                .grades_if_changed("demo-a", cursor.version.as_deref())
                .await
                .unwrap()
                .is_none()
        );

        let rebuild = |book| GradeSnapshot::new("demo-a", book, &student.courses);
        let mut book = first.book.clone();
        book.courses[1].assessments[0].feedback = Some("更正".into());
        let changed = rebuild(book);
        assert_ne!(first.version, changed.version);
        assert_eq!(changed.changes(&cursor).changed.len(), 1);
        assert_eq!(
            changed.changes(&cursor).changed[0].course_id,
            first.roster[1].course_id
        );

        let mut book = first.book.clone();
        book.published_gpa = Some(3.8);
        book.courses.pop();
        let changed = rebuild(book);
        assert_ne!(first.version, changed.version);
        assert_eq!(changed.roster.len(), 5);
        assert!(changed.changes(&cursor).changed.is_empty());

        let mut book = first.book.clone();
        book.term = "next-term".into();
        assert_eq!(rebuild(book).changes(&cursor).changed.len(), 6);
    }
}
