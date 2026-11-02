import Foundation
import UserNotifications
import Combine

public typealias IsHandled = Bool

@MainActor
public protocol SinchPush {
    
    /// Sends device token to specific identity.
    /// - Parameters:
    ///     - token: token which is coming from method: `application(_:, didRegisterForRemoteNotificationsWithDeviceToken:)`
    func sendDeviceToken(_ token: Data)

    /// Handles a notification payload. Call it from `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.
    /// A message the relay socket already delivered is handled without being shown again.
    /// - Returns: Whether the notification belongs to Sinch Chat SDK.
    func handleNotification(_ payload: [AnyHashable: Any]) -> IsHandled

    /// Handles a notification payload and, before returning, reports the delivery to Sinch. Call it from
    /// `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` and call the fetch completion handler
    /// after it returns, so a notification that wakes the app in the background is reported before the app is
    /// suspended. The call returns at most 20 seconds in total after it was made, the restore of the session and
    /// the hand-off to the upload included, and what could not be sent is kept for later.
    ///
    /// This also reports the deliveries of a cold launch in the background, when `setIdentity` has succeeded
    /// at least once and `initialize` ran at launch. The session of the last identity is restored here when the
    /// launch did not already do so. Nothing is reported before the first unlock after a device
    /// restart, as the Keychain and `UserDefaults` cannot be read yet.
    /// - Returns: Whether the notification belongs to Sinch Chat SDK.
    func handleBackgroundNotification(_ payload: [AnyHashable: Any]) async -> IsHandled

    /// Forwards `application(_:handleEventsForBackgroundURLSession:completionHandler:)`. The SDK uploads delivery
    /// reports with background `URLSession`s (also for the Notification Service Extension), and the system wakes the
    /// app to tell it they finished. Call this from that app delegate method; when it returns `true` the SDK has
    /// taken the completion handler and calls it once it has processed the events, otherwise handle the session yourself.
    /// - Parameters:
    ///   - identifier: The session identifier the system passed.
    ///   - completionHandler: The completion handler the system passed.
    /// - Returns: Whether the session belongs to the SDK.
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) -> Bool

    /// Handles notification response payload.
    /// - Returns: Information whenether the notification belongs to Sinch Chat SDK or not.
    func handleNotificationResponse(_ notificationResponse: UNNotificationResponse) -> IsHandled
    
    /// Handles a notification that is about to be presented.
    /// Returns `[]` for an APNs copy of a message the relay socket already delivered.
    /// - Returns: Presentation options, or `nil` when the notification is not a Sinch notification.
    func handleWillPresentNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions?

    /// Asks user for notification permission.
    /// - Parameters:
    ///     - completion: Contains information about notification status.
    func askNotificationPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void)

    /// Checks notification permission status.
    /// - Parameters:
    ///     - completion: Contains information about notification status.
    func checkPushPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void)

    /// Asks user for notification permission.
    /// - Returns: Contains information about notification status.
    @available(iOS 13.0, *)
    func askNotificationPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never>

    /// Checks notification permission status.
    /// - Returns: Contains information about notification status.
    @available(iOS 13.0, *)
    func checkPushPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never>

    /// The push relay state. The relay is a WebSocket open only while the app is in the foreground.
    /// It starts after `setIdentity` succeeds, when `AppConfig.relay` is `.enabled` and the region has a relay URL.
    var socketState: SinchPushSocketState { get }

    /// Publishes every change of ``socketState`` on the main thread, and replays the current value.
    var socketStatePublisher: AnyPublisher<SinchPushSocketState, Never> { get }

    /// Publishes each message received over the relay socket once, on the main thread. Does not replay.
    /// The same message is also posted as a notification. See ``handleWillPresentNotification(_:)``.
    var socketMessagePublisher: AnyPublisher<SinchPushSocketMessage, Never> { get }

    /// Reports what happened to a relay notification. Reports are queued and sent once the relay is connected,
    /// so the call is safe in the background. Reports are dropped while no identity owns them.
    ///
    /// The SDK reports DELIVERED on receipt and DISPLAYED when it posts the notification, not when the user sees it.
    /// - Parameters:
    ///     - messageId: ``SinchPushSocketMessage/id`` of the message.
    ///     - status: What happened to the notification.
    func reportStatus(messageId: String, status: SinchPushMessageStatus)

    /// The installation identifier used by the push relay and push API. `nil` when it cannot be read or stored.
    var installationId: String? { get }

    /// Turns the push relay on or off at runtime, taking effect immediately. Persisted; on by default.
    ///
    /// Turning it off closes the socket and keeps it closed, and pushes then arrive through APNs only. Reports stay
    /// queued until the relay runs again. The switch is read at `setIdentity`, so it also applies before one.
    /// - Parameter enabled: `false` to turn the relay off. Setting the current value does nothing.
    func setRelayEnabled(_ enabled: Bool)

    /// The runtime switch set by ``setRelayEnabled(_:)``. Whether a socket runs is reported by ``socketState``.
    var isRelayEnabled: Bool { get }

}

