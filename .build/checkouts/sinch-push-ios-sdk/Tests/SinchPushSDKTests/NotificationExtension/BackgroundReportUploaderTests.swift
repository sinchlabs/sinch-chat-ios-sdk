import SinchPushSDKNotificationExtension
import XCTest

@testable import SinchPushSDK

/// A session that records the uploads instead of handing them to the system.
final class FakeReportUploadSession: ReportUploadSession, @unchecked Sendable {
    struct Started {
        let request: URLRequest
        let fileURL: URL
        let taskDescription: String
        let body: Data?
    }

    private let lock = NSLock()
    private var recorded: [Started] = []
    private var invalidations = 0

    var started: [Started] { lock.withLock { recorded } }
    var invalidationCount: Int { lock.withLock { invalidations } }

    func finishTasksAndInvalidate() {
        lock.withLock { invalidations += 1 }
    }

    func startUpload(_ request: URLRequest, fromFile fileURL: URL, taskDescription: String) {
        lock.withLock {
            recorded.append(Started(request: request, fileURL: fileURL, taskDescription: taskDescription,
                                    body: try? Data(contentsOf: fileURL)))
        }
    }
}

/// A container in a temporary directory, shared as an App Group would be.
func makeTestContainer(appGroup: String? = "group.test") -> ReportContainer {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sinch-report-\(UUID().uuidString)")
    return ReportContainer(appGroup: appGroup, directory: directory)
}

final class BackgroundReportUploaderTests: XCTestCase {

    private var container: ReportContainer!
    private var session: FakeReportUploadSession!
    private var uploader: BackgroundReportUploader!
    private let baseURL = URL(string: "https://grpc.sinch-push.prod.sinch.com")!

    override func setUp() {
        super.setUp()
        container = makeTestContainer()
        session = FakeReportUploadSession()
        let fake = session!
        uploader = BackgroundReportUploader(identifier: BackgroundReportUploader.makeExtensionIdentifier(),
                                            container: container, makeSession: { _ in fake })
    }

    override func tearDown() {
        if let directory = container.directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private func delivery(_ id: String = "m-1") -> ReportedDelivery {
        ReportedDelivery(messageID: id, subscriberID: "s-1")
    }

    private var markers: SentReportMarkerStore { SentReportMarkerStore(container: container) }

    private func finish(_ started: FakeReportUploadSession.Started, status: Int? = 200, header: String? = nil,
                        body: Data = Data(), error: Error? = nil) {
        uploader.uploadFinished(taskDescription: started.taskDescription, httpStatus: status,
                                headerGrpcStatus: header, body: body, error: error)
    }

    func testTheIdentifiersOfTheAppAndTheExtension() {
        XCTAssertEqual(BackgroundReportUploader.baseIdentifier, "com.sinch.chatsdk.reports")
        XCTAssertEqual(BackgroundReportUploader.legacyExtensionIdentifier, "com.sinch.chatsdk.reports.nse")
        XCTAssertTrue(BackgroundReportUploader.makeExtensionIdentifier().hasPrefix("com.sinch.chatsdk.reports.nse."))
    }

    func testEveryExtensionUploadGetsItsOwnIdentifier() {
        let first = BackgroundReportUploader.makeExtensionIdentifier()

        XCTAssertNotEqual(first, BackgroundReportUploader.makeExtensionIdentifier())
        XCTAssertTrue(BackgroundReportUploader.isExtensionIdentifier(first))
    }

    func testWhichIdentifiersAreAnExtensions() {
        XCTAssertTrue(BackgroundReportUploader.isExtensionIdentifier("com.sinch.chatsdk.reports.nse"))
        XCTAssertTrue(BackgroundReportUploader.isExtensionIdentifier("com.sinch.chatsdk.reports.nse.abc"))
        XCTAssertFalse(BackgroundReportUploader.isExtensionIdentifier("com.sinch.chatsdk.reports.nse."))
        XCTAssertFalse(BackgroundReportUploader.isExtensionIdentifier("com.sinch.chatsdk.reports"))
        XCTAssertFalse(BackgroundReportUploader.isExtensionIdentifier("com.sinch.chatsdk.reports.nsex"))
        XCTAssertFalse(BackgroundReportUploader.isExtensionIdentifier("com.host.nse"))
    }

    func testTheSessionStopsRetryingWithinTheTimeTheAppHoldsTheDeliveries() {
        XCTAssertEqual(BackgroundReportUploader.resourceTimeout, 10 * 60)
    }

    func testAnUploadHandsTheFramedBodyFileToTheSession() throws {
        XCTAssertTrue(uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL))

        let started = try XCTUnwrap(session.started.first)
        XCTAssertEqual(started.body, GRPCWebReportEvents.body(for: [delivery()]))
        XCTAssertEqual(started.request.value(forHTTPHeaderField: "authorization"), "jwt")
        XCTAssertEqual(started.request.url?.lastPathComponent, "ReportEvents")
        XCTAssertTrue(started.fileURL.path.hasPrefix(try XCTUnwrap(container.directory).path), "the file is in the container")
    }

