#!/usr/bin/env bash
# NovaCraft iOS: unsigned Java 21 + iOS LWJGL IPA on Codemagic personal free M2.
# This reproduces the verified-dependency steps in build-ios-lwjgl.yml.
# The output is UNSIGNED. iPASide must sign the app and every nested Mach-O.
set -euo pipefail

cd "$CM_BUILD_DIR"
ROOT="$PWD"
LOGS="$ROOT/dist/build-logs"
mkdir -p "$LOGS"
TEMP_WORK="$(mktemp -d)"
trap 'rm -rf "$TEMP_WORK"' EXIT

# Codemagic Xcode 16.4 image includes Azul Zulu Java 8; LWJGL iOS uses Ant/JDK8.
JAVA8_HOME="/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home"
if [[ ! -x "$JAVA8_HOME/bin/java" ]]; then
    JAVA8_HOME="$(/usr/libexec/java_home -v 1.8)"
fi
[[ -x "$JAVA8_HOME/bin/java" ]] || { echo "Missing Java 8 JDK"; exit 1; }
export JAVA8_HOME
export JAVA_HOME="$JAVA8_HOME"
export PATH="$JAVA8_HOME/bin:/opt/homebrew/bin:$PATH"
echo "Java 8: $JAVA8_HOME"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"

for tool in ant wget xcodegen; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        brew install "$tool"
    fi
done

# Compile Swift first, before using free minutes to build the large LWJGL fork.
# The Xcode target does not link Java/LWJGL until after the .app is built.
python3 -m venv "$TEMP_WORK/icon-venv"
"$TEMP_WORK/icon-venv/bin/python" -m pip install --disable-pip-version-check pillow
"$TEMP_WORK/icon-venv/bin/python" scripts/generate-app-icon.py
xcodegen generate

echo "Building unsigned NovaCraft iOS app"
xcodebuild -project NovaCraft.xcodeproj -scheme NovaCraft \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$TEMP_WORK/DerivedData" CODE_SIGNING_ALLOWED=NO build \
    2>&1 | tee "$LOGS/xcodebuild.log"

APP="$TEMP_WORK/DerivedData/Build/Products/Release-iphoneos/NovaCraft.app"
[[ -d "$APP" ]] || { echo "Missing NovaCraft.app"; exit 1; }

UPSTREAM_REV="39272d4d0ca119379024e3ca7207699fd3fce237"
LWJGL_SOURCE="$TEMP_WORK/lwjgl3"
echo "Fetching pinned iOS LWJGL commit $UPSTREAM_REV"
git clone https://github.com/PojavLauncherTeam/lwjgl3.git "$LWJGL_SOURCE"
git -C "$LWJGL_SOURCE" checkout --detach "$UPSTREAM_REV"

# SHA256-pinned iOS libffi to avoid Xcode 16.4 invalid-CFI build failures.
curl --fail --location --retry 3 \
    --output "$TEMP_WORK/libffi-ios.zip" \
    "https://github.com/openjdk-mobile/ios-tools/releases/download/libffi-build/libffi-ios.zip"
echo "4f39fd1d53fbd69d1bdbd915413077d130daa3f6792d1b3a03a690a9cbd4dea3  $TEMP_WORK/libffi-ios.zip" | shasum -a 256 -c -
mkdir -p "$TEMP_WORK/libffi-content"
unzip -q "$TEMP_WORK/libffi-ios.zip" -d "$TEMP_WORK/libffi-content"
LIBFFI="$(find "$TEMP_WORK/libffi-content" -type f -name 'libffi.a' -print -quit)"
[[ -n "$LIBFFI" ]] || { echo "Missing iOS libffi.a"; exit 1; }

cd "$LWJGL_SOURCE"
mkdir -p bin/libs/native/macos/arm64/org/lwjgl
cp "$LIBFFI" bin/libs/native/macos/arm64/org/lwjgl/libffi.a

