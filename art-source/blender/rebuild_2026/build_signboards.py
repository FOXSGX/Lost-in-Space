"""《迷失太空》太空舱实体挂牌金属框（吊牌 + 壁挂牌）Blender 4.5 锻造脚本"""

import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
KIT_DIR = os.path.join(REPO, "art-source", "deliveries", "ART-SAMPLE-002_TEAM_KIT", "02_BLENDER_SOURCE", "scripts")
OUT_DIR = os.path.join(REPO, "game", "assets", "models", "rebuild")
sys.path.insert(0, KIT_DIR)

import aq2kit as K
import aqs_kit as A
import hero_mats as HM


def fresh_mats():
    K.reset_scene()
    K._MATS.clear()
    mats = HM.build_materials()
    mats["M_SteelDeep"] = mats["M_DarkSteel"]
    mats["M_GlowAmber"] = K.mat("M_GlowAmber", (0.96, 0.68, 0.28), 0.16, 0.0,
                                emit=(0.98, 0.72, 0.34), emit_strength=1.5)
    return mats


def finalize(hero, filename, seed=401):
    obj = hero.finish(
        smooth=True,
        split_angle=34.0,
        bake={"ao_rays": 8, "ao_dist": 0.12, "seed": seed, "mat_gain": dict(HM.WEAR_GAIN), "ground_z": -1.0, "verbose": False},
    )
    tri = obj.modifiers.new("Tri", "TRIANGULATE")
    tri.quad_method = "BEAUTY"
    K.apply_modifiers(obj)
    A.export_glb(os.path.join(OUT_DIR, filename), obj.name)
    A.report(filename, obj)


