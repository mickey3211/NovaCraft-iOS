#!/usr/bin/env python3
"""Generate a sharp, deterministic NovaCraft home screen icon at 1024x1024."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
img = Image.new("RGB", (S, S), (6, 13, 31))
px = img.load()
for y in range(S):
    for x in range(S):
        t = y / (S - 1)
        glow = max(0, 1 - (((x - 512) / 640) ** 2 + ((y - 350) / 650) ** 2))
        px[x, y] = (
            int(7 + 9 * (1-t) + 4 * glow),
            int(15 + 28 * (1-t) + 26 * glow),
            int(38 + 31 * (1-t) + 39 * glow),
        )

glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
g = ImageDraw.Draw(glow)
g.ellipse((180, 80, 845, 845), fill=(0, 186, 255, 85))
glow = glow.filter(ImageFilter.GaussianBlur(105))
img = Image.alpha_composite(img.convert("RGBA"), glow)
d = ImageDraw.Draw(img)

# Isometric voxel floating world, with dark sides and a diamond-blue top.
d.polygon([(140, 565), (514, 365), (888, 565), (514, 766)], fill=(3, 32, 63, 255))
d.polygon([(140, 565), (514, 766), (514, 851), (140, 651)], fill=(8, 85, 137, 255))
d.polygon([(514, 766), (888, 565), (888, 651), (514, 851)], fill=(4, 48, 94, 255))
d.line([(140, 565), (514, 365), (888, 565), (514, 766), (140, 565)], fill=(45, 225, 255, 255), width=17, joint="curve")
# Cyan circuit-style voxel highlights
for coords in [
    [(205, 574), (294, 619), (374, 580)],
    [(641, 555), (713, 515), (799, 564)],
    [(225, 656), (310, 706), (310, 744)],
    [(716, 700), (810, 646)],
]:
    d.line(coords, fill=(56, 194, 253, 255), width=10, joint="curve")

# Minecraft-like crystal: visible stacked pixel facets
d.polygon([(515, 285), (661, 414), (609, 613), (515, 696), (412, 600), (366, 423)], fill=(19, 173, 235, 255))
d.polygon([(515, 285), (661, 414), (515, 460), (366, 423)], fill=(109, 235, 255, 255))
d.polygon([(366, 423), (515, 460), (515, 696), (412, 600)], fill=(3, 95, 172, 255))
d.polygon([(515, 460), (661, 414), (609, 613), (515, 696)], fill=(4, 142, 216, 255))
d.polygon([(472, 345), (518, 304), (564, 348), (521, 394)], fill=(230, 255, 255, 255))
d.line([(515, 285), (661, 414), (609, 613), (515, 696), (412, 600), (366, 423), (515, 285)], fill=(168, 251, 255, 255), width=12, joint="curve")
# Distinctive angular N monogram.
d.line([(414, 570), (414, 418), (607, 565), (607, 410)], fill=(0, 43, 92, 255), width=40, joint="curve")
d.line([(414, 570), (414, 418), (607, 565), (607, 410)], fill=(235, 255, 255, 255), width=24, joint="curve")
# Crisp corner stars
for x,y in [(170, 280),(827, 330),(761, 174),(275, 810)]:
    d.polygon([(x,y-18),(x+6,y-5),(x+20,y),(x+6,y+5),(x,y+18),(x-6,y+5),(x-20,y),(x-6,y-5)], fill=(80, 226, 255, 255))
# Border kept away from iOS rounded clip.
d.rounded_rectangle((38, 38, 985, 985), radius=220, outline=(38, 166, 235, 255), width=12)
# RGB output, no transparency per iOS app icon requirements.
out = Path("Native/NovaCraft/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
out.parent.mkdir(parents=True, exist_ok=True)
img.convert("RGB").save(out, "PNG", optimize=True)
print(f"NovaCraft icon generated: {out} ({out.stat().st_size} bytes)")
