extends SceneTree

const QUIET := preload("res://tests/quiet_window.gd")

## 腐墟星实机性能采样（窗口渲染，不用截图回读）。
## 用法：godot --path game --script res://tests/ruin_art_perf.gd
## 输出 P50/P95 帧时间、平均 draw calls / primitives / objects。

var _frames: Array[float] = []
var _draw: Array[int] = []
var _prims: Array[int] = []
var _objects: Array[int] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	QUIET.apply()
	var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28610 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	if player != null:
		player.global_position = Vector3(-2.0, 0.0, 22.0)
		player.rotation.y = 0.1
		player._camera_yaw = 0.1
		player._update_ruin_first_person(0.016)
	# 预热：让着色器/材质/实例都进入缓存。
	for index: int in 90:
		await process_frame
	var warm := 0
	var previous := Time.get_ticks_usec()
	for index: int in 240:
		await process_frame
		var now := Time.get_ticks_usec()
		if warm < 30:
			warm += 1
			previous = now
			continue
		_frames.append(float(now - previous) / 1000.0)
		previous = now
		_draw.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		_objects.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	var p50 := _percentile(_frames, 50.0)
	var p95 := _percentile(_frames, 95.0)
	print("RUIN_ART_PERF frames=%d p50_ms=%.2f p95_ms=%.2f fps_p50=%.1f fps_p95=%.1f" % [
		_frames.size(), p50, p95, 1000.0 / maxf(p50, 0.01), 1000.0 / maxf(p95, 0.01)])
	print("RUIN_ART_PERF draw_calls=avg:%d/max:%d primitives=avg:%d/max:%d objects=avg:%d/max:%d" % [
		_avg_int(_draw), _max_int(_draw), _avg_int(_prims), _max_int(_prims), _avg_int(_objects), _max_int(_objects)])
	quit(0)


func _percentile(values: Array[float], pct: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(round(float(sorted.size() - 1) * pct / 100.0)), 0, sorted.size() - 1)
	return sorted[index]


func _avg_int(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var total := 0
	for value in values:
		total += value
	return total / values.size()


func _max_int(values: Array[int]) -> int:
	var best := 0
	for value in values:
		best = maxi(best, value)
	return best
