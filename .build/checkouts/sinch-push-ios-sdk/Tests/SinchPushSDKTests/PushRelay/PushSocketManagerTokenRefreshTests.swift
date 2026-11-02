import XCTest
@testable import SinchPushSDK

/// `auth_required` closes: one refresh per session, and a refreshed token must belong to the same user.
@MainActor
final class PushSocketManagerTokenRefreshTests: XCTestCase {

    private var rig: RelayTestHarness!

    override func setUp() async throws {
        try await super.setUp()
        rig = RelayTestHarness()
    }

    // MARK: - auth_required

    func testRetryingFromAuthRequiredStartsACleanSession() async {
        rig.auth.refreshResults = [.failure(AuthDataSourceError.notLoggedIn)]
        rig.start()
        await rig.handshake()
        rig.factory.current?.serverClose(reason: .unauthorized)
        await rig.flush()
        await waitUntil { self.rig.manager.state.status == .error }

        rig.start()
        await rig.flush()
        XCTAssertEqual(rig.factory.createdCount, 2)
        XCTAssertEqual(rig.manager.state.status, .connecting)
    }

    func testAuthRequiredRefreshesTheTokenOnceAndReconnects() async {
        let refreshed = makeAuthModel(claims: ["uuid": "user-1", "appId": "app-1", "projectId": "jwt-project", "n": 2])
        rig.auth.suspendsRefreshes = true
        rig.start()
        await rig.handshake()

        rig.factory.current?.serverClose(reason: .unauthorized, detail: "expired")
        await rig.auth.waitForRefreshCall(1)
        rig.auth.finishRefresh(with: .success(refreshed))
        await waitUntil { self.rig.factory.createdCount == 2 }

        XCTAssertEqual(rig.auth.refreshCount, 1)
        rig.factory.current?.openSocket()
        XCTAssertEqual(rig.factory.current?.hellos.first?.authToken, refreshed.accessToken)
        XCTAssertEqual(rig.manager.socketConfiguration?.authToken, refreshed.accessToken)

        await rig.handshake()
        rig.factory.current?.serverClose(reason: .unauthorized, detail: "still bad")
        await rig.settle()
        XCTAssertEqual(rig.auth.refreshCount, 1)
        XCTAssertEqual(rig.auth.suspendedRefreshCount, 0)
        XCTAssertEqual(rig.factory.createdCount, 2)
        XCTAssertEqual(rig.manager.state.status, .authRequired)
    }

    func testAdoptingARefreshedTokenCallsBack() async {
        var refreshedCount = 0
        rig.manager.onAccessTokenRefreshed = { refreshedCount += 1 }
        rig.auth.refreshResults = [.success(makeAuthModel(claims: ["uuid": "user-1", "appId": "app-1", "projectId": "jwt-project", "n": 2]))]
        rig.start()
        await rig.handshake()

        rig.factory.current?.serverClose(reason: .unauthorized)
        await waitUntil { refreshedCount == 1 }
    }

    func testARejectedRefreshDoesNotCallBack() async {
        var refreshedCount = 0
        rig.manager.onAccessTokenRefreshed = { refreshedCount += 1 }
        rig.auth.refreshResults = [.success(makeAuthModel(claims: ["uuid": "someone-else", "appId": "app-1"]))]
        rig.start()
        await rig.handshake()

        rig.factory.current?.serverClose(reason: .unauthorized)
        await rig.flush()
        await waitUntil { self.rig.manager.state.status == .error }

        XCTAssertEqual(refreshedCount, 0)
    }

    func testAFailedRefreshPublishesAnErrorAndDoesNotReconnect() async {
        rig.auth.refreshResults = [.failure(AuthDataSourceError.anonymousTokenCannotBeRefreshed)]
        rig.start()
        await rig.handshake()
        rig.factory.current?.serverClose(reason: .unauthorized)
        await rig.flush()
        await waitUntil { self.rig.manager.state.status == .error }

        XCTAssertTrue(try XCTUnwrap(rig.manager.state.lastError).contains("refresh failed"))
        XCTAssertEqual(rig.factory.createdCount, 1)
    }

    func testARefreshedTokenOfAnotherUserIsRejected() async {
        rig.auth.refreshResults = [.success(makeAuthModel(claims: ["uuid": "someone-else", "appId": "app-1"]))]
        rig.start()
        await rig.handshake()
        rig.factory.current?.serverClose(reason: .unauthorized)
        await rig.flush()
        await waitUntil { self.rig.manager.state.status == .error }

        XCTAssertTrue(try XCTUnwrap(rig.manager.state.lastError).contains("another user"))
        XCTAssertEqual(rig.factory.createdCount, 1)
    }

    func testARefreshFinishingAfterStopIsDiscarded() async {
        rig.auth.suspendsRefreshes = true
        rig.start()
        await rig.handshake()
        rig.factory.current?.serverClose(reason: .unauthorized)
        await rig.auth.waitForRefreshCall(1)   // the refresh is in flight
        rig.manager.stop()
        rig.auth.finishRefresh(with: .success(makeAuthModel(claims: ["uuid": "user-1", "appId": "app-1", "n": 3])))
        await rig.settle()

        XCTAssertEqual(rig.factory.createdCount, 1)
        XCTAssertEqual(rig.manager.state.status, .stopped)
    }
}
