"""ART-QUALITY-002-NATURAL · 地面与路线

旧做法：在旧地面上再盖一张 22x34 m 的平面。本轮不这么做，而是：

  * 按真实碰撞地面（y=0，含 x[-22,22] z[-30,14] 与崩落采场坑口）重建
    **一张连续地面网格**，高度只在 0 以下 6 cm 内起伏，玩家脚不会浮空；
  * 坑口是真正的洞（不铺面），由地质体的坑壁与破碎唇缘收边；
  * 路线不是"贴图"，而是嵌入地面的磨损石板（每块独立、有接缝、有高低差），
    把玩家从入口引到锻造台。

导出：aq002_ground.glb
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aq2kit as K
from aq2kit import fbm, vnoise

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "project", "assets", "models", "aq002", "aq002_ground.glb")

PIT = {"min_x": -15.5, "max_x": -8.0, "min_z": -1.5, "max_z": 7.5}
BOUNDS = {"min_x": -22.0, "max_x": 22.0, "min_z": -30.0, "max_z": 14.0}
STEP = 0.38


def ground_y(x, z):
    """地面高度：只允许微低于 0，避免把玩家脚埋进地面。"""
    d = -0.010
    d -= 0.060 * fbm(x * 0.26, z * 0.26, seed=101, octaves=3)
    d -= 0.024 * fbm(x * 0.95, z * 0.95, seed=107, octaves=2)
    d -= 0.010 * fbm(x * 2.6, z * 2.6, seed=111, octaves=2)
    d += 0.008 * vnoise(x * 2.4, z * 2.4, seed=109)
    return min(0.004, d)


def inside_pit(x, z, pad=0.0):
    return (PIT["min_x"] - pad <= x <= PIT["max_x"] + pad and
            PIT["min_z"] - pad <= z <= PIT["max_z"] + pad)


def build_ground():
    xs = []
    x = BOUNDS["min_x"]
    while x <= BOUNDS["max_x"] + 1e-6:
        xs.append(x)
        x += STEP
    zs = []
    z = BOUNDS["min_z"]
    while z <= BOUNDS["max_z"] + 1e-6:
        zs.append(z)
        z += STEP
    nx, nz = len(xs), len(zs)
    verts = []
    for zi in range(nz):
        for xi in range(nx):
            px, pz = xs[xi], zs[zi]
            # 坑口边缘下沉，让地质体的破碎唇缘压住接缝
            edge = 0.0
            if (PIT["min_x"] - 0.9 <= px <= PIT["max_x"] + 0.9 and
                    PIT["min_z"] - 0.9 <= pz <= PIT["max_z"] + 0.9):
                edge = -0.10
            verts.append((px, ground_y(px, pz) + edge, pz))
    faces = []
    for zi in range(nz - 1):
        for xi in range(nx - 1):
            cx = (xs[xi] + xs[xi + 1]) * 0.5
            cz = (zs[zi] + zs[zi + 1]) * 0.5
            if inside_pit(cx, cz, pad=-0.05):
                continue
            a = zi * nx + xi
            b = zi * nx + xi + 1
            c = (zi + 1) * nx + xi + 1
            d = (zi + 1) * nx + xi
            faces.append((a, b, c, d))
    return verts, faces


def build_path():
    """嵌入地面的磨损石板：从入口 z≈7 到锻造台 z≈-2.6，略微弯曲。"""
    verts, faces = [], []
    z = 7.0
    idx = 0
    while z > -3.0:
        t = (7.0 - z) / 10.0
        cx = -0.35 + 0.55 * math.sin(t * 2.2)
        w = 1.15 + 0.22 * math.sin(idx * 1.7)
        d = 1.26 + 0.16 * math.cos(idx * 2.1)
        yaw = (0.10 * math.sin(idx * 1.3)) * 180.0 / math.pi
        base = len(verts)
        # 每块石板是 4x3 的细分面，四角轻微翘曲，接缝自然
        gx, gz = 4, 3
        for iz in range(gz + 1):
            for ix in range(gx + 1):
                u = (ix / gx - 0.5) * w
                v = (iz / gz - 0.5) * d
                a = math.radians(yaw)
                px = cx + u * math.cos(a) - v * math.sin(a)
                pz = z + u * math.sin(a) + v * math.cos(a)
                wob = 0.012 * math.sin(ix * 2.3 + idx) + 0.012 * math.cos(iz * 1.9 + idx * 1.4)
                y = ground_y(px, pz) + 0.035 + wob
                verts.append((px, y, pz))
        for iz in range(gz):
            for ix in range(gx):
                a = base + iz * (gx + 1) + ix
                b = a + 1
                c = a + (gx + 1) + 1
                dd = a + (gx + 1)
                faces.append((a, b, c, dd))
        z -= 1.42
        idx += 1
    return verts, faces


def build_edge_stones():
    """坑口外侧一圈压边石：让"地面结束、坑开始"这件事有交代。"""
    verts, faces = [], []
    per = [
        ((PIT["min_x"], PIT["min_z"]), (PIT["max_x"], PIT["min_z"]), (0, -1)),
        ((PIT["max_x"], PIT["min_z"]), (PIT["max_x"], PIT["max_z"]), (1, 0)),
        ((PIT["max_x"], PIT["max_z"]), (PIT["min_x"], PIT["max_z"]), (0, 1)),
        ((PIT["min_x"], PIT["max_z"]), (PIT["min_x"], PIT["min_z"]), (-1, 0)),
    ]
    for (a, b, out) in per:
        length = math.dist(a, b)
        n = int(length / 1.25)
        for i in range(n):
            t = (i + 0.5) / n
            cx = a[0] + (b[0] - a[0]) * t + out[0] * 0.16
            cz = a[1] + (b[1] - a[1]) * t + out[1] * 0.16
            w = 0.52 + 0.18 * vnoise(i * 1.7, 3.0, seed=131)
            d = 1.05 + 0.25 * vnoise(i * 2.1, 7.0, seed=137)
            y = ground_y(cx, cz) + 0.02
            base = len(verts)
            ang = math.atan2(b[1] - a[1], b[0] - a[0])
            for corner in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
                u = corner[0] * w
                v = corner[1] * d
                px = cx + u * math.cos(ang) - v * math.sin(ang)
                pz = cz + u * math.sin(ang) + v * math.cos(ang)
                verts.append((px, y + (0.03 if corner[1] < 0 else 0.0), pz))
            faces.append((base, base + 1, base + 2, base + 3))
    return verts, faces


def main():
    K.reset_scene()
    rock = K.mat("M_GroundRock", (0.255, 0.222, 0.190), 0.92)
    stone = K.mat("M_Flagstone", (0.345, 0.335, 0.315), 0.85)
    v, f = build_ground()
    g = K.mesh_object("Ground", v, f, rock, smooth=True, split_angle=60.0,
                      orient_center=(0.0, 6.0, -8.0))
    v, f = build_path()
    p = K.mesh_object("Path", v, f, stone, smooth=False)
    v, f = build_edge_stones()
    e = K.mesh_object("PitCoping", v, f, stone, smooth=True, split_angle=46.0)
    print("AQ002_GROUND tris=%d" % K.tri_count([g, p, e]))
    K.export_glb(OUT)
    K.save_blend(os.path.join(ROOT, "art-source", "aq002_ground.blend"))


if __name__ == "__main__":
    main()
