import Foundation
import os

/// The foreground-only delivery-channel client.
///
/// `@unchecked Sendable`, sound because every stored property is confined to the
/// ``Scheduler``'s context: entry points, transport callbacks and timers all hop
/// through `scheduler.perform` / `scheduler.schedule` first. The exceptions are
/// ``currentState``, ``currentPendingMessages``, ``setCallbacks(_:)`` and
/// ``setHandlerRegistered(_:)``, which a host calls from its own thread and which
/// are guarded by `shared`.
///
/// `seenRegistry` has no default: socket and APNs dedupe only agree if both use the
/// same process-wide registry.
final class SocketClient: @unchecked Sendable {

    /// Used when neither the config nor the server supplies an interval.
    static let defaultPollIntervalMs = 5000

    /// Floor on the poll interval, so a server request for a shorter one is raised to this.
    static let minPollIntervalMs = 1000

    /// Bound on `getPendingPushMessages`, matching the outbox bound.
    static let pendingMessageCapacity = 200

    /// At most one alerting system notification per window; the rest are posted silently.
    static let notificationAlertWindowMs: Int64 = 2000

    /// Host-facing events, invoked on the scheduler's context.
    struct Callbacks: Sendable {
        var onState: (@Sendable (SocketState) -> Void)?
        /// One delivered pooled message. Not fired for a dedupe hit, which is still acked DELIVERED.
        var onMessage: (@Sendable (SocketMessageEvent) -> Void)?
        var onLog: (@Sendable (String) -> Void)?
        /// Fired at most once per start, on `Close(UNAUTHORIZED)`. The host refreshes
        /// the credential and calls ``updateConfiguration(_:)``.
        var onAuthRequired: (@Sendable () -> Void)?
    }

    let transportFactory: SocketTransportFactory
    let scheduler: Scheduler
    let random: RandomSource
    let store: SocketStateStore
    let tokenStore: AuthTokenStore
    let deviceInfo: DeviceInfoProviding
    let presenter: NotificationPresenting
    let deliveredNotifications: DeliveredNotificationLookup
    let logger: SocketLogger
    let seen: SeenMessageRegistry

    /// State a host reads from its own thread. Scheduler-confined code uses the
    /// computed accessors below.
    struct Shared: Sendable {
        var callbacks: Callbacks
        var state = SocketState(status: .idle)
        var pendingMessages: [SocketMessageEvent] = []
    }
    let shared: OSAllocatedUnfairLock<Shared>

    var callbacks: Callbacks {
        get { shared.withLock { $0.callbacks } }
        set { shared.withLock { $0.callbacks = newValue } }
    }
    var state: SocketState {
        get { shared.withLock { $0.state } }
        set { shared.withLock { $0.state = newValue } }
    }
    var pendingMessages: [SocketMessageEvent] {
        get { shared.withLock { $0.pendingMessages } }
        set { shared.withLock { $0.pendingMessages = newValue } }
    }

    var configuration: SocketConfiguration?
    var transport: SocketTransport?

    /// Monotonic socket id. A callback from a replaced socket is ignored, so a
    /// trailing `onClose` cannot schedule a second reconnect.
    var generation = 0

    var pollTask: ScheduledTask?
    var reconnectTask: ScheduledTask?
    var deferralTask: ScheduledTask?

    var attempts = 0
    /// `attempts` before this session's `HelloAck` zeroed it, restored if the reset is forfeited.
    var attemptsBeforeHelloAck = 0
    /// Whether the session's `HelloAck` reset is still unspent.
    var helloAckResetArmed = false

    var pollIntervalMs = SocketClient.defaultPollIntervalMs

    var lastSeenMessageID = ""
    /// `enqueued_at_unix_millis` of the message `lastSeenMessageID` names; 0 when unknown.
    var lastSeenEnqueuedAtMs: Int64 = 0
    /// When the last alerting notification was posted; nil before the first.
    var lastAlertAtMs: Int64?
    /// Built in `init`; the rejection callback captures the client weakly.
    let tracker: ReportTracker

