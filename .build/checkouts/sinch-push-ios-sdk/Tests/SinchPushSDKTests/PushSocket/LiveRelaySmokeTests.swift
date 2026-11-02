//  LiveRelaySmokeTests.swift — iOS counterpart of `LiveRelayContractTests`: connects to an
//  already running relay and expects the Hello → HelloAck handshake to publish `connected`.
//
//  Skipped unless `SINCH_PUSH_RELAY_URL`, `SINCH_PUSH_RELAY_JWT`, `SINCH_PUSH_RELAY_APP_ID`
//  and `SINCH_PUSH_RELAY_USER_ID` are set (optionally `SINCH_PUSH_RELAY_PROJECT_ID`).
//  `xcodebuild` forwards environment to the test runner only with the `TEST_RUNNER_` prefix.

import XCTest

@testable import SinchPushSDK

final class LiveRelaySmokeTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _states: [SocketState] = []
        private var _logs: [String] = []
        let connected: XCTestExpectation

        init(connected: XCTestExpectation) {
            self.connected = connected
            // A reconnect publishes `connected` again.
            connected.assertForOverFulfill = false
        }

        var states: [SocketState] { lock.withLock { _states } }
        var logs: [String] { lock.withLock { _logs } }

        func record(_ state: SocketState) {
            lock.withLock { _states.append(state) }
            if state.status == .connected { connected.fulfill() }
        }

        func record(log line: String) { lock.withLock { _logs.append(line) } }
    }

    private struct RelayEnvironment {
        var url: String
        var jwt: String
        var appID: String
        var userID: String
        var projectID: String

        static func load() throws -> RelayEnvironment {
            try LiveTests.skipUnlessEnabled()
            let environment = ProcessInfo.processInfo.environment
            func value(_ name: String) -> String? {
                environment[name].flatMap { $0.isEmpty ? nil : $0 }
            }
            guard let url = value("SINCH_PUSH_RELAY_URL"), let jwt = value("SINCH_PUSH_RELAY_JWT"),
                let appID = value("SINCH_PUSH_RELAY_APP_ID"), let userID = value("SINCH_PUSH_RELAY_USER_ID")
            else {
                throw XCTSkip(
                    "live relay smoke test skipped: set SINCH_PUSH_RELAY_URL, SINCH_PUSH_RELAY_JWT, "
                        + "SINCH_PUSH_RELAY_APP_ID and SINCH_PUSH_RELAY_USER_ID "
                        + "(xcodebuild: prefix each with TEST_RUNNER_)")
            }
            return RelayEnvironment(
                url: url, jwt: jwt, appID: appID, userID: userID,
                projectID: value("SINCH_PUSH_RELAY_PROJECT_ID") ?? "")
        }
    }

    func testHelloAckPublishesConnectedOverTheRealTransport() throws {
        let relay = try RelayEnvironment.load()
        let recorder = Recorder(connected: expectation(description: "HelloAck -> connected"))

        let store = InMemorySocketStateStore()
        let client = SocketClient(
            configuration: SocketConfiguration(
                url: relay.url, authToken: relay.jwt, projectID: relay.projectID,
                appID: relay.appID, userID: relay.userID,
                displayNotifications: .never),
            transportFactory: URLSessionWebSocketTransportFactory(),
            scheduler: DispatchScheduler(),
            random: SystemRandomSource(),
            store: store,
            tokenStore: InMemoryAuthTokenStore(),
            seenRegistry: SeenMessageRegistry(store: store),
            callbacks: SocketClient.Callbacks(
                onState: { recorder.record($0) },
                onLog: { recorder.record(log: $0) }))

        client.start()
        defer { client.stop() }

        wait(for: [recorder.connected], timeout: 15)

        let state = client.currentState
        XCTAssertEqual(
            state.status, .connected, "logs:\n\(recorder.logs.joined(separator: "\n"))")
        XCTAssertFalse(state.connectionId.isEmpty, "HelloAck carries a connection id")
        XCTAssertGreaterThanOrEqual(state.pollIntervalMs, SocketClient.minPollIntervalMs)
        XCTAssertTrue(recorder.states.map(\.status).contains(.connecting))
    }
}
