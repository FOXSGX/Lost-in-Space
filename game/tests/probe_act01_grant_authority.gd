extends SceneTree

## AUDIT-ONLY authority probe for the Act01 hold-grant RPC.
##
## Two real Godot processes, real ENet, isolated UDP port, official Launcher
## scene. It does not drive the level: the point is the authorization boundary of
## `CoopNet.act1_grant_hold`, not the cart puzzle (that is covered by
## probe_act01_hold_grant.gd).
##
## Cases
##   A  a CLIENT tries to invoke the authority RPC (rpc_id to the host and a
##      broadcast). Godot must refuse it; the client must not end up holding.
##   B  the HOST addresses a well-formed grant to the WRONG pid. The client's
##      `pid != local_pid` gate must drop it.
##   C  the HOST sends the correct grant. Positive control over the real wire.
##   D  the HOST repeats the same attach grant (duplicate delivery).
##   E  the HOST sends a detach, then a second detach (idempotency).
##
## Usage:
##   godot --headless --fixed-fps 60 --path <project> res://scenes/launcher.tscn \
##     -s res://tests/probe_act01_grant_authority.gd -- \
##     --role=host|client --port=NNNN --out=<dir> --tag=<id>

var role := "host"
var port := 9971
var out_dir := ""
var tag := ""
var stage: Node = null
var player: Node = null
var net: Node = null
var checks := 0
var failures: Array[String] = []
var lines: Array[String] = []
var started_msec := 0
var _finished := false
var client_self_hold_seen := false


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
		elif s.begins_with("--port="):
			port = int(s.split("=")[1])
		elif s.begins_with("--out="):
			out_dir = s.split("=")[1]
		elif s.begins_with("--tag="):
			tag = s.split("=")[1]


func _watchdog() -> void:
	await create_timer(300.0).timeout
	log_line("WATCHDOG role=%s" % role)
	_finish(false)


func log_line(text: String) -> void:
	print("[%s] %s" % [role, text])
	lines.append(text)


func check(ok: bool, text: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)
	return ok


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


func _external() -> bool:
	return player != null and bool(player.get("external_hold"))


func _operator() -> int:
	return int(stage.get("cart_operator")) if stage != null else -1


func _hold_owner() -> Dictionary:
	return (stage.get("hold_owner") as Dictionary).duplicate(true) if stage != null else {}


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 900:
		await physics_frame
		guard += 1
	var launcher: Node = current_scene
	if launcher == null or str(launcher.name) != "Launcher":
		check(false, "booted into the official Launcher")
		_finish(false)
		return
	var hub: Node = root.get_node_or_null("/root/SessionHub")
	check(hub != null, "SessionHub autoload exists")
	if hub == null:
		_finish(false)
		return
	var err := -1
	if role == "host":
		err = int(hub.call("start", true, port))
	else:
		err = int(hub.call("start", false, port, "127.0.0.1"))
	check(err == OK, "real ENet %s started on port %d (err=%d)" % [role, port, err])
	if err != OK:
		_finish(false)
		return
	change_scene_to_file("res://act1/act01.tscn")
	var ok := await _wait_until(func() -> bool: return current_scene != null and str(current_scene.name) == "Act01", 60.0)
	check(ok, "Act01 scene loaded")
	if not ok:
		_finish(false)
		return
	stage = current_scene
	player = stage.get("local_player") as Node
	net = root.get_node_or_null("/root/SessionHub/CoopNet")
	check(player != null and net != null, "stage player and CoopNet are available")
	await _wait(1.0)

	if role == "host":
		await _host_flow()
	else:
		await _client_flow()
	_finish(failures.is_empty())


# ---------------------------------------------------------------------------
# host
# ---------------------------------------------------------------------------
func _host_flow() -> void:
	var joined := await _wait_until(func() -> bool:
		return int(stage.get("active_pids").size()) >= 2, 180.0)
	check(joined, "host registered the client seat (active=%s)" % str((stage.get("active_pids") as Dictionary).keys()))
	if not joined:
		return
	var enet := int(net.call("act1_enet_for_pid", 2))
	check(enet != 0, "host resolved the client enet id (enet=%d)" % enet)
	if enet == 0:
		return
	# Let the client run its unauthorized attempts first (case A).
	await _wait(6.0)
	var op_after_attack := _operator()
	var owner_after_attack := _hold_owner()
	check(op_after_attack == 0, "A a client-issued grant did not set cart_operator on the host (got %d)" % op_after_attack)
	check(owner_after_attack.is_empty(), "A a client-issued grant did not create a hold_owner entry (got %s)" % str(owner_after_attack))
	log_line("RECORD host_after_attack %s" % JSON.stringify({
		"operator": op_after_attack, "hold_owner": owner_after_attack}))

	# Case B: correct payload, WRONG pid.
	net.call("act1_send_grant", enet, "cart_push", 1, {
		"attach": true, "offset": [-2.05, 0.02, 0.0], "yaw": -PI * 0.5})
	await _wait(1.5)
	log_line("B sent a grant addressed to pid=1 to the pid=2 client")
	# TEST DOUBLE: stand in for the host's own `_execute_interaction` having
	# already accepted this operator. The real validated path is covered by
	# probe_act01_hold_grant.gd (host 22/0, client 21/0); here we only need the
	# authoritative pose channel to agree with the grant, otherwise the 15 Hz
	# pose would (correctly) revoke the client's mirror inside one tick.
	stage.set("cart_operator", 2)
	# Case C: correct grant.
	net.call("act1_send_grant", enet, "cart_push", 2, {
		"attach": true, "offset": [-2.05, 0.02, 0.0], "yaw": -PI * 0.5})
	await _wait(1.5)
	# Case D: duplicate of the same grant.
	net.call("act1_send_grant", enet, "cart_push", 2, {
		"attach": true, "offset": [-2.05, 0.02, 0.0], "yaw": -PI * 0.5})
	await _wait(1.5)
	# Case F: the host revokes the operator WITHOUT sending a detach grant. The
	# client must fall back to the authoritative pose and drop the hold.
	stage.set("cart_operator", 0)
	await _wait(1.5)
	log_line("F host cleared cart_operator without sending any grant")
	# Case E: detach twice (the client is already detached; both must be no-ops).
	net.call("act1_send_grant", enet, "cart_push", 2, {"attach": false})
	await _wait(1.0)
	net.call("act1_send_grant", enet, "cart_push", 2, {"attach": false})
	await _wait(1.0)
	# The host's own cart_operator stays 0: grants alone never authorize the host.
	check(_operator() == 0, "host cart_operator is still 0 (grants alone never authorize the host side)")
	# Give the client time to finish its assertions before we tear down.
	await _wait_until(func() -> bool: return bool(net.get("online")) == false, 20.0)


