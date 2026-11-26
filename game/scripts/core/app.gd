extends Node3D

## Resonance 05 V2 entry point.
##
## Solo, host and client all build the same level; the difference is who owns
## the machines (CoopSession.is_host) and whether a CoopNet exists. The session
## owns the participant list and the participation ledger; the level owns the
## physical machines; the surge director owns the accident; the story director
## owns the mission gate.

var level: LevelBuilder
var player: PlayerController
var hud: GameHud
var audio: AudioDirector
var story: StoryDirector
var surge: SurgeDirector
var session: CoopSession
var net: CoopNet
var mode: String = "solo"
var host_port: int = CoopNet.PORT_DEFAULT
var join_address: String = "127.0.0.1"

var paused: bool = false
var debug_visible: bool = false
var completed: bool = false
var _fall_timer: float = 0.0
var _last_prompt: String = ""
var _crew_clock: float = 0.0
var _auto: String = ""

# --- cross-chapter hand-off (SessionHub contract) ---------------------------
# Act 4 leaves `chapter_progress` and `pending_spawn` on the shared SessionHub
# autoload. Act 5 only consumes those two frozen fields: it does not keep a
# second copy of the campaign state and it does not redefine the session.
var handoff_consumed: bool = false
var handoff_valid: bool = false
var handoff_from_act04: bool = false
var handoff_payload: Dictionary = {}
var handoff_pending: Dictionary = {}
var entry_spawn: Vector3 = LevelBuilder.SPAWN_POSITION
var entry_yaw: float = 0.0
var spawn_from_payload: bool = false
var _handoff_started: bool = false

const FINALE_SCENE := "res://demo/demo_ending.tscn"
## Small beat after the crew result before the settlement scene replaces the
## act, so the completion card is not cut off mid-fade.
const SETTLE_DELAY := 1.6


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()
	InputSetup.ensure_actions()
	_consume_handoff()
	audio = AudioDirector.new()
	audio.name = "AudioDirector"
	add_child(audio)
	audio.setup()

	# The session and the network peer live on the SessionHub autoload so they
	# survive scene changes (Act 4 → Act 5). This act scene only binds to them.
	session = SessionHub.session
	net = SessionHub.net
	session.add_player(1, "七号", true)

	level = LevelBuilder.new()
	level.name = "Level"
	add_child(level)
	level.build(audio, session)

	hud = GameHud.new()
	hud.name = "Hud"
	add_child(hud)

	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	player.teleport(entry_spawn, entry_yaw, -0.04)
	player.audio = audio
	level.bind_player(player)
	session.local_player_ref = player
	var explore5: Node3D = preload("res://scripts/act5/act5_explore_props.gd").new() as Node3D
	add_child(explore5)
	explore5.setup(hud)

	story = StoryDirector.new()
	story.name = "Story"
	add_child(story)
	story.setup(level, hud, audio, player, session)
	level.story = story

	surge = SurgeDirector.new()
	surge.name = "Surge"
	add_child(surge)
	surge.setup(level, session, audio, hud, player)
	story.surge = surge

	net.bind(session, level, story, surge, hud, player, audio)
	net.process_mode = Node.PROCESS_MODE_ALWAYS

	if mode == "host":
		var err: int = SessionHub.start(true, host_port)
		if err == OK:
			hud.toast("主机已启动 · 端口 %d · 等待队友加入" % host_port, 4.0)
		else:
			hud.toast("主机启动失败：%d" % err, 4.0)
	elif mode == "client":
		surge.set_remote(true)
		story._remote_mode = true
		var err2: int = SessionHub.start(false, host_port, join_address)
		if err2 == OK:
			hud.toast("正在连接 %s:%d …" % [join_address, host_port], 4.0)
		else:
			hud.toast("连接失败：%d" % err2, 4.0)

	_connect_signals()
	hud.fade_rect.color = Color(0, 0, 0, 1)
	hud.fade(0.0, 2.2)
	if not _is_headless():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	story.begin()
	hud.toast("WASD 移动 · E 交互 · F1 帮助 · F8 转为观战", 4.2)
	_apply_handoff_feedback()
	_update_crew()
	explore5.populate_ambient(self)
	if _auto == "host" or _auto == "client" or _auto == "solo":
		var bot: Node = load("res://tests/coop_auto.gd").new()
		bot.name = "CoopAuto"
		bot.set("role", _auto)
		add_child(bot)


