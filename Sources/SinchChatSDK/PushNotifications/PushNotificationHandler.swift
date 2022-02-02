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

    func handleNotification(payload: [AnyHashable: Any]) -> IsHandled

    func handleWillPresentNotification(_ payload: [AnyHashable: Any]) -> UNNotificationPresentationOptions?

    func registerAddressee(_ service: PushNotificationAddressee)
    func removeAddressee(_ service: PushNotificationAddressee)
}

protocol PushNotificationAddressee {
    var id: PushNotificationAddresseeName { get }

    func handleNotification(payload: [AnyHashable: Any]) -> IsHandled
    func handleWillPresentNotification(_ payload: [AnyHashable: Any]) -> UNNotificationPresentationOptions?
}

enum PushNotificationAddresseeName: String {
    case chat
}

final class DefaultPushNotificationHandler: PushNotificationHandler {

    private let pushDeviceTokenCoordinator: PushDeviceTokenCoordinator

    var pushRepository: PushRepository? {
        didSet {
            sendTokenIfNeeded()
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

    init(userDefaults: UserDefaults = UserDefaults.standard) {
        self.pushDeviceTokenCoordinator = PushDeviceTokenCoordinator(userDefaults: userDefaults)
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
        guard let token = pushDeviceTokenCoordinator.getTokenToSend(), let repository = pushRepository else {
            return
        }

        Logger.verbose("sending device token")
        repository.sendDeviceToken(token: token) { [weak self] result in
            switch result {
            case .success:
                self?.pushDeviceTokenCoordinator.tokenDidSent()
                Logger.info("device token updated")
            case .failure(let error):
                Logger.warning("device token cannot be updated")
                Logger.verbose(error)
            }
        }
    }
}
