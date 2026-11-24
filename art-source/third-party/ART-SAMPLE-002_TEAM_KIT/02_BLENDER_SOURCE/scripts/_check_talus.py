import bpy
path = r"C:\Users\ASUS\Desktop\迷失太空\work\art-quality-002-natural\art-source\aq002_geology.blend"
bpy.ops.wm.open_mainfile(filepath=path)
o = bpy.data.objects["Geology_Talus"]
me = o.data
worst = (0, None)
for p in me.polygons:
    vs = [me.vertices[i].co for i in p.vertices]
    for i in range(len(vs)):
        d = (vs[i] - vs[(i+1) % len(vs)]).length
        if d > worst[0]:
            worst = (d, p.index)
print("WORST", worst)
p = me.polygons[worst[1]]
for i in p.vertices:
    print("  v", tuple(round(c, 2) for c in me.vertices[i].co))
