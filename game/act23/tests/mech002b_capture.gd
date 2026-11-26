extends Node
## MECHANICS-002B · 真实窗口截图：矿车手制动与制动过程
## 01–05 玩家视角；06 是标注过的证据镜头（鼓/闸瓦），不改变任何机械状态。

const OUT := "res://act23/captures/mech002b"

var stage: Node
var cart: AnimatableBody3D
var device: Node
var player: CharacterBody3D
var rig: Node3D
var evidence: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	stage = (load("res://act23/moving_cart.tscn") as PackedScene).instantiate()
	add_child(stage)
	await _w(150)
	cart = stage.get("cart") as AnimatableBody3D
	device = stage.get("device")
	player = stage.get("player") as CharacterBody3D
	rig = cart.get("brake_rig") as Node3D

	# 1 释放状态：正常行驶，手柄在释放位
	_at_console()
	await _w(5)
	cart.call("start")
	for i in range(400):
		await get_tree().physics_frame
		if float(cart.get("speed")) > 1.5:
			break
	await _w(10)
	await _shot("01_release.png", "行驶中 · 手制动释放（档位 %d，行程 %.2f，力 %.0f N）" % [
		int(rig.get("notch")), float(rig.get("travel")), float(cart.call("brake_force"))])

	# 2 拉 1 档：手柄过棘轮，闸瓦压上鼓，矿车开始因制动力减速
	stage.call("request_action", "cart_brake", 1)
	await _w(26)
	await _shot("02_service.png", "B 拉 1 档 · 手柄到位，闸瓦压上制动鼓（%.0f N），矿车减速（%.2f m/s）" % [
		float(cart.call("brake_force")), float(cart.get("speed"))])

	# 3 停稳：速度 0，闸仍咬合
	for i in range(200):
		await get_tree().physics_frame
		if float(cart.get("speed")) < 0.01:
			break
	await _w(30)
	await _shot("03_stopped.png", "常用制动停车 · 手制动 1 档保持（速度 %.3f m/s）" % float(cart.get("speed")))

	# 4 紧急档：松开、重新发车、拉满 2 档
	stage.call("request_action", "cart_brake", 1)   # 1 → 2
	await _w(40)
	await _shot("04_emergency_static.png", "2 档（紧急）静态：手柄顶到机械止挡（行程 %.2f，力 %.0f N）" % [
		float(rig.get("travel")), float(cart.call("brake_force"))])
	stage.call("request_action", "cart_brake", 1)   # 2 → 0 释放
	await _w(40)
	_at_console()
	await _w(5)
	cart.call("start")
	for i in range(400):
		await get_tree().physics_frame
		if float(cart.get("speed")) > 1.5:
			break
	await _w(10)
	stage.call("request_action", "cart_brake", 1)   # → 1
	await _w(20)
	stage.call("request_action", "cart_brake", 1)   # → 2
	await _w(30)
	await _shot("05_emergency.png", "紧急制动中 · 2 档（力 %.0f N，速度 %.2f m/s）" % [
		float(cart.call("brake_force")), float(cart.get("speed"))])
	for i in range(200):
		await get_tree().physics_frame
		if float(cart.get("speed")) < 0.01:
			break

	# 6 证据镜头：近侧鼓与闸瓦（标注为证据镜头）
	_evidence_camera()
	await _w(20)
	await _shot("06_drum_shoe.png", "证据镜头｜近侧制动鼓与闸瓦咬合（鼓面线速度 %.2f m/s，闸瓦力 %.0f N）" % [
		float(rig.call("drum_surface_speed")), float(rig.call("shoe_force"))])
	print("CAP brake=%s" % str(cart.call("brake_state")))
	get_tree().quit(0)


func _evidence_camera() -> void:
	evidence = Camera3D.new()
	evidence.name = "EvidenceCamera"
	evidence.fov = 52.0
	cart.add_child(evidence)
	# 车体局部：站在近侧外看鼓与闸瓦（鼓在 2.70, 1.10, 0.72）
	evidence.global_transform = Transform3D(Basis.IDENTITY,
		cart.to_global(Vector3(4.05, 1.72, -1.05)))
	evidence.look_at(cart.to_global(Vector3(2.66, 1.12, 0.72)), Vector3.UP)
	evidence.current = true


func _at_console() -> void:
	# 站在手制动台前（正常玩家视角）：手柄、扇形板、连杆都在画面里。
	player.global_position = cart.to_global(Vector3(0.35, 2.05, 1.86))
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var look: Vector3 = cart.to_global(Vector3(1.58, 2.34, 1.30)) - (player.global_position + Vector3.UP * 1.5)
	var yaw: float = atan2(-look.x, -look.z)
	var pitch: float = atan2(-look.y, Vector2(look.x, look.z).length())
	player.set("_camera_yaw", yaw)
	player.set("_camera_yaw_target", yaw)
	player.set("_camera_pitch", pitch)
	player.set("_camera_pitch_target", pitch)


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


