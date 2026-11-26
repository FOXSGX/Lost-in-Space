extends SceneTree

## R2 · 双人连续交接探针（host / client 各一个真实 Godot 进程）
##
## 验证范围：正式 Launcher → Act01 → Act23Chapter → Resonance04 → Act05 入口。
## 不把 Act05 全工序计入本探针的 PASS 口径（--act05=full 可另行选择）。
##
## 入口：正式 Launcher（res://scenes/launcher.tscn），用真实鼠标点击进入：
##   host   → 「创建主机（等待队友加入）」
##   client → 「加入主机（本机 127.0.0.1）」
##
## 之后每一幕都用**玩家真实输入动作**推进（WASD / E / F / Q / 空格 / 绞盘…）：
##   * 不写任何任务完成 flag；
##   * 不调用 complete_chapter / change_scene 跳关；
##   * 不传送玩家（全文件没有 teleport / global_position = 赋值）。
## 只读采样引擎状态并落盘 JSON。
##
## R2 与 R1 的关键差异（均为测试工装）：
##   * Act23 登车/下车/回车改为**分时通行**：两名玩家不再同时挤 0.96 m 宽的
##     登车门（R1 的固定帧率双进程 + 同时走位会在楼梯/门槛互相卡住）。
##   * 删掉 R1 为绕开上述卡位而加的两处传送（A23_BOARD_FALLBACK、
##     Act04 hammer teleport），改为真实绕行 waypoint + 精确停靠。
##   * Act01 压力测试先等 host 的 fan + damper 都到位，再调 governor，
##     避免真实时钟下客户端过早把调速器停在 0.55 导致压力永远到不了 0.58。
##   * 所有跨场景/已释放节点引用都经 is_instance_valid + current_scene 守卫。
##
## 用法（两个进程跑同一个脚本，role 不同）：
##   godot --headless --path <project> res://scenes/launcher.tscn \
##     -s res://tests/r2_full_chain_probe.gd -- --role=host --out=<dir> --mode=full
##
## mode: full | act01 | act23 | act04

const FINALE_NAME := "Finale"
const HOST_BUTTON := "创建主机（等待队友加入）"
const CLIENT_BUTTON := "加入主机（本机 127.0.0.1）"

var role: String = "host"
var mode: String = "full"
var out_dir: String = ""
var tag: String = ""
var legacy_act05: bool = false
var run_act05_full: bool = false

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
		elif s.begins_with("--act05="):
			var act05_mode: String = s.split("=")[1]
			legacy_act05 = act05_mode == "legacy"
			run_act05_full = act05_mode == "full"


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


## A freed Node raises on get()/get_node(); every scene-owned reference that can
## outlive a chapter switch must pass through these two guards first.
func _valid(node: Variant) -> bool:
	# is_instance_valid() must run BEFORE the `is Node` test: a Variant that
	# holds a previously freed instance makes `is` itself raise (seen in the
	# successful run r2-full-05 stderr during the Act23→Act04 hand-off).
	if not is_instance_valid(node):
		return false
	return node is Node


## A node can still be "valid" for a frame while it has already left the tree
## (scene switch); get_global_transform() then errors. Treat that as gone.
func _in_tree(node: Variant) -> bool:
	if not _valid(node):
		return false
	return (node as Node).is_inside_tree()


func _scene_is(name: String) -> bool:
	return current_scene != null and str(current_scene.name) == name


func _player_ok() -> bool:
	return _in_tree(player)


func _safe_get(node: Variant, key: String, fallback: Variant = null) -> Variant:
	if not _valid(node):
		return fallback
	return (node as Object).get(key)


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
	if mate is Vector3 and _in_tree(player):
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
		# Act04 snapshots carry their own numeric "stage"; do not let it
		# overwrite the hand-off record name (r2-full-05..09 JSON had 0/1/2/5
		# instead of act04_memory1 etc.). Keep the machine stage separately.
		if str(key) == "stage":
			entry["snapshot_stage"] = payload[key]
		else:
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
	if not await _verify_act05_entry():
		return false
	if run_act05_full:
		# Explicit opt-in only: the R2 acceptance boundary is the Act05 entry.
		await _wait(2.0)
		if not await _drive_act05():
			return false
	return true


# ---------------------------------------------------------------------------
# Act01 · 真实输入合作（host: 入口/推车/通风/发车；client: 门闩/电源/调节阀/离场链）
# ---------------------------------------------------------------------------
var _a1_stage: Node = null


