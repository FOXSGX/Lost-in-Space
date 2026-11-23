extends SceneTree

## Collision coverage / air-wall audit.
## Every static collision shape must have visible geometry at the same place, so
## a player can never be stopped by an invisible plane.

var app: Node3D
var level: LevelBuilder
var failures: int = 0
var checks: Array[Dictionary] = []


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details})
	if not ok:
		failures += 1
	print("AW ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://tests-out"
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(30)
	level = app.get("level") as LevelBuilder
	var meshes: Array[MeshInstance3D] = []
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null:
			meshes.append(mi)
	var shapes: int = 0
	var uncovered: Array[String] = []
	var max_size: float = 0.0
	for body in level.find_children("*", "StaticBody3D", true, false):
		var sb: StaticBody3D = body as StaticBody3D
		for child in sb.get_children():
			if not child is CollisionShape3D:
				continue
			var cs: CollisionShape3D = child as CollisionShape3D
			if cs.shape == null:
				continue
			shapes += 1
			var dbg: Mesh = cs.shape.get_debug_mesh()
			if dbg == null:
				continue
			var world_aabb: AABB = cs.global_transform * dbg.get_aabb()
			max_size = maxf(max_size, world_aabb.size.length())
			var found: bool = false
			for mi in meshes:
				var mbox: AABB = mi.global_transform * mi.get_aabb()
				if mbox.intersects(world_aabb):
					found = true
					break
			if not found:
				uncovered.append("%s (%s)" % [cs.get_path(), str(world_aabb)])
	check(shapes > 40, "collision shapes present", {"count": shapes})
	check(uncovered.is_empty(), "every collision shape has visible geometry", {"uncovered": uncovered, "count": uncovered.size()})
	check(max_size < 60.0, "no runaway air-wall box", {"largest_diagonal": max_size})

	# F3 debug overlay
	app.call("_toggle_debug")
	await frames(3)
	check(bool(app.get("debug_visible")), "F3 debug overlay enabled")
	var hud: GameHud = app.get("hud") as GameHud
	check(hud.debug_label.visible, "debug text is visible")
	check(debug_collisions_hint == true, "debug collision hint enabled")
	app.call("_toggle_debug")
	await frames(3)
	check(debug_collisions_hint == false, "debug collision hint disabled again")

	# player capsule clearance at known route points
	var player: PlayerController = app.get("player") as PlayerController
	var points: Array[Vector3] = [
		Vector3(0, 4.06, 38.0), Vector3(0, 4.06, 26.0), Vector3(0, 4.06, 12.6),
		Vector3(-5.0, 4.06, 10.4), Vector3(-5.0, 1.5, 4.2), Vector3(-5.0, 0.1, 2.3),
		Vector3(-8.0, 0.1, 2.2), Vector3(0, 0.1, 9.2), Vector3(10.3, 0.1, 4.2),
		Vector3(10.8, 0.1, -5.7), Vector3(-2.0, 0.1, -8.1), Vector3(-13.4, 0.1, -2.0),
	]
	var blocked: Array[String] = []
	for p in points:
		var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = 0.30
		capsule.height = 1.65
		q.shape = capsule
		q.transform = Transform3D(Basis(), p + Vector3(0, 0.95, 0))
		q.collision_mask = 1 | 8
		q.exclude = []
		var hits: Array[Dictionary] = player.get_world_3d().direct_space_state.intersect_shape(q, 8)
		if not hits.is_empty():
			blocked.append("%s -> %d" % [str(p), hits.size()])
	check(blocked.is_empty(), "route sample points are free for the player capsule", {"blocked": blocked})

	var report: Dictionary = {"ok": failures == 0, "failures": failures, "checks": checks, "shapes": shapes, "meshes": meshes.size(), "largest_diagonal": max_size}
	var f: FileAccess = FileAccess.open(out_dir + "/airwall_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("AIRWALL_REPORT ", JSON.stringify({"ok": failures == 0, "failures": failures, "shapes": shapes, "meshes": meshes.size()}))
	quit(0 if failures == 0 else 1)
