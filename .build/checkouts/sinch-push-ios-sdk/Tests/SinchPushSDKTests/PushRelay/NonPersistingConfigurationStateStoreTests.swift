import XCTest
@testable import SinchPushSDK

/// Every slice the relay needs across a launch is forwarded; the configuration slice is neither written nor read.
@MainActor
final class NonPersistingConfigurationStateStoreTests: XCTestCase {

    private func wrapped() -> FakeSocketStateStore { FakeSocketStateStore() }

    private func report(_ id: String) -> PendingReport {
        PendingReport(messageId: id, sinchMessageId: "sinch-\(id)", status: .displayed, reason: "", attempts: 1,
                      deferUntilMs: nil)
    }

    // MARK: - The forwarded slices

    func testTheSeenSetTheReportedKeysAndTheCursorAreForwarded() {
        let store = wrapped()
        let subject = NonPersistingConfigurationStateStore(wrapping: store)

        XCTAssertEqual(subject.loadSeenMessageIDs(), [])
        XCTAssertEqual(subject.loadReportedKeys(), [])
        XCTAssertEqual(subject.loadLastSeenMessageID(), "")
        XCTAssertEqual(subject.loadLastSeenEnqueuedAtMs(), 0)

        subject.saveSeenMessageIDs(["m-1", "m-2"])
        subject.saveReportedKeys(["m-1:1"])
        subject.saveLastSeen(id: "m-2", enqueuedAtMs: 5_000)

        XCTAssertEqual(store.seen, ["m-1", "m-2"], "the seen set is the registry's, and must survive a launch")
        XCTAssertEqual(store.reported, ["m-1:1"])
        XCTAssertEqual(store.lastSeen, "m-2")
        XCTAssertEqual(store.lastSeenEnqueuedAt, 5_000)
        XCTAssertEqual(store.combinedLastSeenSaves.count, 1, "the combined call is forwarded, not split into two writes")
        XCTAssertEqual(store.combinedLastSeenSaves.first?.id, "m-2")
        XCTAssertEqual(store.combinedLastSeenSaves.first?.enqueuedAtMs, 5_000)
        XCTAssertEqual(subject.loadSeenMessageIDs(), ["m-1", "m-2"])
        XCTAssertEqual(subject.loadReportedKeys(), ["m-1:1"])
        XCTAssertEqual(subject.loadLastSeenMessageID(), "m-2")
        XCTAssertEqual(subject.loadLastSeenEnqueuedAtMs(), 5_000)
    }

    func testTheOutboxAndThePendingMessagesAreForwarded() {
        let store = wrapped()
        let subject = NonPersistingConfigurationStateStore(wrapping: store)
        let queued = report("m-1")
        let held = SocketMessageEvent(pooled: blankPooledMessage(messageID: "m-2"), ackToken: "ack-2", receivedAt: 42)

        XCTAssertTrue(subject.loadOutbox().isEmpty)
        XCTAssertTrue(subject.loadPendingMessages().isEmpty)

        subject.saveOutbox([queued])
        subject.savePendingMessages([held])

        XCTAssertEqual(store.outbox.map(\.messageId), ["m-1"])
        XCTAssertEqual(store.messages.map(\.id), ["m-2"])
        XCTAssertEqual(subject.loadOutbox().map(\.messageId), ["m-1"])
        XCTAssertEqual(subject.loadPendingMessages().map(\.id), ["m-2"])
    }

    // MARK: - The configuration slice

    func testSavingTheConfigurationWritesNothing() {
        let store = wrapped()
        let subject = NonPersistingConfigurationStateStore(wrapping: store)

        subject.saveConfiguration(testConfiguration().persistable)

        XCTAssertNil(store.configuration, "the relay URL and the identity must not reach the store")
        XCTAssertNil(subject.loadConfiguration())
    }

    func testACopyLeftByAnEarlierBuildIsNeitherReadNorKept() {
        let store = wrapped()
        let earlier = testConfiguration().persistable
        store.saveConfiguration(earlier)
        let subject = NonPersistingConfigurationStateStore(wrapping: store)

        XCTAssertNil(subject.loadConfiguration(), "no relaunch path in the SDK reads it, so it must not be offered")

        subject.clearConfiguration()
        XCTAssertNil(store.configuration, "the clear reaches the store, so an earlier build's copy is deleted")
        XCTAssertEqual(store.clearConfigurationCount, 1)
    }

    // MARK: - The production wiring

    /// `+Live` is not built in the test host, so the two store choices are pinned through its factory methods.
    func testTheLiveWiringHandsTheClientAStoreWithoutAConfigurationAndAnInMemoryToken() {
        let suite = "sinch.tests.relay.persistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSocketStateStore(defaults: defaults)

        let clientStore = PushSocketManager.Dependencies.clientStateStore(store)
        clientStore.saveConfiguration(testConfiguration().persistable)
        XCTAssertNil(store.loadConfiguration(), "the relay URL and the identity never reach the store")

        XCTAssertTrue(PushSocketManager.Dependencies.clientTokenStore() is InMemoryAuthTokenStore,
                      "the relay JWT is held for the process only, not in the Keychain")
    }

    /// Only the store half is asserted: the Keychain token deletion needs an entitlement the test host lacks.
    func testTheOneOffCleanUpRemovesWhatAnEarlierBuildPersisted() {
        let store = FakeSocketStateStore(configuration: testConfiguration().persistable)

        PushSocketManager.Dependencies.clearPersistedRelaySession(store: store, logger: SilentSocketLogger())

        XCTAssertNil(store.configuration)
        XCTAssertEqual(store.clearConfigurationCount, 1)
    }
}
