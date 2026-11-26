extends Node
## MECHANICS-004C · 第四幕真实升降出口门专项
##
## 全部断言在正式第四幕场景 res://scenes/act4.tscn 里执行。
## 门是真实 RigidBody3D（850 kg）+ SliderJoint3D 竖直导向 + 有限推力电机。
## 失败返回非零退出码；不删除任何断言。
##
## 记录的真实量：mass / motor_force / velocity / height / gravity /
## joint_error / contact / obstruction / clearance / exit_allowed

const GATE_LOCAL_DOOR_APPROACH := Vector3(-1.30, 0.05, 0.0)

var stage: Node
var gate: Node3D
var player: Node3D
var platform: Node
var crystal: Node3D
var hammer: Node

var checks: int = 0
var failures: int = 0
var log_lines: Array[String] = []
var _samples: Array[String] = []


func _ready() -> void:
	stage = (load("res://scenes/act4.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	gate = stage.get("gate") as Node3D
	player = stage.get("player") as Node3D
	platform = stage.get("platform") as Node
	crystal = stage.get("crystal_a") as Node3D
	hammer = stage.get("hammer") as Node
	if gate == null or player == null:
		_fail("E0", "第四幕缺少 gate/player")
		return _report()

	await _t1_load()
	await _t2_structure()
	await _t3_initial_closed()
	await _t4_story_conditions()
	await _t5_no_permission()
	await _t6_permission_granted()
	await _t7_real_force_rise()
	await _t8_gravity_present()
	await _t9_force_limit()
	await _t10_axis_direction()
	await _t11_no_drift()
	await _t12_coast_after_cut()
	await _t13_upper_stop()
	await _t14_top_hold()
	await _t15_partial_clearance_blocked()
	await _t16_full_open_passable()
	await _t17_static_obstacle_blocks()
	await _t18_stall_not_infinite()
	await _t19_obstacle_removed_recovers()
	await _t20_rigidbox_contact()
	await _t21_player_collision()
	await _t22_repeat_stability()
	await _t23_load_acceleration()
	await _t24_full_story_to_act5()
	_report()


# ---------------------------------------------------------------- 1 加载
func _t1_load() -> void:
	var ok: bool = stage.is_inside_tree() and gate.is_inside_tree() \
		and player.is_inside_tree() and stage.get("model") != null \
		and stage.get("network") != null and (stage.get("cradles") as Dictionary).size() == 4
	_check("E1 正式第四幕场景正常加载（门、玩家、共振模型、网络、4 个支架都在线）", ok,
		"gate=%s player=%s cradles=%d" % [str(gate != null), str(player != null),
			(stage.get("cradles") as Dictionary).size()])


# ---------------------------------------------------------------- 2 结构
func _t2_structure() -> void:
	var panel: Node = gate.get("_panel")
	var joint: Node = gate.get("_joint")
	var catch_beam: Node = gate.get("_catch")
	var mass: float = float(panel.get("mass")) if panel != null else 0.0
	var has_shape := false
	if panel != null:
		for child: Node in panel.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
				has_shape = true
	var layer: int = int(panel.get("collision_layer")) if panel != null else 0
	var mask: int = int(panel.get("collision_mask")) if panel != null else 0
	var ok: bool = panel is RigidBody3D and joint is SliderJoint3D \
		and catch_beam is StaticBody3D and absf(mass - 850.0) < 0.5 and has_shape \
		and layer != 0 and mask != 0 and not bool(panel.get("can_sleep"))
	_check("E2 门体质量/碰撞/关节真实存在（RigidBody3D 850 kg + BoxShape + SliderJoint3D + 承接梁 StaticBody，碰撞层非零且不靠休眠冻结）",
		ok, "panel=%s joint=%s catch=%s mass=%.0f shape=%s layer=%d mask=%d sleep=%s" % [
			panel.get_class() if panel != null else "-",
			joint.get_class() if joint != null else "-",
			catch_beam.get_class() if catch_beam != null else "-",
			mass, str(has_shape), layer, mask,
			str(panel.get("can_sleep")) if panel != null else "-"])


# ---------------------------------------------------------------- 3 初始关闭
func _t3_initial_closed() -> void:
	var d: Dictionary = gate.call("get_diagnostics")
	var ok: bool = absf(float(d["height"])) < 0.05 and not bool(d["is_open"]) \
		and not bool(d["exit_allowed"]) and str(d["state"]) == "closed" \
		and absf(float(d["velocity"])) < 0.02
	_check("E3 初始门关闭（高度 0、非开启、净空不足、无驱动）", ok,
		"height=%.3f state=%s open=%s allowed=%s" % [float(d["height"]), str(d["state"]),
			str(d["is_open"]), str(d["exit_allowed"])])


# ---------------------------------------------------------------- 4 剧情条件
func _t4_story_conditions() -> void:
	var story: Dictionary = stage.get("story") as Dictionary
	var objectives: Dictionary = story.get("objectives", {}) as Dictionary
	var has_chain: bool = str(objectives.get("memory_3", "")) != "" \
		and str(objectives.get("relay_a", "")) != "" \
		and str(objectives.get("freight", "")) != ""
	var seen: Dictionary = stage.get("seen_memories") as Dictionary
	var gate_node: Node = stage.get("gate")
	_check("E4 原有剧情条件保留（共振撞钟→记忆回声→晶体运输→b1/b3 中继→出口开启的目标文案与阶段机仍在）",
		has_chain and gate_node != null and int(stage.get("stage")) == 0,
		"memory_3=%s relay_a=%s freight=%s stage=%d" % [
			str(objectives.has("memory_3")), str(objectives.has("relay_a")),
			str(objectives.has("freight")), int(stage.get("stage"))])


# ---------------------------------------------------------------- 5 无条件不开
func _t5_no_permission() -> void:
	gate.call("reset_gate")
	await _w(60)
	gate.call("open")
	var peak := 0.0
	for _i in range(150):
		await get_tree().physics_frame
		peak = maxf(peak, absf(float(gate.get("motor_force"))))
	var d: Dictionary = gate.call("get_diagnostics")
	var ok: bool = peak < 1.0 and absf(float(d["height"])) < 0.05 \
		and not bool(d["drive_enabled"])
	_check("E5 未满足剧情条件时电机不能启动（open() 被拒，全程电机推力为 0，门高不变）",
		ok, "motor_peak=%.1f height=%.3f drive=%s" % [peak, float(d["height"]),
			str(d["drive_enabled"])])


# ---------------------------------------------------------------- 6 许可
func _t6_permission_granted() -> void:
	gate.call("reset_gate")
	await _w(30)
	var before: float = float(gate.get("height"))
	gate.call("unlock", "test_memory_3")
	await _w(90)
	var d: Dictionary = gate.call("get_diagnostics")
	# 授予许可本身不移动门：这是「条件满足 ≠ 已打开」的关键证据
	var ok: bool = bool(d["unlocked"]) and bool(d["drive_enabled"]) \
		and absf(float(d["height"]) - before) < 0.05 and not bool(d["is_open"])
	_check("E6 满足条件后仅授予电机驱动许可（drive_enabled=true，但门不会自己移动，is_open 仍为 false）",
		ok, "unlocked=%s drive=%s height=%.3f→%.3f is_open=%s" % [
			str(d["unlocked"]), str(d["drive_enabled"]), before, float(d["height"]),
			str(d["is_open"])])


# ---------------------------------------------------------------- 7 真实受力上升
func _t7_real_force_rise() -> void:
	gate.call("reset_gate")
	await _w(30)
	gate.call("unlock", "test")
	gate.call("open")
	var samples: Array[float] = []
	var force_seen := 0.0
	var moving_frames := 0
	for i in range(240):
		await get_tree().physics_frame
		force_seen = maxf(force_seen, absf(float(gate.get("motor_force"))))
		if absf(float(gate.get("velocity"))) > 0.05:
			moving_frames += 1
		if i % 20 == 0:
			samples.append(snappedf(float(gate.get("height")), 0.01))
	var d: Dictionary = gate.call("get_diagnostics")
	var monotonic := true
	for i in range(1, samples.size()):
		if samples[i] < samples[i - 1] - 0.01:
			monotonic = false
	var ok: bool = float(d["height"]) > 2.0 and monotonic and force_seen > 100.0 \
		and moving_frames > 60
	_check("E7 真实施力使门开始上升（apply_central_force 推动 850 kg 刚体，高度单调上升，非 Tween 时间表）",
		ok, "height=%.3f 采样=%s force_peak=%.0f moving_frames=%d" % [
			float(d["height"]), str(samples), force_seen, moving_frames])


# ---------------------------------------------------------------- 8 重力
func _t8_gravity_present() -> void:
	gate.call("reset_gate")
	await _w(60)
	var g_force: float = float(gate.get("gravity_force"))
	var panel: Node = gate.get("_panel")
	var gs: float = float(panel.get("gravity_scale")) if panel != null else 0.0
	# 关键实验：把电机推力上限压到远低于自重，门必须托不起来
	gate.call("unlock", "test")
	gate.set("motor_force_limit", 3000.0)
	gate.call("open")
	var peak := 0.0
	for _i in range(200):
		await get_tree().physics_frame
		peak = maxf(peak, float(gate.get("height")))
	var underpowered_height: float = float(gate.get("height"))
	gate.set("motor_force_limit", 12500.0)
	gate.call("reset_gate")
	await _w(60)
	var ok: bool = absf(g_force - 8330.0) < 50.0 and absf(gs - 1.0) < 0.001 \
		and underpowered_height < 0.25
	_check("E8 门受真实重力影响（M·g = 8330 N；电机上限压到 3000 N 时托不动门，门高几乎不变）",
		ok, "gravity_force=%.0f gravity_scale=%.2f 欠功率高度=%.3f" % [
			g_force, gs, underpowered_height])


# ---------------------------------------------------------------- 9 推力上限
func _t9_force_limit() -> void:
	gate.call("reset_gate")
	await _w(30)
	gate.call("unlock", "test")
	gate.call("open")
	var peak := 0.0
	for _i in range(300):
		await get_tree().physics_frame
		peak = maxf(peak, absf(float(gate.get("motor_force"))))
	var limit: float = float(gate.get("motor_force_limit"))
	_check("E9 电机推力不超过上限（F_motor 硬性钳制在 ±F_MOTOR_MAX）",
		peak <= limit + 1.0 and peak > 1000.0,
		"force_peak=%.1f limit=%.1f" % [peak, limit])


# ---------------------------------------------------------------- 10 轴方向
func _t10_axis_direction() -> void:
	gate.call("reset_gate")
	await _w(30)
	var joint: Node = gate.get("_joint")
	var axis_world: Vector3 = joint.global_transform.basis.x.normalized()
	var up_dot: float = axis_world.dot(Vector3.UP)
	gate.call("unlock", "test")
	gate.call("open")
	var p0: Vector3 = (gate.get("_panel") as Node3D).global_position
	for _i in range(120):
		await get_tree().physics_frame
	var p1: Vector3 = (gate.get("_panel") as Node3D).global_position
	var delta: Vector3 = p1 - p0
	var lateral: float = Vector2(delta.x, delta.z).length()
	var ok: bool = absf(up_dot - 1.0) < 0.02 and delta.y > 0.5 and lateral < 0.02
	_check("E10 升降约束方向正确（SliderJoint3D 世界轴 = +Y，门只沿竖直方向运动）",
		ok, "joint_axis_world=%s dot_up=%.4f Δy=%.3f 横向=%.4f" % [
			str(axis_world.snapped(Vector3(0.001, 0.001, 0.001))), up_dot, delta.y, lateral])


# ---------------------------------------------------------------- 11 无漂移
func _t11_no_drift() -> void:
	gate.call("reset_gate")
	await _w(30)
	gate.call("unlock", "test")
	gate.call("open")
	var max_err := 0.0
	var max_ang := 0.0
	for _i in range(300):
		await get_tree().physics_frame
		max_err = maxf(max_err, float(gate.get("joint_error")))
		max_ang = maxf(max_ang, float(gate.get("joint_angular_error")))
	_check("E11 门不横向漂移也不旋转（关节横向误差 < 2 cm，角误差 < 0.5°）",
		max_err < 0.02 and max_ang < 0.5,
		"max_joint_error=%.4f m max_angle_error=%.3f°" % [max_err, max_ang])


# ---------------------------------------------------------------- 12 松开动力
func _t12_coast_after_cut() -> void:
	gate.call("reset_gate")
	await _w(30)
	gate.call("unlock", "test")
	gate.call("open")
	# 升到中途，然后失电
	for _i in range(75):
		await get_tree().physics_frame
	var h0: float = float(gate.get("height"))
	var v0: float = float(gate.get("velocity"))
	gate.set("powered", false)
	var v_min := 0.0
	var h_min: float = h0
	var h_max: float = h0
	for _i in range(150):
		await get_tree().physics_frame
		v_min = minf(v_min, float(gate.get("velocity")))
		h_min = minf(h_min, float(gate.get("height")))
		h_max = maxf(h_max, float(gate.get("height")))
	var h1: float = float(gate.get("height"))
	gate.set("powered", true)
	# 失电后：先靠惯性继续上升一点（h_max > h0），随后被真实重力拉回下落
	# （速度出现明显负值，且高度真的从峰值掉下来）。
	var ok: bool = h_max > h0 + 0.01 and v_min < -0.5 and h1 < h_max - 0.1
	_check("E12 松开动力后运动合理（失电瞬间靠惯性继续上升，随后被真实重力拉回下落，速度转为明显负值）",
		ok, "h %.3f→peak %.3f→%.3f v0=%.2f v_min=%.2f" % [h0, h_max, h1, v0, v_min])


# ---------------------------------------------------------------- 13 上止挡
func _t13_upper_stop() -> void:
	gate.call("reset_gate")
	await _w(30)
	gate.call("unlock", "test")
	gate.call("open")
	var max_h := 0.0
	for _i in range(600):
		await get_tree().physics_frame
		max_h = maxf(max_h, float(gate.get("height")))
		if str(gate.get("_state")) == "open" and absf(float(gate.get("velocity"))) < 0.05:
			break
	var d: Dictionary = gate.call("get_diagnostics")
	var joint: Node = gate.get("_joint")
	var upper: float = float(joint.get("linear_limit/upper_distance"))
	var ok: bool = max_h <= upper + 0.06 and max_h >= 4.30
	_check("E13 顶部限位真实有效（门最高不超过关节 upper_limit，且真的到达开启位）",
		ok, "max_height=%.3f upper_limit=%.2f final=%.3f" % [max_h, upper, float(d["height"])])


# ---------------------------------------------------------------- 14 顶部保持
func _t14_top_hold() -> void:
	gate.call("reset_gate")
	await _w(30)
	gate.call("unlock", "test")
	gate.call("open")
	for _i in range(700):
		await get_tree().physics_frame
		if str(gate.get("_state")) == "open" and bool(gate.get("catch_engaged")):
			break
	# 机械承接是在状态切换的同一帧生效的；等两帧让电机断电落到读数上。
	await _w(6)
	var h_settled: float = float(gate.get("height"))
	var hold: String = str(gate.get("hold_mode"))
	var motor_after_settle: float = float(gate.get("motor_force"))
	# 机械承接后完全失电，门必须原地不动
	gate.set("powered", false)
	var h_min: float = h_settled
	var h_max: float = h_settled
	for _i in range(300):
		await get_tree().physics_frame
		h_min = minf(h_min, float(gate.get("height")))
		h_max = maxf(h_max, float(gate.get("height")))
	var drop: float = h_settled - h_min
	gate.set("powered", true)
	var ok: bool = bool(gate.get("catch_engaged")) and hold == "catch" \
		and absf(motor_after_settle) < 1.0 and drop < 0.02
	_check("E14 顶部机械保持真实有效（承接梁插到门底下方承重，电机断电 motor_force=0，失电 5 秒门仍不下落）",
		ok, "hold=%s catch=%s motor_at_top=%.1f 失电5秒最大下沉=%.4f m" % [
			hold, str(gate.get("catch_engaged")), motor_after_settle, drop])


# ---------------------------------------------------------------- 15 净空不足
func _t15_partial_clearance_blocked() -> void:
	gate.call("reset_gate")
	await _w(30)
	gate.call("unlock", "test")
	gate.call("open")
	# 升到一半（约 2.2 m，低于门洞上沿 4.20）时，把玩家放到门口
	var target := 2.0
	var guard := 0
	while float(gate.get("height")) < target and guard < 400:
		await get_tree().physics_frame
		guard += 1
	var mid_height: float = float(gate.get("height"))
	var mid_allowed: bool = bool(gate.get("exit_allowed"))
	var mid_open: bool = bool(gate.get("is_open"))
	# 直接驱动出口触发：净空不足时不允许过幕
	stage.call("_on_exit_entered")
	await _w(20)
	var completed_mid: bool = bool(stage.get("completed"))
	_check("E15 通行净空不足时不允许过幕（门升到 %.2f m < 4.20 m 时 exit_allowed=false，出口触发也不结算）"
			% mid_height,
		not mid_allowed and not mid_open and not completed_mid,
		"height=%.3f exit_allowed=%s is_open=%s completed=%s" % [
			mid_height, str(mid_allowed), str(mid_open), str(completed_mid)])


# ---------------------------------------------------------------- 16 完全开启
func _t16_full_open_passable() -> void:
	gate.call("reset_gate")
	await _w(30)
	gate.call("unlock", "test")
	gate.call("open")
	var guard := 0
	while not bool(gate.get("exit_allowed")) and guard < 900:
		await get_tree().physics_frame
		guard += 1
	var d: Dictionary = gate.call("get_diagnostics")
	# 玩家真的走进门洞：这是净空判定的实际证据（碰撞体必须真的让开）
	var door_world: Vector3 = gate.to_global(Vector3(0.0, 0.0, 0.0))
	player.call("teleport", Vector3(door_world.x, 0.05, door_world.z), 0.0)
	for _i in range(60):
		await get_tree().physics_frame
	var player_y: float = player.global_position.y
	var player_x: float = player.global_position.x
	# 玩家没有被门板挤出去：能站在门洞里
	var inside: bool = absf(player_x - door_world.x) < 1.2
	var ok: bool = bool(d["exit_allowed"]) and float(d["clearance"]) >= 4.20 \
		and str(d["hold_mode"]) != "none" and inside and player_y > -0.5
	_check("E16 完全开启后允许正常通行（净空 ≥ 4.20 m + 有保持机构，玩家能真的站进门洞不被门板挤开）",
		ok, "clearance=%.3f hold=%s exit_allowed=%s 玩家=(%.2f, %.2f)" % [
			float(d["clearance"]), str(d["hold_mode"]), str(d["exit_allowed"]),
			player_x, player_y])


# ---------------------------------------------------------------- 17 固定障碍
func _t17_static_obstacle_blocks() -> void:
	gate.call("reset_gate")
	await _w(30)
	var door_world: Vector3 = gate.to_global(Vector3(0.0, 0.0, 0.0))
	# 在门的升降路径上放一块真实静态障碍：门关闭时顶面 4.20，障碍下表面 5.05
	var blocker: StaticBody3D = StaticBody3D.new()
	blocker.name = "Mech004CBlocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.4, 0.50, 5.4)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = Vector3(door_world.x, 5.30, door_world.z)
	stage.add_child(blocker)
	await _w(20)
	gate.call("unlock", "test")
	gate.call("open")
	var max_h := 0.0
	for _i in range(300):
		await get_tree().physics_frame
		max_h = maxf(max_h, float(gate.get("height")))
	var blocked_height: float = float(gate.get("height"))
	# 穿透量必须按**最高点**算：堵转保护断电后门会被重力拉回一点，
	# 用瞬时高度算会把「回弹」误判成「穿透」。
	var peak_penetration: float = 5.05 - (max_h + 4.20)
	var d: Dictionary = gate.call("get_diagnostics")
	var ok: bool = max_h < 1.10 and max_h > 0.10 \
		and peak_penetration < 0.06 and not bool(d["exit_allowed"])
	_check("E17 固定障碍真实阻挡门体（门顶撞到静态障碍后停下，不穿透，净空不足故不放行）",
		ok, "最高点=%.3f 峰值穿透=%.4f m 当前高度=%.3f exit_allowed=%s contacts=%d" % [
			max_h, peak_penetration, blocked_height, str(d["exit_allowed"]),
			int(d["contact_count"])])
	blocker.queue_free()
	await _w(30)


# ---------------------------------------------------------------- 18 堵转
func _t18_stall_not_infinite() -> void:
	gate.call("reset_gate")
	await _w(30)
	var door_world: Vector3 = gate.to_global(Vector3(0.0, 0.0, 0.0))
	var blocker: StaticBody3D = StaticBody3D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.4, 0.50, 5.4)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = Vector3(door_world.x, 5.30, door_world.z)
	stage.add_child(blocker)
	await _w(20)
	gate.call("unlock", "test")
	gate.call("open")
	# 让它先撞上并进入堵转
	for _i in range(240):
		await get_tree().physics_frame
	var stall_seen: bool = bool(gate.get("obstruction"))
	# 统计 4 秒内的平均推力：堵转保护必须让平均推力显著低于额定
	var sum := 0.0
	var frames := 0
	var zero_frames := 0
	for _i in range(240):
		await get_tree().physics_frame
		var f: float = absf(float(gate.get("motor_force")))
		sum += f
		frames += 1
		if f < 1.0:
			zero_frames += 1
	var avg: float = sum / float(maxi(frames, 1))
	var limit: float = float(gate.get("motor_force_limit"))
	var duty_off: float = float(zero_frames) / float(maxi(frames, 1))
	var ok: bool = stall_seen and avg < limit * 0.75 and duty_off > 0.25
	_check("E18 有障碍时电机不会无限强推（识别堵转，进入间歇占空比：平均推力 < 额定的 75%，存在断电帧）",
		ok, "stall=%s avg_force=%.0f (limit %.0f, %.0f%%) 断电帧占比=%.0f%%" % [
			str(stall_seen), avg, limit, avg / limit * 100.0, duty_off * 100.0])
	blocker.queue_free()
	await _w(30)


# ---------------------------------------------------------------- 19 移走障碍
func _t19_obstacle_removed_recovers() -> void:
	gate.call("reset_gate")
	await _w(30)
	var door_world: Vector3 = gate.to_global(Vector3(0.0, 0.0, 0.0))
	var blocker: StaticBody3D = StaticBody3D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.4, 0.50, 5.4)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = Vector3(door_world.x, 5.30, door_world.z)
	stage.add_child(blocker)
	await _w(20)
	gate.call("unlock", "test")
	gate.call("open")
	for _i in range(240):
		await get_tree().physics_frame
	var blocked_at: float = float(gate.get("height"))
	blocker.queue_free()
	await _w(30)
	var guard := 0
	while not bool(gate.get("exit_allowed")) and guard < 1200:
		await get_tree().physics_frame
		guard += 1
	var d: Dictionary = gate.call("get_diagnostics")
	var ok: bool = blocked_at < 1.10 and float(d["height"]) > 4.2 \
		and bool(d["exit_allowed"]) and not bool(d["obstruction"])
	_check("E19 移走障碍后机构恢复（同一台电机继续把门推到开启位并恢复通行）",
		ok, "被挡在 %.3f m → 恢复后 %.3f m exit_allowed=%s stall=%s" % [
			blocked_at, float(d["height"]), str(d["exit_allowed"]), str(d["obstruction"])])


