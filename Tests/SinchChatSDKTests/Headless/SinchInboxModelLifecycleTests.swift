import XCTest
@testable import SinchChatSDK

/// Dropping, abandoning and refreshing the inbox model while it loads.
@MainActor
final class SinchInboxModelLifecycleTests: XCTestCase {

    private var dataSource: FakeInboxDataSource!
    private var environment: FakeHeadlessEnvironment!
    private let timing = SinchInboxModel.Timing(reconnectDelay: .milliseconds(10), foregroundDelay: .zero)

    override func setUp() async throws {
        dataSource = FakeInboxDataSource()
        environment = FakeHeadlessEnvironment()
    }

    func test_droppedWithoutStop_endsTheDataSourceSubscription() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        var model: SinchInboxModel? = SinchInboxModel(dataSource: dataSource, environment: environment, timing: timing)
        weak var weakModel = model
        try await model?.start()
        XCTAssertTrue(dataSource.isSubscribed())
        let cancelled = dataSource.cancelSubscriptionCalls

        model = nil

        await waitUntil { !self.dataSource.isSubscribed() }
        XCTAssertNil(weakModel)
        XCTAssertGreaterThan(dataSource.cancelSubscriptionCalls, cancelled)
    }

    func test_droppedAfterStop_doesNotCancelAgain() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        var model: SinchInboxModel? = SinchInboxModel(dataSource: dataSource, environment: environment, timing: timing)
        try await model?.start()
        model?.stop()
        let cancelled = dataSource.cancelSubscriptionCalls

        model = nil
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(dataSource.cancelSubscriptionCalls, cancelled)
    }

    func test_refresh_whileStartLoads_waitsForTheFirstLoad_insteadOfCancellingIt() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        dataSource.holdNextCalls()
        let model = SinchInboxModel(dataSource: dataSource, environment: environment, timing: timing)
        let start = Task { try await model.start() }
        await waitUntil { self.dataSource.heldCalls == 1 }
        let refresh = Task { try await model.refresh() }
        try await Task.sleep(for: .milliseconds(30))

        dataSource.release()

        try await start.value
        try await refresh.value
        XCTAssertEqual(model.chats.map(\.name), ["Alice"])
        XCTAssertEqual(dataSource.getCalls, 1, "the first load was the refresh")
        model.stop()
    }

    func test_cancellingTheCaller_whileTheFirstLoadRuns_abandonsTheStart() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        dataSource.holdNextCalls()
        let model = SinchInboxModel(dataSource: dataSource, environment: environment, timing: timing)
        let start = Task { try await model.start() }
        await waitUntil { self.dataSource.heldCalls == 1 }

        start.cancel()
        dataSource.release()

        guard case let .failure(error) = await start.result else { return XCTFail("start must not complete") }
        XCTAssertEqual(error as? SinchHeadlessError, .cancelled)
        XCTAssertFalse(dataSource.isSubscribed())
        XCTAssertTrue(model.chats.isEmpty)
        do {
            try await model.refresh()
            XCTFail("expected notStarted")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .notStarted)
        }
    }

    // MARK: Joiners

    func test_aStartThatJoinsTheRun_andIsCancelled_stopsWaiting_withoutStoppingTheRun() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        dataSource.holdNextCalls()
        let model = SinchInboxModel(dataSource: dataSource, environment: environment, timing: timing)
        let first = Task { try await model.start() }
        await waitUntil { self.dataSource.heldCalls == 1 }
        let joiner = Task { try await model.start() }
        try await Task.sleep(for: .milliseconds(30))

        joiner.cancel()

        // The page is still held: the joiner did not wait for it.
        guard case let .failure(error) = await joiner.result else { return XCTFail("the joiner must not complete") }
        XCTAssertEqual(error as? SinchHeadlessError, .cancelled)
        dataSource.release()
        try await first.value
        XCTAssertEqual(model.chats.map(\.name), ["Alice"])
        XCTAssertTrue(dataSource.isSubscribed())
        model.stop()
    }

    func test_aRefreshThatJoinsTheFirstLoad_andIsCancelled_stopsWaiting_withoutStoppingTheStart() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        dataSource.holdNextCalls()
        let model = SinchInboxModel(dataSource: dataSource, environment: environment, timing: timing)
        let start = Task { try await model.start() }
        await waitUntil { self.dataSource.heldCalls == 1 }
        let refresh = Task { try await model.refresh() }
        try await Task.sleep(for: .milliseconds(30))

        refresh.cancel()

        guard case let .failure(error) = await refresh.result else { return XCTFail("the refresh must not complete") }
        XCTAssertEqual(error as? SinchHeadlessError, .cancelled)
        dataSource.release()
        try await start.value
        XCTAssertEqual(model.chats.map(\.name), ["Alice"])
        model.stop()
    }

    // MARK: The connection goes away under the first page

    func test_offlineWhileTheFirstPageLoads_failsStartAsOffline_andStopsTheModel() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        dataSource.holdNextCalls()
        let model = SinchInboxModel(dataSource: dataSource, environment: environment, timing: timing)
        let start = Task { try await model.start() }
        await waitUntil { self.dataSource.heldCalls == 1 }

        environment.setOnline(false)
        await waitUntil { !model.isOnline }
        dataSource.release()

        guard case let .failure(error) = await start.result else { return XCTFail("start must not complete") }
        XCTAssertEqual(error as? SinchHeadlessError, .offline)
        XCTAssertEqual(model.lastError, .offline)
        XCTAssertFalse(dataSource.isSubscribed())
        do {
            try await model.refresh()
            XCTFail("a failed first load stops the model")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .notStarted)
        }

        // Calling start() again retries. (The stopped model no longer watches the network; a started one gets the
        // current state from the environment first.)
        try await model.start()
        XCTAssertEqual(model.chats.map(\.name), ["Alice"])
        XCTAssertNil(model.lastError)
        model.stop()
    }

    // MARK: The chat options

    func test_willStart_runsWhenTheModelStarts_notWhenItIsCreated() async throws {
        dataSource.setPages([[]])
        final class Counter { var value = 0 }
        let counter = Counter()
        let model = SinchInboxModel(dataSource: dataSource, environment: environment, timing: timing,
                                    willStart: { counter.value += 1 })
        XCTAssertEqual(counter.value, 0)

        try await model.start()
        try await model.start() // started already
        XCTAssertEqual(counter.value, 1)
        model.stop()
    }
}
