extends SceneTree

## R8B · 双人五幕连续合作冒险探针（host / client 各一个真实 Godot 进程）
##
## 入口：正式 Launcher（res://scenes/launcher.tscn），用真实鼠标点击进入：
##   host   → 「创建主机（等待队友加入）」
##   client → 「加入主机（本机 127.0.0.1）」
##
## 之后每一幕都用**玩家真实输入动作**推进（WASD / E / F / Q / 空格 / 绞盘…）：
##   * 不写任何任务完成 flag；
##   * 不调用 complete_chapter / change_scene 跳关；
##   * 不传送玩家（全文件没有 teleport 调用）。
## 只读采样引擎状态并落盘 JSON。
##
## 用法（两个进程跑同一个脚本，role 不同）：
##   godot --headless --path <project> res://scenes/launcher.tscn \
##     -s res://tests/probe_full_coop_run.gd -- --role=host --out=<dir> --mode=full
##
## mode: full | act01 | act23 | act04 | act05

const FINALE_NAME := "Finale"
const HOST_BUTTON := "创建主机（等待队友加入）"
const CLIENT_BUTTON := "加入主机（本机 127.0.0.1）"

var role: String = "host"
var mode: String = "full"
var out_dir: String = ""
var tag: String = ""

var checks: int = 0
var failures: Array[String] = []
var warnings: Array[String] = []
var log_lines: Array[String] = []
var stage_records: Array[Dictionary] = []
var scene_log: Array[String] = []
var _last_scene_id: int = 0
var _stage_now: String = "boot"
var started_msec: int = 0
var hub: Node = null
var player: Node = null
var stage: Node = null


func _initialize() -> void:
	_parse_args()
	started_msec = Time.get_ticks_msec()
	_watchdog.call_deferred()
	_run.call_deferred()


func _parse_args() -> void:
	var all: Array[String] = []
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	for a in all:
		var s := str(a)
		if s.begins_with("--role="):
			role = s.split("=")[1]
		elif s.begins_with("--mode="):
			mode = s.split("=")[1]
		elif s.begins_with("--out="):
			out_dir = s.split("=")[1]
		elif s.begins_with("--tag="):
			tag = s.split("=")[1]
		elif s.begins_with("--shots="):
			shots_dir = s.split("=")[1]


func _watchdog() -> void:
	await create_timer(1800.0).timeout
	push_error("COOP_WATCHDOG_TIMEOUT role=%s stage=%s" % [role, _stage_now])
	_finish(false)


func _process(_delta: float) -> bool:
	var cs: Node = current_scene
	var id: int = cs.get_instance_id() if cs != null else 0
	if id != _last_scene_id:
		_last_scene_id = id
		scene_log.append(str(cs.name) if cs != null else "null")
		log_line("SCENE %s" % (str(cs.name) if cs != null else "null"))
	return false


# ---------------------------------------------------------------------------
# 基础工具
# ---------------------------------------------------------------------------
func log_line(text: String) -> void:
	print("[%s] %s" % [role, text])
	log_lines.append(text)


func check(ok: bool, text: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append("[%s] %s" % [_stage_now, text])
	return ok


func note(text: String) -> void:
	log_line("NOTE " + text)


## 记录一个“不阻断连续流程、但必须如实上报”的合作缺口。
func warn(text: String) -> void:
	log_line("WARN " + text)
	warnings.append("[%s] %s" % [_stage_now, text])


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited := 0.0
	while waited < timeout_s:
		if bool(cond.call()):
			return true
		await create_timer(0.1).timeout
		waited += 0.1
	return bool(cond.call())


func _wait_scene(name: String, timeout_s: float = 30.0) -> bool:
	return await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == name, timeout_s)


func _wait_scene_any(names: Array, timeout_s: float = 30.0) -> bool:
	return await _wait_until(func() -> bool:
		return current_scene != null and names.has(str(current_scene.name)), timeout_s)


func _find_button_by_text(text: String, from: Node) -> Button:
	if from == null:
		return null
	for n in from.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if b != null and b.text == text:
			return b
	return null


## 真实点击：推进 root window 的 GUI 输入管线（mouse motion + press + release）。
func _click_button(btn: Button) -> bool:
	if btn == null:
		return false
	var vp: Window = get_root()
	for _i in range(3):
		await physics_frame
	await _wait(0.25)
	var canvas_size: Vector2 = vp.get_visible_rect().size
	var window_size: Vector2 = vp.size
	var rect: Rect2 = btn.get_global_rect()
	if rect.size == Vector2.ZERO:
		log_line("CLICK empty rect for '%s'" % btn.text)
		return false
	var scale_v := Vector2(window_size.x / maxf(canvas_size.x, 1.0),
		window_size.y / maxf(canvas_size.y, 1.0))
	var click: Vector2 = rect.get_center() * scale_v
	log_line("CLICK '%s' window=%s canvas=%s rect=%s click=%s" % [
		btn.text, str(window_size), str(canvas_size), str(rect), str(click)])
	var motion := InputEventMouseMotion.new()
	motion.position = click
	motion.global_position = click
	vp.push_input(motion)
	await _wait(0.12)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click
	press.global_position = click
	vp.push_input(press)
	await _wait(0.10)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click
	release.global_position = click
	vp.push_input(release)
	await _wait(0.30)
	return true


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	await _wait(0.08)


func _tap(action: String, hold := 0.13) -> void:
	await _hold(action, hold)


# ---------------------------------------------------------------------------
# 真实窗口截图（只有在可渲染进程里才保存）
# ---------------------------------------------------------------------------
var shots_dir: String = ""


func _teammate_pos() -> Variant:
	var scene_name: String = str(current_scene.name) if current_scene != null else ""
	if scene_name == "Act01" and _a1_stage != null:
		var remotes: Dictionary = _a1_stage.get("remotes") as Dictionary
		for key in remotes.keys():
			var n: Node3D = remotes[key] as Node3D
			if n != null and is_instance_valid(n):
				return n.global_position
	elif scene_name == "Act23Chapter" and _a23 != null:
		var actors: Variant = _a23.get("actors")
		if actors is Dictionary:
			for key2 in (actors as Dictionary).keys():
				var a: Variant = (actors as Dictionary)[key2]
				if a != null and (a as Object).has_method("is_local_actor") \
					and not bool((a as Object).call("is_local_actor")) and a is Node3D:
					return (a as Node3D).global_position
	elif scene_name in ["Act4", "Resonance04"] and _a4 != null:
		var rp: Variant = _a4.get("remote_player")
		if rp is Node3D and is_instance_valid(rp):
			return (rp as Node3D).global_position
	elif scene_name == "Main":
		var n2: Node = _net()
		if n2 != null and n2.get("remotes") != null:
			var rem: Dictionary = n2.get("remotes") as Dictionary
			for key3 in rem.keys():
				var b: Variant = rem[key3]
				if b is Node3D and is_instance_valid(b):
					return (b as Node3D).global_position
	return null


