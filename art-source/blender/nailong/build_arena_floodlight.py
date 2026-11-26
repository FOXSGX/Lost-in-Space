"""奶龙星 · 场外场地灯塔（Mid 级资产，按《美术制作与 AI 协作指南》九步流水线）

坐标：Godot 约定（x 右 / y 上 / z 前）；原点 = 塔脚地面中心（底面 y=0）。
结构：混凝土承台 + 四件地脚螺栓 → 锥形灯杆（分三段，带法兰）→ 检修爬梯（护栏+踏棍）
      → 横臂 + 两件投光灯（灯罩 + 防眩檐 + 发光透镜 + 挂钩）→ 电缆 → 接地牌。

导出：assets/models/nailong/floodlight_tower.glb
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = r"C:\Users\31798\.openclaw\workspace\ref\art_sample_002\02_BLENDER_SOURCE\scripts"
sys.path.insert(0, KIT)
sys.path.insert(0, HERE)

import aq2kit as K
import aqs_kit as S
from aqs_kit import Hero, bm_box, bm_cyl, bm_tube
import nailong_kit as N

OUT_DIR = r"C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet\assets\models\nailong"

POLE_H = 6.2
POLE_R0 = 0.135
POLE_R1 = 0.078


def build(out_file="floodlight_tower.glb"):
    K.reset_scene()
    K._MATS.clear()

    cream = K.mat("M_PaintCream", (0.615, 0.578, 0.488), 0.48, 0.08)
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.58, 0.42)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)
    glow = K.mat("M_LampGlow", (0.95, 0.78, 0.42), 0.35, 0.0, emit=(1.0, 0.82, 0.48), emit_strength=6.0)

    h = Hero("FloodlightTower")

    # ---------------------------------------------------------- 承台与地脚
    h.add(bm_box((1.20, 0.26, 1.20), bevel=0.012, segments=2), deep, loc=(0.0, 0.13, 0.0))
    h.add(bm_box((0.86, 0.08, 0.86), bevel=0.008, segments=2), bare, loc=(0.0, 0.30, 0.0))
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            N.add_bolt(h, (sx * 0.46, 0.30, sz * 0.46), bare, axis="up",
                       d=0.026, head_h=0.016, phase=1.7 * sx + 0.9 * sz)

    # ---------------------------------------------------------- 灯杆（三段）
    seg_h = POLE_H / 3.0
    for i in range(3):
        y0 = 0.34 + i * seg_h
        r0 = POLE_R0 + (POLE_R1 - POLE_R0) * (i / 3.0)
        r1 = POLE_R0 + (POLE_R1 - POLE_R0) * ((i + 1) / 3.0)
        h.add(bm_cyl(r0, seg_h, seg=16, r2=r1), cream, loc=(0.0, y0 + seg_h * 0.5, 0.0))
        # 法兰
        h.add(bm_cyl(r0 + 0.045, 0.05, seg=16), bare, loc=(0.0, y0, 0.0))

    # ---------------------------------------------------------- 检修爬梯
    ladder_x = 0.16
    for side in (-1.0, 1.0):
        h.add(bm_box((0.026, POLE_H - 0.5, 0.026), bevel=0.002, segments=1), bare,
              loc=(ladder_x + side * 0.12, 0.34 + (POLE_H - 0.5) * 0.5, -0.14))
    z_rung = -0.14
    y = 0.62
    while y < POLE_H - 0.25:
        h.add(bm_box((0.27, 0.022, 0.022), bevel=0.002, segments=1), bare,
              loc=(ladder_x, y, z_rung))
        y += 0.30
    # 护笼（顶部半圈）
    for i in range(6):
        ang = -0.9 + i * 0.36
        h.add(bm_box((0.02, 0.02, 0.30), bevel=0.001, segments=1), bare,
              loc=(ladder_x + 0.30 * (1.0 - abs(ang) * 0.4), POLE_H - 0.9 + i * 0.10, z_rung - 0.05))

    # ---------------------------------------------------------- 横臂与投光灯
    arm_y = POLE_H - 0.10
    h.add(bm_box((2.30, 0.13, 0.13), bevel=0.006, segments=2), cream, loc=(0.0, arm_y, 0.0))
    # 斜撑
    for sx in (-1.0, 1.0):
        h.add(bm_box((0.90, 0.055, 0.07), bevel=0.003, segments=1), cream,
              loc=(sx * 0.42, arm_y - 0.30, 0.0), rot=(0.0, 0.0, sx * 0.55))
    for sx in (-1.0, 1.0):
        lx = sx * 1.00
        # 挂钩（承力件，禁悬浮）
        h.add(bm_box((0.05, 0.16, 0.05), bevel=0.003, segments=1), bare,
              loc=(lx, arm_y - 0.10, 0.0))
        # 灯体
        h.add(bm_box((0.46, 0.30, 0.26), bevel=0.010, segments=2), deep,
              loc=(lx, arm_y - 0.32, 0.02))
        # 防眩檐
        h.add(bm_box((0.50, 0.05, 0.34), bevel=0.004, segments=1), deep,
              loc=(lx, arm_y - 0.15, 0.06))
        # 发光透镜（朝场内 -z）
        h.add(bm_box((0.40, 0.24, 0.03), bevel=0.004, segments=1), glow,
              loc=(lx, arm_y - 0.32, -0.13))

    # ---------------------------------------------------------- 电缆
    pts = [(0.0, 0.36, 0.22), (0.0, 1.60, 0.20), (0.0, 3.40, 0.19), (0.0, arm_y - 0.18, 0.12)]
    h.add(bm_tube(pts, 0.028, seg=6), bare)

    # ---------------------------------------------------------- 接地牌
    h.add(bm_box((0.24, 0.16, 0.010), bevel=0.002, segments=1), cream,
          loc=(0.0, 1.15, 0.16))
    for dx in (-0.07, 0.07):
        N.add_bolt(h, (dx, 1.15, 0.166), bare, axis="zp", d=0.014, head_h=0.008, phase=2.0 * dx)

    obj = N.finish_asset(h, {"ao_rays": 11, "ao_dist": 0.18, "seed": 31, "ground_z": 0.0})
    print("NAILONG_FLOODLIGHT tris=%d" % K.tri_count([obj]))
    N.report_mats(obj)
    N.report_bbox("FloodlightTower", obj)
    out = os.path.join(OUT_DIR, out_file)
    os.makedirs(OUT_DIR, exist_ok=True)
    S.export_glb(out, "FloodlightTower")
    print("NAILONG_FLOODLIGHT exported", out, os.path.getsize(out))


if __name__ == "__main__":
    build()
