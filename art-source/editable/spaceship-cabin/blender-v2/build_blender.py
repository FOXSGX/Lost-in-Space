"""Blender 4.5: polish the existing ship without moving gameplay anchors.

Run: blender --background --python build_blender.py
Source coordinates supplied to helpers are Godot X/Y-up/Z metres.
Original GLB remains untouched. No downloaded assets or textures are used.
"""
from pathlib import Path
import bpy
import bmesh
import json
import math
from mathutils import Vector
from collections import defaultdict

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
ORIGINAL = ROOT / "game/assets/ship-hub/ship_hub.glb"
RUNTIME = ROOT / "game/assets/ship-hub/ship_hub_blender_v2.glb"
HERE.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ORIGINAL))
original_meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
original_faces = sum(len(o.data.polygons) for o in original_meshes)

def linear(v):
    return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4

def mat(name, color, rough=.6, metal=0, glow=0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    rgb = tuple(linear(int(color[i:i+2], 16) / 255) for i in (0, 2, 4))
    m.node_tree.nodes.clear()
    p = m.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    output = m.node_tree.nodes.new('ShaderNodeOutputMaterial')
    m.node_tree.links.new(p.outputs['BSDF'], output.inputs['Surface'])
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    p.inputs['Emission Color'].default_value = (*rgb, 1)
    p.inputs['Emission Strength'].default_value = glow
    m.diffuse_color = (*rgb, 1)
    return m

palette = {
    'hull': ('D6D7C9', .58, .05, 0), 'hull_light': ('EEE8D9', .53, .03, 0),
    'hull_shadow': ('899D98', .65, 0, 0), 'teal': ('366D77', .5, .12, 0),
    'teal_dark': ('233F50', .6, .08, 0), 'teal_light': ('76BDB4', .5, .1, 0),
    'floor': ('657F89', .82, .03, 0), 'floor_alt': ('69838D', .82, .03, 0),
    'deck_mid': ('435F70', .8, .03, 0), 'dark': ('30495B', .62, .15, 0),
    'orange': ('EAA366', .52, .1, 0), 'ivory': ('F1E8D6', .58, .02, 0),
    'coral': ('C77F70', .85, 0, 0), 'sage': ('8EB2A0', .85, 0, 0),
    'screen': ('163C50', .4, .05, .05), 'screen_light': ('8BDDD3', .4, .05, .65),
    'lamp': ('F9D69D', .5, 0, .55), 'cyan': ('75D8D2', .4, .15, .25),
    'chrome': ('93AEB2', .35, .6, 0), 'rubber': ('293D49', .85, 0, 0),
}
for name, args in palette.items():
    mat(name, *args)

M = {
    'ink': mat('V2_Ink', '243B4E', .65, .1),
    'ivory': mat('V2_Porcelain', 'E7E3D6', .5, .08),
    'deck': mat('V2_DeckInset', '3D596B', .8, .06),
    'deck2': mat('V2_DeckRaised', '4D6C7B', .78, .04),
    'seam': mat('V2_Seam', '344F61', .8),
    'teal': mat('V2_Enamel', '387B84', .48, .18),
    'mint': mat('V2_Mint', '8ABEB4', .65),
    'copper': mat('V2_Orange', 'D9955A', .48, .22),
    'light': mat('V2_LightMint', '8EDDD4', .5, .08, .5),
    'warm': mat('V2_LightWarm', 'F6D4A0', .5, 0, .55),
    'screen': mat('V2_Screen', '102D42', .4, .12, .04),
    'graphic': mat('V2_ScreenGraphic', '8AD8D4', .5, 0, .7),
    'violet': mat('V2_LogViolet', 'AAA5D4', .5, .05, .25),
    'metal': mat('V2_SatinMetal', 'A4B8B6', .36, .55),
    'planet': mat('V2_HologramOcean', '50BFC7', .45, .25, .2),
    'land': mat('V2_HologramLand', 'A8E1C6', .6, .1, .15),
}

# Weld the triangle-soup importer and recalculate normals before new work.
for o in original_meshes:
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.00001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(o.data)
    bm.free()
    for poly in o.data.polygons:
        poly.use_smooth = not o.name.startswith(('Deck/', 'Hull/'))
    o.data.set_sharp_from_angle(angle=math.radians(45))
    if o.name.startswith(('StarMap/', 'Deck/star_map_outline')):
        bpy.data.objects.remove(o, do_unlink=True)

def pos(p):
    return (p[0], -p[2], p[1])

def finish(o, name, material):
    o.name = name
    o.data.materials.clear()
    o.data.materials.append(M[material] if isinstance(material, str) else material)
    return o

def box(name, p, size, material, bevel=.05, angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos(p))
    o = bpy.context.object
    o.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new('Soft manufactured edges', 'BEVEL')
        mod.width = min(bevel, min(size) * .35)
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
        for poly in o.data.polygons:
            # Keep broad planar faces exactly flat; only fillets interpolate.
            # This avoids triangulated highlights after glTF/Godot import.
            poly.use_smooth = max(abs(v) for v in poly.normal) < .9999
        o.data.set_sharp_from_angle(angle=math.radians(45))
        normal = o.modifiers.new('Weighted face normals', 'WEIGHTED_NORMAL')
        normal.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=normal.name)
    o.rotation_euler.z = -angle
    return finish(o, name, material)

