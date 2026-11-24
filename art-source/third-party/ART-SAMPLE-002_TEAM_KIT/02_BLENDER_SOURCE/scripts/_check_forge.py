import bpy
from mathutils import Vector
path = r"C:\Users\ASUS\Desktop\迷失太空\work\art-quality-002-natural\art-source\aq002_forge.blend"
bpy.ops.wm.open_mainfile(filepath=path)
o = bpy.data.objects.get("ForgeStatic")
me = o.data
target = Vector((0.62, -1.16, 0.88))  # Blender = (x, -z, y)
found = []
for v in me.vertices:
    if (v.co - target).length < 0.12:
        found.append((round(v.co.x,2), round(v.co.y,2), round(v.co.z,2)))
print("NEAR", len(found), found[:8])
# 统计 y 在 0.8..1.0 且 z 在 1.0..1.3 的顶点
cnt = 0
for v in me.vertices:
    gx, gy, gz = v.co.x, v.co.z, -v.co.y
    if 0.5 < gx < 0.8 and 0.8 < gy < 1.0 and 1.0 < gz < 1.3:
        cnt += 1
print("ZONE", cnt)
