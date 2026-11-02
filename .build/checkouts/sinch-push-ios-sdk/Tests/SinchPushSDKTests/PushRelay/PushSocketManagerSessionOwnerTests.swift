import XCTest
@testable import SinchPushSDK

/// The outbox and the replay cursor belong to one identity; a replaced client cannot leak into the next session.
@MainActor
final class PushSocketManagerSessionOwnerTests: XCTestCase {

    private var rig: RelayTestHarness!

    override func setUp() async throws {
        try await super.setUp()
        rig = RelayTestHarness()
    }

    // MARK: - Session owner: the outbox and the replay cursor belong to one identity

    private func pendingReport(_ id: String) -> PendingReport {
        PendingReport(messageId: id, sinchMessageId: "sinch-\(id)", status: .displayed, reason: "", attempts: 0,
                      deferUntilMs: nil)
    }

    func testTheOutboxAndTheCursorSurviveAColdLaunchForTheSameUser() async throws {
        let store = FakeSocketStateStore(lastSeen: "m-old", lastSeenEnqueuedAt: 5_000, outbox: [pendingReport("m-1")])
        let relaunched = RelayTestHarness(store: store, owner: ownerOfUser1)

        relaunched.start()
        await relaunched.flush()
        relaunched.factory.current?.openSocket()

        XCTAssertEqual(relaunched.factory.current?.hellos.first?.lastSeenMessageID, "m-old")
        await relaunched.handshake()
        XCTAssertEqual(relaunched.factory.current?.reports.map(\.messageID), ["m-1"], "the pending report is sent")
        XCTAssertEqual(relaunched.sessionOwner.loadOwner(), ownerOfUser1)
    }

    func testAnotherUserDoesNotInheritTheOutboxOrTheCursor() async throws {
        let store = FakeSocketStateStore(lastSeen: "m-old", lastSeenEnqueuedAt: 5_000, outbox: [pendingReport("m-1")])
        let relaunched = RelayTestHarness(store: store, owner: "app-1|jwt-project|user-0")

        relaunched.start()
        await relaunched.flush()
        relaunched.factory.current?.openSocket()

        XCTAssertEqual(relaunched.factory.current?.hellos.first?.lastSeenMessageID, "", "no replay cursor of user-0")
        XCTAssertTrue(store.loadOutbox().isEmpty)
        XCTAssertEqual(store.loadLastSeenMessageID(), "")
        XCTAssertEqual(store.loadLastSeenEnqueuedAtMs(), 0)
        await relaunched.handshake()
        XCTAssertTrue(relaunched.factory.current?.reports.isEmpty ?? true, "user-0's report is not sent as user-1")
        XCTAssertEqual(relaunched.sessionOwner.loadOwner(), ownerOfUser1)
    }

    func testTheFirstEverSessionStartsClean() async {
        rig.store.saveOutbox([pendingReport("stale")])   // no owner recorded: whoever left this is unknown
        rig.start()
        await rig.flush()
        XCTAssertTrue(rig.store.loadOutbox().isEmpty)
    }

    func testSwitchingUserInTheSameLaunchClearsThePreviousUsersReports() async {
        rig.start()
        await rig.handshake()
        rig.deliverMessage(id: "m-1")
        await rig.flush()
        XCTAssertEqual(rig.store.loadLastSeenMessageID(), "m-1")
        rig.manager.reportStatus(messageId: "m-queued", status: .dismissed)

        rig.start(auth: makeAuthModel(claims: ["uuid": "user-2", "appId": "app-1", "projectId": "jwt-project"]))
        await rig.flush()

        XCTAssertEqual(rig.store.loadLastSeenMessageID(), "")
        XCTAssertFalse(rig.store.loadOutbox().contains { $0.messageId == "m-queued" })
        XCTAssertEqual(rig.sessionOwner.loadOwner(), "app-1|jwt-project|user-2")
        rig.factory.current?.openSocket()
        XCTAssertEqual(rig.factory.current?.hellos.first?.lastSeenMessageID, "")
    }