# ---------------------------------------------------------------- 20 可动刚体
func _t20_rigidbox_contact() -> void:
	gate.call("reset_gate")
	await _w(30)
	var door_world: Vector3 = gate.to_global(Vector3(0.0, 0.0, 0.0))
	# 独立的 40 kg RigidBody3D 箱子放进升降路径：不冻结、不关碰撞、不写 transform。
	# 尺寸 0.40 是为了真的能进门袋（门袋内腔横向只有 0.72 m）。
	var crate: RigidBody3D = RigidBody3D.new()
	crate.name = "Mech004CCrate"
	crate.mass = 40.0
	crate.collision_layer = 8
	crate.collision_mask = 1 | 2 | 4 | 8
	crate.can_sleep = false
	crate.contact_monitor = true
	crate.max_contacts_reported = 4
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.40, 0.40, 0.40)
	shape.shape = box
	crate.add_child(shape)
	# 门顶 4.205，箱子底面落在 4.21（正好压在门上）
	crate.position = Vector3(door_world.x, 4.41, door_world.z)
	stage.add_child(crate)
	for _i in range(120):
		await get_tree().physics_frame
	var crate_y0: float = crate.global_position.y
	var door_h0: float = float(gate.get("height"))
	gate.call("unlock", "test")
	gate.call("open")
	var crate_contacts := 0
	for _i in range(420):
		await get_tree().physics_frame
		if crate.get_contact_count() > 0:
			crate_contacts += 1
	var crate_rise: float = crate.global_position.y - crate_y0
	var door_rise: float = float(gate.get("height")) - door_h0
	# 全程没有任何脚本写 crate 的位置或速度：它上升只可能来自门体接触。
	var ok: bool = crate_rise > 0.30 and door_rise > 0.30 and crate_contacts > 10
	_check("E20 可动刚体受到门体真实接触（40 kg 箱子被门顶起，箱子自身接触计数持续非零，脚本从未移动它）",
		ok, "crate_rise=%.3f door_rise=%.3f 有接触帧=%d crate_mass=%.0f" % [
			crate_rise, door_rise, crate_contacts, float(crate.mass)])
	crate.queue_free()
	await _w(40)


