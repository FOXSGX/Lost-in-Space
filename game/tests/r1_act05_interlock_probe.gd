extends SceneTree

## R1 focused Act05 east/west hydraulic-leg interlock probe (two real processes,
## direct Main scene).
##
## Setup teleports each body to its own console (so navigation is not under
## test), then every claim / pump / counterweight / lock attempt is real input.
##
## Sequence:
##   1. host latches the EAST leg with real E + W.
##   2. host goes to the lock console and presses E while the west leg is not
##      latched. The claw must refuse with a real interlock reason and must not
##      lock (this is the negative interlock case).
##   3. client latches the WEST leg with real E + W.
##   4. host moves the counterweight (real E + W) until the core is capturable.
##   5. host presses E at the lock console; the claw may now lock.
##   6. host asserts the authoritative ledger has one stabilizer_lock credit for
##      pid1 and one for pid2, both legs latched, and the core locked.
## The client's mirror is reported separately; it is never used as authority.

var role: String = "host"
var tag: String = "interlock"
var out_dir: String = ""
var log_lines: Array[String] = []
var started: int = 0
var failures: int = 0
var lock_fail_reasons: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--role="):
			role = s.split("=")[1]
		elif s.begins_with("--tag="):
			tag = s.split("=")[1]
		elif s.begins_with("--out="):
			out_dir = s.split("=")[1]
	started = Time.get_ticks_msec()
	_run.call_deferred()


func log_line(text: String) -> void:
	print("[%s] %s" % [role, text])
	log_lines.append(text)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _hub() -> Node:
	return root.get_node_or_null("/root/SessionHub")


func _net() -> Node:
	var hub := _hub()
	return hub.get("net") if hub != null else null


func _session() -> Node:
	var hub := _hub()
	return hub.get("session") if hub != null else null


func _connected() -> bool:
	var net := _net()
	if net == null:
		return false
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return int(net.call("peer_count")) >= 2


func _face(pos: Vector3) -> void:
	var p: Node3D = current_scene.get("player") as Node3D
	var d: Vector3 = pos - p.global_position
	var yaw: float = atan2(-d.x, -d.z)
	var flat: float = Vector2(d.x, d.z).length()
	var pitch: float = -atan2(d.y - 1.45, maxf(flat, 0.05))
	p.call("set_look", yaw, clampf(pitch, -1.1, 1.1))


func _press(action := "interact", hold := 0.12) -> void:
	Input.action_press(action)
	await _wait(hold)
	Input.action_release(action)
	await _wait(0.35)


func _to_stab(stab: Object) -> void:
	var area: Node3D = stab.get("area") as Node3D
	var center: Vector3 = area.global_position
	var basis: Basis = (stab as Node3D).global_transform.basis
	var stand: Vector3 = center + basis.z * 1.25
	stand.y = 0.06
	var p: Node3D = current_scene.get("player") as Node3D
	p.call("teleport", stand, 0.0)
	await _wait(0.5)
	_face(center)
	await _wait(0.25)


func _latch_leg(stab: Object, label: String) -> bool:
	await _to_stab(stab)
	await _press()
	var operating: bool = bool((current_scene.get("player") as Object).get("operating"))
	log_line("%s E operating=%s machine=%s pos=%s" % [
		label, str(operating), str(_session().get("local_operating_machine")),
		str((current_scene.get("player") as Node3D).global_position)])
	if not operating:
		return false
	Input.action_press("move_forward")
	var waited := 0.0
	while waited < 20.0 and not bool(stab.get("latched")):
		await _wait(0.25)
		waited += 0.25
	Input.action_release("move_forward")
	await _wait(0.3)
	if bool((current_scene.get("player") as Object).get("operating")):
		await _press()
	return bool(stab.get("latched"))


func _lock_attempt(label: String) -> void:
	var level: Node = current_scene.get("level")
	var core: Object = level.get("core") as Object
	var p: Node3D = current_scene.get("player") as Node3D
	p.call("teleport", Vector3(0.0, 0.06, 10.6), 0.0)
	await _wait(0.5)
	_face(Vector3(0.0, 1.2, 8.6))
	await _wait(0.3)
	log_line("%s BEFORE interlock='%s' capturable=%s locked=%s locking=%s" % [
		label, str(core.call("lock_interlock_reason")), str(bool(core.call("is_capturable"))),
		str(bool(core.call("is_locked"))), str(bool(core.call("is_locking")))])
	await _press()
	await _wait(0.8)
	log_line("%s AFTER interlock='%s' capturable=%s locked=%s locking=%s fail_reasons=%s" % [
		label, str(core.call("lock_interlock_reason")), str(bool(core.call("is_capturable"))),
		str(bool(core.call("is_locked"))), str(bool(core.call("is_locking"))),
		str(lock_fail_reasons)])


