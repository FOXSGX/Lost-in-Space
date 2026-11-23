extends Node
## MECHANICS-001F · 共振星第一幕"真实货舱固定带与载重约束"专项
##
## 全部断言在正式 act01.tscn 实例中真实执行：货箱是 RigidBody3D，
## 张力是"只能受拉"的弹性索模型算出来的力，直接作用在货箱刚体上。
## 关键工况记录：mass / force / displacement / velocity / tension /
##                anchor_position / ratchet_state / cargo_secured
## 失败时退出码非零。

const FORCE_N := 600.0
const FORCE_FRAMES := 60

var app: Node
var rig: Act1CargoRig
var failures: int = 0
var checks: int = 0
var ev: Array = []


func _ready() -> void:
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	app = ps.instantiate()
	add_child(app)
	await _w(120)
	rig = app.builder.cargo_rig
	if rig == null or rig.crate == null:
		_fail("F0", "正式场景里没有货舱固定带系统")
		return _report()

	await _f01_cargo_structure()
	await _f02_anchors()
	await _f03_initial_slack()
	await _f04_e_does_not_set_flag()
	await _f05_ratchet_moves()
	await _f06_tension_real()
	await _f07_tension_on_body()
	await _f08_unfixed_moves()
	await _f09_fixed_holds()
	await _f10_released_moves_again()
	await _f11_under_tension_blocks_launch()
	await _f12_off_zone()
	await _f13_latch_positions()
	await _f14_departure_stable()
	await _f15_overload()
	await _f16_reset()
	await _f17_five_cycles()
	await _f18_launch_conditions()
	await _f19_flow_order()
	await _f20_player_reach()
	await _f21_mass_variants()
	_report()


# ---------------------------------------------------------------- 1 结构
func _f01_cargo_structure() -> void:
	var body_ok := rig.crate is RigidBody3D and rig.crate.mass >= 90.0
	var shape_ok := false
	for c in rig.crate.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var bs: BoxShape3D = (c as CollisionShape3D).shape
			shape_ok = bs.size.x > 0.8 and bs.size.y > 0.7 and bs.size.z > 0.8
	var local: Vector3 = rig.to_local(rig.crate.global_position)
	var on_deck := absf(local.x - Act1CargoRig.CRATE_CENTER.x) < 0.06 \
		and absf(local.z - Act1CargoRig.CRATE_CENTER.z) < 0.06 \
		and absf(local.y - (Act1CargoRig.DECK_Y + Act1CargoRig.CRATE_HALF.y)) < 0.03
	var real_body := not rig.crate.freeze and rig.crate.collision_layer == 4 \
		and rig.crate.get_parent() == app
	_check("F1 货舱实际货物是真实刚体（有质量/碰撞，未冻结，不挂在矿车下）",
		body_ok and shape_ok and on_deck and real_body,
		"mass=%.0f layer=%d 世界父节点=%s 局部位置=%s 碰撞盒=%s" % [
			rig.crate.mass, rig.crate.collision_layer, rig.crate.get_parent().name,
			str(local.snapped(Vector3(0.001, 0.001, 0.001))), str(shape_ok)])


# ---------------------------------------------------------------- 2 锚点
func _f02_anchors() -> void:
	var ok: bool = rig.cart == app.builder.mine_cart and rig.get_parent() == rig.cart
	var a0: Vector3 = rig._world(Act1CargoRig.DRUM_ANCHOR)
	var z_before: float = rig.cart.global_position.z
	rig.cart.global_position.z = z_before - 1.5
	await _w(2)
	var a1: Vector3 = rig._world(Act1CargoRig.DRUM_ANCHOR)
	rig.cart.global_position.z = z_before
	await _w(2)
	var followed: bool = absf((a1 - a0).z + 1.5) < 0.01 and absf(a0.distance_to(a1) - 1.5) < 0.01
	_check("F2 固定带锚点是矿车上的实体硬件，并随矿车运动",
		ok and followed,
		"锚点 世界 %s → 随车移动后 %s；货台四点（卷筒+两挂钩）局部 %s/%s/%s" % [
			str(a0.snapped(Vector3(0.001, 0.001, 0.001))),
			str(a1.snapped(Vector3(0.001, 0.001, 0.001))),
			str(Act1CargoRig.DRUM_ANCHOR), str(Act1CargoRig.HOOK_A), str(Act1CargoRig.HOOK_B)])


