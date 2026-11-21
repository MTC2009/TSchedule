use crate::{domain::*, grade_sync::GradeSnapshot};
use chrono::{Datelike, Days, NaiveDate, Weekday};
use std::sync::Arc;

fn term_id(date: NaiveDate) -> String {
    format!(
        "{}-{}",
        date.year(),
        if date.month() >= 8 {
            "autumn"
        } else {
            "spring"
        }
    )
}

fn term_start(date: NaiveDate) -> NaiveDate {
    NaiveDate::from_ymd_opt(date.year(), if date.month() >= 8 { 8 } else { 1 }, 1)
        .expect("valid term start")
}

fn previous_term_start(date: NaiveDate) -> NaiveDate {
    let (year, month) = if date.month() >= 8 {
        (date.year(), 1)
    } else {
        (date.year() - 1, 8)
    };
    NaiveDate::from_ymd_opt(year, month, 1).expect("valid previous term start")
}

fn demo_work(profile: &Profile, courses: &[Course], variant: usize) -> Vec<Work> {
    let date = profile.reference_date;
    let previous_start = previous_term_start(date);
    let previous = term_id(previous_start);
    let make = |key: &str, kind, title: &str, due_at, course_index: Option<usize>| Work {
        id: format!("{}-{key}", profile.id),
        kind,
        title: title.into(),
        course_id: course_index.map(|i| courses[i].id.clone()),
        due_at,
        status: WorkStatus::Pending,
        description: match kind {
            WorkKind::Task => "完成后请核对提交内容。",
            WorkKind::Exam => "请提前确认考试时间与考场。",
            WorkKind::Evaluation => "回顾学习过程，整理收获与待改进之处。",
        }
        .into(),
        published_at: None,
        term: Some(profile.term.clone()),
        work_type: None,
        task: None,
        exam: None,
    };
    let deadline = |days| at(date + Days::new(days), 18 * 60);
    let exam_day = previous_start + Days::new(23);
    let past_exam_end = at(exam_day, 11 * 60);
    let earned = 36.0 + variant as f64;
    let subject_one = 19.0 + variant as f64;
    let subject_two = 33.0 + variant as f64;
    vec![
        Work {
            published_at: date
                .checked_sub_days(Days::new(2))
                .map(|day| at(day, 9 * 60)),
            work_type: Some("practice".into()),
            task: Some(TaskDetails {
                mode: Some("online".into()),
                grading_status: GradingStatus::Pending,
                score: None,
                attachments: vec![],
                opens_at: date
                    .checked_sub_days(Days::new(1))
                    .map(|day| at(day, 8 * 60)),
                submission: None,
                feedback: None,
            }),
            ..make("w0", WorkKind::Task, "单元练习", deadline(1), Some(0))
        },
        Work {
            status: WorkStatus::Submitted,
            published_at: date
                .checked_sub_days(Days::new(5))
                .map(|day| at(day, 10 * 60)),
            work_type: Some("reading".into()),
            task: Some(TaskDetails {
                mode: Some("offline".into()),
                grading_status: GradingStatus::Graded,
                score: Some(Score::Numeric {
                    earned,
                    possible: Some(45.0),
                }),
                attachments: vec![AttachmentMetadata {
                    name: "阅读材料.txt".into(),
                    size_bytes: None,
                }],
                opens_at: date
                    .checked_sub_days(Days::new(3))
                    .map(|day| at(day, 9 * 60)),
                submission: Some(TaskSubmission {
                    submitted_at: Some(at(date, 14 * 60)),
                    text: Some(
                        "我先标出段落的主张，再把两条例证和它们各自支持的理由写在一起。".into(),
                    ),
                    attachments: vec![AttachmentMetadata {
                        name: "段落标注.txt".into(),
                        size_bytes: Some(1536),
                    }],
                }),
                feedback: Some(TaskFeedback {
                    text: Some(
                        "论点和例证区分得很清楚。下次可以补一句，交代第二条例证为什么更有说服力。"
                            .into(),
                    ),
                    attachments: vec![],
                }),
            }),
            ..make("w1", WorkKind::Task, "阅读记录", deadline(2), Some(1))
        },
        Work {
            work_type: Some("checkpoint".into()),
            exam: Some(ExamDetails {
                start: at(date + Days::new(3), 17 * 60),
                end: deadline(3),
                score: None,
                results: vec![],
            }),
            ..make("w2", WorkKind::Exam, "阶段考试", deadline(3), Some(2))
        },
        make("w3", WorkKind::Evaluation, "学习反思", deadline(4), Some(3)),
        Work {
            status: WorkStatus::Completed,
            ..make(
                "evaluation-complete",
                WorkKind::Evaluation,
                "读书分享回顾",
                at(date, 16 * 60),
                None,
            )
        },
        Work {
            status: WorkStatus::Completed,
            term: Some(previous.clone()),
            published_at: Some(at(previous_start + Days::new(4), 9 * 60)),
            work_type: Some("reflection".into()),
            task: Some(TaskDetails {
                mode: Some("online".into()),
                grading_status: GradingStatus::Graded,
                score: Some(Score::Letter { value: "B".into() }),
                attachments: vec![],
                opens_at: None,
                submission: None,
                feedback: Some(TaskFeedback {
                    text: Some("下一次请把观察到的事实与自己的判断分别记录。".into()),
                    attachments: vec![],
                }),
            }),
            ..make(
                "past-task",
                WorkKind::Task,
                "图书展回顾",
                at(previous_start + Days::new(16), 15 * 60),
                Some(0),
            )
        },
        Work {
            status: WorkStatus::Completed,
            term: Some(previous),
            work_type: Some("checkpoint".into()),
            exam: Some(ExamDetails {
                start: at(exam_day, 9 * 60),
                end: past_exam_end,
                score: Some(Score::Numeric {
                    earned: subject_one + subject_two,
                    possible: Some(72.0),
                }),
                results: vec![
                    ExamResult {
                        course_id: courses[0].id.clone(),
                        score: Some(Score::Numeric {
                            earned: subject_one,
                            possible: Some(28.0),
                        }),
                    },
                    ExamResult {
                        course_id: courses[1].id.clone(),
                        score: Some(Score::Numeric {
                            earned: subject_two,
                            possible: Some(44.0),
                        }),
                    },
                ],
            }),
            ..make(
                "past-exam",
                WorkKind::Exam,
                "综合学科回顾",
                past_exam_end,
                None,
            )
        },
    ]
}

