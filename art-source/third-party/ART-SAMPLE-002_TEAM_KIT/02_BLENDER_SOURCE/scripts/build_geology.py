"""ART-QUALITY-002-NATURAL · 洞厅地质体生成

设计原则（这一轮最重要的一条）
================================
岩壁不是"很多块岩石资产首尾相接"，而是**一张连续的地质曲面**：
基底是 R04CaveShell 真正的碰撞面，新网格只从这个面向内生长，因此

  * 不可能出现"模块接缝"，因为根本没有模块；
  * 不可能把玩家挡在看不见的碰撞外面，也不会穿进石头里；
  * 大形体来自三件事：**大尺度凹凸（bay / lobe）**、**断层错台（fault scarp）**
    和**层理台阶（strata terrace）**，而不是随机噪声。

生成顺序
  1. wall   连续洞壁，含 3 处凹龛、2 条断层、7 层沉积台阶、竖向侵蚀槽
  2. ceiling 下凹穹顶，含大尺度起伏
  3. talus  墙脚连续堆积裙（岩壁→地面过渡）
  4. pit    崩落采场（真实坑体）的内壁与破碎坑缘
  5. outcrop 三块手工控制点的大岩体，负责近景轮廓与设备基础

导出：assets/models/aq002/aq002_geology.glb
"""

import json
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aq2kit as K
from aq2kit import fbm, smoothstep, vnoise, TAU, D2R

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ENV_PATH = os.path.join(ROOT, "art-source", "envelope", "cave_envelope.json")
VARIANT = "a"
for _a in sys.argv:
    if _a in ("b", "a"):
        VARIANT = _a
OUT_GLB = os.path.join(ROOT, "project", "assets", "models", "aq002",
                       "aq002_geology_%s.glb" % VARIANT)
OUT_BLEND = os.path.join(ROOT, "art-source", "aq002_geology.blend")

AXIS_Z = -8.0  # 洞厅轴线（superellipse 的 z 中心）

# 方案 A：两条斜向断层把洞壁切成大破面，三处工作面凹龛。
FAULTS_A = [
    {"n": (math.cos(28 * D2R), math.sin(28 * D2R)), "p": (-6.0, 2.0), "depth": 0.62, "width": 0.55},
    {"n": (math.cos(-64 * D2R), math.sin(-64 * D2R)), "p": (9.0, -16.0), "depth": 0.48, "width": 0.70},
]
BAYS_A = [
    (math.radians(268.0), 0.34, 0.85, 5.2, 3.4),
    (math.radians(96.0), 0.30, 0.70, 4.6, 3.0),
    (math.radians(186.0), 0.26, 0.55, 6.0, 2.6),
]

# 方案 B：一条贯通南北的主断层把洞厅切成两级台地，双侧长条工作面，
# 中央是一座被岩体半包围的"矿囊"。整体更"被岩体包住"，工业件更少露在开阔地。
FAULTS_B = [
    {"n": (math.cos(6 * D2R), math.sin(6 * D2R)), "p": (4.4, -6.0), "depth": 1.05, "width": 0.95},
    {"n": (math.cos(96 * D2R), math.sin(96 * D2R)), "p": (-9.0, -14.0), "depth": 0.55, "width": 0.75},
]
BAYS_B = [
    (math.radians(250.0), 0.42, 1.25, 4.4, 3.8),
    (math.radians(78.0), 0.36, 0.95, 5.4, 3.2),
    (math.radians(300.0), 0.22, 0.70, 7.0, 2.4),
    (math.radians(132.0), 0.20, 0.60, 3.2, 2.2),
]


def faults():
    return FAULTS_B if VARIANT == "b" else FAULTS_A


def bays():
    return BAYS_B if VARIANT == "b" else BAYS_A


def point_and_normal(wall, row, col):
    p = wall[row][col]
    dx = p[0]
    dz = p[2] - AXIS_Z
    L = math.hypot(dx, dz)
    if L < 1e-6:
        return p, (0.0, -1.0)
    return p, (-dx / L, -dz / L)


def angle_of(p):
    return math.atan2(p[2] - AXIS_Z, p[0]) % TAU


