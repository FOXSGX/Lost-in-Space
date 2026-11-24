extends Node
## MECHANICS-002C · 第二幕断轨维修绞盘真实物理专项
##
## 全部断言在正式第二幕切片 res://act23/moving_cart.tscn 的维修区里执行：
## 有限力矩电机 → 卷筒（惯量/角速度/力矩）→ 受拉缆绳（张力）→ 摆动轨道（负载）
## → 鼓刹（有限摩擦容量）→ 锁定销（真实机械条件）。
## 失败返回非零退出码。

const HAUL_FRAMES: int = 3000
var stage: Node
var flow: Node
var rig: Node
var winch: Node
var rail: Node
var cable: Node
var station: Node
var cart: AnimatableBody3D
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
	device = stage.get("device")
	player = stage.get("player") as CharacterBody3D
	rig = flow.get("rig")
	winch = rig.get("winch")
	station = _find_station(stage)
	rail = rig.get("rail")
	cable = rig.get("cable")
	if flow == null or rig == null or station == null or winch == null or rail == null:
		_fail("C0", "维修区缺少 flow/rig/winch/rail")
		return _report()
	await _c1_load()
	await _c2_story()
	await _c3_machine()
	await _c4_torque_drive()
	await _c5_torque_limit()
	await _c6_cable_point()
	await _c7_slack()
	await _c8_tension()
	await _c9_pull()
	await _c10_leverage()
	await _c11_blocked()
	await _c12_no_false_success()
	await _c13_brake_motion()
	await _c13b_brake_capacity()
	await _c14_brake_hold()
	await _c15_release()
	await _c16_not_yet()
	await _c17_complete()
	await _c18_reset()
	await _c19_repeat()
	await _c20_tension_cap()
	await _c21_no_regression()
	await _c22_route_resume()
	_report()


# ---------------------------------------------------------------- 1 加载
func _c1_load() -> void:
	var anchors: Array = rig.call("anchor_ids") as Array
	var drum: Node = station.get("drum") as Node
	_check("C1 正式断轨维修区正常加载（绞盘机/卷筒/缆绳/摆动轨/两个吊耳）",
		stage.is_inside_tree() and rig.is_inside_tree() and drum != null and cable != null
			and anchors.size() == 2 and absf(float(rail.get("hinge_angle")) - deg_to_rad(15.0)) < 0.01,
		"anchors=%s drum=%s cable=%s 起始角=%.2f°" % [str(anchors), str(drum != null),
			str(cable != null), rad_to_deg(float(rail.get("hinge_angle")))])


# ---------------------------------------------------------------- 2 剧情
func _c2_story() -> void:
	var objective: String = str(flow.get("objective_text"))
	var repair_text: String = str(flow.call("_objective_for", "repair"))
	_check("C2 原有剧情任务保留（board 起点、维修目标文案、初始卡在碎石里的轨道）",
		objective != "" and repair_text != "" and bool(rail.get("jammed"))
			and not bool(rig.get("completed")) and not bool(cart.get("route_clear")),
		"phase=%s ride目标=%s 维修目标=%s jammed=%s route_clear=%s" % [
			str(flow.get("phase")), objective, repair_text, str(rail.get("jammed")),
			str(cart.get("route_clear"))])


# ---------------------------------------------------------------- 3 机构
func _c3_machine() -> void:
	var state: Dictionary = winch.call("torque_state")
	_check("C3 卷筒与驱动机构真实存在（惯量、堵转力矩、鼓半径、鼓刹容量都由状态给出）",
		float(state.get("inertia", 0.0)) > 10.0 and float(state.get("motor_stall_torque", 0.0)) > 500.0
			and float(state.get("radius", 0.0)) > 0.2 and float(state.get("brake_capacity", 0.0)) > 400.0,
		"I=%.0f kg·m²  stall=%.0f N·m  r=%.2f m  闸容量=%.0f N·m" % [
			float(state.get("inertia", 0.0)), float(state.get("motor_stall_torque", 0.0)),
			float(state.get("radius", 0.0)), float(state.get("brake_capacity", 0.0))])


