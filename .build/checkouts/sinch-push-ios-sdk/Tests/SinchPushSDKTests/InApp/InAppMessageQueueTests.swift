import XCTest
@testable import SinchPushSDK

@MainActor
final class InAppMessageQueueTests: XCTestCase {

    // MARK: - Doubles

    /// Records the scheduled work instead of running it, so the queue's gaps can
    /// be asserted without waiting.
    @MainActor
    final class RecordingScheduler: InAppScheduling {

        struct Pending {
            let delay: TimeInterval
            let work: @MainActor () -> Void
        }

        private(set) var pending: Pending?
        private(set) var delays: [TimeInterval] = []

        func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
            pending = Pending(delay: delay, work: work)
            delays.append(delay)
        }

        func cancel() {
            pending = nil
        }

        func runPending() {
            let next = pending
            pending = nil
            next?.work()
        }
    }

    @MainActor
    final class RecordingDelegate: InAppMessageDelegate {

        var shouldPresentResult = true
        private(set) var shouldPresentedMessages: [InAppMessage] = []
        private(set) var tappedActions: [InAppChoiceAction] = []
        private(set) var dismissedMessages: [InAppMessage] = []

        func shouldPresent(_ message: InAppMessage) -> Bool {
            shouldPresentedMessages.append(message)
            return shouldPresentResult
        }

        func didTapAction(_ action: InAppChoiceAction, in message: InAppMessage) {
            tappedActions.append(action)
        }

        func didDismiss(_ message: InAppMessage) {
            dismissedMessages.append(message)
        }
    }

    /// A `@MainActor final` class, so the closures handed to the controller only
    /// capture a `Sendable` value instead of the test case itself.
    @MainActor
    final class PresentationSpy {
        var host: UIViewController?
        private(set) var presented: [UIViewController] = []

        func record(_ controller: UIViewController) {
            presented.append(controller)
        }
    }

    // MARK: - Properties

    private var controller: InAppMessageController!
    private var scheduler: RecordingScheduler!
    private var delegate: RecordingDelegate!
    private var spy: PresentationSpy!

    private var presented: [UIViewController] { spy.presented }

    private let text = InAppMessage(body: .text(text: "first"))
    private let other = InAppMessage(body: .text(text: "second"))

    override func setUp() {
        super.setUp()

        let spy = PresentationSpy()
        spy.host = UIViewController()

        controller = InAppMessageController()
        scheduler = RecordingScheduler()
        delegate = RecordingDelegate()
        self.spy = spy

        controller.scheduler = scheduler
        controller.delegate = delegate
        controller.hostProvider = { [spy] in spy.host }
        controller.presentAction = { [spy] _, controller in
            spy.record(controller)
        }
    }

    // MARK: - Empty payload

    /// Ported from `InAppMessagesControllerTests.testFailureShowInAppMessage`.
    func testEmptyPayloadIsNotQueued() {
        let accepted = controller.present(userInfo: [:])

        XCTAssertFalse(accepted)
        XCTAssertTrue(controller.queue.isEmpty)
        XCTAssertTrue(presented.isEmpty)
    }

    // MARK: - Ingestion

    func testDisabledControllerRejects() {
        controller.isEnabled = false

        XCTAssertFalse(controller.present(text))
        XCTAssertTrue(controller.queue.isEmpty)
        XCTAssertTrue(delegate.shouldPresentedMessages.isEmpty)
    }

    func testDelegateCanVeto() {
        delegate.shouldPresentResult = false

        XCTAssertFalse(controller.present(text))
        XCTAssertTrue(controller.queue.isEmpty)
        XCTAssertTrue(presented.isEmpty)
    }

    func testFirstMessagePresentsImmediately() {
        XCTAssertTrue(controller.present(text))

        XCTAssertEqual(controller.queue, [text])
        XCTAssertTrue(controller.isPresenting)
        XCTAssertEqual(presented.count, 1)

        let alert = presented[0] as? InAppMessageViewController
        XCTAssertNotNil(alert)
        XCTAssertEqual(alert?.modalPresentationStyle, .overFullScreen)
        XCTAssertEqual(alert?.modalTransitionStyle, .crossDissolve)
    }

    func testSecondMessageWaitsForTheFirst() {
        controller.present(text)
        controller.present(other)

        XCTAssertEqual(controller.queue, [text, other])
        XCTAssertEqual(presented.count, 1)
    }

    // MARK: - Dismissal and gaps

    /// Ported from `InAppMessagesControllerTests.testCloseInAppMessage`.
    func testCloseRemovesTheMessage() {
        controller.present(text)
        controller.messageDidClose(text)

        XCTAssertTrue(controller.queue.isEmpty)
        XCTAssertFalse(controller.isPresenting)
        XCTAssertEqual(delegate.dismissedMessages, [text])
        XCTAssertTrue(scheduler.delays.isEmpty)
    }

    func testHalfASecondBetweenMessages() {
        controller.present(text)
        controller.present(other)
        controller.messageDidClose(text)

        XCTAssertEqual(scheduler.delays, [controller.presentationGap])
        XCTAssertEqual(controller.presentationGap, 0.5, accuracy: 0.0001)
        XCTAssertEqual(controller.queue, [other])
        XCTAssertEqual(presented.count, 1)

        scheduler.runPending()

        XCTAssertEqual(presented.count, 2)
        XCTAssertTrue(controller.isPresenting)
        XCTAssertEqual(controller.queue, [other])
    }

    func testClosingAnUnknownMessageRemovesItWithoutStalling() {
        controller.present(text)

        let stray = InAppMessage(body: .text(text: "stray"))
        controller.messageDidClose(stray)

        XCTAssertEqual(controller.queue, [text])
        XCTAssertFalse(controller.isPresenting)
    }

    // MARK: - Alert back-off

    func testAlertInFrontBacksOffFiveSeconds() {
        spy.host = UIAlertController(title: "App alert", message: nil, preferredStyle: .alert)

        XCTAssertTrue(controller.present(text))

        XCTAssertEqual(controller.queue, [text])
        XCTAssertFalse(controller.isPresenting)
        XCTAssertEqual(presented.count, 0)
        XCTAssertEqual(scheduler.delays, [controller.alertBackoff])
        XCTAssertEqual(controller.alertBackoff, 5.0, accuracy: 0.0001)

        // The alert is gone by the next attempt.
        spy.host = UIViewController()
        scheduler.runPending()

        XCTAssertTrue(controller.isPresenting)
        XCTAssertEqual(presented.count, 1)
    }

    func testMissingHostRetriesLater() {
        spy.host = nil

        controller.present(text)

        XCTAssertEqual(scheduler.delays, [controller.alertBackoff])
        XCTAssertFalse(controller.isPresenting)
    }

    // MARK: - Reported actions

    func testTappedActionIsReportedToTheDelegate() {
        let choice = InAppChoice(title: "Yes", action: .text(postbackData: "yes"))
        let message = InAppMessage(body: .choices(text: "Pick", choices: [choice]))

        controller.present(message)

        let alert = presented.first as? InAppMessageViewController
        XCTAssertNotNil(alert)
        // The view controller reports the action; drive it the same way a tap would.
        controller.inAppMessageViewController(alert!, didSelect: choice.action, in: message)

        XCTAssertEqual(delegate.tappedActions, [.text(postbackData: "yes")])
    }

    func testDismissAllClearsTheQueue() {
        controller.present(text)
        controller.present(other)

        controller.dismissAll()

        XCTAssertTrue(controller.queue.isEmpty)
        XCTAssertFalse(controller.isPresenting)
        XCTAssertEqual(delegate.dismissedMessages, [text, other])
    }

    // MARK: - Push pipeline seam

    func testRelayMetadataIsConsumedOnlyForInAppMessages() {
        let payload = InAppPayloadFixtures.relayMetadata(InAppPayloadFixtures.text("Relay"))

        XCTAssertTrue(controller.present(metadata: payload))
        XCTAssertEqual(controller.queue, [InAppMessage(body: .text(text: "Relay"))])

        XCTAssertFalse(controller.present(metadata: InAppPayloadFixtures.foreignMetadata))
    }

    func testUserInfoIsConsumedOnlyForInAppMessages() {
        let payload = InAppPayloadFixtures.userInfo(InAppPayloadFixtures.media("https://cdn.example.com/a.png"))

        XCTAssertTrue(controller.present(userInfo: payload))
        XCTAssertEqual(controller.queue, [InAppMessage(body: .media(url: "https://cdn.example.com/a.png"))])

        XCTAssertFalse(controller.present(userInfo: [:]))
    }
}
