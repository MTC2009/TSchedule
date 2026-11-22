import Foundation
import BackgroundTasks
import Network
import Observation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case today, grades, attendance, tasks, otherItems, planner, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: String(localized: "今日"); case .grades: "GPA"; case .attendance: String(localized: "我的考勤")
        case .tasks: String(localized: "我的任务"); case .otherItems: String(localized: "其余项目"); case .planner: String(localized: "计划"); case .settings: String(localized: "设置")
        }
    }
    var symbol: String {
        switch self {
        case .today: "sun.horizon"; case .grades: "chart.bar.xaxis"; case .attendance: "person.badge.clock"
        case .tasks: "checklist"; case .otherItems: "pencil.and.list.clipboard"
        case .planner: "calendar"; case .settings: "slider.horizontal.3"
        }
    }
    var portalSection: String? {
        switch self {
        case .today, .planner: "我的日程"
        case .grades: "动态成绩"
        case .otherItems, .settings: nil
        case .tasks: "我的任务"
        case .attendance: "我的考勤"
        }
    }
}

enum OtherItemsSection: String, CaseIterable, Identifiable {
    case exams, evaluations, resources
    var id: Self { self }

    var title: String {
        switch self { case .exams: String(localized: "考试"); case .evaluations: String(localized: "测评"); case .resources: String(localized: "资料库") }
    }

    var emptyTitle: String {
        switch self {
        case .exams: String(localized: "暂无考试")
        case .evaluations: String(localized: "暂无测评")
        case .resources: String(localized: "暂无资料")
        }
    }

    var portalSection: String {
        switch self {
        case .exams: SchoolWorkKind.exam.portalSection
        case .evaluations: SchoolWorkKind.evaluation.portalSection
        case .resources: "我的资料库"
        }
    }

    var collection: SchoolPortalCollection {
        switch self { case .exams: .exams; case .evaluations: .evaluations; case .resources: .resources }
    }

    func campusPage(offset: Int) -> CampusPage {
        switch self {
        case .exams: .work("exam", offset: offset)
        case .evaluations: .work("evaluation", offset: offset)
        case .resources: .resources(offset: offset)
        }
    }
}

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case time, system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .time: String(localized: "跟随时段"); case .system: String(localized: "跟随系统"); case .light: String(localized: "浅色"); case .dark: String(localized: "深色") } }
}
enum GlassStyle: String, Codable, CaseIterable, Identifiable {
    case clear, regular
    var id: String { rawValue }
    var title: String { self == .clear ? String(localized: "清透") : String(localized: "标准") }
}

struct Preferences: Codable, Equatable {
    var appearance: Appearance = .time
    var glass: GlassStyle = .clear
    var weather: Weather = .cloudy
    var automaticFestival = true
    var festival: Festival = .none
    var ambientMotion = true
    var liveBackground = true
    var sceneMinute = Double(SchoolClock.minute(in: Date()))
    var remindersEnabled = false
    var reminderLead = 5
    var morningEnabled = true
    var morningMinute = 435
    var weightedGPA = true
}

/// A missing service account is not permission to use the bundled timetable.
enum CampusSource: String {
    case school, localFixture, fixtureService

    static let preferenceKey = "tschedule.qa.campusSource"
    static var initial: Self {
        #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
        return UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .school
        #else
        return .school
        #endif
    }
}