# ---------------------------------------------------------------- 3 初始松弛
func _f03_initial_slack() -> void:
	rig.reset_cargo()
	await _w(30)
	var slack: float = rig.rest_length(rig._loops[0]) - float(rig._loops[0]["L"])
	_check("F3 初始固定带松弛、棘轮未张紧、货物未固定",
		rig.clicks == 0 and rig.tension() < Act1CargoRig.TAUT_EPS
			and slack > 0.06 and not rig.secured() and not bool(app.flags["cargo_secured"]),
		"clicks=0 张力=%.1f N 几何长度=%.3f 静止长度=%.3f 松弛=%.3f m secured=false" % [
			rig.tension(), float(rig._loops[0]["L"]), rig.rest_length(rig._loops[0]), slack])


# ---------------------------------------------------------------- 4 E 不直接完成
func _f04_e_does_not_set_flag() -> void:
	app.flags["chock_removed"] = true
	app.flags["brake_released"] = true
	app.flags["cargo_secured"] = false
	await _w(2)
	_press_cargo()
	await _w(2)
	var immediate := bool(app.flags["cargo_secured"])
	await _w(45)
	_check("F4 按一次 E 不直接置 cargo_secured（E 只启动一个棘轮行程）",
		not immediate and not bool(app.flags["cargo_secured"]) and rig.clicks == 1,
		"按下瞬间 flag=%s；45 帧后 flag=%s clicks=%d 张力=%.0f N" % [
			str(immediate), str(app.flags["cargo_secured"]), rig.clicks, rig.tension()])


# ---------------------------------------------------------------- 5 棘轮真运动
func _f05_ratchet_moves() -> void:
	rig.reset_cargo()
	await _w(20)
	var turns0: float = rig.drum_turns
	_press_cargo()
	var mid_lever := 0.0
	for i in range(40):
		await get_tree().physics_frame
		mid_lever = maxf(mid_lever, rig.lever_angle)
	var handed := rig.clicks == 1 and mid_lever > 0.8
	await _w(20)
	_check("F5 张紧机构真实运动（手柄行程 + 卷筒转角 + 棘爪落位）",
		handed and rig.drum_turns > turns0 + 0.2 and rig.pawl_depth > 0.9,
		"手柄最大角=%.2f rad 卷筒转角 %.3f → %.3f rad 棘爪深度=%.2f clicks=%d" % [
			mid_lever, turns0, rig.drum_turns, rig.pawl_depth, rig.clicks])


# ---------------------------------------------------------------- 6 真张力
func _f06_tension_real() -> void:
	await _pump_until_secured()
	var t := rig.tension()
	var rest: float = rig.rest_length(rig._loops[0])
	var L: float = float(rig._loops[0]["L"])
	_check("F6 固定带真实产生张力（张力 = 刚度 × 伸长量，且不超过额定值）",
		t > Act1CargoRig.SECURE_TENSION and L >= rest - 0.002 and t <= Act1CargoRig.MAX_TENSION,
		"clicks=%d 卷绕=%.3f 静止长度=%.3f 几何长度=%.3f 伸长=%.4f m 张力=%.0f N" % [
			rig.clicks, rig.take_up(), rest, L, L - rest, t])


# ---------------------------------------------------------------- 7 力作用在刚体上
func _f07_tension_on_body() -> void:
	var t0 := rig.tension()
	var p0: Vector3 = rig.to_local(rig.crate.global_position)
	for i in range(30):
		rig.crate.apply_central_force(Vector3(0, 0, -800.0))
		await get_tree().physics_frame
	var t1 := rig.tension()
	var p1: Vector3 = rig.to_local(rig.crate.global_position)
	_ev("F7", 0.0, 800.0, (p1 - p0).length(), rig.crate.linear_velocity.length(), t1, rig.secured())
	_check("F7 张力随货物相对运动真实变化，并直接作用在货物刚体上",
		absf(t1 - t0) > 30.0 and (p1 - p0).length() < 0.12 and t1 <= Act1CargoRig.MAX_TENSION,
		"张力 %.0f → %.0f N；货物局部位移=%.4f m；速度=%.3f m/s" % [
			t0, t1, (p1 - p0).length(), rig.crate.linear_velocity.length()])
	rig.reset_cargo()
	await _w(20)


