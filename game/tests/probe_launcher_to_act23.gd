extends SceneTree

## R6A · Launcher → Act01 → Act23 handoff probe (REAL UI click + REAL INPUT).
##
## Unlike R5 (which booted straight into `res://act1/act01.tscn`), this probe
## starts from the OFFICIAL project entry (`res://scenes/launcher.tscn`, the
## configured main scene) and performs a REAL mouse click on the
## "开始单人剧情" button through the viewport GUI input pipeline (no direct
## `_start_solo()` call, no scene-path shortcut). That click is what a player
## does; the Launcher then sets SessionHub.mode="solo" and switches to Act01.
##
## After the real Act01 boots, the probe drives the same REAL INPUT playthrough
## as R5 (Input.action_press walking + real raycast interactions; no flag is
## written by hand, no teleport, no begin_departure()) all the way to the
## real departure, and asserts the production handoff:
##   launch_cart → cart physically runs → Act1App._begin_handoff_host
##   → Act1SessionBridge.complete_act01
##   → SessionHub.complete_chapter("act01", …, "act23", res://scenes/act23.tscn)
##   → change_scene_to_file → Act23Chapter (real Act23 subtree boots).
##
## Assertions unique to R6A:
##   * the tree really booted into the Launcher (official entry, not Act01);
##   * the solo button was really clicked through GUI input;
##   * the Launcher node was freed after the switch;
##   * SessionHub is reused (mode=solo, one instance, Act1CoopNet never created);
##   * exactly TWO scene switches: Launcher→Act01 and Act01→Act23;
##   * exactly ONE valid chapter handoff into Act23Chapter;
##   * no duplicate player / session / peer objects at any point.
##
## Run:
##   godot --headless --fixed-fps 60 --path <P> res://scenes/launcher.tscn \
##         -s res://tests/probe_launcher_to_act23.gd

const CART_TUNNEL_HANDOFF_WAIT := 260  # 0.1 s steps => 26 s of game time max

const SOLO_BUTTON_TEXT := "开始单人剧情"

var launcher: Node
var solo_button: Button
var scene: Node3D
var stage: Node3D
var player: Act1StationPlayer
var failures: Array[String] = []
var log_lines: Array[String] = []
var snapshots: Dictionary = {}
var _scene_log: Array[String] = []
var _last_scene_id := 0


func _initialize() -> void:
	_watchdog.call_deferred()
	_run.call_deferred()


## Safety net: if anything goes wrong mid-coroutine, never leave Godot hanging.
func _watchdog() -> void:
	await create_timer(780.0).timeout
	push_error("PROBE_LAUNCHER_TO_ACT23 WATCHDOG TIMEOUT")
	quit(9)


## Frame-accurate scene ledger: every time `current_scene` is replaced the new
## root is appended, so scene counts never depend on coroutine timing luck.
func _process(_delta: float) -> bool:
	var cs: Node = current_scene
	var id: int = cs.get_instance_id() if cs != null else 0
	if id != _last_scene_id:
		_last_scene_id = id
		_scene_log.append(str(cs.name) if cs != null else "null")
	return false


func log_line(text: String) -> void:
	print(text)
	log_lines.append(text)


func check(ok: bool, text: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)


## Number of distinct non-null scenes the tree has shown so far. A "null" entry
## is the engine's transient frame inside change_scene_to_file, not a switch.
func _distinct_scenes() -> int:
	var seen: Array[String] = []
	for name in _scene_log:
		if name != "null" and not seen.has(name):
			seen.append(name)
	return seen.size()


func _find_button_by_text(text: String, from: Node) -> Button:
	if from == null:
		return null
	for n in from.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if b != null and b.text == text:
			return b
	return null


