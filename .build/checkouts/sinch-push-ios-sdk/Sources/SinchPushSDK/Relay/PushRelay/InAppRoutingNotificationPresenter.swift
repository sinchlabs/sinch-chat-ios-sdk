import Foundation

/// Offers relay messages to the in-app UI on the main actor, and posts the rest through `inner`.
/// A message shown in the app counts as DISPLAYED.
final class InAppRoutingNotificationPresenter: NotificationPresenting, @unchecked Sendable {
    private let inner: NotificationPresenting
    private let showInApp: @MainActor @Sendable ([String: String]) -> Bool

    init(inner: NotificationPresenting, showInApp: @escaping @MainActor @Sendable ([String: String]) -> Bool) {
        self.inner = inner
        self.showInApp = showInApp
    }

    var handlerRegistered: Bool {
        get { inner.handlerRegistered }
        set { inner.handlerRegistered = newValue }
    }

    func post(_ message: SocketMessageEvent, alerting: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async { [inner, showInApp] in
            if MainActor.assumeIsolated({ showInApp(message.metadata) }) {
                completion(true)
            } else {
                inner.post(message, alerting: alerting, completion: completion)
            }
        }
    }
}
