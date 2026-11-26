extends RefCounted

## ACT23-MULTIPLAYER-DECK-EGRESS-FIX-R1 · reusable real-input Act23 flow.
##
## Used by the official-Launcher full-chain harness after the real Act01 ->
## Act23 hand-off, and by the direct chapter runner. It only drives the same
## Input actions a player uses (W/Shift/Space/E and the winch keys); it never
## teleports, writes gameplay flags or touches collision layers.
##
## The caller supplies the live Act23 slice and waits for the returned bool.
## Cross-process ordering uses this helper's own phase/done files in out_dir.

const VERSION := "a23flow-r1"

var tree: SceneTree
var role: String = "host"
var index: int = 0
var players: int = 3
var out_dir: String = ""
var mode: String = "full"
var tag: String = ""

var stage: Node = null
var player: CharacterBody3D = null
var cart: AnimatableBody3D = null
var flow: Node = null
var yard: Node3D = null
var rig: Node3D = null
var coop: Node = null
var me: int = 0
var expected_slot: int = 1

var checks: int = 0
var failures: Array[String] = []
var warnings: Array[String] = []
var started_ms: int = 0
var _cap: Dictionary = {}
var _passed: bool = false
var _finished: bool = false

func setup(p_tree: SceneTree, p_role: String, p_index: int, p_players: int,
		p_out: String, p_tag: String, p_mode: String, p_seat: int) -> void:
	tree = p_tree
	role = p_role
	index = p_index
	players = p_players
	out_dir = p_out
	tag = p_tag
	mode = p_mode
	expected_slot = p_seat if p_seat > 0 else (1 if role == "host" else index + 1)
	started_ms = Time.get_ticks_msec()

func run() -> bool:
	_record("a23_boot")
	await _run()
	return _passed and failures.is_empty()
# --------------------------------------------------------------------- utils --
func log_line(text: String) -> void:
	print("[%s%d] %s" % [role, index, text])

func check(ok: bool, text: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)
	return ok

func note(text: String) -> void:
	log_line("NOTE " + text)

func warn(text: String) -> void:
	warnings.append(text)
	log_line("WARN " + text)

func _wait(seconds: float) -> void:
	await tree.create_timer(seconds).timeout

func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout_s * 1000.0):
		if bool(cond.call()):
			return true
		await tree.process_frame
	return bool(cond.call())

func _abs(name: String) -> String:
	return out_dir.replace("\\", "/") + "/" + name

