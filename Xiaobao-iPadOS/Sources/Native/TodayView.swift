import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                let calendar = model.provider.schoolCalendar.publishedDay(on: model.now)
                TodayRotationHeader(date: model.now, day: model.todayRotationDay,
                                    unpublished: calendar?.status == .unpublished)
                let lessons = model.provider.lessons(on: model.now)
                let next = NextSchoolDay(after: model.now) { date in
                    let source = model.provider, row = source.schoolCalendar.publishedDay(on: date)
                    guard row?.teachingDay != nil else { return (row, nil) }
                    return (row, source.timeline(on: date, lessons: source.lessons(on: date)))
                }
                TodayTimetableView(timeline: model.provider.timeline(on: model.now, lessons: lessons),
                                   nextSchoolDay: next, noClassNotice: calendar?.notices.first)
                Text("XIAOBAO").tracking(3)
                    .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            .padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
    }
}

/// The timeline is the only overview. Its selected instant also drives the card above it.
struct TodayTimetableView: View {
    @Environment(AppModel.self) private var model
    /// Original enrollment timeline; never give a display-filtered timeline to ActivityKit.
    let timeline: LessonTimeline?
    let nextSchoolDay: NextSchoolDay?
    var noClassNotice: String? = nil
    @State private var saved: (Read, [PersonalPlan])?

    private struct Read: Hashable {
        let scope: TimetablePlanScope?
        let day: String
        let publication: String?
        let revision: UUID
    }

    private var read: Read {
        .init(scope: TimetablePlanScope(model), day: SchoolClock.key(model.now),
              publication: model.planRotationCalendar?.sourceSHA256, revision: model.planDisplayRevision)
    }

    var body: some View {
        let key = read, date = model.now
        let plans = saved?.0 == key ? saved?.1 ?? [] : []
        let school = PlannerSchoolSource(model: model, dates: [date]).schoolDay(on: date).school
        let display = TimetablePresentation(on: date, school: school, plans: plans, settings: model.personalization)
        let visible = display.timeline(original: timeline)
        let instant = model.timetableInstant
        let focus = visible?.focus(at: instant)
        let recess = visible?.recess(at: instant)
        let hidden = timeline?.blocks.isEmpty == false || !plans.isEmpty || school.entries.contains { $0.kind.isReferenceOnly }
        FocusLessonCard(timeline: visible, focus: focus, recess: recess, instant: instant,
                        nextSchoolDay: nextSchoolDay, noClassNotice: noClassNotice, emptyIsFiltered: hidden)
            .task(id: key) {
                guard let scope = key.scope else { saved = nil; return }
                let courses = try? await model.planStore.read(day: key.day, for: scope.owner, calendar: model.planRotationCalendar)
                    .filter { $0.courseKind != nil }
                guard !Task.isCancelled, read == key else { return }
                saved = (key, courses ?? [])
            }
        if let visible, let bounds = visible.bounds {
            TimeLensView(timeline: visible, bounds: bounds, instant: instant, focus: focus, recess: recess)
        }
        if let timeline, timeline.bounds != nil { LessonActivityControl(timeline: timeline) }
    }
}

private struct TimeLensView: View {
    let timeline: LessonTimeline
    let bounds: ClosedRange<Int>
    let instant: Date
    let focus: LessonTimeline.Block?
    let recess: DateInterval?
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var isPressed = false
    @Namespace private var glassNamespace

