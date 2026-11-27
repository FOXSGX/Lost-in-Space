extends SceneTree

const QUIET := preload("res://tests/quiet_window.gd")

## 腐墟星美术证据截图（指南方法四）。
## 用法：godot --path game --script res://tests/ruin_art_capture.gd -- <输出目录>
##
## 输出：
##   A_wide / B_player_eye / C_interaction_* / D_threequarter
##   4 张 1–2 m 材质特写、锁定/激活对比、撤离状态序列、D_key_only
##   同机位旧版对比（FOV 76，沿用首版截图相机位）
##   perf.log（draw calls / primitives / fps）

var main: Main3D
var player: SpacePlayer3D
var ruin: RuinPlanet
var out_dir := "user://ruin-art"
var free_cam: Camera3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	QUIET.apply()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = String(args[0])
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28510 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	player = main.players.get(1) as SpacePlayer3D
	ruin = main._ruin_planet
	if player == null or ruin == null:
		push_error("capture: 玩家或腐墟星世界没有建立")
		quit(1)
		return
	main.set_process(false)
	main._feedback_label.visible = false
	ruin.hud.visible = false
	ruin._apply_camera_environment()

	# ── A 远景：临时自由机位，审构图与 70/15/10/8 比例 ──
	free_cam = Camera3D.new()
	free_cam.name = "ArtCaptureCamera"
	main.add_child(free_cam)
	free_cam.fov = 50.0
	free_cam.global_position = Vector3(0.0, 16.0, 44.0)
	free_cam.look_at(Vector3(0.0, 3.5, 0.0), Vector3.UP)
	free_cam.current = true
	await _shot("A_wide.png")
	free_cam.queue_free()
	free_cam = null
	player._camera.current = true
	ruin.hud.visible = true

	main._update_hud()
	main._update_ruin_interaction_hint(player, 99.0)

	# ── B 玩家眼高 ──
	_place(Vector3(-2.0, 0.0, 22.0), 0.10, 65.0)
	await _shot("B_player_eye.png")

	# ── C 核心交互近景 ──
	_place(Vector3(-62.0, 0.0, 26.6), 0.0, 44.0)
	await _shot("C_interaction_doorlock.png")
	_place(Vector3(-12.0, 0.0, -10.6), 0.0, 44.0)
	await _shot("C_interaction_crate.png")
	_place(Vector3(2.0, 0.0, -32.8), 0.0, 44.0)
	await _shot("C_interaction_energy.png")
	_place(Vector3(36.0, 0.0, -15.6), 0.0, 55.0)
	await _shot("C_interaction_hospital_portal.png")

	# ── D 建筑/地面交界 ──
	_place(Vector3(26.0, 0.0, -10.0), 2.45, 52.0)
	await _shot("D_threequarter.png")

	# ── 1–2 m 材质特写 ──
	_place(Vector3(-56.5, 0.0, 25.2), 0.0, 40.0)
	await _shot("E_closeup_facade_seam.png")
	_place(Vector3(-61.0, 0.0, 26.3), 0.0, 36.0)
	await _shot("E_closeup_lock.png")
	_place(Vector3(-48.6, 0.0, 34.2), 0.0, 40.0)
	await _shot("E_closeup_pad_console.png")
	_place(Vector3(12.0, 0.0, 11.6), 0.0, 40.0)
	await _shot("E_closeup_fungus.png")

	# ── 锁定 / 激活对比 + 12 帧撤离序列 ──
	ruin.set_extraction_active(false)
	await _shot("F_extraction_locked.png")
	for index: int in 6:
		await _shot("G_sequence_%02d_locked.png" % index)
	ruin.set_extraction_active(true)
	for index: int in 6:
		await _shot("G_sequence_%02d_active.png" % index)
	await _shot("F_extraction_active.png")

	# ── 只留主光：验证不是靠环境光掩盖结构 ──
	var env := ruin.get("_environment") as Environment
	if env != null:
		var saved := env.ambient_light_energy
		env.ambient_light_energy = 0.0
		_place(Vector3(-2.0, 0.0, 22.0), 0.10, 65.0)
		await _shot("D_key_only.png")
		env.ambient_light_energy = saved

	# ── 同机位旧版对比（首版截图机位与 FOV 76）──
	ruin.hud.visible = true
	ruin.set_extraction_active(false)
	_place(Vector3(0.0, 0.0, 24.0), 0.0, 76.0)
	await _shot("H_before_after_avenue.png")
	_place(Vector3(-40.0, 0.0, -8.0), 0.0, 76.0)
	await _shot("H_before_after_market.png")
	_place(Vector3(40.0, 0.0, -12.0), 0.0, 76.0)
	await _shot("H_before_after_hospital.png")
	_place(Vector3(2.0, 0.0, -32.2), 0.0, 76.0)
	await _shot("H_before_after_energy.png")

	_write_perf()
	print("RUIN_ART_CAPTURE done: ", out_dir)
	quit(0)


func _place(point: Vector3, yaw: float, fov: float) -> void:
	player.global_position = point
	player.rotation.y = yaw
	player._camera_yaw = yaw
	player._camera_yaw_target = yaw
	player._camera_pitch = 0.0
	player._camera_pitch_target = 0.0
	player._camera.fov = fov
	player._update_ruin_first_person(0.016)
	main._update_hud()
	main._update_ruin_interaction_hint(player, 99.0)
	ruin._apply_camera_environment()


func _shot(file_name: String) -> void:
	for index: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("截图失败：" + file_name)
		return
	image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	image.save_png(out_dir.path_join(file_name))


func _write_perf() -> void:
	var lines := PackedStringArray()
	lines.append("time=%s" % Time.get_datetime_string_from_system())
	lines.append("draw_calls=%d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	lines.append("primitives=%d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	lines.append("objects=%d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	lines.append("fps=%.1f" % float(Performance.get_monitor(Performance.TIME_FPS)))
	var file := FileAccess.open(out_dir.path_join("perf.log"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines))
		file.close()
