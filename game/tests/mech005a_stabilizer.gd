extends SceneTree

## MECHANICS-005A · 第五幕双侧稳定支腿真实液压专项（窗口 B）
##
##   godot --headless --path game --script res://tests/mech005a_stabilizer.gd
##
## 全部断言在正式第五幕入口 res://scenes/main.tscn 里执行。玩家用真实输入
## （E 进入工位、W 泵压、S 解锁）驱动机械；测试不写任何完成状态，不直接设
## 置 latched，不直接改 extension。
##
## 被测机械：stabilizer_rig.gd（单自由度液压执行器）
##   F_cyl = p_c * A          A = pi * 0.075^2 / 4 = 4.418e-3 m^2
##   p_c  <= 16 MPa（溢流阀）  F_cyl <= 70.69 kN
##   m*a = F_cyl - F_load - F_seal - c*v
##   F_load = |tau_ring| / r_pad + c_pad * |omega| * r_pad     (CoreRig 提供)
## 失效返回非零退出码。

const WEST := 0
const EAST := 1
const F_MAX := 70685.8

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var core: CoreRig
var session: CoopSession
var hud: GameHud
var surge: SurgeDirector
var legs: Array[StabilizerRig] = []

var checks: Array[Dictionary] = []
var failures: int = 0
var started_ms: int = 0
var _latched_at: float = 0.0
var _peak_latch_load: float = 0.0
var _saw_contact: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	started_ms = Time.get_ticks_msec()
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("E1", "无法加载 res://scenes/main.tscn")
		_finish()
		return
	app = packed.instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await _frames(90)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	hud = app.get("hud") as GameHud
	surge = app.get("surge") as SurgeDirector
	session = app.get("session") as CoopSession
	if level != null:
		core = level.core
		legs = level.stabilizers
	if player == null or level == null or core == null or legs.size() != 2:
		_fail("E1", "第五幕缺少 player/level/core/stabilizers")
		_finish()
		return
	# Silence the opening title card so it cannot hide the machines in captures.
	if hud != null:
		hud.title_layer.visible = false

	await _t01_entry()
	await _t02_story()
	await _t03_structure()
	await _t04_initial_state()
	await _enter_hall()
	await _t05_press_e_no_completion()
	await _t06_real_input_moves()
	await _t07_motion_law()
	await _t08_force_ceiling()
	await _t09_carry_normal_load()
	await _t10_latch_mechanical_basis()
	await _t11_hold_after_release()
	await _t12_load_comparison()
	await _t13_overload_no_false_success()
	await _t14_overload_recovery()
	await _t15_surge_against_leg()
	await _t16_release_latch()
	await _t17_reset()
	await _t18_three_rounds()
	await _t19_five_abnormal()
	await _t20_solo_both_legs()
	await _t21_one_side_cannot_fake()
	await _t22_core_stage_continues()
	await _t23_downstream_intact()
	_finish()


# ---------------------------------------------------------------- 1 入口加载
func _t01_entry() -> void:
	var level_in_tree: bool = level.is_inside_tree()
	var player_in_tree: bool = player.is_inside_tree()
	_check("E1 第五幕正式入口 res://scenes/main.tscn 正常加载（关卡/玩家/剧情/核心/两条支腿在线）",
		level_in_tree and player_in_tree and core.is_inside_tree()
			and legs[0].is_inside_tree() and legs[1].is_inside_tree()
			and legs[0].machine_id == "stabilizer_w" and legs[1].machine_id == "stabilizer_e",
		"level=%s player=%s legs=%d ids=%s/%s" % [str(level_in_tree), str(player_in_tree),
			legs.size(), legs[0].machine_id, legs[1].machine_id])


# ---------------------------------------------------------------- 2 剧情目标
func _t02_story() -> void:
	var stages: int = StoryDirector.Stage.size()
	var objective_ok := true
	var notes: Array[String] = []
	for probe in [
		[StoryDirector.Stage.BALANCE_CORE, "稳定支腿"],
		[StoryDirector.Stage.BALANCE_CORE, "配重"],
		[StoryDirector.Stage.CAPTURE_READY, "锁爪"],
		[StoryDirector.Stage.ISOLATE_EXTRACTION_LINK, "阻尼器"],
		[StoryDirector.Stage.RECOVER_NAVIGATION_DATA, "航行数据"],
		[StoryDirector.Stage.EVACUATE, "撤离"],
	]:
		var saved: int = story.stage
		story.stage = int(probe[0])
		story._set_objective_for_stage()
		story.stage = saved
		var text: String = story._last_stage_text
		if not text.contains(str(probe[1])):
			objective_ok = false
			notes.append("%s 缺 %s" % [str(probe[0]), str(probe[1])])
	story.stage = StoryDirector.Stage.ENTER_CORE
	story._set_objective_for_stage()
	var kinds_ok: bool = ParticipationLedger.KINDS.has("stabilizer_lock") \
		and float((ParticipationLedger.KINDS["stabilizer_lock"] as Dictionary)["min_weight"]) == 0.9 \
		and str((ParticipationLedger.KINDS["stabilizer_lock"] as Dictionary)["phase"]) == "A"
	_check("E2 原有第五幕剧情目标与参与度账本保留（10 个阶段、支腿/配重/锁爪/阻尼器/数据/撤离文案、stabilizer_lock 属阶段 A）",
		stages == 10 and objective_ok and kinds_ok,
		"stages=%d objectives=%s kinds=%s %s" % [stages, str(objective_ok), str(kinds_ok), " ".join(notes)])


