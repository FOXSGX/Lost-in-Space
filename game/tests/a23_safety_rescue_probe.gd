extends SceneTree

# =============================================================================
# a23_safety_rescue_probe.gd · ACT23 安全制动 / 玩家救援 专项验收探针
#
# 真实输入（WASD / E / B / R / W / Space）、真实物理、真实 ENet（每个进程一条）。
# 判定只读取生产状态：global_position、cart-local、contains_point、is_on_floor、
# cart.running / speed / brake_reason / stopped_for_fault、rig 的 holder、20 Hz
# 快照镜像。探针**从不**写 running / brake_reason / on_deck / grounded / locked /
# 救援计数 / 矿车距离。
#
# 启动（每个进程一条，见 tools/run_probe.ps1）：
#   Godot --headless --path <project> res://act23/act23_entry.tscn \
#     -s res://tests/a23_safety_rescue_probe.gd -- \
#     --port 26600 --coop-host --role=host --seat=1 --players=3 --scenario=safety --out=<dir>
#
# 场景：
#   safety  正常行驶不误制动 → 船员离车 → 保护制动 → 救援回甲板 → 重新发车
#           → 断轨治理停车 → 故障未解除时发车被拒 → 完整维修/锁定 → 全员登车
#           → 重新发车 → 抵达终点
#   rescue  发车行驶 → 制动 → 全员真实下车 → 单人救援 → 多人同时救援
#           → 落点间隔/可移动 → 重新登车交互 → 重复/过期救援请求 → 身份一致
# =============================================================================

const DECK_TOP: float = 1.9546444
const SAFETY_REASON: String = "driver_left_deck"

var role: String = "host"
var scenario: String = "safety"
var players: int = 2
var port: int = 26600
var address: String = "127.0.0.1"
var out_dir: String = "user://a23_sr"
var seat: int = 1
var me: int = 1

var stage: Node3D
var cart: AnimatableBody3D
var player: CharacterBody3D
var flow: Node
var coop: Node
var yard: Node3D

var clock: int = 0
var checks: Array = []
var failures: int = 0
var samples: Array = []

# --- lifecycle --------------------------------------------------------------
func _initialize() -> void:
	run.call_deferred()

func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--players="): players = int(arg.trim_prefix("--players="))
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--address="): address = arg.trim_prefix("--address=")
		elif arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--seat="): seat = int(arg.trim_prefix("--seat="))

func tps() -> int:
	return int(Engine.physics_ticks_per_second)

func seconds(value: float) -> int:
	return maxi(1, int(round(value * float(tps()))))

func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame
		clock += 1

func wait_real(value: float) -> void:
	await frames(seconds(value))

# --- reporting --------------------------------------------------------------
func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details, "t": clock,
		"role": role, "seat": me})
	if not ok: failures += 1
	print("SR_", "OK   " if ok else "FAIL ", "[", role, "/", scenario, "/", str(me), "] ",
		label, " ", JSON.stringify(details))

func note(label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": true, "label": label, "details": details, "t": clock,
		"role": role, "seat": me, "note": true})
	print("SR_NOTE [", role, "/", scenario, "/", str(me), "] ", label, " ", JSON.stringify(details))

func wait_until(predicate: Callable, limit: int, label: String = "") -> bool:
	for i: int in range(limit):
		await physics_frame
		clock += 1
		if i % 300 == 0:
			print("SR_HB role=", role, " seat=", str(me), " wait=", label,
				" frame=", i, "/", limit)
		if bool(predicate.call()): return true
	return false

func wait_sec(value: float, predicate: Callable, label: String = "") -> bool:
	return await wait_until(predicate, seconds(value), label)

# --- input ------------------------------------------------------------------
func stop_move() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
	Input.action_release("sprint")

func press(action: String, hold: int = 8, after: int = 20) -> void:
	Input.action_press(action)
	await frames(hold)
	Input.action_release(action)
	await frames(after)

func face(target: Vector3) -> void:
	if player == null or not is_instance_valid(player): return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_yaw", yaw)

# Real movement input only: face the target every frame and walk forward.
func walk_to(target: Vector3, budget: float, label: String = "", arrive: float = 0.55,
		check_y: bool = false) -> bool:
	if player == null or not is_instance_valid(player): return false
	var start: Vector3 = player.global_position
	var climbing: bool = target.y > start.y + 0.30
	var descending: bool = target.y < start.y - 0.80
	var last: Vector3 = start
	var stuck: float = 0.0
	var elapsed: float = 0.0
	face(target)
	Input.action_press("move_up")
	while elapsed < budget:
		await physics_frame
		clock += 1
		elapsed += 1.0 / float(tps())
		if player == null or not is_instance_valid(player): break
		face(target)
		var pos: Vector3 = player.global_position
		var flat: float = Vector2(pos.x - target.x, pos.z - target.z).length()
		var dy: float = absf(pos.y - target.y)
		if flat < arrive and (not check_y or ((not climbing or dy < 0.30) and
				(not descending or dy < 0.70))):
			break
		if pos.distance_to(last) < 0.008:
			stuck += 1.0 / float(tps())
		else:
			stuck = 0.0
			last = pos
		if stuck > 0.90:
			print("SR_WALK_STUCK ", label, " target=", target, " pos=", pos,
				" flat=", flat, " dy=", dy)
			break
	Input.action_release("move_up")
	await frames(2)
	if player == null or not is_instance_valid(player): return false
	var end: Vector3 = player.global_position
	var end_flat: float = Vector2(end.x - target.x, end.z - target.z).length()
	print("SR_WALK ", label, " target=", target, " pos=", end, " flat=", end_flat,
		" y=", end.y, " moved=", end.distance_to(start))
	return end_flat <= arrive * 1.6

# Same real-input walk, but the target is a CART-LOCAL point re-projected every
# frame. A deck lane that is sampled once is already 1.5 m behind the rider one
# second later at cruise speed, which is how the first attempt at leaving a
# moving deck failed (the seat stayed on the deck and no safety brake could be
# observed). HARNESS FIX, no gameplay state is written here.
func walk_cart(local_at: Vector3, budget: float, label: String = "", arrive: float = 0.55,
		check_y: bool = false) -> bool:
	if player == null or not is_instance_valid(player): return false
	var start: Vector3 = player.global_position
	var start_world: Vector3 = cart.to_global(local_at)
	var climbing: bool = start_world.y > start.y + 0.30
	var descending: bool = start_world.y < start.y - 0.80
	var last: Vector3 = start
	var stuck: float = 0.0
	var elapsed: float = 0.0
	Input.action_press("move_up")
	var end: Vector3 = start
	while elapsed < budget:
		var target: Vector3 = cart.to_global(local_at)
		face(target)
		await physics_frame
		clock += 1
		elapsed += 1.0 / float(tps())
		if player == null or not is_instance_valid(player): break
		target = cart.to_global(local_at)
		var pos: Vector3 = player.global_position
		var flat: float = Vector2(pos.x - target.x, pos.z - target.z).length()
		var dy: float = absf(pos.y - target.y)
		if flat < arrive and (not check_y or ((not climbing or dy < 0.30) and
				(not descending or dy < 0.70))):
			break
		if pos.distance_to(last) < 0.008:
			stuck += 1.0 / float(tps())
		else:
			stuck = 0.0
			last = pos
		if stuck > 0.90:
			print("SR_WALK_CART_STUCK ", label, " local=", local_at, " pos=", pos,
				" flat=", flat, " dy=", dy)
			break
		end = pos
	Input.action_release("move_up")
	await frames(2)
	if player == null or not is_instance_valid(player): return false
	end = player.global_position
	var end_local: Vector3 = cart.to_local(end)
	var end_flat: float = Vector2(end_local.x - local_at.x, end_local.z - local_at.z).length()
	print("SR_WALK_CART ", label, " local=", local_at, " end_local=", end_local,
		" flat=", end_flat, " y=", end.y, " moved=", end.distance_to(start))
	return end_flat <= arrive * 1.6

# --- world reads ------------------------------------------------------------
func cart_global(local_at: Vector3) -> Vector3:
	return cart.to_global(local_at)

func yard_at(local_at: Vector3) -> Vector3:
	return yard.to_global(local_at)

func actor(slot: int) -> CharacterBody3D:
	var actors: Dictionary = stage.get("actors") as Dictionary
	if not actors.has(slot): return null
	return actors[slot] as CharacterBody3D

func on_deck() -> bool:
	if cart == null or player == null: return false
	return bool(cart.call("contains_point", player.global_position))

func actor_on_deck(who: Variant) -> bool:
	if cart == null: return false
	var body: CharacterBody3D = who as CharacterBody3D
	if body == null or not is_instance_valid(body) or not body.is_inside_tree(): return false
	return bool(cart.call("contains_point", body.global_position))

func actor_cleared(who: Variant) -> bool:
	var body: CharacterBody3D = who as CharacterBody3D
	if body == null or not is_instance_valid(body) or not body.is_inside_tree(): return false
	var at: Vector3 = body.global_position
	return (not bool(cart.call("contains_point", at))) and at.y < 0.60

func all_on_deck() -> bool:
	var actors: Dictionary = stage.get("actors") as Dictionary
	var count: int = 0
	for slot: int in actors:
		if actor_on_deck(actors[slot]): count += 1
	return count >= players

func rig_node() -> Node:
	if yard == null or not is_instance_valid(yard): return null
	return yard.get("rig") as Node

func alignment() -> Dictionary:
	var rig: Node = rig_node()
	if rig == null: return {}
	return rig.call("alignment_state") as Dictionary

func complete() -> bool:
	if yard == null or not is_instance_valid(yard): return false
	return bool(yard.call("completion"))

func find_anchor(anchor_id: String) -> Node3D:
	for node: Node in get_nodes_in_group("winch_anchor"):
		var anchor: Node3D = node as Node3D
		if anchor != null and is_instance_valid(anchor) and str(anchor.get("anchor_id")) == anchor_id:
			return anchor
	return null

func workstation(kind: String) -> Vector3:
	if yard == null: return Vector3.ZERO
	var rows: Array = yard.call("workstations") as Array
	for row: Variant in rows:
		var entry: Dictionary = row as Dictionary
		if str(entry.get("kind", "")) == kind:
			return entry.get("position") as Vector3
	return Vector3.ZERO

func near_kind() -> String:
	var near: Variant = flow.get("near")
	if near is Dictionary:
		return str((near as Dictionary).get("kind", ""))
	return ""

func station_holder(kind: String) -> int:
	var rig: Node = rig_node()
	if rig == null: return 0
	return int(rig.get("%s_holder" % kind))

func take_station(kind: String, attempts: int = 4) -> bool:
	var offered: bool = await wait_sec(40.0, func() -> bool: return near_kind() == kind, "offer_" + kind)
	print("SR_STATION ", kind, " offered=", offered, " near=", near_kind())
	for attempt: int in range(attempts):
		await press("repair")
		var took: bool = await wait_sec(5.0,
			func() -> bool: return station_holder(kind) == me, "hold_" + kind)
		if took: return true
		print("SR_STATION_RETRY ", kind, " ", attempt, " holder=", station_holder(kind),
			" near=", near_kind())
	return station_holder(kind) == me

func actor_row(slot: int) -> Dictionary:
	var who: CharacterBody3D = actor(slot)
	if who == null or not is_instance_valid(who):
		return {"slot": slot, "present": false}
	var local_at: Vector3 = cart.to_local(who.global_position)
	return {
		"slot": slot, "present": true, "peer_id": int(who.get("peer_id")),
		"is_local": who == player,
		"pos": [snappedf(who.global_position.x, 0.001), snappedf(who.global_position.y, 0.001),
			snappedf(who.global_position.z, 0.001)],
		"cart_local": [snappedf(local_at.x, 0.001), snappedf(local_at.y, 0.001),
			snappedf(local_at.z, 0.001)],
		"on_floor": bool(who.call("is_on_floor")) if who == player else false,
		"contains_point": bool(cart.call("contains_point", who.global_position)),
		"grip_id": int(who.get("grip_id")),
		"interaction_locked": bool(who.get("interaction_locked")),
		"input_enabled": bool(who.get("input_enabled")),
		"recovery_count": int(who.get("recovery_count")),
		"velocity": [snappedf(who.velocity.x, 0.01), snappedf(who.velocity.y, 0.01),
			snappedf(who.velocity.z, 0.01)],
	}

func all_rows() -> Array:
	var out: Array = []
	var actors: Dictionary = stage.get("actors") as Dictionary
	var keys: Array = actors.keys()
	keys.sort()
	for slot: int in keys:
		out.append(actor_row(slot))
	return out

func cart_row() -> Dictionary:
	return {
		"distance": snappedf(float(cart.get("distance")), 0.001),
		"speed": snappedf(float(cart.get("speed")), 0.001),
		"mirror_speed": snappedf(float(cart.get("mirror_speed")), 0.001),
		"target_distance": snappedf(float(cart.get("target_distance")), 0.001),
		"running": bool(cart.get("running")),
		"arrived": bool(cart.get("arrived")),
		"route_clear": bool(cart.get("route_clear")),
		"stopped_for_fault": bool(cart.get("stopped_for_fault")),
		"brake_reason": str(cart.get("brake_reason")),
		"state": str(cart.get("state")),
		"revision": int(cart.get("revision")),
		"network_client": bool(cart.get("network_client")),
	}

func safety_row() -> Dictionary:
	var count: int = -1
	var triggered: bool = false
	var riders: Dictionary = {}
	for prop: Dictionary in stage.get_property_list():
		var name: String = str(prop["name"])
		if name == "_safety_brake_count": count = int(stage.get("_safety_brake_count"))
		elif name == "_safety_triggered": triggered = bool(stage.get("_safety_triggered"))
		elif name == "_safety_riders": riders = stage.get("_safety_riders") as Dictionary
	return {"brake_count": count, "triggered": triggered, "riders": riders.keys()}

func rig_row() -> Dictionary:
	var rig: Node = rig_node()
	if rig == null: return {}
	return {"guide_holder": int(rig.get("guide_holder")),
		"bracket_holder": int(rig.get("bracket_holder")),
		"completed": bool(rig.get("completed"))}

func net_row() -> Dictionary:
	if coop == null: return {}
	return {"mode": str(coop.get("mode")), "local_slot": int(coop.get("local_slot")),
		"peers": get_multiplayer().get_peers().size(),
		"slots": (coop.get("slots") as Dictionary).keys(),
		"sent": int(coop.get("snapshots_sent")), "recv": int(coop.get("snapshots_received")),
		"rejected_poses": int(coop.get("rejected_poses")),
		"rejected_actions": int(coop.get("rejected_actions"))}

func snapshot() -> Dictionary:
	return {"role": role, "seat": me, "scenario": scenario, "clock": clock,
		"players": players, "cart": cart_row(), "actors": all_rows(),
		"rig": rig_row(), "safety": safety_row(), "net": net_row(),
		"flow": {"phase": str(flow.get("phase")),
			"console_actor": int(flow.get("console_actor")),
			"at_console": bool(flow.get("at_console"))},
		"feedback": str(stage.get("feedback"))}

func sample(tag: String) -> void:
	samples.append({"t": clock, "tag": tag, "state": snapshot()})

# --- seat barrier (files carry only "whose turn is it", never world state) ---
func seat_file(pid: int) -> String:
	return out_dir.path_join("seat_%d.json" % pid)

func seat_write(step: String, extra: Dictionary = {}) -> void:
	if out_dir == "": return
	var previous: Dictionary = seat_doc(me)
	var history: Array = previous.get("steps", []) as Array
	if not history.has(step): history.append(step)
	var doc: Dictionary = {"seat": me, "step": step, "steps": history, "t": clock}
	for key: Variant in extra.keys():
		doc[key] = extra[key]
	var file: FileAccess = FileAccess.open(seat_file(me), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(doc))
		file.close()