# ---------------------------------------------------------------- 8 A：未固定
func _f08_unfixed_moves() -> void:
	rig.reset_cargo()
	await _w(40)
	var r := await _force_case("A 未固定（初始松弛）")
	_check("F8 固定前：同一外力下货物可以被明显推动",
		r["disp"] > 0.05 and r["peak_v"] > 0.25,
		"力=%.0f N×%d 帧 disp=%.3f m 峰值速度=%.2f m/s 张力=%.0f N secured=false" % [
			FORCE_N, FORCE_FRAMES, r["disp"], r["peak_v"], r["tension"]])


# ---------------------------------------------------------------- 9 B：固定
func _f09_fixed_holds() -> void:
	rig.reset_cargo()
	await _w(30)
	await _pump_until_secured()
	var before := rig.tension()
	var r := await _force_case("B 真实张紧固定")
	var a_disp := float(_case_a_disp)
	_check("F9 固定后：相同外力下位移显著减少（A/B 对照）",
		r["disp"] < 0.06 and r["disp"] < a_disp * 0.35 and rig.secured(),
		"力=%.0f N×%d 帧 disp=%.4f m（A 为 %.3f m） 张力 %.0f→%.0f N secured=%s" % [
			FORCE_N, FORCE_FRAMES, r["disp"], a_disp, before, r["tension"], str(rig.secured())])


# ---------------------------------------------------------------- 10 C：解除
func _f10_released_moves_again() -> void:
	app._execute_interaction(int(app.local_pid), "cargo_latch", "press")
	await _w(180)
	var released_ok := rig.latch_open and rig.clicks == 0 and rig.payout > 0.2 and not rig.secured()
	var r := await _force_case("C 真实解除固定")
	var b_disp := float(_case_b_disp)
	_check("F10 通过机械锁扣解除后：货物恢复合理移动",
		released_ok and r["disp"] > 0.05 and r["disp"] > b_disp * 2.0 and not rig.secured(),
		"锁扣打开=%s clicks=%d 放出带长=%.2f m；disp=%.3f m（B 为 %.3f m） 张力=%.0f N" % [
			str(rig.latch_open), rig.clicks, rig.payout, r["disp"], b_disp, r["tension"]])
	rig.reset_cargo()
	await _w(20)


# ---------------------------------------------------------------- 11 张力不足
func _f11_under_tension_blocks_launch() -> void:
	rig.reset_cargo()
	await _w(20)
	app.flags["chock_removed"] = true
	app.flags["brake_released"] = true
	app.flags["vent_complete"] = true
	app.flags["cargo_secured"] = false
	for i in range(6):
		if rig.lever_busy():
			await _w(10)
			continue
		_press_cargo()
		await _w(45)
	var t := rig.tension()
	# 同一帧内读联锁：主机每帧会用真实机构状态回写 brake_released，跨帧读会读到机构真值
	app.flags["chock_removed"] = true
	app.flags["brake_released"] = true
	var blocked := not bool(app._launch_conditions_ok())
	var reason: String = str(app._launch_block_reason())
	_check("F11 张力不足时不允许发车（联锁读真实张力，不读“按过 E”）",
		blocked and t < Act1CargoRig.SECURE_TENSION and reason.find("固定带") >= 0,
		"clicks=%d 张力=%.0f N（阈值 %.0f）launch_ok=false 拒绝原因=%s" % [
			rig.clicks, t, Act1CargoRig.SECURE_TENSION, reason])


# ---------------------------------------------------------------- 12 偏位
func _f12_off_zone() -> void:
	rig.reset_cargo()
	await _w(20)
	rig.crate.global_position = rig.global_transform * (Act1CargoRig.CRATE_CENTER + Vector3(0.0, 0.0, 1.25))
	rig.crate.linear_velocity = Vector3.ZERO
	await _w(20)
	var in_zone: bool = rig.crate_in_zone()
	var pumped: bool = rig.pump()
	await _w(45)
	_check("F12 货物偏位时不能隔空固定",
		(not in_zone) and (not pumped) and not rig.secured() and not bool(app.flags["cargo_secured"]),
		"货物局部位置=%s 在有效区域=%s 棘轮可张紧=%s secured=false" % [
			str(rig.to_local(rig.crate.global_position).snapped(Vector3(0.01, 0.01, 0.01))),
			str(in_zone), str(pumped)])
	rig.reset_cargo()
	await _w(30)


