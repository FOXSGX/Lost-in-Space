extends SceneTree

## 腐墟星第一人称/卡通改版截图。
## 用法：godot --path game --script res://tests/ruin_first_person_capture.gd -- <输出目录>

var output_dir := "user://ruin-first-person"
var _main: Main3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		output_dir = String(args[0])
	DirAccess.make_dir_recursive_absolute(output_dir)
	var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 27560 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	if player == null:
		quit(1)
		return
	_main = main
	main.set_process(false)
	main._feedback_label.visible = false
	main._ruin_planet.hud.tick(0.016)

	# 01 登陆艇：朝向殖民城。
	_place(player, Vector3(-46.0, 0.0, 30.0), -1.09)
	await _capture("01_landing_pad.png")

	# 02 主街与广场。
	_place(player, Vector3(0.0, 0.0, 24.0), 0.0)
	await _capture("02_avenue_plaza.png")

	# 03 超市正面。
	_place(player, Vector3(-40.0, 0.0, -8.0), 0.0)
	await _capture("03_market.png")

	# 04 医院正面。
	_place(player, Vector3(40.0, 0.0, -12.0), 0.0)
	await _capture("04_hospital.png")

	# 05 学校正面。
	_place(player, Vector3(-62.0, 0.0, 33.0), 0.0)
	await _capture("05_school_street.png")

	# 16 能源站正面。
	_place(player, Vector3(2.0, 0.0, -32.2), 0.0)
	await _capture("16_energy_station.png")

	# 11/12 门锁与二级弹子锁界面。
	_place(player, Vector3(-62.0, 0.0, 27.0), 0.0)
	await _capture("11_door_lock.png")
	main.start_ruin_lockpick(1, "school")
	await _capture("12_lockpick.png")
	main.finish_ruin_lockpick(false)

	# 13/14 超市、医院门锁位置检查。
	_place(player, Vector3(-40.0, 0.0, -13.4), 0.0)
	await _capture("13_market_door_lock.png")
	_place(player, Vector3(36.0, 0.0, -17.4), 0.0)
	await _capture("14_hospital_door_lock.png")

	# 15 暴力撬门：R 的撬棍视角与读条。
	_place(player, Vector3(-40.0, 0.0, -13.4), 0.0)
	main.handle_action(1, "ruin_force_door")
	main._update_hud()
	main._update_ruin_interaction_hint(player, 99.0)
	await _capture("15_force_door.png")
	main._ruin_planet._tick_force_jobs(3.0)
	await process_frame

	# 06 感染者近景。
	main._ruin_planet._spawn_one()
	await process_frame
	var zombie: SpaceEnemy3D = null
	for value in main._ruin_planet.zombies.values():
		zombie = value as SpaceEnemy3D
		break
	if zombie != null:
		zombie.global_position = Vector3(0.0, 0.0, -1.6)
		zombie.rotation.y = PI
		_place(player, Vector3(0.0, 0.0, 1.4), 0.0)
		await _capture("06_infected_closeup.png")

		# 07 近战挥拳的瞬间。
		player.play_ruin_attack()
		await _capture("07_melee_swing.png")

	# 08 腐墟星地图。
	main._toggle_map()
	main._update_hud()
	await _capture("08_map.png")
	main._toggle_map()

	# 09/10 目标完成后的登陆艇与撤离读条。
	for id in ["food_a", "food_b", "food_c"]:
		main._ruin_planet._finish_search(1, String(id))
	for id in ["market", "hospital", "school"]:
		main._ruin_planet.enter_building(1, String(id))
	main._tick_ruin_extraction(0.1)
	_place(player, main._ruin_planet.pad_position() + Vector3(0.0, 0.0, 3.0), 0.0)
	await _capture("09_extraction_ready.png")
	main._tick_ruin_extraction(1.5)
	main._update_hud()
	main._update_interaction_hint()
	await _capture("10_extraction_progress.png")

	print("RUIN_FIRST_PERSON_CAPTURE done: ", output_dir)
	quit(0)


func _place(player: SpacePlayer3D, point: Vector3, yaw: float) -> void:
	player.global_position = point
	player.rotation.y = yaw
	player._camera_yaw = yaw
	player._camera_yaw_target = yaw
	player._camera_pitch = 0.0
	player._camera_pitch_target = 0.0
	player._update_ruin_first_person(0.016)
	if _main != null:
		_main._update_hud()
		_main._update_interaction_hint()
		if _main._ruin_planet != null and _main._ruin_planet.hud != null:
			_main._ruin_planet.hud.tick(0.016)


func _capture(file_name: String) -> void:
	for index: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("截图失败：" + file_name)
		return
	image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	image.save_png(output_dir.path_join(file_name))
