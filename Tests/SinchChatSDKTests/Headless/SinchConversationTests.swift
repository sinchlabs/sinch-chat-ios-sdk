import XCTest
@testable import SinchChatSDK

/// Start, history, live messages, connectivity, stop and the content projection.
@MainActor
final class SinchConversationTests: ConversationTestCase {

    // MARK: Start

    func test_start_loadsFirstPageAndSubscribes() async throws {
        try await startWithHistory([[Fixture.text("m1", "one"), Fixture.text("m2", "two")], [Fixture.text("m0", "zero")]])

        XCTAssertEqual(conversation.phase, .ready)
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1", "m2"])
        XCTAssertTrue(conversation.hasMoreHistory)
        XCTAssertFalse(conversation.isLoadingHistory)
        XCTAssertEqual(dataSource.subscribeCalls, 1)
        XCTAssertEqual(dataSource.historyCalls, 1)
        XCTAssertTrue(environment.isChatRunning)
    }

    func test_start_isIdempotent() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        let conversation = self.conversation!
        async let first: Void = conversation.start()
        async let second: Void = conversation.start()
        _ = try await (first, second)
        try await conversation.start()

        XCTAssertEqual(dataSource.subscribeCalls, 1)
        XCTAssertEqual(dataSource.historyCalls, 1)
        XCTAssertEqual(conversation.messages.count, 1)
    }

    func test_start_failure_setsFailedPhase_andCanBeRetried() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.failHistory(times: 1)

        do {
            try await conversation.start()
            XCTFail("expected start to throw")
        } catch {
            guard case .underlying = error as? SinchHeadlessError else { return XCTFail("\(error)") }
        }
        guard case .failed = conversation.phase else { return XCTFail("phase \(conversation.phase)") }

        try await conversation.start()
        XCTAssertEqual(conversation.phase, .ready)
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1"])
    }

    func test_start_dropsEventsAndDateSeparators() async throws {
        let compose = Message(entryId: "e1", owner: .system, body: MessageEvent(type: .composeEnd))
        let date = Message(entryId: "-1", owner: .system, body: MessageDate(sendDate: 1))
        try await startWithHistory([[compose, date, Fixture.text("m1", "one")]])
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1"])
    }

    // MARK: History

    func test_loadMore_prependsOlderPage_andUpdatesHasMore() async throws {
        try await startWithHistory([[Fixture.text("m3", "three"), Fixture.text("m4", "four")],
                                    [Fixture.text("m1", "one"), Fixture.text("m2", "two")]])
        XCTAssertTrue(conversation.hasMoreHistory)

        try await conversation.loadMore()

        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1", "m2", "m3", "m4"])
        XCTAssertFalse(conversation.hasMoreHistory)
        XCTAssertEqual(dataSource.historyTokens, [nil, "1"])

        try await conversation.loadMore() // no more pages: a no-op, not an error
        XCTAssertEqual(dataSource.historyCalls, 2)
    }

    func test_loadMore_beforeStart_throws() async {
        do {
            try await conversation.loadMore()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .notStarted)
        }
    }

    // MARK: Live messages, typing

    func test_incomingMessage_isAppended_andPublishedOnEveryUpdatesStream() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")]])
        let first = conversation.updates
        let second = conversation.updates

        dataSource.emit(Fixture.text("m2", "two"))
        dataSource.emit(Fixture.text("m2", "two")) // the same entry again is ignored

        await waitUntil { self.conversation.messages.count == 2 }
        for stream in [first, second] {
            var iterator = stream.makeAsyncIterator()
            guard case let .appended(message)? = await iterator.next() else { return XCTFail("expected appended") }
            XCTAssertEqual(message.entryId, "m2")
        }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1", "m2"])
    }

    /// What a subscriber that drained its buffer is left with: the resets in it, and for the last one the number of
    /// messages it carries plus the events that follow it (which apply on top of it). Their sum is the message count.
    private func rebuiltCount(_ events: [SinchConversationUpdate]) -> (resets: Int, total: Int?) {
        var resets = 0
        var total: Int?
        for event in events {
            switch event {
            case let .reset(messages):
                resets += 1
                total = messages.count
            case .appended:
                total = total.map { $0 + 1 }
            default:
                break
            }
        }
        return (resets, total)
    }

    private func drain(_ stream: AsyncStream<SinchConversationUpdate>, count: Int = 256) async -> [SinchConversationUpdate] {
        var iterator = stream.makeAsyncIterator()
        var events: [SinchConversationUpdate] = []
        for _ in 0..<count {
            guard let event = await iterator.next() else { break }
            events.append(event)
        }
        return events
    }

    func test_updatesStream_thatFallsBehind_getsOneResetWithTheMessagesAtThatPoint_notOnePerEvent() async throws {
        try await startWithHistory([[]])
        let stream = conversation.updates // nobody reads it while the messages arrive

        for index in 0..<300 { dataSource.emit(Fixture.text("m\(index)", "text \(index)")) }
        await waitUntil(timeout: 5) { self.conversation.messages.count == 300 }

        let events = await drain(stream)
        let (resets, total) = rebuiltCount(events)
        XCTAssertEqual(resets, 1, "one reset for the overflow, not one per event after it")
        XCTAssertEqual(total, 300, "the reset plus the events behind it add up to the current messages")
    }

    func test_updatesStream_thatFallsBehindAgainAfterDraining_getsAnotherReset() async throws {
        try await startWithHistory([[]])
        let stream = conversation.updates
        for index in 0..<300 { dataSource.emit(Fixture.text("a\(index)", "text \(index)")) }
        await waitUntil(timeout: 5) { self.conversation.messages.count == 300 }
        var iterator = stream.makeAsyncIterator()
        var first: [SinchConversationUpdate] = []
        for _ in 0..<256 { if let event = await iterator.next() { first.append(event) } } // drained
        XCTAssertEqual(rebuiltCount(first).resets, 1)

        for index in 0..<300 { dataSource.emit(Fixture.text("b\(index)", "text \(index)")) }
        await waitUntil(timeout: 5) { self.conversation.messages.count == 600 }
        var second: [SinchConversationUpdate] = []
        for _ in 0..<256 { if let event = await iterator.next() { second.append(event) } }

        let (resets, total) = rebuiltCount(second)
        XCTAssertEqual(resets, 1)
        XCTAssertEqual(total, 600)
    }

    func test_updatesStream_thatNeverReads_keepsAResetInItsBuffer_whateverHappens() async throws {
        try await startWithHistory([[]])
        let stream = conversation.updates

        for index in 0..<1000 { dataSource.emit(Fixture.text("m\(index)", "text \(index)")) }
        await waitUntil(timeout: 10) { self.conversation.messages.count == 1000 }

        let events = await drain(stream)
        let (resets, total) = rebuiltCount(events)
        // The queued reset itself would be dropped after a buffer's worth of events, so another one follows: a few,
        // not one per event.
        XCTAssertGreaterThanOrEqual(resets, 1)
        XCTAssertLessThanOrEqual(resets, 4)
        XCTAssertEqual(total, 1000)
    }

    func test_typingIndicator_followsComposeEvents_andExpires() async throws {
        try await startWithHistory([[]])
        let started = Message(entryId: "c1", owner: .system, body: MessageEvent(type: .composeStarted))
        let ended = Message(entryId: "c2", owner: .system, body: MessageEvent(type: .composeEnd))

        dataSource.emit(started)
        await waitUntil { self.conversation.isAgentTyping }
        dataSource.emit(ended)
        await waitUntil { !self.conversation.isAgentTyping }

        dataSource.emit(started)
        await waitUntil { self.conversation.isAgentTyping }
        await waitUntil(timeout: 2) { !self.conversation.isAgentTyping } // typingTimeout is 150 ms in tests

        dataSource.emit(started)
        await waitUntil { self.conversation.isAgentTyping }
        dataSource.emit(Fixture.text("m1", "hi"))
        await waitUntil { !self.conversation.isAgentTyping }
        XCTAssertTrue(conversation.messages.contains { $0.entryId == "m1" })
    }

    // MARK: Connectivity and lifecycle

    func test_offline_blocksSend_andReconnectReloadsFirstPage() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")]])
        XCTAssertEqual(dataSource.historyCalls, 1)

        // The monitor's first answer repeats the state the model started with: it must not reload.
        environment.setOnline(true)
        await waitUntil { self.environment.posted.contains { if case .didChangeInternetState(true) = $0 { true } else { false } } }
        XCTAssertEqual(dataSource.historyCalls, 1)
        XCTAssertEqual(dataSource.subscribeCalls, 1)

        environment.setOnline(false)
        await waitUntil { !self.conversation.isOnline }
        do {
            _ = try await conversation.send(text: "hello")
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .offline)
        }
        XCTAssertTrue(conversation.pending.isEmpty)

        environment.setOnline(true)
        await waitUntil { self.dataSource.historyCalls == 2 && self.conversation.phase == .ready }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1"])
        XCTAssertEqual(dataSource.subscribeCalls, 2)
        XCTAssertTrue(environment.posted.contains { if case .didChangeInternetState(false) = $0 { true } else { false } })
    }

    func test_backgroundClosesChannel_foregroundReopensAndReloads() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")]])

        environment.send(.didEnterBackground)
        await waitUntil { self.dataSource.closeCalls == 1 }

        environment.send(.willEnterForeground)
        await waitUntil { self.dataSource.startChannelCalls == 1 && self.dataSource.historyCalls == 2 }
        await waitUntil { self.conversation.phase == .ready }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1"])
    }

    func test_liveMessageDuringReload_isBufferedThenApplied_withoutDuplicates() async throws {
        let first = Fixture.text("m1", "one")
        let second = Fixture.text("m2", "two")
        try await startWithHistory([[first, second]])

        environment.send(.didEnterBackground)
        await waitUntil { self.dataSource.closeCalls == 1 }
        dataSource.holdNextHistoryCalls()
        environment.send(.willEnterForeground)
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }
        XCTAssertEqual(conversation.phase, .connecting)

        // The first page is still loading: what arrives now waits, and the list is not touched.
        dataSource.emit(Fixture.text("m3", "three"))
        dataSource.emit(second) // the page contains it too
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1", "m2"])

        dataSource.releaseHistory()
        await waitUntil { self.conversation.phase == .ready }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1", "m2", "m3"])
    }

    func test_subscriptionDropped_resubscribes() async throws {
        try await startWithHistory([[]])
        conversation.subscriptionError()
        await waitUntil { self.dataSource.subscribeCalls == 2 }
    }

    // MARK: Stop

    func test_stop_closesChannel_postsDidCloseChat_andCanRestart() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")]])

        conversation.stop()
        conversation.stop() // idempotent

        XCTAssertEqual(conversation.phase, .idle)
        XCTAssertEqual(dataSource.closeCalls, 1)
        XCTAssertEqual(environment.didCloseChatCount, 1)
        XCTAssertFalse(environment.isChatRunning)
        XCTAssertEqual(conversation.messages.count, 1, "messages stay readable")

        dataSource.setPages([[Fixture.text("m1", "one"), Fixture.text("m2", "two")]])
        try await conversation.start()
        XCTAssertEqual(dataSource.startChannelCalls, 1, "reopens the channel it closed")
        XCTAssertEqual(conversation.messages.count, 2)
    }

    func test_stop_whenStartedFromInbox_keepsSharedChannelOpen() async throws {
        conversation = Fixture.conversation(dataSource, environment: environment, isStartedFromInbox: true)
        try await startWithHistory([[]])
        conversation.stop()
        XCTAssertEqual(dataSource.closeCalls, 0)
        XCTAssertEqual(environment.didCloseChatCount, 1)
    }

    func test_stop_endsOpenUpdateStreams() async throws {
        try await startWithHistory([[]])
        let recorder = UpdateRecorder(conversation)

        conversation.stop()

        await waitUntil { recorder.isFinished }
    }

    // MARK: Content projection

    func test_content_projectsInternalBodies() {
        let choices = MessageChoices(text: "Pick", choices: [
            .textMessage(ChoiceText(text: "Yes", postback: "y", entryID: "m1")),
            .urlMessage(ChoiceUrl(url: "https://example.com", text: "Site"))
        ])
        let message = Message(entryId: "m1", owner: .incoming(nil), body: choices)
        guard case let .choices(text, items) = message.content else { return XCTFail("expected choices") }
        XCTAssertEqual(text, "Pick")
        XCTAssertEqual(items, [.reply(text: "Yes", postback: "y", messageID: "m1"),
                               .url(text: "Site", url: "https://example.com")])
        guard case .text("hi") = Fixture.text("m2", "hi").content else { return XCTFail("expected text") }
    }

    func test_content_projectsMediaTextAndEventTexts() {
        let mediaText = Message(entryId: "m1", owner: .incoming(nil),
                                body: MessageMediaText(text: "Look", url: "https://files.example/a.png"))
        guard case let .mediaText(text, url) = mediaText.content else { return XCTFail("expected mediaText") }
        XCTAssertEqual(text, "Look")
        XCTAssertEqual(url, "https://files.example/a.png")

        let fallback = Message(entryId: "m2", owner: .system, body: MessageEvent(type: .fallbackMessage(payload: "raw payload")))
        guard case .event("raw payload") = fallback.content else { return XCTFail("expected the fallback payload") }
        let custom = Message(entryId: "m3", owner: .system, body: MessageEvent(type: .customText(text: "Hello")))
        guard case .event("Hello") = custom.content else { return XCTFail("expected the custom text") }
    }
}
