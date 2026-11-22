import SwiftUI

struct CampusGradebookView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @State private var requestedCheck = false

    var body: some View {
        let client = model.campus
        let saved = client.savedGrades
        let readout = saved?.grades.gpaReadout
        GPAOverviewView(
            isCurrentTerm: true,
            summary: readout?.summary,
            unavailableMessage: availabilityMessage(for: readout),
            courses: saved?.courseGradeDetails ?? []
        ) {
            if let saved { Text(termTitle(saved.grades.term)).font(.subheadline.weight(.medium)) }
        } gradeStatus: {
            if let saved, saved.grades.courses.isEmpty {
                StudentEmptyState(title: String(localized: "暂无课程成绩"), detail: String(localized: "已保存的学期没有课程成绩。"))
                    .background(.background, in: .rect(cornerRadius: 30))
            }
            checkControls
        }
        .task(id: phase) {
            if phase == .active { await client.load(.grades) }
        }
        .refreshable {
            if saved != nil || client.updatePolicy != .manual { await checkGrades() }
        }
    }

    private func availabilityMessage(for readout: CampusGPAReadout?) -> String {
        if case .unavailable(let inputs)? = readout {
            let reasons = inputs.map(\.message).joined(separator: String(localized: "；"))
            return String(localized: "暂不能估算：\(reasons)。")
        }
        let client = model.campus
        if !client.readSavedGrades && client.errors[.grades] == nil { return String(localized: "正在读取本机成绩。") }
        if client.checkingGrades || requestedCheck { return String(localized: "正在检查本学期成绩。") }
        return String(localized: "尚未获取本学期成绩。")
    }

    @ViewBuilder private var checkControls: some View {
        let client = model.campus
        let checking = client.checkingGrades || requestedCheck
        if client.readSavedGrades || client.errors[.grades] != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let error = client.errors[.grades] {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let saved = client.savedGrades {
                    Text("最近检查 \(schoolDateLabel(saved.checked, format: "yyyy年M月d日 HH:mm"))")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let message = client.gradeCheckMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                Button {
                    Task { await checkGrades() }
                } label: {
                    if checking {
                        Label { Text("检查中") } icon: { ProgressView() }
                    } else {
                        Label(client.savedGrades == nil ? String(localized: "获取本学期成绩") : String(localized: "刷新 GPA"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.glass)
                .disabled(checking)
                .accessibilityIdentifier("gpa-check-grades")
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 30))
        }
    }

    private func checkGrades() async {
        guard !requestedCheck, !model.campus.checkingGrades else { return }
        requestedCheck = true
        defer { requestedCheck = false }
        await model.campus.load(.grades, force: true)
    }

    private func termTitle(_ id: String) -> String {
        let parts = id.split(separator: "-")
        guard parts.count == 2, parts[0].count == 4, Int(parts[0]) != nil else { return id }
        switch parts[1] {
        case "spring": return String(localized: "\(parts[0]) 春季学期")
        case "autumn": return String(localized: "\(parts[0]) 秋季学期")
        default: return id
        }
    }
}

private extension CampusGPAReadout.MissingInput {
    var message: String {
        switch self {
        case .courseList: String(localized: "缺少有效的计入课程清单")
        case .credits: String(localized: "部分课程缺少有效学分")
        case .publishedTotals: String(localized: "部分课程缺少可换算的已公布成绩")
        case .conversionRule: String(localized: "缺少校方计分规则")
        case .invalidConversionRule: String(localized: "校方计分规则不完整或有冲突")
        case .invalidValues: String(localized: "学分或绩点数据无效")
        }
    }
}
