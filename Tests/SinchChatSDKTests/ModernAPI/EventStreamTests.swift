import XCTest
import Combine

@testable import SinchChatSDK

/// The `AsyncStream` accessors of the SDK's public publishers.
@MainActor
final class EventStreamTests: XCTestCase {

    // MARK: - SinchChatSDK.events

    func testPluginEventsStreamDeliversTheEventsOfTheSubject() async {
        let sdk = SinchChatSDK()
        // Reading the property subscribes synchronously, so the events sent afterwards are buffered.
        let stream = sdk.events

        sdk.eventListenerSubject.send(.didCloseChat)
        sdk.eventListenerSubject.send(.didChangeInternetState(isOn: true))

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        guard case .didCloseChat = first else {
            return XCTFail("unexpected first event: \(String(describing: first))")
        }
        guard case let .didChangeInternetState(isOn) = second else {
            return XCTFail("unexpected second event: \(String(describing: second))")
        }
        XCTAssertTrue(isOn)
    }

    func testEventsSentBeforeTheStreamExistsAreNotReplayed() async {
        let sdk = SinchChatSDK()
        sdk.eventListenerSubject.send(.didCloseChat)

        let stream = sdk.events
        sdk.eventListenerSubject.send(.didChangeInternetState(isOn: false))

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()

        guard case let .didChangeInternetState(isOn) = first else {
            return XCTFail("the stream must start with the event sent after it was created, got \(String(describing: first))")
        }
        XCTAssertFalse(isOn)
    }

    func testCancellingTheConsumingTaskEndsTheIteration() async {
        let sdk = SinchChatSDK()
        let task = Task { () -> Bool in
            for await _ in sdk.events {}
            return true
        }

        task.cancel()

        let finished = await task.value
        XCTAssertTrue(finished, "a cancelled consumer must leave the loop instead of hanging")
    }

    // MARK: - SinchInbox.events

    func testInboxEventsStreamDeliversTheEventsOfTheSubject() async {
        let inbox = DefaultSinchInbox(pushPermissionHandler: PushNofiticationPermissionHandlerStub())
        let stream = inbox.events

        inbox.chatInboxEventListenerSubject.send(.subcriptionFailed)

        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()

        guard case .subcriptionFailed = event else {
            return XCTFail("unexpected inbox event: \(String(describing: event))")
        }
    }

    // MARK: - Termination

    func testReleasingTheStreamCancelsItsSubscription() {
        let subject = PassthroughSubject<SinchInboxEvent, Never>()
        let cancelled = Locked(false)
        var stream: AsyncStream<SinchInboxEvent>? = EventStream.make(
            from: subject.handleEvents(receiveCancel: cancellationHandler(cancelled))
        )
        var iterator = stream?.makeAsyncIterator()

        XCTAssertNotNil(iterator)
        XCTAssertFalse(cancelled.value)

        iterator = nil
        stream = nil

        XCTAssertTrue(cancelled.value, "the stream must cancel its subscription when it is released")
    }

    func testBreakingOutOfTheLoopEndsTheStream() async {
        let sdk = SinchChatSDK()
        let iterated = Locked(0)
        let stream = sdk.events
        sdk.eventListenerSubject.send(.didCloseChat)

        let task = Task { () -> Bool in
            for await _ in stream {
                iterated.mutate { $0 += 1 }
                break
            }
            return true
        }

        let finished = await task.value
        XCTAssertTrue(finished)
        XCTAssertEqual(iterated.value, 1)
    }
}
