import Foundation

/// Bounded insertion-ordered set; lookups do not refresh eviction order.
struct SeenSet: Equatable {
    static let capacity = 2000

    /// Oldest first. The eviction order and the persisted order are the same list.
    private(set) var order: [String] = []
    private var index: Set<String> = []
    private let limit: Int

    init() { limit = SeenSet.capacity }

    /// An empty set with its own bound, restored from `persisted`. An over-long list keeps its newest entries.
    init(limit: Int, persisted: [String] = []) {
        self.limit = limit
        for id in persisted {
            insert(id)
        }
    }

    /// Restores from persisted state, oldest first. Entries beyond ``capacity`` are dropped from the front.
    init(persisted: [String]) {
        limit = SeenSet.capacity
        for id in persisted.suffix(SeenSet.capacity) {
            insert(id)
        }
    }

    var count: Int { order.count }

    /// Whether `id` has already been processed.
    func contains(_ id: String) -> Bool {
        index.contains(id)
    }

    /// Records `id`. Returns `false` on a dedupe hit.
    @discardableResult
    mutating func insert(_ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        guard index.insert(id).inserted else { return false }
        order.append(id)
        evictIfNeeded()
        return true
    }

    /// Oldest first, the order ``init(persisted:)`` expects.
    var persisted: [String] { order }

    private mutating func evictIfNeeded() {
        while order.count > limit {
            let oldest = order.removeFirst()
            index.remove(oldest)
        }
    }
}
