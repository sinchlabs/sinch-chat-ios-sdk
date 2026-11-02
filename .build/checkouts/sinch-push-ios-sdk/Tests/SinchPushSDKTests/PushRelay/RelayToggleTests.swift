import XCTest
@testable import SinchPushSDK

/// The effective relay state (kill switch + runtime toggle + region), what `Subscribe` reports for it, and the runtime
/// toggle `SinchPush.setRelayEnabled(_:)`: socket stop/start and exactly one re-subscribe per change.
@MainActor
final class RelayToggleTests: XCTestCase {

    private typealias BackgroundService = Sinch_Push_V1beta1_Resources_BackgroundServiceState

    private var rig: RelayTestHarness!
    private var settings: RelaySettings!
    private var coordinatorSuite: String!
    private var coordinatorDefaults: UserDefaults!
    private var authDataSource: MockAuthDataSource!
    private var repository: RecordingSubscribeRepository!
    private var handler: DefaultPushNotificationHandler!
    private var push: DefaultSinchPush!

    private let token = Data([0xab, 0xcd, 0xef])

    override func setUp() async throws {
        try await super.setUp()
        rig = RelayTestHarness()
        settings = rig.settings
        coordinatorSuite = "sinch.tests.relaytoggle.\(UUID().uuidString)"
        coordinatorDefaults = UserDefaults(suiteName: coordinatorSuite)
        authDataSource = MockAuthDataSource()
        authDataSource.identityHashValue = "identity-1"
        repository = RecordingSubscribeRepository()
        handler = makeHandler()
        push = DefaultSinchPush(pushNotificationHandler: handler, inAppPresenter: InAppControllerStub(),
                                socketManager: rig.manager, relaySettings: settings)
    }

    override func tearDown() async throws {
        coordinatorDefaults.removePersistentDomain(forName: coordinatorSuite)
        try await super.tearDown()
    }

    private func deviceInfoProvider(_ settings: RelaySettings) -> SystemDeviceInfoProvider {
        SystemDeviceInfoProvider(installationId: { "install-1" }, relaySwitch: settings.effectiveSwitch)
    }

    private func makeHandler(settings: RelaySettings? = nil,
                             repository: PushRepository? = nil) -> DefaultPushNotificationHandler {
        let handler = DefaultPushNotificationHandler(
            userDefaults: coordinatorDefaults,
            deviceInfoProvider: deviceInfoProvider(settings ?? self.settings))
        handler.authDataSource = authDataSource
        handler.pushRepository = repository ?? self.repository
        return handler
    }

    /// What `setIdentity` does before its token request: the SDK now holds `config`.
    private func setIdentity(_ config: SinchSDKConfig.AppConfig) {
        settings.appConfig = config
        // The repository `setIdentity` creates triggers the Subscribe.
        handler.pushRepository = repository
        rig.start(config: config)
    }

    private var sentStates: [BackgroundService?] {
        repository.calls.map { $0.deviceInfo?.backgroundService }
    }

    private func sentStates(of repository: HoldingRelaySubscribeRepository) -> [BackgroundService?] {
        repository.calls.map { $0.deviceInfo?.backgroundService }
    }

    // MARK: - Effective state => Subscribe's background_service

    private func subscribedState(config: SinchSDKConfig.AppConfig, runtimeEnabled: Bool = true) -> BackgroundService? {
        let defaults = UserDefaults(suiteName: "sinch.tests.relaystate.\(UUID().uuidString)")!
        let repository = RecordingSubscribeRepository()
        let settings = RelaySettings(userDefaults: defaults)
        settings.setEnabled(runtimeEnabled)
        settings.appConfig = config
        let handler = DefaultPushNotificationHandler(userDefaults: defaults,
                                                     deviceInfoProvider: deviceInfoProvider(settings))
        handler.authDataSource = authDataSource
        handler.pushRepository = repository
        handler.sendDeviceToken(token: token)
        return repository.calls.first?.deviceInfo?.backgroundService
    }

    func testAResolvableEnabledRelaySubscribesWithUnsupported() {
        XCTAssertEqual(subscribedState(config: makeAppConfig()), .unsupported)
        XCTAssertEqual(BackgroundService.unsupported.rawValue, 1)
    }

    func testTheKillSwitchSubscribesWithRelayDisabled() {
        XCTAssertEqual(subscribedState(config: makeAppConfig(relay: .disabled)), .relayDisabled)
    }

    func testTheRuntimeToggleOffSubscribesWithRelayDisabled() {
        XCTAssertEqual(subscribedState(config: makeAppConfig(), runtimeEnabled: false), .relayDisabled)
    }

