# SinchChatSDK

Sinch Chat SDK for iOS. The SDK provides UIKit view controllers for chat and inbox, plus first-stage SwiftUI support through wrapper views and a state object.

Push notifications come from a separate package, [SinchPushSDK](https://github.com/sinchlabs/sinch-push-ios-sdk),
which this SDK depends on and re-exports. `SinchChatSDK.shared.push` is
`SinchPushSDK.shared.push`: the same facade, the same persisted state.

## Requirements

- iOS 18+
- Swift 6+

## Installation

### Swift Package Manager

```
https://github.com/sinchlabs/sinch-chat-ios-sdk.git
```

| Product | Target |
| --- | --- |
| `SinchChatSDK` | the app |
| `SinchChatSDKNotificationExtension` | a Notification Service Extension — a compatibility re-export of `SinchPushSDKNotificationExtension` |

The package resolves [sinch-push-ios-sdk](https://github.com/sinchlabs/sinch-push-ios-sdk)
itself; do not add it separately.

### CocoaPods

SinchChatSDK 2.0.0 and later are a **binary** pod (`vendored_frameworks`) published in our own spec
repo, not on trunk. 2.2.0 reaches that spec repo a few days after the GitHub release: from then on
`pod 'SinchChatSDK'` resolves 2.2.0, and before it resolves 2.1.1. Swift Package Manager has had 2.2.0 since its GitHub release.
Add both sources:

```ruby
source 'https://github.com/sinchlabs/sinch-ios-specs.git'
source 'https://cdn.cocoapods.org/'   # trunk, for the app's other pods

platform :ios, '18.0'
use_frameworks!

target 'App' do
  pod 'SinchChatSDK'   # brings SinchPushSDK, the source push pod, with it
end

target 'NotificationService' do
  # The NSE target takes the extension pod only, never SinchChatSDK or SinchPushSDK.
  pod 'SinchPushSDKNotificationExtension'
end

```

The binary links gRPC Swift 2 and Kingfisher statically inside the framework. It links
`SinchPushSDK` and `SwiftProtobuf` dynamically, so the app ships exactly one protobuf
runtime and the chat SDK, the push pod and the app all share it.

Protobuf comes from `SinchSwiftProtobuf`, Apple's swift-protobuf 1.39.0 sources
repackaged for iOS 16 with library evolution. The module is still `SwiftProtobuf`, and
no `post_install` hook is needed (you can delete the one from 2.1.0 and earlier). Do not
add trunk's `SwiftProtobuf` pod to the same app: both pods provide the `SwiftProtobuf`
module, and `pod install` fails.

## Setup

1. Add the `SinchChatSDK` package to your project.
2. Initialize the SDK early in app launch (typically from `AppDelegate` or `@UIApplicationDelegateAdaptor`):

```swift
SinchChatSDK.shared.initialize(.init(pushNotificationMode: .sandbox))
```

3. Set the user identity before opening chat or inbox UI:

```swift
try await SinchChatSDK.shared.setIdentity(
    config: .init(
        clientID: "your-client-id",
        projectID: "your-project-id",
        configID: "your-config-id",
        region: .EU1
    ),
    identity: .anonymous
)
```

The completion-handler form is still available, and does the same thing:

```swift
SinchChatSDK.shared.setIdentity(
    with: .init(
        clientID: "your-client-id",
        projectID: "your-project-id",
        configID: "your-config-id",
        region: .EU1
    ),
    identity: .anonymous
) { result in
    // handle result
}
```

## UIKit Integration

Create chat UI (chat UI is created synchronously and must run on the main actor, so an async flow awaits the
identity first and then opens it):

```swift
Task { @MainActor in
    try await SinchChatSDK.shared.setIdentity(config: config, identity: .anonymous)

    let chatViewController = try SinchChatSDK.shared.chat.getChatViewController(
        uiConfig: .defaultValue,
        localizationConfig: .defaultValue,
        options: GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true)
    )
    navigationController.pushViewController(chatViewController, animated: true)
}
```

Create inbox UI:

```swift
let inboxViewController = try SinchChatSDK.shared.chat.inbox.getInboxViewController(
    uiConfig: .defaultValue,
    localizationConfig: .defaultValue,
    options: GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true)
)
navigationController.pushViewController(inboxViewController, animated: true)
```

## Async/await

Every completion-handler call has an `async` counterpart, added in 2.1.0 and fully additive: both forms
call the same code, so a call site can migrate one call at a time. The async forms are `async throws`
where the completion form reports an error.

### Identity

```swift
// Sets the identity and returns when it is stored.
try await SinchChatSDK.shared.setIdentity(
    config: config,
    identity: .selfSignedWithAppSecret(userId: userID, appSecret: appSecret)
)

// Logs the user out and removes the token.
try await SinchChatSDK.shared.removeIdentity()
```

`setIdentity(config:identity:)` is a typed-throws function: `catch` receives a `SinchSDKIdentityError`, so the
failure can be handled exhaustively. The chat side effects are the same as in the completion form — the token
provider, the chat channel of the identity's region, the `didSetIdentity` plugin event and a fresh chat session.
The `config:` label differs from the completion form's `with:` on purpose: overloading on `async` alone would
capture 2.0.0 calls written inside an `async` function and start requiring `try await`.

### Inbox

```swift
let chats = await SinchChatSDK.shared.chat.inbox.getInboxChats(options: nil)

for chat in chats {
    print(chat.name, chat.text)
}
```

As in the completion form, a failure (for example "not logged in") is reported as an empty array.

### Events

The two public Combine subjects have `AsyncStream` accessors. Each access subscribes afresh — nothing is
replayed — and the subscription is cancelled when the consumer stops iterating, on `break`, on task
cancellation or when the stream is released:

```swift
for await event in SinchChatSDK.shared.events {
    switch event {
    case .didSetIdentity(let auth): print("signed in", auth)
    case .didRemoveIdentity: print("signed out")
    default: break
    }
}

for await update in SinchChatSDK.shared.chat.inbox.events {
    if case .chatUpdated(let chat) = update {
        print("conversation updated:", chat.name)
    }
}
```

Both streams buffer up to 64 pending events and drop the oldest when a consumer does not drain them.

### Plugins

The methods a chat plugin receives have async forms too:

```swift
let payload = try await methods.sendMessage(.text("Hi"), authModel: nil, chatOptions: nil)
await methods.presentViewController(viewController, true)
```

### Push

`SinchChatSDK.shared.push` is the push facade, so the push SDK's async APIs — notification permissions, the
relay streams and the in-app events — are available on the same object:

```swift
let push = SinchChatSDK.shared.push

// Asks the system and returns the answer; the completion and Combine forms are unchanged.
let status = await push.requestNotificationPermission()

// The current permission, without asking.
let current = await push.notificationPermissionStatus()

// The relay state: the current one first, then every change.
for await state in push.socketStates {
    print("relay:", state)
}

// Relay messages, each once and in order.
for await message in push.socketMessages {
    print("push:", message)
}

// In-app alert lifecycle events, next to `inAppMessages.delegate`.
for await event in SinchPushSDK.shared.inAppMessages.events {
    switch event {
    case .presented(let message): print("in-app:", message)
    case .actionTapped(let action, let message): print("action:", action, message)
    case .dismissed(let message): print("dismissed:", message)
    }
}
```

The async permission methods are named apart from `askNotificationPermission()` and `checkPushPermission()` on
purpose: those already have a no-argument Combine overload, so a same-name `async` one would make
`push.askNotificationPermission().sink` ambiguous. Each `for await` loop is one subscriber and is cancelled when
the loop exits.

## SwiftUI Integration

### Wrapper Views

Use `SinchChatView` and `SinchInboxView` to embed SDK UI in SwiftUI:

```swift
import SwiftUI
import SinchChatSDK

struct ChatScreen: View {
    var body: some View {
        SinchChatView(
            uiConfig: .defaultValue,
            localizationConfig: .defaultValue,
            options: GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true),
            onError: { error in
                print("Failed to open chat: \(error)")
            }
        )
        .ignoresSafeArea()
    }
}
```

```swift
struct InboxScreen: View {
    var body: some View {
        SinchInboxView(
            options: GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true)
        )
        .ignoresSafeArea()
    }
}
```

These views wrap the existing UIKit controllers in a `UINavigationController`, preserving SDK navigation behavior.

### State Management

Use `SinchChatSDKState` for SwiftUI-friendly identity and event handling:

```swift
import SwiftUI
import SinchChatSDK

struct ContentView: View {
    @StateObject private var sinchState = SinchChatSDKState()
    @State private var showChat = false

    var body: some View {
        VStack {
            Text("Chat status: \(String(describing: sinchState.chatAvailability))")

            Button("Sign In") {
                Task {
                    try await sinchState.setIdentity(
                        with: .init(
                            clientID: "your-client-id",
                            projectID: "your-project-id",
                            configID: "your-config-id",
                            region: .EU1
                        ),
                        identity: .anonymous
                    )
                    showChat = true
                }
            }
        }
        .fullScreenCover(isPresented: $showChat) {
            SinchChatView(options: GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true))
        }
    }
}
```

Available state:

- `identityStatus` — `.notSet`, `.setting`, `.set`, `.removing`, `.failed`
- `chatAvailability` — current chat availability from the SDK
- `isSettingIdentity` / `isRemovingIdentity` — loading flags
- `lastPluginEvent` — latest SDK lifecycle event
- `inboxChats` — inbox conversations loaded via `loadInboxChats(options:)`
- `lastInboxEvent` — latest inbox update event
- `lastError` — most recent error

Async methods:

```swift
try await sinchState.setIdentity(with: config, identity: .anonymous)
try await sinchState.removeIdentity()
sinchState.refreshChatAvailability()
await sinchState.loadInboxChats(options: nil)
sinchState.subscribeToSDKEvents()
sinchState.subscribeToInboxUpdates(options: GetChatViewControllerOptions(metadata: [], shouldInitializeConversation: true))
```

## iPad and foldable iPhone

The chat and inbox screens adapt to the window, not the device model, so the same code covers iPhone, iPhone Duo
(folded and unfolded), iPad, Split View, Slide Over and Stage Manager. No configuration is needed.

| Window | Inbox | Chat |
|---|---|---|
| Compact width (iPhone, iPhone Duo folded, narrow iPad split) | list; tapping a row pushes the chat | full width |
| Regular width (iPad, iPhone Duo unfolded, wide windows) | sidebar with the chat beside it | centred column, max 680 pt (760 pt when the chat area is wider than 900 pt) |

- The chat area is the width of the chat itself, not of the window: next to the inbox sidebar it is the detail
  column. Text bubbles are capped at 520 pt on regular width and rich cards grow to 360 pt; iPhone portrait is
  unchanged.
- The attachment menu, photo library, document picker and share sheet open as popovers anchored to the tapped
  control on regular width.
- On iPhone Duo with iOS 27.1 or later the inbox sidebar ends at the hinge when the device is unfolded. The hinge
  code is compiled with Xcode 27.2 or later (the CocoaPods binary includes it); older Xcode versions build without it.
- `getInboxViewController(layout: .stack)` and `SinchInboxView(layout: .stack)` keep the list-only inbox. When you
  host `SinchInboxView` in a `NavigationStack`, hide the stack's bar with `.toolbar(.hidden, for: .navigationBar)`
  and pass `onClose:` so the sidebar shows a back button. See [Documentation/SinchInbox.md](Documentation/SinchInbox.md).

## Headless (no UI)

To build your own chat UI, use the logic without the SDK screens. `makeConversation` returns a
`SinchConversation`: an `@Observable` `@MainActor` model that owns history paging, the subscription and its
reconnects, optimistic sends (de-duplicated against the server echo), the typing indicator, network reachability
and app foreground/background handling. The new headless types (`SinchConversation`, `SinchInboxModel`,
`SinchPendingMessage`, `SinchMedia`, `SinchMessageContent`, ...) use Foundation types only. `Message.body` and
`MessageMedia` still carry UIKit types (images, for one), as they do for the SDK screens.

It throws `SinchChatSDKError.unavailable` in the cases where `getChatViewController` does, including while another
chat is running: only one chat can run at a time, so call `stop()` before creating the next one. `start()` checks
again and throws `SinchHeadlessError.unavailable`, because another chat can open between `makeConversation` and
`start()`. A conversation holds the "chat is running" flag only while it is connected: it gives it back when loading
fails, when the device goes offline and when the app moves to the background, and takes it again when it reloads.
A chat screen that opens, or returns to the foreground, takes the "chat is running" flag from a running headless
conversation: the conversation keeps its live subscription until its next reconnect, and then becomes
`.failed(.unavailable)`. Both models throw `SinchHeadlessError`.

```swift
let conversation = try SinchChatSDK.shared.chat.makeConversation(options: nil)
try await conversation.start()          // first history page + live subscription; idempotent
                                        // cancelling while start() is still loading abandons it;
                                        // call stop() when the view goes away

conversation.messages                   // [Message], chronological, no date separators
conversation.pending                    // [SinchPendingMessage]: .sending / .failed, render after messages
conversation.phase                      // .idle, .connecting, .ready, .failed(SinchHeadlessError)
conversation.isLoadingHistory, conversation.hasMoreHistory
conversation.isAgentTyping, conversation.isOnline

try await conversation.loadMore()       // older page
try await conversation.send(text: "Hello")
try await conversation.send(.file(url)) // .image(Data), .video(URL), .audio(URL), .file(URL)
try await conversation.sendLocation(latitude: 52.52, longitude: 13.40)
try await conversation.sendChoice(postback: "yes", messageID: "…")
try await conversation.retry(tempID)    // a message whose status is .failed
conversation.sendTyping(true)
conversation.stop()                     // closes the channel, posts .didCloseChat, ends the `updates` streams
```

`phase`, `isAgentTyping`, `isOnline`, `isLoadingHistory` and `hasMoreHistory` are observable properties only. They are
not events on `updates`; read them when an update arrives or observe them with `withObservationTracking`.

`phase` also covers the connection after `.ready`: while the device is offline or the app is in the background the
model has given the connection up and is `.connecting` again, sends throw `SinchHeadlessError.offline`, and it reloads
by itself. `start()` interrupted by going offline throws `.offline` and leaves `.failed(.offline)`, which retries by
itself too.

`message.content` turns a `Message` into an enum (`.text`, `.media`, `.location`, `.choices`, `.card`, `.carousel`,
`.event`, ...) so you do not have to cast `message.body` to the concrete body types (`MessageText` and the others are
public).

**Include `default:` in every `switch` over these enums.** Built from source (SPM), a new case breaks an exhaustive
switch; with the binary pod it is a warning. Use `default:` either way. These enums may gain cases in minor releases:
`SinchMessageContent` (a new kind of message), `SinchConversationUpdate`, `SinchHeadlessError`,
`SinchConversation.Phase`, `SinchPendingMessage.Status`, `SinchChoice` and `SinchMedia`.

```swift
switch message.content {
case .text(let text): show(text)
case .media(let url, _): showAttachment(url)
default: showPlaceholder()              // unsupported, custom, and kinds added later
}
```

Two things to know about `sendChoice(_:)` and `sendLocation`: `sendChoice(_:)` answers `.reply` choices only and does
nothing for the other kinds (URL, call, location are actions for your app); `sendLocation` uses the SDK's default
localization for the title and button label unless you pass `title:` and `label:`.

### SwiftUI

Observe the model directly; nothing else is needed.

```swift
struct ChatScreen: View {
    @State private var conversation: SinchConversation?
    @State private var draft = ""

    var body: some View {
        VStack {
            if let conversation {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        if conversation.hasMoreHistory {
                            Button("Load earlier") { Task { try? await conversation.loadMore() } }
                        }
                        ForEach(conversation.messages, id: \.entryId) { message in
                            if case .text(let text) = message.content { Text(text) }
                        }
                        ForEach(conversation.pending) { item in
                            HStack {
                                Text((item.body as? MessageText)?.text ?? "")
                                if item.status == .failed {
                                    Button("Retry") { Task { _ = try? await conversation.retry(item.tempID) } }
                                }
                            }
                        }
                        if conversation.isAgentTyping { Text("…") }
                    }
                }
                TextField("Message", text: $draft)
                    .onSubmit {
                        let text = draft
                        draft = ""
                        Task { _ = try? await conversation.send(text: text) }
                    }
            }
        }
        .task {
            let conversation = try? SinchChatSDK.shared.chat.makeConversation()
            self.conversation = conversation
            try? await conversation?.start()
        }
        .onDisappear { conversation?.stop() }
    }
}
```

### UIKit

`updates` yields what changed, for diffable data sources. Every access returns a new stream, so several screens can
listen at once. `messages` and `pending` are already up to date when an update arrives.

```swift
final class ChatViewController: UIViewController {
    private let conversation: SinchConversation
    private var updatesTask: Task<Void, Never>?

    init() throws {
        conversation = try SinchChatSDK.shared.chat.makeConversation()
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let updates = conversation.updates   // take the stream before start(), so the first reset is not missed
        updatesTask = Task { [weak self] in
            for await update in updates {
                guard let self else { return }
                switch update {
                case .appended, .pendingAdded:
                    self.applySnapshot(animated: true)
                default: // every other update, and any case a later SDK release adds: rebuild from messages + pending
                    self.applySnapshot(animated: false)
                }
            }
        }
        Task { try? await conversation.start() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            updatesTask?.cancel()   // stop() ends the stream too; cancelling also covers a screen that is simply dropped
            conversation.stop()
        }
    }

    deinit { updatesTask?.cancel() }

    private func applySnapshot(animated: Bool) {
        // Build a diffable snapshot from conversation.messages + conversation.pending.
    }
}
```

### Inbox

```swift
let inbox = try SinchChatSDK.shared.chat.inbox.makeInboxModel()
try await inbox.start()                  // inbox.chats, inbox.isLoading, inbox.hasMore
try await inbox.loadMore()               // next page
try await inbox.refresh()                // first page again

let conversation = try SinchChatSDK.shared.chat.inbox.makeConversation(inboxChat: inbox.chats[0])
inbox.stop()
```

Notes:

- A conversation that is dropped without `stop()` still closes its subscription and channel, but call `stop()`: it
  also releases the "chat is running" flag at a defined time and posts `.didCloseChat`.
- `stop()` ends every open `updates` stream. A message that was still being sent becomes `.failed` in `pending`
  (so it can be retried after a restart); one the server had already accepted leaves the list and comes back with
  the history.
- Foreground and background are app-wide (`UIApplication` notifications), not per scene. With several scenes (iPad
  multi-window), backgrounding one window suspends the models of all windows until the app enters the foreground
  again.
- `send` returns once the server accepted the message. The message stays in `pending` until the server echo
  arrives (or, if it does not within a few seconds, until the send answer is trusted), then it moves to `messages`.
- A conversation asks for the notification permission on send when it is not granted, like the chat screen. Set
  `conversation.requestsPushPermissionOnSend = false` to opt out.
- The headless models do not run plugin message handlers (`customMessageTypeHandlers`), which transform messages
  for the SDK screens.

## Push Notifications

Push is included: `SinchChatSDK.shared.push` is the push facade of `SinchPushSDK`, and
`import SinchChatSDK` already re-exports `SinchPushSDK` (`@_exported`). Existing code
keeps compiling and behaving the same, including the persisted state.

Keep push registration and notification delegate methods in `AppDelegate` or `@UIApplicationDelegateAdaptor`:

```swift
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    SinchChatSDK.shared.push.sendDeviceToken(deviceToken)
}
```

Delivery reports and the foreground push relay are described in [`Documentation/PushRelay.md`](Documentation/PushRelay.md).
The push API itself (relay, in-app alerts, permissions, delivery reports) is documented in
[the SinchPushSDK README](https://github.com/sinchlabs/sinch-push-ios-sdk).

In-app message alerts are rendered by the push SDK now. On the chat SDK they are the same
alerts, configured through `SinchPushSDK.shared.inAppMessages`:

```swift
SinchPushSDK.shared.inAppMessages.isEnabled = true
SinchPushSDK.shared.inAppMessages.theme = .default
SinchPushSDK.shared.inAppMessages.delegate = myInAppHandler   // InAppMessageDelegate
```

### Notification Service Extension (optional, recommended)

Add a Notification Service Extension to report the delivery of **every** visible push to Sinch, also after the user
force-quit the app, and set the App Group in `initialize`. The reports are uploaded with a background `URLSession`, so
they complete even when the extension or the app is suspended or killed. Step-by-step setup, signing notes and
troubleshooting: [`Documentation/NotificationServiceExtension.md`](Documentation/NotificationServiceExtension.md).

The extension uses the **`SinchPushSDKNotificationExtension`** product of the push package
(SPM) or pod (CocoaPods). `SinchChatSDKNotificationExtension` still exists as an SPM
product that only re-exports it, so an existing extension target keeps building without
changes; the pod is `SinchPushSDKNotificationExtension`.

```swift
SinchChatSDK.shared.initialize(SinchInitializeOptions(pushNotificationMode: .prod, appGroup: "group.com.example.app"))

func application(_ application: UIApplication,
                 handleEventsForBackgroundURLSession identifier: String,
                 completionHandler: @escaping () -> Void) {
    _ = SinchChatSDK.shared.push.handleEventsForBackgroundURLSession(identifier: identifier,
                                                                     completionHandler: completionHandler)
}
```

## Migration to 2.0.0

SinchChatSDK 2.0.0 moves push into [SinchPushSDK](https://github.com/sinchlabs/sinch-push-ios-sdk)
and re-exports it. **No source changes are required:** `SinchChatSDK.shared.push`, the
in-app delegate path and every persisted key keep their names, so users stay signed in
and queued reports are kept.

What changes is how the SDK is installed:

- **Swift Package Manager**: only the version. The URL and both product names
  (`SinchChatSDK`, `SinchChatSDKNotificationExtension`) are unchanged.
- **CocoaPods**: 2.0.0 is not on trunk. Add the spec repo, then bump the version
  (see [Installation](#cocoapods)):

  ```ruby
  source 'https://github.com/sinchlabs/sinch-ios-specs.git'
  source 'https://cdn.cocoapods.org/'
  ```

  Keep `use_frameworks!`. The app now installs three pods: `SinchChatSDK` (binary),
  `SinchPushSDK` (source) and `SinchSwiftProtobuf` (dynamic, since 2.1.1);
  `SinchChatSDK` declares them, so the Podfile only needs `pod 'SinchChatSDK'`.
- **Notification Service Extension**: move the extension target from the old
  `SinchChatSDK` extension sub-target to the `SinchPushSDKNotificationExtension` pod
  (CocoaPods) or product (SPM). The API (`SinchPushNotificationExtension.didReceive(_:appGroup:)`)
  is unchanged.

If you only need push and no chat UI, depend on `SinchPushSDK` directly instead; see its
README. The old `SinchChatSDK.shared.push` API keeps working in both cases.

## Migration Notes

- **2.2.0** (iPad, iPhone Duo and headless):
  - `getInboxViewController` now returns an adaptive inbox by default (`layout: .automatic`): sidebar + chat on
    regular width, pushed list on compact width. A pushed inbox hides the host navigation bar while visible.
  - Use `getInboxViewController(layout: .stack)` (or `SinchInboxView(layout: .stack)`) for the previous list-only
    behaviour. In SwiftUI, hide the NavigationStack's bar and pass `onClose:`.
  - `SinchInboxView`'s `UIViewControllerType` is now `UIViewController`. See `Documentation/SinchInbox.md`.
  - The chat screen lays out by size class and window width (centred, capped column on regular width), and its
    action sheets and pickers are anchored popovers on iPad. No code change is needed.
  - New headless API: `makeConversation` / `makeInboxModel`, see [Headless (no UI)](#headless-no-ui).
- **2.1.0** adds `async` forms next to every completion-handler call; nothing was removed or renamed. The new
  forms carry distinct labels or names (`setIdentity(config:identity:)`, `requestNotificationPermission()`), so
  every 2.0.0 spelling keeps resolving to the same function — including a `setIdentity(with:identity:)` call with
  no completion handler written inside an `async` function.
- Existing UIKit integrations should continue using `getChatViewController` and `getInboxViewController`.
- SwiftUI apps should prefer `SinchChatView`, `SinchInboxView`, and `SinchChatSDKState` for first-stage support.
- A future SDK release may provide native SwiftUI chat/inbox views; the current SwiftUI API wraps UIKit internally.

## Security

### Identity signing

Prefer the new `selfSignedWithAppSecret` identity so the SDK computes the
HMAC-SHA512 digest internally — your app secret never has to leave the
caller and is not persisted:

```swift
try await SinchChatSDK.shared.setIdentity(
    config: config,
    identity: .selfSignedWithAppSecret(
        userId: userID,
        appSecret: appSecret
    )
)
```

`selfSigned(userId:secret:)` is still supported for backwards compatibility
but requires you to pre-compute the digest with the now-deprecated
`String.hmac(algorithm: .SHA512, key:)` helper.

### Token storage

Access tokens are stored in the iOS Keychain
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), scoped per SDK
configuration. On first contact with the SDK, any token previously stored in
`UserDefaults` is migrated automatically and the legacy key is removed.

### Production note

Do not embed your application secret in production code. The same warning
applies to the Sinch RTC JWT helpers in `SinchVideoRTCPluginSDK` — sign JWTs
on your backend and ship the resulting token to the client.