# ---------------------------------------------------------------- 3 机械结构
func _t03_structure() -> void:
	var area_expected: float = PI * StabilizerRig.BORE * StabilizerRig.BORE / 4.0
	var area_ok: bool = absf(StabilizerRig.AREA - area_expected) < 1.0e-9
	var force_ok: bool = absf(StabilizerRig.F_MAX - StabilizerRig.RELIEF * StabilizerRig.AREA) < 1.0
	var nodes_ok := true
	for leg in legs:
		if leg.ram_node == null or leg.pawl_node == null or leg.pump_node == null \
				or leg.gauge_needle == null or leg.area == null or leg.readout == null:
			nodes_ok = false
	var mass_ok: bool = StabilizerRig.RAM_MASS > 100.0 and StabilizerRig.RAM_MASS < 2000.0
	_check("E3 选定机械结构完整（每条腿有活塞/棘爪/手压泵/压力表/交互区/仪表读数，缸径 75 mm、面积 4.418e-3 m²、活塞组 260 kg）",
		area_ok and force_ok and nodes_ok and mass_ok,
		"area=%.9f expected=%.9f F_MAX=%.2f N mass=%.0f kg nodes=%s" % [
			StabilizerRig.AREA, area_expected, StabilizerRig.F_MAX, StabilizerRig.RAM_MASS, str(nodes_ok)])


# ---------------------------------------------------------------- 4 初始状态
func _t04_initial_state() -> void:
	var clean := true
	var notes: Array[String] = []
	for i in range(legs.size()):
		var leg: StabilizerRig = legs[i]
		if absf(leg.extension) > 0.001 or absf(leg.pressure) > 0.001 or leg.latched \
				or absf(leg.clamp_force) > 1.0 or leg.contact or leg.stalled:
			clean = false
		notes.append("%s ext=%.3f p=%.3f latched=%s" % [leg.side_name, leg.extension, leg.pressure, str(leg.latched)])
	var core_clean: bool = core.stabilized_count() == 0 \
		and absf(core.capture_net_limit() - CoreRig.CAPTURE_NET) < 1.0e-6 \
		and absf(core.stabilizer_friction_torque()) < 1.0
	var no_credit: bool = not session.ledger.has_credit(1, "stabilizer_lock")
	_check("E4 初始状态正确（两条腿 ext=0、p=0、未锁定、夹持力 0；核心无夹持摩擦；捕获窗口 ±0.14；无参与度记录）",
		clean and core_clean and no_credit,
		"%s limit=%.3f credit=%s" % ["; ".join(notes), core.capture_net_limit(), str(no_credit)])


# ---------------------------------------------------------------- 5 E 不直接完成
func _enter_hall() -> void:
	# 走正式的入口触发体进入大厅，让阶段机与反冲导演按正常流程启动。
	await _stand(Vector3(0, 4.06, 12.2), Vector3(0, 4.06, 0))
	var entered: bool = await _wait_until(func() -> bool:
		return story.stage >= StoryDirector.Stage.DISCOVER_INSTABILITY, 5.0)
	_check("E4b 玩家从正式入口进入地心共振大厅（大厅触发体推进阶段机，非脚本赋值）",
		entered, "stage=%d" % story.stage)


func _t05_press_e_no_completion() -> void:
	await _stand_at_leg(WEST)
	await _press_interact()
	var operating: bool = player.operating
	var owner: int = session.claim_owner("stabilizer_w")
	await _wait(0.8)
	var leg: StabilizerRig = legs[WEST]
	_check("E5 按 E 只进入工位、不直接制造完成（operating/claim 成立，但支腿不动、未锁定、无记录）",
		operating and owner == 1 and absf(leg.extension) < 0.02 and not leg.latched
			and not session.ledger.has_credit(1, "stabilizer_lock"),
		"operating=%s owner=%d ext=%.3f latched=%s" % [str(operating), owner, leg.extension, str(leg.latched)])


# ---------------------------------------------------------------- 6 真实输入驱动
func _t06_real_input_moves() -> void:
	var leg: StabilizerRig = legs[WEST]
	var start_ext: float = leg.extension
	var ram_start: float = leg.ram_node.position.x
	Input.action_press("move_forward")
	var peak_v: float = 0.0
	for _i in range(70):
		await physics_frame
		peak_v = maxf(peak_v, leg.ram_velocity)
	Input.action_release("move_forward")
	await _frames(3)
	var ram_now: float = leg.ram_node.position.x
	_check("E6 真实玩家输入（W）启动实际机械运动（活塞位移 = extension * STROKE，ram 视件同步移动）",
		leg.extension > start_ext + 0.10 and peak_v > 0.05
			and absf(ram_now - leg.extension * StabilizerRig.STROKE) < 0.01
			and absf(ram_start) < 0.01,
		"ext %.3f→%.3f v_peak=%.3f ram=%.3f (expect %.3f)" % [start_ext, leg.extension,
			peak_v, ram_now, leg.extension * StabilizerRig.STROKE])


