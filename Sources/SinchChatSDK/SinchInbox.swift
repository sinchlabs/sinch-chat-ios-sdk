import UIKit
import Combine
public protocol SinchInbox {
    
    /// Inbox event listener. It will be called when new event occurs.
    ///
    var chatInboxEventListenerSubject: PassthroughSubject<SinchInboxEvent, Never> { get }

    /// Creating Inbox UI. This method may throw
    ///
    /// The SDK's implementation returns the adaptive inbox (`SinchInboxLayout.automatic`): a sidebar with the chat
    /// beside it on regular width, a list that pushes the chat on compact width. When the returned controller is
    /// pushed on a `UINavigationController`, the host's navigation bar is hidden while the inbox is visible, because
    /// the inbox draws its own bars. Use `getInboxViewController(uiConfig:localizationConfig:options:layout:)` with
    /// `.stack` for the previous behaviour. See `Documentation/SinchInbox.md`.
    /// - Parameters:

    ///   - uiConfig: Optionally ui changes might be provided with different settings.
    ///   - localizationConfig: Optionally localization might be provided with different text translation.
    ///   - options: Optionally custom chat options.

    /// - Returns: UIViewController which contains inbox UI.
    /// - Throws: SinchInboxSDKError enum with specific error.
    func getInboxViewController(uiConfig: SinchSDKConfig.UIConfig?,
                                localizationConfig: SinchSDKConfig.LocalizationConfig?,
                                options: GetChatViewControllerOptions?) throws -> SinchChatViewController
    /// Get latest conversations
    /// - Parameters:
    ///   - options: Optionally custom chat options.
    ///
    /// - Returns: array of latest conversations
    ///
    func getInboxChats(options: GetChatViewControllerOptions?, completion: @escaping @Sendable ([InboxChat]) -> Void)

    /// Subscribe to inbox chat updates
    /// - Parameters:
    ///   - options: Optionally custom chat options.
    ///
    func subscribeToInboxChatUpdates(options: GetChatViewControllerOptions)

    /// Creating Chat UI. This method may throw
    /// - Parameters:
    ///
    ///   - InboxChat: Conversation obtained with getInboxChats(completion: @escaping ([InboxChat]) -> Void)
    ///   - uiConfig: Optionally ui changes might be provided with different settings.
    ///   - localizationConfig: Optionally localization might be provided with different text translation.

    /// - Returns: UIViewController which contains chat UI.
    /// - Throws: SinchChatSDKError enum with specific error.
    ///
    func getChatViewController(inboxChat: InboxChat,
                               uiConfig: SinchSDKConfig.UIConfig?,
                               localizationConfig: SinchSDKConfig.LocalizationConfig?
    ) throws -> SinchChatViewController
    
}

public struct InboxChat: Codable, Sendable {
    
    // display model
    public var name: String
    public var text: String
    public var sendDate: Date
    
    public var avatarImage: String?
    public var status: String

    // run model
    public var chatOptions: GetChatViewControllerOptions?
    // todo delete
    public init(text: String, sendDate: Date, avatarImage: String?, status: String, options: GetChatViewControllerOptions) {
        self.text = text
        self.sendDate = sendDate
        self.avatarImage = avatarImage
        self.chatOptions = options
        self.status = status
        self.name = ""
    }
    
    init(channel: Sinch_Chat_Sdk_V1alpha2_Channel, options: GetChatViewControllerOptions? ) {
        self.name = channel.displayName
        self.text = channel.hasLastEntry ? handleIncomingMessage(channel.lastEntry)?.convertToText ?? "" : ""
        self.sendDate = Date(timeIntervalSince1970: TimeInterval(channel.updatedAt.seconds))
        self.avatarImage = nil
        self.chatOptions = options
        // TODO add status
        self.status = ""
    }
}

public extension SinchInbox {
    
    func getInboxViewController(uiConfig: SinchSDKConfig.UIConfig? = nil,
                                localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
                                options: GetChatViewControllerOptions? = nil) throws -> SinchChatViewController {
        try getInboxViewController(uiConfig: uiConfig, localizationConfig: localizationConfig, options: options)
    }

