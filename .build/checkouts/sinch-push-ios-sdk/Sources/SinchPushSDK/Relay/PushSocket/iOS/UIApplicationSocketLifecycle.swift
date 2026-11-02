import Foundation

#if canImport(UIKit)
import UIKit

/// Drives ``SocketClient`` from `UIApplication` notifications, on the main actor.
@MainActor
final class UIApplicationSocketLifecycle: AppLifecycleObserving {
    var onBackground: (() -> Void)?
    var onForeground: (() -> Void)?

    private let client: SocketClient
    private var tokens: [NSObjectProtocol] = []
    private var isObserving = false

    init(client: SocketClient) {
        self.client = client
        self.onBackground = { [weak client] in client?.suspend() }
        self.onForeground = { [weak client] in client?.resume() }
    }

    isolated deinit {
        stopObserving()
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default
        // `didBecomeActive` also covers activation without a foreground transition, such as after a call.
        tokens.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onBackground?() }
            })
        tokens.append(
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onForeground?() }
            })
        tokens.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onForeground?() }
            })
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
    }
}
#endif
