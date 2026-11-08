import Foundation
import Synchronization
import XCTest
@testable import SinchChatSDK

/// The "chat is running" flag is read from any thread (`isChatAvailable()`, the push handler) while the main actor
/// claims and releases it: state and owner are one value behind one lock.
final class ChatFlagTests: XCTestCase {

    private func makeChat() -> DefaultSinchChat {
        DefaultSinchChat(pushPermissionHandler: PushNotificationHandlerStub())
    }

    func test_concurrentClaims_haveExactlyOneWinner() {
        let chat = makeChat()
        let winners = Mutex(0)

        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            if chat.claimChat(owner: UUID()) {
                winners.withLock { $0 += 1 }
            }
        }

        XCTAssertEqual(winners.withLock { $0 }, 1)
        XCTAssertEqual(chat.state, .running)
        XCTAssertNotNil(chat.stateOwner)
    }

    func test_claimsAndReleasesFromManyThreads_leaveAConsistentFlag() {
        let chat = makeChat()
        let owners = (0..<8).map { _ in UUID() }

        DispatchQueue.concurrentPerform(iterations: 4000) { index in
            let owner = owners[index % owners.count]
            _ = chat.isChatAvailable()
            if chat.claimChat(owner: owner) { chat.releaseChat(owner: owner) }
        }

        // Every claim that won was released by the same token: nothing is left held.
        XCTAssertEqual(chat.state, .idle)
        XCTAssertNil(chat.stateOwner)
    }

    func test_releaseByAnotherToken_doesNothing() {
        let chat = makeChat()
        let owner = UUID()
        XCTAssertTrue(chat.claimChat(owner: owner))

        chat.releaseChat(owner: UUID())

        XCTAssertEqual(chat.state, .running)
        XCTAssertEqual(chat.stateOwner, owner)
        chat.releaseChat(owner: owner)
        XCTAssertEqual(chat.state, .idle)
        XCTAssertNil(chat.stateOwner)
    }

    func test_screenRelease_appliesToItsOwnTokenOrToAnUnownedFlag_butNotToAnotherHolder() {
        let chat = makeChat()
        let screen = UUID()
        let holder = UUID()

        chat.takeChat(owner: screen)
        chat.releaseChatFromScreen(owner: screen)
        XCTAssertEqual(chat.state, .idle)

        XCTAssertTrue(chat.claimChat(owner: holder))
        chat.releaseChatFromScreen(owner: screen)
        XCTAssertEqual(chat.state, .running, "another holder's claim stays")
        XCTAssertEqual(chat.stateOwner, holder)

        chat.setFlag(state: .running, owner: nil) // the flag written without a token
        chat.releaseChatFromScreen(owner: screen)
        XCTAssertEqual(chat.state, .idle)
    }

    func test_isChatAvailable_readsTheFlag() {
        let chat = makeChat()
        XCTAssertEqual(chat.isChatAvailable(), .uninitialized)
        XCTAssertTrue(chat.claimChat(owner: UUID()))
        XCTAssertEqual(chat.isChatAvailable(), .currentlyRunning)
    }
}
