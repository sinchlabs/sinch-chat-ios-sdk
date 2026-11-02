import Darwin
import SinchPushSDKNotificationExtension
import XCTest

@testable import SinchPushSDK

/// The accounting of finished uploads: where the files are, who keeps the failures, how the session is released.
final class BackgroundReportUploaderBehaviourTests: XCTestCase {

    private var container: ReportContainer!
    private var session: FakeReportUploadSession!
    private let baseURL = URL(string: "https://grpc.sinch-push.prod.sinch.com")!
    private let clock = TestClock()

    override func setUp() {
        super.setUp()
        container = makeTestContainer()
        session = FakeReportUploadSession()
    }

    override func tearDown() {
        if let directory = container.directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private func makeUploader(_ identifier: String) -> BackgroundReportUploader {
        let fake = session!
        return BackgroundReportUploader(identifier: identifier, container: container, makeSession: { _ in fake })
    }

    private func delivery(_ id: String = "m-1") -> ReportedDelivery {
        ReportedDelivery(messageID: id, subscriberID: "s-1")
    }

    private func fail(_ uploader: BackgroundReportUploader, status: Int? = 503, error: Error? = nil) throws {
        let started = try XCTUnwrap(session.started.last)
        uploader.uploadFinished(taskDescription: started.taskDescription, httpStatus: status,
                                headerGrpcStatus: nil, body: Data(), error: error)
    }

    // MARK: - Files

    func testTheManifestCarriesTheFullPathOfTheUploadFile() throws {
        let uploader = makeUploader(BackgroundReportUploader.baseIdentifier)
        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)
        let started = try XCTUnwrap(session.started.first)

        let manifest = try JSONDecoder().decode(BackgroundReportUploader.Manifest.self,
                                                from: Data(started.taskDescription.utf8))

        XCTAssertEqual(manifest.path, started.fileURL.path)
        XCTAssertEqual(manifest.file, started.fileURL.lastPathComponent)
    }

    func testTheFileIsRemovedByItsFullPathWhateverDirectoryTheUploaderHasNow() throws {
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("elsewhere-\(UUID().uuidString)")
        try Data("x".utf8).write(to: elsewhere)
        let description = String(decoding: try JSONEncoder().encode(
            BackgroundReportUploader.Manifest(file: "other.grpcweb", deliveries: [delivery()], path: elsewhere.path)),
                                 as: UTF8.self)
        let uploader = makeUploader(BackgroundReportUploader.baseIdentifier)

        uploader.uploadFinished(taskDescription: description, httpStatus: 200, headerGrpcStatus: "0", body: Data(), error: nil)

        XCTAssertFalse(FileManager.default.fileExists(atPath: elsewhere.path))
    }

    func testAManifestWithoutAPathStillDecodesAndItsFileIsFoundInTheUploadsDirectory() throws {
        let uploader = makeUploader(BackgroundReportUploader.baseIdentifier)
        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)
        let started = try XCTUnwrap(session.started.first)
        let legacy = #"{"file":"\#(started.fileURL.lastPathComponent)","deliveries":[{"messageID":"m-1","subscriberID":"s-1"}]}"#
        let accepted = SharedBox<Bool?>(nil)
        uploader.onFinished = { _, result in accepted.value = result }

        uploader.uploadFinished(taskDescription: legacy, httpStatus: 200, headerGrpcStatus: "0", body: Data(), error: nil)

