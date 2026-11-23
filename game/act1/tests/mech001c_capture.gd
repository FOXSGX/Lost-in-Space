extends Node
## MECHANICS-001C · 真实窗口截图：通风机组机械联锁

const OUT_DIR := "res://act1/captures/mech001c"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	var app: Node = ps.instantiate()
	add_child(app)
	await _w(120)
	var hud: Node = app.get("hud")
	if hud != null and hud.get("_intro") != null:
		hud.get("_intro").visible = false
	var vent: Act1Ventilation = app.builder.vent
	var il: Act1FanInterlock = app.builder.fan_interlock
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(8.55, 1.72, -24.35)
	cam.look_at(Vector3(6.85, 1.05, -23.55), Vector3.UP)
	cam.fov = 62.0
	cam.make_current()
	await _w(20)
	await _shot("01_before.png", "锁销在位 / 联轴器未啮合")

	# 1) 拉锁销：执行器动作中
	il.pull_rotor_lock()
	await _w(14)
	await _shot("02_lock_pulling.png", "执行器正在拔出锁销")
	for i in range(120):
		await get_tree().physics_frame
		if il.rotor_released():
			break
	await _w(10)
	await _shot("03_lock_released.png", "锁销脱开 · 转子自由")

	# 2) 推联轴器：推入过程（换到联轴器近景）
	cam.global_position = Vector3(8.55, 1.92, -29.85)
	cam.look_at(Vector3(6.85, 1.30, -29.05), Vector3.UP)
	await _w(6)
	il.push_coupling()
	await _w(18)
	await _shot("04_coupling_pushing.png", "执行器正在推入联轴器")
	for i in range(180):
		await get_tree().physics_frame
		if il.coupling_engaged():
			break
	await _w(10)
	await _shot("05_coupling_engaged.png", "联轴器啮合到位 · 动力可传递")

	# 3) 通电并启动风机（真实转速建立）
	app.flags["power_ready"] = true
	app._execute_interaction(int(app.local_pid), "start_fan", "press")
	await _w(80)
	cam.global_position = Vector3(12.4, 3.1, -21.8)
	cam.look_at(Act1Ventilation.FAN_POS, Vector3.UP)
	await _w(60)
	await _shot("06_fan_spinning.png", "主风机真实转动 speed=%.2f" % vent.speed)
	print("CAP vent speed=%.3f pressure=%.3f running=%s ready=%s" % [
		vent.speed, vent.pressure, "true" if vent.running else "false",
		"true" if il.machine_ready() else "false"])
	get_tree().quit(0)


func _shot(name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, name]))
	var lum: float = 0.0
	var w: int = img.get_width()
	var h: int = img.get_height()
	for k in range(24):
		var px: Color = img.get_pixel(int(w * (0.25 + 0.02 * k)), int(h * 0.55))
		lum += (px.r + px.g + px.b) / 3.0
	print("SHOT %s lum=%.3f  %s" % [name, lum / 24.0, note])


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame
