"""Blender 主角皮肤目录：男生帅气 / 女生好看 / 沙雕搞怪。

  ranger    默认：钢蓝侦察兵 + 风衣后摆 + 青色面罩光缝        （男性）
  gala      星际集市：黑金礼服 + 红色面罩 + 金边                （男性）
  nova      星际集市：珍珠白礼服 + 品红面罩 + 裙摆              （女性）
  valkyrie  星际集市：绯红重甲 + 金色翎羽盔 + 橙色面罩          （女性）
  duck      星际集市：充气小黄鸭（沙雕）                        （通用）

Godot 侧契约（所有皮肤一致）：
  - Body 下挂 LeftArmPivot / RightArmPivot / LeftElbowPivot / RightElbowPivot /
    LeftLegPivot / RightLegPivot / LeftKneePivot / RightKneePivot / HeadPivot
  - 网格名保持：Helmet / Visor / Backpack / YellowShoulder / Torso / ChestPanel ...
  - 脚在 z=0，正面朝 -Y（Blender）→ 导出后朝 -Z（Godot）

坐标换算：位置 gv(x,y,z)=(x,-z,y)；尺寸 gs(x,y,z)=(x,z,y)

Run:
    blender --background --python build_protagonist.py
"""

import math
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[3]
OUT_DIR = ROOT / "game" / "assets" / "characters" / "skins"

STYLES = {
    "ranger": {
        "body": "male",
        "suit": (0.42, 0.58, 0.70, 1),
        "dark": (0.10, 0.15, 0.21, 1),
        "plate": (0.62, 0.70, 0.78, 1),
        "chest": (0.82, 0.86, 0.90, 1),
        "accent": (1.0, 0.62, 0.10, 1),
        "pack": (0.22, 0.32, 0.42, 1),
        "glow": (0.10, 0.75, 1.0, 1),
        "glow_strength": 5.0,
        "coat": 1.0, "skirt": 0.0, "bulk": 1.0, "crest": 0.20,
        "tanks": False, "pauldron": False, "plume": False, "duck": False,
    },
    "gala": {
        "body": "male",
        "suit": (0.06, 0.07, 0.10, 1),
        "dark": (0.02, 0.02, 0.04, 1),
        "plate": (0.85, 0.68, 0.28, 1),
        "chest": (0.12, 0.11, 0.13, 1),
        "accent": (0.95, 0.78, 0.35, 1),
        "pack": (0.05, 0.05, 0.07, 1),
        "glow": (1.0, 0.25, 0.20, 1),
        "glow_strength": 6.0,
        "coat": 1.45, "skirt": 0.0, "bulk": 0.95, "crest": 0.26,
        "tanks": False, "pauldron": False, "plume": False, "duck": False,
    },
    "nova": {
        "body": "female",
        "suit": (0.88, 0.90, 0.94, 1),
        "dark": (0.12, 0.14, 0.20, 1),
        "plate": (0.72, 0.80, 0.90, 1),
        "chest": (0.98, 0.98, 1.0, 1),
        "accent": (1.0, 0.55, 0.75, 1),
        "pack": (0.30, 0.36, 0.48, 1),
        "glow": (1.0, 0.35, 0.75, 1),
        "glow_strength": 5.5,
        "coat": 0.0, "skirt": 1.0, "bulk": 0.88, "crest": 0.30,
        "tanks": False, "pauldron": False, "plume": False, "duck": False,
    },
    "valkyrie": {
        "body": "female",
        "suit": (0.55, 0.10, 0.14, 1),
        "dark": (0.16, 0.04, 0.06, 1),
        "plate": (0.88, 0.70, 0.30, 1),
        "chest": (0.70, 0.18, 0.20, 1),
        "accent": (1.0, 0.80, 0.35, 1),
        "pack": (0.35, 0.10, 0.12, 1),
        "glow": (1.0, 0.55, 0.12, 1),
        "glow_strength": 5.0,
        "coat": 0.0, "skirt": 0.7, "bulk": 1.02, "crest": 0.34,
        "tanks": False, "pauldron": True, "plume": True, "duck": False,
    },
    "duck": {
        "body": "male",
        "suit": (1.0, 0.82, 0.12, 1),
        "dark": (0.95, 0.70, 0.05, 1),
        "plate": (1.0, 0.90, 0.40, 1),
        "chest": (1.0, 0.95, 0.65, 1),
        "accent": (1.0, 0.45, 0.10, 1),
        "pack": (1.0, 0.75, 0.10, 1),
        "glow": (1.0, 0.55, 0.10, 1),
        "glow_strength": 2.0,
        "coat": 0.0, "skirt": 0.0, "bulk": 1.35, "crest": 0.0,
        "tanks": False, "pauldron": False, "plume": False, "duck": True,
    },
}


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    material.diffuse_color = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = strength
    return material


