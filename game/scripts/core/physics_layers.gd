class_name PhysicsLayers
extends RefCounted

## Single source of truth for the project's 3D physics layers (`project.godot`).
const WORLD := 1         # Layer 1: static geometry / level collision
const PLAYER := 2        # Layer 2: player CharacterBody3D
const INTERACT := 4      # Layer 3: interactable / dynamic props
const MACHINE := 8       # Layer 4: heavy machines / rigs
const TRIGGER := 16      # Layer 5: Area3D triggers / carts
const CAMERA_PROBE := 32 # Layer 6: camera-only shell / moving deck floor
