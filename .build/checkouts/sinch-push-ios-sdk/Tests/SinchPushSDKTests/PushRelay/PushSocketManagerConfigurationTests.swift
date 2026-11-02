import XCTest
@testable import SinchPushSDK

/// Which identity, claims and configuration let the relay start, and what it reports when it does not.
@MainActor
final class PushSocketManagerConfigurationTests: XCTestCase {

    private var rig: RelayTestHarness!

    override func setUp() async throws {
        try await super.setUp()
        rig = RelayTestHarness()
    }

    // MARK: - Start

    func testNothingConnectsBeforeStart() async {
        await rig.flush()
        XCTAssertEqual(rig.factory.createdCount, 0)
        XCTAssertEqual(rig.manager.state.status, .idle)
        XCTAssertFalse(rig.manager.state.relayEnabled)
        XCTAssertNotNil(rig.manager.state.disabledReason)
    }

    func testStartConnectsWithTheClaimsOfTheToken() async throws {
        rig.start()
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, 1)
        XCTAssertEqual(rig.factory.current?.connectCalls, [URL(string: "wss://relay.example.com/ws")!])
        rig.factory.current?.openSocket()
        let hello = try XCTUnwrap(rig.factory.current?.hellos.first)
        XCTAssertEqual(hello.appID, "app-1")
        XCTAssertEqual(hello.userID, "user-1")
        XCTAssertEqual(hello.projectID, "jwt-project")
        XCTAssertEqual(hello.authToken, makeAuthModel().accessToken)
        XCTAssertEqual(rig.manager.state.status, .connecting)
        XCTAssertTrue(rig.manager.state.relayEnabled)
        XCTAssertNil(rig.manager.state.disabledReason)
        XCTAssertEqual(rig.manager.socketConfiguration?.displayNotifications, .always)
    }

    func testSnakeCaseClaimsAreAccepted() throws {
        rig.start(auth: makeAuthModel(claims: ["uuid": "u", "app_id": "a", "project_id": "p"]))
        rig.factory.current?.openSocket()
        let hello = try XCTUnwrap(rig.factory.current?.hellos.first)
        XCTAssertEqual(hello.appID, "a")
        XCTAssertEqual(hello.projectID, "p")
    }

    func testProjectIDFallsBackToTheConfiguredProject() throws {
        rig.start(auth: makeAuthModel(claims: ["uuid": "u", "appId": "a"]))
        rig.factory.current?.openSocket()
        XCTAssertEqual(rig.factory.current?.hellos.first?.projectID, "config-project")
    }

    func testMissingAppIDDoesNotStartAndPublishesAnError() async {
        rig.start(auth: makeAuthModel(claims: ["uuid": "u", "projectId": "p"]))
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, 0)
        XCTAssertEqual(rig.manager.state.status, .error)
        XCTAssertTrue(rig.manager.state.relayEnabled)
        XCTAssertEqual(rig.manager.state.lastError, RelayConfigurationError.missingAppID.description)
        XCTAssertNil(rig.lifecycle)
    }

    func testMissingUserIDDoesNotStartAndPublishesAnError() {
        rig.start(auth: makeAuthModel(claims: ["appId": "a"]))
        XCTAssertEqual(rig.factory.createdCount, 0)
        XCTAssertEqual(rig.manager.state.lastError, RelayConfigurationError.missingUserID.description)
    }

    func testAnUndecodableTokenDoesNotStart() {
        let auth = AuthModel(accessToken: "not-a-jwt", sinchIdentity: .anonymous, clientID: "c", projectID: "p",
                             configID: "c", region: relayRegion())
        rig.start(auth: auth)
        XCTAssertEqual(rig.factory.createdCount, 0)
        XCTAssertEqual(rig.manager.state.status, .error)
    }

    func testDisabledRegionPublishesTheReasonAndDoesNotConnect() async {
        rig.start(config: makeAppConfig(region: regionWithoutARelayHost()))
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, 0)
        XCTAssertFalse(rig.manager.state.relayEnabled)
        XCTAssertTrue(try XCTUnwrap(rig.manager.state.disabledReason).contains("no relay host for push host"))
        XCTAssertNil(rig.lifecycle)
    }

    func testABuiltInRegionConnectsToItsRelay() async {
        rig.start(config: makeAppConfig(region: .EU1))
        await rig.flush()

        XCTAssertEqual(rig.factory.createdCount, 1)
        XCTAssertEqual(rig.factory.current?.connectCalls,
                       [URL(string: "wss://relay.sinch-push.prod.sinch.com/ws")!])
        XCTAssertTrue(rig.manager.state.relayEnabled)
    }

    func testKillSwitchDoesNotConnect() {
        rig.start(config: makeAppConfig(relay: .disabled))
        XCTAssertEqual(rig.factory.createdCount, 0)
        XCTAssertFalse(rig.manager.state.relayEnabled)
    }

    // MARK: - Insecure relay (allowInsecureRelay)

    func testAPlaintextRelayNeedsAllowInsecureRelay() async {
        let ws = relayRegion(isSecure: false, relay: "ws://127.0.0.1:8080/ws")
        rig.start(config: makeAppConfig(region: ws))
        await rig.flush()
        XCTAssertEqual(rig.factory.createdCount, 0)
        XCTAssertFalse(rig.manager.state.relayEnabled)
        XCTAssertTrue(try XCTUnwrap(rig.manager.state.disabledReason).contains("allowInsecureRelay"))

        rig.start(config: makeAppConfig(region: ws, allowInsecureRelay: true))
        await rig.flush()
        XCTAssertEqual(rig.factory.current?.connectCalls, [URL(string: "ws://127.0.0.1:8080/ws")!])
        XCTAssertTrue(rig.manager.state.relayEnabled)
    }

    func testAPlaintextRelayIsIndependentOfTheGrpcChannelSecurity() async {
        // `isSecure: true` is the (TLS) gRPC channel; it neither enables nor blocks a ws:// relay.
        let region = relayRegion(isSecure: true, relay: "ws://127.0.0.1:8080/ws")
        rig.start(config: makeAppConfig(region: region, allowInsecureRelay: true))
        await rig.flush()
        XCTAssertEqual(rig.factory.createdCount, 1)
    }
}
