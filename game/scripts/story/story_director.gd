class_name StoryDirector
extends Node

## Mission progression for Resonance 05. Every stage change is derived from a
## real mechanical state (core capturable, claw locked, coupling separated, data
## object taken) instead of a free-form success flag.

enum Stage {
	ENTER_CORE,
	DISCOVER_INSTABILITY,
	BALANCE_CORE,
	CAPTURE_READY,
	LOCK_CORE,
	DISCOVER_FEEDBACK,
	ISOLATE_EXTRACTION_LINK,
	RECOVER_NAVIGATION_DATA,
	EVACUATE,
	COMPLETED,
}

signal stage_changed(stage: int)
signal checkpoint_changed(index: int)
signal run_completed(summary: Dictionary)

const CP_POSITIONS: Array[Vector3] = [
	Vector3(0, 4.06, 38.0),
	Vector3(0, 4.06, 12.6),
	Vector3(0, 0.06, 8.4),
	Vector3(10.8, 0.06, -6.0),
]
const CP_YAWS: Array[float] = [0.0, 0.0, 0.0, PI * 0.5]

var level: LevelBuilder
var hud: GameHud
var audio: AudioDirector
var player: PlayerController
var core: CoreRig
var stage: int = Stage.ENTER_CORE
var checkpoint: int = 0
var lock_attempts: int = 0
var surges: int = 0
var start_time: float = 0.0
var completion_time: float = 0.0
var data_taken: bool = false
var memory_watched: bool = false
var intro_done: bool = false
var _balance_tutorial: bool = false
var _lock_snapshot_left: float = 0.12
var _lock_snapshot_right: float = 0.88
var _feedback_busy: bool = false
var _isolation_busy: bool = false
var _completed: bool = false
var _last_surge_line: float = -10.0
var _last_stage_text: String = ""
var session: CoopSession
var surge: SurgeDirector
var _end_text: String = ""
var _remote_mode: bool = false


func setup(p_level: LevelBuilder, p_hud: GameHud, p_audio: AudioDirector, p_player: PlayerController, p_session: CoopSession = null) -> void:
	level = p_level
	hud = p_hud
	audio = p_audio
	player = p_player
	session = p_session
	core = level.core
	start_time = 0.0
	_connect()


func _connect() -> void:
	level.hall_entered.connect(_on_hall_entered)
	level.core_lock_event.connect(_on_core_locked)
	level.isolation_event.connect(_on_isolation_done)
	level.data_event.connect(_on_data_taken)
	level.exit_reached.connect(_on_exit_reached)
	level.lock_rig.lock_attempt_failed.connect(_on_lock_failed)
	core.lock_started.connect(_on_lock_started)
	core.surge_shock.connect(_on_surge)
	level.left_station.cart_moved.connect(_on_cart_moved)
	level.right_station.cart_moved.connect(_on_cart_moved)
	level.left_station.lever_engaged.connect(_on_lever_engaged)
	level.right_station.lever_engaged.connect(_on_lever_engaged)
	level.memory.memory_started.connect(_on_memory_started)
	level.terminals[0].log_requested.connect(_on_log_requested)
	level.isolation.message.connect(_on_system_message)
	level.push_door.opened.connect(_on_door_open)


func begin() -> void:
	start_time = float(Time.get_ticks_msec()) / 1000.0
	stage = Stage.ENTER_CORE
	checkpoint = 0
	_set_objective_for_stage()
	hud.show_title("穿越被切断的矿层，完成矿工当年没能做完的事。", 6.5)
	hud.subtitle("第 46 天：别让车下去。晶体在记账。", "老宋 · 最后一条维护记录", 5.2)
	hud.subtitle("我们沿着断轨走进了 R-05 深层设施。深处的机械声一直没有停过。", "远征队", 5.0)
	hud.toast("WASD 移动 · E 交互 · F1 操作说明", 5.0)
	intro_done = true


