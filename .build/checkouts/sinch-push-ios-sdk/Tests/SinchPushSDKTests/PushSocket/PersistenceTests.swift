//  PersistenceTests.swift — the store itself, and a relaunch.
//
//  Core restoration tests: they drive `SocketClient` and `UserDefaultsSocketStateStore` directly.
//  The SDK manager suppresses configuration restoration, so it never rebuilds a session from the store the way the client below does.

import XCTest

@testable import SinchPushSDK

final class PersistenceTests: XCTestCase {
    private var suiteName: String = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "com.sinch.push.socket.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - The store

    func testTheOutboxRoundTripsThroughUserDefaults() throws {
        let store = UserDefaultsSocketStateStore(defaults: defaults)
        store.saveOutbox([
            PendingReport(
                messageId: "msg-1", sinchMessageId: "sinch-1", status: .dismissed,
                reason: "swiped", attempts: 2, deferUntilMs: 1_770_000_000_500),
            PendingReport(
                messageId: "msg-2", sinchMessageId: "sinch-2", status: .delivered,
                reason: "", attempts: 0, deferUntilMs: nil),
        ])

        let reloaded = UserDefaultsSocketStateStore(defaults: defaults)
        XCTAssertEqual(reloaded.loadOutbox().count, 2)
        let first = try XCTUnwrap(reloaded.loadOutbox().first)
        XCTAssertEqual(first.messageId, "msg-1")
        XCTAssertEqual(first.status, .dismissed)
        XCTAssertEqual(first.reason, "swiped")
        XCTAssertEqual(first.attempts, 2)
        // The deadline must survive, or a report the relay is still shedding is resent.
        XCTAssertEqual(first.deferUntilMs, 1_770_000_000_500)
    }

    func testTheSeenSetAndTheSentSetRoundTripTogether() {
        let store = UserDefaultsSocketStateStore(defaults: defaults)
        store.saveSeenMessageIDs(["msg-1", "msg-2"])
        store.saveReportedKeys(["msg-1:1", "msg-1:2"])
        store.saveLastSeenMessageID("msg-2")

        let reloaded = UserDefaultsSocketStateStore(defaults: defaults)
        XCTAssertEqual(reloaded.loadSeenMessageIDs(), ["msg-1", "msg-2"])
        XCTAssertEqual(Set(reloaded.loadReportedKeys()), ["msg-1:1", "msg-1:2"])
        XCTAssertEqual(reloaded.loadLastSeenMessageID(), "msg-2")
    }

    func testPendingMessagesRoundTripWithAbsentFieldsStillAbsent() throws {
        let store = UserDefaultsSocketStateStore(defaults: defaults)
        let blank = SocketMessageEvent(
            pooled: blankPooledMessage(messageID: "msg-1"), ackToken: "", receivedAt: 42)
        store.savePendingMessages([blank])

        let reloaded = UserDefaultsSocketStateStore(defaults: defaults)
        let message = try XCTUnwrap(reloaded.loadPendingMessages().first)
        XCTAssertEqual(message.id, "msg-1")
        XCTAssertNil(message.title, "an absent field came back as an empty one")
        XCTAssertNil(message.imageUrl)
        XCTAssertEqual(message.receivedAt, 42)
    }

    func testTheConfigurationRoundTripsWithoutTheToken() throws {
        let store = UserDefaultsSocketStateStore(defaults: defaults)
        store.saveConfiguration(testConfiguration(sdkVersion: "rn-sinch-push/1.0.1").persistable)

        let reloaded = UserDefaultsSocketStateStore(defaults: defaults)
        let persisted = try XCTUnwrap(reloaded.loadConfiguration())
        XCTAssertEqual(persisted.url, "ws://127.0.0.1:8080/ws")
        XCTAssertEqual(persisted.displayNotifications, "always")
        XCTAssertEqual(persisted.sdkVersion, "rn-sinch-push/1.0.1")
        // No field to leak the token into, which is why `SocketConfiguration/persistable` exists.
        let encoded = try JSONEncoder().encode(persisted)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("jwt.token.value"))

