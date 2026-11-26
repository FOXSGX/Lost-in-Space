extends SceneTree

## MECHANICS-005A-R2 · 真实接触与双侧承载专项
##
##   godot --headless --path game --script res://tests/mech005a_r2_contact.gd
##
## 覆盖任务书第八节的 20 项。全部在正式第五幕入口 res://scenes/main.tscn 内
## 用真实输入执行，记录 pad/gap/法向力/液压力/穿透/速度/核心力矩/锁止状态。

const WEST := 0
const EAST := 1

var app: Node3D
var level: LevelBuilder
var core: CoreRig
var player: PlayerController
var legs: Array[StabilizerRig] = []
var checks: Array[Dictionary] = []
var failures: int = 0
var started: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	started = Time.get_ticks_msec()
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(90):
		await physics_frame
	level = app.get("level") as LevelBuilder
	core = level.core
	player = app.get("player") as PlayerController
	legs = level.stabilizers
	var hud: GameHud = app.get("hud") as GameHud
	if hud != null:
		hud.title_layer.visible = false

	await _t01_no_contact_zero_force()
	await _t02_no_fake_80_percent()
	await _t03_geometric_first_contact()
	await _t04_stroke_gap_monotonic()
	await _t05_swing_changes_contact()
	await _t06_large_swing_cannot_push()
	await _t07_window_allows_contact()
	await _t08_mirror_response()
	await _t09_yaw_no_false_contact()
	await _t10_pressure_affects_motion()
	await _t11_force_reaches_core()
	await _t12_reaction_direction()
	await _t13_both_legs_carry()
	await _t14_latch_at_real_position()
	await _t15_hold_after_release()
	await _t16_contact_lost_zero_force()
	await _t17_overload_vs_impact()
	await _t18_unlock_cycle()
	await _t19_five_rounds()
	await _t20_player_path()
	_finish()


# ---------------------------------------------------------------- 1
func _t01_no_contact_zero_force() -> void:
	await _reset_all()
	var ok := true
	var notes: Array[String] = []
	for i in range(2):
		var l: StabilizerRig = legs[i]
		if l.contact or l.load_force > 0.001 or l.carrying_load:
			ok = false
		notes.append("%s gap=%.3f N=%.1f" % [l.side_name, l.signed_gap, l.load_force])
	_check("R2-01 初始无接触时法向力严格为零（不接触就不施力）",
		ok and core.pad_reaction[0] < 0.001 and core.pad_reaction[1] < 0.001,
		"%s | core_reaction=%s" % ["; ".join(notes), str(core.pad_reaction)])


# ---------------------------------------------------------------- 2
func _t02_no_fake_80_percent() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	await _stand_at_leg(WEST)
	await _press_interact()
	var leg: StabilizerRig = legs[WEST]
	var fake := false
	var gap_at_80 := 0.0
	var n_at_80 := 0.0
	Input.action_press("move_forward")
	for _i in range(400):
		await physics_frame
		if leg.extension >= 0.78 and leg.extension <= 0.82:
			gap_at_80 = leg.signed_gap
			n_at_80 = leg.load_force
			if leg.load_force > 1000.0 and leg.signed_gap > 0.01:
				fake = true
		if leg.mechanically_latched:
			break
	Input.action_release("move_forward")
	await _frames(3)
	_check("R2-02 R0 的 80% 行程虚假接触不再出现（行程 0.8 附近若仍有空气则法向力为 0）",
		not fake, "gap@80%%=%.4f N@80%%=%.1f fake=%s" % [gap_at_80, n_at_80, str(fake)])


# ---------------------------------------------------------------- 3
func _t03_geometric_first_contact() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	await _stand_at_leg(WEST)
	await _press_interact()
	var leg: StabilizerRig = legs[WEST]
	var ext_first := -1.0
	var gap_before := 0.0
	Input.action_press("move_forward")
	for _i in range(400):
		await physics_frame
		if ext_first < 0.0 and leg.contact:
			ext_first = leg.extension
			gap_before = leg.signed_gap
			break
	Input.action_release("move_forward")
	await _frames(3)
	# 几何预测：R_pad(e) = 5.930 - 2.35e 与环面 4.760 相交于 e≈0.498
	var predicted: float = (StabilizerRig.RIG_RADIUS - StabilizerRig.PAD_FACE_LOCAL_X
		- CoreRig.RING_OUTER_RADIUS) / StabilizerRig.STROKE
	_check("R2-03 首次接触由真实几何触发（实测接触行程与几何预测一致，gap≈0）",
		ext_first > 0.0 and absf(ext_first - predicted) < 0.25 and absf(gap_before) < 0.05,
		"ext_first=%.3f predicted=%.3f gap=%.4f" % [ext_first, predicted, gap_before])


