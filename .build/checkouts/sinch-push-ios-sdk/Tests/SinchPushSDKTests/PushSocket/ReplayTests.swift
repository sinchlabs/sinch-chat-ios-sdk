//  ReplayTests.swift — fast ack, replay cursor and the replay-burst UX.
//
//    * the report is on the wire before any other work on the message,
//    * the cursor is durable and survives a new client over the same store,
//    * a burst of replayed messages alerts once, not once per message.

import XCTest

@testable import SinchPushSDK

/// Swift 6: `onMessage` is `@Sendable`, so what it records lives in a reference type.
private final class ReplayProbe: @unchecked Sendable {
    var harness: SocketHarness!
    var atCallback: [Sinch_Push_Delivery_V1beta1_Ws_DeliveryReport.Status] = []
    var atPost: [Sinch_Push_Delivery_V1beta1_Ws_DeliveryReport.Status] = []
}

final class ReplayTests: XCTestCase {

    private func presenter(accepts: Bool = true) -> FakeNotificationPresenter {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = accepts
        return presenter
    }

    // MARK: - Fast ack

    func testDeliveredIsTheFirstOutboundFrameAfterAPushedMessage() {
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter())
        harness.handshake()
        let before = harness.transport.sentKinds

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        let after = Array(harness.transport.sentKinds.dropFirst(before.count))
        XCTAssertEqual(after, ["report", "report"], "DELIVERED, then DISPLAYED")
        XCTAssertEqual(harness.reports.first?.status, .delivered)
        XCTAssertEqual(harness.reports.first?.messageID, "msg-1")
    }

    func testDeliveredIsOnTheWireBeforeTheMessageCallbackAndTheNotificationWork() {
        let presenter = self.presenter()
        let probe = ReplayProbe()
        let box = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter,
            onMessage: { _ in probe.atCallback = probe.harness.reports.map(\.status) },
            start: false)
        probe.harness = box
        presenter.onPost = { _ in probe.atPost = box.reports.map(\.status) }
        box.client.start()
        box.handshake()

        box.deliverMessage(pooledMessage(messageID: "msg-1"))

        XCTAssertEqual(probe.atCallback, [.delivered], "DELIVERED had not been sent when the callback ran")
        XCTAssertEqual(probe.atPost, [.delivered], "DELIVERED had not been sent when the post started")
    }

    func testTheSeenSetAndLastSeenAreDurableBeforeDeliveredGoesOut() {
        let store = FakeSocketStateStore()
        var box: SocketHarness!
        var reportsWhenLastSeenWasSaved = -1
        var seenWhenLastSeenWasSaved: [String] = []
        store.onSaveLastSeen = {
            reportsWhenLastSeenWasSaved = box.reports.count
            seenWhenLastSeenWasSaved = store.seen
        }
        box = makeHarness(store: store)
        box.handshake()

        box.deliverMessage(pooledMessage(messageID: "msg-1"))

        XCTAssertEqual(seenWhenLastSeenWasSaved, ["msg-1"])
        XCTAssertEqual(reportsWhenLastSeenWasSaved, 0, "last_seen was saved after the report was sent")
        XCTAssertEqual(box.reports.count, 1)
        XCTAssertEqual(store.lastSeen, "msg-1")
    }

    func testEveryMessageOfAHelloAckReplayIsAckedInReplayOrderBeforeTheFirstPoll() {
        let harness = makeHarness(presenter: presenter(accepts: false))

        harness.handshake(messages: [
            pooledMessage(messageID: "a", enqueuedAt: 1_000),
            pooledMessage(messageID: "b", enqueuedAt: 2_000),
            pooledMessage(messageID: "c", enqueuedAt: 3_000),
        ])

        XCTAssertEqual(harness.transport.sentKinds, ["hello", "report", "report", "report", "poll"])
        XCTAssertEqual(harness.reports.map(\.messageID), ["a", "b", "c"])
        XCTAssertTrue(harness.reports.allSatisfy { $0.status == .delivered })
    }

    func testADedupeHitPutsNothingNewOnTheWire() {
        let harness = makeHarness(presenter: presenter())
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))
        let sent = harness.transport.sent.count

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        // Nothing new reaches the wire because `(msg-1, DELIVERED)` was already reported.
        XCTAssertEqual(harness.transport.sent.count, sent)
    }

    // MARK: - The replay cursor

    func testLastSeenIsPersistedOnEveryDedupeMissAndAHitNeverRegressesIt() {
        let harness = makeHarness(presenter: presenter(accepts: false))
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "msg-1", enqueuedAt: 1_000))
        XCTAssertEqual(harness.store.lastSeen, "msg-1")
        harness.deliverMessage(pooledMessage(messageID: "msg-2", enqueuedAt: 2_000))
        XCTAssertEqual(harness.store.lastSeen, "msg-2")
        XCTAssertEqual(harness.store.lastSeenEnqueuedAt, 2_000)

        harness.deliverMessage(pooledMessage(messageID: "msg-1", enqueuedAt: 1_000))
        XCTAssertEqual(harness.store.lastSeen, "msg-2")
    }

    func testAFreshClientOverTheSameStoreSendsTheCursorInItsHello() {
        let store = FakeSocketStateStore()
        let first = makeHarness(store: store, presenter: presenter(accepts: false))
        first.handshake()
        first.deliverMessage(pooledMessage(messageID: "msg-1", enqueuedAt: 1_000))
        first.deliverMessage(pooledMessage(messageID: "msg-2", enqueuedAt: 2_000))

        let second = makeHarness(store: store, presenter: presenter(accepts: false))
        second.transport.openSocket()

        XCTAssertEqual(second.hello?.lastSeenMessageID, "msg-2")
    }

    func testTheCursorSurvivesInUserDefaultsAsIdAndTimestamp() throws {
        let suite = "ReplayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let writer = UserDefaultsSocketStateStore(defaults: defaults)
        let first = makeHarness(
            store: FakeSocketStateStore(), presenter: presenter(accepts: false))
        first.handshake()
        first.deliverMessage(pooledMessage(messageID: "msg-9", enqueuedAt: 9_000))
        writer.saveLastSeenMessageID(first.store.lastSeen)
        writer.saveLastSeenEnqueuedAtMs(first.store.lastSeenEnqueuedAt)

        let reader = UserDefaultsSocketStateStore(defaults: defaults)
        XCTAssertEqual(reader.loadLastSeenMessageID(), "msg-9")
        XCTAssertEqual(reader.loadLastSeenEnqueuedAtMs(), 9_000)
    }

    func testAnOlderMessageArrivingAfterANewerOneDoesNotMoveTheCursorBack() {
        let harness = makeHarness(presenter: presenter(accepts: false))
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "new", enqueuedAt: 5_000))
        harness.deliverMessage(pooledMessage(messageID: "old", enqueuedAt: 1_000))

        XCTAssertEqual(harness.store.lastSeen, "new")
        XCTAssertEqual(harness.store.lastSeenEnqueuedAt, 5_000)
        XCTAssertEqual(harness.deliveredMessageIDs, ["new", "old"])
        XCTAssertEqual(harness.reports(.delivered).map(\.messageID), ["new", "old"])
        XCTAssertTrue(harness.store.seen.contains("old"))

        harness.serverClose(reason: .shutdown)
        harness.scheduler.advance(by: 60_000)
        harness.transport.openSocket()
        XCTAssertEqual(harness.hello?.lastSeenMessageID, "new")
    }

    func testTheNoRegressionRuleHoldsAcrossARestart() {
        let store = FakeSocketStateStore()
        let first = makeHarness(store: store, presenter: presenter(accepts: false))
        first.handshake()
        first.deliverMessage(pooledMessage(messageID: "new", enqueuedAt: 5_000))

        let second = makeHarness(store: store, presenter: presenter(accepts: false))
        second.handshake()
        second.deliverMessage(pooledMessage(messageID: "old", enqueuedAt: 1_000))

        XCTAssertEqual(store.lastSeen, "new")
    }

    func testEqualTimestampsAndMissingTimestampsFollowArrivalOrder() {
        let harness = makeHarness(presenter: presenter(accepts: false))
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "a", enqueuedAt: 5_000))
        harness.deliverMessage(pooledMessage(messageID: "b", enqueuedAt: 5_000))
        XCTAssertEqual(harness.store.lastSeen, "b", "a tie is arrival order")

        harness.deliverMessage(pooledMessage(messageID: "c", enqueuedAt: 0))
        XCTAssertEqual(harness.store.lastSeen, "c", "no timestamp: arrival order")
        XCTAssertEqual(harness.store.lastSeenEnqueuedAt, 0)

        harness.deliverMessage(pooledMessage(messageID: "d", enqueuedAt: 1_000))
        XCTAssertEqual(harness.store.lastSeen, "d", "nothing to compare against once the cursor has no timestamp")
    }

    func testAHelloAckReplayLeavesTheCursorOnTheNewestMessage() {
        let harness = makeHarness(presenter: presenter(accepts: false))

        harness.handshake(messages: [
            pooledMessage(messageID: "a", enqueuedAt: 1_000),
            pooledMessage(messageID: "b", enqueuedAt: 2_000),
        ])

        XCTAssertEqual(harness.store.lastSeen, "b")
    }

    // MARK: - The alert window

    func testTheWindowAndTheThreadAreTheSpecifiedConstants() {
        XCTAssertEqual(SocketClient.notificationAlertWindowMs, 2000)
        XCTAssertEqual(SocketNotificationStyle.fallbackThread, "sinchpush")
    }

    func testTheNotificationStyleIsAlertingOrSilentAndKeepsTheTriggerThread() {
        let alerting = SocketNotificationStyle(alerting: true, trigger: "orders")
        XCTAssertEqual(alerting.threadIdentifier, "orders")
        XCTAssertTrue(alerting.playsSound)
        XCTAssertFalse(alerting.passive)

        let silent = SocketNotificationStyle(alerting: false, trigger: "orders")
        XCTAssertEqual(silent.threadIdentifier, "orders", "silence does not change the thread")
        XCTAssertFalse(silent.playsSound)
        XCTAssertTrue(silent.passive)
    }

    func testAnAbsentOrEmptyTriggerFallsBackToTheSharedThread() {
        for trigger in [nil, ""] as [String?] {
            for alerting in [true, false] {
                let style = SocketNotificationStyle(alerting: alerting, trigger: trigger)
                XCTAssertEqual(style.threadIdentifier, "sinchpush")
                XCTAssertEqual(style.playsSound, alerting)
                XCTAssertEqual(style.passive, !alerting)
            }
        }
    }

    func testABurstOfNWithinTheWindowIsOneAlertAndNMinusOneSilent() {
        let presenter = self.presenter()
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter)
        harness.handshake()

        for index in 0..<6 {
            harness.deliverMessage(pooledMessage(messageID: "m-\(index)", enqueuedAt: 1_000 + Int64(index)))
            harness.scheduler.advance(by: 300)  // 6 x 300 ms = 1.8 s < 2 s
        }

        XCTAssertEqual(presenter.posted.count, 6, "nothing is dropped")
        XCTAssertEqual(presenter.postedAlerting, [true, false, false, false, false, false])
        XCTAssertEqual(harness.reports(.displayed).count, 6, "silent posts are still DISPLAYED")
        XCTAssertEqual(harness.deliveredMessageIDs.count, 6)
    }

    func testAReplayInOneHelloAckIsOneAlertAndTheRestSilent() {
        let presenter = self.presenter()
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter)

        harness.handshake(messages: (0..<4).map { pooledMessage(messageID: "r-\($0)") })

        XCTAssertEqual(presenter.postedAlerting, [true, false, false, false])
    }

    func testANewAlertIsAllowedOnceTheWindowHasElapsed() {
        let presenter = self.presenter()
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "m-0"))
        harness.scheduler.advance(by: 1_999)
        harness.deliverMessage(pooledMessage(messageID: "m-1"))
        harness.scheduler.advance(by: 1)  // exactly 2000 ms after the alert
        harness.deliverMessage(pooledMessage(messageID: "m-2"))
        harness.scheduler.advance(by: 100)
        harness.deliverMessage(pooledMessage(messageID: "m-3"))

        XCTAssertEqual(presenter.postedAlerting, [true, false, true, false])
    }

    func testAMessageThatIsNotDisplayedDoesNotSpendTheWindow() {
        let presenter = self.presenter()
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .never),
            presenter: presenter)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "m-0"))
        XCTAssertTrue(presenter.posted.isEmpty)

        harness.client.updateConfiguration(testConfiguration(displayNotifications: .always))
        harness.handshake(connectionID: "conn-2")
        harness.deliverMessage(pooledMessage(messageID: "m-1"))

        XCTAssertEqual(presenter.postedAlerting, [true])
    }
}
