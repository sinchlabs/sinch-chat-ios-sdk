import UIKit

/// Finds the view controller to present an alert from.
enum InAppWindowHelper {

    static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first

        if let delegate = activeScene?.delegate as? UIWindowSceneDelegate,
           let root = delegate.window??.rootViewController {
            return topMost(from: root)
        }

        if let root = activeScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            return topMost(from: root)
        }

        return topMost(from: UIApplication.shared.delegate?.window??.rootViewController)
    }

    static func topMost(from current: UIViewController?) -> UIViewController? {
        if let presented = current?.presentedViewController {
            return topMost(from: presented)
        }
        if let navigation = current as? UINavigationController {
            return topMost(from: navigation.visibleViewController)
        }
        if let tab = current as? UITabBarController {
            return topMost(from: tab.selectedViewController)
        }
        return current
    }
}
