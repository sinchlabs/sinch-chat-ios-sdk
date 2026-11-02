import Foundation
import os

/// Serialises client work onto one queue, which also provides the timers.
///
/// One serial queue for callbacks and timers means a reconnect scheduled from a
/// frame handler cannot race that handler.
final class DispatchScheduler: Scheduler {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(label: "com.sinch.push.socket")) {
        self.queue = queue
    }

    func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// Always enqueues, even when already on the queue.
    func perform(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    func schedule(after delayMs: Int, _ work: @escaping @Sendable () -> Void) -> ScheduledTask {
        let task = DispatchWorkItem(block: work)
        queue.asyncAfter(deadline: .now() + .milliseconds(max(0, delayMs)), execute: task)
        return DispatchScheduledTask(task)
    }
}

/// `DispatchWorkItem.cancel()` is thread-safe, and `item` is never reassigned.
private final class DispatchScheduledTask: ScheduledTask, @unchecked Sendable {
    private let item: DispatchWorkItem
    init(_ item: DispatchWorkItem) { self.item = item }
    func cancel() { item.cancel() }
}

/// `SystemRandomNumberGenerator`, wrapped so tests can pin the backoff.
final class SystemRandomSource: RandomSource {
    func nextUnitDouble() -> Double {
        Double.random(in: 0..<1)
    }
}

/// A logger with an injectable sink. The default sink prints and ignores the level.
final class PrintSocketLogger: SocketLogger {
    private let prefix: String
    private let sink: @Sendable (String, SocketLogLevel) -> Void

    init(prefix: String = "[SinchPushSocket]", sink: (@Sendable (String, SocketLogLevel) -> Void)? = nil) {
        self.prefix = prefix
        self.sink = sink ?? { line, _ in print("\(line)") }
    }

    func log(_ line: String, level: SocketLogLevel) {
        sink("\(prefix) \(line)", level)
    }
}

/// Discards everything. The core default, so an embedder's own logging is not replaced.
final class SilentSocketLogger: SocketLogger {
    func log(_ line: String, level: SocketLogLevel) {}
}

/// `UserDefaults`-backed state, one JSON-encoded key per slice.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe, and a coder is created per
/// call. The seen set is also written by ``SeenMessageRegistry`` from outside the
/// client's scheduler.
final class UserDefaultsSocketStateStore: SocketStateStore, @unchecked Sendable {
    private enum Key {
        static let prefix = "com.sinch.push.socket."
        static let seen = prefix + "seenMessageIds"
        static let reported = prefix + "reportedKeys"
        static let lastSeen = prefix + "lastSeenMessageId"
        static let lastSeenEnqueuedAt = prefix + "lastSeenEnqueuedAtMs"
        static let outbox = prefix + "outbox"
        static let messages = prefix + "pendingMessages"
        static let configuration = prefix + "configuration"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSeenMessageIDs() -> [String] {
        load([String].self, Key.seen) ?? []
    }

    func saveSeenMessageIDs(_ ids: [String]) {
        save(ids, Key.seen)
    }

    func loadReportedKeys() -> [String] {
        load([String].self, Key.reported) ?? []
    }

    func saveReportedKeys(_ keys: [String]) {
        save(keys, Key.reported)
    }

    func loadLastSeenMessageID() -> String {
        defaults.string(forKey: Key.lastSeen) ?? ""
    }

    func saveLastSeenMessageID(_ id: String) {
        defaults.set(id, forKey: Key.lastSeen)
    }

    func loadLastSeenEnqueuedAtMs() -> Int64 {
        Int64(defaults.integer(forKey: Key.lastSeenEnqueuedAt))
    }

    func saveLastSeenEnqueuedAtMs(_ ms: Int64) {
        defaults.set(Int(ms), forKey: Key.lastSeenEnqueuedAt)
    }

    func loadOutbox() -> [PendingReport] {
        load([PendingReport].self, Key.outbox) ?? []
    }

    func saveOutbox(_ reports: [PendingReport]) {
        save(reports, Key.outbox)
    }

    func loadPendingMessages() -> [SocketMessageEvent] {
        load([SocketMessageEvent].self, Key.messages) ?? []
    }