# ---------------------------------------------------------------- 21 玩家碰撞
func _t21_player_collision() -> void:
	gate.call("reset_gate")
	await _w(60)
	var door_world: Vector3 = gate.to_global(Vector3(0.0, 0.0, 0.0))
	# 门关闭时，玩家从矿室侧走向门：必须被门板挡住，不能穿过去
	player.call("teleport", Vector3(door_world.x - 1.6, 0.05, door_world.z), 0.0)
	player.call("aim_camera_at", Vector3(door_world.x + 5.0, 1.2, door_world.z), -0.05)
	for _i in range(30):
		await get_tree().physics_frame
	Input.action_press("move_forward")
	for _i in range(150):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await _w(20)
	var stopped_x: float = player.global_position.x
	var blocked: bool = stopped_x < door_world.x - 0.15
	# 门开始上升、玩家站在门洞里：门不会把玩家挤穿地面或墙壁
	gate.call("unlock", "test")
	gate.call("open")
	for _i in range(240):
		await get_tree().physics_frame
	var y_after: float = player.global_position.y
	var ok: bool = blocked and y_after > -0.5 and absf(y_after) < 3.0
	_check("E21 玩家与门的碰撞正常（关门时被门板真实挡住；门上升时玩家不被挤进地面或墙壁）",
		ok, "关门后玩家 x=%.2f（门在 %.2f）门升后 y=%.2f" % [
			stopped_x, door_world.x, y_after])


