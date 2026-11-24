extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：推车的落地高度、轮子接触与地面几何
## 只打印读数（expected_checks = 0 → 记为 RAN）。


func _configure() -> void:
	suite_name = "diag_cart"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(40.0, 0.0, 0.85)
	await wait_physics(6)
	var pad: StaticBody3D = add_static_pad(Vector3(0.0, 0.0, 0.0), Vector3(24, 0.3, 24), 0.85)
	pad.name = "Plaza"
	await wait_physics(6)
	print("DIAG plaza_top_y=%.3f plaza_transform=%s" % [
		pad.global_transform.origin.y + 0.15, str(pad.global_transform.origin)])
	print("DIAG floor_top=%.3f" % surface_point_at(0.0, 0.0).y)

	var cart: LISCart = LISCart.new()
	cart.name = "TestCart"
	add_child(cart)
	cart.global_position = Vector3(0.0, 1.6, 0.0)
	await wait_physics(60)
	print("DIAG cart_y=%.3f wheels=%d grounded=%d" % [
		cart.global_position.y, cart.wheel_bodies.size(), cart.grounded_wheel_count()])
	for i in range(cart.wheel_bodies.size()):
		var w: RigidBody3D = cart.wheel_bodies[i]
		print("DIAG wheel[%d] %s pos=%s contacts=%d local=%s" % [
			i, w.name, str(w.global_position), w.get_contact_count(),
			str(cart.wheel_local[i])])
	print("DIAG chassis contacts=%d resting=%s" % [
		cart.get_contact_count(), str(cart.sleeping)])
	for c: Dictionary in LISContactProbe.contacts_of(cart):
		print("DIAG chassis contact with %s at %s" % [
			str(c.get("name", "?")), str(c.get("position", Vector3.ZERO))])
	# 静态射线：轮心正下方
	for i in range(cart.wheel_bodies.size()):
		var w: RigidBody3D = cart.wheel_bodies[i]
		var p: Vector3 = surface_point_at(w.global_position.x, w.global_position.z)
		print("DIAG ray under wheel[%d] -> y=%.3f (wheel y=%.3f, diff=%.3f)" % [
			i, p.y, w.global_position.y, w.global_position.y - p.y])
