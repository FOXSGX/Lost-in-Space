extends Node
## MECHANICS-001A · 第一幕「电源模块就位」物理化专项探针（001A 基线版）

var app: Node
var failures: int = 0


func _ready() -> void:
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	app = ps.instantiate()
	add_child(app)
	await get_tree().physics_frame
	await _wait(90)

	var cart: Act1PowerCart = app.builder.power_cart
	var mod: RigidBody3D = app.builder.power_module
	if cart == null or mod == null:
		_fail("X0", "场景里没有 power_cart / power_module")
		return _report()

	_check("X1 模块是真实刚体（质量/碰撞）",
		mod is RigidBody3D and mod.mass > 20.0,
		"mass=%.1f kg, layer=%d" % [mod.mass, mod.collision_layer])

	var bad_ok: int = 0
	var bad_moved: float = 0.0
	for k in range(5):
		cart.reset_cart()
		await _wait(8)
		cart.docked = false
		var p_bad: Vector3 = mod.global_position
		cart.transfer_module(Act1StationBuilder.SOCKET)
		await _wait(40)
		bad_moved = maxf(bad_moved, mod.global_position.distance_to(p_bad))
		if (not cart.module_transferred_flag) and mod.global_position.distance_to(p_bad) < 0.05:
			bad_ok += 1
	_check("X2 推车未到位时绞盘不动作、任务不完成（5 轮）",
		bad_ok == 5, "%d/5 轮通过，最大位移 %.3f m" % [bad_ok, bad_moved])

	var chain_ok: int = 0
	var travel_min: float = 99.0
	var err_max: float = 0.0
	var peak_max: float = 0.0
	var frames_max: int = 0
	for k in range(3):
		cart.reset_cart()
		await _wait(10)
		cart.global_position.x = Act1PowerCart.DOCK_X
		mod.global_position = cart.global_transform * Vector3(0.0, 1.85, 0.0)
		cart.docked = true
		await _wait(6)
		var p0: Vector3 = mod.global_position
		cart.transfer_module(Act1StationBuilder.SOCKET)
		var peak: float = 0.0
		var frames: int = -1
		for i in range(900):
			await get_tree().physics_frame
			peak = maxf(peak, mod.linear_velocity.length())
			if cart.module_transferred_flag:
				frames = i
				break
		var travel: float = mod.global_position.distance_to(p0)
		var flat_err: float = Vector2(mod.global_position.x - Act1StationBuilder.SOCKET.x,
			mod.global_position.z - Act1StationBuilder.SOCKET.z).length()
		travel_min = minf(travel_min, travel)
		err_max = maxf(err_max, flat_err)
		peak_max = maxf(peak_max, peak)
		frames_max = maxi(frames_max, frames)
		if frames > 0 and travel > 0.8 and flat_err < 0.45:
			chain_ok += 1
	_check("X3 绞盘真实牵引 + 物理就位（连续 3 轮）",
		chain_ok == 3,
		"%d/3 轮通过；最小位移 %.2f m，最大插座误差 %.2f m，峰值速度 %.2f m/s，最长 %d 帧" % [
			chain_ok, travel_min, err_max, peak_max, frames_max])
	_check("X4 就位标志由物理状态触发（容差内 + 静止）",
		cart.module_transferred_flag and err_max < 0.45,
		"末轮 flag=%s，三轮回差最大 %.2f m" % [
			"true" if cart.module_transferred_flag else "false", err_max])

	cart.reset_cart()
	await _wait(20)
	var home_err: float = mod.global_position.distance_to(cart.module_home)
	_check("X5 复位后模块回到导轨起点、标志清除",
		(not cart.module_transferred_flag) and home_err < 0.05,
		"flag=%s，距起点 %.3f m" % [
			"true" if cart.module_transferred_flag else "false", home_err])
	_report()


func _wait(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print(("PASS  " if ok else "FAIL  ") + name + "  |  " + detail)


func _fail(tag: String, msg: String) -> void:
	failures += 1
	print("FAIL  " + tag + "  |  " + msg)


func _report() -> void:
	print("MECH001A_DONE failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