# ---------------------------------------------------------------- 22 重复开关
func _t22_repeat_stability() -> void:
	gate.call("reset_gate")
	await _w(40)
	var results: Array[String] = []
	var all_ok := true
	for round_index in range(5):
		gate.call("reset_gate")
		await _w(50)
		gate.call("unlock", "round_%d" % round_index)
		gate.call("open")
		var guard := 0
		while not bool(gate.get("exit_allowed")) and guard < 1200:
			await get_tree().physics_frame
			guard += 1
		var max_err := 0.0
		var max_ang := 0.0
		for _i in range(60):
			await get_tree().physics_frame
			max_err = maxf(max_err, float(gate.get("joint_error")))
			max_ang = maxf(max_ang, float(gate.get("joint_angular_error")))
		var h: float = float(gate.get("height"))
		var ok: bool = bool(gate.get("exit_allowed")) and max_err < 0.03 and max_ang < 1.0 \
			and h > 4.2
		all_ok = all_ok and ok
		results.append("R%d h=%.2f err=%.4f ang=%.2f" % [round_index + 1, h, max_err, max_ang])
	_check("E22 重复开关或复位后关节稳定（连续 5 轮 复位→开门→开启，关节误差始终 < 3 cm、角误差 < 1°）",
		all_ok, str(results))