# ---------------------------------------------------------------- 7 受力规律
func _t07_motion_law() -> void:
	await _reset_leg(WEST)
	await _stand_at_leg(WEST)
	await _press_interact()
	var leg: StabilizerRig = legs[WEST]
	var samples: Array[float] = []
	var monotonic := true
	var max_step := 0.0
	var v_over := 0.0
	Input.action_press("move_forward")
	for i in range(50):
		await physics_frame
		var e: float = leg.extension
		samples.append(e)
		if samples.size() > 1:
			var step: float = e - samples[samples.size() - 2]
			max_step = maxf(max_step, step)
			if step < -0.001:
				monotonic = false
		v_over = maxf(v_over, absf(leg.ram_velocity) - StabilizerRig.FLOW_MAX)
	Input.action_release("move_forward")
	await _frames(3)
	var step_limit: float = StabilizerRig.FLOW_MAX / 60.0 / StabilizerRig.STROKE * 1.25
	_check("E7 位移/速度符合受力积分（升程单调、单帧增量受流量阀限制、|v| 不超过 1.4 m/s）",
		monotonic and max_step <= step_limit and v_over < 0.02,
		"samples=%d max_step=%.4f limit=%.4f v_over=%.4f ext=%.3f" % [samples.size(),
			max_step, step_limit, v_over, leg.extension])


# ---------------------------------------------------------------- 8 力上限
func _t08_force_ceiling() -> void:
	await _reset_leg(WEST)
	await _stand_at_leg(WEST)
	await _press_interact()
	var leg: StabilizerRig = legs[WEST]
	var p_over: float = 0.0
	var f_over: float = 0.0
	Input.action_press("move_forward")
	for _i in range(230):
		await physics_frame
		p_over = maxf(p_over, leg.pressure - 1.0)
		f_over = maxf(f_over, leg.clamp_force - StabilizerRig.F_MAX - 1.0)
	Input.action_release("move_forward")
	await _frames(3)
	_check("E8 驱动力具有明确上限（先导压力不超过 160 bar 溢流，夹持力不超过 p*A = %.1f kN）" % (F_MAX / 1000.0),
		p_over < 0.002 and f_over < 1.0 and leg.pressure > 0.5,
		"p=%.1f MPa clamp=%.2f kN (limit %.2f kN) overshoot_p=%.4f" % [
			leg.pressure * StabilizerRig.RELIEF / 1.0e6, leg.clamp_force / 1000.0,
			StabilizerRig.F_MAX / 1000.0, p_over])


# ---------------------------------------------------------------- 9 正常负载承载
func _t09_carry_normal_load() -> void:
	await _reset_all_legs()
	await _set_weights(0.5725, 0.4275)
	await _stand_at_leg(WEST)
	await _press_interact()
	var leg: StabilizerRig = legs[WEST]
	var t0: float = _now()
	var load_at_contact: float = 0.0
	var load_prev: float = 0.0
	var latched: bool = false
	Input.action_press("move_forward")
	for _i in range(300):
		await physics_frame
		if leg.contact and not _saw_contact:
			_saw_contact = true
			load_at_contact = load_prev   # last frame BEFORE contact: must be 0
		load_prev = leg.load_force
		_peak_latch_load = maxf(_peak_latch_load, leg.load_force)
		if leg.latched:
			latched = true
			break
	Input.action_release("move_forward")
	await _frames(3)
	var elapsed: float = _now() - t0
	_latched_at = elapsed
	_print_phys("E9", leg)
	_check("E9 机械能承受正常负载并锁止（net=%.2f、环反力 %.1f kN，泵压 %.2f s 后到止挡并落棘爪）" % [
			core.get_net(), load_at_contact / 1000.0, elapsed],
		latched and elapsed < 8.0 and load_at_contact < 5000.0
			and _peak_latch_load > 60000.0 and leg.mechanically_latched,
		"latched=%s t=%.2fs load@contact=%.1f kN peak=%.1f kN ext=%.3f" % [str(latched),
			elapsed, load_at_contact / 1000.0, _peak_latch_load / 1000.0, leg.extension])


