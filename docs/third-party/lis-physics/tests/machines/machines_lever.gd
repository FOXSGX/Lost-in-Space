extends "res://tests/harness/lis_test_case.gd"
## 机械层 · 真实杠杆与配重（任务书 §11.B）
##
## 验证"力矩真的由质量与力臂决定"：
##   1.  支点是真实铰链（不是脚本写角度）
##   2.  空载时停在平衡角（配重把载物端抬起）
##   3.  阈值以下的货物压不动
##   4.  阈值以上的货物能压动
##   5.  同一质量放在不同力臂上产生不同结果
##   6.  两个物体组合起来能压动（力矩叠加）
##   7.  直接推动杠杆也能让它动
##   8.  移走配重后自然回转
##   9.  机械限位真的存在（角度不超限）
##  10.  复位后回到初始角度


func _configure() -> void:
	suite_name = "machines_lever"
	expected_checks = 11


func _run() -> void:
	make_world_with_floor(30.0, 0.0, 0.9)
	await wait_physics(6)

	var lever: LISLever = LISLever.new()
	lever.name = "TestLever"
	add_child(lever)
	lever.global_position = Vector3(0.0, LISLever.PIVOT_HEIGHT, 0.0)
	await wait_physics(120)

	# --- 1) 支点是真实铰链 ---------------------------------------------
	check("支点是真实铰链且接线有效", lever.hinge != null and LISJointKit.is_wired(lever.hinge),
		"hinge=%s" % ("ok" if lever.hinge != null else "null"))

	# --- 2) 空载平衡角 ------------------------------------------------
	var rest_angle: float = lever.angle_deg()
	check("空载停在平衡角（载物端抬起 ≈ +14°）", rest_angle > 8.0 and rest_angle <= 14.5,
		"平衡角 %.2f°（机械限位 ±14°）" % rest_angle)

	# --- 3) 阈值以下：12 kg 压不动 -------------------------------------
	var light: LISBody = make_body(lever.pan_world() + Vector3(0.0, 0.45, 0.0),
		Vector3(0.5, 0.5, 0.5), 12.0, Color(0.6, 0.8, 0.6), {"display_name": "12kg 货"})
	await wait_physics(120)
	var angle_light: float = lever.angle_deg()
	print("DIAG lever rest=%.2f after12=%.2f pan_load=%.1f" % [
		rest_angle, angle_light, lever.pan_load_kg])
	check("12 kg 压不动杠杆（角度基本不变）", absf(angle_light - rest_angle) < 6.0,
		"%.2f° → %.2f°" % [rest_angle, angle_light])
	check("载物台测得真实负载 12 kg", absf(lever.pan_load_kg - 12.0) < 1.0,
		"pan_load=%.1f kg" % lever.pan_load_kg)

	# --- 4) 阈值以上：24 kg 放到远端能压动 ----------------------------
	light.queue_free()
	await wait_physics(80)
	var heavy24: LISBody = make_body(lever.pan_world() + Vector3(0.0, 0.5, 0.32),
		Vector3(0.55, 0.55, 0.55), 24.0, Color(0.8, 0.6, 0.4), {"display_name": "24kg 远货"})
	await wait_physics(150)
	var angle_heavy: float = lever.angle_deg()
	print("DIAG lever after24far=%.2f load=%.1f gravity_t=%.1f load_t=%.1f" % [
		angle_heavy, lever.pan_load_kg, lever.gravity_torque(), lever.load_torque(lever.pan_cargo())])
	check("24 kg 放在远端能压下杠杆", angle_heavy < rest_angle - 4.0,
		"%.2f° → %.2f°" % [rest_angle, angle_heavy])

	# --- 5) 力臂差异：同样的 24 kg 放在近端压不动 ---------------------
	heavy24.queue_free()
	await wait_physics(80)
	var near24: LISBody = make_body(lever.pan_world() + Vector3(0.0, 0.5, -0.55),
		Vector3(0.55, 0.55, 0.55), 24.0, Color(0.6, 0.6, 0.9), {"display_name": "24kg 近货"})
	await wait_physics(150)
	var angle_near: float = lever.angle_deg()
	var arm_far: float = lever.arm_length(lever.pan_world() + Vector3(0.0, 0.0, 0.32))
	var arm_near: float = lever.arm_length(lever.pan_world() + Vector3(0.0, 0.0, -0.55))
	print("DIAG lever near24=%.2f arm_far=%.2f arm_near=%.2f" % [
		angle_near, arm_far, arm_near])
	check("力臂更短时同一质量压不下去", angle_near > angle_heavy + 3.0,
		"远端 %.2f° vs 近端 %.2f°（力臂 %.2f m vs %.2f m）" % [
			angle_heavy, angle_near, arm_far, arm_near])

	# --- 6) 两个物体组合施力 -------------------------------------------
	near24.queue_free()
	await wait_physics(80)
	var a12: LISBody = make_body(lever.pan_world() + Vector3(-0.16, 0.5, 0.10),
		Vector3(0.45, 0.45, 0.45), 12.0, Color(0.9, 0.8, 0.5), {"display_name": "12kg-a"})
	var b12: LISBody = make_body(lever.pan_world() + Vector3(0.16, 0.5, 0.10),
		Vector3(0.45, 0.45, 0.45), 12.0, Color(0.9, 0.6, 0.7), {"display_name": "12kg-b"})
	await wait_physics(150)
	var angle_sum: float = lever.angle_deg()
	print("DIAG lever two12=%.2f load=%.1f" % [angle_sum, lever.pan_load_kg])
	check("两个 12 kg 组合起来压得动", angle_sum < rest_angle - 3.0 and lever.pan_load_kg > 20.0,
		"%.2f° → %.2f°（实测负载 %.0f kg）" % [rest_angle, angle_sum, lever.pan_load_kg])

	# --- 7) 直接推动杠杆 -----------------------------------------------
	a12.queue_free()
	b12.queue_free()
	await wait_physics(120)
	lever.reset_lever()
	await wait_physics(60)
	var before_push: float = lever.angle_deg()
	# 在载物端施加向下的力
	for i in range(60):
		lever.push_force(Vector3(0.0, -420.0, 0.0), lever.global_transform.basis.z * 1.2)
		await get_tree().physics_frame
	var after_push: float = lever.angle_deg()
	check("直接推动杠杆端部能让它转", after_push < before_push - 2.0,
		"%.2f° → %.2f°（在 1.2 m 力臂上施加 420 N）" % [before_push, after_push])

	# --- 8) 移走货物后自然回转 -----------------------------------------
	lever.reset_lever()
	await wait_physics(120)
	var back_angle: float = lever.angle_deg()
	check("复位后回到平衡角", absf(back_angle - rest_angle) < 3.0,
		"复位后 %.2f°（初始平衡 %.2f°）" % [back_angle, rest_angle])

	# --- 9) 机械限位 ---------------------------------------------------
	var over: bool = false
	for i in range(90):
		lever.push_force(Vector3(0.0, -900.0, 0.0), lever.global_transform.basis.z * 1.5)
		await get_tree().physics_frame
		if lever.angle_deg() < -LISLever.LIMIT_DEG - 1.0:
			over = true
	check("机械限位生效（角度不越过 −14°）", not over,
		"最终角度 %.2f°（限位 ±%.0f°）" % [lever.angle_deg(), LISLever.LIMIT_DEG])

	# --- 10) 销毁不留悬空关节 ------------------------------------------
	var hinge_ref: HingeJoint3D = lever.hinge
	lever.despawn()
	await wait_physics(6)
	check("销汇后铰链被释放", not is_instance_valid(lever) or not is_instance_valid(hinge_ref),
		"lever 有效=%s · hinge 有效=%s" % [
			str(is_instance_valid(lever)), str(is_instance_valid(hinge_ref))])
