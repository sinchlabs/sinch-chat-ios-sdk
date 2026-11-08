import XCTest
@testable import SinchChatSDK

/// The claim on the real flag (`SinchChatSDK.shared._chat`), mixed with writes the way the chat screen makes them: it
/// takes the flag with a token of its own and never asks whether anyone else holds it. `screenWrites` stands for a
/// flag written without a token (what the screen did before it had one); the `DefaultStartViewModel` tests below use
/// the real screen.
@MainActor
final class SystemHeadlessEnvironmentTests: XCTestCase {

    private var chat: DefaultSinchChat { SinchChatSDK.shared._chat }
    private let system = SystemHeadlessEnvironment()
    private var savedState: SinchChatState = .idle
    private var savedOwner: UUID?
    private var dataSource: FakeMessageDataSource!
    private var environment: FakeHeadlessEnvironment!
    private var conversation: SinchConversation!

    override func setUp() async throws {
        savedState = chat.state
        savedOwner = chat.stateOwner
        chat.setFlag(state: .idle, owner: nil)
        dataSource = FakeMessageDataSource()
        environment = FakeHeadlessEnvironment()
        environment.chatBackend = system
        conversation = Fixture.conversation(dataSource, environment: environment)
    }

    override func tearDown() async throws {
        conversation.stop()
        conversation = nil
        chat.setFlag(state: savedState, owner: savedOwner)
    }

    /// What `StartViewModel` does to the flag.
    private func screenWrites(_ state: SinchChatState) {
        chat.setFlag(state: state, owner: nil)
    }

    // MARK: claimChat / releaseChat

    func test_claim_takesTheFlag_forOneOwnerAtATime() {
        let first = UUID()
        let second = UUID()

        XCTAssertTrue(system.claimChat(owner: first))
        XCTAssertEqual(chat.state, .running)
        XCTAssertEqual(chat.stateOwner, first)
        XCTAssertTrue(system.claimChat(owner: first), "claiming again with the same token succeeds")
        XCTAssertFalse(system.claimChat(owner: second))
        XCTAssertEqual(chat.stateOwner, first)

        system.releaseChat(owner: second) // not the owner: nothing happens
        XCTAssertEqual(chat.state, .running)
        system.releaseChat(owner: first)
        XCTAssertEqual(chat.state, .idle)
        XCTAssertNil(chat.stateOwner)
    }

    func test_screenWriteWhileClaimed_takesTheFlagAway_andTheOldOwnerCanNeitherReclaimNorRelease() {
        let owner = UUID()
        XCTAssertTrue(system.claimChat(owner: owner))

        screenWrites(.running) // the chat screen resumed: running, no owner

        XCTAssertFalse(system.claimChat(owner: owner), "the screen holds the flag now")
        system.releaseChat(owner: owner)
        XCTAssertEqual(chat.state, .running, "a release by the old owner must not clear the screen's flag")
        XCTAssertNil(chat.stateOwner)

        screenWrites(.idle) // the screen closed
        XCTAssertTrue(system.claimChat(owner: owner))
        XCTAssertEqual(chat.stateOwner, owner)
    }

    func test_screenIdleWrite_clearsAStaleOwner() {
        let owner = UUID()
        XCTAssertTrue(system.claimChat(owner: owner))

        screenWrites(.idle)

        XCTAssertNil(chat.stateOwner)
        XCTAssertTrue(system.claimChat(owner: UUID()), "the flag is free after the screen wrote idle")
    }

    // MARK: The chat screen's own token

    private func makeScreen() -> DefaultStartViewModel {
        DefaultStartViewModel(messageDataSource: MessageDataSourceStub(), notificationPermission: PushNotificationHandlerStub())
    }

    func test_screen_takesTheFlagWithItsOwnToken_andGivesItBackWhenItDisappears() {
        let screen = makeScreen()

        screen.onInternetOn()

        XCTAssertEqual(chat.state, .running)
        XCTAssertNotNil(chat.stateOwner, "the screen holds the flag with a token of its own")
        XCTAssertFalse(system.claimChat(owner: UUID()))

        screen.onDisappear()

        XCTAssertEqual(chat.state, .idle)
        XCTAssertNil(chat.stateOwner)
        XCTAssertTrue(system.claimChat(owner: UUID()))
    }

