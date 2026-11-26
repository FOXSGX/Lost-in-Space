extends "res://tests/test_cart_interactions.gd"

# Camera-overlap diagnostic at the point the m23 regression flagged.
# Reports which body the camera sphere actually intersects, by name and layer.

func run() -> void:
	await boot()
	await travel(Vector3(1, 0, 1.55))
	await frames(30)
	await start_from_console()
	for _i: int in range(3600):
		await frames(1)
		if float(cart.get("distance")) >= 48.0:
			break
	await frames(30)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for _i: int in range(240):
		await frames(1)
		if not bool(player.call("camera_overlap")):
			continue
		var camera: Camera3D = player.get("camera") as Camera3D
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = 0.24
		query.shape = sphere
		query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
		query.collision_mask = 4
		var hits: Array[Dictionary] = space.intersect_shape(query, 4)
		var names: Array[String] = []
		for hit: Dictionary in hits:
			var collider: Object = hit["collider"] as Object
			names.append("%s(layer=%d)" % [str(collider), (collider as CollisionObject3D).collision_layer])
		print("OVERLAP dist=%.2f camera=%s hits=%s" % [float(cart.get("distance")), camera.global_position, ", ".join(names)])
		break
	print("CAMERA_OVERLAP_PROBE_DONE")
	finish_probe()

func finish_probe() -> void:
	stop()
	scene = null
	current_scene = null
	app.queue_free()
	await frames(4)
	quit(0)
