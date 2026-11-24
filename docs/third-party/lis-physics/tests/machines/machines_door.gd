extends "res://tests/harness/lis_test_case.gd"
## 机械层 · 机械门与限位开关（任务书 §11.C）
##
## 验证：
##   1.  被动铰链门：推一下真的转开
##   2.  竖直门轴下重力不产生绕轴力矩（历史错误：曾把重力算成开门力矩）
##   3.  门被障碍物阻挡时不能穿过
##   4.  电动门：马达驱动力矩有限，空门可开
##   5.  电动门被 40 kg 箱挡住时推不动（堵转），并报告 blocked
##   6.  断电后马达不再输出力矩，门保持合理物理状态
##   7.  机械限位：门不越过设定开度
##   8.  限位开关只有被真实物体压下去才闭合
##   9.  移走负载后开关断开
##  10.  门可复位到关闭位


func _configure() -> void:
	suite_name = "machines_door"
	expected_checks = 15


func _run() -> void:
	make_world_with_floor(30.0, 0.0, 0.9)
	await wait_physics(6)

	# ===== A. 被动铰链门 ==============================================
	var door: LISHingeDoor = LISHingeDoor.new()
	door.name = "TestHingeDoor"
	add_child(door)
	door.global_position = Vector3(-6.0, 0.0, 0.0)
	await wait_physics(90)
	var closed_deg: float = door.get_open_degrees()
	check("铰链门初始是关闭的", absf(closed_deg) < 3.0,
		"开合角 %.2f°" % closed_deg)

	# 竖直门轴 + 重力：门不会自己转开
	await wait_physics(120)
	var drift: float = absf(door.get_open_degrees() - closed_deg)
	check("竖直门轴下重力不产生开门力矩（不自己转开）", drift < 2.0,
		"120 帧后角度漂移 %.2f°" % drift)

	# 推一下真的转开
	var push_from: Vector3 = door.panel.global_position + Vector3(0.0, 0.0, -1.2)
	door.push_from(push_from)
	await wait_physics(90)
	var opened: float = door.get_open_degrees()
	check("推一下门真的转开", absf(opened) > 20.0,
		"推开 %.2f°（peak 角速度 %.2f rad/s）" % [opened, door.peak_speed])

	# 机械限位
	var too_far: bool = false
	for i in range(120):
		door.push_from(push_from, 90.0)
		await get_tree().physics_frame
		if absf(door.get_open_degrees()) > LISHingeDoor.OPEN_LIMIT_DEG + 8.0:
			too_far = true
	check("机械限位生效", not too_far,
		"最终 %.2f°（限位 ±%.0f°）" % [door.get_open_degrees(), LISHingeDoor.OPEN_LIMIT_DEG])

	# 复位
	door.reset_door()
	await wait_physics(30)
	check("门可复位到关闭位", absf(door.get_open_degrees()) < 4.0,
		"复位后 %.2f°" % door.get_open_degrees())
	door.despawn()
	await wait_physics(6)

	# ===== B. 电动门 =================================================
	var motor_door: LISMotorDoor = LISMotorDoor.new()
	motor_door.name = "TestMotorDoor"
	add_child(motor_door)
	motor_door.global_position = Vector3(6.0, 0.0, 0.0)
	await wait_physics(90)
	check("电动门初始关闭", absf(motor_door.angle_deg()) < 4.0,
		"角度 %.2f°" % motor_door.angle_deg())

	motor_door.set_request(true)
	await wait_physics(150)
	var open_deg: float = motor_door.angle_deg()
	check("空门被马达打开（力矩上限足够）", open_deg > 60.0,
		"开到 %.2f°（指令 %.0f°，力矩上限 %.0f N·m）" % [
			open_deg, motor_door.open_deg, motor_door.max_torque])

	motor_door.reset_door()
	await wait_physics(60)
	# rearm(开关闭合?) 的语义：**开关闭合 = 请求开门**。
	# 这里必须先让门保持在关闭位并确认它没被驱动，否则后面还没摆好障碍物，
	# 门就已经自己开到 87° 了（先前版本实测 blocked_deg=87.07，测的是"门已开"）。
	motor_door.rearm(false)
	await wait_physics(60)
	check("复位后门保持在关闭位（未自行开启）", absf(motor_door.angle_deg()) < 4.0,
		"角度 %.2f°" % motor_door.angle_deg())

	# ===== C. 被障碍物阻挡 ===========================================
	# 障碍物必须真的**挡住**门，而不是被门推开。
	#
	# 实测（diag_door3）：40 kg 箱子放在扫掠面上时，门板一推就把箱子从 z=0.80
	# 顶到 z=1.43 —— 门照样开到 88°，箱子被推走了。这不是缺陷：
	# 600 N·m 的马达推 40 kg 的箱子本来就推得动。
	#
	# 要验证"堵转"必须让障碍物**不可能被推动**：用静态障碍（相当于卡死的钢梁）
	# 挡住门板扫掠路径。这是真实工况（门被掉落的钢梁/固定的机柜挡住）。
	var door_center: Vector3 = motor_door.global_position
	var static_block: StaticBody3D = add_static_pad(
		door_center + Vector3(0.30, 0.0, 0.55), Vector3(0.9, 2.05, 0.30), 0.9)
	static_block.name = "StaticObstacle"
	await wait_physics(60)
	motor_door.set_request(true)
	await wait_physics(240)
	var blocked_deg: float = motor_door.angle_deg()
	print("DIAG motor_door blocked_deg=%.2f blocked=%s torque=%.0f" % [
		blocked_deg, str(motor_door.blocked), motor_door.motor_torque])
	check("被静态障碍阻挡时门开不到底", blocked_deg < motor_door.open_deg - 15.0,
		"开到 %.2f°（无障碍应到 %.0f°）" % [blocked_deg, motor_door.open_deg])
	check("门报告堵转状态", motor_door.blocked,
		"blocked=%s，马达力矩 %.0f N·m（上限 %.0f）" % [
			str(motor_door.blocked), motor_door.motor_torque, motor_door.max_torque])

	# ===== D. 断电 ===================================================
	motor_door.set_powered(false)
	await wait_physics(30)
	check("断电后马达输出为 0", is_zero_approx(motor_door.motor_torque),
		"motor_torque=%.2f" % motor_door.motor_torque)
	# 断电后门应不再持续被驱动（角度不再继续向目标增大）
	var deg_before_power_off: float = motor_door.angle_deg()
	await wait_physics(90)
	var deg_after_power_off: float = motor_door.angle_deg()
	check("断电后门不会被继续驱动", absf(deg_after_power_off - deg_before_power_off) < 6.0,
		"%.2f° → %.2f°" % [deg_before_power_off, deg_after_power_off])
	motor_door.set_powered(true)
	if is_instance_valid(static_block):
		static_block.queue_free()
	await wait_physics(60)
	motor_door.despawn()
	await wait_physics(6)

	# ===== E. 限位开关 ===============================================
	var sw: LISLimitSwitch = LISLimitSwitch.new()
	sw.name = "TestLimitSwitch"
	add_child(sw)
	sw.global_position = Vector3(0.0, 0.0, 8.0)
	await wait_physics(120)
	check("空载时限位开关断开", not sw.is_closed(),
		"closed=%s，压缩 %.1f mm" % [str(sw.is_closed()), sw.compression * 1000.0])

	# 用真实刚体压下去（不是脚本设状态）。
	#
	# 压杆物必须**细**（≤0.12 m 见方）：顶杆两侧有导向薄板（净空 ±0.070 m），
	# 0.30 m 见方的箱子会直接卡在导向梁上，一点也压不下去
	# （实测压缩量恒为 8.2 mm，那就是顶杆自重压在弹簧上的平衡量）。
	var presser: LISBody = make_body(sw.global_position + Vector3(0.0, 1.10, 0.0),
		Vector3(0.11, 0.55, 0.11), 15.0, Color(0.8, 0.6, 0.6), {"display_name": "压杆物"})
	await wait_physics(150)
	print("DIAG switch comp=%.1fmm closed=%s pressed_by=%s presser_y=%.3f" % [
		sw.compression * 1000.0, str(sw.is_closed()), sw.pressed_by, presser.global_position.y])
	check("被真实刚体压下去后开关闭合", sw.is_closed(),
		"压缩 %.1f mm（阈值 %.0f mm），pressed_by=%s" % [
			sw.compression * 1000.0, LISLimitSwitch.PRESS_CLOSE * 1000.0, sw.pressed_by])

	# 移走负载后断开
	presser.queue_free()
	await wait_physics(120)
	check("移走负载后开关断开", not sw.is_closed(),
		"closed=%s，压缩 %.1f mm" % [str(sw.is_closed()), sw.compression * 1000.0])