    /// Terminal: `stop()`, `Close(UNAUTHORIZED)`, `Close(BG_RESUMED)`.
    var stopped = false
    /// ``retire()`` was called; the client never runs or writes again.
    var retired = false
    /// Bumped whenever the running client is invalidated. Deferred work that outlives
    /// the call that queued it captures this. Unlike `generation`, an ordinary
    /// reconnect does not bump it.
    var sessionEpoch = 0
    /// Backgrounded: config is kept, nothing is flushed, nothing retries.
    var suspended = false
    /// One credential refresh attempt per start.
    var authRefreshAttempted = false
    var didLoadPersistedState = false

    init(
        configuration: SocketConfiguration? = nil,
        transportFactory: SocketTransportFactory,
        scheduler: Scheduler,
        random: RandomSource,
        store: SocketStateStore,
        tokenStore: AuthTokenStore,
        presenter: NotificationPresenting = NoopNotificationPresenter(),
        logger: SocketLogger = SilentSocketLogger(),
        deviceInfo: DeviceInfoProviding = StaticDeviceInfoProvider(),
        deliveredNotifications: DeliveredNotificationLookup = NoDeliveredNotifications(),
        seenRegistry: SeenMessageRegistry,
        callbacks: Callbacks = Callbacks()
    ) {
        self.transportFactory = transportFactory
        self.scheduler = scheduler
        self.random = random
        self.store = store
        self.tokenStore = tokenStore
        self.deviceInfo = deviceInfo
        self.presenter = presenter
        self.deliveredNotifications = deliveredNotifications
        self.logger = logger
        self.seen = seenRegistry
        self.shared = OSAllocatedUnfairLock(initialState: Shared(callbacks: callbacks))
        self.tracker = ReportTracker(
            store: store, logger: logger, random: random, now: { scheduler.nowMs() })
        self.tracker.onRejection = { [weak self] error in self?.recordAckRejection(error) }
        self.configuration = configuration
    }

    func setCallbacks(_ callbacks: Callbacks) {
        self.callbacks = callbacks
    }

    /// Whether the host has an in-app handler registered, which the `whenUnhandled` rule keys on.
    func setHandlerRegistered(_ registered: Bool) {
        presenter.handlerRegistered = registered
    }

    /// Connect, or resume after a stop.
    func start() {
        scheduler.perform { [weak self] in
            guard let self, !self.retired else { return }
            self.loadPersistedStateIfNeeded()
            self.stopped = false
            self.suspended = false
            self.attempts = 0
            self.authRefreshAttempted = false
            self.persistConfiguration()
            self.open()
        }
    }

    /// Stop until the host calls ``start()`` again.
    func stop() {
        scheduler.perform { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.sessionEpoch += 1
            self.suspended = false
            self.clearTimers()
            self.closeSocket()
            self.publish(status: .stopped)
        }
    }

    /// `UIApplication.didEnterBackground`: close with 1000 and keep the config. The
    /// outbox is written on each mutation, not here.
    func suspend() {
        scheduler.perform { [weak self] in
            guard let self, !self.stopped else { return }
            guard !self.suspended else { return }
            self.suspended = true
            self.clearTimers()
            self.closeSocket()
            self.tracker.connectionClosed()
            self.publish(status: .idle)
        }
    }

    /// Reconnect after backgrounding. The immediate poll and outbox flush follow the `HelloAck`.
    func resume() {
        scheduler.perform { [weak self] in
            guard let self, !self.stopped else { return }
            guard self.suspended else { return }
            self.suspended = false
            self.attempts = 0
            self.open()
        }
    }

    /// Reconnects with a fresh `Hello`. It is also the only way out of `auth_required`.
    func updateConfiguration(_ configuration: SocketConfiguration) {
        scheduler.perform { [weak self] in
            guard let self, !self.retired else { return }
            self.configuration = configuration
            self.persistConfiguration()
            self.sessionEpoch += 1
            self.stopped = false
            self.suspended = false
            self.attempts = 0
            self.clearTimers()
            self.closeSocket()
            self.open()
        }
    }

