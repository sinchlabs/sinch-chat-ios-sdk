import SinchPushSDKNotificationExtension
import XCTest

@testable import SinchPushSDK

final class DeliveryReportSessionRestorerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var configStore: StoredAppConfigStore!
    private var storage: InMemoryAuthStorage!
    private var outbox: DeliveryReportOutbox!
    private var sender: FakeDeliveryReportSender!
    private var tokens: SessionTokenRecorder!
    private var reporter: DeliveryReporter!

    private let config = SinchSDKConfig.AppConfig(clientID: "client", projectID: "project", configID: "config",
                                                  region: .EU1, locale: Locale(identifier: "en_US"))

    override func setUp() {
        super.setUp()
        let suite = "com.sinch.chatsdk.tests.restorer.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        configStore = StoredAppConfigStore(defaults: defaults)
        storage = InMemoryAuthStorage()
        outbox = DeliveryReportOutbox(store: FakeDeliveryReportStore())
        sender = FakeDeliveryReportSender()
        tokens = SessionTokenRecorder()
        let sender = sender!
        let tokens = tokens!
        // A reporter that has no session until the restorer gives it one.
        reporter = DeliveryReporter(
            outbox: outbox,
            dependencies: DeliveryReporter.Dependencies(
                scheduler: SerialManualScheduler(),
                random: ScriptedRandomSource(fixed: 0.5),
                makeSender: { authDataSource, _ in
                    tokens.record((try? authDataSource.currentAccessToken()) ?? "none")
                    return sender
                },
                isApplicationActive: { false },
                isNotificationServiceExtension: { false },
                notificationCenter: NotificationCenter()))
    }

    private func queueDelivery() {
        outbox.enqueue(messageID: "m-0", subscriberID: "s-1", enqueuedAtMs: 1_770_000_000_000)
    }

    private func restorer() -> DeliveryReportSessionRestorer {
        DeliveryReportSessionRestorer(configStore: configStore,
                                      authStorage: { [storage] _ in storage! },
                                      pushClient: { _ in StubPushAPIClient() })
    }

    private func storeToken(_ accessToken: String, identity: SinchSDKIdentity = .selfSigned(userId: "u", secret: "h")) {
        storage.save(AuthModel(accessToken: accessToken, sinchIdentity: identity, clientID: "client",
                               projectID: "project", configID: "config", region: .EU1))
    }

    func testTheSessionIsRestoredFromTheStoredConfigAndTheKeychainToken() async {
        configStore.save(config)
        storeToken("stored-token")

        let restored = restorer().restore(into: reporter)
        queueDelivery()
        await reporter.flushForBackgroundWake(deadline: .seconds(5), callTimeout: .seconds(5))

        XCTAssertEqual(restored?.config, config)
        XCTAssertEqual(restored?.identity, .selfSigned(userId: "u", secret: "h"))
        XCTAssertEqual(tokens.accessTokens, ["stored-token"])
        XCTAssertEqual(sender.batches.map { $0.map(\.messageID) }, [["m-0"]])
        XCTAssertEqual(outbox.count, 0)
    }

    func testNothingIsRestoredWithoutAStoredConfig() async {
        storeToken("stored-token")

        let restored = restorer().restore(into: reporter)
        queueDelivery()
        await reporter.flushForBackgroundWake(deadline: .seconds(5), callTimeout: .seconds(5))

        XCTAssertNil(restored)
        XCTAssertTrue(sender.batches.isEmpty)
        XCTAssertEqual(outbox.count, 1)
    }

    func testNothingIsRestoredWithoutAToken() async {
        configStore.save(config)

        let restored = restorer().restore(into: reporter)
        queueDelivery()
        await reporter.flushForBackgroundWake(deadline: .seconds(5), callTimeout: .seconds(5))

        XCTAssertNil(restored)
        XCTAssertTrue(sender.batches.isEmpty)
    }

    func testAnAnonymousIdentityIsRestoredToo() {
        configStore.save(config)
        storeToken("anonymous-token", identity: .anonymous)

        XCTAssertEqual(restorer().restore(into: reporter)?.identity, .anonymous)
    }

    func testTheStoredConfigRoundTripsAndClears() throws {
        let custom = SinchSDKConfig.AppConfig(
            clientID: "c", projectID: "p", configID: "k",
            region: .custom(host: "chat.example", pushAPIHost: "push.example", port: 8443, isSecure: false,
                            relayURL: URL(string: "ws://relay.example/ws")),
            locale: Locale(identifier: "pl_PL"), relay: .disabled, allowInsecureRelay: true)
        XCTAssertNil(configStore.load())

        configStore.save(custom)
        XCTAssertEqual(configStore.load(), custom)

        configStore.clear()
        XCTAssertNil(configStore.load())
    }

    @MainActor
    func testRemoveIdentityClearsTheStoredConfig() {
        let sdk = SinchPushSDK()
        sdk.storedAppConfigStore = configStore
        configStore.save(config)
        let finished = expectation(description: "removeIdentity completes")

        sdk.removeIdentity { _ in finished.fulfill() }

        wait(for: [finished], timeout: 5)
        XCTAssertNil(configStore.load())
    }
}