# ---------------------------------------------------------------------------
# Cross-chapter hand-off (read-only consumption of the frozen SessionHub API)
# ---------------------------------------------------------------------------
## Read what Act 4 left on the shared hub. This runs before the level exists so
## the body can spawn on the handed-over transform; the payload itself is kept
## on the instance for the settlement record.
func _consume_handoff() -> void:
	if SessionHub == null:
		return
	var progress: Variant = SessionHub.chapter_progress
	if progress is Dictionary:
		handoff_payload = (progress as Dictionary).duplicate(true)
	var pending: Variant = SessionHub.pending_spawn
	if pending is Dictionary:
		handoff_pending = (pending as Dictionary).duplicate(true)
	handoff_from_act04 = bool(handoff_pending.get("from_act4", false)) and str(handoff_pending.get("chapter", "")) == "resonance_04"
	handoff_valid = bool(handoff_payload.get("completed", false)) or handoff_from_act04

	# Spawn transform: the contract documents `pending_spawn.spawn`; the payload
	# itself is also accepted so a chapter can hand over a position without
	# inventing a second field. Anything invalid falls back to the level spawn.
	entry_spawn = LevelBuilder.SPAWN_POSITION
	entry_yaw = 0.0
	var handed_position: Variant = _payload_position(handoff_pending)
	if handed_position == null:
		handed_position = _payload_position(handoff_payload)
	if handed_position is Vector3 and _valid_spawn(handed_position as Vector3):
		entry_spawn = handed_position as Vector3
		entry_yaw = _payload_yaw(handoff_pending, handoff_payload)
		spawn_from_payload = true

	# Entering this scene means Act 5 is the current chapter. Act 4 uses the
	# legacy request_scene_switch path, which never wrote the uniform ledger, so
	# its own completion payload is adopted once here (no completion is invented:
	# it is only copied from what Act 4 reported).
	SessionHub.current_chapter = "act05"
	if handoff_from_act04 and bool(handoff_payload.get("completed", false)):
		var history: Dictionary = SessionHub.chapter_history
		var act4: Variant = history.get("act04", {})
		if act4 is Dictionary and (act4 as Dictionary).is_empty():
			SessionHub.record_chapter_done("act04", handoff_payload.duplicate(true))
	handoff_consumed = true


func _payload_position(data: Dictionary) -> Variant:
	for key in ["spawn", "spawn_position", "position"]:
		var value: Variant = data.get(key, null)
		if value is Vector3:
			return value
	return null


func _payload_yaw(pending: Dictionary, payload: Dictionary) -> float:
	for data in [pending, payload]:
		var value: Variant = (data as Dictionary).get("yaw", null)
		if value is float or value is int:
			return float(value)
	return 0.0


func _valid_spawn(pos: Vector3) -> bool:
	if not is_finite(pos.x) or not is_finite(pos.y) or not is_finite(pos.z):
		return false
	return absf(pos.x) < 200.0 and absf(pos.z) < 200.0 and pos.y > -10.0 and pos.y < 80.0


func _apply_handoff_feedback() -> void:
	if hud == null or not handoff_consumed:
		return
	if handoff_from_act04:
		var strikes: int = int(handoff_payload.get("strikes", 0))
		var seconds: float = float(handoff_payload.get("seconds", 0.0))
		hud.toast("章节衔接：第四幕已完成（撞钟 %d 次 · 用时 %d 秒）· 记录已接入第五幕" % [strikes, int(seconds)], 4.8)
	elif handoff_valid:
		hud.toast("章节衔接：上一章状态已接入", 4.0)



func _parse_args() -> void:
	var args: Array[String] = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg == "--host":
			mode = "host"
		elif arg == "--client":
			mode = "client"
		elif arg.begins_with("--port="):
			host_port = int(arg.split("=")[1])
		elif arg.begins_with("--address="):
			join_address = arg.split("=")[1]
		elif arg.begins_with("--auto="):
			_auto = arg.split("=")[1]
			mode = _auto
	if _auto == "client":
		mode = "client"
	elif _auto == "host":
		mode = "host"
	elif _auto == "solo":
		mode = "solo"


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _connect_signals() -> void:
	player.prompt_changed.connect(_on_prompt_changed)
	player.request_debug.connect(_toggle_debug)
	player.request_reset.connect(_reset_to_checkpoint)
	player.request_restart.connect(_restart_level)
	player.request_pause.connect(_toggle_pause)
	story.run_completed.connect(_on_completed)


func _on_prompt_changed(text: String) -> void:
	_last_prompt = text
	hud.set_prompt(text)


func _on_completed(_summary: Dictionary) -> void:
	completed = true
	_settle_chapter()