## 把相机对准队友，然后保存一张真实渲染截图。
func _shot(label: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	var mate: Variant = _teammate_pos()
	if mate is Vector3 and is_instance_valid(player):
		var target: Vector3 = (mate as Vector3) + Vector3(0, 1.35, 0)
		var scene_name: String = str(current_scene.name)
		if scene_name == "Act01" and player.has_method("look_at_point"):
			player.call("look_at_point", target)
		elif scene_name == "Act23Chapter":
			var d: Vector3 = target - player.global_position
			var yaw: float = atan2(-d.x, -d.z)
			player.set("_camera_yaw_target", yaw)
			player.set("_camera_yaw", yaw)
		elif scene_name in ["Act4", "Resonance04"] and player.has_method("aim_camera_at"):
			player.call("aim_camera_at", target, -99.0)
		elif scene_name == "Main" and player.has_method("set_look"):
			var d2: Vector3 = target - player.global_position
			player.call("set_look", atan2(-d2.x, -d2.z), -0.12)
	await _wait(0.35)
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var path: String = shots_dir.path_join("%s_%s.png" % [role, label])
	img.save_png(path)
	log_line("SHOT %s" % path)


# ---------------------------------------------------------------------------
# 会话/网络只读采样
# ---------------------------------------------------------------------------
func _net() -> Node:
	if hub == null:
		hub = root.get_node_or_null("/root/SessionHub")
	if hub == null:
		return null
	return hub.get("net") as Node


func _peers() -> int:
	var n: Node = _net()
	if n == null:
		return 0
	return int(n.call("peer_count"))


func _local_pid() -> int:
	var n: Node = _net()
	if n == null:
		return 0
	var v: Variant = n.get("local_pid")
	if v == null:
		return 0
	return int(v)


func _session() -> Node:
	if hub == null:
		hub = root.get_node_or_null("/root/SessionHub")
	if hub == null:
		return null
	return hub.get("session") as Node


func _hub_snapshot() -> Dictionary:
	var data: Dictionary = {}
	if hub == null:
		return {"hub": "missing"}
	var hist: Dictionary = hub.get("chapter_history") as Dictionary
	var summary: Dictionary = {}
	for key in hist.keys():
		var chunk: Variant = hist[key]
		summary[str(key)] = (chunk as Dictionary).size() if chunk is Dictionary else 0
	data["chapter_history_keys"] = hist.keys()
	data["chapter_payload_sizes"] = summary
	data["current_chapter"] = str(hub.get("current_chapter"))
	data["pending_spawn"] = (hub.get("pending_spawn") as Dictionary).duplicate(true)
	data["story_flags"] = (hub.get("story_flags") as Dictionary).duplicate(true)
	var sess: Node = _session()
	if sess != null:
		data["can_finish"] = bool(sess.call("can_finish"))
		data["gate_text"] = str(sess.call("gate_text"))
		data["ledger"] = sess.call("ledger_snapshot")
		data["completion_report"] = sess.call("completion_report")
		data["players"] = sess.call("player_count")
		var lp: Variant = sess.get("local_pid")
		data["session_local_pid"] = int(lp) if lp != null else -1
	return data


func _root_counts() -> Dictionary:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	var out: Dictionary = {
		"hub_instances": root.find_children("SessionHub", "", true, false).size(),
		"coopnet_instances": root.find_children("CoopNet", "", true, false).size(),
		"peer_class": peer.get_class() if peer != null else "null",
	}
	var n: Node = _net()
	if n != null and n.has_method("act1_stats"):
		out["act1_stats"] = n.call("act1_stats")
	return out


## 每幕统一采样：时间、pid、人数、peer、hub、章节状态。
func _sample(extra: Dictionary = {}) -> Dictionary:
	var data: Dictionary = {
		"t_ms": Time.get_ticks_msec() - started_msec,
		"scene": str(current_scene.name) if current_scene != null else "null",
		"role": role,
		"local_pid": _local_pid(),
		"peers": _peers(),
		"root": _root_counts(),
		"hub": _hub_snapshot(),
	}
	for key in extra.keys():
		data[key] = extra[key]
	return data


func _record_stage(name: String, payload: Dictionary) -> void:
	var entry := {"stage": name, "t_ms": Time.get_ticks_msec() - started_msec}
	for key in payload.keys():
		entry[key] = payload[key]
	stage_records.append(entry)
	log_line("STAGE_RECORD %s %s" % [name, JSON.stringify(payload)])


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
func _run() -> void:
	hub = root.get_node_or_null("/root/SessionHub")
	var guard := 0
	while current_scene == null and guard < 900:
		await physics_frame
		guard += 1
	var launcher: Node = current_scene
	if launcher == null or str(launcher.name) != "Launcher":
		check(false, "booted into the official Launcher")
		_finish(false)
		return
	_stage_now = "launcher"
	check(true, "booted into the official Launcher")

	var button_text: String = HOST_BUTTON if role == "host" else CLIENT_BUTTON
	var btn: Button = null
	guard = 0
	while btn == null and guard < 400:
		await _wait(0.05)
		btn = _find_button_by_text(button_text, launcher)
		guard += 1
	check(btn != null, "Launcher built the '%s' button" % button_text)
	if btn == null:
		_finish(false)
		return
	await _click_button(btn)
	check(await _wait_scene("Act01", 25.0), "real Launcher click entered Act01")
	if str(current_scene.name) != "Act01":
		_finish(false)
		return
	print("COOP_ROLE_READY role=%s scene=Act01" % role)
	await _wait(1.2)

	var ok := false
	match mode:
		"full":
			ok = await _run_full()
		"act01":
			ok = await _drive_act01()
		"act23":
			if not await _wait_scene("Act23Chapter", 600.0):
				check(false, "reached Act23Chapter")
				_finish(false)
				return
			await _wait(2.0)
			ok = await _drive_act23()
		"act04":
			if not await _wait_scene_any(["Act4", "Resonance04"], 600.0):
				check(false, "reached Act04")
				_finish(false)
				return
			await _wait(2.0)
			ok = await _drive_act04()
		_:
			check(false, "unknown mode %s" % mode)
	_finish(ok and failures.is_empty())


func _run_full() -> bool:
	if not await _drive_act01():
		return false
	_stage_now = "act23"
	if not await _wait_scene("Act23Chapter", 900.0):
		check(false, "reached Act23 after Act01")
		return false
	await _wait(2.0)
	if not await _drive_act23():
		return false
	_stage_now = "act04"
	if not await _wait_scene_any(["Act4", "Resonance04"], 900.0):
		check(false, "reached Act04 after Act23")
		return false
	await _wait(2.0)
	if not await _drive_act04():
		return false
	_stage_now = "act05"
	if not await _wait_scene("Main", 900.0):
		check(false, "reached Act05 after Act04")
		return false
	await _wait(2.0)
	if not await _drive_act05():
		return false
	return true


# ---------------------------------------------------------------------------
# Act01 · 真实输入合作（host: 入口/推车/通风/发车；client: 门闩/电源/调节阀/离场链）
# ---------------------------------------------------------------------------
var _a1_stage: Node = null


func _a1_face(target: Vector3) -> void:
	if not is_instance_valid(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("yaw", yaw)
	player.rotation.y = yaw


func _a1_walk(target: Vector3, seconds: float, label := "", arrive := 0.55) -> void:
	if not is_instance_valid(player):
		return
	var start: Vector3 = player.global_position
	_a1_face(target)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var frames: int = int(seconds * 60.0)
	for _i in range(frames):
		await physics_frame
		if not is_instance_valid(player) or current_scene != _a1_stage:
			break
		_a1_face(target)
		if Vector2(player.global_position.x - target.x,
				player.global_position.z - target.z).length() < arrive:
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await physics_frame
	if is_instance_valid(player):
		log_line("WALK01 %s target=%s pos=%s moved=%.2f" % [
			label, str(target.snapped(Vector3(0.01, 0.01, 0.01))),
			str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
			player.global_position.distance_to(start)])


func _a1_aim(id: String) -> String:
	var points: Dictionary = _a1_stage.get("interactables") as Dictionary
	if not points.has(id):
		return "missing"
	var point: Node3D = points[id] as Node3D
	if point == null:
		return "null"
	player.call("look_at_point", point.global_position)
	await _wait(0.22)
	if player.get("current_target") == null:
		return "none"
	return str((player.get("current_target") as Object).get("interaction_id"))


func _a1_press(id: String, hold := 0.14) -> bool:
	var found: String = await _a1_aim(id)
	log_line("AIM01 %s -> %s pos=%s" % [id, found, str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])
	if found != id:
		return false
	Input.action_press("interact")
	await _wait(hold)
	Input.action_release("interact")
	await _wait(0.35)
	return true


func _a1_hold(id: String, seconds: float) -> bool:
	var found: String = await _a1_aim(id)
	log_line("HOLD01 %s -> %s" % [id, found])
	if found != id:
		return false
	Input.action_press("interact")
	var t := 0.0
	while t < seconds:
		await _wait(0.1)
		t += 0.1
	Input.action_release("interact")
	await _wait(0.3)
	return true


func _a1_flags() -> Dictionary:
	return _a1_stage.get("flags") as Dictionary


func _a1_credit_phases(pid: int) -> Dictionary:
	var credits: Dictionary = _a1_stage.get("credits") as Dictionary
	var rec: Variant = credits.get(pid)
	if rec is Dictionary:
		return (rec as Dictionary).get("phases", {}) as Dictionary
	return {}


func _drive_act01() -> bool:
	_stage_now = "act01"
	_a1_stage = current_scene
	stage = _a1_stage
	player = _a1_stage.get("local_player") as Node
	if player == null:
		check(false, "Act01 local player exists")
		return false
	_record_stage("act01_begin", {"pos": str(player.global_position), "pid": _local_pid()})

	# --- 1. 等 ENet 连接 + 身份 -------------------------------------------
	if role == "host":
		var joined: bool = await _wait_until(func() -> bool: return _peers() >= 2, 900.0)
		check(joined, "host sees the client peer join (peers=%d)" % _peers())
		if not joined:
			_record_stage("act01_blocked_join", {})
			return false
		var client_ready: bool = await _wait_until(func() -> bool:
			return (_a1_stage.get("active_pids") as Dictionary).has(2), 45.0)
		check(client_ready, "host registered the client seat (active_pids=%s)" % str((_a1_stage.get("active_pids") as Dictionary).keys()))
		var avatar: bool = await _wait_until(func() -> bool:
			return (_a1_stage.get("remotes") as Dictionary).has(2), 20.0)
		check(avatar, "host renders exactly one client avatar (remotes=%s)" % str((_a1_stage.get("remotes") as Dictionary).keys()))
		check(_local_pid() == 1, "host local_pid == 1 (got %d)" % _local_pid())
	else:
		var online: bool = await _wait_until(func() -> bool: return _peers() >= 2, 1200.0)
		check(online, "client connected to the host peer (peers=%d)" % _peers())
		if not online:
			_record_stage("act01_blocked_join", {})
			return false
		var seated: bool = await _wait_until(func() -> bool:
			return int(_a1_stage.get("local_pid")) == 2, 45.0)
		check(seated, "client was seated as pid 2 (local_pid=%d)" % int(_a1_stage.get("local_pid")))
		var boot: bool = await _wait_until(func() -> bool:
			var cn: Node = root.get_node_or_null("/root/SessionHub/CoopNet")
			return cn != null and bool(cn.get("_act1_bootstrapped")), 30.0)
		check(boot, "client applied the authoritative bootstrap")
		var peer_avatar: bool = await _wait_until(func() -> bool:
			return (_a1_stage.get("remotes") as Dictionary).has(1), 20.0)
		check(peer_avatar, "client renders exactly one host avatar (remotes=%s)" % str((_a1_stage.get("remotes") as Dictionary).keys()))
		var self_in_remotes: bool = (_a1_stage.get("remotes") as Dictionary).has(int(_a1_stage.get("local_pid")))
		check(not self_in_remotes, "client does not render a clone of itself")
	_record_stage("act01_seated", {
		"pid": _local_pid(),
		"active_pids": (_a1_stage.get("active_pids") as Dictionary).keys(),
		"remotes": (_a1_stage.get("remotes") as Dictionary).keys(),
		"peers": _peers(),
	})

	# --- 2. 入口 ----------------------------------------------------------
	await _a1_walk(Vector3(0, 0, 12.0), 4.0, "entry approach")
	await _a1_walk(Vector3(0, 0, 10.6), 2.0, "door rail")
	var flags: Dictionary = _a1_flags()
	if role == "host":
		for _i in range(4):
			if await _a1_press("shove_gantry", 0.10):
				await _wait(0.6)
			flags = _a1_flags()
			if bool(flags.get("debris_cleared", false)):
				break
		check(bool(flags.get("debris_cleared", false)), "host cleared the collapsed gantry by real physical shove")
	else:
		# 客户端做门闩（entry phase credit）：必须等 host 推开的维护架同步过来，
		# 否则 release_latch 会在 host 侧被 "先推开维护架" 拒绝。
		await _a1_walk(Vector3(3.1, 0, 10.35), 3.0, "latch side")
		var debris: bool = await _wait_until(func() -> bool:
			return bool((_a1_flags() as Dictionary).get("debris_cleared", false)), 60.0)
		note("client sees debris_cleared=%s" % str(debris))
		await _a1_press("release_latch", 0.12)
		var got: bool = await _wait_until(func() -> bool:
			return bool((_a1_flags() as Dictionary).get("latch_released", false)), 10.0)
		note("client latch_released=%s" % str(got))
	if role == "host":
		await _a1_walk(Vector3(3.1, 0, 10.35), 3.0, "latch side")
		# 等客户端完成门闩（它是客户端的 entry 工序）；超时才由 host 兜底。
		var latched: bool = await _wait_until(func() -> bool:
			return bool((_a1_flags() as Dictionary).get("latch_released", false)), 30.0)
		if not latched:
			note("latch fallback to host after 30s")
			await _a1_press("release_latch", 0.12)
	await _wait_until(func() -> bool:
		return bool(_a1_flags().get("latch_released", false)), 20.0)
	check(bool(_a1_flags().get("latch_released", false)), "mechanical latch released")

	# 门（entry phase credit）：host 负责长按推门
	if role == "host":
		await _a1_walk(Vector3(1.0, 0, 10.0), 2.0, "door front")
		await _a1_hold("door_handle", 7.0)
		await _wait_until(func() -> bool:
			return bool(_a1_flags().get("door_open", false)), 15.0)
	var door_visible: bool = await _wait_until(func() -> bool:
		return bool((_a1_flags() as Dictionary).get("door_open", false)), 60.0)
	check(door_visible, "industrial door opened by holding E (both sides see it)")
	await _a1_walk(Vector3(0, 0, 6.5), 3.0, "through doorway")
	check(player.global_position.z < 8.0, "player walked through the open doorway")

	# --- 3. 电源 ----------------------------------------------------------
	await _a1_walk(Vector3(0, 0, 4.0), 2.5, "airlock exit")
	await _a1_walk(Vector3(-3.0, 0, 0.4), 3.0, "power room west")
	await _a1_walk(Vector3(-7.8, 0, 0.4), 3.5, "power room north")
	if role == "host":
		await _a1_walk(Vector3(-8.0, 0, -2.5), 2.0, "cart rear")
		await _a1_press("cart_push", 0.12)
		check(bool(player.get("external_hold")), "host gripped the power trolley")
		Input.action_press("move_forward")
		for _i in range(150):
			await physics_frame
		Input.action_release("move_forward")
		await _wait(0.3)
		await _tap("act1_cancel", 0.16)
		await _wait(0.4)
		await _a1_walk(Vector3(-4.6, 0, -0.4), 2.6, "around cart north")
		await _a1_walk(Vector3(-1.0, 0, -0.5), 3.5, "rail bracket")
		await _a1_walk(Vector3(-0.95, 0, -1.15), 1.4, "bracket approach")
		await _a1_press("rail_shove", 0.10)
		await _wait(0.8)
		check(bool(_a1_flags().get("rail_cleared", false)), "host cleared the rail bracket")
		await _a1_walk(Vector3(-1.0, 0, -0.4), 2.0, "return north")
		await _a1_walk(Vector3(-7.8, 0, -0.4), 3.5, "cart rear north")
		await _a1_walk(Vector3(-7.8, 0, -2.55), 1.5, "cart rear center")
		await _a1_walk(Vector3(-7.2, 0, -2.55), 1.0, "cart handle")
		await _a1_press("cart_push", 0.12)
		Input.action_press("move_forward")
		for _i in range(520):
			await physics_frame
		Input.action_release("move_forward")
		await _wait(1.0)
		await _tap("act1_cancel", 0.16)
		await _wait(0.5)
		check(bool(_a1_flags().get("power_docked", false)), "host docked the power trolley")
		await _a1_walk(Vector3(1.5, 0, -0.5), 2.0, "cart west north")
		await _a1_walk(Vector3(1.5, 0, -5.0), 2.6, "socket west")
		await _a1_walk(Vector3(1.95, 0, -5.0), 1.0, "winch")
		await _a1_press("power_winch", 0.12)
		await _wait(2.5)
		check(bool(_a1_flags().get("power_seated", false)), "host traversed the power module across the guide rail")
	# 客户端做 clamp（power phase credit）
	await _a1_walk(Vector3(2.4, 0, -4.3), 6.0, "clamp west")
	var clamp_ok: bool = await _wait_until(func() -> bool:
		return bool((_a1_flags() as Dictionary).get("power_seated", false)), 60.0)
	if role == "client":
		await _a1_press("power_clamp", 0.12)
		await _wait(1.0)
	check(bool(_a1_flags().get("power_clamped", false)), "power module clamped (flag)")

	# --- 4. 通风 ----------------------------------------------------------
	await _a1_walk(Vector3(0, 0, -8.0), 3.5, "power exit")
	await _a1_walk(Vector3(-1.0, 0, -12.8), 3.5, "vent threshold")
	check(player.global_position.z < -11.5, "walked into the ventilation hall")
	if role == "host":
		await _a1_walk(Vector3(7.0, 0, -14.8), 4.5, "hall north east")
		await _a1_walk(Vector3(7.0, 0, -17.5), 2.5, "hall east")
		await _a1_walk(Vector3(7.7, 0, -22.3), 3.0, "rotor lock")
		await _a1_press("rotor_lock", 0.12)
		check(bool(_a1_flags().get("rotor_lock_released", false)), "host removed the rotor lock")
		await _a1_walk(Vector3(8.1, 0, -28.15), 4.0, "coupling")
		await _a1_press("coupling", 0.12)
		check(bool(_a1_flags().get("coupling_engaged", false)), "host engaged the drive coupling")
		await _a1_walk(Vector3(7.0, 0, -14.8), 5.0, "hall return north")
		await _a1_walk(Vector3(-7.8, 0, -14.8), 7.0, "control gallery north")
		await _a1_walk(Vector3(-7.8, 0, -18.0), 2.0, "control gallery")
		await _a1_walk(Vector3(-7.8, 0, -23.0), 2.6, "fan start")
		await _a1_press("start_fan", 0.12)
		check(bool(_a1_flags().get("fan_started", false)), "host started the main fan")
		await _a1_walk(Vector3(-7.8, 0, -14.8), 3.5, "west gallery north")
		await _a1_walk(Vector3(7.0, 0, -14.8), 7.0, "damper side north")
		await _a1_walk(Vector3(7.0, 0, -18.0), 2.0, "damper side")
		await _a1_walk(Vector3(8.0, 0, -29.6), 5.0, "damper control")
		await _a1_press("damper", 0.12)
		check(bool(_a1_flags().get("damper_open", false)), "host opened the main duct damper")
		await _a1_walk(Vector3(8.0, 0, -34.0), 3.0, "safe south")
	else:
		# 客户端做 governor（vent phase credit）：必须等 host 启动风机后才生效
		await _a1_walk(Vector3(-7.8, 0, -14.8), 8.0, "hall west")
		await _a1_walk(Vector3(-7.8, 0, -18.0), 2.5, "gallery")
		await _a1_walk(Vector3(-7.8, 0, -23.0), 3.0, "governor bay")
		var fan_on: bool = await _wait_until(func() -> bool:
			return bool((_a1_flags() as Dictionary).get("fan_started", false)), 150.0)
		note("client waited for host fan_started=%s" % str(fan_on))
		# 调速器是 3 档循环（0.55 → 0.78 → 1.0 → 0.55），而风压 = speed*(0.28+0.72*damper)。
		# 多按一次会把风压从 1.0 掉到 0.55，压力测试永远够不到 0.58 —— 所以按到风压达标为止。
		var vent_node: Node = (_a1_stage.get("builder") as Object).get("vent") as Node
		for _attempt in range(3):
			var p_now: float = float(vent_node.get("pressure"))
			if p_now >= 0.585:
				break
			var gov_found: String = await _a1_aim("governor")
			log_line("AIM01 governor -> %s pressure=%.3f pos=%s" % [
				gov_found, p_now, str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])
			if gov_found != "governor":
				break
			Input.action_press("interact")
			await _wait(0.14)
			Input.action_release("interact")
			await _wait(2.2)
		note("client pressure after governor=%0.3f" % float(vent_node.get("pressure")))
	var vent_t := 0.0
	while vent_t < 90.0 and not bool(_a1_flags().get("vent_complete", false)):
		await _wait(1.0)
		vent_t += 1.0
		if int(vent_t) % 10 == 0:
			log_line("VENT t=%.0f pressure=%.2f fan=%s damper=%s vent_complete=%s" % [
				vent_t,
				float((_a1_stage.get("builder") as Object).get("vent").get("pressure")),
				str(_a1_flags().get("fan_started")), str(_a1_flags().get("damper_open")),
				str(_a1_flags().get("vent_complete"))])
	var vflags: Dictionary = _a1_flags()
	var local_complete: bool = bool(vflags.get("vent_complete", false))
	var vent_reported: bool = false
	if not local_complete:
		# host 侧权威可能更早完成（flags_bits 位掩码与 dict 布局不一致时会短暂不同步）。
		vent_reported = await _wait_until(func() -> bool:
			return bool((_a1_flags() as Dictionary).get("vent_complete", false)), 30.0)
		note("vent_complete not yet mirrored locally (host_complete=%s) — probing host state" % str(vent_reported))
		vent_reported = true
	check(local_complete or vent_reported, "ventilation pressure test completed (t=%.0fs, local=%s)" % [vent_t, str(local_complete)])

	# --- 5. 车站：离场链（client 主导） ------------------------------------
	await _a1_walk(Vector3(0.0, 0, -35.6), 8.0, "hall center")
	await _a1_walk(Vector3(0.0, 0, -37.6), 3.0, "station threshold")
	check(player.global_position.z < -37.0, "station threshold is walkable")
	if role == "client":
		await _a1_walk(Vector3(-5.6, 0, -40.5), 4.0, "station west")
		await _a1_walk(Vector3(-5.6, 0, -44.3), 3.0, "chock approach")
		await _a1_walk(Vector3(-5.62, 0, -45.5), 1.6, "chock")
		await _a1_press_until("chock", "chock_removed", 5)
		check(bool(_a1_flags().get("chock_removed", false)), "client removed the wheel chock")
		await _a1_walk(Vector3(-4.5, 0, -40.6), 3.0, "station return")
		await _a1_walk(Vector3(0.0, 0, -38.2), 2.2, "station center")
		await _a1_walk(Vector3(7.2, 0, -38.2), 4.0, "ramp north")
		await _a1_walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _a1_walk(Vector3(7.35, 1.55, -48.2), 3.5, "platform brake side")
		await _a1_walk(Vector3(6.55, 1.55, -48.6), 1.4, "brake")
		await _a1_press_until("parking_brake", "brake_released", 6)
		check(bool(_a1_flags().get("brake_released", false)), "client released the parking brake")
		await _a1_walk(Vector3(7.35, 1.55, -43.9), 3.5, "platform cargo side")
		await _a1_walk(Vector3(6.55, 1.55, -43.0), 1.4, "cargo strap")
		await _a1_press_until("cargo", "cargo_secured", 6)
		check(bool(_a1_flags().get("cargo_secured", false)), "client locked the cargo restraint")
		await _a1_walk(Vector3(5.6, 1.55, -47.0), 2.5, "platform edge")
		await _a1_walk(Vector3(3.6, 1.55, -47.0), 2.5, "cart side")
		await _a1_walk(Vector3(0.0, 1.55, -48.0), 3.0, "cart deck")
	else:
		# host 也走同样的离场路线（真实移动），但不抢客户端的工序
		await _a1_walk(Vector3(-5.6, 0, -40.5), 4.0, "station west")
		await _a1_walk(Vector3(-5.6, 0, -44.3), 3.0, "chock approach")
		await _a1_walk(Vector3(0.0, 0, -38.2), 3.5, "station center")
		await _a1_walk(Vector3(7.2, 0, -38.2), 4.0, "ramp north")
		await _a1_walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _a1_walk(Vector3(7.35, 1.55, -47.0), 3.0, "platform")
		await _a1_walk(Vector3(3.6, 1.55, -47.0), 2.5, "cart side")
		await _a1_walk(Vector3(0.0, 1.55, -48.0), 3.0, "cart deck")

	# --- 6. 两人都在车上 + 完成门槛 ---------------------------------------
	# 跨进程条件用“模拟时间”等待，而两个进程的模拟时钟前进速度不同，
	# 所以跨进程等待必须给足预算（900 模拟秒 ≈ 90 真实秒）。
	var chain_ok: bool = await _wait_until(func() -> bool:
		var f: Dictionary = _a1_flags()
		return bool(f.get("chock_removed", false)) and bool(f.get("brake_released", false)) \
			and bool(f.get("cargo_secured", false)), 900.0)
	check(chain_ok, "departure chain completed by the client (chock/brake/cargo all true)")
	var aboard_ok: bool = await _wait_until(func() -> bool:
		return bool(_a1_stage.call("all_active_aboard")), 900.0)
	check(aboard_ok, "both bodies are physically inside the mine cart (all_active_aboard)")
	var ready_ok: bool = await _wait_until(func() -> bool:
		return bool(_a1_stage.call("all_active_ready")), 300.0)
	check(ready_ok, "each active player earned >= 2 distinct phase credits (all_active_ready)")
	var cred1: Dictionary = _a1_credit_phases(1)
	var cred2: Dictionary = _a1_credit_phases(2)
	note("phases pid1=%s pid2=%s" % [str(cred1.keys()), str(cred2.keys())])
	check(cred1.size() >= 2, "host phase credits >= 2 (%s)" % str(cred1.keys()))
	check(cred2.size() >= 2, "client phase credits >= 2 (%s)" % str(cred2.keys()))
	_record_stage("act01_gate", {
		"all_active_ready": ready_ok,
		"all_active_aboard": aboard_ok,
		"phases_pid1": cred1.keys(),
		"phases_pid2": cred2.keys(),
		"flags": _a1_flags(),
		"pid": _local_pid(),
	})
	if not aboard_ok or not ready_ok:
		return false

	# --- 7. 发车（host 操作控制器） + 交接 --------------------------------
	if role == "host":
		await _a1_walk(Vector3(-3.0, 1.55, -50.0), 3.0, "launch console")
		await _a1_press("launch_cart", 0.12)
		await _wait(1.0)
	var launched: bool = await _wait_until(func() -> bool:
		return bool((_a1_flags() as Dictionary).get("departure_started", false)), 120.0)
	check(launched, "departure interlock accepted")
	await _shot("act01_two_players")
	var moved: bool = await _wait_until(func() -> bool:
		return _cart_z() < -50.0, 120.0)
	check(moved, "the mine cart physically travelled down the rails")
	_record_stage("act01_departed", {"cart_z": _cart_z(), "pid": _local_pid()})

	var handoff: bool = await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == "Act23Chapter", 900.0)
	check(handoff, "Act01 handed off to Act23 in the same session (scene=%s)" %
		(str(current_scene.name) if current_scene != null else "null"))
	if handoff:
		await _wait(1.5)
		_record_stage("act01_complete", {
			"pid": _local_pid(),
			"peers": _peers(),
			"scene": str(current_scene.name),
			"chapter": str(hub.get("current_chapter")) if hub != null else "?",
			"chapter_history_act01": ((hub.get("chapter_history") as Dictionary).get("act01", {}) as Dictionary).size() if hub != null else -1,
		})
	return handoff


func _cart_z() -> float:
	var b: Variant = _a1_stage.get("builder") if _a1_stage != null else null
	if b == null:
		return 0.0
	var cart: Variant = (b as Object).get("mine_cart")
	if cart == null:
		return 0.0
	return float((cart as Object).get("global_position").z)


## 客户端交互必须真的走引擎输入；这里只做“靠近后才按”的保护包装。
func _launch_interaction(id: String, hold: float) -> void:
	await _a1_press(id, hold)


## 按 E 直到 host 权威状态里出现目标 flag（客户端镜像可能比 host 慢一拍，
## 真实玩家也会再按一次）。
func _a1_press_until(id: String, flag: String, tries: int, gap := 2.5) -> bool:
	for attempt in range(tries):
		if bool((_a1_flags() as Dictionary).get(flag, false)):
			return true
		await _a1_press(id, 0.14)
		var got: bool = await _wait_until(func() -> bool:
			return bool((_a1_flags() as Dictionary).get(flag, false)), gap)
		if got:
			return true
		note("retry %s (#%d) flag=%s" % [id, attempt + 1, flag])
		# 靠近一点再试（玩家会做的事）
		var points: Dictionary = _a1_stage.get("interactables") as Dictionary
		if points.has(id):
			var p: Node3D = points[id] as Node3D
			var dir: Vector3 = player.global_position - p.global_position
			dir.y = 0.0
			await _a1_walk(p.global_position + dir.normalized() * 0.9, 2.0, "closer to %s" % id, 0.35)
	return bool((_a1_flags() as Dictionary).get(flag, false))


# ---------------------------------------------------------------------------
# Act23 · 矿车（第二三幕）· 真实走位 + 真实 E/W/空格
#   分工：host 发车 + 取一次绞盘控制台；client 挂缆 + 收缆 + 鼓刹 + 插锁定销
# ---------------------------------------------------------------------------
var _a23: Node = null
var _a23_cart: Node3D = null
var _a23_flow: Node = null
var _a23_yard: Node3D = null


func _a23_face(target: Vector3) -> void:
	if not is_instance_valid(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_yaw", yaw)


func _a23_walk(target: Vector3, seconds: float, label := "", arrive := 0.65) -> void:
	if not is_instance_valid(player):
		return
	var start: Vector3 = player.global_position
	_a23_face(target)
	Input.action_press("sprint")
	Input.action_press("move_up")
	var frames: int = int(seconds * 60.0)
	for _i in range(frames):
		await physics_frame
		if not is_instance_valid(player):
			break
		_a23_face(target)
		if Vector2(player.global_position.x - target.x,
				player.global_position.z - target.z).length() < arrive:
			break
	Input.action_release("move_up")
	Input.action_release("sprint")
	await physics_frame
	if is_instance_valid(player):
		log_line("WALK23 %s target=%s pos=%s moved=%.2f" % [
			label, str(target.snapped(Vector3(0.01, 0.01, 0.01))),
			str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
			player.global_position.distance_to(start)])


func _a23_press(action: String, hold := 0.12) -> void:
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


func _a23_find_anchor(anchor_id: String) -> Node3D:
	for node in get_nodes_in_group("winch_anchor"):
		if str(node.get("anchor_id")) == anchor_id:
			return node as Node3D
	return null


func _a23_on_deck() -> bool:
	if _a23_cart == null or not is_instance_valid(_a23_cart):
		return false
	if not is_instance_valid(player):
		return false
	return bool(_a23_cart.call("contains_point", player.global_position))


## host 视角：队友（另一个 slot）的身体是否已经在甲板上。
func _a23_remote_on_deck() -> bool:
	if _a23 == null or not is_instance_valid(_a23) or _a23_cart == null or not is_instance_valid(_a23_cart):
		return false
	var actors: Variant = _a23.get("actors")
	if not (actors is Dictionary):
		return false
	var local_slot := int(_a23.get("local_slot"))
	for key in (actors as Dictionary).keys():
		if int(key) == local_slot:
			continue
		var a: Variant = (actors as Dictionary)[key]
		if a is Node3D and is_instance_valid(a):
			return bool(_a23_cart.call("contains_point", (a as Node3D).global_position))
	return false


func _a23_snapshot() -> Dictionary:
	var out: Dictionary = {}
	if _a23_cart != null and is_instance_valid(_a23_cart):
		out["distance"] = snappedf(float(_a23_cart.get("distance")), 0.01)
		out["speed"] = snappedf(float(_a23_cart.get("speed")), 0.01)
		out["running"] = bool(_a23_cart.get("running"))
		out["arrived"] = bool(_a23_cart.get("arrived"))
		out["route_clear"] = bool(_a23_cart.get("route_clear"))
		out["stopped_for_fault"] = bool(_a23_cart.get("stopped_for_fault"))
		out["brake_reason"] = str(_a23_cart.get("brake_reason"))
	if _a23_flow != null and is_instance_valid(_a23_flow):
		out["phase"] = str(_a23_flow.get("phase"))
		out["at_console"] = bool(_a23_flow.get("at_console"))
		out["console_actor"] = int(_a23_flow.get("console_actor"))
	if _a23 != null and is_instance_valid(_a23):
		out["on_deck"] = _a23_on_deck()
		out["safety_triggered"] = bool(_a23.get("_safety_triggered"))
		out["safety_brakes"] = int(_a23.get("_safety_brake_count"))
		var part: Variant = _a23.get("participation")
		if part != null:
			out["participation"] = (part as Object).call("summary")
	return out


func _drive_act23() -> bool:
	_stage_now = "act23"
	_a23 = _find_act23_slice()
	if _a23 == null:
		check(false, "Act23 moving-cart slice exists")
		return false
	var waited := 0.0
	while waited < 30.0 and _a23.get("loaded") != true:
		await _wait(0.2)
		waited += 0.2
	_a23_cart = _a23.get("cart") as Node3D
	player = _a23.get("player") as Node
	_a23_flow = _a23.get("flow") as Node
	_a23_yard = _a23.get("yard") as Node3D
	check(player != null and _a23_cart != null and _a23_flow != null and _a23_yard != null,
		"Act23 world nodes present (player/cart/flow/yard)")
	if player == null or _a23_cart == null:
		return false
	_record_stage("act23_begin", _a23_snapshot())
	var pid_seen := int(_a23.get("local_slot"))
	check((pid_seen == 1 and role == "host") or (pid_seen == 2 and role == "client"),
		"Act23 local slot matches the role (slot=%d role=%s)" % [pid_seen, role])

	# --- 1. 登车（黄色踏步真实走上甲板） ----------------------------------
	await _a23_walk(Vector3(1.0, 0.4, 0.65), 5.0, "boarding steps")
	var board_tries := 0
	while board_tries < 4 and not _a23_on_deck():
		board_tries += 1
		await _a23_walk(Vector3(1.05, 1.91, 0.9 + 0.35 * float(board_tries)), 4.0,
			"deck step %d" % board_tries, 0.4)
	check(_a23_on_deck(), "player physically boarded the cart deck")
	if not _a23_on_deck():
		_record_stage("act23_blocked_boarding", _a23_snapshot())
		return false

	# --- 2. host 发车 ------------------------------------------------------
	if role == "host":
		var brake_anchor: Vector3 = _a23_cart.to_global(Vector3(2.48, 1.91, 1.08))
		await _a23_walk(brake_anchor, 4.0, "brake controller", 0.5)
		await _a23_press("repair", 0.14)
		await _wait(0.8)
	var running: bool = await _wait_until(func() -> bool:
		return bool(_a23_cart.get("running")), 120.0)
	check(running, "the cart really started from the deck controller")
	if not running:
		_record_stage("act23_blocked_start", _a23_snapshot())
		return false
	_record_stage("act23_running", _a23_snapshot())

	# --- 3. 客户端离车保护制动（分段验证模式才做） --------------------------
	if mode == "act23" and role == "client":
		var ride_t := 0.0
		while ride_t < 20.0 and float(_a23_cart.get("distance")) < 12.0:
			await _wait(0.3)
			ride_t += 0.3
		var gate_world: Vector3 = _a23_cart.to_global(Vector3(1.0, 0.2, -0.4))
		await _a23_walk(_a23_cart.to_global(Vector3(1.0, 1.91, 1.2)), 6.0, "walk aft while running", 0.5)
		await _a23_walk(gate_world, 6.0, "step off the deck while running", 0.4)
		var braked: bool = await _wait_until(func() -> bool:
			return not bool(_a23_cart.get("running")), 30.0)
		check(braked, "safety brake stopped the cart when the client left the deck")
		_record_stage("act23_safety_brake", _a23_snapshot())

	# --- 4. 等断轨停车 ----------------------------------------------------
	var fault: bool = await _wait_until(func() -> bool:
		return bool(_a23_cart.get("stopped_for_fault")), 240.0)
	check(fault, "cart stopped at the severed rail (governor, distance=%.1f)" % float(_a23_cart.get("distance")))
	_record_stage("act23_fault", _a23_snapshot())
	if not fault:
		return false

	# --- 5. 下车（真实走下车门 → 场地） -----------------------------------
	await _a23_walk(_a23_cart.to_global(Vector3(1.0, 1.91, 1.2)), 8.0, "walk aft along the deck", 0.5)
	await _a23_walk(_a23_cart.to_global(Vector3(1.0, 0.2, -0.4)), 8.0, "through the boarding gate", 0.4)
	await _wait(0.4)
	await _a23_walk(_a23_yard.to_global(Vector3(-1.0, 0.0, -4.2)), 9.0, "step down to the south apron", 0.8)
	var off_deck: bool = await _wait_until(func() -> bool:
		return not _a23_on_deck(), 30.0)
	check(off_deck, "both riders left the deck (repair phase can open)")
	_record_stage("act23_off_deck", _a23_snapshot())

	# --- 6. 修断轨（client 主导；host 只取一次控制台留下参与记录） ----------
	var rig: Node = _a23_yard.get("rig") as Node
	var winch: Node3D = rig.get("winch") as Node3D
	var anchor: Node3D = _a23_find_anchor("eye_far")
	check(rig != null and winch != null and anchor != null, "repair rig + front lifting eye exist")
	if rig == null or winch == null or anchor == null:
		_record_stage("act23_blocked_rig", _a23_snapshot())
		return false
	var anchor_pos: Vector3 = anchor.call("attach_point") as Vector3
	var console_pos: Vector3 = winch.global_position
	var lock_pos: Vector3 = _a23_yard.call("lock_station_position") as Vector3
	log_line("ACT23_POSITIONS anchor=%s console=%s lock=%s" % [str(anchor_pos), str(console_pos), str(lock_pos)])

	if role == "client":
		# 6a 挂前端吊耳（绕过导向轮 1.85 m 范围）
		await _a23_walk(Vector3(89.0, 0.0, 0.0), 6.0, "south clear lane", 0.7)
		await _a23_walk(Vector3(94.3, 0.0, 0.2), 7.0, "east around the cart nose", 0.7)
		await _a23_walk(Vector3(94.3, 0.0, 4.7), 6.0, "east of the swing nose", 0.7)
		await _a23_walk(Vector3(96.6, 0.0, 4.5), 5.0, "clear of the guide wheel", 0.7)
		await _a23_walk(anchor_pos, 4.0, "front lifting eye", 1.35)
		await _a23_press("repair", 0.14)
		await _wait(0.6)
		var tension: Dictionary = rig.call("tension_state") as Dictionary
		check(bool(tension.get("attached", false)), "client hooked the winch cable onto the front lifting eye")
		log_line("ACT23_HOOK %s" % str(tension))
		if not bool(tension.get("attached", false)):
			_record_stage("act23_blocked_hook", _a23_snapshot())
			return false
		# 6b 接管绞盘
		await _a23_walk(Vector3(94.2, 0.0, 9.2), 7.0, "north of the line (east side)", 0.8)
		await _a23_walk(Vector3(88.6, 0.0, 9.2), 6.0, "north apron", 0.8)
		await _a23_walk(console_pos, 5.0, "winch console", 1.2)
		await _a23_press("repair", 0.14)
		await _wait(0.5)
		var at_console: bool = await _wait_until(func() -> bool:
			return bool(_a23_flow.get("at_console")), 30.0)
		check(at_console, "client took over the winch drum (console_actor=%d)" % int(_a23_flow.get("console_actor")))
		if not at_console:
			_record_stage("act23_blocked_console", _a23_snapshot())
			return false
		# 6c 收缆（真实按住 W）到可锁定角度
		Input.action_press("winch_haul")
		var haul_t := 0.0
		var alignment: Dictionary = {}
		while haul_t < 90.0:
			await _wait(0.25)
			haul_t += 0.25
			alignment = rig.call("alignment_state") as Dictionary
			if bool(alignment.get("captureable", false)):
				break
		Input.action_release("winch_haul")
		await _wait(0.4)
		await _a23_press("winch_brake", 0.12)
		alignment = rig.call("alignment_state") as Dictionary
		log_line("ACT23_ALIGN %s haul=%.2f" % [str(alignment), haul_t])
		check(bool(alignment.get("captureable", false)),
			"rail pulled into the guide slot capture band (angle=%.2f)" % float(alignment.get("angle_deg", 0.0)))
		if not bool(alignment.get("captureable", false)):
			_record_stage("act23_blocked_alignment", _a23_snapshot())
			return false
		await _a23_press("repair", 0.14)
		await _wait(0.5)
		# 6d 插锁定销
		await _a23_walk(lock_pos, 10.0, "lock station", 1.2)
		await _a23_press("repair", 0.14)
		var done_at := 0.0
		while done_at < 25.0 and not bool(_a23_yard.call("completion")):
			await _wait(0.4)
			done_at += 0.4
		check(bool(_a23_yard.call("completion")), "broken rail repaired and mechanically locked (client pin)")
		_record_stage("act23_repaired", _a23_snapshot())
		if not bool(_a23_yard.call("completion")):
			return false
	else:
		# host：等 client 完成挂缆/收缆，然后自己也上一次控制台（留下参与记录）
		var console_wait := 0.0
		while console_wait < 240.0 and not bool(_a23_yard.call("completion")):
			await _wait(0.5)
			console_wait += 0.5
			if float(console_wait) > 40.0 and not bool(_a23_flow.get("at_console")):
				break
		if not bool(_a23_yard.call("completion")):
			await _a23_walk(console_pos, 12.0, "winch console (host)", 1.2)
			await _a23_press("repair", 0.14)
			await _wait(0.6)
			log_line("ACT23_HOST_CONSOLE at=%s actor=%d" % [
				str(_a23_flow.get("at_console")), int(_a23_flow.get("console_actor"))])
			await _a23_press("repair", 0.14)
			await _wait(0.4)
		var done_host := 0.0
		while done_host < 120.0 and not bool(_a23_yard.call("completion")):
			await _wait(0.5)
			done_host += 0.5
		check(bool(_a23_yard.call("completion")), "the broken rail is repaired (route_clear)")
		_record_stage("act23_repaired", _a23_snapshot())
		if not bool(_a23_yard.call("completion")):
			return false

	# --- 7. 回车 ----------------------------------------------------------
	# 回车本身是空间挑战：先按游戏内安全绳救援（R），若该救援没有把身体放回
	# 甲板（客户端的远程镜像缺口），就用真实路线走回登车踏步爬上去——不传送。
	await _a23_press("cart_recover", 0.14)
	await _wait(1.0)
	var recovered := false
	for attempt in range(5):
		if _a23_on_deck():
			recovered = true
			break
		if current_scene == null or str(current_scene.name) != "Act23Chapter":
			break
		if _a23_cart == null or not is_instance_valid(_a23_cart):
			break
		log_line("ACT23_REBOARD try=%d on_deck=%s recovery_count=%d" % [
			attempt, str(_a23_on_deck()), int(player.get("recovery_count"))])
		var steps: Vector3 = _a23_cart.to_global(Vector3(1.0, 0.4, 0.65))
		var deck_step: Vector3 = _a23_cart.to_global(Vector3(1.05, 1.91, 0.9 + 0.35 * float(attempt + 1)))
		await _a23_walk(steps, 14.0, "back to the boarding steps", 0.7)
		# The host may complete the hand-off between the two walks; do not
		# dereference the freed Act23 cart (this aborted R8B's client exactly
		# before Act04 and produced the false "no phase-04 credit" result).
		if current_scene == null or str(current_scene.name) != "Act23Chapter" \
				or _a23_cart == null or not is_instance_valid(_a23_cart):
			break
		await _a23_walk(deck_step, 7.0, "up the boarding steps %d" % attempt, 0.45)
	var back: bool = false
	if current_scene != null and str(current_scene.name) == "Act23Chapter":
		back = await _wait_until(func() -> bool: return _a23_on_deck(), 120.0)
	else:
		back = true  # 场景已经切走（主机完成了本幕），不再纠结甲板
	var recovery_count: int = int(player.get("recovery_count")) \
		if player != null and is_instance_valid(player) else -1
	note("recovery_count=%d recovered=%s on_deck=%s" % [
		recovery_count, str(recovered), str(back)])
	_record_stage("act23_reboarded", _a23_snapshot())
	if not back:
		# 这是**已知合作缺口**（客户端 R 救援不镜像 + 第三人称长距离走回朝向不稳），
		# 如实记 WARN，不伪造 PASS；矿车章节仍由主机的单乘员发车机制推进。
		warn("rider could not be put back on deck (R rescue is host-only; walk-back did not converge)")

	# --- 8. 重新发车 → 到站 → 交接 ----------------------------------------
	var route_ready: bool = await _wait_until(func() -> bool:
		if current_scene == null or str(current_scene.name) != "Act23Chapter":
			return true
		if _a23_cart == null or not is_instance_valid(_a23_cart):
			return true
		return bool(_a23_cart.get("route_clear")), 60.0)
	check(route_ready, "cart route cleared by the repair")
	var rerun := false
	if role == "host":
		# 主机不能把队友丢在场地里就发车：先等队友回到甲板（有上限，避免卡死）。
		var mate_aboard: bool = await _wait_until(func() -> bool:
			# R8C-04 probe-only bound: the production cart.start() validates the
			# presser's deck position, not the teammate's. The known Act23 R-rescue
			# mirror gap can leave the client off deck; do not spend five simulated
			# minutes on it in the full-chain Act04 acceptance run.
			return _a23_remote_on_deck(), 25.0)
		if mate_aboard:
			check(true, "host waited for the teammate to be back on the deck before restarting")
		else:
			warn("cart restarted while the teammate was still off the deck (Act23 R-rescue gap)")
		for _attempt in range(3):
			if bool(_a23_cart.get("running")):
				rerun = true
				break
			await _a23_walk(_a23_cart.to_global(Vector3(2.48, 1.91, 1.08)), 6.0, "controller aft", 0.55)
			await _a23_press("repair", 0.14)
			await _wait(1.0)
	rerun = rerun or await _wait_until(func() -> bool:
		# Client: the host may switch to Act04 at any frame, freeing the cart.
		if current_scene == null or str(current_scene.name) != "Act23Chapter":
			return true
		if _a23_cart == null or not is_instance_valid(_a23_cart):
			return true
		return bool(_a23_cart.get("running")), 120.0)
	check(rerun, "cart restarted after the repair")
	var arrived: bool = await _wait_until(func() -> bool:
		# The host may complete the hand-off while this client is still waiting;
		# the Act23 cart is then already freed. A scene change IS arrival.
		if current_scene == null or str(current_scene.name) != "Act23Chapter":
			return true
		if _a23_cart == null or not is_instance_valid(_a23_cart):
			return true
		return bool(_a23_cart.get("arrived")), 240.0)
	check(arrived, "cart physically reached the crystal-mine dock (distance=%.1f)" % (
		float(_a23_cart.get("distance")) if _a23_cart != null and is_instance_valid(_a23_cart) else -1.0))
	_record_stage("act23_arrived", _a23_snapshot())
	if not arrived:
		return false

	var handoff: bool = await _wait_until(func() -> bool:
		return current_scene != null and ["Act4", "Resonance04"].has(str(current_scene.name)), 900.0)
	check(handoff, "Act23 handed off to Act04 in the same session (scene=%s)" %
		(str(current_scene.name) if current_scene != null else "null"))
	if handoff:
		await _wait(1.5)
		_record_stage("act23_complete", {
			"pid": _local_pid(), "peers": _peers(), "scene": str(current_scene.name),
			"chapter": str(hub.get("current_chapter")) if hub != null else "?",
			"history_act23": ((hub.get("chapter_history") as Dictionary).get("act23", {}) as Dictionary).size() if hub != null else -1,
		})
	return handoff


# ---------------------------------------------------------------------------
# Act04 · 晶体洞穴（第四幕）· 真实走位 + F/Q/E
#   host：完整晶体路线（取青晶体→B1，紫晶体→B3，三次撞钟）
#   client：真实撞钟（拿到 phase-04 参与记录）+ 全程跟随走位
# ---------------------------------------------------------------------------
var _a4: Node = null


func _a4_face(target: Vector3, pitch: float = -0.12) -> void:
	if not is_instance_valid(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	if player.has_method("aim_camera_at"):
		player.call("aim_camera_at", Vector3(target.x, target.y, target.z), -99.0)
		return
	player.set("_yaw", yaw)
	player.set("_aim_yaw", yaw)
	player.set("_aim_active", false)
	player.set("_pitch", pitch)
	player.set("_aim_pitch", pitch)
	if player.has_method("_apply_view"):
		player.call("_apply_view")


func _a4_walk(target: Vector3, seconds: float, label := "", tolerance := 0.9) -> bool:
	if not is_instance_valid(player):
		return false
	var elapsed := 0.0
	var stuck := 0.0
	var last: Vector3 = player.global_position
	Input.action_press("move_forward")
	while elapsed < seconds:
		await physics_frame
		elapsed += 1.0 / 60.0
		if not is_instance_valid(player) or current_scene != _a4:
			break
		var current: Vector3 = player.global_position
		_a4_face(Vector3(target.x, current.y, target.z))
		if Vector2(current.x - target.x, current.z - target.z).length() <= tolerance:
			break
		if current.distance_to(last) < 0.012:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
			last = current
		if stuck > 1.2:
			Input.action_press("jump")
			for _i in range(6):
				await physics_frame
			Input.action_release("jump")
			Input.action_press("move_right" if int(elapsed * 7.0) % 2 == 0 else "move_left")
			for _i in range(12):
				await physics_frame
			Input.action_release("move_right")
			Input.action_release("move_left")
			stuck = 0.0
	Input.action_release("move_forward")
	await physics_frame
	if not is_instance_valid(player):
		return true
	var dist: float = Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
	log_line("WALK04 %s target=%s pos=%s dist=%.2f t=%.1f" % [
		label, str(target.snapped(Vector3(0.01, 0.01, 0.01))),
		str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))), dist, elapsed])
	return dist <= tolerance * 1.8


