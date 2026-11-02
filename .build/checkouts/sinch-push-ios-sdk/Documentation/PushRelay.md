# Push relay (foreground delivery)

Release notes: [`CHANGELOG.md`](../CHANGELOG.md).

The push relay is a WebSocket between the app and the Sinch push relay. It is open **only while the app is in the
foreground**: messages arrive immediately, without waiting for APNs. When the app goes to the background or is
terminated the socket is closed and push notifications arrive through APNs as before. Nothing about background
modes or entitlements changes.

Messages are never delivered twice: a message that reached the app through APNs is not shown again by the relay and
the other way round (they share one message id).

## Availability

| Region | Relay |
|---|---|
| `.EU1` | Enabled: the relay of the region — `wss://relay.sinch-push.prod.sinch.com/ws` (it mirrors the push host `grpc.sinch-push.prod.sinch.com`). |
| `.US1` | Enabled: the relay of the region — `wss://relay.sinch-push.us1.prod.sinch.com/ws` (it mirrors the push host `grpc.sinch-push.us1.prod.sinch.com`). |
| `.custom(host:pushAPIHost:port:isSecure:relayURL:)` | Enabled when `relayURL` is set. Without one the relay URL is derived from `pushAPIHost`: the staging relay for the staging push hosts, the production relay for the production ones. |

The relay URL is derived from the region, so an integrator never has to pass one. The derived hosts have to exist in
DNS before the relay can be connected to: the production relay hosts
(`relay.sinch-push.prod.sinch.com`, `relay.sinch-push.us1.prod.sinch.com`) must be published for `.EU1` / `.US1` to
connect; until then the socket fails to connect and the app keeps working over APNs.

```swift
let region = Region.custom(host: "chat.example.com",
                           pushAPIHost: "push.example.com",
                           port: nil,
                           isSecure: true,
                           relayURL: URL(string: "wss://relay.example.com/ws"))
```

The relay deployed in staging (eu1tst), in front of the staging sinch-push, is derived for the staging push hosts:

```swift
let staging = Region.custom(host: "grpc.sinch-chat.staging.sinch.com",
                             pushAPIHost: "grpc.sinch-push.staging.sinch.com",
                             port: 443,
                             isSecure: true)
// → wss://relay.sinch-push.eu1tst.staging.sinch.com/ws
```

* `wss://` is always accepted. `ws://` (local development) only with `AppConfig.allowInsecureRelay` (below).
* `isSecure` concerns the chat gRPC channel only (`false` makes it plaintext); it neither enables nor blocks a
  `ws://` relay.
* `relayURL: nil` (the default) derives the relay URL from the region (see *Availability*); a push host without a
  relay leaves the relay disabled for that region.

## Configuration

`AppConfig` has a kill switch, enabled by default:

```swift
let config = SinchSDKConfig.AppConfig(clientID: "…", projectID: "…", configID: "…",
                                      region: region,
                                      relay: .disabled)   // default: .enabled
```

For a relay on your own machine, `allowInsecureRelay: true` lets the SDK connect to a plaintext `ws://` URL
(default `false`; development only). `AppConfig`s encoded before the option existed decode with `false`. Without it a
`ws://` URL leaves the relay disabled (`socketState.disabledReason` says why).

```swift
let local = Region.custom(host: "…", pushAPIHost: "…", port: nil, isSecure: true,   // gRPC keeps TLS
                          relayURL: URL(string: "ws://127.0.0.1:8080/ws"))
let config = SinchSDKConfig.AppConfig(clientID: "…", projectID: "…", configID: "…", region: local,
                                      allowInsecureRelay: true)
```

The relay starts after `setIdentity` succeeds and stops as soon as `removeIdentity` is called. A repeated
`setIdentity` for the same user does not reconnect (unless the access token changed); for another user it restarts
the relay.

A running relay also stops as soon as `setIdentity` is *called* for a different identity or configuration, not when it
succeeds: if that call fails, the SDK does not keep a relay open for the previous identity next to the new
configuration (it starts again with the next successful `setIdentity`).

## Turning the relay off at runtime

```swift
push.setRelayEnabled(false)   // immediate: the socket closes, the identity and the subscription stay
push.isRelayEnabled           // the switch itself (persisted across launches, on by default)
push.setRelayEnabled(true)    // starts the socket again if an identity is set and the configuration allows it
```

