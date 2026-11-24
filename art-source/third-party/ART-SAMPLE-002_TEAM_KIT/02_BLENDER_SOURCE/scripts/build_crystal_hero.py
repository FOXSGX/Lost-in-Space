"""ART-SAMPLE-001 · 主晶体（共振钟晶体）与它的根部

上一版的问题（ART-QUALITY-002 报告 §14 / 15.12）：
  1. 晶体"插"在砧面上——根部是单独一块岩穹，晶体与岩穹之间没有长出来的关系；
  2. 晶体在近景里读作均匀发光的塑料，解理窗过曝；
  3. 夹爪只在晶体最宽处相切，"被咬住"这件事读不出来。

本轮做法：
  * 根部改成**一整块带层理与解理面的基岩**，晶体从岩体的裂隙里长出来，
    岩面上有被晶体顶裂的石片（顶裂方向与晶柱轴向一致，交代真实接触关系）；
  * 晶柱有**不规则六方截面 + 阶梯状解理断口 + 腰线 + 内部晶脉**，
    轴向不同、粗细不同、断口不同，没有一根是另一根的复制；
  * 根部岩座被砧座三块楔爪咬住，接触带有一圈碎屑与积尘。

坐标：本资产原点 = 晶体落座点（世界 (0, 1.18, -5.14)，机器局部 (0, 1.18, -1.74)）。
"""

import math
import os
import sys

import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aqs_kit as A
import aq2kit as K
import hero_mats as HM
from aqs_kit import Hero
from aq2kit import TAU, fbm, vnoise

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "project", "assets", "models", "aqs002")


def hex_profile(r, seed, phase=0.0, sides=6, irr=0.22):
    """不规则六方截面：每个角半径独立扰动（"天然晶体"与"挤出六边形"的区别）。"""
    pts = []
    for i in range(sides):
        a = phase + TAU * i / sides
        rr = r * (1.0 - irr * 0.5 + irr * vnoise(i * 3.7 + seed, seed * 1.7, 0.5))
        pts.append((rr * math.cos(a), rr * math.sin(a)))
    return pts


def crystal_column(h, r0, seed, tilt=(0.0, 0.0), tip_ratio=0.30, steps=9, sides=6,
                   phase=0.0, waist=1.06):
    """一根晶柱：(y, profile) 放样，顶部做阶梯解理断口。"""
    secs = []
    secs.append((-0.14, hex_profile(r0 * 1.06, seed, phase, sides, 0.14)))
    secs.append((0.0, hex_profile(r0, seed, phase, sides)))
    for i in range(steps):
        t = (i + 1) / float(steps)
        y = h * (1.0 - tip_ratio) * t
        rr = r0 * (1.0 - 0.34 * t + 0.14 * math.sin(t * math.pi) * (waist - 1.0) * 6.0)
        secs.append((y, hex_profile(rr, seed + i * 1.3, phase + 3.0 * t, sides)))
    yt = h * (1.0 - tip_ratio)
    secs.append((yt + h * tip_ratio * 0.42, hex_profile(r0 * 0.52, seed + 31, phase + 6.0, sides)))
    secs.append((yt + h * tip_ratio * 0.68, hex_profile(r0 * 0.30, seed + 47, phase + 9.0, sides)))
    off = (r0 * 0.16, r0 * 0.10)
    tipr = hex_profile(r0 * 0.10, seed + 59, phase + 12.0, sides)
    secs.append((h, [(p[0] + off[0], p[1] + off[1]) for p in tipr]))
    bm = A.bm_loft(secs, close=True)
    bm.normal_update()
    for v in bm.verts:
        d = (fbm(v.co.x * 26.0, v.co.y * 12.0, v.co.z * 26.0, 3, seed=seed + 5) - 0.5) * 0.004
        v.co += v.normal * d
    if any(abs(a) > 1e-9 for a in tilt):
        rx, rz = [a * math.pi / 180.0 for a in tilt]
        bm.transform(Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(rx, 4, "X"))
    return bm


