//  LiveDeliveryReportTests.swift — APNs delivery reporting against a real sinch-push and relay.
//
//  Skipped unless the SINCH_PUSH_LIVE_* variables below are set; `DevApp/scripts/live_delivery_report_test.sh`
//  starts the servers, mints the identity and sets them. `xcodebuild` forwards environment to the test runner
//  only with the `TEST_RUNNER_` prefix. The simulator reaches the host's 127.0.0.1.
//
//  The tests check what the client sees; the rows the server wrote are checked by the script.

import XCTest

@testable import SinchPushSDK

@MainActor
final class LiveDeliveryReportTests: XCTestCase {

    private static let timeout: TimeInterval = 20

    private struct LiveEnvironment {
        /// The sinch-push gRPC endpoint.
        var pushHost: String
        var pushPort: Int
        /// A sinch-push JWT of the scenario's project, app and user, and the iOS config of that project.
        var jwt: String
        var configID: String
        /// The message the APNs scenario delivers. A 26-character id, like the server's.
        var apnsMessageID: String
        /// The relay endpoint, the identity a message was stored for, and that message.
        var relayURL: String
        var relayAppID: String
        var relayUserID: String
        var relayInstallationID: String
        var socketMessageID: String

        static func load() throws -> LiveEnvironment {
            try LiveTests.skipUnlessEnabled()
            let environment = ProcessInfo.processInfo.environment
            func value(_ name: String) -> String? {
                environment["SINCH_PUSH_LIVE_\(name)"].flatMap { $0.isEmpty ? nil : $0 }
            }
            guard let host = value("PUSH_HOST"), let port = value("PUSH_PORT").flatMap({ Int($0) }),
                let jwt = value("JWT"), let configID = value("CONFIG_ID"), let apnsMessageID = value("APNS_MESSAGE_ID"),
                let relayURL = value("RELAY_URL"), let relayAppID = value("RELAY_APP_ID"),
                let relayUserID = value("RELAY_USER_ID"), let installationID = value("RELAY_INSTALLATION_ID"),
                let socketMessageID = value("SOCKET_MESSAGE_ID")
            else {
                throw XCTSkip(
                    "live delivery report test skipped: set SINCH_PUSH_LIVE_PUSH_HOST, _PUSH_PORT, _JWT, _CONFIG_ID, "
                        + "_APNS_MESSAGE_ID, _RELAY_URL, _RELAY_APP_ID, _RELAY_USER_ID, _RELAY_INSTALLATION_ID and "
                        + "_SOCKET_MESSAGE_ID (xcodebuild: prefix each with TEST_RUNNER_), "
                        + "or run DevApp/scripts/live_delivery_report_test.sh")
            }
            return LiveEnvironment(
                pushHost: host, pushPort: port, jwt: jwt, configID: configID, apnsMessageID: apnsMessageID,
                relayURL: relayURL, relayAppID: relayAppID, relayUserID: relayUserID,
                relayInstallationID: installationID, socketMessageID: socketMessageID)
        }
    }

    // MARK: - Test doubles

    /// The push API over plaintext gRPC-web, which the local sinch-push serves.
    private final class PlaintextPushAPIClient: PushAPIClient, @unchecked Sendable {
        let grpcWebClient: GrpcWebClient?

        init(host: String, port: Int) {
            self.grpcWebClient = GrpcWebClient(
                baseURL: URL(string: "http://\(host):\(port)")!,
                missingStatusPolicy: .acceptIfMessageReceived)
        }

        func closeChannel() {}
    }

    private final class JWTAuthDataSource: AuthDataSource, @unchecked Sendable {
        let jwt: String
        let currentConfigID: String

        init(jwt: String, configID: String) {
            self.jwt = jwt
            currentConfigID = configID
        }

        var isLoggedIn: Bool { true }
        var identityHashValue: String? { nil }
        var currentAuthorization: AuthModel? { nil }

        func generateToken(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity) async throws -> AuthModel {
            throw AuthDataSourceError.notLoggedIn
        }

        func generateToken(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity,
                           completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void) {}

        func refreshToken() async throws -> AuthModel { throw AuthDataSourceError.notLoggedIn }
        func currentAccessToken() throws -> String { jwt }
        func deleteToken() {}
    }