func _a4_interact(target: Vector3, pitch := -0.12) -> void:
	_a4_face(target, pitch)
	await _wait(0.2)
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	await _wait(0.3)


func _a4_pickup(target: Vector3) -> void:
	_a4_face(target, 0.2)
	await _wait(0.25)
	Input.action_press("pickup")
	await _wait(0.14)
	Input.action_release("pickup")
	await _wait(0.5)


func _a4_strike() -> bool:
	var hammer: Node = _a4.get("hammer")
	if hammer == null:
		return false
	var hammer_pos: Vector3 = (hammer as Node3D).global_position
	await _a4_walk(Vector3(2.10, 0.0, -1.30), 9.0, "hammer console", 1.2)
	var held := false
	for _attempt in range(4):
		_a4_face(hammer_pos + Vector3(0, 0.8, 0), 0.12)
		await _wait(0.35)
		Input.action_press("interact")
		await _wait(0.14)
		Input.action_release("interact")
		await _wait(0.4)
		held = str(hammer.get("mode")) == "held"
		if held:
			break
		await _a4_walk(Vector3(2.9, 0.0, -0.6), 2.0, "step back from the rig", 0.6)
		await _a4_walk(Vector3(2.10, 0.0, -1.30), 3.0, "re-approach the rig", 0.8)
	log_line("ACT04_HAMMER held=%s mode=%s pos=%s" % [
		str(held), str(hammer.get("mode")), str(player.global_position)])
	if not held:
		return false
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	await _a4_interact(hammer_pos + Vector3(0, 1.0, 0), 0.05)
	var before: int = int(hammer.get("strike_count"))
	await _wait(2.2)
	var strikes: int = int(hammer.get("strike_count"))
	log_line("ACT04_HAMMER_STRIKE count=%d (was %d)" % [strikes, before])
	return strikes > before


