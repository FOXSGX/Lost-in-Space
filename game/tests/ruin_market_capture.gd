extends SceneTree

const QUIET := preload("res://tests/quiet_window.gd")

## 超市室内效果图：卖场、货架、收银、路障、仓库、办公室、装卸口。

var output_dir := "user://ruin-market-interior"
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
	main.network_port = 28140 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	interior = main._ruin_planet.market_interior
	player = main.players.get(1) as SpacePlayer3D
	main._ruin_planet.unlock_building(1, "market")
	await process_frame
	await physics_frame
	main.set_process(false)
	main._feedback_label.visible = false
	if main._settings_visible:
		main._close_settings()

	await _shot("01_entry_1f.png", 0, Vector3(0.0, 0.0, 6.8), 0.0, -0.04)
	await _shot("02_sales_floor_1f.png", 0, Vector3(-2.0, 0.0, 2.4), 0.0, -0.04)
	await _shot("03_shelves_1f.png", 0, Vector3(5.0, 0.0, -2.0), PI, -0.04)
	await _shot("04_checkout_1f.png", 0, Vector3(-3.5, 0.0, 4.2), PI, -0.04)
	await _shot("05_barricade_1f.png", 0, Vector3(-5.5, 0.0, 5.6), PI, -0.04)
	await _shot("06_warehouse_2f.png", 1, Vector3(2.0, 0.0, 0.2), 0.0, -0.04)
	await _shot("07_loading_2f.png", 1, Vector3(8.0, 0.0, 5.6), PI, -0.04)
	await _shot("08_office_task_2f.png", 1, Vector3(10.0, 0.0, 7.2), 0.0, -0.04)
	await _shot("09_stairwell.png", 0, Vector3(-8.8, 0.0, 4.4), 0.0, 0.08)

	print("RUIN_MARKET_CAPTURE done: ", output_dir)
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
