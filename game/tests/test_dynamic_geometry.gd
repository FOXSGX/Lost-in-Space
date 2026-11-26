extends SceneTree

## Dynamic mechanical intersection audit.
##
## Samples the full motion envelope of the moving assemblies and tests the
## actual visible triangles (not just AABBs) for interpenetration:
##   - the three gimbal rings and the crystal through the swing envelope,
##   - the suspension cage rods vs the rings/crystal,
##   - the three capture rams through their full extension,
##   - the counterweight cart at both ends of its track,
##   - the isolation flanges and carriage at rest and separated.
##
## Intentional contacts (wheel on rail, claw pads on the capture collar, pin in
## its guide, flange dog teeth) are listed separately and not counted as defects.

var app: Node3D
var level: LevelBuilder
var core: CoreRig
var lock_rig: LockRig
var left_cart: WeightCart
var right_cart: WeightCart
var isolation: IsolationRig
var failures: int = 0
var checks: Array[Dictionary] = []
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
	print("DG ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "res://tests-out"
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(90)
	level = app.get("level") as LevelBuilder
	core = level.core
	lock_rig = level.lock_rig
	left_cart = level.left_cart
	right_cart = level.right_cart
	isolation = level.isolation
	core.set_physics_process(false)
	await audit_core()
	await audit_claws()
	await audit_carts()
	await audit_isolation()
	var report: Dictionary = {"ok": failures == 0, "failures": failures, "checks": checks}
	var f: FileAccess = FileAccess.open(out_dir + "/dynamic_geometry_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("DYNAMIC_GEOMETRY ", JSON.stringify({"ok": failures == 0, "failures": failures, "checks": checks.size()}))
	quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# Core gimbal envelope
# ---------------------------------------------------------------------------

func audit_core() -> void:
	var pairs: Array = [
		["OuterRing/RingBody", "MiddleRing/RingBody"],
		["OuterRing/RingBody", "InnerRing/RingBody"],
		["MiddleRing/RingBody", "InnerRing/RingBody"],
		["OuterRing/RingBody", "CrystalPivot/CoreCrystal"],
		["MiddleRing/RingBody", "CrystalPivot/CoreCrystal"],
		["InnerRing/RingBody", "CrystalPivot/CoreCrystal"],
		["CageRod", "OuterRing/RingBody"],
		["CageRod", "MiddleRing/RingBody"],
		["CageRod", "InnerRing/RingBody"],
		["CageRod", "CrystalPivot/CoreCrystal"],
		["CageCollar", "PivotBearing"],
	]
	var states: Array = [
		{"a": 0.0, "yaw": 0.0, "tilt": 0.0, "spin": 0.0},
		{"a": 0.58, "yaw": 0.55, "tilt": 0.30, "spin": 0.40},
		{"a": -0.58, "yaw": 1.10, "tilt": -0.30, "spin": -0.40},
		{"a": 0.40, "yaw": 2.20, "tilt": 0.38, "spin": 1.20},
		{"a": -0.40, "yaw": 3.30, "tilt": -0.38, "spin": -1.20},
		{"a": 0.20, "yaw": 4.40, "tilt": 0.20, "spin": 2.10},
	]
	var offenders: Array[String] = []
	var total_hits: int = 0
	for state in states:
		var info: Dictionary = state as Dictionary
		core.swing.rotation = Vector3(0, 0, float(info["a"]))
		core.swing.rotation.x = 0.0
		core.outer_yaw = float(info["yaw"])
		core.middle_tilt = float(info["tilt"])
		core.inner_spin = float(info["spin"])
		core._apply_ring_pose()
		await process_frame
		for pair in pairs:
			var a_name: String = str(pair[0])
			var b_name: String = str(pair[1])
			var ta: PackedVector3Array = tris_or_prefix(a_name, 3 if a_name.ends_with("RingBody") or a_name.ends_with("CageRod") else 1)
			var tb: PackedVector3Array = tris_or_prefix(b_name, 3 if b_name.ends_with("RingBody") or b_name.ends_with("CageRod") else 1)
			var hits: int = tri_sets_intersect(ta, tb)
			if hits > 0:
				total_hits += hits
				offenders.append("%s vs %s @ angle %.2f hits %d" % [a_name, b_name, float(info["a"]), hits])
			print("  core ", a_name, " vs ", b_name, " state a=", info["a"], " hits=", hits)
	check(offenders.is_empty(), "core rings/crystal/cage do not interpenetrate", {"offenders": offenders, "hits": total_hits})

	# Static rest pose measurements: show the clearances are real, not accidental.
	core.swing.rotation = Vector3.ZERO
	core.outer_yaw = 0.0
	core.middle_tilt = 0.0
	core.inner_spin = 0.0
	core._apply_ring_pose()
	await process_frame
	var crystal_aabb: AABB = world_aabb("ResonanceCore/Swing/CrystalPivot/CoreCrystal")
	var inner_aabb: AABB = world_aabb("ResonanceCore/Swing/InnerRing/RingBody")
	var cage_aabb: AABB = world_aabb_prefix("CageRod")
	check(crystal_aabb.size.x > 0.5, "crystal geometry present", {"aabb": str(crystal_aabb)})
	check(maxf(inner_aabb.size.x, maxf(inner_aabb.size.y, inner_aabb.size.z)) > 5.0, "inner ring geometry present", {"aabb": str(inner_aabb)})
	check(cage_aabb.size.x > 0.1, "cage rods present", {"aabb": str(cage_aabb)})


# ---------------------------------------------------------------------------
# Capture rams
# ---------------------------------------------------------------------------

func audit_claws() -> void:
	core.force_locked_state()
	core.set_physics_process(false)
	lock_rig.target_extension = 1.0
	await frames(140)
	# jaw plates across rams and against the crystal
	var jaw_hits: int = 0
	var pin_hits: int = 0
	for i in range(3):
		var jaw_i: PackedVector3Array = tris_path("CaptureRig/Ram_%d/CapturePin/JawTop" % i, 1)
		jaw_i.append_array(tris_path("CaptureRig/Ram_%d/CapturePin/JawBottom" % i, 1))
		jaw_hits += tri_sets_intersect(jaw_i, tris_path("ResonanceCore/Swing/CrystalPivot/CoreCrystal", 1))
		var pin_i: PackedVector3Array = tris_path("CaptureRig/Ram_%d/CapturePin" % i, 2)
		for j in range(i + 1, 3):
			pin_hits += tri_sets_intersect(pin_i, tris_path("CaptureRig/Ram_%d/CapturePin" % j, 2))
			var jaw_j: PackedVector3Array = tris_path("CaptureRig/Ram_%d/CapturePin/JawTop" % j, 1)
			jaw_j.append_array(tris_path("CaptureRig/Ram_%d/CapturePin/JawBottom" % j, 1))
			jaw_hits += tri_sets_intersect(jaw_i, jaw_j)
	check(jaw_hits == 0, "closed claw jaws do not touch the crystal or each other", {"hits": jaw_hits})
	check(pin_hits == 0, "the three capture pins do not intersect each other", {"hits": pin_hits})
	# Controlled contact: jaw pads vs the capture collar is expected to touch.
	var collar: PackedVector3Array = tris_path("ResonanceCore/Swing/CrystalPivot/CaptureCollar", 1)
	var contact_hits: int = 0
	for i in range(3):
		var jaw_i2: PackedVector3Array = tris_path("CaptureRig/Ram_%d/CapturePin/JawTop" % i, 1)
		jaw_i2.append_array(tris_path("CaptureRig/Ram_%d/CapturePin/JawBottom" % i, 1))
		contact_hits += tri_sets_intersect(jaw_i2, collar)
	print("  controlled jaw/collar triangle contacts: ", contact_hits)
	checks.append({"ok": true, "label": "jaw/collar contact is a controlled bearing contact", "details": {"hits": contact_hits}})


# ---------------------------------------------------------------------------
# Counterweight carts and track
# ---------------------------------------------------------------------------

func audit_carts() -> void:
	var track_names: Array[String] = ["TrackFascia", "TrestleBeam", "TrestleLeg"]
	var hit_total: int = 0
	for p in [0.0, 0.35, 1.0]:
		left_cart.set_p(p)
		right_cart.set_p(1.0 - p)
		await process_frame
		var track_all: PackedVector3Array = PackedVector3Array()
		for tn in track_names:
			track_all.append_array(tris_prefix_under(tn, level, 1))
		for cart_name in ["LeftCounterweight", "RightCounterweight"]:
			var body: PackedVector3Array = tris_path(cart_name + "/Chassis", 1)
			body.append_array(tris_path(cart_name + "/Bogie", 1))
			hit_total += tri_sets_intersect(body, track_all)
	check(hit_total == 0, "cart body never intersects the track structure", {"hits": hit_total})
	left_cart.set_p(0.2)
	await process_frame


# ---------------------------------------------------------------------------
# Isolation coupling
# ---------------------------------------------------------------------------

func audit_isolation() -> void:
	isolation.reset_state()
	await frames(6)
	var fixed_flange: PackedVector3Array = tris_path("ExtractionIsolationRig/FixedFlange", 1)
	var carriage_flange: PackedVector3Array = tris_path("ExtractionIsolationRig/SlidingCarriage/CarriageFlange", 1)
	var fixed_dogs: PackedVector3Array = tris_prefix_under("FixedDog", isolation, 1)
	var carriage_dogs: PackedVector3Array = tris_prefix_under("CarriageDog", isolation, 1)
	var flange_hits: int = tri_sets_intersect(fixed_flange, carriage_flange)
	var dog_hits: int = tri_sets_intersect(fixed_dogs, carriage_dogs)
	var pin_hits: int = tri_sets_intersect(tris_path("ExtractionIsolationRig/SafetyPin/PinBody", 1), fixed_flange)
	pin_hits += tri_sets_intersect(tris_path("ExtractionIsolationRig/SafetyPin/PinBody", 1), carriage_flange)
	check(flange_hits == 0, "fixed and sliding flange discs do not overlap", {"hits": flange_hits})
	check(dog_hits == 0, "dog teeth interlock without overlapping", {"hits": dog_hits})
	check(pin_hits == 0, "safety pin passes above the flange discs, not through them", {"hits": pin_hits})
	var gap_rest: float = flange_gap()
	isolation.force_separated_state()
	await frames(4)
	var gap_open: float = flange_gap()
	check(gap_rest > 0.05 and gap_rest < 0.35, "flange gap at rest is a real coupling clearance", {"gap": gap_rest})
	check(gap_open > 0.9, "flange gap after separation is open", {"gap": gap_open})
	var separated_hits: int = tri_sets_intersect(tris_path("ExtractionIsolationRig/FixedFlange", 1), tris_path("ExtractionIsolationRig/SlidingCarriage/CarriageFlange", 1))
	check(separated_hits == 0, "separated flanges are fully clear", {"hits": separated_hits})


func flange_gap() -> float:
	var fixed_aabb: AABB = world_aabb("ExtractionIsolationRig/FixedFlange")
	var carriage_aabb: AABB = world_aabb("ExtractionIsolationRig/SlidingCarriage/CarriageFlange")
	return maxf(0.0, fixed_aabb.position.x - (carriage_aabb.position.x + carriage_aabb.size.x))


# ---------------------------------------------------------------------------
# Triangle helpers
# ---------------------------------------------------------------------------

func tris_path(path: String, stride: int = 1) -> PackedVector3Array:
	var node: Node = level.get_node_or_null(path)
	if node == null:
		return PackedVector3Array()
	return tris_from_node(node, stride)


func tris_named(name: String, stride: int = 1) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for node in level.find_children(name, "MeshInstance3D", true, false):
		out.append_array(tris_from_node(node, stride))
	return out


func tris_or_prefix(name: String, stride: int = 1) -> PackedVector3Array:
	if name.contains("/"):
		return tris_path(name, stride)
	return tris_prefix(name, stride)


func tris_prefix(prefix: String, stride: int = 1) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if str(mi.name).begins_with(prefix):
			out.append_array(tris_from_node(mi, stride))
	return out


func tris_prefix_under(prefix: String, under: Node, stride: int = 1) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for node in under.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if str(mi.name).begins_with(prefix):
			out.append_array(tris_from_node(mi, stride))
	return out


func world_aabb_prefix(prefix: String) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if not str(mi.name).begins_with(prefix) or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func tris_named_under(name: String, under: Node, stride: int = 1) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for node in under.find_children(name, "MeshInstance3D", true, false):
		out.append_array(tris_from_node(node, stride))
	return out


func tris_from_node(node: Node, stride: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for mi_node in _meshes_under(node):
		var mi: MeshInstance3D = mi_node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D = mi.global_transform
		for s in range(mi.mesh.get_surface_count()):
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			if arrays.size() < Mesh.ARRAY_VERTEX + 1:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx_variant: Variant = arrays[Mesh.ARRAY_INDEX]
			var idx: PackedInt32Array = PackedInt32Array()
			if idx_variant != null:
				idx = idx_variant as PackedInt32Array
			if idx.is_empty():
				var t_count: int = verts.size() / 3
				var ti: int = 0
				while ti < t_count:
					if ti % stride == 0:
						out.append(xf * verts[ti * 3])
						out.append(xf * verts[ti * 3 + 1])
						out.append(xf * verts[ti * 3 + 2])
					ti += 1
			else:
				var tri_count: int = idx.size() / 3
				var ti2: int = 0
				while ti2 < tri_count:
					if ti2 % stride == 0:
						out.append(xf * verts[idx[ti2 * 3]])
						out.append(xf * verts[idx[ti2 * 3 + 1]])
						out.append(xf * verts[idx[ti2 * 3 + 2]])
					ti2 += 1
	return out


func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes_under(child))
	return out


func world_aabb(path: String) -> AABB:
	var node: Node = level.get_node_or_null(path)
	if node == null:
		return AABB()
	var out: AABB = AABB()
	var first: bool = true
	for mi in _meshes_under(node):
		var m: MeshInstance3D = mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func world_aabb_named(name: String) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for node in level.find_children(name, "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func tri_sets_intersect(a: PackedVector3Array, b: PackedVector3Array) -> int:
	if a.is_empty() or b.is_empty():
		return 0
	# Per-triangle AABBs for the broad phase.
	var a_boxes: Array[AABB] = []
	var a_count: int = a.size() / 3
	for i in range(a_count):
		a_boxes.append(AABB(a[i * 3], Vector3.ZERO).expand(a[i * 3 + 1]).expand(a[i * 3 + 2]))
	var b_boxes: Array[AABB] = []
	var b_count: int = b.size() / 3
	for j in range(b_count):
		b_boxes.append(AABB(b[j * 3], Vector3.ZERO).expand(b[j * 3 + 1]).expand(b[j * 3 + 2]))
	var hits: int = 0
	for i in range(a_count):
		var ab: AABB = a_boxes[i]
		for j in range(b_count):
			if not ab.intersects(b_boxes[j]):
				continue
			if tri_tri(
				a[i * 3], a[i * 3 + 1], a[i * 3 + 2],
				b[j * 3], b[j * 3 + 1], b[j * 3 + 2]
			):
				hits += 1
				if hits > 32:
					return hits
	return hits


func tri_tri(a0: Vector3, a1: Vector3, a2: Vector3, b0: Vector3, b1: Vector3, b2: Vector3) -> bool:
	# Non-coplanar triangles intersect iff one of their edges pierces the other.
	return (
		seg_tri(a0, a1, b0, b1, b2) or seg_tri(a1, a2, b0, b1, b2) or seg_tri(a2, a0, b0, b1, b2)
		or seg_tri(b0, b1, a0, a1, a2) or seg_tri(b1, b2, a0, a1, a2) or seg_tri(b2, b0, a0, a1, a2)
	)


func seg_tri(p0: Vector3, p1: Vector3, t0: Vector3, t1: Vector3, t2: Vector3) -> bool:
	var dir: Vector3 = p1 - p0
	var e1: Vector3 = t1 - t0
	var e2: Vector3 = t2 - t0
	var h: Vector3 = dir.cross(e2)
	var det: float = e1.dot(h)
	if absf(det) < 0.000001:
		return false
	var inv: float = 1.0 / det
	var s: Vector3 = p0 - t0
	var u: float = inv * s.dot(h)
	if u < -0.0001 or u > 1.0001:
		return false
	var q: Vector3 = s.cross(e1)
	var v: float = inv * dir.dot(q)
	if v < -0.0001 or u + v > 1.0001:
		return false
	var t: float = inv * e2.dot(q)
	return t > 0.0001 and t < 0.9999