@MainActor @Observable
final class AppModel {
    var preferences: Preferences { didSet { persist() } }
    private static let personalizationKey = "tschedule.localPersonalization.v1"
    var personalization: LocalPersonalization {
        didSet {
            if oldValue != personalization, let data = try? JSONEncoder().encode(personalization) {
                UserDefaults.standard.set(data, forKey: Self.personalizationKey)
            }
        }
    }
    var tab: AppTab = .today {
        didSet { if tab != .planner { plannerDateRequest = nil } }
    }
    var otherItemsSection: OtherItemsSection = .exams
    var now = Date()
    private(set) var plannerDateRequest: Date?
    private(set) var inspectedMinute: Int?
    var selectedLesson: TimetableDetail?
    var environmentPresented = false
    var portalPresented = false
    var portalSection: String?
    var completedDemoTaskIDs: Set<String> { didSet { UserDefaults.standard.set(Array(completedDemoTaskIDs), forKey: "xiaobao.demo.completedTasks") } }
    var savedDemoResourceIDs: Set<String> { didSet { UserDefaults.standard.set(Array(savedDemoResourceIDs), forKey: "xiaobao.demo.savedResources") } }
    var provider: DemoSchoolProvider { .local }
    var gradebook: Gradebook { .demo }
    var attendance: AttendanceReport { .demo }
    private(set) var campusSource: CampusSource
    var usesLocalTimetable: Bool {
        campusSource == .localFixture && !school.selected && campus.account == nil && campus.notice == nil
    }
    let notifications = ReminderService()
    let lessonActivity = LessonActivityController()
    let cityWeather: CityWeatherStore
    let portal: PortalSession
    let school: SchoolPortalStore
    let timetable: SchoolTimetableStore
    let assignments: SchoolAssignmentStore
    let gradeCache: SchoolGradeCache
    @ObservationIgnored private let schoolNetwork = NWPathMonitor()
    private(set) var schoolNetworkAvailable = false
    private(set) var schoolContentVisible = false
    @ObservationIgnored var materialQueue: Task<Void, Never>?
    @ObservationIgnored var materialReads: [SchoolAssignmentStore.MaterialKey:(id:UUID, epoch:UUID, read:Task<SchoolTaskMaterial, Error>)] = [:]
    var timetableForeground = true
    var timetableCheckingSession = false
    let schoolLogin = SchoolPortalLoginVault()
    let campus: CampusConnection
    let planStore: PlanStore
    let courseForecasts = CourseForecastStore()
    var planDisplayRevision = UUID()
    @ObservationIgnored var planReminderOwner: PlanOwner?
    @ObservationIgnored var planReminderOwnerKnown = false
    @ObservationIgnored var planReminderRead = UUID()
    @ObservationIgnored private var checkedLaunchLogin = false
    @ObservationIgnored private var launchLoginTask: Task<Void, Never>?
    @ObservationIgnored private var gradePageActive = false
    @ObservationIgnored private var gradeReadRequested = false
    @ObservationIgnored private var gradeAwaitsDocument = false
    @ObservationIgnored private var explicitGradeVisit = false
    @ObservationIgnored private var gradeVisitTask: Task<Void, Never>?
    @ObservationIgnored private var gradeVisitID = UUID()
    private(set) var offlineGradeTerm: String?

