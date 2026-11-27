extends SceneTree

## 四栋建筑楼梯统一医院模板：
## 两条 2.3 m 梯段槽位、实体踏步、中央分隔墙；每层只有一个入口并交错。

const STAIR_TEMPLATE := preload("res://scripts/ruin_stair_template.gd")

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


func capsule_clear(point: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.45
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis(), point)
	query.collision_mask = 2
	return main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	return main.get_world_3d().direct_space_state.intersect_ray(query)


func run() -> void:
	main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28230 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	ruin = main._ruin_planet

	var cases: Array[Dictionary] = [
		{"name": "医院", "node": ruin.hospital_interior, "x0": -12.0, "x1": -7.0, "z": 6.0, "levels": 4},
		{"name": "学校", "node": ruin.school_interior, "x0": -12.0, "x1": -7.0, "z": 6.0, "levels": 3},
		{"name": "超市", "node": ruin.market_interior, "x0": -14.0, "x1": -9.0, "z": 7.0, "levels": 2},
		{"name": "能源站", "node": ruin.energy_station_interior, "x0": -15.0, "x1": -10.0, "z": 6.0, "levels": 4},
	]
	for data: Dictionary in cases:
		var interior := data.node as Node3D
		if interior == null:
			check(false, "%s 室内没有建立" % data.name)
			continue
		for level: int in int(data.levels):
			var level_y: float = (interior.call("level_position", level) as Vector3).y
			var entry_side := 1.0 if level % 2 == 0 else -1.0
			var entry_point := Vector3(float(data.x1) + 0.5, level_y + 0.80, entry_side * float(data.z))
			var closed_point := Vector3(float(data.x1) + 0.12, level_y + 0.80, -entry_side * float(data.z))
			check(capsule_clear(entry_point), "%s L%d 唯一入口被堵" % [data.name, level])
			check(not capsule_clear(closed_point), "%s L%d 封闭侧仍可穿墙" % [data.name, level])
			var landing_hit := ray(Vector3((float(data.x0) + float(data.x1)) * 0.5, level_y + 1.5, entry_side * (float(data.z) + 0.5)), Vector3((float(data.x0) + float(data.x1)) * 0.5, level_y - 0.5, entry_side * (float(data.z) + 0.5)))
			check(not landing_hit.is_empty(), "%s L%d 楼梯入口平台缺失" % [data.name, level])
			if level < int(data.levels) - 1:
				var lane_x := STAIR_TEMPLATE.lane_center(float(data.x0), float(data.x1), level)
				var lane_hit := ray(Vector3(lane_x, level_y + 2.2, 0.0), Vector3(lane_x, level_y - 0.5, 0.0))
				check(not lane_hit.is_empty(), "%s L%d 梯段中心没有落脚面" % [data.name, level])
				check(not capsule_clear(Vector3((float(data.x0) + float(data.x1)) * 0.5, level_y + 0.8, 0.0)), "%s L%d 中央分隔墙缺失" % [data.name, level])
		print("STAIRS ", data.name, " ", interior.find_children("*Stair*", "MeshInstance3D", true, false).map(func(n): return n.name))
		check(interior.find_children("StairStepFill*", "MeshInstance3D", true, false).size() >= (int(data.levels) - 1) * 14, "%s 实体踏步数量不足" % data.name)
		check(interior.find_children("StairSideWall*", "MeshInstance3D", true, false).size() >= int(data.levels) - 1, "%s 中央分隔墙数量不足" % data.name)
		check(interior.find_children("StairDoorPost*", "MeshInstance3D", true, false).size() >= int(data.levels) * 2, "%s 楼梯门框不是沿 Z 轴" % data.name)
		check(interior.find_children("StairLanding*", "MeshInstance3D", true, false).size() >= int(data.levels), "%s 楼梯入口平台缺失" % data.name)
		check(interior.find_children("StairDoorLamp*", "MeshInstance3D", true, false).size() >= int(data.levels), "%s 楼梯门楣灯缺失" % data.name)
		check(interior.find_children("StairDoorSign*", "MeshInstance3D", true, false).size() >= int(data.levels), "%s 楼梯门牌缺失" % data.name)
		check(interior.find_children("StairFloorFill*", "MeshInstance3D", true, false).size() >= 1, "%s 空梯段槽位没有补地板" % data.name)
		check(interior.find_children("StairGuard*", "MeshInstance3D", true, false).is_empty(), "%s 仍保留防坠挡板" % data.name)
		var base_y: float = (interior.call("level_position", 0) as Vector3).y
		var inactive_x := STAIR_TEMPLATE.lane_center(float(data.x0), float(data.x1), 1)
		var fill_hit := ray(Vector3(inactive_x, base_y + 1.2, 0.0), Vector3(inactive_x, base_y - 1.0, 0.0))
		check(not fill_hit.is_empty(), "%s 底层空槽仍会掉入虚空" % data.name)

	print("RUIN_STAIR_PARITY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
