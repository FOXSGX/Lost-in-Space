extends Node
## MECHANICS-001D · 车轮止轮楔真实刚体专项
## 说明：本专项按任务 §9 允许的方式初始化 `vent_complete` 前置状态；
## 真实任务链路由第一幕 21 项流程验证。

var app: Node
var chock: Act1WheelChock
var body: RigidBody3D
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	app = ps.instantiate()
	add_child(app)
	await _w(120)
	chock = app.builder.wheel_chock
	if chock == null:
		_fail("D0", "场景里没有 wheel_chock")
		return _report()
	body = chock.body

	_check("D1 止轮楔是真实刚体（不是无碰撞网格）",
		body is RigidBody3D and body.mass >= 10.0 and body.collision_layer != 0,
		"RigidBody3D mass=%.0f layer=%d" % [body.mass, body.collision_layer])

	_check("D2 初始：楔块在位、任务未完成",
		(not chock.removed()) and (not bool(app.flags["chock_removed"])),
		"removed=%s flag=%s" % [
			"true" if chock.removed() else "false",
			"true" if app.flags["chock_removed"] else "false"])

	# D3 通风未完成时被拒（真实剧情联锁）
	app.flags["vent_complete"] = false
	var p0: Vector3 = body.global_position
	await _press("chock")
	await _w(45)
	_check("D3 通风未完成时止轮楔拖不动（剧情联锁保留）",
		body.global_position.distance_to(p0) < 0.08 and not bool(app.flags["chock_removed"]),
		"位移 %.3f m，flag=%s" % [body.global_position.distance_to(p0),
			"true" if app.flags["chock_removed"] else "false"])

	# D4 按 E 只启动执行器，不是瞬间完成
	app.flags["vent_complete"] = true
	var p1: Vector3 = body.global_position
	await _press("chock")
	var instant: float = p1.z - body.global_position.z
	_check("D4 按 E 只启动执行器（楔块不是瞬间消失/瞬移）",
		(not chock.removed()) or instant < 0.25,
		"按下瞬间 dz=%.3f m，removed=%s" % [instant,
			"true" if chock.removed() else "false"])

	# D5 楔块真实被拖出
	var removed_at: int = -1
	for i in range(200):
		await get_tree().physics_frame
		if chock.removed():
			removed_at = i
			break
	await _w(20)
	var dx: float = chock._home.z - body.global_position.z
	_check("D5 楔块由执行器真实拖出（位移达标）",
		removed_at > 0 and dx >= 0.30,
		"第 %d 帧判定移走，位移 %.3f m" % [removed_at, dx])

	# D6 任务状态由物理位置同步
	_check("D6 任务状态由刚体位置同步（不是 E 直接置位）",
		bool(app.flags["chock_removed"]),
		"chock_removed=%s" % ("true" if app.flags["chock_removed"] else "false"))

	# D7 只有止轮楔一项不足以发车（其它联锁仍有效）
	app.flags["brake_released"] = false
	app.flags["cargo_secured"] = false
	_check("D7 仅移走止轮楔不足以发车（其它联锁仍生效）",
		not bool(app._launch_conditions_ok()),
		"launch_conditions_ok=false")

	# D8 楔块被推回/被挡住时不判定为移走
	chock.reset_chock()
	await _w(20)
	_check("D8 楔块回到原位时不再判定为已移走",
		not chock.removed(),
		"removed=%s，dx=%.3f m" % [
			"true" if chock.removed() else "false",
			chock._home.z - body.global_position.z])

	# D9 反向推：静态挡边阻止楔块被推得更深（不穿透）
	var p9: Vector3 = body.global_position
	for i in range(40):
		body.sleeping = false
		body.apply_central_force(Vector3(0.0, 0.0, 260.0))
		await get_tree().physics_frame
	await _w(15)
	var pushed: float = absf(body.global_position.z - p9.z)
	_check("D9 楔块被 +Z 挡边挡住（不会穿透/陷入轮下）",
		pushed < 0.12,
		"反向推(+Z) 40 帧后位移 %.3f m" % pushed)

	# D10 重置后回到初始位置
	chock.reset_chock()
	await _w(20)
	_check("D10 重置后楔块回到初始位置",
		body.global_position.distance_to(chock._home) < 0.08,
		"距原位 %.3f m" % body.global_position.distance_to(chock._home))

	# D11 连续 3 轮拖出/复位稳定
	var stable: int = 0
	var travel_min: float = 99.0
	for k in range(3):
		chock.reset_chock()
		await _w(25)
		chock.pull()
		var ok_round: bool = false
		for i in range(220):
			await get_tree().physics_frame
			if chock.removed():
				ok_round = true
				break
		var t: float = chock._home.z - body.global_position.z
		travel_min = minf(travel_min, t)
		if ok_round:
			stable += 1
	_check("D11 连续 3 轮拖出/复位都稳定（不发散、不弹飞）",
		stable == 3 and travel_min >= 0.30 and body.global_position.y > -1.0,
		"%d/3 轮通过，最小位移 %.3f m，末位置 y=%.2f" % [stable, travel_min, body.global_position.y])
	_report()


func _press(id: String) -> void:
	app._execute_interaction(int(app.local_pid), id, "press")
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
	print("MECH001D_DONE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
