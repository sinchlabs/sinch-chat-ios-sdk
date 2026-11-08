import UIKit
import Synchronization
@_spi(SinchChat) import SinchPushSDK

public protocol SinchChat {
     var inbox: SinchInbox { get }

    /// Advanced settings and method of Sinch Chat.
    var advanced: SinchChatAdvanced { get }
    
    /// Checks if chat can be opened.
    /// - Returns: Current Chat availability.
    func isChatAvailable() -> SinchSDKChatAvailability
    
    /// Creating Chat UI. This method may throw
    /// - Parameters:
   
    ///   - uiConfig: Optionally ui changes might be provided with different settings.
    ///   - localizationConfig: Optionally localization might be provided with different text translation.
    ///   - options: Optionally custom chat options.
    /// - Returns: UIViewController which contains chat UI.
    /// - Throws: SinchChatSDKError enum with specific error.
    func getChatViewController(uiConfig: SinchSDKConfig.UIConfig?,
                               localizationConfig: SinchSDKConfig.LocalizationConfig?,
                               options: GetChatViewControllerOptions?) throws -> SinchChatViewController
    
}

public protocol SinchChatViewController: UIViewController {
}

public extension SinchChat {
    
    func getChatViewController(uiConfig: SinchSDKConfig.UIConfig? = nil,
                               localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
                               options: GetChatViewControllerOptions? = nil) throws -> SinchChatViewController {
        try getChatViewController(uiConfig: uiConfig, localizationConfig: localizationConfig, options: options)
    }
}

public enum SinchSDKChatAvailability {
    /// The Chat is ready to user.
    case available
    /// The Chat is not initialized
    /// Tip: use initialize method to initialize chat.
    case uninitialized
    /// The chat is not authorized
    /// Tip: User setIdentity method to authorize the client.
    case authorizationNeeded
    
    /// The chat is opened
    /// You cannot run two chats at once.
    case currentlyRunning
}

public enum SinchChatSDKError: Error {
    case unavailable
    case error(String)
}

public enum SinchChatState: Sendable {
    case running
    case idle
}

final class DefaultSinchChat: SinchChat, @unchecked Sendable {
    
    /// Contains all methods connected with Inbox. Before using the inbox you should use method `setIdentity`.
    public var inbox: SinchInbox { _inbox }

    lazy var _inbox = DefaultSinchInbox(pushPermissionHandler: pushPermissionHandler)

    /// The "a chat is running" flag and who holds it. One value behind one lock: `isChatAvailable()` and the push
    /// handler read it from any thread while the main actor claims and releases it.
    private struct ChatFlag: Sendable {
        var state: SinchChatState = .idle
        var owner: UUID?
    }

    private let flag = Mutex(ChatFlag())

    var state: SinchChatState {
        flag.withLock { $0.state }
    }

    /// Who set `state` to `.running`: a headless conversation or a chat screen (each with its own token), so only that
    /// holder can release it. `nil` while idle, or when something wrote the state without a token.
    var stateOwner: UUID? {
        flag.withLock { $0.owner }
    }

    /// Writes state and owner in one step. Used by tests only; production code goes through the claim and release
    /// methods below.
    func setFlag(state: SinchChatState, owner: UUID?) {
        flag.withLock { flag in
            flag.state = state
            flag.owner = owner
        }
    }

    /// Takes the flag for `owner` unless somebody else holds it. Claiming again with the same token succeeds. State and
    /// owner change in one step.
    func claimChat(owner: UUID) -> Bool {
        flag.withLock { flag in
            if flag.state == .running, flag.owner != owner { return false }
            flag.state = .running
            flag.owner = owner
            return true
        }
    }

    /// Gives the flag back when `owner` holds it; does nothing otherwise, so a holder can never release a claim that
    /// is not its own.
    func releaseChat(owner: UUID) {
        flag.withLock { flag in
            guard flag.owner == owner else { return }
            flag.owner = nil
            flag.state = .idle
        }
    }

    /// The chat screen takes the flag whether or not another chat holds it (it never asked before), and records itself
    /// as the holder. A headless conversation that held it has lost it: its next claim fails.
    func takeChat(owner: UUID) {
        flag.withLock { flag in
            flag.state = .running
            flag.owner = owner
        }
    }

    /// The chat screen gives the flag back. Applies when `owner` holds it, or when no token holds it (the flag was
    /// written without one: the screen's state before it had tokens). It never applies when another token holds it,
    /// so a screen that already lost the flag to a headless conversation or to another screen leaves that claim
    /// alone.
    func releaseChatFromScreen(owner: UUID) {
        flag.withLock { flag in
            guard flag.owner == owner || flag.owner == nil else { return }
            flag.owner = nil
            flag.state = .idle
        }
    }

    var lastChatOptions: GetChatViewControllerOptions?
    
    var advanced: SinchChatAdvanced = .init()
    
    internal var tokenProvider: ChatTokenProvider? {
        didSet {
            _inbox.tokenProvider = tokenProvider
        }
    }
    internal var region: Region? {
        didSet {
            _inbox.region = region
        }
    }
    internal var apiClient: APIClient? {
        didSet {
            _inbox.apiClient = apiClient
        }
    }

    private let pushPermissionHandler: PushNofiticationPermissionHandler
    private let chatNotificationHandler = ChatNotificationHandler()
    private var rootCordinator: RootCoordinator?

