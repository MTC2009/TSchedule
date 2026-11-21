import Foundation
#if canImport(SwiftUI)
import Observation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum CampusError: LocalizedError {
    case origin, invalidResponse, signedOut, changed, http(Int)
    var errorDescription: String? {
        switch self {
        case .origin: "请输入 HTTPS 服务地址；本机服务也可使用 http://127.0.0.1。"
        case .invalidResponse: "服务返回的数据无法读取。"
        case .signedOut: "此设备的登录已过期，请重新连接。"
        case .changed: "账号已切换。"
        case .http(let code): "服务返回 HTTP \(code)。"
        }
    }
}

@MainActor protocol CampusVault {
    func read() throws -> Data?
    func store(_ data: Data?) throws
}

struct CampusAccount: Codable, Sendable {
    let origin: URL
    let profile: String
    let scope: UUID
    var access: String
    var expires: Date
    var refresh: String?
    var refreshExpires: Date?
    var gradeCheckPolicy: CampusUpdatePolicy?
}

private struct TokenPair: Decodable {
    let access_token, expires_at: String
    let refresh_token, refresh_expires_at: String?
    func apply(to account: inout CampusAccount) throws {
        guard !access_token.isEmpty, let expires = campusInstant(expires_at) else { throw CampusError.invalidResponse }
        if let refresh_token {
            guard !refresh_token.isEmpty, let raw = refresh_expires_at, let limit = campusInstant(raw) else { throw CampusError.invalidResponse }
            account.refresh = refresh_token
            account.refreshExpires = limit
        }
        account.access = access_token
        account.expires = expires
    }
}

func campusInstant(_ text: String) -> Date? {
    (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)) ??
    (try? Date.ISO8601FormatStyle().parse(text))
}

func campusOrigin(_ text: String) throws -> URL {
    guard var c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let host = c.host?.lowercased(), !host.isEmpty, c.user == nil, c.password == nil,
          c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/",
          c.scheme == "https" || (c.scheme == "http" && ["localhost","127.0.0.1","[::1]","::1"].contains(host)) else { throw CampusError.origin }
    c.path = "/"
    guard let url = c.url else { throw CampusError.origin }
    return url
}

private final class APIRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

typealias CampusSend = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

func campusTransport() -> CampusSend {
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
    config.httpShouldSetCookies = false
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForRequest = 12
    let session = URLSession(configuration: config, delegate: APIRedirectPolicy(), delegateQueue: nil)
    return { request in
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CampusError.invalidResponse }
        return (data, http)
    }
}

#if canImport(SwiftUI)
@Observable
#endif
@MainActor final class CampusConnection {
    struct Snapshot { let content: CampusContent; let cache: CachedCampusPage }
    private(set) var account: CampusAccount?
    private(set) var pages: [CampusPage: Snapshot] = [:]
    private(set) var errors: [CampusPage: String] = [:]
    private(set) var notice: String?
    private(set) var savedGrades: SavedCampusGrades?
    private(set) var readSavedGrades = false
    private(set) var checkingGrades = false
    private(set) var gradeCheckMessage: String?
    private(set) var taskReadGeneration = UUID()
    private var offline = CampusOfflineState()
    private var localRead: Task<CampusOfflineState?, Error>?
    private var readOffline = false
    private var legacyService = false
    private enum SyncResult { case ready, legacy, failed }
    private struct SyncFlight { let id: UUID; let grades: Bool; let task: Task<SyncResult, Never> }
    private var syncFlight: SyncFlight?
    private(set) var syncIssue: String?
    var syncing: Bool { syncFlight != nil }
    var lastFullCheck: Date? { offline.check.allChecked }
    var attendanceRecords: OfflineAttendance? {
        if case .attendance(let value) = offline.data[.attendance] { return value }
        return nil
    }

    var canReadTasks: Bool {
        guard let account, (account.refreshExpires ?? account.expires) > now() else { return false }
        return offline.manifest.map { $0.parts[CampusModule.tasks.rawValue] != nil } ?? true
    }

    /// The full current-term bundle is not limited to the legacy 30-item page.
    var cachedTaskList: CampusList<CampusWork>? {
        guard canReadTasks else { return nil }
        if case .work(let rows) = offline.data[.tasks] {
            return CampusList(items: rows, total: rows.count, offset: 0, limit: rows.count)
        }
        if case .work(let page) = pages[.work("task")]?.content { return page }
        return nil
    }

