import Foundation

@testable import SinchPushSDK

/// An in-memory store that counts its saves.
final class FakeDeliveryReportStore: DeliveryReportStore, @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [DeliveryReport]
    private var saves = 0

    init(reports: [DeliveryReport] = []) {
        self.reports = reports
    }

    var saveCount: Int { lock.withLock { saves } }
    var stored: [DeliveryReport] { lock.withLock { reports } }

    func loadDeliveryReports() -> [DeliveryReport] { stored }

    func saveDeliveryReports(_ reports: [DeliveryReport]) {
        lock.withLock {
            self.reports = reports
            saves += 1
        }
    }
}

/// A clock the test owns. Unlike `ManualScheduler`, it serialises `perform`, since the reporter
/// runs on Swift tasks that hop onto the scheduler from different threads.
final class SerialManualScheduler: Scheduler, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var clockMs: Int64
    private var tasks: [ManualScheduledTask] = []

    init(nowMs: Int64 = 1_770_000_000_000) {
        self.clockMs = nowMs
    }

    func nowMs() -> Int64 { lock.withLock { clockMs } }

    func perform(_ work: @escaping @Sendable () -> Void) {
        lock.withLock { work() }
    }

    func schedule(after delayMs: Int, _ work: @escaping @Sendable () -> Void) -> ScheduledTask {
        lock.withLock {
            let task = ManualScheduledTask(fireAtMs: clockMs + Int64(max(0, delayMs)), work: work)
            tasks.append(task)
            return task
        }
    }

    /// Moves the clock and fires what is due, in the scheduled order.
    func advance(by milliseconds: Int) {
        lock.withLock {
            let target = clockMs + Int64(milliseconds)
            while let due = tasks.filter({ !$0.isCancelled && $0.fireAtMs <= target }).min(by: { $0.fireAtMs < $1.fireAtMs }) {
                tasks.removeAll { $0 === due }
                clockMs = max(clockMs, due.fireAtMs)
                due.work()
            }
            clockMs = target
        }
    }

    var pendingDelays: [Int] {
        lock.withLock { tasks.filter { !$0.isCancelled }.map { Int($0.fireAtMs - clockMs) } }
    }
}

/// Records every batch and answers from a script. With `holds` set, a call waits for ``finishHeldCall(with:)``.
final class FakeDeliveryReportSender: DeliveryReportSending, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[DeliveryReport]] = []
    private var script: [Result<Void, Error>] = []
    private var held: [CheckedContinuation<Void, Error>] = []
    private var earlyFinishes: [Result<Void, Error>] = []
    private let callSignals: AsyncStream<Void>
    private let callSignalSink: AsyncStream<Void>.Continuation
    private var callIterator: AsyncStream<Void>.AsyncIterator

    /// Whether a call waits for the test to finish it.
    var holds = false

    init() {
        let (stream, sink) = AsyncStream<Void>.makeStream()
        callSignals = stream
        callSignalSink = sink
        callIterator = stream.makeAsyncIterator()
    }

    var batches: [[DeliveryReport]] { lock.withLock { recorded } }

    /// The results of the next calls, in order. A call past the script succeeds.
    func script(_ results: Result<Void, Error>...) {
        lock.withLock { script.append(contentsOf: results) }
    }

    /// Repeats `result` for every call past the script.
    var defaultResult: Result<Void, Error> = .success(())

    func reportEvents(_ events: [DeliveryReport]) async throws {
        let (hold, scripted): (Bool, Result<Void, Error>?) = lock.withLock {
            recorded.append(events)
            return (holds, script.isEmpty ? nil : script.removeFirst())
        }
        callSignalSink.yield()
        if hold {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let early = lock.withLock { () -> Result<Void, Error>? in
                    if earlyFinishes.isEmpty {
                        held.append(continuation)
                        return nil
                    }
                    return earlyFinishes.removeFirst()
                }
                if let early { continuation.resume(with: early) }
            }
            return
        }
        try (scripted ?? defaultResult).get()
    }

    /// Waits until `count` calls were made in total.
    func waitForCalls(_ count: Int) async {
        while batches.count < count {
            _ = await callIterator.next()
        }
    }

    /// Finishes the oldest held call, or the next one when none is held yet.
    func finishHeldCall(with result: Result<Void, Error> = .success(())) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard !held.isEmpty else {
                earlyFinishes.append(result)
                return nil
            }
            return held.removeFirst()
        }
        continuation?.resume(with: result)
    }
}

final class ReportTestAuthDataSource: AuthDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private var refreshes = 0
    private var failsRefresh = false

    init(token: String? = "token") {
        self.token = token
    }

    var accessToken: String? {
        get { lock.withLock { token } }
        set { lock.withLock { token = newValue } }
    }

    var refreshCount: Int { lock.withLock { refreshes } }

    var refreshFails: Bool {
        get { lock.withLock { failsRefresh } }
        set { lock.withLock { failsRefresh = newValue } }
    }

    var isLoggedIn: Bool { true }
    var identityHashValue: String? { nil }
    var currentConfigID: String { "" }
    var currentAuthorization: AuthModel? { nil }

    func generateToken(config: SinchSDKConfig.AppConfig, identity: SinchSDKIdentity) async throws -> AuthModel {
        throw AuthDataSourceError.notLoggedIn
    }

    func generateToken(config: SinchSDKConfig.AppConfig,
                       identity: SinchSDKIdentity,
                       completion: @escaping @Sendable (Result<AuthModel, AuthRepositoryError>) -> Void) {}

    func refreshToken() async throws -> AuthModel {
        let fails = lock.withLock { () -> Bool in
            refreshes += 1
            return failsRefresh
        }
        if fails { throw AuthDataSourceError.anonymousTokenCannotBeRefreshed }
        return AuthModel(accessToken: "refreshed", sinchIdentity: .anonymous, clientID: "", projectID: "",
                         configID: "", region: .EU1)
    }

    func currentAccessToken() throws -> String {
        guard let token = accessToken else { throw AuthDataSourceError.notLoggedIn }
        return token
    }

    func deleteToken() {}
}

final class StubPushAPIClient: PushAPIClient, @unchecked Sendable {
    /// No transport: the sender reports through ``GrpcWebError`` and the reporter retries, exactly as for an
    /// unreachable server.
    var grpcWebClient: GrpcWebClient? { nil }

    func closeChannel() {}
}

final class RecordingDeliveryReporter: DeliveryReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(messageID: String, subscriberID: String)] = []

    var reports: [(messageID: String, subscriberID: String)] { lock.withLock { recorded } }

    func reportDelivery(messageID: String, subscriberID: String) {
        lock.withLock { recorded.append((messageID, subscriberID)) }
    }
}

func deliveryReport(_ messageID: String, subscriber: String = "s-1", at enqueuedAtMs: Int64 = 1_770_000_000_000) -> DeliveryReport {
    DeliveryReport(messageID: messageID, subscriberID: subscriber, enqueuedAtMs: enqueuedAtMs)
}
