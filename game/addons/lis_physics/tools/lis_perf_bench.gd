class_name LISPerfBench
extends Node3D
## LIS Physics SDK · 性能基准工具（随 SDK 交付，可复跑）
##
##   godot --headless --path <工程> res://addons/lis_physics/tools/lis_perf_bench.tscn
##   godot --path <工程> res://addons/lis_physics/tools/lis_perf_bench.tscn      （窗口模式，可测真实 FPS）
##
## 测量原则（任务书 §17）：
##   * **不使用 --fixed-fps**：那只是把 delta 固定成 1/60，测出来的不是真实帧率；
##   * 先做**计时器自检**：确认 Time.get_ticks_usec() 的刻度与真实时间一致，
##     否则后面所有 P95/P99 都不可信；
##   * 同时记录"物理计算耗时"与"墙钟耗时"，两者不能混为一谈；
##   * 报告平均值 / P95 / P99 / 最大值，不只报平均；
##   * 记录活跃刚体数、接触对数、峰值内存；
##   * 检查异常：NaN、穿透、弹飞、关节失效。
##
## 判定口径：本工具**只产数据，不产 GO**。
## 性能门禁是否通过由独立的性能验收决定 —— 工具不会为了让结果好看而改阈值。

## 场景清单：[名称, 刚体数, 是否堆叠, 是否高频接触]
const SCENARIOS := [
	["bodies_20", 20, false, false],
	["bodies_50", 50, false, false],
	["bodies_100", 100, false, false],
	["bodies_200", 200, false, false],
	["stack_layers", 60, true, false],
	["high_contact", 40, false, true],
	["machine_combo", 24, false, false],
	["rope_pulley", 30, false, false],
	["cart_loaded", 14, false, false],
	["multi_player", 12, false, false],
]

## 每场景的采样帧数（预热之后）。
@export var sample_frames: int = 240
## 预热帧数。
@export var warmup_frames: int = 60
## 是否在每个场景结束后清理（true 才能隔离场景间影响）。
@export var cleanup_between: bool = true
## 结果输出路径（user:// 与工程内各写一份）。
@export var output_path: String = "user://lis_perf_result.json"
## 只在指定场景上跑（留空 = 全部）。
@export var only_scenario: String = ""

var results: Array[Dictionary] = []
var _current_root: Node3D = null


func _ready() -> void:
	print("LIS_PERF_START version=%s" % LISPhysics.SDK_VERSION)
	# 有真实显示服务器时关掉垂直同步：否则 FPS 被显示器刷新率钉死，
	# 读到的只是"屏幕上限"而不是"引擎能力"。
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		print("LIS_PERF_VSYNC disabled")
	await get_tree().process_frame
	# 先做计时器自检：不可信就明确报告，不继续产假数据。
	var timer_ok: bool = await _check_timer()
	if not timer_ok:
		print("LIS_PERF_TIMER_UNTRUSTED 计时器自检未通过，性能数据不可信")
		get_tree().quit(3)
		return
	await _run_all()
	_write_report()
	await get_tree().process_frame
	get_tree().quit(0)


## 计时器自检：用 OS.delay_usec 校准 Time.get_ticks_usec。
## 若测得的睡眠时间与请求值偏差超过 25%，说明计时或调度不可信。
func _check_timer() -> bool:
	var probes: Array[float] = []
	for i in range(5):
		var t0: int = Time.get_ticks_usec()
		OS.delay_usec(20000)
		var dt: float = float(Time.get_ticks_usec() - t0) / 1000.0
		probes.append(dt)
	probes.sort()
	var median: float = probes[probes.size() / 2]
	var err: float = absf(median - 20.0) / 20.0
	print("LIS_PERF_TIMER median_20ms_sleep=%.2fms error=%.1f%%" % [median, err * 100.0])
	return err < 0.25


