"""Generate the editable source preview and an importable glTF binary for the ship hub.

No engine files are touched. Run with: python generate_ship_hub.py
Requires only Pillow for the preview; GLB generation uses the Python standard library.
Coordinates are in metres; Y is up, and the cockpit faces -Z.
"""

from __future__ import annotations

import json
import math
import struct
from dataclasses import dataclass
from pathlib import Path

from PIL import Image


HERE = Path(__file__).resolve().parent
OUT_GLB = HERE / "ship_hub.glb"
OUT_PREVIEW = HERE / "ship_hub-preview.png"

COLORS = {
    "hull": (0.83, 0.80, 0.71),
    "hull_light": (0.92, 0.89, 0.80),
    "hull_shadow": (0.65, 0.66, 0.62),
    "teal": (0.11, 0.48, 0.50),
    "teal_light": (0.21, 0.67, 0.68),
    "teal_dark": (0.07, 0.30, 0.33),
    "floor": (0.52, 0.54, 0.52),
    "floor_alt": (0.58, 0.59, 0.56),
    "dark": (0.11, 0.15, 0.19),
    "orange": (0.94, 0.48, 0.10),
    "cyan": (0.22, 0.87, 0.95),
    "glass": (0.035, 0.095, 0.17),
    "crate": (0.69, 0.68, 0.60),
}


@dataclass
class Part:
    name: str
    material: str
    triangles: list[tuple[tuple[float, float, float], ...]]


parts: list[Part] = []


def add_poly(name: str, material: str, vertices, faces) -> None:
    triangles = []
    for face in faces:
        for i in range(1, len(face) - 1):
            triangles.append((vertices[face[0]], vertices[face[i]], vertices[face[i + 1]]))
    parts.append(Part(name, material, triangles))


def box(name, x, y, z, sx, sy, sz, material):
    x0, x1 = x - sx / 2, x + sx / 2
    y0, y1 = y - sy / 2, y + sy / 2
    z0, z1 = z - sz / 2, z + sz / 2
    v = [(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),
         (x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)]
    f = [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)]
    add_poly(name, material, v, f)


def prism(name, outline, bottom, top, material):
    n = len(outline)
    v = [(x,bottom,z) for x,z in outline] + [(x,top,z) for x,z in outline]
    f = [tuple(range(n-1,-1,-1)), tuple(range(n,2*n))]
    f += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    add_poly(name, material, v, f)


def cylinder(name, x, y, z, radius, height, material, sides=10):
    outline = [(x + radius * math.cos(i*2*math.pi/sides),
                z + radius * math.sin(i*2*math.pi/sides)) for i in range(sides)]
    prism(name, outline, y-height/2, y+height/2, material)


def ring(name, x, y, z, inner, outer, height, material, sides=16):
    v = []
    for yy, rr in ((y-height/2,inner),(y-height/2,outer),
                   (y+height/2,inner),(y+height/2,outer)):
        v += [(x+rr*math.cos(i*2*math.pi/sides), yy,
               z+rr*math.sin(i*2*math.pi/sides)) for i in range(sides)]
    f = []
    for i in range(sides):
        j = (i+1)%sides
        f += [(i,j,2*sides+j,2*sides+i),
              (sides+j,sides+i,3*sides+i,3*sides+j),
              (2*sides+i,2*sides+j,3*sides+j,3*sides+i),
              (j,i,sides+i,sides+j)]
    add_poly(name, material, v, f)


def ico(name, x, y, z, rx, ry, rz, material):
    phi = (1 + math.sqrt(5))/2
    raw = [(-1,phi,0),(1,phi,0),(-1,-phi,0),(1,-phi,0),
           (0,-1,phi),(0,1,phi),(0,-1,-phi),(0,1,-phi),
           (phi,0,-1),(phi,0,1),(-phi,0,-1),(-phi,0,1)]
    v = []
    for a,b,c in raw:
        d = math.sqrt(a*a+b*b+c*c)
        v.append((x+rx*a/d, y+ry*b/d, z+rz*c/d))
    f = [(0,11,5),(0,5,1),(0,1,7),(0,7,10),(0,10,11),
         (1,5,9),(5,11,4),(11,10,2),(10,7,6),(7,1,8),
         (3,9,4),(3,4,2),(3,2,6),(3,6,8),(3,8,9),
         (4,9,5),(2,4,11),(6,2,10),(8,6,7),(9,8,1)]
    add_poly(name, material, v, f)