    func savePendingMessages(_ messages: [SocketMessageEvent]) {
        save(messages, Key.messages)
    }

    func loadConfiguration() -> PersistedSocketConfiguration? {
        load(PersistedSocketConfiguration.self, Key.configuration)
    }

    func saveConfiguration(_ configuration: PersistedSocketConfiguration) {
        save(configuration, Key.configuration)
    }

    func clearConfiguration() {
        defaults.removeObject(forKey: Key.configuration)
    }

    /// A slice this build cannot decode is dropped. Re-delivering a message is safe.
    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

/// The in-memory store, for tests and for hosts without `UserDefaults`.
///
/// A new client handed the same instance behaves like a restart.
/// Thread-safe, since the seen set is written from the APNs paths. One unfair lock guards every slice.
final class InMemorySocketStateStore: SocketStateStore, Sendable {
    private struct Slices {
        var seen: [String] = []
        var reported: [String] = []
        var lastSeen = ""
        var lastSeenEnqueuedAt: Int64 = 0
        var outbox: [PendingReport] = []
        var messages: [SocketMessageEvent] = []
        var configuration: PersistedSocketConfiguration?
    }

    private let slices = OSAllocatedUnfairLock(initialState: Slices())

    init() {}

    func loadSeenMessageIDs() -> [String] { slices.withLock { $0.seen } }
    func saveSeenMessageIDs(_ ids: [String]) {
        slices.withLock {
            $0.seen = ids
        }
    }

    func loadReportedKeys() -> [String] { slices.withLock { $0.reported } }
    func saveReportedKeys(_ keys: [String]) {
        slices.withLock {
            $0.reported = keys
        }
    }

    func loadLastSeenMessageID() -> String { slices.withLock { $0.lastSeen } }
    func saveLastSeenMessageID(_ id: String) {
        slices.withLock {
            $0.lastSeen = id
        }
    }

    func loadLastSeenEnqueuedAtMs() -> Int64 { slices.withLock { $0.lastSeenEnqueuedAt } }
    func saveLastSeenEnqueuedAtMs(_ ms: Int64) {
        slices.withLock {
            $0.lastSeenEnqueuedAt = ms
        }
    }

    func loadOutbox() -> [PendingReport] { slices.withLock { $0.outbox } }
    func saveOutbox(_ reports: [PendingReport]) {
        slices.withLock {
            $0.outbox = reports
        }
    }

    func loadPendingMessages() -> [SocketMessageEvent] { slices.withLock { $0.messages } }
    func savePendingMessages(_ value: [SocketMessageEvent]) {
        slices.withLock {
            $0.messages = value
        }
    }

    func loadConfiguration() -> PersistedSocketConfiguration? { slices.withLock { $0.configuration } }
    func saveConfiguration(_ value: PersistedSocketConfiguration) {
        slices.withLock {
            $0.configuration = value
        }
    }

    func clearConfiguration() {
        slices.withLock {
            $0.configuration = nil
        }
    }
}

/// In-memory credential storage. Only the owning client touches it, on its scheduler.
final class InMemoryAuthTokenStore: AuthTokenStore, @unchecked Sendable {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func loadToken() -> String? { token }
    func saveToken(_ token: String) { self.token = token }
    func clearToken() { token = nil }
}

/// Posts nothing. The core default; a host wanting local notifications installs
/// `iOS/SocketNotificationPresenter.swift`.
final class NoopNotificationPresenter: NotificationPresenting {
    /// Written by the host's thread and read on the scheduler, so it is locked.
    private let registered = OSAllocatedUnfairLock(initialState: false)

    var handlerRegistered: Bool {
        get { registered.withLock { $0 } }
        set { registered.withLock { $0 = newValue } }
    }

    func post(
        _ message: SocketMessageEvent, alerting: Bool, completion: @escaping @Sendable (Bool) -> Void
    ) {
        completion(false)
    }
}

/// Finds nothing delivered. The core default; the socket then always posts.
final class NoDeliveredNotifications: DeliveredNotificationLookup {
    func isDelivered(identifier: String, completion: @escaping @Sendable (Bool) -> Void) {
        completion(false)
    }
}