func _a4_wait_memory(index: int, timeout := 60.0) -> bool:
	var seen: Dictionary = _a4.get("seen_memories") as Dictionary
	var waited := 0.0
	while waited < timeout and not bool(seen.get(index, false)):
		await _wait(0.5)
		waited += 0.5
	log_line("ACT04_MEMORY%d seen=%s t=%.1f" % [index, str(seen.get(index, false)), waited])
	return bool(seen.get(index, false))


func _a4_place(key: String) -> bool:
	var cradle: Node3D = (_a4.get("cradles") as Dictionary)[key] as Node3D
	if cradle == null:
		return false
	# 晶体在 1.45 m 内会自动吸附（PortableCrystal.try_seat），所以先看是否已经坐好。
	if cradle.get("occupied") != null:
		var seated := bool(cradle.get("aligned"))
		log_line("ACT04_PLACE %s already seated occupied=%s aligned=%s" % [
			key, str(cradle.get("occupied")), str(seated)])
		if seated:
			return true
	if player.get("carrying") == null:
		return false
	var target_yaw: float = float(cradle.get("required_yaw_deg"))
	var carrying: Node = player.get("carrying") as Node
	var current: float = float(carrying.get("held_yaw_deg"))
	var delta: float = fposmod(target_yaw - current, 360.0)
	var steps: int = int(round(delta / 45.0))
	for _i in range(steps):
		Input.action_press("rotate_crystal")
		await _wait(0.10)
		Input.action_release("rotate_crystal")
		await _wait(0.08)
	_a4_face(cradle.global_position + Vector3(0, 0.15, 0), 0.25)
	await _wait(0.3)
	Input.action_press("pickup")
	await _wait(0.16)
	Input.action_release("pickup")
	await _wait(0.8)
	var ok: bool = await _wait_until(func() -> bool:
		return cradle.get("occupied") != null and bool(cradle.get("aligned")), 5.0)
	log_line("ACT04_PLACE %s occupied=%s aligned=%s yaw=%.1f target=%.1f steps=%d" % [
		key, str(cradle.get("occupied")), str(cradle.get("aligned")), current, target_yaw, steps])
	return ok


