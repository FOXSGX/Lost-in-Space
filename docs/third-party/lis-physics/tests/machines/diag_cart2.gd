extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：推车的落地高度与接触（纯平地，无叠加平台）
## 只打印读数（expected_checks = 0 → 记为 RAN）。


func _configure() -> void:
	suite_name = "diag_cart2"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(60.0, 0.0, 0.85)
	await wait_physics(10)
	print("DIAG floor_top=%.3f" % surface_point_at(0.0, 0.0).y)

	var cart: LISCart = LISCart.new()
	cart.name = "TestCart"
	add_child(cart)
	cart.global_position = Vector3(0.0, 0.60, 0.0)
	for i in range(90):
		await get_tree().physics_frame
		if i % 15 == 0:
			print("DIAG f=%d cart_y=%.3f vel=%.3f sleeping=%s grounded=%d" % [
				i, cart.global_position.y, cart.linear_velocity.length(),
				str(cart.sleeping), cart.grounded_wheel_count()])
	print("DIAG final cart_y=%.3f chassis_contacts=%d" % [
		cart.global_position.y, cart.get_contact_count()])
	for i in range(cart.wheel_bodies.size()):
		var w: RigidBody3D = cart.wheel_bodies[i]
		print("DIAG wheel[%d] pos=%s contacts=%d sleeping=%s" % [
			i, str(w.global_position), w.get_contact_count(), str(w.sleeping)])
	# 地面射线
	for i in range(4):
		var w: RigidBody3D = cart.wheel_bodies[i]
		var p: Vector3 = surface_point_at(w.global_position.x, w.global_position.z)
		print("DIAG ray[%d] ground_y=%.3f wheel_y=%.3f gap=%.3f" % [
			i, p.y, w.global_position.y, w.global_position.y - p.y])
	# 推一下
	var z0: float = cart.global_position.z
	for i in range(60):
		cart.push_force_centered(Vector3(0.0, 0.0, -420.0))
		await get_tree().physics_frame
	print("DIAG after push dz=%.4f v=%.3f sleeping=%s" % [
		absf(cart.global_position.z - z0), cart.telemetry_forward_speed, str(cart.sleeping)])
	for i in range(cart.wheel_bodies.size()):
		print("DIAG wheel spin[%d]=%.4f" % [i, cart.wheel_spin_list()[i]])