func _process(delta: float) -> void:
	if level == null:
		return
	if not _completed:
		_update_capture_stage()
		if audio != null:
			audio.set_tension(level.core_instability if stage >= Stage.DISCOVER_INSTABILITY else 0.0)
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	if core != null and core.surge_timer > 0.0 and t - _last_surge_line > 6.0 and not _completed:
		_last_surge_line = t
		hud.subtitle("共振冲击！配重过冲了，反向推动手柄修正。", "七号", 4.2)


func _update_capture_stage() -> void:
	if core == null or core.is_locked():
		return
	if stage == Stage.BALANCE_CORE and core.is_capturable() and core.lock_interlock_reason() == "":
		_set_stage(Stage.CAPTURE_READY)
		hud.toast("核心进入捕获范围，稳定支腿已锁定", 2.6)
	elif stage == Stage.CAPTURE_READY and (not core.is_capturable() or core.lock_interlock_reason() != ""):
		_set_stage(Stage.BALANCE_CORE)


func _set_stage(new_stage: int) -> void:
	if stage == new_stage:
		return
	stage = new_stage
	_set_objective_for_stage()
	stage_changed.emit(stage)


func _set_objective_for_stage() -> void:
	var text: String = ""
	match stage:
		Stage.ENTER_CORE:
			text = "深入 R-05 设施，前往地心共振大厅"
		Stage.DISCOVER_INSTABILITY:
			text = "观察失稳的共振核心。大厅里现在有两处稳定支腿、一段维修栈桥和应急制动"
		Stage.BALANCE_CORE:
			text = "分头行动：把两侧稳定支腿泵到锁止，同时用配重把核心压进捕获范围"
		Stage.CAPTURE_READY:
			text = "捕获条件已满足（支腿 2/2）— 到中央控制台启动锁爪"
		Stage.LOCK_CORE:
			text = "液压锁爪正在闭合…"
		Stage.DISCOVER_FEEDBACK:
			text = "采掘回路仍在回注振动 — 东侧隔离区的阻尼器必须先加载"
		Stage.ISOLATE_EXTRACTION_LINK:
			text = "一人加载回路阻尼器，另一人拔销并推动滑架分离联轴器"
		Stage.RECOVER_NAVIGATION_DATA:
			text = "取回显现的深空航行数据"
		Stage.EVACUATE:
			text = "从西侧紧急撤离通道离开"
		Stage.COMPLETED:
			text = "共振星 · 地心的回声 — 完成"
	if session != null and stage != Stage.COMPLETED and session.is_host:
		var gate: String = session.gate_text()
		if gate != "":
			text += "\n参与缺口：" + gate
	if text != _last_stage_text:
		_last_stage_text = text
		hud.set_objective(text)


func _on_door_open() -> void:
	hud.toast("检查点：入口通道已打开", 2.2)


func _on_hall_entered() -> void:
	if stage >= Stage.DISCOVER_INSTABILITY:
		return
	_set_stage(Stage.DISCOVER_INSTABILITY)
	checkpoint = 1
	checkpoint_changed.emit(checkpoint)
	hud.toast("检查点：地心共振大厅", 3.0)
	hud.subtitle("……这就是矿工拼命想封住的东西。", "远征队", 4.0)
	hud.subtitle("核心还在转。每转一圈，整座大厅都跟着响。", "七号", 4.4)
	if audio != null:
		audio.play_sfx("metal_clank", Vector3(0, 5, 8), -6.0)


func _on_lever_engaged() -> void:
	if stage == Stage.DISCOVER_INSTABILITY:
		_set_stage(Stage.BALANCE_CORE)
	if not _balance_tutorial:
		_balance_tutorial = true
		hud.subtitle("配重小车连着核心的平衡环。推动手柄，观察核心怎么回应。", "七号", 4.6)
		hud.subtitle("松开手柄后小车还有惯性；反向推可以修正。", "七号", 4.0)
		if audio != null:
			audio.play_sfx("lever_click", Vector3(0, 2, 6), -5.0)


func _on_cart_moved(_p: float) -> void:
	if stage == Stage.DISCOVER_INSTABILITY:
		_set_stage(Stage.BALANCE_CORE)


