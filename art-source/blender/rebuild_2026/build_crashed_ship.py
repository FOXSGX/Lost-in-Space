"""《迷失太空》巨型星际母舰级坠毁“归航号”飞船（约 78m 长 × 64m 翼展 × 26m 高）+ 巨型断翼残骸群
Blender 4.5 / Y-up Godot 坐标系（挂载在 FrostWorld Vector3(0, 0.7, 12)）：
- 前部机库（X∈[-6.8,+6.8], Y∈[0,6.8], Z∈[-6.8,+6.8]）保持 100% 中空畅通，玩家从庞大母舰的舰首下层登舱口走出；
- 主舰体向南（+Z）纵深延展至 Z=+62（世界 Z=+74），完全避开东西两侧仓库(X=-23)/车库(X=+24)与南区建筑(X=±52)；
- 整体大倾角【舰首俯冲扎雪 + 舰体左倾横滚 ~14° + 舰尾四联巨型引擎与 26m 双垂尾高高翘起】，体积压倒全基地所有建筑！
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix

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
    mats["M_Scorch"] = mats["M_DarkSteel"]
    mats["M_HullWhite"] = mats["M_PaintCream"]
    mats["M_GlowCyan"] = K.mat("M_GlowCyan", (0.20, 0.85, 0.96), 0.14, 0.0,
                               emit=(0.18, 0.84, 0.98), emit_strength=2.2)
    mats["M_CockpitGlass"] = mats["M_GlowCyan"]
    mats["M_GlowAmber"] = K.mat("M_GlowAmber", (0.98, 0.48, 0.10), 0.14, 0.0,
                                emit=(1.0, 0.44, 0.08), emit_strength=3.0)
    mats["M_GlowRed"] = K.mat("M_GlowRed", (0.98, 0.20, 0.10), 0.14, 0.0,
                              emit=(1.0, 0.18, 0.08), emit_strength=2.8)
    return mats


def finalize_and_export(hero, filename, seed=81, ao_rays=6, ground_z=-0.5):
    gain = dict(HM.WEAR_GAIN)
    obj = hero.finish(
        smooth=True,
        split_angle=34.0,
        bake={"ao_rays": ao_rays, "ao_dist": 0.35, "seed": seed, "mat_gain": gain, "ground_z": ground_z, "verbose": False},
    )
    tri = obj.modifiers.new("Tri", "TRIANGULATE")
    tri.quad_method = "BEAUTY"
    K.apply_modifiers(obj)
    out_path = os.path.join(OUT_DIR, filename)
    A.export_glb(out_path, obj.name)
    A.report(filename, obj)


def bm_cyl(r1, r2, h, segs=22):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi * 0.5, 3, 'X'))
    return bm


def bm_wedge(w, h, d, top_scale_x=0.72, top_scale_z=0.72, top_shift_z=0.0):
    bm = bmesh.new()
    hx, hy, hz = w * 0.5, h * 0.5, d * 0.5
    tx, tz = hx * top_scale_x, hz * top_scale_z
    v0 = bm.verts.new((-hx, -hy, -hz))
    v1 = bm.verts.new((hx, -hy, -hz))
    v2 = bm.verts.new((hx, -hy, hz))
    v3 = bm.verts.new((-hx, -hy, hz))
    v4 = bm.verts.new((-tx, hy, -tz + top_shift_z))
    v5 = bm.verts.new((tx, hy, -tz + top_shift_z))
    v6 = bm.verts.new((tx, hy, tz + top_shift_z))
    v7 = bm.verts.new((-tx, hy, tz + top_shift_z))
    bm.faces.new((v0, v1, v2, v3))
    bm.faces.new((v4, v7, v6, v5))
    bm.faces.new((v0, v4, v5, v1))
    bm.faces.new((v1, v5, v6, v2))
    bm.faces.new((v2, v6, v7, v3))
    bm.faces.new((v3, v7, v4, v0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(w, h, d) * 0.04, segments=2, affect="EDGES", clamp_overlap=True)
    return bm


def build_crashed_ship():
    """78m 长 × 64m 翼展 × 26m 高的星际母舰级坠毁‘归航号’（前下层保留 100% 畅通登舱机库）"""
    m = fresh_mats()
    h = A.Hero("HeroCrashedShip")

    # ------------------------------------------------------------------ 1. 舰首下层登舱机库内壁（严格避让 X∈[-6.8,+6.8], Y∈[0,6.8], Z∈[-6.8,+6.8]）
    for sx in (-1.0, 1.0):
        for iz in (-4.4, -1.4, 1.6, 4.6):
            h.add(A.bm_box((0.40, 6.4, 0.42), bevel=0.04, segments=2),
                  m["M_CastSteel"], loc=(sx * 6.74, 3.25, iz))
        h.add(A.bm_box((0.28, 0.34, 13.0), bevel=0.04, segments=2),
              m["M_PaintOrange"], loc=(sx * 6.72, 0.22, 0.0))
    h.add(A.bm_box((13.2, 6.6, 0.34), bevel=0.05, segments=2),
          m["M_DarkSteel"], loc=(0.0, 3.35, 6.82))
    for iz, rz in ((-4.6, 0.0), (-1.4, -6.0), (1.8, 3.0), (4.8, 0.0)):
        h.add(A.bm_box((13.4, 0.40, 0.42), bevel=0.04, segments=2),
              m["M_CastSteel"], loc=(0.0, 6.65, iz), rot=(0.0, 0.0, rz))
    h.add(A.bm_box((0.42, 0.16, 11.2), bevel=0.02, segments=2),
          m["M_GlowCyan"], loc=(3.2, 6.72, 0.0))
    h.add(A.bm_box((0.42, 0.16, 7.2), bevel=0.02, segments=2),
          m["M_GlowAmber"], loc=(-3.2, 6.52, -1.2), rot=(3.0, 0.0, -8.0))
    # 机库前出口门眉（高 Y=6.35，完全不挡人！）
    h.add(A.bm_box((7.2, 0.85, 0.95), bevel=0.08, segments=2),
          m["M_CastSteel"], loc=(0.0, 6.35, -7.25), rot=(0.0, 0.0, 5.0))
    h.add(A.bm_box((4.8, 0.24, 0.30), bevel=0.03, segments=2),
          m["M_GlowAmber"], loc=(0.5, 6.22, -7.70), rot=(0.0, 0.0, 5.0))

    # ------------------------------------------------------------------ 2. 前段装甲侧舷包覆（环抱登舱机库，宽度适中避开东西两栋站房）
    # 左舷压雪侧舱（向左倾倒并被压进雪坑）
    h.add(bm_wedge(5.6, 7.8, 22.0, top_scale_x=0.68, top_scale_z=0.88),
          m["M_HullWhite"], loc=(-9.8, 2.8, 2.0), rot=(-10.0, 2.0, 14.0))
    h.add(A.bm_box((5.8, 2.2, 21.0), bevel=0.16, segments=2),
          m["M_Scorch"], loc=(-10.4, 0.65, 1.8), rot=(-10.0, 2.0, 14.0))
    # 左舷前部焦黑撕裂骨架肋条
    for kz in (-5.0, -1.5, 2.0, 5.5, 9.0):
        h.add(A.bm_box((0.75, 6.2, 0.58), bevel=0.05, segments=2),
              m["M_DarkSteel"], loc=(-12.6, 3.0 + kz * 0.15, kz), rot=(-11.0, 6.0, 16.0))

    # 右舷抬升侧舱（随舰体左滚向上抬高！）
    h.add(bm_wedge(5.8, 9.2, 22.0, top_scale_x=0.70, top_scale_z=0.88),
          m["M_HullWhite"], loc=(10.0, 5.4, 2.2), rot=(-10.5, -2.0, 14.0))
    h.add(A.bm_box((0.55, 1.15, 19.5), bevel=0.06, segments=2),
          m["M_PaintOrange"], loc=(12.8, 5.8, 2.0), rot=(-10.5, -2.0, 14.0))
    for rz in (-5.0, -1.0, 3.0, 7.0, 11.0):
        h.add(A.bm_box((0.68, 8.6, 0.68), bevel=0.06, segments=2),
              m["M_CastSteel"], loc=(12.3, 5.4 + rz * 0.16, rz), rot=(-10.5, 0.0, 14.0))

    # 入口左右肩甲（紧包 X=±5 物理墙，中间 6m 通道 100% 畅通）
    h.add(bm_wedge(5.6, 6.8, 4.2, top_scale_x=0.74, top_scale_z=0.64, top_shift_z=0.6),
          m["M_HullWhite"], loc=(-6.2, 3.0, -7.6), rot=(-10.0, 5.0, 11.0))
    h.add(bm_wedge(5.6, 7.8, 4.2, top_scale_x=0.74, top_scale_z=0.64, top_shift_z=0.6),
          m["M_HullWhite"], loc=(6.2, 3.9, -7.6), rot=(-10.0, -5.0, 12.0))

    # ------------------------------------------------------------------ 3. 俯冲扎雪的巨型舰首鼻锥与舰桥头甲（Z=-7..-21）
    # 悬挑在登舱口正上方的厚重俯冲舰首甲板（Y=7.6..12.2，人从下面轻松走过！）
    h.add(bm_wedge(15.6, 4.4, 13.0, top_scale_x=0.58, top_scale_z=0.62, top_shift_z=2.0),
          m["M_HullWhite"], loc=(-0.4, 9.2, -10.8), rot=(-15.0, 0.0, 13.0))
    h.add(A.bm_box((11.5, 0.45, 2.0), bevel=0.05, segments=2),
          m["M_PaintOrange"], loc=(-0.4, 10.6, -12.4), rot=(-15.0, 0.0, 13.0))
    # 猛扎进左前雪坑的焦黑巨型舰首撞角（避开正中 X=0 通道，形成强烈的砸地视觉！）
    h.add(bm_wedge(8.4, 4.2, 9.2, top_scale_x=0.45, top_scale_z=0.42, top_shift_z=1.8),
          m["M_Scorch"], loc=(-5.8, 3.5, -16.2), rot=(-26.0, 10.0, 17.0))
    h.add(A.bm_box((6.2, 0.72, 0.72), bevel=0.06, segments=2),
          m["M_PaintOrange"], loc=(-6.4, 1.8, -19.6), rot=(-26.0, 10.0, 17.0))
    # 撞弯的两根巨型前伸探测炮管/空速针
    for sx in (-1.2, 1.2):
        h.add(bm_cyl(0.14, 0.05, 4.8, 10),
              m["M_CastSteel"], loc=(-6.4 + sx, 1.6, -21.2), rot=(72.0, 18.0, 0.0))

    # ------------------------------------------------------------------ 4. 巨无霸中后主舰体 + 多层指挥舰桥上层建筑（Z=+7..+48，高耸至 Y=22m！）
    # 中段主龙骨巨舰躯干（宽 26m × 高 14.5m × 长 38m，以 13° 大俯冲角高高向船尾昂起！）
    h.add(bm_wedge(26.5, 14.2, 38.0, top_scale_x=0.72, top_scale_z=0.86, top_shift_z=1.4),
          m["M_HullWhite"], loc=(1.2, 10.8, 25.5), rot=(-12.5, 0.0, 14.0))
    # 巨舰底部焦黑防热瓦腹甲
    h.add(bm_wedge(23.5, 3.4, 34.0, top_scale_x=0.88, top_scale_z=0.90),
          m["M_Scorch"], loc=(2.4, 3.6, 25.0), rot=(-12.5, 0.0, 14.0))
    # 贯通舰体左右两侧的醒目工业橙远征涂装宽带与散热百叶装甲
    for sx in (-1.0, 1.0):
        band_y = 7.6 if sx < 0 else 14.0
        h.add(A.bm_box((0.75, 2.2, 32.0), bevel=0.08, segments=2),
              m["M_PaintOrange"], loc=(sx * 12.8 + 1.2, band_y, 25.5), rot=(-12.5, 0.0, 14.0))
        for rz in (12.0, 18.5, 25.0, 31.5, 38.0):
            h.add(A.bm_box((1.1, 12.5, 1.2), bevel=0.08, segments=2),
                  m["M_CastSteel"], loc=(sx * 12.6 + 1.2, (7.4 if sx < 0 else 13.6) + (rz - 25.0) * 0.22, rz),
                  rot=(-12.5, 0.0, 14.0))

    # 上层指挥舰桥塔楼（坐落在主舰体背脊上方 Z=+6..+24, Y=14..21.5m，像真正星际巡洋舰的司令塔！）
    h.add(bm_wedge(14.5, 5.8, 17.5, top_scale_x=0.68, top_scale_z=0.72, top_shift_z=1.6),
          m["M_HullWhite"], loc=(-0.2, 15.8, 12.5), rot=(-12.5, 0.0, 14.0))
    # 指挥舰桥宽幅发光全景玻璃窗（右半边微亮冰青应急光，左半边破裂焦黑！）
    h.add(bm_wedge(6.2, 2.4, 4.4, top_scale_x=0.74, top_scale_z=0.66),
          m["M_CockpitGlass"], loc=(2.6, 15.8, 5.0), rot=(-14.0, 0.0, 14.0))
    h.add(bm_wedge(5.6, 2.2, 4.2, top_scale_x=0.74, top_scale_z=0.66),
          m["M_Scorch"], loc=(-3.2, 14.4, 5.0), rot=(-14.0, 0.0, 14.0))
    # 舰桥顶部雷达阵、通信天线与被撞掀翻的巨大背脊装甲盖板
    h.add(bm_wedge(6.8, 2.4, 24.0, top_scale_x=0.72, top_scale_z=0.86),
          m["M_CastSteel"], loc=(0.4, 19.6, 23.0), rot=(-12.5, 0.0, 14.0))
    h.add(A.bm_box((7.5, 0.55, 5.6), bevel=0.08, segments=2),
          m["M_Scorch"], loc=(-4.2, 17.6, 17.5), rot=(-28.0, 16.0, 38.0))
    h.add(A.bm_box((3.2, 1.8, 4.8), bevel=0.06, segments=2),
          m["M_GlowAmber"], loc=(-3.2, 16.2, 18.0), rot=(-12.5, 0.0, 14.0))
    # 舰桥顶端通讯锅与红色高空防撞灯
    h.add(bm_cyl(0.36, 0.24, 4.2, 12), m["M_CastSteel"], loc=(-1.2, 21.8, 14.0), rot=(-10.0, 0.0, 14.0))
    h.add(bm_cyl(2.2, 0.35, 0.72, 18), m["M_HullWhite"], loc=(-1.6, 23.8, 13.6), rot=(-32.0, 14.0, 14.0))

    # 前后衔接脊背甲壳（平滑盖住机库顶部 Z=-6..+10）
    h.add(bm_wedge(19.6, 3.6, 19.0, top_scale_x=0.68, top_scale_z=0.84, top_shift_z=0.8),
          m["M_HullWhite"], loc=(0.4, 10.6, 1.5), rot=(-12.5, 0.0, 14.0))

    # ------------------------------------------------------------------ 5. 史诗级不对称巨翼：右翼 34m 高耸斜刺天空，左翼齐根炸裂插雪！
    # 右翼（从 X=+12 一直延伸到 X=+42，仰起 23°，翼尖高达 Y=21m！远远看去震撼力爆棚！）
    h.add(bm_wedge(14.5, 3.8, 22.0, top_scale_x=0.80, top_scale_z=0.70, top_shift_z=2.4),
          m["M_HullWhite"], loc=(18.5, 11.2, 24.0), rot=(-10.0, 12.0, 22.0))
    h.add(A.bm_box((10.5, 0.55, 3.2), bevel=0.05, segments=2),
          m["M_PaintOrange"], loc=(19.0, 13.0, 23.5), rot=(-10.0, 12.0, 22.0))
    h.add(bm_wedge(14.0, 2.4, 15.0, top_scale_x=0.72, top_scale_z=0.58, top_shift_z=1.8),
          m["M_HullWhite"], loc=(30.8, 16.4, 30.2), rot=(-10.0, 18.0, 24.0))
    # 右翼尖巨大垂翼 + 青蓝航行灯
    h.add(bm_wedge(1.3, 6.8, 9.5, top_scale_x=0.50, top_scale_z=0.50, top_shift_z=1.5),
          m["M_PaintOrange"], loc=(37.2, 20.8, 33.8), rot=(-8.0, 14.0, 22.0))
    h.add(A.bm_box((0.9, 0.75, 1.1), bevel=0.05, segments=2),
          m["M_GlowCyan"], loc=(38.2, 23.8, 32.5), rot=(0.0, 0.0, 22.0))

    # 左翼（从 X=-12 仅残存 9m 锯齿焦黑断根狠狠压在雪地里，露出 5 根粗大断裂钛钢翼梁 + 炽热电弧！）
    h.add(bm_wedge(9.6, 3.5, 19.5, top_scale_x=0.78, top_scale_z=0.68, top_shift_z=1.8),
          m["M_HullWhite"], loc=(-15.8, 3.6, 22.0), rot=(-12.0, -10.0, 22.0))
    h.add(A.bm_box((3.8, 2.8, 16.5), bevel=0.10, segments=2),
          m["M_Scorch"], loc=(-20.2, 1.6, 23.5), rot=(-14.0, -14.0, 26.0))
    for bz in (15.5, 19.0, 22.5, 26.0, 29.5):
        h.add(A.bm_box((5.4, 0.65, 0.68), bevel=0.04, segments=2),
              m["M_CastSteel"], loc=(-22.4, 1.4 + (bz - 22.0) * 0.12, bz), rot=(-10.0, -18.0 + (bz - 22.0) * 1.4, 24.0))
    h.add(A.bm_box((1.6, 1.1, 3.4), bevel=0.05, segments=2),
          m["M_GlowAmber"], loc=(-21.2, 2.1, 23.0), rot=(0.0, 0.0, 22.0))

    # ------------------------------------------------------------------ 6. 四联巨型母舰离子主引擎集群 + 27 米高双垂尾（Z=+42..+60, Y=+11..+27m！）
    # 4 个直径 5.6m 的巨无霸离子推进喷口（上下双层或宽列四联阵，高高翘在半空喷烟冒火！）
    engines = [
        (-6.2, 12.6, 48.0, True),
        (-1.8, 15.8, 47.0, False),
        (4.2, 17.2, 47.0, True),
        (9.2, 15.4, 48.0, False),
    ]
    for ex, ey, ez, burning in engines:
        h.add(bm_cyl(3.4, 2.85, 10.5, 22),
              m["M_CastSteel"], loc=(ex, ey, ez), rot=(77.5, 0.0, 14.0))
        h.add(bm_cyl(3.58, 3.58, 1.2, 22),
              m["M_PaintOrange"], loc=(ex, ey - 0.5, ez - 2.6), rot=(77.5, 0.0, 14.0))
        h.add(bm_cyl(2.4, 3.25, 5.4, 24),
              m["M_Scorch"], loc=(ex, ey + 1.45, ez + 6.8), rot=(77.5, 0.0, 14.0))
        h.add(bm_cyl(1.85, 2.25, 1.2, 20),
              m["M_GlowAmber"] if burning else m["M_GlowRed"],
              loc=(ex, ey + 1.85, ez + 8.6), rot=(77.5, 0.0, 14.0))

    # 右侧 27 米超高巨型垂直尾翼（全地图标志性剪影！）
    h.add(bm_wedge(1.8, 13.8, 13.5, top_scale_x=0.44, top_scale_z=0.46, top_shift_z=2.8),
          m["M_HullWhite"], loc=(12.2, 22.8, 43.5), rot=(-12.0, 0.0, 4.0))
    h.add(A.bm_box((1.9, 2.0, 7.2), bevel=0.06, segments=2),
          m["M_PaintOrange"], loc=(12.8, 25.8, 45.2), rot=(-12.0, 0.0, 4.0))
    h.add(A.bm_box((0.95, 0.95, 1.2), bevel=0.05, segments=2),
          m["M_GlowRed"], loc=(13.1, 29.4, 47.0))

    # 左侧撞折歪斜 48° 的巨型断尾翼
    h.add(bm_wedge(1.7, 11.8, 12.2, top_scale_x=0.44, top_scale_z=0.46, top_shift_z=2.4),
          m["M_HullWhite"], loc=(-8.8, 17.5, 43.0), rot=(-14.0, -8.0, 48.0))
    h.add(A.bm_box((1.8, 1.8, 6.2), bevel=0.06, segments=2),
          m["M_PaintOrange"], loc=(-11.2, 19.6, 44.5), rot=(-14.0, -8.0, 48.0))

    # 舰腹折断甩出的巨型液压起落架
    h.add(bm_cyl(0.72, 0.88, 6.2, 14), m["M_CastSteel"], loc=(14.5, 4.2, 18.0), rot=(28.0, 0.0, -34.0))
    h.add(A.bm_box((3.6, 0.95, 5.2), bevel=0.10, segments=2), m["M_DarkSteel"], loc=(16.8, 1.4, 19.6), rot=(22.0, 14.0, -28.0))

    finalize_and_export(h, "hero_crashed_ship.glb", seed=81, ao_rays=6, ground_z=-0.5)


def build_wreck_debris():
    """配合 78m 巨型坠毁母舰的超大残骸散落场（22m 断裂左翼 + 甩飞巨型引擎舱 + 散落巨幅装甲板，绵延至船尾后 105m）"""
    m = fresh_mats()
    h = A.Hero("HeroShipWreckDebris")

    # 1. 折断甩飞的 22 米巨型左翼外段（如巨鲸尾鳍般斜插在船后左方雪地！）
    h.add(bm_wedge(13.5, 2.8, 19.5, top_scale_x=0.70, top_scale_z=0.58, top_shift_z=2.2),
          m["M_HullWhite"], loc=(-26.5, 4.2, 54.0), rot=(24.0, -28.0, -48.0))
    h.add(A.bm_box((9.2, 0.65, 3.2), bevel=0.05, segments=2),
          m["M_PaintOrange"], loc=(-26.0, 5.6, 53.2), rot=(24.0, -28.0, -48.0))
    h.add(bm_wedge(1.3, 6.4, 8.8, top_scale_x=0.52, top_scale_z=0.52, top_shift_z=1.5),
          m["M_PaintOrange"], loc=(-31.5, 8.8, 58.6), rot=(22.0, -26.0, -45.0))
    h.add(A.bm_box((3.8, 2.4, 10.5), bevel=0.08, segments=2),
          m["M_Scorch"], loc=(-21.8, 1.5, 50.0), rot=(24.0, -28.0, -48.0))

    # 2. 飞甩在船尾右后方的撕裂巨型辅助引擎舱（半埋雪里冒黑烟！）
    h.add(bm_cyl(3.2, 2.5, 7.6, 20),
          m["M_Scorch"], loc=(18.5, 1.8, 72.0), rot=(72.0, 32.0, 18.0))
    h.add(bm_cyl(3.38, 3.38, 1.0, 20),
          m["M_PaintOrange"], loc=(17.2, 2.1, 69.5), rot=(72.0, 32.0, 18.0))
    h.add(bm_cyl(1.75, 2.1, 0.9, 16),
          m["M_GlowAmber"], loc=(19.8, 1.6, 74.2), rot=(72.0, 32.0, 18.0))

    # 3. 沿 110 米迫降拖沟散落的 6 块巨幅扭曲船体装甲残片
    plates = [
        ((-10.5, 1.2, 66.0), (8.2, 0.58, 5.8), (18.0, 24.0, -18.0), "M_HullWhite"),
        ((7.2, 1.0, 78.0), (9.5, 0.65, 4.8), (-16.0, -35.0, 22.0), "M_Scorch"),
        ((-14.2, 1.6, 86.0), (6.8, 0.55, 7.2), (28.0, 18.0, 32.0), "M_PaintOrange"),
        ((10.8, 0.9, 94.0), (8.4, 0.58, 5.4), (14.0, -16.0, -25.0), "M_HullWhite"),
        ((-4.2, 0.85, 102.0), (10.5, 0.72, 4.2), (-20.0, 42.0, 15.0), "M_CastSteel"),
        ((4.5, 1.1, 112.0), (7.6, 0.55, 4.6), (22.0, -28.0, 18.0), "M_Scorch"),
    ]
    for loc, sz, rot, mkey in plates:
        h.add(A.bm_box(sz, bevel=0.08, segments=2), m[mkey], loc=loc, rot=rot)

    finalize_and_export(h, "hero_ship_wreck_debris.glb", seed=83, ao_rays=6, ground_z=-0.2)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    build_crashed_ship()
    build_wreck_debris()
    print("BUILD_COLOSSAL_CRASHED_SHIP_OK")


if __name__ == "__main__":
    main()
