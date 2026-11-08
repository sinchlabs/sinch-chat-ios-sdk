import UIKit

public final class WindowHelper {
   
    /// The view controller a new presentation should start from: the top of the app window of the foreground scene.
    /// Main actor only; prefer this over ``getVisibleController()``.
    @MainActor
    public static func visibleController() -> UIViewController? {
        visibleControllerOnMain()
    }

    /// Same as ``visibleController()`` for callers that are not on the main actor.
    ///
    /// **Call this on the main thread.** UIKit state is main-thread only, so an off-main call blocks the calling
    /// thread with `DispatchQueue.main.sync` until the main queue has read the windows. That deadlocks if the main
    /// thread is itself waiting for the calling thread (a lock or a semaphore held by it), so do not call it
    /// off-main while holding anything the main thread may wait for.
    public static func getVisibleController() -> UIViewController? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { visibleControllerOnMain() }
        }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { visibleControllerOnMain() } }
    }

    @MainActor
    private static func visibleControllerOnMain() -> UIViewController? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // Only scenes the user can see. A background or unattached scene has nothing to present on.
        let scene = windowScenes.first { $0.activationState == .foregroundActive }
            ?? windowScenes.first { $0.activationState == .foregroundInactive }

        if let scene, let root = appWindow(in: scene)?.rootViewController {
            return getVisibleViewController(root)
        }

        // Apps without scenes (or without a visible one) keep the app delegate's window.
        return getVisibleViewController(UIApplication.shared.delegate?.window??.rootViewController)
    }

    /// The window of the app in a scene, never an overlay (alert, keyboard, status bar or custom windows sit above
    /// `.normal`, and the key window is often one of them).
    @MainActor
    static func appWindow(in scene: UIWindowScene) -> UIWindow? {
        // UIKit lifecycle: the scene delegate owns the window.
        if let delegate = scene.delegate as? UIWindowSceneDelegate, let delegateWindow = delegate.window,
           let window = delegateWindow, window.windowLevel == .normal {
            return window
        }
        // SwiftUI lifecycle: no scene delegate window, ask the scene.
        if let keyWindow = scene.keyWindow, keyWindow.windowLevel == .normal {
            return keyWindow
        }
        return scene.windows.first { $0.windowLevel == .normal && !$0.isHidden }
    }

    public static func getVisibleViewController(_ currentVc: UIViewController?) -> UIViewController? {
        
        if let presentedViewController = currentVc?.presentedViewController {
            return getVisibleViewController(presentedViewController)
        }
        
        if let navigationController = currentVc as? UINavigationController {
            return navigationController.visibleViewController
        }
        
        if let tabBarController = currentVc as? UITabBarController {
            return tabBarController.selectedViewController
        }
        
        if let pageViewController = currentVc as? UIPageViewController {
            return pageViewController
        }
        if let alert = currentVc as? UIAlertController {
            return alert
        }
        
        return currentVc
    }
}
