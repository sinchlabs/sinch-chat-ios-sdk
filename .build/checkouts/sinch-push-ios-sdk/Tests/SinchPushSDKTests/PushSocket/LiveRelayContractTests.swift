//  LiveRelayContractTests.swift — the Swift client against a real `deliveryd` and
//  `report-sink-stub` over URLSessionWebSocketTransport.
//
//  Opt-in (RELAY_CONTRACT=1, macOS): binds real ports, and skips with a message when
//  the relay binaries are missing. macOS only (see RelayHarness.swift).

#if os(macOS)
import XCTest

@testable import SinchPushSDK

// MARK: - A live client

/// A real client over the real transport, with the callbacks it published.
private final class Live: @unchecked Sendable {
    private let lock = NSLock()
    private var _states: [SocketState] = []
    private var _messages: [SocketMessageEvent] = []
    private var _logs: [String] = []
    let client: SocketClient

    var states: [SocketState] { lock.withLock { _states } }
    var messages: [SocketMessageEvent] { lock.withLock { _messages } }
    var logs: [String] { lock.withLock { _logs } }
    var state: SocketState? { states.last }
    var connected: Bool { state?.status == .connected }

    private final class LockedLogger: SocketLogger {
        let sink: @Sendable (String) -> Void
        init(_ sink: @escaping @Sendable (String) -> Void) { self.sink = sink }
        func log(_ line: String, level: SocketLogLevel) { sink(line) }
    }

    /// A `store` shared between two instances is a restart; the default device-info
    /// provider carries no installation id (a legacy client).
    init(
        relay: RelayHarness, appID: String, userID: String,
        store: InMemorySocketStateStore = InMemorySocketStateStore(),
        deviceInfo: DeviceInfoProviding = StaticDeviceInfoProvider()
    ) {
        let configuration = SocketConfiguration(
            url: relay.wsURL, authToken: "dev-token", projectID: "contract-project",
            appID: appID, userID: userID, pollIntervalMs: 0, displayNotifications: .never,
            sdkVersion: "rn-sinch-push-contract/1.0.0")
        var callbacks = SocketClient.Callbacks()
        let box = Box()
        let logger = LockedLogger { box.append(log: $0) }
        client = SocketClient(
            configuration: configuration,
            transportFactory: URLSessionWebSocketTransportFactory(),
            scheduler: DispatchScheduler(),
            random: SystemRandomSource(),
            store: store,
            tokenStore: InMemoryAuthTokenStore(token: "dev-token"),
            logger: logger,
            deviceInfo: deviceInfo,
            seenRegistry: SeenMessageRegistry(store: store))
        callbacks.onState = { box.append(state: $0) }
        callbacks.onMessage = { box.append(message: $0) }
        callbacks.onLog = { box.append(log: $0) }
        client.setCallbacks(callbacks)
        box.owner = self
    }

    /// Callbacks arrive on the scheduler's queue; this funnels them under a lock.
    final class Box: @unchecked Sendable {
        weak var owner: Live?

        func append(state: SocketState) {
            guard let owner else { return }
            owner.lock.withLock { owner._states.append(state) }
        }

        func append(message: SocketMessageEvent) {
            guard let owner else { return }
            owner.lock.withLock { owner._messages.append(message) }
        }

        func append(log: String) {
            guard let owner else { return }
            owner.lock.withLock { owner._logs.append(log) }
        }
    }
}

// MARK: - Test helpers

private func withClient(
    _ relay: RelayHarness, appID: String, user: String, _ body: (Live) throws -> Void
) rethrows {
    let live = Live(relay: relay, appID: appID, userID: user)
    live.client.start()
    defer { live.client.stop(); Thread.sleep(forTimeInterval: 0.1) }
    try body(live)
}

/// Fails on timeout and returns whether the predicate held.
@discardableResult
private func waitFor(
    _ timeout: TimeInterval, _ what: String, extra: () -> String = { "" },
    file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    XCTFail("timed out after \(timeout)s waiting for \(what)\n\(extra())", file: file, line: line)
    return false
}

private func uniqueUser(_ tag: String) -> String { "contract-user-\(tag)-\(DispatchTime.now().uptimeNanoseconds)" }

final class LiveRelayContractTests: XCTestCase {

    // Written in class `setUp()`/`tearDown()`, read by tests that XCTest runs serially.
    private nonisolated(unsafe) static var relay: RelayHarness?
    private nonisolated(unsafe) static var skipReason = ""

    private let appID = "contract-app"

    override class func setUp() {
        super.setUp()
        guard LiveTests.areEnabled else {
            skipReason = "live tests are off (set SINCH_LIVE_TESTS=1)"
            return
        }
        let (harness, why) = RelayHarness.locate()
        guard let harness else {
            skipReason = why
            return
        }
        do {
            try harness.start()
            relay = harness
        } catch {
            harness.stop()
            skipReason = "relay failed to start: \(error)"
            failedStart = "\(error)"
        }
    }