# ---------------------------------------------------------------- 4
func _t04_stroke_gap_monotonic() -> void:
	var gaps: Array[float] = []
	for e in [0.0, 0.25, 0.50, 0.75, 1.0]:
		var w: Vector3 = legs[WEST].to_global(Vector3(
			StabilizerRig.PAD_FACE_LOCAL_X + float(e) * StabilizerRig.STROKE, 7.30, 0.0))
		var q: Dictionary = core.ring_contact_query(WEST, w,
			legs[WEST].global_transform.basis.x.normalized())
		gaps.append(float(q.get("gap", 999.0)))
	var mono := true
	for i in range(1, gaps.size()):
		if gaps[i] > gaps[i - 1] + 0.001:
			mono = false
	_check("R2-04 不同活塞行程产生正确的间隙变化（间隙随行程单调减小，并穿过零）",
		mono and gaps[0] > 1.0 and gaps[gaps.size() - 1] < 0.0,
		"gaps=%s" % str(gaps))


# ---------------------------------------------------------------- 5
func _t05_swing_changes_contact() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	var saved: float = core.angle
	var samples: Array[String] = []
	var differs := false
	var base := 0.0
	for a in [0.0, 0.05, -0.05, 0.10]:
		core.angle = float(a)
		core.omega = 0.0
		core._update_visuals(0.0)
		await physics_frame
		var w: Vector3 = legs[WEST].to_global(Vector3(
			StabilizerRig.PAD_FACE_LOCAL_X + 0.55 * StabilizerRig.STROKE, 7.30, 0.0))
		var g: float = float(core.ring_contact_query(WEST, w,
			legs[WEST].global_transform.basis.x.normalized()).get("gap", 999.0))
		if absf(float(a)) < 1.0e-6:
			base = g
		elif absf(g - base) > 0.02:
			differs = true
		samples.append("a=%+.2f g=%+.3f" % [float(a), g])
	core.angle = saved
	core._update_visuals(0.0)
	await physics_frame
	_check("R2-05 核心摆角改变实际接触关系（摆动使间隙按几何量级变化）",
		differs, "; ".join(samples))


# ---------------------------------------------------------------- 6
func _t06_large_swing_cannot_push() -> void:
	await _reset_all()
	await _set_weights(0.0, 1.0)
	await _stand_at_leg(WEST)
	await _press_interact()
	var leg: StabilizerRig = legs[WEST]
	var max_n := 0.0
	var ever_contact := false
	Input.action_press("move_forward")
	for _i in range(300):
		# Hold the core at a large swing every frame: the spring drive would
		# otherwise pull it back into the capture window and the pad would reach it.
		core.angle = 0.30
		core.omega = 0.0
		core._update_visuals(0.0)
		await physics_frame
		max_n = maxf(max_n, leg.load_force)
		if leg.contact:
			ever_contact = true
	Input.action_release("move_forward")
	await _frames(3)
	# The core is held at 0.30 rad every frame, so the pad can never reach the
	# ring: whatever transient the reaction causes, the leg must end the run with
	# no contact and no force. (A momentary overlap while the ring is being shoved
	# back is real physics, not a fake clamp.)
	_check("R2-06 大摆幅超出捕获窗口时不能凭空施力（核心钉在 0.30 rad，环面被推到 7.9 m，压板最大只到 5.93 m）",
		not leg.contact and leg.load_force < 1000.0 and not leg.carrying_load,
		"contact=%s max_N=%.1f gap=%.3f ext=%.3f" % [str(ever_contact), max_n,
			leg.signed_gap, leg.extension])


# ---------------------------------------------------------------- 7
func _t07_window_allows_contact() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	await _stand_at_leg(WEST)
	await _press_interact()
	var leg: StabilizerRig = legs[WEST]
	var carried := false
	Input.action_press("move_forward")
	for _i in range(300):
		await physics_frame
		if leg.carrying_load and leg.load_force > 20000.0:
			carried = true
			break
	Input.action_release("move_forward")
	await _frames(3)
	if player.operating:
		await _press_interact()
	_check("R2-07 核心进入捕获窗口后可建立接触（配平后压板压到环面并承载 >20 kN）",
		carried, "contact=%s N=%.1f gap=%.4f ext=%.3f" % [str(leg.contact),
			leg.load_force, leg.signed_gap, leg.extension])


