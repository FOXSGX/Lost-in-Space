extends SceneTree
## Windowed performance probe. Run WITHOUT --headless and without --fixed-fps:
##   godot --path . --script res://tests/benchmark.gd
## Measures wall-clock frame intervals with V-Sync disabled and samples the
## renderer's draw-call / primitive / memory counters during representative play.

var game: Node
var samples: Array[float] = []
var draw_calls: Array[float] = []
var primitives: Array[float] = []
var node_counts: Array[float] = []
var video_mem: Array[float] = []
var phases: Array[Dictionary] = []


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run()


func _run() -> void:
	await create_timer(2.0).timeout
	await _warmup(90)
	await _phase("spawn_static", 360)
	game.player.teleport(Vector3(4.0, 0.2, 2.0), -30.0)
	game.player.aim_camera_at(Vector3(14.0, 2.0, -10.0), -0.12)
	Input.action_press("move_forward")
	await _phase("walk_center", 480)
	Input.action_release("move_forward")
	game.player.teleport(Vector3(2.25, 0.2, -0.4), 0.0)
	game.player.aim_camera_at(Vector3(16.5, 2.6, -11.5), -0.10)
	await create_timer(0.4).timeout
	await _strike()
	await _phase("memory_one_and_wave", 720)
	var report: Dictionary = _report()
	var file: FileAccess = FileAccess.open("res://evidence/tests/performance.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("PERF_RESULT " + JSON.stringify(report))
	quit()


func _warmup(frames: int) -> void:
	for index: int in range(frames):
		await process_frame


func _phase(label: String, frames: int) -> void:
	var last: int = Time.get_ticks_usec()
	var draw_start: int = samples.size()
	var phase_draw: Array[float] = []
	var phase_prim: Array[float] = []
	var phase_nodes: Array[float] = []
	var phase_mem: Array[float] = []
	for index: int in range(frames):
		await process_frame
		var now: int = Time.get_ticks_usec()
		var ms: float = float(now - last) / 1000.0
		last = now
		samples.append(ms)
		phase_draw.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		phase_prim.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		phase_nodes.append(float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		phase_mem.append(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	var phase_samples: Array = samples.slice(draw_start, samples.size())
	var sorted_values: Array = phase_samples.duplicate()
	sorted_values.sort()
	phases.append({
		"label": label,
		"frames": frames,
		"p50_ms": _percentile(sorted_values, 0.50),
		"p95_ms": _percentile(sorted_values, 0.95),
		"p99_ms": _percentile(sorted_values, 0.99),
		"avg_draw_calls": _average(phase_draw),
		"max_draw_calls": _max(phase_draw),
		"avg_primitives": _average(phase_prim),
		"max_primitives": _max(phase_prim),
		"avg_nodes": _average(phase_nodes),
		"max_video_mem_mb": _max(phase_mem) / (1024.0 * 1024.0),
	})
	draw_calls.append_array(phase_draw)
	primitives.append_array(phase_prim)
	node_counts.append_array(phase_nodes)
	video_mem.append_array(phase_mem)
	print("PHASE ", label, " frames=", frames, " p50=", phases[-1]["p50_ms"], " p95=", phases[-1]["p95_ms"], " p99=", phases[-1]["p99_ms"], " draw=", phases[-1]["avg_draw_calls"])


func _strike() -> void:
	game.player.aim_camera_at(Vector3(2.25, 1.3, -1.95), -0.08)
	await create_timer(0.5).timeout
	Input.action_press("interact")
	await create_timer(0.15).timeout
	Input.action_release("interact")
	Input.action_press("move_forward")
	await create_timer(1.65).timeout
	Input.action_release("move_forward")
	await create_timer(0.15).timeout
	Input.action_press("interact")
	await create_timer(0.15).timeout
	Input.action_release("interact")
	await create_timer(2.0).timeout
	game.player.aim_camera_at(Vector3(16.5, 2.6, -11.5), -0.10)


func _report() -> Dictionary:
	var sorted_all: Array = samples.duplicate()
	sorted_all.sort()
	return {
		"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"window": "%dx%d" % [root.size.x, root.size.y],
		"total_frames": samples.size(),
		"p50_ms": _percentile(sorted_all, 0.50),
		"p95_ms": _percentile(sorted_all, 0.95),
		"p99_ms": _percentile(sorted_all, 0.99),
		"avg_fps": 1000.0 / maxf(_average(samples), 0.001),
		"avg_draw_calls": _average(draw_calls),
		"max_draw_calls": _max(draw_calls),
		"avg_primitives": _average(primitives),
		"max_primitives": _max(primitives),
		"max_video_mem_mb": _max(video_mem) / (1024.0 * 1024.0),
		"max_nodes": _max(node_counts),
		"phases": phases,
	}


func _percentile(sorted_values: Array, fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index: int = clampi(int(round(float(sorted_values.size() - 1) * fraction)), 0, sorted_values.size() - 1)
	return float(sorted_values[index])


func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: Variant in values:
		total += float(value)
	return total / float(values.size())


func _max(values: Array) -> float:
	var result: float = 0.0
	for value: Variant in values:
		result = maxf(result, float(value))
	return result