    private nonisolated(unsafe) static var failedStart: String?

    override class func tearDown() {
        relay?.stop()
        relay = nil
        super.tearDown()
    }

    private func requireRelay() throws -> RelayHarness {
        try LiveTests.skipUnlessEnabled()
        if let failed = Self.failedStart { XCTFail(failed) }
        guard let relay = Self.relay else { throw XCTSkip("live relay contract skipped: \(Self.skipReason)") }
        return relay
    }

    // MARK: - Scenarios

    func testHandshakeWithin2sLearnsTheSessionParameters() throws {
        let relay = try requireRelay()
        withClient(relay, appID: appID, user: uniqueUser("hs")) { live in
            let started = Date()
            waitFor(2, "connected within 2 s", extra: { relay.relayTail() }) { live.connected }
            XCTAssertLessThanOrEqual(Date().timeIntervalSince(started), 2.5)
            XCTAssertFalse(live.state?.connectionId.isEmpty ?? true)
            XCTAssertGreaterThan(live.state?.pollIntervalMs ?? 0, 0)
            XCTAssertTrue(live.states.contains { $0.status == .connecting })
        }
    }

    func testAnEnqueuedMessageIsPushedWithoutAPoll() throws {
        let relay = try requireRelay()
        let user = uniqueUser("push")
        let sinchID = "contract-push-\(DispatchTime.now().uptimeNanoseconds)"
        try withClient(relay, appID: appID, user: user) { live in
            waitFor(10, "connected", extra: { relay.relayTail() }) { live.connected }
            try relay.enqueue(
                appID: appID, userID: user, sinchMessageID: sinchID, title: "Hello from SDK contract",
                body: "contract body")
            // Shorter than one poll interval, so a coincidental poll cannot pass this.
            XCTAssertGreaterThan(live.state?.pollIntervalMs ?? 0, 1000)
            waitFor(1, "push delivery within 1 s of enqueue", extra: { relay.relayTail() }) { !live.messages.isEmpty }
            guard let message = live.messages.first else { return }
            XCTAssertEqual(message.sinchMessageId, sinchID)
            XCTAssertEqual(message.title, "Hello from SDK contract")
            XCTAssertEqual(message.body, "contract body")
            XCTAssertEqual(message.ackToken, message.id)
            XCTAssertFalse(message.id.isEmpty)
        }
    }

    func testExactlyOneDeliveredReachesTheSinkWithAnAcceptedAckAndACorrelatedChannelID() throws {
        let relay = try requireRelay()
        let user = uniqueUser("delivered")
        let sinchID = "contract-report-\(DispatchTime.now().uptimeNanoseconds)"
        try withClient(relay, appID: appID, user: user) { live in
            waitFor(10, "connected", extra: { relay.relayTail() }) { live.connected }
            try relay.enqueue(appID: appID, userID: user, sinchMessageID: sinchID, title: "report correlation")
            waitFor(10, "the report to reach the sink", extra: { relay.sinkTail() + relay.relayTail() }) {
                relay.sinkReports().contains { $0.sinchMessageID == sinchID }
            }
            // Give a poll tick or a redelivery the chance to produce a duplicate.
            Thread.sleep(forTimeInterval: 1)
            let reports = relay.sinkReports().filter { $0.sinchMessageID == sinchID }
            XCTAssertEqual(reports.count, 1, "\(reports)")
            XCTAssertEqual(reports.first?.status, "DELIVERED")

            let delivered = live.messages.first { $0.sinchMessageId == sinchID }
            XCTAssertNotNil(delivered)
            let channelID = reports.first?.channelMessageID ?? ""
            XCTAssertFalse(channelID.isEmpty, "channel_message_id missing upstream")
            XCTAssertEqual(channelID, delivered?.id)
            XCTAssertNotEqual(channelID, sinchID)
            XCTAssertEqual(channelID, delivered?.ackToken)

            waitFor(5, "the report Ack", extra: { live.logs.joined(separator: "\n") }) {
                live.logs.contains { $0.contains("ack accepted=true") }
            }
            XCTAssertFalse(live.logs.contains { $0.contains("ack accepted=false") })
        }
    }

