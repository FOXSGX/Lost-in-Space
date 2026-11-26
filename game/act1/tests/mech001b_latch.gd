extends Node
## MECHANICS-001B-R2 · 旋转锁爪与机械锁止专项
## 断言真正执行并计数；失败返回非零退出码。

var app: Node
var cart: Act1PowerCart
var jaw: RigidBody3D
var mod: RigidBody3D
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	app = ps.instantiate()
	add_child(app)
	await _w(90)
	cart = app.builder.power_cart
	jaw = cart.clamp_jaw
	mod = app.builder.power_module
	if cart == null or jaw == null or mod == null:
		_fail("Z0", "场景缺少 power_cart / clamp_jaw / power_module")
		return _report()

	var axis: Vector3 = cart.clamp_axis
	_check("A1 铰链自由轴由实测确定且为水平轴",
		absf(axis.dot(Vector3.UP)) < 0.01 and absf(axis.length() - 1.0) < 0.01,
		"axis=%s" % str(axis.snapped(Vector3(0.001, 0.001, 0.001))))

	# A2 未下指令时锁爪被马达保持在打开位（水平），不会被重力甩下去
	await _w(90)
	_check("A2 未下指令时锁爪由马达保持在打开位",
		absf(cart.clamp_angle) <= 0.10 and not cart.clamp_closed,
		"angle=%.3f rad，closed=%s" % [cart.clamp_angle,
			"true" if cart.clamp_closed else "false"])

	_check("B1 未发出夹紧指令时任务不通电",
		not bool(app.flags["power_clamped"]),
		"power_clamped=%s" % ("true" if app.flags["power_clamped"] else "false"))

	cart.global_position.x = Act1PowerCart.DOCK_X
	mod.global_position = cart.global_transform * Vector3(0.0, 1.86, 0.0)
	cart.docked = true
	await _w(10)
	cart.transfer_module(Act1StationBuilder.SOCKET)
	for i in range(400):
		await get_tree().physics_frame
		if cart.module_transferred_flag:
			break
	_check("C1 模块真实沿导轨进入插座（同一件刚体）",
		cart.module_transferred_flag,
		"flag=%s，位置=%s" % [
			"true" if cart.module_transferred_flag else "false",
			str(mod.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])

	var a0: float = cart.clamp_angle
	cart.set_clamp(true)
	var closed_at: int = -1
	for i in range(300):
		await get_tree().physics_frame
		if cart.clamp_angle >= Act1PowerCart.CLAMP_CLOSED_ANGLE - 0.10 and cart.clamp_angle <= Act1PowerCart.CLAMP_CLOSED_ANGLE + 0.10:
			closed_at = i
			break
	var a1: float = cart.clamp_angle
	_check("B2 锁爪由电机真实转到锁止角（压在模块上）",
		closed_at > 0 and a1 > a0,
		"%.3f → %.3f rad（第 %d 帧到位）" % [a0, a1, closed_at])

	await _w(45)
	var a2: float = cart.clamp_angle
	_check("B3 锁止后角度稳定（马达保持，不漂移）",
		absf(a2 - a1) < 0.10 and cart.clamp_locked(),
		"%.3f → %.3f rad，locked=%s" % [a1, a2,
			"true" if cart.clamp_locked() else "false"])

	await _w(30)
	_check("B4 通电由真实机械锁止状态决定",
		bool(app.flags["power_clamped"]) and bool(app.flags["power_ready"]),
		"power_clamped=%s power_ready=%s" % [
			"true" if app.flags["power_clamped"] else "false",
			"true" if app.flags["power_ready"] else "false"])

	cart.set_clamp(false)
	var reopened: bool = false
	for i in range(400):
		await get_tree().physics_frame
		if cart.clamp_angle <= 0.10:
			reopened = true
			break
	_check("A3 反向电机能把锁爪抬回打开位", reopened,
		"angle=%.3f rad" % cart.clamp_angle)

	var stable: int = 0
	for k in range(3):
		cart.set_clamp(true)
		await _w(150)
		var closed_ok: bool = cart.clamp_angle >= 0.88 and cart.clamp_angle <= 1.12
		cart.set_clamp(false)
		await _w(150)
		if closed_ok and cart.clamp_angle <= 0.12:
			stable += 1
	_check("A4 连续 3 轮开合后角度不发散", stable == 3,
		"%d/3 轮：闭合落在 0.90–1.12 rad 且回到 ≤0.12 rad" % stable)
	# === 反向拉力（任务 §5 / §13-10）：锁止后拉不动 / 解锁后可动 ===
	cart.set_clamp(true)
	for i in range(300):
		await get_tree().physics_frame
		if cart.clamp_locked():
			break
	await _w(30)
	mod.sleeping = false
	var p6: Vector3 = mod.global_position
	for i in range(50):
		mod.apply_central_force(Vector3(0.0, 0.0, 600.0))
		await get_tree().physics_frame
	await _w(15)
	var d6: float = mod.global_position.distance_to(p6)
	_check("B6 锁止后同一外力拉不动模块",
		cart.clamp_locked() and d6 < 0.10,
		"锁爪 %.3f rad，位移 %.3f m" % [cart.clamp_angle, d6])

	cart.set_clamp(false)
	await _w(150)
	mod.sleeping = false
	var p7: Vector3 = mod.global_position
	for i in range(50):
		mod.apply_central_force(Vector3(0.0, 0.0, 600.0))
		await get_tree().physics_frame
	await _w(15)
	var d7: float = mod.global_position.distance_to(p7)
	_check("B7 解锁后同一外力又能拉动模块",
		d7 > 0.50 and cart.clamp_angle <= 0.20,
		"锁爪 %.3f rad，位移 %.3f m" % [cart.clamp_angle, d7])

	mod.sleeping = false
	# B5 复位后可重新完成整套流程（任务 §C8）
	cart.reset_cart()
	await _w(30)
	cart.global_position.x = Act1PowerCart.DOCK_X
	mod.global_position = cart.global_transform * Vector3(0.0, 1.86, 0.0)
	cart.docked = true
	await _w(12)
	cart.transfer_module(Act1StationBuilder.SOCKET)
	for i in range(400):
		await get_tree().physics_frame
		if cart.module_transferred_flag:
			break
	await _w(30)
	cart.set_clamp(true)
	var relock: bool = false
	for i in range(300):
		await get_tree().physics_frame
		if cart.clamp_locked():
			relock = true
			break
	_check("B5 复位后可重新送料并再次锁止", relock and cart.module_transferred_flag,
		"就位=%s，锁爪 %.3f rad" % [
			"true" if cart.module_transferred_flag else "false", cart.clamp_angle])
	_report()


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
	print("MECH001B_DONE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
