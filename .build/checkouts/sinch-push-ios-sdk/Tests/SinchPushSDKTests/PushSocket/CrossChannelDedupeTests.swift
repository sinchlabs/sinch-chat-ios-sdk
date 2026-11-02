//  One seen set for the socket, FCM and APNs.

import XCTest
import os

@testable import SinchPushSDK

final class CrossChannelDedupeTests: XCTestCase {

    private let key = PushMessageIdentity.metadataKey

    // MARK: - The registry

    func testMarkSeenIsTrueOnceAndFalseOnARepeat() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())

        XCTAssertTrue(registry.markSeen("m-1"))
        XCTAssertFalse(registry.markSeen("m-1"))
        XCTAssertTrue(registry.contains("m-1"))
        XCTAssertFalse(registry.contains("m-2"))
        XCTAssertFalse(registry.markSeen(""), "an empty id is never a message")
    }

    func testTheRegistryPersistsEveryNewIdUnderTheExistingKey() {
        let store = FakeSocketStateStore()
        let registry = SeenMessageRegistry(store: store)

        registry.markSeen("m-1")
        registry.markSeen("m-2")
        registry.markSeen("m-1")

        XCTAssertEqual(store.seen, ["m-1", "m-2"])
        XCTAssertEqual(SeenMessageRegistry(store: store).snapshot, ["m-1", "m-2"])
    }

    func testAnExistingFiveHundredSetLoadsIntoTheTwoThousandSet() {
        let old = (0..<500).map { "old-\($0)" }
        let store = FakeSocketStateStore(seen: old)
        let registry = SeenMessageRegistry(store: store)

        XCTAssertTrue(registry.contains("old-0"))
        XCTAssertTrue(registry.contains("old-499"))
        XCTAssertFalse(registry.markSeen("old-250"), "a migrated id still dedupes")

        for index in 0..<1500 { XCTAssertTrue(registry.markSeen("new-\(index)")) }
        XCTAssertEqual(registry.snapshot.count, 2000)
        XCTAssertTrue(registry.contains("old-0"))
        XCTAssertTrue(registry.markSeen("one-more"))
        XCTAssertFalse(registry.contains("old-0"))
    }

    func testAStoreWrittenAtTheOldBoundIsNotRewrittenOnLoad() {
        let store = FakeSocketStateStore(seen: ["a", "b"])
        _ = SeenMessageRegistry(store: store).contains("a")
        XCTAssertEqual(store.seen, ["a", "b"])
    }

    func testConcurrentMarkSeenAdmitsEachIdExactlyOnce() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        // Swift 6: the closure is concurrent, so the tally sits behind a lock.
        let admitted = OSAllocatedUnfairLock(initialState: [String: Int]())

        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for _ in 0..<4 {
                for index in 0..<200 {
                    let id = "m-\(index)"
                    if registry.markSeen(id) {
                        admitted.withLock { $0[id, default: 0] += 1 }
                    }
                }
            }
        }

        let tally = admitted.withLock { $0 }
        XCTAssertEqual(tally.count, 200)
        XCTAssertTrue(tally.values.allSatisfy { $0 == 1 })
        XCTAssertEqual(registry.snapshot.count, 200)
    }

    // MARK: - Shared by the client and the push path

    func testAMessageTheSocketDeliveredFirstIsASuppressedAPNsCopy() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .never), registry: registry)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "m-1"))
        XCTAssertEqual(harness.deliveredMessageIDs, ["m-1"])

        let decision = PushPresentationDecider(registry: registry)
            .decide(userInfo: [key: "m-1"], requestIdentifier: "m-1")

        XCTAssertEqual(decision, .suppress)
    }

    func testAMessageDeliveredThroughAPNsFirstIsADedupeHitForTheSocket() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        let decider = PushPresentationDecider(registry: registry)
        XCTAssertEqual(decider.decide(userInfo: [key: "m-1"], requestIdentifier: "x"), .present)

        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter, registry: registry)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "m-1"))

        // Dedupe suppressed the event and notification, not the ack: DELIVERED still goes out.
        XCTAssertEqual(harness.deliveredMessageIDs, [])
        XCTAssertEqual(harness.reports(.delivered).map(\.messageID), ["m-1"])
        XCTAssertEqual(harness.reports(.displayed).count, 0)
        XCTAssertEqual(presenter.posted.count, 0)
    }

    // MARK: - Dedupe suppresses the presentation, not the ack

    /// The relay waits 3 s for DELIVERED before falling back to APNs; a silent hit would
    /// book an ACK_TIMEOUT and resend a message APNs already delivered.
    func testMessageReceivedThroughAPNsIsAcknowledgedOnceByTheSocket() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        XCTAssertEqual(
            PushPresentationDecider(registry: registry)
                .decide(userInfo: [key: "m-1"], requestIdentifier: "u"),
            .present)
        XCTAssertTrue(registry.contains("m-1"), "the APNs path marked it")

        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter, registry: registry)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "m-1"))

        XCTAssertEqual(harness.reports(.delivered).map(\.messageID), ["m-1"], "one DELIVERED went out")
        XCTAssertEqual(harness.reports.count, 1, "and nothing else")
        XCTAssertEqual(harness.deliveredMessageIDs, [])
        XCTAssertEqual(presenter.posted.count, 0)
        XCTAssertTrue(harness.logger.contains("duplicate message m-1; acked, no event, no notification"))
        XCTAssertEqual(harness.client.currentPendingMessages.count, 0)
    }

    func testASocketDuplicateIsAckedOnlyOnce() {
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .never))
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "m-1"))
        harness.deliverMessage(pooledMessage(messageID: "m-1"))

        XCTAssertEqual(harness.reports(.delivered).map(\.messageID), ["m-1"])
        XCTAssertEqual(harness.reports.count, 1)
        XCTAssertEqual(harness.deliveredMessageIDs, ["m-1"])
    }

    // MARK: - willPresent / didReceiveRemoteNotification (PushPresentationDecider)
    // Both entry points use `decide`, which suppresses only what another channel delivered.

    func testASeenAPNsMessageIsSuppressed() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        registry.markSeen("m-1")

        XCTAssertEqual(
            PushPresentationDecider(registry: registry)
                .decide(userInfo: [key: "m-1"], requestIdentifier: "ignored"),
            .suppress)
    }

    func testAnUnseenAPNsMessageIsMarkedAndPresented() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        let decider = PushPresentationDecider(registry: registry)

        XCTAssertEqual(decider.decide(userInfo: [key: "m-1"], requestIdentifier: "u"), .present)
        XCTAssertTrue(registry.contains("m-1"))
    }

    func testTheAPNsPathNeverSuppressesItsOwnMark() {
        // `willPresent` and `didReceiveRemoteNotification` of one push arrive in either order; the second must not hide what the first left unshown.
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        let decider = PushPresentationDecider(registry: registry)

        XCTAssertEqual(decider.decide(userInfo: [key: "m-1"], requestIdentifier: "m-1"), .present)
        XCTAssertEqual(decider.decide(userInfo: [key: "m-1"], requestIdentifier: nil), .present)
        XCTAssertEqual(decider.decide(userInfo: [key: "m-1"], requestIdentifier: "m-1"), .present)
    }

    func testAPushWithoutAnIdIsNeverDeduped() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        let decider = PushPresentationDecider(registry: registry)

        XCTAssertEqual(decider.decide(userInfo: ["aps": ["alert": "hi"]], requestIdentifier: "abc"), .present)
        XCTAssertEqual(decider.decide(userInfo: ["aps": ["alert": "hi"]], requestIdentifier: "abc"), .present)
        XCTAssertEqual(registry.snapshot, [])
    }

    func testTheRequestIdentifierIsTheFallbackOnlyForARecognisableSinchPush() {
        let sinch: [AnyHashable: Any] = ["sinch.push.subscriber_id": "s-1"]

        XCTAssertEqual(
            PushMessageIdentity.messageId(userInfo: sinch, requestIdentifier: "m-1"), "m-1")
        XCTAssertNil(PushMessageIdentity.messageId(userInfo: [:], requestIdentifier: "m-1"))
        XCTAssertNil(
            PushMessageIdentity.messageId(
                userInfo: sinch, requestIdentifier: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        XCTAssertNil(PushMessageIdentity.messageId(userInfo: sinch, requestIdentifier: ""))
        XCTAssertEqual(
            PushMessageIdentity.messageId(
                userInfo: [key: "m-2"], requestIdentifier: "m-1"), "m-2")
    }

    func testASocketNotificationIsRecognisedBySourceOnly() {
        XCTAssertTrue(PushMessageIdentity.isSocketOriginated(userInfo: ["source": "socket"]))
        XCTAssertFalse(PushMessageIdentity.isSocketOriginated(userInfo: [:]))
        XCTAssertFalse(PushMessageIdentity.isSocketOriginated(userInfo: ["source": "apns"]))
        XCTAssertFalse(PushMessageIdentity.isSocketOriginated(userInfo: ["source": 1]))
    }

    func testAPushTheSocketAlreadyDeliveredIsACopyOnBothEntryPoints() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .never), registry: registry)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "m-1"))
        XCTAssertTrue(registry.contains("m-1"))
        let decider = PushPresentationDecider(registry: registry)
        let info: [AnyHashable: Any] = [key: "m-1", "aps": ["alert": "hi"]]

        XCTAssertEqual(decider.decide(userInfo: info, requestIdentifier: nil), .suppress)
        XCTAssertEqual(decider.decide(userInfo: info, requestIdentifier: "m-1"), .suppress)
        XCTAssertEqual(registry.snapshot, ["m-1"], "looked up, not re-marked")
    }

    func testABackgroundPushIsMarkedSoTheSocketsCopyIsADuplicate() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        let decider = PushPresentationDecider(registry: registry)

        XCTAssertEqual(
            decider.decide(userInfo: [key: "m-1", "aps": ["content-available": 1]], requestIdentifier: nil),
            .present)
        XCTAssertTrue(registry.contains("m-1"))
    }

    // MARK: - Notification identity and the delivered-notification check

    func testTheSocketNotificationIdentifierIsTheMessageId() {
        XCTAssertEqual(SocketNotificationPresenter.identifier(messageId: "m-1"), "m-1")
        XCTAssertEqual(SocketNotificationPresenter.identifier(messageId: "a:b:c"), "a:b:c")
    }

    func testAMessageAlreadyInTheNotificationCentreIsNotPostedAgain() {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let delivered = FakeDeliveredNotifications()
        delivered.delivered = ["m-1"]
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter, delivered: delivered)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "m-1"))

        XCTAssertEqual(delivered.asked, ["m-1"])
        XCTAssertEqual(presenter.posted.count, 0, "the APNs copy is on screen already")
        XCTAssertEqual(harness.deliveredMessageIDs, ["m-1"])
        XCTAssertEqual(harness.reports(.delivered).count, 1)
        // Nothing was posted, so DISPLAYED is not claimed.
        XCTAssertEqual(harness.reports(.displayed).count, 0)
        XCTAssertTrue(harness.logger.contains("already in the notification centre"))
    }

    func testAMessageNotInTheNotificationCentreIsPostedAndDisplayed() {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let delivered = FakeDeliveredNotifications()
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter, delivered: delivered)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "m-1"))

        XCTAssertEqual(delivered.asked, ["m-1"])
        XCTAssertEqual(presenter.posted.map(\.id), ["m-1"])
        XCTAssertEqual(harness.reports(.displayed).count, 1)
    }

    func testTheLookupIsNotConsultedWhenNothingWouldBePosted() {
        let delivered = FakeDeliveredNotifications()
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .never), delivered: delivered)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "m-1"))

        XCTAssertEqual(delivered.asked, [])
    }

    func testAnAsynchronousLookupDelaysOnlyThePost() {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let delivered = FakeDeliveredNotifications()
        delivered.answersInline = false
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter, delivered: delivered)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "m-1"))

        XCTAssertEqual(harness.deliveredMessageIDs, ["m-1"])
        XCTAssertEqual(harness.reports(.delivered).count, 1)
        XCTAssertEqual(presenter.posted.count, 0)

        delivered.flush()
        XCTAssertEqual(presenter.posted.map(\.id), ["m-1"])
    }

    func testASkippedPostDoesNotSpendTheAlertWindow() {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let delivered = FakeDeliveredNotifications()
        delivered.delivered = ["m-1"]
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter, delivered: delivered)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "m-1"))
        harness.deliverMessage(pooledMessage(messageID: "m-2"))

        XCTAssertEqual(presenter.posted.map(\.id), ["m-2"])
        XCTAssertEqual(presenter.postedAlerting, [true])
    }

    // MARK: - A hit on an id another channel saw still advances the cursor

    func testAnIdSeenByAPNsAdvancesTheCursorWhenItArrivesOverTheSocket() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        _ = PushPresentationDecider(registry: registry)
            .decide(userInfo: [key: "m-1"], requestIdentifier: "x")
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter, registry: registry)
        harness.handshake()

        harness.deliverMessage(pooledMessage(messageID: "m-1", enqueuedAt: 5_000))

        XCTAssertEqual(harness.store.lastSeen, "m-1")
        XCTAssertEqual(harness.store.lastSeenEnqueuedAt, 5_000)
        XCTAssertEqual(harness.deliveredMessageIDs, [])
        XCTAssertEqual(harness.reports(.delivered).map(\.messageID), ["m-1"])
        XCTAssertEqual(harness.reports(.displayed).count, 0)
        XCTAssertEqual(presenter.posted.count, 0)
    }

    func testAHitOnAnOlderIdDoesNotWalkTheCursorBack() {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        registry.markSeen("m-1")
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .never), registry: registry)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "m-2", enqueuedAt: 9_000))

        harness.deliverMessage(pooledMessage(messageID: "m-1", enqueuedAt: 1_000))

        XCTAssertEqual(harness.store.lastSeen, "m-2")
    }

    /// Cursor at m-2/9_000, then a hit on an already-seen m-1 carrying `hitAt`.
    private func cursorAfterAHit(at hitAt: Int64) -> (String, Int64) {
        let registry = SeenMessageRegistry(store: FakeSocketStateStore())
        registry.markSeen("m-1")
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .never), registry: registry)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "m-2", enqueuedAt: 9_000))
        harness.deliverMessage(pooledMessage(messageID: "m-1", enqueuedAt: hitAt))
        return (harness.store.lastSeen, harness.store.lastSeenEnqueuedAt)
    }

    func testAHitWithAnUnknownTimestampDoesNotMoveTheCursor() {
        let cursor = cursorAfterAHit(at: 0)
        XCTAssertEqual(cursor.0, "m-2")
        XCTAssertEqual(cursor.1, 9_000)
    }

    func testAHitWithAnEqualTimestampDoesNotMoveTheCursor() {
        let cursor = cursorAfterAHit(at: 9_000)
        XCTAssertEqual(cursor.0, "m-2")
        XCTAssertEqual(cursor.1, 9_000)
    }

    func testAHitWithAStrictlyNewerTimestampMovesTheCursor() {
        let cursor = cursorAfterAHit(at: 9_001)
        XCTAssertEqual(cursor.0, "m-1")
        XCTAssertEqual(cursor.1, 9_001)
    }

    // MARK: - The lookup answers after the client was stopped

    func testALookupThatAnswersAfterStopPostsNothingAndReportsNoDisplayed() {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let delivered = FakeDeliveredNotifications()
        delivered.answersInline = false
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter, delivered: delivered)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "m-1"))
        XCTAssertEqual(delivered.asked, ["m-1"])

        harness.client.stop()
        delivered.flush()

        XCTAssertEqual(presenter.posted.count, 0)
        XCTAssertEqual(harness.reports(.displayed).count, 0)
    }

    func testALookupThatAnswersAfterAReconfigurePostsNothing() {
        let presenter = FakeNotificationPresenter()
        presenter.acceptsPost = true
        let delivered = FakeDeliveredNotifications()
        delivered.answersInline = false
        let harness = makeHarness(
            configuration: testConfiguration(displayNotifications: .always),
            presenter: presenter, delivered: delivered)
        harness.handshake()
        harness.deliverMessage(pooledMessage(messageID: "m-1"))

        harness.client.updateConfiguration(testConfiguration(displayNotifications: .always))
        delivered.flush()

        XCTAssertEqual(presenter.posted.count, 0)
        XCTAssertEqual(harness.reports(.displayed).count, 0)
    }
}
