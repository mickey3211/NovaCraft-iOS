#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_TEMP:?CI scratch directory required}"
ROOT="$PWD"
REV=7b6aead9fb88b3623e3b3725ebb42670cbe4c579
WORK="$RUNNER_TEMP/nova-glfw"
OUT="$RUNNER_TEMP/nova-glfw-component"
mkdir -p "$WORK" "$OUT"
git init "$WORK/source"
git -C "$WORK/source" remote add origin https://github.com/glfw/glfw.git
git -C "$WORK/source" fetch --depth 1 origin "$REV"
git -C "$WORK/source" checkout --detach FETCH_HEAD
python3 scripts/patch-glfw-ios.py "$WORK/source" "$ROOT/Graphics/GLFW"
cmake -S "$WORK/source" -B "$WORK/build" -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON -DGLFW_BUILD_COCOA=OFF -DGLFW_BUILD_X11=OFF \
  -DGLFW_BUILD_WAYLAND=OFF -DGLFW_BUILD_DOCS=OFF -DGLFW_BUILD_TESTS=OFF \
  -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_INSTALL=OFF
cmake --build "$WORK/build" --parallel 3
LIB="$WORK/build/src/libglfw.3.4.dylib"
test -s "$LIB"
xcrun lipo "$LIB" -verify_arch arm64
xcrun vtool -show-build "$LIB" > "$OUT/platform.txt"
grep -q 'platform IOS' "$OUT/platform.txt"
xcrun nm -gUj "$LIB" > "$OUT/exports.txt"
for symbol in _glfwCreateWindow _glfwGetProcAddress _glfwSwapBuffers _glfwPollEvents _nova_glfw_create_view; do
  grep -Fx "$symbol" "$OUT/exports.txt"
done
# Verify every eagerly loaded GLFW entrypoint in our exact LWJGL revision.
LWJGL_REV=39272d4d0ca119379024e3ca7207699fd3fce237
curl --fail --location --retry 3 --max-time 60 \
  "https://raw.githubusercontent.com/PojavLauncherTeam/lwjgl3/$LWJGL_REV/modules/lwjgl/glfw/src/generated/java/org/lwjgl/glfw/GLFW.java" \
  -o "$WORK/GLFW.java"
python3 - "$WORK/GLFW.java" "$OUT/exports.txt" <<'PYTHON'
import re,sys
from pathlib import Path
required={'_'+s for s in re.findall(r'apiGetFunctionAddress\(GLFW, "([^"]+)"',Path(sys.argv[1]).read_text())}
assert len(required) >= 100, 'Unexpected LWJGL source layout'
missing=required-set(Path(sys.argv[2]).read_text().split())
assert not missing, f'Missing LWJGL entrypoints: {sorted(missing)}'
print(f'Validated {len(required)} LWJGL GLFW entrypoints')
PYTHON
cp "$LIB" "$OUT/libglfw.dylib"
install_name_tool -id @rpath/libglfw.dylib "$OUT/libglfw.dylib"
cp "$WORK/source/LICENSE.md" "$OUT/GLFW-LICENSE.md"
cp "$ROOT/Graphics/GLFW/nova_ios_surface.h" "$OUT/"
printf 'GLFW %s, modified by scripts/patch-glfw-ios.py in NovaCraft\n' "$REV" > "$OUT/SOURCES.txt"
tar --exclude='.git' -czf "$OUT/glfw-modified-source.tar.gz" -C "$WORK" source
