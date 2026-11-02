//  The `Hello` field set, published transitions, poll interval floor and immediate poll.

import XCTest

@testable import SinchPushSDK

final class HandshakeTests: XCTestCase {

    // MARK: - Hello field set

    func testHelloIsTheFirstFrameOnAnOpenSocket() {
        let harness = makeHarness()

        XCTAssertTrue(harness.sentFrames.isEmpty)

        harness.transport.openSocket()

        XCTAssertEqual(harness.transport.sentKinds, ["hello"])
    }

    func testHelloCarriesTheIdentityTheRelayValidates() throws {
        let harness = makeHarness()

        harness.transport.openSocket()

        let hello = try XCTUnwrap(harness.hello)
        XCTAssertEqual(hello.authToken, "jwt.token.value")
        XCTAssertEqual(hello.projectID, "project-1")
        XCTAssertEqual(hello.appID, "app-1")
        XCTAssertEqual(hello.userID, "user-1")
        XCTAssertNotEqual(hello.platform, Sinch_Push_Delivery_V1beta1_Ws_Platform.unspecified)
    }

    func testAFreshCredentialReachesTheWireOnTheNextHello() {
        let harness = makeHarness()
        harness.handshake()

        harness.client.updateConfiguration(
            testConfiguration(authToken: "rotated.token.value"))
        XCTAssertEqual(harness.socketCount, 2)

        harness.transport.openSocket()
        XCTAssertEqual(harness.transport.sentKinds, ["hello"])
        XCTAssertEqual(harness.hello?.authToken, "rotated.token.value")
    }

    // MARK: - Platform and SDK version

    func testPlatformIsIOSAndNotDerivedFromBackground() throws {
        let harness = makeHarness()
        harness.transport.openSocket()

        let hello = try XCTUnwrap(harness.hello)
        XCTAssertEqual(hello.platform, Sinch_Push_Delivery_V1beta1_Ws_Platform.ios)
        XCTAssertFalse(hello.background)
    }

    func testSDKVersionIsTheStringTheConfigCarries() {
        let harness = makeHarness(
            configuration: testConfiguration(sdkVersion: "rn-sinch-push/9.9.9"))

        harness.transport.openSocket()

        XCTAssertEqual(harness.hello?.sdkVersion, "rn-sinch-push/9.9.9")
    }

    func testEmptyConfiguredVersionFallsBackRatherThanSendingNothing() {
        let harness = makeHarness(configuration: testConfiguration(sdkVersion: ""))

        harness.transport.openSocket()

        XCTAssertEqual(harness.hello?.sdkVersion, SocketConfiguration.defaultSDKVersion)
    }

    // MARK: - Device info

    func testHelloCarriesAllTwelveFieldsOfTheRelayContract() throws {
        let harness = makeHarness(
            store: FakeSocketStateStore(lastSeen: "msg-9"),
            deviceInfo: testDeviceInfo(
                installationId: "0b9c1f0e-6f3a-4b8e-9d57-2f6f6c1a7e11",
                osVersion: "17.5.1", bundleId: "com.example.host"))
        harness.transport.openSocket()

        let hello = try XCTUnwrap(harness.hello)
        XCTAssertEqual(hello.authToken, "jwt.token.value")
        XCTAssertEqual(hello.projectID, "project-1")
        XCTAssertEqual(hello.appID, "app-1")
        XCTAssertEqual(hello.userID, "user-1")
        XCTAssertEqual(hello.platform, .ios)
        XCTAssertFalse(hello.background)
        XCTAssertEqual(hello.lastSeenMessageID, "msg-9")
        XCTAssertEqual(hello.sdkVersion, SocketConfiguration.defaultSDKVersion)
        XCTAssertEqual(hello.installationID, "0b9c1f0e-6f3a-4b8e-9d57-2f6f6c1a7e11")
        XCTAssertEqual(hello.osVersion, "17.5.1")
        XCTAssertEqual(hello.bundleID, "com.example.host")
        XCTAssertEqual(hello.backgroundService, .unsupported)
    }

    func testIOSBackgroundServiceIsUnsupportedWhateverTheConfigurationSays() throws {
        let harness = makeHarness()
        harness.handshake()
        harness.serverClose(reason: .shutdown)
        harness.scheduler.advance(by: 60_000)
        harness.transport.openSocket()

        XCTAssertEqual(harness.hello?.backgroundService, .unsupported)
    }

