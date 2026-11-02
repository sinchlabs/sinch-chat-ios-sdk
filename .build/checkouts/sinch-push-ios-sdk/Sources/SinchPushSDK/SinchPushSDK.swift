import Foundation
import Combine
import UIKit
import SinchPushSDKNotificationExtension
import os

/// The standalone Sinch push SDK.
///
/// Gives a host app an identity and an access token, APNs subscriptions, the foreground push relay, delivery reports
/// and in-app message alerts. The Notification Service Extension is a product of its own
/// (``SinchPushNotificationExtension``).
///
/// ```swift
/// SinchPushSDK.shared.initialize(
///     config: .init(projectID: "…", clientID: "…", configID: "…", region: .EU1),
///     options: .init(environment: .prod, appGroup: "group.…"))
/// SinchPushSDK.shared.setIdentity(.anonymous)
/// SinchPushSDK.shared.push.sendDeviceToken(deviceToken)
/// ```
public final class SinchPushSDK: @unchecked Sendable {

    /// Contains all methods regarding push notifications. To be able to use push notifications you need to call `setIdentity` method.
    private var _push: SinchPush?
    public var push: SinchPush {
        if let existing = _push { return existing }
        let new = MainActor.assumeIsolated {
            installInAppPresenterIfNeeded()
            return DefaultSinchPush(pushNotificationHandler: pushNotificationHandler,
                             inAppPresenter: inAppPresenterBox,
                             socketManager: pushSocketManager,
                             relaySettings: relaySettings,
                             deliveryReporter: deliveryReporter,
                             restoreDeliveryReportSession: { [unowned self] in
                                 await self.restoreDeliveryReportSessionIfMissing()
                             },
                             reportUploaders: reportUploaders)
        }
        _push = new
        return new
    }

    /// The in-app message presenter. The in-app UI (`InApp/`) sets itself here; the default shows nothing.
    ///
    /// It may be set before or after ``push`` is first read, and the APNs path and the relay both use the latest value.
    public var inAppPresenter: InAppMessagePresenting {
        get { inAppPresenterBox.presenter }
        set { inAppPresenterBox.presenter = newValue }
    }

    /// The in-app message entry point: the delegate, the theme and the enable switch.
    @MainActor
    public var inAppMessages: InAppMessages { InAppMessages.shared }

    /// The suffix follows the environment: `-prod` for ``SinchPushEnvironment/prod``, `-dev` otherwise. The chat SDK
    /// gets it so both SDKs report the same family of version strings.
    public nonisolated(unsafe) private(set) static var version = baseVersion + "-dev"

    private static let baseVersion = "1.0.0"

    /// The dedupe set shared by the socket and the APNs handlers.
    let seenMessageRegistry: SeenMessageRegistry
    private let socketStateStore: SocketStateStore
    /// The queue the push relay and the delivery reports run on.
    private let socketScheduler: Scheduler
    /// Reports APNs deliveries to sinch-push. Fixed at init: `push` and the socket manager capture it on first use.
    let deliveryReporter: DeliveryReporter
    /// The background `URLSession`s the delivery reports are uploaded with, and the files they share with the
    /// Notification Service Extension.
    let reportUploaders: ReportUploaders
    /// Copies the access token for the Notification Service Extension into the App Group.
    private var credentialsMirror: ReportCredentialsMirror { ReportCredentialsMirror(container: reportUploaders.container) }
    /// Whether the app was launched, or is, in the background. `initialize` restores the delivery-report session then only.
    var isApplicationInBackground: @MainActor @Sendable () -> Bool = { UIApplication.shared.applicationState == .background }
    /// Builds the push API client the delivery reports go through. `nil` means no reports.
    var deliveryReportClientFactory: (Region) -> PushAPIClient? = { DefaultPushAPIClient(region: $0) }
    /// The storage the token of a stored config is read from, for the delivery reports of a background launch.
    var deliveryReportAuthStorage: (SinchSDKConfig.AppConfig) -> AuthStorage = { KeychainAuthStorage(config: $0) }
    /// The config `setIdentity` last succeeded with, for the delivery reports of a background launch.
    var storedAppConfigStore = StoredAppConfigStore()
    /// The runtime relay switch, and the configuration the relay state is derived from.
    let relaySettings: RelaySettings
    /// Bumped by each `setIdentity` and `removeIdentity`. A late `setIdentity` completion checks it before starting the relay.
    let identityChangeCounter = OSAllocatedUnfairLock(initialState: 0)

