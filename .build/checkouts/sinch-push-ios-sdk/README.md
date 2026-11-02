# SinchPushSDK

The Sinch push SDK for iOS. It gives an app an identity and an access token, APNs
subscriptions, the foreground push relay, delivery reports and in-app message alerts.
It is a standalone package: it does not contain chat, and it does not depend on a chat
SDK.

The Notification Service Extension is a product of its own,
`SinchPushSDKNotificationExtension`, which is Foundation and UserNotifications only.

- [Requirements](#requirements)
- [Installation](#installation)
  - [Swift Package Manager](#swift-package-manager)
  - [CocoaPods](#cocoapods)
- [Quick start](#quick-start)
- [Permissions](#permissions)
- [Notification Service Extension and App Group](#notification-service-extension-and-app-group)
- [Push relay](#push-relay)
- [In-app message alerts](#in-app-message-alerts)
- [Coming from `SinchChatSDK.shared.push`](#coming-from-sinchchatsdksharedpush)
- [Documentation](#documentation)

## Requirements

- iOS 16.0 or later
- Swift 6 (the package uses `swift-tools-version:6.1`, so Xcode 16.3 or later)
- one dependency: [apple/swift-protobuf](https://github.com/apple/swift-protobuf)
- no gRPC runtime and no NIO: the transport is gRPC-web over `URLSession`

## Installation

### Swift Package Manager

Add the package to your app:

```
https://github.com/sinchlabs/sinch-push-ios-sdk.git
```

| Product | Target |
| --- | --- |
| `SinchPushSDK` | the app |
| `SinchPushSDKNotificationExtension` | the Notification Service Extension only |

The app target needs `SinchPushSDK`. In Xcode: *File ▸ Add Package Dependencies…*,
paste the URL, then select the product for the target.

### CocoaPods

The pods live in our own spec repo, not on trunk. Add both sources:

```ruby
source 'https://github.com/sinchlabs/sinch-ios-specs.git'
source 'https://cdn.cocoapods.org/'   # SwiftProtobuf

platform :ios, '16.0'
use_frameworks!

target 'App' do
  pod 'SinchPushSDK'
end

target 'NotificationService' do
  # The extension target takes this pod only. Never SinchPushSDK itself.
  pod 'SinchPushSDKNotificationExtension'
end

# Trunk's SwiftProtobuf declares iOS 11.0 and Xcode refuses deployment targets below
# 15.0, so the pods need their deployment target raised. SinchPushSDK is built with
# library evolution because SinchChatSDK (when used) is a prebuilt binary compiled
# against a resilient push module.
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

`SinchPushSDK` brings `SinchPushSDKNotificationExtension` as a dependency at the same
version, and the in-app assets and strings in a `SinchPushSDK.bundle` resource bundle
that the SDK looks up at runtime.

If you also use `SinchChatSDK` (2.0.0 or later), do not add `SwiftProtobuf` to the
Podfile yourself: the chat pod depends on it, and the prebuilt chat binary links the
same dynamic `SwiftProtobuf.framework` that the app ships. The hook above is required
for both SDKs.

## Quick start

Import `SinchPushSDK` and wire the app delegate. `initialize` registers for remote
notifications and restores the delivery-report session; `setIdentity` issues the access
token and subscribes the device.

```swift
import UIKit
import UserNotifications
import SinchPushSDK

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        SinchPushSDK.shared.initialize(
            config: .init(clientID: "your-client-id",
                          projectID: "your-project-id",
                          configID: "your-config-id",
                          region: .EU1),
            options: .init(environment: .prod,                    // .sandbox in development
                           appGroup: "group.com.example.app"))    // see the extension below

        SinchPushSDK.shared.setIdentity(.anonymous) { result in
            switch result {
            case .success:
                break // the device token, if known already, is subscribed now
            case .failure(let error):
                print("setIdentity failed: \(error)")
            }
        }
        return true
    }

    // MARK: - APNs

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        SinchPushSDK.shared.push.sendDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Reports the delivery of a background wake too, then returns.
        Task {
            let isHandled = await SinchPushSDK.shared.push.handleBackgroundNotification(userInfo)
            completionHandler(isHandled ? .newData : .noData)
        }
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        if SinchPushSDK.shared.push.handleEventsForBackgroundURLSession(identifier: identifier,
                                                                        completionHandler: completionHandler) {
            return // the SDK keeps the handler and calls it when the upload is done
        }
        // not the SDK's session: handle it yourself
    }

    // MARK: - Foreground presentation and taps

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // nil when the notification is not a Sinch one: decide yourself then.
        SinchPushSDK.shared.push.handleWillPresentNotification(notification) ?? [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        _ = SinchPushSDK.shared.push.handleNotificationResponse(response)
    }
}
```

Notes:

- `initialize(config:options:)` may also be called without a config; `setIdentity(with:identity:completion:)`
  then carries it. Passing it here makes the locale and the relay settings ready before the first identity.
- `.off` as the environment registers for no remote notifications and subscribes no device.
- For a signed user call `setIdentity(.selfSignedWithAppSecret(userId:appSecret:))`; the SDK computes the
  HMAC-SHA512 digest itself and never persists the secret. `selfSigned(userId:secret:)` with a precomputed
  digest is still accepted.
- `removeIdentity(_:)` unsubscribes the device, deletes the token and stops the relay.
- Reading `SinchPushSDK.shared.push` the first time creates the push pipeline; it is safe from any app
  delegate callback.

`push` also exposes:

| API | What it does |
| --- | --- |
| `handleNotification(_:)` | synchronous handling of an APNs payload; returns whether it belongs to Sinch |
| `handleBackgroundNotification(_:) async` | the same, then reports the delivery with a background `URLSession` |
| `handleWillPresentNotification(_:)` | presentation options for a foreground notification, `nil` when it is not Sinch |
| `handleNotificationResponse(_:)` | handles a tap or a dismissal |
| `handleEventsForBackgroundURLSession(identifier:completionHandler:)` | takes over the SDK's background upload sessions |
| `sendDeviceToken(_:)` | subscribes this device to the current identity |

## Permissions

```swift
SinchPushSDK.shared.push.askNotificationPermission { status in
    switch status {
    case .granted:       break
    case .denied:        break // the user has to change it in Settings
    case .notDetermined: break
    }
}

SinchPushSDK.shared.push.checkPushPermission { status in
    // the current state, without asking
}
```

Combine variants are available: `askNotificationPermission()` and `checkPushPermission()`
return `AnyPublisher<SinchSDKNotificationStatus, Never>`.

## Notification Service Extension and App Group

The extension reports the delivery of every visible push, including after the user
force-quit the app. It is optional but recommended.

1. Add a Notification Service Extension target.
2. Add the `SinchPushSDKNotificationExtension` product (SPM) or pod (CocoaPods) to the
   extension target only.
3. Add the **App Groups** capability to the app and to the extension with the same
   group, and pass it to `initialize` as `options.appGroup`.
4. Call the SDK first thing in `didReceive`:

```swift
import UserNotifications
import SinchPushSDKNotificationExtension

final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        SinchPushNotificationExtension.didReceive(request, appGroup: "group.com.example.app")
        contentHandler(request.content)
    }
}
```

The app must also forward `handleEventsForBackgroundURLSession` (see above) so the SDK
learns the result of the upload. Step-by-step setup, signing, memory limits and
troubleshooting: [`Documentation/NotificationServiceExtension.md`](Documentation/NotificationServiceExtension.md).

## Push relay

The relay is a WebSocket to the Sinch push relay, open only while the app is in the
foreground. Messages arrive immediately instead of waiting for APNs; in the background
and after termination pushes arrive through APNs. Nothing is delivered twice.

```swift
let push = SinchPushSDK.shared.push

push.socketState                 // status, relayEnabled, disabledReason, lastError, reconnectAttempts
push.socketStatePublisher        // every change, on the main thread, replays the current value
push.socketMessagePublisher      // every relay message once, on the main thread
push.installationId              // this installation's id, nil while the Keychain is locked

push.setRelayEnabled(false)      // persisted runtime switch; the identity and subscription stay
push.isRelayEnabled
push.reportStatus(messageId: message.id, status: .displayed)   // or .dismissed
```

The relay starts after `setIdentity` succeeds when the region has a relay URL, and
stops on `removeIdentity`. Relay messages are posted as local notifications, so the
`UNUserNotificationCenter` delegate forwarding above is required. Full details:
[`Documentation/PushRelay.md`](Documentation/PushRelay.md).

## In-app message alerts

The SDK renders in-app messages itself: it parses the payload of an APNs notification
or of a relay message (`owner` = `sinch`, `protobufPayload` = base64 `AppMessage`) and
presents the alert over the current view controller. Text, media, location, choices,
card and carousel layouts are supported.

```swift
// Turn the built-in rendering off; the SDK then posts a system notification instead.
SinchPushSDK.shared.inAppMessages.isEnabled = true

// Colours, fonts, images and strings. Start from `.default` and override what you need.
var theme = InAppMessageTheme.default
theme.cornerRadius = 16
theme.buttonBackgroundColor = .systemBlue
theme.buttonTitleColor = .white
SinchPushSDK.shared.inAppMessages.theme = theme
```

`InAppMessageDelegate` observes the alerts and can take rendering over:

```swift
import SinchPushSDK

@MainActor
final class InAppHandler: InAppMessageDelegate {

    // Return false to render the alert yourself; the SDK then shows nothing.
    func shouldPresent(_ message: InAppMessage) -> Bool { true }

    // The SDK opens url / tel: / Maps itself and still reports the tap here.
    // `.text(postbackData:)` has no built-in behaviour: send it to your backend.
    func didTapAction(_ action: InAppChoiceAction, in message: InAppMessage) {
        if case .text(let postbackData) = action {
            sendPostback(postbackData)
        }
    }

    func didDismiss(_ message: InAppMessage) {}
}

SinchPushSDK.shared.inAppMessages.delegate = InAppHandler()
```

`InAppMessages.queue` lists the alerts waiting to be shown, and
`present(_:)` queues one manually. The SDK renders on the main actor: set the delegate
and the theme from the main thread.

## Coming from `SinchChatSDK.shared.push`

`SinchChatSDK` 2.0.0 depends on SinchPushSDK and re-exports it, so nothing breaks if
you keep using `SinchChatSDK.shared.push`. To use push without chat:

| Before | After |
| --- | --- |
| `import SinchChatSDK` | `import SinchPushSDK` |
| `SinchChatSDK.shared.initialize(SinchInitializeOptions(pushNotificationMode: .prod, appGroup: …))` | `SinchPushSDK.shared.initialize(config: …, options: SinchPushInitializeOptions(environment: .prod, appGroup: …))` |
| `SinchChatSDK.shared.setIdentity(with:identity:)` | `SinchPushSDK.shared.setIdentity(with:identity:)` |
| `SinchChatSDK.shared.push.…` | `SinchPushSDK.shared.push.…` |
| in-app settings on the chat SDK | `SinchPushSDK.shared.inAppMessages` |

The notification handling order is unchanged (dedupe, in-app, addressee) and the
persisted state (Keychain accounts, `UserDefaults` keys, App Group directory and
background session identifiers) keeps the `com.sinch.chatsdk` names on purpose, so
moving from chat to push does not log anybody out or lose queued reports.

## Documentation

- [`Documentation/NotificationServiceExtension.md`](Documentation/NotificationServiceExtension.md)
- [`Documentation/PushRelay.md`](Documentation/PushRelay.md)
- [`CHANGELOG.md`](CHANGELOG.md)
