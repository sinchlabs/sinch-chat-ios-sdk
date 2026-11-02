import Foundation
import os

/// Starts a background upload. `URLSession` is the production one; tests use a fake.
package protocol ReportUploadSession: AnyObject, Sendable {
    /// Hands `fileURL` to the system as the body of `request`. The system uploads it even when the process is gone.
    func startUpload(_ request: URLRequest, fromFile fileURL: URL, taskDescription: String)

    /// Lets the running tasks finish and then releases the session, which frees its identifier.
    func finishTasksAndInvalidate()
}

extension ReportUploadSession {
    package func finishTasksAndInvalidate() {}
}

/// Uploads `ReportEvents` calls with a background `URLSession`, so they complete when the app or the extension is
/// suspended or killed. The system finishes the upload and wakes the app, which gets the session's events through
/// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`, the extension's included.
///
/// What each upload carried travels in the task's `taskDescription`, which the system keeps, so a relaunched
/// process knows which deliveries an answer is about. A success records a sent marker for each delivery. A failure of
/// an upload that the extension started is stored for the app to report (see ``PendingDeliveryStore``); a failure of
/// the app's own upload leaves the deliveries in the app's outbox.
///
/// The server keeps the first terminal status of a delivery, so a report that arrives twice (the extension's and the
/// app's, when a marker was not written in time) does no harm.
///
/// ### Session identifiers
/// The system allows one process per background session identifier. The app uses `com.sinch.chatsdk.reports`; every
/// extension upload uses its own `com.sinch.chatsdk.reports.nse.<uuid>` (``makeExtensionIdentifier()``): extension
/// processes are reused and may idle for long, so a process must not keep a session the app wants to open. The
/// extension registers the identifier, starts the upload and releases the session right away
/// (``invalidatesSessionAfterUpload``). The app serves an extension's session when the system wakes it for that
/// identifier, and reopens the registered sessions (see ``ReportSessionRegistry``).
package final class BackgroundReportUploader: NSObject, @unchecked Sendable {
    package static let baseIdentifier = "com.sinch.chatsdk.reports"
    /// The identifier extension processes used before each one got its own. Still served, never created.
    package static let legacyExtensionIdentifier = baseIdentifier + ".nse"
    package static let extensionIdentifierPrefix = baseIdentifier + ".nse."

    /// How long the system keeps trying an upload. The app holds the deliveries of an upload in flight for as long,
    /// so that it does not report them a second time while the system still might.
    package static let resourceTimeout: TimeInterval = 10 * 60

    /// Whether `identifier` names a session of an extension process.
    package static func isExtensionIdentifier(_ identifier: String) -> Bool {
        identifier == legacyExtensionIdentifier
            || (identifier.hasPrefix(extensionIdentifierPrefix) && identifier.count > extensionIdentifierPrefix.count)
    }

    /// A new identifier for an extension process.
    package static func makeExtensionIdentifier() -> String {
        extensionIdentifierPrefix + UUID().uuidString
    }

    /// What a task's `taskDescription` holds.
    package struct Manifest: Codable, Equatable {
        /// The name of the upload file.
        package let file: String
        /// The full path of the upload file, where it was written. Absent in a manifest written by an older version,
        /// which then relied on the directory of the uploader that read it.
        package let path: String?
        package let deliveries: [ReportedDelivery]

        package init(file: String, deliveries: [ReportedDelivery], path: String? = nil) {
            self.file = file
            self.path = path
            self.deliveries = deliveries
        }
    }

    package let identifier: String
    /// The container as it was when the uploader was created: where its files and its session are, for good.
    private let container: ReportContainer
    private let uploadsURL: URL?
    private let markers: SentReportMarkerStore
    private let pending: PendingDeliveryStore
    private let registry: ReportSessionRegistry
    private let makeSession: ((BackgroundReportUploader) -> ReportUploadSession)?
    private let isExtensionSession: Bool
    private let invalidatesSessionAfterUpload: Bool
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var session: ReportUploadSession?
        var bodies: [Int: Data] = [:]
        var eventsCompletions: [@Sendable () -> Void] = []
        var releasesWhenDone = false
    }

    /// Called for each finished upload with the deliveries it carried, and whether the server accepted them.
    /// Called on the session's delegate queue.
    package var onFinished: (@Sendable (_ deliveries: [ReportedDelivery], _ accepted: Bool) -> Void)? {
        get { finished.withLock { $0 } }
        set { finished.withLock { $0 = newValue } }
    }
    private let finished = OSAllocatedUnfairLock<(@Sendable ([ReportedDelivery], Bool) -> Void)?>(initialState: nil)

    /// Called when the session is released, which frees the identifier for a new uploader.
    package var onInvalidated: (@Sendable () -> Void)? {
        get { invalidated.withLock { $0 } }
        set { invalidated.withLock { $0 = newValue } }
    }
    private let invalidated = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)

    private static let uploadsDirectory = "report-uploads"
    private static let staleUploadAge: TimeInterval = 24 * 60 * 60

    /// - Parameters:
    ///   - makeSession: Builds the session the uploads go through. The default is a background `URLSession`
    ///     named `identifier`, in the App Group when the container has one; an extension's session needs one.
    ///   - invalidatesSessionAfterUpload: Releases the session as soon as an upload is started, so the process holds
    ///     no session afterwards and the identifier is free for the app to open. The extension's way.
    package init(identifier: String,
                 container: ReportContainer,
                 invalidatesSessionAfterUpload: Bool = false,
                 makeSession: ((BackgroundReportUploader) -> ReportUploadSession)? = nil) {
        let container = container.frozen()
        self.identifier = identifier
        self.container = container
        uploadsURL = container.directory?.appendingPathComponent(Self.uploadsDirectory, isDirectory: true)
        markers = SentReportMarkerStore(container: container)
        pending = PendingDeliveryStore(container: container)
        registry = ReportSessionRegistry(container: container)
        isExtensionSession = Self.isExtensionIdentifier(identifier)
        self.makeSession = makeSession
        self.invalidatesSessionAfterUpload = invalidatesSessionAfterUpload
        super.init()
    }

    // MARK: - Shared instances

    private static let instances = OSAllocatedUnfairLock<[String: BackgroundReportUploader]>(initialState: [:])

    /// The uploader of `identifier` in this process. A process may hold only one session per identifier.
    package static func shared(identifier: String, container: ReportContainer) -> BackgroundReportUploader {
        let key = identifier + "|" + (container.appGroup ?? "")
        return instances.withLock { instances in
            if let existing = instances[key] { return existing }
            let new = BackgroundReportUploader(identifier: identifier, container: container)
            instances[key] = new
            return new
        }
    }

    // MARK: - Uploading

    /// Writes the call to a file and hands it to the session. Returns whether the upload was started.
    @discardableResult
    package func upload(_ deliveries: [ReportedDelivery], accessToken: String, baseURL: URL) -> Bool {
        guard !deliveries.isEmpty, let directory = prepareUploadsDirectory(), let session = session() else { return false }
        removeStaleUploads(in: directory)
        let file = UUID().uuidString + ".grpcweb"
        let fileURL = directory.appendingPathComponent(file)
        container.write(GRPCWebReportEvents.body(for: deliveries), to: fileURL)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let description = try? JSONEncoder().encode(
                Manifest(file: file, deliveries: deliveries, path: fileURL.path)) else {
            try? FileManager.default.removeItem(at: fileURL)
            return false
        }
        // Before the upload starts: the extension may be killed right after, and the app has to find the session.
        if isExtensionSession { registry.touch(identifier) }
        let request = GRPCWebReportEvents.request(baseURL: baseURL, accessToken: accessToken)
        session.startUpload(request, fromFile: fileURL, taskDescription: String(decoding: description, as: UTF8.self))
        // The system carries the upload on; this process lets go of the session, and of its identifier.
        if invalidatesSessionAfterUpload { session.finishTasksAndInvalidate() }
        return true
    }

    /// Keeps the completion handler of the system until the session has delivered all its events.
    /// The session is created here when this is a fresh process, which makes the system deliver the events.
    /// Every handler is kept and called once, however many times the system asks.
    package func handleEvents(completionHandler: @escaping @Sendable () -> Void) {
        state.withLock { $0.eventsCompletions.append(completionHandler) }
        _ = session()
    }

    /// Creates the session, which makes the system deliver the events that wait for it. Does nothing when the session
    /// exists. With `releaseAfter`, the session finishes its tasks and is released that many seconds later, for an
    /// uploader that only collects results.
    package func activate(releaseAfter delay: TimeInterval? = nil) {
        guard let delay else {
            _ = session()
            return
        }
        state.withLock { $0.releasesWhenDone = true }
        guard let session = session() else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { session.finishTasksAndInvalidate() }
    }

    /// Makes the uploader release its session when the system has delivered the events of the session.
    package func releaseSessionWhenDone() {
        state.withLock { $0.releasesWhenDone = true }
    }

    private func session() -> ReportUploadSession? {
        state.withLock { state in
            if let session = state.session { return session }
            guard let session = makeSession?(self) ?? makeSystemSession() else { return nil }
            state.session = session
            return session
        }
    }

    /// A background `URLSession` named `identifier`. The extension's one is refused without an App Group: it could not
    /// share its files with the app, which would never learn how its uploads ended.
    private func makeSystemSession() -> ReportUploadSession? {
        if isExtensionSession, !container.isShared { return nil }
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sharedContainerIdentifier = container.appGroup
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        return URLSessionReportUploadSession(session: session)
    }

    // MARK: - Results

    /// Reads the answer of a finished upload. Without a readable `taskDescription` there is nothing to account for.
    package func uploadFinished(taskDescription: String?, httpStatus: Int?, headerGrpcStatus: String?,
                                body: Data, error: Error?) {
        guard let taskDescription,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: Data(taskDescription.utf8)) else { return }
        let accepted: Bool
        if error == nil, let httpStatus {
            accepted = GRPCWebReportEvents.outcome(httpStatus: httpStatus, headerGrpcStatus: headerGrpcStatus,
                                                   body: body) == .success
        } else {
            accepted = false
        }
        if accepted {
            markers.record(manifest.deliveries)
        } else if isExtensionSession {
            // Nobody else knows these deliveries: the app learns them from the store.
            pending.append(manifest.deliveries)
        }
        removeUploadFile(of: manifest)
        onFinished?(manifest.deliveries, accepted)
    }

    private func prepareUploadsDirectory() -> URL? {
        guard let url = uploadsURL else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Removes the file the upload was made from, where the manifest says it was written.
    private func removeUploadFile(of manifest: Manifest) {
        if let path = manifest.path { try? FileManager.default.removeItem(atPath: path) }
        if let uploadsURL { try? FileManager.default.removeItem(at: uploadsURL.appendingPathComponent(manifest.file)) }
    }

    /// Drops the files of uploads that never reported back.
    private func removeStaleUploads(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, Date().timeIntervalSince(modified) > Self.staleUploadAge {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

extension BackgroundReportUploader: URLSessionDataDelegate {
    package func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        state.withLock { $0.bodies[dataTask.taskIdentifier, default: Data()].append(data) }
    }

    package func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let body = state.withLock { $0.bodies.removeValue(forKey: task.taskIdentifier) } ?? Data()
        let response = task.response as? HTTPURLResponse
        uploadFinished(taskDescription: task.taskDescription,
                       httpStatus: response?.statusCode,
                       headerGrpcStatus: response?.value(forHTTPHeaderField: "grpc-status"),
                       body: body,
                       error: error)
    }

    package func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let (completions, release) = state.withLock { state -> ([@Sendable () -> Void], ReportUploadSession?) in
            defer { state.eventsCompletions = [] }
            return (state.eventsCompletions, state.releasesWhenDone ? state.session : nil)
        }
        for completion in completions { DispatchQueue.main.async(execute: completion) }
        release?.finishTasksAndInvalidate()
    }

    package func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        state.withLock { $0.session = nil }
        onInvalidated?()
    }
}

/// The production session: a background `URLSession`.
final class URLSessionReportUploadSession: ReportUploadSession, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func startUpload(_ request: URLRequest, fromFile fileURL: URL, taskDescription: String) {
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = taskDescription
        task.resume()
    }

    func finishTasksAndInvalidate() {
        session.finishTasksAndInvalidate()
    }
}
