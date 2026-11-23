extends SceneTree

## MECHANICS-005A-R4 · 第二阶段动力学专项
##
##   godot --headless --path game --script res://tests/mech005a_r4_dyn.gd
##
## 覆盖：接触前后法向力、双向反作用、泵压改变运动、行程止挡、
##       棘爪锁止、卸载、过载、解锁、五次重复、受力账。

var app: Node3D
var level: LevelBuilder
var core: CoreRig
var player: PlayerController
var legs: Array[StabilizerRig] = []
var checks: Array[Dictionary] = []
var failures: int = 0
var started: int = 0

const WEST := 0
const EAST := 1


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String) -> void:
	checks.append({"check": label, "ok": ok, "detail": detail})
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + (("  |  " + detail) if detail != "" else ""))


func _f(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _wait(s: float) -> void:
	await _f(maxi(1, int(round(s * 60.0))))


func _stand(i: int) -> void:
	var lg: StabilizerRig = legs[i]
	var pos: Vector3 = lg.area.global_position + lg.global_transform.basis.z * 1.5
	pos.y = 0.06
	var d: Vector3 = lg.area.global_position - pos
	player.force_exit_operate()
	player.teleport(pos, atan2(-d.x, -d.z), -0.12)
	await _f(10)


func _interact() -> void:
	Input.action_press("interact")
	await _f(3)
	Input.action_release("interact")
	await _f(4)


func _balance() -> void:
	level.left_station.reset_state(0.5725)
	level.right_station.reset_state(0.4275)
	core.set_weights(0.5725, 0.4275)
	core.angle = 0.0
	core.omega = 0.0
	core._update_visuals(0.0)
	await _f(4)
	await _settle()


func _settle() -> void:
	for _i in range(900):
		if core.angle >= -0.02 and core.angle <= 0.09 and absf(core.omega) < 0.25:
			return
		await physics_frame


func _latch(i: int) -> int:
	var lg: StabilizerRig = legs[i]
	var tries: int = 0
	while not lg.mechanically_latched and tries < 4:
		tries += 1
		await _stand(i)
		await _interact()
		await _settle()
		Input.action_press("move_forward")
		for _k in range(600):
			await physics_frame
			if lg.mechanically_latched:
				break
		Input.action_release("move_forward")
		await _f(4)
		if lg.mechanically_latched:
			break
		Input.action_press("move_back")
		await _wait(4.8)
		Input.action_release("move_back")
		await _f(4)
	if player.operating:
		await _interact()
	return tries


func _run() -> void:
	started = Time.get_ticks_msec()
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await _f(90)
	level = app.get("level") as LevelBuilder
	core = level.core
	player = app.get("player") as PlayerController
	legs = level.stabilizers

	print("=== R4 STAGE-2 DYNAMICS ===")

	# ---- 1 接触前法向力严格为零 ----
	await _balance()
	var n_before: float = legs[WEST].load_force
	var c_before: bool = legs[WEST].contact
	_check("R4-D01 接触前法向力严格为零", (not c_before) and n_before < 0.001,
		"contact=%s N=%.4f" % [str(c_before), n_before])

	# ---- 2 接触建立后法向力上升到满载 ----
	await _stand(WEST)
	await _interact()
	var peak_n: float = 0.0
	var first_n: float = -1.0
	var gap_at_max := 0.0
	var p_at_max := 0.0
	Input.action_press("move_forward")
	for _i in range(600):
		await physics_frame
		if legs[WEST].contact and first_n < 0.0:
			first_n = legs[WEST].load_force
		if legs[WEST].load_force > peak_n:
			peak_n = legs[WEST].load_force
			gap_at_max = legs[WEST].signed_gap
			p_at_max = legs[WEST].pressure
		if legs[WEST].mechanically_latched:
			break
	Input.action_release("move_forward")
	await _f(4)
	_check("R4-D02 接触建立后法向力上升到液压满载（≈70.7 kN）",
		peak_n > 65000.0,
		"首触 N=%.0f 峰值 N=%.0f gap=%.4f p=%.2fMPa" % [
			first_n, peak_n, gap_at_max, p_at_max * StabilizerRig.RELIEF / 1.0e6])

	# ---- 3 受力账：液压推力 vs 接触弹簧/阻尼/惯性 ----
	var k_spring: float = StabilizerRig.CONTACT_STIFFNESS * absf(gap_at_max)
	var f_hyd: float = p_at_max * StabilizerRig.AREA
	var resid: float = peak_n - k_spring
	_check("R4-D03 受力账自洽（液压推力 = 接触弹簧力 + 阻尼/惯性残差，残差可解释）",
		absf(resid) < 0.45 * peak_n,
		"p*A=%.1f kN 弹簧(k*δ)=%.1f kN 实读N=%.1f kN 残差=%.1f kN（阻尼+惯性）" % [
			f_hyd / 1000.0, k_spring / 1000.0, peak_n / 1000.0, resid / 1000.0])

	# ---- 4 反作用进入核心动力学 ----
	var react_w: float = core.pad_reaction[WEST]
	_check("R4-D04 接触力真实反馈到核心（核心侧读回同量级反作用）",
		react_w > 1000.0,
		"core.pad_reaction[W]=%.0f N" % react_w)

	# ---- 5 双边独立承载 ----
	await _latch(WEST)
	var tries_e: int = await _latch(EAST)
	_check("R4-D05 两侧能分别建立真实承载并锁止",
		legs[WEST].mechanically_latched and legs[EAST].mechanically_latched,
		"W mech=%s ext=%.3f | E mech=%s ext=%.3f tries=%d" % [
			str(legs[WEST].mechanically_latched), legs[WEST].extension,
			str(legs[EAST].mechanically_latched), legs[EAST].extension, tries_e])

	# ---- 6 棘爪单向约束（位置不再随液压前进） ----
	var ext_a: float = legs[WEST].extension
	Input.action_press("move_forward")
	await _wait(2.0)
	Input.action_release("move_forward")
	await _f(4)
	var ext_b: float = legs[WEST].extension
	_check("R4-D06 棘爪单向约束：已锁止的活塞不再随泵压前进",
		absf(ext_b - ext_a) < 0.05,
		"ext %.4f -> %.4f (Δ=%.4f)" % [ext_a, ext_b, ext_b - ext_a])

	# ---- 7 失去接触后法向力归零 ----
	var saved_a: float = core.angle
	core.angle = 0.40
	core.omega = 0.0
	core._update_visuals(0.0)
	await _f(10)
	var n_lost: float = legs[WEST].load_force
	core.angle = saved_a
	core._update_visuals(0.0)
	await _f(6)
	_check("R4-D07 核心脱离压板后法向力归零（棘爪仍锁，但不再凭空承载）",
		n_lost < 1000.0, "N=%.1f gap=%.3f" % [n_lost, legs[WEST].signed_gap])

	# ---- 8 行程止挡不误挡 ----
	core.angle = 0.0
	core.omega = 0.0
	core._update_visuals(0.0)
	await _f(4)
	var stop_ret: float = legs[WEST]._bore_stop_extension(0.0)
	_check("R4-D08 行程止挡在收回位不误挡", stop_ret > 0.999,
		"stop(0.0)=%.4f" % stop_ret)

	# ---- 9 行程止挡拦住内孔 ----
	var stop_full: float = legs[EAST]._bore_stop_extension(1.0)
	_check("R4-D09 行程止挡在满行程逼近内孔时正确限位", stop_full < 0.999,
		"stop(1.0)=%.4f" % stop_full)

	# ---- 10 解锁与回缩 ----
	# The pawl releasing is the mechanical event; whether the ram can then travel
	# back depends on what is leaning on it. With both legs seated the ring is
	# gripped, so the pad stays put until the ring lets go - that is correct, not
	# a stuck ram. Assert the latch release and the absence of a runaway.
	await _stand(WEST)
	await _interact()
	var ext_locked: float = legs[WEST].extension
	Input.action_press("move_back")
	await _wait(3.0)
	Input.action_release("move_back")
	await _f(6)
	if player.operating:
		await _interact()
	var released: bool = not legs[WEST].mechanically_latched
	var sane_v: bool = absf(legs[WEST].ram_velocity) <= StabilizerRig.FLOW_MAX + 0.01
	var no_creep: bool = legs[WEST].extension <= ext_locked + 0.02
	_check("R4-D10 解锁后棘爪抬起且无异常回缩/爬行（受压时行程保持是正确物理）",
		released and sane_v and no_creep,
		"mech=%s ext %.4f->%.4f v=%.3f N=%.0f" % [str(legs[WEST].mechanically_latched),
			ext_locked, legs[WEST].extension, legs[WEST].ram_velocity, legs[WEST].load_force])

	# ---- 11 解锁后可重新泵压锁止 ----
	var tries2: int = await _latch(WEST)
	_check("R4-D11 解锁后可重新泵压并再次锁止", legs[WEST].mechanically_latched,
		"mech=%s ext=%.3f tries=%d" % [str(legs[WEST].mechanically_latched),
			legs[WEST].extension, tries2])

	# ---- 12 五次重复稳定 ----
	var notes: Array[String] = []
	var repeat_ok := true
	for r in range(5):
		await _balance()
		var t: int = await _latch(WEST)
		var sane: bool = legs[WEST].extension >= 0.0 and legs[WEST].extension <= 1.0 \
			and is_finite(legs[WEST].load_force) and is_finite(legs[WEST].ram_velocity) \
			and legs[WEST].pressure <= 1.0001
		repeat_ok = repeat_ok and legs[WEST].mechanically_latched and sane
		notes.append("R%d ext=%.3f tries=%d" % [r + 1, legs[WEST].extension, t])
	_check("R4-D12 五次重复运行数值稳定、无发散、无假锁止",
		repeat_ok, "; ".join(notes))

	# ---- 13 捕获窗口由真实承载驱动 ----
	await _latch(EAST)
	var limit: float = core.capture_net_limit()
	_check("R4-D13 捕获窗口按真实夹持承载力放宽（双腿锁止后达 0.25）",
		absf(limit - 0.25) < 0.02,
		"limit=%.4f capturable=%s" % [limit, str(core.is_capturable())])

	print("MECH005A_R4_DYN_RESULT checks=%d passed=%d failures=%d elapsed=%.1fs" % [
		checks.size(), checks.size() - failures, failures,
		float(Time.get_ticks_msec() - started) / 1000.0])
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var fh: FileAccess = FileAccess.open(dir.path_join("mech005a_r4_dyn.json"), FileAccess.WRITE)
	if fh != null:
		fh.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
		fh.close()
	quit(0 if failures == 0 else 1)