func _run_all() -> void:
	for entry: Array in SCENARIOS:
		var nm: String = str(entry[0])
		if only_scenario != "" and only_scenario != nm:
			continue
		await _run_scenario(nm, int(entry[1]), bool(entry[2]), bool(entry[3]))


func _run_scenario(nm: String, count: int, stacked: bool, high_contact: bool) -> void:
	_current_root = Node3D.new()
	_current_root.name = "Scenario_%s" % nm
	add_child(_current_root)
	_build_floor()
	var bodies: Array[RigidBody3D] = []
	if nm == "machine_combo":
		await _build_machine_combo()
	elif nm == "rope_pulley":
		await _build_rope_pulley()
	elif nm == "cart_loaded":
		await _build_cart_loaded()
	elif nm == "multi_player":
		await _build_multi_player()
	else:
		_build_bodies(count, stacked, high_contact)
	await _wait_frames(warmup_frames)

	# --- 采样 ----------------------------------------------------------
	#
	# 【为什么不能把"await physics_frame 的墙钟"当 FPS】
	# 物理帧由引擎按 physics_ticks_per_second 调度；等待一帧物理帧的墙钟时间
	# 在无头模式下**恒等于 1/60 s**，与场景负载完全无关。
	# 直接拿它算 FPS 会得到"20 刚体和 200 刚体都是 60 FPS"的假数据。
	#
	# 因此这里采集两类量，分别有明确含义：
	#   frame_us   主循环每帧的墙钟间隔（反映引擎调度节奏，headless 下受 60 Hz 限流）
	#   physics_us 引擎自报的每物理步 CPU 耗时（**真正的负载指标**）
	# 以及主动统计的刚体数/接触数（Jolt 下 Performance 的 3D 统计不可靠，会恒为 0）。
	var frame_us: Array[int] = []
	var physics_us: Array[float] = []
	var active_samples: Array[int] = []
	var pair_samples: Array[int] = []
	var wall_start: int = Time.get_ticks_usec()
	for i in range(sample_frames):
		var t0: int = Time.get_ticks_usec()
		await get_tree().physics_frame
		var dt: int = Time.get_ticks_usec() - t0
		frame_us.append(dt)
		physics_us.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0)
		active_samples.append(_count_active_bodies())
		pair_samples.append(_count_contact_pairs())
	var wall_elapsed_s: float = float(Time.get_ticks_usec() - wall_start) / 1_000_000.0

	# --- 统计 ----------------------------------------------------------
	var stats: Dictionary = _percentiles(frame_us)
	var pstats: Dictionary = _percentiles_float(physics_us)
	var anomalies: Dictionary = _scan_anomalies()
	var active_bodies: int = _avg_int(active_samples)
	var collision_pairs: int = _avg_int(pair_samples)
	var mem_static: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var mem_peak: float = OS.get_static_memory_peak_usage() / 1048576.0
	var fps: float = float(sample_frames) / maxf(wall_elapsed_s, 0.001)
	var real_fps: float = Engine.get_frames_per_second()
	# 物理预算占用比：physics_ms_p99 占一个物理步（16.67 ms @60 Hz）的比例。
	# 这是"还能不能再加物体"的直接指标，比 FPS 更能说明负载。
	var tick_ms: float = 1000.0 / float(maxi(LISPhysics.physics_ticks_per_second(), 1))
	var budget_pct: float = (pstats["p99"] / 1000.0) / tick_ms * 100.0

	var rec: Dictionary = {
		"scenario": nm,
		"bodies_requested": count,
		"frames": sample_frames,
		"wall_s": snappedf(wall_elapsed_s, 0.001),
		"fps_wall": snappedf(fps, 0.1),
		"fps_engine": snappedf(real_fps, 0.1),
		"frame_ms_avg": snappedf(stats["avg"] / 1000.0, 0.001),
		"frame_ms_p95": snappedf(stats["p95"] / 1000.0, 0.001),
		"frame_ms_p99": snappedf(stats["p99"] / 1000.0, 0.001),
		"frame_ms_max": snappedf(stats["max"] / 1000.0, 0.001),
		"physics_ms_avg": snappedf(pstats["avg"] / 1000.0, 0.001),
		"physics_ms_p95": snappedf(pstats["p95"] / 1000.0, 0.001),
		"physics_ms_p99": snappedf(pstats["p99"] / 1000.0, 0.001),
		"physics_ms_max": snappedf(pstats["max"] / 1000.0, 0.001),
		"physics_budget_pct_p99": snappedf(budget_pct, 0.1),
		"active_bodies": active_bodies,
		"collision_pairs": collision_pairs,
		"mem_static_mb": snappedf(mem_static, 0.1),
		"mem_peak_mb": snappedf(mem_peak, 0.1),
		"nan_or_inf": int(anomalies["nan"]),
		"below_floor": int(anomalies["below"]),
		"flying": int(anomalies["flying"]),
		"broken_joints": int(anomalies["broken_joints"]),
	}
	results.append(rec)
	print("LIS_PERF scenario=%s bodies=%d active=%d pairs=%d physics_ms avg=%.2f p95=%.2f p99=%.2f max=%.2f budget=%.1f%% frame_ms avg=%.2f p99=%.2f engine_fps=%.1f mem=%.1f/%.1fMB nan=%d below=%d flying=%d broken=%d" % [
		nm, count, active_bodies, collision_pairs, rec["physics_ms_avg"],
		rec["physics_ms_p95"], rec["physics_ms_p99"], rec["physics_ms_max"],
		budget_pct, rec["frame_ms_avg"], rec["frame_ms_p99"], real_fps,
		mem_static, mem_peak, rec["nan_or_inf"], rec["below_floor"],
		rec["flying"], rec["broken_joints"]])

	if cleanup_between:
		_current_root.queue_free()
		_current_root = null
		await _wait_frames(10)