# The upstream shaderc nightly URL is gone. Vanilla OpenGL does not use shaderc.
# Mirror the same narrowly scoped upstream patch already used by NovaCraft CI.
python3 - <<'PY'
from pathlib import Path
p = Path("ci_build_ios.bash")
s = p.read_text()
s = s.replace('wget -nc "https://nightly.link/PojavLauncherTeam/shaderc/workflows/ios/main/libshaderc.zip"', ': # upstream shaderc nightly unavailable')
s = s.replace('unzip -o libshaderc.zip -d $LWJGL_NATIVE/shaderc', ': # no shaderc')
s = s.replace('rm $LWJGL_NATIVE/shaderc/libshaderc_shared.1.dylib', ': # no shaderc')
s = s.replace('mv $LWJGL_NATIVE/shaderc/libshaderc_shared.dylib $LWJGL_NATIVE/shaderc/libshaderc.dylib', ': # no shaderc')
s = s.replace('cp $LWJGL_NATIVE/shaderc/libshaderc.dylib bin/out/', ': # no shaderc')
s = s.replace('  -Dbinding.assimp=false \\', '  -Dbinding.assimp=false \\\n  -Dbinding.shaderc=false \\')
p.write_text(s)
PY

echo "Building iOS LWJGL (log: dist/build-logs/lwjgl-build.log)"
SKIP_LIBFFI=1 bash ci_build_ios.bash 2>&1 | tee "$LOGS/lwjgl-build.log"
[[ -d bin/RELEASE && -d bin/out ]] || { echo "LWJGL build did not create output"; exit 1; }

cd "$ROOT"
mkdir -p Vendor/LWJGL-iOS/jars Vendor/LWJGL-iOS/native
find "$LWJGL_SOURCE/bin/RELEASE" -type f -name '*.jar' \
    ! -name '*-natives-*' ! -name '*-sources.jar' \
    -exec cp {} Vendor/LWJGL-iOS/jars/ \;
cp "$LWJGL_SOURCE/bin/out/"*.dylib Vendor/LWJGL-iOS/native/
[[ -s Vendor/LWJGL-iOS/native/liblwjgl.dylib ]] || { echo "Missing liblwjgl.dylib"; exit 1; }
[[ -n "$(find Vendor/LWJGL-iOS/jars -maxdepth 1 -name '*.jar' -print -quit)" ]] || { echo "Missing LWJGL jars"; exit 1; }

echo "Downloading checksum-verified iOS Java 21 runtime"
bash scripts/build-vendor-ios-jre21.sh 2>&1 | tee "$LOGS/java-runtime.log"

bash scripts/package-java-runtime.sh "$APP"
bash scripts/package-upstream-lwjgl-ios.sh "$APP"
bash scripts/package-nova-bootstrap.sh "$APP"
[[ -s "$APP/NovaBootstrap/novacraft-bootstrap.jar" ]] || exit 1
[[ -s "$APP/Frameworks/NovaJava21.framework/NovaJava21" ]] || exit 1
[[ -s "$APP/Frameworks/liblwjgl.dylib" ]] || exit 1
[[ -s "$APP/LWJGL-iOS/lwjgl.jar" ]] || exit 1
bash scripts/audit-ios-game-ipa.sh "$APP" 2>&1 | tee "$LOGS/ipa-audit.log"
cp ios-native-signing-inventory.txt dist/ios-native-signing-inventory.txt

mkdir -p "$TEMP_WORK/ipa/Payload"
ditto "$APP" "$TEMP_WORK/ipa/Payload/NovaCraft.app"
cd "$TEMP_WORK/ipa"
zip -qry "$ROOT/dist/NovaCraft-Java21-LWJGL-UNSIGNED.ipa" Payload
[[ -s "$ROOT/dist/NovaCraft-Java21-LWJGL-UNSIGNED.ipa" ]] || exit 1
ls -lh "$ROOT/dist/NovaCraft-Java21-LWJGL-UNSIGNED.ipa"
echo "Unsigned IPA ready. Sign ALL embedded Mach-O libraries and frameworks before installing."
