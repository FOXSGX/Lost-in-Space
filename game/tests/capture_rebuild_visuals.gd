extends SceneTree

## 《迷失太空》太空舱 2.0 & 霜烬星 2.0 gl_compatibility 实机八视角视觉验收截图脚本

const OUT_DIR := "res://../work/rebuild-2026-visuals/"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var abs_out: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_out)

	# ---------------- 1. 主界面（MAYDAY AIRWAYS 暖白手账风）+ 太空舱 2.0 ----------------
	var main: Node = (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait_frames(8)
	var home_img: Image = root.get_texture().get_image()
	home_img.save_png(abs_out + "ui_home_menu.png")
	print("SAVED " + abs_out + "ui_home_menu.png")

	main._ship_session.persistence_enabled = false
	main.network_port = 24572
	main._create_host()
	await _wait_frames(8)
	# 在 B_eye 保留完整 HUD（检验指南针与主线追踪卡），其余视角看纯 3D 美术
	if main._ship_session._layer != null:
		main._ship_session._layer.visible = false
	if main._items != null and main._items.get("_layer") != null:
		main._items._layer.visible = false

	var cam: Camera3D = Camera3D.new()
	cam.near = 0.08
	cam.far = 900.0
	root.add_child(cam)
	cam.current = true

	await _snap(cam, Vector3(0.0, 3.6, 10.2), Vector3(0.0, 1.3, -4.0), 56.0, abs_out + "ship_A_wide.png")
	if main._ship_session._layer != null:
		main._ship_session._layer.visible = true
	if main._items != null and main._items.get("_layer") != null:
		main._items._layer.visible = true
	await _snap(cam, Vector3(0.0, 1.62, 5.2), Vector3(0.0, 1.35, -3.0), 65.0, abs_out + "ship_B_eye.png")
	if main._ship_session._layer != null:
		main._ship_session._layer.visible = false
	if main._items != null and main._items.get("_layer") != null:
		main._items._layer.visible = false
	await _snap(cam, Vector3(2.2, 1.55, 0.2), Vector3(5.2, 1.05, 2.2), 46.0, abs_out + "ship_C_console_closeup.png")
	await _snap(cam, Vector3(-2.1, 1.65, 0.0), Vector3(-5.1, 1.05, 2.1), 50.0, abs_out + "ship_D_refill_and_core.png")
	# 视角 E：回看舱尾星球出舱气闸（正后）与独立训练舱通道（右舷），验证两门 90° 分离与鸿蒙实体挂牌
	await _snap(cam, Vector3(-3.2, 2.35, 3.8), Vector3(2.6, 2.0, 12.6), 62.0, abs_out + "ship_E_airlock_and_training_doors.png")

	# ---------------- 1.5 独立美化训练舱双视角 ----------------
	main.players[1].teleport_to(ShipHub3D.AIRLOCK)
	main._ship_session.request("interact")
	await _wait_frames(10)
	cam.current = true
	await _snap(cam, Vector3(4.5, 2.5, 5.4), Vector3(-3.8, 2.4, -1.8), 64.0, abs_out + "training_A_wide.png")
	await _snap(cam, Vector3(-1.8, 2.2, 4.6), Vector3(-7.6, 1.4, 3.5), 54.0, abs_out + "training_B_bench_and_plaque.png")

	root.remove_child(main)
	main.queue_free()
	await _wait_frames(4)

	# ---------------- 2. 霜烬星 2.0 四视角 ----------------
	var frost: Node = (load("res://previews/frost_station/adventure.tscn") as PackedScene).instantiate()
	root.add_child(frost)
	await _wait_frames(4)
	frost.start_session(true)
	await _wait_frames(8)
	# 点亮动力与雷达，检查物理因果导管与灯效状态
	frost.progress.district_power = true
	frost.progress["radar_online"] = true
	frost.world.apply_progress(frost.progress)
	await _wait_frames(6)

	cam.current = true
	await _snap(cam, Vector3(-28.0, 19.0, 18.0), Vector3(4.0, 2.5, -108.0), 52.0, abs_out + "frost_A_wide.png")
	await _snap(cam, Vector3(0.0, 2.4, -4.0), Vector3(0.0, 4.0, -110.0), 65.0, abs_out + "frost_B_eye.png")
	# 把运输车挪到雪原阳光下做特写审视（不改永久状态）
	var cart: Node3D = frost.world.cart
	cart.position = Vector3(16.0, 0.65, -48.0)
	cart.rotation_degrees = Vector3(0.0, -32.0, 0.0)
	await _wait_frames(4)
	await _snap(cam, Vector3(10.5, 2.2, -42.5), Vector3(16.0, 1.05, -48.0), 46.0, abs_out + "frost_C_rover_closeup.png")
	await _snap(cam, Vector3(14.0, 7.5, -148.0), Vector3(4.0, 6.5, -195.0), 54.0, abs_out + "frost_D_canyon_ice.png")

	# 新增视角 E：11 栋极地建筑群全貌（玻璃温室穹顶 + 高空通讯灯塔 + 货运中转站 + 主建筑群）
	await _snap(cam, Vector3(-118.0, 32.0, 26.0), Vector3(-8.0, 4.0, -96.0), 58.0, abs_out + "frost_E_expanded_town.png")
	# 新增视角 F：精细物品与 5 件新创意玩具雪地近距离陈列特写（氧气瓶/医疗箱/热枪/弹跳垫/信号弹/音响/碰碰球/保温壶）
	var showcase: Node3D = Node3D.new()
	showcase.name = "ItemShowcaseTemp"
	frost.world.add_child(showcase)
	var kinds: Array[String] = ["oxygen", "medical", "battery", "heater", "suction", "bounce_pad", "flare", "boombox", "bumper_orb", "thermos"]
	for i: int in kinds.size():
		var item_vis: Node3D = ItemProp3D.create(kinds[i])
		var row: int = i / 5
		var col: int = i % 5
		item_vis.position = Vector3(-4.2 + float(col) * 1.15, 0.28, -32.2 - float(row) * 1.35)
		item_vis.rotation_degrees.y = -12.0
		showcase.add_child(item_vis)
	await _wait_frames(4)
	await _snap(cam, Vector3(-1.9, 1.85, -28.0), Vector3(-1.9, 0.50, -32.8), 52.0, abs_out + "frost_F_items_and_toys_closeup.png")

	# 新增视角 G：呆萌科考小机器人“小霜” + 4 格物品栏 + 体温/氧气微条 + 头盔微结霜验收
	if frost.players.has(1):
		(frost.players[1] as SpacePlayer3D).warmth = 0.42
	await _wait_frames(12)
	await _snap(cam, Vector3(-5.8, 1.35, -31.2), Vector3(-8.5, 0.72, -34.0), 46.0, abs_out + "frost_G_helper_bot_and_visor_frost.png")

	# 新增视角 H：巨兽遗迹最深处 · 冰封巨兽心脏密钥祭坛
	if frost.players.has(1):
		(frost.players[1] as SpacePlayer3D).warmth = 1.0
	await _wait_frames(8)
	await _snap(cam, Vector3(4.5, 16.0, -591.5), Vector3(-2.4, 15.2, -602.0), 54.0, abs_out + "frost_H_heart_altar_climax.png")

	print("VISUAL_CAPTURE_12_OK dir=" + abs_out)
	quit(0)

func _wait_frames(n: int) -> void:
	for _i: int in n:
		await process_frame

func _snap(cam: Camera3D, pos: Vector3, look: Vector3, fov: float, path: String) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await _wait_frames(5)
	var img: Image = root.get_texture().get_image()
	img.save_png(path)
	print("SAVED " + path)