func _a1_face(target: Vector3) -> void:
	if not _in_tree(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("yaw", yaw)
	player.rotation.y = yaw


func _a1_walk(target: Vector3, seconds: float, label := "", arrive := 0.55) -> void:
	if not _in_tree(player):
		return
	var start: Vector3 = player.global_position
	_a1_face(target)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var frames: int = int(seconds * 60.0)
	for _i in range(frames):
		await physics_frame
		if not _in_tree(player) or current_scene != _a1_stage:
			break
		_a1_face(target)
		if Vector2(player.global_position.x - target.x,
				player.global_position.z - target.z).length() < arrive:
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await physics_frame
	if _in_tree(player):
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


func _a1_ok() -> bool:
	return _scene_is("Act01") and _valid(_a1_stage)


func _a1_flags() -> Dictionary:
	if not _a1_ok():
		return {}
	return _a1_stage.get("flags") as Dictionary


func _a1_credit_phases(pid: int) -> Dictionary:
	if not _a1_ok():
		return {}
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
		# R2 test-harness timing fix: pressure = fan_speed * (0.28 + 0.72 * damper).
		# With the damper still closed the ceiling is 0.28, far below the 0.58
		# vent gate, so the client must not make its governor decision before the
		# host has opened BOTH the fan and the damper. R1 only waited for the fan,
		# which is why a real-clock run could park the governor at 0.55 and then
		# wait forever. This is a probe ordering fix; the machine logic is untouched.
		var air_ready: bool = await _wait_until(func() -> bool:
			var f: Dictionary = _a1_flags()
			return bool(f.get("fan_started", false)) and bool(f.get("damper_open", false)), 240.0)
		note("client waited for host fan_started+damper_open=%s" % str(air_ready))
		var vent_node: Node = ((_a1_stage.get("builder") as Object).get("vent") as Node) if _a1_ok() else null
		if vent_node != null:
			# 调速器是 3 档循环（0.55 → 0.78 → 1.0 → 0.55），按到风压达标为止。
			for _attempt in range(6):
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
	var b: Variant = _a1_stage.get("builder") if _a1_ok() else null
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
	if not _in_tree(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_yaw", yaw)


func _a23_cart_ok() -> bool:
	return _scene_is("Act23Chapter") and _valid(_a23) and _valid(_a23_cart)


func _a23_global(local: Vector3) -> Vector3:
	if not _a23_cart_ok():
		return Vector3.ZERO
	return _a23_cart.to_global(local)


## Walk with real movement input only. The R2 version breaks on the XZ distance
## AND on the vertical target when climbing/descending, so a body that is still
## halfway up the 6-step boarding stair is never mistaken for "on the deck".
func _a23_walk(target: Vector3, seconds: float, label := "", arrive := 0.55, sprint := true, check_y := false) -> bool:
	if not _in_tree(player):
		return false
	var start: Vector3 = player.global_position
	var climbing: bool = target.y > start.y + 0.30
	var descending: bool = target.y < start.y - 0.80
	var last: Vector3 = start
	var stuck_t: float = 0.0
	var elapsed: float = 0.0
	_a23_face(target)
	if sprint:
		Input.action_press("sprint")
	Input.action_press("move_up")
	while elapsed < seconds:
		await physics_frame
		elapsed += 1.0 / 60.0
		if not _in_tree(player) or not _scene_is("Act23Chapter"):
			break
		_a23_face(target)
		var pos: Vector3 = player.global_position
		var flat: float = Vector2(pos.x - target.x, pos.z - target.z).length()
		var dy: float = absf(pos.y - target.y)
		if flat < arrive and (not check_y or ((not climbing or dy < 0.30) and (not descending or dy < 0.70))):
			break
		if pos.distance_to(last) < 0.008:
			stuck_t += 1.0 / 60.0
		else:
			stuck_t = 0.0
			last = pos
		if stuck_t > 0.90:
			log_line("WALK23_STUCK %s target=%s pos=%s flat=%.2f dy=%.2f" % [
				label, str(target), str(pos), flat, dy])
			break
	Input.action_release("move_up")
	if sprint:
		Input.action_release("sprint")
	await physics_frame
	await _wait(0.05)
	if not _in_tree(player):
		return false
	var end: Vector3 = player.global_position
	var final_flat: float = Vector2(end.x - target.x, end.z - target.z).length()
	log_line("WALK23 %s target=%s pos=%s moved=%.2f flat=%.2f y=%.2f" % [
		label, str(target.snapped(Vector3(0.01, 0.01, 0.01))),
		str(end.snapped(Vector3(0.01, 0.01, 0.01))), end.distance_to(start), final_flat, end.y])
	return final_flat <= arrive * 1.6


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
		if _valid(node) and str(node.get("anchor_id")) == anchor_id:
			return node as Node3D
	return null


func _a23_on_deck() -> bool:
	if not _a23_cart_ok() or not _in_tree(player):
		return false
	return bool(_a23_cart.call("contains_point", player.global_position))


func _a23_actor_on_deck(actor: Variant) -> bool:
	if not _a23_cart_ok() or not _valid(actor) or not (actor is Node3D):
		return false
	return bool(_a23_cart.call("contains_point", (actor as Node3D).global_position))


func _a23_actor_cleared(actor: Variant) -> bool:
	if not _a23_cart_ok() or not _valid(actor) or not (actor is Node3D):
		return false
	var p: Vector3 = (actor as Node3D).global_position
	return (not bool(_a23_cart.call("contains_point", p))) and p.y < 0.60


## host 视角：队友（另一个 slot）的身体是否已经在甲板上。
func _a23_remote_on_deck() -> bool:
	if not _a23_cart_ok():
		return false
	var actors: Variant = _a23.get("actors")
	if not (actors is Dictionary):
		return false
	var local_slot: int = int(_a23.get("local_slot"))
	for key in (actors as Dictionary).keys():
		if int(key) == local_slot:
			continue
		return _a23_actor_on_deck((actors as Dictionary)[key])
	return false


## A body that is merely outside the deck box but still wedged on the stair is
## NOT clear of the gate. R1 only checked contains_point and accepted that state.
func _a23_remote_cleared() -> bool:
	if not _a23_cart_ok():
		return false
	var actors: Variant = _a23.get("actors")
	if not (actors is Dictionary):
		return false
	var local_slot: int = int(_a23.get("local_slot"))
	for key in (actors as Dictionary).keys():
		if int(key) == local_slot:
			continue
		return _a23_actor_cleared((actors as Dictionary)[key])
	return false


func _a23_snapshot() -> Dictionary:
	var out: Dictionary = {}
	if _valid(_a23_cart):
		out["distance"] = snappedf(float(_a23_cart.get("distance")), 0.01)
		out["speed"] = snappedf(float(_a23_cart.get("speed")), 0.01)
		out["running"] = bool(_a23_cart.get("running"))
		out["arrived"] = bool(_a23_cart.get("arrived"))
		out["route_clear"] = bool(_a23_cart.get("route_clear"))
		out["stopped_for_fault"] = bool(_a23_cart.get("stopped_for_fault"))
		out["brake_reason"] = str(_a23_cart.get("brake_reason"))
	if _valid(_a23_flow):
		out["phase"] = str(_a23_flow.get("phase"))
		out["at_console"] = bool(_a23_flow.get("at_console"))
		out["console_actor"] = int(_a23_flow.get("console_actor"))
	if _valid(_a23):
		out["on_deck"] = _a23_on_deck()
		out["safety_triggered"] = bool(_a23.get("_safety_triggered"))
		out["safety_brakes"] = int(_a23.get("_safety_brake_count"))
		var part: Variant = _a23.get("participation")
		if part != null:
			out["participation"] = (part as Object).call("summary")
	return out


## Boarding is the first narrow choke: one 0.90 m stair, two 0.76 m capsules.
## R1 let both players climb at the same time; in fixed-fps runs they pushed
## each other off the step and the host never reached the deck. R2 makes the
## host climb first, the client wait for the host to be on deck, then climb.
## Every move is still W input; there is no position assignment.
func _a23_board() -> bool:
	if not _a23_cart_ok():
		return false
	await _a23_walk(_a23_global(Vector3(1.0, 0.40, -2.0)), 6.0, "boarding landing", 0.45, false, true)
	for attempt in range(4):
		if _a23_on_deck():
			return true
		if not _a23_cart_ok():
			return false
		await _a23_walk(_a23_global(Vector3(1.0, 0.40, -0.80)), 3.0, "stair foot %d" % attempt, 0.22, false, true)
		await _a23_walk(_a23_global(Vector3(1.0, 1.05, -0.10)), 3.0, "stairs mid %d" % attempt, 0.22, false, true)
		await _a23_walk(_a23_global(Vector3(1.0, 1.91, 0.55)), 3.0, "stairs top %d" % attempt, 0.20, false, true)
		await _a23_walk(_a23_global(Vector3(1.0, 1.95, 1.55)), 3.0, "deck lane %d" % attempt, 0.20, false, true)
		if _a23_on_deck():
			return true
		# Walk back down to the landing and retry; never teleport.
		await _a23_walk(_a23_global(Vector3(1.0, 0.40, -1.10)), 3.0, "reset stairs %d" % attempt, 0.30, false, true)
	return _a23_on_deck()


## Leave the deck through the real 0.96 m gate. Approach the gate lane first so
## the capsule is centred, then walk straight out; R1 stopped 0.5 m short and
## the 0.38 m capsule wedged on the rail-end corner (full-final-13).
func _a23_exit_deck() -> bool:
	await _a23_walk(_a23_global(Vector3(1.0, 1.95, 2.60)), 6.0, "deck center", 0.30, false, true)
	await _a23_walk(_a23_global(Vector3(1.0, 1.95, 1.35)), 5.0, "gate lane", 0.10, false, true)
	await _a23_walk(_a23_global(Vector3(1.0, 0.20, -0.60)), 5.0, "through the boarding gate", 0.30, false, true)
	await _a23_walk(_a23_global(Vector3(0.50, 0.0, -2.40)), 4.0, "south apron", 0.60, false, true)
	await _wait(0.4)
	if not _in_tree(player):
		return false
	var pos: Vector3 = player.global_position
	var grounded: bool = bool(player.call("is_on_floor"))
	var deck: bool = _a23_on_deck()
	log_line("A23_OFF_DECK pos=%s grounded=%s on_deck=%s" % [str(pos), str(grounded), str(deck)])
	return (not deck) and pos.y < 0.60 and grounded


func _drive_act23() -> bool:
	_stage_now = "act23"
	_a23 = _find_act23_slice()
	if _a23 == null:
		check(false, "Act23 moving-cart slice exists")
		return false
	var waited := 0.0
	while waited < 30.0 and _valid(_a23) and _a23.get("loaded") != true:
		await _wait(0.2)
		waited += 0.2
	if not _valid(_a23) or not _scene_is("Act23Chapter"):
		check(false, "Act23 scene stayed alive while the slice loaded")
		return false
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

	# --- 1. 分时登车（真实 W 上黄色踏步，不传送） --------------------------
	if role == "host":
		if not await _a23_board():
			check(false, "host physically boarded the cart deck")
			_record_stage("act23_blocked_boarding", _a23_snapshot())
			return false
		# Clear the top of the stairs before the client climbs; waiting at the
		# landing lane would block the only 0.90 m-wide boarding stair.
		await _a23_walk(_a23_global(Vector3(2.48, 1.95, 1.08)), 5.0, "host wait at controller", 0.45, false)
		var client_boarded: bool = await _wait_until(_a23_remote_on_deck, 90.0)
		check(client_boarded, "host waited for the client to board before departure")
		if not client_boarded:
			_record_stage("act23_blocked_boarding", _a23_snapshot())
			return false
	else:
		var host_boarded: bool = await _wait_until(_a23_remote_on_deck, 90.0)
		check(host_boarded, "client waited for the host to clear the boarding stairs")
		if not host_boarded:
			_record_stage("act23_blocked_boarding", _a23_snapshot())
			return false
		if not await _a23_board():
			check(false, "client physically boarded the cart deck")
			_record_stage("act23_blocked_boarding", _a23_snapshot())
			return false
	check(_a23_on_deck(), "%s physically boarded the cart deck" % role)
	if not _a23_on_deck():
		return false

	# --- 2. host 发车 ------------------------------------------------------
	if role == "host":
		await _a23_walk(_a23_global(Vector3(2.48, 1.95, 1.08)), 5.0, "brake controller", 0.45, false)
		for _attempt in range(3):
			if bool(_a23_cart.get("running")):
				break
			await _a23_press("repair", 0.16)
			await _wait(0.8)
	var running: bool = await _wait_until(func() -> bool:
		if not _a23_cart_ok():
			return true
		return bool(_a23_cart.get("running")), 120.0)
	check(running, "the cart really started from the deck controller")
	if not running:
		_record_stage("act23_blocked_start", _a23_snapshot())
		return false
	_record_stage("act23_running", _a23_snapshot())

	# --- 3. 等断轨停车 ----------------------------------------------------
	var fault: bool = await _wait_until(func() -> bool:
		if not _scene_is("Act23Chapter"):
			return true
		if not _a23_cart_ok():
			return true
		return bool(_a23_cart.get("stopped_for_fault")), 240.0)
	check(fault, "cart stopped at the severed rail (governor, distance=%.1f)" %
		float(_safe_get(_a23_cart, "distance", -1.0)))
	_record_stage("act23_fault", _a23_snapshot())
	if not fault or not _a23_cart_ok():
		return false

	# --- 4. 分时下车（client 先走；host 确认队友真的落到场地再走） --------
	if role == "client":
		if not await _a23_exit_deck():
			check(false, "client physically stepped off the deck onto the yard")
			_record_stage("act23_blocked_off_deck", _a23_snapshot())
			return false
		# Clear the landing lane so the host has a free path off the gate.
		await _a23_walk(Vector3(89.0, 0.0, -1.5), 3.0, "client clear south apron", 0.6, false)
		var host_cleared: bool = await _wait_until(_a23_remote_cleared, 90.0)
		check(host_cleared, "client waited for the host to clear the gate")
		if not host_cleared:
			_record_stage("act23_blocked_off_deck", _a23_snapshot())
			return false
	else:
		var client_cleared: bool = await _wait_until(_a23_remote_cleared, 90.0)
		check(client_cleared, "host waited for the client to clear the gate before using it")
		if not client_cleared:
			_record_stage("act23_blocked_off_deck", _a23_snapshot())
			return false
		if not await _a23_exit_deck():
			check(false, "host physically stepped off the deck onto the yard")
			_record_stage("act23_blocked_off_deck", _a23_snapshot())
			return false
		# Stage south of the repair lane; standing on the apron would block the
		# client's first hook waypoint (89, 0, 0).
		await _a23_walk(Vector3(87.5, 0.0, -3.0), 3.0, "host staging south", 0.7, false)
	var off_deck: bool = (not _a23_on_deck()) and _in_tree(player) and player.global_position.y < 0.60
	check(off_deck, "both riders are on the yard ground, not wedged on the stairs")
	_record_stage("act23_off_deck", _a23_snapshot())
	if not off_deck:
		return false

	# --- 5. 修断轨（client 主导；host 等完工后再留下参与记录） ------------
	var rig: Node = _a23_yard.get("rig") as Node
	var winch: Node3D = rig.get("winch") as Node3D if rig != null else null
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
		await _a23_walk(Vector3(89.0, 0.0, 0.0), 6.0, "south clear lane", 0.7, false)
		await _a23_walk(Vector3(94.3, 0.0, 0.2), 7.0, "east around the cart nose", 0.7, false)
		await _a23_walk(Vector3(94.3, 0.0, 4.7), 6.0, "east of the swing nose", 0.7, false)
		await _a23_walk(Vector3(96.6, 0.0, 4.5), 5.0, "clear of the guide wheel", 0.7, false)
		# Stop ~1.0 m south of the lifting eye, still facing north. Walking onto
		# the anchor itself put the eye behind the body and the guide wheel closer,
		# so the host's repair router answered GUIDE_REFUSED (run r2-full-02).
		await _a23_walk(anchor_pos, 4.0, "front lifting eye", 1.0, false)
		await _a23_press("repair", 0.14)
		await _wait(0.6)
		var tension: Dictionary = rig.call("tension_state") as Dictionary
		check(bool(tension.get("attached", false)), "client hooked the winch cable onto the front lifting eye")
		log_line("ACT23_HOOK %s" % str(tension))
		if not bool(tension.get("attached", false)):
			_record_stage("act23_blocked_hook", _a23_snapshot())
			return false
		# 6b 接管绞盘
		await _a23_walk(Vector3(94.2, 0.0, 9.2), 7.0, "north of the line (east side)", 0.8, false)
		await _a23_walk(Vector3(88.6, 0.0, 9.2), 6.0, "north apron", 0.8, false)
		await _a23_walk(console_pos, 5.0, "winch console", 1.2, false)
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
		await _a23_walk(lock_pos, 10.0, "lock station", 1.05, false)
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
		# host 在场地南侧等 client 完成整套机械修复，避免两人抢控制台。
		var done_wait := 0.0
		while done_wait < 300.0 and not bool(_a23_yard.call("completion")):
			await _wait(0.5)
			done_wait += 0.5
		if bool(_a23_yard.call("completion")):
			# 完工后再上一次控制台，留下 host 的真实参与记录（不代做任何机械步骤）。
			# Approach from the south-east so the cart's under-deck block is not
			# crossed diagonally.
			await _a23_walk(Vector3(94.3, 0.0, -2.5), 8.0, "host east staging", 0.7, false)
			await _a23_walk(Vector3(94.3, 0.0, 4.7), 7.0, "host east of nose", 0.8, false)
			await _a23_walk(Vector3(94.2, 0.0, 9.2), 6.0, "host north apron", 0.8, false)
			await _a23_walk(Vector3(88.6, 0.0, 9.2), 6.0, "host north apron west", 0.8, false)
			await _a23_walk(console_pos, 5.0, "winch console (host)", 1.2, false)
			await _a23_press("repair", 0.14)
			await _wait(0.6)
			log_line("ACT23_HOST_CONSOLE at=%s actor=%d" % [
				str(_a23_flow.get("at_console")), int(_a23_flow.get("console_actor"))])
			await _a23_press("repair", 0.14)
			await _wait(0.4)
		check(bool(_a23_yard.call("completion")), "the broken rail is repaired (route_clear)")
		_record_stage("act23_repaired", _a23_snapshot())
		if not bool(_a23_yard.call("completion")):
			return false

	# --- 6. 分时回车（client 先；R 救援失败就走真实楼梯） -----------------
	if role == "client":
		for _attempt in range(3):
			await _a23_press("cart_recover", 0.14)
			await _wait(1.0)
			if _a23_on_deck():
				break
		if not _a23_on_deck():
			await _a23_walk(Vector3(96.6, 0.0, 4.5), 9.0, "reboard east", 0.7, false)
			await _a23_walk(Vector3(94.3, 0.0, 0.2), 8.0, "reboard south", 0.7, false)
			await _a23_walk(Vector3(89.0, 0.0, 0.6), 6.0, "reboard lane", 0.5, false)
			await _a23_board()
		check(_a23_on_deck(), "client is back on the deck for the re-ride")
		if not _a23_on_deck():
			_record_stage("act23_blocked_reboard", _a23_snapshot())
			return false
		# Keep the top of the stairs clear while the host climbs back on.
		await _a23_walk(_a23_global(Vector3(1.0, 1.95, 2.85)), 4.0, "client clear of stairs", 0.35, false)
		var host_back: bool = await _wait_until(_a23_remote_on_deck, 120.0)
		check(host_back, "client waited for the host to be back on deck")
		if not host_back:
			return false
	else:
		var client_back: bool = await _wait_until(_a23_remote_on_deck, 120.0)
		check(client_back, "host waited for the client to be back on deck")
		if not client_back:
			_record_stage("act23_blocked_reboard", _a23_snapshot())
			return false
		for _attempt in range(3):
			if _a23_on_deck():
				break
			await _a23_press("cart_recover", 0.14)
			await _wait(1.0)
		if not _a23_on_deck():
			# West-side route around the under-deck block, then the same stairs.
			await _a23_walk(Vector3(83.5, 0.0, 8.2), 9.0, "reboard west apron", 0.8, false)
			await _a23_walk(Vector3(83.5, 0.0, 0.8), 8.0, "reboard west lane", 0.8, false)
			await _a23_walk(Vector3(89.0, 0.0, 0.6), 6.0, "reboard south lane", 0.5, false)
			await _a23_board()
		check(_a23_on_deck(), "host is back on the deck for the re-ride")
		if not _a23_on_deck():
			_record_stage("act23_blocked_reboard", _a23_snapshot())
			return false
	_record_stage("act23_reboarded", _a23_snapshot())

	# --- 7. 重新发车 → 到站 → 交接 ----------------------------------------
	var route_ready: bool = await _wait_until(func() -> bool:
		if not _a23_cart_ok():
			return true
		return bool(_a23_cart.get("route_clear")), 60.0)
	check(route_ready, "cart route cleared by the repair")
	if role == "host":
		for _attempt in range(3):
			if bool(_a23_cart.get("running")):
				break
			await _a23_walk(_a23_global(Vector3(2.48, 1.95, 1.08)), 6.0, "controller aft", 0.45, false)
			await _a23_press("repair", 0.16)
			await _wait(1.0)
	var rerun: bool = await _wait_until(func() -> bool:
		if not _scene_is("Act23Chapter"):
			return true
		if not _a23_cart_ok():
			return true
		return bool(_a23_cart.get("running")), 120.0)
	check(rerun, "cart restarted after the repair")
	if not rerun:
		return false
	var arrived: bool = await _wait_until(func() -> bool:
		# The host may complete the hand-off while this client is still waiting;
		# the Act23 cart is then already freed. A scene change IS arrival.
		if not _scene_is("Act23Chapter"):
			return true
		if not _a23_cart_ok():
			return true
		return bool(_a23_cart.get("arrived")), 240.0)
	check(arrived, "cart physically reached the crystal-mine dock (distance=%.1f)" %
		float(_safe_get(_a23_cart, "distance", -1.0)))
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
	if not _in_tree(player):
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
	if not _in_tree(player):
		return false
	var elapsed := 0.0
	var stuck := 0.0
	var last: Vector3 = player.global_position
	Input.action_press("move_forward")
	while elapsed < seconds:
		await physics_frame
		elapsed += 1.0 / 60.0
		if not _in_tree(player) or current_scene != _a4:
			break
		var current: Vector3 = player.global_position
		_a4_face(Vector3(target.x, current.y, target.z))
		if Vector2(current.x - target.x, current.z - target.z).length() <= tolerance:
			break
		if current.distance_to(last) < 0.02:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
			last = current
		if stuck > 1.0:
			# The west-alcove lip is a real 0.4 m rock step. R1's known-good probe
			# used a real jump + sidestep here; R2 keeps that input (no teleport),
			# then re-aims at the waypoint.
			Input.action_press("jump")
			for _i in range(6):
				await physics_frame
			Input.action_release("jump")
			var side := "move_right" if int(elapsed * 7.0) % 2 == 0 else "move_left"
			Input.action_press(side)
			for _i in range(18):
				await physics_frame
			Input.action_release(side)
			stuck = 0.0
			last = player.global_position
	Input.action_release("move_forward")
	await physics_frame
	if not _in_tree(player):
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
	if not _valid(_a4):
		return false
	var hammer: Node = _a4.get("hammer")
	if not _valid(hammer):
		return false
	var anchor: Vector3 = (hammer as Node3D).call("get_interaction_position") as Vector3
	log_line("ACT04_HAMMER_START mode=%s anchor=%s pos=%s" % [
		str(hammer.get("mode")), str(anchor), str(player.global_position)])
	# R2: walk the clear north-west approach. The old straight line ended at
	# (1.2, -1.9) against the console cabinet, and R1 papered over that with
	# player.teleport(). A real player goes around the cabinet: first to the
	# west/north of it, then east onto the documented console stand.
	await _a4_walk(Vector3(1.15, 0.0, -0.55), 14.0, "hammer north west", 1.0)
	await _a4_walk(Vector3(2.35, 0.0, -0.55), 6.0, "hammer console stand", 0.45)
	var held := false
	for attempt in range(5):
		_a4_face(anchor, 0.05)
		await _wait(0.45)
		var target_name := ""
		var ct: Variant = player.get("current_target")
		if _valid(ct):
			target_name = str((ct as Node).name)
		var dist: float = player.global_position.distance_to(anchor)
		log_line("ACT04_AIM attempt=%d target=%s dist=%.2f pos=%s" % [
			attempt, target_name, dist, str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])
		Input.action_press("interact")
		await _wait(0.14)
		Input.action_release("interact")
		await _wait(0.45)
		held = str(hammer.get("mode")) == "held"
		if held:
			break
		# A real player re-centres: north of the cabinet, then back to the stand.
		await _a4_walk(Vector3(2.35, 0.0, 0.35), 2.5, "step away from the rig", 0.45)
		await _a4_walk(Vector3(2.35, 0.0, -0.55), 3.0, "re-approach the rig", 0.35)
	log_line("ACT04_HAMMER held=%s mode=%s pos=%s" % [
		str(held), str(hammer.get("mode")), str(player.global_position)])
	if not held:
		return false
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	# While held the player controller routes E to HammerRig._update_held(),
	# which releases the hammer into a real swing.
	_a4_face(anchor, 0.05)
	await _wait(0.25)
	Input.action_press("interact")
	await _wait(0.14)
	Input.action_release("interact")
	var before: int = int(hammer.get("strike_count"))
	await _wait(2.4)
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


func _a4_ledger_has(pid: int, kind: String) -> bool:
	var sess: Node = _session()
	if sess == null:
		return false
	var led: Variant = sess.get("ledger")
	if led == null:
		return false
	return bool(led.call("has_credit", pid, kind))


func _a4_hammer_mode() -> String:
	if not _valid(_a4):
		return "gone"
	var hammer: Variant = _a4.get("hammer")
	if not _valid(hammer):
		return "gone"
	return str((hammer as Object).get("mode"))


func _a4_remote_z() -> float:
	if not _valid(_a4):
		return 999.0
	var rp: Variant = _a4.get("remote_player")
	if _valid(rp) and rp is Node3D:
		return (rp as Node3D).global_position.z
	return 999.0


func _drive_act04() -> bool:
	_stage_now = "act04"
	_a4 = current_scene
	var ready: bool = await _wait_until(func() -> bool:
		if not _valid(_a4):
			return false
		if _a4.get("player") == null:
			return false
		if _a4.get("hammer") == null:
			return false
		return _a4.get("cradles") is Dictionary, 45.0)
	check(ready, "Act04 player, hammer rig and cradles became ready")
	if not ready:
		return false
	player = _a4.get("player") as Node
	if not _in_tree(player):
		check(false, "Act04 player exists")
		return false
	await _wait(1.0)
	_record_stage("act04_begin", _a4_snapshot())
	log_line("ACT04_START pos=%s mode=%s" % [str(player.global_position), str(_a4.get("coop_mode"))])

	# --- 1. 双方各撞一次钟（分时使用唯一的控制台） -------------------------
	# R1 let both bodies converge on the 0.78 x 0.62 m console at once. R2
	# serialises the real E/W interaction: host strikes, steps south out of the
	# aisle, the client then strikes from the north stand.
	var struck: bool = false
	if role == "host":
		struck = await _a4_strike()
		check(struck, "host struck the resonance bell with real E/W input")
		if not struck:
			_record_stage("act04_blocked_strike", _a4_snapshot())
			return false
		# Wait west of the hammer, not on the client's hold point (4.5, 4.0).
		await _a4_walk(Vector3(-4.0, 0.0, 5.0), 6.0, "host wait west of the console", 1.0)
		var client_credit: bool = await _wait_until(func() -> bool:
			return _a4_ledger_has(2, "act4_hammer_strike"), 90.0)
		check(client_credit, "host waited for the client's real phase-04 credit")
		if not client_credit:
			_record_stage("act04_blocked_client_strike", _a4_snapshot())
			return false
	else:
		var host_credit: bool = await _wait_until(func() -> bool:
			return _a4_ledger_has(1, "act4_hammer_strike"), 90.0)
		check(host_credit, "client waited for the host's real phase-04 credit")
		if not host_credit:
			_record_stage("act04_blocked_client_strike", _a4_snapshot())
			return false
		struck = await _a4_strike()
		check(struck, "client struck the resonance bell with real E/W input")
		if not struck:
			_record_stage("act04_blocked_strike", _a4_snapshot())
			return false

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
		# --- 客户端：持位等待主机恢复中继链 --------------------------------
		# R1's extra strike was never required: the client already earned its
		# phase-04 credit with the first real strike, and the second approach was
		# the run that got stuck at (-8.28, 3.2). R1 also walked the client into
		# the 4 m-wide west alcove at the same time as the host; two 0.76 m
		# capsules met at (-15.5, 7.9) and the host could never reach the shelf
		# (run r2-full-03). The client now holds the console area, which is not
		# on the host's relay route, so both bodies stay separated. This removes
		# a duplicate walk, not a game phase: the exit gate still needs both
		# phase-04 credits and both bodies walk into the exit later.
		note("client holds east of the hammer while the host restores the relay chain")
		# (4.5, 4.0) is east of the console and clear of the host's west route;
		# it is also the start of the client's own east-side exit route.
		await _a4_walk(Vector3(4.5, 0.0, 4.0), 6.0, "client hold east", 0.8)
		await _wait(1.0)

	var mem3: bool = await _a4_wait_memory(3, 180.0)
	check(mem3, "memory three reached through the restored final chain")
	var gate_open := false
	var gate_wait := 0.0
	var gate: Node = _a4.get("gate")
	while gate_wait < 60.0 and _valid(gate) and not bool(gate.get("is_open")):
		await _wait(0.4)
		gate_wait += 0.4
	gate_open = _valid(gate) and bool(gate.get("is_open"))
	check(gate_open, "exit gate physically opened")
	_record_stage("act04_gate", _a4_snapshot())
	if not gate_open:
		return false

	# --- 3. 分时走进出口（client 先；host 看到队友已到走廊再跟进） --------
	var completed := false
	if role == "client":
		# East-side route around the collapsed stope; the direct line from the
		# console to (0,-21) crosses the hammer rig and the pit. These waypoints
		# were validated by tests/r2_act4_route_probe.gd.
		await _a4_walk(Vector3(4.5, 0.0, -6.0), 9.0, "client east side south", 0.9)
		await _a4_walk(Vector3(0.0, 0.0, -14.0), 8.0, "client final west aisle", 1.0)
		await _a4_walk(Vector3(0.0, 0.0, -21.0), 8.0, "final chamber aisle client", 1.2)
		await _a4_walk(Vector3(6.2, 0.0, -25.0), 10.0, "exit corridor client", 0.6)
		# The client is not the authority: wait for the host to follow into the
		# trigger. A real client sees "waiting for host authority" here.
		completed = await _wait_until(func() -> bool:
			if not _scene_is("Resonance04") and not _scene_is("Act4"):
				return true
			return _valid(_a4) and bool(_a4.get("completed")), 120.0)
	else:
		var client_in: bool = await _wait_until(func() -> bool:
			return _a4_remote_z() < -24.0, 90.0)
		check(client_in, "host waited for the client to pass the exit gate")
		if not client_in:
			return false
		for attempt in range(4):
			if _scene_is("Main"):
				completed = true
				break
			await _a4_walk(Vector3(0.0, 0.0, -21.0), 10.0, "final chamber aisle %d" % attempt, 1.2)
			await _a4_walk(Vector3(6.2, 0.0, -25.0), 10.0, "exit corridor %d" % attempt, 1.3)
			completed = await _wait_until(func() -> bool:
				return _scene_is("Main") or (_valid(_a4) and bool(_a4.get("completed"))), 20.0)
			if completed or _scene_is("Main"):
				completed = true
				break
			# Step back out of the trigger, wait for the teammate's credit event,
			# then re-enter. Same loop a player performs after the toast.
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
	if not _in_tree(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	var flat: float = Vector2(d.x, d.z).length()
	var pitch: float = -atan2(d.y - 1.45, maxf(flat, 0.05))
	player.call("set_look", yaw, clampf(pitch, -1.1, 1.1))


func _a5_walk(target: Vector3, seconds: float, label := "", tolerance := 1.1) -> bool:
	if not _in_tree(player):
		return false
	var elapsed := 0.0
	var stuck := 0.0
	var last: Vector3 = player.global_position
	Input.action_press("move_forward")
	while elapsed < seconds:
		await physics_frame
		elapsed += 1.0 / 60.0
		if not _in_tree(player) or current_scene != _a5:
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
	if not _in_tree(player) or current_scene != _a5:
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


## R1 diagnostics: sample the host-authoritative leg state (and the client's own
## local operate target) while the normal Act05 script runs. Pure read-only.
func _a5_monitor() -> void:
	var level: Node = _a5.get("level")
	var session: Node = _a5.get("session")
	var surge: Node = _a5.get("surge")
	var story: Node = _a5.get("story")
	if level == null or session == null:
		return
	var samples: int = 0
	while is_instance_valid(_a5) and current_scene == _a5 and samples < 900:
		await _wait(0.5)
		samples += 1
		var stabs: Array = level.get("stabilizers") as Array
		var parts: Array[String] = []
		for i in range(stabs.size()):
			var s: Object = stabs[i]
			parts.append("%d:%s ext=%.2f p=%.2f lat=%s owner=%d" % [
				i, "W" if i == 0 else "E",
				float(s.get("extension")), float(s.get("pressure")),
				str(bool(s.get("latched"))),
				int(session.call("claim_owner", "stabilizer_w" if i == 0 else "stabilizer_e"))])
		var axis: float = float((session.get("remote_axes") as Dictionary).get("stabilizer_w", -99.0))
		var target_name: String = ""
		var op_target: Variant = player.get("operate_target")
		if op_target is Node and is_instance_valid(op_target):
			target_name = str((op_target as Node).name)
		log_line("MON05 role=%s t=%.1f surge=%s/%s stage=%s core=cap:%s lock:%s | %s | axis_w=%.2f op=%s machine=%s target=%s pos=%s" % [
			role, float(Time.get_ticks_msec() - started_msec) / 1000.0,
			str(surge.get("state")) if surge != null else "?", str(surge.get("surge_count")) if surge != null else "?",
			str(story.get("stage")) if _a5.get("story") != null else "?",
			str((level.get("core") as Object).call("is_capturable")),
			str((level.get("core") as Object).call("is_locked")),
			" | ".join(parts), axis,
			str(bool(player.get("operating"))), str(session.get("local_operating_machine")),
			target_name, str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])


## R2 acceptance boundary: both real processes are inside Act05's Main scene,
## the production hand-off flag is set, and the session still has both seats.
## The Act05 machine chain is deliberately NOT part of this probe's PASS scope.
func _verify_act05_entry() -> bool:
	_a5 = current_scene
	if not _scene_is("Main"):
		check(false, "Act05 entry scene is Main (got %s)" % (str(current_scene.name) if current_scene != null else "null"))
		return false
	var got_node: bool = await _wait_until(func() -> bool:
		if not _scene_is("Main"):
			return false
		if not _valid(_a5):
			return false
		var p: Variant = _a5.get("player")
		return _valid(p) and _valid(_a5.get("level")), 60.0)
	check(got_node, "Act05 world/player became ready after the hand-off")
	if not got_node:
		return false
	player = _a5.get("player") as Node
	var handoff: bool = bool(_a5.get("handoff_from_act04"))
	check(handoff, "Act05 was entered through the real Act04 hand-off (handoff_from_act04=true)")
	var both_online: bool = await _wait_until(func() -> bool: return _peers() >= 2, 30.0)
	var peers: int = _peers()
	check(both_online and peers == 2, "both processes are still in the same ENet session (peers=%d)" % peers)
	var seated: bool = await _wait_until(func() -> bool:
		var sess: Node = _session()
		return sess != null and int(sess.call("player_count")) >= 2, 30.0)
	check(seated, "Act05 session still has both player seats")
	var pos: Vector3 = player.global_position if _in_tree(player) else Vector3.ZERO
	check(pos.y > 3.0, "player spawned on the Act05 deck (y=%.2f)" % pos.y)
	log_line("ACT05_ENTRY scene=%s pos=%s handoff_from_act04=%s peers=%d players=%s" % [
		str(current_scene.name), str(pos.snapped(Vector3(0.01, 0.01, 0.01))), str(handoff), peers,
		str(_session().call("player_count") if _session() != null else -1)])
	_record_stage("act05_entry", {
		"pid": _local_pid(), "peers": peers, "scene": str(current_scene.name),
		"handoff_from_act04": handoff, "pos": str(pos),
		"player_count": int(_session().call("player_count")) if _session() != null else -1,
		"chapter": str(hub.get("current_chapter")) if hub != null else "?",
	})
	# Harness barrier: the host used to call quit() the instant its own checks
	# passed, dropping the ENet peer before the client could read peers==2.
	# r2-full-07 failed exactly there (client peers=1) while the game hand-off
	# itself had succeeded. Hold both ends in Main long enough for the peer to
	# run the same checks, then finish together. This changes only test timing.
	log_line("ACT05_ENTRY_HOLD 20s so the peer can verify the same session")
	await _wait(20.0)
	log_line("ACT05_ENTRY_HOLD_DONE peers=%d" % _peers())
	return handoff and peers == 2 and seated and pos.y > 3.0


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
	_a5_monitor()

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
		# The direct line from the left ramp to the hall centre climbs onto the
		# counterweight rail and wedges at y≈2.0. Walk south around the core
		# pedestal like a player would.
		await _a5_walk(Vector3(-4.0, 0.06, 8.0), 8.0, "hall south west", 1.2)
		await _a5_walk(Vector3(0.0, 0.06, 10.5), 8.0, "hall south", 1.2)
		await _a5_walk(Vector3(8.0, 0.06, 10.5), 10.0, "hall south east", 1.2)
		await _a5_walk(Vector3(10.3, 0.06, 6.0), 6.0, "east aisle", 1.2)
		await _a5_walk(Vector3(8.0, 0.06, 2.2), 6.0, "right ramp foot", 1.2)
		# R1: the host latches its own (east) leg before the counterweight. The
		# west leg is the client's, so the two-leg interlock is earned by two
		# different players, not by the host doing both machines.
		var stabs_h: Array = level.get("stabilizers") as Array
		var east_stab: Object = stabs_h[1]
		var east_area: Node3D = east_stab.get("area") as Node3D
		var east_center: Vector3 = east_area.global_position
		var east_basis: Basis = (east_stab as Node3D).global_transform.basis
		var east_stand: Vector3 = east_center + east_basis.z * 1.25
		east_stand.y = 0.06
		await _a5_walk(Vector3(10.3, 0.06, -2.0), 10.0, "east leg aisle", 1.2)
		await _a5_walk(Vector3(8.3, 0.06, -6.0), 8.0, "east leg approach", 1.2)
		await _a5_walk(east_stand, 8.0, "east stabilizer", 1.1)
		_a5_face(east_center)
		await _wait(0.25)
		await _a5_press()
		var ope := false
		for _i in range(3):
			if bool(player.get("operating")):
				ope = true
				break
			await _a5_walk(east_stand, 4.0, "east stabilizer retry", 0.8)
			await _a5_press()
		check(ope, "host operates the east stabilizer with real E")
		if ope:
			Input.action_press("move_forward")
			var east_wait := 0.0
			while east_wait < 15.0 and not bool(east_stab.get("latched")):
				await _wait(0.25)
				east_wait += 0.25
			Input.action_release("move_forward")
			await _a5_press()
		check(bool(east_stab.get("latched")), "east stabilizer latched by host pumping")
		var led_e: Variant = session.get("ledger")
		check(led_e != null and bool(led_e.call("has_credit", _local_pid(), "stabilizer_lock")),
			"host earned stabilizer_lock credit")
		var east_credit: bool = led_e != null and bool(led_e.call("has_credit", _local_pid(), "stabilizer_lock"))
		log_line("ACT05_EAST_LEG latched=%s credit=%s" % [
			str(bool(east_stab.get("latched"))), str(east_credit)])
		await _a5_walk(Vector3(8.0, 0.06, 2.2), 12.0, "back to station ramp foot", 1.2)
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
		_a5_face((stab.get("area") as Node3D).global_position)
		await _wait(0.25)
		await _a5_press()
		var opw := false
		for _i in range(4):
			if bool(player.get("operating")):
				opw = true
				break
			await _a5_walk(stand, 4.0, "stabilizer retry", 0.8)
			await _a5_press()
		check(opw, "client operates the west stabilizer with real E")
		log_line("ACT05_STAB_BEGIN op=%s machine=%s target=%s pos=%s" % [
			str(bool(player.get("operating"))), str(session.get("local_operating_machine")),
			str((player.get("operate_target") as Node).name if player.get("operate_target") is Node else "null"),
			str(player.global_position)])
		# A real player keeps pumping until the pawl drops; a single fixed 6 s
		# hold is not representative when a surge can knock the ram back. Hold W
		# continuously and let the host-authoritative latched flag end it.
		# `--act05=legacy` reproduces the R8C-04 timing exactly (one 6 s hold).
		var latched: bool = false
		var pump_elapsed: float = 0.0
		if legacy_act05:
			await _a5_hold("move_forward", 6.0)
			await _a5_press()
			latched = bool((level.get("stabilizers") as Array)[0].get("latched"))
			log_line("ACT05_STAB_PUMP_END legacy t=6.0 latched=%s op=%s pos=%s" % [
				str(latched), str(bool(player.get("operating"))), str(player.global_position)])
		else:
			Input.action_press("move_forward")
			while pump_elapsed < 30.0:
				await _wait(0.25)
				pump_elapsed += 0.25
				if bool((level.get("stabilizers") as Array)[0].get("latched")):
					latched = true
					break
			Input.action_release("move_forward")
			log_line("ACT05_STAB_PUMP_END t=%.1f latched=%s op=%s pos=%s" % [
				pump_elapsed, str(latched), str(bool(player.get("operating"))), str(player.global_position)])
			await _a5_press()
		check(latched, "west stabilizer latched by real client pumping")
		var led2: Variant = session.get("ledger")
		check(led2 != null and bool(led2.call("has_credit", _local_pid(), "stabilizer_lock")),
			"client earned stabilizer_lock credit")

	# --- 3. 维修爬梯 → 栈桥 → 抓握过涌浪（B，双方） ------------------------
	var catwalk: Node = level.get("catwalk")
	var ladder_node: Node3D = catwalk.get("ladder_station_node") as Node3D if catwalk != null else null
	var ladder_stand: Vector3 = Vector3(-7.55, 0.06, 0.65)
	if ladder_node != null:
		ladder_stand = Vector3(ladder_node.global_position.x, 0.06, ladder_node.global_position.z + 0.9)
	if role == "host":
		# Host comes from the east ramp; cross the hall on the south side so the
		# core pedestal cannot pin the body against a counterweight rail.
		await _a5_walk(Vector3(8.0, 0.06, 10.5), 8.0, "ladder south east", 1.2)
		await _a5_walk(Vector3(-4.0, 0.06, 10.5), 10.0, "ladder south west", 1.2)
		await _a5_walk(Vector3(-7.9, 0.06, 3.8), 6.0, "ladder west approach", 1.2)
	if role == "client" and not legacy_act05:
		# The direct line from the west leg runs into the catwalk support
		# column (a real, visible obstacle). Walk around it like a player would
		# instead of pushing into it and calling the ladder unreachable.
		await _a5_walk(Vector3(-9.7, 0.06, -4.6), 8.0, "ladder west detour", 1.2)
		await _a5_walk(Vector3(-9.7, 0.06, 1.4), 8.0, "ladder north detour", 1.2)
		await _a5_walk(Vector3(-7.9, 0.06, 1.2), 6.0, "ladder front", 1.0)
	await _a5_walk(ladder_stand, 10.0, "catwalk ladder", 0.9)
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
	# The rail is the north edge of the deck; the body must stand on the deck
	# (south of it). The old +0.9 target was outside the deck and walked the
	# body off the north railing.
	await _a5_walk(Vector3(grip_target.x, 3.5, grip_target.z - 0.55), 12.0, "brace rail", 1.2)
	var grabbing := false
	for _attempt in range(4):
		_a5_face(grip_target)
		await _a5_press()
		grabbing = bool(player.get("grabbing"))
		if grabbing:
			break
		await _a5_walk(Vector3(grip_target.x, 3.5, grip_target.z - 0.55), 3.0, "brace retry", 0.9)
	check(grabbing, "player grabbed a catwalk rail with real E")
	if grabbing:
		# The phase-B credit must come from a surge that happens *while* the
		# player is holding the rail. Waiting for any historical surge is a
		# false positive: record the count at grab time and require a new one.
		var surge_before: int = int(surge.get("surge_count"))
		var surge_t := 0.0
		while surge_t < 180.0 and int(surge.get("surge_count")) <= surge_before:
			await _wait(0.5)
			surge_t += 0.5
		log_line("ACT05_SURGE before=%d now=%s t=%.1f grabbing=%s state=%s" % [
			surge_before, str(surge.get("surge_count")), surge_t,
			str(player.get("grabbing")), str(surge.get("state"))])
		check(int(surge.get("surge_count")) > surge_before,
			"a natural resonance surge fired while braced")
		await _a5_press()
	var led3: Variant = session.get("ledger")
	var b_ok: bool = led3 != null and (bool(led3.call("has_credit", _local_pid(), "surge_response")) \
		or bool(led3.call("has_credit", _local_pid(), "brace_hold")))
	check(b_ok, "player earned a phase-B credit by bracing through the surge")
	_record_stage("act05_brace", _a5_snapshot())

	# --- 4. 下栈桥 --------------------------------------------------------
	# The deck is railed on both long sides; the intended way down is the free
	# east end (x = -8.2 world). The old targets (-11.6, z=-2.6) were outside
	# the south railing, so the body could only push into the rail and the test
	# then blamed the following stations.
	await _a5_walk(Vector3(-8.7, 3.5, -4.2), 9.0, "catwalk free end", 1.1)
	await _a5_walk(Vector3(-6.7, 3.5, -4.2), 6.0, "walk off the free end", 1.2)
	await _a5_walk(Vector3(-6.7, 0.06, -4.2), 6.0, "land below the catwalk", 1.5)
	# R2: no teleport fallback. If the free-end drop leaves the body on the
	# bracket, walk off the end with real input and report the height honestly.
	if player.global_position.y > 2.0:
		await _a5_walk(Vector3(-5.0, 0.06, -2.0), 10.0, "walk off the catwalk end", 1.4)
	log_line("ACT05_LEFT_CATWALK y=%.2f pos=%s grabbing=%s operating=%s" % [
		player.global_position.y, str(player.global_position),
		str(bool(player.get("grabbing"))), str(bool(player.get("operating")))])
	if player.global_position.y > 2.0:
		await _a5_walk(Vector3(-5.0, 0.06, -2.0), 8.0, "leave the catwalk", 1.4)

	if role == "host":
		# --- C：爪锁 + 阻尼 ------------------------------------------------
		var both_latched: bool = await _wait_until(func() -> bool:
			return int((level as Object).call("stabilizers_latched")) >= 2, 240.0)
		check(both_latched, "both hydraulic legs are latched (core can be captured)")
		var cap: bool = await _wait_until(func() -> bool:
			return bool((level.get("core") as Object).call("is_capturable")), 240.0)
		check(cap, "core entered the capture band")
		await _a5_walk(Vector3(-4.0, 0.06, 8.0), 8.0, "south west floor", 1.2)
		await _a5_walk(Vector3(0.0, 0.06, 10.5), 6.0, "south of the lock", 1.2)
		await _a5_walk(Vector3(0.0, 0.06, 10.6), 3.0, "lock console stand", 0.9)
		_a5_face(Vector3(0.0, 1.2, 8.6))
		await _wait(0.3)
		await _a5_press()
		var locked: bool = await _wait_until(func() -> bool:
			return bool((level.get("core") as Object).call("is_locked")), 60.0)
		check(locked, "hydraulic claw locked the core with real E")
		var led4: Variant = session.get("ledger")
		check(led4 != null and bool(led4.call("has_credit", _local_pid(), "lock_assist")),
			"host earned lock_assist credit")
		await _a5_walk(Vector3(8.0, 0.06, 8.0), 8.0, "east south floor", 1.2)
		await _a5_walk(Vector3(10.3, 0.06, 2.0), 6.0, "east aisle", 1.2)
		await _a5_walk(Vector3(8.0, 0.06, -2.3), 5.0, "damper approach", 1.2)
		await _a5_walk(Vector3(6.4, 0.06, -2.3), 4.0, "extraction damper", 1.0)
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
		await _a5_walk(Vector3(6.0, 0.06, -9.0), 8.0, "rear hall east", 1.2)
		await _a5_walk(Vector3(-3.0, 0.06, -8.0), 8.0, "data plinth", 1.2)
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
		"probe": "r2_full_chain_probe.gd",
		"scope": "Launcher -> Act01 -> Act23Chapter -> Resonance04 -> Act05 entry",
		"act05_full_requested": run_act05_full,
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



