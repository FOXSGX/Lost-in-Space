extends SceneTree

## Act4 freight clamp / cargo-registration regression (audit R-02 / R-03 / R-21).
##
## A. The clamp must return to the OPEN travel after any release, so a second
##    load can be clamped again (it used to freeze at CHOCK_INNER / press 1.14 m
##    and eject the next crystal).
## B. seat_cargo() must refuse a crystal that is not actually inside the bay
##    (try_seat() calls it from 1.75 m away, which includes the dock floor).
## C. _blocked_ahead() must sample in FRONT of the deck, not behind it.
##
## Run: godot --headless --path game --script res://tests/act4_freight_clamp.gd

var app: Node3D
var platform: FreightPlatform
var crystal: PortableCrystal
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("FREIGHT ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func run() -> void:
	var scene: PackedScene = load("res://scenes/act4.tscn") as PackedScene
	app = scene.instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(60)
	platform = app.get("platform") as FreightPlatform
	crystal = app.get("crystal_a") as PortableCrystal
	check(platform != null, "platform resolved")
	check(crystal != null, "crystal_a resolved")
	if platform == null or crystal == null:
		print("ACT4_FREIGHT_REPORT ", JSON.stringify({"checks": checks, "failures": failures, "ok": false}))
		quit(1)
		return

	var bay: Vector3 = platform.get_bay_position()

	# ---- C: probe direction ------------------------------------------------
	# The probe is a 0.34 m ray from +1.72 m to +2.06 m along the travel axis,
	# at platform-origin height + BLOCK_PROBE_HEIGHT (0.90 m). The wall must sit
	# inside that segment, so place it 1.90 m ahead at the same height.
	platform.speed = 1.0
	var probe_y: float = platform.global_position.y + 0.90
	var probe_x: float = platform.global_position.x
	var probe_z: float = platform.global_position.z
	# The wall must sit BEYOND the probe's start (1.72 m): a ray that starts
	# inside a shape reports nothing (hit_from_inside defaults to false), which
	# is why a wall at 1.9 m with 0.4 m thickness silently produced no hit.
	var front_wall: StaticBody3D = _wall(Vector3(probe_x + 2.20, probe_y, probe_z))
	await frames(2)
	platform.speed = 1.0
	check(platform.call("_blocked_ahead"), "obstacle AHEAD is detected", {
		"dir": 1.0, "wall": Vector3(probe_x + 2.20, probe_y, probe_z)})
	front_wall.queue_free()
	await frames(2)
	var back_wall: StaticBody3D = _wall(Vector3(probe_x - 2.20, probe_y, probe_z))
	await frames(2)
	platform.speed = 1.0
	check(not platform.call("_blocked_ahead"), "obstacle BEHIND is ignored", {"dir": 1.0})
	back_wall.queue_free()
	platform.speed = 0.0
	await frames(2)

	# ---- B: registration must require real containment ---------------------
	crystal.freeze = false
	crystal.global_position = bay + Vector3(1.25, 0.35, 0.0)   # on the deck, outside the bay
	var rejected: bool = not bool(platform.call("seat_cargo", crystal))
	check(rejected, "crystal 1.25 m off bay centre is refused", {"cargo": platform.cargo})

	# ---- A: first load / clamp / release / second load ---------------------
	# NOTE: PortableCrystal auto-registers through try_seat() on its own physics
	# tick, so the explicit call must happen in the same frame as the placement;
	# otherwise the second call correctly reports "already occupied".
	crystal.global_position = bay + Vector3(0.0, 0.35, 0.0)
	check(bool(platform.call("seat_cargo", crystal)), "crystal inside the bay is accepted")
	await frames(4)
	platform.toggle_clamp()
	await frames(180)
	check(platform.is_cargo_fixed(), "first load clamps", {
		"clamp_t": platform.clamp_t, "locked": platform.jaw_locked,
	})
	var chock_after_first: float = platform.get("_chock_pos")
	var press_after_first: float = platform.get("_press_y")

	platform.release_cargo()
	check(is_equal_approx(float(platform.get("_chock_pos")), 1.20),
		"clamp returns to CHOCK_OPEN on release", {"chock": platform.get("_chock_pos")})
	check(is_equal_approx(float(platform.get("_press_y")), 1.80),
		"press plate returns to PRESS_OPEN_Y on release", {"press": platform.get("_press_y")})

	crystal.global_position = bay + Vector3(0.0, 0.35, 0.0)
	check(bool(platform.call("seat_cargo", crystal)), "second load is accepted")
	await frames(4)
	platform.toggle_clamp()
	await frames(180)
	check(platform.is_cargo_fixed(), "second load clamps again", {
		"clamp_t": platform.clamp_t, "locked": platform.jaw_locked,
		"first_chock": chock_after_first, "first_press": press_after_first,
	})

	# ---- D: R-07 grab stand positions clear all clamp chocks & rails --------
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.76
	var space: PhysicsDirectSpaceState3D = platform.get_world_3d().direct_space_state
	var chock_rids: Array[RID] = []
	for side_node: Node3D in platform.get("_clamp_sides"):
		for child: Node in side_node.get_children():
			if child is CollisionObject3D:
				chock_rids.append((child as CollisionObject3D).get_rid())
	var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	for pid_key: Variant in FreightPlatform.GRAB_POINTS.keys():
		var gp: Dictionary = FreightPlatform.GRAB_POINTS[pid_key] as Dictionary
		var stand_world: Vector3 = platform.to_global(gp["stand"] as Vector3) + Vector3(0.0, 0.90, 0.0)
		q.transform = Transform3D(Basis.IDENTITY, stand_world)
		var hits: Array[Dictionary] = space.intersect_shape(q, 8)
		var chock_hit: bool = false
		for h: Dictionary in hits:
			if chock_rids.has(h.get("rid")):
				chock_hit = true
				break
		check(not chock_hit, "grab point %s clears all clamp chocks" % str(pid_key), {"stand": gp["stand"]})

	print("ACT4_FREIGHT_REPORT ", JSON.stringify({
		"checks": checks, "failures": failures, "ok": failures == 0,
	}))
	quit(0 if failures == 0 else 1)


func _wall(at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.4, 1.6, 1.6)
	cs.shape = box
	body.add_child(cs)
	# Parent under the level (same World3D + Node3D ancestry) rather than the
	# SceneTree root Window: a body created directly on the viewport was not
	# reachable by the platform's ray query.
	app.add_child(body)
	body.global_position = at
	return body
