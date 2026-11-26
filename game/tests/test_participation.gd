extends SceneTree

## Participation suite for Resonance 05 V2 (tests A-H from the brief).
##
## Real-machine paths are used wherever a machine can accept a non-local
## operator: claims + streamed axis drive the stabilisers, carts, brake, damper,
## catwalk lock and isolation carriage as any player id. Instant-press actions
## (the lock console, the shear pin, the data plinth) are simulated at the
## ledger boundary because a single process only has one local body; those are
## marked SIM in the report. Everything is host-authoritative session state.
##
## This is a state-machine / session simulation, NOT a two-client network test.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var session: CoopSession
var surge: SurgeDirector
var hud: GameHud
var cases: Array[Dictionary] = []
var out_path: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-04-05-coop-vertical-slice/tests-out/participation_suite.json"


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func wait(seconds: float) -> void:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await physics_frame


func new_app(extra_players: Array) -> void:
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(45)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	session = app.get("session") as CoopSession
	surge = app.get("surge") as SurgeDirector
	hud = app.get("hud") as GameHud
	hud.title_layer.visible = false
	# Put the run in the hall stage so the surge director is armed exactly as it
	# would be in normal play.
	story.stage = StoryDirector.Stage.BALANCE_CORE
	# In the vertical slice the CoopSession lives on the SessionHub autoload and
	# survives scene reloads, whereas the source project created a fresh session
	# per case. Reset the ledger/claims so each case starts clean.
	session.ledger = ParticipationLedger.new()
	session.ledger.add_player(1, "七号", true)
	session.claims.clear()
	session.grab_states.clear()
	session.player_states.clear()
	# The suite drives every participant through the claim + axis path, so no
	# body is "the local player" for input purposes.
	session.local_pid = 0
	for pid in extra_players:
		session.add_player(int(pid), "队友%d" % (int(pid) - 1))


func close_app() -> void:
	if app != null:
		app.queue_free()
		app = null
	await frames(4)


func pump(pid: int, machine_id: String, seconds: float, axis: float = 1.0) -> bool:
	var claim: Dictionary = session.try_claim(machine_id, pid)
	if not bool(claim.get("ok", false)):
		return false
	# MECHANICS-005A-R4: with the R0 swing restored a stabiliser leg only seats
	# while the ring is inside the pad's reach. Real players retract and try again;
	# do the same here so the participation ledger sees the same credit a human
	# would earn. Only stabiliser_* machines need it - everything else is direct.
	if machine_id.begins_with("stabilizer_"):
		var leg_i: int = 0 if machine_id == "stabilizer_w" else 1
		for attempt in range(3):
			var st: int = 0
			while st < 240:
				st += 1
				if absf((app.get("level") as LevelBuilder).core.get_omega()) < 0.20 \
						and absf((app.get("level") as LevelBuilder).core.get_angle()) < 0.09:
					break
				await frames(1)
			session.set_axis(machine_id, pid, axis)
			await wait(seconds)
			session.set_axis(machine_id, pid, 0.0)
			if (app.get("level") as LevelBuilder).stabilizers[leg_i].latched:
				break
			session.set_axis(machine_id, pid, -axis)
			await wait(seconds)
			session.set_axis(machine_id, pid, 0.0)
		session.release_claim(machine_id, pid)
		return true
	session.set_axis(machine_id, pid, axis)
	await wait(seconds)
	session.set_axis(machine_id, pid, 0.0)
	session.release_claim(machine_id, pid)
	return true


func work_a(pid: int, slot: int) -> String:
	match slot:
		0:
			await pump(pid, "stabilizer_w", 6.0)
			return "stabilizer_w"
		1:
			await pump(pid, "stabilizer_e", 6.0)
			return "stabilizer_e"
		2:
			await pump(pid, "brake", 2.0)
			return "brake"
		3:
			await pump(pid, "catwalk_lock", 1.6)
			return "catwalk_preload"
	return "none"


