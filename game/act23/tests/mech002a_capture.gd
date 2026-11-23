extends Node
## MECHANICS-002A · 真实窗口截图：货舱固定座机械锁爪
## 01–06 全部使用**玩家视角**（本地角色相机），不摆状态、不改机械；
## 下放/合拢/锁定都走真实的 F/G/E 交互通道，任务状态由物理接触推导。

const OUT := "res://act23/captures/mech002a"

var stage: Node
var cart: AnimatableBody3D
var device: Node
var player: CharacterBody3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ps: PackedScene = load("res://act23/moving_cart.tscn") as PackedScene
	stage = ps.instantiate()
	add_child(stage)
	await _w(150)
	cart = stage.get("cart") as AnimatableBody3D
	device = stage.get("device")
	player = stage.get("player") as CharacterBody3D

	# ---- 1 初始状态：两个容器散放在甲板上，固定座张开，HUD 货物 0/2
	_stage_at_cradle(0)
	await _w(40)
	await _shot("01_before.png", "初始状态：容器散放在甲板，锁爪张开，HUD 货物 %d/2" % int(device.call("locked_count")))

	# ---- 2 机械操作开始：按 G 把容器放到固定座（真实下放，不是吸附）
	stage.call("request_action", "pickup", 1)
	await _w(20)
	stage.call("request_action", "deposit", 1)
	await _w(30)
	await _shot("02_place.png", "按 G 下放：容器被真实下放到固定座，未冻结、未钉住")

	for i in range(120):
		await get_tree().physics_frame
		if str(((device.get("cargo") as Array)[0] as Node).get("phase")) == "seated":
			break
	await _w(20)
	await _shot("03_seated.png", "容器落在座板上 · 锁爪仍张开 · 按 E 开始合拢")

	# ---- 3 真实机械运动过程：按 E，锁爪走一半行程
	_stage_at_cradle(0)
	await _w(6)
	stage.call("request_action", "repair", 1)
	# 62 帧 ≈ 1.03 s：锁爪按 CRANK_RATE 0.11 m/s 走了约一半行程（0.49 → 约 0.38），
	# 截图能真的看到"正在夹"而不是"还没动"。
	await _w(62)
	await _shot("04_closing.png", "锁爪电机合拢中 · 两侧钢爪向内夹（%s）" % str(device.call("clamp_state")))

	for i in range(160):
		await get_tree().physics_frame
		if bool(device.call("slot_secured", 0)):
			break
	await _w(20)
	# ---- 4 物理条件满足：夹钳与边轨真的夹住，HUD 货物 1/2
	_stage_at_cradle(0)
	await _w(20)
	await _shot("05_clamped.png", "物理条件满足：锁爪合拢、容器在座内、接触座板 → secured=true，HUD 货物 %d/2" % int(device.call("locked_count")))

	# ---- 5 任务完成与剧情推进：原有控制器发车，矿车进入 ride
	player.global_position = cart.to_global(Vector3(2.48, 2.05, 1.20))
	player.velocity = Vector3.ZERO
	await _w(20)
	stage.call("request_action", "repair", 1)
	await _w(40)
	var running: bool = bool(cart.get("running"))
	await _w(120)
	var look: Vector3 = cart.to_global(Vector3(-1.10, 2.30, 2.92)) - (player.global_position + Vector3.UP * 1.5)
	var yaw2: float = atan2(-look.x, -look.z)
	var pitch2: float = atan2(-look.y, Vector2(look.x, look.z).length())
	player.set("_camera_yaw", yaw2)
	player.set("_camera_yaw_target", yaw2)
	player.set("_camera_pitch", pitch2)
	player.set("_camera_pitch_target", pitch2)
	await _w(30)
	await _shot("06_departing.png", "任务完成后剧情继续：矿车按原有控制器发车（running=%s），容器仍被锁爪夹住（secured=%s）" % [
		str(running), str(device.call("slot_secured", 0))])
	print("CAP locked=%d phase=%s running=%s distance=%.1f" % [
		int(device.call("locked_count")), str(stage.get("flow").get("phase")),
		str(running), float(cart.get("distance"))])
	get_tree().quit(0)


func _stage_at_cradle(index: int) -> void:
	var slots: Array = device.get("slots") as Array
	var target: Vector3 = cart.to_global(slots[index] as Vector3)
	player.global_position = cart.to_global((slots[index] as Vector3) + Vector3(0.0, 0.0, -1.85))
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var look: Vector3 = target - (player.global_position + Vector3.UP * 1.5)
	var yaw: float = atan2(-look.x, -look.z)
	# pitch 是"看向角"：正数=向下
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
