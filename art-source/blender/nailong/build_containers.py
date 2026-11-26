"""奶龙星 · 集装箱（两个规格，Mid 级资产，按《美术制作与 AI 协作指南》九步流水线）

坐标：**Godot 约定（x 右 / y 上 / z 前）**；原点 = 箱体地面中心（底面 y=0）。
规格：A = 3.40 × 2.50 × 1.40（20ft 级）、B = 2.60 × 2.20 × 1.20（10ft 级）。

结构：8 只角件 → 4 根角柱 → 上下周圈梁（底梁/顶梁/端梁）→ 侧墙与端墙瓦楞板
      （真实波形放样，板面内缩 12 mm 形成装配阴影线）→ 门端双扇门 + 门框 +
      锁杆/把手/铰链 + 门封胶条 → 铭牌位（钢底板 + 螺栓）+ 顶部瓦楞盖板 + 底部叉车槽。

导出：assets/models/nailong/container_a.glb / container_b.glb
"""
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

OUT_DIR = r"C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet\assets\models\nailong"

CAST = 0.17        # 角件
POST = 0.13        # 角柱
RAIL_H = 0.14      # 周圈梁高
RAIL_T = 0.09
WALL_OFF = 0.045   # 墙板内缩（波纹顶到外皮以内 5 mm）
RIB_P = 0.28
RIB_A = 0.040