    func testAnUnavailableInstallationIdSendsAnEmptyIdAndKeepsTheConnection() throws {
        struct Locked: Error {}
        let logger = RecordingLogger()
        let provider = SystemDeviceInfoProvider(
            installationId: { throw Locked() }, osVersion: { "17.5" },
            bundleId: { "com.example.host" }, logger: logger)
        let harness = makeHarness(deviceInfo: provider)

        harness.transport.openSocket()

        let hello = try XCTUnwrap(harness.hello, "the Hello must still be sent")
        XCTAssertEqual(hello.installationID, "")
        XCTAssertEqual(hello.osVersion, "17.5", "the rest of the device info is unaffected")
        XCTAssertEqual(hello.bundleID, "com.example.host")
        XCTAssertTrue(logger.contains("installation id unavailable"))
        XCTAssertFalse(harness.published(.error), "an unavailable id must not fail the connection")
    }

    func testAnInstallationIdThatWasUnavailableIsRetriedOnTheNextHello() throws {
        struct Locked: Error {}

        final class Flaky: @unchecked Sendable {  // driven on one thread
            var locked = true
            func read() throws -> String {
                if locked { throw Locked() }
                return "0b9c1f0e-6f3a-4b8e-9d57-2f6f6c1a7e11"
            }
        }
        let flaky = Flaky()
        let provider = SystemDeviceInfoProvider(
            installationId: { try flaky.read() }, osVersion: { "17.5" }, bundleId: { "b" })
        let harness = makeHarness(deviceInfo: provider)
        harness.transport.openSocket()
        XCTAssertEqual(harness.hello?.installationID, "")

        flaky.locked = false
        harness.serverClose(reason: .shutdown)
        harness.scheduler.advance(by: 60_000)
        harness.transport.openSocket()

        XCTAssertEqual(harness.hello?.installationID, "0b9c1f0e-6f3a-4b8e-9d57-2f6f6c1a7e11")
    }

    func testTheInstallationIdIsTheOneTheInstallationIdStoreHandsOut() throws {
        let store = KeychainInstallationIdStore(backing: InMemoryInstallationIdBacking())
        let provider = SystemDeviceInfoProvider(
            installationId: { try store.installationId() }, osVersion: { "17.5" }, bundleId: { "b" })
        let harness = makeHarness(deviceInfo: provider)

        harness.transport.openSocket()

        XCTAssertEqual(harness.hello?.installationID, try store.installationId())
        XCTAssertFalse(try XCTUnwrap(harness.hello?.installationID).isEmpty)
    }