def build_crystal():
    m = HM.build_materials()
    h = Hero("BellCrystal")
    shell, core, vein = m["M_CrystalShell"], m["M_CrystalCore"], m["M_CrystalVein"]
    root_rock, talus = m["M_RootRock"], m["M_Talus"]

    # ---------------------------------------------------------------- 根部基岩
    base = A.rock_from_planes((1.62, 0.60, 1.48), seed=201, cuts=9, subdiv=3,
                              rough=0.010, bevel=0.007, strata=(0.085, 0.020))
    for v in base.verts:
        v.co.z *= 0.62          # 压扁成"露出地面的一层岩台"
    h.add(base, root_rock, loc=(0.0, -0.02, 0.0))
    for i in range(7):
        a = TAU * i / 7 + 0.3
        rr = 0.70 + 0.10 * vnoise(i * 2.1, 3.0, 0.0)
        flake = A.rock_from_planes((0.30 + 0.10 * vnoise(i, 1.0, 2.0), 0.070, 0.24),
                                   seed=210 + i, cuts=4, subdiv=2, rough=0.004, bevel=0.003)
        h.add(flake, talus, loc=(rr * math.cos(a), 0.035, rr * math.sin(a)),
              rot=(0.0, math.degrees(a) + 12.0 * vnoise(i, 5.0, 0.0), 0.0))

    # ---------------------------------------------------------------- 顶裂石片
    for i, (ax, az, ang, lift) in enumerate([(0.86, 0.7, 24.0, 0.085),
                                             (-0.92, 0.5, -38.0, 0.10),
                                             (0.10, -1.0, 8.0, 0.075)]):
        fl = A.rock_from_planes((0.52, 0.075, 0.42), seed=230 + i, cuts=4, subdiv=2,
                                rough=0.005, bevel=0.004, strata=(0.06, 0.012))
        h.add(fl, root_rock, loc=(ax * 0.44, 0.10 + lift, az * 0.44),
              rot=(math.degrees(math.atan2(az, 1.0)) * 18.0, ang,
                   -math.degrees(math.atan2(ax, 1.0)) * 18.0))

    # ---------------------------------------------------------------- 晶柱
    cols = [
        (1.78, 0.300, 3.1, 0.02, 0.03, 2.0, -3.0, 0.33),
        (1.15, 0.195, 11.7, -0.34, 0.16, -9.0, 12.0, 0.34),
        (0.92, 0.158, 23.3, 0.36, -0.18, 11.0, -14.0, 0.32),
        (0.62, 0.115, 31.9, 0.12, 0.42, -14.0, -6.0, 0.34),
        (0.48, 0.095, 47.5, -0.24, -0.34, 16.0, 9.0, 0.30),
        (0.34, 0.070, 59.1, 0.50, 0.30, -6.0, 22.0, 0.36),
        (0.26, 0.058, 61.7, -0.52, 0.02, 8.0, -20.0, 0.32),
    ]
    for i, (hh, rr, sd, bx, bz, tx, tz, tr) in enumerate(cols):
        bm = crystal_column(hh, rr, sd, tilt=(tx, tz), tip_ratio=tr,
                            steps=9, sides=6, phase=sd * 0.31)
        h.add(bm, shell, loc=(bx, 0.10, bz))
        if i < 3:
            vh = hh * 0.62
            vb = A.bm_lathe([(0.0, 0.0), (rr * 0.13, 0.02), (rr * 0.10, vh * 0.6),
                             (0.0, vh)], seg=6)
            h.add(vb, vein, loc=(bx, 0.16, bz),
                  rot=(0.0, math.degrees(math.atan2(bz, 1.0)) * 10.0, 0.0))
        for k in range(3):
            a = TAU * (k / 3.0) + i
            pb = A.rock_from_planes((0.055, 0.030, 0.045), seed=300 + i * 5 + k, cuts=3,
                                    subdiv=1, rough=0.002, bevel=0.0015)
            h.add(pb, talus, loc=(bx + 0.09 * math.cos(a), 0.115, bz + 0.09 * math.sin(a)))

    # 主柱中段的一处解理窗（薄片贴晶面，颜色更冷但**不发光**：
    # 上一版用发光芯材质做这块，近距离直接读成一块过曝白方块）
    win = A.bm_loft([(0.66, [(0.0, -0.055), (0.135, -0.012), (0.115, 0.055), (0.0, 0.055)]),
                     (0.88, [(0.0, -0.050), (0.130, -0.010), (0.110, 0.050), (0.0, 0.050)])],
                    close=True, cap_start=True, cap_end=True)
    h.add(win, shell, loc=(0.225, 0.0, 0.135), rot=(0.0, -26.0, 0.0))

    # ---------------------------------------------------------- 根部融合（P4）
    # 岩体"长"到晶体上去：三片岩板压住晶柱根部外沿（不是把晶体插进岩里），
    # 再加一圈放射状细裂隙与侵蚀凹窝，交代"晶体在挤压并侵蚀围岩"。
    for i, (ang, dist, lift, w_, d_) in enumerate([(38.0, 0.60, 0.05, 0.42, 0.30),
                                                   (152.0, 0.55, 0.09, 0.36, 0.26),
                                                   (268.0, 0.63, 0.03, 0.30, 0.22)]):
        a = math.radians(ang)
        plate = A.rock_from_planes((w_, 0.075, d_), seed=780 + i, cuts=5, subdiv=2,
                                   rough=0.004, bevel=0.003, strata=(0.055, 0.012))
        # 岩板向晶体倾斜 22°（被顶起来的方向与晶柱轴向一致）
        h.add(plate, root_rock,
              loc=(dist * math.cos(a), 0.10 + lift, dist * math.sin(a)),
              rot=(18.0 * math.cos(a), ang, -18.0 * math.sin(a)))
    for i in range(7):
        a = TAU * i / 7 + 0.31
        r0 = 0.72
        crack = A.rock_from_planes((0.22 + 0.06 * vnoise(i, 3.0, 1.0), 0.020, 0.030),
                                   seed=800 + i, cuts=3, subdiv=1,
                                   rough=0.001, bevel=0.0012)
        h.add(crack, m["M_BedrockDark"],
              loc=(r0 * math.cos(a), 0.105, r0 * math.sin(a)),
              rot=(0.0, math.degrees(a), 0.0))
    for i in range(4):
        a = TAU * i / 4 + 0.8
        for k in range(3):
            s = 0.055 + 0.02 * k
            pb = A.rock_from_planes((s, s * 0.6, s), seed=820 + i * 5 + k, cuts=3,
                                    subdiv=1, rough=0.0015, bevel=0.0015)
            h.add(pb, talus, loc=(0.46 * math.cos(a) + 0.05 * k, 0.115,
                                  0.46 * math.sin(a) - 0.04 * k))

    obj = h.finish(smooth=True, split_angle=25.0,
                   bake=dict(ao_rays=10, ao_dist=0.22, seed=41, mat_gain=HM.WEAR_GAIN))
    A.report("BellCrystal", obj)
    return obj


def main():
    K.reset_scene()
    HM.build_materials()
    build_crystal()
    A.export_glb(os.path.join(OUT, "aqs002_bell_crystal.glb"), "BellCrystal")
    K.save_blend(os.path.join(ROOT, "art-source", "aqs002_crystal.blend"))
    print("AQS001_CRYSTAL_OK")


main()