The relay runs only when **all three** hold: `AppConfig.relay == .enabled`, the runtime switch is on, and the region
has a usable relay URL (the region-derived one, or an explicit `relayURL`; a `ws://` URL needs `allowInsecureRelay`).
That is the *effective relay state*. `socketState` shows it (`relayEnabled`, `disabledReason` — "relay disabled at
runtime" after `setRelayEnabled(false)`, status `.stopped`).

**What the backend is told.** The SDK's Subscribe carries `background_service`:

| Effective relay state | `background_service` | Routing |
|---|---|---|
| on (socket will run when the app is in the foreground) | `UNSUPPORTED` (1) | relay while connected, push provider otherwise |
| off by configuration: `relay: .disabled`, switch off, or no relay URL for the region | `RELAY_DISABLED` (5) | push provider only |

Only configuration decides. A relay that is on but momentarily not connected (offline, app in the background,
authentication error) still reports `UNSUPPORTED`. Every change of that state — the switch, or a `setIdentity` with a
different `relay` option / region — re-subscribes exactly once (when the device token and an identity are known).
The WebSocket `Hello` keeps `UNSUPPORTED`; with the relay off there is no socket and no `Hello`.

The device fields are all-or-nothing: while the Keychain is locked and the installation id is therefore unknown, the
Subscribe goes out without them, so the backend sees no `background_service` at all (legacy, treated as
UNSPECIFIED) — the next Subscribe that can read the id sends the state above again.

**Reports** made while the relay is off stay queued for the identity (they are not dropped) and are sent when the relay
runs again; `removeIdentity` or a different user clears them as before.

`setRelayEnabled` before `setIdentity` is remembered and read when the identity is authorised. Hosts that mock
`SinchPush` get defaults (`setRelayEnabled` does nothing, `isRelayEnabled` answers the toggle's default, on).

## Required app wiring

Messages from the relay are shown as **local notifications**, and your notification delegate decides how they are
presented in the foreground — exactly as for APNs. Forward both delegate methods to the SDK:

```swift
func userNotificationCenter(_ center: UNUserNotificationCenter,
                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    // nil: not a Sinch notification, decide yourself.
    SinchPushSDK.shared.push.handleWillPresentNotification(notification) ?? [.banner, .list, .sound]
}

func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse) async {
    _ = SinchPushSDK.shared.push.handleNotificationResponse(response)
}
```

Without the `willPresent` forwarding iOS does not show a notification while the app is in the foreground, so
relay messages would be invisible. `handleNotificationResponse` hands a tap to the app and reports a swipe-away
(dismiss) of a relay notification to the relay.

If you handle remote notifications in `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`, keep
calling `SinchPushSDK.shared.push.handleNotification(_:)` from it.

## Observing the relay

```swift
let push = SinchPushSDK.shared.push

push.socketState                       // SinchPushSocketState: status, relayEnabled, disabledReason, lastError, reconnectAttempts
push.socketStatePublisher              // replays the current state; delivers on the main thread
push.socketMessagePublisher            // every relay message once; no replay; delivers on the main thread
push.installationId                    // String? — nil when the Keychain is unavailable
```

* `socketState.relayEnabled == false` with a `disabledReason` tells why the relay is not used (kill switch, region
  without relay host, `setRelayEnabled(false)`, no identity yet). The reason is meant for logs.
* `status` is `.idle` while the app is in the background; `.authRequired` / `.error` mean the relay is off until the
  next `setIdentity` (the SDK already tried to re-issue the access token once).
* A message that is an in-app message (Sinch `owner` + `protobufPayload`) is shown in the app and no system
  notification is posted for it, like for APNs.
* After a reconnect the relay replays what you missed. Only the first notification of a burst alerts (banner, sound);
  the others are posted silently — into the notification list and the badge, no banner, no sound — also in the
  foreground. Nothing is dropped.
* `installationId` is read from the Keychain once and cached for the life of the process once it was readable.

## Reporting what the user did

The SDK reports `delivered` and, for the notifications it posts, `displayed` and `dismissed` itself. `displayed` means
the notification was posted: a message whose banner your app (or the open conversation) then suppresses in
`willPresent` is still reported `displayed`. If your app
shows a relay message in its own UI, report it:

```swift
push.reportStatus(messageId: message.id, status: .displayed)   // or .dismissed
```

Reports are queued while the relay is not connected and sent at the next connection, so calling this from the
background is fine.

Pending reports and the replay position (the id the relay resumes after) belong to one user of one app/project. They
are kept across launches for the same user, and cleared when another user starts a relay session and on
`removeIdentity`. A report made while no user owns the pending reports — after `removeIdentity`, and on the very
first launch before any `setIdentity` — is dropped (and logged), not kept for whoever signs in next. After a cold
launch the previous session's user still owns them: a report made before `setIdentity` is queued, and kept if the
same user signs in again (it is discarded if another one does).

## Reporting APNs deliveries from a background wake

A push with `content-available: 1` wakes a suspended or terminated app, and the SDK reports its delivery to sinch-push
during that wake. Call the async handler and finish the fetch only after it returns, as the app is suspended again
soon after the completion handler:

```swift
func application(_ application: UIApplication,
                 didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                 fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    Task {
        let isHandled = await SinchPushSDK.shared.push.handleBackgroundNotification(userInfo)
        completionHandler(isHandled ? .newData : .noData)
    }
}
```

`handleBackgroundNotification` does what the synchronous `handleNotification` does (which stays as it is), then hands
the queued delivery reports to a **background `URLSession`** upload and returns, without waiting for the response: the
system completes the upload even when the app is suspended right after. The reports stay in the outbox, marked in
flight, until the upload ends: the normal flush leaves them alone for that time (as long as the system keeps trying the
upload, 10 minutes), a successful upload removes them, a failed one hands them back. A report whose answer is lost is
sent again after that; the server keeps the first terminal status, so the rare duplicate is harmless. The hand-off waits
for a flush that is running, so its batch is not uploaded twice, and an access token that is expired (or about to be) is
refreshed first, as an upload cannot retry a 401 once the app is suspended. When the upload cannot be started, or the
token cannot be refreshed, the call falls back to one bounded attempt over gRPC. The whole call, the restore of the
session and the hand-off included, takes at most 20 seconds in total, counted from the moment it is called: a report
that could not be sent stays in the outbox and goes out at the next trigger (foreground, the next wake). No retry is
scheduled, since the app does not run in between, and one an earlier flush scheduled is left alone. A
`content-available` push that arrives while the app is in the foreground is reported by the normal flush instead, with
its usual backoff.

Deliveries the Notification Service Extension could not upload are queued in the app's outbox by `initialize` and at the
start of `handleBackgroundNotification` (unless an upload has reported them already), so the app reports them.

Forward `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to
`SinchPushSDK.shared.push.handleEventsForBackgroundURLSession(identifier:completionHandler:)` so the SDK learns the
result of an upload that finished while the app was not running; see
[Background URLSession](NotificationServiceExtension.md#background-urlsession).

This also works for a cold launch the system starts in the background, where your code never calls `setIdentity`:
the SDK keeps the `AppConfig` of the last successful `setIdentity` (in `UserDefaults`, no secret) and finds the user's
token in the Keychain. Call `SinchPushSDK.shared.initialize(config:options:)` early in `didFinishLaunching`, before the async
handler runs. `initialize` restores that session only for a launch in the background (a foreground launch reaches
`setIdentity`), and the async handler restores it when it is still missing. Nothing is reported until `setIdentity` has succeeded once on the device, and `removeIdentity` forgets
the stored config (even when its unsubscribe fails). The reports of the previous user are dropped when another user
calls `setIdentity`; the same user signing in again, with another locale or relay option, keeps them. An expired token
is refreshed during the wake for a signed identity; an anonymous one cannot be, so its reports wait for the next
`setIdentity`.

Nothing is reported before the first unlock after a device restart: the Keychain and `UserDefaults` cannot be read
yet. The async handler tries the restore again, so a wake after the unlock reports.

Without a Notification Service Extension, a push that does not wake the app (no `content-available`, or the user
force-quit the app) is not reported until the app runs again. To report every visible push, also after a force-quit,
add the optional extension: [Notification Service Extension](NotificationServiceExtension.md).

## Duplicates

Each relay message has one id, also carried by its APNs copy (`sinch.push.message_id`). The SDK keeps the ids it has
seen (the last 2000, across launches). Whichever channel delivers a message **first** wins; only the copy of the *other*
channel is suppressed:

* an APNs notification whose id the relay socket already delivered (in this launch or an earlier one) is not presented
  (`handleWillPresentNotification` returns `[]`) and not handled again (`handleNotification` returns `true` without
  showing an in-app message or asking an addressee);
* a relay message whose id was already seen, through APNs or the socket, is not published or shown; one whose
  notification is already in the notification center is published (`socketMessagePublisher`) but no second
  notification is posted;
* a tap on a notification is handled by `handleNotificationResponse` and your own code.

Only Sinch notifications take part; your own notifications are never deduplicated.

### `willPresent` and `didReceiveRemoteNotification` in any order

For one foreground push (content-available + alert) iOS may call your `userNotificationCenter(_:willPresent:)` and
`application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` in either order. Forward both to the SDK
(`handleWillPresentNotification`, `handleNotification`) and do not rely on an order: a message that arrived over APNs is
never hidden by its own other callback, and it is suppressed only when it is a copy of a message the relay socket
delivered. (The SDK shows in-app messages from `handleNotification`, and decides the banner in
`handleWillPresentNotification`.) A second APNs delivery of the same message in the same launch is not suppressed;
APNs collapses those itself (`apns-collapse-id`).

## Test doubles

The relay members of `SinchPush` (`socketState`, `socketStatePublisher`, `socketMessagePublisher`, `reportStatus`,
`installationId`) have default implementations that describe a relay that is not there (idle, `relayEnabled == false`,
no messages, no-op report, `nil`), so an existing mock of `SinchPush` keeps compiling.

`handleBackgroundNotification(_:)` has a default implementation too: it calls the synchronous `handleNotification(_:)` and reports nothing.
