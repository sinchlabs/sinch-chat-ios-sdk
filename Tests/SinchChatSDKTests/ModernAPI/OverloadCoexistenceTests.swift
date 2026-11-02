import XCTest

@testable import SinchChatSDK

/// Compile-time checks that the completion-handler and the async forms coexist at a call site.
///
/// Nothing here is called by a test: the point is that both spellings type-check from one file, inside and outside an
/// async context. The regression this guards against is an async overload that steals the completion form's call
/// shape — the 2.0.0 spellings below would then need `try await` and the file would stop compiling.
private enum OverloadCompileChecks {

    /// The 2.0.0 forms, called from an async function exactly as an app written against 2.0.0 does.
    ///
    /// Each identity call is bound to `Void`, which only the synchronous completion form returns: an async overload
    /// resolving the same spelling would need `try await` and would fail to type-check here.
    static func completionFormsFromAnAsyncContext(_ sdk: SinchChatSDK,
                                                  _ config: SinchSDKConfig.AppConfig,
                                                  _ inbox: SinchInbox,
                                                  _ options: GetChatViewControllerOptions?) async {
        let withConfig: Void = sdk.setIdentity(with: config, identity: .anonymous)
        let logout: Void = sdk.removeIdentity(nil)
        let inboxChats: Void = inbox.getInboxChats(options: nil) { _ in }
        _ = (withConfig, logout, inboxChats)
    }

    /// The same forms outside an async context, plus the explicit completion labels.
    static func completionFormsFromASynchronousContext(_ sdk: SinchChatSDK,
                                                       _ config: SinchSDKConfig.AppConfig) {
        sdk.setIdentity(with: config, identity: .anonymous)
        sdk.setIdentity(with: config, identity: .anonymous, completion: nil)
        sdk.setIdentity(with: config, identity: .anonymous) { _ in }
        sdk.removeIdentity(nil)
        sdk.removeIdentity { _ in }
    }

    /// The 2.1.0 async forms, with their distinct labels.
    static func asyncForms(_ sdk: SinchChatSDK, _ config: SinchSDKConfig.AppConfig) async throws {
        try await sdk.setIdentity(config: config, identity: .anonymous)
        try await sdk.removeIdentity()
    }

    static func inboxForms(_ inbox: SinchInbox, options: GetChatViewControllerOptions?) async {
        _ = await inbox.getInboxChats(options: options)
        inbox.getInboxChats(options: options) { _ in }
    }

    static func pluginForms(_ methods: SinchPluginAvailablePluginMethods) async throws {
        _ = try await methods.sendMessage(.text("hi"), authModel: nil, chatOptions: nil)
        methods.sendMessage(.text("hi"), authModel: nil, chatOptions: nil) { _ in }
    }

    /// The overloads are distinct functions, not two spellings of one.
    static func distinctReferences(_ sdk: SinchChatSDK) {
        let completionWithConfig: (SinchSDKConfig.AppConfig, SinchSDKIdentity,
                                   (@Sendable (Result<Void, SinchSDKIdentityError>) -> Void)?) -> Void =
            sdk.setIdentity(with:identity:completion:)
        let asyncWithConfig: (SinchSDKConfig.AppConfig, SinchSDKIdentity) async throws -> Void =
            sdk.setIdentity(config:identity:)
        let completionLogout: ((@Sendable (Result<Void, Error>) -> Void)?) -> Void = sdk.removeIdentity(_:)
        let asyncLogout: () async throws -> Void = sdk.removeIdentity

        _ = (completionWithConfig, asyncWithConfig, completionLogout, asyncLogout)
    }
}

/// The two forms of `setIdentity`/`removeIdentity` reach the same implementation, so a call site can migrate one
/// call at a time without changing behaviour.
@MainActor
final class OverloadCoexistenceTests: XCTestCase {

    private let config = modernAPIConfig()

    func testCompletionAndAsyncSetIdentityReachTheSameForwarder() async throws {
        let sdk = SinchChatSDK()
        let calls = Locked(0)

        sdk.pushSetIdentity = { _, _, completion in
            calls.mutate { $0 += 1 }
            completion(.success(()))
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // The 2.0.0 call shape, inside an async body.
            sdk.setIdentity(with: config, identity: .anonymous) { _ in
                continuation.resume()
            }
        }
        try await sdk.setIdentity(config: config, identity: .anonymous)

        XCTAssertEqual(calls.value, 2, "both forms must forward to the same push call")
    }

    /// The 2.0.0 spelling without a completion argument still resolves to the completion form and never awaits.
    func testTheCompletionCallShapeFromAnAsyncContextReachesTheForwarder() async throws {
        let sdk = SinchChatSDK()
        let calls = Locked(0)

        sdk.pushSetIdentity = { _, _, completion in
            calls.mutate { $0 += 1 }
            completion(.success(()))
        }

        sdk.setIdentity(with: config, identity: .anonymous)

        // The completion form is synchronous: the forwarder has already run by the time it returns.
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(sdk.config, config, "the chat side effects of the completion form still run")
    }

    func testCompletionAndAsyncRemoveIdentityReachTheSameForwarder() async throws {
        let sdk = SinchChatSDK()
        let calls = Locked(0)

        sdk.pushRemoveIdentity = { completion in
            calls.mutate { $0 += 1 }
            completion(.success(()))
        }

        sdk.removeIdentity(nil)
        try await sdk.removeIdentity()

        XCTAssertEqual(calls.value, 2, "both forms must forward to the same push call")
    }

    func testAsyncGetInboxChatsReturnsTheValueOfTheCompletionForm() async {
        let inbox = DefaultSinchInbox(pushPermissionHandler: PushNofiticationPermissionHandlerStub())

        // Without a token provider the completion form reports an empty list; the async form forwards it.
        let chats = await inbox.getInboxChats(options: nil)

        XCTAssertTrue(chats.isEmpty)
    }
}