func _on_lock_started() -> void:
	_lock_snapshot_left = level.left_cart.get_p()
	_lock_snapshot_right = level.right_cart.get_p()
	_set_stage(Stage.LOCK_CORE)


func _on_lock_failed(reason: String) -> void:
	lock_attempts += 1
	hud.subtitle("捕获失败：%s。锁爪已退回，请继续修正配重。" % reason, "液压锁爪", 4.6)
	if audio != null:
		audio.play_sfx("lock_fail", Vector3(0, 1.2, 6.5), -1.0)


func _on_core_locked() -> void:
	checkpoint = 2
	checkpoint_changed.emit(checkpoint)
	_set_stage(Stage.DISCOVER_FEEDBACK)
	hud.toast("检查点：核心机械锁定", 3.0)
	hud.subtitle("锁爪咬住了核心。摆动在下降——", "远征队", 3.2)
	await get_tree().create_timer(1.8).timeout
	if checkpoint < 2 or _completed:
		return
	hud.subtitle("警告：另一条采掘回路仍在向核心回注振动。", "七号", 4.2)
	hud.subtitle("必须切断东侧的联轴器，否则锁爪会被震开。", "七号", 4.4)


func _on_isolation_done() -> void:
	if _completed:
		return
	checkpoint = 3
	checkpoint_changed.emit(checkpoint)
	_set_stage(Stage.ISOLATE_EXTRACTION_LINK)
	hud.toast("检查点：采掘回路已隔离", 3.0)
	hud.subtitle("联轴器分离。回注振动正在衰减。", "七号", 3.6)
	await get_tree().create_timer(1.6).timeout
	if checkpoint < 3 or _completed:
		return
	core.set_data_mode(true)
	level.data_plinth.reveal()
	hud.subtitle("核心的振动降到了安全阈值……晶体里有东西在回应。", "远征队", 3.8)
	hud.subtitle("导航数据正在显现。坐标指向星图之外。", "七号", 4.0)
	_set_stage(Stage.RECOVER_NAVIGATION_DATA)
	level.set_conduit_powered(false)


func _on_data_taken() -> void:
	if data_taken:
		return
	data_taken = true
	if session != null and session.is_host:
		session.credit(session.local_pid, "data_take", 1.0, "取出深空航行数据")
	_set_stage(Stage.EVACUATE)
	hud.subtitle("深空航行坐标已写入。", "七号", 3.2)
	hud.subtitle("老宋他们守住的东西，我们带走了。", "远征队", 4.0)
	level.exit_door.open_door()
	hud.toast("西侧紧急撤离通道已解锁", 3.0)


func _on_surge(_strength: float) -> void:
	surges += 1


func _on_memory_started() -> void:
	memory_watched = true
	hud.subtitle("第 44 天：不是矿石的问题。核心在把振动聚起来，又在放大。", "老宋 · 维护记录", 5.2)
	hud.subtitle("他们不是在躲什么怪物。是我们自己修的采掘机，把地心的振动一圈圈放大。", "老宋 · 维护记录", 5.4)
	hud.subtitle("记录显示：矿工切断了运输轨道，但没有摧毁核心。核心里保存着一份深空航行数据。", "七号", 5.6)
	hud.subtitle("把它留下来。也许有一天，会有人需要它。", "老宋 · 维护记录", 4.8)
	if audio != null:
		audio.play_sfx("memory", level.memory.global_position, -3.0)


func _on_log_requested(title: String, lines: Array) -> void:
	for line in lines:
		hud.subtitle(str(line), title, 5.4)
	hud.toast("维护日志已读取", 2.2)


func _on_system_message(text: String) -> void:
	hud.subtitle(text, "系统", 3.6)