func _build_floor() -> void:
	var f: StaticBody3D = StaticBody3D.new()
	f.name = "PerfFloor"
	f.collision_layer = LISPhysics.LAYER_WORLD
	f.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = Vector3(120, 0.4, 120)
	cs.shape = bs
	cs.position = Vector3(0.0, -0.2, 0.0)
	f.add_child(cs)
	var m: PhysicsMaterial = PhysicsMaterial.new()
	m.friction = 0.8
	m.rough = false
	f.physics_material_override = m
	_current_root.add_child(f)


func _build_bodies(count: int, stacked: bool, high_contact: bool) -> void:
	var side: int = int(ceil(sqrt(float(count))))
	for i in range(count):
		var b: LISBody = LISBody.new()
		b.name = "P%03d" % i
		b.body_size = Vector3(0.4, 0.4, 0.4)
		b.mass_kg = 6.0
		b.auto_build_visual = false
		_current_root.add_child(b)
		var gx: int = i % side
		var gz: int = i / side
		var y: float = 0.21
		if stacked:
			y = 0.21 + float(i % 5) * 0.42
			gx = i / 5
			gz = 0
		b.global_position = Vector3(float(gx) * 0.9 - 10.0, y, float(gz) * 0.9 - 10.0)
		if high_contact:
			b.linear_velocity = Vector3(0.0, -6.0, 0.0)
		b.contact_monitor = true
		b.max_contacts_reported = 4


func _build_machine_combo() -> void:
	var cart: LISCart = LISCart.new()
	cart.name = "PerfCart"
	_current_root.add_child(cart)
	cart.global_position = Vector3(0.0, 0.60, 0.0)
	var lever: LISLever = LISLever.new()
	lever.name = "PerfLever"
	_current_root.add_child(lever)
	lever.global_position = Vector3(8.0, LISLever.PIVOT_HEIGHT, 0.0)
	var door: LISMotorDoor = LISMotorDoor.new()
	door.name = "PerfDoor"
	_current_root.add_child(door)
	door.global_position = Vector3(-8.0, 0.0, 0.0)
	door.set_request(true)
	for i in range(12):
		var b: LISBody = LISBody.new()
		b.name = "PB%d" % i
		b.body_size = Vector3(0.5, 0.5, 0.5)
		b.mass_kg = 10.0
		b.auto_build_visual = false
		_current_root.add_child(b)
		b.global_position = Vector3(-4.0 + float(i) * 0.8, 0.6 + float(i % 3) * 0.5, 6.0)


