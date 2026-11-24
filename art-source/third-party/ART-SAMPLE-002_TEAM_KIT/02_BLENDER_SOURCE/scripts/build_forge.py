"""ART-QUALITY-002-NATURAL · 敲钟机（共振锻造台）

这一版不是"在原机器外面套一层壳"，而是按整机产品重新设计：

  受力路径：岩石基座 → 铸铁底盘 → 锥形立柱 → 横梁 → 铸造吊架 → 轴承座 → 轴
            → 摆臂 → 锤头 → 砧座 → 岩石基座
  动力路径：曳引轮 → 转向滑轮 → 拉索 → 锤头吊环
  附属系统：液压蓄能器 → 管路 → 轴承润滑；操作台 → 电缆 → 地沟

输出（挂载点见 tests/aq002_env.gd）：
  aq002_forge_static.glb  地基/立柱/横梁/轴承/砧座/管线/操作台（挂在 HammerRig 原点）
  aq002_forge_swing.glb   摆臂+锤头（挂在 PendulumPivot 原点，跟随原摆动）
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aq2kit as K
from aq2kit import Part, D2R

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "project", "assets", "models", "aq002")

PIVOT_Y = 4.30
ARM = 3.50
BEAM_Y = 5.42
LEG_X = 1.22
ANVIL_Z = -1.74
CX, CZ = 2.12, 1.30          # 操作台（必须贴近原交互点 2.25 / 1.45）


def rrect(w, d, c):
    """带切角的矩形截面（8 点）。c 越大越接近八边形。"""
    return [
        (w * 0.5 - c, -d * 0.5),
        (w * 0.5, -d * 0.5 + c),
        (w * 0.5, d * 0.5 - c),
        (w * 0.5 - c, d * 0.5),
        (-w * 0.5 + c, d * 0.5),
        (-w * 0.5, d * 0.5 - c),
        (-w * 0.5, -d * 0.5 + c),
        (-w * 0.5 + c, -d * 0.5),
    ]


def circle_pts(r, n=24, phase=0.0):
    return [(r * math.cos(phase + K.TAU * i / n), r * math.sin(phase + K.TAU * i / n)) for i in range(n)]


def scale_pts(pts, s):
    return [(p[0] * s, p[1] * s) for p in pts]


def build_static():
    cream = K.mat("M_PaintCream", (0.78, 0.745, 0.655), 0.5, 0.18)
    orange = K.mat("M_PaintOrange", (0.72, 0.30, 0.08), 0.52, 0.15)
    yellow = K.mat("M_PaintYellow", (0.82, 0.60, 0.12), 0.5, 0.12)
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.55, 0.45)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)
    found = K.mat("M_Foundation", (0.33, 0.34, 0.35), 0.72, 0.30)
    worn = K.mat("M_WornSteel", (0.47, 0.455, 0.425), 0.4, 0.5)
    bronze = K.mat("M_Bronze", (0.56, 0.40, 0.165), 0.36, 0.5)
    rubber = K.mat("M_Rubber", (0.05, 0.052, 0.056), 0.92, 0.0)

    p = Part("ForgeStatic")

    # ================================================================ 设备基础
    # 不是一块圆盘，而是一整块矩形设备基础：立柱、砧座、操作台都坐在这块
    # 承台上，所以"机器"和"砧座"是同一台设备，而不是台上台下的两件东西。
    #   岩台 → 混凝土垫层 → 铸铁承台面 → 地脚螺栓
    FND_CX, FND_CZ = 0.25, -0.20
    rock_f = [(-0.10, rrect(4.90, 4.40, 0.52)),
              (0.04, rrect(4.74, 4.24, 0.50))]
    p.loft(rock_f, m=deep, loc=(FND_CX, 0, FND_CZ))
    p.loft([(0.04, rrect(4.74, 4.24, 0.50)), (0.10, rrect(4.58, 4.08, 0.48)),
            (0.30, rrect(4.48, 3.98, 0.46)), (0.36, rrect(4.30, 3.80, 0.44))],
           m=deep, loc=(FND_CX, 0, FND_CZ))
    # 承台正面：两道内凹加强肋 + 一排地脚螺栓，避免出现一整块空白大板
    for rx in (-1.45, -0.48, 0.48, 1.45):
        p.box((0.24, 0.36, 0.13), (FND_CX + rx, 0.30, FND_CZ + 1.98), m=deep, bevel=0.014)
    for bx in (-1.75, -0.65, 0.65, 1.75):
        p.cyl(0.05, 0.05, (FND_CX + bx, 0.44, FND_CZ + 1.96), m=bronze, rot=(90.0, 0, 0), segments=6)
        p.cyl(0.05, 0.05, (FND_CX + bx, 0.20, FND_CZ + 1.96), m=bronze, rot=(90.0, 0, 0), segments=6)
    p.box((4.10, 0.05, 0.05), (FND_CX, 0.145, FND_CZ + 1.96), m=yellow, bevel=0.004)

    # 铸铁承台面（顶面与踏步同高，四角倒角）
    p.loft([(0.36, rrect(4.30, 3.80, 0.44)), (0.44, rrect(4.22, 3.70, 0.44)),
            (0.50, rrect(4.10, 3.60, 0.42))],
           m=found, loc=(FND_CX, 0, FND_CZ))
    # 地脚螺栓：沿四周 10 组
    bolt_spots = []
    for i in range(4):
        t = (i + 0.5) / 4.0
        bolt_spots.append((FND_CX - 1.90 + 3.80 * t, FND_CZ - 1.72))
        bolt_spots.append((FND_CX - 1.90 + 3.80 * t, FND_CZ + 1.72))
    for i in range(3):
        t = (i + 0.5) / 3.0
        bolt_spots.append((FND_CX - 1.96, FND_CZ - 1.05 + 2.10 * t))
        bolt_spots.append((FND_CX + 1.96, FND_CZ - 1.05 + 2.10 * t))
    for (bx, bz) in bolt_spots:
        p.cyl(0.075, 0.13, (bx, 0.56, bz), m=bronze, segments=8)
        p.cyl(0.135, 0.04, (bx, 0.505, bz), m=bare, segments=12)
    # 承台边缘的安全黄踢脚带（面向通道的三边）
    p.box((4.10, 0.06, 0.06), (FND_CX, 0.47, FND_CZ - 1.80), m=yellow, bevel=0.004)
    p.box((4.10, 0.06, 0.06), (FND_CX, 0.47, FND_CZ + 1.80), m=yellow, bevel=0.004)

    # ================================================================ 立柱
    for side in (-1, 1):
        x = side * LEG_X
        # 柱脚
        p.loft([(0.50, rrect(0.86, 0.78, 0.12)), (0.62, rrect(0.86, 0.78, 0.12))],
               m=deep, loc=(x, 0, 0))
        p.loft([(0.62, rrect(0.62, 0.56, 0.08)), (0.68, rrect(0.62, 0.56, 0.08))],
               m=bare, loc=(x, 0, 0))
        for bx, bz in ((-0.33, -0.29), (-0.33, 0.29), (0.33, -0.29), (0.33, 0.29)):
            p.cyl(0.045, 0.05, (x + bx, 0.705, bz), m=bronze, segments=8)
        # 锥形柱身：0.50x0.44 → 0.36x0.32
        # 柱身：不是一根等截面直筒。做成"柱脚加粗 → 双道加劲环 → 上段收细"的连续剖面，
        # 让轮廓有节奏，而不是一根被磨圆的方管。
        sections = []
        steps = 26
        for i in range(steps + 1):
            t = i / steps
            y = 0.68 + (BEAM_Y - 0.62 - 0.68) * t
            w = 0.50 - 0.14 * t
            d = 0.44 - 0.12 * t
            # 两道加劲环（分别在 32% 与 62% 高度），局部外扩 0.05
            ring = 0.0
            for rc in (0.32, 0.62):
                dt = abs(t - rc)
                if dt < 0.035:
                    ring = max(ring, 0.052 * (1.0 - dt / 0.035))
            # 柱脚 0–8% 外扩（承压放大）：**只加进深 ±z，不加宽度 ±x**。
            # 宽度直接决定与锤头的横向净空：立柱内侧面 |x| = 0.97 是 build_forge 的
            # 既有硬约束（锤头半宽 0.95）。第 43 回合加入外扩时把宽度也加了，
            # 实测把净空从 +20 mm 压到 −7.5 mm（tools/check_flare.py 可复算），
            # 因此改回"只加深"：柱脚前后面照样加厚，横向不再侵入锤头包络。
            flare = 0.055 * max(0.0, 1.0 - t / 0.08)
            w += ring
            d += ring * 0.85 + flare
            sections.append((y, rrect(w, d, 0.07 + 0.012 * t)))
        p.loft(sections, m=cream, loc=(x, 0, 0))
        # 纵向凹槽：柱身正面与背面各一道窄槽，打断大面积平面
        for zside in (-1, 1):
            p.box((0.085, BEAM_Y - 0.62 - 0.90, 0.045),
                  (x, 0.68 + (BEAM_Y - 0.62 - 0.68) * 0.5, zside * (0.215 - 0.05)),
                  m=deep, bevel=0.012)
        # 柱脚护板（工业橙）：宽度 0.56 → 0.52。护板是"包裹柱脚"的薄板，
        # 收 2 cm 后内侧面到 0.96，给静止姿态的锤头（半宽 0.95）留 1 cm，
        # 正面几乎看不出差别（第 44 回合，见报告 15.8）。
        p.loft([(0.68, rrect(0.52, 0.50, 0.08)), (1.14, rrect(0.52, 0.50, 0.08)),
                (1.20, rrect(0.50, 0.46, 0.08))], m=orange, loc=(x, 0, 0))
        # 柱头：法兰 + 加劲肋 + 螺栓
        p.loft([(BEAM_Y - 0.72, rrect(0.46, 0.40, 0.06)),
                (BEAM_Y - 0.58, rrect(0.80, 0.66, 0.10)),
                (BEAM_Y - 0.48, rrect(0.80, 0.66, 0.10))], m=deep, loc=(x, 0, 0))
        for bx, bz in ((-0.30, -0.23), (-0.30, 0.23), (0.30, -0.23), (0.30, 0.23)):
            p.cyl(0.042, 0.05, (x + bx, BEAM_Y - 0.44, bz), m=bronze, segments=8)
        # 柱身与横梁之间的三角托（承重过渡）
        p.box((0.14, 0.46, 0.60), (x, BEAM_Y - 0.78, 0.0), m=deep, bevel=0.02)

    # ================================================================ 横梁
    p.box((3.10, 0.72, 0.68), (0.0, BEAM_Y, 0.0), m=cream, bevel=0.085, segments=3)
    # 端盖
    for side in (-1, 1):
        p.cyl(0.32, 0.06, (side * 1.56, BEAM_Y, 0.0), m=deep, rot=(0, 0, 90.0), segments=20)
    # 下缘加强板 + 铆钉排
    p.box((3.02, 0.06, 0.50), (0.0, BEAM_Y - 0.39, 0.0), m=deep, bevel=0.01)
    for i in range(9):
        xx = -1.36 + i * 0.34
        p.cyl(0.034, 0.03, (xx, BEAM_Y - 0.415, 0.24), m=bronze, segments=6)
        p.cyl(0.034, 0.03, (xx, BEAM_Y - 0.415, -0.24), m=bronze, segments=6)
    # 顶部铭牌
    p.box((0.90, 0.02, 0.22), (0.0, BEAM_Y + 0.365, 0.0), m=yellow, bevel=0.004)

    # ================================================================ 吊架 + 轴承
    # 铸造吊架：一块从横梁下缘垂下的整体铸件，两侧收腰，轴承座与它一体
    for side in (-1, 1):
        h = (BEAM_Y - 0.42) - PIVOT_Y
        p.loft([(PIVOT_Y - 0.34, rrect(0.34, 0.86, 0.08)),
                (PIVOT_Y + 0.10, rrect(0.30, 0.70, 0.08)),
                (BEAM_Y - 0.44, rrect(0.26, 0.58, 0.06))],
               m=deep, loc=(side * 0.62, 0, 0))
        # 轴承座：上下两半 + 端盖
        p.lathe([(0.0, -0.17), (0.30, -0.17), (0.36, -0.11), (0.36, 0.11),
                 (0.30, 0.17), (0.0, 0.17)], (side * 0.62, PIVOT_Y, 0.0),
                m=deep, rot=(0, 0, 90.0), segments=26)
        p.lathe([(0.0, -0.06), (0.225, -0.06), (0.225, 0.06), (0.0, 0.06)],
                (side * 0.62, PIVOT_Y, 0.0), m=bare, rot=(0, 0, 90.0), segments=22)
        for i in range(5):
            a = K.TAU * i / 5 + math.pi / 5
            p.cyl(0.032, 0.05, (side * 0.62, PIVOT_Y + 0.27 * math.cos(a), 0.27 * math.sin(a)),
                  m=bronze, rot=(0, 0, 90.0), segments=6)
        # 注：轴承下方不再加落地支撑肋——它会穿过锤头的静止/打击包络。
        # 承重由"横梁 → 吊架 → 轴承"这条路径交代，摆锤区保持净空。
        # 油杯
        p.cyl(0.05, 0.10, (side * 0.62, PIVOT_Y + 0.40, 0.0), m=bronze, segments=8)
        p.cyl(0.075, 0.04, (side * 0.62, PIVOT_Y + 0.34, 0.0), m=deep, segments=10)

    # 轴
    p.cyl(0.135, 1.30, (0.0, PIVOT_Y, 0.0), m=bare, rot=(0, 0, 90.0), segments=22)
    for side in (-1, 1):
        p.cyl(0.185, 0.04, (side * 0.86, PIVOT_Y, 0.0), m=deep, rot=(0, 0, 90.0), segments=22)
        p.cyl(0.055, 0.07, (side * 0.88, PIVOT_Y, 0.0), m=bronze, rot=(0, 0, 90.0), segments=8)

    # ================================================================ 砧座
    # 岩石墩（与洞壁同一成因）→ 铸铁砧体 → 可更换打击面
    stone = circle_pts(0.92, 12, 0.2)
    p.loft([(-0.06, scale_pts(stone, 1.14)), (0.08, stone),
            (0.46, scale_pts(stone, 0.90)), (0.56, scale_pts(stone, 0.80))],
           m=deep, loc=(0.0, 0.0, ANVIL_Z))
    # 铸铁砧体：一次成型的厚铸件（宽底 → 收腰 → 顶盘），不再堆台阶
    # 顶盘与打击面之间改为**连续斜面**过渡（原来 1.10 收口后打击面更宽，
    # 形成一圈内凹肩部，从低角度看是一条读作裂缝的死黑带）。
    p.loft([(0.56, rrect(1.66, 1.14, 0.13)),
            (0.68, rrect(1.72, 1.18, 0.14)),
            (0.86, rrect(1.34, 0.96, 0.11)),
            (1.02, rrect(1.46, 1.04, 0.12)),
            (1.115, rrect(1.52, 1.06, 0.13))],
           m=deep, loc=(0.0, 0.0, ANVIL_Z))
    # 注：晶体自带的岩座（RootDome）负责承托与"长出来"的关系，
    # 砧面这里不再做环形唇缘，避免在内圈露出黑色空腔。
    # 打击面（可更换钢板）
    p.box((1.54, 0.06, 1.08), (0.0, 1.145, ANVIL_Z), m=deep, bevel=0.016, rot=(-4.0, 0.0, 0.0))
    for bx in (-0.62, 0.0, 0.62):
        for bz in (-0.42, 0.42):
            p.cyl(0.038, 0.03, (bx, 1.175, ANVIL_Z + bz), m=bronze, segments=6)
    # 晶体夹持颚：三块铸钢卡爪，把晶体根部咬在砧面上
    for i in range(3):
        a = math.pi * 0.5 + K.TAU * i / 3
        jx = 0.60 * math.cos(a)
        jz = ANVIL_Z + 0.60 * math.sin(a)
        p.loft([(1.12, rrect(0.26, 0.30, 0.04)),
                (1.24, rrect(0.24, 0.26, 0.04)),
                (1.40, rrect(0.18, 0.20, 0.03))],
               m=deep, loc=(jx, 0.0, jz), rot=(0.0, -math.degrees(a) + 90.0, 0.0))
        p.cyl(0.032, 0.04, (jx, 1.44, jz), m=bronze, segments=6)
    # 砧座与底盘之间的铸造连接
    # 砧座与承台之间的连接：原来是"砧座前方 0.7 m 一块独立矮方块"，
    # 从 02 机位看就是贴在砧座面前的一块突兀黑块。改成从砧体向后下
    # 延伸到承台的连续铸造肋（起点在砧座底缘，终点落在承台顶面）。
    # z 半宽必须收在承台内：承台 z 范围 -2.10..1.70，肋中心 -1.64，
    # 因此 z 半宽上限 0.46（-2.10 边界）。上一版做到 0.85 会悬出承台 0.39 m。
    p.loft([(0.56, rrect(1.10, 0.88, 0.10)),
            (0.46, rrect(0.96, 0.90, 0.10)),
            (0.30, rrect(0.84, 0.88, 0.09)),
            (0.16, rrect(0.74, 0.86, 0.08))],
           m=deep, loc=(0.0, 0.0, ANVIL_Z + 0.10))
    # 晶体根部由晶体自己的岩座承担；砧面上只留一圈承托唇缘

    # ================================================================ 液压 / 管路
    # 横置蓄能器架在底盘上，管路上接到轴承润滑点
    tank_c = (1.36, 0.92, -0.85)
    p.lathe([(0.0, -0.52), (0.22, -0.52), (0.26, -0.42), (0.26, 0.42),
             (0.22, 0.52), (0.0, 0.52)], (tank_c[0], tank_c[1], tank_c[2]),
            m=orange, rot=(0, 0, 90.0), segments=24)
    for i in range(3):
        p.lathe([(0.0, -0.03), (0.275, -0.03), (0.275, 0.03), (0.0, 0.03)],
                (tank_c[0] + (-0.30 + i * 0.30), tank_c[1], tank_c[2]),
                m=deep, rot=(0, 0, 90.0), segments=24)
    # 鞍座
    for dx in (-0.34, 0.34):
        p.box((0.14, 0.28, 0.34), (tank_c[0] + dx, 0.72, tank_c[2]), m=deep, bevel=0.02)
    # 出口管 → 轴承
    p.cyl(0.048, 0.60, (tank_c[0] - 0.52, 1.05, tank_c[2]), m=bare, rot=(0, 0, 90.0), segments=10)
    p.cyl(0.048, 1.10, (tank_c[0] - 0.82, 1.55, tank_c[2]), m=bare, segments=10)
    p.cyl(0.048, 1.15, (tank_c[0] - 0.82, 2.62, tank_c[2] + 0.28), m=bare,
          rot=(34.0, 0, 0), segments=10)
    # 压力表
    p.cyl(0.09, 0.05, (tank_c[0] - 0.82, 2.30, tank_c[2] + 0.10), m=deep,
          rot=(0, 0, 90.0), segments=14)
    p.cyl(0.065, 0.055, (tank_c[0] - 0.79, 2.30, tank_c[2] + 0.10), m=yellow,
          rot=(0, 0, 90.0), segments=14)

    # ================================================================ 背面检修件
    # 轴承需要维护，所以背面有爬梯、走线槽与蓄能器支架——这些是"为什么
    # 这台机器背面长这样"的答案，而不是随手贴的装饰。
    LX = LEG_X
    for side in (-1, 1):
        for i in range(7):
            yy = 0.75 + i * 0.35
            p.cyl(0.020, 0.34, (side * LX, yy, 0.44), m=bare, rot=(0, 0, 90.0), segments=6)
    for side in (-1, 1):
        p.box((0.05, 2.60, 0.05), (side * LX - 0.19, 1.90, 0.44), m=deep, bevel=0.006)
        p.box((0.05, 2.60, 0.05), (side * LX + 0.19, 1.90, 0.44), m=deep, bevel=0.006)
        # 梯顶护栏
        p.box((0.44, 0.04, 0.04), (side * LX, 3.24, 0.44), m=yellow, bevel=0.004)
    # 走线槽：从操作台一侧沿基础到立柱
    p.box((1.55, 0.07, 0.16), (1.30, 0.56, 1.02), m=deep, bevel=0.008, rot=(0, 0, 8.0))
    p.box((0.16, 0.07, 1.30), (2.02, 0.56, 0.60), m=deep, bevel=0.008)
    for i in range(4):
        p.cyl(0.028, 0.05, (1.30 + i * 0.36, 0.60, 1.02 - i * 0.05), m=bronze, segments=6)
    # 蓄能器鞍座与地脚
    for dx in (-0.34, 0.34):
        p.box((0.16, 0.30, 0.30), (tank_c[0] + dx, 0.62, tank_c[2]), m=deep, bevel=0.02)
        p.box((0.30, 0.06, 0.36), (tank_c[0] + dx, 0.50, tank_c[2]), m=found, bevel=0.01)

    # ================================================================ 操作台
    p.loft([(0.02, rrect(0.94, 0.78, 0.06)), (0.14, rrect(0.94, 0.78, 0.06)),
            (0.80, rrect(0.86, 0.70, 0.06)), (0.86, rrect(0.90, 0.74, 0.06))],
           m=cream, loc=(CX, 0.0, CZ))
    p.box((0.90, 0.12, 0.74), (CX, 0.06, CZ), m=deep, bevel=0.015)
    p.box((0.84, 0.08, 0.04), (CX, 0.14, CZ + 0.38), m=yellow, bevel=0.004)
    # 斜面仪表板
    p.box((0.82, 0.05, 0.40), (CX, 0.84, CZ - 0.02), m=deep, bevel=0.012, rot=(18.0, 0, 0))
    for i in range(3):
        gx = CX - 0.24 + i * 0.16
        p.cyl(0.060, 0.03, (gx, 0.882, CZ - 0.055), m=bare, rot=(72.0, 0, 0), segments=14)
        p.cyl(0.045, 0.034, (gx, 0.886, CZ - 0.058), m=yellow, rot=(72.0, 0, 0), segments=14)
    # 曳引轮 + 护罩
    p.lathe([(0.0, -0.09), (0.16, -0.09), (0.175, -0.05), (0.175, 0.05),
             (0.16, 0.09), (0.0, 0.09)], (CX, 1.06, CZ - 0.06),
            m=bronze, rot=(0, 0, 90.0), segments=22)
    p.box((0.42, 0.30, 0.05), (CX, 1.10, CZ + 0.24), m=deep, bevel=0.01)
    # 操作杆
    p.cyl(0.055, 0.06, (CX + 0.32, 0.90, CZ + 0.26), m=deep, segments=10)
    p.box((0.05, 0.34, 0.05), (CX + 0.34, 1.06, CZ + 0.28), m=yellow, bevel=0.006,
          rot=(8.0, 0, 10.0))
    p.cyl(0.05, 0.08, (CX + 0.36, 1.23, CZ + 0.30), m=rubber, rot=(0, 0, 78.0), segments=10)
    # 柜门 + 锁扣
    p.box((0.58, 0.46, 0.02), (CX, 0.46, CZ + 0.355), m=cream, bevel=0.008)
    p.cyl(0.024, 0.09, (CX + 0.20, 0.46, CZ + 0.37), m=bare, rot=(0, 0, 90.0), segments=8)
    # 电缆：柜体 → 底盘电缆沟
    # 柜体电缆：只从柜底走到走线槽，两段短管，不再有一米多长的黑杆横穿台面
    p.cyl(0.040, 0.40, (CX - 0.06, 0.44, CZ - 0.02), m=rubber, rot=(24.0, 0, 0), segments=8)
    p.cyl(0.034, 0.26, (CX - 0.22, 0.52, CZ - 0.22), m=rubber, rot=(0, 0, 58.0), segments=8)

    obj = p.finish(smooth=True, split_angle=34.0)
    return obj


def build_swing():
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.55, 0.45)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)
    found = K.mat("M_Foundation", (0.33, 0.34, 0.35), 0.72, 0.30)
    cream = K.mat("M_PaintCream", (0.78, 0.745, 0.655), 0.5, 0.18)
    orange = K.mat("M_PaintOrange", (0.72, 0.30, 0.08), 0.52, 0.15)
    yellow = K.mat("M_PaintYellow", (0.82, 0.60, 0.12), 0.5, 0.12)
    worn = K.mat("M_WornSteel", (0.47, 0.455, 0.425), 0.4, 0.5)
    bronze = K.mat("M_Bronze", (0.56, 0.40, 0.165), 0.36, 0.5)

    p = Part("ForgeSwing")
    # 摆臂：两块渐宽钢板，从轴心伸到锤头
    for side in (-1, 1):
        x = side * 0.20
        sections = []
        for i in range(7):
            t = i / 6.0
            y = -0.02 - (ARM - 0.24) * t
            w = 0.24 + 0.20 * t
            sections.append((y, rrect(0.17, w, 0.035)))
        p.loft(sections, m=cream, loc=(x, 0, 0))
        # 轴孔包头
        p.lathe([(0.0, -0.13), (0.26, -0.13), (0.29, -0.09), (0.29, 0.09),
                 (0.26, 0.13), (0.0, 0.13)], (x, 0.0, 0.0),
                m=deep, rot=(0, 0, 90.0), segments=22)
        for i in range(5):
            a = K.TAU * i / 5 + math.pi / 5
            p.cyl(0.028, 0.04, (x + side * 0.15, 0.205 * math.cos(a), 0.205 * math.sin(a)),
                  m=bronze, rot=(0, 0, 90.0), segments=6)

    # 摆臂之间的工字撑
    for t in (0.30, 0.58, 0.82):
        y = -0.02 - (ARM - 0.24) * t
        p.box((0.40, 0.12, 0.10), (0.0, y, 0.0), m=deep, bevel=0.014)

    # ================================================================ 锤头
    head_y = -ARM
    # 锤头宽度受立柱净距约束：柱身内侧面在 |x| = 0.97，锤头半宽必须小于它。
    # 但**柱脚（0.86 宽，内侧面 0.79）与柱脚护板都宽于柱身**，而静止姿态下
    # （REST_ANGLE = 2.5°，锤头几乎垂直悬在两根立柱之间）锤头下缘正好落在
    # 柱脚的高度带（y 0.50..0.62）里 —— 实测咬进去 5.2 cm（报告 15.4）。
    #
    # 第 44 回合的处理：把锤头下缘做成"收腰"剖面 —— 下 0.26 m 收到 1.44 宽，
    # 到 y≈0.64（柱脚顶面以上）再向外放坡到中段最大 1.90。
    # 这样既清掉干涉，中段与打击面的宽度、位置都不变，剪影只多了一道下缘收口，
    # 读起来像铸造锤头的加固裙边，而不是被削掉一块。
    hs = [
        (head_y - 0.32, rrect(1.44, 0.62, 0.08)),
        (head_y - 0.26, rrect(1.48, 0.66, 0.09)),
        (head_y - 0.16, rrect(1.50, 0.70, 0.10)),
        (head_y - 0.06, rrect(1.84, 0.80, 0.12)),
        (head_y + 0.10, rrect(1.90, 0.84, 0.13)),
        (head_y + 0.30, rrect(1.76, 0.72, 0.10)),
    ]
    p.loft(hs, m=deep, loc=(0.0, 0.0, -0.06))
    # 侧板（装配法兰）
    for side in (-1, 1):
        p.box((0.10, 0.70, 0.90), (side * 0.88, head_y, -0.06), m=cream, bevel=0.025)
        for i in range(3):
            # 螺栓头原来在 |x| = 0.935 + r0.036 = 0.971，比柱脚护板内侧面（0.96）还外；
            # 收进 2 cm、缩小一号（外缘 0.947），并整排上移 8 cm：
            # 最低一颗原来落在 wy≈0.58，正卡进柱脚（内侧面 0.79）15 cm；
            # 上移后最低一颗在 wy≈0.66，位于柱脚顶面（0.62）与护板下沿（0.68）之间。
            p.cyl(0.032, 0.04, (side * 0.915, head_y - 0.08 + i * 0.20, 0.28),
                  m=bronze, rot=(0, 0, 90.0), segments=6)
    # 打击面
    p.box((1.32, 0.66, 0.18), (0.0, head_y, -0.55), m=worn, bevel=0.022, rot=(-4.0, 0, 0))
    for bx in (-0.52, 0.0, 0.52):
        p.cyl(0.052, 0.06, (bx, head_y - 0.12, -0.64), m=bronze, rot=(90.0, 0, 0), segments=8)
    # 顶部警示条 + 吊环
    p.box((1.10, 0.16, 0.05), (0.0, head_y + 0.39, -0.06), m=yellow, bevel=0.006)
    p.lathe([(0.0, -0.05), (0.13, -0.05), (0.13, 0.05), (0.0, 0.05)],
            (0.0, head_y + 0.48, -0.06), m=bronze, rot=(0, 0, 90.0), segments=14)
    # 配重块
    p.box((0.94, 0.32, 0.52), (0.0, head_y + 0.04, 0.56), m=orange, bevel=0.035)
    p.box((0.98, 0.06, 0.56), (0.0, head_y + 0.24, 0.56), m=deep, bevel=0.01)

    obj = p.finish(smooth=True, split_angle=34.0)
    return obj


def main():
    K.reset_scene()
    static = build_static()
    swing = build_swing()
    K.export_glb(os.path.join(OUT_DIR, "aq002_forge_static.glb"),
                 name_filter=lambda n: n == "ForgeStatic")
    K.export_glb(os.path.join(OUT_DIR, "aq002_forge_swing.glb"),
                 name_filter=lambda n: n == "ForgeSwing")
    print("AQ002_FORGE static_tris=%d swing_tris=%d"
          % (K.tri_count([static]) if static else 0,
             K.tri_count([swing]) if swing else 0))
    K.save_blend(os.path.join(ROOT, "art-source", "aq002_forge.blend"))


if __name__ == "__main__":
    main()
