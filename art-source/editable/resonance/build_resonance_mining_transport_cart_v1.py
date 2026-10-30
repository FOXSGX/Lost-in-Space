"""Build Resonance Star mining transport cart v1.

Phase 1 focuses on authored silhouette and believable mechanical structure.
The source .blend keeps preview cameras/lights; the GLB excludes them.
Run from repository root with:
  tools/blender-5.2.2-windows-x64/blender.exe -b --python art-source/editable/resonance/build_resonance_mining_transport_cart_v1.py
"""
from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / "art-source" / "editable" / "resonance"
MODEL_DIR = ROOT / "game" / "assets" / "resonance" / "models"
ITER_DIR = ROOT / "work" / "gameplay-iterations" / "20261019-resonance-mining-cart-v1"
BLEND_PATH = SOURCE_DIR / "resonance_mining_transport_cart_v1.blend"
GLB_PATH = MODEL_DIR / "resonance_mining_transport_cart_v1.glb"


def ensure_dirs() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    ITER_DIR.mkdir(parents=True, exist_ok=True)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def set_input(node, name: str, value) -> None:
    socket = node.inputs.get(name)
    if socket is not None:
        socket.default_value = value


def make_material(name: str, color: tuple[float, float, float, float], metallic: float = 0.0,
                  roughness: float = 0.45, emission=None, emission_strength: float = 0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    set_input(bsdf, "Base Color", color)
    set_input(bsdf, "Metallic", metallic)
    set_input(bsdf, "Roughness", roughness)
    if emission is not None:
        set_input(bsdf, "Emission Color", emission)
        set_input(bsdf, "Emission Strength", emission_strength)
    links.new(bsdf.outputs[0], output.inputs[0])
    return mat


def make_materials() -> dict[str, bpy.types.Material]:
    return {
        "orange": make_material("RS_Cart_Painted_Orange", (0.72, 0.18, 0.035, 1), metallic=0.56, roughness=0.30),
        "cream": make_material("RS_Cart_Painted_Cream", (0.92, 0.46, 0.075, 1), metallic=0.50, roughness=0.28),
        "steel": make_material("RS_Cart_Steel", (0.12, 0.17, 0.20, 1), metallic=0.90, roughness=0.23),
        "edge": make_material("RS_Cart_Edge_Steel", (0.28, 0.35, 0.37, 1), metallic=0.76, roughness=0.25),
        "dark": make_material("RS_Cart_Rubber", (0.018, 0.024, 0.028, 1), metallic=0.12, roughness=0.56),
        "glass": make_material("RS_Cart_Visor", (0.018, 0.105, 0.14, 1), metallic=0.28, roughness=0.10),
        "cyan": make_material("RS_Cart_Resonance_Cyan", (0.015, 0.28, 0.34, 1), metallic=0.34, roughness=0.18,
                              emission=(0.02, 0.80, 1.0, 1), emission_strength=4.0),
        "amber": make_material("RS_Cart_Amber_Lamp", (0.85, 0.26, 0.025, 1), metallic=0.28, roughness=0.22,
                               emission=(1.0, 0.25, 0.02, 1), emission_strength=2.8),
        "yellow": make_material("RS_Cart_Safety_Yellow", (0.90, 0.54, 0.04, 1), metallic=0.26, roughness=0.28),
        "clay": make_material("RS_Cart_Clay", (0.55, 0.58, 0.60, 1), metallic=0.12, roughness=0.38),
        "clay_dark": make_material("RS_Cart_Clay_Dark", (0.27, 0.29, 0.30, 1), metallic=0.16, roughness=0.44),
        "ground": make_material("RS_Cart_Preview_Ground", (0.055, 0.070, 0.080, 1), metallic=0.05, roughness=0.82),
        "rail": make_material("RS_Cart_Preview_Rail", (0.11, 0.14, 0.15, 1), metallic=0.82, roughness=0.22),
    }


def apply_bevel(obj, width: float = 0.08, segments: int = 3) -> None:
    if width <= 0:
        return
    bevel = obj.modifiers.new("Edge_softening", "BEVEL")
    bevel.width = width
    bevel.segments = segments
    bevel.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.modifier_apply(modifier=bevel.name)
    except RuntimeError:
        pass
    obj.select_set(False)
    if obj.type == "MESH":
        weighted = obj.modifiers.new("Weighted_normals", "WEIGHTED_NORMAL")
        weighted.keep_sharp = True
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        try:
            bpy.ops.object.modifier_apply(modifier=weighted.name)
        except RuntimeError:
            pass
        obj.select_set(False)


def add_box(name: str, location, dimensions, mat, bevel: float = 0.06, parent=None, rotation=None):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation or (0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (dimensions[0] / 2.0, dimensions[1] / 2.0, dimensions[2] / 2.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    apply_bevel(obj, bevel, 3)
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def add_cylinder(name: str, location, radius: float, depth: float, mat, vertices: int = 24,
                 rotation=None, bevel: float = 0.03, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location,
                                        rotation=rotation or (0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    apply_bevel(obj, bevel, 2)
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def add_uv_sphere(name: str, location, scale, mat, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def add_pipe(name: str, a, b, radius: float, mat, parent=None):
    start, end = Vector(a), Vector(b)
    delta = end - start
    obj = add_cylinder(name, (start + end) * 0.5, radius, delta.length, mat, vertices=18,
                       bevel=radius * 0.25, parent=parent)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized())
    return obj


def add_ring(name: str, location, major_radius: float, minor_radius: float, mat, parent=None, rotation=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major_radius, minor_radius=minor_radius, major_segments=40,
                                     minor_segments=12, location=location, rotation=rotation or (0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def add_profile_extruded(name: str, points_xz, y_center: float, thickness: float, mat,
                         bevel: float = 0.08, parent=None):
    verts = []
    half = thickness / 2.0
    for y in (y_center - half, y_center + half):
        verts.extend((x, y, z) for x, z in points_xz)
    n = len(points_xz)
    faces = []
    faces.append(tuple(range(n - 1, -1, -1)))
    faces.append(tuple(range(n, 2 * n)))
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    apply_bevel(obj, bevel, 3)
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def add_bolt(name: str, location, mat, parent=None, radius: float = 0.065, rotation=None):
    return add_cylinder(name, location, radius, 0.045, mat, vertices=12,
                        rotation=rotation or (math.pi / 2.0, 0.0, 0.0), bevel=0.015, parent=parent)


def add_panel_seam(name: str, location, dimensions, mat, parent=None, rotation=None):
    return add_box(name, location, dimensions, mat, bevel=0.015, parent=parent, rotation=rotation)


def build_cart(mats):
    root = bpy.data.objects.new("RES_MiningTransportCart_V1", None)
    bpy.context.collection.objects.link(root)
    root["asset_id"] = "resonance_mining_transport_cart_v1"
    root["design_status"] = "phase_1_silhouette_review"
    root["scale_reference"] = "vehicle_length_9.6m_width_4.1m_height_5.4m"
    root["gameplay_hooks"] = "cargo_bed, player_push, magnetic_hook, winch, resonance_core"
    root["pivot_policy"] = "root_at_rail_center; bogies and resonance_loop separated for animation"

    # The low, tapered chassis is the visual spine of the cart.
    add_box("Chassis/impact_keel", (0.0, 0.0, 1.45), (8.9, 3.35, 1.00), mats["steel"], 0.20, root)
    add_box("Chassis/painted_sill", (0.0, 0.0, 2.08), (8.2, 3.25, 0.42), mats["orange"], 0.13, root)
    add_box("Chassis/inner_deck", (-0.55, 0.0, 2.36), (6.2, 2.55, 0.30), mats["edge"], 0.06, root)
    for y in (-1.55, 1.55):
        add_box(f"Chassis/side_sill_{y:+.1f}", (0.0, y, 1.95), (8.75, 0.26, 0.78), mats["cream"], 0.07, root)
        add_box(f"Chassis/side_shadow_{y:+.1f}", (0.0, y * 1.02, 1.42), (8.35, 0.20, 0.18), mats["dark"], 0.04, root)
    for x in (-3.78, -2.15, -0.52, 1.10, 2.73, 3.86):
        add_bolt(f"Chassis/deck_bolt_{x:+.2f}", (x, -1.67, 2.20), mats["edge"], root, 0.052)
        add_bolt(f"Chassis/deck_bolt_back_{x:+.2f}", (x, 1.67, 2.20), mats["edge"], root, 0.052)

    # Rear cargo cradle: a curved, open silhouette with layered cheek plates.
    cradle_profile = [(-4.16, 2.18), (-3.92, 3.18), (-3.34, 4.12), (-2.25, 4.56),
                      (-0.70, 4.62), (0.55, 4.25), (1.32, 3.48), (1.46, 2.25)]
    for side in (-1, 1):
        y = side * 1.58
        add_profile_extruded(f"CargoCradle/outer_cheek_{side:+d}", cradle_profile, y, 0.34, mats["orange"], 0.10, root)
        inner_profile = [(x + 0.14, z - 0.15) for x, z in cradle_profile[1:-1]]
        add_profile_extruded(f"CargoCradle/inner_cheek_{side:+d}", inner_profile, side * 1.39, 0.16, mats["cream"], 0.045, root)
        add_pipe(f"CargoCradle/top_guard_{side:+d}", (-3.48, side * 1.77, 3.65), (0.64, side * 1.77, 4.02), 0.11, mats["edge"], root)
        add_pipe(f"CargoCradle/rear_guard_{side:+d}", (-3.98, side * 1.77, 2.60), (-3.50, side * 1.77, 3.88), 0.09, mats["steel"], root)
        for x, z in ((-3.45, 3.16), (-1.95, 4.24), (-0.20, 4.35), (0.76, 3.66)):
            add_bolt(f"CargoCradle/cheek_bolt_{side:+d}_{x:+.2f}", (x, side * 1.79, z), mats["edge"], root, 0.055)
    add_box("CargoCradle/floor", (-1.35, 0.0, 2.70), (4.65, 2.55, 0.28), mats["dark"], 0.07, root)
    add_box("CargoCradle/floor_liner", (-1.18, 0.0, 2.86), (3.95, 2.12, 0.12), mats["steel"], 0.04, root)
    for x in (-3.20, -1.62, -0.04, 1.02):
        add_box(f"CargoCradle/floor_rib_{x:+.2f}", (x, 0.0, 2.96), (0.18, 2.22, 0.16), mats["edge"], 0.025, root)

    # Signature resonance loop and its grounded supports.
    resonance_root = bpy.data.objects.new("ResonanceLoop", None)
    bpy.context.collection.objects.link(resonance_root)
    resonance_root.parent = root
    add_ring("ResonanceLoop/outer_frame", (-0.84, 0.0, 4.78), 1.33, 0.14, mats["steel"], resonance_root, rotation=(0.0, math.pi / 2.0, 0.0))
    add_ring("ResonanceLoop/glow_ring", (-0.84, 0.0, 4.78), 1.07, 0.075, mats["cyan"], resonance_root, rotation=(0.0, math.pi / 2.0, 0.0))
    add_uv_sphere("ResonanceLoop/core", (-0.84, 0.0, 4.78), (0.38, 0.38, 0.38), mats["cyan"], resonance_root)
    for side in (-1, 1):
        add_pipe(f"ResonanceLoop/support_{side:+d}", (-1.72, side * 0.88, 3.40), (-0.84, side * 0.88, 4.60), 0.12, mats["edge"], resonance_root)
        add_pipe(f"ResonanceLoop/support_foot_{side:+d}", (-2.12, side * 1.08, 3.08), (-1.70, side * 0.88, 3.40), 0.15, mats["steel"], resonance_root)
    for angle in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):
        x = -0.84 + 1.08 * math.sin(angle)
        z = 4.78 + 1.08 * math.cos(angle)
        add_box(f"ResonanceLoop/segment_marker_{angle:.2f}", (x, 0.0, z), (0.18, 0.50, 0.12), mats["amber"], 0.025, resonance_root,
                rotation=(0.0, angle, 0.0))

    # Front cabin shell: one continuous wedge gives the cart a designed nose.
    cabin_profile = [(0.72, 2.20), (1.30, 2.12), (2.66, 2.55), (3.72, 3.28),
                     (3.64, 4.05), (2.92, 4.70), (1.80, 4.86), (1.02, 4.35)]
    add_profile_extruded("Cabin/outer_wedge", cabin_profile, 0.0, 3.15, mats["cream"], 0.12, root)
    add_profile_extruded("Cabin/side_shadow_left", [(x, z - 0.12) for x, z in cabin_profile[1:-1]], -1.58, 0.11, mats["orange"], 0.04, root)
    add_profile_extruded("Cabin/side_shadow_right", [(x, z - 0.12) for x, z in cabin_profile[1:-1]], 1.58, 0.11, mats["orange"], 0.04, root)
    add_box("Cabin/front_bumper", (3.82, 0.0, 2.55), (0.30, 3.18, 0.62), mats["steel"], 0.12, root, rotation=(0.0, -0.18, 0.0))
    add_box("Cabin/visor", (3.48, 0.0, 3.72), (0.16, 2.12, 0.78), mats["glass"], 0.08, root, rotation=(0.0, -0.28, 0.0))
    add_box("Cabin/visor_glow", (3.59, 0.0, 3.30), (0.10, 2.30, 0.12), mats["cyan"], 0.025, root, rotation=(0.0, -0.20, 0.0))
    add_box("Cabin/left_cheek", (2.35, -1.61, 3.27), (1.42, 0.18, 0.78), mats["orange"], 0.06, root, rotation=(0.0, -0.22, 0.0))
    add_box("Cabin/right_cheek", (2.35, 1.61, 3.27), (1.42, 0.18, 0.78), mats["orange"], 0.06, root, rotation=(0.0, -0.22, 0.0))
    add_panel_seam("Cabin/service_seam_left", (1.68, -1.67, 3.84), (0.08, 0.035, 0.95), mats["steel"], root, rotation=(0.0, -0.24, 0.0))
    add_panel_seam("Cabin/service_seam_right", (1.68, 1.67, 3.84), (0.08, 0.035, 0.95), mats["steel"], root, rotation=(0.0, -0.24, 0.0))
    for side in (-1, 1):
        add_bolt(f"Cabin/shoulder_bolt_{side:+d}_a", (1.70, side * 1.73, 3.23), mats["edge"], root, 0.065)
        add_bolt(f"Cabin/shoulder_bolt_{side:+d}_b", (2.92, side * 1.70, 3.00), mats["edge"], root, 0.065)

    # Side service modules add functional read at player height.
    for side in (-1, 1):
        y = side * 1.77
        add_box(f"ServicePanel/{side:+d}/housing", (0.72, y, 2.72), (1.20, 0.26, 0.78), mats["steel"], 0.10, root)
        add_box(f"ServicePanel/{side:+d}/panel", (0.72, side * 1.92, 2.74), (0.82, 0.06, 0.42), mats["orange"], 0.045, root)
        add_box(f"ServicePanel/{side:+d}/status", (0.88, side * 1.97, 2.74), (0.08, 0.035, 0.22), mats["cyan"], 0.01, root)
        add_box(f"ServicePanel/{side:+d}/handle", (0.52, side * 1.98, 2.52), (0.38, 0.06, 0.08), mats["yellow"], 0.02, root)
        for x in (0.36, 1.06):
            add_bolt(f"ServicePanel/{side:+d}/bolt_{x:.2f}", (x, side * 1.98, 2.91), mats["edge"], root, 0.042)

    # Bogies, suspension, wheel housings and rail clamps make the cart credible.
    bogie_root = bpy.data.objects.new("BogieSystem", None)
    bpy.context.collection.objects.link(bogie_root)
    bogie_root.parent = root
    for index, x in enumerate((-2.62, 2.34)):
        add_box(f"Bogie/{index}/crossbeam", (x, 0.0, 0.88), (1.72, 3.04, 0.36), mats["steel"], 0.10, bogie_root)
        add_box(f"Bogie/{index}/center_block", (x, 0.0, 1.12), (1.18, 1.48, 0.55), mats["dark"], 0.12, bogie_root)
        for side in (-1, 1):
            y = side * 1.45
            add_cylinder(f"Bogie/{index}/wheel_{side:+d}", (x, y, 0.62), 0.48, 0.34, mats["dark"], 28,
                         rotation=(math.pi / 2.0, 0.0, 0.0), bevel=0.045, parent=bogie_root)
            add_ring(f"Bogie/{index}/wheel_hub_{side:+d}", (x, side * 1.64, 0.62), 0.24, 0.06, mats["yellow"], bogie_root,
                     rotation=(math.pi / 2.0, 0.0, 0.0))
            add_pipe(f"Bogie/{index}/suspension_{side:+d}", (x, side * 1.22, 1.05), (x, side * 1.45, 0.86), 0.12, mats["edge"], bogie_root)
            add_box(f"Bogie/{index}/rail_jaw_{side:+d}", (x, side * 1.93, 0.58), (0.74, 0.25, 0.52), mats["orange"], 0.08, bogie_root)
            add_pipe(f"Bogie/{index}/rail_arm_{side:+d}", (x, side * 1.63, 0.82), (x, side * 1.92, 0.66), 0.08, mats["steel"], bogie_root)
        add_box(f"Bogie/{index}/shock_cap", (x, 0.0, 1.46), (0.52, 1.20, 0.24), mats["amber"], 0.04, bogie_root)

    # Rear counterweight and front marker fins complete the silhouette.
    add_box("RearCounterweight/housing", (-3.95, 0.0, 2.55), (0.56, 2.65, 1.24), mats["steel"], 0.12, root)
    add_box("RearCounterweight/amber_band", (-4.27, 0.0, 2.54), (0.08, 2.70, 0.20), mats["amber"], 0.018, root)
    for side in (-1, 1):
        add_profile_extruded(f"Cabin/fender_fin_{side:+d}", [(2.12, 4.08), (3.02, 4.56), (3.55, 4.40), (2.74, 4.05)], side * 1.76, 0.16,
                             mats["orange"], 0.045, root)

    # Preview-only rails and scale card; stripped before GLB export.
    add_box("PreviewGround", (0.0, 0.0, -0.06), (24.0, 20.0, 0.12), mats["ground"], 0.0)
    for y in (-1.18, 1.18):
        add_box(f"PreviewRail_{y:+.2f}", (0.0, y, 0.05), (18.0, 0.16, 0.22), mats["rail"], 0.035)
        for x in (-7.0, -5.0, -3.0, -1.0, 1.0, 3.0, 5.0, 7.0):
            add_box(f"PreviewSleeper_{y:+.2f}_{x:+.1f}", (x, 0.0, 0.0), (0.22, 3.30, 0.12), mats["rail"], 0.02)
    return root


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_preview():
    bpy.ops.object.camera_add(location=(12.8, 13.5, 9.4))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    camera.data.lens = 58
    look_at(camera, (0.0, 0.0, 2.65))
    bpy.context.scene.camera = camera

    lights = [
        ("Key", (7.5, -9.0, 12.0), 1250.0, 5.5, (1.0, 0.69, 0.48)),
        ("Fill", (-8.0, -3.0, 7.5), 1050.0, 6.0, (0.40, 0.70, 1.0)),
        ("Rim", (-1.0, 9.0, 11.0), 1600.0, 4.0, (1.0, 0.34, 0.12)),
        ("TopSoft", (0.0, 0.0, 16.0), 750.0, 7.0, (0.62, 0.76, 1.0)),
    ]
    for name, loc, energy, size, color in lights:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color
        look_at(light, (0.0, 0.0, 2.4))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.018, 0.026, 0.040)
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.filepath = str(ITER_DIR / "grey_45.png")
    scene.render.image_settings.color_mode = "RGBA"
    return camera


def all_model_objects():
    excluded = {"PreviewCamera", "Key", "Fill", "Rim", "TopSoft", "PreviewGround"}
    return [obj for obj in bpy.data.objects if obj.type == "MESH" and obj.name not in excluded and not obj.name.startswith("PreviewRail") and not obj.name.startswith("PreviewSleeper")]


def render_view(camera, label: str, location, target, clay: bool = True):
    camera.location = location
    look_at(camera, target)
    scene = bpy.context.scene
    scene.camera = camera
    originals = []
    if clay:
        for obj in all_model_objects():
            originals.append((obj, list(obj.data.materials)))
            obj.data.materials.clear()
            obj.data.materials.append(bpy.data.materials["RS_Cart_Clay_Dark"] if "Bogie" in obj.name or "dark" in obj.name.lower() else bpy.data.materials["RS_Cart_Clay"])
    scene.render.filepath = str(ITER_DIR / f"{label}.png")
    bpy.ops.render.render(write_still=True)
    if clay:
        for obj, mats in originals:
            obj.data.materials.clear()
            for mat in mats:
                obj.data.materials.append(mat)


def render_all_views(camera):
    render_view(camera, "grey_45", (12.8, 13.5, 9.4), (0.0, 0.0, 2.65), True)
    render_view(camera, "grey_front", (14.8, 0.0, 4.9), (0.0, 0.0, 2.8), True)
    render_view(camera, "grey_side", (0.0, 15.6, 5.5), (0.0, 0.0, 2.8), True)
    render_view(camera, "grey_top", (0.5, 0.8, 21.5), (0.0, 0.0, 2.0), True)
    render_view(camera, "grey_close", (7.2, 7.2, 5.1), (1.2, 0.0, 3.2), True)
    render_view(camera, "color_45", (12.8, 13.5, 9.4), (0.0, 0.0, 2.65), False)


def strip_preview_only_objects():
    prefixes = ("PreviewRail", "PreviewSleeper")
    exact = {"PreviewCamera", "Key", "Fill", "Rim", "TopSoft", "PreviewGround"}
    for obj in list(bpy.data.objects):
        if obj.name in exact or obj.name.startswith(prefixes):
            bpy.data.objects.remove(obj, do_unlink=True)


def export_runtime():
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    strip_preview_only_objects()
    bpy.ops.export_scene.gltf(filepath=str(GLB_PATH), export_format="GLB", use_selection=False,
                              export_apply=True, export_texcoords=True, export_normals=True,
                              export_materials="EXPORT", export_cameras=False, export_lights=False)


def main():
    ensure_dirs()
    clear_scene()
    mats = make_materials()
    build_cart(mats)
    camera = setup_preview()
    render_all_views(camera)
    export_runtime()
    print(f"RES_CART_BLEND={BLEND_PATH}")
    print(f"RES_CART_GLB={GLB_PATH}")
    print(f"RES_CART_ITER_DIR={ITER_DIR}")


if __name__ == "__main__":
    main()
