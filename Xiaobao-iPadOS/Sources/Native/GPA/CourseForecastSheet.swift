import SwiftUI

struct CourseForecastSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let courseName: String
    let categories: [String]
    let existing: AssessmentForecast?
    let saveEstimate: (AssessmentForecast) -> Void
    let removeEstimate: (UUID) -> Void
    @State private var name = ""
    @State private var mark = ""
    @State private var category: String?
    @State private var weight = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任务名称（可选）", text: $name)
                        .accessibilityIdentifier("course-forecast-name")
                    TextField("预估得分（%）", text: $mark)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("course-forecast-mark")
                    if categories.isEmpty {
                        LabeledContent("任务类别", value: "不分组")
                    } else {
                        Picker("任务类别", selection: $category) {
                            Text("不分组").tag(nil as String?)
                            ForEach(categories, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        .accessibilityIdentifier("course-forecast-category")
                    }
                } header: {
                    Text(courseName)
                } footer: {
                    Text(mark.isEmpty || percent(mark) != nil ? "得分可以填 0–100，支持小数。" : "得分必须是 0–100 之间的数值。")
                }

                Section {
                    TextField("假设占课程总评（%，可选）", text: $weight)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("course-forecast-weight")
                } footer: {
                    Text(hasInvalidWeight
                         ? "权重必须是 0–100 之间的数值。"
                         : "权重是你填的试算假设，不是学校权重。留空仍可加入，但不计算预估总评。")
                }

                if let existing {
                    Section {
                        Button("移除预估", role: .destructive) {
                            removeEstimate(existing.id)
                            dismiss()
                        }
                        .accessibilityIdentifier("course-forecast-remove")
                    }
                }
            }
            .navigationTitle(existing == nil ? "添加预估" : "编辑预估")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "添加" : "保存", action: save)
                        .disabled(percent(mark) == nil || hasInvalidWeight)
                        .accessibilityIdentifier("course-forecast-save")
                }
            }
            .onAppear(perform: loadExisting)
        }
        .presentationDetents([.large])
    }

    private var hasInvalidWeight: Bool {
        !weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && percent(weight) == nil
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
        category = existing.category
        weight = existing.courseWeight.map { ($0 * 100).formatted(format) } ?? ""
    }

    private func save() {
        guard let mark = percent(mark), !hasInvalidWeight,
              let estimate = try? AssessmentForecast(id: existing?.id ?? UUID(), name: name,
                                                         category: category, mark: mark,
                                                         courseWeight: percent(weight).map { $0 / 100 }) else { return }
        saveEstimate(estimate)
        dismiss()
    }
}
