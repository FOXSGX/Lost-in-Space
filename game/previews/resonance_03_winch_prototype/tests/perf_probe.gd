extends SceneTree

# Repeatable frame-time probe. Runs windowed by default and records every
# rendered frame per activity. Run the same script with --headless to get the
# logic/physics-only baseline and separate CPU cost from GPU cost.
#
# It teleports between stations on purpose: this measures rendering and physics,
# not walking routes. Gameplay correctness is covered by probe_rig.gd.
#
# Usage:
#   godot --path <project> --script res://tests/perf_probe.gd -- <outdir> [label]

var app: Node3D
var player: CharacterBody3D
var rig: Node3D
var machine: Node3D
var output: String = "user://perf"
var label: String = "windowed"
var current_phase: String = "boot"
var frames: Array[Dictionary] = []
var _last_usec: int = 0
var _start_usec: int = 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		output = args[0]
	if args.size() > 1:
		label = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	var cold: bool = label.contains("cold")
	var boot_usec: int = Time.get_ticks_usec()
	app = (load("resonance_03.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	player = app.get("player") as CharacterBody3D
	rig = app.get("rig") as Node3D
	machine = app.get("machine") as Node3D
	player.set("paused", true)

	if cold:
		# Record the very first frames, including the scene's first draws. This is
		# the run that reproduces the "10 fps" first screenshot.
		_start_usec = boot_usec
		_last_usec = boot_usec
		current_phase = "cold_first_frames"
		for _i: int in range(150):
			await process_frame
			record()
	else:
		await wait_frames(10)
		await warmup_views()
		_start_usec = Time.get_ticks_usec()
		_last_usec = _start_usec

	await phase("startup", 1.6)
	await phase("idle", 2.0)
	await phase_walk("walk", 3.0)
	await phase("hook_setup", 0.2)
	await place_close("eye_far")
	rig.call("attach_cable", "eye_far")
	await phase("tension_slack", 1.0)

	await place_console()
	app.set("at_console", true)
	await phase_haul("haul_jam_break", 2.2)
	await phase_haul("rail_moving", 3.0)
	Input.action_release("winch_haul")
	await phase("overload_release", 1.0)

	await mid_eye_slip("clutch_slip", 3.2)
	await phase("reset_between", 0.8)

	await align_and_lock("align", 6.0)
	await phase("lock_idle", 1.2)
	Input.action_release("winch_haul")
	await phase("second_reset", 1.0)

	_save()
	current_scene = null
	app.queue_free()
	await wait_frames(3)
	quit(0)

func wait_frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame

# Render the four key sightlines once before measuring. On a machine where the
# shader cache cannot be written (or on the very first launch), the compatibility
# renderer compiles pipelines on first view and produces one long frame. The
# warm-up moves that known cost into the loading phase, and the measured run
# shows whether any stutter remains.
func warmup_views() -> void:
	var views: Array = [
		[Vector3(0.6, 0.3, 5.2), 0.0],
		[Vector3(4.6, 0.3, 1.4), -0.5],
		[Vector3(-1.2, 0.3, 4.7), -0.7],
		[Vector3(6.2, 0.3, 2.6), -0.5],
	]
	for view: Array in views:
		player.call("teleport_to", view[0] as Vector3, float(view[1]))
		player.set("_camera_pitch", -0.25)
		player.set("_camera_pitch_target", -0.25)
		player.call("update_camera", 1.0, true)
		await wait_frames(24)
	player.call("teleport_to", Vector3(0.6, 0.3, 5.2), -0.18)
	player.call("update_camera", 1.0, true)
	await wait_frames(12)

func record() -> void:
	var now: int = Time.get_ticks_usec()
	var ms: float = float(now - _last_usec) / 1000.0
	_last_usec = now
	frames.append({
		"phase": current_phase,
		"t": float(now - _start_usec) / 1_000_000.0,
		"ms": ms,
		"process": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
	})

func phase(name: String, seconds: float) -> void:
	current_phase = name
	_last_usec = Time.get_ticks_usec()
	var start: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start) / 1_000_000.0 < seconds:
		await process_frame
		record()

func phase_walk(name: String, seconds: float) -> void:
	current_phase = name
	_last_usec = Time.get_ticks_usec()
	player.set("paused", false)
	Input.action_press("move_up", 0.8)
	var start: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start) / 1_000_000.0 < seconds:
		await process_frame
		record()
	Input.action_release("move_up")
	player.set("paused", true)
	await wait_frames(2)

func phase_haul(name: String, seconds: float) -> void:
	current_phase = name
	_last_usec = Time.get_ticks_usec()
	Input.action_press("winch_haul")
	var start: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start) / 1_000_000.0 < seconds:
		await process_frame
		record()
	Input.action_release("winch_haul")
	await wait_frames(2)

