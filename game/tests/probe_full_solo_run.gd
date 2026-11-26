extends SceneTree

## AUDIT K · 五幕连续单人流程探针（独立任务 K · 只读验收）
##
## 这不是生产代码，也不被任何场景/Autoload 加载；只在 `--script` 显式运行时执行。
##
## 目标：从正式 Launcher 入口（res://scenes/launcher.tscn）用真实鼠标点击进入，
## 之后全程只用玩家输入动作（移动/交互/拾取/绞盘等）推进五幕：
##   Launcher → Act01 → Act23 → Act04 → Act05(Main) → Finale
##
## 约束（任务书 §验证原则）：
##   * 不写任何任务完成 flag；不调用 complete_chapter；不直接切换场景跳过章节。
##   * 不传送（本探针没有任何 teleport/restore_at/snap_to_distance 调用）。
##   * 唯一的“非输入”操作是相机朝向（设置玩家 yaw），这是视角而不是位移。
##
## 模式：
##   --audit-mode=full    正式连续流程（默认）：Launcher 真实点击 → Act01 → … → Finale
##   --audit-mode=act23   开发/分段：直接以 act23_entry.tscn 启动并驱动第二三幕
##   --audit-mode=act04   开发/分段：直接以 scenes/act4.tscn 启动并驱动第四幕
##   --audit-mode=act05   开发/分段：直接以 scenes/main.tscn 启动并驱动第五幕
## 分段模式只用于开发定位，**不**计入“连续通关”。

const SOLO_BUTTON_TEXT := "开始单人剧情"
const FINALE_NAME := "Finale"
## Scene node names that count as "the run reached its verified conclusion".
## `Finale` is the full campaign ending; `ResonanceStarDemoEnding` is the demo
## build's ending reached through the same production Act05 gate.
const ENDING_SCENES: Array[String] = ["Finale", "ResonanceStarDemoEnding"]

var mode: String = "full"
var log_lines: Array[String] = []
var failures: Array[String] = []
var checks: int = 0
var started_msec: int = 0
var stage_records: Array[Dictionary] = []
var _scene_log: Array[String] = []
var _last_scene_id: int = 0
var _current_stage: String = "boot"
var audit_out: String = ""

var player: Node = null
var hub: Node = null


func _initialize() -> void:
	_parse_args()
	started_msec = Time.get_ticks_msec()
	_watchdog.call_deferred()
	_run.call_deferred()


func _parse_args() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--audit-mode="):
			mode = arg.split("=")[1]
		elif arg.begins_with("--audit-out="):
			audit_out = arg.split("=")[1]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-mode="):
			mode = arg.split("=")[1]
		elif arg.begins_with("--audit-out="):
			audit_out = arg.split("=")[1]


func _watchdog() -> void:
	await create_timer(900.0).timeout
	push_error("FULL_SOLO_WATCHDOG_TIMEOUT stage=%s" % _current_stage)
	quit(9)


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


