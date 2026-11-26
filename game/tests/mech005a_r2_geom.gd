extends SceneTree

## MECHANICS-005A-R2 · 第一阶段几何诊断（只测量，不改任何生产代码）
##
##   godot --headless --path game --script res://tests/mech005a_r2_geom.gd
##
## 回答任务书第三节的 10 个问题，并输出「几何可行性表」。

const TRIM := 4.76          # 外平衡环 trim 外缘半径
const BOSS := 4.90          # ClampPad 凸台外缘
const BOSS_HALF_DEG := 2.8  # 凸台角半宽（0.44/2 / 4.55 rad ≈ 2.8°）
const PIVOT_Y := 18.2

var app: Node3D
var level: LevelBuilder
var core: CoreRig
var legs: Array[StabilizerRig] = []


func _initialize() -> void:
	_run.call_deferred()


## 在环的局部坐标系里做射线-圆柱求交，返回沿活塞轴的有符号间隙
func gap_to_cylinder(ring: Node3D, pad_world: Vector3, axis_world: Vector3, R: float) -> float:
	var inv: Transform3D = ring.global_transform.affine_inverse()
	var p: Vector3 = inv * pad_world
	var n: Vector3 = inv.basis * axis_world
	var flat: Vector2 = Vector2(n.x, n.z)
	if flat.length() < 1.0e-6:
		return 999.0
	flat = flat.normalized()
	var a: Vector2 = Vector2(p.x, p.z)
	var b: float = a.dot(flat)
	var c: float = a.length_squared() - R * R
	var disc: float = b * b - c
	if disc < 0.0:
		return 999.0
	return -b - sqrt(disc)


func pad_world(leg: StabilizerRig, e: float) -> Vector3:
	return leg.to_global(Vector3(1.67 + e * StabilizerRig.STROKE, 7.30, 0.0))


