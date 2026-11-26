extends SceneTree

## Act 4 participation suite (tests A & B from the brief, ledger boundary).
##
## Same honest standard as the Act 5 suite (participation_A_H_simulated): this
## drives the host-authoritative CoopSession + ParticipationLedger directly and
## re-implements the Act 4 exit-gate decision exactly as `_on_exit_entered` does,
## so the anti-idle rule is verified in isolation without a two-client network.
## The two-process network path and the real gate call are covered separately by
## act4_coop_auto.gd's JSON reports and the FULL_RUN_TEST documentation.

var session: CoopSession
var cases: Array[Dictionary] = []
var out_path: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-04-05-coop-vertical-slice/tests-out/act4_participation.json"


func _initialize() -> void:
	run.call_deferred()


func new_session(extra_players: Array) -> void:
	var hub: Node = Engine.get_main_loop().root.get_node_or_null("/root/SessionHub")
	if hub != null:
		session = hub.get("session") as CoopSession
	# Fresh ledger + participant list per case so credits never leak between
	# cases (the autoload session is long-lived).
	session.ledger = ParticipationLedger.new()
	session.ledger.add_player(1, "七号", true)
	for pid in extra_players:
		session.add_player(int(pid), "队友%d" % (int(pid) - 1))
	session.claims.clear()


## Exact copy of the gate check inside ResonanceGame._on_exit_entered.
func gate_would_open() -> Dictionary:
	var missing: Array[int] = []
	var by_pid: Dictionary = {}
	for pid in session.ledger.active_ids():
		var ready: bool = session.ledger.ready_for_phase(pid, "04")
		if not ready:
			missing.append(pid)
			by_pid[pid] = session.ledger.missing_kinds(pid, "04")
	return {"missing": missing, "by_pid": by_pid}


func case_ok(name: String, ok: bool, detail: Dictionary = {}) -> void:
	var item: Dictionary = {"name": name, "ok": ok}
	for k in detail.keys():
		item[k] = detail[k]
	cases.append(item)
	print(("PASS  " if ok else "FAIL  ") + name)


func run() -> void:
	# --- A. both participants have an Act-4 credit -> gate allows ---------
	await new_session([2])
	session.credit(1, "act4_hammer_strike", 1.0, "拉响撞钟")
	session.credit(2, "act4_crystal_carry", 1.0, "搬运晶体")
	var gate_a: Dictionary = gate_would_open()
	case_ok("A_both_participate_gate_allows", gate_a["missing"].is_empty(), {
		"missing": gate_a["missing"], "p1_ready04": session.ledger.ready_for_phase(1, "04"), "p2_ready04": session.ledger.ready_for_phase(2, "04")
	})

	# --- B. player 2 idle -> gate refuses with a clear message -------------
	await new_session([2])
	session.credit(1, "act4_hammer_strike", 1.0, "拉响撞钟")
	var gate_b: Dictionary = gate_would_open()
	var b_missing: Array = gate_b["missing"]
	var p2_missing: Array = gateway_missing_for(gate_b, 2)
	var b_refused: bool = not b_missing.is_empty()
	case_ok("B_idle_player_not_auto_passed", b_refused, {"missing": b_missing})
	# The idle player is told exactly which real action is still missing.
	if p2_missing.size() > 0:
		var kind0: String = str(p2_missing[0])
		var label0: String = str((ParticipationLedger.KINDS[kind0] as Dictionary).get("label", kind0))
		case_ok("B_idle_player_told_what_to_do", not label0.is_empty() and not kind0.is_empty(), {"label": label0})
	else:
		case_ok("B_idle_player_told_what_to_do", false, {"detail": "no missing kinds surfaced"})

	# --- H (Act 4 flavour). fake activity must not earn an Act-4 credit -----
	await new_session([])
	var before_h: Array = session.ledger.get_record(1).get("credits", {}).keys()
	var low: bool = session.credit(1, "act4_platform_drive", 0.1, "too small / not a real drive")
	session.set_axis("cart_left", 1, 1.0)  # not an Act-4 machine claim at all
	var after_h: Array = session.ledger.get_record(1).get("credits", {}).keys()
	case_ok("H_act4_fake_activity_rejected", after_h.is_empty() and not low, {"credits": after_h, "low_accepted": low})

	# --- D (disconnect release, Act 4 flavour). peer drop releases claims ---
	await new_session([2])
	session.try_claim("cart_left", 2)
	var owner_before: int = session.claim_owner("cart_left")
	session.remove_player(2, "disconnect")
	var owner_after: int = session.claim_owner("cart_left")
	case_ok("D_disconnect_releases_claim", owner_before == 2 and owner_after == 0, {"before": owner_before, "after": owner_after})

	var passed: int = 0
	for item in cases:
		if bool(item.get("ok", false)):
			passed += 1
	print("ACT4_PARTICIPATION_RESULT pass=%d/%d" % [passed, cases.size()])
	var report: Dictionary = {
		"suite": "act4_participation_ABDH_simulated",
		"note": "CoopSession + ParticipationLedger boundary simulation of the Act 4 exit gate and disconnect release; two-process network path covered by act4_coop_auto",
		"cases": cases,
		"passed": passed,
		"total": cases.size(),
	}
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	quit(0 if passed == cases.size() else 1)


func gateway_missing_for(gate: Dictionary, pid: int) -> Array:
	var by_pid: Dictionary = gate.get("by_pid", {})
	if by_pid.has(pid):
		return by_pid[pid] as Array
	return []