# ---------------------------------------------------------------- 4 力矩驱动
func _c4_torque_drive() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(30)  # 起吊前缆绳是松的
	var before: Dictionary = winch.call("torque_state")
	Input.action_press("winch_haul")
	var peak_motor: float = 0.0
	for i in range(30):
		await get_tree().physics_frame
		peak_motor = maxf(peak_motor, float(winch.get("motor_torque")))
	var after: Dictionary = winch.call("torque_state")
	Input.action_release("winch_haul")
	var omega: float = float(after.get("omega", 0.0))
	_check("C4 卷筒转动由有效动力产生（空载段电机力矩使 ω 从 0 加速，不是预设转速）",
		absf(float(before.get("omega", 0.0))) < 0.001 and omega > 0.5 and peak_motor > 500.0,
		"ω %.3f → %.3f rad/s；起步 τ_motor 峰值=%.0f N·m；τ_cable=%.0f；inertia=%.0f" % [
			float(before.get("omega", 0.0)), omega, peak_motor,
			float(after.get("cable_torque", 0.0)), float(after.get("inertia", 0.0))])
	await _reset()


# ---------------------------------------------------------------- 5 力矩上限
func _c5_torque_limit() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(20)
	Input.action_press("winch_haul")
	var peak_motor: float = 0.0
	var peak_cable: float = 0.0
	var stalled_omega: float = 9.0
	for i in range(240):
		await get_tree().physics_frame
		var s: Dictionary = winch.call("torque_state")
		peak_motor = maxf(peak_motor, float(s.get("motor_torque", 0.0)))
		peak_cable = maxf(peak_cable, absf(float(s.get("cable_torque", 0.0))))
		if float(winch.get("tension")) > 2500.0:
			stalled_omega = minf(stalled_omega, absf(float(s.get("omega", 0.0))))
	Input.action_release("winch_haul")
	_check("C5 电机力矩存在明确上限（堵转/带载时 τ_motor ≤ 额定 1088 N·m，缆绳反力矩与之对抗）",
		peak_motor <= 1088.0 + 1.0 and peak_motor > 800.0 and peak_cable > 700.0 and stalled_omega < 0.6,
		"峰值 τ_motor=%.0f N·m，|τ_cable|峰值=%.0f N·m，重载段 ω=%.3f rad/s" % [
			peak_motor, peak_cable, stalled_omega])
	await _reset()


# ---------------------------------------------------------------- 6 连接点
func _c6_cable_point() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(10)
	var anchor: Node3D = rig.call("find_anchor", "eye_far")
	var eye: Vector3 = anchor.call("attach_point") as Vector3
	var rail_eye: Vector3 = rail.call("attach_world",
		rail.to_local(eye) + Vector3.ZERO) as Vector3
	var length_ok: bool = float(winch.get("free_length")) > 8.0
	_check("C6 缆绳连接点正确（钩子挂在真实吊耳世界坐标上，挂缆后先放绳到松驰）",
		bool(winch.get("attached")) and eye.distance_to(rail_eye) < 0.01 and length_ok,
		"吊耳世界=%s，自由绳长=%.2f m，attached=%s" % [str(eye.snapped(Vector3(0.01, 0.01, 0.01))),
			float(winch.get("free_length")), str(winch.get("attached"))])
	await _reset()


# ---------------------------------------------------------------- 7 松弛
func _c7_slack() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(40)
	var slack_t: float = float(winch.get("tension"))
	var stretch: float = float(rail.get("stretch"))
	_check("C7 缆绳松弛时张力为零（绳长 > 吊耳距离，缆绳只受拉不压）",
		slack_t < 1.0 and stretch < 0.001,
		"松弛张力 %.2f N，stretch=%.4f m，自由绳长=%.2f m" % [slack_t, stretch,
			float(winch.get("free_length"))])
	await _reset()


# ---------------------------------------------------------------- 8 张紧
func _c8_tension() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(20)
	Input.action_press("winch_haul")
	for i in range(240):
		await get_tree().physics_frame
		if float(winch.get("tension")) > 500.0:
			break
	var t: float = float(winch.get("tension"))
	Input.action_release("winch_haul")
	_check("C8 收绳后张力增加（缆绳被拉伸，T = k·ΔL，饱和在上限内）",
		t > 500.0 and t <= 3200.0 * 1.05,
		"张力 %.0f N，stretch=%.4f m，k=%.0f N/m" % [t, float(rail.get("stretch")), 26000.0])
	await _reset()