def build_compact():
    # One continuous walkable deck, about 14 x 11 metres. The model's floor top is Y=0.
    octagon = [(-5.9,-5.5),(5.9,-5.5),(7,-4.4),(7,4.4),
               (5.9,5.5),(-5.9,5.5),(-7,4.4),(-7,-4.4)]
    prism("Deck/structural_floor", octagon, -0.34, -0.06, "dark")
    # Wide, low-contrast floor panels; keep the middle clear for movement.
    for ix,x in enumerate((-5.2,-3.5,-1.8,-0.1,1.6,3.3,5.0)):
        for iz,z in enumerate((-3.4,-1.7,0,1.7,3.4)):
            box(f"Deck/panel_{ix}_{iz}",x,-0.035,z,1.62,0.05,1.62,
                "floor" if (ix+iz)%3 else "floor_alt")
    # Broad framing strips. Right and near walls stay low for an unobstructed isometric camera.
    box("Hull/left_wall",-6.78,1.15,0,0.44,2.30,8.80,"teal")
    box("Hull/right_cutaway_wall",6.78,0.55,0,0.44,1.10,8.80,"teal")
    box("Hull/forward_wall",0,1.35,-5.30,11.9,2.70,0.42,"teal_dark")
    box("Hull/near_left_parapet",-4.30,0.52,5.30,3.30,1.04,0.50,"hull_light")
    box("Hull/near_right_parapet",4.30,0.52,5.30,3.30,1.04,0.50,"hull_light")
    for x in (-6.63,6.63):
        box(f"Hull/upper_rail_{x}",x,2.35 if x<0 else 1.15,0,
            0.57,0.25,8.95,"hull_light")
    for z in (-4.25,-1.45,1.35,4.15):
        box(f"Hull/left_rib_{z}",-6.48,1.23,z,0.66,2.44,0.38,"hull_light")
        box(f"Hull/right_rib_{z}",6.48,0.61,z,0.66,1.22,0.38,"hull_light")
    box("Hull/forward_top_beam",0,2.73,-5.27,11.8,0.28,0.65,"hull_light")

    # Forward panorama and raised, clearly bounded cockpit.
    box("Bridge/panorama_frame",0,1.94,-5.05,8.1,1.45,0.19,"hull_light")
    box("Bridge/panorama_glass",0,1.94,-4.93,7.65,1.10,0.07,"glass")
    box("Bridge/window_lower_rail",0,1.30,-4.88,8.35,0.17,0.34,"dark")
    box("Bridge/platform",0,0.27,-3.78,7.9,0.66,2.95,"floor_alt")
    box("Bridge/platform_front_lip",0,0.25,-2.27,7.9,0.50,0.22,"teal")
    for side in (-1,1):
        # Two small stair runs leave the centre for the planet display.
        sx = side*3.03
        for k in range(3):
            box(f"Bridge/stairs_{side}_{k}",sx,0.10+k*0.20,-1.92-k*0.29,
                1.34,0.20+k*0.20,0.32,"hull_light")
        box(f"Bridge/stair_edge_{side}",side*3.82,0.39,-2.1,0.17,0.75,1.25,"teal")
    # Flight controls and chair. Seat faces the front window (-Z).
    for i,x in enumerate((-2.64,-1.32,0,1.32,2.64)):
        box(f"Bridge/console_{i}",x,1.04,-4.34,1.20,0.64,0.69,"hull")
        box(f"Bridge/screen_{i}",x,1.38,-4.28,0.88,0.035,0.42,
            "cyan" if i==2 else "orange")
    cylinder("Bridge/pilot_chair_pedestal",0,0.88,-3.08,0.36,0.52,"dark",8)
    box("Bridge/pilot_chair_seat",0,1.08,-3.13,0.85,0.20,0.78,"teal")
    box("Bridge/pilot_chair_back",0,1.53,-2.83,0.82,0.84,0.20,"teal_dark")
    box("Bridge/pilot_chair_head",0,2.03,-2.83,0.52,0.21,0.18,"hull")

    # Central star map is a display, while the bridge console is the single selection point.
    cylinder("StarMap/base",0,0.20,-0.34,1.39,0.42,"dark",12)
    ring("StarMap/base_rim",0,0.48,-0.34,1.13,1.43,0.10,"teal_light",16)
    cylinder("StarMap/display_surface",0,0.51,-0.34,1.12,0.04,"cyan",12)
    ico("StarMap/hologram_planet",0,1.19,-0.34,0.50,0.50,0.50,"cyan")
    ring("StarMap/orbit",0,1.06,-0.34,0.69,0.74,0.035,"teal_light",16)

    # Cargo bay left: shelves sit against the wall and do not invade the centre aisle.
    box("Cargo/back_panel",-6.29,1.18,1.75,0.24,1.97,5.55,"teal_dark")
    for z in (-0.90,0.65,2.20,3.75):
        box(f"Cargo/shelf_{z}",-5.55,0.72,z,1.43,0.15,1.37,"hull")
        box(f"Cargo/upper_shelf_{z}",-5.55,1.48,z,1.43,0.15,1.37,"hull")
    for z in (-0.91,0.65,2.2,3.75):
        for y in (0.98,1.74):
            box(f"Cargo/crate_{z}_{y}",-5.52,y,z,0.84,0.40,0.75,
                "crate" if y<1.2 else "teal")
    for z in (0.4,2.45):
        box(f"Cargo/floor_crate_{z}",-4.13,0.33,z,0.83,0.66,0.82,"hull_light")
        box(f"Cargo/floor_crate_band_{z}",-4.13,0.35,z,0.86,0.12,0.84,"orange")

    # Repair bench and oxygen/energy service point on the right wall.
    box("Repair/wall_panel",6.28,1.22,0.87,0.20,1.87,3.20,"teal_dark")
    box("Repair/bench_top",5.33,0.95,0.52,2.15,0.17,1.09,"hull_light")
    box("Repair/bench_base",5.33,0.43,0.52,1.95,0.86,0.92,"teal_dark")
    box("Repair/bench_drawer",5.28,0.48,1.02,1.38,0.22,0.05,"floor_alt")
    box("Repair/tool_panel",6.12,1.65,0.25,0.13,0.66,1.55,"hull")
    for i,z in enumerate((-0.24,0.17,0.57)):
        box(f"Repair/simple_tool_{i}",5.99,1.66,z,0.17,0.47,0.10,"dark")
    cylinder("Recharge/column",5.76,0.85,3.26,0.48,1.70,"hull_light",8)
    cylinder("Recharge/top",5.76,1.72,3.26,0.53,0.18,"teal",8)
    box("Recharge/status_light",5.26,1.10,3.26,0.08,0.40,0.45,"cyan")
    box("Recharge/control",4.62,0.83,3.25,0.40,1.03,0.42,"teal_dark")
    box("Recharge/control_screen",4.43,1.15,3.25,0.04,0.26,0.27,"orange")

    # Airlock: two wall returns, substantial frame, door and short ramp.
    box("Airlock/left_pillar",-1.48,1.25,5.24,0.43,2.50,0.58,"teal")
    box("Airlock/right_pillar",1.48,1.25,5.24,0.43,2.50,0.58,"teal")
    box("Airlock/top_lintel",0,2.39,5.24,3.35,0.35,0.59,"hull_light")
    box("Airlock/door",0,1.17,5.37,2.53,2.15,0.19,"hull")
    box("Airlock/door_center",0,1.15,5.51,1.40,1.58,0.08,"hull_light")
    box("Airlock/door_indicator",0,2.21,5.58,0.48,0.11,0.06,"cyan")
    box("Airlock/outer_ramp",0,-0.19,6.13,3.24,0.22,1.20,"floor_alt")
    for x in (-1.59,1.59):
        box(f"Airlock/ramp_edge_{x}",x,-0.05,6.13,0.15,0.28,1.34,"orange")

    # A separate mission terminal is decorative until its gameplay is decided.
    box("Mission/terminal_stand",-4.78,0.56,-2.59,0.48,1.12,0.55,"teal_dark")
    box("Mission/terminal_screen",-4.78,1.17,-2.72,0.54,0.24,0.44,"orange")



