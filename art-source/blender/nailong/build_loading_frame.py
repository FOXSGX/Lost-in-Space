"""奶龙星 · 北侧装卸门架（Mid 级资产，按《美术制作与 AI 协作指南》九步流水线）

坐标：**Godot 约定（x 右 / y 上 / z 前）**，aq2kit 在合入时自动转 Blender Z-up。
尺寸：x 5.6 × y 3.9 × z 1.3；原点 = 两柱中心连线地面中点。

导出：assets/models/nailong/loading_frame.glb
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = r"C:\Users\31798\.openclaw\workspace\ref\art_sample_002\02_BLENDER_SOURCE\scripts"
sys.path.insert(0, KIT)

import aq2kit as K
import aqs_kit as S
from aqs_kit import Hero, bm_box

OUT = r"C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet\assets\models\nailong\loading_frame.glb"

COL_X = 2.40
COL_H = 3.30
BEAM_Y = 3.44


def main():
    K.reset_scene()

    cream = K.mat("M_PaintCream", (0.615, 0.578, 0.488), 0.46, 0.10)
    yellow = K.mat("M_PaintYellow", (0.80, 0.56, 0.09), 0.48, 0.08)
    orange = K.mat("M_PaintOrange", (0.70, 0.268, 0.062), 0.48, 0.10)
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.58, 0.45)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)

    h = Hero("LoadingFrame")

    def column(x):
        # 工字柱：web 0.10 + 双翼缘 0.24（沿 z 法向）
        h.add(bm_box((0.10, COL_H, 0.10), bevel=0.006, segments=2), deep, loc=(x, COL_H * 0.5, 0.0))
        for sz in (-0.06, 0.06):
            h.add(bm_box((0.24, COL_H, 0.022), bevel=0.004, segments=2), cream,
                  loc=(x, COL_H * 0.5, sz))
        # 承台底板 + 四件套地脚螺栓（凸台 + 垫圈 + 六角头，独立相位）
        h.plate((0.56, 0.036, 0.44), (x, 0.018, 0.0), deep, thickness=0.036, bevel=0.006, fold=None)
        for bx in (-0.20, 0.20):
            for bz in (-0.14, 0.14):
                h.bolt((x + bx, 0.036, bz), bare, axis="up", d=0.026, boss=True,
                       boss_mat=deep, phase=0.7 * bx + 1.3 * bz)
        # 三角加强肋（0.02 厚，沿 y-z 平面斜 42°）
        for sz, rx in ((-0.16, 42.0), (0.16, -42.0)):
            h.add(bm_box((0.30, 0.26, 0.020), bevel=0.003, segments=2), cream,
                  loc=(x, 0.20, sz), rot=(rx, 0.0, 0.0))
        # 柱脚焊道
        h.weld([(x - 0.12, 0.045, -0.062), (x + 0.12, 0.045, -0.062)], deep, r=0.006)
        h.weld([(x - 0.12, 0.045, 0.062), (x + 0.12, 0.045, 0.062)], deep, r=0.006)
        # 警示踢脚（贴柱，0.10 高）
        h.plate((0.36, 0.012, 0.36), (x, 0.055, 0.0), yellow, thickness=0.012, bevel=0.004, fold=None)

    column(-COL_X)
    column(COL_X)

    # 顶部工字梁（沿 x）：上下翼缘 + web
    for dy in (-0.09, 0.09):
        h.add(bm_box((5.20, 0.024, 0.26), bevel=0.005, segments=2), cream,
              loc=(0.0, BEAM_Y + dy, 0.0))
    h.add(bm_box((5.20, 0.16, 0.024), bevel=0.004, segments=2), deep, loc=(0.0, BEAM_Y, 0.0))

    # 节点板 + 螺栓行 + 焊缝
    for sx in (-1.0, 1.0):
        x = sx * COL_X
        h.plate((0.34, 0.30, 0.014), (x, BEAM_Y - 0.02, -0.14), deep, thickness=0.014,
                bevel=0.003, fold=None)
        h.bolt_row((x - 0.10, BEAM_Y - 0.16, -0.14), (x + 0.10, BEAM_Y - 0.16, -0.14), 3,
                   bare, axis="zn", d=0.020)
        h.weld([(x - 0.13, BEAM_Y - 0.20, -0.131), (x + 0.13, BEAM_Y - 0.20, -0.131)], deep)
        h.weld([(x - 0.13, BEAM_Y - 0.20, 0.131), (x + 0.13, BEAM_Y - 0.20, 0.131)], deep)

    # 斜撑（0.08 方管，柱头 → 梁中下）
    for sx in (-1.0, 1.0):
        h.add(bm_box((1.55, 0.08, 0.08), bevel=0.006, segments=2), cream,
              loc=(sx * 1.35, BEAM_Y - 0.42, 0.0), rot=(0.0, 0.0, -sx * 12.0))

    # 悬挂小车 + 轮 + 链条 + 吊钩
    ty = BEAM_Y - 0.26
    h.add(bm_box((0.46, 0.20, 0.34), bevel=0.012, segments=2), orange, loc=(0.85, ty, 0.0))
    for sx in (-0.16, 0.16):
        for sz in (-0.11, 0.11):
            h.add(bm_box((0.09, 0.06, 0.06), bevel=0.008, segments=2), bare,
                  loc=(0.85 + sx, ty + 0.12, sz), rot=(0.0, 90.0, 0.0))
    chain_top = ty - 0.10
    h.add(S.bm_tube([(0.85, chain_top, 0.0), (0.85, chain_top - 0.62, 0.0)], 0.020, seg=8), bare)
    h.add(bm_box((0.14, 0.24, 0.05), bevel=0.012, segments=3), yellow,
          loc=(0.85, chain_top - 0.72, 0.0))
    h.add(bm_box((0.20, 0.06, 0.05), bevel=0.010, segments=3), yellow,
          loc=(0.88, chain_top - 0.86, 0.0))

    # 沿柱线管 + 接线盒（左柱）
    h.add(S.bm_tube([(-COL_X + 0.16, 0.10, 0.16), (-COL_X + 0.16, 1.30, 0.16)], 0.032, seg=8), deep)
    h.add(bm_box((0.16, 0.12, 0.14), bevel=0.012, segments=2), deep,
          loc=(-COL_X + 0.16, 1.38, 0.16))
    h.add(bm_box((0.10, 0.02, 0.10), bevel=0.004, segments=2), yellow,
          loc=(-COL_X + 0.16, 1.45, 0.16))

    obj = h.finish(smooth=True, split_angle=32.0,
                   bake={"ao_rays": 11, "ao_dist": 0.17, "seed": 7, "ground_z": 0.0})
    print("NAILONG_LOADING_FRAME tris=%d" % K.tri_count([obj]))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    S.export_glb(OUT, "LoadingFrame")
    print("NAILONG_LOADING_FRAME exported", os.path.exists(OUT), os.path.getsize(OUT))


if __name__ == "__main__":
    main()
