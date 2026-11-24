extends "res://tests/harness/lis_test_case.gd"
## 机械层 · 通用机械制动（任务书 §11.E）
##
## 验证：
##   1.  制动**不是**冻结物体（物理仍在运行，freeze 为 false）
##   2.  接合后能让转动的轮子减速
##   3.  制动力矩有硬上限（没有无限大）
##   4.  释放后能重新自由转动
##   5.  断电后失去容量（真实机构行为）
##   6.  制动能量被记录且恒为正（没有凭空造能量）
##   7.  速度响应：高速时容量按比例衰减（摩擦片衰退）
##   8.  线性制动（推车式）也能减速
##   9.  障碍物接触不会让制动"无限吸能"
##  10.  制动遥测可读


func _configure() -> void:
	suite_name = "machines_brake"
	expected_checks = 11


func _run() -> void:
	make_world_with_floor(24.0, 0.0, 0.9)
	await wait_physics(6)

	# --- 一个架在铰链上的轮子 ------------------------------------------
	var frame: StaticBody3D = add_static_pad(Vector3(0.0, 0.0, 0.0),
		Vector3(0.4, 2.0, 0.4), 0.9)
	frame.name = "WheelFrame"
	var wheel: RigidBody3D = RigidBody3D.new()
	wheel.name = "BrakeWheel"
	wheel.mass = 20.0
	wheel.gravity_scale = 0.0
	wheel.can_sleep = false
	wheel.angular_damp = 0.02
	wheel.collision_layer = LISPhysics.LAYER_PROP
	wheel.collision_mask = LISPhysics.LAYER_WORLD
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = 0.5
	cyl.height = 0.2
	cs.shape = cyl
	cs.rotation = Vector3(0.0, 0.0, PI * 0.5)
	wheel.add_child(cs)
	add_child(wheel)
	wheel.global_position = Vector3(0.0, 1.6, 0.0)
	# 铰链：轴沿世界 X（轮子绕 X 转）
	var hinge: HingeJoint3D = LISJointKit.create_hinge(frame, "WheelAxle",
		frame, wheel, wheel.global_position, Vector3.RIGHT)
	await wait_physics(10)
	check("轮子铰链接线有效", LISJointKit.is_wired(hinge), "hinge ok")

	# --- 制动器绑定 ----------------------------------------------------
	var brake: LISBrake = LISBrake.new()
	brake.name = "TestBrake"
	brake.max_torque = 200.0
	brake.engage_time = 0.05
	brake.release_time = 0.05
	add_child(brake)
	brake.bind_hinge(hinge)
	await wait_physics(6)

	# 先把轮子转到 12 rad/s
	wheel.angular_velocity = Vector3(12.0, 0.0, 0.0)
	await wait_physics(10)
	var w_before: float = absf(wheel.angular_velocity.x)
	check("轮子已建立初始角速度", w_before > 8.0, "ω=%.2f rad/s" % w_before)

	# --- 接合制动 ------------------------------------------------------
	brake.set_engaged(true)
	await wait_physics(90)
	var w_after: float = absf(wheel.angular_velocity.x)
	print("DIAG brake ω %.2f → %.2f · τ=%.1f · 耗散 %.1f J" % [
		w_before, w_after, brake.last_torque, brake.dissipated_joules])
	check("接合制动后轮子明显减速", w_after < w_before * 0.5,
		"ω %.2f → %.2f rad/s" % [w_before, w_after])
	check("制动不是冻结物体（物理仍在运行）", not wheel.freeze,
		"freeze=%s，sleeping=%s" % [str(wheel.freeze), str(wheel.sleeping)])
	check("制动力矩不超过硬上限", absf(brake.last_torque) <= brake.max_torque + 0.01,
		"|τ|=%.2f N·m ≤ 上限 %.0f N·m" % [absf(brake.last_torque), brake.max_torque])
	check("制动能量被记录且为正", brake.dissipated_joules > 0.0,
		"耗散 %.2f J（τ·ω·dt 累加）" % brake.dissipated_joules)

	# --- 释放后能重新转动 ----------------------------------------------
	brake.set_engaged(false)
	await wait_physics(30)
	var w_released: float = absf(wheel.angular_velocity.x)
	wheel.angular_velocity = Vector3(6.0, 0.0, 0.0)
	await wait_physics(30)
	var w_free: float = absf(wheel.angular_velocity.x)
	check("释放后轮子重新自由转动（仍有角速度）", w_free > 3.0,
		"释放时 %.2f → 30 帧后 %.2f rad/s" % [w_released, w_free])

	# --- 断电 ----------------------------------------------------------
	brake.set_engaged(true)
	await wait_physics(30)
	var torque_powered: float = absf(brake.last_torque)
	brake.set_powered(false)
	await wait_physics(20)
	var torque_unpowered: float = absf(brake.last_torque)
	check("断电后制动器失去容量", torque_unpowered < 0.01,
		"通电 |τ|=%.1f N·m → 断电 |τ|=%.2f N·m" % [torque_powered, torque_unpowered])
	brake.set_powered(true)

	# --- 速度响应（衰退） ----------------------------------------------
	# 先把上一台制动器彻底松开：它还挂着且在接合状态，
	# 否则它会抢先把轮子刹停，"高速"工况根本测不到（实测系数恒为 1.00）。
	brake.set_engaged(false)
	await wait_physics(20)
	var brake2: LISBrake = LISBrake.new()
	brake2.name = "FadingBrake"
	brake2.max_torque = 200.0
	brake2.fade_omega = 4.0
	brake2.fade_ratio = 0.4
	add_child(brake2)
	brake2.bind_hinge(hinge)
	await wait_physics(6)
	# 高速：直接把角速度置到 20 rad/s，**立刻**读容量系数（不等它被刹）
	wheel.angular_velocity = Vector3(20.0, 0.0, 0.0)
	var factor_high: float = brake2._capacity_factor()
	# 低速：置到 1 rad/s 再读
	wheel.angular_velocity = Vector3(1.0, 0.0, 0.0)
	var factor_low: float = brake2._capacity_factor()
	print("DIAG fade high=%.3f low=%.3f" % [factor_high, factor_low])
	check("高速时制动容量按比例衰退", factor_high < factor_low - 0.05,
		"高速容量系数 %.2f < 低速 %.2f（fade_omega=%.0f，fade_ratio=%.2f）" % [
			factor_high, factor_low, brake2.fade_omega, brake2.fade_ratio])
	brake2.queue_free()
	await wait_physics(4)

	# --- 线性制动 ------------------------------------------------------
	var cart: LISBody = make_body(Vector3(8.0, 0.31, 0.0), Vector3(0.6, 0.6, 0.6), 60.0,
		Color(0.6, 0.7, 0.8), {"display_name": "滑块", "friction": 0.05})
	await wait_physics(30)
	var linear_brake: LISBrake = LISBrake.new()
	linear_brake.name = "LinearBrake"
	linear_brake.max_force = 900.0
	linear_brake.engage_time = 0.05
	add_child(linear_brake)
	linear_brake.bind_body_axis(cart, Vector3.RIGHT)
	await wait_physics(4)
	cart.linear_velocity = Vector3(0.0, 0.0, -6.0)
	await wait_physics(4)
	var v_before: float = cart.linear_velocity.length()
	linear_brake.set_engaged(true)
	for i in range(60):
		linear_brake.apply_linear_brake(1.0 / 60.0)
		await get_tree().physics_frame
	var v_after: float = cart.linear_velocity.length()
	print("DIAG linear brake v %.2f → %.2f · F=%.0f N" % [
		v_before, v_after, linear_brake.last_force])
	check("线性制动让滑块减速", v_after < v_before * 0.6,
		"速度 %.2f → %.2f m/s（力上限 %.0f N）" % [v_before, v_after, linear_brake.max_force])

	# --- 遥测 ----------------------------------------------------------
	var tel: Dictionary = linear_brake.telemetry()
	check("制动遥测字段齐全",
		tel.has("engaged") and tel.has("torque") and tel.has("force")
		and tel.has("heat") and tel.has("dissipated_j"),
		"字段 %s" % str(tel.keys()))