def build():
    """Expand the hull to 42 x 33 m, preserving human-sized equipment."""
    build_compact()
    expanded = []
    offsets = {
        "Cargo": (-12.75, 3.0), "Repair": (12.75, -3.5),
        "Recharge": (12.75, 7.0), "Mission": (-12.75, -7.5),
        "Airlock": (0.0, 10.0),
    }
    for part in parts:
        group = part.name.split("/", 1)[0]
        if part.name.startswith("Deck/panel_"):
            continue
        triangles = []
        xs = [v[0] for tri in part.triangles for v in tri]
        center_x = (min(xs) + max(xs)) / 2
        for tri in part.triangles:
            vertices = []
            for x, y, z in tri:
                if group in ("Deck", "Hull"):
                    x, z = x * 3, z * 3
                elif group == "Bridge":
                    z -= 10.6
                    if any(k in part.name for k in ("panorama", "window_lower")):
                        x *= 3
                    elif "platform" in part.name:
                        x *= 2
                    else:
                        x += center_x  # Spread consoles and stairs, retain object size.
                elif group in offsets:
                    dx, dz = offsets[group]
                    x, z = x + dx, z + dz
                vertices.append((x, y, z))
            triangles.append(tuple(vertices))
        expanded.append(Part(part.name, part.material, triangles))
    parts[:] = expanded
    for ix in range(23):
        x = -19.8 + ix * 1.8
        for iz in range(17):
            z = -14.4 + iz * 1.8
            box(f"Deck/panel_{ix}_{iz}", x, -0.035, z, 1.74, 0.05, 1.74,
                "floor_alt" if (ix + iz) % 6 == 0 else "floor")
    for side_x in (-1, 1):
        for side_z in (-1, 1):
            a = (side_x * 17.7, side_z * 16.5)
            b = (side_x * 21.0, side_z * 13.2)
            dx, dz = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dz)
            nx, nz = -dz / length * 0.3, dx / length * 0.3
            outline = [(a[0]+nx,a[1]+nz),(b[0]+nx,b[1]+nz),
                       (b[0]-nx,b[1]-nz),(a[0]-nx,a[1]-nz)]
            prism(f"Hull/corner_{side_x}_{side_z}", outline, 0, 1.1, "teal")
    # Low deck borders distinguish the service zones without blocking the main hall.
    for name, x, z, sx, sz, color in [
        ("cargo", -16.1, 4.5, 7.0, 10.0, "orange"),
        ("repair", 17.0, -3.0, 5.4, 6.0, "orange"),
        ("supply", 17.0, 10.1, 5.4, 5.0, "cyan"),
        ("bridge", 0, -12.0, 17.0, 6.0, "teal_light"),
    ]:
        for side in (-1, 1):
            box(f"Deck/{name}_edge_{side}", x + side * sx / 2, 0.003, z,
                0.045, 0.015, sz, color)
        box(f"Deck/{name}_front", x, 0.003, z + sz / 2, sx, 0.015, 0.045, color)


