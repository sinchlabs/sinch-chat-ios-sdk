import Foundation
import SwiftProtobuf
import SinchPushSDKNotificationExtension
import UIKit

/// Sends delivery reports to sinch-push.
protocol DeliveryReportSending: Sendable {
    /// Sends one batch of deliveries. Throws when the server refused them.
    func reportEvents(_ events: [DeliveryReport]) async throws

    /// Sends one batch of deliveries, giving up after `timeout` when it is set.
    func reportEvents(_ events: [DeliveryReport], timeout: Duration?) async throws
}

extension DeliveryReportSending {
    func reportEvents(_ events: [DeliveryReport], timeout: Duration?) async throws {
        try await reportEvents(events)
    }
}

/// The gRPC-web sender, over the push API of the configured region.
///
/// The push host answers native gRPC, so the status is invisible: the client accepts a call that received a message
/// frame and treats a `grpc-status` in the headers as the error it is (``GrpcWebClient/MissingStatusPolicy``).
final class PushAPIDeliveryReportSender: DeliveryReportSending, @unchecked Sendable {
    /// The push service method.
    static let path = "sinch.push.sdk.v1beta1.SdkService/ReportEvents"

    private let client: PushAPIClient
    private let authDataSource: AuthDataSource
    private let metadata: StandardMetadata

    init(client: PushAPIClient, authDataSource: AuthDataSource, metadata: StandardMetadata = .init()) {
        self.client = client
        self.authDataSource = authDataSource
        self.metadata = metadata
    }

    func reportEvents(_ events: [DeliveryReport]) async throws {
        try await reportEvents(events, timeout: nil)
    }

    func reportEvents(_ events: [DeliveryReport], timeout: Duration?) async throws {
        guard let grpc = client.grpcWebClient else { throw PushRepositoryError.internalError }
        let request = Self.reportRequest(events)
        let headers = metadata.headers(token: try? authDataSource.currentAccessToken())
        let _: Google_Protobuf_Empty = try await grpc.unary(
            path: Self.path,
            request: request,
            metadata: headers,
            timeout: timeout)
    }

    /// The request for a batch of deliveries.
    static func reportRequest(_ events: [DeliveryReport]) -> Sinch_Push_Sdk_V1beta1_ReportEventsRequest {
        Sinch_Push_Sdk_V1beta1_ReportEventsRequest.with {
            $0.events = events.map { event in
                Sinch_Push_Sdk_V1beta1_ReportedEvent.with {
                    $0.messageID = event.messageID
                    $0.subscriberID = event.subscriberID
                    // The server refuses a batch that carries anything but DELIVERED.
                    $0.eventType = .delivered
                }
            }
        }
    }
}

/// Hands `ReportEvents` calls to a background `URLSession`.
protocol DeliveryReportUploading: Sendable {
    /// Returns whether the upload was started.
    func upload(_ deliveries: [ReportedDelivery], accessToken: String, baseURL: URL) -> Bool
}

extension BackgroundReportUploader: DeliveryReportUploading {}

/// The APNs deliveries the SDK reports to sinch-push.
protocol DeliveryReporting: AnyObject, Sendable {
    /// Queues the first APNs delivery of a message. A delivery already queued is ignored.
    func reportDelivery(messageID: String, subscriberID: String)

    /// Sends what is queued during a background wake, and returns by `deadline`.
    func flushForBackgroundWake(until deadline: ContinuousClock.Instant) async

    /// Queues the deliveries the Notification Service Extension could not upload, unless a background upload has
    /// reported them already.
    func drainPendingDeliveries()
}

extension DeliveryReporting {
    func flushForBackgroundWake(until deadline: ContinuousClock.Instant) async {}
    func drainPendingDeliveries() {}
}

/// Reports the APNs deliveries to sinch-push.
///
/// The deliveries wait in an outbox and are sent in batches. All state lives on the
/// scheduler's queue, which the push relay shares. One flush runs at a time; a trigger
/// during a running flush makes it run one more pass when it ends.
final class DeliveryReporter: DeliveryReporting, @unchecked Sendable {

    /// The most deliveries one `ReportEvents` call carries.
    static let batchSize = 100