    /// Creating Inbox UI with an explicit layout. This method may throw
    /// - Parameters:
    ///   - uiConfig: Optionally ui changes might be provided with different settings.
    ///   - localizationConfig: Optionally localization might be provided with different text translation.
    ///   - options: Optionally custom chat options.
    ///   - layout: `.automatic` shows a sidebar with the selected chat beside it on regular width and a pushed
    ///     list on compact width. The returned controller can be pushed, presented (with or without a navigation
    ///     controller) or embedded. `.stack` returns the plain list that pushes the chat; it must be placed in a
    ///     `UINavigationController` by the caller.
    ///
    ///     `layout` is only honoured by the SDK's own implementation (`SinchChatSDK.shared.chat.inbox`). A custom
    ///     type conforming to `SinchInbox` (a test double, a wrapper) ignores it: this overload then calls its
    ///     `getInboxViewController(uiConfig:localizationConfig:options:)`, which decides the layout itself.
    /// - Returns: UIViewController which contains inbox UI.
    /// - Throws: SinchInboxSDKError enum with specific error.
    func getInboxViewController(uiConfig: SinchSDKConfig.UIConfig? = nil,
                                localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
                                options: GetChatViewControllerOptions? = nil,
                                layout: SinchInboxLayout) throws -> SinchChatViewController {
        guard let defaultInbox = self as? DefaultSinchInbox else {
            return try getInboxViewController(uiConfig: uiConfig, localizationConfig: localizationConfig, options: options)
        }
        return try defaultInbox.makeInboxViewController(uiConfig: uiConfig,
                                                        localizationConfig: localizationConfig,
                                                        options: options,
                                                        layout: layout)
    }
}

public enum SinchInboxSDKError: Error {
    case unavailable
}
public enum SinchInboxEvent: Sendable {
    case chatUpdated(InboxChat)
    case subcriptionFailed
}

final class DefaultSinchInbox: SinchInbox, @unchecked Sendable {

    var lastChatOptions: GetChatViewControllerOptions?
    public lazy var chatInboxEventListenerSubject = PassthroughSubject<SinchInboxEvent, Never>()

    internal var tokenProvider: ChatTokenProvider?
    internal var region: Region?

    private let pushPermissionHandler: PushNofiticationPermissionHandler
    private let chatNotificationHandler = ChatNotificationHandler()
    var apiClient: APIClient?
    private var rootCoordinator: InboxRootCoordinator?
    private var inbox: InboxViewController?

    init(pushPermissionHandler: PushNofiticationPermissionHandler) {
        self.pushPermissionHandler = pushPermissionHandler
    }

    public func getInboxViewController(uiConfig: SinchSDKConfig.UIConfig? = nil,
                                       localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
                                       options: GetChatViewControllerOptions? = nil) throws -> SinchChatViewController {
        try makeInboxViewController(uiConfig: uiConfig, localizationConfig: localizationConfig, options: options, layout: .automatic)
    }

    func makeInboxViewController(uiConfig: SinchSDKConfig.UIConfig?,
                                 localizationConfig: SinchSDKConfig.LocalizationConfig?,
                                 options: GetChatViewControllerOptions?,
                                 layout: SinchInboxLayout) throws -> SinchChatViewController {
        let capturedUIConfig = uiConfig
        let capturedLocConfig = localizationConfig
        let capturedOptions = options
        return try MainActor.assumeIsolated {
            guard let tokenProvider = self.tokenProvider, let region = self.region else {
                throw SinchChatSDKError.unavailable
            }
            guard let client = self.getOrCreateAPIClient(region: region) else {
                throw SinchChatSDKError.unavailable
            }

            self.apiClient = client
            self.lastChatOptions = capturedOptions

            let inboxDataSource = DefaultInboxDataSource(apiClient: client, tokenProvider: tokenProvider, options: capturedOptions)

            if let root = self.rootCoordinator {
                root.inboxDataSource.cancelSubscription()
            }

            let rootCordinator = DefaultInboxRootCoordinator(uiConfiguration: capturedUIConfig ?? .defaultValue,
                                                             localizationConfiguration: capturedLocConfig ?? .defaultValue,
                                                             tokenProvider: tokenProvider, pushPermissionHandler: self.pushPermissionHandler, inboxDataSource: inboxDataSource)

            self.rootCoordinator =  rootCordinator
            let inboxViewController =  rootCordinator.getRootViewController(apiClient: client, options: capturedOptions)

            switch layout {
            case .stack:
                return inboxViewController
            case .automatic:
                return rootCordinator.getAdaptiveRootViewController(inbox: inboxViewController)
            }
        }
    }

