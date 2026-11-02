import Foundation
import os

/// The seam between push and the in-app message UI.
///
/// Push offers every candidate to the presenter and only posts the APNs notification when the presenter declines.
/// The in-app code lives in `InApp/` and is the only implementation; the default one shows nothing.
public protocol InAppMessagePresenting: Sendable {
    /// Offers the metadata of a message received over the relay socket.
    /// - Returns: `true` when an in-app message was shown, so the system notification is skipped.
    @MainActor func present(metadata: [String: String]) -> Bool

    /// Offers the payload of an APNs notification.
    /// - Returns: `true` when an in-app message was shown, so the notification is not handled as an APNs copy.
    @MainActor func present(userInfo: [AnyHashable: Any]) -> Bool
}

/// Shows nothing. The default until the in-app UI is wired in.
struct NoopInAppMessagePresenter: InAppMessagePresenting {
    @MainActor func present(metadata: [String: String]) -> Bool { false }
    @MainActor func present(userInfo: [AnyHashable: Any]) -> Bool { false }
}

/// Holds the current presenter, so one set on ``SinchPushSDK`` before or after `push` was first read is the one the
/// APNs path and the relay socket use.
final class InAppPresenterBox: InAppMessagePresenting, @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock<InAppMessagePresenting>(initialState: NoopInAppMessagePresenter())

    var presenter: InAppMessagePresenting {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    /// Whether no real presenter was set yet.
    var isDefault: Bool {
        storage.withLock { $0 is NoopInAppMessagePresenter }
    }

    @MainActor func present(metadata: [String: String]) -> Bool {
        presenter.present(metadata: metadata)
    }

    @MainActor func present(userInfo: [AnyHashable: Any]) -> Bool {
        presenter.present(userInfo: userInfo)
    }
}
