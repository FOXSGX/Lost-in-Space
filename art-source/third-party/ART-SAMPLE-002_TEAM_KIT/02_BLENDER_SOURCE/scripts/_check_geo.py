import bpy, sys, math
path = r"C:\Users\ASUS\Desktop\迷失太空\work\art-quality-002-natural\art-source\aq002_geology.blend"
bpy.ops.wm.open_mainfile(filepath=path)
for o in bpy.context.scene.objects:
    if o.type != "MESH":
        continue
    me = o.data
    longest = 0.0
    short = 0
    for p in me.polygons:
        vs = [me.vertices[i].co for i in p.vertices]
        for i in range(len(vs)):
            d = (vs[i] - vs[(i+1) % len(vs)]).length
            longest = max(longest, d)
            if d < 0.001:
                short += 1
    print("CHECK %-22s verts=%6d faces=%6d maxedge=%.2f degenerate=%d" % (o.name, len(me.vertices), len(me.polygons), longest, short))