func _build_rope_pulley() -> void:
	var rope: LISRope = LISRope.new()
	rope.name = "PerfRope"
	rope.build_visual = false
	_current_root.add_child(rope)
	await get_tree().physics_frame
	rope.build(24, 0.34, Vector3(-8.0, 6.0, 0.0), Vector3.RIGHT, true, 0.0)
	var pulley: LISPulley = LISPulley.new()
	pulley.name = "PerfPulley"
	_current_root.add_child(pulley)
	pulley.global_position = Vector3(0.0, 6.0, 0.0)
	await get_tree().physics_frame
	for i in range(6):
		var b: LISBody = LISBody.new()
		b.name = "PR%d" % i
		b.body_size = Vector3(0.5, 0.5, 0.5)
		b.mass_kg = 20.0
		b.auto_build_visual = false
		_current_root.add_child(b)
		b.global_position = Vector3(6.0, 0.3 + float(i) * 0.55, 2.0 * float(i))


func _build_cart_loaded() -> void:
	var cart: LISCart = LISCart.new()
	cart.name = "PerfLoadedCart"
	_current_root.add_child(cart)
	cart.global_position = Vector3(0.0, 0.60, 0.0)
	await get_tree().physics_frame
	for i in range(8):
		var b: LISBody = LISBody.new()
		b.name = "PC%d" % i
		b.body_size = Vector3(0.35, 0.35, 0.35)
		b.mass_kg = 8.0
		b.auto_build_visual = false
		_current_root.add_child(b)
		b.global_position = Vector3(-0.3 + 0.3 * float(i % 3), 0.95 + 0.4 * float(i / 3), -0.4 + 0.4 * float(i % 2))


func _build_multi_player() -> void:
	var crate: LISBody = LISBody.new()
	crate.name = "PerfCrate"
	crate.body_size = Vector3(1.2, 1.0, 1.0)
	crate.mass_kg = 90.0
	crate.auto_build_visual = false
	_current_root.add_child(crate)
	crate.global_position = Vector3(0.0, 0.6, 0.0)
	for i in range(4):
		var ang: float = TAU * float(i) / 4.0
		var root: Node3D = Node3D.new()
		root.name = "PerfP%d" % i
		_current_root.add_child(root)
		root.global_position = Vector3(cos(ang) * 2.4, 1.4, sin(ang) * 2.4)
		var cam: Camera3D = Camera3D.new()
		cam.name = "Cam"
		root.add_child(cam)
		cam.global_position = root.global_position
		cam.look_at(crate.global_position + Vector3(0.0, 0.4, 0.0), Vector3.UP)
		var ad: LISFirstPersonAdapter = LISFirstPersonAdapter.new()
		ad.name = "Ad"
		ad.read_input = false
		ad.player_id = i + 1
		root.add_child(ad)
		ad.body = root
		ad.camera = cam
		await get_tree().physics_frame
		ad.grab(crate)


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


