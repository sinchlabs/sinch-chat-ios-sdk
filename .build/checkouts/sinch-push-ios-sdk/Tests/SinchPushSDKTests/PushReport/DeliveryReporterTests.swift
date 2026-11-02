import SinchPushSDKNotificationExtension
import UIKit
import XCTest

@testable import SinchPushSDK

final class DeliveryReporterTests: XCTestCase {

    private var rig: DeliveryReporterRig!

    override func setUp() {
        super.setUp()
        rig = DeliveryReporterRig()
    }

    // MARK: - Batches

    func testTwoHundredFiftyDeliveriesGoOutInBatchesOfAHundred() async {
        rig.queue(250)

        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.map(\.count), [100, 100, 50])
        XCTAssertEqual(rig.sender.batches.first?.first?.messageID, "m-0")
        XCTAssertEqual(rig.sender.batches.last?.last?.messageID, "m-249")
        XCTAssertEqual(rig.outbox.count, 0)
        XCTAssertEqual(rig.store.stored, [])
    }

    func testAnEmptyOutboxSendsNothing() async {
        await rig.reporter.flush().value

        XCTAssertTrue(rig.sender.batches.isEmpty)
    }

    func testTheRequestCarriesDeliveredEventsOnly() {
        let request = PushAPIDeliveryReportSender.reportRequest([
            deliveryReport("m-1", subscriber: "s-1"),
            deliveryReport("m-2", subscriber: "s-2")
        ])

        XCTAssertEqual(request.events.map(\.messageID), ["m-1", "m-2"])
        XCTAssertEqual(request.events.map(\.subscriberID), ["s-1", "s-2"])
        XCTAssertEqual(request.events.map(\.eventType), [.delivered, .delivered])
        XCTAssertTrue(request.events.allSatisfy { !$0.hasGroupName })
    }

    // MARK: - Unauthenticated

    func testUnauthenticatedRefreshesTheTokenAndSendsTheBatchAgain() async {
        rig.queue(3)
        rig.sender.script(.failure(rpcError(GrpcWebStatus.unauthenticated)))

        await rig.reporter.flush().value

        XCTAssertEqual(rig.auth.refreshCount, 1)
        XCTAssertEqual(rig.sender.batches.count, 2)
        XCTAssertEqual(rig.sender.batches[0], rig.sender.batches[1])
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testASecondUnauthenticatedKeepsTheBatchAndStopsTheFlush() async {
        rig.queue(150)
        rig.sender.script(.failure(rpcError(GrpcWebStatus.unauthenticated)), .failure(rpcError(GrpcWebStatus.unauthenticated)))

        await rig.reporter.flush().value

        XCTAssertEqual(rig.auth.refreshCount, 1)
        XCTAssertEqual(rig.sender.batches.count, 2)
        XCTAssertEqual(rig.outbox.count, 150)
        XCTAssertEqual(rig.scheduler.pendingDelays, [])
    }

    func testAFailedRefreshKeepsTheBatchAndStopsTheFlush() async {
        rig.queue(3)
        rig.auth.refreshFails = true
        rig.sender.script(.failure(rpcError(GrpcWebStatus.unauthenticated)))

        await rig.reporter.flush().value

        XCTAssertEqual(rig.auth.refreshCount, 1)
        XCTAssertEqual(rig.sender.batches.count, 1)
        XCTAssertEqual(rig.outbox.count, 3)
        XCTAssertEqual(rig.scheduler.pendingDelays, [])
    }

    func testARetryAfterRefreshThatFailsTransientlyIsRetriedWithBackoff() async {
        rig.queue(2)
        rig.sender.script(.failure(rpcError(GrpcWebStatus.unauthenticated)), .failure(rpcError(GrpcWebStatus.unavailable)))

        await rig.reporter.flush().value

        XCTAssertEqual(rig.outbox.count, 2)
        XCTAssertEqual(rig.scheduler.pendingDelays, [500])
    }

    // MARK: - Refused batches

    func testARefusedBatchIsDroppedAndTheFlushContinues() async {
        for code in [GrpcWebStatus.invalidArgument, GrpcWebStatus.notFound, GrpcWebStatus.permissionDenied] {
            let rig = DeliveryReporterRig()
            rig.queue(150)
            rig.sender.script(.failure(rpcError(code)))

            await rig.reporter.flush().value

            XCTAssertEqual(rig.sender.batches.map(\.count), [100, 50], "\(code)")
            XCTAssertEqual(rig.sender.batches[0].first?.messageID, "m-0", "\(code)")
            XCTAssertEqual(rig.sender.batches[1].first?.messageID, "m-100", "\(code)")
            XCTAssertEqual(rig.outbox.count, 0, "\(code)")
            XCTAssertEqual(rig.scheduler.pendingDelays, [], "\(code)")
        }
    }

    func testAnyOtherCodeKeepsTheBatchAndWaitsForTheNextTrigger() async {
        rig.queue(150)
        rig.sender.script(.failure(rpcError(GrpcWebStatus.internalError)))

        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.count, 1)
        XCTAssertEqual(rig.outbox.count, 150)
        XCTAssertEqual(rig.scheduler.pendingDelays, [])

        await rig.reporter.flush().value
        XCTAssertEqual(rig.outbox.count, 0)
    }

    // MARK: - Transient failures

    func testATransientFailureKeepsTheBatchAndRetriesAfterTheBackoff() async {
        let failures: [Error] = [rpcError(GrpcWebStatus.unavailable), rpcError(GrpcWebStatus.deadlineExceeded), URLError(.notConnectedToInternet)]
        for failure in failures {
            let rig = DeliveryReporterRig()
            rig.queue(3)
            rig.sender.script(.failure(failure))

            await rig.reporter.flush().value

            XCTAssertEqual(rig.outbox.count, 3, "\(failure)")
            XCTAssertEqual(rig.scheduler.pendingDelays, [500], "\(failure)")

            rig.scheduler.advance(by: 499)
            XCTAssertEqual(rig.sender.batches.count, 1, "\(failure)")
            rig.scheduler.advance(by: 1)
            await rig.waitForPasses(2)

            XCTAssertEqual(rig.sender.batches.count, 2, "\(failure)")
            XCTAssertEqual(rig.outbox.count, 0, "\(failure)")
        }
    }

    func testATriggerMakesAtMostFiveAttemptsAndThenWaits() async {
        rig.queue(2)
        rig.sender.defaultResult = .failure(rpcError(GrpcWebStatus.unavailable))

        await rig.reporter.flush().value
        var delays: [Int] = []
        for attempt in 1..<DeliveryReporter.maxAttemptsPerTrigger {
            let pending = rig.scheduler.pendingDelays
            XCTAssertEqual(pending.count, 1)
            delays.append(pending[0])
            rig.scheduler.advance(by: pending[0])
            await rig.waitForPasses(attempt + 1)
        }

        XCTAssertEqual(delays, [500, 1000, 2000, 4000])
        XCTAssertEqual(rig.sender.batches.count, 5)
        XCTAssertEqual(rig.scheduler.pendingDelays, [])
        XCTAssertEqual(rig.outbox.count, 2)

        rig.sender.defaultResult = .success(())
        await rig.reporter.flush().value
        XCTAssertEqual(rig.sender.batches.count, 6)
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testANewTriggerStartsItsOwnAttemptCountAndCancelsThePendingRetry() async {
        rig.queue(2)
        rig.sender.script(.failure(rpcError(GrpcWebStatus.unavailable)), .failure(rpcError(GrpcWebStatus.unavailable)))

        await rig.reporter.flush().value
        XCTAssertEqual(rig.scheduler.pendingDelays, [500])
        rig.scheduler.advance(by: 500)
        await rig.waitForPasses(2)
        XCTAssertEqual(rig.scheduler.pendingDelays, [1000])

        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.count, 3)
        XCTAssertEqual(rig.outbox.count, 0)
        rig.scheduler.advance(by: 60_000)
        XCTAssertEqual(rig.sender.batches.count, 3)
    }

    // MARK: - One flush at a time

    func testATriggerDuringAFlushDoesNotStartASecondOne() async {
        rig.queue(2)
        rig.sender.holds = true
        let first = rig.reporter.flush()
        await rig.sender.waitForCalls(1)

        await rig.reporter.flush().value
        XCTAssertEqual(rig.sender.batches.count, 1)

        rig.sender.holds = false
        rig.sender.finishHeldCall()
        await first.value

        XCTAssertEqual(rig.sender.batches.count, 1)
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testADeliveryQueuedDuringAFlushIsSentByTheFlushThatEndsAfterIt() async {
        rig.queue(1)
        rig.sender.holds = true
        let first = rig.reporter.flush()
        await rig.sender.waitForCalls(1)

        rig.outbox.enqueue(messageID: "late", subscriberID: "s-1", enqueuedAtMs: rig.scheduler.nowMs())
        await rig.reporter.flush().value
        rig.sender.holds = false
        rig.sender.finishHeldCall()
        await first.value

        XCTAssertEqual(rig.sender.batches.map { $0.map(\.messageID) }, [["m-0"], ["late"]])
        XCTAssertEqual(rig.outbox.count, 0)
    }

    // MARK: - Time to live

    func testADeliveryOlderThanSeventyTwoHoursIsNotSent() async {
        rig.outbox.enqueue(messageID: "old", subscriberID: "s-1", enqueuedAtMs: rig.scheduler.nowMs())
        rig.scheduler.advance(by: 72 * 60 * 60 * 1000 + 1)
        rig.outbox.enqueue(messageID: "fresh", subscriberID: "s-1", enqueuedAtMs: rig.scheduler.nowMs())

        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.map { $0.map(\.messageID) }, [["fresh"]])
        XCTAssertEqual(rig.outbox.count, 0)
    }

    // MARK: - When it only queues

    func testANotificationServiceExtensionOnlyQueues() async {
        rig.isNotificationServiceExtension = true

        rig.reporter.reportDelivery(messageID: "m-1", subscriberID: "s-1")
        await rig.reporter.flush().value

        XCTAssertTrue(rig.sender.batches.isEmpty)
        XCTAssertEqual(rig.store.stored.map(\.messageID), ["m-1"])
    }

    func testANotificationServiceExtensionNeverAsksWhetherTheAppIsActive() {
        rig.isNotificationServiceExtension = true

        rig.reporter.reportDelivery(messageID: "m-1", subscriberID: "s-1")

        XCTAssertEqual(rig.applicationActiveReads, 0)
        XCTAssertEqual(rig.outbox.count, 1)
    }

    func testWithoutATokenItOnlyQueues() async {
        rig.auth.accessToken = nil

        rig.reporter.reportDelivery(messageID: "m-1", subscriberID: "s-1")
        await rig.reporter.flush().value

        XCTAssertTrue(rig.sender.batches.isEmpty)
        XCTAssertEqual(rig.outbox.count, 1)
    }

    func testWithoutASessionItOnlyQueues() async {
        let rig = DeliveryReporterRig()
        rig.reporter.endSession()
        rig.outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 1)

        await rig.reporter.flush().value

        XCTAssertTrue(rig.sender.batches.isEmpty)
        XCTAssertEqual(rig.outbox.count, 1)
    }

    // MARK: - Triggers

    func testAnEnqueueInTheForegroundSends() async {
        rig.reporter.reportDelivery(messageID: "m-1", subscriberID: "s-1")
        await rig.waitForPasses(1)

        XCTAssertEqual(rig.sender.batches.map { $0.map(\.messageID) }, [["m-1"]])
        XCTAssertEqual(rig.sender.batches.first?.first?.subscriberID, "s-1")
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testAnEnqueueOutsideTheForegroundOnlyQueues() async {
        rig.isApplicationActive = false

        rig.reporter.reportDelivery(messageID: "m-1", subscriberID: "s-1")

        XCTAssertTrue(rig.sender.batches.isEmpty)
        XCTAssertEqual(rig.outbox.count, 1)
    }

    func testAnAlreadyQueuedDeliveryDoesNotTriggerAFlush() async {
        rig.isApplicationActive = false
        rig.reporter.reportDelivery(messageID: "m-1", subscriberID: "s-1")
        rig.isApplicationActive = true

        rig.reporter.reportDelivery(messageID: "m-1", subscriberID: "s-1")
        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.count, 1)
    }

    func testWillEnterForegroundSendsWhatIsQueued() async {
        rig.isApplicationActive = false
        rig.reporter.reportDelivery(messageID: "m-1", subscriberID: "s-1")

        rig.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await rig.waitForPasses(1)

        XCTAssertEqual(rig.sender.batches.count, 1)
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testWillEnterForegroundQueuesAndSendsWhatTheExtensionLeft() async {
        rig.pendingDeliveries = [ReportedDelivery(messageID: "e-1", subscriberID: "s-1")]

        rig.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await rig.waitForPasses(1)

        XCTAssertEqual(rig.sender.batches.flatMap { $0.map(\.messageID) }, ["e-1"])
        XCTAssertTrue(rig.pendingDeliveries.isEmpty)
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testWillEnterForegroundWithAnEmptyOutboxSendsNothing() async {
        rig.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await rig.reporter.flush().value

        XCTAssertTrue(rig.sender.batches.isEmpty)
    }

    // MARK: - Identity

    func testEndingTheSessionEmptiesTheOutbox() async {
        rig.queue(3)

        rig.reporter.endSession()
        await rig.reporter.flush().value

        XCTAssertEqual(rig.outbox.count, 0)
        XCTAssertEqual(rig.store.stored, [])
        XCTAssertTrue(rig.sender.batches.isEmpty)
    }

    func testAFlushOfAnEndedSessionNeitherSendsNorRemovesTheNextSessionsDeliveries() async {
        rig.queue(1)
        rig.sender.holds = true
        let stale = rig.reporter.flush()
        await rig.sender.waitForCalls(1)

        rig.reporter.endSession()
        let next = ReportTestAuthDataSource()
        let nextSender = FakeDeliveryReportSender()
        rig.route(next, to: nextSender)
        rig.reporter.setSession(authDataSource: next, client: StubPushAPIClient())
        rig.queue(1)
        rig.queue(1, subscriber: "s-2", prefix: "other")

        rig.sender.holds = false
        rig.sender.finishHeldCall()
        await stale.value

        XCTAssertEqual(rig.outbox.count, 2)
        XCTAssertTrue(nextSender.batches.isEmpty)

        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.map { $0.map(\.messageID) }, [["m-0"]])
        XCTAssertEqual(nextSender.batches.map { $0.map(\.messageID) }, [["m-0", "other-0"]])
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testARetryScheduledBeforeTheSessionEndedDoesNotFire() async {
        rig.queue(1)
        rig.sender.script(.failure(rpcError(GrpcWebStatus.unavailable)))
        await rig.reporter.flush().value
        XCTAssertEqual(rig.scheduler.pendingDelays, [500])

        rig.reporter.endSession()
        rig.scheduler.advance(by: 60_000)

        XCTAssertEqual(rig.sender.batches.count, 1)
    }

    // MARK: - Background wake

    /// The app is in the background for these: a push woke it up.
    private func wakeInBackground() {
        rig.isApplicationActive = false
    }

    func testTheBackgroundFlushSendsWhatIsQueuedWithTheCallTimeout() async {
        wakeInBackground()
        let sender = TimeoutRecordingSender()
        rig.route(rig.auth, to: sender)
        rig.queue(3)

        await rig.reporter.flushForBackgroundWake(deadline: .seconds(5), callTimeout: .seconds(7))

        XCTAssertEqual(sender.timeouts, [.seconds(7)])
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testTheBackgroundFlushReturnsWithinItsDeadlineWhenTheServerNeverAnswers() async {
        wakeInBackground()
        rig.queue(2)
        rig.sender.holds = true

        let reporter = rig.reporter
        let start = ContinuousClock.now
        await reporter.flushForBackgroundWake(deadline: .milliseconds(200), callTimeout: .seconds(60))
        let elapsed = ContinuousClock.now - start

        XCTAssertLessThan(elapsed, .seconds(3))
        XCTAssertEqual(rig.sender.batches.count, 1)
        XCTAssertEqual(rig.outbox.count, 2)
        rig.sender.finishHeldCall(with: .failure(rpcError(GrpcWebStatus.cancelled)))
    }

    func testTheBackgroundFlushSchedulesNoRetryWhenTheServerIsUnavailable() async {
        wakeInBackground()
        rig.queue(2)
        rig.sender.script(.failure(rpcError(GrpcWebStatus.unavailable)))

        await rig.reporter.flushForBackgroundWake(deadline: .seconds(5), callTimeout: .seconds(5))

        XCTAssertEqual(rig.sender.batches.count, 1)
        XCTAssertEqual(rig.outbox.count, 2)
        XCTAssertEqual(rig.scheduler.pendingDelays, [])
    }

    func testTheBackgroundFlushKeepsTheRetryAFailedFlushScheduled() async {
        rig.queue(1)
        rig.sender.script(.failure(rpcError(GrpcWebStatus.unavailable)), .failure(rpcError(GrpcWebStatus.unavailable)))
        await rig.reporter.flush().value
        XCTAssertEqual(rig.scheduler.pendingDelays, [500])

        await rig.reporter.flushForBackgroundWake(deadline: .seconds(5), callTimeout: .seconds(5))

        XCTAssertEqual(rig.sender.batches.count, 2)
        XCTAssertEqual(rig.outbox.count, 1)
        XCTAssertEqual(rig.scheduler.pendingDelays, [500], "the wake does not cancel the backoff of the earlier flush")
    }

    func testTheForegroundWakeIsTheNormalFlushWithItsBackoff() async {
        rig.queue(2)
        rig.sender.script(.failure(rpcError(GrpcWebStatus.unavailable)))

        await rig.reporter.flushForBackgroundWake(deadline: .seconds(5), callTimeout: .seconds(5))

        XCTAssertEqual(rig.sender.batches.count, 1)
        XCTAssertEqual(rig.outbox.count, 2)
        XCTAssertEqual(rig.scheduler.pendingDelays, [500], "a content-available push in the foreground backs off like any flush")
    }

    func testTheForegroundWakeSendsWhatIsQueued() async {
        rig.queue(3)

        await rig.reporter.flushForBackgroundWake(deadline: .seconds(5), callTimeout: .seconds(5))

        XCTAssertEqual(rig.sender.batches.map(\.count), [3])
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testTheBackgroundFlushWaitsForTheRunningFlush() async throws {
        wakeInBackground()
        rig.queue(1)
        rig.sender.holds = true
        let running = rig.reporter.flush()
        await rig.sender.waitForCalls(1)
        rig.queue(1, prefix: "later")
        let returned = ReturnFlag()

        let reporter = rig.reporter
        let wake = Task {
            await reporter.flushForBackgroundWake(deadline: .seconds(10), callTimeout: .seconds(5))
            returned.set()
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(returned.isSet)

        rig.sender.holds = false
        rig.sender.finishHeldCall()
        await running.value
        await wake.value

        XCTAssertTrue(returned.isSet)
        XCTAssertEqual(rig.outbox.count, 0)
        XCTAssertEqual(rig.sender.batches.flatMap { $0.map(\.messageID) }, ["m-0", "later-0"])
    }

    func testTheBackgroundFlushWithoutASessionSendsNothing() async {
        wakeInBackground()
        rig.reporter.endSession()
        rig.queue(1)

        await rig.reporter.flushForBackgroundWake(deadline: .seconds(5), callTimeout: .seconds(5))

        XCTAssertTrue(rig.sender.batches.isEmpty)
    }
}

/// Records the call timeout of every batch.
private final class TimeoutRecordingSender: DeliveryReportSending, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration?] = []

    var timeouts: [Duration?] { lock.withLock { recorded } }

    func reportEvents(_ events: [DeliveryReport]) async throws {
        try await reportEvents(events, timeout: nil)
    }

    func reportEvents(_ events: [DeliveryReport], timeout: Duration?) async throws {
        lock.withLock { recorded.append(timeout) }
    }
}

private final class ReturnFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() { lock.withLock { value = true } }
}