func seat_doc(pid: int) -> Dictionary:
	var file: FileAccess = FileAccess.open(seat_file(pid), FileAccess.READ)
	if file == null: return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}

func seat_step(pid: int) -> String:
	return str(seat_doc(pid).get("step", ""))

# Sticky: a seat that has already moved on to a later checkpoint still counts
# as having reached this one. Without this, a fast peer overwrote the marker
# before a slow peer read it and the barrier timed out on a checkpoint that had
# really been reached.
func seat_has(pid: int, step: String) -> bool:
	var doc: Dictionary = seat_doc(pid)
	if doc.is_empty(): return false
	if str(doc.get("step", "")) == step: return true
	var history: Array = doc.get("steps", []) as Array
	return history.has(step)

func seat_wait(pid: int, step: String, budget: float) -> bool:
	return await wait_sec(budget, func() -> bool: return seat_has(pid, step),
		"seat%d:%s" % [pid, step])

# --- boarding / leaving the deck (real W input only) ------------------------
func board_deck() -> bool:
	if cart == null: return false
	await walk_cart(Vector3(1.0, 0.40, -2.0), 6.0, "boarding landing", 0.45, true)
	for attempt: int in range(4):
		if on_deck(): return true
		await walk_cart(Vector3(1.0, 0.40, -0.80), 3.0, "stair foot %d" % attempt, 0.22, true)
		await walk_cart(Vector3(1.0, 1.05, -0.10), 3.0, "stairs mid %d" % attempt, 0.22, true)
		await walk_cart(Vector3(1.0, 1.91, 0.55), 3.0, "stairs top %d" % attempt, 0.20, true)
		await walk_cart(Vector3(1.0, 1.95, 1.55), 3.0, "deck lane %d" % attempt, 0.20, true)
		if on_deck(): return true
		await walk_cart(Vector3(1.0, 0.40, -1.10), 3.0, "reset stairs %d" % attempt, 0.30, true)
	return on_deck()

func exit_deck() -> bool:
	await walk_cart(Vector3(1.0, 1.95, 2.60), 6.0, "deck center", 0.30, true)
	await walk_cart(Vector3(1.0, 1.95, 1.35), 5.0, "gate lane", 0.10, true)
	await walk_cart(Vector3(1.0, 0.20, -0.60), 5.0, "through the boarding gate", 0.30, true)
	await walk_cart(Vector3(0.50, 0.0, -2.40), 4.0, "south apron", 0.60, true)
	await wait_real(0.4)
	if player == null or not is_instance_valid(player): return false
	var pos: Vector3 = player.global_position
	var grounded: bool = bool(player.call("is_on_floor"))
	var deck: bool = on_deck()
	print("SR_OFF_DECK pos=", pos, " grounded=", grounded, " on_deck=", deck)
	return (not deck) and pos.y < 0.60 and grounded

func hold_spot(which: int) -> Vector3:
	match which:
		1: return Vector3(2.48, 1.95, 1.08)
		2: return Vector3(-0.5, 1.95, 2.25)
		3: return Vector3(1.9, 1.95, 2.25)
		_: return Vector3(-0.5, 1.95, 3.05)

func start_cart_from_deck(tries: int = 3) -> bool:
	await walk_to(cart_global(Vector3(2.48, 1.95, 1.08)), 5.0, "brake controller", 0.45, true)
	for attempt: int in range(tries):
		if bool(cart.get("running")): return true
		await press("repair")
		await wait_real(0.8)
	return bool(cart.get("running"))

# --- repair (production order, copied from the accepted repair harness) -----
func return_to_landing() -> void:
	var local_at: Vector3 = yard.to_local(player.global_position)
	if local_at.z < -1.60:
		await walk_to(yard_at(Vector3(3.60, 0.0, -3.60)), 12.0, "return: south apron", 0.70, false)
		await walk_to(yard_at(Vector3(-1.00, 0.0, -4.30)), 10.0, "return: boarding landing", 0.75, false)
		return
	await walk_to(yard_at(Vector3(5.70, 0.0, 4.60)), 18.0, "return: north of the receiver", 0.75, false)
	await walk_to(yard_at(Vector3(3.60, 0.0, 4.20)), 8.0, "return: east apron", 0.65, false)
	await walk_to(yard_at(Vector3(3.60, 0.0, -0.60)), 9.0, "return: east of the hull", 0.65, false)
	await walk_to(yard_at(Vector3(3.60, 0.0, -3.60)), 8.0, "return: south apron", 0.70, false)
	await walk_to(yard_at(Vector3(-1.00, 0.0, -4.30)), 10.0, "return: boarding landing", 0.75, false)

func egress_to_yard() -> bool:
	await exit_deck()
	if (not on_deck()) and player.global_position.y < 0.60:
		return true
	for attempt: int in range(4):
		print("SR_EGRESS_RETRY ", attempt, " pos=", player.global_position)
		await walk_cart(Vector3(1.0, 0.20, -1.40), 5.0, "yard descent retry %d" % attempt, 0.35, true)
		await walk_cart(Vector3(0.5, 0.0, -2.40), 5.0, "yard landing retry %d" % attempt, 0.45, true)
		await wait_real(0.5)
		if (not on_deck()) and player.global_position.y < 0.60:
			return true
	return (not on_deck()) and player.global_position.y < 0.60