    /// The identity `setIdentity` last ran for, by the Keychain account of its config and its normalised identity.
    /// The delivery reports of another identity are dropped. Config fields that are not part of the account (locale,
    /// relay) are not part of the identity.
    @MainActor private var deliveryReportIdentity: (account: String, identity: SinchSDKIdentity)?

    @MainActor private var _pushSocketManager: PushSocketManager?
    @MainActor var pushSocketManager: PushSocketManager {
        if let existing = _pushSocketManager { return existing }
        installInAppPresenterIfNeeded()
        let new = PushSocketManager(
            dependencies: .live(registry: seenMessageRegistry, store: socketStateStore,
                                relaySwitch: relaySettings.effectiveSwitch, scheduler: socketScheduler),
            settings: relaySettings,
            showInApp: { [box = inAppPresenterBox] metadata in
                box.present(metadata: metadata)
            })
        new.onAccessTokenRefreshed = { [unowned self] in
            self.deliveryReporter.flush()
        }
        _pushSocketManager = new
        return new
    }

    public static let shared = SinchPushSDK()

    let pushNotificationHandler: DefaultPushNotificationHandler
    private let inAppPresenterBox = InAppPresenterBox()

    var options: SinchPushInitializeOptions?

    /// The chat SDK sets its own locale before it has a config; otherwise the config's locale wins.
    private var localeOverride: Locale?

    /// The metadata every RPC carries. It reads the latest config and version, so a repository made after
    /// `setIdentity` sends the values of that identity.
    var metadata: StandardMetadata {
        StandardMetadata(locale: localeOverride ?? config?.locale ?? .current, sdkVersion: Self.version)
    }

    private(set) var config: SinchSDKConfig.AppConfig? {
        didSet {
            relaySettings.appConfig = config
        }
    }
    var authDataSource: AuthDataSource? {
        didSet {
            pushNotificationHandler.authDataSource = authDataSource
        }
    }

    /// - Parameters:
    ///   - makeDeliveryReporter: Builds the reporter on the scheduler the push relay runs on. Tests inject theirs.
    ///   - reportUploaders: The background uploads of the delivery reports. Tests inject theirs.
    init(makeDeliveryReporter: ((Scheduler) -> DeliveryReporter)? = nil, reportUploaders: ReportUploaders? = nil) {
        let store = UserDefaultsSocketStateStore()
        let registry = SeenMessageRegistry(store: store)
        socketStateStore = store
        seenMessageRegistry = registry
        let scheduler = DispatchScheduler()
        socketScheduler = scheduler
        let uploaders = reportUploaders ?? ReportUploaders(container: ReportContainer())
        self.reportUploaders = uploaders
        let reporter = makeDeliveryReporter?(scheduler) ?? DeliveryReporter(
            outbox: DeliveryReportOutbox(store: UserDefaultsDeliveryReportStore()),
            dependencies: .live(scheduler: scheduler, uploaders: uploaders, metadata: .init()))
        deliveryReporter = reporter
        uploaders.reporter = reporter
        let settings = RelaySettings()
        relaySettings = settings
        pushNotificationHandler = DefaultPushNotificationHandler(
            deviceInfoProvider: SystemDeviceInfoProvider.live(relaySwitch: settings.effectiveSwitch))
    }

    // MARK: - Initialization

    /// Initialization of the SDK.
    ///
    /// - Parameters:
    ///   - config: The app's Sinch config. It may also arrive with ``setIdentity(with:identity:completion:)``; pass it
    ///     here to have the locale and the relay settings ready before the first identity.
    ///   - options: The push environment and the App Group shared with the Notification Service Extension.
    ///     ``SinchPushEnvironment/off`` registers for no remote notifications and subscribes no device.
    public func initialize(config: SinchSDKConfig.AppConfig? = nil,
                           options: SinchPushInitializeOptions = .standard) {
        Self.version = Self.baseVersion + (options.environment == .prod ? "-prod" : "-dev")
        if let config {
            self.config = config
        }
        if options.environment != .off {
            registerForRemoteNotificationIfNeeded()
            setPushRepositoryIfPossible()
        }
        self.options = options
        reportUploaders.container.appGroup = options.appGroup
        // Delivers the completions of the uploads that finished while the app was not running.
        reportUploaders.activateSessions()
        // A launch in the foreground reaches `setIdentity`; one in the background may not, so it restores the session.
        // A background wake restores a missing session itself, in `handleBackgroundNotification`.
        runOnMain { [self] in
            if isApplicationInBackground() { restoreDeliveryReportSessionOnMain() }
        }
        // What the Notification Service Extension could not upload is reported by the app.
        deliveryReporter.drainPendingDeliveries()
    }

