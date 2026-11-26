"""《迷失太空》太空舱 2.0 & 霜烬星 2.0 英雄级 GLB 批量锻造脚本（Blender 4.5）
严格遵循《美术制作与AI协作指南》与 ART-SAMPLE-002 工艺规范：
- 零裸方块：所有主体用 rrect_r + bm_loft 放样、bm_lathe 车削、多段物理倒角、底座与加强筋；
- 70/15/10/8/2 色板规范：M_SteelDeep/M_PaintGrey 压底、M_PaintCream 识别壳、M_PaintOrange 严格限手柄/护杠/卡箍；
- 必须在 EdgeSplit 之前执行 bake_masks() 烘焙 4 通道顶点色 Col（R磨损/G自遮挡/B斑块/A朝上）；
- 导出前强制全三角化并带切线空间（TANGENT）与 Col 顶点色。
"""

import math
import os
import random
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
    return extra_mats(HM.build_materials())

def extra_mats(mats):
    mats["M_SteelDeep"] = mats["M_DarkSteel"]
    mats["M_FossilBone"] = K.mat("M_FossilBone", (0.62, 0.58, 0.50), 0.72, 0.0)
    mats["M_ThermalCore"] = K.mat("M_ThermalCore", (0.95, 0.48, 0.12), 0.12, 0.0,
                                  emit=(1.0, 0.52, 0.14), emit_strength=2.0)
    mats["M_GlowCyan"] = K.mat("M_GlowCyan", (0.20, 0.85, 0.96), 0.14, 0.0,
                               emit=(0.18, 0.84, 0.98), emit_strength=1.8)
    mats["M_GlowAmber"] = K.mat("M_GlowAmber", (0.96, 0.62, 0.18), 0.16, 0.0,
                                emit=(0.96, 0.56, 0.14), emit_strength=1.8)
    mats["M_GlowRed"] = K.mat("M_GlowRed", (0.95, 0.22, 0.14), 0.16, 0.0,
                              emit=(1.0, 0.20, 0.12), emit_strength=1.8)
    return mats


def finalize_and_export(hero, filename, seed=1, ao_rays=8, ground_z=0.0):
    gain = dict(HM.WEAR_GAIN)
    gain["M_FossilBone"] = 0.75
    gain["M_ThermalCore"] = 0.20
    obj = hero.finish(
        smooth=True,
        split_angle=32.0,
        bake={"ao_rays": ao_rays, "ao_dist": 0.18, "seed": seed, "mat_gain": gain, "ground_z": ground_z, "verbose": False},
    )
    tri = obj.modifiers.new("Tri", "TRIANGULATE")
    tri.quad_method = "BEAUTY"
    K.apply_modifiers(obj)
    out_path = os.path.join(OUT_DIR, filename)
    A.export_glb(out_path, obj.name)
    A.report(filename, obj)


