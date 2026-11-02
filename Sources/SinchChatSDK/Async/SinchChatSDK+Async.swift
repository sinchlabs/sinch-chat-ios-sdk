import Foundation

// The async surface of ``SinchChatSDK``. It is purely additive: every call is a bridge over the completion-handler
// API that shipped before, so both styles coexist and share exactly the same behaviour and side effects.

public extension SinchChatSDK {

    /// The plugin and chat lifecycle events, as an async sequence.
    ///
    /// Backed by ``eventListenerSubject``: each access creates a fresh stream, and events sent before it is created
    /// are not replayed. The subscription is cancelled when the consumer stops iterating — on `break`, on task
    /// cancellation, or when the stream is released — so a closed view does not leave a subscriber behind.
    /// `SinchPluginEvent` is `Sendable`, so the stream can be handed to another task or actor; the view controller of
    /// ``SinchPluginEvent/didStartChat(chatViewController:chatOptions:)`` is main-actor isolated, like UIKit itself.
    ///
    /// ```swift
    /// for await event in SinchChatSDK.shared.events {
    ///     switch event { ... }
    /// }
    /// ```
    ///
    /// Up to 64 pending events are buffered; older ones are dropped when a consumer does not drain the stream.
    var events: AsyncStream<SinchPluginEvent> {
        EventStream.make(from: eventListenerSubject)
    }

    /// Sets the identity of the user and returns when it is stored.
    ///
    /// The async form of ``setIdentity(with:identity:completion:)``: it awaits the same call and runs the same chat
    /// side effects on success — the config, the token provider, the chat channel of the identity's region, the
    /// ``SinchPluginEvent/didSetIdentity(_:)`` event and a fresh chat session. Calling it again regenerates the token,
    /// as the completion form does.
    ///
    /// The `config:` label differs from the completion form's `with:` on purpose: sharing the labels would make 2.0.0
    /// code such as `setIdentity(with: config, identity: .anonymous)` inside an async function resolve to this
    /// overload, where the missing `try await` is a compile error.
    ///
    /// ```swift
    /// try await SinchChatSDK.shared.setIdentity(
    ///     config: config,
    ///     identity: .anonymous
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - config: Configuration of sdk.
    ///   - identity: The way of user authorization.
    /// - Throws: ``SinchSDKIdentityError`` when the identity cannot be set.
    func setIdentity(config: SinchSDKConfig.AppConfig,
                     identity: SinchSDKIdentity) async throws(SinchSDKIdentityError) {
        let gate = OnceGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, SinchSDKIdentityError>) in
            setIdentity(with: config, identity: identity) { result in
                guard gate.claim() else { return }
                continuation.resume(with: result)
            }
        }
    }

    /// Removes the identity of the user and returns when the stored token is gone.
    ///
    /// The async form of ``removeIdentity(_:)``: it awaits the same call, sends
    /// ``SinchPluginEvent/didRemoveIdentity`` on success and propagates the push SDK's error on failure.
    /// The name is safe to share: `removeIdentity(_:)` has no default for its completion, so `removeIdentity()` can
    /// only mean this overload.
    ///
    /// ```swift
    /// try await SinchChatSDK.shared.removeIdentity()
    /// ```
    ///
    /// - Throws: The error the push SDK reports when the identity cannot be removed.
    func removeIdentity() async throws {
        let gate = OnceGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            removeIdentity { result in
                guard gate.claim() else { return }
                continuation.resume(with: result)
            }
        }
    }
}