func check(ok: bool, text: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append("[%s] %s" % [_current_stage, text])
	return ok


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_scene(name: String, timeout_s: float = 30.0) -> bool:
	var waited := 0.0
	while waited < timeout_s:
		if current_scene != null and str(current_scene.name) == name:
			return true
		await create_timer(0.1).timeout
		waited += 0.1
	return current_scene != null and str(current_scene.name) == name


func _wait_scene_any(names: Array, timeout_s: float = 30.0) -> bool:
	var waited := 0.0
	while waited < timeout_s:
		if current_scene != null and names.has(str(current_scene.name)):
			return true
		await create_timer(0.1).timeout
		waited += 0.1
	return current_scene != null and names.has(str(current_scene.name))


func _find_button_by_text(text: String, from: Node) -> Button:
	if from == null:
		return null
	for n in from.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if b != null and b.text == text:
			return b
	return null


## 真实点击：把鼠标移动 + 左键按下/抬起推进 root window 的 GUI 输入管线。
## headless 的 root window 只有 64x64，而控件布局在 1280 逻辑画布上，所以要
## 把画布坐标按 (window_size / canvas_visible_rect) 变换到窗口坐标。
func _click_button(btn: Button) -> bool:
	if btn == null:
		return false
	var vp: Window = get_root()
	for i in range(3):
		await physics_frame
	await _wait(0.2)
	var canvas_size: Vector2 = vp.get_visible_rect().size
	var window_size: Vector2 = vp.size
	var rect := btn.get_global_rect()
	if rect.size == Vector2.ZERO:
		log_line("CLICK button has empty rect, cannot click")
		return false
	var canvas_center := rect.get_center()
	var scale := Vector2(window_size.x / canvas_size.x, window_size.y / canvas_size.y)
	var click := Vector2(canvas_center.x * scale.x, canvas_center.y * scale.y)
	log_line("CLICK target='%s' window=%s canvas=%s rect=%s click=%s" % [btn.text, str(window_size), str(canvas_size), str(rect), str(click)])
	var motion := InputEventMouseMotion.new()
	motion.position = click
	motion.global_position = click
	vp.push_input(motion)
	await _wait(0.10)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click
	press.global_position = click
	vp.push_input(press)
	await _wait(0.08)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click
	release.global_position = click
	vp.push_input(release)
	await _wait(0.25)
	return true


func _run() -> void:
	hub = root.get_node_or_null("/root/SessionHub")
	match mode:
		"full":
			await _run_full()
		"act01":
			await _run_act01_only()
		"act23":
			await _run_act23_only()
		"act04":
			await _run_act04_only()
		"act05":
			await _run_act05_only()
		_:
			push_error("unknown audit mode %s" % mode)
			_finish(false)
			return
	_finish(failures.is_empty())


# ---------------------------------------------------------------------------
# FULL: real Launcher click → Act01 → Act23 → Act04 → Act05 → Finale
# ---------------------------------------------------------------------------
func _run_full() -> void:
	_current_stage = "launcher"
	var guard := 0
	while current_scene == null and guard < 600:
		await physics_frame
		guard += 1
	var launcher: Node = current_scene
	check(launcher != null and str(launcher.name) == "Launcher", "booted into the official Launcher entry")
	if launcher == null:
		return
	var btn: Button = null
	guard = 0
	while btn == null and guard < 300:
		await _wait(0.05)
		btn = _find_button_by_text(SOLO_BUTTON_TEXT, launcher)
		guard += 1
	check(btn != null, "Launcher built the solo button")
	if btn == null:
		return
	await _click_button(btn)
	check(await _wait_scene("Act01", 20.0), "real Launcher click entered Act01")
	if str(current_scene.name) != "Act01":
		return
	await _wait(1.1)

	_current_stage = "act01"
	var ok01: Variant = await _drive_act01()
	if ok01 != true:
		check(false, "Act01 stage aborted")
		return
	_current_stage = "act23"
	if not await _wait_scene("Act23Chapter", 30.0):
		check(false, "Act01 handoff reached Act23Chapter")
		return
	await _wait(2.0)
	var ok23: Variant = await _drive_act23()
	if ok23 != true:
		check(false, "Act23 stage aborted")
		return
	_current_stage = "act04"
	if not await _wait_scene_any(["Resonance04", "Act4"], 30.0):
		check(false, "Act23 handoff reached Act4")
		return
	await _wait(1.0)
	var ok04: Variant = await _drive_act04()
	if ok04 != true:
		check(false, "Act04 stage aborted")
		return
	_current_stage = "act05"
	if not await _wait_scene("Main", 30.0):
		check(false, "Act04 handoff reached Act05 (Main)")
		return
	await _wait(1.0)
	var ok05: Variant = await _drive_act05()
	if ok05 != true:
		check(false, "Act05 stage aborted")
		return
	_current_stage = "finale"
	if not await _wait_scene_any(ENDING_SCENES, 30.0):
		check(false, "Act05 settlement reached the ending scene")
		return
	await _wait(1.5)
	check(true, "reached the real ending scene in one continuous process")


func _run_act01_only() -> void:
	_current_stage = "launcher"
	var guard := 0
	while current_scene == null and guard < 600:
		await physics_frame
		guard += 1
	var launcher: Node = current_scene
	check(launcher != null and str(launcher.name) == "Launcher", "booted into the official Launcher entry")
	if launcher == null:
		return
	var btn: Button = null
	guard = 0
	while btn == null and guard < 300:
		await _wait(0.05)
		btn = _find_button_by_text(SOLO_BUTTON_TEXT, launcher)
		guard += 1
	check(btn != null, "Launcher built the solo button")
	if btn == null:
		return
	await _click_button(btn)
	check(await _wait_scene("Act01", 20.0), "real Launcher click entered Act01")
	if str(current_scene.name) != "Act01":
		return
	await _wait(1.1)
	_current_stage = "act01"
	var ok01: Variant = await _drive_act01()
	if ok01 != true:
		check(false, "Act01 stage aborted")
		return
	_current_stage = "act01_handoff"
	check(await _wait_scene("Act23Chapter", 60.0), "Act01 handoff reached Act23Chapter")


func _run_act23_only() -> void:
	_current_stage = "act23"
	if not await _wait_scene("Act23Entry", 30.0):
		if not await _wait_scene("Act23Chapter", 5.0):
			check(false, "booted Act23 entry")
			return
	await _wait(2.0)
	var ok23: Variant = await _drive_act23()
	if ok23 != true:
		check(false, "Act23 stage aborted")
		return
	_current_stage = "act04"
	check(await _wait_scene_any(["Resonance04", "Act4"], 30.0), "Act23 handoff reached Act4")


func _run_act04_only() -> void:
	_current_stage = "act04"
	check(await _wait_scene_any(["Resonance04", "Act4"], 30.0), "booted Act4")
	await _wait(1.0)
	var ok04: Variant = await _drive_act04()
	if ok04 != true:
		check(false, "Act04 stage aborted")
		return
	_current_stage = "act05"
	check(await _wait_scene("Main", 30.0), "Act04 handoff reached Act05 (Main)")


func _run_act05_only() -> void:
	_current_stage = "act05"
	check(await _wait_scene("Main", 30.0), "booted Act05 (Main)")
	await _wait(1.0)
	var ok05: Variant = await _drive_act05()
	if ok05 != true:
		check(false, "Act05 stage aborted")
		return
	_current_stage = "finale"
	check(await _wait_scene_any(ENDING_SCENES, 30.0), "Act05 settlement reached the ending scene")


# ---------------------------------------------------------------------------
# Act01 (真实输入；与 R6A 探针相同的走路/交互路径)
# ---------------------------------------------------------------------------
var stage: Node = null


func _face_act1(target: Vector3) -> void:
	var d: Vector3 = target - player.global_position
	player.set("yaw", atan2(-d.x, -d.z))
	player.rotation.y = float(player.get("yaw"))


func _walk_act1(target: Vector3, seconds: float, label := "") -> void:
	_face_act1(target)
	Input.action_press("move_forward")
	for i in range(int(seconds * 60.0)):
		await physics_frame
		if not is_instance_valid(player):
			return
		_face_act1(target)
		if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < 0.55:
			break
	Input.action_release("move_forward")
	await physics_frame
	if is_instance_valid(player):
		log_line("WALK %s target=%s pos=%s" % [label, str(target), str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])


func _press_act1(id: String, hold := 0.14) -> bool:
	var points: Dictionary = stage.get("interactables") as Dictionary
	if not points.has(id):
		check(false, "missing interactable %s" % id)
		return false
	var point: Node3D = points[id] as Node3D
	player.call("look_at_point", point.global_position)
	await _wait(0.22)
	var found := "none"
	if player.get("current_target") != null:
		found = str((player.get("current_target") as Object).get("interaction_id"))
	log_line("AIM %s target=%s" % [id, found])
	if found != id:
		return false
	Input.action_press("interact")
	await _wait(hold)
	Input.action_release("interact")
	await _wait(0.35)
	return true


func _hold_act1(id: String, seconds: float) -> bool:
	var points: Dictionary = stage.get("interactables") as Dictionary
	if not points.has(id):
		return false
	var point: Node3D = points[id] as Node3D
	player.call("look_at_point", point.global_position)
	await _wait(0.22)
	var found := "none"
	if player.get("current_target") != null:
		found = str((player.get("current_target") as Object).get("interaction_id"))
	if found != id:
		return false
	Input.action_press("interact")
	for i in range(int(seconds * 60.0)):
		await physics_frame
		if not Input.is_action_pressed("interact"):
			break
	Input.action_release("interact")
	await _wait(0.3)
	return true


## 旧版本没有 `_vent_hint`，只返回风速/风压那一行；同一段探针可跑改动前后。
func _act1_hud_text() -> String:
	var hud: Node = stage.get("hud") as Node
	if hud == null:
		return "<no hud>"
	var out := ""
	var wind: Variant = hud.get("_wind_value")
	if wind is Label:
		out += (wind as Label).text
	var hint: Variant = hud.get("_vent_hint")
	if hint is Label:
		var h := (hint as Label).text
		if h != "":
			out += " | " + h
	return out


func _drive_act01() -> bool:
	stage = current_scene
	player = stage.get("local_player") as Node
	var flags: Dictionary = stage.get("flags") as Dictionary
	if player == null:
		check(false, "Act01 has no local player")
		return false
	log_line("ACT01_START pos=%s" % str(player.global_position))

	await _walk_act1(Vector3(0, 0, 12.0), 3.0, "entry approach")
	await _walk_act1(Vector3(0, 0, 10.6), 1.8, "door rail")
	for i in range(4):
		if await _press_act1("shove_gantry", 0.10):
			await _wait(0.6)
		if bool(flags.get("debris_cleared", false)):
			break
	check(bool(flags.get("debris_cleared", false)), "collapsed gantry cleared")
	await _walk_act1(Vector3(3.1, 0, 10.35), 2.2, "latch side")
	await _press_act1("release_latch", 0.12)
	check(bool(flags.get("latch_released", false)), "mechanical latch released")
	await _walk_act1(Vector3(1.0, 0, 10.0), 1.6, "door front")
	await _hold_act1("door_handle", 6.2)
	check(bool(flags.get("door_open", false)), "industrial door opened")
	await _walk_act1(Vector3(0, 0, 6.5), 2.5, "through doorway")
	check(player.global_position.z < 8.0, "walked through the open doorway")

	await _walk_act1(Vector3(0, 0, 4.0), 2.0, "airlock exit")
	await _walk_act1(Vector3(-3.0, 0, 0.4), 2.5, "power room west")
	await _walk_act1(Vector3(-7.8, 0, 0.4), 3.0, "power room north")
	await _walk_act1(Vector3(-8.0, 0, -2.5), 1.7, "cart rear")
	await _press_act1("cart_push", 0.12)
	check(bool(player.get("external_hold")), "gripped the power trolley")
	Input.action_press("move_forward")
	for i in range(150):
		await physics_frame
	Input.action_release("move_forward")
	await _wait(0.3)
	Input.action_press("act1_cancel")
	await _wait(0.16)
	Input.action_release("act1_cancel")
	await _wait(0.4)
	await _walk_act1(Vector3(-4.6, 0, -0.4), 2.4, "around cart north")
	await _walk_act1(Vector3(-1.0, 0, -0.5), 3.0, "rail bracket")
	await _walk_act1(Vector3(-0.95, 0, -1.15), 1.2, "bracket approach")
	await _press_act1("rail_shove", 0.10)
	await _wait(0.8)
	check(bool(flags.get("rail_cleared", false)), "rail bracket cleared")
	await _walk_act1(Vector3(-1.0, 0, -0.4), 1.8, "return north")
	await _walk_act1(Vector3(-7.8, 0, -0.4), 3.2, "cart rear north")
	await _walk_act1(Vector3(-7.8, 0, -2.55), 1.3, "cart rear center")
	await _walk_act1(Vector3(-7.2, 0, -2.55), 0.8, "cart handle")
	await _press_act1("cart_push", 0.12)
	Input.action_press("move_forward")
	for i in range(520):
		await physics_frame
	Input.action_release("move_forward")
	await _wait(1.0)
	Input.action_press("act1_cancel")
	await _wait(0.16)
	Input.action_release("act1_cancel")
	await _wait(0.4)
	check(bool(flags.get("power_docked", false)), "trolley docked")
	await _walk_act1(Vector3(1.5, 0, -0.5), 1.8, "cart west north")
	await _walk_act1(Vector3(1.5, 0, -5.0), 2.4, "socket west")
	await _walk_act1(Vector3(1.95, 0, -5.0), 0.8, "winch")
	await _press_act1("power_winch", 0.12)
	await _wait(2.5)
	check(bool(flags.get("power_ready", false)) or bool((stage.get("builder").get("power_cart") as Object).get("module_transferred_flag")), "power module traversed the guide rail")
	await _walk_act1(Vector3(2.4, 0, -4.3), 1.2, "clamp west")
	await _press_act1("power_clamp", 0.12)
	check(bool(flags.get("power_ready", false)), "power module clamped")

	await _walk_act1(Vector3(0, 0, -8.0), 3.0, "power exit")
	await _walk_act1(Vector3(-1.0, 0, -12.8), 3.0, "vent threshold")
	check(player.global_position.z < -11.5, "walked into the ventilation hall")
	await _walk_act1(Vector3(7.0, 0, -14.8), 4.0, "hall north east")
	await _walk_act1(Vector3(7.0, 0, -17.5), 2.0, "hall east")
	await _walk_act1(Vector3(7.7, 0, -22.3), 2.5, "rotor lock")
	await _press_act1("rotor_lock", 0.12)
	check(bool(flags.get("rotor_lock_released", false)), "rotor lock removed")
	await _walk_act1(Vector3(8.1, 0, -28.15), 3.8, "coupling")
	await _press_act1("coupling", 0.12)
	check(bool(flags.get("coupling_engaged", false)), "drive coupling engaged")
	await _walk_act1(Vector3(7.0, 0, -14.8), 4.5, "hall return north")
	await _walk_act1(Vector3(-7.8, 0, -14.8), 7.0, "control gallery north")
	await _walk_act1(Vector3(-7.8, 0, -18.0), 1.8, "control gallery")
	await _walk_act1(Vector3(-7.8, 0, -23.0), 2.4, "fan start")
	await _press_act1("start_fan", 0.12)
	check(bool(flags.get("fan_started", false)), "main fan started")
	await _walk_act1(Vector3(-7.8, 0, -14.8), 3.0, "west gallery north")
	await _walk_act1(Vector3(7.0, 0, -14.8), 7.0, "damper side north")
	await _walk_act1(Vector3(7.0, 0, -18.0), 1.8, "damper side")
	await _walk_act1(Vector3(8.0, 0, -29.6), 5.0, "damper control")
	await _press_act1("damper", 0.12)
	check(bool(flags.get("damper_open", false)), "main duct damper opened")
	await _walk_act1(Vector3(8.0, 0, -34.0), 3.0, "safe south")
	var hud_ready: String = _act1_hud_text()
	log_line("VENT_HUD_READY " + hud_ready)
	check(hud_ready.find("风压") >= 0, "HUD shows the live pressure")
	check(hud_ready.find("58") >= 0, "HUD names the 58% pressure target")
	var waited := 0
	while waited < 12 and not bool(flags.get("vent_complete", false)):
		await _wait(1.0)
		waited += 1
		log_line("VENT t=%d speed=%.2f damper=%.2f pressure=%.2f complete=%s" % [waited, float(stage.get("builder").get("vent").get("speed")), float(stage.get("builder").get("vent").get("damper")), float(stage.get("builder").get("vent").get("pressure")), str(flags.get("vent_complete"))])
	check(bool(flags.get("vent_complete", false)), "6-second live pressure test completed")
	# The HUD repaints on its own 0.08 s clock (`_hud_clock`), so reading it in the
	# same frame the flag flips catches the previous frame's text. Wait one HUD
	# period so the assertion observes what a player actually sees.
	await _wait(0.3)
	var hud_done: String = _act1_hud_text()
	log_line("VENT_HUD_DONE " + hud_done)
	check(hud_done.find("通过") >= 0, "HUD reports the passed pressure test")

	await _walk_act1(Vector3(7.0, 0, -35.4), 2.5, "hall south")
	await _walk_act1(Vector3(0.0, 0, -35.6), 4.0, "hall center")
	await _walk_act1(Vector3(0.0, 0, -37.6), 2.4, "station threshold")
	check(player.global_position.z < -37.0, "station threshold is walkable")
	await _walk_act1(Vector3(-5.6, 0, -40.5), 3.5, "station west")
	await _walk_act1(Vector3(-5.6, 0, -44.3), 2.5, "chock approach")
	await _walk_act1(Vector3(-5.62, 0, -45.5), 1.4, "chock")
	await _press_act1("chock", 0.12)
	check(bool(flags.get("chock_removed", false)), "wheel chock removed")
	await _walk_act1(Vector3(-4.5, 0, -40.6), 2.4, "station return")
	await _walk_act1(Vector3(0.0, 0, -38.2), 2.0, "station center")
	await _walk_act1(Vector3(7.2, 0, -38.2), 3.5, "ramp north")
	await _walk_act1(Vector3(7.2, 1.55, -43.0), 3.5, "platform ramp")
	check(player.global_position.y > 1.2, "walked up the boarding ramp")
	await _walk_act1(Vector3(7.35, 1.55, -48.2), 3.0, "platform brake side")
	await _walk_act1(Vector3(6.55, 1.55, -48.6), 1.2, "brake")
	await _press_act1("parking_brake", 0.12)
	check(bool(flags.get("brake_released", false)), "parking brake released")
	await _walk_act1(Vector3(7.35, 1.55, -43.9), 3.0, "platform cargo side")
	await _walk_act1(Vector3(6.55, 1.55, -43.0), 1.2, "cargo strap")
	await _press_act1("cargo", 0.12)
	check(bool(flags.get("cargo_secured", false)), "cargo restraint locked")

	await _walk_act1(Vector3(5.6, 1.55, -47.0), 2.0, "platform edge")
	await _walk_act1(Vector3(3.6, 1.55, -47.0), 2.0, "cart side")
	await _walk_act1(Vector3(0.0, 1.55, -48.0), 2.5, "cart deck")
	check(bool(stage.call("all_active_aboard")), "player physically inside the mine cart")
	check(bool(stage.call("all_active_ready")), "cooperation credit satisfied by real interactions")

	await _walk_act1(Vector3(-3.0, 1.55, -50.0), 2.6, "launch console")
	await _press_act1("launch_cart", 0.12)
	check(bool(flags.get("departure_started", false)), "departure interlock accepted")
	var builder1: Variant = stage.get("builder")
	var cart1: Node3D = builder1.get("mine_cart") as Node3D if builder1 != null else null
	var z_before: float = cart1.global_position.z if cart1 != null else 0.0
	await _wait(2.0)
	if is_instance_valid(stage) and is_instance_valid(cart1):
		var z_after: float = cart1.global_position.z
		check(z_after < z_before - 2.0, "cart travelled down the rails (%.2f -> %.2f)" % [z_before, z_after])
	stage_records.append({"stage": "act01", "completed": true})
	return true


# ---------------------------------------------------------------------------
# Act23 (真实输入：登车 → 发车 → 断轨停车 → 下车修轨 → 回车 → 到站)
# ---------------------------------------------------------------------------
var slice: Node = null


func _yaw_to(target: Vector3) -> float:
	var d: Vector3 = target - player.global_position
	return atan2(-d.x, -d.z)


func _face_act23(target: Vector3) -> void:
	var yaw := _yaw_to(target)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_yaw", yaw)


func _walk_act23(target: Vector3, seconds: float, label := "", arrive := 0.65) -> void:
	var start: Vector3 = player.global_position
	_face_act23(target)
	Input.action_press("sprint")
	Input.action_press("move_up")
	var frames := int(seconds * 60.0)
	for i in range(frames):
		await physics_frame
		if not is_instance_valid(player):
			break
		_face_act23(target)
		if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < arrive:
			break
	Input.action_release("move_up")
	Input.action_release("sprint")
	await physics_frame
	if is_instance_valid(player):
		var moved: float = player.global_position.distance_to(start)
		log_line("WALK23 %s target=%s pos=%s moved=%.2f" % [label, str(target.snapped(Vector3(0.01, 0.01, 0.01))), str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))), moved])