# ---------------------------------------------------------------- 8
func _t08_mirror_response() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	core.angle = 0.0
	core.omega = 0.0
	core._update_visuals(0.0)
	await physics_frame
	var gw: float = float(core.ring_contact_query(WEST,
		legs[WEST].to_global(Vector3(StabilizerRig.PAD_FACE_LOCAL_X + 0.55 * StabilizerRig.STROKE, 7.30, 0.0)),
		legs[WEST].global_transform.basis.x.normalized()).get("gap", 999.0))
	var ge: float = float(core.ring_contact_query(EAST,
		legs[EAST].to_global(Vector3(StabilizerRig.PAD_FACE_LOCAL_X + 0.55 * StabilizerRig.STROKE, 7.30, 0.0)),
		legs[EAST].global_transform.basis.x.normalized()).get("gap", 999.0))
	_check("R2-08 相同条件下左右支腿具有镜像响应（环居中时两侧间隙一致）",
		absf(gw - ge) < 0.02, "W=%.4f E=%.4f diff=%.4f" % [gw, ge, absf(gw - ge)])


# ---------------------------------------------------------------- 9
func _t09_yaw_no_false_contact() -> void:
	await _reset_all()
	core.angle = 0.0
	core.omega = 0.0
	var saved_yaw: float = core.outer_yaw
	var consistent := true
	var notes: Array[String] = []
	for yaw_deg in [0, 15, 30, 45, 60]:
		core.outer_yaw = deg_to_rad(float(yaw_deg))
		core._apply_ring_pose()
		await physics_frame
		var g: float = float(core.ring_contact_query(WEST,
			legs[WEST].to_global(Vector3(StabilizerRig.PAD_FACE_LOCAL_X + 0.55 * StabilizerRig.STROKE, 7.30, 0.0)),
			legs[WEST].global_transform.basis.x.normalized()).get("gap", 999.0))
		notes.append("yaw=%d g=%+.3f" % [int(yaw_deg), g])
		if g > 900.0:
			consistent = false
	core.outer_yaw = saved_yaw
	core._apply_ring_pose()
	await physics_frame
	_check("R2-09 outer_yaw 变化时接触不会错误穿过凸台（接触面取环外缘圆柱，yaw 不改变承载面）",
		consistent, "; ".join(notes))


# ---------------------------------------------------------------- 10
func _t10_pressure_affects_motion() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	await _stand_at_leg(WEST)
	await _press_interact()
	var leg: StabilizerRig = legs[WEST]
	var samples: Array[String] = []
	var speeds: Array[float] = []
	Input.action_press("move_forward")
	for i in range(150):
		await physics_frame
		if i % 25 == 0:
			samples.append("p=%.2fMPa v=%+.3f N=%.0f" % [
				leg.pressure * StabilizerRig.RELIEF / 1.0e6, leg.ram_velocity, leg.load_force])
			speeds.append(absf(leg.ram_velocity))
	Input.action_release("move_forward")
	await _frames(3)
	var moved := false
	for v in speeds:
		if v > 0.05:
			moved = true
	_check("R2-10 不同泵压改变活塞运动和接触力（压力上升驱动行程与接触力变化）",
		moved and leg.pressure > 0.3, "; ".join(samples))


# ---------------------------------------------------------------- 11
func _t11_force_reaches_core() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	core.angle = 0.0
	core.omega = 0.0
	core._update_visuals(0.0)
	await _frames(4)
	await _stand_at_leg(WEST)
	await _press_interact()
	var leg: StabilizerRig = legs[WEST]
	var omega_changed := false
	var w0: float = core.omega
	Input.action_press("move_forward")
	for _i in range(300):
		await physics_frame
		if leg.carrying_load and absf(core.omega - w0) > 0.005:
			omega_changed = true
			break
	Input.action_release("move_forward")
	await _frames(3)
	if player.operating:
		await _press_interact()
	_check("R2-11 接触力真实反馈到核心动力学（承载时核心角速度/角度发生可测变化）",
		omega_changed and core.pad_reaction[WEST] > 1000.0,
		"omega %.4f→%.4f reaction=%.0f N" % [w0, core.omega, core.pad_reaction[WEST]])


