"""ART-SAMPLE-002 · 重新导出锤头低模（三角化，保证 glTF 能算切线）

bake 已在 build_head.py 里完成，这里只做"打开源工程 → 三角化 → 导出"，
避免重复烘焙（每次烘焙约 2 分钟）。

用法： blender -b art-source/aqs002_head.blend -P art-source/blender/export_head.py
"""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_GLB = os.path.join(ROOT, "project", "assets", "models", "aqs002")


def main():
    low = bpy.data.objects.get("HeadLow")
    if low is None:
        raise RuntimeError("HeadLow not found in blend")
    low.hide_set(False)
    low.hide_viewport = False
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    m = low.modifiers.new("Tri", "TRIANGULATE")
    m.quad_method = "BEAUTY"
    m.ngon_method = "BEAUTY"
    for mod in list(low.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    # 导出前把材质名改回美术约定名（烘焙时临时用的是 M_HeadCurv 等目标材质）
    for mat in low.data.materials:
        if mat is not None:
            mat.name = "M_CastSteelBaked"
    low.data.calc_loop_triangles()
    os.makedirs(OUT_GLB, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_GLB, "aqs002_head_low.glb"),
        export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_materials="EXPORT",
        export_cameras=False, export_lights=False, export_extras=False,
        export_normals=True, export_tangents=True, export_texcoords=True,
    )
    print("EXPORT_HEAD_OK tris=%d" % len(low.data.loop_triangles))


main()

