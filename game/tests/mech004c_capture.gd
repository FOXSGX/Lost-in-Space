extends Node
## MECHANICS-004C · 真实窗口截图（第一人称玩家视角）
##
## 六张证据：
##   01 门关闭              02 电机启动
##   03 门上升中            04 固定障碍挡门
##   05 顶部限位与保持      06 玩家通过出口
##
## 不作弊：不传送门体、不冻结刚体、不关闭碰撞、不直接设置开门状态。
## 门只靠真实施力上升；障碍是真实 StaticBody；玩家只按真实按键与转视角。
## 唯一允许的摆位是**玩家自己的站位与视角**（那是真实玩家会做的事）。
##
## 第四幕正式洞穴偏暗：本进程在门口临时补一盏灯（仅截图进程，不改正式场景）。

const OUT := "res://captures/mech004c"

var stage: Node
var gate: Node3D
var player: Node3D
var fill: OmniLight3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	stage = (load("res://scenes/act4.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(180)
	gate = stage.get("gate") as Node3D
	player = stage.get("player") as Node3D
	if gate == null or player == null:
		print("CAP_FAIL missing gate/player")
		get_tree().quit(1)
		return

	fill = OmniLight3D.new()
	fill.light_color = Color(1.0, 0.86, 0.70)
	fill.light_energy = 7.5
	fill.omni_range = 20.0
	stage.add_child(fill)

	var door_world: Vector3 = gate.to_global(Vector3(0.0, 0.0, 0.0))
	fill.global_position = Vector3(door_world.x - 3.0, 4.6, door_world.z)

	# ---------------- 01 门关闭 ----------------
	# 站在最终矿室一侧，正对关闭的门。
	await _stand(Vector3(door_world.x - 5.6, 0.05, door_world.z + 0.6),
		Vector3(door_world.x, 2.1, door_world.z), 0.0)
	await _w(60)
	await _shot("01_gate_closed.png",
		"门关闭（height=%.2f state=%s exit_allowed=%s）" % [
			float(gate.get("height")), str(gate.get("_state")),
			str(gate.get("exit_allowed"))])

	# ---------------- 02 电机启动 ----------------
	# 剧情条件满足 → 授予许可 → 开始施力。抓门刚开始动、推力已建立的那一帧。
	gate.call("unlock", "capture_memory_3")
	gate.call("open")
	var force_seen := 0.0
	for _i in range(30):
		await get_tree().physics_frame
		force_seen = maxf(force_seen, absf(float(gate.get("motor_force"))))
	await _shot("02_motor_start.png",
		"电机启动（motor_force=%.0f N，limit=%.0f N，height=%.3f，velocity=%.2f）" % [
			force_seen, float(gate.get("motor_force_limit")),
			float(gate.get("height")), float(gate.get("velocity"))])

	# ---------------- 03 门上升中 ----------------
	var guard := 0
	while float(gate.get("height")) < 2.30 and guard < 600:
		await get_tree().physics_frame
		guard += 1
	var h_mid: float = float(gate.get("height"))
	var v_mid: float = float(gate.get("velocity"))
	await _shot("03_gate_rising.png",
		"门上升中（height=%.2f m，velocity=%.2f m/s，contact=%d，joint_err=%.4f）" % [
			h_mid, v_mid, int(gate.get("contact_count")), float(gate.get("joint_error"))])

	# 让门先开到位（后面障碍测试要复位）
	guard = 0
	while not bool(gate.get("exit_allowed")) and guard < 1200:
		await get_tree().physics_frame
		guard += 1
	var h_open: float = float(gate.get("height"))
	var hold: String = str(gate.get("hold_mode"))
	gate.call("reset_gate")
	await _w(90)

	# ---------------- 04 固定障碍挡门 ----------------
	# 真实 StaticBody 挡在升降路径上：门顶撞上后停在低处，电机进入堵转保护。
	var blocker: StaticBody3D = StaticBody3D.new()
	blocker.name = "CaptureBlocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.40, 0.50, 5.40)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = Vector3(door_world.x, 5.30, door_world.z)
	stage.add_child(blocker)
	# 障碍的可见外观：一根钢制横梁，让画面读得出「被挡住」而不是「门停了」
	var beam: MeshInstance3D = MeshInstance3D.new()
	var beam_mesh: BoxMesh = BoxMesh.new()
	beam_mesh.size = Vector3(1.40, 0.50, 5.40)
	beam.mesh = beam_mesh
	beam.material_override = MaterialLibrary.metal(Color(0.72, 0.26, 0.14), 0.42, 0.85)
	beam.position = Vector3(door_world.x, 5.30, door_world.z)
	stage.add_child(beam)
	await _w(30)
	gate.call("unlock", "capture_obstacle")
	gate.call("open")
	guard = 0
	while not bool(gate.get("obstruction")) and guard < 900:
		await get_tree().physics_frame
		guard += 1
	await _w(20)
	await _shot("04_blocked_by_obstacle.png",
		"固定障碍挡门（height=%.2f m，obstruction=%s，contacts=%d，motor=%.0f N）" % [
			float(gate.get("height")), str(gate.get("obstruction")),
			int(gate.get("contact_count")), float(gate.get("motor_force"))])
	blocker.queue_free()
	beam.queue_free()
	await _w(40)

	# ---------------- 05 顶部限位与保持 ----------------
	# 移走障碍后同一台电机继续把门推到位，机械承接梁插入门底下方承重。
	guard = 0
	while not (bool(gate.get("catch_engaged")) and bool(gate.get("exit_allowed"))) and guard < 1800:
		await get_tree().physics_frame
		guard += 1
	await _w(30)
	var h_top: float = float(gate.get("height"))
	var motor_top: float = float(gate.get("motor_force"))
	# 站远一点，把门袋、承接梁与门顶一起收进画面
	await _stand(Vector3(door_world.x - 7.2, 0.05, door_world.z + 1.4),
		Vector3(door_world.x - 0.3, 5.4, door_world.z), 0.30)
	await _w(40)
	await _shot("05_top_hold.png",
		"顶部限位与机械保持（height=%.2f m，hold=%s，catch=%s，motor=%.0f N）" % [
			h_top, str(gate.get("hold_mode")), str(gate.get("catch_engaged")), motor_top])

	# ---------------- 06 玩家通过出口 ----------------
	# 玩家真的走过门洞进入走廊（只按 W，不传送进触发区）。
	# 注意站位：面向门洞，而不是像 05 那样偏向景观机位。
	await _stand(Vector3(door_world.x - 3.4, 0.05, door_world.z + 0.2),
		Vector3(door_world.x + 4.0, 1.4, door_world.z), 0.0)
	await _w(30)
	Input.action_press("move_forward")
	# 行走途中先拍一张「正在穿过门洞」
	var frames_walked := 0
	for _i in range(150):
		await get_tree().physics_frame
		frames_walked += 1
		if frames_walked == 60:
			await _shot("06_player_passing.png",
				"玩家通过出口（行走中：玩家 x=%.2f，门在 x=%.2f，clearance=%.2f m，exit_allowed=%s）" % [
					player.global_position.x, door_world.x, float(gate.get("clearance")),
					str(gate.get("exit_allowed"))])
	Input.action_release("move_forward")
	await _w(30)

	print("CAP_DONE gate_open_height=%.2f hold=%s motor_at_top=%.0f" % [
		h_open, hold, motor_top])
	get_tree().quit(0)


func _stand(eye: Vector3, target: Vector3, extra_pitch: float) -> void:
	player.call("teleport", eye, 0.0)
	var eye_at: Vector3 = eye + Vector3.UP * 1.42
	var drop: float = eye_at.y - target.y
	var flat: float = Vector2(target.x - eye.x, target.z - eye.z).length()
	var pitch: float = -clampf(atan2(drop, maxf(flat, 0.05)), 0.10, 1.05) + extra_pitch
	player.call("aim_camera_at", target, pitch)


func _shot(file_name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s" % [OUT, file_name]))
	var w: int = img.get_width()
	var h: int = img.get_height()
	var lum := 0.0
	for k in range(20):
		var px: Color = img.get_pixel(int(w * (0.30 + 0.02 * k)), int(h * 0.50))
		lum += (px.r + px.g + px.b) / 3.0
	print("SHOT %s %dx%d lum=%.3f  %s" % [file_name, w, h, lum / 20.0, note])


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
