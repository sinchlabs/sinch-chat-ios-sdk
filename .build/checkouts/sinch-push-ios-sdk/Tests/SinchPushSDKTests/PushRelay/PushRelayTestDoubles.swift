import Foundation
import UserNotifications

@testable import SinchPushSDK

// MARK: - Subscribe repository

/// Records every Subscribe and lets the test decide what it returns.
final class RecordingSubscribeRepository: PushRepository, @unchecked Sendable {
    struct Call: Equatable {
        let token: String
        let deviceInfo: DeviceInfo?
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var unsubscribedTokens: [String] = []
    private var storedResult: Result<Void, Error> = .success(())
    private var storedUnsubscribeResult: Result<Void, Error> = .success(())

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    var unsubscribed: [String] {
        lock.lock(); defer { lock.unlock() }
        return unsubscribedTokens
    }

    var result: Result<Void, Error> {
        get { lock.lock(); defer { lock.unlock() }; return storedResult }
        set { lock.lock(); defer { lock.unlock() }; storedResult = newValue }
    }

    var unsubscribeResult: Result<Void, Error> {
        get { lock.lock(); defer { lock.unlock() }; return storedUnsubscribeResult }
        set { lock.lock(); defer { lock.unlock() }; storedUnsubscribeResult = newValue }
    }

    func sendDeviceToken(token: String, deviceInfo: DeviceInfo?) async throws -> String? {
        try record(token: token, deviceInfo: deviceInfo).get()
        return nil
    }

    func sendDeviceToken(token: String,
                         deviceInfo: DeviceInfo?,
                         completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        // Synchronous on purpose: tests need no waiting.
        completion(record(token: token, deviceInfo: deviceInfo))
    }

    private func record(token: String, deviceInfo: DeviceInfo?) -> Result<Void, Error> {
        lock.withLock {
            recorded.append(Call(token: token, deviceInfo: deviceInfo))
            return storedResult
        }
    }

    func unsubscribe(_ currentDeviceToken: String) async throws {
        lock.withLock { unsubscribedTokens.append(currentDeviceToken) }
    }

    func unsubscribe(_ currentDeviceToken: String,
                     _ completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        lock.lock()
        unsubscribedTokens.append(currentDeviceToken)
        let result = storedUnsubscribeResult
        lock.unlock()
        completion(result)
    }


}

// MARK: - Routing

/// Records what the routing passes to the existing push handler.
final class RoutingHandlerStub: PushNotificationHandler, @unchecked Sendable {
    var pushRepository: PushRepository?
    var authDataSource: AuthDataSource?
    var willPresentResult: UNNotificationPresentationOptions? = [.badge, .banner, .list]
    var handleResult = true
    private(set) var willPresentPayloads: [[AnyHashable: Any]] = []
    private(set) var handledPayloads: [[AnyHashable: Any]] = []

    private(set) var resubscribeCount = 0

    func sendDeviceToken(token: Data) {}
    func resubscribeIfNeeded() { resubscribeCount += 1 }
    func unsubscribe(_ completion: @escaping @Sendable (Result<Void, Error>) -> Void) { completion(.success(())) }
    func handleNotification(payload: [AnyHashable: Any]) -> IsHandled {
        handledPayloads.append(payload)
        return handleResult
    }
    func handleWillPresentNotification(_ payload: [AnyHashable: Any]) -> UNNotificationPresentationOptions? {
        willPresentPayloads.append(payload)
        return willPresentResult
    }
    func registerAddressee(_ service: PushNotificationAddressee) {}
    func removeAddressee(_ service: PushNotificationAddressee) {}
    func getAddressee(id: PushNotificationAddresseeName) -> PushNotificationAddressee? { nil }
    func askForPermissions(completion: ((SinchSDKNotificationStatus) -> Void)?) {}
    func checkIfPermissionIsGranted(completion: @escaping (SinchSDKNotificationStatus) -> Void) {}
}

/// Stands in for the in-app UI: records what push offered it and answers with ``shows``.
final class InAppControllerStub: InAppMessagePresenting, @unchecked Sendable {
    var shows = false

    private(set) var payloads: [[AnyHashable: Any]] = []
    private(set) var metadataOffers: [[String: String]] = []

    @MainActor
    func present(metadata: [String: String]) -> Bool {
        metadataOffers.append(metadata)
        return shows
    }

    @MainActor
    func present(userInfo: [AnyHashable: Any]) -> Bool {
        payloads.append(userInfo)
        return shows
    }
}
