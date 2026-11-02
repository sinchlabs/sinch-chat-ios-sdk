import XCTest

/// Waits for a main-actor condition without blocking; fails with the caller's location on timeout.
@MainActor
func waitUntil(
    timeout: TimeInterval = 2,
    pollInterval: Duration = .milliseconds(10),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return }
        try? await Task<Never, Never>.sleep(for: pollInterval)
    } while Date() < deadline

    XCTAssertTrue(condition(), "Timed out after \(timeout)s waiting for condition", file: file, line: line)
}