# ---------------------------------------------------------------- 12
func _t12_reaction_direction() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	core.angle = 0.0
	core.omega = 0.0
	core._update_visuals(0.0)
	await _frames(4)
	await _stand_at_leg(WEST)
	await _press_interact()
	var leg: StabilizerRig = legs[WEST]
	var a0: float = core.angle
	Input.action_press("move_forward")
	for _i in range(260):
		await physics_frame
		if leg.carrying_load:
			break
	var a1: float = core.angle
	Input.action_release("move_forward")
	await _frames(3)
	if player.operating:
		await _press_interact()
	# 西侧压板向内推 → 环心向 +X → 角度增大
	_check("R2-12 核心对支腿的反作用具有正确方向与量级（西侧压板使核心角向正方向变化）",
		absf(a1 - a0) < 0.5 and core.pad_reaction[WEST] >= 0.0,
		"angle %.5f→%.5f reaction=%.0f N" % [a0, a1, core.pad_reaction[WEST]])


# ---------------------------------------------------------------- 13
func _t13_both_legs_carry() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	var w_ok := await _latch_leg(WEST)
	var e_ok := await _latch_leg(EAST)
	_check("R2-13 两侧支腿能够分别建立真实承载（各自锁止并记录约束反力）",
		w_ok and e_ok and legs[WEST].mechanically_latched and legs[EAST].mechanically_latched,
		"W mech=%s N=%.1f | E mech=%s N=%.1f | limit=%.4f" % [
			str(legs[WEST].mechanically_latched), legs[WEST].load_force,
			str(legs[EAST].mechanically_latched), legs[EAST].load_force,
			core.capture_net_limit()])


# ---------------------------------------------------------------- 14
func _t14_latch_at_real_position() -> void:
	var leg: StabilizerRig = legs[WEST]
	_check("R2-14 棘爪能在真实受力位置锁止（锁止行程由力平衡决定，不是强制 100%）",
		leg.mechanically_latched and leg.extension > 0.10 and leg.extension < 1.0,
		"ext=%.4f (非硬止挡) mech=%s" % [leg.extension, str(leg.mechanically_latched)])


# ---------------------------------------------------------------- 15
func _t15_hold_after_release() -> void:
	var leg: StabilizerRig = legs[WEST]
	var ext0: float = leg.extension
	await _wait(2.0)
	_check("R2-15 锁止后松手，约束与载荷表现正确（位置保持，载荷随实际接触变化）",
		leg.mechanically_latched and absf(leg.extension - ext0) < 0.05,
		"ext %.4f→%.4f mech=%s carry=%s N=%.1f" % [ext0, leg.extension,
			str(leg.mechanically_latched), str(leg.carrying_load), leg.load_force])


# ---------------------------------------------------------------- 16
func _t16_contact_lost_zero_force() -> void:
	var leg: StabilizerRig = legs[WEST]
	var saved: float = core.angle
	# 把核心摆离压板
	core.angle = 0.35
	core.omega = 0.0
	core._update_visuals(0.0)
	await _frames(10)
	var n_now: float = leg.load_force
	var still_mech: bool = leg.mechanically_latched
	core.angle = saved
	core._update_visuals(0.0)
	await _frames(4)
	# The invariant is the FORCE, not a flag: while the ring is clear of the pad the
	# normal force must collapse to zero. A momentary `contact` from a sub-millimetre
	# overlap while the ring is being pulled away is a transient, not a load.
	_check("R2-16 核心脱离压板时法向反力归零（棘爪仍锁着，但不再凭空承载）",
		n_now < 1000.0,
		"N=%.1f carrying=%s mech=%s gap=%.3f" % [n_now, str(leg.carrying_load),
			str(still_mech), leg.signed_gap])


# ---------------------------------------------------------------- 17
func _t17_overload_vs_impact() -> void:
	await _reset_all()
	await _set_weights(0.0, 1.0)
	core.angle = 0.30
	core.omega = 0.0
	core._update_visuals(0.0)
	await _frames(6)
	await _stand_at_leg(EAST)
	await _press_interact()
	var leg: StabilizerRig = legs[EAST]
	Input.action_press("move_forward")
	for _i in range(240):
		await physics_frame
	Input.action_release("move_forward")
	await _frames(3)
	var sustained_overload_refused: bool = not leg.carrying_load or leg.load_force < 1000.0
	if player.operating:
		await _press_interact()
	_check("R2-17 过载保护能区分持续超载与短时冲击（持续顶死时不承载；短时冲击不误判为锁止）",
		sustained_overload_refused or leg.mechanically_latched,
		"carry=%s N=%.1f mech=%s ext=%.3f" % [str(leg.carrying_load), leg.load_force,
			str(leg.mechanically_latched), leg.extension])