func _press_act23(action: String, hold := 0.12) -> void:
	Input.action_press(action)
	await _wait(hold)
	Input.action_release(action)
	await _wait(0.35)


func _find_act23_slice() -> Node:
	var node: Node = current_scene
	if node == null:
		return null
	if node.get("cart") != null and node.get("player") != null:
		return node
	for path in ["MovingCartSlice", "Act23Entry/MovingCartSlice"]:
		var found: Node = node.get_node_or_null(path)
		if found != null and found.get("cart") != null:
			return found
	return null


func _drive_act23() -> bool:
	slice = _find_act23_slice()
	if slice == null:
		check(false, "Act23 slice node missing")
		return false
	var waited := 0.0
	while waited < 15.0 and slice.get("loaded") != true:
		await _wait(0.2)
		waited += 0.2
	var cart: Node3D = slice.get("cart") as Node3D
	player = slice.get("player") as Node
	var flow: Node = slice.get("flow") as Node
	var yard: Node3D = slice.get("yard") as Node3D
	check(player != null and cart != null and flow != null and yard != null, "Act23 world nodes present (player/cart/flow/yard)")
	if player == null or cart == null:
		return false
	log_line("ACT23_START pos=%s cart=%s phase=%s distance=%.2f" % [str(player.global_position), str(cart.global_position), str(flow.get("phase")), float(cart.get("distance"))])

	# 1) 登车：从登车平台沿黄色踏步走上甲板
	await _walk_act23(Vector3(1.0, 0.4, 0.65), 5.0, "boarding steps")
	var board_tries := 0
	while board_tries < 4 and not bool(cart.call("contains_point", player.global_position)):
		board_tries += 1
		await _walk_act23(Vector3(1.05, 1.91, 0.9 + 0.35 * float(board_tries)), 4.0, "deck step %d" % board_tries, 0.4)
	log_line("ACT23_DECK pos=%s on_deck=%s" % [str(player.global_position), str(cart.call("contains_point", player.global_position))])
	if not bool(cart.call("contains_point", player.global_position)):
		check(false, "player physically standing on the cart deck")
		return false
	check(true, "player boarded the cart via the yellow steps")

	# 2) 到前端控制器发车
	await _walk_act23(Vector3(2.48, 1.91, 1.08), 3.0, "brake controller", 0.45)
	await _press_act23("repair", 0.14)
	await _wait(0.8)
	check(bool(cart.get("running")), "cart started from the real controller (E)")
	if not bool(cart.get("running")):
		return false
	log_line("ACT23_RUN distance=%.2f speed=%.2f" % [float(cart.get("distance")), float(cart.get("speed"))])

	# 3) 等断轨停车
	var ride := 0.0
	while ride < 120.0 and not bool(cart.get("stopped_for_fault")):
		await _wait(0.5)
		ride += 0.5
	log_line("ACT23_FAULT t=%.1f distance=%.2f speed=%.2f stopped=%s phase=%s pos=%s" % [ride, float(cart.get("distance")), float(cart.get("speed")), str(cart.get("stopped_for_fault")), str(flow.get("phase")), str(player.global_position)])
	check(bool(cart.get("stopped_for_fault")), "cart stopped at the severed rail (real governor)")
	check(absf(float(cart.get("distance")) - 88.0) < 3.0, "cart stop distance is the authored FAULT_STOP (%.2f)" % float(cart.get("distance")))
	stage_records.append({"stage": "act23_ride", "distance": float(cart.get("distance")), "phase": str(flow.get("phase"))})

	# 4) 下车、修断轨（真实 E / W / 空格 输入；位置全部运行时查询）
	var rig: Node = yard.get("rig") as Node
	var winch: Node3D = rig.get("winch") as Node3D
	var anchor: Node3D = _find_anchor("eye_far")
	check(rig != null and winch != null and anchor != null, "repair rig + front lifting eye exist (eye_far)")
	if rig == null or winch == null or anchor == null:
		return false
	var anchor_pos: Vector3 = anchor.call("attach_point") as Vector3
	var console_pos: Vector3 = winch.global_position
	var lock_pos: Vector3 = yard.call("lock_station_position") as Vector3
	log_line("ACT23_POSITIONS anchor=%s console=%s lock=%s yard=%s" % [str(anchor_pos), str(console_pos), str(lock_pos), str(yard.global_position)])

	# 从甲板下车：甲板近侧只有 local x≈0.52..1.48 的登车口是开的（其余是挡杆），
	# 所以玩家必须走到那个口再下到工地地面——真实移动，不传送。
	var gate_world: Vector3 = cart.to_global(Vector3(1.0, 0.2, -0.4))
	await _walk_act23(cart.to_global(Vector3(1.0, 1.91, 1.2)), 6.0, "walk aft along the deck", 0.5)
	await _walk_act23(gate_world, 6.0, "through the boarding gate", 0.4)
	await _wait(0.6)
	log_line("ACT23_GATE pos=%s local=%s y=%.2f" % [str(player.global_position), str(cart.to_local(player.global_position)), player.global_position.y])
	# 落到检修场地地面（y≈0）：先离开矿车侧面，再沿场地南侧走到断轨前端
	await _walk_act23(yard.to_global(Vector3(-1.0, 0.0, -4.2)), 7.0, "step down to the south apron", 0.8)
	await _wait(0.3)
	log_line("ACT23_GROUND pos=%s y=%.2f floor=%s" % [str(player.global_position), player.global_position.y, str(player.call("is_on_floor"))])
	check(player.global_position.y < 1.2, "player left the deck and stands on the yard floor (y=%.2f)" % player.global_position.y)

	# 挂前端吊耳（沿轨道南侧绕过车头，再从导向轮范围外靠近吊耳：
	# 导向轮工作站的 E 优先级高于吊耳，必须站在它的 1.85 m 范围以外）
	await _walk_act23(Vector3(89.0, 0.0, 0.0), 5.0, "south clear lane", 0.7)
	await _walk_act23(Vector3(94.3, 0.0, 0.2), 6.0, "east around the cart nose", 0.7)
	await _walk_act23(Vector3(94.3, 0.0, 4.7), 5.0, "east of the swing nose", 0.7)
	await _walk_act23(Vector3(96.6, 0.0, 4.5), 4.0, "clear of the guide wheel", 0.7)
	await _walk_act23(anchor_pos, 3.0, "front lifting eye", 1.35)
	await _press_act23("repair", 0.14)
	await _wait(0.5)
	var tension: Dictionary = rig.call("tension_state") as Dictionary
	log_line("ACT23_HOOK attached=%s near=%s tension=%s pos=%s" % [str(tension.get("attached")), str(flow.get("near")), str(tension), str(player.global_position)])
	check(bool(tension.get("attached", false)), "winch cable hooked onto the front lifting eye (E)")
	if not bool(tension.get("attached", false)):
		return false

	# 接管绞盘：从矿车东侧绕到北面，再沿北侧到绞盘
	await _walk_act23(Vector3(94.2, 0.0, 9.2), 6.0, "north of the line (east side)", 0.8)
	await _walk_act23(Vector3(88.6, 0.0, 9.2), 5.0, "north apron", 0.8)
	await _walk_act23(console_pos, 4.0, "winch console", 1.2)
	await _press_act23("repair", 0.14)
	await _wait(0.4)
	log_line("ACT23_CONSOLE at_console=%s owner=%s near=%s pos=%s" % [str(flow.get("at_console")), str(flow.get("console_actor")), str(flow.get("near")), str(player.global_position)])
	check(bool(flow.get("at_console")), "player took over the winch drum (E)")

	# 收缆：真实按住 W，直到导向槽可捕获
	Input.action_press("winch_haul")
	var haul_t := 0.0
	var last_log := 0.0
	var alignment: Dictionary = {}
	while haul_t < 45.0:
		await _wait(0.25)
		haul_t += 0.25
		alignment = rig.call("alignment_state") as Dictionary
		if haul_t - last_log >= 2.0:
			last_log = haul_t
			log_line("ACT23_HAUL t=%.1f angle=%.2f capture=%s jammed=%s stalled=%s" % [haul_t, float(alignment.get("angle_deg", 0.0)), str(alignment.get("captureable")), str(alignment.get("jammed")), str(alignment.get("stalled"))])
		if bool(alignment.get("captureable", false)):
			break
	Input.action_release("winch_haul")
	await _wait(0.3)
	await _press_act23("winch_brake", 0.12)
	alignment = rig.call("alignment_state") as Dictionary
	log_line("ACT23_ALIGN angle=%.2f capture=%s in_band=%s" % [float(alignment.get("angle_deg", 0.0)), str(alignment.get("captureable")), str(alignment.get("in_band"))])
	check(bool(alignment.get("captureable", false)), "rail pulled into the guide slot capture band (angle=%.2f)" % float(alignment.get("angle_deg", 0.0)))
	if not bool(alignment.get("captureable", false)):
		stage_records.append({"stage": "act23_repair_blocked", "alignment": alignment, "tension": rig.call("tension_state"), "hauls": haul_t})
		return false

	# 离开绞盘 → 锁定座插销
	await _press_act23("repair", 0.14)
	await _wait(0.4)
	log_line("ACT23_LEAVE at_console=%s" % str(flow.get("at_console")))
	await _walk_act23(lock_pos, 8.0, "lock station", 1.2)
	await _press_act23("repair", 0.14)
	await _wait(0.5)
	var lock_state: Dictionary = rig.call("lock_state") as Dictionary
	log_line("ACT23_PIN %s pending=%s" % [str(lock_state), str(rig.get("_pending_lock"))])
	var guide_t := 0.0
	while guide_t < 12.0 and not bool(yard.call("completion")):
		await _wait(0.4)
		guide_t += 0.4
	log_line("ACT23_REPAIR completed=%s t=%.1f route_clear=%s phase=%s" % [str(yard.call("completion")), guide_t, str(cart.get("route_clear")), str(flow.get("phase"))])
	check(bool(yard.call("completion")), "broken rail repaired and mechanically locked (E pin)")
	check(bool(cart.get("route_clear")), "cart route cleared by the repair (production flag)")
	if not bool(yard.call("completion")):
		stage_records.append({"stage": "act23_lock_blocked", "lock": lock_state, "alignment": rig.call("alignment_state")})
		return false
	stage_records.append({"stage": "act23_repair", "alignment": rig.call("alignment_state"), "completion": true})

	# 5) 回车上：使用游戏内安全绳救援动作（R），不是测试传送
	await _press_act23("cart_recover", 0.14)
	await _wait(1.0)
	log_line("ACT23_REBOARD pos=%s on_deck=%s recoveries=%d" % [str(player.global_position), str(cart.call("contains_point", player.global_position)), int(player.get("recovery_count"))])
	check(bool(cart.call("contains_point", player.global_position)), "game's safety-rope rescue (R) put the rider back on the deck")
	if not bool(cart.call("contains_point", player.global_position)):
		return false

	# 6) 重新发车 → 真实到站 → 交接
	var brake_anchor: Vector3 = cart.to_global(Vector3(2.48, 1.91, 1.08))
	await _walk_act23(brake_anchor, 4.0, "controller aft", 0.5)
	await _press_act23("repair", 0.14)
	await _wait(0.8)
	log_line("ACT23_RIDE2 running=%s distance=%.2f" % [str(cart.get("running")), float(cart.get("distance"))])
	check(bool(cart.get("running")), "cart restarted after the repair (E)")
	if not bool(cart.get("running")):
		return false
	var ride2 := 0.0
	while ride2 < 60.0 and not bool(cart.get("arrived")):
		await _wait(0.3)
		ride2 += 0.3
	log_line("ACT23_ARRIVED t=%.1f distance=%.2f arrived=%s phase=%s" % [ride2, float(cart.get("distance")), str(cart.get("arrived")), str(flow.get("phase"))])
	check(bool(cart.get("arrived")), "cart physically reached the crystal-mine dock (distance=%.2f)" % float(cart.get("distance")))
	check(str(flow.get("phase")) == "done", "level flow derived phase=done from the real arrival")
	if not bool(cart.get("arrived")):
		return false
	# 交接由生产代码在 4.5 s 后自动发起
	var handoff := 0.0
	while handoff < 20.0 and _scene_name() != "Act4":
		await _wait(0.3)
		handoff += 0.3
	log_line("ACT23_HANDOFF scene=%s chapter=%s t=%.1f" % [_scene_name(), str(hub.get("current_chapter")), handoff])
	var final_distance: float = float(cart.get("distance")) if is_instance_valid(cart) else -1.0
	stage_records.append({"stage": "act23", "completed": true, "distance": final_distance, "chapter": str(hub.get("current_chapter")), "scene": _scene_name()})
	return true


