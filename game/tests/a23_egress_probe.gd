extends SceneTree

## ACT23-MP-DECK-EGRESS-FIX-R1 · static ground-support probe (single process).
##
## Not a gameplay run: it boots the real Act23 chapter, parks the cart exactly at
## the fault stop (distance 88.0, same as production FAULT_STOP) and maps what
## is under the deck gate — ground height, owning collider, layer — so the
## "does the yard actually have a floor at the exit" question is answered with
## raycasts instead of guesses.
##
## Usage:
##   godot --headless --path <project> -s res://tests/a23_egress_probe.gd \
##     -- --out=<dir> [--dist=88.0]
##
## It never moves a player, never sets on_deck, never writes gameplay state.

var out_dir: String = ""
var dist: float = 88.0
var _stage: Node = null
var _cart: Node3D = null
var _lines: Array[String] = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = str(a)
		if s.begins_with("--out="): out_dir = s.split("=")[1]
		elif s.begins_with("--dist="): dist = float(s.split("=")[1])
	_run.call_deferred()

func log_line(text: String) -> void:
	_lines.append(text)
	print("[egress_probe] ", text)

func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return space.intersect_ray(q)

func _hit_row(space: PhysicsDirectSpaceState3D, at: Vector3, tag: String) -> Dictionary:
	var hit: Dictionary = _ray(space, at + Vector3.UP * 4.0, at + Vector3.DOWN * 8.0)
	if hit.is_empty():
		return {"tag": tag, "x": snappedf(at.x, 0.01), "z": snappedf(at.z, 0.01),
			"ground_y": null, "body": "", "layer": 0}
	var body: Object = hit.get("collider")
	var body_name: String = ""
	var layer: int = 0
	if body != null and is_instance_valid(body):
		body_name = str((body as Node).name)
		layer = int((body as CollisionObject3D).collision_layer)
	return {"tag": tag, "x": snappedf(at.x, 0.01), "z": snappedf(at.z, 0.01),
		"ground_y": snappedf((hit["position"] as Vector3).y, 0.001),
		"body": body_name, "layer": layer}

