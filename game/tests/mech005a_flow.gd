extends SceneTree

## MECHANICS-005A · 第五幕端到端（窗口 B）
##
##   godot --headless --path game --script res://tests/mech005a_flow.gd
##
## 从正式入口 res://scenes/main.tscn 直接开跑（不注入第四幕 payload，不依赖
## 窗口 A 的 004C 出口门），全程只用真实输入：E 交互、W 泵压/推杆、S 反向。
## 覆盖：进入地心大厅 → 反冲预警 → 双侧支腿真实泵压锁止 → 配重把核心压进
## 捕获窗口 → 液压锁爪 → 阻尼器 → 拔销 + 滑架分离 → 深空航行数据 → 撤离闸门
## → 第五幕结算写账本 → 进入既有结局场景。
##
## 不写 completed、不写 data_taken、不直接设置 latched/机械状态。

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var core: CoreRig
var session: CoopSession
var surge: SurgeDirector
var hud: GameHud
var hub: Node

var checks: Array[Dictionary] = []
var failures: int = 0
var started_ms: int = 0
var legs: Array[StabilizerRig] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	started_ms = Time.get_ticks_msec()
	hub = root.get_node_or_null("/root/SessionHub")
	if hub == null:
		_fail("F0", "SessionHub autoload 缺失")
		_finish()
		return
	# 干净起点：本次从第五幕正式入口直接进入，不伪造任何第四幕交接。
	hub.set("chapter_progress", {})
	hub.set("pending_spawn", {})
	hub.set("current_chapter", "act04")
	var hist: Dictionary = (hub.get("chapter_history") as Dictionary).duplicate(true)
	for key in hist.keys():
		hist[key] = {}
	hub.set("chapter_history", hist)

	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	app = packed.instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await _frames(90)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	hud = app.get("hud") as GameHud
	surge = app.get("surge") as SurgeDirector
	session = app.get("session") as CoopSession
	core = level.get("core") as CoreRig
	legs = level.stabilizers
	if hud != null:
		hud.title_layer.visible = false

	_check("F1 第五幕正式入口可独立加载（不依赖第四幕交接，玩家在正式出生点，章节标为 act05）",
		level.is_inside_tree() and player.is_inside_tree() and bool(app.get("handoff_consumed"))
			and not bool(app.get("spawn_from_payload"))
			and str(hub.get("current_chapter")) == "act05",
		"consumed=%s payload_spawn=%s chapter=%s pos=%s" % [
			str(app.get("handoff_consumed")), str(app.get("spawn_from_payload")),
			str(hub.get("current_chapter")), str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])

	# --- 1 进入地心大厅 -----------------------------------------------------
	await _stand(Vector3(0, 4.06, 12.2), Vector3(0, 4.06, 0))
	var entered: bool = await _wait_until(func() -> bool:
		return story.stage >= StoryDirector.Stage.DISCOVER_INSTABILITY, 6.0)
	_check("F2 玩家走进地心共振大厅（入口触发体推进阶段机）", entered, "stage=%d" % story.stage)

	# --- 2 配重（真实手柄）把核心压向捕获窗口 --------------------------------
	await _stand(Vector3(8.5, 1.70, 7.47), level.right_station.area.global_position)
	await _press_interact()
	await _hold("move_back", 9.0)
	await _press_interact()
	_check("F3 配重手柄真实改变核心力矩（右车向内，|net| 明显下降，阶段 A 记入账本）",
		absf(core.get_net()) < 0.30 and session.ledger.has_credit(1, "counterweight_effect"),
		"net=%.3f" % core.get_net())

	# --- 3 反冲预警：抓栏杆 → 阶段 B ----------------------------------------
	await _stand(Vector3(-10.4, 3.50, -3.95), Vector3(-11.1, 4.45, -3.45))
	var grabbed: bool = false
	for _attempt in range(3):
		await _press_interact()
		grabbed = player.grabbing
		if grabbed:
			break
		await _stand(Vector3(-10.4, 3.50, -3.95), Vector3(-11.1, 4.45, -3.45))
	var surged: bool = await _wait_until(func() -> bool: return surge.surge_count >= 1, 45.0)
	if player.grabbing:
		await _press_interact()
	_check("F4 真实反冲冲击发生，抓栏杆产生阶段 B 的实际防护记录",
		grabbed and surged and session.ledger.has_credit(1, "surge_response"),
		"grab=%s surges=%d" % [str(grabbed), surge.surge_count])

	# --- 4 双侧稳定支腿：真实泵压 -------------------------------------------
	await _latch_leg(0, "西")
	await _latch_leg(1, "东")
	var limit: float = core.capture_net_limit()
	_check("F5 两条支腿依次真实泵压到止挡并落棘爪（单人可完成，捕获窗口按夹持力放宽到 ±0.25）",
		legs[0].latched and legs[1].latched and level.stabilizers_latched() == 2
			and absf(limit - 0.25) < 1.0e-4,
		"w=%s e=%s limit=%.4f clamp=%.1f/%.1f kN" % [str(legs[0].latched), str(legs[1].latched),
			limit, legs[0].clamp_force / 1000.0, legs[1].clamp_force / 1000.0])

	# --- 5 把核心压进捕获范围 ------------------------------------------------
	await _balance_into_window()
	var capturable: bool = await _wait_until(func() -> bool: return core.is_capturable(), 15.0)
	_check("F6 核心进入捕获范围（|net| 与 |omega| 都由真实机械状态决定，阶段机进入 CAPTURE_READY）",
		capturable and story.stage == StoryDirector.Stage.CAPTURE_READY
			and absf(core.get_net()) <= limit,
		"capturable=%s stage=%d net=%.3f omega=%.3f limit=%.3f" % [str(capturable), story.stage,
			core.get_net(), core.get_omega(), limit])

	# --- 6 液压锁爪 ---------------------------------------------------------
	await _stand(Vector3(0, 0.06, 10.1), Vector3(0, 1.2, 8.6))
	await _press_interact()
	var locked: bool = await _wait_until(func() -> bool: return core.is_locked(), 8.0)
	_check("F7 液压锁爪在真实可捕获状态下闭合（锁爪控制台 E，两条支腿是硬联锁）",
		locked and session.ledger.has_credit(1, "lock_assist"),
		"locked=%s stage=%d" % [str(locked), story.stage])

	# --- 7 阻尼器 -----------------------------------------------------------
	await _wait_until(func() -> bool: return story.stage >= StoryDirector.Stage.DISCOVER_FEEDBACK, 8.0)
	await _stand(Vector3(6.4, 0.06, -2.3), Vector3(6.4, 1.2, -4.4))
	await _press_interact()
	await _hold("move_forward", 2.8)
	var damped: bool = await _wait_until(func() -> bool: return level.damper.latched_flag, 6.0)
	if player.operating:
		await _press_interact()
	_check("F8 回路阻尼器正常加载（未受支腿改造影响）", damped,
		"pressure=%.2f" % level.damper.pressure)

	# --- 8 隔离销 + 滑架 ----------------------------------------------------
	await _stand(Vector3(10.7, 0.06, -5.0), Vector3(10.6, 1.3, -8.6))
	await _press_interact()
	var pin_out: bool = await _wait_until(func() -> bool: return level.isolation.pin_out, 6.0)
	var ready: bool = await _wait_until(func() -> bool: return level.damper.damper_effect() >= 0.35, 10.0)
	var operating: bool = false
	for _attempt in range(6):
		await _stand(Vector3(10.7, 0.06, -5.0), Vector3(10.6, 1.3, -8.6))
		await _press_interact()
		operating = await _wait_until(func() -> bool: return player.operating, 2.5)
		if operating:
			break
		await _frames(30)
	await _hold("move_forward", 5.5)
	var separated: bool = await _wait_until(func() -> bool: return level.isolation.separated_flag, 10.0)
	_check("F9 拔出隔离销并推动滑架分离联轴器（阻尼器必须先加载，联锁未放宽）",
		pin_out and ready and separated and session.ledger.has_credit(1, "isolation_pin")
			and session.ledger.has_credit(1, "carriage_push"),
		"pin=%s damper=%.2f separated=%s" % [str(pin_out), level.damper.damper_effect(), str(separated)])

	# --- 9 深空航行数据 -----------------------------------------------------
	await _wait_until(func() -> bool: return story.stage >= StoryDirector.Stage.RECOVER_NAVIGATION_DATA, 10.0)
	await _stand(Vector3(-3.0, 0.06, -8.0), Vector3(-3.0, 1.0, -9.1))
	await _press_interact()
	var data_ok: bool = await _wait_until(func() -> bool: return story.data_taken, 8.0)
	var door_open: bool = await _wait_until(func() -> bool: return level.exit_door.is_opened, 4.0)
	_check("F10 深空航行数据仍可获取（数据基座交互，撤离闸门由门自己的行程打开）",
		data_ok and story.stage >= StoryDirector.Stage.EVACUATE and door_open,
		"data=%s stage=%d door=%s" % [str(data_ok), story.stage, str(door_open)])

	# --- 10 撤离 → 结算 ----------------------------------------------------
	var phases: Dictionary = session.ledger.get_record(1).get("phases", {}) as Dictionary
	_check("F11 单人走完 A/B/C 三阶段实质工作（阶段账本由机械发放，无脚本代签）",
		int(phases.get("A", 0)) > 0 and int(phases.get("B", 0)) > 0 and int(phases.get("C", 0)) > 0
			and session.can_finish(),
		"phases=%s can_finish=%s" % [str(phases), str(session.can_finish())])

	# Capture the machine evidence before the scene switch frees the level.
	var evidence: Dictionary = {
		"legs": [legs[0].snapshot(), legs[1].snapshot()],
		"net": core.get_net(),
		"omega": core.get_omega(),
		"limit": core.capture_net_limit(),
		"friction_torque_knm": core.stabilizer_friction_torque() / 1000.0,
		"stabilizer_states": core.stabilizer_states.duplicate(),
		"clamp_kn": [legs[0].clamp_force / 1000.0, legs[1].clamp_force / 1000.0],
	}

	var before: Dictionary = _act05_record()
	await _stand(Vector3(-25.5, 0.06, -2.0), Vector3(-27.5, 1.2, -2.0))
	var completed: bool = await _wait_until(func() -> bool:
		return story.stage == StoryDirector.Stage.COMPLETED, 12.0)
	var stage_at_finish: int = story.stage if is_instance_valid(story) else -1
	var recorded: bool = await _wait_until(func() -> bool: return not _act05_record().is_empty(), 12.0)
	evidence["stage_at_finish"] = stage_at_finish
	_check("F12 穿越撤离闸门完成第五幕（完成由剧情门与参与度门共同判定，测试未写 completed）",
		completed and recorded and before.is_empty(),
		"stage=%d recorded=%s before_empty=%s" % [stage_at_finish, str(recorded), str(before.is_empty())])

	var switched: bool = await _wait_until(func() -> bool:
		return current_scene != null and current_scene != app, 20.0)
	var finale_name: String = str(current_scene.name) if current_scene != null else "null"
	var finale_text: String = _collect_label_text(current_scene)
	_check("F13 第五幕结算把章节记录写入 SessionHub 并切到既有结局场景（结局把 Act05 行标为已完成）",
		switched and str(hub.get("current_chapter")) == "finale"
			and bool(_act05_record().get("completed", false))
			and finale_text.contains("●") and finale_text.contains("Act05"),
		"scene=%s chapter=%s act05=%s text=%.70s" % [finale_name, str(hub.get("current_chapter")),
			str(_act05_record().get("completed", false)), finale_text.replace("\n", " ")])

	var rec: Dictionary = _act05_record()
	_check("F14 结算 payload 由真实运行推导（用时/共振次数/参与度/数据标记俱全）",
		float(rec.get("seconds", 0.0)) > 5.0 and int(rec.get("surges", 0)) >= 1
			and bool(rec.get("story_completed", false)) and bool(rec.get("data_taken", false)),
		"seconds=%.1f surges=%d story_completed=%s data_taken=%s" % [float(rec.get("seconds", 0.0)),
			int(rec.get("surges", 0)), str(rec.get("story_completed", false)),
			str(rec.get("data_taken", false))])

	evidence["elapsed_test_seconds"] = float(Time.get_ticks_msec() - started_ms) / 1000.0
	evidence["finale_scene"] = finale_name
	evidence["act05"] = rec
	print("FLOW_EVIDENCE " + JSON.stringify(evidence))
	_finish()