func mid_eye_slip(name: String, seconds: float) -> void:
	Input.action_release("winch_haul")
	rig.call("reset_mission")
	app.set("at_console", false)
	player.call("set_operating", null)
	await wait_frames(4)
	await place_close("eye_mid")
	rig.call("attach_cable", "eye_mid")
	await place_console()
	app.set("at_console", true)
	await phase_haul(name, seconds)
	await wait_frames(2)

func align_and_lock(name: String, seconds: float) -> void:
	Input.action_release("winch_haul")
	rig.call("reset_mission")
	app.set("at_console", false)
	player.call("set_operating", null)
	await wait_frames(4)
	await place_close("eye_far")
	rig.call("attach_cable", "eye_far")
	await place_console()
	app.set("at_console", true)
	current_phase = name
	_last_usec = Time.get_ticks_usec()
	Input.action_press("winch_haul")
	var start: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start) / 1_000_000.0 < seconds:
		await process_frame
		record()
		var info: Dictionary = rig.call("alignment_state") as Dictionary
		if float(info.get("angle_deg", 15.0)) <= 1.4:
			break
	Input.action_release("winch_haul")
	await wait_frames(90)
	current_phase = "align_settle"
	_last_usec = Time.get_ticks_usec()
	# Wait for the rail to settle, still recording.
	for _i: int in range(120):
		await process_frame
		record()
		var settled_info: Dictionary = rig.call("alignment_state") as Dictionary
		if bool(settled_info.get("lockable", false)):
			break
	var socket: Vector3 = (app.get("lock_station") as Node3D).global_position
	player.call("teleport_to", socket + Vector3(-0.7, 0.3, 0.2), 0.0)
	app.set("at_console", false)
	player.call("set_operating", null)
	await wait_frames(10)
	current_phase = "lock_pin"
	rig.call("try_install_lock")
	await phase("locked_hold", 1.2)

func place_close(anchor_id: String) -> void:
	var anchor: Node3D = rig.call("find_anchor", anchor_id) as Node3D
	var at: Vector3 = anchor.call("attach_point") as Vector3
	player.call("teleport_to", at + Vector3(0.0, 0.0, 1.2), 0.0)
	await wait_frames(4)

func place_console() -> void:
	var console: Vector3 = (app.get("winch_station") as Node3D).global_position
	player.call("teleport_to", console + Vector3(0.0, 0.3, 1.7), 0.0)
	await wait_frames(4)

func _save() -> void:
	var by_phase: Dictionary = {}
	for entry: Dictionary in frames:
		var phase_name: String = str(entry["phase"])
		if not by_phase.has(phase_name):
			by_phase[phase_name] = []
		(by_phase[phase_name] as Array).append(float(entry["ms"]))
	var summary: Dictionary = {}
	for phase_name: String in by_phase.keys():
		var values: Array = by_phase[phase_name]
		values.sort()
		summary[phase_name] = {
			"count": values.size(),
			"p50": _pct(values, 0.50),
			"p95": _pct(values, 0.95),
			"p99": _pct(values, 0.99),
			"max": float(values[values.size() - 1]),
			"over_16_7": _over(values, 16.7),
			"over_33": _over(values, 33.0),
			"over_50": _over(values, 50.0),
			"over_100": _over(values, 100.0),
		}
	var data: Dictionary = {
		"label": label,
		"godot": Engine.get_version_info().get("string", ""),
		"renderer": RenderingServer.get_video_adapter_name(),
		"headless": DisplayServer.get_name() == "headless",
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"total_frames": frames.size(),
		"duration_s": float(Time.get_ticks_usec() - _start_usec) / 1_000_000.0,
		"summary": summary,
		"frames": frames,
	}
	var file: FileAccess = FileAccess.open(output.path_join("perf_%s.json" % label), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()
	var csv: FileAccess = FileAccess.open(output.path_join("perf_%s.csv" % label), FileAccess.WRITE)
	if csv != null:
		csv.store_line("phase,ms,process_ms,physics_ms,draw_calls,objects")
		for entry: Dictionary in frames:
			csv.store_line("%s,%.3f,%.3f,%.3f,%d,%d" % [
				str(entry["phase"]), float(entry["ms"]), float(entry["process"]),
				float(entry["physics"]), int(entry["draw_calls"]), int(entry["objects"]),
			])
		csv.close()
	print("PERF_RESULT ", JSON.stringify({"label": label, "frames": frames.size(), "summary": summary}))

func _pct(values: Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var index: int = clampi(int(floor(p * float(values.size() - 1))), 0, values.size() - 1)
	return float(values[index])

func _over(values: Array, threshold: float) -> int:
	var count: int = 0
	for value: float in values:
		if value > threshold:
			count += 1
	return count
