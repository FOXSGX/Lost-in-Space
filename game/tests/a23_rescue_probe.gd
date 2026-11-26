extends SceneTree

# =============================================================================
# a23_rescue_probe.gd · Act23 矿车「救援落点 / 救援后状态」复现与验收探针
#
# 全部操作都是真实玩家输入（WASD / E / B / R）与真实物理；判定只读取
# global_position / cart-local / contains_point / is_on_floor / coop 快照字段。
# 本探针**从不**写 running / brake_reason / on_deck / grounded / locked / rescue
# 计数或任何任务 flag。
#
# 启动（每个进程一条）：
#   Godot --headless --path <project> res://act23/act23_entry.tscn \
#         -s res://tests/a23_rescue_probe.gd -- --role=host --players=3 \
#            --port=26600 --coop-host --out=<dir>
#   客户端把 --coop-host 换成 --coop-client 127.0.0.1 并加 --seat=N
#
# 场景：
#   repro        最小复现：所有人开局在登车平台（不在甲板），逐席按 R 请求救援
# =============================================================================

const DECK_TOP: float = 1.9546444
const FOOT_OFFSET: float = 0.05

var role: String = "host"
var scenario: String = "repro"
var players: int = 2
var port: int = 26600
var address: String = "127.0.0.1"
var out_dir: String = "user://a23_rescue"
var seat: int = 1

var stage: Node3D
var cart: AnimatableBody3D
var player: CharacterBody3D
var flow: Node
var coop: Node
var yard: Node

var clock: int = 0
var checks: Array = []
var failures: int = 0
var rows: Array = []

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

func local_slot() -> int:
	return int(coop.get("local_slot")) if coop != null else 1

# --- 基础工具 ---------------------------------------------------------------
func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame
		clock += 1

func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details, "t": clock, "role": role})
	if not ok: failures += 1
	print("RS_", "OK   " if ok else "FAIL ", "[", role, "/", scenario, "] ", label, " ", JSON.stringify(details))

func note(label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": true, "label": label, "details": details, "t": clock, "role": role, "note": true})
	print("RS_NOTE [", role, "/", scenario, "] ", label, " ", JSON.stringify(details))

func stop_move() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)

func press(action: String, hold: int = 2, after: int = 6) -> void:
	Input.action_press(action)
	await frames(hold)
	Input.action_release(action)
	await frames(after)

func wait_until(predicate: Callable, limit: int, label: String = "") -> bool:
	for i: int in range(limit):
		await physics_frame
		clock += 1
		if i % 300 == 0:
			print("RS_HB role=", role, " wait=", label, " frame=", i, "/", limit)
		if bool(predicate.call()): return true
	return false

func seconds(value: float) -> int:
	return maxi(1, int(round(value * float(Engine.physics_ticks_per_second))))

func local_of(world_at: Vector3) -> Vector3:
	return cart.to_local(world_at)

func actor(slot: int) -> CharacterBody3D:
	var actors: Dictionary = stage.get("actors") as Dictionary
	if not actors.has(slot): return null
	return actors[slot] as CharacterBody3D

func actor_row(slot: int) -> Dictionary:
	var who: CharacterBody3D = actor(slot)
	if who == null or not is_instance_valid(who):
		return {"slot": slot, "present": false}
	var local: Vector3 = cart.to_local(who.global_position)
	return {
		"slot": slot, "present": true, "peer_id": int(who.get("peer_id")),
		"is_local": who == player,
		"pos": [snappedf(who.global_position.x, 0.001), snappedf(who.global_position.y, 0.001),
			snappedf(who.global_position.z, 0.001)],
		"cart_local": [snappedf(local.x, 0.001), snappedf(local.y, 0.001), snappedf(local.z, 0.001)],
		"on_floor": bool(who.call("is_on_floor")),
		"contains_point": bool(cart.call("contains_point", who.global_position)),
		"grip_id": int(who.get("grip_id")),
		"interaction_locked": bool(who.get("interaction_locked")),
		"input_enabled": bool(who.get("input_enabled")),
		"recovery_count": int(who.get("recovery_count")),
		"velocity": [snappedf(who.velocity.x, 0.01), snappedf(who.velocity.y, 0.01),
			snappedf(who.velocity.z, 0.01)],
	}

func all_actor_rows() -> Array:
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
		"route_clear": bool(cart.get("route_clear")),
		"stopped_for_fault": bool(cart.get("stopped_for_fault")),
		"brake_reason": str(cart.get("brake_reason")),
		"state": str(cart.get("state")),
		"revision": int(cart.get("revision")),
		"network_client": bool(cart.get("network_client")),
	}

func rig_row() -> Dictionary:
	var rig: Node = yard.get("rig") if yard != null else null
	if rig == null: return {}
	return {"guide_holder": int(rig.get("guide_holder")),
		"bracket_holder": int(rig.get("bracket_holder")),
		"completed": bool(rig.get("completed"))}

