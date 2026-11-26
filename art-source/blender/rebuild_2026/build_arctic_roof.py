"""极地科考站英雄屋顶与工业上层结构（彻底消除平顶方盒感）"""
import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
KIT_DIR = os.path.join(REPO, "art-source", "deliveries", "ART-SAMPLE-002_TEAM_KIT", "02_BLENDER_SOURCE", "scripts")
sys.path.insert(0, KIT_DIR)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import aqs_kit as A
from build_hero_pack import fresh_mats, finalize_and_export


def build_arctic_roof():
    m = fresh_mats()
    h = A.Hero("HeroArcticRoof")
    # 单位归一化尺寸 10×10m，装配时按每栋建筑宽高缩放
    # 1. 四周深钢檐口女儿墙与倒角包边
    h.add(A.bm_loft([
        (0.00, A.rrect_r(10.3, 10.3, 0.42, 4)),
        (0.42, A.rrect_r(10.1, 10.1, 0.40, 4)),
    ]), m["M_SteelDeep"])
    # 2. 双坡收分奶油白保温屋盖（带天窗脊线，彻底告别平顶鞋盒）
    h.add(A.bm_loft([
        (0.42, A.rrect_r(9.6, 9.6, 0.36, 4)),
        (1.65, A.rrect_r(6.2, 8.6, 0.30, 4)),
        (2.15, A.rrect_r(3.4, 7.6, 0.24, 4)),
    ]), m["M_PaintCream"])
    # 3. 四道外置深钢加强肋拱（跨屋面承力结构）
    for sz in (-3.2, -1.1, 1.1, 3.2):
        h.add(A.bm_tube([
            (-4.95, 0.35, sz), (-3.15, 1.72, sz), (-1.75, 2.22, sz),
            (1.75, 2.22, sz), (3.15, 1.72, sz), (4.95, 0.35, sz)
        ], 0.16, seg=8), m["M_SteelDeep"])
    # 4. 顶脊发光天窗条 + 工业橙屋顶通讯/检修护栏 + 双排风冷却烟囱
    h.add(A.bm_box((1.2, 0.24, 6.4), bevel=0.04, segments=2), m["M_CastSteel"], loc=(0.0, 2.25, 0.0))
    h.add(A.bm_box((0.68, 0.08, 5.8), bevel=0.015, segments=2), m["M_GlowCyan"], loc=(0.0, 2.38, 0.0))
    for sx in (-2.2, 2.2):
        h.add(A.bm_lathe([(0.0, 0.0), (0.48, 0.0), (0.52, 0.35), (0.42, 1.15), (0.50, 1.28), (0.0, 1.28)], 14),
              m["M_CastSteel"], loc=(sx, 1.55, -2.2))
        h.add(A.bm_cyl(0.46, 0.14, seg=14), m["M_PaintOrange"], loc=(sx, 2.35, -2.2))
    # 屋顶边缘防撞警示黄条与通讯天线桅杆
    h.add(A.bm_box((9.8, 0.12, 0.16), bevel=0.02, segments=2), m["M_PaintYellow"], loc=(0.0, 0.36, 5.08))
    h.add(A.bm_cyl(0.08, 2.8, seg=8), m["M_BareSteel"], loc=(3.2, 1.6, 2.6))
    h.add(A.bm_torus(0.32, 0.05, 14, 8), m["M_PaintOrange"], loc=(3.2, 3.8, 2.6), rot=(90.0, 0.0, 0.0))
    finalize_and_export(h, "hero_arctic_roof.glb", seed=117)


if __name__ == "__main__":
    build_arctic_roof()
    print("ARCTIC_ROOF_BUILT_OK")
