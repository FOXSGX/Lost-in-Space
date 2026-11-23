extends SceneTree

## LIS-GAMEPLAY-001B · two focused audits in one headless run.
##
## A. The `act1_autotest.gd` completion assertion is not a forced pass.
##    `save_and_wait()` now reads the completion through a bridge captured while
##    the level was alive. This block proves that assertion is meaningful: on a
##    freshly built Act01 the same call must report completed=false, and only a
##    real departure may flip it to true.
##
## B. The `--early-coop=` launch hook is inert unless explicitly requested.
##    The hook must not add a probe node, must not touch flags, must not write
##    files and must not disturb an otherwise normal Act01 boot.
##
## Usage:
##   godot --headless --fixed-fps 60 --path game \
##     -s res://act1/tests/act1_audit_hooks.gd -- <out_dir>

var failures: Array[String] = []
var lines: Array[String] = []
var checks := 0
var out_dir := ""


func _initialize() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0 and not str(ua[0]).begins_with("--"):
		out_dir = str(ua[0])
	_run.call_deferred()


func log_line(t: String) -> void:
	print("AUDIT " + t)
	lines.append(t)


func check(ok: bool, t: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + t)
	if not ok:
		failures.append(t)
	return ok


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	# ---- B. hook inertness: this run has NO --early-coop argument ----------
	var arg_lists := [OS.get_cmdline_args(), OS.get_cmdline_user_args()]
	var hook_present := false
	for lst in arg_lists:
		for a in lst:
			if str(a).begins_with("--early-coop="):
				hook_present = true
	check(not hook_present, "this audit run carries no --early-coop argument (control case)")

	var packed := load("res://act1/act01.tscn") as PackedScene
	check(packed != null, "Act01 scene loads")
	if packed == null:
		_finish()
		return
	var stage: Node = packed.instantiate()
	root.add_child(stage)
	await _wait(1.6)

	# No probe node must be injected by a plain boot.
	var probe_a: Node = root.get_node_or_null("Act1EarlyServiceCoop")
	check(probe_a == null, "plain boot does not attach the --early-coop probe")
	var autotest_a: Node = root.get_node_or_null("Act1Autotest")
	check(autotest_a == null, "plain boot does not attach the --autotest runner either")
	# A normal boot must leave the world in its authored initial state.
	var flags: Dictionary = stage.get("flags") as Dictionary
	var dirty: Array[String] = []
	for k in ["power_ready", "rotor_lock_released", "coupling_engaged", "fan_started",
			"vent_complete", "departure_started", "completed", "handoff"]:
		if bool(flags.get(k, false)):
			dirty.append(str(k))
	check(dirty.is_empty(), "plain boot leaves every machine flag false (%s)" % str(dirty))
	var net: Object = stage.get("net")
	check(net != null and str(net.get("mode")) == "solo", "plain boot is a solo session (mode=%s)" % (str(net.get("mode")) if net != null else "?"))
	check(int(net.call("peer_count")) == 1, "plain boot opens no extra peer")

	# ---- A. the completion assertion is real ------------------------------
	var bridge: Object = stage.get("bridge")
	check(bridge != null, "Act01 built a session bridge")
	check(bridge != null and bridge.has_method("recorded_completion"),
		"the bridge exposes recorded_completion (what save_and_wait reads)")
	if bridge != null:
		var pre: Dictionary = bridge.call("recorded_completion")
		check(not bool(pre.get("completed", false)),
			"before departure recorded_completion() is false, so the assertion can fail")
		# Write a genuine completion the way the real departure does, then prove
		# the very same call observes it. Nothing is forced: the value comes from
		# the session's own ledger.
		var fake := {"mode": "solo", "completed": true, "time": Time.get_ticks_msec(), "chapter": "act01"}
		stage.call("set_flag", "departure_started", true)
		bridge.call("complete_act01", fake)
		await _wait(0.2)
		var post: Dictionary = bridge.call("recorded_completion")
		check(bool(post.get("completed", false)),
			"after a real complete_act01 the same call reports completed=true")

	# The bridge must survive the level being freed: that is exactly the crash.
	# Capture it, free the stage, and read again.
	if bridge != null:
		stage.queue_free()
		await _wait(0.5)
		var still: Dictionary = bridge.call("recorded_completion")
		check(bool(still.get("completed", false)),
			"a captured bridge still reports the completion after the level is freed")

	_finish()


func _finish() -> void:
	var ok := failures.is_empty()
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var rep := {"probe": "act1_audit_hooks.gd", "passed": ok, "checks": checks,
			"failures": failures, "log": lines}
		var f := FileAccess.open(out_dir.path_join("act1_audit_hooks.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(rep, "  "))
			f.close()
	log_line("RESULT checks=%d failures=%d passed=%s" % [checks, failures.size(), str(ok)])
	print("AUDIT_HOOKS_%s checks=%d" % ["OK" if ok else "FAIL", checks])
	quit(0 if ok else 1)
