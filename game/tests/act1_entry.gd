extends SceneTree

## Thin SceneTree `--script` smoke entry for Act 1 (`res://act1/act01.tscn`, audit R-12 / R-43).
## Run: godot --headless --path game --script res://tests/act1_entry.gd

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var packed: PackedScene = load("res://act1/act01.tscn") as PackedScene
	if packed == null:
		push_error("ACT1_ENTRY_FAILED: could not load res://act1/act01.tscn")
		quit(1)
		return
	var app: Node = packed.instantiate()
	root.add_child(app)
	current_scene = app
	for _i in range(20):
		await physics_frame
	var builder: Variant = app.get("builder")
	var ok: bool = builder != null
	print("ACT1_ENTRY ", "0 failures" if ok else "1 failures", " builder=", ok)
	app.queue_free()
	await physics_frame
	quit(0 if ok else 1)
