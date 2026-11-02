# Changelog

SDK changes that affect host developers. The newest section is synced to the public mirror
([sinch-chat-ios-sdk](https://github.com/sinchlabs/sinch-chat-ios-sdk)) at release time.

## 2.1.0

A Swift-concurrency surface for chat, and it is **purely additive**: every existing declaration, signature and
verification path is unchanged, and each new call bridges the completion-handler API it shipped with. Both forms
call the same code, so a call site can migrate one call at a time.

### Added

- **`SinchChatSDK.setIdentity(config:identity:) async throws(SinchSDKIdentityError)`** — awaits the completion form,
  including its chat side effects (the token provider, the chat channel of the identity's region, the
  `didSetIdentity` plugin event and a fresh chat session). Typed throws, so `catch` receives a
  `SinchSDKIdentityError`. The `config:` label differs from the completion form's `with:` so the two can never
  be confused at a call site.
- **`SinchChatSDK.removeIdentity() async throws`** — awaits the completion form and its `didRemoveIdentity` event.
- **`SinchInbox.getInboxChats(options:) async -> [InboxChat]`** — awaits the completion form. As there, a failure is
  reported as an empty array.
- **`SinchPluginAvailablePluginMethods.sendMessage(_:authModel:chatOptions:) async throws -> String`** and
  **`presentViewController(_:_:) async`** — the async forms of the methods a chat plugin receives.
- **`SinchChatSDK.events: AsyncStream<SinchPluginEvent>`** and
  **`SinchInbox.events: AsyncStream<SinchInboxEvent>`** — the public `eventListenerSubject` and
  `chatInboxEventListenerSubject` as async sequences. Each access subscribes afresh (nothing is replayed), buffers up
  to 64 events, and cancels its subscription when the consumer stops iterating — on `break`, on task cancellation or
  when the stream is released.
- **Conformances**: `SinchInboxEvent` and `SinchChatOptions` are now `Sendable`, and `SinchPluginEvent` is
  `@unchecked Sendable` (its only non-`Sendable` payload is `any ChatViewProtocol`, a main-actor-isolated
  `UIViewController`). Both are additive; existing conformers and switches are unaffected.

### Changed

- **Version**: `SinchChatSDK.version` reports `2.1.0`; the podspec is `2.1.0`. The `SinchPushSDK` dependency stays
  `~> 1.0`.

### Notes

- Every async form is named or labelled apart from the completion form it bridges, so no 2.0.0 spelling changes
  meaning: a completion-less `SinchChatSDK.shared.setIdentity(with:identity:)` inside an `async` function still
  resolves to the completion form (the async one is `setIdentity(config:identity:)`), and `removeIdentity(nil)`
  still selects the completion form (`removeIdentity() async` is the only call with no argument).
- The push SDK's async APIs are reachable through `SinchChatSDK.shared.push`:
  `requestNotificationPermission()`, `notificationPermissionStatus()`, `socketStates`, `socketMessages`, and
  `SinchPushSDK.shared.inAppMessages.events`.
- The completion handlers are guarded against a second invocation: a doubled completion is ignored instead of
  trapping the process on a checked continuation.

## 2.0.0

Push moves into [SinchPushSDK](https://github.com/sinchlabs/sinch-push-ios-sdk), a
standalone iOS 16 package with no chat in it. SinchChatSDK depends on it and re-exports
it, so **existing source keeps compiling and behaves the same**.

### Changed

- **Dependency graph**: `SinchChatSDK` now depends on the `SinchPushSDK` package
  (`from: "1.0.0"`) instead of containing the push code. `import SinchChatSDK` re-exports
  it (`@_exported import SinchPushSDK`), and `SinchChatSDK.shared.push` forwards to
  `SinchPushSDK.shared.push`.
- **Notification Service Extension product**: the implementation moved to
  `SinchPushSDKNotificationExtension`. The `SinchChatSDKNotificationExtension` SPM product
  still exists and only re-exports it, so an existing extension target keeps building.
  On CocoaPods the extension pod is `SinchPushSDKNotificationExtension`.
- **CocoaPods**: 2.0.0 is published in our own spec repo
  (`https://github.com/sinchlabs/sinch-ios-specs`) and is no longer on trunk. The pod
  stays a binary `SinchChatSDK.xcframework`, but it now links `SinchPushSDK` and
  `SwiftProtobuf` **dynamically**: the app, the push pod and the chat binary share one
  protobuf runtime, which fixes the missing-framework launch failure of the 1.1.0 binary.
  Integrators add two `source` lines and one `post_install` hook; no code changes.
  gRPC Swift 2 and Kingfisher stay linked statically inside the binary.
- **iOS version**: chat stays on iOS 18. Push itself (and SinchPushSDK standalone) is
  iOS 16.
- **In-app message alerts** are rendered by SinchPushSDK now. Integrators who customise
  them configure `SinchPushSDK.shared.inAppMessages` (delegate, theme, `isEnabled`);
  the alert content, layouts and the notification handling order are unchanged.

### Fixed

- The prebuilt 1.1.0 binary linked `SwiftProtobuf` statically and depended on a
  `SwiftProtobuf_<hash>_PackageProduct.framework` that it did not ship, so an app could
  fail at launch with `Library not loaded`. The 2.0.0 binary links the runtime the app
  installs.

Push relay: foreground push delivery over a WebSocket, with APNs for background and terminated apps.
Full documentation: [`Documentation/PushRelay.md`](Documentation/PushRelay.md).

### Added

- **Push relay** — a WebSocket to the Sinch push relay that is open only while the app is in the foreground. Messages
  arrive immediately instead of waiting for APNs. When the app is backgrounded or terminated the socket closes and
  pushes arrive through APNs as before; no background modes or entitlements change. Nothing is delivered twice: a
  message that arrived through one channel is not shown again by the other.
- **`SinchPush` relay API**:
  - `socketState: SinchPushSocketState` — current state of the socket (`status`, `relayEnabled`, `disabledReason`,
    `lastError`, `reconnectAttempts`).
  - `socketStatePublisher: AnyPublisher<SinchPushSocketState, Never>` — every state change, on the main thread,
    replaying the current value to new subscribers.
  - `socketMessagePublisher: AnyPublisher<SinchPushSocketMessage, Never>` — every relay message once, on the main
    thread, without replay. A notification is posted for each message as well; see
    [`Documentation/PushRelay.md`](Documentation/PushRelay.md) for how your notification delegate decides whether it is
    shown in the foreground.
  - `reportStatus(messageId:status:)` — report what happened to a relay notification (`.displayed`, `.dismissed`). The
    report is queued and sent when the relay connects, so it is safe to call from the background. The SDK itself
    reports DELIVERED on receipt and DISPLAYED when it posts a notification.
  - `installationId: String?` — this installation's id as the relay and the push API know it. `nil` when it cannot be
    read or stored (e.g. the Keychain is unavailable before the first unlock).
  - `setRelayEnabled(_:)` — turn the relay on or off at runtime, with immediate effect. Persisted across launches and
    on by default.
  - `isRelayEnabled: Bool` — the runtime switch itself. Whether a socket actually runs is `socketState`, not this
    value.
- **Notification Service Extension (optional, recommended)** — new SPM library product
  `SinchChatSDKNotificationExtension` for a Notification Service Extension target (Foundation and UserNotifications
  only; add it to the extension target, not `SinchChatSDK`). `SinchPushNotificationExtension.didReceive(_:appGroup:)`
  reports a DELIVERED event for a Sinch push from the extension, which runs for every visible push with
  `mutable-content: 1`, also after a force-quit, and returns at once: the report is a gRPC-web `ReportEvents` call
  handed to a background `URLSession`. Returns `false` for a non-Sinch push and when no shared session exists. Each upload uses a background session of its own, released once started. The app does not report a delivery the extension already reported (shared sent-markers, the last 1000 or 7 days). Needs
  the App Groups capability on the app and the extension. See
  [`Documentation/NotificationServiceExtension.md`](Documentation/NotificationServiceExtension.md).
- **`SinchInitializeOptions.appGroup`** (`String?`, default `nil`) — the App Group shared with the extension. When set,
  the SDK mirrors a minimal record (access token, push API URL, user id, app id; never the identity secret) into the
  group's container, as a file protected until the first unlock, after every `setIdentity` and token refresh, and
  deletes it on `removeIdentity`. `SinchInitializeOptions.init` takes the new parameter last.
- **`SinchPush.handleEventsForBackgroundURLSession(identifier:completionHandler:)`** — forward
  `application(_:handleEventsForBackgroundURLSession:completionHandler:)`. Returns `false` when the session is not the
  SDK's (`com.sinch.chatsdk.reports`, `com.sinch.chatsdk.reports.nse`). Default implementation for existing `SinchPush`
  conformers returns `false`.
- **New public types**: `SinchPushSocketState`, `SinchPushSocketStatus`, `SinchPushSocketMessage`,
  `SinchPushMessageStatus`.
- **Configuration**: `SinchSDKConfig.AppConfig` takes `relay: .enabled / .disabled` (a kill switch, default
  `.enabled`) and `allowInsecureRelay: Bool` (default `false`; only needed for a plaintext `ws://` relay URL in local
  development). `wss://` is always accepted. Configs encoded before these options existed decode with `.enabled` and
  `false`.
- **`Region.custom(host:pushAPIHost:port:isSecure:relayURL:)`** — the relay WebSocket URL of the environment
  (`relayURL: URL? = nil`). Without one the relay URL is derived from the region (see below); an explicit URL always
  wins. Persisted regions encoded before the option existed still decode.
- **Relay availability**: the relay URL is derived from the region, so an integrator never has to pass one:
  - `.EU1` → `wss://relay.sinch-push.prod.sinch.com/ws` (mirrors the push host `grpc.sinch-push.prod.sinch.com`);
  - `.US1` → `wss://relay.sinch-push.us1.prod.sinch.com/ws` (mirrors the push host `grpc.sinch-push.us1.prod.sinch.com`);
  - `.custom` without a `relayURL` → the staging relay (`wss://relay.sinch-push.eu1tst.staging.sinch.com/ws`) for the
    staging push hosts (`grpc.sinch-push.staging.sinch.com`, `grpc.sinch-push.eu1tst.staging.sinch.com`), the EU
    relay for `grpc.sinch-push.prod.sinch.com`, the US relay for `grpc.sinch-push.us1.prod.sinch.com`; any other
    push host leaves the relay disabled for that region.

  The production relay hosts have to exist in DNS before `.EU1` / `.US1` can connect; until then the relay cannot be
  reached and everything works over APNs as before.

### Changed

- **APNs deliveries are reported from a background wake** — new `SinchPush.handleBackgroundNotification(_:) async`: it handles the
  payload like the synchronous method, then hands the delivery reports to a background `URLSession` upload and returns
  quickly; the system completes the upload even if the app is suspended (the reports are marked in flight in the
  outbox, not resent by the normal flush until the upload fails or 10 minutes pass, and removed on success; a lost
  answer causes at most a harmless duplicate, as the server keeps the first terminal status). An expired access token
  is refreshed before the hand-off, and a flush that is running is waited for. When the upload cannot be started it
  falls back to one bounded gRPC attempt (the whole call takes at most 20 seconds in total, nothing left
  scheduled for the suspended app; in the foreground it is the normal flush with its backoff). The synchronous `handleNotification(_:)` is unchanged. Call the async one from
  `didReceiveRemoteNotification` and finish the fetch completion handler after it returns. A background cold launch
  reports too: the SDK stores the `AppConfig` of the last successful `setIdentity` (cleared by `removeIdentity`, also
  when its unsubscribe fails) and uses the token from the Keychain; `initialize` (call it early in
  `didFinishLaunching`) restores only the delivery reports, not the chat, and only for a launch in the background;
  the async handler restores a missing session itself. `initialize`, each return to the foreground and a failed extension upload the app learns of also queue the
  deliveries the Notification Service Extension could not upload. Nothing is reported before the first unlock
  after a restart. The default implementation for existing `SinchPush` conformers reports nothing. No extension or App Group is needed (both are optional).
- **Subscribe sends device information** — the push API Subscribe now carries the installation id, platform, OS
  version, SDK version and bundle id, plus `background_service`: `UNSUPPORTED` (1) while the relay may run (relay
  while connected, push provider otherwise) and `RELAY_DISABLED` (5) when the SDK is configured to run no relay
  socket (`relay: .disabled`, `setRelayEnabled(false)`, or a region without a relay URL), which routes pushes through
  the push provider only. The device fields are all-or-nothing: while the installation id cannot be read, the Subscribe
  goes out without them and the next Subscribe that can read it sends them.
- **Cross-channel deduplication** — `handleWillPresentNotification` and `handleNotification` deduplicate a message
  that the relay socket already delivered (its APNs copy is not presented and not handled again) and mark a message
  seen through APNs, so the socket's later copy is dropped. Whichever channel delivers a message first wins; a tap on
  a notification always opens the chat. iOS may call `willPresent` and `didReceiveRemoteNotification` in either order
  for one push — forward both to the SDK and do not rely on an order.

### Breaking

- **`Region.custom` gained a fifth associated value** `relayURL: URL? = nil`. Construction stays source-compatible
  (the new element has a default), but an exhaustive `switch` or a pattern match on
  `.custom(let host, let pushAPIHost, let port, let isSecure)` must add the fifth element — that is a **source
  break**. Codable data stays compatible in both directions.
- **ABI break in the prebuilt xcframework**: the `Region` enum changed shape, and the `SinchPush` protocol gained 7
  requirements (5 properties — `socketState`, `socketStatePublisher`, `socketMessagePublisher`, `installationId`,
  `isRelayEnabled` — and 2 methods — `reportStatus(messageId:status:)`, `setRelayEnabled(_:)`). Default
  implementations are provided in a `public extension SinchPush` (`isRelayEnabled` returns `true`, the toggle's
  default; `socketState` reports "no relay" — idle, `relayEnabled == false` — and the rest is no messages, a no-op
  report, `nil`), so existing host conformers — a test mock, for example —
  keep compiling. Apps that link the xcframework must rebuild against the new binary; nothing changes for apps built
  from source or through the Swift Package Manager.
- **Versioning**: the next release must be a new minor version at least (`1.2.0`), and a major one (`2.0.0`) if the
  project follows strict semver for source-breaking changes.

### Packaging

`SinchChatSDK.podspec` ships the prebuilt xcframework (`s.source` is a release `.zip` of `SinchChatSDK.xcframework`,
`vendored_frameworks`) and has no `source_files` glob, so the new `PushRelay/` and `PushSocket/` sources are picked up
automatically when `DevApp/scripts/build_xcframework.sh` builds the whole `SinchChatSDK` scheme — no packaging change
was needed.