## REAL click: push actual mouse motion + left button press/release through the
## root window's GUI input pipeline so the Button's own signal logic fires.
## Headless root window is tiny (64x64) while controls are laid out in logical
## canvas space (1280x...), so the click point must be transformed canvas→window
## by (window_size / canvas_visible_rect_size).
func _click_button(btn: Button) -> bool:
	if btn == null:
		return false
	var vp: Window = get_root()
	# let the layout pass settle so anchors resolve to real positions
	for i in range(3):
		await physics_frame
	await create_timer(0.2).timeout
	var canvas_size: Vector2 = vp.get_visible_rect().size
	var window_size: Vector2 = vp.size
	var rect := btn.get_global_rect()
	if rect.size == Vector2.ZERO:
		log_line("CLICK button has empty rect, cannot click")
		return false
	var canvas_center := rect.get_center()
	var scale := Vector2(window_size.x / canvas_size.x, window_size.y / canvas_size.y)
	var click := Vector2(canvas_center.x * scale.x, canvas_center.y * scale.y)
	log_line("CLICK target='%s' window=%s canvas=%s rect=%s canvas_center=%s click=%s" % [btn.text, str(window_size), str(canvas_size), str(rect), str(canvas_center), str(click)])
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
	return true


func _face(target: Vector3) -> void:
	var d := target - player.global_position
	player.yaw = atan2(-d.x, -d.z)
	player.rotation.y = player.yaw


func walk(target: Vector3, seconds: float, label := "") -> void:
	_face(target)
	Input.action_press("move_forward")
	var last := player.global_position
	for i in range(int(seconds * 60.0)):
		await physics_frame
		if not is_instance_valid(player):
			break
		_face(target)
		if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < 0.55:
			break
		if i % 30 == 0:
			last = player.global_position
	Input.action_release("move_forward")
	await physics_frame
	if not is_instance_valid(player):
		return
	log_line("WALK %s target=%s pos=%s y=%.2f" % [label, str(target.snapped(Vector3(0.1, 0.1, 0.1))), str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))), player.global_position.y])