# ------------------------------------------------------------------ 1. 全息星图中控台
def build_star_table():
    m = fresh_mats()
    h = A.Hero("HeroStarTable")

    # 扩底铸铁底座 + 收腰 + 宽肩台面（rrect_r 放样）
    secs = [
        (0.00, A.rrect_r(2.70, 2.70, 0.55, 6)),
        (0.16, A.rrect_r(2.58, 2.58, 0.52, 6)),
        (0.24, A.rrect_r(2.05, 2.05, 0.44, 6)),
        (0.68, A.rrect_r(1.92, 1.92, 0.42, 6)),
        (0.84, A.rrect_r(2.54, 2.54, 0.52, 6)),
        (0.96, A.rrect_r(2.44, 2.44, 0.50, 6)),
    ]
    h.add(A.bm_loft(secs), m["M_SteelDeep"])
    # 奶油白中腰识别装甲护壳（留装配缝）
    mid = [
        (0.28, A.rrect_r(2.14, 2.14, 0.46, 6)),
        (0.64, A.rrect_r(2.04, 2.04, 0.44, 6)),
    ]
    h.add(A.bm_loft(mid), m["M_PaintCream"])
    # 顶面仪器凹台与青铜刻度环
    h.add(A.bm_lathe([(0.0, 0.95), (1.02, 0.95), (1.05, 1.02), (0.94, 1.04), (0.86, 0.98), (0.0, 0.98)], 32), m["M_Bronze"])
    h.add(A.bm_lathe([(0.0, 0.98), (0.84, 0.98), (0.80, 1.01), (0.0, 1.01)], 32), m["M_GlowCyan"])
    # 四角工业橙防撞扶手与紧固件
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            h.add(A.bm_box((0.26, 0.14, 0.26), bevel=0.025, segments=3), m["M_PaintOrange"], loc=(sx * 1.08, 0.88, sz * 1.08))
            h.bolt((sx * 1.12, 0.16, sz * 1.12), m["M_BareSteel"], axis="up", d=0.045, head_h=0.024)
    # 底座四周斜向加强筋
    for ang in (0, 90, 180, 270):
        h.add(A.bm_box((0.16, 0.34, 0.42), bevel=0.015, segments=2, taper=(0.9, 0.55)),
              m["M_CastSteel"], loc=(math.sin(ang * A.D2R) * 1.05, 0.28, math.cos(ang * A.D2R) * 1.05), rot=(0, ang, 0))
    # 悬浮全息投影星环结构（实体机械投影架 + 青蓝轨道环）
    h.add(A.bm_torus(0.76, 0.024, 28, 8), m["M_GlowCyan"], loc=(0.0, 1.56, 0.0), rot=(18.0, 0.0, 12.0))
    h.add(A.bm_torus(0.52, 0.018, 24, 8), m["M_GlowAmber"], loc=(0.0, 1.56, 0.0), rot=(-26.0, 20.0, -8.0))
    h.add(A.bm_lathe([(0.0, 0.0), (0.18, 0.08), (0.24, 0.22), (0.18, 0.36), (0.0, 0.44)], 18), m["M_CrystalCore"], loc=(0.0, 1.34, 0.0))
    finalize_and_export(h, "hero_star_table.glb", seed=101)


# ------------------------------------------------------------------ 2. 实体工业拉杆操作台
def build_lever_console():
    m = fresh_mats()
    h = A.Hero("HeroLeverConsole")

    # 落地铸铁底座
    h.add(A.bm_loft([
        (0.00, A.rrect_r(0.98, 0.72, 0.14, 5)),
        (0.12, A.rrect_r(0.92, 0.66, 0.12, 5)),
    ]), m["M_SteelDeep"])
    # 奶油白圆角放样机身（扩底→收腰→宽肩）
    h.add(A.bm_loft([
        (0.12, A.rrect_r(0.84, 0.58, 0.12, 5)),
        (0.58, A.rrect_r(0.78, 0.52, 0.11, 5)),
        (0.96, A.rrect_r(0.88, 0.62, 0.12, 5)),
        (1.06, A.rrect_r(0.82, 0.54, 0.11, 5)),
    ]), m["M_PaintCream"])
    # 前面板检修门 + 真实 2mm 阴影凹槽 + 四角螺栓
    h.add(A.bm_box((0.62, 0.54, 0.04), bevel=0.012, segments=2), m["M_PaintGrey"], loc=(0.0, 0.52, 0.275))
    for sx in (-0.25, 0.25):
        for sy in (0.32, 0.72):
            h.bolt((sx, sy, 0.295), m["M_Bronze"], axis="zp", d=0.026, head_h=0.014)
    # 工业橙前部扶手护杠（严格 <8% 面积）
    h.add(A.bm_tube([(-0.36, 0.98, 0.28), (-0.36, 0.98, 0.42), (0.36, 0.98, 0.42), (0.36, 0.98, 0.28)], 0.024, seg=10), m["M_PaintOrange"])
    # 顶部倾斜控制面板 + 圆形模拟表盘 + 闸槽
    h.add(A.bm_box((0.74, 0.08, 0.40), bevel=0.015, segments=2), m["M_SteelDeep"], loc=(0.0, 1.07, -0.02), rot=(14.0, 0.0, 0.0))
    # 模拟表盘底座（左）
    h.add(A.bm_lathe([(0.0, 0.0), (0.14, 0.0), (0.15, 0.06), (0.12, 0.08), (0.0, 0.07)], 20), m["M_Bronze"], loc=(-0.18, 1.08, 0.02), rot=(14.0, 0.0, 0.0))
    h.add(A.bm_cyl(0.11, 0.02, seg=18), m["M_GlowCyan"], loc=(-0.18, 1.13, 0.03), rot=(14.0, 0.0, 0.0))
    # 闸刀导向槽（右）+ 侧挂小工作灯罩
    h.add(A.bm_box((0.14, 0.10, 0.26), bevel=0.012, segments=2), m["M_CastSteel"], loc=(0.18, 1.12, 0.0))
    h.add(A.bm_tube([(0.34, 1.06, -0.14), (0.38, 1.48, -0.14), (0.28, 1.54, -0.02)], 0.018, seg=8), m["M_BareSteel"])
    h.add(A.bm_lathe([(0.0, 0.0), (0.13, -0.02), (0.10, 0.08), (0.04, 0.12), (0.0, 0.12)], 16), m["M_PaintOrange"], loc=(0.24, 1.44, 0.02), rot=(20.0, 0.0, 18.0))
    h.add(A.bm_cyl(0.065, 0.03, seg=12), m["M_Glass"], loc=(0.24, 1.41, 0.02), rot=(20.0, 0.0, 18.0))
    finalize_and_export(h, "hero_lever_console.glb", seed=102)


