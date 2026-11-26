extends SceneTree

# =============================================================================
# safety_brake_probe.gd · Act23 矿车「离车保护制动」(C2) 复现 / 验收探针
#
# 全部操作都是真实玩家输入（WASD / E / B）与真实物理；判定读取 global_position、
# is_on_floor()、cart.speed、cart.contains_point()、20 Hz 快照镜像状态。
# 本探针**从不**写 running / brake_reason / braking / 任务 flag。
#
# 角色与场景：
#   --role=solo                    单进程离线
#       --scenario=solo_normal     单人正常乘坐不误制动 + 真实 B 制动
#       --scenario=solo_leave      单人（主机本地角色）离车 → 保护制动
#   --role=host   --coop-host      主机（权威侧）
#   --role=client --coop-client 127.0.0.1
#       --scenario=normal          双人正常乘坐不误制动 + 客户端 B 制动
#       --scenario=client_leave    客户端在行驶中真实走下甲板 → 主机保护制动
#       --scenario=host_leave      主机在行驶中真实走下甲板 → 主机保护制动
#       --scenario=disconnect      客户端在甲板上断线 → 不误判为离车
#       --scenario=bystander       客户端已连接但从未上车 → 不误判为离车
#
# 输出（<out> 由 --out= 指定）：
#   <role>.json            判定 + 最终状态
#   <role>_ride.csv        逐帧本端视角（distance/speed/mirror_speed/running/…）
#   <role>_actors.csv      逐帧全部角色在矿车局部坐标 + contains_point
# =============================================================================

const DECK_TOP: float = 1.9546444
const FOOT_OFFSET: float = 0.05
const SAFETY_REASON: String = "driver_left_deck"
# 登车口通道（甲板近侧 z=0.87 的开口 x 0.52..1.48）与门外的落点。
const GATE_IN: Vector3 = Vector3(1.0, 1.9546444, 1.35)
const GATE_OUT: Vector3 = Vector3(1.0, 1.9546444, 0.10)

var role: String = "solo"
var scenario: String = "solo_normal"
var port: int = 9951
var address: String = "127.0.0.1"
var out_dir: String = "user://safety_probe"

var stage: Node3D
var cart: AnimatableBody3D
var player: CharacterBody3D
var flow: Node
var coop: Node

var clock: int = 0
var checks: Array = []
var failures: int = 0
var ride_rows: Array = []
var actor_rows: Array = []
var watching: bool = false
var leave_observed: Dictionary = {}

# --- 基础工具 ---------------------------------------------------------------
func _initialize() -> void:
	run.call_deferred()

func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--out="): out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--address="): address = arg.trim_prefix("--address=")

func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame
		clock += 1

func watch_frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame
		clock += 1
		if watching: _watch_tick()

func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details, "t": clock, "role": role})
	if not ok: failures += 1
	print("SB_", "OK   " if ok else "FAIL ", "[", role, "/", scenario, "] ", label, " ", JSON.stringify(details))

func note(label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": true, "label": label, "details": details, "t": clock, "role": role, "note": true})
	print("SB_NOTE [", role, "/", scenario, "] ", label, " ", JSON.stringify(details))

func local_of(world_at: Vector3) -> Vector3:
	return cart.to_local(world_at)

func _stage_var(name: String, fallback: Variant) -> Variant:
	if stage == null: return fallback
	for prop: Dictionary in stage.get_property_list():
		if str(prop["name"]) == name:
			return stage.get(name)
	return fallback

# --- 真实输入 ---------------------------------------------------------------
func stop_move() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)

func press(action: String, hold: int = 2, after: int = 6) -> void:
	Input.action_press(action)
	await frames(hold)
	Input.action_release(action)
	await frames(after)

func steer(target: Vector3, limit: int, radius: float, cart_local: bool) -> Dictionary:
	var reached: bool = false
	var aim: Vector3 = target
	var check_timer: int = 0
	var last: Vector3 = player.global_position
	var detour: int = 0
	var side: float = 1.0
	var used: int = 0
	var max_step: float = 0.0
	for _i: int in range(limit):
		used += 1
		var world_target: Vector3 = cart.to_global(target) if cart_local else target
		var here: Vector3 = player.global_position
		if Vector2(here.x - world_target.x, here.z - world_target.z).length() < radius:
			reached = true
			break
		if detour > 0:
			detour -= 1
		else:
			aim = world_target
			check_timer += 1
			if check_timer >= 26:
				if Vector2(here.x - last.x, here.z - last.z).length() < 0.32:
					var toward: Vector3 = world_target - here
					toward.y = 0.0
					var perp: Vector3 = Vector3(-toward.z, 0.0, toward.x)
					if perp.length() > 0.001:
						aim = here + perp.normalized() * 2.2 * side
						detour = 24
						side = -side
				last = here
				check_timer = 0
		var direction: Vector3 = aim - player.global_position
		direction.y = 0.0
		if direction.length() < 0.06:
			direction = Vector3(0.08, 0.0, 0.08)
		var yaw: float = float(player.get("_camera_yaw"))
		var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
		var strength: float = clampf(direction.length() / 0.55, 0.55, 1.0)
		var horizontal: float = direction.normalized().dot(right) * strength
		var vertical: float = -direction.normalized().dot(forward) * strength
		stop_move()
		Input.action_press("move_right" if horizontal > 0.0 else "move_left", absf(horizontal))
		Input.action_press("move_down" if vertical > 0.0 else "move_up", absf(vertical))
		await physics_frame
		clock += 1
		max_step = maxf(max_step, player.global_position.distance_to(here))
	stop_move()
	await frames(6)
	return {"ok": reached, "frames": used, "max_step": max_step}

