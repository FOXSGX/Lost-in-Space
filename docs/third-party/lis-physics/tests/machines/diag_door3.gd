extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：门板与挡门箱在扫掠过程中的真实重叠
## 只打印读数（expected_checks = 0 → 记为 RAN）。


func _configure() -> void:
	suite_name = "diag_door3"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(30.0, 0.0, 0.9)
	await wait_physics(6)
	var md: LISMotorDoor = LISMotorDoor.new()
	md.name = "MD"
	add_child(md)
	md.global_position = Vector3(0.0, 0.0, 0.0)
	await wait_physics(60)
	# 箱子放在 +Z 侧半径 1.0 m 处
	var blocker: LISBody = make_body(Vector3(0.40, 0.61, 0.80),
		Vector3(0.55, 1.2, 0.55), 40.0, Color(0.7, 0.6, 0.4), {"display_name": "挡门箱"})
	await wait_physics(90)
	print("DIAG blocker=%s" % str(blocker.global_position))
	print("DIAG panel mass=%.0f layer=%d mask=%d shape=%s" % [
		md.panel.mass, md.panel.collision_layer, md.panel.collision_mask,
		str(LISContactProbe.shape_size(md.panel))])
	print("DIAG blocker layer=%d mask=%d shape=%s" % [
		blocker.collision_layer, blocker.collision_mask, str(blocker.size())])
	var obb_panel: Dictionary = LISContactProbe.box_obb(md.panel)
	var obb_box: Dictionary = LISContactProbe.box_obb(blocker)
	print("DIAG sat_depth(initial)=%.3f" % LISContactProbe.sat_depth(obb_panel, obb_box))
	md.set_request(true)
	var min_gap_angle: float = -1.0
	for i in range(12):
		await wait_physics(20)
		var d: float = LISContactProbe.sat_depth(
			LISContactProbe.box_obb(md.panel), LISContactProbe.box_obb(blocker))
		print("DIAG i=%d angle=%.1f sat=%.3f panel=%s box=%s contactsP=%d contactsB=%d" % [
			i, md.angle_deg(), d, str(md.panel.global_position),
			str(blocker.global_position), md.panel.get_contact_count(), blocker.get_contact_count()])
		if d > 0.0 and min_gap_angle < 0.0:
			min_gap_angle = md.angle_deg()
	print("DIAG overlap_first_at_angle=%.1f" % min_gap_angle)