func _colliders_report(root: Node) -> Array:
	var rows: Array = []
	for node in root.find_children("*", "CollisionObject3D", true, false):
		var body: CollisionObject3D = node as CollisionObject3D
		var aabb: AABB = AABB()
		var first: bool = true
		for c in body.find_children("*", "CollisionShape3D", true, false):
			var cs: CollisionShape3D = c as CollisionShape3D
			if cs.shape == null: continue
			var local_aabb: AABB = cs.transform * cs.shape.get_debug_mesh().get_aabb()
			var world_aabb: AABB = body.global_transform * local_aabb
			aabb = world_aabb if first else aabb.merge(world_aabb)
			first = false
		if first: continue
		var centre: Vector3 = aabb.get_center()
		rows.append({
			"name": str(body.name),
			"path": str(body.get_path()),
			"class": body.get_class(),
			"layer": body.collision_layer,
			"mask": body.collision_mask,
			"center": [snappedf(centre.x, 0.01), snappedf(centre.y, 0.01), snappedf(centre.z, 0.01)],
			"size": [snappedf(aabb.size.x, 0.01), snappedf(aabb.size.y, 0.01), snappedf(aabb.size.z, 0.01)],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float((a["center"] as Array)[1]) > float((b["center"] as Array)[1]))
	return rows

func _find_slice() -> Node:
	if current_scene == null:
		return null
	if current_scene.get("cart") != null:
		return current_scene
	for path in ["MovingCartSlice", "Act23Entry/MovingCartSlice"]:
		var found: Node = current_scene.get_node_or_null(path)
		if found != null and found.get("cart") != null:
			return found
	return null

func _run() -> void:
	log_line("boot project=%s" % ProjectSettings.globalize_path("res://"))
	change_scene_to_file("res://scenes/act23.tscn")
	var waited: float = 0.0
	var slice: Node = null
	while waited < 60.0:
		await process_frame
		waited += 1.0 / 60.0
		slice = _find_slice()
		if slice != null and slice.get("loaded") == true:
			break
	if slice == null:
		log_line("FAIL no Act23 slice (scene=%s)" % (str(current_scene.name) if current_scene != null else "null"))
		_finish()
		return
	_stage = slice
	_cart = _stage.get("cart") as Node3D
	log_line("scene=%s cart_class=%s loaded=%s" % [str(current_scene.name), _cart.get_class(), str(_stage.get("loaded"))])
	# Park the cart at the production fault stop. This is scene setup for the
	# probe only; no player position and no gameplay flag is touched.
	_cart.call("snap_to_distance", dist)
	_cart.set("speed", 0.0)
	_cart.set("running", false)
	await physics_frame
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	var cart_xf: Transform3D = _cart.global_transform
	log_line("cart distance=%.3f global=%s" % [float(_cart.get("distance")), str(cart_xf.origin)])
	var yard: Node3D = _stage.get("yard") as Node3D
	var player: CharacterBody3D = _stage.get("player") as CharacterBody3D
	log_line("yard_global=%s player_spawn=%s" % [str(yard.global_position), str(player.global_position)])

	# --- 1. deck box extents as production defines them ---------------------
	var deck_top_local: float = 1.9546444
	var rows: Array = []
	# Egress lane: x = 1.0 (the authored gate gap centre is x 0.52..1.48) walking
	# from the deck centre out to the south apron, plus lateral probes across the
	# gate gap and the platform edges.
	for z: float in [2.60, 2.20, 1.80, 1.35, 1.10, 0.90, 0.87, 0.60, 0.30, 0.00,
			-0.40, -0.70, -1.00, -1.40, -2.00, -2.40, -2.80, -3.30, -3.80]:
		rows.append(_hit_row(space, cart_xf * Vector3(1.0, 0.0, z), "lane_x1.00_z%.2f" % z))
	for x: float in [0.0, 0.52, 0.75, 1.0, 1.25, 1.48, 1.9]:
		rows.append(_hit_row(space, cart_xf * Vector3(x, 0.0, 0.10), "gate_x%.2f_z0.10" % x))
	# The cart deck surface itself (should hit the cart body).
	rows.append(_hit_row(space, cart_xf * Vector3(1.0, 0.0, 2.00), "deck_surface_x1.00_z2.00"))
	# Yard side around the winch console / walkway.
	var yard_xf: Transform3D = yard.global_transform
	for z: float in [3.40, 0.0, -2.40]:
		for x: float in [-2.6, 0.0, 2.0, 4.5, 6.5]:
			rows.append(_hit_row(space, yard_xf * Vector3(x, 0.0, z), "yard_x%.2f_z%.2f" % [x, z]))

	# --- 2. every collider near the stop (layer + extent) --------------------
	var colliders: Array = _colliders_report(_stage)
	var near: Array = []
	for row in colliders:
		var c: Array = row["center"] as Array
		var world_centre := Vector3(float(c[0]), float(c[1]), float(c[2]))
		var local: Vector3 = cart_xf.affine_inverse() * world_centre
		if absf(local.x) < 12.0 and absf(local.z) < 12.0:
			var copy: Dictionary = (row as Dictionary).duplicate(true)
			copy["cart_local_center"] = [snappedf(local.x, 0.01), snappedf(local.y, 0.01), snappedf(local.z, 0.01)]
			near.append(copy)

	# --- 3. production predicates at the same points ------------------------
	var contains: Array = []
	for z: float in [3.53, 3.0, 2.6, 2.2, 1.35, 1.0, 0.90, 0.87, 0.86, 0.5, 0.0, -0.6]:
		for x: float in [0.52, 1.0, 1.48]:
			var world: Vector3 = cart_xf * Vector3(x, deck_top_local, z)
			contains.append({"x": x, "z": z, "contains": bool(_cart.call("contains_point", world))})

	# --- 4. the authored dock/landing platforms -----------------------------
	var landings: Array = []
	for node in _stage.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if str(mesh.name).begins_with("DockLanding"):
			var aabb: AABB = mesh.global_transform * mesh.get_aabb()
			landings.append({"name": str(mesh.name),
				"center": [snappedf(aabb.get_center().x, 0.01), snappedf(aabb.get_center().y, 0.01), snappedf(aabb.get_center().z, 0.01)],
				"size": [snappedf(aabb.size.x, 0.01), snappedf(aabb.size.y, 0.01), snappedf(aabb.size.z, 0.01)]})

	var payload: Dictionary = {
		"probe": "a23_egress_probe",
		"distance": float(_cart.get("distance")),
		"cart_global": {"origin": [cart_xf.origin.x, cart_xf.origin.y, cart_xf.origin.z]},
		"deck_top_local": deck_top_local,
		"ray_rows": rows,
		"colliders_near": near,
		"contains_samples": contains,
		"dock_landings": landings,
		"player_spawn": [player.global_position.x, player.global_position.y, player.global_position.z],
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f: FileAccess = FileAccess.open(out_dir.path_join("a23_egress_probe.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(payload, "  "))
			f.close()
	# Human-readable summary: the egress lane only.
	for row in rows:
		var d: Dictionary = row as Dictionary
		if str(d["tag"]).begins_with("lane_"):
			log_line("%-22s ground_y=%s body=%s layer=%d" % [str(d["tag"]), str(d["ground_y"]), str(d["body"]), int(d["layer"])])
	for row in rows:
		var d2: Dictionary = row as Dictionary
		if str(d2["tag"]).begins_with("deck_surface") or str(d2["tag"]).begins_with("gate_"):
			log_line("%-28s ground_y=%s body=%s layer=%d" % [str(d2["tag"]), str(d2["ground_y"]), str(d2["body"]), int(d2["layer"])])
	for row in near:
		var d3: Dictionary = row as Dictionary
		log_line("COLLIDER %-26s layer=%-3d size=%s local=%s" % [str(d3["name"]), int(d3["layer"]), str(d3["size"]), str(d3["cart_local_center"])])
	for l in landings:
		log_line("LANDING %s center=%s size=%s" % [str((l as Dictionary)["name"]), str((l as Dictionary)["center"]), str((l as Dictionary)["size"])])
	log_line("PROBE_DONE")
	_finish()

func _finish() -> void:
	quit(0)