    func testARetryForTheSameUserKeepsWhatIsPending() async {
        rig.auth.refreshResults = [.failure(AuthDataSourceError.notLoggedIn)]
        rig.start()
        await rig.handshake()
        rig.manager.reportStatus(messageId: "m-queued", status: .dismissed)
        rig.factory.current?.serverClose(reason: .unauthorized)
        await rig.flush()
        await waitUntil { self.rig.manager.state.status == .error }

        rig.start()
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, 2)
        XCTAssertEqual(rig.store.loadOutbox().map(\.messageId), ["m-queued"])
    }

    func testRemovingTheIdentityClearsTheOutboxTheCursorAndTheOwner() async {
        rig.start()
        await rig.handshake()
        rig.deliverMessage(id: "m-1")
        await rig.flush()
        rig.manager.reportStatus(messageId: "m-queued", status: .dismissed)

        rig.manager.stop()
        await rig.flush()

        XCTAssertTrue(rig.store.loadOutbox().isEmpty)
        XCTAssertEqual(rig.store.loadLastSeenMessageID(), "")
        XCTAssertEqual(rig.store.loadLastSeenEnqueuedAtMs(), 0)
        XCTAssertNil(rig.sessionOwner.loadOwner())
        XCTAssertNil(rig.manager.sessionOwner)
    }

    func testAReportMadeAfterRemoveIdentityIsDropped() async {
        rig.start()
        await rig.handshake()
        rig.manager.stop()

        rig.manager.reportStatus(messageId: "m-9", status: .dismissed)

        XCTAssertTrue(rig.store.loadOutbox().isEmpty, "it would otherwise be sent for whoever signs in next")
    }

    func testAReportBeforeAnyIdentityIsDropped() {
        rig.manager.reportStatus(messageId: "m-9", status: .dismissed)
        XCTAssertTrue(rig.store.loadOutbox().isEmpty)
    }

    func testTheNextUserAfterRemoveIdentityStartsClean() async {
        rig.start()
        await rig.handshake()
        rig.manager.stop()
        rig.start(auth: makeAuthModel(claims: ["uuid": "user-2", "appId": "app-1", "projectId": "jwt-project"]))
        await rig.flush()
        rig.factory.current?.openSocket()
        XCTAssertEqual(rig.factory.current?.hellos.first?.lastSeenMessageID, "")
        XCTAssertEqual(rig.sessionOwner.loadOwner(), "app-1|jwt-project|user-2")
    }

    // MARK: - A replaced client cannot leak into the next session

    private func reportedIDs(_ rig: RelayTestHarness) -> [String] { rig.store.loadOutbox().map(\.messageId) }

    func testALatePresenterCompletionOfAReplacedClientDoesNotWriteItsOutboxIntoTheNextUsersStore() async {
        rig.presenter.acceptsPost = true
        rig.presenter.defersCompletions = true
        rig.start()
        await rig.handshake()
        rig.deliverMessage(id: "m-A")
        await rig.flush()
        XCTAssertEqual(rig.presenter.posted.map(\.id), ["m-A"], "the post is out, its completion is not")
        XCTAssertTrue(reportedIDs(rig).contains("m-A"), "A's DELIVERED is in the outbox")
        // The real notification centre's completion keeps the client alive; so does this.
        let clientOfA = rig.manager.client

        rig.start(auth: makeAuthModel(claims: ["uuid": "user-2", "appId": "app-1", "projectId": "jwt-project"]))
        await rig.flush()
        XCTAssertTrue(reportedIDs(rig).isEmpty, "B starts clean")

        rig.presenter.completeDeferred()   // A's notification centre answers late, on A's retired client
        await rig.flush()

        XCTAssertTrue(reportedIDs(rig).isEmpty, "nothing of A's reaches B's store: \(reportedIDs(rig))")
        XCTAssertFalse(clientOfA === rig.manager.client)
        rig.manager.reportStatus(messageId: "m-B", status: .dismissed)
        XCTAssertEqual(reportedIDs(rig), ["m-B"], "B's own tracker is unaffected")
    }

    func testALatePresenterCompletionAfterRemoveIdentityQueuesNoDisplayed() async {
        rig.presenter.acceptsPost = true
        rig.presenter.defersCompletions = true
        rig.start()
        await rig.handshake()
        rig.deliverMessage(id: "m-A")
        await rig.flush()
        let clientOfA = rig.manager.client

        rig.manager.stop()
        await rig.flush()
        XCTAssertTrue(reportedIDs(rig).isEmpty)

        rig.presenter.completeDeferred()
        await rig.flush()

        XCTAssertTrue(reportedIDs(rig).isEmpty, "the removed identity's DISPLAYED is not queued: \(reportedIDs(rig))")
        rig.start(auth: makeAuthModel(claims: ["uuid": "user-2", "appId": "app-1", "projectId": "jwt-project"]))
        await rig.flush()
        XCTAssertTrue(reportedIDs(rig).isEmpty, "and not carried to the next user")
        XCTAssertFalse(clientOfA === rig.manager.client)
    }

    func testAReportAfterRemoveIdentityAndANewStartGoesToTheFreshClientNotARetiredOne() async {
        rig.start()
        await rig.handshake()
        rig.manager.stop()
        rig.start()
        await rig.flush()
        rig.manager.reportStatus(messageId: "m-2", status: .dismissed)
        XCTAssertEqual(reportedIDs(rig), ["m-2"])
    }

    func testAReportBetweenRemoveIdentityAndTheNextStartIsDropped() async {
        rig.start()
        await rig.handshake()
        rig.manager.stop()
        await rig.flush()

        rig.manager.reportStatus(messageId: "m-2", status: .dismissed)
        XCTAssertTrue(reportedIDs(rig).isEmpty, "no owner: nothing is queued for whoever signs in next")

        rig.start()
        await rig.flush()
        XCTAssertTrue(reportedIDs(rig).isEmpty, "and it is not sent after the next start either: \(reportedIDs(rig))")
    }
}
