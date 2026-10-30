"""Build the four character tools + shield dome as GLB assets.

Run:
    blender --background --python build_character_tools.py
"""

import math
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[3]
OUT_DIR = ROOT / "game" / "assets" / "characters" / "tools"


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, metallic=0.0, roughness=0.4, emission=None, strength=0.0, alpha=1.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            material.blend_method = "BLEND"
            material.use_backface_culling = False
        except AttributeError:
            pass
    return material


def materials():
    return {
        "shell": mat("CT_Shell", (0.30, 0.36, 0.44, 1), 0.68, 0.32),
        "edge": mat("CT_Edge", (0.62, 0.68, 0.76, 1), 0.80, 0.22),
        "grip": mat("CT_Grip", (0.14, 0.16, 0.20, 1), 0.2, 0.55),
        "cyan": mat("CT_Cyan", (0.01, 0.55, 0.75, 1), 0.3, 0.2, (0.05, 0.85, 1.0, 1), 4.0),
        "amber": mat("CT_Amber", (0.65, 0.28, 0.04, 1), 0.4, 0.25, (1.0, 0.35, 0.02, 1), 3.2),
        "teal": mat("CT_Teal", (0.02, 0.45, 0.35, 1), 0.3, 0.2, (0.05, 1.0, 0.72, 1), 3.2),
        "dome": mat("CT_Dome", (0.25, 0.65, 0.95, 1), 0.1, 0.15, (0.2, 0.7, 1.0, 1), 0.6, alpha=0.20),
    }


def box(name, loc, size, material, parent):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    obj.parent = parent
    obj.data.materials.append(material)
    return obj


def cyl(name, loc, radius, depth, material, parent, rot=(0, 0, 0), vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=vertices, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = rot
    obj.parent = parent
    obj.data.materials.append(material)
    return obj


def torus(name, loc, major, minor, material, parent, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(location=loc, major_radius=major, minor_radius=minor)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = rot
    obj.parent = parent
    obj.data.materials.append(material)
    return obj


def sphere(name, loc, scale, material, parent):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, location=loc, segments=20, ring_count=12)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.parent = parent
    obj.data.materials.append(material)
    return obj


def new_root(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


def build_conduit(m):
    """导能枪：短枪身 + 线圈 + 前部发射口，能量青蓝。"""
    root = new_root("TOOL_Conduit")
    box("Body", (0, 0, -0.16), (0.09, 0.11, 0.30), m["shell"], root)
    box("Rail", (0, 0.07, -0.16), (0.05, 0.03, 0.34), m["edge"], root)
    cyl("Grip", (0, -0.12, 0.02), 0.035, 0.18, m["grip"], root, (0, 0, 0), 12)
    cyl("Muzzle", (0, 0, -0.34), 0.055, 0.10, m["edge"], root, (math.pi / 2, 0, 0), 16)
    cyl("Core", (0, 0, -0.38), 0.032, 0.05, m["cyan"], root, (math.pi / 2, 0, 0), 16)
    for index in range(4):
        torus(f"Coil_{index}", (0, 0, -0.24 + index * 0.05), 0.062, 0.011, m["cyan"], root)
    box("Sight", (0, 0.075, -0.05), (0.03, 0.02, 0.10), m["cyan"], root)
    return root


def build_hook(m):
    """磁力钩索：绞盘 + 三爪钩 + 缠线，橙黄。"""
    root = new_root("TOOL_Hook")
    cyl("Drum", (0, 0, 0), 0.075, 0.14, m["shell"], root, (0, math.pi / 2, 0), 16)
    torus("DrumRing", (0, 0, 0), 0.082, 0.014, m["amber"], root, (0, math.pi / 2, 0))
    box("Frame", (0, 0, -0.10), (0.10, 0.09, 0.08), m["edge"], root)
    cyl("Handle", (0, -0.09, 0.06), 0.03, 0.14, m["grip"], root, (0.5, 0, 0), 12)
    for index in range(3):
        angle = index * math.tau / 3.0
        offset = (math.cos(angle) * 0.05, math.sin(angle) * 0.05, -0.17)
        box(f"Prong_{index}", offset, (0.025, 0.025, 0.12), m["edge"], root).rotation_euler = (0, 0, angle)
        sphere(f"ProngTip_{index}", (offset[0], offset[1], -0.235), (0.03, 0.03, 0.03), m["amber"], root)
    torus("Coil", (0, 0, 0.085), 0.045, 0.012, m["amber"], root)
    return root


def build_scanner(m):
    """广域扫描仪：主体 + 碟形天线 + 屏幕，青绿。"""
    root = new_root("TOOL_Scanner")
    box("Body", (0, 0, -0.08), (0.12, 0.07, 0.20), m["shell"], root)
    box("Screen", (0, -0.045, -0.05), (0.09, 0.01, 0.07), m["teal"], root)
    cyl("Mast", (0, 0.02, -0.22), 0.012, 0.16, m["edge"], root, (0, 0, 0), 8)
    cyl("Dish", (0, 0.02, -0.31), 0.10, 0.02, m["edge"], root, (0.5, 0, 0), 20)
    cyl("DishCore", (0, 0.02, -0.32), 0.035, 0.03, m["teal"], root, (0.5, 0, 0), 16)
    for index in range(3):
        box(f"Key_{index}", (-0.03 + index * 0.03, -0.05, 0.02), (0.02, 0.01, 0.02), m["teal"], root)
    return root


def build_shield_device(m):
    """便携护盾：发射器本体，展开时另加载 dome。"""
    root = new_root("TOOL_Shield")
    box("Body", (0, 0, -0.05), (0.13, 0.10, 0.13), m["shell"], root)
    cyl("Emitter", (0, 0, -0.14), 0.06, 0.04, m["edge"], root, (math.pi / 2, 0, 0), 16)
    torus("EmitterRing", (0, 0, -0.16), 0.062, 0.01, m["cyan"], root)
    box("Lever", (0, 0.07, 0.02), (0.03, 0.03, 0.09), m["grip"], root)
    sphere("Lamp", (0, -0.02, 0.03), (0.035, 0.035, 0.035), m["cyan"], root)
    return root


def build_shield_dome(m):
    root = new_root("TOOL_ShieldDome")
    sphere("Dome", (0, 0.95, 0), (2.0, 1.9, 2.0), m["dome"], root)
    torus("DomeRim", (0, 0.02, 0), 0.98, 0.02, m["cyan"], root, (math.pi / 2, 0, 0))
    return root


def export(root, filename: str) -> None:
    root.rotation_euler.x = math.radians(90.0)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_DIR / filename),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    root.rotation_euler.x = 0.0
    print(f"CHARACTER_TOOL {filename}")


def build(builder, filename: str, m) -> None:
    clear_scene()
    materials_map = m()
    root = builder(materials_map)
    export(root, filename)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    build(build_conduit, "tool_conduit.glb", materials)
    build(build_hook, "tool_hook.glb", materials)
    build(build_scanner, "tool_scanner.glb", materials)
    build(build_shield_device, "tool_shield.glb", materials)
    build(build_shield_dome, "shield_dome.glb", materials)
    print("CHARACTER_TOOLS done")


main()
