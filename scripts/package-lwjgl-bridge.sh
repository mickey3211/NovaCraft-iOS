#!/bin/bash
set -euo pipefail

# Optional native graphics bridge supplied as an actual signed iOS framework.
# A placeholder binary is not a LWJGL implementation.
APP="${1:?Usage: package-lwjgl-bridge.sh path/to/NovaCraft.app}"
SOURCE="Vendor/NovaLWJGLBridge.framework"
[[ -d "$SOURCE" ]] || { echo "No iOS LWJGL bridge supplied; Minecraft graphics unavailable."; exit 0; }
BINARY="$SOURCE/NovaLWJGLBridge"
PLIST="$SOURCE/Info.plist"
[[ -f "$BINARY" && -f "$PLIST" ]] || { echo "LWJGL framework is incomplete"; exit 1; }
EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$PLIST")
[[ "$EXECUTABLE" == "NovaLWJGLBridge" ]] || { echo "Invalid LWJGL framework executable"; exit 1; }
lipo -archs "$BINARY" | grep -qw arm64 || { echo "LWJGL framework lacks arm64"; exit 1; }
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
lipo "$BINARY" -thin arm64 -output "$TMP"
xcrun vtool -show-build "$TMP" | grep -Eq 'platform (IOS|2)([[:space:]]|$)' || {
  echo "LWJGL framework is not compiled for physical iOS devices"
  exit 1
}
mkdir -p "$APP/Frameworks"
ditto "$SOURCE" "$APP/Frameworks/NovaLWJGLBridge.framework"
echo "Embedded iOS native LWJGL bridge; final IPA signing must sign this framework."