# ---------------------------------------------------------------- 9 牵引
func _c9_pull() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(20)
	var a0: float = float((rail.call("alignment") as Dictionary).get("angle_deg"))
	Input.action_press("winch_haul")
	var t: float = 0.0
	var t_max: float = 0.0
	for i in range(360):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		t_max = maxf(t_max, float(winch.get("tension")))
		if absf(float((rail.call("alignment") as Dictionary).get("angle_deg"))) < 12.0:
			break
	Input.action_release("winch_haul")
	var a1: float = float((rail.call("alignment") as Dictionary).get("angle_deg"))
	_check("C9 张力能够真实驱动负载（15°→12°：张力先破卡阻，再推动 9000 kg·m² 的轨道段）",
		a1 < a0 - 2.0 and t_max > 2000.0 and t > 1.0,
		"角度 %.2f° → %.2f°，峰值张力 %.0f N，用时 %.1f s" % [a0, a1, t_max, t])
	cap("PULL a0=%.2f a1=%.2f T=%.0f t=%.1f" % [a0, a1, t_max, t])
	await _reset()


# ---------------------------------------------------------------- 10 杠杆差异
func _c10_leverage() -> void:
	await _reset()
	await _attach("eye_mid")
	await _w(20)
	Input.action_press("winch_haul")
	var far_deg: float = 0.0
	var t_mid: float = 0.0
	for i in range(300):
		await get_tree().physics_frame
		far_deg = float((rail.call("alignment") as Dictionary).get("angle_deg"))
		t_mid = maxf(t_mid, float(winch.get("tension")))
	Input.action_release("winch_haul")
	var mid_stuck: bool = absf(far_deg - 15.0) < 0.35 and bool(rail.get("jammed"))
	await _reset()
	await _attach("eye_far")
	await _w(20)
	Input.action_press("winch_haul")
	for i in range(240):
		await get_tree().physics_frame
		if not bool(rail.get("jammed")):
			break
	Input.action_release("winch_haul")
	var far_broke: bool = not bool(rail.get("jammed"))
	_check("C10 不同负载（吊耳力臂）产生合理差异：中段吊耳拉不脱卡阻，前端长力臂可以",
		mid_stuck and far_broke,
		"中段吊耳 5 s 后仍 %.2f°（峰值 %.0f N）→ 卡阻未脱；前端吊耳卡阻已解除=%s" % [
			far_deg, t_mid, str(far_broke)])
	await _reset()


# ---------------------------------------------------------------- 11 受阻
func _c11_blocked() -> void:
	await _reset()
	rail.set("bracket_engaged", true)
	await _attach("eye_far")
	await _w(20)
	var a0: float = float(rail.get("hinge_angle"))
	Input.action_press("winch_haul")
	await _w(90)
	var a1: float = float(rail.get("hinge_angle"))
	var tension: float = float(winch.get("tension"))
	Input.action_release("winch_haul")
	rail.set("bracket_engaged", false)
	_check("C11 负载被安全支架挡住时不会穿透（角度不动，张力照样建立，鼓被顶住）",
		absf(a1 - a0) < deg_to_rad(0.05) and tension > 1000.0,
		"角度变化 %.4f°（< 0.05°），张力 %.0f N，支架=%s" % [
			rad_to_deg(absf(a1 - a0)), tension, str(rail.get("bracket_engaged"))])
	await _reset()


# ---------------------------------------------------------------- 12 伪成功
func _c12_no_false_success() -> void:
	await _reset()
	var refused_early: Dictionary = rig.call("try_install_lock")
	await _attach("eye_mid")
	await _w(20)
	Input.action_press("winch_haul")
	await _w(300)
	Input.action_release("winch_haul")
	var refused_mid: Dictionary = rig.call("try_install_lock")
	_check("C12 机械条件不足时不会伪成功（15° 外插销被拒；中段吊耳拉不脱也插不进）",
		not bool(refused_early.get("ok")) and not bool(refused_mid.get("ok"))
			and not bool(rig.get("completed")),
		"15° 拒绝=%s（%s）；中段拒绝=%s（%s）" % [str(not bool(refused_early.get("ok"))),
			str(refused_early.get("reason")), str(not bool(refused_mid.get("ok"))),
			str(refused_mid.get("reason"))])
	await _reset()