    func testARegionWithoutARelayHostSubscribesWithRelayDisabled() {
        XCTAssertEqual(subscribedState(config: makeAppConfig(region: regionWithoutARelayHost())), .relayDisabled)
    }

    func testTheBuiltInRegionsSubscribeWithUnsupported() {
        XCTAssertEqual(subscribedState(config: makeAppConfig(region: .EU1)), .unsupported)
        XCTAssertEqual(subscribedState(config: makeAppConfig(region: .US1)), .unsupported)
    }

    func testAPlaintextRelayUrlNeedsAllowInsecureRelay() {
        let region = relayRegion(relay: "ws://127.0.0.1:8080/ws")
        XCTAssertEqual(subscribedState(config: makeAppConfig(region: region)), .relayDisabled)
        XCTAssertEqual(subscribedState(config: makeAppConfig(region: region, allowInsecureRelay: true)), .unsupported)
    }

    // MARK: - The effective state as the core's RelaySwitchStore

    func testTheEffectiveSwitchReportsTheEffectiveStateNotJustTheRuntimeToggle() {
        let defaults = UserDefaults(suiteName: "sinch.tests.relayswitch.\(UUID().uuidString)")!
        let settings = RelaySettings(userDefaults: defaults)
        let effective = settings.effectiveSwitch
        XCTAssertTrue(settings.isEnabled, "the runtime toggle defaults to on")
        XCTAssertFalse(effective.isEnabled, "no configuration yet: no socket, so not effective")

        settings.appConfig = makeAppConfig()
        XCTAssertTrue(effective.isEnabled)

        settings.appConfig = makeAppConfig(relay: .disabled)
        XCTAssertFalse(effective.isEnabled, "the kill switch")
        settings.appConfig = makeAppConfig(region: regionWithoutARelayHost())
        XCTAssertFalse(effective.isEnabled, "a region without a relay host")

        settings.appConfig = makeAppConfig()
        settings.setEnabled(false)
        XCTAssertFalse(effective.isEnabled, "the runtime toggle")
        XCTAssertFalse(UserDefaultsRelaySwitchStore(defaults: defaults).isEnabled)
    }

    func testTheEffectiveSwitchWritesTheRuntimeToggleUnderTheCoreKey() {
        let defaults = UserDefaults(suiteName: "sinch.tests.relaykey.\(UUID().uuidString)")!
        let settings = RelaySettings(userDefaults: defaults)

        settings.effectiveSwitch.setEnabled(false)

        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(defaults.object(forKey: "com.sinch.push.relay.enabled") as? Bool, false)
        XCTAssertEqual(RelaySettings.enabledKey, "com.sinch.push.relay.enabled")
        XCTAssertNil(defaults.object(forKey: "sinch_relay_enabled"), "the old key is gone")
    }

    func testTheEffectiveSwitchFeedsTheDeviceInfoProvider() {
        let defaults = UserDefaults(suiteName: "sinch.tests.relayshared.\(UUID().uuidString)")!
        let settings = RelaySettings(userDefaults: defaults)
        let provider = deviceInfoProvider(settings)

        XCTAssertEqual(provider.current(sdkVersionOverride: nil).backgroundService, .relayDisabled,
                       "no configuration: nothing is effective")
        settings.appConfig = makeAppConfig()
        XCTAssertEqual(provider.current(sdkVersionOverride: nil).backgroundService, .unsupported)
        settings.setEnabled(false)
        XCTAssertEqual(provider.current(sdkVersionOverride: nil).backgroundService, .relayDisabled)
    }

    func testTheEnumNumberOnTheWireIsFive() throws {
        XCTAssertEqual(BackgroundService.relayDisabled.rawValue, 5)
        XCTAssertTrue(BackgroundService.allCases.contains(.relayDisabled))

        var info = DeviceInfo.fixture()
        info.backgroundService = .relayDisabled
        let request = DefaultPushRepository.subscribeRequest(token: "t", config: "c", deviceInfo: info)
        let bytes: [UInt8] = try request.serializedBytes()
        let decoded = try Sinch_Push_Sdk_V1beta1_SubscribeRequest(serializedBytes: bytes)
        XCTAssertEqual(decoded.backgroundService.rawValue, 5)
        XCTAssertEqual(decoded.backgroundService, .relayDisabled)
    }

