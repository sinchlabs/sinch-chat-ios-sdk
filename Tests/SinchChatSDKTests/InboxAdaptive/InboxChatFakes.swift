import UIKit
@testable import SinchChatSDK

/// Mimics the global "one chat at a time" slot (`SinchChatSDK.shared._chat.state`): taken when a chat is created,
/// given back when the chat is torn down or deallocated, and refused while taken (like `getChatViewController`).
@MainActor
final class FakeChatSlot {

    enum Failure: Error { case alreadyRunning, injected }

    private(set) var isRunning = false
    /// What happened to the slot, in order: `start(n)` when chat n was created, `close(n)` when it was torn down
    /// for its replacement, `deinit(n)` when its deallocation was handled (after the `Task` hop of the real code).
    private(set) var events: [String] = []
    private(set) var startedCount = 0
    /// Serials of the chats that were torn down for their replacement.
    private(set) var tornDownSerials: Set<Int> = []
    /// The next `claim()` throws `Failure.injected`.
    var failNextClaim = false

    func claim() throws {
        if failNextClaim {
            failNextClaim = false
            throw Failure.injected
        }
        guard !isRunning else { throw Failure.alreadyRunning }
        isRunning = true
        events.append("start(\(startedCount))")
        startedCount += 1
    }

    func didTearDown(_ serial: Int) {
        tornDownSerials.insert(serial)
        events.append("close(\(serial))")
        isRunning = false
    }

    /// Like the real `deinit`: a chat that was torn down for its replacement leaves the slot alone.
    func didDeinit(_ serial: Int, wasTornDown: Bool) {
        events.append("deinit(\(serial))")
        if !wasTornDown { isRunning = false }
    }

    func markRunning() { isRunning = true }

    func release() { isRunning = false }
}

/// A chat screen that behaves like `StartViewController` as far as the inbox cares: running while alive, idle
/// after `tearDownForReplacement`, and (like the real `deinit`) idle again only in a later `Task`, and not at all
/// when it was torn down for its replacement before.
@MainActor
final class FakeChatViewController: UIViewController, InboxReplaceableChat {

    let channelID: String?
    private let slot: FakeChatSlot
    /// Position in creation order (0 for the first chat the slot started).
    let serial: Int
    // Written on main only; deinit has exclusive access, so the unchecked read there is safe.
    nonisolated(unsafe) private(set) var isTornDown = false

    init(slot: FakeChatSlot, channelID: String?) {
        self.slot = slot
        self.serial = slot.startedCount - 1
        self.channelID = channelID
        super.init(nibName: nil, bundle: nil)
        title = "chat"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Like the real chat, the slot is (re)marked running once the screen is up, unless it was already replaced.
        if !isTornDown { slot.markRunning() }
    }

    func tearDownForReplacement() {
        guard !isTornDown else { return }
        isTornDown = true
        slot.didTearDown(serial)
    }

    deinit {
        let slot = self.slot
        let serial = self.serial
        let wasTornDown = isTornDown
        Task { @MainActor in slot.didDeinit(serial, wasTornDown: wasTornDown) }
    }
}
