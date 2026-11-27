extends SceneTree

## 腐墟星室内外碰撞审计：出生/门口/楼层/核心井/楼梯/室外入口。
## 目标不是逐像素检查装饰，而是确认玩家不会掉出地板、不会穿过入口门洞、不会走进核心井。

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


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := main.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	return space.intersect_ray(query)


func capsule_clear(point: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.45
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis(), point)
	query.collision_mask = 2
	return main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func run() -> void:
	main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28610
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	ruin = main._ruin_planet

	var entries := [
		{"name": "医院", "node": ruin.hospital_interior, "base": 197.0, "level": 1, "levels": 4, "half_x": 12.0, "half_z": 8.5, "door": 8.38},
		{"name": "学校", "node": ruin.school_interior, "base": 450.0, "level": 0, "levels": 3, "half_x": 12.0, "half_z": 8.5, "door": 8.38},
		{"name": "超市", "node": ruin.market_interior, "base": 570.0, "level": 0, "levels": 2, "half_x": 14.0, "half_z": 9.0, "door": 8.88},
		{"name": "能源站", "node": ruin.energy_station_interior, "base": 320.0, "level": 2, "levels": 4, "half_x": 15.0, "half_z": 10.0, "door": 9.88},
		{"name": "庇护所", "node": ruin.shelter_interior, "base": 700.0, "level": 0, "levels": 1, "half_x": 9.0, "half_z": 6.0, "door": 5.88},
	]
	for entry: Dictionary in entries:
		var interior := entry["node"] as Node3D
		var label := String(entry["name"])
		check(interior != null, "%s 室内没有建立" % label)
		if interior == null:
			continue
		var base := float(entry["base"])
		var spawn: Vector3 = interior.call("spawn_position")
		var level_y: float = (interior.call("level_position", int(entry["level"])) as Vector3).y
		# 出生点脚下必须有地板。
		var floor_hit := ray(spawn + Vector3.UP * 1.5, spawn - Vector3.UP * 1.5)
		check(not floor_hit.is_empty(), "%s 出生点脚下没有地板" % label)
		if not floor_hit.is_empty():
			check(absf((floor_hit.position as Vector3).y - level_y) < 0.25, "%s 出生点地板高度不对" % label)
		# 出生胶囊不能卡在墙/家具里。
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.36
		capsule.height = 1.45
		var shape_query := PhysicsShapeQueryParameters3D.new()
		shape_query.shape = capsule
		shape_query.transform = Transform3D(Basis(), spawn + Vector3.UP * 0.78)
		shape_query.collision_mask = 2
		var overlaps := main.get_world_3d().direct_space_state.intersect_shape(shape_query, 1)
		check(overlaps.is_empty(), "%s 出生点被墙体/家具占用" % label)
		# 门内 2.2 m 必须能直走。
		var aisle_hit := ray(spawn + Vector3.UP * 1.0, spawn + Vector3.UP * 1.0 + Vector3(0.0, 0.0, -2.2))
		check(aisle_hit.is_empty(), "%s 出生点前方 2.2 m 被挡住" % label)
		# 回头必须撞到关着的入口门，而不是门洞/虚空。
		var door_hit := ray(spawn + Vector3.UP * 1.2, spawn + Vector3.UP * 1.2 + Vector3(0.0, 0.0, 3.2))
		check(not door_hit.is_empty(), "%s 入口门没有碰撞" % label)
		if not door_hit.is_empty():
			check(String((door_hit.collider as Node).name).contains("InteriorEntranceDoor"), "%s 入口门碰撞不是 InteriorEntranceDoorCollision" % label)
		# 楼层网格：排除已知楼梯井/核心井后，不应再出现无地板点。
		var level_count := int(entry["levels"])
		for level: int in level_count:
			var y: float = (interior.call("level_position", level) as Vector3).y
			for x: float in [-6.0, -2.0, 2.0, 6.0, 10.0]:
				for z: float in [-7.0, -3.0, 3.0, 7.0]:
					if absf(x) > float(entry["half_x"]) - 1.0 or absf(z) > float(entry["half_z"]) - 1.0:
						continue
					if x < -6.0 and absf(z) < 6.0:
						continue
					if label == "能源站" and absf(x) < 5.0 and absf(z) < 5.0:
						continue
					var hit := ray(Vector3(x, y + 1.5, z), Vector3(x, y - 0.5, z))
					check(not hit.is_empty(), "%s L%d 地板缺失 @(%d,%d)" % [label, level, int(x), int(z)])

	# 外墙缝：从室内沿墙向外打射线，除已知入口门外必须撞到碰撞。
	for entry: Dictionary in entries:
		var interior := entry["node"] as Node3D
		if interior == null:
			continue
		var label := String(entry["name"])
		var half_x := float(entry["half_x"])
		var half_z := float(entry["half_z"])
		var entrance_level := int(entry["level"])
		for level: int in int(entry["levels"]):
			var y: float = (interior.call("level_position", level) as Vector3).y
			for side: float in [-1.0, 1.0]:
				for z: float in range(-int(half_z) + 1, int(half_z)):
					var hit := ray(Vector3(side * (half_x - 0.6), y + 1.2, z), Vector3(side * (half_x + 0.4), y + 1.2, z))
					check(not hit.is_empty(), "%s L%d 东/西外墙有缝 @x%d,z%d" % [label, level, int(side * half_x), int(z)])
				for x: float in range(-int(half_x) + 1, int(half_x)):
					if level == entrance_level and absf(x) < 1.6:
						continue
					var hit := ray(Vector3(x, y + 1.2, side * (half_z - 0.6)), Vector3(x, y + 1.2, side * (half_z + 0.4)))
					check(not hit.is_empty(), "%s L%d 南/北外墙有缝 @x%d,z%d" % [label, level, int(x), int(side * half_z)])

	# 能源站 1F 进门右转：门框与南墙之间曾有 0.2 m 缝。
	var energy_seam := ruin.energy_station_interior as Node3D
	if energy_seam != null:
		var y: float = (energy_seam.call("level_position", 2) as Vector3).y
		for side: float in [-1.0, 1.0]:
			var seam_hit := ray(Vector3(side * 1.4, y + 1.2, 9.4), Vector3(side * 1.4, y + 1.2, 10.6))
			check(not seam_hit.is_empty(), "能源站 1F 入口%s侧门框/南墙仍有缝" % ("右" if side > 0.0 else "左"))
			check(not capsule_clear(Vector3(side * 1.4, y + 0.8, 9.8)), "能源站 1F 入口%s侧胶囊能挤过门框" % ("右" if side > 0.0 else "左"))

	# 能源站控制室：主通道不应被控制台/冷却罐占满。
	if energy_seam != null:
		var y: float = (energy_seam.call("level_position", 2) as Vector3).y
		for point: Vector3 in [Vector3(6.2, y + 0.8, 6.8), Vector3(9.0, y + 0.8, 7.2), Vector3(11.0, y + 0.8, 7.0)]:
			check(capsule_clear(point), "能源站控制室通道被家具占用 @%s" % str(point))

	# 医院中央走廊：每层主通道不能被病床/担架/护士台堵住。
	var hospital := ruin.hospital_interior as Node3D
	if hospital != null:
		for level: int in 4:
			var y: float = (hospital.call("level_position", level) as Vector3).y
			for x: float in [-5.0, -1.0, 3.0, 7.0]:
				check(capsule_clear(Vector3(x, y + 0.8, 0.0)), "医院 L%d 中央走廊被堵 @x%.1f" % [level, x])

	# 医院/能源站顶板、灯座与管线范围。
	for pair: Array in [[hospital, "医院", 197.0], [energy_seam, "能源站", 320.0]]:
		var interior := pair[0] as Node3D
		if interior == null:
			continue
		var label := String(pair[1])
		var base := float(pair[2])
		check(interior.find_children("HospitalCeiling", "MeshInstance3D", true, false).size() + interior.find_children("EnergyCeiling", "MeshInstance3D", true, false).size() > 0, "%s 没有顶板" % label)
		check(interior.find_children("CeilingLightMount", "MeshInstance3D", true, false).size() >= interior.find_children("CeilingLight", "MeshInstance3D", true, false).size(), "%s 有顶灯没有灯座" % label)
		var floor_prefix := "HospitalFloorTexture" if label == "医院" else "EnergyFloorTexture"
		var grout_prefix := "FloorGrout" if label == "医院" else "FloorPlateSeam"
		check(interior.find_children(floor_prefix + "*", "MeshInstance3D", true, false).size() >= 4, "%s 地面纹理层不足" % label)
		check(interior.find_children(grout_prefix + "*", "MeshInstance3D", true, false).size() >= 4, "%s 地面分缝缺失" % label)
		for node: Node in interior.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh == null or not String(mesh.name).contains("Pipe"):
				continue
			if String(mesh.name).begins_with("CorePipe"):
				continue
			var aabb: AABB = mesh.global_transform * mesh.get_aabb()
			var center_y := (aabb.position.y + aabb.end.y) * 0.5
			var floor_y: float = base + floor((aabb.position.y - base) / 3.0) * 3.0
			check(aabb.position.y >= floor_y - 0.08 and aabb.end.y <= floor_y + 3.08, "%s 管线越出楼层：%s AABB y %.2f..%.2f" % [label, mesh.name, aabb.position.y, aabb.end.y])

	# 能源站核心井：每层四个方向都必须撞到护栏碰撞。
	var energy := ruin.energy_station_interior as Node3D
	if energy != null:
		for level: int in 4:
			var y: float = (energy.call("level_position", level) as Vector3).y
			for side: float in [-1.0, 1.0]:
				var hit_z := ray(Vector3(0.0, y + 1.2, side * 5.0), Vector3(0.0, y + 1.2, 0.0))
				var hit_x := ray(Vector3(side * 5.0, y + 1.2, 0.0), Vector3(0.0, y + 1.2, 0.0))
				check(not hit_z.is_empty(), "能源站 L%d 核心井 z 向没有护栏碰撞" % level)
				check(not hit_x.is_empty(), "能源站 L%d 核心井 x 向没有护栏碰撞" % level)
		# 两条梯段槽位：同医院模板，中心 -13.71 / -11.29。
		for level: int in 3:
			var y: float = (energy.call("level_position", level) as Vector3).y
			var lane_x := -13.71 if level % 2 == 0 else -11.29
			var lane_hit := ray(Vector3(lane_x, y + 2.2, 0.0), Vector3(lane_x, y - 0.5, 0.0))
			check(not lane_hit.is_empty(), "能源站 L%d 梯段中心没有落脚面" % level)
			check(capsule_clear(Vector3(lane_x, y + 2.35, 0.0)), "能源站 L%d 梯段被栏杆/墙占用" % level)
			var entry_side := 1.0 if level % 2 == 0 else -1.0
			check(capsule_clear(Vector3(-10.0, y + 0.80, entry_side * 6.0)), "能源站 L%d 唯一楼梯入口被堵" % level)
			check(not capsule_clear(Vector3(-9.9, y + 0.80, -entry_side * 6.0)), "能源站 L%d 封闭侧仍可穿墙" % level)

	# 室外：登陆艇和 5 栋建筑入口都必须有地面。
	var exterior_points: Array[Vector3] = [ruin.pad_position()]
	for id: String in ruin.buildings.keys():
		exterior_points.append((ruin.buildings[id] as Dictionary).entry)
	for point: Vector3 in exterior_points:
		var hit := ray(point + Vector3.UP * 3.0, point - Vector3.UP * 3.0)
		check(not hit.is_empty(), "室外入口没有地面：%s" % str(point))

	print("RUIN_INTERIOR_CLIPPING: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