# ---------------------------------------------------------------- 机械工序
func _latch_leg(index: int, side: String) -> void:
	var leg: StabilizerRig = legs[index]
	for attempt in range(4):
		await _stand_at_leg(index)
		await _press_interact()
		if not player.operating:
			await _frames(20)
			continue
		Input.action_press("move_forward")
		for _i in range(320):
			await physics_frame
			if leg.latched:
				break
		Input.action_release("move_forward")
		await _frames(3)
		if player.operating:
			await _press_interact()
		if leg.latched:
			break
	print("LEG %s latched=%s ext=%.4f clamp=%.1f kN load=%.1f kN stall=%s" % [side,
		str(leg.latched), leg.extension, leg.clamp_force / 1000.0, leg.load_force / 1000.0,
		str(leg.stalled)])


func _balance_into_window() -> void:
	for _try in range(7):
		if core.is_capturable():
			break
		await _stand(Vector3(8.5, 1.70, 7.47), level.right_station.area.global_position)
		await _press_interact()
		var dir: String = "move_back" if core.get_net() > 0.0 else "move_forward"
		await _hold(dir, 1.6)
		await _press_interact()
		await _wait(0.8)


# ---------------------------------------------------------------- 工具
func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _wait(seconds: float) -> void:
	var count: int = maxi(1, int(round(seconds * 60.0)))
	for _i in range(count):
		await physics_frame


