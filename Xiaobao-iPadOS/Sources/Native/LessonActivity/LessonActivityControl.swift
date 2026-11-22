import SwiftUI

/// One foreground action belongs to the existing Today schedule.
struct LessonActivityControl: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    let timeline: LessonTimeline

    var body: some View {
        let activity = model.lessonActivity
        let source = model.lessonActivitySource
        let plan = LessonActivityPlan(timeline: timeline, at: model.now)
        let focus = phase == .active ? activity.focusMinute(in: timeline, source: source, at: model.now) : nil
        Group {
            if activity.isRunning || (source != nil && plan != nil) {
                VStack(alignment: .trailing, spacing: 6) {
                    Button(activity.isRunning ? String(localized: "结束锁屏课表") : String(localized: "在锁屏显示课表"),
                           systemImage: activity.isRunning ? "stop.circle" : "lock.rectangle") {
                        if activity.isRunning { activity.stop() }
                        else if phase == .active, !model.portalPresented, let source, model.lessonActivitySource == source,
                                let actual = LessonActivityPlan(timeline: timeline, at: Date()) {
                            activity.start(actual, source: source, appearance: model.personalization.lessonActivity)
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(activity.ending || phase != .active)
                    .accessibilityIdentifier("lesson-activity-toggle")
                    .accessibilityHint(activity.isRunning ? "" : String(localized: "在锁屏显示距离下课的分钟数和下一节课程名"))
                    if let issue = activity.issue {
                        Text(issue).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onChange(of: plan, initial: true) { _, value in
            if let source, phase == .active { activity.validate(value, source: source) }
        }
        .onChange(of: focus, initial: true) { _, minute in
            if let minute, phase == .active {
                activity.consumeFocus()
                model.inspect(minute)
            }
        }
    }
}
