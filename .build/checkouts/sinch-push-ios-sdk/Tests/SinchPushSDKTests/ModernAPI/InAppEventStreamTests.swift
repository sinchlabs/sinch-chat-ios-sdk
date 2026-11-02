import XCTest
@testable import SinchPushSDK

/// `InAppMessages.events`: the same lifecycle the delegate gets, delivered to one or
/// many async consumers.
@MainActor
final class InAppEventStreamTests: XCTestCase {

    private var controller: InAppMessageController!
    private var scheduler: NoopScheduler!
    private var delegate: RecordingEventDelegate!
    private var spy: PresentationSpy!

    private let text = InAppMessage(body: .text(text: "first"))
    private let other = InAppMessage(body: .text(text: "second"))

    override func setUp() async throws {
        try await super.setUp()
        controller = InAppMessageController()
        scheduler = NoopScheduler()
        delegate = RecordingEventDelegate()
        spy = PresentationSpy()
        controller.scheduler = scheduler
        controller.delegate = delegate
        controller.hostProvider = { [spy] in spy.host }
        controller.presentAction = { [spy] _, controller in spy.record(controller) }
    }

    func testPresentedEventIsEmittedAndTheDelegateStillRuns() async {
        var iterator = controller.events.makeAsyncIterator()

        XCTAssertTrue(controller.present(text))

        guard case .presented(let message)? = await iterator.next() else {
            return XCTFail("expected a presented event")
        }
        XCTAssertEqual(message, text)
        XCTAssertEqual(delegate.shouldPresentedMessages, [text])
    }

    func testActionTappedEventIsEmittedAndTheDelegateStillRuns() async {
        let choice = InAppChoice(title: "Yes", action: .text(postbackData: "yes"))
        let message = InAppMessage(body: .choices(text: "Pick", choices: [choice]))
        var iterator = controller.events.makeAsyncIterator()

        XCTAssertTrue(controller.present(message))
        _ = await iterator.next() // presented
        let alert = spy.presented.compactMap { $0 as? InAppMessageViewController }.first
        guard let alert else { return XCTFail("the alert was not rendered") }
        controller.inAppMessageViewController(alert, didSelect: choice.action, in: message)

        guard case .actionTapped(let action, let tappedIn)? = await iterator.next() else {
            return XCTFail("expected an actionTapped event")
        }
        XCTAssertEqual(action, .text(postbackData: "yes"))
        XCTAssertEqual(tappedIn, message)
        XCTAssertEqual(delegate.tappedActions, [.text(postbackData: "yes")])
    }

    func testDismissedEventIsEmittedAndTheDelegateStillRuns() async {
        var iterator = controller.events.makeAsyncIterator()
        controller.present(text)
        _ = await iterator.next() // presented

        controller.messageDidClose(text)

        guard case .dismissed(let message)? = await iterator.next() else {
            return XCTFail("expected a dismissed event")
        }
        XCTAssertEqual(message, text)
        XCTAssertEqual(delegate.dismissedMessages, [text])
    }

    func testDismissAllEmitsDismissedForEveryQueuedMessage() async {
        var iterator = controller.events.makeAsyncIterator()
        controller.present(text)
        controller.present(other)

        controller.dismissAll()

        var events: [InAppMessageEvent] = []
        for _ in 0..<3 {
            guard let event = await iterator.next() else { break }
            events.append(event)
        }

        XCTAssertEqual(events.count, 3)
        guard case .presented(let first) = events[0], case .presented(let second) = events[1],
              case .dismissed(let dropped) = events[2] else {
            return XCTFail("unexpected events: \(events)")
        }
        XCTAssertEqual(first, text)
        XCTAssertEqual(second, other)
        XCTAssertEqual(dropped, text, "the head is dismissed first")
        XCTAssertEqual(delegate.dismissedMessages, [text, other])
    }

    func testTwoConsumersBothReceiveAndOneLeavingDoesNotStopTheOther() async {
        var first: AsyncStream<InAppMessageEvent>.Iterator? = controller.events.makeAsyncIterator()
        var second = controller.events.makeAsyncIterator()

        controller.present(text)

        guard case .presented(let firstMessage)? = await first?.next() else {
            return XCTFail("the first consumer must receive the event")
        }
        guard case .presented(let secondMessage)? = await second.next() else {
            return XCTFail("the second consumer must receive the event")
        }
        XCTAssertEqual(firstMessage, text)
        XCTAssertEqual(secondMessage, text)

        first = nil
        controller.present(other)

        guard case .presented(let stillDelivered)? = await second.next() else {
            return XCTFail("the remaining consumer must keep receiving")
        }
        XCTAssertEqual(stillDelivered, other)
    }

    func testATerminatedConsumerIsRemovedFromTheFanOut() async {
        var first: AsyncStream<InAppMessageEvent>.Iterator? = controller.events.makeAsyncIterator()
        var second = controller.events.makeAsyncIterator()
        XCTAssertEqual(controller.eventStream.consumerCount, 2)

        first = nil
        await waitUntil { controller.eventStream.consumerCount == 1 }

        // The remaining consumer is unaffected and still gets the next event.
        controller.present(text)
        guard case .presented(let message)? = await second.next() else {
            return XCTFail("the remaining consumer must keep receiving")
        }
        XCTAssertEqual(message, text)
    }

    func testThePublicFacadeExposesTheStream() {
        let events: AsyncStream<InAppMessageEvent> = InAppMessages.shared.events
        _ = events
    }
}

// MARK: - Doubles

/// Runs no scheduled work: the queue's gap is irrelevant to the events.
@MainActor
private final class NoopScheduler: InAppScheduling {
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {}
    func cancel() {}
}

/// Collects the alert controllers the queue presents.
@MainActor
private final class PresentationSpy {
    var host: UIViewController? = UIViewController()
    private(set) var presented: [UIViewController] = []

    func record(_ controller: UIViewController) {
        presented.append(controller)
    }
}

@MainActor
private final class RecordingEventDelegate: InAppMessageDelegate {
    private(set) var shouldPresentedMessages: [InAppMessage] = []
    private(set) var tappedActions: [InAppChoiceAction] = []
    private(set) var dismissedMessages: [InAppMessage] = []

    func shouldPresent(_ message: InAppMessage) -> Bool {
        shouldPresentedMessages.append(message)
        return true
    }

    func didTapAction(_ action: InAppChoiceAction, in message: InAppMessage) {
        tappedActions.append(action)
    }

    func didDismiss(_ message: InAppMessage) {
        dismissedMessages.append(message)
    }
}