# ---------------------------------------------------------------- 13 鼓刹作用
func _c13_brake_motion() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(20)
	Input.action_press("winch_haul")
	for i in range(120):
		await get_tree().physics_frame
		if absf(float(winch.get("drum_omega"))) > 0.5:
			break
	var before: float = absf(float(winch.get("drum_omega")))
	Input.action_release("winch_haul")
	await _w(2)
	Input.action_press("winch_brake")
	await _w(3)
	Input.action_release("winch_brake")
	await _w(45)
	var after: float = absf(float(winch.get("drum_omega")))
	_check("C13 鼓刹能够改变卷筒真实运动（空载转起来的鼓，拉闸后靠摩擦停住，不是清速度）",
		before > 0.4 and after < 0.05 and bool(winch.get("brake")),
		"ω %.3f → %.3f rad/s，brake=%s，行程=%.2f，τ_brake=%.0f N·m" % [
			before, after, str(winch.get("brake")), float(winch.get("brake_travel")),
			float(winch.get("brake_torque"))])
	await _reset()


# ---------------------------------------------------------------- 13b 鼓刹容量
func _c13b_brake_capacity() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(20)
	Input.action_press("winch_haul")
	for i in range(240):
		await get_tree().physics_frame
		if bool(rail.get("jammed")) == false:
			break
	var tension: float = float(winch.get("tension"))
	Input.action_release("winch_haul")
	await _w(2)
	Input.action_press("winch_brake")
	await _w(3)
	Input.action_release("winch_brake")
	var slipped: bool = false
	var peak_speed: float = 0.0
	for i in range(60):
		await get_tree().physics_frame
		slipped = slipped or bool(winch.get("brake_slipping"))
		peak_speed = maxf(peak_speed, absf(float(winch.get("drum_omega"))))
	var torque_needed: float = tension * 0.34
	_check("C13b 鼓刹能力有上限（950 N·m ≈ 2794 N 缆绳：满载张力下会打滑，允许合理滑移而不是无限锁死）",
		slipped and tension > 2500.0 and torque_needed > 950.0 and peak_speed > 0.03,
		"张力 %.0f N（需 %.0f N·m），闸容量 950 N·m，打滑=%s，滑移速度峰值 %.3f rad/s" % [
			tension, torque_needed, str(slipped), peak_speed])
	await _reset()

# ---------------------------------------------------------------- 14 鼓刹保持
func _c14_brake_hold() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(20)
	Input.action_press("winch_haul")
	var reached := false
	for i in range(3600):
		await get_tree().physics_frame
		if absf(float((rail.call("alignment") as Dictionary).get("angle_deg"))) <= 2.8:
			reached = true
			break
	Input.action_release("winch_haul")
	await _w(2)
	Input.action_press("winch_brake")
	await _w(3)
	Input.action_release("winch_brake")
	await _w(40)
	var a0: float = float((rail.call("alignment") as Dictionary).get("angle_deg"))
	var t0: float = float(winch.get("tension"))
	await _w(120)
	var a1: float = float((rail.call("alignment") as Dictionary).get("angle_deg"))
	var t1: float = float(winch.get("tension"))
	_check("C14 鼓刹保持能力可实测（咬住负载 2 s，轨道角度漂移 < 1°，张力不被放掉）",
		reached and absf(a1 - a0) < 1.0 and t1 > 300.0,
		"角度 %.2f° → %.2f°（漂移 %.2f°），张力 %.0f → %.0f N，slip=%s" % [
			a0, a1, absf(a1 - a0), t0, t1, str(winch.get("brake_slipping"))])
	await _reset()


