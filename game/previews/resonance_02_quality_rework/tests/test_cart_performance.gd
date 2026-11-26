extends "res://tests/test_cart_interactions.gd"

# Performance measurement for the moving cart slice.
# Samples real rendered frame intervals plus Godot monitors for every phase the
# task requires: idle, acceleration, curve, walking, turning, gripping,
# carrying, multiple cargo sliding, braking, arrival and reset.
var measurements: Dictionary = {}
var active_label: String = ""
var last_tick: int = 0

func begin_sample(label: String) -> void:
	active_label = label
	measurements[label] = []
	last_tick = Time.get_ticks_usec()

func frame_sample() -> void:
	if active_label == "": return
	var now: int = Time.get_ticks_usec()
	(measurements[active_label] as Array).append({
		"frame_ms": float(now - last_tick) / 1000.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"physics_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"active_bodies": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
	})
	last_tick = now

func measure(label: String, seconds: float, orbiting: bool = false) -> void:
	begin_sample(label)
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(seconds * 1000.0):
		if orbiting:
			player.set("_camera_yaw_target", PI * 0.5 + sin(float(Time.get_ticks_msec() - start) * 0.0025) * 1.4)
		await process_frame
	active_label = ""
	print("PERF_SAMPLES ", label, " ", (measurements[label] as Array).size())

func wait_distance(target: float, limit: int = 6000) -> void:
	# The cart settles just under LENGTH, so never wait on an exact value.
	for _i: int in range(limit):
		if float(cart.get("distance")) >= target or bool(cart.get("arrived")): return
		await process_frame

func stats(samples: Array) -> Dictionary:
	if samples.is_empty(): return {}
	var values: Array[float] = []
	for entry: Dictionary in samples:
		values.append(float(entry["frame_ms"]))
	values.sort()
	var total: float = 0.0
	for value: float in values: total += value
	var count: int = values.size()
	return {
		"frames": count,
		"mean_ms": total / float(count),
		"p50_ms": values[int(count * 0.50)],
		"p95_ms": values[mini(int(count * 0.95), count - 1)],
		"p99_ms": values[mini(int(count * 0.99), count - 1)],
		"max_ms": values[count - 1],
		"over_33ms": values.filter(func(v: float) -> bool: return v > 33.3).size(),
		"over_50ms": values.filter(func(v: float) -> bool: return v > 50.0).size(),
		"over_100ms": values.filter(func(v: float) -> bool: return v > 100.0).size(),
	}

func run() -> void:
	await boot()
	# Match the shipping configuration: VSync on, 120 FPS cap.
	Engine.max_fps = 120
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	process_frame.connect(frame_sample)
	await frames(120)
	await travel(Vector3(1, 0, 1.55))
	await frames(60)
	await measure("01_idle_on_deck", 3.0)

	await start_from_console()
	await measure("02_acceleration", 3.0)
	await measure("03_cruise", 3.0)

	await wait_distance(20.0)
	begin_sample("04_walking_on_deck")
	Input.action_press("move_right")
	await frames(120)
	Input.action_release("move_right")
	await frames(30)
	active_label = ""

	await measure("05_fast_turning", 3.0, true)

	await wait_distance(31.0)
	await measure("06_bend_curve", 3.0)

	await travel(Vector3(-0.7, 1.91, 1.44))
	await face(Vector3(-0.7, 2.91, 0.87))
	await press("repair")
	check(int(player.get("grip_id")) == 0, "性能采样中成功抓扶")
	await measure("07_gripping_in_bend", 3.0)
	await press("repair")

	await press("cart_brake")
	await measure("08_braking", 3.0)
	await frames(60)

	var bodies: Array[RigidBody3D] = cargo.get("cargo") as Array[RigidBody3D]
	await pick_body(bodies[0])
	await measure("09_carrying_cargo", 3.0, true)
	await face(Vector3(-0.9, 2.0, 2.8))
	await press("drop")
	await frames(40)

	await start_from_console()
	await wait_distance(52.0)
	# Force both containers loose and let them slide together in the bend.
	for body: RigidBody3D in bodies:
		body.freeze = false
		body.sleeping = false
	await measure("10_multiple_cargo_sliding", 3.0)

	await press("cart_brake")
	await measure("11_emergency_brake", 3.0)
	await frames(120)

	await start_from_console()
	await wait_distance(88.0)
	await frames(240)
	await measure("12_arrival", 3.0)
	await scene.call("reset_run")
	await measure("13_after_reset", 3.0)

	var summary: Dictionary = {}
	for label: String in measurements:
		summary[label] = stats(measurements[label] as Array)
	var report: Dictionary = {
		"cpu": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"engine": Engine.get_version_info(),
		"viewport": [root.size.x, root.size.y],
		"renderer": "gl_compatibility",
		"physics_engine": "Jolt Physics",
		"vsync": true,
		"fps_cap": 120,
		"movie_recording": false,
		"summary": summary,
		"measurements": measurements,
		"note": "Real rendered frame intervals captured while driving the actual cart with automated inputs. CPU monitors are not GPU timings.",
	}
	var file: FileAccess = FileAccess.open(output.path_join("performance-cart.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("PERF_SUMMARY ", JSON.stringify(summary))
	await finish()
