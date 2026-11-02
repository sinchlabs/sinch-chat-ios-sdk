import Foundation
import SinchPushSDKNotificationExtension

/// The App Group the app last mirrored into, kept so that the app can still find the files of the group after the
/// host stopped passing `appGroup` to `initialize`: the mirror is deleted from it, and the extension's sessions are
/// served for it.
struct RememberedAppGroup: @unchecked Sendable {
    private static let key = "com.sinch.push.reports.lastAppGroup"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var identifier: String? {
        defaults.string(forKey: Self.key)
    }

    func remember(_ appGroup: String) {
        if identifier != appGroup { defaults.set(appGroup, forKey: Self.key) }
    }
}

/// Copies what the Notification Service Extension needs to report a delivery into the App Group: the access token,
/// the push API URL, the user and the app id. Never the identity secret. Does nothing until the host passes an
/// `appGroup` to `initialize`.
///
/// After `clear()` the mirror stays off until `resume()`: a token refresh that was in flight when the identity was
/// removed must not write the old user's token back for the extension to report with.
struct ReportCredentialsMirror: Sendable {
    let container: ReportContainer
    private let rememberedGroup: RememberedAppGroup

    init(container: ReportContainer, defaults: UserDefaults = .standard) {
        self.container = container
        rememberedGroup = RememberedAppGroup(defaults: defaults)
    }

    private var store: SharedReportCredentialsStore { SharedReportCredentialsStore(container: container) }

    func update(from token: AuthModel) {
        guard let appGroup = container.appGroup, !container.credentialsMirrorPaused else { return }
        guard container.isShared else {
            Logger.warning("appGroup \(appGroup) has no container: add the App Group capability to the app")
            return
        }
        guard let baseURL = token.region.pushReportBaseURL else { return }
        rememberedGroup.remember(appGroup)
        store.write(SharedReportCredentials(accessToken: token.accessToken, reportBaseURL: baseURL,
                                            userId: token.getUserID(), appId: token.configID))
    }

    /// Deletes the mirror, in the current App Group and in the one last used, and stops mirroring until `resume()`.
    func clear() {
        container.credentialsMirrorPaused = true
        let groups = [container.appGroup, rememberedGroup.identifier].compactMap { $0 }
        for group in Set(groups) {
            let target = container.resolved(appGroup: group)
            guard target.isShared else { continue }
            SharedReportCredentialsStore(container: target).clear()
        }
    }

    /// Mirrors again. Call it when an identity was set up and is still the current one.
    func resume() {
        container.credentialsMirrorPaused = false
    }
}

/// An `AuthStorage` that mirrors every token it saves, and clears the mirror when the token is deleted.
///
/// It touches the mirror only while `isCurrent` holds. The host passes whether the identity it was made for is still
/// the current one: a call that comes late from the data source of a removed or replaced identity (the `deleteToken`
/// after the unsubscribe of `removeIdentity`, a token refresh in flight) must neither clear the mirror of the next
/// identity nor write the old user's token back.
final class MirroringAuthStorage: AuthStorage, @unchecked Sendable {
    private let base: AuthStorage
    private let mirror: ReportCredentialsMirror
    private let isCurrent: @Sendable () -> Bool

    init(base: AuthStorage, mirror: ReportCredentialsMirror, isCurrent: @escaping @Sendable () -> Bool = { true }) {
        self.base = base
        self.mirror = mirror
        self.isCurrent = isCurrent
    }

    func read() -> AuthModel? { base.read() }

    func save(_ token: AuthModel) {
        base.save(token)
        if isCurrent() { mirror.update(from: token) }
    }

    func deleteToken() {
        base.deleteToken()
        if isCurrent() { mirror.clear() }
    }
}
