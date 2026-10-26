#!/bin/bash
# Build a native iOS JVM framework from the actual verified upstream JRE21.
set -euo pipefail
SOURCE_URL="https://assets.angelauramc.dev/openjdk/ios-arm64/jre21-ios-aarch64.zip"
SOURCE_SHA="64043966e5e67e47bd244bb1e27f52367895674699f46693703ebd9a120b73fa"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
curl --fail --location --retry 3 --output "$TEMP/jre21.zip" "$SOURCE_URL"
echo "$SOURCE_SHA  $TEMP/jre21.zip" | shasum -a 256 -c -
unzip -q "$TEMP/jre21.zip" -d "$TEMP/download"
archive="$(find "$TEMP/download" -maxdepth 2 -name 'jre21-*-release.tar.xz' -type f -print -quit)"
[[ -n "$archive" ]] || { echo "No upstream Java 21 tarball"; exit 1; }
mkdir "$TEMP/jre"
tar -xJf "$archive" -C "$TEMP/jre" --no-same-owner
test -s "$TEMP/jre/lib/server/libjvm.dylib"
test -s "$TEMP/jre/lib/modules"
grep -Eq '^JAVA_VERSION="21([.]|")' "$TEMP/jre/release" || { echo "Upstream runtime isn't Java 21"; exit 1; }
mkdir -p Vendor/NovaJava21.framework
ditto "$TEMP/jre/lib/server/libjvm.dylib" Vendor/NovaJava21.framework/NovaJava21
ditto "$TEMP/jre/lib" Vendor/NovaJava21.framework/lib
# Don't keep an extra copy of the JVM executable inside the Java home.
rm -f Vendor/NovaJava21.framework/lib/server/libjvm.dylib
cat > Vendor/NovaJava21.framework/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>pl.novacraft.java21</string>
<key>CFBundleName</key><string>NovaJava21</string>
<key>CFBundleExecutable</key><string>NovaJava21</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>21.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>17.0</string>
</dict></plist>
PLIST
file Vendor/NovaJava21.framework/NovaJava21
du -sh Vendor/NovaJava21.framework
echo "Prepared upstream Java21 runtime. iOS code signing and native dependency loading remain to be verified."