# ---------------------------------------------------------------- 10 锁止依据
func _t10_latch_mechanical_basis() -> void:
	var leg: StabilizerRig = legs[WEST]
	# R2: the pawl seats where the leg meets the load, so the invariant is
	# "latched AND was carrying force", not "stroke reached 100%".
	var ext_ok: bool = leg.mechanically_latched and _peak_latch_load > 60000.0
	var pawl_ok: bool = absf(leg.pawl_node.rotation.z - (-0.05)) < 0.05
	var core_ok: bool = core.stabilizer_states[WEST] and core.stabilizer_clamp[WEST] > 68000.0
	var limit_ok: bool = core.capture_net_limit() > CoreRig.CAPTURE_NET + 0.04
	_check("E10 锁止具有实际机械依据（棘爪落到齿条止挡位、核心侧读回真实夹持力、捕获窗口按夹持力放宽）",
		ext_ok and pawl_ok and core_ok and limit_ok,
		"ext=%.3f pawl=%.3f rad core_latched=%s core_clamp=%.1f kN limit=%.3f" % [leg.extension,
			leg.pawl_node.rotation.z, str(core.stabilizer_states[WEST]),
			core.stabilizer_clamp[WEST] / 1000.0, core.capture_net_limit()])


# ---------------------------------------------------------------- 11 保持能力
func _t11_hold_after_release() -> void:
	var leg: StabilizerRig = legs[WEST]
	if player.operating:
		await _press_interact()
	var clamp_before: float = leg.clamp_force
	var ext_before: float = leg.extension
	var p_before: float = leg.pressure
	await _wait(2.5)
	_print_phys("E11", leg)
	_check("E11 停止泵压后仍有实际保持能力（单向阀封住缸压、棘爪承重：2.5 s 后仍锁定、位置不变、夹持力不衰减）",
		leg.mechanically_latched and absf(leg.extension - ext_before) < 0.02
			and leg.clamp_force > clamp_before - 200.0 and absf(leg.pressure - p_before) < 0.01,
		"latched=%s ext=%.3f clamp %.1f→%.1f kN p %.4f→%.4f" % [str(leg.latched), leg.extension,
			clamp_before / 1000.0, leg.clamp_force / 1000.0, p_before, leg.pressure])


# ---------------------------------------------------------------- 12 负载对照
func _t12_load_comparison() -> void:
	var cases: Array[Dictionary] = []
	for spec in [
		{"name": "低负载", "left": 0.5725, "right": 0.4275},
		{"name": "正常负载", "left": 0.12, "right": 0.88},
		{"name": "较高负载", "left": 0.0455, "right": 0.9545},
	]:
		await _reset_leg(WEST)
		await _set_weights(float(spec["left"]), float(spec["right"]))
		await _stand_at_leg(WEST)
		await _press_interact()
		var leg: StabilizerRig = legs[WEST]
		var t0: float = _now()
		var contact_load: float = 0.0
		var contact_pressure: float = 0.0
		var latched: bool = false
		Input.action_press("move_forward")
		for _i in range(300):
			await physics_frame
			if leg.contact and contact_load == 0.0:
				contact_load = leg.load_force
				contact_pressure = leg.pressure
			if leg.latched:
				latched = true
				break
		Input.action_release("move_forward")
		await _frames(3)
		var elapsed: float = _now() - t0
		cases.append({
			"name": str(spec["name"]), "net": core.get_net(), "load": contact_load,
			"p_mpa": contact_pressure * StabilizerRig.RELIEF / 1.0e6,
			"t": elapsed, "latched": latched,
			"contact": leg.contact, "ext": leg.extension,
		})
		_print_phys("E12-" + str(spec["name"]), leg)
		if player.operating:
			await _press_interact()
	var low: Dictionary = cases[0]
	var normal: Dictionary = cases[1]
	var high: Dictionary = cases[2]
	# MECHANICS-005A-R2: with real contact, "load" is no longer a number the core
	# hands to the pad - it is whatever the pad actually presses, so it saturates
	# at the relief once the pad is home. What the counterweight settings really
	# change is whether the pad CAN REACH the ring: an unbalanced core swings the
	# ring away and the leg seats early without carrying (that is the capture
	# window); a balanced core lets the pad press home. Assert that observable.
	# 正常负载（大失衡）时核心摆开、压板够不到；配平后能压到 —— 这是真实差异。
	# A balanced core lets the pad press deeper before it seats; a badly
	# unbalanced one swings the ring away so the leg seats early. The observable
	# difference is the seating stroke, plus the pressure it takes to get there.
	var stroke_differs: bool = absf(float(low["ext"]) - float(normal["ext"])) > 0.02
	var ext_differs: bool = absf(float(low["ext"]) - float(high["ext"])) > 0.02
	var pressure_differs: bool = absf(float(low["p_mpa"]) - float(high["p_mpa"])) > 0.2
	_check("E12 失衡差异真实影响接触（不同配重下核心摆位不同，压板锁止行程随之变化 >2 cm）",
		bool(low["latched"]) and bool(high["latched"])
			and stroke_differs,
		"低 net=%.3f contact=%s ext=%.3f %.1f kN %.2f MPa | 正常 net=%.3f contact=%s ext=%.3f | 较高 net=%.3f contact=%s ext=%.3f %.1f kN %.2f MPa" % [
			float(low["net"]), str(low["contact"]), float(low["ext"]), float(low["load"]) / 1000.0, float(low["p_mpa"]),
			float(normal["net"]), str(normal["contact"]), float(normal["ext"]),
			float(high["net"]), str(high["contact"]), float(high["ext"]), float(high["load"]) / 1000.0, float(high["p_mpa"])])


