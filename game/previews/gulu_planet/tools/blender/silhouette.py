"""角色渲染自检：把图片压成 ASCII 剪影 + 统计面部色块。

只用于确认“轮廓、部位齐全、五官有渲染出来”，**不能**代替人工审美判断。
    python silhouette.py <png> [cols]
"""
import sys
from PIL import Image

path = sys.argv[1]
cols = int(sys.argv[2]) if len(sys.argv) > 2 else 46
im = Image.open(path).convert("RGB")
w, h = im.size
rows = int(cols * h / w * 0.5)
small = im.resize((cols, rows), Image.LANCZOS)

mask = []
for y in range(rows):
    line = []
    for x in range(cols):
        r, g, b = [v / 255.0 for v in small.getpixel((x, y))]
        warm = (r - b) > 0.06 and r > 0.22
        white = r > 0.80 and g > 0.80 and b > 0.78
        dark = r < 0.14 and g < 0.16 and b < 0.16
        if white:
            ch = "O"      # 眼白/高光
        elif dark and warm is False and (r + g + b) < 0.35:
            ch = "@"      # 瞳孔/鼻孔/嘴
        elif warm:
            ch = "#"
        else:
            ch = " "
        line.append(ch)
        mask.append((ch, x, y, r, g, b))
    print("".join(line))

counts = {}
for ch, *_ in mask:
    counts[ch] = counts.get(ch, 0) + 1
total = sum(counts.values())
print("cells: " + " ".join("%s=%d" % (k if k != " " else "bg", v) for k, v in sorted(counts.items())))
xs = [x for ch, x, y, *_ in mask if ch in "#O@"]
ys = [y for ch, x, y, *_ in mask if ch in "#O@"]
if xs:
    print("subject bbox cols %d..%d of %d, rows %d..%d of %d" % (min(xs), max(xs), cols, min(ys), max(ys), rows))
