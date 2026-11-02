import SinchPushSDKNotificationExtension
import XCTest

@testable import SinchPushSDK

/// `handleEventsForBackgroundURLSession`: which sessions are the SDK's, and who gets told.
@MainActor
final class BackgroundURLSessionEventsTests: XCTestCase {

    private var container: ReportContainer!
    private var created: CreatedSessions!
    private var uploaders: ReportUploaders!
    private let defaults = UserDefaults(suiteName: "uploaders-tests-\(UUID().uuidString)")!
    private let extensionIdentifier = "com.sinch.chatsdk.reports.nse.7C1E5A52-9D1F-4A43-8F55-0F1D1D3C7A10"

    private final class CreatedSessions: @unchecked Sendable {
        private let lock = NSLock()
        private var identifiers: [String] = []
        var all: [String] { lock.withLock { identifiers } }
        func add(_ identifier: String) { lock.withLock { identifiers.append(identifier) } }
    }

    override func setUp() async throws {
        try await super.setUp()
        container = makeTestContainer()
        let created = CreatedSessions()
        self.created = created
        uploaders = ReportUploaders(container: container, defaults: defaults, makeUploader: { identifier, container in
            created.add(identifier)
            return BackgroundReportUploader(identifier: identifier, container: container,
                                            makeSession: { _ in FakeReportUploadSession() })
        })
    }

    override func tearDown() async throws {
        if let directory = container.directory { try? FileManager.default.removeItem(at: directory) }
        try await super.tearDown()
    }

    func testTheSessionOfTheAppIsTheSDKs() {
        XCTAssertTrue(uploaders.handleEvents(identifier: "com.sinch.chatsdk.reports", completionHandler: {}))
        XCTAssertEqual(created.all, ["com.sinch.chatsdk.reports"])
    }

    func testTheSessionOfAnExtensionProcessIsTheSDKs() {
        XCTAssertTrue(uploaders.handleEvents(identifier: extensionIdentifier, completionHandler: {}))
        XCTAssertEqual(created.all, [extensionIdentifier])
    }

    func testTheOldSessionOfTheExtensionIsStillTheSDKs() {
        XCTAssertTrue(uploaders.handleEvents(identifier: "com.sinch.chatsdk.reports.nse", completionHandler: {}))
        XCTAssertEqual(created.all, ["com.sinch.chatsdk.reports.nse"])
    }

    func testTheUploaderOfAnExtensionSessionIsBuiltForItsExactIdentifier() throws {
        let uploader = try XCTUnwrap(uploaders.uploader(forIdentifier: extensionIdentifier))

        XCTAssertEqual(uploader.identifier, extensionIdentifier)
    }

    func testTwoExtensionSessionsGetTheirOwnUploaders() throws {
        let other = extensionIdentifier + "2"

        let first = try XCTUnwrap(uploaders.uploader(forIdentifier: extensionIdentifier))
        let second = try XCTUnwrap(uploaders.uploader(forIdentifier: other))

        XCTAssertFalse(first === second)
        XCTAssertEqual(created.all, [extensionIdentifier, other])
    }

    func testAnExtensionUploaderIsMadeAgainOnceItsSessionIsReleased() throws {
        let first = try XCTUnwrap(uploaders.uploader(forIdentifier: extensionIdentifier))
        XCTAssertTrue(first === uploaders.uploader(forIdentifier: extensionIdentifier))

        first.urlSession(.shared, didBecomeInvalidWithError: nil)

        XCTAssertFalse(first === uploaders.uploader(forIdentifier: extensionIdentifier))
    }

    func testAReleasedExtensionSessionIsForgottenByTheRegistry() throws {
        ReportSessionRegistry(container: container).touch(extensionIdentifier)
        let uploader = try XCTUnwrap(uploaders.uploader(forIdentifier: extensionIdentifier))

        uploader.urlSession(.shared, didBecomeInvalidWithError: nil)

        XCTAssertEqual(ReportSessionRegistry(container: container).identifiers(idleFor: 0), [])
    }

    func testAnExtensionSessionNeedsAnAppGroup() {
        let unshared = ReportUploaders(container: makeTestContainer(appGroup: nil), defaults: defaults)

        XCTAssertNil(unshared.uploader(forIdentifier: extensionIdentifier))
        XCTAssertFalse(unshared.handleEvents(identifier: extensionIdentifier, completionHandler: {}))
        XCTAssertNotNil(unshared.uploader(forIdentifier: BackgroundReportUploader.baseIdentifier), "the app's own does not")
    }

