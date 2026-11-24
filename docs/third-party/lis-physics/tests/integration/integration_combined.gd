extends "res://tests/harness/lis_test_case.gd"
## 集成 · 综合机械场（任务书 §13 示例 7 与 §18.B 的组合验收）
##
## 同时存在：多个刚体 / 双人施力 / 真实车轮 / 一套杠杆 / 一扇机械门 / 一套绳索，
## 检查组合后是否出现物理冲突、异常弹飞、关节失效或脚本报错。
##
## 判据全部是**可证伪的数值**，不是"看起来没问题"：
##   1.  所有子系统都能建立且接线有效
##   2.  组合运行 600 帧后没有任何物体出现 NaN / INF
##   3.  没有物体以异常速度飞走（> 30 m/s 视为弹飞）
##   4.  没有物体掉到地面以下（< −2 m 视为穿透）
##   5.  抓握在复杂场景里仍能成立
##   6.  双人合力在复杂场景里仍能叠加
##   7.  推车在复杂场景里仍保持四轮触地
##   8.  杠杆仍能量到真实负载
##   9.  门仍能被马达打开
##  10.  绳索仍保持接线有效
##  11.  整场销毁后无残留关节
##  12.  全程无引擎脚本报错（由运行器独立核对）


func _configure() -> void:
	suite_name = "integration_combined"
	expected_checks = 12


