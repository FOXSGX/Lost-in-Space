extends SceneTree

## 腐墟星物资/掉落物的落脚点验收：
## 物资箱、掉落物和街具必须在真实铺装顶面上，而不是埋在 y=0。

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 27780 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	await physics_frame

	var ruin: RuinPlanet = main._ruin_planet
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(ruin != null and player != null, "腐墟星没有建立")
	check(is_equal_approx(ruin.surface_height(0.0, 6.0), 0.09), "广场顶面高度不是 0.09")
	check(is_equal_approx(ruin.surface_height(30.0, 8.0), 0.035), "主街顶面高度不是 0.035")
	check(is_equal_approx(ruin.surface_height(0.0, 12.5), 0.09), "自动售货机新点位不在广场上")

	for id in ruin.food_sites:
		var site: Dictionary = ruin.food_sites[id]
		var point: Vector3 = site.root.position
		check(absf(point.y - ruin.surface_height(point.x, point.z)) < 0.002, "物资点不在铺装顶面：" + String(id))
		check(is_instance_valid(site.ring) and site.ring.visible == false, "物资环初始状态错误：" + String(id))

	# 物资点不能压到长椅/花坛；food_b 原来正好压在 (6,12) 的长椅上。
	var blockers: Array[Vector2] = [
		Vector2(-6.0, 12.0), Vector2(6.0, 12.0), Vector2(-6.0, 0.0), Vector2(6.0, 0.0), Vector2(-40.0, -12.5),
		Vector2(-12.5, 6.0), Vector2(12.5, 6.0),
	]
	for id in ruin.food_sites:
		var site: Dictionary = ruin.food_sites[id]
		var point: Vector2 = Vector2(site.root.position.x, site.root.position.z)
		for blocker in blockers:
			check(point.distance_to(blocker) > 1.6, "物资点与街具重叠：%s / %s" % [String(id), str(blocker)])

	# 广场和主街现在都应该有可命中的薄碰撞；掉落物不会沉到 y=0。
	var space := main.get_world_3d().direct_space_state
	for sample in [[Vector3(0.0, 2.0, 6.0), 0.09], [Vector3(26.0, 2.0, 8.0), 0.035]]:
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(sample[0], Vector3(sample[0].x, -1.0, sample[0].z), 2))
		check(not hit.is_empty(), "铺装碰撞缺失：" + str(sample[0]))
		if not hit.is_empty():
			check(absf((hit.position as Vector3).y - float(sample[1])) < 0.006, "铺装碰撞高度不对：" + str(sample[0]))

	player.global_position = Vector3(0.0, 0.12, 10.0)
	var drop_point: Vector3 = main._items.drop_position(player)
	check(drop_point.y >= 0.09, "广场掉落点低于广场顶面：%.3f" % drop_point.y)
	var floor_bodies: Array[Node] = ruin.world_root.find_children("RuinFloor*", "StaticBody3D", true, false)
	check(floor_bodies.size() >= 8, "铺装碰撞体数量不足")

	# 真实丢一个医疗包，让它落到广场顶面，而不是穿过铺装沉到 y=0。
	main._items._spawn_drop(1, {"kind": "medical"})
	main._items.publish()
	for index: int in 40:
		await physics_frame
	var dropped: Dictionary = main._items.drops[main._items.drops.size() - 1]
	check(float(dropped.position.y) >= 0.085, "掉落物沉到广场下面：%.3f" % float(dropped.position.y))

	print("RUIN_ITEM_PLACEMENT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
