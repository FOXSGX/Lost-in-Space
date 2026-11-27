extends SceneTree

## 掉出室内地板的兜底：低于室内最低楼层后回入口；没有锚点且低于地面则回登陆艇。

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
	main.network_port = 28620
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	ruin = main._ruin_planet
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D

	main.enter_hospital(1)
	await process_frame
	var spawn: Vector3 = ruin.hospital_spawn_position()
	check(player.global_position.distance_to(spawn) < 1.0, "进入医院没有落在入口")
	check(not (ruin.get("_interior_anchors") as Dictionary).is_empty(), "进入医院没有登记室内锚点")

	# 故意掉到最低楼层以下，tick 应把玩家拉回入口。
	player.teleport_to(Vector3(spawn.x, spawn.y - 22.0, spawn.z))
	ruin.tick(0.016)
	await process_frame
	check(player.global_position.distance_to(spawn) < 0.6, "掉出医院地板后没有回入口")
	check(player.global_position.y > 195.0, "兜底后仍在室内低处")

	# 正常离开后清锚点；再掉到地面以下应回登陆艇，而不是回医院。
	main.exit_hospital(1)
	await process_frame
	check((ruin.get("_interior_anchors") as Dictionary).is_empty(), "离开医院没有清除室内锚点")
	player.teleport_to(Vector3(0.0, -12.0, 0.0))
	ruin.tick(0.016)
	await process_frame
	check(player.global_position.distance_to(ruin.pad_position()) < 4.0, "没有锚点掉到地面以下没有回登陆艇")
	check(player.global_position.y > -1.0, "回登陆艇后仍在地面以下")

	print("RUIN_VOID_RECOVERY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
