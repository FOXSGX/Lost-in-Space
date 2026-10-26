"""Build the continuous cave vertical slice for Resonance Planet (option A).

The scene is intentionally standalone: entrance chamber -> mineral tunnel -> second
cavern. It is a Blender authored route prototype, with RES_ empties for Godot
anchors. Existing Resonance assets are not overwritten.
"""
from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = Path(__file__).resolve().parent
MODEL_DIR = ROOT / "game" / "assets" / "resonance" / "models"
BLEND_PATH = SOURCE_DIR / "resonance_cave_vertical_slice_v2.blend"
PREVIEW_PATH = SOURCE_DIR / "resonance_cave_vertical_slice_v2-preview.png"
GLB_PATH = MODEL_DIR / "resonance_cave_vertical_slice_v2.glb"


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name: str, color, metallic=0.0, roughness=0.82, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if name.startswith("Cave_Rock"):
        noise = mat.node_tree.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 2.8
        noise.inputs["Detail"].default_value = 3.0
        noise.inputs["Roughness"].default_value = 0.72
        bump = mat.node_tree.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.16
        bump.inputs["Distance"].default_value = 0.22
        mat.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        mat.node_tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    mat.diffuse_color = (*color, 1.0)
    return mat


def make_materials():
    return {
        "rock": material("Cave_Rock_Clay", (0.28, 0.13, 0.085), 0.0, 0.88),
        "rock_light": material("Cave_Rock_Peach", (0.50, 0.25, 0.12), 0.0, 0.82),
        "rock_dark": material("Cave_Rock_PlumShadow", (0.10, 0.065, 0.11), 0.0, 0.92),
        "floor": material("Cave_Walkable_Slate", (0.22, 0.20, 0.28), 0.0, 0.82),
        "metal": material("Embedded_Factory_TealMetal", (0.055, 0.15, 0.17), 0.62, 0.34),
        "metal_edge": material("Embedded_Factory_HoneyEdge", (0.52, 0.28, 0.07), 0.58, 0.30),
        "cyan": material("Resonance_Cyan", (0.04, 0.48, 0.56), 0.12, 0.25, (0.10, 0.90, 1.0), 3.6),
        "amber": material("Resonance_Amber", (0.82, 0.34, 0.07), 0.10, 0.26, (1.0, 0.52, 0.08), 3.0),
        "green": material("Resonance_Green", (0.06, 0.48, 0.24), 0.10, 0.26, (0.18, 1.0, 0.52), 3.6),
        "crystal": material("Cave_Crystal_Cyan", (0.06, 0.34, 0.50), 0.10, 0.20, (0.15, 0.85, 1.0), 3.8),
        "crystal_warm": material("Cave_Crystal_Sun", (0.86, 0.32, 0.07), 0.10, 0.22, (1.0, 0.55, 0.08), 3.3),
        "warning": material("Cave_Transition_Coral", (0.82, 0.24, 0.08), 0.16, 0.28, (1.0, 0.30, 0.06), 3.0),
    }


def assign(obj, mat):
    obj.data.materials.append(mat)
    return obj


