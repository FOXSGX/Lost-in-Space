"""极地科考站建筑外骨架承力扶壁与保温舷窗模块（彻底消除平墙方盒感）"""
import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
KIT_DIR = os.path.join(REPO, "art-source", "deliveries", "ART-SAMPLE-002_TEAM_KIT", "02_BLENDER_SOURCE", "scripts")
sys.path.insert(0, KIT_DIR)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import aqs_kit as A
from build_hero_pack import fresh_mats, finalize_and_export


def build_wall_buttress():
    m = fresh_mats()
    h = A.Hero("HeroWallButtress")
    # 宽 10m × 高 7m 标准化外墙承力模块（两根斜撑扶壁 + 工业橙铸铁脚靴 + 横向伴热管 + 暖光双层保温窗）
    for sx in (-4.4, 4.4):
        # 扩底混凝土基脚
        h.add(A.bm_loft([
            (0.00, A.rrect_r(1.15, 1.35, 0.14, 3)),
            (0.32, A.rrect_r(0.95, 1.15, 0.12, 3)),
        ]), m["M_Concrete"], loc=(sx, 0.0, 0.35))
        # 工业橙抗撞柱靴
        h.add(A.bm_loft([
            (0.32, A.rrect_r(0.76, 0.92, 0.10, 3)),
            (1.18, A.rrect_r(0.64, 0.76, 0.09, 3)),
        ]), m["M_PaintOrange"], loc=(sx, 0.0, 0.32))
        h.bolt_row((sx - 0.18, 1.02, 0.72), (sx + 0.18, 1.02, 0.72), 2, m["M_BareSteel"], axis="zp", d=0.036)
        # 斜向收分深钢扶壁柱
        h.add(A.bm_loft([
            (1.18, A.rrect_r(0.58, 0.68, 0.08, 3)),
            (6.85, A.rrect_r(0.46, 0.44, 0.07, 3)),
        ]), m["M_SteelDeep"], loc=(sx, 0.0, 0.24))
    # 中段奶油白加厚护墙板带 + 保温伴热铜管
    h.add(A.bm_box((8.4, 0.42, 0.28), bevel=0.04, segments=2), m["M_PaintCream"], loc=(0.0, 1.15, 0.16))
    h.add(A.bm_box((8.4, 0.34, 0.24), bevel=0.03, segments=2), m["M_SteelDeep"], loc=(0.0, 5.45, 0.16))
    h.add(A.bm_tube([(-4.4, 1.55, 0.30), (4.4, 1.55, 0.30)], 0.068, seg=8), m["M_Copper"])
    # 中心倒角暖光保温舷窗（赋予极地站房“里面有暖气和生命”的视觉吸引力）
    h.add(A.bm_box((4.6, 2.05, 0.36), bevel=0.08, segments=3), m["M_SteelDeep"], loc=(0.0, 3.35, 0.18))
    h.add(A.bm_box((4.1, 1.55, 0.12), bevel=0.02, segments=2), m["M_Glass"], loc=(0.0, 3.35, 0.32))
    # 窗框竖向抗压中梃
    for mx in (-1.35, 0.0, 1.35):
        h.add(A.bm_box((0.14, 1.66, 0.20), bevel=0.02, segments=2), m["M_CastSteel"], loc=(mx, 3.35, 0.34))
    finalize_and_export(h, "hero_wall_buttress.glb", seed=118)


if __name__ == "__main__":
    build_wall_buttress()
    print("WALL_BUTTRESS_BUILT_OK")
