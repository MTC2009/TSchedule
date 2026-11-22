import SwiftUI

struct TimetableDisplaySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsForm {
            Section {
                rows([.schoolCourse, .examCourse, .optionalBlock, .freeblock, .assembly])
            } header: {
                Text("课程与节次")
            } footer: {
                Text("只改变本机「今日」和「计划」的显示，不改选课、提醒或实时活动。外考课程不包括考试日程。")
            }
            Section {
                rows([.tssa, .study, .sport])
            } header: {
                Text("晚间安排")
            } footer: {
                Text("关闭 TSSA 后，已排定的那一节按晚自习显示。若也关闭晚自习，则两者都不显示。")
            }
            Section("生活作息") {
                rows([.breakfast, .lunch, .dinner, .wash, .sleep])
            }
        }
        .navigationTitle("课表显示")
    }

    private func rows(_ categories: [TimetableCategory]) -> some View {
        ForEach(categories, id: \.self) { category in
            Toggle(isOn: Binding(get: { model.personalization.shows(category) },
                                 set: { model.personalization.setShown($0, for: category) })) {
                Text(verbatim: category.title)
            }
            .accessibilityIdentifier("timetable-shows-" + category.rawValue)
        }
    }
}
