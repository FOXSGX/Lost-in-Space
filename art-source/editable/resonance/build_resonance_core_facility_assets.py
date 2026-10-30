"""Regenerate the reactor tower and extraction platform only."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from mathutils import Vector
from build_resonance_factory_assets import (
    SOURCE_DIR,
    MODEL_DIR,
    build_extraction,
    build_reactor_tower,
    export_asset,
    materials,
)


def main() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    palette = materials()
    export_asset(build_reactor_tower, "resonance_reactor_tower.glb", palette, (24, 18, -24), Vector((0, 7, 0)))
    export_asset(build_extraction, "resonance_extraction_platform.glb", palette, (18, 14, -18), Vector((0, 1.5, 0)))


if __name__ == "__main__":
    main()
