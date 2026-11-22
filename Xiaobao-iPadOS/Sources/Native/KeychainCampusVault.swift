import Foundation
import Security

@MainActor struct KeychainCampusVault: CampusVault {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "cn.xiaobao.ipados.api-session.v1",
         kSecAttrAccount as String: "active-device"]
    }
    private func check(_ status: OSStatus) throws {
        if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: String(localized: "暂时无法访问钥匙串，请解锁 iPad 后重试。")])
        }
    }
    func read() throws -> Data? {
        var options = query
        options[kSecReturnData as String] = true
        options[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(options as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return value as? Data
    }
    func store(_ data: Data?) throws {
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
            return
        }
        let account = try JSONDecoder().decode(CampusAccount.self, from: data)
        let protection = account.gradeCheckPolicy == .background ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let attributes: [String: Any] = [kSecValueData as String: data,
                                        kSecAttrAccessible as String: protection]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try check(SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil))
        } else { try check(status) }
    }
}
