#!/usr/bin/env bash
# Separately licensed OpenAL Soft; real iOS CoreAudio output, not a silent stub.
set -euo pipefail
: "${RUNNER_TEMP:?CI scratch directory required}"
REV=d3875f333fb6abe2f39d82caca329414871ae53b
WORK="$RUNNER_TEMP/nova-openal"
OUT="$RUNNER_TEMP/nova-openal-component"
mkdir -p "$WORK" "$OUT"
git init "$WORK/source"
git -C "$WORK/source" remote add origin https://github.com/kcat/openal-soft.git
git -C "$WORK/source" fetch --depth 1 origin "$REV"
git -C "$WORK/source" checkout --detach FETCH_HEAD
test "$(git -C "$WORK/source" rev-parse HEAD)" = "$REV"
cmake -S "$WORK/source" -B "$WORK/build" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_NAME_DIR=@rpath \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DLIBTYPE=SHARED -DALSOFT_OSX_FRAMEWORK=OFF \
  -DALSOFT_BACKEND_COREAUDIO=ON -DALSOFT_REQUIRE_COREAUDIO=ON \
  -DALSOFT_BACKEND_PIPEWIRE=OFF -DALSOFT_BACKEND_PULSEAUDIO=OFF \
  -DALSOFT_BACKEND_JACK=OFF -DALSOFT_BACKEND_PORTAUDIO=OFF \
  -DALSOFT_BACKEND_SDL2=OFF -DALSOFT_BACKEND_WAVE=OFF \
  -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
  -DALSOFT_INSTALL=OFF
cmake --build "$WORK/build" --config Release --target OpenAL --parallel 3
# Follow the versioned dylib symlink into a single canonical packaged filename.
cp -L "$WORK/build/libopenal.dylib" "$OUT/libopenal.dylib"
install_name_tool -id @rpath/libopenal.dylib "$OUT/libopenal.dylib"
xcrun lipo "$OUT/libopenal.dylib" -verify_arch arm64
xcrun vtool -show-build "$OUT/libopenal.dylib" | tee "$OUT/platform.txt"
grep -q 'platform IOS' "$OUT/platform.txt"
xcrun nm -gUj "$OUT/libopenal.dylib" > "$OUT/exports.txt"
for symbol in _alcOpenDevice _alcCreateContext _alcIsExtensionPresent _alGetProcAddress _alGenSources _alBufferData; do
  grep -Fx "$symbol" "$OUT/exports.txt"
done
cp "$WORK/source/COPYING" "$OUT/OpenAL-Soft-LICENSE"
printf 'OpenAL Soft 1.23.1\nhttps://github.com/kcat/openal-soft\nCommit %s\n' "$REV" > "$OUT/SOURCES.txt"
tar --exclude='.git' -czf "$OUT/openal-soft-source.tar.gz" -C "$WORK" source
