import Foundation

/// The device facts one `Hello` carries.
struct DeviceInfo: Sendable, Equatable {
    typealias BackgroundServiceState = Sinch_Push_V1beta1_Resources_BackgroundServiceState

    /// `Hello.installation_id`. Empty when unavailable; the relay treats that as a legacy client.
    var installationId: String

    /// `Hello.platform`: the websocket enum (IOS = 1), not the push API's `resources.Platform` (IOS = 3).
    var platform: Sinch_Push_Delivery_V1beta1_Ws_Platform

    var osVersion: String

    var sdkVersion: String

    var bundleId: String

    /// `Hello.background_service`: `UNSUPPORTED`, or `RELAY_DISABLED` while the relay switch is off.
    var backgroundService: BackgroundServiceState

    /// This info when the installation id is known, else `nil`. `Subscribe` sends no device field without it.
    var subscribable: DeviceInfo? {
        installationId.isEmpty ? nil : self
    }

    /// The relay's byte cap on `os_version`, `bundle_id` and `sdk_version`. An over-long
    /// value rejects the `Hello` rather than being truncated, so the SDK clamps first.
    static let maxDeviceInfoValueBytes = 128

    /// The longest prefix of whole `Character`s within the UTF-8 byte limit.
    ///
    /// Bytes, not `count`: a multi-byte character must not let 128 characters through as
    /// a longer field.
    ///
    /// - Returns: `value` itself when it fits, otherwise a prefix of it.
    static func clampedUTF8(_ value: String, maxBytes: Int = DeviceInfo.maxDeviceInfoValueBytes) -> String {
        guard value.utf8.count > maxBytes else { return value }
        var kept = ""
        kept.reserveCapacity(maxBytes)
        var used = 0
        for character in value {
            let width = character.utf8.count
            if used + width > maxBytes { break }
            kept.append(character)
            used += width
        }
        return kept
    }
}

/// Source of ``DeviceInfo``, injected into the client so a test can supply one.
protocol DeviceInfoProviding: AnyObject, Sendable {
    /// The facts as they are now. Called once per `Hello` and never cached, so an
    /// installation id unavailable on one connect is retried on the next.
    ///
    /// - Parameter sdkVersionOverride: `SocketConfiguration.sdkVersion`. `nil` or empty
    ///   selects ``SocketConfiguration/defaultSDKVersion``.
    func current(sdkVersionOverride: String?) -> DeviceInfo
}

extension DeviceInfoProviding {
    /// The facts without an sdk-version override, as used by `Subscribe`.
    func current() -> DeviceInfo { current(sdkVersionOverride: nil) }
}

final class SystemDeviceInfoProvider: DeviceInfoProviding {
    private let installationId: @Sendable () throws -> String
    private let osVersion: @Sendable () -> String
    private let bundleId: @Sendable () -> String
    private let logger: SocketLogger
    private let relaySwitch: RelaySwitchStore

    /// - Parameters:
    ///   - installationId: the store's `installationId()`. A throw is logged and becomes an empty id.
    ///   - osVersion: defaults to ``systemOSVersion()``.
    ///   - bundleId: defaults to `Bundle.main.bundleIdentifier`.
    ///   - relaySwitch: the relay off switch. Defaults to an in-memory "on".
    init(
        installationId: @escaping @Sendable () throws -> String,
        osVersion: @escaping @Sendable () -> String = SystemDeviceInfoProvider.systemOSVersion,
        bundleId: @escaping @Sendable () -> String = { Bundle.main.bundleIdentifier ?? "" },
        logger: SocketLogger = SilentSocketLogger(),
        relaySwitch: RelaySwitchStore = InMemoryRelaySwitchStore()
    ) {
        self.installationId = installationId
        self.osVersion = osVersion
        self.bundleId = bundleId
        self.logger = logger
        self.relaySwitch = relaySwitch
    }

    func current(sdkVersionOverride: String?) -> DeviceInfo {
        let id: String
        do {
            id = try installationId()
        } catch {
            // Sent as an empty id. The next Hello asks the store again.
            logger.log("installation id unavailable, sending Hello without it: \(error)", level: .error)
            id = ""
        }
        return DeviceInfo(
            installationId: id,
            platform: SocketConfiguration.platform,
            osVersion: DeviceInfo.clampedUTF8(osVersion()),
            sdkVersion: DeviceInfo.clampedUTF8(SocketConfiguration.resolveSDKVersion(sdkVersionOverride)),
            bundleId: DeviceInfo.clampedUTF8(bundleId()),
            // The relay off switch overrides the constant `UNSUPPORTED`.
            backgroundService: relaySwitch.isEnabled ? .unsupported : .relayDisabled)
    }

    // MARK: - OS version

    /// `ProcessInfo` is thread-safe, unlike `UIDevice.current.systemVersion`, which is main-actor isolated.
    static func systemOSVersion() -> String {
        return formatOSVersion(ProcessInfo.processInfo.operatingSystemVersion)
    }

    /// `major.minor`, plus `.patch` only when non-zero, matching `UIDevice.systemVersion`.
    static func formatOSVersion(_ version: OperatingSystemVersion) -> String {
        var text = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion != 0 { text += ".\(version.patchVersion)" }
        return text
    }
}

/// A provider with fixed values. The core default, so it never reads the installation store.
final class StaticDeviceInfoProvider: DeviceInfoProviding {
    let installationId: String
    let osVersion: String
    let bundleId: String

    init(installationId: String = "", osVersion: String = "", bundleId: String = "") {
        self.installationId = installationId
        self.osVersion = osVersion
        self.bundleId = bundleId
    }

    func current(sdkVersionOverride: String?) -> DeviceInfo {
        return DeviceInfo(
            installationId: installationId,
            platform: SocketConfiguration.platform,
            osVersion: DeviceInfo.clampedUTF8(osVersion),
            sdkVersion: DeviceInfo.clampedUTF8(SocketConfiguration.resolveSDKVersion(sdkVersionOverride)),
            bundleId: DeviceInfo.clampedUTF8(bundleId),
            backgroundService: .unsupported)
    }
}
