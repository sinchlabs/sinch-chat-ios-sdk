import SinchPushSDKNotificationExtension
import XCTest

@testable import SinchPushSDK

final class PendingDeliveryStoreTests: XCTestCase {

    private var container: ReportContainer!
    private let clock = TestClock()

    override func setUp() {
        super.setUp()
        container = makeTestContainer()
    }

    override func tearDown() {
        if let directory = container.directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private func store() -> PendingDeliveryStore {
        let clock = clock
        return PendingDeliveryStore(container: container, now: { clock.now })
    }

    private func delivery(_ id: String, subscriber: String = "s-1") -> ReportedDelivery {
        ReportedDelivery(messageID: id, subscriberID: subscriber)
    }

    func testTakingReturnsTheDeliveriesOldestFirstAndEmptiesTheStore() {
        store().append([delivery("a")])
        clock.advance(by: 10)
        store().append([delivery("b", subscriber: "s-2")])

        let taken = store().take()

        XCTAssertEqual(taken, [PendingDelivery(messageId: "a", subscriberId: "s-1", failedAt: clock.now.addingTimeInterval(-10)),
                               PendingDelivery(messageId: "b", subscriberId: "s-2", failedAt: clock.now)])
        XCTAssertEqual(store().take(), [])
    }

    func testNothingIsPendingInAFreshContainer() {
        XCTAssertEqual(store().take(), [])
    }

    func testTheSameDeliveryIsStoredOnce() {
        store().append([delivery("a")])
        store().append([delivery("a"), delivery("a", subscriber: "s-2")])

        XCTAssertEqual(store().take().map(\.subscriberId), ["s-1", "s-2"])
    }

    func testTheStoreHoldsTheLastThousand() {
        store().append((0..<1005).map { delivery("m-\($0)") })

        let taken = store().take()

        XCTAssertEqual(taken.count, 1000)
        XCTAssertEqual(taken.first?.messageId, "m-5")
        XCTAssertEqual(taken.last?.messageId, "m-1004")
    }

    func testDeliveriesExpireAfterSevenDays() {
        store().append([delivery("old")])
        clock.advance(by: 6 * 24 * 3600)
        store().append([delivery("newer")])
        clock.advance(by: 2 * 24 * 3600)

        XCTAssertEqual(store().take().map(\.messageId), ["newer"])
    }

    func testTwoContainersOfTheSameGroupShareTheStore() {
        store().append([delivery("a")])
        let other = ReportContainer(appGroup: "group.test", directory: container.directory?.deletingLastPathComponent())

        let clock = clock
        XCTAssertEqual(PendingDeliveryStore(container: other, now: { clock.now }).take().map(\.messageId), ["a"])
        XCTAssertEqual(store().take(), [])
    }

    func testNothingIsStoredWithoutDeliveries() {
        store().append([])

        XCTAssertEqual(store().take(), [])
    }

    func testConcurrentAppendsAreAllKept() {
        let shared = store()
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            shared.append([delivery("m-\(index)")])
        }

        XCTAssertEqual(Set(store().take().map(\.messageId)), Set((0..<20).map { "m-\($0)" }))
    }
}

final class ReportSessionRegistryTests: XCTestCase {

    private var container: ReportContainer!
    private let clock = TestClock()

    override func setUp() {
        super.setUp()
        container = makeTestContainer()
    }

    override func tearDown() {
        if let directory = container.directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private func registry() -> ReportSessionRegistry {
        let clock = clock
        return ReportSessionRegistry(container: container, now: { clock.now })
    }

    func testOnlyIdleSessionsAreListed() {
        registry().touch("old")
        clock.advance(by: 400)
        registry().touch("recent")

        XCTAssertEqual(registry().identifiers(idleFor: 300), ["old"])
        XCTAssertEqual(Set(registry().identifiers(idleFor: 0)), ["old", "recent"])
    }

    func testTouchingASessionAgainRefreshesItOnce() {
        registry().touch("a")
        clock.advance(by: 400)
        registry().touch("a")

        XCTAssertEqual(registry().identifiers(idleFor: 300), [])
        XCTAssertEqual(registry().identifiers(idleFor: 0), ["a"])
    }

    func testARemovedSessionIsForgotten() {
        registry().touch("a")
        registry().touch("b")

        registry().remove("a")

        XCTAssertEqual(registry().identifiers(idleFor: 0), ["b"])
    }

    func testSessionsExpireAfterADayAndTheListIsBounded() {
        registry().touch("ancient")
        clock.advance(by: 25 * 3600)
        for index in 0..<60 { registry().touch("s-\(index)") }

        let all = registry().identifiers(idleFor: 0)

        XCTAssertEqual(all.count, ReportSessionRegistry.capacity)
        XCTAssertFalse(all.contains("ancient"))
        XCTAssertFalse(all.contains("s-9"))
        XCTAssertTrue(all.contains("s-59"))
    }
}

final class AccessTokenExpiryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func token(payload: String) -> String {
        func encode(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return [encode(#"{"alg":"none"}"#), encode(payload), "sig"].joined(separator: ".")
    }

    private func token(exp: TimeInterval) -> String {
        token(payload: #"{"uuid":"u","exp":\#(Int(exp))}"#)
    }

    func testAPastExpiryIsExpired() {
        XCTAssertTrue(AccessTokenExpiry.isExpired(token(exp: now.timeIntervalSince1970 - 1), leeway: 0, now: now))
    }

    func testAFutureExpiryIsNot() {
        XCTAssertFalse(AccessTokenExpiry.isExpired(token(exp: now.timeIntervalSince1970 + 3600), leeway: 60, now: now))
    }

    func testTheLeewayCountsATokenAboutToExpire() {
        let soon = token(exp: now.timeIntervalSince1970 + 30)

        XCTAssertFalse(AccessTokenExpiry.isExpired(soon, leeway: 0, now: now))
        XCTAssertTrue(AccessTokenExpiry.isExpired(soon, leeway: 60, now: now))
    }

    func testAFractionalExpiryIsRead() {
        let fractional = token(payload: #"{"exp":1770000100.5}"#)

        XCTAssertEqual(AccessTokenExpiry.expiry(of: fractional), Date(timeIntervalSince1970: 1_770_000_100.5))
    }

    func testATokenThatCannotBeReadIsNotExpired() {
        XCTAssertFalse(AccessTokenExpiry.isExpired("not-a-jwt", leeway: 60, now: now))
        XCTAssertFalse(AccessTokenExpiry.isExpired("", leeway: 60, now: now))
        XCTAssertFalse(AccessTokenExpiry.isExpired("a.@@@.c", leeway: 60, now: now))
        XCTAssertFalse(AccessTokenExpiry.isExpired(token(payload: #"{"uuid":"u"}"#), leeway: 60, now: now), "no exp")
        XCTAssertFalse(AccessTokenExpiry.isExpired(token(payload: #"{"exp":"soon"}"#), leeway: 60, now: now))
    }

    func testTheClockIsTheDeviceByDefault() {
        XCTAssertTrue(AccessTokenExpiry.isExpired(token(exp: 1_000), leeway: 60))
        XCTAssertFalse(AccessTokenExpiry.isExpired(token(exp: Date().timeIntervalSince1970 + 3600), leeway: 60))
    }
}