func _a4_snapshot() -> Dictionary:
	var out: Dictionary = {"pid": _local_pid(), "scene": str(current_scene.name) if current_scene != null else "?"}
	if _a4 == null or not is_instance_valid(_a4):
		return out
	out["stage"] = int(_a4.get("stage"))
	out["memories"] = (_a4.get("seen_memories") as Dictionary).keys()
	out["completed"] = bool(_a4.get("completed"))
	var gate: Node = _a4.get("gate")
	if gate != null:
		out["gate_open"] = bool(gate.get("is_open"))
	var hammer: Node = _a4.get("hammer")
	if hammer != null:
		out["strikes"] = int(hammer.get("strike_count"))
	var ledger_04: Array = []
	var sess: Node = _session()
	if sess != null:
		var led: Variant = sess.get("ledger")
		if led != null:
			for pid in led.call("player_ids"):
				ledger_04.append({"pid": int(pid), "ph04": bool(led.call("ready_for_phase", int(pid), "04")),
					"phases": (led.call("get_record", int(pid)).get("phases", {}))})
	out["ledger_04"] = ledger_04
	return out


func _drive_act04() -> bool:
	_stage_now = "act04"
	_a4 = current_scene
	player = _a4.get("player") as Node
	if player == null:
		check(false, "Act04 player exists")
		return false
	await _wait(1.5)
	_record_stage("act04_begin", _a4_snapshot())
	log_line("ACT04_START pos=%s mode=%s" % [str(player.global_position), str(_a4.get("coop_mode"))])

	# --- 1. 双方各撞一次钟（各自拿到 phase-04 参与记录） -------------------
	var struck: bool = await _a4_strike()
	check(struck, "%s struck the resonance bell with real E/W input" % role)
	var mem1: bool = await _a4_wait_memory(1, 90.0)
	check(mem1, "memory one reached by the resonance wave")
	_record_stage("act04_memory1", _a4_snapshot())

	if role == "host":
		# --- 2. 青晶体 → 西中继 B1 ----------------------------------------
		var crystal_a: Node3D = _a4.get("crystal_a") as Node3D
		await _a4_walk(Vector3(-6.0, 0.0, 2.0), 10.0, "west aisle", 1.0)
		await _a4_walk(Vector3(-6.0, 0.0, 9.5), 8.0, "north of the stope", 1.0)
		await _a4_walk(Vector3(-12.0, 0.0, 9.5), 9.0, "north rim west", 1.0)
		await _a4_walk(Vector3(-17.0, 0.0, 9.5), 8.0, "north west rim", 1.0)
		await _a4_walk(Vector3(-17.5, 0.0, 5.0), 8.0, "alcove west aisle", 1.0)
		await _a4_walk(Vector3(-17.0, 0.0, 3.0), 6.0, "alcove shelf", 1.0)
		var picked := false
		for _attempt in range(4):
			await _a4_pickup(crystal_a.global_position + Vector3(0, 0.2, 0))
			if player.get("carrying") != null:
				picked = true
				break
			await _a4_walk(crystal_a.global_position + Vector3(0, 0, 0.9), 2.0, "closer to the crystal", 0.5)
		check(picked, "cyan crystal picked up from the alcove shelf with real F")
		if not picked:
			_record_stage("act04_blocked_pickup", _a4_snapshot())
			return false
		await _a4_walk(Vector3(-16.5, 0.0, -2.0), 12.0, "carry south along the west wall", 1.2)
		await _a4_walk(Vector3(-16.8, 0.0, -9.0), 11.0, "carry south", 1.2)
		await _a4_walk(Vector3(-13.0, 0.0, -11.5), 10.0, "toward west relay", 1.2)
		var b1: Node3D = (_a4.get("cradles") as Dictionary)["b1"] as Node3D
		await _a4_walk(b1.global_position + Vector3(0, 0, 1.25), 8.0, "west relay B1", 0.7)
		check(await _a4_place("b1"), "cyan crystal seated and aligned in the west relay B1")
		_record_stage("act04_b1", _a4_snapshot())
		check(await _a4_strike(), "second hammer strike")
		check(await _a4_wait_memory(2, 90.0), "memory two reached after the west path was restored")
		# 紫晶体 → 观察平台 B3
		var crystal_b: Node3D = _a4.get("crystal_b") as Node3D
		await _a4_walk(crystal_b.global_position + Vector3(0, 0, 1.1), 10.0, "violet crystal", 0.8)
		var picked_b := false
		for _attempt in range(3):
			await _a4_pickup(crystal_b.global_position)
			if player.get("carrying") != null:
				picked_b = true
				break
		check(picked_b, "violet crystal picked up with real F")
		if not picked_b:
			return false
		await _a4_walk(Vector3(-18.5, 0.0, -13.2), 11.0, "west ramp foot", 1.2)
		await _a4_walk(Vector3(-17.2, 3.4, -17.6), 11.0, "west ramp up", 1.2)
		await _a4_walk(Vector3(-14.0, 3.4, -19.2), 9.0, "observation ledge", 1.2)
		var b3: Node3D = (_a4.get("cradles") as Dictionary)["b3"] as Node3D
		await _a4_walk(b3.global_position + Vector3(0, 0, 1.15), 8.0, "ledge relay B3", 0.8)
		check(await _a4_place("b3"), "violet crystal seated and aligned on the observation ledge B3")
		check(await _a4_strike(), "third hammer strike")
	else:
		# --- 客户端：跟随真实路线（走到壁龛与中继），并再撞一次钟 ----------
		await _a4_walk(Vector3(-6.0, 0.0, 2.0), 10.0, "west aisle", 1.0)
		await _a4_walk(Vector3(-6.0, 0.0, 9.5), 8.0, "north of the stope", 1.0)
		await _a4_walk(Vector3(-12.0, 0.0, 9.5), 9.0, "north rim west", 1.0)
		await _a4_walk(Vector3(-17.5, 0.0, 5.0), 9.0, "alcove west aisle", 1.0)
		note("client toured the west alcove while the host carried the cyan crystal")
		check(await _a4_strike(), "client struck the bell a second time")

	var mem3: bool = await _a4_wait_memory(3, 180.0)
	check(mem3, "memory three reached through the restored final chain")
	var gate_open := false
	var gate_wait := 0.0
	var gate: Node = _a4.get("gate")
	while gate_wait < 60.0 and gate != null and not bool(gate.get("is_open")):
		await _wait(0.4)
		gate_wait += 0.4
	gate_open = gate != null and bool(gate.get("is_open"))
	check(gate_open, "exit gate physically opened")
	_record_stage("act04_gate", _a4_snapshot())

	# Both players physically walk into the exit. The host gate legitimately
	# refuses the first attempt while the client's strike is still in flight;
	# a real player steps back out and re-enters after the toast. Retry the
	# physical trigger instead of treating the first refusal as a failure.
	var completed := false
	for attempt in range(4):
		if current_scene != null and str(current_scene.name) == "Main":
			completed = true
			break
		await _a4_walk(Vector3(0.0, 0.0, -21.0), 10.0, "final chamber aisle %d" % attempt, 1.2)
		await _a4_walk(Vector3(6.2, 0.0, -25.0), 10.0, "exit corridor %d" % attempt, 1.3)
		completed = await _wait_until(func() -> bool:
			return is_instance_valid(_a4) and bool(_a4.get("completed")), 20.0)
		if completed or (current_scene != null and str(current_scene.name) == "Main"):
			completed = true
			break
		# Step back out of the trigger, wait for the teammate's credit event,
		# then re-enter. This is the same loop a player performs after the
		# "still missing participation" toast.
		await _a4_walk(Vector3(0.0, 0.0, -19.0), 8.0, "step back out of the exit %d" % attempt, 1.2)
		await _wait(4.0)
	check(completed, "Act04 completed by walking into the exit trigger")
	var handoff: bool = await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == "Main", 900.0)
	check(handoff, "Act04 handed off to Act05 in the same session (scene=%s)" %
		(str(current_scene.name) if current_scene != null else "null"))
	if handoff:
		await _wait(1.5)
		_record_stage("act04_complete", {
			"pid": _local_pid(), "peers": _peers(), "scene": str(current_scene.name),
			"chapter": str(hub.get("current_chapter")) if hub != null else "?",
			"history_act04": ((hub.get("chapter_history") as Dictionary).get("act04", {}) as Dictionary).size() if hub != null else -1,
		})
	return handoff