func _find_anchor(anchor_id: String) -> Node3D:
	for node in get_nodes_in_group("winch_anchor"):
		if str(node.get("anchor_id")) == anchor_id:
			return node as Node3D
	return null


# ---------------------------------------------------------------------------
# Act04 (真实输入：锤击 → 取晶体 → 放中继 → 锤击 → … → 出口)
# ---------------------------------------------------------------------------
var game4: Node = null


func _face_act4(target: Vector3, pitch: float = -0.12) -> void:
	if not is_instance_valid(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("_yaw", yaw)
	player.set("_aim_yaw", yaw)
	player.set("_aim_active", false)
	player.set("_pitch", pitch)
	player.set("_aim_pitch", pitch)
	player.call("_apply_view")


func _walk_act4(target: Vector3, seconds: float, label := "", tolerance := 0.9) -> bool:
	var elapsed := 0.0
	var stuck := 0.0
	var last: Vector3 = player.global_position
	Input.action_press("move_forward")
	while elapsed < seconds:
		await physics_frame
		elapsed += 1.0 / 60.0
		if not is_instance_valid(player) or current_scene != game4:
			break
		var current: Vector3 = player.global_position
		_face_act4(Vector3(target.x, current.y, target.z))
		if Vector2(current.x - target.x, current.z - target.z).length() <= tolerance:
			break
		if current.distance_to(last) < 0.012:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
			last = current
		if stuck > 1.2:
			# 卡住时用真实的跳跃 + 侧移脱困（玩家会做的事），不是传送。
			Input.action_press("jump")
			for i in range(6):
				await physics_frame
			Input.action_release("jump")
			Input.action_press("move_right" if int(elapsed * 7.0) % 2 == 0 else "move_left")
			for i in range(12):
				await physics_frame
			Input.action_release("move_right")
			Input.action_release("move_left")
			stuck = 0.0
	Input.action_release("move_forward")
	await physics_frame
	if not is_instance_valid(player):
		log_line("WALK04 %s ended early: Act04 scene already left (handoff fired)" % label)
		return true
	var dist: float = Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
	log_line("WALK04 %s target=%s pos=%s dist=%.2f t=%.1f" % [label, str(target.snapped(Vector3(0.01, 0.01, 0.01))), str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))), dist, elapsed])
	return dist <= tolerance * 1.8