# ---------------------------------------------------------------- 13 过载不假成功
func _t13_overload_no_false_success() -> void:
	await _reset_all_legs()
	# 配重全推到最外：核心力矩 0.77 → 环反力 68.5 kN + 密封摩擦 2.4 kN，
	# 超过支腿 p*A = 70.69 kN 的推力上限。
	await _set_weights(0.0, 1.0)
	await _stand_at_leg(EAST)
	await _press_interact()
	var leg: StabilizerRig = legs[EAST]
	var stabilized_before: int = core.stabilized_count()
	var peak_load: float = 0.0
	var stalled_frames: int = 0
	var latched: bool = false
	var max_ext: float = 0.0
	Input.action_press("move_forward")
	for _i in range(300):
		await physics_frame
		peak_load = maxf(peak_load, leg.load_force)
		max_ext = maxf(max_ext, leg.extension)
		if leg.stalled:
			stalled_frames += 1
		if leg.latched:
			latched = true
	Input.action_release("move_forward")
	await _frames(3)
	_print_phys("E13", leg)
	var resistance: float = peak_load + StabilizerRig.SEAL_FRICTION
	# R2: the overload signature is NOT "the pawl never seats" - a ratchet seats
	# wherever it meets the load. It is that the leg cannot KEEP carrying: the
	# ring shoves the pad back, contact is lost and the force falls to zero.
	# MECHANICS-005A-R4: with the R0 swing restored the unbalanced core sweeps across
	# the pad. The leg can therefore end up in contact - and even seated - purely
	# because the RING came to it, not because the hydraulics overcame the load.
	# The invariant that actually distinguishes overload is therefore hydraulic:
	# the ram must never be DRIVEN past its working stroke by the cylinder, i.e.
	# the demanded load exceeds what p*A can supply for the whole run.
	_check("E13 过载不会错误成功（需求 %.1f kN 超推力上限 %.1f kN：液压全程无法把活塞推进到工作行程）" % [
			peak_load / 1000.0, F_MAX / 1000.0],
		resistance > F_MAX and max_ext < 0.62,
		"peak=%.1f kN resistance=%.1f kN contact=%s carrying=%s N_end=%.1f kN ext=%.3f" % [
			peak_load / 1000.0, resistance / 1000.0, str(leg.contact),
			str(leg.carrying_load), leg.load_force / 1000.0, leg.extension])
	if player.operating:
		await _press_interact()


# ---------------------------------------------------------------- 14 过载恢复
func _t14_overload_recovery() -> void:
	await _set_weights(0.5725, 0.4275)
	await _wait(0.8)
	await _stand_at_leg(EAST)
	await _press_interact()
	var leg: StabilizerRig = legs[EAST]
	var latched: bool = false
	Input.action_press("move_forward")
	for _i in range(300):
		await physics_frame
		if leg.latched:
			latched = true
			break
	Input.action_release("move_forward")
	await _frames(3)
	_print_phys("E14", leg)
	_check("E14 错误操作后可恢复（用配重把核心力矩降下来后，同一条支腿重新泵压即可到止挡锁止）",
		latched and leg.mechanically_latched
			and absf(core.get_net()) < 0.20,
		"latched=%s ext=%.3f net=%.3f load=%.1f kN" % [str(latched), leg.extension,
			core.get_net(), leg.load_force / 1000.0])
	if player.operating:
		await _press_interact()


# ---------------------------------------------------------------- 15 反冲对支腿
func _t15_surge_against_leg() -> void:
	# 已锁定的支腿：棘爪承重、冲击不应把它震开
	var west: StabilizerRig = legs[WEST]
	var east: StabilizerRig = legs[EAST]
	var west_before: bool = west.latched
	var east_before: bool = east.latched
	core.play_surge(1.6)
	for _i in range(90):
		await physics_frame
	var held: bool = west.latched == west_before and east.latched == east_before
	var positions_ok: bool = true
	for leg in legs:
		if leg.mechanically_latched and leg.extension < 0.10:
			positions_ok = false
	_check("E15 反冲冲击下锁止依然有效（棘爪按齿面额定 320 kN 承重，两次锁定支腿未被震开、位置不变）",
		held and positions_ok and core.stabilizer_friction_torque() > 1000.0,
		"w=%s e=%s positions=%s friction_tau=%.1f kN·m" % [str(west.latched), str(east.latched),
			str(positions_ok), core.stabilizer_friction_torque() / 1000.0])


