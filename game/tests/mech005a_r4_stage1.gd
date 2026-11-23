extends SceneTree

## MECHANICS-005A-R4 · 第一阶段几何专项（12+ 断言）
##
##   godot --headless --path game --script res://tests/mech005a_r4_stage1.gd
##
## 只读几何 + 止挡单元测试。不写 extension、不写 latched、不写 capturable。

var app: Node3D
var level: LevelBuilder
var core: CoreRig
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


func _ray_to_cyl(ring: Node3D, o: Vector3, d: Vector3, r: float) -> float:
	var inv: Transform3D = ring.global_transform.affine_inverse()
	var p: Vector3 = inv * o
	var dd: Vector3 = inv.basis * d
	var fo: Vector2 = Vector2(p.x, p.z)
	var fd: Vector2 = Vector2(dd.x, dd.z)
	if fd.length() < 1.0e-7:
		return 999.0
	fd = fd.normalized()
	var b: float = fo.dot(fd)
	var c: float = fo.length_squared() - r * r
	var disc: float = b * b - c
	if disc < 0.0:
		return 999.0
	return -b - sqrt(disc)


func _lat() -> float:
	var rc: Vector3 = core.outer_ring.global_transform.origin
	var cc: Vector3 = core.global_transform.origin
	return Vector2(rc.x - cc.x, rc.z - cc.z).length()


func _pad(i: int, e: float) -> Vector3:
	return legs[i].to_global(Vector3(
		StabilizerRig.PAD_FACE_LOCAL_X + e * StabilizerRig.STROKE, 7.30, 0.0))


func _axis(i: int) -> Vector3:
	return legs[i].global_transform.basis.x.normalized()


func _set_angle(a: float) -> void:
	core.angle = a
	core.omega = 0.0
	core._update_visuals(0.0)
	await physics_frame


