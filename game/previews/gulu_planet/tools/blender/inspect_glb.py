import bpy
import json
import os
import sys

# 用法：blender --background --factory-startup --python inspect_glb.py -- <file.glb>
argv = sys.argv
path = argv[argv.index("--") + 1] if "--" in argv else argv[-1]
path = os.path.abspath(path)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

meshes = []
for obj in bpy.context.scene.objects:
    if obj.type != 'MESH':
        continue
    mesh = obj.data
    meshes.append({
        "name": obj.name,
        "location": [round(v, 4) for v in obj.location],
        "dimensions": [round(v, 4) for v in obj.dimensions],
        "vertices": len(mesh.vertices),
        "polygons": len(mesh.polygons),
        "materials": [m.name for m in mesh.materials if m],
        "vertex_groups": [g.name for g in obj.vertex_groups],
        "modifiers": [m.type for m in obj.modifiers],
    })

armatures = []
for obj in bpy.context.scene.objects:
    if obj.type != 'ARMATURE':
        continue
    armatures.append({
        "name": obj.name,
        "bones": len(obj.data.bones),
        "bone_names": [b.name for b in obj.data.bones][:80],
    })

actions = []
for action in bpy.data.actions:
    actions.append({
        "name": action.name,
        "frame_range": [round(v, 2) for v in action.frame_range],
    })

images = [{"name": img.name, "size": list(img.size)} for img in bpy.data.images if img.name != "Render Result"]

bounds = None
for obj in bpy.context.scene.objects:
    if obj.type != 'MESH':
        continue
    corners = [obj.matrix_world @ __import__('mathutils').Vector(c) for c in obj.bound_box]
    mn = [min(c[i] for c in corners) for i in range(3)]
    mx = [max(c[i] for c in corners) for i in range(3)]
    if bounds is None:
        bounds = {"min": mn, "max": mx}
    else:
        bounds["min"] = [min(bounds["min"][i], mn[i]) for i in range(3)]
        bounds["max"] = [max(bounds["max"][i], mx[i]) for i in range(3)]

report = {
    "file": path,
    "blender": bpy.app.version_string,
    "mesh_count": len(meshes),
    "meshes": meshes,
    "armatures": armatures,
    "actions": actions,
    "images": images[:40],
    "bounds": bounds,
}
out = os.path.splitext(path)[0] + "_inspection.json"
with open(out, "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)

print("GLB_INSPECT", path)
print("GLB_MESH_COUNT", len(meshes))
print("GLB_ARMATURES", armatures)
print("GLB_ACTIONS", actions)
print("GLB_BOUNDS", bounds)
print("GLB_REPORT", out)