func _wait_until(cond: Callable, timeout: float) -> bool:
	var budget: int = maxi(1, int(round(timeout * 60.0)))
	for _i in range(budget):
		if bool(cond.call()):
			return true
		await physics_frame
	return bool(cond.call())


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d: Vector3 = to - from
	return atan2(-d.x, -d.z)


func _pitch_to(from: Vector3, to: Vector3) -> float:
	var flat: float = Vector2(to.x - from.x, to.z - from.z).length()
	return -atan2(to.y - (from.y + 1.62), flat)


func _stand(pos: Vector3, target: Vector3) -> void:
	player.force_exit_operate()
	player.stop_grab()
	player.external_hold = false
	player.teleport(pos, _yaw_to(pos, target), clampf(_pitch_to(pos, target), -1.1, 1.1))
	await _frames(10)


func _stand_at_leg(index: int) -> void:
	var leg: StabilizerRig = legs[index]
	await _stand(leg.anchor.origin + Vector3(0, 0, -0.6), leg.global_position + Vector3(0, 1.2, 0))


func _press_interact() -> void:
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	await _frames(3)


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	await _frames(3)


func _act05_record() -> Dictionary:
	var hist: Dictionary = hub.get("chapter_history") as Dictionary
	var rec: Variant = hist.get("act05", {})
	if rec is Dictionary:
		return rec as Dictionary
	return {}


func _collect_label_text(node: Node) -> String:
	var text: String = ""
	if node == null:
		return text
	if node is Label:
		text += (node as Label).text + "\n"
	for child in node.get_children():
		text += _collect_label_text(child)
	return text


func _check(label: String, ok: bool, detail: String) -> void:
	checks.append({"check": label, "ok": ok, "detail": detail})
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + (("  |  " + detail) if detail != "" else ""))


func _fail(tag: String, detail: String) -> void:
	checks.append({"check": tag, "ok": false, "detail": detail})
	failures += 1
	print("FAIL  %s  %s" % [tag, detail])


func _finish() -> void:
	print("MECH005A_FLOW_RESULT checks=%d passed=%d failures=%d elapsed=%.1fs" % [
		checks.size(), checks.size() - failures, failures,
		float(Time.get_ticks_msec() - started_ms) / 1000.0])
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(dir.path_join("mech005a_flow.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
		file.close()
	quit(0 if failures == 0 else 1)
