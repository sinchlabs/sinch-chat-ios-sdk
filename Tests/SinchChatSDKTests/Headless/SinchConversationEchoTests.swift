import XCTest
@testable import SinchChatSDK

/// Which pending message an echo settles: the tombstone of a locally confirmed message, and failed messages.
@MainActor
final class SinchConversationEchoTests: ConversationTestCase {

    private let lostAnswer = MessageDataSourceError.unknown(NSError(domain: "net", code: -1))

    // MARK: Tombstones

    func test_echoUnderTheSendAnswersId_usesUpTheTombstone() async throws {
        try await startWithHistory([[]])
        _ = try await conversation.send(text: "hi")
        await waitUntil { self.conversation.messages.count == 1 } // confirmed locally as srv-1

        dataSource.emit(outgoingEcho(id: "srv-1", text: "hi")) // the message itself, same id
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(conversation.messages.count, 1)

        dataSource.emit(outgoingEcho(id: "other-device", text: "hi")) // the same text from another device
        await waitUntil { self.conversation.messages.count == 2 }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1", "other-device"])
    }

    func test_reload_clearsTheTombstones() async throws {
        try await startWithHistory([[]])
        _ = try await conversation.send(text: "hi")
        await waitUntil { self.conversation.messages.count == 1 }

        await reconnect()
        await waitUntil { self.conversation.phase == .ready && self.conversation.messages.isEmpty }
        dataSource.emit(outgoingEcho(id: "other-device", text: "hi"))

        await waitUntil { self.conversation.messages.map(\.entryId) == ["other-device"] }
    }

    // MARK: Failed messages

    func test_lateEcho_ofALocallyConfirmedMessage_doesNotSettleAnEarlierFailedOneWithTheSameText() async throws {
        try await startWithHistory([[]])
        dataSource.queueSendResults([.failure(lostAnswer), .success("srv-2")])
        _ = try? await conversation.send(text: "hi") // tmp-1: failed
        _ = try await conversation.send(text: "hi") // tmp-2: confirmed locally after the grace period
        await waitUntil { self.conversation.messages.map(\.entryId) == ["srv-2"] }

        dataSource.emit(outgoingEcho(id: "late-77", text: "hi")) // tmp-2's echo, under another id
        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-2"])
        XCTAssertEqual(conversation.pending.map(\.status), [.failed], "the failed message never went out")
    }

    func test_echo_doesNotSettleAMessageThatFailedBeforeTheNetwork() async throws {
        try await startWithHistory([[]])
        dataSource.queueSendResults([.failure(.notLoggedIn)])
        _ = try? await conversation.send(text: "hi")
        XCTAssertEqual(conversation.pending.first?.status, .failed)

        dataSource.emit(outgoingEcho(id: "other-device", text: "hi")) // somebody else wrote the same
        await waitUntil { self.conversation.messages.count == 1 }

        XCTAssertEqual(conversation.pending.first?.status, .failed, "it was never sent; Retry must stay available")
    }

    func test_echo_settlesAMessageWhoseCallWasCancelledAfterDispatch() async throws {
        try await startWithHistory([[]])
        dataSource.queueSendResults([.failure(.unknown(CancellationError()))])
        _ = try? await conversation.send(text: "hi")
        XCTAssertEqual(conversation.pending.first?.status, .failed)

        dataSource.emit(outgoingEcho(id: "srv-5", text: "hi"))
        await waitUntil { self.conversation.pending.isEmpty }

        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-5"])
    }

    func test_stoppedWhileSending_thenEcho_settlesTheFailedMessage() async throws {
        try await startWithHistory([[]])
        dataSource.onSend { _ in try? await Task.sleep(for: .milliseconds(200)) }
        let conversation = self.conversation!
        let send = Task { try await conversation.send(text: "hi") }
        await waitUntil { self.dataSource.sent.count == 1 }
        conversation.stop()
        XCTAssertEqual(conversation.pending.first?.status, .failed)
        try await conversation.start() // the first call is still running

        dataSource.emit(outgoingEcho(id: "srv-1", text: "hi")) // it did go out

        await waitUntil { self.conversation.pending.isEmpty }
        XCTAssertEqual(conversation.messages.map(\.entryId), ["srv-1"])
        _ = try? await send.value
    }
}
