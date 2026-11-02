#!/bin/bash
# Regenerates the SwiftProtobuf messages of SinchPushSDK.
#
# The generated files are renamed after the upstream ones of the chat SDK, so the same message ends up under the same
# name in both places:
#
#   sinch/chat/sdk/v1alpha2/sdk.proto          -> chatSdk.pb.swift
#   sinch/push/sdk/v1beta1/sdk.proto            -> pushSdk.pb.swift
#   sinch/push/v1beta1/resources.proto          -> push_v1beta1_resources.pb.swift
#   sinch/push/events/v1beta1/events.proto      -> events.pb.swift
#
# `push/delivery/v1beta1/ws/websocket.pb.swift` (the relay frames) is copied from the chat SDK's generated output; it is
# not part of the trimmed protos of this script.
#
# Requirements: protoc and protoc-gen-swift (protoc 36.2, protoc-gen-swift 1.38.x).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
OUT="$ROOT/Sources/SinchPushSDK/Transport/Generated"

rm -rf "$OUT"
mkdir -p "$OUT"

protoc \
  --plugin=protoc-gen-swift="$(command -v protoc-gen-swift)" \
  --swift_out="$OUT" \
  --proto_path=Protos \
  Protos/sinch/chat/sdk/v1alpha2/sdk.proto \
  Protos/sinch/push/sdk/v1beta1/sdk.proto \
  Protos/sinch/push/v1beta1/resources.proto \
  Protos/sinch/push/events/v1beta1/events.proto

mv "$OUT/sinch/chat/sdk/v1alpha2/sdk.pb.swift"        "$OUT/sinch/chat/sdk/v1alpha2/chatSdk.pb.swift"
mv "$OUT/sinch/push/sdk/v1beta1/sdk.pb.swift"          "$OUT/sinch/push/sdk/v1beta1/pushSdk.pb.swift"
mv "$OUT/sinch/push/v1beta1/resources.pb.swift"        "$OUT/sinch/push/v1beta1/push_v1beta1_resources.pb.swift"
mv "$OUT/sinch/push/events/v1beta1/events.pb.swift"    "$OUT/sinch/push/events/v1beta1/events.pb.swift"

echo "Generated:"
find "$OUT" -name "*.swift" | sort
