"""ART-QUALITY-002-NATURAL · Blender 工具库（几何 / 岩体 / 导出）

与 ART-QUALITY-001 的 aqkit 不同，这里不再用「逐层多边形柱堆叠」造岩
（那是最终被判为"人工砖墙"的做法）。本库只提供两件事：

1. **从采样曲面生成连续网格**：顶点、法线、UV、平滑组由真实地形函数决定，
   岩石的大形体来自包络曲面 + 向内生长，而不是把模块首尾相接。
2. **手写剖面/旋转体/放样**：工业件的截面由设计者给出控制点，
   倒角是厚实连续的（bevel），而不是在立方体上加圆角。

坐标约定：作者用 Godot 坐标（x 右 / y 上 / -z 前），导出时转 Blender。
"""

import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

TAU = math.pi * 2.0
D2R = math.pi / 180.0


# --------------------------------------------------------------------- 场景
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.length_unit = "METERS"


def g(x, y, z):
    """Godot -> Blender。"""
    return Vector((x, -z, y))


# --------------------------------------------------------------------- 噪声
def _hash(ix, iy, iz, seed=0):
    seed = int(seed)   # ART-SAMPLE-001 本地修正：允许传小数种子（晶体用小数 seed）
    n = (ix * 374761393 + iy * 668265263 + iz * 1274126177 + seed * 982451653) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFFFF) / float(0xFFFFFF)


def _fade(t):
    return t * t * (3.0 - 2.0 * t)


def vnoise(x, y, z=0.0, seed=0):
    """平滑值噪声，返回 0..1。"""
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = _fade(x - ix), _fade(y - iy), _fade(z - iz)
    def h(a, b, c):
        return _hash(ix + a, iy + b, iz + c, seed)
    x00 = h(0, 0, 0) * (1 - fx) + h(1, 0, 0) * fx
    x10 = h(0, 1, 0) * (1 - fx) + h(1, 1, 0) * fx
    x01 = h(0, 0, 1) * (1 - fx) + h(1, 0, 1) * fx
    x11 = h(0, 1, 1) * (1 - fx) + h(1, 1, 1) * fx
    y0 = x00 * (1 - fy) + x10 * fy
    y1 = x01 * (1 - fy) + x11 * fy
    return y0 * (1 - fz) + y1 * fz


def fbm(x, y, z=0.0, octaves=4, lac=2.03, gain=0.5, seed=0):
    amp, freq, total, norm = 1.0, 1.0, 0.0, 0.0
    for i in range(octaves):
        total += amp * vnoise(x * freq, y * freq, z * freq, seed + i * 17)
        norm += amp
        amp *= gain
        freq *= lac
    return total / norm


def smoothstep(a, b, t):
    if a == b:
        return 0.0 if t < a else 1.0
    x = min(1.0, max(0.0, (t - a) / (b - a)))
    return x * x * (3.0 - 2.0 * x)


# --------------------------------------------------------------------- 材质
_MATS = {}


