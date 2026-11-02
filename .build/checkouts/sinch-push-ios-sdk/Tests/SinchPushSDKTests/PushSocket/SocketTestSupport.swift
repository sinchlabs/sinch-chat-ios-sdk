import Foundation

@testable import SinchPushSDK

// MARK: - Clock

/// A one-shot timer held until the test advances the clock.
final class ManualScheduledTask: ScheduledTask, @unchecked Sendable {
    let fireAtMs: Int64
    let work: @Sendable () -> Void
    var isCancelled = false

    init(fireAtMs: Int64, work: @escaping @Sendable () -> Void) {
        self.fireAtMs = fireAtMs
        self.work = work
    }

    func cancel() { isCancelled = true }
}

/// A clock the test owns, and the only place timers exist.
///
/// `perform` runs its work inline, so state is settled once `start()` returns.
/// The suite runs on one thread, so the fakes are `@unchecked Sendable` and
/// deliberately unsynchronised.
final class ManualScheduler: Scheduler, @unchecked Sendable {
    private var clockMs: Int64

    private var tasks: [ManualScheduledTask] = []

    private(set) var performCount = 0

    init(nowMs: Int64 = 1_770_000_000_000) {
        self.clockMs = nowMs
    }

    func nowMs() -> Int64 { clockMs }

    func perform(_ work: @escaping @Sendable () -> Void) {
        performCount += 1
        work()
    }

    func schedule(after delayMs: Int, _ work: @escaping @Sendable () -> Void) -> ScheduledTask {
        let task = ManualScheduledTask(
            fireAtMs: clockMs + Int64(max(0, delayMs)),
            work: work)
        tasks.append(task)
        return task
    }

    // MARK: - Test drivers

    /// Fires everything due in the scheduled order, including timers scheduled by
    /// the work being fired; `advance(by: 0)` fires whatever is due now.
    func advance(by milliseconds: Int) {
        let target = clockMs + Int64(milliseconds)
        while true {
            let due = tasks.enumerated()
                .filter { !$0.element.isCancelled && $0.element.fireAtMs <= target }
                .min { ($0.element.fireAtMs, $0.offset) < ($1.element.fireAtMs, $1.offset) }
            guard let due else { break }
            tasks.remove(at: due.offset)
            clockMs = max(clockMs, due.element.fireAtMs)
            due.element.work()
        }
        clockMs = target
    }

    var pendingTasks: [ManualScheduledTask] { tasks.filter { !$0.isCancelled } }

    var pendingDelays: [Int] { pendingTasks.map { Int($0.fireAtMs - clockMs) } }
}

// MARK: - Random

/// A draw the test pins, so a scheduled delay is exact.
final class ScriptedRandomSource: RandomSource, @unchecked Sendable {
    private var values: [Double]
    private var index = 0
    private(set) var drawCount = 0

    init(fixed value: Double = 0.5) {
        self.values = [value]
    }

    /// A sequence, then the last value forever.
    init(_ sequence: [Double]) {
        precondition(!sequence.isEmpty, "ScriptedRandomSource needs at least one draw")
        self.values = sequence
    }

    func nextUnitDouble() -> Double {
        drawCount += 1
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

// MARK: - Logging

/// Records every diagnostic line.
final class RecordingLogger: SocketLogger, @unchecked Sendable {
    private(set) var entries: [(line: String, level: SocketLogLevel)] = []

    var lines: [String] { entries.map(\.line) }

    func log(_ line: String, level: SocketLogLevel) { entries.append((line, level)) }

    func levels(containing fragment: String) -> [SocketLogLevel] {
        entries.filter { $0.line.contains(fragment) }.map(\.level)
    }

    func contains(_ fragment: String) -> Bool {
        lines.contains { $0.contains(fragment) }
    }
}

// MARK: - Device info

/// A `DeviceInfoProviding` whose whole answer a test controls.
final class FakeDeviceInfoProvider: DeviceInfoProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var value: DeviceInfo

    init(_ info: DeviceInfo = .fixture()) {
        self.value = info
    }

    var info: DeviceInfo {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    func current(sdkVersionOverride: String?) -> DeviceInfo {
        var out = info
        out.sdkVersion = SocketConfiguration.resolveSDKVersion(sdkVersionOverride ?? out.sdkVersion)
        return out
    }
}

extension DeviceInfo {
    /// An empty `installationId` is "unavailable".
    static func fixture(
        installationId: String = "6f1c2a9e-3b7d-4e8a-9c21-5d4b7a0e1f23",
        osVersion: String = "18.1",
        sdkVersion: String = "0.0.0-test",
        bundleId: String = "com.sinch.example",
        backgroundService: DeviceInfo.BackgroundServiceState = .unsupported
    ) -> DeviceInfo {
        DeviceInfo(
            installationId: installationId,
            platform: SocketConfiguration.platform,
            osVersion: osVersion,
            sdkVersion: sdkVersion,
            bundleId: bundleId,
            backgroundService: backgroundService)
    }
}

func testDeviceInfo(
    installationId: String = "0b9c1f0e-6f3a-4b8e-9d57-2f6f6c1a7e11",
    osVersion: String = "17.5.1",
    bundleId: String = "com.example.host"
) -> StaticDeviceInfoProvider {
    StaticDeviceInfoProvider(
        installationId: installationId, osVersion: osVersion, bundleId: bundleId)
}

// MARK: - Notifications

/// Posts (or refuses to post) without `UNUserNotificationCenter`.
///
/// `acceptsPost` defaults to `false` so DISPLAYED assertions cannot pass by default.
final class FakeNotificationPresenter: NotificationPresenting, @unchecked Sendable {
    var handlerRegistered = false
    var acceptsPost = false
    private(set) var posted: [SocketMessageEvent] = []
    private(set) var postedAlerting: [Bool] = []
    var onPost: ((SocketMessageEvent) -> Void)?
    /// When `true` the completion of a post is held until ``completeDeferred(_:)``.
    var defersCompletions = false
    private var deferred: [@Sendable (Bool) -> Void] = []

    func completeDeferred(_ accepted: Bool = true) {
        let held = deferred
        deferred = []
        held.forEach { $0(accepted) }
    }

    func post(
        _ message: SocketMessageEvent, alerting: Bool, completion: @escaping @Sendable (Bool) -> Void
    ) {
        posted.append(message)
        postedAlerting.append(alerting)
        onPost?(message)
        if defersCompletions {
            deferred.append(completion)
            return
        }
        completion(acceptsPost)
    }
}

final class FakeDeliveredNotifications: DeliveredNotificationLookup, @unchecked Sendable {
    var delivered: Set<String> = []
    private(set) var asked: [String] = []
    /// When `false` the answer is held until ``flush()``.
    var answersInline = true
    private var pending: [@Sendable () -> Void] = []

    func isDelivered(identifier: String, completion: @escaping @Sendable (Bool) -> Void) {
        asked.append(identifier)
        let answer: @Sendable () -> Void = { [self] in completion(delivered.contains(identifier)) }
        if answersInline { answer() } else { pending.append(answer) }
    }

    func flush() {
        let work = pending
        pending = []
        work.forEach { $0() }
    }
}