    /// Filter the entire authorized snapshot, not the slices used by older services.
    func cachedOtherItems(for page: CampusPage) -> CampusContent? {
        guard let account, (account.refreshExpires ?? account.expires) > now() else { return nil }
        let key: CampusModule
        switch page {
        case .work("exam", _): key = .exams
        case .work("evaluation", _): key = .evaluations
        case .resources: key = .resources
        default: return nil
        }
        if let manifest = offline.manifest, manifest.parts[key.rawValue] == nil { return nil }
        switch offline.data[key] {
        case .work(let rows): return .work(.init(items: rows, total: rows.count, offset: 0, limit: max(1, rows.count)))
        case .resources(let rows): return .resources(.init(items: rows, total: rows.count, offset: 0, limit: max(1, rows.count)))
        default: return nil
        }
    }

    /// A manual task-term read uses the session boundary but never loads grades or persists history.
    func readTaskPage(_ query: TaskReadRequest, scope: UUID) async throws -> CampusList<CampusWork> {
        guard let current = validAccount(), current.scope == scope else { throw CampusError.changed }
        try await hydrate(current)
        guard epoch == scope else { throw CampusError.changed }
        guard canReadTasks else { throw CampusError.http(403) }
        let generation = taskReadGeneration
        let (body, response) = try await fetch(query.route, current)
        try Task.checkCancellation()
        guard epoch == scope, taskReadGeneration == generation else { throw CampusError.changed }
        guard response.statusCode == 200, canReadTasks else {
            throw CampusError.http(response.statusCode == 200 ? 403 : response.statusCode)
        }
        let directives = Self.cacheDirectives(response)
        guard directives.contains("private"), !directives.contains("no-store"),
              body.count <= CampusDiskCache.maxBody else { throw CampusError.invalidResponse }
        return try JSONDecoder().decode(CampusEnvelope<CampusList<CampusWork>>.self, from: body).data
    }

    /// Read the active account's visible dates without requesting seven pages.
    /// A directly received day can carry overrides not present in its template.
    func cachedSchedule(on date: Date) -> CampusSchedule? {
        guard let account, (account.refreshExpires ?? account.expires) > now(),
              SchoolClock.dayDate(SchoolClock.key(date)) != nil else { return nil }
        if let manifest = offline.manifest, manifest.parts[CampusModule.timetable.rawValue] == nil { return nil }
        let key = CampusPage.schedule(SchoolClock.key(date))
        let snapshot = pages[key]
        if let snapshot, snapshot.cache.tag?.hasPrefix("offline:") != true,
           case .schedule(let saved) = snapshot.content, saved.date == SchoolClock.key(date) {
            return saved
        }
        if case .timetable(let timetable) = offline.data[.timetable] { return timetable.schedule(date) }
        return nil
    }
    private var foreground = UUID()
    private var handledOpening: UUID?
    private var gradeAttemptOpening: UUID?
    private var epoch = UUID()
    private struct Flight { let id: UUID; let task: Task<Bool, Never> }
    private var requests: [CampusPage: Flight] = [:]
    private var renewal: Task<String, Error>?
    private var disk: CampusDiskCache?
    private let vault: any CampusVault
    private let root: URL
    private let gradeRoot: URL?
    private let send: CampusSend
    private let now: () -> Date

    init(vault: any CampusVault, root: URL, gradeRoot: URL? = nil, send: @escaping CampusSend = campusTransport(), now: @escaping () -> Date = Date.init) {
        self.vault = vault; self.root = root; self.gradeRoot = gradeRoot; self.send = send; self.now = now
        restore()
    }

    func restore() {
        guard account == nil else { return }
        do {
            guard let data = try vault.read() else { return }
            let stored = try JSONDecoder().decode(CampusAccount.self, from: data)
            guard try campusOrigin(stored.origin.absoluteString) == stored.origin, stored.refresh != nil else { throw CampusError.invalidResponse }
            activate(stored)
            if (stored.refreshExpires ?? .distantPast) <= now() { invalidate() }
        } catch { notice = error.localizedDescription }
    }

