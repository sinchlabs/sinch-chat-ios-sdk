import UIKit
import Combine
public protocol SinchInbox {
    
    /// Inbox event listener. It will be called when new event occurs.
    ///
    var chatInboxEventListenerSubject: PassthroughSubject<SinchInboxEvent, Never> { get }

    /// Creating Inbox UI. This method may throw
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
    func getInboxChats(options: GetChatViewControllerOptions?, completion: @escaping ([InboxChat]) -> Void)

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

public struct InboxChat: Codable {
    
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
}

public enum SinchInboxSDKError: Error {
    case unavailable
}
public enum SinchInboxEvent {
    case chatUpdated(InboxChat)
    case subcriptionFailed
}

final class DefaultSinchInbox: SinchInbox {

    var lastChatOptions: GetChatViewControllerOptions?
    public lazy var chatInboxEventListenerSubject = PassthroughSubject<SinchInboxEvent, Never>()

    internal var authDataSource: AuthDataSource?
    internal var region: Region?

    private let pushPermissionHandler: PushNofiticationPermissionHandler
    private let chatNotificationHandler = ChatNotificationHandler()
    private var apiClient: APIClient?
    private var rootCoordinator: InboxRootCoordinator?
    private var inbox: InboxViewController?

    init(pushPermissionHandler: PushNofiticationPermissionHandler) {
        self.pushPermissionHandler = pushPermissionHandler
    }

    public func getInboxViewController(uiConfig: SinchSDKConfig.UIConfig? = nil,
                                       localizationConfig: SinchSDKConfig.LocalizationConfig? = nil,
                                       options: GetChatViewControllerOptions? = nil) throws -> SinchChatViewController {

        guard let authDataSource = authDataSource, let region = region else {
            throw SinchChatSDKError.unavailable
        }
        guard let client = DefaultAPIClient(region: region) else {
            throw SinchChatSDKError.unavailable
        }
        
        apiClient = client
        lastChatOptions = options

        let inboxDataSource = DefaultInboxDataSource(apiClient: apiClient!, authDataSource: authDataSource, options: options)

        if let root = self.rootCoordinator {
            root.inboxDataSource.cancelSubscription()
        }

        let rootCordinator = DefaultInboxRootCoordinator(uiConfiguration: uiConfig ?? .defaultValue,
                                                         localizationConfiguration: localizationConfig ?? .defaultValue,
                                                         authDataSource: authDataSource, pushPermissionHandler: pushPermissionHandler, inboxDataSource: inboxDataSource)

        self.rootCoordinator =  rootCordinator
        let inboxViewController =  rootCordinator.getRootViewController(apiClient: client, options: options)

        return inboxViewController

    }

    func getInboxChats(options: GetChatViewControllerOptions?, completion: @escaping ([InboxChat]) -> Void) {
        guard let authDataSource = authDataSource,
              let region = region,
              let client = DefaultAPIClient(region: region) else {
            return
        }
        lastChatOptions = options

        let inboxDataSource = DefaultInboxDataSource(apiClient: client, authDataSource: authDataSource, options: options)

        self.rootCoordinator = DefaultInboxRootCoordinator(uiConfiguration: .defaultValue,
                                                           localizationConfiguration: .defaultValue,
                                                           authDataSource: authDataSource,
                                                           pushPermissionHandler: pushPermissionHandler,
                                                           inboxDataSource: inboxDataSource)

        rootCoordinator?.inboxDataSource.getChannels(completion: { result in

            switch result {
            case .success(let channels):

                completion(channels.map {
                    InboxChat(channel: $0, options: options)
                })
            case .failure(let error):
                print(error)
                completion([])
            }
        })
    }
    func subscribeToInboxChatUpdates(options: GetChatViewControllerOptions) {

        guard let authDataSource = authDataSource, let region = region, let client = DefaultAPIClient(region: region) else {
            chatInboxEventListenerSubject.send(.subcriptionFailed)
            return
        }

        lastChatOptions = options

        let inboxDataSource = DefaultInboxDataSource(apiClient: client, authDataSource: authDataSource, options: options)

        self.rootCoordinator = DefaultInboxRootCoordinator(uiConfiguration: .defaultValue,
                                                           localizationConfiguration: .defaultValue,
                                                           authDataSource: authDataSource,
                                                           pushPermissionHandler: pushPermissionHandler,
                                                           inboxDataSource: inboxDataSource)

        (self.rootCoordinator?.inboxDataSource as! DefaultInboxDataSource).delegate = self
        rootCoordinator?.inboxDataSource.subscribeForChannels(completion: { result in

            switch result {
            case .success(let channel):

                self.chatInboxEventListenerSubject.send(.chatUpdated( InboxChat(channel: channel, options: options)))

            case .failure(let error):
                print(error)
                self.chatInboxEventListenerSubject.send(.subcriptionFailed)
            }
        })
    }
    func getChatViewController(
        inboxChat: InboxChat,
        uiConfig: SinchSDKConfig.UIConfig? = nil,
        localizationConfig: SinchSDKConfig.LocalizationConfig? = nil) throws -> SinchChatViewController {

        if let root = self.rootCoordinator {
                root.inboxDataSource.cancelSubscription()
            }

            return try SinchChatSDK.shared.chat.getChatViewController(uiConfig: uiConfig ?? rootCoordinator?.uiConfiguration,
                                                                  localizationConfig: localizationConfig ?? rootCoordinator?.localizationConfiguration,
                                                                      options: inboxChat.chatOptions)

        }
    
    func initilize() {

        //   SinchChatSDK.shared.pushNotificationHandler.registerAddressee(chatNotificationHandler)
        //    chatNotificationHandler.delegate = self
    }
}
extension DefaultSinchInbox : InboxDataSourceDelegate {
    func subscriptionError() {
        subscribeToInboxChatUpdates(options: lastChatOptions!)
    }
}
