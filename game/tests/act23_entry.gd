extends SceneTree

## Thin SceneTree `--script` smoke entry for Act 2-3 (`res://scenes/act23.tscn`, audit R-12 / R-13).
## Run: godot --headless --path game --script res://tests/act23_entry.gd

const PhysicsLayers := preload("res://scripts/core/physics_layers.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var packed: PackedScene = load("res://scenes/act23.tscn") as PackedScene
	if packed == null:
		push_error("ACT23_ENTRY_FAILED: could not load res://scenes/act23.tscn")
		quit(1)
		return
	var app: Node = packed.instantiate()
	root.add_child(app)
	current_scene = app
	for _i in range(20):
		await physics_frame
	var cave: Node = app.find_child("CaveCollision", true, false)
	var rock: Node = app.find_child("RockCaveCollision", true, false)
	var cave_ok: bool = cave is StaticBody3D and ((cave as StaticBody3D).collision_layer & PhysicsLayers.WORLD) != 0
	var rock_ok: bool = rock is StaticBody3D and ((rock as StaticBody3D).collision_layer & PhysicsLayers.WORLD) != 0
	var ok: bool = cave_ok and rock_ok
	print("ACT23_ENTRY ", "0 failures" if ok else "1 failures", " cave_world=", cave_ok, " rock_world=", rock_ok)
	app.queue_free()
	await physics_frame
	quit(0 if ok else 1)