/// The restored session through a `SinchPushSDK` of its own: what a `setIdentity` does to the queued deliveries of it.
/// `SinchPushSDK.shared` is never touched, and `setIdentity` itself is not run: it would point the SDK at a host and
/// start network calls. Its identity check is the `stopPushRelayIfIdentityChanges` the tests call.
@MainActor
final class RestoredDeliveryReportIdentityTests: XCTestCase {

    private var sdk: SinchPushSDK!
    private var rig: DeliveryReporterRig!
    private var storage: InMemoryAuthStorage!
    private var configStore: StoredAppConfigStore!
    private var container: ReportContainer!

    private let config = SinchSDKConfig.AppConfig(
        clientID: "client", projectID: "project", configID: "config",
        region: .EU1, locale: Locale(identifier: "en_US"))

    override func setUp() {
        super.setUp()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sdk-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        container = ReportContainer(appGroup: "group.test", directory: directory)
        let uploaders = ReportUploaders(container: container, makeUploader: {
            BackgroundReportUploader(identifier: $0, container: $1, makeSession: { _ in NoopUploadSession() })
        })
        let suite = "com.sinch.chatsdk.tests.restoredIdentity.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        configStore = StoredAppConfigStore(defaults: UserDefaults(suiteName: suite)!)
        storage = InMemoryAuthStorage()
        rig = DeliveryReporterRig()
        rig.reporter.endSession()
        let reporter = rig.reporter
        let storage = storage!
        sdk = SinchPushSDK(makeDeliveryReporter: { _ in reporter }, reportUploaders: uploaders)
        sdk.storedAppConfigStore = configStore
        sdk.deliveryReportClientFactory = { _ in StubPushAPIClient() }
        sdk.deliveryReportAuthStorage = { _ in storage }
    }

    private func storeSignedIn(userId: String = "u") {
        configStore.save(config)
        storage.save(AuthModel(accessToken: "stored-token", sinchIdentity: .selfSigned(userId: userId, secret: "h"),
                               clientID: "client", projectID: "project", configID: "config", region: .EU1))
    }

    /// The identity check of `setIdentity`, for a config of the same account.
    private func changeIdentity(userId: String, locale: String = "en_US",
                                relay: SinchSDKConfig.RelayOption = .enabled) {
        let changed = SinchSDKConfig.AppConfig(clientID: "client", projectID: "project", configID: "config",
                                               region: config.region, locale: Locale(identifier: locale), relay: relay)
        sdk.stopPushRelayIfIdentityChanges(config: changed, identity: .selfSigned(userId: userId, secret: "h"))
    }

