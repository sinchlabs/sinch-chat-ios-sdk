import XCTest

@testable import SinchPushSDK

/// The APNs rule: the first delivery of a push that names its message and subscriber is queued.
final class APNsDeliveryReportTests: XCTestCase {

    private let messageKey = "sinch.push.message_id"
    private let subscriberKey = "sinch.push.subscriber_id"
    private var registry: SeenMessageRegistry!
    private var reporter: RecordingDeliveryReporter!
    private var decider: PushPresentationDecider!

    override func setUp() {
        super.setUp()
        registry = SeenMessageRegistry(store: FakeSocketStateStore())
        reporter = RecordingDeliveryReporter()
        decider = PushPresentationDecider(registry: registry, deliveryReporter: reporter)
    }

    func testANewPushWithBothKeysIsReported() {
        let decision = decider.decide(userInfo: [messageKey: "m-1", subscriberKey: "s-1"], requestIdentifier: "x")

        XCTAssertEqual(decision, .present)
        XCTAssertEqual(reporter.reports.map(\.messageID), ["m-1"])
        XCTAssertEqual(reporter.reports.map(\.subscriberID), ["s-1"])
    }

    func testAMessageTheSocketAlreadyMarkedIsNotReported() {
        registry.markSeen("m-1")

        let decision = decider.decide(userInfo: [messageKey: "m-1", subscriberKey: "s-1"], requestIdentifier: "x")

        XCTAssertEqual(decision, .suppress)
        XCTAssertTrue(reporter.reports.isEmpty)
    }

    func testAPushWithoutASubscriberIsNotReported() {
        XCTAssertEqual(decider.decide(userInfo: [messageKey: "m-1"], requestIdentifier: "x"), .present)
        XCTAssertEqual(decider.decide(userInfo: [messageKey: "m-2", subscriberKey: ""], requestIdentifier: "x"), .present)
        XCTAssertEqual(decider.decide(userInfo: [messageKey: "m-3", subscriberKey: 7], requestIdentifier: "x"), .present)

        XCTAssertTrue(reporter.reports.isEmpty)
    }

    func testAPushWithoutAMessageIdIsNotReportedEvenWithARequestIdentifier() {
        XCTAssertEqual(decider.decide(userInfo: [subscriberKey: "s-1"], requestIdentifier: "request-1"), .present)
        XCTAssertEqual(decider.decide(userInfo: [messageKey: "", subscriberKey: "s-1"], requestIdentifier: "request-1"),
                       .present)

        XCTAssertTrue(reporter.reports.isEmpty)
        XCTAssertTrue(registry.contains("request-1"))
    }

    func testTheSecondCallbackForTheSamePushDoesNotReportAgain() {
        let userInfo: [AnyHashable: Any] = [messageKey: "m-1", subscriberKey: "s-1"]

        XCTAssertEqual(decider.decide(userInfo: userInfo, requestIdentifier: "m-1"), .present)
        XCTAssertEqual(decider.decide(userInfo: userInfo, requestIdentifier: nil), .present)
        XCTAssertEqual(decider.decide(userInfo: userInfo, requestIdentifier: "m-1"), .present)

        XCTAssertEqual(reporter.reports.count, 1)
    }

    func testEachPushIsReportedOnce() {
        _ = decider.decide(userInfo: [messageKey: "m-1", subscriberKey: "s-1"], requestIdentifier: nil)
        _ = decider.decide(userInfo: [messageKey: "m-2", subscriberKey: "s-1"], requestIdentifier: nil)

        XCTAssertEqual(reporter.reports.map(\.messageID), ["m-1", "m-2"])
    }

    func testADeciderWithoutAReporterStillDecides() {
        let plain = PushPresentationDecider(registry: registry)

        XCTAssertEqual(plain.decide(userInfo: [messageKey: "m-1", subscriberKey: "s-1"], requestIdentifier: nil), .present)
    }
}
