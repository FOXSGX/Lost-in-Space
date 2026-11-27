"""腐墟星截图色板比例 + 剪影检查。

用法：
    <bundled python> art-source/ruin/tools/analyze_palette.py \
        work/ruin-art-20261125/evidence/A_wide.png \
        work/ruin-art-20261125/evidence/B_player_eye.png

输出：
    与输入同目录的 palette_report.txt
    与输入同目录的 silhouette_<name>.png（纯黑剪影，人工确认 6 个地标不混淆）

判定口径（与《美术制作与 AI 协作指南》1.2 一致）：
    基底 65–75% / 明度壳 10–15% / 青绿 5–10% / 工业橙 <=8% / 警示红 <2%
只统计画面下半部（去掉天空），并屏蔽 HUD 的几块固定区域；这是近似测量，
用于发现“奶油色刷满整屏”或“橙色泛滥”这类结构性问题，不替代人工评分。
"""

import os
import sys

import numpy as np
from PIL import Image

PALETTE = {
    "base": [
        (0x66, 0x5A, 0x49), (0x47, 0x4B, 0x49), (0x3F, 0x44, 0x43),
        (0x5F, 0x5A, 0x4D), (0x3B, 0x3A, 0x33), (0x55, 0x4C, 0x40),
        (0x7A, 0x6E, 0x5A), (0x3C, 0x3A, 0x33), (0x2A, 0x2B, 0x26),
        # 渲染后的中性沥青/广场/暗墙：视觉读作灰绿，不是青绿功能色

        (0x5F, 0x62, 0x52), (0x2A, 0x33, 0x2C),
    ],
    "shell": [
        (0xA9, 0x9C, 0x84), (0xBD, 0xB2, 0x98), (0x7C, 0x70, 0x5C),

    ],
    "teal": [(0x2E, 0x52, 0x59), (0x1D, 0x36, 0x3C), (0x6B, 0x92, 0x94), (0x4B, 0x6F, 0x72)],
    "orange": [(0xA8, 0x61, 0x2F), (0x7A, 0x43, 0x1F), (0xE0, 0xB4, 0x78)],
    "red": [(0xB8, 0x49, 0x3C), (0x6F, 0x30, 0x2C), (0xD2, 0x4A, 0x3A)],
    "foliage": [(0x5E, 0x6B, 0x53), (0x46, 0x52, 0x3F)],
}

TARGETS = {
    "base": (65.0, 75.0),
    "shell": (10.0, 15.0),
    "teal": (5.0, 10.0),
    "orange": (0.0, 8.0),
    "red": (0.0, 2.0),
}
TOLERANCE = 3.0


def _all_colors():
    cols, labels = [], []
    for key, values in PALETTE.items():
        for rgb in values:
            cols.append(rgb)
            labels.append(key)
    return np.asarray(cols, dtype=np.float32), labels


def analyze(path: str) -> str:
    img = Image.open(path).convert("RGB")
    arr = np.asarray(img, dtype=np.float32)
    h, w, _ = arr.shape
    # 只取下 2/3（天空不参与 70/15/10/8 比例）；HUD 屏蔽左上、顶部、底部中间。
    mask = np.zeros((h, w), dtype=bool)
    mask[int(h * 0.34):, :] = True
    # 显式屏蔽 HUD 的固定块（顶部生命/罗盘/氧气、左上目标、底部物品槽与提示）。
    for rect in [
        (20, 20, 270, 66), (20, 80, 445, 220), (440, 20, 845, 90),
        (905, 20, 1268, 92), (548, 552, 742, 652), (350, 636, 935, 704),
        (618, 336, 662, 384),
    ]:
        x0, y0, x1, y1 = rect
        mask[max(0, y0):min(h, y1), max(0, x0):min(w, x1)] = False
    pixels = arr[mask]
    if pixels.size == 0:
        return f"{os.path.basename(path)}: 没有可分析像素\n"

    colors, labels = _all_colors()
    # 最近色分类：调色板里已包含“深青沥青=基底”，比 HSV 规则更贴近本项目的命名。
    diff = pixels[:, None, :] - colors[None, :, :]
    dist = np.sum(diff * diff, axis=2)
    nearest = np.argmin(dist, axis=1)
    counts = {}
    for index in nearest:
        key = labels[int(index)]
        # 植被属于“地貌中性底色”，按指南口径并入 65–75% 基底。
        if key == "foliage":
            key = "base"
        counts[key] = counts.get(key, 0) + 1
    total = float(len(pixels))
    lines = [f"== {os.path.basename(path)}  (分析像素 {int(total)})"]
    for key, (lo, hi) in TARGETS.items():
        pct = 100.0 * counts.get(key, 0) / total
        flag = "OK" if (lo - TOLERANCE) <= pct <= (hi + TOLERANCE) else "CHECK"
        lines.append(f"  {key:8s} {pct:6.2f}%  目标 {lo:4.1f}–{hi:4.1f}% (±{TOLERANCE:.0f})   [{flag}]")
    unknown = 100.0 - sum(100.0 * counts.get(k, 0) / total for k in TARGETS)
    lines.append(f"  other    {unknown:6.2f}%  （天空/未归类/抗锯齿）")

    # 纯黑剪影：背景压白、主体压黑，人工确认地标轮廓是否互相混淆。
    gray = arr.mean(axis=2)
    sil = np.where(gray[:, :, None] > 52.0, 255, 0).astype(np.uint8)
    sil = np.repeat(sil, 3, axis=2)
    out_path = os.path.join(os.path.dirname(path), "silhouette_" + os.path.basename(path))
    Image.fromarray(sil, mode="RGB").save(out_path)
    lines.append(f"  silhouette -> {out_path}")
    return "\n".join(lines) + "\n"


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        return
    report = []
    for path in sys.argv[1:]:
        if not os.path.exists(path):
            report.append(f"missing: {path}\n")
            continue
        report.append(analyze(path))
    text = "\n".join(report)
    print(text)
    out_dir = os.path.dirname(sys.argv[1]) or "."
    with open(os.path.join(out_dir, "palette_report.txt"), "w", encoding="utf-8") as handle:
        handle.write(text)


if __name__ == "__main__":
    main()
