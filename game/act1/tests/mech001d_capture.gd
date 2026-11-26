extends Node
## MECHANICS-001D · 真实窗口截图：车轮止轮楔

const OUT_DIR := "res://act1/captures/mech001d"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	var app: Node = ps.instantiate()
	add_child(app)
	await _w(120)
	var hud: Node = app.get("hud")
	if hud != null and hud.get("_intro") != null:
		hud.get("_intro").visible = false
	var chock: Act1WheelChock = app.builder.wheel_chock
	app.flags["vent_complete"] = true   # 前置：通风已完成（截图需要发车阶段可见）
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(-1.9, 2.9, -42.6)
	cam.look_at(Vector3(-5.62, 0.55, -46.8), Vector3.UP)
	cam.fov = 72.0
	cam.make_current()
	# 截图用局部补光（任务 §10 允许的小范围必要照明，不修改场景美术）
	var lamp: OmniLight3D = OmniLight3D.new()
	add_child(lamp)
	lamp.global_position = Vector3(-5.0, 1.9, -45.2)
	lamp.light_energy = 14.0
	lamp.omni_range = 12.0
	lamp.light_color = Color(1.0, 0.96, 0.88)
	var lamp2: OmniLight3D = OmniLight3D.new()
	add_child(lamp2)
	lamp2.global_position = Vector3(-6.4, 1.3, -47.8)
	lamp2.light_energy = 8.0
	lamp2.omni_range = 10.0
	await _w(20)
	await _shot("01_before.png", "止轮楔压在轮下 · 交互提示可见")

	chock.pull()
	await _w(16)
	await _shot("02_pulling.png", "执行器正在拖出楔块")

	for i in range(200):
		await get_tree().physics_frame
		if chock.removed():
			break
	await _w(12)
	await _shot("03_removed.png", "楔块脱离轮下 · HUD 同步任务状态")

	# 走完其余发车联锁（用真实交互通道）
	app._execute_interaction(int(app.local_pid), "parking_brake", "press")
	await _w(60)
	# MECHANICS-001F：货舱固定带改为真实棘轮，需要摇到工作张力
	for n in range(10):
		if bool(app.flags["cargo_secured"]):
			break
		app.flags["chock_removed"] = true
		app.flags["brake_released"] = true
		app._execute_interaction(int(app.local_pid), "cargo", "press")
		await _w(45)
	await _w(20)
	await _shot("04_interlock_ready.png", "发车联锁就绪（止轮楔已移走/制动已释放/货物已固定）")
	print("CAP chock_removed=%s brake=%s cargo=%s launch_ok=%s" % [
		"true" if app.flags["chock_removed"] else "false",
		"true" if app.flags["brake_released"] else "false",
		"true" if app.flags["cargo_secured"] else "false",
		"true" if bool(app._launch_conditions_ok()) else "false"])
	get_tree().quit(0)


func _shot(name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, name]))
	var lum: float = 0.0
	var w: int = img.get_width()
	var h: int = img.get_height()
	for k in range(24):
		var px: Color = img.get_pixel(int(w * (0.25 + 0.02 * k)), int(h * 0.6))
		lum += (px.r + px.g + px.b) / 3.0
	print("SHOT %s lum=%.3f  %s" % [name, lum / 24.0, note])


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame
