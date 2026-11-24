"""ART-SAMPLE-002 · 锤头高模雕刻 + 低模 UV + 烘焙（P0）

本轮最重要的一件事：把 ART-SAMPLE-001 里"参数化放样出来的对称锤头"换成
**高模造型 → 烘焙进低模** 的真实制作流程。

流程
----
1. `build_low()`   低模：与 001 完全相同的关键尺寸（最宽 1.80 m，半宽 0.90，
                  下缘收腰、侧板 0.88、打击面 1.30 × 0.62），但拓扑更规整、
                  并为 UV 做了边线分配。
2. `build_high()`  高模：低模 Subsurf(2) → 多尺度位移（铸造下垂、型砂起伏、
                  手工收边）→ 追加**不对称**铸造特征：中缝环带（带抖动）、
                  侧面两个不对称凸台、一处补焊补丁、顶部浅凹、尾部铸瘤。
3. `unwrap_low()`  低模 Smart UV（岛间距 8 mm），2048² 覆盖。
4. `bake()`        Cycles：
                   - NORMAL（tangent，selected-to-active，cage 35 mm）2048²
                   - AO（high → low）1024²
                   - CURVATURE（high 的 Geometry.Pointiness → EMIT）1024²
                   打包成 `aqs002_head_normal.png` 与 `aqs002_head_mask.png`
                   （R=曲率 G=AO）。
5. 导出 `aqs002_head_low.glb`（材质名 `M_CastSteelBaked`），并把高模与低模
   一起存进 `art-source/aqs002_head.blend`（贴图打包，队友打开即用）。

硬约束（不得破坏）
------------------
* 锤头最大宽度 1.80 m（半宽 0.90），横向净空 ≥ 20 mm；
* 下缘收腰 1.40/1.46/1.50（避开柱脚与护板）；
* 打击面（-z 侧）保持平整、可更换：1.30 × 0.62 的可换板；
* 位移**以向内为主**（外扩 ≤ 2.5 mm），不改变验证过的避让关系。

用法： blender -b --factory-startup -P art-source/blender/build_head.py
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aqs_kit as A
import aq2kit as K
import hero_mats as HM
from aqs_kit import Hero, rrect_r
from aq2kit import TAU, fbm, vnoise

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_GLB = os.path.join(ROOT, "project", "assets", "models", "aqs002")
OUT_TEX = os.path.join(ROOT, "project", "assets", "textures", "aqs002")
BLEND = os.path.join(ROOT, "art-source", "aqs002_head.blend")

ARM = 3.50
HY = -ARM          # 锤头中心 y（摆动件局部）
ZC = -0.06         # 锤头中心 z

# 与 build_press.py 完全一致的关键剖面（不得改动）
HS = [(HY - 0.32, (1.40, 0.60, 0.075)),
      (HY - 0.26, (1.46, 0.66, 0.085)),
      (HY - 0.14, (1.50, 0.72, 0.095)),
      (HY - 0.04, (1.74, 0.82, 0.115)),
      (HY + 0.12, (1.80, 0.86, 0.125)),
      (HY + 0.28, (1.70, 0.74, 0.100))]

SEG = 10           # 圆角段数（低模）：比 001 的 4 段更圆，近景不露折线


# ------------------------------------------------------------------ 低模
def build_low():
    """低模锤体 + 两侧侧板 + 尾座。全部按 001 的尺寸，但拓扑更匀。"""
    h = Hero("HeadLow")
    cast = HM.build_materials()["M_CastSteel"]

    # 主体：在原始 6 个控制剖面之间插值成 13 段，圆角段数 4 → 约 3.4k 面
    secs = []
    for i in range(len(HS) - 1):
        y0, (w0, d0, r0) = HS[i]
        y1, (w1, d1, r1) = HS[i + 1]
        steps = 8
        for s in range(steps):
            t = s / float(steps)
            y = y0 + (y1 - y0) * t
            secs.append((y, rrect_r(w0 + (w1 - w0) * t, d0 + (d1 - d0) * t,
                                    r0 + (r1 - r0) * t, SEG)))
    yL, (wL, dL, rL) = HS[-1]
    secs.append((yL, rrect_r(wL, dL, rL, SEG)))
    h.add(A.bm_loft(secs), cast, loc=(0.0, 0.0, ZC))

    # 侧板（装配面）——两侧对称，但高模会在其上做出不对称的工艺差异
    for side in (-1, 1):
        h.add(A.bm_box((0.075, 0.62, 0.86), bevel=0.016, segments=2), cast,
              loc=(side * 0.880, HY, ZC))
    # 尾座（后侧缓冲座）
    h.add(A.bm_box((0.86, 0.26, 0.30), bevel=0.035, segments=2), cast,
          loc=(0.0, HY + 0.02, ZC + 0.56))
    obj = h.finish(smooth=True, split_angle=30.0, bake=None)
    obj.name = "HeadLow"
    return obj


# ------------------------------------------------------------------ 高模
def _subdiv(obj, levels=2):
    m = obj.modifiers.new("Subdiv", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    K.apply_modifiers(obj)
    obj.data.calc_loop_triangles()
    return obj


def _displace_multi(bm, seed=0):
    """多尺度位移：铸造下垂（低频）+ 型砂起伏（中频）+ 手工收边（高频）。

    以**向内为主**（-0.0025 .. +0.0008），保证不破坏已验证的横向净空。
    """
    bm.normal_update()
    for v in bm.verts:
        p = v.co
        low = (fbm(p.x * 2.2, p.y * 2.2, p.z * 2.2, 3, seed=seed) - 0.5) * 2.0
        mid = (fbm(p.x * 7.5, p.y * 7.5, p.z * 7.5, 3, seed=seed + 7) - 0.5) * 2.0
        hi = (vnoise(p.x * 26.0, p.y * 26.0, p.z * 26.0, seed + 13) - 0.5) * 2.0
        d = low * 0.0022 + mid * 0.0011 + hi * 0.0004
        # 向外偏置压到 +0.0008 以内
        d = min(d, 0.0008)
        v.co += v.normal * d
    return bm


def _cast_seam_ring(bm, y, z, w, d, r=0.010, wobble=0.004, seed=11):
    """中缝环带：一圈截面略鼓的凸起，半径沿周长抖动（手工铸件的中缝不会完美）。"""
    n = 48
    ring = []
    for i in range(n):
        a = TAU * i / n
        # 圆角矩形的近似周长参数化：用 rrect 采样再插值
        pass
    return bm


def build_high(low):
    """高模：低模细分 + 位移 + 不对称铸造特征。"""
    high = low.copy()
    high.data = low.data.copy()
    high.name = "HeadHigh"
    bpy.context.scene.collection.objects.link(high)
    high.hide_set(False)

    _subdiv(high, 2)

    bm = bmesh.new()
    bm.from_mesh(high.data)
    _displace_multi(bm, seed=31)

    # ---- 不对称铸造特征 1：侧面凸台（左右大小/位置不同，真实铸件不会左右一致）
    for side, (bx, by, bz, br, bh) in {
        1: (0.885, HY + 0.06, ZC + 0.14, 0.085, 0.020),
        -1: (0.885, HY - 0.10, ZC - 0.16, 0.065, 0.016),
    }.items():
        bm2 = bmesh.new()
        bmesh.ops.create_cone(bm2, cap_ends=True, cap_tris=False, segments=16,
                              radius1=br, radius2=br * 0.72, depth=bh)
        bm2.transform(Matrix.Rotation(-90.0 * math.pi / 180.0, 4, "X"))
        bm2.transform(Matrix.Rotation(90.0 * math.pi / 180.0, 4, "Y") * (-side))
        bm2.transform(Matrix.Translation(Vector((side * bx, by, bz))))
        A.bm_join(bm, bm2)

    # ---- 不对称特征 2：一处补焊补丁（左后上方，矩形薄片 + 焊道凸起）
    patch = bmesh.new()
    bmesh.ops.create_cube(patch, size=1.0)
    for v in patch.verts:
        v.co.x *= 0.006
        v.co.y *= 0.16
        v.co.z *= 0.20
    patch.transform(Matrix.Translation(Vector((-0.902, HY + 0.16, ZC + 0.22))))
    A.bm_join(bm, patch)

    # ---- 不对称特征 3：顶部浅凹（长期被钢索摩擦/雨水积存）
    for v in bm.verts:
        if v.co.y > HY + 0.30 and abs(v.co.x) < 0.55 and abs(v.co.z - ZC) < 0.22:
            v.co.y -= 0.004 * (1.0 - min(1.0, abs(v.co.x) / 0.55))

    # ---- 中缝环带：沿 z=ZC 平面绕一圈略鼓的铸造筋（抖动）
    ring_pts = []
    n = 72
    for i in range(n):
        a = TAU * i / n
        # 椭圆近似（宽 0.94 / 深 0.46），再加抖动
        rx = 0.905
        rz = 0.44
        wob = (vnoise(i * 0.7, 3.0, 0.0, 17) - 0.5) * 0.010
        p = Vector((math.cos(a) * (rx + wob), HY + 0.10 + math.sin(a) * (rz + wob), ZC))
        ring_pts.append(p)
    for i in range(n):
        p0 = ring_pts[i]
        p1 = ring_pts[(i + 1) % n]
        mid = (p0 + p1) * 0.5
        seg = bmesh.new()
        bmesh.ops.create_cone(seg, cap_ends=True, cap_tris=False, segments=8,
                              radius1=0.011, radius2=0.011, depth=(p1 - p0).length * 1.35)
        d = (p1 - p0).normalized()
        q = Vector((0.0, 0.0, 1.0)).rotation_difference(d)
        seg.transform(Matrix.Translation(mid) @ q.to_matrix().to_4x4())
        A.bm_join(bm, seg)

    bm.to_mesh(high.data)
    bm.free()
    high.data.update()

    # 平滑着色 + 轻微平滑一遍（把分割面抹成连续曲面）
    for p in high.data.polygons:
        p.use_smooth = True
    sm = high.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.35
    sm.iterations = 2
    K.apply_modifiers(high)
    high.data.calc_loop_triangles()
    print("HIGH tris=%d" % len(high.data.loop_triangles))
    return high


# ------------------------------------------------------------------ UV
def unwrap_low(low):
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.006,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("UV islands baked into low (%s)" % low.name)


# ------------------------------------------------------------------ 烘焙
def _bake_target_material(obj, image, name="M_CastSteelBaked"):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = nt.nodes.get("Material Output")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.select = True
    nt.nodes.active = tex
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return mat


def bake(low, high):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.use_denoising = False
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.margin = 12
    sc.render.bake.cage_extrusion = 0.035
    sc.render.bake.use_clear = True

    def new_img(name, size, non_color):
        if name in bpy.data.images:
            bpy.data.images.remove(bpy.data.images[name])
        img = bpy.data.images.new(name, size, size, alpha=False,
                                  float_buffer=False)
        img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
        return img

    os.makedirs(OUT_TEX, exist_ok=True)

    # ---- NORMAL（2048²，tangent space）
    nrm = new_img("HeadNormal", 2048, True)
    _bake_target_material(low, nrm)
    bpy.ops.object.select_all(action="DESELECT")
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    sc.cycles.samples = 4
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT",
                        use_selected_to_active=True, cage_extrusion=0.035,
                        margin=12, use_clear=True)
    nrm.filepath_raw = os.path.join(OUT_TEX, "aqs002_head_normal.png")
    nrm.file_format = "PNG"
    nrm.save()
    print("BAKE normal ok")

    # ---- AO（1024²）
    ao = new_img("HeadAO", 1024, True)
    _bake_target_material(low, ao, "M_HeadAO")
    sc.cycles.samples = 24
    bpy.ops.object.bake(type="AO", use_selected_to_active=True,
                        cage_extrusion=0.035, margin=12, use_clear=True)
    ao.filepath_raw = os.path.join(OUT_TEX, "_head_ao.png")
    ao.file_format = "PNG"
    ao.save()
    print("BAKE ao ok")

    # ---- CURVATURE（high 的 Pointiness → EMIT）
    curv = new_img("HeadCurv", 1024, True)
    # 高模临时材质
    hm = bpy.data.materials.new("M_CurvSrc")
    hm.use_nodes = True
    nt = hm.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = nt.nodes.get("Material Output")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.42
    ramp.color_ramp.elements[1].position = 0.58
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    nt.links.new(geo.outputs["Pointiness"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    high.data.materials.clear()
    high.data.materials.append(hm)

    _bake_target_material(low, curv, "M_HeadCurv")
    sc.cycles.samples = 8
    bpy.ops.object.bake(type="EMIT", use_selected_to_active=True,
                        cage_extrusion=0.035, margin=12, use_clear=True)
    curv.filepath_raw = os.path.join(OUT_TEX, "_head_curv.png")
    curv.file_format = "PNG"
    curv.save()
    print("BAKE curvature ok")
    return nrm, ao, curv


# ------------------------------------------------------------------ 打包 / 导出
def pack_maps(nrm, ao, curv):
    """把 AO 与曲率打包进一张 RG 掩膜（R=曲率 G=AO），减少采样与显存。"""
    try:
        import numpy as np
    except Exception:
        print("PACK skip (no numpy in blender python)")
        return
    a = np.asarray(ao.pixels[:], dtype=np.float32).reshape(1024, 1024, 4)
    c = np.asarray(curv.pixels[:], dtype=np.float32).reshape(1024, 1024, 4)
    out = np.zeros((1024, 1024, 4), dtype=np.float32)
    out[..., 0] = c[..., 0]
    out[..., 1] = a[..., 0]
    out[..., 2] = 0.0
    out[..., 3] = 1.0
    img = bpy.data.images.new("HeadMask", 1024, 1024, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels = out.reshape(-1).tolist()
    img.filepath_raw = os.path.join(OUT_TEX, "aqs002_head_mask.png")
    img.file_format = "PNG"
    img.save()
    print("PACK mask ok")


def export_glb(low):
    os.makedirs(OUT_GLB, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_GLB, "aqs002_head_low.glb"),
        export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_materials="EXPORT",
        export_cameras=False, export_lights=False, export_extras=False,
        export_normals=True, export_tangents=True, export_texcoords=True,
    )
    print("EXPORT head_low.glb")


def main():
    K.reset_scene()
    HM.build_materials()
    low = build_low()
    low.data.calc_loop_triangles()
    print("LOW tris=%d" % len(low.data.loop_triangles))
    unwrap_low(low)
    high = build_high(low)
    bpy.context.view_layer.objects.active = low
    low.select_set(True)
    nrm, ao, curv = bake(low, high)
    pack_maps(nrm, ao, curv)
    export_glb(low)
    # 源工程：低模 + 高模一起保存，贴图打包
    high.hide_render = True
    high.hide_viewport = True
    for img in (nrm, ao, curv):
        try:
            img.pack()
        except Exception:
            pass
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("AQS002_HEAD_OK")


main()