    /// How many times one trigger tries a batch before it waits for the next trigger.
    static let maxAttemptsPerTrigger = 5

    /// How long a background wake may spend reporting, from the moment the wake starts: the restore of the session,
    /// the hand-off and the flush all fit in it. iOS suspends the app about 30 seconds after the wake, and the host
    /// still has to finish the fetch.
    static let backgroundWakeDeadline: Duration = .seconds(20)

    /// The room a wake leaves for the token refresh, which has its own 5 second timeout, when it bounds a
    /// `ReportEvents` call by the time left.
    static let backgroundWakeRefreshAllowance: Duration = .seconds(5)

    /// The shortest `ReportEvents` call of a wake.
    static let backgroundWakeMinimumCallTimeout: Duration = .seconds(1)

    /// How long a delivery handed to a background upload stays out of the normal flush: as long as the system keeps
    /// trying the upload. A delivery whose answer is lost is sent again then; the server keeps the first terminal
    /// status, so the rare duplicate is harmless.
    static let uploadInFlightDurationMs = DeliveryReportOutbox.inFlightDurationMs

    /// The identity the deliveries are reported for.
    struct Session: Sendable {
        let authDataSource: AuthDataSource
        let client: PushAPIClient
        /// The base URL of the push API over HTTPS, where a background upload goes. `nil` means no uploads.
        var reportBaseURL: URL? = nil
    }

    /// What the reporter needs from the app.
    struct Dependencies: Sendable {
        /// The queue the deliveries are sent on. The push relay uses the same one.
        var scheduler: Scheduler
        /// The jitter source of the retry backoff.
        var random: RandomSource
        /// Builds the sender of a session.
        var makeSender: @Sendable (AuthDataSource, PushAPIClient) -> DeliveryReportSending
        /// Whether the app is in the foreground.
        var isApplicationActive: @Sendable () -> Bool
        /// Whether the process is a notification service extension.
        var isNotificationServiceExtension: @Sendable () -> Bool
        /// The centre that posts the foreground transition.
        var notificationCenter: NotificationCenter
        /// The background `URLSession` a wake in the background hands the deliveries to. `nil` means none.
        var uploader: (@Sendable () -> DeliveryReportUploading?)? = nil
        /// Which of the deliveries a background upload has reported already (the notification service extension's
        /// included). `nil` means none is known.
        var sentDeliveries: (@Sendable ([ReportedDelivery]) -> Set<ReportedDelivery>)? = nil
        /// Takes the deliveries the notification service extension could not upload. `nil` means none.
        var pendingDeliveries: (@Sendable () -> [PendingDelivery])? = nil
        /// Whether an access token is expired, or about to be: a background upload carries it without a retry.
        var isAccessTokenExpired: @Sendable (String) -> Bool = { AccessTokenExpiry.isExpired($0, leeway: 60) }
    }

    /// What a batch's outcome is.
    private enum BatchOutcome {
        /// The server accepted the batch; it leaves the outbox.
        case accepted
        /// The server refused the batch for good; it leaves the outbox.
        case refused
        /// The batch is kept, and the flush waits for the next trigger.
        case keep
        /// The batch is kept, and the flush is tried again after a backoff.
        case retry
    }

    private let outbox: DeliveryReportOutbox
    private let dependencies: Dependencies

    /// The identity the deliveries are reported for. Only touched on the scheduler's queue.
    private var session: Session?
    /// Bumped when the session ends, so a flush of the old session cannot touch the next one's outbox.
    private var generation = 0
    /// Whether a flush is running. Only touched on the scheduler's queue.
    private var isFlushing = false
    /// Whether a trigger arrived during the running flush. Only touched on the scheduler's queue.
    private var rerunRequested = false
    /// Callers waiting for the running flush to end. Only touched on the scheduler's queue.
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    /// The pending backoff retry. Only touched on the scheduler's queue.
    private var retryTask: ScheduledTask?
    private var foregroundObserver: NSObjectProtocol?

    /// Called on the scheduler's queue each time a pass ends.
    var onPassFinished: (@Sendable () -> Void)?

