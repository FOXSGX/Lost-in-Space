"""奶龙星 · 场外场地便携装货口（Mid 级资产）

坐标：Godot 约定（x 右 / y 上 / z 前）；原点 = 门洞地面中心，开口朝 -x（玩家沿 +x 射入）。
结构：门槛踏板 + 两侧导流仓壁（瓦楞）→ 后挡板（瓦楞）→ 门框（H 型钢立柱 + 顶梁）
      → 门楣两块警示牌 + 两盏投光灯（带挂钩与发光透镜）→ 接地铜排 + 地脚螺栓。

导出：assets/models/nailong/arena_gate.glb
门洞默认半宽 2.2 m / 高 3.4 m；引擎侧按地图缩放 z，实现窄门/宽门。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = r"C:\Users\31798\.openclaw\workspace\ref\art_sample_002\02_BLENDER_SOURCE\scripts"
sys.path.insert(0, KIT)
sys.path.insert(0, HERE)

import aq2kit as K
import aqs_kit as S
from aqs_kit import Hero, bm_box, bm_cyl
import nailong_kit as N

OUT_DIR = r"C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet\assets\models\nailong"

HW = 2.2      # 门洞半宽（z）
H = 3.4       # 门洞高
DEPTH = 1.7   # 门体深度（x）


def build(out_file="arena_gate.glb"):
    K.reset_scene()
    K._MATS.clear()

    cream = K.mat("M_PaintCream", (0.615, 0.578, 0.488), 0.48, 0.08)
    yellow = K.mat("M_PaintYellow", (0.80, 0.56, 0.09), 0.48, 0.08)
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.58, 0.42)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)
    glow = K.mat("M_LampGlow", (0.95, 0.78, 0.42), 0.35, 0.0, emit=(1.0, 0.82, 0.48), emit_strength=6.0)

    h = Hero("ArenaGate")

    # ---------------------------------------------------------- 门槛与地面件
    h.add(bm_box((DEPTH + 0.5, 0.10, HW * 2.0 + 0.5), bevel=0.006, segments=2), deep,
          loc=(DEPTH * 0.5 - 0.1, 0.05, 0.0))
    h.add(bm_box((0.30, 0.05, HW * 2.0), bevel=0.006, segments=1), yellow,
          loc=(0.05, 0.105, 0.0))

    # ---------------------------------------------------------- 后挡板（瓦楞）
    h.add(N.corrugated(HW * 2.0 + 0.1, H - 0.2, thick=0.010, period=0.30, amp=0.05,
                       base=0.0, seg_per=4), cream,
          loc=(DEPTH, 0.10, 0.0), rot=(0.0, -90.0, 0.0))
    # 后挡板框
    for sz in (-1.0, 1.0):
        h.add(bm_box((0.16, H, 0.16), bevel=0.006, segments=2), deep,
              loc=(DEPTH - 0.06, H * 0.5, sz * (HW + 0.02)))
    h.add(bm_box((0.16, 0.16, HW * 2.0 + 0.2), bevel=0.006, segments=2), deep,
          loc=(DEPTH - 0.06, H - 0.02, 0.0))

    # ---------------------------------------------------------- 两侧导流仓壁
    for sz in (-1.0, 1.0):
        h.add(N.corrugated(DEPTH, H, thick=0.010, period=0.28, amp=0.045, seg_per=4), cream,
              loc=(DEPTH * 0.5, 0.0, sz * HW), rot=(0.0, 0.0, 0.0))
        # 仓壁外框
        h.add(bm_box((DEPTH + 0.1, 0.16, 0.16), bevel=0.006, segments=2), deep,
              loc=(DEPTH * 0.5, H, sz * HW))
        for sx in (0.0, DEPTH):
            h.add(bm_box((0.16, H, 0.16), bevel=0.006, segments=2), deep,
                  loc=(sx, H * 0.5, sz * HW))

    # ---------------------------------------------------------- 门框立柱（H 型）
    for sz in (-1.0, 1.0):
        z = sz * (HW + 0.10)
        h.add(bm_box((0.26, H + 0.5, 0.20), bevel=0.008, segments=2), deep,
              loc=(0.10, (H + 0.5) * 0.5, z))
        # 柱脚
        h.add(bm_box((0.50, 0.08, 0.42), bevel=0.006, segments=2), bare,
              loc=(0.10, 0.04, z))
        for dx in (-0.15, 0.15):
            for dz in (-0.12, 0.12):
                N.add_bolt(h, (0.10 + dx, 0.08, z + dz), bare, axis="up",
                           d=0.022, head_h=0.014, phase=1.3 * dx + 0.7 * dz)

    # 顶梁
    h.add(bm_box((0.34, 0.30, HW * 2.0 + 0.7), bevel=0.008, segments=2), deep,
          loc=(0.10, H + 0.32, 0.0))

    # ---------------------------------------------------------- 门楣警示牌
    for i, sz in enumerate((-1.0, 1.0)):
        h.add(bm_box((0.06, 0.46, 1.30), bevel=0.006, segments=2), yellow,
              loc=(-0.06, H + 0.34, sz * 0.80))
        h.add(bm_box((0.07, 0.40, 1.22), bevel=0.004, segments=1), deep,
              loc=(-0.07, H + 0.34, sz * 0.80))

    # ---------------------------------------------------------- 投光灯（两盏）
    for sz in (-1.0, 1.0):
        lx = 0.10
        lz = sz * (HW - 0.35)
        h.add(bm_box((0.10, 1.30, 0.10), bevel=0.004, segments=1), bare,
              loc=(lx, H + 1.05, lz))
        h.add(bm_box((0.34, 0.22, 0.34), bevel=0.008, segments=2), deep,
              loc=(lx, H + 1.75, lz))
        h.add(bm_box((0.30, 0.18, 0.03), bevel=0.004, segments=1), glow,
              loc=(lx - 0.18, H + 1.75, lz))

    # ---------------------------------------------------------- 接地铜排与踢脚
    for sz in (-1.0, 1.0):
        h.add(bm_box((0.05, 0.55, 0.09), bevel=0.003, segments=1), bare,
              loc=(DEPTH - 0.02, 0.32, sz * (HW - 0.18)))
        h.add(bm_box((0.12, 0.16, 0.22), bevel=0.004, segments=1), cream,
              loc=(DEPTH - 0.04, 0.14, sz * (HW - 0.18)))

    obj = N.finish_asset(h, {"ao_rays": 11, "ao_dist": 0.20, "seed": 41, "ground_z": 0.0})
    print("NAILONG_GATE tris=%d" % K.tri_count([obj]))
    N.report_mats(obj)
    N.report_bbox("ArenaGate", obj)
    out = os.path.join(OUT_DIR, out_file)
    os.makedirs(OUT_DIR, exist_ok=True)
    S.export_glb(out, "ArenaGate")
    print("NAILONG_GATE exported", out, os.path.getsize(out))


if __name__ == "__main__":
    build()