    func testNothingIsUploadedForNoDeliveries() {
        XCTAssertFalse(uploader.upload([], accessToken: "jwt", baseURL: baseURL))
        XCTAssertTrue(session.started.isEmpty)
    }

    func testASuccessRecordsASentMarkerAndRemovesTheFile() throws {
        let finished = SharedBox<[(deliveries: [ReportedDelivery], accepted: Bool)]>([])
        uploader.onFinished = { deliveries, accepted in finished.value.append((deliveries, accepted)) }
        uploader.upload([delivery("a"), delivery("b")], accessToken: "jwt", baseURL: baseURL)
        let started = try XCTUnwrap(session.started.first)

        finish(started, body: Data([0x80, 0, 0, 0, 16]) + Data("grpc-status: 0\r\n".utf8))

        XCTAssertTrue(markers.contains(delivery("a")))
        XCTAssertTrue(markers.contains(delivery("b")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: started.fileURL.path))
        XCTAssertEqual(finished.value.map(\.accepted), [true])
        XCTAssertEqual(finished.value.first?.deliveries, [delivery("a"), delivery("b")])
    }

    func testAHeaderStatusOfZeroIsASuccess() throws {
        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)

        finish(try XCTUnwrap(session.started.first), header: "0")

        XCTAssertTrue(markers.contains(delivery()))
    }

    func testANonZeroGrpcStatusLeavesTheDeliveryUnmarked() throws {
        let accepted = SharedBox<Bool?>(nil)
        uploader.onFinished = { _, result in accepted.value = result }
        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)
        let started = try XCTUnwrap(session.started.first)

        finish(started, body: Data([0x80, 0, 0, 0, 16]) + Data("grpc-status: 16\r\n".utf8))

        XCTAssertFalse(markers.contains(delivery()))
        XCTAssertEqual(accepted.value, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: started.fileURL.path), "the file is removed either way")
    }

    func testAnHttpErrorLeavesTheDeliveryUnmarked() throws {
        let accepted = SharedBox<Bool?>(nil)
        uploader.onFinished = { _, result in accepted.value = result }
        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)

        finish(try XCTUnwrap(session.started.first), status: 502)

        XCTAssertFalse(markers.contains(delivery()))
        XCTAssertEqual(accepted.value, false)
    }

    func testATransportErrorLeavesTheDeliveryUnmarked() throws {
        let accepted = SharedBox<Bool?>(nil)
        uploader.onFinished = { _, result in accepted.value = result }
        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)

        finish(try XCTUnwrap(session.started.first), status: nil, error: URLError(.notConnectedToInternet))

        XCTAssertFalse(markers.contains(delivery()))
        XCTAssertEqual(accepted.value, false)
    }

    func testAnUploadFinishedByAnotherProcessIsAccountedForFromTheTaskDescription() throws {
        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)
        let description = try XCTUnwrap(session.started.first).taskDescription
        // The app relaunched for the extension's session has an uploader of its own and the description only.
        let relaunched = BackgroundReportUploader(identifier: BackgroundReportUploader.makeExtensionIdentifier(),
                                                  container: container, makeSession: { _ in FakeReportUploadSession() })

        relaunched.uploadFinished(taskDescription: description, httpStatus: 200, headerGrpcStatus: "0",
                                  body: Data(), error: nil)

        XCTAssertTrue(markers.contains(delivery()))
    }

    func testAnUnreadableTaskDescriptionIsIgnored() {
        let called = SharedBox(false)
        uploader.onFinished = { _, _ in called.value = true }

        uploader.uploadFinished(taskDescription: "not json", httpStatus: 200, headerGrpcStatus: nil, body: Data(), error: nil)
        uploader.uploadFinished(taskDescription: nil, httpStatus: 200, headerGrpcStatus: nil, body: Data(), error: nil)

        XCTAssertFalse(called.value)
    }

    func testTheSessionIsCreatedWhenTheSystemHandsOverItsEvents() {
        let created = SharedBox(0)
        let counting = BackgroundReportUploader(identifier: "x", container: container, makeSession: { _ in
            created.value += 1
            return FakeReportUploadSession()
        })

        counting.handleEvents(completionHandler: {})

        XCTAssertEqual(created.value, 1)
    }

    func testTheSystemCompletionHandlerRunsWhenTheEventsAreDone() async {
        let done = expectation(description: "completion handler")
        uploader.handleEvents(completionHandler: { done.fulfill() })

        uploader.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)

        await fulfillment(of: [done], timeout: 2)
    }
}

