extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var body: AnimatableBody3D = AnimatableBody3D.new()
	root.add_child(body)
	body.position = Vector3(1, 2, 3)
	print("A position=", body.position, " global=", body.global_position, " sync=", body.sync_to_physics)
	body.position.y = 5.0
	print("B position=", body.position)
	body.global_position = Vector3(4, 5, 6)
	print("C position=", body.position, " global=", body.global_position)
	await physics_frame
	print("D position=", body.position, " global=", body.global_position)
	var sb: StaticBody3D = StaticBody3D.new()
	root.add_child(sb)
	sb.position = Vector3(7, 8, 9)
	print("S position=", sb.position)
	quit()
