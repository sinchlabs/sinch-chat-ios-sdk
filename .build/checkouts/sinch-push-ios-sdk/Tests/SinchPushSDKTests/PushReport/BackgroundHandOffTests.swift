import SinchPushSDKNotificationExtension
import XCTest

@testable import SinchPushSDK

/// The hand-off of a background wake to the uploader: an expired token, a running flush, the deadline, the deliveries
/// the extension left behind, and the moment an upload's result is saved.
final class BackgroundHandOffTests: XCTestCase {

    private var rig: DeliveryReporterRig!
    private var uploader: FakeDeliveryReportUploader!
    private let baseURL = URL(string: "https://grpc.sinch-push.prod.sinch.com")!

    override func setUp() {
        super.setUp()
        rig = DeliveryReporterRig()
        uploader = FakeDeliveryReportUploader()
        rig.uploader = uploader
        rig.auth.accessToken = "jwt"
        rig.reporter.setSession(authDataSource: rig.auth, client: StubPushAPIClient(), reportBaseURL: baseURL)
        rig.isApplicationActive = false
    }

    private func wake(deadline: Duration = .seconds(5)) async {
        await rig.reporter.flushForBackgroundWake(deadline: deadline, callTimeout: .seconds(5))
    }

    private func delivery(_ id: String) -> ReportedDelivery { ReportedDelivery(messageID: id, subscriberID: "s-1") }

    // MARK: - Expired token

    func testAnExpiredTokenIsRefreshedBeforeTheUpload() async {
        rig.expiredTokens = ["jwt"]
        rig.queue(2)

        await wake()

        XCTAssertEqual(rig.auth.refreshCount, 1)
        XCTAssertEqual(uploader.uploads.map(\.accessToken), ["refreshed"])
        XCTAssertTrue(rig.sender.batches.isEmpty)
    }

    func testATokenThatIsNotExpiredIsNotRefreshed() async {
        rig.queue(1)

        await wake()

        XCTAssertEqual(rig.auth.refreshCount, 0)
        XCTAssertEqual(uploader.uploads.map(\.accessToken), ["jwt"])
    }

    func testAnExpiredTokenThatCannotBeRefreshedLeavesTheDeliveriesToTheGrpcFlush() async {
        rig.expiredTokens = ["jwt"]
        rig.auth.refreshFails = true
        rig.queue(2)

        await wake()

        XCTAssertTrue(uploader.uploads.isEmpty, "an upload with an expired token would only be answered with a 401")
        XCTAssertEqual(rig.sender.batches.map(\.count), [2])
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testNothingQueuedDoesNotRefreshTheToken() async {
        rig.expiredTokens = ["jwt"]

        await wake()

        XCTAssertEqual(rig.auth.refreshCount, 0)
        XCTAssertTrue(uploader.uploads.isEmpty)
    }

    // MARK: - Running flush

    func testTheHandOffWaitsForARunningFlushInsteadOfUploadingItsBatchAgain() async throws {
        rig.queue(1)
        rig.sender.holds = true
        let running = rig.reporter.flush()
        await rig.sender.waitForCalls(1)
        let reporter = rig.reporter

        let woken = Task { await reporter.flushForBackgroundWake(deadline: .seconds(10), callTimeout: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(uploader.uploads.isEmpty, "the hand-off waits for the flush")

        rig.sender.holds = false
        rig.sender.finishHeldCall()
        await running.value
        await woken.value

        XCTAssertEqual(rig.sender.batches.flatMap { $0.map(\.messageID) }, ["m-0"])
        XCTAssertTrue(uploader.uploads.isEmpty, "m-0 was sent by the flush and is not uploaded again")
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testTheHandOffUploadsWhatARunningFlushLeftInTheOutbox() async throws {
        rig.queue(1)
        rig.sender.holds = true
        let running = rig.reporter.flush()
        await rig.sender.waitForCalls(1)
        let reporter = rig.reporter
        let woken = Task { await reporter.flushForBackgroundWake(deadline: .seconds(10), callTimeout: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(100))

        rig.sender.holds = false
        rig.sender.finishHeldCall(with: .failure(rpcError(GrpcWebStatus.internalError)))
        await running.value
        await woken.value

        XCTAssertEqual(uploader.uploads.flatMap { $0.deliveries }, [delivery("m-0")])
    }

    func testTheHandOffStopsWaitingForARunningFlushAtTheDeadline() async {
        rig.queue(1)
        rig.sender.holds = true
        _ = rig.reporter.flush()
        await rig.sender.waitForCalls(1)

        let start = ContinuousClock.now
        await wake(deadline: .milliseconds(200))
        let elapsed = ContinuousClock.now - start

        XCTAssertLessThan(elapsed, .seconds(3))
        XCTAssertTrue(uploader.uploads.isEmpty)
        rig.sender.finishHeldCall(with: .failure(rpcError(GrpcWebStatus.cancelled)))
    }

    // MARK: - Deadline

    func testTheDeadlineIsAbsolute() async {
        rig.queue(1)
        rig.sender.holds = true
        rig.uploader = nil

        let start = ContinuousClock.now
        // A deadline that is almost over, as when the restore of the session has used up the wake.
        await rig.reporter.flushForBackgroundWake(until: start + .milliseconds(100))
        let elapsed = ContinuousClock.now - start

        XCTAssertLessThan(elapsed, .seconds(3))
        XCTAssertEqual(rig.sender.batches.count, 1)
        rig.sender.finishHeldCall(with: .failure(rpcError(GrpcWebStatus.cancelled)))
    }

    func testTheCallTimeoutIsWhatIsLeftOfTheDeadlineLessTheRefreshAllowance() async {
        rig.uploader = nil
        let sender = RecordedTimeouts()
        rig.route(rig.auth, to: sender)
        rig.queue(1)

        await rig.reporter.flushForBackgroundWake(until: ContinuousClock.now + .seconds(20))

        guard let timeout = sender.timeouts.first ?? nil else { return XCTFail("the call carries a timeout") }
        XCTAssertLessThanOrEqual(timeout, .seconds(15))
        XCTAssertGreaterThan(timeout, .seconds(14))
    }

    // MARK: - In-flight window

    func testTheInFlightWindowIsTheLifetimeOfTheUpload() async {
        let window = Int(DeliveryReporter.uploadInFlightDurationMs)
        XCTAssertEqual(DeliveryReporter.uploadInFlightDurationMs, Int64(BackgroundReportUploader.resourceTimeout * 1000))
        rig.queue(1)
        await wake()

        rig.scheduler.advance(by: window - 1)
        XCTAssertTrue(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 100).isEmpty)

        rig.scheduler.advance(by: 1)
        XCTAssertEqual(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 100).count, 1)
    }

    // MARK: - Pending deliveries of the extension

    func testThePendingDeliveriesOfTheExtensionAreQueued() {
        rig.pendingDeliveries = [delivery("e-1"), delivery("e-2")]

        rig.reporter.drainPendingDeliveries()

        XCTAssertEqual(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 100).map(\.messageID), ["e-1", "e-2"])
    }

    func testAPendingDeliveryThatAnUploadReportedIsNotQueued() {
        rig.pendingDeliveries = [delivery("e-1"), delivery("e-2")]
        rig.sentDeliveries = [delivery("e-1")]

        rig.reporter.drainPendingDeliveries()

        XCTAssertEqual(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 100).map(\.messageID), ["e-2"])
    }

    func testAPendingDeliveryIsTakenOnce() {
        rig.pendingDeliveries = [delivery("e-1")]

        rig.reporter.drainPendingDeliveries()
        rig.reporter.drainPendingDeliveries()

        XCTAssertEqual(rig.outbox.count, 1)
        XCTAssertTrue(rig.pendingDeliveries.isEmpty)
    }

    func testAnExtensionProcessLeavesThePendingDeliveriesAlone() {
        rig.isNotificationServiceExtension = true
        rig.pendingDeliveries = [delivery("e-1")]

        rig.reporter.drainPendingDeliveries()

        XCTAssertEqual(rig.outbox.count, 0)
        XCTAssertEqual(rig.pendingDeliveries.count, 1)
    }

    func testADrainedDeliveryKeepsTheTimeItFailedAsItsAge() {
        rig.setPendingDeliveries([delivery("e-1")], failedAgo: 60 * 60)

        rig.reporter.drainPendingDeliveries()

        let queued = rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 100)
        XCTAssertEqual(queued.map(\.enqueuedAtMs), [rig.scheduler.nowMs() - 60 * 60 * 1000])
    }

