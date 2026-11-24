"""奶龙星 · Blender 通用工艺件（瓦楞板 / H 型钢 / 梁 / 柱脚 / 遮光罩）

只放三件资产共用的东西，全部按《美术制作与 AI 协作指南》的工艺口径：

* 瓦楞板：真实的波形截面放样（不是贴图假装），带板厚与 2–3 mm 装配余量；
* H 型钢：腹板 + 上下翼缘是分开的实体，接缝留阴影线；
* 柱脚：承台底板 + 四件套地脚螺栓（凸台 + 垫圈 + 45° 倒棱六角头，独立相位）；
* 遮光罩 / 灯头：车削剖面，灯罩必带挂钩与防眩罩（禁无承力悬浮件）。

坐标约定与 aq2kit / aqs_kit 一致：作者用 Godot 坐标（x 右 / y 上 / -z 前）。
"""

import math

import bmesh
import bpy
import aq2kit as K
import aqs_kit as S
from aqs_kit import TAU, bm_box
from mathutils import Vector


# ------------------------------------------------------------------ 瓦楞板
def corrugated(width, height, thick=0.008, period=0.32, amp=0.042, seg_per=5,
               base=0.0, taper=1.0):
    """竖向瓦楞板：宽 width（x）、高 height（y，base..base+height）、肋朝 +z。

    截面是真正的余弦波形 + 等厚回程，所以侧光下有连续的明暗带，
    每米 3 条肋、肋高 42 mm，远看是"集装箱"，近看是折弯钢板。
    """
    n = max(2, int(round(width / period)))
    steps = n * seg_per
    outer = []
    for i in range(steps + 1):
        u = -width * 0.5 + width * i / steps
        d = amp * (0.5 - 0.5 * math.cos(TAU * i / seg_per))
        outer.append((u, d))
    prof = outer + [(u, d - thick) for (u, d) in reversed(outer)]
    if abs(taper - 1.0) > 1e-6:
        prof = [(u * taper, d) for (u, d) in prof]
    return S.bm_loft([(base, prof), (base + height, prof)], smooth_sides=True)


# ------------------------------------------------------------------ 型钢
def add_h_column(h, x, z, y0, y1, mat_web, mat_flange, w=0.20, depth=0.16,
                 tf=0.022, tw=0.010, bevel=0.003):
    """H 型钢柱：翼缘朝 ±z，腹板夹在中间；翼缘比腹板厚一倍多（真实比例）。"""
    yc = (y0 + y1) * 0.5
    hh = y1 - y0
    h.add(bm_box((tw, hh, depth - 2.0 * tf), bevel=bevel, segments=2), mat_web,
          loc=(x, yc, z))
    for sz in (-1.0, 1.0):
        h.add(bm_box((w, hh, tf), bevel=bevel, segments=2), mat_flange,
              loc=(x, yc, z + sz * (depth * 0.5 - tf * 0.5)))


def add_beam_x(h, x0, x1, y, z, mat_flange, mat_web, depth=0.15, tall=0.16,
               tf=0.020, tw=0.011):
    """沿 x 的工字梁：上下翼缘水平、腹板竖直。y = 梁底。"""
    xc = (x0 + x1) * 0.5
    length = x1 - x0
    h.add(bm_box((length, tall, tw), bevel=0.003, segments=2), mat_web,
          loc=(xc, y + tall * 0.5, z))
    for sy in (-1.0, 1.0):
        h.add(bm_box((length, tf, depth), bevel=0.004, segments=2), mat_flange,
              loc=(xc, y + tall * 0.5 + sy * (tall * 0.5 - tf * 0.5), z))


def add_beam_z(h, z0, z1, y, x, mat_flange, mat_web, depth=0.15, tall=0.16,
               tf=0.020, tw=0.011, tilt=0.0):
    """沿 z 的斜梁（屋架椽条）：y = 梁底中点高度，tilt 为绕 x 的角度。"""
    zc = (z0 + z1) * 0.5
    length = z1 - z0
    rot = (tilt, 0.0, 0.0)
    h.add(bm_box((tw, tall, length), bevel=0.003, segments=2), mat_web,
          loc=(x, y + tall * 0.5, zc), rot=rot)
    for sx in (-1.0, 1.0):
        h.add(bm_box((depth, tf, length), bevel=0.004, segments=2), mat_flange,
              loc=(x + sx * (depth * 0.5 - tf * 0.5), y + tall * 0.5, zc), rot=rot)


# ------------------------------------------------------------------ 斜撑

def add_frame(h, pts, w, hh, mat):
    """沿折线扫掠方截面（X 形斜撑 / 拉杆用；Hero 没暴露 Part.frame）。"""
    h.part.frame(pts, w, hh, mat)