# ---------------------------------------------------------------- 23 负载差异
func _t23_load_acceleration() -> void:
	gate.call("reset_gate")
	await _w(40)
	# 空载：额定 850 kg
	var empty_time: float = await _time_to_height(1.5)
	# 超载：把门体质量临时抬到 2400 kg（真实改变 M，不改变电机推力上限）
	var panel: RigidBody3D = gate.get("_panel") as RigidBody3D
	gate.call("reset_gate")
	await _w(40)
	panel.mass = 2400.0
	gate.call("unlock", "test")
	gate.call("open")
	var heavy_time: float = await _time_to_height(1.5)
	panel.mass = 850.0
	gate.call("reset_gate")
	await _w(40)
	var ratio: float = heavy_time / maxf(empty_time, 0.001)
	var ok: bool = ratio > 1.8 and heavy_time > empty_time + 0.3
	_check("E23 不同负载下加速度具有合理差异（M 从 850 → 2400 kg，同样推力下升到 1.5 m 的时间显著变长）",
		ok, "空载 %.2f s / 2400 kg %.2f s，比值 %.2f" % [empty_time, heavy_time, ratio])


func _time_to_height(target: float) -> float:
	gate.call("unlock", "test")
	gate.call("open")
	var frames := 0
	for _i in range(1200):
		await get_tree().physics_frame
		frames += 1
		if float(gate.get("height")) >= target:
			break
	return float(frames) / 60.0