func work_c(pid: int, slot: int) -> String:
	match slot:
		0:
			session.credit(pid, "lock_assist", 1.0, "SIM: 锁爪控制台按键")
			return "lock_assist(SIM)"
		1:
			await pump(pid, "damper", 2.0)
			return "damper"
		2:
			level.isolation.pin_out = true
			session.credit(pid, "isolation_pin", 1.0, "SIM: 拔销按键")
			return "isolation_pin(SIM)"
		3:
			await pump(pid, "isolation_carriage", 3.2)
			return "carriage"
	return "none"


func grab_phase_b(pids: Array) -> void:
	for pid in pids:
		session.set_grab_state(int(pid), true)
	surge._begin_warning()
	await wait(4.4)
	for pid in pids:
		session.set_grab_state(int(pid), false)


func case(name: String, participants: Array, idle: Array) -> Dictionary:
	await new_app(participants.slice(1))
	var working: Array = []
	for pid in participants:
		if not idle.has(pid):
			working.append(pid)
	var assignments: Array[String] = []
	for i in range(working.size()):
		assignments.append(await work_a(int(working[i]), i))
	# The core must actually settle for the claw to accept a lock; only the
	# ledger gate is under test here, so the cart is driven separately.
	if participants.size() >= 1:
		await pump(1, "cart_right", 6.0, -1.0)
	await grab_phase_b(working)
	var c_assign: Array[String] = []
	for i in range(working.size()):
		c_assign.append(await work_c(int(working[i]), i))
	var detail: Dictionary = {
		"name": name,
		"participants": participants,
		"idle": idle,
		"assign_a": assignments,
		"assign_c": c_assign,
		"ready": {},
		"can_finish": session.can_finish(),
		"gate": session.gate_text(),
	}
	var all_working_ready: bool = true
	for pid in working:
		var is_ready: bool = session.ledger.is_ready(int(pid))
		(detail["ready"] as Dictionary)[int(pid)] = is_ready
		if not is_ready:
			all_working_ready = false
	var idle_not_ready: bool = true
	for pid in idle:
		var idle_ready: bool = session.ledger.is_ready(int(pid))
		(detail["ready"] as Dictionary)[int(pid)] = idle_ready
		if idle_ready:
			idle_not_ready = false
	detail["all_working_ready"] = all_working_ready
	detail["idle_not_ready"] = idle_not_ready
	detail["ok"] = all_working_ready and idle_not_ready and (session.can_finish() == idle.is_empty())
	await close_app()
	return detail


