# Changelog

Changes that affect host developers. Pushed to the public repository
([sinch-push-ios-sdk](https://github.com/sinchlabs/sinch-push-ios-sdk)) at release time.

## 1.0.0

The first release of SinchPushSDK as a standalone package, extracted from SinchChatSDK.
It keeps the push API and the persisted state of the chat SDK, so an existing
integration can switch imports without logging users out or re-subscribing devices.

### Added

- **`SinchPushSDK` product.** Identity and access token, APNs subscriptions, delivery
  reports, the foreground push relay and in-app message alerts, without chat.
  `SinchPushSDK.shared.initialize(config:options:)`, `setIdentity`, `removeIdentity`.
- **iOS 16 and Swift 6.** The push and extension code no longer needs iOS 18: it uses
  `OSAllocatedUnfairLock`, `ContinuousClock` and `Duration`, all available on iOS 16.
  `isolated deinit` is used only on `@MainActor` types.
- **One dependency: SwiftProtobuf.** The transport is gRPC-web over `URLSession`; there
  is no gRPC runtime and no NIO. Token RPCs go to `grpc-web.sinch-chat.*`, push RPCs to
  the sinch-push host.
- **`SinchPushSDKNotificationExtension` product.** A separate module (and a separate
  CocoaPods pod) for a Notification Service Extension: Foundation and UserNotifications
  only, so the extension stays inside the iOS memory limit.
  `SinchPushNotificationExtension.didReceive(_:appGroup:)` reports a delivery from the
  extension, also after a force-quit.
- **In-app message alerts** — the SDK parses the APNs and relay payloads and renders
  text, media, location, choices, card and carousel alerts. Public API:
  - `SinchPushSDK.shared.inAppMessages` — `delegate`, `theme`, `isEnabled`, `queue`,
    `present(_:)`;
  - `InAppMessageDelegate` — `shouldPresent(_:)`, `didTapAction(_:in:)`,
    `didDismiss(_:)`; return `false` from `shouldPresent` to render yourself;
  - `InAppMessageTheme.default` — colours, fonts, images and strings, with the bundled
    `SinchPushSDK` resource bundle.
- **Push relay** (`Documentation/PushRelay.md`): a WebSocket open only in the foreground,
  with APNs as the fallback. `socketState`, `socketStatePublisher`,
  `socketMessagePublisher`, `reportStatus(messageId:status:)`, `installationId`,
  `setRelayEnabled(_:)`, `isRelayEnabled`. A message is never shown twice: the relay and
  APNs share the dedupe registry.
- **Delivery reports.** DELIVERED for APNs deliveries, uploaded with background
  `URLSession`s (for the app and for the extension) so they survive suspension and
  termination. APNs deliveries are reported from a background wake with
  `handleBackgroundNotification(_:)`; the extension reports visible pushes.
- **Handling API**: `sendDeviceToken(_:)`, `handleNotification(_:)`,
  `handleBackgroundNotification(_:)`, `handleWillPresentNotification(_:)`,
  `handleNotificationResponse(_:)`,
  `handleEventsForBackgroundURLSession(identifier:completionHandler:)`,
  `askNotificationPermission`, `checkPushPermission`.
- **CocoaPods**: `SinchPushSDK` and `SinchPushSDKNotificationExtension` source pods in
  `github.com/sinchlabs/sinch-ios-specs` (never trunk). The app needs
  `use_frameworks!` and one `post_install` hook that raises deployment targets below
  15.0 to 16.0 and sets `BUILD_LIBRARY_FOR_DISTRIBUTION` for SwiftProtobuf and both
  pods.

### Compatibility

- The persisted state keeps the chat SDK's names on purpose: Keychain accounts
  (`com.sinch.chatsdk.auth`, `com.sinch.push`), `UserDefaults` keys
  (`sinch_device_token`, `com.sinch.push.*`, `com.sinch.chatsdk.reports.*`), the App
  Group directory (`Library/Application Support/com.sinch.chatsdk/`) and the background
  session identifiers (`com.sinch.chatsdk.reports`, `.nse`).
- `SinchChatSDK` 2.0.0 depends on this package and re-exports it, so
  `SinchChatSDK.shared.push` keeps working.
