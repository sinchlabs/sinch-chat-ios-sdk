import Foundation

protocol ScheduledTask: AnyObject, Sendable {
    func cancel()
}

/// Serialises work onto one execution context and provides time.
///
/// Every ``SocketClient`` entry point runs through ``perform(_:)``, so client state
/// is only touched from one context.
protocol Scheduler: AnyObject, Sendable {
    /// Wall-clock milliseconds since the Unix epoch, for `reported_at_unix_millis` and `rate_limited` deadlines.
    func nowMs() -> Int64

    /// Run `work` on the scheduler's context. The live scheduler always enqueues,
    /// even when already on that context.
    func perform(_ work: @escaping @Sendable () -> Void)

    /// Run `work` once after `delayMs`. A zero delay still goes through the scheduler.
    func schedule(after delayMs: Int, _ work: @escaping @Sendable () -> Void) -> ScheduledTask
}

/// The only source of randomness the backoff uses. Controllable so tests can pin jitter.
protocol RandomSource: AnyObject, Sendable {
    func nextUnitDouble() -> Double
}

/// Why a socket went away, as the transport sees it.
struct SocketTransportClose: Sendable {
    /// WebSocket close code. 1000 is a normal closure, used for backgrounding.
    var code: Int
    var reason: String?
}

/// One WebSocket connection. Binary messages only; text frames are dropped by the transport.
protocol SocketTransport: AnyObject, Sendable {
    func connect(to url: URL)

    /// Send one binary frame. Ignored when the socket is not open.
    func send(_ data: Data)

    /// Close with a code (1000 means "the app backgrounded").
    func close(code: Int, reason: String?)

    var isOpen: Bool { get }

    /// The client clears these before every ``close(code:reason:)``, so a replaced
    /// socket cannot deliver a second close.
    var onOpen: (@Sendable () -> Void)? { get set }
    var onBinary: (@Sendable (Data) -> Void)? { get set }
    var onClose: (@Sendable (SocketTransportClose) -> Void)? { get set }
}

/// Creates a socket per attempt, so a reconnect can ask for a new one.
protocol SocketTransportFactory: AnyObject, Sendable {
    func makeTransport() -> SocketTransport
}

/// Foreground/background transitions.
///
/// `didEnterBackground` closes with 1000 and cancels the backoff. The foreground
/// transition reconnects; the `HelloAck` then triggers the immediate `Poll`.
@MainActor
protocol AppLifecycleObserving: AnyObject {
    var onBackground: (() -> Void)? { get set }
    var onForeground: (() -> Void)? { get set }
    func startObserving()
    func stopObserving()
}

/// Posts the local notification for a socket message.
protocol NotificationPresenting: AnyObject, Sendable {
    /// Post a notification for `message`. The completion reports whether the
    /// post was accepted; DISPLAYED is queued only on success.
    ///
    /// `alerting == false` posts silently, for a replay burst.
    func post(
        _ message: SocketMessageEvent,
        alerting: Bool,
        completion: @escaping @Sendable (Bool) -> Void)

    /// Whether the host app has registered an in-app handler.
    var handlerRegistered: Bool { get set }
}

/// Covers messages APNs delivered while the app was in the background, which the
/// seen set never saw. The identifier is the message id on both channels.
protocol DeliveredNotificationLookup: AnyObject, Sendable {
    func isDelivered(identifier: String, completion: @escaping @Sendable (Bool) -> Void)
}

/// How a socket notification is styled, separated from `UNNotificationContent` so it is testable.
struct SocketNotificationStyle: Equatable, Sendable {
    /// The thread for a message without a `trigger`.
    static let fallbackThread = "sinchpush"

    /// The message's non-empty `trigger`, else ``fallbackThread``.
    let threadIdentifier: String
    /// `false` for the silent post of a replay burst.
    let playsSound: Bool
    /// `true` for the silent post, using `.passive` where available.
    let passive: Bool

    init(alerting: Bool, trigger: String?) {
        if let trigger, !trigger.isEmpty {
            threadIdentifier = trigger
        } else {
            threadIdentifier = SocketNotificationStyle.fallbackThread
        }
        playsSound = alerting
        passive = !alerting
    }
}

/// Everything the client keeps across a restart. The auth token is not here; it
/// lives in ``AuthTokenStore``.
protocol SocketStateStore: AnyObject, Sendable {
    // Seen set, oldest first; the order the LRU evicts in.
    func loadSeenMessageIDs() -> [String]
    func saveSeenMessageIDs(_ ids: [String])

    // "id:statusNumber" keys already reported.
    func loadReportedKeys() -> [String]
    func saveReportedKeys(_ keys: [String])

    // Newest received `message_id`, echoed in `Hello`, and its `enqueued_at_unix_millis`
    // (0 = unknown). An older replayed message must not move the cursor back.
    func loadLastSeenMessageID() -> String
    func saveLastSeenMessageID(_ id: String)
    func loadLastSeenEnqueuedAtMs() -> Int64
    func saveLastSeenEnqueuedAtMs(_ ms: Int64)
    func saveLastSeen(id: String, enqueuedAtMs: Int64)

    func loadOutbox() -> [PendingReport]
    func saveOutbox(_ reports: [PendingReport])

    /// Messages the host has not consumed yet, recoverable after a background.
    func loadPendingMessages() -> [SocketMessageEvent]
    func savePendingMessages(_ messages: [SocketMessageEvent])

    func loadConfiguration() -> PersistedSocketConfiguration?
    func saveConfiguration(_ configuration: PersistedSocketConfiguration)
    func clearConfiguration()
}

extension SocketStateStore {
    /// Two `UserDefaults` writes; a store with a real transaction can override this.
    func saveLastSeen(id: String, enqueuedAtMs: Int64) {
        saveLastSeenMessageID(id)
        saveLastSeenEnqueuedAtMs(enqueuedAtMs)
    }
}

/// The credential, kept apart from ``SocketStateStore`` so only the Keychain store holds a JWT.
protocol AuthTokenStore: AnyObject, Sendable {
    func loadToken() -> String?
    func saveToken(_ token: String)
    func clearToken()
}

/// How visible a diagnostic line should be. A line without a level is `.verbose`.
enum SocketLogLevel: Sendable, Equatable {
    case verbose
    case warning
    case error
}

protocol SocketLogger: AnyObject, Sendable {
    func log(_ line: String, level: SocketLogLevel)
}

extension SocketLogger {
    func log(_ line: String) {
        log(line, level: .verbose)
    }
}
