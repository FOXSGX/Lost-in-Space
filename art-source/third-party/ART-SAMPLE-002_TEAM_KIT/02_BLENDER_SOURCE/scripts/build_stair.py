"""ART-QUALITY-002-NATURAL · 入口钢梯（DockStair 的可见外观重制）

原实现是一条 3.2m 跨、2.6m 高的平滑斜坡碰撞体，上面贴了台阶、踢脚、
斜撑、警示条、栏杆等 10 层零碎几何，从出生点看是一块灰色大三角 +
几根互相交叉的黄色斜杆——这正是"突兀、杂乱"的典型。

本轮：碰撞完全不动（还是那条斜坡，走起来不会卡），可见外观整体重做成
一部真正的钢结构楼梯：

  * 两侧通长钢梯梁（stringer），承托每一级踏面
  * 13 级带防滑前缘的钢踏面
  * 靠外一侧的立柱 + 扶手 + 中横杆（连续、不交叉）
  * 梯脚落在岩石基座上，柱脚有底板与地脚螺栓

导出：aq002_stair.glb
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
OUT = os.path.join(ROOT, "project", "assets", "models", "aq002", "aq002_stair.glb")

LOW = (-1.0, 0.0, 3.8)
HIGH = (-4.2, 2.6, 3.8)
WIDTH = 1.6
STEPS = 13


def build():
    cream = K.mat("M_PaintCream", (0.78, 0.745, 0.655), 0.5, 0.18)
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.55, 0.45)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)
    yellow = K.mat("M_PaintYellow", (0.82, 0.60, 0.12), 0.5, 0.12)
    orange = K.mat("M_PaintOrange", (0.72, 0.30, 0.08), 0.52, 0.15)
    bronze = K.mat("M_Bronze", (0.56, 0.40, 0.165), 0.36, 0.5)
    rock = K.mat("M_StairRock", (0.22, 0.185, 0.155), 0.9, 0.0)

    p = Part("Stair")
    dx = HIGH[0] - LOW[0]
    dy = HIGH[1] - LOW[1]
    run = abs(dx)
    slope = math.sqrt(run * run + dy * dy)
    ang = math.atan2(dy, run)  # 0..pi/2
    z0 = LOW[2] - WIDTH * 0.5
    z1 = LOW[2] + WIDTH * 0.5

    # ---------------------------------------------------------------- 梯梁
    for z in (z0 + 0.05, z1 - 0.05):
        p.box((slope + 0.10, 0.34, 0.10),
              ((LOW[0] + HIGH[0]) * 0.5, (LOW[1] + HIGH[1]) * 0.5 - 0.18, z),
              m=deep, rot=(0.0, 0.0, -math.degrees(ang)), bevel=0.012)

    # ---------------------------------------------------------------- 踏面
    step_run = run / STEPS
    step_rise = dy / STEPS
    for i in range(STEPS):
        t = (i + 0.5) / STEPS
        x = LOW[0] + dx * t
        y = LOW[1] + dy * t
        # 踏面
        p.box((step_run + 0.06, 0.045, WIDTH - 0.10), (x, y, LOW[2]),
              m=bare, bevel=0.008)
        # 前缘防滑条
        p.box((0.045, 0.030, WIDTH - 0.16), (x - step_run * 0.5 + 0.01, y + 0.030, LOW[2]),
              m=yellow, bevel=0.004)
        # 踢面
        p.box((0.035, step_rise + 0.02, WIDTH - 0.12),
              (x - step_run * 0.5, y - step_rise * 0.5, LOW[2]),
              m=deep, bevel=0.006)

    # ---------------------------------------------------------------- 栏杆
    # 只做靠场地外侧（+z）一侧，避免两根斜杆在出生点画面里交叉
    rail_z = z1 + 0.06
    posts = 6
    for i in range(posts):
        t = i / (posts - 1.0)
        x = LOW[0] + dx * t
        y = LOW[1] + dy * t
        p.box((0.06, 1.02, 0.06), (x, y + 0.51, rail_z), m=deep, bevel=0.008)
        p.box((0.16, 0.03, 0.16), (x, y + 1.02, rail_z), m=orange, bevel=0.004)
    # 扶手与中横杆沿坡面连续
    for (h, r, mm) in ((1.03, 0.032, yellow), (0.55, 0.022, deep)):
        p.box((slope + 0.12, r * 2.0, r * 2.0),
              ((LOW[0] + HIGH[0]) * 0.5, (LOW[1] + HIGH[1]) * 0.5 + h, rail_z),
              m=mm, rot=(0.0, 0.0, -math.degrees(ang)), bevel=0.004)

    # ---------------------------------------------------------------- 支撑
    for t in (0.34, 0.72):
        x = LOW[0] + dx * t
        y = LOW[1] + dy * t
        h = max(0.2, y - 0.30)
        p.box((0.16, h, 0.16), (x, h * 0.5, LOW[2] - WIDTH * 0.5 + 0.12), m=deep, bevel=0.01)
        p.box((0.42, 0.06, 0.42), (x, 0.03, LOW[2] - WIDTH * 0.5 + 0.12), m=bare, bevel=0.008)
        for bx, bz in ((-0.13, -0.13), (-0.13, 0.13), (0.13, -0.13), (0.13, 0.13)):
            p.cyl(0.028, 0.05, (x + bx, 0.07, LOW[2] - WIDTH * 0.5 + 0.12 + bz),
                  m=bronze, segments=6)

    # ---------------------------------------------------------------- 梯脚基座
    # 一块被凿平的岩石承台：楼梯不是"插"在地面上
    p.loft([(-0.10, [(math.cos(a) * 1.05, math.sin(a) * 0.78) for a in
                     [K.TAU * k / 9 for k in range(9)]]),
            (0.03, [(math.cos(a) * 0.98, math.sin(a) * 0.72) for a in
                    [K.TAU * k / 9 for k in range(9)]]),
            (0.10, [(math.cos(a) * 0.80, math.sin(a) * 0.58) for a in
                    [K.TAU * k / 9 for k in range(9)]])],
           m=rock, loc=(LOW[0] + 0.10, 0.0, LOW[2]))
    # 楼梯底板与承台的连接
    p.box((0.70, 0.08, WIDTH + 0.10), (LOW[0] + 0.05, 0.13, LOW[2]), m=deep, bevel=0.01)

    obj = p.finish(smooth=True, split_angle=38.0)
    return obj


def main():
    K.reset_scene()
    obj = build()
    print("AQ002_STAIR tris=%d" % K.tri_count([obj]))
    K.export_glb(OUT)
    K.save_blend(os.path.join(ROOT, "art-source", "aq002_stair.blend"))


if __name__ == "__main__":
    main()