    init() {
        var saved = UserDefaults.standard.data(forKey: "xiaobao.native.preferences.v1")
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        // Older timetable drags wrote fractional minutes into appearance settings.
        // The appearance slider and its shortcuts only save whole minutes. Leave those choices alone.
        if !saved.liveBackground, saved.sceneMinute != saved.sceneMinute.rounded() {
            saved.liveBackground = true
            saved.sceneMinute = saved.sceneMinute.rounded()
        }
        preferences = saved
        // Keep this independent of older appearance/session preferences so
        // installing the Settings update doesn't reset an existing device.
        personalization = UserDefaults.standard.data(forKey: Self.personalizationKey)
            .flatMap { try? JSONDecoder().decode(LocalPersonalization.self, from: $0) } ?? .init()
        let weatherClient = OpenMeteoClient()
        cityWeather = CityWeatherStore { city in try await weatherClient.read(city) }
        let source = CampusSource.initial
        campusSource = source
        completedDemoTaskIDs = source == .school ? [] : Set(UserDefaults.standard.stringArray(forKey: "xiaobao.demo.completedTasks") ?? [])
        savedDemoResourceIDs = source == .school ? [] : Set(UserDefaults.standard.stringArray(forKey: "xiaobao.demo.savedResources") ?? [])
        SchoolTaskDownload.clearAbandoned()
        let session = PortalSession(persistent: true)
        portal = session
        let saltKey = "xiaobao.portal.localNamespace"
        let salt = UserDefaults.standard.string(forKey: saltKey) ?? UUID().uuidString
        UserDefaults.standard.set(salt, forKey: saltKey)
        let schoolReader = SchoolPortalReader(session: session, salt: salt)
        school = SchoolPortalStore(selected: source == .school,
                                   reader: { try await schoolReader.read($0, expected: $1) })
        let supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        assignments = SchoolAssignmentStore(directory: supportRoot.appendingPathComponent("TScheduleAssignments-v1", isDirectory: true))
        timetable = SchoolTimetableStore(file: supportRoot.appendingPathComponent("TScheduleTimetable-v1", isDirectory: true)
            .appendingPathComponent("timetable.plist"))
        gradeCache = SchoolGradeCache(file: supportRoot.appendingPathComponent("TScheduleSchoolGrades-v1", isDirectory: true)
            .appendingPathComponent("grades.plist"))
        session.school = school
        if let binding = schoolLogin.binding { school.rememberComparison(binding.owner) }
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XiaobaoPages-v1", isDirectory: true)
        let gradeRoot = supportRoot.appendingPathComponent("XiaobaoGrades-v1", isDirectory: true)
        campus = CampusConnection(vault: KeychainCampusVault(), root: cacheRoot, gradeRoot: gradeRoot,
                                  restoreOnInit: source == .fixtureService)
        planStore = PlanStore(file: supportRoot.appendingPathComponent("XiaobaoPlanner-v1", isDirectory: true)
            .appendingPathComponent("plans.plist"))
        school.onAccountConfirmation = { [weak self] owner in
            guard let self else { return }
            if let owner {
                if self.assignments.hasRegistration && self.assignments.owner != owner { self.notifications.requireAssignmentRemoval() }
                if let previous = self.gradeCache.owner, previous != owner { self.offlineGradeTerm = nil }
                self.confirmReminderOwner(owner); self.timetable.verified(owner); self.assignments.verified(owner)
                self.gradeCache.verified(owner)
            } else {
                self.timetable.forget(); self.assignments.forget(); self.gradeCache.forget()
                self.offlineGradeTerm = nil; self.revokeAccountReminders()
            }
        }
        school.onGradeOverview = { [weak self] book, owner, current, checked in
            guard let self, self.canUseLiveSchool, self.school.owner == owner else { return }
            self.gradeCache.accept(book, owner: owner, current: current, checked: checked)
        }
        school.onGradeDetail = { [weak self] groups, course, term, owner in
            guard let self, self.canUseLiveSchool, self.school.owner == owner else { return }
            self.gradeCache.accept(groups: groups, course: course, term: term, owner: owner)
        }
        school.onGradeDenial = { [weak self] request in self?.gradeCache.revoke(request) }
        school.onCompleteTasks = { [weak self] list, owner, current in
            guard let self, self.school.owner == owner, self.portal.foreground,
                  !self.portalPresented, !self.portal.manualSheet else { return }
            if self.assignments.accept(list, owner: owner, current: current) {
                if let term = list.termLabel?.id { self.warmTaskMaterials(in:term) }
                Task { await self.refreshPlanReminders() }
            } else if self.assignments.enabled { self.notifications.requireAssignmentRemoval() }
        }
        school.onRevokeTasks = { [weak self] in
            guard let self, self.assignments.hasRegistration else { return }
            self.stopTaskMaterials(); self.notifications.requireAssignmentRemoval(); self.assignments.forget()
        }
        session.onForgetLogin = { [weak self] in
            guard let self else { return }
            self.timetable.forget(); self.assignments.forget(); self.gradeCache.forget()
            self.offlineGradeTerm = nil; self.revokeAccountReminders()
            self.lessonActivity.stop()
            try? self.schoolLogin.disable()
        }
        notifications.permitsSchoolDelivery = { [weak self] in
            guard let self else { return false }
            return self.timetable.lessonRemindersEnabled && self.school.selected && self.reminderAccess != .revoked
        }
        notifications.permitsPersonalDelivery = { [weak self] in
            guard let self else { return false }
            return self.reminderAccess != .revoked
        }
        notifications.permitsAssignmentDelivery = { [weak self] in
            guard let self else { return false }
            return self.canDisplaySavedAssignments && self.assignments.enabled && !self.assignments.writeFailed && self.reminderAccess != .revoked
        }
        schoolNetwork.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.schoolNetworkAvailable = online }
        }
        schoolNetwork.start(queue: DispatchQueue(label: "tschedule.school.network"))
        #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
        notifications.permitsFixtureDelivery = { [weak self] in self?.usesLocalTimetable == true }
        #endif
    }

    var timetableInstant: Date { inspectedMinute.map { SchoolClock.at(minute: $0, on: now) } ?? now }
    var minute: Int { inspectedMinute ?? SchoolClock.minute(in: now) }
    var sceneMinute: Int {
        if tab == .today, !environmentPresented, let inspectedMinute { return inspectedMinute }
        return preferences.liveBackground ? SchoolClock.minute(in: now) : Int(preferences.sceneMinute.rounded())
    }
    var skyTime: SkyTime { SkyTime(minute: sceneMinute, on: now) }
    var phase: DayPhase { skyTime.phase }
    var weatherDisplay: CityWeatherDisplay { cityWeather.display(at: now, preview: preferences.weather) }

    func previewWeather(_ weather: Weather) {
        // Keep the previous manual choice even after city updates and app restarts.
        cityWeather.setFollowsCity(false)
        preferences.weather = weather
    }
    var festival: Festival { .displayed(on: now, automatic: preferences.automaticFestival, manual: preferences.festival) }
    var colorScheme: ColorScheme? {
        switch preferences.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        case .time: phase == .night ? .dark : .light
        }
    }
    var backgroundSymbol: String {
        let weather = weatherDisplay.weather
        if weather != .sunny { return weather.symbol }
        return phase == .night ? "moon.stars" : phase == .sunset ? "sunset" : phase == .dawn ? "sunrise" : "sun.max"
    }
    func inspect(_ minute: Int) {
        let value = min(1439, max(0, minute))
        if inspectedMinute != value { inspectedMinute = value }
    }

    func returnToNow() {
        inspectedMinute = nil
        now = Date()
    }

    func previewScene(_ minute: Int) {
        preferences.liveBackground = false
        preferences.sceneMinute = Double(minute)
    }

    func openPlanner(on date: Date) {
        plannerDateRequest = SchoolClock.calendar.startOfDay(for: date)
        tab = .planner
    }

    // A date jump is consumed once; Planner owns its browsing state after landing.
    func takePlannerDateRequest() -> Date? {
        guard let date = plannerDateRequest else { return nil }
        plannerDateRequest = nil
        return date
    }

    func openNotification(_ route: NotificationRoute) {
        guard usesLocalTimetable else { return }
        openPlanner(on: route.date)
        selectedLesson = provider.lessons(on: route.date).first { $0.id == route.lessonID }.map(TimetableDetail.init)
    }

    func openPortal(section: String? = nil) {
        lessonActivity.stop()
        stopLaunchLogin()
        setGradePageActive(false)
        let signInIssue = school.owner == nil ? school.identityIssue : nil
        timetable.reviewAccount()
        assignments.reviewAccount()
        gradeCache.reviewAccount()
        offlineGradeTerm = nil
        revokeAccountReminders()
        if school.selected {
            // An account can also be changed *inside* the website. Do not show a prior
            // student's native detail between closing the sheet and verifying its owner.
            portal.cancelSchoolReads()
            school.beginManualReview()
        }
        selectSource(.school)
        portal.manualSheet = true
        if let signInIssue, !signInIssue.permitsIdentityRecheck {
            portal.openSignIn(after: signInIssue); portalSection = section
        } else { portalSection = portal.open(section) ? nil : section }
        portalPresented = true
    }

    private func selectSource(_ source: CampusSource) {
        guard source != campusSource else { return }
        if campusSource == .school { assignments.forget(); gradeCache.forget(); offlineGradeTerm = nil }
        revokeAccountReminders()
        lessonActivity.stop()
        setGradePageActive(false)
        portal.cancelSchoolReads()
        campusSource = source
        school.select(source == .school)
        #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
        UserDefaults.standard.set(source.rawValue, forKey: CampusSource.preferenceKey)
        #endif
        selectedLesson = nil
        scheduleDataCheck()
    }

    #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
    func selectLocalFixture() { selectSource(.localFixture) }

    func connectFixture(origin: String, profile: String, remember: Bool) async throws {
        // Save the intended source before connecting. Failure or relaunch must not imply "local".
        selectSource(.fixtureService)
        try await campus.connect(origin: origin, profile: profile, remember: remember)
        scheduleDataCheck()
    }

    func disconnectFixture() async throws {
        try await campus.logout()
        scheduleDataCheck()
    }
    #endif

    func finishManualPortal() async {
        portal.manualSheet = false
        // A login page is not a request to forget this device's explicit enrollment.
        if !portal.loading, SchoolPortalReader.isHome(portal.webView.url) { school.beginNavigation() }
        await checkPortalSession()
    }

    func stopLaunchLogin(resetForNextForeground: Bool = false) {
        launchLoginTask?.cancel()
        if resetForNextForeground { checkedLaunchLogin = false }
    }

    private func restoreLaunchLoginIfNeeded() {
        // Planner browsing never needs a password. Today can also prepare live records;
        // keep the student's independent startup opt-in working after process termination.
        // Neither reading the saved file nor the passive GPA operation calls this flow.
        if !schoolNetworkAvailable || (localSchoolTimetable != nil && tab == .planner) { return }
        guard !checkedLaunchLogin, !timetableCheckingSession, portal.foreground, !portal.manualSheet, !portalPresented,
              school.selected, !portal.loading, !school.isRecoveringSession else { return }
        if school.owner != nil { checkedLaunchLogin = true; return }
        guard school.identityIssue == .login || school.identityIssue == .expired,
              let binding = schoolLogin.binding, binding.restoresOnLaunch == true, !binding.paused else { return }
        checkedLaunchLogin = true
        launchLoginTask = Task { [weak self] in
            guard let self else { return }
            defer { self.launchLoginTask = nil; self.startRequestedGradeRead() }
            var used: SchoolPortalLoginVault.Binding?
            let epoch = self.school.epoch
            @MainActor func permitted() -> Bool {
                !Task.isCancelled && self.portal.foreground && !self.portalPresented && !self.portal.manualSheet &&
                self.school.selected && self.school.epoch == epoch && self.schoolLogin.binding?.id == binding.id &&
                self.schoolLogin.binding?.restoresOnLaunch == true
            }
            await self.school.restoreLogin(for: binding.owner) {
                try await self.portal.signInWithDeviceBinding(allowed: permitted) {
                    guard permitted() else { throw CancellationError() }
                    let pair = try self.schoolLogin.claim(for: binding.owner)
                    used = pair.0
                    return pair.1
                }
            }
            if let used, permitted(), self.school.owner == binding.owner { self.schoolLogin.confirm(used) }
        }
    }

    func checkPortalSession() async {
        guard canUseLiveSchool else { return }
        // Explicit action, not a timer, decides what follows a confirmed auth boundary.
        guard school.identityIssue?.permitsIdentityRecheck != false else { restoreLaunchLoginIfNeeded(); return }
        guard !school.isRecoveringSession else { return }
        if portal.webView.url == nil { portal.loadIfNeeded(); return }
        guard !portal.loading, !portal.webView.isLoading else { return }
        if let issue = portal.documentIssue(loading: false) {
            school.invalidate(issue)
        } else { await school.verify(); schoolIdentityUpdated() }
    }

    func retrySchoolIdentity() async {
        guard school.selected, portal.foreground, !school.isRecoveringSession, !portal.loading else { return }
        if gradePageActive { gradeReadRequested = true }
        if !SchoolPortalReader.isHome(portal.webView.url) || portal.errorMessage != nil { portal.reload() }
        else { await checkPortalSession() }
        startRequestedGradeRead()
    }

    func setGradePageActive(_ active: Bool) {
        guard active != gradePageActive else { return }
        gradePageActive = active
        if active { requestSchoolGrades(explicit:false) }
        else {
            gradeVisitID = UUID(); gradeReadRequested = false; gradeAwaitsDocument = false; explicitGradeVisit = false
            gradeVisitTask?.cancel(); gradeVisitTask = nil
            if launchLoginTask == nil { portal.cancelGradeEntry() }
        }
    }

    func selectSidebar(_ destination: AppTab) {
        // Scene activation, a timer and a SwiftUI remount are not a student's gesture.
        explicitGradeVisit = destination == .grades && school.selected && portal.foreground && !portalPresented
        tab = destination
        if [.tasks, .grades, .attendance, .otherItems].contains(destination), school.selected { restoreLaunchLoginIfNeeded() }
        if explicitGradeVisit && gradePageActive { requestSchoolGrades() }
    }

    func selectAcademicTerm(_ id: String) {
        offlineGradeTerm = nil
        let old = school.selectedTermID
        school.selectTerm(id)
        guard old != school.selectedTermID else { return }
        gradeVisitID = UUID(); gradeVisitTask?.cancel(); gradeVisitTask = nil
        gradeReadRequested = false; gradeAwaitsDocument = false
        if gradePageActive { requestSchoolGrades() }
    }

    func requestSchoolGrades(explicit: Bool = true, force: Bool = false) {
        guard gradePageActive, gradeVisitTask == nil, canUseLiveSchool else { return }
        school.enableTaskScoresOnGradeVisit()
        if !force, offlineGradeTerm == nil,
           school.hasRecentGrades() || cachedGradeSnapshot.map({ $0.checked.timeIntervalSinceNow > -300 }) == true { return }
        if explicit { explicitGradeVisit = true }
        gradeReadRequested = true; gradeAwaitsDocument = false; startRequestedGradeRead()
        if force && school.owner == nil && school.identityIssue != .expired { Task { await retrySchoolIdentity() } }
    }

    func schoolIdentityUpdated() {
        courseForecasts.endSession(unless: school.owner, session: school.epoch)
        restoreLaunchLoginIfNeeded()
        reconcileLessonActivitySource()
        if let binding = schoolLogin.binding,
           school.identityIssue == .changed || (school.owner != nil && school.owner != binding.owner) {
            try? schoolLogin.disable()
        }
        if (school.owner != nil && school.identityIssue == nil) || school.identityIssue == .expired { gradeAwaitsDocument = false }
        startRequestedGradeRead()
    }

    /// Consume one user visit, not each SwiftUI remount or periodic identity check.
    func startRequestedGradeRead() {
        let boundOwner = explicitGradeVisit && schoolLogin.binding?.paused == false ? schoolLogin.binding?.owner : nil
        guard launchLoginTask == nil, gradeReadRequested, !gradeAwaitsDocument, gradeVisitTask == nil, gradePageActive, tab == .grades,
              canUseLiveSchool,
              !portal.loading, !portal.webView.isLoading, !school.isRecoveringSession, !school.pending.contains(school.gradeRead),
              school.owner != nil || school.identityIssue == .expired || (boundOwner != nil && school.identityIssue == .login) else { return }
        gradeReadRequested = false; explicitGradeVisit = false
        let id = UUID(); gradeVisitID = id
        gradeVisitTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.gradeVisitID == id { self.gradeVisitTask = nil } }
            if let term = self.offlineGradeTerm, self.school.owner != nil {
                await self.school.loadTerms()
                guard !Task.isCancelled, self.gradeVisitID == id else { return }
                if self.school.terms?.terms.contains(where: { $0.id == term }) == true {
                    self.school.selectTerm(term)
                    self.offlineGradeTerm = nil
                } else if self.school.terms != nil {
                    // A previously cached archived term may be absent from the live list.
                    return
                } else { return }
            }
            var used: SchoolPortalLoginVault.Binding?
            let signIn: (@MainActor (String) async throws -> Void)? = boundOwner.map { bound in
                { expected in
                    guard expected == bound else { throw SchoolPortalIssue.changed }
                    let ticket = self.school.epoch
                    @MainActor func allowed() -> Bool {
                        !Task.isCancelled && self.gradeVisitID == id && self.gradePageActive && self.tab == .grades &&
                        self.portal.foreground && self.school.selected && !self.portalPresented && self.school.epoch == ticket
                    }
                    try await self.portal.signInWithDeviceBinding(allowed:allowed) {
                        guard allowed() else { throw CancellationError() }
                        let pair = try self.schoolLogin.claim(for:expected)
                        used = pair.0; return pair.1
                    }
                }
            }
            await self.school.openGrades(boundOwner:boundOwner, signIn:signIn) {
                guard !Task.isCancelled, self.gradeVisitID == id, self.tab == .grades,
                      self.gradePageActive, !self.portalPresented else { throw CancellationError() }
                try await self.portal.reopenForGrades()
            }
            if let used, self.gradeVisitID == id, !Task.isCancelled,
               self.school.owner == used.owner, self.school.grades != nil { self.schoolLogin.confirm(used) }
            // A document transition is not a failed sign-in. Keep this visit's intent
            // for the next verified navigation, never retry it in a tight loop.
            if self.gradeVisitID == id, self.school.issues[school.gradeRead] == .notReady || self.school.identityIssue == .notReady {
                self.gradeAwaitsDocument = true; self.gradeReadRequested = true
                self.explicitGradeVisit = boundOwner != nil && used == nil
            }
        }
    }

    var activePortalSection: String? {
        tab == .otherItems ? otherItemsSection.portalSection : tab.portalSection
    }

    /// An inactive overlay pauses interaction but keeps the current display and visit.
    /// Only a real foreground arrival starts the school-work scheduler.
    func updateSchoolScene(_ phase: ScenePhase) -> Bool {
        let arriving = phase == .active && !schoolContentVisible
        if phase != .inactive { schoolContentVisible = phase == .active }
        timetableForeground = phase == .active
        portal.foreground = timetableForeground
        return arriving
    }

    var canUseLiveSchool: Bool {
        school.selected && schoolNetworkAvailable && portal.foreground && !portalPresented && !portal.manualSheet
    }

    var canShowCachedGrades: Bool {
        school.selected && schoolContentVisible && !portalPresented && !portal.manualSheet && school.identityIssue != .changed &&
            gradeCache.owner != nil && (school.owner == nil || school.owner == gradeCache.owner)
    }

    var cachedGradeSnapshot: SchoolGradeCache.Snapshot? {
        guard canShowCachedGrades else { return nil }
        return gradeCache.snapshot(term: offlineGradeTerm ?? school.selectedTermID, verifiedOwner: school.owner)
    }

    func selectCachedGradeTerm(_ id: String) {
        guard canShowCachedGrades, gradeCache.snapshot(term: id, verifiedOwner: school.owner) != nil else { return }
        if canUseLiveSchool, school.terms?.terms.contains(where: { $0.id == id }) == true {
            selectAcademicTerm(id)
        } else {
            offlineGradeTerm = id
            if canUseLiveSchool { requestSchoolGrades(explicit: false) }
        }
    }

    var todayRotationDay: Int? {
        if school.selected {
            guard let calendar = PublishedSchoolCalendar.bundledHS else { return nil }
            return localSchoolTimetable?.calendarDay(on: now, calendar: calendar)?.teachingDay
        }
        if campus.account != nil {
            guard let schedule = campus.cachedSchedule(on: now) else { return nil }
            if let published = schedule.calendarDay { return published.day }
            return schedule.day
        }
        guard usesLocalTimetable else { return nil }
        if let published = provider.schoolCalendar.publishedDay(on: now) { return published.day }
        return provider.day(on: now)
    }

    func toggleDemoTask(_ id: String) {
        if completedDemoTaskIDs.contains(id) { completedDemoTaskIDs.remove(id) } else { completedDemoTaskIDs.insert(id) }
    }

    func toggleSavedResource(_ id: String) {
        if savedDemoResourceIDs.contains(id) { savedDemoResourceIDs.remove(id) } else { savedDemoResourceIDs.insert(id) }
    }

    private(set) var backgroundCheckStatus: String?
    static let refreshID = "cn.xiaobao.ipados.refresh"

    func scheduleDataCheck() {
        let scheduler = BGTaskScheduler.shared
        guard campusSource == .fixtureService, campus.updatePolicy == .background, campus.account?.refresh != nil else {
            scheduler.cancel(taskRequestWithIdentifier: Self.refreshID)
            backgroundCheckStatus = nil
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshID)
        let due = campus.lastFullCheck?.addingTimeInterval(48 * 3600) ?? Date()
        request.earliestBeginDate = max(due, Date().addingTimeInterval(15 * 60))
        do {
            try scheduler.submit(request)
            backgroundCheckStatus = nil
        } catch {
            backgroundCheckStatus = String(localized: "系统暂未安排后台刷新，下次打开时会检查到期的资料。")
        }
    }

    func runDataCheck() async {
        guard campusSource == .fixtureService else { return }
        await campus.scheduledRefresh()
        scheduleDataCheck()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: "xiaobao.native.preferences.v1")
    }
}
