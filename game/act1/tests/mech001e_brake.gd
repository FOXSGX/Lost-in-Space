extends Node
## MECHANICS-001E-R3 · 正式场景停车制动专项
## 全部断言在正式 act01.tscn 实例中真实执行；失败返回非零退出码。

var app: Node
var br: Act1ParkingBrake
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	app = ps.instantiate()
	add_child(app)
	await _w(120)
	br = app.builder.parking_brake
	if br == null:
		_fail("E0", "场景里没有 parking_brake")
		return _report()

	_check("E1 制动组件由 R2 脚本加载",
		br.get_script() != null and str(br.get_script().resource_path).ends_with("act1_parking_brake_r2.gd"),
		str(br.get_script().resource_path))

	_check("E2 销爪与制动鼓都是真实刚体",
		br.pin is RigidBody3D and br.drum is RigidBody3D and br.pin.mass > 0.5 and br.drum.mass > 0.5,
		"pin=%.0fkg drum=%.0fkg" % [br.pin.mass, br.drum.mass])

	_check("E3 初始处于真实锁止状态",
		(not br.released()) and absf(br.pin_travel()) < 0.02,
		"travel=%.3f released=%s" % [br.pin_travel(), "true" if br.released() else "false"])

	# 前置：止轮楔已移走（专项允许初始化前置状态，真实链路见 21 项流程）
	app.flags["chock_removed"] = true
	# E4：按 E 不直接置标志（原地检查）
	app._execute_interaction(int(app.local_pid), "parking_brake", "press")
	await _w(3)
	_check("E4 E 不直接设置 brake_released",
		not bool(app.flags["brake_released"]),
		"brake_released=%s" % ("true" if app.flags["brake_released"] else "false"))

	# E5：执行器把销爪真实抽出
	var out_at: int = -1
	for i in range(200):
		await get_tree().physics_frame
		if br.released():
			out_at = i
			break
	await _w(15)
	_check("E5 销爪由执行器真实抽出到位",
		out_at > 0 and br.pin_travel() <= -Act1ParkingBrake.RELEASE_TRAVEL,
		"第 %d 帧解除，travel=%.3f" % [out_at, br.pin_travel()])

	_check("E6 released() 与真实行程一致",
		br.released() and bool(app.flags["brake_released"]),
		"released=%s flag=%s" % [
			"true" if br.released() else "false",
			"true" if app.flags["brake_released"] else "false"])

	# E7：解除后鼓在力矩下真实转动
	await _w(45)
	var w_free: float = br.drum_omega()
	_check("E7 解除后制动鼓真实转动", w_free > 2.0,
		"ω=%.2f rad/s" % w_free)

	# E8：重新锁止
	br.apply_brake()
	var back_at: int = -1
	for i in range(220):
		await get_tree().physics_frame
		if not br.released():
			back_at = i
			break
	_check("E8 可重新锁止（销爪回到啮合位）",
		back_at > 0 and (not br.released()) and br.pin_travel() > -Act1ParkingBrake.RELEASE_TRAVEL,
		"第 %d 帧重锁，travel=%.3f" % [back_at, br.pin_travel()])

	# E9：重锁后鼓被真实阻挡（角速度显著下降）
	await _w(110)
	var w_locked: float = br.drum_omega()
	_check("E9 重锁后制动鼓被真实阻挡", w_locked < w_free * 0.5,
		"自由 ω=%.2f → 锁止 ω=%.2f" % [w_free, w_locked])

	# E10：止轮楔未移走时发车被拒
	app.flags["chock_removed"] = false
	app.flags["brake_released"] = true
	app.flags["cargo_secured"] = true
	_check("E10 止轮楔未移走时发车联锁拒绝",
		not bool(app._launch_conditions_ok()), "launch_conditions_ok=false")

	# E11：销爪未脱开时发车被拒
	app.flags["chock_removed"] = true
	br.reset_brake()
	await _w(10)
	app.flags["brake_released"] = false
	_check("E11 销爪未脱开时发车联锁拒绝",
		not bool(app._launch_conditions_ok()), "launch_conditions_ok=false")

	# E12：复位后重新处于锁止
	br.reset_brake()
	await _w(20)
	_check("E12 复位后回到初始锁止状态",
		(not br.released()) and absf(br.pin_travel()) < 0.02 and br.drum_omega() < 1.0,
		"travel=%.3f ω=%.2f" % [br.pin_travel(), br.drum_omega()])

	# ---- MECHANICS-001F 开工补充验证：双向 ±12 N·m 三态 + 持续锁止 + 越位 + 代码审计 ----
	await _run_bidirectional()
	await _audit_no_velocity_zeroing()
	_report()


