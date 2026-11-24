"""ART-SAMPLE-001 · 第四幕英雄区：基础平台 + 敲钟机（静/动）+ 操作台

设计叙事（画面里要能读出"为什么长这样"）
------------------------------------
「一台架在天然洞厅里的共振检定台」。晶体不是摆件：它被砧座上的楔爪咬住，
用重锤敲击来读共振。整台机器的形状由三件事决定：

  1. **承力**：锤头 3.5 m、落点能量全部灌进砧座 → 砧座有独立传力路径
     （砧体 → 铸铁承台 → 灌浆 → 混凝土三次浇筑的垫层 → 岩基）。
  2. **对中**：摆锤必须每次落在同一点 → 立柱之间净空、横梁吊两个剖分轴承、
     轴上有止推环与键、锤头两侧有侧板法兰。
  3. **维护**：轴承要加脂、砧面要换、晶体要换 → 爬梯、注油杯、换板螺栓、
     楔爪、走线槽、卷扬、机装工作灯。

尺寸硬约束（与既有玩法/物理判定共用，不得改动）
------------------------------------------
  * 立柱中心 x = ±1.22，内侧面 |x| = 0.97；锤头半宽 ≤ 0.95（横向净空 20 mm）。
  * 摆动轴 y = 4.30，臂长 3.50，静止角 +2.5°，打击角 −30°。
  * 砧座中心 z = −1.74（局部），砧面顶 y = 1.175（主晶体坐在上面）。
  * 操作台交互锚点 (2.25, 1.15, 1.45) 不动。
  * 静部件不得进入 −30°..+74° 的锤头扫掠体。
"""

import math
import os
import random
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aqs_kit as A
import aq2kit as K
import hero_mats as HM
from aqs_kit import Hero, rrect_r
from aq2kit import D2R, TAU

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "project", "assets", "models", "aqs002")

# ------------------------------------------------------------------ 布局常量
LEG_X = 1.22
PIVOT_Y = 4.30
ARM = 3.50
BEAM_Y = 5.42
BEAM_BOT = 5.06
BEAM_TOP = 5.78
ANVIL_Z = -1.74
PLINTH_H = 0.34
PLATE_Y0 = 0.34
PLATE_Y1 = 0.45
PED_Y1 = 0.58
COL_Y0 = 0.72
COL_TOP = BEAM_BOT - 0.34
PLATE_C = (0.0, -0.45)
PLATE_SZ = (3.70, 4.00)
PLINTH_C = (0.20, -0.45)
PLINTH_SZ = (5.10, 4.70)
COL_W0, COL_D0 = 0.50, 0.44
COL_W1, COL_D1 = 0.38, 0.34
MACH_Z = 0.0         # 机器中心 z（立柱、横梁、吊架对称面；砧座在 -1.74）


def col_dim(t):
    """柱身收分：t=0 柱脚，t=1 柱顶。返回 (w, d, bulge, ring)。"""
    w = COL_W0 + (COL_W1 - COL_W0) * t
    d = COL_D0 + (COL_D1 - COL_D0) * t
    bulge = 0.024 * math.sin(math.pi * min(1.0, t * 1.35)) ** 2
    ring = 0.0
    for rc in (0.30, 0.66):
        dt = abs(t - rc)
        if dt < 0.030:
            ring = max(ring, 0.024 * (1.0 - dt / 0.030))
    return w, d, bulge, ring


def col_profile(t):
    w, d, bulge, ring = col_dim(t)
    return rrect_r(w + bulge + ring * 2.0, d + bulge + ring * 1.8,
                   0.042 + 0.008 * (1.0 - t), 4)


def gusset(y_base, y_top, z_front, depth, thick, mat):
    """竖直三角形加劲肋（薄板，沿 x 挤出）：(y,z) 里的直角三角形。"""
    prof = [(y_base, z_front), (y_base, z_front + depth), (y_top, z_front)]
    return A.bm_loft_x([(-thick * 0.5, prof), (thick * 0.5, prof)])