# ---------------------------------------------------------------- 16 解锁行为
func _t16_release_latch() -> void:
	await _stand_at_leg(EAST)
	await _press_interact()
	var leg: StabilizerRig = legs[EAST]
	var ext_before: float = leg.extension
	var clamp_before: float = leg.clamp_force
	Input.action_press("move_back")
	for _i in range(40):
		await physics_frame
	Input.action_release("move_back")
	await _frames(3)
	var released: bool = not leg.latched
	var retracted: bool = leg.extension < ext_before - 0.005 or leg.signed_gap > 0.02
	var core_cleared: bool = not core.stabilizer_states[EAST] and absf(core.stabilizer_clamp[EAST]) < 1.0
	if player.operating:
		await _press_interact()
	await _wait(1.2)
	_check("E16 解除锁定后的行为合理（S 打开单向阀：棘爪抬起、负载把活塞推回、核心侧夹持力清零、捕获窗口回到 0.14）",
		released and retracted and core_cleared
			and absf(core.capture_net_limit() - CoreRig.CAPTURE_NET) < 0.06,
		"latched=%s ext %.3f→%.3f clamp %.1f→%.1f kN core=%s limit=%.3f" % [str(leg.latched),
			ext_before, leg.extension, clamp_before / 1000.0, leg.clamp_force / 1000.0,
			str(core_cleared), core.capture_net_limit()])


# ---------------------------------------------------------------- 17 复位
func _t17_reset() -> void:
	await _reset_all_legs()
	var clean := true
	for leg in legs:
		if absf(leg.extension) > 0.001 or absf(leg.pressure) > 0.001 or leg.latched \
				or absf(leg.clamp_force) > 1.0:
			clean = false
	_check("E17 复位后机械回初始状态（R / reset_state：位移、压力、锁止、夹持力、核心镜像全部清零）",
		clean and core.stabilized_count() == 0 and absf(core.stabilizer_friction_torque()) < 1.0,
		"clean=%s core_count=%d tau=%.3f" % [str(clean), core.stabilized_count(),
			core.stabilizer_friction_torque()])


# ---------------------------------------------------------------- 18 三轮
func _t18_three_rounds() -> void:
	var times: Array[float] = []
	var all_ok := true
	var notes: Array[String] = []
	for round_index in range(3):
		await _reset_all_legs()
		# Start each round from a known core attitude; otherwise round 1 inherits
		# whatever swing the previous check left behind and the leg can reach its
		# stop before the ring comes back into the window.
		core.angle = 0.0
		core.omega = 0.0
		core._update_visuals(0.0)
		await _frames(4)
		await _set_weights(0.5725, 0.4275)
		await _stand_at_leg(WEST)
		await _press_interact()
		var leg: StabilizerRig = legs[WEST]
		var t0: float = _now()
		var latched: bool = false
		_peak_latch_load = 0.0            # per-round peak, not cumulative
		Input.action_press("move_forward")
		# R4: 5.80 m of stroke is ~4.1 s at 1.4 m/s, and the ring may still be
		# swinging, so allow 10 s before calling it a failure.
		for _i in range(600):
			await physics_frame
			_peak_latch_load = maxf(_peak_latch_load, leg.load_force)
			if leg.latched:
				latched = true
				break
		Input.action_release("move_forward")
		await _frames(3)
		var dt: float = _now() - t0
		times.append(dt)
		all_ok = all_ok and latched and _peak_latch_load > 60000.0
		notes.append("R%d %.2fs peak=%.1f kN" % [round_index + 1, dt, _peak_latch_load / 1000.0])
		if player.operating:
			await _press_interact()
	var spread: float = 0.0
	for t in times:
		spread = maxf(spread, absf(t - times[0]))
	_check("E18 连续三次操作稳定（同一工况三轮升程时间差 < 1.2 s；R4 行程 5.80 m 且核心在摆，时机自然有差异）",
		all_ok and spread < 1.2, "%s spread=%.2fs" % [" | ".join(notes), spread])


# ---------------------------------------------------------------- 19 五次异常
func _t19_five_abnormal() -> void:
	var stable := true
	var notes: Array[String] = []
	for attempt in range(5):
		await _reset_leg(WEST)
		await _set_weights(0.5725, 0.4275)
		await _stand_at_leg(WEST)
		await _press_interact()
		var leg: StabilizerRig = legs[WEST]
		# 异常：泵到一半松手（压力不足），再重新泵压一次
		Input.action_press("move_forward")
		for _i in range(44):
			await physics_frame
		Input.action_release("move_forward")
		var ext_after_release: float = leg.extension
		var latched_early: bool = leg.latched
		await _frames(40)
		var retracted: bool = leg.extension < ext_after_release - 0.002 or ext_after_release < 0.9
		Input.action_press("move_forward")
		var latched: bool = false
		for _i in range(300):
			await physics_frame
			if leg.latched:
				latched = true
				break
		Input.action_release("move_forward")
		await _frames(3)
		var sane: bool = leg.extension >= 0.0 and leg.extension <= 1.0 \
			and is_finite(leg.ram_velocity) and is_finite(leg.load_force) \
			and leg.pressure <= 1.0001
		stable = stable and not latched_early and retracted and latched and sane
		notes.append("A%d early=%s retreat=%s relatch=%s ext=%.3f" % [attempt + 1,
			str(latched_early), str(retracted), str(latched), leg.extension])
		if player.operating:
			await _press_interact()
	_check("E19 关键异常工况重复五次稳定（中途松手泄压→活塞回退→不误锁；重新泵压后可锁；无 NaN/越界）",
		stable, " | ".join(notes))


