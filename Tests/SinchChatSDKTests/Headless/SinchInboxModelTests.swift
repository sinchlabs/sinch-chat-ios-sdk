import XCTest
@testable import SinchChatSDK

@MainActor
final class SinchInboxModelTests: XCTestCase {

    private var dataSource: FakeInboxDataSource!
    private var environment: FakeHeadlessEnvironment!
    private var model: SinchInboxModel!

    override func setUp() async throws {
        dataSource = FakeInboxDataSource()
        environment = FakeHeadlessEnvironment()
        model = SinchInboxModel(dataSource: dataSource, environment: environment,
                                timing: .init(reconnectDelay: .milliseconds(10), foregroundDelay: .zero))
    }

    override func tearDown() async throws {
        model.stop()
        model = nil
    }

    func test_start_loadsFirstPage_andReportsHasMore() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice"), Fixture.channel("b", "Bob")], [Fixture.channel("c", "Carol")]])

        try await model.start()

        XCTAssertEqual(model.chats.map(\.name), ["Alice", "Bob"])
        XCTAssertTrue(model.hasMore)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(dataSource.isSubscribed())
    }

    func test_loadMore_appendsPage_withoutDuplicates_andEndsPaging() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice"), Fixture.channel("b", "Bob")],
                             [Fixture.channel("b", "Bob"), Fixture.channel("c", "Carol")]])
        try await model.start()

        try await model.loadMore()

        XCTAssertEqual(model.chats.map(\.name), ["Alice", "Bob", "Carol"])
        XCTAssertFalse(model.hasMore)
        try await model.loadMore()
        XCTAssertEqual(dataSource.getCalls, 2)
    }

    func test_subscriptionUpdate_mergesAndMovesChatToTop_newChatGoesFirst() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice"), Fixture.channel("b", "Bob")]])
        try await model.start()

        var update = Sinch_Chat_Sdk_V1alpha2_Channel()
        update.channelID = "b"
        dataSource.emit(update) // no display name: the old one is kept, as the inbox screen does
        await waitUntil { self.model.chats.first?.name == "Bob" }
        XCTAssertEqual(model.chats.map(\.name), ["Bob", "Alice"])

        dataSource.emit(Fixture.channel("z", "Zed"))
        await waitUntil { self.model.chats.count == 3 }
        XCTAssertEqual(model.chats.map(\.name), ["Zed", "Bob", "Alice"])
    }

    func test_refresh_replacesTheList() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        try await model.start()
        dataSource.setPages([[Fixture.channel("x", "Xena")]])

        try await model.refresh()

        XCTAssertEqual(model.chats.map(\.name), ["Xena"])
    }

    func test_start_isIdempotent_andRefreshBeforeStartThrows() async throws {
        do {
            try await model.refresh()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .notStarted)
        }
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        try await model.start()
        try await model.start()
        XCTAssertEqual(dataSource.getCalls, 1)
    }

    func test_reconnect_reloadsFirstPage() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        try await model.start()

        environment.setOnline(false)
        await waitUntil { !self.model.isOnline }
        environment.setOnline(true)

        await waitUntil { self.dataSource.getCalls == 2 && !self.model.isLoading }
        XCTAssertEqual(model.chats.map(\.name), ["Alice"])
    }

    func test_stop_cancelsSubscription() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        try await model.start()
        let before = dataSource.cancelSubscriptionCalls

        model.stop()

        XCTAssertGreaterThan(dataSource.cancelSubscriptionCalls, before)
        XCTAssertFalse(dataSource.isSubscribed())
    }

    func test_loadMoreInFlightDuringRefresh_isDropped_andPagingContinuesWithTheNextPage() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")], [Fixture.channel("b", "Bob")], [Fixture.channel("c", "Carol")]])
        try await model.start()
        dataSource.holdNextCalls()
        let model = self.model!
        let more = Task { try await model.loadMore() }
        await waitUntil { self.dataSource.heldCalls == 1 }

        try await model.refresh() // resets the paging while the old page is still on its way
        dataSource.release()

        guard case let .failure(error) = await more.result else { return XCTFail("the stale page must not be applied") }
        XCTAssertEqual(error as? SinchHeadlessError, .cancelled)
        XCTAssertEqual(model.chats.map(\.name), ["Alice"])
        try await model.loadMore()
        XCTAssertEqual(model.chats.map(\.name), ["Alice", "Bob"], "page 1 must not be skipped")
    }

    func test_start_whileTheFirstLoadRuns_waitsForIt() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        dataSource.holdNextCalls()
        let model = self.model!
        let first = Task { try await model.start() }
        await waitUntil { self.dataSource.heldCalls == 1 }
        var secondDone = false
        let second = Task {
            try await model.start()
            secondDone = true
        }
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(secondDone, "must not return before the first page is there")

        dataSource.release()
        try await first.value
        try await second.value
        XCTAssertEqual(model.chats.map(\.name), ["Alice"])
        XCTAssertEqual(dataSource.getCalls, 1)
    }

    func test_reloadFailure_isExposedAsLastError_andClearedByTheNextSuccess() async throws {
        dataSource.setPages([[Fixture.channel("a", "Alice")]])
        try await model.start()
        XCTAssertNil(model.lastError)

        dataSource.failNextCalls()
        environment.setOnline(false)
        await waitUntil { !self.model.isOnline }
        environment.setOnline(true)
        await waitUntil { self.model.lastError != nil }

        try await model.refresh()
        XCTAssertNil(model.lastError)
    }
}