# ================================================================== 基础平台
def build_platform():
    m = HM.build_materials()
    h = Hero("Platform")
    conc, grout = m["M_Concrete"], m["M_Grout"]
    plate_m, yellow = m["M_PaintGrey"], m["M_PaintYellow"]
    bronze, steel = m["M_Bronze"], m["M_MachinedSteel"]

    cx, cz = PLINTH_C
    w, d = PLINTH_SZ

    # ================================================================ 混凝土垫层
    # P2：把"钢平台感"换成真正的浇筑混凝土——
    #   1. 三次浇筑，**每次高度不等**（0.11 / 0.13 / 0.10），层缝不是等距横线；
    #   2. 模板板块沿 x/z **不等分**（1.9 / 3.2 m 与 2.8 / 1.9 m），缝宽 6–11 mm 且带抖动；
    #   3. 每块模板面有 ±3 mm 的错位与 ±0.4° 的倾斜（装模公差）；
    #   4. 两处拆模崩角（不同高度/进深）+ 外露骨料；
    #   5. 三处砂浆脱落斑（浅凹 + 骨料外露）。
    rng = random.Random(2027)
    pour_h = [0.115, 0.135, PLINTH_H - 0.115 - 0.135]
    xcuts = [-w * 0.5, -w * 0.5 + 1.92, w * 0.5 - 3.20, w * 0.5]
    zcuts = [-d * 0.5, -d * 0.5 + 2.78, -d * 0.5 + 1.94, d * 0.5]
    zcuts = sorted(zcuts + [d * 0.5])
    y = 0.0
    for k, ph in enumerate(pour_h):
        y0, y1 = y, y + ph
        y += ph
        for i in range(len(xcuts) - 1):
            for j in range(len(zcuts) - 1):
                bx0, bx1 = xcuts[i], xcuts[i + 1]
                bz0, bz1 = zcuts[j], zcuts[j + 1]
                # 模板缝（内缩）与装模公差
                jx = rng.uniform(0.003, 0.0055)
                jz = rng.uniform(0.003, 0.0055)
                ox = rng.uniform(-0.0018, 0.0018)
                oz = rng.uniform(-0.0018, 0.0018)
                bw = (bx1 - bx0) - jx * 2.0
                bd = (bz1 - bz0) - jz * 2.0
                top = (y1 - 0.004) if k < len(pour_h) - 1 else y1
                secs = [(y0 + 0.004, rrect_r(bw - 0.008, bd - 0.008, 0.040, 3)),
                        (y0 + 0.010, rrect_r(bw, bd, 0.044, 3)),
                        (top - 0.008, rrect_r(bw, bd, 0.044, 3)),
                        (top, rrect_r(bw - 0.014, bd - 0.014, 0.038, 3))]
                h.add(A.bm_loft(secs), conc,
                      loc=(cx + (bx0 + bx1) * 0.5 + ox, 0.0, cz + (bz0 + bz1) * 0.5 + oz),
                      rot=(rng.uniform(-0.25, 0.25), 0.0, rng.uniform(-0.35, 0.35)),
                      soft=(0.0022, 5.0, 11 + k * 7 + i * 5 + j * 3))

    # ---- 拆模崩角 A（左前上角）：缺一块，露出骨料
    spall_a = (cx - w * 0.5 + 0.30, PLINTH_H - 0.14, cz + d * 0.5 - 0.26)
    h.add(A.rock_from_planes((0.44, 0.30, 0.40), seed=71, cuts=4, subdiv=2,
                             rough=0.004, bevel=0.004), conc, loc=spall_a)
    for i, (dx, dz, s) in enumerate([(0.12, -0.10, 0.055), (0.20, 0.04, 0.040),
                                     (0.06, 0.10, 0.032), (0.26, -0.02, 0.026)]):
        h.add(A.rock_from_planes((s, s * 0.9, s), seed=80 + i, cuts=4, subdiv=2,
                                 rough=0.0015, bevel=0.002), m["M_Talus"],
              loc=(spall_a[0] + dx, spall_a[1] + rng.uniform(-0.05, 0.05), spall_a[2] + dz))

    # ---- 拆模崩角 B（右前下角，位置/尺度与 A 不同）
    spall_b = (cx + w * 0.5 - 0.34, 0.13, cz + d * 0.5 - 0.30)
    h.add(A.rock_from_planes((0.30, 0.26, 0.34), seed=97, cuts=4, subdiv=2,
                             rough=0.004, bevel=0.003), conc, loc=spall_b)

    # ---- 砂浆脱落斑：三处浅凹 + 骨料外露（不是"贴一块石头"，而是同一块混凝土表面缺了浆）
    for pi, (px, py, pz, ps) in enumerate([(-1.55, PLINTH_H, 1.05, 0.30),
                                           (1.30, PLINTH_H, -0.35, 0.24),
                                           (-0.55, PLINTH_H, -1.55, 0.20)]):
        h.add(A.rock_from_planes((ps, 0.030, ps * 0.8), seed=120 + pi, cuts=5, subdiv=2,
                                 rough=0.0018, bevel=0.003), conc,
              loc=(cx + px, py - 0.016, cz + pz))
        for gi in range(5):
            gs = 0.016 + 0.010 * rng.random()
            h.add(A.rock_from_planes((gs, gs * 0.75, gs), seed=140 + pi * 7 + gi, cuts=3,
                                     subdiv=1, rough=0.001, bevel=0.0015), m["M_Talus"],
                  loc=(cx + px + rng.uniform(-ps * 0.38, ps * 0.38), py - 0.008,
                       cz + pz + rng.uniform(-ps * 0.30, ps * 0.30)))

    # ---- 铸铁承台（机加工面 + 倒棱 + 挡水唇缘）
    pw, pd = PLATE_SZ
    secs = [(PLATE_Y0, rrect_r(pw - 0.030, pd - 0.030, 0.075, 3)),
            (PLATE_Y0 + 0.014, rrect_r(pw, pd, 0.080, 3)),
            (PLATE_Y1 - 0.020, rrect_r(pw, pd, 0.080, 3)),
            (PLATE_Y1 - 0.004, rrect_r(pw - 0.020, pd - 0.020, 0.076, 3)),
            (PLATE_Y1, rrect_r(pw - 0.048, pd - 0.048, 0.070, 3))]
    h.add(A.bm_loft(secs), plate_m, loc=(PLATE_C[0], 0.0, PLATE_C[1]), soft=(0.0006, 18.0, 3))
    lip = 0.030
    for side in (-1, 1):
        h.add(A.bm_box((pw - 0.10, lip, 0.042), bevel=0.006, segments=2), steel,
              loc=(PLATE_C[0], PLATE_Y1 + lip * 0.5, PLATE_C[1] + side * (pd * 0.5 - 0.032)))
    h.add(A.bm_box((0.042, lip, pd - 0.10), bevel=0.006, segments=2), steel,
          loc=(PLATE_C[0] - pw * 0.5 + 0.032, PLATE_Y1 + lip * 0.5, PLATE_C[1]))

    # ---- 灌浆收口：承台四周一圈斜坡（机体与混凝土的真实接触方式）
    gs = 0.052
    for side in (-1, 1):
        # 沿 x 的两条
        h.add(A.bm_box((pw + gs, 0.034, 0.048), bevel=0.010, segments=2), grout,
              loc=(PLATE_C[0], PLATE_Y0 + 0.012, PLATE_C[1] + side * (pd * 0.5 + gs * 0.30)),
              rot=(side * 16.0, 0.0, 0.0))
        # 沿 z 的两条
        h.add(A.bm_box((0.048, 0.034, pd + gs), bevel=0.010, segments=2), grout,
              loc=(PLATE_C[0] + side * (pw * 0.5 + gs * 0.30), PLATE_Y0 + 0.012, PLATE_C[1]),
              rot=(0.0, -side * 16.0, 0.0))

    # ---- 地脚螺栓（M30 × 14）：六角头 + 垫圈 + 灌浆凸台
    spots = []
    for i in range(4):
        t = (i + 0.5) / 4.0
        spots.append((PLATE_C[0] - pw * 0.5 + 0.10 + (pw - 0.20) * t, PLATE_C[1] - pd * 0.5 + 0.072))
        spots.append((PLATE_C[0] - pw * 0.5 + 0.10 + (pw - 0.20) * t, PLATE_C[1] + pd * 0.5 - 0.072))
    for i in range(3):
        t = (i + 0.5) / 3.0
        spots.append((PLATE_C[0] - pw * 0.5 + 0.072, PLATE_C[1] - pd * 0.5 + 0.48 + (pd - 0.96) * t))
        spots.append((PLATE_C[0] + pw * 0.5 - 0.072, PLATE_C[1] - pd * 0.5 + 0.48 + (pd - 0.96) * t))
    for (bx, bz) in spots:
        h.bolt((bx, PLATE_Y1, bz), bronze, axis="up", d=0.030, head_h=0.019,
               washer_mat=steel, boss=0.011, boss_mat=grout)

    # ---- 排水明沟（承台前方、离垫层边缘 0.25 m）+ 格栅 + 落水管
    # 放在垫层内侧：贴在立面上的通长沟会在近景读成一排"梳齿"。
    ch_len, ch_z, ch_x = 3.20, PLATE_C[1] + pd * 0.5 + 0.16, PLATE_C[0]
    u = [(-0.070, 0.0), (-0.070, -0.070), (0.070, -0.070), (0.070, 0.0)]
    h.add(A.bm_loft_x([(ch_x - ch_len * 0.5, [(PLINTH_H + p[1], ch_z + p[0]) for p in u]),
                       (ch_x + ch_len * 0.5, [(PLINTH_H + p[1], ch_z + p[0]) for p in u])],
                      close=False, cap_start=False, cap_end=False), m["M_DarkSteel"])
    # 格栅：栅条沉在沟内 2 cm，不外露成"梳齿"
    for i in range(13):
        gx = ch_x - ch_len * 0.5 + 0.16 + i * (ch_len - 0.32) / 12.0
        h.add(A.bm_box((0.022, 0.016, 0.120), bevel=0.002, segments=1), steel,
              loc=(gx, PLINTH_H - 0.022, ch_z))
    h.add(A.bm_cyl(0.040, 0.28, seg=14), m["M_DarkSteel"],
          loc=(ch_x + ch_len * 0.5 - 0.05, PLINTH_H - 0.20, ch_z), axis="down")

    # ---- 安全踢脚带（面漆）
    for side in (-1, 1):
        h.add(A.bm_box((w - 0.16, 0.082, 0.013), bevel=0.004, segments=2), yellow,
              loc=(cx, PLINTH_H - 0.052, cz + side * (d * 0.5 + 0.004)))
    h.add(A.bm_box((0.013, 0.082, d - 0.16), bevel=0.004, segments=2), yellow,
          loc=(cx + w * 0.5 + 0.004, PLINTH_H - 0.052, cz))

    obj = h.finish(smooth=True, split_angle=30.0,
                   bake=dict(ao_rays=8, ao_dist=0.16, seed=17, mat_gain=HM.WEAR_GAIN))
    A.report("Platform", obj)
    return obj


