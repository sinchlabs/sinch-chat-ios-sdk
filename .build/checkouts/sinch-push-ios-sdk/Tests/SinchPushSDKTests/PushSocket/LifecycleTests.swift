//  LifecycleTests.swift — iOS is foreground-only; APNs is the background channel.
//  Driven through the client; the notification wiring is covered by
//  UIApplicationSocketLifecycleTests.

import XCTest

@testable import SinchPushSDK

final class LifecycleTests: XCTestCase {

    func testBackgroundClosesTheSocketWithOneThousand() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()

        harness.client.suspend()

        let call = harness.transport.closeCalls.last
        XCTAssertEqual(call?.code, 1000, "the background close is a normal closure")
        XCTAssertEqual(harness.recorder.current?.status, .idle)
        XCTAssertFalse(harness.transport.isOpen)
    }

    func testBackgroundCancelsTheBackoffAndSchedulesNothing() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()

        harness.client.suspend()

        XCTAssertEqual(harness.pendingTimers, 0)
        let sockets = harness.socketCount
        harness.advanceToNoFutureTimer()
        XCTAssertEqual(harness.socketCount, sockets, "a socket was opened while backgrounded")
    }

    func testBackgroundKeepsTheConfiguration() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()

        harness.client.suspend()
        harness.client.resume()
        harness.transport.openSocket()

        XCTAssertEqual(harness.hello?.authToken, "jwt.token.value")
        XCTAssertEqual(harness.hello?.appID, "app-1")
        XCTAssertEqual(harness.hello?.userID, "user-1")
    }

    func testBackgroundFlushesNothing() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()

        harness.client.suspend()
        harness.client.report(messageId: "msg-1", status: .dismissed)

        XCTAssertEqual(harness.reports.count, 0, "something was flushed with no socket")
        XCTAssertEqual(harness.store.outbox.count, 1)
    }

    func testForegroundReconnectsPollsImmediatelyAndFlushesTheOutbox() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()
        harness.client.suspend()
        harness.client.report(messageId: "msg-1", status: .dismissed)

        harness.client.resume()
        XCTAssertEqual(harness.socketCount, 2, "the foreground transition reconnects")

        harness.handshake(connectionID: "conn-after-resume")

        XCTAssertEqual(harness.transport.sentKinds.first, "hello")
        XCTAssertEqual(harness.polls.count, 1)
        XCTAssertEqual(harness.reports.map(\.messageID), ["msg-1"])
        XCTAssertEqual(harness.recorder.current?.status, .connected)
        XCTAssertEqual(harness.recorder.current?.connectionId, "conn-after-resume")
    }

    func testABackgroundResumeStartsTheBackoffFromZero() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()

        for _ in 0..<3 {
            harness.handshake()
            harness.serverClose(reason: .poolFull, detail: "rate_limited")
            harness.scheduler.advance(by: 60_000)
        }
        harness.handshake()
        harness.client.suspend()
        XCTAssertEqual(harness.client.backoffState.attempts, 0)

        harness.client.resume()
        harness.handshake()
        harness.serverClose(reason: .shutdown)

        XCTAssertEqual(harness.client.backoffState.attempts, 1)
    }

    func testASecondBackgroundSignalIsIgnored() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()

        harness.client.suspend()
        let closes = harness.transport.closeCalls.count
        harness.client.suspend()

        XCTAssertEqual(harness.transport.closeCalls.count, closes)
    }

    func testAResumeWithoutABackgroundIsIgnored() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()

        harness.client.resume()

        XCTAssertEqual(harness.socketCount, 1)
        XCTAssertEqual(harness.recorder.current?.status, .connected)
    }

    func testStopWhileBackgroundedStaysStopped() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()
        harness.client.suspend()
        harness.client.stop()

        harness.client.resume()

        XCTAssertEqual(harness.socketCount, 1, "a stopped client was revived by a resume")
        XCTAssertEqual(harness.recorder.current?.status, .stopped)
    }

    // MARK: - Hello.background is never set on iOS

    func testTheBackgroundFlagIsFalseOnEveryConnect() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()
        harness.transport.openSocket()
        XCTAssertFalse(harness.hello?.background ?? true)

        harness.client.suspend()
        harness.client.resume()
        harness.transport.openSocket()
        XCTAssertFalse(harness.hello?.background ?? true)

        harness.handshake()
        harness.transport.failTransport(code: 1006)
        harness.scheduler.advance(by: 60_000)
        harness.transport.openSocket()
        XCTAssertFalse(harness.hello?.background ?? true)
    }

    func testTheBackgroundFlagCannotBeConfigured() {
        let configuration = testConfiguration()
        XCTAssertEqual(configuration.resolvedSDKVersion, SocketConfiguration.defaultSDKVersion)

        let harness = makeHarness(configuration: configuration)
        harness.handshake()
        harness.transport.openSocket()
        XCTAssertFalse(harness.hello?.background ?? true)
    }

    // MARK: - Retiring the client

    func testRetireClosesTheSocketLikeStopAndIgnoresALatePresenterCompletion() {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        presenter.defersCompletions = true
        let harness = makeHarness(presenter: presenter)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "m-1"))
        XCTAssertEqual(presenter.posted.map(\.id), ["m-1"])
        let outboxBefore = harness.store.outbox

        harness.client.retire()
        XCTAssertEqual(harness.recorder.current?.status, .stopped)
        XCTAssertFalse(harness.transport.isOpen)
        harness.store.saveOutbox([])   // the replacement's store

        presenter.completeDeferred()

        XCTAssertTrue(harness.store.outbox.isEmpty, "no DISPLAYED, no write-back of the old outbox")
        XCTAssertFalse(outboxBefore.isEmpty, "DELIVERED was queued before the retire")
        XCTAssertFalse(harness.reports.contains { $0.status == .displayed })
    }

    func testRetireMakesReportsStartAndResetNoOps() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()
        harness.client.retire()
        let sockets = harness.socketCount

        harness.client.report(messageId: "m-1", status: .dismissed)
        harness.client.start()
        harness.client.resetSessionState()
        harness.client.clearPendingMessages()

        XCTAssertEqual(harness.socketCount, sockets, "a retired client never reconnects")
        XCTAssertTrue(harness.store.outbox.isEmpty)
    }

    func testRetireIgnoresAFrameTheTransportAlreadyHandedOver() {
        let harness = makeHarness(configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()
        // The transport calls `onBinary` outside its lock, so a frame can be in flight when `retire()` runs.
        let inFlight = harness.transport.onBinary
        XCTAssertNotNil(inFlight)
        let store = harness.store
        let eventsBefore = harness.recorder.messages.count
        let pendingBefore = store.messages.count
        let lastSeenBefore = store.lastSeen
        let seenBefore = store.seen

        harness.client.retire()
        var message = Sinch_Push_Delivery_V1beta1_Ws_Message()
        message.message = pooledMessage(messageID: "late-1")
        inFlight?(try! FrameCodec.encodeServerFrame(makeServerFrame(message)))

        XCTAssertEqual(store.messages.count, pendingBefore, "no pending write into the shared store")
        XCTAssertEqual(store.lastSeen, lastSeenBefore, "no last_seen write")
        XCTAssertEqual(store.seen, seenBefore, "no seen-set write")
        XCTAssertEqual(harness.recorder.messages.count, eventsBefore, "no event")
    }
}