    private func activate(_ value: CampusAccount) {
        epoch = value.scope; account = value; notice = nil
        disk = value.refresh == nil ? nil : CampusDiskCache(root: root, scope: value.scope, gradeRoot: gradeRoot)
    }

    func connect(origin input: String, profile: String, remember: Bool = true) async throws {
        let origin = try campusOrigin(input)
        restore()
        if let current = validAccount() {
            guard current.origin == origin, current.profile == profile, (current.refresh != nil) == remember else { throw CampusError.changed }
            return
        }
        let attempt = UUID()
        epoch = attempt
        let body = try JSONSerialization.data(withJSONObject: ["profile": profile, "remember": remember])
        let pair = try await tokenRequest(origin, "demo/sessions", body)
        var new = CampusAccount(origin: origin, profile: profile, scope: attempt, access: "", expires: .distantPast)
        try pair.apply(to: &new)
        guard (new.refresh != nil) == remember else { throw CampusError.invalidResponse }
        do {
            guard epoch == attempt else { throw CampusError.changed }
            try vault.store(remember ? JSONEncoder().encode(new) : nil)
            activate(new)
        } catch {
            _ = try? await revoke(new)
            throw error
        }
    }

    private func request(_ origin: URL, _ route: String, method: String = "GET", bearer: String? = nil) throws -> URLRequest {
        guard let url = URL(string: "api/v1/" + route, relativeTo: origin)?.absoluteURL else { throw CampusError.origin }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let bearer { req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        return req
    }

    private func tokenRequest(_ origin: URL, _ route: String, _ body: Data) async throws -> TokenPair {
        var req = try request(origin, route, method: "POST")
        req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (body, http) = try await send(req)
        guard (200..<300).contains(http.statusCode) else { throw CampusError.http(http.statusCode) }
        return try JSONDecoder().decode(CampusEnvelope<TokenPair>.self, from: body).data
    }

    private func access(_ scope: UUID, rejected: String? = nil) async throws -> String {
        guard let current = account, current.scope == scope else { throw CampusError.changed }
        if current.expires > now(), current.access != rejected { return current.access }
        guard let refresh = current.refresh, (current.refreshExpires ?? .distantPast) > now() else {
            invalidate(); throw CampusError.signedOut
        }
        if let renewal { return try await renewal.value }
        let task = Task { () throws -> String in
            let body = try JSONEncoder().encode(["refresh_token": refresh])
            do {
                let pair = try await tokenRequest(current.origin, "session/refresh", body)
                guard var updated = account, updated.scope == scope else { throw CampusError.changed }
                try pair.apply(to: &updated)
                try vault.store(JSONEncoder().encode(updated))
                account = updated
                return updated.access
            } catch CampusError.http(401) {
                if epoch == scope { invalidate() }
                throw CampusError.signedOut
            }
        }
        renewal = task
        defer { if epoch == scope { renewal = nil } }
        return try await task.value
    }

    private func fetch(_ route: String, _ current: CampusAccount, tag: String? = nil, json: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var token = try await access(current.scope)
        for attempt in 0...1 {
            guard epoch == current.scope else { throw CampusError.changed }
            var req = try request(current.origin, route, method: json == nil ? "GET" : "POST", bearer: token)
            if let json {
                req.httpBody = json
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            if let tag { req.setValue(tag, forHTTPHeaderField: "If-None-Match") }
            let reply = try await send(req)
            guard epoch == current.scope else { throw CampusError.changed }
            if reply.1.statusCode != 401 { return reply }
            if attempt == 0 { token = try await access(current.scope, rejected: token) }
        }
        invalidate()
        throw CampusError.signedOut
    }

    var updatePolicy: CampusUpdatePolicy { account?.gradeCheckPolicy ?? .manual }

    func setUpdatePolicy(_ policy: CampusUpdatePolicy) async throws {
        guard var current = account else { throw CampusError.signedOut }
        guard policy != .background || current.refresh != nil else { throw CampusError.signedOut }
        current.gradeCheckPolicy = policy
        if current.refresh != nil { try vault.store(JSONEncoder().encode(current)) }
        account = current
        try await disk?.setBackgroundProtection(policy == .background)
    }

    func enteredBackground() { foreground = UUID() }

    private func validAccount() -> CampusAccount? {
        guard let current = account else { return nil }
        guard (current.refreshExpires ?? current.expires) > now() else { invalidate(); return nil }
        return current
    }

    private func hydrate(_ current: CampusAccount) async throws {
        guard !readOffline else { return }
        let store = disk
        let read = localRead ?? Task { try await store?.readOffline() }
        localRead = read
        defer { if epoch == current.scope { localRead = nil } }
        let value = try await read.value
        guard epoch == current.scope else { throw CampusError.changed }
        if !readOffline {
            readOffline = true
            if let value {
                offline = value
                try publishGrades(checked: false, previous: nil)
            }
        }
    }

    private func publishGrades(checked: Bool, previous: String?, refreshedMetadata: Bool = false) throws {
        guard case .grades(let value) = offline.data[.grades], let time = offline.check.gradesChecked else { return }
        let previousRoster = savedGrades?.roster ?? []
        let changed = savedGrades?.version != value.version
        if changed || refreshedMetadata {
            savedGrades = try value.applying(to: nil, at: offline.check.gradesUpdated ?? time)
        }
        savedGrades?.checked = time
        readSavedGrades = true
        if checked {
            if previous == nil { gradeCheckMessage = "已获取 \(value.courses.count) 门课的成绩" }
            else if changed {
                let edited = value.courses.filter { stamp in
                    !previousRoster.contains { $0.course_id == stamp.course_id && $0.revision == stamp.revision }
                }
                gradeCheckMessage = edited.count == 1 ? "\(edited[0].name) 的成绩已更新" : "成绩已更新"
            } else { gradeCheckMessage = "上次检查没有新成绩" }
            errors[.grades] = nil
        }
    }

    @discardableResult private func present(_ page: CampusPage) -> Bool {
        guard let time = offline.check.checked else { return false }
        let revisions = page.modules.compactMap { offline.versions[$0] }
        guard revisions.count == page.modules.count else { return false }
        let tag = "offline:" + revisions.joined(separator: ".")
        let previous = pages[page]
        if previous?.cache.tag == tag && previous?.cache.checked == time { return true }
        guard let content = previous?.cache.tag == tag ? previous?.content : offline.content(page) else { return false }
        publish(page, content, CachedCampusPage(body: Data(), tag: tag, checked: time, ttl: 0))
        return true
    }

    func opened() async {
        restore()
        let opening = foreground
        guard handledOpening != opening, let current = validAccount() else { return }
        handledOpening = opening
        guard updatePolicy != .manual else { return }
        do { try await hydrate(current) } catch { return }
        if offline.manifest == nil { _ = await loadGrades(current, check: false) }
        guard epoch == current.scope, foreground == opening, gradeAttemptOpening != opening,
              updatePolicy.isDue(lastChecked: offline.check.allChecked ?? (offline.manifest == nil ? savedGrades?.checked : nil), now: now()) else { return }
        _ = await checkAll()
    }

    @discardableResult func checkAll() async -> Bool {
        guard let current = validAccount() else { return false }
        gradeAttemptOpening = foreground
        let result = await synchronize(current, grades: true)
        if result == .legacy, epoch == current.scope {
            let today = SchoolClock.key(now())
            let defaults: [CampusPage] = [.grades, .courses, .attendance, .schedule(today), .calendar(today, today),
                                          .work("task"), .work("exam"), .work("evaluation"), .resources()]
            let wanted = Set(defaults).union(pages.keys)
            for page in wanted {
                guard epoch == current.scope, !Task.isCancelled else { return false }
                await legacyLoad(page, current, force: true)
            }
            guard epoch == current.scope else { return false }
            let success = wanted.allSatisfy { errors[$0] == nil }
            syncIssue = success ? nil : "部分资料暂时无法检查。"
            return success
        }
        return result == .ready
    }

    func scheduledRefresh() async {
        restore()
        guard updatePolicy == .background, let current = validAccount(), current.refresh != nil else { return }
        do { try await hydrate(current) } catch { return }
        guard epoch == current.scope, updatePolicy == .background,
              updatePolicy.isDue(lastChecked: offline.check.allChecked, now: now()), !Task.isCancelled else { return }
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return }
            _ = await checkAll()
        } onCancel: {
            Task { @MainActor in
                if self.epoch == current.scope { self.syncFlight?.task.cancel() }
            }
        }
    }

