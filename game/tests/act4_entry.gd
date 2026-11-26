extends SceneTree

## Thin SceneTree `--script` smoke entry for Act 4 (`res://scenes/act4.tscn`, audit R-12).
## Run: godot --headless --path game --script res://tests/act4_entry.gd

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var packed: PackedScene = load("res://scenes/act4.tscn") as PackedScene
	if packed == null:
		push_error("ACT4_ENTRY_FAILED: could not load res://scenes/act4.tscn")
		quit(1)
		return
	var app: Node = packed.instantiate()
	root.add_child(app)
	current_scene = app
	for _i in range(20):
		await physics_frame
	var platform: Node = app.get("platform") as Node
	var gate: Node = app.get("gate") as Node
	var ok: bool = platform != null and gate != null
	print("ACT4_ENTRY ", "0 failures" if ok else "1 failures", " platform=", platform != null, " gate=", gate != null)
	app.queue_free()
	await physics_frame
	quit(0 if ok else 1)
