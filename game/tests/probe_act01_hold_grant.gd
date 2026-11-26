extends SceneTree

## Act01 hold-grant focused two-process probe.
##
## Scope: only the integrated Act01 hold-authorization path
## (`CoopNet.act1_grant_hold` / `Act1NetFacade.send_grant`) plus the door
## begin/end request path. The probe uses the official Launcher and real ENet,
## and drives the player with real input actions only. It never writes a flag,
## never calls complete_chapter/change_scene, and never teleports.
##
## Role host: prepares the entry (debris/latch/rail) and observes the
## authoritative door/cart state while the client performs both holds.
## Role client: opens the door by holding E, then grips/pushes/releases the
## power cart. A final re-grip followed by `CoopNet.shutdown()` is the
## abnormal-interruption case.

const HOST_BUTTON := "创建主机（等待队友加入）"
const CLIENT_BUTTON := "加入主机（本机 127.0.0.1）"

var role: String = "host"
var out_dir: String = ""
var tag: String = ""
var port: int = 9931
var entry: String = "direct"
var scenario: String = "full"

var checks: int = 0
var failures: Array[String] = []
var warnings: Array[String] = []
var log_lines: Array[String] = []
var stages: Array[Dictionary] = []
var started_msec: int = 0

var stage: Node = null
var player: Node = null
var _last_scene_id: int = 0
var _finished: bool = false

# Client-only observations used by the host/report when interpreting timeouts.
var client_grant_applied: bool = false
var client_cart_attempts: int = 0
var client_shutdown_sent: bool = false


func _initialize() -> void:
	_parse_args()
	started_msec = Time.get_ticks_msec()
	_watchdog.call_deferred()
	_run.call_deferred()


func _parse_args() -> void:
	var all: Array[String] = []
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	for a in all:
		var s := str(a)
		if s.begins_with("--role="):
			role = s.split("=")[1]
		elif s.begins_with("--out="):
			out_dir = s.split("=")[1]
		elif s.begins_with("--tag="):
			tag = s.split("=")[1]
		elif s.begins_with("--port="):
			port = int(s.split("=")[1])
		elif s.begins_with("--entry="):
			entry = s.split("=")[1]
		elif s.begins_with("--scenario="):
			scenario = s.split("=")[1]


func _watchdog() -> void:
	await create_timer(900.0).timeout
	push_error("HOLD_PROBE_WATCHDOG role=%s" % role)
	_finish(false)


func _process(_delta: float) -> bool:
	var cs: Node = current_scene
	var id: int = cs.get_instance_id() if cs != null else 0
	if id != _last_scene_id:
		_last_scene_id = id
		log_line("SCENE %s" % (str(cs.name) if cs != null else "null"))
	return false


# ---------------------------------------------------------------------------
# logging / checks
# ---------------------------------------------------------------------------
func log_line(text: String) -> void:
	print("[%s] %s" % [role, text])
	log_lines.append(text)


func check(ok: bool, text: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)
	return ok


func note(text: String) -> void:
	log_line("NOTE " + text)


func warn(text: String) -> void:
	log_line("WARN " + text)
	warnings.append(text)


func _record(name: String, payload: Dictionary) -> void:
	var entry: Dictionary = {"stage": name, "t_ms": Time.get_ticks_msec() - started_msec}
	for key in payload.keys():
		entry[key] = payload[key]
	stages.append(entry)
	log_line("RECORD %s %s" % [name, JSON.stringify(payload)])


# ---------------------------------------------------------------------------
# generic waits / launcher input
# ---------------------------------------------------------------------------
func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited := 0.0
	while waited < timeout_s:
		if bool(cond.call()):
			return true
		await create_timer(0.1).timeout
		waited += 0.1
	return bool(cond.call())


func _wait_scene(name: String, timeout_s: float = 30.0) -> bool:
	return await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == name, timeout_s)


func _find_button_by_text(text: String, from: Node) -> Button:
	if from == null:
		return null
	for n in from.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if b != null and b.text == text:
			return b
	return null


