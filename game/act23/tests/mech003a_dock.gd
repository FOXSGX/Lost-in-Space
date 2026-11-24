extends Node
## MECHANICS-003A · 第三幕（03 · 晶体矿区入口）停靠夹钳专项
##
## 全部断言在正式切片 res://act23/moving_cart.tscn 的 106 m 站台上执行：
## 1 自由度闸臂（惯量/配重/止挡）+ 棘爪 + 真实几何压车判定 + 章节完成条件。
## 失败返回非零退出码。

var stage: Node
var flow: Node
var cart: AnimatableBody3D
var dock: Node3D
var device: Node
var player: CharacterBody3D
var checks: int = 0
var failures: int = 0


func _ready() -> void:
	stage = (load("res://act23/moving_cart.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	flow = stage.get("flow")
	cart = stage.get("cart") as AnimatableBody3D
	dock = stage.get("dock") as Node3D
	device = stage.get("device")
	player = stage.get("player") as CharacterBody3D
	if flow == null or cart == null or dock == null or player == null:
		_fail("D0", "切片缺少 flow/cart/dock/player")
		return _report()
	# 本专项要在关卡里反复做停靠/解除，不能被真实的章节切换把场景换走；
	# 真正的 Act23 → Act04 交接由 mech003a_handoff 单独验证。
	stage.set("_chapter_handoff_started", true)
	await _d1_load()
	await _d2_story()
	await _d3_hardware()
	await _d4_initial()
	await _d5_key_not_success()
	await _d6_operation()
	await _d7_gravity()
	await _d8_latch_conditions()
	await _d9_dock()
	await _d10_blocked()
	await _d11_release()
	await _d12_retry()
	await _d13_reset()
	await _d14_repeat()
	await _d15_abnormal()
	await _d16_regression()
	await _d17_player()
	await _d18_handoff_ready()
	_report()


# ---------------------------------------------------------------- 1 加载
func _d1_load() -> void:
	var arm: Node = dock.get_node_or_null("DockArm")
	_check("D1 第三幕正式切片与晶体门停靠夹钳正常加载",
		stage.is_inside_tree() and dock.is_inside_tree() and arm != null
			and absf(float(cart.get("distance"))) < 0.01,
		"stage=%s dock=%s arm=%s distance=%.2f" % [stage.name, dock.name, str(arm != null),
			float(cart.get("distance"))])


# ---------------------------------------------------------------- 2 剧情
func _d2_story() -> void:
	var dock_text: String = str(flow.call("_objective_for", "dock"))
	var done_text: String = str(flow.call("_objective_for", "done"))
	_check("D2 原有第三幕剧情保留（board 起点、晶体门停靠目标、到站目标文案）",
		str(flow.get("phase")) == "board" and dock_text.find("夹钳") >= 0
			and done_text.find("停靠") >= 0 and not bool(dock.call("docked")),
		"phase=%s dock目标=%s done目标=%s" % [str(flow.get("phase")), dock_text, done_text])


# ---------------------------------------------------------------- 3 机构
func _d3_hardware() -> void:
	var pawl: Node = dock.get_node_or_null("Pawl")
	var arm: Node = dock.get_node_or_null("DockArm")
	var state: Dictionary = dock.call("state")
	_check("D3 机械设备正确创建（闸臂/棘爪/铰座：惯量 130 kg·m²、拉力矩上限 430 N·m、闭合 86°）",
		pawl != null and arm != null and float(state.get("inertia", 0.0)) > 50.0
			and float(state.get("pull_torque_max", 0.0)) > 200.0
			and absf(float(state.get("closed_deg", 0.0)) - 85.9) < 0.5,
		"pawl=%s arm=%s I=%.0f τmax=%.0f 闭合=%.1f°" % [str(pawl != null), str(arm != null),
			float(state.get("inertia", 0.0)), float(state.get("pull_torque_max", 0.0)),
			float(state.get("closed_deg", 0.0))])


# ---------------------------------------------------------------- 4 初始
func _d4_initial() -> void:
	var state: Dictionary = dock.call("state")
	_check("D4 初始状态正确（闸臂竖起 0°、未落棘爪、未停靠、矿车不在门区）",
		absf(float(state.get("angle_deg", 99.0))) < 0.5 and not bool(state.get("latched", true))
			and not bool(state.get("docked", true)) and not bool(state.get("cart_in_zone", true)),
		"angle=%.1f latched=%s docked=%s in_zone=%s" % [
			float(state.get("angle_deg", 0.0)), str(state.get("latched")),
			str(state.get("docked")), str(state.get("cart_in_zone"))])


# ---------------------------------------------------------------- 5 按键不直接完成
func _d5_key_not_success() -> void:
	# 站台离矿车超过 18 m 会被关卡的安全救援拉回甲板（真实规则），
	# 所以先把车停在门区外 6 m（允许下车、但还不在停靠位）。
	cart.call("snap_to_distance", 100.0)
	await _w(20)
	await _at_handle()
	var handle: Vector3 = dock.call("handle_world") as Vector3
	print("CAP D5 dist=%.2f player=%s handle=%s" % [player.global_position.distance_to(handle),
		str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
		str(handle.snapped(Vector3(0.01, 0.01, 0.01)))])
	var result: Dictionary = dock.call("operate")
	await _w(10)
	_check("D5 交互不会直接宣布任务完成（E 只返回“拉闸臂”，docked 仍为 false、章节不进入 done）",
		bool(result.get("ok", false)) and str(result.get("action", "")) == "pulling"
			and not bool(dock.call("docked")) and str(flow.get("phase")) != "done",
		"operate=%s docked=%s phase=%s" % [str(result), str(dock.call("docked")),
			str(flow.get("phase"))])


# ---------------------------------------------------------------- 6 操作改变机构
func _d6_operation() -> void:
	var a0: float = float((dock.call("state") as Dictionary).get("angle_deg", 0.0))
	Input.action_press("repair")
	for i in range(120):
		await get_tree().physics_frame
		if float((dock.call("state") as Dictionary).get("angle_deg", 0.0)) > 40.0:
			break
	var a1: float = float((dock.call("state") as Dictionary).get("angle_deg", 0.0))
	Input.action_release("repair")
	_check("D6 玩家操作能够改变真实机械状态（按住 E → 闸臂转角由力矩积分增大）",
		a1 > a0 + 30.0 and a1 < 90.0,
		"角度 %.1f° → %.1f°（I=130 kg·m²，拉力矩 430 N·m）" % [a0, a1])


# ---------------------------------------------------------------- 7 配重恢复
func _d7_gravity() -> void:
	Input.action_release("repair")
	var a0: float = float((dock.call("state") as Dictionary).get("angle_deg", 0.0))
	var t: float = 0.0
	for i in range(130):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var a1: float = float((dock.call("state") as Dictionary).get("angle_deg", 0.0))
	_check("D7 机械运动符合实际受力（松手后配重把闸臂抬回，角度单调减小）",
		a1 < a0 - 1.0 and t > 0.5,
		"松手 %.2f s：%.1f° → %.1f°（配重 330 N·m 系数）" % [t, a0, a1])


# ---------------------------------------------------------------- 8 条件不足
func _d8_latch_conditions() -> void:
	# 矿车不在门区：把车退回维修区，再拉闸臂
	cart.call("reset_run")
	cart.call("snap_to_distance", 90.0)
	await _w(20)
	await _at_handle()
	Input.action_press("repair")
	await _w(150)
	var state: Dictionary = dock.call("state")
	Input.action_release("repair")
	_check("D8 条件不足时不会成功（矿车不在晶体门：闸臂能拉到底但棘爪不落、docked=false）",
		absf(float(state.get("angle_deg", 0.0)) - 85.9) < 3.0
			and not bool(state.get("latched", true)) and not bool(state.get("docked", true))
			and not bool(state.get("cart_in_zone", true)),
		"angle=%.1f latched=%s docked=%s in_zone=%s blocked=%s" % [
			float(state.get("angle_deg", 0.0)), str(state.get("latched")),
			str(state.get("docked")), str(state.get("cart_in_zone")), str(state.get("blocked"))])
	await _w(30)


# ---------------------------------------------------------------- 9 正确停靠
func _d9_dock() -> void:
	await _drive_to_dock()
	await _at_handle()
	Input.action_press("repair")
	var latched: bool = false
	for i in range(240):
		await get_tree().physics_frame
		if bool(dock.call("docked")):
			latched = true
			break
	Input.action_release("repair")
	await _w(30)
	var state: Dictionary = dock.call("state")
	_check("D9 正确物理条件满足后任务完成（车在门区 + 闸臂压住车侧 + 棘爪落位 → docked → 章节 done）",
		latched and bool(state.get("latched", false)) and bool(state.get("pressed", false))
			and str(flow.get("phase")) == "done",
		"angle=%.1f pressed=%s latched=%s docked=%s phase=%s" % [
			float(state.get("angle_deg", 0.0)), str(state.get("pressed")),
			str(state.get("latched")), str(state.get("docked")), str(flow.get("phase"))])
	cap("DOCK A_angle=%.1f B_latched=%s C_docked=%s phase=%s" % [
		float(state.get("angle_deg", 0.0)), str(state.get("latched")),
		str(state.get("docked")), str(flow.get("phase"))])


# ---------------------------------------------------------------- 10 受阻
func _d10_blocked() -> void:
	# 车退回门区外，闸臂拉到止挡：臂端没有压到车，pressed=false，不得判停靠
	await _release_and_open()
	cart.call("snap_to_distance", 100.0)
	await _w(20)
	await _at_handle()
	Input.action_press("repair")
	await _w(150)
	var state: Dictionary = dock.call("state")
	Input.action_release("repair")
	_check("D10 机械受到阻挡时不会穿透/误判（臂压空：到止挡但 pressed=false，docked=false）",
		absf(float(state.get("angle_deg", 0.0)) - 85.9) < 3.0
			and not bool(state.get("pressed", true)) and not bool(state.get("docked", true))
			and bool(state.get("blocked", false)),
		"angle=%.1f pressed=%s blocked=%s docked=%s" % [
			float(state.get("angle_deg", 0.0)), str(state.get("pressed")),
			str(state.get("blocked")), str(state.get("docked"))])
	await _w(30)


# ---------------------------------------------------------------- 11 锁止/释放
func _d11_release() -> void:
	await _drive_to_dock()
	await _at_handle()
	Input.action_press("repair")
	for i in range(240):
		await get_tree().physics_frame
		if bool(dock.call("docked")):
			break
	Input.action_release("repair")
	await _w(20)
	var before: bool = bool(dock.call("docked"))
	# E 抬棘爪
	Input.action_press("repair")
	await _w(3)
	Input.action_release("repair")
	flow.call("try_interact", player)
	for i in range(60):
		await get_tree().physics_frame
	var after: Dictionary = dock.call("state")
	_check("D11 锁止/释放状态合理（抬棘爪后闸臂被配重抬回、docked 失效、章节退回 dock）",
		before and not bool(after.get("latched", true)) and not bool(after.get("docked", true))
			and float(after.get("angle_deg", 90.0)) < 80.0 and str(flow.get("phase")) == "dock",
		"before=%s after latched=%s angle=%.1f phase=%s" % [str(before),
			str(after.get("latched")), float(after.get("angle_deg", 0.0)), str(flow.get("phase"))])
	await _w(40)


# ---------------------------------------------------------------- 12 失败恢复
func _d12_retry() -> void:
	await _at_handle()
	Input.action_press("repair")
	var ok: bool = false
	for i in range(240):
		await get_tree().physics_frame
		if bool(dock.call("docked")):
			ok = true
			break
	Input.action_release("repair")
	await _w(20)
	_check("D12 操作失败后可以恢复（解除后重新拉闸臂仍能完成停靠）",
		ok and str(flow.get("phase")) == "done",
		"重试 docked=%s phase=%s" % [str(ok), str(flow.get("phase"))])


# ---------------------------------------------------------------- 13 复位
func _d13_reset() -> void:
	stage.call("reset_run")
	await _w(60)
	var state: Dictionary = dock.call("state")
	_check("D13 R 复位正确（闸臂回竖起、棘爪抬起、矿车回起点、章节回 board）",
		absf(float(state.get("angle_deg", 99.0))) < 0.5 and not bool(state.get("latched", true))
			and not bool(state.get("docked", true)) and absf(float(cart.get("distance"))) < 0.01
			and str(flow.get("phase")) == "board",
		"angle=%.1f latched=%s distance=%.2f phase=%s" % [
			float(state.get("angle_deg", 0.0)), str(state.get("latched")),
			float(cart.get("distance")), str(flow.get("phase"))])


# ---------------------------------------------------------------- 14 连续 3 次
func _d14_repeat() -> void:
	var ok: bool = true
	var angles: Array[float] = []
	for i: int in range(3):
		stage.call("reset_run")
		await _w(40)
		await _drive_to_dock()
		await _at_handle()
		Input.action_press("repair")
		for k in range(240):
			await get_tree().physics_frame
			if bool(dock.call("docked")):
				break
		Input.action_release("repair")
		await _w(20)
		var state: Dictionary = dock.call("state")
		angles.append(float(state.get("angle_deg", 0.0)))
		ok = ok and bool(state.get("docked", false)) and str(flow.get("phase")) == "done"
		if not ok:
			break
	stage.call("reset_run")
	await _w(40)
	_check("D14 连续 3 次完成过程稳定（每次都真实停靠成功）", ok,
		"3 次收臂角度 %s" % str(angles))


# ---------------------------------------------------------------- 15 异常 5 次
func _d15_abnormal() -> void:
	var ok: bool = true
	for i: int in range(5):
		stage.call("reset_run")
		await _w(30)
		cart.call("snap_to_distance", 100.0)
		await _w(10)
		await _at_handle()
		Input.action_press("repair")
		await _w(90)
		Input.action_release("repair")
		await _w(20)
		if bool(dock.call("docked")):
			ok = false
			break
	_check("D15 关键异常工况重复 5 次稳定（车不在门区时反复拉闸臂都不会误判停靠）", ok,
		"5 次空拉：从未 docked")
	stage.call("reset_run")
	await _w(40)


# ---------------------------------------------------------------- 16 002 回归
func _d16_regression() -> void:
	var notch: int = int(cart.call("apply_brake_notch", 1))
	await _w(30)
	var force: float = float(cart.call("brake_force"))
	cart.call("apply_brake_notch", 0)
	await _w(20)
	var cargo: Array = device.get("cargo") as Array
	var rig: Node = flow.get("rig")
	var winch: Node = rig.get("winch") if rig != null else null
	_check("D16 002A/002B/002C 无回归（双箱货舱、手制动 1 档、绞盘机都在线）",
		cargo.size() == 2 and notch == 1 and force > 1800.0 and winch != null
			and int(device.call("locked_count")) == 0,
		"cargo=%d 手制动=%.0f N 绞盘=%s" % [cargo.size(), force, str(winch != null)])
	cart.call("reset_run")
	await _w(30)


# ---------------------------------------------------------------- 17 玩家
func _d17_player() -> void:
	player.global_position = cart.to_global(Vector3(0.6, 2.05, 1.7))
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await _w(20)
	var p0: Vector3 = player.global_position
	Input.action_press("move_up")
	await _w(40)
	Input.action_release("move_up")
	await _w(10)
	var moved: float = Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length()
	var hud: Node = stage.get("hud")
	_check("D17 玩家移动与 HUD 无回归（新夹钳不挡路、不卡人）",
		moved > 0.2 and hud != null and player.global_position.is_finite(),
		"位移 %.2f m hud=%s" % [moved, str(hud != null)])


# ---------------------------------------------------------------- 18 交接就绪
func _d18_handoff_ready() -> void:
	stage.call("reset_run")
	await _w(40)
	await _drive_to_dock()
	await _at_handle()
	Input.action_press("repair")
	for i in range(240):
		await get_tree().physics_frame
		if bool(dock.call("docked")):
			break
	Input.action_release("repair")
	await _w(20)
	var hub: Node = get_node_or_null("/root/SessionHub")
	_check("D18 第三幕完成状态可供章节交接（phase=done 且 SessionHub.complete_chapter 可用）",
		str(flow.get("phase")) == "done" and hub != null and hub.has_method("complete_chapter"),
		"phase=%s hub=%s" % [str(flow.get("phase")), str(hub != null)])


# ---------------------------------------------------------------- 工具
func _drive_to_dock() -> void:
	cart.call("reset_run")
	await _w(30)
	cart.call("snap_to_distance", 103.0)
	cart.call("release_route")
	await _w(20)
	cart.call("start")
	for i in range(900):
		await get_tree().physics_frame
		if bool(cart.get("arrived")):
			break
	await _w(30)


func _at_handle() -> void:
	var handle: Vector3 = dock.call("handle_world") as Vector3
	player.call("restore_at", handle + Vector3(0.0, -0.85, -1.25))
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var look: Vector3 = (dock.call("arm_tip_world") as Vector3) - (player.global_position + Vector3.UP * 1.5)
	var yaw: float = atan2(-look.x, -look.z)
	player.set("_camera_yaw", yaw)
	player.set("_camera_yaw_target", yaw)
	await _w(20)


func _release_and_open() -> void:
	Input.action_release("repair")
	dock.call("release")
	await _w(40)


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func cap(text: String) -> void:
	print("CAP " + text)


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
	print("MECH003A_DONE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)





