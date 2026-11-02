import Foundation

/// What ``ReportTracker/reportsToSend(nowMs:mode:)`` is being asked for.
enum OutboxFlushMode: Sendable, Equatable {
    /// After `HelloAck`.
    case all
    /// A `rate_limited` deferral has expired.
    case deferredOnly
    /// A poll tick: bounded retry of `upstream_forward_failed` only. Deferred entries are excluded.
    case forwardFailureRetryOnly
}

/// The result of an `Ack`, for the client to act on.
enum AckOutcome: Sendable, Equatable {
    /// Correlated and accepted: the entry is now marked reported.
    case accepted
    /// Correlated and refused; the error string names the rejection.
    case rejected(error: String)
    /// Nothing was correlated. Logged, and nothing else changes.
    case uncorrelated
}

/// The delivery-report state machine, the sent-set and the outbox.
///
/// * The Ack token is constructed, never parsed, so a `:` in a message id is harmless.
/// * A `rate_limited` rejection defers on its own timer, not on the poll tick being throttled.
/// * A sent-but-unanswered entry is not re-sent while the connection lives. It returns
///   to queued when the connection closes.
final class ReportTracker {

    /// Fixed, like every other limit.
    static let outboxCapacity = 200

    /// Larger than the seen set, since one message can carry several statuses.
    static let sentSetCapacity = SeenSet.capacity * 4

    /// Bounds retries of `upstream_forward_failed`, which waiting does not fix.
    static let maxForwardFailureRetries = 3

    private let store: SocketStateStore
    private let logger: SocketLogger
    private let random: RandomSource
    private let now: () -> Int64

    /// Oldest first: the eviction order when the outbox is full.
    private var pending: [PendingReport] = []
    /// Reported keys, "id:statusNumber". Persisted with the seen set so a restart does not re-report.
    private var sentKeys = SeenSet(limit: ReportTracker.sentSetCapacity)
    /// Keys handed to the transport and not yet answered. In memory only, so a restart resends.
    private var inFlight: Set<String> = []
    /// See ``retire()``.
    private var retired = false

    /// Set whenever an Ack was refused, so the client can put it in `lastError`.
    var onRejection: ((String) -> Void)?

    init(store: SocketStateStore, logger: SocketLogger, random: RandomSource, now: @escaping () -> Int64) {
        self.store = store
        self.logger = logger
        self.random = random
        self.now = now
        self.pending = store.loadOutbox()
        self.sentKeys = SeenSet(limit: ReportTracker.sentSetCapacity, persisted: store.loadReportedKeys())
    }

    /// Queues a report, at most once per `(message_id, status)`.
    ///
    /// `sentKeys` grows only on an accepted Ack. A report that is dropped (after its
    /// retries, as `unsupported_status`, or by eviction) is not counted, so a later
    /// socket hit for that id sends it again.
    ///
    /// - Returns: `true` when queued. `false` means already reported, already queued,
    ///   or not sendable.
    @discardableResult
    func queue(
        messageId: String,
        sinchMessageId: String,
        status: SocketDeliveryStatus,
        reason: String = ""
    ) -> Bool {
        guard !retired else { return false }
        guard !messageId.isEmpty else {
            // The relay refuses this as `missing_message_id`.
            logger.log("dropping \(status.rawValue) report with an empty message_id: \(reason)", level: .warning)
            return false
        }
        let entry = PendingReport(
            messageId: messageId,
            sinchMessageId: sinchMessageId,
            status: status,
            reason: reason,
            attempts: 0,
            deferUntilMs: nil)
        let key = entry.sentKey
        guard !sentKeys.contains(key) else {
            logger.log("suppressing duplicate \(status.rawValue) report for \(messageId)")
            return false
        }
        guard !pending.contains(where: { $0.sentKey == key }) else {
            return false
        }
        pending.append(entry)
        evictIfNeeded()
        persistOutbox()
        return true
    }

    /// A pooled message that could not be decoded becomes a `FAILED` report.
    @discardableResult
    func queueFailure(messageId: String, sinchMessageId: String, detail: String) -> Bool {
        queue(
            messageId: messageId,
            sinchMessageId: sinchMessageId,
            status: .failed,
            reason: "decode: \(detail)")
    }

    private func evictIfNeeded() {
        while pending.count > ReportTracker.outboxCapacity {
            let dropped = pending.removeFirst()
            logger.log(
                "outbox full (\(ReportTracker.outboxCapacity)); dropped oldest report "
                    + "\(dropped.status.rawValue) for \(dropped.messageId)",
                level: .warning)
        }
    }

    /// The reports to hand to the transport, in queue order.
    func reportsToSend(nowMs: Int64, mode: OutboxFlushMode) -> [PendingReport] {
        var out: [PendingReport] = []
        for entry in pending {
            if inFlight.contains(entry.sentKey) { continue }
            switch mode {
            case .all:
                if let deferUntilMs = entry.deferUntilMs, deferUntilMs > nowMs { continue }
                out.append(entry)
            case .deferredOnly:
                guard let deferUntilMs = entry.deferUntilMs, deferUntilMs <= nowMs else { continue }
                out.append(entry)
            case .forwardFailureRetryOnly:
                guard entry.deferUntilMs == nil, entry.attempts > 0 else { continue }
                out.append(entry)
            }
        }
        return out
    }

