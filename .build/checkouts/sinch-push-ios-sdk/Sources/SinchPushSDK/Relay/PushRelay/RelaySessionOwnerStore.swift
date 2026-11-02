import Foundation

/// Persists the owner of the relay outbox and replay cursor.
protocol RelaySessionOwnerStoring: AnyObject, Sendable {
    func loadOwner() -> String?
    /// `nil` removes it.
    func saveOwner(_ owner: String?)
}

/// `UserDefaults`-backed. `UserDefaults` is thread-safe.
final class UserDefaultsRelaySessionOwnerStore: RelaySessionOwnerStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "com.sinch.push.socket.sessionOwner"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadOwner() -> String? {
        defaults.string(forKey: Self.key)
    }

    func saveOwner(_ owner: String?) {
        if let owner {
            defaults.set(owner, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