    // MARK: - Identity

    /// Sets identity of the user.
    /// This method must be called `as soon as` we can authorize the user.
    /// Calling this method once again causes the token will be `regenerated`.
    /// If the type of token is different than current one. Example: anonymous vs signed -> token `will be` regenerated.
    /// - Parameters:
    ///   - config: Configuration of sdk.
    ///   - identity: The way of user authorization.
    ///   - completion: Callback with result of user authorization.
    public func setIdentity(with config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity,
                            completion: (@Sendable (Result<Void, SinchSDKIdentityError>) -> Void)? = nil) {
        let identityChange = identityChangeCounter.withLock { value -> Int in
            value += 1
            return value
        }
        stopPushRelayIfIdentityChanges(config: config, identity: identity)
        self.config = config
        let keychainStorage = KeychainAuthStorage(config: config)
        _ = AuthStorageMigrator(keychainStorage: keychainStorage)
        let mirror = credentialsMirror
        let identityStillCurrent: @Sendable () -> Bool = { [counter = identityChangeCounter] in
            counter.withLock { $0 } == identityChange
        }
        authDataSource = DefaultAuthDataSource(
            authRepository: DefaultAuthRepository(config: config, metadata: metadata),
            authStorage: MirroringAuthStorage(base: keychainStorage, mirror: mirror, isCurrent: identityStillCurrent)
        )

        let capturedCompletion = completion
        authDataSource?.generateToken(config: config, identity: identity, completion: { result in
            self.setPushRepositoryIfPossible()

            switch result {
            case .failure(let error):
                switch error {
                case .internalError(tracingID: let tracingID):
                    capturedCompletion?(.failure(.internalError(tracingID: tracingID)))
                default:
                    capturedCompletion?(.failure(.internalError(tracingID: "unknown")))
                }
            case .success(let token):
                self.persistIdentity(config: config, token: token, mirror: mirror, identityChange: identityChange)
                self.startPushRelay(config: config, auth: token, identityChange: identityChange)
                self.startDeliveryReports(config: config, identityChange: identityChange)

                capturedCompletion?(.success(()))

            }
        })
    }

    /// Sets the identity with the config passed to ``initialize(config:options:)``.
    public func setIdentity(_ identity: SinchSDKIdentity,
                            completion: (@Sendable (Result<Void, SinchSDKIdentityError>) -> Void)? = nil) {
        guard let config else {
            completion?(.failure(.internalError(tracingID: "initialize(config:) was not called")))
            return
        }
        setIdentity(with: config, identity: identity, completion: completion)
    }

    /// Removes identity of the user.
    /// This method is logging out user. It removes token and other user data from the app.
    public func removeIdentity(_ completion: (@Sendable (Result<Void, Error>) -> Void)?) {

        // Invalidates in-flight `setIdentity` completions, so none can restart the relay.
        identityChangeCounter.withLock { $0 += 1 }
        stopPushRelay()
        // On the main actor as `persistIdentity` is, so a late `setIdentity` cannot write what this clears.
        let mirror = credentialsMirror
        runOnMain { [self] in
            storedAppConfigStore.clear()
            mirror.clear()
        }

        guard let authDataSource = authDataSource else {
            completion?(.success(()))
            return
        }
        let currentAuthDataSource = authDataSource
        let tempPushNottifications = DefaultPushNotificationHandler(subscribesOnRepositoryChange: false)
        tempPushNottifications.authDataSource = authDataSource
        tempPushNottifications.pushRepository = DefaultPushRepository(region: config?.region ?? .EU1,
                                                                      authDataSource: authDataSource,
                                                                      metadata: metadata)
        tempPushNottifications.unsubscribe { result in
            switch result {
            case .success:
                currentAuthDataSource.deleteToken()

                completion?(.success(()))
            case .failure(let error):
                completion?(.failure(error))
            }
        }
    }

    // MARK: - Chat SDK hooks

