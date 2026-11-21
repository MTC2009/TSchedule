import SwiftUI
import UIKit

struct LessonActivitySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var heading = ""

    private var background: LessonActivityAppearance.Background { model.personalization.lessonActivity.background }
    private var appearance: LessonActivityAppearance { .init(background: background, nextHeading: heading) }

    private var preview: LessonActivityAttributes.ContentState {
        let date = model.now
        guard model.school.selected, model.school.owner != nil,
              let week = model.school.week(on: date), let schedule = week.schedule(on: date),
              let timeline = schedule.timeline(courseName: { week.names[$0] ?? "课程" }),
              let plan = LessonActivityPlan(timeline: timeline, at: date)
        else { return .closed }
        return .init(startsAt: plan.startsAt, endsAt: plan.endsAt, nextLesson: plan.next?.title,
                     isDemo: false, appearance: appearance)
    }

    var body: some View {
        SettingsForm {
            Section("锁屏预览") {
                LessonActivityCard(state: preview, isStale: false, previewDate: model.now)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(background.tint ?? Color(uiColor: .secondarySystemBackground))
                    }
                    .accessibilityIdentifier("settings-activity-preview")
            }
            Section {
                Picker("卡片背景", selection: Binding(get: { background }, set: { choice in
                    model.personalization.setLessonActivity(.init(background: choice,
                        nextHeading: model.personalization.lessonActivity.nextHeading))
                })) {
                    Text("系统默认").tag(LessonActivityAppearance.Background.system)
                    Text("校园蓝").tag(LessonActivityAppearance.Background.campusBlue)
                    Text("柔和灰").tag(LessonActivityAppearance.Background.softGray)
                }
                .accessibilityIdentifier("settings-activity-background")
            } footer: {
                Text("有正在进行的课程时，预览使用今天已读取的课表。")
            }
            Section {
                TextField("下一节课小标题", text: $heading, prompt: Text("下一节课"))
                    .accessibilityIdentifier("settings-activity-heading")
                    .submitLabel(.done)
                    .onSubmit(saveHeading)
                Button("保存小标题", action: saveHeading)
                    .disabled(heading == (model.personalization.lessonActivity.nextHeading ?? ""))
            } header: {
                Text("下一节课小标题")
            } footer: {
                Text("留空保存可恢复默认。下次开启实时活动时使用新样式，不影响课程名或下课时间。")
            }
        }
        .navigationTitle("实时活动")
        .onAppear { heading = model.personalization.lessonActivity.nextHeading ?? "" }
    }

    private func saveHeading() {
        model.personalization.setLessonActivity(appearance)
        heading = model.personalization.lessonActivity.nextHeading ?? ""
    }
}