func _counterweight() -> bool:
	var p: Node3D = current_scene.get("player") as Node3D
	p.call("teleport", Vector3(8.5, 1.70, 7.47), 0.0)
	await _wait(0.5)
	_face(Vector3(8.5, 1.60, 6.60))
	await _wait(0.3)
	await _press()
	if not bool(p.get("operating")):
		log_line("COUNTERWEIGHT E failed to operate")
		return false
	Input.action_press("move_back")
	await _wait(10.0)
	Input.action_release("move_back")
	await _wait(0.3)
	if bool(p.get("operating")):
		await _press()
	var core: Object = (current_scene.get("level") as Object).get("core") as Object
	return bool(core.call("is_capturable"))


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 600:
		await process_frame
		guard += 1
	await _wait(1.5)
	var game := current_scene
	if game == null or str(game.name) != "Main":
		log_line("FAIL wrong scene")
		_finish()
		return
	for _i in range(240):
		if _connected():
			break
		await _wait(0.25)
	if not _connected():
		log_line("FAIL no peer link")
		_finish()
		return
	await _wait(1.0)
	var level: Node = game.get("level")
	var session := _session()
	var stabs: Array = level.get("stabilizers") as Array
	var west: Object = stabs[0]
	var east: Object = stabs[1]
	var core: Object = level.get("core") as Object
	# Capture the real lock-failure reason emitted by LockRig (the same signal
	# that drives the HUD toast).
	(level.get("lock_rig") as Object).connect("lock_attempt_failed",
		func(reason: String) -> void: lock_fail_reasons.append(reason))
	log_line("START host=%s client=%s stage=%s" % [
		str(bool(session.get("is_host"))), str(session.get("local_pid")),
		str((game.get("story") as Object).get("stage"))])

	if role == "host":
		# 1. host latches the east leg.
		var east_ok: bool = await _latch_leg(east, "EAST")
		log_line("EAST host_latched=%s credit=%s" % [
			str(east_ok), str(bool((session.get("ledger") as Object).call("has_credit", 1, "stabilizer_lock")))])
		# 2. negative interlock: only one of two legs is latched.
		await _lock_attempt("NEGATIVE")
		var refused: bool = not bool(core.call("is_locked")) and not bool(core.call("is_locking")) \
			and not lock_fail_reasons.is_empty()
		log_line("NEGATIVE refused=%s reasons=%s interlock_now='%s'" % [
			str(refused), str(lock_fail_reasons), str(core.call("lock_interlock_reason"))])
		if not refused:
			failures += 1
			log_line("FAIL the claw did not refuse with only the east leg latched")
		# 3. wait for the client's real west leg.
		var west_ok: bool = await _wait_until(func() -> bool:
			return bool(west.get("latched")), 60.0)
		log_line("WEST latched=%s pid2_credit=%s owner=%d" % [
			str(west_ok),
			str(bool((session.get("ledger") as Object).call("has_credit", 2, "stabilizer_lock"))),
			int(session.call("claim_owner", "stabilizer_w"))])
		if not west_ok:
			failures += 1
			log_line("FAIL the client never latched the west leg")
		# 4. real counterweight until capturable.
		var cap: bool = await _counterweight()
		if not cap:
			cap = await _counterweight()
		log_line("CAPTURABLE=%s net=%.3f limit=%.3f interlock='%s'" % [
			str(cap), float(core.call("get_net")), float(core.call("capture_net_limit")),
			str(core.call("lock_interlock_reason"))])
		if not cap:
			failures += 1
			log_line("FAIL core never became capturable")
		# 5. positive lock with both legs latched.
		await _lock_attempt("POSITIVE")
		var locked_ok: bool = await _wait_until(func() -> bool:
			return bool(core.call("is_locked")), 30.0)
		var led := session.get("ledger") as Object
		var p1_lock: bool = bool(led.call("has_credit", 1, "stabilizer_lock"))
		var p2_lock: bool = bool(led.call("has_credit", 2, "stabilizer_lock"))
		var p1_assist: bool = bool(led.call("has_credit", 1, "lock_assist"))
		log_line("HOST_AUTHORITY locked=%s east=%s west=%s p1_leg=%s p2_leg=%s p1_lock_assist=%s interlock='%s'" % [
			str(locked_ok), str(bool(east.get("latched"))), str(bool(west.get("latched"))),
			str(p1_lock), str(p2_lock), str(p1_assist), str(core.call("lock_interlock_reason"))])
		if not locked_ok:
			failures += 1
		if not (p1_lock and p2_lock):
			failures += 1
			log_line("FAIL host ledger does not hold one leg credit per player")
		if not p1_assist:
			failures += 1
			log_line("FAIL host has no lock_assist credit")
		log_line("HOST_LEDGER " + JSON.stringify(led.call("snapshot")))
		# Keep the authority alive long enough for the client's 15 Hz mirror to
		# receive the locked snapshot (the client's own check is evidence only).
		await _wait(2.5)
	else:
		# Client: wait for the host's east leg, then latch west with real input.
		var east_seen: bool = await _wait_until(func() -> bool:
			return bool(east.get("latched")), 60.0)
		log_line("CLIENT sees east latched=%s" % str(east_seen))
		var west_ok: bool = await _latch_leg(west, "WEST")
		var led2 := session.get("ledger") as Object
		log_line("CLIENT_ASSERT west_local=%s pid2_credit=%s east_local=%s" % [
			str(west_ok), str(bool(led2.call("has_credit", 2, "stabilizer_lock"))),
			str(bool(east.get("latched")))])
		if not west_ok:
			failures += 1
		var locked_seen: bool = await _wait_until(func() -> bool:
			return bool(core.call("is_locked")), 60.0)
		log_line("CLIENT_ASSERT core_locked_mirror=%s interlock='%s'" % [
			str(locked_seen), str(core.call("lock_interlock_reason"))])
		if not locked_seen:
			failures += 1
			log_line("FAIL client never saw the host's core lock")
	_finish()


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited := 0.0
	while waited < timeout_s:
		if bool(cond.call()):
			return true
		await _wait(0.1)
		waited += 0.1
	return bool(cond.call())


func _finish() -> void:
	var payload := {
		"probe": "r1_act05_interlock_probe.gd",
		"role": role,
		"tag": tag,
		"failures": failures,
		"elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0,
		"log": log_lines,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("interlock_%s_%s.json" % [role, tag]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(payload, "  "))
			f.close()
	quit(0 if failures == 0 else 1)