func press_id(id: String, hold := 0.14, label := "") -> bool:
	if not stage.interactables.has(id):
		check(false, "missing interactable %s" % id)
		return false
	var point: Act1Interactable = stage.interactables[id]
	var dist := player.global_position.distance_to(point.global_position)
	if dist > 4.1:
		log_line("AIM %s distance too far %.2f at %s" % [id, dist, str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	player.look_at_point(point.global_position)
	await create_timer(0.22).timeout
	var found := "none"
	if player.current_target != null:
		found = str(player.current_target.get("interaction_id"))
	log_line("AIM %s target=%s prompt=%s" % [id, found, player.current_prompt])
	if found != id:
		return false
	Input.action_press("interact")
	await create_timer(hold).timeout
	Input.action_release("interact")
	await create_timer(0.35).timeout
	return true


func hold_id(id: String, seconds: float) -> bool:
	if not stage.interactables.has(id):
		return false
	var point: Act1Interactable = stage.interactables[id]
	player.look_at_point(point.global_position)
	await create_timer(0.22).timeout
	var found := "none"
	if player.current_target != null:
		found = str(player.current_target.get("interaction_id"))
	log_line("HOLD_AIM %s target=%s" % [id, found])
	if found != id:
		return false
	Input.action_press("interact")
	for i in range(int(seconds * 60.0)):
		await physics_frame
		if not Input.is_action_pressed("interact"):
			break
	Input.action_release("interact")
	await create_timer(0.3).timeout
	return true


func _run() -> void:
	# --- Phase 0: boot into the OFFICIAL Launcher ---------------------------
	var guard := 0
	while current_scene == null and guard < 600:
		await physics_frame
		guard += 1
	launcher = current_scene
	check(launcher != null and str(launcher.name) == "Launcher",
		"project booted into the official Launcher entry (%s)" % (str(launcher.name) if launcher != null else "none"))
	if launcher == null:
		_finish(false)
		return

	guard = 0
	while solo_button == null and guard < 300:
		await create_timer(0.05).timeout
		solo_button = _find_button_by_text(SOLO_BUTTON_TEXT, launcher)
		guard += 1
	check(solo_button != null, "Launcher built the '%s' button (real UI present)" % SOLO_BUTTON_TEXT)
	if solo_button == null:
		_finish(false)
		return

	# --- Phase 1: REAL click on the solo button ------------------------------
	await _click_button(solo_button)

	guard = 0
	while (current_scene == null or str(current_scene.name) != "Act01") and guard < 900:
		await physics_frame
		guard += 1
	check(current_scene != null and str(current_scene.name) == "Act01",
		"real launch operation entered the real Act01 scene (guard=%d)" % guard)
	if current_scene == null or str(current_scene.name) != "Act01":
		_finish(false)
		return

	# --- Phase 2: Act01 boot assertions (R6A: no duplicate session/peer) ------
	await create_timer(1.1).timeout
	scene = current_scene as Node3D
	stage = scene
	player = stage.local_player

	check(root.get_node_or_null("Launcher") == null, "Launcher node was freed by the real scene switch")
	var hubs := root.find_children("SessionHub", "", true, false)
	check(hubs.size() == 1, "exactly one SessionHub instance is live (%d)" % hubs.size())
	var hub: Node = root.get_node_or_null("/root/SessionHub")
	check(hub != null, "the unified SessionHub autoload is present")
	check(str(hub.get("mode")) == "solo", "SessionHub.mode=solo after the real solo launch (got %s)" % str(hub.get("mode")))
	check(str(hub.get("current_chapter")) == "act01", "SessionHub.current_chapter=act01 at Act01 boot (got %s)" % str(hub.get("current_chapter")))
	check(stage.bridge != null and bool(stage.bridge.integrated),
		"Act1SessionBridge is bound to /root/SessionHub (integrated mode, not standalone stub)")
	check(stage.net != null and bool(stage.net.integrated), "Act1NetFacade is in integrated mode (bound to unified session)")
	check(stage.net.backend == null, "no Act1CoopNet backend was created in integrated mode")
	check(not player.downed and player.is_on_floor(), "spawn is on solid floor")
	check(root.find_children("*", "Act1CoopNet", true, false).size() == 0,
		"no Act1CoopNet peer exists after boot (%d)" % root.find_children("*", "Act1CoopNet", true, false).size())
	check(root.find_children("*", "Act1StationPlayer", true, false).size() == 1,
		"exactly one real playable player exists in Act01 (%d)" % root.find_children("*", "Act1StationPlayer", true, false).size())
	log_line("START pos=%s" % str(player.global_position))

	# --- A. entry ---------------------------------------------------------
	await walk(Vector3(0, 0, 12.0), 3.0, "entry approach")
	await walk(Vector3(0, 0, 10.6), 1.8, "door rail")
	for i in range(4):
		var ok := await press_id("shove_gantry", 0.10)
		if ok:
			await create_timer(0.6).timeout
		if stage.flags["debris_cleared"]:
			break
	check(stage.flags["debris_cleared"], "collapsed gantry physically cleared from the door rail")
	await walk(Vector3(3.1, 0, 10.35), 2.2, "latch side")
	await press_id("release_latch", 0.12)
	check(stage.flags["latch_released"], "mechanical latch released")
	await walk(Vector3(1.0, 0, 10.0), 1.6, "door front")
	await hold_id("door_handle", 6.2)
	check(stage.flags["door_open"], "industrial door opened and collider moved with it")
	await walk(Vector3(0, 0, 6.5), 2.5, "through doorway")
	check(player.global_position.z < 8.0, "walked through the open doorway (no invisible wall)")

	# --- B. power cart ----------------------------------------------------
	await walk(Vector3(0, 0, 4.0), 2.0, "airlock exit")
	await walk(Vector3(-3.0, 0, 0.4), 2.5, "power room west")
	await walk(Vector3(-7.8, 0, 0.4), 3.0, "power room north")
	await walk(Vector3(-8.0, 0, -2.5), 1.7, "cart rear")
	await press_id("cart_push", 0.12)
	check(player.external_hold, "gripped the 70 kg power trolley handle")
	Input.action_press("move_forward")
	for i in range(150):
		await physics_frame
	Input.action_release("move_forward")
	await create_timer(0.3).timeout
	log_line("CART pushed to %.2f path_blocked=%s" % [stage.builder.power_cart.global_position.x, str(stage.builder.power_cart.path_blocked)])
	Input.action_press("act1_cancel")
	await create_timer(0.16).timeout
	Input.action_release("act1_cancel")
	await create_timer(0.4).timeout
	check(not player.external_hold, "released trolley handle")
	await walk(Vector3(-4.6, 0, -0.4), 2.4, "around cart north")
	await walk(Vector3(-1.0, 0, -0.5), 3.0, "rail bracket")
	await walk(Vector3(-0.95, 0, -1.15), 1.2, "bracket approach")
	await press_id("rail_shove", 0.10)
	await create_timer(0.8).timeout
	check(stage.flags["rail_cleared"], "rail bracket cleared from the trolley path")
	await walk(Vector3(-1.0, 0, -0.4), 1.8, "return north")
	await walk(Vector3(-7.8, 0, -0.4), 3.2, "cart rear north")
	await walk(Vector3(-7.8, 0, -2.55), 1.3, "cart rear center")
	await walk(Vector3(-7.2, 0, -2.55), 0.8, "cart handle")
	await press_id("cart_push", 0.12)
	check(player.external_hold, "regripped trolley after clearing the rail")
	Input.action_press("move_forward")
	for i in range(520):
		await physics_frame
	Input.action_release("move_forward")
	await create_timer(1.0).timeout
	Input.action_press("act1_cancel")
	await create_timer(0.16).timeout
	Input.action_release("act1_cancel")
	await create_timer(0.4).timeout
	check(stage.builder.power_cart.docked, "trolley physically rolled into the dock tolerance")
	check(stage.flags["power_docked"], "host registered the physical dock")
	await walk(Vector3(1.5, 0, -0.5), 1.8, "cart west north")
	await walk(Vector3(1.5, 0, -5.0), 2.4, "socket west")
	await walk(Vector3(1.95, 0, -5.0), 0.8, "winch")
	await press_id("power_winch", 0.12)
	await create_timer(2.5).timeout
	check(stage.builder.power_cart.module_transferred_flag, "power module physically traversed the guide rail")
	await walk(Vector3(2.4, 0, -4.3), 1.2, "clamp west")
	await press_id("power_clamp", 0.12)
	check(stage.flags["power_ready"], "power module clamped and control circuit live")
	snapshots["power"] = stage.build_snapshot(0)

	# --- C. ventilation ---------------------------------------------------
	await walk(Vector3(0, 0, -8.0), 3.0, "power exit")
	await walk(Vector3(-1.0, 0, -12.8), 3.0, "vent threshold")
	check(player.global_position.z < -11.5, "walked into the ventilation hall")
	await walk(Vector3(7.0, 0, -14.8), 4.0, "hall north east")
	await walk(Vector3(7.0, 0, -17.5), 2.0, "hall east")
	await walk(Vector3(7.7, 0, -22.3), 2.5, "rotor lock")
	await press_id("rotor_lock", 0.12)
	check(stage.flags["rotor_lock_released"], "rotor lock physically removed")
	await walk(Vector3(8.1, 0, -28.15), 3.8, "coupling")
	await press_id("coupling", 0.12)
	check(stage.flags["coupling_engaged"], "drive coupling engaged")
	await walk(Vector3(7.0, 0, -14.8), 4.5, "hall return north")
	await walk(Vector3(-7.8, 0, -14.8), 7.0, "control gallery north")
	await walk(Vector3(-7.8, 0, -18.0), 1.8, "control gallery")
	await walk(Vector3(-7.8, 0, -23.0), 2.4, "fan start")
	await press_id("start_fan", 0.12)
	check(stage.builder.vent.running, "main fan started")
	check(stage.flags["fan_started"], "fan start registered")
	await walk(Vector3(-7.8, 0, -14.8), 3.0, "west gallery north")
	await walk(Vector3(7.0, 0, -14.8), 7.0, "damper side north")
	await walk(Vector3(7.0, 0, -18.0), 1.8, "damper side")
	await walk(Vector3(8.0, 0, -29.6), 5.0, "damper control")
	await press_id("damper", 0.12)
	check(stage.flags["damper_open"], "main duct damper opened")
	await walk(Vector3(8.0, 0, -34.0), 3.0, "safe south")
	var wait := 0
	while wait < 12 and not stage.flags["vent_complete"]:
		await create_timer(1.0).timeout
		wait += 1
		log_line("VENT t=%d speed=%.2f damper=%.2f pressure=%.2f complete=%s pos=%s" % [wait, stage.builder.vent.speed, stage.builder.vent.damper, stage.builder.vent.pressure, str(stage.flags["vent_complete"]), str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	check(stage.flags["vent_complete"], "6-second live pressure test completed")
	snapshots["vent"] = stage.build_snapshot(0)

	# --- D. station -------------------------------------------------------
	await walk(Vector3(7.0, 0, -35.4), 2.5, "hall south")
	await walk(Vector3(0.0, 0, -35.6), 4.0, "hall center")
	await walk(Vector3(0.0, 0, -37.6), 2.4, "station threshold")
	check(player.global_position.z < -37.0, "station threshold is walkable")
	await walk(Vector3(-5.6, 0, -40.5), 3.5, "station west")
	await walk(Vector3(-5.6, 0, -44.3), 2.5, "chock approach")
	await walk(Vector3(-5.62, 0, -45.5), 1.4, "chock")
	await press_id("chock", 0.12)
	check(stage.flags["chock_removed"], "wheel chock removed")
	await walk(Vector3(-4.5, 0, -40.6), 2.4, "station return")
	await walk(Vector3(0.0, 0, -38.2), 2.0, "station center")
	await walk(Vector3(7.2, 0, -38.2), 3.5, "ramp north")
	await walk(Vector3(7.2, 1.55, -43.0), 3.5, "platform ramp")
	check(player.global_position.y > 1.2, "walked up the boarding ramp")
	await walk(Vector3(7.35, 1.55, -48.2), 3.0, "platform brake side")
	await walk(Vector3(6.55, 1.55, -48.6), 1.2, "brake")
	await press_id("parking_brake", 0.12)
	check(stage.flags["brake_released"], "parking brake released")
	await walk(Vector3(7.35, 1.55, -43.9), 3.0, "platform cargo side")
	await walk(Vector3(6.55, 1.55, -43.0), 1.2, "cargo strap")
	await press_id("cargo", 0.12)
	check(stage.flags["cargo_secured"], "cargo restraint locked")

	# boarding interlock is evaluated by the real game logic from the player's
	# physical position; nothing here sets it.
	await walk(Vector3(5.6, 1.55, -47.0), 2.0, "platform edge")
	await walk(Vector3(3.6, 1.55, -47.0), 2.0, "cart side")
	await walk(Vector3(0.0, 1.55, -48.0), 2.5, "cart deck")
	check(stage.all_active_aboard(), "player physically inside the mine cart (all_active_aboard from real position)")
	check(stage.all_active_ready(), "cooperation credit satisfied by real interactions")

	# --- E. departure interlock + real launch -----------------------------
	await walk(Vector3(-3.0, 1.55, -50.0), 2.6, "launch console")
	var pre_prompt := str(stage.builder.mine_cart._launch_prompt())
	log_line("LAUNCH_PROMPT_BEFORE=%s" % pre_prompt)
	check(not pre_prompt.contains("未"), "launch prompt reports the interlock as satisfied (no unmet condition)")
	await press_id("launch_cart", 0.12)
	check(stage.flags["departure_started"], "departure interlock accepted by the real launch_cart interaction")
	check(stage.builder.mine_cart.departing, "mine cart entered departing state")
	check(player.external_hold, "rider attached to moving cart")

	# duplicate-departure guard: a second press must not restart anything
	var z_before: float = stage.builder.mine_cart.global_position.z
	await press_id("launch_cart", 0.12)
	await create_timer(2.0).timeout
	if is_instance_valid(stage) and stage.builder != null and stage.builder.mine_cart != null:
		var z_after: float = stage.builder.mine_cart.global_position.z
		check(z_after < z_before - 2.0, "cart physically travelled down the rails (z %.2f -> %.2f)" % [z_before, z_after])
		snapshots["launch"] = stage.build_snapshot(0)
	else:
		log_line("NOTE cart left the Act01 scene before the 2 s sample (handoff already fired)")

	# --- F. handoff: Act01 completion → SessionHub → Act23 -----------------
	hub = root.get_node_or_null("/root/SessionHub")
	check(hub != null, "single unified SessionHub autoload is present")
	for i in range(CART_TUNNEL_HANDOFF_WAIT):
		await create_timer(0.1).timeout
		if current_scene != null and str(current_scene.name) == "Act23Chapter":
			break
	# let Act23 build its world
	await create_timer(2.0).timeout

	var switches := _distinct_scenes() - 1
	log_line("SCENE_LEDGER=%s (a 'null' entry is the engine's transient frame inside change_scene_to_file)" % str(_scene_log))

	var chapter := str(hub.get("current_chapter")) if hub != null else "no-hub"
	var history: Dictionary = hub.get("chapter_history") as Dictionary if hub != null else {}
	var act01_rec: Dictionary = history.get("act01", {}) as Dictionary
	var spawn: Dictionary = hub.get("pending_spawn") as Dictionary if hub != null else {}
	var scene_name := str(current_scene.name) if current_scene != null else "null"
	log_line("HANDOFF current_chapter=%s scene=%s switches=%d" % [chapter, scene_name, switches])
	log_line("HANDOFF act01_record=%s" % JSON.stringify(act01_rec))
	log_line("HANDOFF spawn_from=%s spawn_to=%s spawn_keys=%s" % [str(spawn.get("from_chapter", "")), str(spawn.get("to_chapter", "")), str(spawn.keys())])

	check(act01_rec.get("completed", false) == true, "SessionHub recorded chapter_history.act01.completed=true (real completion event)")
	check(str(act01_rec.get("chapter", "")) == "act01", "completion payload carries chapter=act01")
	check(str(act01_rec.get("mode", "")) != "", "completion payload carries a real mode (%s)" % str(act01_rec.get("mode", "")))
	check((act01_rec.get("credits", {}) as Dictionary).size() > 0, "completion payload carries the real participation ledger")
	check(chapter == "act23", "SessionHub.current_chapter switched to act23")
	check(str(spawn.get("from_chapter", "")) == "act01" and str(spawn.get("to_chapter", "")) == "act23",
		"handoff spawn payload declares act01 -> act23")
	check(spawn.has("mode") and spawn.has("result") and spawn.has("launch_seconds"),
		"handoff spawn payload carries the documented contract keys (mode/result/launch_seconds)")
	check(scene_name == "Act23Chapter", "the tree really entered the Act23 wrapper node (not just a log line)")
	check(switches == 2, "exactly two scene switches: Launcher->Act01 and Act01->Act23 (got %d)" % switches)
	check(_scene_log.count("Act23Chapter") == 1, "exactly one valid chapter handoff into Act23Chapter (%d)" % _scene_log.count("Act23Chapter"))
	check(_scene_log.count("Act01") == 1, "exactly one Act01 scene boot (%d)" % _scene_log.count("Act01"))

	# wrapper must point at the real Act23 subtree, and that subtree must boot
	var wrapper: Node = current_scene
	var entry: Node = wrapper.get_node_or_null("Act23Entry") if wrapper != null else null
	var slice: Node = entry.get_node_or_null("MovingCartSlice") if entry != null else null
	check(entry != null, "scenes/act23.tscn instances res://act23/act23_entry.tscn")
	check(slice != null, "Act23Entry instantiated the real MovingCartSlice subtree")
	check(slice != null and slice.get_node_or_null("MovingCart") != null, "Act23 world built: MovingCart present")
	check(slice != null and slice.get_node_or_null("Player1") != null, "Act23 world built: Player1 present")
	check(slice != null and slice.get_node_or_null("LevelFlow") != null, "Act23 world built: LevelFlow present")

	# old Act01 scene / player must be gone, session/peer must not be duplicated
	check(root.get_node_or_null("Act01") == null, "old Act01 scene node was freed by the scene switch")
	check(root.find_children("LocalPlayer", "", true, false).size() == 0,
		"no duplicate Act01 player object remains after the handoff (%d)" % root.find_children("LocalPlayer", "", true, false).size())
	hubs = root.find_children("SessionHub", "", true, false)
	check(hubs.size() == 1, "exactly one SessionHub instance after the handoff (%d)" % hubs.size())
	var unified_net: Node = hub.get_node_or_null("CoopNet") if hub != null else null
	check(unified_net != null, "the unified session still owns /root/SessionHub/CoopNet")
	# Act 23 ships its own scene-local node also named "CoopNet" (its chapter RPC
	# surface). In a non-networked run it must stay offline: no socket of its own.
	var act23_nets := root.find_children("CoopNet", "", true, false)
	var act23_net: Node = null
	for n in act23_nets:
		if n != unified_net:
			act23_net = n
	log_line("COOPNET_NODES=%s" % str(act23_nets.map(func(n: Node) -> String: return str(root.get_path_to(n)))))
	check(act23_nets.size() == 2, "Act23's own chapter net node is present next to the unified one (%d total)" % act23_nets.size())
	check(act23_net != null and str(act23_net.get("mode")) == "offline",
		"Act23's chapter net stayed offline in solo (mode=%s) — it did not open a socket" % (str(act23_net.get("mode")) if act23_net != null else "null"))
	var global_peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	check(not (global_peer is ENetMultiplayerPeer),
		"no ENet socket is open in this solo run (single offline peer): %s" % (global_peer.get_class() if global_peer != null else "null"))
	var act1_nets := root.find_children("*", "Act1CoopNet", true, false)
	check(act1_nets.size() == 0, "no second Act1CoopNet peer was created in integrated mode (%d)" % act1_nets.size())

	# no duplicate completion: the record must not grow or flip after the switch
	var act01_rec_after: Dictionary = (hub.get("chapter_history") as Dictionary).get("act01", {}) if hub != null else {}
	check(act01_rec_after.get("time", 0) == act01_rec.get("time", -1),
		"chapter_history.act01 was not rewritten a second time after the switch")

	_finish(failures.is_empty(), { "chapter": chapter, "scene": scene_name, "completion": act01_rec, "switches": switches })


func _finish(passed: bool, extra: Dictionary = {}) -> void:
	var report := {
		"passed": passed,
		"failures": failures,
		"mode": "launcher-real-click-integrated-real-input",
		"entry": "res://scenes/launcher.tscn",
		"scene_ledger": _scene_log,
	}
	for k in extra:
		report[k] = extra[k]
	if snapshots.has("launch"):
		report["flags"] = snapshots["launch"].get("flags", {})
		report["credits"] = snapshots["launch"].get("credits", {})
	report["log"] = log_lines
	var f := FileAccess.open("res://../tests-out/r6a_launcher_to_act23_full_run.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	log_line("RESULT failures=%d" % failures.size())
	if passed:
		print("PROBE_LAUNCHER_TO_ACT23_OK")
	else:
		push_error("PROBE_LAUNCHER_TO_ACT23_FAIL " + str(failures))
	quit(0 if passed else 1)