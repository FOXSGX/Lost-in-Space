"""CPU fallback preview and GLB writer for the mining cart silhouette.

This does not replace Blender: it exists so the first-round silhouette can still
be reviewed while the bundled Blender executable fails at Windows startup.
The geometry is authored as explicit primitives and exported as Y-up glTF.
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ITER_DIR = ROOT / "work" / "gameplay-iterations" / "20261019-resonance-mining-cart-v1"
GLB_PATH = ROOT / "game" / "assets" / "resonance" / "models" / "resonance_mining_transport_cart_v1_fallback.glb"
ITER_DIR.mkdir(parents=True, exist_ok=True)
GLB_PATH.parent.mkdir(parents=True, exist_ok=True)

COLORS = {
    "orange": (0.76, 0.20, 0.045),
    "cream": (0.96, 0.52, 0.10),
    "steel": (0.16, 0.20, 0.22),
    "edge": (0.35, 0.42, 0.43),
    "dark": (0.028, 0.035, 0.040),
    "glass": (0.025, 0.18, 0.24),
    "cyan": (0.03, 0.72, 0.86),
    "amber": (1.00, 0.28, 0.03),
    "yellow": (1.00, 0.62, 0.06),
    "clay": (0.58, 0.61, 0.62),
    "clay_dark": (0.30, 0.32, 0.33),
}

parts: list[dict] = []


def add_part(name, verts, faces, material):
    parts.append({"name": name, "verts": [tuple(float(v) for v in p) for p in verts], "faces": [tuple(f) for f in faces], "material": material})


def box(name, c, d, material, rot_z=0.0):
    cx, cy, cz = c
    dx, dy, dz = d
    local = [(-dx/2,-dy/2,-dz/2),(dx/2,-dy/2,-dz/2),(dx/2,dy/2,-dz/2),(-dx/2,dy/2,-dz/2),
             (-dx/2,-dy/2,dz/2),(dx/2,-dy/2,dz/2),(dx/2,dy/2,dz/2),(-dx/2,dy/2,dz/2)]
    co, si = math.cos(rot_z), math.sin(rot_z)
    verts=[]
    for x,y,z in local:
        verts.append((cx + co*x - si*y, cy + si*x + co*y, cz + z))
    faces=[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(4,0,3,7)]
    add_part(name, verts, faces, material)


def extruded_profile(name, points_xz, y_center, thickness, material):
    h=thickness/2.0
    verts=[(x,y_center-h,z) for x,z in points_xz] + [(x,y_center+h,z) for x,z in points_xz]
    n=len(points_xz)
    faces=[tuple(range(n-1,-1,-1)), tuple(range(n,2*n))]
    for i in range(n):
        j=(i+1)%n
        faces.append((i,j,n+j,n+i))
    add_part(name, verts, faces, material)


def cylinder(name, center, radius, depth, material, axis="y", segments=20):
    cx,cy,cz=center
    verts=[]
    for i in range(segments):
        a=2*math.pi*i/segments
        u,v=radius*math.cos(a),radius*math.sin(a)
        if axis=="y": verts.append((cx+u,cy-depth/2,cz+v))
        elif axis=="z": verts.append((cx+u,cy+v,cz-depth/2))
    for i in range(segments):
        a=2*math.pi*i/segments
        u,v=radius*math.cos(a),radius*math.sin(a)
        if axis=="y": verts.append((cx+u,cy+depth/2,cz+v))
        elif axis=="z": verts.append((cx+u,cy+v,cz+depth/2))
    faces=[tuple(range(segments-1,-1,-1)), tuple(range(segments,2*segments))]
    for i in range(segments):
        j=(i+1)%segments
        faces.append((i,j,segments+j,segments+i))
    add_part(name, verts, faces, material)


def sphere(name, center, radii, material, rings=8, segments=16):
    cx,cy,cz=center; rx,ry,rz=radii
    verts=[]
    for r in range(rings+1):
        phi=math.pi*r/rings
        for s in range(segments):
            th=2*math.pi*s/segments
            verts.append((cx+rx*math.sin(phi)*math.cos(th), cy+ry*math.sin(phi)*math.sin(th), cz+rz*math.cos(phi)))
    faces=[]
    for r in range(rings):
        for s in range(segments):
            a=r*segments+s; b=r*segments+(s+1)%segments; c=(r+1)*segments+(s+1)%segments; d=(r+1)*segments+s
            faces.append((a,b,c,d))
    add_part(name, verts, faces, material)


def pipe(name, a, b, radius, material, segments=12):
    ax,ay,az=a; bx,by,bz=b
    dx,dy,dz=bx-ax,by-ay,bz-az
    L=math.sqrt(dx*dx+dy*dy+dz*dz)
    ux,uy,uz=dx/L,dy/L,dz/L
    ref=(0.0,0.0,1.0) if abs(uz)<0.9 else (0.0,1.0,0.0)
    vx=uy*ref[2]-uz*ref[1]; vy=uz*ref[0]-ux*ref[2]; vz=ux*ref[1]-uy*ref[0]
    vl=math.sqrt(vx*vx+vy*vy+vz*vz); vx,vy,vz=vx/vl,vy/vl,vz/vl
    wx=uy*vz-uz*vy; wy=uz*vx-ux*vz; wz=ux*vy-uy*vx
    verts=[]
    for p in (a,b):
        for i in range(segments):
            th=2*math.pi*i/segments; co,si=math.cos(th),math.sin(th)
            verts.append((p[0]+radius*(co*vx+si*wx), p[1]+radius*(co*vy+si*wy), p[2]+radius*(co*vz+si*wz)))
    faces=[tuple(range(segments-1,-1,-1)),tuple(range(segments,2*segments))]
    for i in range(segments):
        j=(i+1)%segments; faces.append((i,j,segments+j,segments+i))
    add_part(name, verts, faces, material)


def torus(name, center, major, minor, material, vertical=True, seg_major=32, seg_minor=8):
    cx,cy,cz=center; verts=[]
    for i in range(seg_major):
        u=2*math.pi*i/seg_major
        for j in range(seg_minor):
            v=2*math.pi*j/seg_minor
            x=(major+minor*math.cos(v))*math.cos(u)
            y=(major+minor*math.cos(v))*math.sin(u)
            z=minor*math.sin(v)
            if vertical: verts.append((cx+x,cy+y,cz+z))
            else: verts.append((cx+x,cy+y,cz+z))
    faces=[]
    for i in range(seg_major):
        for j in range(seg_minor):
            a=i*seg_minor+j; b=i*seg_minor+(j+1)%seg_minor; c=((i+1)%seg_major)*seg_minor+(j+1)%seg_minor; d=((i+1)%seg_major)*seg_minor+j
            faces.append((a,b,c,d))
    # vertical ring is generated in XY by default; rotate around X to XZ.
    if vertical:
        for idx,(x,y,z) in enumerate(verts):
            verts[idx]=(x, cy + (z-cz), cz + (y-cy))
    add_part(name, verts, faces, material)


def build():
    box("Chassis/impact_keel", (0,0,1.45), (8.9,3.35,1.0), "steel")
    box("Chassis/painted_sill", (0,0,2.08), (8.2,3.25,0.42), "orange")
    box("Chassis/inner_deck", (-0.55,0,2.36), (6.2,2.55,0.30), "edge")
    for y in (-1.55,1.55):
        box(f"Chassis/side_sill_{y}", (0,y,1.95), (8.75,0.26,0.78), "cream")
    cradle=[(-4.16,2.18),(-3.92,3.18),(-3.34,4.12),(-2.25,4.56),(-0.70,4.62),(0.55,4.25),(1.32,3.48),(1.46,2.25)]
    for side in (-1,1):
        extruded_profile(f"CargoCradle/outer_cheek_{side}", cradle, side*1.58, 0.34, "orange")
        extruded_profile(f"CargoCradle/inner_cheek_{side}", [(x+0.14,z-0.15) for x,z in cradle[1:-1]], side*1.39, 0.16, "cream")
        pipe(f"CargoCradle/top_guard_{side}",(-3.48,side*1.77,3.65),(0.64,side*1.77,4.02),0.11,"edge")
        pipe(f"CargoCradle/rear_guard_{side}",(-3.98,side*1.77,2.60),(-3.50,side*1.77,3.88),0.09,"steel")
    box("CargoCradle/floor",(-1.35,0,2.70),(4.65,2.55,0.28),"dark")
    box("CargoCradle/floor_liner",(-1.18,0,2.86),(3.95,2.12,0.12),"steel")
    box("CargoCradle/cargo_mount",(-1.18,0,3.12),(2.55,1.72,.18),"edge")
    torus("ResonanceLoop/outer_frame",(-0.84,0,4.78),1.33,0.14,"steel",True)
    torus("ResonanceLoop/glow_ring",(-0.84,0,4.78),1.07,0.075,"cyan",True)
    sphere("ResonanceLoop/core",(-0.84,0,4.78),(0.38,0.38,0.38),"cyan")
    for side in (-1,1):
        pipe(f"ResonanceLoop/support_{side}",(-1.72,side*.88,3.40),(-.84,side*.88,4.60),.12,"edge")
        pipe(f"ResonanceLoop/support_foot_{side}",(-2.12,side*1.08,3.08),(-1.70,side*.88,3.40),.15,"steel")
    cabin=[(.72,2.20),(1.30,2.12),(2.66,2.55),(3.72,3.28),(3.64,4.05),(2.92,4.70),(1.80,4.86),(1.02,4.35)]
    extruded_profile("Cabin/outer_wedge", cabin,0,3.15,"cream")
    box("Cabin/front_bumper",(3.82,0,2.55),(.30,3.18,.62),"steel",rot_z=0.0)
    box("Cabin/visor",(3.48,0,3.72),(.16,2.12,.78),"glass")
    box("Cabin/visor_glow",(3.59,0,3.30),(.10,2.30,.12),"cyan")
    extruded_profile("Cabin/side_window_left",[(1.62,3.55),(2.75,3.55),(3.22,3.80),(2.75,4.26),(1.80,4.34)],-1.60,0.08,"glass")
    extruded_profile("Cabin/side_window_right",[(1.62,3.55),(2.75,3.55),(3.22,3.80),(2.75,4.26),(1.80,4.34)],1.60,0.08,"glass")
    extruded_profile("Cabin/side_armor_left",[(0.82,2.42),(1.95,2.38),(3.02,2.86),(2.72,3.22),(1.05,3.12)],-1.70,0.12,"orange")
    extruded_profile("Cabin/side_armor_right",[(0.82,2.42),(1.95,2.38),(3.02,2.86),(2.72,3.22),(1.05,3.12)],1.70,0.12,"orange")
    box("Cabin/side_marker_left",(2.30,-1.77,3.12),(.22,.05,.10),"yellow")
    box("Cabin/side_marker_right",(2.30,1.77,3.12),(.22,.05,.10),"yellow")
    for side in (-1,1):
        box(f"Cabin/cheek_{side}",(2.35,side*1.61,3.27),(1.42,.18,.78),"orange",rot_z=0.0)
        box(f"ServicePanel/{side}/housing",(.72,side*1.77,2.72),(1.20,.26,.78),"steel")
        box(f"ServicePanel/{side}/panel",(.72,side*1.92,2.74),(.82,.06,.42),"orange")
        box(f"ServicePanel/{side}/status",(.88,side*1.97,2.74),(.08,.035,.22),"cyan")
    for idx,x in enumerate((-2.62,2.34)):
        box(f"Bogie/{idx}/crossbeam",(x,0,.88),(1.72,3.04,.36),"steel")
        box(f"Bogie/{idx}/center_block",(x,0,1.12),(1.18,1.48,.55),"dark")
        for side in (-1,1):
            cylinder(f"Bogie/{idx}/wheel_{side}",(x,side*1.45,.62),.48,.34,"dark",axis="y")
            torus(f"Bogie/{idx}/hub_{side}",(x,side*1.64,.62),.24,.06,"yellow",vertical=False)
            pipe(f"Bogie/{idx}/suspension_{side}",(x,side*1.22,1.05),(x,side*1.45,.86),.12,"edge")
            box(f"Bogie/{idx}/rail_jaw_{side}",(x,side*1.93,.58),(.74,.25,.52),"orange")
    box("RearCounterweight/housing",(-3.95,0,2.55),(.56,2.65,1.24),"steel")
    box("RearCounterweight/amber_band",(-4.27,0,2.54),(.08,2.70,.20),"amber")


def material_color(name, clay):
    if clay:
        return COLORS["clay_dark"] if name in ("dark","steel") else COLORS["clay"]
    return COLORS[name]


def render(label, elev, azim, clay=False):
    fig=plt.figure(figsize=(12,9),dpi=110)
    ax=fig.add_subplot(111,projection="3d")
    ax.set_facecolor((0.012,0.018,0.028)); fig.patch.set_facecolor((0.012,0.018,0.028))
    for part in parts:
        polys=[[part["verts"][i] for i in face] for face in part["faces"]]
        poly=Poly3DCollection(polys,facecolors=material_color(part["material"],clay),edgecolors=(0.03,0.04,0.045),linewidths=0.28,alpha=1.0)
        ax.add_collection3d(poly)
    # rail read is deliberately preview-only.
    for y in (-1.18,1.18):
        ax.plot([-7,7],[y,y],[0.05,0.05],color=(0.25,0.30,0.31),lw=3)
        for x in (-7,-5,-3,-1,1,3,5,7): ax.plot([x,x],[-1.75,1.75],[0,0],color=(0.18,0.22,0.23),lw=2)
    ax.set_xlim(-5.8,5.8); ax.set_ylim(-4.5,4.5); ax.set_zlim(0,7.2)
    ax.set_box_aspect((11.6,9.0,7.2)); ax.view_init(elev=elev,azim=azim)
    ax.set_axis_off(); plt.tight_layout(pad=0)
    out=ITER_DIR/(label+".png"); fig.savefig(out,bbox_inches="tight",pad_inches=0,dpi=110); plt.close(fig)
    return out


def pack_glb():
    # Flatten every face as independent triangles; this keeps the fallback GLB simple and robust.
    positions=[]; normals=[]; colors=[]; batches=[]; indices=[]
    material_names=list(COLORS.keys())[:10]
    mat_index={m:i for i,m in enumerate(material_names)}
    for part in parts:
        start=len(positions); idx=[]
        for face in part["faces"]:
            if len(face)<3: continue
            for k in range(1,len(face)-1):
                tri=(face[0],face[k],face[k+1])
                p0=part["verts"][tri[0]]; p1=part["verts"][tri[1]]; p2=part["verts"][tri[2]]
                ux,uy,uz=p1[0]-p0[0],p1[1]-p0[1],p1[2]-p0[2]
                vx,vy,vz=p2[0]-p0[0],p2[1]-p0[1],p2[2]-p0[2]
                nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
                ln=math.sqrt(nx*nx+ny*ny+nz*nz) or 1.0; n=(nx/ln,ny/ln,nz/ln)
                for p in (p0,p1,p2):
                    # z-up preview -> Y-up glTF; preserve handedness by flipping depth.
                    positions.append((p[0],p[2],-p[1])); normals.append((n[0],n[2],-n[1])); c=COLORS[part["material"]]; colors.append((c[0],c[1],c[2],1.0)); idx.append(len(positions)-1)
        batches.append({"name":part["name"],"material":mat_index[part["material"]],"first":len(indices),"count":len(idx)})
        indices.extend(idx)
    pos_blob=b''.join(struct.pack('<3f',*p) for p in positions)
    norm_blob=b''.join(struct.pack('<3f',*n) for n in normals)
    color_blob=b''.join(struct.pack('<4f',*c) for c in colors)
    ind_blob=b''.join(struct.pack('<I',i) for i in indices)
    # align each view to 4 bytes
    def pad(b): return b + b'\0'*((-len(b))%4)
    pos_blob=pad(pos_blob); norm_blob=pad(norm_blob); color_blob=pad(color_blob); ind_blob=pad(ind_blob)
    blob=pos_blob+norm_blob+color_blob+ind_blob
    views=[{"buffer":0,"byteOffset":0,"byteLength":len(pos_blob),"target":34962},
           {"buffer":0,"byteOffset":len(pos_blob),"byteLength":len(norm_blob),"target":34962},
           {"buffer":0,"byteOffset":len(pos_blob)+len(norm_blob),"byteLength":len(color_blob),"target":34962},
           {"buffer":0,"byteOffset":len(pos_blob)+len(norm_blob)+len(color_blob),"byteLength":len(ind_blob),"target":34963}]
    accessors=[]
    accessors.append({"bufferView":0,"componentType":5126,"count":len(positions),"type":"VEC3","min":[min(p[i] for p in positions) for i in range(3)],"max":[max(p[i] for p in positions) for i in range(3)]})
    accessors.append({"bufferView":1,"componentType":5126,"count":len(normals),"type":"VEC3"})
    accessors.append({"bufferView":2,"componentType":5126,"count":len(colors),"type":"VEC4"})
    accessors.append({"bufferView":3,"componentType":5125,"count":len(indices),"type":"SCALAR"})
    materials=[]
    for name in material_names:
        c=COLORS[name]; materials.append({"name":"RS_"+name,"pbrMetallicRoughness":{"baseColorFactor":[1.0,1.0,1.0,1.0],"metallicFactor":0.6 if name in ('steel','edge','orange','cream') else 0.15,"roughnessFactor":0.28 if name in ('cyan','glass','amber') else 0.42},"emissiveFactor":[c[0]*0.08,c[1]*0.08,c[2]*0.08] if name in ('cyan','amber') else [0,0,0]})
    meshes=[]
    for batch in batches:
        # one mesh per authored part; all accessors point to the flattened stream with a local index offset.
        mesh={"name":batch["name"],"primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"COLOR_0":2},"indices":3,"material":batch["material"]}]}
        meshes.append(mesh)
    # Use one mesh that contains all geometry and one node; names remain in extras for the review tool.
    primitives=[]
    cursor=0
    for batch in batches:
        primitives.append({"attributes":{"POSITION":0,"NORMAL":1,"COLOR_0":2},"indices":3,"material":batch["material"],"extras":{"part":batch["name"]}})
        cursor+=batch["count"]
    # The flattened index stream is global; a single primitive is the safest representation.
    mesh={"name":"RES_MiningTransportCart_V1_Fallback","primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"COLOR_0":2},"indices":3,"material":0,"extras":{"parts":[p["name"] for p in parts]}}]}
    doc={"asset":{"version":"2.0","generator":"Lost in Space CPU fallback cart builder"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"RES_MiningTransportCart_V1_Fallback","mesh":0,"extras":{"asset_id":"resonance_mining_transport_cart_v1","status":"fallback_until_blender_recovers"}}],"meshes":[mesh],"materials":materials,"accessors":accessors,"bufferViews":views,"buffers":[{"byteLength":len(blob)}]}
    raw=json.dumps(doc,separators=(',',':')).encode('utf-8'); raw += b' '*((-len(raw))%4)
    blob=blob
    glb=b'glTF'+struct.pack('<II',2,12+8+len(raw)+8+len(blob))+struct.pack('<I',len(raw))+b'JSON'+raw+struct.pack('<I',len(blob))+b'BIN\0'+blob
    GLB_PATH.write_bytes(glb)


def main():
    build()
    render("grey_45",25,-48,True)
    render("grey_front",18,-90,True)
    render("grey_side",18,0,True)
    render("grey_top",78,-80,True)
    render("grey_close",30,-56,True)
    render("color_45",25,-48,False)
    pack_glb()
    print("FALLBACK_PREVIEW_DIR="+str(ITER_DIR))
    print("FALLBACK_GLB="+str(GLB_PATH))

if __name__=="__main__": main()
