import XCTest
@testable import SinchChatSDK

/// What a dropped, stopped or abandoned conversation leaves behind: the started teardown, the typing chain, a caller
/// that gives up, a retry while the failed call still runs.
@MainActor
final class SinchConversationTeardownTests: ConversationTestCase {

    private func cancelledError(of run: Task<Void, any Error>) async -> SinchHeadlessError? {
        guard case let .failure(error) = await run.result else { return nil }
        return error as? SinchHeadlessError
    }

    // MARK: Dropped without stop, in states that gave the claim back

    func test_droppedWhileOffline_stillClosesTheChannel_andPostsDidCloseChat() async throws {
        let source = FakeMessageDataSource()
        source.setPages([[Fixture.text("m1", "one")]])
        var model: SinchConversation? = Fixture.conversation(source, environment: environment)
        weak var weakModel = model
        try await model?.start()
        environment.setOnline(false)
        await waitUntil { !self.environment.isChatRunning }
        XCTAssertEqual(source.closeCalls, 0)
        let cancelled = source.cancelSubscriptionCalls

        model = nil

        await waitUntil { source.closeCalls == 1 && self.environment.didCloseChatCount == 1 }
        XCTAssertNil(weakModel)
        XCTAssertGreaterThan(source.cancelSubscriptionCalls, cancelled)
        XCTAssertFalse(environment.isChatRunning)
    }

    func test_droppedWhileFailed_stillClosesTheChannel_andPostsDidCloseChat() async throws {
        let source = FakeMessageDataSource()
        source.setPages([[Fixture.text("m1", "one")]])
        source.failHistory(times: 1)
        var model: SinchConversation? = Fixture.conversation(source, environment: environment)
        weak var weakModel = model
        _ = try? await model?.start()
        guard case .failed = model?.phase else { return XCTFail("phase \(String(describing: model?.phase))") }
        XCTAssertFalse(environment.isChatRunning)
        XCTAssertEqual(source.closeCalls, 0)

        model = nil

        await waitUntil { source.closeCalls == 1 && self.environment.didCloseChatCount == 1 }
        XCTAssertNil(weakModel)
    }

    func test_droppedAfterStop_doesNotCloseOrPostAgain() async throws {
        let source = FakeMessageDataSource()
        source.setPages([[Fixture.text("m1", "one")]])
        var model: SinchConversation? = Fixture.conversation(source, environment: environment)
        try await model?.start()
        model?.stop()
        XCTAssertEqual(source.closeCalls, 1)
        XCTAssertEqual(environment.didCloseChatCount, 1)

        model = nil
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(source.closeCalls, 1)
        XCTAssertEqual(environment.didCloseChatCount, 1)
    }

    // MARK: Typing chain

    func test_stop_dropsEveryQueuedTypingLink_notOnlyTheLast() async throws {
        try await startWithHistory([[]])
        dataSource.onEvent { event in
            if case .composeStarted = event { try? await Task.sleep(for: .milliseconds(100)) }
        }

        conversation.sendTyping(true)
        conversation.sendTyping(false)
        conversation.sendTyping(true)
        conversation.stop()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(dataSource.events.isEmpty, "typing sent after stop(): \(dataSource.events)")
    }

    // MARK: First page and the caller

