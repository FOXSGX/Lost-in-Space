extends SceneTree

const QUIET := preload("res://tests/quiet_window.gd")

## 入口取证：每个室内拍“进门向前”和“回头”两张，医院额外拍大厅宽景。
## 只用于检查出生朝向、入口门和空间尺度，不参与玩法。

var main: Main3D
var ruin: RuinPlanet
var player: SpacePlayer3D
var output_dir: String


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	QUIET.apply()
	var args := OS.get_cmdline_user_args()
	output_dir = args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://").path_join("../work/ruin-collision-20261125").simplify_path()
	DirAccess.make_dir_recursive_absolute(output_dir)
	main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28630
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	ruin = main._ruin_planet
	player = main.players.get(1) as SpacePlayer3D
	main.set_process(false)

	var entries := [
		["hospital", ruin.hospital_interior],
		["school", ruin.school_interior],
		["market", ruin.market_interior],
		["energy", ruin.energy_station_interior],
		["shelter", ruin.shelter_interior],
	]
	for entry: Array in entries:
		var key := String(entry[0])
		var interior := entry[1] as Node3D
		if interior == null:
			continue
		await _shot(key + "_forward.png", interior.call("spawn_position"), 0.0, -0.02)
		await _shot(key + "_door.png", interior.call("spawn_position"), PI, -0.02)
	await _shot("hospital_lobby_wide.png", (ruin.hospital_interior as Node3D).call("spawn_position"), 0.0, -0.02)
	await _shot("energy_lobby_wide.png", (ruin.energy_station_interior as Node3D).call("spawn_position"), 0.0, -0.02)

	print("RUIN_INTERIOR_ENTRY_CAPTURE done: ", output_dir)
	quit(0)


func _shot(file_name: String, point: Vector3, yaw: float, pitch: float) -> void:
	player.teleport_to(point)
	player.rotation.y = yaw
	player._camera_yaw = yaw
	player._camera_yaw_target = yaw
	player._camera_pitch = pitch
	player._camera_pitch_target = pitch
	player._update_ruin_first_person(0.016)
	ruin._apply_camera_environment()
	main._update_hud()
	main._update_ruin_interaction_hint(player, 0.016)
	for index: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image != null:
		image.save_png(output_dir.path_join(file_name))