    /// The real gRPC sender, with every call it carries recorded.
    private final class CountingSender: DeliveryReportSending, @unchecked Sendable {
        private let wrapped: DeliveryReportSending
        private let lock = NSLock()
        private var recorded: [[DeliveryReport]] = []
        private var failures: [String] = []

        init(wrapping wrapped: DeliveryReportSending) {
            self.wrapped = wrapped
        }

        var calls: [[DeliveryReport]] { lock.withLock { recorded } }
        var errors: [String] { lock.withLock { failures } }

        func reportedMessageIDs() -> [String] { calls.flatMap { $0.map(\.messageID) } }

        func reportEvents(_ events: [DeliveryReport]) async throws {
            lock.withLock { recorded.append(events) }
            do {
                try await wrapped.reportEvents(events)
            } catch {
                lock.withLock { failures.append("\(error)") }
                throw error
            }
        }
    }

    /// The SDK's APNs entry over the real reporter, which flushes at once as the app is active.
    @MainActor
    private struct Rig {
        let harness: RelayTestHarness
        let outbox: DeliveryReportOutbox
        let sender: CountingSender
        let push: DefaultSinchPush
        let pushRepository: DefaultPushRepository

        var registry: SeenMessageRegistry { harness.registry }

        init(environment: LiveEnvironment) {
            let client = PlaintextPushAPIClient(host: environment.pushHost, port: environment.pushPort)
            let auth = JWTAuthDataSource(jwt: environment.jwt, configID: environment.configID)
            let sender = CountingSender(wrapping: PushAPIDeliveryReportSender(client: client, authDataSource: auth))
            let outbox = DeliveryReportOutbox(store: FakeDeliveryReportStore())
            let reporter = DeliveryReporter(
                outbox: outbox,
                dependencies: DeliveryReporter.Dependencies(
                    scheduler: DispatchScheduler(),
                    random: SystemRandomSource(),
                    makeSender: { _, _ in sender },
                    isApplicationActive: { true },
                    isNotificationServiceExtension: { false },
                    notificationCenter: NotificationCenter()))
            reporter.setSession(authDataSource: auth, client: client)

            let harness = RelayTestHarness()
            self.harness = harness
            self.outbox = outbox
            self.sender = sender
            push = DefaultSinchPush(
                pushNotificationHandler: RoutingHandlerStub(), inAppPresenter: InAppControllerStub(),
                socketManager: harness.manager, relaySettings: harness.settings, deliveryReporter: reporter)
            pushRepository = DefaultPushRepository(region: .EU1, authDataSource: auth, client: client)
        }

        /// Subscribes a device the way the SDK does and returns the server's subscriber id.
        func subscribe() async throws -> String {
            let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
            let subscriberID = try await pushRepository.sendDeviceToken(token: token, deviceInfo: nil)
            return try XCTUnwrap(subscriberID, "Subscribe returned no subscriber id")
        }

        /// What a provider push of sinch-push carries.
        func apnsUserInfo(messageID: String, subscriberID: String) -> [AnyHashable: Any] {
            [
                "aps": ["alert": ["title": "Live", "body": "APNs copy"]],
                "sinch.push.message_id": messageID,
                "sinch.push.subscriber_id": subscriberID
            ]
        }

        func present(messageID: String, subscriberID: String) -> UNNotificationPresentationOptions? {
            push.handleWillPresent(
                userInfo: apnsUserInfo(messageID: messageID, subscriberID: subscriberID),
                requestIdentifier: messageID, hasSound: false)
        }
    }