    /// Report a delivery status for a known message. Queued while disconnected, so a
    /// dismissal with the socket closed still reaches the relay.
    func report(messageId: String, status: SocketDeliveryStatus) {
        scheduler.perform { [weak self] in
            guard let self, !self.retired else { return }
            self.tracker.queue(
                messageId: messageId,
                sinchMessageId: self.sinchMessageId(for: messageId),
                status: status)
            self.flushIfConnected(.all)
        }
    }

    /// The published state.
    var currentState: SocketState { state }

    /// Messages the host has not consumed yet, newest first.
    var currentPendingMessages: [SocketMessageEvent] {
        pendingMessages.sorted { $0.receivedAt > $1.receivedAt }
    }

    /// Forget the previous identity's outbox and `last_seen` cursor, in memory and in the store.
    func resetSessionState() {
        scheduler.perform { [weak self] in
            guard let self, !self.retired else { return }
            self.tracker.clearOutbox()
            self.lastSeenMessageID = ""
            self.lastSeenEnqueuedAtMs = 0
            self.store.saveLastSeen(id: "", enqueuedAtMs: 0)
        }
    }

    /// Re-read the outbox from the store, for a client replacing another client of the same identity.
    func reloadSessionState() {
        scheduler.perform { [weak self] in
            guard let self, !self.retired else { return }
            self.tracker.reloadFromStore()
        }
    }

    func clearPendingMessages() {
        scheduler.perform { [weak self] in
            guard let self, !self.retired else { return }
            self.pendingMessages.removeAll()
            self.store.savePendingMessages([])
        }
    }

    /// End of life for a client that something else replaces. Beyond ``stop()``, nothing
    /// in flight may still write to the store the replacement shares. Clean the store
    /// up (``resetSessionState()``, ``clearPendingMessages()``) before calling this.
    func retire() {
        scheduler.perform { [weak self] in
            guard let self, !self.retired else { return }
            self.retired = true
            self.tracker.retire()
            self.stopped = true
            self.sessionEpoch += 1
            self.suspended = false
            self.clearTimers()
            // A frame already handed to `onBinary` may still hop onto the scheduler; the
            // bump makes it fail the generation check.
            self.generation += 1
            self.closeSocket()
            self.publish(status: .stopped)
        }
    }

    /// Zero the budget and arm the reset, because a completed handshake shows the server had capacity.
    func noteHelloAck() {
        attemptsBeforeHelloAck = attempts
        attempts = 0
        helloAckResetArmed = true
    }

    /// The session did real work: a pooled message arrived or a report was accepted.
    /// A bare poll is not work, since the relay answers an idle poll with silence.
    func noteSessionWork() {
        helloAckResetArmed = false
    }

    /// For the conformance suite: the attempt count and whether the reset is armed.
    var backoffState: (attempts: Int, resetArmed: Bool) {
        (attempts, helloAckResetArmed)
    }

    /// What a `publish` does to `lastError`. "Keep" and "clear" differ, and most transitions must keep it.
    enum LastErrorUpdate {
        case keep
        case clear
        case set(String?)
    }

    func publish(
        status: SocketStatus,
        connectionId: String? = nil,
        lastError: LastErrorUpdate = .keep
    ) {
        state.status = status
        if let connectionId { state.connectionId = connectionId }
        state.reconnectAttempts = attempts
        state.pollIntervalMs = pollIntervalMs
        switch lastError {
        case .keep: break
        case .clear: state.lastError = nil
        case .set(let value): state.lastError = value
        }
        callbacks.onState?(state)
    }

    /// A rejected report sets `lastError` without changing the status.
    func recordAckRejection(_ error: String) {
        state.lastError = error
        callbacks.onState?(state)
    }

    func log(_ line: String, level: SocketLogLevel = .verbose) {
        logger.log(line, level: level)
        callbacks.onLog?(line)
    }
}
