extends SceneTree

## 学校已被整栋封闭：门被木板/钢条钉死，不能撬锁或进入。

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
	main.network_port = 28140 + int(Time.get_ticks_msec() % 30)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	ruin = main._ruin_planet
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(ruin != null and ruin.school_interior != null, "学校内部没有建立")
	check(player != null, "玩家没有生成")
	if player == null or ruin == null:
		print("RUIN_SCHOOL_SEALED: %d checks, %d failures" % [checks, failures.size()])
		quit(1)
		return
	var school: Dictionary = ruin.buildings["school"]
	var root_node: Node3D = school.root as Node3D
	check(root_node.find_child("SchoolSealBoardA", true, false) != null, "学校门没有封板")
	check(root_node.find_child("SchoolSealBrace", true, false) != null, "学校门没有钢条")
	player.teleport_to((school.entry as Vector3) + Vector3(0.0, 0.0, 0.5))
	ruin.unlock_building(1, "school")
	await process_frame
	check(ruin.is_building_locked("school"), "学校仍然可以被撬开")
	check(not ruin.discovered_buildings.has("school"), "学校仍然被登记为已进入")
	check(not ruin.is_inside_school(player.global_position), "玩家仍然能进入学校")
	check(ruin.prompt(player).contains("封死"), "学校门口没有封闭提示")

	print("RUIN_SCHOOL_SEALED: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