    func test_screenThatLostTheFlag_doesNotWipeAHeadlessClaim() async throws {
        let stale = makeScreen()
        stale.onInternetOn()
        stale.onDisappear() // gave the flag back
        dataSource.setPages([[Fixture.text("m1", "one")]])
        try await conversation.start()
        let holder = try XCTUnwrap(chat.stateOwner)

        stale.onInternetLost() // a screen that no longer holds the flag writes idle
        stale.onDidEnterBackground()
        stale.onDisappear()

        XCTAssertEqual(chat.state, .running)
        XCTAssertEqual(chat.stateOwner, holder)
        XCTAssertEqual(conversation.phase, .ready)
        conversation.stop()
        XCTAssertEqual(chat.state, .idle, "the conversation can still release its own claim")
    }

    func test_screenThatLostTheFlagToAnotherScreen_doesNotWipeIt() {
        let first = makeScreen()
        let second = makeScreen()
        first.onInternetOn()
        second.onInternetOn() // takes the flag over, as the chat screen always did
        let holder = chat.stateOwner

        first.onInternetLost()

        XCTAssertEqual(chat.state, .running)
        XCTAssertEqual(chat.stateOwner, holder)
        second.onDisappear()
        XCTAssertEqual(chat.state, .idle)
    }

    func test_screenThatTakesTheFlagFromAConversation_winsIt_andTheConversationCannotReleaseIt() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        try await conversation.start()
        let screen = makeScreen()

        screen.onInternetOn()
        let holder = chat.stateOwner
        conversation.stop()

        XCTAssertEqual(chat.state, .running, "stop() leaves the screen's flag alone")
        XCTAssertEqual(chat.stateOwner, holder)
        screen.onDisappear()
        XCTAssertEqual(chat.state, .idle)
    }

    func test_screenDroppedWhileHoldingTheFlag_givesItBack() async {
        var screen: DefaultStartViewModel? = makeScreen()
        screen?.onInternetOn()
        XCTAssertEqual(chat.state, .running)

        screen = nil

        await waitUntil { self.chat.state == .idle }
        XCTAssertNil(chat.stateOwner)
    }

    // MARK: A conversation on the real flag

    func test_stop_afterTheScreenTookTheFlag_leavesTheScreensFlagAlone() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        try await conversation.start()
        XCTAssertEqual(chat.state, .running)
        XCTAssertNotNil(chat.stateOwner)

        screenWrites(.running)
        conversation.stop()

        XCTAssertEqual(chat.state, .running, "stop() must not set the screen's flag to idle")
        XCTAssertNil(chat.stateOwner)
    }

    func test_reconnect_afterTheScreenTookTheFlag_failsAsUnavailable_untilTheScreenClosesAndStartIsCalledAgain() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        try await conversation.start()
        environment.setOnline(false)
        await waitUntil { self.chat.state == .idle }

        screenWrites(.running) // the screen opens while the conversation is offline
        environment.setOnline(true)

        await waitUntil { self.conversation.phase == .failed(.unavailable) }
        XCTAssertEqual(chat.state, .running, "the screen's flag is untouched")
        XCTAssertNil(chat.stateOwner)
        XCTAssertEqual(dataSource.historyCalls, 1, "nothing was loaded without the flag")

        screenWrites(.idle) // the screen closed
        try await conversation.start()
        XCTAssertEqual(conversation.phase, .ready)
        XCTAssertEqual(chat.state, .running)
        XCTAssertNotNil(chat.stateOwner)
    }

    func test_start_whileReconnectingAndTheScreenTookTheFlag_throwsUnavailable() async throws {
        dataSource.setPages([[Fixture.text("m1", "one")]])
        try await conversation.start()
        environment.setOnline(false)
        await waitUntil { self.chat.state == .idle }
        dataSource.holdNextHistoryCalls()
        environment.setOnline(true) // claims the flag again and reloads
        await waitUntil { self.dataSource.heldHistoryCalls == 1 }
        XCTAssertNotNil(chat.stateOwner)

        screenWrites(.running) // the screen takes over while the reload is in flight

        do {
            try await conversation.start()
            XCTFail("expected unavailable")
        } catch {
            XCTAssertEqual(error as? SinchHeadlessError, .unavailable)
        }
        XCTAssertEqual(chat.state, .running)
        XCTAssertNil(chat.stateOwner)
        dataSource.releaseHistory()
    }
}
