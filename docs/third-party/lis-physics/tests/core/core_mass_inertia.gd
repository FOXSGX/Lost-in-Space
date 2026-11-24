extends "res://tests/harness/lis_test_case.gd"
## 核心层 · 质量、惯量、重心与尺寸
##
## 验证"物体行为由真实物理参数决定"：
##   * 同一推力作用下，位移与质量成反比（F=ma 的直接后果）；
##   * 惯量张量与均质长方体理论值一致；
##   * 自定义重心真的改变了倾倒阈值；
##   * size() / half_extent() / extent_along() 与几何一致。
##
## 不使用 Transform 伪造运动：位移全部来自 apply_central_force + 物理积分。


func _configure() -> void:
	suite_name = "core_mass_inertia"
	expected_checks = 11


func _run() -> void:
	make_world_with_floor(20.0, 0.0, 0.0)   # 无摩擦地面，隔离质量效应
	await wait_physics(5)

	# --- 1) 同推力 → 位移与质量成反比 --------------------------------
	var light: LISBody = make_body(Vector3(-4.0, 0.31, 0.0), Vector3(0.6, 0.6, 0.6), 10.0,
		Color(0.4, 0.8, 0.5), {"friction": 0.0, "rough": false})
	var heavy: LISBody = make_body(Vector3(4.0, 0.31, 0.0), Vector3(0.6, 0.6, 0.6), 40.0,
		Color(0.8, 0.4, 0.4), {"friction": 0.0, "rough": false})
	await wait_physics(20)
	var p_light: Vector3 = light.global_position
	var p_heavy: Vector3 = heavy.global_position
	# 同一恒力 200 N 作用 30 帧（0.5 s）
	for i in range(30):
		light.apply_central_force(Vector3(0, 0, -200.0))
		heavy.apply_central_force(Vector3(0, 0, -200.0))
		await get_tree().physics_frame
	var d_light: float = p_light.distance_to(light.global_position)
	var d_heavy: float = p_heavy.distance_to(heavy.global_position)
	var ratio: float = d_light / maxf(d_heavy, 0.0001)
	check_gt("10 kg 比 40 kg 位移更大", d_light, d_heavy)
	check_range("位移比 ≈ 质量反比 4", ratio, 3.0, 5.2)

	# --- 2) 惯量张量 --------------------------------------------------
	var box_size: Vector3 = Vector3(0.6, 1.2, 0.4)
	var m: float = 30.0
	var theoretical: Vector3 = LISPhysics.box_inertia(m, box_size)
	var want_x: float = m / 12.0 * (1.2 * 1.2 + 0.4 * 0.4)
	check_range("Ixx 与 m/12·(h²+d²) 一致", theoretical.x, want_x * 0.999, want_x * 1.001, " kg·m²")

	var spinner: LISBody = make_body(Vector3(0.0, 2.0, 8.0), box_size, m,
		Color(0.5, 0.5, 0.9), {"friction": 0.0})
	await wait_physics(10)
	spinner.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	spinner.center_of_mass = Vector3(0.0, 0.3, 0.0)
	spinner.inertia = theoretical
	await wait_physics(2)
	check("自定义重心生效",
		is_equal_approx(spinner.center_of_mass.y, 0.3),
		"center_of_mass=%.2f" % spinner.center_of_mass.y)

	# 绕 Y 施加扭矩冲量 → 角速度 = J / Iyy
	var iyy: float = m / 12.0 * (box_size.x * box_size.x + box_size.z * box_size.z)
	spinner.angular_velocity = Vector3.ZERO
	spinner.apply_torque_impulse(Vector3(0.0, iyy * 2.0, 0.0))
	await get_tree().physics_frame
	check_range("扭矩冲量 J/Iyy 给出正确角速度", spinner.angular_velocity.y, 1.6, 2.4, " rad/s")

	# --- 3) 尺寸与展宽 -------------------------------------------------
	var s: Vector3 = spinner.size()
	check("size() 与配置一致",
		s.is_equal_approx(box_size), "size=%s" % str(s))
	var ext_x: float = LISPhysics.extent_along(box_size, Vector3.RIGHT)
	check_range("extent_along(+X) = 半宽", ext_x, 0.299, 0.301, " m")
	check_range("half_extent 为对角线一半", spinner.half_extent(),
		box_size.length() * 0.5 - 0.001, box_size.length() * 0.5 + 0.001, " m")

	# --- 4) 重心显著改变倾倒阈值 ---------------------------------------
	# 判据用**静力稳定性**，不用"推一下看谁倒得远"（两边都会倒，读数没有区分度）：
	#   薄高箱体半宽 0.15 m、高 1.20 m。
	#   重心在几何中心 → 重心高 0.60 m → 倾倒临界角 atan(0.15/0.60) = 14.0°；
	#   重心抬到顶部 (局部 +0.55) → 重心高 1.15 m → 临界 atan(0.15/1.15) = 7.4°。
	#   给定同一个初始倾角 10.5°：前者应回正，后者应继续倾倒直到躺平。
	#
	# 初始位姿是**初始条件**（不是伪造运动），之后全部由重力与接触决定。
	# 关键细节：倾斜时必须把箱体抬到"底角恰好触地"，否则底角穿进地面，
	# 穿透恢复冲量会把两个箱子都掀翻 —— 那是测试初始化缺陷，不是物理结论。
	var seed_deg: float = 10.5
	var box_size2: Vector3 = Vector3(0.30, 1.20, 0.30)
	var rest_y: float = _rest_y_for_tilt(box_size2, seed_deg)
	# 稳定性测试必须站在**有摩擦**的台面上：本用例的地面被设成 μ=0 以隔离质量效应，
	# 零摩擦时倾斜箱体的底面会滑出去，任何重心高度都会倒 —— 那不是重心的结论。
	add_static_pad(Vector3(-6.0, 0.0, -8.0), Vector3(5.0, 0.10, 3.0), 0.95)
	add_static_pad(Vector3(6.0, 0.0, -8.0), Vector3(5.0, 0.10, 3.0), 0.95)
	var pad_top: float = 0.10
	var low_com: LISBody = make_body(Vector3(-4.0, pad_top + rest_y, -8.0), box_size2, 20.0,
		Color(0.4, 0.7, 0.7), {"friction": 0.95, "rough": true, "handles": 0})
	var high_com: LISBody = make_body(Vector3(4.0, pad_top + rest_y, -8.0), box_size2, 20.0,
		Color(0.7, 0.7, 0.4), {"friction": 0.95, "rough": true, "handles": 0})
	await wait_physics(20)
	high_com.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	high_com.center_of_mass = Vector3(0.0, 0.55, 0.0)
	for b: LISBody in [low_com, high_com]:
		# 必须**同时**写回高度：物体已经落地（中心高 0.60），只改 rotation
		# 会让底角扎进地面 1.7 cm，穿透恢复冲量足以把箱子掀翻。
		b.rotation = Vector3(0.0, 0.0, deg_to_rad(seed_deg))
		b.global_position = Vector3(b.global_position.x, pad_top + rest_y, b.global_position.z)
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
	await wait_physics(180)
	var tilt_low: float = _tilt_deg(low_com)
	var tilt_high: float = _tilt_deg(high_com)
	check("低重心箱体回正（< 4°）", tilt_low < 4.0,
		"稳态倾角 %.2f°（临界 14.0°，初始 %.1f°）" % [tilt_low, seed_deg])
	check_gt("高重心箱体倾倒（> 30°）", tilt_high, 30.0, " °")

	# --- 5) 有效重量 ---------------------------------------------------
	var w: float = heavy.effective_weight()
	check_range("有效重量 = m·g", w, 40.0 * 9.7, 40.0 * 9.9, " N")


func _tilt_deg(b: RigidBody3D) -> float:
	return rad_to_deg(acos(clampf(b.global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))


## 把箱体绕 Z 转 deg 后，让最低的那个底角恰好落在 y = 0 所需的中心高度。
## 用于设置一个**不穿地**的初始倾角。
func _rest_y_for_tilt(size: Vector3, deg: float) -> float:
	var half: Vector3 = size * 0.5
	var c: float = cos(deg_to_rad(deg))
	var s: float = sin(deg_to_rad(deg))
	# 绕 Z 旋转：局部 (x, y) → 世界 (x·c − y·s, x·s + y·c)
	var lowest: float = 1.0e9
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var wy: float = sx * half.x * s + sy * half.y * c
			lowest = minf(lowest, wy)
	return -lowest + 0.004
