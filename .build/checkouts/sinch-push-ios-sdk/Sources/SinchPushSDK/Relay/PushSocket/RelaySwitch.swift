import Foundation
import os

/// The relay off switch. Device info reports `RELAY_DISABLED` while it is off.
protocol RelaySwitchStore: AnyObject, Sendable {
    /// `true` unless something turned the relay off.
    var isEnabled: Bool { get }

    func setEnabled(_ enabled: Bool)
}

/// The `UserDefaults` store, defaulting to `true`. Not the Keychain: the value is policy, not a secret.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe and the store holds nothing else.
final class UserDefaultsRelaySwitchStore: RelaySwitchStore, @unchecked Sendable {
    static let key = "com.sinch.push.relay.enabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        // `bool(forKey:)` would read an absent key as `false`.
        guard let stored = defaults.object(forKey: Self.key) as? Bool else { return true }
        return stored
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
}

/// A non-persisting store, the default for a provider built without one.
final class InMemoryRelaySwitchStore: RelaySwitchStore {
    private let enabled: OSAllocatedUnfairLock<Bool>

    init(enabled: Bool = true) {
        self.enabled = OSAllocatedUnfairLock(initialState: enabled)
    }

    var isEnabled: Bool {
        enabled.withLock { $0 }
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled.withLock { $0 = enabled }
    }
}
