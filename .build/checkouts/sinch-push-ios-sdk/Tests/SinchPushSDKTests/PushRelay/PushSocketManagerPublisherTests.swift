import Combine
import XCTest
@testable import SinchPushSDK

/// Published state and messages, in-app routing, status reports, and the cached installation id.
@MainActor
final class PushSocketManagerPublisherTests: XCTestCase {

    private var rig: RelayTestHarness!

    override func setUp() async throws {
        try await super.setUp()
        rig = RelayTestHarness()
    }

    // MARK: - Publishers

    func testStatePublisherReplaysTheCurrentValue() async {
        rig.start()
        await rig.flush()
        let late = PublisherCollector(rig.manager.stateSubject)
        XCTAssertEqual(late.values.count, 1)
        XCTAssertEqual(late.values.first?.status, .connecting)
        await rig.handshake()
        XCTAssertEqual(late.values.last?.status, .connected)
    }

    func testStateMapsEveryCoreStatus() {
        let pairs: [(SocketStatus, SinchPushSocketStatus)] = [
            (.idle, .idle), (.connecting, .connecting), (.connected, .connected), (.reconnecting, .reconnecting),
            (.error, .error), (.stopped, .stopped), (.authRequired, .authRequired), (.replaced, .replaced)
        ]
        XCTAssertEqual(pairs.count, SocketStatus.allCases.count)
        for (core, mapped) in pairs {
            XCTAssertEqual(SinchPushSocketStatus(core), mapped)
        }
    }

    func testAMessageIsPublishedOnceWithItsFields() async throws {
        let messages = PublisherCollector(rig.manager.messageSubject)
        rig.start()
        await rig.handshake()

        rig.deliverMessage(id: "m-1", metadata: ["owner": "sinch", "topic_id": "t"], title: "Hi")
        rig.deliverMessage(id: "m-1", title: "dupe")
        await rig.flush()

        XCTAssertEqual(messages.values.count, 1)
        let message = try XCTUnwrap(messages.values.first)
        XCTAssertEqual(message.id, "m-1")
        XCTAssertEqual(message.sinchMessageId, "sinch-m-1")
        XCTAssertEqual(message.title, "Hi")
        XCTAssertNil(message.body)
        XCTAssertNil(message.imageUrl)
        XCTAssertEqual(message.metadata, ["owner": "sinch", "topic_id": "t"])
        XCTAssertEqual(message.enqueuedAt, Date(timeIntervalSince1970: 1_770_000_000))
    }

    func testAMessageSeenThroughAnotherChannelIsNotPublished() async {
        let messages = PublisherCollector(rig.manager.messageSubject)
        rig.registry.markSeen("m-apns")
        rig.start()
        await rig.handshake()

        rig.deliverMessage(id: "m-apns")
        await rig.flush()
        XCTAssertTrue(messages.values.isEmpty)
        XCTAssertTrue(rig.presenter.posted.isEmpty)
    }

    func testAMessagePostsALocalNotificationAndReportsDisplayed() async {
        rig.start()
        await rig.handshake()
        rig.deliverMessage(id: "m-1", metadata: ["owner": "sinch"])
        await rig.flush()

        XCTAssertEqual(rig.presenter.posted.map(\.id), ["m-1"])
        XCTAssertEqual(rig.presenter.posted.first?.metadata, ["owner": "sinch"])
        await waitUntil { !self.rig.factory.current!.reports.filter { $0.status == .displayed }.isEmpty }
    }

    // MARK: - In-app routing

    func testAnInAppMessageIsShownInTheAppInsteadOfPostingANotification() async throws {
        rig.state.inAppResult = { _ in true }
        let metadata = ["owner": "sinch", "protobufPayload": "AAAA"]
        rig.start()
        await rig.handshake()
        rig.deliverMessage(id: "m-1", metadata: metadata)
        await rig.flush()

        XCTAssertEqual(rig.inAppOffers, [metadata])
        XCTAssertTrue(rig.presenter.posted.isEmpty, "no system notification for a message shown in-app")
        await waitUntil { !self.rig.factory.current!.reports.filter { $0.status == .displayed }.isEmpty }
    }

    func testAMessageThatIsNotInAppFallsThroughToTheSystemNotification() async {
        rig.state.inAppResult = { _ in false }
        rig.start()
        await rig.handshake()
        rig.deliverMessage(id: "m-1", metadata: ["owner": "sinch"])
        await rig.flush()

        XCTAssertEqual(rig.inAppOffers.count, 1)
        XCTAssertEqual(rig.presenter.posted.map(\.id), ["m-1"])
    }

    func testTheMessageIsPublishedBeforeTheInAppOffer() async {
        let state = rig.state
        let cancellable = rig.manager.messageSubject.sink { _ in state.log.append("published") }
        rig.state.inAppResult = { _ in state.log.append("in-app"); return true }
        rig.start()
        await rig.handshake()
        rig.deliverMessage(id: "m-1")
        await rig.flush()
        XCTAssertEqual(state.log, ["published", "in-app"])
        cancellable.cancel()
    }

    // MARK: - Reports

    func testReportStatusSendsAReportWhenConnected() async {
        rig.start()
        await rig.handshake()
        rig.manager.reportStatus(messageId: "m-1", status: .dismissed)
        XCTAssertEqual(rig.factory.current?.reports.map(\.status), [.dismissed])
        XCTAssertEqual(rig.factory.current?.reports.first?.messageID, "m-1")
    }

    func testReportStatusIsQueuedUntilTheSocketConnects() async {
        rig.start()
        rig.manager.reportStatus(messageId: "m-1", status: .displayed)
        XCTAssertTrue(rig.factory.current?.reports.isEmpty ?? true)
        XCTAssertEqual(rig.store.loadOutbox().map(\.messageId), ["m-1"])

        await rig.handshake()
        XCTAssertEqual(rig.factory.current?.reports.map(\.status), [.displayed])
    }

    func testReportStatusWithAnEmptyIdIsIgnored() {
        rig.start()
        rig.manager.reportStatus(messageId: "", status: .displayed)
        XCTAssertTrue(rig.store.loadOutbox().isEmpty)
    }

    func testInstallationIdIsCachedAfterTheFirstSuccessfulRead() {
        rig.state.installationId = nil
        XCTAssertNil(rig.manager.installationId)
        XCTAssertNil(rig.manager.installationId)
        XCTAssertEqual(rig.state.installationIdReads, 2, "an unreadable id is asked for again")

        rig.state.installationId = "install-1"
        XCTAssertEqual(rig.manager.installationId, "install-1")
        rig.state.installationId = "other"
        XCTAssertEqual(rig.manager.installationId, "install-1")
        XCTAssertEqual(rig.state.installationIdReads, 3, "read once, then served from the cache")
    }
}