func face(target: Vector3) -> void:
	for _i: int in range(26):
		var direction: Vector3 = target - player.global_position
		player.set("_camera_yaw_target", atan2(-direction.x, -direction.z))
		await physics_frame
		clock += 1

# 真实 WASD 走出甲板：目标点每帧按矿车的实时位姿重新投影，所以是"相对行驶中的甲板"
# 的真实移动，不是瞬移。走出门框后角色自然掉到地面（local_y < 1.5）即视为离车。
func walk_off_deck(limit: int) -> Dictionary:
	# 先站进登车口通道（近侧开口只有 x 0.52..1.48），否则会沿着栏杆走；
	# 这段仍是真实 WASD（steer 用的是玩家同一套移动输入）。
	var lane: Vector3 = cart.to_local(player.global_position)
	if not (lane.x > 0.55 and lane.x < 1.45 and lane.z > 0.9 and lane.z < 2.0):
		await steer(GATE_IN, 300, 0.35, true)
	var used: int = 0
	var min_local_y: float = 99.0
	var last_local: Vector3 = cart.to_local(player.global_position)
	while used < limit:
		var world_target: Vector3 = cart.to_global(GATE_OUT)
		var toward: Vector3 = world_target - player.global_position
		toward.y = 0.0
		var direction: Vector3 = toward
		if direction.length() < 0.05: direction = Vector3(0.0, 0.0, -0.08)
		var yaw: float = float(player.get("_camera_yaw"))
		var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
		var horizontal: float = direction.normalized().dot(right)
		var vertical: float = -direction.normalized().dot(forward)
		stop_move()
		Input.action_press("move_right" if horizontal > 0.0 else "move_left", absf(horizontal))
		Input.action_press("move_down" if vertical > 0.0 else "move_up", absf(vertical))
		await physics_frame
		clock += 1
		if watching: _watch_tick()
		used += 1
		last_local = cart.to_local(player.global_position)
		min_local_y = minf(min_local_y, last_local.y)
		if last_local.y < 1.5: break
	stop_move()
	await frames(6)
	last_local = cart.to_local(player.global_position)
	return {"left": last_local.y < 1.5, "frames": used, "min_local_y": min_local_y,
		"cart_local": [last_local.x, last_local.y, last_local.z], "on_floor": player.is_on_floor()}

# --- 采样 -------------------------------------------------------------------
func _watch_tick() -> void:
	var own_local: Vector3 = cart.to_local(player.global_position)
	var safety_count: int = int(_stage_var("_safety_brake_count", -1))
	ride_rows.append([clock, float(cart.get("distance")), float(cart.get("speed")),
		float(cart.get("mirror_speed")), 1 if bool(cart.get("running")) else 0,
		str(cart.get("brake_reason")), str(cart.get("state")), int(cart.get("revision")),
		own_local.x, own_local.y, own_local.z, 1 if player.is_on_floor() else 0, safety_count])
	var actors: Dictionary = stage.get("actors") as Dictionary
	var keys: Array = actors.keys()
	keys.sort()
	for slot: int in keys:
		var actor: CharacterBody3D = actors[slot] as CharacterBody3D
		if actor == null or not is_instance_valid(actor): continue
		var l: Vector3 = cart.to_local(actor.global_position)
		actor_rows.append([clock, slot, 1 if actor == player else 0, l.x, l.y, l.z,
			1 if actor.is_on_floor() else 0,
			1 if bool(cart.call("contains_point", actor.global_position)) else 0,
			int(actor.get("grip_id"))])

func summarise(rows: Array) -> Dictionary:
	if rows.is_empty(): return {}
	var first: Array = rows[0]
	var drift := 0.0
	var foot_min := 999.0
	var floor_frames := 0
	var sinking := 0
	var speed_max := 0.0
	var mirror_max := 0.0
	for row: Array in rows:
		var dx: float = float(row[8]) - float(first[8])
		var dz: float = float(row[10]) - float(first[10])
		drift = maxf(drift, sqrt(dx * dx + dz * dz))
		var foot: float = float(row[9]) + FOOT_OFFSET
		foot_min = minf(foot_min, foot)
		if foot < DECK_TOP - 0.03: sinking += 1
		if int(row[11]) == 1: floor_frames += 1
		speed_max = maxf(speed_max, float(row[2]))
		mirror_max = maxf(mirror_max, float(row[3]))
	var travelled: float = float(rows[rows.size() - 1][1]) - float(first[1])
	return {"frames": rows.size(), "drift_m": drift, "min_clearance": foot_min - DECK_TOP,
		"sinking_frames": sinking, "on_floor_ratio": float(floor_frames) / float(rows.size()),
		"cart_speed_max": speed_max, "mirror_speed_max": mirror_max,
		"distance_start": float(first[1]), "distance_end": float(rows[rows.size() - 1][1]),
		"distance_delta": travelled}

