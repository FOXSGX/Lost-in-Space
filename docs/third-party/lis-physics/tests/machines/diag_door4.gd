extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：静态障碍是否真的挡住门板扫掠面
## 只打印读数（expected_checks = 0 → 记为 RAN）。


func _configure() -> void:
	suite_name = "diag_door4"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(30.0, 0.0, 0.9)
	await wait_physics(6)
	var md: LISMotorDoor = LISMotorDoor.new()
	md.name = "MD"
	add_child(md)
	md.global_position = Vector3(0.0, 0.0, 0.0)
	await wait_physics(60)

	var door_center: Vector3 = md.global_position
	var pad: StaticBody3D = add_static_pad(
		door_center + Vector3(0.30, 0.0, 0.55), Vector3(0.9, 2.05, 0.30), 0.9)
	pad.name = "StaticObstacle"
	await wait_physics(30)
	var pad_size: Vector3 = LISContactProbe.shape_size(pad)
	print("DIAG pad_center=%s size=%s layer=%d mask=%d" % [
		str(pad.global_position), str(pad_size), pad.collision_layer, pad.collision_mask])
	print("DIAG pad_x=[%.2f,%.2f] z=[%.2f,%.2f] y=[%.2f,%.2f]" % [
		pad.global_position.x - pad_size.x * 0.5, pad.global_position.x + pad_size.x * 0.5,
		pad.global_position.z - pad_size.z * 0.5, pad.global_position.z + pad_size.z * 0.5,
		pad.global_position.y - pad_size.y * 0.5, pad.global_position.y + pad_size.y * 0.5])
	print("DIAG panel_layer=%d panel_mask=%d" % [md.panel.collision_layer, md.panel.collision_mask])
	print("DIAG hinge_global=%s" % str(md.hinge.global_position))

	md.set_request(true)
	var first_overlap: float = -1.0
	for i in range(40):
		await wait_physics(6)
		var d: float = LISContactProbe.sat_depth(
			LISContactProbe.box_obb(md.panel), LISContactProbe.box_obb(pad))
		if d > 0.0005 and first_overlap < 0.0:
			first_overlap = md.angle_deg()
		if i % 4 == 0:
			print("DIAG i=%d angle=%.1f sat=%.4f panel=%s contacts=%d torque=%.0f" % [
				i, md.angle_deg(), d, str(md.panel.global_position),
				md.panel.get_contact_count(), md.motor_torque])
	print("DIAG first_overlap_angle=%.1f final_angle=%.1f" % [first_overlap, md.angle_deg()])
