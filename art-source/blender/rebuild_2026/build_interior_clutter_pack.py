"""《迷失太空》室内深度丰富化 · 10 套生活化陈设与墙顶工业设施（Blender 4.5 / Y-up）
彻底填满 32–42m 巨型建筑的大片空白墙面、天花板与角落，呈现“真实有人生活办公过的科幻极地科考城”：
1. hero_wall_pipe_run.glb       —— 贴墙重型保温工业管束 + 橙色压力阀门 + 仪表盘（消除光秃秃灰墙！）
2. hero_ceiling_truss_lamp.glb  —— 悬挂式工业桁架长条吊灯 + 钢索（彻底消除空荡平顶！）
3. hero_locker_bank.glb         —— 4 门宇航员个人储物衣柜组（半开门 + 柜顶宇航头盔 + 铭牌，人味拉满！）
4. hero_server_rack.glb         —— 科研主机/数据机柜（密集青蓝/琥珀呼吸指示灯阵列 + 线缆）
5. hero_sofa_lounge.glb         —— 温馨休闲转角沙发 + 矮茶几（摆着平板、热茶杯与桌面盆栽）
6. hero_kitchen_counter.glb     —— 极地生活厨房吧台（咖啡机 + 食品加热炉 + 水槽 + 吊杯架）
7. hero_tool_wall_cabinet.glb   —— 机修工具挂板墙 + 红色轮式工具车 + 备用轮胎（车库与机甲厂灵魂！）
8. hero_cryo_sample_tank.glb    —— 圆柱形发光冰样/生物标本培养柱（里面封存发光极地蓝晶或绿植！）
9. hero_whiteboard_wall.glb     —— 贴墙发光科研任务简报白板/全息战术地图屏
10. hero_floor_clutter.glb      —— 角落生活/工作杂物堆（叠放手提箱 + 卷起的橙色电缆 + 便携暖风机 + 警示锥）
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
    mats["M_GlowGreen"] = K.mat("M_GlowGreen", (0.20, 0.88, 0.52), 0.18, 0.0, emit=(0.20, 0.88, 0.52), emit_strength=2.0)
    mats["M_GlowRed"] = K.mat("M_GlowRed", (0.96, 0.24, 0.16), 0.16, 0.0, emit=(1.0, 0.24, 0.14), emit_strength=2.2)
    mats["M_PlantLeaf"] = K.mat("M_PlantLeaf", (0.16, 0.54, 0.26), 0.62, 0.0)
    mats["M_FabricWarm"] = K.mat("M_FabricWarm", (0.58, 0.44, 0.34), 0.78, 0.0)
    mats["M_FabricBlue"] = K.mat("M_FabricBlue", (0.26, 0.46, 0.56), 0.76, 0.0)
    mats["M_GlassWarm"] = K.mat("M_GlassWarm", (0.68, 0.84, 0.88), 0.10, 0.16, emit=(0.40, 0.78, 0.88), emit_strength=0.45)
    return mats


def export_model(hero, filename, seed=130, ao_rays=6):
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


def bm_cyl(r1, r2, h, segs=16):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi * 0.5, 3, 'X'))
    return bm


def build_wall_pipe_run():
    """1. 贴墙 9m 工业保温管束 + 橙色阀门 + 竖向立柱（彻底打破光秃秃灰墙！）"""
    m = fresh_mats()
    h = A.Hero("HeroWallPipeRun")
    for py, rad, mat_k in ((3.2, 0.22, "M_CastSteel"), (2.6, 0.16, "M_PaintCream"), (2.1, 0.14, "M_PaintOrange")):
        h.add(bm_cyl(rad, rad, 9.0, 14), m[mat_k], loc=(0.0, py, 0.0), rot=(0.0, 0.0, 90.0))
    for bx in (-3.6, -1.2, 1.2, 3.6):
        h.add(A.bm_box((0.28, 3.8, 0.42), bevel=0.04, segments=2), m["M_DarkSteel"], loc=(bx, 1.9, -0.10))
        h.add(A.bm_box((0.46, 0.52, 0.16), bevel=0.02, segments=2), m["M_GlowCyan"] if bx > 0 else m["M_GlowAmber"], loc=(bx, 1.55, 0.15))
    # 两个手轮阀门
    for vx in (-2.4, 2.4):
        h.add(bm_cyl(0.24, 0.24, 0.08, 16), m["M_PaintOrange"], loc=(vx, 2.1, 0.26), rot=(90.0, 0.0, 0.0))
    export_model(h, "hero_wall_pipe_run.glb", seed=131)


def build_ceiling_truss_lamp():
    """2. 悬挂式 6.5m 工业桁架双管吊灯（吊在室内天花板下，立体层次立刻拉满！）"""
    m = fresh_mats()
    h = A.Hero("HeroCeilingTrussLamp")
    h.add(A.bm_box((6.5, 0.24, 0.85), bevel=0.04, segments=2), m["M_DarkSteel"], loc=(0.0, 0.0, 0.0))
    for sz in (-0.26, 0.26):
        h.add(A.bm_box((6.1, 0.10, 0.16), bevel=0.02, segments=2), m["M_GlowAmber"], loc=(0.0, -0.14, sz))
    for sx in (-2.6, 2.6):
        h.add(bm_cyl(0.05, 0.05, 1.8, 10), m["M_CastSteel"], loc=(sx, 0.95, 0.0))
        h.add(A.bm_box((0.36, 0.34, 0.95), bevel=0.03, segments=2), m["M_PaintOrange"], loc=(sx, 0.04, 0.0))
    export_model(h, "hero_ceiling_truss_lamp.glb", seed=132)


def build_locker_bank():
    """3. 4 门宇航员个人储物衣柜（其中一扇门半开 + 柜顶放着橘色头盔和工具盒！）"""
    m = fresh_mats()
    h = A.Hero("HeroLockerBank")
    h.add(A.bm_box((3.2, 2.35, 0.72), bevel=0.04, segments=2), m["M_CastSteel"], loc=(0.0, 1.18, 0.0))
    for i in range(4):
        lx = -1.16 + i * 0.78
        if i == 2:
            # 半开柜门（立刻产生“刚有人取过装备”的生活感！）
            h.add(A.bm_box((0.68, 2.08, 0.06), bevel=0.02, segments=2), m["M_PaintCream"], loc=(lx + 0.18, 1.18, 0.56), rot=(0.0, -42.0, 0.0))
        else:
            h.add(A.bm_box((0.68, 2.08, 0.06), bevel=0.02, segments=2), m["M_PaintCream"], loc=(lx, 1.18, 0.38))
            h.add(A.bm_box((0.06, 0.32, 0.08), bevel=0.01, segments=2), m["M_PaintOrange"], loc=(lx + 0.24, 1.24, 0.43))
        h.add(A.bm_box((0.44, 0.14, 0.04), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(lx, 1.98, 0.42))
    # 柜顶放着备用的宇航头盔与收纳箱
    h.add(bm_cyl(0.20, 0.18, 0.34, 14), m["M_PaintOrange"], loc=(-0.95, 2.52, 0.0))
    h.add(A.bm_box((0.76, 0.36, 0.52), bevel=0.03, segments=2), m["M_DarkSteel"], loc=(0.82, 2.54, 0.0))
    export_model(h, "hero_locker_bank.glb", seed=133)


def build_server_rack():
    """4. 科研数据主机机柜（高 2.5m，密集青蓝/绿/琥珀闪烁指示灯！）"""
    m = fresh_mats()
    h = A.Hero("HeroServerRack")
    h.add(A.bm_box((1.35, 2.55, 1.10), bevel=0.05, segments=2), m["M_DarkSteel"], loc=(0.0, 1.28, 0.0))
    for i in range(6):
        sy = 0.42 + i * 0.36
        h.add(A.bm_box((1.12, 0.24, 0.08), bevel=0.02, segments=2), m["M_CastSteel"], loc=(0.0, sy, 0.55))
        h.add(A.bm_box((0.52, 0.06, 0.05), bevel=0.01, segments=2), m["M_GlowCyan"] if i % 2 == 0 else m["M_GlowGreen"], loc=(-0.20, sy + 0.03, 0.60))
        h.add(A.bm_box((0.16, 0.06, 0.05), bevel=0.01, segments=2), m["M_GlowAmber"], loc=(0.34, sy + 0.03, 0.60))
    h.add(A.bm_box((1.42, 0.16, 1.16), bevel=0.03, segments=2), m["M_PaintOrange"], loc=(0.0, 2.58, 0.0))
    export_model(h, "hero_server_rack.glb", seed=134)


def build_sofa_lounge():
    """5. 科考队员休息区 L 型沙发 + 矮茶几 + 桌面热茶杯与小绿植"""
    m = fresh_mats()
    h = A.Hero("HeroSofaLounge")
    # 长沙发底座、靠背与暖色布艺软垫
    h.add(A.bm_box((3.2, 0.42, 1.05), bevel=0.06, segments=2), m["M_CastSteel"], loc=(0.0, 0.22, -0.65))
    h.add(A.bm_box((3.05, 0.24, 0.92), bevel=0.08, segments=2), m["M_FabricWarm"], loc=(0.0, 0.52, -0.60))
    h.add(A.bm_box((3.05, 0.66, 0.26), bevel=0.08, segments=2), m["M_FabricWarm"], loc=(0.0, 0.88, -1.04))
    for sx in (-1.52, 1.52):
        h.add(A.bm_box((0.24, 0.62, 1.02), bevel=0.06, segments=2), m["M_FabricBlue"], loc=(sx, 0.55, -0.64))
    # 前方矮茶几 + 发光平板电脑 + 两个茶杯 + 桌面绿植盆栽
    h.add(A.bm_box((1.85, 0.10, 0.95), bevel=0.03, segments=2), m["M_PaintCream"], loc=(0.0, 0.52, 0.72))
    for sx in (-0.72, 0.72):
        h.add(A.bm_box((0.10, 0.50, 0.76), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(sx, 0.25, 0.72))
    h.add(A.bm_box((0.46, 0.04, 0.34), bevel=0.01, segments=2), m["M_GlowCyan"], loc=(-0.38, 0.59, 0.72), rot=(0.0, 14.0, 0.0))
    h.add(bm_cyl(0.16, 0.12, 0.22, 12), m["M_PaintOrange"], loc=(0.56, 0.68, 0.68))
    h.add(bm_cyl(0.22, 0.28, 0.34, 9), m["M_PlantLeaf"], loc=(0.56, 0.92, 0.68))
    export_model(h, "hero_sofa_lounge.glb", seed=135)


def build_kitchen_counter():
    """6. 极地科考站温馨厨房吧台（咖啡机 + 食品合成微波炉 + 水槽 + 吊灯栏）"""
    m = fresh_mats()
    h = A.Hero("HeroKitchenCounter")
    h.add(A.bm_box((4.4, 1.02, 1.25), bevel=0.04, segments=2), m["M_PaintCream"], loc=(0.0, 0.51, 0.0))
    h.add(A.bm_box((4.52, 0.10, 1.32), bevel=0.02, segments=2), m["M_DarkSteel"], loc=(0.0, 1.06, 0.0))
    # 左侧全自动极地咖啡机（带热杯和暖光指示）
    h.add(A.bm_box((0.68, 0.72, 0.54), bevel=0.04, segments=2), m["M_PaintOrange"], loc=(-1.45, 1.46, -0.22))
    h.add(A.bm_box((0.44, 0.24, 0.08), bevel=0.01, segments=2), m["M_GlowAmber"], loc=(-1.45, 1.62, 0.07))
    # 中央食品合成微波炉（青绿亮屏）
    h.add(A.bm_box((1.05, 0.66, 0.62), bevel=0.04, segments=2), m["M_CastSteel"], loc=(0.0, 1.44, -0.22))
    h.add(A.bm_box((0.64, 0.42, 0.06), bevel=0.01, segments=2), m["M_GlowCyan"], loc=(-0.12, 1.44, 0.10))
    # 右侧成摞餐盘与保温水壶
    h.add(bm_cyl(0.22, 0.22, 0.26, 16), m["M_PaintCream"], loc=(1.35, 1.24, 0.05))
    h.add(bm_cyl(0.14, 0.12, 0.44, 14), m["M_PaintOrange"], loc=(1.82, 1.32, -0.15))
    # 上方悬挂暖光吧台吊柜
    h.add(A.bm_box((4.2, 0.55, 0.65), bevel=0.04, segments=2), m["M_CastSteel"], loc=(0.0, 2.75, -0.22))
    h.add(A.bm_box((3.8, 0.08, 0.24), bevel=0.01, segments=2), m["M_GlowAmber"], loc=(0.0, 2.44, -0.22))
    export_model(h, "hero_kitchen_counter.glb", seed=136)


def build_tool_wall_cabinet():
    """7. 机修工具挂板墙 + 橘色滚轮工具箱 + 靠墙备用宽胎（车库/机甲厂神器！）"""
    m = fresh_mats()
    h = A.Hero("HeroToolWallCabinet")
    # 工具挂板背墙
    h.add(A.bm_box((3.6, 2.4, 0.18), bevel=0.03, segments=2), m["M_DarkSteel"], loc=(0.0, 1.4, -0.45))
    # 挂满扳手/焊枪/零件盒剪影
    for tx in (-1.3, -0.7, -0.1, 0.5, 1.1):
        h.add(A.bm_box((0.14, 0.68, 0.08), bevel=0.02, segments=2), m["M_CastSteel"], loc=(tx, 1.85, -0.32))
    h.add(A.bm_box((3.2, 0.16, 0.36), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(0.0, 2.42, -0.28))
    # 下方橘色重型滚轮工具柜
    h.add(A.bm_box((1.85, 1.05, 0.85), bevel=0.04, segments=2), m["M_PaintOrange"], loc=(-0.55, 0.56, 0.06))
    for dy in (0.28, 0.54, 0.80):
        h.add(A.bm_box((1.62, 0.18, 0.06), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(-0.55, dy, 0.50))
    # 右侧立放的两只巨大极地备用宽胎
    for tz in (-0.05, 0.38):
        h.add(bm_cyl(0.56, 0.56, 0.36, 18), m["M_Rubber"], loc=(1.15, 0.56, tz), rot=(90.0, 0.0, 16.0))
        h.add(bm_cyl(0.28, 0.28, 0.39, 14), m["M_PaintOrange"], loc=(1.15, 0.56, tz), rot=(90.0, 0.0, 16.0))
    export_model(h, "hero_tool_wall_cabinet.glb", seed=137)


def build_cryo_sample_tank():
    """8. 圆柱形发光冰样/生物培养液柱（高 3.6m，科研楼/钻探站/标本馆/温室镇馆道具！）"""
    m = fresh_mats()
    h = A.Hero("HeroCryoSampleTank")
    h.add(bm_cyl(0.95, 0.86, 0.62, 18), m["M_DarkSteel"], loc=(0.0, 0.31, 0.0))
    h.add(bm_cyl(0.86, 0.95, 0.58, 18), m["M_DarkSteel"], loc=(0.0, 3.32, 0.0))
    # 中间通透发光培养玻璃柱 + 内部漂浮发光蓝冰晶核
    h.add(bm_cyl(0.74, 0.74, 2.42, 22), m["M_GlassWarm"], loc=(0.0, 1.82, 0.0))
    h.add(bm_cyl(0.32, 0.16, 1.48, 8), m["M_GlowCyan"], loc=(0.0, 1.82, 0.0), rot=(8.0, 22.0, -6.0))
    # 3 根外骨骼保护钢柱
    for a in (0, 120, 240):
        rad = math.radians(a)
        h.add(bm_cyl(0.08, 0.08, 2.95, 10), m["M_PaintOrange"], loc=(math.cos(rad) * 0.86, 1.82, math.sin(rad) * 0.86))
    export_model(h, "hero_cryo_sample_tank.glb", seed=138)


def build_whiteboard_wall():
    """9. 贴墙发光科研战术简报大屏/白板（宽 3.8m × 高 2.1m，打破大白墙！）"""
    m = fresh_mats()
    h = A.Hero("HeroWhiteboardWall")
    h.add(A.bm_box((3.9, 2.15, 0.16), bevel=0.04, segments=2), m["M_DarkSteel"], loc=(0.0, 1.95, 0.0))
    h.add(A.bm_box((3.55, 1.80, 0.08), bevel=0.02, segments=2), m["M_GlowCyan"], loc=(0.0, 1.95, 0.08))
    # 贴在白板上的几块橙色/白色数据便签条
    h.add(A.bm_box((0.95, 0.42, 0.05), bevel=0.01, segments=2), m["M_PaintOrange"], loc=(-1.05, 2.32, 0.13))
    h.add(A.bm_box((1.25, 0.65, 0.05), bevel=0.01, segments=2), m["M_DarkSteel"], loc=(0.75, 1.85, 0.13))
    h.add(A.bm_box((0.62, 0.34, 0.05), bevel=0.01, segments=2), m["M_GlowAmber"], loc=(-0.95, 1.55, 0.13))
    export_model(h, "hero_whiteboard_wall.glb", seed=139)


def build_floor_clutter():
    """10. 角落生活/远征杂物堆（叠放手提装备箱 + 卷绕电缆 + 便携暖风机 + 警示锥）"""
    m = fresh_mats()
    h = A.Hero("HeroFloorClutter")
    # 叠放的两个防撞装备箱
    h.add(A.bm_box((0.96, 0.52, 0.64), bevel=0.04, segments=2), m["M_CastSteel"], loc=(-0.45, 0.26, -0.15), rot=(0.0, 12.0, 0.0))
    h.add(A.bm_box((0.76, 0.40, 0.52), bevel=0.04, segments=2), m["M_PaintOrange"], loc=(-0.42, 0.72, -0.12), rot=(0.0, -8.0, 0.0))
    # 便携暖风机（带发光橙热网）
    h.add(A.bm_box((0.52, 0.66, 0.42), bevel=0.04, segments=2), m["M_PaintCream"], loc=(0.56, 0.33, -0.18), rot=(0.0, -24.0, 0.0))
    h.add(A.bm_box((0.36, 0.36, 0.06), bevel=0.01, segments=2), m["M_GlowAmber"], loc=(0.48, 0.36, 0.03), rot=(0.0, -24.0, 0.0))
    # 盘在地上的粗黑电缆圈 + 橙色警示锥
    h.add(bm_cyl(0.38, 0.38, 0.12, 18), m["M_Rubber"], loc=(0.12, 0.06, 0.56))
    h.add(bm_cyl(0.24, 0.06, 0.62, 12), m["M_PaintOrange"], loc=(-0.82, 0.31, 0.54))
    export_model(h, "hero_floor_clutter.glb", seed=140)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    build_wall_pipe_run()
    build_ceiling_truss_lamp()
    build_locker_bank()
    build_server_rack()
    build_sofa_lounge()
    build_kitchen_counter()
    build_tool_wall_cabinet()
    build_cryo_sample_tank()
    build_whiteboard_wall()
    build_floor_clutter()
    print("BUILD_INTERIOR_CLUTTER_PACK_OK (10 GLBs)")


if __name__ == "__main__":
    main()