func _on_exit_reached() -> void:
	if _completed:
		return
	if _remote_mode:
		return
	if not data_taken:
		hud.subtitle("闸门仍然闭锁。先把导航数据带走。", "系统", 3.0)
		return
	# Participation gate: the physical objectives are done, but the finale is a
	# crew result. Every effective participant has to have done real work in all
	# three phases; the board and the HUD name exactly what is missing.
	if session != null and not session.can_finish():
		var report: Dictionary = session.completion_report()
		var lines: Array[String] = []
		for entry in report.get("missing", []):
			var info: Dictionary = entry as Dictionary
			var miss: Array = info.get("missing", [])
			var first: String = str(miss[0]) if miss.size() > 0 else ""
			lines.append("%s：%s" % [str(info.get("name", "?")), first])
		hud.show_alert("还不能收队", 3.4)
		hud.subtitle("撤离闸门被联锁：还有队友没有完成本幕的实质工作。", "系统", 4.0)
		for line in lines:
			hud.subtitle(line, "全员参与", 4.2)
		hud.toast("机械目标已完成，但全员参与尚未满足", 3.4)
		return
	_completed = true
	completion_time = float(Time.get_ticks_msec()) / 1000.0
	_set_stage(Stage.COMPLETED)
	var elapsed: float = completion_time - start_time
	var minutes: int = int(elapsed) / 60
	var seconds: int = int(elapsed) % 60
	var lines: String = "核心已稳定，采掘回路已隔离，深空导航数据已录入飞船。\n\n"
	lines += "我们终于明白，老宋他们切断轨道，不是为了逃跑，而是为了把最后一份希望留在下面。\n\n"
	lines += "下一站：星图之外的信号源。\n\n"
	lines += "用时 %d:%02d    锁定尝试 %d 次    共振冲击 %d 次\n\n" % [minutes, seconds, lock_attempts, surges]
	lines += _participation_lines()
	_end_text = lines
	hud.clear_subtitles()
	hud.show_end(lines)
	hud.fade(0.55, 1.6)
	if audio != null:
		audio.play_sfx("data_take", Vector3.ZERO, -2.0)
		audio.set_tension(0.0)
	player.mouse_enabled = false
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var summary: Dictionary = {
		"elapsed": elapsed,
		"lock_attempts": lock_attempts,
		"surges": surges,
		"checkpoint": checkpoint,
		"memory_watched": memory_watched,
		"participants": session.completion_report() if session != null else {},
	}
	run_completed.emit(summary)


func _participation_lines() -> String:
	if session == null:
		return ""
	var report: Dictionary = session.completion_report()
	var parts: Array[String] = ["全员参与记录："]
	for entry in report.get("ready", []):
		var info: Dictionary = entry as Dictionary
		var phases: Dictionary = info.get("phases", {})
		parts.append("  %s  完成 A%d / B%d / C%d" % [str(info.get("name", "?")), int(phases.get("A", 0)), int(phases.get("B", 0)), int(phases.get("C", 0))])
	for entry in report.get("spectators", []):
		var info2: Dictionary = entry as Dictionary
		parts.append("  观战：%s" % str(info2.get("name", "?")))
	for entry in report.get("disconnected", []):
		var info3: Dictionary = entry as Dictionary
		parts.append("  离线：%s（不计入完成）" % str(info3.get("name", "?")))
	return "\n".join(parts)