def palette(cfg):
    return {
        "suit": mat("PX_Suit", cfg["suit"], 0.15, 0.45),
        "suit_dark": mat("PX_SuitDark", cfg["dark"], 0.25, 0.40),
        "plate": mat("PX_Plate", cfg["plate"], 0.55, 0.30),
        "visor": mat("PX_Visor", (0.02, 0.03, 0.05, 1), 0.85, 0.08, cfg["glow"], 0.6),
        "chest": mat("PX_Chest", cfg["chest"], 0.35, 0.35),
        "yellow": mat("PX_Accent", cfg["accent"], 0.30, 0.30, cfg["accent"], 1.6),
        "glove": mat("PX_Glove", cfg["dark"], 0.30, 0.45),
        "boot": mat("PX_Boot", cfg["dark"], 0.30, 0.45),
        "pack": mat("PX_Pack", cfg["pack"], 0.45, 0.35),
        "glow": mat("PX_Glow", cfg["glow"], 0.2, 0.12, cfg["glow"], cfg["glow_strength"]),
    }


def gv(x, y, z):
    return (x, -z, y)


def gs(x, y, z):
    return (x, z, y)


def bevel(obj, width=0.015, segments=3):
    modifier = obj.modifiers.new("Bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def cube(name, loc, size, material, parent, bevel_width=0.015, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = gs(*size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.rotation_euler = rot
    if bevel_width > 0:
        bevel(obj, bevel_width, 3)
    obj.parent = parent
    obj.data.materials.append(material)
    return obj


def sphere(name, loc, scale, material, parent, segments=24, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, location=loc, segments=segments, ring_count=rings)
    obj = bpy.context.object
    obj.name = name
    obj.scale = gs(*scale)
    bpy.ops.object.shade_smooth()
    obj.parent = parent
    obj.data.materials.append(material)
    apply_view_color(obj, material)
    return obj


def cylinder(name, loc, radius, depth, material, parent, rot=(0, 0, 0), vertices=20, radius_top=None):
    if radius_top is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=vertices, location=loc)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=radius_top, depth=depth, vertices=vertices, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = rot
    bpy.ops.object.shade_smooth()
    obj.parent = parent
    obj.data.materials.append(material)
    apply_view_color(obj, material)
    return obj


def apply_view_color(obj, material) -> None:
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        obj.color = bsdf.inputs["Base Color"].default_value


def empty(name, loc, parent):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.parent = parent
    return obj


