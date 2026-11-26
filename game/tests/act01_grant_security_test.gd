extends SceneTree

## Hardened Act01 hold-grant receiver test.
##
## This replaces the earlier audit probe that asserted the vulnerable behavior
## (hostile offsets applied verbatim, no sender argument). It drives the real
## Act01 scene in one process and calls the application receiver directly with
## the exact identity arguments the @rpc handler now supplies. No ENet port, no
## authority-ledger writes and no completion state are touched.

const ACT1_SCENE := "res://act1/act01.tscn"

var out_dir := ""
var checks := 0
var failures: Array[String] = []
var lines: Array[String] = []
var stage: Node = null
var player: Node = null
var _finished := false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not str(args[0]).begins_with("--"):
		out_dir = str(args[0])
	_watchdog.call_deferred()
	_run.call_deferred()


func _watchdog() -> void:
	await create_timer(25.0).timeout
	if _finished:
		return
	print("GRANT_SECURITY_TIMEOUT")
	quit(2)


func log_line(text: String) -> void:
	print("Grants " + text)
	lines.append(text)


func check(ok: bool, text: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)
	return ok


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _valid_cart() -> Dictionary:
	return {"attach": true, "offset": [-2.05, 0.02, 0.0], "yaw": -PI * 0.5}


func _run() -> void:
	var packed: PackedScene = load(ACT1_SCENE) as PackedScene
	if packed == null:
		check(false, "Act01 scene loads")
		_finish()
		return
	change_scene_to_packed(packed)
	await _wait(1.2)
	stage = current_scene
	check(stage != null and str(stage.name) == "Act01", "Act01 scene is running")
	if stage == null:
		_finish()
		return
	player = stage.get("local_player") as Node
	check(player != null, "local player exists")
	var pid: int = int(stage.get("local_pid"))
	check(pid == 1, "standalone local_pid is 1 (got %d)" % pid)

	# --- schema positives -------------------------------------------------
	check(bool((stage.call("grant_payload_valid", "cart_push", _valid_cart()) as Dictionary).get("ok", false)),
		"valid cart attach payload is accepted")
	check(bool((stage.call("grant_payload_valid", "cart_push", {"attach": false}) as Dictionary).get("ok", false)),
		"valid cart release payload is accepted")
	check(bool((stage.call("grant_payload_valid", "climb", {
		"from": [3.9, -2.0, -22.2],
		"to": [2.35, 3.5, -22.2],
		"duration": 2.4,
	}) as Dictionary).get("ok", false)), "valid rescue-climb payload is accepted")
	check(bool((stage.call("grant_payload_valid", "ride", {"attach": true}) as Dictionary).get("ok", false)),
		"valid ride payload is accepted")

	# --- schema negatives -------------------------------------------------
	var bad_cases: Array = [
		["cart_payload_huge", "cart_push", {"attach": true, "offset": [9999.0, 9999.0, 9999.0], "yaw": 0.0}],
		["cart_payload_nan", "cart_push", {"attach": true, "offset": [NAN, 0.0, 0.0], "yaw": 0.0}],
		["cart_payload_short", "cart_push", {"attach": true, "offset": [-2.05, 0.02], "yaw": 0.0}],
		["cart_yaw_huge", "cart_push", {"attach": true, "offset": [-2.05, 0.02, 0.0], "yaw": 12345.0}],
		["cart_extra_field", "cart_push", {"attach": true, "offset": [-2.05, 0.02, 0.0], "yaw": 0.0, "teleport": [1, 2, 3]}],
		["climb_huge_target", "climb", {"from": [0.0, -2.0, -22.0], "to": [40.0, 8.0, -22.0], "duration": 0.2}],
		["climb_bad_landing", "climb", {"from": [3.9, -2.0, -22.2], "to": [12.0, 3.5, -22.2], "duration": 2.4}],
		["climb_short_array", "climb", {"from": [3.9, -2.0], "to": [2.35, 3.5, -22.2], "duration": 2.4}],
		["ride_false", "ride", {"attach": false}],
		["unknown_id", "open_everything", {"attach": true}],
	]
	for case in bad_cases:
		var result: Dictionary = stage.call("grant_payload_valid", str(case[1]), case[2]) as Dictionary
		check(not bool(result.get("ok", false)), "rejects %s (%s)" % [
			str(case[0]), str(result.get("reason", "?"))])

	# --- receiver identity gates fail closed ------------------------------
	var home: Vector3 = (player as Node3D).global_position
	stage.call("client_apply_grant", "cart_push", _valid_cart(), 22, pid)
	await _wait(0.15)
	check(not bool(player.get("external_hold")), "wrong sender peer id cannot attach")
	stage.call("client_apply_grant", "cart_push", _valid_cart(), 1, pid + 1)
	await _wait(0.15)
	check(not bool(player.get("external_hold")), "wrong recipient pid cannot attach")
	stage.call("client_apply_grant", "cart_push", _valid_cart())
	await _wait(0.15)
	check(not bool(player.get("external_hold")), "missing identity arguments fail closed")
	stage.call("client_apply_grant", "cart_push", {
		"attach": true, "offset": [9999.0, 9999.0, 9999.0], "yaw": 12345.0,
	}, 1, pid)
	await _wait(0.2)
	var hostile_pos: Vector3 = (player as Node3D).global_position
	check(not bool(player.get("external_hold")) and hostile_pos.distance_to(home) < 0.5,
		"hostile offset grant leaves the body in place (moved %.2f m)" % hostile_pos.distance_to(home))
	check(hostile_pos.distance_to(home) < 1000.0, "hostile offset cannot produce a 17 km displacement")
	stage.call("client_apply_grant", "climb", {
		"from": [home.x, home.y, home.z],
		"to": [home.x + 40.0, home.y + 6.0, home.z],
		"duration": 0.2,
	}, 1, pid)
	await _wait(0.4)
	check(((player as Node3D).global_position - home).length() < 0.5,
		"hostile climb target is rejected without movement")

	# --- positive control -------------------------------------------------
	stage.call("client_apply_grant", "cart_push", _valid_cart(), 1, pid)
	await _wait(0.2)
	var cart: Node = stage.get("builder").get("power_cart")
	check(bool(player.get("external_hold")), "valid grant still attaches the local body")
	check(player.get("attached_to") == cart, "valid grant attaches to the power cart")
	check(int(stage.get("cart_operator")) == pid, "valid grant mirrors cart_operator=local_pid")
	stage.call("client_apply_grant", "cart_push", {"attach": false}, 1, pid)
	await _wait(0.2)
	check(not bool(player.get("external_hold")), "valid release still detaches the body")

	# --- interaction authorization ---------------------------------------
	check(not bool(stage.call("_validate_interaction", pid, "self_rescue", "press")),
		"a standing player cannot claim self-rescue")
	check(not bool(stage.call("_validate_interaction", pid, "cart_push", "end")),
		"a player cannot release a cart hold they do not own")
	check(not bool(stage.call("_validate_interaction", pid, "door_handle", "grab_end")),
		"a player cannot release another player's door hold")
	var valid_state: Dictionary = {
		"pos": (player as Node3D).global_position,
		"yaw": 0.0, "pitch": 0.0, "grab": false, "downed": false,
		"hold": false, "external": false, "cart_axis": 0.0, "grab_id": "",
	}
	check(str(stage.call("_validate_player_state", valid_state)) == "", "valid body state passes")
	var bad_state: Dictionary = valid_state.duplicate(true)
	bad_state["pos"] = Vector3(NAN, 0.0, 0.0)
	check(str(stage.call("_validate_player_state", bad_state)) == "pos_range",
		"NaN body state is rejected")

	# --- legal remote cart axis + disconnect cleanup ---------------------
	var cart_before_axis: float = (cart as Node3D).global_position.x
	stage.get("builder").get("power_cart").call("begin_push", pid)
	stage.set("cart_operator", pid)
	var driving_state: Dictionary = valid_state.duplicate(true)
	driving_state["cart_axis"] = 1.0
	stage.call("host_receive_state", pid, driving_state)
	await _wait(0.35)
	check((cart as Node3D).global_position.x > cart_before_axis,
		"a legal remote axis still drives the host-authoritative cart")
	cart.call("set_axis", 0.0)
	stage.call("host_add_player", 2)
	stage.set("cart_operator", 2)
	(stage.get("hold_owner") as Dictionary)["cart_push"] = 2
	stage.call("host_remove_player", 2)
	check(int(stage.get("cart_operator")) == 0, "disconnect cleanup clears cart_operator")
	check(not (stage.get("hold_owner") as Dictionary).has("cart_push"),
		"disconnect cleanup clears cart_push hold ownership")
	check(not (stage.get("active_pids") as Dictionary).has(2),
		"disconnect cleanup removes the Act01 seat")
	check(not (stage.get("remotes") as Dictionary).has(2),
		"disconnect cleanup removes the remote avatar")

	var script: Script = stage.get_script() as Script
	var has_sender := false
	var has_recipient := false
	if script != null:
		for method in script.get_script_method_list():
			if str(method.get("name", "")) == "client_apply_grant":
				for argument in (method.get("args", []) as Array):
					var arg_name := str((argument as Dictionary).get("name", ""))
					has_sender = has_sender or arg_name == "sender_peer_id"
					has_recipient = has_recipient or arg_name == "recipient_pid"
	check(has_sender and has_recipient,
		"client_apply_grant has application sender and recipient identity arguments")

	_finish()


func _finish() -> void:
	_finished = true
	var report: Dictionary = {
		"probe": "act01_grant_security_test.gd",
		"mode": "hardened_receiver",
		"checks": checks,
		"failures": failures,
		"log": lines,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("act01_grant_security.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
			log_line("REPORT " + ProjectSettings.globalize_path(out_dir.path_join("act01_grant_security.json")))
	log_line("RESULT checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("GRANT_SECURITY_OK checks=%d" % checks)
	else:
		print("GRANT_SECURITY_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
