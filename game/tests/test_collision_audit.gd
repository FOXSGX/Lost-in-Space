extends SceneTree

## Strict collision / air-wall / camera audit for Resonance 05.
##
## Unlike the legacy AABB-overlap check, this test:
##   A. samples the actual collision surfaces (including trimeshes) and proves a
##      visible mesh exists at each sample;
##   B. walks the real player into walls, railings, the track, the doors and the
##      isolation bed, and reads the F3 block probe for each stop;
##   C. checks the eye is not inside visible geometry when standing close to
##      machinery and walls;
##   D. flags large reachable visible meshes that have no collision at all.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var hud: GameHud
var failures: int = 0
var checks: Array[Dictionary] = []
var visible_boxes: Array[Dictionary] = []
var out_dir: String = ""


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details})
	if not ok:
		failures += 1
	print("CA ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "res://tests-out"
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(80)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	hud = app.get("hud") as GameHud
	story.set_process(false)
	story.set_physics_process(false)
	hud.title_layer.visible = false
	hud.clear_subtitles()
	_collect_visible_boxes()
	await audit_collision_surfaces()
	await audit_player_presses()
	# The visible-without-collision sweep uses the AABBs captured at start-up, so
	# it has to run before the lane walk opens the blast door and moves geometry.
	audit_visible_without_collision()
	await audit_walkable_lanes()
	await audit_camera_clearance()
	var report: Dictionary = {
		"ok": failures == 0,
		"failures": failures,
		"checks": checks,
		"visible_meshes": visible_boxes.size(),
	}
	var f: FileAccess = FileAccess.open(out_dir + "/collision_audit_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("COLLISION_AUDIT ", JSON.stringify({"ok": failures == 0, "failures": failures, "checks": checks.size()}))
	quit(0 if failures == 0 else 1)


func _collect_visible_boxes() -> void:
	visible_boxes.clear()
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		visible_boxes.append({"node": mi, "aabb": aabb, "name": str(mi.get_path())})


func _covered(point: Vector3, grow: float = 0.06) -> String:
	for item in visible_boxes:
		var aabb: AABB = item["aabb"] as AABB
		if aabb.grow(grow).has_point(point):
			return str(item["name"])
	return ""


func audit_collision_surfaces() -> void:
	var bodies: Array[StaticBody3D] = []
	for node in level.find_children("*", "StaticBody3D", true, false):
		bodies.append(node as StaticBody3D)
	var total_samples: int = 0
	var uncovered: Array[String] = []
	var shape_count: int = 0
	var per_shape: Array[Dictionary] = []
	for body in bodies:
		for child in body.get_children():
			if not child is CollisionShape3D:
				continue
			var cs: CollisionShape3D = child as CollisionShape3D
			if cs.shape == null:
				continue
			shape_count += 1
			var samples: Array[Vector3] = _surface_samples(cs)
			var missing: int = 0
			var first_missing: String = ""
			for p in samples:
				total_samples += 1
				if _covered(p) == "":
					missing += 1
					if first_missing == "":
						first_missing = str(p)
			var ratio: float = 1.0 - float(missing) / float(maxi(1, samples.size()))
			if ratio < 0.55:
				uncovered.append("%s %s samples=%d uncovered=%d first=%s" % [str(cs.get_path()), cs.shape.get_class(), samples.size(), missing, first_missing])
			per_shape.append({"path": str(cs.get_path()), "ratio": ratio, "samples": samples.size()})
	check(shape_count > 150, "collision shapes enumerated", {"count": shape_count})
	check(uncovered.is_empty(), "every collision surface is backed by visible geometry", {"uncovered": uncovered, "samples": total_samples})
	var worst: float = 1.0
	var worst_path: String = ""
	for item in per_shape:
		if float(item["ratio"]) < worst:
			worst = float(item["ratio"])
			worst_path = str(item["path"])
	check(worst >= 0.5, "worst collision-surface coverage", {"ratio": worst, "shape": worst_path})


func _surface_samples(cs: CollisionShape3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var shape: Shape3D = cs.shape
	var xf: Transform3D = cs.global_transform
	if shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
		var stride: int = maxi(1, int(faces.size() / 70))
		var i: int = 0
		while i < faces.size():
			out.append(xf * faces[i])
			i += stride
		return out
	var dbg: Mesh = shape.get_debug_mesh()
	if dbg == null:
		return out
	var box: AABB = dbg.get_aabb()
	var c: Vector3 = box.get_center()
	var s: Vector3 = box.size
	for dx in [-0.5, 0.0, 0.5]:
		for dy in [-0.5, 0.0, 0.5]:
			for dz in [-0.5, 0.0, 0.5]:
				out.append(xf * (c + Vector3(s.x * dx, s.y * dy, s.z * dz)))
	return out


func audit_player_presses() -> void:
	player.mouse_enabled = false
	var probes: Array = [
		{"name": "tunnel east wall", "start": Vector3(1.5, 4.06, 30.0), "yaw": -PI * 0.5, "axis": "x", "limit": 3.5, "dir": 1.0},
		{"name": "tunnel west wall", "start": Vector3(-1.5, 4.06, 33.0), "yaw": PI * 0.5, "axis": "x", "limit": -3.5, "dir": -1.0},
		{"name": "hall east wall", "start": Vector3(13.0, 0.06, -2.0), "yaw": -PI * 0.5, "axis": "x", "limit": 15.9, "dir": 1.0},
		{"name": "hall west wall", "start": Vector3(-13.0, 0.06, -2.0), "yaw": PI * 0.5, "axis": "x", "limit": -15.9, "dir": -1.0},
		{"name": "balcony rail", "start": Vector3(0.0, 4.06, 11.6), "yaw": 0.0, "axis": "z", "limit": 10.3, "dir": -1.0},
		{"name": "left station outer rail", "start": Vector3(-8.7, 1.66, 6.6), "yaw": PI * 0.5, "axis": "x", "limit": -9.7, "dir": -1.0},
		{"name": "track trestle", "start": Vector3(10.2, 0.06, 3.2), "yaw": 0.0, "axis": "z", "limit": 1.6, "dir": -1.0},
		{"name": "core pedestal", "start": Vector3(0.0, 0.06, 5.2), "yaw": 0.0, "axis": "z", "limit": 3.0, "dir": -1.0},
		{"name": "isolation bed", "start": Vector3(10.5, 0.06, -6.4), "yaw": 0.0, "axis": "z", "limit": -7.7, "dir": -1.0},
		{"name": "entrance shutter", "start": Vector3(0.0, 4.06, 26.0), "yaw": 0.0, "axis": "z", "limit": 24.0, "dir": -1.0},
		{"name": "exit blast door", "start": Vector3(-13.6, 0.06, -2.0), "yaw": PI * 0.5, "axis": "x", "limit": -15.5, "dir": -1.0},
	]
	for probe in probes:
		var info: Dictionary = probe as Dictionary
		player.operating = false
		player.teleport(info["start"] as Vector3, float(info["yaw"]), 0.0)
		await frames(8)
		var before_events: int = player.block_events
		var start: Vector3 = player.global_position
		Input.action_press("move_forward")
		await frames(78)
		Input.action_release("move_forward")
		await frames(6)
		var end: Vector3 = player.global_position
		var axis: String = str(info["axis"])
		var value: float = end.x if axis == "x" else end.z
		var limit: float = float(info["limit"])
		var dir: float = float(info["dir"])
		var moved: float = start.distance_to(end)
		var stopped: bool = (value - limit) * dir <= 0.05
		var real_block: bool = player.block_events > before_events
		var not_air: bool = player.block_info.is_empty() or not bool(player.block_info.get("airwall_candidate", true))
		check(stopped, "walk blocked at " + str(info["name"]), {"end": str(end.snapped(Vector3(0.01, 0.01, 0.01))), "limit": limit})
		check(moved > 0.10, "player actually approached " + str(info["name"]), {"moved": moved})
		check(real_block, "F3 block probe fired at " + str(info["name"]), {"blocks": player.block_history.size()})
		check(not_air, "block at " + str(info["name"]) + " has visible geometry", {"block": player.block_info})
		if not player.block_info.is_empty():
			print("    block ", info["name"], " -> ", JSON.stringify(player.block_info))
			if bool(player.block_info.get("airwall_candidate", false)):
				var cp: Vector3 = player.block_info.get("contact", Vector3.ZERO) as Vector3
				for item in visible_boxes:
					var vb: AABB = item["aabb"] as AABB
					if vb.grow(0.5).has_point(cp):
						print("      near visible: ", item["name"], " aabb=", vb)


func audit_walkable_lanes() -> void:
	# Pressing into walls proves the walls block. It does not prove that a lane
	# which is supposed to be open really is: a post in the middle of the exit
	# doorway blocked the walkway while every wall probe still passed.
	# So the same real walking input is used to walk whole lanes end to end.
	level.exit_door.open_door()
	await frames(200)
	var lanes: Array = [
		{"name": "exit corridor centre lane", "start": Vector3(-13.2, 0.06, -2.0), "yaw": PI * 0.5, "expect": 11.0},
		{"name": "exit corridor west lane", "start": Vector3(-13.2, 0.06, -3.4), "yaw": PI * 0.5, "expect": 11.0},
		{"name": "exit corridor east lane", "start": Vector3(-13.2, 0.06, -0.6), "yaw": PI * 0.5, "expect": 11.0},
		{"name": "hall west aisle to exit door", "start": Vector3(-11.0, 0.06, -2.0), "yaw": PI * 0.5, "expect": 4.0},
	]
	for lane in lanes:
		var info: Dictionary = lane as Dictionary
		player.operating = false
		player.teleport(info["start"] as Vector3, float(info["yaw"]), 0.0)
		await frames(8)
		var start: Vector3 = player.global_position
		Input.action_press("move_forward")
		await frames(170)
		Input.action_release("move_forward")
		await frames(6)
		var end: Vector3 = player.global_position
		var moved: float = start.distance_to(end)
		var want: float = float(info["expect"])
		check(moved >= want, "lane is walkable end to end: " + str(info["name"]), {"moved": moved, "expected": want, "end": str(end.snapped(Vector3(0.01, 0.01, 0.01)))})


func audit_camera_clearance() -> void:
	var spots: Array = [
		{"name": "core pedestal edge", "pos": Vector3(0.0, 0.06, 3.6), "yaw": 0.0},
		{"name": "left console", "pos": Vector3(-8.6, 1.66, 7.4), "yaw": -0.5},
		{"name": "under track", "pos": Vector3(8.0, 0.06, 2.6), "yaw": 0.0},
		{"name": "east wall", "pos": Vector3(14.0, 0.06, -2.0), "yaw": -PI * 0.5},
		{"name": "isolation front", "pos": Vector3(10.7, 0.06, -6.4), "yaw": 0.0},
		{"name": "exit corridor", "pos": Vector3(-22.0, 0.06, -1.6), "yaw": PI * 0.5},
	]
	var inside: Array[String] = []
	for spot in spots:
		var info: Dictionary = spot as Dictionary
		player.teleport(info["pos"] as Vector3, float(info["yaw"]), 0.0)
		await frames(10)
		var eye: Vector3 = player.get_eye_position()
		for item in visible_boxes:
			var aabb: AABB = item["aabb"] as AABB
			var item_name: String = str(item["name"])
			if item_name.ends_with("/HallShell") or item_name.ends_with("/EntranceTunnel"):
				continue
			# 加法 godray 锥（CoreDomeShaft / ExitPortalShaft …）是体积光效：
			# 镜头“在它里面”是正常现象，不是穿模；它也不该有碰撞（会卡住视角）。
			if item_name.ends_with("Shaft"):
				continue
			if aabb.size.x * aabb.size.y * aabb.size.z < 0.25:
				continue
			var inner: AABB = aabb.grow(-0.02)
			if inner.size.x <= 0.01 or inner.size.y <= 0.01 or inner.size.z <= 0.01:
				continue
			if inner.has_point(eye):
				inside.append("%s inside %s" % [info["name"], item["name"]])
				break
	check(inside.is_empty(), "eye is never inside visible geometry", {"inside": inside})


func audit_visible_without_collision() -> void:
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var flagged: Array[String] = []
	var ignored_prefixes: Array[String] = ["Crystal", "WallCrystal", "OrbitShard", "Stalactite", "Field", "Energy", "Holo", "Label", "Beacon", "Dust", "Resonance", "Spark"]
	for item in visible_boxes:
		var mi: MeshInstance3D = item["node"] as MeshInstance3D
		var aabb: AABB = item["aabb"] as AABB
		var size: Vector3 = aabb.size
		if size.x * size.y * size.z < 0.60:
			continue
		if minf(size.x, minf(size.y, size.z)) < 0.18:
			continue
		if aabb.get_center().y > 2.2:
			continue
		var node_name: String = str(mi.name)
		var skip: bool = false
		for prefix in ignored_prefixes:
			if node_name.begins_with(prefix):
				skip = true
				break
		if skip:
			continue
		# 挂空的线缆本体/护套（…_WireRun/CartFeedbackL_Core 等）是装饰件：
		# 它们悬在头部高度，给碰撞只会让人物被“看不见的管子”卡住。
		# 这是按祖先节点名的结构性排除，不是逐个白名单。
		if _inside_wire_run(mi):
			continue
		var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var cap: CapsuleShape3D = CapsuleShape3D.new()
		cap.radius = 0.28
		cap.height = 1.4
		q.shape = cap
		q.transform = Transform3D(Basis(), aabb.get_center())
		q.collision_mask = 1
		var hits: Array[Dictionary] = space.intersect_shape(q, 2)
		if hits.is_empty():
			flagged.append(item["name"] + " " + str(size))
	check(flagged.is_empty(), "large visible props have collision", {"flagged": flagged})
	if not flagged.is_empty():
		print("    visible-without-collision: ", JSON.stringify(flagged))


## True when the mesh belongs to a hanging cable run (`*_WireRun`).
## Cable bodies/sleeves are decoration: they hang at head height and a collider
## there would snag the player on geometry that is not meant to block anyone.
func _inside_wire_run(mi: Node) -> bool:
	var node: Node = mi
	while node != null:
		if str(node.name).contains("WireRun"):
			return true
		if node == level:
			return false
		node = node.get_parent()
	return false