## 在一个方向上完成 锁止 / 释放自由 / 重新锁止 三态测量。
## 记录：累积角位移、角速度、销爪行程、实际接触。
func _run_bidirectional() -> void:
	br.drive_torque = 0.0          # 关掉演示力矩，只施加测试的 ±12 N·m
	for sign_dir in [1.0, -1.0]:
		var tag := "+12Nm" if sign_dir > 0.0 else "-12Nm"
		var torque: Vector3 = br.axis * 12.0 * sign_dir
		# 相同初始条件
		br.reset_brake()
		app.flags["chock_removed"] = true
		app.flags["brake_released"] = true
		await _w(30)
		var travel0: float = br.pin_travel()

		# --- 状态 1：锁止 ---
		var angle0: float = br.drum.rotation.z
		var t0 := Time.get_ticks_msec()
		var locked := await _hold_torque(torque, 240)
		print("EVID %s LOCKED  cum_angle=%.4f rad  omega_end=%.3f rad/s  pin_travel=%.4f m  contacts=%s  用时 %d ms" % [
			tag, locked["cum"], locked["omega"], br.pin_travel(), str(br.pin_contacts()),
			Time.get_ticks_msec() - t0])
		_check("E13%s 锁止状态在 %s 负载下持续稳定（角速度收敛且角位移有界）" % [tag, tag],
			locked["omega"] < 0.35 and locked["cum"] < 1.60,
			"cum=%.4f rad ω_end=%.3f 接触=%s" % [locked["cum"], locked["omega"], str(br.pin_contacts())])
		_check("E14%s 销爪在负载下不越位（无 0.021 m 越位）" % tag,
			br.pin_travel() < 0.01 and br.pin_travel() > -0.03,
			"travel 初始 %.4f → 负载后 %.4f" % [travel0, br.pin_travel()])

		# --- 状态 2：解除 ---
		br.release_brake()
		var out_frames := -1
		for i in range(240):
			await get_tree().physics_frame
			if br.released():
				out_frames = i
				break
		var free := await _spin_to(torque, 10.0, 90)
		print("EVID %s RELEASED cum_angle=%.3f rad  omega_end=%.3f rad/s  pin_travel=%.4f m  解除帧=%d" % [
			tag, free["cum"], free["omega"], br.pin_travel(), out_frames])
		_check("E16%s 解除后同一力矩下制动鼓自由转动" % [tag, "（正）" if sign_dir > 0.0 else "（负）"],
			free["omega"] > 3.0 and free["cum"] > 0.20 and out_frames > 0,
			"ω=%.2f cum=%.3f travel=%.3f" % [free["omega"], free["cum"], br.pin_travel()])

		# --- 状态 3：重新锁止 ---
		br.apply_brake()
		var back_frames := -1
		for i in range(240):
			await get_tree().physics_frame
			if not br.released():
				back_frames = i
				break
		var relocked := await _hold_torque(torque, 300)
		print("EVID %s RELOCKED cum_angle=%.3f rad  omega_end=%.3f rad/s  pin_travel=%.4f m  重锁帧=%d  contacts=%s" % [
			tag, relocked["cum"], relocked["omega"], br.pin_travel(), back_frames, str(br.pin_contacts())])
		_check("E17%s 旋转中的鼓被重新锁止并停下（不是只降到中速）" % [tag, tag],
			back_frames > 0 and relocked["omega"] < 0.60,
			"重锁帧=%d ω_end=%.3f cum=%.3f" % [back_frames, relocked["omega"], relocked["cum"]])
		_check("E18%s 反向/正向都能被齿圈-销爪几何挡住（双向）" % [tag, tag],
			relocked["omega"] < 0.60 and relocked["cum"] < 12.0,
			"cum=%.3f rad" % relocked["cum"])
		_check("E15%s 销爪伸入由实体止挡限位（重锁停在止挡面，未越位）" % tag,
			br.in_stop != null and br.pin_travel() > -0.005 and br.pin_travel() < 0.006,
			"重锁后 travel=%.4f（旧机制可被推入 0.021~0.067 m），止挡=%s，接触=%s" % [
				br.pin_travel(), "PinInStop" if br.in_stop != null else "MISSING", str(br.pin_contacts())])
	# 复原演示力矩，避免影响后续场景
	br.drive_torque = Act1ParkingBrake.SPIN_TORQUE
	br.reset_brake()
	await _w(10)


