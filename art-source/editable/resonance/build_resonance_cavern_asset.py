"""Generate the cavern shell and vertical maintenance routes."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from mathutils import Vector
from build_resonance_factory_assets import SOURCE_DIR, MODEL_DIR, build_cavern_shell, export_asset, materials


def main() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    export_asset(build_cavern_shell, "resonance_cavern_shell.glb", materials(), (78, 58, -84), Vector((0, 10, 0)))


if __name__ == "__main__":
    main()