func net_row() -> Dictionary:
	if coop == null: return {}
	return {"mode": str(coop.get("mode")), "local_slot": int(coop.get("local_slot")),
		"slot": local_slot(),
		"slots": (coop.get("slots") as Dictionary).keys(),
		"peers": get_multiplayer().get_peers().size(),
		"sent": int(coop.get("snapshots_sent")), "recv": int(coop.get("snapshots_received")),
		"rejected_poses": int(coop.get("rejected_poses")),
		"rejected_actions": int(coop.get("rejected_actions"))}

func snapshot() -> Dictionary:
	return {"role": role, "seat": seat, "scenario": scenario, "clock": clock,
		"players": players, "cart": cart_row(), "actors": all_actor_rows(),
		"rig": rig_row(), "net": net_row(), "feedback": str(stage.get("feedback")),
		"flow": {"phase": str(flow.get("phase")), "console_actor": int(flow.get("console_actor")),
			"at_console": bool(flow.get("at_console"))}}

func sample(tag: String) -> void:
	rows.append({"t": clock, "tag": tag, "state": snapshot()})

func write_outputs() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var data: Dictionary = {"role": role, "seat": seat, "scenario": scenario,
		"players": players, "passed": failures == 0, "failures": failures,
		"checks": checks, "samples": rows,
		"final": snapshot() if stage != null else {}}
	var name: String = "%s_%s.json" % [role, str(seat)]
	var file: FileAccess = FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()

func finish() -> void:
	stop_move()
	await frames(6)
	write_outputs()
	print("RS_RESULT ", JSON.stringify({"role": role, "seat": seat, "scenario": scenario,
		"checks": checks.size(), "failures": failures, "passed": failures == 0}))
	quit(0 if failures == 0 else 1)

# --- 启动 -------------------------------------------------------------------
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

func _crew_joined(slot_target: int) -> bool:
	var actor_count: int = (stage.get("actors") as Dictionary).size()
	var slot_count: int = (coop.get("slots") as Dictionary).size()
	return actor_count >= slot_target and slot_count >= slot_target

func wait_ready(slot_target: int) -> bool:
	if role == "client":
		return await wait_until(_client_ready, seconds(30.0), "welcome")
	return await wait_until(func() -> bool: return _crew_joined(slot_target), seconds(60.0), "crew_join")

func begin() -> bool:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("RS_PROBE_START role=", role, " seat=", seat, " scenario=", scenario,
		" players=", players, " port=", port, " out=", out_dir)
	await frames(2)
	stage = find_stage()
	if stage == null:
		print("RS_PROBE no stage")
		quit(1)
		return false
	cart = stage.get("cart") as AnimatableBody3D
	player = stage.get("player") as CharacterBody3D
	flow = stage.get("flow")
	coop = stage.get("coop")
	yard = stage.get("yard")
	await frames(40)
	note("启动状态", snapshot())
	return true

# --- 场景：最小复现 ----------------------------------------------------------
func scenario_repro() -> void:
	var ready: bool = await wait_ready(players)
	check(ready, "R0 会话就绪（%d 人）" % players,
		{"net": net_row(), "actors": all_actor_rows()})
	if not ready: return
	# 在甲板外时按 R（生产救援入口）。每一席依次按，间隔 15 帧由各席自身完成。
	var mine: Dictionary = actor_row(local_slot())
	check(not bool(mine.get("contains_point", false)), "R1 本席开局不在甲板上（可请求救援）", mine)
	sample("before_r")
	await press("cart_recover", 2, 10)
	sample("after_r")
	await frames(seconds(1.5))
	sample("after_r_settle")
	var after: Dictionary = actor_row(local_slot())
	check(bool(after.get("contains_point", false)),
		"R2 本席按 R 后回到甲板（主机权威救援在本席生效）",
		{"slot": local_slot(), "after": after, "cart": cart_row(), "net": net_row()})
	check(bool(after.get("contains_point", false)) and bool(after.get("on_floor", false)) and
		bool(after.get("input_enabled", true)) and not bool(after.get("interaction_locked", false)),
		"R3 救援后角色在甲板上、落地、可移动、无残留交互锁", after)
	# 等所有席位都被救援（或超时），便于对照主机/客户端
	var all_on: bool = await wait_until(func() -> bool:
		for row: Dictionary in all_actor_rows():
			if not bool(row.get("contains_point", false)): return false
		return true, seconds(15.0), "all_rescued")
	check(all_on, "R4 全部席位都在甲板上（所有玩家都被救援）", {"actors": all_actor_rows()})
	note("救援后最终状态", snapshot())

func run() -> void:
	if not (await begin()): return
	match scenario:
		"repro": await scenario_repro()
		_: await scenario_repro()
	await finish()