    func test_stopWhileTheFirstPageLoadsAndFails_throwsCancelled_notTheLoadError() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.failHistory(times: 1)
        dataSource.holdNextHistoryCalls()
        let conversation = self.conversation!
        let run = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }

        conversation.stop()
        dataSource.releaseHistory()

        let error = await cancelledError(of: run)
        XCTAssertEqual(error, .cancelled)
        XCTAssertEqual(conversation.phase, .idle)
    }

    func test_cancellingTheCaller_whileTheFirstPageLoads_abandonsTheStart() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.holdNextHistoryCalls()
        let conversation = self.conversation!
        let run = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }

        run.cancel()
        dataSource.releaseHistory()

        let error = await cancelledError(of: run)
        XCTAssertEqual(error, .cancelled)
        XCTAssertEqual(conversation.phase, .idle)
        XCTAssertFalse(environment.isChatRunning)
        XCTAssertFalse(dataSource.isSubscribed())
        XCTAssertEqual(environment.didCloseChatCount, 1)
        XCTAssertTrue(conversation.messages.isEmpty)
    }

    func test_aCancelledOldStart_doesNotStopTheNewRun() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.holdNextHistoryCalls(2)
        let conversation = self.conversation!
        let first = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }
        conversation.stop()
        let second = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 2 }

        first.cancel() // its run was cancelled by stop() already; this must not reach the new run
        dataSource.releaseHistory()

        _ = await first.result
        try await second.value
        XCTAssertEqual(conversation.phase, .ready)
        XCTAssertTrue(environment.isChatRunning)
    }

    // MARK: Retry while the failed call runs

    func test_retry_whileTheCallThatWasStoppedIsStillInFlight_throws() async throws {
        try await startWithHistory([[]])
        dataSource.onSend { _ in try? await Task.sleep(for: .milliseconds(300)) }
        let conversation = self.conversation!
        let send = Task { try await conversation.send(text: "hello") }
        await waitUntil { self.dataSource.sent.count == 1 }

        conversation.stop()
        try await conversation.start() // the first call is still running
        let tempID = try XCTUnwrap(conversation.pending.first?.tempID)
        XCTAssertEqual(conversation.pending.first?.status, .failed)

        do {
            _ = try await conversation.retry(tempID)
            XCTFail("expected unknownPendingMessage")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .unknownPendingMessage)
        }
        XCTAssertEqual(dataSource.sent.count, 1, "the message must not be sent a second time")
        _ = try? await send.value
    }

    // MARK: A send that was in flight at stop(), and the history after the restart

    private var nowSeconds: Int64 { Int64(Date().timeIntervalSince1970) }

    /// A send that went out and got no answer before `stop()`, with the transport call still running.
    private func stopWithASendInFlight(_ text: String) async throws -> Task<Void, Never> {
        try await startWithHistory([[]])
        dataSource.onSend { _ in try? await Task.sleep(for: .milliseconds(400)) }
        let conversation = self.conversation!
        let send = Task { _ = try? await conversation.send(text: text) }
        await waitUntil { self.dataSource.sent.count == 1 }
        conversation.stop()
        XCTAssertEqual(conversation.pending.first?.status, .failed)
        return send
    }

    func test_restart_settlesAFailedMessage_thatTheHistoryNowContains() async throws {
        let send = try await stopWithASendInFlight("hello")
        dataSource.setPages([[outgoingEcho(id: "srv-1", text: "hello", date: nowSeconds)]])

        try await conversation.start()

        XCTAssertTrue(conversation.pending.isEmpty, "the server has the message: nothing is left to retry")
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])
        XCTAssertEqual(dataSource.sent.count, 1, "the message was not sent again")
        await send.value
    }

    func test_restart_keepsAFailedMessage_whenTheHistoryOnlyHasAnOlderMessageWithTheSameText() async throws {
        let send = try await stopWithASendInFlight("hello")
        // An old "hello" from long before the failed message was written: not its delivery.
        dataSource.setPages([[outgoingEcho(id: "old", text: "hello", date: nowSeconds - 3600)]])

        try await conversation.start()

        XCTAssertEqual(conversation.pending.map(\.status), [.failed])
        XCTAssertEqual(conversation.messages.map(\.entryId), ["old"])
        await send.value
    }

    func test_restart_keepsAFailedMessage_whenTheOnlyMatchIsAnEarlierIdenticalMessageThatWasSentAndListed() async throws {
        try await startWithHistory([[]])
        // "ok" goes through; a minute later the second "ok" is dispatched and fails without an answer.
        dataSource.queueSendResults([.success("srv-1"),
                                     .failure(.unknown(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))])
        _ = try await conversation.send(text: "ok")
        await waitUntil { self.conversation.pending.isEmpty }
        _ = try? await conversation.send(text: "ok")
        XCTAssertEqual(conversation.pending.map(\.status), [.failed])
        // The reload lists the first "ok" under its server id, 60 s before the failed one.
        dataSource.setPages([[outgoingEcho(id: "srv-1", text: "ok", date: nowSeconds - 60)]])

        await reconnect()
        await waitUntil { self.conversation.phase == .ready }

        XCTAssertEqual(conversation.pending.map(\.status), [.failed], "the earlier \"ok\" is not its delivery: Retry stays")
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])
    }

    func test_restart_settlesAFailedMessage_thatTheHistoryHasJustInsideTheWindow() async throws {
        let send = try await stopWithASendInFlight("hello")
        // Another clock, 100 s ahead: still within the slack (120 s) after the failure.
        dataSource.setPages([[outgoingEcho(id: "srv-1", text: "hello", date: nowSeconds + 100)]])

        try await conversation.start()

        XCTAssertTrue(conversation.pending.isEmpty)
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])
        await send.value
    }

    func test_restart_keepsAFailedMessage_whenTheHistoryTextIsSentLongAfterTheFailure() async throws {
        let send = try await stopWithASendInFlight("hello")
        // The same text from another device, five minutes after the failure: not the failed message.
        dataSource.setPages([[outgoingEcho(id: "other-device", text: "hello", date: nowSeconds + 300)]])

        try await conversation.start()

        XCTAssertEqual(conversation.pending.map(\.status), [.failed])
        XCTAssertEqual(conversation.messages.map(\.entryId), ["other-device"])
        await send.value
    }

    func test_restart_keepsAFailedMessage_thatNeverWentOut() async throws {
        try await startWithHistory([[]])
        dataSource.queueSendResults([.failure(.noInternetConnection)])
        _ = try? await conversation.send(text: "hello")
        XCTAssertEqual(conversation.pending.map(\.status), [.failed])
        conversation.stop()
        dataSource.setPages([[outgoingEcho(id: "srv-1", text: "hello", date: nowSeconds)]])

        try await conversation.start()

        XCTAssertEqual(conversation.pending.map(\.status), [.failed], "it failed before the network: this is another message")
    }

    // MARK: Delivery classification

    func test_mayHaveReachedServer_separatesBeforeTheNetworkFromAfterDispatch() {
        XCTAssertFalse(MessageDataSourceError.notLoggedIn.mayHaveReachedServer)
        XCTAssertFalse(MessageDataSourceError.noInternetConnection.mayHaveReachedServer)
        XCTAssertFalse(MessageDataSourceError.unknownTypeOfMessage.mayHaveReachedServer)
        XCTAssertTrue(MessageDataSourceError.unknown(CancellationError()).mayHaveReachedServer)
        XCTAssertTrue(MessageDataSourceError.unknown(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
            .mayHaveReachedServer)
    }
}
