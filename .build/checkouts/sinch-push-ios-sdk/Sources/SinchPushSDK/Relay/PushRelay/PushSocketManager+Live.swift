import UIKit

extension PushSocketManager.Dependencies {
    /// The production wiring: `URLSession` WebSocket, a serial queue, an in-memory token, local notifications.
    /// Nothing is resumed from persisted configuration, since the manager always passes it in.
    static func live(registry: SeenMessageRegistry, store: SocketStateStore,
                     relaySwitch: RelaySwitchStore,
                     scheduler: Scheduler) -> PushSocketManager.Dependencies {
        let logger = PrintSocketLogger(sink: { line, level in Self.sdkLog(line, level: level) })
        clearPersistedRelaySession(store: store, logger: logger)
        return PushSocketManager.Dependencies(
            transportFactory: URLSessionWebSocketTransportFactory(),
            scheduler: scheduler,
            random: SystemRandomSource(),
            store: clientStateStore(store),
            tokenStore: clientTokenStore(),
            presenter: SocketNotificationPresenter(),
            deliveredNotifications: SystemDeliveredNotificationLookup(),
            sessionOwner: UserDefaultsRelaySessionOwnerStore(),
            deviceInfo: SystemDeviceInfoProvider.live(logger: logger, relaySwitch: relaySwitch),
            logger: logger,
            registry: registry,
            makeLifecycle: { UIApplicationSocketLifecycle(client: $0) },
            isApplicationInBackground: { !isForeground(UIApplication.shared.applicationState) },
            installationId: { try? KeychainInstallationIdStore.shared.installationId() })
    }

    /// The `Logger` level for a socket diagnostic; warnings and errors survive production filtering.
    static func sdkLevel(for level: SocketLogLevel) -> Logger.Level {
        switch level {
        case .error: .error
        case .warning: .warning
        case .verbose: .verbose
        }
    }

    static func sdkLog(_ line: String, level: SocketLogLevel, file: String = #file, function: String = #function,
                       lineNumber: Int = #line) {
        Logger.custom(level: sdkLevel(for: level), line, file: file, function, lineNumber)
    }

    /// `.inactive` counts as foreground, since a notification can wake the app in that state.
    static func isForeground(_ state: UIApplication.State) -> Bool {
        state != .background
    }

    /// The store the client gets: the shared one, without its configuration slice.
    static func clientStateStore(_ store: SocketStateStore) -> NonPersistingConfigurationStateStore {
        NonPersistingConfigurationStateStore(wrapping: store)
    }

    /// The JWT is held in memory for the life of the process.
    static func clientTokenStore() -> AuthTokenStore {
        InMemoryAuthTokenStore()
    }

    /// Removes the relay configuration and JWT that an earlier build persisted. Called once per process.
    static func clearPersistedRelaySession(store: SocketStateStore, logger: SocketLogger) {
        KeychainAuthTokenStore(logger: logger).clearToken()
        store.clearConfiguration()
    }
}
