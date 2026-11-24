"""ART-SAMPLE-001 · 相邻岩层：承台脚下的基岩台、层理断面、崩积与碎屑

为什么放在这里（空间故事）
--------------------------
混凝土垫层不是凭空铺在平地上的：它是**浇筑在基岩上**的。所以承台四周
（尤其背面与两侧）露出被打平的一层基岩台、层理断面和崩积碎石。
玩家在 1–2 m 看到的接触关系是：混凝土地坪 → 20–30 cm 高的基岩台阶 → 层理断面，
而不是"一块地板 + 一块石头"。

坐标：机器局部坐标（y=0 为洞厅地面，z 负方向朝向砧座/晶体）。
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aqs_kit as A
import aq2kit as K
import hero_mats as HM
from aqs_kit import Hero
from aq2kit import TAU, vnoise

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "project", "assets", "models", "aqs002")

# 与 build_press.py 的垫层一致
PLINTH_C = (0.20, -0.45)
PLINTH_SZ = (5.10, 4.70)


def slab(h, mat, cx, cz, sx, sy, sz, seed, yaw=0.0, strata=None):
    """一块被切割过的板状基岩：顶面近水平，四个侧面是解理面。"""
    bm = A.rock_from_planes((sx, sy, sz), seed=seed, cuts=7, subdiv=3,
                            rough=0.006, bevel=0.005, strata=strata)
    # 压成台阶：顶面削平
    top = max(v.co.y for v in bm.verts)
    for v in bm.verts:
        if v.co.y > top - 0.05:
            v.co.y = top - 0.05 + (v.co.y - (top - 0.05)) * 0.25
    h.add(bm, mat, loc=(cx, 0.0, cz), rot=(0.0, yaw, 0.0))


def build_rocks():
    m = HM.build_materials()
    h = Hero("RockHero")
    rock_a, rock_b, talus = m["M_Bedrock"], m["M_BedrockDark"], m["M_Talus"]

    x0 = PLINTH_C[0] - PLINTH_SZ[0] * 0.5     # 垫层左边 x
    x1 = PLINTH_C[0] + PLINTH_SZ[0] * 0.5
    z0 = PLINTH_C[1] - PLINTH_SZ[1] * 0.5     # 垫层后边 z（负方向）
    z1 = PLINTH_C[1] + PLINTH_SZ[1] * 0.5

    # ---------------------------------------------------------- 背面基岩台阶
    # 厚块状层理：每层 26–44 cm，层间 3–8 cm 硬错台。
    # （上一版是 6–7 cm 的"薄石板"，投影到 1 m 视距上读成硬纸板。）
    steps = [(-1.30, 2.20, 0.44, 4), (0.95, 2.10, 0.30, 7), (2.55, 1.30, 0.38, 11)]
    for i, (cx, sx, sy, sd) in enumerate(steps):
        slab(h, rock_a if i % 2 == 0 else rock_b, cx, z0 - 0.42 - i * 0.04,
             sx, sy, 1.10, 401 + i, yaw=(i - 1) * 4.0, strata=(0.13, 0.032))
    # 台阶面上再叠一层厚石板（层理断口），错开半个身位
    for i in range(4):
        cx = -1.55 + i * 1.02
        slab(h, talus, cx, z0 - 0.52, 0.94, 0.26, 0.66, 420 + i,
             yaw=-6.0 + i * 4.5, strata=(0.095, 0.022))

    # ---------------------------------------------------------- 两处层理断面（竖直岩壁）
    for i, (cx, cz, sx, sy, sz) in enumerate([(x0 - 0.62, z0 + 0.35, 1.40, 1.30, 1.70),
                                              (x1 + 0.60, z0 + 0.85, 1.20, 0.95, 1.45)]):
        bm = A.rock_from_planes((sx, sy, sz), seed=440 + i, cuts=8, subdiv=3,
                                rough=0.008, bevel=0.006, strata=(0.105, 0.026))
        # 朝垫层的一面切成近乎垂直的断面（读作开挖面）
        h.add(bm, rock_b if i else rock_a, loc=(cx, 0.0, cz),
              rot=(0.0, 18.0 if i else -14.0, 0.0))
        # 断面顶部的碎块
        for k in range(3):
            pb = A.rock_from_planes((0.20, 0.11, 0.17), seed=460 + i * 5 + k, cuts=4,
                                    subdiv=2, rough=0.004, bevel=0.003)
            h.add(pb, talus, loc=(cx + 0.30 * (k - 1), sy * 0.5 + 0.05,
                                  cz + 0.20 * (k - 1)), rot=(0.0, k * 21.0, 0.0))

    # ---------------------------------------------------------- 面向玩家的两处岩层断面
    # P3：玩家从 +z 走上来时，西侧与东侧各有一处"被开挖切断"的岩层立面，
    # 层厚 0.22/0.31 m 不等、断口朝向 ±x 与 +z 之间 —— 让 3–8 m 中景也有地质结构。
    for i, (cx, cz, sx, sy, sz, yaw) in enumerate([(-3.95, -1.85, 1.55, 1.55, 1.65, -38.0),
                                                   (3.90, 0.55, 1.30, 1.10, 1.40, 34.0)]):
        bm = A.rock_from_planes((sx, sy, sz), seed=610 + i, cuts=9, subdiv=3,
                                rough=0.009, bevel=0.006,
                                strata=(0.22 if i == 0 else 0.31, 0.040))
        h.add(bm, rock_a if i == 0 else rock_b, loc=(cx, 0.0, cz), rot=(0.0, yaw, 0.0))
        # 断面脚下的崩积（3 块，大小不一，不排成一条线）
        for k in range(3):
            s = 0.20 + 0.13 * ((k * 7 + i * 3) % 5) / 4.0
            pb = A.rock_from_planes((s * 1.5, s * 0.95, s * 1.2), seed=640 + i * 11 + k,
                                    cuts=5, subdiv=2, rough=0.004, bevel=0.003)
            h.add(pb, talus, loc=(cx + (k - 1) * (0.42 + 0.14 * i),
                                  s * 0.45,
                                  cz + 0.55 + 0.18 * ((k * 3 + 1) % 3)))

    # ---------------------------------------------------------- 中景过渡岩（4–8 m 精度桥接）
    # 英雄区的岩石面密度明显高于背景洞壁，这里用一圈中景岩把过渡补上，
    # 不是"填满画面"，而是补上"精度突然掉档"的观感断裂。
    ring = [(-5.60, -3.20, 0.95), (-6.60, 0.40, 0.80), (-4.20, 2.60, 0.70),
            (5.20, -2.60, 0.90), (6.40, 0.20, 0.75), (4.30, 2.90, 0.65)]
    for i, (cx, cz, s) in enumerate(ring):
        bm = A.rock_from_planes((s * 1.6, s * 1.25, s * 1.4), seed=700 + i * 13,
                                cuts=7, subdiv=2, rough=0.007, bevel=0.005,
                                strata=(0.18 + 0.05 * (i % 3), 0.030))
        h.add(bm, rock_a if i % 2 else rock_b, loc=(cx, 0.0, cz),
              rot=(0.0, i * 37.0, 0.0))

    # ---------------------------------------------------------- 崩积（talus）：两处石堆
    for ci, (cx, cz) in enumerate([(x0 - 0.35, z1 - 0.55), (x1 + 0.42, z0 + 1.35)]):
        for i in range(9):
            a = TAU * i / 9 + ci * 0.7
            rr = 0.18 + 0.26 * vnoise(i * 1.7, ci * 3.0, 0.4)
            s = 0.10 + 0.10 * vnoise(i * 2.3, ci, 1.1)
            pb = A.rock_from_planes((s * 1.4, s, s * 1.1), seed=480 + ci * 20 + i, cuts=5,
                                    subdiv=2, rough=0.004, bevel=0.003)
            h.add(pb, talus if i % 3 else rock_b,
                  loc=(cx + rr * math.cos(a), s * 0.35, cz + rr * math.sin(a)),
                  rot=(0.0, i * 27.0 + ci * 11.0, 0.0))

    # ---------------------------------------------------------- 垫层脚下的碎屑带
    for i in range(26):
        a = TAU * i / 26 + 0.2
        # 只铺在背面与两侧（正面是通道，保持干净）
        if math.sin(a) > 0.35:
            continue
        rr = 2.35 + 0.30 * vnoise(i * 0.9, 2.0, 5.0)
        s = 0.045 + 0.045 * vnoise(i * 1.3, 7.0, 0.8)
        pb = A.rock_from_planes((s * 1.3, s * 0.7, s), seed=520 + i, cuts=4, subdiv=1,
                                rough=0.002, bevel=0.0015)
        h.add(pb, talus, loc=(PLINTH_C[0] + rr * math.cos(a) * 1.10, s * 0.4,
                              PLINTH_C[1] + rr * math.sin(a)))

    obj = h.finish(smooth=False, split_angle=0.0,
                   bake=dict(ao_rays=9, ao_dist=0.34, seed=57, mat_gain=HM.WEAR_GAIN))
    A.report("RockHero", obj)
    return obj


def main():
    K.reset_scene()
    HM.build_materials()
    build_rocks()
    A.export_glb(os.path.join(OUT, "aqs002_rock_hero.glb"), "RockHero")
    K.save_blend(os.path.join(ROOT, "art-source", "aqs002_rock.blend"))
    print("AQS001_ROCK_OK")


main()