func _click_button(btn: Button) -> bool:
	if btn == null:
		return false
	var vp: Window = get_root()
	for _i in range(3):
		await physics_frame
	await _wait(0.25)
	var canvas_size: Vector2 = vp.get_visible_rect().size
	var window_size: Vector2 = vp.size
	var rect: Rect2 = btn.get_global_rect()
	if rect.size == Vector2.ZERO:
		return false
	var scale_v := Vector2(window_size.x / maxf(canvas_size.x, 1.0),
		window_size.y / maxf(canvas_size.y, 1.0))
	var click: Vector2 = rect.get_center() * scale_v
	var motion := InputEventMouseMotion.new()
	motion.position = click
	motion.global_position = click
	vp.push_input(motion)
	await _wait(0.12)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click
	press.global_position = click
	vp.push_input(press)
	await _wait(0.10)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click
	release.global_position = click
	vp.push_input(release)
	await _wait(0.30)
	return true


# ---------------------------------------------------------------------------
# session / Act01 readers
# ---------------------------------------------------------------------------
func _net() -> Node:
	var hub: Node = root.get_node_or_null("/root/SessionHub")
	if hub == null:
		return null
	return hub.get("net") as Node


func _peers() -> int:
	var n: Node = _net()
	if n == null:
		return 0
	return int(n.call("peer_count"))


func _local_pid() -> int:
	var n: Node = _net()
	if n == null:
		return 0
	var v: Variant = n.get("local_pid")
	return int(v) if v != null else 0


func _bound() -> bool:
	var n: Node = _net()
	return n != null and bool(n.get("_act1_bootstrapped"))


func _flags() -> Dictionary:
	if stage == null:
		return {}
	return stage.get("flags") as Dictionary


func _hold_owner() -> Dictionary:
	if stage == null:
		return {}
	return stage.get("hold_owner") as Dictionary


## Act1StationBuilder extends RefCounted, not Node: keep these as untyped
## Variant handles so `.get("open_amount")` / `.global_position` resolve at
## runtime instead of a failed `as Node` cast returning null.
func _builder() -> Variant:
	if stage == null:
		return null
	return stage.get("builder")


func _door() -> Variant:
	var b: Variant = _builder()
	return b.get("door") if b != null else null


func _cart() -> Variant:
	var b: Variant = _builder()
	return b.get("power_cart") if b != null else null


func _cart_operator() -> int:
	return int(stage.get("cart_operator")) if stage != null else 0


func _door_amount() -> float:
	var d: Variant = _door()
	return float(d.get("open_amount")) if d != null else -1.0


func _cart_x() -> float:
	var c: Variant = _cart()
	return float(c.global_position.x) if c != null else 0.0


func _cart_velocity() -> float:
	var c: Variant = _cart()
	return float(c.get("velocity")) if c != null else 0.0


func _external_hold() -> bool:
	return bool(player.get("external_hold")) if player != null else false


func _attached_to_cart() -> bool:
	return player != null and player.get("attached_to") == _cart()