# ------------------------------------------------------------------ 紧固件
def add_bolt(h, base, mat, axis="up", d=0.020, head_h=0.013, phase=0.0,
             boss=0.0, boss_mat=None, washer=True):
    """贴面四件套螺栓：底座凸台 + 垫圈 + 45° 倒棱六角头，严格的层叠顺序。

    注意：aqs_kit 的 Hero.bolt() 会把六角头再抬 head_h，垫圈因此悬在板面上方；
    本资产一律用这里的版本，保证螺母真的压在垫圈上。
    """
    from aqs_kit import AXES
    axis_v = Vector(AXES[axis]).normalized()
    r = d * 0.5
    p = Vector(base)
    if boss > 0.0:
        b = S.bm_lathe([(0.0, -boss), (r * 2.4, -boss * 0.92),
                        (r * 2.4 + 0.002, -boss * 0.40), (r * 2.4, 0.0), (0.0, 0.0)],
                       seg=12)
        h.add(b, boss_mat or mat, loc=tuple(p), axis=axis)
    top = p
    if washer:
        w = S.bm_lathe([(0.0, 0.0), (r * 1.44, 0.0), (r * 1.42, 0.0026),
                        (r * 1.36, 0.0036), (0.0, 0.0036)], seg=12)
        h.add(w, mat, loc=tuple(p), axis=axis)
        top = p + axis_v * 0.0036
    hexp = [(r * math.cos(phase + TAU * i / 6), r * math.sin(phase + TAU * i / 6))
            for i in range(6)]
    head = S.bm_prism(hexp, head_h * 0.66)
    _bevel(head, min(head_h * 0.10, r * 0.09))
    cap = S.bm_prism([(u * 0.87, v * 0.87) for (u, v) in hexp], head_h * 0.34)
    for v in cap.verts:
        v.co.y += head_h * 0.66
    _bevel(cap, min(head_h * 0.08, r * 0.07))
    head = S.bm_join(head, cap)
    h.add(head, mat, loc=tuple(top), axis=axis)


def _bevel(bm, off, segments=1):
    bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=off,
                    offset_type="OFFSET", segments=segments, profile=0.5,
                    affect="EDGES", clamp_overlap=True)
    return bm


# ------------------------------------------------------------------ 柱脚
def add_foot(h, x, z, sx, sz, mat_plate, mat_bolt, mat_boss, bolt_d=0.022,
             bolts=((-1.0, -1.0), (1.0, 1.0)), y=0.0, thickness=0.030):
    """承台底板 + 地脚螺栓（只放对角两颗，避免无意义堆螺母）。"""
    h.plate((sx, thickness, sz), (x, y + thickness * 0.5, z), mat_plate,
            thickness=thickness, bevel=0.004, fold=None)
    for sx_, sz_ in bolts:
        add_bolt(h, (x + sx_ * (sx * 0.5 - 0.055), y + thickness, z + sz_ * (sz * 0.5 - 0.055)),
                 mat_bolt, axis="up", d=bolt_d, boss=0.010, boss_mat=mat_boss,
                 phase=0.9 * sx_ + 1.7 * sz_ + 0.4 * x)


# ------------------------------------------------------------------ 灯头
def add_lamp(h, x, y_top, z, mat_shell, mat_trim, rod_drop=0.34, rim_r=0.205,
             seg=16):
    """吊装灯头：楼板挂板 → 吊杆 → 锥形遮光罩 → 防眩横杆。

    y_top 是挂点（梁/板底面），灯罩底沿在 y_top - rod_drop。
    """
    y_rim = y_top - rod_drop
    h.add(bm_box((0.11, 0.012, 0.11), bevel=0.003, segments=2), mat_trim,
          loc=(x, y_top + 0.006, z))
    h.add(bm_cyl(0.011, rod_drop + 0.01, seg=8), mat_trim,
          loc=(x, y_rim, z))
    hood = S.bm_lathe([
        (0.0, y_rim + 0.135), (0.042, y_rim + 0.135), (0.05, y_rim + 0.112),
        (rim_r, y_rim + 0.022), (rim_r, y_rim), (rim_r - 0.018, y_rim),
        (0.05, y_rim + 0.096), (0.0, y_rim + 0.096),
    ], seg=seg)
    h.add(hood, mat_shell)
    # 防眩：两道横杆 + 一圈卡箍
    for off in (-0.075, 0.075):
        h.add(S.bm_tube([(x - rim_r + 0.02, y_rim - 0.004, z + off),
                         (x + rim_r - 0.02, y_rim - 0.004, z + off)], 0.005, seg=6),
              mat_trim)
    ring = S.bm_lathe([
        (rim_r - 0.006, y_rim + 0.052), (rim_r + 0.006, y_rim + 0.052),
        (rim_r + 0.006, y_rim + 0.068), (rim_r - 0.006, y_rim + 0.068),
        (rim_r - 0.006, y_rim + 0.052),
    ], seg=seg)
    h.add(ring, mat_trim)
    return y_rim


