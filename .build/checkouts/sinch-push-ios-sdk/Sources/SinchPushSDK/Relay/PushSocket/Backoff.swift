import Foundation

/// Full-jitter reconnect and retry backoff: a delay in `[0, min(30 s, 1 s · 2^(attempts - 1))]`.
///
/// The whole window is drawn from, so a shed cohort spreads out. The first retry
/// after a shed may be immediate.
enum ReconnectBackoff {
    static let baseMs = 1000

    static let maxMs = 30_000

    /// The window for `attempts`, which is one-based and clamped to the base window.
    static func ceilingMs(attempts: Int) -> Int {
        let exponent = max(1, attempts)
        // Bound the exponent before shifting.
        guard exponent <= 1 + (maxMs / baseMs) else { return maxMs }
        return min(maxMs, baseMs * (1 << (exponent - 1)))
    }

    /// One draw from the window, floored to whole milliseconds.
    static func delayMs(attempts: Int, using random: RandomSource) -> Int {
        let ceiling = ceilingMs(attempts: attempts)
        let draw = random.nextUnitDouble()
        // Keeps a source that returns 1.0 inside the window.
        let bounded = min(max(0.0, draw), 0.999_999_999_999)
        return Int(bounded * Double(ceiling))
    }
}