func _interact_act4(target: Vector3, pitch := -0.12) -> void:
	_face_act4(target, pitch)
	await _wait(0.2)
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	await _wait(0.3)


func _strike_hammer() -> bool:
	var hammer: Node = game4.get("hammer")
	if hammer == null:
		return false
	var hammer_pos: Vector3 = (hammer as Node3D).global_position
	await _walk_act4(Vector3(2.10, 0.0, -1.30), 9.0, "hammer console", 1.2)
	var held := false
	for attempt in range(4):
		_face_act4(hammer_pos + Vector3(0, 0.8, 0), 0.12)
		await _wait(0.35)
		Input.action_press("interact")
		await _wait(0.14)
		Input.action_release("interact")
		await _wait(0.4)
		held = str(hammer.get("mode")) == "held"
		if held:
			break
		# 退半步换角度再试（玩家会做的事）
		await _walk_act4(Vector3(2.9, 0.0, -0.6), 2.0, "step back from the rig", 0.6)
		await _walk_act4(Vector3(2.10, 0.0, -1.30), 3.0, "re-approach the rig", 0.8)
	log_line("ACT04_HAMMER held=%s target=%s mode=%s pos=%s" % [str(held), str(player.get("current_target")), str(hammer.get("mode")), str(player.global_position)])
	if not held:
		return false
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	await _interact_act4(hammer_pos + Vector3(0, 1.0, 0), 0.05)
	var strikes_before: int = int(hammer.get("strike_count"))
	await _wait(2.2)
	var strikes: int = int(hammer.get("strike_count"))
	log_line("ACT04_HAMMER_STRIKE count=%d (was %d) strength=%.2f" % [strikes, strikes_before, float(hammer.get("last_strength"))])
	return strikes > strikes_before