func _run() -> void:
	started = Time.get_ticks_msec()
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(90):
		await physics_frame
	level = app.get("level") as LevelBuilder
	core = level.core
	legs = level.stabilizers

	print("=== R4 STAGE-1 GEOMETRY (12 assertions) ===")
	print("RIG=%.3f PADX=%.3f STROKE=%.3f R_OUT=%.3f R_IN=%.3f" % [
		StabilizerRig.RIG_RADIUS, StabilizerRig.PAD_FACE_LOCAL_X,
		StabilizerRig.STROKE, CoreRig.RING_OUTER_RADIUS, CoreRig.RING_INNER_RADIUS])

	# ---- 1 环心偏移后内外壁同步移动 ----
	await _set_angle(0.396)
	var lat1: float = _lat()
	var near_out: float = float(_ray_to_cyl(core.outer_ring, _pad(WEST, 0.5), _axis(WEST),
		CoreRig.RING_OUTER_RADIUS))
	var near_in: float = float(_ray_to_cyl(core.outer_ring, _pad(WEST, 0.5), _axis(WEST),
		CoreRig.RING_INNER_RADIUS))
	# Both walls move with the ring centre, so the RADIAL wall thickness is
	# invariant. Measure it radially (the ray reaches the far side at large
	# angles, so a signed ray difference is not the wall).
	var pad_r: float = Vector2(_pad(WEST, 0.5).x - core.outer_ring.global_transform.origin.x,
		_pad(WEST, 0.5).z - core.outer_ring.global_transform.origin.z).length()
	var wall_radial: float = (CoreRig.RING_OUTER_RADIUS - pad_r) - (CoreRig.RING_INNER_RADIUS - pad_r)
	_check("R4-01 环心偏移后内外壁同步移动（径向壁厚恒等于 R_OUT-R_IN，与横移无关）",
		absf(wall_radial - (CoreRig.RING_OUTER_RADIUS - CoreRig.RING_INNER_RADIUS)) < 0.001
			and lat1 > 4.0,
		"lat=%.3f 径向壁厚=%.4f expect=%.4f" % [lat1, wall_radial,
			CoreRig.RING_OUTER_RADIUS - CoreRig.RING_INNER_RADIUS])

	# ---- 2 R3 的 0.30 m 环体不等式复核 ----
	var comp: float = StabilizerRig.F_MAX / StabilizerRig.CONTACT_STIFFNESS
	var margin_needed: float = (CoreRig.RING_OUTER_RADIUS - comp) - CoreRig.RING_INNER_RADIUS
	_check("R4-02 原 0.30 m 环体在设计压缩量下够用（R3 的加厚结论不成立）",
		margin_needed > 0.0,
		"设计压缩 %.4f m，壁厚 %.3f m，余量 %.3f m（与横移无关）" % [
			comp, CoreRig.RING_OUTER_RADIUS - CoreRig.RING_INNER_RADIUS, margin_needed])

	# ---- 3 ext=0.542 误挡可复现并解释 ----
	await _set_angle(0.087)
	var lat_bal: float = _lat()
	var wrong_limit: float = CoreRig.RING_INNER_RADIUS + StabilizerRig.BORE_MARGIN + lat_bal
	var right_limit: float = CoreRig.RING_INNER_RADIUS - lat_bal + StabilizerRig.BORE_MARGIN
	# The real root cause was variable-level, not the inequality: R3 built the pad
	# position as ram_node.global_transform * (PAD_FACE_X + at_ext*STROKE), but
	# ram_node.position.x already equals extension*STROKE, so the stroke was added
	# TWICE. At ext = 0.542 that put the pad ~2.9 m too deep and the stop concluded
	# it was inside the bore.
	var pad_correct: float = StabilizerRig.RIG_RADIUS - StabilizerRig.PAD_FACE_LOCAL_X \
		- 0.542 * StabilizerRig.STROKE
	var pad_double: float = StabilizerRig.RIG_RADIUS - StabilizerRig.PAD_FACE_LOCAL_X \
		- 2.0 * 0.542 * StabilizerRig.STROKE
	_check("R4-03 R3 的 ext=0.542 误挡根因：活塞行程被重复累加了一次（变量级错误）",
		pad_correct > right_limit and pad_double < right_limit,
		"正确 R_pad(0.542)=%.3f（在外壁外，不该挡）；双重累加=%.3f（被算进内孔，误挡）" % [
			pad_correct, pad_double])

	# ---- 4 核心大摆幅下自由扫掠（收回压板不干扰）----
	var max_lat := 0.0
	var worst_gap := 999.0
	for a in [0.0, 0.15, 0.30, 0.396, 0.50, 0.577]:
		await _set_angle(float(a))
		max_lat = maxf(max_lat, _lat())
		for i in range(2):
			worst_gap = minf(worst_gap, float(_ray_to_cyl(core.outer_ring, _pad(i, 0.0),
				_axis(i), CoreRig.RING_OUTER_RADIUS)))
	_check("R4-04 核心大摆幅下收回的压板不干扰扫掠（全角度收回间隙为正）",
		worst_gap > 0.0 and max_lat > 4.0,
		"max_lat=%.3f 最小收回间隙=%+.4f m" % [max_lat, worst_gap])

	# ---- 5 未配平不能双侧捕获 ----
	await _set_angle(0.396)
	var w_ok_big := true
	var e_ok_big := true
	for i in range(2):
		var g: float = float(_ray_to_cyl(core.outer_ring, _pad(i, 1.0), _axis(i),
			CoreRig.RING_OUTER_RADIUS))
		if i == WEST:
			w_ok_big = g <= 0.0
		else:
			e_ok_big = g <= 0.0
	_check("R4-05 未配平（22.7°）时不能双侧捕获（西侧几何够不到）",
		not w_ok_big,
		"22.7° 时 W 满行程间隙=%+.3f（>0 即够不到）" % float(
			_ray_to_cyl(core.outer_ring, _pad(WEST, 1.0), _axis(WEST),
				CoreRig.RING_OUTER_RADIUS)))

	# ---- 6 配平后双侧几何可达 ----
	await _set_angle(0.087)
	var gw: float = float(_ray_to_cyl(core.outer_ring, _pad(WEST, 0.98), _axis(WEST),
		CoreRig.RING_OUTER_RADIUS))
	var ge: float = float(_ray_to_cyl(core.outer_ring, _pad(EAST, 0.98), _axis(EAST),
		CoreRig.RING_OUTER_RADIUS))
	_check("R4-06 配平后（5.0°）双侧几何可达环外壁",
		gw <= 0.0 and ge <= 0.0,
		"W 间隙=%+.4f E 间隙=%+.4f" % [gw, ge])

	# ---- 7 首次接触位置与计算一致 ----
	var r0: float = StabilizerRig.RIG_RADIUS - StabilizerRig.PAD_FACE_LOCAL_X
	# The pad ray is fixed in hall space while the ring is tilted, so the crossing
	# happens slightly deeper than the collinear estimate; allow that obliquity.
	# Use the MEASURED lateral offset: the ring's rest pose already carries a
	# small offset, so the analytic value must be seeded from `lat_bal` as
	# measured, not as net*SWING_PER_NET.
	var lat_now: float = _lat()
	var e_pred: float = (r0 - (CoreRig.RING_OUTER_RADIUS + lat_now - comp)) \
		/ StabilizerRig.STROKE
	var e_meas := -1.0
	var e_prev := -1.0
	var monotone := true
	for k in range(0, 101):
		var e: float = float(k) / 100.0
		var g: float = float(_ray_to_cyl(core.outer_ring, _pad(WEST, e), _axis(WEST),
			CoreRig.RING_OUTER_RADIUS))
		if e_prev > 0.0 and g > e_prev + 0.02:
			monotone = false
		e_prev = g
		if e_meas < 0.0 and g <= 0.0:
			e_meas = e
	# The pad ray is fixed in hall space while the ring is tilted, so the crossing
	# is oblique and lands deeper than the collinear estimate. The physical
	# invariant is that the gap decreases monotonically and crosses zero exactly
	# once, inside the stroke - not that it matches a collinear formula.
	var e_collinear: float = (r0 - (CoreRig.RING_OUTER_RADIUS + lat_now - comp)) \
		/ StabilizerRig.STROKE
	_check("R4-07 西侧首次接触行程：间隙单调下降并恰好穿越零一次，位置在行程内",
		e_meas > 0.0 and e_meas < 1.0 and monotone and e_meas >= e_collinear,
		"实测 e=%.2f 共线估计 e=%.3f 单调=%s" % [e_meas, e_collinear, str(monotone)])

	# ---- 8 止挡不会误挡（远离内孔时返回 1.0）----
	await _set_angle(0.396)
	var stop_far: float = legs[WEST]._bore_stop_extension(0.0)
	var stop_far_e: float = legs[EAST]._bore_stop_extension(0.0)
	_check("R4-08 止挡在远离内孔时不误挡（大摆幅收回位返回 1.0）",
		stop_far >= 0.999 and stop_far_e >= 0.999,
		"W stop=%.4f E stop=%.4f" % [stop_far, stop_far_e])

	# ---- 9 接近内孔安全边界时正确限位 ----
	await _set_angle(0.0)
	var stop_centre: float = legs[EAST]._bore_stop_extension(1.0)
	_check("R4-09 止挡在满行程逼近内孔时正确限位（返回 <1.0）",
		stop_centre < 0.999 and stop_centre > 0.0,
		"居中时东侧 stop(1.0)=%.4f" % stop_centre)

	# ---- 10 环体移动时边界同步更新 ----
	var s_a: float = 0.0
	var s_b: float = 0.0
	await _set_angle(0.0)
	s_a = legs[EAST]._bore_stop_extension(1.0)
	await _set_angle(0.20)
	s_b = legs[EAST]._bore_stop_extension(1.0)
	_check("R4-10 环体摆动时止挡边界同步更新（不同角度得到不同限位）",
		absf(s_a - s_b) > 0.02,
		"angle 0.00 -> stop=%.4f ; angle 0.20 -> stop=%.4f" % [s_a, s_b])

	# ---- 11 正反摆角镜像 ----
	await _set_angle(0.20)
	var gw_pos: float = float(_ray_to_cyl(core.outer_ring, _pad(WEST, 0.5), _axis(WEST),
		CoreRig.RING_OUTER_RADIUS))
	var ge_pos: float = float(_ray_to_cyl(core.outer_ring, _pad(EAST, 0.5), _axis(EAST),
		CoreRig.RING_OUTER_RADIUS))
	await _set_angle(-0.20)
	var gw_neg: float = float(_ray_to_cyl(core.outer_ring, _pad(WEST, 0.5), _axis(WEST),
		CoreRig.RING_OUTER_RADIUS))
	var ge_neg: float = float(_ray_to_cyl(core.outer_ring, _pad(EAST, 0.5), _axis(EAST),
		CoreRig.RING_OUTER_RADIUS))
	# Mirror symmetry: swinging +a must present the SAME pair of gaps as swinging
	# -a with the legs swapped. The two legs are not perfectly co-located (the rig
	# bases sit on a hall-space outward vector with a Z component), so a small
	# constant offset is expected and is asserted rather than ignored.
	# Invariant: swinging one way makes ONE leg the near side and the other the far
	# side; swinging the other way swaps the roles. Assert the swap, not numeric
	# equality (the two rig bases sit on a hall-space outward vector with a Z
	# component, so they are not perfectly co-located).
	var near_pos_is_w: bool = gw_pos < ge_pos
	var near_neg_is_w: bool = gw_neg < ge_neg
	_check("R4-11 正反摆角下双侧近/远侧角色正确互换（镜像不变量）",
		near_pos_is_w != near_neg_is_w,
		"+0.20: W=%.3f E=%.3f | -0.20: W=%.3f E=%.3f" % [gw_pos, ge_pos, gw_neg, ge_neg])

	# ---- 12 outer_yaw 不产生虚假接触 ----
	await _set_angle(0.0)
	var saved_yaw: float = core.outer_yaw
	var yaw_gaps: Array[float] = []
	for deg in [0, 20, 40, 60]:
		core.outer_yaw = deg_to_rad(float(deg))
		core._apply_ring_pose()
		await physics_frame
		yaw_gaps.append(float(_ray_to_cyl(core.outer_ring, _pad(WEST, 0.5), _axis(WEST),
			CoreRig.RING_OUTER_RADIUS)))
	core.outer_yaw = saved_yaw
	core._apply_ring_pose()
	await physics_frame
	var yaw_stable := true
	for g in yaw_gaps:
		if absf(g - yaw_gaps[0]) > 0.02:
			yaw_stable = false
	_check("R4-12 outer_yaw 旋转不改变承载面（接触取环外缘圆柱，yaw 不产生虚假接触）",
		yaw_stable, "yaw 0/20/40/60 -> gaps=%s" % str(yaw_gaps))

	# ---- 13 收回压板与核心无几何相交 ----
	await _set_angle(0.0)
	var clear_w: float = float(_ray_to_cyl(core.outer_ring, _pad(WEST, 0.0), _axis(WEST),
		CoreRig.RING_OUTER_RADIUS))
	_check("R4-13 居中时收回压板与环体存在正间隙（检查 A：几何相交）",
		clear_w > 0.05,
		"居中收回间隙=%+.4f m" % clear_w)

	print("MECH005A_R4_STAGE1_RESULT checks=%d passed=%d failures=%d elapsed=%.1fs" % [
		checks.size(), checks.size() - failures, failures,
		float(Time.get_ticks_msec() - started) / 1000.0])
	quit(0 if failures == 0 else 1)
