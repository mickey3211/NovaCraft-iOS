#!/usr/bin/env bash
set -euo pipefail
# Builds the REAL iOS ARM64 OpenJDK Zero static JVM from OpenJDK/mobile sources.
# Not a runnable NovaCraft framework: linking libjvm.a together with JDK native
# libraries/class library modules into a signed iOS framework is subsequent work.
# Usage:
#   OPENJDK_MOBILE_SRC=/path/to/mobile IOS_JDK_SUPPORT=/path/to/support \
#   BOOT_JDK=/path/to/jdk24/Contents/Home bash scripts/build-openjdk-mobile-ios.sh
: "${OPENJDK_MOBILE_SRC:?Set OPENJDK_MOBILE_SRC to a checkout of https://github.com/openjdk/mobile}"
: "${IOS_JDK_SUPPORT:?Set IOS_JDK_SUPPORT to the extracted iOS libffi/cups support directory}"
: "${BOOT_JDK:?Set BOOT_JDK to a JDK24 home for building OpenJDK/mobile}"
[[ "$(uname -s)" == "Darwin" ]] || { echo "macOS and Xcode are required"; exit 1; }
[[ -f "$OPENJDK_MOBILE_SRC/configure" ]] || { echo "Invalid OpenJDK/mobile checkout"; exit 1; }
[[ -f "$IOS_JDK_SUPPORT/libffi/include/ffi.h" ]] || { echo "Missing iOS libffi headers"; exit 1; }
[[ -d "$IOS_JDK_SUPPORT/libffi/libs" ]] || { echo "Missing iOS libffi libraries"; exit 1; }
[[ -d "$IOS_JDK_SUPPORT/cups-2.3.6" ]] || { echo "Missing CUPS iOS headers"; exit 1; }
[[ -x "$BOOT_JDK/bin/java" ]] || { echo "Invalid boot JDK"; exit 1; }
command -v xcrun >/dev/null
command -v autoconf >/dev/null
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
SRC="$(cd "$OPENJDK_MOBILE_SRC" && pwd)"
SUPPORT="$(cd "$IOS_JDK_SUPPORT" && pwd)"
BOOT="$(cd "$BOOT_JDK" && pwd)"
cd "$SRC"
bash configure \
  --with-conf-name=ios-aarch64-zero-release \
  --disable-warnings-as-errors \
  --openjdk-target=aarch64-macos-ios \
  --with-jvm-variants=zero \
  --with-boot-jdk="$BOOT" \
  --with-libffi-include="$SUPPORT/libffi/include" \
  --with-libffi-lib="$SUPPORT/libffi/libs" \
  --with-cups-include="$SUPPORT/cups-2.3.6" \
  --with-sysroot="$SDK"
CONF="build/ios-aarch64-zero-release"
[[ -d "$CONF" ]] || { echo "OpenJDK iOS build configuration not found"; exit 1; }
make CONF="$(basename "$CONF")" static-libs-image
JVM="$CONF/images/static-libs/lib/zero/libjvm.a"
[[ -n "$JVM" && -s "$JVM" ]] || { echo "No static iOS Zero JVM library found"; exit 1; }
echo "Built iOS JVM static archive: $JVM"
echo "IMPORTANT: This archive cannot be dlopen()'d; NovaCraft still needs a signed framework and JDK classes."