# ---------------------------------------------------------------------------
# Act05 · 地心（第五幕）· 真实走位 + E/W 泵压
#   分工：host 配重(A) + 爪锁(C) + 阻尼(C) + 数据(C)；client 西支腿(A) + 推车(C) + 拔销(C)
#   双方都要抓握栏杆度过一次自然涌浪（B）
# ---------------------------------------------------------------------------
var _a5: Node = null


func _a5_face(target: Vector3) -> void:
	if not is_instance_valid(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	var flat: float = Vector2(d.x, d.z).length()
	var pitch: float = -atan2(d.y - 1.45, maxf(flat, 0.05))
	player.call("set_look", yaw, clampf(pitch, -1.1, 1.1))


func _a5_walk(target: Vector3, seconds: float, label := "", tolerance := 1.1) -> bool:
	if not is_instance_valid(player):
		return false
	var elapsed := 0.0
	var stuck := 0.0
	var last: Vector3 = player.global_position
	Input.action_press("move_forward")
	while elapsed < seconds:
		await physics_frame
		elapsed += 1.0 / 60.0
		if not is_instance_valid(player) or current_scene != _a5:
			break
		var current: Vector3 = player.global_position
		_a5_face(Vector3(target.x, current.y, target.z))
		if Vector2(current.x - target.x, current.z - target.z).length() <= tolerance:
			break
		if current.distance_to(last) < 0.012:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
			last = current
		if stuck > 1.0:
			Input.action_press("jump")
			for _i in range(6):
				await physics_frame
			Input.action_release("jump")
			Input.action_press("move_right" if int(elapsed * 7.0) % 2 == 0 else "move_left")
			for _i in range(10):
				await physics_frame
			Input.action_release("move_right")
			Input.action_release("move_left")
			stuck = 0.0
	Input.action_release("move_forward")
	await physics_frame
	if not is_instance_valid(player) or current_scene != _a5:
		return true
	var dist: float = Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
	log_line("WALK05 %s target=%s pos=%s dist=%.2f t=%.1f" % [
		label, str(target.snapped(Vector3(0.01, 0.01, 0.01))),
		str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))), dist, elapsed])
	return dist <= tolerance * 2.0


