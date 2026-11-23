extends SceneTree

## Act 01 module smoke test — the "最小会话桩 / 独立测试宿主" verification.
##
## Boots the module entry scene (`res://act1/act01.tscn`) in standalone mode,
## asserts the world / player / HUD / machines / interactables come up, checks
## the input fallback and the ventilation pressure gate, and asserts the
## SessionBridge records an Act01 completion (standalone stub) without needing a
## second act. Writes a JSON report to `res://../tests-out/act1_module_smoke.json`.

var app: Node3D
var failures: Array[String] = []
var log_lines: Array[String] = []
var checks: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func log_line(text: String) -> void:
	print(text)
	log_lines.append(text)


func check(ok: bool, text: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + text)
	checks[text] = ok
	if not ok:
		failures.append(text)


func _run() -> void:
	var packed: PackedScene = load("res://act1/act01.tscn") as PackedScene
	check(packed != null, "entry scene res://act1/act01.tscn loads as PackedScene")
	if packed == null:
		_finish()
		return
	app = packed.instantiate() as Node3D
	root.add_child(app)
	await create_timer(1.6).timeout

	# --- world / player / hud -------------------------------------------------
	check(app.get("builder") != null, "Act1StationBuilder built the world")
	check(app.get("local_player") != null, "Act1StationPlayer spawned")
	check(app.get("hud") != null, "Act1Hud created")
	check(app.get("net") != null, "Act1NetFacade created")
	check(not app.get("bridge") == null, "Act1SessionBridge created (standalone stub)")

	var builder: Object = app.get("builder")
	check(builder != null and builder.get("vent") != null, "ventilation rig present")
	check(builder != null and builder.get("power_cart") != null, "power cart rig present")
	check(builder != null and builder.get("mine_cart") != null, "mine cart rig present")
	check(builder != null and builder.get("wind_crate") != null, "wind crate present")
	check(builder != null and builder.get("door") != null, "entry door present")

	var interactables: Dictionary = app.get("interactables")
	check(interactables.size() >= 14, "interaction points registered (%d)" % interactables.size())
	var local_player: Node3D = app.get("local_player")
	check(local_player != null and local_player.is_on_floor(), "player spawns on solid floor")
	check(local_player != null and int(local_player.get("player_pid")) == 1, "local pid is 1")

	# --- input fallback (module-specific Q + unified-compatible E/X/R) ---------
	check(InputMap.has_action("act1_cancel"), "action act1_cancel (Q) registered")
	check(InputMap.has_action("interact"), "action interact (E) present")
	check(InputMap.has_action("emergency"), "action emergency (X) present")
	check(InputMap.has_action("reset_level"), "action reset_level (R) present")

	# --- wind / pressure gate -------------------------------------------------
	var vent: Object = builder.get("vent")
	vent.call("set_running", true)
	vent.call("set_governor", 1.0)
	vent.call("set_damper_target", 1.0)
	var vent_ok := false
	for i in range(40):
		if app.call("get_vent_pressure") > 0.58:
			vent_ok = true
			break
		await create_timer(0.25).timeout
	check(vent_ok, "vent pressure rises above 0.58 with damper/gov at 1.0")

	var block_reason: String = str(app.call("_launch_block_reason"))
	check(block_reason.find("通风未恢复") >= 0, "launch blocked while ventilation incomplete")

	# --- completion bridge (standalone stub, no second act) -------------------
	var bridge: Object = app.get("bridge")
	bridge.call("complete_act01", {"mode": "solo", "completed": true, "time": 12345})
	var recorded: Dictionary = bridge.call("recorded_completion")
	check(bool(recorded.get("completed", false)), "bridge recorded Act01 completion (standalone)")
	check(bool((bridge.get("chapter_history") as Dictionary).has("act01")), "chapter_history.act01 exists")

	# --- snapshot wiring (used by both standalone and unified clients) --------
	var snap: Dictionary = app.call("build_snapshot", 0)
	check(snap.has("flags") and snap.has("vent") and snap.has("mine"), "build_snapshot() returns flags/vent/mine")
	check(snap.has("players") and snap.has("credits"), "build_snapshot() returns players/credits")

	log_line("SMOKE_RESULT failures=%d checks=%d" % [failures.size(), checks.size()])
	_finish()


func _finish() -> void:
	var payload := {
		"passed": failures.is_empty(),
		"failures": failures,
		"checks": checks,
		"mode": "standalone",
		"engine": Engine.get_version_info()["string"],
		"log": log_lines,
	}
	var f := FileAccess.open("res://../tests-out/act1_module_smoke.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "  "))
		f.close()
	quit(0 if failures.is_empty() else 1)