extends SceneTree

## Prints the interaction anchors (operate positions) for the integration doc.

var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for i in range(20):
		await physics_frame
	var level: LevelBuilder = app.get("level") as LevelBuilder
	for n in level.find_children("*", "Node", true, false):
		if not n.is_in_group("interactable"):
			continue
		var line: String = "  %s" % n.get_path()
		if n is Node3D:
			line += "  node=%s" % (n as Node3D).global_position.snapped(Vector3(0.01, 0.01, 0.01))
		if "anchor" in n:
			var t: Transform3D = n.get("anchor") as Transform3D
			line += "  anchor=%s" % t.origin.snapped(Vector3(0.01, 0.01, 0.01))
		for child in n.get_children():
			if child is Area3D:
				line += "  area=%s" % (child as Area3D).global_position.snapped(Vector3(0.01, 0.01, 0.01))
		print(line)
	quit()