def cyl(name, p, radius, height, material, vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=height, location=pos(p))
    o = bpy.context.object
    bevel = o.modifiers.new('Edge fillet', 'BEVEL')
    bevel.width = min(.04, height * .18)
    bevel.segments = 3
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    for poly in o.data.polygons:
        poly.use_smooth = len(poly.vertices) == 4
    return finish(o, name, material)

def ring(name, p, radius, thickness, material, tilt=0):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=thickness, major_segments=64, minor_segments=8, location=pos(p))
    o = bpy.context.object
    o.rotation_euler.x = tilt
    for poly in o.data.polygons:
        poly.use_smooth = True
    return finish(o, name, material)

def line(name, points, thickness, material):
    c = bpy.data.curves.new(name, 'CURVE')
    c.dimensions = '3D'
    c.resolution_u = 1
    c.bevel_depth = thickness
    c.bevel_resolution = 2
    spline = c.splines.new('POLY')
    spline.points.add(len(points)-1)
    for v, p in zip(spline.points, points):
        v.co = (*pos(p), 1)
    o = bpy.data.objects.new(name, c)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.convert(target='MESH')
    o = bpy.context.object
    o.select_set(False)
    return finish(o, name, material)

def text(name, value, p, size, material, plane='floor'):
    c = bpy.data.curves.new(name, 'FONT')
    c.body = value
    c.size = size
    c.align_x = 'CENTER'
    c.align_y = 'CENTER'
    c.extrude = .0005
    c.resolution_u = 3
    o = bpy.data.objects.new(name, c)
    bpy.context.collection.objects.link(o)
    o.location = pos(p)
    if plane == 'back':
        o.rotation_euler.x = math.pi / 2
    elif plane == 'left':
        o.rotation_euler = (math.pi / 2, 0, math.pi / 2)
    elif plane == 'right':
        o.rotation_euler = (math.pi / 2, 0, -math.pi / 2)
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.object, name, material)

def floor_chevron(name, x, z, color='warm'):
    line(name, [(x-.25,.037,z+.12),(x,.037,z-.12),(x+.25,.037,z+.12)], .025, color)