func reset_to_checkpoint() -> void:
	_completed = false
	hud.clear_subtitles()
	hud.show_end_hidden()
	hud.fade(0.0, 0.4)
	player.set_physics_process(true)
	player.mouse_enabled = true
	player.force_exit_operate()
	level.push_door.reset_state()
	level.lock_rig.reset_state()
	level.isolation.reset_state()
	level.data_plinth.reset_state()
	level.exit_door.reset_state()
	level.memory.reset_state()
	for terminal in level.terminals:
		terminal.reset_state()
	if level.catwalk != null:
		level.catwalk.reset_state()
	for stab in level.stabilizers:
		stab.reset_state()
	if level.brake != null:
		level.brake.reset_state()
	if level.damper != null:
		level.damper.reset_state()
	if surge != null:
		surge.reset_state()
	level.set_alarm(false)
	data_taken = false
	_stage_force_for_checkpoint()
	var left_p: float = 0.12
	var right_p: float = 0.88
	if checkpoint >= 2:
		left_p = _lock_snapshot_left
		right_p = _lock_snapshot_right
	level.left_station.reset_state(left_p)
	level.right_station.reset_state(right_p)
	core.set_weights(left_p, right_p)
	core.reset_state()
	core.set_data_mode(false)
	level.set_conduit_powered(false)
	if checkpoint >= 1:
		level.push_door.force_open()
	if checkpoint >= 2:
		core.force_locked_state()
		level.lock_rig.force_locked_visual()
		level.set_conduit_powered(true)
	if checkpoint >= 3:
		level.isolation.force_separated_state()
		core.set_data_mode(true)
		level.data_plinth.reveal()
		level.set_conduit_powered(false)
	if checkpoint >= 3:
		_set_stage(Stage.RECOVER_NAVIGATION_DATA)
	elif checkpoint >= 2:
		_set_stage(Stage.DISCOVER_FEEDBACK)
	elif checkpoint >= 1:
		_set_stage(Stage.DISCOVER_INSTABILITY)
	else:
		_set_stage(Stage.ENTER_CORE)
	var pos: Vector3 = CP_POSITIONS[clampi(checkpoint, 0, CP_POSITIONS.size() - 1)]
	var yaw: float = CP_YAWS[clampi(checkpoint, 0, CP_YAWS.size() - 1)]
	player.teleport(pos, yaw, -0.05)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.toast("已回到检查点 %d" % checkpoint, 2.4)
	if audio != null:
		audio.stop_all_loops()


func _stage_force_for_checkpoint() -> void:
	pass


func reset_stage_for_full_restart() -> void:
	stage = Stage.ENTER_CORE
	checkpoint = 0
	lock_attempts = 0
	surges = 0
	_completed = false


func _set_lock_snapshot(left_p: float, right_p: float) -> void:
	_lock_snapshot_left = left_p
	_lock_snapshot_right = right_p


# ---------------------------------------------------------------------------
# Network / remote presentation
# ---------------------------------------------------------------------------

## Client-side: the host owns the stage. Apply it without replaying story beats
## twice, and keep objectives / UI in sync.
func apply_network_stage(new_stage: int, new_checkpoint: int) -> void:
	_remote_mode = true
	var changed_stage: bool = new_stage != stage
	stage = new_stage
	if new_checkpoint != checkpoint:
		checkpoint = new_checkpoint
		checkpoint_changed.emit(checkpoint)
	if new_stage >= Stage.EVACUATE:
		data_taken = true
	elif new_stage < Stage.EVACUATE:
		data_taken = false
	if changed_stage:
		_set_objective_for_stage()
		if new_stage == Stage.COMPLETED:
			pass
	if new_stage >= Stage.RECOVER_NAVIGATION_DATA and new_stage < Stage.COMPLETED:
		if level != null and not level.data_plinth.revealed_flag:
			level.data_plinth.reveal()
			if level.core != null:
				level.core.set_data_mode(true)
	if new_stage >= Stage.EVACUATE and level != null:
		if not level.exit_door.is_opened:
			level.exit_door.open_door()


## Client-side finale. The host composes the crew report (participation ledger,
## lock attempts, surcharge count); the client mirrors that exact text instead of
## inventing a local summary, so both screens tell the same story.
func apply_network_completion(text: String) -> void:
	_remote_mode = true
	var fresh: bool = text != _end_text
	_completed = true
	_end_text = text
	if stage != Stage.COMPLETED:
		stage = Stage.COMPLETED
	if fresh and hud != null:
		hud.clear_subtitles()
		hud.show_end(text)


func apply_network_reset() -> void:
	_completed = false
	_end_text = ""
	hud.show_end_hidden()
	hud.clear_subtitles()
	hud.fade(0.0, 0.4)
	player.set_physics_process(true)
	player.mouse_enabled = true


func completed_flag() -> bool:
	return _completed


func completion_text() -> String:
	return _end_text
