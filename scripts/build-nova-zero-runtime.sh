#!/usr/bin/env bash
# Build an internally consistent iOS Zero VM + class modules + runtime data.
# OpenJDK and ios-tools remain separately licensed dependencies.
set -euo pipefail
: "${RUNNER_TEMP:?CI scratch directory required}"
: "${JAVA_HOME:?Boot JDK 26 required}"
ROOT="$PWD"
WORK="$RUNNER_TEMP/nova-zero-source"
mkdir -p "$WORK"
MOBILE_REV=c1ed06aaef34c8dccf71e236d1ffa20918a77cfb
TOOLS_REV=2f0a489b48cdb13901185be051004f7a9c23bf14
MODULES=(java.base java.desktop java.datatransfer java.prefs java.logging java.xml java.net.http java.management java.naming java.security.sasl jdk.unsupported jdk.crypto.ec jdk.charsets jdk.zipfs)
checkout() {
  git init "$2"
  git -C "$2" remote add origin "$1"
  git -C "$2" fetch --depth 1 origin "$3"
  git -C "$2" checkout --detach FETCH_HEAD
  test "$(git -C "$2" rev-parse HEAD)" = "$3"
}
checkout https://github.com/openjdk/mobile.git "$WORK/mobile" "$MOBILE_REV"
checkout https://github.com/openjdk-mobile/ios-tools.git "$WORK/ios-tools" "$TOOLS_REV"
curl --fail --location --retry 3 -o "$WORK/libffi.zip" https://github.com/openjdk-mobile/ios-tools/releases/download/libffi-build/libffi-ios.zip
echo "4f39fd1d53fbd69d1bdbd915413077d130daa3f6792d1b3a03a690a9cbd4dea3  $WORK/libffi.zip" | shasum -a 256 -c -
unzip -q "$WORK/libffi.zip" -d "$WORK/ffi"
FFI_LIB="$(find "$WORK/ffi" -name libffi.a -print -quit)"
FFI_HEADER="$(find "$WORK/ffi" -name ffi.h -print -quit)"
test -n "$FFI_LIB" && test -n "$FFI_HEADER"
cd "$WORK/mobile"
# Do not let the iOS cross configuration generate its own macOS build-JDK:
# that path inherits non-Darwin library suffix/linker flags in this revision.
# Build normal host tools first, before adding iOS-only symbol references.
HOST_JDK="$RUNNER_TEMP/nova-host-jdk"
if [[ ! -x "$HOST_JDK/bin/jmod" ]]; then
  bash configure --with-conf-name=nova-host --with-boot-jdk="$JAVA_HOME" \
    --disable-warnings-as-errors --with-native-debug-symbols=none
  gmake CONF=nova-host JOBS=3 jdk-image
  ditto "$WORK/mobile/build/nova-host/images/jdk" "$HOST_JDK"
fi
"$HOST_JDK/bin/java" -version
cp "$WORK/ios-tools/openjdk-ext/src/hotspot/symbol_keeper.cpp" src/hotspot/os/bsd/
bash configure --with-conf-name=nova-ios-zero --disable-warnings-as-errors \
  --openjdk-target=aarch64-macos-ios --with-jvm-variants=zero \
  --with-boot-jdk="$JAVA_HOME" --with-build-jdk="$HOST_JDK" --with-native-debug-symbols=none \
  --with-sysroot="$(xcrun --sdk iphoneos --show-sdk-path)" \
  --with-libffi-include="$(dirname "$FFI_HEADER")" --with-libffi-lib="$(dirname "$FFI_LIB")" \
  --with-cups-include="$(xcrun --sdk macosx --show-sdk-path)/usr/include"
TARGETS=()
for module in "${MODULES[@]}"; do TARGETS+=("$module-java"); done
gmake CONF=nova-ios-zero JOBS=3 static-libs-image "${TARGETS[@]}" java.base-copy java.base-gendata
BUILD="$WORK/mobile/build/nova-ios-zero"
# Never package the host JVM or native macOS libraries into the iOS app.
BIN="$HOST_JDK/bin"
JMOD="$BIN/jmod"
"$JMOD" --version
mkdir -p "$WORK/jmods" "$WORK/base-data"
test -s "$BUILD/jdk/lib/tzdb.dat"
cp "$BUILD/jdk/lib/tzdb.dat" "$WORK/base-data/"
for module in "${MODULES[@]}"; do
  test -s "$BUILD/jdk/modules/$module/module-info.class"
  EXTRA=()
  if [[ "$module" == java.base ]]; then
    EXTRA+=(--libs "$WORK/base-data")
    if [[ -d "$BUILD/jdk/conf" ]]; then EXTRA+=(--config "$BUILD/jdk/conf"); fi
  fi
  "$JMOD" create --class-path "$BUILD/jdk/modules/$module" --target-platform ios-aarch64 \
    "${EXTRA[@]}" "$WORK/jmods/$module.jmod"
done
MODULE_CSV="$(IFS=,; echo "${MODULES[*]}")"
"$BIN/jlink" --module-path "$WORK/jmods" --add-modules "$MODULE_CSV" \
  --output "$WORK/runtime" --disable-plugin generate-jli-classes
"$BIN/jimage" list "$WORK/runtime/lib/modules" > "$WORK/modules-inventory.txt"
for module in "${MODULES[@]}"; do grep -F "Module: $module" "$WORK/modules-inventory.txt"; done
test -s "$WORK/runtime/lib/tzdb.dat"
# Retain all built static class libraries; final linkage resolves only references.
mkdir -p "$WORK/static" "$ROOT/ZeroIntegration/Resources" "$WORK/headers"
cp "$BUILD/jdk/include/"*.h "$WORK/headers/"
cp "$BUILD/jdk/include/ios/"*.h "$WORK/headers/"
libtool -static -o "$WORK/static/libNovaOpenJDK.a" \
  "$BUILD/images/static-libs/lib/zero/libjvm.a" \
  "$BUILD/images/static-libs/lib/"*.a "$FFI_LIB"
xcodebuild -create-xcframework -library "$WORK/static/libNovaOpenJDK.a" \
  -headers "$WORK/headers" -output "$ROOT/ZeroIntegration/OpenJDK.xcframework"
# JNI home discovery expects NovaCraft.app/lib/lib/modules (verified on device).
ditto "$WORK/runtime" "$ROOT/ZeroIntegration/Resources/lib"
cp "$WORK/modules-inventory.txt" "$ROOT/ZeroIntegration/Resources/runtime-modules.txt"
mkdir -p "$ROOT/ZeroIntegration/Resources/RuntimeLicenses"
cp LICENSE ASSEMBLY_EXCEPTION ADDITIONAL_LICENSE_INFO "$ROOT/ZeroIntegration/Resources/RuntimeLicenses/"
cp "$WORK/ios-tools/LICENSE" "$ROOT/ZeroIntegration/Resources/RuntimeLicenses/ios-tools-LICENSE"
printf 'OpenJDK/mobile: %s\nios-tools: %s\n' "$MOBILE_REV" "$TOOLS_REV" > "$ROOT/ZeroIntegration/Resources/RuntimeLicenses/SOURCES.txt"