def build(name, L, H, D, seed, out_file):
    K.reset_scene()
    K._MATS.clear()

    cream = K.mat("M_PaintCream", (0.615, 0.578, 0.488), 0.46, 0.10)
    yellow = K.mat("M_PaintYellow", (0.80, 0.56, 0.09), 0.48, 0.08)
    orange = K.mat("M_PaintOrange", (0.70, 0.268, 0.062), 0.48, 0.10)
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.58, 0.45)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)
    rubber = K.mat("M_Rubber", (0.052, 0.058, 0.060), 0.86, 0.0)

    h = Hero(name)
    hx, hz = L * 0.5, D * 0.5

    # ---------------------------------------------------------- 角件（8 只）
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            for y in (0.0, H - CAST):
                h.add(bm_box((CAST, CAST, CAST), bevel=0.008, segments=2), deep,
                      loc=(sx * (hx - CAST * 0.5), y + CAST * 0.5, sz * (hz - CAST * 0.5)))
            # 角柱（角件之间）
            h.add(bm_box((POST, H - 2.0 * CAST, POST), bevel=0.005, segments=2), deep,
                  loc=(sx * (hx - CAST * 0.5), H * 0.5, sz * (hz - CAST * 0.5)))

    # ---------------------------------------------------------- 周圈梁
    beam_x = L - 2.0 * CAST
    beam_z = D - 2.0 * CAST
    for y in (0.02, H - RAIL_H - 0.02):
        for sz in (-1.0, 1.0):
            h.add(bm_box((beam_x, RAIL_H, RAIL_T), bevel=0.004, segments=2), deep,
                  loc=(0.0, y + RAIL_H * 0.5, sz * (hz - RAIL_T * 0.5)))
        for sx in (-1.0, 1.0):
            h.add(bm_box((RAIL_T, RAIL_H, beam_z), bevel=0.004, segments=2), deep,
                  loc=(sx * (hx - RAIL_T * 0.5), y + RAIL_H * 0.5, 0.0))
    # 底梁上一条窄黄带（箱体识别腰线，面积 < 8%）
    for sz in (-1.0, 1.0):
        h.add(bm_box((beam_x - 0.30, 0.045, 0.010), bevel=0.002, segments=2), yellow,
              loc=(0.0, 0.145, sz * (hz - RAIL_T * 0.5 + RAIL_T * 0.5)))

    # ---------------------------------------------------------- 侧墙（瓦楞）
    wall_h = H - 2.0 * (CAST + 0.02)
    wall_w = L - 2.0 * (CAST + 0.01)
    for sz, ry in ((1.0, 0.0), (-1.0, 180.0)):
        h.add(N.corrugated(wall_w, wall_h, thick=0.008, period=RIB_P, amp=RIB_A,
                           base=CAST + 0.02, seg_per=3),
              cream, loc=(0.0, 0.0, sz * (hz - WALL_OFF)), rot=(0.0, ry, 0.0))
    # 端墙（-x，封闭端）
    end_w = D - 2.0 * (CAST + 0.01)
    h.add(N.corrugated(end_w, wall_h, thick=0.008, period=RIB_P, amp=RIB_A,
                       base=CAST + 0.02, seg_per=3),
          cream, loc=(-hx + WALL_OFF, 0.0, 0.0), rot=(0.0, -90.0, 0.0))

    # ---------------------------------------------------------- 门端（+x）
    door_w = (D - 2.0 * (CAST + 0.01)) * 0.5 - 0.012
    dx = hx - 0.070
    for sz in (-1.0, 1.0):
        h.add(N.corrugated(door_w, wall_h - 0.02, thick=0.007, period=RIB_P, amp=RIB_A,
                           base=CAST + 0.03, seg_per=3),
              cream, loc=(dx, 0.0, sz * (door_w * 0.5 + 0.012)), rot=(0.0, 90.0, 0.0))
    # 门框：上下门槛/门媚角钢（竖向靠角件充当）
    for y in (CAST + 0.005, H - CAST - 0.055):
        h.add(bm_box((0.060, 0.05, beam_z), bevel=0.003, segments=2), deep,
              loc=(hx - 0.055, y + 0.025, 0.0))
    # 门封胶条（两扇门内缘，深色）
    h.add(bm_box((0.012, wall_h - 0.04, 0.026), bevel=0.003, segments=2), rubber,
          loc=(hx - 0.082, H * 0.5, 0.0))

    # 锁杆：4 根 + 上下导座 + 把手 + 凸轮座
    rods = (-(hz - CAST - 0.10), -(hz - CAST - 0.42),
            hz - CAST - 0.42, hz - CAST - 0.10)
    for i, rz in enumerate(rods):
        h.add(S.bm_cyl(0.013, H - 2.0 * CAST - 0.10, seg=8), bare,
              loc=(hx - 0.012, CAST + 0.06, rz))
        for y in (CAST + 0.20, H - CAST - 0.26):
            h.add(bm_box((0.032, 0.048, 0.070), bevel=0.004, segments=2), deep,
                  loc=(hx - 0.010, y, rz))
        h.add(bm_box((0.026, 0.055, 0.075), bevel=0.004, segments=2), deep,
              loc=(hx - 0.012, 0.055, rz))
        h.add(bm_box((0.030, 0.030, 0.030), bevel=0.004, segments=2), bare,
              loc=(hx - 0.012, CAST + 0.06, rz))
    # 把手（只在中间两根上，操作色）
    for sz in (-1.0, 1.0):
        h.add(bm_box((0.030, 0.075, 0.235), bevel=0.006, segments=2), orange,
              loc=(hx - 0.030, 1.16, sz * (hz - CAST - 0.26)))
        h.add(bm_box((0.030, 0.075, 0.235), bevel=0.006, segments=2), orange,
              loc=(hx - 0.030, 1.32, sz * (hz - CAST - 0.26)))
    # 铰链：每扇 3 只
    for sz in (-1.0, 1.0):
        for y in (0.42, H * 0.5, H - 0.42):
            h.add(bm_box((0.030, 0.135, 0.055), bevel=0.005, segments=2), deep,
                  loc=(hx - 0.030, y, sz * (hz - CAST - 0.02)))

    # ---------------------------------------------------------- 铭牌位
    py = 1.62
    pz = hz - 0.0015
    h.add(bm_box((0.38, 0.27, 0.010), bevel=0.002, segments=2), bare,
          loc=(-hx + 0.72, py, pz))
    for bx in (-0.145, 0.145):
        for by in (-0.095, 0.095):
            N.add_bolt(h, (-hx + 0.72 + bx, py + by, pz + 0.005), bare, axis="zp",
                       d=0.016, head_h=0.010, phase=1.1 * bx + 2.3 * by)
    # 小数据铭牌
    h.add(bm_box((0.18, 0.12, 0.008), bevel=0.002, segments=2), bare,
          loc=(-hx + 0.72, py - 0.24, pz - 0.002))
    for bx in (-0.060, 0.060):
        N.add_bolt(h, (-hx + 0.72 + bx, py - 0.24, pz + 0.002), bare, axis="zp",
                   d=0.013, head_h=0.008, phase=3.1 * bx)

    # ---------------------------------------------------------- 顶盖
    h.add(N.corrugated(L - 0.16, D - 0.16, thick=0.006, period=RIB_P, amp=0.026,
                       base=-(D - 0.16) * 0.5, seg_per=3),
          cream, loc=(0.0, H - 0.03, 0.0), rot=(-90.0, 0.0, 0.0))

    # ---------------------------------------------------------- 角件焊缝
    for sz in (-1.0, 1.0):
        for sx in (-1.0, 1.0):
            h.weld([(sx * (hx - CAST + 0.02), CAST + 0.005, sz * (hz - CAST * 0.5)),
                    (sx * (hx - CAST * 0.5), CAST + 0.005, sz * (hz - 0.02))],
                   deep, r=0.0045)

    obj = N.finish_asset(h, {"ao_rays": 11, "ao_dist": 0.17, "seed": seed, "ground_z": 0.0})
    print("NAILONG_CONTAINER %s tris=%d" % (name, K.tri_count([obj])))
    N.report_mats(obj)
    N.report_bbox(name, obj)
    N.check_islands(obj)
    out = os.path.join(OUT_DIR, out_file)
    os.makedirs(OUT_DIR, exist_ok=True)
    S.export_glb(out, name)
    print("NAILONG_CONTAINER exported", out, os.path.getsize(out))


def main():
    build("ContainerA", 3.40, 2.50, 1.40, 17, "container_a.glb")
    build("ContainerB", 2.60, 2.20, 1.20, 19, "container_b.glb")


if __name__ == "__main__":
    main()