# ---------------------------------------------------------------------------
# client
# ---------------------------------------------------------------------------
func _client_flow() -> void:
	var seated := await _wait_until(func() -> bool:
		return int(net.get("local_pid")) == 2 and int(stage.get("active_pids").size()) >= 2, 180.0)
	check(seated, "client was seated as pid 2")
	if not seated:
		return
	await _wait(1.0)

	# --- A: the client tries to invoke the authority RPC --------------------
	var forged := {"attach": true, "offset": [-2.05, 0.02, 0.0], "yaw": -PI * 0.5}
	var called := false
	if net.has_method("act1_grant_hold"):
		# rpc_id to the host, then a broadcast: both are non-authority sends.
		net.rpc_id(1, "act1_grant_hold", "cart_push", 2, forged)
		net.rpc("act1_grant_hold", "cart_push", 2, forged)
		called = true
	check(called, "A the client attempted act1_grant_hold.rpc_id(1, ...) and .rpc(...)")
	await _wait(2.0)
	check(not _external(), "A the client did not grant itself a hold (external_hold=false)")
	check(_operator() == 0, "A the client did not mirror an operator from its own call (operator=%d)" % _operator())

	# --- B: wrong-pid grant must be dropped ---------------------------------
	var wrong_pid_dropped := true
	for i in range(15):
		if _external():
			wrong_pid_dropped = false
			break
		await _wait(0.1)
	check(wrong_pid_dropped, "B a grant addressed to pid=1 did not attach the pid=2 client")
	log_line("RECORD client_after_wrong_pid %s" % JSON.stringify({
		"external": _external(), "operator": _operator()}))

	# --- C: correct grant attaches -----------------------------------------
	var attached := await _wait_until(func() -> bool: return _external(), 20.0)
	check(attached, "C the correctly addressed grant attached the client")
	var op_c := _operator()
	check(op_c == 2, "C the client mirrored cart_operator=2 from the authority grant (got %d)" % op_c)
	# --- D: duplicate delivery is idempotent --------------------------------
	await _wait(2.0)
	check(_external(), "D a duplicate attach grant kept the client attached (no detach churn)")
	check(_operator() == 2, "D the duplicate did not corrupt cart_operator (got %d)" % _operator())
	# --- F: authority revokes without a detach grant ------------------------
	# This is the real safety net: `_client_update()` compares the local hold
	# against the 15 Hz authoritative `cart_operator` pose, so a lost or never
	# delivered detach grant still releases the body.
	var revoked := await _wait_until(func() -> bool: return not _external(), 20.0)
	check(revoked, "F the client dropped the hold when the authoritative pose cleared cart_operator")
	await _wait(0.5)
	check(_operator() == 0, "F cart_operator followed the authoritative pose back to 0 (got %d)" % _operator())
	# --- E: detach (twice) on an already detached client --------------------
	await _wait(1.0)
	check(not _external(), "E a detach grant on an already detached client is a no-op")
	await _wait(1.0)
	check(not _external(), "E a second detach is also a no-op")
	check(_operator() == 0, "E cart_operator stays 0 (got %d)" % _operator())
	log_line("RECORD client_final %s" % JSON.stringify({
		"external": _external(), "operator": _operator(),
		"hold_owner": _hold_owner(), "checks": checks, "failures": failures}))

	# Leave so the host can finish.
	if net != null and net.has_method("shutdown"):
		net.call("shutdown")
	await _wait(1.0)


func _finish(passed: bool) -> void:
	if _finished:
		return
	_finished = true
	var report := {
		"probe": "probe_act01_grant_authority.gd",
		"role": role,
		"tag": tag,
		"passed": passed,
		"checks": checks,
		"failures": failures,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_msec) / 1000.0,
		"log": lines,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var path := out_dir.path_join("authority_%s%s.json" % [role, ("_" + tag) if tag != "" else ""])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
			log_line("REPORT " + ProjectSettings.globalize_path(path))
	log_line("RESULT role=%s checks=%d failures=%d passed=%s" % [role, checks, failures.size(), str(passed)])
	if passed:
		print("AUTH_OK role=%s" % role)
	else:
		print("AUTH_FAIL role=%s %s" % [role, str(failures)])
	quit(0 if passed else 1)