        XCTAssertEqual(accepted.value, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: started.fileURL.path))
    }

    func testAFrozenContainerKeepsTheAppGroupItHad() {
        let live = ReportContainer(appGroup: nil)
        let frozen = live.frozen()

        live.appGroup = "group.later"

        XCTAssertNil(frozen.appGroup)
        XCTAssertEqual(live.resolved(appGroup: "group.other").appGroup, "group.other")
    }

    func testAnExtensionSessionIsRefusedWithoutAnAppGroup() {
        let unshared = makeTestContainer(appGroup: nil)
        let uploader = BackgroundReportUploader(identifier: BackgroundReportUploader.makeExtensionIdentifier(),
                                                container: unshared)

        XCTAssertFalse(uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL))
        uploader.handleEvents(completionHandler: {})
    }

    // MARK: - Failures of the extension

    func testAFailedExtensionUploadIsLeftToTheApp() throws {
        let uploader = makeUploader(BackgroundReportUploader.makeExtensionIdentifier())
        uploader.upload([delivery("a"), delivery("b")], accessToken: "jwt", baseURL: baseURL)

        try fail(uploader, status: 503)

        let pending = container.takePendingDeliveries()
        XCTAssertEqual(pending.map(\.messageId), ["a", "b"])
        XCTAssertEqual(pending.map(\.subscriberId), ["s-1", "s-1"])
    }

    func testEveryKindOfFailureIsLeftToTheApp() throws {
        let uploader = makeUploader(BackgroundReportUploader.makeExtensionIdentifier())
        for (index, outcome) in [(401, Data()), (500, Data()), (200, Data([0x80, 0, 0, 0, 16]) + Data("grpc-status: 16\r\n".utf8)),
                                 (200, Data())].enumerated() {
            uploader.upload([delivery("m-\(index)")], accessToken: "jwt", baseURL: baseURL)
            let started = try XCTUnwrap(session.started.last)
            uploader.uploadFinished(taskDescription: started.taskDescription, httpStatus: outcome.0,
                                    headerGrpcStatus: nil, body: outcome.1, error: nil)
        }
        uploader.upload([delivery("transport")], accessToken: "jwt", baseURL: baseURL)
        try fail(uploader, status: nil, error: URLError(.timedOut))

        XCTAssertEqual(container.takePendingDeliveries().map(\.messageId), ["m-0", "m-1", "m-2", "m-3", "transport"])
    }

    func testASuccessOfTheExtensionLeavesNothingPending() throws {
        let uploader = makeUploader(BackgroundReportUploader.makeExtensionIdentifier())
        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)
        let started = try XCTUnwrap(session.started.first)

        uploader.uploadFinished(taskDescription: started.taskDescription, httpStatus: 200, headerGrpcStatus: "0",
                                body: Data(), error: nil)

        XCTAssertEqual(container.takePendingDeliveries(), [])
    }

    func testAFailedUploadOfTheAppStaysInTheAppsOutboxOnly() throws {
        let uploader = makeUploader(BackgroundReportUploader.baseIdentifier)
        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)

        try fail(uploader)

        XCTAssertEqual(container.takePendingDeliveries(), [])
    }

    func testTheLegacyExtensionSessionLeavesItsFailuresToTheAppToo() throws {
        let uploader = makeUploader(BackgroundReportUploader.legacyExtensionIdentifier)
        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)

        try fail(uploader)

        XCTAssertEqual(container.takePendingDeliveries().count, 1)
    }

    // MARK: - Registry

    func testAnExtensionUploadRegistersItsSessionForTheApp() {
        let identifier = BackgroundReportUploader.makeExtensionIdentifier()
        makeUploader(identifier).upload([delivery()], accessToken: "jwt", baseURL: baseURL)

        XCTAssertEqual(ReportSessionRegistry(container: container).identifiers(idleFor: 0), [identifier])
    }

    func testAnExtensionUploadReleasesItsSessionOnceStarted() throws {
        let fake = FakeReportUploadSession()
        let identifier = BackgroundReportUploader.makeExtensionIdentifier()
        let uploader = BackgroundReportUploader(identifier: identifier, container: container,
                                                invalidatesSessionAfterUpload: true, makeSession: { _ in fake })

        XCTAssertTrue(uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL))

        XCTAssertEqual(fake.started.count, 1)
        XCTAssertEqual(fake.invalidationCount, 1, "the extension holds no session once the system carries the upload")
        XCTAssertEqual(ReportSessionRegistry(container: container).identifiers(idleFor: 0), [identifier],
                       "registered before it was released")
    }

    func testAnUploaderThatDoesNotReleaseKeepsItsSession() {
        let fake = FakeReportUploadSession()
        let uploader = BackgroundReportUploader(identifier: BackgroundReportUploader.baseIdentifier,
                                                container: container, makeSession: { _ in fake })

        uploader.upload([delivery()], accessToken: "jwt", baseURL: baseURL)

        XCTAssertEqual(fake.invalidationCount, 0)
    }

    func testTheAppsUploadIsNotRegistered() {
        makeUploader(BackgroundReportUploader.baseIdentifier).upload([delivery()], accessToken: "jwt", baseURL: baseURL)

        XCTAssertEqual(ReportSessionRegistry(container: container).identifiers(idleFor: 0), [])
    }

    // MARK: - Events

    func testEveryCompletionHandlerOfTheSystemIsCalledOnce() async {
        let uploader = makeUploader(BackgroundReportUploader.baseIdentifier)
        let calls = SharedBox([String]())
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        uploader.handleEvents(completionHandler: { calls.value.append("first"); first.fulfill() })
        uploader.handleEvents(completionHandler: { calls.value.append("second"); second.fulfill() })

        uploader.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        uploader.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)

        await fulfillment(of: [first, second], timeout: 2)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls.value.sorted(), ["first", "second"])
    }

    func testAnUploaderThatReleasesItsSessionDoesSoWhenTheEventsAreDone() {
        let uploader = makeUploader(BackgroundReportUploader.makeExtensionIdentifier())
        uploader.releaseSessionWhenDone()
        uploader.handleEvents(completionHandler: {})
        XCTAssertEqual(session.invalidationCount, 0)

        uploader.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)

        XCTAssertEqual(session.invalidationCount, 1)
    }

    func testTheAppsSessionIsNotReleasedAfterItsEvents() {
        let uploader = makeUploader(BackgroundReportUploader.baseIdentifier)
        uploader.handleEvents(completionHandler: {})

        uploader.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)

        XCTAssertEqual(session.invalidationCount, 0)
    }

    func testAnActivatedSessionIsReleasedAfterTheGrace() {
        let uploader = makeUploader(BackgroundReportUploader.makeExtensionIdentifier())

        uploader.activate(releaseAfter: 0.05)

        let deadline = Date().addingTimeInterval(2)
        while session.invalidationCount == 0 && Date() < deadline { usleep(10_000) }
        XCTAssertEqual(session.invalidationCount, 1)
    }

    func testAnInvalidatedSessionIsReportedAndMadeAgain() {
        let created = SharedBox(0)
        let uploader = BackgroundReportUploader(identifier: "x", container: container, makeSession: { _ in
            created.value += 1
            return FakeReportUploadSession()
        })
        let invalidated = SharedBox(0)
        uploader.onInvalidated = { invalidated.value += 1 }
        uploader.activate()

        uploader.urlSession(.shared, didBecomeInvalidWithError: nil)
        uploader.activate()

        XCTAssertEqual(invalidated.value, 1)
        XCTAssertEqual(created.value, 2)
    }
}

/// The flock of the shared files must not block a process that could be suspended while it holds it.
final class ReportContainerLockTests: XCTestCase {

    func testALockAnotherProcessHoldsDoesNotBlockForever() throws {
        let container = makeTestContainer()
        defer { if let directory = container.directory { try? FileManager.default.removeItem(at: directory) } }
        let lockURL = try XCTUnwrap(container.directory).appendingPathComponent("held.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        XCTAssertEqual(flock(descriptor, LOCK_EX), 0)
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        let started = Date()

        let ran = container.withFileLock(named: "held.lock") { true }

        XCTAssertTrue(ran, "the body runs, without the lock")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testAFreeLockIsTakenAndReleased() throws {
        let container = makeTestContainer()
        defer { if let directory = container.directory { try? FileManager.default.removeItem(at: directory) } }

        XCTAssertEqual(container.withFileLock(named: "a.lock") { 1 }, 1)
        XCTAssertEqual(container.withFileLock(named: "a.lock") { 2 }, 2)
    }
}