func _drive_act04() -> bool:
	game4 = current_scene
	player = game4.get("player") as Node
	if player == null:
		check(false, "Act04 player missing")
		return false
	log_line("ACT04_START pos=%s" % str(player.global_position))
	check(await _strike_hammer(), "first hammer strike through real E/W input")
	var seen: Dictionary = game4.get("seen_memories") as Dictionary
	var waited := 0.0
	while waited < 25.0 and not bool(seen.get(1, false)):
		await _wait(0.5)
		waited += 0.5
	log_line("ACT04_MEMORY1 seen=%s stage=%s" % [str(seen), str(game4.get("stage"))])
	check(bool(seen.get(1, false)), "memory one reached by the resonance wave")

	# 走向西侧壁龛里的青色晶体（真实行走；这是本轮最需要验证的一段）
	var crystal_a: Node3D = game4.get("crystal_a") as Node3D
	log_line("ACT04_CRYSTAL_A pos=%s" % str(crystal_a.global_position))
	await _walk_act4(Vector3(-6.0, 0.0, 2.0), 8.0, "west aisle", 1.0)
	await _walk_act4(Vector3(-6.0, 0.0, 9.5), 6.0, "north of the stope", 1.0)
	await _walk_act4(Vector3(-12.0, 0.0, 9.5), 7.0, "north rim west", 1.0)
	await _walk_act4(Vector3(-17.0, 0.0, 9.5), 6.0, "north west rim", 1.0)
	await _walk_act4(Vector3(-17.5, 0.0, 5.0), 6.0, "alcove west aisle", 1.0)
	await _walk_act4(Vector3(-17.0, 0.0, 3.0), 5.0, "alcove shelf", 1.0)
	log_line("ACT04_ALCOVE pos=%s crystal=%s dist=%.2f" % [str(player.global_position), str(crystal_a.global_position), player.global_position.distance_to(crystal_a.global_position)])
	# 壁龛里的晶体离地面 2.6 m；真实玩家能在这个距离按 F 取到（拾取半径 3.2 m）
	var picked := false
	for attempt in range(4):
		_face_act4(crystal_a.global_position + Vector3(0, 0.2, 0), 0.35)
		await _wait(0.3)
		Input.action_press("pickup")
		await _wait(0.14)
		Input.action_release("pickup")
		await _wait(0.5)
		if player.get("carrying") != null:
			picked = true
			break
		await _walk_act4(crystal_a.global_position + Vector3(0, 0, 0.9), 2.0, "closer to the crystal", 0.5)
	log_line("ACT04_PICK_A carrying=%s pos=%s" % [str(player.get("carrying")), str(player.global_position)])
	check(picked, "cyan crystal picked up from the alcove shelf with real F (no teleport)")
	if not picked:
		stage_records.append({"stage": "act04_blocked_pickup", "pos": str(player.global_position), "crystal": str(crystal_a.global_position)})
		return false

	# 带着晶体走到西中继 B1（绕开塌陷采场；真实搬运，速度变慢）
	await _walk_act4(Vector3(-16.5, 0.0, -2.0), 10.0, "carry south along the west wall", 1.2)
	await _walk_act4(Vector3(-16.8, 0.0, -9.0), 9.0, "carry south", 1.2)
	await _walk_act4(Vector3(-13.0, 0.0, -11.5), 8.0, "toward west relay", 1.2)
	var b1: Node3D = (game4.get("cradles") as Dictionary)["b1"] as Node3D
	await _walk_act4(b1.global_position + Vector3(0, 0, 1.25), 6.0, "west relay B1", 0.7)
	check(await _place_in_cradle("b1"), "cyan crystal seated and aligned in the west relay B1 (real F + Q)")

	# 第二次锤击 → 记忆二
	check(await _strike_hammer(), "second hammer strike")
	check(await _wait_memory(2), "memory two reached after the west path was restored")

	# 紫晶体 B：货架上取走 → 经西侧斜坡搬上观察平台 B3
	var crystal_b: Node3D = game4.get("crystal_b") as Node3D
	await _walk_act4(crystal_b.global_position + Vector3(0, 0, 1.1), 8.0, "violet crystal", 0.8)
	var picked_b := false
	for attempt in range(3):
		_face_act4(crystal_b.global_position, 0.2)
		await _wait(0.25)
		Input.action_press("pickup")
		await _wait(0.14)
		Input.action_release("pickup")
		await _wait(0.5)
		if player.get("carrying") != null:
			picked_b = true
			break
	check(picked_b, "violet crystal picked up with real F")
	if not picked_b:
		return false
	await _walk_act4(Vector3(-18.5, 0.0, -13.2), 9.0, "west ramp foot", 1.2)
	await _walk_act4(Vector3(-17.2, 3.4, -17.6), 9.0, "west ramp up", 1.2)
	await _walk_act4(Vector3(-14.0, 3.4, -19.2), 7.0, "observation ledge", 1.2)
	var b3: Node3D = (game4.get("cradles") as Dictionary)["b3"] as Node3D
	await _walk_act4(b3.global_position + Vector3(0, 0, 1.15), 6.0, "ledge relay B3", 0.8)
	check(await _place_in_cradle("b3"), "violet crystal seated and aligned on the observation ledge B3")

	# 第三次锤击 → 记忆三 → 出口开启
	check(await _strike_hammer(), "third hammer strike")
	check(await _wait_memory(3), "memory three reached through the restored final chain")
	var gate: Node = game4.get("gate")
	var gate_open := 0.0
	while gate_open < 8.0 and not bool(gate.get("is_open")):
		await _wait(0.4)
		gate_open += 0.4
	log_line("ACT04_GATE open=%s t=%.1f" % [str(gate.get("is_open")), gate_open])
	check(bool(gate.get("is_open")), "exit gate physically opened")
	# 走进出口触发区（真实移动，不传送）。出口触发会让 Act04 自己切到第五幕，
	# 所以这里容忍场景在行走途中被释放：那本身就是“真实完成”的结果。
	await _walk_act4(Vector3(0.0, 0.0, -21.0), 10.0, "final chamber aisle", 1.2)
	await _walk_act4(Vector3(6.2, 0.0, -25.0), 10.0, "exit corridor", 1.3)
	var complete_t := 0.0
	while complete_t < 10.0 and is_instance_valid(game4) and current_scene == game4 and not bool(game4.get("completed")):
		await _wait(0.3)
		complete_t += 0.3
	var completed := false
	var seconds := -1.0
	var scene_name := str(current_scene.name) if current_scene != null else "null"
	if is_instance_valid(game4):
		completed = bool(game4.get("completed"))
		seconds = float(game4.get("completion_seconds"))
	if not completed and scene_name == "Main":
		completed = true
	log_line("ACT04_COMPLETE completed=%s seconds=%.1f scene=%s t=%.1f" % [str(completed), seconds, scene_name, complete_t])
	check(completed, "Act04 completed by walking into the exit trigger (scene now %s)" % scene_name)
	stage_records.append({"stage": "act04", "completed": completed, "seconds": seconds, "scene_after": scene_name})
	return completed


func _wait_memory(index: int) -> bool:
	var seen: Dictionary = game4.get("seen_memories") as Dictionary
	var waited := 0.0
	while waited < 30.0 and not bool(seen.get(index, false)):
		await _wait(0.5)
		waited += 0.5
	log_line("ACT04_MEMORY%d seen=%s stage=%s t=%.1f" % [index, str(seen.get(index, false)), str(game4.get("stage")), waited])
	return bool(seen.get(index, false))


func _place_in_cradle(key: String) -> bool:
	var cradle: Node3D = (game4.get("cradles") as Dictionary)[key] as Node3D
	if player.get("carrying") == null:
		return false
	var target_yaw: float = float(cradle.get("required_yaw_deg"))
	var carrying: Node = player.get("carrying") as Node
	var current: float = float(carrying.get("held_yaw_deg"))
	var delta: float = fposmod(target_yaw - current, 360.0)
	var steps: int = int(round(delta / 45.0))
	for i in range(steps):
		Input.action_press("rotate_crystal")
		await _wait(0.10)
		Input.action_release("rotate_crystal")
		await _wait(0.08)
	_face_act4(cradle.global_position + Vector3(0, 0.15, 0), 0.25)
	await _wait(0.3)
	Input.action_press("pickup")
	await _wait(0.16)
	Input.action_release("pickup")
	await _wait(0.8)
	var ok: bool = cradle.get("occupied") != null and bool(cradle.get("aligned"))
	log_line("ACT04_PLACE %s occupied=%s aligned=%s yaw=%.1f target=%.1f steps=%d" % [key, str(cradle.get("occupied")), str(cradle.get("aligned")), current, target_yaw, steps])
	return ok


# ---------------------------------------------------------------------------
# Act05 (真实输入：走廊 → 配重 → 共振抓握 → 两条支腿 → 爪锁 → 阻尼 → 隔离
#        → 推车 → 取数据 → 撤离)
# ---------------------------------------------------------------------------
var game5: Node = null


func _face_act5(target: Vector3) -> void:
	if not is_instance_valid(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	var flat: float = Vector2(d.x, d.z).length()
	var pitch: float = -atan2(d.y - 1.45, maxf(flat, 0.05))
	player.call("set_look", yaw, clampf(pitch, -1.1, 1.1))


func _walk_act5(target: Vector3, seconds: float, label := "", tolerance := 1.1) -> bool:
	var elapsed := 0.0
	var stuck := 0.0
	var last: Vector3 = player.global_position
	Input.action_press("move_forward")
	while elapsed < seconds:
		await physics_frame
		elapsed += 1.0 / 60.0
		if not is_instance_valid(player) or current_scene != game5:
			break
		var current: Vector3 = player.global_position
		_face_act5(Vector3(target.x, current.y, target.z))
		if Vector2(current.x - target.x, current.z - target.z).length() <= tolerance:
			break
		if current.distance_to(last) < 0.012:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
			last = current
		if stuck > 1.0:
			Input.action_press("jump")
			for i in range(6):
				await physics_frame
			Input.action_release("jump")
			Input.action_press("move_right" if int(elapsed * 7.0) % 2 == 0 else "move_left")
			for i in range(10):
				await physics_frame
			Input.action_release("move_right")
			Input.action_release("move_left")
			stuck = 0.0
	Input.action_release("move_forward")
	await physics_frame
	if not is_instance_valid(player) or current_scene != game5:
		log_line("WALK05 %s ended early: Act05 scene left" % label)
		return true
	var dist: float = Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
	log_line("WALK05 %s target=%s pos=%s dist=%.2f t=%.1f" % [label, str(target.snapped(Vector3(0.01, 0.01, 0.01))), str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))), dist, elapsed])
	return dist <= tolerance * 2.0


func _press5(action := "interact", hold := 0.12) -> void:
	Input.action_press(action)
	await _wait(hold)
	Input.action_release(action)
	await _wait(0.25)


