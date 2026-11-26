extends Node

## LIS-GAMEPLAY-002 · refusal ATTRIBUTION probe (two processes).
##
## The plant for this probe: `_execute_interaction()` runs on the host for a
## remote player's request, so a plain `_send_local_toast()` during a refused
## press painted the sentence on the HOST's screen and left the player who
## pressed E with nothing. `_feedback_to()` now addresses the actor with
## `sync_message.rpc_id()`.
##
## This probe proves the routing from the outside, with two real processes:
##
##   client2  presses the blocked platform machines. It must SEE each refusal.
##   host     must NOT see those refusal sentences (it sees the client's body and
##            the authoritative flags, but not the client's private feedback).
##
## It also proves the opposite direction still works: the host's own refusal is
## local to the host and does not leak to the client.
##
## Usage (host first):
##   godot --headless --path game --port 9961 --host  res://act1/act01.tscn \
##     -- --attrib=host   --out=<dir>
##   godot --headless --path game --port 9961 --client res://act1/act01.tscn \
##     -- --attrib=client --out=<dir>

var stage: Node3D
var player: Node
var role := ""
var out_dir := ""
var failures: Array[String] = []
var lines: Array[String] = []
var checks := 0

const CHOCK := Vector3(-5.62, 0.05, -45.40)
const BRAKE := Vector3(6.55, 1.60, -48.60)
const CARGO := Vector3(5.35, 1.58, -47.05)

## Every sentence the platform machines can emit when refusing.
const REFUSAL_MARKERS := ["通风未恢复", "止轮楔", "压不下去", "拉不动", "联锁锁住"]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--attrib="):
			role = s.substr("--attrib=".length())
		elif s.begins_with("--out="):
			out_dir = s.substr("--out=".length())
	call_deferred("_run")


func log_line(t: String) -> void:
	print("ATTRIB[%s] %s" % [role, t])
	lines.append(t)


func check(ok: bool, t: String) -> void:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + t)
	if not ok:
		failures.append(t)


func _flags() -> Dictionary:
	return stage.get("flags") as Dictionary


func _flag(k: String) -> bool:
	return bool(_flags().get(k, false))


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _toast() -> String:
	var hud: Node = stage.get("hud") as Node
	if hud == null:
		return ""
	var t: Variant = hud.get("_toast")
	if not (t is Label):
		return ""
	return (t as Label).text if (t as Label).modulate.a > 0.02 else ""


func _clear_toast() -> void:
	var hud: Node = stage.get("hud") as Node
	var t: Variant = hud.get("_toast")
	if t is Label:
		(t as Label).text = ""
		(t as Label).modulate.a = 0.0
	hud.set("_toast_time", 0.0)


func _look(id: String) -> void:
	var p: Object = (stage.get("interactables") as Dictionary).get(id) as Object
	if p != null:
		player.call("look_at_point", p.get("global_position"))
	await get_tree().create_timer(0.45).timeout


func _warp(p: Vector3) -> void:
	player.call("teleport", p, 0.0, 0.0)
	await get_tree().create_timer(0.25).timeout


func _is_refusal(s: String) -> bool:
	for m in REFUSAL_MARKERS:
		if s.find(str(m)) >= 0:
			return true
	return false


func _marker(name: String) -> String:
	return out_dir.path_join("attrib_" + name)


func _mark(name: String, body: String = "") -> void:
	var f := FileAccess.open(_marker(name), FileAccess.WRITE)
	if f != null:
		f.store_string(body if body != "" else str(Time.get_ticks_msec()))
		f.close()


func _wait_marker(name: String, secs: float) -> bool:
	var w := 0.0
	while w < secs:
		if FileAccess.file_exists(_marker(name)):
			return true
		await get_tree().create_timer(0.2).timeout
		w += 0.2
	return FileAccess.file_exists(_marker(name))


func _read_marker(name: String) -> String:
	var path := _marker(name)
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt


func _peers(secs: float, want: int) -> bool:
	var w := 0.0
	while w < secs:
		var net: Object = stage.get("net")
		if net != null and int(net.call("peer_count")) >= want:
			return true
		await get_tree().create_timer(0.4).timeout
		w += 0.4
	return false


func _run() -> void:
	while stage == null:
		await get_tree().process_frame
	await _wait(1.8)
	player = stage.get("local_player")
	log_line("start mode=%s pid=%d" % [str(stage.get("net").get("mode")), int(stage.get("local_pid"))])
	if role == "host":
		await _run_host()
	else:
		await _run_client()
	_finish()


