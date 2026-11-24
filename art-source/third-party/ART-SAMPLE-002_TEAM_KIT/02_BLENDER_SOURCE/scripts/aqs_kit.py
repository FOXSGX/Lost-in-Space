"""ART-SAMPLE-001 · 英雄区建模工具库（敲钟机 / 晶体 / 平台 / 岩层）

与 ART-QUALITY-002 的 `aq2kit.py` 的分工
---------------------------------------
`aq2kit` 解决的是"把一个形体造对"（连续曲面、放样、旋转体、GLB 导出）。
本库解决的是"1–2 米近看经不经得起"这件事，补的都是近景判据里的具体项：

* **圆角与倒角**：`rrect_r()` 给出真正的圆角矩形截面（不是切角八边形），
  所有机加工边都有 0.8–3 mm 倒角几何（不是靠平滑组骗）。
* **紧固件**：`bolt()` / `bolt_row()` 造六角头 + 垫圈 + 沉座凸台，
  每颗有独立相位，不是一排一模一样的柱子。
* **焊缝**：`weld()` 沿真实接缝走向铺一条带抖动的焊道（铸焊件必须有的东西）。
* **薄板**：`plate()` 给出带折边的板，板与板之间有装配间隙（2–3 mm 阴影线）。
* **铸造面**：`soften()` 沿法线做亚毫米级噪声位移，让大平面不再是"数学平面"。
* **顶点遮罩烘焙**：`bake_masks()` 把**曲率凸处磨损、凹处积垢、环境遮蔽**烘进顶点色，
  供 Godot 侧的材质库读取；这是让"干净玩具"变成"用过的东西"最廉价也最有效的一步。
* **断裂面岩石**：`rock_from_planes()` 用随机平面切出真正的解理面（带锐棱 + 微倒角），
  而不是球体加噪声。

坐标约定与 aq2kit 一致：作者用 Godot 坐标（x 右 / y 上 / -z 前），导出时转 Blender。
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aq2kit as K
from aq2kit import D2R, TAU, fbm, g, smoothstep, vnoise

# Godot 坐标 -> Blender 坐标（与 aq2kit.g 同一约定），做成矩阵便于整体变换
GB = Matrix(((1.0, 0.0, 0.0, 0.0),
             (0.0, 0.0, -1.0, 0.0),
             (0.0, 1.0, 0.0, 0.0),
             (0.0, 0.0, 0.0, 1.0)))

AXES = {
    "up": (0.0, 1.0, 0.0), "down": (0.0, -1.0, 0.0),
    "xp": (1.0, 0.0, 0.0), "xn": (-1.0, 0.0, 0.0),
    "zp": (0.0, 0.0, 1.0), "zn": (0.0, 0.0, -1.0),
}


# ------------------------------------------------------------------ 几何基元
def _bevel_all(bm, offset, segments=3, profile=0.5):
    if offset <= 0.0:
        return bm
    bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=offset,
                    offset_type="OFFSET", segments=segments, profile=profile,
                    affect="EDGES", clamp_overlap=True)
    return bm


def bm_box(size, bevel=0.0, segments=3, taper=None):
    """居中的盒子；segments>=2 时圆角是真正的曲面过渡。"""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = size
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    if taper is not None:
        # taper = (top_scale_x, top_scale_z)：向上收分的铸件
        tx, tz = taper
        for v in bm.verts:
            if v.co.y > 0.0:
                v.co.x *= tx
                v.co.z *= tz
    _bevel_all(bm, bevel, segments)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def rrect_r(w, d, r, seg=4):
    """真正的圆角矩形截面（x 为宽 / z 为深），返回 (x, z) 点列。

    seg 是每个圆角的段数：seg=4 时单个圆角有 5 个点，近景能看出是连续的圆弧。
    """
    r = min(r, w * 0.5 - 1e-4, d * 0.5 - 1e-4)
    hw, hd = w * 0.5, d * 0.5
    pts = []
    centers = [(hw - r, hd - r, 0.0), (-hw + r, hd - r, 90.0),
               (-hw + r, -hd + r, 180.0), (hw - r, -hd + r, 270.0)]
    for cx, cz, a0 in centers:
        for i in range(seg + 1):
            a = (a0 + 90.0 * i / seg) * D2R
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def circle_pts(r, n=24, phase=0.0):
    return [(r * math.cos(phase + TAU * i / n), r * math.sin(phase + TAU * i / n)) for i in range(n)]


def bm_cyl(r, h, seg=24, r2=None, caps=True, smooth=True):
    """沿 +y 的圆柱/圆台（底面 y=0、顶面 y=h）。"""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=seg,
                          radius1=r, radius2=(r if r2 is None else r2), depth=h)
    bm.transform(Matrix.Rotation(-90.0 * D2R, 4, "X"))
    for v in bm.verts:
        v.co.y += h * 0.5
    for f in bm.faces:
        f.smooth = smooth and len(f.verts) == 4
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def bm_loft(sections, close=True, cap_start=True, cap_end=True, smooth_sides=True):
    """sections: [(y, [(x, z), ...]), ...]，沿 y 放样。"""
    bm = bmesh.new()
    rings = []
    for y, pts in sections:
        rings.append([bm.verts.new((p[0], y, p[1])) for p in pts])
    bm.verts.ensure_lookup_table()
    n = len(rings[0])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(n if close else n - 1):
            k2 = (k + 1) % n
            try:
                f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
                f.smooth = smooth_sides
            except ValueError:
                pass
    if cap_start:
        try:
            bm.faces.new(list(reversed(rings[0])))
        except ValueError:
            pass
    if cap_end:
        try:
            bm.faces.new(rings[-1])
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def bm_lathe(profile, seg=32, phase=0.0):
    """(r, y) 剖面绕 y 轴旋转；r=0 处收成一点。"""
    bm = bmesh.new()
    rings = []
    for r, y in profile:
        if r <= 1e-6:
            rings.append(None)
            continue
        rings.append([bm.verts.new((r * math.cos(phase + TAU * i / seg), y,
                                    r * math.sin(phase + TAU * i / seg)))
                      for i in range(seg)])
    bm.verts.ensure_lookup_table()
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        if a is None and b is None:
            continue
        if a is None:
            tip = bm.verts.new((0.0, profile[i][1], 0.0))
            for k in range(seg):
                try:
                    bm.faces.new((tip, b[k + 1] if k + 1 < seg else b[0], b[k]))
                except ValueError:
                    pass
            continue
        if b is None:
            tip = bm.verts.new((0.0, profile[i + 1][1], 0.0))
            for k in range(seg):
                try:
                    bm.faces.new((tip, a[k], a[k + 1] if k + 1 < seg else a[0]))
                except ValueError:
                    pass
            continue
        for k in range(seg):
            k2 = (k + 1) % seg
            try:
                f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
                f.smooth = True
            except ValueError:
                pass
    if profile[0][0] > 1e-6:
        try:
            bm.faces.new(list(reversed(rings[0])))
        except ValueError:
            pass
    if profile[-1][0] > 1e-6:
        try:
            bm.faces.new(rings[-1])
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def bm_tube(path, r, seg=8, radii=None, caps=True, smooth=True):
    """沿折线扫掠圆截面（电缆 / 管 / 焊道 / 拉杆）。用平行传输避免截面翻转。"""
    pts = [Vector(p) for p in path]
    n = len(pts)
    if n < 2:
        raise ValueError("tube needs >=2 points")
    tangents = []
    for i in range(n):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == n - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        if t.length < 1e-9:
            t = Vector((0.0, 1.0, 0.0))
        tangents.append(t.normalized())
    ref = Vector((0.0, 1.0, 0.0))
    if abs(tangents[0].dot(ref)) > 0.95:
        ref = Vector((1.0, 0.0, 0.0))
    nrm = (ref - tangents[0] * ref.dot(tangents[0])).normalized()
    bm = bmesh.new()
    rings = []
    for i in range(n):
        if i > 0:
            nrm = nrm - tangents[i] * nrm.dot(tangents[i])
            if nrm.length < 1e-6:
                nrm = Vector((1.0, 0.0, 0.0)) - tangents[i] * tangents[i].x
            nrm.normalize()
        bino = tangents[i].cross(nrm).normalized()
        rr = r if radii is None else radii[i]
        ring = []
        for k in range(seg):
            a = TAU * k / seg
            ring.append(bm.verts.new(pts[i] + nrm * (rr * math.cos(a)) + bino * (rr * math.sin(a))))
        rings.append(ring)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(seg):
            k2 = (k + 1) % seg
            try:
                f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
                f.smooth = smooth
            except ValueError:
                pass
    if caps:
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            try:
                bm.faces.new(list(reversed(ring)) if flip else ring)
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def bm_prism(profile, h, smooth_sides=False):
    """把 (x, z) 多边形沿 y 挤出 h（底面 y=0）。"""
    return bm_loft([(0.0, profile), (h, profile)], smooth_sides=smooth_sides)


def bm_loft_x(sections, close=True, cap_start=True, cap_end=True, smooth_sides=False):
    """沿 x 放样；sections: [(x, [(y, z), ...]), ...]（用于横梁这种沿 x 走的件）。"""
    bm = bmesh.new()
    rings = []
    for x, pts in sections:
        rings.append([bm.verts.new((x, p[0], p[1])) for p in pts])
    bm.verts.ensure_lookup_table()
    n = len(rings[0])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(n if close else n - 1):
            k2 = (k + 1) % n
            try:
                f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
                f.smooth = smooth_sides
            except ValueError:
                pass
    if cap_start:
        try:
            bm.faces.new(list(reversed(rings[0])))
        except ValueError:
            pass
    if cap_end:
        try:
            bm.faces.new(rings[-1])
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def arc_pts(cx, cy, r, a0, a1, seg):
    return [(cx + r * math.cos((a0 + (a1 - a0) * i / seg) * D2R),
             cy + r * math.sin((a0 + (a1 - a0) * i / seg) * D2R)) for i in range(seg + 1)]


def i_profile(y0, y1, zc, tf, tw, ff, fw, r=0.028, seg=3):
    """工字钢截面（在 (y, z) 平面里，给 bm_loft_x 用）。

    tf: 上翼缘厚 / ff: 下翼缘厚 / tw: 腹板厚 / fw: 翼缘宽的一半 / zc: 中心 z。
    腹板与翼缘之间是真正的圆角（铸钢梁的标志）。
    """
    yt = y1 - tf
    yb = y0 + ff
    pts = []
    # 下翼缘底面向右
    pts += [(y0, zc - fw), (y0, zc + fw), (yb - r, zc + fw)]
    pts += arc_pts(yb - r, zc + tw * 0.5 + r, r, 0.0, -90.0, seg)[1:]
    pts += [(yb, zc + tw * 0.5)]
    pts += [(yt, zc + tw * 0.5)]
    pts += arc_pts(yt + r, zc + tw * 0.5 + r, r, -90.0, 0.0, seg)[1:]
    pts += [(yt + r, zc + fw)]
    pts += [(y1, zc + fw), (y1, zc - fw), (yt + r, zc - fw)]
    pts += arc_pts(yt + r, zc - tw * 0.5 - r, r, 0.0, 90.0, seg)[1:]
    pts += [(yt, zc - tw * 0.5), (yb, zc - tw * 0.5)]
    pts += arc_pts(yb - r, zc - tw * 0.5 - r, r, 90.0, 180.0, seg)[1:]
    pts += [(yb - r, zc - fw)]
    # 去掉重复点
    out = []
    for p in pts:
        if not out or (abs(p[0] - out[-1][0]) > 1e-6 or abs(p[1] - out[-1][1]) > 1e-6):
            out.append(p)
    return out


def bm_join(dst, src):
    """把一个 bmesh 的顶点/面并进另一个（src 会被释放）。"""
    src.verts.ensure_lookup_table()
    src.faces.ensure_lookup_table()
    vmap = {}
    for v in src.verts:
        vmap[v] = dst.verts.new(v.co)
    dst.verts.ensure_lookup_table()
    for f in src.faces:
        try:
            nf = dst.faces.new([vmap[v] for v in f.verts])
            nf.smooth = f.smooth
        except ValueError:
            pass
    src.free()
    return dst


def bm_torus(R, r, seg_major=20, seg_minor=8, arc=1.0):
    bm = bmesh.new()
    rings = []
    for i in range(seg_major + (0 if arc >= 1.0 else 1)):
        a = TAU * arc * i / seg_major
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for k in range(seg_minor):
            b = TAU * k / seg_minor
            rr = R + r * math.cos(b)
            ring.append(bm.verts.new((rr * ca, r * math.sin(b), rr * sa)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(seg_minor):
            k2 = (k + 1) % seg_minor
            try:
                f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
                f.smooth = True
            except ValueError:
                pass
    if arc >= 1.0:
        a, b = rings[-1], rings[0]
        for k in range(seg_minor):
            k2 = (k + 1) % seg_minor
            try:
                f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
                f.smooth = True
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


# ------------------------------------------------------------------ 装配体
class Hero:
    """把若干 bmesh 基元装配成一个带材质槽的物体。"""

    def __init__(self, name):
        self.part = K.Part(name)
        self.count = 0

    def add(self, bm, mat, loc=(0.0, 0.0, 0.0), axis=None, rot=None, soft=None):
        """axis: 'up'/'down'/'xp'/'xn'/'zp'/'zn'，把 +y 轴转到该方向。"""
        if axis is not None:
            q = Vector((0.0, 1.0, 0.0)).rotation_difference(Vector(AXES[axis]).normalized())
            bm.transform(q.to_matrix().to_4x4())
        if rot is not None and any(abs(a) > 1e-9 for a in rot):
            rx, ry, rz = [a * D2R for a in rot]
            bm.transform(Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y")
                         @ Matrix.Rotation(rx, 4, "X"))
        if soft:
            soften(bm, *soft)
        if any(abs(a) > 1e-9 for a in loc):
            bm.transform(Matrix.Translation(Vector(loc)))
        bm.transform(GB)
        self.part._merge(bm, mat, (0.0, 0.0, 0.0), pre_converted=True)
        self.count += 1
        return self

    # -------------------------------------------------- 紧固件
    def bolt(self, loc, mat, axis="up", d=0.024, head_h=0.014, washer=True,
             washer_mat=None, boss=0.0, boss_mat=None, phase=None, nut=False):
        """六角头 + 垫圈 + 可选沉座凸台。六角头带 45° 倒棱，近景能看出是螺母不是圆柱。"""
        if phase is None:
            phase = random.uniform(0.0, TAU)
        r = d * 0.5
        hexp = [(r * math.cos(phase + TAU * i / 6), r * math.sin(phase + TAU * i / 6)) for i in range(6)]
        # 六角头：下段直身 + 上段 45° 倒棱（螺母读感靠这一道棱）
        head = bm_prism(hexp, head_h * 0.68)
        _bevel_all(head, min(head_h * 0.12, r * 0.10), 2)
        top = bm_prism([(p[0] * 0.88, p[1] * 0.88) for p in hexp], head_h * 0.32)
        for v in top.verts:
            v.co.y += head_h * 0.68
        _bevel_all(top, min(head_h * 0.09, r * 0.09), 2)
        head = bm_join(head, top)
        base = Vector(loc)
        axis_v = Vector(AXES[axis]).normalized()
        self.add(head, mat, loc=base + axis_v * (head_h + (0.003 if washer else 0.0)),
                 axis=axis)
        if washer:
            w = bm_lathe([(0.0, 0.0), (r * 1.42, 0.0), (r * 1.42, 0.0028), (r * 1.36, 0.0034),
                          (0.0, 0.0034)], seg=14)
            self.add(w, washer_mat or mat, loc=base + axis_v * head_h, axis=axis)
        if boss > 0.0:
            b = bm_lathe([(0.0, -boss), (r * 2.5, -boss), (r * 2.5 + 0.002, -boss * 0.45),
                          (r * 2.5, 0.0), (0.0, 0.0)], seg=16)
            self.add(b, boss_mat or washer_mat or mat, loc=base, axis=axis)
        if nut:
            n = bm_prism([(r * 1.25 * math.cos(phase + TAU * i / 6),
                           r * 1.25 * math.sin(phase + TAU * i / 6)) for i in range(6)], head_h * 1.05)
            _bevel_all(n, head_h * 0.12, 2)
            self.add(n, mat, loc=base - axis_v * (head_h * 0.1), axis=axis)
        return self

    def bolt_row(self, a, b, count, mat, **kw):
        va, vb = Vector(a), Vector(b)
        for i in range(count):
            t = 0.0 if count == 1 else i / float(count - 1)
            self.bolt(va.lerp(vb, t), mat, **kw)
        return self

    # -------------------------------------------------- 焊缝
    def weld(self, path, mat, r=0.0062, seed=0, seg=6, wobble=0.28):
        pts = [Vector(p) for p in path]
        radii = []
        for i, p in enumerate(pts):
            n = vnoise(p.x * 24.0, p.y * 24.0, p.z * 24.0, seed)
            radii.append(r * (1.0 - wobble * 0.5 + wobble * n))
        self.add(bm_tube(pts, r, seg=seg, radii=radii), mat)
        return self

    # -------------------------------------------------- 薄板
    def plate(self, size, loc, mat, thickness=0.004, bevel=0.0012, rot=None,
              fold=("xn", "zn"), fold_len=0.016):
        """带折边的薄板：板厚真实、四边有 R≈板厚的边、可选两条折边。"""
        self.add(bm_box(size, bevel=bevel, segments=2), mat, loc=loc, rot=rot)
        if fold:
            sx, sy, sz = size
            for side in fold:
                if side in ("xn", "xp"):
                    d = bm_box((thickness * 1.1, sy * 0.98, fold_len), bevel=bevel * 0.7, segments=2)
                    off = Vector(((-1 if side == "xn" else 1) * (sx * 0.5), 0.0,
                                  (-1 if fold[1] == "zn" else 1) * (sz * 0.5 - fold_len * 0.5)))
                else:
                    d = bm_box((sx * 0.98, thickness * 1.1, fold_len), bevel=bevel * 0.7, segments=2)
                    off = Vector((0.0, 0.0, (-1 if side == "zn" else 1) * (sz * 0.5)))
                self.add(d, mat, loc=Vector(loc) + off)
        return self

    def finish(self, smooth=True, split_angle=32.0, bake=None):
        """bake：遮罩烘焙参数。**必须在 EdgeSplit 之前烘**——切开顶点后 1-ring 拓扑
        就断了，曲率（凸棱磨损）算不出来，遮罩会整片变成 0。"""
        obj = self.part.finish(smooth=False)
        if bake is not None:
            bake_masks(obj, **bake)
        if smooth:
            K.shade_auto_smooth(obj, split_angle)
        return obj


# ------------------------------------------------------------------ 表面处理
def soften(bm, amp=0.0007, freq=9.0, seed=0, axis_bias=0.0):
    """沿法线做亚毫米级铸造型噪声位移：让大平面不再是数学平面（近景最要紧的一条）。"""
    bm.normal_update()
    if amp <= 0.0:
        return bm
    for v in bm.verts:
        n = v.normal
        d = (fbm(v.co.x * freq, v.co.y * freq, v.co.z * freq, 3, seed=seed) - 0.5) * 2.0 * amp
        d += (vnoise(v.co.x * freq * 3.1, v.co.y * freq * 3.1, v.co.z * freq * 3.1, seed + 5) - 0.5) * amp * 0.45
        v.co += n * d
    return bm


def rock_from_planes(size, seed, cuts=11, subdiv=3, jitter=0.16, bevel=0.006,
                     rough=0.012, strata=None):
    """断裂面岩块：先切出解理面（锐棱），再给面加轻微起伏，最后微倒角。

    size: (sx, sy, sz) 近似包围尺寸；strata=(period, amp) 追加水平层理错台。
    """
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0] * 0.5
        v.co.y *= size[1] * 0.5
        v.co.z *= size[2] * 0.5
    # 先圆一下大形（四级细分后才有足够面承受切割）
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=subdiv, use_grid_fill=True)
    bmesh.ops.smooth_vert(bm, verts=list(bm.verts), factor=0.35, use_axis_x=True,
                          use_axis_y=True, use_axis_z=True)
    for c in range(cuts):
        # 随机平面：法线偏向上/侧，避免全是斜切
        theta = rng.uniform(0.0, TAU)
        phi = rng.uniform(-0.55, 0.95)
        n = Vector((math.cos(theta) * math.cos(phi), math.sin(phi), math.sin(theta) * math.cos(phi)))
        n.normalize()
        # 切在包围盒里、离中心一段距离处
        reach = 0.5 * (abs(n.x) * size[0] + abs(n.y) * size[1] + abs(n.z) * size[2]) * 0.5
        dist = reach * rng.uniform(0.55, 1.02)
        if c == 0:
            dist = reach * 1.03  # 第一刀只做削平，保证有基准面
        co = n * dist
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        try:
            bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=co, plane_no=n,
                                   clear_outer=True, clear_inner=False)
        except Exception:
            continue
    # 面内起伏：每块解理面不是绝对平的
    bm.normal_update()
    for v in bm.verts:
        d = (fbm(v.co.x * 5.2, v.co.y * 5.2, v.co.z * 5.2, 3, seed=seed + 3) - 0.5) * rough
        d += (vnoise(v.co.x * 21.0, v.co.y * 21.0, v.co.z * 21.0, seed + 9) - 0.5) * rough * 0.5
        v.co += v.normal * d
    if strata:
        period, amp = strata
        for v in bm.verts:
            h = math.floor(v.co.y / period)
            step = (vnoise(h * 3.7, 0.5, 0.5, seed + 11) - 0.5) * 2.0 * amp
            # 只在层界附近错台，避免整体位移
            frac = (v.co.y / period) - h
            if frac > 0.82:
                v.co.y += step * (frac - 0.82) / 0.18
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, offset_type="OFFSET",
                        segments=1, profile=0.5, affect="EDGES", clamp_overlap=True)
    for f in bm.faces:
        f.smooth = False
    return bm


# ------------------------------------------------------------------ 遮罩烘焙
def bake_masks(obj, ao_rays=10, ao_dist=0.18, seed=0, mat_gain=None,
               ground_z=None, verbose=True):
    """把三件事烘进顶点色（Blender 局部坐标；builder 里 z 是"上"）：

    R = 边缘磨损（凸棱越多越亮，再乘噪声）
    G = 环境遮蔽（自遮挡 + 贴地压暗）
    B = 涂装破损/落尘斑（噪声团块，集中在凸棱附近）
    A = 朝上程度（积尘/雨后水渍用）
    """
    me = obj.data
    me.calc_loop_triangles()
    nv = len(me.vertices)
    verts = [v.co.copy() for v in me.vertices]
    tris = [tuple(t.vertices) for t in me.loop_triangles]

    # --- 顶点法线（面积加权）---
    vn = [Vector((0.0, 0.0, 0.0)) for _ in range(nv)]
    for p in me.polygons:
        n = p.normal.copy()
        for vi in p.vertices:
            vn[vi] += n * p.area
    for i in range(nv):
        vn[i] = vn[i].normalized() if vn[i].length > 1e-9 else Vector((0.0, 0.0, 1.0))

    # --- 离散平均曲率：邻域重心落在顶点法线哪一侧 ---
    neigh = [set() for _ in range(nv)]
    for a, b, c in tris:
        neigh[a].update((b, c))
        neigh[b].update((a, c))
        neigh[c].update((a, b))
    curv = [0.0] * nv
    for i in range(nv):
        if not neigh[i]:
            continue
        acc = Vector((0.0, 0.0, 0.0))
        elen = 0.0
        for j in neigh[i]:
            acc += verts[j]
            elen += (verts[j] - verts[i]).length
        if elen <= 1e-9:
            continue
        mean = acc / float(len(neigh[i]))
        elen /= float(len(neigh[i]))
        # 凸：邻域重心在法线的反方向
        curv[i] = -(mean - verts[i]).dot(vn[i]) / max(elen, 1e-5)

    # --- 材质增益 ---
    vmat = [0] * nv
    for p in me.polygons:
        for vi in p.vertices:
            vmat[vi] = p.material_index
    mat_names = [m.name if m else "" for m in me.materials]
    gain = []
    for nm in mat_names:
        gv = 1.0
        if mat_gain:
            for key, val in mat_gain.items():
                if key in nm:
                    gv = val
                    break
        gain.append(gv)

    # --- 自遮挡 AO（BVH 余弦半球采样）---
    bvh = BVHTree.FromPolygons([tuple(v) for v in verts], tris, all_triangles=True, epsilon=0.0)
    occ = [0.0] * nv
    rng = random.Random(seed)
    dirs_cache = {}
    for i in range(nv):
        n = vn[i]
        key = (round(n.x, 2), round(n.y, 2), round(n.z, 2))
        basis = dirs_cache.get(key)
        if basis is None:
            t = Vector((0.0, 0.0, 1.0))
            if abs(n.z) > 0.9:
                t = Vector((1.0, 0.0, 0.0))
            b1 = n.cross(t).normalized()
            b2 = n.cross(b1).normalized()
            basis = (b1, b2)
            dirs_cache[key] = basis
        b1, b2 = basis
        origin = verts[i] + n * 0.0016
        hits = 0
        for k in range(ao_rays):
            # 余弦加权：用 sqrt 变换的均匀采样
            u1 = (k + 0.5) / ao_rays
            u2 = rng.random()
            rr = math.sqrt(u1)
            a = TAU * u2
            d = (n * math.sqrt(max(0.0, 1.0 - u1)) + b1 * (rr * math.cos(a)) + b2 * (rr * math.sin(a)))
            d.normalize()
            hit = bvh.ray_cast(origin, d, ao_dist)
            if hit[0] is not None:
                hits += 1
        occ[i] = hits / float(ao_rays)

    # --- 写顶点色 ---
    attr_name = "Col"
    if attr_name in me.color_attributes:
        me.color_attributes.remove(me.color_attributes[attr_name])
    attr = me.color_attributes.new(name=attr_name, type="FLOAT_COLOR", domain="POINT")
    zs = [v.z for v in verts]
    zmin, zmax = min(zs), max(zs)
    for i in range(nv):
        p = verts[i]
        # 磨损：凸棱为主，叠加噪声让磨损断续
        cv = max(0.0, curv[i])
        wear_n = fbm(p.x * 6.0, p.y * 6.0, p.z * 6.0, 3, seed=seed + 21)
        wear = smoothstep(0.30, 1.15, cv) * (0.40 + 0.70 * wear_n) * gain[vmat[i]]
        wear = min(1.0, max(0.0, wear))
        # 破损斑：细一级的噪声团块，靠凸棱加权（大团块会读成"泥点"）
        chip = smoothstep(0.66, 0.90, fbm(p.x * 6.5, p.y * 6.5, p.z * 6.5, 3, seed=seed + 33))
        chip *= (0.25 + 0.75 * min(1.0, cv * 1.6)) * 0.65
        chip = min(1.0, max(0.0, chip * gain[vmat[i]]))
        # 遮蔽：自遮挡 + 贴地
        ao = occ[i]
        if ground_z is not None:
            ao = max(ao, 1.0 - smoothstep(0.0, 0.34, p.z - ground_z))
        up = max(0.0, min(1.0, vn[i].z * 0.5 + 0.5))
        attr.data[i].color = (wear, ao, chip, up)
    if verbose:
        vals = list(attr.data)
        print("BAKE_MASK %s verts=%d tris=%d wear_max=%.2f ao_mean=%.2f" % (
            obj.name, nv, len(tris),
            max(v.color[0] for v in vals),
            sum(v.color[1] for v in vals) / max(1, nv)))
    return attr


# ------------------------------------------------------------------ 导出
def export_glb(path, name):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError("object not found: " + name)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    kwargs = dict(filepath=path, export_format="GLB", use_selection=True,
                  export_apply=True, export_yup=True, export_materials="EXPORT",
                  export_cameras=False, export_lights=False, export_extras=False,
                  export_normals=True, export_tangents=True,
                  export_all_vertex_colors=False, export_vertex_color="ACTIVE",
                  export_vertex_color_name="Col")
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_vertex_color_name", None)
        bpy.ops.export_scene.gltf(**kwargs)
    return path


def report(name, obj):
    obj.data.calc_loop_triangles()
    print("ASSET %s tris=%d verts=%d mats=%d" % (
        name, len(obj.data.loop_triangles), len(obj.data.vertices), len(obj.data.materials)))

