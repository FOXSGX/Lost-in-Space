"""奶龙星 · 南侧维修棚（Mid 级资产，按《美术制作与 AI 协作指南》九步流水线）

坐标：**Godot 约定（x 右 / y 上 / z 前）**；原点 = 棚屋地面中心（世界 0, 0, -11.8）。
尺寸：x 6.24 × y 3.32 × z 3.10（含屋檐出挑）。

结构：四根 H 型钢柱（前高后低，屋面 6° 单坡）→ 两侧工字梁 → 三根椽条 →
      瓦楞屋面板（真实波形放样）→ 背墙/侧墙瓦楞板 + 檩条 + 黄色踢脚 →
      工作台（台面板折边 + 腿框 + 柜门 + 台钳 + 工具箱）→ 背墙挂板 →
      吊装遮光工作灯（挂板 + 吊杆 + 锥罩 + 防眩杆 + 管卡）→ 柱脚承台与地脚螺栓。

导出：assets/models/nailong/service_shed.glb
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = r"C:\Users\31798\.openclaw\workspace\ref\art_sample_002\02_BLENDER_SOURCE\scripts"
sys.path.insert(0, KIT)
sys.path.insert(0, HERE)

import aq2kit as K
import aqs_kit as S
from aqs_kit import Hero, bm_box
import nailong_kit as N

OUT = r"C:\Users\31798\Documents\GitHub\Lost-in-Space-gulu\game\previews\gulu_planet\assets\models\nailong\service_shed.glb"

COL_X = 2.60           # 柱距 5.2 m，通行净宽 >= 2.0 m
COL_Z = 1.15
TILT = -6.0            # 屋面单坡，向后（-z）排水
RY = 3.15              # 屋面板中面在 z=0 的高度
SLOPE = math.tan(6.0 * math.pi / 180.0)
SHEET_T = 0.008
RAFTER_T = 0.13


def under(z):
    """屋面板下沿高度（z 处）。"""
    return RY + SLOPE * z - SHEET_T


def main():
    K.reset_scene()

    cream = K.mat("M_PaintCream", (0.615, 0.578, 0.488), 0.46, 0.10)
    yellow = K.mat("M_PaintYellow", (0.80, 0.56, 0.09), 0.48, 0.08)
    orange = K.mat("M_PaintOrange", (0.70, 0.268, 0.062), 0.48, 0.10)
    deep = K.mat("M_SteelDeep", (0.135, 0.16, 0.18), 0.58, 0.45)
    bare = K.mat("M_BareSteel", (0.40, 0.43, 0.455), 0.34, 0.55)
    rubber = K.mat("M_Rubber", (0.052, 0.058, 0.060), 0.86, 0.0)

    h = Hero("ServiceShed")

    # ------------------------------------------------------------ 柱 + 梁
    rear_beam_bottom = under(-COL_Z) - RAFTER_T            # 2.899
    front_beam_bottom = under(COL_Z) - RAFTER_T            # 3.141
    col_rear_h = rear_beam_bottom - 0.16
    col_front_h = front_beam_bottom - 0.16

    for x in (-COL_X, COL_X):
        for z, hh in ((COL_Z, col_front_h), (-COL_Z, col_rear_h)):
            N.add_h_column(h, x, z, 0.0, hh, deep, cream)
            N.add_foot(h, x, z, 0.44, 0.36, deep, bare, deep,
                       bolts=((-1.0, -1.0),))
            # 柱脚焊道（两条，沿 z 走向）
            h.weld([(x - 0.10, 0.038, z - 0.07), (x - 0.10, 0.038, z + 0.07)], deep, r=0.0055)
            h.weld([(x + 0.10, 0.038, z - 0.07), (x + 0.10, 0.038, z + 0.07)], deep, r=0.0055)

    N.add_beam_x(h, -COL_X - 0.30, COL_X + 0.30, rear_beam_bottom, -COL_Z, cream, deep)
    N.add_beam_x(h, -COL_X - 0.30, COL_X + 0.30, front_beam_bottom, COL_Z, cream, deep)

    # 梁柱节点：节点板 + 螺栓行 + 焊道
    for sx in (-1.0, 1.0):
        for sz, bb in ((-1.0, rear_beam_bottom), (1.0, front_beam_bottom)):
            x = sx * COL_X
            z = sz * COL_Z
            h.plate((0.30, 0.26, 0.012), (x, bb + 0.13, z + sz * 0.086), deep,
                    thickness=0.012, bevel=0.003, fold=None)
            if sz > 0.0:
                # 前节点是检修面：节点板 + 螺栓；后节点藏在背墙里，只焊不栓
                for bx in (-0.09, 0.09):
                    N.add_bolt(h, (x + bx, bb + 0.05, z + sz * 0.094), bare, axis="zp",
                               d=0.018, head_h=0.011, phase=2.4 * bx + 0.7 * x)
            h.weld([(x - 0.13, bb + 0.012, z + sz * 0.078),
                    (x + 0.13, bb + 0.012, z + sz * 0.078)], deep, r=0.0055)

    # ------------------------------------------------------------ 椽条
    for x in (-2.40, 0.0, 2.40):
        N.add_beam_z(h, -COL_Z, COL_Z, under(0.0) - RAFTER_T, x, cream, deep,
                     depth=0.10, tall=RAFTER_T, tf=0.016, tw=0.009, tilt=TILT)

    # ------------------------------------------------------------ 屋面板
    sheet = N.corrugated(6.24, 3.10, thick=SHEET_T, period=0.34, amp=0.040, base=-1.55,
                         seg_per=4)
    h.add(sheet, cream, loc=(0.0, RY, 0.0), rot=(TILT - 90.0, 0.0, 0.0))
    # 檐口封边 + 两侧收边
    h.add(bm_box((6.24, 0.095, 0.018), bevel=0.004, segments=2), cream,
          loc=(0.0, RY + SLOPE * 1.545 + 0.052, 1.545), rot=(TILT, 0.0, 0.0))
    for sx in (-1.0, 1.0):
        h.add(bm_box((0.018, 0.062, 3.08), bevel=0.003, segments=2), bare,
              loc=(sx * 3.115, RY + 0.004, 0.0), rot=(TILT, 0.0, 0.0))
    # 檐沟：檐口内侧一条 U 形槽（底 + 两侧壁，0.012 钢板折弯）
    GY = under(1.40) - 0.062
    h.add(bm_box((5.86, 0.012, 0.14), bevel=0.003, segments=2), deep, loc=(0.0, GY, 1.40))
    for sz in (-1.0, 1.0):
        h.add(bm_box((5.86, 0.062, 0.012), bevel=0.003, segments=2), deep,
              loc=(0.0, GY + 0.031, 1.40 + sz * 0.066))

    # ------------------------------------------------------------ 背墙
    WALL_TOP = 2.42
    back = N.corrugated(5.86, WALL_TOP - 0.10, thick=0.008, period=0.30, amp=0.038, base=0.10,
                        seg_per=2)
    h.add(back, cream, loc=(0.0, 0.0, -1.13), rot=(0.0, 180.0, 0.0))
    # 檩条：下 / 中 / 上（贴墙内侧）
    for y, tall in ((0.14, 0.09), (1.25, 0.07), (WALL_TOP - 0.06, 0.09)):
        h.add(bm_box((5.86, tall, 0.05), bevel=0.003, segments=2), deep,
              loc=(0.0, y, -1.075))
    # 黄色踢脚（0.10 m，贴墙 12 mm 出挑）
    h.add(bm_box((5.86, 0.105, 0.014), bevel=0.003, segments=2), yellow,
          loc=(0.0, 0.175, -1.062))
    # 墙顶到梁的立柱（背墙通过三根立柱挂在梁上）
    for x in (-1.90, 0.0, 1.90):
        h.add(bm_box((0.06, rear_beam_bottom - WALL_TOP, 0.06), bevel=0.003, segments=2),
              deep, loc=(x, (rear_beam_bottom + WALL_TOP) * 0.5, -1.12))

    # ------------------------------------------------------------ 侧墙（西侧）
    side = N.corrugated(2.26, WALL_TOP - 0.10, thick=0.008, period=0.30, amp=0.038, base=0.10,
                        seg_per=2)
    h.add(side, cream, loc=(-2.62, 0.0, 0.0), rot=(0.0, -90.0, 0.0))
    for z in (-1.06, 1.06):
        h.add(bm_box((0.05, WALL_TOP - 0.16, 0.06), bevel=0.003, segments=2), deep,
              loc=(-2.585, WALL_TOP * 0.5, z))
    h.add(bm_box((0.055, 0.08, 2.26), bevel=0.003, segments=2), deep,
          loc=(-2.585, WALL_TOP - 0.06, 0.0))

    # ------------------------------------------------------------ 工作台
    WB_X = 0.40
    WB_Z = 0.65
    TOP_Y = 0.862
    # 台面：钢面板 + 前沿折边（板厚 20 mm，折边下翻 55 mm）
    h.add(bm_box((2.40, 0.020, 0.90), bevel=0.005, segments=3), bare,
          loc=(WB_X, TOP_Y - 0.010, WB_Z))
    h.add(bm_box((2.40, 0.055, 0.018), bevel=0.004, segments=2), bare,
          loc=(WB_X, TOP_Y - 0.038, WB_Z + 0.441))
    # 台面下框：四根方腿（立在柜体四角投影外，看得见承力）+ 两道横撑
    for x in (WB_X - 1.13, WB_X + 1.13):
        for z in (WB_Z - 0.41, WB_Z + 0.41):
            h.add(bm_box((0.075, TOP_Y - 0.030, 0.075), bevel=0.003, segments=2), deep,
                  loc=(x, (TOP_Y - 0.030) * 0.5, z))
    h.add(bm_box((2.34, 0.045, 0.045), bevel=0.003, segments=2), deep,
          loc=(WB_X, 0.20, WB_Z + 0.41))
    h.add(bm_box((2.34, 0.045, 0.045), bevel=0.003, segments=2), deep,
          loc=(WB_X, 0.20, WB_Z - 0.41))
    # 台下柜：柜体 + 两块柜门（3 mm 缝）+ 拉手
    h.add(bm_box((1.90, 0.62, 0.68), bevel=0.006, segments=3), deep,
          loc=(WB_X, 0.42, WB_Z))
    for sx in (-1.0, 1.0):
        h.add(bm_box((0.947, 0.50, 0.016), bevel=0.003, segments=2), deep,
              loc=(WB_X + sx * 0.4735, 0.44, WB_Z + 0.340))
        h.add(bm_box((0.11, 0.019, 0.019), bevel=0.004, segments=2), bare,
              loc=(WB_X + sx * 0.4735 - sx * 0.40, 0.47, WB_Z + 0.352))
        for by in (0.402, 0.538):
            h.add(bm_box((0.016, 0.016, 0.026), bevel=0.004, segments=2), bare,
                  loc=(WB_X + sx * 0.4735 - sx * 0.40, by, WB_Z + 0.343))
    # 台钳：铸体 + 两块钳口 + 丝杠 + 手柄
    VX = WB_X - 0.86
    h.add(bm_box((0.24, 0.115, 0.205), bevel=0.010, segments=3, taper=(0.86, 0.92)),
          orange, loc=(VX, TOP_Y + 0.058, WB_Z))
    h.add(bm_box((0.075, 0.060, 0.235), bevel=0.004, segments=2), bare,
          loc=(VX - 0.075, TOP_Y + 0.145, WB_Z))
    h.add(bm_box((0.075, 0.060, 0.235), bevel=0.004, segments=2), bare,
          loc=(VX + 0.075, TOP_Y + 0.145, WB_Z))
    h.add(S.bm_cyl(0.018, 0.22, seg=10), bare, loc=(VX, TOP_Y + 0.06, WB_Z + 0.10),
          axis="zp")
    h.add(bm_box((0.018, 0.26, 0.018), bevel=0.005, segments=2), bare,
          loc=(VX, TOP_Y + 0.06, WB_Z + 0.32))
    # 工具箱：箱体 + 盖 + 提手 + 橙色锁扣
    TX = WB_X + 0.72
    h.add(bm_box((0.56, 0.19, 0.30), bevel=0.008, segments=3), cream,
          loc=(TX, TOP_Y + 0.108, WB_Z))
    h.add(bm_box((0.57, 0.045, 0.31), bevel=0.006, segments=2), cream,
          loc=(TX, TOP_Y + 0.222, WB_Z))
    h.add(S.bm_tube([(TX - 0.11, TOP_Y + 0.246, WB_Z), (TX - 0.075, TOP_Y + 0.286, WB_Z),
                     (TX + 0.075, TOP_Y + 0.286, WB_Z), (TX + 0.11, TOP_Y + 0.246, WB_Z)],
                    0.009, seg=6), bare)
    h.add(bm_box((0.055, 0.075, 0.022), bevel=0.004, segments=2), orange,
          loc=(TX, TOP_Y + 0.16, WB_Z - 0.155))

    # ------------------------------------------------------------ 背墙挂板 + 软管
    h.add(bm_box((1.30, 0.72, 0.012), bevel=0.003, segments=2), deep,
          loc=(WB_X, 1.66, -1.108))
    for x in (-0.20, 0.20, 0.60):
        h.add(S.bm_tube([(WB_X + x, 1.86, -1.095), (WB_X + x, 1.80, -1.055)],
                        0.006, seg=6), bare)
    h.add(S.bm_torus(0.135, 0.015, seg_major=14, seg_minor=6, arc=0.86), rubber,
          loc=(WB_X + 0.60, 1.70, -1.09), rot=(-90.0, 0.0, 0.0))
    # 从挂板到台面的悬垂软管
    h.add(S.bm_tube([(WB_X - 0.55, 1.42, -1.10), (WB_X - 0.50, 1.20, -0.95),
                     (WB_X - 0.52, 1.02, -0.70), (WB_X - 0.62, 0.90, -0.40),
                     (WB_X - 0.70, 0.86, -0.10)], 0.016, seg=8), rubber)

    # ------------------------------------------------------------ 吊装工作灯
    lamp_x, lamp_z = 0.40, 0.20
    N.add_lamp(h, lamp_x, under(lamp_z) - 0.004, lamp_z, deep, bare,
               rod_drop=0.56, rim_r=0.20)
    # 灯位处的接线盒 + 沿椽条走的线管
    h.add(S.bm_tube([(0.40, under(lamp_z) + 0.02, 0.20), (0.40, under(lamp_z) - 0.03, 0.20)],
                    0.012, seg=8), deep)
    h.add(S.bm_tube([(0.52, under(0.20) - 0.02, 0.20), (1.90, under(0.20) - 0.05, 0.20),
                     (2.40, under(0.20) - 0.05, 0.20), (2.44, 2.60, 0.62),
                     (2.60, 1.46, 1.15)], 0.014, seg=6), deep)

    # ------------------------------------------------------------ 东柱线管 + 检修盒
    cxp = COL_X + 0.115
    h.add(S.bm_tube([(cxp, 0.30, 1.15), (cxp, 1.30, 1.15)], 0.026, seg=10), deep)
    h.add(bm_box((0.155, 0.20, 0.13), bevel=0.008, segments=2), deep,
          loc=(cxp, 1.42, 1.15))
    h.add(bm_box((0.11, 0.014, 0.10), bevel=0.003, segments=2), yellow,
          loc=(cxp + 0.079, 1.44, 1.15), rot=(0.0, 90.0, 0.0))
    # 管卡（一进一出各一道，不撒螺母）
    for y in (0.55, 0.95):
        h.add(bm_box((0.045, 0.028, 0.075), bevel=0.004, segments=2), bare,
              loc=(cxp + 0.012, y, 1.15))

    obj = N.finish_asset(h, {"ao_rays": 11, "ao_dist": 0.17, "seed": 13, "ground_z": 0.0})
    print("NAILONG_SERVICE_SHED tris=%d" % K.tri_count([obj]))
    N.report_mats(obj)
    N.report_bbox("ServiceShed", obj)
    N.check_islands(obj)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    S.export_glb(OUT, "ServiceShed")
    print("NAILONG_SERVICE_SHED exported", os.path.exists(OUT), os.path.getsize(OUT))


if __name__ == "__main__":
    main()