## 连续施加固定力矩，返回累积角位移（绝对值累加）与末速。
func _hold_torque(torque: Vector3, frames: int) -> Dictionary:
	var cum := 0.0
	var prev: float = br.drum.rotation.z
	var stop_touch := false
	var max_travel := 0.0
	for i in range(frames):
		br.drum.apply_torque(torque)
		await get_tree().physics_frame
		var cur: float = br.drum.rotation.z
		var d := wrapf(cur - prev, -PI, PI)
		cum += absf(d)
		prev = cur
		if br.pin_touching_in_stop():
			stop_touch = true
		max_travel = maxf(max_travel, absf(br.pin_travel()))
	return {"cum": cum, "omega": br.drum_omega(), "stop_touch": stop_touch, "max_travel": max_travel}


## 施加力矩把鼓带到目标角速度（60 Hz 下可分辨的转速区间），再交给锁止测量。
func _spin_to(torque: Vector3, target_omega: float, max_frames: int) -> Dictionary:
	var cum := 0.0
	var prev: float = br.drum.rotation.z
	for i in range(max_frames):
		br.drum.apply_torque(torque)
		await get_tree().physics_frame
		var cur: float = br.drum.rotation.z
		cum += absf(wrapf(cur - prev, -PI, PI))
		prev = cur
		if br.drum_omega() >= target_omega:
			break
	return {"cum": cum, "omega": br.drum_omega()}


## 代码审计：正常机械操作路径中不得直接清零刚体速度。
## 只看**运行路径**（_physics_process … reset_brake 之前）：复位允许清速度，正常路径不允许。
func _audit_no_velocity_zeroing() -> void:
	var path := "res://act1/scripts/machines/act1_parking_brake_r2.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	var src := "" if f == null else f.get_as_text()
	var i0 := src.find("func _physics_process")
	var i1 := src.find("func reset_brake")
	var running := "" if i0 < 0 or i1 <= i0 else src.substr(i0, i1 - i0)
	var vel_edits := running.count(".linear_velocity =") + running.count(".angular_velocity =")
	print("AUDIT %s：运行路径 %d 字符；直接写速度 = %d 次；限力执行器 apply_central_force = %d 次；伸入端止挡 PinInStop = %d 次" % [
		path, running.length(), vel_edits,
		running.count("apply_central_force"), src.count("PinInStop")])
	_check("E19 正常锁止路径不再直接操作销爪速度（改由实体止挡 + 限力执行器）",
		vel_edits == 0 and running.find("apply_central_force") > 0 and src.count("PinInStop") >= 1,
		"velocity_writes=%d force_calls=%d stop=%d" % [
			vel_edits, running.count("apply_central_force"), src.count("PinInStop")])


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS  " if ok else "FAIL  ") + name + "  |  " + detail)


func _fail(tag: String, msg: String) -> void:
	checks += 1
	failures += 1
	print("FAIL  " + tag + "  |  " + msg)


func _report() -> void:
	print("MECH001E_DONE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