    func testTheLastAppGroupServesAnExtensionSessionWhenNoneIsSetNow() {
        let live = ReportContainer(appGroup: nil, directory: container.directory?.deletingLastPathComponent())
        defaults.set("group.test", forKey: "com.sinch.push.reports.lastAppGroup")
        let remembering = ReportUploaders(container: live, defaults: defaults, makeUploader: { identifier, container in
            BackgroundReportUploader(identifier: identifier, container: container, makeSession: { _ in FakeReportUploadSession() })
        })

        XCTAssertTrue(remembering.handleEvents(identifier: extensionIdentifier, completionHandler: {}))
    }

    func testAnotherSessionIsNotTheSDKsAndItsHandlerIsNotTaken() {
        let called = SharedBox(false)

        XCTAssertFalse(uploaders.handleEvents(identifier: "com.host.downloads", completionHandler: { called.value = true }))
        XCTAssertFalse(uploaders.handleEvents(identifier: "com.sinch.chatsdk.reports.other", completionHandler: {}))
        XCTAssertFalse(uploaders.handleEvents(identifier: "com.sinch.chatsdk.reports.nse.", completionHandler: {}))
        XCTAssertFalse(uploaders.handleEvents(identifier: "com.sinch.chatsdk.reports.nsex", completionHandler: {}))

        XCTAssertFalse(called.value)
        XCTAssertEqual(created.all, [])
    }

    func testTheSameUploaderServesRepeatedEvents() {
        _ = uploaders.handleEvents(identifier: "com.sinch.chatsdk.reports", completionHandler: {})
        _ = uploaders.handleEvents(identifier: "com.sinch.chatsdk.reports", completionHandler: {})

        XCTAssertEqual(created.all.count, 1, "a process may hold one session per identifier")
    }

    func testTheHandlerRunsWhenTheSessionHasDeliveredItsEvents() async throws {
        let done = expectation(description: "handler")
        XCTAssertTrue(uploaders.handleEvents(identifier: "com.sinch.chatsdk.reports", completionHandler: { done.fulfill() }))

        let uploader = try XCTUnwrap(uploaders.uploader(forIdentifier: "com.sinch.chatsdk.reports"))
        uploader.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)

