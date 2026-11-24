"""快速预览：把当前 .blend 里的网格从四个方向渲染成图，用于判断造型。

用法：
  blender -b <file.blend> -P render_preview.py -- <outdir> <prefix> [dist]
"""

import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv
args = argv[argv.index("--") + 1:] if "--" in argv else []
OUT = args[0] if len(args) > 0 else os.path.join(os.path.dirname(bpy.data.filepath), "previews")
PREFIX = args[1] if len(args) > 1 else "preview"
DIST = float(args[2]) if len(args) > 2 else 0.0

os.makedirs(OUT, exist_ok=True)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not meshes:
    raise SystemExit("no mesh")

# 包围盒
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
        hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
center = (lo + hi) * 0.5
size = (hi - lo).length
if DIST <= 0:
    DIST = size * 1.25

# 地面
bpy.ops.mesh.primitive_plane_add(size=size * 4, location=(center.x, center.y, lo.z - 0.01))
ground = bpy.context.active_object
m = bpy.data.materials.new("PreviewGround")
m.use_nodes = True
m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.18, 0.19, 0.21, 1)
m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
ground.data.materials.append(m)

# 相机
cam_data = bpy.data.cameras.new("PreviewCam")
cam_data.lens = 38
cam = bpy.data.objects.new("PreviewCam", cam_data)
bpy.context.scene.collection.objects.link(cam)
bpy.context.scene.camera = cam

# 三点光
def add_light(name, kind, loc, energy, size_=6.0):
    d = bpy.data.lights.new(name, kind)
    d.energy = energy
    if kind == "AREA":
        d.size = size_
    o = bpy.data.objects.new(name, d)
    o.location = loc
    bpy.context.scene.collection.objects.link(o)
    direction = center - Vector(loc)
    o.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return o

add_light("Key", "AREA", (center.x + size * 0.7, center.y - size * 0.9, center.z + size * 0.8), 260 * size, size * 0.7)
add_light("Fill", "AREA", (center.x - size * 0.9, center.y - size * 0.5, center.z + size * 0.4), 110 * size, size * 0.9)
add_light("Rim", "AREA", (center.x - size * 0.2, center.y + size * 1.0, center.z + size * 0.6), 180 * size, size * 0.6)

sc = bpy.context.scene
try:
    sc.render.engine = "BLENDER_EEVEE"
except Exception:
    sc.render.engine = "BLENDER_WORKBENCH"
sc.render.resolution_x = 1000
sc.render.resolution_y = 760
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("PreviewWorld")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.055, 0.07, 1)
sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0

VIEWS = [
    ("front", -90.0, 14.0),
    ("three_quarter", -56.0, 12.0),
    ("side", -18.0, 10.0),
    ("detail", -74.0, 4.0),
]
for (name, az, el) in VIEWS:
    dist = DIST if name != "detail" else DIST * 0.55
    a = math.radians(az)
    e = math.radians(el)
    pos = center + Vector((math.cos(a) * math.cos(e), -math.sin(a) * math.cos(e), math.sin(e))) * dist
    cam.location = pos
    cam.rotation_euler = (center - pos).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (PREFIX, name))
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", sc.render.filepath)