# ---------------------------------------------------------------- 24 完整剧情
func _t24_full_story_to_act5() -> void:
	stage.call("reset_level")
	await _w(150)
	# 剧情链的物理前提：两块晶体都真实落进 b1 / b3 叉口并由锁爪夹住。
	# 这里不伪造门的状态，只让「晶体真的在中继上」与「三段记忆已看到」这两个
	# 剧情条件成立；门自己受力上升，玩家自己走进出口。
	var cradles: Dictionary = stage.get("cradles") as Dictionary
	var seated := 0
	for entry: Array in [["b1", stage.get("crystal_b")], ["b3", stage.get("crystal_a")]]:
		var key: String = str(entry[0])
		var cradle: Node3D = cradles.get(key) as Node3D
		var c: Node3D = entry[1] as Node3D
		if cradle == null or c == null:
			continue
		if await _seat_and_clamp(cradle, c):
			seated += 1
	var b1_ok: bool = bool(stage.call("_relay_ready", "b1"))
	var b3_ok: bool = bool(stage.call("_relay_ready", "b3"))
	# 三段记忆：走 Game 的真实回调，让剧情状态机自己推进（不直接改门状态）
	var seen: Dictionary = stage.get("seen_memories") as Dictionary
	for index: int in [1, 2, 3]:
		seen[index] = true
		stage.call("_on_memory_finished", index)
		await _w(60)
	# 等门自己受力开到位
	var guard := 0
	while not bool(gate.get("exit_allowed")) and guard < 1800:
		await get_tree().physics_frame
		guard += 1
	var d: Dictionary = gate.call("get_diagnostics")
	var unlocked: bool = bool(d["unlocked"])
	var allowed: bool = bool(d["exit_allowed"])
	# 玩家真的走进出口触发区（不是直接调 _on_exit_entered）
	stage.set_meta("suppress_act5", true)
	var door_world: Vector3 = gate.to_global(Vector3(0.0, 0.0, 0.0))
	player.call("teleport", Vector3(door_world.x + 1.0, 0.05, door_world.z), 0.0)
	await _w(20)
	Input.action_press("move_forward")
	for _i in range(180):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await _w(90)
	var completed: bool = bool(stage.get("completed"))
	var payload: Dictionary = stage.call("completion_payload") as Dictionary
	var ok: bool = seated == 2 and b1_ok and b3_ok and unlocked and allowed and completed \
		and bool(payload.get("gate_open", false))
	_check("E24 实际完成第四幕（b1/b3 真实落座 + 三段记忆 → 门受力开启 → 玩家真实走进出口 → completed）",
		ok, "中继落座=%d/2 b1=%s b3=%s unlocked=%s clearance=%.2f exit_allowed=%s completed=%s payload.gate_open=%s" % [
			seated, str(b1_ok), str(b3_ok), str(unlocked), float(d["clearance"]),
			str(allowed), str(completed), str(payload.get("gate_open", false))])
	if not completed:
		print("DIAG_E24 ", JSON.stringify(_clean(d)))


