#!/usr/bin/env bash
# Separately licensed renderer dependency; does not implement NovaCraft's GLFW bridge.
set -euo pipefail
: "${RUNNER_TEMP:?CI scratch directory required}"
MG_REV=fcdf91456c1b3b5e77e5264cffe682595c13113f
TOOLCHAIN_REV=b36d5bce6f9a2d11d9f144bd5882ba31cfdca420
WORK="$RUNNER_TEMP/nova-mobileglues"
OUT="$RUNNER_TEMP/nova-graphics-component"
mkdir -p "$WORK" "$OUT"
git init "$WORK/source"
git -C "$WORK/source" remote add origin https://github.com/MobileGL-Dev/MobileGlues.git
git -C "$WORK/source" fetch --depth 1 origin "$MG_REV"
git -C "$WORK/source" checkout --detach FETCH_HEAD
test "$(git -C "$WORK/source" rev-parse HEAD)" = "$MG_REV"
# Perfetto is unused with PROFILING=OFF; all required submodules use gitlink pins.
git -C "$WORK/source" submodule update --init --recursive --depth 1 -- \
  MobileGlues-cpp/3rdparty/xxhash MobileGlues-cpp/3rdparty/glslang \
  MobileGlues-cpp/3rdparty/SPIRV-Cross MobileGlues-cpp/include/ska
git init "$WORK/toolchain"
git -C "$WORK/toolchain" remote add origin https://github.com/leetal/ios-cmake.git
git -C "$WORK/toolchain" fetch --depth 1 origin "$TOOLCHAIN_REV"
git -C "$WORK/toolchain" checkout --detach FETCH_HEAD
cmake -S "$WORK/source/MobileGlues-cpp" -B "$WORK/build" \
  -DCMAKE_TOOLCHAIN_FILE="$WORK/toolchain/ios.toolchain.cmake" \
  -DMACOS=ON -DPLATFORM=OS64 -DDEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_FLAGS=-Wno-error=implicit-function-declaration
cmake --build "$WORK/build" --config RelWithDebInfo --target mobileglues --parallel 3
LIB="$WORK/build/libmobileglues.dylib"
test -s "$LIB"
xcrun lipo "$LIB" -verify_arch arm64
xcrun vtool -show-build "$LIB" | tee "$OUT/platform.txt"
grep -q 'platform IOS' "$OUT/platform.txt"
xcrun nm -gUj "$LIB" > "$OUT/exports.txt"
for symbol in _glGetString _glClear _glDrawElements _glCreateShader; do
  grep -Fx "$symbol" "$OUT/exports.txt"
done
otool -L "$LIB" > "$OUT/dependencies.txt"
cp "$LIB" "$OUT/"
cp "$WORK/source/LICENSE" "$OUT/MobileGlues-LICENSE"
printf 'MobileGlues %s\nios-cmake %s\n' "$MG_REV" "$TOOLCHAIN_REV" > "$OUT/SOURCES.txt"
git -C "$WORK/source" submodule status --recursive >> "$OUT/SOURCES.txt"
# Corresponding source and included notices accompany the compiled library.
tar --exclude='.git' -czf "$OUT/mobileglues-source.tar.gz" -C "$WORK" source toolchain
cat > "$OUT/README.txt" <<'NOTICE'
Compiled iOS ARM64 OpenGL translation dependency, not a runnable app.
No Amethyst application code is included. MobileGlues is LGPL-2.1.
The binary still requires its EGL/GLES frameworks, a native window/context,
LWJGL bindings and NovaCraft's GLFW bridge. Those are not supplied here.
No Minecraft frame or iOS 27 device execution is established by this build.
NOTICE
