#!/usr/bin/env python3
"""Disable the optional shaderc LWJGL binding in upstream's iOS source build.

The pinned fork's shaderc nightly download is HTTP 404. Vanilla Minecraft
uses GLFW/OpenGL, not the shaderc compilation binding.
"""
from pathlib import Path
p = Path("ci_build_ios.bash")
s = p.read_text()
lines = s.splitlines(keepends=True)
unneeded = (
    'wget -nc "https://nightly.link/PojavLauncherTeam/shaderc/',
    'unzip -o libshaderc.zip',
    'rm $LWJGL_NATIVE/shaderc/libshaderc_shared',
    'mv $LWJGL_NATIVE/shaderc/',
    'cp $LWJGL_NATIVE/shaderc/libshaderc.dylib',
)
filtered = [line for line in lines if not line.lstrip().startswith(unneeded)]
if len(filtered) == len(lines):
    raise SystemExit("Upstream build script changed: shaderc download not found")
s = "".join(filtered)
needle = '  -Dbinding.spvc=false \\\n'
if needle not in s:
    raise SystemExit("Upstream binding selection changed")
s = s.replace(needle, needle + '  -Dbinding.shaderc=false \\\n')
p.write_text(s)
print("Disabled optional shaderc iOS dependency and binding.")
