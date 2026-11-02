import Foundation

extension SocketClient {

    /// Handles one pooled message: a `Message` frame, or an entry in a `HelloAck` pool.
    ///
    /// Persist the seen set and cursor, and queue DELIVERED, before publishing or
    /// presenting. A dedupe hit still reports DELIVERED.
    func emitMessage(
        _ pooled: Sinch_Push_Delivery_V1beta1_Ws_PooledMessage,
        ackToken: String
    ) {
        // Keyed by `PooledMessage.message_id`, never `Message.ack_token`, which the relay mints separately.
        let messageId = pooled.messageID
        guard !messageId.isEmpty else {
            log("dropping pooled message with an empty message_id", level: .warning)
            return
        }
        // A hit suppresses presentation only. The relay still waits for DELIVERED, or it
        // re-pushes the message after an ACK_TIMEOUT. The cursor advances only on a newer timestamp.
        guard seen.markSeen(messageId) else {
            advanceLastSeen(
                messageId: messageId, enqueuedAtMs: pooled.enqueuedAtUnixMillis, onHit: true)
            tracker.queue(
                messageId: messageId,
                sinchMessageId: pooled.sinchMessageID,
                status: .delivered)
            flushIfConnected(.all)
            log("duplicate message \(messageId); acked, no event, no notification")
            return
        }
        // The seen set and cursor are persisted before DELIVERED is queued, so a crash
        // after the ack cannot turn a replay into a second DELIVERED.
        advanceLastSeen(messageId: messageId, enqueuedAtMs: pooled.enqueuedAtUnixMillis)
        tracker.queue(
            messageId: messageId,
            sinchMessageId: pooled.sinchMessageID,
            status: .delivered)
        flushIfConnected(.all)

        let event = SocketMessageEvent(
            pooled: pooled, ackToken: ackToken, receivedAt: scheduler.nowMs())
        storePending(event)

        callbacks.onMessage?(event)

        guard shouldDisplayNotification else { return }
        // A copy APNs already showed is not posted again. The event above still went out.
        let epoch = sessionEpoch
        deliveredNotifications.isDelivered(identifier: messageId) { [weak self] delivered in
            guard let self else { return }
            // The lookup answers on the system's queue, so hop back to the scheduler.
            self.scheduler.perform {
                guard !self.stopped, epoch == self.sessionEpoch else { return }
                if delivered {
                    self.markShown(messageId: messageId)
                    self.log("message \(messageId) is already in the notification centre; not posting")
                    return
                }
                self.post(event, pooled: pooled)
            }
        }
    }

    func post(
        _ event: SocketMessageEvent, pooled: Sinch_Push_Delivery_V1beta1_Ws_PooledMessage
    ) {
        let messageId = event.id
        presenter.post(event, alerting: takeAlertSlot()) { [weak self] posted in
            guard let self, posted else { return }
            self.scheduler.perform {
                // A retired client shares its store with its replacement, so it writes nothing.
                guard !self.retired else { return }
                self.markShown(messageId: messageId)
                // DISPLAYED is queued like any other report, so it survives a disconnected socket.
                self.tracker.queue(
                    messageId: messageId,
                    sinchMessageId: pooled.sinchMessageID,
                    status: .displayed)
                self.flushIfConnected(.all)
            }
        }
    }

    func storePending(_ event: SocketMessageEvent) {
        guard !retired else { return }
        // Append and trim in one critical section, so a reader never sees capacity + 1.
        let (snapshot, dropped): ([SocketMessageEvent], SocketMessageEvent?) = shared.withLock {
            $0.pendingMessages.append(event)
            let dropped =
                $0.pendingMessages.count > SocketClient.pendingMessageCapacity
                ? $0.pendingMessages.removeFirst() : nil
            return ($0.pendingMessages, dropped)
        }
        if let dropped {
            log("pending message store full; dropped \(dropped.id)", level: .warning)
        }
        store.savePendingMessages(snapshot)
    }

    /// Advances the cursor to the newest received message.
    ///
    /// Relay ids are opaque, so "newest" comes from `enqueued_at_unix_millis`. The
    /// cursor moves only for a message enqueued at or after the one it names. With no
    /// timestamps, arrival order decides. A dedupe hit (`onHit`) moves it only on a
    /// known, strictly newer timestamp.
    func advanceLastSeen(messageId: String, enqueuedAtMs: Int64, onHit: Bool = false) {
        guard !retired else { return }
        if onHit && !(enqueuedAtMs > 0 && (lastSeenEnqueuedAtMs == 0 || enqueuedAtMs > lastSeenEnqueuedAtMs)) {
            return
        }
        let known = enqueuedAtMs > 0 && lastSeenEnqueuedAtMs > 0
        if known && enqueuedAtMs < lastSeenEnqueuedAtMs {
            return
        }
        lastSeenMessageID = messageId
        lastSeenEnqueuedAtMs = max(enqueuedAtMs, 0)
        store.saveLastSeen(id: lastSeenMessageID, enqueuedAtMs: lastSeenEnqueuedAtMs)
    }

    /// Whether the next notification may alert. Only the first in each window alerts.
    /// The slot is taken when the post is attempted, so a burst cannot all alert.
    func takeAlertSlot() -> Bool {
        let now = scheduler.nowMs()
        if let last = lastAlertAtMs, now - last < SocketClient.notificationAlertWindowMs {
            return false
        }
        lastAlertAtMs = now
        return true
    }

    var shouldDisplayNotification: Bool {
        let rule = configuration?.displayNotifications ?? .whenUnhandled
        switch rule {
        case .never: return false
        case .always: return true
        case .whenUnhandled: return !presenter.handlerRegistered
        }
    }

    func markShown(messageId: String) {
        if let index = pendingMessages.firstIndex(where: { $0.id == messageId }) {
            pendingMessages[index].shown = true
            store.savePendingMessages(pendingMessages)
        }
    }

    func sinchMessageId(for messageId: String) -> String {
        pendingMessages.first(where: { $0.id == messageId })?.sinchMessageId
            ?? tracker.sinchMessageId(for: messageId)
            ?? ""
    }
}