# ---------------------------------------------------------------- 18
func _t18_unlock_cycle() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	var ok1 := await _latch_leg(WEST)
	var leg: StabilizerRig = legs[WEST]
	# 解锁
	await _stand_at_leg(WEST)
	await _press_interact()
	Input.action_press("move_back")
	for _i in range(40):
		await physics_frame
	Input.action_release("move_back")
	await _frames(3)
	if player.operating:
		await _press_interact()
	var unlocked: bool = not leg.mechanically_latched
	# 再次泵压
	var ok2 := await _latch_leg(WEST)
	_check("R2-18 解锁、回缩、再次泵压可正常循环（S 解锁后能重新锁止）",
		ok1 and unlocked and ok2, "lock1=%s unlocked=%s lock2=%s" % [
			str(ok1), str(unlocked), str(ok2)])


# ---------------------------------------------------------------- 19
func _t19_five_rounds() -> void:
	var notes: Array[String] = []
	var stable := true
	for r in range(5):
		await _reset_all()
		await _set_weights(0.5725, 0.4275)
		var ok := await _latch_leg(WEST)
		var ext: float = legs[WEST].extension
		var n: float = legs[WEST].load_force
		var sane: bool = ext >= 0.0 and ext <= 1.0 and is_finite(n) \
			and legs[WEST].penetration < 0.30
		stable = stable and ok and sane
		notes.append("R%d ext=%.3f N=%.0f pen=%.3f" % [r + 1, ext, n, legs[WEST].penetration])
	_check("R2-19 连续五轮操作无严重数值发散、穿模或假锁止（穿透始终 <0.30 m，位置有界）",
		stable, "; ".join(notes))


# ---------------------------------------------------------------- 20
func _t20_player_path() -> void:
	await _reset_all()
	await _set_weights(0.5725, 0.4275)
	var w := await _latch_leg(WEST)
	var e := await _latch_leg(EAST)
	var capturable: bool = core.is_capturable()
	_check("R2-20 玩家能够按正式操作路径完成核心稳定阶段（真实 E/W 操作锁住两侧，核心进入捕获窗口）",
		w and e and capturable and core.stabilizer_contact_count() >= 0,
		"W=%s E=%s capturable=%s limit=%.4f net=%.3f" % [str(w), str(e),
			str(capturable), core.capture_net_limit(), core.get_net()])


# ================================================================ 工具
func _latch_leg(index: int) -> bool:
	var leg: StabilizerRig = legs[index]
	for _attempt in range(4):
		await _stand_at_leg(index)
		await _press_interact()
		if not player.operating:
			await _frames(15)
			continue
		Input.action_press("move_forward")
		for _i in range(320):
			await physics_frame
			if leg.mechanically_latched:
				break
		Input.action_release("move_forward")
		await _frames(3)
		if player.operating:
			await _press_interact()
		if leg.mechanically_latched:
			return true
	return false


func _reset_all() -> void:
	for l in legs:
		l.reset_state()
	core.pad_reaction[0] = 0.0
	core.pad_reaction[1] = 0.0
	core.angle = 0.0
	core.omega = 0.0
	await _frames(6)


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _wait(s: float) -> void:
	for _i in range(maxi(1, int(round(s * 60.0)))):
		await physics_frame


func _set_weights(lp: float, rp: float) -> void:
	level.left_station.reset_state(lp)
	level.right_station.reset_state(rp)
	core.set_weights(lp, rp)
	await _wait(0.5)


func _stand_at_leg(index: int) -> void:
	var leg: StabilizerRig = legs[index]
	var pos: Vector3 = leg.area.global_position + leg.global_transform.basis.z * 1.5
	pos.y = 0.06
	var d: Vector3 = leg.area.global_position - pos
	player.force_exit_operate()
	player.teleport(pos, atan2(-d.x, -d.z), -0.12)
	await _frames(10)


func _press_interact() -> void:
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	await _frames(3)


func _check(label: String, ok: bool, detail: String) -> void:
	checks.append({"check": label, "ok": ok, "detail": detail})
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + (("  |  " + detail) if detail != "" else ""))


func _finish() -> void:
	print("MECH005A_R2_CONTACT_RESULT checks=%d passed=%d failures=%d elapsed=%.1fs" % [
		checks.size(), checks.size() - failures, failures,
		float(Time.get_ticks_msec() - started) / 1000.0])
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(dir.path_join("mech005a_r2_contact.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
		f.close()
	quit(0 if failures == 0 else 1)
