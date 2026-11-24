extends SceneTree

## 腐墟星剧情效果图：庇护所、NPC 对话、核心、菌群泵、最终选择。

var output_dir := "user://ruin-story"
var main: Main3D
var player: SpacePlayer3D
var ruin: RuinPlanet


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
	main.enter_shelter(1)
	await process_frame
	await physics_frame
	main.set_process(false)
	main._feedback_label.visible = false
	if main._settings_visible:
		main._close_settings()

	await _shot("01_shelter_wide.png", Vector3(0.0, 700.15, 4.2), 0.0, -0.03)
	await _shot("02_engineer_workbench.png", Vector3(-4.6, 700.15, 1.2), 0.20, -0.04)
	await _shot("03_doctor_medbay.png", Vector3(4.4, 700.15, 1.2), -0.20, -0.04)

	var engineer: Vector3 = ruin.shelter_npc_positions()["engineer"]
	player.teleport_to(Vector3(engineer.x, 700.15, engineer.z + 2.0))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	player._camera_pitch = -0.04
	player._camera_pitch_target = -0.04
	ruin.open_shelter_dialogue(1, "engineer")
	await _capture("04_engineer_dialogue.png")
	ruin.choose_shelter_dialogue(1, "engineer", 0)
	await process_frame

	main.exit_shelter(1)
	await process_frame
	await physics_frame
	await _shot("05_secret_door.png", Vector3(0.0, 326.15, -8.1), 0.0, -0.03)

	await _shot("06_reactor_core.png", Vector3(7.0, 320.15, 6.7), 0.0, -0.04)
	var pump: Vector3 = ruin.energy_station_interior.call("pump_console_position")
	await _shot("07_pump_console.png", Vector3(pump.x, 323.15, pump.z + 1.6), 0.0, -0.04)

	# 最终选择：把三件套直接置为已取得，回庇护所打开三选项。
	for id in ["energy_access_card", "coolant_stabilizer", "school_observation_data", "market_navigation_module", "reactor_core"]:
		ruin.quest_items[id] = true
	ruin.story_flags["met_engineer"] = true
	ruin.story_flags["met_doctor"] = true
	ruin._refresh_story_stage()
	main.enter_shelter(1)
	await process_frame
	await physics_frame
	main._update_hud()
	player.teleport_to(Vector3(engineer.x, 700.15, engineer.z + 2.0))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	player._camera_pitch = -0.04
	player._camera_pitch_target = -0.04
	ruin.open_shelter_dialogue(1, "engineer")
	await _capture("08_final_choice.png")

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