def add_box(name, location, dimensions, mat, bevel=0.0, rotation=(0.0, 0.0, 0.0), parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    if bevel > 0.0:
        modifier = obj.modifiers.new("SoftEdge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    if parent is not None:
        obj.parent = parent
    return obj


def add_cylinder(name, location, radius, depth, mat, rotation=(0.0, 0.0, 0.0), vertices=16, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    if parent is not None:
        obj.parent = parent
    return obj


def add_rock(name, location, scale, mat, seed, parent=None):
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    for vertex in obj.data.vertices:
        wobble = 0.93 + rng.random() * 0.14
        vertex.co *= wobble
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    bpy.ops.object.shade_smooth()
    if parent is not None:
        obj.parent = parent
    return obj


def add_crystal(name, location, height, radius, mat, rotation, parent=None):
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=radius, radius2=radius * 0.12, depth=height, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    if parent is not None:
        obj.parent = parent
    return obj


def add_anchor(name, location, anchor_type, parent=None):
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.65
    empty.location = location
    empty["anchor_type"] = anchor_type
    empty["route_id"] = "resonance_cave_vertical_slice_v1"
    if parent is not None:
        empty.parent = parent
    bpy.context.collection.objects.link(empty)
    return empty


def add_light(name, location, color, energy, radius=5.0):
    data = bpy.data.lights.new(name, type="AREA")
    data.energy = energy
    data.color = color
    data.shape = "DISK"
    data.size = radius
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    bpy.context.collection.objects.link(obj)
    return obj


def add_rock_wall_line(prefix, x_values, z, y_center, scale_z, mat, seed_base):
    for index, x in enumerate(x_values):
        height = scale_z * (0.85 + 0.22 * math.sin(index * 1.8))
        add_rock(f"{prefix}_{index:02d}", (x, y_center + height * 0.35, z), (3.8, height * 0.48, 2.2), mat, seed_base + index)
        if index % 2 == 0:
            add_rock(f"{prefix}_lower_{index:02d}", (x + 0.6, 1.2, z + (0.6 if z > 0 else -0.6)), (3.6, 1.5, 2.4), mat, seed_base + 100 + index)


def build_floor(m):
    add_box("CaveWalkableFloor", (34.0, -0.45, 0.0), (108.0, 0.9, 40.0), m["floor"], bevel=0.25)
    # Raised stone islands communicate a safe route without creating a visual wall.
    for index, (x, z, sx, sz) in enumerate([
        (-8.0, 10.0, 4.0, 2.5), (5.0, 10.0, 4.0, 2.2),
        (31.0, 9.0, 3.0, 2.0), (62.0, 11.0, 4.0, 2.4),
        (78.0, 12.0, 4.0, 2.2),
    ]):
        add_rock(f"WalkableRockIsland_{index}", (x, 0.0, z), (sx, 0.32, sz), m["rock_light"], 700 + index)


def build_chamber_one(m):
    root = bpy.data.objects.new("RES_Chamber01_Entrance", None)
    bpy.context.collection.objects.link(root)
    # Side walls leave the route and entrance open on the X axis.
    xs = [-14.0, -9.0, -4.0, 1.0, 6.0, 11.0]
    add_rock_wall_line("Chamber01_WallNorth", xs, 14.5, 5.7, 9.0, m["rock"], 100)
    add_rock_wall_line("Chamber01_WallSouth", xs, -14.5, 5.4, 8.5, m["rock"], 130)
    # A broken back wall gives the entrance a readable silhouette.
    for index, z in enumerate([-10.0, -5.0, 5.0, 10.0]):
        add_rock(f"Chamber01_Back_{index}", (-16.2, 4.5 + index % 2, z), (2.7, 5.0 + index * 0.6, 3.2), m["rock_light"], 180 + index)
    # Roof ribs form an authored cave, while keeping the center open to the camera.
    for index, x in enumerate([-13.0, -6.0, 1.0, 8.0, 14.0]):
        roof_z = 7.0 if index % 2 == 0 else -7.0
        add_rock(f"Chamber01_RoofRib_{index}", (x, 16.0 + (index % 2) * 0.6, roof_z), (3.3, 1.3, 4.0), m["rock_dark"], 220 + index)
    # Entrance arch at the west side.
    for index, z in enumerate([-11.0, -7.0, 7.0, 11.0]):
        add_rock(f"EntranceArch_{index}", (-18.0, 4.0 + abs(z) * 0.25, z), (2.4, 4.7, 2.2), m["rock_light"], 250 + index)
    add_rock("EntranceArchTop", (-18.0, 12.0, 0.0), (2.7, 2.2, 13.0), m["rock_light"], 258)
    add_anchor("RES_Entrance", (-17.0, 0.0, 0.0), "entrance", root)
    add_anchor("RES_Respawn01", (-9.0, 0.2, 0.0), "respawn", root)
    add_anchor("RES_Chamber01_Camera", (-4.0, 8.0, 8.0), "camera_focus", root)


def build_task_one(m):
    root = bpy.data.objects.new("RES_Task01_DoubleLock", None)
    bpy.context.collection.objects.link(root)
    # Embedded rail and two opposed lock stations make the cooperation visible.
    add_box("Task01_RailBed", (-2.0, 0.25, 0.0), (22.0, 0.5, 3.2), m["metal"], bevel=0.12, parent=root)
    for z in (-1.0, 1.0):
        add_box(f"Task01_Rail_{z}", (-2.0, 0.78, z), (22.0, 0.16, 0.16), m["metal_edge"], bevel=0.05, parent=root)
    for side, x, accent in [("Power", -9.0, m["cyan"]), ("Clamp", 5.0, m["amber"])]:
        add_box(f"Task01_{side}_Pedestal", (x, 0.8, 0.0), (2.8, 1.5, 4.2), m["metal"], bevel=0.18, parent=root)
        add_cylinder(f"Task01_{side}_Beacon", (x, 2.0, 0.0), 0.75, 0.28, accent, rotation=(math.pi / 2, 0.0, 0.0), parent=root)
        add_box(f"Task01_{side}_Panel", (x, 1.45, -2.05), (1.2, 0.7, 0.22), accent, bevel=0.08, parent=root)
    # A physical rock/metal transition gate is already open in the authored slice.
    add_rock("Transition01_LeftRock", (12.5, 4.6, -5.0), (2.2, 4.8, 3.0), m["rock_light"], 290, root)
    add_rock("Transition01_RightRock", (12.5, 4.6, 5.0), (2.2, 4.8, 3.0), m["rock_light"], 291, root)
    add_box("Transition01_OverheadBeam", (12.5, 10.5, 0.0), (2.4, 2.2, 11.0), m["metal"], bevel=0.18, parent=root)
    add_box("Transition01_OpeningLight", (12.7, 4.8, 0.0), (0.18, 5.8, 0.22), m["cyan"], bevel=0.04, parent=root)
    add_anchor("RES_Task01_Power", (-9.0, 0.2, 0.0), "task_power", root)
    add_anchor("RES_Task01_Clamp", (5.0, 0.2, 0.0), "task_clamp", root)
    add_anchor("RES_Transition01_MineGate", (12.5, 0.2, 0.0), "transition", root)


def build_tunnel(m):
    root = bpy.data.objects.new("RES_Tunnel01_Mineral", None)
    bpy.context.collection.objects.link(root)
    xs = [17.0, 22.0, 27.0, 32.0, 37.0, 42.0, 47.0]
    add_rock_wall_line("Tunnel_WallNorth", xs, 6.8, 3.5, 5.0, m["rock"], 320)
    add_rock_wall_line("Tunnel_WallSouth", xs, -6.8, 3.3, 4.8, m["rock"], 360)
    for index, x in enumerate(xs):
        add_rock(f"Tunnel_Roof_{index}", (x, 8.9 + (index % 2) * 0.6, 0.0), (2.8, 1.9, 6.8), m["rock_dark"], 400 + index)
    # Embedded mineral rail, readable as the route through the tunnel.
    add_box("MineralRouteBed", (32.0, 0.2, 0.0), (35.0, 0.35, 2.0), m["metal"], bevel=0.10, parent=root)
    for z in (-0.65, 0.65):
        add_box(f"MineralRouteRail_{z}", (32.0, 0.65, z), (35.0, 0.14, 0.14), m["cyan"], bevel=0.04, parent=root)
    for index, x in enumerate([21.0, 29.0, 37.0, 45.0]):
        add_crystal(f"TunnelCrystal_{index}", (x, 3.0 + (index % 2) * 0.6, 5.4 if index % 2 == 0 else -5.4), 3.2, 0.7, m["crystal" if index % 2 == 0 else "crystal_warm"], (0.12, 0.2 * index, 0.18), root)
        add_box(f"TunnelPathMarker_{index}", (x, 0.82, 0.0), (1.4, 0.04, 0.55), m["amber"], bevel=0.02, parent=root)
    add_anchor("RES_Tunnel01_Entry", (16.0, 0.2, 0.0), "transition", root)
    add_anchor("RES_Tunnel01_Exit", (48.0, 0.2, 0.0), "transition", root)
    add_anchor("RES_Tunnel01_Camera", (32.0, 6.0, 5.0), "camera_focus", root)


def build_chamber_two(m):
    root = bpy.data.objects.new("RES_Chamber02_MineralCathedral", None)
    bpy.context.collection.objects.link(root)
    xs = [53.0, 59.0, 65.0, 71.0, 77.0, 83.0]
    add_rock_wall_line("Chamber02_WallNorth", xs, 18.0, 7.0, 12.0, m["rock"], 500)
    add_rock_wall_line("Chamber02_WallSouth", xs, -18.0, 7.0, 11.5, m["rock"], 540)
    for index, x in enumerate([55.0, 63.0, 71.0, 79.0, 87.0]):
        add_rock(f"Chamber02_Roof_{index}", (x, 17.0 + (index % 2) * 1.2, 0.0), (4.4, 2.8, 16.0), m["rock_dark"], 580 + index)
    # Crystals become the far landmark and explain why the factory is here.
    for index, (x, z, h, r) in enumerate([(58, 12, 8.0, 1.1), (66, -12, 6.0, 0.9), (73, 12, 10.0, 1.3), (82, -10, 7.0, 1.0), (87, 10, 11.0, 1.25)]):
        add_crystal(f"CathedralCrystal_{index}", (x, 4.0 + h * 0.45, z), h, r, m["crystal" if index % 2 == 0 else "crystal_warm"], (0.09, 0.22 * index, -0.12), root)
    # A compact cooperative loading station anchors the second task.
    add_box("Task02_FreightDeck", (69.0, 0.35, 0.0), (16.0, 0.7, 7.0), m["metal"], bevel=0.20, parent=root)
    add_box("Task02_FreightCrate", (65.0, 2.1, 0.0), (3.8, 3.0, 3.8), m["metal_edge"], bevel=0.28, parent=root)
    for z in (-1.25, 1.25):
        add_box(f"Task02_CrateGlow_{z}", (65.0, 2.1, z), (2.0, 0.25, 0.18), m["amber"], bevel=0.04, parent=root)
    add_box("Task02_StableSocket", (75.0, 1.2, 4.0), (3.0, 1.5, 1.1), m["green"], bevel=0.18, parent=root)
    add_cylinder("Task02_SocketRing", (75.0, 2.0, 4.0), 1.0, 0.25, m["green"], rotation=(math.pi / 2, 0.0, 0.0), parent=root)
    add_anchor("RES_Chamber02_Entry", (51.0, 0.2, 0.0), "transition", root)
    add_anchor("RES_Task02_Freight", (65.0, 0.2, 0.0), "task_freight", root)
    add_anchor("RES_Task02_StableSocket", (75.0, 0.2, 4.0), "task_stabilizer", root)
    add_anchor("RES_Respawn02", (56.0, 0.2, -7.0), "respawn", root)
    add_anchor("RES_Chamber02_Camera", (72.0, 10.0, 12.0), "camera_focus", root)
    add_anchor("RES_Exit", (88.0, 0.2, 0.0), "exit", root)


def build_scene(m):
    root = bpy.data.objects.new("RES_ResonanceCaveVerticalSlice_v1", None)
    bpy.context.collection.objects.link(root)
    build_floor(m)
    build_chamber_one(m)
    build_task_one(m)
    build_tunnel(m)
    build_chamber_two(m)
    # A few directional lights keep the route readable without flattening the cave.
    add_light("EntranceFill", (-8.0, 10.0, 3.0), (1.0, 0.40, 0.18), 900.0, 9.0)
    add_light("TunnelCyanFill", (32.0, 6.5, 0.0), (0.12, 0.45, 1.0), 700.0, 8.0)
    add_light("CathedralGlow", (73.0, 11.0, -2.0), (0.15, 0.85, 1.0), 1300.0, 12.0)
    # Route markers: warm at the current task, cyan at the transition, green at the next task.
    add_anchor("RES_RouteStart", (-13.0, 0.2, 0.0), "route_start", root)
    add_anchor("RES_RouteDirection", (25.0, 0.2, 0.0), "route_direction", root)
    add_anchor("RES_RouteGoal", (73.0, 0.2, 4.0), "route_goal", root)
    return root


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("CaveSliceWorld")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    if background is not None:
        background.inputs["Color"].default_value = (0.025, 0.015, 0.012, 1.0)
        background.inputs["Strength"].default_value = 0.42
    camera_data = bpy.data.cameras.new("CaveSliceReviewCamera")
    camera = bpy.data.objects.new("CaveSliceReviewCamera", camera_data)
    camera.location = (0.0, 4.5, 0.0)
    camera_data.lens = 30.0
    camera_data.sensor_width = 36.0
    look_at(camera, (40.0, 3.2, 0.5))
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    scene.view_settings.exposure = 1.0
    # A neutral sun reveals the rock silhouette while local lights retain task readability.
    sun_data = bpy.data.lights.new("CaveSun", type="SUN")
    sun_data.energy = 2.5
    sun_data.angle = math.radians(18.0)
    sun = bpy.data.objects.new("CaveSun", sun_data)
    sun.rotation_euler = (math.radians(28.0), math.radians(-32.0), math.radians(20.0))
    bpy.context.collection.objects.link(sun)
    add_light("RouteSoftbox", (37.0, 21.0, 12.0), (0.82, 0.48, 0.30), 4200.0, 22.0)


def export_glb():
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_extras=True,
    )


def main():
    clear_scene()
    mats = make_materials()
    build_scene(mats)
    setup_render()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    # Render is performed by the separate preview helper; skipping it here avoids
    # Blender's Windows thumbnail writer crashing in headless Eevee sessions.
    export_glb()
    print(f"CAVE_VERTICAL_SLICE blend={BLEND_PATH}")
    print(f"CAVE_VERTICAL_SLICE preview={PREVIEW_PATH}")
    print(f"CAVE_VERTICAL_SLICE glb={GLB_PATH}")


main()
