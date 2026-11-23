extends Node
## MECHANICS-001C · 通风机组机械联锁专项
## 断言真实执行并计数；失败返回非零退出码。
## 说明：本专项允许初始化 `power_ready` 前置条件（电源真链路由第一幕 21 项流程验证）。

var app: Node
var vent: Act1Ventilation
var il: Act1FanInterlock
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	app = ps.instantiate()
	add_child(app)
	await _w(120)
	vent = app.builder.vent
	il = app.builder.fan_interlock
	if vent == null or il == null:
		_fail("C0", "场景缺少 vent 或 fan_interlock")
		return _report()

	_check("C1 通风机组与机械联锁都存在", vent != null and il != null,
		"vent=%s interlock=%s" % ["ok" if vent != null else "null", "ok" if il != null else "null"])

	# 初始机械状态
	_check("C2 初始：锁销未脱开、联轴器未啮合",
		(not il.rotor_released()) and (not il.coupling_engaged()) and (not il.machine_ready()),
		"released=%s engaged=%s ready=%s" % [
			"true" if il.rotor_released() else "false",
			"true" if il.coupling_engaged() else "false",
			"true" if il.machine_ready() else "false"])

	# C3 未通电时按启动手柄必须被拒
	app.flags["power_ready"] = false
	await _press("start_fan")
	_check("C3 未通电时启动手柄无反应",
		(not bool(app.flags["fan_started"])) and (not vent.running),
		"fan_started=%s running=%s" % [
			"true" if app.flags["fan_started"] else "false",
			"true" if vent.running else "false"])

	# C4 锁销未拔时联轴器被拒
	await _press("coupling")
	_check("C4 锁销未脱开时联轴器推不动",
		not il.coupling_engaged() and il.collar.global_position.distance_to(il._collar_home) < 0.08,
		"collar 偏移 %.3f m" % il.collar.global_position.distance_to(il._collar_home))

	# C5 按 E 只启动执行器：按下瞬间锁销尚未脱开
	var pin_before: Vector3 = il.pin.global_position
	await _press("rotor_lock")
	var dx_instant: float = il.pin.global_position.x - pin_before.x
	_check("C5 按 E 只启动执行器（销钉不是瞬间到位）",
		(not il.rotor_released()) or dx_instant < 0.25,
		"按下瞬间 dx=%.3f m，released=%s" % [dx_instant,
			"true" if il.rotor_released() else "false"])

	# C6 销钉真实滑出并脱开
	var released_at: int = -1
	for i in range(180):
		await get_tree().physics_frame
		if il.rotor_released():
			released_at = i
			break
	await _w(20)
	var dx: float = il.pin.global_position.x - il._pin_home.x
	_check("C6 锁销由执行器真实拔出并脱开",
		released_at > 0 and dx >= 0.30,
		"第 %d 帧脱开，总位移 %.3f m" % [released_at, dx])

	# C7 脱开后任务状态由机械位置同步
	_check("C7 任务状态由机械位置同步（不是 E 直接置位）",
		bool(app.flags["rotor_lock_released"]),
		"rotor_lock_released=%s" % ("true" if app.flags["rotor_lock_released"] else "false"))

	# C8 联轴器真实推入啮合
	var collar_before: Vector3 = il.collar.global_position
	await _press("coupling")
	var engaged_at: int = -1
	for i in range(240):
		await get_tree().physics_frame
		if il.coupling_engaged():
			engaged_at = i
			break
	await _w(20)
	var dcol: float = il.collar.global_position.distance_to(collar_before)
	_check("C8 联轴器由执行器真实推入并啮合",
		engaged_at > 0 and dcol > 0.20,
		"第 %d 帧啮合，滑套位移 %.3f m" % [engaged_at, dcol])

	# C9 两件都真实到位后机械联锁成立
	_check("C9 锁销脱开 + 联轴器啮合 → 机械联锁成立",
		il.machine_ready(),
		"ready=%s" % ("true" if il.machine_ready() else "false"))

	# C10 通电 + 联锁成立后才能启动，转速真实建立
	app.flags["power_ready"] = true
	await _w(6)
	var speed0: float = vent.speed
	await _press("start_fan")
	for i in range(45):
		await get_tree().physics_frame
	var speed1: float = vent.speed
	_check("C10 启动后转速真实上升（不是置位即完成）",
		bool(app.flags["fan_started"]) and speed1 > speed0 + 0.05,
		"speed %.3f → %.3f（45 帧）" % [speed0, speed1])

	# C11 转子角度随转速真实累积
	var rot0: float = vent.rotor.rotation.x
	await _w(30)
	var rot1: float = vent.rotor.rotation.x
	_check("C11 转子真实转动（角度随转速累积）",
		absf(rot1 - rot0) > 0.05,
		"rotor Δ=%.3f rad，speed=%.3f" % [rot1 - rot0, vent.speed])

	# C12 机械联锁一旦断开，风机必须失去动力
	il.reset_interlock()
	await _w(20)
	_check("C12 机械联锁断开后风机自动失去动力",
		(not bool(app.flags["fan_started"])) and (not vent.running),
		"fan_started=%s running=%s" % [
			"true" if app.flags["fan_started"] else "false",
			"true" if vent.running else "false"])

	# 复原联锁用于后续压力测试
	il.pull_rotor_lock()
	await _w(90)
	il.push_coupling()
	await _w(130)
	app.flags["power_ready"] = true
	await _press("start_fan")
	await _w(30)

	# C13 条件不足（风门未开）时不完成
	vent.set_damper_target(0.0)
	vent.set_governor(1.0)
	vent.pressure_test_seconds = 0.0
	vent.vent_complete = false
	await _w(120)
	_check("C13 风门未开时压力测试不会通过",
		(not vent.vent_complete) and vent.pressure < Act1Ventilation.PRESSURE_MIN + 0.02,
		"pressure=%.3f complete=%s" % [vent.pressure,
			"true" if vent.vent_complete else "false"])

	# C14 条件满足后 6 秒真实压力测试才完成
	vent.set_damper_target(1.0)
	var done_at: int = -1
	for i in range(600):
		await get_tree().physics_frame
		if vent.vent_complete:
			done_at = i
			break
	_check("C14 风门+调速器满足后 6 s 压力测试通过",
		done_at > 240,
		"第 %d 帧完成（约 %.1f s）" % [done_at, float(done_at) / 60.0])

	# C15 重置后机械与通风都回到初始
	il.reset_interlock()
	vent.reset_vent()
	app.flags["rotor_lock_released"] = false
	app.flags["coupling_engaged"] = false
	app.flags["fan_started"] = false
	await _w(20)
	_check("C15 重置后锁销/联轴器/风机回到初始状态",
		(not il.rotor_released()) and (not il.coupling_engaged())
			and vent.speed < 0.35 and (not vent.vent_complete),
		"released=%s engaged=%s speed=%.3f complete=%s" % [
			"true" if il.rotor_released() else "false",
			"true" if il.coupling_engaged() else "false",
			vent.speed, "true" if vent.vent_complete else "false"])
	_report()


func _press(id: String) -> void:
	var pid: int = int(app.local_pid)
	app._execute_interaction(pid, id, "press")
	await _w(4)


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
	print("MECH001C_DONE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