func run_repair_role() -> void:
	var rig: Node = rig_node()
	var winch: Node3D = rig.get("winch") as Node3D if rig != null else null
	var anchor: Node3D = find_anchor("eye_far")
	check(rig != null and winch != null and anchor != null,
		"维修绞盘与前端吊耳存在", {"rig": rig != null, "winch": winch != null,
			"anchor": anchor != null})
	if rig == null or winch == null or anchor == null: return
	var lock_pos: Vector3 = yard.call("lock_station_position") as Vector3
	var guide_pos: Vector3 = workstation("guide")
	var bracket_pos: Vector3 = workstation("bracket")
	seat_write("yard")

	if me == 2:
		# the operator: hook + drum
		await walk_to(yard_at(Vector3(2.2, 0.0, -1.20)), 9.0, "yard south lane", 0.60, false)
		await walk_to(yard_at(Vector3(3.60, 0.0, -0.60)), 5.0, "east of the cut", 0.50, false)
		await walk_to(yard_at(Vector3(5.60, 0.0, -0.55)), 5.0, "front lifting eye", 0.60, false)
		face(anchor.call("attach_point") as Vector3)
		await press("repair")
		await wait_real(0.5)
		var tension0: Dictionary = rig.call("tension_state") as Dictionary
		check(bool(tension0.get("attached", false)),
			"seat2 用 E 把缆绳挂上前端吊耳", {"tension": tension0})
		if not bool(tension0.get("attached", false)):
			seat_write("hook_failed")
			return
		seat_write("hooked", {"anchor": str(tension0.get("anchor_name", ""))})
		await walk_to(yard_at(Vector3(5.60, 0.0, -1.50)), 6.0, "east staging", 0.50, false)
		await walk_to(yard_at(Vector3(5.70, 0.0, 4.60)), 9.0, "north of the receiver", 0.65, false)
		await walk_to(yard_at(Vector3(-0.60, 0.0, 3.95)), 9.0, "winch console", 0.70, false)
		face(winch.global_position)
		await press("repair")
		await wait_real(0.5)
		check(await wait_sec(40.0, func() -> bool: return bool(flow.get("at_console")),
			"console_taken"), "seat2 用 E 接管绞盘")
		check(int(flow.get("console_actor")) == me,
			"console_actor 是真实操作者",
			{"console_actor": int(flow.get("console_actor"))})
		if not bool(flow.get("at_console")) or int(flow.get("console_actor")) != me:
			seat_write("console_failed")
			return
		seat_write("console")
		var align_now: Dictionary = alignment()
		Input.action_press("winch_haul")
		var haul_t: float = 0.0
		var jam_broken: bool = false
		while haul_t < 70.0:
			await wait_real(0.1)
			haul_t += 0.1
			align_now = alignment()
			if not jam_broken and not bool(align_now.get("jammed", true)):
				jam_broken = true
				print("SR_JAM_BROKEN angle=", float(align_now.get("angle_deg", 0.0)),
					" t=", haul_t)
			if absf(float(align_now.get("angle_deg", 99.0))) <= 7.6:
				break
		Input.action_release("winch_haul")
		await wait_real(0.3)
		await press("winch_brake")
		var align1: Dictionary = alignment()
		print("SR_ALIGN_JAW ", align1, " haul=", haul_t)
		check(jam_broken, "前端吊耳把摆动轨从碎石中拉出",
			{"angle": float(align1.get("angle_deg", 0.0)), "haul_s": haul_t})
		check(absf(float(align1.get("angle_deg", 99.0))) <= 8.0,
			"绞盘把轨头带进接收架窗口",
			{"angle": float(align1.get("angle_deg", 0.0))})
		if not jam_broken or absf(float(align1.get("angle_deg", 99.0))) > 8.0:
			seat_write("jaw_failed")
			return
		seat_write("jaw_window", {"angle": float(align1.get("angle_deg", 0.0))})
		if players >= 3:
			check(await seat_wait(3, "guide_held", 220.0),
				"seat3 在最终捕获前握住导向轮")
		if players >= 4:
			check(await seat_wait(4, "bracket_folded", 220.0),
				"seat4 在最终捕获前收起安全支架")
		if not complete():
			if bool((rig.get("winch") as Node3D).get("brake")):
				await press("winch_brake")
			Input.action_press("winch_haul")
			var haul2: float = 0.0
			while haul2 < 45.0:
				await wait_real(0.1)
				haul2 += 0.1
				align_now = alignment()
				if absf(float(align_now.get("angle_deg", 99.0))) <= 3.0:
					break
				if complete(): break
			Input.action_release("winch_haul")
			await wait_real(0.3)
			await press("winch_brake")
			align_now = alignment()
			print("SR_ALIGN_CAPTURE ", align_now, " haul2=", haul2)
		seat_write("window_ready",
			{"angle": float(alignment().get("angle_deg", 0.0))})
		var pin_t: float = 0.0
		while pin_t < 240.0 and not complete():
			await wait_real(0.2)
			pin_t += 0.2
		if not complete():
			for attempt: int in range(8):
				if complete(): break
				var a_r: Dictionary = alignment()
				if bool(a_r.get("captureable", false)) or bool(a_r.get("lockable", false)):
					await wait_real(1.0)
					continue
				if bool((rig.get("winch") as Node3D).get("brake")):
					await press("winch_brake")
				var deg: float = float(a_r.get("angle_deg", 99.0))
				var key: String = "winch_haul" if deg > 0.0 else "winch_payout"
				Input.action_press(key)
				await wait_real(1.0)
				Input.action_release(key)
				await wait_real(0.4)
				print("SR_PIN_RECOVER ", attempt, " align=", alignment())
		var align_final: Dictionary = alignment()
		check(complete(), "轨道维修完成并锁定",
			{"angle": float(align_final.get("angle_deg", 0.0)),
			 "locked": bool(align_final.get("locked", false))})
		seat_write("pin_installed", {"angle": float(align_final.get("angle_deg", 0.0)),
			"locked": bool(align_final.get("locked", false))})
		if bool(flow.get("at_console")):
			await press("repair")
			await wait_real(0.3)
		check(not bool(flow.get("at_console")), "seat2 离开绞盘")
	elif me == 1:
		# the pin seat: socket + hand wheel witness
		await walk_to(yard_at(Vector3(2.2, 0.0, -1.20)), 10.0, "host yard south lane", 0.60, false)
		await walk_to(yard_at(Vector3(5.60, 0.0, -1.50)), 7.0, "host east staging", 0.60, false)
		await walk_to(yard_at(Vector3(5.70, 0.0, 4.60)), 9.0, "host north of the receiver", 0.65, false)
		await walk_to(yard_at(Vector3(7.30, 0.0, 2.60)), 5.0, "host lock approach", 0.50, false)
		await walk_to(yard_at(Vector3(6.90, 0.0, 2.30)), 4.0, "host lock socket", 0.45, false)
		face(lock_pos)
		seat_write("at_lock",
			{"lock_distance": float(player.global_position.distance_to(lock_pos))})
		if players >= 4:
			check(await seat_wait(4, "bracket_propped", 260.0),
				"seat1 在锁定座等待 seat4 撑起支架")
			check(await seat_wait(3, "guide_held", 200.0),
				"seat1 在支架拒绝检查前等 seat3 握住导向轮")
			await press("repair")
			var ref_feedback: String = ""
			var feedback_wait: float = 0.0
			while feedback_wait < 3.0:
				ref_feedback = str(stage.get("feedback"))
				if ref_feedback.find("支架") >= 0: break
				await wait_real(0.2)
				feedback_wait += 0.2
			var ref_align: Dictionary = alignment()
			print("SR_PIN_REFUSED feedback=", ref_feedback, " bracket=",
				bool(ref_align.get("bracket", false)), " completed=", complete())
			check(not complete(), "支架撑住时锁定销无法插入")
			check(ref_feedback.find("支架") >= 0, "拒绝信息点名安全支架",
				{"feedback": ref_feedback})
			check(str(flow.get("phase")) == "repair",
				"支架撑住时关卡仍在维修阶段", {"phase": str(flow.get("phase"))})
			check(not bool(cart.get("route_clear")), "支架撑住时线路仍未放行")
			seat_write("prop_refusal_checked")
		var presses: int = 0
		var press_t: float = 0.0
		var saw_guided: bool = false
		while press_t < 300.0 and not complete():
			await wait_real(0.2)
			press_t += 0.2
			var a_now: Dictionary = alignment()
			if bool(a_now.get("guiding", false)): saw_guided = true
			if near_kind() != "lock": continue
			if not bool(a_now.get("captureable", false)) and not bool(a_now.get("lockable", false)):
				continue
			await press("repair")
			presses += 1
			await wait_real(0.3)
			var after_press: Dictionary = alignment()
			if bool(after_press.get("guiding", false)): saw_guided = true
			if complete(): break
			if presses >= 60: break
		var a_done: Dictionary = alignment()
		await wait_real(0.6)
		check(presses >= 1, "seat1 在锁定座按了 E", {"presses": presses})
		check(complete(), "seat1 插入锁定销完成锁定",
			{"completed": complete(), "angle": float(a_done.get("angle_deg", 0.0))})
		check(bool(a_done.get("locked", false)), "摆动轨报告 locked=true")
		check(absf(float(a_done.get("angle_deg", 0.0))) < 0.05,
			"锁定后轨头精确回到线路", {"angle": float(a_done.get("angle_deg", 0.0))})
		check(bool(cart.get("route_clear")), "锁定放行矿车线路（route_clear）")
		check(str(flow.get("phase")) == "locked" or str(flow.get("phase")) == "reride",
			"主机阶段已越过维修", {"phase": str(flow.get("phase"))})
		seat_write("pin_done", {"presses": presses, "saw_guided": saw_guided})
	elif me == 3:
		check(await seat_wait(2, "jaw_window", 300.0),
			"seat3 看到轨头进入接收架窗口")
		await walk_to(yard_at(Vector3(0.0, 0.0, -3.60)), 12.0, "seat3 south apron", 0.60, false)
		await walk_to(yard_at(Vector3(5.55, 0.0, -3.60)), 8.0, "seat3 south of the wheel", 0.60, false)
		await walk_to(yard_at(Vector3(5.55, 0.0, -1.30)), 5.0, "seat3 guide wheel stand", 0.50, false)
		face(guide_pos)
		var took: bool = await take_station("guide")
		check(took, "seat3 用 E 握住导向轮",
			{"holder": station_holder("guide")})
		if not took:
			seat_write("guide_failed")
			return
		seat_write("guide_held",
			{"angle": float(alignment().get("angle_deg", 0.0))})
		check(await seat_wait(2, "pin_installed", 300.0),
			"seat3 保持导向轮直到锁定销落位")
		var a_hold: Dictionary = alignment()
		await wait_real(1.2)
		check(station_holder("guide") == 0, "锁定后生产流程释放导向轮")
		check(not bool(player.get("interaction_locked")),
			"锁定后 seat3 可以自由行走")
		seat_write("guide_released",
			{"angle": float(a_hold.get("angle_deg", 0.0))})
	elif me == 4:
		check(await seat_wait(2, "jaw_window", 300.0),
			"seat4 看到轨头进入接收架窗口")
		await walk_to(yard_at(Vector3(2.2, 0.0, -1.20)), 12.0, "seat4 south lane", 0.60, false)
		await walk_to(yard_at(Vector3(2.90, 0.0, -1.30)), 5.0, "seat4 east of the prop", 0.50, false)
		await walk_to(yard_at(Vector3(1.90, 0.0, -1.30)), 4.0, "seat4 prop stand", 0.45, false)
		face(bracket_pos)
		var took: bool = await take_station("bracket")
		check(took, "seat4 用 E 撑起安全支架",
			{"holder": station_holder("bracket")})
		if not took:
			seat_write("bracket_failed")
			return
		var a_prop: Dictionary = alignment()
		check(bool(a_prop.get("bracket", false)), "轨道记录到支架已撑住")
		seat_write("bracket_propped",
			{"angle": float(a_prop.get("angle_deg", 0.0))})
		check(await seat_wait(1, "prop_refusal_checked", 200.0),
			"seat4 等锁定座确认支架拒绝锁定销")
		await press("repair")
		await wait_sec(5.0, func() -> bool: return station_holder("bracket") == 0, "fold_prop")
		var a_fold: Dictionary = alignment()
		check(station_holder("bracket") == 0, "seat4 收起安全支架")
		check(not bool(a_fold.get("bracket", false)), "轨道记录到支架已收起")
		check(not bool(player.get("interaction_locked")),
			"收起支架后 seat4 可以自由移动")
		seat_write("bracket_folded",
			{"angle": float(a_fold.get("angle_deg", 0.0))})

	if not (await wait_sec(300.0, func() -> bool: return complete(), "repair_complete")):
		seat_write("repair_timeout")
		return

# --- re-board (real stairs only) -------------------------------------------
func reboard() -> bool:
	if on_deck():
		return true
	await return_to_landing()
	await board_deck()
	if not on_deck():
		await walk_to(cart_global(Vector3(1.0, 0.40, -2.00)), 7.0, "re-board landing retry", 0.45, true)
		await walk_to(cart_global(Vector3(1.0, 1.10, -0.10)), 5.0, "re-board ramp", 0.30, true)
		await walk_to(cart_global(Vector3(1.0, 1.90, 0.90)), 5.0, "re-board ramp top", 0.30, true)
		await walk_to(cart_global(Vector3(1.0, 1.95, 1.55)), 4.0, "re-board deck lane", 0.25, true)
	await wait_real(0.5)
	return on_deck()

# =============================================================================
# SAFETY scenario
# =============================================================================
# `speed` is host-only in the production mirror (clients only carry
# mirror_speed), so the shared "the ride is under way" gate uses the two fields
# both sides publish. The host still asserts the authoritative speed itself.
func _cart_running_past_5() -> bool:
	return bool(cart.get("running")) and float(cart.get("distance")) > 5.0

func _mirror_safety_brake() -> bool:
	return not bool(cart.get("running")) and str(cart.get("brake_reason")) == SAFETY_REASON

func _cart_running_past_10() -> bool:
	return bool(cart.get("running")) and float(cart.get("distance")) > 10.0

func _cart_past_10() -> bool:
	return float(cart.get("distance")) > 10.0

