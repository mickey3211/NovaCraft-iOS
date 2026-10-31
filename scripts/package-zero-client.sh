#!/usr/bin/env bash
set -euo pipefail
APP="${1:?app path}"
COMPONENTS="${2:?component directory}"
mkdir -p "$APP/Frameworks" "$APP/LWJGL-iOS" "$APP/ThirdPartyNotices"
cp "$COMPONENTS/glfw/libglfw.dylib" "$APP/Frameworks/"
cp "$COMPONENTS/mobileglues/libmobileglues.dylib" "$APP/Frameworks/"
cp "$COMPONENTS/openal/libopenal.dylib" "$APP/Frameworks/"
cp "$COMPONENTS/openal/OpenAL-Soft-LICENSE" "$APP/ThirdPartyNotices/"
cp "$COMPONENTS/openal/SOURCES.txt" "$APP/ThirdPartyNotices/OpenAL-Soft-SOURCES.txt"
cp "$COMPONENTS/openal/openal-soft-source.tar.gz" "$APP/ThirdPartyNotices/"
# Package only modules used by the vanilla GL client; do not include Vulkan/VMA.
for name in lwjgl lwjgl_opengl lwjgl_stb freetype; do
  cp "$COMPONENTS/lwjgl/native/lib${name}.dylib" "$APP/Frameworks/"
done
for module in lwjgl lwjgl-glfw lwjgl-opengl lwjgl-stb lwjgl-openal lwjgl-freetype lwjgl-tinyfd; do
  cp "$COMPONENTS/lwjgl/jars/$module/$module.jar" "$APP/LWJGL-iOS/"
done
cp "$COMPONENTS/lwjgl/native/liblwjgl_tinyfd.dylib" "$APP/Frameworks/"
find "$COMPONENTS/lwjgl/jars" -type f -name '*license*' -exec cp {} "$APP/ThirdPartyNotices/" \;
cp "$COMPONENTS/glfw/GLFW-LICENSE.md" "$APP/ThirdPartyNotices/"
cp "$COMPONENTS/mobileglues/MobileGlues-LICENSE" "$APP/ThirdPartyNotices/"
# Keep source notices and the separately licensed renderer's corresponding source.
cp "$COMPONENTS/mobileglues/SOURCES.txt" "$APP/ThirdPartyNotices/MobileGlues-SOURCES.txt"
cp "$COMPONENTS/mobileglues/mobileglues-source.tar.gz" "$APP/ThirdPartyNotices/"
cp "$COMPONENTS/glfw/glfw-modified-source.tar.gz" "$APP/ThirdPartyNotices/"
curl --fail --location --retry 3 --max-time 180 \
  https://github.com/jeremyfa/build-angle/releases/download/angle-af8a791/angle-ios-universal.zip \
  -o "$RUNNER_TEMP/angle-ios.zip"
echo "be74f72d85629265364fe0fba6a3815c3bb77b39f9e9e661f5b148917e38ecf1  $RUNNER_TEMP/angle-ios.zip" | shasum -a 256 -c -
unzip -q "$RUNNER_TEMP/angle-ios.zip" -d "$RUNNER_TEMP/nova-angle"
for lib in libEGL libGLESv2; do
  ditto "$RUNNER_TEMP/nova-angle/$lib.xcframework/ios-arm64/$lib.framework" "$APP/Frameworks/$lib.framework"
  rm -rf "$APP/Frameworks/$lib.framework/Headers" "$APP/Frameworks/$lib.framework/_CodeSignature"
done
curl --fail --location --retry 3 --max-time 60 \
  https://raw.githubusercontent.com/google/angle/af8a791f61e42600c6910280393c5183f701bfd1/LICENSE \
  -o "$APP/ThirdPartyNotices/ANGLE-LICENSE"
printf 'ANGLE af8a791f61e42600c6910280393c5183f701bfd1\nBinary build: https://github.com/jeremyfa/build-angle/releases/tag/angle-af8a791\n' > "$APP/ThirdPartyNotices/ANGLE-SOURCES.txt"
# Match each dylib's install name to its packaged file (upstream FreeType uses
# libfreetype.6.dylib while LWJGL's configured filename is libfreetype.dylib).
for dylib in "$APP/Frameworks/"*.dylib; do
  install_name_tool -id "@rpath/$(basename "$dylib")" "$dylib"
done
# Fail for missing non-system dependencies instead of publishing a broken closure.
python3 scripts/audit-zero-client.py "$APP"
