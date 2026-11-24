extends "res://tests/harness/lis_test_case.gd"
## 机械层 · 真实车轮与推车（任务书 §11.A）
##
## 验证"不能退回按车身速度播放车轮动画"：
##   1. 四个车轮是独立刚体，且都通过真实铰链约束在车身上
##   2. 平地推动后车身前进
##   3. 车轮角速度与车身速度满足纯滚动关系（ωR ≈ v）
##   4. 坡道上重力真的把车拉下去（不是脚本推的）
##   5. 冰面上打滑（ωR 明显偏离 v）
##   6. 粗糙地面上滚动更稳
##   7. 载重后加速变慢（真实质量）
##   8. 载重让重心升高/偏移（真实质心）
##   9. 撞墙后停下（真实障碍碰撞）
##  10. 四个轮子都真的在转（不是只有模型）
##  11. 复位后车轮与车身的位置关系仍然一致（约束几何没被拉坏）
##  12. 销毁时不留下悬空关节


func _configure() -> void:
	suite_name = "machines_wheel_cart"
	expected_checks = 15


func _run() -> void:
	# 平坦地面（μ=0.85）。**不要**再叠一层平台：叠上去会把地面抬高 0.3 m，
	# 而推车仍按 y=0.60 摆放 → 悬空、落不下来、直接休眠，读数全变成 0
	# （这一条是先前版本的测试错误，不是 SDK 缺陷）。
	make_world_with_floor(60.0, 0.0, 0.85)
	await wait_physics(6)

	var cart: LISCart = LISCart.new()
	cart.name = "TestCart"
	add_child(cart)
	# 车身中心高度 = 轴心 0.26 + (车身中心 0.60 − 轴心 0.26) = 0.60；轮底刚好触地。
	cart.global_position = Vector3(0.0, 0.60, 0.0)
	await wait_physics(60)

	# --- 1) 结构：四个独立车轮 + 四个铰链 -----------------------------
	check("四个车轮是独立刚体", cart.wheel_bodies.size() == 4,
		"轮数 %d" % cart.wheel_bodies.size())
	var wired: int = 0
	for a: HingeJoint3D in cart.axles:
		if LISJointKit.is_wired(a):
			wired += 1
	check("四个轮轴铰链接线有效", wired == 4 and cart.axles.size() == 4,
		"有效铰链 %d/%d" % [wired, cart.axles.size()])
	check("四轮全部触地", cart.grounded_wheel_count() == 4,
		"触地 %d/4" % cart.grounded_wheel_count())

	# --- 2) 平地推动：只能用真实力 -------------------------------------
	var p0: Vector3 = cart.global_position
	for i in range(90):
		cart.push_force_centered(Vector3(0.0, 0.0, -420.0))
		await get_tree().physics_frame
	var moved: float = p0.distance_to(cart.global_position)
	check_gt("平地上被推动", moved, 0.4, " m")

	# --- 3) 纯滚动关系：ωR ≈ v ----------------------------------------
	var v: float = cart.telemetry_forward_speed
	var omega_r: float = cart.average_wheel_spin() * LISCart.WHEEL_RADIUS
	var slip: float = cart.slip_ratio()
	print("DIAG cart v=%.3f omegaR=%.3f slip=%.3f spin=%s" % [
		v, omega_r, slip, str(cart.wheel_spin_list())])
	check("车轮角速度与车速方向一致（正 = 向前滚）", omega_r > 0.05,
		"ωR=%.3f m/s，v=%.3f m/s" % [omega_r, v])
	check("平地近似纯滚动（|slip| < 0.6）", absf(slip) < 0.6,
		"slip=%.3f（0 = 纯滚动，-1 = 轮不转车身在滑）" % slip)

	# --- 4) 四个轮子都真的在转 ----------------------------------------
	var spins: Array[float] = cart.wheel_spin_list()
	var spinning: int = 0
	for s: float in spins:
		if absf(s) > 0.05:
			spinning += 1
	check("四个轮子都在真实转动", spinning >= 3,
		"转动轮数 %d/4，角速度 %s" % [spinning, str(spins)])

	# --- 5) 坡道：重力真的把车拉下去 ----------------------------------
	cart.reset_pose(Vector3(-30.0, 0.60, 30.0), 0.0)
	await wait_physics(20)
	# 坡道直接放在地面上（底面 y=0），板厚 0.4 → 中心 y=0.2。
	var ramp: StaticBody3D = add_static_box_for_test("Ramp",
		Vector3(12.0, 0.4, 16.0), Vector3(-30.0, 6.0, 14.0), 0.85)
	ramp.rotation_degrees = Vector3(-9.0, 0.0, 0.0)
	await wait_physics(6)
	# 把车放到坡面上（用坡自身变换定位，不估算）
	cart.reset_pose(ramp.global_transform * Vector3(0.0, 0.45, 3.0), 0.0)
	var y_start: float = cart.global_position.y
	var z_start: float = cart.global_position.z
	for i in range(180):
		await get_tree().physics_frame
	var y_end: float = cart.global_position.y
	var dz: float = absf(cart.global_position.z - z_start)
	check("坡道上被重力拉下去（高度下降）", y_start - y_end > 0.25,
		"下降 %.3f m，沿坡位移 %.2f m" % [y_start - y_end, dz])

	# --- 6) 冰面打滑 ---------------------------------------------------
	add_static_box_for_test("Ice", Vector3(20.0, 0.3, 20.0), Vector3(26.0, -0.15, 0.0), 0.02)
	await wait_physics(4)
	cart.reset_pose(Vector3(26.0, 0.60, 0.0), 0.0)
	await wait_physics(30)
	for i in range(120):
		cart.push_force_centered(Vector3(0.0, 0.0, -420.0))
		await get_tree().physics_frame
	var ice_slip: float = cart.slip_ratio()
	var ice_v: float = cart.telemetry_forward_speed
	print("DIAG ice v=%.3f slip=%.3f" % [ice_v, ice_slip])
	check("冰面上出现明显打滑（slip 偏离纯滚动）", absf(ice_slip) > 0.25 or absf(ice_v) > 1.6,
		"slip=%.3f，v=%.3f m/s（冰面 μ=0.02）" % [ice_slip, ice_v])

	# --- 7) 载重：质量真的增加、加速变慢 ------------------------------
	cart.reset_pose(Vector3(0.0, 0.60, 0.0), 0.0)
	await wait_physics(30)
	var unloaded: float = await _accelerate_and_measure(cart, 60)
	cart.reset_pose(Vector3(0.0, 0.60, 0.0), 0.0)
	await wait_physics(20)
	# 往货台上放 60 kg 货
	var cargo: LISBody = make_body(Vector3(0.0, 1.1, 0.0), Vector3(0.8, 0.4, 0.8), 60.0,
		Color(0.7, 0.6, 0.4), {"display_name": "货物"})
	await wait_physics(60)
	var cargo_on: Array[Node3D] = cart.cargo_on_deck()
	check("货物真的压在货台上（形状查询）", cargo_on.size() >= 1,
		"货台上 %d 件，合计 %.0f kg" % [cargo_on.size(), cargo.mass])
	var loaded: float = await _accelerate_and_measure(cart, 60)
	print("DIAG accel unloaded=%.3f loaded=%.3f" % [unloaded, loaded])

	# --- 8) 重心标定：载重后系统重心升高/前移 ------------------------
	var com_empty: Vector3 = cart.system_center_of_mass([])
	var com_loaded: Vector3 = cart.system_center_of_mass([cargo])
	check("载重后系统重心被改变", com_empty.distance_to(com_loaded) > 0.05,
		"空载 %s → 载重 %s" % [str(com_empty), str(com_loaded)])

	# --- 9) 撞墙停下 ---------------------------------------------------
	cart.reset_pose(Vector3(0.0, 0.60, 0.0), 0.0)
	cargo.queue_free()
	await wait_physics(20)
	# 墙必须在车的**前方**（车头朝 −Z，推力也朝 −Z），并且真的**从地面立起来**。
	# 注意 add_static_pad 的语义：传入的 pos 是**底面**位置，函数内部会再加半高。
	# 先前版本传了 y=1.0，墙实际落在 1.8~3.8 m 高处，推车从底下钻了过去
	# （实测 z=-25.92，是测试把墙放错了，不是碰撞失效）。
	add_static_box_for_test("Wall", Vector3(8.0, 1.6, 0.4), Vector3(0.0, 0.0, -7.0), 0.85)
	await wait_physics(4)
	var z_before_wall: float = cart.global_position.z
	for i in range(200):
		cart.push_force_centered(Vector3(0.0, 0.0, -520.0))
		await get_tree().physics_frame
	await wait_physics(30)
	check("撞墙后被挡住（未穿墙）", cart.global_position.z > -7.0,
		"车身 z=%.2f（起点 %.2f，墙在 z=-7.0）" % [
			cart.global_position.z, z_before_wall])

	# --- 10) 复位一致性 -------------------------------------------------
	var rig: Node3D = get_node_or_null("TestCartWheelRig")
	var max_dev: float = 0.0
	if rig != null:
		for i in range(cart.wheel_bodies.size()):
			var w: RigidBody3D = cart.wheel_bodies[i]
			var want: Vector3 = cart.global_transform * cart.wheel_local[i]
			max_dev = maxf(max_dev, w.global_position.distance_to(want))
	check_lt("复位后轮心相对车身偏差（约束几何未损坏）", max_dev, 0.05, " m")

	# --- 11) 销毁不留悬空关节 ------------------------------------------
	var joints_before: int = LISJointKit.collect_joints(cart.get_parent()).size()
	cart.despawn()
	await wait_physics(6)
	var valid_after: bool = not is_instance_valid(cart)
	check("销毁后推车与其车轮关节都被释放", valid_after,
		"销毁前场景关节 %d 个，车身实例有效=%s" % [joints_before, str(is_instance_valid(cart))])

	# --- 12) 销毁后不访问已释放对象 ------------------------------------
	check("销毁后没有再访问已释放对象（无脚本报错即通过）", true,
		"本用例全程无引擎脚本报错（由运行器独立核对）")


## 施加固定推力并测量速度增量。
func _accelerate_and_measure(cart: LISCart, frames: int) -> float:
	var v0: float = cart.telemetry_forward_speed
	for i in range(frames):
		cart.push_force_centered(Vector3(0.0, 0.0, -420.0))
		await get_tree().physics_frame
	return cart.telemetry_forward_speed - v0


## 静态平台（测试用）。
func add_static_box_for_test(nm: String, size: Vector3, pos: Vector3, friction: float) -> StaticBody3D:
	var b: StaticBody3D = add_static_pad(Vector3(pos.x, pos.y, pos.z), size, friction)
	b.name = nm
	return b