    func getInboxChats(options: GetChatViewControllerOptions?, completion: @escaping @Sendable ([InboxChat]) -> Void) {
        let capturedOptions = options
        Task { @MainActor in
            guard let tokenProvider = self.tokenProvider,
                  let region = self.region,
                  let client = self.getOrCreateAPIClient(region: region) else {
                completion([])
                return
            }
            self.lastChatOptions = capturedOptions

            let inboxDataSource = DefaultInboxDataSource(apiClient: client, tokenProvider: tokenProvider, options: capturedOptions)

            self.rootCoordinator = DefaultInboxRootCoordinator(uiConfiguration: .defaultValue,
                                                               localizationConfiguration: .defaultValue,
                                                               tokenProvider: tokenProvider,
                                                               pushPermissionHandler: self.pushPermissionHandler,
                                                               inboxDataSource: inboxDataSource)

            self.rootCoordinator?.inboxDataSource.getChannels(completion: { [weak self] result in
                switch result {
                case .success(let channels):
                    completion(channels.map {
                        InboxChat(channel: $0, options: self?.lastChatOptions)
                    })
                case .failure(let error):
                    print(error)
                    completion([])
                }
            })
        }
    }
    func subscribeToInboxChatUpdates(options: GetChatViewControllerOptions) {

        let capturedOptions = options
        Task { @MainActor in
            guard let tokenProvider = self.tokenProvider,
                  let region = self.region,
                  let client = self.getOrCreateAPIClient(region: region) else {
                self.chatInboxEventListenerSubject.send(.subcriptionFailed)
                return
            }

            self.lastChatOptions = capturedOptions

            let inboxDataSource = DefaultInboxDataSource(apiClient: client, tokenProvider: tokenProvider, options: capturedOptions)

            self.rootCoordinator = DefaultInboxRootCoordinator(uiConfiguration: .defaultValue,
                                                               localizationConfiguration: .defaultValue,
                                                               tokenProvider: tokenProvider,
                                                               pushPermissionHandler: self.pushPermissionHandler,
                                                               inboxDataSource: inboxDataSource)

            (self.rootCoordinator?.inboxDataSource as! DefaultInboxDataSource).delegate = self
            self.rootCoordinator?.inboxDataSource.subscribeForChannels(completion: { [weak self] result in

                switch result {
                case .success(let channel):
                    let opts = self?.lastChatOptions
                    self?.chatInboxEventListenerSubject.send(.chatUpdated( InboxChat(channel: channel, options: opts)))

                case .failure(let error):
                    print(error)
                    self?.chatInboxEventListenerSubject.send(.subcriptionFailed)
                }
            })
        }
    }
    func getChatViewController(
        inboxChat: InboxChat,
        uiConfig: SinchSDKConfig.UIConfig? = nil,
        localizationConfig: SinchSDKConfig.LocalizationConfig? = nil) throws -> SinchChatViewController {

        return try MainActor.assumeIsolated {
            if let root = self.rootCoordinator {
                root.inboxDataSource.cancelSubscription()
            }

            return try SinchChatSDK.shared.chat.getChatViewController(uiConfig: uiConfig ?? self.rootCoordinator?.uiConfiguration,
                                                                     localizationConfig: localizationConfig ?? self.rootCoordinator?.localizationConfiguration,
                                                                     options: inboxChat.chatOptions)
        }
    }

    func initilize() {

        //   SinchChatSDK.shared.pushNotificationHandler.registerAddressee(chatNotificationHandler)
        //    chatNotificationHandler.delegate = self
    }

    private func getOrCreateAPIClient(region: Region) -> APIClient? {
        if let apiClient {
            return apiClient
        }
        if let sharedClient = SinchChatSDK.shared.apiClient {
            apiClient = sharedClient
            return sharedClient
        }
        guard let client = Default2APIClient(region: region) else {
            return nil
        }
        apiClient = client
        return client
    }
}
extension DefaultSinchInbox : InboxDataSourceDelegate {
    nonisolated func subscriptionError() {
        Task { @MainActor in
            guard let options = self.lastChatOptions else { return }
            self.subscribeToInboxChatUpdates(options: options)
        }
    }
}
