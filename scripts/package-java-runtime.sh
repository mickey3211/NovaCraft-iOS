#!/bin/bash
set -euo pipefail

# Package a separately supplied, iOS-arm64 compatible JVM framework.
# The repository intentionally does not contain a JVM binary.
APP="${1:?Usage: package-java-runtime.sh path/to/NovaCraft.app}"
SOURCE="Vendor/NovaJavaRuntime.framework"
if [[ ! -d "$SOURCE" ]]; then
  echo "No iOS Java 21 runtime supplied; building launcher without JVM."
  exit 0
fi
BINARY="$SOURCE/NovaJavaRuntime"
test -f "$BINARY" || { echo "Missing framework binary"; exit 1; }
file "$BINARY"
if ! lipo -archs "$BINARY" | grep -qw arm64; then
  echo "JVM framework does not contain arm64"; exit 1
fi
if ! xcrun nm -gU "$BINARY" | grep -q 'JNI_CreateJavaVM'; then
  echo "JVM framework does not export JNI_CreateJavaVM"; exit 1
fi
mkdir -p "$APP/Frameworks"
ditto "$SOURCE" "$APP/Frameworks/NovaJavaRuntime.framework"
echo "Embedded JVM framework. Final IPA signing must include nested frameworks."
