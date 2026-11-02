import Foundation

public struct SinchSDKConfig: Sendable {
    private let appConfig: AppConfig

    public init(appConfig: AppConfig) {
        self.appConfig = appConfig
    }

    public struct AppConfig: Codable, Sendable, Equatable {
        // swiftlint:disable:next type_name nesting
        typealias ID = String

        let clientID: ID
        let projectID: ID
        let configID: ID
        let region: Region
        let locale: Locale
        let relay: RelayOption
        let allowInsecureRelay: Bool

        /// - Parameters:
        ///   - relay: Switch for the foreground push relay connection (see ``RelayOption``).
        ///   - allowInsecureRelay: Allows a plaintext `ws://` relay URL (local development only). `wss://` is always
        ///     accepted. Independent of `Region.custom`'s `isSecure`, which switches the chat gRPC channel.
        public init(clientID: String,
                    projectID: String,
                    configID: String,
                    region: Region,
                    locale: Locale = Locale.current,
                    relay: RelayOption = .enabled,
                    allowInsecureRelay: Bool = false) {
            self.clientID = clientID
            self.projectID = projectID
            self.configID = configID
            self.region = region
            self.locale = locale
            self.relay = relay
            self.allowInsecureRelay = allowInsecureRelay
        }

        /// `relay` and `allowInsecureRelay` are absent in configs encoded before the options existed; they then default
        /// to `.enabled` and `false`.
        public init(from decoder: Swift.Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.clientID = try container.decode(ID.self, forKey: .clientID)
            self.projectID = try container.decode(ID.self, forKey: .projectID)
            self.configID = try container.decode(ID.self, forKey: .configID)
            self.region = try container.decode(Region.self, forKey: .region)
            self.locale = try container.decode(Locale.self, forKey: .locale)
            self.relay = try container.decodeIfPresent(RelayOption.self, forKey: .relay) ?? .enabled
            self.allowInsecureRelay = try container.decodeIfPresent(Bool.self, forKey: .allowInsecureRelay) ?? false
        }
    }

    /// Kill switch for the push relay: a WebSocket to the Sinch push relay that is open only while
    /// the app is in the foreground (background and terminated apps are reached through APNs).
    public enum RelayOption: String, Codable, Sendable {
        /// Connect to the relay after `setIdentity` succeeds, when the region has a relay URL.
        case enabled
        /// Never connect to the relay; push notifications arrive through APNs only.
        case disabled
    }
}
