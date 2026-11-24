"""奶龙星 · 东南角观测台（Mid 级资产，按《美术制作与 AI 协作指南》九步流水线）

坐标：**Godot 约定（x 右 / y 上 / z 前）**；原点 = 台面中心地面点（世界 5.4, 0, 12.4）。
尺寸：x 6.55 × y 4.55 × z 2.42（含楼梯与标杆灯）。

结构：四根方管柱（承台底板 + 地脚螺栓）→ 台面周圈梁 + 台面板（4 块，3 mm 缝）→
      踢脚挡板 + 柱顶斜撑 + 两道 X 形斜撑 → 三面栏杆（立柱 + 上/中横杆 + 踢脚）→
      西侧 8 级钢梯（踏面板 + 防滑胶条 + 双斜梁 + 单侧扶手）→ 台上标杆灯（法兰 + 灯罩）。

导出：assets/models/nailong/observation_deck.glb
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = r"C:\Users\31798\.openclaw\workspace\ref\art_sample_002\02_BLENDER_SOURCE\scripts"
sys.path.insert(0, KIT)
sys.path.insert(0, HERE)

import aq2kit as K
import aqs_kit as S
from aqs_kit import Hero, bm_box
import nailong_kit as N

OUT = r"C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet\assets\models\nailong\observation_deck.glb"

DECK_TOP = 2.62
DECK_T = 0.10
BEAM_Y = DECK_TOP - DECK_T - 0.16      # 2.36：周圈梁底
BEAM_TALL = 0.16
LEG_X = 1.70
LEG_Z = 0.95
RAIL_TOP = DECK_TOP + 1.05             # 1.00–1.05 m 护栏
STEP_RISE = 0.3075
STEP_RUN = 0.31
STEPS = 8


def main():
    K.reset_scene()
    K._MATS.clear()

    cream = K.mat("M_PaintCream", (0.615, 0.578, 0.488), 0.46, 0.10)
    yellow = K.mat("M_PaintYellow", (0.80, 0.56, 0.09), 0.48, 0.08)
    orange = K.mat("M_PaintOrange", (0.70, 0.268, 0.062), 0.48, 0.10)
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.58, 0.45)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)
    rubber = K.mat("M_Rubber", (0.052, 0.058, 0.060), 0.86, 0.0)

    h = Hero("ObservationDeck")

    # ------------------------------------------------------------ 立柱 + 承台
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            x, z = sx * LEG_X, sz * LEG_Z
            h.add(bm_box((0.14, BEAM_Y, 0.14), bevel=0.005, segments=2), deep,
                  loc=(x, BEAM_Y * 0.5, z))
            # 柱脚承台 + 对角两颗地脚螺栓
            h.plate((0.34, 0.030, 0.30), (x, 0.015, z), deep, thickness=0.030,
                    bevel=0.004, fold=None)
            for d in (-1.0, 1.0):
                N.add_bolt(h, (x + d * 0.115, 0.030, z - d * 0.095), bare, axis="up",
                           d=0.020, head_h=0.012, boss=0.008, boss_mat=deep,
                           phase=1.3 * d + 0.8 * sx)
            # 柱脚焊道
            h.weld([(x - 0.09, 0.036, z - 0.075), (x - 0.09, 0.036, z + 0.075)], deep,
                   r=0.005)

    # ------------------------------------------------------------ 台面梁
    # 周圈梁（四边） + 柱顶次梁（四道，直接把台面荷载传到四根腿）
    for sz in (-1.0, 1.0):
        N.add_beam_x(h, -2.00, 2.00, BEAM_Y, sz * 1.11, cream, deep,
                     depth=0.10, tall=BEAM_TALL)
        h.add(bm_box((4.00, BEAM_TALL, 0.09), bevel=0.003, segments=2), deep,
              loc=(0.0, BEAM_Y + BEAM_TALL * 0.5, sz * LEG_Z))
    for sx in (-1.0, 1.0):
        N.add_beam_z(h, -1.19, 1.19, BEAM_Y, sx * 1.88, cream, deep,
                     depth=0.10, tall=BEAM_TALL)
        h.add(bm_box((0.09, BEAM_TALL, 2.38), bevel=0.003, segments=2), deep,
              loc=(sx * LEG_X, BEAM_Y + BEAM_TALL * 0.5, 0.0))

    # ------------------------------------------------------------ 台面板（4 块，3 mm 缝）
    plate_w = 0.985
    plate_y = DECK_TOP - DECK_T * 0.5
    for cx in (-1.4975, -0.5025, 0.5025, 1.4975):
        h.add(bm_box((plate_w, DECK_T, 2.34), bevel=0.006, segments=3), bare,
              loc=(cx, plate_y, 0.0))
        # 板下折边（让台面看得出是折弯钢板，不是一块厚砖）
        for sz in (-1.0, 1.0):
            h.add(bm_box((plate_w, 0.050, 0.014), bevel=0.003, segments=2), bare,
                  loc=(cx, DECK_TOP - DECK_T - 0.020, sz * 1.163))

    # ------------------------------------------------------------ 踢脚挡板（0.10 m）
    toe_y = DECK_TOP + 0.05
    for sz in (-1.0, 1.0):
        h.add(bm_box((3.96, 0.10, 0.018), bevel=0.003, segments=2), yellow,
              loc=(0.0, toe_y, sz * 1.185))
    h.add(bm_box((0.018, 0.10, 2.37), bevel=0.003, segments=2), yellow,
          loc=(1.985, toe_y, 0.0))
    for sz in (-1.0, 1.0):
        h.add(bm_box((0.018, 0.10, 0.60), bevel=0.003, segments=2), yellow,
              loc=(-1.985, toe_y, sz * 0.885))

    # ------------------------------------------------------------ 斜撑
    # 柱顶斜撑（4）：梁底到柱身 45°
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            h.add(bm_box((0.62, 0.07, 0.07), bevel=0.004, segments=2), cream,
                  loc=(sx * 1.44, BEAM_Y - 0.16, sz * LEG_Z), rot=(0.0, 0.0, sx * sz * 45.0))
    # 两道 X 形斜撑（z 面），方管 50 mm
    for sz in (-1.0, 1.0):
        N.add_frame(h, [(LEG_X - 0.07, 0.30, sz * LEG_Z), (-LEG_X + 0.07, BEAM_Y - 0.12, sz * LEG_Z)],
                    0.05, 0.05, deep)
        N.add_frame(h, [(-LEG_X + 0.07, 0.30, sz * LEG_Z), (LEG_X - 0.07, BEAM_Y - 0.12, sz * LEG_Z)],
                    0.05, 0.05, deep)

    # ------------------------------------------------------------ 栏杆
    posts = []
    for x in (-1.95, -0.65, 0.65, 1.95):
        posts.append((x, 1.15))
        posts.append((x, -1.15))
    posts.append((1.95, 0.0))
    for (px, pz) in posts:
        h.add(bm_box((0.055, RAIL_TOP - DECK_TOP + 0.02, 0.055), bevel=0.004, segments=2),
              cream, loc=(px, (DECK_TOP + RAIL_TOP) * 0.5 + 0.01, pz))
        # 柱底法兰（螺栓只放法兰上，不撒）
        h.add(bm_box((0.12, 0.014, 0.12), bevel=0.003, segments=1), deep,
              loc=(px, DECK_TOP + 0.007, pz))
    # 上/中/下横杆
    rails_z = (1.15, -1.15)
    for pz in rails_z:
        for y, tall in ((RAIL_TOP, 0.05), (DECK_TOP + 0.62, 0.035), (DECK_TOP + 0.16, 0.03)):
            h.add(bm_box((3.96, tall, 0.045), bevel=0.004, segments=2), cream,
                  loc=(0.0, y, pz))
    for y, tall in ((RAIL_TOP, 0.05), (DECK_TOP + 0.62, 0.035), (DECK_TOP + 0.16, 0.03)):
        h.add(bm_box((0.045, tall, 2.36), bevel=0.004, segments=2), cream,
              loc=(1.95, y, 0.0))
    # 扶手顶横杆上一条橙色握把带（可抓扶 = 交互色，面积很小）
    h.add(bm_box((3.96, 0.012, 0.020), bevel=0.004, segments=2), orange,
          loc=(0.0, RAIL_TOP + 0.031, 1.15))

    # ------------------------------------------------------------ 楼梯（西侧 8 级）
    top_x = -2.00
    for k in range(1, STEPS + 1):
        top_y = DECK_TOP - STEP_RISE * k
        cx = top_x - STEP_RUN * (k - 0.5)
        h.add(bm_box((STEP_RUN - 0.012, 0.045, 0.86), bevel=0.005, segments=3), bare,
              loc=(cx, top_y - 0.0225, 0.0))
        # 防滑胶条（踏面前沿）
        h.add(bm_box((0.030, 0.008, 0.80), bevel=0.002, segments=1), rubber,
              loc=(cx + STEP_RUN * 0.5 - 0.035, top_y + 0.002, 0.0))
    run = STEP_RUN * STEPS
    rise = DECK_TOP - STEP_RISE * STEPS
    ang = math.atan2(DECK_TOP - rise, run)
    length = math.hypot(run, DECK_TOP - rise)
    for sz in (-1.0, 1.0):
        h.add(bm_box((length, 0.155, 0.028), bevel=0.004, segments=2), deep,
              loc=(top_x - run * 0.5, (DECK_TOP + rise) * 0.5 - 0.115, sz * 0.47),
              rot=(0.0, 0.0, math.degrees(ang)))
    # 楼梯扶手（单侧，贴 z=+0.50）
    h.add(bm_box((0.045, 1.00, 0.045), bevel=0.004, segments=2), cream,
          loc=(top_x + 0.06, DECK_TOP + 0.50, 0.50))
    h.add(bm_box((0.045, 0.98, 0.045), bevel=0.004, segments=2), cream,
          loc=(top_x - run + 0.10, rise + 0.49, 0.50))
    h.add(S.bm_tube([(top_x + 0.06, DECK_TOP + 1.00, 0.50),
                     (top_x - run + 0.10, rise + 0.98, 0.50)], 0.021, seg=8), cream)
    h.add(S.bm_tube([(top_x - 0.10, DECK_TOP + 0.58, 0.50),
                     (top_x - run + 0.14, rise + 0.56, 0.50)], 0.016, seg=6), cream)

    # ------------------------------------------------------------ 台上标杆灯
    lx, lz = 1.60, 0.90
    h.add(S.bm_cyl(0.034, 1.63, seg=10), bare, loc=(lx, DECK_TOP, lz))
    h.add(bm_box((0.17, 0.016, 0.17), bevel=0.004, segments=2), deep,
          loc=(lx, DECK_TOP + 0.008, lz))
    for d in (-1.0, 1.0):
        N.add_bolt(h, (lx + d * 0.058, DECK_TOP + 0.016, lz), bare, axis="up",
                   d=0.014, head_h=0.009, phase=2.1 * d)
    # 灯罩骨架（4 根立柱 + 顶盖），灯芯由场景侧自发光方块担任
    beacon_y = DECK_TOP + 1.63
    for a in range(4):
        ang2 = math.radians(45.0 + 90.0 * a)
        h.add(bm_box((0.014, 0.20, 0.014), bevel=0.002, segments=2), deep,
              loc=(lx + 0.082 * math.cos(ang2), beacon_y + 0.10, lz + 0.082 * math.sin(ang2)))
    h.add(S.bm_lathe([(0.0, beacon_y + 0.20), (0.105, beacon_y + 0.20),
                      (0.105, beacon_y + 0.213), (0.055, beacon_y + 0.24),
                      (0.0, beacon_y + 0.24)], seg=16), deep, loc=(lx, 0.0, lz))
    h.add(S.bm_lathe([(0.088, beacon_y + 0.012), (0.100, beacon_y + 0.012),
                      (0.100, beacon_y + 0.034), (0.088, beacon_y + 0.034),
                      (0.088, beacon_y + 0.012)], seg=16), yellow, loc=(lx, 0.0, lz))

    obj = N.finish_asset(h, {"ao_rays": 11, "ao_dist": 0.17, "seed": 23, "ground_z": 0.0})
    print("NAILONG_OBS_DECK tris=%d" % K.tri_count([obj]))
    N.report_mats(obj)
    N.report_bbox("ObservationDeck", obj)
    N.check_islands(obj)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    S.export_glb(OUT, "ObservationDeck")
    print("NAILONG_OBS_DECK exported", os.path.exists(OUT), os.path.getsize(OUT))


if __name__ == "__main__":
    main()
