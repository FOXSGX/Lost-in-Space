extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：电动门开合过程中门板的真实扫掠位置
## 只打印读数（expected_checks = 0 → 记为 RAN）。


func _configure() -> void:
	suite_name = "diag_door2"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(30.0, 0.0, 0.9)
	await wait_physics(6)
	var md: LISMotorDoor = LISMotorDoor.new()
	md.name = "MD"
	add_child(md)
	md.global_position = Vector3(0.0, 0.0, 0.0)
	await wait_physics(60)
	print("DIAG door origin=%s" % str(md.global_position))
	print("DIAG panel_center=%s panel_size(1.28,2.05,0.08) hinge=%s" % [
		str(md.panel.global_position), str(md.hinge.global_position)])
	print("DIAG floor_to_panel_bottom=%.3f" % (md.panel.global_position.y - 2.05 * 0.5))
	md.set_request(true)
	for i in range(10):
		await wait_physics(20)
		var p: Vector3 = md.panel.global_position
		var fwd: Vector3 = md.panel.global_transform.basis.x
		print("DIAG i=%d angle=%.1f panel=%s panel_x_axis=%s tip=%s" % [
			i, md.angle_deg(), str(p), str(fwd), str(p + fwd * 0.64)])
