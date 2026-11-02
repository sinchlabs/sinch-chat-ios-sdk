import XCTest

@testable import SinchPushSDK

/// `DefaultSinchPush.handleBackgroundNotification`: the handling of the payload, then the session restore, then the flush.
@MainActor
final class BackgroundNotificationTests: XCTestCase {

    private var rig: RelayTestHarness!
    private var handler: RoutingHandlerStub!
    private var reporter: FlushSpyReporter!
    private var order: CallOrder!

    override func setUp() async throws {
        try await super.setUp()
        rig = RelayTestHarness()
        handler = RoutingHandlerStub()
        order = CallOrder()
        reporter = FlushSpyReporter(order: order)
    }

    private func makePush() -> DefaultSinchPush {
        let order = order!
        return DefaultSinchPush(
            pushNotificationHandler: handler, inAppPresenter: InAppControllerStub(),
            socketManager: rig.manager, relaySettings: rig.settings, deliveryReporter: reporter,
            restoreDeliveryReportSession: { order.record("restore") })
    }

    private func apns(_ id: String = "m-1") -> [AnyHashable: Any] {
        ["aps": ["content-available": 1], "owner": "sinch", "sinch.push.message_id": id]
    }

    func testTheAsyncHandlerFlushesTheReportsWhileTheAppIsInactive() async {
        let push = makePush()

        let handled = await push.handleBackgroundNotification(apns())

        XCTAssertTrue(handled)
        XCTAssertEqual(reporter.flushCount, 1)
    }

    func testTheSessionIsRestoredBeforeTheFlush() async {
        let push = makePush()

        _ = await push.handleBackgroundNotification(apns())

        XCTAssertEqual(order.calls, ["drain", "restore", "flush"])
    }

    func testTheWakesDeadlineStartsBeforeTheSessionIsRestored() async {
        let order = order!
        let push = DefaultSinchPush(
            pushNotificationHandler: handler, inAppPresenter: InAppControllerStub(),
            socketManager: rig.manager, relaySettings: rig.settings, deliveryReporter: reporter,
            restoreDeliveryReportSession: {
                order.record("restore")
                try? await Task.sleep(for: .milliseconds(300))
            })

        _ = await push.handleBackgroundNotification(apns())

        guard let deadline = reporter.deadline, let reachedFlush = reporter.flushStartedAt else {
            return XCTFail("the flush got a deadline")
        }
        let budget = DeliveryReporter.backgroundWakeDeadline
        XCTAssertLessThanOrEqual(deadline, reachedFlush + budget - .milliseconds(250), "the restore is part of the budget")
        XCTAssertGreaterThan(deadline, reachedFlush + budget - .seconds(2))
    }

    func testAnUnrelatedPayloadIsNotHandledButStillFlushes() async {
        let push = makePush()
        handler.handleResult = false

        let handled = await push.handleBackgroundNotification(["aps": ["content-available": 1]])

        XCTAssertFalse(handled)
        XCTAssertEqual(reporter.flushCount, 1, "the outbox may hold deliveries of earlier wakes")
    }

    func testWithoutAReporterTheAsyncHandlerOnlyHandlesThePayload() async {
        let push = DefaultSinchPush(pushNotificationHandler: handler, inAppPresenter: InAppControllerStub(),
                                    socketManager: rig.manager, relaySettings: rig.settings)

        let handled = await push.handleBackgroundNotification(apns())

        XCTAssertTrue(handled)
        XCTAssertEqual(reporter.flushCount, 0)
    }
}

private final class CallOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var calls: [String] { lock.withLock { recorded } }

    func record(_ call: String) { lock.withLock { recorded.append(call) } }
}

private final class FlushSpyReporter: DeliveryReporting, @unchecked Sendable {
    private let order: CallOrder
    private let lock = NSLock()
    private var flushes = 0
    private var flushDeadline: ContinuousClock.Instant?
    private var flushStart: ContinuousClock.Instant?

    init(order: CallOrder) { self.order = order }

    var deadline: ContinuousClock.Instant? { lock.withLock { flushDeadline } }
    var flushStartedAt: ContinuousClock.Instant? { lock.withLock { flushStart } }

    func drainPendingDeliveries() { order.record("drain") }

    var flushCount: Int { lock.withLock { flushes } }

    func reportDelivery(messageID: String, subscriberID: String) {}

    func flushForBackgroundWake(until deadline: ContinuousClock.Instant) async {
        lock.withLock {
            flushes += 1
            flushDeadline = deadline
            flushStart = ContinuousClock.now
        }
        order.record("flush")
    }
}