# ---------------------------------------------------------------------------
# Act01 movement / interaction (real input only)
# ---------------------------------------------------------------------------
func _face(target: Vector3) -> void:
	if not is_instance_valid(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("yaw", yaw)
	player.rotation.y = yaw


func _walk(target: Vector3, seconds: float, label := "", arrive := 0.60) -> void:
	if not is_instance_valid(player):
		return
	var start: Vector3 = player.global_position
	_face(target)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var frames: int = int(seconds * 60.0)
	for _i in range(frames):
		await physics_frame
		if not is_instance_valid(player) or current_scene != stage:
			break
		_face(target)
		if Vector2(player.global_position.x - target.x,
				player.global_position.z - target.z).length() < arrive:
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await physics_frame
	if is_instance_valid(player):
		log_line("WALK01 %s target=%s pos=%s moved=%.2f" % [
			label, str(target.snapped(Vector3(0.01, 0.01, 0.01))),
			str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
			player.global_position.distance_to(start)])


func _aim(id: String) -> String:
	if stage == null or player == null:
		return "missing-stage"
	var points: Dictionary = stage.get("interactables") as Dictionary
	if not points.has(id):
		return "missing"
	var point: Node3D = points[id] as Node3D
	if point == null:
		return "null"
	player.call("look_at_point", point.global_position)
	await _wait(0.22)
	if player.get("current_target") == null:
		return "none"
	return str((player.get("current_target") as Object).get("interaction_id"))


func _press_interact(seconds: float) -> void:
	Input.action_press("interact")
	await _wait(seconds)
	Input.action_release("interact")
	await _wait(0.30)


func _press_until(id: String, flag: String, attempts: int) -> bool:
	for _i in range(attempts):
		if bool(_flags().get(flag, false)):
			return true
		var found: String = await _aim(id)
		if found != id:
			log_line("AIM01 %s -> %s (retry)" % [id, found])
			await _wait(0.8)
			continue
		await _press_interact(0.12)
		await _wait(0.6)
	return bool(_flags().get(flag, false))


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 1800:
		await physics_frame
		guard += 1
	var launcher: Node = current_scene
	if launcher == null or str(launcher.name) != "Launcher":
		check(false, "booted into the official Launcher")
		_finish(false)
		return
	check(true, "booted into the official Launcher")

	var button_text: String = HOST_BUTTON if role == "host" else CLIENT_BUTTON
	var btn: Button = null
	guard = 0
	while btn == null and guard < 800:
		await _wait(0.05)
		btn = _find_button_by_text(button_text, launcher)
		guard += 1
	check(btn != null, "Launcher built the '%s' button" % button_text)
	if btn == null:
		_finish(false)
		return

	if entry == "launcher":
		# Official path: real mouse click on the Launcher button (fixed port 9877).
		check(port == 9877, "Launcher entry uses the fixed port 9877 (port=%d)" % port)
		await _click_button(btn)
		check(await _wait_scene("Act01", 60.0), "real Launcher click entered Act01")
	else:
		# Isolated entry for machines where another task owns 9877: the same
		# real ENet peer and the same Act01 scene, started through the same
		# SessionHub entry the button calls. No product file is changed.
		var hub: Node = root.get_node_or_null("/root/SessionHub")
		check(hub != null, "SessionHub autoload exists")
		var err: int = -1
		if hub != null:
			if role == "host":
				err = int(hub.call("start", true, port))
			else:
				err = int(hub.call("start", false, port, "127.0.0.1"))
		check(err == OK, "real ENet %s started on port %d (err=%d)" % [role, port, err])
		if err != OK:
			_finish(false)
			return
		change_scene_to_file("res://act1/act01.tscn")
		check(await _wait_scene("Act01", 60.0), "Act01 scene loaded after the real session start")
	if current_scene == null or str(current_scene.name) != "Act01":
		_finish(false)
		return
	stage = current_scene
	player = stage.get("local_player") as Node
	check(player != null, "Act01 local player exists")
	if player == null:
		_finish(false)
		return
	await _wait(1.2)
	log_line("ACT01_READY role=%s pid=%d peers=%d" % [role, _local_pid(), _peers()])

	var ok := false
	if scenario == "door_abort":
		if role == "host":
			ok = await _host_door_abort()
		else:
			ok = await _client_door_abort()
	elif role == "host":
		ok = await _host_flow()
	else:
		ok = await _client_flow()
	_finish(ok and failures.is_empty())


# ---------------------------------------------------------------------------
# door abnormal interruption scenario (door is a begin/end request, not a grant)
# ---------------------------------------------------------------------------
func _host_door_abort() -> bool:
	check(_local_pid() == 1, "host local_pid == 1 (got %d)" % _local_pid())
	var joined: bool = await _wait_until(func() -> bool: return _peers() >= 2, 900.0)
	check(joined, "host sees the client peer join (peers=%d)" % _peers())
	if not joined:
		return false
	var seated: bool = await _wait_until(func() -> bool:
		return (stage.get("active_pids") as Dictionary).has(2), 180.0)
	check(seated, "host registered the client seat (active=%s)" % str((stage.get("active_pids") as Dictionary).keys()))
	if not seated:
		return false
	await _walk(Vector3(0, 0, 12.0), 8.0, "entry approach")
	await _walk(Vector3(0, 0, 10.6), 2.0, "door rail")
	var debris: bool = await _press_until("shove_gantry", "debris_cleared", 8)
	check(debris, "host cleared the collapsed gantry")
	await _walk(Vector3(3.1, 0, 10.35), 3.0, "latch side")
	var latch: bool = await _press_until("release_latch", "latch_released", 6)
	check(latch, "host released the mechanical latch")
	if not debris or not latch:
		return false

	var pusher: int = int(_door().get("pusher_pid"))
	var began: bool = await _wait_until(func() -> bool:
		return int(_door().get("pusher_pid")) == 2 or _door_amount() > 0.05, 240.0)
	var amount_at_disconnect: float = _door_amount()
	check(began, "client door hold reached the host (pusher=%d amount=%.3f)" % [pusher, amount_at_disconnect])
	_record("host_door_abort_begin", {"pusher": int(_door().get("pusher_pid")),
		"amount": amount_at_disconnect, "hold_owner": _hold_owner().duplicate(true)})
	if not began:
		return false

	var gone: bool = await _wait_until(func() -> bool:
		return not (stage.get("active_pids") as Dictionary).has(2), 240.0)
	check(gone, "host observed the client disconnect while pushing the door")
	await _wait(1.0)
	var pusher_after: int = int(_door().get("pusher_pid"))
	var amount_after: float = _door_amount()
	var stopped: bool = absf(amount_after - amount_at_disconnect) < 0.08
	var owner_clear: bool = not _hold_owner().has("door_handle")
	check(pusher_after == 0, "disconnect cleared the door pusher (pusher=%d)" % pusher_after)
	check(owner_clear, "disconnect cleared hold_owner[door_handle]")
	check(stopped, "door stopped after the client disconnect (amount %.3f -> %.3f)" % [
		amount_at_disconnect, amount_after])
	_record("host_door_abort_release", {"pusher": pusher_after, "amount": amount_after,
		"stopped": stopped, "hold_owner": _hold_owner().duplicate(true)})
	return pusher_after == 0 and owner_clear and stopped


func _client_door_abort() -> bool:
	var online: bool = await _wait_until(func() -> bool: return _peers() >= 2, 1200.0)
	check(online, "client connected to the host peer (peers=%d)" % _peers())
	if not online:
		return false
	var seated: bool = await _wait_until(func() -> bool: return _local_pid() == 2, 180.0)
	check(seated, "client was seated as pid 2 (local_pid=%d)" % _local_pid())
	var boot: bool = await _wait_until(func() -> bool: return _bound(), 180.0)
	check(boot, "client applied the authoritative bootstrap")
	if not seated or not boot:
		return false
	await _walk(Vector3(0, 0, 12.0), 8.0, "entry approach")
	await _walk(Vector3(1.0, 0, 10.0), 3.0, "door front")

	var holding := false
	for _attempt in range(10):
		var found: String = await _aim("door_handle")
		if found != "door_handle":
			await _wait(0.8)
			continue
		Input.action_press("interact")
		var opened: bool = await _wait_until(func() -> bool: return _door_amount() > 0.05, 3.0)
		if opened:
			holding = true
			break
		Input.action_release("interact")
		await _wait(0.8)
	check(holding, "client held the door (amount=%.3f)" % _door_amount())
	if not holding:
		await _client_disconnect()
		return false
	_record("client_door_abort_hold", {"amount": _door_amount(),
		"pusher": int(_door().get("pusher_pid"))})
	# Abnormal: shut the peer down with E still held; no `end` request is sent.
	client_shutdown_sent = true
	var n: Node = _net()
	if n != null and n.has_method("shutdown"):
		n.call("shutdown")
	log_line("CLIENT_ABNORMAL_SHUTDOWN while holding door amount=%.3f" % _door_amount())
	await _wait(1.2)
	return true


# ---------------------------------------------------------------------------
# host
# ---------------------------------------------------------------------------
func _host_flow() -> bool:
	check(_local_pid() == 1, "host local_pid == 1 (got %d)" % _local_pid())
	var joined: bool = await _wait_until(func() -> bool: return _peers() >= 2, 900.0)
	check(joined, "host sees the client peer join (peers=%d)" % _peers())
	if not joined:
		return false
	var seated: bool = await _wait_until(func() -> bool:
		return (stage.get("active_pids") as Dictionary).has(2), 180.0)
	check(seated, "host registered the client seat (active=%s)" % str((stage.get("active_pids") as Dictionary).keys()))
	if not seated:
		return false

	# Entry setup: debris, latch. The client opens the door and pushes the cart.
	await _walk(Vector3(0, 0, 12.0), 8.0, "entry approach")
	await _walk(Vector3(0, 0, 10.6), 2.0, "door rail")
	var debris: bool = await _press_until("shove_gantry", "debris_cleared", 8)
	check(debris, "host cleared the collapsed gantry by a real physical shove")
	await _walk(Vector3(3.1, 0, 10.35), 3.0, "latch side")
	var latch: bool = await _press_until("release_latch", "latch_released", 6)
	check(latch, "host released the mechanical latch")
	_record("host_entry_ready", {"debris": debris, "latch": latch,
		"pos": str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))})

	# The client's door hold begins here; it is a begin/end request path, not a
	# hold grant. Host authority opens the door as the client keeps E down.
	var door_start: float = _door_amount()
	# `flags.door_open` is only raised when open_amount reaches exactly 1.0
	# (`on_door_opened`), so the host waits for the flag, not a 0.99 estimate.
	var door_open: bool = await _wait_until(func() -> bool:
		return bool(_flags().get("door_open", false)), 240.0)
	check(door_open, "client-held door opened (amount %.3f -> %.3f, door_open=%s)" % [
		door_start, _door_amount(), str(_flags().get("door_open", false))])
	_record("host_door", {"opened": door_open, "amount": _door_amount(),
		"hold_owner": _hold_owner().duplicate(true)})
	if not door_open:
		return false

	# Walk through the open doorway to the rail bracket (real movement only).
	await _walk(Vector3(0, 0, 6.5), 3.0, "through doorway")
	check(player.global_position.z < 8.0, "host walked through the open doorway")
	await _walk(Vector3(0, 0, 4.0), 2.5, "airlock exit")
	await _walk(Vector3(-3.0, 0, 0.4), 3.0, "power room west")
	await _walk(Vector3(-7.8, 0, 0.4), 3.5, "power room north")
	await _walk(Vector3(-4.6, 0, -0.4), 2.6, "around cart north")
	await _walk(Vector3(-1.0, 0, -0.5), 3.5, "rail bracket")
	await _walk(Vector3(-0.95, 0, -1.15), 1.4, "bracket approach")
	var rail: bool = await _press_until("rail_shove", "rail_cleared", 6)
	check(rail, "host cleared the rail bracket (cart path free)")
	_record("host_rail_ready", {"rail_cleared": rail,
		"pos": str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))})
	if not rail:
		return false

	# Wait for the client's cart_push begin. The host accepts it even when the
	# client-side grant is broken; the operator set alone is not proof of a grant.
	var op: bool = await _wait_until(func() -> bool: return _cart_operator() == 2, 300.0)
	check(op, "host accepted client cart_push begin (cart_operator=%d)" % _cart_operator())
	check(_hold_owner().get("cart_push", 0) == 2,
		"host recorded hold_owner[cart_push]=2 for the client (got %s)" % str(_hold_owner().get("cart_push", 0)))
	_record("host_cart_begin", {"operator": _cart_operator(),
		"power_cart_operator": int(_cart().get("operator_pid")),
		"hold_owner": _hold_owner().duplicate(true),
		"cart_x": _cart_x()})
	if not op:
		return false

	# The client is holding E and pressing W. The cart only moves if the client
	# actually received the grant, because `cart_axis` is gated on external_hold.
	var x0: float = _cart_x()
	var moved: bool = await _wait_until(func() -> bool:
		return absf(_cart_x() - x0) > 0.15, 180.0)
	var x1: float = _cart_x()
	check(moved, "cart moved from client W while the grant was held (x %.2f -> %.2f)" % [x0, x1])
	_record("host_cart_sustained", {"moved": moved, "x0": x0, "x1": x1,
		"operator": _cart_operator(), "velocity": _cart_velocity()})

	# Release E: the host must clear the operator and the cart must brake.
	var released: bool = await _wait_until(func() -> bool: return _cart_operator() == 0, 180.0)
	check(released, "host cleared the cart operator after client release (operator=%d)" % _cart_operator())
	var stop_x: float = _cart_x()
	await _wait(2.0)
	var stopped: bool = absf(_cart_x() - stop_x) < 0.08 and absf(_cart_velocity()) < 0.20
	check(stopped, "cart stopped after release (x %.2f -> %.2f, vel %.2f)" % [stop_x, _cart_x(), _cart_velocity()])
	_record("host_cart_released", {"released": released, "stopped": stopped,
		"operator": _cart_operator(), "hold_owner": _hold_owner().duplicate(true),
		"cart_x": _cart_x(), "velocity": _cart_velocity()})

	# Abnormal interruption: the client re-grips and then shuts its peer down
	# without sending an end request. The host must release the claim/operator.
	if moved and released:
		var regrip: bool = await _wait_until(func() -> bool: return _cart_operator() == 2, 300.0)
		check(regrip, "host accepted the client re-grip (cart_operator=%d)" % _cart_operator())
		_record("host_cart_regrip", {"regrip": regrip, "operator": _cart_operator(),
			"hold_owner": _hold_owner().duplicate(true)})
		if regrip:
			var gone: bool = await _wait_until(func() -> bool:
				return not (stage.get("active_pids") as Dictionary).has(2), 300.0)
			check(gone, "host observed the client disconnect while holding")
			await _wait(1.5)
			var clean: bool = _cart_operator() == 0 \
				and int(_cart().get("operator_pid")) == 0 \
				and not _hold_owner().has("cart_push") \
				and absf(_cart_velocity()) < 0.40
			check(clean, "disconnect released the cart hold (operator=%d cart_op=%d hold_owner=%s vel=%.2f)" % [
				_cart_operator(), int(_cart().get("operator_pid")),
				str(_hold_owner().keys()), _cart_velocity()])
			_record("host_disconnect_release", {"clean": clean, "operator": _cart_operator(),
				"power_cart_operator": int(_cart().get("operator_pid")),
				"hold_owner": _hold_owner().duplicate(true), "velocity": _cart_velocity()})
		else:
			warn("re-grip timeout; abnormal disconnect not exercised")
	else:
		warn("cart never moved / was never released; abnormal disconnect not exercised")
		# Still wait for the client to leave so the host report is complete.
		await _wait_until(func() -> bool:
			return not (stage.get("active_pids") as Dictionary).has(2), 300.0)

	_record("host_final", {"pid": _local_pid(), "peers": _peers(),
		"door": _door_amount(), "cart_x": _cart_x(), "operator": _cart_operator(),
		"hold_owner": _hold_owner().duplicate(true), "flags": _flags().duplicate(true)})
	return true


