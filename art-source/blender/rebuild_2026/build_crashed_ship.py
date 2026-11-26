"""《迷失太空》坠毁“归航号”大型写实科幻飞船 + 舱内返回主舱气闸门（Blender 4.5 / Y-up Godot 坐标系）
- aqs_kit 直接采用 Godot Y-up 坐标（+X 东/右舷，+Y 上，-Z 北/机头朝科考站，+Z 南/机尾双引擎）；
- 内部保留宽敞中空登舱机库（X∈[-6.8, +6.8], Y∈[0, 6.8], Z∈[-6.8, +6.8]），与 FrostWorld 物理碰撞完美契合；
- 外部包裹约 38m 长 × 41m 翼展 × 12.6m 高的坠毁宇航飞船：悬挑驾驶舱鼻锥、后掠重型三角翼（左翼梢折损插雪）、
  背部脊梁散热片、双巨型离子引擎喷口、双外倾垂尾与机腹着陆腿；
- 同步生成舱内高清加压气闸舱门 hero_ship_return_hatch.glb。
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
    mats["M_GlowAmber"] = K.mat("M_GlowAmber", (0.96, 0.58, 0.16), 0.16, 0.0,
                                emit=(0.98, 0.54, 0.14), emit_strength=2.4)
    mats["M_GlowRed"] = K.mat("M_GlowRed", (0.96, 0.22, 0.14), 0.16, 0.0,
                              emit=(1.0, 0.22, 0.14), emit_strength=2.4)
    return mats


def finalize_and_export(hero, filename, seed=71, ao_rays=6, ground_z=-0.4):
    gain = dict(HM.WEAR_GAIN)
    gain["M_Scorch"] = 0.85
    gain["M_HullWhite"] = 0.72
    gain["M_CockpitGlass"] = 0.15
    obj = hero.finish(
        smooth=True,
        split_angle=34.0,
        bake={"ao_rays": ao_rays, "ao_dist": 0.25, "seed": seed, "mat_gain": gain, "ground_z": ground_z, "verbose": False},
    )
    tri = obj.modifiers.new("Tri", "TRIANGULATE")
    tri.quad_method = "BEAUTY"
    K.apply_modifiers(obj)
    out_path = os.path.join(OUT_DIR, filename)
    A.export_glb(out_path, obj.name)
    A.report(filename, obj)


def bm_cyl(r1, r2, h, segs=20):
    """Y-up 圆柱/圆台（轴沿 Y 轴）"""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    # create_cone 默认沿 Blender Z 轴，旋至 Y 轴对齐 aqs_kit
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi * 0.5, 3, 'X'))
    return bm


def bm_wedge(w, h, d, top_scale_x=0.72, top_scale_z=0.72, top_shift_z=0.0):
    """Y-up 倒角梯形航天装甲块（X=宽, Y=高, Z=深；-Z朝前，+Z朝后）"""
    bm = bmesh.new()
    hx, hy, hz = w * 0.5, h * 0.5, d * 0.5
    tx, tz = hx * top_scale_x, hz * top_scale_z
    # 底面 y = -hy
    v0 = bm.verts.new((-hx, -hy, -hz))
    v1 = bm.verts.new((hx, -hy, -hz))
    v2 = bm.verts.new((hx, -hy, hz))
    v3 = bm.verts.new((-hx, -hy, hz))
    # 顶面 y = +hy
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
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(w, h, d) * 0.045, segments=2, affect="EDGES", clamp_overlap=True)
    return bm


def build_crashed_ship():
    """坠毁的‘归航号’重型极地探索飞船（-Z 为北方机头与登舱坡道，+Z 为南方尾部双引擎与迫降沟）"""
    m = fresh_mats()
    h = A.Hero("HeroCrashedShip")

    # ------------------------------------------------------------------ 1. 左右流线型装甲机身侧舱（包覆 X=±7.0 物理墙，内部 X∈[-6.8,+6.8] 完全畅通）
    for sx in (-1.0, 1.0):
        # 主体厚装甲侧壁（内贴 X=±6.95，外扩至 X=±10.2）
        h.add(bm_wedge(3.35, 7.1, 16.8, top_scale_x=0.68, top_scale_z=0.88),
              m["M_HullWhite"], loc=(sx * 8.55, 3.55, 0.4))
        # 机腹焦黑防热瓦护板
        h.add(A.bm_box((3.55, 1.35, 16.4), bevel=0.14, segments=2),
              m["M_Scorch"], loc=(sx * 8.65, 0.72, 0.4))
        # 机身侧舷工业橙救援涂装腰带
        h.add(A.bm_box((0.42, 0.78, 14.6), bevel=0.06, segments=2),
              m["M_PaintOrange"], loc=(sx * 10.12, 3.2, 0.2))
        # 侧舷装甲加强肋（前后 5 道）
        for rz in (-6.0, -3.1, 0.0, 3.1, 6.2):
            h.add(A.bm_box((0.55, 6.8, 0.55), bevel=0.06, segments=2),
                  m["M_CastSteel"], loc=(sx * 9.85, 3.45, rz))
        # 机身前部肩甲斜坡（包住门廊左右 X=±5.0, Z=-7.0 物理墙）
        h.add(bm_wedge(4.8, 6.8, 3.2, top_scale_x=0.78, top_scale_z=0.65, top_shift_z=0.4),
              m["M_HullWhite"], loc=(sx * 5.65, 3.4, -7.25))
        h.add(A.bm_box((3.6, 0.55, 0.55), bevel=0.05, segments=2),
              m["M_PaintOrange"], loc=(sx * 5.3, 4.4, -8.75))
        # 舱内侧壁航天肋拱装饰（玩家出生在机库内部，一眼就是真实宇宙飞船舱内！）
        for iz in (-4.0, -1.0, 2.0, 5.0):
            h.add(A.bm_box((0.42, 6.4, 0.42), bevel=0.04, segments=2),
                  m["M_CastSteel"], loc=(sx * 6.72, 3.3, iz))
        # 舱内底部工业橙安全踢脚线
        h.add(A.bm_box((0.30, 0.36, 13.0), bevel=0.04, segments=2),
              m["M_PaintOrange"], loc=(sx * 6.72, 0.25, 0.0))

    # ------------------------------------------------------------------ 2. 后部密封舱壁 + 船顶厚重龟背甲壳
    # 后部主隔舱壁（Z=+8.35，完全包住 Z=+7 物理后墙）
    h.add(bm_wedge(15.2, 7.4, 3.4, top_scale_x=0.84, top_scale_z=0.78),
          m["M_HullWhite"], loc=(0.0, 3.7, 8.35))
    # 舱内后墙装饰装甲板（Z=+6.82，留足空间给 Z=+4 的核心台）
    h.add(A.bm_box((13.2, 6.6, 0.32), bevel=0.05, segments=2),
          m["M_DarkSteel"], loc=(0.0, 3.35, 6.82))

    # 船顶主穹脊屋盖（Y=7.0..9.4, Z=-7.8..+9.2）
    h.add(bm_wedge(16.8, 2.4, 17.6, top_scale_x=0.66, top_scale_z=0.84, top_shift_z=0.6),
          m["M_HullWhite"], loc=(0.0, 8.1, 0.8))
    # 船顶中央散热装甲脊梁 + 工业橙舰体识别条
    h.add(bm_wedge(5.4, 1.35, 15.0, top_scale_x=0.72, top_scale_z=0.86),
          m["M_CastSteel"], loc=(0.0, 9.7, 1.6))
    h.add(A.bm_box((5.8, 0.35, 1.4), bevel=0.05, segments=2),
          m["M_PaintOrange"], loc=(0.0, 9.35, -2.8))
    h.add(A.bm_box((5.8, 0.35, 1.4), bevel=0.05, segments=2),
          m["M_PaintOrange"], loc=(0.0, 9.35, 4.8))
    # 顶部横置散热鳍片
    for fz in (-0.1, 1.0, 2.1, 3.2, 4.3, 5.4, 6.5):
        h.add(A.bm_box((3.8, 0.72, 0.24), bevel=0.03, segments=2),
              m["M_DarkSteel"], loc=(0.0, 10.45, fz))

    # 舱内天花板纵横桁架 + 冰青发光灯带
    for iz in (-4.6, -1.6, 1.6, 4.8):
        h.add(A.bm_box((13.4, 0.40, 0.42), bevel=0.04, segments=2),
              m["M_CastSteel"], loc=(0.0, 6.72, iz))
    for sx in (-3.2, 3.2):
        h.add(A.bm_box((0.45, 0.16, 11.5), bevel=0.02, segments=2),
              m["M_GlowCyan"], loc=(sx, 6.78, 0.0))

    # ------------------------------------------------------------------ 3. 悬挑式前部航天驾驶舱鼻锥（高悬在入口上方 Y=6.8..10.6, Z=-5.5..-16.8，玩家从飞船鼻下走出！）
    h.add(bm_wedge(10.6, 3.2, 8.8, top_scale_x=0.58, top_scale_z=0.62, top_shift_z=1.4),
          m["M_HullWhite"], loc=(0.0, 8.4, -9.6))
    # 鼻尖防热整流罩（收尖至 Z=-16.8）
    h.add(bm_wedge(6.4, 2.1, 4.8, top_scale_x=0.45, top_scale_z=0.42, top_shift_z=0.9),
          m["M_Scorch"], loc=(0.0, 7.65, -14.4))
    # 驾驶舱全景斜舷窗发光蓝玻璃 + 装甲窗框
    h.add(bm_wedge(7.6, 1.65, 3.4, top_scale_x=0.70, top_scale_z=0.62, top_shift_z=0.5),
          m["M_CockpitGlass"], loc=(0.0, 9.15, -11.4))
    for sx in (-2.0, 0.0, 2.0):
        h.add(A.bm_box((0.28, 1.72, 3.5), bevel=0.03, segments=2),
              m["M_DarkSteel"], loc=(sx, 9.18, -11.45), rot=(-16.0, 0.0, 0.0))
    # 鼻尖橙色雷达环 + 两根前伸测速空速管
    h.add(A.bm_box((4.8, 0.45, 0.45), bevel=0.05, segments=2),
          m["M_PaintOrange"], loc=(0.0, 7.35, -16.55))
    for sx in (-1.4, 1.4):
        h.add(bm_cyl(0.08, 0.03, 2.6, 10),
              m["M_CastSteel"], loc=(sx, 7.25, -17.6), rot=(90.0, 0.0, 0.0))

    # 入口门眉加压气闸顶框 + 橙色警示灯带（Z=-7.25, Y=6.35，完全不挡人！）
    h.add(A.bm_box((6.8, 0.85, 0.95), bevel=0.08, segments=2),
          m["M_CastSteel"], loc=(0.0, 6.35, -7.25))
    h.add(A.bm_box((5.6, 0.24, 0.32), bevel=0.03, segments=2),
          m["M_GlowAmber"], loc=(0.0, 6.28, -7.68))

    # 登舱坡道左右引导矮护栏与橘色着陆灯（X=±4.5，中间 9m 完全畅通！）
    for sx in (-1.0, 1.0):
        h.add(A.bm_box((0.35, 0.42, 7.8), bevel=0.05, segments=2),
              m["M_PaintOrange"], loc=(sx * 4.5, 0.12, -11.4), rot=(3.5, 0.0, 0.0))
        for lz in (-8.6, -11.4, -14.2):
            h.add(A.bm_box((0.30, 0.85, 0.28), bevel=0.03, segments=2),
                  m["M_CastSteel"], loc=(sx * 4.5, 0.35, lz))
            h.add(A.bm_box((0.24, 0.16, 0.24), bevel=0.02, segments=2),
                  m["M_GlowAmber"], loc=(sx * 4.5, 0.82, lz))

    # ------------------------------------------------------------------ 4. 重型后掠三角机翼 + 折损插雪左翼梢 + 液压起落架
    for sx in (-1.0, 1.0):
        # 内段厚翼根（X=±9.8..±16.0）
        h.add(bm_wedge(6.8, 2.35, 12.2, top_scale_x=0.82, top_scale_z=0.72, top_shift_z=1.2),
              m["M_HullWhite"], loc=(sx * 12.8, 2.35, 2.6), rot=(0.0, sx * 10.0, -sx * 6.0))
        # 机翼橙色救援识别带
        h.add(A.bm_box((4.6, 0.35, 1.6), bevel=0.04, segments=2),
              m["M_PaintOrange"], loc=(sx * 13.0, 3.52, 2.4), rot=(0.0, sx * 10.0, -sx * 6.0))
        # 外段机翼（左翼折损下沉插入雪地，右翼完好微扬，坠落故事感拉满！）
        wing_y = 1.05 if sx < 0 else 1.85
        wing_roll = 19.0 if sx < 0 else -9.0
        h.add(bm_wedge(6.2, 1.45, 8.4, top_scale_x=0.74, top_scale_z=0.62, top_shift_z=1.0),
              m["M_HullWhite"], loc=(sx * 18.0, wing_y, 5.6), rot=(0.0, sx * 15.0, wing_roll))
        # 翼尖小翼 + 航行红/青灯
        h.add(bm_wedge(0.75, 3.6, 5.2, top_scale_x=0.55, top_scale_z=0.55, top_shift_z=0.9),
              m["M_PaintOrange"], loc=(sx * 20.6, wing_y + 1.45, 7.2), rot=(0.0, sx * 10.0, wing_roll * 0.6))
        h.add(A.bm_box((0.55, 0.45, 0.65), bevel=0.05, segments=2),
              m["M_GlowRed"] if sx < 0 else m["M_GlowCyan"],
              loc=(sx * 20.9, wing_y + 2.75, 6.2))
        # 重型液压起落架支柱 + 雪地防滑大脚垫
        for lz in (-3.2, 5.2):
            h.add(bm_cyl(0.42, 0.55, 2.6, 12),
                  m["M_CastSteel"], loc=(sx * 11.4, 1.0, lz), rot=(0.0, 0.0, sx * 12.0))
            h.add(A.bm_box((1.9, 0.52, 2.8), bevel=0.08, segments=2),
                  m["M_DarkSteel"], loc=(sx * 11.9, -0.22, lz))

    # ------------------------------------------------------------------ 5. 尾部双巨型主推进离子引擎 + 双外倾垂尾（Z=+9.5..+17.8）
    for sx in (-1.0, 1.0):
        # 引擎短舱整流罩
        h.add(bm_cyl(2.65, 2.25, 6.2, 20),
              m["M_CastSteel"], loc=(sx * 4.4, 3.65, 11.4), rot=(90.0, 0.0, 0.0))
        # 引擎外圈橙色耐高温环
        h.add(bm_cyl(2.78, 2.78, 0.85, 20),
              m["M_PaintOrange"], loc=(sx * 4.4, 3.65, 10.2), rot=(90.0, 0.0, 0.0))
        # 巨型尾喷口钟罩（灼烧暗钢）
        h.add(bm_cyl(1.75, 2.35, 3.4, 22),
              m["M_Scorch"], loc=(sx * 4.4, 3.55, 15.6), rot=(90.0, 0.0, 0.0))
        # 喷口深处余烬发光核心（左引擎受损发红橙余温，右引擎微弱蓝光）
        h.add(bm_cyl(1.20, 1.45, 0.65, 18),
              m["M_GlowAmber"] if sx < 0 else m["M_GlowCyan"],
              loc=(sx * 4.4, 3.55, 16.6), rot=(90.0, 0.0, 0.0))
        # 高耸外倾双垂直尾翼（200m 外就能一眼认出这是一艘迫降的宇宙飞船！）
        h.add(bm_wedge(0.95, 7.4, 7.6, top_scale_x=0.45, top_scale_z=0.48, top_shift_z=1.6),
              m["M_HullWhite"], loc=(sx * 5.8, 8.8, 11.2), rot=(0.0, 0.0, -sx * 14.0))
        h.add(A.bm_box((1.02, 1.05, 3.8), bevel=0.05, segments=2),
              m["M_PaintOrange"], loc=(sx * 6.35, 10.6, 12.0), rot=(0.0, 0.0, -sx * 14.0))
        # 尾翼顶端红色防撞警示信标
        h.add(A.bm_box((0.55, 0.55, 0.72), bevel=0.05, segments=2),
              m["M_GlowRed"], loc=(sx * 6.65, 12.35, 13.0))

    # 尾部中央辅助反应堆整流罩
    h.add(bm_wedge(4.2, 3.8, 5.2, top_scale_x=0.68, top_scale_z=0.62, top_shift_z=0.8),
          m["M_Scorch"], loc=(0.0, 2.2, 12.2))

    # 船顶通讯雷达锅 + 紧急信标
    h.add(bm_cyl(0.24, 0.16, 2.4, 12), m["M_CastSteel"], loc=(-1.8, 11.4, 5.8))
    h.add(bm_cyl(1.15, 0.22, 0.45, 18), m["M_HullWhite"], loc=(-1.8, 12.6, 5.8), rot=(-25.0, 12.0, 0.0))
    h.add(A.bm_box((0.45, 0.45, 0.45), bevel=0.05, segments=2), m["M_GlowAmber"], loc=(1.8, 10.85, 5.6))

    finalize_and_export(h, "hero_crashed_ship.glb", seed=71, ao_rays=6, ground_z=-0.5)


def build_return_hatch():
    """舱内‘返回飞船主舱’加压气闸舱门（宽 3.15m × 高 3.65m，正面朝 +Z，挂载后旋转面向机库中央）"""
    m = fresh_mats()
    h = A.Hero("HeroShipReturnHatch")

    # 重型斜倒角加压门框
    h.add(A.bm_box((3.15, 3.65, 0.56), bevel=0.09, segments=2), m["M_CastSteel"], loc=(0.0, 1.82, 0.0))
    # 内嵌厚装甲舱门扇
    h.add(A.bm_box((2.35, 3.05, 0.68), bevel=0.08, segments=2), m["M_HullWhite"], loc=(0.0, 1.68, 0.04))
    # 门扇中缝与橙色警示下缘
    h.add(A.bm_box((0.10, 2.90, 0.72), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(0.0, 1.68, 0.06))
    h.add(A.bm_box((2.20, 0.36, 0.72), bevel=0.04, segments=2), m["M_PaintOrange"], loc=(0.0, 0.36, 0.06))
    # 门周发光冰青气密就绪指示框
    for sx in (-1.26, 1.26):
        h.add(A.bm_box((0.11, 3.08, 0.14), bevel=0.02, segments=2), m["M_GlowCyan"], loc=(sx, 1.72, 0.34))
    h.add(A.bm_box((2.62, 0.12, 0.14), bevel=0.02, segments=2), m["M_GlowCyan"], loc=(0.0, 3.24, 0.34))
    # 中央机械气密锁手轮
    h.add(bm_cyl(0.42, 0.42, 0.16, 18), m["M_DarkSteel"], loc=(0.0, 1.52, 0.42), rot=(90.0, 0.0, 0.0))
    h.add(bm_cyl(0.28, 0.28, 0.20, 18), m["M_PaintOrange"], loc=(0.0, 1.52, 0.46), rot=(90.0, 0.0, 0.0))
    for a in (0.0, 90.0):
        h.add(A.bm_box((0.76, 0.10, 0.10), bevel=0.02, segments=2), m["M_CastSteel"], loc=(0.0, 1.52, 0.49), rot=(0.0, 0.0, a))
    # 门上方观察窗（透出飞船主舱的温暖灯光）
    h.add(A.bm_box((1.35, 0.52, 0.14), bevel=0.04, segments=2), m["M_GlowAmber"], loc=(0.0, 2.52, 0.36))
    # 右侧发光交互操控面板
    h.add(A.bm_box((0.36, 0.62, 0.24), bevel=0.04, segments=2), m["M_DarkSteel"], loc=(1.78, 1.48, 0.22))
    h.add(A.bm_box((0.24, 0.34, 0.08), bevel=0.02, segments=2), m["M_GlowCyan"], loc=(1.78, 1.56, 0.34))
    # 门槛防滑金属踏板
    h.add(A.bm_box((3.2, 0.14, 0.95), bevel=0.03, segments=2), m["M_DarkSteel"], loc=(0.0, 0.07, 0.38))

    finalize_and_export(h, "hero_ship_return_hatch.glb", seed=72, ao_rays=8, ground_z=0.0)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    build_crashed_ship()
    build_return_hatch()
    print("BUILD_CRASHED_SHIP_OK")


if __name__ == "__main__":
    main()