final class SentReportMarkerStoreTests: XCTestCase {

    private var container: ReportContainer!
    private let clock = TestClock()

    override func setUp() {
        super.setUp()
        container = makeTestContainer()
    }

    override func tearDown() {
        if let directory = container.directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private func store() -> SentReportMarkerStore {
        let clock = clock
        return SentReportMarkerStore(container: container, now: { clock.now })
    }

    private func delivery(_ id: String, subscriber: String = "s-1") -> ReportedDelivery {
        ReportedDelivery(messageID: id, subscriberID: subscriber)
    }

    func testARecordedDeliveryIsFoundForItsSubscriberOnly() {
        store().record([delivery("m-1")])

        XCTAssertTrue(store().contains(delivery("m-1")))
        XCTAssertFalse(store().contains(delivery("m-1", subscriber: "s-2")))
        XCTAssertFalse(store().contains(delivery("m-2")))
    }

    func testTheStoreHoldsTheLastThousand() {
        store().record((0..<1005).map { delivery("m-\($0)") })

        XCTAssertFalse(store().contains(delivery("m-4")))
        XCTAssertTrue(store().contains(delivery("m-5")))
        XCTAssertTrue(store().contains(delivery("m-1004")))
    }

    func testMarkersExpireAfterSevenDays() {
        store().record([delivery("old")])
        clock.advance(by: 6 * 24 * 3600)
        store().record([delivery("newer")])
        XCTAssertTrue(store().contains(delivery("old")))

        clock.advance(by: 2 * 24 * 3600)

        XCTAssertFalse(store().contains(delivery("old")))
        XCTAssertTrue(store().contains(delivery("newer")))
    }

    func testRecordingTwiceKeepsOneMarker() {
        store().record([delivery("m-1")])
        store().record([delivery("m-1")])

        XCTAssertEqual(store().sent(among: [delivery("m-1")]).count, 1)
    }

    func testSentAmongReturnsTheMarkedOnes() {
        store().record([delivery("a"), delivery("c")])

        XCTAssertEqual(store().sent(among: [delivery("a"), delivery("b"), delivery("c")]), [delivery("a"), delivery("c")])
    }

    func testTwoStoresOnTheSameContainerShareTheMarkers() {
        SentReportMarkerStore(container: container).record([delivery("m-1")])

        let other = ReportContainer(appGroup: "group.test", directory: container.directory?.deletingLastPathComponent())
        XCTAssertTrue(SentReportMarkerStore(container: other).contains(delivery("m-1")))
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_770_000_000)

    var now: Date { lock.withLock { date } }

    func advance(by seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

/// A value the test and a `@Sendable` callback share.
final class SharedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