    init(pushPermissionHandler: PushNofiticationPermissionHandler,
         apiClient: APIClient? = nil) {
        self.pushPermissionHandler = pushPermissionHandler
    }
    
    public func isChatAvailable() -> SinchSDKChatAvailability {
        guard state != .running else {
            return SinchSDKChatAvailability.currentlyRunning
        }

        guard let tokenProvider = tokenProvider, region != nil else {
            return SinchSDKChatAvailability.uninitialized
        }

        guard tokenProvider.isLoggedIn == true else {
            return SinchSDKChatAvailability.authorizationNeeded
        }

        return SinchSDKChatAvailability.available
    }

    public func getChatViewController(uiConfig: SinchSDKConfig.UIConfig? = nil,
                                      localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
                                      options: GetChatViewControllerOptions? = nil) throws -> SinchChatViewController {
        let capturedUIConfig = uiConfig
        let capturedLocConfig = localizationConfig
        let capturedOptions = options
        return try MainActor.assumeIsolated {
            guard self.isChatAvailable() == .available, let tokenProvider = self.tokenProvider, let region = self.region else {
                throw SinchChatSDKError.unavailable
            }

            if self.apiClient == nil {
                guard let client = Default2APIClient(region: region) else {
                    throw SinchChatSDKError.unavailable
                }
                self.apiClient = client
            }

            var topicModel: TopicModel?
            if let topicID = capturedOptions?.topicID {
                topicModel = TopicModel(topicID: topicID)
            }

            let messageDataSource = DefaultMessageDataSource(
                apiClient: self.apiClient!,
                tokenProvider: tokenProvider,
                topicModel: topicModel,
                metadata: capturedOptions?.metadata ?? [],
                shouldInitializeConversation: capturedOptions?.shouldInitializeConversation ?? false,
                sendDocumentAsText: capturedOptions?.sendDocumentAsTextMessage ?? false)

            let rootCordinator = DefaultRootCoordinator(messageDataSource: messageDataSource,
                                                        tokenProvider: tokenProvider,
                                                        pushPermissionHandler: self.pushPermissionHandler)

            self.rootCordinator = rootCordinator
            let uiConfig = capturedUIConfig ?? SinchSDKConfig.UIConfig.defaultValue
            let locConfig = capturedLocConfig ?? SinchSDKConfig.LocalizationConfig.defaultValue

            self.lastChatOptions = capturedOptions
            return rootCordinator.getRootViewController(uiConfig: uiConfig, localizationConfig: locConfig, sendDocumentAsText: capturedOptions?.sendDocumentAsTextMessage ?? false)
        }
    }

    func initilize() {
        _inbox.initilize()
        // Push owns APNs; chat handles its own payloads as a registered addressee.
        SinchPushSDK.shared.register(addressee: chatNotificationHandler)
        chatNotificationHandler.delegate = self
    }
}

extension DefaultSinchChat: ChatNotificationHandlerDelegate {
    
    func getChatState() -> SinchChatState {
        state
    }
}

public protocol SinchMetadata: Codable, Hashable {
    // swiftlint:disable:next large_tuple
    func getKeyValue() -> (key: String, value: String, mode: SinchMetadataMode)
}

public typealias SinchMetadataArray = Array<SinchMetadataCustom>

public enum SinchMetadataMode: Codable, Sendable {
    case once
    case withEachMessage
}

public struct GetChatViewControllerOptions: Codable, Sendable {
    var topicID: String?
    let metadata: SinchMetadataArray
    let shouldInitializeConversation: Bool
    let sendDocumentAsTextMessage: Bool

    public init(
        topicID: String? = nil,
        metadata: SinchMetadataArray,
        shouldInitializeConversation: Bool = false,
        sendDocumentAsTextMessage: Bool = false
    ) {
        self.topicID = topicID
        self.metadata = metadata
        self.shouldInitializeConversation = shouldInitializeConversation
        self.sendDocumentAsTextMessage = sendDocumentAsTextMessage
    }
}

public struct SinchMetadataCustom: Codable, Equatable, SinchMetadata, Sendable {
    let key: String
    let value: String
    let mode: SinchMetadataMode
    
    public init(key: String, value: String, mode: SinchMetadataMode) {
        self.key = key
        self.value = value
        self.mode = mode
    }
    
    // swiftlint:disable:next large_tuple
    public func getKeyValue() -> (key: String, value: String, mode: SinchMetadataMode) {
        return (key, value, mode)
    }
    
    public static func == (lhs: SinchMetadataCustom, rhs: SinchMetadataCustom) -> Bool {
        lhs.key == rhs.key &&
        lhs.value == rhs.value &&
        lhs.mode == rhs.mode
    }
}

public class SinchChatAdvanced {
    
    internal init() {}
    
    internal var _isSendingMessagesEnabled: Bool = true
    internal var enableSendingMessagesHandler: (() -> Void)?
    internal var disableSendingMessagesHandler: (() -> Void)?
    
    /// Provides information if sending messages feature is enabled.
    public var isSendingMessagesEnabled: Bool {
        _isSendingMessagesEnabled
    }
    
    /// Enables possibility to sending messages.
    public func enableSendingMessages() {
        _isSendingMessagesEnabled = true
        self.enableSendingMessagesHandler?()
    }
    
    /// Disables possibility to sending messages.
    public func disableSendingMessages() {
        _isSendingMessagesEnabled = false
        self.disableSendingMessagesHandler?()
    }
    
}