    /// The messages the relay socket delivered.
    private final class SocketRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String] = []
        private var lines: [String] = []

        var messageIDs: [String] { lock.withLock { ids } }
        var logs: [String] { lock.withLock { lines } }

        func record(message: SocketMessageEvent) { lock.withLock { ids.append(message.id) } }
        func record(log line: String) { lock.withLock { lines.append(line) } }
    }

    // MARK: - Helpers

    /// A 26-character id, the length the server stores message ids in.
    private func freshMessageID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(26))
    }

    /// Polls `condition` until it holds or the timeout passes; returns whether it held.
    private func eventually(timeout: TimeInterval = LiveDeliveryReportTests.timeout,
                            _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return true
    }

    // MARK: - Scenario 1: the APNs path of a relay-disabled project

    func testAnApnsDeliveryIsReportedOnceAndLeavesTheOutbox() async throws {
        let environment = try LiveEnvironment.load()
        let rig = Rig(environment: environment)
        let messageID = environment.apnsMessageID

        let subscriberID = try await rig.subscribe()
        XCTAssertFalse(subscriberID.isEmpty)
        print("LIVE subscriber_id=\(subscriberID) apns_message_id=\(messageID)")

        let options = rig.present(messageID: messageID, subscriberID: subscriberID)
        XCTAssertNotNil(options, "an unseen APNs push is presented")

        let reported = await eventually { rig.sender.calls.count >= 1 && rig.outbox.isEmpty }
        XCTAssertTrue(reported, "the outbox did not drain: calls=\(rig.sender.calls.count) errors=\(rig.sender.errors)")
        XCTAssertEqual(rig.sender.errors, [])
        XCTAssertEqual(rig.sender.calls.map { $0.map(\.messageID) }, [[messageID]])
        XCTAssertEqual(rig.sender.calls.first?.first?.subscriberID, subscriberID)

        // The same push arrives again through the other callback: it is a known message, not a second report.
        XCTAssertTrue(rig.push.handleNotification(rig.apnsUserInfo(messageID: messageID, subscriberID: subscriberID)))
        XCTAssertEqual(rig.sender.calls.count, 1)
        XCTAssertTrue(rig.outbox.isEmpty)
    }

    // MARK: - Scenario 2: a message the relay socket delivered is never reported

    func testAMessageTheSocketDeliveredIsNeverReported() async throws {
        let environment = try LiveEnvironment.load()
        let rig = Rig(environment: environment)
        let socketMessageID = environment.socketMessageID
        let subscriberID = try await rig.subscribe()

        let recorder = SocketRecorder()
        let store = InMemorySocketStateStore()
        let client = SocketClient(
            configuration: SocketConfiguration(
                url: environment.relayURL, authToken: "dev-token", projectID: "live-report-project",
                appID: environment.relayAppID, userID: environment.relayUserID, displayNotifications: .never),
            transportFactory: URLSessionWebSocketTransportFactory(),
            scheduler: DispatchScheduler(),
            random: SystemRandomSource(),
            store: store,
            tokenStore: InMemoryAuthTokenStore(token: "dev-token"),
            deviceInfo: StaticDeviceInfoProvider(installationId: environment.relayInstallationID),
            seenRegistry: rig.registry,
            callbacks: SocketClient.Callbacks(
                onMessage: { recorder.record(message: $0) },
                onLog: { recorder.record(log: $0) }))
        client.start()
        defer { client.stop() }

        let received = await eventually { recorder.messageIDs.contains(socketMessageID) }
        XCTAssertTrue(received, "the relay did not replay \(socketMessageID); logs:\n\(recorder.logs.joined(separator: "\n"))")
        XCTAssertTrue(rig.registry.contains(socketMessageID), "the socket marks what it delivers as seen")

        let options = rig.present(messageID: socketMessageID, subscriberID: subscriberID)
        XCTAssertEqual(options, [], "the APNs copy of a socket-delivered message presents nothing")
        XCTAssertTrue(rig.push.handleNotification(rig.apnsUserInfo(messageID: socketMessageID, subscriberID: subscriberID)))

        // A message only APNs delivered is reported after the copy, so by the time its report left, a report
        // of the copy would have too.
        let controlID = freshMessageID()
        _ = rig.present(messageID: controlID, subscriberID: subscriberID)
        let drained = await eventually { rig.sender.reportedMessageIDs().contains(controlID) && rig.outbox.isEmpty }
        XCTAssertTrue(drained, "the control message was not reported: errors=\(rig.sender.errors)")

        XCTAssertEqual(rig.sender.errors, [])
        XCTAssertEqual(rig.sender.reportedMessageIDs(), [controlID])
        XCTAssertFalse(rig.sender.reportedMessageIDs().contains(socketMessageID))
        XCTAssertTrue(rig.outbox.isEmpty)
        print("LIVE socket_message_id=\(socketMessageID) control_message_id=\(controlID)")
    }
}
