import Foundation
@_spi(SinchChat) import SinchPushSDK

/// The notification permission calls chat needs. Push owns the implementation and the system prompt.
protocol PushNofiticationPermissionHandler: AnyObject {
    /// It must be called from main thread
    func askForPermissions(completion: ((SinchSDKNotificationStatus) -> Void)?)

    func checkIfPermissionIsGranted(completion: @escaping (SinchSDKNotificationStatus) -> Void)
}

/// Forwards the permission calls to `SinchPushSDK.shared.push`.
final class DefaultPushPermissionHandler: PushNofiticationPermissionHandler, @unchecked Sendable {

    func askForPermissions(completion: ((SinchSDKNotificationStatus) -> Void)?) {
        nonisolated(unsafe) let completion = completion
        onMain { SinchPushSDK.shared.push.askNotificationPermission { completion?($0) } }
    }

    func checkIfPermissionIsGranted(completion: @escaping (SinchSDKNotificationStatus) -> Void) {
        nonisolated(unsafe) let completion = completion
        onMain { SinchPushSDK.shared.push.checkPushPermission { completion($0) } }
    }

    /// The push facade is `@MainActor`, and chat calls these from the main thread.
    private func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
        }
    }
}