        let rebuilt = persisted.configuration(authToken: "jwt.token.value")
        XCTAssertEqual(rebuilt, testConfiguration(sdkVersion: "rn-sinch-push/1.0.1"))
    }

    func testTheTokenIsPersistedInTheTokenStoreAndNotInTheStateStore() {
        let harness = makeHarness()

        XCTAssertEqual(harness.tokenStore.loadToken(), "jwt.token.value")
        // Checked against the encoded form of every slice, so no mapping could leak the JWT either.
        XCTAssertFalse(harness.store.persistedText(contains: "jwt.token.value"))
        XCTAssertEqual(harness.store.configuration?.url, "ws://127.0.0.1:8080/ws")
    }

    func testAnUnreadableSliceIsDroppedRatherThanFailingTheLaunch() {
        // Dropping costs a re-delivered message, which the relay tolerates; keeping it leaves state nothing can act on.
        defaults.set("not json at all".data(using: .utf8), forKey: "com.sinch.push.socket.outbox")

        let store = UserDefaultsSocketStateStore(defaults: defaults)
        XCTAssertEqual(store.loadOutbox().count, 0)
        XCTAssertEqual(store.loadSeenMessageIDs(), [])
        XCTAssertNil(store.loadConfiguration())
    }

    // MARK: - Relaunch

    func testARelaunchedClientResumesFromPersistedStateAndTheToken() throws {
        let store = UserDefaultsSocketStateStore(defaults: defaults)
        let tokenStore = InMemoryAuthTokenStore(token: "jwt.token.value")
        let factory = FakeSocketTransportFactory()
        let scheduler = ManualScheduler()

        // First run: connect and queue a report the relay never answered.
        let first = SocketClient(
            configuration: testConfiguration(),
            transportFactory: factory,
            scheduler: scheduler,
            random: ScriptedRandomSource(fixed: 0.5),
            store: store,
            tokenStore: tokenStore,
            presenter: FakeNotificationPresenter(),
            logger: SilentSocketLogger(),
            seenRegistry: SeenMessageRegistry(store: store))
        first.start()
        let socket = try XCTUnwrap(factory.sockets.last)
        socket.openSocket()
        var ack = Sinch_Push_Delivery_V1beta1_Ws_HelloAck()
        ack.connectionID = "conn-1"
        socket.deliver(makeServerFrame(ack))
        first.report(messageId: "msg-1", status: .dismissed)
        first.stop()
        XCTAssertEqual(store.loadOutbox().count, 1)

        // Second run: no configuration, only the persisted config and the token.
        let second = SocketClient(
            configuration: nil,
            transportFactory: factory,
            scheduler: scheduler,
            random: ScriptedRandomSource(fixed: 0.5),
            store: store,
            tokenStore: tokenStore,
            presenter: FakeNotificationPresenter(),
            logger: SilentSocketLogger(),
            seenRegistry: SeenMessageRegistry(store: store))
        second.start()

        let reopened = try XCTUnwrap(factory.sockets.last)
        XCTAssertEqual(reopened.connectCalls.count, 1)
        reopened.openSocket()
        XCTAssertEqual(reopened.hello?.authToken, "jwt.token.value",
            "the relaunched client did not pick up the token")
        XCTAssertEqual(
            reopened.connectCalls.first?.absoluteString, "ws://127.0.0.1:8080/ws",
            "the relaunched client did not pick up the persisted config")

        var secondAck = Sinch_Push_Delivery_V1beta1_Ws_HelloAck()
        secondAck.connectionID = "conn-2"
        reopened.deliver(makeServerFrame(secondAck))

        XCTAssertEqual(reopened.reports.map(\.messageID), ["msg-1"])
        second.stop()
    }
}
