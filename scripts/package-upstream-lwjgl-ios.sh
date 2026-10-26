#!/bin/bash
set -euo pipefail
APP="${1:?Usage: package-upstream-lwjgl-ios.sh path/to/NovaCraft.app}"
SOURCE="Vendor/LWJGL-iOS"
[[ -d "$SOURCE" ]] || { echo "Upstream LWJGL iOS not supplied; skipping."; exit 0; }
[[ -d "$SOURCE/jars" && -d "$SOURCE/native" ]] || { echo "Expected jars/ and native/ subfolders"; exit 1; }
shopt -s nullglob
JARS=("$SOURCE"/jars/*.jar)
NATIVES=("$SOURCE"/native/*.dylib)
(( ${#JARS[@]} > 0 && ${#NATIVES[@]} > 0 )) || { echo "Missing LWJGL jars or dylibs"; exit 1; }
mkdir -p "$APP/LWJGL-iOS" "$APP/Frameworks"
for jar in "${JARS[@]}"; do
  ditto "$jar" "$APP/LWJGL-iOS/$(basename "$jar")"
done
for dylib in "${NATIVES[@]}"; do
  lipo -archs "$dylib" | grep -qw arm64 || { echo "Not arm64: $dylib"; exit 1; }
  TMP=$(mktemp)
  if [[ "$(lipo -archs "$dylib" | wc -w | tr -d ' ')" -gt 1 ]]; then
    lipo "$dylib" -thin arm64 -output "$TMP"
  else
    cp "$dylib" "$TMP"
  fi
  if ! xcrun vtool -show-build "$TMP" | grep -Eq 'platform (IOS|2)([[:space:]]|$)'; then
    rm -f "$TMP"; echo "Not iOS device: $dylib"; exit 1
  fi
  rm -f "$TMP"
  ditto "$dylib" "$APP/Frameworks/$(basename "$dylib")"
done
echo "Installed upstream LWJGL Java jars and iOS dylibs. All dylibs require signing before install."
