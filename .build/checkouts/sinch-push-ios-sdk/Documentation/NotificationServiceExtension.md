# Notification Service Extension (optional, recommended)

A Notification Service Extension (NSE) lets the Sinch Push SDK report the **delivery** of every visible push to Sinch,
including pushes that never wake your app.

- [Why](#why)
- [Prerequisites](#prerequisites)
- [Set it up in Xcode](#set-it-up-in-xcode)
- [App side](#app-side)
- [Signing and provisioning](#signing-and-provisioning)
- [How it works](#how-it-works)
- [Background URLSession](#background-urlsession)
- [Memory and time limits](#memory-and-time-limits)
- [Verify it](#verify-it)
- [Troubleshooting](#troubleshooting)

## Why

Without an extension the SDK reports a delivery when your app gets to run: a `content-available` push that wakes it (see
[`handleBackgroundNotification`](PushRelay.md#reporting-apns-deliveries-from-a-background-wake)), or the next time the app
opens. iOS wakes the app for a silent push only now and then, and never when the user force-quit it. A visible push that
the user never taps is then not reported at all.

An extension with `mutable-content: 1` runs for **every visible push, also after a force-quit**, before the notification
is shown. The SDK uses that moment to hand a `DELIVERED` report to a background `URLSession`, which uploads it even if
the extension is suspended or killed a second later.

The extension is optional. Without it everything still works, and deliveries are reported as described in
[PushRelay.md](PushRelay.md). Adding it only closes the gap above.

## Prerequisites

- **Push Notifications** capability on the app (already needed for push).
- **App Groups** capability on **both** the app and the extension, with the same group id, for example
  `group.com.example.app`. The app and the extension share data through it.
- The server sends `mutable-content: 1` in the `aps` dictionary. sinch-push sets it on visible pushes; nothing to do in
  your backend if you use sinch-push. Without it iOS does not start the extension.
- iOS 16 or later (the SDK's minimum).

## Set it up in Xcode

1. **File ▸ New ▸ Target… ▸ Notification Service Extension.** Name it `NotificationService`, language Swift. When Xcode
   asks, do not activate the new scheme. The bundle identifier must start with the app's:
   `<app bundle id>.NotificationService`, for example `com.example.app.NotificationService`.
2. **Add the SDK product to the extension target only.** Select the extension target ▸ *General* ▸ *Frameworks and
   Libraries* ▸ **+** ▸ choose `SinchPushSDKNotificationExtension` from the SinchPushSDK package. With CocoaPods,
   add `pod 'SinchPushSDKNotificationExtension'` to the extension target in the Podfile instead. It has no
   dependencies other than Foundation and UserNotifications (no UIKit, no SwiftProtobuf), which keeps the
   extension small. Do **not** add `SinchPushSDK` itself to the extension: it is large and the extension's memory limit
   is low. The app target keeps `SinchPushSDK`, which already contains the shared code.
3. **Add the App Groups capability** to the extension target (*Signing & Capabilities* ▸ **+ Capability** ▸ *App
   Groups*) and tick the same group as the app. This adds `NotificationService.entitlements`:

   ```xml
   <key>com.apple.security.application-groups</key>
   <array>
       <string>group.com.example.app</string>
   </array>
   ```

4. **Replace `NotificationService.swift`** with:

   ```swift
   import UserNotifications
   import SinchPushSDKNotificationExtension

   final class NotificationService: UNNotificationServiceExtension {
       private var contentHandler: ((UNNotificationContent) -> Void)?
       private var bestAttemptContent: UNMutableNotificationContent?

       override func didReceive(_ request: UNNotificationRequest,
                                withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
           self.contentHandler = contentHandler
           bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

           // First thing: queue the DELIVERED report. Returns quickly; the upload runs in a background URLSession.
           SinchPushNotificationExtension.didReceive(request, appGroup: "group.com.example.app")

           // Then hand the notification over. Modify the content here if you need to.
           contentHandler(bestAttemptContent ?? request.content)
       }

       override func serviceExtensionTimeWillExpire() {
           // Called just before the extension is killed. Deliver what you have.
           if let contentHandler, let bestAttemptContent {
               contentHandler(bestAttemptContent)
           }
       }
   }
   ```

   `didReceive(_:appGroup:)` returns `false` for a push that is not from Sinch and when the app has not shared a
   session yet (see below). Ignore the result unless you want to log it: your own pushes pass through unchanged.

   Call it **before** any slow work of your own (image downloads and the like). The extension has about 30 seconds in
   total, and the report does not depend on how long you take afterwards.

5. **Check the extension's `Info.plist`.** Xcode generates `NSExtension ▸ NSExtensionPointIdentifier =
   com.apple.usernotifications.service` and `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).NotificationService`.
   Leave both.

6. **Deployment target** of the extension: iOS 16.0 or later, like the app.

## App side

Two small changes in the app target. The group id is the one on both capabilities.

### 1. Share the session with the extension

Pass the group to `initialize`. Call it early in `application(_:didFinishLaunchingWithOptions:)`:

```swift
SinchPushSDK.shared.initialize(
    options: SinchPushInitializeOptions(environment: .prod, appGroup: "group.com.example.app")
)
```

With `appGroup` set the SDK copies a minimal record into the group's container, after every `setIdentity` and every token
refresh, and deletes it on `removeIdentity`:

| Field | Meaning |
| --- | --- |
| `accessToken` | the JWT the SDK uses for the push API |
| `reportBaseURL` | the push API URL of your region (`https://grpc.sinch-push.prod.sinch.com` for EU1) |
| `userId` | the user the token was issued for |
| `appId` | the id of the Sinch config |

The identity secret (`appSecret` or the HMAC digest) is **never** copied. The record is a file in the App Group
container with `NSFileProtectionCompleteUntilFirstUserAuthentication`, excluded from backups: the Keychain item the token
comes from is readable after the first unlock too. A shared Keychain access group would need the *Keychain Sharing*
capability in addition to the App Group, and the file needs nothing beyond the App Group. Other apps of the same group
can read the file, so use a group that only your own apps belong to.

`appGroup` defaults to `nil`; nothing is shared then, and `didReceive` in the extension returns `false`.

The token expires, and the extension cannot refresh it. When the mirrored token has expired (or expires within a minute),
the extension does not upload; it stores the delivery in the App Group, and the app reports it the next time it runs (see
[If the report fails](#if-the-report-fails)). The record is rewritten each time the app refreshes the token, which it does
whenever it is used, and deleted on `removeIdentity`. After `removeIdentity` the SDK stops mirroring until the next
successful `setIdentity`, so a token refresh that was still in flight cannot bring the old user's token back.

If you later stop passing `appGroup`, the SDK still deletes the record from the group it last used.

### 2. Forward the background session events

The system wakes the app when an upload of the SDK has finished, also one the extension started. Forward the call from
your app delegate (see [Background URLSession](#background-urlsession)):

```swift
func application(_ application: UIApplication,
                 handleEventsForBackgroundURLSession identifier: String,
                 completionHandler: @escaping () -> Void) {
    if SinchPushSDK.shared.push.handleEventsForBackgroundURLSession(identifier: identifier,
                                                                    completionHandler: completionHandler) {
        return // the SDK keeps the handler and calls it when it is done
    }
    // Not the SDK's session: handle your own background sessions here.
}
```

It returns `false`, and keeps the handler, for any identifier that is not one of the SDK's. With SwiftUI, use
`@UIApplicationDelegateAdaptor`.

## Signing and provisioning

The extension is a separate bundle and needs its own signing identity, which is where most setups fail:

- **App ID.** Register `com.example.app.NotificationService` in the developer portal with the **App Groups** capability
  and the same group as the app. (Push Notifications is not needed on the extension's App ID.)
- **Provisioning profile.** One per configuration for the extension: development, and App Store / TestFlight (or ad hoc).
  Each must include the App Group. With automatic signing Xcode creates them for you; with manual signing or fastlane
  `match`, run `match` for the extension's bundle id too.
- **App Group on the app's App ID.** Regenerate the app's profile after adding the group.
- **Export options.** `xcodebuild -exportArchive` and fastlane's `gym` need a profile for each bundle id of the archive.
  In `ExportOptions.plist`:

  ```xml
  <key>method</key>
  <string>app-store</string>
  <key>provisioningProfiles</key>
  <dict>
      <key>com.example.app</key>
      <string>Example App AppStore</string>
      <key>com.example.app.NotificationService</key>
      <string>Example App NotificationService AppStore</string>
  </dict>
  ```

  With fastlane: `export_options: { provisioningProfiles: { "com.example.app" => "…", "com.example.app.NotificationService" => "…" } }`.
- The extension's `CFBundleVersion` and `CFBundleShortVersionString` must equal the app's, or App Store Connect rejects
  the build. Use the same `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` build settings for both targets.

## How it works

```
 push (mutable-content: 1) ──▶ NotificationService.didReceive
                                 └─ SinchPushNotificationExtension.didReceive
                                      1. read sinch.push.message_id / sinch.push.subscriber_id from the payload
                                      2. read the shared record (access token, push API URL) from the App Group
                                      3. skip it if the sent-marker says it was reported already
                                      4. mirrored token expired? store the delivery for the app and stop
                                      5. write the gRPC-web ReportEvents body to a file, start a background upload
                                 contentHandler(...)                 ◀── returns in milliseconds
                 nsurlsessiond uploads (extension may be gone)
                                 └─▶ app wakes → handleEventsForBackgroundURLSession → sent-marker recorded
```

- The report is a `ReportEvents` call with `DELIVERED` (300), as gRPC-web over HTTPS: `POST
  <push API>/sinch.push.sdk.v1beta1.SdkService/ReportEvents`, `content-type: application/grpc-web+proto`, the access
  token in `authorization`. No gRPC library is needed in the extension.
- When the server accepts it, the delivery is written to a **sent-marker** store in the App Group (the last 1000
  deliveries, at most 7 days old). The app checks it before it reports a delivery, so a delivery the extension reported is
  not reported again by the app.
- A `ReportEvents` answer counts as accepted only with `grpc-status: 0`, in the trailer or in the header. An HTTP 2xx
  without any `grpc-status` (a captive portal, a proxy error page) is **not** accepted.
- For a custom region, the report goes to `pushAPIHost` over `https`, on the region's `port`; `isSecure: false` makes it
  `http`. A `host:port` in `pushAPIHost` is understood too.

### If the report fails

The extension cannot retry, and the app does not know about a delivery the extension handled. So whenever the extension
does not get an accepted answer, it **stores the delivery in the App Group** (`pending-deliveries.json`: message id,
subscriber id, time; the last 1000, at most 7 days old):

- the token expired, so the extension did not try;
- the upload could not be started;
- the upload finished with `401`, any other non-2xx status, a transport error, a non-zero `grpc-status`, or no
  `grpc-status` at all.

The app reads and empties that store (`ReportContainer.takePendingDeliveries()`) when it runs and queues the deliveries
in its own outbox, which reports them with a fresh token and retries. So an extension failure delays the report until the
app runs once; it does not lose it.

- If the app and the extension both report the same delivery (before either marker exists, or when the app's marker check
  races the extension's upload), the server receives it twice. **The server keeps the first terminal status of a
  delivery, so such a duplicate is harmless.**

## Background URLSession

The SDK uploads delivery reports with a **background `URLSession`**, in the app as well as in the extension, so a report
completes even if the process is suspended or killed before the response arrives.

| Session identifier | Owner |
| --- | --- |
| `com.sinch.chatsdk.reports` | the app |
| `com.sinch.chatsdk.reports.nse.<uuid>` | one extension upload |
| `com.sinch.chatsdk.reports.nse` | extension builds before the identifier carried a `<uuid>`; still served, never created |

The system allows **one process per background session identifier**, and the app and the extension are separate
processes (so are two runs of the extension, and an extension process can idle for minutes between pushes). Each
extension upload therefore creates its own session under a new identifier, `com.sinch.chatsdk.reports.nse.<uuid>`, notes
it in the App Group, starts the upload and releases the session at once (`finishTasksAndInvalidate`): the extension never
holds a session after `didReceive` returns, and a noted identifier is always one the extension has let go of. The app
serves any identifier with that prefix: when the system wakes it for one, the SDK builds a session for exactly that
identifier, collects the results and releases it. On every launch the app also reopens the noted extension sessions
(after a short grace of 30 seconds, which covers the moments between noting and releasing) and its own, so results that
arrived while it was not running are not missed. A failed extension upload that the app learns of is queued from the
pending store at once, and the app also queues the pending deliveries each time it comes to the foreground. An extension session needs the App Group; the
SDK does not create one without it.

Sessions are created with `sessionSendsLaunchEvents = true`, `sharedContainerIdentifier` set to your App Group when you
passed `appGroup` to `initialize`, and a **resource timeout of 10 minutes**: the system gives up on an upload after that,
and the app holds the deliveries of an upload in flight for as long (below), so it cannot report them a second time while
the system might still deliver them. The App Group and the directory of the files are fixed when a session is created;
the upload body is written to a file in that container first (a background session can only upload from a file), and the
full path of the file travels with the task, so the file is removed when the upload finishes wherever the process is.

In the app, `SinchPushSDK.shared.push.handleBackgroundNotification(_:)` uses the same mechanism: the queued reports are
handed to the `com.sinch.chatsdk.reports` session and the call returns quickly, instead of waiting for the response. The
reports stay in the outbox marked **in flight**, and the normal foreground flush leaves them alone until the upload
finishes or 10 minutes have passed (the session's resource timeout). A successful upload removes them from the outbox; a failed one hands them back
to the normal flush. While the app is in the foreground, reports go out over gRPC as before.

You must forward `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to the SDK (see
[App side](#2-forward-the-background-session-events)); without it the system still uploads, but the SDK learns the result
only the next time the app runs, and the reports are held back from the normal flush until then.

## Memory and time limits

- An extension has roughly **24 MB** of memory on recent iOS versions, and is killed when it goes over. The
  `SinchPushSDKNotificationExtension` product is a few hundred lines on top of Foundation; adding the main `SinchPushSDK`
  (UIKit, the relay, the in-app UI, SwiftProtobuf) to the extension would risk the limit. Do not.
- The extension has about **30 seconds**. `didReceive` returns in milliseconds. It never waits for the network.
- iOS keeps the extension process alive between pushes for a while. The SDK holds no session across pushes: each upload
  has its own session, released as soon as the upload is started.
- The files shared with the app are guarded by file locks. The SDK takes them without blocking (a short, bounded retry,
  then it goes on): a process that is suspended while it holds a lock on a file in the shared container is killed by
  the system (`0xdead10cc`).

## Verify it

1. Run the **app** target on a device or simulator, call `initialize` with `appGroup` and `setIdentity`, and allow
   notifications.
2. Send a test push with `mutable-content` to the simulator (`payload.apns`):

   ```json
   {
     "aps": { "alert": { "title": "Hello", "body": "Test" }, "mutable-content": 1 },
     "sinch.push.message_id": "test-message-1",
     "sinch.push.subscriber_id": "test-subscriber-1"
   }
   ```

   ```sh
   xcrun simctl push booted com.example.app payload.apns
   ```

   Use a real message id and subscriber id from Sinch if you want the server to accept the report; a made-up one is
   refused (a non-zero `grpc-status`) and stays unmarked.
3. **Attach the debugger to the extension:** *Debug ▸ Attach to Process by PID or Name…* ▸ `NotificationService`, or run
   the extension's scheme and choose your app as the host. Set a breakpoint in `didReceive` and send the push.
4. **Logs.** In Console.app, select the device, filter by `process:NotificationService` or by subsystem
   `com.apple.CFNetwork`. A started upload shows a `com.sinch.chatsdk.reports.nse.<uuid>` background task in `nsurlsessiond`:

   ```sh
   xcrun simctl spawn booted log stream --level debug --predicate 'process == "nsurlsessiond" OR process == "NotificationService"'
   ```

5. **Force-quit** the app (swipe it away) and send the push again: the banner appears, and the report is still uploaded.
6. After the upload finished, the delivery is in the sent-marker store: `<App Group container>/Library/Application
   Support/com.sinch.chatsdk/sent-report-markers.json`. On the simulator,
   `xcrun simctl get_app_container booted com.example.app groups` prints the container path.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| The extension never runs. | The push has no `mutable-content: 1`; the extension's bundle id is not prefixed by the app's; the extension's deployment target is higher than the device's; the extension was not embedded in the app (*Build Phases ▸ Embed Foundation Extensions*). Also: a silent push (no `alert`) never starts it. |
| `didReceive` returns `false`. | Not a Sinch push (no `sinch.push.message_id` / `sinch.push.subscriber_id`), or the app never called `initialize` with this `appGroup`, or `setIdentity` has not succeeded yet, or the group id differs between the code and the entitlements. |
| `didReceive` returns `false` and the log says the App Group has no container. | The App Groups capability is missing on the app **or** the extension, or the group is not in the provisioning profile. |
| The extension is killed at once. | Memory: `SinchPushSDK` was added to the extension target. Remove it and add `SinchPushSDKNotificationExtension` only. |
| The report is uploaded but not accepted (no marker is written). | The extension stored the delivery (`pending-deliveries.json`); open the app and it reports it. Typical causes: the access token expired before the extension ran, or a wrong region. |
| The marker never appears. | The app does not forward `handleEventsForBackgroundURLSession`, or `initialize` runs late. Call `initialize` in `didFinishLaunching`. |
| App Store Connect rejects the upload. | The extension's version / build number differs from the app's, or its profile has no App Group. |
| `error: Multiple commands produce …` or duplicate symbols. | Both `SinchPushSDK` and `SinchPushSDKNotificationExtension` are linked into the **app**. That is fine (the first depends on the second); make sure the extension target links the second one only. |
| Reports are sent twice. | Expected in a race (see [How it works](#how-it-works)); the server deduplicates by message and subscriber. |
