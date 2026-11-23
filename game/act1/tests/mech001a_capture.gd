extends Node
## MECHANICS-001A · 真实窗口截图（需图形驱动，不能 headless）
## 取景只移动玩家/相机，不改机械状态；绞盘与模块走真实物理。

const OUT := "res://act1/captures/mech001a"

var app: Node
var cart: Act1PowerCart
var mod: RigidBody3D
var cam: Camera3D


func _ready() -> void:
	var ps: PackedScene = load("res://act1/act01.tscn") as PackedScene
	app = ps.instantiate()
	add_child(app)
	await _w(90)
	cart = app.builder.power_cart
	mod = app.builder.power_module
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_hide_briefing()
	# 第一幕剧情是"恢复电源"：通电前站内照明是关的，截图会全黑。
	# 取景前先点亮站内照明（只影响灯光，不改任何机械状态）。
	if app.has_method("_builder_power_light_on"):
		app.call("_builder_power_light_on")
	await _w(20)

	# ① 电源区全景（未通电）：以导轨中点为锚，退到斜上方俯看
	var rail_mid: Vector3 = Vector3(Act1StationBuilder.SOCKET.x, 1.34,
		(Act1PowerCart.RAIL_Z + Act1StationBuilder.SOCKET.z) * 0.5)
	_look(rail_mid + Vector3(3.0, 1.9, 3.2), rail_mid, -0.35)
	await _shot("01_power_zone_before")

	# ② 模块停在导轨起点（以模块为中心）
	_look(mod.global_position + Vector3(2.0, 1.0, 1.6), mod.global_position, -0.28)
	await _shot("02_module_on_rail")

	# ③ 推车到位 + 绞盘牵引中
	cart.global_position.x = Act1PowerCart.DOCK_X
	cart.docked = true
	await _w(6)
	cart.transfer_module(Act1StationBuilder.SOCKET)
	await _w(18)
	_look(mod.global_position + Vector3(2.0, 1.0, 1.5), mod.global_position, -0.28)
	await _shot("03_winch_pulling")

	# ④ 物理就位 + 机械夹锁定
	for i in range(600):
		await get_tree().physics_frame
		if cart.module_transferred_flag:
			break
	await _w(30)
	app.flags["power_clamped"] = true
	app._builder_power_light_on()
	await _w(20)
	_look(mod.global_position + Vector3(1.9, 1.1, 1.4), mod.global_position, -0.30)
	await _shot("04_module_seated")

	get_tree().quit(0)


func _hide_briefing() -> void:
	# 开场简报是 hud._intro（默认 6.5 s 后淡出），取景前直接隐藏；HUD 其余保留
	if app != null and app.hud != null and "_intro" in app.hud:
		var intro: CanvasItem = app.hud.get("_intro") as CanvasItem
		if intro != null:
			intro.visible = false
	for n: Node in app.find_children("*", "CanvasItem", true, false):
		var ci: CanvasItem = n as CanvasItem
		if ci == null:
			continue
		var nm: String = str(ci.name).to_lower()
		if nm.contains("brief") or nm.contains("intro") or nm.contains("titlecard"):
			ci.visible = false


func _look(from: Vector3, target: Vector3, pitch: float) -> void:
	# 独立相机取景：不再依赖玩家胶囊的位置/朝向（之前总是拍偏或对着灯）
	if cam == null:
		cam = Camera3D.new()
		cam.name = "CaptureCam"
		cam.fov = 65.0
		cam.near = 0.05
		cam.far = 200.0
		add_child(cam)
		cam.make_current()
	cam.global_position = from
	var d: Vector3 = target - from
	if d.length() < 0.01:
		return
	cam.look_at(target, Vector3.UP)
	var _p: float = pitch


func _w(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT_FAIL ", name)
		return
	var err: int = img.save_png(OUT + "/" + name + ".png")
	# 用平均亮度判断这张图到底有没有内容（全黑 = 取景/照明失败）
	var small: Image = img.duplicate()
	small.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var sum: float = 0.0
	for y in range(small.get_height()):
		for x in range(small.get_width()):
			var c: Color = small.get_pixel(x, y)
			sum += (c.r + c.g + c.b) / 3.0
	var lum: float = sum / float(small.get_width() * small.get_height())
	print("SHOT %s %dx%d err=%d lum=%.3f" % [name, img.get_width(), img.get_height(), err, lum])
