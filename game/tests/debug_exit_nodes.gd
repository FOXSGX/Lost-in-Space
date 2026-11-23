extends SceneTree

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
	for n in level.find_children("Exit*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		print("NODE %s  pos=%s  aabb=%s  vis=%s" % [mi.get_path(), mi.global_position, box, mi.is_visible_in_tree()])
	quit()
