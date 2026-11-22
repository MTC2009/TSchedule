import SwiftUI

struct CourseForecastSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let courseName: String
    let groups: ForecastGroups
    let existing: AssessmentForecast?
    let saveEstimate: (AssessmentForecast) throws -> Void
    let removeEstimate: (UUID) throws -> Void
    @State private var name = ""
    @State private var mark = ""
    @State private var groupID: String?
    @State private var didLoad = false
    @State private var writeFailed = false
    @FocusState private var editingMark: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任务名称（可选）", text: $name)
                        .accessibilityIdentifier("course-forecast-name")
                    if groups.options.isEmpty {
                        LabeledContent("评估分组", value: String(localized: "未提供"))
                    } else {
                        Picker("评估分组", selection: $groupID) {
                            Text("请选择分组").tag(nil as String?)
                            ForEach(groups.options) { group in Text(group.title).tag(Optional(group.id)) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("course-forecast-category")
                    }
                    if let group = groups[groupID] {
                        if !groups.isLeaf(group.id) {
                            Text("请选择任务所属的子分组；上级分组只用来汇总。").font(.footnote).foregroundStyle(.secondary)
                        }
                        let nested = group.parentID != nil || group.weight?.scope == .group
                        shareRow(nested ? String(localized: "分组占上级") : String(localized: "分组占课程总评"),
                                 value: group.weight?.displayText ?? String(localized: "未提供"), id: "course-forecast-group-share")
                        if nested {
                            shareRow(String(localized: "折合课程总评"), value: groups.courseShare(of: group).map {
                                $0.formatted(.percent.precision(.fractionLength(0...2)))
                            } ?? String(localized: "未提供"),
                                     id: "course-forecast-course-share")
                        }
                    }
                    // iPad's decimalPad may be a modal popover: its dismissal used to
                    // consume the tap meant for the menu or Save. Keep decimal input
                    // and hardware-keyboard Done without putting a popover over the form.
                    TextField("预估得分（%）", text: $mark)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($editingMark).submitLabel(.done)
                        .onSubmit { editingMark = false }
                        .accessibilityIdentifier("course-forecast-mark")
                } header: {
                    Text(courseName)
                } footer: {
                    if writeFailed { Text("无法保存预测，请稍后重试。") }
                    else { Text(mark.isEmpty || percent(mark) != nil ? String(localized: "得分可以填 0–100，支持小数。") : String(localized: "得分必须是 0–100 之间的数值。")) }
                }

                if let existing {
                    Section {
                        Button("移除预估", role: .destructive) {
                            do { try removeEstimate(existing.id) }
                            catch { writeFailed = true }
                        }
                        .accessibilityIdentifier("course-forecast-remove")
                    }
                }
            }
            .navigationTitle(existing == nil ? String(localized: "添加预估") : String(localized: "编辑预估"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? String(localized: "添加") : String(localized: "保存"), action: save)
                        .disabled(percent(mark) == nil || !groupIsValid)
                        .accessibilityIdentifier("course-forecast-save")
                }
            }
            .onAppear(perform: loadExisting)
        }
        .presentationDetents([.large])
    }

    private var groupIsValid: Bool { groups.options.isEmpty ? groupID == nil : groups[groupID].map { groups.isLeaf($0.id) } == true }

    private func shareRow(_ label: String, value: String, id: String) -> some View {
        LabeledContent(label, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label).accessibilityValue(value).accessibilityIdentifier(id)
    }

    private func percent(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = trimmed.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        guard let value = Double(number), value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    private func loadExisting() {
        guard !didLoad, let existing else { return }
        didLoad = true
        let format = FloatingPointFormatStyle<Double>.number.locale(locale).grouping(.never).precision(.fractionLength(0...12))
        name = existing.name ?? ""
        mark = existing.mark.formatted(format)
        groupID = groups.id(for: existing)
    }

    private func save() {
        guard let mark = percent(mark), groupIsValid,
              let estimate = try? AssessmentForecast(id: existing?.id ?? UUID(), name: name,
                                                     groupID: groupID, groupAnchor: groups.anchor(for: groupID), mark: mark) else { return }
        do { try saveEstimate(estimate) }
        catch { writeFailed = true }
    }
}
