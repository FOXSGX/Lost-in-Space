extends Node
## MECHANICS-002C · 真实窗口截图：断轨维修绞盘
## 01–05 玩家视角；06 是标注过的证据镜头（卷筒/缆绳），不改变机械状态。

const OUT := "res://act23/captures/mech002c"

var stage: Node
var flow: Node
var rig: Node
var winch: Node
var rail: Node
var player: CharacterBody3D
var evidence: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	stage = (load("res://act23/moving_cart.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	flow = stage.get("flow")
	rig = flow.get("rig")
	winch = rig.get("winch")
	rail = rig.get("rail")
	player = stage.get("player") as CharacterBody3D
	var machine: Node3D = winch as Node3D
	var anchor: Node3D = rig.call("find_anchor", "eye_far")

	# 1 维修前：从断轨前方看整条维修线（摆动轨 15°、绞盘机、警示牌）
	var far: Vector3 = rail.call("far_point") as Vector3
	var yard: Node3D = flow.get("yard") as Node3D
	_aim(Vector3(84.6, 0.25, 3.0), far)
	await _w(30)
	await _shot("01_before.png", "维修前：断轨区，摆动轨错位 %.1f°，绞盘机待命（卡阻未脱）" % [
		rad_to_deg(float(rail.get("hinge_angle")))])

	# 2 挂缆后松弛：缆绳垂着，张力 0
	player.global_position = (anchor.call("attach_point") as Vector3) + Vector3(1.6, 0.2, 0.6)
	await _w(6)
	rig.call("attach_cable", "eye_far", player)
	await _w(20)
	_aim(Vector3(93.0, 0.25, 4.6), Vector3(90.0, 1.2, 7.6))
	await _w(20)
	await _shot("02_slack.png", "缆绳松弛：钩子挂在前端吊耳上，张力 %.0f N（只受拉，不压）" % [
		float(winch.get("tension"))])

	# 3 收绳：接管绞盘控制台，W 收缆，轨道真的被拉回来
	var console_at: Vector3 = machine.global_position + Vector3(0.0, 0.2, -2.0)
	player.global_position = console_at
	await _w(6)
	flow.call("_enter_console", player)
	await _w(6)
	Input.action_press("winch_haul")
	for i in range(900):
		await get_tree().physics_frame
		if absf(float((rail.call("alignment") as Dictionary).get("angle_deg"))) <= 8.0:
			break
	await _shot("03_hauling.png", "收绳中：张力 %.0f N，轨道被拉到 %.2f°，卷筒 ω=%.2f rad/s" % [
		float(winch.get("tension")),
		float((rail.call("alignment") as Dictionary).get("angle_deg")),
		float(winch.get("drum_omega"))])

	# 4 到导向槽后落鼓刹：手柄压下，鼓被闸瓦抱住
	for i in range(900):
		await get_tree().physics_frame
		if absf(float((rail.call("alignment") as Dictionary).get("angle_deg"))) <= 2.6:
			break
	Input.action_release("winch_haul")
	await _w(2)
	Input.action_press("winch_brake")
	await _w(3)
	Input.action_release("winch_brake")
	await _w(40)
	# 4 鼓刹：站在操作位看不清鼓（机座挡住），这里用明确标注的证据镜头
	var station: Node3D = _find_station(stage) as Node3D
	var drum_at: Vector3 = (station.get("drum") as Node3D).global_position
	_evidence_at(drum_at + Vector3(1.75, 0.06, 0.15), drum_at, 40.0)
	await _w(20)
	await _shot("04_brake.png", "证据镜头｜鼓刹咬住卷筒：ω=%.3f rad/s，张力 %.0f N，闸=%s（玩家视角被机座遮挡）" % [
		float(winch.get("drum_omega")), float(winch.get("tension")),
		"咬合" if bool(winch.get("brake")) else "释放"])
	_clear_evidence()
	await _w(10)

	# 5 插销后：轨道复位、锁定，矿车线路恢复
	var pin: Dictionary = rig.call("try_install_lock")
	await _w(120)
	var lock_at: Vector3 = rail.call("far_point") as Vector3
	_aim(Vector3(96.0, 0.25, 6.4), Vector3(96.4, 0.1, 3.6))
	await _w(30)
	await _shot("05_locked.png", "维修完成：锁定销到位，轨道复位 %.2f°，线路恢复（pin=%s）" % [
		float((rail.call("alignment") as Dictionary).get("angle_deg")),
		str(pin.get("mode", pin.get("reason", "")))])

	# 6 证据镜头：卷筒、缠绳与闸瓦
	_evidence_camera(machine)
	await _w(20)
	await _shot("06_drum_evidence.png", "证据镜头｜绞盘机、卷筒与出缆口（ω=%.2f，张力 %.0f N）" % [
		float(winch.get("drum_omega")), float(winch.get("tension"))])
	print("CAP rig=%s" % str(rig.call("rig_snapshot")))
	get_tree().quit(0)


func _aim(eye: Vector3, target: Vector3) -> void:
	player.global_position = eye
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var look: Vector3 = target - (eye + Vector3.UP * 1.5)
	var yaw: float = atan2(-look.x, -look.z)
	var pitch: float = atan2(-look.y, Vector2(look.x, look.z).length())
	player.set("_camera_yaw", yaw)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_pitch", pitch)
	player.set("_camera_pitch_target", pitch)


func _evidence_at(eye: Vector3, target: Vector3, fov: float = 50.0) -> void:
	evidence = Camera3D.new()
	evidence.name = "EvidenceCamera"
	evidence.fov = fov
	stage.add_child(evidence)
	evidence.global_transform = Transform3D(Basis.IDENTITY, eye)
	evidence.look_at(target, Vector3.UP)
	evidence.current = true


func _clear_evidence() -> void:
	if evidence == null:
		return
	evidence.current = false
	evidence.queue_free()
	evidence = null


func _find_station(node: Node) -> Node:
	if node == null:
		return null
	if node.get("drum") != null:
		return node
	for child: Node in node.get_children():
		var hit: Node = _find_station(child)
		if hit != null:
			return hit
	return null


func _evidence_camera(machine: Node3D) -> void:
	var station: Node3D = _find_station(stage) as Node3D
	var drum_at: Vector3 = (station.get("drum") as Node3D).global_position
	_evidence_at(machine.global_position + Vector3(2.6, 1.35, -1.6),
		machine.global_position + Vector3(0.0, 1.1, 0.0), 52.0)


func _shot(name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s" % [OUT, name]))
	var w: int = img.get_width()
	var h: int = img.get_height()
	var lum := 0.0
	for k in range(20):
		var px: Color = img.get_pixel(int(w * (0.3 + 0.02 * k)), int(h * 0.5))
		lum += (px.r + px.g + px.b) / 3.0
	print("SHOT %s lum=%.3f  %s" % [name, lum / 20.0, note])


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame




