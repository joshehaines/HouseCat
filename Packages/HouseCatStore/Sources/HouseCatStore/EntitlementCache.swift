import Foundation
import Security

/// Where the last known entitlements are mirrored for offline launches.
public protocol EntitlementCache: Sendable {
    func load() -> Entitlements?
    func save(_ entitlements: Entitlements)
}

/// Mirrors entitlements to this device's Keychain. Not synchronisable: each
/// device re-derives its own from the store.
public struct KeychainEntitlementCache: EntitlementCache {
    public var service: String
    public var account: String

    public init(service: String = "com.housecatgame.housecat.entitlements", account: String = "entitlements") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    public func load() -> Entitlements? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Entitlements.self, from: data)
    }

    public func save(_ entitlements: Entitlements) {
        guard let data = try? JSONEncoder().encode(entitlements) else { return }
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Removes the mirror ("Delete all my data", tests).
    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// For tests and previews.
public final class InMemoryEntitlementCache: EntitlementCache, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Entitlements?

    public init(_ entitlements: Entitlements? = nil) {
        stored = entitlements
    }

    public func load() -> Entitlements? {
        lock.withLock { stored }
    }

    public func save(_ entitlements: Entitlements) {
        lock.withLock { stored = entitlements }
    }
}
