"""《迷失太空》生活化多层货架/壁柜 + 物理机关解谜硬件资产包（Blender 4.5 / Y-up Godot 坐标系）
第 1 轮 & 第 2 轮共用资产（一次导出，全图实装）：
1. hero_open_supply_shelf.glb   —— 开放式三层极地工业物资货架（层板顶面精确 Y=0.56 / 1.24 / 1.92m，带边角折叠毛毯、小储物盒与层底暖灯带）
2. hero_wall_counter_shelf.glb  —— 生活/医疗/实验壁挂双层柜台架（下柜台面 Y=0.96m + 洞洞板背墙 + 上层悬空开放置物架 Y=1.64m）
3. hero_puzzle_fuse_box.glb     —— 物理电池插槽配电箱（带凹槽电池仓、铜排与顶部状态指示灯座）
4. hero_puzzle_target_plate.glb —— 动能撞击靶盘（八角装甲外框 + 醒目同心圆靶心，碰碰球撞击后翻绿解锁！）
5. hero_puzzle_acoustic_vault.glb —— 声波共振结晶锁罩（六棱共振水晶罩 + 底部声学共振底座，复古音响共振震碎！）
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
    mats["M_GlowCyan"] = K.mat("M_GlowCyan", (0.20, 0.88, 0.98), 0.14, 0.0, emit=(0.18, 0.86, 0.98), emit_strength=2.2)
    mats["M_GlowAmber"] = K.mat("M_GlowAmber", (0.98, 0.62, 0.18), 0.16, 0.0, emit=(0.98, 0.58, 0.16), emit_strength=2.2)
    mats["M_GlowGreen"] = K.mat("M_GlowGreen", (0.20, 0.92, 0.54), 0.16, 0.0, emit=(0.20, 0.92, 0.54), emit_strength=2.2)
    mats["M_GlowRed"] = K.mat("M_GlowRed", (0.98, 0.24, 0.16), 0.16, 0.0, emit=(1.0, 0.24, 0.14), emit_strength=2.4)
    mats["M_FabricWarm"] = K.mat("M_FabricWarm", (0.58, 0.44, 0.34), 0.78, 0.0)
    mats["M_FabricBlue"] = K.mat("M_FabricBlue", (0.26, 0.46, 0.56), 0.76, 0.0)
    mats["M_Copper"] = K.mat("M_Copper", (0.76, 0.42, 0.22), 0.28, 0.85)
    return mats


def export_model(hero, filename, seed=201, ao_rays=6):
    gain = dict(HM.WEAR_GAIN)
    gain["M_FabricWarm"] = 0.35
    gain["M_FabricBlue"] = 0.35
    gain["M_Copper"] = 0.25
    obj = hero.finish(
        smooth=True,
        split_angle=34.0,
        bake={"ao_rays": ao_rays, "ao_dist": 0.18, "seed": seed, "mat_gain": gain, "ground_z": 0.0, "verbose": False},
    )
    tri = obj.modifiers.new("Tri", "TRIANGULATE")
    tri.quad_method = "BEAUTY"
    K.apply_modifiers(obj)
    out_path = os.path.join(OUT_DIR, filename)
    A.export_glb(out_path, obj.name)
    A.report(filename, obj)


def bm_cyl(r1, r2, h, segs=16):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi * 0.5, 3, 'X'))
    return bm


def build_open_supply_shelf():
    """1. 开放式三层工业极地物资货架（宽 3.40m × 高 2.35m × 深 0.90m）
    实心层板顶面精确对齐：下层 Y=0.56m、中层 Y=1.24m、上层 Y=1.92m
    两侧有斜拉钢撑、层底柔光灯条、边角带自然生活杂物，中间留出宽敞开放格放可拾取物品！
    """
    m = fresh_mats()
    h = A.Hero("HeroOpenSupplyShelf")

    # 四根重型角钢立柱 + 橡胶底座
    for sx in (-1.64, 1.64):
        for sz in (-0.41, 0.41):
            h.add(A.bm_box((0.09, 2.32, 0.09), bevel=0.015, segments=2), m["M_DarkSteel"], loc=(sx, 1.16, sz))
            h.add(A.bm_box((0.14, 0.06, 0.14), bevel=0.01, segments=2), m["M_Rubber"], loc=(sx, 0.03, sz))
        # 两侧工业斜拉筋 + 防掉落侧护栏
        for ty in (0.66, 1.34, 2.02):
            h.add(A.bm_box((0.04, 0.05, 0.78), bevel=0.01, segments=2), m["M_PaintOrange"], loc=(sx, ty, 0.0))
        h.add(A.bm_box((0.04, 0.05, 1.55), bevel=0.01, segments=2), m["M_CastSteel"], loc=(sx, 1.16, 0.0), rot=(42.0, 0.0, 0.0))

    # 背部工业透气网格横梁（开放通透感，方便前后透视）
    for by in (0.28, 0.90, 1.58, 2.26):
        h.add(A.bm_box((3.28, 0.07, 0.05), bevel=0.01, segments=2), m["M_CastSteel"], loc=(0.0, by, -0.42))
    # 顶部橙色安全横眉 + 标牌槽
    h.add(A.bm_box((3.38, 0.12, 0.10), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(0.0, 2.28, 0.41))
    h.add(A.bm_box((0.92, 0.07, 0.03), bevel=0.01, segments=2), m["M_GlowCyan"], loc=(0.0, 2.28, 0.47))

    # 三层实心层板（顶面精确位于 Y=0.56, 1.24, 1.92）+ 前缘金属包边 + 层底照明灯条
    for top_y in (0.56, 1.24, 1.92):
        h.add(A.bm_box((3.26, 0.06, 0.84), bevel=0.012, segments=2), m["M_CastSteel"], loc=(0.0, top_y - 0.03, 0.0))
        h.add(A.bm_box((3.28, 0.08, 0.04), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(0.0, top_y - 0.03, 0.41))
        # 层底微发光照明条，让每一层架子上的物资都层次分明！
        if top_y > 0.6:
            h.add(A.bm_box((2.60, 0.025, 0.06), bevel=0.005, segments=2), m["M_GlowAmber"], loc=(0.0, top_y - 0.072, 0.18))

    # 极克制的角落生活感点缀（完全避开 x=-1.15..+1.15 的主要陈列区！）
    # 1) 最下层地脚放两个斜靠的扁储物箱（地面 Y=0..0.42）
    h.add(A.bm_box((0.76, 0.36, 0.56), bevel=0.03, segments=2), m["M_PaintCream"], loc=(-1.05, 0.18, 0.02), rot=(0.0, 6.0, 0.0))
    h.add(A.bm_box((0.28, 0.06, 0.04), bevel=0.01, segments=2), m["M_PaintOrange"], loc=(-1.05, 0.24, 0.31), rot=(0.0, 6.0, 0.0))
    h.add(A.bm_box((0.68, 0.34, 0.52), bevel=0.03, segments=2), m["M_DarkSteel"], loc=(1.08, 0.17, -0.02), rot=(0.0, -9.0, 0.0))
    # 2) 顶层角落放叠好的保暖毯与小零件盒（留出中/左/右宽大空位）
    h.add(A.bm_box((0.46, 0.10, 0.42), bevel=0.03, segments=2), m["M_FabricBlue"], loc=(-1.34, 1.97, -0.06), rot=(0.0, 12.0, 0.0))
    h.add(A.bm_box((0.42, 0.09, 0.38), bevel=0.03, segments=2), m["M_FabricWarm"], loc=(-1.32, 2.06, -0.04), rot=(0.0, -8.0, 0.0))
    h.add(A.bm_box((0.40, 0.22, 0.34), bevel=0.02, segments=2), m["M_PaintCream"], loc=(1.36, 2.03, -0.08), rot=(0.0, -14.0, 0.0))

    export_model(h, "hero_open_supply_shelf.glb", seed=201)


def build_wall_counter_shelf():
    """2. 生活/医疗/实验壁挂双层柜台架（宽 3.20m × 高 2.25m × 深 0.88m）
    下柜台面精确 Y=0.96m，上层悬空置物架精确 Y=1.64m，中间是深钢工具洞洞板背墙与暖光操作灯带！
    """
    m = fresh_mats()
    h = A.Hero("HeroWallCounterShelf")

    # 下层储物地柜（高 0.90m + 0.06m 奶油白操作台面 => 顶面精确 Y=0.96m）
    h.add(A.bm_box((3.12, 0.86, 0.80), bevel=0.03, segments=2), m["M_CastSteel"], loc=(0.0, 0.45, 0.0))
    h.add(A.bm_box((3.20, 0.06, 0.88), bevel=0.015, segments=2), m["M_PaintCream"], loc=(0.0, 0.93, 0.0))
    # 三扇柜门 + 工业橙拉手（中间微开一格抽屉，更有烟火气！）
    for i in range(3):
        dx = -1.02 + i * 1.02
        h.add(A.bm_box((0.92, 0.68, 0.05), bevel=0.015, segments=2), m["M_PaintCream"], loc=(dx, 0.44, 0.41))
        h.add(A.bm_box((0.26, 0.04, 0.05), bevel=0.01, segments=2), m["M_PaintOrange"], loc=(dx, 0.64, 0.45))

    # 背部护板墙 + 洞洞挂板框 + 两侧立柱
    h.add(A.bm_box((3.16, 1.24, 0.06), bevel=0.015, segments=2), m["M_DarkSteel"], loc=(0.0, 1.58, -0.40))
    for sx in (-1.54, 1.54):
        h.add(A.bm_box((0.08, 1.30, 0.10), bevel=0.015, segments=2), m["M_CastSteel"], loc=(sx, 1.61, -0.37))

    # 上层悬空开放置物架（顶面精确位于 Y=1.64m）+ 两侧斜三角托架 + 架底操作照明灯条
    h.add(A.bm_box((3.10, 0.05, 0.56), bevel=0.012, segments=2), m["M_CastSteel"], loc=(0.0, 1.615, -0.10))
    h.add(A.bm_box((3.12, 0.05, 0.03), bevel=0.008, segments=2), m["M_PaintOrange"], loc=(0.0, 1.655, 0.17))
    h.add(A.bm_box((2.50, 0.025, 0.06), bevel=0.005, segments=2), m["M_GlowAmber"], loc=(0.0, 1.575, -0.05))
    for sx in (-1.30, 0.0, 1.30):
        h.add(A.bm_box((0.05, 0.24, 0.46), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(sx, 1.48, -0.15))

    # 顶檐收口梁 + 小状态灯
    h.add(A.bm_box((3.20, 0.10, 0.24), bevel=0.02, segments=2), m["M_CastSteel"], loc=(0.0, 2.20, -0.30))
    h.add(A.bm_box((0.60, 0.04, 0.04), bevel=0.01, segments=2), m["M_GlowCyan"], loc=(0.0, 2.20, -0.17))

    # 边角小收纳罐（避开中段陈列区）
    h.add(bm_cyl(0.08, 0.08, 0.22, 12), m["M_PaintCream"], loc=(-1.36, 1.75, -0.16))
    h.add(bm_cyl(0.07, 0.07, 0.18, 12), m["M_PaintOrange"], loc=(-1.22, 1.73, -0.22))

    export_model(h, "hero_wall_counter_shelf.glb", seed=202)


def build_puzzle_fuse_box():
    """3. 物理电池插槽配电箱（可插入备用电池 `cell` 通电解锁！）"""
    m = fresh_mats()
    h = A.Hero("HeroPuzzleFuseBox")
    # 稳固底座与主体机箱
    h.add(A.bm_box((0.96, 0.22, 0.72), bevel=0.03, segments=2), m["M_DarkSteel"], loc=(0.0, 0.11, 0.0))
    h.add(A.bm_box((0.84, 1.38, 0.56), bevel=0.04, segments=2), m["M_CastSteel"], loc=(0.0, 0.90, -0.04))
    # 正面凹入的电池卡槽围框 + 铜导电触片
    for sx in (-0.28, 0.28):
        h.add(A.bm_box((0.12, 0.62, 0.22), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(sx, 1.02, 0.24))
    h.add(A.bm_box((0.68, 0.10, 0.24), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(0.0, 0.72, 0.24))
    h.add(A.bm_box((0.68, 0.10, 0.24), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(0.0, 1.34, 0.24))
    for cx in (-0.12, 0.12):
        h.add(A.bm_box((0.06, 0.36, 0.06), bevel=0.01, segments=2), m["M_Copper"], loc=(cx, 1.02, 0.24))
    # 顶部配电导气管 + 警示灯基座
    h.add(bm_cyl(0.14, 0.16, 0.18, 14), m["M_DarkSteel"], loc=(0.0, 1.66, 0.0))
    export_model(h, "hero_puzzle_fuse_box.glb", seed=203)


def build_puzzle_target_plate():
    """4. 动能撞击靶盘（直径 1.4m，八角装甲框 + 中心撞击核心，碰碰球击中解锁！）"""
    m = fresh_mats()
    h = A.Hero("HeroPuzzleTargetPlate")
    h.add(bm_cyl(0.72, 0.76, 0.18, 8), m["M_DarkSteel"], loc=(0.0, 0.0, 0.0), rot=(90.0, 0.0, 0.0))
    h.add(bm_cyl(0.56, 0.56, 0.22, 16), m["M_PaintOrange"], loc=(0.0, 0.0, 0.02), rot=(90.0, 0.0, 0.0))
    h.add(bm_cyl(0.36, 0.36, 0.26, 16), m["M_PaintCream"], loc=(0.0, 0.0, 0.04), rot=(90.0, 0.0, 0.0))
    # 四角装甲夹具
    for a in (45, 135, 225, 315):
        rad = math.radians(a)
        h.add(A.bm_box((0.20, 0.20, 0.24), bevel=0.02, segments=2), m["M_CastSteel"],
              loc=(math.cos(rad) * 0.64, math.sin(rad) * 0.64, 0.02), rot=(0.0, 0.0, a))
    export_model(h, "hero_puzzle_target_plate.glb", seed=204)


def build_puzzle_acoustic_vault():
    """5. 声波共振结晶锁底座（六角声学基座 + 音叉谐振柱，配发光共振结晶罩）"""
    m = fresh_mats()
    h = A.Hero("HeroPuzzleAcousticVault")
    h.add(bm_cyl(0.95, 1.10, 0.34, 6), m["M_DarkSteel"], loc=(0.0, 0.17, 0.0))
    h.add(bm_cyl(0.78, 0.84, 0.16, 6), m["M_CastSteel"], loc=(0.0, 0.42, 0.0))
    # 三根环绕音叉式声波接收柱
    for a in (0, 120, 240):
        rad = math.radians(a)
        px, pz = math.cos(rad) * 0.82, math.sin(rad) * 0.82
        h.add(A.bm_box((0.12, 1.35, 0.14), bevel=0.02, segments=2), m["M_PaintCream"],
              loc=(px, 0.96, pz), rot=(0.0, -a, 0.0))
        h.add(A.bm_box((0.06, 0.92, 0.06), bevel=0.01, segments=2), m["M_GlowCyan"],
              loc=(px * 0.86, 1.02, pz * 0.86), rot=(0.0, -a, 0.0))
    export_model(h, "hero_puzzle_acoustic_vault.glb", seed=205)


if __name__ == "__main__":
    build_open_supply_shelf()
    build_wall_counter_shelf()
    build_puzzle_fuse_box()
    build_puzzle_target_plate()
    build_puzzle_acoustic_vault()
    print("ALL_SHELF_AND_PUZZLE_GLBS_OK")
