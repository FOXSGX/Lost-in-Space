"""Debug/recovery entry point for the hero module."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mathutils import Vector
from build_resonance_factory_assets import SOURCE_DIR, MODEL_DIR, build_hero, export_asset, materials

def main() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    export_asset(build_hero, "resonance_module_hero.glb", materials(), (17, 13, -18), Vector((0, 1.4, 0)))

if __name__ == "__main__":
    main()