    /// The access token the chat SDK authenticates its gRPC calls with.
    @_spi(SinchChat)
    public var tokenProvider: PushTokenProvider {
        PushTokenProvider(current: { [weak self] in self?.authDataSource })
    }

    /// The config of the latest identity.
    @_spi(SinchChat)
    public var appConfig: SinchSDKConfig.AppConfig? { config }

    /// The locale the RPC metadata carries. Setting it overrides the config's locale until the next `setIdentity`.
    @_spi(SinchChat)
    public var locale: Locale {
        get { metadata.locale }
        set { localeOverride = newValue }
    }

    /// Registers an addressee that handles the APNs notifications of another SDK. The chat SDK registers itself here.
    @_spi(SinchChat)
    public func register(addressee: PushNotificationAddressee) {
        pushNotificationHandler.registerAddressee(addressee)
    }

    /// Unregisters an addressee registered with ``register(addressee:)``.
    @_spi(SinchChat)
    public func remove(addressee: PushNotificationAddressee) {
        pushNotificationHandler.removeAddressee(addressee)
    }

    /// Sets the in-app message presenter. The chat SDK forwards its own delegate here.
    @_spi(SinchChat)
    public func setInAppPresenter(_ presenter: InAppMessagePresenting) {
        inAppPresenter = presenter
    }

    // MARK: - Delivery reports

    /// A launch the system starts in the background never reaches `setIdentity`. The delivery reports can still go
    /// out, as the stored config and the Keychain token are enough to sign them.
    ///
    /// Does nothing when an identity is already set, so it can run again: before the first unlock after a restart the
    /// Keychain and `UserDefaults` read nothing, and a later call restores what the first one could not.
    func restoreDeliveryReportSession() {
        runOnMain { [self] in restoreDeliveryReportSessionOnMain() }
    }

    /// Restores the session when there is none, and returns when the reporter has been given it.
    func restoreDeliveryReportSessionIfMissing() async {
        await MainActor.run { restoreDeliveryReportSessionOnMain() }
    }

    /// Whether the identity change counter is still where it is now: false once `setIdentity` or `removeIdentity` ran.
    private func currentIdentityCheck() -> @Sendable () -> Bool {
        let counter = identityChangeCounter
        let change = counter.withLock { $0 }
        return { counter.withLock { $0 } == change }
    }

    @MainActor
    private func restoreDeliveryReportSessionOnMain() {
        guard deliveryReportIdentity == nil else { return }
        let mirror = credentialsMirror
        let baseStorage = deliveryReportAuthStorage
        let isCurrentIdentity = currentIdentityCheck()
        let restorer = DeliveryReportSessionRestorer(
            configStore: storedAppConfigStore,
            authStorage: { MirroringAuthStorage(base: baseStorage($0), mirror: mirror, isCurrent: isCurrentIdentity) },
            pushClient: deliveryReportClientFactory)
        guard let restored = restorer.restore(into: deliveryReporter) else { return }
        // An app that adds `appGroup` in an update has its token only in the Keychain so far.
        mirror.update(from: restored.token)
        deliveryReportIdentity = (KeychainAuthStorage.accountKey(for: restored.config), restored.identity)
    }

    // MARK: - Private

    /// Installs the in-app UI as the presenter unless the host replaced it.
    @MainActor
    private func installInAppPresenterIfNeeded() {
        guard inAppPresenterBox.isDefault else { return }
        inAppPresenter = InAppMessageController.shared // IN-APP WIRING
    }

