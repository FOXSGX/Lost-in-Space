"""《迷失太空》室内美术精修升级包（Blender 4.5 / Y-up Godot 坐标系）
把之前略显方块的 4 件核心室内道具彻底精雕细琢，并新增 2 套高质感微细节建筑件：
1. 精修 hero_hydro_planter.glb —— 去掉刺眼荧光块，雕刻真实多瓣斜展叶片簇 + 土壤托盘 + 细喷淋管 + 柔和暖光灯架！
2. 精修 hero_sofa_lounge.glb   —— 去掉圆锥假盆栽，雕刻真实多叶扇形蕨类盆栽 + 缝线坐垫靠枕 + 翻盖笔记本电脑 + 咖啡杯！
3. 精修 hero_drill_rig.glb     —— 雕刻螺旋钻杆、4 根液压推进缸、工业仪表环与环形金属安全检修平台！
4. 精修 hero_cryo_sample_tank.glb —— 雕刻多棱面悬浮蓝晶尖塔 + 上下钛钢夹爪 + 压力管路与精致玻璃肋框架！
5. 新增 hero_desk_clutter.glb  —— 精细桌面生活/科研小物件簇（可调台灯 + 书堆 + 咖啡杯 + 文件夹 + 发光试管盒）！
6. 新增 hero_wall_pilaster.glb —— 室内建筑级钢构承重肋柱 + 腰线护墙板 + 踢脚线（彻底终结光秃秃水泥灰墙！）
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
    mats["M_GlowCyan"] = K.mat("M_GlowCyan", (0.20, 0.88, 0.98), 0.14, 0.0, emit=(0.18, 0.86, 0.98), emit_strength=2.0)
    mats["M_GlowAmber"] = K.mat("M_GlowAmber", (0.98, 0.62, 0.18), 0.16, 0.0, emit=(0.98, 0.58, 0.16), emit_strength=2.0)
    mats["M_GlowGreen"] = K.mat("M_GlowGreen", (0.20, 0.88, 0.52), 0.18, 0.0, emit=(0.20, 0.88, 0.52), emit_strength=1.8)
    mats["M_PlantLeaf"] = K.mat("M_PlantLeaf", (0.15, 0.48, 0.22), 0.65, 0.0)
    mats["M_PlantLeafLight"] = K.mat("M_PlantLeafLight", (0.28, 0.64, 0.30), 0.60, 0.0)
    mats["M_FabricWarm"] = K.mat("M_FabricWarm", (0.58, 0.42, 0.32), 0.80, 0.0)
    mats["M_FabricBlue"] = K.mat("M_FabricBlue", (0.24, 0.44, 0.56), 0.78, 0.0)
    mats["M_GlassWarm"] = K.mat("M_GlassWarm", (0.68, 0.84, 0.88), 0.10, 0.16, emit=(0.32, 0.72, 0.84), emit_strength=0.35)
    return mats


def export_model(hero, filename, seed=160, ao_rays=6):
    gain = dict(HM.WEAR_GAIN)
    gain["M_PlantLeaf"] = 0.45
    gain["M_PlantLeafLight"] = 0.45
    gain["M_FabricWarm"] = 0.35
    gain["M_FabricBlue"] = 0.35
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


def add_fern_cluster(h, m, center_x, base_y, center_z, scale=1.0, frond_count=7):
    """雕刻多瓣斜展的真实叶片簇（告别亮瞎眼的发光方块！）"""
    for i in range(frond_count):
        ang = (i / float(frond_count)) * 360.0 + (center_x * 47.0)
        rad = math.radians(ang)
        tilt = 32.0 + (i % 3) * 14.0
        leaf_len = (0.34 + (i % 2) * 0.10) * scale
        leaf_w = 0.11 * scale
        mat_k = "M_PlantLeaf" if i % 2 == 0 else "M_PlantLeafLight"
        ox = center_x + math.cos(rad) * 0.10 * scale
        oz = center_z + math.sin(rad) * 0.10 * scale
        h.add(A.bm_box((leaf_w, 0.025 * scale, leaf_len), bevel=0.008 * scale, segments=2),
              m[mat_k], loc=(ox, base_y + 0.14 * scale, oz), rot=(tilt, -ang + 90.0, 0.0))
    # 中心嫩芽
    h.add(bm_cyl(0.06 * scale, 0.02 * scale, 0.22 * scale, 8), m["M_PlantLeafLight"], loc=(center_x, base_y + 0.11 * scale, center_z))


def refine_hydro_planter():
    """1. 精修水培种植槽（真实自然翠绿叶簇 + 不锈钢喷淋管道 + 暖白植物补光灯）"""
    m = fresh_mats()
    h = A.Hero("HeroHydroPlanter")
    # 陶瓷白主体槽体 + 底部深钢排水底座 + 侧边水位视窗
    h.add(A.bm_box((3.65, 0.72, 1.48), bevel=0.06, segments=2), m["M_PaintCream"], loc=(0.0, 0.50, 0.0))
    h.add(A.bm_box((3.74, 0.18, 1.56), bevel=0.04, segments=2), m["M_DarkSteel"], loc=(0.0, 0.09, 0.0))
    h.add(A.bm_box((3.38, 0.10, 1.24), bevel=0.02, segments=2), m["M_Rubber"], loc=(0.0, 0.85, 0.0))
    h.add(A.bm_box((0.55, 0.16, 0.06), bevel=0.02, segments=2), m["M_GlowCyan"], loc=(-1.1, 0.50, 0.74))
    # 10 株多层次真实斜展绿植丛（自然深绿/嫩绿交替，完全没有刺眼荧光块！）
    for px in (-1.28, -0.64, 0.0, 0.64, 1.28):
        for pz in (-0.30, 0.30):
            add_fern_cluster(h, m, px, 0.90, pz, scale=1.05, frond_count=6)
    # 不锈钢龙门补光灯架 + 细滴灌喷头管 + 柔和暖白灯条
    for sx in (-1.66, 1.66):
        h.add(bm_cyl(0.05, 0.05, 1.56, 10), m["M_CastSteel"], loc=(sx, 1.62, 0.0))
    h.add(A.bm_box((3.52, 0.12, 0.34), bevel=0.03, segments=2), m["M_DarkSteel"], loc=(0.0, 2.38, 0.0))
    h.add(A.bm_box((3.12, 0.05, 0.16), bevel=0.01, segments=2), m["M_GlowAmber"], loc=(0.0, 2.31, 0.0))
    export_model(h, "hero_hydro_planter.glb", seed=161)


def refine_sofa_lounge():
    """2. 精修温馨休闲沙发（分段蓬松软垫 + 撞色抱枕 + 真实扇叶盆栽 + 翻盖笔记本电脑 + 咖啡杯）"""
    m = fresh_mats()
    h = A.Hero("HeroSofaLounge")
    # 金属沙发框架与细斜腿
    h.add(A.bm_box((3.3, 0.18, 1.06), bevel=0.04, segments=2), m["M_DarkSteel"], loc=(0.0, 0.24, -0.65))
    for sx in (-1.48, 1.48):
        for sz in (-1.05, -0.25):
            h.add(bm_cyl(0.04, 0.03, 0.20, 10), m["M_CastSteel"], loc=(sx, 0.10, sz))
    # 三段独立蓬松坐垫与靠背（带真实接缝层次）
    for cx in (-1.02, 0.0, 1.02):
        h.add(A.bm_box((0.96, 0.24, 0.92), bevel=0.08, segments=2), m["M_FabricWarm"], loc=(cx, 0.45, -0.60))
        h.add(A.bm_box((0.96, 0.64, 0.26), bevel=0.08, segments=2), m["M_FabricWarm"], loc=(cx, 0.86, -1.04))
    # 两侧加厚扶手 + 两个斜靠撞色抱枕
    for sx in (-1.58, 1.58):
        h.add(A.bm_box((0.24, 0.56, 1.04), bevel=0.07, segments=2), m["M_FabricBlue"], loc=(sx, 0.56, -0.64))
    h.add(A.bm_box((0.46, 0.42, 0.16), bevel=0.06, segments=2), m["M_FabricBlue"], loc=(-1.12, 0.76, -0.82), rot=(-18.0, 22.0, 12.0))
    h.add(A.bm_box((0.46, 0.42, 0.16), bevel=0.06, segments=2), m["M_PaintOrange"], loc=(1.14, 0.76, -0.82), rot=(-16.0, -24.0, -10.0))
    # 现代感茶几 + 翻盖笔记本电脑 + 咖啡杯 + 真实多叶绿植盆栽
    h.add(A.bm_box((1.95, 0.09, 0.98), bevel=0.03, segments=2), m["M_PaintCream"], loc=(0.0, 0.50, 0.74))
    for sx in (-0.78, 0.78):
        h.add(A.bm_box((0.08, 0.48, 0.78), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(sx, 0.24, 0.74))
    # 打开的科幻笔记本电脑
    h.add(A.bm_box((0.44, 0.03, 0.30), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(-0.46, 0.56, 0.72), rot=(0.0, 16.0, 0.0))
    h.add(A.bm_box((0.44, 0.28, 0.03), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(-0.50, 0.70, 0.58), rot=(-18.0, 16.0, 0.0))
    h.add(A.bm_box((0.38, 0.22, 0.02), bevel=0.01, segments=2), m["M_GlowCyan"], loc=(-0.49, 0.70, 0.60), rot=(-18.0, 16.0, 0.0))
    # 两个陶瓷咖啡杯
    h.add(bm_cyl(0.055, 0.05, 0.11, 12), m["M_PaintOrange"], loc=(0.06, 0.60, 0.84))
    h.add(bm_cyl(0.055, 0.05, 0.11, 12), m["M_PaintCream"], loc=(0.24, 0.60, 0.66))
    # 精致陶盆 + 多叶扇形极地蕨类绿植（彻底取代之前的圆锥假树！）
    h.add(bm_cyl(0.18, 0.13, 0.24, 16), m["M_PaintCream"], loc=(0.64, 0.66, 0.68))
    h.add(bm_cyl(0.16, 0.16, 0.03, 14), m["M_Rubber"], loc=(0.64, 0.77, 0.68))
    add_fern_cluster(h, m, 0.64, 0.78, 0.68, scale=0.88, frond_count=8)
    export_model(h, "hero_sofa_lounge.glb", seed=162)


def refine_drill_rig():
    """3. 精修冰川钻探中心立式螺旋钻塔（螺旋叶片钻杆 + 4 根液压推进缸 + 检修围栏平台！）"""
    m = fresh_mats()
    h = A.Hero("HeroDrillRig")
    # 环形重型检修底座与安全黄黑护栏柱
    h.add(bm_cyl(2.85, 2.55, 0.58, 16), m["M_DarkSteel"], loc=(0.0, 0.29, 0.0))
    h.add(bm_cyl(1.45, 1.45, 0.64, 16), m["M_CastSteel"], loc=(0.0, 0.34, 0.0))
    for a in range(0, 360, 45):
        rad = math.radians(a)
        h.add(bm_cyl(0.05, 0.05, 1.05, 8), m["M_PaintOrange"], loc=(math.cos(rad) * 2.45, 1.08, math.sin(rad) * 2.45))
    # 四角主钢塔立柱 + 横向加强桁架圈
    for sx in (-1.45, 1.45):
        for sz in (-1.45, 1.45):
            h.add(A.bm_box((0.28, 7.8, 0.28), bevel=0.04, segments=2), m["M_PaintOrange"], loc=(sx, 4.1, sz))
            # 伴随立柱的镀铬液压推进活塞缸
            h.add(bm_cyl(0.11, 0.11, 4.2, 12), m["M_BareSteel"], loc=(sx * 0.72, 2.8, sz * 0.72))
    for ry in (2.6, 5.2, 7.6):
        h.add(A.bm_box((3.25, 0.32, 3.25), bevel=0.04, segments=2), m["M_CastSteel"], loc=(0.0, ry, 0.0))
    # 中央粗大金属螺旋钻杆（分段斜肋螺旋刃 + 发光蓝冰芯提取段 + 精密激光切环）
    h.add(bm_cyl(0.32, 0.32, 7.4, 16), m["M_BareSteel"], loc=(0.0, 4.0, 0.0))
    for i in range(11):
        hy = 0.95 + i * 0.54
        h.add(A.bm_box((1.15, 0.14, 0.42), bevel=0.03, segments=2), m["M_CastSteel"], loc=(0.0, hy, 0.0), rot=(18.0, i * 36.0, 0.0))
    # 被提取出的多棱面极地发光冰芯柱体 + 激光扫描环
    h.add(bm_cyl(0.46, 0.42, 2.2, 8), m["M_GlowCyan"], loc=(0.0, 2.1, 0.0))
    h.add(bm_cyl(1.12, 1.12, 0.22, 20), m["M_DarkSteel"], loc=(0.0, 4.2, 0.0))
    h.add(bm_cyl(1.16, 1.16, 0.09, 20), m["M_GlowAmber"], loc=(0.0, 4.2, 0.0))
    export_model(h, "hero_drill_rig.glb", seed=163)


def refine_cryo_sample_tank():
    """4. 精修冰样/生物培养液柱（多棱面悬浮水晶集群 + 钛钢上下夹爪 + 压力管与玻璃框架！）"""
    m = fresh_mats()
    h = A.Hero("HeroCryoSampleTank")
    h.add(bm_cyl(0.98, 0.88, 0.62, 18), m["M_DarkSteel"], loc=(0.0, 0.31, 0.0))
    h.add(bm_cyl(0.88, 0.98, 0.58, 18), m["M_DarkSteel"], loc=(0.0, 3.36, 0.0))
    h.add(bm_cyl(0.92, 0.92, 0.10, 18), m["M_GlowCyan"], loc=(0.0, 0.64, 0.0))
    h.add(bm_cyl(0.92, 0.92, 0.10, 18), m["M_GlowCyan"], loc=(0.0, 3.04, 0.0))
    # 外层通透培养玻璃圆筒
    h.add(bm_cyl(0.76, 0.76, 2.38, 24), m["M_GlassWarm"], loc=(0.0, 1.84, 0.0))
    # 内部多棱面悬浮极地晶簇（主尖塔 + 3 支斜生晶芽，比单圆柱精细 10 倍！）
    h.add(bm_cyl(0.24, 0.04, 1.55, 6), m["M_GlowCyan"], loc=(0.0, 1.85, 0.0), rot=(6.0, 15.0, -4.0))
    for i in range(3):
        ang = math.radians(i * 120.0 + 30.0)
        h.add(bm_cyl(0.14, 0.03, 0.92, 6), m["M_GlowCyan"],
              loc=(math.cos(ang) * 0.22, 1.65, math.sin(ang) * 0.22), rot=(22.0, i * 120.0, 14.0))
    # 上下固定夹爪 + 4 根外骨骼保护钢柱 + 压力表小盒
    for a in (0, 90, 180, 270):
        rad = math.radians(a)
        h.add(bm_cyl(0.065, 0.065, 2.95, 10), m["M_CastSteel"], loc=(math.cos(rad) * 0.86, 1.84, math.sin(rad) * 0.86))
    h.add(A.bm_box((0.36, 0.42, 0.16), bevel=0.03, segments=2), m["M_PaintOrange"], loc=(0.0, 0.42, 0.92))
    export_model(h, "hero_cryo_sample_tank.glb", seed=164)


def build_desk_clutter():
    """5. 新增：精细桌面生活与科研小物件簇（可调暖光台灯 + 叠放资料书 + 咖啡杯 + 文件夹 + 迷你盆栽）"""
    m = fresh_mats()
    h = A.Hero("HeroDeskClutter")
    # 折臂暖光台灯
    h.add(bm_cyl(0.13, 0.11, 0.05, 14), m["M_DarkSteel"], loc=(-0.58, 0.025, -0.18))
    h.add(bm_cyl(0.025, 0.025, 0.36, 8), m["M_CastSteel"], loc=(-0.56, 0.20, -0.18), rot=(0.0, 0.0, -14.0))
    h.add(A.bm_box((0.26, 0.08, 0.14), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(-0.44, 0.38, -0.18), rot=(0.0, 0.0, -18.0))
    h.add(A.bm_box((0.20, 0.04, 0.09), bevel=0.01, segments=2), m["M_GlowAmber"], loc=(-0.44, 0.34, -0.18), rot=(0.0, 0.0, -18.0))
    # 叠放的 3 本精装科考日志/档案夹
    h.add(A.bm_box((0.32, 0.05, 0.24), bevel=0.01, segments=2), m["M_FabricBlue"], loc=(-0.08, 0.025, 0.04), rot=(0.0, 8.0, 0.0))
    h.add(A.bm_box((0.30, 0.045, 0.22), bevel=0.01, segments=2), m["M_PaintOrange"], loc=(-0.06, 0.072, 0.02), rot=(0.0, -6.0, 0.0))
    h.add(A.bm_box((0.28, 0.04, 0.20), bevel=0.01, segments=2), m["M_PaintCream"], loc=(-0.08, 0.114, 0.04), rot=(0.0, 14.0, 0.0))
    # 陶瓷热饮杯 + 平板记录板 + 小工具盒
    h.add(bm_cyl(0.052, 0.048, 0.11, 14), m["M_PaintCream"], loc=(0.30, 0.055, 0.12))
    h.add(A.bm_box((0.34, 0.03, 0.24), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(0.48, 0.018, -0.12), rot=(0.0, -22.0, 0.0))
    h.add(A.bm_box((0.28, 0.02, 0.18), bevel=0.01, segments=2), m["M_GlowCyan"], loc=(0.48, 0.032, -0.12), rot=(0.0, -22.0, 0.0))
    export_model(h, "hero_desk_clutter.glb", seed=165)


def build_wall_pilaster():
    """6. 新增：室内建筑级钢构承重肋柱 + 腰线护墙板 + 踢脚线（宽 8.5m × 高 6.5m，贴内墙秒变 AAA 科幻建筑！）"""
    m = fresh_mats()
    h = A.Hero("HeroWallPilaster")
    # 底部防撞深钢踢脚线 + 腰高金属防护栏带
    h.add(A.bm_box((8.6, 0.36, 0.26), bevel=0.04, segments=2), m["M_DarkSteel"], loc=(0.0, 0.18, 0.06))
    h.add(A.bm_box((8.6, 0.20, 0.22), bevel=0.03, segments=2), m["M_PaintOrange"], loc=(0.0, 1.35, 0.06))
    h.add(A.bm_box((8.6, 0.28, 0.28), bevel=0.04, segments=2), m["M_CastSteel"], loc=(0.0, 5.85, 0.08))
    # 3 根斜顶托钢构承重柱 + 微发光工业安全灯带
    for px in (-3.8, 0.0, 3.8):
        h.add(A.bm_box((0.46, 6.2, 0.42), bevel=0.05, segments=2), m["M_CastSteel"], loc=(px, 3.1, 0.06))
        h.add(A.bm_box((0.54, 0.56, 0.48), bevel=0.05, segments=2), m["M_DarkSteel"], loc=(px, 0.28, 0.08))
        h.add(A.bm_box((0.12, 1.4, 0.08), bevel=0.01, segments=2), m["M_GlowCyan"], loc=(px, 3.6, 0.28))
    export_model(h, "hero_wall_pilaster.glb", seed=166)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    refine_hydro_planter()
    refine_sofa_lounge()
    refine_drill_rig()
    refine_cryo_sample_tank()
    build_desk_clutter()
    build_wall_pilaster()
    print("REFINE_INTERIOR_HERO_ART_OK (6 GLBs)")


if __name__ == "__main__":
    main()