# Rebuild old furniture cases with native bevel topology, eliminating diagonal
# shading wedges inherited from the original hand-authored triangle soup.
for old in list(bpy.context.scene.objects):
    if old.type != 'MESH':
        continue
    is_case = old.name.startswith(('Decor/bench_', 'Bridge/console_', 'Bridge/pilot_chair_seat',
        'Bridge/pilot_chair_back', 'Bridge/pilot_chair_head', 'Repair/bench_', 'Recharge/control'))
    is_round = old.name.startswith(('Decor/planter_', 'Decor/side_table_top_', 'Decor/side_table_leg_'))
    if not is_case and not is_round:
        continue
    points=[old.matrix_world@Vector(v) for v in old.bound_box]
    low=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    center=(low+high)*.5
    extent=high-low
    name=old.name
    material=old.data.materials[0]
    bpy.data.objects.remove(old,do_unlink=True)
    p=(center.x,center.z,-center.y)
    size=(extent.x,extent.z,extent.y)
    if is_round:
        cyl(name,p,size[0]*.5,size[1],material,48)
    else:
        box(name,p,size,material,.10)

# Central promenade: contrasting large plates with a restrained navigation spine.
for z in [-9, -6, -3, 3, 6, 9, 12]:
    for side in [-1, 1]:
        box(f'V2Deck/plate_{side}_{z}', (side*4.25,.013,z), (5.55,.012,2.88), 'deck2', .03)
        box(f'V2Deck/service_notch_{side}_{z}', (side*6.65,.027,z+.95), (.48,.012,.07), 'mint', .01)
for z in [-9.2,-6.5,5.8,8.0,11.3,13.5]:
    floor_chevron(f'V2Deck/heading_{z}', 0,z)
for x in [-7.5,7.5]:
    for z in [-8,-4,0,4,8,12]:
        box(f'V2Deck/inset_light_{x}_{z}', (x,.032,z), (.07,.012,1.15),'light',.01)

# Broad zone pads and approach guides sit below the boot sole, outside collision logic.
zones=[('CARGO',(-17.5,4.5),(4.5,8.1),'copper','02'),
       ('WORKSHOP',(17.45,-2.98),(4.3,4.4),'copper','03'),
       ('LIFE SUPPORT',(17.5,10.2),(4.2,4.0),'mint','04'),
       ('FLIGHT LOG',(-17.7,-9.5),(4.1,4.1),'violet','05')]
for zone,(x,z),(sx,sz),accent,num in zones:
    key=zone.replace(' ','_')
    box(f'V2Deck/{key}_pad',(x,.016,z),(sx,.016,sz),'deck',.025)
    box(f'V2Deck/{key}_threshold',(x,.035,z+sz/2-.18),(sx-.36,.012,.1),accent,.01)
    # Keep labels horizontal to match the fixed gameplay camera.
    text(f'V2Deck/{key}_id',num,(x,.04,z+sz/2-.65),.62,accent)
    for side in [-1,1]:
        box(f'V2Deck/{key}_corner_{side}',(x+side*(sx/2-.12),.035,z+sz/2-.38),(.08,.012,.6),accent,.01)
text('V2Deck/homeward_wordmark','H O M E W A R D',(0,.043,8.7),.49,'mint')
text('V2Deck/ship_id','GH / 214',(0,.043,12.0),.30,'ivory')

# A radial floor graphic and a richer globe table stay inside the existing 2.9 m collider.
for r in [2.15,2.85]:
    ring(f'V2Deck/briefing_ring_{r}',(0,.033,-.34),r,.016,'mint')
for i in range(24):
    a=math.tau*i/24
    box(f'V2Deck/briefing_tick_{i}',(2.57*math.cos(a),.036,-.34+2.57*math.sin(a)),(.18,.01,.035),'light' if i%6==0 else 'mint',.006,angle=-a)
cyl('V2StarMap/plinth',(0,.18,-.34),1.37,.36,'ink')
cyl('V2StarMap/body',(0,.41,-.34),1.26,.25,'ivory')
cyl('V2StarMap/dark_top',(0,.565,-.34),1.3,.08,'screen')
ring('V2StarMap/illuminated_lip',(0,.61,-.34),1.25,.035,'light')
for i in range(8):
    a=math.tau*i/8
    box(f'V2StarMap/radial_trim_{i}',(1.245*math.cos(a),.40,-.34+1.245*math.sin(a)),(.14,.24,.14),'teal',.035,angle=a)
    box(f'V2StarMap/interface_{i}',(.99*math.cos(a),.617,-.34+.99*math.sin(a)),(.24,.015,.12),'graphic',.02,angle=-a)