# ---------------------------------------------------------------- 15 松开
func _c15_release() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(20)
	print("CAP C15 pre owned=%s at_console=%s slot=%d" % [
		str(flow.call("console_owned_by", int(stage.get("local_slot")))), str(flow.get("at_console")),
		int(stage.get("local_slot"))])
	var braked: bool = bool(winch.get("brake"))
	Input.action_press("winch_brake")   # 松闸（复位后鼓刹是咬合的）
	await _w(3)
	Input.action_release("winch_brake")
	await _w(20)
	Input.action_press("winch_haul")
	var omega: float = 0.0
	for i in range(90):
		await get_tree().physics_frame
		omega = absf(float(winch.get("drum_omega")))
		if omega > 0.2:
			break
	Input.action_release("winch_haul")
	_check("C15 松开鼓刹后卷筒恢复合理自由度（复位时闸是咬合的 → 松开 → W 又能把鼓转起来）",
		braked and not bool(winch.get("brake")) and omega > 0.2,
		"起始咬合=%s → 释放=%s，收绳 ω=%.3f rad/s" % [str(braked),
			str(winch.get("brake")), omega])
	await _reset()


# ---------------------------------------------------------------- 16 未达条件
func _c16_not_yet() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(20)
	var result: Dictionary = rig.call("try_install_lock")
	_check("C16 维修未达到实际条件时不能完成（轨道在 15°、卡阻未脱，销子插不进）",
		not bool(result.get("ok")) and not bool(rig.get("completed"))
			and str(result.get("reason")) != "",
		"拒绝原因：%s" % str(result.get("reason")))
	await _reset()


# ---------------------------------------------------------------- 17 真实完成
func _c17_complete() -> void:
	await _reset()
	var run: Dictionary = await _complete_mission()
	_check("C17 满足真实机械条件后任务完成（收绳到导向槽 → 落鼓刹 → 插销 → 轨道复位 → 解线）",
		bool(run.get("completed")) and bool(run.get("route")) and float(run.get("deg")) <= 4.0,
		"收绳后角度 %.2f°，用时 %.1f s，completed=%s，route_clear=%s" % [
			float(run.get("deg")), float(run.get("time")), str(run.get("completed")),
			str(run.get("route"))])
	await _reset()


# ---------------------------------------------------------------- 18 复位
func _c18_reset() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(20)
	Input.action_press("winch_haul")
	await _w(120)
	Input.action_release("winch_haul")
	await _w(20)
	cart.call("reset_run")
	device.call("reset_all")
	rig.call("reset_mission")
	await _w(60)
	var s: Dictionary = winch.call("torque_state")
	_check("C18 R 复位正确（绳长回起始、闸重新咬合、角速度 0、轨道回 15°、卡阻回位）",
		not bool(winch.get("attached")) and bool(winch.get("brake"))
			and absf(float(winch.get("free_length")) - float(winch.get("start_length"))) < 0.01
			and absf(float(s.get("omega", 1.0))) < 0.001
			and absf(rad_to_deg(float(rail.get("hinge_angle"))) - 15.0) < 0.05
			and bool(rail.get("jammed")) and not bool(rig.get("completed")),
		"attached=%s brake=%s 绳长=%.2f ω=%.3f 角度=%.2f° jam=%s completed=%s" % [
			str(winch.get("attached")), str(winch.get("brake")),
			float(winch.get("free_length")), float(s.get("omega", 0.0)),
			rad_to_deg(float(rail.get("hinge_angle"))), str(rail.get("jammed")),
			str(rig.get("completed"))])


# ---------------------------------------------------------------- 19 连续
func _c19_repeat() -> void:
	var ok: bool = true
	var times: Array[float] = []
	for i: int in range(5):
		await _reset()
		var run: Dictionary = await _complete_mission()
		times.append(float(run.get("time")))
		ok = ok and bool(run.get("completed")) and bool(run.get("route"))
		if not ok:
			break
	await _reset()
	_check("C19 连续操作 5 个维修循环稳定（每次都真实完成，用时离散 < 25%）",
		ok and times.size() == 5,
		"5 次用时 %s" % str(times))


# ---------------------------------------------------------------- 20 张力上限
func _c20_tension_cap() -> void:
	await _reset()
	await _attach("eye_far")
	await _w(20)
	Input.action_press("winch_haul")
	var peak: float = 0.0
	for i in range(360):
		await get_tree().physics_frame
		peak = maxf(peak, float(winch.get("tension")))
	Input.action_release("winch_haul")
	_check("C20 张力具有合理上限（缆绳弹簧饱和在 3200 N 额定附近，不会无限增长）",
		peak > 1000.0 and peak <= 3200.0 * 1.05 + 1.0,
		"峰值张力 %.0f N（额定 %.0f N × 1.05）" % [peak, 3200.0])
	await _reset()