def build_hanging_sign():
    """天花板/龙骨吊挂式实体航空双面金属指示牌框（中心原点在牌面中心，宽 2.52m × 高 0.80m）"""
    m = fresh_mats()
    h = A.Hero("HeroHangingSign")
    # 主厚重暗钢牌框底板
    h.add(A.bm_box((2.56, 0.84, 0.12), bevel=0.025, segments=2), m["M_SteelDeep"], loc=(0.0, 0.0, 0.0))
    # 奶油白内嵌金属边框饰条（上下各一条）
    for sy in (-0.42, 0.42):
        h.add(A.bm_box((2.52, 0.06, 0.16), bevel=0.015, segments=2), m["M_PaintCream"], loc=(0.0, sy, 0.0))
    # 左右工业橙防护角靴
    for sx in (-1.28, 1.28):
        h.add(A.bm_box((0.10, 0.86, 0.17), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(sx, 0.0, 0.0))
    # 顶部双吊杆 + 青铜固定法兰（向上延伸 0.72m 稳稳咬住上方龙骨/天花板）
    for sx in (-0.88, 0.88):
        h.add(A.bm_box((0.06, 0.72, 0.06), bevel=0.01, segments=2), m["M_CastSteel"], loc=(sx, 0.78, 0.0))
        h.add(A.bm_box((0.16, 0.08, 0.16), bevel=0.015, segments=2), m["M_Bronze"], loc=(sx, 0.46, 0.0))
        h.add(A.bm_box((0.18, 0.08, 0.18), bevel=0.015, segments=2), m["M_Bronze"], loc=(sx, 1.12, 0.0))
    # 牌顶暖色小灯罩条（照亮牌面）
    h.add(A.bm_box((1.8, 0.05, 0.18), bevel=0.01, segments=2), m["M_SteelDeep"], loc=(0.0, 0.47, 0.04))
    h.add(A.bm_box((1.65, 0.025, 0.06), bevel=0.005, segments=1), m["M_GlowAmber"], loc=(0.0, 0.44, 0.11))
    finalize(h, "hero_hanging_sign.glb", seed=401)


def build_wall_plaque():
    """舱壁实体金属壁挂指示牌框（中心原点在牌面中心，贴墙背板在 -Z，牌面朝 +Z，宽 1.76m × 高 0.68m）"""
    m = fresh_mats()
    h = A.Hero("HeroWallPlaque")
    # 贴墙背板
    h.add(A.bm_box((1.84, 0.76, 0.08), bevel=0.02, segments=2), m["M_SteelDeep"], loc=(0.0, 0.0, -0.02))
    # 左侧工业橙识别竖条 + 四角青铜紧固螺栓
    h.add(A.bm_box((0.09, 0.72, 0.11), bevel=0.018, segments=2), m["M_PaintOrange"], loc=(-0.90, 0.0, 0.0))
    h.add(A.bm_box((0.07, 0.72, 0.10), bevel=0.015, segments=2), m["M_PaintCream"], loc=(0.90, 0.0, 0.0))
    for sx in (-0.82, 0.82):
        for sy in (-0.31, 0.31):
            h.add(A.bm_box((0.05, 0.05, 0.04), bevel=0.01, segments=1), m["M_Bronze"], loc=(sx, sy, 0.03))
    # 顶部小遮檐照明灯条
    h.add(A.bm_box((1.36, 0.05, 0.16), bevel=0.01, segments=2), m["M_CastSteel"], loc=(0.0, 0.40, 0.04))
    h.add(A.bm_box((1.22, 0.024, 0.05), bevel=0.005, segments=1), m["M_GlowAmber"], loc=(0.0, 0.37, 0.09))
    finalize(h, "hero_wall_plaque.glb", seed=402)


def build_equip_pedestal():
    """训练舱居中对称英雄氧气装备展示台（顶面精确高度 y=0.95m，四面完全对称，无任何遮挡与偏斜）"""
    m = fresh_mats()
    m["M_GlowCyan"] = K.mat("M_GlowCyan", (0.20, 0.88, 0.98), 0.14, 0.0,
                            emit=(0.18, 0.86, 0.98), emit_strength=2.0)
    h = A.Hero("HeroEquipPedestal")
    # 扩底铸铁八角底座 + 收腰奶油白装甲机身 + 宽肩圆角台面
    h.add(A.bm_loft([
        (0.00, A.rrect_r(1.56, 1.56, 0.34, 6)),
        (0.14, A.rrect_r(1.48, 1.48, 0.32, 6)),
        (0.22, A.rrect_r(1.16, 1.16, 0.26, 6)),
        (0.72, A.rrect_r(1.12, 1.12, 0.26, 6)),
        (0.84, A.rrect_r(1.48, 1.48, 0.30, 6)),
        (0.94, A.rrect_r(1.42, 1.42, 0.28, 6)),
    ]), m["M_SteelDeep"])
    # 中腰奶油白识别装甲环壳
    h.add(A.bm_loft([
        (0.26, A.rrect_r(1.24, 1.24, 0.28, 6)),
        (0.68, A.rrect_r(1.20, 1.20, 0.27, 6)),
    ]), m["M_PaintCream"])
    # 顶面青铜精密托环 + 发光青蓝装备定位光圈（精确落在 y=0.94..0.96，托住氧气瓶）
    h.add(A.bm_lathe([(0.0, 0.93), (0.56, 0.93), (0.58, 0.96), (0.50, 0.965), (0.46, 0.945), (0.0, 0.945)], 28), m["M_Bronze"])
    h.add(A.bm_torus(0.42, 0.018, 28, 8), m["M_GlowCyan"], loc=(0.0, 0.955, 0.0))
    # 四角工业橙防撞护角与青铜螺栓
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            h.add(A.bm_box((0.20, 0.11, 0.20), bevel=0.022, segments=2), m["M_PaintOrange"], loc=(sx * 0.62, 0.89, sz * 0.62))
            h.add(A.bm_box((0.12, 0.26, 0.24), bevel=0.015, segments=2), m["M_CastSteel"], loc=(sx * 0.62, 0.22, sz * 0.62))
    finalize(h, "hero_equip_pedestal.glb", seed=403)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    build_hanging_sign()
    build_wall_plaque()
    build_equip_pedestal()
    print("SIGNBOARD_AND_PEDESTAL_GLBS_OK")
