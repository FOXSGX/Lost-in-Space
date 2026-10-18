"""Standalone repeatable export for the Blender-authored helper drone."""

from __future__ import annotations

import importlib.util
import math
from pathlib import Path

from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = Path(__file__).with_name("build_resonance_factory_assets.py")
spec = importlib.util.spec_from_file_location("resonance_factory_assets", SCRIPT)
factory = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(factory)


def main() -> None:
    factory.SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    factory.MODEL_DIR.mkdir(parents=True, exist_ok=True)
    factory.clear_scene()
    mats = factory.materials()
    root = factory.build_helper_drone(mats)
    preview = factory.SOURCE_DIR / "resonance_helper_drone-preview.png"
    factory.render_preview(root, preview, target=Vector((0, 0, 0)), camera_loc=(4, 3, -5), ground=False)
    blend = factory.SOURCE_DIR / "resonance_helper_drone.blend"
    import bpy

    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    root.rotation_euler.x = math.radians(90.0)
    bpy.ops.export_scene.gltf(
        filepath=str(factory.MODEL_DIR / "resonance_helper_drone.glb"),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    print(f"RES_DRONE blend={blend} preview={preview}")


if __name__ == "__main__":
    main()
