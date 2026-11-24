import bpy
from mathutils import Vector
path = r"C:\Users\ASUS\Desktop\迷失太空\work\art-quality-002-natural\art-source\aq002_geology_a.blend"
bpy.ops.wm.open_mainfile(filepath=path)
center = Vector((0.0, 4.0, 8.0))  # Godot (0,5,-8) -> Blender (0,8,5)? see below
# Godot->Blender: (x, -z, y). center godot (0, 4, -8) -> blender (0, 8, 4)
center = Vector((0.0, 8.0, 4.0))
for name in ["Geology_Wall", "Geology_Ceiling", "Geology_Talus", "Geology_Pit"]:
    o = bpy.data.objects.get(name)
    if o is None:
        continue
    me = o.data
    bad = 0
    total = 0
    for p in me.polygons:
        c = p.center
        if p.normal.dot(center - c) < 0:
            bad += 1
        total += 1
    print("NORM %-18s faces=%5d facing_away=%5d" % (name, total, bad))