# ---------------------------------------------------------------------------
# client
# ---------------------------------------------------------------------------
func _client_flow() -> bool:
	var online: bool = await _wait_until(func() -> bool: return _peers() >= 2, 1200.0)
	check(online, "client connected to the host peer (peers=%d)" % _peers())
	if not online:
		return false
	var seated: bool = await _wait_until(func() -> bool: return _local_pid() == 2, 180.0)
	check(seated, "client was seated as pid 2 (local_pid=%d)" % _local_pid())
	var boot: bool = await _wait_until(func() -> bool: return _bound(), 180.0)
	check(boot, "client applied the authoritative bootstrap")
	if not seated or not boot:
		return false

	# --- door: real begin/end hold, host-authoritative open -----------------
	await _walk(Vector3(0, 0, 12.0), 8.0, "entry approach")
	await _walk(Vector3(1.0, 0, 10.0), 3.0, "door front")
	var door_seen := false
	var stopped_after_release := false
	for attempt in range(8):
		var found: String = await _aim("door_handle")
		log_line("AIM01 door_handle -> %s attempt=%d amount=%.2f" % [found, attempt + 1, _door_amount()])
		if found != "door_handle":
			await _wait(1.0)
			continue
		var before: float = _door_amount()
		Input.action_press("interact")
		await _wait(0.8)
		var during: float = _door_amount()
		Input.action_release("interact")
		await _wait(0.4)
		var after: float = _door_amount()
		if during > before + 0.03:
			door_seen = true
			check(true, "client door hold opened the door (amount %.2f -> %.2f)" % [before, during])
			await _wait(0.8)
			stopped_after_release = absf(_door_amount() - after) < 0.04
			check(stopped_after_release, "door stopped opening after the client released E (amount %.2f -> %.2f)" % [after, _door_amount()])
			break
		await _wait(1.0)
	check(door_seen, "client door begin/end path was accepted by the host")
	if not door_seen:
		warn("door hold never opened; cart test will likely be blocked")
		_record("client_door", {"door_seen": false, "amount": _door_amount()})
		await _client_disconnect()
		return false

	# Finish opening the door by holding E; host authority advances open_amount.
	# Aim once and keep the same `holding_target`; the handle itself moves with
	# the door, so re-aiming mid-hold is both unnecessary and fragile. Hold until
	# the authoritative `door_open` flag (exact 1.0), not a 0.99 float estimate.
	if not bool(_flags().get("door_open", false)):
		var found2: String = await _aim("door_handle")
		log_line("AIM01 door_handle finish -> %s amount=%.3f" % [found2, _door_amount()])
		if found2 == "door_handle":
			Input.action_press("interact")
			await _wait_until(func() -> bool:
				return bool(_flags().get("door_open", false)) or _door_amount() >= 1.0, 14.0)
			Input.action_release("interact")
			await _wait(0.4)
	var door_fully_open: bool = bool(_flags().get("door_open", false)) or _door_amount() >= 1.0
	check(door_fully_open, "client held the door fully open (amount=%.3f door_open=%s)" % [
		_door_amount(), str(_flags().get("door_open", false))])
	_record("client_door", {"door_seen": door_seen, "stopped": stopped_after_release,
		"amount": _door_amount(), "flags_door_open": bool(_flags().get("door_open", false))})

	# --- cart: walk to the handle through the opened doorway ----------------
	await _walk(Vector3(0, 0, 6.5), 3.0, "through doorway")
	await _walk(Vector3(0, 0, 4.0), 2.5, "airlock exit")
	await _walk(Vector3(-3.0, 0, 0.4), 3.0, "power room west")
	await _walk(Vector3(-7.8, 0, 0.4), 3.5, "power room north")
	await _walk(Vector3(-8.0, 0, -2.5), 2.0, "cart rear")
	await _walk(Vector3(-7.2, 0, -2.55), 1.0, "cart handle")

	# Let the host finish clearing the rail and enter its operator watch before
	# the client grips. Without this the first W burst can happen before the
	# host records its baseline, making a correct hold look like "no movement".
	var rail_seen: bool = await _wait_until(func() -> bool:
		return bool(_flags().get("rail_cleared", false)), 240.0)
	note("client sees rail_cleared=%s before cart grip" % str(rail_seen))
	await _wait(3.0)

	var attached := false
	var moves := 0
	var x_before := 0.0
	var x_after := 0.0
	for attempt in range(12):
		client_cart_attempts += 1
		var found: String = await _aim("cart_push")
		log_line("AIM01 cart_push -> %s attempt=%d operator=%d external=%s" % [
			found, attempt + 1, _cart_operator(), str(_external_hold())])
		if found != "cart_push":
			await _wait(1.0)
			continue
		Input.action_press("interact")
		var got: bool = await _wait_until(func() -> bool: return _external_hold(), 3.0)
		if not got:
			Input.action_release("interact")
			await _wait(1.0)
			continue
		attached = true
		client_grant_applied = true
		check(_attached_to_cart(), "client applied the cart_push grant (attached_to=%s)" % str(player.get("attached_to")))
		# Sustained hold: keep E down, press W. Movement is cart-only because
		# external_hold suppresses body movement and gates cart_axis.
		x_before = _cart_x()
		Input.action_press("move_forward")
		await _wait(2.0)
		Input.action_release("move_forward")
		x_after = _cart_x()
		moves += 1
		check(absf(x_after - x_before) > 0.15, "client cart moved while holding E (x %.2f -> %.2f)" % [x_before, x_after])
		check(_external_hold() and _attached_to_cart(), "client stayed attached through the sustained hold")
		# `hold_owner` lives on the host only; the client never receives it.
		# The host-side record below is the authoritative copy.
		note("client hold_owner is host-only (local keys=%s)" % str(_hold_owner().keys()))
		_record("client_cart_held", {"x_before": x_before, "x_after": x_after,
			"external": _external_hold(), "attached": _attached_to_cart(),
			"operator": _cart_operator(), "hold_owner_local": _hold_owner().duplicate(true)})
		break

	check(attached, "client received and applied the cart_push hold grant")
	if attached:
		# The cart hold is an explicit release, matching the in-game prompt
		# "E 松开 · WASD 推拉 · Q 取消": key-up alone does nothing because the
		# grant deliberately latched the body. A second E press sends the
		# authoritative `end` request and the host clears the operator.
		Input.action_release("interact")
		await _wait(0.25)
		Input.action_press("interact")
		await _wait(0.15)
		Input.action_release("interact")
		var detached: bool = await _wait_until(func() -> bool: return not _external_hold(), 6.0)
		check(detached, "client detached after the explicit E release (external_hold=%s)" % str(_external_hold()))
		check(player.get("attached_to") == null, "client attached_to cleared after release")
		# Leave a gap so the host can observe the braked/stationary cart before
		# the re-grip, otherwise the "stopped after release" sample overlaps it.
		await _wait(2.5)
		check(not _external_hold(), "client did not re-attach after release")
		_record("client_cart_released", {"detached": detached,
			"operator": _cart_operator(), "external": _external_hold(),
			"hold_owner_local": _hold_owner().duplicate(true)})

		# Re-grip, then shut the peer down while still attached. This is the
		# abnormal interruption: no end request is sent.
		var found3: String = await _aim("cart_push")
		log_line("REGRIP aim=%s stage_pid=%d net_pid=%d bound=%s op=%d external=%s" % [
			found3, int(stage.get("local_pid")), _local_pid(), str(_bound()),
			_cart_operator(), str(_external_hold())])
		if found3 == "cart_push":
			Input.action_press("interact")
			var regrip := false
			for i in range(60):
				if _external_hold():
					regrip = true
					break
				await _wait(0.1)
				if i % 10 == 0:
					log_line("REGRIP_WAIT t=%.1f external=%s op=%d stage_pid=%d net_pid=%d bound=%s" % [
						float(i) * 0.1, str(_external_hold()), _cart_operator(),
						int(stage.get("local_pid")), _local_pid(), str(_bound())])
			check(regrip, "client re-gripped the cart (external_hold=%s)" % str(_external_hold()))
			if regrip:
				_record("client_regrip", {"external": _external_hold(),
					"operator": _cart_operator(), "attached": _attached_to_cart()})
				client_shutdown_sent = true
				var n: Node = _net()
				if n != null and n.has_method("shutdown"):
					n.call("shutdown")
					log_line("CLIENT_ABNORMAL_SHUTDOWN while external_hold=%s" % str(_external_hold()))
				await _wait(1.2)
	else:
		Input.action_release("interact")
		await _wait(0.5)

	_record("client_final", {"grant_applied": client_grant_applied,
		"cart_attempts": client_cart_attempts, "moves": moves,
		"shutdown": client_shutdown_sent, "external": _external_hold(),
		"operator": _cart_operator(), "door": _door_amount(),
		"flags": _flags().duplicate(true)})
	await _client_disconnect()
	return true