    var body: some View {
        let minute = model.minute
        let cursor = timeline.minute(of: instant)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("课程时间轴").font(.headline)
                Spacer()
                let inspecting = model.inspectedMinute != nil
                Button("回到当前时间") { model.returnToNow() }.buttonStyle(.glass).font(.caption)
                    .disabled(!inspecting).opacity(inspecting ? 1 : 0)
                    .allowsHitTesting(inspecting).accessibilityHidden(!inspecting)
            }
            GeometryReader { proxy in
                let inset = min(32, proxy.size.width / 8)
                let track = max(1, proxy.size.width - 2 * inset)
                let layout = TimelineTrackLayout(timeline: timeline, bounds: bounds, width: Double(track))
                let select = { (x: CGFloat) in
                    model.inspect(Int(layout.minute(at: Double(x - inset)).rounded()))
                }
                GlassEffectContainer(spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        ForEach(layout.tiles) { tile in
                            blockTile(tile.block, width: CGFloat(tile.width))
                                .position(x: inset + CGFloat(tile.center), y: 43)
                        }
                        if cursor >= Double(bounds.lowerBound), cursor <= Double(bounds.upperBound) {
                            marker(minute: minute)
                                .position(x: inset + CGFloat(layout.position(at: cursor)), y: 43)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .overlay {
                    // The glass and tiles move under the finger; measure touches in the fixed track.
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(glassNamespace))
                            .updating($isPressed) { _, pressed, _ in pressed = true }
                            .onChanged { select($0.location.x) }
                            .onEnded { select($0.location.x) })
                }
                .coordinateSpace(name: glassNamespace)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("课程时间透镜")
                .accessibilityValue(spokenProgress(minute))
                .accessibilityAdjustableAction { direction in
                    let adjustment = direction == .increment ? 5 : -5
                    model.inspect(min(bounds.upperBound, max(bounds.lowerBound, minute + adjustment)))
                }
            }.frame(height: 94)
            Text(model.inspectedMinute == nil ? String(localized: "现在 \(SchoolClock.time(minute))") : String(localized: "所选时间 \(SchoolClock.time(minute))"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).background(.primary.opacity(0.035), in: .rect(cornerRadius: 30))
    }

    private func marker(minute: Int) -> some View {
        let outline = RoundedRectangle(cornerRadius: isPressed ? 23 : 4, style: .continuous)
        return VStack(spacing: 6) {
            Capsule().fill(Color.accentColor).frame(width: 2, height: 42)
            if isPressed {
                Text(SchoolClock.time(minute)).font(.caption2.weight(.semibold)).monospacedDigit()
                    .fixedSize().transition(.opacity)
            }
        }
        .frame(width: isPressed ? 62 : 8, height: isPressed ? 84 : 54)
        .background {
            if reduceTransparency { outline.fill(Color(uiColor: .secondarySystemBackground)) }
        }
        .glassEffect(reduceTransparency ? .identity : .clear, in: outline)
        .glassEffectID("time-lens", in: glassNamespace)
        // Only the transient contact animates the marker, never hover or the retained minute.
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func tileLabel(_ block: LessonTimeline.Block) -> some View {
        if let period = block.lesson {
            Text(period.shortName).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
        } else {
            ViewThatFits(in: .horizontal) {
                Text(block.title).font(.caption.weight(.medium)).fixedSize()
                Text(block.title).font(.caption2.weight(.medium).width(.compressed)).fixedSize()
                // Prefer a legible short name over an ellipsis or splitting a word.
                // The card, full timetable and adjustable control still use the full title.
                switch block {
                case .freeblock: Text("空节").font(.caption.weight(.medium))
                default: Text(block.title).font(.caption2.weight(.medium))
                }
            }.lineLimit(1)
        }
    }

    private func blockTile(_ block: LessonTimeline.Block, width: CGFloat) -> some View {
        let fraction = block.elapsedFraction(at: instant)
        let label = tileLabel(block).frame(width: width, height: 54)
        let blue = label.foregroundStyle(.white).background(Color.accentColor)
        return Group {
            if fraction == 1 { blue }
            else {
                label.foregroundStyle(.primary).background(Color.primary.opacity(0.06))
                    .overlay {
                        if fraction > 0 {
                            // Mask the ink with the fill so a label crossing the boundary stays legible.
                            blue.mask(alignment: .leading) { Rectangle().frame(width: width * CGFloat(fraction)) }
                        }
                    }
            }
        }.clipShape(.rect(cornerRadius: 13))
    }

    private func spokenProgress(_ minute: Int) -> String {
        let time = SchoolClock.time(minute)
        if let recess {
            return String(localized: "\(time)，课间，\(restCountdown(after: recess.end, at: instant, in: timeline))")
        }
        guard let focus else { return String(localized: "\(time)，今天的课程已结束") }
        if instant < focus.start {
            if case .activity = focus { return String(localized: "\(time)，接下来，\(focus.title)") }
            return String(localized: "\(time)，下一节，\(focus.title)")
        }
        let percent = Int(focus.elapsedFraction(at: instant) * 100)
        let status = if case .freeblock = focus { String(localized: "，休息一下") } else { "" }
        return String(localized: "\(time)，\(focus.title)\(status)，已过 \(percent)%")
    }
}

private struct FocusLessonCard: View {
    @Environment(AppModel.self) private var model
    let timeline: LessonTimeline?
    let focus: LessonTimeline.Block?
    let recess: DateInterval?
    let instant: Date
    let nextSchoolDay: NextSchoolDay?
    let noClassNotice: String?
    let emptyIsFiltered: Bool