fn demo_daily(
    id: &str,
    coverage: DateRange,
    variant: usize,
) -> AttendanceSeries<DailyAttendanceRecord> {
    let records = coverage
        .from
        .iter_days()
        .take_while(|day| *day <= coverage.to)
        .filter(|day| weekday(*day))
        .map(|date| {
            let (status, leave_status) = match (date.ordinal() as usize + variant) % 17 {
                0 => (AttendanceStatus::Absent, Some("approved".into())),
                1 => (AttendanceStatus::Late, None),
                _ => (AttendanceStatus::Present, None),
            };
            DailyAttendanceRecord {
                id: format!("{id}-daily:{date}"),
                date,
                class_name: format!("{} 班", variant + 1),
                status,
                leave_status,
            }
        })
        .collect();
    AttendanceSeries { coverage, records }
}

fn demo_activity(
    id: &str,
    coverage: DateRange,
    variant: usize,
) -> AttendanceSeries<ActivityAttendanceRecord> {
    let records = coverage
        .from
        .iter_days()
        .take_while(|day| *day <= coverage.to)
        .filter(|day| day.weekday() == Weekday::Wed)
        .map(|date| ActivityAttendanceRecord {
            id: format!("{id}-activity:{date}"),
            activity_name: ["阅读交流会", "创客工坊"][variant].into(),
            start: at(date, 16 * 60 + 15),
            status: match (date.day() as usize + variant) % 3 {
                0 => AttendanceStatus::Early,
                _ => AttendanceStatus::Present,
            },
        })
        .collect();
    AttendanceSeries { coverage, records }
}

fn demo_grades(courses: &[Course], term_start: NaiveDate, variant: usize) -> Gradebook {
    // Published fixture dates stay stable across service restarts within a term.
    let courses = courses
        .iter()
        .enumerate()
        .map(|(i, course)| {
            let score = 84.0 + ((i * 3 + variant * 5) % 15) as f64;
            let (class_type, class_name) = if i % 2 == 0 {
                ("teaching", "教学班")
            } else {
                ("administrative", "行政班")
            };
            CourseGrade {
                course_id: course.id.clone(),
                published_score: Some(Score::Numeric {
                    earned: score,
                    possible: Some(100.0),
                }),
                published_gpa: None, // No verified school GPA policy: do not invent a conversion.
                class_type: Some(class_type.into()),
                class_name: Some(format!("{class_name} {}", i + 1)),
                published_letter_grade: Some(if score >= 90.0 { "A" } else { "B" }.into()),
                first_published_at: Some(at(term_start, 10 * 60)),
                assessments: vec![
                    Assessment {
                        id: format!("{}-a1", course.id),
                        title: "单元测验".into(),
                        date: term_start,
                        status: GradingStatus::Graded,
                        score: Some(Score::Numeric {
                            earned: score / 5.0,
                            possible: Some(20.0),
                        }),
                        feedback: Some("请核对最后一题的解题步骤。".into()),
                        weight: Some(0.25),
                    },
                    Assessment {
                        id: format!("{}-a2", course.id),
                        title: "课堂表现".into(),
                        date: term_start + Days::new(7),
                        status: GradingStatus::Graded,
                        score: Some(Score::Letter { value: "A".into() }),
                        feedback: None,
                        weight: Some(0.15),
                    },
                    Assessment {
                        id: format!("{}-a3", course.id),
                        title: "专题作业".into(),
                        date: term_start + Days::new(14),
                        status: GradingStatus::Pending,
                        score: None,
                        feedback: None,
                        weight: Some(0.60),
                    },
                ],
            }
        })
        .collect();
    Gradebook {
        term: term_id(term_start),
        published_gpa: None,
        courses,
    }
}