# ---------------------------------------------------------------- 13 锁扣
func _f13_latch_positions() -> void:
	await _pump_until_secured()
	var pawl_locked: float = rig.pawl_depth
	var latch_enabled: bool = rig.latch_point.enabled
	var locked_ok := pawl_locked > 0.95 and not rig.latch_open and rig.secured() and latch_enabled
	app._execute_interaction(int(app.local_pid), "cargo_latch", "press")
	await _w(60)
	var pawl_released: float = rig.pawl_depth
	var open_ok := rig.latch_open and pawl_released < 0.05 and not rig.secured() \
		and not bool(app.flags["cargo_secured"])
	_check("F13 机械锁扣真实到位：棘爪落入齿槽=锁定，抬起=释放",
		locked_ok and open_ok,
		"锁定：棘爪=%.2f 锁扣手柄可用=%s；释放：锁扣打开=%s 棘爪=%.2f secured=false" % [
			pawl_locked, str(latch_enabled), str(rig.latch_open), pawl_released])


# ---------------------------------------------------------------- 14 发车稳定
func _f14_departure_stable() -> void:
	rig.reset_cargo()
	await _w(30)
	await _pump_until_secured()
	var p0: Vector3 = rig.to_local(rig.crate.global_position)
	var t0 := rig.tension()
	# 让矿车按原有剧情发车（把本地玩家放到车厢里，走真实 begin_departure 路径）
	app.local_player.global_position = app.builder.mine_cart.global_transform * Vector3(0, 1.6, 0)
	await _w(4)
	app.builder.mine_cart.begin_departure()
	var max_drift := 0.0
	for i in range(180):
		await get_tree().physics_frame
		var d: float = rig.to_local(rig.crate.global_position).distance_to(p0)
		max_drift = maxf(max_drift, d)
	var p1: Vector3 = rig.to_local(rig.crate.global_position)
	var speed: float = app.builder.mine_cart.speed
	_ev("F14", 0.0, 0.0, (p1 - p0).length(), rig.crate.linear_velocity.length(), rig.tension(), rig.secured())
	_check("F14 正常矿车起步（0→6.4 m/s）时货物保持合理稳定",
		speed > 4.0 and max_drift < 0.40 and rig.crate_in_zone() and rig.secured(),
		"矿车速度=%.2f m/s 相对货台最大漂移=%.3f m 末位移=%.3f m 张力 %.0f→%.0f N 在区域=%s" % [
			speed, max_drift, (p1 - p0).length(), t0, rig.tension(), str(rig.crate_in_zone())])
	app.builder.mine_cart.reset_cart()
	rig.reset_cargo()
	app.local_player.teleport(Act1App.SPAWN, 0.0, -0.05)
	app.flags["departure_started"] = false
	app.flags["completed"] = false
	await _w(60)


# ---------------------------------------------------------------- 15 过载
func _f15_overload() -> void:
	rig.reset_cargo()
	await _w(30)
	await _pump_until_secured()
	var tmax := 0.0
	var finite := true
	for i in range(90):
		rig.crate.apply_central_force(Vector3(0, 0, -6000.0))
		await get_tree().physics_frame
		tmax = maxf(tmax, rig.tension())
		if not rig.crate.global_position.is_finite() or not is_finite(rig.tension()):
			finite = false
	var local: Vector3 = rig.to_local(rig.crate.global_position)
	var inside: bool = absf(local.x) < 4.4 and absf(local.z) < 4.4
	_ev("F15", 0.0, 6000.0, (local - Act1CargoRig.CRATE_CENTER).length(), rig.crate.linear_velocity.length(), tmax, rig.secured())
	_check("F15 过载时有合理响应（张力被额定值限制，不发散、不弹飞）",
		finite and tmax <= Act1CargoRig.MAX_TENSION + 1.0 and inside,
		"力=6000 N×90 帧 峰值张力=%.0f N（额定 %.0f）货物局部=%s 仍在货台=%s" % [
			tmax, Act1CargoRig.MAX_TENSION, str(local.snapped(Vector3(0.01, 0.01, 0.01))), str(inside)])
	rig.reset_cargo()
	await _w(30)


