"""ART-QUALITY-002-NATURAL · 自建功能晶体外观

目的：替换来源不可考的 `assets/crystals/res_crys_*.glb`，
同时让功能晶体与新的洞壁/机械共用同一套造型语言（多面柱体 + 解理面 + 尖端收束）。

材质命名遵循 `crystal_visual.gd::_apply_materials` 的关键字约定：
  · 名字含 deep / cleavage → 暗部
  · 名字含 axial / exposed / nucleus → 亮的轴向芯
  · 名字含 violet → 紫调（只在 cyan 调色板下生效）
因此这里用 M_Deep / M_Mid / M_Axial / M_Exposed / M_Violet 五个材质名。

用法：
  blender -b --factory-startup -P build_crystal_shapes.py -- blade|cluster_mid|cluster_env|cluster_west
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aq2kit as K
from aq2kit import Part

OUT = r"C:\Users\ASUS\Desktop\迷失太空\work\art-quality-002-natural\project\assets\models\aq002"
ART = r"C:\Users\ASUS\Desktop\迷失太空\work\art-quality-002-natural\art-source"


def mats():
    return {
        "deep": K.mat("M_Deep", (0.055, 0.34, 0.42), 0.12, 0.0),
        "mid": K.mat("M_Mid", (0.10, 0.58, 0.70), 0.14, 0.0),
        "axial": K.mat("M_Axial", (0.55, 0.93, 1.0), 0.08, 0.0),
        "exposed": K.mat("M_Exposed", (0.72, 0.97, 1.0), 0.08, 0.0),
        "violet": K.mat("M_Violet", (0.30, 0.20, 0.62), 0.16, 0.0),
    }


def ngon(r, n, phase=0.0, squash=1.0):
    return [(r * math.cos(K.TAU * k / n + phase), r * squash * math.sin(K.TAU * k / n + phase))
            for k in range(n)]


def shard(name, base_r, height, sides, phase, lean_x, lean_z, m_deep, m_mid, m_axial, tip_ratio=0.30,
          segs=4):
    """一根晶体：多面柱体 + 腰线 + 尖端收束，其中一段轴向面用亮材质。"""
    p = Part(name)
    secs = []
    for i in range(segs):
        t = i / float(segs - 1)
        # 底部略外扩、中段最粗、顶端收束
        rr = base_r * (0.78 + 0.42 * math.sin(math.pi * min(1.0, t * 0.92)))
        rr = max(rr, base_r * 0.16)
        y = height * t
        xo = lean_x * (t ** 1.6)
        zo = lean_z * (t ** 1.6)
        secs.append((y, [(x + xo, z + zo) for (x, z) in ngon(rr, sides, phase + 0.07 * i)]))
    # 尖端
    tip_y = height * (1.0 + tip_ratio * 0.35)
    secs.append((tip_y, [(lean_x + 0.012 * math.cos(phase + k), lean_z + 0.012 * math.sin(phase + k))
                         for k in range(sides)]))
    # 主体用 mid，轴向面另建一块薄壳用亮材质
    p.loft(secs[:-1] + [secs[-1]], m=m_mid, cap_start=True, cap_end=False)
    # 轴向高光芯：一根更细的同形柱，略偏中心，用亮材质
    p2 = Part(name + "_axial")
    core = []
    for i, (y, ring) in enumerate(secs):
        c = [(x * 0.34, z * 0.34) for (x, z) in ring]
        core.append((y, c))
    p2.loft(core, m=m_axial, cap_start=True, cap_end=True)
    # 底部解理面（暗）
    p3 = Part(name + "_cleavage")
    p3.loft([(0.0, [(x * 1.18, z * 1.18) for (x, z) in secs[0][1]]),
             (height * 0.10, [(x * 1.04, z * 1.04) for (x, z) in secs[0][1]])],
            m=m_deep, cap_start=True, cap_end=False)
    return [p.finish(smooth=False), p2.finish(smooth=False), p3.finish(smooth=False)]


def build(kind):
    K.reset_scene()
    mt = mats()
    objs = []
    if kind == "blade":
        objs += shard("Blade", 0.250, 1.05, 6, 0.3, 0.035, -0.02, mt["deep"], mt["mid"], mt["axial"])
        objs += shard("BladeSmall", 0.120, 0.42, 5, 1.1, -0.05, 0.04, mt["deep"], mt["mid"], mt["exposed"])
    elif kind == "cluster_mid":
        for i, (a, r, h) in enumerate([(0.0, 0.215, 1.15), (1.1, 0.165, 0.72), (2.4, 0.145, 0.86),
                                       (3.6, 0.120, 0.55), (4.9, 0.105, 0.62)]):
            px, pz = 0.16 * math.cos(a), 0.14 * math.sin(a)
            parts = shard("Shard%d" % i, r, h, 5 + (i % 2), a, px * 0.5, pz * 0.5,
                          mt["deep"], mt["mid"], mt["axial"])
            for p in parts:
                p.location = (px, 0.0, pz)
            objs += parts
    elif kind == "cluster_env":
        for i, (a, r, h) in enumerate([(0.2, 0.34, 1.55), (1.4, 0.25, 1.10), (2.7, 0.21, 1.28),
                                       (4.0, 0.19, 0.86), (5.2, 0.17, 0.95), (0.9, 0.13, 0.55)]):
            px, pz = 0.30 * math.cos(a), 0.26 * math.sin(a)
            parts = shard("Env%d" % i, r, h, 5 + (i % 3), a * 1.3, px * 0.6, pz * 0.6,
                          mt["deep"], mt["mid"], mt["axial"])
            for p in parts:
                p.location = (px, 0.0, pz)
            objs += parts
    elif kind == "cluster_west":
        for i, (a, r, h) in enumerate([(0.6, 0.300, 1.25), (2.0, 0.200, 0.80), (3.3, 0.165, 1.02)]):
            px, pz = 0.22 * math.cos(a), 0.20 * math.sin(a)
            parts = shard("West%d" % i, r, h, 6, a, px * 0.5, pz * 0.5,
                          mt["deep"], mt["violet"], mt["axial"])
            for p in parts:
                p.location = (px, 0.0, pz)
            objs += parts
    else:
        raise SystemExit("unknown kind " + kind)

    obj = K.join(objs, "Crystal")

    # ---- 归一化：底部贴 y=0，总高度对齐旧资产（blade 2.13 / cluster 2.13，沿用旧尺寸），
    # 这样晶体占位、拾取射线与交互距离都与替换前一致，不会破坏搬运判定。
    import bpy
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = obj.data
    ys = [v.co.z for v in me.vertices]          # Blender 里 Godot 的 y 对应 z
    ymin = min(ys)
    for v in me.vertices:
        v.co.z -= ymin
    bpy.context.view_layer.update()
    ys = [v.co.z for v in me.vertices]
    height = max(ys) - min(ys)
    target = 1.75 if kind == "blade" else 2.05
    if height > 1e-6:
        k = target / height
        for v in me.vertices:
            v.co *= k
    bpy.context.view_layer.update()
    ys = [v.co.z for v in me.vertices]
    xs = [v.co.x for v in me.vertices]
    print("AQ002_CRYSHAPE %s tris=%d  height=%.2f  width=%.2f"
          % (kind, K.tri_count([obj]), max(ys) - min(ys), max(xs) - min(xs)))
    K.export_glb(os.path.join(OUT, "aq002_crystal_%s.glb" % kind))
    K.save_blend(os.path.join(ART, "aq002_crystal_%s.blend" % kind))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build(args[0] if args else "blade")
