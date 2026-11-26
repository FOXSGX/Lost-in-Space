"""把 Downloads 里的 nailong（Sketchfab / CC-BY-4.0）转成游戏用 GLB。

    blender --background --factory-startup --python build_nailong_dl.py -- <scene.gltf> <out.glb> [preview_dir]

做的事：
1. 删掉 Sketchfab 附带的占位球，只保留主网格 + 骨架；
2. T-pose 的手臂放下来（旋转 DEF-upper_arm 50°），并把当前姿势烘成新的 rest pose；
3. 7 层 UV 合成 1 层；
4. 导出 GLB（贴图内嵌，不带动画）。

朝向 / 落地不在这里改：模型朝 +Z、脚底 z=-0.072，
由 Godot 侧 `milk_dragon_model.gd` 统一转 180°、抬 0.072。
"""
import bpy
import os
import sys
import math
from mathutils import Quaternion

argv = sys.argv
src = argv[argv.index("--") + 1]
out_glb = argv[argv.index("--") + 2]
preview_dir = argv[argv.index("--") + 3] if len(argv) > argv.index("--") + 3 else ""

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
main_mesh = max(meshes, key=lambda o: len(o.data.vertices))
for ob in list(bpy.data.objects):
    if ob.type == "MESH" and ob is not main_mesh:
        bpy.data.objects.remove(ob, do_unlink=True)
    elif ob.type in {"CAMERA", "LIGHT"}:
        bpy.data.objects.remove(ob, do_unlink=True)

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")

# ---- 手臂放下 ----
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
for name in ("DEF-upper_arm.L_165_148", "DEF-upper_arm.R_195_178"):
    pb = arm.pose.bones.get(name)
    if pb is None:
        print("WARN missing bone %s" % name)
        continue
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0), math.radians(50.0))
bpy.context.view_layer.update()

# 先把当前变形烘进网格（否则把姿势设成 rest 会把网格弹回 T-pose）
bpy.ops.object.mode_set(mode='OBJECT')
bpy.context.view_layer.objects.active = main_mesh
applied = False
for mod in list(main_mesh.modifiers):
    if mod.type == 'ARMATURE':
        bpy.ops.object.modifier_apply(modifier=mod.name)
        applied = True

# 再把姿势变成 rest pose，让骨骼跟着手臂一起放下来
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.select_all(action='SELECT')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')

# 重新挂上骨架修改器（顶点组还在）
mod = main_mesh.modifiers.new(name="Armature", type='ARMATURE')
mod.object = arm
main_mesh.parent = arm
print("arms baked into rest pose (mesh modifier applied=%s)" % applied)

# ---- 尺寸 / 头部位置（给 Godot 侧定嘴部挂点）----
mw = main_mesh.matrix_world
pts = [mw @ v.co for v in main_mesh.data.vertices]
xs = [p.x for p in pts]
ys = [p.y for p in pts]
zs = [p.z for p in pts]
print("AABB x=(%.3f..%.3f) y=(%.3f..%.3f) z=(%.3f..%.3f)" % (
    min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
head = [p for p in pts if p.z > 1.25]
if head:
    print("HEAD y=(%.3f..%.3f) z=(%.3f..%.3f)" % (
        min(p.y for p in head), max(p.y for p in head),
        min(p.z for p in head), max(p.z for p in head)))

# ---- 只留一层 UV ----
while len(main_mesh.data.uv_layers) > 1:
    main_mesh.data.uv_layers.remove(main_mesh.data.uv_layers[-1])

# ---- 导出 ----
os.makedirs(os.path.dirname(out_glb), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_glb, export_format='GLB', export_apply=False,
                          export_animations=False, export_skins=True, export_yup=True)
print("exported %s (%.2f MB)" % (out_glb, os.path.getsize(out_glb) / 1048576.0))

# ---- 预览图 ----
if preview_dir:
    os.makedirs(preview_dir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.18, 0.19, 1.0)
    for name, loc, rot, energy, size in [
        ("Key", (3.2, -3.2, 3.8), (55, 0, 42), 900, 4),
        ("Fill", (-3.4, -1.6, 2.2), (70, 0, -62), 260, 5),
        ("Rim", (0.6, 3.6, 3.2), (115, 0, 6), 420, 3),
    ]:
        light = bpy.data.lights.new(name, 'AREA')
        light.energy = energy
        light.size = size
        ob = bpy.data.objects.new(name, light)
        ob.location = loc
        ob.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(ob)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 2.2
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    center = ((min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5, (min(zs) + max(zs)) * 0.5)
    from mathutils import Vector
    target = Vector(center)
    for name, (dx, dy) in {"front": (0.0, -4.0), "side": (4.0, 0.0),
                           "three_quarter": (2.9, -2.9)}.items():
        cam.location = Vector((center[0] + dx, center[1] + dy, center[2]))
        cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(preview_dir, "dl_nailong_posed_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)