func _hold5(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	await _wait(0.2)


func _drive_act05() -> bool:
	game5 = current_scene
	player = game5.get("player") as Node
	var level: Node = game5.get("level") as Node
	var story: Node = game5.get("story") as Node
	var session: Node = game5.get("session") as Node
	var surge: Node = game5.get("surge") as Node
	var core: Node = level.get("core")
	if player == null or level == null or story == null:
		check(false, "Act05 world nodes present (player/level/story)")
		return false
	log_line("ACT05_START pos=%s stage=%s handoff_consumed=%s" % [str(player.global_position), str(story.get("stage")), str(game5.get("handoff_consumed"))])
	var stage_before := int(story.get("stage"))

	# 1) 从出生点走到大厅，触发“发现失稳”
	if not await _walk_act5(Vector3(0.0, 4.06, 26.0), 14.0, "spawn to shutter", 1.2):
		check(false, "walk from the Act05 spawn to the hall")
		stage_records.append({"stage": "act05_blocked_spawn", "pos": str(player.global_position)})
		return false
	# 1b) 被卡住的卷帘门：真实 E 抓握 + W 推开（与 PlaythroughBot 相同）
	await _walk_act5(Vector3(0.0, 4.06, 24.6), 4.0, "shutter", 0.8)
	_face_act5(Vector3(0.0, 5.0, 24.2))
	await _press5()
	var grabbed_door := bool(player.get("operating"))
	if not grabbed_door:
		await _walk_act5(Vector3(0.0, 4.06, 25.0), 3.0, "shutter retry", 0.7)
		_face_act5(Vector3(0.0, 5.0, 24.2))
		await _press5()
		grabbed_door = bool(player.get("operating"))
	log_line("ACT05_SHUTTER grabbed=%s pos=%s" % [str(grabbed_door), str(player.global_position)])
	check(grabbed_door, "jammed shutter grabbed with real E")
	if grabbed_door:
		await _hold5("move_forward", 3.8)
		await _press5()
	await _walk_act5(Vector3(0.0, 4.06, 22.5), 6.0, "through the shutter", 1.0)
	await _walk_act5(Vector3(0.0, 4.06, 12.2), 10.0, "hall balcony", 1.2)
	var hall_t := 0.0
	while hall_t < 6.0 and int(story.get("stage")) < 2:
		await _wait(0.4)
		hall_t += 0.4
	log_line("ACT05_HALL stage=%s (was %d)" % [str(story.get("stage")), stage_before])
	check(int(story.get("stage")) >= 2, "hall trigger advanced the story to the instability stage")

	# 2) 下到地面层（左侧坡道），再去右站配重
	await _walk_act5(Vector3(-5.0, 4.06, 10.4), 8.0, "left ramp top", 1.2)
	await _walk_act5(Vector3(-5.0, 1.4, 4.2), 8.0, "left ramp middle", 1.3)
	await _walk_act5(Vector3(-5.0, 0.06, 2.4), 8.0, "left ramp bottom", 1.2)
	await _walk_act5(Vector3(0.0, 0.06, 6.0), 8.0, "ground floor center", 1.2)
	await _walk_act5(Vector3(10.3, 0.06, 6.0), 10.0, "east aisle", 1.2)
	await _walk_act5(Vector3(8.0, 0.06, 2.2), 8.0, "right ramp foot", 1.2)
	await _walk_act5(Vector3(8.0, 1.66, 4.6), 8.0, "right ramp up", 1.3)
	await _walk_act5(Vector3(9.3, 1.66, 7.5), 6.0, "right platform", 1.2)
	await _walk_act5(Vector3(8.5, 1.70, 7.47), 4.0, "counterweight console", 0.9)
	await _press5()
	var operating := false
	for i in range(3):
		if bool(player.get("operating")):
			operating = true
			break
		await _walk_act5(Vector3(8.6, 1.70, 7.40), 3.0, "counterweight handle", 0.6)
		await _press5()
	log_line("ACT05_LEVER operating=%s pos=%s" % [str(operating), str(player.global_position)])
	check(operating, "counterweight console is operable with real E")
	if operating:
		await _hold5("move_back", 9.0)
		await _press5()
	var ledger5: Variant = session.get("ledger")
	check(ledger5 != null and bool(ledger5.call("has_credit", 1, "counterweight_effect")), "counterweight credit earned by the real lever pull")
	stage_records.append({"stage": "act05_counterweight", "pos": str(player.global_position), "stage_value": int(story.get("stage"))})

	# 3) 下到地面 → 维修爬梯 → 栈桥 → 共振抓握（等一次自然涌浪）
	await _walk_act5(Vector3(8.0, 0.06, 4.6), 7.0, "down the station ramp", 1.2)
	await _walk_act5(Vector3(8.0, 0.06, 2.2), 5.0, "station ramp foot", 1.1)
	var catwalk: Node = level.get("catwalk")
	var ladder_node: Node3D = catwalk.get("ladder_station_node") as Node3D if catwalk != null else null
	log_line("ACT05_LADDER_NODE pos=%s operating=%s grabbing=%s impaired=%.1f" % [str(ladder_node.global_position) if ladder_node != null else "null", str(player.get("operating")), str(player.get("grabbing")), float(player.get("impaired_timer"))])
	await _walk_act5(ladder_node.global_position + Vector3(0, 0, 0.9) if ladder_node != null else Vector3(6.45, 0.06, 3.35), 6.0, "catwalk ladder", 0.9)
	for i in range(3):
		if not bool(player.get("operating")):
			break
		await _press5()
	_face_act5(ladder_node.global_position if ladder_node != null else Vector3(6.45, 1.0, 3.35))
	await _press5()
	var climbed := 0.0
	Input.action_press("move_forward")
	while climbed < 6.0 and player.global_position.y < 3.0:
		await _wait(0.2)
		climbed += 0.2
	Input.action_release("move_forward")
	await _wait(0.4)
	log_line("ACT05_LADDER y=%.2f pos=%s t=%.1f grabbing=%s" % [player.global_position.y, str(player.global_position), climbed, str(player.get("grabbing"))])
	check(player.global_position.y > 3.0, "player climbed the maintenance ladder onto the catwalk (y=%.2f)" % player.global_position.y)
	if player.global_position.y <= 3.0:
		stage_records.append({"stage": "act05_blocked_ladder", "pos": str(player.global_position)})
		return false
	var grips: Array = catwalk.get("grab_points") as Array if catwalk != null else []
	var grip_target := Vector3(-10.4, 3.5, -3.95)
	if grips.size() > 0:
		grip_target = (grips[grips.size() - 1] as Node3D).global_position
		log_line("ACT05_GRIPS n=%d last=%s" % [grips.size(), str(grip_target)])
	await _walk_act5(Vector3(grip_target.x, 3.5, grip_target.z + 0.9), 10.0, "brace rail", 1.2)
	var grabbed := false
	for attempt in range(4):
		_face_act5(grip_target)
		await _press5()
		grabbed = bool(player.get("grabbing"))
		if grabbed:
			break
		await _walk_act5(Vector3(grip_target.x, 3.5, grip_target.z + 0.9), 3.0, "brace retry", 0.9)
	log_line("ACT05_BRACE grabbing=%s pos=%s" % [str(grabbed), str(player.global_position)])
	check(grabbed, "player grabbed the west rail with real E")
	if grabbed:
		var surge_t := 0.0
		while surge_t < 45.0 and int(surge.get("surge_count")) < 1:
			await _wait(0.5)
			surge_t += 0.5
		log_line("ACT05_SURGE count=%s state=%s t=%.1f" % [str(surge.get("surge_count")), str(surge.get("state")), surge_t])
		check(int(surge.get("surge_count")) >= 1, "a natural resonance surge fired while braced")
		await _press5()
	check(ledger5.call("has_credit", 1, "surge_response"), "surge response credit earned by a real protective action")

	# 4) 下栈桥 → 两条液压支腿（真实 E + W 泵压）
	await _walk_act5(Vector3(-11.6, 3.5, -2.6), 6.0, "catwalk east end", 1.2)
	await _walk_act5(Vector3(-11.6, 0.06, -2.6), 4.0, "drop off the catwalk", 1.4)
	if player.global_position.y > 2.0:
		await _walk_act5(Vector3(-8.0, 0.06, -2.0), 6.0, "leave the catwalk", 1.4)
	log_line("ACT05_DESCEND pos=%s downed=%s" % [str(player.global_position), str(player.get("downed"))])
	for index: int in [1, 0]:
		var stabs: Array = level.get("stabilizers") as Array
		if stabs == null or stabs.size() <= index:
			check(false, "stabilizer array is missing")
			return false
		var stab: Variant = stabs[index]
		var anchor_xf: Transform3D = stab.get("anchor")
		var stand: Vector3 = anchor_xf.origin + Vector3(0, 0, -0.6)
		await _walk_act5(stand, 12.0, "stabilizer %d" % index, 1.1)
		await _press5()
		var op := false
		for i in range(3):
			if bool(player.get("operating")):
				op = true
				break
			await _walk_act5(stand, 3.0, "stabilizer %d retry" % index, 0.8)
			await _press5()
		if op:
			await _hold5("move_forward", 4.2)
			await _press5()
		log_line("ACT05_STAB %d latched=%s ext=%.2f pos=%s" % [index, str(stab.get("latched")), float(stab.get("extension")), str(player.global_position)])
		check(bool(stab.get("latched")), "stabilizer %d latched by real pumping" % index)

	# 5) 爪锁 → 阻尼 → 隔离 → 推车 → 数据 → 撤离
	await _walk_act5(Vector3(0.0, 0.06, 0.0), 10.0, "center floor", 1.4)
	await _walk_act5(Vector3(0.0, 0.06, 6.0), 8.0, "south of the lock", 1.4)
	await _walk_act5(Vector3(0.0, 0.06, 10.6), 6.0, "lock console stand", 0.9)
	log_line("ACT05_LOCK_APPROACH pos=%s net=%.3f capturable=%s stage=%s" % [str(player.global_position), float(core.get_net()), str(core.is_capturable()), str(story.get("stage"))])
	_face_act5(Vector3(0.0, 1.2, 8.6))
	await _wait(0.3)
	log_line("ACT05_AIM lock target=%s pos=%s" % [str(player.get("current_target")), str(player.global_position)])
	await _wait(0.3)
	await _press5()
	var lock_t := 0.0
	while lock_t < 10.0 and not bool(core.call("is_locked")):
		await _wait(0.4)
		lock_t += 0.4
	log_line("ACT05_LOCK locked=%s t=%.1f" % [str(core.call("is_locked")), lock_t])
	check(bool(core.call("is_locked")), "hydraulic claw locked the core with real E")

	await _walk_act5(Vector3(6.4, 0.06, -2.3), 12.0, "extraction damper", 1.2)
	_face_act5(Vector3(6.4, 1.2, -4.4))
	await _wait(0.3)
	await _press5()
	await _hold5("move_forward", 2.6)
	if bool(player.get("operating")):
		await _press5()
	var damper: Node = level.get("damper")
	log_line("ACT05_DAMPER latched=%s pressure=%.2f" % [str(damper.get("latched_flag")), float(damper.get("pressure"))])
	check(bool(damper.get("latched_flag")), "extraction damper latched by real input")

	await _walk_act5(Vector3(10.3, 0.06, 4.2), 10.0, "east aisle north", 1.3)
	await _walk_act5(Vector3(12.35, 0.06, 4.0), 6.0, "east aisle corner", 1.2)
	await _walk_act5(Vector3(12.35, 0.06, -2.0), 8.0, "east aisle south", 1.3)
	await _walk_act5(Vector3(10.9, 0.06, -5.7), 6.0, "isolation bay", 1.0)
	_face_act5(Vector3(10.6, 1.3, -8.6))
	await _wait(0.3)
	var iso: Node = level.get("isolation")
	for pin_attempt in range(4):
		if bool(iso.get("pin_out")):
			break
		_face_act5(Vector3(10.6, 1.3, -8.6))
		await _wait(0.25)
		log_line("ACT05_PIN_AIM target=%s pos=%s pin=%s" % [str(player.get("current_target")), str(player.global_position), str(iso.get("pin_out"))])
		await _press5()
		await _wait(0.5)
	var pin_t := 0.0
	while pin_t < 6.0 and not bool(iso.get("pin_out")):
		await _wait(0.4)
		pin_t += 0.4
	var pin_credit: bool = bool(ledger5.call("has_credit", 1, "isolation_pin"))
	log_line("ACT05_PIN pin_out=%s credit=%s" % [str(iso.get("pin_out")), str(pin_credit)])
	check(bool(iso.get("pin_out")) or pin_credit, "isolation safety pin pulled by a real protective action (flag or ledger credit)")
	var damp_t := 0.0
	while damp_t < 12.0 and float(damper.call("damper_effect")) < 0.35:
		await _wait(0.4)
		damp_t += 0.4
	log_line("ACT05_DAMPER_EFFECT %.2f t=%.1f" % [float(damper.call("damper_effect")), damp_t])
	var op_iso := false
	for i in range(6):
		await _walk_act5(Vector3(10.7, 0.06, -5.0), 3.0, "carriage console", 0.8)
		await _press5()
		if bool(player.get("operating")):
			op_iso = true
			break
		await _wait(0.4)
	if op_iso:
		await _hold5("move_forward", 5.5)
	var sep_t := 0.0
	while sep_t < 10.0 and not bool(iso.get("separated_flag")):
		await _wait(0.4)
		sep_t += 0.4
	log_line("ACT05_ISOLATION separated=%s progress=%.2f" % [str(iso.get("separated_flag")), float(iso.get("progress"))])
	check(bool(iso.get("separated_flag")), "extraction coupling separated by the real carriage push")

	await _walk_act5(Vector3(6.0, 0.06, -6.0), 8.0, "rear hall", 1.2)
	await _walk_act5(Vector3(-3.0, 0.06, -8.0), 9.0, "data plinth", 1.2)
	_face_act5(Vector3(-3.0, 1.0, -9.1))
	await _wait(0.3)
	log_line("ACT05_AIM data target=%s pos=%s" % [str(player.get("current_target")), str(player.global_position)])
	await _wait(0.3)
	await _press5()
	var data_t := 0.0
	while data_t < 8.0 and not bool(story.get("data_taken")):
		await _wait(0.4)
		data_t += 0.4
	log_line("ACT05_DATA taken=%s t=%.1f" % [str(story.get("data_taken")), data_t])
	check(bool(story.get("data_taken")), "navigation data taken through the plinth with real E")
	check(bool(session.call("can_finish")), "participation gate satisfied by real credits")

	# 6) 撤离：真实走进出口通道
	await _walk_act5(Vector3(-8.0, 0.06, -6.0), 10.0, "exit side", 1.3)
	await _walk_act5(Vector3(-13.4, 0.06, -2.0), 9.0, "blast door", 1.3)
	await _walk_act5(Vector3(-25.5, 0.06, -2.0), 14.0, "exit corridor", 1.5)
	_face_act5(Vector3(-27.5, 1.2, -2.0))
	var settled_t := 0.0
	# `current_scene` is null during the frames between Act05 being freed and the
	# ending scene being instantiated. Every read must be null-guarded: the
	# previous unguarded `current_scene.name` crashed the probe immediately after
	# the real hand-off had already completed, turning a pass into a false failure.
	#
	# The demo build routes the verified Act05 gate to `res://demo/demo_ending.tscn`
	# (node name `ResonanceStarDemoEnding`), not to the full campaign's `Finale`.
	# Both names mean "the run reached its verified conclusion", so accept either
	# instead of asserting one hard-coded scene name.
	while settled_t < 12.0 and not ENDING_SCENES.has(_scene_name()):
		await _wait(0.4)
		settled_t += 0.4
	var stage_after: String = str(story.get("stage")) if is_instance_valid(story) else "left"
	var scene_after: String = _scene_name()
	var reached_ending: bool = ENDING_SCENES.has(scene_after)
	log_line("ACT05_SETTLE stage=%s scene=%s t=%.1f" % [stage_after, scene_after, settled_t])
	check(reached_ending, "real exit crossing settled the run and entered the ending scene")
	stage_records.append({"stage": "act05", "completed": reached_ending, "scene_after": scene_after})
	return reached_ending


func _scene_name() -> String:
	return str(current_scene.name) if current_scene != null else ""


func _finish(passed: bool) -> void:
	var report := {
		"probe": "probe_full_solo_run.gd",
		"mode": mode,
		"passed": passed,
		"checks": checks,
		"failures": failures,
		"scene_ledger": _scene_log,
		"stages": stage_records,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_msec) / 1000.0,
		"log": log_lines,
	}
	var path := "user://full_solo_%s.json" % mode
	if audit_out != "":
		path = audit_out.path_join("full_solo_%s.json" % mode)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
		log_line("REPORT %s" % ProjectSettings.globalize_path(path))
	log_line("RESULT mode=%s checks=%d failures=%d" % [mode, checks, failures.size()])
	if passed:
		print("FULL_SOLO_OK mode=%s" % mode)
	else:
		push_error("FULL_SOLO_FAIL mode=%s %s" % [mode, str(failures)])
	quit(0 if passed else 1)






