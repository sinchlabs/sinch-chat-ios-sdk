import XCTest
@testable import SinchChatSDK

/// Races and ownership: stop during start, who holds the "chat is running" flag, paging across reloads, and what a
/// stopped or dropped model leaves behind.
@MainActor
final class SinchConversationLifecycleTests: ConversationTestCase {

    private func cancelledError(of run: Task<Void, any Error>) async -> SinchHeadlessError? {
        guard case let .failure(error) = await run.result else { return nil }
        return error as? SinchHeadlessError
    }

    // MARK: Stop during start

    func test_stopRightAfterStart_cancelsTheRunBeforeItLoadsAnything() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        let conversation = self.conversation!
        let run = Task { try await conversation.start() }
        while conversation.phase == .idle { await Task.yield() }

        conversation.stop()

        let error = await cancelledError(of: run)
        XCTAssertEqual(error, .cancelled)
        XCTAssertEqual(conversation.phase, .idle)
        XCTAssertFalse(environment.isChatRunning)
        XCTAssertEqual(dataSource.subscribeCalls, 0)
        XCTAssertFalse(dataSource.isSubscribed())
        XCTAssertEqual(environment.didCloseChatCount, 1)
    }

    func test_stopWhileTheFirstPageLoads_leavesNothingRunning() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.holdNextHistoryCalls()
        let conversation = self.conversation!
        let run = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }

        conversation.stop()
        dataSource.releaseHistory()

        let error = await cancelledError(of: run)
        XCTAssertEqual(error, .cancelled)
        XCTAssertEqual(conversation.phase, .idle)
        XCTAssertTrue(conversation.messages.isEmpty)
        XCTAssertFalse(environment.isChatRunning)
        XCTAssertFalse(dataSource.isSubscribed())
    }

    func test_aFinishedOldRun_doesNotClearTheSharedTaskOfTheNewRun() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        let conversation = self.conversation!
        dataSource.holdNextHistoryCalls(2)
        let first = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }
        conversation.stop()
        let second = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 2 }

        dataSource.releaseHistory(1) // the old run ends first
        let firstError = await cancelledError(of: first)
        XCTAssertEqual(firstError, .cancelled)

        let third = Task { try await conversation.start() } // must join the second run, not begin a third
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(dataSource.historyCalls, 2)

        dataSource.releaseHistory()
        try await second.value
        try await third.value
        XCTAssertEqual(conversation.phase, .ready)
        XCTAssertEqual(dataSource.historyCalls, 2)
    }

    // MARK: The "chat is running" flag

    func test_start_whileAnotherConversationRuns_throwsUnavailable_andLeavesItAlone() async throws {
        try await startWithHistory([[]])
        let otherSource = FakeMessageDataSource()
        let other = Fixture.conversation(otherSource, environment: environment)

        do {
            try await other.start()
            XCTFail("expected unavailable")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .unavailable)
        }
        other.stop() // not started: must not release the flag of the running one

        XCTAssertEqual(other.phase, .idle)
        XCTAssertEqual(otherSource.subscribeCalls, 0)
        XCTAssertTrue(environment.isChatRunning)
        XCTAssertEqual(conversation.phase, .ready)
    }

    func test_stopAndStart_whileTheChatScreenIsOpen_throwsUnavailable() async throws {
        try await startWithHistory([[]])
        conversation.stop()
        environment.externalChatRunning = true // the SDK chat screen opened

        do {
            try await conversation.start()
            XCTFail("expected unavailable")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .unavailable)
        }
        XCTAssertEqual(conversation.phase, .idle)
        XCTAssertTrue(environment.externalChatRunning)

        environment.externalChatRunning = false
        try await conversation.start()
        XCTAssertEqual(conversation.phase, .ready)
    }

    func test_failedStart_givesTheFlagBack_andRetryTakesItAgain() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.failHistory(times: 1)

        do {
            try await conversation.start()
            XCTFail("expected start to throw")
        } catch {}

        guard case .failed = conversation.phase else { return XCTFail("phase \(conversation.phase)") }
        XCTAssertFalse(environment.isChatRunning, "foreground pushes and the chat screen must work again")
        XCTAssertFalse(dataSource.isSubscribed())

        try await conversation.start()
        XCTAssertTrue(environment.isChatRunning)
    }

    func test_offline_givesTheFlagBack_andReconnectTakesItAgain() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")]])

        environment.setOnline(false)
        await waitUntil { !self.environment.isChatRunning }

        environment.setOnline(true)
        await waitUntil { self.conversation.phase == .ready && self.environment.isChatRunning }
    }

    func test_background_givesTheFlagBack_andForegroundTakesItAgain() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")]])

        environment.send(.didEnterBackground)
        await waitUntil { !self.environment.isChatRunning }

        environment.send(.willEnterForeground)
        await waitUntil { self.conversation.phase == .ready && self.environment.isChatRunning }
    }

    func test_reconnect_whileAnotherChatRuns_failsAsUnavailable_withoutLoading() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")]])
        environment.setOnline(false)
        await waitUntil { !self.environment.isChatRunning }
        environment.externalChatRunning = true

        environment.setOnline(true)

        await waitUntil { self.conversation.phase == .failed(.unavailable) }
        XCTAssertEqual(dataSource.historyCalls, 1)
        XCTAssertTrue(environment.externalChatRunning)
    }

    // MARK: Dropped without stop

    func test_droppedWithoutStop_closesSubscriptionAndChannel_andGivesTheFlagBack() async throws {
        let source = FakeMessageDataSource()
        source.setPages([[Fixture.text("m1", "one")]])
        var model: SinchConversation? = Fixture.conversation(source, environment: environment)
        weak var weakModel = model
        try await model?.start()
        XCTAssertTrue(environment.isChatRunning)
        let cancelled = source.cancelSubscriptionCalls

        model = nil

        await waitUntil { !self.environment.isChatRunning }
        XCTAssertNil(weakModel)
        XCTAssertGreaterThan(source.cancelSubscriptionCalls, cancelled)
        XCTAssertFalse(source.isSubscribed())
        XCTAssertEqual(source.closeCalls, 1)
        XCTAssertEqual(environment.didCloseChatCount, 1)
    }

    // MARK: Paging across reloads

    func test_loadMoreInFlightDuringReload_isDropped_andPagingContinuesWithTheNextPage() async throws {
        try await startWithHistory([[Fixture.text("m5", "five"), Fixture.text("m6", "six")],
                                    [Fixture.text("m3", "three"), Fixture.text("m4", "four")],
                                    [Fixture.text("m1", "one"), Fixture.text("m2", "two")]])
        dataSource.holdNextHistoryCalls()
        let conversation = self.conversation!
        let more = Task { try await conversation.loadMore() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }

        environment.send(.didEnterBackground)
        await waitUntil { self.dataSource.closeCalls == 1 }
        environment.send(.willEnterForeground)
        await waitUntil { self.dataSource.historyCalls == 3 && conversation.phase == .ready }
        dataSource.releaseHistory() // the old page answers after the reload finished

        let result = await more.result
        guard case let .failure(error) = result else { return XCTFail("the stale page must not be applied") }
        XCTAssertEqual(error as? SinchHeadlessError, .cancelled)
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m5", "m6"])

        try await conversation.loadMore()
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m3", "m4", "m5", "m6"], "page 1 must not be skipped")
        XCTAssertEqual(dataSource.historyTokens, [nil, "1", nil, "1"])
    }

    // MARK: Updates

    func test_pendingSettledByTheHistory_isReportedAsRemoved() async throws {
        let slow = SinchConversation.Timing(typingTimeout: .seconds(30), typingSuppression: 0, echoGrace: .seconds(30),
                                            reconnectDelay: .milliseconds(10), foregroundDelay: .zero)
        conversation.stop()
        conversation = Fixture.conversation(dataSource, environment: environment, timing: slow)
        try await startWithHistory([[]])
        let recorder = UpdateRecorder(conversation)
        _ = try await conversation.send(text: "hello")
        let tempID = try XCTUnwrap(conversation.pending.first?.tempID)

        dataSource.setPages([[outgoingEcho(id: "srv-1", text: "hello")]])
        await reconnect()
        await waitUntil { self.conversation.phase == .ready && self.conversation.pending.isEmpty }

        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])
        await waitUntil { recorder.removedTempIDs == [tempID] }
        XCTAssertTrue(conversation.resolved.isEmpty)
    }

    func test_stop_marksUnconfirmedMessagesFailed_andTellsTheUpdatesStream() async throws {
        try await startWithHistory([[]])
        let recorder = UpdateRecorder(conversation)
        dataSource.onSend { _ in try? await Task.sleep(for: .seconds(5)) }
        let conversation = self.conversation!
        let send = Task { try await conversation.send(text: "hello") }
        await waitUntil { conversation.pending.count == 1 }

        conversation.stop()

        XCTAssertEqual(conversation.pending.first?.status, .failed)
        XCTAssertEqual(conversation.pending.first?.error, .cancelled)
        await waitUntil { recorder.isFinished }
        let updated = recorder.events.contains { if case .pendingUpdated(let item) = $0 { item.status == .failed } else { false } }
        XCTAssertTrue(updated)
        send.cancel()
    }

    func test_stopWhileASendIsInFlight_appendsNothingAfterwards() async throws {
        try await startWithHistory([[]])
        dataSource.onSend { _ in try? await Task.sleep(for: .milliseconds(100)) }
        let conversation = self.conversation!
        let send = Task { try await conversation.send(text: "hello") }
        await waitUntil { conversation.pending.count == 1 }

        conversation.stop()
        _ = try await send.value // the server accepted it after all
        try await Task.sleep(for: .milliseconds(300)) // longer than the echo grace period

        XCTAssertTrue(conversation.messages.isEmpty)
        XCTAssertTrue(conversation.pending.isEmpty)
        XCTAssertEqual(conversation.phase, .idle)
    }
}