    var body: some View {
        GlassCard {
            if let timeline {
                if timeline.blocks.isEmpty {
                    endOfDay(emptyIsFiltered ? String(localized: "没有可显示的安排") : String(localized: "今天没有排课"),
                             symbol: "calendar", notice: noClassNotice)
                } else {
                    // Measure each real alternative at the current width and text size.
                    // Only the active content is drawn, interactive or read by VoiceOver.
                    ZStack(alignment: .leading) {
                        ForEach(timeline.blocks) { block in
                            let card = content(for: block, in: timeline)
                            if recess != nil || block.id != focus?.id { card.hidden().accessibilityHidden(true) }
                            else if hasDetails(block) {
                                Button { model.selectedLesson = TimetableDetail(block) } label: { card }
                                    .buttonStyle(.plain).accessibilityHint("查看详情")
                                    .accessibilityIdentifier("today-timetable-detail")
                            } else { card }
                        }
                        if let interval = recess ?? timeline.recesses.first {
                            let card = periodCard(status: String(localized: "课间 · \(restCountdown(after: interval.end, at: instant, in: timeline))"),
                                                  location: nil, title: String(localized: "课间"), interval: interval)
                            if recess != nil { card } else { card.hidden().accessibilityHidden(true) }
                        }
                        let finished = endOfDay(String(localized: "今天的课程已结束"), symbol: "sunset")
                        if focus == nil { finished } else { finished.hidden().accessibilityHidden(true) }
                    }
                }
            } else {
                Text("课程时间暂不可用").font(.headline)
            }
        }
    }

    private func content(for block: LessonTimeline.Block, in timeline: LessonTimeline) -> some View {
        let active = instant >= block.start
        let minutes = minutesUntil(active ? block.end : block.start, from: instant)
        let title: String
        let status: String
        switch block {
        case .lesson(let lesson):
            title = lesson.name
            status = active ? String(localized: "上课中 · \(minutes) 分钟后下课") : String(localized: "下一节 · \(minutes) 分钟后上课")
        case .freeblock:
            title = block.title
            status = active ? String(localized: "空节中 · \(minutes) 分钟后结束") : String(localized: "下一节 · \(minutes) 分钟后开始")
        case .reference(let period, _):
            title = period.name
            status = active ? String(localized: "\(minutes) 分钟后结束") : String(localized: "下一项 · \(minutes) 分钟后开始")
        case .activity(let activity, _):
            title = activity.detailTitle
            switch activity {
            case .assembly:
                status = active ? String(localized: "班会中 · \(minutes) 分钟后下课") : String(localized: "下一节 · \(minutes) 分钟后开始")
            case .lunch:
                status = active ? String(localized: "午餐中 · \(restCountdown(after: block.end, at: instant, in: timeline))")
                                : String(localized: "下一项 · \(minutes) 分钟后开始")
            }
        }
        let opensDetail = hasDetails(block)
        return periodCard(status: status, location: block.location, title: title,
                          interval: DateInterval(start: block.start, end: block.end),
                          expectsLocation: block.lesson != nil,
                          opensDetail: opensDetail, showReminder: block.lesson != nil && model.usesLocalTimetable)
    }

