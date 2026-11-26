import bpy
import json
import math
import os
from mathutils import Vector

# 独立测试资产：1 m 模块 + 前向/顶部标记，用来验证 Blender → GLB → Godot 的
# 比例、轴向与材质链路。与奶龙角色无关，不替换角色。

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "test", "blender_link_test.glb"))
META = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "test", "blender_link_test.json"))
BLEND = os.path.abspath(os.path.join(os.path.dirname(__file__), "blender_link_test.blend"))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0

def material(name, color, metallic=0.0, roughness=0.55):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat

body_mat = material("BodyMat", (0.85, 0.32, 0.12), 0.1, 0.45)
nose_mat = material("ForwardMat", (1.0, 0.82, 0.16), 0.0, 0.5)
top_mat = material("TopMat", (0.18, 0.85, 0.45), 0.0, 0.5)
back_mat = material("BackMat", (0.15, 0.35, 0.75), 0.0, 0.5)

# 1 m 主体（0.8 m 宽、0.8 m 深、0.8 m 高），底部在 z=0。
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.4))
body = bpy.context.object
body.name = "Body"
body.dimensions = (0.8, 0.8, 0.8)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
bevel = body.modifiers.new("Bevel", 'BEVEL')
bevel.width = 0.035
bevel.segments = 2
body.data.materials.append(body_mat)

# Blender +Y 前向标记；glTF 导出后应到 Godot 的 -Z。
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0.0, 0.65, 0.4))
fwd = bpy.context.object
fwd.name = "ForwardMarker"
fwd.data.materials.append(nose_mat)

# Blender +Z 顶部标记；glTF 导出后应到 Godot 的 +Y。
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.10, location=(0.0, 0.0, 0.92))
top = bpy.context.object
top.name = "TopMarker"
top.data.materials.append(top_mat)

# Blender -Y 后向标记，帮助判断旋转。
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, -0.68, 0.4))
back = bpy.context.object
back.name = "BackMarker"
back.dimensions = (0.25, 0.18, 0.25)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
back.data.materials.append(back_mat)

for obj in bpy.context.scene.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = body

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    use_selection=False,
    export_apply=True,
    export_yup=True,
    export_materials='EXPORT',
)

# 记录元数据，方便后续检查。
bounds = []
for obj in bpy.context.scene.objects:
    if obj.type == 'MESH':
        corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        mins = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
        maxs = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
        bounds.append({"name": obj.name, "min": list(mins), "max": list(maxs)})

bpy.ops.wm.save_as_mainfile(filepath=BLEND)

meta = {
    "blender": bpy.app.version_string,
    "units": "m",
    "forward_blender": "+Y",
    "up_blender": "+Z",
    "export": "GLB / glTF 2.0 / +Y up",
    "file": "res://assets/test/blender_link_test.glb",
    "blend": "res://tools/blender/blender_link_test.blend",
    "objects": bounds,
    "materials": [m.name for m in bpy.data.materials if m.users > 0],
}
with open(META, "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False, indent=2)

print("BLENDER_TEST_EXPORT", OUT)
print("BLENDER_TEST_OBJECTS", [o.name for o in bpy.context.scene.objects])
print("BLENDER_TEST_MATERIALS", meta["materials"])
