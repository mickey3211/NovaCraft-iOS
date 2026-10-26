#!/bin/bash
set -euo pipefail
APP="${1:?Usage: package-java-runtime.sh path/to/NovaCraft.app}"
[[ -d "$APP" ]] || { echo "Missing app bundle"; exit 1; }

validate_and_copy() {
  local name="$1" source="Vendor/$1.framework"
  local binary="$source/$name" plist="$source/Info.plist"
  [[ -d "$source" ]] || return 0
  [[ -f "$binary" && -f "$plist" ]] || { echo "Incomplete $name"; exit 1; }
  local executable identifier
  executable=$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$plist")
  identifier=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$plist")
  [[ "$executable" == "$name" && -n "$identifier" ]] || { echo "Invalid $name Info.plist"; exit 1; }
  lipo -archs "$binary" | grep -qw arm64 || { echo "$name lacks arm64"; exit 1; }
  local tmp
  tmp=$(mktemp)
  if [[ "$(lipo -archs "$binary" | wc -w | tr -d ' ')" -gt 1 ]]; then
    lipo "$binary" -thin arm64 -output "$tmp"
  else
    cp "$binary" "$tmp"
  fi
  if ! xcrun vtool -show-build "$tmp" | grep -Eq 'platform (IOS|2)([[:space:]]|$)'; then
    rm -f "$tmp"
    echo "$name is not built for iOS device"
    exit 1
  fi
  local symbols
  symbols=$(xcrun nm -gU "$tmp")
  rm -f "$tmp"
  grep -q '_JNI_CreateJavaVM' <<< "$symbols" || { echo "$name missing JNI_CreateJavaVM"; exit 1; }
  grep -q '_JNI_GetCreatedJavaVMs' <<< "$symbols" || { echo "$name missing JNI_GetCreatedJavaVMs"; exit 1; }
  mkdir -p "$APP/Frameworks"
  ditto "$source" "$APP/Frameworks/$name.framework"
  echo "Embedded $name (iOS arm64)."
}

count=0
for major in 8 16 17 21 25; do
  if [[ -d "Vendor/NovaJava${major}.framework" ]]; then
    validate_and_copy "NovaJava${major}"
    count=$((count + 1))
  fi
done
if [[ -d Vendor/NovaJavaRuntime.framework ]]; then
  validate_and_copy "NovaJavaRuntime"
  count=$((count + 1))
fi
if (( count == 0 )); then
  echo "No iOS JVM binaries provided. IPA cannot launch Minecraft Java."
else
  echo "Embedded $count JVM framework(s). All executable code must be signed when installing IPA."
fi
; then
    if [[ "$(lipo -archs "$binary" | wc -w | tr -d ' ')" -gt 1 ]]; then
      lipo "$binary" -thin arm64 -output "$tmp"
    else
      cp "$binary" "$tmp"
    fi
  fi
  if ! xcrun vtool -show-build "$tmp" | grep -Eq 'platform (IOS|2)([[:space:]]|$)'; then
    rm -f "$tmp"
    echo "$name is not built for iOS device"
    exit 1
  fi
  local symbols
  symbols=$(xcrun nm -gU "$tmp")
  rm -f "$tmp"
  grep -q '_JNI_CreateJavaVM' <<< "$symbols" || { echo "$name missing JNI_CreateJavaVM"; exit 1; }
  grep -q '_JNI_GetCreatedJavaVMs' <<< "$symbols" || { echo "$name missing JNI_GetCreatedJavaVMs"; exit 1; }
  mkdir -p "$APP/Frameworks"
  ditto "$source" "$APP/Frameworks/$name.framework"
  echo "Embedded $name (iOS arm64)."
}

count=0
for major in 8 16 17 21 25; do
  if [[ -d "Vendor/NovaJava${major}.framework" ]]; then
    validate_and_copy "NovaJava${major}"
    count=$((count + 1))
  fi
done
if [[ -d Vendor/NovaJavaRuntime.framework ]]; then
  validate_and_copy "NovaJavaRuntime"
  count=$((count + 1))
fi
if (( count == 0 )); then
  echo "No iOS JVM binaries provided. IPA cannot launch Minecraft Java."
else
  echo "Embedded $count JVM framework(s). All executable code must be signed when installing IPA."
fi