    init(outbox: DeliveryReportOutbox, dependencies: Dependencies) {
        self.outbox = outbox
        self.dependencies = dependencies
        foregroundObserver = dependencies.notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            // The extension may have left deliveries since the app last drained, while the process stayed alive.
            self?.drainPendingDeliveries()
            self?.flush()
        }
    }

    deinit {
        if let foregroundObserver {
            dependencies.notificationCenter.removeObserver(foregroundObserver)
        }
    }

    // MARK: - Queueing

    /// Queues a delivery and, when the app is in the foreground, sends what is queued.
    /// An extension never asks whether the app is active: `UIApplication.shared` is unavailable there.
    func reportDelivery(messageID: String, subscriberID: String) {
        // The extension may have reported it already.
        if isSentByUpload(ReportedDelivery(messageID: messageID, subscriberID: subscriberID)) { return }
        let queued = outbox.enqueue(messageID: messageID,
                                    subscriberID: subscriberID,
                                    enqueuedAtMs: dependencies.scheduler.nowMs())
        guard queued, !dependencies.isNotificationServiceExtension(), dependencies.isApplicationActive() else {
            return
        }
        flush()
    }

    /// Whether a background upload reported the delivery already.
    private func isSentByUpload(_ delivery: ReportedDelivery) -> Bool {
        dependencies.sentDeliveries?([delivery]).isEmpty == false
    }

    /// Queues the deliveries the notification service extension could not upload, so the app reports them. The ones
    /// a background upload reported meanwhile are dropped, and so are the ones older than the outbox's time to live.
    /// A queued delivery keeps the time it failed as its age, so the time to live is not renewed. A notification
    /// service extension leaves them alone.
    func drainPendingDeliveries() {
        guard !dependencies.isNotificationServiceExtension(),
              let pending = dependencies.pendingDeliveries?(), !pending.isEmpty else { return }
        let nowMs = dependencies.scheduler.nowMs()
        for entry in pending {
            let failedAtMs = min(Int64(entry.failedAt.timeIntervalSince1970 * 1000), nowMs)
            let delivery = ReportedDelivery(messageID: entry.messageId, subscriberID: entry.subscriberId)
            guard nowMs - failedAtMs <= DeliveryReportOutbox.ttlMs, !isSentByUpload(delivery) else { continue }
            outbox.enqueue(messageID: delivery.messageID, subscriberID: delivery.subscriberID, enqueuedAtMs: failedAtMs)
        }
    }

    // MARK: - Session

    /// Gives the reporter the identity the deliveries are reported for.
    func setSession(authDataSource: AuthDataSource, client: PushAPIClient?, reportBaseURL: URL? = nil) {
        dependencies.scheduler.perform { [self] in
            guard let client else {
                session = nil
                return
            }
            session = Session(authDataSource: authDataSource, client: client, reportBaseURL: reportBaseURL)
        }
    }

    /// Ends the reporting session: the queued deliveries are dropped.
    func endSession() {
        dependencies.scheduler.perform { [self] in
            generation += 1
            session = nil
            retryTask?.cancel()
            retryTask = nil
            outbox.clear()
        }
    }

    // MARK: - Flushing

    /// Sends the queued deliveries. The returned task finishes when this call's passes are done.
    @discardableResult
    func flush() -> Task<Void, Never> {
        Task { await runFlush(attempt: 1) }
    }

    /// Sends the queued deliveries when a push wakes the app, and returns when they are sent or `deadline` has passed.
    ///
    /// In the foreground this is the normal flush, backoff retries included. Otherwise the deliveries are handed to
    /// the background `URLSession`, which the system completes even when the app is suspended; without one, or when
    /// the hand-off cannot be made, a flush already running is waited for, then one attempt is made: nothing is
    /// scheduled for later, since the app is suspended soon after the wake, and a retry an earlier flush scheduled
    /// stays. What is not sent stays in the outbox for the next trigger.
    /// The call always returns by `deadline`, even when the server or the token refresh never answers.
    func flushForBackgroundWake(until deadline: ContinuousClock.Instant) async {
        let remaining = deadline - ContinuousClock.now - Self.backgroundWakeRefreshAllowance
        await flushForBackgroundWake(until: deadline, callTimeout: max(remaining, Self.backgroundWakeMinimumCallTimeout))
    }

    func flushForBackgroundWake(deadline: Duration, callTimeout: Duration) async {
        await flushForBackgroundWake(until: ContinuousClock.now + deadline, callTimeout: callTimeout)
    }

    func flushForBackgroundWake(until deadline: ContinuousClock.Instant, callTimeout: Duration) async {
        let isActive = await isForegroundProcess()
        // The system completes an upload even when the app is suspended soon after this returns.
        if !isActive, await handOffToUploader(until: deadline) { return }
        // A foreground flush is the app's own and keeps running, as it does for any other trigger.
        await race(until: deadline, timeoutValue: (), cancelsWork: !isActive) { [self] in
            if isActive {
                await runFlush(attempt: 1)
            } else {
                await runBoundedFlush(callTimeout: callTimeout)
            }
        }
    }

    /// Hands the queued deliveries to the background uploader, marking them in flight. Returns whether it did, or
    /// had nothing to hand over; `false` leaves the deliveries to the in-process flush.
    ///
    /// A flush that is running is waited for, as the batch it carries is not marked and would be sent twice. An access
    /// token that is expired is refreshed first: the upload cannot retry a 401 once the app is suspended.
    private func handOffToUploader(until deadline: ContinuousClock.Instant) async -> Bool {
        guard let uploader = dependencies.uploader?() else { return false }
        let start: (session: Session, generation: Int, token: String, baseURL: URL, hasWork: Bool)? =
            await onScheduler { [self] in
                guard let session, canSend(session), let baseURL = session.reportBaseURL,
                      let token = try? session.authDataSource.currentAccessToken() else { return nil }
                return (session, generation, token, baseURL, hasWork: !nextUnsentBatch().isEmpty)
            }
        guard let start else { return false }
        guard start.hasWork else { return true }
        guard await waitUntilIdle(until: deadline) else { return false }
        var token = start.token
        if dependencies.isAccessTokenExpired(token) {
            guard let refreshed = await refreshedAccessToken(of: start.session, until: deadline) else { return false }
            token = refreshed
        }
        let accessToken = token
        return await onScheduler { [self] in
            // A flush that started meanwhile, or another session, leaves the deliveries to the in-process flush.
            guard !isFlushing, generation == start.generation, canSend(start.session) else { return false }
            let nowMs = dependencies.scheduler.nowMs()
            // Bounded by the outbox's capacity; a batch the uploader refuses ends the loop.
            for _ in 0..<(DeliveryReportOutbox.capacity / Self.batchSize + 1) {
                let batch = nextUnsentBatch()
                guard !batch.isEmpty else { return true }
                outbox.markInFlight(batch, untilMs: nowMs + Self.uploadInFlightDurationMs)
                let deliveries = batch.map { ReportedDelivery(messageID: $0.messageID, subscriberID: $0.subscriberID) }
                guard uploader.upload(deliveries, accessToken: accessToken, baseURL: start.baseURL) else {
                    outbox.clearInFlight(batch)
                    return false
                }
            }
            return true
        }
    }

    /// The access token after a refresh, or `nil` when it failed or `deadline` came first.
    private func refreshedAccessToken(of session: Session, until deadline: ContinuousClock.Instant) async -> String? {
        await race(until: deadline, timeoutValue: nil) {
            do {
                return try await session.authDataSource.refreshToken().accessToken
            } catch {
                Logger.warning("push delivery reports: the access token could not be refreshed")
                return nil
            }
        }
    }

    /// What a background upload finished with. Accepted deliveries leave the outbox; the others go back to the
    /// normal flush, which sends them at its next trigger.
    ///
    /// Returns once the outbox is saved: the system's completion handler of the background session may be called as
    /// soon as the upload's delegate callback returns, and the app is suspended after it. Call it off the scheduler's
    /// queue, as the session's delegate queue is; it gives up waiting after a couple of seconds.
    func uploadFinished(_ deliveries: [ReportedDelivery], accepted: Bool) {
        let applied = DispatchSemaphore(value: 0)
        dependencies.scheduler.perform { [self] in
            defer { applied.signal() }
            let reports = deliveries.map {
                DeliveryReport(messageID: $0.messageID, subscriberID: $0.subscriberID, enqueuedAtMs: 0)
            }
            if accepted {
                outbox.remove(reports)
            } else {
                outbox.clearInFlight(reports)
            }
        }
        _ = applied.wait(timeout: .now() + 2)
    }

    /// The next batch to send, without the deliveries a background upload has reported already. Those are dropped.
    /// Only call it on the scheduler's queue.
    private func nextUnsentBatch() -> [DeliveryReport] {
        while true {
            let batch = outbox.nextBatch(nowMs: dependencies.scheduler.nowMs(), limit: Self.batchSize)
            guard let sentDeliveries = dependencies.sentDeliveries, !batch.isEmpty else { return batch }
            let sent = sentDeliveries(batch.map { ReportedDelivery(messageID: $0.messageID, subscriberID: $0.subscriberID) })
            let reported = batch.filter {
                sent.contains(ReportedDelivery(messageID: $0.messageID, subscriberID: $0.subscriberID))
            }
            guard !reported.isEmpty else { return batch }
            outbox.remove(reported)
            let unsent = batch.filter { report in !reported.contains { $0.isSameDelivery(as: report) } }
            if !unsent.isEmpty { return unsent }
        }
    }

    /// Whether the app is in the foreground, where a flush may schedule its backoff retries.
    private func isForegroundProcess() async -> Bool {
        guard !dependencies.isNotificationServiceExtension() else { return false }
        return await MainActor.run { dependencies.isApplicationActive() }
    }

    /// Runs the passes of a background wake: no backoff retry is scheduled or cancelled.
    private func runBoundedFlush(callTimeout: Duration) async {
        while true {
            switch await onScheduler({ self.beginFlush(requestRerun: false) }) {
            case .nothingToSend:
                return
            case .busy:
                await waitUntilIdle()
                guard !Task.isCancelled else { return }
            case .started(let session, let generation):
                _ = await sendBatches(session: session, generation: generation, callTimeout: callTimeout)
                let again = await onScheduler {
                    self.endFlush(generation: generation, retryAfterAttempt: nil)
                }
                guard again else { return }
                // The rerun belongs to a trigger that expects the normal flush, backoff retries included. Once the
                // wake is over, or the app is active, it goes there instead of looping here.
                if Task.isCancelled {
                    flush()
                    return
                }
                if await isForegroundProcess() {
                    flush()
                    return
                }
            }
        }
    }

    /// Returns whether no flush is running before `deadline`.
    private func waitUntilIdle(until deadline: ContinuousClock.Instant) async -> Bool {
        await race(until: deadline, timeoutValue: false) { [self] in
            await waitUntilIdle()
            return true
        }
    }

    /// Returns when no flush is running.
    private func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            dependencies.scheduler.perform {
                if self.isFlushing {
                    self.idleWaiters.append(continuation)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Runs passes until one finds nothing to do or no trigger came in meanwhile.
    /// A pass run for a trigger that arrived meanwhile counts as the first attempt of that trigger.
    private func runFlush(attempt firstAttempt: Int) async {
        var attempt = firstAttempt
        while case .started(let session, let generation) = await onScheduler({ self.beginFlush(requestRerun: true) }) {
            let start = (session: session, generation: generation)
            let needsRetry = await sendBatches(session: start.session, generation: start.generation, callTimeout: nil)
            let retryAfter = needsRetry ? attempt : nil
            let again = await onScheduler {
                self.endFlush(generation: start.generation, retryAfterAttempt: retryAfter)
            }
            guard again else { return }
            attempt = 1
        }
    }

    /// What starting a pass came to.
    private enum PassStart {
        case started(Session, generation: Int)
        /// A pass is running.
        case busy
        case nothingToSend
    }

    /// Starts a pass, when there is something to send. With `requestRerun`, a pass already running is asked to run
    /// again, and the pending backoff retry is replaced by this pass.
    private func beginFlush(requestRerun: Bool) -> PassStart {
        guard !isFlushing else {
            if requestRerun {
                rerunRequested = true
                return .nothingToSend
            }
            return .busy
        }
        guard let session, canSend(session), !outbox.isEmpty else { return .nothingToSend }
        if requestRerun {
            retryTask?.cancel()
            retryTask = nil
        }
        isFlushing = true
        return .started(session, generation: generation)
    }

    /// Ends a pass. Returns whether another one is due.
    private func endFlush(generation startGeneration: Int, retryAfterAttempt attempt: Int?) -> Bool {
        isFlushing = false
        let waiters = idleWaiters
        idleWaiters = []
        defer {
            waiters.forEach { $0.resume() }
            onPassFinished?()
        }
        let again = rerunRequested
        rerunRequested = false
        if let attempt, startGeneration == generation, !again {
            scheduleRetry(afterAttempt: attempt)
        }
        return again
    }

    /// Whether the deliveries can be sent now.
    private func canSend(_ session: Session) -> Bool {
        guard !dependencies.isNotificationServiceExtension() else { return false }
        guard let token = try? session.authDataSource.currentAccessToken(), !token.isEmpty else { return false }
        return true
    }

    /// Sends the queued deliveries in batches, until the outbox is empty or a batch is kept.
    /// Returns whether the kept batch is to be tried again after a backoff.
    private func sendBatches(session: Session, generation: Int, callTimeout: Duration?) async -> Bool {
        let sender = dependencies.makeSender(session.authDataSource, session.client)
        while true {
            let batch = await onScheduler {
                guard self.generation == generation else { return [DeliveryReport]() }
                return self.nextUnsentBatch()
            }
            guard !batch.isEmpty else { return false }
            switch await send(batch, session: session, sender: sender, callTimeout: callTimeout) {
            case .accepted, .refused:
                let current = await onScheduler {
                    guard self.generation == generation else { return false }
                    self.outbox.remove(batch)
                    return true
                }
                guard current else { return false }
            case .keep:
                return false
            case .retry:
                return true
            }
        }
    }

    /// Sends one batch, refreshing the access token once when the server rejects it.
    private func send(_ batch: [DeliveryReport],
                      session: Session,
                      sender: DeliveryReportSending,
                      callTimeout: Duration?) async -> BatchOutcome {
        do {
            try await sender.reportEvents(batch, timeout: callTimeout)
            return .accepted
        } catch let error as GrpcWebError where error.grpcStatusCode == GrpcWebStatus.unauthenticated {
            return await sendAfterRefresh(batch, session: session, sender: sender, callTimeout: callTimeout)
        } catch {
            return outcome(for: error)
        }
    }

    /// Refreshes the access token and sends the batch once more.
    private func sendAfterRefresh(_ batch: [DeliveryReport],
                                  session: Session,
                                  sender: DeliveryReportSending,
                                  callTimeout: Duration?) async -> BatchOutcome {
        do {
            _ = try await session.authDataSource.refreshToken()
        } catch {
            Logger.warning("push delivery reports: the access token could not be refreshed")
            return .keep
        }
        do {
            try await sender.reportEvents(batch, timeout: callTimeout)
            return .accepted
        } catch let error as GrpcWebError where error.grpcStatusCode == GrpcWebStatus.unauthenticated {
            return .keep
        } catch {
            return outcome(for: error)
        }
    }

    /// What an error means for the batch.
    private func outcome(for error: Error) -> BatchOutcome {
        guard let webError = error as? GrpcWebError, let code = webError.grpcStatusCode else { return .retry }
        switch code {
        case GrpcWebStatus.invalidArgument, GrpcWebStatus.notFound, GrpcWebStatus.permissionDenied:
            Logger.warning("push delivery reports: the server refused a batch (\(GrpcWebStatus.name(code)))")
            return .refused
        case GrpcWebStatus.unavailable, GrpcWebStatus.deadlineExceeded:
            return .retry
        default:
            return .keep
        }
    }

    /// Schedules the next attempt of a trigger, until the attempt cap is reached.
    private func scheduleRetry(afterAttempt attempt: Int) {
        guard attempt < Self.maxAttemptsPerTrigger else {
            Logger.warning("push delivery reports: the batch is kept after \(attempt) attempts")
            return
        }
        let delay = ReconnectBackoff.delayMs(attempts: attempt, using: dependencies.random)
        let startGeneration = generation
        retryTask = dependencies.scheduler.schedule(after: delay) { [weak self] in
            guard let self, self.generation == startGeneration else { return }
            Task { await self.runFlush(attempt: attempt + 1) }
        }
    }

    /// Runs `work` on the scheduler's queue and returns its result.
    private func onScheduler<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            dependencies.scheduler.perform {
                continuation.resume(returning: work())
            }
        }
    }
}

