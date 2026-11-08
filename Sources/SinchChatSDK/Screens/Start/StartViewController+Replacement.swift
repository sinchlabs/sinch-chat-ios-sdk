import UIKit

/// A chat shown in the detail column of the adaptive inbox that must give up the "one running chat" slot
/// synchronously, before the next chat is created.
@MainActor
protocol InboxReplaceableChat: AnyObject {
    /// Stops the chat (subscription, history, global `idle` state) without waiting for it to be deallocated.
    func tearDownForReplacement()
}

extension StartViewController: InboxReplaceableChat {

    /// `deinit` only schedules its teardown in a `Task`, which can run after the next chat has started and would
    /// reset the global state under it. This releases the flag and posts `didCloseChat` now; afterwards the view
    /// model ignores lifecycle calls (foreground, network, `deinit`), so a chat kept alive by a transition can't
    /// come back to `running`. The channel stays open: the inbox owns it (`isStartedFromInbox`).
    func tearDownForReplacement() {
        guard !isTornDownForReplacement else { return }
        isTornDownForReplacement = true
        viewModel.tearDownForReplacement()
        SinchChatSDK.shared.eventListenerSubject.send(.didCloseChat)
    }
}
