use super::work_time;
use crate::domain::{Score, Work, WorkKind};
use chrono::{DateTime, FixedOffset};
use serde::Serialize;

#[derive(Serialize)]
pub(super) struct Row<'a> {
    pub work_id: &'a str,
    kind: WorkKind,
    term: Option<&'a str>,
    work_type: Option<&'a str>,
    pub course_id: Option<&'a str>,
    title: &'a str,
    pub at: DateTime<FixedOffset>,
    score: Option<&'a Score>,
    score_rate: Option<f64>,
}

fn score_rate(score: Option<&Score>) -> Option<f64> {
    // Never silently convert a letter, an ungraded result, or an invalid denominator to zero.
    match score {
        Some(Score::Numeric {
            earned,
            possible: Some(possible),
        }) if earned.is_finite() && possible.is_finite() && *possible > 0.0 => {
            let rate = earned / possible;
            rate.is_finite().then_some(rate)
        }
        _ => None,
    }
}

pub(super) fn rows<'a>(work: &[&'a Work], course_id: Option<&str>) -> Vec<Row<'a>> {
    let mut rows = Vec::new();
    for &item in work {
        let row = |course_id, score| Row {
            work_id: &item.id,
            kind: item.kind,
            term: item.term.as_deref(),
            work_type: item.work_type.as_deref(),
            course_id,
            title: &item.title,
            at: work_time(item),
            score,
            score_rate: score_rate(score),
        };
        match item.kind {
            WorkKind::Task => rows.push(row(
                item.course_id.as_deref(),
                item.task.as_ref().and_then(|task| task.score.as_ref()),
            )),
            WorkKind::Exam => {
                if let Some(exam) = &item.exam {
                    // Stats are per subject, not the exam's aggregate score.
                    rows.extend(
                        exam.results
                            .iter()
                            .filter(|result| course_id.is_none_or(|id| result.course_id == id))
                            .map(|result| row(Some(&result.course_id), result.score.as_ref())),
                    );
                }
            }
            WorkKind::Evaluation => {}
        }
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_denominators_are_not_zero_scores() {
        for possible in [None, Some(0.0), Some(-9.0), Some(f64::INFINITY)] {
            assert_eq!(
                score_rate(Some(&Score::Numeric {
                    earned: 4.0,
                    possible
                })),
                None
            );
        }
        assert_eq!(
            score_rate(Some(&Score::Numeric {
                earned: 0.0,
                possible: Some(9.0)
            })),
            Some(0.0)
        );
    }
}