func state_of(who: CharacterBody3D = null) -> Dictionary:
	var actor: CharacterBody3D = who if who != null else player
	if actor == null: return {}
	var local: Vector3 = cart.to_local(actor.global_position)
	return {
		"role": role, "scenario": scenario, "clock": clock,
		"slot": int(actor.get("peer_id")), "coop_mode": str(coop.get("mode")) if coop != null else "",
		"local_slot": int(coop.get("local_slot")) if coop != null else 0,
		"actors": (stage.get("actors") as Dictionary).size(),
		"peers": get_multiplayer().get_peers().size(),
		"cart": {
			"distance": float(cart.get("distance")), "speed": float(cart.get("speed")),
			"mirror_speed": float(cart.get("mirror_speed")),
			"target_distance": float(cart.get("target_distance")),
			"running": bool(cart.get("running")), "arrived": bool(cart.get("arrived")),
			"route_clear": bool(cart.get("route_clear")),
			"stopped_for_fault": bool(cart.get("stopped_for_fault")),
			"brake_reason": str(cart.get("brake_reason")), "state": str(cart.get("state")),
			"revision": int(cart.get("revision")),
			"network_client": bool(cart.get("network_client")),
		},
		"me": {"cart_local": [local.x, local.y, local.z],
			"on_floor": actor.is_on_floor(), "contains_point": bool(cart.call("contains_point", actor.global_position))},
		"all_actors": _all_actor_rows(),
		"security": {
			"armed": _stage_var("_safety_armed", null),
			"triggered": _stage_var("_safety_triggered", null),
			"riders": _stage_var("_safety_riders", null),
			"brake_count": _stage_var("_safety_brake_count", -1),
		},
		"net": {
			"snapshots_sent": int(coop.get("snapshots_sent")) if coop != null else -1,
			"snapshots_received": int(coop.get("snapshots_received")) if coop != null else -1,
			"rejected_poses": int(coop.get("rejected_poses")) if coop != null else -1,
			"rejected_actions": int(coop.get("rejected_actions")) if coop != null else -1,
		},
		"feedback": str(stage.get("feedback")),
	}

func _all_actor_rows() -> Array:
	var rows: Array = []
	var actors: Dictionary = stage.get("actors") as Dictionary
	var keys: Array = actors.keys()
	keys.sort()
	for slot: int in keys:
		var actor: CharacterBody3D = actors[slot] as CharacterBody3D
		if actor == null or not is_instance_valid(actor): continue
		var local: Vector3 = cart.to_local(actor.global_position)
		rows.append({"slot": slot, "is_local": actor == player,
			"cart_local": [local.x, local.y, local.z], "on_floor": actor.is_on_floor(),
			"contains_point": bool(cart.call("contains_point", actor.global_position)),
			"peer_id": int(actor.get("peer_id")), "grip_id": int(actor.get("grip_id"))})
	return rows

func write_csv(name: String, rows: Array, header: String) -> void:
	var file: FileAccess = FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
	if file == null: return
	file.store_line(header)
	for row: Array in rows:
		var parts: PackedStringArray = []
		for value: Variant in row: parts.append(str(value))
		file.store_line(",".join(parts))
	file.close()