    func load(_ page: CampusPage, force: Bool = false) async {
        guard let current = validAccount() else { return }
        do { try await hydrate(current) }
        catch { if epoch == current.scope { errors[page] = error.localizedDescription }; return }
        guard epoch == current.scope else { return }
        if !force, let manifest = offline.manifest, page.modules.contains(where: { manifest.parts[$0.rawValue] == nil }) {
            errors[page] = "此账号暂无这项资料。"
            return
        }
        if page == .grades {
            if !readSavedGrades { _ = await loadGrades(current, check: false) }
            if !force { return }
            gradeAttemptOpening = foreground
        } else if present(page) && !force {
            return
        } else if pages[page] == nil, let cached = await disk?.read(page),
                  let content = try? page.decode(cached.body), epoch == current.scope, offline.manifest == nil {
            publish(page, content, cached)
        }
        guard epoch == current.scope else { return }
        if !force && page != .grades && present(page) { return }
        let result = await synchronize(current, grades: page == .grades)
        guard epoch == current.scope else { return }
        switch result {
        case .legacy: await legacyLoad(page, current, force: force)
        case .ready:
            if page == .grades ? savedGrades == nil : !present(page) { errors[page] = "所选资料暂不可用。" }
            else { errors[page] = nil }
        case .failed: errors[page] = syncIssue
        }
    }