    private func hasDetails(_ block: LessonTimeline.Block) -> Bool {
        if case .freeblock = block { return false }
        return true
    }

    private func periodCard(status: String, location: String?, title: String, interval: DateInterval,
                            expectsLocation: Bool = false, opensDetail: Bool = false, showReminder: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status).font(.subheadline)
                Spacer()
                if opensDetail { Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true) }
            }.foregroundStyle(.secondary)
            if let location, !location.isEmpty {
                let font = Font.system(size: 64, weight: .semibold, design: .rounded)
                // A full-size line reserves the row. The name fits the available
                // width without changing the measurements of the other three lines.
                Text(verbatim: "0").font(font).fixedSize()
                    .hidden().accessibilityHidden(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Text(verbatim: location).font(font).foregroundStyle(Color.accentColor)
                            .minimumScaleFactor(0.45).lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
            } else if expectsLocation { Text("地点未提供").foregroundStyle(.secondary) }
            Text(title).font(.title2.weight(.semibold))
            Text("\(schoolDateLabel(interval.start, format: "HH:mm")) – \(schoolDateLabel(interval.end, format: "HH:mm"))")
                .monospacedDigit().foregroundStyle(.primary)
            if showReminder, model.preferences.remindersEnabled {
                Label("课前提醒已开启", systemImage: "bell").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    private func endOfDay(_ title: String, symbol: String, notice: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol).font(.title2.weight(.semibold))
            if let notice { Text(notice).font(.subheadline).foregroundStyle(.secondary) }
            nextClassPreview
        }
    }

    @ViewBuilder private var nextClassPreview: some View {
        if let next = nextSchoolDay {
            let date = schoolDateLabel(next.date)
            VStack(alignment: .leading, spacing: 6) {
                Text("下一个上课日").font(.subheadline).foregroundStyle(.secondary)
                Text(verbatim: next.rotation.map { String(localized: "\(date) · Day \($0)") } ?? date)
                    .font(.headline)
                let first = next.firstLessons.filter { model.personalization.shows(TimetablePresentation.courseCategory(title: $0.name, start: $0.start)) }
                if first.count > 1 {
                    Text("首节有多个课次同时开始，可在计划中查看。")
                } else if let lesson = first.first {
                    Text(verbatim: String(localized: "第一节：\(lesson.name) · \(lesson.room ?? String(localized: "教室未提供"))"))
                } else if next.firstLessons.isEmpty {
                    Text("第一节课尚未确认")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today-next-school-day")
            Button("查看当天计划", systemImage: "arrow.right") { model.openPlanner(on: next.date) }
                .buttonStyle(.glass)
                .accessibilityHint("打开\(date)的计划")
                .accessibilityIdentifier("today-next-school-day-plan")
        } else {
            Text("下一个上课日尚未确认").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private func minutesUntil(_ target: Date, from instant: Date) -> Int {
    max(0, Int(ceil(target.timeIntervalSince(instant) / 60)))
}

private func restCountdown(after end: Date, at instant: Date, in timeline: LessonTimeline) -> String {
    if let next = timeline.nextInstructionStart(from: end) {
        return String(localized: "还有 \(minutesUntil(next, from: instant)) 分钟上课")
    }
    let minutes = minutesUntil(end, from: instant)
    // A terminal Free Block has no class to count down to.
    if let next = timeline.focus(at: end), next.start == end, case .freeblock = next {
        return String(localized: "\(minutes) 分钟后进入空节")
    }
    return String(localized: "\(minutes) 分钟后结束")
}