    private func registerForRemoteNotificationIfNeeded() {
        if !UIApplication.shared.isRegisteredForRemoteNotifications {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func setPushRepositoryIfPossible() {
        guard let authDataSource = authDataSource, authDataSource.isLoggedIn, let config = config else {
            return
        }
        Logger.verbose("--------- SET PUSH REPOSITORY")
        pushNotificationHandler.pushRepository = DefaultPushRepository(region: config.region,
                                                                      authDataSource: authDataSource,
                                                                      metadata: metadata)
    }

    private func startPushRelay(config: SinchSDKConfig.AppConfig, auth: AuthModel, identityChange: Int) {
        guard let authDataSource else { return }
        runOnMain { [self] in
            guard identityChangeCounter.withLock({ $0 }) == identityChange else {
                Logger.verbose("push relay not started: identity changed in the meantime")
                return
            }
            pushSocketManager.start(config: config, auth: auth, authDataSource: authDataSource)
        }
    }

    /// Keeps the config and the token for a launch in the background, and for the Notification Service Extension. A
    /// completion that arrives after `removeIdentity` or another `setIdentity` writes nothing: it would bring back the
    /// session that was logged out.
    func persistIdentity(config: SinchSDKConfig.AppConfig, token: AuthModel, mirror: ReportCredentialsMirror,
                         identityChange: Int) {
        runOnMain { [self] in
            guard identityChangeCounter.withLock({ $0 }) == identityChange else {
                Logger.verbose("identity not stored: it changed in the meantime")
                return
            }
            storedAppConfigStore.save(config)
            // After a `removeIdentity` the mirror ignores updates until it is resumed.
            mirror.resume()
            // A cached token is not saved again, so the mirror is written here as well.
            mirror.update(from: token)
        }
    }

    private func startDeliveryReports(config: SinchSDKConfig.AppConfig, identityChange: Int) {
        guard let authDataSource else { return }
        runOnMain { [self] in
            guard identityChangeCounter.withLock({ $0 }) == identityChange else { return }
            deliveryReporter.setSession(authDataSource: authDataSource,
                                        client: deliveryReportClientFactory(config.region),
                                        reportBaseURL: config.region.pushReportBaseURL)
            deliveryReporter.flush()
        }
    }

    func stopPushRelayIfIdentityChanges(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity) {
        runOnMain { [self] in
            _pushSocketManager?.identityWillChange(config: config, identity: identity)
            // The stored token carries the identity as `storageKey(for:)` normalises it.
            let current = (account: KeychainAuthStorage.accountKey(for: config),
                           identity: DefaultAuthDataSource.storageKey(for: identity))
            if let previous = deliveryReportIdentity, previous != current {
                deliveryReporter.endSession()
            }
            deliveryReportIdentity = current
        }
    }

    private func stopPushRelay() {
        runOnMain { [self] in
            _pushSocketManager?.stop()
            deliveryReporter.endSession()
            deliveryReportIdentity = nil
        }
    }

    /// Runs `work` on the main actor, synchronously when already on the main thread.
    private func runOnMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
        }
    }
}

// MARK: - Spi types

/// The token and identity state of the SDK, for the chat SDK.
@_spi(SinchChat)
public final class PushTokenProvider: @unchecked Sendable {
    private let current: @Sendable () -> AuthDataSource?

    init(current: @escaping @Sendable () -> AuthDataSource?) {
        self.current = current
    }

    /// Whether a stored identity exists.
    public var isLoggedIn: Bool { current()?.isLoggedIn ?? false }

    /// The hash of the stored identity, used as the key of the subscription records.
    public var identityHashValue: String? { current()?.identityHashValue }

    /// The config id of the latest identity.
    public var configID: String { current()?.currentConfigID ?? "" }

    /// The stored token.
    public var currentAuthorization: AuthModel? { current()?.currentAuthorization }

    /// The access token used to authenticate outbound RPCs.
    public func currentAccessToken() throws -> String {
        guard let dataSource = current() else { throw AuthDataSourceError.notLoggedIn }
        return try dataSource.currentAccessToken()
    }

    /// Re-issues the access token of the stored identity, bypassing the cache, and stores it.
    public func refreshToken() async throws -> AuthModel {
        guard let dataSource = current() else { throw AuthDataSourceError.notLoggedIn }
        return try await dataSource.refreshToken()
    }

    /// Deletes the stored token.
    public func deleteToken() {
        current()?.deleteToken()
    }
}

// MARK: - Options

public struct SinchPushInitializeOptions: Sendable {
    /// The APNs environment.
    public var environment: SinchPushEnvironment
    /// The App Group the app shares with its Notification Service Extension. Set it to let the extension report
    /// the delivery of a push (see `Documentation/NotificationServiceExtension.md`): the SDK then copies the access
    /// token and the push API URL, never the identity secret, into the group's container. `nil` (the default)
    /// shares nothing.
    public var appGroup: String?

    public static let standard = SinchPushInitializeOptions(environment: .prod)

    public init(environment: SinchPushEnvironment = .prod, appGroup: String? = nil) {
        self.environment = environment
        self.appGroup = appGroup
    }
}

public enum SinchPushEnvironment: Sendable {
    /// Production APNs and the production backends.
    case prod
    /// Sandbox APNs.
    case sandbox
    /// No remote notifications: nothing is registered or subscribed.
    case off
}
