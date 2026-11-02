import Combine
import Foundation
import UserNotifications
import XCTest
import os
@testable import SinchPushSDK

/// The `AsyncStream` relay API: current state first, later changes delivered, and the
/// Combine subscription cancelled when the stream terminates.
@MainActor
final class ModernRelayStreamTests: XCTestCase {

    private func connected() -> SinchPushSocketState {
        SinchPushSocketState(status: .connected, relayEnabled: true)
    }

    // MARK: - States

    func testSocketStatesYieldsTheCurrentStateFirst() async {
        let push = StreamingPushStub()
        push.states.send(connected())

        var iterator = push.socketStates.makeAsyncIterator()

        let first = await iterator.next()
        XCTAssertEqual(first, connected())
    }

    func testSocketStatesDeliversLaterChanges() async {
        let push = StreamingPushStub()
        var iterator = push.socketStates.makeAsyncIterator()
        let current = await iterator.next()
        XCTAssertEqual(current, push.socketState, "the current state comes first")

        let reconnecting = SinchPushSocketState(status: .reconnecting, relayEnabled: true,
                                                lastError: "offline", reconnectAttempts: 2)
        push.states.send(reconnecting)

        let changed = await iterator.next()
        XCTAssertEqual(changed, reconnecting)
    }

    func testSlowStateConsumerKeepsTheNewestState() async {
        let push = StreamingPushStub()
        var iterator = push.socketStates.makeAsyncIterator()
        _ = await iterator.next()

        push.states.send(SinchPushSocketState(status: .connecting, relayEnabled: true))
        push.states.send(connected())

        let newest = await iterator.next()
        XCTAssertEqual(newest, connected(), "the state stream buffers the newest value")
    }

    func testTerminatingTheStateStreamCancelsItsSubscription() async {
        let push = StreamingPushStub()

        func readOneState() async {
            var iterator = push.socketStates.makeAsyncIterator()
            _ = await iterator.next()
        }
        await readOneState()

        await waitUntil { push.stateCancellations == 1 }
    }

    // MARK: - Messages

    func testSocketMessagesDoesNotReplayEarlierMessages() async {
        let push = StreamingPushStub()
        push.messages.send(relayMessage(id: "before"))

        var iterator = push.socketMessages.makeAsyncIterator()
        push.messages.send(relayMessage(id: "after"))

        let received = await iterator.next()
        XCTAssertEqual(received?.id, "after", "messages are not replayed")
    }

    func testEachStreamIsAnIndependentConsumer() async {
        let push = StreamingPushStub()
        var first: AsyncStream<SinchPushSocketMessage>.Iterator? = push.socketMessages.makeAsyncIterator()
        var second = push.socketMessages.makeAsyncIterator()

        push.messages.send(relayMessage(id: "m-1"))
        let firstMessage = await first?.next()?.id
        let secondMessage = await second.next()?.id
        XCTAssertEqual(firstMessage, "m-1")
        XCTAssertEqual(secondMessage, "m-1")

        first = nil
        await waitUntil { push.messageCancellations == 1 }

        push.messages.send(relayMessage(id: "m-2"))
        let stillDelivered = await second.next()?.id
        XCTAssertEqual(stillDelivered, "m-2", "the remaining consumer keeps receiving")
    }

    func testTerminatingTheMessageStreamCancelsItsSubscription() async {
        let push = StreamingPushStub()

        func readOneMessage() async {
            var iterator = push.socketMessages.makeAsyncIterator()
            push.messages.send(relayMessage(id: "m-1"))
            _ = await iterator.next()
        }
        await readOneMessage()

        await waitUntil { push.messageCancellations == 1 }
    }
}

// MARK: - Doubles

private func relayMessage(id: String) -> SinchPushSocketMessage {
    SinchPushSocketMessage(id: id, sinchMessageId: "sinch-\(id)", receivedAt: Date(timeIntervalSince1970: 0),
                           enqueuedAt: Date(timeIntervalSince1970: 0))
}

/// A `SinchPush` whose relay publishers are real subjects, so a stream sees live values
/// and its cancellation can be counted.
@MainActor
private final class StreamingPushStub: SinchPush {

    let states = CurrentValueSubject<SinchPushSocketState, Never>(
        SinchPushSocketState(status: .idle, relayEnabled: true))
    let messages = PassthroughSubject<SinchPushSocketMessage, Never>()

    private let stateCancelCount = OSAllocatedUnfairLock(initialState: 0)
    private let messageCancelCount = OSAllocatedUnfairLock(initialState: 0)

    var stateCancellations: Int { stateCancelCount.withLock { $0 } }
    var messageCancellations: Int { messageCancelCount.withLock { $0 } }

    var socketState: SinchPushSocketState { states.value }

    var socketStatePublisher: AnyPublisher<SinchPushSocketState, Never> {
        states.handleEvents(receiveCancel: { [stateCancelCount] in
            stateCancelCount.withLock { $0 += 1 }
        }).eraseToAnyPublisher()
    }

    var socketMessagePublisher: AnyPublisher<SinchPushSocketMessage, Never> {
        messages.handleEvents(receiveCancel: { [messageCancelCount] in
            messageCancelCount.withLock { $0 += 1 }
        }).eraseToAnyPublisher()
    }

    func sendDeviceToken(_ token: Data) {}
    func handleNotification(_ payload: [AnyHashable: Any]) -> IsHandled { false }
    func handleNotificationResponse(_ notificationResponse: UNNotificationResponse) -> IsHandled { false }
    func handleWillPresentNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions? { nil }
    func askNotificationPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        completion(.notDetermined)
    }
    func checkPushPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        completion(.notDetermined)
    }
    func askNotificationPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never> {
        Empty().eraseToAnyPublisher()
    }
    func checkPushPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never> {
        Empty().eraseToAnyPublisher()
    }
}