        await fulfillment(of: [done], timeout: 2)
    }

    func testAFinishedUploadIsReportedToTheReporter() async throws {
        let rig = DeliveryReporterRig()
        uploaders.reporter = rig.reporter
        rig.queue(1)
        rig.outbox.markInFlight(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 10), untilMs: Int64.max)
        let uploader = try XCTUnwrap(uploaders.uploader(forIdentifier: extensionIdentifier))
        let description = String(decoding: try JSONEncoder().encode(
            BackgroundReportUploader.Manifest(file: "x.grpcweb",
                                              deliveries: [ReportedDelivery(messageID: "m-0", subscriberID: "s-1")])),
                                 as: UTF8.self)

        uploader.uploadFinished(taskDescription: description, httpStatus: 200, headerGrpcStatus: "0", body: Data(), error: nil)

        XCTAssertEqual(rig.outbox.count, 0)
    }

    private func manifestDescription() throws -> String {
        String(decoding: try JSONEncoder().encode(
            BackgroundReportUploader.Manifest(file: "x.grpcweb",
                                              deliveries: [ReportedDelivery(messageID: "m-0", subscriberID: "s-1")])),
               as: UTF8.self)
    }

    func testAFailedUploadOfTheExtensionQueuesItsPendingDeliveriesAtOnce() throws {
        let rig = DeliveryReporterRig()
        uploaders.reporter = rig.reporter
        rig.pendingDeliveries = [ReportedDelivery(messageID: "e-1", subscriberID: "s-1")]
        let uploader = try XCTUnwrap(uploaders.uploader(forIdentifier: extensionIdentifier))

        uploader.uploadFinished(taskDescription: try manifestDescription(), httpStatus: 503, headerGrpcStatus: nil,
                                body: Data(), error: nil)

        XCTAssertEqual(rig.outbox.nextBatch(nowMs: rig.scheduler.nowMs(), limit: 10).map(\.messageID), ["e-1"])
        XCTAssertTrue(rig.pendingDeliveries.isEmpty)
    }

    func testAnAcceptedUploadOfTheExtensionDrainsNothing() throws {
        let rig = DeliveryReporterRig()
        uploaders.reporter = rig.reporter
        rig.pendingDeliveries = [ReportedDelivery(messageID: "e-1", subscriberID: "s-1")]
        let uploader = try XCTUnwrap(uploaders.uploader(forIdentifier: extensionIdentifier))

        uploader.uploadFinished(taskDescription: try manifestDescription(), httpStatus: 200, headerGrpcStatus: "0",
                                body: Data(), error: nil)

        XCTAssertEqual(rig.outbox.count, 0)
        XCTAssertEqual(rig.pendingDeliveries.count, 1)
    }

    func testAFailedUploadOfTheAppDrainsNothing() throws {
        let rig = DeliveryReporterRig()
        uploaders.reporter = rig.reporter
        rig.pendingDeliveries = [ReportedDelivery(messageID: "e-1", subscriberID: "s-1")]
        let uploader = try XCTUnwrap(uploaders.uploader(forIdentifier: BackgroundReportUploader.baseIdentifier))

        uploader.uploadFinished(taskDescription: try manifestDescription(), httpStatus: 503, headerGrpcStatus: nil,
                                body: Data(), error: nil)

        XCTAssertEqual(rig.pendingDeliveries.count, 1, "its deliveries are in the app's own outbox")
    }

    // MARK: - Activation

    func testAnExtensionSessionIsReopenedOnceItsGraceHasPassed() {
        XCTAssertEqual(ReportUploaders.extensionSessionIdleTime, 30)
        let grace = ReportUploaders.extensionSessionIdleTime
        ReportSessionRegistry(container: container, now: { Date().addingTimeInterval(-grace - 5) })
            .touch(extensionIdentifier)
        ReportSessionRegistry(container: container, now: { Date().addingTimeInterval(-grace + 20) })
            .touch(extensionIdentifier + "-fresh")

        uploaders.activateSessions()

        XCTAssertEqual(Set(created.all), [BackgroundReportUploader.baseIdentifier, extensionIdentifier],
                       "a registration a minute old needs no five minutes of idling")
    }

    func testActivatingCreatesTheAppsSessionAndIsRepeatable() {
        uploaders.activateSessions()
        uploaders.activateSessions()

        XCTAssertEqual(created.all, [BackgroundReportUploader.baseIdentifier])
    }

    func testActivatingReopensTheIdleSessionsOfTheExtension() {
        let registry = ReportSessionRegistry(container: container, now: { Date().addingTimeInterval(-3600) })
        registry.touch(extensionIdentifier)
        ReportSessionRegistry(container: container).touch(extensionIdentifier + "-recent")

        uploaders.activateSessions()

        XCTAssertEqual(Set(created.all), [BackgroundReportUploader.baseIdentifier, extensionIdentifier])
    }

    func testActivatingWithoutAnAppGroupOpensTheAppsSessionOnly() {
        let created = CreatedSessions()
        let unshared = ReportUploaders(container: makeTestContainer(appGroup: nil), defaults: defaults,
                                       makeUploader: { identifier, container in
            created.add(identifier)
            return BackgroundReportUploader(identifier: identifier, container: container,
                                            makeSession: { _ in FakeReportUploadSession() })
        })

        unshared.activateSessions()

        XCTAssertEqual(created.all, [BackgroundReportUploader.baseIdentifier])
    }

    // MARK: - Through SinchPush

    func testTheHostsAppDelegateCallReachesTheSDKsSessions() {
        let harness = RelayTestHarness()
        let push = DefaultSinchPush(pushNotificationHandler: RoutingHandlerStub(),
                                    inAppPresenter: InAppControllerStub(),
                                    socketManager: harness.manager, relaySettings: harness.settings,
                                    reportUploaders: uploaders)

        XCTAssertTrue(push.handleEventsForBackgroundURLSession(identifier: extensionIdentifier, completionHandler: {}))
        XCTAssertFalse(push.handleEventsForBackgroundURLSession(identifier: "com.host.downloads", completionHandler: {}))
    }

    func testWithoutUploadersNoSessionIsTheSDKs() {
        let harness = RelayTestHarness()
        let push = DefaultSinchPush(pushNotificationHandler: RoutingHandlerStub(),
                                    inAppPresenter: InAppControllerStub(),
                                    socketManager: harness.manager, relaySettings: harness.settings)

        XCTAssertFalse(push.handleEventsForBackgroundURLSession(identifier: "com.sinch.chatsdk.reports", completionHandler: {}))
    }
}