    func testDisplayedAndDismissedReachTheSinkAfterReport() throws {
        let relay = try requireRelay()
        let user = uniqueUser("status")
        let sinchID = "contract-status-\(DispatchTime.now().uptimeNanoseconds)"
        try withClient(relay, appID: appID, user: user) { live in
            waitFor(10, "connected", extra: { relay.relayTail() }) { live.connected }
            try relay.enqueue(appID: appID, userID: user, sinchMessageID: sinchID, title: "status")
            waitFor(10, "message", extra: { relay.relayTail() }) { !live.messages.isEmpty }
            guard let id = live.messages.first?.id else { return }
            live.client.report(messageId: id, status: .displayed)
            live.client.report(messageId: id, status: .dismissed)
            waitFor(10, "DISPLAYED and DISMISSED at the sink", extra: { relay.sinkTail() }) {
                let statuses = relay.sinkReports().filter { $0.sinchMessageID == sinchID }.map(\.status)
                return statuses.contains("DISPLAYED") && statuses.contains("DISMISSED")
            }
            let reports = relay.sinkReports().filter { $0.sinchMessageID == sinchID }
            XCTAssertEqual(reports.count, 3, "\(reports)")
            XCTAssertTrue(reports.allSatisfy { $0.channelMessageID == id })
        }
    }

    func testReconnectsWithANewSessionAfterSIGTERM() throws {
        let relay = try requireRelay()
        try withClient(relay, appID: appID, user: uniqueUser("sigterm")) { live in
            waitFor(10, "connected", extra: { relay.relayTail() }) { live.connected }
            let first = live.state?.connectionId ?? ""
            XCTAssertFalse(first.isEmpty)

            try relay.sigtermRelayAndAwaitExit()
            waitFor(10, "the client to notice the shutdown", extra: { "\(live.states)" }) {
                live.states.contains { $0.status == .reconnecting }
            }
            // Respawn on process exit, not on the signal (the relay holds its ports while draining).
            try relay.startRelay()
            waitFor(30, "a reconnect with a fresh connection id", extra: {
                "\(live.states)\n\(live.logs.joined(separator: "\n"))\n\(relay.relayTail(30))"
            }) { live.connected && live.state?.connectionId != first }
            XCTAssertNotEqual(live.state?.connectionId, first)
            XCTAssertEqual(live.state?.status, .connected)
        }
    }

    func testADismissedRaisedWhileDisconnectedArrivesAfterTheReconnect() throws {
        let relay = try requireRelay()
        let user = uniqueUser("outbox")
        let sinchID = "contract-outbox-\(DispatchTime.now().uptimeNanoseconds)"
        try withClient(relay, appID: appID, user: user) { live in
            waitFor(10, "connected", extra: { relay.relayTail() }) { live.connected }
            try relay.enqueue(appID: appID, userID: user, sinchMessageID: sinchID, title: "outbox")
            waitFor(10, "message", extra: { relay.relayTail() }) { !live.messages.isEmpty }
            guard let id = live.messages.first?.id else { return }
            waitFor(10, "DELIVERED at the sink", extra: { relay.sinkTail() }) {
                relay.sinkReports().contains { $0.sinchMessageID == sinchID && $0.status == "DELIVERED" }
            }

            try relay.sigtermRelayAndAwaitExit()
            waitFor(10, "the client to notice the shutdown", extra: { "\(live.states)" }) { !live.connected }
            live.client.report(messageId: id, status: .dismissed)
            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertFalse(
                relay.sinkReports().contains { $0.sinchMessageID == sinchID && $0.status == "DISMISSED" },
                "nothing may reach the sink while the relay is down")

            try relay.startRelay()
            waitFor(30, "the outboxed DISMISSED at the sink", extra: { relay.sinkTail() + "\n" + live.logs.joined(separator: "\n") }) {
                relay.sinkReports().contains { $0.sinchMessageID == sinchID && $0.status == "DISMISSED" }
            }
            let dismissed = relay.sinkReports().filter { $0.sinchMessageID == sinchID && $0.status == "DISMISSED" }
            XCTAssertEqual(dismissed.count, 1)
            XCTAssertEqual(dismissed.first?.channelMessageID, id)
        }
    }

    func testAHelloCarryingTheFullDeviceInfoIsAcceptedAndTheRelayRegistersTheInstallation() throws {
        let relay = try requireRelay()
        let user = uniqueUser("devinfo")
        let installationID = UUID().uuidString.lowercased()
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func increment() { lock.withLock { value += 1 } }
            var count: Int { lock.withLock { value } }
        }
        let installationIDCalls = Counter()
        let deviceInfo = SystemDeviceInfoProvider(
            installationId: { installationIDCalls.increment(); return installationID },
            osVersion: { "17.5.1" },
            bundleId: { "com.example.contract" })
        let live = Live(relay: relay, appID: appID, userID: user, deviceInfo: deviceInfo)
        live.client.start()
        defer { live.client.stop(); Thread.sleep(forTimeInterval: 0.1) }

