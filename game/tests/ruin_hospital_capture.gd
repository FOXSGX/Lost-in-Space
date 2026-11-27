extends SceneTree

const QUIET := preload("res://tests/quiet_window.gd")

## 医院室内效果图：B1 太平间 / 1F 大厅 / 2F 病房 / 3F 手术 / 楼梯间。

var output_dir := "user://ruin-hospital-interior"
var main: Main3D
var player: SpacePlayer3D
var interior: Node3D


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
	main.network_port = 27890 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	interior = main._ruin_planet.hospital_interior
	player = main.players.get(1) as SpacePlayer3D
	main._ruin_planet.unlock_building(1, "hospital")
	await process_frame
	await physics_frame
	main.set_process(false)
	main._feedback_label.visible = false

	await _shot("01_lobby.png", 1, Vector3(0.0, 0.0, 7.0), 0.0, -0.04)
	main._ruin_planet.story_flags["quest_intel"] = true
	main._update_hud()
	await _shot("01f_task_unlocked.png", 1, Vector3(0.0, 0.0, 7.0), 0.0, -0.04)
	await _shot("01c_hospital_directory.png", 1, Vector3(0.0, 0.0, 7.0), -0.55, -0.04)
	await _shot("01d_entry_left_stair_sign.png", 1, Vector3(0.0, 0.0, 6.9), PI * 0.5, -0.02)
	await _shot("01e_stair_sign_close.png", 1, Vector3(-7.5, 0.0, 6.9), PI * 0.5, -0.02)
	await _shot("01b_lobby_up.png", 1, Vector3(0.0, 0.0, 7.0), 0.0, 1.05)
	await _shot("02_pharmacy.png", 1, Vector3(2.0, 0.0, -4.5), 0.0, -0.04)
	await _shot("03_outpatient_2f.png", 2, Vector3(4.0, 0.0, 0.2), PI, -0.04)
	await _shot("04_exam_2f.png", 2, Vector3(-4.5, 0.0, -1.9), 0.0, -0.04)
	await _shot("05_morgue_b1.png", 0, Vector3(-3.0, 0.0, 3.8), PI, -0.06)
	await _shot("06_ward_3f_locked.png", 3, Vector3(-6.2, 0.0, 0.0), -PI * 0.5, -0.04)
	await _shot("07_locked_ward_door.png", 3, Vector3(4.0, 0.0, 0.2), PI, -0.02)
	await _shot("09_ward_door_unlocked.png", 3, Vector3(-4.0, 0.0, 0.2), PI, -0.02)
	# 病房门 1.5–2 m 近景：审门窗框、凹板、推杆、编号牌与磨损（开门前拍）。
	await _shot("16_ward_door_locked_closeup.png", 3, Vector3(4.0, 0.0, -0.4), PI, -0.02)
	await _shot("17_ward_door_unlocked_closeup.png", 3, Vector3(-4.0, 0.0, -0.4), PI, -0.02)
	main.open_hospital_ward_door(1)
	await create_timer(0.6).timeout
	await _shot("10_ward_door_opened.png", 3, Vector3(-4.0, 0.0, 0.2), PI, -0.04)
	await _shot("11_basement_pharmacy.png", 0, Vector3(2.0, 0.0, -3.4), 0.0, -0.05)
	await _shot("15_archive_b1.png", 0, Vector3(-2.6, 0.0, -3.2), 0.0, -0.05)
	await _shot("12_security_card.png", 1, Vector3(8.0, 0.0, 6.0), 0.0, -0.04)
	await _shot("13_sedation_records.png", 2, Vector3(9.8, 0.0, 4.4), 0.0, -0.04)
	await _shot("14_sedation_room.png", 2, Vector3(8.0, 0.0, 7.9), 0.0, -0.06)
	await _shot("08_stairwell.png", 1, Vector3(-8.8, 0.0, 4.4), 0.0, 0.10)
	await _shot("08a_stair_door_open.png", 1, Vector3(-5.4, 0.0, -6.0), PI * 0.5, -0.02)
	await _shot("08b_stair_up.png", 1, Vector3(-10.0, 0.0, -5.6), PI, 0.04)
	await _shot("08c_stair_landing_2f.png", 2, Vector3(-10.0, 0.0, 5.6), 0.0, 0.04)
	await _shot("08d_b1_stair_bottom.png", 0, Vector3(-9.5, 0.0, 4.4), 0.0, 0.12)

	print("RUIN_HOSPITAL_CAPTURE done: ", output_dir)
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