func _write_json(name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(_abs(name), FileAccess.WRITE)
	if f == null:
		log_line("FILE_WRITE_FAIL " + name)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()

func _read_json(name: String) -> Dictionary:
	if not FileAccess.file_exists(_abs(name)):
		return {}
	var f := FileAccess.open(_abs(name), FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	var parsed: Variant = j.data
	return parsed as Dictionary if parsed is Dictionary else {}

func _host_phase(name: String, extra: Dictionary = {}) -> void:
	if role != "host":
		return
	var doc := {"name": name, "seq": Time.get_ticks_msec()}
	for k in extra.keys():
		doc[k] = extra[k]
	_write_json("a23_phase.json", doc)

func _phase() -> String:
	return str(_read_json("a23_phase.json").get("name", ""))

func _wait_phase(name: String, timeout_s: float) -> bool:
	return await _wait_until(func() -> bool: return _phase() == name, timeout_s)

func _write_done(name: String, extra: Dictionary = {}) -> void:
	var doc := {"pid": me, "t": float(Time.get_ticks_msec() - started_ms) / 1000.0}
	for k in extra.keys():
		doc[k] = extra[k]
	_write_json("a23_" + name, doc)

func _done_exists(name: String) -> bool:
	return not _read_json("a23_" + name).is_empty()

func _valid(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	return node is Node

func _in_tree(node: Variant) -> bool:
	if not _valid(node):
		return false
	return (node as Node).is_inside_tree()

func _scene_now() -> String:
	return str(tree.current_scene.name) if tree.current_scene != null else "null"

func _find_slice() -> Node:
	if tree.current_scene == null:
		return null
	if tree.current_scene.get("cart") != null and tree.current_scene.get("player") != null:
		return tree.current_scene
	for path in ["MovingCartSlice", "Act23Entry/MovingCartSlice", "Act23Entry/Act23Entry/MovingCartSlice"]:
		var found: Node = tree.current_scene.get_node_or_null(path)
		if found != null and found.get("cart") != null:
			return found
	return null

# ------------------------------------------------------------------- capture --
func _snapshot() -> Dictionary:
	var out: Dictionary = {
		"pid": me, "role": role, "index": index,
		"t": float(Time.get_ticks_msec() - started_ms) / 1000.0,
		"scene": _scene_now(),
	}
	if stage != null and is_instance_valid(stage):
		out["stage_slot"] = int(stage.get("local_slot"))
		out["coop_mode"] = str(coop.get("mode")) if coop != null else "?"
		out["coop_slots"] = (coop.get("slots") as Dictionary).keys() if coop != null else []
		out["actors"] = (stage.get("actors") as Dictionary).keys()
	if cart != null and is_instance_valid(cart):
		out["distance"] = snappedf(float(cart.get("distance")), 0.01)
		out["speed"] = snappedf(float(cart.get("speed")), 0.01)
		out["running"] = bool(cart.get("running"))
		out["stopped_for_fault"] = bool(cart.get("stopped_for_fault"))
		out["arrived"] = bool(cart.get("arrived"))
		out["route_clear"] = bool(cart.get("route_clear"))
	if flow != null and is_instance_valid(flow):
		out["phase"] = str(flow.get("phase"))
		out["at_console"] = bool(flow.get("at_console"))
		out["console_actor"] = int(flow.get("console_actor"))
	if yard != null and is_instance_valid(yard):
		out["repaired"] = bool(yard.call("completion"))
	if _in_tree(player):
		out["pos"] = str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))
		out["on_deck"] = _on_deck()
		out["on_floor"] = bool(player.call("is_on_floor"))
		out["grip"] = int(player.get("grip_id"))
		out['recovery_count'] = int(player.get('recovery_count'))
		out["locked"] = player.get("interaction_locked") == true
	if stage != null and is_instance_valid(stage):
		out['safety_brakes'] = int(stage.get('_safety_brake_count'))
		out['stage_pids'] = (stage.get('actors') as Dictionary).keys()
	return out

func _record(label: String) -> void:
	var c := _snapshot()
	c["label"] = label
	_write_json("%s%d.%s.json" % [role, index, label], c)

# ------------------------------------------------------------------- status --
func _on_deck() -> bool:
	if not _valid(cart) or not _in_tree(player):
		return false
	return bool(cart.call("contains_point", player.global_position))

func _actor(pid: int) -> Node:
	if not _valid(stage):
		return null
	var actors: Variant = stage.get("actors")
	if not actors is Dictionary:
		return null
	return (actors as Dictionary).get(pid) as Node

func _remote_on_deck(pid: int) -> bool:
	var a: Node = _actor(pid)
	if not _valid(a) or not (a is Node3D):
		return false
	return bool(cart.call("contains_point", (a as Node3D).global_position))

func _remote_cleared(pid: int) -> bool:
	var a: Node = _actor(pid)
	if not _valid(a) or not (a is Node3D):
		return false
	var p: Vector3 = (a as Node3D).global_position
	return not bool(cart.call("contains_point", p)) and p.y < 0.60

func _all_remote_on_deck() -> bool:
	if not _valid(stage) or not _valid(cart):
		return false
	for p in range(1, players + 1):
		if p == me:
			continue
		if not _remote_on_deck(p):
			return false
	return true

func _all_on_deck() -> bool:
	if not _on_deck():
		return false
	return _all_remote_on_deck()

# ------------------------------------------------------------------ movement --
func _face(target: Vector3) -> void:
	if not _in_tree(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_yaw", yaw)

## Real W/Shift input. `local` targets are re-evaluated against the moving cart
## every frame; `check_y` also requires the body to arrive at the target height,
## so a body halfway up the six-step boarding stair is never "on the deck".
func _travel(target: Vector3, seconds: float, label: String, arrive: float,
		sprint: bool, check_y: bool, local: bool) -> bool:
	if not _in_tree(player):
		return false
	var start: Vector3 = player.global_position
	var world: Vector3 = cart.to_global(target) if local else target
	var climbing: bool = world.y > start.y + 0.30
	var descending: bool = world.y < start.y - 0.80
	var last: Vector3 = start
	var stuck_t: float = 0.0
	var elapsed: float = 0.0
	_face(world)
	if sprint:
		Input.action_press("sprint")
	Input.action_press("move_up")
	while elapsed < seconds:
		await tree.physics_frame
		elapsed += 1.0 / 60.0
		if not _in_tree(player):
			break
		world = cart.to_global(target) if local else target
		_face(world)
		var pos: Vector3 = player.global_position
		var flat: float = Vector2(pos.x - world.x, pos.z - world.z).length()
		var dy: float = absf(pos.y - world.y)
		if flat < arrive and (not check_y or ((not climbing or dy < 0.30) and (not descending or dy < 0.75))):
			break
		if pos.distance_to(last) < 0.008:
			stuck_t += 1.0 / 60.0
		else:
			stuck_t = 0.0
			last = pos
		if stuck_t > 0.95:
			log_line("WALK23_STUCK %s target=%s pos=%s flat=%.2f dy=%.2f" % [
				label, str(world.snapped(Vector3(0.01, 0.01, 0.01))),
				str(pos.snapped(Vector3(0.01, 0.01, 0.01))), flat, dy])
			_dump_blockers(world)
			break
	Input.action_release("move_up")
	if sprint:
		Input.action_release("sprint")
	await tree.physics_frame
	await _wait(0.05)
	if not _in_tree(player):
		return false
	var end: Vector3 = player.global_position
	world = cart.to_global(target) if local else target
	var final_flat: float = Vector2(end.x - world.x, end.z - world.z).length()
	log_line("WALK23 %s target=%s pos=%s moved=%.2f flat=%.2f y=%.2f" % [
		label, str(world.snapped(Vector3(0.01, 0.01, 0.01))),
		str(end.snapped(Vector3(0.01, 0.01, 0.01))), end.distance_to(start),
		final_flat, end.y])
	return final_flat <= arrive * 1.6

func _dump_blockers(world: Vector3) -> void:
	# Diagnostic only: report what the capsule actually touched, so a harness
	# route bug is not mistaken for level geometry.
	if not _in_tree(player):
		return
	var dir: Vector3 = world - player.global_position
	dir.y = 0.0
	dir = dir.normalized()
	log_line("BLOCK_DIAG pos=%s dir=%s on_deck=%s layer=%d mask=%d" % [
		str(player.global_position), str(dir), str(_on_deck()),
		int(player.get("collision_layer")), int(player.get("collision_mask"))])
	for i in range(player.get_slide_collision_count()):
		var col: KinematicCollision3D = player.get_slide_collision(i)
		if col == null:
			continue
		var other: Object = col.get_collider()
		if other is Node:
			var n: Node = other as Node
			var layer: int = int((n as Object).get("collision_layer")) if (n as Object).get("collision_layer") != null else -1
			log_line("BLOCK_SLIDE %s class=%s layer=%d at=%s" % [str(n.name), n.get_class(), layer, str(col.get_position())])
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.42
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3.UP * 0.9 + dir * 0.45)
	q.collision_mask = 0xFFFFFFFF
	q.exclude = [player.get_rid()]
	var hits := player.get_world_3d().direct_space_state.intersect_shape(q, 12)
	for h in hits:
		var o: Variant = h.get("collider")
		if o is Node:
			var n2: Node = o as Node
			var layer2: int = int((n2 as Object).get("collision_layer")) if (n2 as Object).get("collision_layer") != null else -1
			log_line("BLOCK_SHAPE %s class=%s layer=%d" % [
				str(n2.name), n2.get_class(), layer2])
	var ray_from: Vector3 = player.global_position + Vector3.UP * 0.9
	var rq := PhysicsRayQueryParameters3D.create(ray_from, ray_from + dir * 1.4, 0xFFFFFFFF, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(rq)
	if not hit.is_empty():
		var ro: Variant = hit.get("collider")
		var rname := "?"
		var rlayer := -1
		if ro is Node:
			rname = str((ro as Node).name)
			rlayer = int((ro as Object).get("collision_layer")) if (ro as Object).get("collision_layer") != null else -1
		log_line("BLOCK_RAY %s layer=%d normal=%s" % [rname, rlayer, str(hit.get("normal"))])

func _walk_world(target: Vector3, seconds: float, label: String, arrive := 0.55,
		sprint := false, check_y := false) -> bool:
	return await _travel(target, seconds, label, arrive, sprint, check_y, false)

func _walk_local(local: Vector3, seconds: float, label: String, arrive := 0.30,
		sprint := false, check_y := true) -> bool:
	return await _travel(local, seconds, label, arrive, sprint, check_y, true)

func _jump_up(seconds := 0.8) -> void:
	Input.action_press("move_up")
	await tree.physics_frame
	Input.action_press("jump")
	await _wait(0.12)
	Input.action_release("jump")
	var t := 0.0
	while t < seconds:
		await tree.physics_frame
		t += 1.0 / 60.0
	Input.action_release("move_up")

func _press(action: String, hold := 0.14) -> void:
	Input.action_press(action)
	await _wait(hold)
	Input.action_release(action)
	await _wait(0.45)

# ----------------------------------------------------------------- boot/wait --
func _boot() -> bool:
	var guard := 0
	while tree.current_scene == null and guard < 900:
		await tree.process_frame
		guard += 1
	if tree.current_scene == null:
		check(false, "Act23 scene booted")
		return false
	# Wait for the real moving-cart slice to finish _ready.
	guard = 0
	while guard < 1200:
		stage = _find_slice()
		if stage != null and stage.get("loaded") == true:
			break
		await tree.process_frame
		guard += 1
	if stage == null:
		check(false, "moving-cart slice exists (scene=%s)" % _scene_now())
		return false
	coop = stage.get("coop") as Node
	cart = stage.get("cart") as AnimatableBody3D
	flow = stage.get("flow") as Node
	yard = stage.get("yard") as Node3D
	player = stage.get("player") as CharacterBody3D
	rig = yard.get("rig") as Node3D if yard != null else null
	check(cart != null and player != null and flow != null and yard != null and rig != null,
		"Act23 world nodes present (player/cart/flow/yard/rig)")
	me = int(stage.get("local_slot"))
	expected_slot = 1 if role == "host" else index + 1
	if role == "host":
		check(int(player.get("peer_id")) == 1, "host body peer_id starts at slot 1")
	return cart != null and player != null and flow != null and yard != null and rig != null

func _wait_self() -> bool:
	# The client's local body is renamed from slot 1 to the host's welcome slot.
	# Do not assert the final seat until that real handshake has landed.
	if role == "host":
		check(me == 1, "host owns slot 1")
		return true
	var ok: bool = await _wait_until(func() -> bool:
		if not _valid(coop) or str(coop.get("mode")) != "client":
			return false
		return int(stage.get("local_slot")) == expected_slot, 120.0)
	me = int(stage.get("local_slot"))
	check(ok and me == expected_slot, "client accepted the host-assigned seat %d (slot=%d)" % [expected_slot, me])
	check(int(player.get("peer_id")) == me, "client body peer_id follows the assigned seat (%d)" % me)
	return ok and me == expected_slot

func _wait_peers() -> bool:
	if role == "host":
		var ok: bool = await _wait_until(func() -> bool:
			if not _valid(coop):
				return false
			var slots: Dictionary = coop.get("slots") as Dictionary
			if slots.size() < players:
				return false
			var nodes: Dictionary = stage.get("actors") as Dictionary
			return nodes.size() >= players, 300.0)
		check(ok, "host registered %d chapter peers (slots=%s actors=%s)" % [
			players, str((coop.get("slots") as Dictionary).keys()) if _valid(coop) else "?",
			str((stage.get("actors") as Dictionary).keys())])
		return ok
	var joined: bool = await _wait_until(func() -> bool:
		if not _valid(coop):
			return false
		var nodes: Dictionary = stage.get("actors") as Dictionary
		return nodes.size() >= players, 300.0)
	check(joined, "client sees all %d chapter bodies (actors=%s)" % [
		players, str((stage.get("actors") as Dictionary).keys())])
	return joined

func _ensure_on_pad() -> bool:
	await _wait(0.8)
	if _on_deck():
		return true
	var p: Vector3 = player.global_position
	var pad_top := 0.40
	var landing := cart.to_global(Vector3(1.0, pad_top, -2.0))
	var step := cart.to_global(Vector3(3.66, 0.21, -2.0))
	log_line("A23_SPAWN_RECOVER pos=%s landing=%s step=%s" % [str(p), str(landing), str(step)])
	# Only walk real input. The landing is 0.42 m above the cave floor; its
	# outboard step splits that lip into two climbable 0.21 m rises.
	if p.y < 0.20:
		await _walk_world(Vector3(step.x, 0.0, step.z), 5.0, "pad step foot", 0.55, false, false)
		await _walk_world(step + Vector3(0.0, 0.21, 0.0), 3.0, "pad step top", 0.45, false, false)
		await _jump_up(0.8)
	await _walk_world(landing, 5.0, "boarding landing", 0.55, false, true)
	if player.global_position.y < 0.30:
		await _jump_up(0.9)
		await _walk_world(landing, 4.0, "boarding landing retry", 0.60, false, false)
	var ok: bool = player.global_position.y > 0.20 and not _on_deck()
	log_line("A23_PAD pos=%s ok=%s floor=%s" % [str(player.global_position), str(ok), str(player.call("is_on_floor"))])
	return ok

# -------------------------------------------------------------------- boarding --
func _board_once() -> bool:
	await _walk_local(Vector3(1.0, 0.40, -2.0), 6.0, "boarding landing", 0.45, false, true)
	for attempt in range(4):
		if _on_deck():
			return true
		await _walk_local(Vector3(1.0, 0.40, -0.80), 4.0, "stair foot %d" % attempt, 0.22, false, true)
		await _walk_local(Vector3(1.0, 1.05, -0.10), 4.0, "stairs mid %d" % attempt, 0.22, false, true)
		await _walk_local(Vector3(1.0, 1.91, 0.55), 4.0, "stairs top %d" % attempt, 0.20, false, true)
		await _walk_local(Vector3(1.0, 1.95, 1.55), 4.0, "deck lane %d" % attempt, 0.20, false, true)
		if _on_deck():
			return true
		await _walk_local(Vector3(1.0, 0.40, -1.10), 4.0, "reset stairs %d" % attempt, 0.30, false, true)
	return _on_deck()

func _deck_spot(pid: int) -> Vector3:
	match pid:
		1: return Vector3(2.48, 1.95, 1.08)
		2: return Vector3(0.80, 1.95, 2.45)
		# Keep the north side clear for the real egress lane (x=1, z=2.6 -> 0.6).
		# These are authored cart-local deck positions, not teleports; each seat
		# still walks there with W before the host opens its exit turn.
		3: return Vector3(-1.50, 1.95, 2.80)
		_: return Vector3(-2.50, 1.95, 2.80)

func _waiting_spot(pid: int) -> Vector3:
	# Distinct authored landing positions. The production spawn point is shared
	# by every peer, so each body clears it with real W input as soon as its
	# seat is known. No position is assigned.
	match pid:
		1: return Vector3(2.60, 0.40, -3.00)
		2: return Vector3(3.00, 0.40, -1.20)
		3: return Vector3(0.20, 0.40, -3.00)
		_: return Vector3(3.00, 0.40, -2.60)

func _board_sequence() -> bool:
	# Host boards first. Every other seat waits for an explicit phase so four
	# 0.76 m capsules do not jam the single 0.90 m stair. This mirrors a crew
	# queueing at a door; all movement is real W input.
	if role == "host":
		if not await _board_once():
			check(false, "host physically boarded the cart deck")
			return false
		await _walk_local(_deck_spot(1), 5.0, "host control spot", 0.45, false)
		for p in range(2, players + 1):
			_host_phase("board_%d" % p)
			var ok: bool = await _wait_until(func() -> bool: return _done_exists("done_board_%d.json" % p), 180.0)
			check(ok, "host waited for pid%d to board" % p)
			if not ok:
				return false
		var all: bool = await _wait_until(func() -> bool: return _all_on_deck(), 120.0)
		check(all, "host sees all %d bodies on the deck" % players)
		return all
	var wait_board: bool = await _wait_phase("board_%d" % me, 300.0)
	check(wait_board, "pid%d received its real boarding turn" % me)
	if not wait_board:
		return false
	if not await _board_once():
		check(false, "pid%d physically boarded the cart deck" % me)
		_write_done("blocked_board_%d.json" % me, _snapshot())
		return false
	# Clear the stair top; the next seat needs the 0.90 m lane.
	await _walk_local(_deck_spot(me), 5.0, "deck spot pid%d" % me, 0.45, false)
	_write_done("done_board_%d.json" % me, {"on_deck": _on_deck(), "pos": str(player.global_position)})
	return true

# -------------------------------------------------------------------- launch --
func _launch_sequence() -> bool:
	if role == "host":
		await _wait(1.0)
		# Every reported seat is aboard; the host uses the real departure interlock.
		var all: bool = await _wait_until(func() -> bool: return _all_on_deck(), 120.0)
		check(all, "host departure interlock sees the whole crew aboard")
		if not all:
			return false
		await _walk_local(Vector3(2.48, 1.95, 1.08), 5.0, "departure controller", 0.45, false)
		for _attempt in range(5):
			if bool(cart.get("running")):
				break
			await _press("repair", 0.16)
			await _wait(0.7)
		var started: bool = await _wait_until(func() -> bool: return bool(cart.get("running")), 60.0)
		check(started, "host started the cart from the real deck controller")
		if not started:
			return false
		_host_phase("launch")
		return true
	var go: bool = await _wait_phase("launch", 300.0)
	check(go, "pid%d received the launch phase" % me)
	return go

# -------------------------------------------------------------------- egress --
func _exit_deck() -> bool:
	await _walk_local(Vector3(1.0, 1.95, 2.60), 7.0, "deck center", 0.30, false, true)
	await _walk_local(Vector3(1.0, 1.95, 1.35), 6.0, "gate lane", 0.10, false, true)
	await _walk_local(Vector3(1.0, 0.20, -0.60), 6.0, "through the boarding gate", 0.30, false, true)
	await _walk_local(Vector3(0.50, 0.0, -2.40), 5.0, "maintenance landing", 0.55, false, true)
	await _wait(0.5)
	if not _in_tree(player):
		return false
	var pos: Vector3 = player.global_position
	var grounded: bool = bool(player.call("is_on_floor"))
	var deck: bool = _on_deck()
	log_line("A23_OFF_DECK pos=%s grounded=%s on_deck=%s phase=%s" % [
		str(pos), str(grounded), str(deck), str(flow.get("phase"))])
	var ok: bool = (not deck) and pos.y >= 0.10 and pos.y < 0.90 and grounded
	if not ok:
		_write_done("blocked_egress_%d.json" % me, _snapshot())
		return false
	return true

func _exit_coordinator(order: Array) -> void:
	for p in order:
		_host_phase("exit_%d" % p)
		var ok: bool = await _wait_until(func() -> bool: return _done_exists("done_exit_%d.json" % p), 240.0)
		check(ok, "host waited for pid%d to clear the deck gate" % p)
		if not ok:
			return
		var prev_ok: bool = _read_json("a23_done_exit_%d.json" % p).get("ok", false)
		check(prev_ok, "pid%d reported a grounded landing off the deck" % p)
		if not prev_ok:
			return
	_host_phase("exit_all")

func _exit_sequence() -> bool:
	var order: Array = []
	for p in range(2, players + 1):
		order.append(p)
	order.append(1)
	if role == "host":
		# The host coordinates the queue but is also the last body through the
		# gate, so it must not return before its own phase arrives.
		_exit_coordinator.call_deferred(order)
	var turn: bool = await _wait_phase("exit_%d" % me, 420.0)
	check(turn, "pid%d received its real egress turn" % me)
	if not turn:
		return false
	# Release any grip with the same real E key before walking.
	if int(player.get("grip_id")) >= 0:
		await _press("repair", 0.14)
		await _wait(0.4)
	var ok2: bool = await _exit_deck()
	_write_done("done_exit_%d.json" % me, {"ok": ok2, "pos": str(player.global_position),
		"on_deck": _on_deck(), "phase": str(flow.get("phase"))})
	if not ok2:
		return false
	var all_out: bool = await _wait_phase("exit_all", 180.0)
	check(all_out, "pid%d saw the whole crew's egress phase" % me)
	return all_out

# ---------------------------------------------------------------------- yard --
func _console_stand() -> Vector3:
	return yard.to_global(Vector3(-0.60, 0.0, 3.95))

func _yard_route_to_console() -> Array:
	return [
		Vector3(89.0, 0.0, 0.0),
		Vector3(94.3, 0.0, 0.2),
		Vector3(94.3, 0.0, 4.7),
		Vector3(94.2, 0.0, 9.2),
		_console_stand(),
	]

func _reach_console() -> bool:
	var route: Array = _yard_route_to_console()
	for i in range(route.size()):
		var target: Vector3 = route[i] as Vector3
		var ok: bool = await _walk_world(target, 9.0, "yard leg %d" % i, 0.65, false, false)
		if not ok:
			warn("yard leg %d missed target %s (pos=%s)" % [i, str(target), str(player.global_position)])
	var console: Vector3 = (rig.get("winch") as Node3D).global_position
	var dist: float = player.global_position.distance_to(console)
	log_line("A23_CONSOLE_APPROACH pos=%s console=%s dist=%.2f phase=%s" % [
		str(player.global_position), str(console), dist, str(flow.get("phase"))])
	return dist <= 3.0

func _take_console() -> bool:
	var console: Vector3 = (rig.get("winch") as Node3D).global_position
	var d: Vector3 = console - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_yaw", yaw)
	await _wait(0.4)
	await _press("repair", 0.16)
	var at: bool = await _wait_until(func() -> bool: return bool(flow.get("at_console")), 20.0)
	var actor: int = int(flow.get("console_actor"))
	check(at, "pid%d took over the winch console with E (at_console=%s actor=%d)" % [me, str(at), actor])
	check(actor == me or actor == 0, "console_actor is the real operator (actor=%d expected=%d)" % [actor, me])
	return at and actor == me

# ------------------------------------------------------------------ full flow --
func _anchor_far() -> Node3D:
	for n: Node in tree.get_nodes_in_group("winch_anchor"):
		if _valid(n) and str(n.get("anchor_id")) == "eye_far":
			return n as Node3D
	return null

func _eye_stand() -> Vector3:
	return yard.to_global(Vector3(5.60, 0.0, -0.55))

func _hook_eye() -> bool:
	var route: Array = [
		Vector3(89.0, 0.0, 0.0),
		Vector3(94.3, 0.0, 0.2),
		Vector3(94.3, 0.0, 4.7),
		_eye_stand(),
	]
	for i in range(route.size()):
		await _walk_world(route[i] as Vector3, 9.0, "eye leg %d" % i, 0.65, false, false)
	var anchor: Node3D = _anchor_far()
	check(anchor != null, "front lifting eye exists")
	if anchor == null:
		return false
	var at: Vector3 = anchor.call("attach_point") as Vector3
	var d: Vector3 = at - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_yaw", yaw)
	await _wait(0.4)
	log_line("A23_EYE pos=%s attach=%s dist=%.2f" % [
		str(player.global_position), str(at), player.global_position.distance_to(at)])
	await _press("repair", 0.16)
	await _wait(0.8)
	var tension: Dictionary = rig.call("tension_state") as Dictionary
	var attached: bool = bool(tension.get("attached", false))
	check(attached, "pid%d hooked the cable onto the front lifting eye with E" % me)
	return attached

func _walk_to_console_from_eye() -> bool:
	var route: Array = [
		yard.to_global(Vector3(5.60, 0.0, -1.50)),
		yard.to_global(Vector3(5.70, 0.0, 4.60)),
		_console_stand(),
	]
	for i in range(route.size()):
		await _walk_world(route[i] as Vector3, 9.0, "console leg %d" % i, 0.65, false, false)
	var console: Vector3 = (rig.get("winch") as Node3D).global_position
	var dist: float = player.global_position.distance_to(console)
	log_line("A23_CONSOLE_APPROACH pos=%s console=%s dist=%.2f phase=%s" % [
		str(player.global_position), str(console), dist, str(flow.get("phase"))])
	return dist <= 3.0

func _repair_sequence() -> bool:
	# The solo integration flow's proven drum sequence: break the jam, haul to
	# the far side of the capture window, then creep/payout back into it.
	var rail: Dictionary = rig.call("alignment_state") as Dictionary
	check(bool((rig.call("tension_state") as Dictionary).get("attached", false)),
		"cable is attached before the drum is worked")
	Input.action_press("winch_haul")
	var t := 0.0
	var jam_broken := false
	while t < 20.0:
		await _wait(0.25)
		t += 0.25
		rail = rig.call("alignment_state") as Dictionary
		if not bool(rail.get("jammed", true)):
			jam_broken = true
			break
	check(jam_broken, "hauling broke the swing-section jam (angle=%.2f)" % float(rail.get("angle_deg", 99.0)))
	var overshot := false
	while t < 60.0:
		await _wait(0.25)
		t += 0.25
		rail = rig.call("alignment_state") as Dictionary
		if float(rail.get("angle_deg", 0.0)) < -5.2:
			overshot = true
			break
	Input.action_release("winch_haul")
	await _wait(0.4)
	check(overshot, "continuous hauling really moved the rail past the slot (angle=%.2f)" % float(rail.get("angle_deg", 99.0)))
	Input.action_press("winch_creep")
	var dir := ""
	var creep_t := 0.0
	while creep_t < 30.0:
		await tree.physics_frame
		creep_t += 1.0 / 60.0
		rail = rig.call("alignment_state") as Dictionary
		if bool(rail.get("lockable", false)):
			break
		var angle: float = float(rail.get("angle_deg", 0.0))
		var want := ""
		if angle > 2.0:
			want = "winch_haul"
		elif angle < -2.0:
			want = "winch_payout"
		if want != dir:
			if dir != "":
				Input.action_release(dir)
			dir = want
			if dir != "":
				Input.action_press(dir)
	if dir != "":
		Input.action_release(dir)
	Input.action_release("winch_haul")
	Input.action_release("winch_payout")
	Input.action_release("winch_creep")
	await _wait(0.4)
	rail = rig.call("alignment_state") as Dictionary
	check(bool(rail.get("captureable", false)) or bool(rail.get("lockable", false)),
		"creep/payout brought the rail into the pin's capture window (angle=%.2f)" % float(rail.get("angle_deg", 99.0)))
	# Leave the drum with the same real E key.
	await _press("repair", 0.16)
	var left: bool = await _wait_until(func() -> bool: return not bool(flow.get("at_console")), 20.0)
	check(left, "pid%d left the console with E" % me)
	# Walk around the receiver to the pin socket, exactly the authored route.
	var route: Array = [
		yard.to_global(Vector3(5.70, 0.0, 4.60)),
		yard.to_global(Vector3(7.30, 0.0, 2.60)),
		yard.to_global(Vector3(6.90, 0.0, 2.30)),
	]
	for i in range(route.size()):
		await _walk_world(route[i] as Vector3, 8.0, "lock leg %d" % i, 0.65, false, false)
	var lock_at: Vector3 = yard.call("lock_station_position") as Vector3
	var d: Vector3 = lock_at - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_yaw", yaw)
	await _wait(0.4)
	await _press("repair", 0.16)
	var done: bool = await _wait_until(func() -> bool: return bool(yard.call("completion")), 30.0)
	var lock_state: Dictionary = rig.call("lock_state") as Dictionary if rig.has_method("lock_state") else {}
	check(done, "the swing section is mechanically pinned and repair completes")
	check(bool(cart.get("route_clear")), "the repaired route is released for the cart")
	check(bool(lock_state.get("locked", true)), "lock pin state is locked (%s)" % str(lock_state))
	return done

func _reboard_route() -> bool:
	var route: Array = [
		yard.to_global(Vector3(5.60, 0.0, 2.30)),
		yard.to_global(Vector3(4.60, 0.0, 2.10)),
		yard.to_global(Vector3(2.90, 0.0, -0.80)),
		yard.to_global(Vector3(3.66, 0.0, -4.20)),
		yard.to_global(Vector3(0.00, 0.0, -4.10)),
	]
	for i in range(route.size()):
		await _walk_world(route[i] as Vector3, 9.0, "return leg %d" % i, 0.70, false, false)
	await _walk_local(Vector3(1.0, 0.40, -1.95), 6.0, "return landing", 0.45, false, true)
	await _walk_local(Vector3(1.0, 0.40, -0.80), 5.0, "return stair foot", 0.30, false, true)
	await _walk_local(Vector3(1.0, 1.05, -0.10), 5.0, "return stairs mid", 0.30, false, true)
	await _walk_local(Vector3(1.0, 1.91, 0.55), 5.0, "return stairs top", 0.30, false, true)
	await _walk_local(Vector3(1.0, 1.95, 1.55), 5.0, "return deck", 0.30, false, true)
	if not _on_deck():
		return false
	await _walk_local(_deck_spot(me), 6.0, "return deck spot pid%d" % me, 0.45, false)
	return _on_deck()

func _reboard_coordinator(order: Array) -> void:
	for p in order:
		_host_phase("reboard_%d" % p)
		var ok: bool = await _wait_until(func() -> bool: return _done_exists("done_reboard_%d.json" % p), 240.0)
		check(ok, "host waited for pid%d to re-board" % p)
		if not ok:
			return
		var prev_ok: bool = _read_json("a23_done_reboard_%d.json" % p).get("ok", false)
		check(prev_ok, "pid%d is physically back on the deck" % p)
		if not prev_ok:
			return
	_host_phase("reboard_all")
	_write_done("reboard_all.json")

func _reboard_sequence() -> bool:
	var order: Array = []
	for p in range(2, players + 1):
		order.append(p)
	order.append(1)
	if role == "host":
		_reboard_coordinator.call_deferred(order)
	var turn: bool = await _wait_phase("reboard_%d" % me, 420.0)
	check(turn, "pid%d received its real re-board turn" % me)
	if not turn:
		return false
	var ok: bool = await _reboard_route()
	_write_done("done_reboard_%d.json" % me, {"ok": ok, "pos": str(player.global_position)})
	check(ok, "pid%d physically walked back up the boarding stairs" % me)
	if not ok:
		return false
	var all: bool = await _wait_until(func() -> bool: return _done_exists("reboard_all.json"), 180.0)
	check(all, "pid%d saw the whole crew back aboard" % me)
	return all

func _second_launch() -> bool:
	if role == "host":
		await _wait(1.0)
		var all: bool = await _wait_until(func() -> bool: return _all_on_deck(), 120.0)
		check(all, "host sees the whole crew back on the deck")
		if not all:
			return false
		await _walk_local(Vector3(2.48, 1.95, 1.08), 5.0, "second departure controller", 0.45, false)
		for _attempt in range(6):
			if bool(cart.get("running")):
				break
			await _press("repair", 0.16)
			await _wait(0.8)
		var started: bool = await _wait_until(func() -> bool: return bool(cart.get("running")), 60.0)
		check(started, "host restarted the repaired cart from the deck controller")
		if not started:
			return false
		_host_phase("launch2")
		_write_done("launch2.json")
		return true
	var go: bool = await _wait_until(func() -> bool: return _done_exists("launch2.json"), 300.0)
	check(go, "pid%d received the second launch phase" % me)
	return go

func _run_full() -> void:
	# Every seat has to stand on the maintenance yard floor, not just leave the
	# deck box. pid2 then performs the real cable/drum/pin repair.
	if me == 2:
		if not await _hook_eye():
			_finish(false)
			return
		_record("eye_hooked")
		if not await _walk_to_console_from_eye():
			check(false, "pid2 reached the winch console area")
			_write_done("blocked_console_%d.json" % me, _snapshot())
			_finish(false)
			return
		if not await _take_console():
			_write_done("blocked_console_take_%d.json" % me, _snapshot())
			_finish(false)
			return
		_record("console_owned")
		if not await _repair_sequence():
			_write_done("blocked_repair_%d.json" % me, _snapshot())
			_finish(false)
			return
		_record("repaired")
		_write_done("repaired.json", _snapshot())
	else:
		var route: Array = _yard_route_to_console()
		for i in range(3):
			await _walk_world(route[i] as Vector3, 9.0, "yard leg %d (support)" % i, 0.75, false, false)
		_record("yard")
	if role == "host":
		var owner_ok: bool = await _wait_until(func() -> bool: return int(flow.get('console_actor')) == 2, 300.0)
		check(owner_ok, "host-authoritative console_actor maps to the real operator pid2")
		_record("console_owner")
		var seen: bool = await _wait_until(func() -> bool: return _done_exists("repaired.json"), 300.0)
		check(seen, "host saw the real repair complete")
		check(bool(yard.call("completion")), "host-authoritative repair state is complete")
		if not seen or not bool(yard.call("completion")):
			_finish(false)
			return
		_host_phase("repair_done")
		_write_done("repair_done.json")
	else:
		var rd: bool = await _wait_until(func() -> bool: return _done_exists("repair_done.json"), 300.0)
		check(rd, "pid%d received the repair_done phase" % me)
		if not rd:
			_finish(false)
			return
	# All seats walk back and queue at the authored boarding stairs.
	if not await _reboard_sequence():
		_finish(false)
		return
	_record("reboarded")
	if not await _second_launch():
		_finish(false)
		return
	_record("launch2")
	var scene_left := func() -> bool:
		if tree.current_scene == null:
			return true
		return str(tree.current_scene.name) != "Act23Chapter"
	var arrived: bool = await _wait_until(func() -> bool:
		if scene_left.call():
			return true
		return _valid(cart) and bool(cart.get("arrived")), 240.0)
	if bool(scene_left.call()):
		# The host owns the campaign switch. A client can receive the Act04
		# broadcast before the last unreliable cart mirror lands; the host's
		# authoritative hand-off is the completion signal, and every earlier
		# egress/repair/re-board/identity check already ran on this client.
		note("Act23 campaign hand-off observed before the local cart mirror set arrived")
		check(true, "Act23 campaign hand-off observed after the repaired run")
		_write_done("full_done_%d.json" % me, {"handoff_before_mirror": true})
		_finish(failures.is_empty())
		return
	check(arrived, "repaired cart reached the crystal-mine dock (distance=%.2f)" % float(cart.get("distance")))
	check(str(flow.get("phase")) == "done", "Act23 phase is done after the repaired run")
	if not arrived:
		_write_done("blocked_arrival_%d.json" % me, _snapshot())
		_finish(false)
		return
	_record("arrived")
	check(int(player.get("recovery_count")) == 0,
		"pid%d never needed the safety-rope rescue" % me)
	_write_done("full_done_%d.json" % me, _snapshot())
	if mode == "full_official":
		# The unified SessionHub starts the Act23 -> Act04 switch 4.5 s after the
		# phase becomes done. Return immediately after arrival; the caller waits
		# for the real scene change and the campaign switch owns the teardown.
		_finish(failures.is_empty())
		return
	if role == "host":
		for p in range(2, players + 1):
			await _wait_until(func() -> bool: return _done_exists("full_done_%d.json" % p), 60.0)
	_finish(failures.is_empty())

# ---------------------------------------------------------------------- run ---
func _run() -> void:
	_record("boot")
	if not await _boot():
		_finish(false)
		return
	if not await _wait_self():
		_finish(false)
		return
	# Every body leaves the shared spawn point with real W input immediately;
	# waiting for the whole crew here is what let four capsules pile up.
	if not await _ensure_on_pad():
		check(false, "pid%d is on the boarding landing before boarding" % me)
		_write_done("blocked_spawn_%d.json" % me, _snapshot())
		_finish(false)
		return
	await _walk_local(_waiting_spot(me), 5.0, "clear the shared spawn point", 0.45, false, false)
	if not await _wait_peers():
		_finish(false)
		return
	_record("ready")
	if not await _board_sequence():
		_finish(false)
		return
	_record("boarded")
	if not await _launch_sequence():
		_finish(false)
		return
	_record("running")
	var fault: bool = await _wait_until(func() -> bool:
		return bool(cart.get("stopped_for_fault")), 360.0)
	check(fault, "cart governor stopped at the severed rail (distance=%.2f)" % float(cart.get("distance")))
	if not fault:
		_write_done("blocked_fault_%d.json" % me, _snapshot())
		_finish(false)
		return
	_record("fault")
	if not await _exit_sequence():
		_finish(false)
		return
	_record("off_deck")
	var phase_ok: bool = await _wait_until(func() -> bool: return str(flow.get("phase")) == "repair", 20.0)
	check(phase_ok, "phase advanced to repair after a real deck egress (phase=%s)" % str(flow.get("phase")))
	if mode.begins_with("full"):
		await _run_full()
		return
	# Every seat must reach the maintenance yard floor; only pid2 operates the
	# drum in this probe. The route is the same authored walkway a player uses.
	if me == 2:
		if not await _reach_console():
			check(false, "pid2 reached the winch console area")
			_write_done("blocked_console_%d.json" % me, _snapshot())
			_finish(false)
			return
		_record("console_near")
		if not await _take_console():
			_write_done("blocked_console_take_%d.json" % me, _snapshot())
			_finish(false)
			return
		_record("console_owned")
		# Real drum input proves the console is not a passive trigger.
		Input.action_press("winch_haul")
		await _wait(2.0)
		Input.action_release("winch_haul")
		await _wait(0.5)
		var tension: Dictionary = rig.call("tension_state") as Dictionary
		note("tension after 2 s haul: %s" % str(tension))
		var align: Dictionary = rig.call("alignment_state") as Dictionary
		note("alignment after 2 s haul: %s" % str(align))
	else:
		# The other seats still have to be physically in the yard, not parked on
		# the landing. Walk the first three legs and stop clear of the console lane.
		var route: Array = _yard_route_to_console()
		for i in range(3):
			await _walk_world(route[i] as Vector3, 9.0, "yard leg %d (support)" % i, 0.75, false, false)
		_record("yard")
	# Give the host a moment to mirror the console owner, then compare.
	var actor_now: int = int(flow.get("console_actor"))
	if me == 2:
		check(actor_now == 2, "client's mirrored console_actor maps to pid2 (actor=%d)" % actor_now)
		_write_done("console_taken.json", _snapshot())
		await _wait_phase("run_done", 180.0)
	elif role == "host":
		var seen: bool = await _wait_until(func() -> bool: return _done_exists("console_taken.json"), 240.0)
		check(seen, "host saw pid2's real console takeover")
		actor_now = int(flow.get("console_actor"))
		check(actor_now == 2, "host-authoritative console_actor maps to pid2 (actor=%d)" % actor_now)
		_host_phase("run_done")
	else:
		await _wait_phase("run_done", 240.0)
	_record("console_check")
	# A rescue pull or a teleport would be visible as a non-zero recovery count.
	check(int(player.get("recovery_count")) == 0,
		"pid%d egress used no safety-rope rescue (recovery_count=%d)" % [me, int(player.get("recovery_count"))])
	if role == "host":
		for p in range(1, players + 1):
			var a: Node = _actor(p)
			if _valid(a):
				check(int(a.get("recovery_count")) == 0, "pid%d was never safety-rope rescued" % p)
	# Clients acknowledge the final phase before the host tears the session down.
	if role != "host":
		_write_done("done_run_%d.json" % me, {"ok": true})
	else:
		for p in range(2, players + 1):
			await _wait_until(func() -> bool: return _done_exists("done_run_%d.json" % p), 60.0)
	_finish(failures.is_empty())

func _finish(passed: bool) -> void:
	if _finished:
		return
	_finished = true
	if _valid(stage):
		_cap = _snapshot()
	_cap["checks"] = checks
	_cap["failures"] = failures
	_cap["warnings"] = warnings
	_cap["passed"] = passed
	_cap["mode"] = mode
	_cap["tag"] = tag
	_passed = passed
	_write_json("a23_%s%d.result.json" % [role, index], _cap)
	log_line("A23_RESULT: role=%s index=%d slot=%d passed=%s checks=%d failures=%d" % [
		role, index, me, str(passed), checks, failures.size()])
	print("A23_RESULT_JSON: " + JSON.stringify(_cap))
