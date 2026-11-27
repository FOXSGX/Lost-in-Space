extends SceneTree

## 庇护所暗门离开后必须背向暗门，而不是面对暗门。

var checks := 0
var failures: Array[String] = []
var main: Main3D
var ruin: RuinPlanet


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28320 + int(Time.get_ticks_msec() % 30)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	ruin = main._ruin_planet
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(player != null and ruin.shelter_interior != null, "庇护所或玩家没有建立")
	if player != null and ruin.shelter_interior != null:
		player.teleport_to(ruin.shelter_spawn_position())
		main.exit_shelter(1)
		await process_frame
		await physics_frame
		var exit_point: Vector3 = ruin.energy_secret_return_position()
		var door_origin: Vector3 = ruin.energy_station_interior.call("secret_door_position")
		var outward := Vector3(exit_point.x - door_origin.x, 0.0, exit_point.z - door_origin.z).normalized()
		check(not ruin.is_inside_shelter(player.global_position), "离开庇护所后仍在室内")
		check(player.global_position.distance_to(exit_point) < 2.0, "离开庇护所后没有回到暗门外")
		check((-player.global_transform.basis.z).dot(outward) > 0.9, "离开庇护所后没有背向暗门")
		check((-player._camera.global_transform.basis.z).dot(outward) > 0.8, "离开庇护所后镜头没有背向暗门")

	print("RUIN_SHELTER_EXIT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
