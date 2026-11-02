import Foundation
import Combine
import UIKit

/// Main-actor owner of the process's one foreground relay session.
///
/// The core client runs on its own scheduler. Everything it reports is hopped to
/// the main queue in order, where this class lives.
@MainActor
final class PushSocketManager {

    struct Dependencies {
        var transportFactory: SocketTransportFactory
        var scheduler: Scheduler
        var random: RandomSource
        var store: SocketStateStore
        var tokenStore: AuthTokenStore
        var presenter: NotificationPresenting
        var deliveredNotifications: DeliveredNotificationLookup
        var sessionOwner: RelaySessionOwnerStoring
        var deviceInfo: DeviceInfoProviding
        var logger: SocketLogger
        var registry: SeenMessageRegistry
        var makeLifecycle: @MainActor (SocketClient) -> AppLifecycleObserving
        var isApplicationInBackground: @MainActor () -> Bool
        var installationId: @Sendable () -> String?
    }

    let stateSubject: CurrentValueSubject<SinchPushSocketState, Never>
    let messageSubject = PassthroughSubject<SinchPushSocketMessage, Never>()

    /// The client of the current session. A new one is made per session, because the core allows one credential refresh per `start()`.
    private(set) var client: SocketClient
    /// Called after a refreshed access token was adopted.
    var onAccessTokenRefreshed: (() -> Void)?
    let registry: SeenMessageRegistry

    private let dependencies: Dependencies
    private let settings: RelaySettings
    private let presenter: NotificationPresenting
    private var lifecycle: AppLifecycleObserving?
    private var authDataSource: AuthDataSource?
    private var appConfig: SinchSDKConfig.AppConfig?
    private var appIdentity: SinchSDKIdentity?
    /// The latest authorised token of the identity. An expired one costs one `auth_required` round trip.
    private var appAuth: AuthModel?
    /// `appID|projectID|userID` of the session that owns the store's outbox and cursor. `nil` after `removeIdentity`.
    private(set) var sessionOwner: String?
    private var cachedInstallationId: String?
    /// The configuration the client runs with. `nil` means no relay session.
    private(set) var socketConfiguration: SocketConfiguration?
    /// Incremented when a session ends or its identity changes, so a late token refresh can detect it is stale.
    private var sessionID = 0
    /// Identifies the current client. Callbacks from a retired client are ignored.
    private var clientGeneration = 0

    var state: SinchPushSocketState { stateSubject.value }

    /// - Parameters:
    ///   - settings: the runtime toggle and the configuration the relay state is derived from.
    ///   - showInApp: shows a relay message in the app when it is an in-app message.
    init(dependencies: Dependencies, settings: RelaySettings, showInApp: @escaping @MainActor @Sendable ([String: String]) -> Bool) {
        self.dependencies = dependencies
        self.settings = settings
        self.registry = dependencies.registry
        self.sessionOwner = dependencies.sessionOwner.loadOwner()
        self.presenter = InAppRoutingNotificationPresenter(inner: dependencies.presenter, showInApp: showInApp)
        self.stateSubject = CurrentValueSubject(
            SinchPushSocketState(status: .idle, relayEnabled: false,
                                 disabledReason: "relay not started (setIdentity has not succeeded yet)"))
        self.client = PushSocketManager.makeClient(dependencies, presenter: presenter, configuration: nil)
        install(callbacks: client, generation: clientGeneration)
    }

    private static func makeClient(_ dependencies: Dependencies,
                                   presenter: NotificationPresenting,
                                   configuration: SocketConfiguration?) -> SocketClient {
        SocketClient(
            configuration: configuration,
            transportFactory: dependencies.transportFactory,
            scheduler: dependencies.scheduler,
            random: dependencies.random,
            store: dependencies.store,
            tokenStore: dependencies.tokenStore,
            presenter: presenter,
            logger: dependencies.logger,
            deviceInfo: dependencies.deviceInfo,
            deliveredNotifications: dependencies.deliveredNotifications,
            seenRegistry: dependencies.registry)
    }

