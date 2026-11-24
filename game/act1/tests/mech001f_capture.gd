extends Node
## MECHANICS-001F · 真实窗口截图：货舱固定带
## 01–03、05 使用**玩家视角**（本地玩家相机，站在发车站台上）；
## 04 外力对照使用独立证据镜头（已在此明确标记）。

const OUT := "res://act1/captures/mech001f"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	var app: Node = ps.instantiate()
	add_child(app)
	await _w(120)
	var hud: Node = app.get("hud")
	if hud != null and hud.get("_intro") != null:
		hud.get("_intro").visible = false
	var rig: Act1CargoRig = app.builder.cargo_rig
	var player: Act1StationPlayer = app.local_player
	# 截图走真实链路：先移走止轮楔、再真实解除停车制动，之后才动固定带
	app.flags["vent_complete"] = true
	app.builder.wheel_chock.pull()
	for i in range(150):
		await get_tree().physics_frame
		if bool(app.flags["chock_removed"]):
			break
	app.builder.parking_brake.release_brake()
	for i in range(150):
		await get_tree().physics_frame
		if bool(app.flags["brake_released"]):
			break
	await _w(10)
	print("CAP prerequisites chock=%s brake=%s" % [
		str(app.flags["chock_removed"]), str(app.flags["brake_released"])])

	# ---- 玩家视角：站在发车站台边，隔着登车缺口看货舱
	_player_view(player, Vector3(6.05, 1.53, -46.10), rig.pump_point.global_position + Vector3(0.55, 0.25, -0.35))
	await _w(40)
	await _shot("01_before.png", "固定前：货箱在货台上，两条交叉固定带松弛下垂")

	# ---- 张紧中：摇到第 6 档（张力 600 N），再按一档并停在行程中间
	for n in range(6):
		app._execute_interaction(int(app.local_pid), "cargo", "press")
		await _w(46)
	_player_view(player, Vector3(6.05, 1.53, -46.10), rig.pump_point.global_position + Vector3(0.55, 0.25, -0.35))
	await _w(4)
	app._execute_interaction(int(app.local_pid), "cargo", "press")
	await _w(14)
	await _shot("02_tensioning.png", "张紧中：棘轮手柄在行程中，带体被拉直（张力 %.0f N）" % rig.tension())

	# ---- 固定后：达到工作张力 + 棘爪落位 + 联锁就绪
	for n in range(6):
		if rig.secured():
			break
		app._execute_interaction(int(app.local_pid), "cargo", "press")
		await _w(46)
	await _w(20)
	_player_view(player, Vector3(6.05, 1.53, -46.10), rig.pump_point.global_position + Vector3(0.55, 0.20, -0.35))
	await _w(6)
	await _shot("03_secured.png", "固定后：张力 %.0f N / 棘爪落位 / cargo_secured=%s" % [
		rig.tension(), str(app.flags["cargo_secured"])])

	# ---- 外力对照（独立证据镜头，已标记）
	var cam := Camera3D.new()
	cam.name = "EvidenceCam_NotPlayerView"
	add_child(cam)
	cam.global_position = Vector3(4.35, 3.05, -44.55)
	cam.look_at(Vector3(2.55, 1.85, -47.20), Vector3.UP)
	cam.fov = 62.0
	cam.make_current()
	var lamp := OmniLight3D.new()
	add_child(lamp)
	lamp.global_position = Vector3(3.9, 3.3, -45.6)
	lamp.light_energy = 9.0
	lamp.omni_range = 8.0
	lamp.light_color = Color(1.0, 0.95, 0.86)
	await _w(20)
	var p_fixed: Vector3 = rig.to_local(rig.crate.global_position)
	for i in range(60):
		rig.crate.apply_central_force(Vector3(0, 0, -600.0))
		await get_tree().physics_frame
	await _w(10)
	await _shot("04a_force_fixed.png", "证据镜头｜600 N 外推 1 s：固定状态位移 %.3f m（张力 %.0f N）" % [
		rig.to_local(rig.crate.global_position).distance_to(p_fixed), rig.tension()])

	# 解除锁扣后施加同一外力
	app._execute_interaction(int(app.local_pid), "cargo_latch", "press")
	await _w(180)
	var p_free: Vector3 = rig.to_local(rig.crate.global_position)
	for i in range(60):
		rig.crate.apply_central_force(Vector3(0, 0, -600.0))
		await get_tree().physics_frame
	await _w(10)
	await _shot("04b_force_released.png", "证据镜头｜同一 600 N 外推：解除后位移 %.3f m" % [
		rig.to_local(rig.crate.global_position).distance_to(p_free)])

	# ---- 发车：回到玩家视角，重新固定后发车
	rig.reset_cargo()
	await _w(30)
	for n in range(9):
		if rig.secured():
			break
		app._execute_interaction(int(app.local_pid), "cargo", "press")
		await _w(46)
	_player_view(player, Vector3(6.05, 1.53, -46.10), rig.pump_point.global_position + Vector3(0.55, 0.20, -0.35))
	await _w(10)
	player.global_position = app.builder.mine_cart.global_transform * Vector3(1.2, 1.55, -0.9)
	await _w(6)
	app.builder.mine_cart.begin_departure()
	await _w(50)
	player.look_at_point(rig.crate.global_position + Vector3(0.0, 0.15, 0.0))
	await _w(10)
	await _shot("05_departing.png", "发车中：矿车以 %.1f m/s 驶离，货物仍被固定带约束（漂移 %.3f m）" % [
		app.builder.mine_cart.speed,
		rig.to_local(rig.crate.global_position).distance_to(Act1CargoRig.CRATE_CENTER)])
	print("CAP secured=%s tension=%.0f clicks=%d latch=%s flag=%s" % [
		str(rig.secured()), rig.tension(), rig.clicks, str(rig.latch_open), str(app.flags["cargo_secured"])])
	get_tree().quit(0)


func _player_view(p: Act1StationPlayer, pos: Vector3, look: Vector3) -> void:
	p.teleport(pos, 0.0, -0.06)
	p.global_position = pos
	p.look_at_point(look)
	if p.camera != null:
		p.camera.make_current()


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


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
