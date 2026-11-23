extends SceneTree

## Focused schema/range tests for the Act05 host-side mirrors. Creates fresh
## CoopSession/CoopNet test doubles; the real SessionHub ledger and run state are
## untouched. No ENet peer is created.

var checks := 0
var failures: Array[String] = []
var out_dir := ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not str(args[0]).begins_with("--"):
		out_dir = str(args[0])
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print(("PASS " if ok else "FAIL ") + text)


func _run() -> void:
	var session := CoopSession.new()
	root.add_child(session)
	session.setup(1, true)
	session.add_player(1, "测试", true)

	var bad_claim: Dictionary = session.try_claim("made_up_machine", 1)
	_check(not bool(bad_claim.get("ok", true)) and str(bad_claim.get("reason", "")) == "unknown_machine",
		"unknown machine claim is rejected")
	var bad_pid: Dictionary = session.try_claim("cart_left", 0)
	_check(not bool(bad_pid.get("ok", true)), "non-positive claimant pid is rejected")
	var good_claim: Dictionary = session.try_claim("cart_left", 1)
	_check(bool(good_claim.get("ok", false)), "known machine claim still succeeds")
	session.release_claim("cart_left", 1)

	var net := CoopNet.new()
	net.name = "GuardNet"
	net.session = session
	root.add_child(net)
	var valid_state: Dictionary = {
		"pos": Vector3(1, 0.05, 2), "yaw": 0.5, "grab": false, "op": true,
		"impaired": 0.0, "op_machine": "cart_left",
	}
	_check(str(net.call("_validate_act5_player_state", valid_state)) == "", "valid Act05 state passes")
	var nan_state: Dictionary = valid_state.duplicate(true)
	nan_state["pos"] = Vector3(NAN, 0.0, 0.0)
	_check(str(net.call("_validate_act5_player_state", nan_state)) == "pos_range",
		"NaN Act05 position is rejected")
	var far_state: Dictionary = valid_state.duplicate(true)
	far_state["pos"] = Vector3(9999, 0.0, 0.0)
	_check(str(net.call("_validate_act5_player_state", far_state)) == "pos_range",
		"out-of-world Act05 position is rejected")
	var bad_machine: Dictionary = valid_state.duplicate(true)
	bad_machine["op_machine"] = "not_a_machine"
	_check(str(net.call("_validate_act5_player_state", bad_machine)) == "op_machine_unknown",
		"unknown operating machine enum is rejected")
	var bad_bool: Dictionary = valid_state.duplicate(true)
	bad_bool["grab"] = 1
	_check(str(net.call("_validate_act5_player_state", bad_bool)) == "grab_type",
		"mistyped grab flag is rejected")
	var big_state: Dictionary = valid_state.duplicate(true)
	for i in range(30):
		big_state["junk_%d" % i] = i
	_check(str(net.call("_validate_act5_player_state", big_state)) == "shape",
		"oversized Act05 state dictionary is rejected")

	var bad_action_ok := true
	for action in ["isolation_pin", "lock", "data"]:
		bad_action_ok = bad_action_ok and CoopNet.ACT5_ACTION_IDS.has(action)
	_check(bad_action_ok and not CoopNet.ACT5_ACTION_IDS.has("teleport_all"),
		"Act05 action allow-list contains only the three authored actions")

	# Act04 ledger mirror: the reliable ledger event/bootstrap carries the same
	# kinds list that the host recorded. These are isolated test ledgers, not the
	# SessionHub authority ledger.
	var source := ParticipationLedger.new()
	source.add_player(1, "主机")
	source.credit(1, "act4_hammer_strike", 1.0, "test")
	var mirror := ParticipationLedger.new()
	mirror.add_player(1, "客户端")
	mirror.apply_snapshot(source.snapshot())
	_check(mirror.has_credit(1, "act4_hammer_strike"),
		"Act04 ledger snapshot preserves the client-visible kinds list")

	var report: Dictionary = {
		"probe": "test_net_payload_guards.gd",
		"checks": checks,
		"failures": failures,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("payload_guards.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	print("PAYLOAD_GUARDS_RESULT checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("PAYLOAD_GUARDS_OK")
	else:
		print("PAYLOAD_GUARDS_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