bpy.ops.mesh.primitive_uv_sphere_add(segments=40,ring_count=20,radius=.55,location=pos((0,1.31,-.34)))
planet=finish(bpy.context.object,'V2StarMap/hologram_planet','planet')
for poly in planet.data.polygons: poly.use_smooth=True
# Stylized land plates on the planet are separate low raised facets.
for i,(lat,lon) in enumerate([(10,0),(22,25),(42,40),(-18,80),(-30,110),(48,170),(24,210),(-10,235)]):
    a,b=math.radians(lat),math.radians(lon)
    p=(.55*math.cos(a)*math.cos(b),1.31+.55*math.sin(a),-.34+.55*math.cos(a)*math.sin(b))
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=pos(p))
    o=finish(bpy.context.object,f'V2StarMap/land_{i}','land')
    o.scale=(.18,.13,.07)
    o.rotation_euler=Vector(pos((p[0],p[1]-1.31,p[2]+.34))).to_track_quat('Z','Y').to_euler()
ring('V2StarMap/orbit',(0,1.31,-.34),.88,.018,'light',.42)
ring('V2StarMap/equator',(0,1.31,-.34),.566,.008,'graphic')
for y,r in [(.72,.4),(.84,.28),(.96,.17)]:
    ring(f'V2StarMap/projection_{y}',(0,y,-.34),r,.012,'graphic')

# Rear bulkhead: layered observation window, inset wall panels and low visual hierarchy.
for x in [-16,-13,13,16]:
    box(f'V2Hull/aft_panel_{x}',(x,1.35,-15.55),(2.5,2.12,.13),'ivory',.16)
    box(f'V2Hull/aft_inset_{x}',(x,1.37,-15.45),(1.9,1.55,.06),'teal',.12)
    for y in [.9,1.15,1.4]:
        box(f'V2Hull/aft_vent_{x}_{y}',(x,y,-15.405),(1.25,.05,.025),'ink',.01)
for x in [-9,-4.5,0,4.5,9]:
    box(f'V2Bridge/window_mullion_{x}',(x,1.94,-14.72),(.1,1.3,.12),'ivory',.03)
box('V2Bridge/window_lower_warm_strip',(0,1.24,-14.68),(22.8,.04,.07),'warm',.01)
box('V2Bridge/window_upper_trim',(0,2.74,-14.80),(24.6,.18,.26),'ivory',.08)
text('V2Bridge/nameplate','H O M E W A R D  /  G H - 2 1 4',(0,2.73,-14.64),.24,'ink','back')

# Port and starboard wall panels, service channels, access hatches and corner lamps.
for side in [-1,1]:
    for i,z in enumerate([-10,-6,-2,2,6,10]):
        height=1.75 if side<0 else .66
        y=1.15 if side<0 else .55
        box(f'V2Hull/side_panel_{side}_{i}',(side*20.05,y,z),(.15,height,3.4),'ivory',.10)
        box(f'V2Hull/side_inset_{side}_{i}',(side*19.95,y,z),(.04,height*.63,2.85),'teal',.025)
        box(f'V2Hull/lower_service_{side}_{i}',(side*19.86,.19,z),(.08,.1,3.35),'ink',.025)
        box(f'V2Hull/guide_light_{side}_{i}',(side*19.82,.28,z),(.04,.04,1.2),'light',.012)
        if side<0:
            for dz in [-.75,.75]:
                box(f'V2Hull/access_hinge_{i}_{dz}',(-19.88,1.1,z+dz),(.08,.5,.07),'metal',.02)

# Existing station footprints: clear silhouettes and readable work surfaces.
for z in [2.1,3.65,5.2,6.75]:
    for y in [.98,1.74]:
        box(f'V2Cargo/face_{z}_{y}',(-17.79,y,z),(.04,.25,.52),'ink',.025)
        box(f'V2Cargo/display_{z}_{y}',(-17.761,y+.04,z),(.012,.09,.25),'graphic',.006)