# ================================================================== 静部件
def build_static():
    m = HM.build_materials()
    h = Hero("PressStatic")
    cream, orange, yellow = m["M_PaintCream"], m["M_PaintOrange"], m["M_PaintYellow"]
    grey = m["M_PaintGrey"]
    cast, dark = m["M_CastSteel"], m["M_DarkSteel"]
    bare, mach = m["M_BareSteel"], m["M_MachinedSteel"]
    bronze, copper, rubber = m["M_Bronze"], m["M_Copper"], m["M_Rubber"]
    glass = m["M_Glass"]

    # ---------------------------------------------------------- 机座鞍座
    SECS_C = -0.36
    secs = [(PLATE_Y1, rrect_r(3.26, 3.62, 0.14, 4)),
            (PLATE_Y1 + 0.028, rrect_r(3.40, 3.76, 0.16, 4)),
            (PED_Y1 - 0.060, rrect_r(3.28, 3.64, 0.14, 4)),
            (PED_Y1 - 0.016, rrect_r(3.24, 3.60, 0.13, 4)),
            (PED_Y1, rrect_r(3.16, 3.52, 0.12, 4))]
    h.add(A.bm_loft(secs), cast, loc=(0.0, 0.0, SECS_C), soft=(0.0012, 8.0, 23))
    # 鞍座加劲肋（四角，带焊道）
    for sx in (-1, 1):
        for sz in (-1, 1):
            x = sx * 1.05
            zf = MACH_Z + sz * 1.08
            h.add(gusset(PLATE_Y1 + 0.02, PED_Y1 + 0.10, zf, -sz * 0.30, 0.030, cast),
                  cast, loc=(x, 0.0, 0.0))
            h.weld([(x, PLATE_Y1 + 0.03, zf), (x, (PLATE_Y1 + PED_Y1) * 0.5 + 0.04, zf - sz * 0.12),
                    (x, PED_Y1 + 0.09, zf - sz * 0.24)], cast, r=0.0055, seed=4)
    # 鞍座上的地脚螺栓（把鞍座压在承台上）
    for bx in (-1.30, -0.55, 0.55, 1.30):
        for bz in (-1.30, 0.55):
            h.bolt((bx, PED_Y1, MACH_Z + bz), bronze, axis="up", d=0.024, head_h=0.016,
                   washer_mat=bare)

    # ---------------------------------------------------------- 立柱
    for side in (-1, 1):
        x = side * LEG_X
        h.add(A.bm_box((0.74, 0.026, 0.70), bevel=0.008, segments=2), mach,
              loc=(x, PED_Y1 + 0.013, MACH_Z))
        foot = [(PED_Y1 + 0.026, rrect_r(0.70, 0.66, 0.045, 3)),
                (PED_Y1 + 0.058, rrect_r(0.80, 0.76, 0.055, 3)),
                (PED_Y1 + 0.126, rrect_r(0.78, 0.74, 0.050, 3)),
                (COL_Y0, rrect_r(0.62, 0.58, 0.040, 3))]
        h.add(A.bm_loft(foot), cast, loc=(x, 0.0, MACH_Z), soft=(0.0009, 12.0, 5))
        for bx, bz in ((-0.29, -0.27), (0.29, -0.27), (-0.29, 0.27), (0.29, 0.27)):
            h.bolt((x + bx, PED_Y1 + 0.058, MACH_Z + bz), bronze, axis="up",
                   d=0.024, head_h=0.016, washer_mat=bare)
        h.weld([(x - 0.34, COL_Y0 - 0.003, MACH_Z), (x + 0.34, COL_Y0 - 0.003, MACH_Z)],
               cast, r=0.0052, seed=9)

        # 柱身：连续收分剖面
        n = 30
        secs = []
        for i in range(n + 1):
            t = i / n
            y = COL_Y0 + (COL_TOP - COL_Y0) * t
            secs.append((y, col_profile(t)))
        h.add(A.bm_loft(secs), cream, loc=(x, 0.0, MACH_Z), soft=(0.0007, 14.0, 31))

        # 三道铸造环带（沿收分走，环带上有螺栓排）
        for rc in (0.22, 0.52, 0.82):
            ry = COL_Y0 + (COL_TOP - COL_Y0) * rc
            w, d, bulge, _ = col_dim(rc)
            band = [(ry - 0.055, rrect_r(w + bulge + 0.020, d + bulge + 0.018, 0.044, 4)),
                    (ry - 0.030, rrect_r(w + bulge + 0.034, d + bulge + 0.030, 0.046, 4)),
                    (ry + 0.030, rrect_r(w + bulge + 0.034, d + bulge + 0.030, 0.046, 4)),
                    (ry + 0.055, rrect_r(w + bulge + 0.020, d + bulge + 0.018, 0.044, 4))]
            h.add(A.bm_loft(band), cast, loc=(x, 0.0, MACH_Z))
            for k in range(4):
                ang = TAU * k / 4 + math.pi / 4
                bx = x + (w + bulge + 0.030) * 0.5 * math.cos(ang)
                bz = MACH_Z + (d + bulge + 0.030) * 0.5 * math.sin(ang)
                h.bolt((bx, ry, bz), bronze, axis="up", d=0.014, head_h=0.009, washer=False)

        # 柱脚护板（工业橙）：折边 + 竖向压筋 + 固定螺栓
        # 一整片平漆面在 1 m 处一定会读成"塑料块"，所以这里给它冲压件的特征。
        h.add(A.bm_loft([(COL_Y0, rrect_r(0.56, 0.52, 0.030, 3)),
                         (COL_Y0 + 0.34, rrect_r(0.56, 0.52, 0.030, 3)),
                         (COL_Y0 + 0.40, rrect_r(0.54, 0.50, 0.030, 3))]),
              orange, loc=(x, 0.0, MACH_Z))
        for sz in (-1, 1):
            h.add(A.bm_box((0.545, 0.012, 0.022), bevel=0.004, segments=2), orange,
                  loc=(x, COL_Y0 + 0.392, MACH_Z + sz * 0.252))
        for k in (-1, 0, 1):
            h.add(A.bm_box((0.013, 0.250, 0.011), bevel=0.003, segments=2), orange,
                  loc=(x + k * 0.16, COL_Y0 + 0.195, MACH_Z + 0.266))
        for sx in (-1, 1):
            h.add(A.bm_cyl(0.026, 0.007, seg=12), bare,
                  loc=(x + sx * 0.215, COL_Y0 + 0.315, MACH_Z + 0.268), rot=(90.0, 0.0, 0.0))
            h.bolt((x + sx * 0.215, COL_Y0 + 0.315, MACH_Z + 0.263), bronze,
                   axis="zp", d=0.014, head_h=0.010, washer=False)
        # 柱脚缓冲橡胶（锤头静止时靠在这里）
        h.add(A.bm_box((0.16, 0.20, 0.09), bevel=0.02, segments=2), rubber,
              loc=(x - side * 0.16, COL_Y0 + 0.44, MACH_Z))
        # 柱头：法兰 + 螺栓
        cap = [(COL_TOP, rrect_r(0.46, 0.42, 0.035, 3)),
               (COL_TOP + 0.10, rrect_r(0.60, 0.56, 0.045, 3)),
               (COL_TOP + 0.24, rrect_r(0.60, 0.56, 0.045, 3)),
               (BEAM_BOT, rrect_r(0.50, 0.46, 0.040, 3))]
        h.add(A.bm_loft(cap), cast, loc=(x, 0.0, MACH_Z), soft=(0.0008, 12.0, 37))
        for bx, bz in ((-0.22, -0.20), (0.22, -0.20), (-0.22, 0.20), (0.22, 0.20)):
            h.bolt((x + bx, COL_TOP + 0.17, MACH_Z + bz), bronze, axis="up",
                   d=0.020, head_h=0.014, washer_mat=bare)
        # 柱头与横梁之间的三角托
        for sz in (-1, 1):
            h.add(gusset(BEAM_BOT - 0.52, BEAM_BOT - 0.02, MACH_Z + sz * 0.23,
                         -sz * 0.34, 0.026, cast), cast, loc=(x, 0.0, 0.0))

    # ---------------------------------------------------------- 横梁（工字铸钢）
    prof = A.i_profile(BEAM_BOT, BEAM_TOP, 0.0, 0.115, 0.115, 0.125, 0.315, r=0.030, seg=3)
    secs = [(-1.58, [(p[0], p[1] * 0.94) for p in prof]), (-1.50, prof),
            (1.50, prof), (1.58, [(p[0], p[1] * 0.94) for p in prof])]
    h.add(A.bm_loft_x(secs), cream, loc=(0.0, 0.0, MACH_Z), soft=(0.0007, 11.0, 41))
    # 端座 + 铆钉排
    end_pts = [(BEAM_BOT, -0.335), (BEAM_TOP, -0.335), (BEAM_TOP, 0.335), (BEAM_BOT, 0.335)]
    for side in (-1, 1):
        h.add(A.bm_loft_x([(side * 1.58, end_pts),
                           (side * 1.68, [(p[0], p[1] * 0.93) for p in end_pts])]),
              cast, loc=(0.0, 0.0, MACH_Z))
        for i in range(5):
            yy = BEAM_BOT + 0.14 + i * 0.11
            for zz in (-0.30, 0.30):
                h.bolt((side * 1.645, yy, MACH_Z + zz), bronze,
                       axis="xp" if side > 0 else "xn", d=0.015, head_h=0.010, washer=False)
    # 铭牌座 + 吊耳
    h.add(A.bm_box((0.60, 0.014, 0.28), bevel=0.004, segments=2), mach,
          loc=(-0.62, BEAM_TOP + 0.007, MACH_Z))
    for side in (-1, 1):
        h.add(A.bm_torus(0.070, 0.019, seg_major=16, seg_minor=8, arc=0.60), bare,
              loc=(side * 0.44, BEAM_TOP + 0.06, MACH_Z), rot=(0.0, 0.0, 0.0))

    # ---------------------------------------------------------- 吊架 + 剖分轴承
    for side in (-1, 1):
        x = side * 0.62
        hang = [(PIVOT_Y - 0.30, rrect_r(0.46, 1.02, 0.10, 4)),
                (PIVOT_Y - 0.10, rrect_r(0.44, 0.94, 0.09, 4)),
                (PIVOT_Y + 0.14, rrect_r(0.40, 0.82, 0.08, 4)),
                (BEAM_BOT - 0.08, rrect_r(0.34, 0.62, 0.06, 4))]
        h.add(A.bm_loft(hang), cream, loc=(x, 0.0, MACH_Z), soft=(0.0008, 12.0, 47))
        for zz in (-0.36, 0.36):
            h.add(gusset(BEAM_BOT - 0.44, BEAM_BOT - 0.02, MACH_Z + zz * 0.55,
                         -zz * 0.20, 0.022, cream), cream, loc=(x, 0.0, 0.0))
        h.add(A.bm_lathe([(0.0, -0.155), (0.235, -0.155), (0.255, -0.140), (0.255, -0.020),
                          (0.235, -0.004), (0.0, -0.004)], seg=26),
              cast, loc=(x, PIVOT_Y, MACH_Z), rot=(0.0, 0.0, 90.0))
        h.add(A.bm_lathe([(0.0, 0.004), (0.235, 0.004), (0.255, 0.020), (0.255, 0.140),
                          (0.235, 0.155), (0.0, 0.155)], seg=26),
              cast, loc=(x, PIVOT_Y, MACH_Z), rot=(0.0, 0.0, 90.0))
        for i in range(4):
            a = TAU * i / 4 + math.pi / 4
            h.bolt((x, PIVOT_Y + 0.135 * math.cos(a), MACH_Z + 0.135 * math.sin(a)),
                   bronze, axis="xp" if side > 0 else "xn", d=0.014, head_h=0.010, washer=False)
        h.add(A.bm_lathe([(0.0, 0.0), (0.030, 0.0), (0.030, 0.028), (0.022, 0.048), (0.0, 0.048)],
                         seg=12), bronze, loc=(x, PIVOT_Y + 0.155, MACH_Z))
        h.add(A.bm_tube([(x, PIVOT_Y + 0.19, MACH_Z), (x, PIVOT_Y + 0.42, MACH_Z),
                         (x + side * 0.12, PIVOT_Y + 0.58, MACH_Z - 0.22)], 0.008, seg=6), copper)
    # 轴 + 止推环 + 键
    h.add(A.bm_cyl(0.125, 1.52, seg=26), mach, loc=(0.0, PIVOT_Y, MACH_Z), rot=(0.0, 0.0, 90.0))
    for side in (-1, 1):
        h.add(A.bm_lathe([(0.0, -0.02), (0.175, -0.02), (0.175, 0.020), (0.0, 0.020)], seg=22),
              cast, loc=(side * 0.83, PIVOT_Y, MACH_Z), rot=(0.0, 0.0, 90.0))
        h.add(A.bm_cyl(0.040, 0.070, seg=6), bronze, loc=(side * 0.86, PIVOT_Y, MACH_Z),
              rot=(0.0, 0.0, 90.0))
        h.add(A.bm_box((0.055, 0.028, 0.020), bevel=0.004, segments=2), bare,
              loc=(side * 0.76, PIVOT_Y + 0.105, MACH_Z))

    # ---------------------------------------------------------- 砧座
    az = ANVIL_Z
    # 砧基（铸铁块，坐在鞍座顶面上）
    h.add(A.bm_loft([(PED_Y1, rrect_r(1.90, 1.40, 0.10, 4)),
                     (PED_Y1 + 0.030, rrect_r(1.84, 1.34, 0.10, 4)),
                     (COL_Y0, rrect_r(1.74, 1.26, 0.09, 4))]), cast, loc=(0.0, 0.0, az),
          soft=(0.0010, 10.0, 53))
    for bx in (-0.70, 0.0, 0.70):
        for bz in (-0.50, 0.50):
            h.bolt((bx, PED_Y1 + 0.030, az + bz), bronze, axis="up", d=0.026, head_h=0.017,
                   washer_mat=bare)
    # 砧体：一次成型的厚铸件
    body = [(COL_Y0, rrect_r(1.68, 1.22, 0.09, 4)),
            (COL_Y0 + 0.060, rrect_r(1.74, 1.26, 0.10, 4)),
            (0.90, rrect_r(1.50, 1.10, 0.08, 4)),
            (1.020, rrect_r(1.44, 1.06, 0.08, 4)),
            (1.105, rrect_r(1.50, 1.10, 0.08, 4))]
    h.add(A.bm_loft(body), cast, loc=(0.0, 0.0, az), soft=(0.0010, 9.0, 59))
    for side in (-1, 1):
        h.add(A.bm_lathe([(0.0, 0.0), (0.085, 0.0), (0.085, 0.032), (0.052, 0.052), (0.0, 0.052)],
                         seg=16), cast, loc=(side * 0.74, 0.80, az), rot=(0.0, 0.0, 90.0))
    # 打击面（可更换板）+ 沉头螺栓
    h.add(A.bm_box((1.42, 0.062, 1.06), bevel=0.013, segments=3), mach,
          loc=(0.0, 1.140, az), soft=(0.0004, 26.0, 61))
    for bx in (-0.56, 0.0, 0.56):
        for bz in (-0.40, 0.40):
            h.bolt((bx, 1.170, az + bz), bare, axis="up", d=0.018, head_h=0.007, washer=False)
    # 打击面边缘的崩口（长期受击的真实痕迹）
    for i, (dx, dz, s) in enumerate([(0.66, -0.44, 0.105), (-0.62, 0.40, 0.075)]):
        h.add(A.rock_from_planes((s, s * 0.45, s * 0.8), seed=90 + i, cuts=3, subdiv=1,
                                 rough=0.0015, bevel=0.0015), bare,
              loc=(dx, 1.170, az + dz))
    # 晶体座环（机加工）+ 三块楔爪
    h.add(A.bm_lathe([(0.62, 1.168), (0.78, 1.168), (0.78, 1.194), (0.71, 1.208),
                      (0.62, 1.208)], seg=40), mach, loc=(0.0, 0.0, az))
    for i in range(3):
        a = math.pi * 0.5 + TAU * i / 3
        jx, jz = 0.80 * math.cos(a), az + 0.80 * math.sin(a)
        jaw = [(1.176, rrect_r(0.30, 0.34, 0.04, 3)),
               (1.300, rrect_r(0.26, 0.28, 0.035, 3)),
               (1.460, rrect_r(0.20, 0.22, 0.030, 3))]
        h.add(A.bm_loft(jaw), cast, loc=(jx, 0.0, jz), soft=(0.0006, 14.0, 67))
        h.bolt((jx, 1.400, jz), bronze, axis="up", d=0.016, head_h=0.011, washer=False)

    # ---------------------------------------------------------- 侧面检修梯
    # 挂在右立柱外侧（主视区之外）：只有梯梁与踏棍，不做护笼（护笼在近景会读成货架）
    lx = 1.80
    for sz in (-0.20, 0.20):
        h.add(A.bm_box((0.038, 3.60, 0.038), bevel=0.005, segments=2), dark,
              loc=(lx, 2.72, MACH_Z + sz))
    for i in range(10):
        h.add(A.bm_cyl(0.014, 0.40, seg=8), bare,
              loc=(lx, 1.10 + i * 0.34, MACH_Z), rot=(90.0, 0.0, 0.0))
    for sz in (-0.20, 0.20):
        h.add(A.bm_box((0.14, 0.030, 0.14), bevel=0.006, segments=2), dark,
              loc=(lx, PLATE_Y1 + 0.015, MACH_Z + sz))
    # 电缆桥架：贴着承台侧面走（横在垫层上会读成"掉在地上的一根棍子"）
    h.add(A.bm_box((0.10, 0.075, 0.90), bevel=0.008, segments=2), grey,
          loc=(1.58, PLATE_Y1 + 0.045, MACH_Z + 0.55))
    for i in range(3):
        h.add(A.bm_cyl(0.026, 0.040, seg=8), bronze,
              loc=(1.58, PLATE_Y1 + 0.095, MACH_Z + 0.20 + i * 0.35))

    # ---------------------------------------------------------- 机装工作灯（光源有来源）
    for i, (lx, lz2) in enumerate([(-1.58, MACH_Z + 0.46), (1.58, MACH_Z - 0.46)]):
        ly = BEAM_BOT - 0.26
        h.add(A.bm_tube([(lx * 0.80, ly + 0.20, lz2 * 0.5), (lx, ly + 0.10, lz2),
                         (lx, ly - 0.02, lz2)], 0.020, seg=8), dark)
        h.add(A.bm_lathe([(0.0, 0.0), (0.072, 0.0), (0.100, -0.030), (0.142, -0.112),
                          (0.152, -0.136), (0.140, -0.146)], seg=22), grey,
              loc=(lx, ly - 0.02, lz2))
        h.add(A.bm_lathe([(0.0, -0.128), (0.112, -0.128), (0.120, -0.138), (0.0, -0.138)],
                         seg=20), glass, loc=(lx, ly - 0.02, lz2))
        h.add(A.bm_box((0.070, 0.042, 0.070), bevel=0.006, segments=2), dark,
              loc=(lx, ly + 0.03, lz2))
        h.bolt((lx, ly - 0.06, lz2), bronze, axis="up", d=0.011, head_h=0.007, washer=False)

    obj = h.finish(smooth=True, split_angle=30.0,
                   bake=dict(ao_rays=9, ao_dist=0.17, seed=23, mat_gain=HM.WEAR_GAIN))
    A.report("PressStatic", obj)
    return obj