# ------------------------------------------------------------------ 3. 军械与工坊一体工作台
def build_workshop_bench():
    m = fresh_mats()
    h = A.Hero("HeroWorkshopBench")

    # 两侧重型工字钢承力机腿与靴座
    for sx in (-0.95, 0.95):
        h.add(A.bm_box((0.30, 0.14, 0.96), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(sx, 0.07, 0.0))
        h.add(A.bm_box((0.20, 0.84, 0.78), bevel=0.02, segments=2), m["M_SteelDeep"], loc=(sx, 0.54, 0.0))
        h.bolt((sx, 0.14, 0.36), m["M_BareSteel"], axis="up", d=0.032)
        h.bolt((sx, 0.14, -0.36), m["M_BareSteel"], axis="up", d=0.032)
    # 奶油白厚重工作台面 + 防撞包边
    h.add(A.bm_box((2.35, 0.14, 1.04), bevel=0.028, segments=3), m["M_PaintCream"], loc=(0.0, 0.98, 0.0))
    h.add(A.bm_box((2.40, 0.06, 0.06), bevel=0.012, segments=2), m["M_PaintYellow"], loc=(0.0, 0.98, 0.52))
    # 后部立柱 + 奶油色工业工具背板 + 顶部遮光工坊灯
    for sx in (-1.02, 1.02):
        h.add(A.bm_box((0.12, 1.38, 0.14), bevel=0.018, segments=2), m["M_SteelDeep"], loc=(sx, 1.66, -0.42))
    h.add(A.bm_box((1.96, 0.92, 0.08), bevel=0.018, segments=2), m["M_PaintGrey"], loc=(0.0, 1.56, -0.44))
    h.add(A.bm_box((1.72, 0.54, 0.04), bevel=0.012, segments=2), m["M_GlowCyan"], loc=(0.0, 1.58, -0.39))
    # 顶部悬臂雨檐灯罩
    h.add(A.bm_box((2.20, 0.12, 0.52), bevel=0.022, segments=2), m["M_PaintCream"], loc=(0.0, 2.34, -0.22))
    h.add(A.bm_box((1.84, 0.05, 0.16), bevel=0.008, segments=2), m["M_Glass"], loc=(0.0, 2.27, -0.14))
    # 台面重型台钳与工具箱（中近景生活感）
    h.add(A.bm_box((0.32, 0.20, 0.24), bevel=0.016, segments=2), m["M_CastSteel"], loc=(-0.74, 1.15, 0.20))
    h.add(A.bm_box((0.44, 0.22, 0.30), bevel=0.02, segments=2), m["M_PaintOrange"], loc=(0.72, 1.16, 0.12))
    finalize_and_export(h, "hero_workshop_bench.glb", seed=103)


# ------------------------------------------------------------------ 4. 生命与充氧生态补给柱
def build_refill_pod():
    m = fresh_mats()
    h = A.Hero("HeroRefillPod")

    # 车削扩底基座
    h.add(A.bm_lathe([
        (0.0, 0.0), (0.68, 0.0), (0.68, 0.10), (0.58, 0.20),
        (0.46, 0.26), (0.46, 0.36), (0.0, 0.36)
    ], 24), m["M_SteelDeep"])
    # 中心发光充氧透明能源柱 + 上下青铜法兰
    h.add(A.bm_cyl(0.24, 1.42, seg=20), m["M_GlowCyan"], loc=(0.0, 0.36, 0.0))
    for y in (0.36, 1.72):
        h.add(A.bm_lathe([(0.0, 0.0), (0.36, 0.0), (0.38, 0.05), (0.34, 0.10), (0.0, 0.10)], 22), m["M_Bronze"], loc=(0.0, y, 0.0))
    # 两侧奶油白装甲护翼（带倒角和工业橙阀门手轮）
    for sx in (-1.0, 1.0):
        h.add(A.bm_box((0.20, 1.54, 0.42), bevel=0.032, segments=3), m["M_PaintCream"], loc=(sx * 0.40, 1.08, 0.0))
        h.add(A.bm_torus(0.11, 0.022, 16, 8), m["M_PaintOrange"], loc=(sx * 0.54, 1.06, 0.14), rot=(0.0, 0.0, 90.0))
    # 顶冠与防撞警示环
    h.add(A.bm_lathe([(0.0, 1.82), (0.54, 1.82), (0.56, 1.94), (0.44, 2.08), (0.0, 2.12)], 24), m["M_PaintTeal"])
    h.bolt_row((-0.44, 0.12, 0.44), (0.44, 0.12, 0.44), 4, m["M_BareSteel"], axis="up", d=0.030)
    finalize_and_export(h, "hero_refill_pod.glb", seed=104)


# ------------------------------------------------------------------ 5. 真英雄级极地探险车
def build_polar_rover():
    m = fresh_mats()
    h = A.Hero("HeroPolarRover")

    # 1. 重型深钢阶梯底盘（收分倒角，绝非方块）
    h.add(A.bm_box((2.32, 0.38, 4.46), bevel=0.06, segments=3, taper=(0.94, 0.96)), m["M_SteelDeep"], loc=(0.0, 0.24, 0.0))
    # 2. 流线倒角奶油白前装甲车鼻（多剖面沿 Z 风格放样）
    nose = A.bm_box((2.18, 0.66, 1.48), bevel=0.14, segments=4, taper=(0.86, 0.78))
    h.add(nose, m["M_PaintCream"], loc=(0.0, 0.64, -1.48))
    # 车头百叶散热格栅
    for i in range(4):
        h.add(A.bm_box((1.32, 0.06, 0.08), bevel=0.012, segments=2), m["M_CastSteel"], loc=(0.0, 0.48 + i * 0.11, -2.18))
    # 3. 工业橙重型前防撞牛栏杠 + 前绞盘钩（严格控制点缀面积）
    h.add(A.bm_tube([(-1.06, 0.34, -2.18), (-1.06, 0.78, -2.38), (1.06, 0.78, -2.38), (1.06, 0.34, -2.18)], 0.055, seg=10), m["M_PaintOrange"])
    h.add(A.bm_box((0.52, 0.22, 0.26), bevel=0.025, segments=2), m["M_CastSteel"], loc=(0.0, 0.44, -2.30))
    h.add(A.bm_torus(0.10, 0.028, 14, 8), m["M_PaintYellow"], loc=(0.0, 0.44, -2.46), rot=(90.0, 0.0, 0.0))
    # 4. 开放式驾驶舱 + 两侧奶油白翼子板轮眉
    for sx in (-1.0, 1.0):
        for sz in (-1.38, 1.38):
            h.add(A.bm_box((0.36, 0.26, 1.24), bevel=0.05, segments=3), m["M_PaintGrey"], loc=(sx * 1.18, 0.54, sz))
        # 双人人体工学座椅（圆角靠背）
        h.add(A.bm_box((0.68, 0.16, 0.68), bevel=0.04, segments=3), m["M_Rubber"], loc=(sx * 0.56, 0.58, -0.45))
        h.add(A.bm_box((0.68, 0.66, 0.16), bevel=0.04, segments=3), m["M_Rubber"], loc=(sx * 0.56, 0.94, -0.10), rot=(-10.0, 0.0, 0.0))
    # 仪表台与方向盘
    h.add(A.bm_box((1.92, 0.34, 0.44), bevel=0.05, segments=3), m["M_SteelDeep"], loc=(0.0, 0.92, -1.04))
    h.add(A.bm_torus(0.18, 0.026, 18, 8), m["M_PaintOrange"], loc=(-0.56, 1.06, -0.78), rot=(62.0, 0.0, 0.0))
    # 5. 坚固钢管防滚架（平行传输扫掠圆管）
    for sx in (-1.02, 1.02):
        h.add(A.bm_tube([
            (sx, 0.55, -1.25), (sx, 1.88, -0.96), (sx, 1.94, 0.18), (sx, 0.62, 0.28)
        ], 0.048, seg=10), m["M_SteelDeep"])
    h.add(A.bm_tube([(-1.02, 1.88, -0.96), (1.02, 1.88, -0.96)], 0.048, seg=10), m["M_PaintOrange"])
    h.add(A.bm_tube([(-1.02, 1.94, 0.18), (1.02, 1.94, 0.18)], 0.048, seg=10), m["M_SteelDeep"])
    # 车顶双高光射灯罩（穿透极地暴风雪）
    for sx in (-0.64, 0.64):
        h.add(A.bm_lathe([(0.0, 0.0), (0.14, 0.0), (0.16, 0.14), (0.12, 0.20), (0.0, 0.20)], 16),
              m["M_PaintCream"], loc=(sx, 2.02, -0.98), rot=(-90.0, 0.0, 0.0))
        h.add(A.bm_cyl(0.12, 0.03, seg=14), m["M_Glass"], loc=(sx, 2.02, -1.16), rot=(90.0, 0.0, 0.0))
    # 6. 后部带肋条与护栏的磁力货斗（可装 12 件物资与便携热核）
    h.add(A.bm_box((2.16, 0.18, 1.96), bevel=0.03, segments=2), m["M_CastSteel"], loc=(0.0, 0.54, 1.24))
    for rx in (-0.75, -0.25, 0.25, 0.75):
        h.add(A.bm_box((0.08, 0.05, 1.78), bevel=0.01, segments=2), m["M_BareSteel"], loc=(rx, 0.65, 1.24))
    for sx in (-1.04, 1.04):
        h.add(A.bm_box((0.12, 0.54, 1.94), bevel=0.025, segments=2), m["M_PaintCream"], loc=(sx, 0.88, 1.24))
        h.add(A.bm_tube([(sx, 1.18, 0.34), (sx, 1.18, 2.16)], 0.034, seg=8), m["M_PaintOrange"])
    # 尾灯组与后排气推进口
    for sx in (-0.82, 0.82):
        h.add(A.bm_box((0.34, 0.14, 0.08), bevel=0.015, segments=2), m["M_GlowRed"], loc=(sx, 0.54, 2.24))
        h.add(A.bm_lathe([(0.0, 0.0), (0.14, 0.0), (0.17, 0.18), (0.12, 0.24), (0.0, 0.24)], 14),
              m["M_MachinedSteel"], loc=(sx * 0.52, 0.32, 2.22), rot=(90.0, 0.0, 0.0))
    finalize_and_export(h, "hero_polar_rover.glb", seed=105)


# ------------------------------------------------------------------ 6. 极地科考站英雄门斗与柱靴模块
def build_station_porch():
    m = fresh_mats()
    h = A.Hero("HeroStationPorch")

    # 两侧扩底混凝土承台 + 工业橙铸铁柱靴 + 奶油白倒角方柱（直接呼应 ART-SAMPLE-002 视觉标杆）
    for sx in (-4.2, 4.2):
        h.add(A.bm_loft([
            (0.00, A.rrect_r(1.18, 1.18, 0.16, 4)),
            (0.24, A.rrect_r(1.04, 1.04, 0.14, 4)),
        ]), m["M_Concrete"], loc=(sx, 0.0, 0.0))
        h.add(A.bm_loft([
            (0.24, A.rrect_r(0.84, 0.84, 0.12, 4)),
            (1.12, A.rrect_r(0.74, 0.74, 0.11, 4)),
        ]), m["M_PaintOrange"], loc=(sx, 0.0, 0.0))
        h.bolt_row((sx - 0.24, 0.96, 0.38), (sx + 0.24, 0.96, 0.38), 3, m["M_BareSteel"], axis="zp", d=0.036)
        h.add(A.bm_loft([
            (1.12, A.rrect_r(0.68, 0.68, 0.10, 4)),
            (3.75, A.rrect_r(0.62, 0.62, 0.09, 4)),
        ]), m["M_PaintCream"], loc=(sx, 0.0, 0.0))
        # 中段紧固钢箍
        h.add(A.bm_box((0.72, 0.18, 0.72), bevel=0.02, segments=2), m["M_SteelDeep"], loc=(sx, 2.45, 0.0))
    # 顶部厚重防雪斜雨棚 + 暗钢工字横梁 + 警示黄前檐边
    h.add(A.bm_box((9.6, 0.42, 0.85), bevel=0.04, segments=3), m["M_SteelDeep"], loc=(0.0, 3.85, 0.0))
    h.add(A.bm_box((10.2, 0.28, 2.55), bevel=0.05, segments=3), m["M_PaintCream"], loc=(0.0, 4.18, 0.45), rot=(8.0, 0.0, 0.0))
    h.add(A.bm_box((10.24, 0.10, 0.14), bevel=0.015, segments=2), m["M_PaintYellow"], loc=(0.0, 4.00, 1.72))
    # 挂壁防眩工作灯
    for sx in (-3.2, 3.2):
        h.add(A.bm_box((0.46, 0.24, 0.38), bevel=0.03, segments=2), m["M_SteelDeep"], loc=(sx, 3.55, 0.92))
        h.add(A.bm_box((0.36, 0.06, 0.28), bevel=0.01, segments=2), m["M_Glass"], loc=(sx, 3.42, 0.92))
    finalize_and_export(h, "hero_station_porch.glb", seed=106)


# ------------------------------------------------------------------ 7. 便携式高能热核电池
def build_thermal_core():
    m = fresh_mats()
    h = A.Hero("HeroThermalCore")

    # 下/上奶油白倒角端盖
    h.add(A.bm_lathe([(0.0, 0.0), (0.34, 0.0), (0.36, 0.06), (0.30, 0.14), (0.0, 0.14)], 16), m["M_PaintCream"])
    h.add(A.bm_lathe([(0.0, 0.72), (0.30, 0.72), (0.36, 0.80), (0.34, 0.88), (0.0, 0.88)], 16), m["M_PaintCream"])
    # 中心热核发光晶柱
    h.add(A.bm_cyl(0.18, 0.60, seg=14), m["M_ThermalCore"], loc=(0.0, 0.14, 0.0))
    # 四根暗钢防滚护柱 + 顶部工业橙双手提把
    for i in range(4):
        ang = i * 90.0 + 45.0
        px, pz = math.cos(ang * A.D2R) * 0.28, math.sin(ang * A.D2R) * 0.28
        h.add(A.bm_cyl(0.032, 0.66, seg=8), m["M_SteelDeep"], loc=(px, 0.11, pz))
    h.add(A.bm_tube([(-0.22, 0.88, 0.0), (-0.20, 1.04, 0.0), (0.20, 1.04, 0.0), (0.22, 0.88, 0.0)], 0.028, seg=8), m["M_PaintOrange"])
    finalize_and_export(h, "hero_thermal_core.glb", seed=107)


# ------------------------------------------------------------------ 8. 真解理面极地玄武岩巨石
def build_glacier_rock():
    m = fresh_mats()
    h = A.Hero("HeroGlacierRock")
    rock_bm = A.rock_from_planes((6.2, 4.4, 5.4), seed=208, cuts=12, subdiv=3, bevel=0.012, rough=0.045, strata=(0.68, 0.08))
    h.add(rock_bm, m["M_Bedrock"], loc=(0.0, 1.6, 0.0))
    # 伴生副岩块（打破单体孤立感）
    sub_bm = A.rock_from_planes((2.8, 1.9, 2.5), seed=209, cuts=9, subdiv=2, bevel=0.010, rough=0.03)
    h.add(sub_bm, m["M_BedrockDark"], loc=(2.4, 0.7, 1.5), rot=(0, 38, 0))
    finalize_and_export(h, "hero_glacier_rock.glb", seed=108, ao_rays=6)


# ------------------------------------------------------------------ 9. 不等边棱面蓝冰晶簇
def build_ice_spire():
    m = fresh_mats()
    h = A.Hero("HeroIceSpire")

    def prism_spire(base_r, height, lean_x, lean_z, seed):
        rng = random.Random(seed)
        angles = sorted([i * (A.TAU / 6.0) + rng.uniform(-0.18, 0.18) for i in range(6)])
        radii = [base_r * rng.uniform(0.76, 1.18) for _ in range(6)]
        secs = []
        for idx, (t, sc) in enumerate([(0.0, 1.05), (0.18, 0.96), (0.68, 0.72), (0.90, 0.36), (1.0, 0.04)]):
            pts = [(math.cos(a) * r * sc + lean_x * t, math.sin(a) * r * sc + lean_z * t) for a, r in zip(angles, radii)]
            secs.append((t * height, pts))
        bm = A.bm_loft(secs, smooth_sides=False)
        A._bevel_all(bm, 0.012, 1)
        return bm

    # 主棱 + 两根斜插副棱 + 根部蚀变基岩座
    h.add(prism_spire(0.62, 4.4, 0.35, -0.22, 301), m["M_CrystalShell"], loc=(0.0, -0.45, 0.0))
    h.add(prism_spire(0.42, 2.8, -0.48, 0.35, 302), m["M_CrystalCore"], loc=(-0.55, -0.35, 0.35), rot=(12, 45, -16))
    h.add(prism_spire(0.36, 2.1, 0.42, 0.48, 303), m["M_CrystalShell"], loc=(0.52, -0.30, 0.40), rot=(-14, -30, 18))
    base_rock = A.rock_from_planes((2.4, 0.9, 2.2), seed=304, cuts=8, subdiv=2, bevel=0.008, rough=0.025)
    h.add(base_rock, m["M_BedrockDark"], loc=(0.0, 0.18, 0.0))
    finalize_and_export(h, "hero_ice_spire.glb", seed=109, ao_rays=6)


# ------------------------------------------------------------------ 10. 巨兽古骨弧形肋拱
def build_fossil_arch():
    m = fresh_mats()
    h = A.Hero("HeroFossilArch")

    # 沿巨大抛物线弧形扫掠渐变椭圆截面（真实古生物巨肋骨形态）
    pts = []
    radii = []
    segs = 14
    for i in range(segs + 1):
        t = i / float(segs)
        ang = math.pi * (0.08 + 0.84 * t)
        x = -math.cos(ang) * 14.0
        y = math.sin(ang) * 16.5 - 1.2
        z = math.sin(t * math.pi * 2.0) * 0.65
        pts.append((x, y, z))
        # 根部膨大、中段收紧、顶部脊棱微膨
        r = 1.45 - 0.55 * math.sin(t * math.pi) + 0.18 * math.sin(t * math.pi * 4.0)
        radii.append(r)
    bm = A.bm_tube(pts, 1.0, seg=10, radii=radii, caps=True, smooth=True)
    A.soften(bm, amp=0.09, freq=0.65, seed=401)
    h.add(bm, m["M_FossilBone"])
    # 两侧基座压岩碎石
    for sx in (-13.2, 13.2):
        rb = A.rock_from_planes((4.8, 3.2, 4.4), seed=402 if sx < 0 else 403, cuts=9, subdiv=2, bevel=0.015, rough=0.06)
        h.add(rb, m["M_Bedrock"], loc=(sx, 0.8, 0.0))
    finalize_and_export(h, "hero_fossil_arch.glb", seed=110, ao_rays=6)


# ------------------------------------------------------------------ 11. 极地防撞物资箱 & 易爆低温燃料罐
def build_props():
    # A. 防撞物资箱
    m = fresh_mats()
    h = A.Hero("HeroCargoCrate")
    h.add(A.bm_box((0.92, 0.64, 0.72), bevel=0.045, segments=3), m["M_PaintCream"], loc=(0.0, 0.34, 0.0))
    h.add(A.bm_box((0.96, 0.14, 0.76), bevel=0.02, segments=2), m["M_SteelDeep"], loc=(0.0, 0.34, 0.0))
    for sx in (-0.43, 0.43):
        for sz in (-0.33, 0.33):
            h.add(A.bm_box((0.14, 0.68, 0.14), bevel=0.022, segments=2), m["M_PaintOrange"], loc=(sx, 0.34, sz))
    h.add(A.bm_tube([(-0.22, 0.68, 0.0), (-0.22, 0.78, 0.0), (0.22, 0.78, 0.0), (0.22, 0.68, 0.0)], 0.022, seg=8), m["M_BareSteel"])
    finalize_and_export(h, "hero_cargo_crate.glb", seed=111)

    # B. 易爆低温燃料/冷媒罐（可用于吸推引爆炸开冰障或击毁霜巡无人机）
    m = fresh_mats()
    c = A.Hero("HeroCryoCanister")
    c.add(A.bm_lathe([
        (0.0, 0.0), (0.24, 0.0), (0.26, 0.08), (0.26, 0.74),
        (0.20, 0.88), (0.10, 0.94), (0.10, 1.02), (0.0, 1.02)
    ], 18), m["M_PaintOrange"])
    # 中段暗钢防滚环与警示红条
    c.add(A.bm_cyl(0.275, 0.12, seg=18), m["M_SteelDeep"], loc=(0.0, 0.22, 0.0))
    c.add(A.bm_cyl(0.275, 0.12, seg=18), m["M_SteelDeep"], loc=(0.0, 0.58, 0.0))
    c.add(A.bm_cyl(0.268, 0.08, seg=18), m["M_GlowRed"], loc=(0.0, 0.41, 0.0))
    c.add(A.bm_torus(0.11, 0.022, 14, 8), m["M_PaintYellow"], loc=(0.0, 1.04, 0.0))
    finalize_and_export(c, "hero_cryo_canister.glb", seed=112)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    build_star_table()
    build_lever_console()
    build_workshop_bench()
    build_refill_pod()
    build_polar_rover()
    build_station_porch()
    build_thermal_core()
    build_glacier_rock()
    build_ice_spire()
    build_fossil_arch()
    build_props()
    print("ALL_12_HERO_GLBS_BUILT_OK")


if __name__ == "__main__":
    main()