def wall_depth(angle, y, p):
    """向内生长深度（米）。越深 = 洞壁越往中间退。"""
    d = 0.18
    # 大尺度起伏：3 个宽缓的鼓包与凹槽
    d += 0.62 * (fbm(angle * 2.1, y * 0.13, seed=11, octaves=3) - 0.5) * 2.0
    # 凹龛（远处工作面的开挖痕迹）
    for (ca, cw, cd, cy, ch) in bays():
        da = abs(((angle - ca + math.pi) % TAU) - math.pi)
        w = (1.0 - smoothstep(cw * 0.35, cw, da))
        v = (1.0 - smoothstep(ch * 0.45, ch, abs(y - cy)))
        d += cd * w * v
    # 断层错台：平面一侧整体退后，边缘锐利 → 大破面
    for f in faults():
        nx, nz = f["n"]
        dist = (p[0] - f["p"][0]) * nx + (p[2] - f["p"][1]) * nz
        step = smoothstep(-f["width"], f["width"], dist)
        d += f["depth"] * (1.0 - step)
    # 沉积台阶：层厚与层位都沿走向强烈变化，避免出现等距水平条带
    warp = 2.4 * (fbm(angle * 0.62, y * 0.03, seed=3, octaves=3) - 0.5)
    band = y * (0.62 + 0.35 * vnoise(angle * 0.9, 0.0, seed=13)) + warp
    t = band - math.floor(band)
    ledge = (1.0 - smoothstep(0.0, 0.20, t))
    d += 0.13 * ledge * (0.45 + 1.25 * vnoise(angle * 4.0, y * 0.2, seed=5))
    # 大尺度倾斜岩层：整片岩壁沿一个方向缓慢起伏，打破水平均质
    d += 0.22 * math.sin(angle * 2.4 + y * 0.18 + 1.1)
    # 竖向侵蚀槽：只在中段发育，底部与顶部收住
    flute = math.sin(angle * (9.0 + 5.0 * vnoise(angle * 1.7, y * 0.4, seed=9))
                     + 2.4 * vnoise(angle * 3.3, y * 0.9, seed=13))
    d += 0.13 * flute * smoothstep(1.2, 2.6, y) * (1.0 - smoothstep(8.0, 11.0, y))
    # 侵蚀细节：中频 + 高频
    d += 0.16 * (fbm(angle * 5.5, y * 0.55, seed=17, octaves=3) - 0.5) * 2.0
    d += 0.06 * (vnoise(angle * 23.0, y * 2.4, seed=23) - 0.5) * 2.0
    # 近景修形：玩家 0–4 m 高度能看清的范围，专门加一层高频起伏、
    # 竖向水蚀沟和小尺度崩落面，避免近看是"光滑曲面 + 均匀条带"。
    near = (1.0 - smoothstep(2.6, 5.2, y))
    # 近景起伏的幅度按"1.2 m 视距能看清"来定。原来给 4–7 cm，在这个距离
    # 只剩一层柔和明暗（第 46 回合 A/B 实测），所以抬到 10–22 cm。
    d += 0.220 * (fbm(angle * 26.0, y * 1.6, seed=29, octaves=3) - 0.5) * 2.0 * near
    d += 0.100 * (vnoise(angle * 61.0, y * 5.0, seed=31) - 0.5) * 2.0 * near
    gully = math.sin(angle * (44.0 + 12.0 * vnoise(angle * 2.0, y * 0.5, seed=33))
                     + 3.1 * vnoise(angle * 7.0, y * 1.4, seed=35))
    d += 0.140 * gully * near * (0.4 + 0.6 * (1.0 - smoothstep(0.2, 2.2, y)))
    # 崩落面：几条锐利的折痕，只在近景高度出现
    crease = abs(fbm(angle * 3.1, y * 0.9, seed=41, octaves=2) - 0.5)
    d += 0.180 * (1.0 - smoothstep(0.0, 0.06, crease)) * near
    # 硬错台：层与层之间是台阶，不是平滑过渡。这是"岩石而不是水泥"最直接的读法，
    # 也只有把它做进几何里才看得见（贴图做不到）。
    step_band = y * (0.90 + 0.50 * vnoise(angle * 1.3, 0.0, seed=47)) + warp * 0.6
    st = step_band - math.floor(step_band)
    d += 0.160 * smoothstep(0.88, 1.0, st) * near
    # 高频道：1 m 级与 0.4 m 级。第 46 回合网格还是 0.33 m/列、0.20 m/行，
    # 这两档做不出来；加密采样后才有意义（幅度小，但近看就是它们给"岩面"的读感）。
    d += 0.055 * (vnoise(angle * 190.0, y * 12.0, seed=53) - 0.5) * 2.0 * near
    d += 0.028 * (vnoise(angle * 330.0, y * 22.0, seed=59) - 0.5) * 2.0 * near
    return max(0.06, d)


