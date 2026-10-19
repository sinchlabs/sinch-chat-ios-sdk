#!/bin/bash
# Note: the binary build does not re-export SwiftProtobuf (the SPM build does).
# Builds SinchChatSDK.xcframework (device + simulator) for the CocoaPods release.
# Output: build/SinchChatSDK.xcframework.zip (contains the xcframework and LICENSE.md)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build"
PKG="$WORK/pkg"
NAME=SinchChatSDK

rm -rf "$WORK"
mkdir -p "$PKG"

# Build from a temp copy where the library product is dynamic, so the framework
# statically contains gRPC & co. Package.swift in the repo stays untouched.
rsync -a --exclude build --exclude .git --exclude .swiftpm "$ROOT/Sources" "$ROOT/Package.swift" "$ROOT/LICENSE.md" "$PKG/"
mkdir -p "$PKG/Tests/SinchChatSDKTests"
sed -i '' 's/\.library(name: "SinchChatSDK", targets:/.library(name: "SinchChatSDK", type: .dynamic, targets:/' "$PKG/Package.swift"
grep -q 'type: .dynamic' "$PKG/Package.swift" || { echo "failed to patch Package.swift"; exit 1; }

# Library evolution (module stability) only for the SDK target: some dependencies don't compile with it.
perl -0pi -e 's/\.process\("record\.wav"\)\]/.process("record.wav")],\n swiftSettings: [.unsafeFlags(["-enable-library-evolution"])]/' "$PKG/Package.swift"
grep -q 'enable-library-evolution' "$PKG/Package.swift" || { echo "failed to patch Package.swift"; exit 1; }

# Keep dependency modules (gRPC, SwiftProtobuf) out of the public module interface, so consumers
# don't need them (they are linked statically into the binary).
find "$PKG/Sources" -name '*.swift' -print0 | xargs -0 perl -pi -e 's/^(?:\@_exported )?import (GRPC\w*|SwiftProtobuf|Kingfisher|Logging)\b/internal import $1/'

archive() { # $1 = destination, $2 = archive name
  (cd "$PKG" && xcodebuild archive \
    -scheme "$NAME" \
    -destination "$1" \
    -archivePath "$WORK/$2.xcarchive" \
    -derivedDataPath "$WORK/derived-$2" \
    SKIP_INSTALL=NO \
    SWIFT_EMIT_MODULE_INTERFACE=YES \
    -quiet)
}

archive "generic/platform=iOS" ios
archive "generic/platform=iOS Simulator" ios-sim

# SPM archives only contain the bare binary. Assemble complete frameworks: binary + module interface
# + generated header/modulemap + resource bundle (strings, assets, record.wav).
assemble() { # $1 = archive name, $2 = SPM products dir name, $3 = swiftinterface triple
  local BIN="$WORK/$1.xcarchive/Products/usr/local/lib/$NAME.framework"
  local PROD="$WORK/derived-$1/Build/Intermediates.noindex/ArchiveIntermediates/$NAME/BuildProductsPath/$2"
  local GEN="$WORK/derived-$1/Build/Intermediates.noindex/ArchiveIntermediates/$NAME/IntermediateBuildFilesPath"
  local FW="$WORK/frameworks/$1/$NAME.framework"
  mkdir -p "$FW/Modules/$NAME.swiftmodule" "$FW/Headers"
  cp "$BIN/$NAME" "$BIN/Info.plist" "$FW/"
  for ext in swiftinterface swiftdoc abi.json; do
    for f in "$PROD/$NAME.swiftmodule/"*."$ext"; do
      case "$f" in *.private.swiftinterface|*.package.swiftinterface) continue;; esac
      cp "$f" "$FW/Modules/$NAME.swiftmodule/"
    done
  done
  cp "$GEN"/GeneratedModuleMaps-*/"$NAME-Swift.h" "$FW/Headers/"
  printf 'framework module %s {\n  header "%s-Swift.h"\n  export *\n}\n' "$NAME" "$NAME" > "$FW/Modules/module.modulemap"
  cp -R "$PROD/${NAME}_${NAME}.bundle" "$FW/"
}
assemble ios Release-iphoneos
assemble ios-sim Release-iphonesimulator

xcodebuild -create-xcframework \
  -framework "$WORK/frameworks/ios/$NAME.framework" \
  -framework "$WORK/frameworks/ios-sim/$NAME.framework" \
  -output "$WORK/$NAME.xcframework"

cp "$ROOT/LICENSE.md" "$WORK/"
(cd "$WORK" && zip -qry "$NAME.xcframework.zip" "$NAME.xcframework" LICENSE.md)
echo "Built $WORK/$NAME.xcframework.zip"
shasum -a 256 "$WORK/$NAME.xcframework.zip"