## Act05 -> finale contract. The signal alone is not proof: the completion is
## only accepted when the story's own gate is closed (navigation data taken and
## every active participant has verified phase credits). A test that merely
## writes `completed = true` on the object therefore cannot reach the finale.
func _settle_chapter() -> void:
	if _handoff_started:
		return
	if story == null or not story.completed_flag():
		return
	if not story.data_taken:
		return
	if session != null and not session.can_finish():
		return
	if SessionHub == null:
		return
	_handoff_started = true
	var payload: Dictionary = _completion_payload()
	var spawn: Dictionary = {
		"chapter": "resonance_05",
		"from_act05": true,
		"completed": bool(payload.get("completed", false)),
		"spawn": entry_spawn,
	}
	await get_tree().create_timer(SETTLE_DELAY).timeout
	if not is_inside_tree():
		return
	SessionHub.complete_chapter("act05", payload, "finale", FINALE_SCENE, spawn)


## Derived only from the live run (story gate, participation ledger, machines).
func _completion_payload() -> Dictionary:
	var participants: Dictionary = {}
	var ledger: Dictionary = {}
	if session != null:
		participants = session.completion_report()
		ledger = session.ledger_snapshot()
	var seconds: float = 0.0
	if story != null:
		seconds = maxf(0.0, story.completion_time - story.start_time)
	return {
		"chapter": "resonance_05",
		"completed": story.completed_flag() if story != null else false,
		"story_completed": story.completed_flag() if story != null else false,
		"data_taken": story.data_taken if story != null else false,
		"seconds": seconds,
		"lock_attempts": story.lock_attempts if story != null else 0,
		"surges": story.surges if story != null else 0,
		"checkpoint": story.checkpoint if story != null else 0,
		"memory_watched": story.memory_watched if story != null else false,
		"handoff_from_act04": handoff_from_act04,
		"entry_spawn": entry_spawn,
		"participants": participants,
		"ledger": ledger,
	}


func _toggle_debug() -> void:
	debug_visible = not debug_visible
	hud.set_debug(debug_visible)
	if get_tree() != null:
		get_tree().debug_collisions_hint = debug_visible


func _toggle_pause() -> void:
	if completed:
		return
	if paused:
		paused = false
		get_tree().paused = false
		hud.show_pause(false)
		if not _is_headless():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		player.mouse_enabled = true
	else:
		paused = true
		get_tree().paused = true
		hud.show_pause(true)
		player.mouse_enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _reset_to_checkpoint() -> void:
	if completed:
		return
	if paused:
		_toggle_pause()
	if net != null and net.is_online() and not net.is_host:
		net.request_reset.rpc_id(1)
		hud.toast("已请求主机重置", 2.0)
		return
	story.reset_to_checkpoint()
	hud.set_prompt("")
	player.mouse_enabled = true
	completed = false
	_update_crew()


func _restart_level() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _toggle_spectator() -> void:
	if session == null:
		return
	if not net.is_online():
		hud.toast("单人模式没有其他参与者", 2.2)
		return
	if not net.is_host:
		hud.toast("只有主机可以调整参与状态", 2.4)
		return
	var status: String = session.status_of(1)
	if status == ParticipationLedger.STATUS_SPECTATOR:
		session.set_status(1, ParticipationLedger.STATUS_ACTIVE)
		hud.toast("已返回有效参与者", 2.4)
	else:
		session.set_status(1, ParticipationLedger.STATUS_SPECTATOR)
		hud.toast("已转为观战：本次通关不计入你的记录", 3.2)
	_update_crew()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		if player != null and player.operating:
			player.stop_operating()
			get_viewport().set_input_as_handled()
			return
		if player != null and player.grabbing:
			player.stop_grab()
			get_viewport().set_input_as_handled()
			return
		if completed:
			return
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).physical_keycode
		if key == KEY_Q and paused:
			get_tree().quit()
			return
		if key == KEY_F5:
			_restart_level()
			return
		if key == KEY_R and paused:
			_reset_to_checkpoint()
			return
		if key == KEY_F1:
			hud.show_help(not hud.help_visible)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F8:
			_toggle_spectator()
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	if level == null:
		return
	if not completed:
		_check_fall()
	if debug_visible and hud != null:
		hud.update_debug(_debug_text())
	_crew_clock -= delta
	if _crew_clock <= 0.0:
		_crew_clock = 0.35
		_update_crew()


