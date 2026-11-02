//  A real serial scheduler verifies that presenter completions from another
//  queue re-enter client confinement.

import XCTest

@testable import SinchPushSDK

final class BackgroundPresenterCompletionTests: XCTestCase {

    private final class DeferredPresenter: NotificationPresenting, @unchecked Sendable {
        private let lock = NSLock()
        private var _completions: [@Sendable (Bool) -> Void] = []
        private var _handlerRegistered = false
        let posted: XCTestExpectation

        init(posted: XCTestExpectation) { self.posted = posted }

        var handlerRegistered: Bool {
            get { lock.withLock { _handlerRegistered } }
            set { lock.withLock { _handlerRegistered = newValue } }
        }

        var completions: [@Sendable (Bool) -> Void] { lock.withLock { _completions } }

        func post(
            _ message: SocketMessageEvent, alerting: Bool, completion: @escaping @Sendable (Bool) -> Void
        ) {
            lock.withLock { _completions.append(completion) }
            posted.fulfill()
        }
    }

    func testACompletionFromABackgroundQueueQueuesDisplayedOnceAndPersistsShown() throws {
        let queue = DispatchQueue(label: "test.push.socket.scheduler")
        let store = FakeSocketStateStore()
        let factory = FakeSocketTransportFactory()
        let presenter = DeferredPresenter(posted: expectation(description: "post called"))
        presenter.posted.assertForOverFulfill = true

        let client = SocketClient(
            configuration: testConfiguration(displayNotifications: .always),
            transportFactory: factory,
            scheduler: DispatchScheduler(queue: queue),
            random: ScriptedRandomSource(fixed: 0.5),
            store: store,
            tokenStore: InMemoryAuthTokenStore(),
            presenter: presenter,
            logger: RecordingLogger(),
            seenRegistry: SeenMessageRegistry(store: store),
            callbacks: SocketClient.Callbacks())
        client.start()

        queue.sync {}
        let socket = try XCTUnwrap(factory.current)
        socket.openSocket()
        var ack = Sinch_Push_Delivery_V1beta1_Ws_HelloAck()
        ack.connectionID = "conn-1"
        socket.deliver(makeServerFrame(ack))
        var message = Sinch_Push_Delivery_V1beta1_Ws_Message()
        message.message = pooledMessage(messageID: "msg-1")
        socket.deliver(makeServerFrame(message))

        wait(for: [presenter.posted], timeout: 5)
        queue.sync {}
        XCTAssertEqual(presenter.completions.count, 1)
        XCTAssertTrue(
            queue.sync { socket.reports.filter { $0.status == .displayed }.isEmpty },
            "nothing is DISPLAYED until the presenter completes")

        let completed = expectation(description: "presenter completed off-queue")
        let completion = try XCTUnwrap(presenter.completions.first)
        DispatchQueue.global(qos: .userInitiated).async {
            completion(true)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        queue.sync {}

        let (displayed, shown) = queue.sync {
            (
                socket.reports.filter { $0.status == .displayed },
                store.messages.first(where: { $0.id == "msg-1" })?.shown
            )
        }
        XCTAssertEqual(displayed.count, 1, "DISPLAYED is queued exactly once")
        XCTAssertEqual(displayed.first?.messageID, "msg-1")
        XCTAssertEqual(shown, true, "`shown` is persisted for the message")
        XCTAssertEqual(client.currentPendingMessages.first?.shown, true)
    }
}