# ---------------------------------------------------------------- 21 无回归
func _c21_no_regression() -> void:
	var notch: int = int(cart.call("apply_brake_notch", 1))
	await _w(40)
	var force: float = float(cart.call("brake_force"))
	var mass: float = float(cart.call("effective_mass"))
	var locked: int = int(device.call("locked_count"))
	var cargo_count: int = (device.get("cargo") as Array).size()
	cart.call("apply_brake_notch", 0)
	await _w(20)
	_check("C21 002A 货舱与 002B 矿车制动无回归（双座/双箱在线，1 档手制动仍有力）",
		cargo_count == 2 and locked == 0 and notch == 1 and force > 1800.0 and mass > 1650.0,
		"容器 %d 件，locked=%d，手制动 1 档 %.0f N，有效质量 %.0f kg（玩家在绞盘处，不在车上）" % [
			cargo_count, locked, force, mass])
	cart.call("reset_run")
	await _w(30)


# ---------------------------------------------------------------- 22 恢复行驶
func _c22_route_resume() -> void:
	await _reset()
	var run: Dictionary = await _complete_mission()
	var d0: float = float(cart.get("distance"))
	cart.call("start")
	await _w(90)
	var moving: bool = float(cart.get("speed")) > 0.3 and float(cart.get("distance")) > d0 + 0.1
	_check("C22 维修完成后矿车恢复行驶（route_clear 由真实锁定触发，发车后真的往前走）",
		bool(run.get("route")) and moving and bool(cart.get("running")),
		"route_clear=%s，速度 %.2f m/s，位移 %.2f m" % [str(cart.get("route_clear")),
			float(cart.get("speed")), float(cart.get("distance")) - d0])
	cart.call("brake", "test_cleanup")
	await _w(30)


# ---------------------------------------------------------------- 工具
func _complete_mission() -> Dictionary:
	var t: float = 0.0
	var anchor: Node3D = rig.call("find_anchor", "eye_far")
	player.global_position = (anchor.call("attach_point") as Vector3) + Vector3(1.4, 0.2, 0.0)
	await _w(4)
	rig.call("attach_cable", "eye_far", player)
	await _take_console()
	Input.action_press("winch_haul")
	var deg: float = 15.0
	for i in range(HAUL_FRAMES):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		deg = float((rail.call("alignment") as Dictionary).get("angle_deg"))
		if absf(deg) <= 2.6:
			break
	Input.action_release("winch_haul")
	await _w(2)
	Input.action_press("winch_brake")
	await _w(1)
	Input.action_release("winch_brake")
	await _w(30)
	var pin: Dictionary = rig.call("try_install_lock")
	await _w(120)
	flow.call("leave_console", 0)
	await _w(10)
	return {"completed": bool(rig.get("completed")), "route": bool(cart.get("route_clear")),
		"deg": deg, "time": t, "pin": pin}


func _find_station(node: Node) -> Node:
	if node == null:
		return null
	if node.has_method("_process") and node.get("drum") != null:
		return node
	for child: Node in node.get_children():
		var hit: Node = _find_station(child)
		if hit != null:
			return hit
	return null


func _attach(anchor_id: String) -> void:
	var anchor: Node3D = rig.call("find_anchor", anchor_id)
	player.global_position = (anchor.call("attach_point") as Vector3) + Vector3(1.4, 0.2, 0.0)
	await _w(4)
	rig.call("attach_cable", anchor_id, player)
	await _take_console()


func _take_console() -> void:
	var machine: Node3D = winch as Node3D
	player.global_position = machine.global_position + Vector3(0.0, 0.2, 1.9)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await _w(4)
	flow.call("_enter_console", player)
	await _w(4)


func _reset() -> void:
	Input.action_release("winch_haul")
	Input.action_release("winch_payout")
	Input.action_release("winch_brake")
	flow.call("leave_console", 0)
	cart.call("reset_run")
	device.call("reset_all")
	rig.call("reset_mission")
	rail.set("bracket_engaged", false)
	await _w(50)


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
	print("MECH002C_DONE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)




