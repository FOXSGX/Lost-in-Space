"""Build the resonance cave kit in Blender.

Assets:
  cave_rock_wall.glb    irregular rock slab cluster (10 x 30 x 4 m)
  cave_stalactite.glb   hanging spike cluster (8 m)
  cave_ore_crystal.glb  glowing ore cluster (emissive)
  cave_floor_tile.glb   20 x 20 m displaced rock tile with vertex colours

Run:
    blender --background --python build_cave_kit.py
"""

import math
import random
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[3]
OUT_DIR = ROOT / "game" / "assets" / "resonance" / "models"


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, metallic=0.0, roughness=0.85, emission=None, strength=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = strength
    material.diffuse_color = color
    return material


def rock_materials():
    return {
        "rock": mat("Cave_Rock", (0.16, 0.12, 0.12, 1)),
        "rock_dark": mat("Cave_RockDark", (0.09, 0.07, 0.07, 1)),
        "rock_warm": mat("Cave_RockWarm", (0.24, 0.15, 0.11, 1)),
        "crack": mat("Cave_Crack", (0.55, 0.22, 0.08, 1), 0.0, 0.5, (1.0, 0.42, 0.12, 1), 3.0),
        "ore_cyan": mat("Cave_OreCyan", (0.15, 0.55, 0.75, 1), 0.2, 0.25, (0.25, 0.85, 1.0, 1), 5.0),
        "ore_amber": mat("Cave_OreAmber", (0.9, 0.5, 0.15, 1), 0.2, 0.25, (1.0, 0.55, 0.12, 1), 4.0),
    }


def rock_blob(name, loc, scale, material, parent, seed):
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.5, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    for vertex in obj.data.vertices:
        factor = 0.82 + rng.random() * 0.36
        vertex.co *= factor
    obj.parent = parent
    obj.data.materials.append(material)
    bpy.ops.object.shade_flat()
    return obj


def build_rock_wall(m):
    root = bpy.data.objects.new("CaveRockWall", None)
    bpy.context.collection.objects.link(root)
    rng = random.Random(20261018)
    # 主岩板：上下错落的几块
    for index in range(9):
        x = (index - 4) * 1.15 + rng.uniform(-0.2, 0.2)
        y = rng.uniform(-0.4, 0.4)
        z = 15.0 + rng.uniform(-1.2, 1.2)
        rock_blob(f"Slab{index}", (x, y, z), (3.4, 2.6, 30.0 + rng.uniform(-2.0, 3.0)), m["rock"], root, index)
    # 底部岩堆
    for index in range(7):
        rock_blob(f"Base{index}", (rng.uniform(-5.0, 5.0), rng.uniform(-1.2, 1.2), rng.uniform(0.6, 2.4)),
                  (3.2, 3.0, 2.6), m["rock_dark"], root, 100 + index)
    # 岩层里的发光裂缝
    for index in range(4):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(rng.uniform(-4.0, 4.0), 1.6, rng.uniform(6.0, 24.0)))
        crack = bpy.context.object
        crack.name = f"Crack{index}"
        crack.scale = (rng.uniform(0.6, 1.4), 0.12, rng.uniform(1.6, 4.0))
        crack.rotation_euler = (0.0, rng.uniform(-0.3, 0.3), rng.uniform(-0.4, 0.4))
        crack.parent = root
        crack.data.materials.append(m["crack"])
    return root


def build_stalactite(m):
    root = bpy.data.objects.new("CaveStalactite", None)
    bpy.context.collection.objects.link(root)
    rng = random.Random(7)
    for index in range(5):
        height = rng.uniform(4.0, 8.5)
        radius = rng.uniform(0.5, 1.1)
        bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=radius * 0.12, depth=height,
                                        vertices=8, location=(rng.uniform(-2.0, 2.0), rng.uniform(-2.0, 2.0), -height * 0.5))
        spike = bpy.context.object
        spike.name = f"Spike{index}"
        spike.rotation_euler = (rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), 0.0)
        spike.parent = root
        spike.data.materials.append(m["rock_dark"] if index % 2 else m["rock"])
    return root


def build_ore(m):
    root = bpy.data.objects.new("CaveOre", None)
    bpy.context.collection.objects.link(root)
    rng = random.Random(11)
    for index in range(7):
        height = rng.uniform(0.7, 1.9)
        bpy.ops.mesh.primitive_cone_add(radius1=rng.uniform(0.18, 0.34), radius2=0.0, depth=height,
                                        vertices=5, location=(rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7), height * 0.42))
        crystal = bpy.context.object
        crystal.name = f"Ore{index}"
        crystal.rotation_euler = (rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), rng.uniform(0.0, 6.28))
        crystal.parent = root
        crystal.data.materials.append(m["ore_cyan"] if index % 3 else m["ore_amber"])
    rock_blob("OreBase", (0.0, 0.0, 0.18), (1.9, 1.9, 0.7), m["rock_dark"], root, 55)
    return root


def build_floor_tile(m):
    root = bpy.data.objects.new("CaveFloorTile", None)
    bpy.context.collection.objects.link(root)
    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.object
    plane.name = "FloorRock"
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.subdivide(number_cuts=23)
    bpy.ops.object.mode_set(mode="OBJECT")
    # 用分形噪声抬高低频起伏
    texture = bpy.data.textures.new("CaveFloorNoise", type="CLOUDS")
    texture.noise_scale = 2.4
    displace = plane.modifiers.new("Displace", "DISPLACE")
    displace.texture = texture
    displace.strength = 0.55
    displace.mid_level = 0.5
    bpy.context.view_layer.objects.active = plane
    bpy.ops.object.modifier_apply(modifier=displace.name)
    bpy.ops.object.shade_flat()
    plane.parent = root
    plane.data.materials.append(m["rock"])
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
    print(f"CAVE_ASSET {filename}")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for builder, filename in [
        (build_rock_wall, "cave_rock_wall.glb"),
        (build_stalactite, "cave_stalactite.glb"),
        (build_ore, "cave_ore_crystal.glb"),
        (build_floor_tile, "cave_floor_tile.glb"),
    ]:
        clear_scene()
        materials_map = rock_materials()
        root = builder(materials_map)
        export(root, filename)
    print("CAVE_KIT done")


main()
