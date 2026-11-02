//  RelayHarness.swift — launches the prebuilt relay binaries for the live contract suite.
//
//  macOS only (`Process` is unavailable on iOS); `LiveRelaySmokeTests` covers iOS.

#if os(macOS)
import Foundation

private final class ProbeOutcome: @unchecked Sendable {
    var ok = false
    var last: String?
}

enum RelayHarnessError: Error, CustomStringConvertible {
    case relayNeverBecameHealthy(status: String, logTail: String)
    case relayDidNotExitAfterTermination(logTail: String)
    case enqueueFailed(output: String)

    var description: String {
        switch self {
        case let .relayNeverBecameHealthy(status, logTail):
            return "deliveryd never became healthy: \(status)\n\(logTail)"
        case .relayDidNotExitAfterTermination(let logTail):
            return "deliveryd did not exit within 25 s of SIGTERM\n\(logTail)"
        case .enqueueFailed(let output):
            return "enqueue failed: \(output)"
        }
    }
}

final class RelayHarness: @unchecked Sendable {

    struct SinkReport: Equatable {
        var sinchMessageID: String
        var channelMessageID: String
        var status: String
    }

    let httpPort = RelayHarness.freePort()
    let grpcPort = RelayHarness.freePort()
    private let metricsPort = RelayHarness.freePort()
    private let probesPort = RelayHarness.freePort()
    private let sinkPort = RelayHarness.freePort()
    private let sinkProbesPort = RelayHarness.freePort()

    var wsURL: String { "ws://127.0.0.1:\(httpPort)/ws" }

    private let binDir: URL
    private let lock = NSLock()
    private var sinkLines: [String] = []
    private var relayLines: [String] = []
    private var sink: Process?
    private(set) var relay: Process?

    private init(binDir: URL) { self.binDir = binDir }

