import XCTest

@testable import SinchPushSDK

/// Re-subscribe on change: the handler sends the token again when anything `Subscribe`
/// carries differs from what was last sent for the identity.
final class PushDeviceTokenResubscribeTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var authDataSource: MockAuthDataSource!
    private var deviceInfo: FakeDeviceInfoProvider!
    private var repository: RecordingSubscribeRepository!
    private var handler: DefaultPushNotificationHandler!

    private let token = Data([0xab, 0xcd, 0xef])

    override func setUp() {
        super.setUp()
        suiteName = "sinch.tests.resubscribe.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        authDataSource = MockAuthDataSource()
        authDataSource.identityHashValue = "identity-1"
        deviceInfo = FakeDeviceInfoProvider()
        repository = RecordingSubscribeRepository()
        handler = makeHandler()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeHandler(subscribesOnRepositoryChange: Bool = true) -> DefaultPushNotificationHandler {
        let handler = DefaultPushNotificationHandler(
            userDefaults: defaults,
            deviceInfoProvider: deviceInfo,
            subscribesOnRepositoryChange: subscribesOnRepositoryChange)
        handler.authDataSource = authDataSource
        handler.pushRepository = repository
        return handler
    }

    // MARK: - What is sent

    func testFirstTokenSubscribesWithTheDeviceInfo() {
        handler.sendDeviceToken(token: token)

        XCTAssertEqual(repository.calls.count, 1)
        XCTAssertEqual(repository.calls.first?.token, "abcdef")
        XCTAssertEqual(repository.calls.first?.deviceInfo, DeviceInfo.fixture())
    }

    // MARK: - Unchanged => no call

    func testSameTokenAndSameInfoDoesNotSubscribeAgain() {
        handler.sendDeviceToken(token: token)
        handler.sendDeviceToken(token: token)

        XCTAssertEqual(repository.calls.count, 1)
    }

    func testAnUnchangedFingerprintSurvivesANewHandlerOverTheSameDefaults() {
        handler.sendDeviceToken(token: token)

        let relaunched = makeHandler(subscribesOnRepositoryChange: true)
        relaunched.sendDeviceToken(token: token)

        XCTAssertEqual(repository.calls.count, 1)
    }

    func testRepositoryAssignedAfterTheTokenSubscribesOnce() {
        let late = DefaultPushNotificationHandler(
            userDefaults: defaults, deviceInfoProvider: deviceInfo)
        late.authDataSource = authDataSource
        late.sendDeviceToken(token: token)
        XCTAssertTrue(repository.calls.isEmpty, "there was no repository to send with")

        late.pushRepository = repository
        late.pushRepository = repository

        XCTAssertEqual(repository.calls.count, 1)
    }

    // MARK: - Each field change => one call

    func testEachFieldChangeSubscribesExactlyOnceMore() {
        handler.sendDeviceToken(token: token)
        XCTAssertEqual(repository.calls.count, 1)

        let changes: [(String, (inout DeviceInfo) -> Void)] = [
            ("installation_id", { $0.installationId = "0b8f3d52-7c1e-4a96-b5d0-2e9f6a4c8d17" }),
            ("os_version", { $0.osVersion = "18.2" }),
            ("sdk_version", { $0.sdkVersion = "0.1.19-prod" }),
            ("bundle_id", { $0.bundleId = "com.example.other" }),
            ("background_service", { $0.backgroundService = .disabled })
        ]
        for (index, (name, change)) in changes.enumerated() {
            var info = deviceInfo.info
            change(&info)
            deviceInfo.info = info

            handler.sendDeviceToken(token: token)
            XCTAssertEqual(repository.calls.count, index + 2, "\(name) change did not re-subscribe")

            handler.sendDeviceToken(token: token)
            XCTAssertEqual(repository.calls.count, index + 2, "\(name) change subscribed twice")
        }
    }

    func testATokenChangeSubscribesAgain() {
        handler.sendDeviceToken(token: token)
        handler.sendDeviceToken(token: Data([0x01, 0x02]))

        XCTAssertEqual(repository.calls.map(\.token), ["abcdef", "0102"])
    }

    func testAnotherIdentitySubscribesEvenWithTheSameInfo() {
        handler.sendDeviceToken(token: token)

        authDataSource.identityHashValue = "identity-2"
        handler.sendDeviceToken(token: token)

        XCTAssertEqual(repository.calls.count, 2)
    }

    func testAFailedSubscribeIsNotRecordedAsSent() {
        repository.result = .failure(PushRepositoryError.internalError)
        handler.sendDeviceToken(token: token)
        repository.result = .success(())
        handler.sendDeviceToken(token: token)
        handler.sendDeviceToken(token: token)

        XCTAssertEqual(repository.calls.count, 2)
    }

    // MARK: - Migration

    func testALegacyTokenOnlyRecordIsTreatedAsChangedExactlyOnce() throws {
        let legacy = try PropertyListEncoder().encode(["identity-1": "abcdef"])
        defaults.set(legacy, forKey: "sinch_sent_token_dictionary")
        defaults.set("abcdef", forKey: "sinch_device_token")

        handler.pushRepository = repository
        XCTAssertEqual(repository.calls.count, 1)

        handler.sendDeviceToken(token: token)
        XCTAssertEqual(repository.calls.count, 1)
    }

    func testACorruptStoredFingerprintDoesNotCrashAndResubscribes() {
        defaults.set(Data([0xff, 0x00]), forKey: "sinch_sent_subscription_fingerprint_dictionary")

        handler.sendDeviceToken(token: token)

        XCTAssertEqual(repository.calls.count, 1)
    }

    // MARK: - Installation id unavailable

    func testAnUnavailableInstallationIdSubscribesWithoutDeviceInfoThenCompletesLater() {
        deviceInfo.info = .fixture(installationId: "")
        handler.sendDeviceToken(token: token)

        XCTAssertEqual(repository.calls.count, 1)
        XCTAssertNil(repository.calls.first?.deviceInfo)

        handler.sendDeviceToken(token: token)
        XCTAssertEqual(repository.calls.count, 1)

        deviceInfo.info = .fixture()
        handler.sendDeviceToken(token: token)
        XCTAssertEqual(repository.calls.count, 2)
        XCTAssertEqual(repository.calls.last?.deviceInfo, DeviceInfo.fixture())
    }

    // MARK: - Identity captured at send time

    func testALateSubscribeCompletionRecordsUnderTheIdentityItWasSentFor() throws {
        let holding = HoldingSubscribeRepository()
        let late = DefaultPushNotificationHandler(userDefaults: defaults, deviceInfoProvider: deviceInfo)
        late.authDataSource = authDataSource
        late.pushRepository = holding
        late.sendDeviceToken(token: token)   // sent for identity-1, still in flight
        XCTAssertEqual(holding.pending.count, 1)

        authDataSource.identityHashValue = "identity-2"
        holding.completePending(with: .success(()))

        let coordinator = PushDeviceTokenCoordinator(userDefaults: defaults)
        let info = DeviceInfo.fixture()
        XCTAssertNil(coordinator.getTokenToSend(deviceInfo: info, for: "identity-1"), "recorded for the identity it was sent for")
        XCTAssertEqual(coordinator.getTokenToSend(deviceInfo: info, for: "identity-2"), "abcdef",
                       "the other identity has not been subscribed")
    }

    func testTheAuthDataSourceCanBeSwappedWhileSubscribesRead() {
        let coordinator = PushDeviceTokenCoordinator(userDefaults: defaults)
        coordinator.setTokenToSend(deviceToken: token)
        let sources = (0..<4).map { index -> MockAuthDataSource in
            let source = MockAuthDataSource()
            source.identityHashValue = "identity-\(index)"
            return source
        }
        DispatchQueue.concurrentPerform(iterations: 400) { index in
            if index % 2 == 0 {
                coordinator.authDataSource = sources[index % sources.count]
            } else {
                _ = coordinator.subscribableIdentityHash
            }
        }
        XCTAssertNotNil(coordinator.authDataSource)
    }

    // MARK: - SDK version

    /// The socket configuration's `sdkVersion` is a dev/test override of `Hello` only.
    func testSubscribeReportsTheBuiltInSDKVersionWhileHelloHonoursTheConfiguredOverride() {
        let provider = SystemDeviceInfoProvider(installationId: { "install-1" })

        // Hello: the client asks the provider with the configuration's override.
        let harness = makeHarness(configuration: testConfiguration(sdkVersion: "override/9"), deviceInfo: provider)
        harness.transport.openSocket()
        XCTAssertEqual(harness.hello?.sdkVersion, "override/9")

        // Subscribe: the handler asks without one.
        let live = DefaultPushNotificationHandler(userDefaults: defaults, deviceInfoProvider: provider)
        live.authDataSource = authDataSource
        live.pushRepository = repository
        live.sendDeviceToken(token: token)

        XCTAssertEqual(repository.calls.last?.deviceInfo?.sdkVersion, SinchPushSDK.version)
        XCTAssertNotEqual(repository.calls.last?.deviceInfo?.sdkVersion, "override/9")
    }

    // MARK: - removeIdentity

    func testTheLogoutHandlerDoesNotSubscribeWhenItsRepositoryIsSet() {
        handler.sendDeviceToken(token: token)
        authDataSource.identityHashValue = "identity-2"
        let before = repository.calls.count

        let logout = makeHandler(subscribesOnRepositoryChange: false)
        _ = logout

        XCTAssertEqual(repository.calls.count, before)
    }

    func testUnsubscribeStillUsesTheLastToken() {
        handler.sendDeviceToken(token: token)
        let done = expectation(description: "unsubscribed")

        handler.unsubscribe { _ in done.fulfill() }

        wait(for: [done], timeout: 1)
        XCTAssertEqual(repository.unsubscribed, ["abcdef"])
    }

    func testASuccessfulUnsubscribeClearsTheRecordSoTheSameIdentitySubscribesAgain() {
        handler.sendDeviceToken(token: token)
        XCTAssertEqual(repository.calls.count, 1)

        let done = expectation(description: "unsubscribed")
        handler.unsubscribe { result in
            if case .success = result { done.fulfill() }
        }
        wait(for: [done], timeout: 1)

        let relogin = makeHandler()
        relogin.sendDeviceToken(token: token)

        XCTAssertEqual(repository.calls.count, 2, "the cleared record must not suppress the Subscribe")
    }

    func testASuccessfulUnsubscribeAlsoSubscribesOnRepositoryAssignment() {
        handler.sendDeviceToken(token: token)
        let done = expectation(description: "unsubscribed")
        handler.unsubscribe { _ in done.fulfill() }
        wait(for: [done], timeout: 1)

        let relogin = DefaultPushNotificationHandler(
            userDefaults: defaults, deviceInfoProvider: deviceInfo)
        relogin.authDataSource = authDataSource
        relogin.pushRepository = repository

        XCTAssertEqual(repository.calls.count, 2)
    }

    func testAFailedUnsubscribeKeepsTheRecord() {
        struct Boom: Error {}
        handler.sendDeviceToken(token: token)
        repository.unsubscribeResult = .failure(Boom())

        let done = expectation(description: "unsubscribe failed")
        handler.unsubscribe { result in
            if case .failure = result { done.fulfill() }
        }
        wait(for: [done], timeout: 1)

        let relogin = makeHandler()
        relogin.sendDeviceToken(token: token)

        XCTAssertEqual(repository.calls.count, 1, "the subscription may still exist; keep the record")
    }

    func testClearingOneIdentityLeavesAnotherIdentitysRecordAlone() {
        handler.sendDeviceToken(token: token)
        authDataSource.identityHashValue = "identity-2"
        handler.sendDeviceToken(token: token)
        XCTAssertEqual(repository.calls.count, 2)

        let done = expectation(description: "unsubscribed")
        handler.unsubscribe { _ in done.fulfill() }  // identity-2
        wait(for: [done], timeout: 1)

        authDataSource.identityHashValue = "identity-1"
        makeHandler().sendDeviceToken(token: token)
        XCTAssertEqual(repository.calls.count, 2, "identity-1 was not unsubscribed")
    }

    // MARK: - Logout handler lifetime

    func testUnsubscribeClearsTheRecordWhenTheHandlerIsGoneBeforeTheRpcCompletes() {
        handler.sendDeviceToken(token: token)
        XCTAssertEqual(repository.calls.count, 1)

        // Same shape as `SinchPushSDK.removeIdentity`: a local handler nothing retains.
        let done = expectation(description: "unsubscribed")
        weak var weakTemp: DefaultPushNotificationHandler?
        do {
            let temp = DefaultPushNotificationHandler(
                userDefaults: defaults, deviceInfoProvider: deviceInfo,
                subscribesOnRepositoryChange: false)
            weakTemp = temp
            temp.authDataSource = authDataSource
            temp.pushRepository = DelayedUnsubscribeRepository(delay: 0.2)
            temp.unsubscribe { _ in done.fulfill() }
        }
        XCTAssertNil(weakTemp, "the handler must not be what keeps the logout alive")
        wait(for: [done], timeout: 5)

        let relogin = makeHandler()
        relogin.sendDeviceToken(token: token)
        XCTAssertEqual(repository.calls.count, 2, "the record survived a successful logout unsubscribe")
    }

    func testUnsubscribeWithoutARepositoryStillCompletes() {
        handler.sendDeviceToken(token: token)
        let bare = DefaultPushNotificationHandler(userDefaults: defaults, deviceInfoProvider: deviceInfo)
        bare.authDataSource = authDataSource

        let done = expectation(description: "completed")
        bare.unsubscribe { result in
            if case .success = result { done.fulfill() }
        }
        wait(for: [done], timeout: 1)
    }

    // MARK: - Device info is collected only when a Subscribe can go out

    func testDeviceInfoIsNotCollectedWithoutAToken() {
        let counting = CountingDeviceInfoProvider()
        let fresh = DefaultPushNotificationHandler(userDefaults: defaults, deviceInfoProvider: counting)
        fresh.authDataSource = authDataSource

        XCTAssertNil(defaults.string(forKey: "sinch_device_token"), "precondition: no token stored")

        fresh.pushRepository = repository

        XCTAssertEqual(counting.count, 0)
        XCTAssertTrue(repository.calls.isEmpty)
    }

    func testDeviceInfoIsNotCollectedWithoutAnIdentity() {
        let counting = CountingDeviceInfoProvider()
        let fresh = DefaultPushNotificationHandler(userDefaults: defaults, deviceInfoProvider: counting)
        authDataSource.identityHashValue = nil
        fresh.authDataSource = authDataSource
        fresh.pushRepository = repository

        fresh.sendDeviceToken(token: token)

        XCTAssertEqual(counting.count, 0)
        XCTAssertTrue(repository.calls.isEmpty)
    }

    // MARK: - Concurrency

    func testConcurrentRecordAndClearOnDistinctIdentitiesLoseNoUpdate() {
        let count = 200
        let coordinators = (0..<count).map { index -> PushDeviceTokenCoordinator in
            let coordinator = PushDeviceTokenCoordinator(userDefaults: defaults)
            let auth = MockAuthDataSource()
            auth.identityHashValue = "identity-\(index)"
            coordinator.authDataSource = auth
            return coordinator
        }
        coordinators[0].setTokenToSend(deviceToken: token)
        let info = DeviceInfo.fixture()

        DispatchQueue.concurrentPerform(iterations: count) { index in
            let coordinator = coordinators[index]
            coordinator.recordSubscription(token: "abcdef", deviceInfo: info, for: "identity-\(index)")
            if index % 2 == 1 {
                coordinator.clearSentRecord(for: "identity-\(index)")
            }
        }

        for (index, coordinator) in coordinators.enumerated() {
            if index % 2 == 0 {
                XCTAssertNil(coordinator.getTokenToSend(deviceInfo: info, for: "identity-\(index)"), "identity-\(index) lost its record")
            } else {
                XCTAssertEqual(coordinator.getTokenToSend(deviceInfo: info, for: "identity-\(index)"), "abcdef",
                               "identity-\(index) was not cleared")
            }
        }
        let sent = try? PropertyListDecoder().decode(
            [String: String].self,
            from: defaults.data(forKey: "sinch_sent_token_dictionary") ?? Data())
        XCTAssertEqual(sent?.count, count / 2)
    }

    // MARK: - Fingerprint

    func testTheFingerprintIgnoresNothingSubscribeCarriesAndIsStable() {
        let base = PushDeviceTokenCoordinator.fingerprint(token: "t", deviceInfo: .fixture())
        XCTAssertEqual(base, PushDeviceTokenCoordinator.fingerprint(token: "t", deviceInfo: .fixture()))
        XCTAssertNotEqual(base, PushDeviceTokenCoordinator.fingerprint(token: "t", deviceInfo: nil))
        XCTAssertNotEqual(base, PushDeviceTokenCoordinator.fingerprint(token: "u", deviceInfo: .fixture()))
        XCTAssertFalse(base.contains(DeviceInfo.fixture().installationId))
    }
}