    /// Marks entries as handed to the transport, so one connection does not send them twice.
    func markSent(_ entries: [PendingReport]) {
        for entry in entries where !inFlight.contains(entry.sentKey) {
            inFlight.insert(entry.sentKey)
        }
    }

    /// The connection is gone, so in-flight entries can no longer be acknowledged and are queued again.
    func connectionClosed() {
        inFlight.removeAll()
    }

    /// Forgets every queued report, in memory and on disk. The sent-keys are kept.
    func clearOutbox() {
        pending.removeAll()
        inFlight.removeAll()
        persistOutbox()
    }

    /// Re-reads the outbox and sent-keys from the store. Called on the scheduler, so it runs after the previous client's writes.
    func reloadFromStore() {
        guard !retired else { return }
        pending = store.loadOutbox()
        sentKeys = SeenSet(limit: ReportTracker.sentSetCapacity, persisted: store.loadReportedKeys())
        inFlight.removeAll()
    }

    /// Drops everything and never touches the store again, since a replacement client shares it.
    func retire() {
        retired = true
        pending.removeAll()
        sentKeys = SeenSet(limit: ReportTracker.sentSetCapacity)
        inFlight.removeAll()
    }

    /// Number of reports waiting, for tests and diagnostics.
    var pendingCount: Int { pending.count }

    /// Keys already reported, oldest first, for persistence.
    var reportedKeys: [String] { sentKeys.persisted }

    /// Applies an `Ack`.
    @discardableResult
    func handle(_ ack: Sinch_Push_Delivery_V1beta1_Ws_Ack) -> AckOutcome {
        let token = ack.ackToken
        guard !token.isEmpty else {
            logger.log("ack with an empty token is uncorrelatable; nothing changed")
            return .uncorrelated
        }
        guard let index = pending.firstIndex(where: { $0.ackToken == token }) else {
            logger.log("ack token \(token) matches no queued report; nothing changed")
            return .uncorrelated
        }
        if ack.accepted {
            let accepted = pending.remove(at: index)
            // The only place `sentKeys` changes, so the only place it is persisted.
            if sentKeys.insert(accepted.sentKey) { persistSentKeys() }
            inFlight.remove(accepted.sentKey)
            persistOutbox()
            return .accepted
        }
        return applyRejection(
            to: index,
            error: ack.error,
            messageId: pending[index].messageId)
    }

    private func applyRejection(
        to index: Int,
        error: String,
        messageId: String
    ) -> AckOutcome {
        onRejection?(error.isEmpty ? "ack rejected (\(messageId))" : error)

        switch error {
        case "rate_limited":
            // Defer with backoff, using the same full-jitter family as reconnects.
            var entry = pending[index]
            entry.attempts += 1
            let delay = ReconnectBackoff.delayMs(attempts: entry.attempts, using: random)
            entry.deferUntilMs = now() + Int64(delay)
            pending[index] = entry
            inFlight.remove(entry.sentKey)
            persistOutbox()
            logger.log(
                "report \(entry.status.rawValue) for \(entry.messageId) deferred "
                    + "\(delay)ms (rate_limited)",
                level: .warning)
            return .rejected(error: error)

        case "upstream_forward_failed":
            var entry = pending[index]
            entry.attempts += 1
            if entry.attempts > ReportTracker.maxForwardFailureRetries {
                pending.remove(at: index)
                inFlight.remove(entry.sentKey)
                persistOutbox()
                logger.log(
                    "dropping \(entry.status.rawValue) report for \(entry.messageId) after "
                        + "\(entry.attempts) forward failures",
                    level: .warning)
                return .rejected(error: error)
            }
            // No deferral: the next poll tick retries this one.
            entry.deferUntilMs = nil
            pending[index] = entry
            inFlight.remove(entry.sentKey)
            persistOutbox()
            logger.log(
                "report \(entry.status.rawValue) for \(entry.messageId) will retry on the "
                    + "next poll (attempt \(entry.attempts))",
                level: .warning)
            return .rejected(error: error)

        case "unsupported_status":
            // Permanent for this status against this relay version.
            let entry = pending.remove(at: index)
            inFlight.remove(entry.sentKey)
            persistOutbox()
            logger.log(
                "dropping \(entry.status.rawValue) report for \(entry.messageId): the relay "
                    + "does not support this status",
                level: .warning)
            return .rejected(error: error)

        default:
            // Unknown or empty errors change no policy.
            logger.log("ack refused with error '\(error)'; no policy change", level: .warning)
            return .rejected(error: error)
        }
    }

    /// The `sinch_message_id` of a queued report for `messageId`, or `nil`.
    func sinchMessageId(for messageId: String) -> String? {
        pending.first(where: { $0.messageId == messageId })?.sinchMessageId
    }

    /// The earliest deferral among queued, not-in-flight reports, or `nil`. A due
    /// deadline is included, so its timer fires at once. In-flight entries are excluded,
    /// or the timer would spin until their Ack.
    func nextDeferral() -> Int64? {
        pending
            .filter { !inFlight.contains($0.sentKey) }
            .compactMap(\.deferUntilMs)
            .min()
    }

    // The sent-set can hold about 8000 keys, so it is rewritten only when an Ack is accepted.

    private func persistOutbox() {
        guard !retired else { return }
        store.saveOutbox(pending)
    }

    private func persistSentKeys() {
        guard !retired else { return }
        store.saveReportedKeys(sentKeys.persisted)
    }
}