def ceiling_depth(x, z):
    d = 0.22
    d += 0.85 * fbm(x * 0.075, z * 0.075, seed=31, octaves=3)
    d += 0.30 * fbm(x * 0.26, z * 0.26, seed=37, octaves=2)
    d += 0.12 * (vnoise(x * 1.1, z * 1.1, seed=41) - 0.5) * 2.0
    return d


def resample_rows(env):
    """纵向重采样：墙脚 0–3.2 m 每 0.10 m 一行（原来 0.20 m），
    以上保持 0.40 m。近景要有 10–30 cm 尺度的起伏，0.2 m 的采样根本表达不出来。"""
    wall_def = env["wall"]
    rows = wall_def["points"]
    heights = wall_def["heights"]
    out_rows = []
    out_h = []
    for r in range(len(rows) - 1):
        y0 = heights[r] if r < len(heights) else rows[r][0][1]
        y1 = heights[r + 1] if r + 1 < len(heights) else rows[r + 1][0][1]
        step = 0.10 if y1 <= 3.2 else 0.40
        n = max(1, int(round((y1 - y0) / step)))
        for k in range(n):
            t = k / n
            out_rows.append([lerp3(rows[r][c], rows[r + 1][c], t) for c in range(len(rows[0]))])
            out_h.append(y0 + (y1 - y0) * t)
    out_rows.append(rows[-1])
    out_h.append(heights[-1] if heights else rows[-1][0][1])
    return out_rows, out_h


def resample_cols(rows, factor=2):
    """沿墙走向加密：401 列 → 801 列（约 0.16 m 一列）。
    走向太稀的话，30–60 cm 尺度的岩面细节连采样点都没有。"""
    src_cols = len(rows[0])
    out = []
    for row in rows:
        nr = []
        for c in range(src_cols - 1):
            for k in range(factor):
                nr.append(lerp3(row[c], row[c + 1], k / factor))
        nr.append(row[-1])
        out.append(nr)
    return out