    func testOSVersionIsMajorMinorAndPatchOnlyWhenNonZero() {
        func format(_ major: Int, _ minor: Int, _ patch: Int) -> String {
            SystemDeviceInfoProvider.formatOSVersion(
                OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch))
        }
        XCTAssertEqual(format(17, 5, 0), "17.5")
        XCTAssertEqual(format(17, 5, 1), "17.5.1")
        XCTAssertEqual(format(14, 0, 0), "14.0")
        XCTAssertEqual(format(26, 0, 3), "26.0.3")
    }

    func testTheLiveOSVersionIsNeverEmpty() {
        XCTAssertFalse(SystemDeviceInfoProvider.systemOSVersion().isEmpty)
    }

    func testSDKVersionHasOneSourceAndTheConfigOverrideWins() {
        let provider = StaticDeviceInfoProvider()
        XCTAssertEqual(
            provider.current(sdkVersionOverride: nil).sdkVersion, SocketConfiguration.defaultSDKVersion)
        XCTAssertEqual(
            provider.current(sdkVersionOverride: "").sdkVersion, SocketConfiguration.defaultSDKVersion)
        XCTAssertEqual(
            provider.current(sdkVersionOverride: "rn-sinch-push/9.9.9").sdkVersion,
            "rn-sinch-push/9.9.9")
        let system = SystemDeviceInfoProvider(installationId: { "x" })
        XCTAssertEqual(
            system.current(sdkVersionOverride: nil).sdkVersion, SocketConfiguration.defaultSDKVersion)
    }

    // MARK: - Published transitions

    func testFirstAttemptPublishesConnectingAndLaterAttemptsReconnecting() {
        let harness = makeHarness()

        XCTAssertEqual(harness.recorder.statuses, [.connecting])

        harness.handshake()
        harness.transport.failTransport(code: 1006)
        XCTAssertEqual(harness.recorder.current?.status, .reconnecting)

        harness.scheduler.advance(by: 500)
        XCTAssertEqual(
            harness.recorder.statuses,
            [.connecting, .connected, .reconnecting, .reconnecting])
    }

    func testANewAttemptClearsTheErrorLeftByTheLastOne() {
        let harness = makeHarness()
        harness.transport.failTransport(code: 1006)
        XCTAssertEqual(harness.recorder.current?.lastError, "socket closed (code=1006)")

        harness.scheduler.advance(by: 500)

        XCTAssertNil(harness.recorder.current?.lastError)
    }

    // MARK: - HelloAck handling

    func testHelloAckPublishesConnectedWithTheConnectionId() {
        let harness = makeHarness()

        harness.handshake(connectionID: "conn-7")

        XCTAssertEqual(harness.recorder.current?.status, .connected)
        XCTAssertEqual(harness.recorder.current?.connectionId, "conn-7")
    }

    func testHelloAckDrainsPooledMessagesWithAnEmptyAckToken() throws {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))

        let pooled = [pooledMessage(messageID: "msg-a"), pooledMessage(messageID: "msg-b")]
        harness.handshake(messages: pooled)

        XCTAssertEqual(harness.deliveredMessageIDs, ["msg-a", "msg-b"])
        for id in ["msg-a", "msg-b"] {
            let pending = try XCTUnwrap(harness.client.currentPendingMessages.first { $0.id == id })
            XCTAssertEqual(pending.ackToken, "")
        }
        XCTAssertEqual(harness.store.lastSeen, "msg-b")
    }

    // MARK: - Poll interval

    func testConfigWinsOverTheServerValue() {
        let harness = makeHarness(
            configuration: testConfiguration(pollIntervalMs: 2000))

        harness.handshake(pollIntervalMs: 30000)

        XCTAssertEqual(harness.recorder.current?.pollIntervalMs, 2000)
    }

    func testServerValueIsUsedWhenConfigIsAbsent() {
        let harness = makeHarness(configuration: testConfiguration(pollIntervalMs: 0))

        harness.handshake(pollIntervalMs: 15000)

        XCTAssertEqual(harness.recorder.current?.pollIntervalMs, 15000)
    }

    func testDefaultIsUsedWhenNeitherConfigNorServerHasOne() {
        let harness = makeHarness(configuration: testConfiguration(pollIntervalMs: 0))

        harness.handshake(pollIntervalMs: 0)

        XCTAssertEqual(harness.recorder.current?.pollIntervalMs, SocketClient.defaultPollIntervalMs)
        XCTAssertEqual(harness.recorder.current?.pollIntervalMs, 5000)
    }

    func testASubSecondServerValueIsFlooredInStateAndInTheTimer() {
        let harness = makeHarness()

        harness.handshake(pollIntervalMs: 50)

        XCTAssertEqual(harness.recorder.current?.pollIntervalMs, 1000)
        harness.scheduler.advance(by: 999)
        XCTAssertEqual(harness.polls.count, 1, "the immediate poll only")
        harness.scheduler.advance(by: 1)
        XCTAssertEqual(harness.polls.count, 2)
    }

    // MARK: - Immediate poll

    func testAPollIsSentImmediatelyAfterEveryHelloAck() {
        let harness = makeHarness()

        harness.handshake()

        XCTAssertEqual(harness.transport.sentKinds, ["hello", "poll"])
    }

    func testTheImmediatePollArrivesOnEveryReconnectToo() {
        let harness = makeHarness()
        harness.handshake()

        harness.transport.failTransport(code: 1006)
        harness.scheduler.advance(by: 500)
        harness.handshake(connectionID: "conn-2")

        XCTAssertEqual(harness.transport.sentKinds, ["hello", "poll"])
    }

    // MARK: - State surface

    func testLastErrorCarriesACloseDetailsText() {
        let harness = makeHarness()
        harness.handshake()

        harness.serverClose(reason: .poolFull, detail: "rate_limited")

        XCTAssertEqual(harness.recorder.current?.lastError, "rate_limited")
    }

    func testACloseWithoutDetailStillCarriesAReason() {
        let harness = makeHarness()
        harness.handshake()

        harness.serverClose(reason: .shutdown)

        XCTAssertEqual(
            harness.recorder.current?.lastError,
            "server closed (reason=\(Sinch_Push_Delivery_V1beta1_Ws_CloseReason.shutdown.rawValue))")
    }

    func testConnectionIdIsEmptyBeforeTheFirstHandshake() {
        let harness = makeHarness()

        XCTAssertEqual(harness.recorder.current?.connectionId, "")
        XCTAssertEqual(harness.client.currentState.connectionId, "")
    }
}