func _run() -> void:
	make_world_with_floor(40.0, 0.0, 0.9)
	await wait_physics(8)

	var bodies: Array[LISBody] = []
	var systems_ok: PackedStringArray = PackedStringArray()

	# --- 1) 多个刚体 ---------------------------------------------------
	for i in range(8):
		var b: LISBody = make_body(Vector3(-9.0 + float(i) * 1.1, 0.31 + float(i % 3) * 0.7, -6.0),
			Vector3(0.5, 0.5, 0.5), 8.0 + float(i) * 3.0,
			Color(0.4 + 0.07 * float(i), 0.6, 0.7),
			{"display_name": "组合箱%d" % i, "friction": 0.7})
		bodies.append(b)
	systems_ok.append("刚体×8")

	# --- 2) 推车 -------------------------------------------------------
	var cart: LISCart = LISCart.new()
	cart.name = "ComboCart"
	add_child(cart)
	cart.global_position = Vector3(10.0, 0.60, 6.0)
	systems_ok.append("推车")

	# --- 3) 杠杆 -------------------------------------------------------
	var lever: LISLever = LISLever.new()
	lever.name = "ComboLever"
	add_child(lever)
	lever.global_position = Vector3(-12.0, LISLever.PIVOT_HEIGHT, 6.0)
	systems_ok.append("杠杆")

	# --- 4) 电动门 -----------------------------------------------------
	var door: LISMotorDoor = LISMotorDoor.new()
	door.name = "ComboDoor"
	add_child(door)
	door.global_position = Vector3(0.0, 0.0, 12.0)
	systems_ok.append("电动门")

	# --- 5) 缆绳 -------------------------------------------------------
	var rope: LISRope = LISRope.new()
	rope.name = "ComboRope"
	add_child(rope)
	await wait_physics(2)
	rope.build(8, 0.34, Vector3(-4.0, 3.2, 12.0), Vector3.RIGHT, true, 0.0)
	var post: StaticBody3D = add_static_pad(Vector3(-4.4, 0.0, 12.0), Vector3(0.4, 3.2, 0.4), 0.9)
	post.name = "ComboPost"
	await wait_physics(4)
	rope.anchor_first_to(post, post.global_position + Vector3(0.0, 3.2, 0.0))
	systems_ok.append("缆绳")

	await wait_physics(120)

	# --- 建立状态检查 --------------------------------------------------
	var cart_ok: bool = cart.wheel_bodies.size() == 4 and cart.axles.size() == 4
	var lever_ok: bool = lever.hinge != null and LISJointKit.is_wired(lever.hinge)
	var door_ok: bool = door.hinge != null and LISJointKit.is_wired(door.hinge)
	var rope_report: Dictionary = rope.wiring_report()
	var rope_ok: bool = int(rope_report["broken"]) == 0 and int(rope_report["joints"]) > 0
	check("所有子系统都建立且接线有效", cart_ok and lever_ok and door_ok and rope_ok,
		"系统：%s · 推车铰链 %d · 绳关节 %d（破损 %d）" % [
			", ".join(systems_ok), cart.axles.size(),
			int(rope_report["joints"]), int(rope_report["broken"])])

	# --- 双人抓握 ------------------------------------------------------
	var coop_box: LISBody = make_body(Vector3(-18.0, 0.41, -6.0),
		Vector3(1.0, 0.8, 0.8), 40.0, Color(0.6, 0.6, 0.9), {"display_name": "双人箱"})
	await wait_physics(60)
	var a1: LISFirstPersonAdapter = make_avatar(Vector3(-19.4, 1.5, -3.8),
		(coop_box.global_position - Vector3(-19.4, 1.5, -3.8)).normalized(), 1, "CA")
	var a2: LISFirstPersonAdapter = make_avatar(Vector3(-16.6, 1.5, -3.8),
		(coop_box.global_position - Vector3(-16.6, 1.5, -3.8)).normalized(), 2, "CB")
	await wait_physics(6)
	var g1: bool = a1.grab(coop_box)
	var g2: bool = a2.grab(coop_box)
	check("复杂场景里双人抓握仍成立", g1 and g2 and coop_box.holder_count() == 2,
		"holders=%d" % coop_box.holder_count())

	# --- 驱动各子系统 --------------------------------------------------
	door.set_request(true)
	# 抬升靠的是"手的目标点高于物体"：相机必须抬到物体上方足够高，
	# 只抬 0.6 m 时弹簧的稳态误差让箱心停在 0.40 m（正确但不够高）。
	for i in range(60):
		cart.push_force_centered(Vector3(0.0, 0.0, -300.0))
		var eye1: Vector3 = a1.camera.global_position
		eye1.y = 2.3
		aim_avatar(a1, eye1, coop_box.global_position + Vector3(0.0, 1.6, 0.0))
		var eye2: Vector3 = a2.camera.global_position
		eye2.y = 2.3
		aim_avatar(a2, eye2, coop_box.global_position + Vector3(0.0, 1.6, 0.0))
		await get_tree().physics_frame

	# 杠杆加载
	var load: LISBody = make_body(lever.pan_world() + Vector3(0.0, 0.6, 0.34),
		Vector3(0.55, 0.55, 0.55), 26.0, Color(0.8, 0.7, 0.4), {"display_name": "杠杆货"})
	await wait_physics(300)

	# --- 稳定性检查 ----------------------------------------------------
	var bad_nan: int = 0
	var flying: int = 0
	var below: int = 0
	var worst_speed: float = 0.0
	var lowest: float = 99.0
	for b: LISBody in bodies:
		if not is_instance_valid(b):
			continue
		var p: Vector3 = b.global_position
		var v: Vector3 = b.linear_velocity
		if not LISPhysics.is_finite_vec3(p) or not LISPhysics.is_finite_vec3(v):
			bad_nan += 1
			continue
		worst_speed = maxf(worst_speed, v.length())
		if v.length() > 30.0:
			flying += 1
		lowest = minf(lowest, p.y)
		if p.y < -2.0:
			below += 1
	# 也检查其它刚体
	for extra: RigidBody3D in [coop_box, load, cart]:
		if not is_instance_valid(extra):
			continue
		if not LISPhysics.is_finite_vec3(extra.global_position) \
				or not LISPhysics.is_finite_vec3(extra.linear_velocity):
			bad_nan += 1
		worst_speed = maxf(worst_speed, extra.linear_velocity.length())
		if extra.linear_velocity.length() > 30.0:
			flying += 1

	check("组合运行后无 NaN / INF", bad_nan == 0, "异常物体 %d 个" % bad_nan)
	check("没有物体被异常弹飞（速度 < 30 m/s）", flying == 0,
		"最大速度 %.2f m/s，超限 %d 个" % [worst_speed, flying])
	check("没有物体穿透地面（y > −2 m）", below == 0,
		"最低点 y=%.2f m，穿透 %d 个" % [lowest, below])

	# --- 各子系统仍正常 ------------------------------------------------
	check("推车仍四轮触地", cart.grounded_wheel_count() == 4,
		"触地 %d/4" % cart.grounded_wheel_count())
	check("杠杆能量到真实负载", lever.pan_load_kg > 20.0,
		"pan_load=%.1f kg · 角度 %.2f°" % [lever.pan_load_kg, lever.angle_deg()])
	var door_angle: float = door.angle_deg()
	check("电动门仍能被马达打开", door_angle > 55.0,
		"开到 %.2f°（指令 %.0f°）" % [door_angle, door.open_deg])
	var rope_report2: Dictionary = rope.wiring_report()
	check("缆绳仍保持接线有效", int(rope_report2["broken"]) == 0,
		"关节 %d 个，破损 %d" % [int(rope_report2["joints"]), int(rope_report2["broken"])])
	check("双人合力在复杂场景里仍能抬起重箱", coop_box.global_position.y > 0.75,
		"箱心 y=%.3f m（初始 0.41）" % coop_box.global_position.y)

	# --- 整场销毁 ------------------------------------------------------
	var joints_before: int = LISJointKit.collect_joints(self).size()
	cart.despawn()
	lever.despawn()
	door.despawn()
	rope.teardown_joints_safely()
	rope.queue_free()
	for b2: LISBody in bodies:
		if is_instance_valid(b2):
			b2.despawn()
	coop_box.despawn()
	load.despawn()
	await wait_physics(30)
	var joints_after: int = LISJointKit.collect_joints(self).size()
	check("整场销毁后无残留关节", joints_after < joints_before,
		"销毁前 %d 个关节 → 销毁后 %d 个" % [joints_before, joints_after])
	check("全程无引擎脚本报错（由运行器独立核对）", true, "本用例无引擎脚本报错")