    /// Callbacks arrive on the core's scheduler and hop to the main queue, which preserves their order.
    private func install(callbacks client: SocketClient, generation: Int) {
        client.setCallbacks(SocketClient.Callbacks(
            onState: { [weak self] state in
                guard let self else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard generation == self.clientGeneration else { return }
                        self.handle(state: state)
                    }
                }
            },
            onMessage: { [weak self] message in
                guard let self else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard generation == self.clientGeneration else { return }
                        self.handle(message: message)
                    }
                }
            },
            onLog: nil,
            onAuthRequired: { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard generation == self.clientGeneration else { return }
                        self.handleAuthRequired()
                    }
                }
            }))
    }

    /// Retires the previous client, which then writes nothing to the store its successor shares.
    private func replaceClient(configuration: SocketConfiguration?) {
        clientGeneration += 1
        client.clearPendingMessages()
        client.retire()
        client = PushSocketManager.makeClient(dependencies, presenter: presenter, configuration: configuration)
        install(callbacks: client, generation: clientGeneration)
    }

    // MARK: - Identity lifecycle

    /// Starts, or updates, the relay after `setIdentity` succeeded.
    ///
    /// The same identity with an unchanged token does nothing. A changed token updates the session.
    func start(config: SinchSDKConfig.AppConfig, auth: AuthModel, authDataSource: AuthDataSource) {
        self.authDataSource = authDataSource
        self.appConfig = config
        self.appIdentity = auth.sinchIdentity
        self.appAuth = auth

        switch settings.resolve(config: config) {
        case .disabled(let reason):
            Logger.info("push relay disabled: \(reason)")
            let wasRunning = socketConfiguration != nil
            endSession()
            publish(SinchPushSocketState(status: wasRunning ? .stopped : .idle, relayEnabled: false,
                                         disabledReason: reason))
        case .enabled(let url):
            switch SocketConfiguration.relay(url: url, auth: auth, config: config) {
            case .failure(let error):
                Logger.warning("push relay not started: \(error)")
                endSession()
                publish(SinchPushSocketState(status: .error, relayEnabled: true, lastError: error.description))
            case .success(let configuration):
                activate(configuration)
            }
        }
    }

    /// The runtime toggle changed. Does nothing before an identity is authorised, since the next `start` reads the toggle.
    func relayEnabledDidChange() {
        guard let appConfig, let appAuth, let authDataSource else { return }
        start(config: appConfig, auth: appAuth, authDataSource: authDataSource)
    }

    /// Stops the relay for good (`removeIdentity`). Clears the outbox and cursor, which belong to the removed identity.
    func stop() {
        let wasRunning = socketConfiguration != nil
        endSession()
        authDataSource = nil
        appConfig = nil
        appIdentity = nil
        appAuth = nil
        sessionOwner = nil
        replaceClient(configuration: nil)
        client.resetSessionState()
        let ownerStore = dependencies.sessionOwner
        dependencies.scheduler.perform { ownerStore.saveOwner(nil) }
        publish(SinchPushSocketState(status: wasRunning ? .stopped : .idle, relayEnabled: false,
                                     disabledReason: "identity removed"))
    }

    /// `setIdentity` is starting for `config` and `identity`. A relay for another identity is stopped now,
    /// so a failed `setIdentity` cannot leave the old relay running.
    func identityWillChange(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity) {
        guard appConfig != config || appIdentity != identity else { return }
        let wasRunning = socketConfiguration != nil
        if wasRunning {
            Logger.info("push relay stopped: setIdentity for a different identity or configuration")
            endSession()
        }
        authDataSource = nil
        appConfig = nil
        appIdentity = nil
        appAuth = nil
        if wasRunning {
            publish(SinchPushSocketState(status: .stopped, relayEnabled: false,
                                         disabledReason: "identity changing (setIdentity in progress)"))
        }
    }

    private func activate(_ configuration: SocketConfiguration) {
        if let current = socketConfiguration, current.isSameSession(as: configuration) {
            if current.authToken == configuration.authToken, !isTerminal(state.status) {
                Logger.verbose("push relay already running for this identity")
                return
            }
            if !isTerminal(state.status) {
                // Same identity, new token: reconnect with a fresh Hello.
                sessionID += 1
                socketConfiguration = configuration
                client.updateConfiguration(configuration)
                suspendIfInBackground()
                return
            }
            // A terminal state is retried as a clean session.
        }
        // A new identity, or a retry from a terminal state. The new client gets its own credential refresh.
        sessionID += 1
        socketConfiguration = configuration
        replaceClient(configuration: configuration)
        adoptSessionState(for: configuration)
        // The lifecycle observer drives one client, so it is rebuilt with each one.
        lifecycle?.stopObserving()
        let observer = dependencies.makeLifecycle(client)
        observer.startObserving()
        lifecycle = observer
        client.start()
        suspendIfInBackground()
    }

    /// Clears the outbox and cursor when the session owner changes. Otherwise reloads them.
    private func adoptSessionState(for configuration: SocketConfiguration) {
        let owner = configuration.sessionOwnerKey
        if sessionOwner == owner {
            client.reloadSessionState()
        } else {
            Logger.info("push relay: new session owner, clearing the outbox and the replay cursor")
            client.resetSessionState()
        }
        sessionOwner = owner
        let ownerStore = dependencies.sessionOwner
        dependencies.scheduler.perform { ownerStore.saveOwner(owner) }
    }

    /// Ends the session. The configuration is dropped first, so queued events are ignored.
    private func endSession() {
        sessionID += 1
        socketConfiguration = nil
        lifecycle?.stopObserving()
        lifecycle = nil
        client.stop()
        client.clearPendingMessages()
        let tokenStore = dependencies.tokenStore
        let store = dependencies.store
        dependencies.scheduler.perform {
            tokenStore.clearToken()
            store.clearConfiguration()
        }
    }

    private func suspendIfInBackground() {
        // A relay started in the background must not hold a socket. The next foreground transition resumes it.
        if dependencies.isApplicationInBackground() {
            client.suspend()
        }
    }

    /// States the client does not leave on its own.
    private func isTerminal(_ status: SinchPushSocketStatus) -> Bool {
        switch status {
        case .authRequired, .replaced, .stopped, .error: return true
        default: return false
        }
    }

    // MARK: - Host entry points

    /// Reports a status for a relay message. It is queued while the socket is not connected.
    func reportStatus(messageId: String, status: SinchPushMessageStatus) {
        guard !messageId.isEmpty else {
            Logger.warning("reportStatus ignored: empty message id")
            return
        }
        // Without an owner, a queued report would be sent to whoever signs in next.
        guard sessionOwner != nil else {
            Logger.warning("reportStatus dropped: no identity (message \(messageId))")
            return
        }
        client.report(messageId: messageId, status: status.socketStatus)
    }

    /// Cached after the first successful read. An unreadable id is requested again.
    var installationId: String? {
        if let cachedInstallationId { return cachedInstallationId }
        let id = dependencies.installationId()
        cachedInstallationId = id
        return id
    }

    // MARK: - Core callbacks (already on the main actor)

    private func handle(state: SocketState) {
        guard socketConfiguration != nil else { return }
        publish(SinchPushSocketState(state))
    }

    private func handle(message: SocketMessageEvent) {
        guard socketConfiguration != nil else { return }
        messageSubject.send(SinchPushSocketMessage(message))
    }

    /// The relay refused the token, once per start. Re-issues it and reconnects.
    private func handleAuthRequired() {
        guard let current = socketConfiguration, let authDataSource, let appConfig else { return }
        let session = sessionID
        let url = current.url
        Task { [weak self] in
            do {
                let refreshed = try await authDataSource.refreshToken()
                self?.applyRefreshedToken(refreshed, url: url, config: appConfig, session: session)
            } catch {
                self?.refreshFailed("access token refresh failed: \(error)", session: session)
            }
        }
    }

    private func applyRefreshedToken(_ auth: AuthModel, url: String, config: SinchSDKConfig.AppConfig, session: Int) {
        guard session == sessionID, let current = socketConfiguration, let relayURL = URL(string: url) else { return }
        switch SocketConfiguration.relay(url: relayURL, auth: auth, config: config) {
        case .failure(let error):
            refreshFailed("refreshed access token unusable: \(error)", session: session)
        case .success(let refreshed):
            guard refreshed.isSameSession(as: current) else {
                refreshFailed("refreshed access token belongs to another user", session: session)
                return
            }
            Logger.info("push relay access token refreshed")
            appAuth = auth
            socketConfiguration = refreshed
            client.updateConfiguration(refreshed)
            suspendIfInBackground()
            onAccessTokenRefreshed?()
        }
    }

    private func refreshFailed(_ reason: String, session: Int) {
        guard session == sessionID, socketConfiguration != nil else { return }
        Logger.warning("push relay: \(reason)")
        publish(SinchPushSocketState(status: .error, relayEnabled: true, lastError: reason))
    }

    private func publish(_ state: SinchPushSocketState) {
        guard state != stateSubject.value else { return }
        stateSubject.send(state)
    }
}