    func testTransientStatesDoNotChangeWhatSubscribeReports() async {
        setIdentity(makeAppConfig())
        handler.sendDeviceToken(token: token)
        XCTAssertTrue(settings.isEffective)

        rig.state.isInBackground = true
        rig.lifecycle?.onBackground?()
        XCTAssertTrue(settings.isEffective)
        rig.lifecycle?.onForeground?()
        await rig.handshake()
        rig.factory.current?.serverClose(reason: .unauthorized)
        await rig.flush()

        handler.sendDeviceToken(token: token)
        XCTAssertEqual(sentStates, [.unsupported])
    }

    // MARK: - Runtime toggle

    func testTheToggleIsOnByDefaultAndPersisted() {
        XCTAssertTrue(push.isRelayEnabled)
        push.setRelayEnabled(false)
        XCTAssertFalse(push.isRelayEnabled)

        let relaunched = RelaySettings(userDefaults: UserDefaults(suiteName: rig.defaultsSuite)!)
        XCTAssertFalse(relaunched.isEnabled)
    }

    func testTurningTheRelayOffStopsTheSocketAndResubscribesOnceWithRelayDisabled() async {
        setIdentity(makeAppConfig())
        handler.sendDeviceToken(token: token)
        await rig.handshake()
        XCTAssertEqual(rig.manager.state.status, .connected)
        XCTAssertEqual(sentStates, [.unsupported])

        push.setRelayEnabled(false)
        await rig.flush()

        XCTAssertEqual(rig.manager.state.status, .stopped)
        XCTAssertFalse(rig.manager.state.relayEnabled)
        XCTAssertEqual(rig.manager.state.disabledReason?.contains("relay disabled at runtime"), true)
        XCTAssertFalse(push.socketState.relayEnabled)
        XCTAssertNil(rig.manager.socketConfiguration)
        XCTAssertFalse(rig.lifecycle?.isObserving ?? true)
        XCTAssertEqual(sentStates, [.unsupported, .relayDisabled])

        let sockets = rig.factory.createdCount
        rig.scheduler.advance(by: 120_000)
        await rig.flush()
        XCTAssertEqual(rig.factory.createdCount, sockets)
        XCTAssertEqual(rig.manager.state.status, .stopped)
    }

    func testTurningTheRelayBackOnStartsTheSocketAndResubscribesOnceWithUnsupported() async {
        setIdentity(makeAppConfig())
        handler.sendDeviceToken(token: token)
        await rig.handshake()
        push.setRelayEnabled(false)
        await rig.flush()
        let sockets = rig.factory.createdCount

        push.setRelayEnabled(true)
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, sockets + 1)
        XCTAssertTrue(rig.manager.state.relayEnabled)
        XCTAssertNotNil(rig.manager.socketConfiguration)
        XCTAssertTrue(rig.lifecycle?.isObserving ?? false)
        XCTAssertEqual(sentStates, [.unsupported, .relayDisabled, .unsupported])