func scenario_safety() -> void:
	var ready: bool = await wait_ready()
	check(ready, "S0 会话就绪", {"net": net_row(), "actors": all_rows()})
	if not ready: return
	# --- board in pid order, clear the exit gate -----------------------------
	if me > 1:
		check(await wait_sec(120.0,
			func() -> bool: return actor_on_deck(actor(me - 1)), "prev_boarded"),
			"seat%d 等 seat%d 登上甲板" % [me, me - 1])
	check(await board_deck(), "seat%d 用真实 W 输入登上甲板" % me,
		{"cart_local": player.global_position, "on_floor": bool(player.call("is_on_floor"))})
	await walk_to(cart_global(hold_spot(me)), 6.0, "hold clear of the deck exit", 0.45, true)
	seat_write("decked")
	note("登车后状态", snapshot())

	if me == 1:
		check(await wait_sec(180.0, func() -> bool: return all_on_deck(), "all_on_deck"),
			"主机看到全部 %d 人都在甲板上" % players, {"actors": all_rows()})
		check(await start_cart_from_deck(), "主机用 E 从控制器真实发车",
			{"cart": cart_row(), "feedback": str(stage.get("feedback"))})
	# --- 1) normal ride: no false safety brake -------------------------------
	var moving: bool = await wait_sec(60.0, _cart_running_past_5, "moving")
	check(moving, "矿车真实行驶（running 且 distance>5）", {"cart": cart_row()})
	if me == 1:
		check(float(cart.get("speed")) > 1.0, "S0b 主机权威速度 > 1 m/s（真实巡航）",
			{"speed": float(cart.get("speed"))})
	await wait_real(3.0)
	var ride_state: Dictionary = snapshot()
	var ride_cart: Dictionary = ride_state["cart"] as Dictionary
	check(bool(ride_cart["running"]) and str(ride_cart["brake_reason"]) == "",
		"S1 正常行驶期间没有误触发安全制动", {"cart": ride_cart,
		"safety": ride_state["safety"]})
	var all_riding: bool = true
	for row: Dictionary in ride_state["actors"] as Array:
		if not bool(row.get("contains_point", false)): all_riding = false
	check(all_riding, "S1b 正常行驶期间每位船员都在甲板上",
		{"actors": ride_state["actors"]})
	if me == 1:
		check(int((ride_state["safety"] as Dictionary)["brake_count"]) == 0,
			"S1c 主机安全制动计数仍为 0", ride_state["safety"])

	# --- 2) crew left the deck -> production safety brake --------------------
	var leaver: int = players
	var off: bool = false
	if me == leaver:
		off = await exit_deck()
	else:
		off = await wait_sec(9.0, func() -> bool: return actor_cleared(actor(leaver)), "leaver_off")
	check(off, "seat%d 在行驶中以真实 W 输入离开甲板（local_y<1.5）" % leaver,
		{"leaver": actor_row(leaver), "own_pos": player.global_position, "on_deck": on_deck()})
	if me == 1:
		var braked: bool = await wait_sec(6.0,
			func() -> bool: return not bool(cart.get("running")), "safety_brake")
		var brake_state: Dictionary = snapshot()
		var brake_cart: Dictionary = brake_state["cart"] as Dictionary
		check(braked, "S2 船员离车后生产安全制动生效（running→false）",
			{"cart": brake_cart, "safety": brake_state["safety"],
			 "feedback": brake_state["feedback"]})
		check(str(brake_cart["brake_reason"]) == SAFETY_REASON,
			"S3 制动原因 = driver_left_deck（生产保护制动规则）",
			{"brake_reason": brake_cart["brake_reason"]})
		check(int((brake_state["safety"] as Dictionary)["brake_count"]) == 1,
			"S3b 整趟只记录一次保护制动", brake_state["safety"])
		sample("safety_brake")
		# 制动后不允许任何不符合生产规则的自动重启
		await wait_real(2.0)
		var still: Dictionary = cart_row()
		check(not bool(still["running"]), "S3c 制动后矿车保持停车（没有自动重启）",
			{"cart": still})
	else:
		var mirror: bool = await wait_sec(6.0, _mirror_safety_brake, "mirror_brake")
		check(mirror, "S4 客户端镜像到主机权威的制动状态与原因",
			{"cart": cart_row(), "net": net_row()})
	# --- 3) rescue the leaver back onto the deck ----------------------------
	if me == leaver:
		var rescued: bool = false
		for attempt: int in range(6):
			if on_deck(): break
			await press("cart_recover")
			await wait_real(0.6)
			rescued = on_deck()
		check(rescued, "S5 离车船员用 R 真实请求救援并回到甲板",
			{"cart_local": cart.to_local(player.global_position), "cart": cart_row(),
			 "recovery_count": int(player.get("recovery_count"))})
		check(bool(player.call("is_on_floor")), "S5b 救援后角色真的站在甲板上",
			{"on_floor": bool(player.call("is_on_floor"))})
		check(bool(player.get("input_enabled")) and not bool(player.get("interaction_locked")),
			"S5c 救援后移动输入恢复、无残留交互锁",
			{"input_enabled": bool(player.get("input_enabled")),
			 "interaction_locked": bool(player.get("interaction_locked"))})
		check(int(player.get("recovery_count")) >= 1, "S5d 救援计数在客户端本机生效",
			{"recovery_count": int(player.get("recovery_count"))})
		await walk_to(cart_global(hold_spot(me)), 5.0, "rescued hold", 0.5, true)
	if me == 1:
		var back: bool = await wait_sec(15.0,
			func() -> bool: return actor_on_deck(actor(leaver)), "leaver_back")
		check(back, "S6 主机看到被救援船员回到甲板（主机权威位置）",
			{"actors": all_rows()})
		check(int(actor(leaver).get("recovery_count")) >= 1, "S6b 主机侧救援计数已增加",
			{"recovery_count": int(actor(leaver).get("recovery_count"))})
		check(await start_cart_from_deck(), "S7 全部回到甲板后重新发车", {"cart": cart_row()})
	else:
		check(await wait_sec(20.0, func() -> bool: return bool(cart.get("running")),
			"restarted"), "S7 客户端镜像到重新发车", {"cart": cart_row()})
	# --- 4) ride to the real fault (severed rail governor stop) -------------
	var fault: bool = await wait_sec(150.0, func() -> bool:
		return bool(cart.get("stopped_for_fault")), "fault_stop")
	var fault_state: Dictionary = snapshot()
	var fault_cart: Dictionary = fault_state["cart"] as Dictionary
	check(fault, "S8 矿车按生产规则在断轨前停车（stopped_for_fault）",
		{"cart": fault_cart})
	check(absf(float(fault_cart["distance"]) - 88.0) < 0.5,
		"S8b 停车位置 = 生产断轨停车点 88 m", {"distance": fault_cart["distance"]})
	check(not bool(fault_cart["running"]) and not bool(fault_cart["route_clear"]),
		"S8c 停车后未放行线路（route_clear=false）", {"cart": fault_cart})
	if me == 1:
		check(int((fault_state["safety"] as Dictionary)["brake_count"]) == 1,
			"S8d 正常行驶到断轨期间没有再次误制动", fault_state["safety"])
	# --- 5) restart refused while the track is still severed ----------------
	var walked_to_console: bool = false
	if me == 1:
		walked_to_console = await walk_to(cart_global(Vector3(2.48, 1.95, 1.08)), 6.0,
			"console at fault", 0.45, true)
		await press("repair")
		await wait_real(0.8)
		var refusal: String = str(stage.get("feedback"))
		var refusal_cart: Dictionary = cart_row()
		check(walked_to_console, "S9 主机走到前端控制器")
		check(not bool(refusal_cart["running"]), "S9b 故障未解除时发车被拒绝（running=false）",
			{"cart": refusal_cart, "feedback": refusal})
		check(refusal.find("断") >= 0 or refusal.find("修复") >= 0,
			"S9c 拒绝信息说明真实原因（断轨/维修）", {"feedback": refusal})
		check(str(cart.call("start_refusal")) != "", "S9d 生产 start_refusal 非空",
			{"start_refusal": str(cart.call("start_refusal"))})
	else:
		await wait_sec(20.0, func() -> bool: return bool(cart.get("stopped_for_fault")),
			"client_fault_mirror")
		check(not bool(cart.get("running")) and bool(cart.get("stopped_for_fault")),
			"S9 客户端镜像到故障停车且不可发车", {"cart": cart_row()})

	# --- 6) egress + real production repair --------------------------------
	var order: Array = []
	for pid: int in range(2, players + 1): order.append(pid)
	order.append(1)
	var pos_index: int = order.find(me)
	if pos_index > 0:
		var prev: int = int(order[pos_index - 1])
		check(await wait_sec(150.0, func() -> bool: return actor_cleared(actor(prev)),
			"prev_cleared"), "seat%d 等 seat%d 离开登车口" % [me, prev])
	var egress_ok: bool = await egress_to_yard()
	check(egress_ok, "seat%d 用真实 W 输入走下甲板进入维修场" % me,
		{"pos": player.global_position, "on_deck": on_deck()})
	if me != 2:
		var hold_at: Vector3 = Vector3(2.6, 0.0, -2.8)
		if me == 4: hold_at = Vector3(-0.9, 0.0, -2.8)
		await walk_to(cart_global(hold_at), 6.0, "clear the stair foot", 0.5, true)
	seat_write("yard")
	await run_repair_role()
	check(complete(), "S10 合法维修 + 机械锁定完成", {"rig": rig_row(),
		"route_clear": bool(cart.get("route_clear")), "phase": str(flow.get("phase"))})
	check(bool(cart.get("route_clear")), "S10b 锁定后线路放行")
	check(not bool(player.get("interaction_locked")),
		"S10c 维修结束后没有残留交互锁")
	# --- 7) re-board and re-launch ----------------------------------------
	var reorder: Array = []
	for pid: int in range(2, players + 1): reorder.append(pid)
	reorder.append(1)
	var rpos: int = reorder.find(me)
	if rpos > 0:
		var prev2: int = int(reorder[rpos - 1])
		check(await wait_sec(180.0, func() -> bool: return actor_on_deck(actor(prev2)),
			"prev_reboarded"), "seat%d 等 seat%d 重新登车" % [me, prev2])
	var reboarded: bool = await reboard()
	check(reboarded, "seat%d 用真实 W 输入重新登上甲板" % me,
		{"pos": player.global_position, "on_deck": on_deck()})
	if me != 1:
		await walk_to(cart_global(hold_spot(me) + Vector3(0.0, 0.0, 0.4)), 6.0,
			"clear the stair top", 0.5, true)
	if me == 1:
		check(await wait_sec(180.0, func() -> bool: return all_on_deck(), "all_back"),
			"主机看到全员重新登车", {"actors": all_rows()})
		check(await start_cart_from_deck(), "S11 修好后重新发车（E）",
			{"cart": cart_row(), "feedback": str(stage.get("feedback"))})
		var arrived: bool = await wait_sec(90.0, func() -> bool:
			return bool(cart.get("arrived")), "arrived")
		var done_state: Dictionary = snapshot()
		check(arrived, "S12 矿车抵达 Act23 终点", {"cart": done_state["cart"]})
		check(str((done_state["flow"] as Dictionary)["phase"]) == "done",
			"S12b 关卡阶段 = done", done_state["flow"])
		check(bool((done_state["cart"] as Dictionary)["arrived"]), "S12c arrived=true",
			done_state["cart"])
	else:
		# The host starts the Act04 hand-off in the SAME frame that `phase`
		# becomes "done", and begin_handoff() stops the Act23 snapshot stream, so
		# the last mirror packet a client can ever receive is the pre-arrival one.
		# The client therefore asserts the mirrored end-of-line position (the
		# production observable it really has); the authoritative arrived/done
		# assertion is the host's, and the Act04 hand-off itself is covered by the
		# full-chain regression, which rides the shared SessionHub.
		var mirror_done: bool = await wait_sec(120.0, func() -> bool:
			return float(cart.get("distance")) > 105.5 and bool(cart.get("route_clear")),
			"mirror_arrival")
		check(mirror_done, "S12 客户端镜像到矿车抵达终点段（distance>105.5，线路已放行）",
			{"cart": cart_row(), "phase": str(flow.get("phase"))})
	check(me == int(player.get("peer_id")), "S13 本机身份与席位一致",
		{"peer_id": int(player.get("peer_id")), "me": me, "net": net_row()})
	sample("safety_end")

