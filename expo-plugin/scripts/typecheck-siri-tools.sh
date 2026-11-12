#!/bin/sh
# Type-checks generated Siri tool Swift against the real SyrupAIKit sources and the iOS 27.3 SDK, the way the app
# target compiles it: with SIRI_AI_PREVIEW on, in Swift 5 and Swift 6 language modes, once as an evaluation build
# (SIRI_AI_EVAL_SWITCHES on), and once with the preview off.
#
# Usage: expo-plugin/scripts/typecheck-siri-tools.sh [swift files...]
# Defaults to the approved sample in plugin/src/__tests__/fixtures/siri-tools.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
TARGET=arm64-apple-ios27.3
OUT="$ROOT/.build/siri-tools-typecheck"

if [ "$#" -eq 0 ]; then
  set -- "$HERE"/../plugin/src/__tests__/fixtures/siri-tools/*.swift
fi

mkdir -p "$OUT"
xcrun -sdk iphoneos swiftc -emit-module -parse-as-library -module-name SyrupAIKit -target "$TARGET" -swift-version 6 \
  -emit-module-path "$OUT/SyrupAIKit.swiftmodule" "$ROOT"/Sources/SyrupAIKit/*.swift

for mode in 5 6; do
  echo "Swift $mode, SIRI_AI_PREVIEW on: $*"
  xcrun -sdk iphoneos swiftc -typecheck -parse-as-library -target "$TARGET" -swift-version "$mode" \
    -D SIRI_AI_PREVIEW -I "$OUT" "$@"
done

echo "Swift 6, SIRI_AI_PREVIEW and SIRI_AI_EVAL_SWITCHES on"
xcrun -sdk iphoneos swiftc -typecheck -parse-as-library -target "$TARGET" -swift-version 6 \
  -D SIRI_AI_PREVIEW -D SIRI_AI_EVAL_SWITCHES -I "$OUT" "$@"

echo "Swift 6, SIRI_AI_PREVIEW off"
xcrun -sdk iphoneos swiftc -typecheck -parse-as-library -target "$TARGET" -swift-version 6 -I "$OUT" "$@"

echo "OK"