func run() -> void:
	# A. two players, both work
	var a: Dictionary = await case("A_two_players_both_work", [1, 2], [])
	# B. two players, one idle
	var b: Dictionary = await case("B_two_players_one_idle", [1, 2], [2])
	# C. three players, one idle
	var c: Dictionary = await case("C_three_players_one_idle", [1, 2, 3], [3])
	# D. four players, one idle
	var d: Dictionary = await case("D_four_players_one_idle", [1, 2, 3, 4], [4])
	cases.append(a)
	cases.append(b)
	cases.append(c)
	cases.append(d)

	# E. free role swap: the same two players keep swapping machines.
	await new_app([2])
	var e_ok: bool = true
	var swap_log: Array[String] = []
	# MECHANICS-005A-R4: with the R0 swing the core must be inside the capture
	# window before a leg can seat, so trim the counterweights first.
	await pump(1, "cart_left", 6.0, 1.0)
	await wait(6.0)
	var first: Dictionary = session.try_claim("stabilizer_w", 1)
	swap_log.append("P1 claim stabilizer_w=%s" % str(first.get("ok", false)))
	await pump(1, "stabilizer_w", 6.0)
	var second: Dictionary = session.try_claim("stabilizer_e", 2)
	swap_log.append("P2 claim stabilizer_e=%s" % str(second.get("ok", false)))
	await pump(2, "stabilizer_e", 6.0)
	# swap: P1 takes the damper, P2 takes a counterweight
	await pump(1, "damper", 2.0)
	await pump(2, "cart_right", 6.0, -1.0)
	var p1_a: bool = session.ledger.has_credit(1, "stabilizer_lock")
	var p1_c: bool = session.ledger.has_credit(1, "damper_latch")
	var p2_a: bool = session.ledger.has_credit(2, "stabilizer_lock")
	var p2_a_cart: bool = session.ledger.has_credit(2, "counterweight_effect")
	e_ok = p1_a and p1_c and p2_a and p2_a_cart
	cases.append({
		"name": "E_free_role_swap",
		"ok": e_ok,
		"detail": swap_log,
		"p1": session.ledger.snapshot().get(1, {}),
		"p2": session.ledger.snapshot().get(2, {}),
	})

	# F. disconnect releases claims and removes the participant from the gate.
	await new_app([2])
	await pump(2, "stabilizer_e", 6.0)
	session.try_claim("brake", 2)
	var owner_before: int = session.claim_owner("brake")
	session.remove_player(2, "disconnect")
	var owner_after: int = session.claim_owner("brake")
	var p2_status: String = session.status_of(2)
	var p2_ready: bool = session.ledger.is_ready(2)
	# P1 completes their own work; the run can now finish without P2.
	await pump(1, "stabilizer_w", 6.0)
	await grab_phase_b([1])
	await work_c(1, 0)
	var f_ok: bool = owner_before == 2 and owner_after == 0 and p2_status == ParticipationLedger.STATUS_DISCONNECTED and not p2_ready and session.can_finish()
	cases.append({
		"name": "F_disconnect_release",
		"ok": f_ok,
		"owner_before": owner_before,
		"owner_after": owner_after,
		"p2_status": p2_status,
		"p2_ready": p2_ready,
		"can_finish_after": session.can_finish(),
		"gate": session.gate_text(),
	})
	await close_app()

	# G. solo (the full run is covered by test_solo_coop.gd; here only the gate).
	await new_app([])
	await pump(1, "stabilizer_w", 6.0)
	await pump(1, "stabilizer_e", 6.0)
	await pump(1, "cart_right", 6.0, -1.0)
	await grab_phase_b([1])
	await work_c(1, 0)
	var g_ready: bool = session.ledger.is_ready(1)
	var g_can: bool = session.can_finish()
	cases.append({"name": "G_solo_gate", "ok": g_ready and g_can, "ready": g_ready, "can_finish": g_can})
	await close_app()

	# H. false contribution must not count.
	await new_app([2])
	var before: Array = session.ledger.get_record(2).get("credits", {}).keys()
	# 1) repeated claims without doing any work
	for i in range(6):
		session.try_claim("stabilizer_w", 2)
		await frames(6)
		session.release_claim("stabilizer_w", 2)
	# 2) axis with no claim
	session.set_axis("stabilizer_e", 2, 1.0)
	await frames(30)
	# 3) credits below the measured-effect threshold
	var low1: bool = session.credit(2, "stabilizer_lock", 0.5, "too small")
	var low2: bool = session.credit(2, "counterweight_effect", 0.01, "too small")
	var low3: bool = session.credit(2, "damper_latch", 0.2, "too small")
	# 4) pressing the lock console with no capture range
	var lock_before: Array = session.ledger.get_record(2).get("credits", {}).keys()
	level.lock_rig.interact(player)
	await frames(5)
	# 5) walking a couple of metres
	player.teleport(Vector3(2, 0.06, 3), 0.0, 0.0)
	await frames(20)
	var after: Array = session.ledger.get_record(2).get("credits", {}).keys()
	var h_ok: bool = after.is_empty() and not low1 and not low2 and not low3 and before.is_empty()
	cases.append({
		"name": "H_no_false_contribution",
		"ok": h_ok,
		"credits_after": after,
		"low_credit_rejected": [not low1, not low2, not low3],
		"lock_console_no_credit": lock_before == after,
	})
	await close_app()

	var passed: int = 0
	for item in cases:
		if bool(item.get("ok", false)):
			passed += 1
		print(("PASS  " if bool(item.get("ok", false)) else "FAIL  ") + str(item.get("name", "?")))
	print("PARTICIPATION_RESULT pass=%d/%d" % [passed, cases.size()])
	var report: Dictionary = {
		"suite": "participation_A_H_simulated",
		"note": "state-machine simulation with real machine paths; instant-press actions marked SIM",
		"cases": cases,
		"passed": passed,
		"total": cases.size(),
	}
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	quit()