# =============================================================================
# RESCUE scenario
# =============================================================================
func min_gap_between(mine: Vector3, others: Array) -> float:
	var best: float = 99.0
	for row: Variant in others:
		var entry: Dictionary = row as Dictionary
		if not bool(entry.get("present", false)): continue
		if int(entry["slot"]) == me: continue
		var local_at: Array = entry["cart_local"] as Array
		var other := Vector3(float(local_at[0]), float(local_at[1]), float(local_at[2]))
		best = minf(best, Vector2(mine.x - other.x, mine.z - other.z).length())
	return best

func scenario_rescue() -> void:
	var ready: bool = await wait_ready()
	check(ready, "R0 会话就绪", {"net": net_row(), "actors": all_rows()})
	if not ready: return
	if me > 1:
		check(await wait_sec(120.0, func() -> bool: return actor_on_deck(actor(me - 1)),
			"prev_boarded"), "seat%d 等 seat%d 登上甲板" % [me, me - 1])
	check(await board_deck(), "seat%d 用真实 W 输入登上甲板" % me)
	await walk_to(cart_global(hold_spot(me)), 6.0, "hold clear", 0.45, true)
	seat_write("decked")
	if me == 1:
		check(await wait_sec(180.0, func() -> bool: return all_on_deck(), "all_on_deck"),
			"主机看到全员登车")
		check(await start_cart_from_deck(), "主机用 E 真实发车", {"cart": cart_row()})
	var moving: bool = false
	if me == 1:
		moving = await wait_sec(60.0, _cart_running_past_10, "moving")
	else:
		# `running` is already false in the client mirror by the time the host's B
		# lands at 10 m; the shared observable both ends publish is the distance.
		moving = await wait_sec(60.0, _cart_past_10, "moving")
	check(moving, "矿车真实行驶到 10 m 以上", {"cart": cart_row()})
	if me == 1:
		await press("cart_brake")
		await wait_real(2.0)
		check(not bool(cart.get("running")) and str(cart.get("brake_reason")) == "player_brake",
			"主机按 B 真实制动（生产制动路径）",
			{"cart": cart_row(), "feedback": str(stage.get("feedback"))})
	else:
		check(await wait_sec(20.0, func() -> bool: return not bool(cart.get("running")),
			"mirror_brake"), "客户端镜像到制动", {"cart": cart_row()})
	check(await wait_sec(20.0, func() -> bool:
		return float(cart.get("speed")) < 0.03 or bool(cart.get("network_client")), "settled"),
		"矿车停稳（救援前置条件）", {"cart": cart_row()})

	# --- everyone leaves the deck for real (host-ordered, seat barriers) ----
	# Position polling alone races with the rescue that follows: a seat that is
	# already back on the deck looks like a seat that never left. The barriers
	# below carry only "whose turn is it", never world state.
	if me == 1:
		seat_write("brake_done", {"brake_reason": str(cart.get("brake_reason"))})
	else:
		check(await seat_wait(1, "brake_done", 30.0), "seat%d 等主机完成真实制动" % me)
	var exit_order: Array = []
	for pid: int in range(2, players + 1): exit_order.append(pid)
	exit_order.append(1)
	var my_index: int = exit_order.find(me)
	if my_index > 0:
		var prev: int = int(exit_order[my_index - 1])
		check(await seat_wait(prev, "off", 120.0),
			"seat%d 等 seat%d 离开甲板" % [me, prev])
	var off: bool = await exit_deck()
	check(off, "seat%d 用真实 W 输入离开甲板" % me,
		{"pos": player.global_position, "on_deck": on_deck()})
	seat_write("off", {"pos": [snappedf(player.global_position.x, 0.01),
		snappedf(player.global_position.y, 0.01), snappedf(player.global_position.z, 0.01)],
		"on_deck": on_deck()})
	if me == 1:
		var all_off: bool = true
		for pid: int in range(2, players + 1):
			var seen_off: bool = await seat_wait(pid, "off", 120.0)
			if not seen_off: all_off = false
		var physically_off: bool = true
		for row: Dictionary in all_rows() as Array:
			if bool(row.get("contains_point", true)): physically_off = false
		check(all_off and physically_off, "R0b 主机确认全员真实离开甲板（不在甲板盒内）",
			{"actors": all_rows()})
		seat_write("all_off", {"all_off": all_off and physically_off})
	else:
		# Nobody is rescued until the last seat is physically off the deck: a
		# rescued body standing in the 0.96 m gate lane blocks the seat that still
		# has to walk out of it.
		check(await seat_wait(1, "all_off", 120.0), "seat%d 等全员离开甲板" % me)

	# --- single rescue (one seat) ------------------------------------------
	var single: int = 2 if players >= 2 else 1
	if me == single:
		var ok: bool = false
		for attempt: int in range(6):
			if on_deck(): break
			await press("cart_recover")
			await wait_real(0.7)
			ok = on_deck()
		var local_at: Vector3 = cart.to_local(player.global_position)
		check(ok, "R1 单人以 R 请求真实救援并回到甲板",
			{"cart_local": local_at, "recovery_count": int(player.get("recovery_count"))})
		check(bool(player.call("is_on_floor")), "R1b 单人救援后站在甲板上")
		check(bool(player.get("input_enabled")) and not bool(player.get("interaction_locked")),
			"R1c 单人救援后输入恢复、交互锁清空",
			{"input_enabled": bool(player.get("input_enabled")),
			 "interaction_locked": bool(player.get("interaction_locked"))})
		check(int(player.get("recovery_count")) >= 1, "R1d 单人救援计数 +1")
		var before: Vector3 = player.global_position
		await walk_cart(local_at + Vector3(0.0, 0.0, 0.55), 2.0, "move after rescue", 0.40, true)
		var moved: float = player.global_position.distance_to(before)
		check(moved > 0.12, "R1e 单人救援后可以用真实输入移动（>0.12 m）", {"moved": moved})
		sample("single_rescued")
		seat_write("single", {"cart_local": [snappedf(local_at.x, 0.01),
			snappedf(local_at.y, 0.01), snappedf(local_at.z, 0.01)],
			"recovery_count": int(player.get("recovery_count")), "moved": moved})
	else:
		check(await seat_wait(single, "single", 40.0),
			"seat%d 看到 seat%d 被救援回甲板" % [me, single], {"actors": all_rows()})
	if me == 1:
		var peer_back: bool = await wait_sec(15.0,
			func() -> bool: return actor_on_deck(actor(single)), "host_single")
		check(peer_back, "R2 主机侧代理位置与客户端一致（被救援者在甲板上）",
			{"actors": all_rows()})
		check(int(actor(single).get("recovery_count")) >= 1,
			"R2b 主机侧救援计数与客户端一致",
			{"host_count": int(actor(single).get("recovery_count"))})

	# --- simultaneous rescue of the rest ----------------------------------
	if me != single:
		await press("cart_recover")
		await wait_real(0.3)
		if not on_deck():
			await press("cart_recover")
		await wait_real(1.0)
	else:
		await wait_real(0.6)
	var mine_on: bool = on_deck()
	var mine_local: Vector3 = cart.to_local(player.global_position)
	check(mine_on, "R3 多人同时救援：本席回到甲板",
		{"cart_local": mine_local, "recovery_count": int(player.get("recovery_count"))})
	if mine_on:
		var gap: float = min_gap_between(mine_local, all_rows())
		check(gap >= 0.75, "R4 救援落点与相邻船员保持胶囊间距（>=0.75 m）",
			{"gap": gap, "cart_local": mine_local, "actors": all_rows()})
		check(mine_local.x > -3.3 and mine_local.x < 2.9 and mine_local.z > 0.9 and
			mine_local.z < 3.45, "R4b 救援落点在真实可站立的甲板范围内",
			{"cart_local": mine_local})
		check(bool(player.call("is_on_floor")), "R4c 多人救援后角色落在甲板实体上",
			{"on_floor": bool(player.call("is_on_floor"))})
	seat_write("rescued", {"cart_local": [snappedf(mine_local.x, 0.01),
		snappedf(mine_local.y, 0.01), snappedf(mine_local.z, 0.01)],
		"on_deck": mine_on, "recovery_count": int(player.get("recovery_count"))})
	if me == 1:
		var all_files: bool = true
		for pid: int in range(2, players + 1):
			var seen: bool = await seat_wait(pid, "rescued", 60.0)
			if not seen: all_files = false
		var all_back: bool = await wait_sec(15.0, func() -> bool: return all_on_deck(),
			"all_back")
		check(all_back, "R3b 主机看到全体被救援者都在甲板上", {"actors": all_rows()})
		check(all_files, "R3c 每个席位都报告了自己的救援落点", {"actors": all_rows()})
		var rows: Array = all_rows()
		var min_pair: float = 99.0
		for i: int in range(rows.size()):
			for j: int in range(i + 1, rows.size()):
				var a: Dictionary = rows[i] as Dictionary
				var b: Dictionary = rows[j] as Dictionary
				var la: Array = a["cart_local"] as Array
				var lb: Array = b["cart_local"] as Array
				var d: float = Vector2(float(la[0]) - float(lb[0]),
					float(la[2]) - float(lb[2])).length()
				min_pair = minf(min_pair, d)
		check(min_pair >= 0.75, "R5 多人救援落点没有长期重叠（最小间距 %.2f m）" % min_pair,
			{"min_pair": min_pair, "actors": rows})
		sample("multi_rescued")
		seat_write("gaps_ok")
	else:
		check(await seat_wait(1, "gaps_ok", 60.0), "seat%d 等主机确认落点间隔" % me)

	# --- every seat can move again after its rescue -----------------------
	var walk_before: Vector3 = player.global_position
	var walk_local: Vector3 = cart.to_local(walk_before)
	await walk_cart(walk_local + Vector3(0.0, 0.0, 0.50), 2.0, "move after multi rescue", 0.35, true)
	var moved_after: float = player.global_position.distance_to(walk_before)
	check(moved_after > 0.12, "R4d 多人救援后本席仍可用真实输入移动（>0.12 m）",
		{"moved": moved_after, "cart_local": cart.to_local(player.global_position)})
	seat_write("moved")
	if me == 1:
		var all_moved: bool = true
		for pid: int in range(2, players + 1):
			var seen_move: bool = await seat_wait(pid, "moved", 40.0)
			if not seen_move: all_moved = false
		check(all_moved, "R4e 每个席位都在救援后完成了真实移动")
	# --- stale / duplicate rescue requests (cart still stopped) -----------
	var stay_before: Vector3 = player.global_position
	var count_before: int = int(player.get("recovery_count"))
	await press("cart_recover")
	await press("cart_recover")
	await wait_real(1.0)
	var stay_after: Vector3 = player.global_position
	check(stay_after.distance_to(stay_before) < 0.05,
		"R6 已登车后的重复救援请求不会再次传送",
		{"before": stay_before, "after": stay_after})
	check(int(player.get("recovery_count")) == count_before,
		"R6b 重复救援请求不会污染救援计数",
		{"before": count_before, "after": int(player.get("recovery_count"))})
	seat_write("stale")
	# --- normal interaction restored --------------------------------------
	if me == 1:
		var all_stale: bool = true
		for pid: int in range(2, players + 1):
			var seen_stale: bool = await seat_wait(pid, "stale", 40.0)
			if not seen_stale: all_stale = false
		check(all_stale, "R6c 每个席位都完成了重复请求检查")
		var started: bool = await start_cart_from_deck()
		check(started, "R7 救援后回到甲板仍可正常发车（交互恢复）",
			{"cart": cart_row(), "feedback": str(stage.get("feedback"))})
		seat_write("restarted", {"running": bool(cart.get("running"))})
	else:
		check(await seat_wait(1, "restarted", 40.0),
			"seat%d 等主机重新发车" % me)
		check(await wait_sec(20.0, func() -> bool: return bool(cart.get("running")),
			"restarted_mirror"), "R7 客户端镜像到救援后正常发车", {"cart": cart_row()})
	check(me == int(player.get("peer_id")), "R8 本机身份与席位一致",
		{"peer_id": int(player.get("peer_id")), "me": me, "net": net_row()})
	if me == 1:
		var identities: bool = true
		for pid: int in range(1, players + 1):
			if actor(pid) == null or int(actor(pid).get("peer_id")) != pid:
				identities = false
		check(identities, "R8b 主机侧每个实体都映射到自己的席位", {"actors": all_rows()})
		seat_write("identities_ok")
	sample("rescue_end")