def build(cfg, m):
    female = cfg["body"] == "female"
    duck = cfg["duck"]
    root = empty("ProtagonistRoot", (0, 0, 0), None)
    body = empty("Body", (0, 0, 0), root)
    bulk = cfg["bulk"]
    shoulder_x = 0.19 if female else 0.21
    waist = 0.24 if female else 0.26
    hip_x = 0.27 if female else 0.30

    # ── 骨盆与腰 ─────────────────────────────────────────────
    cube("Hips", gv(0, 0.94, 0), (hip_x * bulk, 0.20, 0.22 * bulk), m["suit_dark"], body, 0.05)
    cube("Belt", gv(0, 1.02, 0), (0.33 * bulk, 0.08, 0.235 * bulk), m["plate"], body, 0.02)
    cube("BeltBuckle", gv(0, 1.02, -0.125 * bulk), (0.07, 0.05, 0.03), m["glow"], body, 0.008)
    if female:
        cube("HipPlates", gv(0, 1.00, 0.02), (0.36 * bulk, 0.10, 0.19 * bulk), m["plate"], body, 0.03)

    # ── 躯干 ─────────────────────────────────────────────────
    cube("Abdomen", gv(0, 1.13, 0), (waist * bulk * 0.92, 0.17, 0.17 * bulk), m["suit"], body, 0.04)
    cube("Torso", gv(0, 1.30, 0.005), (0.35 * bulk, 0.30, 0.22 * bulk), m["suit"], body, 0.07)
    cube("ChestTaper", gv(0, 1.21, -0.005), (0.30 * bulk, 0.10, 0.20 * bulk), m["suit_dark"], body, 0.03)
    cube("ChestPlate", gv(0, 1.36, -0.11 * bulk), (0.29 * bulk, 0.18, 0.06), m["plate"], body, 0.02, (0.12, 0, 0))
    cube("ChestPanel", gv(0, 1.22, -0.13 * bulk), (0.15, 0.12, 0.04), m["chest"], body, 0.012)
    cube("ChestCore", gv(0, 1.24, -0.155 * bulk), (0.06, 0.06, 0.02), m["glow"], body, 0.006)
    cube("Collar", gv(0, 1.46, 0.01), (0.23 * bulk, 0.09, 0.20 * bulk), m["plate"], body, 0.025)
    cube("PulseStripL", gv(-0.175 * bulk, 1.30, 0.02), (0.015, 0.16, 0.06), m["glow"], body, 0.004)
    cube("PulseStripR", gv(0.175 * bulk, 1.30, 0.02), (0.015, 0.16, 0.06), m["glow"], body, 0.004)

    # 风衣后摆 / 裙摆
    if cfg["coat"] > 0.0:
        length = 0.46 * cfg["coat"]
        for name, sign in (("CoatL", -1.0), ("CoatR", 1.0)):
            cube(name, gv(sign * 0.10, 0.86 - length * 0.5, 0.17), (0.16, length, 0.05),
                 m["suit_dark"], body, 0.02, (0.12, 0, sign * 0.10))
            cube(name + "Trim", gv(sign * 0.10, 0.86 - length, 0.17), (0.16, 0.03, 0.055),
                 m["glow"], body, 0.004, (0.12, 0, sign * 0.10))
    if cfg["skirt"] > 0.0:
        length = 0.34 * cfg["skirt"]
        for name, sign in (("SkirtL", -1.0), ("SkirtR", 1.0), ("SkirtBack", 1.0)):
            x = sign * (0.13 if name != "SkirtBack" else 0.0)
            z = 0.14 if name != "SkirtBack" else 0.19
            cube(name, gv(x, 0.88 - length * 0.5, z), (0.20, length, 0.04),
                 m["suit"], body, 0.015, (0.10, 0, sign * 0.12))
            cube(name + "Trim", gv(x, 0.88 - length, z), (0.20, 0.025, 0.045),
                 m["glow"], body, 0.004, (0.10, 0, sign * 0.12))

    # ── 背包 ─────────────────────────────────────────────────
    cube("Backpack", gv(0, 1.28, 0.185), (0.24 * bulk, 0.28, 0.12), m["pack"], body, 0.035)
    cube("BackpackLid", gv(0, 1.43, 0.18), (0.21 * bulk, 0.07, 0.10), m["suit_dark"], body, 0.02)
    for name, x in (("TankL", -0.155), ("TankR", 0.155)):
        cylinder(name, gv(x, 1.24, 0.20), 0.045, 0.26, m["plate"], body, (0, 0, 0), 14)
    for name, x in (("ThrusterL", -0.09), ("ThrusterR", 0.09)):
        cylinder(name, gv(x, 1.10, 0.21), 0.035, 0.10, m["plate"], body, (math.pi / 2, 0, 0), 14)
        cylinder(name + "Glow", gv(x, 1.06, 0.21), 0.026, 0.03, m["glow"], body, (math.pi / 2, 0, 0), 12)
    cube("PackCore", gv(0, 1.30, 0.28), (0.10, 0.10, 0.02), m["glow"], body, 0.006)
    if cfg["tanks"]:
        for name, x in (("TankL", -0.20), ("TankR", 0.20)):
            cylinder(name, gv(x, 1.24, 0.24), 0.075, 0.34, m["plate"], body, (0, 0, 0), 16)

    # ── 头 ───────────────────────────────────────────────────
    head = empty("HeadPivot", gv(0, 1.52, 0), body)
    cylinder("Neck", gv(0, -0.02, 0), 0.05, 0.08, m["suit_dark"], head, (0, 0, 0), 16)
    if duck:
        sphere("Helmet", gv(0, 0.16, -0.01), (0.34, 0.34, 0.36), m["suit"], head)
        cube("Visor", gv(0, 0.16, -0.17), (0.10, 0.06, 0.05), m["glow"], head, 0.01)
        cube("Jaw", gv(0, 0.06, -0.20), (0.16, 0.05, 0.14), m["yellow"], head, 0.02, (0.25, 0, 0))
        sphere("HelmetCrest", gv(0, 0.34, 0.0), (0.10, 0.08, 0.16), m["yellow"], head)
    else:
        sphere("Helmet", gv(0, 0.13, -0.005), (0.235, 0.245, 0.26), m["suit"], head)
        sphere("HelmetCrest", gv(0, 0.25, 0.02), (0.06, 0.16, cfg["crest"] + 0.08), m["plate"], head)
        cube("Visor", gv(0, 0.14, -0.112), (0.165, 0.07, 0.05), m["visor"], head, 0.012, (-0.10, 0, 0))
        cube("VisorSlit", gv(0, 0.135, -0.138), (0.155, 0.018, 0.012), m["glow"], head, 0.004, (-0.10, 0, 0))
        cube("Jaw", gv(0, 0.055, -0.055), (0.17, 0.09, 0.13), m["suit_dark"], head, 0.03)
        if female:
            # 侧发片 + 后颈护片，做出女性剪影
            for name, x in (("HairL", -0.17), ("HairR", 0.17)):
                cube(name, gv(x, 0.02, 0.06), (0.07, 0.22, 0.10), m["suit_dark"], head, 0.02, (0.10, 0, 0))
            cube("HairBack", gv(0, 0.00, 0.16), (0.18, 0.20, 0.06), m["suit_dark"], head, 0.02)
        if cfg["plume"]:
            cylinder("Plume", gv(0, 0.34, -0.02), 0.05, 0.22, m["yellow"], head, (0.25, 0, 0), 12, 0.01)
    for name, x in (("LeftEar", -0.145), ("RightEar", 0.145)):
        cylinder(name, gv(x, 0.14, -0.01), 0.045, 0.05, m["plate"], head, (0, math.pi / 2, 0), 14)
    cylinder("Antenna", gv(0.10, 0.28, 0.04), 0.006, 0.16, m["glove"], head, (0.12, 0, 0), 6)
    sphere("AntennaTip", gv(0.115, 0.36, 0.05), (0.028, 0.028, 0.028), m["glow"], head)

    # ── 手臂 ─────────────────────────────────────────────────
    for name, sign in (("Left", -1.0), ("Right", 1.0)):
        shoulder = empty(f"{name}ArmPivot", gv(sign * shoulder_x * bulk, 1.42, 0.0), body)
        sphere(f"{name}Shoulder", (0, 0, 0), (0.135 * bulk, 0.13, 0.135 * bulk), m["suit"], shoulder)
        sphere(f"{name}PauldronRound", (sign * 0.01, 0.03, 0), (0.155 * bulk, 0.12, 0.16 * bulk), m["plate"], shoulder)
        if name == "Left":
            cube("YellowShoulder", gv(sign * 0.05, 0.03, 0), (0.12 * bulk, 0.10, 0.14 * bulk), m["yellow"], shoulder, 0.03, (0, 0.22, 0))
        else:
            cube("RightShoulderPad", gv(sign * 0.05, 0.03, 0), (0.12 * bulk, 0.10, 0.14 * bulk), m["plate"], shoulder, 0.03, (0, -0.22, 0))
        if cfg["pauldron"]:
            cube(f"{name}Pauldron", gv(sign * 0.08, 0.05, 0), (0.16, 0.10, 0.18), m["plate"], shoulder, 0.03, (0, sign * 0.30, 0))
        cylinder(f"{name}Arm", gv(0, -0.15, 0), 0.05 * bulk, 0.24, m["suit"], shoulder, (0, 0, 0), 16, 0.043)
        elbow = empty(f"{name}ElbowPivot", gv(0, -0.29, 0.0), shoulder)
        sphere(f"{name}Elbow", (0, 0, 0), (0.07, 0.07, 0.07), m["suit_dark"], elbow)
        cylinder(f"{name}Forearm", gv(0, -0.13, 0), 0.048 * bulk, 0.22, m["plate"], elbow, (0, 0, 0), 16, 0.040)
        cube(f"{name}Glove", gv(0, -0.27, -0.01), (0.085, 0.11, 0.10), m["glove"], elbow, 0.02)
        cube(f"{name}Knuckle", gv(0, -0.27, -0.065), (0.07, 0.04, 0.02), m["glow"], elbow, 0.005)

    # ── 腿 ───────────────────────────────────────────────────
    for name, sign in (("Left", -1.0), ("Right", 1.0)):
        hip = empty(f"{name}LegPivot", gv(sign * 0.10 * bulk, 0.92, 0.0), body)
        cube(f"{name}ThighPlate", gv(sign * 0.02, -0.06, -0.03), (0.12 * bulk, 0.18, 0.12 * bulk), m["plate"], hip, 0.02, (0, sign * 0.12, 0))
        cylinder(f"{name}Leg", gv(0, -0.16, 0), 0.065 * bulk, 0.28, m["suit"], hip, (0, 0, 0), 16, 0.055)
        knee = empty(f"{name}KneePivot", gv(0, -0.32, 0.0), hip)
        sphere(f"{name}Knee", (0, 0, 0), (0.075 * bulk, 0.075, 0.075 * bulk), m["suit_dark"], knee)
        cylinder(f"{name}Shin", gv(0, -0.20, 0), 0.055 * bulk, 0.36, m["suit"], knee, (0, 0, 0), 16, 0.048)
        cube(f"{name}Boot", gv(0, -0.53, -0.015), (0.10 * bulk, 0.13, 0.21), m["boot"], knee, 0.035)
        cube(f"{name}BootToe", gv(0, -0.555, -0.13), (0.095 * bulk, 0.07, 0.10), m["boot"], knee, 0.025, (0.12, 0, 0))
        cube(f"{name}SoleGlow", gv(0, -0.592, -0.05), (0.085, 0.015, 0.15), m["glow"], knee, 0.004)

    return root