def cross(a,b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def sub(a,b):
    return (a[0]-b[0],a[1]-b[1],a[2]-b[2])


def dot(a,b):
    return sum(x*y for x,y in zip(a,b))


def unit(v):
    mag = math.sqrt(dot(v,v))
    return tuple(x/mag for x in v)


def make_glb():
    binary = bytearray()
    views, accessors, meshes, nodes = [], [], [], []
    mats = []
    for name,rgb in COLORS.items():
        rgba = list(rgb) + [0.68 if name=="cyan" else 1.0]
        mat = {"name":name,"pbrMetallicRoughness":{
            "baseColorFactor":rgba,"metallicFactor":0,"roughnessFactor":0.92},
            "doubleSided":True}
        if name=="cyan":
            mat["alphaMode"]="BLEND"
            mat["emissiveFactor"]=[0.06,0.38,0.42]
        mats.append(mat)
    mat_idx = {name:i for i,name in enumerate(COLORS)}

    def append(data, target):
        while len(binary)%4:
            binary.append(0)
        offset = len(binary)
        binary.extend(data)
        views.append({"buffer":0,"byteOffset":offset,"byteLength":len(data),"target":target})
        return len(views)-1

    for part in parts:
        verts, norms = [], []
        for tri in part.triangles:
            n = unit(cross(sub(tri[1],tri[0]),sub(tri[2],tri[0])))
            for v in tri:
                verts.extend(v)
                norms.extend(n)
        count = len(verts)//3
        if count > 65535:
            raise ValueError(f"Too many vertices in {part.name}")
        pv = append(struct.pack("<"+"f"*len(verts),*verts),34962)
        nv = append(struct.pack("<"+"f"*len(norms),*norms),34962)
        iv = append(struct.pack("<"+"H"*count,*range(count)),34963)
        pos = [tuple(verts[i:i+3]) for i in range(0,len(verts),3)]
        low = [min(v[i] for v in pos) for i in range(3)]
        high = [max(v[i] for v in pos) for i in range(3)]
        a_pos = len(accessors)
        accessors.append({"bufferView":pv,"componentType":5126,"count":count,
                          "type":"VEC3","min":low,"max":high})
        a_norm = len(accessors)
        accessors.append({"bufferView":nv,"componentType":5126,"count":count,"type":"VEC3"})
        a_idx = len(accessors)
        accessors.append({"bufferView":iv,"componentType":5123,"count":count,"type":"SCALAR"})
        meshes.append({"name":part.name,"primitives":[{"attributes":{"POSITION":a_pos,
            "NORMAL":a_norm},"indices":a_idx,"material":mat_idx[part.material]}]})
        nodes.append({"name":part.name,"mesh":len(meshes)-1})

    doc = {"asset":{"version":"2.0","generator":"Lost in Space ship hub source generator"},
           "scene":0,"scenes":[{"nodes":list(range(len(nodes)))}],"nodes":nodes,
           "meshes":meshes,"materials":mats,"buffers":[{"byteLength":len(binary)}],
           "bufferViews":views,"accessors":accessors}
    jb = json.dumps(doc,separators=(",",":"),ensure_ascii=False).encode("utf-8")
    jb += b" "*((4-len(jb)%4)%4)
    binary.extend(b"\0"*((4-len(binary)%4)%4))
    total = 12+8+len(jb)+8+len(binary)
    with OUT_GLB.open("wb") as f:
        f.write(struct.pack("<III",0x46546C67,2,total))
        f.write(struct.pack("<I4s",len(jb),b"JSON")); f.write(jb)
        f.write(struct.pack("<I4s",len(binary),b"BIN\0")); f.write(binary)


def make_preview():
    width,height = 1200,800
    im = Image.new("RGB",(width,height),(217,222,222))
    pixels = im.load()
    zbuffer = [float("inf")] * (width*height)
    camera = (51,48,57)
    target = (0,0.3,0)
    forward = unit(sub(target,camera))
    right = unit(cross(forward,(0,1,0)))
    up = cross(right,forward)
    focal = 1790
    def project(v):
        r = sub(v,camera)
        depth = dot(r,forward)
        return (width/2+dot(r,right)*focal/depth,
                height/2-dot(r,up)*focal/depth,depth)
    light = unit((-0.4,0.9,0.45))
    for part in parts:
        color = COLORS[part.material]
        for tri in part.triangles:
            pts = [project(v) for v in tri]
            if min(p[2] for p in pts)<=0:
                continue
            n = unit(cross(sub(tri[1],tri[0]),sub(tri[2],tri[0])))
            illumination = 0.79 + 0.18*max(0,dot(n,light))
            if part.material=="cyan": illumination=1.0
            shade = tuple(max(0,min(255,int(c*255*illumination))) for c in color)
            (x0,y0,d0),(x1,y1,d1),(x2,y2,d2) = pts
            den = (y1-y2)*(x0-x2)+(x2-x1)*(y0-y2)
            if abs(den)<1e-8:
                continue
            min_x=max(0,int(math.floor(min(x0,x1,x2))))
            max_x=min(width-1,int(math.ceil(max(x0,x1,x2))))
            min_y=max(0,int(math.floor(min(y0,y1,y2))))
            max_y=min(height-1,int(math.ceil(max(y0,y1,y2))))
            for yy in range(min_y,max_y+1):
                for xx in range(min_x,max_x+1):
                    px,py=xx+0.5,yy+0.5
                    w0=((y1-y2)*(px-x2)+(x2-x1)*(py-y2))/den
                    w1=((y2-y0)*(px-x2)+(x0-x2)*(py-y2))/den
                    w2=1-w0-w1
                    if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6:
                        continue
                    depth=1/(w0/d0+w1/d1+w2/d2)
                    idx=yy*width+xx
                    if depth < zbuffer[idx]:
                        zbuffer[idx]=depth
                        pixels[xx,yy]=shade
    im.resize((1600,1067),Image.Resampling.LANCZOS).save(OUT_PREVIEW)


if __name__ == "__main__":
    build()
    make_glb()
    make_preview()
    print(f"Generated {len(parts)} named parts: {OUT_GLB.name}, {OUT_PREVIEW.name}")