# --- boot / run -------------------------------------------------------------
func find_stage() -> Node3D:
	if current_scene != null:
		var direct: Node3D = current_scene.get_node_or_null("MovingCartSlice") as Node3D
		if direct != null: return direct
		var found: Array = current_scene.find_children("*", "Node3D", true, false)
		for node: Node in found:
			var candidate: Node3D = node as Node3D
			if candidate != null and candidate.has_method("rescue_player") and candidate.get("cart") != null:
				return candidate
	return null

func _client_ready() -> bool:
	return str(coop.get("mode")) == "client" and int(coop.get("local_slot")) >= 2

func _crew_joined() -> bool:
	var actor_count: int = (stage.get("actors") as Dictionary).size()
	var slot_count: int = (coop.get("slots") as Dictionary).size()
	return actor_count >= players and slot_count >= players

func wait_ready() -> bool:
	if role == "client":
		var ok: bool = await wait_until(_client_ready, seconds(30.0), "welcome")
		me = int(coop.get("local_slot"))
		return ok
	var host_ok: bool = await wait_until(_crew_joined, seconds(60.0), "crew_join")
	me = int(coop.get("local_slot"))
	return host_ok

func write_outputs() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var data: Dictionary = {"role": role, "seat": me, "scenario": scenario,
		"players": players, "passed": failures == 0, "failures": failures,
		"checks": checks, "samples": samples,
		"final": snapshot() if stage != null else {}}
	var file: FileAccess = FileAccess.open(
		out_dir.path_join("sr_%s_%d.json" % [role, me]), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()

func shutdown() -> void:
	stop_move()
	await frames(4)
	seat_write("done")
	if role == "host":
		for pid: int in range(2, players + 1):
			var other: bool = await seat_wait(pid, "done", 40.0)
			if not other:
				print("SR_BARRIER_MISSING seat=", pid)
		await frames(20)
	else:
		await seat_wait(1, "host_done", 30.0)
		await frames(10)
	write_outputs()
	print("SR_RESULT ", JSON.stringify({"role": role, "seat": me, "scenario": scenario,
		"checks": checks.size(), "failures": failures, "passed": failures == 0}))
	quit(0 if failures == 0 else 1)

func begin() -> bool:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("SR_PROBE_START role=", role, " seat=", seat, " scenario=", scenario,
		" players=", players, " port=", port, " out=", out_dir)
	await frames(2)
	stage = find_stage()
	if stage == null:
		print("SR_PROBE no stage")
		quit(1)
		return false
	cart = stage.get("cart") as AnimatableBody3D
	player = stage.get("player") as CharacterBody3D
	flow = stage.get("flow")
	coop = stage.get("coop")
	yard = stage.get("yard") as Node3D
	await frames(40)
	me = int(coop.get("local_slot")) if coop != null else 1
	note("启动状态", snapshot())
	return true

func run() -> void:
	if not (await begin()): return
	match scenario:
		"rescue": await scenario_rescue()
		_: await scenario_safety()
	if role == "host":
		await frames(2)
		seat_write("host_done")
	await shutdown()

