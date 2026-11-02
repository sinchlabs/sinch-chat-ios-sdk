import Foundation
import os

/// The inputs of the effective relay state, read by the socket manager, the Subscribe path and the runtime toggle.
///
/// The relay is effective when the configuration enables it, the runtime toggle is on and the region has a relay URL.
/// Transient states such as offline do not change it.
final class RelaySettings: @unchecked Sendable {

    /// The runtime toggle's `UserDefaults` key.
    static let enabledKey = UserDefaultsRelaySwitchStore.key

    private let toggle: UserDefaultsRelaySwitchStore
    /// The configuration of the latest `setIdentity`. Set before its token request, so a Subscribe sees it.
    private let appConfigStorage = OSAllocatedUnfairLock<SinchSDKConfig.AppConfig?>(initialState: nil)

    init(userDefaults: UserDefaults = .standard) {
        self.toggle = UserDefaultsRelaySwitchStore(defaults: userDefaults)
    }

    /// The runtime toggle, persisted. On until it is turned off.
    var isEnabled: Bool {
        toggle.isEnabled
    }

    /// - Returns: whether the value changed.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard enabled != isEnabled else { return false }
        toggle.setEnabled(enabled)
        return true
    }

    var appConfig: SinchSDKConfig.AppConfig? {
        get { appConfigStorage.withLock { $0 } }
        set { appConfigStorage.withLock { $0 = newValue } }
    }

    /// Whether this SDK runs a relay socket for `config`, and if not, why.
    func resolve(config: SinchSDKConfig.AppConfig) -> RelayResolution {
        // The host's configuration takes precedence over the runtime toggle.
        if config.relay == .enabled, !isEnabled {
            return .disabled(reason: "relay disabled at runtime (SinchPush.setRelayEnabled(false))")
        }
        return RelayEndpoint.resolve(region: config.region, option: config.relay,
                                     allowInsecure: config.allowInsecureRelay)
    }

    /// Whether the relay is effective for the latest configuration. Without one, it is not.
    var isEffective: Bool {
        guard let config = appConfig, case .enabled = resolve(config: config) else { return false }
        return true
    }

    /// The effective state as a ``RelaySwitchStore``, so `background_service` is `UNSUPPORTED` or `RELAY_DISABLED` everywhere.
    var effectiveSwitch: RelaySwitchStore { EffectiveRelaySwitch(settings: self) }
}

/// ``RelaySwitchStore`` over ``RelaySettings``: `isEnabled` is the effective state.
private final class EffectiveRelaySwitch: RelaySwitchStore {
    private let settings: RelaySettings

    init(settings: RelaySettings) {
        self.settings = settings
    }

    var isEnabled: Bool { settings.isEffective }

    func setEnabled(_ enabled: Bool) {
        settings.setEnabled(enabled)
    }
}
