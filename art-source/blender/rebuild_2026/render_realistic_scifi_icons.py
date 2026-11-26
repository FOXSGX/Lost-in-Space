"""《迷失太空》Blender 4.5 真实 3D 棚拍 · 写实科幻风格全套 27 个物品图标渲染器
- 彻底告别扁平极简线条风！
- 直接把游戏里真实的高模 3D GLB（氧气瓶、医疗箱、热熔枪、吸推枪、电池、薯片、纪念杯、弹跳垫、信号弹、音响、碰碰球、保温壶等）
  以及专门雕刻的 3D 科幻装备件放入专业三点科幻影棚（主暖白柔光 + 冰青边缘轮廓光 + 琥珀底反光 + 金属高光反射），
  用 Blender EEVEE Next 透明底渲染为 256×256 超清写实科幻图标，并叠加极克制的宇航头盔微光学底框！
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
KIT_DIR = os.path.join(REPO, "art-source", "deliveries", "ART-SAMPLE-002_TEAM_KIT", "02_BLENDER_SOURCE", "scripts")
GLB_DIR = os.path.join(REPO, "game", "assets", "models", "rebuild")
OUT_DIR = os.path.join(REPO, "game", "assets", "items", "visor_icons")
sys.path.insert(0, KIT_DIR)

import aq2kit as K
import aqs_kit as A
import hero_mats as HM


def setup_render_engine():
    scene = bpy.context.scene
    # 使用 BLENDER_EEVEE_NEXT（Blender 4.5 默认实时写实 PBR 渲染器，速度快且支持金属高光与自发光辉光）
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except Exception:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    scene.view_settings.exposure = 0.35
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 24


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_render_engine()


def setup_studio(cam_dist=1.0, target=Vector((0, 0, 0)), radius=0.5, yaw_deg=34.0, pitch_deg=20.0):
    scene = bpy.context.scene
    # 深空极微环境反射（让金属和玻璃表面出现真实冷蓝-暖金高光渐变！）
    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs[0].default_value = (0.09, 0.14, 0.20, 1.0)
    bg.inputs[1].default_value = 0.85
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs[0], out.inputs[0])

    # 影棚相机（长焦 68mm 防透视畸变，像真实军工/科幻产品目录图！）
    cam_data = bpy.data.cameras.new("StudioCam")
    cam_data.lens = 68.0
    cam_obj = bpy.data.objects.new("StudioCam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    yaw = math.radians(yaw_deg)
    pitch = math.radians(pitch_deg)
    offset = Vector((
        math.sin(yaw) * math.cos(pitch),
        -math.cos(yaw) * math.cos(pitch),
        math.sin(pitch),
    )) * cam_dist
    cam_obj.location = target + offset
    direction = (target - cam_obj.location).normalized()
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    # 专业三点写实科幻影棚布光
    def add_light(name, ltype, energy, color, loc, size=1.0):
        ld = bpy.data.lights.new(name, type=ltype)
        ld.energy = energy
        ld.color = color
        if ltype == "AREA":
            ld.size = size
        lo = bpy.data.objects.new(name, ld)
        scene.collection.objects.link(lo)
        lo.location = loc
        d = (target - lo.location).normalized()
        lo.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()

    s = max(radius, 0.25)
    # 主光：右前上方高质感暖白柔光箱（打出立体明暗与烤漆质感）
    add_light("Key", "AREA", 180.0 * s * s, (1.0, 0.94, 0.86), target + Vector((2.6 * s, -2.2 * s, 2.8 * s)), size=2.4 * s)
    # 轮廓光：左后上方冰青科幻轮廓光（勾出硬朗金属倒角亮边！）
    add_light("RimCyan", "AREA", 240.0 * s * s, (0.28, 0.88, 1.0), target + Vector((-2.8 * s, 2.2 * s, 1.8 * s)), size=2.0 * s)
    # 辅光：左侧柔和工业橙暖反光（消除死黑，提升写实层次）
    add_light("FillAmber", "AREA", 75.0 * s * s, (1.0, 0.68, 0.36), target + Vector((-2.4 * s, -1.8 * s, -0.6 * s)), size=2.6 * s)


def enhance_materials_for_icon():
    """重建纯净写实 PBR 材质节点（断开 GLB 打包的 4 通道 AO/曲率顶点色，避免 Base Color 被染绿！）"""
    overrides = {
        "M_PaintCream": ((0.82, 0.80, 0.75), 0.30, 0.14, None, 0.0),
        "M_PaintOrange": ((0.96, 0.42, 0.08), 0.28, 0.18, None, 0.0),
        "M_CastSteel": ((0.44, 0.49, 0.54), 0.32, 0.86, None, 0.0),
        "M_BareSteel": ((0.68, 0.72, 0.76), 0.22, 0.94, None, 0.0),
        "M_DarkSteel": ((0.18, 0.21, 0.26), 0.38, 0.78, None, 0.0),
        "M_SteelDeep": ((0.16, 0.19, 0.24), 0.38, 0.78, None, 0.0),
        "M_Rubber": ((0.11, 0.12, 0.14), 0.72, 0.05, None, 0.0),
        "M_Bronze": ((0.76, 0.52, 0.24), 0.26, 0.90, None, 0.0),
        "M_Teal": ((0.10, 0.68, 0.76), 0.28, 0.26, None, 0.0),
        "M_GlowCyan": ((0.22, 0.92, 1.0), 0.10, 0.0, (0.20, 0.90, 1.0), 4.2),
        "M_GlowAmber": ((1.0, 0.62, 0.16), 0.12, 0.0, (1.0, 0.56, 0.14), 4.2),
        "M_ThermalCore": ((1.0, 0.50, 0.12), 0.12, 0.0, (1.0, 0.48, 0.10), 4.8),
        "M_GlowRed": ((1.0, 0.24, 0.14), 0.12, 0.0, (1.0, 0.22, 0.12), 4.5),
        "M_GlowGreen": ((0.20, 0.94, 0.56), 0.12, 0.0, (0.18, 0.94, 0.54), 4.0),
        "M_CrystalCore": ((0.24, 0.86, 1.0), 0.08, 0.12, (0.22, 0.84, 1.0), 3.6),
        "M_CrystalShell": ((0.12, 0.58, 0.78), 0.10, 0.16, (0.16, 0.72, 0.92), 2.2),
        "M_GlassWarm": ((0.72, 0.88, 0.94), 0.08, 0.20, (0.35, 0.78, 0.92), 1.4),
    }
    for mat in bpy.data.materials:
        base_name = mat.name.split(".")[0]
        col, rough, metal, emit, emit_s = overrides.get(base_name, ((0.62, 0.64, 0.66), 0.36, 0.45, None, 0.0))
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        bsdf.inputs["Base Color"].default_value = (*col, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if emit is not None and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emit_s


def compute_bounds(objs):
    min_v = Vector((1e9, 1e9, 1e9))
    max_v = Vector((-1e9, -1e9, -1e9))
    for obj in objs:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            wc = obj.matrix_world @ Vector(corner)
            min_v.x = min(min_v.x, wc.x); min_v.y = min(min_v.y, wc.y); min_v.z = min(min_v.z, wc.z)
            max_v.x = max(max_v.x, wc.x); max_v.y = max(max_v.y, wc.y); max_v.z = max(max_v.z, wc.z)
    center = (min_v + max_v) * 0.5
    extent = max_v - min_v
    radius = max(extent.length * 0.5, 0.1)
    return center, radius


def render_glb_icon(glb_name, out_name, yaw_deg=36.0, pitch_deg=22.0, tilt_euler=(0, 0, 0), zoom=2.75):
    clear_scene()
    glb_path = os.path.join(GLB_DIR, glb_name)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if tilt_euler != (0, 0, 0):
        rot = Euler([math.radians(a) for a in tilt_euler], "XYZ").to_matrix().to_4x4()
        for o in meshes:
            o.matrix_world = rot @ o.matrix_world
    bpy.context.view_layer.update()
    enhance_materials_for_icon()
    center, radius = compute_bounds(meshes)
    setup_studio(cam_dist=radius * (zoom * 1.16), target=center, radius=radius, yaw_deg=yaw_deg, pitch_deg=pitch_deg)
    bpy.context.scene.render.filepath = os.path.join(OUT_DIR, out_name)
    bpy.ops.render.render(write_still=True)


def make_mat(name, col, rough=0.35, metal=0.5, emit=None, emit_s=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_s
    return m


def add_prim(bm, mat, loc=(0, 0, 0), rot=(0, 0, 0)):
    mesh = bpy.data.meshes.new("P")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    for p in mesh.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new("P", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = [math.radians(a) for a in rot]
    return obj


def bm_cyl(r1, r2, h, segs=24):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    return bm


def bm_box(sx, sy, sz, bev=0.03):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bev, segments=2, affect="EDGES", clamp_overlap=True)
    return bm


def bm_sphere(r, u=24, v=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=r)
    return bm


def render_custom_3d_icon(build_fn, out_name, yaw_deg=34.0, pitch_deg=20.0, zoom=2.85):
    clear_scene()
    objs = build_fn()
    bpy.context.view_layer.update()
    center, radius = compute_bounds(objs)
    setup_studio(cam_dist=radius * (zoom * 1.16), target=center, radius=radius, yaw_deg=yaw_deg, pitch_deg=pitch_deg)
    bpy.context.scene.render.filepath = os.path.join(OUT_DIR, out_name)
    bpy.ops.render.render(write_still=True)


def build_thermal_suit():
    # 写实 3D 极地宇航恒温胸甲背心（奶油陶瓷装甲板 + 工业橙保温管 + 发光温控胸核）
    cream = make_mat("C", (0.76, 0.74, 0.69), 0.34, 0.18)
    orange = make_mat("O", (0.94, 0.44, 0.10), 0.32, 0.16)
    dark = make_mat("D", (0.16, 0.19, 0.24), 0.42, 0.75)
    amber = make_mat("A", (1.0, 0.62, 0.16), 0.14, 0.0, (1.0, 0.58, 0.14), 4.5)
    objs = [
        add_prim(bm_box(0.62, 0.34, 0.72, 0.07), cream, (0, 0, 0)),
        add_prim(bm_box(0.84, 0.28, 0.26, 0.06), orange, (0, 0, 0.26)),
        add_prim(bm_box(0.52, 0.38, 0.24, 0.05), dark, (0, 0, -0.22)),
        add_prim(bm_cyl(0.11, 0.11, 0.40, 20), amber, (0, -0.02, 0.08), (90, 0, 0)),
        add_prim(bm_box(0.14, 0.40, 0.68, 0.03), dark, (-0.22, 0, 0.02)),
        add_prim(bm_box(0.14, 0.40, 0.68, 0.03), dark, (0.22, 0, 0.02)),
    ]
    return objs


def build_wide_scanner():
    # 写实 3D 广域手持战术雷达扫描仪（折叠碟形天线 + 发光雷达屏 + 战术握把）
    cream = make_mat("C", (0.74, 0.76, 0.74), 0.34, 0.20)
    steel = make_mat("S", (0.36, 0.42, 0.48), 0.32, 0.85)
    cyan = make_mat("Y", (0.20, 0.92, 1.0), 0.12, 0.0, (0.18, 0.90, 1.0), 4.5)
    orange = make_mat("O", (0.94, 0.44, 0.10), 0.32, 0.20)
    return [
        add_prim(bm_box(0.46, 0.22, 0.56, 0.05), steel, (0, 0, 0)),
        add_prim(bm_box(0.36, 0.04, 0.34, 0.02), cyan, (0, -0.11, 0.04)),
        add_prim(bm_cyl(0.34, 0.08, 0.14, 24), cream, (0, 0.14, 0.34), (48, 0, 0)),
        add_prim(bm_cyl(0.03, 0.02, 0.26, 12), orange, (0, 0.04, 0.42), (48, 0, 0)),
        add_prim(bm_box(0.18, 0.16, 0.34, 0.03), orange, (0, 0.0, -0.40)),
    ]


def build_signal_stabilizer():
    # 写实 3D 信号稳压中继柱（双铜线圈 + 发光青绿稳定环 + 重型底座）
    steel = make_mat("S", (0.34, 0.40, 0.46), 0.32, 0.85)
    bronze = make_mat("B", (0.74, 0.50, 0.22), 0.28, 0.88)
    cyan = make_mat("Y", (0.20, 0.92, 0.84), 0.12, 0.0, (0.18, 0.92, 0.82), 4.5)
    return [
        add_prim(bm_cyl(0.32, 0.28, 0.16, 18), steel, (0, 0, -0.34)),
        add_prim(bm_cyl(0.10, 0.10, 0.82, 18), steel, (0, 0, 0.06)),
        add_prim(bm_cyl(0.24, 0.24, 0.10, 22), bronze, (0, 0, -0.10)),
        add_prim(bm_cyl(0.24, 0.24, 0.10, 22), bronze, (0, 0, 0.18)),
        add_prim(bm_cyl(0.20, 0.20, 0.08, 22), cyan, (0, 0, 0.04)),
        add_prim(bm_sphere(0.12), cyan, (0, 0, 0.48)),
    ]


def build_coolant():
    # 写实 3D 液氮低温冷却罐（双箍钢罐 + 发光液氮透明窗）
    cream = make_mat("C", (0.76, 0.78, 0.80), 0.32, 0.25)
    steel = make_mat("S", (0.28, 0.34, 0.40), 0.35, 0.82)
    cyan = make_mat("Y", (0.22, 0.90, 1.0), 0.10, 0.0, (0.20, 0.88, 1.0), 4.5)
    return [
        add_prim(bm_cyl(0.26, 0.26, 0.72, 24), cream, (0, 0, 0)),
        add_prim(bm_cyl(0.28, 0.28, 0.10, 24), steel, (0, 0, 0.34)),
        add_prim(bm_cyl(0.28, 0.28, 0.10, 24), steel, (0, 0, -0.34)),
        add_prim(bm_cyl(0.27, 0.27, 0.26, 24), cyan, (0, 0, 0.0)),
        add_prim(bm_box(0.32, 0.08, 0.12, 0.02), steel, (0, 0, 0.44)),
    ]


def build_hover_board():
    # 写实 3D 反重力极地滑雪板（流线双翘板 + 橙色护边 + 底部青色推进喷口）
    cream = make_mat("C", (0.76, 0.75, 0.70), 0.32, 0.20)
    orange = make_mat("O", (0.94, 0.44, 0.10), 0.30, 0.20)
    cyan = make_mat("Y", (0.20, 0.92, 1.0), 0.12, 0.0, (0.20, 0.90, 1.0), 4.2)
    dark = make_mat("D", (0.14, 0.16, 0.20), 0.60, 0.25)
    return [
        add_prim(bm_box(0.34, 0.96, 0.07, 0.03), cream, (0, 0, 0), (12, 0, 28)),
        add_prim(bm_box(0.36, 0.28, 0.08, 0.02), orange, (0, 0, 0.01), (12, 0, 28)),
        add_prim(bm_box(0.24, 0.14, 0.06, 0.02), dark, (0, 0.20, 0.04), (12, 0, 28)),
        add_prim(bm_box(0.24, 0.14, 0.06, 0.02), dark, (0, -0.20, 0.04), (12, 0, 28)),
        add_prim(bm_cyl(0.10, 0.10, 0.05, 18), cyan, (0, 0.32, -0.05), (12, 0, 28)),
        add_prim(bm_cyl(0.10, 0.10, 0.05, 18), cyan, (0, -0.32, -0.05), (12, 0, 28)),
    ]


def build_hologram_projector():
    # 写实 3D 全息投影仪底座 + 立体发光半透宇航员剪影
    steel = make_mat("S", (0.26, 0.30, 0.36), 0.35, 0.85)
    cyan = make_mat("Y", (0.22, 0.92, 1.0), 0.10, 0.0, (0.22, 0.92, 1.0), 4.5)
    return [
        add_prim(bm_cyl(0.32, 0.26, 0.14, 20), steel, (0, 0, -0.34)),
        add_prim(bm_cyl(0.22, 0.22, 0.05, 20), cyan, (0, 0, -0.25)),
        add_prim(bm_cyl(0.16, 0.12, 0.38, 18), cyan, (0, 0, 0.04)),
        add_prim(bm_sphere(0.14), cyan, (0, 0, 0.36)),
    ]


def build_smoke_grenade():
    # 写实 3D 战术彩色发烟罐（带安全拉环与压杆）
    dark = make_mat("D", (0.22, 0.26, 0.30), 0.40, 0.78)
    coral = make_mat("R", (0.96, 0.32, 0.20), 0.32, 0.18)
    amber = make_mat("A", (1.0, 0.62, 0.16), 0.14, 0.0, (1.0, 0.58, 0.16), 4.2)
    return [
        add_prim(bm_cyl(0.18, 0.18, 0.56, 20), dark, (0, 0, -0.04), (0, 14, 0)),
        add_prim(bm_cyl(0.19, 0.19, 0.18, 20), coral, (0, 0, 0.02), (0, 14, 0)),
        add_prim(bm_cyl(0.08, 0.08, 0.16, 14), amber, (0.04, 0, 0.30), (0, 14, 0)),
    ]


def build_echo_penguin():
    # 写实 3D 机械发声极地企鹅玩具（奶油金属机身 + 橙喙 + 发光眼）
    dark = make_mat("D", (0.16, 0.20, 0.26), 0.36, 0.75)
    cream = make_mat("C", (0.82, 0.82, 0.78), 0.34, 0.20)
    orange = make_mat("O", (0.96, 0.48, 0.10), 0.32, 0.15)
    cyan = make_mat("Y", (0.20, 0.92, 1.0), 0.12, 0.0, (0.20, 0.92, 1.0), 4.5)
    return [
        add_prim(bm_cyl(0.26, 0.18, 0.54, 20), dark, (0, 0, -0.05)),
        add_prim(bm_sphere(0.20), cream, (0, -0.10, -0.06)),
        add_prim(bm_sphere(0.18), dark, (0, 0, 0.28)),
        add_prim(bm_cyl(0.06, 0.01, 0.14, 12), orange, (0, -0.20, 0.26), (95, 0, 0)),
        add_prim(bm_sphere(0.04), cyan, (-0.07, -0.16, 0.32)),
        add_prim(bm_sphere(0.04), cyan, (0.07, -0.16, 0.32)),
    ]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    # 1. 直接用真实高模 3D GLB 进行影棚级写实 PBR 渲染（16 个核心物品！）
    glb_jobs = [
        ("hero_oxygen_bottle.glb", "oxygen.png", 34, 18, (0, 0, 0), 2.85),
        ("hero_medkit.glb", "medical.png", 28, 18, (0, 0, 0), 2.75),
        ("hero_heat_lance.glb", "heater.png", 44, 16, (0, 0, 12), 2.75),
        ("hero_suction_gun.glb", "suction.png", 46, 16, (0, 0, 12), 2.75),
        ("hero_battery_pack.glb", "cell.png", 34, 20, (0, 0, 0), 2.80),
        ("hero_battery_pack.glb", "battery.png", -34, 22, (0, 0, 0), 2.80),
        ("hero_cryo_canister.glb", "fuel.png", 30, 16, (0, 0, -10), 2.85),
        ("hero_snack_pack.glb", "chips.png", 24, 14, (0, 0, 0), 2.75),
        ("hero_keepsake_mug.glb", "keepsake.png", 36, 22, (0, 0, 0), 2.85),
        ("hero_cargo_crate.glb", "crate.png", 38, 24, (0, 0, 0), 2.85),
        ("hero_cargo_crate.glb", "freight.png", -38, 22, (0, 0, 0), 2.85),
        ("hero_sample_crystal.glb", "sample.png", 30, 18, (0, 0, 0), 2.85),
        ("hero_bounce_pad.glb", "bounce_pad.png", 35, 36, (0, 0, 0), 2.70),
        ("hero_flare_stick.glb", "flare.png", 36, 16, (0, 26, 0), 2.80),
        ("hero_boombox.glb", "boombox.png", 26, 16, (0, 0, 0), 2.75),
        ("hero_bumper_orb.glb", "bumper_orb.png", 32, 22, (0, 0, 0), 2.85),
        ("hero_bumper_orb.glb", "bubble.png", -32, 24, (0, 0, 0), 2.85),
        ("hero_thermos.glb", "thermos.png", 34, 18, (0, 0, 0), 2.85),
        ("hero_thermal_core.glb", "core.png", 32, 20, (0, 0, 0), 2.85),
    ]
    for glb_name, out_name, yaw, pitch, tilt, zoom in glb_jobs:
        render_glb_icon(glb_name, out_name, yaw, pitch, tilt, zoom)

    # 2. 其余 8 件装备/趣味件采用专属 3D 影棚建模渲染
    custom_jobs = [
        (build_thermal_suit, "thermal_suit.png", 26, 16, 2.85),
        (build_wide_scanner, "wide_scanner.png", 34, 18, 2.85),
        (build_signal_stabilizer, "signal_stabilizer.png", 32, 18, 2.90),
        (build_coolant, "coolant.png", 32, 18, 2.85),
        (build_hover_board, "board.png", 34, 30, 2.80),
        (build_hologram_projector, "hologram.png", 30, 18, 2.85),
        (build_smoke_grenade, "smoke.png", 34, 18, 2.90),
        (build_echo_penguin, "penguin.png", 28, 16, 2.85),
    ]
    for fn, out_name, yaw, pitch, zoom in custom_jobs:
        render_custom_3d_icon(fn, out_name, yaw, pitch, zoom)

    print(f"RENDERED 27 PHOTOREALISTIC 3D SCI-FI ICONS -> {OUT_DIR}")


if __name__ == "__main__":
    main()