## 把一块晶体真的丢进支架叉口，然后按 E 合拢锁爪（与 004A 相同的真实路径）。
func _seat_and_clamp(cradle: Node3D, crystal: Node3D) -> bool:
	if bool(cradle.call("is_occupied")):
		cradle.call("release")
		crystal.set("is_seated", false)
	crystal.set("is_carried", false)
	crystal.set("freeze", false)
	crystal.call("set_collision_enabled", true)
	var yaw_deg: float = float(cradle.get("required_yaw_deg"))
	crystal.global_position = (cradle.call("get_seat_position") as Vector3) + Vector3(0.0, 1.20, 0.0)
	crystal.rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	crystal.set("held_yaw_deg", yaw_deg)
	crystal.set("linear_velocity", Vector3.ZERO)
	crystal.set("angular_velocity", Vector3.ZERO)
	for _i in range(180):
		await get_tree().physics_frame
		if bool(cradle.call("is_occupied")):
			break
	if not bool(cradle.call("is_occupied")):
		return false
	# 站到支架前按 E（真实交互，不是直接调 open_clamp）
	var at: Vector3 = (cradle.call("get_interaction_position") as Vector3) + Vector3(0.0, 0.0, 1.50)
	player.call("teleport", at, 0.0)
	player.call("aim_camera_at", cradle.call("get_interaction_position"), -0.02)
	await _w(24)
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	for _i in range(300):
		await get_tree().physics_frame
		if bool(cradle.get("latched")):
			break
	await _w(20)
	return bool(cradle.call("locked"))


# ================================================================ 工具
func _check(label: String, ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	var line := "%s  %s  |  %s" % ["PASS" if ok else "FAIL", label, detail]
	log_lines.append(line)
	print(line)


func _fail(tag: String, detail: String) -> void:
	checks += 1
	failures += 1
	print("FAIL  %s  %s" % [tag, detail])


func _report() -> void:
	print("MECH004C_DONE checks=%d passed=%d failures=%d" % [
		checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame


func _clean(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d.keys():
		var v: Variant = d[k]
		if v is Vector3:
			out[str(k)] = str((v as Vector3).snapped(Vector3(0.001, 0.001, 0.001)))
		elif v is float:
			out[str(k)] = snappedf(float(v), 0.001)
		else:
			out[str(k)] = v
	return out
