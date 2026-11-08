import XCTest
import GRPCCore
import GRPCNIOTransportHTTP2Posix
@testable import SinchChatSDK

/// Lets a test decide when a fake gRPC call returns.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// An API client whose calls never reach the network. The first call ignores cancellation until its gate opens (a run
/// that outlives its cancellation); later calls wait until they are cancelled.
private final class BlockingAPIClient: APIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let firstCallGate = Gate()

    var isChannelStarted: Bool { true }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }

    func closeChannel() {}
    func startChannel() {}

    func withClient<Result: Sendable>(handle: (GRPCClient<HTTP2ClientTransport.Posix>) async throws -> Result) async throws -> Result {
        let number: Int = { lock.lock(); defer { lock.unlock() }; count += 1; return count }()
        if number == 1 {
            await firstCallGate.wait()
        } else {
            try await Task.sleep(for: .seconds(30))
        }
        throw CancellationError()
    }
}

/// `cancelSubscription()` followed by a new subscription must keep the new run's slot even when the old run finishes
/// afterwards: clearing it would let a third subscription start a second server stream next to the live one.
final class DataSourceSubscriptionSlotTests: XCTestCase {

    private func waitFor(_ timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func test_messages_oldRunFinishingAfterResubscribe_keepsTheNewSlot() async throws {
        let client = BlockingAPIClient()
        let source = DefaultMessageDataSource(apiClient: client, tokenProvider: MockTokenProvider())
        let first = source.subscribeForMessages()
        let firstDrain = Task { for try await _ in first {} }
        await waitFor { client.calls == 1 }
        XCTAssertTrue(source.isSubscribed())

        source.cancelSubscription() // the old run keeps going: its call has not returned
        XCTAssertFalse(source.isSubscribed())
        let second = source.subscribeForMessages()
        let secondDrain = Task { for try await _ in second {} }
        await waitFor { client.calls == 2 }
        XCTAssertTrue(source.isSubscribed())

        await client.firstCallGate.open() // now the old run finishes
        _ = try? await firstDrain.value
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(source.isSubscribed(), "the old run must not clear the slot of the new one")
        source.cancelSubscription()
        secondDrain.cancel()
    }

    func test_channels_oldRunFinishingAfterResubscribe_keepsTheNewSlot() async throws {
        let client = BlockingAPIClient()
        let source = DefaultInboxDataSource(apiClient: client, tokenProvider: MockTokenProvider())
        let first = source.subscribeForChannels()
        let firstDrain = Task { for try await _ in first {} }
        await waitFor { client.calls == 1 }
        XCTAssertTrue(source.isSubscribed())

        source.cancelSubscription()
        let second = source.subscribeForChannels()
        let secondDrain = Task { for try await _ in second {} }
        await waitFor { client.calls == 2 }
        XCTAssertTrue(source.isSubscribed())

        await client.firstCallGate.open()
        _ = try? await firstDrain.value
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(source.isSubscribed(), "the old run must not clear the slot of the new one")
        source.cancelSubscription()
        secondDrain.cancel()
    }
}
