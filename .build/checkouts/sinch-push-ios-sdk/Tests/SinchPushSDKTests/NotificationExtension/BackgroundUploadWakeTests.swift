import SinchPushSDKNotificationExtension
import XCTest

@testable import SinchPushSDK

/// The wake path of the reporter: the queued deliveries go to the background uploader.
final class BackgroundUploadWakeTests: XCTestCase {

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

    private func wake() async {
        await rig.reporter.flushForBackgroundWake(deadline: .seconds(5), callTimeout: .seconds(5))
    }

    private func delivery(_ id: String) -> ReportedDelivery { ReportedDelivery(messageID: id, subscriberID: "s-1") }

    func testAWakeInTheBackgroundHandsTheQueueToTheUploader() async {
        rig.queue(3)

        await wake()

        XCTAssertEqual(uploader.uploads.count, 1)
        XCTAssertEqual(uploader.uploads.first?.deliveries, [delivery("m-0"), delivery("m-1"), delivery("m-2")])
        XCTAssertEqual(uploader.uploads.first?.accessToken, "jwt")
        XCTAssertEqual(uploader.uploads.first?.baseURL, baseURL)
        XCTAssertTrue(rig.sender.batches.isEmpty, "the in-process flush did not run")
    }

    func testAWakeUploadsInBatchesOfAHundred() async {
        rig.queue(250)

        await wake()

        XCTAssertEqual(uploader.uploads.map(\.deliveries.count), [100, 100, 50])
    }

    func testTheDeliveriesStayInTheOutboxInFlightUntilTheUploadEnds() async {
        rig.queue(2)

        await wake()

        XCTAssertEqual(rig.outbox.count, 2)
        XCTAssertTrue(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 100).isEmpty)
    }

    func testTheNormalFlushLeavesTheInFlightDeliveriesAlone() async {
        rig.queue(2)
        await wake()
        rig.isApplicationActive = true

        await rig.reporter.flush().value

        XCTAssertTrue(rig.sender.batches.isEmpty)
        XCTAssertEqual(rig.outbox.count, 2)
    }

    func testASecondWakeDoesNotUploadTheSameDeliveriesAgain() async {
        rig.queue(2)
        await wake()

        await wake()

        XCTAssertEqual(uploader.uploads.count, 1)
    }

    func testADeliveryQueuedAfterTheFirstWakeIsUploadedByTheNext() async {
        rig.queue(1)
        await wake()
        rig.outbox.enqueue(messageID: "later", subscriberID: "s-1", enqueuedAtMs: rig.scheduler.nowMs())

        await wake()

        XCTAssertEqual(uploader.uploads.map(\.deliveries), [[delivery("m-0")], [delivery("later")]])
    }

    func testAnAcceptedUploadRemovesTheDeliveriesFromTheOutbox() async {
        rig.queue(2)
        await wake()

        rig.reporter.uploadFinished([delivery("m-0"), delivery("m-1")], accepted: true)

        XCTAssertEqual(rig.outbox.count, 0)
        XCTAssertEqual(rig.store.stored, [])
    }

    func testAFailedUploadHandsTheDeliveriesBackToTheNormalFlush() async {
        rig.queue(2)
        await wake()
        rig.reporter.uploadFinished([delivery("m-0"), delivery("m-1")], accepted: false)
        rig.isApplicationActive = true

        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.map(\.count), [2])
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testAnUploadThatNeverReportsBackIsResentAfterTenMinutes() async {
        rig.queue(1)
        await wake()
        rig.scheduler.advance(by: 9 * 60 * 1000)
        XCTAssertTrue(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 10).isEmpty)

        rig.scheduler.advance(by: 2 * 60 * 1000)

        XCTAssertEqual(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 10).map(\.messageID), ["m-0"])
    }

    func testAnUploaderThatCannotStartLeavesTheDeliveriesToTheInProcessFlush() async {
        uploader.starts = false
        rig.queue(2)

        await wake()

        XCTAssertEqual(rig.sender.batches.map(\.count), [2])
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testWithoutABaseURLTheInProcessFlushRuns() async {
        rig.reporter.setSession(authDataSource: rig.auth, client: StubPushAPIClient())
        rig.queue(1)

        await wake()

        XCTAssertTrue(uploader.uploads.isEmpty)
        XCTAssertEqual(rig.sender.batches.map(\.count), [1])
    }

    func testInTheForegroundTheWakeKeepsTheGrpcFlush() async {
        rig.isApplicationActive = true
        rig.queue(2)

        await wake()

        XCTAssertTrue(uploader.uploads.isEmpty)
        XCTAssertEqual(rig.sender.batches.map(\.count), [2])
    }

    // MARK: - Sent markers

    func testADeliveryTheExtensionReportedIsNotQueued() {
        rig.sentDeliveries = [delivery("m-1")]
        rig.isApplicationActive = false

        rig.reporter.reportDelivery(messageID: "m-1", subscriberID: "s-1")
        rig.reporter.reportDelivery(messageID: "m-2", subscriberID: "s-1")

        XCTAssertEqual(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 10).map(\.messageID), ["m-2"])
    }

    func testADeliveryMarkedAfterItWasQueuedIsDroppedAtFlushTime() async {
        rig.queue(3)
        rig.sentDeliveries = [delivery("m-1")]
        rig.isApplicationActive = true

        await rig.reporter.flush().value

        XCTAssertEqual(rig.sender.batches.first?.map(\.messageID), ["m-0", "m-2"])
        XCTAssertEqual(rig.outbox.count, 0)
    }

    func testADeliveryMarkedAfterItWasQueuedIsNotUploaded() async {
        rig.queue(2)
        rig.sentDeliveries = [delivery("m-0")]

        await wake()

        XCTAssertEqual(uploader.uploads.first?.deliveries, [delivery("m-1")])
        XCTAssertEqual(rig.outbox.count, 1, "the marked one left the outbox")
    }
}

/// The in-flight state of the outbox.
final class DeliveryReportOutboxInFlightTests: XCTestCase {

    func testAnInFlightDeliveryIsPersistedAndSurvivesARestart() {
        let store = FakeDeliveryReportStore()
        let outbox = DeliveryReportOutbox(store: store)
        outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 1_000)
        outbox.markInFlight(outbox.nextBatch(nowMs: 1_000, limit: 10), untilMs: 5_000)

        let restarted = DeliveryReportOutbox(store: store)

        XCTAssertTrue(restarted.nextBatch(nowMs: 2_000, limit: 10).isEmpty)
        XCTAssertEqual(restarted.nextBatch(nowMs: 5_000, limit: 10).count, 1)
    }

    func testReportsPersistedBeforeInFlightExistedStillDecode() throws {
        let legacy = #"[{"messageID":"m-1","subscriberID":"s-1","enqueuedAtMs":1000}]"#

        let decoded = try JSONDecoder().decode([DeliveryReport].self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded, [DeliveryReport(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 1000)])
    }

    func testClearingInFlightMakesTheDeliveryDueAgain() {
        let outbox = DeliveryReportOutbox(store: FakeDeliveryReportStore())
        outbox.enqueue(messageID: "m-1", subscriberID: "s-1", enqueuedAtMs: 1_000)
        let batch = outbox.nextBatch(nowMs: 1_000, limit: 10)
        outbox.markInFlight(batch, untilMs: 9_999_999)

        outbox.clearInFlight(batch)

        XCTAssertEqual(outbox.nextBatch(nowMs: 1_000, limit: 10).count, 1)
    }
}
