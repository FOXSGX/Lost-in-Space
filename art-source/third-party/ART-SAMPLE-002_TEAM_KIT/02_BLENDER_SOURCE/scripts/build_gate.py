"""ART-QUALITY-002-NATURAL · 06 出口门（卷扬提升门）

原版门的问题（docs/04-06_GATE-调查.md 第 2 节）：
  门体是一块平板；没有门框；导轨直接切进岩体、没有端座；灯塔是杆 + 球；
  门袋内壁是平板。

本轮按"卷扬提升门"重做纯视觉外观，**不碰**任何功能件：
  · 门体仍是 `ExitGate/GatePanel`（RigidBody3D + 物理滑轨），只换它的可见网格；
  · 立柱 / 导轨 / 门袋的碰撞体全部保留，新门框只是包在外面的铸钢件；
  · 门的升降、锁扣、触发、出口状态机一律不动。

坐标系与 exit_gate.gd 一致（门节点本地）：
  · x = 门厚方向（玩家在 -x 侧），y = 向上，z = 门洞宽度方向
  · 门洞净宽 4.30（立柱内表面 z = ±2.15），门体 0.36 × 4.20 × 4.08
  · 立柱中心 z = ±2.50，导轨在 x = -0.36、z = ±2.22

导出：
  aq002_gate_static.glb —— 门框 / 门楣 / 导轨端座 / 卷扬 / 门槛 / 控制箱
  aq002_gate_panel.glb  —— 门扇（挂在 GatePanel 节点下，随门升降）
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
OUT_S = os.path.join(ROOT, "project", "assets", "models", "aq002", "aq002_gate_static.glb")
OUT_P = os.path.join(ROOT, "project", "assets", "models", "aq002", "aq002_gate_panel.glb")

PILLAR_Z = 2.50          # 立柱中心
PILLAR_W = 0.85          # 立柱 z 向宽度（比碰撞盒 0.70 略宽，包住它）
PANEL_H = 4.20
PANEL_HW = 2.04          # 门体半宽
LINTEL_Y = 5.50
POCKET_BOTTOM = 4.60


def mats():
    return {
        "cream": K.mat("M_PaintCream", (0.78, 0.745, 0.655), 0.5, 0.18),
        "orange": K.mat("M_PaintOrange", (0.72, 0.30, 0.08), 0.52, 0.15),
        "yellow": K.mat("M_PaintYellow", (0.82, 0.60, 0.12), 0.5, 0.12),
        "deep": K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.55, 0.45),
        "bare": K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55),
        "worn": K.mat("M_WornSteel", (0.47, 0.455, 0.425), 0.4, 0.5),
        "bronze": K.mat("M_Bronze", (0.56, 0.40, 0.165), 0.36, 0.5),
        "rubber": K.mat("M_Rubber", (0.05, 0.052, 0.056), 0.92, 0.0),
    }


def rrect(w, d, c):
    return [
        (w * 0.5 - c, -d * 0.5), (w * 0.5, -d * 0.5 + c),
        (w * 0.5, d * 0.5 - c), (w * 0.5 - c, d * 0.5),
        (-w * 0.5 + c, d * 0.5), (-w * 0.5, d * 0.5 - c),
        (-w * 0.5, -d * 0.5 + c), (-w * 0.5 + c, -d * 0.5),
    ]


def build_static():
    M = mats()
    p = Part("GateStatic")

    # ------------------------------------------------------------ 门框立柱
    for side in (-1, 1):
        z = side * PILLAR_Z
        # 柱脚：一块更宽的铸钢底座 + 地脚螺栓
        p.box((0.86, 0.26, 1.10), (0.02, 0.13, z), m=M["deep"], bevel=0.03)
        for bz in (-0.36, 0.0, 0.36):
            for bx in (-0.28, 0.32):
                p.cyl(0.055, 0.10, (bx, 0.30, z + bz), m=M["bronze"], segments=8)
        # 柱身：正面带一道竖向凸棱，避免整面平墙
        p.loft([(0.26, rrect(0.62, PILLAR_W, 0.10)),
                (1.10, rrect(0.60, PILLAR_W, 0.10)),
                (4.90, rrect(0.56, PILLAR_W - 0.06, 0.09)),
                (5.22, rrect(0.52, PILLAR_W - 0.10, 0.08))], m=M["cream"], loc=(0.0, 0.0, z))
        # 内侧导轨槽：门体从这里穿过（门体半宽 2.04，槽口 2.15..2.44）
        inner = -side * (PILLAR_W * 0.5 - 0.10)
        p.box((0.30, 4.40, 0.22), (-0.16, 2.60, z + inner), m=M["bare"], bevel=0.02)
        # 正面：三道横向加强带 + 一排螺栓
        for i, y in enumerate((1.35, 2.55, 3.75)):
            p.box((0.66, 0.22, PILLAR_W + 0.04), (0.0, y, z), m=M["deep"], bevel=0.025)
        for i in range(6):
            p.cyl(0.045, 0.08, (-0.32, 0.75 + i * 0.72, z), m=M["bronze"],
                  rot=(0.0, 90.0, 0.0), segments=8)
        # 柱顶斜撑：把立柱和门楣连起来，结构上说得通
        p.box((0.42, 0.90, 0.26), (-0.02, 5.05, z - side * 0.30), m=M["deep"],
              bevel=0.02, rot=(side * 22.0, 0.0, 0.0))
        # 警示带（下段）
        p.box((0.64, 0.30, PILLAR_W + 0.05), (0.0, 0.62, z), m=M["yellow"], bevel=0.006)

    # ------------------------------------------------------------ 门楣
    p.box((0.72, 0.62, 6.60), (0.0, LINTEL_Y, 0.0), m=M["cream"], bevel=0.04)
    p.box((0.76, 0.10, 6.66), (0.0, LINTEL_Y - 0.34, 0.0), m=M["deep"], bevel=0.012)
    # 门楣下沿的斜导面（门升上去时贴着它）
    p.box((0.60, 0.14, 4.40), (-0.06, LINTEL_Y - 0.42, 0.0), m=M["bare"], bevel=0.02,
          rot=(0.0, 0.0, 0.0))
    for bz in (-2.0, 2.0):
        for i in range(3):
            p.cyl(0.05, 0.09, (-0.34, LINTEL_Y - 0.10 + i * 0.20, bz), m=M["bronze"],
                  rot=(0.0, 90.0, 0.0), segments=8)

    # ------------------------------------------------------------ 导轨端座
    # 原版导轨 8.6 m 直接切进岩体；这里给上端一个铸钢端座、下端一个斜挡
    for side in (-1, 1):
        z = side * 2.22
        p.box((0.34, 0.46, 0.42), (-0.36, 8.10, z), m=M["deep"], bevel=0.03)
        p.box((0.26, 0.20, 0.30), (-0.36, 0.62, z), m=M["deep"], bevel=0.02)
        for i, y in enumerate((1.10, 3.30, 6.20, 7.70)):
            p.box((0.22, 0.16, 0.30), (-0.52, y, z), m=M["bare"], bevel=0.015)

    # ------------------------------------------------------------ 卷扬
    wy = LINTEL_Y + 0.62
    # 机架
    p.box((0.60, 0.16, 2.10), (0.0, wy - 0.30, 0.0), m=M["deep"], bevel=0.02)
    # 卷筒
    p.lathe([(0.0, -0.62), (0.24, -0.62), (0.30, -0.54), (0.30, 0.54),
             (0.24, 0.62), (0.0, 0.62)], (0.0, wy, 0.0), m=M["deep"],
            rot=(0.0, 0.0, 90.0), segments=20)
    for bz in (-0.30, 0.30):
        p.lathe([(0.0, -0.06), (0.38, -0.06), (0.42, -0.02), (0.42, 0.02),
                 (0.38, 0.06), (0.0, 0.06)], (0.0, wy, bz), m=M["deep"],
                rot=(0.0, 0.0, 90.0), segments=20)
    # 减速箱 + 电机
    p.box((0.42, 0.44, 0.50), (-0.02, wy, 0.92), m=M["deep"], bevel=0.03)
    p.cyl(0.20, 0.46, (0.0, wy, 1.44), m=M["orange"], rot=(90.0, 0.0, 0.0), segments=16)
    p.cyl(0.11, 0.52, (0.0, wy, 1.44), m=M["bare"], rot=(90.0, 0.0, 0.0), segments=12)
    # 钢丝绳：从卷筒两侧垂到门扇吊耳
    for bz in (-0.92, 0.92):
        p.cyl(0.022, 1.35, (0.0, wy - 0.70, bz), m=M["rubber"], segments=6)
    # 卷筒护罩：正面盖板 + 两端侧板，卷筒只从下方露出绳索
    p.box((0.06, 0.78, 1.80), (-0.38, wy + 0.06, 0.0), m=M["deep"], bevel=0.02)
    for bz in (-0.94, 0.94):
        p.box((0.52, 0.78, 0.06), (-0.10, wy + 0.06, bz), m=M["deep"], bevel=0.015)

    # 检修梯（挂在右立柱外侧）
    for i in range(9):
        p.box((0.05, 0.04, 0.30), (0.34, 1.20 + i * 0.42, -3.02), m=M["bare"], bevel=0.004)
    for bz in (-3.14, -2.90):
        p.box((0.06, 4.00, 0.06), (0.34, 3.00, bz), m=M["bare"], bevel=0.006)

    # ------------------------------------------------------------ 门洞周边：控制箱
    cx, cz = -0.34, -2.78
    p.box((0.26, 0.70, 0.52), (cx, 1.55, cz), m=M["deep"], bevel=0.02)
    p.box((0.24, 0.26, 0.46), (cx - 0.14, 1.68, cz), m=M["yellow"], bevel=0.006)
    for i in range(3):
        p.cyl(0.035, 0.05, (cx - 0.18, 1.62 - i * 0.10, cz - 0.12 + i * 0.12),
              m=M["bronze"], rot=(0.0, 90.0, 0.0), segments=8)
    # 状态灯：装在立柱上方的支架上，而不是一根杆顶个球
    p.box((0.22, 0.10, 0.22), (-0.30, 4.62, -2.50), m=M["deep"], bevel=0.01)
    p.cyl(0.085, 0.16, (-0.30, 4.72, -2.50), m=M["orange"], segments=12)
    # 电缆：控制箱 → 门框底部走线槽
    p.cyl(0.028, 0.90, (-0.30, 1.10, -3.10), m=M["rubber"], rot=(0.0, 0.0, 6.0), segments=6)

    # ------------------------------------------------------------ 门槛 + 排水
    p.box((0.96, 0.16, 4.70), (0.0, -0.06, 0.0), m=M["deep"], bevel=0.02)
    p.box((1.02, 0.03, 4.76), (0.0, 0.015, 0.0), m=M["yellow"], bevel=0.004)
    for i in range(9):
        p.box((0.30, 0.05, 0.30), (-0.56, -0.02, -1.80 + i * 0.45), m=M["bare"], bevel=0.006)

    obj = p.finish(smooth=True, split_angle=32.0)
    return obj


def build_panel():
    M = mats()
    p = Part("GatePanel")
    cy = PANEL_H * 0.5

    # 主体板：比碰撞盒（0.36）薄 6 cm，前后各留 3 cm，避免穿透
    p.box((0.30, PANEL_H, PANEL_HW * 2), (0.0, cy, 0.0), m=M["bare"], bevel=0.03)

    # 正面：外框 + 横向加强肋 + 竖向分缝
    p.box((0.06, 0.18, PANEL_HW * 2 - 0.06), (-0.17, PANEL_H - 0.14, 0.0), m=M["deep"], bevel=0.015)
    p.box((0.06, 0.18, PANEL_HW * 2 - 0.06), (-0.17, 0.14, 0.0), m=M["deep"], bevel=0.015)
    for bz in (-PANEL_HW + 0.12, PANEL_HW - 0.12):
        p.box((0.06, PANEL_H - 0.20, 0.18), (-0.17, cy, bz), m=M["deep"], bevel=0.015)
    for i in range(5):
        p.box((0.05, 0.16, PANEL_HW * 2 - 0.30), (-0.18, 0.62 + i * 0.72, 0.0), m=M["deep"],
              bevel=0.012)
    for bz in (-0.72, 0.72):
        p.box((0.04, PANEL_H - 0.44, 0.06), (-0.17, cy, bz), m=M["deep"], bevel=0.008)

    # 底部危险斜纹（真几何，不是贴图）
    for i in range(6):
        p.box((0.05, 0.26, 0.30), (-0.18, 0.36, -1.55 + i * 0.62), m=M["yellow"],
              bevel=0.006, rot=(0.0, 0.0, 0.0))
    p.box((0.05, 0.08, PANEL_HW * 2 - 0.12), (-0.18, 0.16, 0.0), m=M["cream"], bevel=0.006)

    # 中央检修舱口：圆形，带一圈螺栓和一个十字手轮
    p.lathe([(0.0, -0.05), (0.40, -0.05), (0.44, -0.01), (0.44, 0.03),
             (0.40, 0.06), (0.0, 0.06)], (-0.20, cy, 0.0), m=M["cream"],
            rot=(0.0, 0.0, 90.0), segments=24)
    for i in range(8):
        a = K.TAU * i / 8
        p.cyl(0.028, 0.05, (-0.24, cy + 0.34 * math.cos(a), 0.34 * math.sin(a)),
              m=M["bronze"], rot=(0.0, 90.0, 0.0), segments=6)
    p.cyl(0.07, 0.10, (-0.28, cy, 0.0), m=M["bronze"], rot=(0.0, 90.0, 0.0), segments=10)
    p.box((0.06, 0.44, 0.06), (-0.30, cy, 0.0), m=M["bare"], bevel=0.008)
    p.box((0.06, 0.06, 0.44), (-0.30, cy, 0.0), m=M["bare"], bevel=0.008)

    # 顶部吊耳（钢丝绳挂点）
    for bz in (-0.92, 0.92):
        p.box((0.10, 0.46, 0.16), (-0.02, PANEL_H + 0.16, bz), m=M["deep"], bevel=0.015)
        p.cyl(0.05, 0.12, (-0.02, PANEL_H + 0.12, bz), m=M["bare"],
              rot=(0.0, 90.0, 0.0), segments=8)

    # 两侧滑块（在导轨槽里滑）
    for side in (-1, 1):
        for y in (0.70, 2.10, 3.50):
            p.box((0.22, 0.26, 0.14), (0.0, y, side * (PANEL_HW - 0.02)), m=M["bronze"],
                  bevel=0.01)

    # 底部密封条 + 两侧压条
    p.box((0.34, 0.10, PANEL_HW * 2 - 0.20), (0.0, 0.03, 0.0), m=M["rubber"], bevel=0.01)

    obj = p.finish(smooth=True, split_angle=34.0)
    return obj


def main():
    K.reset_scene()
    s = build_static()
    pn = build_panel()
    print("AQ002_GATE static_tris=%d panel_tris=%d" % (K.tri_count([s]), K.tri_count([pn])))
    K.export_glb(OUT_S, name_filter=lambda n: n.startswith("GateStatic"))
    K.export_glb(OUT_P, name_filter=lambda n: n.startswith("GatePanel"))
    K.save_blend(os.path.join(ROOT, "art-source", "aq002_gate.blend"))


if __name__ == "__main__":
    main()