def bm_cyl(r, h, seg=12):
    return S.bm_cyl(r, h, seg=seg)


# ------------------------------------------------------------------ 检查
def check_islands(obj, tol=0.02, verbose=False):
    """连通块体检：先把拆边合并回去，再找“悬空且碰不到任何其他件”的孤立块。"""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-4)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    nv = len(bm.verts)
    parent = list(range(nv))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for e in bm.edges:
        union(e.verts[0].index, e.verts[1].index)
    groups = {}
    for v in bm.verts:
        r = find(v.index)
        g = groups.setdefault(r, [1e9, 1e9, 1e9, -1e9, -1e9, -1e9, 0])
        g[0] = min(g[0], v.co.x)
        g[1] = min(g[1], v.co.y)
        g[2] = min(g[2], v.co.z)
        g[3] = max(g[3], v.co.x)
        g[4] = max(g[4], v.co.y)
        g[5] = max(g[5], v.co.z)
        g[6] += 1
    bm.free()
    boxes = list(groups.values())
    orphans = []
    for i, a in enumerate(boxes):
        if a[2] <= tol:
            continue  # 落地
        touch = False
        for j, b in enumerate(boxes):
            if i == j:
                continue
            if (a[0] - tol <= b[3] and b[0] - tol <= a[3]
                    and a[1] - tol <= b[4] and b[1] - tol <= a[4]
                    and a[2] - tol <= b[5] and b[2] - tol <= a[5]):
                touch = True
                break
        if not touch:
            orphans.append(a)
    print("ISLANDS %s components=%d verts=%d floating_orphans=%d" % (
        obj.name, len(boxes), nv, len(orphans)))
    for o in orphans:
        print("  ORPHAN x=%.3f..%.3f y=%.3f..%.3f z=%.3f..%.3f verts=%d" % (
            o[0], o[3], o[1], o[4], o[2], o[5], o[6]))
    if verbose:
        for b in sorted(boxes, key=lambda b: b[6])[:6]:
            print("  small block verts=%d y=%.3f..%.3f" % (b[6], b[2], b[5]))
    return orphans


# ------------------------------------------------------------------ 收尾
def finish_asset(h, bake, split_angle=32.0, uv=True, margin=0.006, triangulate=True):
    """严格的收尾顺序：建网格 → Smart UV → 烘 4 通道顶点色 → EdgeSplit。

    《指南》Step 5/6 的致命顺序就是这个：先展 UV、烘完顶点色，最后才能拆边；
    拆完边再烘，1-ring 拓扑断了，曲率（凸棱磨损）会整片变 0。
    """
    obj = h.part.finish(smooth=False)
    if uv:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=margin)
        bpy.ops.object.mode_set(mode="OBJECT")
    if bake is not None:
        S.bake_masks(obj, **bake)
    K.shade_auto_smooth(obj, split_angle)
    if triangulate:
        triangulate_mesh(obj)
    return obj


def triangulate_mesh(obj):
    """导出前强制全三角化：不先三角化，glTF 算不出 TANGENT（法线贴图全废）。"""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="BEAUTY",
                          ngon_method="BEAUTY")
    bm.to_mesh(me)
    bm.free()
    me.update()
    return obj


def report_mats(obj):
    """按材质统计三角面（做预算时看钱花在哪）。"""
    me = obj.data
    me.calc_loop_triangles()
    counts = {}
    for t in me.loop_triangles:
        nm = me.materials[t.material_index].name if t.material_index < len(me.materials) else "?"
        counts[nm] = counts.get(nm, 0) + 1
    print("TRIS_BY_MAT %s" % counts)


def report_bbox(name, obj):
    """打印包围盒（Godot 语义尺寸：x 宽 / y 高 / z 深）。"""
    vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
    xs = [v.x for v in vs]
    ys = [v.z for v in vs]
    zs = [-v.y for v in vs]
    print("BBOX %s x=%.3f..%.3f (%.3f) y=%.3f..%.3f (%.3f) z=%.3f..%.3f (%.3f)" % (
        name, min(xs), max(xs), max(xs) - min(xs),
        min(ys), max(ys), max(ys) - min(ys),
        min(zs), max(zs), max(zs) - min(zs)))