        await rig.handshake()
        XCTAssertEqual(rig.manager.state.status, .connected)
        XCTAssertEqual(rig.factory.current?.hellos.first?.backgroundService, .unsupported,
                       "the Hello of a running socket keeps UNSUPPORTED")
    }

    func testTogglingToTheSameValueDoesNothing() async {
        setIdentity(makeAppConfig())
        handler.sendDeviceToken(token: token)
        await rig.handshake()
        let sockets = rig.factory.createdCount

        push.setRelayEnabled(true)
        XCTAssertEqual(sentStates, [.unsupported])
        XCTAssertEqual(rig.factory.createdCount, sockets)

        push.setRelayEnabled(false)
        push.setRelayEnabled(false)
        XCTAssertEqual(sentStates, [.unsupported, .relayDisabled])
    }

    func testTheToggleDoesNotRemoveTheIdentityOrUnsubscribe() async {
        setIdentity(makeAppConfig())
        handler.sendDeviceToken(token: token)
        await rig.handshake()

        push.setRelayEnabled(false)
        await rig.flush()

        XCTAssertTrue(repository.unsubscribed.isEmpty)
        XCTAssertNotNil(rig.manager.sessionOwner)
    }

    func testReportsStayQueuedWhileTheRelayIsOffAndAreSentWhenItRunsAgain() async {
        setIdentity(makeAppConfig())
        await rig.handshake()
        rig.manager.reportStatus(messageId: "m-queued", status: .dismissed)
        XCTAssertEqual(rig.factory.current?.reports.map(\.messageID), ["m-queued"])

        push.setRelayEnabled(false)
        await rig.flush()
        rig.manager.reportStatus(messageId: "m-offline", status: .displayed)
        XCTAssertEqual(rig.store.loadOutbox().map(\.messageId).contains("m-offline"), true,
                       "a report made while the relay is off is kept, not dropped")

        push.setRelayEnabled(true)
        await rig.flush()
        await rig.handshake()
        XCTAssertEqual(rig.factory.current?.reports.map(\.messageID).contains("m-offline"), true)
    }

    func testTurningTheRelayOnHonoursTheKillSwitch() async {
        setIdentity(makeAppConfig(relay: .disabled))
        handler.sendDeviceToken(token: token)
        XCTAssertEqual(sentStates, [.relayDisabled])
        push.setRelayEnabled(false)
        XCTAssertEqual(sentStates, [.relayDisabled], "disabled either way: no new state, no new Subscribe")

        push.setRelayEnabled(true)
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, 0)
        XCTAssertFalse(rig.manager.state.relayEnabled)
        XCTAssertTrue(try XCTUnwrap(rig.manager.state.disabledReason).contains("relay: .disabled"))
        XCTAssertEqual(sentStates, [.relayDisabled])
    }

    func testTurningTheRelayOffBeforeSetIdentityIsRememberedByTheNextStart() async {
        push.setRelayEnabled(false)
        XCTAssertEqual(rig.manager.state.disabledReason, "relay not started (setIdentity has not succeeded yet)")

        setIdentity(makeAppConfig())
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, 0)
        XCTAssertEqual(rig.manager.state.disabledReason?.contains("relay disabled at runtime"), true)

        push.setRelayEnabled(true)
        await rig.flush()
        XCTAssertEqual(rig.factory.createdCount, 1)
    }

    func testTurningTheRelayBackOnDuringASetIdentityForAnotherIdentityStartsNothing() async {
        setIdentity(makeAppConfig())
        handler.sendDeviceToken(token: token)
        await rig.handshake()
        XCTAssertEqual(rig.factory.createdCount, 1)

        push.setRelayEnabled(false)
        await rig.flush()
        XCTAssertNil(rig.manager.socketConfiguration)
        let sockets = rig.factory.createdCount
        let observers = rig.lifecycles.count

        // `setIdentity(B)` starts while the relay is off: A's inputs must still be dropped, or turning the toggle on starts a socket for the replaced identity.
        rig.manager.identityWillChange(config: makeAppConfig(), identity: .selfSigned(userId: "user-2", secret: "s"))
        await rig.flush()

        push.setRelayEnabled(true)
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, sockets, "no socket was opened for the identity being replaced")
        XCTAssertNil(rig.manager.socketConfiguration)
        XCTAssertEqual(rig.lifecycles.count, observers)
        XCTAssertFalse(push.socketState.relayEnabled)
    }

    func testThePersistedToggleDoesNotFlipFlopSubscribeAcrossLaunches() {
        setIdentity(makeAppConfig())
        handler.sendDeviceToken(token: token)
        push.setRelayEnabled(false)
        XCTAssertEqual(sentStates, [.unsupported, .relayDisabled])

        let relaunchedSettings = RelaySettings(userDefaults: UserDefaults(suiteName: rig.defaultsSuite)!)
        relaunchedSettings.appConfig = makeAppConfig()
        let relaunched = makeHandler(settings: relaunchedSettings)
        relaunched.sendDeviceToken(token: token)

        XCTAssertEqual(sentStates, [.unsupported, .relayDisabled], "the persisted state matches what was last sent")
    }

    // MARK: - setIdentity with another configuration

    func testASetIdentityWithAnotherRelayOptionResubscribesOnce() async {
        setIdentity(makeAppConfig(relay: .enabled))
        handler.sendDeviceToken(token: token)
        await rig.handshake()
        XCTAssertEqual(sentStates, [.unsupported])

        setIdentity(makeAppConfig(relay: .disabled))
        await rig.flush()

        XCTAssertEqual(sentStates, [.unsupported, .relayDisabled])
        XCTAssertEqual(rig.manager.state.status, .stopped)
        XCTAssertFalse(rig.manager.state.relayEnabled)

        setIdentity(makeAppConfig(relay: .disabled))
        XCTAssertEqual(sentStates, [.unsupported, .relayDisabled])

        setIdentity(makeAppConfig(relay: .enabled))
        XCTAssertEqual(sentStates, [.unsupported, .relayDisabled, .unsupported])
    }

    func testASetIdentityWithAnotherRegionResubscribesOnce() {
        setIdentity(makeAppConfig())
        handler.sendDeviceToken(token: token)
        setIdentity(makeAppConfig(region: regionWithoutARelayHost()))

        XCTAssertEqual(sentStates, [.unsupported, .relayDisabled])
    }

    // MARK: - A toggle that lands while a Subscribe is in flight

    /// A toggle that turns the relay back on while a Subscribe is in flight compares against the previous fingerprint, sends nothing,
    /// and the completion then records a state the relay is no longer in (RELAY_DISABLED while the socket runs).
    /// The re-evaluation hops to the main queue, so the test drains it before looking at the calls.
    func testTurningTheRelayBackOnWhileASubscribeIsInFlightSubscribesTheNewStateWhenItCompletes() async {
        let (handler, push, holding) = makeHeldSubscribes()
        handler.sendDeviceToken(token: token)
        XCTAssertEqual(sentStates(of: holding), [.unsupported])
        holding.completeAll(with: .success(()))
        await rig.flush()
        XCTAssertEqual(sentStates(of: holding), [.unsupported])

        push.setRelayEnabled(false)
        XCTAssertEqual(sentStates(of: holding), [.unsupported, .relayDisabled])
        push.setRelayEnabled(true)
        XCTAssertEqual(sentStates(of: holding), [.unsupported, .relayDisabled],
                       "the in-flight Subscribe still owns the record, so nothing goes out yet")

        holding.completeAll(with: .success(()))
        XCTAssertEqual(sentStates(of: holding), [.unsupported, .relayDisabled],
                       "the re-evaluation is hopped to the main queue, so it has not run yet")

        await rig.flush()

        XCTAssertEqual(sentStates(of: holding), [.unsupported, .relayDisabled, .unsupported],
                       "the state the relay is in once the in-flight Subscribe is recorded must be subscribed too")
        XCTAssertEqual(holding.calls.map(\.onMainThread), [true, true, true],
                       "the Subscribe the completion re-evaluates into must go out on the main thread")
    }

    /// Nothing changed while the Subscribe was in flight: completing it subscribes nothing more.
    func testCompletingASubscribeWhoseStateDidNotChangeSendsNothingMore() async {
        let (handler, push, holding) = makeHeldSubscribes()
        handler.sendDeviceToken(token: token)
        XCTAssertEqual(sentStates(of: holding), [.unsupported])

        holding.completeAll(with: .success(()))
        await rig.flush()
        XCTAssertEqual(sentStates(of: holding), [.unsupported], "an unchanged state must not subscribe again")
        XCTAssertEqual(holding.pending, 0)

        push.setRelayEnabled(false)
        XCTAssertEqual(sentStates(of: holding), [.unsupported, .relayDisabled])
        holding.completeAll(with: .success(()))
        await rig.flush()
        XCTAssertEqual(sentStates(of: holding), [.unsupported, .relayDisabled])
        XCTAssertEqual(holding.pending, 0)
    }

    /// A handler and a toggle over a repository that holds the Subscribe completions.
    private func makeHeldSubscribes() -> (handler: DefaultPushNotificationHandler, push: DefaultSinchPush,
                                          holding: HoldingRelaySubscribeRepository) {
        let holding = HoldingRelaySubscribeRepository()
        let handler = makeHandler(repository: holding)
        settings.appConfig = makeAppConfig()
        let push = DefaultSinchPush(pushNotificationHandler: handler, inAppPresenter: InAppControllerStub(),
                                    socketManager: rig.manager, relaySettings: settings)
        return (handler, push, holding)
    }
}