func _update_crew() -> void:
	if session == null or hud == null:
		return
	var rows: Array[String] = []
	for pid in session.ledger.player_ids():
		var record: Dictionary = session.ledger.get_record(pid)
		if record.is_empty():
			continue
		var status: String = str(record.get("status", "active"))
		var tag: String = ""
		if status == ParticipationLedger.STATUS_SPECTATOR:
			tag = " [观战]"
		elif status == ParticipationLedger.STATUS_DISCONNECTED:
			tag = " [离线]"
		elif status == ParticipationLedger.STATUS_AWAY:
			tag = " [暂离]"
		var mark: String = ""
		for phase in ParticipationLedger.PHASES:
			mark += ("●" if session.ledger.ready_for_phase(pid, phase) else "○")
		rows.append("P%d %s %s%s" % [pid, session.ledger.display_name(pid), mark, tag])
	var title: String = "全员参与 · 1 人"
	if net != null and net.is_online():
		title = "全员参与 · %d 人在线" % net.peer_count()
	elif session.player_count() > 1:
		title = "全员参与 · %d 人" % session.player_count()
	var local_id: int = session.local_pid
	var hint: String = ""
	if not session.ledger.is_ready(local_id) and session.status_of(local_id) == ParticipationLedger.STATUS_ACTIVE:
		var miss: Array[String] = session.ledger.missing_summary(local_id)
		if not miss.is_empty():
			hint = "你还需要：" + miss[0]
	elif session.is_host:
		var gate: String = session.gate_text()
		if gate != "":
			hint = "收队前：" + gate
		else:
			hint = "全员已具备收队条件"
	hud.update_crew("\n".join(rows), hint, title)


func _check_fall() -> void:
	if player == null:
		return
	if player.global_position.y < -6.0:
		_fall_timer += get_process_delta_time()
		if _fall_timer > 0.6:
			_fall_timer = 0.0
			story.reset_to_checkpoint()
			hud.toast("已回到最近检查点", 2.0)
	else:
		_fall_timer = 0.0


func _debug_text() -> String:
	var lines: String = ""
	lines += "FPS %d  |  %.1f ms\n" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())]
	lines += "POS %.1f %.1f %.1f  yaw %.2f pitch %.2f\n" % [player.global_position.x, player.global_position.y, player.global_position.z, player.yaw, player.pitch]
	lines += "CORE net %.3f  angle %.3f  omega %.3f  limit %.3f  %s\n" % [level.core.get_net(), level.core.get_angle(), level.core.get_omega(), level.core.capture_net_limit(), "CAPTURE" if level.core.is_capturable() else "UNSTABLE"]
	lines += "CARTS L %.2f  R %.2f  |  stage %d  checkpoint %d\n" % [level.left_cart.get_p(), level.right_cart.get_p(), story.stage, story.checkpoint]
	lines += "COOP host=%s pid=%d online=%s peers=%d remote=%s\n" % [str(net.is_host), session.local_pid, str(net.is_online()), net.peer_count(), str(level.core.remote)]
	lines += "STAB w=%.2f/%s e=%.2f/%s  brake=%.2f/%s  damper=%.2f/%s\n" % [
		level.stabilizers[0].extension, str(level.stabilizers[0].latched),
		level.stabilizers[1].extension, str(level.stabilizers[1].latched),
		level.brake.pressure, str(level.brake.latched), level.damper.pressure, str(level.damper.latched_flag)]
	lines += "HYD w p=%.1fMPa load=%.1fkN clamp=%.1fkN v=%+.2fm/s %s | e p=%.1fMPa load=%.1fkN clamp=%.1fkN v=%+.2fm/s %s\n" % [
		level.stabilizers[0].pressure * StabilizerRig.RELIEF / 1.0e6,
		level.stabilizers[0].load_force / 1000.0,
		level.stabilizers[0].clamp_force / 1000.0,
		level.stabilizers[0].ram_velocity,
		"STALL" if level.stabilizers[0].stalled else "ok",
		level.stabilizers[1].pressure * StabilizerRig.RELIEF / 1.0e6,
		level.stabilizers[1].load_force / 1000.0,
		level.stabilizers[1].clamp_force / 1000.0,
		level.stabilizers[1].ram_velocity,
		"STALL" if level.stabilizers[1].stalled else "ok"]
	lines += "CATWALK tilt %.3f  pins %d  preload %.2f  surge %s %.1fs\n" % [level.catwalk.tilt, level.catwalk.pins_seated, level.catwalk.preload_state, surge.state, surge.warning_left]
	lines += "ISO pin=%s prog=%.2f  |  GATE %s\n" % [str(level.isolation.pin_out), level.isolation.progress, str(session.can_finish())]
	for pid in session.ledger.player_ids():
		lines += "  P%d %s %s\n" % [pid, session.ledger.display_name(pid), str(session.ledger.get_record(pid).get("phases", {}))]
	lines += "OPERATING %s  target %s  grab %s\n" % [str(player.operating), str(player.current_target.name if player.current_target != null else "none"), str(player.grabbing)]
	lines += "PROMPT %s\n" % _last_prompt
	lines += "COLLIDERS %d  MESHES %d  LIGHTS %d  TRIS %d\n" % [int(level.kit.stats["colliders"]), int(level.kit.stats["meshes"]), int(level.kit.stats["lights"]), int(level.kit.stats["triangles"])]
	lines += "BLOCKS %d  %s\n" % [player.block_events, player.get_block_text()]
	lines += "GPU %s" % RenderingServer.get_video_adapter_name()
	return lines
