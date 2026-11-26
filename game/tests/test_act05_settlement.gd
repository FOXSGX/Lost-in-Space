extends SceneTree

## Act05 -> finale settlement contract test, driven through real gameplay.
##
##   godot --headless --path . --script res://tests/test_act05_settlement.gd
##
## Method (same standard as the accepted `tests/coop_auto.gd`): the operator is
## moved between stations by teleport, but every machine is operated with the
## real input actions (E/W/S/…) and the real claim/credit protocol. No gameplay
## flag is written from this test: `story.data_taken`, the participation
## ledger, `story.stage` and `SessionHub.chapter_history` must all come from the
## world. The Act-4 hand-off is injected exactly as Act 4 writes it, so the run
## starts from a chapter-context that is honest.
##
## Asserts the four settlement layers:
##   S1 completion is earned (data taken through interaction + participation gate)
##   S2 the finale is triggered by that completion (scene switches by itself)
##   S3 SessionHub recorded a legal Act-5 completion payload
##   S4 the finale scene reads the ledger and shows Act 5 as completed

const ACT04_PAYLOAD := {
	"chapter": "resonance_04",
	"completed": true,
	"seconds": 88.0,
	"memories": {1: true, 2: true, 3: true},
	"strikes": 3,
	"gate_open": true,
	"player_exit_position": Vector3(6.2, 0.2, -25.0),
	"freight_accident_fired": true,
}

var failures: int = 0
var checks: Array[Dictionary] = []
var hub: Node
var app: Node
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var session: CoopSession
var surge: SurgeDirector
var started_ms: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	started_ms = Time.get_ticks_msec()
	hub = root.get_node_or_null("/root/SessionHub")
	check("SessionHub autoload is alive", hub != null)
	if hub == null:
		_finish()
		return
	hub.set("chapter_progress", ACT04_PAYLOAD.duplicate(true))
	hub.set("pending_spawn", {
		"chapter": "resonance_04",
		"completed": true,
		"from_act4": true,
		"spawn": LevelBuilder.SPAWN_POSITION,
		"yaw": 0.0,
	})
	hub.set("current_chapter", "act04")
	var hist: Dictionary = (hub.get("chapter_history") as Dictionary).duplicate(true)
	for key in hist.keys():
		hist[key] = {}
	hub.set("chapter_history", hist)

	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	app = packed.instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(90)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	session = app.get("session") as CoopSession
	surge = app.get("surge") as SurgeDirector
	check("act05 built from the Act-4 hand-off", player != null and level != null and story != null)
	check("hand-off consumed on entry", _truthy(app.get("handoff_consumed")))
	check("no Act-5 settlement before any gameplay", _act05_record().is_empty(), str(_act05_record()))

	await _enter_hall()
	await _balance_counterweight()
	await _brace_through_surge()
	await _latch_both_legs()
	await _lock_core()
	await _load_damper()
	await _separate_isolation()
	await _take_data()

	# S1: completion evidence must be real.
	check("S1 navigation data taken by interacting with the plinth", story.data_taken)
	check("S1 every phase has a verified credit", session.can_finish(), session.gate_text())
	check("S1 completion is still not recorded before the exit", _act05_record().is_empty(), str(_act05_record()))
	check("S1 stage is EVACUATE before the exit", story.stage == StoryDirector.Stage.EVACUATE, "stage=%d" % story.stage)

	await _walk_into_exit()
	var settled: bool = await _wait_until(func() -> bool:
		return not _act05_record().is_empty(), 10.0)
	check("S2 real exit crossing completed the run", settled, "stage=%d can_finish=%s" % [story.stage, str(session.can_finish())])
	check("S2 story reached its own COMPLETED stage", story.stage == StoryDirector.Stage.COMPLETED, "stage=%d" % story.stage)

	var switched: bool = await _wait_until(func() -> bool:
		return current_scene != null and current_scene.name == "Finale", 20.0)
	check("S2 finale scene was created by the settlement", switched, str(current_scene.name if current_scene != null else "null"))

	# S3: the hub record is legal and derived from the run.
	var rec: Dictionary = _act05_record()
	check("S3 SessionHub received the Act-5 completion", not rec.is_empty(), str(rec.keys()))
	check("S3 completion flag survived the contract", bool(rec.get("completed", false)), str(rec.get("completed")))
	check("S3 completion came from the story gate", bool(rec.get("story_completed", false)) and bool(rec.get("data_taken", false)), str(rec.get("story_completed")))
	check("S3 elapsed time recorded", float(rec.get("seconds", 0.0)) > 5.0, str(rec.get("seconds")))
	check("S3 participation report records the operator as ready", _operator_ready(rec), str(rec.get("participants", {})))
	check("S3 ledger carries the real phase credits", _ledger_has(rec, "data_take") and _ledger_has(rec, "stabilizer_lock"), str(rec.get("ledger", {})))
	check("S3 current chapter advanced to finale", str(hub.get("current_chapter")) == "finale", str(hub.get("current_chapter")))
	check("S3 Act-4 hand-off still in the ledger", bool(((hub.get("chapter_history") as Dictionary).get("act04", {}) as Dictionary).get("completed", false)), str((hub.get("chapter_history") as Dictionary).get("act04", {})))

	# S4: the finale reads the ledger instead of trusting a hard-coded screen.
	var finale_text: String = _collect_label_text(current_scene)
	check("S4 finale marks Act 5 as completed", finale_text.contains("●") and finale_text.contains("第五幕 · 地心的回声"), finale_text.substr(0, 160))
	check("S4 finale renders the Act-5 payload summary", finale_text.contains("第五幕用时"), finale_text.substr(0, 200))
	check("S4 finale chapter record is derived", bool(((hub.get("chapter_history") as Dictionary).get("finale", {}) as Dictionary).get("completed", false)), str((hub.get("chapter_history") as Dictionary).get("finale", {})))
	_print_run_log(rec)
	_finish()


# ---------------------------------------------------------------------------
# real gameplay beats
# ---------------------------------------------------------------------------
func _enter_hall() -> void:
	await _stand(Vector3(0, 4.06, 12.2), Vector3(0, 4.06, 0))
	var entered: bool = await _wait_until(func() -> bool: return story.stage >= StoryDirector.Stage.DISCOVER_INSTABILITY, 5.0)
	check("hall trigger advances the story", entered, "stage=%d" % story.stage)


func _balance_counterweight() -> void:
	await _stand(Vector3(8.5, 1.70, 7.47), level.right_station.area.global_position)
	await _press_interact()
	var operating: bool = await _wait_until(func() -> bool: return player.operating, 5.0)
	check("counterweight console is operable", operating)
	await _hold("move_back", 9.0)
	await _press_interact()
	check("counterweight credit from a real lever pull", session.ledger.has_credit(1, "counterweight_effect"), str(session.ledger.get_record(1).get("phases", {})))
	check("lever pull advanced the story to balance", story.stage >= StoryDirector.Stage.BALANCE_CORE, "stage=%d" % story.stage)


func _brace_through_surge() -> void:
	await _stand(Vector3(-10.4, 3.50, -3.95), Vector3(-11.1, 4.45, -3.45))
	var grabbed: bool = false
	for _attempt in range(3):
		await _press_interact()
		grabbed = player.grabbing
		if grabbed:
			break
		await _stand(Vector3(-10.4, 3.50, -3.95), Vector3(-11.1, 4.45, -3.45))
	check("rail grab is a real protective action", grabbed and session.ledger.has_credit(1, "surge_response"), str(session.ledger.get_record(1).get("phases", {})))
	var surged: bool = await _wait_until(func() -> bool: return surge.surge_count >= 1, 40.0)
	check("a natural resonance surge fired", surged, "count=%d state=%s" % [surge.surge_count, surge.state])
	if player.grabbing:
		await _press_interact()


func _latch_both_legs() -> void:
	for index in [1, 0]:
		var stab: StabilizerRig = level.stabilizers[index]
		await _stand(stab.anchor.origin + Vector3(0, 0, -0.6), stab.global_position + Vector3(0, 1.2, 0))
		await _press_interact()
		var operating: bool = await _wait_until(func() -> bool: return player.operating, 5.0)
		if not operating:
			await _stand(stab.anchor.origin + Vector3(0, 0, -0.6), stab.global_position + Vector3(0, 1.2, 0))
			await _press_interact()
			operating = await _wait_until(func() -> bool: return player.operating, 5.0)
		# MECHANICS-005A-R4: with the R0 swing the ring must be inside the pad's
		# reach while the leg is pumped. 5.80 m of stroke also takes ~4.4 s, so a
		# single short hold is not enough - retract and try again like a human.
		var tries: int = 0
		while not stab.latched and tries < 4:
			tries += 1
			var settle: int = 0
			while settle < 300:
				settle += 1
				if absf(level.core.get_omega()) < 0.20 and absf(level.core.get_angle()) < 0.09:
					break
				await physics_frame
			await _hold("move_forward", 6.0)
			if stab.latched:
				break
			await _hold("move_back", 4.8)
		if player.operating:
			await _press_interact()
		check("stabilizer %d latched by pumping" % index, stab.latched,
			"ext=%.2f tries=%d" % [stab.extension, tries])
	await _wait_until(func() -> bool: return level.stabilizers_latched() == 2, 4.0)
	check("both legs latched", level.stabilizers_latched() == 2, "legs=%d" % level.stabilizers_latched())
	var capturable: bool = await _wait_until(func() -> bool: return level.core.is_capturable(), 20.0)
	if not capturable:
		await _stand(Vector3(8.5, 1.70, 7.47), level.right_station.area.global_position)
		await _press_interact()
		await _hold("move_back" if level.core.get_net() > 0.0 else "move_forward", 2.0)
		await _press_interact()
		capturable = await _wait_until(func() -> bool: return level.core.is_capturable(), 15.0)
	check("core is inside the capture window", capturable, "net=%.3f" % level.core.get_net())


func _lock_core() -> void:
	await _stand(Vector3(0, 0.06, 10.1), Vector3(0, 1.2, 8.6))
	await _press_interact()
	var locked: bool = await _wait_until(func() -> bool: return level.core.is_locked(), 8.0)
	check("hydraulic claw locked the core", locked, "stage=%d" % story.stage)
	check("lock assist credited", session.ledger.has_credit(1, "lock_assist"), str(session.ledger.get_record(1).get("phases", {})))


func _load_damper() -> void:
	await _wait_until(func() -> bool: return story.stage >= StoryDirector.Stage.DISCOVER_FEEDBACK, 6.0)
	await _stand(Vector3(6.4, 0.06, -2.3), Vector3(6.4, 1.2, -4.4))
	await _press_interact()
	await _hold("move_forward", 2.6)
	check("extraction damper latched", level.damper.latched_flag, "pressure=%.2f" % level.damper.pressure)
	if player.operating:
		await _press_interact()


func _separate_isolation() -> void:
	await _stand(Vector3(10.7, 0.06, -5.0), Vector3(10.6, 1.3, -8.6))
	await _press_interact()
	var pin_out: bool = await _wait_until(func() -> bool: return level.isolation.pin_out, 6.0)
	check("isolation safety pin pulled", pin_out)
	# Let the loaded damper reach its effect before pushing the carriage (the
	# isolation rig refuses the push otherwise); the damper was loaded above.
	var damped: bool = await _wait_until(func() -> bool: return level.damper.damper_effect() >= 0.35, 10.0)
	check("damper effect is loaded for the carriage", damped, "effect=%.2f" % level.damper.damper_effect())
	var operating: bool = false
	for _attempt in range(6):
		await _stand(Vector3(10.7, 0.06, -5.0), Vector3(10.6, 1.3, -8.6))
		await _press_interact()
		operating = await _wait_until(func() -> bool: return player.operating, 2.5)
		if operating:
			break
		await _frames(30)
	check("carriage console is operable", operating)
	await _hold("move_forward", 5.5)
	var separated: bool = await _wait_until(func() -> bool: return level.isolation.separated_flag, 10.0)
	check("extraction coupling separated", separated, "progress=%.2f" % level.isolation.progress)
	check("isolation pin credited", session.ledger.has_credit(1, "isolation_pin"), str(session.ledger.get_record(1).get("phases", {})))
	check("carriage push credited", session.ledger.has_credit(1, "carriage_push"), str(session.ledger.get_record(1).get("phases", {})))


func _take_data() -> void:
	await _wait_until(func() -> bool: return story.stage >= StoryDirector.Stage.RECOVER_NAVIGATION_DATA, 8.0)
	await _stand(Vector3(-3.0, 0.06, -8.0), Vector3(-3.0, 1.0, -9.1))
	await _press_interact()
	var data_ok: bool = await _wait_until(func() -> bool: return story.data_taken, 8.0)
	check("navigation data taken through the plinth", data_ok)
	check("evacuation stage reached", story.stage >= StoryDirector.Stage.EVACUATE, "stage=%d" % story.stage)


func _walk_into_exit() -> void:
	await _stand(Vector3(-25.5, 0.06, -2.0), Vector3(-27.5, 1.2, -2.0))
	await _wait_until(func() -> bool: return story.stage == StoryDirector.Stage.COMPLETED, 10.0)


# ---------------------------------------------------------------------------
# helpers (same conventions as tests/coop_auto.gd)
# ---------------------------------------------------------------------------
func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _wait(seconds: float) -> void:
	var count: int = maxi(1, int(round(seconds * 60.0)))
	for _i in range(count):
		await physics_frame


func _wait_until(cond: Callable, timeout: float) -> bool:
	var budget: int = maxi(1, int(round(timeout * 60.0)))
	for _i in range(budget):
		if bool(cond.call()):
			return true
		await physics_frame
	return bool(cond.call())


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d: Vector3 = to - from
	return atan2(-d.x, -d.z)


func _pitch_to(from: Vector3, to: Vector3) -> float:
	var flat: float = Vector2(to.x - from.x, to.z - from.z).length()
	return -atan2(to.y - (from.y + 1.62), flat)


func _stand(pos: Vector3, target: Vector3) -> void:
	player.force_exit_operate()
	player.stop_grab()
	player.external_hold = false
	player.teleport(pos, _yaw_to(pos, target), clampf(_pitch_to(pos, target), -1.1, 1.1))
	await _frames(10)


func _press_interact() -> void:
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	await _frames(3)


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	await _frames(3)


func _truthy(value: Variant) -> bool:
	return value != null and bool(value)


func _act05_record() -> Dictionary:
	var hist: Dictionary = hub.get("chapter_history") as Dictionary
	var rec: Variant = hist.get("act05", {})
	if rec is Dictionary:
		return rec as Dictionary
	return {}


func _operator_ready(rec: Dictionary) -> bool:
	var participants: Dictionary = rec.get("participants", {}) as Dictionary
	for entry in participants.get("ready", []):
		var info: Dictionary = entry as Dictionary
		if int(info.get("id", 0)) == 1:
			return true
	return false


func _ledger_has(rec: Dictionary, kind: String) -> bool:
	var ledger: Dictionary = rec.get("ledger", {}) as Dictionary
	var record: Dictionary = {}
	if ledger.has(1):
		record = ledger.get(1, {}) as Dictionary
	elif ledger.has("1"):
		record = ledger.get("1", {}) as Dictionary
	var kinds: Array = record.get("kinds", []) as Array
	return kinds.has(kind)


func _collect_label_text(node: Node) -> String:
	var text: String = ""
	if node == null:
		return text
	if node is Label:
		text += (node as Label).text + "\n"
	for child in node.get_children():
		text += _collect_label_text(child)
	return text


func check(label: String, ok: bool, detail: String = "") -> void:
	checks.append({"check": label, "ok": ok, "detail": detail})
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + (("  |  " + detail) if detail != "" else ""))


func _print_run_log(rec: Dictionary) -> void:
	print("RUN_EVIDENCE " + JSON.stringify({
		"elapsed_test_seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0,
		"stage": story.stage if story != null and is_instance_valid(story) else -1,
		"surges": surge.surge_count if surge != null and is_instance_valid(surge) else -1,
		"lock_attempts": story.lock_attempts if story != null and is_instance_valid(story) else -1,
		"act05_record_keys": rec.keys(),
		"act05_completed": rec.get("completed", false),
		"participants": rec.get("participants", {}),
		"ledger": rec.get("ledger", {}),
	}))


func _finish() -> void:
	var report: Dictionary = {
		"checks": checks.size(),
		"failures": failures,
		"passed": failures == 0,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0,
		"results": checks,
		"act05_record": _act05_record(),
	}
	print("ACT05_SETTLEMENT_RESULT " + JSON.stringify(report))
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(dir.path_join("act05_settlement.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	quit(0 if failures == 0 else 1)
