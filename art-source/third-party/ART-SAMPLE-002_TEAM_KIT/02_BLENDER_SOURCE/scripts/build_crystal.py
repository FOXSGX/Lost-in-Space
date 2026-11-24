"""ART-QUALITY-002-NATURAL · 中央主晶体（bell）

设计要点
========
1. 主体不是一根对称的"叶子"，而是**五根不同高度的晶柱组成的晶簇**：
   主柱有清楚的解理面、腰线与不对称的尖端；其余四根从同一根部向外生长。
2. 根部是重点：一圈被顶裂的岩石（六个岩齿）咬住晶柱，砧座的钢面从裂缝里
   翘起，缝隙里有发光的晶脉。晶体是"长出来"的，不是插上去的。
3. 只在根部做发光脉，柱身靠晶体 Shader 的面/棱/尖端分层，不靠大面积自发光。

导出：aq002_bell_crystal.glb（原点在晶体根部，向上生长）
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aq2kit as K
from aq2kit import Part, D2R

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "project", "assets", "models", "aq002", "aq002_bell_crystal.glb")


def shard_section(r, n, phase, squash, jitter, seed):
    pts = []
    for i in range(n):
        a = phase + K.TAU * i / n
        wob = 1.0 + jitter * (K.vnoise(i * 2.7 + seed * 0.3, seed * 0.11, seed=seed) - 0.5) * 2.0
        rr = r * wob
        pts.append((rr * math.cos(a), rr * math.sin(a) * squash))
    return pts


def shard(name, base_r, height, profile, mat, n=7, phase=0.0, squash=0.85,
          jitter=0.18, seed=1, lean=(0.0, 0.0), bend=1.6):
    """profile: [(t, radius_mult, ox, oz)]，从根到尖。"""
    p = Part(name)
    sec = []
    for (t, mult, ox, oz) in profile:
        r = max(0.012, base_r * mult)
        pts = shard_section(r, n, phase, squash, jitter, seed)
        sec.append((height * t, [(x + ox, z + oz) for (x, z) in pts]))
    # 收尖
    tipx = profile[-1][2] + lean[0]
    tipz = profile[-1][3] + lean[1]
    last = sec[-1][1]
    tiny = [((tipx + (x - profile[-1][2]) * 0.10), (tipz + (z - profile[-1][3]) * 0.10))
            for (x, z) in last]
    sec.append((height * (profile[-1][0] + 0.055), tiny))
    p.loft(sec, m=mat, cap_start=True, cap_end=True)
    return p.finish(smooth=False)


def build_crystal():
    shell = K.mat("M_CrystalShell", (0.035, 0.145, 0.200), 0.18, 0.0)
    core = K.mat("M_CrystalCore", (0.10, 0.40, 0.52), 0.12, 0.0)
    vein = K.mat("M_CrystalVein", (0.13, 0.07, 0.28), 0.2, 0.0)
    rock = K.mat("M_RootRock", (0.285, 0.240, 0.198), 0.9, 0.0)
    steel = K.mat("M_RootSteel", (0.30, 0.31, 0.32), 0.4, 0.6)

    objs = []

    # ---------------------------------------------------------------- 主柱
    main_profile = [
        (0.00, 0.72, 0.00, 0.00),
        (0.08, 1.00, 0.01, 0.01),
        (0.22, 0.92, 0.03, 0.03),
        (0.40, 0.78, 0.06, 0.06),
        (0.56, 0.84, 0.09, 0.10),
        (0.72, 0.60, 0.13, 0.15),
        (0.86, 0.34, 0.17, 0.20),
        (0.95, 0.16, 0.20, 0.24),
    ]
    objs.append(shard("Shard_Main", 0.31, 1.18, main_profile, shell, n=8,
                      phase=0.28, squash=0.86, jitter=0.16, seed=11,
                      lean=(0.05, 0.05)))

    # 主柱解理窗：内凹的亮面（不做整体透明，靠一块更亮的解理面表达内部能量）
    win = Part("CleavageWindow")
    win.loft([(0.26, [(-0.11, -0.245), (0.09, -0.265), (0.13, -0.16), (-0.08, -0.135)]),
              (0.44, [(-0.09, -0.255), (0.07, -0.275), (0.11, -0.18), (-0.06, -0.155)]),
              (0.60, [(-0.05, -0.245), (0.04, -0.26), (0.07, -0.20), (-0.03, -0.19)])],
             m=core, cap_start=False, cap_end=False)
    objs.append(win.finish(smooth=False))

    # ---------------------------------------------------------------- 副柱
    subs = [
        ("Shard_A", 0.135, 0.86, (-0.36, 0.06), (-0.30, 0.06), 0.9, 21),
        ("Shard_B", 0.120, 0.68, (0.34, -0.05), (0.27, -0.03), 0.4, 33),
        ("Shard_C", 0.105, 0.50, (-0.12, -0.36), (-0.09, -0.27), 1.7, 41),
        ("Shard_D", 0.088, 0.38, (0.26, 0.31), (0.19, 0.23), 2.4, 53),
    ]
    for (name, r, h, base_pos, lean, phase, seed) in subs:
        prof = [
            (0.00, 0.80, 0.0, 0.0),
            (0.16, 1.00, lean[0] * 0.12, lean[1] * 0.12),
            (0.50, 0.82, lean[0] * 0.45, lean[1] * 0.45),
            (0.80, 0.50, lean[0] * 0.75, lean[1] * 0.75),
            (0.94, 0.20, lean[0] * 0.95, lean[1] * 0.95),
        ]
        prof = [(t, m, base_pos[0] + ox, base_pos[1] + oz) for (t, m, ox, oz) in prof]
        objs.append(shard(name, r, h, prof, shell, n=6, phase=phase, squash=0.9,
                          jitter=0.20, seed=seed))
        # 副柱根部的一圈亮色生长纹
        base = Part(name + "_Base")
        base.lathe([(0.0, -0.01), (r * 1.40, -0.01), (r * 1.18, 0.07), (0.0, 0.09)],
                   (base_pos[0], 0.0, base_pos[1]), m=core, segments=7)
        objs.append(base.finish(smooth=False))

    # ---------------------------------------------------------------- 根部岩石
    # 晶体从一块隆起的岩瘤里长出来：连续的穹面（不是一圈环），
    # 因此不会在根部露出黑色空腔；岩瘤边缘被三块小石片顶裂。
    dome = Part("RootDome")
    # 底缘比砧面（1.52 × 1.06 的方块，半宽 0.76 / 0.53）更大，
    # 让岩穹完整盖住砧面边缘，避免出现一圈读作"裂缝"的暗缝。
    # 根部岩穹略放大：近距视角下"晶体像插在小石头上"。
    # 打击判定只依赖角度与角速度（hammer_rig.gd:463），不含几何检测，
    # 因此加大根部不会影响敲钟——这一点已通过读源码确认，而非猜测。
    prof = [(-0.06, [(0.80 * math.cos(K.TAU * k / 17) * (1.0 + 0.05 * math.cos(k * 2.1)),
                      0.70 * math.sin(K.TAU * k / 17) * (1.0 + 0.05 * math.sin(k * 1.7)))
                     for k in range(17)]),
            (0.06, [(0.74 * math.cos(K.TAU * k / 17), 0.64 * math.sin(K.TAU * k / 17)) for k in range(17)]),
            (0.16, [(0.44 * math.cos(K.TAU * k / 17), 0.38 * math.sin(K.TAU * k / 17)) for k in range(17)]),
            (0.23, [(0.22 * math.cos(K.TAU * k / 17), 0.19 * math.sin(K.TAU * k / 17)) for k in range(17)])]
    dome.loft(prof, m=rock, cap_start=True, cap_end=True)
    objs.append(dome.finish(smooth=False))
    # 三块被顶裂的小石片
    for i in range(3):
        a = K.TAU * i / 3 + 0.4
        px, pz = 0.50 * math.cos(a), 0.44 * math.sin(a)
        sp = Part("RootShard%d" % i)
        sp.loft([(0.04, [(0.16 * math.cos(a + t), 0.14 * math.sin(a + t)) for t in (0.0, 1.4, 2.6, 4.0)]),
                 (0.22, [(0.10 * math.cos(a + t), 0.09 * math.sin(a + t)) for t in (0.0, 1.4, 2.6, 4.0)])],
                m=rock, loc=(px, 0.0, pz), cap_start=True, cap_end=True)
        objs.append(sp.finish(smooth=False))
    # 裂缝中的晶脉
    for i, (vx, vz, ry) in enumerate([(0.21, 0.17, 34.0), (-0.25, 0.10, -28.0)]):
        vp = Part("Vein%d" % i)
        vp.box((0.05, 0.02, 0.22), (vx, 0.14, vz), m=vein, rot=(0, ry, 0), bevel=0.004)
        objs.append(vp.finish(smooth=False))

    # 被顶起的砧座钢面：只保留两片小薄板
    for i, (sx, sz, rz) in enumerate([(0.46, 0.30, 12.0), (-0.47, 0.26, -9.0)]):
        sp2 = Part("CrackPlate%d" % i)
        sp2.box((0.18, 0.026, 0.14), (sx, 0.045, sz), m=steel, rot=(0, rz, 2.0), bevel=0.006)
        objs.append(sp2.finish(smooth=False))
    obj = K.join(objs, "BellCrystal")
    print("AQ002_BELL tris=%d" % K.tri_count([obj]))
    return obj


def main():
    K.reset_scene()
    obj = build_crystal()
    K.export_glb(OUT)
    K.save_blend(os.path.join(ROOT, "art-source", "aq002_bell_crystal.blend"))


if __name__ == "__main__":
    main()