def lerp3(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def build_wall(env):
    rows_raw = env["wall"]["points"]
    heights_raw = env["wall"]["heights"]
    _rows, _hs = resample_rows(env)
    rows = resample_cols(_rows, 2)
    heights = _hs
    cols = len(rows[0])
    verts = []
    for r in range(len(rows)):
        for c in range(cols):
            p, n = point_and_normal(rows, r, c)
            ang = angle_of(p)
            y = heights[r] if r < len(heights) else p[1]
            d = wall_depth(ang, y, p)
            # 顶部 0.6 m 收回到包络，保证与天花网格衔接
            if r >= len(rows) - 2:
                d *= 0.35
            # 关键：向内生长方向必须朝**岩石一侧**（远离洞腔），
            # 否则新岩壁会侵入可行走空间，把玩家/相机埋进石头里。
            verts.append((p[0] - n[0] * d, p[1], p[2] - n[1] * d))
    faces = []
    for r in range(len(rows) - 1):
        for c in range(cols - 1):
            a = r * cols + c
            b = r * cols + c + 1
            cc = (r + 1) * cols + c + 1
            dd = (r + 1) * cols + c
            faces.append((a, b, cc, dd))
    return verts, faces


def build_ceiling(env):
    """穹顶：网格尺寸必须大于洞壁最大外径，让天花板"压进"岩壁里，
    否则边缘会与岩壁之间留下一条缝，从洞内看就是一道锯齿状的黑带。"""
    ceil = env["ceiling"]
    src_xs = ceil["xs"]
    src_zs = ceil["zs"]
    hs = ceil["heights"]
    xs = []
    x = -23.0
    while x <= 23.0 + 1e-6:
        xs.append(round(x, 3))
        x += 0.55
    zs = []
    z = -32.0
    while z <= 16.0 + 1e-6:
        zs.append(round(z, 3))
        z += 0.55
    verts = []
    for z in zs:
        for x in xs:
            ix = min(range(len(src_xs)), key=lambda i: abs(src_xs[i] - x))
            iz = min(range(len(src_zs)), key=lambda i: abs(src_zs[i] - z))
            y = hs[iz][ix] - ceiling_depth(x, z)
            verts.append((x, y, z))
    nx = len(xs)
    nz = len(zs)
    faces = []
    for iz in range(nz - 1):
        for ix in range(nx - 1):
            a = iz * nx + ix
            b = iz * nx + ix + 1
            c = (iz + 1) * nx + ix + 1
            d = (iz + 1) * nx + ix
            faces.append((d, c, b, a))
    return verts, faces

def build_talus(env):
    """墙脚堆积：洞壁→地面的连续过渡，不是藏在墙脚的碎石堆。"""
    wall = env["wall"]["points"]
    heights = env["wall"]["heights"]
    cols = len(wall[0])
    row_low = 3  # y ≈ 0.9
    verts = []
    for c in range(cols):
        p, n = point_and_normal(wall, row_low, c)
        ang = angle_of(p)
        d = wall_depth(ang, heights[row_low], p)
        spread = 1.15 + 0.95 * fbm(ang * 3.4, 0.0, seed=51, octaves=3)
        toe = 0.55 + 0.55 * vnoise(ang * 9.0, 1.0, seed=57)
        # 三段：壁面接触 → 坡脚 → 地面接触
        # 顶边贴在可见岩壁表面（p - n*d），其余两排朝洞内延伸 → 连续的堆积坡
        verts.append((p[0] - n[0] * d, 1.10, p[2] - n[1] * d))
        verts.append((p[0] + n[0] * (spread * 0.45), toe + 0.35,
                      p[2] + n[1] * (spread * 0.45)))
        verts.append((p[0] + n[0] * spread, -0.04,
                      p[2] + n[1] * spread))
    # 顶点按"每列 3 个"排列，索引必须是 c*3+k，不能当成按行排列。
    faces = []
    for c in range(cols - 1):
        for k in range(2):
            a = c * 3 + k
            b = (c + 1) * 3 + k
            cc = (c + 1) * 3 + k + 1
            dd = c * 3 + k + 1
            faces.append((a, b, cc, dd))
    return verts, faces


def build_pit(env):
    pit = env["pit"]
    x0, x1 = pit["min_x"], pit["max_x"]
    z0, z1 = pit["min_z"], pit["max_z"]
    fy = pit["floor_y"]
    verts, faces = [], []
    # 每面由 4 排顶点组成：坑口破碎唇缘（向外翻）→ 上部陡壁 → 下部内收 → 坑底
    edges = [
        ((x0, z0), (x1, z0), (0.0, -1.0)),
        ((x1, z1), (x0, z1), (0.0, 1.0)),
        ((x0, z1), (x0, z0), (-1.0, 0.0)),
        ((x1, z0), (x1, z1), (1.0, 0.0)),
    ]
    for (a, b, out) in edges:
        n = 9
        base = len(verts)
        for i in range(n + 1):
            t = i / n
            ax = a[0] + (b[0] - a[0]) * t
            az = a[1] + (b[1] - a[1]) * t
            wob = 0.22 * math.sin(t * 9.0 + 1.7) + 0.12 * vnoise(t * 7.0, 2.0, seed=61)
            lip = 0.30 + wob
            verts.append((ax + out[0] * lip, 0.10 + 0.06 * math.sin(t * 12.0), az + out[1] * lip))
            verts.append((ax + out[0] * 0.02, -0.55, az + out[1] * 0.02))
            verts.append((ax - out[0] * 0.28 + 0.10 * math.sin(t * 6.0), -1.9,
                          az - out[1] * 0.28 + 0.10 * math.cos(t * 6.0)))
            verts.append((ax + out[0] * 0.02, fy + 0.02, az + out[1] * 0.02))
        for i in range(n):
            for k in range(3):
                a0 = base + i * 4 + k
                b0 = base + (i + 1) * 4 + k
                c0 = base + (i + 1) * 4 + k + 1
                d0 = base + i * 4 + k + 1
                faces.append((a0, b0, c0, d0))
    return verts, faces


def build_outcrops():
    """三块手工控制点的大岩体。不是随机形变：每块都有明确的成因与朝向。

    做法：以细分球为骨，逐顶点执行本区统一的"层理内收 + 侵蚀"规则，
    再按作者空间缩放 / 旋转 / 就位。三块各自的尺度与朝向不同，
    所以不会读成同一个模型复制三遍。
    """
    import bmesh
    from mathutils import Matrix as M
    out = []
    specs = [
        # 名称, 中心, 尺度, 走向(度), 种子
        ("Outcrop_ForgeBase", (-13.8, 1.05, -7.8), (2.2, 1.20, 1.9), 18, 71),
        ("Outcrop_StairToe", (-9.0, 0.90, 5.8), (2.1, 1.00, 1.8), -24, 83),
        ("Outcrop_GateJamb", (-6.2, 1.2, -23.2), (2.0, 1.5, 1.7), 64, 97),
    ]
    for (name, c, s, yaw, seed) in specs:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
        for v in bm.verts:
            x, y, z = v.co.x, v.co.y, v.co.z
            strata = 0.14 * math.sin(y * 5.8 + 0.6) + 0.06 * math.sin(y * 13.0)
            erode = 0.20 * (fbm(x * 1.7 + seed, y * 1.7, z * 1.7, seed=seed) - 0.5) * 2.0
            r = 1.0 + strata + erode
            v.co = K.g(x * r * s[0], y * r * s[1], z * r * s[2])
            # 压平底面
            if v.co.z < K.g(0, -s[1] * 0.55, 0).z:
                v.co.z = K.g(0, -s[1] * 0.55, 0).z
        rz = yaw * D2R
        bm.transform(M.Rotation(rz, 4, "Z"))
        bm.transform(M.Translation(K.g(*c)))
        out.append((name, bm))
    return out


def make_mesh_from_bm(name, bm, material):
    bm.normal_update()
    for f in bm.faces:
        f.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    K.shade_auto_smooth(obj, 46.0)
    return obj


def main():
    K.reset_scene()
    print("AQ002_GEOLOGY variant=", VARIANT)
    env = K.load_envelope(ENV_PATH)
    rock = K.mat("M_RockWarm", (0.30, 0.225, 0.170), 0.88)
    rock_dark = K.mat("M_RockDark", (0.17, 0.135, 0.115), 0.92)
    sediment = K.mat("M_Sediment", (0.36, 0.30, 0.235), 0.9)

    v, f = build_wall(env)
    wall = K.mesh_object("Geology_Wall", v, f, rock, smooth=True, split_angle=38.0,
                         orient_center=(0.0, 5.0, AXIS_Z))
    v, f = build_ceiling(env)
    ceil = K.mesh_object("Geology_Ceiling", v, f, rock_dark, smooth=True, split_angle=44.0,
                         orient_center=(0.0, 0.0, AXIS_Z))
    v, f = build_talus(env)
    talus = K.mesh_object("Geology_Talus", v, f, sediment, smooth=True, split_angle=52.0,
                          orient_center=(0.0, -0.5, AXIS_Z))
    v, f = build_pit(env)
    pit = K.mesh_object("Geology_Pit", v, f, rock_dark, smooth=True, split_angle=34.0,
                        orient_center=(-11.75, -1.2, 3.0))
    objs = [wall, ceil, talus, pit]
    for name, bm in build_outcrops():
        objs.append(make_mesh_from_bm(name, bm, rock))

    total = K.tri_count(objs)
    print("AQ002_GEOLOGY objects=%d tris=%d" % (len(objs), total))
    K.export_glb(OUT_GLB)
    K.save_blend(OUT_BLEND.replace(".blend", "_%s.blend" % VARIANT))
    print("AQ002_GEOLOGY wrote", OUT_GLB)


if __name__ == "__main__":
    main()
