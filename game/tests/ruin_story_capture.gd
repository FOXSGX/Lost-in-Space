extends SceneTree

const QUIET := preload("res://tests/quiet_window.gd")

## 腐墟星剧情效果图：庇护所、NPC 对话、核心、菌群泵、最终选择。

var output_dir := "user://ruin-story"
var main: Main3D
var player: SpacePlayer3D
var ruin: RuinPlanet


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	QUIET.apply()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output_dir = String(args[0])
	DirAccess.make_dir_recursive_absolute(output_dir)
	main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28290 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	ruin = main._ruin_planet
	player = main.players.get(1) as SpacePlayer3D
	ruin.unlock_building(1, "energy_station")
	await process_frame
	await physics_frame
	main.set_process(false)
	main._feedback_label.visible = false
	if main._settings_visible:
		main._close_settings()

	var secret: Vector3 = ruin.energy_station_interior.call("secret_door_position")
	await _shot("01_shelter_intercom.png", Vector3(secret.x, secret.y - 0.85, secret.z + 1.2), 0.0, -0.03)
	await _shot("05_secret_door.png", Vector3(0.0, 326.15, -8.1), 0.0, -0.03)

	player.teleport_to(Vector3(secret.x, secret.y - 0.85, secret.z + 0.8))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	player._camera_pitch = -0.04
	player._camera_pitch_target = -0.04
	ruin.open_shelter_dialogue(1, "")
	await _capture("04_engineer_dialogue.png")
	ruin.choose_shelter_dialogue(1, "engineer", 0)
	await process_frame

	await _shot("06_reactor_core.png", Vector3(7.0, 320.15, 6.7), 0.0, -0.04)
	var pump: Vector3 = ruin.energy_station_interior.call("pump_console_position")
	await _shot("07_pump_console.png", Vector3(pump.x, 323.15, pump.z + 1.6), 0.0, -0.04)

	# 最终选择：把三件套直接置为已取得，回庇护所打开三选项。
	for id in ["energy_access_card", "coolant_stabilizer", "market_navigation_module", "reactor_core"]:
		ruin.quest_items[id] = true
	ruin.story_flags["met_engineer"] = true
	ruin.story_flags["met_doctor"] = true
	ruin._refresh_story_stage()
	await process_frame
	await physics_frame
	main._update_hud()
	player.teleport_to(Vector3(secret.x, secret.y - 0.85, secret.z + 0.8))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	player._camera_pitch = -0.04
	player._camera_pitch_target = -0.04
	ruin.open_shelter_dialogue(1, "")
	await _capture("08_final_choice.png")

	# 医生方案：重启后不立刻结算，HUD 指向登陆艇；回艇按 E 才进入真结局。
	ruin.choose_shelter_dialogue(1, "engineer", 1)
	ruin.story_flags["pump_shutdown"] = true
	var reactor: Vector3 = ruin.energy_station_interior.call("reactor_console_position")
	player.teleport_to(Vector3(reactor.x, 320.15, reactor.z + 1.6))
	ruin._restart_reactor_after_pump(1)
	main._update_hud()
	await _capture("09_reactor_restarted.png")
	var pad: Vector3 = ruin.pad_position()
	player.teleport_to(pad + Vector3(0.0, 0.02, 2.5))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	ruin.handle_action(1, "repair")
	main._update_hud()
	await _capture("10_true_ending.png")

	print("RUIN_STORY_CAPTURE done: ", output_dir)
	quit(0)


func _shot(file_name: String, at: Vector3, yaw: float, pitch: float) -> void:
	player.teleport_to(at)
	player.rotation.y = yaw
	player._camera_yaw = yaw
	player._camera_yaw_target = yaw
	player._camera_pitch = pitch
	player._camera_pitch_target = pitch
	player._update_ruin_first_person(0.016)
	ruin._apply_camera_environment()
	main._update_hud()
	main._update_ruin_interaction_hint(player, 0.016)
	await _capture(file_name)


func _capture(file_name: String) -> void:
	for index: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image != null:
		image.save_png(output_dir.path_join(file_name))
