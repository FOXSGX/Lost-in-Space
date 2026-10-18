"""Build the first high-detail Resonance Star hero asset.

This script is intentionally Blender-native: the .blend is the editable source,
the GLB is the runtime delivery, and the preview PNG is the review artifact.
Run from the repository root with the portable Blender executable:

    tools/blender-5.2.2-windows-x64/5.2/blender.exe -b --python \
        art-source/editable/resonance/build_resonance_module_hero.py

The model is a movable planetary factory module. It is designed to replace one
procedural module in Godot while preserving the same gameplay footprint.
"""

from __future__ import annotations

import math
import os
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / "art-source" / "editable" / "resonance"
MODEL_DIR = ROOT / "game" / "assets" / "resonance" / "models"
TEXTURE_PATH = ROOT / "game" / "assets" / "resonance" / "textures" / "industrial_panel.png"
BLEND_PATH = SOURCE_DIR / "resonance_module_hero.blend"
GLB_PATH = MODEL_DIR / "resonance_module_hero.glb"
PREVIEW_PATH = SOURCE_DIR / "resonance_module_hero-preview.png"


def ensure_dirs() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)


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


def material(name: str, color: tuple[float, float, float, float], metallic=0.0, roughness=0.45,
             emission=None, emission_strength=0.0, texture=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    set_input(bsdf, "Base Color", color)
    set_input(bsdf, "Metallic", metallic)
    set_input(bsdf, "Roughness", roughness)
    if emission is not None:
        set_input(bsdf, "Emission Color", emission)
        set_input(bsdf, "Emission Strength", emission_strength)
    links.new(bsdf.outputs[0], out.inputs[0])
    if texture and TEXTURE_PATH.exists():
        image = bpy.data.images.load(str(TEXTURE_PATH), check_existing=True)
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Linear"
        tex.projection = "BOX"
        tex.projection_blend = 0.18
        mapping = nodes.new("ShaderNodeMapping")
        texcoord = nodes.new("ShaderNodeTexCoord")
        set_input(mapping, "Scale", (2.6, 2.6, 2.6))
        links.new(texcoord.outputs["Generated"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def make_materials() -> dict[str, bpy.types.Material]:
    return {
        "panel": material("RS_Panel_Industrial", (0.12, 0.16, 0.18, 1), metallic=0.78, roughness=0.32, texture=True),
        "panel_light": material("RS_Panel_Edge", (0.32, 0.39, 0.40, 1), metallic=0.72, roughness=0.28),
        "steel": material("RS_Steel", (0.18, 0.23, 0.25, 1), metallic=0.92, roughness=0.22),
        "dark": material("RS_Rubber_Dark", (0.025, 0.033, 0.038, 1), metallic=0.18, roughness=0.58),
        "amber": material("RS_Amber_Warning", (0.65, 0.18, 0.035, 1), metallic=0.45, roughness=0.25, emission=(1.0, 0.12, 0.02, 1), emission_strength=1.9),
        "cyan": material("RS_Cyan_Resonance", (0.02, 0.32, 0.38, 1), metallic=0.35, roughness=0.20, emission=(0.02, 0.90, 1.0, 1), emission_strength=3.5),
        "yellow": material("RS_Yellow_Indicator", (0.80, 0.48, 0.035, 1), metallic=0.25, roughness=0.24, emission=(1.0, 0.42, 0.02, 1), emission_strength=2.4),
        "glass": material("RS_Optical_Glass", (0.025, 0.11, 0.14, 1), metallic=0.25, roughness=0.11),
    }


def apply_bevel(obj, width=0.08, segments=3) -> None:
    mod = obj.modifiers.new("Edge_softening", "BEVEL")
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


def add_box(name: str, location, scale, mat, bevel=0.06, parent=None):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (scale[0] / 2.0, scale[1] / 2.0, scale[2] / 2.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        apply_bevel(obj, bevel, 3)
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def add_cylinder(name: str, location, radius, depth, mat, vertices=24, rotation=None, bevel=0.03, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location,
                                        rotation=rotation or (0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    if bevel:
        apply_bevel(obj, bevel, 2)
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def add_uv_sphere(name: str, location, scale, mat, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def add_pipe(name: str, a, b, radius, mat, parent=None):
    start, end = Vector(a), Vector(b)
    delta = end - start
    mid = (start + end) * 0.5
    obj = add_cylinder(name, mid, radius, delta.length, mat, vertices=16, bevel=radius * 0.25, parent=parent)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized())
    return obj


def add_bolt(name: str, location, mat, parent=None, radius=0.065):
    return add_cylinder(name, location, radius, 0.035, mat, vertices=12, rotation=(math.pi / 2.0, 0.0, 0.0), bevel=0.012, parent=parent)


def add_ring(name: str, location, major_radius, minor_radius, mat, parent=None, rotation=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major_radius, minor_radius=minor_radius, major_segments=32,
                                     minor_segments=8, location=location, rotation=rotation or (0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def add_panel_grid(parent, mat, edge_mat) -> None:
    # Recessed face panels create readable scale at gameplay distance.
    for row, y in enumerate((0.58, 0.94, 1.30, 1.66)):
        for col, x in enumerate((-3.45, -2.30, -1.15, 0.0, 1.15, 2.30, 3.45)):
            plate = add_box(f"PanelDeck/plate_{row}_{col}", (x, y, -2.53), (0.98, 0.06, 1.16), mat, 0.035, parent)
            plate.rotation_euler.y = (0.015 if (row + col) % 2 else -0.015)
            add_bolt(f"PanelDeck/bolt_{row}_{col}_a", (x - 0.38, y + 0.035, -3.01), edge_mat, parent, 0.045)
            add_bolt(f"PanelDeck/bolt_{row}_{col}_b", (x + 0.38, y + 0.035, -3.01), edge_mat, parent, 0.045)


def build_module(mats: dict[str, bpy.types.Material]):
    root = bpy.data.objects.new("RES_Module_Hero", None)
    bpy.context.collection.objects.link(root)
    root["asset_id"] = "resonance_module_hero"
    root["design_source"] = "art-source/generated/resonance/resonance-grounded-factory-concept.png"
    root["gameplay_footprint_m"] = "10 x 6"
    root["lod_policy"] = "hero_lod0_runtime_lod1"

    # Layered chassis and impact-resistant edge frame.
    add_box("Chassis/base", (0.0, 0.34, 0.0), (10.4, 0.68, 5.9), mats["panel"], 0.22, root)
    add_box("Chassis/lower_shadow", (0.0, 0.06, 0.0), (9.7, 0.26, 5.25), mats["dark"], 0.12, root)
    add_box("Chassis/deck", (0.0, 0.92, 0.0), (9.65, 0.20, 5.15), mats["panel_light"], 0.06, root)
    for x in (-4.72, 4.72):
        add_box(f"Chassis/edge_beam_{x}", (x, 0.78, 0.0), (0.34, 1.04, 5.35), mats["steel"], 0.06, root)
    for z in (-2.35, 2.35):
        add_box(f"Chassis/front_beam_{z}", (0.0, 0.78, z), (9.75, 1.02, 0.32), mats["steel"], 0.06, root)
    for x in (-4.25, -2.85, -1.45, 0.0, 1.45, 2.85, 4.25):
        add_bolt(f"Chassis/deck_bolt_front_{x}", (x, 1.04, -2.32), mats["panel_light"], root)
        add_bolt(f"Chassis/deck_bolt_back_{x}", (x, 1.04, 2.32), mats["panel_light"], root)

    # Main control hood with a stepped silhouette matching the concept sheet.
    add_box("ControlCabin/lower", (-2.8, 1.48, 0.20), (3.10, 0.72, 2.90), mats["panel"], 0.12, root)
    add_box("ControlCabin/upper", (-2.8, 2.24, 0.20), (2.58, 0.76, 2.36), mats["panel_light"], 0.12, root)
    add_box("ControlCabin/visor", (-2.8, 2.48, -1.02), (2.05, 0.24, 0.15), mats["glass"], 0.04, root)
    for x in (-3.72, -2.80, -1.88):
        add_bolt(f"ControlCabin/face_bolt_{x}", (x, 2.12, -1.06), mats["steel"], root, 0.055)
    add_box("ControlCabin/status_strip", (-2.8, 2.47, 1.23), (1.75, 0.07, 0.16), mats["cyan"], 0.02, root)

    # Exposed resonance conduit with readable rings and service nodes.
    add_pipe("Conduit/main", (-0.35, 1.40, -1.92), (3.90, 1.40, -1.92), 0.12, mats["cyan"], root)
    add_pipe("Conduit/return", (-0.35, 1.19, -1.62), (3.90, 1.19, -1.62), 0.07, mats["steel"], root)
    for index, x in enumerate((0.25, 1.15, 2.05, 2.95, 3.75)):
        add_ring(f"Conduit/ring_{index}", (x, 1.4, -1.92), 0.22, 0.035, mats["yellow"], root, rotation=(math.pi / 2.0, 0.0, 0.0))
        add_box(f"Conduit/node_{index}", (x, 1.02, -1.92), (0.22, 0.24, 0.32), mats["steel"], 0.03, root)

    # Front maintenance face: inset plates, warning stripes and many fasteners.
    add_panel_grid(root, mats["panel"], mats["panel_light"])
    for x in (-4.00, -2.00, 0.00, 2.00, 4.00):
        add_box(f"FrontFace/amber_strip_{x}", (x, 1.08, -2.67), (1.45, 0.035, 0.07), mats["amber"], 0.01, root)
    for x in (-4.18, -2.08, 0.02, 2.12, 4.22):
        add_box(f"FrontFace/inspection_hatch_{x}", (x, 1.22, -2.66), (0.56, 0.08, 0.42), mats["steel"], 0.04, root)
        add_bolt(f"FrontFace/hatch_bolt_{x}_a", (x - 0.18, 1.29, -2.82), mats["panel_light"], root, 0.04)
        add_bolt(f"FrontFace/hatch_bolt_{x}_b", (x + 0.18, 1.29, -2.82), mats["panel_light"], root, 0.04)

    # Four articulated rail clamps: gameplay read = module locked to track.
    for side in (-1, 1):
        for z in (-1.72, 1.72):
            x = side * 4.42
            add_box(f"RailClamp/{side}_{z}/mount", (x, 0.52, z), (0.54, 0.82, 0.92), mats["steel"], 0.08, root)
            add_box(f"RailClamp/{side}_{z}/jaw", (side * 4.92, 0.77, z), (0.42, 0.40, 1.25), mats["panel_light"], 0.08, root)
            add_pipe(f"RailClamp/{side}_{z}/piston", (side * 4.48, 0.68, z), (side * 5.24, 0.68, z), 0.10, mats["dark"], root)
            add_pipe(f"RailClamp/{side}_{z}/rod", (side * 5.00, 0.68, z), (side * 5.38, 0.68, z), 0.055, mats["amber"], root)
            add_ring(f"RailClamp/{side}_{z}/ring", (side * 5.30, 0.68, z), 0.16, 0.035, mats["yellow"], root, rotation=(math.pi / 2.0, 0.0, 0.0))
            for dz in (-0.30, 0.30):
                add_bolt(f"RailClamp/{side}_{z}/bolt_{dz}", (side * 5.12, 0.99, z + dz), mats["steel"], root, 0.045)

    # Rear battery stack and cooling fins create a strong silhouette at map scale.
    add_box("RearBattery/housing", (3.15, 1.58, 1.12), (2.42, 1.18, 1.45), mats["panel"], 0.14, root)
    for index, z in enumerate((0.55, 0.82, 1.09, 1.36, 1.63, 1.90)):
        add_box(f"RearBattery/fin_{index}", (3.15, 1.62, z), (2.02, 0.08, 0.12), mats["panel_light"], 0.02, root)
    add_box("RearBattery/status", (2.42, 1.58, 1.12), (0.08, 0.35, 0.72), mats["cyan"], 0.02, root)
    for x in (2.32, 3.15, 3.98):
        add_bolt(f"RearBattery/bolt_{x}", (x, 2.20, 1.14), mats["panel_light"], root)

    # Small props establish authored scale and improve close camera shots.
    for x, z in ((-4.05, 1.55), (-3.40, 1.55), (4.04, -1.40), (3.42, -1.40)):
        add_cylinder(f"ServiceProp/canister_{x}_{z}", (x, 1.40, z), 0.17, 0.62, mats["yellow"], vertices=16, bevel=0.04, parent=root)
        add_ring(f"ServiceProp/canister_ring_{x}_{z}", (x, 1.72, z), 0.17, 0.025, mats["steel"], root)

    return root


def setup_preview(root) -> None:
    bpy.ops.object.camera_add(location=(13.8, 17.0, -16.5))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    target = Vector((0.0, 1.1, 0.0))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 55
    bpy.context.scene.camera = camera

    for name, loc, energy, size, color in (
        ("Key", (7.0, 12.0, -10.0), 2600.0, 6.0, (1.0, 0.68, 0.48)),
        ("Fill", (-10.0, 7.0, -3.0), 1900.0, 5.0, (0.38, 0.72, 1.0)),
        ("Rim", (4.0, 9.0, 10.0), 2200.0, 4.0, (1.0, 0.40, 0.16)),
    ):
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color
        light.rotation_euler = (Vector((0.0, 1.0, 0.0)) - light.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.mesh.primitive_plane_add(size=50, location=(0.0, -0.16, 0.0))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground.data.materials.append(material("RS_PreviewGround", (0.07, 0.085, 0.10, 1), metallic=0.0, roughness=0.82))

    scene = bpy.context.scene
    # Blender 5.2 portable exposes the Eevee engine as BLENDER_EEVEE.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.world.color = (0.025, 0.035, 0.055)
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)


def strip_preview_only_objects() -> None:
    # Keep the camera, lights and ground in the editable .blend, but never ship
    # them inside the runtime GLB.
    for obj in list(bpy.data.objects):
        if obj.name in {"PreviewCamera", "Key", "Fill", "Rim", "PreviewGround"}:
            bpy.data.objects.remove(obj, do_unlink=True)


def export() -> None:
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    strip_preview_only_objects()
    bpy.ops.export_scene.gltf(filepath=str(GLB_PATH), export_format="GLB", use_selection=False,
                              export_apply=True, export_texcoords=True, export_normals=True,
                              export_materials="EXPORT", export_cameras=False, export_lights=False)


def main() -> None:
    ensure_dirs()
    clear_scene()
    mats = make_materials()
    root = build_module(mats)
    setup_preview(root)
    export()
    print(f"RES_MODULE_HERO_BLEND={BLEND_PATH}")
    print(f"RES_MODULE_HERO_GLB={GLB_PATH}")
    print(f"RES_MODULE_HERO_PREVIEW={PREVIEW_PATH}")


if __name__ == "__main__":
    main()
