"""《迷失太空》英雄资产包 Part 2：太空舱主龙骨拱架、驾驶舱台、地热涡轮发电机、霜巡无人机"""

import math
import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
KIT_DIR = os.path.join(REPO, "art-source", "deliveries", "ART-SAMPLE-002_TEAM_KIT", "02_BLENDER_SOURCE", "scripts")
OUT_DIR = os.path.join(REPO, "game", "assets", "models", "rebuild")
sys.path.insert(0, KIT_DIR)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import aq2kit as K
import aqs_kit as A
from build_hero_pack import fresh_mats, finalize_and_export


# 13. 太空舱重型承压龙骨拱架（宽 13.5m × 高 4.8m，直接取代平直方块舱顶）
def build_ship_rib_arch():
    m = fresh_mats()
    h = A.Hero("HeroShipRibArch")
    for sx in (-1.0, 1.0):
        # 落地铸铁靴 + 工业橙防撞底座
        h.add(A.bm_loft([
            (0.00, A.rrect_r(0.95, 0.92, 0.14, 4)),
            (0.22, A.rrect_r(0.84, 0.82, 0.12, 4)),
        ]), m["M_SteelDeep"], loc=(sx * 6.45, 0.0, 0.0))
        h.add(A.bm_loft([
            (0.22, A.rrect_r(0.68, 0.72, 0.10, 4)),
            (0.92, A.rrect_r(0.60, 0.64, 0.09, 4)),
        ]), m["M_PaintOrange"], loc=(sx * 6.45, 0.0, 0.0))
        h.bolt_row((sx * 6.10, 0.78, -0.22), (sx * 6.10, 0.78, 0.22), 3, m["M_BareSteel"], axis="xn" if sx > 0 else "xp", d=0.032)
        # 奶油白竖向肋柱 + 斜肩承压拱臂
        h.add(A.bm_loft([
            (0.92, A.rrect_r(0.56, 0.58, 0.09, 4)),
            (2.85, A.rrect_r(0.50, 0.54, 0.08, 4)),
        ]), m["M_PaintCream"], loc=(sx * 6.45, 0.0, 0.0))
        h.add(A.bm_tube([
            (sx * 6.45, 2.75, 0.0), (sx * 5.20, 4.10, 0.0), (sx * 3.40, 4.65, 0.0)
        ], 0.26, seg=8), m["M_SteelDeep"])
        # 内侧伴热粗导管
        h.add(A.bm_tube([
            (sx * 5.95, 0.30, 0.28), (sx * 5.95, 2.65, 0.28), (sx * 4.85, 3.85, 0.28)
        ], 0.075, seg=8), m["M_Copper"])
    # 顶冠奶油白重型主梁 + 嵌顶暖光灯槽
    h.add(A.bm_box((7.2, 0.44, 0.64), bevel=0.06, segments=3), m["M_PaintCream"], loc=(0.0, 4.68, 0.0))
    h.add(A.bm_box((5.4, 0.08, 0.24), bevel=0.015, segments=2), m["M_Glass"], loc=(0.0, 4.44, 0.0))
    finalize_and_export(h, "hero_ship_rib_arch.glb", seed=113)


# 14. 舰桥英雄驾驶台 + 装甲座椅
def build_pilot_pod():
    m = fresh_mats()
    h = A.Hero("HeroPilotPod")
    # 控制台主壳（奶油白圆角放样）
    h.add(A.bm_loft([
        (0.00, A.rrect_r(1.55, 0.85, 0.16, 4)),
        (0.18, A.rrect_r(1.42, 0.76, 0.14, 4)),
        (0.86, A.rrect_r(1.62, 0.88, 0.16, 4)),
        (1.02, A.rrect_r(1.50, 0.78, 0.14, 4)),
    ]), m["M_PaintCream"], loc=(0.0, 0.0, -0.45))
    h.add(A.bm_box((1.38, 0.10, 0.52), bevel=0.02, segments=2), m["M_SteelDeep"], loc=(0.0, 1.04, -0.45), rot=(22.0, 0.0, 0.0))
    h.add(A.bm_box((1.16, 0.04, 0.32), bevel=0.008, segments=2), m["M_GlowCyan"], loc=(0.0, 1.09, -0.46), rot=(22.0, 0.0, 0.0))
    # 双推力操纵杆（工业橙手柄）
    for sx in (-0.36, 0.36):
        h.add(A.bm_cyl(0.022, 0.20, seg=8), m["M_BareSteel"], loc=(sx, 1.02, -0.18), rot=(-22.0, 0.0, 0.0))
        h.add(A.bm_box((0.14, 0.06, 0.06), bevel=0.015, segments=2), m["M_PaintOrange"], loc=(sx, 1.20, -0.25))
    # 旋转底座 + 装甲高背驾驶椅
    h.add(A.bm_lathe([(0.0, 0.0), (0.38, 0.0), (0.38, 0.08), (0.14, 0.14), (0.14, 0.48), (0.0, 0.48)], 18), m["M_SteelDeep"], loc=(0.0, 0.0, 0.48))
    h.add(A.bm_box((0.76, 0.16, 0.72), bevel=0.045, segments=3), m["M_Rubber"], loc=(0.0, 0.54, 0.48))
    h.add(A.bm_box((0.74, 0.88, 0.18), bevel=0.05, segments=3), m["M_PaintCream"], loc=(0.0, 1.02, 0.78), rot=(-10.0, 0.0, 0.0))
    h.add(A.bm_box((0.52, 0.26, 0.14), bevel=0.04, segments=3), m["M_PaintOrange"], loc=(0.0, 1.54, 0.84))
    finalize_and_export(h, "hero_pilot_pod.glb", seed=114)


