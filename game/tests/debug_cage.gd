extends SceneTree

var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for i in range(40):
		await physics_frame
	var level: LevelBuilder = app.get("level") as LevelBuilder
	var outer: Node = level.get_node_or_null("ResonanceCore/Swing/OuterRing")
	print("=== outer children ===")
	for c in outer.get_children():
		print("  ", c.name, " ", c.get_class(), " pos=", (c as Node3D).position if c is Node3D else "")
	print("=== all meshes beginning Cage ===")
	for n in level.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if str(mi.name).begins_with("Cage"):
			print("  ", mi.get_path(), " aabb=", mi.global_transform * mi.get_aabb())
	print("=== crystals ===")
	for n3 in level.find_children("*", "MeshInstance3D", true, false):
		var m3: MeshInstance3D = n3 as MeshInstance3D
		if str(m3.name).to_lower().contains("crystal"):
			print("  ", m3.get_path(), " pos=", m3.global_position, " aabb=", m3.global_transform * m3.get_aabb())
	print("=== dogs ===")
	for n in level.find_children("*", "MeshInstance3D", true, false):
		var mi2: MeshInstance3D = n as MeshInstance3D
		if str(mi2.name).begins_with("FixedDog") or str(mi2.name).begins_with("CarriageDog"):
			print("  ", mi2.name, " pos=", mi2.global_position)
	quit()