/// Runs `work` and returns its result, or `timeoutValue` when `deadline` comes first. Unlike a task group it does not
/// wait for work that ignores cancellation, so the caller is back by `deadline`. With `cancelsWork` the work is
/// cancelled when the deadline wins.
private func race<Value: Sendable>(until deadline: ContinuousClock.Instant,
                                   timeoutValue: Value,
                                   cancelsWork: Bool = true,
                                   _ work: @escaping @Sendable () async -> Value) async -> Value {
    let first = FirstResult<Value>()
    let worker = Task { first.deliver(await work()) }
    let timer = Task {
        try? await Task.sleep(until: deadline, clock: .continuous)
        first.deliver(timeoutValue)
    }
    let value = await first.wait()
    timer.cancel()
    if cancelsWork { worker.cancel() }
    return value
}

/// Lets the first of several results through.
private final class FirstResult<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    /// Boxed, as `Value` may be an optional itself.
    private struct Delivered { let value: Value }
    private var result: Delivered?
    private var waiter: CheckedContinuation<Value, Never>?

    func deliver(_ value: Value) {
        let waiter = lock.withLock { () -> CheckedContinuation<Value, Never>? in
            guard result == nil else { return nil }
            result = Delivered(value: value)
            defer { self.waiter = nil }
            return self.waiter
        }
        waiter?.resume(returning: value)
    }

    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> Value? in
                if let result { return result.value }
                waiter = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }
}

