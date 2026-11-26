extends Node
## MECHANICS-001E-R3 · 真实窗口截图：停车制动（证据镜头）

const OUT := "res://act1/captures/mech001e"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	var app: Node = ps.instantiate()
	add_child(app)
	await _w(120)
	var hud: Node = app.get("hud")
	if hud != null and hud.get("_intro") != null:
		hud.get("_intro").visible = false
	var br: Act1ParkingBrake = app.builder.parking_brake
	app.flags["chock_removed"] = true
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(8.35, 2.55, -47.75)
	cam.look_at(Vector3(6.9, 2.35, -48.9), Vector3.UP)
	cam.fov = 58.0
	cam.make_current()
	var lamp: OmniLight3D = OmniLight3D.new()
	add_child(lamp)
	lamp.global_position = Vector3(7.6, 3.0, -47.9)
	lamp.light_energy = 10.0
	lamp.omni_range = 9.0
	await _w(30)
	await _shot("01_locked.png", "初始：销爪伸入齿圈，制动有效")

	app._execute_interaction(int(app.local_pid), "parking_brake", "press")
	await _w(8)
	await _shot("02_releasing.png", "执行器正在抽销爪")
	for i in range(150):
		await get_tree().physics_frame
		if br.released():
			break
	await _w(10)
	await _shot("03_released.png", "销爪退出齿圈 · 制动解除")
	await _w(35)
	await _shot("04_drum_spin.png", "解除后制动鼓真实转动 ω=%.1f" % br.drum_omega())
	br.apply_brake()
	for i in range(150):
		await get_tree().physics_frame
		if not br.released():
			break
	await _w(60)
	await _shot("05_relocked.png", "重新锁止 · 鼓被真实阻挡 ω=%.1f" % br.drum_omega())
	print("CAP travel=%.3f released=%s omega=%.1f flag=%s" % [
		br.pin_travel(), "true" if br.released() else "false", br.drum_omega(),
		"true" if app.flags["brake_released"] else "false"])
	get_tree().quit(0)


func _shot(name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s" % [OUT, name]))
	var w: int = img.get_width()
	var h: int = img.get_height()
	var lum: float = 0.0
	for k in range(20):
		var px: Color = img.get_pixel(int(w * (0.3 + 0.02 * k)), int(h * 0.5))
		lum += (px.r + px.g + px.b) / 3.0
	print("SHOT %s lum=%.3f  %s" % [name, lum / 20.0, note])


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame
