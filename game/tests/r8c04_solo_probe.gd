extends SceneTree

## R8C-04 regression: solo Act 4 must still complete. The co-op participation
## gate is host-only; solo must not require a ledger entry or a second player.

var out_dir: String = ""
var log_lines: Array[String] = []
var started: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--out="):
			out_dir = s.split("=")[1]
	started = Time.get_ticks_msec()
	_run.call_deferred()


func log_line(text: String) -> void:
	print("[solo] %s" % text)
	log_lines.append(text)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 600:
		await process_frame
		guard += 1
	await _wait(2.0)
	var game := current_scene
	if game == null or str(game.name) not in ["Act4", "Resonance04"]:
		log_line("FAIL wrong scene")
		_finish(false)
		return
	game.set_meta("suppress_act5", true)
	log_line("SCENE=%s coop_mode=%s" % [str(game.name), str(game.get("coop_mode"))])
	var player: Node = game.get("player") as Node
	var hammer: Node = game.get("hammer") as Node
	var gate: Node = game.get("gate") as Node
	if player == null or hammer == null or gate == null:
		log_line("FAIL missing player/hammer/gate")
		_finish(false)
		return
	# Real solo hammer strike (should not require any network/ledger).
	player.call("teleport", Vector3(2.25, 0.2, -0.4), 0.0)
	await _wait(0.4)
	player.call("aim_camera_at", Vector3(2.25, 1.2, -4.5), -0.08)
	await _wait(0.3)
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	await _wait(0.4)
	var struck := false
	if str(hammer.get("mode")) == "held":
		Input.action_press("move_forward")
		await _wait(1.45)
		Input.action_release("move_forward")
		await _wait(0.2)
		var before := int(hammer.get("strike_count"))
		Input.action_press("interact")
		await _wait(0.12)
		Input.action_release("interact")
		for _i in range(50):
			await _wait(0.1)
			if int(hammer.get("strike_count")) > before:
				struck = true
				break
	log_line("STRIKE struck=%s count=%d" % [str(struck), int(hammer.get("strike_count"))])
	# Solo exit path: the co-op gate is skipped. Open the physical gate and
	# enter the exit as a solo player.
	game.get("seen_memories")[1] = true
	game.get("seen_memories")[2] = true
	game.get("seen_memories")[3] = true
	if not bool(gate.get("is_open")):
		gate.call("open")
		for _i in range(80):
			await _wait(0.1)
			if bool(gate.get("is_open")):
				break
	game.call("_on_exit_entered")
	await _wait(0.5)
	var completed := bool(game.get("completed"))
	log_line("GATE completed=%s gate_open=%s" % [str(completed), str(bool(gate.get("is_open")))])
	if completed and struck:
		log_line("PASS solo Act 4 still completes (no participation gate regression)")
	else:
		log_line("FAIL solo Act 4 regression")
	_finish(completed and struck)


func _finish(ok: bool) -> void:
	var payload := {
		"probe": "r8c04_solo_probe.gd",
		"role": "solo",
		"passed": ok,
		"elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0,
		"log": log_lines,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("probe_solo.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(payload, "  "))
			f.close()
			log_line("REPORT %s" % out_dir.path_join("probe_solo.json"))
	quit(0 if ok else 1)