def export(root, path: Path) -> None:
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_yup=True,
    )
    print(f"SKIN_GLB {path}")


def setup_preview_scene() -> None:
    """给预览图打光、摆机位：Workbench 渲染，稳定且不依赖 GPU。"""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "BOTH"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.color = (0.05, 0.07, 0.10)
    scene.display.render_aa = "8"

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens = 60.0
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (1.7, 3.3, 1.55)
    scene.camera = camera
    target = bpy.data.objects.new("PreviewTarget", None)
    bpy.context.collection.objects.link(target)
    target.location = (0.0, 0.0, 0.98)
    track = camera.constraints.new(type="TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"

    key_data = bpy.data.lights.new("Key", type="AREA")
    key_data.energy = 900.0
    key_data.size = 3.0
    key = bpy.data.objects.new("Key", key_data)
    key.location = (2.4, -3.2, 3.4)
    key.rotation_euler = (math.radians(50.0), 0.0, math.radians(35.0))
    bpy.context.collection.objects.link(key)


def render_preview(path: Path) -> None:
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print(f"SKIN_PREVIEW {path}")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    preview_dir = OUT_DIR / "previews"
    preview_dir.mkdir(parents=True, exist_ok=True)
    for style_name, cfg in STYLES.items():
        clear_scene()
        materials_map = palette(cfg)
        root = build(cfg, materials_map)
        export(root, OUT_DIR / f"skin_{style_name}.glb")
        setup_preview_scene()
        render_preview(preview_dir / f"skin_{style_name}.png")
    print("SKINS done")


main()
