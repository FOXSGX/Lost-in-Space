extends SceneTree

## 医院楼梯/楼层连通审计：宽梯段、实体井底、上下平台和走廊开口。
## 胶囊尺寸与玩家一致；不依赖视觉截图，专门抓“看起来有楼梯但上不去”。

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
	var query := PhysicsRayQueryParameters3D.create(from, to, 2)
	return main.get_world_3d().direct_space_state.intersect_ray(query)


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
	main.network_port = 28650
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	ruin = main._ruin_planet
	var interior := ruin.hospital_interior as Node3D
	check(interior != null, "医院内部没有建立")
	if interior == null:
		_finish()
		return

	var base := 197.0
	var angle := atan(3.0 / 10.0)
	for interval: int in 3:
		var lower_y := base + float(interval) * 3.0
		var rises_north := interval % 2 == 0
		var bottom_z := 5.0 if rises_north else -5.0
		var top_z := -bottom_z
		var lane_x := -10.8 if interval % 2 == 0 else -8.4
		for step: int in 11:
			var fraction := float(step) / 10.0
			var z := lerpf(bottom_z, top_z, fraction)
			z = clampf(z, -4.8, 4.8)
			var expected_y := lower_y + 1.5 - z * tan(angle) if rises_north else lower_y + 1.5 + z * tan(angle)
			var hit := ray(Vector3(lane_x, expected_y + 1.0, z), Vector3(lane_x, expected_y - 0.8, z))
			check(not hit.is_empty(), "医院楼梯 L%d 坡道没有落脚面 @z%.1f" % [interval, z])
			if not hit.is_empty():
				var surface_y := (hit.position as Vector3).y
				check(absf(surface_y - expected_y) < 0.48, "医院楼梯 L%d 坡面高度不连续 @z%.1f (%.2f/%.2f)" % [interval, z, surface_y, expected_y])
				check(capsule_clear(Vector3(lane_x, surface_y + 1.0, z)), "医院楼梯 L%d 坡道被侧墙/上层梯段占用 @z%.1f" % [interval, z])

		# 每层只有一个入口：B1 南、1F 北、2F 南、3F 北。
		var lower_entry_side := 1.0 if interval % 2 == 0 else -1.0
		for side: float in [-1.0, 1.0]:
			var landing_center := Vector3(-9.5, lower_y + 0.80, side * 6.0)
			check(capsule_clear(landing_center), "医院楼梯 L%d 平台中心被堵 @z%s" % [interval, side * 6.0])
			var landing_hit := ray(Vector3(-9.5, lower_y + 1.5, side * 6.0), Vector3(-9.5, lower_y - 0.5, side * 6.0))
			check(not landing_hit.is_empty(), "医院楼梯 L%d 平台没有地板 @z%s" % [interval, side * 6.0])
			if is_equal_approx(side, lower_entry_side):
				check(capsule_clear(Vector3(-7.0, lower_y + 0.80, side * 6.0)), "医院楼梯 L%d 入口被堵 @z%s" % [interval, side * 6.0])
				check(capsule_clear(Vector3(-7.0, lower_y + 0.8, side * 6.0 - 0.65)), "医院楼梯 L%d 入口左侧过窄" % interval)
				check(capsule_clear(Vector3(-7.0, lower_y + 0.8, side * 6.0 + 0.65)), "医院楼梯 L%d 入口右侧过窄" % interval)
			else:
				check(not capsule_clear(Vector3(-7.0, lower_y + 0.80, side * 6.0)), "医院楼梯 L%d 封闭侧仍能穿门 @z%s" % [interval, side * 6.0])

		# 上层入口在梯段抵达的另一侧。
		var upper_y := lower_y + 3.0
		var upper_entry_side := -lower_entry_side
		check(capsule_clear(Vector3(-7.0, upper_y + 0.80, upper_entry_side * 6.0)), "医院楼梯 L%d 上层入口不可达" % interval)
		check(not capsule_clear(Vector3(-7.0, upper_y + 0.80, lower_entry_side * 6.0)), "医院楼梯 L%d 上层封闭侧仍能穿门" % interval)

	# B1 楼梯井底：不是空洞，有 y=197 的完整地板。
	var bottom_hit := ray(Vector3(-9.5, base + 0.8, 0.0), Vector3(-9.5, base - 0.6, 0.0))
	check(not bottom_hit.is_empty(), "B1 楼梯底部没有地板")
	if not bottom_hit.is_empty():
		check(absf((bottom_hit.position as Vector3).y - base) < 0.12, "B1 楼梯底部地板高度不对")

	# 每层楼梯门后经西侧常开通道进入走廊；这条路径以前被整段墙封死。
	for level: int in [0, 1, 2, 3]:
		var level_y := base + float(level) * 3.0
		for side: float in [-1.0, 1.0]:
			check(capsule_clear(Vector3(-6.0, level_y + 0.8, side * 1.3)), "医院 L%d 楼梯到走廊的通道被墙封死 @z%s" % [level, side * 1.3])
			check(capsule_clear(Vector3(-6.0, level_y + 0.8, side * 2.2)), "医院 L%d 楼梯通道出口被堵 @z%s" % [level, side * 2.2])

	# B1 药库任务物路径：B1 南入口→西侧开口→走廊→药库→稳定剂前。
	for point: Vector3 in [
		Vector3(-9.5, base + 0.8, 6.0),
		Vector3(-6.0, base + 0.8, 1.3),
		Vector3(-3.0, base + 0.8, 0.0),
		Vector3(0.0, base + 0.8, 0.0),
		Vector3(4.0, base + 0.8, -1.3),
		Vector3(2.0, base + 0.8, -3.3),
	]:
		check(capsule_clear(point), "B1 药库稳定剂路径被堵 @%s" % str(point))

	print("RUIN_HOSPITAL_STAIR_TRAVERSAL: %d checks, %d failures" % [checks, failures.size()])
	_finish()


func _finish() -> void:
	quit(0 if failures.is_empty() else 1)
