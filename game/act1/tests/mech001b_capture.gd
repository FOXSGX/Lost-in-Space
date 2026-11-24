extends Node
## MECHANICS-001B-R2 · 真实窗口截图：锁爪打开 / 闭合 / 通电

const OUT_DIR := "res://act1/captures/mech001b"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	var app: Node = ps.instantiate()
	add_child(app)
	await _w(120)
	var cart: Act1PowerCart = app.builder.power_cart
	var hud: Node = app.get("hud")
	if hud != null and hud.get("_intro") != null:
		hud.get("_intro").visible = false
	app._builder_power_light_on() if app.has_method("_builder_power_light_on") else null
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(4.25, 2.75, -1.35)
	cam.look_at(Vector3(4.25, 1.75, -4.95), Vector3.UP)
	cam.fov = 55.0
	cam.make_current()

	# 送模块进插座
	cart.global_position.x = Act1PowerCart.DOCK_X
	cart.docked = true
	await _w(10)
	cart.transfer_module(Act1StationBuilder.SOCKET)
	for i in range(400):
		await get_tree().physics_frame
		if cart.module_transferred_flag:
			break
	await _w(40)
	await _shot("01_latch_open.png", cart.clamp_angle)

	# E：锁爪真实闭合
	cart.set_clamp(true)
	for i in range(300):
		await get_tree().physics_frame
		if cart.clamp_angle <= Act1PowerCart.CLAMP_CLOSED_ANGLE + 0.04:
			break
	await _w(40)
	await _shot("02_latch_closed.png", cart.clamp_angle)
	await _w(60)
	await _shot("03_powered.png", cart.clamp_angle)
	print("CAP done clamped=%s ready=%s angle=%.3f" % [
		"true" if app.flags["power_clamped"] else "false",
		"true" if app.flags["power_ready"] else "false", cart.clamp_angle])
	get_tree().quit(0)


func _shot(name: String, angle: float) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s" % [OUT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(path))
	# 亮度自检：避免存成黑图
	var lum: float = 0.0
	var w: int = img.get_width()
	var h: int = img.get_height()
	for k in range(24):
		var px: Color = img.get_pixel(int(w * (0.2 + 0.03 * k)), int(h * 0.5))
		lum += (px.r + px.g + px.b) / 3.0
	print("SHOT %s lum=%.3f angle=%.3f" % [name, lum / 24.0, angle])


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame
