"""奶龙静态模型构建脚本（Blender 4.5 LTS，无插件）。

用法：
    blender --background --factory-startup --python build_nailong.py -- <输出目录>

设计要点
- 身体/头/四肢/尾巴/耳朵来自**一条骨架曲线 + Skin 修改器**，是一个连续曲面，
  不是互相穿插的球体；再用体素重网格把关节焊成一体。
- 眼、嘴、腮红、鼻孔是按射线检测**贴到曲面上**的小配件（这是卡通角色的常规做法）。
- 面朝 Blender +Y（导出后 Godot 面朝 -Z），脚底 z = 0。
- 同时输出 .blend、.glb 和 5 张预览图。
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "."

# ---------------------------------------------------------------- 基础

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.objects, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            block.remove(item)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(name, color, roughness=0.85, metallic=0.0, specular=0.25):
    """color 按 sRGB 传入（#RRGGBB 的 0..1），内部转成线性再给 Principled。"""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    linear = tuple(srgb_to_linear(c) for c in color)
    bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    for key in ("Specular IOR Level", "Specular"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = specular
            break
    return mat


# ---------------------------------------------------------------- 骨架

# (名字, 位置, 半径)  —— 前 = +Y
NODES = [
    ("hips",      (0.00, 0.00, 0.62), 0.285, True),
    ("belly",     (0.00, -0.01, 0.80), 0.335, False),
    ("chest",     (0.00, 0.00, 0.99), 0.300, False),
    ("neck",      (0.00, 0.01, 1.13), 0.195, False),
    ("head",      (0.00, 0.00, 1.36), 0.345, False),
    ("head_top",  (0.00, -0.01, 1.53), 0.285, False),
    ("muzzle",    (0.00, 0.30, 1.29), 0.150, False),
    ("jaw",       (0.00, 0.26, 1.19), 0.125, False),
    ("ear_l",     (0.19, -0.01, 1.58), 0.085, False),
    ("ear_l_tip", (0.25, 0.01, 1.76), 0.028, False),
    ("ear_r",     (-0.19, -0.01, 1.58), 0.085, False),
    ("ear_r_tip", (-0.25, 0.01, 1.76), 0.028, False),
    ("shoulder_l", (0.24, 0.01, 1.02), 0.110, False),
    ("elbow_l",   (0.37, 0.00, 0.90), 0.098, False),
    ("hand_l",    (0.43, 0.06, 0.77), 0.105, False),
    ("shoulder_r", (-0.24, 0.01, 1.02), 0.110, False),
    ("elbow_r",   (-0.37, 0.00, 0.90), 0.098, False),
    ("hand_r",    (-0.43, 0.06, 0.77), 0.105, False),
    ("hip_l",     (0.175, 0.00, 0.50), 0.160, False),
    ("knee_l",    (0.195, 0.00, 0.30), 0.145, False),
    ("ankle_l",   (0.195, 0.01, 0.13), 0.120, False),
    ("foot_l",    (0.195, 0.11, 0.07), 0.105, False),
    ("hip_r",     (-0.175, 0.00, 0.50), 0.160, False),
    ("knee_r",    (-0.195, 0.00, 0.30), 0.145, False),
    ("ankle_r",   (-0.195, 0.01, 0.13), 0.120, False),
    ("foot_r",    (-0.195, 0.11, 0.07), 0.105, False),
    ("tail_1",    (0.00, -0.24, 0.60), 0.140, False),
    ("tail_2",    (0.00, -0.42, 0.68), 0.100, False),
    ("tail_3",    (0.00, -0.55, 0.80), 0.062, False),
    ("tail_4",    (0.00, -0.60, 0.94), 0.024, False),
]

USE_REMESH = False
HEAD_CENTER = Vector((0.0, 0.0, 1.36))

BONES = [
    ("hips", "belly"), ("belly", "chest"), ("chest", "neck"), ("neck", "head"),
    ("head", "head_top"), ("head", "muzzle"), ("muzzle", "jaw"),
    ("head", "ear_l"), ("ear_l", "ear_l_tip"),
    ("head", "ear_r"), ("ear_r", "ear_r_tip"),
    ("chest", "shoulder_l"), ("shoulder_l", "elbow_l"), ("elbow_l", "hand_l"),
    ("chest", "shoulder_r"), ("shoulder_r", "elbow_r"), ("elbow_r", "hand_r"),
    ("hips", "hip_l"), ("hip_l", "knee_l"), ("knee_l", "ankle_l"), ("ankle_l", "foot_l"),
    ("hips", "hip_r"), ("hip_r", "knee_r"), ("knee_r", "ankle_r"), ("ankle_r", "foot_r"),
    ("hips", "tail_1"), ("tail_1", "tail_2"), ("tail_2", "tail_3"), ("tail_3", "tail_4"),
]


def build_body(mats):
    index = {name: i for i, (name, _, _, _) in enumerate(NODES)}
    mesh = bpy.data.meshes.new("NailongBodyMesh")
    mesh.from_pydata([pos for _, pos, _, _ in NODES], [(index[a], index[b]) for a, b in BONES], [])
    mesh.update()
    obj = bpy.data.objects.new("NailongBody", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    layer = mesh.skin_vertices[0].data
    for i, (_, _, radius, is_root) in enumerate(NODES):
        layer[i].radius = (radius, radius)
        layer[i].use_root = is_root
    sub = obj.modifiers.new("Subdivision", "SUBSURF")
    sub.levels = 3
    sub.render_levels = 3
    _apply(obj, "Skin")
    _apply(obj, "Subdivision")

    # 体素重网格：需要时把关节焊成一个连续曲面（关闭时直接用 Skin+Subsurf 的曲面）
    if USE_REMESH:
        obj.data.remesh_voxel_size = 0.019
        obj.data.remesh_voxel_adaptivity = 0.0
        bpy.ops.object.voxel_remesh()

        smooth = obj.modifiers.new("Smooth", "SMOOTH")
        smooth.factor = 0.5
        smooth.iterations = 3
        _apply(obj, "Smooth")

    bpy.ops.object.shade_smooth()

    # 清掉孤立顶点（Skin 修改器会留下根点）
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for v in [v for v in bm.verts if not v.link_faces]:
        bm.verts.remove(v)
    bm.to_mesh(obj.data)
    bm.free()

    for mat in mats:
        obj.data.materials.append(mat)
    _paint_zones(obj)
    return obj


def _apply(obj, name):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=name)


def _paint_zones(obj):
    """按位置给同一个曲面分配材质槽：肚皮浅色、口鼻浅色。"""
    mesh = obj.data
    idx_body, idx_belly = 0, 1
    for poly in mesh.polygons:
        center = poly.center
        in_belly = (
            0.44 < center.z < 1.12
            and center.y > 0.10
            and abs(center.x) < 0.30
            and poly.normal.y > 0.45
        )
        in_muzzle = center.z > 1.17 and center.z < 1.40 and center.y > 0.22
        poly.material_index = idx_belly if (in_belly or in_muzzle) else idx_body


# ---------------------------------------------------------------- 配件

def surface_hit(obj, origin, direction):
    hit, loc, normal, _index = obj.ray_cast(Vector(origin), Vector(direction).normalized())
    return (loc, normal) if hit else (None, None)


def radial_hit(body, direction):
    """从头部中心向外打射线：保证命中脸表面，不依赖 x/z 是否正好落在椭球内。"""
    d = Vector(direction).normalized()
    return surface_hit(body, HEAD_CENTER + d * 0.02, d)


def add_sphere(name, location, radius, mat, scale=(1, 1, 1), rotation=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    if rotation is not None:
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = rotation
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat)
    return obj


def build_face(body, mats):
    eye_mat, pupil_mat, highlight_mat, cheek_mat, mouth_mat, tongue_mat, nostril_mat = mats

    for side in (1, -1):
        loc, normal = surface_hit(body, (0.155 * side, 1.2, 1.455), (0, -1, 0))
        if loc is None:
            loc = Vector((0.155 * side, 0.30, 1.455))
            normal = Vector((0, 1, 0))
        center = loc - normal * 0.050
        print("ATTACH eye side=%d hit=%s at %s" % (side, loc is not None, [round(v, 3) for v in center]))
        quat = normal.to_track_quat("Z", "Y")
        add_sphere("EyeWhite_%s" % ("L" if side > 0 else "R"), center, 0.088, eye_mat,
                   scale=(1.0, 1.0, 1.12), rotation=quat)
        add_sphere("Pupil_%s" % ("L" if side > 0 else "R"), center + normal * 0.085, 0.043, pupil_mat,
                   scale=(1.0, 1.0, 1.05), rotation=quat)
        add_sphere("Glint_%s" % ("L" if side > 0 else "R"),
                   center + normal * 0.098 + Vector((0.018 * side, 0.0, 0.022)), 0.014,
                   highlight_mat, rotation=quat)
        # 腮红
        loc, normal = radial_hit(body, (0.80 * side, 0.56, -0.24))
        if loc is not None:
            add_sphere("Cheek_%s" % ("L" if side > 0 else "R"), loc + normal * 0.004, 0.072, cheek_mat,
                       scale=(1.15, 1.15, 0.42), rotation=normal.to_track_quat("Z", "Y"))
        else:
            print("ATTACH cheek side=%d MISS" % side)
        # 鼻孔
        loc, normal = surface_hit(body, (0.045 * side, 1.2, 1.345), (0, -1, 0))
        if loc is not None:
            add_sphere("Nostril_%s" % ("L" if side > 0 else "R"), loc + normal * 0.006, 0.021,
                       nostril_mat, scale=(1.0, 1.0, 0.45), rotation=normal.to_track_quat("Z", "Y"))

    # 嘴：贴在一个略凹的曲面上，读作张开的小嘴
    loc, normal = surface_hit(body, (0.0, 1.2, 1.245), (0, -1, 0))
    if loc is None:
        loc, normal = Vector((0, 0.40, 1.245)), Vector((0, 1, 0))
    print("ATTACH mouth at %s" % [round(v, 3) for v in loc])
    quat = normal.to_track_quat("Z", "Y")
    add_sphere("Mouth", loc + normal * 0.010, 0.105, mouth_mat,
               scale=(1.25, 0.62, 0.34), rotation=quat)
    add_sphere("Tongue", loc + normal * 0.016 - Vector((0, 0, 0.030)), 0.062, tongue_mat,
               scale=(1.05, 0.5, 0.30), rotation=quat)


def drop_to_floor():
    """把角色整体落到 z=0：游戏里脚底必须贴地。"""
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.name != "Floor"]
    lowest = min(min((o.matrix_world @ v.co).z for v in o.data.vertices) for o in meshes)
    for obj in meshes:
        obj.data.transform(Matrix.Translation((0.0, 0.0, -lowest)))
    print("FLOOR shift %.4f" % lowest)


# ---------------------------------------------------------------- 场景

def build_scene():
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.055, 0.085, 0.10, 1.0)
    bg.inputs[1].default_value = 0.9
    bpy.context.scene.world = world

    floor_mat = material("Floor", (0.30, 0.36, 0.35), roughness=0.95)
    bpy.ops.mesh.primitive_plane_add(size=24, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "Floor"
    floor.data.materials.append(floor_mat)

    def area(name, loc, energy, size, color=(1, 1, 1)):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        direction = Vector((0, 0, 1.1)) - Vector(loc)
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(obj)

    area("Key", (2.6, 3.2, 3.4), 200, 3.0, (1.0, 0.96, 0.90))
    area("Fill", (-3.2, 1.8, 2.2), 70, 3.5, (0.86, 0.94, 1.0))
    area("Rim", (0.4, -3.4, 2.8), 110, 2.5, (0.80, 0.95, 1.0))


def add_camera(name, location, target, angle_deg, res, ortho=None):
    data = bpy.data.cameras.new(name)
    data.angle = math.radians(angle_deg)
    if ortho is not None:
        data.type = "ORTHO"
        data.ortho_scale = ortho
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(obj)
    obj["res"] = res
    return obj


def render(scene, camera, path, width, height):
    scene.camera = camera
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDER %s" % path)


# ---------------------------------------------------------------- 主流程

def main():
    clear_scene()
    mats = [
        material("NailongCream", (1.0, 0.878, 0.690), 0.88, 0.0, 0.18),
        material("NailongBelly", (1.0, 0.953, 0.855), 0.88, 0.0, 0.18),
        material("EyeWhite", (1.0, 0.992, 0.965), 0.30),
        material("Pupil", (0.055, 0.075, 0.070), 0.22),
        material("Glint", (1.0, 1.0, 1.0), 0.15),
        material("Cheek", (1.0, 0.620, 0.680), 0.80),
        material("Mouth", (0.360, 0.110, 0.150), 0.72),
        material("Tongue", (0.900, 0.430, 0.520), 0.68),
        material("Nostril", (0.240, 0.150, 0.130), 0.75),
    ]

    body = build_body(mats[:2])
    face_mats = (mats[2], mats[3], mats[4], mats[5], mats[6], mats[7], mats[8])
    build_face(body, face_mats)
    drop_to_floor()

    os.makedirs(OUT, exist_ok=True)

    # 只导出角色本体（不带地板/灯光），先于搭影棚导出
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name != "Floor":
            obj.select_set(True)
    glb_path = os.path.join(OUT, "nailong.glb")
    bpy.ops.export_scene.gltf(filepath=glb_path, export_format="GLB", export_apply=True, use_selection=True)
    print("GLB %s" % glb_path)

    build_scene()

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0

    center = (0.0, 0.0, 0.90)
    cams = {
        "front": add_camera("CamFront", (0.0, 5.0, 0.90), center, 34.0, (1000, 1100), ortho=2.05),
        "side": add_camera("CamSide", (5.0, 0.0, 0.90), center, 34.0, (1000, 1100), ortho=2.05),
        "back": add_camera("CamBack", (0.0, -5.0, 0.90), center, 34.0, (1000, 1100), ortho=2.05),
        "three_quarter": add_camera("CamTQ", (2.9, 3.4, 1.55), (0.0, 0.0, 0.92), 32.0, (1100, 1100)),
        # 与游戏一致：眼高 1.6 m、垂直 FOV 74°、距离约 3 m，看向脸
        "first_person": add_camera("CamFP", (0.0, 3.0, 1.60), (0.0, 0.05, 1.25), 74.0, (1280, 800)),
    }

    os.makedirs(OUT, exist_ok=True)

    # 先把模型存下来，再渲染：渲染出问题也不会丢资产
    blend_path = os.path.join(OUT, "nailong.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print("BLEND %s" % blend_path)

    # 统计（不是审美判断，只用于确认网格干净）
    mesh = body.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
    loose = sum(1 for v in bm.verts if not v.link_faces)
    bm.free()
    stats = {
        "body_verts": len(mesh.vertices),
        "body_tris": sum(len(p.vertices) - 2 for p in mesh.polygons),
        "non_manifold_edges": non_manifold,
        "loose_verts": loose,
        "materials": [m.name for m in mesh.materials],
        "bounds_min": [round(min(v.co[i] for v in mesh.vertices), 3) for i in range(3)],
        "bounds_max": [round(max(v.co[i] for v in mesh.vertices), 3) for i in range(3)],
        "objects": [o.name for o in bpy.data.objects if o.type == "MESH"],
    }
    print("STATS " + json.dumps(stats))

    for name, cam in cams.items():
        if "norender" in ARGS:
            break
        width, height = cam["res"]
        render(scene, cam, os.path.join(OUT, "nailong_%s.png" % name), width, height)

    # 结构自检：从正前方射线打到每个五官，看它是不是第一个被击中的物体（没被头吞掉）
    depsgraph = bpy.context.evaluated_depsgraph_get()
    visible = {}
    for part in ("EyeWhite_L", "EyeWhite_R", "Pupil_L", "Pupil_R", "Mouth", "Tongue",
                 "Cheek_L", "Cheek_R", "Nostril_L", "Nostril_R"):
        obj = bpy.data.objects.get(part)
        if obj is None:
            visible[part] = "MISSING"
            continue
        target = obj.matrix_world.translation
        origin = Vector((target.x, 3.0, target.z))
        hit, _loc, _nor, _idx, hit_obj, _mat = scene.ray_cast(depsgraph, origin, target - origin)
        visible[part] = hit_obj.name if hit and hit_obj else "NO_HIT"
    print("VISIBLE " + json.dumps(visible))

    # 剪影遮罩（低分辨率、透明背景，只给我自己做结构检查，不交付）
    scene.render.film_transparent = True
    scene.cycles.samples = 10
    scene.render.resolution_x = 360
    scene.render.resolution_y = 396
    scene.camera = cams["front"]
    scene.render.filepath = os.path.join(OUT, "nailong_mask.png")
    bpy.ops.render.render(write_still=True)
    print("MASK %s" % scene.render.filepath)
    scene.render.film_transparent = False


main()