pub(super) fn make_student(id: &str, name: &str, date: NaiveDate, variant: usize) -> Student {
    let profile = Profile {
        id: id.into(),
        name: name.into(),
        reference_date: date,
        term: term_id(date),
    };
    let names = if variant == 0 {
        [
            "Further Mathematics",
            "English Literature",
            "Geography",
            "Economics",
            "Chemistry",
            "Physical Education",
        ]
    } else {
        [
            "Physics",
            "Economics",
            "Chinese Literature",
            "Physical Education",
            "Further Mathematics",
            "English III",
        ]
    };
    let courses: Vec<_> = names
        .iter()
        .enumerate()
        .map(|(i, name)| Course {
            id: format!("{id}-c{i}"),
            name: (*name).to_owned(),
            teacher: ["林老师", "许老师", "陆老师", "程老师", "陶老师", "顾老师"][i].into(),
            room: Some(format!("D{}", 301 + i + variant * 10)),
        })
        .collect();
    let work = demo_work(&profile, &courses, variant);
    let resources = [ResourceScope::Shared, ResourceScope::Personal]
        .into_iter()
        .enumerate()
        .map(|(i, scope)| {
            let content = format!(
                "{}复习要点：整理本单元的概念，记录仍需复习的问题。",
                courses[i].name
            );
            let shared = scope == ResourceScope::Shared;
            Resource {
                id: format!("{id}-r{i}"),
                title: format!("{}复习笔记", courses[i].name),
                scope,
                kind: ResourceKind::Document,
                size_bytes: Some(content.len() as u64),
                content,
                shared_by: shared.then(|| SharingTeacher {
                    id: format!("{id}-teacher-{i}"),
                    name: courses[i].teacher.clone(),
                }),
                shared_at: shared.then(|| at(date - Days::new(2), 13 * 60)),
            }
        })
        .collect();
    let coverage = DateRange {
        from: date - Days::new(29),
        to: date,
    };
    let mut attendance = Vec::new();
    for day in coverage.from.iter_days().take(30).filter(|d| weekday(*d)) {
        for (i, course) in courses.iter().enumerate() {
            let status = match (day.ordinal() as usize + i + variant * 3) % 19 {
                0 => AttendanceStatus::Absent,
                1 => AttendanceStatus::Late,
                2 => AttendanceStatus::Early,
                _ => AttendanceStatus::Present,
            };
            attendance.push(AttendanceRecord {
                id: format!("{}:{day}", course.id),
                course_id: course.id.clone(),
                date: day,
                status,
            });
        }
    }
    let snapshot = GradeSnapshot::new(
        id,
        demo_grades(&courses, term_start(date), variant),
        &courses,
    );
    let grade_history = vec![demo_grades(
        &courses,
        previous_term_start(date),
        variant + 2,
    )];
    let rotation = Rotation::new(monday(date), 1, 6, vec![]).expect("valid demo rotation");
    // School-wide times are independent of the number of courses a student takes.
    let bells = super::CAMPUS_TEACHING_SLOTS.to_vec();
    Student {
        profile,
        teaching_slots: Some(vec![bells; usize::from(rotation.cycle_length())]),
        rotation,
        grades: Arc::new(snapshot),
        grade_history,
        courses,
        work,
        resources,
        attendance_coverage: coverage,
        attendance,
        daily_attendance: Some(demo_daily(id, coverage, variant)),
        activity_attendance: Some(demo_activity(id, coverage, variant)),
        events: vec![
            CalendarEvent {
                id: format!("{id}-calendar"),
                title: "校园阅读日".into(),
                kind: "school_calendar".into(),
                start: at(date, 0),
                end: at(date + Days::new(1), 0),
                all_day: true,
            },
            CalendarEvent {
                id: format!("{id}-event"),
                title: "社团活动".into(),
                kind: "activity".into(),
                start: at(date, 16 * 60),
                end: at(date, 17 * 60),
                all_day: false,
            },
        ],
    }
}
