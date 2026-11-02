import UIKit

// The async surface of ``SinchPluginAvailablePluginMethods`` — the methods a chat plugin is handed. Purely additive:
// each call bridges the completion-handler requirement that shipped before, so an existing plugin keeps compiling and
// a new plugin can write `await`.

public extension SinchPluginAvailablePluginMethods {

    /// Sends a message, awaited.
    ///
    /// The async form of ``sendMessage(_:authModel:chatOptions:completion:)``. It uses the same message data source,
    /// so ``SinchPluginAvailablePluginMethods/additionalMetadata``, the topic and the conversation options apply the
    /// same way.
    ///
    /// ```swift
    /// let payload = try await methods.sendMessage(.text("Hi"), authModel: nil, chatOptions: nil)
    /// ```
    ///
    /// - Parameters:
    ///   - message: The message to send.
    ///   - authModel: The authorization to use, or `nil` for the current one.
    ///   - chatOptions: The topic, metadata and conversation options of the message.
    /// - Returns: The payload id of the sent message.
    /// - Throws: `SinchChatSDKError.unavailable` when chat is not initialized, or the error of the send call.
    func sendMessage(_ message: MessageType,
                     authModel: AuthModel?,
                     chatOptions: SinchChatOptions?) async throws -> String {
        let gate = OnceGate()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            sendMessage(message, authModel: authModel, chatOptions: chatOptions) { result in
                guard gate.claim() else { return }
                continuation.resume(with: result)
            }
        }
    }

    /// Presents a view controller, awaited.
    ///
    /// The async form of ``presentViewController(_:_:completion:)``: it returns when the presentation animation is
    /// over. It runs on the main thread, as the completion form does.
    func presentViewController(_ viewController: UIViewController, _ animated: Bool) async {
        let gate = OnceGate()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            presentViewController(viewController, animated) {
                guard gate.claim() else { return }
                continuation.resume()
            }
        }
    }
}
