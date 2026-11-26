"""《迷失太空》极地雪地摩托 + 12 套差异化生活化室内核心家具与专业设施（Blender 4.5 / Y-up Godot 坐标系）
彻底解决室内“简陋且大同小异”的问题，让每一栋建筑推门进去一眼就能认出它的用途与人类生活痕迹：
1.  hero_snowmobile.glb        —— 极地双撬科幻雪地摩托（停在飞船出门左前方，一出门就能骑！）
2.  hero_bunk_bed.glb          —— 科考队员上下铺/生活床铺（带枕头、被褥、暖光床头灯、脚箱）
3.  hero_dining_set.glb        —— 餐厅生活餐桌椅组（带餐盘、保温杯与桌垫）
4.  hero_lab_workstation.glb   —— 专业科研实验台（双屏终端、显微镜、发光试剂试管架、台灯）
5.  hero_holo_map_table.glb    —— 中央全息战术星图/盆地沙盘桌（青蓝发光全息投影）
6.  hero_med_pod.glb           —— 医疗舱维生恢复床（翡翠绿心率监测屏 + 悬臂扫描灯）
7.  hero_hydro_planter.glb     —— 生态温室水培种植槽（紫暖植物补光灯架 + 郁郁葱葱绿植）
8.  hero_giant_telescope.glb   —— 天文观测穹顶巨型折返式天文望远镜（带赤道仪与星图台）
9.  hero_reactor_turbine.glb   —— 地热反应堆立式核心涡轮机（发光橙金等离子环 + 粗装甲管路）
10. hero_storage_rack.glb      —— 重型工业仓储货架（满载整齐码放的物资箱与工具筒）
11. hero_mech_gantry.glb       —— 机甲/车库龙门吊维修架（橙黑龙门桁架 + 吊钩 + 工具柜）
12. hero_drill_rig.glb         —— 冰川钻探中心立式冰芯钻机塔（螺旋钻杆 + 发光蓝冰芯标本筒）
13. hero_museum_pedestal.glb   —— 标本馆发光玻璃展台与黄铜围栏柱
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
    mats["M_GlowCyan"] = K.mat("M_GlowCyan", (0.20, 0.88, 0.98), 0.14, 0.0,
                               emit=(0.18, 0.86, 0.98), emit_strength=2.2)
    mats["M_GlowAmber"] = K.mat("M_GlowAmber", (0.98, 0.62, 0.18), 0.16, 0.0,
                                emit=(0.98, 0.58, 0.16), emit_strength=2.2)
    mats["M_GlowGreen"] = K.mat("M_GlowGreen", (0.20, 0.88, 0.52), 0.18, 0.0,
                                emit=(0.20, 0.88, 0.52), emit_strength=2.0)
    mats["M_GlowRed"] = K.mat("M_GlowRed", (0.96, 0.24, 0.16), 0.16, 0.0,
                              emit=(1.0, 0.24, 0.14), emit_strength=2.2)
    mats["M_PlantLeaf"] = K.mat("M_PlantLeaf", (0.16, 0.54, 0.26), 0.62, 0.0)
    mats["M_FabricWarm"] = K.mat("M_FabricWarm", (0.58, 0.44, 0.34), 0.78, 0.0)
    mats["M_FabricBlue"] = K.mat("M_FabricBlue", (0.26, 0.46, 0.56), 0.76, 0.0)
    return mats


def export_model(hero, filename, seed=101, ao_rays=6):
    gain = dict(HM.WEAR_GAIN)
    gain["M_PlantLeaf"] = 0.4
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


def bm_cyl(r1, r2, h, segs=18):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi * 0.5, 3, 'X'))
    return bm


def build_snowmobile():
    """1. 极地科幻双撬雪地摩托（宽 1.38m × 长 3.25m × 高 1.36m，-Z 朝前）"""
    m = fresh_mats()
    h = A.Hero("HeroSnowmobile")
    # 后部宽厚橡胶履带总成 + 减震支架
    h.add(A.bm_box((0.56, 0.46, 1.65), bevel=0.14, segments=2), m["M_Rubber"], loc=(0.0, 0.24, 0.55))
    for rz in (-0.12, 0.35, 0.82, 1.22):
        h.add(bm_cyl(0.18, 0.18, 0.60, 14), m["M_CastSteel"], loc=(0.0, 0.22, rz), rot=(0.0, 0.0, 90.0))
    # 履带上方挡泥护甲与后部小货架
    h.add(A.bm_box((0.68, 0.18, 1.55), bevel=0.04, segments=2), m["M_DarkSteel"], loc=(0.0, 0.56, 0.58))
    h.add(A.bm_box((0.62, 0.08, 0.55), bevel=0.02, segments=2), m["M_CastSteel"], loc=(0.0, 0.72, 1.25))
    # 流线型奶油白+工业橙车头装甲整流罩
    h.add(A.bm_box((0.86, 0.52, 1.28), bevel=0.14, segments=2), m["M_PaintCream"], loc=(0.0, 0.66, -0.58), rot=(8.0, 0.0, 0.0))
    h.add(A.bm_box((0.64, 0.34, 0.62), bevel=0.10, segments=2), m["M_PaintOrange"], loc=(0.0, 0.56, -1.26), rot=(16.0, 0.0, 0.0))
    # 两侧通风散热鳍与护腿踏板
    for sx in (-1.0, 1.0):
        h.add(A.bm_box((0.28, 0.10, 1.45), bevel=0.03, segments=2), m["M_DarkSteel"], loc=(sx * 0.44, 0.36, 0.18))
        h.add(A.bm_box((0.12, 0.24, 0.72), bevel=0.03, segments=2), m["M_PaintOrange"], loc=(sx * 0.44, 0.68, -0.58))
        # 前双滑雪撬 + 橙色液压避震连杆
        h.add(A.bm_box((0.24, 0.08, 1.48), bevel=0.03, segments=2), m["M_DarkSteel"], loc=(sx * 0.58, 0.06, -1.02))
        h.add(A.bm_box((0.24, 0.10, 0.34), bevel=0.03, segments=2), m["M_PaintOrange"], loc=(sx * 0.58, 0.18, -1.80), rot=(-32.0, 0.0, 0.0))
        h.add(bm_cyl(0.05, 0.05, 0.58, 10), m["M_PaintOrange"], loc=(sx * 0.52, 0.38, -1.02), rot=(0.0, 0.0, sx * 16.0))
    # 斜风挡 + 车把 + 发光冰青液晶仪表盘
    h.add(A.bm_box((0.58, 0.42, 0.07), bevel=0.02, segments=2), m["M_GlowCyan"], loc=(0.0, 1.12, -0.58), rot=(-38.0, 0.0, 0.0))
    h.add(bm_cyl(0.035, 0.035, 0.92, 12), m["M_DarkSteel"], loc=(0.0, 1.06, -0.32), rot=(0.0, 0.0, 90.0))
    for sx in (-0.44, 0.44):
        h.add(bm_cyl(0.048, 0.048, 0.18, 12), m["M_Rubber"], loc=(sx, 1.06, -0.32), rot=(0.0, 0.0, 90.0))
    # 加厚长鞍座（支持 1-2 人骑乘）
    h.add(A.bm_box((0.46, 0.24, 1.18), bevel=0.09, segments=2), m["M_Rubber"], loc=(0.0, 0.82, 0.40))
    h.add(A.bm_box((0.42, 0.22, 0.18), bevel=0.06, segments=2), m["M_PaintOrange"], loc=(0.0, 0.94, 0.96), rot=(-16.0, 0.0, 0.0))
    # 双发光大灯 + 尾部氮气涡轮喷口
    for sx in (-0.22, 0.22):
        h.add(A.bm_box((0.18, 0.10, 0.08), bevel=0.02, segments=2), m["M_GlowAmber"], loc=(sx, 0.68, -1.56))
        h.add(bm_cyl(0.08, 0.10, 0.24, 12), m["M_GlowCyan"], loc=(sx * 0.9, 0.54, 1.46), rot=(90.0, 0.0, 0.0))
    export_model(h, "hero_snowmobile.glb", seed=101)


def build_bunk_bed():
    """2. 宇航员生活床铺（带金属床架、暖色床垫枕头、折叠被子、暖光床头灯、床尾储物箱）"""
    m = fresh_mats()
    h = A.Hero("HeroBunkBed")
    # 四根钢架立柱 + 上下两层床板
    for sx in (-0.65, 0.65):
        for sz in (-1.12, 1.12):
            h.add(A.bm_box((0.09, 2.25, 0.09), bevel=0.02, segments=2), m["M_CastSteel"], loc=(sx, 1.12, sz))
    for by in (0.48, 1.56):
        h.add(A.bm_box((1.34, 0.12, 2.26), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(0.0, by, 0.0))
        h.add(A.bm_box((1.22, 0.20, 2.12), bevel=0.06, segments=2), m["M_PaintCream"], loc=(0.0, by + 0.15, 0.0))
        # 温暖盖被 + 枕头（像人刚起过床一样有生活气息）
        h.add(A.bm_box((1.24, 0.14, 1.38), bevel=0.05, segments=2), m["M_FabricBlue"] if by < 1.0 else m["M_FabricWarm"], loc=(0.0, by + 0.24, 0.34))
        h.add(A.bm_box((0.76, 0.14, 0.42), bevel=0.05, segments=2), m["M_PaintCream"], loc=(0.0, by + 0.28, -0.78))
    # 侧面爬梯 + 暖光床头阅读灯
    for ry in (0.6, 0.95, 1.3, 1.65):
        h.add(A.bm_box((0.06, 0.06, 0.44), bevel=0.01, segments=2), m["M_PaintOrange"], loc=(0.68, ry, 0.55))
    h.add(A.bm_box((0.36, 0.12, 0.12), bevel=0.02, segments=2), m["M_GlowAmber"], loc=(0.0, 1.18, -1.06))
    # 床头小矮柜
    h.add(A.bm_box((0.60, 0.62, 0.55), bevel=0.04, segments=2), m["M_PaintCream"], loc=(1.10, 0.31, -0.82))
    export_model(h, "hero_bunk_bed.glb", seed=102)


def build_dining_set():
    """3. 科考站生活食堂餐桌椅组（长餐桌 + 4 把椅子 + 餐盘与杯子）"""
    m = fresh_mats()
    h = A.Hero("HeroDiningSet")
    # 桌面与钢腿
    h.add(A.bm_box((2.6, 0.10, 1.28), bevel=0.03, segments=2), m["M_PaintCream"], loc=(0.0, 0.82, 0.0))
    for sx in (-1.05, 1.05):
        h.add(A.bm_box((0.12, 0.80, 0.96), bevel=0.02, segments=2), m["M_CastSteel"], loc=(sx, 0.40, 0.0))
    # 桌上的餐盘、饮水杯与暖色桌面装饰条
    h.add(A.bm_box((2.2, 0.02, 0.24), bevel=0.01, segments=2), m["M_PaintOrange"], loc=(0.0, 0.88, 0.0))
    for sx in (-0.75, 0.75):
        for sz in (-0.34, 0.34):
            h.add(A.bm_box((0.42, 0.04, 0.28), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(sx, 0.89, sz))
            h.add(bm_cyl(0.055, 0.055, 0.12, 12), m["M_PaintCream"], loc=(sx + 0.28, 0.93, sz))
            # 四把椅子
            cy_dir = 1.0 if sz > 0 else -1.0
            h.add(A.bm_box((0.48, 0.08, 0.46), bevel=0.02, segments=2), m["M_FabricWarm"], loc=(sx, 0.48, sz * 2.55))
            h.add(A.bm_box((0.46, 0.48, 0.08), bevel=0.02, segments=2), m["M_CastSteel"], loc=(sx, 0.74, sz * 2.55 + cy_dir * 0.20))
            h.add(A.bm_box((0.08, 0.46, 0.08), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(sx, 0.23, sz * 2.55))
    export_model(h, "hero_dining_set.glb", seed=103)


def build_lab_workstation():
    """4. 专业极地科研实验台（双显示器、显微镜、发光试剂架与工作灯）"""
    m = fresh_mats()
    h = A.Hero("HeroLabWorkstation")
    # 宽实验台台面 + 下层储物抽屉柜
    h.add(A.bm_box((3.2, 0.12, 1.35), bevel=0.03, segments=2), m["M_PaintCream"], loc=(0.0, 0.94, 0.0))
    for sx in (-1.28, 1.28):
        h.add(A.bm_box((0.56, 0.90, 1.18), bevel=0.03, segments=2), m["M_CastSteel"], loc=(sx, 0.45, 0.0))
    # 双发光科学分析屏
    for sx, ry in ((-0.75, 12.0), (0.05, -6.0)):
        h.add(A.bm_box((0.76, 0.52, 0.06), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(sx, 1.36, -0.35), rot=(0.0, ry, 0.0))
        h.add(A.bm_box((0.68, 0.44, 0.03), bevel=0.01, segments=2), m["M_GlowCyan"], loc=(sx, 1.36, -0.31), rot=(0.0, ry, 0.0))
        h.add(A.bm_box((0.12, 0.26, 0.12), bevel=0.02, segments=2), m["M_CastSteel"], loc=(sx, 1.08, -0.38))
    # 右侧样本显微镜 + 发光冰样试管架
    h.add(A.bm_box((0.36, 0.10, 0.36), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(0.88, 1.04, 0.05))
    h.add(bm_cyl(0.05, 0.07, 0.42, 12), m["M_PaintOrange"], loc=(0.88, 1.28, -0.02), rot=(-18.0, 0.0, 0.0))
    h.add(A.bm_box((0.46, 0.14, 0.22), bevel=0.02, segments=2), m["M_CastSteel"], loc=(1.28, 1.06, -0.18))
    for tx in (1.12, 1.22, 1.32, 1.42):
        h.add(bm_cyl(0.028, 0.028, 0.28, 10), m["M_GlowCyan"] if tx < 1.3 else m["M_GlowGreen"], loc=(tx, 1.22, -0.18))
    # 悬臂实验照明灯
    h.add(A.bm_box((2.8, 0.10, 0.16), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(0.0, 2.10, -0.45))
    h.add(A.bm_box((2.4, 0.05, 0.10), bevel=0.01, segments=2), m["M_GlowAmber"], loc=(0.0, 2.04, -0.45))
    for sx in (-1.35, 1.35):
        h.add(A.bm_box((0.08, 1.15, 0.08), bevel=0.01, segments=2), m["M_CastSteel"], loc=(sx, 1.52, -0.45))
    export_model(h, "hero_lab_workstation.glb", seed=104)


def build_holo_map_table():
    """5. 中央全息战术沙盘桌（适合主楼大厅与通讯总部）"""
    m = fresh_mats()
    h = A.Hero("HeroHoloMapTable")
    h.add(bm_cyl(1.85, 1.55, 0.92, 12), m["M_CastSteel"], loc=(0.0, 0.46, 0.0))
    h.add(bm_cyl(2.05, 2.05, 0.18, 12), m["M_DarkSteel"], loc=(0.0, 0.98, 0.0))
    h.add(bm_cyl(1.75, 1.75, 0.08, 16), m["M_GlowCyan"], loc=(0.0, 1.09, 0.0))
    # 漂浮微缩地形柱与轨道环
    for a in range(0, 360, 60):
        rad = math.radians(a)
        h.add(A.bm_box((0.28, 0.35 + (a % 120) * 0.003, 0.28), bevel=0.02, segments=2),
              m["M_GlowCyan"], loc=(math.cos(rad) * 0.72, 1.35, math.sin(rad) * 0.72))
    h.add(bm_cyl(0.45, 0.15, 0.85, 12), m["M_GlowAmber"], loc=(0.0, 1.55, 0.0))
    export_model(h, "hero_holo_map_table.glb", seed=105)


def build_med_pod():
    """6. 医疗维生恢复舱床（生活医疗楼专属）"""
    m = fresh_mats()
    h = A.Hero("HeroMedPod")
    h.add(A.bm_box((1.35, 0.68, 2.45), bevel=0.10, segments=2), m["M_PaintCream"], loc=(0.0, 0.34, 0.0))
    h.add(A.bm_box((1.12, 0.16, 2.15), bevel=0.06, segments=2), m["M_FabricBlue"], loc=(0.0, 0.74, 0.0))
    # 头端心率生命监测仪（发光绿屏）+ 悬臂扫描环
    h.add(A.bm_box((1.28, 1.65, 0.34), bevel=0.06, segments=2), m["M_CastSteel"], loc=(0.0, 0.88, -1.16))
    h.add(A.bm_box((0.92, 0.56, 0.06), bevel=0.02, segments=2), m["M_GlowGreen"], loc=(0.0, 1.32, -0.98))
    h.add(A.bm_box((1.22, 0.12, 0.32), bevel=0.03, segments=2), m["M_PaintCream"], loc=(0.0, 1.58, -0.25))
    h.add(A.bm_box((0.96, 0.06, 0.16), bevel=0.01, segments=2), m["M_GlowGreen"], loc=(0.0, 1.50, -0.25))
    export_model(h, "hero_med_pod.glb", seed=106)


def build_hydro_planter():
    """7. 生态穹顶水培种植槽（带茂密绿植与顶部发光补光灯架）"""
    m = fresh_mats()
    h = A.Hero("HeroHydroPlanter")
    h.add(A.bm_box((3.6, 0.88, 1.45), bevel=0.06, segments=2), m["M_PaintCream"], loc=(0.0, 0.44, 0.0))
    h.add(A.bm_box((3.35, 0.14, 1.22), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(0.0, 0.86, 0.0))
    # 茂密层次感水培作物丛
    for px in (-1.25, -0.62, 0.0, 0.62, 1.25):
        for pz in (-0.28, 0.28):
            h.add(bm_cyl(0.24, 0.32, 0.48, 8), m["M_PlantLeaf"], loc=(px, 1.14, pz), rot=(6.0, px * 35.0, -5.0))
            h.add(bm_cyl(0.14, 0.24, 0.32, 7), m["M_GlowGreen"], loc=(px, 1.38, pz))
    # 上方植物生长补光灯龙门架
    for sx in (-1.65, 1.65):
        h.add(A.bm_box((0.12, 1.48, 0.12), bevel=0.02, segments=2), m["M_CastSteel"], loc=(sx, 1.58, 0.0))
    h.add(A.bm_box((3.48, 0.12, 0.36), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(0.0, 2.34, 0.0))
    h.add(A.bm_box((3.10, 0.06, 0.22), bevel=0.01, segments=2), m["M_GlowAmber"], loc=(0.0, 2.26, 0.0))
    export_model(h, "hero_hydro_planter.glb", seed=107)


def build_giant_telescope():
    """8. 天文观测穹顶巨型望远镜（高约 6.5m，斜指极地夜空！）"""
    m = fresh_mats()
    h = A.Hero("HeroGiantTelescope")
    # 厚重圆形基座与旋转赤道仪叉臂
    h.add(bm_cyl(2.4, 2.1, 1.1, 18), m["M_CastSteel"], loc=(0.0, 0.55, 0.0))
    h.add(bm_cyl(1.4, 1.1, 2.2, 16), m["M_DarkSteel"], loc=(0.0, 2.1, 0.0))
    for sx in (-1.15, 1.15):
        h.add(A.bm_box((0.35, 2.6, 0.65), bevel=0.05, segments=2), m["M_PaintOrange"], loc=(sx, 3.6, 0.0))
    # 巨大镜筒（斜指 42° 高空！）
    h.add(bm_cyl(1.05, 0.92, 6.4, 22), m["M_PaintCream"], loc=(0.0, 4.8, -0.4), rot=(42.0, 0.0, 0.0))
    h.add(bm_cyl(1.12, 1.12, 0.45, 22), m["M_PaintOrange"], loc=(0.0, 6.2, -1.7), rot=(42.0, 0.0, 0.0))
    h.add(bm_cyl(0.82, 0.82, 0.18, 20), m["M_GlowCyan"], loc=(0.0, 7.1, -2.5), rot=(42.0, 0.0, 0.0))
    export_model(h, "hero_giant_telescope.glb", seed=108)


def build_reactor_turbine():
    """9. 地热反应堆立式核心涡轮机（高 7.2m，动力站/反应堆电厂核心标志！）"""
    m = fresh_mats()
    h = A.Hero("HeroReactorTurbine")
    h.add(bm_cyl(2.2, 1.9, 1.2, 16), m["M_DarkSteel"], loc=(0.0, 0.6, 0.0))
    h.add(bm_cyl(1.35, 1.35, 5.8, 18), m["M_CastSteel"], loc=(0.0, 4.0, 0.0))
    # 3 道发光琥珀等离子环
    for ry in (2.3, 4.0, 5.7):
        h.add(bm_cyl(1.65, 1.65, 0.42, 18), m["M_GlowAmber"], loc=(0.0, ry, 0.0))
    # 4 根粗装甲散热导管
    for a in (0, 90, 180, 270):
        rad = math.radians(a)
        h.add(bm_cyl(0.26, 0.26, 5.6, 12), m["M_PaintOrange"], loc=(math.cos(rad) * 1.75, 3.8, math.sin(rad) * 1.75))
    h.add(bm_cyl(1.85, 2.0, 0.9, 16), m["M_DarkSteel"], loc=(0.0, 7.2, 0.0))
    export_model(h, "hero_reactor_turbine.glb", seed=109)


def build_storage_rack():
    """10. 重型工业仓储货架（满载整齐码放的物资箱，仓库与货运总站专属！）"""
    m = fresh_mats()
    h = A.Hero("HeroStorageRack")
    for sx in (-1.75, 1.75):
        for sz in (-0.58, 0.58):
            h.add(A.bm_box((0.12, 3.8, 0.12), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(sx, 1.9, sz))
    for sy in (0.35, 1.55, 2.75):
        h.add(A.bm_box((3.62, 0.10, 1.26), bevel=0.02, segments=2), m["M_CastSteel"], loc=(0.0, sy, 0.0))
        # 每层整齐摆放的工业物资箱
        for bx in (-1.12, 0.0, 1.12):
            mat_b = m["M_PaintCream"] if (int(sy + bx) % 2 == 0) else m["M_DarkSteel"]
            h.add(A.bm_box((0.92, 0.78, 0.96), bevel=0.04, segments=2), mat_b, loc=(bx, sy + 0.44, 0.0))
            h.add(A.bm_box((0.36, 0.12, 0.98), bevel=0.01, segments=2), m["M_GlowCyan"] if sy > 2.0 else m["M_PaintOrange"], loc=(bx, sy + 0.65, 0.0))
    export_model(h, "hero_storage_rack.glb", seed=110)


def build_mech_gantry():
    """11. 机甲/车库龙门吊重型维修架（高 6.6m × 跨度 7.6m，机修厂与车库专属！）"""
    m = fresh_mats()
    h = A.Hero("HeroMechGantry")
    for sx in (-3.6, 3.6):
        h.add(A.bm_box((0.68, 6.2, 1.1), bevel=0.06, segments=2), m["M_PaintOrange"], loc=(sx, 3.1, 0.0))
        h.add(A.bm_box((1.2, 0.35, 2.6), bevel=0.05, segments=2), m["M_DarkSteel"], loc=(sx, 0.18, 0.0))
    # 顶部龙门主梁 + 滑动吊车 + 暖光作业大灯
    h.add(A.bm_box((8.2, 0.72, 0.95), bevel=0.06, segments=2), m["M_CastSteel"], loc=(0.0, 6.25, 0.0))
    h.add(A.bm_box((1.5, 0.65, 1.2), bevel=0.05, segments=2), m["M_PaintOrange"], loc=(0.4, 5.72, 0.0))
    h.add(bm_cyl(0.08, 0.08, 1.8, 10), m["M_DarkSteel"], loc=(0.4, 4.6, 0.0))
    h.add(A.bm_box((0.55, 0.38, 0.35), bevel=0.04, segments=2), m["M_GlowAmber"], loc=(0.4, 3.65, 0.0))
    export_model(h, "hero_mech_gantry.glb", seed=111)


def build_drill_rig():
    """12. 冰川钻探中心立式冰芯钻机塔（高 7.8m，自带旋转钻杆与发光蓝冰芯！）"""
    m = fresh_mats()
    h = A.Hero("HeroDrillRig")
    h.add(bm_cyl(2.6, 2.2, 0.65, 12), m["M_DarkSteel"], loc=(0.0, 0.32, 0.0))
    # 四根斜撑钻塔钢架
    for sx in (-1.4, 1.4):
        for sz in (-1.4, 1.4):
            h.add(A.bm_box((0.28, 7.6, 0.28), bevel=0.03, segments=2), m["M_PaintOrange"], loc=(sx, 3.9, sz))
    h.add(A.bm_box((3.2, 0.8, 3.2), bevel=0.06, segments=2), m["M_CastSteel"], loc=(0.0, 7.4, 0.0))
    # 中央高速冰芯钻杆 + 提取出的发光极地蓝冰芯圆柱
    h.add(bm_cyl(0.42, 0.42, 7.2, 16), m["M_CastSteel"], loc=(0.0, 3.8, 0.0))
    h.add(bm_cyl(0.56, 0.56, 2.4, 16), m["M_GlowCyan"], loc=(0.0, 2.2, 0.0))
    h.add(bm_cyl(0.95, 0.95, 0.45, 16), m["M_GlowAmber"], loc=(0.0, 4.2, 0.0))
    export_model(h, "hero_drill_rig.glb", seed=112)


def build_museum_pedestal():
    """13. 标本馆发光展台与围栏柱（标本馆专属！）"""
    m = fresh_mats()
    h = A.Hero("HeroMuseumPedestal")
    h.add(A.bm_box((2.2, 1.05, 1.35), bevel=0.06, segments=2), m["M_DarkSteel"], loc=(0.0, 0.52, 0.0))
    h.add(A.bm_box((2.05, 0.12, 1.22), bevel=0.02, segments=2), m["M_GlowAmber"], loc=(0.0, 1.08, 0.0))
    # 展台上的发光微型骨化石样本
    h.add(bm_cyl(0.18, 0.24, 0.72, 12), m["M_PaintCream"], loc=(0.0, 1.42, 0.0), rot=(0.0, 0.0, 72.0))
    # 前方两根黄铜护栏立柱
    for sx in (-1.35, 1.35):
        h.add(bm_cyl(0.06, 0.08, 0.96, 12), m["M_Bronze"], loc=(sx, 0.48, 1.15))
    h.add(A.bm_box((2.7, 0.05, 0.05), bevel=0.01, segments=2), m["M_PaintOrange"], loc=(0.0, 0.82, 1.15))
    export_model(h, "hero_museum_pedestal.glb", seed=113)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    build_snowmobile()
    build_bunk_bed()
    build_dining_set()
    build_lab_workstation()
    build_holo_map_table()
    build_med_pod()
    build_hydro_planter()
    build_giant_telescope()
    build_reactor_turbine()
    build_storage_rack()
    build_mech_gantry()
    build_drill_rig()
    build_museum_pedestal()
    print("BUILD_INTERIORS_AND_SNOWMOBILE_OK (13 GLBs)")


if __name__ == "__main__":
    main()
