import Foundation
import Observation
import Security

/// Only ever constructed for a login name obtained from the already verified student.
struct SchoolPortalLoginSecret: Codable, CustomStringConvertible, CustomDebugStringConvertible {
    let name: String
    let password: String
    var description: String { "<private school credential>" }
    var debugDescription: String { description }
}

enum SchoolPortalEnrollmentError: Error, LocalizedError {
    case storage, invalid, identity
    var errorDescription: String? {
        switch self {
        case .storage: "无法使用本机钥匙串。请确认 iPad 已设置锁屏密码，解锁后再试。"
        case .invalid: "请输入有效的校宝密码。"
        case .identity: "校宝未能确认当前学生的登录名，未保存密码。"
        }
    }
}

/// One private Keychain item. The preference contains only a random installation
/// registration, not an account identifier, password, session grant or grade.
@MainActor @Observable final class SchoolPortalLoginVault {
    struct Binding: Codable, Equatable {
        let id: UUID
        let owner: String
        var paused: Bool
    }

    private(set) var binding: Binding?
    private(set) var registered = false
    private let defaults: UserDefaults
    private let preference = "xiaobao.schoolLogin.registration.v1"
    private let pendingRemoval = "xiaobao.schoolLogin.erasePending.v1"
    private let service: String
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        service = (Bundle.main.bundleIdentifier ?? "TSchedule") + ".school-login.v1"
        refresh()
    }

    private var query: [String:Any] {
        [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service,
         kSecAttrAccount as String:"enrolled-student", kSecAttrSynchronizable as String:false]
    }
    private func requireOK(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw SchoolPortalEnrollmentError.storage }
    }
    private func metadata() throws -> Binding? {
        guard let registered = defaults.string(forKey: preference) else { return nil }
        var q = query; q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let result = SecItemCopyMatching(q as CFDictionary, &item)
        if result == errSecItemNotFound { return nil }; try requireOK(result)
        guard let info = item as? [String:Any],
              info[kSecAttrAccessible as String] as? String == (kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String),
              let bytes = info[kSecAttrGeneric as String] as? Data,
              let header = try? JSONDecoder().decode(Binding.self, from: bytes),
              header.id.uuidString == registered else { return nil }
        return header
    }
    func refresh() {
        registered = defaults.string(forKey:preference) != nil
        if defaults.bool(forKey:pendingRemoval) { try? disable(); return }
        binding = try? metadata()
    }

    func enable(owner: String, name: String, password: String) throws {
        guard owner.utf8.count == 64, !name.isEmpty, name.utf8.count <= 512 else { throw SchoolPortalEnrollmentError.identity }
        guard !password.isEmpty, password.utf8.count <= 1024 else { throw SchoolPortalEnrollmentError.invalid }
        let header = Binding(id: UUID(), owner: owner, paused: false)
        let fields: [String:Any] = [
            kSecAttrAccessible as String:kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            kSecAttrGeneric as String:try JSONEncoder().encode(header),
            kSecValueData as String:try JSONEncoder().encode(SchoolPortalLoginSecret(name:name, password:password))]
        let status = SecItemUpdate(query as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            try requireOK(SecItemAdd(query.merging(fields) { _,new in new } as CFDictionary,nil))
        } else { try requireOK(status) }
        defaults.removeObject(forKey:pendingRemoval)
        defaults.set(header.id.uuidString, forKey: preference); registered = true; binding = header
    }

    /// Persist the pause *before* releasing the secret. Repeated tabs, crashes and
    /// relaunches cannot repeatedly submit a wrong password and lock a school account.
    func claim(for owner: String) throws -> (Binding, SchoolPortalLoginSecret) {
        guard var header = try metadata(), header.owner == owner, !header.paused else { throw SchoolPortalIssue.login }
        header.paused = true; try update(header)
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?; try requireOK(SecItemCopyMatching(q as CFDictionary, &value))
        guard let bytes = value as? Data, let secret = try? JSONDecoder().decode(SchoolPortalLoginSecret.self, from: bytes)
        else { throw SchoolPortalEnrollmentError.storage }
        return (header, secret)
    }

    /// Only the caller that independently reverified this student and read fresh grades may re-arm.
    func confirm(_ claim: Binding) {
        guard var current = try? metadata(), current == claim, current.paused else { return }
        current.paused = false; try? update(current) // On failure, leave paused.
    }
    private func update(_ header: Binding) throws {
        let fields: [String:Any] = [kSecAttrGeneric as String:try JSONEncoder().encode(header)]
        try requireOK(SecItemUpdate(query as CFDictionary, fields as CFDictionary)); binding = header
    }

    /// Invalidate the local authorization first, even if protected data became locked.
    func disable() throws {
        defaults.set(true, forKey:pendingRemoval)
        defaults.removeObject(forKey: preference); registered = false; binding = nil
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try requireOK(status) }
        defaults.removeObject(forKey:pendingRemoval)
    }
}
