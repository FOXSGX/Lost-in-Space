extends SceneTree

## 学校封闭验收截图：只拍外部封死的门，不进入内部。

var output_dir := "user://ruin-school-sealed"
var main: Main3D
var player: SpacePlayer3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		output_dir = args[0]
	DirAccess.make_dir_recursive_absolute(output_dir)
	run.call_deferred()


func run() -> void:
	main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28160 + int(Time.get_ticks_msec() % 30)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	player = main.players.get(1) as SpacePlayer3D
	var school: Dictionary = main._ruin_planet.buildings["school"]
	var at: Vector3 = (school.entry as Vector3) + Vector3(0.0, 0.0, 1.6)
	player.teleport_to(at)
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	player._camera_pitch = 0.0
	player._camera_pitch_target = 0.0
	player._update_ruin_first_person(0.016)
	main._update_hud()
	for index in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image != null:
		image.save_png(output_dir.path_join("01_school_sealed.png"))
	print("RUIN_SCHOOL_CAPTURE done: ", output_dir)
	quit()
