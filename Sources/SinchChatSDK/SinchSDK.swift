import UIKit
import Combine
@_spi(SinchChat) import SinchPushSDK

public final class SinchChatSDK: @unchecked Sendable {

    /// Contains all methods regarding push notifications. To be able to use push notifications you need to call `setIdentity` method.
    ///
    /// Push lives in `SinchPushSDK`. Chat re-exports it, and this forwards, so existing integrations keep calling
    /// `SinchChatSDK.shared.push`.
    public var push: SinchPush {
        SinchPushSDK.shared.push
    }

    /// Contains all methods connected with Chat. Before using the chat you should use method `setIdentity`.
    public var chat: SinchChat { _chat }

    public static let shared = SinchChatSDK()

    lazy var _chat = DefaultSinchChat(pushPermissionHandler: pushPermissionHandler)

    public var disabledFeatures: Set<SinchEnabledFeatures> = []

    var options: SinchInitializeOptions?

    /// The config of the latest identity. Only `SinchPushSDK` reads its fields: they are internal to that module, so
    /// chat keeps it solely as the marker that an identity was configured, and takes the region from the push token.
    private(set) var config: SinchSDKConfig.AppConfig?

    /// The identity and token state of the push SDK, for the chat RPCs.
    var tokenProvider: ChatTokenProvider? {
        didSet {
            _chat.tokenProvider = tokenProvider
        }
    }

    /// The region of the latest identity, for the chat gRPC host.
    var region: Region? {
        didSet {
            _chat.region = region
        }
    }

    var apiClient: APIClient? {
        didSet {
            _chat.apiClient = apiClient
        }
    }

    public var additionalMetadata: SinchMetadataArray = []
    public lazy var eventListenerSubject = PassthroughSubject<SinchPluginEvent, Never>()
    public lazy var customMessageTypeHandlers: [(_ model: Message) -> Message?] = []
    public lazy var customMessageTypeHandlersAsync: [(Message, @escaping (Message?) -> Void) -> Void] = []

    private let pushPermissionHandler = DefaultPushPermissionHandler()

    /// Initialization of SinchSDK
    /// - Parameters:
    ///   - Parameter options: Run sdk with options f.e: using sandbox push notification environment.
    public func initialize(_ options: SinchInitializeOptions = SinchInitializeOptions.standard) {
        self.options = options

        // Push brings the identity, APNs, the relay, delivery reports and the in-app alerts.
        SinchPushSDK.shared.initialize(
            options: SinchPushInitializeOptions(environment: options.pushNotificationsMode.pushEnvironment,
                                                appGroup: options.appGroup)
        )
        // Chat handles its own payloads as a registered addressee of the push APNs handler.
        _chat.initilize()

        if options.plugins.isEmpty == false {
            options.plugins.forEach({ $0.initialize(methods: self) })
        }
    }

    /// Sets identity of the user.
    /// This method must be called `as soon as` we can authorize the user.
    /// Calling this method once again causes the token will be `regenerated`.
    /// If the type of token is different than current one. Example: anonymous vs signed -> token `will be` regenerated.
    /// - Parameters:
    ///   - Parameter config: Configuration of sdk.
    ///   - identity: The way of user authorization.
    ///   - completion: Callback with result of user authorization.
    public func setIdentity(with config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity,
                            completion: (@Sendable (Result<Void, SinchSDKIdentityError>) -> Void)? = nil) {
        SinchPushSDK.shared.setIdentity(with: config, identity: identity) { [weak self] result in
            guard case .success = result else {
                completion?(result)
                return
            }
            guard let self else {
                completion?(result)
                return
            }
            self.config = config
            let provider = SinchPushSDK.shared.tokenProvider
            self.tokenProvider = provider
            if let region = provider.currentRegion {
                // A new identity can point at another region: replace the chat channel, as `setIdentity` always did.
                self.region = region
                if let client = Default2APIClient(region: region) {
                    self.apiClient = client
                }
            }
            if let token = provider.currentAuthorization {
                Self.shared.eventListenerSubject.send(.didSetIdentity(token))
            }
            self.reinitializeChat()

            completion?(.success(()))
        }
    }

    /// Removes identity of the user.
    /// This method is logging out user. It removes token and other user data from the app.
    public func removeIdentity(_ completion: (@Sendable (Result<Void, Error>) -> Void)?) {
        SinchPushSDK.shared.removeIdentity { result in
            if case .success = result {
                SinchChatSDK.shared.eventListenerSubject.send(.didRemoveIdentity)
            }
            completion?(result)
        }
    }

    private func reinitializeChat() {
        _chat.initilize()
    }

    /// The version chat reports in the metadata of its RPCs. Push reports its own.
    static var version: String {
        "2.0.0"
    }
}

public struct SinchInitializeOptions: Sendable {
    public var pushNotificationsMode: SinchPushNotificationsMode = .prod
    public var plugins: [SinchPlugin] = []
    /// The App Group the app shares with its Notification Service Extension. Set it to let the extension report
    /// the delivery of a push (see `Documentation/NotificationServiceExtension.md`): the SDK then copies the access
    /// token and the push API URL, never the identity secret, into the group's container. `nil` (the default)
    /// shares nothing.
    public var appGroup: String?

    public static let standard = SinchInitializeOptions(pushNotificationMode: .prod)

    public init(pushNotificationMode: SinchPushNotificationsMode, plugins: [SinchPlugin] = [], appGroup: String? = nil) {
        self.pushNotificationsMode = pushNotificationMode
        self.plugins = plugins
        self.appGroup = appGroup
    }
}

public enum SinchPushNotificationsMode: Sendable {
    case prod
    case sandbox
    case off

    /// The push SDK's environment for this mode.
    var pushEnvironment: SinchPushEnvironment {
        switch self {
        case .prod: return .prod
        case .sandbox: return .sandbox
        case .off: return .off
        }
    }
}

public enum SinchEnabledFeatures {
    case sendImageMessageFromGallery
    case sendVideoMessageFromGallery
    case sendVoiceMessage
    case sendLocationSharingMessage
    case sendImageFromCamera
    case sendVideoMessageFromCamera
    case sendDocuments

}
