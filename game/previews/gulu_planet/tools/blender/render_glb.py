import bpy
import os
import sys
from mathutils import Vector

argv = sys.argv
path = argv[argv.index("--") + 1] if "--" in argv else argv[-1]
path = os.path.abspath(path)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
scene = bpy.context.scene

# Scene bounds
mins = Vector((1e9, 1e9, 1e9))
maxs = Vector((-1e9, -1e9, -1e9))
for obj in scene.objects:
    if obj.type != 'MESH':
        continue
    for corner in obj.bound_box:
        p = obj.matrix_world @ Vector(corner)
        mins.x = min(mins.x, p.x); mins.y = min(mins.y, p.y); mins.z = min(mins.z, p.z)
        maxs.x = max(maxs.x, p.x); maxs.y = max(maxs.y, p.y); maxs.z = max(maxs.z, p.z)
center = (mins + maxs) * 0.5
size = maxs - mins
radius = max(size.x, size.y, size.z, 0.5)

# Camera from three-quarter front (+Y is the test-asset forward; use -Y/3-4 view)
cam_data = bpy.data.cameras.new("PreviewCamera")
cam = bpy.data.objects.new("PreviewCamera", cam_data)
scene.collection.objects.link(cam)
cam.location = center + Vector((radius * 1.4, -radius * 2.2, radius * 0.55))
direction = center - cam.location
cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
cam_data.lens = 50
scene.camera = cam

# Lights
for name, loc, energy, size_l in [
    ("Key", center + Vector((radius * 2.0, -radius * 2.0, radius * 2.0)), 1100, radius * 2.0),
    ("Fill", center + Vector((-radius * 2.0, -radius * 1.0, radius * 1.2)), 500, radius * 2.0),
]:
    light_data = bpy.data.lights.new(name, 'AREA')
    light_data.energy = energy
    light_data.size = size_l
    light = bpy.data.objects.new(name, light_data)
    light.location = loc
    scene.collection.objects.link(light)
    light.rotation_euler = (center - light.location).to_track_quat('-Z', 'Y').to_euler()

world = bpy.data.worlds.new("PreviewWorld")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.035, 0.045, 0.06, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
scene.world = world

scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
out = os.path.splitext(path)[0] + "_preview.png"
scene.render.filepath = out
scene.render.film_transparent = False
bpy.ops.render.render(write_still=True)
print("GLB_RENDER", out)
print("GLB_RENDER_BOUNDS", list(mins), list(maxs))
