//  URLSessionWebSocketTransportTests.swift — callback discipline of the live transport.
//  Port 1 on the loopback refuses immediately, the retryable path (close 1006).

import XCTest

@testable import SinchPushSDK

final class URLSessionWebSocketTransportTests: XCTestCase {

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var opens = 0
        private var closes: [SocketTransportClose] = []

        var openCount: Int { lock.withLock { opens } }
        var closeEvents: [SocketTransportClose] { lock.withLock { closes } }

        func opened() { lock.withLock { opens += 1 } }
        func closed(_ close: SocketTransportClose) { lock.withLock { closes.append(close) } }
    }

    private let refusedURL = URL(string: "ws://127.0.0.1:1/ws")!

    func testARefusedUpgradeIsReportedAsExactlyOneClose1006() {
        let transport = URLSessionWebSocketTransport()
        let counter = Counter()
        let closed = expectation(description: "onClose")
        transport.onOpen = { counter.opened() }
        transport.onClose = {
            counter.closed($0)
            closed.fulfill()
        }

        transport.connect(to: refusedURL)
        wait(for: [closed], timeout: 15)
        // Give a second, erroneous close the chance to arrive.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        XCTAssertEqual(counter.openCount, 1, "open is reported once connect() returns")
        XCTAssertEqual(counter.closeEvents.count, 1)
        XCTAssertEqual(counter.closeEvents.first?.code, 1006)
        XCTAssertFalse(transport.isOpen)
    }

    /// The client detaches its callbacks before `close` (`closeSocket()`); the cancelled
    /// receive then fails with nothing installed to receive it.
    func testASocketClosedAfterDetachingItsCallbacksDeliversNothing() {
        let transport = URLSessionWebSocketTransport()
        let counter = Counter()
        transport.onOpen = { counter.opened() }
        transport.onClose = { counter.closed($0) }

        transport.connect(to: refusedURL)
        XCTAssertTrue(transport.isOpen)
        transport.onOpen = nil
        transport.onBinary = nil
        transport.onClose = nil
        transport.close(code: 1000, reason: nil)
        XCTAssertFalse(transport.isOpen)
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        XCTAssertEqual(counter.closeEvents.count, 0)
    }
}
