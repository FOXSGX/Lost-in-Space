"""截图体检：亮度统计 + 主体色块包围盒 + 字符图。

    python inspect_shot.py <png> [cols]
"""
import sys
from PIL import Image

RAMP = " .:-=+*#%@"
PALETTE = {
    "dragon_cream": (255, 230, 184),
    "dragon_orange": (255, 154, 84),
    "fuel_amber": (255, 179, 71),
    "hull_light": (196, 210, 208),
    "trim_teal": (55, 89, 103),
    "cyan": (63, 216, 255),
    "player_teal": (107, 148, 180),
}

path = sys.argv[1]
cols = int(sys.argv[2]) if len(sys.argv) > 2 else 76
image = Image.open(path).convert("RGB")
width, height = image.size
name = path.replace("\\", "/").split("/")[-1]

small = image.resize((cols, int(cols * height / width * 0.5)), Image.LANCZOS)
rows = small.size[1]
print("%s  %dx%d -> %dx%d" % (name, width, height, cols, rows))
for y in range(rows):
    line = []
    for x in range(cols):
        r, g, b = small.getpixel((x, y))
        lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
        line.append(RAMP[min(len(RAMP) - 1, int(lum * len(RAMP)))])
    print("".join(line))

probe = image.resize((200, 125))
pixels = list(probe.getdata())
total = len(pixels)
lums = sorted((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0 for r, g, b in pixels)
print("luminance  mean=%.2f  p10=%.2f  p50=%.2f  p90=%.2f  blown>0.94=%.1f%%  dark<0.06=%.1f%%" % (
    sum(lums) / total, lums[int(total * 0.1)], lums[int(total * 0.5)], lums[int(total * 0.9)],
    100.0 * sum(1 for v in lums if v > 0.94) / total,
    100.0 * sum(1 for v in lums if v < 0.06) / total,
))

pw, ph = probe.size
for cname, color in PALETTE.items():
    hits = 0
    minx, miny, maxx, maxy = pw, ph, -1, -1
    for y in range(ph):
        for x in range(pw):
            r, g, b = probe.getpixel((x, y))
            if abs(r - color[0]) < 24 and abs(g - color[1]) < 24 and abs(b - color[2]) < 24:
                hits += 1
                minx = min(minx, x)
                miny = min(miny, y)
                maxx = max(maxx, x)
                maxy = max(maxy, y)
    if hits == 0:
        print("  %-14s     -" % cname)
    else:
        print("  %-14s %5.2f%%  bbox=(%d,%d)-(%d,%d)" % (
            cname, 100.0 * hits / total, minx * width // pw, miny * height // ph,
            maxx * width // pw, maxy * height // ph))