## The client does every blocked press and reports what IT saw.
func _run_client() -> void:
	check(await _peers(90.0, 2), "client joined the host")
	check(int(stage.get("local_pid")) == 2, "client is pid 2")
	await _wait(1.0)

	# 1. chock before ventilation: this client must SEE the refusal.
	await _warp(CHOCK)
	await _look("chock")
	_clear_toast()
	stage.call("request_interaction", "chock", player, "press")
	await _wait(0.5)
	var say := _toast()
	log_line("CLIENT_SAY_CHOCK " + say)
	check(say.find("通风") >= 0, "the acting client sees the chock refusal on its own screen")
	check(not _flag("chock_removed"), "the refusal changed no state")

	# 2. brake before chock: a second, different machine (different cooldown key).
	await _warp(BRAKE)
	await _look("parking_brake")
	_clear_toast()
	stage.call("request_interaction", "parking_brake", player, "press")
	await _wait(0.5)
	var say2 := _toast()
	log_line("CLIENT_SAY_BRAKE " + say2)
	check(say2.find("止轮楔") >= 0, "the acting client sees the brake refusal")

	# 3. cargo: a third machine.
	await _warp(CARGO)
	await _look("cargo")
	_clear_toast()
	stage.call("request_interaction", "cargo", player, "press")
	await _wait(0.5)
	var say3 := _toast()
	log_line("CLIENT_SAY_CARGO " + say3)
	check(say3.find("止轮楔") >= 0 or say3.find("制动") >= 0,
		"the acting client sees the cargo refusal")
	_mark("client_done")

	# 4. The client must NOT receive the host's own private refusal. The host
	#    presses a blocked machine at a moment agreed by the handshake below.
	check(await _wait_marker("host_pressed", 120.0), "host signalled its own press")
	await _wait(1.2)
	var leaked := _toast()
	log_line("CLIENT_AFTER_HOST_PRESS '" + leaked + "'")
	check(not _is_refusal(leaked), "the host's own refusal did not leak to the client")


## The host verifies it did NOT receive the client's refusal sentences.
func _run_host() -> void:
	check(await _peers(90.0, 2), "host sees the client join")
	check(int(stage.get("local_pid")) == 1, "host is pid 1")

	# Watch the host toast across the whole client refusal sequence.
	var seen := ""
	var deadline := 150.0
	var waited := 0.0
	while waited < deadline:
		var t := _toast()
		if _is_refusal(t):
			seen = t
			break
		if FileAccess.file_exists(_marker("client_done")):
			break
		await get_tree().create_timer(0.15).timeout
		waited += 0.15
	log_line("HOST_SAW_REFUSAL '%s'" % seen)
	check(await _wait_marker("client_done", 120.0), "client finished its refusal sequence")
	check(seen == "",
		"the host does NOT see the client's refusal sentences (they were addressed to pid 2)")
	check(not _flag("chock_removed") and not _flag("brake_released") and not _flag("cargo_secured"),
		"no refused machine advanced on the authority either")

	# Now the host's own refusal must stay local: press a blocked machine itself
	# and confirm the client does not get it (the client asserts on its side).
	_clear_toast()
	await _warp(BRAKE)
	await _look("parking_brake")
	stage.call("request_interaction", "parking_brake", player, "press")
	await _wait(0.5)
	var mine := _toast()
	log_line("HOST_OWN_SAY " + mine)
	check(mine.find("止轮楔") >= 0, "the host sees its own refusal locally")
	_mark("host_pressed")


func _finish() -> void:
	var ok := failures.is_empty()
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var rep := {"probe": "act1_refusal_attribution.gd", "role": role, "passed": ok,
			"checks": checks, "failures": failures,
			"flags": (_flags().duplicate(true) if stage != null else {}), "log": lines}
		var f := FileAccess.open(out_dir.path_join("attrib_%s.json" % role), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(rep, "  "))
			f.close()
	log_line("RESULT checks=%d failures=%d passed=%s" % [checks, failures.size(), str(ok)])
	print("ATTRIB_%s %s checks=%d" % [role.to_upper(), "OK" if ok else "FAIL", checks])
	await _wait(1.0)
	get_tree().quit(0 if ok else 1)
