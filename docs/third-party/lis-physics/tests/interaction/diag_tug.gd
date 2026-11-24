extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：反向拉扯为何没有产生偏航
## 只打印读数，不做断言（expected_checks = 0 → 记为 RAN）。


func _configure() -> void:
	suite_name = "diag_tug"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(20.0, 0.0, 0.9)
	await wait_physics(6)
	var tug: LISBody = make_body(Vector3(0.0, 0.31, -12.0), Vector3(3.0, 0.4, 0.4), 30.0,
		Color(0.8, 0.5, 0.8), {"display_name": "横杆", "liftable": true})
	await wait_physics(40)
	print("DIAG tug_rest pos=%s rot=%s" % [str(tug.global_position), str(tug.rotation)])
	var left: LISFirstPersonAdapter = make_avatar(Vector3(-3.4, 0.85, -12.0),
		Vector3(1.0, -0.15, 0.0).normalized(), 30, "L")
	var right: LISFirstPersonAdapter = make_avatar(Vector3(3.4, 0.85, -12.0),
		Vector3(-1.0, -0.15, 0.0).normalized(), 31, "R")
	await wait_physics(6)
	print("DIAG grabL=%s grabR=%s" % [str(left.grab(tug)), str(right.grab(tug))])
	await wait_physics(6)
	print("DIAG holders=%d modeL=%s modeR=%s" % [tug.holder_count(),
		left.grabber.mode, right.grabber.mode])
	print("DIAG gripL=%s gripR=%s localL=%s localR=%s" % [
		str(left.grabber.grip_world()), str(right.grabber.grip_world()),
		str(tug.to_local(left.grabber.grip_world())), str(tug.to_local(right.grabber.grip_world()))])
	for i in range(90):
		aim_avatar(left, Vector3(-3.4 - float(i) * 0.010, 0.85, -12.0), Vector3(-1.5, 0.5, -12.0))
		aim_avatar(right, Vector3(3.4 + float(i) * 0.010, 0.85, -12.0), Vector3(1.5, 0.5, -12.0))
		await get_tree().physics_frame
		if i % 15 == 0:
			print("DIAG i=%d yaw=%.4f omega_y=%.4f forceL=%.1f forceR=%.1f slipL=%.2f slipR=%.2f held=%s/%s" % [
				i, tug.rotation.y, tug.angular_velocity.y,
				left.grabber.last_force, right.grabber.last_force,
				left.grabber.last_clamp_distance, right.grabber.last_clamp_distance,
				str(left.is_holding()), str(right.is_holding())])
	print("DIAG final yaw=%.4f tilt=%.3f" % [tug.rotation.y,
		rad_to_deg(acos(clampf(tug.global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))])
