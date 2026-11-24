extends SceneTree

## 能源站内部效果图：1F 大厅/控制/汽轮机、B1 泵房/冷却、B2 反应堆/星髓、2F 通风。

var output_dir := "user://ruin-energy-station"
var main: Main3D
var player: SpacePlayer3D
var interior: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output_dir = String(args[0])
	DirAccess.make_dir_recursive_absolute(output_dir)
	main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28030 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	interior = main._ruin_planet.energy_station_interior
	player = main.players.get(1) as SpacePlayer3D
	main._ruin_planet.unlock_building(1, "energy_station")
	await process_frame
	await physics_frame
	main.set_process(false)
	main._feedback_label.visible = false
	if main._settings_visible:
		main._close_settings()

	await _shot("01_entry_1f.png", 2, Vector3(0.0, 0.0, 7.4), 0.0, -0.04)
	await _shot("02_control_1f.png", 2, Vector3(8.8, 0.0, 4.8), PI, -0.04)
	await _shot("03_turbine_1f.png", 2, Vector3(5.0, 0.0, -1.5), -0.75, -0.04)
	await _shot("04_pump_b1.png", 1, Vector3(6.5, 0.0, -1.8), 0.0, -0.04)
	await _shot("05_coolant_b1.png", 1, Vector3(7.8, 0.0, 2.0), PI, -0.04)
	await _shot("06_reactor_b2.png", 0, Vector3(0.0, 0.0, 8.4), 0.0, 0.02)
	await _shot("07_distribution_1f.png", 2, Vector3(0.0, 0.0, -6.5), 0.0, -0.02)
	await _shot("08_vent_2f.png", 3, Vector3(6.5, 0.0, 1.8), -2.25, -0.03)
	await _shot("09_observation_2f.png", 3, Vector3(0.0, 0.0, -6.0), PI, 0.04)
	await _shot("10_art_crystal.png", 0, Vector3(-6.0, 0.0, 5.5), 0.20, -0.03)
	await _shot("11_art_console.png", 2, Vector3(8.0, 0.0, 3.4), PI, -0.06)
	await _shot("12_physics_door.png", 2, Vector3(9.1, 0.0, 2.1), 0.0, -0.03)
	await _shot("13_art_press.png", 1, Vector3(7.0, 0.0, -3.0), -0.90, -0.04)

	print("RUIN_ENERGY_CAPTURE done: ", output_dir)
	quit(0)


func _shot(file_name: String, level: int, offset: Vector3, yaw: float, pitch: float) -> void:
	var level_point: Vector3 = interior.call("level_position", level)
	player.teleport_to(level_point + Vector3(offset.x, 0.15, offset.z))
	player.rotation.y = yaw
	player._camera_yaw = yaw
	player._camera_yaw_target = yaw
	player._camera_pitch = pitch
	player._camera_pitch_target = pitch
	player._update_ruin_first_person(0.016)
	main._update_hud()
	main._update_ruin_interaction_hint(player, 0.016)
	await _capture(file_name)


func _capture(file_name: String) -> void:
	for index: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image != null:
		image.save_png(output_dir.path_join(file_name))
