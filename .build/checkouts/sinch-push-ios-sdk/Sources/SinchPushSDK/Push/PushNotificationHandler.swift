import Foundation
import UserNotifications

protocol PushNofiticationPermissionHandler: AnyObject {
    /// It must be called from main thread
    func askForPermissions(completion: ((SinchSDKNotificationStatus) -> Void)?)

    func checkIfPermissionIsGranted(completion: @escaping (SinchSDKNotificationStatus) -> Void)
}

protocol PushNotificationHandler: PushNofiticationPermissionHandler {
    var pushRepository: PushRepository? { get set }
    var authDataSource: AuthDataSource? { get set }

    func sendDeviceToken(token: Data)
    /// Subscribes again if the Subscribe contents changed, such as the relay state. Needs a known device token.
    func resubscribeIfNeeded()
    func unsubscribe(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void)

    func handleNotification(payload: [AnyHashable: Any]) -> IsHandled

    func handleWillPresentNotification(_ payload: [AnyHashable: Any]) -> UNNotificationPresentationOptions?

    func registerAddressee(_ service: PushNotificationAddressee)
    func removeAddressee(_ service: PushNotificationAddressee)
    func getAddressee(id: PushNotificationAddresseeName ) -> PushNotificationAddressee?
}

/// A subsystem that handles APNs notifications, registered on ``SinchPushSDK/register(addressee:)``.
///
/// The chat SDK registers itself as ``PushNotificationAddresseeName/chat`` so a chat push opens the chat and is not
/// presented twice.
public protocol PushNotificationAddressee {
    /// The name the addressee is registered under. ``PushNotificationAddresseeName/chat`` is the only one today.
    var id: PushNotificationAddresseeName { get }

    /// - Returns: `true` when the payload belongs to this addressee and it handled it.
    func handleNotification(payload: [AnyHashable: Any]) -> IsHandled

    /// - Returns: The presentation options for the payload, or `nil` when it does not belong to this addressee.
    func handleWillPresentNotification(_ payload: [AnyHashable: Any]) -> UNNotificationPresentationOptions?
}

/// The addressees push knows about.
public enum PushNotificationAddresseeName: String, Sendable {
    /// The chat SDK.
    case chat
}

final class DefaultPushNotificationHandler: PushNotificationHandler, @unchecked Sendable {

    private let pushDeviceTokenCoordinator: PushDeviceTokenCoordinator
    private let deviceInfoProvider: DeviceInfoProviding
    private let subscribesOnRepositoryChange: Bool

    /// Written on the main thread by `setIdentity`, and every trigger that reads it runs there.
    var pushRepository: PushRepository? {
        didSet {
            if subscribesOnRepositoryChange {
                sendTokenIfNeeded()
            }
        }
    }
    var authDataSource: AuthDataSource? {
        get { pushDeviceTokenCoordinator.authDataSource }
        set { pushDeviceTokenCoordinator.authDataSource = newValue }
    }

    private var notificationCenter: UNUserNotificationCenter {
        return UNUserNotificationCenter.current()
    }

    private var pushServices: [PushNotificationAddresseeName: PushNotificationAddressee] = [:]

    /// - Parameter subscribesOnRepositoryChange: `false` for the logout path, which must not race a Subscribe.
    init(userDefaults: UserDefaults = UserDefaults.standard,
         deviceInfoProvider: DeviceInfoProviding = SystemDeviceInfoProvider.live(),
         subscribesOnRepositoryChange: Bool = true) {
        self.pushDeviceTokenCoordinator = PushDeviceTokenCoordinator(userDefaults: userDefaults)
        self.deviceInfoProvider = deviceInfoProvider
        self.subscribesOnRepositoryChange = subscribesOnRepositoryChange
    }
    
    func getAddressee(id: PushNotificationAddresseeName ) -> PushNotificationAddressee? {
        return pushServices[id]
    }

    func registerAddressee(_ service: PushNotificationAddressee) {
        pushServices[service.id] = service
    }

    func removeAddressee(_ service: PushNotificationAddressee) {
        pushServices[service.id] = nil
    }

    func sendDeviceToken(token: Data) {
        pushDeviceTokenCoordinator.setTokenToSend(deviceToken: token)
        sendTokenIfNeeded()
    }
    
    func resubscribeIfNeeded() {
        sendTokenIfNeeded()
    }

    func unsubscribe(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        guard let token = pushDeviceTokenCoordinator.getLastToken() else {
            completion(.success(()))
            return
        }
        guard let pushRepository else {
            // The completion must still run, or logout never finishes.
            completion(.success(()))
            return
        }
        // Read before the auth token is deleted, since that changes the hash.
        let identityHash = authDataSource?.identityHashValue
        // Captured strongly, so the clear still happens after a short-lived handler is gone.
        pushRepository.unsubscribe(token) { [coordinator = pushDeviceTokenCoordinator] result in
            // The repository reports transport errors as success, so this is not backend-confirmed.
            if case .success = result, let identityHash {
                coordinator.clearSentRecord(for: identityHash)
            }
            completion(result)
        }
    }

    func askForPermissions(completion: ((SinchSDKNotificationStatus) -> Void)?) {
        checkIfPermissionIsGranted { [weak self] status in
            guard let self = self else {
                completion?(status)
                return
            }

            switch status {
            case .notDetermined:
                self.notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    completion?(granted ? .granted : .denied)
                }
            case .granted:
                completion?(status)
            case .denied:
                self.showAlertForGoingToSettings()
            }
        }
    }

    func checkIfPermissionIsGranted(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        notificationCenter.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .ephemeral:
                completion(.granted)
            case .denied:
                completion(.denied)
            case .notDetermined:
                completion(.notDetermined)
            default:
                completion(.notDetermined)
            }
        }
    }

    func handleNotification(payload: [AnyHashable : Any]) -> IsHandled {
        for service in pushServices {
            if service.value.handleNotification(payload: payload) {
                return true
            }
        }
        return false
    }

    func handleWillPresentNotification(_ payload: [AnyHashable : Any]) -> UNNotificationPresentationOptions? {
        for service in pushServices {
            if let options = service.value.handleWillPresentNotification(payload) {
                return options
            }
        }

        return nil
    }

    // MARK: - Private

    private func showAlertForGoingToSettings() {
        DispatchQueue.main.async {
            print("TODO: Go to settings")
        }
    }

    private func sendTokenIfNeeded() {
        guard let repository = pushRepository, let identityHash = pushDeviceTokenCoordinator.subscribableIdentityHash else {
            return
        }

        // Without an installation id, Subscribe carries no device fields. A later readable Keychain re-subscribes.
        let deviceInfo = deviceInfoProvider.current().subscribable

        guard let token = pushDeviceTokenCoordinator.getTokenToSend(deviceInfo: deviceInfo, for: identityHash) else {
            return
        }

        if deviceInfo == nil {
            Logger.warning("installation id unavailable, subscribing without device info")
        }
        Logger.verbose("sending device token")
        repository.sendDeviceToken(token: token, deviceInfo: deviceInfo) { [weak self, coordinator = pushDeviceTokenCoordinator] result in
            switch result {
            case .success:
                coordinator.recordSubscription(token: token, deviceInfo: deviceInfo, for: identityHash)
                Logger.info("device token updated")
                // Rechecks on main, so a change made during this Subscribe is sent next.
                DispatchQueue.main.async { [weak self] in
                    self?.sendTokenIfNeeded()
                }
            case .failure(let error):
                Logger.warning("device token cannot be updated")
                Logger.verbose(error)
            }
        }
    }
}