# ================================================================== 摆动件
def build_swing():
    """摆臂 + 锤头。原点在摆动轴心，挂在 PendulumPivot 下跟随真实物理角。"""
    m = HM.build_materials()
    h = Hero("SwingArm")
    cream, yellow = m["M_PaintCream"], m["M_PaintYellow"]
    cast = m["M_CastSteel"]
    bare, mach = m["M_BareSteel"], m["M_MachinedSteel"]
    bronze, rubber, dark = m["M_Bronze"], m["M_Rubber"], m["M_DarkSteel"]

    # 摆臂：**一根整铸的锥形臂**（不是两片板 + 三道撑 —— 那在正面读成"梯子"）
    secs = []
    for i in range(13):
        t = i / 12.0
        y = -0.02 - (ARM - 0.24) * t
        w = 0.30 + 0.26 * t          # 轴向宽度
        dd = 0.26 + 0.20 * t         # 厚度
        secs.append((y, rrect_r(w, dd, 0.045 + 0.02 * t, 4)))
    h.add(A.bm_loft(secs), cream, loc=(0.0, 0.0, 0.0), soft=(0.0007, 14.0, 71))
    # 两侧铸造肋（真实加劲，不是横撑）
    for side in (-1, 1):
        h.add(A.bm_box((0.030, ARM - 0.55, 0.10), bevel=0.008, segments=2), cream,
              loc=(side * 0.10, -ARM * 0.52, 0.0))
    # 轴孔包头 + 端盖 + 5 颗螺栓
    h.add(A.bm_lathe([(0.0, -0.20), (0.245, -0.20), (0.285, -0.155), (0.285, 0.155),
                      (0.245, 0.20), (0.0, 0.20)], seg=26),
          cast, loc=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 90.0))
    for side in (-1, 1):
        h.add(A.bm_lathe([(0.135, -0.062), (0.210, -0.062), (0.210, 0.062), (0.135, 0.062)],
                         seg=22), mach, loc=(side * 0.205, 0.0, 0.0), rot=(0.0, 0.0, 90.0))
        for i in range(5):
            a = TAU * i / 5 + math.pi / 5
            h.bolt((side * 0.21, 0.185 * math.cos(a), 0.185 * math.sin(a)), bronze,
                   axis="xp" if side > 0 else "xn", d=0.014, head_h=0.010, washer=False)

    # 锤头不再由本脚本生成：改由 art-source/blender/build_head.py 做高模 + 烘焙，
    # 以 aqs002_head_low.glb（UV + 2048² 法线/AO/曲率）单独挂在摆动件下。

    obj = h.finish(smooth=True, split_angle=30.0,
                   bake=dict(ao_rays=8, ao_dist=0.16, seed=29, mat_gain=HM.WEAR_GAIN))
    A.report("SwingArm", obj)
    return obj


