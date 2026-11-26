extends SceneTree

## Prints the current world coordinates of every gameplay anchor so the
## integration document quotes measured values instead of stale ones.

var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for i in range(30):
		await physics_frame
	var level: LevelBuilder = app.get("level") as LevelBuilder
	print("== interactables ==")
	for n in level.find_children("*", "Node", true, false):
		if n.is_in_group("interactable"):
			var n3: Node3D = n as Node3D
			if n3 != null:
				print("  %s  %s" % [n3.get_path(), n3.global_position.snapped(Vector3(0.01, 0.01, 0.01))])
	print("== named anchors ==")
	for p in ["ResonanceCore", "LeftCounterweight", "RightCounterweight", "LockRig", "ExtractionIsolationRig",
			"DataPlinth", "MemoryShard", "ExitBlastDoor", "LeftStation", "RightStation"]:
		var n: Node3D = level.find_child(p, true, false) as Node3D
		if n != null:
			print("  %s  %s" % [p, n.global_position.snapped(Vector3(0.01, 0.01, 0.01))])
	print("== players / triggers ==")
	var player: PlayerController = app.get("player") as PlayerController
	print("  spawn  %s" % player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))
	for n in level.find_children("*Trigger*", "Area3D", true, false):
		print("  %s  %s" % [n.get_path(), (n as Area3D).global_position.snapped(Vector3(0.01, 0.01, 0.01))])
	print("== weights ==")
	print("  left cart %s  right cart %s" % [level.left_cart.global_position.snapped(Vector3(0.01, 0.01, 0.01)), level.right_cart.global_position.snapped(Vector3(0.01, 0.01, 0.01))])
	print("  rail top y %.2f  inner/outer x %.2f/%.2f" % [WeightCart.RAIL_TOP_Y, WeightCart.INNER_X, WeightCart.OUTER_X])
	quit()
