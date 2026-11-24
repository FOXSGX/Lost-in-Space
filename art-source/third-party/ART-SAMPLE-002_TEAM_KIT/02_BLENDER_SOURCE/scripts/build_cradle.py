"""ART-QUALITY-002-NATURAL · 共振摇篮（b1–b4 共用）

原版摇篮是"唱机"：小圆台 + 金色导环 + 两根小夹爪，玩家看不出
它是**承接**晶体、**导向**晶体、还是**锁止**晶体的设备。

本轮按产品重做可见外观，但不碰任何功能件（Jaw_0 / Jaw_1 的枢轴、
Pocket 区、Seat 面、交互点都在原有节点上）：

  承台（落地 + 地脚） → 减振垫 → 机座 → 导向槽 → 夹持窗口 → 控制箱 + 铭牌

夹持窗口留净空 0.62 × 0.40 m，原夹爪在其中开合，不会被新外壳挡住。

导出：aq002_cradle.glb（原点 = 摇篮节点原点，Y 向上）
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
OUT = os.path.join(ROOT, "project", "assets", "models", "aq002", "aq002_cradle.glb")

SEAT_Y = 0.38


def rrect(w, d, c):
    return [
        (w * 0.5 - c, -d * 0.5), (w * 0.5, -d * 0.5 + c),
        (w * 0.5, d * 0.5 - c), (w * 0.5 - c, d * 0.5),
        (-w * 0.5 + c, d * 0.5), (-w * 0.5, d * 0.5 - c),
        (-w * 0.5, -d * 0.5 + c), (-w * 0.5 + c, -d * 0.5),
    ]


def circle_pts(r, n=24, phase=0.0):
    return [(r * math.cos(phase + K.TAU * i / n), r * math.sin(phase + K.TAU * i / n)) for i in range(n)]


def scale_pts(pts, s):
    return [(p[0] * s, p[1] * s) for p in pts]


def build():
    cream = K.mat("M_PaintCream", (0.78, 0.745, 0.655), 0.5, 0.18)
    orange = K.mat("M_PaintOrange", (0.72, 0.30, 0.08), 0.52, 0.15)
    yellow = K.mat("M_PaintYellow", (0.82, 0.60, 0.12), 0.5, 0.12)
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.55, 0.45)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)
    bronze = K.mat("M_Bronze", (0.56, 0.40, 0.165), 0.36, 0.5)
    rubber = K.mat("M_Rubber", (0.05, 0.052, 0.056), 0.92, 0.0)
    rock = K.mat("M_CradleRock", (0.215, 0.180, 0.150), 0.88, 0.0)

    p = Part("Cradle")

    # ---------------------------------------------------------------- 承台
    # 一块八角岩石承台，机器不是直接放在地板上
    rock_ring = circle_pts(0.86, 12, 0.15)
    p.loft([(-0.10, scale_pts(rock_ring, 1.10)), (0.02, rock_ring),
            (0.10, scale_pts(rock_ring, 0.94))], m=rock)
    # 减振垫（橡胶，露出 3 cm）
    pad = circle_pts(0.70, 20)
    p.loft([(0.10, pad), (0.13, scale_pts(pad, 0.99))], m=rubber)
    # 机座：八角厚板，四角切角
    p.loft([(0.13, rrect(1.28, 1.28, 0.16)),
            (0.19, rrect(1.34, 1.34, 0.17)),
            (0.27, rrect(1.30, 1.30, 0.17))], m=deep)
    # 机座顶面的安装法兰
    p.loft([(0.27, rrect(1.04, 1.04, 0.13)), (0.31, rrect(1.00, 1.00, 0.13))], m=bare)
    # 地脚螺栓
    for i in range(8):
        a = K.TAU * i / 8 + math.pi / 8
        p.cyl(0.036, 0.06, (0.60 * math.cos(a), 0.205, 0.60 * math.sin(a)), m=bronze, segments=6)
    # 朝向侧的安全黄踢脚（说明"这一面是操作面"）
    p.box((0.96, 0.05, 0.05), (0.0, 0.24, 0.68), m=yellow, bevel=0.004)

    # ---------------------------------------------------------------- 机座
    # 主体是"环形座 + 后立板"的整体铸件：
    #   环形座承托晶体，后立板挂导向与控制。
    body = circle_pts(0.46, 28)
    p.loft([(0.31, scale_pts(body, 1.02)), (0.34, body),
            (0.38, scale_pts(body, 0.98)), (0.405, scale_pts(body, 0.90))],
           m=cream)
    # 座面（晶体底部落座处，略高于原 SEAT_Y=0.38）
    seat = circle_pts(0.40, 28)
    p.loft([(0.36, seat), (0.405, seat)], m=bare)
    # 座体上的加强筋（4 道，指向地脚）
    for i in range(4):
        a = K.TAU * i / 4 + math.pi / 4
        p.box((0.10, 0.30, 0.30), (0.42 * math.cos(a), 0.46, 0.42 * math.sin(a)),
              m=deep, rot=(0.0, 0.0, -math.degrees(a)), bevel=0.012)

    # 后立架：两根立柱 + 顶部横梁，而不是一块大白板。
    # 这样从任何一侧看都有清楚的结构关系，也不会把晶体背后挡成一片白。
    for side in (-1, 1):
        p.loft([(0.31, rrect(0.20, 0.18, 0.03)),
                (0.38, rrect(0.22, 0.20, 0.03)),
                (1.02, rrect(0.18, 0.17, 0.03))],
               m=cream, loc=(side * 0.52, 0.0, 0.54))
        p.box((0.10, 0.32, 0.26), (side * 0.52, 0.44, 0.44), m=deep, bevel=0.012)
    p.box((1.22, 0.14, 0.18), (0.0, 0.96, 0.54), m=cream, bevel=0.03)
    p.box((1.26, 0.05, 0.20), (0.0, 0.885, 0.54), m=deep, bevel=0.008)
    for bx in (-0.52, 0.52):
        p.cyl(0.03, 0.04, (bx, 1.04, 0.54), m=bronze, segments=6)

    # ---------------------------------------------------------------- 导向槽
    # 两条平行导轨，从座体前缘延伸到后立板：晶体沿它滑进夹持位。
    # 净空 0.62 m，原夹爪（JAW_OPEN=0.62）刚好在其中开合。
    # 导向槽：±0.42（净空 0.78）。原来 ±0.345 → 净空 0.59，而晶体直径 0.68，
    # 近景能看出导轨插进晶体；加宽后爪面（合拢到 0.408）仍落在槽内。
    for side in (-1, 1):
        x = side * 0.42
        p.loft([(0.34, rrect(0.10, 0.66, 0.02)),
                (0.40, rrect(0.12, 0.68, 0.02)),
                (0.46, rrect(0.10, 0.62, 0.02))],
               m=bare, loc=(x, 0.0, -0.06))
        # 导轨前端的导入斜角
        p.box((0.10, 0.12, 0.14), (x, 0.40, -0.44), m=deep, bevel=0.01)
        # 导轨内侧的耐磨片
        p.box((0.02, 0.05, 0.52), (x - side * 0.055, 0.40, -0.06), m=bronze, bevel=0.004)
    # 座体前缘的导入唇缘（晶体放进来时的导向面）
    p.loft([(0.31, [(x, 0.0) for x in (-0.40, -0.34, 0.34, 0.40)]),
            (0.35, [(x, 0.10) for x in (-0.40, -0.34, 0.34, 0.40)])],
           m=deep, loc=(0.0, 0.0, -0.28))

    # ---------------------------------------------------------------- 后壁板
    # 把"两根立柱之间是空的"补成一台有本体的机器，远景里就不会被读成空画框；
    # 板上留三道散热格栅。
    p.box((0.86, 0.58, 0.05), (0.0, 0.60, -0.42), m=deep, bevel=0.012)
    for i in range(3):
        p.box((0.60, 0.030, 0.02), (0.0, 0.42 + i * 0.085, -0.452), m=bare, bevel=0.004)

    # ---------------------------------------------------------------- 控制箱
    # 挂在后立板背面，带铭牌与指示灯座
    for side in (-1, 1):
        cx = side * 0.52
        p.loft([(0.50, rrect(0.30, 0.20, 0.03)),
                (0.54, rrect(0.32, 0.22, 0.03)),
                (0.76, rrect(0.30, 0.21, 0.03))],
               m=deep, loc=(cx, 0.0, 0.62))
        p.box((0.24, 0.12, 0.02), (cx, 0.67, 0.735), m=yellow, bevel=0.004)
        p.cyl(0.026, 0.03, (cx - side * 0.08, 0.65, 0.66), m=bronze,
              rot=(90.0, 0.0, 0.0), segments=10)
    # 电缆：贴在后立架内侧，不伸出机体轮廓
    p.cyl(0.020, 0.34, (0.34, 0.62, 0.56), m=rubber, rot=(0.0, 0.0, 88.0), segments=6)
    p.cyl(0.020, 0.24, (-0.34, 0.50, 0.56), m=rubber, rot=(0.0, 0.0, 88.0), segments=6)

    # ---------------------------------------------------------------- 指示灯座
    # 指示球原来直接浮在 (0, 0.48, 0.42) 的晶体背面，近景像一颗飘着的珠子。
    # 这里在操作面上方做一个灯座：底板 + 围边 + 玻璃凹槽，球挪进来就有落点。
    p.box((0.24, 0.16, 0.05), (0.0, 0.64, -0.60), m=deep, bevel=0.012)
    p.loft([(0.60, rrect(0.20, 0.16, 0.03)), (0.70, rrect(0.22, 0.18, 0.03))],
           m=bare, loc=(0.0, 0.0, -0.575))
    p.cyl(0.075, 0.05, (0.0, 0.68, -0.575), m=rubber, rot=(90.0, 0.0, 0.0), segments=14)
    p.box((0.10, 0.02, 0.06), (0.0, 0.555, -0.62), m=yellow, bevel=0.004)

    # ---------------------------------------------------------------- 锁定指示
    # 座体正面的凹槽 + 锁钩座（锁止由原版 Pawl 节点驱动，这里只做受位）
    p.box((0.22, 0.10, 0.06), (0.0, SEAT_Y + 0.03, 0.50), m=deep, bevel=0.008)
    p.cyl(0.05, 0.06, (0.0, SEAT_Y, 0.54), m=bronze, segments=10)

    # ---------------------------------------------------------------- 操作面（-Z）
    # 玩家从这一侧走近：斜面控制台 + 状态灯 + 铭牌，让"人在哪里操作"一眼可见
    p.loft([(0.31, rrect(0.56, 0.30, 0.04)),
            (0.36, rrect(0.58, 0.32, 0.04)),
            (0.58, rrect(0.50, 0.26, 0.04))],
           m=deep, loc=(0.0, 0.0, -0.42))
    p.box((0.46, 0.05, 0.24), (0.0, 0.60, -0.46), m=bare, bevel=0.008, rot=(20.0, 0.0, 0.0))
    p.cyl(0.055, 0.035, (0.11, 0.635, -0.50), m=bronze, rot=(70.0, 0.0, 0.0), segments=14)
    p.cyl(0.040, 0.040, (0.11, 0.638, -0.503), m=yellow, rot=(70.0, 0.0, 0.0), segments=14)
    p.box((0.34, 0.055, 0.02), (0.0, 0.43, -0.585), m=yellow, bevel=0.004)
    p.box((0.24, 0.03, 0.02), (0.0, 0.47, -0.585), m=orange, bevel=0.004)
    for bx in (-0.24, 0.24):
        p.cyl(0.028, 0.04, (bx, 0.35, -0.575), m=bronze, rot=(90.0, 0.0, 0.0), segments=6)

    obj = p.finish(smooth=True, split_angle=36.0)
    return obj


def main():
    K.reset_scene()
    obj = build()
    print("AQ002_CRADLE tris=%d" % K.tri_count([obj]))
    K.export_glb(OUT)
    K.save_blend(os.path.join(ROOT, "art-source", "aq002_cradle.blend"))


if __name__ == "__main__":
    main()
