# Relay contract pin

The relay WebSocket protocol is **owned by the `sinch-push-relay` repository**.
The files below are byte-for-byte copies of that repository at a pinned commit.
Do not edit them here — an edit here is a contract divergence that only shows up
in production.

## Pinned commit

| | |
| --- | --- |
| Repository | `sinch-push-relay` (`github.com/sinch/sinch-push-relay`) |
| Commit | `d0e0d801c8bf3b44fb024981731314d61ce0113c` (`d0e0d80`) |
| Commit title | `contract: BackgroundServiceState RELAY_DISABLED = 5` |
| Pinned on | 2026-10-20 |

There is no negotiation at runtime: the relay speaks the protocol of the commit
it was built from, and this SDK has to speak the same one. Pinning a commit is
what turns an incompatibility into a build failure instead of a production
incident.

History: pinned at `3742c71dfaf4f8973f76c844cd1b0532b516b679`
(`contract: relay routing Phase 0 shared protos`) until `d0e0d80` landed
`BackgroundServiceState.RELAY_DISABLED = 5` in the relay contract; between the
two the SDK carried that one enum value locally (`TODO(relay-pin)`) while
everything else was the pinned copy. `d0e0d80` is additive (a new enum value,
a new golden vector, contract clarifications), so all three files below are
byte-for-byte copies again and there is no local deviation left.

## Files copied from the pin

| Relay path | Local path |
| --- | --- |
| `proto/sinch/push/delivery/v1beta1/ws/websocket.proto` | `sinch/push/delivery/v1beta1/ws/websocket.proto` |
| `proto/sinch/push/v1beta1/resources.proto` | `sinch/push/v1beta1/resources.proto` |
| `testdata/wire/ws_frames.v1beta1.golden.json` | `SinchPushSDK/Tests/SinchPushSDKTests/PushSocket/Fixtures/ws_frames.v1beta1.golden.json` |

`sinch/push/relay/v1beta1/relay.proto` is deliberately **not** copied: it is a
server-to-server gRPC service (`RelayService`, `RelayCallbackService`), not part
of the SDK wire surface.

The relay's `resources.proto` copy is the only source of
`sinch.push.v1beta1.resources` in this SDK; if a sinch-push copy is ever
vendored, the two must not diverge.

What `d0e0d80` changed for this SDK: `resources.proto` gains
`RELAY_DISABLED = 5` (the file is otherwise identical to the previous pin), and
the golden fixture gains the `client_hello_relay_disabled` vector (48 frames / 14
negative cases, up from 47 / 14). `websocket.proto` is byte-identical to the
`3742c71` copy. `d0e0d80`'s `proto/CONTRACT.md` also renumbers its sections
(`installation_id` format 2.5 → 2.6, callback semantics 2.6 → 2.7, enum naming
2.7 → 2.8; new 2.5 is `RELAY_DISABLED`) and adds the 128-byte cap on
`os_version` / `bundle_id` / `sdk_version` (CONTRACT §2.6), which this SDK
enforces by clamping — see `PushSocket/PORTING.md`.

## The `sinch-push` pin

`sinch/push/sdk/v1beta1/sdk.proto` and `sinch/push/events/v1beta1/events.proto`
are **owned by the `sinch-push` repository**. They are byte-for-byte copies of
that repository at a pinned commit. Do not edit them here — an edit here is a
contract divergence that only shows up in production.

| | |
| --- | --- |
| Repository | `sinch-push` |
| Commit | `ddab2ab5fbf178a84baed473508766306a5a1f15` (`ddab2ab`) |
| Commit title | `style(test): T23d review fixes (accurate env doc, invariants once, e2e harness under 5%)` |
| Pinned on | 2026-10-22 |

| sinch-push path | Local path |
| --- | --- |
| `src/proto/sinch/push/sdk/v1beta1/sdk.proto` | `sinch/push/sdk/v1beta1/sdk.proto` |
| `src/proto/sinch/push/events/v1beta1/events.proto` | `sinch/push/events/v1beta1/events.proto` |

`sdk.proto` imports `sinch/push/v1beta1/resources.proto`, which stays the
relay's copy (above); the `resources.proto` at `ddab2ab` is byte-identical to
it, so the two do not diverge. `events.proto` is vendored because `sdk.proto`
imports it for `PushEventType`; the SDK never calls `EventService`.

`ddab2ab` changes `SdkService.Subscribe` to return `SubscribeResponse`
(`optional string subscriber_id = 1`) instead of `google.protobuf.Empty`, and
makes the `Unsubscribe` / `GetPublicKey` request fields optional. The response
change is wire-compatible (the method path is unchanged): the SDK reads
`subscriber_id` but does not depend on it.

History: `sdk.proto` was a local file until this pin — it carried the relay's
`SubscribeRequest` and, since 2026-10-20, deliberately kept the pre-`9374663`
Subscribe response (no repin). The pin supersedes both.

## The `SubscribeRequest` fields

The relay's `proto/CONTRACT.md` specifies the `SubscribeRequest` fields. The
vendored `sinch/push/sdk/v1beta1/sdk.proto` carries them unchanged (fields 1
to 10, all optional), so both pins have to move together if they ever change.

Note `resources.Platform` and `ws.Platform` are different enums with **different
numbers** (`resources`: IOS=3, ANDROID=4, WEB=1; `ws`: IOS=1, ANDROID=2, WEB=3).
Translate at the boundary; never copy the integer across.

## How to bump the pin

1. Update the pinned commits and the tables above.
2. Re-copy the three files byte-for-byte from the new relay commit:
   ```sh
   RELAY=../sinch-push-relay        # checkout of sinch-push-relay
   REV=<new-commit-sha>
   git -C "$RELAY" show "$REV":proto/sinch/push/delivery/v1beta1/ws/websocket.proto \
     > proto/sinch/push/delivery/v1beta1/ws/websocket.proto
   git -C "$RELAY" show "$REV":proto/sinch/push/v1beta1/resources.proto \
     > proto/sinch/push/v1beta1/resources.proto
   git -C "$RELAY" show "$REV":testdata/wire/ws_frames.v1beta1.golden.json \
     > SinchPushSDK/Tests/SinchPushSDKTests/PushSocket/Fixtures/ws_frames.v1beta1.golden.json
   ```
3. Re-copy the two files byte-for-byte from the new sinch-push commit:
   ```sh
   PUSH=../sinch-push                # checkout of sinch-push
   REV=<new-commit-sha>
   git -C "$PUSH" show "$REV":src/proto/sinch/push/sdk/v1beta1/sdk.proto \
     > proto/sinch/push/sdk/v1beta1/sdk.proto
   git -C "$PUSH" show "$REV":src/proto/sinch/push/events/v1beta1/events.proto \
     > proto/sinch/push/events/v1beta1/events.proto
   ```
4. Check that the new `sdk.proto` still carries the relay's `SubscribeRequest`
   fields, and that `resources.proto` did not diverge from the relay's copy.
5. Regenerate: `sh scripts/generate_proto.sh` from `DevApp/`.
6. Run the golden vectors and fix the call sites that the new `optional` fields
   break:
   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
     -scheme SinchPushSDK-Package -destination 'platform=iOS Simulator,name=iPhone 17' \
     -derivedDataPath /tmp/ios-relay-dd
   ```

Additive changes (new fields, new `oneof` members) are safe — an old decoder
skips them. Removing or renumbering a field, or repurposing an enum number, is
not additive and requires a new package version.