box('V2Cargo/rack_header',(-18.29,2.14,4.45),(1.45,.16,6.1),'ivory',.05)
for z in [1.7,3.7,5.7,7.2]:
    box(f'V2Cargo/shelf_light_{z}',(-17.60,1.5,z),(.04,.045,.65),'warm',.012)

# Technical enamel on the repair station: dial, tool dock, drawer recesses.
for z in [-3.36,-2.98,-2.60]:
    box(f'V2Repair/drawer_face_{z}',(17.08,.58,z),(.02,.25,.31),'teal',.025)
    box(f'V2Repair/pull_{z}',(17.055,.62,z),(.045,.06,.15),'metal',.012)
for i in range(5):
    box(f'V2Repair/tool_socket_{i}',(18.7,1.44,-3.57+i*.25),(.12,.18,.10),'ink',.025)
ring('V2Repair/diagnostic_ring',(18.33,1.54,-2.95),.22,.024,'light')
box('V2Repair/screen',(18.33,1.053,-3.31),(.44,.018,.24),'screen',.03)
for i in range(3):
    box(f'V2Repair/status_trace_{i}',(18.20+i*.1,1.066,-3.31),(.045,.008,.08+i*.035),'graphic',.005)

# Life support collar, small pulse gauges, and blue-white medical insignia.
for y in [.16,.48,1.48]:
    ring(f'V2Supply/structural_collar_{y}',(18.51,y,10.26),.46,.035,'metal')
for i in range(8):
    a=math.tau*i/8
    box(f'V2Supply/cooling_fin_{i}',(18.51+.45*math.cos(a),.9,10.26+.45*math.sin(a)),(.05,.85,.05),'teal',.012)
box('V2Supply/control_recess',(17.14,1.15,10.25),(.025,.32,.31),'screen',.025)
box('V2Supply/cross_v',(17.12,1.15,10.25),(.02,.20,.06),'graphic',.01)
box('V2Supply/cross_h',(17.105,1.15,10.25),(.02,.06,.20),'graphic',.01)

# Lounge upholstery, modest seams and useful surface details within existing furniture.
for side in [-1,1]:
    for z in [-4.8,5.2]:
        for dx in [-.5,.5]:
            box(f'V2Lounge/seat_piping_{side}_{z}_{dx}',(side*8.7+dx,.73,z),(.025,.014,.7),'ivory',.005)
        box(f'V2Lounge/base_toe_{side}_{z}',(side*8.7,.09,z+.48),(2.5,.07,.04),'metal',.012)
    ring(f'V2Lounge/planter_rim_{side}',(side*11.7,.93,.7),.54,.025,'copper')
    box(f'V2Lounge/table_book_{side}',(side*11.3-.05,.77,5.2-.1),(.3,.05,.23),'mint',.02)

# Convert material groups into labelled collections in the native editable source.
scene=bpy.context.scene
source_objects=[o for o in scene.objects if o.type=='MESH']
for o in source_objects:
    prefix=o.name.split('/')[0]
    col=bpy.data.collections.get(prefix) or bpy.data.collections.new(prefix)
    if col.name not in scene.collection.children:
        scene.collection.children.link(col)
    for previous in list(o.users_collection): previous.objects.unlink(o)
    col.objects.link(o)

# Source includes a studio rig; meshes only are exported to the game.
world=bpy.data.worlds.new('Deep blue studio')
world.use_nodes=True
world.node_tree.nodes.clear()
background=world.node_tree.nodes.new('ShaderNodeBackground')
world_output=world.node_tree.nodes.new('ShaderNodeOutputWorld')
world.node_tree.links.new(background.outputs[0],world_output.inputs['Surface'])
background.inputs[0].default_value=(.055,.085,.12,1)
background.inputs[1].default_value=.4
scene.world=world
def area(name, location, target, energy, size, color):
    data=bpy.data.lights.new(name,'AREA')
    data.energy=energy
    data.shape='DISK'
    data.size=size
    data.color=color
    o=bpy.data.objects.new(name,data)
    scene.collection.objects.link(o)
    o.location=pos(location)
    o.rotation_euler=(Vector(pos(target))-o.location).to_track_quat('-Z','Y').to_euler()