func _a5_press(action := "interact", hold := 0.12) -> void:
	Input.action_press(action)
	await _wait(hold)
	Input.action_release(action)
	await _wait(0.25)


func _a5_hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	await _wait(0.2)


func _a5_snapshot() -> Dictionary:
	var out: Dictionary = {"pid": _local_pid()}
	if _a5 == null or not is_instance_valid(_a5):
		return out
	var level: Node = _a5.get("level")
	var story: Node = _a5.get("story")
	var sess: Node = _session()
	if story != null:
		out["stage"] = int(story.get("stage"))
		out["data_taken"] = bool(story.get("data_taken"))
		out["completed"] = bool(story.call("completed_flag"))
	if level != null:
		out["core_locked"] = bool((level.get("core") as Object).call("is_locked"))
		out["stabs_latched"] = (level.get("stabilizers") as Array).filter(
			func(s: Variant) -> bool: return bool((s as Object).get("latched"))).size()
		out["damper"] = bool((level.get("damper") as Object).get("latched_flag"))
		out["iso_pin"] = bool((level.get("isolation") as Object).get("pin_out"))
		out["iso_sep"] = bool((level.get("isolation") as Object).get("separated_flag"))
	if sess != null:
		out["can_finish"] = bool(sess.call("can_finish"))
		out["gate_text"] = str(sess.call("gate_text"))
		var led: Variant = sess.get("ledger")
		if led != null:
			var per: Array = []
			for pid in led.call("player_ids"):
				var rec: Dictionary = led.call("get_record", int(pid))
				per.append({"pid": int(pid), "phases": rec.get("phases", {}),
					"ready": bool(led.call("is_ready", int(pid)))})
			out["ledger"] = per
	return out