# 15. 极地地热涡轮核心发电机（动力站 / 雷达站核心视觉地标）
def build_geothermal_generator():
    m = fresh_mats()
    h = A.Hero("HeroGeothermalGen")
    # 混凝土重型地脚台
    h.add(A.bm_loft([
        (0.00, A.rrect_r(3.4, 3.4, 0.45, 5)),
        (0.32, A.rrect_r(3.1, 3.1, 0.40, 5)),
    ]), m["M_Concrete"])
    # 车削重型涡轮主体 + 青铜散热鳍片
    h.add(A.bm_lathe([
        (0.0, 0.32), (1.28, 0.32), (1.28, 0.58), (1.05, 0.72),
        (1.05, 2.85), (1.24, 3.00), (1.16, 3.45), (0.72, 3.90), (0.0, 3.90)
    ], 24), m["M_SteelDeep"])
    for i in range(5):
        h.add(A.bm_lathe([(0.0, 0.0), (1.26, 0.0), (1.26, 0.08), (0.0, 0.08)], 24), m["M_Bronze"], loc=(0.0, 0.95 + i * 0.40, 0.0))
    # 发光热能核心视窗环
    h.add(A.bm_cyl(1.10, 0.52, seg=24), m["M_ThermalCore"], loc=(0.0, 1.52, 0.0))
    # 四侧奶油白承力装甲护柱 + 工业橙底部加强靴
    for i in range(4):
        ang = i * 90.0 + 45.0
        px, pz = math.cos(ang * A.D2R) * 1.24, math.sin(ang * A.D2R) * 1.24
        h.add(A.bm_box((0.44, 0.72, 0.44), bevel=0.04, segments=2), m["M_PaintOrange"], loc=(px, 0.68, pz), rot=(0, -ang, 0))
        h.add(A.bm_box((0.36, 2.40, 0.36), bevel=0.04, segments=2), m["M_PaintCream"], loc=(px, 2.20, pz), rot=(0, -ang, 0))
    # 顶部蒸汽排风管
    h.add(A.bm_tube([(0.0, 3.85, 0.0), (0.0, 4.95, 0.0), (0.55, 5.25, 0.0)], 0.28, seg=12), m["M_CastSteel"])
    finalize_and_export(h, "hero_geothermal_generator.glb", seed=115)


# 16. 霜巡哨兵无人机（极寒生态/机械威胁，可被撞飞/吸推/热融击爆）
def build_frost_drone():
    m = fresh_mats()
    h = A.Hero("HeroFrostDrone")
    # 八角倒角奶油白+暗钢球形外壳
    h.add(A.bm_loft([
        (-0.48, A.rrect_r(0.70, 0.70, 0.24, 4)),
        (-0.18, A.rrect_r(1.18, 1.18, 0.38, 4)),
        (0.24, A.rrect_r(1.14, 1.14, 0.36, 4)),
        (0.52, A.rrect_r(0.68, 0.68, 0.22, 4)),
    ]), m["M_SteelDeep"])
    # 上装甲盖（奶油白）
    h.add(A.bm_loft([
        (0.18, A.rrect_r(1.22, 1.22, 0.40, 4)),
        (0.46, A.rrect_r(0.86, 0.86, 0.28, 4)),
    ]), m["M_PaintCream"])
    # 中心红色扫描独眼（明确警示威胁）
    h.add(A.bm_lathe([(0.0, 0.0), (0.28, 0.0), (0.28, 0.14), (0.20, 0.18), (0.0, 0.18)], 18),
          m["M_PaintOrange"], loc=(0.0, 0.0, -0.58), rot=(-90.0, 0.0, 0.0))
    h.add(A.bm_cyl(0.18, 0.08, seg=16), m["M_GlowRed"], loc=(0.0, 0.0, -0.68), rot=(90.0, 0.0, 0.0))
    # 两侧悬停推进器舱
    for sx in (-0.78, 0.78):
        h.add(A.bm_box((0.28, 0.16, 0.20), bevel=0.02, segments=2), m["M_BareSteel"], loc=(sx * 0.78, 0.04, 0.0))
        h.add(A.bm_lathe([(0.0, -0.35), (0.22, -0.35), (0.26, -0.10), (0.22, 0.26), (0.0, 0.26)], 14), m["M_CastSteel"], loc=(sx, 0.0, 0.0))
        h.add(A.bm_cyl(0.16, 0.06, seg=12), m["M_GlowCyan"], loc=(sx, -0.38, 0.0))
    finalize_and_export(h, "hero_frost_drone.glb", seed=116)


def main():
    build_ship_rib_arch()
    build_pilot_pod()
    build_geothermal_generator()
    build_frost_drone()
    print("ALL_4_PART2_HERO_GLBS_BUILT_OK")


if __name__ == "__main__":
    main()
