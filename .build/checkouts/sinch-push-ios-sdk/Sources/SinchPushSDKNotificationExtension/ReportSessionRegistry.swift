import Foundation

/// The background sessions the extension started, so that the app can open them again and receive the results
/// that arrived while it was not running.
///
/// Every extension upload names its session after itself (`com.sinch.chatsdk.reports.nse.<uuid>`): the system allows
/// one process per background session identifier. The extension registers the name, starts the upload and then
/// releases the session, so an entry here is a session the extension no longer holds. The app learns the names here.
package struct ReportSessionRegistry: Sendable {
    package static let capacity = 50
    package static let maxAge: TimeInterval = 24 * 60 * 60

    private struct Entry: Codable {
        let identifier: String
        var touchedAt: TimeInterval
    }

    private static let fileName = "extension-sessions.json"
    private static let lockName = "extension-sessions.lock"
    private let container: ReportContainer
    private let now: @Sendable () -> Date

    package init(container: ReportContainer, now: @escaping @Sendable () -> Date = { Date() }) {
        self.container = container
        self.now = now
    }

    /// Records that the session of `identifier` was used just now.
    package func touch(_ identifier: String) {
        guard let url = fileURL else { return }
        container.withFileLock(named: Self.lockName) {
            var entries = load().filter { $0.identifier != identifier }
            entries.append(Entry(identifier: identifier, touchedAt: now().timeIntervalSince1970))
            if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
            save(entries, to: url)
        }
    }

    /// Forgets the session of `identifier`.
    package func remove(_ identifier: String) {
        guard let url = fileURL else { return }
        container.withFileLock(named: Self.lockName) {
            let entries = load()
            let kept = entries.filter { $0.identifier != identifier }
            if kept.count != entries.count { save(kept, to: url) }
        }
    }

    /// The sessions registered at least `idleFor` seconds ago, which covers the time the extension takes to release
    /// a session after it registered it.
    package func identifiers(idleFor idle: TimeInterval) -> [String] {
        guard fileURL != nil else { return [] }
        return container.withFileLock(named: Self.lockName) {
            let newest = now().timeIntervalSince1970 - idle
            return load().filter { $0.touchedAt <= newest }.map(\.identifier)
        }
    }

    private var fileURL: URL? {
        container.directory?.appendingPathComponent(Self.fileName)
    }

    private func save(_ entries: [Entry], to url: URL) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        container.write(data, to: url)
    }

    private func load() -> [Entry] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        let oldest = now().timeIntervalSince1970 - Self.maxAge
        return entries.filter { $0.touchedAt >= oldest }
    }
}