# ================================================================== 操作台
def build_console():
    m = HM.build_materials()
    h = Hero("PressConsole")
    cream, orange, yellow = m["M_PaintCream"], m["M_PaintOrange"], m["M_PaintYellow"]
    teal = m["M_PaintTeal"]
    cast, dark = m["M_CastSteel"], m["M_DarkSteel"]
    bare, mach = m["M_BareSteel"], m["M_MachinedSteel"]
    bronze, rubber = m["M_Bronze"], m["M_Rubber"]
    glass = m["M_Glass"]

    CX, CZ = 2.12, 1.30
    h.add(A.bm_loft([(PLATE_Y1 - 0.02, rrect_r(1.02, 0.86, 0.05, 3)),
                     (PLATE_Y1 + 0.04, rrect_r(0.96, 0.80, 0.05, 3)),
                     (0.86, rrect_r(0.92, 0.76, 0.05, 3)),
                     (0.92, rrect_r(0.96, 0.80, 0.05, 3))]),
          cream, loc=(CX, 0.0, CZ), soft=(0.0008, 13.0, 97))
    for sx in (-1, 1):
        for sz in (-1, 1):
            h.add(A.bm_lathe([(0.0, 0.0), (0.038, 0.0), (0.038, 0.012), (0.030, 0.014),
                              (0.030, 0.055), (0.0, 0.055)], seg=10), bare,
                  loc=(CX + sx * 0.40, PLATE_Y1 - 0.02, CZ + sz * 0.32))
    h.add(A.bm_box((0.86, 0.055, 0.46), bevel=0.012, segments=2), cream,
          loc=(CX, 0.90, CZ - 0.02), rot=(24.0, 0.0, 0.0))
    for i in range(3):
        gx = CX - 0.24 + i * 0.17
        h.add(A.bm_lathe([(0.0, 0.0), (0.070, 0.0), (0.078, 0.014), (0.070, 0.030),
                          (0.0, 0.030)], seg=20), mach,
              loc=(gx, 0.918, CZ - 0.048), rot=(-66.0, 0.0, 0.0))
        h.add(A.bm_cyl(0.058, 0.006, seg=20), teal,
              loc=(gx, 0.945, CZ - 0.038), rot=(-66.0, 0.0, 0.0))
    h.add(A.bm_cyl(0.062, 0.05, seg=14), cast, loc=(CX + 0.33, 0.93, CZ + 0.28))
    h.add(A.bm_box((0.042, 0.34, 0.042), bevel=0.006, segments=2), yellow,
          loc=(CX + 0.36, 1.09, CZ + 0.30), rot=(10.0, 0.0, 12.0))
    h.add(A.bm_cyl(0.052, 0.10, seg=12), rubber,
          loc=(CX + 0.38, 1.255, CZ + 0.32), rot=(0.0, 0.0, 76.0))
    h.add(A.bm_torus(0.13, 0.016, seg_major=18, seg_minor=8, arc=1.0), dark,
          loc=(CX - 0.30, 1.02, CZ + 0.34), rot=(0.0, 90.0, 0.0))
    for i in range(3):
        a = TAU * i / 3
        h.add(A.bm_cyl(0.010, 0.24, seg=6), dark,
              loc=(CX - 0.30, 1.02 + 0.11 * math.sin(a), CZ + 0.34 + 0.11 * math.cos(a)),
              rot=(90.0, 0.0, 0.0))
    # 曳引轮（卷扬）
    h.add(A.bm_lathe([(0.0, -0.075), (0.145, -0.075), (0.165, -0.050), (0.165, 0.050),
                      (0.145, 0.075), (0.0, 0.075)], seg=24), bronze,
          loc=(CX, 1.12, CZ - 0.02), rot=(0.0, 0.0, 90.0))
    for i in range(8):
        a = TAU * i / 8
        h.add(A.bm_box((0.028, 0.10, 0.028), bevel=0.004, segments=2), cast,
              loc=(CX, 1.12 + 0.11 * math.cos(a), CZ - 0.02 + 0.11 * math.sin(a)))
    h.add(A.bm_lathe([(0.03, -0.10), (0.20, -0.10), (0.22, -0.08), (0.22, 0.08),
                      (0.20, 0.10), (0.03, 0.10)], seg=24), dark,
          loc=(CX, 1.12, CZ - 0.02), rot=(0.0, 0.0, 90.0))
    # 柜门 + 铰链 + 锁扣 + 铭牌座
    h.add(A.bm_box((0.62, 0.50, 0.022), bevel=0.008, segments=2), cream,
          loc=(CX, 0.46, CZ + 0.40))
    for i in range(2):
        h.add(A.bm_box((0.07, 0.055, 0.030), bevel=0.006, segments=2), bare,
              loc=(CX - 0.30, 0.34 + i * 0.28, CZ + 0.415))
    h.add(A.bm_cyl(0.020, 0.075, seg=8), bare, loc=(CX + 0.24, 0.46, CZ + 0.415),
          rot=(0.0, 90.0, 0.0))
    h.add(A.bm_box((0.30, 0.10, 0.012), bevel=0.003, segments=2), yellow,
          loc=(CX, 0.78, CZ + 0.405))
    # 台灯：鹅颈臂 + 锥罩 + 玻璃
    neck = [(CX - 0.34, 0.92, CZ + 0.20), (CX - 0.38, 1.10, CZ + 0.26),
            (CX - 0.44, 1.24, CZ + 0.22), (CX - 0.42, 1.30, CZ + 0.10)]
    h.add(A.bm_tube(neck, 0.016, seg=8), dark)
    h.add(A.bm_lathe([(0.0, 0.0), (0.055, 0.0), (0.080, -0.030), (0.115, -0.100),
                      (0.120, -0.118)], seg=20), orange,
          loc=(CX - 0.42, 1.30, CZ + 0.10))
    h.add(A.bm_lathe([(0.0, -0.096), (0.095, -0.096), (0.100, -0.104), (0.0, -0.104)], seg=18),
          glass, loc=(CX - 0.42, 1.30, CZ + 0.10))
    h.add(A.bm_tube([(CX - 0.10, PLATE_Y1 + 0.02, CZ + 0.30), (CX - 0.22, 0.50, CZ + 0.44),
                     (CX - 0.30, 0.46, CZ + 0.50), (CX - 0.44, 0.47, CZ + 0.62)], 0.018, seg=8),
          rubber)

    obj = h.finish(smooth=True, split_angle=30.0,
                   bake=dict(ao_rays=9, ao_dist=0.15, seed=31, mat_gain=HM.WEAR_GAIN))
    A.report("PressConsole", obj)
    return obj


def main():
    K.reset_scene()
    HM.build_materials()
    build_platform()
    build_static()
    build_swing()
    build_console()
    A.export_glb(os.path.join(OUT, "aqs002_platform.glb"), "Platform")
    A.export_glb(os.path.join(OUT, "aqs002_press_static.glb"), "PressStatic")
    A.export_glb(os.path.join(OUT, "aqs002_swing_arm.glb"), "SwingArm")
    A.export_glb(os.path.join(OUT, "aqs002_console.glb"), "PressConsole")
    K.save_blend(os.path.join(ROOT, "art-source", "aqs002_press.blend"))
    print("AQS001_PRESS_OK")


main()










