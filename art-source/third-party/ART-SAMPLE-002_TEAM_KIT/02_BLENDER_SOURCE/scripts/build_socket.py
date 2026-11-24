"""ART-QUALITY-002-NATURAL · 功能晶体的岩石承座

原版每根晶体下是一根圆台（Plinth*），隐藏后晶体就"浮"在地面上。
这里做三种不同轮廓的岩座：不是圆盘，而是被晶体顶裂的低矮岩瘤，
边缘不规则、带 2–3 块崩落岩片。

用法：blender -b --factory-startup -P build_socket.py -- a|b|c
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aq2kit as K
from aq2kit import Part

OUT = r"C:\Users\ASUS\Desktop\迷失太空\work\art-quality-002-natural\project\assets\models\aq002"
ART = r"C:\Users\ASUS\Desktop\迷失太空\work\art-quality-002-natural\art-source"

# 三种轮廓：半径、高度、段数、偏心、噪声强度
VARIANTS = {
    "a": dict(r=0.86, h=0.30, seg=13, ecc=1.00, amp=0.16, chips=3, seed=11),
    "b": dict(r=0.94, h=0.24, seg=11, ecc=1.18, amp=0.20, chips=2, seed=29),
    "c": dict(r=0.78, h=0.36, seg=15, ecc=0.92, amp=0.13, chips=3, seed=47),
}


def ring(r, seg, ecc, amp, seed, phase=0.0, z=0.0):
    pts = []
    for k in range(seg):
        a = K.TAU * k / seg + phase
        wob = 1.0 + amp * (K.vnoise(math.cos(a) * 2.3 + seed, math.sin(a) * 2.3, seed=seed) - 0.5) * 2.0
        pts.append((r * ecc * math.cos(a) * wob, r * math.sin(a) * wob))
    return pts


def build(key):
    v = VARIANTS[key]
    K.reset_scene()
    rock = K.mat("M_RockSocket", (0.255, 0.212, 0.176), 0.86, 0.0)
    parts = []

    # 主岩瘤：底缘外扩、向上收成碗口，晶体从碗口长出来
    p = Part("Socket")
    r, h, seg = v["r"], v["h"], v["seg"]
    prof = [
        (-0.05, ring(r * 1.06, seg, v["ecc"], v["amp"], v["seed"], 0.0)),
        (0.04, ring(r * 1.02, seg, v["ecc"], v["amp"], v["seed"], 0.22)),
        (h * 0.55, ring(r * 0.80, seg, v["ecc"], v["amp"] * 0.8, v["seed"] + 3, 0.41)),
        (h, ring(r * 0.52, seg, v["ecc"], v["amp"] * 0.6, v["seed"] + 5, 0.63)),
        (h * 0.96, ring(r * 0.34, seg, v["ecc"], v["amp"] * 0.4, v["seed"] + 7, 0.80)),
    ]
    p.loft(prof, m=rock, cap_start=True, cap_end=True)
    parts.append(p.finish(smooth=False))

    # 崩落岩片：从碗口向外倒的碎块
    for i in range(v["chips"]):
        a = K.TAU * i / v["chips"] + 0.7 + 0.3 * key.__len__()
        cx = math.cos(a) * r * 0.86
        cz = math.sin(a) * r * 0.78
        c = Part("Chip%d" % i)
        s = 0.20 + 0.05 * i
        base = [(s * 1.30 * math.cos(a + t), s * 0.95 * math.sin(a + t)) for t in (0.0, 1.5, 2.9, 4.3)]
        top = [(s * 0.85 * math.cos(a + t), s * 0.62 * math.sin(a + t)) for t in (0.0, 1.5, 2.9, 4.3)]
        c.loft([(0.015, base), (s * 0.95, top)], m=rock, loc=(cx, 0.0, cz), cap_start=True, cap_end=True)
        parts.append(c.finish(smooth=False))

    obj = K.join(parts, "CrystalSocket")
    print("AQ002_SOCKET %s tris=%d" % (key, K.tri_count([obj])))
    K.export_glb(os.path.join(OUT, "aq002_socket_%s.glb" % key))
    K.save_blend(os.path.join(ART, "aq002_socket_%s.blend" % key))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build(args[0] if args else "a")