/// Keeps the Subscribe completions until the test releases them.
private final class HoldingSubscribeRepository: PushRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var held: [@Sendable (Result<Void, Error>) -> Void] = []

    var pending: [Int] { lock.withLock { Array(held.indices) } }

    func completePending(with result: Result<Void, Error>) {
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
        lock.withLock { held.append(completion) }
    }

    func unsubscribe(_ currentDeviceToken: String) async throws {}
    func unsubscribe(_ currentDeviceToken: String, _ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }
}

private final class CountingDeviceInfoProvider: DeviceInfoProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var count: Int { lock.withLock { calls } }

    func current(sdkVersionOverride: String?) -> DeviceInfo {
        lock.withLock { calls += 1 }
        return .fixture()
    }
}

/// Completes `unsubscribe` after `delay`, on another queue, while keeping itself
/// alive for the duration — like an in-flight network RPC.
private final class DelayedUnsubscribeRepository: PushRepository, @unchecked Sendable {
    private let delay: TimeInterval

    init(delay: TimeInterval) { self.delay = delay }

    func sendDeviceToken(token: String, deviceInfo: DeviceInfo?) async throws -> String? { nil }
    func unsubscribe(_ currentDeviceToken: String) async throws {}

    func sendDeviceToken(token: String,
                         deviceInfo: DeviceInfo?,
                         completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func unsubscribe(_ currentDeviceToken: String,
                     _ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            _ = self
            completion(.success(()))
        }
    }

}