        let started = Date()
        waitFor(2, "connected within 2 s", extra: { relay.relayTail() + "\n" + live.logs.joined(separator: "\n") }) {
            live.connected
        }
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(started), 2.5)
        let connectionID = live.state?.connectionId ?? ""
        XCTAssertFalse(connectionID.isEmpty)
        XCTAssertGreaterThan(live.state?.pollIntervalMs ?? 0, 0)
        XCTAssertEqual(installationIDCalls.count, 1)

        // The relay logs `registered` after it has sent the HelloAck.
        waitFor(5, "the relay to register the session", extra: { relay.relayTail() }) {
            relay.relayEvents("registered").contains { $0["connection_id"] as? String == connectionID }
        }
        let registered = relay.relayEvents("registered").first { $0["connection_id"] as? String == connectionID }
        XCTAssertEqual(registered?["installation_id"] as? String, installationID)
        XCTAssertEqual(registered?["key"] as? String, "sess:\(appID):\(user):\(installationID)")
        XCTAssertTrue(
            relay.relayEvents("ws hello refused: installation_id must be a canonical uuid").isEmpty,
            "a refused Hello would have been logged")
    }

    func testAfterARestartOverTheSameStoreOnlyTheMessagesMissedWhileDisconnectedAreEmittedOnceEach() throws {
        let relay = try requireRelay()
        let user = uniqueUser("replay")
        let store = InMemorySocketStateStore()
        let stamp = DispatchTime.now().uptimeNanoseconds
        let a = "contract-replay-a-\(stamp)"
        let b = "contract-replay-b-\(stamp)"
        let c = "contract-replay-c-\(stamp)"

        // Legacy key (empty installation_id): `enqueue` cannot target an installation.
        let first = Live(relay: relay, appID: appID, userID: user, store: store)
        first.client.start()
        defer { first.client.stop() }
        waitFor(10, "connected", extra: { relay.relayTail() }) { first.connected }
        try relay.enqueue(appID: appID, userID: user, sinchMessageID: a, title: "A")
        // Pushed, not polled (poll interval is 5 s).
        XCTAssertGreaterThan(first.state?.pollIntervalMs ?? 0, 2000)
        waitFor(2, "A pushed within 2 s", extra: { relay.relayTail() }) { !first.messages.isEmpty }
        XCTAssertEqual(first.messages.map(\.sinchMessageId), [a])
        let firstMessage = try XCTUnwrap(first.messages.first)
        waitFor(10, "DELIVERED for A at the sink", extra: { relay.sinkTail() }) {
            relay.sinkReports().contains { $0.sinchMessageID == a && $0.status == "DELIVERED" }
        }
        let firstConnection = first.states.last { !$0.connectionId.isEmpty }?.connectionId ?? ""
        XCTAssertFalse(firstConnection.isEmpty)
        first.client.stop()
        waitFor(5, "the first client to stop", extra: { "\(first.states)" }) { first.state?.status == .stopped }
        // B must wait in the pool, not be pushed into the closing socket.
        guard waitFor(10, "the relay to unregister the first connection", extra: { relay.relayTail() }, {
            relay.relayEvents("unregistered").contains { $0["connection_id"] as? String == firstConnection }
        }) else { return }

        try relay.enqueue(appID: appID, userID: user, sinchMessageID: b, title: "B")
        try relay.enqueue(appID: appID, userID: user, sinchMessageID: c, title: "C")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(first.messages.count, 1, "a stopped client emits nothing")

        // Same store, so the seen set and cursor survive. Hello-replay is a no-op for the
        // legacy key: B and C arrive with the Poll after HelloAck, and A may too, which the
        // seen set must swallow.
        let second = Live(relay: relay, appID: appID, userID: user, store: store)
        second.client.start()
        defer { second.client.stop(); Thread.sleep(forTimeInterval: 0.1) }
        waitFor(20, "B and C emitted after the restart", extra: {
            second.logs.joined(separator: "\n") + "\n" + relay.relayTail(30)
        }) { second.messages.count >= 2 }
        XCTAssertEqual(second.messages.map(\.sinchMessageId), [b, c])
        waitFor(10, "DELIVERED for B and C at the sink", extra: { relay.sinkTail() }) {
            let delivered = relay.sinkReports().filter { $0.status == "DELIVERED" }.map(\.sinchMessageID)
            return delivered.contains(b) && delivered.contains(c)
        }
        // Longer than one poll interval (5 s), to catch a late duplicate.
        Thread.sleep(forTimeInterval: 6)

        XCTAssertEqual(second.messages.map(\.sinchMessageId), [b, c], "exactly B and C, in order, A not again")
        XCTAssertTrue(
            second.logs.contains { $0.contains("duplicate message \(firstMessage.id)") },
            "the relay re-sent A and the seen set swallowed it")
        XCTAssertEqual(first.messages.map(\.sinchMessageId), [a], "A was emitted once, by the first client")
        for id in [a, b, c] {
            let reports = relay.sinkReports().filter { $0.sinchMessageID == id }
            XCTAssertEqual(reports.map(\.status), ["DELIVERED"], "\(reports)")
        }
    }
}
#endif
