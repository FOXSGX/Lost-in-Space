"""构图地图（HSV 规则版）：把截图压成类别图，便于在没有看图控件时判断画面构成。

    python shot_map.py <png> [cols]
"""
import colorsys
import sys
from PIL import Image

path = sys.argv[1]
cols = int(sys.argv[2]) if len(sys.argv) > 2 else 56
image = Image.open(path).convert("RGB")
w, h = image.size
rows = max(1, int(cols * h / w * 0.5))
small = image.resize((cols, rows), Image.LANCZOS)


def classify(r, g, b):
    hh, ss, vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    deg = hh * 360.0
    if vv < 0.18:
        return "."
    if 20 <= deg <= 48 and ss > 0.52 and vv > 0.45:
        return "F"          # 高饱和暖色：燃料/琥珀灯带
    if 20 <= deg <= 60 and ss > 0.12 and vv > 0.45:
        return "D"          # 奶油/橙色：奶龙
    if ss < 0.14 and 0.45 <= vv <= 0.85:
        return "S"          # 低饱和浅色：船体
    if 175 <= deg <= 235 and vv < 0.55:
        return "K"          # 天空/阴影蓝
    if 90 <= deg <= 190 and ss < 0.30 and 0.18 <= vv < 0.55:
        return "G"          # 地面灰绿
    return "+" if vv > 0.45 else "."


counts = {}
lines = []
for y in range(rows):
    line = []
    for x in range(cols):
        ch = classify(*small.getpixel((x, y)))
        counts[ch] = counts.get(ch, 0) + 1
        line.append(ch)
    lines.append("".join(line))
print("%s  (%dx%d)" % (path.replace("\\", "/").split("/")[-1], w, h))
print("  ".join("%s=%d" % kv for kv in sorted(counts.items(), key=lambda kv: -kv[1])))
for line in lines:
    print(line)