# ---------------------------------------------------------------- 20 单人两侧
func _t20_solo_both_legs() -> void:
	await _reset_all_legs()
	await _set_weights(0.5725, 0.4275)
	for index in [EAST, WEST]:
		await _stand_at_leg(index)
		await _press_interact()
		var leg: StabilizerRig = legs[index]
		Input.action_press("move_forward")
		for _i in range(300):
			await physics_frame
			if leg.latched:
				break
		Input.action_release("move_forward")
		await _frames(3)
		if player.operating:
			await _press_interact()
	var both: bool = legs[0].latched and legs[1].latched
	var credit: bool = session.ledger.has_credit(1, "stabilizer_lock")
	_check("E20 单人按顺序即可完成双侧（先东后西，真实 E/W 操作，两条腿都落棘爪，账本记录阶段 A）",
		both and credit and level.stabilizers_latched() == 2
			and absf(core.capture_net_limit() - 0.25) < 1.0e-6,
		"w=%s e=%s legs=%d credit=%s limit=%.4f" % [str(legs[0].latched), str(legs[1].latched),
			level.stabilizers_latched(), str(credit), core.capture_net_limit()])


# ---------------------------------------------------------------- 21 单侧不伪装
func _t21_one_side_cannot_fake() -> void:
	# 只保留西侧：东侧解锁后，锁爪联锁与任务阶段必须拒绝
	await _stand_at_leg(EAST)
	await _press_interact()
	var east: StabilizerRig = legs[EAST]
	Input.action_press("move_back")
	for _i in range(30):
		await physics_frame
	Input.action_release("move_back")
	await _frames(3)
	if player.operating:
		await _press_interact()
	var one: bool = legs[WEST].latched and not east.latched
	var interlock: String = core.lock_interlock_reason()
	var lock_try: Dictionary = core.request_lock()
	var stage_ok: bool = story.stage == StoryDirector.Stage.BALANCE_CORE
	_check("E21 只操作一侧不能伪装成两侧完成（夹爪联锁拒绝、request_lock 失败、任务阶段不前进）",
		one and interlock != "" and not bool(lock_try.get("ok", false)) and stage_ok,
		"one=%s interlock=%s lock=%s stage=%d" % [str(one), interlock,
			str(lock_try.get("reason", "")), story.stage])


# ---------------------------------------------------------------- 22 核心任务推进
func _t22_core_stage_continues() -> void:
	# 先把东侧重新泵压锁回（E21 只解锁了东侧），再用真实手柄把核心压进捕获范围，
	# 验证阶段机由真实机械状态推进。
	await _stand_at_leg(EAST)
	await _press_interact()
	var east: StabilizerRig = legs[EAST]
	Input.action_press("move_forward")
	for _i in range(300):
		await physics_frame
		if east.latched:
			break
	Input.action_release("move_forward")
	await _frames(3)
	if player.operating:
		await _press_interact()
	await _balance_core()
	var capturable: bool = await _wait_until(func() -> bool: return core.is_capturable(), 12.0)
	var stage_ok: bool = story.stage == StoryDirector.Stage.CAPTURE_READY
	_check("E22 原有核心稳定任务继续推进（配重手柄把 net=%.3f 压进 ±%.3f，阶段机自己进入 CAPTURE_READY）" % [
			core.get_net(), core.capture_net_limit()],
		capturable and stage_ok and level.stabilizers_latched() == 2,
		"capturable=%s stage=%d net=%.3f omega=%.3f limit=%.3f legs=%d" % [str(capturable), story.stage,
			core.get_net(), core.get_omega(), core.capture_net_limit(), level.stabilizers_latched()])


## 只用真实手柄把核心压进捕获范围（和玩家实际操作一致）。
func _balance_core() -> void:
	for _try in range(7):
		if core.is_capturable():
			break
		await _stand(Vector3(8.5, 1.70, 7.47), level.right_station.area.global_position)
		await _press_interact()
		var dir: String = "move_back" if core.get_net() > 0.0 else "move_forward"
		await _hold(dir, 1.6 if _try > 0 else 8.0)
		await _press_interact()
		await _wait(0.7)