/// `RecordingSubscribeRepository` with the completions held until the test releases them.
private final class HoldingRelaySubscribeRepository: PushRepository, @unchecked Sendable {
    struct Call: Equatable {
        let token: String
        let deviceInfo: DeviceInfo?
        /// Where the Subscribe went out; every one must be sent from the main thread.
        let onMainThread: Bool
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var held: [@Sendable (Result<Void, Error>) -> Void] = []

    var calls: [Call] { lock.withLock { recorded } }
    var pending: Int { lock.withLock { held.count } }

    /// Releases every Subscribe completion held so far, in the order the calls went out.
    func completeAll(with result: Result<Void, Error>) {
        let completions = lock.withLock { () -> [@Sendable (Result<Void, Error>) -> Void] in
            defer { held.removeAll() }
            return held
        }
        completions.forEach { $0(result) }
    }

    func sendDeviceToken(token: String, deviceInfo: DeviceInfo?) async throws -> String? { nil }

    func sendDeviceToken(token: String,
                         deviceInfo: DeviceInfo?,
                         completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        lock.withLock {
            recorded.append(Call(token: token, deviceInfo: deviceInfo, onMainThread: Thread.isMainThread))
            held.append(completion)
        }
    }

    func unsubscribe(_ currentDeviceToken: String) async throws {}
    func unsubscribe(_ currentDeviceToken: String, _ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

}
