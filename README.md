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
repo, not on trunk. Add both sources:

```ruby
source 'https://github.com/sinchlabs/sinch-ios-specs.git'
source 'https://cdn.cocoapods.org/'   # SwiftProtobuf, and SinchPushSDK's dependency

platform :ios, '18.0'
use_frameworks!

target 'App' do
  pod 'SinchChatSDK'   # brings SinchPushSDK, the source push pod, with it
end

target 'NotificationService' do
  # The NSE target takes the extension pod only, never SinchChatSDK or SinchPushSDK.
  pod 'SinchPushSDKNotificationExtension'
end

# Trunk's SwiftProtobuf declares iOS 11.0 and Xcode refuses deployment targets below
# 15.0. The prebuilt chat binary links SinchPushSDK and SwiftProtobuf dynamically, so
# both must be built with library evolution as well.
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      deployment_target = (config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '0').to_f
      if deployment_target > 0 && deployment_target < 15.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      end
      if %w[SwiftProtobuf SinchPushSDK SinchPushSDKNotificationExtension].include?(target.name)
        config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
      end
    end
  end
end
```

The binary links gRPC Swift 2 and Kingfisher statically inside the framework. It links
`SinchPushSDK` and `SwiftProtobuf` dynamically, so the app ships exactly one protobuf
runtime and the chat SDK, the push pod and the app all share it.

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
- **CocoaPods**: 2.0.0 is not on trunk. Add the spec repo and the `post_install` hook,
  then bump the version (see [Installation](#cocoapods)):

  ```ruby
  source 'https://github.com/sinchlabs/sinch-ios-specs.git'
  source 'https://cdn.cocoapods.org/'
  ```

  Keep `use_frameworks!`. The app now installs three pods: `SinchChatSDK` (binary),
  `SinchPushSDK` (source) and `SwiftProtobuf` (dynamic); `SinchChatSDK` declares them,
  so the Podfile only needs `pod 'SinchChatSDK'`.
- **Notification Service Extension**: move the extension target from the old
  `SinchChatSDK` extension sub-target to the `SinchPushSDKNotificationExtension` pod
  (CocoaPods) or product (SPM). The API (`SinchPushNotificationExtension.didReceive(_:appGroup:)`)
  is unchanged.

If you only need push and no chat UI, depend on `SinchPushSDK` directly instead; see its
README. The old `SinchChatSDK.shared.push` API keeps working in both cases.

## Migration Notes

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