    private func synchronize(_ current: CampusAccount, grades: Bool, confirmed: CampusManifest? = nil) async -> SyncResult {
        if legacyService { return .legacy }
        if let flight = syncFlight {
            let outcome = await flight.task.value
            guard epoch == current.scope, outcome == .ready, grades, !flight.grades else { return outcome }
            if syncFlight?.id == flight.id { syncFlight = nil }
            return await synchronize(current, grades: true, confirmed: offline.manifest)
        }
        let id = UUID()
        let task = Task { () -> SyncResult in
            do {
                try await hydrate(current)
                try Task.checkCancellation()
                if grades { checkingGrades = true }
                defer { if epoch == current.scope { checkingGrades = false } }
                return try await syncModules(current, grades: grades, confirmed: confirmed)
            } catch {
                if epoch == current.scope { syncIssue = error.localizedDescription }
                return .failed
            }
        }
        syncFlight = SyncFlight(id: id, grades: grades, task: task)
        let result = await task.value
        if syncFlight?.id == id { syncFlight = nil }
        return result
    }

    private func forgetUnavailable(_ allowed: Set<CampusModule>, manifest: CampusManifest, current: CampusAccount) async throws {
        guard epoch == current.scope else { throw CampusError.changed }
        let denied = Set(CampusModule.allCases).subtracting(allowed)
        guard !denied.isEmpty, offline.manifest != manifest || !denied.isDisjoint(with: offline.data.keys) else { return }
        var retained = offline
        retained.manifest = manifest
        retained.check.generation = UUID()
        for key in denied { retained.data[key] = nil; retained.versions[key] = nil }
        if denied.contains(.grades) {
            savedGrades = nil; readSavedGrades = true; gradeCheckMessage = nil
            retained.check.gradesChecked = nil; retained.check.gradesUpdated = nil
        }
        for page in Array(pages.keys) where !denied.isDisjoint(with: page.modules) {
            pages[page] = nil; errors[page] = "此账号暂无这项资料。"
        }
        offline = retained
        let store = disk
        await store?.removeLegacyPages()
        if denied.contains(.grades) { await store?.removeGrades() }
        do { try await store?.saveOffline(retained, changed: true, background: updatePolicy == .background) }
        catch { await store?.clearData(); throw error }
        guard epoch == current.scope else { throw CampusError.changed }
    }

    private func discardSchoolData(scope: UUID) async {
        guard epoch == scope else { return }
        if offline.manifest != nil || !offline.data.isEmpty || !pages.isEmpty {
            taskReadGeneration = UUID()
        }
        offline = CampusOfflineState(); pages.removeAll(); savedGrades = nil
        gradeCheckMessage = nil; readSavedGrades = true
        await disk?.clearData()
    }

