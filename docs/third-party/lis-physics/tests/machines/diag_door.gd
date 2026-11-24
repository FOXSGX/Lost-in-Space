extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：电动门被阻挡与限位开关受压的几何
## 只打印读数（expected_checks = 0 → 记为 RAN）。


func _configure() -> void:
	suite_name = "diag_door"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(30.0, 0.0, 0.9)
	await wait_physics(6)

	var md: LISMotorDoor = LISMotorDoor.new()
	md.name = "MD"
	add_child(md)
	md.global_position = Vector3(6.0, 0.0, 0.0)
	await wait_physics(60)
	print("DIAG door_origin=%s panel=%s hinge=%s" % [
		str(md.global_position), str(md.panel.global_position), str(md.hinge.global_position)])
	# 门板尺寸 1.28 × 2.05 × 0.08；铰链在局部 x=-0.64
	print("DIAG panel extents: half_x=0.64 half_z=0.04")

	# 在门板正前方 0.3 m 处放一个 40 kg 箱子（门开时会撞到）
	var bp: Vector3 = md.global_position + Vector3(0.1, 0.31, -0.45)
	print("DIAG blocker at %s" % str(bp))
	var blocker: LISBody = make_body(bp, Vector3(0.5, 0.6, 0.5), 40.0,
		Color(0.7, 0.6, 0.4), {"display_name": "挡门箱"})
	await wait_physics(60)
	md.set_request(true)
	for i in range(240):
		await get_tree().physics_frame
		if i % 40 == 0:
			print("DIAG i=%d angle=%.2f blocked=%s torque=%.0f blocker_pos=%s" % [
				i, md.angle_deg(), str(md.blocked), md.motor_torque,
				str(blocker.global_position)])
	print("DIAG final angle=%.2f blocked=%s" % [md.angle_deg(), str(md.blocked)])

	# ---- 开关几何 ----
	var sw: LISLimitSwitch = LISLimitSwitch.new()
	sw.name = "SW"
	add_child(sw)
	sw.global_position = Vector3(0.0, 0.0, 8.0)
	await wait_physics(60)
	print("DIAG switch origin=%s plunger=%s rest_y=%.2f plunger_top=%.2f" % [
		str(sw.global_position), str(sw.plunger.global_position), sw.rest_y,
		sw.plunger.global_position.y + 0.13])
	# 压杆物必须落在顶杆（0.13 × 0.26 × 0.13）正上方
	var pp: Vector3 = sw.global_position + Vector3(0.0, sw.rest_y + 0.13 + 0.16, 0.0)
	print("DIAG presser at %s" % str(pp))
	var presser: LISBody = make_body(pp, Vector3(0.30, 0.30, 0.30), 15.0,
		Color(0.8, 0.6, 0.6), {"display_name": "压杆物"})
	for i in range(120):
		await get_tree().physics_frame
		if i % 20 == 0:
			print("DIAG i=%d presser_y=%.3f comp=%.1fmm closed=%s by=%s plunger_y=%.3f" % [
				i, presser.global_position.y, sw.compression * 1000.0,
				str(sw.is_closed()), sw.pressed_by, sw.plunger.global_position.y])