## 统计场景里真正参与积分的刚体数。
## Jolt 下 Performance.PHYSICS_3D_ACTIVE_OBJECTS 会恒为 0（实测），
## 所以自己遍历计数，得到的是"场景里有多少刚体"这个确定的事实。
func _count_active_bodies() -> int:
	if _current_root == null:
		return 0
	var n: int = 0
	var stack: Array[Node] = [_current_root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is RigidBody3D and not (cur as RigidBody3D).freeze:
			n += 1
		for c: Node in cur.get_children():
			stack.append(c)
	return n


## 统计接触点数（所有开接触监视的刚体之和）。
func _count_contact_pairs() -> int:
	if _current_root == null:
		return 0
	var n: int = 0
	var stack: Array[Node] = [_current_root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is RigidBody3D:
			var rb: RigidBody3D = cur as RigidBody3D
			if rb.contact_monitor:
				n += rb.get_contact_count()
		for c: Node in cur.get_children():
			stack.append(c)
	return n


func _avg_int(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var total: int = 0
	for v: int in values:
		total += v
	return total / values.size()


func _percentiles(us: Array[int]) -> Dictionary:
	var copy: Array[int] = us.duplicate()
	copy.sort()
	var n: int = copy.size()
	if n == 0:
		return {"avg": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var total: float = 0.0
	for v: int in copy:
		total += float(v)
	return {
		"avg": total / float(n),
		"p95": float(copy[mini(int(float(n) * 0.95), n - 1)]),
		"p99": float(copy[mini(int(float(n) * 0.99), n - 1)]),
		"max": float(copy[n - 1]),
	}


func _percentiles_float(us: Array[float]) -> Dictionary:
	var copy: Array[float] = us.duplicate()
	copy.sort()
	var n: int = copy.size()
	if n == 0:
		return {"avg": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var total: float = 0.0
	for v: float in copy:
		total += v
	return {
		"avg": total / float(n),
		"p95": copy[mini(int(float(n) * 0.95), n - 1)],
		"p99": copy[mini(int(float(n) * 0.99), n - 1)],
		"max": copy[n - 1],
	}


func _scan_anomalies() -> Dictionary:
	var nan_count: int = 0
	var below: int = 0
	var flying: int = 0
	var broken: int = 0
	if _current_root == null:
		return {"nan": 0, "below": 0, "flying": 0, "broken_joints": 0}
	var stack: Array[Node] = [_current_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is RigidBody3D:
			var rb: RigidBody3D = n as RigidBody3D
			if not LISPhysics.is_finite_vec3(rb.global_position) \
					or not LISPhysics.is_finite_vec3(rb.linear_velocity):
				nan_count += 1
			else:
				if rb.global_position.y < -3.0:
					below += 1
				if rb.linear_velocity.length() > 60.0:
					flying += 1
		elif n is Joint3D:
			if not LISJointKit.is_wired(n as Joint3D):
				broken += 1
		for c: Node in n.get_children():
			stack.append(c)
	return {"nan": nan_count, "below": below, "flying": flying, "broken_joints": broken}


func _write_report() -> void:
	var payload: Dictionary = {
		"tool": "lis_perf_bench",
		"sdk_version": LISPhysics.SDK_VERSION,
		"measured_at": Time.get_datetime_string_from_system(true),
		"godot_version": str(Engine.get_version_info().get("string", "?")),
		"physics_engine": LISPhysics.physics_engine_name(),
		"physics_ticks": LISPhysics.physics_ticks_per_second(),
		"os": OS.get_name(),
		"os_version": OS.get_version(),
		"cpu": OS.get_processor_name(),
		"cpu_count": OS.get_processor_count(),
		"display_driver": DisplayServer.get_name(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"headless": DisplayServer.get_name() == "headless",
		"fixed_fps_used": false,
		"sample_frames": sample_frames,
		"warmup_frames": warmup_frames,
		"scenarios": results,
		"note": "本工具只产数据。性能门禁是否通过由独立性能验收决定，不要用本文件宣布 GO。",
	}
	var f: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "  "))
		f.close()
		print("LIS_PERF_WROTE %s" % ProjectSettings.globalize_path(output_path))
	# 同时往 stdout 打一份完整 JSON，便于无头环境直接抓取
	print("LIS_PERF_JSON_BEGIN")
	print(JSON.stringify(payload))
	print("LIS_PERF_JSON_END")
	print("LIS_PERF_DONE scenarios=%d" % results.size())