# ---------------------------------------------------------------- 16 复位
func _f16_reset() -> void:
	await _pump_until_secured()
	app._reset_state()
	await _w(60)
	var local: Vector3 = rig.to_local(rig.crate.global_position)
	var ok := rig.clicks == 0 and rig.tension() < Act1CargoRig.TAUT_EPS and rig.payout == 0.0 \
		and not rig.latch_open and not bool(app.flags["cargo_secured"]) \
		and local.distance_to(Act1CargoRig.CRATE_CENTER) < 0.05 \
		and rig.crate.linear_velocity.length() < 0.05
	_check("F16 R 复位后货物、固定带、棘轮、锁扣全部回到初始状态",
		ok,
		"clicks=0 张力=%.1f 放出=%.2f 锁扣=%s flag=%s 货物局部=%s 速度=%.3f" % [
			rig.tension(), rig.payout, str(rig.latch_open), str(app.flags["cargo_secured"]),
			str(local.snapped(Vector3(0.001, 0.001, 0.001))), rig.crate.linear_velocity.length()])


# ---------------------------------------------------------------- 17 五轮
func _f17_five_cycles() -> void:
	var all_ok := true
	var lines: Array = []
	for n in range(5):
		await _pump_until_secured()
		var t_hi := rig.tension()
		app._execute_interaction(int(app.local_pid), "cargo_latch", "press")
		await _w(180)
		var t_lo := rig.tension()
		var ok := t_hi > Act1CargoRig.SECURE_TENSION and t_lo < Act1CargoRig.TAUT_EPS \
			and rig.clicks == 0 and not rig.secured()
		all_ok = all_ok and ok
		lines.append("#%d %s→%s N" % [n + 1, str(int(t_hi)), str(int(t_lo))])
		if not ok:
			break
	_check("F17 连续 5 轮张紧/释放无异常、无发散",
		all_ok, "张力序列 " + ", ".join(lines))


# ---------------------------------------------------------------- 18 原有联锁
func _f18_launch_conditions() -> void:
	await _pump_until_secured()
	app.flags["chock_removed"] = true
	app.flags["brake_released"] = true
	var cond := {
		"vent": bool(app.flags["vent_complete"]),
		"chock": bool(app.flags["chock_removed"]),
		"brake": bool(app.flags["brake_released"]),
		"cargo": bool(app.flags["cargo_secured"]),
	}
	app.flags["chock_removed"] = false
	var chock_blocks := not bool(app._launch_conditions_ok())
	app.flags["chock_removed"] = true
	app.flags["brake_released"] = false
	var brake_blocks := not bool(app._launch_conditions_ok())
	app.flags["brake_released"] = true
	var cargo_ok := bool(app.flags["cargo_secured"])
	_check("F18 原有发车条件仍然有效（止轮楔/停车制动照旧拦截，货舱项由真实机构给出）",
		chock_blocks and brake_blocks and cargo_ok and cond["cargo"],
		"止轮楔缺失→拒绝=%s 制动未解除→拒绝=%s 货舱 flag=%s（真实 secured=%s）" % [
			str(chock_blocks), str(brake_blocks), str(cargo_ok), str(rig.secured())])


# ---------------------------------------------------------------- 19 流程顺序
func _f19_flow_order() -> void:
	rig.reset_cargo()
	await _w(30)
	app.flags["chock_removed"] = false
	app.flags["brake_released"] = false
	app.flags["cargo_secured"] = false
	var before_ok := true
	app.flags["chock_removed"] = false
	app.flags["brake_released"] = false
	app._execute_interaction(int(app.local_pid), "cargo", "press")
	await _w(40)
	var clicks_no_chock: int = rig.clicks
	before_ok = before_ok and clicks_no_chock == 0 and not bool(app.flags["cargo_secured"])
	app.flags["chock_removed"] = true
	app.flags["brake_released"] = false
	app._execute_interaction(int(app.local_pid), "cargo", "press")
	await _w(40)
	var clicks_no_brake: int = rig.clicks
	var mid_ok := clicks_no_brake == 0 and not bool(app.flags["cargo_secured"])
	app.flags["brake_released"] = true
	await _pump_until_secured()
	_check("F19 第一幕发车顺序不受影响：止轮楔 → 停车制动 → 货舱固定带",
		before_ok and mid_ok and rig.secured() and bool(app.flags["cargo_secured"]),
		"缺止轮楔时 clicks=%d；缺制动时 clicks=%d；两者满足后真实张紧 secured=%s" % [
			clicks_no_chock, clicks_no_brake, str(rig.secured())])


