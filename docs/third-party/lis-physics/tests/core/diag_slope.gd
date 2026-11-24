extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：静态坡道的碰撞与射线取样是否一致
## 只打印读数，不做断言（expected_checks = 0 → 运行器记为 RAN 而不是 PASS）。


func _configure() -> void:
	suite_name = "diag_slope"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(24.0)
	await wait_physics(4)
	var slope: StaticBody3D = add_static_pad(Vector3(0.0, 0.0, -6.0), Vector3(6.0, 0.30, 6.0), 0.85)
	slope.rotation_degrees = Vector3(16.0, 0.0, 0.0)
	await wait_physics(6)
	print("DIAG slope_xform=%s" % str(slope.global_transform))
	print("DIAG slope_layer=%d mask=%d children=%d" % [
		slope.collision_layer, slope.collision_mask, slope.get_child_count()])
	for z: float in [-8.5, -7.0, -6.0, -4.6, -4.0]:
		var p: Vector3 = surface_point_at(0.0, z)
		print("DIAG ray x=0 z=%.1f -> %s" % [z, str(p)])
	var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.2, 0.2, 0.2)
	q.shape = box
	q.collision_mask = LISPhysics.LAYER_WORLD
	q.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, -4.6))
	var hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(q, 8)
	print("DIAG shape_query_hits=%d" % hits.size())
	for h: Dictionary in hits:
		var c: Object = h.get("collider")
		var n: Node = c as Node
		print("DIAG   hit=%s" % (str(n.name) if n != null else "?"))
	var direct: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	direct.from = Vector3(0.0, 12.0, -4.6)
	direct.to = Vector3(0.0, -10.0, -4.6)
	direct.collision_mask = 0xFFFFFFFF
	direct.hit_from_inside = true
	var r: Dictionary = get_world_3d().direct_space_state.intersect_ray(direct)
	print("DIAG all-mask ray -> %s" % str(r))
