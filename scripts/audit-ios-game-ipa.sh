#!/bin/bash
# Audit an unsigned NovaCraft app before offering it for iPhone signing.
set -euo pipefail
[[ $# -ge 1 ]] || { echo "Usage: audit-ios-game-ipa.sh path/to/NovaCraft.app"; exit 1; }
APP="$1"
FRAME="$APP/Frameworks/NovaJava21.framework"
[[ -s "$FRAME/NovaJava21" ]] || { echo "Missing Java21 framework executable"; exit 1; }
[[ -s "$FRAME/lib/libjli.dylib" ]] || { echo "Missing Java Launcher Interface"; exit 1; }
[[ -s "$FRAME/lib/server/libjvm.dylib" ]] || { echo "Missing Java21 libjvm under JAVA_HOME"; exit 1; }
[[ -s "$FRAME/lib/modules" ]] || { echo "Missing Java21 modules"; exit 1; }
[[ -s "$APP/Frameworks/liblwjgl.dylib" ]] || { echo "Missing LWJGL native"; exit 1; }
[[ -s "$APP/LWJGL-iOS/lwjgl.jar" ]] || { echo "Missing LWJGL jar"; exit 1; }

echo "Checking OpenJDK JNI and JLI entrypoints…"
xcrun nm -gU "$FRAME/lib/libjli.dylib" | grep -F '_JLI_Launch' || {
  echo "JLI_Launch not exported"; exit 1;
}
xcrun nm -gU "$FRAME/NovaJava21" | grep -F '_JNI_CreateJavaVM' || {
  echo "JNI_CreateJavaVM not exported"; exit 1;
}
inventory="$PWD/ios-native-signing-inventory.txt"
: > "$inventory"
while IFS= read -r -d '' bin; do
  [[ -s "$bin" ]] || continue
  if file -b "$bin" | grep -q 'Mach-O'; then
    echo "$bin" | sed "s|^$APP/||" >> "$inventory"
    if [[ "$bin" == *.dylib || "$bin" == "$FRAME/NovaJava21" ]]; then
      lipo -archs "$bin" | grep -qw arm64 || {
        echo "Non-arm64 executable: $bin"; exit 1;
      }
      xcrun vtool -show-build "$bin" | grep -Eq 'platform (IOS|2)([[:space:]]|$)' || {
        echo "Not an iOS executable: $bin"; exit 1;
      }
    fi
  fi
done < <(find "$APP/Frameworks" -type f -print0)
sort -u "$inventory" -o "$inventory"
echo "Mach-O binaries to sign individually: $(wc -l < "$inventory" | tr -d ' ')"
echo "WARNING: iPASide must sign all nested native binaries, not only the outer .app."