    func testTheSameUserWithAnotherLocaleOrRelayKeepsTheOutboxOfTheRestoredSession() async {
        storeSignedIn()
        sdk.restoreDeliveryReportSession()
        rig.queue(2)

        changeIdentity(userId: "u", locale: "pl_PL", relay: .disabled)
        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.flatMap { $0.map(\.messageID) }, ["m-0", "m-1"], "restored, then sent")
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testAnotherUserClearsTheOutboxOfTheRestoredSession() {
        storeSignedIn()
        sdk.restoreDeliveryReportSession()
        rig.queue(2)

        changeIdentity(userId: "someone-else")

        XCTAssertEqual(rig.outbox.count, 0)
    }

    private func initialize() {
        sdk.initialize(options: SinchPushInitializeOptions(environment: .off, appGroup: "group.test"))
    }

    private var token: AuthModel {
        AuthModel(accessToken: "fresh-token", sinchIdentity: .selfSigned(userId: "u", secret: "h"),
                  clientID: "client", projectID: "project", configID: "config", region: .EU1)
    }

    private var mirroredCredentials: SharedReportCredentials? { SharedReportCredentialsStore(container: container).read() }

    func testInitializeDoesNotRestoreTheSessionOfAForegroundLaunch() async {
        storeSignedIn()
        sdk.isApplicationInBackground = { false }
        initialize()
        rig.queue(1)

        await rig.reporter.flush().value

        XCTAssertTrue(rig.sender.batches.isEmpty, "a foreground launch reaches setIdentity")
    }

