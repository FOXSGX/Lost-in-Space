extends SceneTree

## 霜烬星美术层的统计与性能采样（同一相机、同一会话，FROST_ART=0 为改造前基线）。
##
##   Godot_v4.7.2-stable_win64_console.exe --path game --script previews/frost_station/art_bench.gd
##
## 输出一行 FROST_ART_BENCH {json}，字段：art、fps_p50/p95、draw_calls、primitives、
## objects、materials、detail_meshes、lights。只读，不改玩法状态。

var world_root: Node3D

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i: int in n:
		await process_frame

func run() -> void:
	world_root = load("res://previews/frost_station/adventure.tscn").instantiate()
	root.add_child(world_root)
	world_root.start_session(false)
	world_root.test_mode = true
	await frames(20)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 52.0
	camera.far = 1400.0
	camera.position = Vector3(26, 14, -18)
	camera.look_at(Vector3(-6, 4, -96), Vector3.UP)
	root.add_child(camera)
	camera.make_current()
	for layer: Node in world_root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await frames(60)
	var samples: Array[float] = []
	var draw_calls: float = 0.0
	var primitives: float = 0.0
	var previous: int = Time.get_ticks_usec()
	for i: int in 120:
		await process_frame
		var now: int = Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
		draw_calls = maxf(draw_calls, float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives = maxf(primitives, float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	samples.sort()
	var p50: float = samples[int(float(samples.size()) * 0.50)]
	var p95: float = samples[int(float(samples.size()) * 0.95)]
	var art: Node3D = world_root.world.get("frost_art") as Node3D
	var families: Dictionary = {}
	var detail_meshes: int = 0
	var lights: int = 0
	var materials: int = 0
	if art != null:
		var data: Dictionary = art.call("stats") as Dictionary
		families = data.get("families", {})
		detail_meshes = int(data.get("detail_meshes", 0))
		lights = int(data.get("lights", 0))
		materials = int(data.get("materials", 0))
	var report: Dictionary = {
		"art": art != null,
		"frame_ms_p50": p50,
		"frame_ms_p95": p95,
		"draw_calls": int(draw_calls),
		"primitives": int(primitives),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"materials": materials,
		"detail_meshes": detail_meshes,
		"lights": lights,
		"families": families,
	}
	print("FROST_ART_BENCH ", JSON.stringify(report))
	quit()
