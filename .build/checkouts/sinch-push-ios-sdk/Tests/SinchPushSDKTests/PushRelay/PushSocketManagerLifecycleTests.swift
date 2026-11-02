import XCTest
@testable import SinchPushSDK

/// Start, background suspension, identity changes, and stop: the socket and the lifecycle observer follow the session.
@MainActor
final class PushSocketManagerLifecycleTests: XCTestCase {

    private var rig: RelayTestHarness!

    override func setUp() async throws {
        try await super.setUp()
        rig = RelayTestHarness()
    }

    // MARK: - Start

    func testStartObservesTheLifecycleAndSuspendsInTheBackground() async {
        rig.start()
        await rig.flush()
        XCTAssertEqual(rig.lifecycle?.isObserving, true)

        await rig.handshake()
        XCTAssertEqual(rig.manager.state.status, .connected)

        rig.lifecycle?.onBackground?()
        await rig.flush()
        XCTAssertEqual(rig.manager.state.status, .idle)
        XCTAssertEqual(rig.factory.current?.closeCalls.last?.code, 1000)

        rig.lifecycle?.onForeground?()
        await rig.flush()
        XCTAssertEqual(rig.factory.createdCount, 2)
        XCTAssertEqual(rig.manager.state.status, .connecting)
    }

    func testStartedInTheBackgroundDoesNotHoldASocket() async {
        rig.state.isInBackground = true
        rig.start()
        await rig.flush()

        XCTAssertEqual(rig.manager.state.status, .idle)
        XCTAssertEqual(rig.factory.current?.closeCalls.last?.code, 1000)
        rig.lifecycle?.onForeground?()
        XCTAssertEqual(rig.factory.createdCount, 2)
    }

    // MARK: - Same / other identity

    func testSameIdentityAndTokenIsIdempotent() async {
        rig.start()
        await rig.flush()
        rig.start()
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, 1)
        XCTAssertEqual(rig.lifecycles.count, 1)
    }

    func testSameIdentityWithANewTokenReconnectsWithIt() async throws {
        rig.start()
        let refreshed = makeAuthModel(claims: ["uuid": "user-1", "appId": "app-1", "projectId": "jwt-project", "n": 2])
        rig.start(auth: refreshed)
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, 2)
        rig.factory.current?.openSocket()
        XCTAssertEqual(rig.factory.current?.hellos.first?.authToken, refreshed.accessToken)
        XCTAssertEqual(rig.lifecycles.count, 1, "the same session keeps its client and lifecycle observer")
    }

    func testADifferentIdentityRestartsWithTheNewConfiguration() async throws {
        rig.start()
        await rig.handshake()
        rig.start(auth: makeAuthModel(claims: ["uuid": "user-2", "appId": "app-1"]))
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, 2)
        XCTAssertEqual(rig.factory.sockets[0].closeCalls.last?.code, 1000, "the old socket is closed")
        rig.factory.current?.openSocket()
        XCTAssertEqual(rig.factory.current?.hellos.first?.userID, "user-2")
        XCTAssertEqual(rig.lifecycles.count, 2)
        XCTAssertEqual(rig.lifecycles.first?.isObserving, false)
        XCTAssertEqual(rig.lifecycle?.isObserving, true)
        XCTAssertEqual(rig.manager.state.relayEnabled, true)
    }

    // MARK: - Stop

    func testStopClosesTheSocketAndDropsTheSessionState() async {
        rig.start()
        await rig.handshake()
        XCTAssertNil(rig.store.loadConfiguration(), "the SDK never persists the relay configuration")
        XCTAssertNotNil(rig.tokenStore.loadToken(), "the JWT is held in memory for this session only")

        rig.manager.stop()
        await rig.flush()

        XCTAssertEqual(rig.factory.current?.closeCalls.last?.code, 1000)
        XCTAssertEqual(rig.lifecycle?.isObserving, false)
        XCTAssertNil(rig.tokenStore.loadToken())
        XCTAssertNil(rig.store.loadConfiguration())
        XCTAssertNil(rig.manager.socketConfiguration)
        XCTAssertEqual(rig.manager.state.status, .stopped)
        XCTAssertFalse(rig.manager.state.relayEnabled)
        XCTAssertEqual(rig.manager.state.disabledReason, "identity removed")
    }

    func testStopBeforeStartIsIdle() {
        rig.manager.stop()
        XCTAssertEqual(rig.manager.state.status, .idle)
        XCTAssertEqual(rig.factory.createdCount, 0)
    }

    func testEventsQueuedBeforeStopAreNotPublishedAfterIt() async {
        let states = PublisherCollector(rig.manager.stateSubject)
        let messages = PublisherCollector(rig.manager.messageSubject)
        rig.start()
        await rig.handshake()
        rig.deliverMessage(id: "m-1")   // queued for the main actor, not run yet
        rig.manager.stop()
        await rig.flush()

        XCTAssertTrue(messages.values.isEmpty)
        XCTAssertEqual(states.values.last?.status, .stopped)
        XCTAssertEqual(rig.manager.state.status, .stopped)
    }

    func testStartAfterStopWorksAgain() async {
        rig.start()
        rig.manager.stop()
        rig.start()
        await rig.flush()
        XCTAssertEqual(rig.factory.createdCount, 2)
        XCTAssertEqual(rig.manager.state.status, .connecting)
        XCTAssertEqual(rig.lifecycle?.isObserving, true)
    }

    // MARK: - setIdentity for a different identity stops the running relay

    func testASetIdentityForAnotherIdentityStopsTheRunningRelay() async {
        rig.start()
        await rig.handshake()

        rig.manager.identityWillChange(config: makeAppConfig(), identity: .selfSigned(userId: "user-2", secret: "s"))
        await rig.flush()

        XCTAssertNil(rig.manager.socketConfiguration)
        XCTAssertEqual(rig.manager.state.status, .stopped)
        XCTAssertEqual(rig.factory.current?.closeCalls.last?.code, 1000)
        XCTAssertEqual(rig.lifecycle?.isObserving, false)
        XCTAssertEqual(rig.manager.sessionOwner, ownerOfUser1, "the outbox is kept for a later same-owner session")
    }

    func testASetIdentityForAnotherConfigurationStopsTheRunningRelay() async {
        rig.start()
        await rig.handshake()

        rig.manager.identityWillChange(config: makeAppConfig(relay: .disabled),
                                       identity: .selfSigned(userId: "user-1", secret: "s"))
        XCTAssertNil(rig.manager.socketConfiguration)
        XCTAssertEqual(rig.manager.state.status, .stopped)
    }

    func testASetIdentityForTheSameIdentityLeavesTheRelayRunning() async {
        rig.start()
        await rig.handshake()

        rig.manager.identityWillChange(config: makeAppConfig(), identity: .selfSigned(userId: "user-1", secret: "s"))
        await rig.flush()

        XCTAssertNotNil(rig.manager.socketConfiguration)
        XCTAssertEqual(rig.manager.state.status, .connected)
    }

    func testASetIdentityWithNoRunningRelayChangesNothing() {
        rig.manager.identityWillChange(config: makeAppConfig(), identity: .anonymous)
        XCTAssertEqual(rig.manager.state.status, .idle)
        XCTAssertEqual(rig.manager.state.disabledReason, "relay not started (setIdentity has not succeeded yet)")
    }
}