def mat(name, color, rough=0.6, metal=0.0, emit=None, emit_strength=0.0):
    if name in _MATS:
        return _MATS[name]
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (emit[0], emit[1], emit[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    m.diffuse_color = (color[0], color[1], color[2], 1.0)
    _MATS[name] = m
    return m


# --------------------------------------------------------------------- 网格
def mesh_object(name, verts_godot, faces, material, smooth=True,
                split_angle=42.0, weld=1e-4, orient_center=None):
    """verts 用 Godot 坐标；faces 为顶点索引三角形/四边形。

    orient_center（Godot 坐标）给出时，所有面法线统一翻转到朝向该点，
    用于洞壁 / 穹顶 / 坑壁这类"从内部看"的曲面。
    """
    me = bpy.data.meshes.new(name)
    vs = [g(v[0], v[1], v[2]) for v in verts_godot]
    me.from_pydata(vs, [], faces)
    me.validate(verbose=False)
    me.update()
    if weld > 0.0:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=weld)
        bm.to_mesh(me)
        bm.free()
    if orient_center is not None:
        orient_toward(me, g(*orient_center))
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    if material is not None:
        me.materials.append(material)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if smooth and split_angle > 0.0:
        es = obj.modifiers.new("EdgeSplit", "EDGE_SPLIT")
        es.split_angle = split_angle * D2R
        es.use_edge_angle = True
        es.use_edge_sharp = False
        apply_modifiers(obj)
    me.calc_loop_triangles()
    return obj


def orient_toward(me, center):
    """把每个面的法线翻到朝向 center。"""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    for f in bm.faces:
        c = f.calc_center_median()
        if f.normal.dot(Vector(center) - c) < 0.0:
            f.normal_flip()
        f.normal_update()
    bm.to_mesh(me)
    bm.free()


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def shade_auto_smooth(obj, angle=42.0):
    for p in obj.data.polygons:
        p.use_smooth = True
    es = obj.modifiers.new("EdgeSplit", "EDGE_SPLIT")
    es.split_angle = angle * D2R
    apply_modifiers(obj)


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    return obj


def export_glb(path, name_filter=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if name_filter is not None:
        objs = [o for o in objs if name_filter(o.name)]
    if not objs:
        raise RuntimeError("no mesh to export: " + path)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_materials="EXPORT",
        export_cameras=False, export_lights=False, export_extras=False,
    )
    return path


def tri_count(objects=None):
    objects = objects or [o for o in bpy.context.scene.objects if o.type == "MESH"]
    n = 0
    for o in objects:
        o.data.calc_loop_triangles()
        n += len(o.data.loop_triangles)
    return n


def save_blend(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)


# --------------------------------------------------------------------- 包络
def load_envelope(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


# --------------------------------------------------------------------- 工业件
class Part:
    """手写控制点的实体累积器（放样 / 旋转 / 扫掠 / 倒角盒）。"""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mat_names = []

    def _idx(self, m):
        if m is None:
            return None
        if m.name not in self.mat_names:
            self.mat_names.append(m.name)
        return self.mat_names.index(m.name)

    def _merge(self, bm2, m, loc=(0.0, 0.0, 0.0), pre_converted=False):
        idx = self._idx(m)
        if not pre_converted:
            bm2.transform(Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0))).to_4x4())
        if any(abs(a) > 1e-9 for a in loc):
            bm2.transform(Matrix.Translation(g(*loc)))
        bm2.verts.ensure_lookup_table()
        bm2.faces.ensure_lookup_table()
        vmap = {}
        for v in bm2.verts:
            vmap[v] = self.bm.verts.new(v.co)
        self.bm.verts.ensure_lookup_table()
        for f in bm2.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            if idx is not None:
                nf.material_index = idx
        bm2.free()

    def _place(self, bm2, rot):
        if any(abs(a) > 1e-9 for a in rot):
            rx, ry, rz = [a * D2R for a in rot]
            bm2.transform(Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y")
                          @ Matrix.Rotation(rx, 4, "X"))

    def loft(self, sections, cap_start=True, cap_end=True, m=None, loc=(0, 0, 0),
             rot=(0, 0, 0), close=True):
        """sections: [(y, [(x,z), ...]), ...]，各截面点数必须一致。
        沿 y 轴放样，截面在 x/z 平面。用来做机壳、立柱、梁、砧座。"""
        bm2 = bmesh.new()
        rings = []
        for y, pts in sections:
            ring = [bm2.verts.new((p[0], y, p[1])) for p in pts]
            rings.append(ring)
        bm2.verts.ensure_lookup_table()
        n = len(rings[0])
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            for k in range(n if close else n - 1):
                k2 = (k + 1) % n
                try:
                    bm2.faces.new((a[k], a[k2], b[k2], b[k]))
                except ValueError:
                    pass
        if cap_start:
            try:
                bm2.faces.new(list(reversed(rings[0])))
            except ValueError:
                pass
        if cap_end:
            try:
                bm2.faces.new(rings[-1])
            except ValueError:
                pass
        bmesh.ops.recalc_face_normals(bm2, faces=list(bm2.faces))
        self._place(bm2, rot)
        self._merge(bm2, m, loc)
        return self

    def box(self, size, loc, m=None, rot=(0, 0, 0), bevel=0.0, segments=3):
        bm2 = bmesh.new()
        bmesh.ops.create_cube(bm2, size=1.0)
        for v in bm2.verts:
            v.co.x *= size[0]
            v.co.y *= size[1]
            v.co.z *= size[2]
        if bevel > 0.0:
            bmesh.ops.bevel(bm2, geom=list(bm2.edges) + list(bm2.verts),
                            offset=bevel, offset_type="OFFSET", segments=segments,
                            profile=0.5, affect="EDGES", clamp_overlap=True)
        self._place(bm2, rot)
        self._merge(bm2, m, loc)
        return self

    def cyl(self, r, h, loc, m=None, rot=(0, 0, 0), segments=24, r2=None, axis="Y"):
        bm2 = bmesh.new()
        bmesh.ops.create_cone(bm2, cap_ends=True, cap_tris=False, segments=segments,
                              radius1=r, radius2=(r if r2 is None else r2), depth=h)
        pre = Matrix.Identity(4)
        if axis == "Y":
            pre = Matrix.Rotation(-90.0 * D2R, 4, "X")
        elif axis == "X":
            pre = Matrix.Rotation(90.0 * D2R, 4, "Y")
        bm2.transform(pre)
        self._place(bm2, rot)
        self._merge(bm2, m, loc)
        return self

    def lathe(self, profile, loc, m=None, rot=(0, 0, 0), segments=32, smooth=True):
        """(r, y) 剖面绕 y 轴旋转。r=0 处收成一点。"""
        bm2 = bmesh.new()
        rings = []
        for r, y in profile:
            if r <= 1e-6:
                rings.append(None)
                continue
            ring = []
            for i in range(segments):
                a = TAU * i / segments
                ring.append(bm2.verts.new((r * math.cos(a), y, r * math.sin(a))))
            rings.append(ring)
        bm2.verts.ensure_lookup_table()
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            if a is None and b is None:
                continue
            if a is None:
                tip = bm2.verts.new((0.0, profile[i][1], 0.0))
                for k in range(segments):
                    k2 = (k + 1) % segments
                    try:
                        bm2.faces.new((tip, b[k], b[k2]))
                    except ValueError:
                        pass
                continue
            if b is None:
                tip = bm2.verts.new((0.0, profile[i + 1][1], 0.0))
                for k in range(segments):
                    k2 = (k + 1) % segments
                    try:
                        bm2.faces.new((tip, a[k2], a[k]))
                    except ValueError:
                        pass
                continue
            for k in range(segments):
                k2 = (k + 1) % segments
                try:
                    bm2.faces.new((a[k], a[k2], b[k2], b[k]))
                except ValueError:
                    pass
        bmesh.ops.recalc_face_normals(bm2, faces=list(bm2.faces))
        if profile[0][0] > 1e-6:
            try:
                bm2.faces.new(list(reversed(rings[0])))
            except ValueError:
                pass
        if profile[-1][0] > 1e-6:
            try:
                bm2.faces.new(rings[-1])
            except ValueError:
                pass
        self._place(bm2, rot)
        self._merge(bm2, m, loc)
        return self

    def frame(self, pts, w, h, m=None, up=(0, 0, 1)):
        """沿折线扫掠矩形截面（钢梁 / 导轨 / 管架）。"""
        for i in range(len(pts) - 1):
            a = Vector(g(*pts[i]))
            b = Vector(g(*pts[i + 1]))
            d = b - a
            L = d.length
            if L < 1e-6:
                continue
            bm2 = bmesh.new()
            bmesh.ops.create_cube(bm2, size=1.0)
            for v in bm2.verts:
                v.co.x *= w
                v.co.z *= h
                v.co.y *= L
            q = Vector((0.0, 1.0, 0.0)).rotation_difference(d.normalized())
            bm2.transform(Matrix.Translation((a + b) * 0.5) @ q.to_matrix().to_4x4())
            self._merge(bm2, m, pre_converted=True)
        return self

    def finish(self, smooth=False, split_angle=40.0):
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for mn in self.mat_names:
            me.materials.append(bpy.data.materials[mn])
        obj = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(obj)
        if smooth:
            shade_auto_smooth(obj, split_angle)
        me.calc_loop_triangles()
        return obj

