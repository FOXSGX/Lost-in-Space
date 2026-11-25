"""《迷失太空》全物品精细化 + 5件创意玩具 + 2座标志新建筑（Blender 4.5）
遵循 ART-SAMPLE-002 与《美术制作与AI协作指南》：
- 零裸方块，全车削/放样/多段倒角 + 70/15/10/8/2 色板；
- EdgeSplit 前烘焙 4 通道顶点色 Col；
- 全三角化导出至 game/assets/models/rebuild/。
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

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
    mats["M_ThermalCore"] = K.mat("M_ThermalCore", (0.95, 0.48, 0.12), 0.14, 0.0,
                                  emit=(1.0, 0.52, 0.14), emit_strength=2.2)
    mats["M_GlowCyan"] = K.mat("M_GlowCyan", (0.20, 0.85, 0.96), 0.14, 0.0,
                               emit=(0.18, 0.84, 0.98), emit_strength=2.0)
    mats["M_GlowAmber"] = K.mat("M_GlowAmber", (0.96, 0.62, 0.18), 0.16, 0.0,
                                emit=(0.96, 0.56, 0.14), emit_strength=2.0)
    mats["M_GlowRed"] = K.mat("M_GlowRed", (0.96, 0.24, 0.16), 0.16, 0.0,
                              emit=(1.0, 0.22, 0.14), emit_strength=2.2)
    mats["M_GlowGreen"] = K.mat("M_GlowGreen", (0.18, 0.86, 0.54), 0.18, 0.0,
                                emit=(0.18, 0.88, 0.54), emit_strength=1.8)
    mats["M_Teal"] = K.mat("M_Teal", (0.16, 0.56, 0.58), 0.38, 0.12)
    mats["M_GlassWarm"] = K.mat("M_GlassWarm", (0.68, 0.84, 0.86), 0.10, 0.18,
                                emit=(0.76, 0.62, 0.36), emit_strength=0.45)
    return mats


def finalize_and_export(hero, filename, seed=1, ao_rays=8, ground_z=0.0):
    gain = dict(HM.WEAR_GAIN)
    gain["M_ThermalCore"] = 0.2
    gain["M_Teal"] = 0.75
    gain["M_GlassWarm"] = 0.15
    obj = hero.finish(
        smooth=True,
        split_angle=34.0,
        bake={"ao_rays": ao_rays, "ao_dist": 0.14, "seed": seed, "mat_gain": gain, "ground_z": ground_z, "verbose": False},
    )
    tri = obj.modifiers.new("Tri", "TRIANGULATE")
    tri.quad_method = "BEAUTY"
    K.apply_modifiers(obj)
    out_path = os.path.join(OUT_DIR, filename)
    A.export_glb(out_path, obj.name)
    A.report(filename, obj)


def bm_sphere(radius=0.5, u_seg=18, v_seg=12):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u_seg, v_segments=v_seg, radius=radius)
    return bm


def bm_icosphere(radius=0.5, subdiv=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    return bm


def bm_cyl(r1, r2, h, segs=16):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    return bm


# ================================================================== A. 精细基础物品 (8件)

# 1. 极地高压氧气瓶 (高约 0.68m, 宽 0.28m)
def build_oxygen_bottle():
    m = fresh_mats()
    h = A.Hero("HeroOxygenBottle")
    # 底部黑色橡胶防撞靴
    h.add(A.bm_lathe([
        (0.00, 0.00), (0.145, 0.00), (0.152, 0.03), (0.148, 0.11), (0.132, 0.12), (0.00, 0.12)
    ], 24), m["M_Rubber"])
    # 奶油白高压无缝气瓶身（带上下半球圆弧肩）
    h.add(A.bm_lathe([
        (0.134, 0.10), (0.138, 0.16), (0.138, 0.45), (0.126, 0.50),
        (0.095, 0.54), (0.055, 0.565), (0.042, 0.58)
    ], 28), m["M_PaintCream"])
    # 中段青蓝氧气识别腰带 + 两条固定箍环
    h.add(A.bm_lathe([(0.140, 0.23), (0.144, 0.24), (0.144, 0.37), (0.140, 0.38)], 28), m["M_Teal"])
    for y_ring in (0.20, 0.41):
        h.add(A.bm_torus(0.140, 0.011, 24, 8), m["M_SteelDeep"], loc=(0.0, y_ring, 0.0))
    # 正面液位观察发光青条
    h.add(A.bm_box((0.032, 0.15, 0.025), bevel=0.006, segments=2), m["M_GlowCyan"], loc=(0.0, 0.305, 0.136))
    # 青铜减压阀座 + 侧出气嘴 + 压力表圆盘
    h.add(A.bm_lathe([(0.046, 0.57), (0.050, 0.62), (0.032, 0.64), (0.024, 0.67), (0.00, 0.67)], 18), m["M_Bronze"])
    h.add(bm_cyl(0.018, 0.016, 0.08, 14), m["M_BareSteel"], loc=(0.055, 0.61, 0.0), rot=(0, 0, 90))
    h.add(bm_cyl(0.034, 0.034, 0.024, 18), m["M_SteelDeep"], loc=(-0.052, 0.61, 0.02), rot=(90, 0, 20))
    h.add(bm_cyl(0.026, 0.026, 0.028, 16), m["M_GlowCyan"], loc=(-0.052, 0.61, 0.022), rot=(90, 0, 20))
    # 顶部工业橙十字阀门手轮
    h.add(A.bm_torus(0.064, 0.012, 20, 8), m["M_PaintOrange"], loc=(0.0, 0.675, 0.0))
    h.add(A.bm_box((0.12, 0.016, 0.018), bevel=0.004, segments=2), m["M_PaintOrange"], loc=(0.0, 0.675, 0.0))
    h.add(A.bm_box((0.018, 0.016, 0.12), bevel=0.004, segments=2), m["M_PaintOrange"], loc=(0.0, 0.675, 0.0))
    # 两侧防撞提手护弓
    for sx in (-1.0, 1.0):
        h.add(A.bm_box((0.022, 0.13, 0.028), bevel=0.005, segments=2), m["M_SteelDeep"], loc=(sx * 0.105, 0.58, 0.0))
    finalize_and_export(h, "hero_oxygen_bottle.glb", seed=301)


# 2. 战地极地医疗箱 (宽 0.44m × 高 0.36m × 厚 0.24m)
def build_medkit():
    m = fresh_mats()
    h = A.Hero("HeroMedkit")
    # 奶油白圆角硬壳箱体（上下放样带装配中缝）
    h.add(A.bm_loft([
        (0.00, A.rrect_r(0.42, 0.22, 0.045, 5)),
        (0.03, A.rrect_r(0.45, 0.24, 0.05, 5)),
        (0.30, A.rrect_r(0.45, 0.24, 0.05, 5)),
        (0.33, A.rrect_r(0.42, 0.22, 0.045, 5)),
    ]), m["M_PaintCream"])
    # 四角深钢防撞护角
    for sx in (-1.0, 1.0):
        for sy in (0.035, 0.295):
            h.add(A.bm_box((0.07, 0.065, 0.255), bevel=0.012, segments=2), m["M_SteelDeep"], loc=(sx * 0.20, sy, 0.0))
    # 两侧金属扣锁 + 顶部工业橙提手
    for sx in (-0.12, 0.12):
        h.add(A.bm_box((0.048, 0.055, 0.26), bevel=0.008, segments=2), m["M_Bronze"], loc=(sx, 0.31, 0.0))
        h.add(A.bm_box((0.028, 0.075, 0.032), bevel=0.006, segments=2), m["M_SteelDeep"], loc=(sx * 0.95, 0.355, 0.0))
    h.add(A.bm_box((0.23, 0.032, 0.038), bevel=0.010, segments=2), m["M_PaintOrange"], loc=(0.0, 0.39, 0.0))
    # 前后双面立体浮雕十字徽章（圆角青绿底板 + 奶油白立体十字，双面清晰醒目）
    for sz in (-1.0, 1.0):
        h.add(A.bm_box((0.18, 0.18, 0.024), bevel=0.014, segments=2), m["M_Teal"], loc=(0.0, 0.165, sz * 0.118))
        h.add(A.bm_box((0.125, 0.038, 0.030), bevel=0.006, segments=2), m["M_PaintCream"], loc=(0.0, 0.165, sz * 0.128))
        h.add(A.bm_box((0.038, 0.125, 0.030), bevel=0.006, segments=2), m["M_PaintCream"], loc=(0.0, 0.165, sz * 0.128))
        # 右上角生命指示绿灯
        h.add(A.bm_box((0.034, 0.034, 0.022), bevel=0.008, segments=2), m["M_GlowGreen"], loc=(0.145, 0.245, sz * 0.118))
    finalize_and_export(h, "hero_medkit.glb", seed=302)


# 3. 高能热能电池组 (0.38 × 0.42 × 0.26m)
def build_battery_pack():
    m = fresh_mats()
    h = A.Hero("HeroBatteryPack")
    # 铸铁重型底座与顶盖
    h.add(A.bm_box((0.36, 0.07, 0.24), bevel=0.014, segments=2), m["M_SteelDeep"], loc=(0.0, 0.035, 0.0))
    h.add(A.bm_box((0.36, 0.065, 0.24), bevel=0.014, segments=2), m["M_SteelDeep"], loc=(0.0, 0.34, 0.0))
    # 中间奶油白隔热主壳
    h.add(A.bm_box((0.28, 0.25, 0.20), bevel=0.018, segments=2), m["M_PaintCream"], loc=(0.0, 0.19, 0.0))
    # 双筒发光能量核心柱 + 铜散热片
    for sx in (-0.095, 0.095):
        h.add(bm_cyl(0.056, 0.056, 0.24, 18), m["M_GlowCyan"], loc=(sx, 0.19, 0.065))
        h.add(bm_cyl(0.056, 0.056, 0.24, 18), m["M_GlowCyan"], loc=(sx, 0.19, -0.065))
        for ry in (0.12, 0.19, 0.26):
            h.add(A.bm_torus(0.060, 0.008, 16, 6), m["M_Bronze"], loc=(sx, ry, 0.065))
            h.add(A.bm_torus(0.060, 0.008, 16, 6), m["M_Bronze"], loc=(sx, ry, -0.065))
    # 两侧工业橙防撞护杠
    for sx in (-0.175, 0.175):
        h.add(A.bm_box((0.028, 0.31, 0.036), bevel=0.008, segments=2), m["M_PaintOrange"], loc=(sx, 0.19, 0.09))
        h.add(A.bm_box((0.028, 0.31, 0.036), bevel=0.008, segments=2), m["M_PaintOrange"], loc=(sx, 0.19, -0.09))
    # 顶部提手与青铜电极柱
    h.add(A.bm_box((0.20, 0.028, 0.034), bevel=0.008, segments=2), m["M_PaintOrange"], loc=(0.0, 0.425, 0.0))
    for sx in (-0.085, 0.085):
        h.add(bm_cyl(0.018, 0.016, 0.065, 14), m["M_Bronze"], loc=(sx, 0.395, 0.0))
    finalize_and_export(h, "hero_battery_pack.glb", seed=303)


# 4. 便携熔冰热枪 / 热风机 (长 0.72m, 沿 -Z 指向枪口)
def build_heat_lance():
    m = fresh_mats()
    h = A.Hero("HeroHeatLance")
    # 奶油白流线主枪身
    h.add(A.bm_box((0.18, 0.19, 0.44), bevel=0.032, segments=3), m["M_PaintCream"], loc=(0.0, 0.16, 0.04))
    # 后部深钢动力仓 + 橙色温控仪表灯
    h.add(A.bm_box((0.20, 0.21, 0.16), bevel=0.022, segments=2), m["M_SteelDeep"], loc=(0.0, 0.16, 0.22))
    h.add(bm_cyl(0.042, 0.042, 0.03, 16), m["M_GlowAmber"], loc=(0.0, 0.17, 0.305), rot=(90, 0, 0))
    # 前段热辐射铜管 + 4 道圆环形散热翅片
    h.add(bm_cyl(0.062, 0.072, 0.34, 20), m["M_CastSteel"], loc=(0.0, 0.16, -0.26), rot=(90, 0, 0))
    for rz in (-0.16, -0.22, -0.28, -0.34):
        h.add(A.bm_torus(0.082, 0.012, 20, 8), m["M_Bronze"], loc=(0.0, 0.16, rz), rot=(90, 0, 0))
    # 灼热发光扩口喷嘴
    h.add(bm_cyl(0.095, 0.068, 0.10, 20), m["M_PaintOrange"], loc=(0.0, 0.16, -0.44), rot=(90, 0, 0))
    h.add(bm_cyl(0.066, 0.045, 0.06, 18), m["M_ThermalCore"], loc=(0.0, 0.16, -0.47), rot=(90, 0, 0))
    # 底部便携燃料罐 + 工业橡胶握把
    h.add(bm_cyl(0.052, 0.052, 0.22, 16), m["M_PaintOrange"], loc=(0.0, 0.02, -0.06), rot=(90, 0, 0))
    h.add(A.bm_box((0.085, 0.22, 0.11), bevel=0.018, segments=2), m["M_Rubber"], loc=(0.0, 0.01, 0.14), rot=(18, 0, 0))
    # 顶部提把护架
    h.add(A.bm_box((0.05, 0.026, 0.26), bevel=0.008, segments=2), m["M_SteelDeep"], loc=(0.0, 0.31, 0.04))
    for sz in (-0.08, 0.14):
        h.add(A.bm_box((0.05, 0.075, 0.032), bevel=0.006, segments=2), m["M_SteelDeep"], loc=(0.0, 0.27, sz))
    finalize_and_export(h, "hero_heat_lance.glb", seed=304)


# 5. 手持重力吸推炮 (长 0.82m, 沿 -Z 指向吸口)
def build_suction_gun():
    m = fresh_mats()
    h = A.Hero("HeroSuctionGun")
    # 奶油白厚重磁力机身
    h.add(A.bm_box((0.24, 0.24, 0.42), bevel=0.042, segments=3), m["M_PaintCream"], loc=(0.0, 0.20, 0.08))
    # 顶部青绿磁力散热盖板
    h.add(A.bm_box((0.18, 0.06, 0.30), bevel=0.014, segments=2), m["M_Teal"], loc=(0.0, 0.33, 0.06))
    # 3 道发光青蓝电磁加速线圈
    h.add(bm_cyl(0.085, 0.105, 0.36, 22), m["M_SteelDeep"], loc=(0.0, 0.20, -0.20), rot=(90, 0, 0))
    for rz in (-0.11, -0.20, -0.29):
        h.add(A.bm_torus(0.118, 0.016, 22, 8), m["M_GlowCyan"], loc=(0.0, 0.20, rz), rot=(90, 0, 0))
    # 宽大喇叭形重力收集口（橙色外罩 + 青铜爪片 + 内部发蓝光核）
    h.add(bm_cyl(0.20, 0.11, 0.16, 24), m["M_PaintOrange"], loc=(0.0, 0.20, -0.40), rot=(90, 0, 0))
    h.add(bm_cyl(0.14, 0.08, 0.06, 20), m["M_GlowCyan"], loc=(0.0, 0.20, -0.44), rot=(90, 0, 0))
    for ang in (0, 120, 240):
        rad = math.radians(ang)
        h.add(A.bm_box((0.036, 0.05, 0.15), bevel=0.008, segments=2), m["M_Bronze"],
              loc=(math.cos(rad) * 0.17, 0.20 + math.sin(rad) * 0.17, -0.42), rot=(0, 0, ang + 90))
    # 后部负压气罐 + 握把
    h.add(bm_cyl(0.085, 0.085, 0.18, 18), m["M_Bronze"], loc=(0.0, 0.20, 0.32), rot=(90, 0, 0))
    h.add(A.bm_box((0.095, 0.24, 0.12), bevel=0.02, segments=2), m["M_Rubber"], loc=(0.0, 0.02, 0.14), rot=(14, 0, 0))
    finalize_and_export(h, "hero_suction_gun.glb", seed=305)


# 6. 太空脆脆薯片袋 (鼓鼓的枕头铝箔包装)
def build_snack_pack():
    m = fresh_mats()
    h = A.Hero("HeroSnackPack")
    # 鼓囊囊的立体放样枕形袋身
    h.add(A.bm_loft([
        (0.00, A.rrect_r(0.28, 0.024, 0.006, 4)),
        (0.04, A.rrect_r(0.29, 0.085, 0.032, 5)),
        (0.18, A.rrect_r(0.32, 0.145, 0.055, 6)),
        (0.32, A.rrect_r(0.29, 0.085, 0.032, 5)),
        (0.36, A.rrect_r(0.28, 0.024, 0.006, 4)),
    ]), m["M_PaintOrange"])
    # 顶部与底部铝箔锯齿封口边
    for sy in (0.012, 0.35):
        h.add(A.bm_box((0.29, 0.028, 0.018), bevel=0.004, segments=2), m["M_Bronze"], loc=(0.0, sy, 0.0))
    # 正反面奶油白口味腰封 + 青色小标志
    h.add(A.bm_box((0.27, 0.12, 0.148), bevel=0.016, segments=2), m["M_PaintCream"], loc=(0.0, 0.185, 0.0))
    for sz in (-0.076, 0.076):
        h.add(bm_cyl(0.036, 0.036, 0.012, 16), m["M_Teal"], loc=(0.0, 0.185, sz), rot=(90, 0, 0))
    finalize_and_export(h, "hero_snack_pack.glb", seed=306)


# 7. 极地科考纪念保温杯 (复古搪瓷马克杯)
def build_keepsake_mug():
    m = fresh_mats()
    h = A.Hero("HeroKeepsakeMug")
    # 车削杯身（微收底 + 外翻青铜杯沿）
    h.add(A.bm_lathe([
        (0.00, 0.00), (0.095, 0.00), (0.108, 0.03), (0.114, 0.22),
        (0.122, 0.255), (0.106, 0.262), (0.096, 0.23), (0.090, 0.04), (0.00, 0.04)
    ], 28), m["M_Teal"])
    # 奶油白装饰环带 + 金属铜杯口圈
    h.add(A.bm_lathe([(0.112, 0.08), (0.117, 0.09), (0.118, 0.17), (0.113, 0.18)], 28), m["M_PaintCream"])
    h.add(A.bm_torus(0.115, 0.010, 24, 8), m["M_Bronze"], loc=(0.0, 0.256, 0.0))
    # 侧面圆润 D 形杯把
    h.add(A.bm_torus(0.068, 0.015, 20, 8), m["M_PaintCream"], loc=(0.125, 0.135, 0.0), rot=(90, 0, 0))
    # 正面金色小星球徽章
    h.add(bm_sphere(0.030, 14, 10), m["M_PaintOrange"], loc=(0.0, 0.13, 0.112))
    h.add(A.bm_torus(0.044, 0.006, 18, 6), m["M_Bronze"], loc=(0.0, 0.13, 0.116), rot=(68, 0, 22))
    finalize_and_export(h, "hero_keepsake_mug.glb", seed=307)


# 8. 异常冰样采集罐 (密闭钢框 + 内部发光冰晶)
def build_sample_crystal():
    m = fresh_mats()
    h = A.Hero("HeroSampleCrystal")
    # 上下青铜密封端盖
    h.add(A.bm_lathe([(0.0, 0.0), (0.13, 0.0), (0.135, 0.06), (0.11, 0.08), (0.0, 0.08)], 20), m["M_SteelDeep"])
    h.add(A.bm_lathe([(0.0, 0.34), (0.11, 0.34), (0.135, 0.36), (0.13, 0.42), (0.0, 0.42)], 20), m["M_SteelDeep"])
    h.add(A.bm_torus(0.122, 0.014, 20, 8), m["M_Bronze"], loc=(0.0, 0.065, 0.0))
    h.add(A.bm_torus(0.122, 0.014, 20, 8), m["M_Bronze"], loc=(0.0, 0.355, 0.0))
    # 3 根防护笼柱
    for ang in (0, 120, 240):
        r = math.radians(ang)
        h.add(bm_cyl(0.014, 0.014, 0.30, 10), m["M_PaintOrange"], loc=(math.cos(r) * 0.112, 0.21, math.sin(r) * 0.112))
    # 内部悬浮多面体异常蓝晶簇
    h.add(bm_cyl(0.01, 0.062, 0.22, 6), m["M_GlowCyan"], loc=(0.0, 0.21, 0.0))
    h.add(bm_cyl(0.01, 0.040, 0.15, 6), m["M_CrystalCore"], loc=(0.032, 0.19, 0.02), rot=(16, 20, -18))
    h.add(bm_cyl(0.01, 0.036, 0.13, 6), m["M_CrystalCore"], loc=(-0.030, 0.22, -0.02), rot=(-14, -15, 22))
    finalize_and_export(h, "hero_sample_crystal.glb", seed=308)


# ================================================================== B. 5件创意趣味交互玩具 (5件)

# 9. 极地弹跳垫 (展开半径 0.95m, 放地上把人/车弹飞 15 米!)
def build_bounce_pad():
    m = fresh_mats()
    h = A.Hero("HeroBouncePad")
    # 厚重八角形深钢锚地底座
    h.add(A.bm_lathe([(0.0, 0.0), (0.86, 0.0), (0.92, 0.08), (0.76, 0.16), (0.0, 0.16)], 8), m["M_SteelDeep"])
    # 4 只抓地橙色稳定脚爪
    for ang in (45, 135, 225, 315):
        r = math.radians(ang)
        h.add(A.bm_box((0.26, 0.14, 0.18), bevel=0.025, segments=2), m["M_PaintOrange"],
              loc=(math.cos(r) * 0.82, 0.07, math.sin(r) * 0.82), rot=(0, -ang, 0))
    # 中段双圈螺旋青铜大弹簧
    h.add(A.bm_torus(0.56, 0.042, 24, 10), m["M_Bronze"], loc=(0.0, 0.21, 0.0))
    h.add(A.bm_torus(0.60, 0.042, 24, 10), m["M_Bronze"], loc=(0.0, 0.30, 0.0))
    # 顶部圆润加厚弹力跳板（奶油白外圈 + 工业橙弹性气垫 + 发光青蓝向上箭环）
    h.add(A.bm_lathe([(0.0, 0.34), (0.72, 0.34), (0.76, 0.42), (0.68, 0.47), (0.0, 0.48)], 24), m["M_PaintCream"])
    h.add(A.bm_torus(0.64, 0.046, 24, 10), m["M_PaintOrange"], loc=(0.0, 0.44, 0.0))
    h.add(A.bm_torus(0.36, 0.026, 22, 8), m["M_GlowCyan"], loc=(0.0, 0.485, 0.0))
    h.add(bm_cyl(0.18, 0.18, 0.04, 18), m["M_GlowCyan"], loc=(0.0, 0.475, 0.0))
    finalize_and_export(h, "hero_bounce_pad.glb", seed=309)


# 10. 极光信号弹 (可点燃投掷：暴风雪照明 + 取暖 + 引走无人机!)
def build_flare_stick():
    m = fresh_mats()
    h = A.Hero("HeroFlareStick")
    # 防滑橡胶尾柄 + 粗肋工业信号管
    h.add(A.bm_lathe([
        (0.00, 0.00), (0.042, 0.00), (0.045, 0.12), (0.038, 0.14), (0.00, 0.14)
    ], 18), m["M_Rubber"])
    h.add(A.bm_lathe([
        (0.042, 0.14), (0.046, 0.16), (0.046, 0.40), (0.042, 0.42)
    ], 20), m["M_PaintOrange"])
    # 奶油白警示斜环 + 铜质发火帽
    h.add(A.bm_torus(0.047, 0.009, 18, 6), m["M_PaintCream"], loc=(0.0, 0.22, 0.0))
    h.add(A.bm_torus(0.047, 0.009, 18, 6), m["M_PaintCream"], loc=(0.0, 0.32, 0.0))
    h.add(A.bm_lathe([(0.046, 0.41), (0.056, 0.43), (0.056, 0.47), (0.042, 0.49)], 18), m["M_Bronze"])
    # 顶部灼热珊瑚橙发光镁芯头
    h.add(A.bm_lathe([(0.00, 0.48), (0.042, 0.49), (0.036, 0.56), (0.00, 0.59)], 18), m["M_GlowRed"])
    finalize_and_export(h, "hero_flare_stick.glb", seed=310)


# 11. 复古极地磁力音响 (开启派对灯效 + 暖气 + 附近箱子跟着节拍蹦迪!)
def build_boombox():
    m = fresh_mats()
    h = A.Hero("HeroBoombox")
    # 奶油白复古圆角主机壳
    h.add(A.bm_loft([
        (0.00, A.rrect_r(0.64, 0.22, 0.04, 5)),
        (0.03, A.rrect_r(0.68, 0.25, 0.05, 5)),
        (0.32, A.rrect_r(0.68, 0.25, 0.05, 5)),
        (0.35, A.rrect_r(0.64, 0.22, 0.04, 5)),
    ]), m["M_PaintCream"])
    # 底部深钢脚垫 + 正面海军蓝/深钢面板
    h.add(A.bm_box((0.62, 0.26, 0.03), bevel=0.012, segments=2), m["M_SteelDeep"], loc=(0.0, 0.175, 0.12))
    # 左右双巨型重低音喇叭（铜圈 + 发光律动光环 + 立体振膜锥）
    for sx in (-0.20, 0.20):
        h.add(A.bm_torus(0.105, 0.016, 22, 8), m["M_Bronze"], loc=(sx, 0.175, 0.132), rot=(90, 0, 0))
        h.add(A.bm_torus(0.080, 0.012, 20, 8), m["M_GlowCyan"], loc=(sx, 0.175, 0.136), rot=(90, 0, 0))
        h.add(bm_sphere(0.036, 14, 10), m["M_PaintOrange"], loc=(sx, 0.175, 0.130))
    # 中央磁带舱窗口 + 发光均衡器条
    h.add(A.bm_box((0.15, 0.11, 0.025), bevel=0.008, segments=2), m["M_Teal"], loc=(0.0, 0.155, 0.132))
    for ex in (-0.045, -0.015, 0.015, 0.045):
        h.add(A.bm_box((0.020, 0.048, 0.024), bevel=0.004, segments=2), m["M_GlowAmber"], loc=(ex, 0.255, 0.132))
    # 顶部厚重铬金属大提手 + 斜伸复古天线
    for sx in (-0.23, 0.23):
        h.add(A.bm_box((0.036, 0.10, 0.038), bevel=0.008, segments=2), m["M_SteelDeep"], loc=(sx, 0.395, 0.0))
    h.add(A.bm_box((0.50, 0.034, 0.044), bevel=0.010, segments=2), m["M_PaintOrange"], loc=(0.0, 0.44, 0.0))
    h.add(bm_cyl(0.009, 0.005, 0.42, 10), m["M_BareSteel"], loc=(0.28, 0.52, -0.05), rot=(0, 0, -24))
    h.add(bm_sphere(0.018, 10, 8), m["M_PaintOrange"], loc=(0.365, 0.71, -0.05))
    finalize_and_export(h, "hero_boombox.glb", seed=311)


# 12. 雪地反重力碰碰球 (直径 0.68m, 可踢可射可撞飞无人机和队友!)
def build_bumper_orb():
    m = fresh_mats()
    h = A.Hero("HeroBumperOrb")
    # 中心切面二十面体防撞内核
    h.add(bm_icosphere(0.30, 2), m["M_PaintCream"], loc=(0.0, 0.34, 0.0))
    # 三轴交叉工业橙弹性防撞橡胶环
    h.add(A.bm_torus(0.315, 0.040, 24, 10), m["M_PaintOrange"], loc=(0.0, 0.34, 0.0))
    h.add(A.bm_torus(0.315, 0.036, 24, 10), m["M_SteelDeep"], loc=(0.0, 0.34, 0.0), rot=(90, 0, 0))
    h.add(A.bm_torus(0.315, 0.036, 24, 10), m["M_SteelDeep"], loc=(0.0, 0.34, 0.0), rot=(90, 90, 0))
    # 6 个发光反重力推进极点
    for dx, dy, dz in [(1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1)]:
        h.add(bm_sphere(0.068, 14, 10), m["M_GlowCyan"], loc=(dx * 0.285, 0.34 + dy * 0.285, dz * 0.285))
    finalize_and_export(h, "hero_bumper_orb.glb", seed=312)


# 13. 极地热可可保温壶 (喝一口回暖 + 回血 + 暖身加速!)
def build_thermos():
    m = fresh_mats()
    h = A.Hero("HeroThermos")
    # 底部橡胶防滑垫 + 经典暖橙圆柱不锈钢壶身
    h.add(A.bm_lathe([(0.0, 0.0), (0.088, 0.0), (0.092, 0.04), (0.086, 0.05), (0.0, 0.05)], 22), m["M_Rubber"])
    h.add(A.bm_lathe([
        (0.086, 0.045), (0.090, 0.07), (0.090, 0.29), (0.076, 0.34), (0.060, 0.36)
    ], 24), m["M_PaintOrange"])
    # 奶油白保温防滑套 + 暖琥珀温度显示条
    h.add(A.bm_lathe([(0.091, 0.11), (0.094, 0.12), (0.094, 0.24), (0.091, 0.25)], 24), m["M_PaintCream"])
    h.add(A.bm_box((0.022, 0.10, 0.020), bevel=0.005, segments=2), m["M_GlowAmber"], loc=(0.0, 0.18, 0.090))
    # 顶部旋盖式青铜保温杯盖
    h.add(A.bm_lathe([(0.062, 0.355), (0.084, 0.365), (0.082, 0.445), (0.070, 0.46), (0.0, 0.46)], 22), m["M_Bronze"])
    # 侧面折叠深钢提手
    h.add(A.bm_box((0.024, 0.17, 0.032), bevel=0.007, segments=2), m["M_SteelDeep"], loc=(0.112, 0.18, 0.0))
    for sy in (0.105, 0.255):
        h.add(A.bm_box((0.045, 0.024, 0.032), bevel=0.005, segments=2), m["M_SteelDeep"], loc=(0.095, sy, 0.0))
    finalize_and_export(h, "hero_thermos.glb", seed=313)


# ================================================================== C. 2座标志性新建筑英雄 GLB (2座)

# 14. 极地玻璃穹顶温室 / 观测舱 (半径 8.2m, 穹顶高 7.2m, 可步入式大拱门朝 +Z)
def build_geo_dome():
    m = fresh_mats()
    h = A.Hero("HeroGeoDome")
    R = 7.6
    # 重型混凝土/暗钢环形地基裙座（留出正南 +Z 大门缺口）
    segs = 16
    for i in range(segs):
        a0 = (i / segs) * math.tau
        a1 = ((i + 1) / segs) * math.tau
        am = 0.5 * (a0 + a1)
        # 朝 +Z (sin(am) > 0.85, |cos(am)| < 0.45) 留出宽敞大门入口
        if math.sin(am) > 0.82 and abs(math.cos(am)) < 0.42:
            continue
        seg_len = 2.0 * R * math.sin(math.pi / segs) + 0.22
        cx = math.cos(am) * R
        cz = math.sin(am) * R
        yaw = -math.degrees(am) + 90.0
        h.add(A.bm_box((seg_len, 1.35, 0.62), bevel=0.06, segments=2), m["M_SteelDeep"], loc=(cx, 0.68, cz), rot=(0, yaw, 0))
        h.add(A.bm_box((seg_len * 0.96, 0.55, 0.72), bevel=0.05, segments=2), m["M_PaintCream"], loc=(cx, 1.55, cz), rot=(0, yaw, 0))

    # 穹顶主体：8 道放射状暗钢主承压肋拱 + 3 道水平纬度圈 + 温暖泛光玻璃窗幕
    for k in range(8):
        ang = k * 22.5
        rad = math.radians(ang)
        # 每道经线拱由 6 段斜梁拼成圆润半球弧
        for s in range(6):
            t0 = (s / 6.0) * math.pi
            t1 = ((s + 1) / 6.0) * math.pi
            tm = 0.5 * (t0 + t1)
            p0 = Vector((math.cos(rad) * math.cos(t0) * R, 1.65 + math.sin(t0) * 5.6, math.sin(rad) * math.cos(t0) * R))
            p1 = Vector((math.cos(rad) * math.cos(t1) * R, 1.65 + math.sin(t1) * 5.6, math.sin(rad) * math.cos(t1) * R))
            # 跳过大门正前方最低一段，避免挡门
            if (p0.z > 5.5 or p1.z > 5.5) and abs(p0.x) < 2.6 and min(p0.y, p1.y) < 3.6:
                continue
            mid = (p0 + p1) * 0.5
            vec = p1 - p0
            L = vec.length
            # 用近似角度放钢肋梁
            horiz = math.hypot(vec.x, vec.z)
            pitch = -math.degrees(math.atan2(vec.y, max(horiz, 1e-4)))
            yaw = math.degrees(math.atan2(vec.x, vec.z))
            h.add(A.bm_box((0.28, 0.34, L + 0.14), bevel=0.04, segments=2), m["M_SteelDeep"], loc=mid, rot=(pitch, yaw, 0))

    # 3 道水平纬度环 + 穹顶暖光天窗玻璃片
    for ring_h, ring_r in [(3.6, 6.95), (5.3, 5.45), (6.65, 3.15)]:
        h.add(A.bm_torus(ring_r, 0.16, 24, 8), m["M_CastSteel"], loc=(0.0, ring_h, 0.0))
    # 穹顶顶部暖白通风帽 + 工业橙环箍
    h.add(A.bm_lathe([(0.0, 6.95), (2.2, 6.95), (2.4, 7.25), (1.7, 7.65), (0.0, 7.75)], 20), m["M_PaintCream"])
    h.add(A.bm_torus(2.25, 0.14, 20, 8), m["M_PaintOrange"], loc=(0.0, 7.15, 0.0))
    # 穹顶玻璃片（分 2 圈暖光幕墙，避开南面大门）
    for tier_y, tier_r, tilt, ph in [(2.75, 7.25, 22.0, 1.85), (4.60, 6.10, 44.0, 1.95), (6.15, 4.15, 64.0, 1.85)]:
        for i in range(12):
            a = (i / 12.0) * math.tau
            if tier_y < 3.5 and math.sin(a) > 0.78 and abs(math.cos(a)) < 0.48:
                continue
            px = math.cos(a) * tier_r
            pz = math.sin(a) * tier_r
            pw = 2.0 * tier_r * math.sin(math.pi / 12.0) * 0.90
            yaw = -math.degrees(a) + 90.0
            h.add(A.bm_box((pw, ph, 0.08), bevel=0.015, segments=1), m["M_GlassWarm"],
                  loc=(px, tier_y, pz), rot=(-tilt, yaw, 0))

    # 正南 (+Z) 工业橙气闸门廊通道（宽 4.6m, 高 4.2m, 绝不挡玩家进出）
    for sx in (-2.55, 2.55):
        h.add(A.bm_box((0.55, 4.1, 3.4), bevel=0.06, segments=2), m["M_PaintCream"], loc=(sx, 2.05, R + 0.9))
        h.add(A.bm_box((0.68, 0.65, 3.6), bevel=0.06, segments=2), m["M_PaintOrange"], loc=(sx, 0.35, R + 0.9))
    h.add(A.bm_box((5.8, 0.62, 3.7), bevel=0.08, segments=2), m["M_PaintOrange"], loc=(0.0, 4.25, R + 0.95))
    h.add(A.bm_box((4.4, 0.24, 0.24), bevel=0.04, segments=2), m["M_GlowAmber"], loc=(0.0, 3.85, R + 2.6))

    # 温室内部环形水培发光苗床装饰（靠近周壁，中间完全空出给玩家活动与放道具）
    for ang in (20, 65, 115, 160, 200, 245, 295, 340):
        rad = math.radians(ang)
        if math.sin(rad) > 0.72 and abs(math.cos(rad)) < 0.50:
            continue
        bx = math.cos(rad) * 5.6
        bz = math.sin(rad) * 5.6
        h.add(A.bm_box((2.1, 0.85, 1.1), bevel=0.06, segments=2), m["M_PaintCream"],
              loc=(bx, 0.42, bz), rot=(0, -ang + 90, 0))
        h.add(A.bm_box((1.7, 0.25, 0.72), bevel=0.04, segments=2), m["M_GlowGreen"],
              loc=(bx, 0.92, bz), rot=(0, -ang + 90, 0))
    finalize_and_export(h, "hero_geo_dome.glb", seed=314, ao_rays=6)


# 15. 极地高空通讯气象塔 (底座 7×7m, 塔高 18.5m, 强垂直地标剪影!)
def build_comms_tower():
    m = fresh_mats()
    h = A.Hero("HeroCommsTower")
    # 四角混凝土重型承台基础 + 4 根收分钢构塔腿 (0 -> 14.5m)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            h.add(A.bm_box((1.5, 1.1, 1.5), bevel=0.08, segments=2), m["M_SteelDeep"], loc=(sx * 2.8, 0.55, sz * 2.8))
            h.add(A.bm_box((1.1, 0.55, 1.1), bevel=0.06, segments=2), m["M_PaintOrange"], loc=(sx * 2.7, 1.25, sz * 2.7))
            # 塔腿分 3 段向上收拢
            pts = [(2.7, 1.2), (2.05, 5.8), (1.45, 10.4), (1.05, 14.6)]
            for k in range(len(pts) - 1):
                r0, y0 = pts[k]
                r1, y1 = pts[k + 1]
                p0 = Vector((sx * r0, y0, sz * r0))
                p1 = Vector((sx * r1, y1, sz * r1))
                mid = (p0 + p1) * 0.5
                v = p1 - p0
                horiz = math.hypot(v.x, v.z)
                pitch = -math.degrees(math.atan2(v.y, max(horiz, 1e-4)))
                yaw = math.degrees(math.atan2(v.x, v.z))
                h.add(A.bm_box((0.36, 0.36, v.length + 0.16), bevel=0.04, segments=2), m["M_CastSteel"], loc=mid, rot=(pitch, yaw, 0))

    # 3 层水平连系钢环 + 交叉斜撑
    for ly, lr in [(5.4, 2.15), (9.8, 1.55), (14.2, 1.12)]:
        for sz in (-lr, lr):
            h.add(A.bm_box((lr * 2.1, 0.26, 0.26), bevel=0.03, segments=2), m["M_SteelDeep"], loc=(0.0, ly, sz))
        for sx in (-lr, lr):
            h.add(A.bm_box((0.26, 0.26, lr * 2.1), bevel=0.03, segments=2), m["M_SteelDeep"], loc=(sx, ly, 0.0))

    # 悬挑中层气象观察室 (y = 8.4 .. 11.4m, 奶油白外壳 + 暖光全景窗 + 工业橙安全护栏)
    h.add(A.bm_loft([
        (8.3, A.rrect_r(5.4, 5.4, 0.85, 5)),
        (8.8, A.rrect_r(6.2, 6.2, 0.95, 5)),
        (11.1, A.rrect_r(6.2, 6.2, 0.95, 5)),
        (11.5, A.rrect_r(5.5, 5.5, 0.85, 5)),
    ]), m["M_PaintCream"])
    # 四面发光暖色观景玻璃窗
    for sx in (-3.05, 3.05):
        h.add(A.bm_box((0.18, 1.35, 3.8), bevel=0.03, segments=2), m["M_GlassWarm"], loc=(sx, 9.95, 0.0))
    for sz in (-3.05, 3.05):
        h.add(A.bm_box((3.8, 1.35, 0.18), bevel=0.03, segments=2), m["M_GlassWarm"], loc=(0.0, 9.95, sz))
    # 观察室下方工业橙装饰腰带
    h.add(A.bm_torus(3.25, 0.14, 24, 8), m["M_PaintOrange"], loc=(0.0, 8.75, 0.0))

    # 塔顶通讯主平台 + 巨型抛物面雷达锅 + 高空红橙航标针
    h.add(A.bm_lathe([(0.0, 14.3), (2.3, 14.3), (2.4, 14.7), (0.0, 14.7)], 16), m["M_SteelDeep"])
    # 巨型车削抛物面雷达天线（斜指天空）
    h.add(A.bm_lathe([
        (0.0, 0.0), (0.55, 0.08), (1.35, 0.32), (2.15, 0.72), (2.65, 1.15),
        (2.55, 1.24), (2.05, 0.82), (1.25, 0.42), (0.0, 0.14)
    ], 24), m["M_PaintCream"], loc=(0.0, 15.8, 0.35), rot=(-52, 24, 0))
    h.add(bm_cyl(0.08, 0.12, 1.65, 12), m["M_Bronze"], loc=(0.0, 16.4, 1.15), rot=(38, 24, 0))
    h.add(bm_sphere(0.24, 14, 10), m["M_PaintOrange"], loc=(0.0, 17.0, 1.75))
    # 避雷针与顶部发光航空红灯
    h.add(bm_cyl(0.14, 0.04, 4.2, 12), m["M_CastSteel"], loc=(0.0, 16.8, -0.7))
    h.add(bm_sphere(0.32, 14, 10), m["M_GlowRed"], loc=(0.0, 19.0, -0.7))
    finalize_and_export(h, "hero_comms_tower.glb", seed=315, ao_rays=6)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    builders = [
        build_oxygen_bottle,
        build_medkit,
        build_battery_pack,
        build_heat_lance,
        build_suction_gun,
        build_snack_pack,
        build_keepsake_mug,
        build_sample_crystal,
        build_bounce_pad,
        build_flare_stick,
        build_boombox,
        build_bumper_orb,
        build_thermos,
        build_geo_dome,
        build_comms_tower,
    ]
    for fn in builders:
        print(f"=== Building {fn.__name__} ===")
        fn()
    print(f"ALL {len(builders)} ITEMS & BUILDINGS BUILT OK -> {OUT_DIR}")


if __name__ == "__main__":
    main()
