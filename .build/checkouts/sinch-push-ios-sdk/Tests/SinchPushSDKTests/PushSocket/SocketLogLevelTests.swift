//  SocketLogLevelTests.swift — production `Logger` drops `.verbose`, so actionable
//  diagnostics carry `.warning` or `.error`.

import XCTest

@testable import SinchPushSDK

final class SocketLogLevelTests: XCTestCase {

    func testARateLimitedAckLogsOneWarning() {
        let harness = makeReportHarness(draw: 0)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        harness.ack(accepted: false, error: "rate_limited", token: "msg-1:1")

        XCTAssertEqual(harness.logger.levels(containing: "(rate_limited)"), [.warning])
    }

    func testAnUnauthorizedCloseLogsAnError() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()

        harness.serverClose(reason: .unauthorized, detail: "bad token")

        XCTAssertEqual(harness.logger.levels(containing: "unauthorized (terminal)"), [.error])
    }

    func testAMalformedFrameIsAnErrorAndAnUnknownTagIsAWarning() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()

        harness.transport.deliverRaw(Wire.envelope(tag: 200, payload: []))
        harness.transport.deliverRaw([0x01])

        XCTAssertEqual(harness.logger.levels(containing: "unknown frame tag 200"), [.warning])
        XCTAssertEqual(harness.logger.levels(containing: "malformed server frame"), [.error])
    }

    func testANormalMessageLogsOnlyVerboseLines() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()
        let handshakeLines = harness.logger.entries.count

        harness.deliverMessage(pooledMessage(messageID: "msg-1"))

        XCTAssertFalse(harness.logger.entries.isEmpty)
        XCTAssertTrue(harness.logger.entries.allSatisfy { $0.level == .verbose })
        XCTAssertGreaterThanOrEqual(harness.logger.entries.count, handshakeLines)
    }

    func testALineWithoutALevelIsVerbose() {
        let logger = RecordingLogger()

        logger.log("plain")

        XCTAssertEqual(logger.entries.map(\.level), [.verbose])
    }

    func testTheSDKAdapterMapsEachLevelToTheMatchingLoggerLevel() {
        typealias Deps = PushSocketManager.Dependencies
        XCTAssertEqual(Deps.sdkLevel(for: .error), .error)
        XCTAssertEqual(Deps.sdkLevel(for: .warning), .warning)
        XCTAssertEqual(Deps.sdkLevel(for: .verbose), .verbose)
    }

    func testThePrintLoggerKeepsThePrefixAndPassesTheLevelToItsSink() {
        let received = LockedBox<[(String, SocketLogLevel)]>([])
        let logger = PrintSocketLogger(prefix: "[P]") { line, level in
            received.withValue { $0.append((line, level)) }
        }

        logger.log("boom", level: .error)
        logger.log("note")

        let seen = received.withValue { $0 }
        XCTAssertEqual(seen.map(\.0), ["[P] boom", "[P] note"])
        XCTAssertEqual(seen.map(\.1), [.error, .verbose])
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }
    func withValue<T>(_ body: (inout Value) -> T) -> T { lock.withLock { body(&value) } }
}