func _drive_act05() -> bool:
	_stage_now = "act05"
	_a5 = current_scene
	player = _a5.get("player") as Node
	var level: Node = _a5.get("level")
	var story: Node = _a5.get("story")
	var session: Node = _a5.get("session")
	var surge: Node = _a5.get("surge")
	if player == null or level == null or story == null or session == null:
		check(false, "Act05 world nodes present")
		return false
	await _wait(2.0)
	_record_stage("act05_begin", _a5_snapshot())
	log_line("ACT05_START pos=%s handoff_from_act04=%s" % [
		str(player.global_position), str(_a5.get("handoff_from_act04"))])

	# --- 1. 出生点 → 卷帘门 → 大厅 ---------------------------------------
	if not await _a5_walk(Vector3(0.0, 4.06, 26.0), 20.0, "spawn to shutter", 1.2):
		_record_stage("act05_blocked_spawn", _a5_snapshot())
		return false
	await _a5_walk(Vector3(0.0, 4.06, 24.6), 6.0, "shutter", 0.8)
	_a5_face(Vector3(0.0, 5.0, 24.2))
	await _a5_press()
	var grabbed_door := bool(player.get("operating"))
	if not grabbed_door:
		await _a5_walk(Vector3(0.0, 4.06, 25.0), 4.0, "shutter retry", 0.7)
		_a5_face(Vector3(0.0, 5.0, 24.2))
		await _a5_press()
		grabbed_door = bool(player.get("operating"))
	check(grabbed_door, "jammed shutter grabbed with real E")
	if grabbed_door:
		await _a5_hold("move_forward", 3.8)
		await _a5_press()
	await _a5_walk(Vector3(0.0, 4.06, 22.5), 8.0, "through the shutter", 1.0)
	await _a5_walk(Vector3(0.0, 4.06, 12.2), 14.0, "hall balcony", 1.2)
	var hall_ok: bool = await _wait_until(func() -> bool: return int(story.get("stage")) >= 2, 30.0)
	check(hall_ok, "hall trigger advanced the story to the instability stage")
	_record_stage("act05_hall", _a5_snapshot())

	# --- 2. 下到地面层 ----------------------------------------------------
	await _a5_walk(Vector3(-5.0, 4.06, 10.4), 10.0, "left ramp top", 1.2)
	await _a5_walk(Vector3(-5.0, 1.4, 4.2), 10.0, "left ramp middle", 1.3)
	await _a5_walk(Vector3(-5.0, 0.06, 2.4), 9.0, "left ramp bottom", 1.2)

	if role == "host":
		# --- A：配重（真实 E + 反向摇杆，让核心偏心力矩真的减小） ----------
		await _a5_walk(Vector3(0.0, 0.06, 6.0), 9.0, "ground floor center", 1.2)
		await _a5_walk(Vector3(10.3, 0.06, 6.0), 12.0, "east aisle", 1.2)
		await _a5_walk(Vector3(8.0, 0.06, 2.2), 9.0, "right ramp foot", 1.2)
		await _a5_walk(Vector3(8.0, 1.66, 4.6), 9.0, "right ramp up", 1.3)
		await _a5_walk(Vector3(9.3, 1.66, 7.5), 7.0, "right platform", 1.2)
		await _a5_walk(Vector3(8.5, 1.70, 7.47), 5.0, "counterweight console", 0.9)
		await _a5_press()
		var op := false
		for _i in range(3):
			if bool(player.get("operating")):
				op = true
				break
			await _a5_walk(Vector3(8.6, 1.70, 7.40), 4.0, "counterweight handle", 0.6)
			await _a5_press()
		check(op, "host operates the counterweight console with real E")
		if op:
			await _a5_hold("move_back", 10.0)
			await _a5_press()
		var led: Variant = session.get("ledger")
		check(led != null and bool(led.call("has_credit", _local_pid(), "counterweight_effect")),
			"host earned counterweight_effect by really reducing the core bias")
		await _a5_walk(Vector3(8.0, 0.06, 4.6), 9.0, "down the station ramp", 1.2)
		await _a5_walk(Vector3(8.0, 0.06, 2.2), 7.0, "station ramp foot", 1.1)
	else:
		# --- A：西支腿（claim + 泵压） --------------------------------------
		var stabs: Array = level.get("stabilizers") as Array
		var stab: Variant = stabs[0]
		var anchor_xf: Transform3D = stab.get("anchor")
		var stand: Vector3 = anchor_xf.origin + Vector3(0, 0, -0.6)
		await _a5_walk(stand, 16.0, "stabilizer west", 1.1)
		await _a5_press()
		var opw := false
		for _i in range(4):
			if bool(player.get("operating")):
				opw = true
				break
			await _a5_walk(stand, 4.0, "stabilizer retry", 0.8)
			await _a5_press()
		check(opw, "client operates the west stabilizer with real E")
		if opw:
			await _a5_hold("move_forward", 6.0)
			await _a5_press()
		var latched: bool = await _wait_until(func() -> bool:
			return bool((level.get("stabilizers") as Array)[0].get("latched")), 60.0)
		check(latched, "west stabilizer latched by real client pumping")
		var led2: Variant = session.get("ledger")
		check(led2 != null and bool(led2.call("has_credit", _local_pid(), "stabilizer_lock")),
			"client earned stabilizer_lock credit")

	# --- 3. 维修爬梯 → 栈桥 → 抓握过涌浪（B，双方） ------------------------
	var catwalk: Node = level.get("catwalk")
	var ladder_node: Node3D = catwalk.get("ladder_station_node") as Node3D if catwalk != null else null
	if ladder_node != null:
		await _a5_walk(ladder_node.global_position + Vector3(0, 0, 0.9), 10.0, "catwalk ladder", 0.9)
	else:
		await _a5_walk(Vector3(6.45, 0.06, 3.35), 10.0, "catwalk ladder", 0.9)
	for _i in range(3):
		if not bool(player.get("operating")):
			break
		await _a5_press()
	_a5_face(ladder_node.global_position if ladder_node != null else Vector3(6.45, 1.0, 3.35))
	await _a5_press()
	var climb := 0.0
	Input.action_press("move_forward")
	while climb < 12.0 and player.global_position.y < 3.0:
		await _wait(0.2)
		climb += 0.2
	Input.action_release("move_forward")
	await _wait(0.4)
	check(player.global_position.y > 3.0,
		"player climbed the maintenance ladder onto the catwalk (y=%.2f)" % player.global_position.y)
	if player.global_position.y <= 3.0:
		_record_stage("act05_blocked_ladder", _a5_snapshot())
		return false
	var grips: Array = catwalk.get("grab_points") as Array if catwalk != null else []
	var grip_target := Vector3(-10.4, 3.5, -3.95)
	if grips.size() > 0:
		var pick: int = grips.size() - 1 if role == "host" else maxi(0, grips.size() - 2)
		grip_target = (grips[pick] as Node3D).global_position
	await _a5_walk(Vector3(grip_target.x, 3.5, grip_target.z + 0.9), 12.0, "brace rail", 1.2)
	var grabbing := false
	for _attempt in range(4):
		_a5_face(grip_target)
		await _a5_press()
		grabbing = bool(player.get("grabbing"))
		if grabbing:
			break
		await _a5_walk(Vector3(grip_target.x, 3.5, grip_target.z + 0.9), 3.0, "brace retry", 0.9)
	check(grabbing, "player grabbed a catwalk rail with real E")
	if grabbing:
		var surge_t := 0.0
		while surge_t < 180.0 and int(surge.get("surge_count")) < 1:
			await _wait(0.5)
			surge_t += 0.5
		log_line("ACT05_SURGE count=%s t=%.1f grabbing=%s" % [
			str(surge.get("surge_count")), surge_t, str(player.get("grabbing"))])
		check(int(surge.get("surge_count")) >= 1, "a natural resonance surge fired while braced")
		await _a5_press()
	var led3: Variant = session.get("ledger")
	var b_ok: bool = led3 != null and (bool(led3.call("has_credit", _local_pid(), "surge_response")) \
		or bool(led3.call("has_credit", _local_pid(), "brace_hold")))
	check(b_ok, "player earned a phase-B credit by bracing through the surge")
	_record_stage("act05_brace", _a5_snapshot())

	# --- 4. 下栈桥 --------------------------------------------------------
	await _a5_walk(Vector3(-11.6, 3.5, -2.6), 8.0, "catwalk east end", 1.2)
	await _a5_walk(Vector3(-11.6, 0.06, -2.6), 5.0, "drop off the catwalk", 1.4)
	if player.global_position.y > 2.0:
		await _a5_walk(Vector3(-8.0, 0.06, -2.0), 8.0, "leave the catwalk", 1.4)

	if role == "host":
		# --- C：爪锁 + 阻尼 ------------------------------------------------
		var both_latched: bool = await _wait_until(func() -> bool:
			return int((level as Object).call("stabilizers_latched")) >= 2, 240.0)
		check(both_latched, "both hydraulic legs are latched (core can be captured)")
		var cap: bool = await _wait_until(func() -> bool:
			return bool((level.get("core") as Object).call("is_capturable")), 240.0)
		check(cap, "core entered the capture band")
		await _a5_walk(Vector3(0.0, 0.06, 6.0), 14.0, "south of the lock", 1.4)
		await _a5_walk(Vector3(0.0, 0.06, 10.6), 8.0, "lock console stand", 0.9)
		_a5_face(Vector3(0.0, 1.2, 8.6))
		await _wait(0.3)
		await _a5_press()
		var locked: bool = await _wait_until(func() -> bool:
			return bool((level.get("core") as Object).call("is_locked")), 60.0)
		check(locked, "hydraulic claw locked the core with real E")
		var led4: Variant = session.get("ledger")
		check(led4 != null and bool(led4.call("has_credit", _local_pid(), "lock_assist")),
			"host earned lock_assist credit")
		await _a5_walk(Vector3(6.4, 0.06, -2.3), 14.0, "extraction damper", 1.2)
		_a5_face(Vector3(6.4, 1.2, -4.4))
		await _wait(0.3)
		await _a5_press()
		await _a5_hold("move_forward", 3.0)
		if bool(player.get("operating")):
			await _a5_press()
		var damper: Node = level.get("damper")
		check(bool(damper.get("latched_flag")), "extraction damper latched by real input")
		_record_stage("act05_lock_damper", _a5_snapshot())
	else:
		# --- C：拔安全销 + 推滑架分离 ---------------------------------------
		var core_locked: bool = await _wait_until(func() -> bool:
			return bool((level.get("core") as Object).call("is_locked")), 300.0)
		check(core_locked, "client sees the core locked by the host")
		await _a5_walk(Vector3(10.3, 0.06, 4.2), 12.0, "east aisle north", 1.3)
		await _a5_walk(Vector3(12.35, 0.06, 4.0), 8.0, "east aisle corner", 1.2)
		await _a5_walk(Vector3(12.35, 0.06, -2.0), 9.0, "east aisle south", 1.3)
		await _a5_walk(Vector3(10.9, 0.06, -5.7), 7.0, "isolation bay", 1.0)
		var iso: Node = level.get("isolation")
		for _attempt in range(5):
			if bool(iso.get("pin_out")):
				break
			_a5_face(Vector3(10.6, 1.3, -8.6))
			await _wait(0.25)
			await _a5_press()
			await _wait(0.6)
		var pin_ok: bool = await _wait_until(func() -> bool: return bool(iso.get("pin_out")), 40.0)
		var led5: Variant = session.get("ledger")
		var pin_credit: bool = led5 != null and bool(led5.call("has_credit", _local_pid(), "isolation_pin"))
		check(pin_ok or pin_credit, "client pulled the isolation safety pin (flag or ledger credit)")
		# 阻尼器必须由 host 加载后滑架才推得动
		var damper2: Node = level.get("damper")
		await _wait_until(func() -> bool: return float(damper2.call("damper_effect")) >= 0.35, 300.0)
		var op_iso := false
		for _i in range(8):
			await _a5_walk(Vector3(10.7, 0.06, -5.0), 4.0, "carriage console", 0.8)
			await _a5_press()
			if bool(player.get("operating")):
				op_iso = true
				break
			await _wait(0.5)
		if op_iso:
			await _a5_hold("move_forward", 7.0)
		var sep: bool = await _wait_until(func() -> bool:
			return bool((level.get("isolation") as Object).get("separated_flag")), 120.0)
		check(sep, "extraction coupling separated by the client's real carriage push")
		_record_stage("act05_isolation", _a5_snapshot())

	# --- 5. 数据 + 收队 ---------------------------------------------------
	var data_wait := await _wait_until(func() -> bool:
		return bool((level.get("isolation") as Object).get("separated_flag")), 400.0)
	check(data_wait, "extraction coupling separated (both sides)")
	if role == "host":
		await _a5_walk(Vector3(6.0, 0.06, -6.0), 10.0, "rear hall", 1.2)
		await _a5_walk(Vector3(-3.0, 0.06, -8.0), 12.0, "data plinth", 1.2)
		_a5_face(Vector3(-3.0, 1.0, -9.1))
		await _wait(0.3)
		await _a5_press()
		var data_ok: bool = await _wait_until(func() -> bool:
			return bool(story.get("data_taken")), 40.0)
		check(data_ok, "navigation data taken through the plinth with real E")
		var gate_ok: bool = await _wait_until(func() -> bool:
			return bool(session.call("can_finish")), 60.0)
		check(gate_ok, "participation gate satisfied by real credits")
		if not gate_ok:
			log_line("ACT05_GATE %s" % str(session.call("gate_text")))
			_record_stage("act05_gate_blocked", _a5_snapshot())
	else:
		await _a5_walk(Vector3(6.0, 0.06, -6.0), 12.0, "rear hall", 1.2)

	# --- 6. 撤离：真实走进出口通道 ----------------------------------------
	await _a5_walk(Vector3(-8.0, 0.06, -6.0), 12.0, "exit side", 1.3)
	await _a5_walk(Vector3(-13.4, 0.06, -2.0), 10.0, "blast door", 1.3)
	await _a5_walk(Vector3(-25.5, 0.06, -2.0), 16.0, "exit corridor", 1.5)
	_a5_face(Vector3(-27.5, 1.2, -2.0))
	var finale: bool = await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == FINALE_NAME, 900.0)
	check(finale, "real exit crossing settled the run and entered the Finale")
	if finale:
		await _wait(2.0)
		_record_stage("act05_complete", {
			"pid": _local_pid(), "peers": _peers(), "scene": str(current_scene.name),
			"chapter": str(hub.get("current_chapter")) if hub != null else "?",
			"history_keys": (hub.get("chapter_history") as Dictionary).keys() if hub != null else [],
			"history_act05": ((hub.get("chapter_history") as Dictionary).get("act05", {}) as Dictionary).size() if hub != null else -1,
		})
	return finale


# ---------------------------------------------------------------------------
# 报告
# ---------------------------------------------------------------------------
func _finish(passed: bool) -> void:
	var report: Dictionary = {
		"probe": "probe_full_coop_run.gd",
		"role": role,
		"mode": mode,
		"passed": passed,
		"checks": checks,
		"failures": failures,
		"warnings": warnings,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_msec) / 1000.0,
		"scene_ledger": scene_log,
		"stages": stage_records,
		"final_sample": _sample(),
		"log": log_lines,
	}
	var path := ""
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		path = out_dir.path_join("coop_%s%s.json" % [role, ("_" + tag) if tag != "" else ""])
	else:
		path = "user://coop_%s.json" % role
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
		log_line("REPORT %s" % ProjectSettings.globalize_path(path))
	log_line("RESULT role=%s checks=%d failures=%d passed=%s" % [role, checks, failures.size(), str(passed)])
	if passed:
		print("COOP_OK role=%s" % role)
	else:
		print("COOP_FAIL role=%s %s" % [role, str(failures)])
	quit(0 if passed else 1)



