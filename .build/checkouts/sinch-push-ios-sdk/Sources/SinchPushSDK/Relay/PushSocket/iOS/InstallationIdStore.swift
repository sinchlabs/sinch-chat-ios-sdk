import Foundation

#if canImport(Security)
import Security
#endif

/// What reading the persisted slot produced.
enum InstallationIdLoad {
    /// The slot holds this id.
    case found(String)
    /// The slot is empty: first launch, or the item was deleted.
    case absent
    /// The slot could not be read, for example a locked Keychain before first unlock.
    /// The id may still be there, so nothing is minted over it.
    case unavailable(reason: String)
}

/// The install's id could not be produced. Callers send without one and do not treat it as a new install.
enum InstallationIdError: Error, CustomStringConvertible, Equatable {
    /// The slot could not be read, or a new id could not be persisted.
    case unavailable(reason: String)

    var description: String {
        switch self {
        case .unavailable(let reason):
            return "installation id unavailable: \(reason)"
        }
    }
}

/// The per-install identity. There is deliberately no setter: an id that could be set could be rotated.
protocol InstallationIdStore: AnyObject, Sendable {
    /// The install's lowercase canonical UUID. Generated and persisted on first call, then stable.
    ///
    /// - Throws: ``InstallationIdError/unavailable(reason:)`` when the slot cannot be read or
    ///   a new id cannot be persisted. Nothing is generated, saved or cached in that case.
    func installationId() throws -> String
}

protocol InstallationIdBacking: AnyObject, Sendable {
    func loadInstallationId() -> InstallationIdLoad

    /// Writes the id. Returns whether it reached storage.
    @discardableResult
    func saveInstallationId(_ id: String) -> Bool
}

/// An in-memory slot, used without the Security framework and by tests as "the Keychain".
final class InMemoryInstallationIdBacking: InstallationIdBacking, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    init(id: String? = nil) {
        self.stored = id
    }

    /// The slot's contents, for tests.
    var storedId: String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func loadInstallationId() -> InstallationIdLoad {
        lock.lock()
        defer { lock.unlock() }
        guard let stored else { return .absent }
        return .found(stored)
    }

    func saveInstallationId(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        stored = id
        return true
    }
}

/// Generates the id once and persists it, in the Keychain by default.
///
/// Load-or-generate is one critical section. Otherwise two first callers could mint
/// two ids, and the loser would overwrite the winner's.
///
/// `@unchecked Sendable`: `resolved` is only touched under `lock`.
final class KeychainInstallationIdStore: InstallationIdStore, @unchecked Sendable {
    /// Shared so the lock covers the whole process. A second store over the same
    /// item would race on the same first call.
    static let shared = KeychainInstallationIdStore()

    private let backing: InstallationIdBacking
    private let generate: @Sendable () -> String
    private let logger: SocketLogger

    private let lock = NSLock()
    /// Cached after the first call. Only a value that is in storage is cached.
    private var resolved: String?

    /// - Parameters:
    ///   - backing: the slot. `nil` is the Keychain, or an in-memory slot without Security.
    ///   - generate: the id factory. Tests use it to count generations.
    init(
        backing: InstallationIdBacking? = nil,
        generate: @escaping @Sendable () -> String = KeychainInstallationIdStore.newIdentifier,
        logger: SocketLogger = PrintSocketLogger()
    ) {
        self.backing = backing ?? KeychainInstallationIdStore.makeDefaultBacking(logger: logger)
        self.generate = generate
        self.logger = logger
    }

    /// Lowercase, because the relay and the tests compare lowercase.
    static func newIdentifier() -> String {
        UUID().uuidString.lowercased()
    }

    /// Lowercase canonical UUID. A stored uppercase id is normalised, not regenerated.
    static func isCanonicalInstallationId(_ value: String) -> Bool {
        value.range(of: Self.canonicalPattern, options: .regularExpression) != nil
    }

    func installationId() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if let resolved { return resolved }

        let persisted: String?
        switch backing.loadInstallationId() {
        case .unavailable(let reason):
            // An unreadable slot is not an empty one, so nothing is minted over it.
            throw InstallationIdError.unavailable(reason: reason)
        case .found(let stored):
            let normalised = stored.lowercased()
            persisted = Self.isCanonicalInstallationId(normalised) ? normalised : nil
        case .absent:
            persisted = nil
        }

        if let persisted {
            resolved = persisted
            return persisted
        }
        return try generateAndPersist()
    }

    /// Mints and persists the id. It is cached only after storage confirms the write.
    private func generateAndPersist() throws -> String {
        let id = generate()
        guard backing.saveInstallationId(id) else {
            logger.log("could not persist the installation id; reporting it as unavailable", level: .error)
            throw InstallationIdError.unavailable(reason: "the installation id could not be persisted")
        }
        resolved = id
        return id
    }

    private static func makeDefaultBacking(logger: SocketLogger) -> InstallationIdBacking {
        #if canImport(Security)
        return KeychainInstallationIdBacking(logger: logger)
        #else
        return InMemoryInstallationIdBacking()
        #endif
    }

    /// Written out, so the check is the contract's shape.
    private static let canonicalPattern =
        "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
}

#if canImport(Security)

/// The Keychain item `com.sinch.push` / `installation-id`.
///
/// Device-only and non-migrating, like the auth token. The socket is foreground-only.
///
/// `Sendable` without qualification: all state is immutable.
final class KeychainInstallationIdBacking: InstallationIdBacking {
    static let defaultService = "com.sinch.push"
    static let defaultAccount = "installation-id"

    private let service: String
    private let account: String
    private let logger: SocketLogger

    init(
        service: String = KeychainInstallationIdBacking.defaultService,
        account: String = KeychainInstallationIdBacking.defaultAccount,
        logger: SocketLogger = PrintSocketLogger()
    ) {
        self.service = service
        self.account = account
        self.logger = logger
    }

    func loadInstallationId() -> InstallationIdLoad {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let outcome = Self.classify(status: status, data: item as? Data)
        switch outcome {
        case .unavailable:
            logger.log("installation id keychain read failed with status \(status)", level: .error)
        case .found(let value) where value.isEmpty && status == errSecSuccess:
            logger.log("the installation id keychain item is not readable as text", level: .error)
        default:
            break
        }
        return outcome
    }

    /// Maps a `SecItemCopyMatching` result to a load outcome. Pure, so it is testable without a Keychain.
    ///
    /// Only `errSecItemNotFound` means "no id". Every other failure is ``InstallationIdLoad/unavailable(reason:)``,
    /// including `errSecInteractionNotAllowed` before the first unlock. An unreadable item is `.found("")`, so it can be replaced.
    static func classify(status: OSStatus, data: Data?) -> InstallationIdLoad {
        switch status {
        case errSecSuccess:
            guard let data, let value = String(data: data, encoding: .utf8) else {
                return .found("")
            }
            return .found(value)
        case errSecItemNotFound:
            return .absent
        default:
            return .unavailable(reason: "the keychain returned status \(status)")
        }
    }

    @discardableResult
    func saveInstallationId(_ id: String) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(id.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus == errSecSuccess { return true }
            logger.log("installation id keychain write failed with status \(addStatus)", level: .error)
            return false
        }
        if status != errSecSuccess {
            logger.log("installation id keychain update failed with status \(status)", level: .error)
            return false
        }
        return true
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif
