extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var app: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(120):
		await physics_frame
	var level: LevelBuilder = app.get("level") as LevelBuilder
	var point: Vector3 = Vector3(4.2, 1.72, 5.78)
	print("--- shapes within 4m of ", point, " ---")
	for body in level.find_children("*", "StaticBody3D", true, false):
		var sb: StaticBody3D = body as StaticBody3D
		for child in sb.get_children():
			if child is CollisionShape3D:
				var cs: CollisionShape3D = child as CollisionShape3D
				var gp: Vector3 = cs.global_position
				if gp.distance_to(point) < 4.0:
					var shape: Shape3D = cs.shape
					var extra: String = ""
					if shape is BoxShape3D:
						extra = "box " + str((shape as BoxShape3D).size)
					elif shape is CylinderShape3D:
						extra = "cyl r=" + str((shape as CylinderShape3D).radius) + " h=" + str((shape as CylinderShape3D).height)
					elif shape is ConcavePolygonShape3D:
						extra = "trimesh"
					print(sb.get_parent().name, "/", sb.name, " ", gp, " ", extra, " path=", cs.get_path())
	print("--- end ---")
	quit()