func write_outputs() -> void:
	var data: Dictionary = {
		"role": role, "scenario": scenario, "passed": failures == 0, "failures": failures,
		"checks": checks, "final": state_of() if stage != null else {},
		"leave_observed": leave_observed,
	}
	var file: FileAccess = FileAccess.open(out_dir.path_join(role + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()
	write_csv(role + "_ride.csv", ride_rows,
		"t,distance,speed,mirror_speed,running,brake_reason,state,revision,own_local_x,own_local_y,own_local_z,on_floor,safety_brake_count")
	write_csv(role + "_actors.csv", actor_rows,
		"t,slot,is_local,local_x,local_y,local_z,on_floor,contains_point,grip_id")

func finish() -> void:
	stop_move()
	await frames(6)
	write_outputs()
	print("SB_RESULT ", JSON.stringify({"role": role, "scenario": scenario,
		"checks": checks.size(), "failures": failures, "passed": failures == 0}))
	quit(0 if failures == 0 else 1)

# --- 等待 -------------------------------------------------------------------
func wait_until(predicate: Callable, limit: int, label: String = "") -> bool:
	for i: int in range(limit):
		await physics_frame
		clock += 1
		if watching: _watch_tick()
		if i % 300 == 0:
			print("SB_HB role=", role, " wait=", label, " frame=", i, "/", limit)
		if bool(predicate.call()): return true
	return false

# 等"主机已经把车停稳、镜像也追平"：不是等到某一帧 running=false 就算数。
# 判据：镜像与最后一份快照的距离差 < 2 cm 连续 45 帧（≈0.75 s）。停车后主机不再
# 产生新距离，所以这等价于两端收敛到同一个 distance。
func wait_settled(limit: int, label: String = "settled") -> bool:
	var stable: int = 0
	for i: int in range(limit):
		await physics_frame
		clock += 1
		if watching: _watch_tick()
		if i % 300 == 0:
			print("SB_HB role=", role, " wait=", label, " frame=", i, "/", limit)
		var gap: float = absf(float(cart.get("target_distance")) - float(cart.get("distance")))
		if gap < 0.02:
			stable += 1
			if stable >= 45: return true
		else:
			stable = 0
	return false

func board_deck() -> Dictionary:
	var leg: Dictionary = await steer(Vector3(1.0, DECK_TOP, 1.75), 900, 0.30, true)
	var l: Vector3 = cart.to_local(player.global_position)
	return {"ok": bool(leg.get("ok")) and player.is_on_floor() and l.y > 1.8,
		"leg": leg, "cart_local": [l.x, l.y, l.z], "on_floor": player.is_on_floor()}

func _actor(slot: int) -> CharacterBody3D:
	var actors: Dictionary = stage.get("actors") as Dictionary
	if not actors.has(slot): return null
	return actors[slot] as CharacterBody3D

func _braked(state: Dictionary) -> bool:
	if state.is_empty(): return false
	return not bool((state["cart"] as Dictionary)["running"]) or str((state["cart"] as Dictionary)["brake_reason"]) != ""

# =============================================================================
# 单人
# =============================================================================
func run_solo() -> void:
	var board: Dictionary = await board_deck()
	check(bool(board.get("ok")), "S1 单人以真实 WASD 走上甲板", board)
	if not bool(board.get("ok")): return
	await steer(Vector3(2.05, DECK_TOP, 1.70), 900, 0.30, true)
	await face(cart.to_global(Vector3(2.48, 2.64, 1.08)))
	await press("repair")
	check(bool(cart.get("running")), "S2 按 E 真实发车（关卡自己的发车路径）",
		{"running": cart.get("running"), "distance": cart.get("distance"),
		 "feedback": str(stage.get("feedback"))})
	if not bool(cart.get("running")): return
	watching = true
	# 正常乘坐窗口：5 秒
	var ride := await wait_until(func() -> bool: return float(cart.get("distance")) > 6.0, 600, "solo_ride")
	var ride_state: Dictionary = state_of()
	check(ride and bool((ride_state["cart"] as Dictionary)["running"]) and
		str((ride_state["cart"] as Dictionary)["brake_reason"]) == "",
		"S3 单人正常乘坐：矿车在跑且没有误制动",
		{"cart": ride_state["cart"], "me": ride_state["me"]})
	var ride_stats: Dictionary = summarise(ride_rows)
	check(float(ride_stats.get("on_floor_ratio", 0.0)) > 0.95 and
		float(ride_stats.get("min_clearance", -99.0)) > -0.05,
		"S4 单人乘坐物理无回归（在地面 + 脚底不穿甲板）", ride_stats)
	if scenario == "solo_leave":
		note("离车前状态（单人/主机本地角色）", state_of())
		var rev_before: int = int(cart.get("revision"))
		var off: Dictionary = await walk_off_deck(420)
		check(bool(off.get("left")), "S5 单人通过真实移动离开甲板（local_y < 1.5）", off)
		var braked: bool = await wait_until(func() -> bool: return not bool(cart.get("running")), 300, "solo_brake")
		var after: Dictionary = state_of()
		check(braked, "S6 单人离车后保护制动触发（running→false）",
			{"cart": after["cart"], "me": after["me"], "feedback": after["feedback"]})
		check(str((after["cart"] as Dictionary)["brake_reason"]) == SAFETY_REASON,
			"S7 制动原因 = driver_left_deck（关卡自己的保护制动）",
			{"brake_reason": (after["cart"] as Dictionary)["brake_reason"]})
		check(int(cart.get("revision")) - rev_before <= 2,
			"S8 只制动一次（没有因为速度/镜像抖动反复制动）",
			{"revision_before": rev_before, "revision_after": int(cart.get("revision")),
			 "brake_count": int(_stage_var("_safety_brake_count", -1))})
		await watch_frames(120)
	else:
		await press("cart_brake")
		check(str(cart.get("brake_reason")) == "player_brake",
			"S5 单人按 B 的原有制动行为不变（player_brake）",
			{"brake_reason": str(cart.get("brake_reason")), "running": cart.get("running")})
		await watch_frames(90)
	watching = false
	check(int((stage.get("actors") as Dictionary).size()) == 1, "S9 单人只有一个角色（没有多余 peer）",
		{"actors": _all_actor_rows(), "peers": get_multiplayer().get_peers().size()})

# =============================================================================
# 主机
# =============================================================================
func run_host() -> void:
	var host_mode: bool = await wait_until(func() -> bool:
		return str(coop.get("mode")) == "host", 600, "host_mode")
	check(host_mode, "H1 主机已开始监听", {"mode": str(coop.get("mode"))})
	if not host_mode: return
	var board: Dictionary = await board_deck()
	check(bool(board.get("ok")), "H2 主机以真实 WASD 走上甲板", board)
	if not bool(board.get("ok")): return
	# 让开登车口（近侧开口仅 0.96 m，站着会把客户端堵在踏步上）
	await steer(Vector3(2.05, DECK_TOP, 1.70), 900, 0.30, true)
	note("H2b 主机让开登车口并站到前端控制器旁", state_of())

	var joined: bool = await wait_until(func() -> bool:
		return (stage.get("actors") as Dictionary).has(2) and (coop.get("slots") as Dictionary).size() >= 2, 6000, "join")
	check(joined, "H3 客户端已加入且远程角色已生成",
		{"actors": _all_actor_rows(), "peers": get_multiplayer().get_peers().size(),
		 "slots": (coop.get("slots") as Dictionary).keys()})
	if not joined: return

	if scenario == "bystander":
		var stayed_off: bool = await wait_until(func() -> bool:
			var other: CharacterBody3D = _actor(2)
			return other != null and not bool(cart.call("contains_point", other.global_position)), 600, "bystander_off")
		check(stayed_off, "H4 旁观客户端没有上甲板（仍在登车平台）",
			{"all_actors": _all_actor_rows()})
	else:
		var client_on_deck: bool = await wait_until(func() -> bool:
			var other: CharacterBody3D = _actor(2)
			return other != null and bool(cart.call("contains_point", other.global_position)), 3000, "client_board")
		check(client_on_deck, "H4 主机确认客户端站上甲板（远程角色真实位置 + contains_point）",
			{"all_actors": _all_actor_rows()})
		if not client_on_deck: return

	await face(cart.to_global(Vector3(2.48, 2.64, 1.08)))
	await press("repair")
	var started: bool = bool(cart.get("running"))
	check(started, "H5 主机按 E 真实发车（主机权威）",
		{"running": cart.get("running"), "distance": cart.get("distance"),
		 "feedback": str(stage.get("feedback"))})
	if not started: return
	watching = true
	var moving: bool = await wait_until(func() -> bool:
		return float(cart.get("distance")) > 6.0 and float(cart.get("speed")) > 1.0, 900, "moving")
	check(moving, "H6 矿车真实行驶（distance>6 且 speed>1）",
		{"cart": state_of()["cart"], "all_actors": _all_actor_rows()})
	if not moving:
		watching = false
		return

	match scenario:
		"normal": await host_normal()
		"client_leave": await host_client_leave()
		"host_leave": await host_host_leave()
		"disconnect": await host_disconnect()
		"bystander": await host_bystander()

	watching = false
	# 等客户端退出，避免两端结果文件互相覆盖/提前结束
	await wait_until(func() -> bool: return get_multiplayer().get_peers().is_empty(), 2400, "client_left")

func host_normal() -> void:
	# 双人正常乘坐窗口：3 秒，不允许误制动
	await watch_frames(180)
	var riding: Dictionary = state_of()
	check(bool((riding["cart"] as Dictionary)["running"]) and
		str((riding["cart"] as Dictionary)["brake_reason"]) == "",
		"H7 双人正常乘坐 3 秒：没有误制动", {"cart": riding["cart"]})
	for row: Dictionary in riding["all_actors"]:
		check(bool(row["contains_point"]), "H7b 乘坐窗口内每位船员都在甲板上",
			{"slot": row["slot"], "cart_local": row["cart_local"]})
	# 客户端会在镜像 distance>12 时按 B（合法链路：请求→主机校验→执行）
	var braked: bool = await wait_until(func() -> bool: return not bool(cart.get("running")), 1800, "client_brake")
	var state: Dictionary = state_of()
	check(braked and str((state["cart"] as Dictionary)["brake_reason"]) == "player_brake",
		"H8 客户端的 B 制动请求被主机接受（brake_reason=player_brake）",
		{"cart": state["cart"], "rejected_actions": (state["net"] as Dictionary)["rejected_actions"]})
	await watch_frames(150)
	var final: Dictionary = state_of()
	var ride_stats: Dictionary = summarise(ride_rows)
	check(float(ride_stats.get("on_floor_ratio", 0.0)) > 0.90 and
		float(ride_stats.get("min_clearance", -99.0)) > -0.05,
		"H9 双人真实乘车物理无回归（主机在地面 + 脚底不穿甲板）", ride_stats)
	check(int((final["net"] as Dictionary)["rejected_poses"]) == 0 and
		int((final["net"] as Dictionary)["rejected_actions"]) == 0,
		"H10 没有新的网络异常（0 被拒位姿 / 0 被拒动作）", final["net"])
	note("制动后最终状态（主机权威）", final)

func host_client_leave() -> void:
	await watch_frames(60)
	# 客户端在 distance>10 时用真实 WASD 走下甲板；主机只负责观测
	var gone: bool = await wait_until(func() -> bool:
		var other: CharacterBody3D = _actor(2)
		if other == null: return false
		return float(cart.to_local(other.global_position).y) < 1.5, 1200, "client_left_deck")
	var observer: Dictionary = state_of()
	var other: CharacterBody3D = _actor(2)
	var other_local: Vector3 = cart.to_local(other.global_position) if other != null else Vector3.ZERO
	leave_observed = {
		"slot": 2, "client_local": [other_local.x, other_local.y, other_local.z],
		"client_contains_point": bool(cart.call("contains_point", other.global_position)) if other != null else false,
		"host_cart_speed": float(cart.get("speed")),
		"host_cart_running": bool(cart.get("running")),
		"host_cart_distance": float(cart.get("distance")),
		"host_own_local_y": float(cart.to_local(player.global_position).y),
		"guard_precondition_local_y_lt_1_5": other_local.y < 1.5,
		"guard_precondition_speed_gt_0_2": float(cart.get("speed")) > 0.2,
		"all_actors": observer["all_actors"],
	}
	check(gone, "H7 主机观测到客户端真实离开甲板（local_y < 1.5）", leave_observed)
	note("离车瞬间主机侧读数（距离/速度/位置）", leave_observed)
	var rev_before: int = int(cart.get("revision"))
	var braked: bool = await wait_until(func() -> bool: return not bool(cart.get("running")), 300, "safety_brake")
	var after: Dictionary = state_of()
	check(braked, "H8 客户端离车后主机触发保护制动（running→false）",
		{"cart": after["cart"], "feedback": after["feedback"]})
	check(str((after["cart"] as Dictionary)["brake_reason"]) == SAFETY_REASON,
		"H9 制动原因 = driver_left_deck",
		{"brake_reason": (after["cart"] as Dictionary)["brake_reason"]})
	check(int(cart.get("revision")) - rev_before <= 2,
		"H10 只制动一次（没有反复制动）",
		{"revision_before": rev_before, "revision_after": int(cart.get("revision")),
		 "brake_count": int(_stage_var("_safety_brake_count", -1))})
	await watch_frames(150)
	var final: Dictionary = state_of()
	check(int((final["net"] as Dictionary)["rejected_actions"]) == 0,
		"H11 客户端没有发起会被拒绝的制动请求（0 被拒动作）", final["net"])
	var security: Dictionary = final["security"] as Dictionary
	check(int(security["brake_count"]) == 1 and not bool(security["triggered"]) and
		not bool(security["armed"]),
		"H12 停车后保护制动状态已复位，且整趟只记录一次（不会反复制动）", security)
	note("保护制动后最终状态", final)

func host_host_leave() -> void:
	await watch_frames(60)
	note("离车前状态（主机本地角色）", state_of())
	var rev_before: int = int(cart.get("revision"))
	var off: Dictionary = await walk_off_deck(420)
	check(bool(off.get("left")), "H7 主机以真实移动离开甲板（local_y < 1.5）", off)
	var braked: bool = await wait_until(func() -> bool: return not bool(cart.get("running")), 300, "safety_brake")
	var after: Dictionary = state_of()
	check(braked, "H8 主机离车后保护制动触发（running→false）",
		{"cart": after["cart"], "feedback": after["feedback"]})
	check(str((after["cart"] as Dictionary)["brake_reason"]) == SAFETY_REASON,
		"H9 制动原因 = driver_left_deck", {"brake_reason": (after["cart"] as Dictionary)["brake_reason"]})
	check(int(cart.get("revision")) - rev_before <= 2, "H10 只制动一次",
		{"revision_before": rev_before, "revision_after": int(cart.get("revision"))})
	await watch_frames(150)
	note("保护制动后最终状态（主机）", state_of())

func host_disconnect() -> void:
	# 客户端在甲板上、矿车行驶中退出（模拟断线）
	await watch_frames(120)
	var riding: Dictionary = state_of()
	check(bool((riding["cart"] as Dictionary)["running"]), "H7 断线前矿车正常行驶",
		{"cart": riding["cart"], "actors": riding["all_actors"]})
	var gone: bool = await wait_until(func() -> bool:
		return get_multiplayer().get_peers().is_empty() and not (stage.get("actors") as Dictionary).has(2),
		1800, "peer_left")
	var at_gone: Dictionary = state_of()
	check(gone, "H8 客户端断线且远程角色已销毁（不会被当成离车）",
		{"peers": get_multiplayer().get_peers().size(), "actors": at_gone["all_actors"]})
	check(bool((at_gone["cart"] as Dictionary)["running"]) and
		str((at_gone["cart"] as Dictionary)["brake_reason"]) == "",
		"H9 断线瞬间没有误触发保护制动", {"cart": at_gone["cart"]})
	var dist_at_gone: float = float((at_gone["cart"] as Dictionary)["distance"])
	await watch_frames(180)
	var after: Dictionary = state_of()
	check(bool((after["cart"] as Dictionary)["running"]) and
		str((after["cart"] as Dictionary)["brake_reason"]) == "",
		"H10 断线后 3 秒仍无误制动（矿车继续行驶）", {"cart": after["cart"]})
	check(float((after["cart"] as Dictionary)["distance"]) - dist_at_gone > 2.0,
		"H11 断线后矿车继续前进",
		{"distance_gone": dist_at_gone, "distance_after": float((after["cart"] as Dictionary)["distance"])})
	check(int((stage.get("actors") as Dictionary).size()) == 1,
		"H12 只剩主机自己的角色（没有重复 peer / 幽灵角色）", {"all_actors": after["all_actors"]})
	# 主机自己仍可正常制动
	await press("cart_brake")
	check(str(cart.get("brake_reason")) == "player_brake",
		"H13 断线后主机仍可正常制动（原有行为）",
		{"brake_reason": str(cart.get("brake_reason")), "running": cart.get("running")})
	await watch_frames(90)
	note("断线场景最终状态", state_of())

func host_bystander() -> void:
	# 客户端已连接但从未上甲板：不是"离车"。窗口要比客户端的观测窗口长，
	# 避免主机自己的 B 制动与客户端的"仍在跑"断言重叠。
	await watch_frames(480)
	var riding: Dictionary = state_of()
	check(bool((riding["cart"] as Dictionary)["running"]) and
		str((riding["cart"] as Dictionary)["brake_reason"]) == "",
		"H7 已连接但未上车的玩家不会被误判为离车（8 秒无误制动）", {"cart": riding["cart"]})
	check(float((riding["cart"] as Dictionary)["distance"]) > 14.0,
		"H8 矿车正常行驶（未被旁观者干扰）", {"distance": (riding["cart"] as Dictionary)["distance"]})
	await press("cart_brake")
	check(str(cart.get("brake_reason")) == "player_brake", "H9 主机按 B 仍可正常制动",
		{"brake_reason": str(cart.get("brake_reason"))})
	await watch_frames(90)

# =============================================================================
# 客户端
# =============================================================================
func run_client() -> void:
	var ready: bool = await wait_until(func() -> bool:
		return str(coop.get("mode")) == "client" and int(coop.get("local_slot")) >= 2, 2400, "welcome")
	check(ready, "C1 客户端加入并拿到席位",
		{"mode": str(coop.get("mode")), "local_slot": int(coop.get("local_slot")),
		 "actors": _all_actor_rows(), "peers": get_multiplayer().get_peers().size()})
	if not ready: return

	if scenario == "bystander":
		# 只站在登车平台，不上甲板
		var running: bool = await wait_until(func() -> bool:
			return bool(cart.get("running")) and float(cart.get("distance")) > 8.0, 2400, "host_departed")
		var on_platform: bool = not bool(cart.call("contains_point", player.global_position))
		check(running and on_platform, "C2 旁观客户端未上甲板，主机正常发车",
			{"cart": state_of()["cart"], "me": state_of()["me"]})
		watching = true
		await watch_frames(180)
		check(bool(cart.get("running")), "C3 旁观者不算离车：镜像里矿车仍在跑",
			{"cart": state_of()["cart"]})
		var braked: bool = await wait_until(func() -> bool: return not bool(cart.get("running")), 900, "host_brake")
		var settled: bool = await wait_settled(900, "settle_bystander")
		var st: Dictionary = state_of()
		var bgap: float = absf(float((st["cart"] as Dictionary)["target_distance"]) -
			float((st["cart"] as Dictionary)["distance"]))
		check(braked and settled and bgap < 0.05, "C4 主机手动制动同步到客户端并停稳",
			{"cart": st["cart"], "gap": bgap})
		watching = false
		return

	var board: Dictionary = await board_deck()
	check(bool(board.get("ok")), "C2 客户端以真实 WASD 走上甲板", board)
	if not bool(board.get("ok")): return

	if scenario == "disconnect":
		var moving: bool = await wait_until(func() -> bool:
			return bool(cart.get("running")) and float(cart.get("distance")) > 10.0, 2400, "cart_moving")
		check(moving, "C3 客户端在甲板上确认矿车行驶",
			{"cart": state_of()["cart"], "me": state_of()["me"]})
		note("客户端在行驶中的甲板上主动退出（模拟断线，从未写共享状态）", state_of())
		write_outputs()
		print("SB_CLIENT_EXIT_WHILE_RIDING ", float(cart.get("distance")))
		print("SB_RESULT ", JSON.stringify({"role": role, "scenario": scenario,
			"checks": checks.size(), "failures": failures, "passed": failures == 0}))
		quit(0)
		return

	watching = true
	var moving: bool = await wait_until(func() -> bool:
		return bool(cart.get("running")) and float(cart.get("distance")) > 6.0, 2400, "cart_moving")
	var moving_state: Dictionary = state_of()
	check(moving, "C3 客户端从镜像确认矿车已发车（running=true）",
		{"cart": moving_state["cart"], "me": moving_state["me"]})
	if not moving:
		watching = false
		return
	# 根因证据：客户端镜像只更新 mirror_speed，cart.speed 恒为 0（修复前）
	note("客户端速度镜像读数", {"cart_speed": (moving_state["cart"] as Dictionary)["speed"],
		"mirror_speed": (moving_state["cart"] as Dictionary)["mirror_speed"],
		"distance": (moving_state["cart"] as Dictionary)["distance"]})
	await watch_frames(90)

	match scenario:
		"normal": await client_normal()
		"client_leave": await client_leave()
		"host_leave": await client_host_leave()

	watching = false
	await frames(30)

func client_normal() -> void:
	# 等镜像 distance > 12 再按 B：客户端只能依据自己镜像到的距离
	var far: bool = await wait_until(func() -> bool: return float(cart.get("distance")) > 12.0, 1200, "distance12")
	check(far, "C4 客户端镜像距离越过 12 m（随后按 B 真实制动）",
		{"distance": float(cart.get("distance"))})
	await press("cart_brake")
	var stopped: bool = await wait_until(func() -> bool: return not bool(cart.get("running")), 900, "brake_mirror")
	var state: Dictionary = state_of()
	check(stopped and str((state["cart"] as Dictionary)["brake_reason"]) == "player_brake",
		"C5 按 B → 主机接受 → 镜像 brake_reason=player_brake",
		{"cart": state["cart"], "last_action_ok": stage.get("last_action_ok"),
		 "feedback": state["feedback"]})
	var ride_stats: Dictionary = summarise(ride_rows)
	check(float(ride_stats.get("on_floor_ratio", 0.0)) > 0.90 and
		float(ride_stats.get("min_clearance", -99.0)) > -0.05,
		"C6 客户端在镜像甲板上乘坐（在地面 + 脚底不穿甲板）", ride_stats)
	check(float(ride_stats.get("drift_m", 99.0)) < 0.60,
		"C7 客户端相对甲板没有明显滑动（< 60 cm）", {"drift_m": ride_stats.get("drift_m")})
	var converged: bool = await wait_settled(900, "settle_normal")
	var final: Dictionary = state_of()
	var gap: float = absf(float((final["cart"] as Dictionary)["target_distance"]) -
		float((final["cart"] as Dictionary)["distance"]))
	check(converged and gap < 0.05, "C8 客户端镜像距离与主机快照收敛（停稳后两端 distance 一致）",
		{"distance": (final["cart"] as Dictionary)["distance"],
		 "target_distance": float(cart.get("target_distance")), "gap": gap})
	note("制动后最终状态（客户端镜像）", final)

func client_leave() -> void:
	var far: bool = await wait_until(func() -> bool: return float(cart.get("distance")) > 10.0, 1200, "distance10")
	check(far, "C4 客户端在行驶中（镜像 distance>10）", {"distance": float(cart.get("distance"))})
	var off: Dictionary = await walk_off_deck(420)
	check(bool(off.get("left")), "C5 客户端通过真实移动离开合法甲板区域（local_y < 1.5）", off)
	note("离车瞬间客户端读数", state_of())
	var braked: bool = await wait_until(func() -> bool: return not bool(cart.get("running")), 600, "host_safety_brake")
	var state: Dictionary = state_of()
	check(braked, "C6 主机保护制动同步到客户端（running→false）",
		{"cart": state["cart"], "me": state["me"]})
	check(str((state["cart"] as Dictionary)["brake_reason"]) == SAFETY_REASON,
		"C7 客户端镜像到的制动原因 = driver_left_deck",
		{"brake_reason": (state["cart"] as Dictionary)["brake_reason"]})
	var ride_stats: Dictionary = summarise(ride_rows)
	note("客户端乘坐统计（含离车瞬间）", ride_stats)
	check(float(ride_stats.get("on_floor_ratio", 0.0)) > 0.60,
		"C8 离车前客户端确实站在（镜像）甲板上", {"on_floor_ratio": ride_stats.get("on_floor_ratio")})
	var converged: bool = await wait_settled(900, "settle_client_leave")
	var final: Dictionary = state_of()
	var gap: float = absf(float((final["cart"] as Dictionary)["target_distance"]) -
		float((final["cart"] as Dictionary)["distance"]))
	check(converged and gap < 0.05, "C9 客户端镜像距离收敛到主机快照（两端制动状态一致）",
		{"distance": (final["cart"] as Dictionary)["distance"],
		 "target_distance": float(cart.get("target_distance")), "gap": gap,
		 "brake_reason": (final["cart"] as Dictionary)["brake_reason"]})
	note("保护制动后最终状态（客户端镜像）", final)

func client_host_leave() -> void:
	# 客户端留在甲板上，等主机的保护制动到达快照
	var braked: bool = await wait_until(func() -> bool: return not bool(cart.get("running")), 1200, "host_safety_brake")
	var state: Dictionary = state_of()
	check(braked, "C4 主机离车后保护制动同步到客户端（running→false）",
		{"cart": state["cart"], "me": state["me"]})
	check(str((state["cart"] as Dictionary)["brake_reason"]) == SAFETY_REASON,
		"C5 客户端镜像到的制动原因 = driver_left_deck",
		{"brake_reason": (state["cart"] as Dictionary)["brake_reason"]})
	var ride_stats: Dictionary = summarise(ride_rows)
	check(float(ride_stats.get("on_floor_ratio", 0.0)) > 0.90 and
		float(ride_stats.get("min_clearance", -99.0)) > -0.05,
		"C6 主机离车时客户端仍在甲板上正常乘坐", ride_stats)
	var converged: bool = await wait_settled(900, "settle_host_leave")
	var final: Dictionary = state_of()
	var gap: float = absf(float((final["cart"] as Dictionary)["target_distance"]) -
		float((final["cart"] as Dictionary)["distance"]))
	check(converged and gap < 0.05, "C7 客户端镜像距离收敛到主机快照（两端制动状态一致）",
		{"distance": (final["cart"] as Dictionary)["distance"],
		 "target_distance": float(cart.get("target_distance")), "gap": gap})
	note("保护制动后最终状态（客户端镜像）", final)

# =============================================================================
func run() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("SB_PROBE_START role=", role, " scenario=", scenario, " port=", port, " out=", out_dir)
	await frames(2)
	stage = current_scene.get_node_or_null("MovingCartSlice") as Node3D
	if stage == null:
		push_error("SB_PROBE no MovingCartSlice")
		quit(1)
		return
	cart = stage.get("cart") as AnimatableBody3D
	player = stage.get("player") as CharacterBody3D
	flow = stage.get("flow")
	coop = stage.get("coop")
	await frames(40)
	note("启动状态", state_of())
	match role:
		"host": await run_host()
		"client": await run_client()
		_: await run_solo()
	await finish()