    private func fetchManifest(_ current: CampusAccount) async throws -> CampusManifest? {
        let known = offline.manifest
        let (bytes, http) = try await fetch("offline/versions", current, tag: known?.tag)
        try Task.checkCancellation()
        let manifest: CampusManifest
        switch http.statusCode {
        case 304:
            guard let known else { throw CampusError.invalidResponse }
            manifest = known
        case 200:
            manifest = try JSONDecoder().decode(CampusEnvelope<CampusManifest>.self, from: bytes).data
        case 404 where known == nil, 501 where known == nil:
            legacyService = true
            return nil
        case 403, 404: await discardSchoolData(scope: current.scope); throw CampusError.http(http.statusCode)
        default: throw CampusError.http(http.statusCode)
        }
        guard !manifest.version.isEmpty, http.value(forHTTPHeaderField: "ETag") == manifest.tag,
              manifest.parts.values.allSatisfy({ !$0.isEmpty }) else { throw CampusError.invalidResponse }
        try await requirePrivateResponse(http, scope: current.scope)
        return manifest
    }

    private func syncModules(_ current: CampusAccount, grades: Bool, confirmed: CampusManifest?) async throws -> SyncResult {
        let wanted = grades ? Set(CampusModule.allCases) : CampusModule.ordinary
        for attempt in 0...1 {
            let manifest: CampusManifest
            if attempt == 0, let confirmed, confirmed == offline.manifest {
                manifest = confirmed
            } else {
                guard let fresh = try await fetchManifest(current) else { return .legacy }
                manifest = fresh
            }
            let allowed = Set(CampusModule.allCases.filter { manifest.parts[$0.rawValue] != nil })
            try await forgetUnavailable(allowed, manifest: manifest, current: current)
            let before = offline
            // An authorized check can recover fields dropped by the previous decoder without clearing the snapshot.
            let refreshGradeMetadata = grades && before.data[.grades] != nil &&
                before.gradeMetadataVersion != SavedCampusGrades.currentMetadataVersion
            // An older native decoder dropped task attributes even when the server had them.
            let refreshTaskMetadata = before.data[.tasks] != nil &&
                before.taskMetadataVersion != TaskCatalog.metadataVersion
            let changed = wanted.intersection(allowed).filter {
                before.data[$0] == nil || before.versions[$0] != manifest.parts[$0.rawValue] ||
                    ($0 == .grades && refreshGradeMetadata) || ($0 == .tasks && refreshTaskMetadata)
            }
            let gradesBackfilled = refreshGradeMetadata && changed.contains(.grades) &&
                before.versions[.grades] == manifest.parts[CampusModule.grades.rawValue]
            var next = before
            if !changed.isEmpty {
                struct Request: Encodable { let version: String; let parts: [String] }
                let payload = try JSONEncoder().encode(Request(version: manifest.version, parts: changed.map(\.rawValue).sorted()))
                let (body, response) = try await fetch("offline/data", current, json: payload)
                try Task.checkCancellation()
                if response.statusCode == 409 && attempt == 0 { continue }
                if response.statusCode == 403 { await discardSchoolData(scope: current.scope); throw CampusError.http(403) }
                guard response.statusCode == 200 else { throw CampusError.http(response.statusCode) }
                try await requirePrivateResponse(response, scope: current.scope)
                let download = try await CampusDownload.unpack(body)
                guard epoch == current.scope else { throw CampusError.changed }
                guard manifest.version == download.version, Set(download.parts.keys) == changed else { throw CampusError.invalidResponse }
                for (key, part) in download.parts {
                    next.data[key] = part
                    next.versions[key] = manifest.parts[key.rawValue]
                }
                if changed.contains(.tasks) { next.taskMetadataVersion = TaskCatalog.metadataVersion }
            }
            let replace = before.manifest == nil || !changed.isEmpty
            next.manifest = manifest
            next.check.checked = now()
            if replace { next.check.generation = UUID() }
            if grades {
                next.check.allChecked = next.check.checked
                if allowed.contains(.grades) { next.check.gradesChecked = next.check.checked }
                if changed.contains(.grades) {
                    next.gradeMetadataVersion = SavedCampusGrades.currentMetadataVersion
                    if !gradesBackfilled { next.check.gradesUpdated = next.check.checked }
                }
            }
            try Task.checkCancellation()
            guard epoch == current.scope else { throw CampusError.changed }
            try await disk?.saveOffline(next, changed: replace, background: updatePolicy == .background)
            guard epoch == current.scope else { throw CampusError.changed }
            offline = next
            let previous = savedGrades?.version
            try publishGrades(checked: grades, previous: previous, refreshedMetadata: gradesBackfilled)
            if changed.contains(.grades) { await disk?.removeGrades() }
            guard epoch == current.scope else { throw CampusError.changed }
            for page in Array(pages.keys) where present(page) { errors[page] = nil }
            syncIssue = nil
            return .ready
        }
        throw CampusError.http(409)
    }

