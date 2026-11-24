"""ART-QUALITY-002-NATURAL · 贴墙工作灯（掠射用）

第 47 回合的对照实验证明：第四幕近景偏软的主因是环境光占主导，同一面墙在
15–25° 掠射光下立刻出棱（`captures/wall_graze/`）。本轮按创建者选择的 1A，
给可走墙面加两盏**带灯具**的工作灯。

做法与规矩：
  · 灯是"装在墙上的"，不是浮在空中的——底板、膨胀螺栓、灯臂、灯罩、接线盒、
    沿墙线管一应俱全；
  · 本地坐标：+z 朝墙里，-z 朝墙外（灯口方向），挂载时按墙面法线旋转；
  · 夹具只做外观，光源由环境层里的 SpotLight3D 提供，位置与灯口对齐。

导出：aq002_wall_lamp.glb（原点 = 底板中心）
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aq2kit as K
from aq2kit import Part

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "project", "assets", "models", "aq002", "aq002_wall_lamp.glb")


def build():
    cream = K.mat("M_PaintCream", (0.78, 0.745, 0.655), 0.5, 0.18)
    yellow = K.mat("M_PaintYellow", (0.82, 0.60, 0.12), 0.5, 0.12)
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.55, 0.45)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)
    bronze = K.mat("M_Bronze", (0.56, 0.40, 0.165), 0.36, 0.5)
    rubber = K.mat("M_Rubber", (0.05, 0.052, 0.056), 0.92, 0.0)

    p = Part("WallLamp")

    # ---- 底板（贴墙）+ 四颗膨胀螺栓 ----
    p.box((0.44, 0.44, 0.06), (0.0, 0.0, 0.0), m=deep, bevel=0.015)
    for bx in (-0.16, 0.16):
        for by in (-0.16, 0.16):
            p.cyl(0.022, 0.06, (bx, by, -0.04), m=bronze, rot=(90.0, 0.0, 0.0), segments=6)

    # ---- 灯臂：短横臂 + 吊臂 ----
    p.box((0.12, 0.12, 0.34), (0.0, 0.0, -0.20), m=bare, bevel=0.02)
    p.box((0.12, 0.26, 0.12), (0.0, -0.10, -0.34), m=bare, bevel=0.02)

    # ---- 灯罩：罩体 + 斜口翻边 + 玻璃 ----
    p.box((0.42, 0.32, 0.34), (0.0, -0.12, -0.56), m=cream, bevel=0.03)
    p.box((0.46, 0.36, 0.05), (0.0, -0.12, -0.74), m=yellow, bevel=0.008)
    p.box((0.36, 0.26, 0.03), (0.0, -0.12, -0.765), m=deep, bevel=0.006)
    # 罩顶的一道防雨檐
    p.box((0.50, 0.06, 0.40), (0.0, 0.055, -0.56), m=yellow, bevel=0.008)

    # ---- 接线盒 + 沿墙线管 ----
    p.box((0.16, 0.14, 0.12), (0.21, 0.02, -0.10), m=deep, bevel=0.012)
    p.cyl(0.030, 0.60, (0.21, 0.24, -0.02), m=rubber, segments=6)

    obj = p.finish(smooth=True, split_angle=32.0)
    return obj


def main():
    K.reset_scene()
    obj = build()
    print("AQ002_LAMP tris=%d" % K.tri_count([obj]))
    K.export_glb(OUT)
    K.save_blend(os.path.join(ROOT, "art-source", "aq002_wall_lamp.blend"))


if __name__ == "__main__":
    main()
