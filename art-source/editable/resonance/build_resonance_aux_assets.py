"""Build only the support-gate and maintenance-facility GLBs.

This small entry point avoids regenerating the already imported hero batch when
iterating on side-branch scenery.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_resonance_factory_assets import (
    SOURCE_DIR,
    MODEL_DIR,
    build_maintenance_facility,
    build_support_gate,
    export_asset,
    materials,
)
from mathutils import Vector


def main() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    palette = materials()
    export_asset(build_support_gate, "resonance_support_safety_gate.glb", palette, (16, 12, -17), Vector((0, 3, 0)))
    export_asset(build_maintenance_facility, "resonance_maintenance_facility.glb", palette, (20, 14, -20), Vector((0, 2.8, 1.0)))


if __name__ == "__main__":
    main()
