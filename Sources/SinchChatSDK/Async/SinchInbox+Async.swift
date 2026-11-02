import Foundation

// The async surface of ``SinchInbox``. Purely additive: each call bridges the completion-handler API that shipped
// before, so both styles coexist and resolve to the same code.

public extension SinchInbox {

    /// The inbox events, as an async sequence.
    ///
    /// Backed by ``chatInboxEventListenerSubject``: each access creates a fresh stream, and events sent before it is
    /// created are not replayed. The subscription is cancelled when the consumer stops iterating — on `break`, on task
    /// cancellation, or when the stream is released. `SinchInboxEvent` is `Sendable`, so the stream can be handed to
    /// another task or actor.
    ///
    /// ```swift
    /// for await event in SinchChatSDK.shared.chat.inbox.events {
    ///     if case .chatUpdated(let chat) = event { ... }
    /// }
    /// ```
    ///
    /// Up to 64 pending events are buffered; older ones are dropped when a consumer does not drain the stream.
    var events: AsyncStream<SinchInboxEvent> {
        EventStream.make(from: chatInboxEventListenerSubject)
    }

    /// The latest conversations, awaited.
    ///
    /// The async form of ``getInboxChats(options:completion:)``. The completion form reports failures as an empty
    /// array; the async form does the same, so a caller cannot distinguish "no conversations" from "not logged in" —
    /// check ``SinchChat/isChatAvailable()`` first when that matters.
    ///
    /// ```swift
    /// let chats = await SinchChatSDK.shared.chat.inbox.getInboxChats(options: nil)
    /// ```
    ///
    /// - Parameter options: Optionally custom chat options.
    /// - Returns: The latest conversations.
    func getInboxChats(options: GetChatViewControllerOptions? = nil) async -> [InboxChat] {
        let gate = OnceGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<[InboxChat], Never>) in
            getInboxChats(options: options) { chats in
                guard gate.claim() else { return }
                continuation.resume(returning: chats)
            }
        }
    }
}
