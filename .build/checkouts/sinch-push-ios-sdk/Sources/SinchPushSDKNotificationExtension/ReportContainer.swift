import Foundation
import os

/// Where the report files live: the App Group container when the host set one up, the process's own Application
/// Support directory otherwise. The app and the notification service extension see the same files only in the first case.
package final class ReportContainer: @unchecked Sendable {
    private let lock = NSLock()
    private var _appGroup: String?
    private let directoryOverride: URL?
    private var _credentialsMirrorPaused = false

    /// - Parameter directory: Replaces the container directory. Tests use it.
    package init(appGroup: String? = nil, directory: URL? = nil) {
        _appGroup = appGroup
        directoryOverride = directory
    }

    /// A copy with `appGroup` fixed to the one this container has now, so that files and sessions created from it
    /// stay in one place even when the host sets the App Group later.
    package func frozen() -> ReportContainer {
        ReportContainer(appGroup: appGroup, directory: directoryOverride)
    }

    /// A copy that lives in `appGroup`.
    package func resolved(appGroup: String?) -> ReportContainer {
        ReportContainer(appGroup: appGroup, directory: directoryOverride)
    }

    /// Whether the app stopped mirroring the credentials, after a `clear` and until the next `resume`.
    /// Held here because every copy of the app's mirror shares this container.
    package var credentialsMirrorPaused: Bool {
        get { lock.withLock { _credentialsMirrorPaused } }
        set { lock.withLock { _credentialsMirrorPaused = newValue } }
    }

    /// The App Group the files are shared through. `nil` until the host passes one to `initialize`.
    package var appGroup: String? {
        get { lock.withLock { _appGroup } }
        set { lock.withLock { _appGroup = newValue } }
    }

    /// The directory of the SDK's report files. Created on demand.
    package var directory: URL? {
        let group = appGroup
        let base: URL?
        if let directoryOverride {
            base = directoryOverride
        } else if let group {
            base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        }
        guard let url = base?.appendingPathComponent("com.sinch.chatsdk", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Whether the files are in the App Group, so that the extension can see them.
    package var isShared: Bool {
        appGroup != nil && directory != nil
    }

    /// How long `withFileLock` waits for a lock another process holds: 20 attempts, 10 ms apart.
    private static let lockAttempts = 20
    private static let lockRetryDelayMicroseconds: UInt32 = 10_000

    /// Runs `body` holding a lock on a file of the container, so the app and the extension do not interleave.
    ///
    /// The wait for the lock is short and bounded: a process suspended while it holds a lock on a file in the shared
    /// container would be killed by the system (0xdead10cc), and must not block another process forever. When the
    /// lock stays taken, `body` runs without it.
    package func withFileLock<T>(named name: String, _ body: () -> T) -> T {
        guard let url = directory?.appendingPathComponent(name) else { return body() }
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return body() }
        var locked = false
        for attempt in 0..<Self.lockAttempts {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                locked = true
                break
            }
            if attempt < Self.lockAttempts - 1 { usleep(Self.lockRetryDelayMicroseconds) }
        }
        defer {
            if locked { flock(descriptor, LOCK_UN) }
            close(descriptor)
        }
        return body()
    }

    /// Writes `data` atomically, readable after the first unlock so that a background wake can read it.
    func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(excluded)
    }
}

/// What the notification service extension needs from the app to report a delivery.
///
/// Holds the access token, which the app already keeps in its Keychain, and never the identity secret.
package struct SharedReportCredentials: Codable, Equatable, Sendable {
    package let accessToken: String
    /// The base URL of the push API of the app's region.
    package let reportBaseURL: URL
    /// The user the token was issued for, when the token names one.
    package let userId: String?
    /// The id of the Sinch chat config the token belongs to.
    package let appId: String

    package init(accessToken: String, reportBaseURL: URL, userId: String?, appId: String) {
        self.accessToken = accessToken
        self.reportBaseURL = reportBaseURL
        self.userId = userId
        self.appId = appId
    }
}

/// The credentials the app mirrors for the extension, in a file of the App Group container.
///
/// A file rather than the Keychain: a Keychain item is shared through a Keychain access group, which is an
/// entitlement of its own (Keychain Sharing) that the App Group capability does not grant on iOS.
/// The file is protected until the first unlock, as the Keychain item the token comes from is.
package struct SharedReportCredentialsStore: Sendable {
    private static let fileName = "report-credentials.json"
    private let container: ReportContainer

    package init(container: ReportContainer) {
        self.container = container
    }

    package func read() -> SharedReportCredentials? {
        guard let url = container.directory?.appendingPathComponent(Self.fileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedReportCredentials.self, from: data)
    }

    package func write(_ credentials: SharedReportCredentials) {
        guard let url = container.directory?.appendingPathComponent(Self.fileName),
              let data = try? JSONEncoder().encode(credentials) else { return }
        container.write(data, to: url)
    }

    package func clear() {
        guard let url = container.directory?.appendingPathComponent(Self.fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// The deliveries a background upload reported, shared by the app and the extension so that the app does not report
/// again what the extension has sent. Bounded in count and age.
package struct SentReportMarkerStore: Sendable {
    package static let capacity = 1000
    package static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private struct Marker: Codable {
        let messageID: String
        let subscriberID: String
        let sentAt: TimeInterval
    }

    private static let fileName = "sent-report-markers.json"
    private let container: ReportContainer
    private let now: @Sendable () -> Date

    package init(container: ReportContainer, now: @escaping @Sendable () -> Date = { Date() }) {
        self.container = container
        self.now = now
    }

    /// Whether `delivery` was reported by an upload.
    package func contains(_ delivery: ReportedDelivery) -> Bool {
        guard container.directory != nil else { return false }
        return container.withFileLock(named: "sent-report-markers.lock") {
            load().contains { $0.messageID == delivery.messageID && $0.subscriberID == delivery.subscriberID }
        }
    }

    /// The deliveries among `deliveries` that were reported by an upload.
    package func sent(among deliveries: [ReportedDelivery]) -> Set<ReportedDelivery> {
        guard !deliveries.isEmpty, container.directory != nil else { return [] }
        return container.withFileLock(named: "sent-report-markers.lock") {
            let markers = load()
            return Set(deliveries.filter { delivery in
                markers.contains { $0.messageID == delivery.messageID && $0.subscriberID == delivery.subscriberID }
            })
        }
    }

    /// Records that `deliveries` were reported.
    package func record(_ deliveries: [ReportedDelivery]) {
        guard !deliveries.isEmpty, let url = container.directory?.appendingPathComponent(Self.fileName) else { return }
        container.withFileLock(named: "sent-report-markers.lock") {
            var markers = load()
            let stamp = now().timeIntervalSince1970
            for delivery in deliveries
            where !markers.contains(where: { $0.messageID == delivery.messageID && $0.subscriberID == delivery.subscriberID }) {
                markers.append(Marker(messageID: delivery.messageID, subscriberID: delivery.subscriberID, sentAt: stamp))
            }
            if markers.count > Self.capacity { markers.removeFirst(markers.count - Self.capacity) }
            guard let data = try? JSONEncoder().encode(markers) else { return }
            container.write(data, to: url)
        }
    }

    /// The markers within `maxAge`, oldest first.
    private func load() -> [Marker] {
        guard let url = container.directory?.appendingPathComponent(Self.fileName),
              let data = try? Data(contentsOf: url),
              let markers = try? JSONDecoder().decode([Marker].self, from: data) else { return [] }
        let oldest = now().timeIntervalSince1970 - Self.maxAge
        return markers.filter { $0.sentAt >= oldest }
    }
}