extension DeliveryReporter.Dependencies {
    /// The production wiring: the socket's queue, the system jitter and the push API of the region.
    /// - Parameters:
    ///   - uploaders: The background uploads of a wake in the background, and the markers they leave.
    ///   - metadata: The locale and SDK version every call carries.
    static func live(scheduler: Scheduler, uploaders: ReportUploaders? = nil,
                     metadata: StandardMetadata = .init()) -> DeliveryReporter.Dependencies {
        DeliveryReporter.Dependencies(
            scheduler: scheduler,
            random: SystemRandomSource(),
            makeSender: { authDataSource, client in
                PushAPIDeliveryReportSender(client: client, authDataSource: authDataSource, metadata: metadata)
            },
            isApplicationActive: {
                Thread.isMainThread && MainActor.assumeIsolated { UIApplication.shared.applicationState == .active }
            },
            isNotificationServiceExtension: { Bundle.main.bundleURL.pathExtension == "appex" },
            notificationCenter: .default,
            uploader: liveUploader(uploaders),
            sentDeliveries: liveSentDeliveries(uploaders),
            pendingDeliveries: livePendingDeliveries(uploaders))
    }

    private static func liveUploader(_ uploaders: ReportUploaders?) -> (@Sendable () -> DeliveryReportUploading?)? {
        guard let uploaders else { return nil }
        return { uploaders.uploader(forIdentifier: BackgroundReportUploader.baseIdentifier) }
    }

    private static func livePendingDeliveries(_ uploaders: ReportUploaders?) -> (@Sendable () -> [PendingDelivery])? {
        guard let uploaders else { return nil }
        // PendingDelivery is the extension's record of an upload that failed; the app reports it itself.
        return { uploaders.container.takePendingDeliveries() }
    }

    private static func liveSentDeliveries(
        _ uploaders: ReportUploaders?
    ) -> (@Sendable ([ReportedDelivery]) -> Set<ReportedDelivery>)? {
        guard let uploaders else { return nil }
        return { SentReportMarkerStore(container: uploaders.container).sent(among: $0) }
    }
}
