"""只重建共振星大空间改造涉及的两个资产，跳过预览渲染。

用法：
    blender --background --python build_resonance_space_pass.py
"""

import importlib.util
import math
from pathlib import Path

import bpy

SCRIPT = Path(__file__).with_name("build_resonance_factory_assets.py")
spec = importlib.util.spec_from_file_location("res_factory", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def export(builder, filename: str) -> None:
    mod.clear_scene()
    materials = mod.materials()
    root = builder(materials)
    object_count = len(bpy.data.objects)
    blend = mod.SOURCE_DIR / filename.replace(".glb", ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    root.rotation_euler.x = math.radians(90.0)
    bpy.ops.export_scene.gltf(
        filepath=str(mod.MODEL_DIR / filename),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    for datablocks in (bpy.data.materials, bpy.data.images):
        for datablock in list(datablocks):
            if datablock.users == 0 and datablock.name not in {"Render Result"}:
                datablocks.remove(datablock)
    print(f"SPACE_PASS {filename} objects={object_count} blend={blend}")


export(mod.build_master_scene, "resonance_master_scene.glb")
export(mod.build_reactor_tower, "resonance_reactor_tower.glb")
export(mod.build_rail_system, "resonance_rail_system.glb")
export(mod.build_processing_zone, "resonance_processing_zone.glb")
print("SPACE_PASS done")
