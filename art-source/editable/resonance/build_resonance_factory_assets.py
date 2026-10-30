"""Generate the Resonance Star industrial factory asset set.

The script is deliberately repeatable and keeps gameplay concerns out of the
Blender files.  Every asset is exported as a separate GLB with named parts,
materials, and a preview render.  Godot owns colliders, interaction anchors,
animation state, and multiplayer state.

Run with Blender 5.2.2 from the repository root:
    tools/blender-5.2.2-windows-x64/blender.exe -b --python \
        art-source/editable/resonance/build_resonance_factory_assets.py
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / "art-source" / "editable" / "resonance"
MODEL_DIR = ROOT / "game" / "assets" / "resonance" / "models"
TEXTURE_DIR = ROOT / "game" / "assets" / "resonance" / "textures"
PANEL_TEXTURE = TEXTURE_DIR / "industrial_panel.png"
GROUND_TEXTURE = TEXTURE_DIR / "alien_rock_ground.png"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0 and datablock.name not in {"Render Result"}:
                datablocks.remove(datablock)


def set_input(node, name: str, value) -> None:
    socket = node.inputs.get(name)
    if socket is not None:
        socket.default_value = value


def mat(name: str, color: tuple[float, float, float, float], metallic: float = 0.0,
        roughness: float = 0.42, emission: tuple[float, float, float, float] | None = None,
        strength: float = 0.0, texture: Path | None = None) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    set_input(bsdf, "Base Color", color)
    set_input(bsdf, "Metallic", metallic)
    set_input(bsdf, "Roughness", roughness)
    if emission is not None:
        set_input(bsdf, "Emission Color", emission)
        set_input(bsdf, "Emission Strength", strength)
    if texture is not None and texture.exists():
        image = bpy.data.images.load(str(texture), check_existing=True)
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.projection = "BOX"
        tex.projection_blend = 0.18
        texcoord = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        set_input(mapping, "Scale", (1.8, 1.8, 1.8))
        links.new(texcoord.outputs["Generated"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs[0], out.inputs[0])
    return material


def materials() -> dict[str, bpy.types.Material]:
    return {
        "steel": mat("RS_Steel_Scuffed", (0.16, 0.19, 0.22, 1), 0.92, 0.27, texture=PANEL_TEXTURE),
        "steel_light": mat("RS_Steel_Edges", (0.32, 0.38, 0.42, 1), 0.84, 0.23),
        "steel_dark": mat("RS_Steel_Shadow", (0.035, 0.045, 0.055, 1), 0.70, 0.34),
        "rubber": mat("RS_Rubber_Hose", (0.018, 0.023, 0.026, 1), 0.18, 0.62),
        "warning": mat("RS_Warning_Amber", (0.70, 0.19, 0.025, 1), 0.45, 0.28, (1.0, 0.09, 0.01, 1), 2.5),
        "cyan": mat("RS_Energy_Cyan", (0.015, 0.20, 0.28, 1), 0.38, 0.18, (0.01, 0.78, 1.0, 1), 4.0),
        "blue": mat("RS_Track_Blue", (0.015, 0.12, 0.34, 1), 0.46, 0.22, (0.02, 0.32, 1.0, 1), 2.8),
        "blue_dim": mat("RS_Track_Blue_Dim", (0.015, 0.10, 0.26, 1), 0.46, 0.30, (0.02, 0.28, 0.86, 1), 1.1),
        "violet": mat("RS_Lift_Violet", (0.18, 0.07, 0.32, 1), 0.36, 0.22, (0.62, 0.14, 1.0, 1), 3.0),
        "green": mat("RS_Extraction_Green", (0.02, 0.36, 0.22, 1), 0.34, 0.22, (0.02, 1.0, 0.40, 1), 3.5),
        "glass": mat("RS_Optical_Glass", (0.015, 0.08, 0.12, 1), 0.20, 0.09),
        "ground": mat("RS_Red_Rock", (0.23, 0.07, 0.035, 1), 0.08, 0.86, texture=GROUND_TEXTURE),
        "rock": mat("RS_Basalt", (0.08, 0.045, 0.045, 1), 0.05, 0.93),
        "concrete": mat("RS_Foundation_Concrete", (0.09, 0.11, 0.13, 1), 0.42, 0.55),
    }


def bevel(obj: bpy.types.Object, width: float = 0.06, segments: int = 3) -> None:
    mod = obj.modifiers.new("Manufactured_edge_bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.modifier_apply(modifier=mod.name)
    except RuntimeError:
        pass
    obj.select_set(False)


def box(name: str, loc, size, material, parent=None, bevel_width: float = 0.05, rot=None):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot or (0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0] / 2.0, size[1] / 2.0, size[2] / 2.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel_width:
        bevel(obj, bevel_width, 3)
    obj.data.materials.append(material)
    if parent:
        obj.parent = parent
    return obj


def cyl(name: str, loc, radius: float, depth: float, material, parent=None, vertices: int = 24,
        rot=None, bevel_width: float = 0.025):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc,
                                        rotation=rot or (0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    if bevel_width:
        bevel(obj, bevel_width, 2)
    obj.data.materials.append(material)
    if parent:
        obj.parent = parent
    return obj


def torus(name: str, loc, major: float, minor: float, material, parent=None, rot=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=36,
                                     minor_segments=10, location=loc, rotation=rot or (0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    if parent:
        obj.parent = parent
    return obj


def sphere(name: str, loc, scale, material, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=28, ring_count=16, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if parent:
        obj.parent = parent
    return obj


def pipe(name: str, a, b, radius: float, material, parent=None):
    start, end = Vector(a), Vector(b)
    delta = end - start
    obj = cyl(name, (start + end) * 0.5, radius, delta.length, material, parent, 18, None, radius * 0.25)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    return obj


def bolt(name: str, loc, material, parent=None, radius: float = 0.065):
    return cyl(name, loc, radius, 0.045, material, parent, 12, (math.pi / 2, 0, 0), 0.012)


def panel(parent, loc, size, materials_map, accent="steel_light", label="Panel"):
    p = box(f"{label}/plate", loc, size, materials_map["steel"], parent, 0.045)
    for i, (sx, sz) in enumerate(((-0.42, -0.38), (0.42, -0.38), (-0.42, 0.38), (0.42, 0.38))):
        bolt(f"{label}/bolt_{i}", (loc[0] + size[0] * sx, loc[1] + size[1] * 0.56, loc[2] + size[2] * sz), materials_map[accent], parent, 0.045)
    return p


def asset_root(name: str, asset_id: str):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    root["asset_id"] = asset_id
    root["design_source"] = "art-source/generated/resonance/resonance-grounded-factory-concept.png"
    root["collision_policy"] = "Godot gameplay collision stays separate"
    return root


def build_hero(m):
    # A richer, lower silhouette module that preserves the existing 10 x 6 m footprint.
    root = asset_root("RES_Module_Hero", "resonance_module_hero")
    root["gameplay_footprint_m"] = "10 x 6"
    box("Chassis/lower", (0, 0.38, 0), (10.25, 0.72, 5.72), m["steel_dark"], root, 0.18)
    box("Chassis/deck", (0, 0.88, 0), (9.72, 0.18, 5.25), m["steel_light"], root, 0.04)
    for x in (-4.72, 4.72):
        box(f"Chassis/side_beam_{x}", (x, 0.76, 0), (0.36, 0.96, 5.34), m["steel"], root, 0.05)
    for z in (-2.36, 2.36):
        box(f"Chassis/end_beam_{z}", (0, 0.78, z), (9.64, 0.96, 0.36), m["steel"], root, 0.05)
    for x in (-4.2, -2.8, -1.4, 0, 1.4, 2.8, 4.2):
        bolt(f"Chassis/deck_bolt_front_{x}", (x, 1.02, -2.30), m["steel_light"], root)
        bolt(f"Chassis/deck_bolt_back_{x}", (x, 1.02, 2.30), m["steel_light"], root)
    # Raised operator cockpit and side service spine.
    box("ControlCabin/lower", (-2.85, 1.45, 0.15), (3.25, 0.72, 2.84), m["steel"], root, 0.12)
    box("ControlCabin/upper", (-2.85, 2.23, 0.15), (2.72, 0.72, 2.34), m["steel_light"], root, 0.12)
    box("ControlCabin/visor", (-2.85, 2.45, -1.04), (2.10, 0.18, 0.18), m["glass"], root, 0.03)
    box("ControlCabin/status_strip", (-2.85, 2.45, 1.28), (1.88, 0.07, 0.18), m["cyan"], root, 0.02)
    for x in (-3.73, -2.85, -1.97):
        bolt(f"ControlCabin/face_bolt_{x}", (x, 2.06, -1.10), m["steel_light"], root, 0.055)
    # Main resonance spine with collars and a return line.
    pipe("Conduit/main", (-0.5, 1.38, -1.88), (3.95, 1.38, -1.88), 0.13, m["cyan"], root)
    pipe("Conduit/return", (-0.5, 1.15, -1.58), (3.95, 1.15, -1.58), 0.075, m["steel_light"], root)
    for i, x in enumerate((0.1, 1.0, 1.9, 2.8, 3.7)):
        torus(f"Conduit/collar_{i}", (x, 1.38, -1.88), 0.22, 0.035, m["warning"], root, (math.pi / 2, 0, 0))
        box(f"Conduit/service_node_{i}", (x, 1.02, -1.88), (0.26, 0.22, 0.34), m["steel_light"], root, 0.025)
    # Full maintenance face, plus inset vents and a repeated fastener language.
    for row, y in enumerate((0.62, 0.96, 1.30, 1.64)):
        for col, x in enumerate((-3.45, -2.30, -1.15, 0, 1.15, 2.30, 3.45)):
            panel(root, (x, y, -2.60), (0.98, 0.055, 1.05), m, "steel_light", f"FrontFace/{row}_{col}")
            box(f"FrontFace/stripe_{row}_{col}", (x, y + 0.04, -2.65), (0.23, 0.018, 0.05), m["warning"], root, 0.01, (0, 0.0, math.radians(-24 if (row + col) % 2 else 24)))
    # Four articulated locking assemblies.
    for side in (-1, 1):
        for z in (-1.70, 1.70):
            x = side * 4.42
            box(f"RailClamp/{side}_{z}/mount", (x, 0.56, z), (0.60, 0.82, 0.92), m["steel"], root, 0.06)
            box(f"RailClamp/{side}_{z}/jaw", (side * 4.93, 0.78, z), (0.44, 0.46, 1.28), m["steel_light"], root, 0.06)
            pipe(f"RailClamp/{side}_{z}/hydraulic_body", (side * 4.45, 0.68, z), (side * 5.22, 0.68, z), 0.11, m["rubber"], root)
            pipe(f"RailClamp/{side}_{z}/piston_rod", (side * 4.98, 0.68, z), (side * 5.39, 0.68, z), 0.055, m["warning"], root)
            torus(f"RailClamp/{side}_{z}/lock_light", (side * 5.30, 0.68, z), 0.15, 0.032, m["warning"], root, (math.pi / 2, 0, 0))
            bolt(f"RailClamp/{side}_{z}/bolt_a", (side * 5.12, 1.00, z - 0.30), m["steel_light"], root, 0.045)
            bolt(f"RailClamp/{side}_{z}/bolt_b", (side * 5.12, 1.00, z + 0.30), m["steel_light"], root, 0.045)
    # Rear battery stack with six fins and cable bundles.
    box("RearBattery/housing", (3.12, 1.52, 1.12), (2.40, 1.18, 1.48), m["steel"], root, 0.12)
    for i, z in enumerate((0.55, 0.82, 1.09, 1.36, 1.63, 1.90)):
        box(f"RearBattery/fin_{i}", (3.12, 1.62, z), (2.04, 0.08, 0.12), m["steel_light"], root, 0.02)
    box("RearBattery/status", (2.40, 1.52, 1.12), (0.08, 0.36, 0.74), m["cyan"], root, 0.02)
    pipe("RearBattery/cable_a", (2.1, 1.0, 0.55), (3.95, 1.0, 0.55), 0.05, m["blue"], root)
    pipe("RearBattery/cable_b", (2.1, 1.12, 0.75), (3.95, 1.12, 0.75), 0.04, m["warning"], root)
    for x in (2.3, 3.12, 3.94):
        bolt(f"RearBattery/bolt_{x}", (x, 2.20, 1.14), m["steel_light"], root)
    for x, z in ((-4.05, 1.55), (-3.40, 1.55), (4.04, -1.40), (3.42, -1.40)):
        cyl(f"ServiceProp/canister_{x}_{z}", (x, 1.40, z), 0.17, 0.62, m["warning"], root, 16)
        torus(f"ServiceProp/collar_{x}_{z}", (x, 1.72, z), 0.17, 0.025, m["steel_light"], root)
    return root


def build_rail_system(m):
    root = asset_root("RES_Rail_System", "resonance_rail_system")
    root["gameplay_footprint_m"] = "24 x 8"
    box("Foundation/plate", (0, -0.03, 0), (24.0, 0.34, 8.2), m["concrete"], root, 0.12)
    for z in (-1.7, 1.7):
        box(f"Rail/rail_{z}", (0, 0.24, z), (24.0, 0.25, 0.34), m["steel_light"], root, 0.04)
        box(f"Rail/glow_{z}", (0, 0.40, z), (23.6, 0.045, 0.07), m["blue_dim"], root, 0.02)
    for i, x in enumerate(range(-10, 11, 4)):
        box(f"Rail/Sleeper/{i}", (x, 0.08, 0), (0.55, 0.24, 7.3), m["steel_dark"], root, 0.03)
        if i % 3 == 0:
            for z in (-1.7, 1.7):
                box(f"Rail/Clamp/{i}_{z}", (x, 0.39, z), (0.75, 0.18, 0.60), m["warning"], root, 0.03)
    # Overhead inspection gantry and vertical depth cue.
    for x in (-8.8, 8.8):
        box(f"Gantry/column_{x}", (x, 3.2, 0), (0.60, 6.4, 0.60), m["steel"], root, 0.06)
        for y in (1.2, 4.4):
            box(f"Gantry/brace_{x}_{y}", (x, y, 0), (0.82, 0.10, 5.4), m["steel_light"], root, 0.02)
    box("Gantry/header", (0, 6.15, 0), (18.4, 0.52, 0.78), m["steel"], root, 0.08)
    for x in range(-8, 9, 4):
        box(f"Gantry/header_light_{x}", (x, 6.15, -0.43), (0.20, 0.20, 0.08), m["warning"], root, 0.01)
    box("Maintenance/catwalk", (0, 3.0, 3.1), (16.0, 0.20, 1.3), m["steel_light"], root, 0.04)
    for side in (-1, 1):
        for x in (-9, 0, 9):
            cyl(f"Signal/{side}_{x}", (x, 0.95, side * 3.0), 0.16, 0.65, m["warning"], root)
            torus(f"Signal/ring_{side}_{x}", (x, 1.30, side * 3.0), 0.19, 0.035, m["warning"], root)
    return root


def build_reactor_tower(m):
    root = asset_root("RES_Reactor_Tower", "resonance_reactor_tower")
    root["gameplay_footprint_m"] = "18 x 34 x 18"
    cyl("Foundation/base", (0, 0.65, 0), 8.1, 1.3, m["concrete"], root, 12, None, 0.10)
    torus("Foundation/rim", (0, 1.35, 0), 7.25, 0.18, m["warning"], root)
    for corner in ((-4.9, -4.9), (-4.9, 4.9), (4.9, -4.9), (4.9, 4.9)):
        x, z = corner
        box(f"Tower/support_{x}_{z}", (x, 15.0, z), (1.05, 27.0, 1.05), m["steel"], root, 0.08)
        for y in (4.0, 9.0, 14.0, 19.0, 24.0, 28.0):
            box(f"Tower/brace_{x}_{z}_{y}", (x, y, z), (1.30, 0.18, 0.18), m["steel_light"], root, 0.02)
    for tier, y in enumerate((4.0, 9.5, 15.0, 20.5, 26.0)):
        torus(f"EnergyRing/{tier}", (0, y, 0), 6.2 - tier * 0.35, 0.20, m["green"], root)
        torus(f"EnergyRing/inner_{tier}", (0, y, 0), 5.2 - tier * 0.28, 0.08, m["cyan"], root)
        for angle in (0, math.pi / 2, math.pi, math.pi * 1.5):
            pipe(f"EnergyRing/pipe_{tier}_{angle}", (math.cos(angle) * 4.6, y, math.sin(angle) * 4.6), (math.cos(angle) * 6.2, y, math.sin(angle) * 6.2), 0.09, m["green"], root)
    cyl("Reactor/inner_vessel", (0, 15.5, 0), 4.5, 27.0, m["glass"], root, 32, None, 0.06)
    cyl("Reactor/energy_core", (0, 15.5, 0), 3.55, 23.0, m["green"], root, 32, None, 0.10)
    for angle in range(0, 360, 30):
        rad = math.radians(angle)
        box(f"Reactor/vertical_fin_{angle}", (math.cos(rad) * 4.1, 15.5, math.sin(rad) * 4.1), (0.18, 24.0, 0.60), m["steel_light"], root, 0.03, (0, -rad, 0))
    box("Service/platform", (0, 5.25, 6.8), (13.4, 0.24, 1.6), m["steel_light"], root, 0.04)
    for x in (-5.6, 5.6):
        box(f"Service/ladder_{x}", (x, 2.4, 6.8), (0.32, 4.7, 0.32), m["steel"], root, 0.03)
    box("Service/maintenance_hatch", (0, 24.0, -4.6), (2.8, 2.0, 0.28), m["steel"], root, 0.06)
    for x in (-0.9, 0.9):
        bolt(f"Service/hatch_bolt_{x}", (x, 24.8, -4.83), m["warning"], root, 0.055)
    return root


def build_core(m):
    root = asset_root("RES_Energy_Core", "resonance_energy_core")
    root["interaction_anchor"] = "double_handle_left_right"
    box("Cage/base", (0, 0.22, 0), (5.8, 0.45, 5.8), m["steel_dark"], root, 0.16)
    for side in (-1, 1):
        box(f"Cage/rail_x_{side}", (side * 2.4, 1.6, 0), (0.24, 3.2, 5.0), m["steel_light"], root, 0.04)
        box(f"Cage/rail_z_{side}", (0, 1.6, side * 2.4), (5.0, 3.2, 0.24), m["steel_light"], root, 0.04)
    for x in (-2.45, 2.45):
        for z in (-2.45, 2.45):
            bolt(f"Cage/bolt_{x}_{z}", (x, 3.25, z), m["warning"], root)
    # Layered container instead of a single glowing sphere.
    cyl("Container/housing", (0, 1.55, 0), 1.42, 2.55, m["steel"], root, 24, None, 0.08)
    cyl("Container/glass", (0, 1.55, 0), 1.10, 2.20, m["cyan"], root, 32, None, 0.05)
    sphere("Container/resonance_field", (0, 1.55, 0), (0.80, 1.05, 0.80), m["cyan"], root)
    for y in (0.62, 1.55, 2.48):
        torus(f"Coil/ring_{y}", (0, y, 0), 1.55, 0.09, m["warning"], root)
        torus(f"Coil/inner_{y}", (0, y, 0), 1.78, 0.055, m["cyan"], root)
    # Real two-person handles.
    for side in (-1, 1):
        pipe(f"Handle/{side}/mount", (side * 1.55, 1.35, 0), (side * 2.05, 1.35, 0), 0.14, m["steel_light"], root)
        pipe(f"Handle/{side}/grip", (side * 2.05, 1.35, -0.72), (side * 2.05, 1.35, 0.72), 0.16, m["rubber"], root)
        bolt(f"Handle/{side}/bolt", (side * 1.55, 1.35, 0), m["warning"], root, 0.06)
    box("Service/console", (0, 3.15, -2.0), (1.8, 0.34, 0.62), m["steel"], root, 0.05)
    for x in (-0.54, 0, 0.54):
        box(f"Service/console_light_{x}", (x, 3.34, -2.32), (0.22, 0.04, 0.08), m["cyan"], root, 0.01)
    return root


def build_drone_dock(m):
    root = asset_root("RES_Drone_Dock", "resonance_drone_dock")
    root["gameplay_footprint_m"] = "12 x 12"
    cyl("Pad/base", (0, 0.34, 0), 5.8, 0.68, m["concrete"], root, 32, None, 0.10)
    torus("Pad/outer_rim", (0, 0.72, 0), 5.2, 0.16, m["steel_light"], root)
    for radius, material, minor in ((4.2, m["blue"], 0.12), (2.8, m["cyan"], 0.11), (1.4, m["warning"], 0.09)):
        torus(f"ChargeRing/{radius}", (0, 0.78, 0), radius, minor, material, root)
    for angle in range(0, 360, 45):
        rad = math.radians(angle)
        x, z = math.cos(rad) * 4.7, math.sin(rad) * 4.7
        box(f"Pad/marker_{angle}", (x, 0.86, z), (0.24, 0.10, 0.70), m["warning"], root, 0.02, (0, -rad, 0))
    for angle in (45, 135, 225, 315):
        rad = math.radians(angle)
        x, z = math.cos(rad) * 3.7, math.sin(rad) * 3.7
        box(f"Arm/{angle}/base", (x, 1.0, z), (0.50, 0.55, 0.50), m["steel"], root, 0.06)
        pipe(f"Arm/{angle}/folded", (x, 1.24, z), (math.cos(rad) * 2.2, 1.42, math.sin(rad) * 2.2), 0.10, m["steel_light"], root)
        torus(f"Arm/{angle}/joint", (x, 1.24, z), 0.18, 0.045, m["warning"], root, (math.pi / 2, 0, 0))
    box("Terminal/housing", (0, 1.45, -4.3), (2.3, 2.2, 0.55), m["steel"], root, 0.10)
    box("Terminal/screen", (0, 1.68, -4.60), (1.2, 0.40, 0.06), m["glass"], root, 0.02)
    for x in (-0.72, 0.72):
        bolt(f"Terminal/bolt_{x}", (x, 2.15, -4.62), m["steel_light"], root)
    return root


def build_extraction(m):
    root = asset_root("RES_Extraction_Platform", "resonance_extraction_platform")
    root["interaction_anchor"] = "green_docking_center"
    cyl("Platform/base", (0, 0.50, 0), 7.8, 1.0, m["concrete"], root, 32, None, 0.12)
    cyl("Platform/deck", (0, 1.05, 0), 6.8, 0.22, m["steel_light"], root, 32, None, 0.04)
    torus("Platform/green_rim", (0, 1.20, 0), 6.0, 0.20, m["green"], root)
    torus("Platform/center_ring", (0, 1.23, 0), 2.8, 0.14, m["green"], root)
    for angle in range(0, 360, 45):
        rad = math.radians(angle)
        x, z = math.cos(rad) * 6.5, math.sin(rad) * 6.5
        box(f"Guard/{angle}/post", (x, 1.8, z), (0.24, 1.6, 0.24), m["steel"], root, 0.03)
        if angle % 90 == 0:
            torus(f"Guard/{angle}/beacon", (x, 2.65, z), 0.20, 0.05, m["green"], root, (math.pi / 2, 0, 0))
    for angle in (0, 90, 180, 270):
        rad = math.radians(angle)
        x, z = math.cos(rad) * 4.9, math.sin(rad) * 4.9
        box(f"Interface/{angle}", (x, 1.55, z), (0.55, 1.0, 0.80), m["steel"], root, 0.06)
        box(f"Interface/{angle}/lamp", (x, 1.85, z - 0.44 * math.sin(rad)), (0.18, 0.18, 0.05), m["green"], root, 0.01, (0, -rad, 0))
    box("Beacon/tower", (0, 3.0, 0), (0.34, 3.6, 0.34), m["steel"], root, 0.04)
    torus("Beacon/halo", (0, 4.55, 0), 0.58, 0.08, m["green"], root)
    return root


def build_helper_drone(m):
    """Small authored helper drone used by the single-player relay mode."""
    root = asset_root("RES_Helper_Drone", "resonance_helper_drone")
    root["asset_role"] = "single-player support drone"
    sphere("Drone/central_housing", (0, 0, 0), (0.58, 0.34, 0.58), m["steel"], root)
    sphere("Drone/energy_core", (0, -0.02, 0), (0.28, 0.16, 0.28), m["cyan"], root)
    torus("Drone/charging_ring", (0, -0.18, 0), 0.68, 0.075, m["cyan"], root)
    for index, angle in enumerate((0.0, math.pi * 0.5, math.pi, math.pi * 1.5)):
        x, z = math.cos(angle) * 0.62, math.sin(angle) * 0.62
        pipe(f"Drone/arm_{index}/strut", (x * 0.55, 0, z * 0.55), (x, 0, z), 0.11, m["steel_light"], root)
        cyl(f"Drone/arm_{index}/rotor", (x, 0, z), 0.22, 0.14, m["blue"], root, 18)
        bolt(f"Drone/arm_{index}/bolt", (x, 0.10, z), m["warning"], root, 0.05)
    for y in (-0.26, 0.26):
        torus(f"Drone/brace_ring_{y}", (0, y, 0), 0.45, 0.04, m["steel_light"], root)
    return root


def build_processing_zone(m):
    root = asset_root("RES_Processing_Zone", "resonance_processing_zone")
    root["gameplay_footprint_m"] = "28 x 20 x 10"
    box("Foundation/plate", (0, 0.2, 0), (28.0, 0.4, 20.0), m["concrete"], root, 0.12)
    # Lower and upper walkable decks establish vertical traversal.
    for y, z, width, depth in ((1.2, -4.0, 23.0, 3.0), (4.5, 3.0, 18.0, 2.6)):
        box(f"Deck/{y}", (0, y, z), (width, 0.22, depth), m["steel_light"], root, 0.04)
        for x in range(-int(width / 2) + 2, int(width / 2), 6):
            bolt(f"Deck/{y}/bolt_{x}", (x, y + 0.16, z + depth * 0.42), m["warning"], root, 0.045)
    for x in (-10.8, 10.8):
        box(f"Gantry/column_{x}", (x, 4.6, 0), (0.75, 9.2, 0.75), m["steel"], root, 0.07)
        box(f"Gantry/column_light_{x}", (x, 4.6, -0.43), (0.14, 7.4, 0.06), m["warning"], root, 0.01)
    box("Gantry/header", (0, 9.0, 0), (22.0, 0.65, 0.90), m["steel"], root, 0.09)
    box("Lift/shaft", (0, 2.8, 0), (4.2, 5.2, 3.8), m["steel_dark"], root, 0.10)
    for side in (-1, 1):
        pipe(f"Lift/hydraulic_{side}", (side * 1.4, 0.8, 0), (side * 1.4, 5.8, 0), 0.16, m["violet"], root)
    for x in (0,):
        box(f"CargoRack/{x}/upright", (x, 3.0, 7.0), (0.38, 5.6, 0.38), m["steel"], root, 0.04)
        for y in (1.2, 3.0, 4.8):
            box(f"CargoRack/{x}/shelf_{y}", (x, y, 7.0), (2.6, 0.18, 1.8), m["steel_light"], root, 0.03)
            box(f"CargoRack/{x}/crate_{y}", (x, y + 0.52, 7.0), (1.5, 0.8, 1.15), m["warning"], root, 0.08)
    for x in (0,):
        pipe(f"Pipe/{x}", (x, 6.7, -7), (x, 2.0, 7), 0.16, m["blue"], root)
        torus(f"Pipe/joint_{x}", (x, 6.7, -7), 0.23, 0.06, m["blue"], root, (math.pi / 2, 0, 0))
    return root


def build_surface_set(m):
    root = asset_root("RES_Surface_Set", "resonance_surface_set")
    root["gameplay_footprint_m"] = "32 x 24"
    box("Ground/strata", (0, -0.12, 0), (32.0, 0.24, 24.0), m["ground"], root, 0.04)
    for i, loc in enumerate(((-11, 0.12, -7), (-5, 0.14, 7), (4, 0.10, -8), (11, 0.18, 5), (0, 0.11, 0))):
        box(f"Strata/{i}", loc, (5.5, 0.18, 0.8), m["rock"], root, 0.03, (0, 0, math.radians(-12 + i * 7)))
    for i, loc in enumerate(((-12, 0.45, -8), (-9, 0.25, 6), (7, 0.35, -7), (13, 0.20, 4), (2, 0.28, 9), (-2, 0.34, -3))):
        rock = sphere(f"LooseRock/{i}", loc, (0.55 + (i % 3) * 0.18, 0.34 + (i % 2) * 0.12, 0.42), m["rock"], root)
        rock.rotation_euler = (0.12 * i, 0.35 * i, 0.18 * i)
    for x in (-13, -6, 3, 12):
        box(f"Wear/track_mark_{x}", (x, 0.04, -1.2), (4.0, 0.04, 0.42), m["warning"], root, 0.01, (0, 0, math.radians(3)))
    return root


def build_support_gate(m):
    root = asset_root("RES_Support_Safety_Gate", "resonance_support_safety_gate")
    root["interaction_anchor"] = "support_gate_console"
    box("Foundation/plinth", (0, 0.25, 0), (8.4, 0.5, 3.2), m["concrete"], root, 0.10)
    for x in (-3.4, 3.4):
        box(f"Gate/pillar_{x}", (x, 3.2, 0), (0.85, 6.4, 0.85), m["steel"], root, 0.08)
        box(f"Gate/pillar_light_{x}", (x, 3.2, -0.46), (0.12, 5.4, 0.05), m["warning"], root, 0.01)
        for y in (1.1, 2.6, 4.1, 5.6):
            bolt(f"Gate/pillar_bolt_{x}_{y}", (x + 0.38, y, -0.48), m["steel_light"], root, 0.045)
    box("Gate/header", (0, 6.2, 0), (7.6, 0.78, 0.90), m["steel"], root, 0.10)
    box("Gate/header_warning", (0, 6.2, -0.48), (5.9, 0.16, 0.08), m["warning"], root, 0.02)
    for x in (-2.1, -0.7, 0.7, 2.1):
        box(f"Gate/door_{x}", (x, 2.6, 0), (1.05, 4.8, 0.18), m["steel_dark"], root, 0.04)
        box(f"Gate/door_light_{x}", (x, 2.6, -0.14), (0.10, 3.9, 0.04), m["violet"], root, 0.01)
    box("Console/housing", (5.0, 1.35, -1.0), (1.2, 2.2, 0.8), m["steel"], root, 0.07)
    box("Console/screen", (5.0, 1.72, -1.45), (0.65, 0.42, 0.05), m["glass"], root, 0.01)
    for x in (4.72, 5.28):
        bolt(f"Console/bolt_{x}", (x, 2.12, -1.46), m["warning"], root, 0.045)
    torus("Gate/lock_ring", (0, 1.15, -0.55), 0.75, 0.09, m["violet"], root)
    return root


def build_maintenance_facility(m):
    root = asset_root("RES_Maintenance_Facility", "resonance_maintenance_facility")
    root["gameplay_footprint_m"] = "16 x 12"
    box("Foundation/rock_cut", (0, 0.2, 0), (16.0, 0.4, 12.0), m["rock"], root, 0.12)
    box("Vault/body", (0, 2.4, 3.6), (11.0, 4.8, 5.0), m["steel_dark"], root, 0.22)
    box("Vault/door", (0, 2.2, 0.95), (4.4, 4.0, 0.26), m["steel"], root, 0.10)
    for x in (-1.6, 0, 1.6):
        box(f"Vault/door_seam_{x}", (x, 2.2, 0.78), (0.08, 3.2, 0.05), m["warning"], root, 0.01)
    for y in (1.0, 2.8, 4.6):
        box(f"Vault/vent_{y}", (-4.7, y, 1.0), (1.4, 0.08, 0.10), m["cyan"], root, 0.01)
    box("Observation/platform", (0, 5.4, -1.7), (13.0, 0.22, 2.2), m["steel_light"], root, 0.04)
    for x in (-5.7, -2.8, 0, 2.8, 5.7):
        bolt(f"Observation/bolt_{x}", (x, 5.58, -2.45), m["steel_light"], root)
    for x in (-5.5, 5.5):
        box(f"Observation/post_{x}", (x, 2.8, -1.7), (0.28, 5.6, 0.28), m["steel"], root, 0.03)
        pipe(f"Observation/brace_{x}", (x, 0.9, -1.7), (x * 0.78, 5.2, -1.7), 0.08, m["warning"], root)
    for x in (-6.2, 6.2):
        sphere(f"RockEdge/{x}", (x, 0.8, 3.8), (1.1, 0.7, 1.3), m["rock"], root)
    return root


def build_cavern_shell(m):
    """A dark, red-brown cavern shell with vertical routes around the factory."""
    root = asset_root("RES_Cavern_Shell", "resonance_cavern_shell")
    root["gameplay_footprint_m"] = "156 x 96 x 34"
    root["collision_policy"] = "Visual cave shell only; player collision remains in Godot"
    # Layered cave walls follow the existing 156 x 96 gameplay envelope.
    for side in (-1, 1):
        z = side * 46.0
        for i, x in enumerate(range(-70, 71, 14)):
            h = 8.0 + float((i * 5) % 5)
            rock = sphere(f"CavernWall/{side}/{i}", (x, h * 0.5, z), (7.0, h * 0.55, 2.8 + (i % 3)), m["rock"], root)
            rock.rotation_euler = (0.06 * (i % 2), 0.12 * i, 0.04 * side)
            box(f"CavernStrata/{side}/{i}", (x, 2.2 + (i % 3) * 0.4, side * 44.3), (10.0, 0.20, 0.22), m["warning"], root, 0.02, (0, 0, math.radians(side * (8 + i % 4))))
    # Roof ribs and stalactites create a readable overhead boundary.
    for i, x in enumerate(range(-70, 71, 14)):
        box(f"CavernRoof/Rib_{i}", (x, 28.0 + (i % 3) * 1.2, 0), (2.2, 1.2, 88.0), m["rock"], root, 0.18, (0.03 * (i % 2), 0.0, 0.0))
        for side in (-1, 1):
            tip = Vector((x + (i % 2) * 2.0, 22.0 - (i % 3) * 1.3, side * (9.0 + (i % 4) * 2.5)))
            stalactite = sphere(f"Stalactite/{i}/{side}", tip, (1.1 + (i % 3) * 0.4, 4.2 + (i % 2) * 1.4, 1.1 + (i % 4) * 0.3), m["rock"], root)
            stalactite.rotation_euler = (0.15 * side, 0.08 * i, 0.08 * side)
    # A central vertical shaft with suspended bridge collars.
    for y in (7.0, 13.0, 19.0, 25.0):
        torus(f"CavernShaft/Ring_{y}", (18.0, y, 20.0), 5.4 + (y % 3) * 0.2, 0.18, m["violet"], root)
        torus(f"CavernShaft/EnergyRing_{y}", (18.0, y, 20.0), 4.3, 0.08, m["cyan"], root)
    for angle in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):
        rad = angle
        pipe(f"CavernShaft/brace_{angle}", (18.0 + math.cos(rad) * 4.8, 5.0, 20.0 + math.sin(rad) * 4.8), (18.0 + math.cos(rad) * 4.8, 26.0, 20.0 + math.sin(rad) * 4.8), 0.18, m["steel_dark"], root)
    for i, y in enumerate((7.0, 13.0, 19.0)):
        box(f"MaintenanceBridge/{i}/deck", (18.0, y, 13.0), (17.0, 0.24, 1.6), m["steel_light"], root, 0.04)
        box(f"MaintenanceBridge/{i}/rail", (18.0, y + 1.0, 13.7), (17.0, 0.16, 0.16), m["warning"], root, 0.02)
        for x in range(11, 26, 3):
            bolt(f"MaintenanceBridge/{i}/bolt_{x}", (x, y + 0.18, 13.7), m["steel_light"], root, 0.04)
    # Cave-side observation ledges above the factory.
    for i, point in enumerate(((-48.0, 12.0, -35.0), (-8.0, 16.0, 35.0), (38.0, 20.0, 30.0), (62.0, 10.0, -35.0))):
        x, y, z = point
        box(f"CaveObservation/{i}/deck", (x, y, z), (16.0, 0.28, 3.0), m["steel_light"], root, 0.05)
        box(f"CaveObservation/{i}/beam", (x, y - 4.0, z), (0.45, 8.0, 0.45), m["steel"], root, 0.05)
        torus(f"CaveObservation/{i}/lamp", (x, y + 0.34, z - 1.1), 0.24, 0.06, m["warning"], root, (math.pi / 2, 0, 0))
    return root


def build_factory_spine(m):
    """Three-bay gantry spine for a large, readable cave hall.

    The earlier pass stacked six full-height gantries across the whole cave so
    that every camera direction ran through trusses.  This pass keeps three
    structural bays plus two long overhead tracks, so the hall reads as a few
    large structures instead of a lattice.
    """
    root = asset_root("RES_Factory_Spine", "resonance_factory_spine")
    root["gameplay_footprint_m"] = "140 x 46"
    root["lod_plan"] = "hero: full panels/bolts; mid: beams/pipes; far: silhouette"
    steel = m["steel"]
    steel_dark = m["steel_dark"]
    steel_light = m["steel_light"]
    warning = m["warning"]
    cyan = m["cyan"]
    violet = m["violet"]
    green = m["green"]

    # Three big bays: two outer arches frame the hall, the centre gantry marks
    # the production line.  No diagonal braces, no per-level bolt rows.
    bay_x = (-52, 0, 52)
    for index, x in enumerate(bay_x):
        height = 21.0 if index == 1 else 18.0
        for z in (-20.0, 20.0):
            box(f"Gantry/{index}/leg_{z}", (x, height * 0.5, z), (1.5, height, 1.5), steel_dark, root, 0.16)
        box(f"Gantry/{index}/crossbeam", (x, height, 0), (1.2, 1.0, 42.0), steel, root, 0.12)
        box(f"Gantry/{index}/upper_track", (x, height + 0.62, 0), (1.2, 0.20, 42.0), warning, root, 0.035)
        box(f"Gantry/{index}/service_deck", (x, 6.2, 0), (14.0, 0.30, 3.2), steel_dark, root, 0.05)
        box(f"Gantry/{index}/service_rail", (x, 6.66, -1.40), (14.0, 0.14, 0.14), cyan, root, 0.018)

    # Two long overhead tracks with sparse clamps read as a single spine.
    for z, accent in ((-8.0, cyan), (8.0, green)):
        box(f"SpineTrack/{z}/support", (0, 24.0, z), (128.0, 0.40, 0.80), steel_dark, root, 0.07)
        box(f"SpineTrack/{z}/glow", (0, 24.30, z), (126.0, 0.12, 0.16), accent, root, 0.018)
        for x in range(-48, 49, 24):
            box(f"SpineTrack/{z}/clamp_{x}", (x, 24.62, z), (0.50, 0.40, 1.10), steel_light, root, 0.04)
    pipe("SpinePipe/coolant_main", (-62, 8.4, -26), (62, 8.4, -26), 0.34, cyan, root)
    pipe("SpinePipe/reactor_return", (-62, 7.6, 14), (24, 9.2, 14), 0.30, green, root)
    pipe("SpinePipe/energy_feed", (-24, 9.2, 14), (62, 10.4, 4), 0.24, warning, root)

    # One suspended cargo unit keeps the industrial read without clutter.
    pipe("Crane/0/cable", (-30, 24.2, 0), (-30, 15.0, 0), 0.12, warning, root)
    box("Crane/0/cargo", (-30, 13.6, 0), (4.6, 2.8, 3.4), steel, root, 0.16)
    for side in (-1, 1):
        pipe(f"Crane/0/arm_{side}", (-30 + side * 2.3, 14.8, 0), (-30 + side * 3.6, 16.2, 0), 0.16, steel_light, root)
    return root



def _master_child(builder, m, parent, name: str, loc, rot_z: float = 0.0, scale: float = 1.0):
    child = builder(m)
    child.name = name
    child.parent = parent
    child.location = loc
    child.rotation_euler[2] = math.radians(rot_z)
    child.scale = (scale, scale, scale)
    return child


def build_master_scene(m):
    """Compose the complete authored Resonance Star visual map.

    Godot owns gameplay colliders, anchors and state. This asset owns every
    visible static surface: cave, cliffs, deep lava, rails, gantries, zone
    facilities and the static silhouettes of the interaction spaces.
    """
    root = asset_root("RES_Resonance_Master_Scene", "resonance_master_scene")
    root["gameplay_footprint_m"] = "156 x 96 x 34"
    root["visual_authority"] = "Blender authored scene; Godot only supplies collision, interaction and state"
    root["lod_plan"] = "hero: panels/bolts/pipes; mid: structures; far: cave silhouette"

    # Cave shell and the continuous industrial backbone.
    _master_child(build_factory_spine, m, root, "FactorySpine", (0, 0, 0))

    # A restrained cave envelope replaces the old floating-stalactite look in
    # the runtime overview.  It is built from beveled basalt slabs, inset strata
    # and anchored ribs so the factory reads as embedded in a real cavern.
    box("Cave/BackWall", (0, 20.0, -74.0), (224.0, 44.0, 6.0), m["rock"], root, 0.28)
    box("Cave/LeftWall", (-110.0, 20.0, 0.0), (6.0, 44.0, 152.0), m["rock"], root, 0.28)
    # 东侧洞壁塌陷：只留低矮断垣，视线可以越过它看到远景山脊与天空。
    for index, (z, height, width) in enumerate(((-58.0, 10.0, 30.0), (-16.0, 15.0, 26.0), (30.0, 8.0, 34.0), (62.0, 13.0, 24.0))):
        box(f"Cave/CollapsedRim/{index}", (112.0, height * 0.5 - 2.0, z), (7.0, height, width), m["rock"], root, 0.24)
    # 开口外的远景山脊，为洞口提供纵深与尺度参照。
    for index, (x, z, radius, height) in enumerate((
        (178.0, -78.0, 24.0, 44.0), (196.0, -8.0, 28.0, 56.0), (184.0, 58.0, 22.0, 40.0),
        (232.0, -46.0, 32.0, 62.0), (240.0, 30.0, 28.0, 52.0),
    )):
        cyl(f"Vista/Ridge/{index}", (x, height * 0.5 - 6.0, z), radius, height, m["rock"], root, 6, (0.0, 0.0, math.radians(4.0 if index % 2 else -5.0)), 0.25)
    # Four tall ribs frame a 44 m high cavern hall.  Their spacing is large on
    # purpose: the earlier five-rib, 28 m roof made the hall read as a shed.
    for index, x in enumerate((-78.0, -26.0, 26.0, 78.0)):
        box(f"Cave/Rib/{index}", (x, 22.0, -32.0), (2.6, 44.0, 2.6), m["steel_dark"], root, 0.10)
        box(f"Cave/Rib/{index}/roof", (x, 44.0, 0.0), (2.6, 1.8, 92.0), m["steel_dark"], root, 0.10)
    # Distant rock spires and boulder fields sell the scale of the cavern.
    for index, (x, z, radius, height) in enumerate((
        (-96.0, -52.0, 7.0, 30.0), (-88.0, 44.0, 6.0, 24.0), (94.0, -48.0, 6.5, 28.0),
        (88.0, 52.0, 7.5, 32.0), (18.0, -66.0, 8.0, 26.0), (-34.0, 64.0, 6.5, 22.0),
    )):
        cyl(f"Cave/Spire/{index}", (x, height * 0.5 - 4.0, z), radius, height, m["rock"], root, 7, (0.0, 0.0, math.radians(6.0 if index % 2 else -6.0)), 0.22)
        sphere(f"Cave/Boulder/{index}", (x * 0.82, 1.0, z * 0.82), (radius * 1.5, 2.4, radius * 1.3), m["rock"], root)

    # Deep magma basin and stepped cliff faces. The red surface is several
    # metres below the playable decks, so the visual read is a real canyon.
    box("Canyon/LavaSea", (0, -4.02, 0), (360.0, 0.18, 200.0), m["rock"], root, 0.08)
    lava_mat = m["warning"]
    for index, x in enumerate(range(-72, 73, 12)):
        box(f"Canyon/LavaRift_{index}", (x, -3.86, 0), (0.22, 0.08, 78.0), lava_mat, root, 0.02)
    deck_rects = (
        (-68, 8, 28, 24), (-30, 22, 18, 12), (-44, 8, 18, 20),
        (-14, -10, 30, 24), (22, -25, 27, 25), (40, -29, 36, 32),
        (14, 20, 14, 12), (-69, -36, 20, 16)
    )
    for index, (x, z, width, depth) in enumerate(deck_rects):
        cx, cz = x + width * 0.5, z + depth * 0.5
        box(f"CliffDeck/{index}/slab", (cx, -0.20, cz), (width, 0.42, depth), m["rock"], root, 0.18)
        box(f"CliffDeck/{index}/cap", (cx, 0.05, cz), (width - 0.5, 0.16, depth - 0.5), m["steel_dark"], root, 0.06)
        for edge_z in (z - 0.42, z + depth + 0.42):
            box(f"CliffDeck/{index}/edge_{edge_z}", (cx, -1.25, edge_z), (width + 0.9, 2.3, 0.62), m["rock"], root, 0.12)
            box(f"CliffDeck/{index}/magma_edge_{edge_z}", (cx, -3.45, edge_z), (width - 0.8, 0.10, 0.14), lava_mat, root, 0.02)
        for edge_x in (x - 0.42, x + width + 0.42):
            box(f"CliffDeck/{index}/side_{edge_x}", (edge_x, -1.25, cz), (0.62, 2.3, depth + 0.9), m["rock"], root, 0.12)
        for strata in range(3):
            y = -0.65 - strata * 0.85
            box(f"CliffDeck/{index}/strata_{strata}", (cx, y, z - 0.78), (width * (0.82 - strata * 0.10), 0.12, 0.18), m["steel_light"], root, 0.02)
        for bolt_x in range(int(x + 2), int(x + width - 1), 4):
            bolt(f"CliffDeck/{index}/bolt_{bolt_x}", (bolt_x, 0.18, z + 0.48), m["warning"], root, 0.06)

    # Authored rail segments and processing decks along the route.
    # Rails, processing decks and hero landmarks are instanced by Godot from
    # their own Blender GLBs; keeping them separate preserves movement and
    # state visibility without duplicating thousands of meshes in the master.

    # Large visual relay terminals for the mandatory between-module handoff.
    for label, point, accent in (("LowSender", (15, 0.25, -3), m["warning"]), ("HighReceiver", (3, 3.35, -3), m["violet"])):
        box(f"SupportRelay/{label}/base", point, (3.2, 0.45, 2.5), m["steel_dark"], root, 0.12)
        torus(f"SupportRelay/{label}/ring", (point[0], point[1] + 0.42, point[2]), 1.05, 0.11, accent, root)
        for sx in (-1.0, 1.0):
            bolt(f"SupportRelay/{label}/bolt_{sx}", (point[0] + sx * 1.1, point[1] + 0.42, point[2] - 0.72), m["steel_light"], root)
    pipe("SupportRelay/pulse_bridge", (15, 0.55, -3), (3, 3.35, -3), 0.12, m["cyan"], root)

    # Authored heat-valve stations remain visible after Godot's procedural
    # decorative meshes are disabled.  Each station has a service plinth,
    # access panel, hand wheel, bolts and a short pipe manifold.
    heat_valves = {
        "left": (-49.0, 0.0, 14.0),
        "right": (-43.0, 0.0, 28.0),
        "relief": (-24.0, 0.0, 28.0),
    }
    for label, (x, y, z) in heat_valves.items():
        box(f"HeatValves/{label}/plinth", (x, y + 0.48, z), (3.0, 0.96, 2.8), m["steel_dark"], root, 0.12)
        panel(root, (x, y + 0.88, z + 1.42), (1.7, 0.56, 0.14), m, "warning", f"HeatValves/{label}/service_panel")
        torus(f"HeatValves/{label}/handwheel", (x, y + 1.40, z), 0.92, 0.12, m["warning"], root)
        cyl(f"HeatValves/{label}/stem", (x, y + 1.60, z), 0.10, 1.35, m["steel_light"], root, 18)
        for sx, sz in ((-1.08, -0.80), (1.08, -0.80), (-1.08, 0.80), (1.08, 0.80)):
            bolt(f"HeatValves/{label}/bolt_{sx}_{sz}", (x + sx, y + 0.98, z + sz), m["steel_light"], root, 0.07)
        pipe(f"HeatValves/{label}/manifold_left", (x - 1.45, y + 0.42, z), (x - 3.2, y + 0.42, z), 0.13, m["warning"], root)
        pipe(f"HeatValves/{label}/manifold_right", (x + 1.45, y + 0.42, z), (x + 3.2, y + 0.42, z), 0.13, m["warning"], root)

    # Static authored silhouettes for the three reactor-deck mechanisms.
    # Interaction state is still driven by Godot, while the visible machine
    # stays in the Blender asset pipeline.
    box("ReactorMechanisms/Lift/deck", (58.0, 0.22, -22.0), (8.0, 0.34, 5.2), m["steel"], root, 0.10)
    for sx in (-3.45, 3.45):
        box(f"ReactorMechanisms/Lift/side_{sx}", (58.0 + sx, 1.0, -22.0), (0.28, 1.9, 4.6), m["steel_light"], root, 0.06)
        for sz in (-1.7, 1.7):
            pipe(f"ReactorMechanisms/Lift/hydraulic_{sx}_{sz}", (58.0 + sx, 0.3, -22.0 + sz), (58.0 + sx, 3.5, -22.0 + sz), 0.12, m["violet"], root)
    torus("ReactorMechanisms/Lift/indicator", (58.0, 0.72, -22.0), 1.30, 0.11, m["violet"], root)
    mirror_positions = {"left": (46.0, 0.0, -8.0), "right": (58.0, 0.0, -4.0), "center": (65.0, 0.0, -14.0)}
    for label, (x, y, z) in mirror_positions.items():
        box(f"ReactorMechanisms/Mirror/{label}/base", (x, y + 0.35, z), (3.8, 0.7, 2.8), m["steel_dark"], root, 0.08)
        box(f"ReactorMechanisms/Mirror/{label}/reflector", (x, y + 1.3, z), (2.4, 0.20, 1.7), m["glass"], root, 0.06)
        torus(f"ReactorMechanisms/Mirror/{label}/ring", (x, y + 1.02, z), 1.08, 0.10, m["violet"], root)
        for sx in (-1.35, 1.35):
            bolt(f"ReactorMechanisms/Mirror/{label}/bolt_{sx}", (x + sx, y + 0.76, z), m["warning"], root, 0.06)
    box("ReactorMechanisms/Coolant/socket", (63.0, 0.36, -14.0), (4.2, 0.72, 3.2), m["steel_dark"], root, 0.08)
    torus("ReactorMechanisms/Coolant/socket_ring", (63.0, 1.12, -14.0), 1.42, 0.12, m["green"], root)
    box("ReactorMechanisms/Coolant/stabilizer", (58.0, 0.30, -10.0), (3.2, 0.60, 2.6), m["steel_dark"], root, 0.08)
    torus("ReactorMechanisms/Coolant/stabilizer_ring", (58.0, 1.02, -10.0), 1.02, 0.10, m["violet"], root)
    for sx in (-2.2, 2.2):
        box(f"ReactorMechanisms/SafetyGate/post_{sx}", (69.0 + sx, 2.6, -20.0), (0.5, 5.2, 0.7), m["steel_dark"], root, 0.06)
    for index in range(3):
        box(f"ReactorMechanisms/SafetyGate/bar_{index}", (67.6 + index * 1.4, 2.4, -20.0), (0.9, 4.5, 0.34), m["warning"], root, 0.05)

    # Static Blender-authored interaction housings around each moving module.
    # Godot still owns the actual interaction points and state transitions.
    module_positions = [(-34.0, 0.0, 18.0), (0.0, 0.0, 2.0), (34.0, 0.0, -14.0)]
    for module_index, (x, y, z) in enumerate(module_positions, start=1):
        for side, accent in ((-1.0, m["cyan"]), (1.0, m["warning"])):
            box(f"ModuleMechanisms/{module_index}/terminal_{side}/housing", (x + side * 3.4, y + 0.46, z), (1.45, 0.92, 1.7), m["steel_dark"], root, 0.10)
            torus(f"ModuleMechanisms/{module_index}/terminal_{side}/indicator", (x + side * 3.4, y + 1.05, z), 0.46, 0.08, accent, root)
            for sz in (-0.54, 0.54):
                bolt(f"ModuleMechanisms/{module_index}/terminal_{side}/bolt_{sz}", (x + side * 3.4, y + 0.98, z + sz), m["steel_light"], root, 0.05)
        box(f"ModuleMechanisms/{module_index}/route_switch/base", (x, y + 0.30, z - 7.2), (2.6, 0.60, 1.4), m["steel_dark"], root, 0.08)
        torus(f"ModuleMechanisms/{module_index}/route_switch/dial", (x, y + 0.90, z - 7.2), 0.64, 0.10, m["violet"], root)
        if module_index == 2:
            box(f"ModuleMechanisms/{module_index}/freight_box/housing", (x, y + 1.15, z + 5.0), (3.4, 2.1, 2.6), m["steel"], root, 0.12)
            for sz in (-0.92, 0.92):
                torus(f"ModuleMechanisms/{module_index}/freight_box/magnet_{sz}", (x, y + 2.28, z + 5.0 + sz * 0.35), 0.38, 0.07, m["cyan"], root)
            for sx in (-1.15, 1.15):
                bolt(f"ModuleMechanisms/{module_index}/freight_box/bolt_{sx}", (x + sx, y + 2.22, z + 5.0), m["warning"], root, 0.06)
        if module_index == 3:
            for beam_index, local_z in enumerate((-3.6, 0.0, 3.6)):
                box(f"ModuleMechanisms/{module_index}/beam_emitter/{beam_index}", (x + (beam_index - 1) * 2.4, y + 1.15, z + local_z), (1.25, 2.2, 0.55), m["steel_dark"], root, 0.08)
                torus(f"ModuleMechanisms/{module_index}/beam_emitter/ring_{beam_index}", (x + (beam_index - 1) * 2.4, y + 2.25, z + local_z), 0.42, 0.08, m["cyan"], root)

    return root


def render_preview(root, path: Path, target=Vector((0, 3, 0)), camera_loc=(20, 16, -20), ground=True):
    bpy.ops.object.camera_add(location=camera_loc)
    cam = bpy.context.object
    cam.name = "PreviewCamera"
    cam.data.lens = 52
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    for name, loc, energy, size, color in (
        ("Key", (12, 18, -14), 1900, 7, (1.0, 0.64, 0.40)),
        ("Fill", (-12, 10, -3), 1400, 6, (0.34, 0.58, 1.0)),
        ("Rim", (8, 12, 14), 1800, 5, (0.48, 1.0, 0.70)),
    ):
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color
        light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()
    if ground:
        plane_size = 80
        bpy.ops.mesh.primitive_plane_add(size=plane_size, location=(0, -0.22, 0))
        plane = bpy.context.object
        plane.name = "PreviewGround"
        plane.data.materials.append(mat("RS_PreviewGround", (0.045, 0.035, 0.04, 1), 0.0, 0.88, texture=GROUND_TEXTURE))
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(path)
    scene.world.color = (0.025, 0.018, 0.025)
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)
    for obj in list(bpy.data.objects):
        if obj.name in {"PreviewCamera", "Key", "Fill", "Rim", "PreviewGround"}:
            bpy.data.objects.remove(obj, do_unlink=True)


def export_asset(builder, filename: str, m, camera_loc, target):
    clear_scene()
    root = builder(m)
    preview = SOURCE_DIR / filename.replace(".glb", "-preview.png")
    if filename == "resonance_master_scene.glb":
        # Blender's viewport is Z-up while the authored factory coordinates
        # are kept Y-up for the Godot export.  Rotate only the review render,
        # then restore the editable source orientation before saving.
        root.rotation_euler.x = math.radians(90.0)
        render_preview(root, preview, Vector((0, 0, 5)), (38, -42, 18))
        root.rotation_euler.x = 0.0
    else:
        render_preview(root, preview, target, camera_loc)
    blend = SOURCE_DIR / filename.replace(".glb", ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    # Blender's glTF exporter maps Blender (x, y, z) to Godot (x, z, -y).
    # Rotate the authored root once at export time so the runtime asset keeps
    # the intended Y-up gameplay orientation without changing the editable
    # modeling coordinates or the review render.
    root.rotation_euler.x = math.radians(90.0)
    bpy.ops.export_scene.gltf(filepath=str(MODEL_DIR / filename), export_format="GLB",
                              use_selection=False, export_apply=True, export_texcoords=True,
                              export_normals=True, export_materials="EXPORT", export_cameras=False,
                              export_lights=False)
    root.rotation_euler.x = 0.0
    # Purge datablocks between batch assets.  Blender 5.2 can otherwise retain
    # image/material users from a previous glTF export and crash on long runs.
    for datablocks in (bpy.data.materials, bpy.data.images):
        for datablock in list(datablocks):
            if datablock.users == 0 and datablock.name not in {"Render Result"}:
                datablocks.remove(datablock)
    print(f"RES_ASSET {filename} blend={blend} preview={preview}")


def main() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    assets = [
        (build_hero, "resonance_module_hero.glb", (17, 13, -18), Vector((0, 1.4, 0))),
        (build_rail_system, "resonance_rail_system.glb", (22, 17, -22), Vector((0, 2.0, 0))),
        (build_reactor_tower, "resonance_reactor_tower.glb", (24, 18, -24), Vector((0, 7, 0))),
        (build_core, "resonance_energy_core.glb", (10, 9, -12), Vector((0, 1.4, 0))),
        (build_drone_dock, "resonance_drone_dock.glb", (15, 11, -15), Vector((0, 1.0, 0))),
        (build_helper_drone, "resonance_helper_drone.glb", (9, 8, -10), Vector((0, 0, 0))),
        (build_extraction, "resonance_extraction_platform.glb", (18, 14, -18), Vector((0, 1.5, 0))),
        (build_processing_zone, "resonance_processing_zone.glb", (28, 20, -28), Vector((0, 4, 0))),
        (build_surface_set, "resonance_surface_set.glb", (30, 24, -30), Vector((0, 0, 0))),
        (build_factory_spine, "resonance_factory_spine.glb", (86, 52, -92), Vector((0, 7, 0))),
        (build_master_scene, "resonance_master_scene.glb", (132, 88, -150), Vector((0, 4, 0))),
    ]
    for builder, filename, camera_loc, target in assets:
        export_asset(builder, filename, materials(), camera_loc, target)


if __name__ == "__main__":
    main()
