import SwiftUI

struct PlannerBandPreview {
    let start: Int
    let end: Int?
    let color: PlanColor?
}

/// Draws the schedule and offers time targets; it has no storage or drag session state.
struct PlannerScheduleCanvas: View {
    @Environment(AppModel.self) private var model
    @State private var selectedWorkID: String?
    @State private var disclosedSchoolTime: PlannerSchoolEntry.ID?
    @State private var labelFrames: [PlannerSchoolEntry.ID: CGRect] = [:]
    @Namespace private var labelSpace
    @ScaledMetric(relativeTo: .caption) private var planLabelHeight = 23.0
    let day: PlannerDay
    let scale: PlannerTimeScale
    let minimumHeight: Double
    let focus: PlannerDay.Focus?
    let preview: PlannerBandPreview?
    let actions: PlannerPlanActions
    let tapMinute: (Double) -> Void
    let acceptsTimeTap: Bool
    let opensSchool: Bool
    let compact: Bool
    let recurringIDs: Set<UUID>
    @Binding var shownGroup: PlannerDay.TimedRow.ID?

    var body: some View {
        let layout = PlannerTimelineLayout(day: day, scale: scale, minimumHeight: minimumHeight)
        GeometryReader { geometry in
            let left = compact ? 2 : PlannerTimelineLayout.markerTarget + 4
            let width = max(1, geometry.size.width - left - (compact ? 2 : 0))
            ZStack(alignment: .topLeading) {
                rules(width: width, left: left)
                schoolLayer(layout, width: width, left: left)
                personalLayer(layout, width: width, left: left)
                if let preview { previewBand(preview, width: width, left: left) }
                if acceptsTimeTap {
                    Color.clear.contentShape(Rectangle())
                        .frame(width: geometry.size.width, height: scale.height)
                        .gesture(SpatialTapGesture().onEnded {
                            if let minute = scale.minute(at: $0.location.y, includingDayEnd: true) { tapMinute(minute) }
                        })
                        .accessibilityHidden(true)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .coordinateSpace(name: labelSpace)
            .contentShape(Rectangle())
        }
        .frame(height: layout.height)
        .onPreferenceChange(PlannerSchoolLabelFrames.self) { labelFrames = $0 }
        .navigationDestination(item: $selectedWorkID) { id in
            if let item = StudentServices.work.first(where: { $0.id == id }) {
                SchoolWorkDetailView(item: item, allowsLocalCompletion: false)
            }
        }
    }

    private func rules(width: CGFloat, left: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.fill.tertiary).frame(width: 1, height: scale.height)
                .position(x: max(0, left - 5), y: scale.height / 2)
            ForEach(0...48, id: \.self) { tick in
                let hour = tick.isMultiple(of: 2)
                let y = scale.position(at: Double(tick * 30))
                Rectangle().fill(hour ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary))
                    .frame(width: width, height: 1)
                    .position(x: left + width / 2, y: y)
                Rectangle().fill(.fill.secondary).frame(width: hour ? 8 : 4, height: 1)
                    .position(x: max(0, left - 5), y: y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func schoolLayer(_ layout: PlannerTimelineLayout, width: CGFloat, left: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.freeBlocks) { freeBlock($0, width: width, left: left) }
            ForEach(layout.school.items) { item in
                if case .school(let entry) = item.row {
                    let lane = laneFrame(item, width: width, left: left)
                    schoolTarget(entry) {
                        schoolLabel(entry, emphasized: focus?.id == item.id,
                                    compact: compact || lane.width < 180, short: item.height < minimumHeight)
                    }
                    .frame(width: lane.width, height: item.height)
                    .position(x: lane.center, y: (item.top + item.bottom) / 2)
                }
            }
            PlannerTimelineMarks(groups: layout.school.markGroups,
                                 permitsOpening: opensSchool, canOpenSchool: canOpenSchool,
                                 openSchool: openSchool, timeLabel: schoolTime, trackWidth: width, left: left) { entry in
                schoolTarget(entry) {
                    Text(entry.title)
                        .font(.caption.weight(.semibold)).lineLimit(2)
                        .padding(.horizontal, 5)
                        .background { recordLabel(entry.id) }
                        .frame(minWidth: PlannerTimelineLayout.markerTarget, minHeight: PlannerTimelineLayout.markerTarget, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private func personalLayer(_ layout: PlannerTimelineLayout, width: CGFloat, left: CGFloat) -> some View {
        let layer = layout.personal
        if !layer.items.isEmpty || !layer.markGroups.isEmpty {
            let schoolText = protectedLabels(layout, width: width, left: left)
            let annotations = PlannerAnnotationLayout(personal: layer,
                track: CGRect(x: left, y: 0, width: width, height: layout.height), labelHeight: planLabelHeight,
                avoiding: schoolText)
            // The school's geometry, the full-width range and the annotations
            // are three independent drawing steps; only the last takes input.
            ZStack(alignment: .topLeading) {
                // Blend the bands first so overlap intensifies without ever
                // exceeding the readability limit over school text.
                ZStack(alignment: .topLeading) { savedBands(layer, width: width, left: left, paint: .overlayFill) }
                    .compositingGroup().opacity(PlannerRangeBand.savedOverlapOpacityLimit)
                    .allowsHitTesting(false)
                ZStack(alignment: .topLeading) { savedBands(layer, width: width, left: left, paint: .endpoints) }
                    .frame(width: left + width, height: layout.height, alignment: .topLeading)
                    .mask { endpointMask(avoiding: schoolText) }
                    .allowsHitTesting(false).accessibilityHidden(true)
                PlannerPlanAnnotations(values: annotations.annotations, day: day, actions: actions,
                                       recurringIDs: recurringIDs, permitsOpening: !acceptsTimeTap, shownGroup: $shownGroup)
            }
        }
    }

    private func endpointMask(avoiding text: [CGRect]) -> some View {
        // Keep the tint above the text, but never let a coincident boundary
        // look like a strike-through. The exposed edge caps keep the time.
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            context.blendMode = .destinationOut
            for rect in text { context.fill(Path(rect.insetBy(dx: -1, dy: -1)), with: .color(.white)) }
        }
    }

    private func protectedLabels(_ layout: PlannerTimelineLayout, width: CGFloat, left: CGFloat) -> [CGRect] {
        let target = PlannerTimelineLayout.markerTarget
        let cards = layout.school.items.compactMap { item -> CGRect? in
            guard case .school(let entry) = item.row else { return nil }
            let lane = laneFrame(item, width: width, left: left)
            // Protect a conservative frame on the first layout pass, then the
            // measured title and any supporting text, including Dynamic Type.
            return labelFrames[entry.id] ?? CGRect(x: lane.center - lane.width / 2,
                y: (item.top + item.bottom - item.height) / 2, width: lane.width, height: item.height)
        }
        let slots = layout.freeBlocks.map { block in
            labelFrames[block.entry.id] ?? CGRect(x: left, y: block.top, width: width, height: block.height)
        }
        let marks = layout.school.markGroups.map { group in
            let badge = CGRect(x: left, y: group.top, width: width, height: target)
            guard let entry = group.singleSchoolEntry else { return badge }
            return badge.union(labelFrames[entry.id] ?? CGRect(x: 0, y: group.top, width: left + width, height: target))
        }
        return cards + slots + marks
    }

    private func recordLabel(_ id: PlannerSchoolEntry.ID) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: PlannerSchoolLabelFrames.self, value: [id: geometry.frame(in: .named(labelSpace))])
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func laneFrame(_ item: PlannerTimelineLayout.Item, width: CGFloat, left: CGFloat)
        -> (width: CGFloat, center: CGFloat) {
        let gap = min(6, width / (2 * CGFloat(item.laneCount)))
        let laneWidth = (width - CGFloat(item.laneCount - 1) * gap) / CGFloat(item.laneCount)
        return (laneWidth, left + CGFloat(item.lane) * (laneWidth + gap) + laneWidth / 2)
    }

    @ViewBuilder private func savedBands(_ layer: PlannerTimelineLayout.Layer, width: CGFloat, left: CGFloat,
                                          paint: PlannerRangeBand.Paint) -> some View {
        ForEach(layer.items) { item in
            savedBand(item.row, top: item.top, bottom: item.bottom, width: width, left: left, paint: paint)
        }
        ForEach(layer.markGroups.flatMap(\.marks)) { mark in
            savedBand(mark.row, top: mark.top, bottom: mark.bottom, width: width, left: left, paint: paint)
        }
    }

    @ViewBuilder private func savedBand(_ row: PlannerDay.TimedRow, top: CGFloat, bottom: CGFloat,
                                         width: CGFloat, left: CGFloat, paint: PlannerRangeBand.Paint) -> some View {
        if case .personal(let plan, _, _) = row {
            PlannerRangeBand(color: plan.color, paint: paint, isPoint: bottom == top)
                .frame(width: width, height: bottom - top + 3)
                .position(x: left + width / 2, y: (top + bottom) / 2)
        }
    }

    @ViewBuilder private func schoolTarget<Content: View>(_ entry: PlannerSchoolEntry,
                                                          @ViewBuilder content: () -> Content) -> some View {
        let title = schoolTitle(entry)
        if opensSchool {
            if canOpenSchool(entry) {
                Button { openSchool(entry) } label: { content().contentShape(Rectangle()) }
                    .buttonStyle(.plain).hoverEffect(.highlight)
                    .accessibilityLabel(title)
                    .accessibilityValue(entry.location ?? "")
                    .accessibilityHint("查看详情中的起止时间")
            } else {
                Button { disclosedSchoolTime = entry.id } label: { content().contentShape(Rectangle()) }
                    .buttonStyle(.plain).hoverEffect(.highlight)
                    .accessibilityLabel(title)
                    .accessibilityValue(entry.location ?? "")
                    .accessibilityHint("查看起止时间")
                    .popover(isPresented: timeDisclosure(for: entry.id)) {
                        schoolTimeDetails(entry, title: title).presentationCompactAdaptation(.popover)
                    }
                    .onDisappear { if disclosedSchoolTime == entry.id { disclosedSchoolTime = nil } }
            }
        } else {
            // Edit keeps school cards passive so a held gesture belongs to the time track.
            content().accessibilityElement(children: .combine)
                .accessibilityLabel(title)
                .accessibilityValue(entry.location ?? "")
        }
    }

    private func timeDisclosure(for id: PlannerSchoolEntry.ID) -> Binding<Bool> {
        Binding(get: { disclosedSchoolTime == id }, set: { presented in
            if !presented, disclosedSchoolTime == id { disclosedSchoolTime = nil }
        })
    }

    private func schoolTimeDetails(_ entry: PlannerSchoolEntry, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(schoolTime(entry)).font(.body).monospacedDigit()
                .accessibilityIdentifier("planner-school-time-range")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(idealWidth: 220, maxWidth: 320, alignment: .leading)
    }

    private func schoolLesson(_ entry: PlannerSchoolEntry) -> Lesson? {
        guard model.usesLocalTimetable, let id = entry.lessonID else { return nil }
        return model.provider.lessons(on: day.date).first { $0.id == id }
    }

    private func schoolWork(_ entry: PlannerSchoolEntry) -> SchoolWork? {
        guard model.usesLocalTimetable, case .work(let kind, let id) = entry.id else { return nil }
        return StudentServices.work.first { $0.id == id && $0.kind.rawValue == kind }
    }

    private func canOpenSchool(_ entry: PlannerSchoolEntry) -> Bool {
        schoolWork(entry) != nil || entry.end != nil
    }

    private func openSchool(_ entry: PlannerSchoolEntry) {
        if let item = schoolWork(entry) { selectedWorkID = item.id; return }
        guard let end = entry.end else { return }
        let start = entry.start
        let interval: DateInterval
        if case .routine(.sleep, let night) = entry.id {
            let minutes = PlannerCampusPeriod.sleep.minutes
            interval = .init(start: SchoolClock.at(minute: minutes.lowerBound, on: night),
                             end: SchoolClock.at(minute: minutes.upperBound, on: night))
        } else { interval = .init(start: start, end: end) }
        let metadata = entry.metadata ?? schoolLesson(entry).map { .init(teacher: $0.course.teacher) }
        model.selectedLesson = TimetableDetail(title: schoolTitle(entry), start: interval.start, end: interval.end,
                                               location: entry.location, metadata: metadata, isCourse: entry.kind == .lesson)
    }

    private func schoolLabel(_ entry: PlannerSchoolEntry, emphasized: Bool, compact: Bool, short: Bool = false) -> some View {
        let caption = [emphasized ? (focus?.isOngoing == true ? String(localized: "进行中") : String(localized: "接下来")) : nil,
                       entry.kind.label, entry.location].compactMap { $0 }.joined(separator: " · ")
        return GlassCard(padding: 0, shape: PlannerCorners.card) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font((self.compact || short ? Font.caption : .subheadline).weight(.semibold))
                    .lineLimit(compact && !short ? 2 : 1).minimumScaleFactor(short ? 0.8 : 1)
                if !compact, !short, !caption.isEmpty {
                    Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.86)
                }
            }
            .background { recordLabel(entry.id) }
            .padding(.horizontal, self.compact ? 5 : (compact ? 8 : 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    private func freeBlock(_ block: PlannerTimelineLayout.FreeBlock, width: CGFloat, left: CGFloat) -> some View {
        let minute = scale.minute(block.entry.start, in: day.date)
        return schoolTarget(block.entry) {
            schoolLabel(block.entry, emphasized: false, compact: compact || width < 180)
        }
        .frame(width: width, height: max(1, block.height - PlannerTimelineLayout.cardGap))
        .accessibilityIdentifier("planner-free-\(Int(minute))")
        .allowsHitTesting(opensSchool)
        .position(x: left + width / 2, y: block.top + block.height / 2)
    }

    private func previewBand(_ preview: PlannerBandPreview, width: CGFloat, left: CGFloat) -> some View {
        let start = scale.position(at: Double(preview.start))
        let end = preview.end.map { scale.position(at: Double($0)) }
        let height = (end ?? start) - start
        return ZStack(alignment: .topLeading) {
            PlannerRangeBand(color: preview.color, paint: .preview, isPoint: end == nil)
                .frame(width: width, height: height + 3)
                .position(x: left + width / 2, y: start + height / 2)
            endpoint(at: start, color: preview.color, left: left)
            if let end { endpoint(at: end, color: preview.color, left: left) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func endpoint(at position: CGFloat, color: PlanColor?, left: CGFloat) -> some View {
        Rectangle().fill(color?.tint ?? .accentColor).frame(width: 10, height: 3)
            .position(x: max(0, left - 5), y: position)
    }

    private func schoolTime(_ entry: PlannerSchoolEntry) -> String {
        // Midnight clips the drawing, not the duration disclosed from either column.
        if case .routine(.sleep, _) = entry.id {
            let night = PlannerCampusPeriod.sleep.minutes
            let start = SchoolClock.time(night.lowerBound), end = SchoolClock.time(night.upperBound - 1440)
            return String(localized: "\(start) – 次日 \(end)")
        }
        let start = SchoolClock.time(Int(scale.minute(entry.start, in: day.date)))
        guard let end = entry.end else { return start }
        return start + " – " + SchoolClock.time(Int(scale.minute(end, in: day.date)))
    }

    private func schoolTitle(_ entry: PlannerSchoolEntry) -> String {
        entry.kind == .freeblock ? String(localized: "空节") : entry.title
    }

    static func timeLabel(_ time: PlanTime) -> String {
        let start = SchoolClock.time(time.startMinute)
        return time.endMinute.map { start + " – " + SchoolClock.time($0) } ?? start
    }
}

private struct PlannerSchoolLabelFrames: PreferenceKey {
    static let defaultValue: [PlannerSchoolEntry.ID: CGRect] = [:]

    static func reduce(value: inout [PlannerSchoolEntry.ID: CGRect], nextValue: () -> [PlannerSchoolEntry.ID: CGRect]) {
        value.merge(nextValue()) { _, newest in newest }
    }
}

private extension PlannerDay.Focus {
    var isOngoing: Bool { if case .ongoing = self { true } else { false } }
}

private extension PlannerSchoolEntry.Kind {
    var label: String? {
        switch self {
        case .lesson, .freeblock, .assembly, .lunch, .optionalBlock, .campusRoutine: nil
        case .calendar: String(localized: "校历")
        case .activity: String(localized: "学校活动")
        case .exam: String(localized: "考试开始")
        case .taskDeadline: String(localized: "任务截止")
        case .examDeadline: String(localized: "考试截止")
        case .evaluationDeadline: String(localized: "测评截止")
        case .deadline: String(localized: "截止")
        }
    }
}