func _run() -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	for _i in range(90):
		await physics_frame
	level = app.get("level") as LevelBuilder
	core = level.core
	legs = level.stabilizers

	print("======== R2 STAGE-1 GEOMETRY DIAGNOSTIC ========")

	# ---------- Q0: 基础坐标 ----------
	print("\n[Q0] 基础几何")
	print("  core.origin          = %s" % str(core.global_transform.origin))
	print("  outer_ring local pos = %s" % str(core.outer_ring.position))
	print("  STROKE=%.3f  PAD_FACE_X=1.67  F_MAX=%.3f kN" % [
		StabilizerRig.STROKE, StabilizerRig.F_MAX / 1000.0])
	for i in range(2):
		var l: StabilizerRig = legs[i]
		print("  leg%d(%s) rig_origin=%s inward=%s dist_to_axis=%.4f" % [
			i, l.side_name, str(l.global_transform.origin.snapped(Vector3(0.001,0.001,0.001))),
			str(l.global_transform.basis.x.normalized().snapped(Vector3(0.001,0.001,0.001))),
			_axis_dist(l.global_transform.origin)])

	# ---------- Q1: 核心最大摆角 ----------
	print("\n[Q1] 核心摆动范围（R0 代码常量）")
	print("  angle clamp = ±0.58 rad (R0 hard-coded in _update_dynamics)")
	print("  target = clamp(net,-0.95,0.95) * 0.62")
	print("  net 范围: net = 0.55*(right-left)+0.22 -> [-0.33, +0.77]")
	for n in [0.77, 0.638, 0.40, 0.25, 0.14, 0.0, -0.33]:
		print("    net=%+.3f -> target_angle=%+.4f rad" % [float(n), clampf(float(n),-0.95,0.95)*0.62])

	# ---------- Q2/Q3: 配重后的核心状态 ----------
	print("\n[Q2/Q3] 配重操作后的实际核心状态（实测）")
	for spec in [["初始", 0.12, 0.88], ["配平后", 0.5725, 0.4275], ["最外", 0.0, 1.0]]:
		level.left_station.reset_state(float(spec[1]))
		level.right_station.reset_state(float(spec[2]))
		core.set_weights(float(spec[1]), float(spec[2]))
		core.angle = 0.0
		core.omega = 0.0
		for _i in range(240):
			await physics_frame
		print("  %-6s net=%+.3f angle=%+.4f omega=%+.4f |net|<=limit? %s" % [
			str(spec[0]), core.get_net(), core.get_angle(), core.get_omega(),
			str(absf(core.get_net()) <= core.capture_net_limit())])

	# ---------- Q4: 故事流程是否要求先平衡 ----------
	print("\n[Q4] 故事流程顺序（story_director 目标文案）")
	var sd: StoryDirector = app.get("story") as StoryDirector
	for st in [2, 3]:
		sd.stage = st
		sd._set_objective_for_stage()
		print("  stage=%d: %s" % [st, sd._last_stage_text.replace("\n", " / ")])

	# ---------- Q5/Q6/Q8: 双侧间隙 vs 行程（angle=0，含 yaw 影响） ----------
	print("\n[Q5/Q6/Q8] angle=0 时双侧间隙 vs 行程（trim=4.76）")
	core.angle = 0.0
	core.omega = 0.0
	core._update_visuals(0.0)
	await physics_frame
	print("  ext    W_r      W_gap    E_r      E_gap    mirror?")
	for e in [0.0, 0.25, 0.5, 0.75, 0.85, 0.90, 0.95, 1.0]:
		var rw: float = _axis_dist(pad_world(legs[0], float(e)))
		var re: float = _axis_dist(pad_world(legs[1], float(e)))
		var gw: float = gap_to_cylinder(core.outer_ring, pad_world(legs[0], float(e)),
			legs[0].global_transform.basis.x.normalized(), TRIM)
		var ge: float = gap_to_cylinder(core.outer_ring, pad_world(legs[1], float(e)),
			legs[1].global_transform.basis.x.normalized(), TRIM)
		print("  %.2f  %.4f  %+8.4f  %.4f  %+8.4f  %s" % [float(e), rw, gw, re, ge,
			str(absf(rw - re) < 1.0e-4)])

	# ---------- Q6: 摆角对双侧间隙的影响 ----------
	print("\n[Q6] 摆角 -> 双侧间隙（满行程 ext=1.0）")
	print("  angle    W_gap     E_gap    ring_lateral")
	for a in [0.0, 0.05, 0.10, 0.20, 0.30, 0.396, 0.58, -0.05, -0.10, -0.20, -0.396]:
		core.angle = float(a)
		core._update_visuals(0.0)
		await physics_frame
		var gw2: float = gap_to_cylinder(core.outer_ring, pad_world(legs[0], 1.0),
			legs[0].global_transform.basis.x.normalized(), TRIM)
		var ge2: float = gap_to_cylinder(core.outer_ring, pad_world(legs[1], 1.0),
			legs[1].global_transform.basis.x.normalized(), TRIM)
		var rc: Vector3 = core.outer_ring.global_transform.origin
		print("  %+.3f  %+8.4f  %+8.4f   %.3f" % [float(a), gw2, ge2,
			Vector2(rc.x - core.global_transform.origin.x, rc.z - core.global_transform.origin.z).length()])

	# ---------- Q7: outer_yaw 与凸台时序 ----------
	print("\n[Q7] outer_yaw 扫过时的凸台接触时序（ext=0.95，angle=0）")
	core.angle = 0.0
	core._update_visuals(0.0)
	await physics_frame
	for yaw_deg in [0, 10, 20, 30, 40, 45, 50, 60, 90]:
		core.outer_yaw = deg_to_rad(float(yaw_deg))
		core._apply_ring_pose()
		await physics_frame
		var gb: float = gap_to_cylinder(core.outer_ring, pad_world(legs[0], 0.95),
			legs[0].global_transform.basis.x.normalized(), BOSS)
		var gt: float = gap_to_cylinder(core.outer_ring, pad_world(legs[0], 0.95),
			legs[0].global_transform.basis.x.normalized(), TRIM)
		print("  yaw=%3d°  gap_to_boss=%+8.4f  gap_to_trim=%+8.4f  (凸台是否更早接触: %s)" % [
			int(yaw_deg), gb, gt, str(gb < gt - 0.01)])

	# ---------- Q8/Q9: 行程可达性 + 液压/承载匹配 ----------
	print("\n[Q8/Q9] 行程可达性与液压匹配")
	var r0: float = _axis_dist(pad_world(legs[0], 0.0))
	var r1: float = _axis_dist(pad_world(legs[0], 1.0))
	print("  R_pad(e=0)=%.4f  R_pad(e=1)=%.4f  ring_face=%.3f" % [r0, r1, TRIM])
	print("  可越过环面的富余量 = %.4f m（R0 仅 %.4f）" % [r1 - TRIM, 4.7664 - 4.76])
	print("  F_MAX=%.3f kN  活塞组=%.0f kg  PAWL_RATED=%.0f kN" % [
		StabilizerRig.F_MAX/1000.0, StabilizerRig.RAM_MASS, StabilizerRig.PAWL_RATED/1000.0])
	print("  弹性接触满推力压缩量 @k=2MN/m = %.4f m" % (StabilizerRig.F_MAX / 2.0e6))

	# ---------- Q10: 真实自由度 vs 脚本状态 ----------
	print("\n[Q10] 自由度盘点")
	print("  真实受力积分: extension/ram_velocity (1-DOF 活塞), core.angle/omega (1-DOF 摆动)")
	print("  脚本状态: latched(bool), stabilizer_states(bool[]), clamp_force(读回)")
	print("  非物理: R0 的 ring_reaction_force() 解析载荷, CONTACT_FRACTION 阈值")

	print("\n======== GEOMETRY VERDICT ========")
	print("R2_GEOM_DONE")
	quit(0)


func _axis_dist(p: Vector3) -> float:
	var ax: Vector3 = Vector3(core.global_transform.origin.x, 0.0, core.global_transform.origin.z)
	return Vector2(p.x - ax.x, p.z - ax.z).length()
