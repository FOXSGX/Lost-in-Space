extends SceneTree

## R6A · Launcher "创建主机" entry smoke.
##
## Verifies the EXISTING host-mode button still works after the R6A rewiring:
## a real click on "创建主机（等待队友加入）" starts the unified SessionHub
## ENet host (one socket) and enters the REAL Act01, with no duplicate
## SessionHub / peer / player objects. This is a boot smoke — it does not play
## the chapter (co-op Act01 playthrough stays out of R6A scope, same as R5).
##
## Run:
##   godot --headless --fixed-fps 60 --path <P> res://scenes/launcher.tscn \
##         -s res://tests/probe_launcher_host_entry.gd

const HOST_BUTTON_TEXT := "创建主机（等待队友加入）"

var launcher: Node
var failures: Array[String] = []
var log_lines: Array[String] = []


func _initialize() -> void:
	_watchdog.call_deferred()
	_run.call_deferred()


func _watchdog() -> void:
	await create_timer(120.0).timeout
	push_error("PROBE_LAUNCHER_HOST_ENTRY WATCHDOG TIMEOUT")
	quit(9)


func log_line(text: String) -> void:
	print(text)
	log_lines.append(text)


func check(ok: bool, text: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)


func _find_button_by_text(text: String, from: Node) -> Button:
	if from == null:
		return null
	for n in from.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if b != null and b.text == text:
			return b
	return null


func _click_button(btn: Button) -> void:
	var vp: Window = get_root()
	for i in range(3):
		await physics_frame
	await create_timer(0.2).timeout
	var canvas_size: Vector2 = vp.get_visible_rect().size
	var window_size: Vector2 = vp.size
	var scale := Vector2(window_size.x / canvas_size.x, window_size.y / canvas_size.y)
	var click := btn.get_global_rect().get_center() * scale
	log_line("CLICK target='%s' click=%s" % [btn.text, str(click)])
	var motion := InputEventMouseMotion.new()
	motion.position = click
	motion.global_position = click
	vp.push_input(motion)
	await create_timer(0.10).timeout
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click
	press.global_position = click
	vp.push_input(press)
	await create_timer(0.08).timeout
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click
	release.global_position = click
	vp.push_input(release)
	await create_timer(0.25).timeout


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 300:
		await physics_frame
		guard += 1
	launcher = current_scene
	check(launcher != null and str(launcher.name) == "Launcher", "project booted into the official Launcher entry")
	if launcher == null:
		_finish()
		return

	var btn: Button = null
	for i in range(200):
		btn = _find_button_by_text(HOST_BUTTON_TEXT, launcher)
		if btn != null:
			break
		await create_timer(0.05).timeout
	check(btn != null, "Launcher built the '%s' button (real UI present)" % HOST_BUTTON_TEXT)
	if btn == null:
		_finish()
		return

	await _click_button(btn)

	guard = 0
	while (current_scene == null or str(current_scene.name) != "Act01") and guard < 900:
		await physics_frame
		guard += 1
	check(current_scene != null and str(current_scene.name) == "Act01",
		"host launch entered the real Act01 scene (guard=%d)" % guard)
	if current_scene == null or str(current_scene.name) != "Act01":
		_finish()
		return
	await create_timer(1.2).timeout

	var stage: Node = current_scene
	var hub: Node = root.get_node_or_null("/root/SessionHub")
	check(hub != null, "unified SessionHub autoload is present")
	check(str(hub.get("mode")) == "host", "SessionHub.mode=host after the real host launch (got %s)" % str(hub.get("mode")))
	check(bool(hub.call("is_online")) == true, "unified session reports online=true (host socket listening)")
	check(str(hub.get("current_chapter")) == "act01", "SessionHub.current_chapter=act01 at Act01 boot")
	check(stage.get("bridge") != null and bool(stage.get("bridge").integrated), "Act1SessionBridge is in integrated mode")
	check(stage.get("net") != null and bool(stage.get("net").integrated), "Act1NetFacade is in integrated mode (no Act1CoopNet backend)")
	check(stage.get("net").backend == null, "no Act1CoopNet backend was created")
	var hubs := root.find_children("SessionHub", "", true, false)
	check(hubs.size() == 1, "exactly one SessionHub instance (%d)" % hubs.size())
	check(root.find_children("*", "Act1CoopNet", true, false).size() == 0,
		"no Act1CoopNet peer exists (%d)" % root.find_children("*", "Act1CoopNet", true, false).size())
	var global_peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	check(global_peer is ENetMultiplayerPeer,
		"exactly one ENet socket is open (the unified host peer): %s" % (global_peer.get_class() if global_peer != null else "null"))
	check(root.find_children("*", "Act1StationPlayer", true, false).size() == 1,
		"exactly one real playable player exists in Act01 (%d)" % root.find_children("*", "Act1StationPlayer", true, false).size())
	check(root.get_node_or_null("Launcher") == null, "Launcher node was freed by the real scene switch")

	_finish()


func _finish() -> void:
	var report := {
		"passed": failures.is_empty(),
		"failures": failures,
		"mode": "launcher-host-click-boot-smoke",
		"entry": "res://scenes/launcher.tscn",
		"log": log_lines,
	}
	var f := FileAccess.open("res://../tests-out/r6a_launcher_host_entry.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	log_line("RESULT failures=%d" % failures.size())
	if failures.is_empty():
		print("PROBE_LAUNCHER_HOST_ENTRY_OK")
	else:
		push_error("PROBE_LAUNCHER_HOST_ENTRY_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)