    private static func cacheDirectives(_ http: HTTPURLResponse) -> [String] {
        (http.value(forHTTPHeaderField: "Cache-Control") ?? "").lowercased()
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func requirePrivateResponse(_ http: HTTPURLResponse, scope: UUID) async throws {
        guard epoch == scope else { throw CampusError.changed }
        let directives = Self.cacheDirectives(http)
        if directives.contains("no-store") { await discardSchoolData(scope: scope); throw CampusError.invalidResponse }
        guard directives.contains("private") else { throw CampusError.invalidResponse }
    }

    private func legacyLoad(_ page: CampusPage, _ current: CampusAccount, force: Bool) async {
        if let pending = requests[page] {
            let contactedServer = await pending.task.value
            guard force, !contactedServer, epoch == current.scope else { return }
            if requests[page]?.id == pending.id { requests[page] = nil }
            await legacyLoad(page, current, force: true)
            return
        }
        let flight = Flight(id: UUID(), task: Task {
            if page == .grades { return await self.loadGrades(current, check: force) }
            return await self.loadPage(page, current, force: force)
        })
        requests[page] = flight
        _ = await flight.task.value
        if requests[page]?.id == flight.id { requests[page] = nil }
    }

    // False means a fresh local value was sufficient. A concurrent pull-to-refresh can still revalidate it.
    private func loadPage(_ page: CampusPage, _ current: CampusAccount, force: Bool) async -> Bool {
        let scope = current.scope
        let disk = self.disk
        guard epoch == scope else { return false }
        if let entry = pages[page]?.cache, entry.ttl == 0 && entry.tag == nil { pages[page] = nil }
        if pages[page] == nil, let cached = await disk?.read(page),
           let content = try? page.decode(cached.body), epoch == scope {
            publish(page, content, cached)
        }
        guard epoch == scope else { return false }
        let prior = pages[page]?.cache
        if !force, let prior, prior.fresh(at: now()) { return false }
        do {
            let (body, http) = try await fetch(page.route, current, tag: prior?.tag)
            guard epoch == scope else { return true }
            let bytes: Data
            switch http.statusCode {
            case 200: bytes = body
            case 304:
                guard let prior, prior.tag != nil else { throw CampusError.invalidResponse }
                bytes = prior.body
            case 403, 404:
                pages[page] = nil
                await disk?.remove(page)
                throw CampusError.http(http.statusCode)
            default: throw CampusError.http(http.statusCode)
            }
            let directives = Self.cacheDirectives(http)
            let cacheable = directives.contains("private") && !directives.contains("no-store") && bytes.count <= CampusDiskCache.maxBody
            let ttl = directives.compactMap { $0.hasPrefix("max-age=") ? Double($0.dropFirst(8)) : nil }.first ?? 0
            let entry = CachedCampusPage(body: bytes, tag: cacheable ? http.value(forHTTPHeaderField: "ETag") : nil,
                                         checked: now(), ttl: cacheable && !directives.contains("no-cache") && ttl.isFinite ? min(86_400, max(0, ttl)) : 0)
            let content = try (http.statusCode == 304 ? pages[page]?.content : nil) ?? page.decode(bytes)
            publish(page, content, entry)
            errors[page] = nil
            if cacheable { await disk?.write(entry, for: page) } else { await disk?.remove(page) }
        } catch {
            guard epoch == scope else { return true }
            if let prior, prior.tag == nil && prior.ttl <= 0 { pages[page] = nil }
            if errors[page] == nil, errors.count >= CampusDiskCache.maxPages, let oldest = errors.keys.first { errors[oldest] = nil }
            errors[page] = error.localizedDescription
        }
        return true
    }

    private func loadGrades(_ current: CampusAccount, check: Bool) async -> Bool {
        let scope = current.scope
        let store = disk
        guard epoch == scope else { return false }
        if !readSavedGrades {
            let saved = await store?.readGrades()
            guard epoch == scope else { return false }
            if !readSavedGrades {
                savedGrades = saved
                readSavedGrades = true
            }
        }
        guard check else { return false }
        gradeAttemptOpening = foreground
        checkingGrades = true
        gradeCheckMessage = nil
        defer { if epoch == scope { checkingGrades = false } }
        do {
            let cursor = try savedGrades?.cursor() ?? Data("{}".utf8)
            let (bytes, http) = try await fetch("grades/sync", current, json: cursor)
            guard epoch == scope else { return true }
            let result: SavedCampusGrades
            switch http.statusCode {
            case 200:
                let delta = try JSONDecoder().decode(CampusEnvelope<CampusGradeChanges>.self, from: bytes).data
                result = try delta.applying(to: savedGrades, at: now())
                if savedGrades == nil {
                    gradeCheckMessage = "已获取 \(result.roster.count) 门课的成绩"
                } else if savedGrades?.version == delta.version {
                    gradeCheckMessage = "上次检查没有新成绩"
                } else if let row = delta.changed.first, delta.changed.count == 1,
                          let course = result.roster.first(where: { $0.course_id == row.course_id }) {
                    gradeCheckMessage = "\(course.name) 的成绩已更新"
                } else {
                    gradeCheckMessage = delta.changed.isEmpty ? "学期或课程信息已更新" : "已更新 \(delta.changed.count) 门课的成绩"
                }
            case 204:
                guard var verified = savedGrades, verified.version != nil,
                      verified.metadataVersion == SavedCampusGrades.currentMetadataVersion else { throw CampusError.invalidResponse }
                gradeCheckMessage = "上次检查没有新成绩"
                verified.checked = now()
                result = verified
            case 403, 404:
                savedGrades = nil
                await store?.removeGrades()
                throw CampusError.http(http.statusCode)
            default: throw CampusError.http(http.statusCode)
            }
            savedGrades = result
            errors[.grades] = nil
            let policy = Self.cacheDirectives(http)
            if policy.contains("private"), !policy.contains("no-store") {
                try await store?.writeGrades(result)
            } else { await store?.removeGrades() }
        } catch {
            if epoch == scope { errors[.grades] = error.localizedDescription }
        }
        return true
    }

    private func publish(_ page: CampusPage, _ content: CampusContent, _ cached: CachedCampusPage) {
        if pages[page] == nil, pages.count >= CampusDiskCache.maxPages,
           let oldest = pages.min(by: { $0.value.cache.checked < $1.value.cache.checked })?.key {
            pages[oldest] = nil; errors[oldest] = nil
        }
        pages[page] = Snapshot(content: content, cache: cached)
    }

    private func dropLocal() -> CampusDiskCache? {
        epoch = UUID()
        taskReadGeneration = UUID()
        syncFlight?.task.cancel(); syncFlight = nil
        localRead?.cancel(); localRead = nil
        offline = CampusOfflineState(); readOffline = false; legacyService = false; syncIssue = nil
        requests.values.forEach { $0.task.cancel() }
        requests.removeAll(); renewal?.cancel(); renewal = nil
        pages.removeAll(); errors.removeAll(); account = nil
        savedGrades = nil; readSavedGrades = false; checkingGrades = false; gradeCheckMessage = nil; gradeAttemptOpening = nil
        let previous = disk; disk = nil
        return previous
    }

    private func invalidate() {
        let previous = dropLocal()
        do { try vault.store(nil); notice = CampusError.signedOut.localizedDescription }
        catch { notice = error.localizedDescription }
        Task { await previous?.clear() }
    }

    private func revoke(_ value: CampusAccount) async throws {
        let req = try request(value.origin, "session", method: "DELETE", bearer: value.refresh ?? value.access)
        let (_, http) = try await send(req)
        guard [204, 401].contains(http.statusCode) else { throw CampusError.http(http.statusCode) }
    }

    func logout() async throws {
        guard let current = account else { return }
        try vault.store(nil)
        let previous = dropLocal()
        let loggedOut = epoch
        await previous?.clear()
        do { try await revoke(current); if epoch == loggedOut { notice = nil } }
        catch { if epoch == loggedOut { notice = "本机已退出。当前无法联系服务器撤销设备会话。" } }
    }
}