/// The relay API was added to ``SinchPush`` after its first release. These defaults keep existing conformers compiling.
public extension SinchPush {
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) -> Bool {
        false
    }

    func handleBackgroundNotification(_ payload: [AnyHashable: Any]) async -> IsHandled {
        handleNotification(payload)
    }

    var socketState: SinchPushSocketState {
        SinchPushSocketState(status: .idle, relayEnabled: false,
                             disabledReason: "not supported by this SinchPush implementation")
    }

    var socketStatePublisher: AnyPublisher<SinchPushSocketState, Never> {
        Just(socketState).eraseToAnyPublisher()
    }

    var socketMessagePublisher: AnyPublisher<SinchPushSocketMessage, Never> {
        Empty().eraseToAnyPublisher()
    }

    func reportStatus(messageId: String, status: SinchPushMessageStatus) {}

    var installationId: String? { nil }

    func setRelayEnabled(_ enabled: Bool) {}

    var isRelayEnabled: Bool { true }
}

@MainActor
final class DefaultSinchPush: SinchPush {
    private let pushNotificationhandler: PushNotificationHandler
    private let inAppPresenter: InAppMessagePresenting
    private let socketManager: PushSocketManager
    /// Cross-channel dedupe of APNs notifications, over the socket's registry.
    private let decider: PushPresentationDecider
    private let relaySettings: RelaySettings
    private let deliveryReporter: DeliveryReporting?
    /// Gives the reporter the session of the last identity when it has none, as a background launch has before `setIdentity`.
    private let restoreDeliveryReportSession: (@Sendable () async -> Void)?
    private let reportUploaders: ReportUploaders?

    init(pushNotificationHandler: PushNotificationHandler,
         inAppPresenter: InAppMessagePresenting,
         socketManager: PushSocketManager,
         relaySettings: RelaySettings,
         deliveryReporter: DeliveryReporting? = nil,
         restoreDeliveryReportSession: (@Sendable () async -> Void)? = nil,
         reportUploaders: ReportUploaders? = nil) {
        self.reportUploaders = reportUploaders
        self.relaySettings = relaySettings
        self.deliveryReporter = deliveryReporter
        self.restoreDeliveryReportSession = restoreDeliveryReportSession
        self.pushNotificationhandler = pushNotificationHandler
        self.inAppPresenter = inAppPresenter
        self.socketManager = socketManager
        self.decider = PushPresentationDecider(registry: socketManager.registry, deliveryReporter: deliveryReporter)
    }

    var socketState: SinchPushSocketState {
        socketManager.state
    }

    var socketStatePublisher: AnyPublisher<SinchPushSocketState, Never> {
        socketManager.stateSubject.eraseToAnyPublisher()
    }

    var socketMessagePublisher: AnyPublisher<SinchPushSocketMessage, Never> {
        socketManager.messageSubject.eraseToAnyPublisher()
    }

    func reportStatus(messageId: String, status: SinchPushMessageStatus) {
        socketManager.reportStatus(messageId: messageId, status: status)
    }

    var installationId: String? {
        socketManager.installationId
    }

    func sendDeviceToken(_ token: Data) {
        pushNotificationhandler.sendDeviceToken(token: token)
    }

    var isRelayEnabled: Bool {
        relaySettings.isEnabled
    }

    func setRelayEnabled(_ enabled: Bool) {
        guard relaySettings.setEnabled(enabled) else { return }
        Logger.info("push relay \(enabled ? "enabled" : "disabled") at runtime")
        // The socket first, so the Subscribe that follows sees the final background_service.
        socketManager.relayEnabledDidChange()
        pushNotificationhandler.resubscribeIfNeeded()
    }

    /// A notification handed over by the host's `didReceiveRemoteNotification`.
    func handleNotification(_ payload: [AnyHashable : Any]) -> IsHandled {
        Logger.debug(payload)

        if decider.decide(userInfo: payload, requestIdentifier: nil) == .suppress {
            // The relay socket delivered this message already: the APNs copy shows nothing again.
            Logger.verbose("notification already delivered over the relay socket, not handling it again")
            return true
        }

        if inAppPresenter.present(userInfo: payload) {
            return true
        }
        
        return pushNotificationhandler.handleNotification(payload: payload)
    }

