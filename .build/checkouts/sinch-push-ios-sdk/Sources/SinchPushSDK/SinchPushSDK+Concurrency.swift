import Foundation

// MARK: - Swift concurrency API

/// Swift-concurrency counterparts of the identity calls.
///
/// Each one awaits the completion-handler method, so the behaviour is the same,
/// including the token cache, the relay hand-off and the delivery-report session.
/// The completion methods are unchanged and still work.
///
/// The async forms are deliberately named apart: `setIdentity(config:identity:)`
/// and `setIdentity(to:)` cannot be confused with `setIdentity(with:identity:completion:)`
/// and `setIdentity(_:completion:)`, whose completion already has a default value.
/// Sharing the labels would make 1.0.0 code such as
/// `setIdentity(with: config, identity: .anonymous)` inside an async function
/// resolve to the async overload and stop compiling.
public extension SinchPushSDK {

    /// Sets the identity of the user and suspends until the access token is issued.
    ///
    /// Same as ``setIdentity(with:identity:completion:)``: calling it again
    /// regenerates the token when the identity changed.
    /// - Parameters:
    ///   - config: Configuration of sdk.
    ///   - identity: The way of user authorization.
    /// - Throws: ``SinchSDKIdentityError`` when the token cannot be issued.
    func setIdentity(config: SinchSDKConfig.AppConfig,
                     identity: SinchSDKIdentity) async throws(SinchSDKIdentityError) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, SinchSDKIdentityError>) in
            self.setIdentity(with: config, identity: identity, completion: { result in
                continuation.resume(with: result)
            })
        }
    }

    /// Sets the identity with the config passed to ``initialize(config:options:)``.
    /// - Parameter identity: The way of user authorization.
    /// - Throws: ``SinchSDKIdentityError`` when no config is available or the token cannot be issued.
    func setIdentity(to identity: SinchSDKIdentity) async throws(SinchSDKIdentityError) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, SinchSDKIdentityError>) in
            self.setIdentity(identity, completion: { result in
                continuation.resume(with: result)
            })
        }
    }

    /// Removes the identity of the user and suspends until the device is unsubscribed.
    ///
    /// Same as ``removeIdentity(_:)``: the token and the relay session are cleared.
    /// The name is safe to share with the completion form: `removeIdentity(_:)` has
    /// no default for its completion, so `removeIdentity()` can only mean this one.
    /// - Throws: The error of the unsubscribe call, if it fails.
    func removeIdentity() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.removeIdentity({ result in
                continuation.resume(with: result)
            })
        }
    }
}
