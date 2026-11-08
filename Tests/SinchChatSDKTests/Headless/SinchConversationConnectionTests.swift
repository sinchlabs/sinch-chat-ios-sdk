import XCTest
@testable import SinchChatSDK

/// The connection of a started conversation: callers that join a run, the connection going away under the first page,
/// what `phase` says while the model waits for the network, and what is allowed outside `.ready`.
@MainActor
final class SinchConversationConnectionTests: ConversationTestCase {

    private func failure(of run: Task<Void, any Error>) async -> SinchHeadlessError? {
        guard case let .failure(error) = await run.result else { return nil }
        return error as? SinchHeadlessError
    }

    private final class Counter {
        var value = 0
    }

    // MARK: Joining a run in progress

    func test_aCallerThatJoinsARun_andIsCancelled_stopsWaiting_withoutStoppingTheRun() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.holdNextHistoryCalls()
        let conversation = self.conversation!
        let first = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }
        let joiner = Task { try await conversation.start() }
        try await Task.sleep(for: .milliseconds(30))

        joiner.cancel()

        // The first page is still held: the joiner returned without waiting for it.
        let error = await failure(of: joiner)
        XCTAssertEqual(error, .cancelled)
        XCTAssertEqual(conversation.phase, .connecting)
        XCTAssertTrue(environment.isChatRunning, "the run was not touched")
        dataSource.releaseHistory()
        try await first.value
        XCTAssertEqual(conversation.phase, .ready)
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1"])
    }

    func test_aCallerThatJoinsARun_whileAlreadyCancelled_throwsCancelledAtOnce() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.holdNextHistoryCalls()
        let conversation = self.conversation!
        let first = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }
        let joiner = Task {
            while !Task.isCancelled { await Task.yield() }
            try await conversation.start()
        }

        joiner.cancel()

        let error = await failure(of: joiner)
        XCTAssertEqual(error, .cancelled)
        dataSource.releaseHistory()
        try await first.value
        XCTAssertEqual(conversation.phase, .ready)
    }

    func test_aJoiner_getsTheResultOfTheRun() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.failHistory(times: 1)
        dataSource.holdNextHistoryCalls()
        let conversation = self.conversation!
        let first = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }
        let joiner = Task { try await conversation.start() }
        try await Task.sleep(for: .milliseconds(30))

        dataSource.releaseHistory()

        let firstError = await failure(of: first)
        let joinerError = await failure(of: joiner)
        guard case .underlying? = firstError else { return XCTFail("expected the load error, got \(String(describing: firstError))") }
        XCTAssertEqual(joinerError, firstError)
    }

    // MARK: The connection goes away under the first page

    func test_offlineWhileTheFirstPageLoads_failsStartAsOffline_andTheReconnectRecovers() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.holdNextHistoryCalls()
        let conversation = self.conversation!
        let run = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }

        environment.setOnline(false)
        await waitUntil { !conversation.isOnline }
        dataSource.releaseHistory()

        let error = await failure(of: run)
        XCTAssertEqual(error, .offline)
        XCTAssertEqual(conversation.phase, .failed(.offline))
        XCTAssertFalse(environment.isChatRunning, "the flag is back, as for any failed load")

        environment.setOnline(true)
        await waitUntil { conversation.phase == .ready }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1"])
        XCTAssertTrue(environment.isChatRunning)
    }

    func test_backgroundWhileTheFirstPageLoads_failsStartAsOffline_andTheForegroundRecovers() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.holdNextHistoryCalls()
        let conversation = self.conversation!
        let run = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }

        environment.send(.didEnterBackground)
        await waitUntil { self.dataSource.closeCalls == 1 }
        dataSource.releaseHistory()

        let error = await failure(of: run)
        XCTAssertEqual(error, .offline)
        XCTAssertEqual(conversation.phase, .failed(.offline))
        XCTAssertFalse(environment.isChatRunning)

        environment.send(.willEnterForeground)
        await waitUntil { conversation.phase == .ready }
        XCTAssertTrue(environment.isChatRunning)
    }

    func test_offlineThenOnline_beforeTheInterruptedFirstPageEnds_stillFailsStartAsOffline() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.holdNextHistoryCalls() // only the first request is held; the reload after the reconnect is not
        let conversation = self.conversation!
        let run = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }

        environment.setOnline(false)
        await waitUntil { !conversation.isOnline }
        environment.setOnline(true)
        // The reload that the reconnect started finishes first; then the interrupted first page ends.
        await waitUntil { conversation.phase == .ready }
        dataSource.releaseHistory()

        let error = await failure(of: run)
        XCTAssertEqual(error, .offline, "nobody stopped or cancelled the start: the connection interrupted it")
        XCTAssertEqual(conversation.phase, .ready, "the reload that took over owns the phase")
        XCTAssertTrue(environment.isChatRunning)
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1"])
    }

    // MARK: phase after .ready

    func test_start_onAStartedModelInTheBackground_throwsOffline_withoutLoadingOrLeavingTheSuspension() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")]])
        environment.send(.didEnterBackground)
        await waitUntil { self.conversation.phase == .connecting }
        let loads = dataSource.historyCalls

        do {
            try await conversation.start()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .offline)
        }
        XCTAssertEqual(dataSource.historyCalls, loads, "nothing is loaded while the app is in the background")
        XCTAssertEqual(conversation.phase, .connecting)
        XCTAssertFalse(environment.isChatRunning)
        do {
            _ = try await conversation.send(text: "hi")
            XCTFail("expected offline: the model is still suspended")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .offline)
        }

        environment.send(.willEnterForeground)
        await waitUntil { self.conversation.phase == .ready }
    }

    func test_offline_afterReady_isConnecting_andSendThrowsOffline_untilTheReloadIsDone() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")]])
        XCTAssertEqual(conversation.phase, .ready)

        environment.setOnline(false)
        await waitUntil { !self.conversation.isOnline }

        XCTAssertEqual(conversation.phase, .connecting)
        XCTAssertEqual(conversation.messages.map(\.entryId), ["m1"], "the messages stay readable")
        do {
            _ = try await conversation.send(text: "hi")
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .offline)
        }

        environment.setOnline(true)
        await waitUntil { self.conversation.phase == .ready }
    }

    func test_background_afterReady_isConnecting_andSendsThrowOffline_whileTheNetworkIsUp() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")]])

        environment.send(.didEnterBackground)
        await waitUntil { self.conversation.phase == .connecting }

        XCTAssertTrue(conversation.isOnline)
        do {
            _ = try await conversation.send(text: "hi")
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .offline)
        }
        XCTAssertTrue(conversation.pending.isEmpty, "nothing was added")
        XCTAssertTrue(dataSource.sent.isEmpty)

        environment.send(.willEnterForeground)
        await waitUntil { self.conversation.phase == .ready }
        _ = try await conversation.send(text: "hi again")
        XCTAssertEqual(dataSource.sent.count, 1)
    }

    // MARK: loadMore and sendTyping outside .ready

    func test_loadMore_whileLoadingTheFirstPage_throwsNotStarted() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")], [Fixture.text("m0", "zero")]])
        dataSource.holdNextHistoryCalls()
        let conversation = self.conversation!
        let run = Task { try await conversation.start() }
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }

        do {
            try await conversation.loadMore()
            XCTFail("expected notStarted")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .notStarted)
        }
        dataSource.releaseHistory()
        try await run.value
        XCTAssertEqual(dataSource.historyCalls, 1, "no second page was requested")
    }

    func test_loadMore_afterAFailedStart_throwsNotStarted() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")], [Fixture.text("m0", "zero")]])
        dataSource.failHistory(times: 1)
        _ = try? await conversation.start()
        guard case .failed = conversation.phase else { return XCTFail("phase \(conversation.phase)") }

        do {
            try await conversation.loadMore()
            XCTFail("expected notStarted")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .notStarted)
        }
        XCTAssertEqual(dataSource.historyCalls, 1)
    }

    func test_loadMore_whileOffline_throwsOffline() async throws {
        try await startWithHistory([[Fixture.text("m1", "one")], [Fixture.text("m0", "zero")]])
        environment.setOnline(false)
        await waitUntil { !self.conversation.isOnline }

        do {
            try await conversation.loadMore()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .offline)
        }
    }

    func test_sendTyping_outsideReady_doesNothing() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        dataSource.failHistory(times: 1)
        let conversation = self.conversation!
        conversation.sendTyping(true) // not started
        _ = try? await conversation.start() // failed
        conversation.sendTyping(true)

        dataSource.holdNextHistoryCalls()
        let run = Task { try await conversation.start() } // connecting
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }
        conversation.sendTyping(true)
        dataSource.releaseHistory()
        try await run.value

        conversation.sendTyping(false) // ready: this one goes out
        await waitUntil { !self.dataSource.events.isEmpty }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(dataSource.events.count, 1, "only the call while ready was sent: \(dataSource.events)")
    }

    // MARK: The chat options

    func test_willStart_runsWhenTheConversationStarts_notWhenItIsCreated() async throws {
        dataSource.setPages([[]])
        let counter = Counter()
        let model = SinchConversation(dataSource: dataSource, environment: environment, pushPermission: nil,
                                      timing: Fixture.fastTiming, willStart: { counter.value += 1 })
        XCTAssertEqual(counter.value, 0)

        try await model.start()
        try await model.start() // ready already: not a start
        XCTAssertEqual(counter.value, 1)

        model.stop()
    }

    func test_willStart_isNotCalledWhenAnotherChatHoldsTheFlag() async throws {
        dataSource.setPages([[]])
        environment.externalChatRunning = true
        let counter = Counter()
        let model = SinchConversation(dataSource: dataSource, environment: environment, pushPermission: nil,
                                      timing: Fixture.fastTiming, willStart: { counter.value += 1 })

        _ = try? await model.start()

        XCTAssertEqual(counter.value, 0)
    }

    // MARK: Value types

    func test_pendingMessage_equalityUsesTempIDAndStatus() {
        let date = Date()
        let sending = SinchPendingMessage(tempID: "t1", body: MessageText(text: "a"), status: .sending, error: nil, createdAt: date)
        var sameWithAnotherBody = sending
        sameWithAnotherBody.body = MessageText(text: "b")
        var failed = sending
        failed.status = .failed
        let other = SinchPendingMessage(tempID: "t2", body: MessageText(text: "a"), status: .sending, error: nil, createdAt: date)

        XCTAssertEqual(sending, sameWithAnotherBody)
        XCTAssertNotEqual(sending, failed)
        XCTAssertNotEqual(sending, other)
        XCTAssertEqual(Set([sending, sameWithAnotherBody, failed, other]).count, 3)
    }

    func test_messageContent_isEquatable() {
        let text = Message(entryId: "1", owner: .outgoing, body: MessageText(text: "hi"))
        XCTAssertEqual(text.content, .text("hi"))
        XCTAssertNotEqual(text.content, .text("ho"))
        XCTAssertNotEqual(text.content, .unsupported)
        XCTAssertEqual(SinchChoice.url(text: "a", url: "b"), SinchChoice.url(text: "a", url: "b"))
        XCTAssertEqual(Set([SinchChoice.url(text: "a", url: "b"), SinchChoice.call(text: "a", phoneNumber: "1")]).count, 2)
    }
}
