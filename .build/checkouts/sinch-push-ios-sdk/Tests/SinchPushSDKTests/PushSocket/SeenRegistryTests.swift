//  SeenRegistryTests.swift — the shared seen-message registry.

import XCTest

@testable import SinchPushSDK

final class SeenRegistryTests: XCTestCase {

    func testARegistryInjectedIntoTwoClientsDedupesAcrossThem() {
        let shared = SeenMessageRegistry(store: FakeSocketStateStore())
        let first = makeHarness(registry: shared)
        let second = makeHarness(registry: shared)
        first.handshake()
        second.handshake()

        first.deliverMessage(pooledMessage(messageID: "msg-1"))
        second.deliverMessage(pooledMessage(messageID: "msg-1"))

        XCTAssertEqual(first.deliveredMessageIDs, ["msg-1"])
        XCTAssertEqual(second.deliveredMessageIDs, [])
        // These harnesses have separate stores, so each tracker reports DELIVERED; in production the shared store's reported keys suppress it.
        XCTAssertEqual(second.reports.map(\.messageID), ["msg-1"])
        XCTAssertEqual(second.reports.first?.status, .delivered)
    }

    func testAPersistedSetBeyondTheBoundKeepsTheNewestIds() {
        let persisted = (0..<2005).map { "id-\($0)" }
        let registry = SeenMessageRegistry(store: FakeSocketStateStore(seen: persisted))

        XCTAssertEqual(registry.snapshot.count, 2000)
        XCTAssertFalse(registry.contains("id-4"))
        XCTAssertTrue(registry.contains("id-5"))
        XCTAssertTrue(registry.contains("id-2004"))
    }
}
