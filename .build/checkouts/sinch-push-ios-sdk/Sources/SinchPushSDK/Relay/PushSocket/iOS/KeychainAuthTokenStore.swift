import Foundation

#if canImport(Security)
import Security

/// Keychain storage for the auth token. A JWT must not be written to `UserDefaults`.
///
/// Stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which keeps it out of backups.
///
/// `Sendable` without qualification: all state is immutable.
final class KeychainAuthTokenStore: AuthTokenStore {
    let service: String
    let account: String
    private let logger: SocketLogger

    init(
        service: String = "com.sinch.push.socket",
        account: String = "auth-token",
        logger: SocketLogger = PrintSocketLogger()
    ) {
        self.service = service
        self.account = account
        self.logger = logger
    }

    func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            // A missing item is normal on first launch. Other failures are logged and not thrown.
            if status != errSecItemNotFound {
                logger.log("keychain read failed with status \(status)", level: .error)
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.log("keychain write failed with status \(addStatus)", level: .error)
            }
        } else if status != errSecSuccess {
            logger.log("keychain update failed with status \(status)", level: .error)
        }
    }

    func clearToken() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

#else

// Without Security, the token is kept in memory.
final class SocketAuthTokenStore: AuthTokenStore, @unchecked Sendable {
    private let backing = InMemoryAuthTokenStore()

    func loadToken() -> String? { backing.loadToken() }
    func saveToken(_ token: String) { backing.saveToken(token) }
    func clearToken() { backing.clearToken() }
}

#endif

/// The store the SDK uses by default on this platform.
#if canImport(Security)
typealias SocketAuthTokenStore = KeychainAuthTokenStore
#endif