    func handleBackgroundNotification(_ payload: [AnyHashable: Any]) async -> IsHandled {
        // The wake's budget starts now: the restore and the hand-off are part of it.
        let deadline = ContinuousClock.now + DeliveryReporter.backgroundWakeDeadline
        // What the extension could not upload is reported by the app.
        deliveryReporter?.drainPendingDeliveries()
        let handled = handleNotification(payload)
        // `initialize` restores the session of a launch in the background only, and it may have found nothing to read.
        await restoreDeliveryReportSession?()
        await deliveryReporter?.flushForBackgroundWake(until: deadline)
        return handled
    }

    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) -> Bool {
        // The system wants the handler called on the main thread; the uploader dispatches there.
        nonisolated(unsafe) let handler = completionHandler
        return reportUploaders?.handleEvents(identifier: identifier, completionHandler: { handler() }) ?? false
    }

    func handleWillPresentNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions? {
        let content = notification.request.content
        return handleWillPresent(userInfo: content.userInfo,
                                 requestIdentifier: notification.request.identifier,
                                 hasSound: content.sound != nil,
                                 categoryIdentifier: content.categoryIdentifier)
    }

    func handleNotificationResponse(_ notificationResponse: UNNotificationResponse) -> IsHandled {
        let request = notificationResponse.notification.request
        return handleResponse(userInfo: request.content.userInfo,
                              requestIdentifier: request.identifier,
                              actionIdentifier: notificationResponse.actionIdentifier,
                              categoryIdentifier: request.content.categoryIdentifier)
    }

    // MARK: - Routing

    /// Takes the fields of a `UNNotification`, which tests cannot construct. A socket notification is recognised by
    /// its `source` and its category together, so a remote payload claiming `source: socket` stays an APNs push.
    func handleWillPresent(userInfo: [AnyHashable: Any],
                           requestIdentifier: String,
                           hasSound: Bool,
                           categoryIdentifier: String? = nil) -> UNNotificationPresentationOptions? {
        Logger.debug(userInfo)

        if PushMessageIdentity.isSocketSourced(userInfo: userInfo, categoryIdentifier: categoryIdentifier) {
            guard let options = pushNotificationhandler.handleWillPresentNotification(userInfo) else {
                return hasSound ? SocketPresentation.alerting : SocketPresentation.silent
            }
            return hasSound ? options : SocketPresentation.silenced(options)
        }

        if decider.decide(userInfo: userInfo, requestIdentifier: requestIdentifier) == .suppress {
            Logger.verbose("notification already delivered over the relay socket, presenting nothing")
            return []
        }
        return pushNotificationhandler.handleWillPresentNotification(userInfo)
    }

    func handleResponse(userInfo: [AnyHashable: Any],
                        requestIdentifier: String,
                        actionIdentifier: String,
                        categoryIdentifier: String? = nil) -> IsHandled {
        Logger.debug(userInfo)

        if PushMessageIdentity.isSocketSourced(userInfo: userInfo, categoryIdentifier: categoryIdentifier) {
            if actionIdentifier == UNNotificationDismissActionIdentifier {
                // Only a dismissal reports. A tap falls through to the host.
                if let id = PushMessageIdentity.socketMessageId(userInfo: userInfo, requestIdentifier: requestIdentifier) {
                    socketManager.reportStatus(messageId: id, status: .dismissed)
                }
                return true
            }
        } else {
            _ = decider.decide(userInfo: userInfo, requestIdentifier: requestIdentifier)
        }
        return pushNotificationhandler.handleNotification(payload: userInfo)
    }

    func checkPushPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        pushNotificationhandler.checkIfPermissionIsGranted(completion: completion)
    }

    @available(iOS 13.0, *)
    func checkPushPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never> {

        let subject = PassthroughSubject<SinchSDKNotificationStatus, Never>()

        checkPushPermission { status in
            subject.send(status)
        }

        return subject.eraseToAnyPublisher()
    }

    @available(iOS 13.0, *)
    func askNotificationPermission() -> AnyPublisher<SinchSDKNotificationStatus, Never> {

        let subject = PassthroughSubject<SinchSDKNotificationStatus, Never>()

        askNotificationPermission { status in
            subject.send(status)
        }

        return subject.eraseToAnyPublisher()
    }

    func askNotificationPermission(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        pushNotificationhandler.askForPermissions { status in
            completion(status)
        }
    }
}

public enum SinchSDKNotificationStatus: Sendable, Equatable {
    /// Notification permission is already granted.
    case granted
    /// Notification permiossion was previously asked but now is denied, user must change it in settings.
    case denied
    /// Notification permission has not been asked yes.
    case notDetermined
}
