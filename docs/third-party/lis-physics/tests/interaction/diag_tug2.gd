extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：反向拉扯过程中的松手动因
## 只打印读数（expected_checks = 0 → 记为 RAN）。


func _configure() -> void:
	suite_name = "diag_tug2"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(20.0, 0.0, 0.9)
	await wait_physics(6)
	var tug: LISBody = make_body(Vector3(0.0, 0.31, -12.0), Vector3(3.0, 0.4, 0.4), 30.0,
		Color(0.8, 0.5, 0.8), {"display_name": "横杆", "liftable": true})
	await wait_physics(40)
	var left: LISFirstPersonAdapter = make_avatar(Vector3(-3.0, 0.85, -12.0),
		Vector3(1.0, -0.15, 0.0).normalized(), 30, "L")
	var right: LISFirstPersonAdapter = make_avatar(Vector3(3.0, 0.85, -12.0),
		Vector3(-1.0, -0.15, 0.0).normalized(), 31, "R")
	await wait_physics(6)
	left.grab(tug)
	right.grab(tug)
	await wait_physics(6)
	left.grabber.grip_slipped.connect(func(r: String) -> void:
		print("DIAG SLIP L reason=%s frame_force=%.1f clamp=%.3f" % [
			r, left.grabber.last_force, left.grabber.last_clamp_distance]))
	right.grabber.grip_slipped.connect(func(r: String) -> void:
		print("DIAG SLIP R reason=%s frame_force=%.1f clamp=%.3f" % [
			r, right.grabber.last_force, right.grabber.last_clamp_distance]))
	for i in range(100):
		aim_avatar(left, Vector3(-3.0, 0.85, -12.0 - float(i) * 0.010),
			Vector3(-3.0, 0.85, -14.0))
		aim_avatar(right, Vector3(3.0, 0.85, -12.0 + float(i) * 0.010),
			Vector3(3.0, 0.85, -10.0))
		await get_tree().physics_frame
		if i % 8 == 0:
			print("DIAG i=%d holders=%d heldL=%s heldR=%s clampL=%.2f clampR=%.2f mode=%s forceL=%.0f forceR=%.0f" % [
				i, tug.holder_count(), str(left.is_holding()), str(right.is_holding()),
				left.grabber.last_clamp_distance, right.grabber.last_clamp_distance,
				left.grabber.mode, left.grabber.last_force, right.grabber.last_force])
