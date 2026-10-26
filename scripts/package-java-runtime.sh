#!/bin/bash
set -euo pipefail

# Optional signed-code packaging for a separately supplied iOS ARM64 Java 21
# framework. This does not build OpenJDK or supply the framework binary.
APP="${1:?Usage: package-java-runtime.sh path/to/NovaCraft.app}"
SOURCE="Vendor/NovaJavaRuntime.framework"
if [[ ! -d "$SOURCE" ]]; then
  echo "No iOS Java runtime supplied; building launcher without JVM."
  exit 0
fi
BINARY="$SOURCE/NovaJavaRuntime"
PLIST="$SOURCE/Info.plist"
test -f "$BINARY" || { echo "Missing framework executable"; exit 1; }
test -f "$PLIST" || { echo "Missing framework Info.plist"; exit 1; }

IDENTIFIER=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$PLIST")
EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$PLIST")
[[ "$EXECUTABLE" == "NovaJavaRuntime" ]] || { echo "Incorrect CFBundleExecutable"; exit 1; }
[[ -n "$IDENTIFIER" ]] || { echo "Missing bundle identifier"; exit 1; }

if ! lipo -archs "$BINARY" | grep -qw arm64; then
  echo "JVM framework does not contain arm64"; exit 1
fi

# macOS arm64 and iOS arm64 are NOT interchangeable. Check Mach-O build
# platform on an arm64 slice, not just the CPU architecture.
TMPDIR_JVM=$(mktemp -d)
trap 'rm -rf "$TMPDIR_JVM"' EXIT
lipo "$BINARY" -thin arm64 -output "$TMPDIR_JVM/runtime"
if ! xcrun vtool -show-build "$TMPDIR_JVM/runtime" | grep -Eq 'platform (IOS|2)([[:space:]]|$)'; then
  echo "JVM binary is not built for iOS (device). macOS/simulator frameworks are rejected."
  exit 1
fi

if ! xcrun nm -gU "$TMPDIR_JVM/runtime" | grep -q '_JNI_CreateJavaVM'; then
  echo "JVM framework does not export JNI_CreateJavaVM"
  exit 1
fi
if ! xcrun nm -gU "$TMPDIR_JVM/runtime" | grep -q '_JNI_GetCreatedJavaVMs'; then
  echo "JVM framework does not export JNI_GetCreatedJavaVMs"
  exit 1
fi

mkdir -p "$APP/Frameworks"
ditto "$SOURCE" "$APP/Frameworks/NovaJavaRuntime.framework"
echo "Validated iOS arm64 JNI framework embedded."
echo "The app and ALL embedded executable dependencies must be signed before installation."
