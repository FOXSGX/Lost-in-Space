extends Node
## MECHANICS-002B · 第二幕矿车真实制动专项
##
## 全部断言在正式第二幕切片 res://act23/moving_cart.tscn 内执行。
## 制动机构：前甲板手制动棘轮（0 释放 / 1 常用 / 2 紧急）→ 闸瓦压紧鼓 →
## 摩擦力矩换算到轮缘 → 进入矿车的合力积分。
## 失败返回非零退出码。

const FORCE_TOL: float = 0.10          # 实测/理论减速比容差
var stage: Node
var cart: AnimatableBody3D
var device: Node
var flow: Node
var player: CharacterBody3D
var rig: Node3D
var checks: int = 0
var failures: int = 0


func _ready() -> void:
	stage = (load("res://act23/moving_cart.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	cart = stage.get("cart") as AnimatableBody3D
	device = stage.get("device")
	flow = stage.get("flow")
	player = stage.get("player") as CharacterBody3D
	rig = cart.get("brake_rig") as Node3D
	if cart == null or device == null or flow == null or player == null or rig == null:
		_fail("M0", "切片缺少 cart/device/flow/player/brake_rig")
		return _report()
	await _m01_load()
	await _m02_structure()
	await _m03_mass()
	await _m04_cruise()
	await _m05_command()
	await _m06_mechanism()
	await _m07_service()
	await _m08_emergency()
	await _m09_continuity()
	await _m10_release()
	await _m11_payload()
	await _m12_clamped_slot1()
	await _m13_loose_cargo()
	await _m14_slot2()
	await _m15_blocked()
	await _m16_low_speed()
	await _m17_reset()
	await _m18_flow()
	await _m19_player()
	await _m20_repeat()
	await _m21_cycle()
	await _m22_fault()
	await _m23_arrival()
	_report()


# ---------------------------------------------------------------- 1 加载
func _m01_load() -> void:
	_check("B1 第二幕行驶切片正常加载（场景/脚本/制动机构全部在线）",
		stage.is_inside_tree() and cart.is_inside_tree() and rig.is_inside_tree()
			and flow.is_inside_tree() and player.is_inside_tree(),
		"stage=%s cart=%s rig=%s flow=%s" % [stage.name, cart.name, rig.name, flow.name])


# ---------------------------------------------------------------- 2 结构
func _m02_structure() -> void:
	var objective: String = str(flow.get("objective_text"))
	var phase: String = str(flow.get("phase"))
	var drums: int = 0
	for child: Node in rig.get_children():
		if child is MeshInstance3D or child is Node3D:
			drums += 1
	_check("B2 原有轨道与阶段机保留（board 起始、发车目标、制动机构作为车体子节点存在）",
		phase == "board" and objective.find("发车") >= 0 and drums >= 6
			and str(cart.get("state")) in ["停靠待发", "已停车"] and float(cart.get("speed")) < 0.01,
		"phase=%s objective=%s rig_nodes=%d state=%s" % [phase, objective, drums, str(cart.get("state"))])


# ---------------------------------------------------------------- 3 质量
func _m03_mass() -> void:
	_at_console()
	await _w(20)
	var mass: float = float(cart.call("effective_mass"))
	var cargo_mass: float = 0.0
	for body: Node in (device.get("cargo") as Array):
		cargo_mass += float(body.get("mass"))
	var expected: float = 1650.0 + cargo_mass + (78.0 if bool(cart.call("contains_point", player.global_position, 0.2)) else 0.0)
	_check("B3 初始车速与质量合理（整备质量 1650 kg + 两件 6 kg 实货 + 在车人员）",
		absf(mass - expected) < 1.0 and mass > 1700.0 and absf(float(cart.get("speed"))) < 0.01,
		"mass=%.1f（期望 %.1f）cargo=%.1f speed=%.3f" % [mass, expected, cargo_mass, float(cart.get("speed"))])


# ---------------------------------------------------------------- 4 不制动
func _m04_cruise() -> void:
	await _run_to_cruise()
	var d0: float = float(cart.get("distance"))
	var v0: float = float(cart.get("speed"))
	for i in range(180):
		await get_tree().physics_frame
	var dist: float = float(cart.get("distance")) - d0
	var v1: float = float(cart.get("speed"))
	_check("B4 不制动时矿车按既有动力机制行驶（3 s 巡航不衰减）",
		dist > 4.2 and dist < 5.1 and v1 > 1.5 and int(rig.get("notch")) == 0,
		"3 s 位移 %.2f m，速度 %.2f → %.2f m/s，闸位 %d" % [dist, v0, v1, int(rig.get("notch"))])
	cart.call("brake", "test_cleanup")
	await _w(30)


# ---------------------------------------------------------------- 5 指令
func _m05_command() -> void:
	await _run_to_cruise()
	_at_console()
	await _w(3)
	var before: Dictionary = cart.call("brake_state")
	stage.call("request_action", "cart_brake", 1)
	await _w(30)
	var after: Dictionary = cart.call("brake_state")
	_check("B5 制动指令确实作用到运动系统（B → 棘轮 1 档 → 手柄行程 → 制动力 > 0）",
		int(before.get("notch", 0)) == 0 and int(after.get("notch", 0)) == 1
			and float(after.get("travel", 0.0)) > 0.05 and float(after.get("brake_force", 0.0)) >= 0.0,
		"notch %d → %d，travel %.3f，force %.0f N，running=%s" % [
			int(before.get("notch", 0)), int(after.get("notch", 0)),
			float(after.get("travel", 0.0)), float(after.get("brake_force", 0.0)),
			str(cart.get("running"))])
	cart.call("reset_run")
	await _w(30)


# ---------------------------------------------------------------- 6 机构
func _m06_mechanism() -> void:
	cart.call("reset_run")
	await _w(30)
	var rest: Dictionary = cart.call("brake_state")
	cart.call("apply_brake_notch", 1)
	await _w(60)
	var service: Dictionary = cart.call("brake_state")
	cart.call("apply_brake_notch", 2)
	await _w(90)
	var emergency: Dictionary = cart.call("brake_state")
	var rest_force: float = float(rest.get("force_at_rail", 0.0))
	var service_force: float = float(service.get("force_at_rail", 0.0))
	var emergency_force: float = float(emergency.get("force_at_rail", 0.0))
	var spring_ok: bool = float(service.get("shoe_force", 0.0)) > 10000.0 \
		and float(emergency.get("shoe_force", 0.0)) > float(service.get("shoe_force", 0.0))
	_check("B6 制动机构具有实际机械状态（释放 0 N → 1 档 ≈2.0 kN → 2 档 ≈3.8 kN，闸瓦压紧力真实）",
		rest_force < 1.0 and service_force > 1800.0 and service_force < 2200.0
			and emergency_force > 3400.0 and emergency_force < 4200.0
			and emergency_force > service_force * 1.5 and spring_ok,
		"force %.0f / %.0f / %.0f N；shoe %.0f / %.0f N；travel %.2f / %.2f" % [
			rest_force, service_force, emergency_force,
			float(service.get("shoe_force", 0.0)), float(emergency.get("shoe_force", 0.0)),
			float(service.get("travel", 0.0)), float(emergency.get("travel", 0.0))])
	cart.call("apply_brake_notch", 0)
	await _w(40)


# ---------------------------------------------------------------- 7 常用制动
func _m07_service() -> void:
	var run: Dictionary = await _brake_run(1, 240)
	var mass: float = float(run["mass"])
	var force: float = float(run["force"])
	var measured: float = (float(run["v0"]) - float(run["v1"])) / maxf(float(run["time"]), 0.001)
	var theory: float = force / mass
	var ratio: float = measured / maxf(theory, 0.001)
	_check("B7 常用制动产生可测减速度，且与 F/M 一致（实测/理论 = %.2f）" % ratio,
		float(run["dist"]) > 0.85 and float(run["dist"]) < 1.35
			and measured > 0.8 and ratio > 1.0 - FORCE_TOL and ratio < 1.0 + FORCE_TOL,
		"v0=%.2f → v1=%.3f，t=%.2f s，停车 %.3f m，F=%.0f N，M=%.1f kg，实测 %.2f m/s² / 理论 %.2f m/s²" % [
			float(run["v0"]), float(run["v1"]), float(run["time"]), float(run["dist"]),
			force, mass, measured, theory])


# ---------------------------------------------------------------- 8 紧急
func _m08_emergency() -> void:
	var run: Dictionary = await _brake_run(2, 240)
	var service_dist: float = 1.094
	var dist: float = float(run["dist"])
	_check("B8 紧急制动产生合理不同结果（2 档力≈1.86×，停车距离比 1 档短 20% 以上）",
		dist < 0.95 and float(run["force"]) > 3400.0 and dist < 1.094 * 0.85,
		"2 档停车 %.3f m / 1 档 %.3f m（%.0f%%），F=%.0f N，t=%.2f s" % [
			dist, service_dist, 100.0 * dist / service_dist, float(run["force"]), float(run["time"])])


# ---------------------------------------------------------------- 9 连续性
func _m09_continuity() -> void:
	await _run_to_cruise()
	cart.call("apply_brake_notch", 1)
	var last_v: float = float(cart.get("speed"))
	var last_d: float = float(cart.get("distance"))
	var rise: float = 0.0
	var back: float = 0.0
	var samples: int = 0
	for i in range(150):
		await get_tree().physics_frame
		var v: float = float(cart.get("speed"))
		var d: float = float(cart.get("distance"))
		rise = maxf(rise, v - last_v)
		back = maxf(back, last_d - d)
		last_v = v
		last_d = d
		samples += 1
	_check("B9 制动距离与速度变化连续（无跳变、无回弹、路程单调）",
		rise < 0.05 and back < 0.0005 and float(cart.get("speed")) < 0.05,
		"逐帧最大速度回升 %.4f m/s，最大路程回退 %.6f m，%d 帧，末速 %.3f" % [
			rise, back, samples, float(cart.get("speed"))])
	cart.call("apply_brake_notch", 0)
	await _w(30)


# ---------------------------------------------------------------- 10 释放
func _m10_release() -> void:
	await _run_to_cruise()
	cart.call("apply_brake_notch", 1)
	for i in range(200):
		await get_tree().physics_frame
		if float(cart.get("speed")) < 0.01:
			break
	var stopped_at: float = float(cart.get("distance"))
	cart.call("apply_brake_notch", 0)
	await _w(80)
	var speed_after: float = float(cart.get("speed"))
	var drift: float = float(cart.get("distance")) - stopped_at
	_check("B10 松开制动后不会无理由恢复原速度（滑行/静止，不自动加速）",
		speed_after < 0.05 and absf(drift) < 0.05 and not bool(cart.get("running")),
		"松开后 80 帧：速度 %.4f m/s，位置变化 %.4f m，running=%s" % [
			speed_after, drift, str(cart.get("running"))])
	cart.call("reset_run")
	await _w(30)


# ---------------------------------------------------------------- 11 载荷
func _m11_payload() -> void:
	var empty: Dictionary = await _brake_with_payload(0)
	var single: Dictionary = await _brake_with_payload(1)
	var double: Dictionary = await _brake_with_payload(2)
	var a0: float = float(empty["decel"])
	var a1: float = float(single["decel"])
	var a2: float = float(double["decel"])
	var ratio: float = a0 / maxf(a2, 0.0001)
	var predicted: float = float(double["mass"]) / float(empty["mass"])
	_check("B11 不同货物质量产生合理结果（空车/单箱/双箱：有效质量真实参与减速，a 随载重下降）",
		float(empty["mass"]) < float(single["mass"]) and float(single["mass"]) < float(double["mass"])
			and a0 > a1 and a1 > a2 and absf(ratio - predicted) / predicted < 0.01,
		"质量 %.0f / %.0f / %.0f kg → 减速度 %.4f / %.4f / %.4f m/s²（a空/a双 = %.4f，理论 %.4f）" % [
			float(empty["mass"]), float(single["mass"]), float(double["mass"]),
			a0, a1, a2, ratio, predicted])


# ---------------------------------------------------------------- 12 1 号座
func _m12_clamped_slot1() -> void:
	var result: Dictionary = await _brake_with_clamped(0)
	_check("B12 已锁紧货物在 1 号固定座、常用制动下保持（留在 pocket 内、仍在锁紧状态）",
		bool(result["still"]) and float(result["shift"]) < 0.035 and float(result["shift"]) < 0.12,
		"加速+制动净漂移 %.4f m（Jolt 穿透容差量级，< pocket 0.12 m），secured=%s，相位 %s" % [
			float(result["shift"]), str(result["still"]), str(result["phase"])])


# ---------------------------------------------------------------- 13 未锁紧
func _m13_loose_cargo() -> void:
	var shift: float = await _loose_cargo_shift()
	_check("B13 未锁紧货物会产生合理惯性响应（紧急制动下相对车台前移，不穿模、不飞出）",
		shift > 0.02 and shift < 1.2,
		"紧急制动后容器相对车台位移 %.3f m" % shift)


# ---------------------------------------------------------------- 14 2 号座
func _m14_slot2() -> void:
	var result: Dictionary = await _brake_with_clamped(1)
	_check("B14 2 号固定座在制动过程中同样正常（锁紧后保持，减速过程不掉货）",
		bool(result["still"]) and float(result["shift"]) < 0.035 and float(result["shift"]) < 0.12,
		"2 号座加速+制动净漂移 %.4f m，secured=%s，相位 %s" % [
			float(result["shift"]), str(result["still"]), str(result["phase"])])


# ---------------------------------------------------------------- 15 受阻
func _m15_blocked() -> void:
	await _run_to_cruise()
	rig.call("set_blocked", true)
	var v0: float = float(cart.get("speed"))
	cart.call("apply_brake_notch", 1)
	await _w(45)
	var state: Dictionary = cart.call("brake_state")
	var v1: float = float(cart.get("speed"))
	rig.call("set_blocked", false)
	cart.call("apply_brake_notch", 0)
	var loss: float = v0 - v1
	_check("B15 机械受阻时不会假装配紧（楔块挡住连杆：手柄行程受限、制动力 0、只剩滑行阻力）",
		bool(state.get("blocked")) and float(state.get("force_at_rail", 0.0)) < 1.0
			and float(state.get("travel", 1.0)) < 0.25 and loss < 0.10,
		"blocked=%s travel=%.3f force=%.0f N，45 帧速度只降 %.3f m/s" % [
			str(state.get("blocked")), float(state.get("travel", 0.0)),
			float(state.get("force_at_rail", 0.0)), loss])
	cart.call("reset_run")
	await _w(30)


# ---------------------------------------------------------------- 16 低速
func _m16_low_speed() -> void:
	await _run_to_cruise()
	cart.call("apply_brake_notch", 2)
	for i in range(200):
		await get_tree().physics_frame
		if float(cart.get("speed")) < 0.18:
			break
	var d0: float = float(cart.get("distance"))
	var worst: float = 0.0
	for i in range(90):
		await get_tree().physics_frame
		worst = minf(worst, float(cart.get("speed")))
	var d1: float = float(cart.get("distance"))
	_check("B16 低速停车稳定（末速精确停在 0，不反向、不抖动、不滑移）",
		float(cart.get("speed")) < 0.001 and worst >= -0.0001 and absf(d1 - d0) < 0.12,
		"90 帧内最负速度 %.5f m/s，位置漂移 %.4f m，末速 %.5f" % [
			worst, d1 - d0, float(cart.get("speed"))])
	cart.call("reset_run")
	await _w(30)


# ---------------------------------------------------------------- 17 复位
func _m17_reset() -> void:
	await _run_to_cruise()
	cart.call("apply_brake_notch", 2)
	await _w(40)
	cart.call("reset_run")
	await _w(40)
	var s: Dictionary = cart.call("brake_state")
	_check("B17 R 复位后速度与机械状态正确恢复（速度 0、位置 0、闸松开、行程回 0）",
		absf(float(cart.get("distance"))) < 0.001 and float(cart.get("speed")) < 0.001
			and int(s.get("notch", 9)) == 0 and float(s.get("travel", 1.0)) < 0.05
			and not bool(cart.get("running")),
		"distance=%.3f speed=%.3f notch=%d travel=%.3f state=%s" % [
			float(cart.get("distance")), float(cart.get("speed")),
			int(s.get("notch", 0)), float(s.get("travel", 0.0)), str(cart.get("state"))])


# ---------------------------------------------------------------- 18 剧情
func _m18_flow() -> void:
	cart.call("reset_run")
	device.call("reset_all")
	await _w(40)
	var phase0: String = str(flow.get("phase"))
	_at_console()
	await _w(6)
	var started: bool = bool(stage.call("request_action", "repair", 1))
	await _w(60)
	var phase1: String = str(flow.get("phase"))
	var riding: bool = phase1 == "ride" and bool(cart.get("running"))
	cart.call("apply_brake_notch", 1)
	await _w(140)
	var stopped_speed: float = float(cart.get("speed"))
	cart.call("apply_brake_notch", 0)
	await _w(20)
	cart.call("start")
	await _w(90)
	var resumed: bool = float(cart.get("speed")) > 0.6
	cart.call("brake", "test_cleanup")
	await _w(120)
	_check("B18 手制动不会卡死原有 board → ride 流程（发车 → 制动停车 → 重新发车）",
		phase0 == "board" and started and riding and stopped_speed < 0.05 and resumed,
		"phase %s → %s；发车=%s；制动后速度 %.3f；重新发车后 %.2f m/s" % [
			phase0, phase1, str(started), stopped_speed, float(cart.get("speed"))])


# ---------------------------------------------------------------- 19 玩家
func _m19_player() -> void:
	cart.call("reset_run")
	await _w(30)
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
	_check("B19 玩家移动、HUD 与主要交互无回归（新制动机构不挡路、不卡人）",
		moved > 0.2 and hud != null and player.global_position.is_finite(),
		"位移 %.2f m，hud=%s" % [moved, str(hud != null)])


# ---------------------------------------------------------------- 20 重复
func _m20_repeat() -> void:
	var dists: Array[float] = []
	for i: int in range(5):
		var run: Dictionary = await _brake_run(1, 240)
		dists.append(float(run["dist"]))
	var lo: float = dists[0]
	var hi: float = dists[0]
	for d: float in dists:
		lo = minf(lo, d)
		hi = maxf(hi, d)
	_check("B20 常用制动重复 5 次结果一致（停车距离离散 < 3 cm，无漂移）",
		hi - lo < 0.03,
		"5 次停车距离 %s（极差 %.4f m）" % [str(dists), hi - lo])


# ---------------------------------------------------------------- 21 换档
func _m21_cycle() -> void:
	cart.call("reset_run")
	await _w(40)
	var speeds: Array[float] = []
	var notches: Array[int] = []
	for i: int in range(7):
		cart.call("pull_brake")
		await _w(20)
		speeds.append(float(cart.get("speed")))
		notches.append(int(rig.get("notch")))
	_check("B21 反复按 B 不会制造额外速度（0→1→2→0 循环，静止时速度始终为 0）",
		notches == [1, 2, 0, 1, 2, 0, 1] and speeds.max() < 0.001 and speeds.min() >= 0.0,
		"档位 %s；速度 %s" % [str(notches), str(speeds)])
	cart.call("reset_run")
	await _w(30)


# ---------------------------------------------------------------- 22 断轨
func _m22_fault() -> void:
	cart.call("reset_run")
	await _w(40)
	cart.call("snap_to_distance", 84.0)
	_at_console()
	await _w(10)
	cart.call("start")
	for i in range(900):
		await get_tree().physics_frame
		if bool(cart.get("stopped_for_fault")):
			break
	var dist: float = float(cart.get("distance"))
	var s: Dictionary = cart.call("brake_state")
	_check("B22 前方断轨处仍能安全停车（调速器电制动 ≤2.5 kN，停在 88 m，落闸驻车）",
		bool(cart.get("stopped_for_fault")) and absf(dist - 88.0) < 0.6
			and float(cart.get("speed")) < 0.06 and int(s.get("notch", 0)) == 1,
		"distance=%.3f speed=%.3f notch=%d" % [dist, float(cart.get("speed")), int(s.get("notch", 0))])


# ---------------------------------------------------------------- 23 终点
func _m23_arrival() -> void:
	cart.call("snap_to_distance", 103.0)
	cart.call("release_route")
	await _w(10)
	cart.call("start")
	for i in range(900):
		await get_tree().physics_frame
		if bool(cart.get("arrived")):
			break
	var dist: float = float(cart.get("distance"))
	_check("B23 修复后仍能到达终点并驻车（106 m，速度归零，手制动落下）",
		bool(cart.get("arrived")) and absf(dist - 106.0) < 0.05 and float(cart.get("speed")) < 0.06,
		"arrived=%s distance=%.3f speed=%.3f" % [
			str(cart.get("arrived")), dist, float(cart.get("speed"))])
	cart.call("reset_run")
	device.call("reset_all")
	await _w(30)


# ---------------------------------------------------------------- 工具
func _brake_run(notch: int, frames: int) -> Dictionary:
	cart.call("reset_run")
	device.call("reset_all")
	await _w(40)
	await _run_to_cruise()
	var v0: float = float(cart.get("speed"))
	var d0: float = float(cart.get("distance"))
	cart.call("apply_brake_notch", notch)
	var t: float = 0.0
	var peak: float = 0.0
	for i in range(frames):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		peak = maxf(peak, float(cart.call("brake_force")))
		if i > 20 and float(cart.get("speed")) < 0.01:
			break
	var run := {
		"v0": v0, "v1": float(cart.get("speed")), "time": t,
		"dist": float(cart.get("distance")) - d0, "force": peak,
		"mass": float(cart.call("effective_mass")),
	}
	cap("BRAKE notch=%d v0=%.2f v1=%.3f t=%.2f m=%.1f F=%.0f mass=%.1f" % [
		notch, float(run["v0"]), float(run["v1"]), float(run["time"]),
		float(run["dist"]), float(run["force"]), float(run["mass"])])
	cart.call("apply_brake_notch", 0)
	await _w(20)
	return run


# 把 0/1/2 件容器"放到站台地面"（冻结在世界坐标，不在甲板上），测真实质量差。
func _brake_with_payload(aboard: int) -> Dictionary:
	cart.call("reset_run")
	device.call("reset_all")
	await _w(40)
	var cargo: Array = device.get("cargo") as Array
	for i: int in range(cargo.size()):
		var body: RigidBody3D = cargo[i] as RigidBody3D
		if i < aboard:
			continue
		body.freeze = true
		body.global_position = cart.global_position + Vector3(-12.0 - 1.5 * float(i), -1.4, 0.0)
		body.reset_physics_interpolation()
		body.set("phase", "free")
		body.set("slot", -1)
	await _w(20)
	_at_console()
	await _w(5)
	cart.call("start")
	for i in range(400):
		await get_tree().physics_frame
		if float(cart.get("speed")) > 1.5:
			break
	var mass: float = float(cart.call("effective_mass"))
	var d0: float = float(cart.get("distance"))
	cart.call("apply_brake_notch", 1)
	await _w(24)   # 手柄行程到位，闸力已稳定
	var va: float = float(cart.get("speed"))
	await _w(24)
	var vb: float = float(cart.get("speed"))
	var decel: float = (va - vb) / (24.0 / 60.0)
	for i in range(200):
		await get_tree().physics_frame
		if float(cart.get("speed")) < 0.01:
			break
	var out := {"mass": mass, "dist": float(cart.get("distance")) - d0, "v0": va, "decel": decel}
	cap("PAYLOAD aboard=%d mass=%.1f va=%.2f decel=%.4f dist=%.4f" % [
		aboard, mass, va, decel, float(out["dist"])])
	cart.call("apply_brake_notch", 0)
	device.call("reset_all")
	await _w(30)
	return out


# 把容器搬进指定固定座并锁紧，然后常用制动，量相对位移。
func _brake_with_clamped(slot_index: int) -> Dictionary:
	cart.call("reset_run")
	device.call("reset_all")
	await _w(40)
	await _place(slot_index)
	await _w(10)
	stage.call("request_action", "repair", 1)
	for i in range(160):
		await get_tree().physics_frame
		if bool(device.call("slot_secured", slot_index)):
			break
	var secured_before: bool = bool(device.call("slot_secured", slot_index))
	var body: RigidBody3D = (device.get("cargo") as Array)[slot_index] as RigidBody3D
	var local0: Vector3 = cart.to_local(body.global_position)
	await _accelerate()
	var local1: Vector3 = cart.to_local(body.global_position)
	cart.call("apply_brake_notch", 1)
	for i in range(200):
		await get_tree().physics_frame
		if i > 20 and float(cart.get("speed")) < 0.01:
			break
	var local2: Vector3 = cart.to_local(body.global_position)
	var still: bool = bool(device.call("slot_secured", slot_index))
	var out := {
		"shift": Vector2(local2.x - local0.x, local2.z - local0.z).length(),
		"still": still and secured_before,
		"phase": str(body.get("phase")),
		"during": Vector2(local1.x - local0.x, local1.z - local0.z).length(),
	}
	cap("CLAMPED slot=%d shift=%.4f during=%.4f secured=%s phase=%s" % [
		slot_index, float(out["shift"]), float(out["during"]), str(still), str(out["phase"])])
	cart.call("apply_brake_notch", 0)
	device.call("reset_all")
	await _w(30)
	return out


func _loose_cargo_shift() -> float:
	cart.call("reset_run")
	device.call("reset_all")
	await _w(40)
	var body: RigidBody3D = (device.get("cargo") as Array)[0] as RigidBody3D
	body.freeze = true
	body.global_position = cart.to_global((device.get("slots") as Array)[0])
	body.reset_physics_interpolation()
	body.freeze = false
	body.set("phase", "seated")
	body.set("slot", 0)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	await _w(40)
	var local0: Vector3 = cart.to_local(body.global_position)
	await _accelerate()
	cart.call("apply_brake_notch", 2)
	for i in range(200):
		await get_tree().physics_frame
		if i > 20 and float(cart.get("speed")) < 0.01:
			break
	var local1: Vector3 = cart.to_local(body.global_position)
	cap("LOOSE shift_x=%.3f shift_z=%.3f y=%.3f phase=%s secured=%s" % [
		local1.x - local0.x, local1.z - local0.z, local1.y, str(body.get("phase")),
		str(device.call("slot_secured", 0))])
	cart.call("apply_brake_notch", 0)
	cart.call("reset_run")
	device.call("reset_all")
	await _w(30)
	return absf(local1.x - local0.x)


func _place(slot_index: int) -> void:
	var slots: Array = device.get("slots") as Array
	player.global_position = cart.to_global((slots[slot_index] as Vector3)
		+ cart.global_basis.z * -1.15 + Vector3.UP * 0.35)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await _w(10)
	stage.call("request_action", "pickup", 1)
	await _w(20)
	stage.call("request_action", "deposit", 1)
	for i in range(150):
		await get_tree().physics_frame
		var body: Node = (device.get("cargo") as Array)[slot_index] as Node
		if str(body.get("phase")) in ["seated", "locked"]:
			break
	await _w(20)


func _accelerate() -> void:
	_at_console()
	await _w(5)
	cart.call("start")
	for i in range(600):
		await get_tree().physics_frame
		if float(cart.get("speed")) > 1.5:
			break
	await _w(10)


func _run_to_cruise() -> void:
	cart.call("reset_run")
	device.call("reset_all")
	await _w(30)
	_at_console()
	await _w(10)
	cart.call("start")
	for i in range(600):
		await get_tree().physics_frame
		if float(cart.get("speed")) > 1.5:
			break
	await _w(10)


func _at_console() -> void:
	player.global_position = cart.to_global(Vector3(2.48, 2.05, 1.20))
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()


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
	print("MECH002B_DONE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)



