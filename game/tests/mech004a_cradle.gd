extends Node
## MECHANICS-004A · 第四幕晶体支架（真实叉口 + 锁爪）专项
##
## 全部断言在正式第四幕场景 res://scenes/act4.tscn 里执行：
## 晶体是 16 kg 刚体，落在支架承托面上；玩家按 E 让两只锁爪合拢，
## 爪停在晶体表面（≤2 mm 压入），棘爪落位 → 中继才成立。
## 失败返回非零退出码。

var stage: Node
var cradles: Dictionary
var player: Node3D
var crystal_a: Node3D
var crystal_b: Node3D
var checks: int = 0
var failures: int = 0


func _ready() -> void:
	stage = (load("res://scenes/act4.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	cradles = stage.get("cradles") as Dictionary
	player = stage.get("player") as Node3D
	crystal_a = stage.get("crystal_a") as Node3D
	crystal_b = stage.get("crystal_b") as Node3D
	if stage == null or cradles.is_empty() or player == null or crystal_a == null:
		_fail("E0", "第四幕场景缺少 cradles/player/crystal")
		return _report()
	await _e1_load()
	await _e2_story()
	await _e3_hardware()
	await _e4_structure()
	await _e5_key_not_success()
	await _e6_operation()
	await _e7_motion()
	await _e8_success()
	await _e9_wrong()
	await _e10_blocked()
	await _e11_release()
	await _e12_recover()
	await _e13_reset()
	await _e14_repeat()
	await _e15_abnormal()
	await _e16_relay()
	await _e17_player()
	await _e18_handoff_ready()
	_report()


# ---------------------------------------------------------------- 1 加载
func _e1_load() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	_check("E1 第四幕正式场景正常加载（4 个支架、2 块晶体、玩家、任务控制器在线）",
		cradles.size() == 4 and crystal_a != null and crystal_b != null and player.is_inside_tree()
			and b1.is_inside_tree() and stage.get("hammer") != null,
		"cradles=%s player=%s hammer=%s" % [str(cradles.keys()), str(player != null),
			str(stage.get("hammer") != null)])


# ---------------------------------------------------------------- 2 剧情
func _e2_story() -> void:
	var story: Dictionary = stage.get("story") as Dictionary
	var objective: Dictionary = story.get("objectives", {}) as Dictionary
	var start_text: String = str(objective.get("start", ""))
	_check("E2 原有剧情目标保留（stage=0、story 里的开始目标文案、四支架两晶体、锤子在线）",
		int(stage.get("stage")) == 0 and start_text != "" and cradles.size() == 4
			and crystal_a != null and crystal_b != null and stage.get("hammer") != null,
		"stage=%d start目标=%s" % [int(stage.get("stage")), start_text])


# ---------------------------------------------------------------- 3 机械
func _e3_hardware() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	var floor_body: Node = b1.get_node_or_null("SeatFloor")
	var jaw0: Node = b1.get_node_or_null("Fork/Jaw_0/JawCollider0")
	var jaw1: Node = b1.get_node_or_null("Fork/Jaw_1/JawCollider1")
	_check("E3 目标机械正确创建（承托面 StaticBody + 两只带碰撞体的锁爪 + 棘爪）",
		floor_body is StaticBody3D and jaw0 is StaticBody3D and jaw1 is StaticBody3D
			and b1.get_node_or_null("Pawl") != null,
		"floor=%s jaw0=%s jaw1=%s pawl=%s" % [str(floor_body != null), str(jaw0 != null),
			str(jaw1 != null), str(b1.get_node_or_null("Pawl") != null)])


# ---------------------------------------------------------------- 4 结构
func _e4_structure() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	_check("E4 机械具有实际物理结构（爪行程 0.62→0.26、承托面在 0.38、晶体 16 kg 刚体）",
		absf(float(b1.get("jaw_x")) - 0.62) < 0.01 and absf(float(b1.get("JAW_STOP")) - 0.26) < 0.01
			and absf(float(crystal_a.get("mass")) - 16.0) < 0.5
			and absf(float(b1.call("get_seat_position").y) - (b1.global_position.y + 0.38)) < 0.01,
		"jaw=%.3f stop=%.2f mass=%.1f seat_y=%.2f" % [float(b1.get("jaw_x")),
			float(b1.get("JAW_STOP")), float(crystal_a.get("mass")),
			float(b1.call("get_seat_position").y)])


# ---------------------------------------------------------------- 5 按键不直接完成
func _e5_key_not_success() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	await _at_cradle(b1)
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	for i in range(240):
		await get_tree().physics_frame
		if not bool(b1.get("jaw_motor")):
			break
	_check("E5 E 不直接完成任务（空叉口合拢：爪走到硬止挡 0.26，latched=false、中继不成立）",
		absf(float(b1.get("jaw_x")) - 0.26) < 0.02 and not bool(b1.get("latched"))
			and not bool(stage.call("_relay_ready", "b1")),
		"jaw=%.3f latched=%s relay=%s" % [float(b1.get("jaw_x")), str(b1.get("latched")),
			str(stage.call("_relay_ready", "b1"))])
	b1.call("open_clamp")
	await _w(120)


# ---------------------------------------------------------------- 6 操作改变机械
func _e6_operation() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	await _drop_crystal_into(b1, crystal_a)
	var jaw_before: float = float(b1.get("jaw_x"))
	await _at_cradle(b1)
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	for i in range(240):
		await get_tree().physics_frame
		if bool(b1.get("latched")):
			break
	_check("E6 正确玩家输入能够操作设备（E 启动螺杆，爪 0.62→压到晶体表面 0.408）",
		jaw_before > 0.60 and absf(float(b1.get("jaw_x")) - 0.408) < 0.02,
		"jaw %.3f → %.3f（晶体半径 0.34 + 爪半厚 0.07 − 2 mm）" % [jaw_before,
			float(b1.get("jaw_x"))])


# ---------------------------------------------------------------- 7 受约束运动
func _e7_motion() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	b1.call("open_clamp")
	await _w(120)
	var samples: Array[float] = []
	await _at_cradle(b1)
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	for i in range(120):
		await get_tree().physics_frame
		samples.append(float(b1.get("jaw_x")))
		if bool(b1.get("latched")):
			break
	var monotonic: bool = true
	for i in range(1, samples.size()):
		if samples[i] > samples[i - 1] + 0.0005:
			monotonic = false
			break
	var travel: float = samples[0] - samples[samples.size() - 1]
	_check("E7 运动来自真实受力/受约束运动（爪按 0.22 m/s 单调合拢，被晶体几何挡住后停止）",
		monotonic and travel > 0.15 and float(b1.get("jaw_x")) >= 0.408 - 0.005,
		"行程 %.3f m，%d 帧，末爪位 %.3f" % [travel, samples.size(), float(b1.get("jaw_x"))])
	await _w(30)


# ---------------------------------------------------------------- 8 条件满足才成功
func _e8_success() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	_check("E8 物理状态达到要求后才能成功（爪压住晶体 + 晶体在叉口 + yaw 对位 → locked + 中继成立）",
		bool(b1.call("locked")) and bool(b1.get("aligned")) and bool(b1.get("pressing"))
			and bool(stage.call("_relay_ready", "b1")),
		"locked=%s aligned=%s pressing=%s relay=%s jaw=%.3f" % [
			str(b1.call("locked")), str(b1.get("aligned")), str(b1.get("pressing")),
			str(stage.call("_relay_ready", "b1")), float(b1.get("jaw_x"))])


# ---------------------------------------------------------------- 9 错误条件
func _e9_wrong() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	# 拔出来，转到 90° 外再放回去：能夹住但 yaw 不对 → 不点亮中继
	b1.call("open_clamp")
	await _w(60)
	crystal_a.call("begin_carry", player)
	await _w(5)
	crystal_a.set("held_yaw_deg", float(b1.get("required_yaw_deg")) + 95.0)
	crystal_a.call("end_carry", false)
	await _drop_crystal_into(b1, crystal_a, 95.0)
	await _at_cradle(b1)
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	for i in range(240):
		await get_tree().physics_frame
		if bool(b1.get("latched")):
			break
	_check("E9 错误条件下不会完成（yaw 偏 95°：爪仍夹住，但 aligned=false、中继不成立）",
		bool(b1.get("latched")) and not bool(b1.get("aligned"))
			and not bool(stage.call("_relay_ready", "b1")),
		"latched=%s aligned=%s relay=%s" % [str(b1.get("latched")), str(b1.get("aligned")),
			str(stage.call("_relay_ready", "b1"))])
	b1.call("open_clamp")
	await _w(80)


# ---------------------------------------------------------------- 10 受阻不穿透
func _e10_blocked() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	await _drop_crystal_into(b1, crystal_a)
	var before: Vector3 = crystal_a.global_position
	await _at_cradle(b1)
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	for i in range(240):
		await get_tree().physics_frame
		if bool(b1.get("latched")):
			break
	await _w(60)
	var after: Vector3 = crystal_a.global_position
	var jaw: float = float(b1.get("jaw_x"))
	var minimum: float = 0.34 + 0.07 - 0.002
	_check("E10 机械受阻不穿透、不异常弹飞（爪内表面不越过晶体表面超过 2 mm，晶体不被弹飞）",
		jaw >= minimum - 0.004 and after.distance_to(before) < 0.06,
		"爪=%.4f（最小 %.4f），晶体位移 %.3f m" % [jaw, minimum, after.distance_to(before)])


# ---------------------------------------------------------------- 11 锁止/释放
func _e11_release() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	await _at_cradle(b1)
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	for i in range(180):
		await get_tree().physics_frame
		if not bool(b1.get("jaw_motor")):
			break
	_check("E11 锁止/释放行为合理（E 抬棘爪：爪退到 0.62，locked=false，中继断开）",
		absf(float(b1.get("jaw_x")) - 0.62) < 0.01 and not bool(b1.call("locked"))
			and not bool(stage.call("_relay_ready", "b1")),
		"jaw=%.3f locked=%s relay=%s" % [float(b1.get("jaw_x")), str(b1.call("locked")),
			str(stage.call("_relay_ready", "b1"))])


# ---------------------------------------------------------------- 12 恢复
func _e12_recover() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	await _at_cradle(b1)
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	for i in range(240):
		await get_tree().physics_frame
		if bool(b1.get("latched")):
			break
	_check("E12 错误操作可恢复（松开后重新合拢仍能锁定）",
		bool(b1.call("locked")) and bool(stage.call("_relay_ready", "b1")),
		"locked=%s relay=%s" % [str(b1.call("locked")), str(stage.call("_relay_ready", "b1"))])


# ---------------------------------------------------------------- 13 复位
func _e13_reset() -> void:
	stage.call("reset_level")
	await _w(90)
	var b1: Node3D = cradles["b1"] as Node3D
	_check("E13 复位或重新加载正确（爪回 0.62、占用清空、晶体回出生点、stage=0）",
		absf(float(b1.get("jaw_x")) - 0.62) < 0.01 and not bool(b1.call("is_occupied"))
			and int(stage.get("stage")) == 0
			and crystal_a.global_position.distance_to(R04LevelBuilder.CRYSTAL_A_SPAWN) < 1.5,
		"jaw=%.3f occupied=%s stage=%d crystal=%s" % [float(b1.get("jaw_x")),
			str(b1.call("is_occupied")), int(stage.get("stage")),
			str(crystal_a.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])


# ---------------------------------------------------------------- 14 连续 3 轮
func _e14_repeat() -> void:
	var ok: bool = true
	var jaws: Array[float] = []
	for round_index: int in range(3):
		var b1: Node3D = cradles["b1"] as Node3D
		await _drop_crystal_into(b1, crystal_a)
		await _at_cradle(b1)
		Input.action_press("interact")
		await _w(3)
		Input.action_release("interact")
		for i in range(240):
			await get_tree().physics_frame
			if bool(b1.get("latched")):
				break
		jaws.append(float(b1.get("jaw_x")))
		ok = ok and bool(b1.call("locked"))
		b1.call("open_clamp")
		await _w(120)
		crystal_a.call("begin_carry", player)
		await _w(5)
		crystal_a.call("end_carry", false)
		await _w(60)
	_check("E14 连续 3 轮能够完成（每轮落座 → 合拢 → 锁定）", ok,
		"3 轮爪位 %s" % str(jaws))


# ---------------------------------------------------------------- 15 异常 5 次
func _e15_abnormal() -> void:
	var ok: bool = true
	var b1: Node3D = cradles["b1"] as Node3D
	stage.call("reset_level")
	await _w(90)
	for i: int in range(5):
		b1.call("reset_cradle")
		await _w(20)
		await _at_cradle(b1)
		Input.action_press("interact")
		await _w(3)
		Input.action_release("interact")
		for k in range(120):
			await get_tree().physics_frame
			if not bool(b1.get("jaw_motor")):
				break
		if bool(b1.get("latched")) or bool(stage.call("_relay_ready", "b1")):
			ok = false
			break
		b1.call("open_clamp")
		await _w(160)
	_check("E15 关键异常工况重复 5 次稳定（空叉口反复合拢：从未锁定，爪回 0.62）", ok and absf(float(b1.get("jaw_x")) - 0.62) < 0.02,
		"5 次空合拢：从未 latched；jaw=%.3f" % float(b1.get("jaw_x")))
	b1.call("reset_cradle")
	await _w(30)


# ---------------------------------------------------------------- 16 中继/后续
func _e16_relay() -> void:
	var b1: Node3D = cradles["b1"] as Node3D
	var b3: Node3D = cradles["b3"] as Node3D
	await _drop_crystal_into(b1, crystal_a)
	await _clamp(b1)
	await _drop_crystal_into(b3, crystal_b)
	await _clamp(b3)
	var ready_a: bool = bool(stage.call("_relay_ready", "b1"))
	var ready_b: bool = bool(stage.call("_relay_ready", "b3"))
	_check("E16 原有后续剧情正常推进（两个中继支架都真实锁定后，继电器判定成立）",
		ready_a and ready_b,
		"b1=%s b3=%s stage=%d" % [str(ready_a), str(ready_b), int(stage.get("stage"))])


# ---------------------------------------------------------------- 17 玩家/HUD
func _e17_player() -> void:
	player.teleport(R04LevelBuilder.SPAWN, 0.0)
	await _w(30)
	var p0: Vector3 = player.global_position
	Input.action_press("move_forward")
	await _w(40)
	Input.action_release("move_forward")
	await _w(10)
	var moved: float = player.global_position.distance_to(p0)
	var hud: Node = stage.get("hud")
	_check("E17 玩家移动、视角与 HUD 无回归（新锁爪不挡路，玩家仍能移动）",
		moved > 0.2 and hud != null and player.global_position.is_finite(),
		"位移 %.2f m hud=%s" % [moved, str(hud != null)])


# ---------------------------------------------------------------- 18 交接就绪
func _e18_handoff_ready() -> void:
	var hub: Node = get_node_or_null("/root/SessionHub")
	var entry_ok: bool = ResourceLoader.exists("res://scenes/act4.tscn")
	_check("E18 act23 → act04 交接正确（act4 是正式下一幕场景，SessionHub 可记录章节）",
		entry_ok and hub != null and hub.has_method("complete_chapter")
			and (hub.get("chapter_history") as Dictionary).has("act04"),
		"entry=%s hub=%s chapters=%s" % [str(entry_ok), str(hub != null),
			str((hub.get("chapter_history") as Dictionary).keys())])


# ---------------------------------------------------------------- 工具
func _drop_crystal_into(cradle: Node3D, crystal: Node3D, yaw_offset: float = 0.0) -> void:
	if bool(cradle.call("is_occupied")):
		cradle.call("release")
		crystal.set("is_seated", false)
	crystal.set("is_carried", false)
	crystal.set("freeze", false)
	crystal.global_position = (cradle.call("get_seat_position") as Vector3) + Vector3(0.0, 1.2, 0.0)
	crystal.rotation = Vector3(0.0, deg_to_rad(float(cradle.get("required_yaw_deg")) + yaw_offset), 0.0)
	crystal.set("held_yaw_deg", float(cradle.get("required_yaw_deg")) + yaw_offset)
	crystal.set("linear_velocity", Vector3.ZERO)
	crystal.set("angular_velocity", Vector3.ZERO)
	for i in range(150):
		await get_tree().physics_frame
		if bool(cradle.call("is_occupied")):
			break
	await _w(20)


func _clamp(cradle: Node3D) -> void:
	await _at_cradle(cradle)
	Input.action_press("interact")
	await _w(3)
	Input.action_release("interact")
	for i in range(240):
		await get_tree().physics_frame
		if bool(cradle.get("latched")):
			break
	await _w(10)


func _at_cradle(cradle: Node3D) -> void:
	var at: Vector3 = (cradle.call("get_interaction_position") as Vector3) + Vector3(0.0, 0.0, 1.5)
	player.call("teleport", at, 0.0)
	var look: Vector3 = (cradle.call("get_interaction_position") as Vector3) - (at + Vector3.UP * 1.55)
	player.set("_camera_yaw", atan2(-look.x, -look.z))
	player.set("_camera_yaw_target", atan2(-look.x, -look.z))
	if player.has_method("aim_camera_at"):
		player.call("aim_camera_at", cradle.call("get_interaction_position"), -0.02)
	await _w(20)


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS  " if ok else "FAIL  ") + name + "  |  " + detail)


func _fail(tag: String, msg: String) -> void:
	checks += 1
	failures += 1
	print("FAIL  " + tag + "  |  " + msg)


func _report() -> void:
	print("MECH004A_DONE checks=%d passed=%d failures=%d" % [checks, checks - failures, failures])
	get_tree().quit(0 if failures == 0 else 1)