func _client_disconnect() -> void:
	if client_shutdown_sent:
		return
	client_shutdown_sent = true
	var n: Node = _net()
	if n != null and n.has_method("shutdown"):
		n.call("shutdown")
	await _wait(1.2)
	log_line("CLIENT_DISCONNECTED_AT_END")


# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------
func _finish(passed: bool) -> void:
	if _finished:
		return
	_finished = true
	var report: Dictionary = {
		"probe": "probe_act01_hold_grant.gd",
		"role": role,
		"tag": tag,
		"passed": passed,
		"checks": checks,
		"failures": failures,
		"warnings": warnings,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_msec) / 1000.0,
		"stages": stages,
		"client_grant_applied": client_grant_applied,
		"client_cart_attempts": client_cart_attempts,
		"client_shutdown_sent": client_shutdown_sent,
		"final": {
			"scene": str(current_scene.name) if current_scene != null else "null",
			"pid": _local_pid(),
			"peers": _peers(),
			"door": _door_amount(),
			"cart_x": _cart_x(),
			"cart_velocity": _cart_velocity(),
			"operator": _cart_operator(),
			"hold_owner": _hold_owner().duplicate(true),
			"external": _external_hold(),
			"flags": _flags().duplicate(true),
		},
		"log": log_lines,
	}
	var path := ""
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		path = out_dir.path_join("hold_%s%s.json" % [role, ("_" + tag) if tag != "" else ""])
	else:
		path = "user://hold_%s.json" % role
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
		log_line("REPORT %s" % ProjectSettings.globalize_path(path))
	log_line("RESULT role=%s checks=%d failures=%d passed=%s" % [role, checks, failures.size(), str(passed)])
	if passed:
		print("HOLD_OK role=%s" % role)
	else:
		print("HOLD_FAIL role=%s %s" % [role, str(failures)])
	quit(0 if passed else 1)
