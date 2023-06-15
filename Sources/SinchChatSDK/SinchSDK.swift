import UIKit

public final class SinchChatSDK {
    
    /// Contains all methods regarding push notifications. To be able to use push notifications you need to call `setIdentity` method.
    private(set) public lazy var push: SinchPush = DefaultSinchPush(pushNotificationHandler: pushNotificationHandler)
    
    /// Contains all methods connected with Chat. Before using the chat you should use method `setIdentity`.
    public var chat: SinchChat { _chat }
    
    public static let shared = SinchChatSDK()
    
    let pushNotificationHandler: PushNotificationHandler = DefaultPushNotificationHandler()
    lazy var _chat = DefaultSinchChat(pushPermissionHandler: pushNotificationHandler)
    
    var disabledFeatures: Set<SinchEnabledFeatures> = [.sendVideoMessageFromGallery]
    
    var options: SinchInitializeOptions?
    private(set) var config: SinchSDKConfig.AppConfig?
    private var authDataSource: AuthDataSource? {
        didSet {
            pushNotificationHandler.authDataSource = authDataSource
        }
    }
    
    private init() {}
    
    /// Initialization of SinchSDK
    /// - Parameters:
    ///   - Parameter options: Run sdk with options f.e: using sandbox push notification environment.
    public func initialize(_ options: SinchInitializeOptions = SinchInitializeOptions.standard) {
        if options.pushNotificationsMode != .off {
            registerForRemoteNotificationIfNeeded()
            setPushRepositoryIfPossible()
        }
        self.options = options
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
                            completion: ((Result<Void, SinchSDKIdentityError>) -> Void)? = nil) {
        self.config = config
        authDataSource = DefaultAuthDataSource(authRepository: DefaultAuthRepository(config: config),
                                               authStorage: DefaultAuthStorage(config: config))
        
        authDataSource?.generateToken(config: config, identity: identity, completion: { result in
            self.setPushRepositoryIfPossible()
            
            switch result {
            case .failure:
                completion?(.failure(.internalError))
            case .success:
                completion?(.success(()))
            }
        })
        
        reinitializeChat()
        
    }
    
    /// Removes identity of the user.
    /// This method is logging out user. It removes token and other user data from the app.
    public func removeIdentity(_ completion: ((Result<Void, Error>) -> Void)?) {
        
        guard let authDataSource = authDataSource else {
            completion?(.success(()))
            return
        }
        let currentAuthDataSource = authDataSource
        let tempPushNottifications = DefaultPushNotificationHandler()
        tempPushNottifications.authDataSource = authDataSource
        tempPushNottifications.pushRepository = DefaultPushRepository(region: config?.region ?? .EU1,
                                                                      authDataSource: authDataSource)
        tempPushNottifications.unsubscribe { result in
            switch result {
            case .success:
                currentAuthDataSource.deleteToken()
                SinchChatSDK.shared.eventListenerSubject.send(.didRemoveIdentity)

                completion?(.success(()))
            case .failure(let error):
                completion?(.failure(error))
            }
        }
    }
    // MARK: - Private
    
    private func registerForRemoteNotificationIfNeeded() {
        if !UIApplication.shared.isRegisteredForRemoteNotifications {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    private func setPushRepositoryIfPossible() {
        guard let authDataSource = authDataSource, authDataSource.isLoggedIn, let config = config else {
            return
        }
        Logger.verbose("--------- SET PUSH REPOSITORY")
        pushNotificationHandler.pushRepository = DefaultPushRepository(region: config.region,
                                                                       authDataSource: authDataSource)
    }
    
    private func reinitializeChat() {
        guard let authDataSource = authDataSource, let config = config else {
            return
        }
        
        _chat.initilize(region: config.region, authDataSource: authDataSource)
    }
    
    static var version: String {
        "0.1.0" + (SinchChatSDK.shared.options?.pushNotificationsMode == .prod ? "-prod" : "-dev")
    }
}

public enum SinchSDKIdentity: Codable, Equatable {
    /// Creates anonymous session with random user identifier.
    case anonymous
    /// Creates session with specific user identifier.
    case selfSigned(userId: String, secret: String)
}

public enum SinchSDKIdentityError: Error {
    /// Our internal issue.
    case internalError
    /// Secret is invalid. Make sure it is generated correctly.
    case invalidSecret
}

public struct SinchInitializeOptions {
    public var pushNotificationsMode: SinchPushNotificationsMode = .prod
    
    public static let standard = SinchInitializeOptions(pushNotificationMode: .prod)
    
    public init(pushNotificationMode: SinchPushNotificationsMode) {
        self.pushNotificationsMode = pushNotificationMode
    }
}

public enum SinchPushNotificationsMode {
    case prod
    case sandbox
    case off
    
}
public enum SinchEnabledFeatures {
    case sendImageMessageFromGallery
    case sendVideoMessageFromGallery
    case sendVoiceMessage
    case sendLocationSharingMessage
    case sendImageFromCamera
    
}
