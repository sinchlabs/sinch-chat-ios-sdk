import Foundation

/// Keeps the last `AppConfig` `setIdentity` succeeded with, so a launch the system starts in the background can
/// report deliveries before the host calls `setIdentity`. The config holds no secret: the token stays in the Keychain.
final class StoredAppConfigStore: @unchecked Sendable {
    private enum Key {
        static let appConfig = "com.sinch.push.deliveryReports.appConfig"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SinchSDKConfig.AppConfig? {
        guard let data = defaults.data(forKey: Key.appConfig) else { return nil }
        return try? JSONDecoder().decode(SinchSDKConfig.AppConfig.self, from: data)
    }

    func save(_ config: SinchSDKConfig.AppConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Key.appConfig)
    }

    func clear() {
        defaults.removeObject(forKey: Key.appConfig)
    }
}

/// Rebuilds the delivery-report session of the last identity from the stored config and the Keychain token.
struct DeliveryReportSessionRestorer {
    /// What a restored session was built for.
    struct Restored {
        let config: SinchSDKConfig.AppConfig
        let identity: SinchSDKIdentity
        let token: AuthModel
    }

    var configStore: StoredAppConfigStore
    /// The storage the config's token is in.
    var authStorage: (SinchSDKConfig.AppConfig) -> AuthStorage = { KeychainAuthStorage(config: $0) }
    var authClient: (Region) -> ChatAuthClient? = { ChatAuthClient(region: $0) }
    var pushClient: (Region) -> PushAPIClient?

    /// Gives `reporter` the session of the stored config, when the storage still holds its token.
    /// Only the reporter is touched: the chat and the push relay stay off until `setIdentity` runs.
    func restore(into reporter: DeliveryReporter) -> Restored? {
        guard let config = configStore.load() else { return nil }
        let storage = authStorage(config)
        guard let token = storage.read(), let authClient = authClient(config.region) else { return nil }
        let authDataSource = DefaultAuthDataSource(
            authRepository: DefaultAuthRepository(config: config, client: authClient),
            authStorage: storage)
        reporter.setSession(authDataSource: authDataSource, client: pushClient(config.region),
                            reportBaseURL: config.region.pushReportBaseURL)
        return Restored(config: config, identity: token.sinchIdentity, token: token)
    }
}
