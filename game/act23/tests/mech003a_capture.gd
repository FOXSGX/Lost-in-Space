extends Node
## MECHANICS-003A · 真实窗口截图：晶体门停靠夹钳
## 01–05 玩家视角；06 是标注过的证据镜头（铰座/棘爪/压车垫块）。

const OUT := "res://act23/captures/mech003a"

var stage: Node
var flow: Node
var cart: AnimatableBody3D
var dock: Node3D
var player: CharacterBody3D
var evidence: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	stage = (load("res://act23/moving_cart.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	flow = stage.get("flow")
	cart = stage.get("cart") as AnimatableBody3D
	dock = stage.get("dock") as Node3D
	player = stage.get("player") as CharacterBody3D
	# 开到晶体门
	cart.call("snap_to_distance", 103.0)
	cart.call("release_route")
	await _w(20)
	cart.call("start")
	for i in range(900):
		await get_tree().physics_frame
		if bool(cart.get("arrived")):
			break
	await _w(30)
	var handle: Vector3 = dock.call("handle_world") as Vector3
	# 1 停靠前：矿车停在晶体门，闸臂竖起
	_aim(handle + Vector3(-1.9, 0.55, -1.6), cart.to_global(Vector3(1.0, 1.6, 0.8)))
	await _w(20)
	await _shot("01_before.png", "矿车停在 03 晶体门、闸臂竖起（phase=%s，docked=%s）" % [
		str(flow.get("phase")), str(dock.call("docked"))])
	# 2 玩家拉住闸臂：臂在行程中
	player.call("restore_at", handle + Vector3(0.0, -0.85, -1.25))
	var look: Vector3 = (dock.call("arm_tip_world") as Vector3) - (player.global_position + Vector3.UP * 1.5)
	player.set("_camera_yaw", atan2(-look.x, -look.z))
	player.set("_camera_yaw_target", atan2(-look.x, -look.z))
	await _w(10)
	Input.action_press("repair")
	var angle: float = 0.0
	for i in range(240):
		await get_tree().physics_frame
		angle = float((dock.call("state") as Dictionary).get("angle_deg", 0.0))
		if angle > 45.0:
			break
	await _shot("02_pulling.png", "玩家按住 E 拉闸臂：%.1f°，配重 %0.f N·m 在往回抬" % [
		angle, float((dock.call("state") as Dictionary).get("gravity_torque", 0.0))])
	for i in range(240):
		await get_tree().physics_frame
		if bool(dock.call("docked")):
			break
	Input.action_release("repair")
	await _w(20)
	# 3 闸臂压住车侧
	_aim(handle + Vector3(-1.6, 0.45, -1.4), cart.to_global(Vector3(1.0, 1.3, 0.87)))
	await _w(10)
	await _shot("03_pressed.png", "闸臂横压在车体侧面：%.1f°，垫块贴合=%s" % [
		float((dock.call("state") as Dictionary).get("angle_deg", 0.0)),
		str((dock.call("state") as Dictionary).get("pressed"))])
	# 4 棘爪落位 + 停靠成立
	await _shot("04_locked.png", "棘爪落位：停靠成立=%s，章节 phase=%s" % [
		str(dock.call("docked")), str(flow.get("phase"))])
	# 5 第三幕完成：目标变为到站，线路恢复
	_aim(handle + Vector3(-2.6, 1.2, -2.4), cart.to_global(Vector3(0.6, 2.2, 1.2)))
	await _w(20)
	await _shot("05_done.png", "03 停靠完成：HUD 目标「%s」" % str(flow.get("objective_text")))
	# 6 证据镜头：铰座、棘爪、压车垫块
	var pivot: Vector3 = dock.to_global(Vector3(1.0, 1.6, -0.72))
	_evidence_at(pivot + Vector3(1.35, 0.15, -1.1), pivot + Vector3(0.0, -0.9, 0.9), 48.0)
	await _w(20)
	await _shot("06_pivot_evidence.png", "证据镜头｜铰座/棘爪/压车垫块（臂 %.1f°，棘爪=%s）" % [
		float((dock.call("state") as Dictionary).get("angle_deg", 0.0)),
		str((dock.call("state") as Dictionary).get("latched"))])
	print("CAP dock=%s" % str(dock.call("state")))
	get_tree().quit(0)


func _aim(eye: Vector3, target: Vector3) -> void:
	player.call("restore_at", eye)
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
