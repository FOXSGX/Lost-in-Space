import importlib.util
import math
from pathlib import Path

import bpy

SCRIPT = Path(__file__).with_name("build_resonance_factory_assets.py")
spec = importlib.util.spec_from_file_location("res_factory", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

mod.clear_scene()
m = mod.materials()
root = mod.build_master_scene(m)
preview = mod.SOURCE_DIR / "resonance_master_scene-preview.png"
# Keep the review camera inside the cavern so the authored roof does not
# occlude the factory from above; the Godot captures provide the gameplay
# near/mid/far views.
root.rotation_euler.x = math.radians(90.0)
mod.render_preview(root, preview, target=mod.Vector((0, 0, 5)), camera_loc=(38, -42, 18), ground=False)
root.rotation_euler.x = 0.0
blend = mod.SOURCE_DIR / "resonance_master_scene.blend"
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
root.rotation_euler.x = math.radians(90.0)
bpy.ops.export_scene.gltf(
    filepath=str(mod.MODEL_DIR / "resonance_master_scene.glb"),
    export_format="GLB",
    use_selection=False,
    export_apply=True,
    export_texcoords=True,
    export_normals=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
)
print(f"RES_MASTER blend={blend} preview={preview}")