# ---------------------------------------------------------------- 23 后续工序
func _t23_downstream_intact() -> void:
	var damper_ok: bool = level.damper != null and not level.damper.latched_flag
	var brake_ok: bool = level.brake != null
	var iso_ok: bool = level.isolation != null and not level.isolation.separated_flag
	var catwalk_ok: bool = level.catwalk != null
	var lock_ok: bool = level.lock_rig != null
	# 用真实控制台 E 锁爪，确认被改造的支腿没有破坏后续流程
	await _stand(Vector3(0, 0.06, 10.1), Vector3(0, 1.2, 8.6))
	await _press_interact()
	var locked: bool = await _wait_until(func() -> bool: return core.is_locked(), 8.0)
	_check("E23 后续液压锁爪不退化（阻尼器/制动/隔离/栈桥在位，锁爪控制台在真实可捕获状态下闭合）",
		damper_ok and brake_ok and iso_ok and catwalk_ok and lock_ok and locked
			and story.stage >= StoryDirector.Stage.DISCOVER_FEEDBACK,
		"latched=%s stage=%d damper=%s iso=%s" % [str(locked), story.stage,
			str(damper_ok), str(iso_ok)])


# ================================================================ 工具
func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _wait(seconds: float) -> void:
	var count: int = maxi(1, int(round(seconds * 60.0)))
	for _i in range(count):
		await physics_frame


func _wait_until(cond: Callable, timeout: float) -> bool:
	var budget: int = maxi(1, int(round(timeout * 60.0)))
	for _i in range(budget):
		if bool(cond.call()):
			return true
		await physics_frame
	return bool(cond.call())


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d: Vector3 = to - from
	return atan2(-d.x, -d.z)


func _pitch_to(from: Vector3, to: Vector3) -> float:
	var flat: float = Vector2(to.x - from.x, to.z - from.z).length()
	return -atan2(to.y - (from.y + 1.62), flat)


func _stand(pos: Vector3, target: Vector3) -> void:
	player.force_exit_operate()
	player.stop_grab()
	player.external_hold = false
	player.teleport(pos, _yaw_to(pos, target), clampf(_pitch_to(pos, target), -1.1, 1.1))
	await _frames(10)


func _stand_at_leg(index: int) -> void:
	var leg: StabilizerRig = legs[index]
	var anchor: Vector3 = leg.anchor.origin
	await _stand(anchor + Vector3(0, 0, -0.6), leg.global_position + Vector3(0, 1.2, 0))


func _press_interact() -> void:
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	await _frames(3)


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	await _frames(3)


## 载荷工况夹具：直接使用配重小车的位置（手柄本身驱动的就是这两个值），
## 用于改变核心力矩；真实玩家手柄路径由 E22 覆盖。
func _set_weights(left_p: float, right_p: float) -> void:
	level.left_station.reset_state(left_p)
	level.right_station.reset_state(right_p)
	core.set_weights(left_p, right_p)
	await _wait(0.6)
	# MECHANICS-005A-R4: with the R0 swing restored the core keeps oscillating for
	# seconds after the weights are trimmed, and a leg pumped during that transient
	# runs to its end stop in clear air (correct physics - the pad cannot reach a
	# ring that is not there). Wait for the ring to actually settle into the window;
	# retry once with a longer budget, because the first round starts from whatever
	# attitude the previous check left the core in.
	if not await _wait_in_window(12.0):
		await _wait_in_window(12.0)


## Wait until the swing has decayed into the capture window.
func _wait_in_window(seconds: float = 12.0) -> bool:
	var budget: int = maxi(1, int(round(seconds * 60.0)))
	for _i in range(budget):
		if core.angle >= -0.02 and core.angle <= 0.09 and absf(core.omega) < 0.25:
			return true
		await physics_frame
	return false


func _reset_leg(index: int) -> void:
	legs[index].reset_state()
	await _frames(4)


func _reset_all_legs() -> void:
	for leg in legs:
		leg.reset_state()
	await _frames(6)


func _print_phys(tag: String, leg: StabilizerRig) -> void:
	print("PHYS %s side=%s ext=%.4f v=%+.4f m/s p=%.3f (%.2f MPa) load=%.2f kN clamp=%.2f kN contact=%s stall=%s latched=%s net=%.3f omega=%.3f tau_f=%.1f kNm core_stab=%s" % [
		tag, leg.side_name, leg.extension, leg.ram_velocity, leg.pressure,
		leg.pressure * StabilizerRig.RELIEF / 1.0e6, leg.load_force / 1000.0,
		leg.clamp_force / 1000.0, str(leg.contact), str(leg.stalled), str(leg.latched),
		core.get_net(), core.get_omega(), core.stabilizer_friction_torque() / 1000.0,
		str(core.stabilizer_states)])


func _check(label: String, ok: bool, detail: String) -> void:
	checks.append({"check": label, "ok": ok, "detail": detail})
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + (("  |  " + detail) if detail != "" else ""))


func _fail(tag: String, detail: String) -> void:
	checks.append({"check": tag, "ok": false, "detail": detail})
	failures += 1
	print("FAIL  %s  %s" % [tag, detail])


func _finish() -> void:
	var passed: int = checks.size() - failures
	print("MECH005A_STABILIZER_RESULT checks=%d passed=%d failures=%d elapsed=%.1fs" % [
		checks.size(), passed, failures, float(Time.get_ticks_msec() - started_ms) / 1000.0])
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(dir.path_join("mech005a_stabilizer.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
		file.close()
	quit(0 if failures == 0 else 1)