    func testInitializeRestoresTheSessionOfABackgroundLaunch() async {
        storeSignedIn()
        sdk.isApplicationInBackground = { true }
        initialize()
        rig.queue(1)

        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.count, 1)
    }

    func testTheBackgroundWakeRestoresTheSessionAForegroundInitializeLeftOut() async {
        storeSignedIn()
        sdk.isApplicationInBackground = { false }
        initialize()
        rig.queue(1)

        await sdk.restoreDeliveryReportSessionIfMissing()
        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.count, 1)
    }

    func testInitializeQueuesTheDeliveriesTheExtensionCouldNotUpload() {
        rig.pendingDeliveries = [ReportedDelivery(messageID: "e-1", subscriberID: "s-1")]
        sdk.isApplicationInBackground = { false }

        initialize()

        XCTAssertEqual(rig.outbox.count, 1)
    }

    func testAStaleSetIdentityCompletionStoresNothingAfterRemoveIdentity() {
        let change = sdk.identityChangeCounter.withLock { $0 }
        let removed = expectation(description: "removeIdentity completes")
        sdk.removeIdentity { _ in removed.fulfill() }
        wait(for: [removed], timeout: 5)

        sdk.persistIdentity(config: config, token: token, mirror: ReportCredentialsMirror(container: container),
                            identityChange: change)

        XCTAssertNil(configStore.load(), "the logged-out session is not resurrected")
        XCTAssertNil(mirroredCredentials)
    }

    func testAStaleSetIdentityCompletionStoresNothingAfterANewerSetIdentity() {
        let change = sdk.identityChangeCounter.withLock { $0 }
        sdk.identityChangeCounter.withLock { $0 += 1 }

        sdk.persistIdentity(config: config, token: token, mirror: ReportCredentialsMirror(container: container),
                            identityChange: change)

        XCTAssertNil(configStore.load())
        XCTAssertNil(mirroredCredentials)
    }

    func testTheCurrentSetIdentityStoresTheConfigAndResumesTheMirrorAfterARemoveIdentity() {
        let removed = expectation(description: "removeIdentity completes")
        sdk.removeIdentity { _ in removed.fulfill() }
        wait(for: [removed], timeout: 5)
        let change = sdk.identityChangeCounter.withLock { $0 }

        sdk.persistIdentity(config: config, token: token, mirror: ReportCredentialsMirror(container: container),
                            identityChange: change)

        XCTAssertEqual(configStore.load(), config)
        XCTAssertEqual(mirroredCredentials?.accessToken, "fresh-token", "the mirror takes updates again")
    }

    // MARK: - Late calls of a replaced identity

    private func mirroringStorage(isCurrent: @escaping @Sendable () -> Bool) -> MirroringAuthStorage {
        MirroringAuthStorage(base: InMemoryAuthStorage(), mirror: ReportCredentialsMirror(container: container),
                             isCurrent: isCurrent)
    }

    func testTheDeleteTokenOfARemovedIdentityDoesNotClearTheMirrorOfTheNext() {
        let counter = sdk.identityChangeCounter
        let before = counter.withLock { $0 }
        let oldStorage = mirroringStorage(isCurrent: { counter.withLock { $0 } == before })
        let removed = expectation(description: "removeIdentity completes")
        sdk.removeIdentity { _ in removed.fulfill() }
        wait(for: [removed], timeout: 5)
        let change = counter.withLock { $0 }
        sdk.persistIdentity(config: config, token: token, mirror: ReportCredentialsMirror(container: container),
                            identityChange: change)
        XCTAssertNotNil(mirroredCredentials)

        oldStorage.deleteToken()

        XCTAssertNotNil(mirroredCredentials, "the next user's mirror stays")
        let next = mirroringStorage(isCurrent: { true })
        next.save(AuthModel(accessToken: "refreshed", sinchIdentity: .selfSigned(userId: "u", secret: "h"),
                            clientID: "client", projectID: "project", configID: "config", region: .EU1))
        XCTAssertEqual(mirroredCredentials?.accessToken, "refreshed", "and is not paused: refreshes still land")
    }

    func testARefreshOfAReplacedIdentityIsNotMirrored() {
        let current = SharedBox(true)
        let storage = mirroringStorage(isCurrent: { current.value })
        storage.save(token)
        XCTAssertEqual(mirroredCredentials?.accessToken, "fresh-token")

        current.value = false
        storage.save(AuthModel(accessToken: "stale", sinchIdentity: .selfSigned(userId: "old", secret: "h"),
                               clientID: "client", projectID: "project", configID: "config", region: .EU1))

        XCTAssertEqual(mirroredCredentials?.accessToken, "fresh-token")
        XCTAssertEqual(storage.read()?.accessToken, "stale", "the token itself is still saved")
    }

    func testTheCurrentIdentityMirrorsAndClears() {
        let storage = mirroringStorage(isCurrent: { true })
        storage.save(token)
        XCTAssertNotNil(mirroredCredentials)

        storage.deleteToken()

        XCTAssertNil(mirroredCredentials)
    }

    func testTheSessionIsRestoredLaterWhenTheFirstRestoreFoundNothing() async {
        sdk.restoreDeliveryReportSession()
        rig.queue(1)
        await rig.reporter.flush().value
        XCTAssertTrue(rig.sender.batches.isEmpty, "before the first unlock the Keychain reads nothing")

        storeSignedIn()
        await sdk.restoreDeliveryReportSessionIfMissing()
        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.count, 1)
        XCTAssertEqual(rig.outbox.count, 0)
    }
}

/// A background session that starts nothing.
private final class NoopUploadSession: ReportUploadSession, @unchecked Sendable {
    func startUpload(_ request: URLRequest, fromFile fileURL: URL, taskDescription: String) {}
}

private final class InMemoryAuthStorage: AuthStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var model: AuthModel?

    func read() -> AuthModel? { lock.withLock { model } }
    func save(_ token: AuthModel) { lock.withLock { model = token } }
    func deleteToken() { lock.withLock { model = nil } }
}

/// Records the access token of the session each sender is made for.
private final class SessionTokenRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var accessTokens: [String] { lock.withLock { recorded } }

    func record(_ token: String) { lock.withLock { recorded.append(token) } }
}