area('Studio_Key',(-12,24,10),(0,0,0),14000,24,(1,.88,.72))
area('Studio_Fill',(20,18,-10),(0,0,0),10000,22,(.66,.84,1))
area('Studio_Rim',(-12,12,-20),(0,0,0),7000,16,(.60,1,.9))
sun_data=bpy.data.lights.new('Studio_Sun','SUN')
sun_data.energy=1.1
sun_data.angle=.2
sun=bpy.data.objects.new('Studio_Sun',sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler=(math.radians(28),math.radians(-20),math.radians(-25))
camera_data=bpy.data.cameras.new('Overview_Camera')
camera=bpy.data.objects.new('Overview_Camera',camera_data)
scene.collection.objects.link(camera)
camera_data.type='ORTHO'
camera_data.ortho_scale=56
camera.location=pos((36,39,46))
camera.rotation_euler=(Vector(pos((0,.3,0)))-camera.location).to_track_quat('-Z','Y').to_euler()
scene.camera=camera
scene.render.engine='CYCLES'
scene.cycles.samples=24
scene.cycles.use_denoising=True
try:
    cycles_preferences=bpy.context.preferences.addons['cycles'].preferences
    cycles_preferences.compute_device_type='OPTIX'
    cycles_preferences.get_devices()
    for device in cycles_preferences.devices:
        device.use=device.type=='OPTIX'
    if any(d.type=='OPTIX' for d in cycles_preferences.devices):
        scene.cycles.device='GPU'
except Exception:
    pass
scene.render.resolution_x=1600
scene.render.resolution_y=1120
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=False
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
scene.view_settings.exposure=.4
scene.render.filepath=str(HERE/'blender-overview.png')
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'ship_hub.blend'))

# Export mesh batches by functional zone/material. Keep window and airlock filtering names.
bpy.ops.object.select_all(action='DESELECT')
batches=defaultdict(list)
for o in source_objects:
    if 'panorama_glass' in o.name:
        key='Bridge_panorama_glass'
    elif o.name.startswith('Airlock/'):
        key=o.name.replace('/','_')
    else:
        group=o.name.split('/')[0]
        if group=='Decor' and 'central_deck' in o.name:
            group='Deck'
        if group=='V2Deck': group='Deck'
        key=group+'_'+o.data.materials[0].name
    batches[key].append(o)
export_meshes=[]
for name, objects in batches.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects: o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    if len(objects)>1: bpy.ops.object.join()
    o=bpy.context.object
    o.name=name
    export_meshes.append(o)
bpy.ops.object.select_all(action='DESELECT')
for o in export_meshes: o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(RUNTIME),export_format='GLB',use_selection=True,
    export_cameras=False,export_lights=False,export_animations=False,export_extras=False,
    export_apply=True,export_yup=True)
# Native source before batching is the editable deliverable. Render exported geometry.
scene.render.filepath=str(HERE/'blender-overview.png')
bpy.ops.render.render(write_still=True)
stats={'blender':bpy.app.version_string,'original_meshes':len(original_meshes),
       'original_triangles':original_faces,'editable_meshes':len(source_objects),
       'runtime_meshes':len(export_meshes),
       'runtime_triangles':sum(len(p.vertices)-2 for o in export_meshes for p in o.data.polygons),
       'source':str(HERE/'ship_hub.blend'),'runtime':str(RUNTIME)}
(HERE/'asset-stats.json').write_text(json.dumps(stats,ensure_ascii=False,indent=2),encoding='utf-8')
print('SHIP_ART_COMPLETE',json.dumps(stats))