    func testADrainedDeliveryDoesNotRenewItsTimeToLive() {
        let ttlSeconds = TimeInterval(DeliveryReportOutbox.ttlMs / 1000)
        rig.setPendingDeliveries([delivery("e-1")], failedAgo: ttlSeconds - 60)
        rig.reporter.drainPendingDeliveries()
        XCTAssertEqual(rig.outbox.count, 1)

        rig.scheduler.advance(by: 61 * 1000)

        XCTAssertTrue(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 100).isEmpty,
                      "past 72 hours since the failure, not since the drain")
    }

    func testAPendingDeliveryOlderThanTheTimeToLiveIsNotQueued() {
        let ttlSeconds = TimeInterval(DeliveryReportOutbox.ttlMs / 1000)
        rig.setPendingDeliveries([delivery("e-1")], failedAgo: ttlSeconds + 1)

        rig.reporter.drainPendingDeliveries()

        XCTAssertEqual(rig.outbox.count, 0)
        XCTAssertTrue(rig.pendingDeliveries.isEmpty, "taken all the same")
    }

    func testTheDrainedDeliveriesAreUploadedByTheNextWake() async {
        rig.pendingDeliveries = [delivery("e-1")]
        rig.reporter.drainPendingDeliveries()

        await wake()

        XCTAssertEqual(uploader.uploads.flatMap { $0.deliveries }, [delivery("e-1")])
    }

    // MARK: - Result of an upload

    func testTheResultOfAnUploadIsSavedWhenUploadFinishedReturns() {
        let store = FakeDeliveryReportStore()
        let outbox = DeliveryReportOutbox(store: store)
        let reporter = DeliveryReporter(
            outbox: outbox,
            dependencies: DeliveryReporter.Dependencies(
                scheduler: DispatchScheduler(queue: DispatchQueue(label: "test.report")),
                random: ScriptedRandomSource(fixed: 0.5),
                makeSender: { _, _ in FakeDeliveryReportSender() },
                isApplicationActive: { false },
                isNotificationServiceExtension: { false },
                notificationCenter: NotificationCenter()))
        outbox.enqueue(messageID: "m-0", subscriberID: "s-1", enqueuedAtMs: Int64(Date().timeIntervalSince1970 * 1000))
        outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: Int64(Date().timeIntervalSince1970 * 1000))
        outbox.markInFlight([deliveryReport("m-1")], untilMs: Int64.max)

        // The live scheduler enqueues; the call still returns only after the outbox is saved.
        reporter.uploadFinished([delivery("m-0")], accepted: true)
        XCTAssertEqual(store.stored.map(\.messageID), ["m-1"])

        reporter.uploadFinished([delivery("m-1")], accepted: false)
        XCTAssertNil(store.stored.first?.inFlightUntilMs)
    }
}

/// Records the call timeout of every batch.
private final class RecordedTimeouts: DeliveryReportSending, @unchecked Sendable {
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
