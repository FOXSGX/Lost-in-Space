extends SceneTree

## Performance probe. Run windowed, 1280x720, no fixed fps:
##   godot --path <project> --resolution 1280x720 --disable-vsync \
##         --script res://tests/test_perf.gd -- <out dir>

var app: Node3D


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await process_frame


func percentile(values: Array[float], p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var idx: int = clampi(int(round((p / 100.0) * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return sorted[idx]


func sample(count: int) -> Dictionary:
	var deltas: Array[float] = []
	var last: int = Time.get_ticks_usec()
	for _i in range(count):
		await process_frame
		var now: int = Time.get_ticks_usec()
		deltas.append(float(now - last) / 1000.0)
		last = now
	var sum: float = 0.0
	var over33: int = 0
	var over50: int = 0
	var max_ms: float = 0.0
	for d in deltas:
		sum += d
		if d > 33.3:
			over33 += 1
		if d > 50.0:
			over50 += 1
		max_ms = maxf(max_ms, d)
	return {
		"frames": deltas.size(),
		"avg_ms": sum / maxf(1.0, float(deltas.size())),
		"p50": percentile(deltas, 50.0),
		"p95": percentile(deltas, 95.0),
		"p99": percentile(deltas, 99.0),
		"max_ms": max_ms,
		"over_33ms": over33,
		"over_50ms": over50,
	}


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://tests-out"
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	var level: LevelBuilder = null
	for _i in range(30):
		await process_frame
	level = app.get("level") as LevelBuilder
	var hud: GameHud = app.get("hud") as GameHud
	hud.title_layer.visible = false
	hud.clear_subtitles()
	# warm up shaders / scene
	await frames(180)
	var idle: Dictionary = await sample(900)
	var core: CoreRig = level.core
	core.play_surge(1.6)
	var surge: Dictionary = await sample(420)
	var gpu: String = RenderingServer.get_video_adapter_name()
	var window_size: Vector2i = DisplayServer.window_get_size()
	var report: Dictionary = {
		"gpu": gpu,
		"renderer": RenderingServer.get_current_rendering_method(),
		"window_size": [window_size.x, window_size.y],
		"vsync": DisplayServer.window_get_vsync_mode(),
		"physics_ticks": Engine.physics_ticks_per_second,
		"idle": idle,
		"surge": surge,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"physics_objects_2d": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		"physics_objects_3d": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"level_stats": level.kit.stats,
		"light_count": level.kit.stats["lights"],
	}
	var f: FileAccess = FileAccess.open(out_dir + "/perf_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("PERF ", JSON.stringify(report))
	quit(0)