# ---------------------------------------------------------------- 20 玩家可达性
func _f20_player_reach() -> void:
	rig.reset_cargo()
	await _w(20)
	var p := app.local_player as Act1StationPlayer
	app.flags["chock_removed"] = true
	app.flags["brake_released"] = true
	# 站在发车站台上、面向矿车货舱
	p.global_position = Vector3(5.35, 1.53, -47.10)
	p.look_at_point(rig.pump_point.global_position)
	await _w(6)
	p._update_interaction()
	var target: Node = p.current_target
	var prompt: String = p.current_prompt
	_press_cargo()
	var pumped := rig.lever_busy() or rig.clicks > 0
	await _w(45)
	_check("F20 正式玩家基础交互正常（站台上能看见并操作货舱棘轮）",
		target != null and target == rig.pump_point and prompt.find("固定带") >= 0 and pumped,
		"瞄准目标=%s 提示=%s 交互距离=%.2f m 已启动行程=%s" % [
			"cargo" if target == rig.pump_point else str(target),
			prompt, p.global_position.distance_to(rig.pump_point.global_position), str(pumped)])


# ---------------------------------------------------------------- 21 不同货物质量
func _f21_mass_variants() -> void:
	var rows: Array = []
	var ok := true
	for m in [60.0, 100.0, 160.0]:
		rig.reset_cargo()
		rig.crate.mass = m
		await _w(30)
		await _pump_until_secured()
		var r := await _force_case("质量 %.0f kg · 固定后 600 N" % m)
		rows.append("m=%.0fkg T=%.0fN disp=%.4fm v=%.2f secured=%s" % [
			m, r["tension"], r["disp"], r["peak_v"], str(rig.secured())])
		ok = ok and rig.secured() and r["disp"] < 0.10
	rig.crate.mass = Act1CargoRig.CRATE_MASS
	rig.reset_cargo()
	await _w(30)
	_check("F21 不同货物质量（60/100/160 kg）下固定带都能约束住货物",
		ok, "; ".join(rows))


# ---------------------------------------------------------------- 工具
var _case_a_disp := 0.0
var _case_b_disp := 0.0


func _pump_until_secured() -> void:
	for i in range(12):
		if rig.secured():
			return
		if rig.lever_busy():
			await _w(10)
			continue
		_press_cargo()
		await _w(48)


## 专项按任务书允许的方式预置前置状态（止轮楔/停车制动），
## 两者必须在**同一帧内**置位并按键，否则主机同步会把它们拉回真实机构状态。
func _press_cargo() -> void:
	app.flags["chock_removed"] = true
	app.flags["brake_released"] = true
	app._execute_interaction(int(app.local_pid), "cargo", "press")


func _force_case(tag: String) -> Dictionary:
	var p0: Vector3 = rig.to_local(rig.crate.global_position)
	var peak := 0.0
	for i in range(FORCE_FRAMES):
		rig.crate.apply_central_force(Vector3(0, 0, -FORCE_N))
		await get_tree().physics_frame
		peak = maxf(peak, rig.crate.linear_velocity.length())
	var p1: Vector3 = rig.to_local(rig.crate.global_position)
	var out := {
		"disp": (p1 - p0).length(),
		"peak_v": peak,
		"tension": rig.tension(),
		"secured": rig.secured(),
	}
	_ev(tag, rig.crate.mass, FORCE_N, out["disp"], peak, rig.tension(), rig.secured())
	if tag.begins_with("A"):
		_case_a_disp = out["disp"]
	elif tag.begins_with("B"):
		_case_b_disp = out["disp"]
	return out


## 关键物理量统一记录（供报告引用）
func _ev(tag: String, mass: float, force: float, disp: float, vel: float, tension: float, secured: bool) -> void:
	var anchor: Vector3 = rig._world(Act1CargoRig.DRUM_ANCHOR) if rig != null else Vector3.ZERO
	var line := "EVID %s | mass=%.1fkg force=%.0fN displacement=%.4fm velocity=%.3fm/s tension=%.1fN anchor=(%.2f,%.2f,%.2f) ratchet=(clicks=%d,pawl=%.2f,latch=%s) cargo_secured=%s crate_local=(%.3f,%.3f,%.3f)" % [
		tag, mass, force, disp, vel, tension, anchor.x, anchor.y, anchor.z,
		rig.clicks, rig.pawl_depth, str(rig.latch_open), str(secured),
		rig.to_local(rig.crate.global_position).x,
		rig.to_local(rig.crate.global_position).y,
		rig.to_local(rig.crate.global_position).z]
	print(line)
	ev.append(line)


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _is_finite(v: float) -> bool:
	return not (is_nan(v) or is_inf(v))


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
	print("MECH001F_DONE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