    static func locate() -> (RelayHarness?, String) {
        let env = ProcessInfo.processInfo.environment
        guard env["RELAY_CONTRACT"] == "1" else {
            return (nil, "live relay contract is opt-in: run on macOS with RELAY_CONTRACT=1 (RELAY_DIR / RELAY_BIN_DIR locate the relay)")
        }
        // Unless RELAY_DIR is set, the relay is `<repo>/../sinch-push-relay`; the repo root
        // holds `.git` (a directory, or a file in a worktree).
        var repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git").path),
            repo.path != "/"
        {
            repo = repo.deletingLastPathComponent()
        }
        let relayDir = env["RELAY_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repo.deletingLastPathComponent().appendingPathComponent("sinch-push-relay")
        let bin = env["RELAY_BIN_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? relayDir.appendingPathComponent("bin")
        let missing = ["deliveryd", "enqueue", "report-sink-stub"].filter {
            !FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent($0).path)
        }
        guard missing.isEmpty else {
            return (
                nil,
                "relay binaries \(missing) not found in \(bin.path); build the relay (make build) or set RELAY_DIR / RELAY_BIN_DIR"
            )
        }
        return (RelayHarness(binDir: bin), "")
    }

    func start() throws {
        sink = try spawn(
            "report-sink-stub",
            env: ["GRPC_LISTEN_ADDR": ":\(sinkPort)", "PROBES_ADDR": ":\(sinkProbesPort)"],
            into: \.sinkLines)
        try startRelay()
    }

    func startRelay() throws {
        relay = try spawn(
            "deliveryd",
            env: [
                "HTTP_PORT": "\(httpPort)", "GRPC_PORT": "\(grpcPort)",
                "METRICS_PORT": "\(metricsPort)", "PROBES_PORT": "\(probesPort)",
                "SINCH_PUSH_GRPC_ADDR": "127.0.0.1:\(sinkPort)", "LOG_LEVEL": "info",
                // The relay wants a JWT_SECRET and verifies the token with it; the harness has no secret and
                // uses a dummy token, so the verification is skipped.
                "AUTH_INSECURE_SKIP_JWT": "true",
            ],
            into: \.relayLines)
        let deadline = Date().addingTimeInterval(15)
        var last = "never attempted"
        while Date() < deadline {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(probesPort)/healthz")!)
            request.timeoutInterval = 0.5
            let done = DispatchSemaphore(value: 0)
            // Written on URLSession's queue, read after `done.wait()`.
            let outcome = ProbeOutcome()
            URLSession.shared.dataTask(with: request) { _, response, error in
                if let http = response as? HTTPURLResponse {
                    outcome.ok = http.statusCode == 200
                    outcome.last = "status \(http.statusCode)"
                } else if let error {
                    outcome.last = error.localizedDescription
                }
                done.signal()
            }.resume()
            done.wait()
            if let reported = outcome.last { last = reported }
            if outcome.ok { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw RelayHarnessError.relayNeverBecameHealthy(status: last, logTail: relayTail())
    }

    /// SIGTERM, then wait for process exit: the relay holds its ports for the whole graceful
    /// drain, so a respawn must wait for it.
    func sigtermRelayAndAwaitExit() throws {
        guard let relay, relay.isRunning else { return }
        relay.terminate()
        let deadline = Date().addingTimeInterval(25)
        while relay.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if relay.isRunning {
            throw RelayHarnessError.relayDidNotExitAfterTermination(logTail: relayTail())
        }
    }

    func stop() {
        for process in [relay, sink].compactMap({ $0 }) where process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
    }

    func enqueue(
        appID: String, userID: String, sinchMessageID: String, title: String, body: String? = nil
    ) throws {
        var args = [
            "-addr", "127.0.0.1:\(grpcPort)", "-app", appID, "-user", userID,
            "-title", title, "-sinch-message-id", sinchMessageID, "-ttl", "120",
        ]
        if let body { args += ["-body", body, "-metadata", "kind=chat"] }
        let process = Process()
        process.executableURL = binDir.appendingPathComponent("enqueue")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw RelayHarnessError.enqueueFailed(output: String(decoding: out, as: UTF8.self))
        }
    }

    func sinkReports() -> [SinkReport] {
        logObjects(\.sinkLines, matching: "ReportDelivery").map { object in
            SinkReport(
                sinchMessageID: object["sinch_message_id"] as? String ?? "",
                channelMessageID: object["channel_message_id"] as? String ?? "",
                status: object["status"] as? String ?? "")
        }
    }

    func relayEvents(_ message: String) -> [[String: Any]] {
        logObjects(\.relayLines, matching: message)
    }

    func relayTail(_ lines: Int = 25) -> String { tail(\.relayLines, "deliveryd", lines) }
    func sinkTail(_ lines: Int = 25) -> String { tail(\.sinkLines, "sink", lines) }

    /// Both processes log JSON objects, one per line, to stderr; lines that are not JSON
    /// objects are skipped.
    private func logObjects(
        _ keyPath: KeyPath<RelayHarness, [String]>, matching message: String
    ) -> [[String: Any]] {
        let text = lock.withLock { self[keyPath: keyPath].joined() }
        return text.split(separator: "\n").compactMap { line -> [String: Any]? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any],
                object["message"] as? String == message
            else { return nil }
            return object
        }
    }

    private func tail(_ keyPath: KeyPath<RelayHarness, [String]>, _ name: String, _ n: Int) -> String {
        lock.withLock {
            "--- \(name) (last \(n)) ---\n"
                + self[keyPath: keyPath].joined().split(separator: "\n").suffix(n).joined(separator: "\n")
        }
    }

    private func spawn(
        _ binary: String, env: [String: String], into target: ReferenceWritableKeyPath<RelayHarness, [String]> & Sendable
    ) throws -> Process {
        let process = Process()
        process.executableURL = binDir.appendingPathComponent(binary)
        process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.lock.lock()
            self[keyPath: target].append(String(decoding: data, as: UTF8.self))
            self.lock.unlock()
        }
        try process.run()
        return process
    }

    private static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        return Int(UInt16(bigEndian: bound.sin_port))
    }
}
#endif
