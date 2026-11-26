import bpy
import os

PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "test", "blender_link_test.glb"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=PATH)
print("BLENDER_REIMPORT", bpy.app.version_string, PATH)
for obj in bpy.context.scene.objects:
    if obj.type == 'MESH':
        print("OBJECT", obj.name, "loc", tuple(round(v, 3) for v in obj.location), "dim", tuple(round(v, 3) for v in obj.dimensions), "mats", [m.name for m in obj.data.materials if m])
print("MESH_COUNT", len([o for o in bpy.context.scene.objects if o.type == 'MESH']))
