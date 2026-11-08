import XCTest
@testable import SinchChatSDK

/// Sending: the optimistic pending message, its confirmation by the echo, retries and typing.
@MainActor
final class SinchConversationSendTests: ConversationTestCase {

    func test_send_addsPendingThenResolvesOnEcho_withoutDuplicates() async throws {
        try await startWithHistory([[]])
        let snapshot = PendingSnapshot()
        let conversation = self.conversation!
        dataSource.onSend { _ in await snapshot.record(conversation) }

        let sent = try await conversation.send(text: "hello")

        let during = await snapshot.value
        XCTAssertEqual(during?.count, 1)
        XCTAssertEqual(during?.first?.status, .sending)
        XCTAssertEqual(sent.entryId, "srv-1")
        XCTAssertEqual(conversation.pending.count, 1, "still waiting for the echo")
        XCTAssertTrue(conversation.messages.isEmpty)

        // The echo carries the server's clock, not the device's.
        dataSource.emit(outgoingEcho(id: "srv-1", text: "hello"))
        await waitUntil { self.conversation.pending.isEmpty }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])
        XCTAssertEqual(conversation.messages.first?.status, .sent)

        dataSource.emit(outgoingEcho(id: "srv-1", text: "hello"))
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(conversation.messages.count, 1, "a repeated echo must not duplicate")
    }

    func test_send_echoBeforeAck_resolvesByContent_andKeepsNothingBehind() async throws {
        try await startWithHistory([[]])
        let dataSource = self.dataSource!
        let echo = outgoingEcho(id: "srv-1", text: "hello")
        dataSource.onSend { _ in
            dataSource.emit(echo)
            try? await Task.sleep(for: .milliseconds(50))
        }

        let sent = try await conversation.send(text: "hello")

        XCTAssertEqual(sent.entryId, "srv-1")
        XCTAssertTrue(conversation.pending.isEmpty)
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])
        XCTAssertTrue(conversation.resolved.isEmpty, "the resolved message is only kept for the call that waits for it")
    }

    func test_send_twoIdenticalTexts_resolveEachOnce() async throws {
        try await startWithHistory([[]])
        _ = try await conversation.send(text: "ok")
        _ = try await conversation.send(text: "ok")
        XCTAssertEqual(conversation.pending.count, 2)

        dataSource.emit(outgoingEcho(id: "srv-1", text: "ok"))
        dataSource.emit(outgoingEcho(id: "srv-2", text: "ok"))
        await waitUntil { self.conversation.pending.isEmpty }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1", "srv-2"])
    }

    func test_repeatedEcho_doesNotSettleTheNextPendingMessageWithTheSameText() async throws {
        let slow = SinchConversation.Timing(typingTimeout: .seconds(30), typingSuppression: 0, echoGrace: .seconds(30),
                                            reconnectDelay: .milliseconds(10), foregroundDelay: .zero)
        conversation.stop()
        conversation = Fixture.conversation(dataSource, environment: environment, timing: slow)
        try await startWithHistory([[]])
        _ = try await conversation.send(text: "ok")
        dataSource.emit(outgoingEcho(id: "srv-1", text: "ok"))
        await waitUntil { self.conversation.pending.isEmpty }

        _ = try await conversation.send(text: "ok")
        dataSource.emit(outgoingEcho(id: "srv-1", text: "ok")) // the same echo again
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(conversation.pending.count, 1, "the second message is still waiting for its own echo")
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])
    }

    func test_send_withoutEcho_confirmsLocallyAfterGrace_andLateEchoIsIgnored() async throws {
        try await startWithHistory([[]])
        _ = try await conversation.send(text: "hello")

        await waitUntil { self.conversation.pending.isEmpty }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])

        dataSource.emit(outgoingEcho(id: "srv-1", text: "hello"))
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(conversation.messages.count, 1)
    }

    func test_send_withoutEcho_lateEchoUnderAnotherId_isStillDropped() async throws {
        try await startWithHistory([[]])
        _ = try await conversation.send(text: "hello")
        await waitUntil { self.conversation.pending.isEmpty } // confirmed locally as srv-1

        // The server's entry id is not the id the send call answered with.
        dataSource.emit(outgoingEcho(id: "entry-77", text: "hello"))
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])

        // The tombstone is used up: the same text again is a new message.
        dataSource.emit(outgoingEcho(id: "entry-78", text: "hello"))
        await waitUntil { self.conversation.messages.count == 2 }
    }

    func test_failedSend_marksPendingFailed_thenRetrySucceeds() async throws {
        try await startWithHistory([[]])
        dataSource.queueSendResults([.failure(.unknown(NSError(domain: "net", code: -1))), .success("srv-9")])

        do {
            _ = try await conversation.send(text: "hello")
            XCTFail("expected failure")
        } catch {
            guard case .underlying = error as? SinchHeadlessError else { return XCTFail("\(error)") }
        }
        let failed = try XCTUnwrap(conversation.pending.first)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertNotNil(failed.error)
        XCTAssertTrue(conversation.messages.isEmpty)

        let sent = try await conversation.retry(failed.tempID)

        XCTAssertEqual(sent.entryId, "srv-9")
        XCTAssertEqual(conversation.pending.first?.tempID, failed.tempID, "keeps its place")
        XCTAssertEqual(conversation.pending.first?.status, .sending)

        dataSource.emit(outgoingEcho(id: "srv-9", text: "hello"))
        await waitUntil { self.conversation.pending.isEmpty }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-9"])
    }

    func test_failedMessage_thatTheServerTookAfterAll_isSettledByItsEcho() async throws {
        try await startWithHistory([[]])
        dataSource.queueSendResults([.failure(.unknown(NSError(domain: "net", code: -1)))])
        _ = try? await conversation.send(text: "hello")
        XCTAssertEqual(conversation.pending.first?.status, .failed)

        dataSource.emit(outgoingEcho(id: "srv-5", text: "hello")) // the answer got lost, the message did arrive
        await waitUntil { self.conversation.pending.isEmpty }

        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-5"], "Retry must not send it a second time")
    }

    func test_retry_unknownOrNotFailed_throws() async throws {
        try await startWithHistory([[]])
        _ = try await conversation.send(text: "hello")
        let tempID = try XCTUnwrap(conversation.pending.first?.tempID)
        for id in ["nope", tempID] {
            do {
                _ = try await conversation.retry(id)
                XCTFail("expected throw for \(id)")
            } catch {
                XCTAssertEqual(error as? SinchHeadlessError, .unknownPendingMessage)
            }
        }
    }

    func test_discard_removesFailedPending_andTellsTheUpdatesStream() async throws {
        try await startWithHistory([[]])
        let recorder = UpdateRecorder(conversation)
        dataSource.queueSendResults([.failure(.noInternetConnection)])
        _ = try? await conversation.send(text: "hello")
        let tempID = try XCTUnwrap(conversation.pending.first?.tempID)

        conversation.discard(tempID)

        XCTAssertTrue(conversation.pending.isEmpty)
        await waitUntil { recorder.removedTempIDs == [tempID] }
    }

    func test_send_beforeStart_throws() async {
        do {
            _ = try await conversation.send(text: "hello")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .notStarted)
        }
        XCTAssertTrue(conversation.pending.isEmpty)
    }

    func test_send_media_uploadsThenSendsUrl_andResolvesOnEcho() async throws {
        try await startWithHistory([[]])
        let file = URL(fileURLWithPath: "/tmp/report.pdf")

        let sent = try await conversation.send(.file(file))

        XCTAssertEqual(dataSource.uploads, 1)
        guard case let .media(message) = try XCTUnwrap(dataSource.sent.first),
              let body = message.body as? MessageMedia else { return XCTFail("expected a media message") }
        XCTAssertEqual(body.url, "https://files.example/upload.pdf")
        XCTAssertEqual(sent.entryId, "srv-1")

        let echo = Message(entryId: "srv-1", owner: .outgoing, body: MessageMedia(url: body.url, sendDate: 5, type: .file(.pdf)))
        dataSource.emit(echo)
        await waitUntil { self.conversation.pending.isEmpty }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])
    }

    func test_send_fileAsText_whenOptionIsSet() async throws {
        conversation.stop()
        conversation = Fixture.conversation(dataSource, environment: environment, sendDocumentAsText: true)
        try await startWithHistory([[]])

        _ = try await conversation.send(.file(URL(fileURLWithPath: "/tmp/report.pdf")))

        guard case let .text(text) = try XCTUnwrap(dataSource.sent.first) else { return XCTFail("expected text") }
        XCTAssertEqual(text, "https://files.example/upload.pdf")
    }

    func test_send_undecodableImage_failsAsUnsupportedMedia() async throws {
        try await startWithHistory([[]])
        do {
            _ = try await conversation.send(.image(Data([0, 1, 2])))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .unsupportedMedia)
        }
        XCTAssertEqual(conversation.pending.first?.status, .failed)
    }

    func test_sendLocation_choice_andTyping() async throws {
        try await startWithHistory([[]])

        let location = try await conversation.sendLocation(latitude: 52.5, longitude: 13.25, title: "Here", label: "Map")
        XCTAssertEqual((location.body as? MessageLocation)?.title, "Here")
        try await conversation.sendChoice(.reply(text: "Yes", postback: "yes", messageID: "m7"))
        try await conversation.sendChoice(.url(text: "Site", url: "https://example.com")) // host's job: no request

        XCTAssertEqual(dataSource.sent.count, 2)
        guard case let .location(lat, lon, config) = dataSource.sent[0] else { return XCTFail("expected location") }
        XCTAssertEqual(lat, 52.5)
        XCTAssertEqual(lon, 13.25)
        XCTAssertEqual(config.outgoingLocationMessageTitle, "Here")
        guard case let .choiceResponseMessage(postback, entryID) = dataSource.sent[1] else { return XCTFail("expected choice") }
        XCTAssertEqual(postback, "yes")
        XCTAssertEqual(entryID, "m7")

        conversation.sendTyping(true)
        conversation.sendTyping(false)
        await waitUntil { self.dataSource.events.count == 2 }
        guard case .composeStarted = dataSource.events[0], case .composeEnd = dataSource.events[1] else {
            return XCTFail("unexpected events \(dataSource.events)")
        }
    }

    func test_typing_isSentInOrder_evenWhenTheFirstCallIsSlow() async throws {
        try await startWithHistory([[]])
        dataSource.onEvent { event in
            if case .composeStarted = event { try? await Task.sleep(for: .milliseconds(80)) }
        }

        conversation.sendTyping(true)
        conversation.sendTyping(false)

        await waitUntil { self.dataSource.events.count == 2 }
        guard case .composeStarted = dataSource.events[0], case .composeEnd = dataSource.events[1] else {
            return XCTFail("typing events were reordered: \(dataSource.events)")
        }
    }

    func test_send_requestsPushPermission_whenNotGranted_andOptOut() async throws {
        let asks = AskCounter()
        let handler = CountingPermissionHandler(counter: asks)
        conversation.stop()
        conversation = Fixture.conversation(dataSource, environment: environment, pushPermission: handler)
        try await startWithHistory([[]])

        _ = try await conversation.send(text: "one")
        XCTAssertEqual(asks.value, 1)

        conversation.requestsPushPermissionOnSend = false
        _ = try await conversation.send(text: "two")
        XCTAssertEqual(asks.value, 1)
    }
}
