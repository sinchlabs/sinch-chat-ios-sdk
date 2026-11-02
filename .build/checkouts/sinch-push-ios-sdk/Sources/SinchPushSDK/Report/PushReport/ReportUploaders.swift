import Foundation
import SinchPushSDKNotificationExtension
import os

/// The background `URLSession` uploaders of the app process: the app's own, and the ones the notification service
/// extension's uploads belong to, which the app serves when the system wakes it for their events.
final class ReportUploaders: @unchecked Sendable {
    let container: ReportContainer
    private let makeUploader: @Sendable (String, ReportContainer) -> BackgroundReportUploader
    private let rememberedGroup: RememberedAppGroup
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var uploaders: [String: BackgroundReportUploader] = [:]
        weak var reporter: DeliveryReporter?
    }

    /// An extension session is reopened once it has been registered this long. Each extension upload has an identifier
    /// of its own, which the extension registers, starts the upload on and then releases (`finishTasksAndInvalidate`)
    /// within moments, so a registered identifier is one the extension has let go of. The time covers the moments
    /// between the registration and the release.
    static let extensionSessionIdleTime: TimeInterval = 30
    /// How long a reopened extension session waits for its results before it is released.
    static let extensionSessionGrace: TimeInterval = 60

    init(container: ReportContainer,
         defaults: UserDefaults = .standard,
         makeUploader: @escaping @Sendable (String, ReportContainer) -> BackgroundReportUploader = {
             BackgroundReportUploader(identifier: $0, container: $1)
         }) {
        self.container = container
        rememberedGroup = RememberedAppGroup(defaults: defaults)
        self.makeUploader = makeUploader
    }

    /// The reporter told about each finished upload.
    var reporter: DeliveryReporter? {
        get { state.withLock { $0.reporter } }
        set { state.withLock { $0.reporter = newValue } }
    }

    /// The uploader of `identifier`, when it is one of the SDK's. The session is created on first use.
    ///
    /// The app's uploader lives as long as the process. An extension's lives while its session has work: the
    /// identifiers are the extension processes' own and there is no end to them, so the uploader releases its session
    /// once the system has delivered the events, and a later call makes a new one. Nil for an extension's identifier
    /// when there is no App Group to serve it in.
    func uploader(forIdentifier identifier: String) -> BackgroundReportUploader? {
        if identifier == BackgroundReportUploader.baseIdentifier {
            return cachedUploader(identifier: identifier, container: container, releasing: false)
        }
        guard BackgroundReportUploader.isExtensionIdentifier(identifier),
              let extensionContainer = extensionContainer() else { return nil }
        return cachedUploader(identifier: identifier, container: extensionContainer, releasing: true)
    }

    private func cachedUploader(identifier: String, container: ReportContainer, releasing: Bool) -> BackgroundReportUploader {
        state.withLock { state in
            if let existing = state.uploaders[identifier] { return existing }
            let new = makeUploader(identifier, container)
            let isExtensionSession = BackgroundReportUploader.isExtensionIdentifier(identifier)
            new.onFinished = { [weak self] deliveries, accepted in
                guard let reporter = self?.reporter else { return }
                reporter.uploadFinished(deliveries, accepted: accepted)
                // The extension's failed upload left its deliveries in the pending store: queue them now rather
                // than at the next launch, as the app may stay alive for a long time.
                if isExtensionSession, !accepted { reporter.drainPendingDeliveries() }
            }
            if releasing {
                new.releaseSessionWhenDone()
                new.onInvalidated = { [weak self] in
                    self?.state.withLock { $0.uploaders[identifier] = nil }
                    ReportSessionRegistry(container: container).remove(identifier)
                }
            }
            state.uploaders[identifier] = new
            return new
        }
    }

    /// Where the extension's files are: the App Group of the app, or the last one the app mirrored into.
    private func extensionContainer() -> ReportContainer? {
        let target = container.appGroup != nil ? container : container.resolved(appGroup: rememberedGroup.identifier)
        return target.isShared ? target : nil
    }

    /// Forwards `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    /// Returns `false` when `identifier` is not one of the SDK's sessions, and then the handler is not kept.
    func handleEvents(identifier: String, completionHandler: @escaping @Sendable () -> Void) -> Bool {
        guard let uploader = uploader(forIdentifier: identifier) else { return false }
        uploader.handleEvents(completionHandler: completionHandler)
        return true
    }

    /// Creates the sessions of this process now, so that the results that arrived while the app was not running are
    /// delivered on every launch, not only on the launches the system makes for a session: the app's own, and the
    /// extension's that are idle. Safe to call repeatedly. Without an App Group the extension's are skipped.
    func activateSessions() {
        uploader(forIdentifier: BackgroundReportUploader.baseIdentifier)?.activate()
        guard let extensionContainer = extensionContainer() else { return }
        let identifiers = ReportSessionRegistry(container: extensionContainer)
            .identifiers(idleFor: Self.extensionSessionIdleTime)
        for identifier in identifiers {
            uploader(forIdentifier: identifier)?.activate(releaseAfter: Self.extensionSessionGrace)
        }
    }
}

extension Region {
    /// The base URL of the push API over HTTPS, where the background uploads go. A custom region brings its own port
    /// and its own plaintext setting, which is the one of its chat channel.
    var pushReportBaseURL: URL? {
        switch self {
        case .EU1: return ReportEndpoint.baseURL(pushHost: ReportEndpoint.eu1Host)
        case .US1: return ReportEndpoint.baseURL(pushHost: ReportEndpoint.us1Host)
        case .custom(_, let pushAPIHost, let port, let isSecure, _):
            return ReportEndpoint.baseURL(pushHost: pushAPIHost, port: port, isSecure: isSecure ?? true)
        }
    }
}
