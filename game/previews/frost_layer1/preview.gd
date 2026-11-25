extends Main3D

const PREVIEW_PLAYER: Script = preload("res://previews/frost_layer1/player.gd")
const PREVIEW_SESSION: Script = preload("res://previews/frost_layer1/session.gd")
const PREVIEW_ITEMS: Script = preload("res://previews/frost_layer1/items.gd")
const ROUTE: Array[Vector2i] = [Vector2i(0,6), Vector2i(-6,6), Vector2i(-6,1), Vector2i(-8,1), Vector2i(-8,-5), Vector2i(-4,-5), Vector2i(-4,-7), Vector2i(3,-7), Vector2i(3,-1), Vector2i(2,-1), Vector2i(2,0), Vector2i(0,0)]
var cells: Dictionary = {}
var walker: SpacePlayer3D
var shortcut_open: bool = false
var entered: bool = false
var returned: bool = false
var gate: StaticBody3D
var gate_panel: MeshInstance3D
var latch_lever: StaticBody3D
var status: Label
var prompt: Label
var prompt_back: ColorRect
var elapsed: float = 0.0
var notice: String = ""
var notice_time: float = 0.0
var trace: Array = []
var distance_walked: float = 0.0
var last_position: Vector3

func _ready() -> void:
	is_host = true
	game_started = true
	ship_active = false
	current_planet_id = "frost_preview"
	connected_ids = [1]
	_settings_visible = false
	_world_root = Node3D.new()
	_world_root.name = "PreviewItemWorld"
	add_child(_world_root)
	_ship_session = PREVIEW_SESSION.new() as ShipSession3D
	add_child(_ship_session)
	_items = PREVIEW_ITEMS.new() as CrewItems3D
	add_child(_items)
	_build_space()
	walker = PREVIEW_PLAYER.new() as SpacePlayer3D
	walker.setup(1, Color("#69c7de"))
	players[1] = walker
	add_child(walker)
	walker.position = Vector3(0, 0.05, 48)
	last_position = walker.position
	var sensor: OmniLight3D = walker.get_node("PlayerSensorLight") as OmniLight3D
	sensor.light_energy = 0.16
	sensor.omni_range = 5.0
	walker._camera_pitch_target = -0.08
	_items.add_item(1, "oxygen")
	_items.mount_oxygen(1)
	_items.ensure_bag(1).equipment_active = false
	notice_time = 0.0
	_health_hud = HealthHUD3D.new()
	add_child(_health_hud)
	_build_preview_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	DisplayServer.window_set_title("霜烬星 · 第1层独立灰盒")
	print("FROST_PREVIEW_READY: shared 5 HP / inventory / oxygen jet; no save writes")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_settings_visible = not _settings_visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _settings_visible else Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB and not _settings_visible:
			_items.handle_action(1, "toggle_equipment")
		if event.physical_keycode == KEY_F5:
			get_tree().reload_current_scene()

func _process(delta: float) -> void:
	if walker == null:
		return
	if not _settings_visible:
		elapsed += delta
	distance_walked += walker.position.distance_to(last_position)
	last_position = walker.position
	notice_time = maxf(0.0, notice_time - delta)
	if not entered and absf(walker.position.z) < 11 and walker.position.x > -7 and walker.position.x < 19:
		entered = true
		trace.append({"event": "entered", "seconds": elapsed, "distance": distance_walked})
		print("FROST_ENTERED ", elapsed)
	if entered and shortcut_open and not returned and walker.position.distance_to(Vector3(0,0,48)) < 6:
		returned = true
		trace.append({"event": "returned", "seconds": elapsed, "distance": distance_walked})
		print("FROST_RETURNED ", elapsed, " distance=", distance_walked)
	status.text = "霜烬星 · 空间预览" if not returned else "已返回停机坪 · F5 再次探索"
	var latch: bool = _can_open()
	prompt.text = "E  拉开维修门" if latch else ("门闩在另一侧" if not shortcut_open and walker.position.distance_to(Vector3(0,0,30)) < 4 else _items.item_hint(1))
	if notice_time > 0:
		prompt.text = notice
	if _settings_visible:
		prompt.text = "已暂停操作 · Esc 继续 · F5 重来"
	prompt_back.visible = not prompt.text.is_empty()

func _physics_process(_delta: float) -> void:
	pass

func handle_action(peer: int, action: String) -> void:
	if _settings_visible:
		return
	if action == "interact":
		if _can_open():
			shortcut_open = true
			latch_lever.rotation_degrees.z = 50
			var opening: Tween = create_tween()
			opening.tween_property(gate,"position:x",9.0,0.5)
			opening.finished.connect(func() -> void: gate.collision_layer = 0)
			trace.append({"event": "gate_open", "seconds": elapsed, "distance": distance_walked})
			show_notice("维修门已打开")
			print("FROST_GATE_OPEN ", elapsed)
		else:
			var nearby: Dictionary = _items.nearby_item(peer)
			if not nearby.is_empty():
				_items.pickup(peer, nearby)
	elif action == "item_use" and _items.selected(peer).is_empty():
		walker.show_attack_animation()
	elif action != "item_scan":
		_items.handle_action(peer, action)

func _can_open() -> bool:
	if shortcut_open or walker == null or walker.position.z >= 27:
		return false
	var target: Vector3 = Vector3(2.7, 1.2, 26.85)
	return walker.position.distance_to(target) < 3.2 and walker.aim_direction().dot((target - walker._camera.global_position).normalized()) > 0.35

func show_notice(message: String) -> void:
	notice = message
	notice_time = 2.0

func _build_space() -> void:
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#a4becd")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c1dbe6")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	add_child(env_node)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("#e2f0ff")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	for index: int in ROUTE.size() - 1:
		var cell: Vector2i = ROUTE[index]
		var target: Vector2i = ROUTE[index+1]
		cells[cell] = true
		while cell != target:
			cell += Vector2i(signi(target.x-cell.x), signi(target.y-cell.y))
			cells[cell] = true
	for x: int in range(-1, 2):
		for z: int in range(5, 8):
			cells[Vector2i(x,z)] = true
	for x: int in range(-1, 3):
		for z: int in range(-1, 2):
			cells[Vector2i(x,z)] = true
	for z: int in range(1, 6):
		cells[Vector2i(0,z)] = true
	# Three distinct spaces interrupt the ravine: a broken loading court,
	# an elevated ice-window lookout, and the buried north maintenance gallery.
	for center: Vector2i in [Vector2i(-6,6),Vector2i(-8,-3),Vector2i(-4,-7)]:
		for dx: int in range(-1,2):
			for dz: int in range(-1,2):
				cells[center+Vector2i(dx,dz)] = true
	var directions: Array[Vector2i] = [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]
	for cell: Vector2i in cells:
		var p: Vector3 = Vector3(cell.x*8,0,cell.y*8)
		_box("Ground", p + Vector3(0,-0.4,0), Vector3(8,0.8,8), Color("#a0b4bf"))
		for dir: Vector2i in directions:
			if not cells.has(cell+dir):
				var wall: Vector3 = p + Vector3(dir.x*4,4,dir.y*4)
				if cell.x == -7 and cell.y in [-4,-3,-2] and dir == Vector2i(1,0):
					_frozen_window(wall)
				else:
					var ridge: StaticBody3D = _box("IceRidge", wall, Vector3(0.8,8,8.6) if dir.x != 0 else Vector3(8.6,8,0.8), Color("#496779"))
					if posmod(cell.x+cell.y,3) == 0:
						_box("RidgeCrown",ridge.position+Vector3(0,4,0),Vector3(2.0,2.0,3.0),Color("#607e90"))
	# Local rise: ordinary steps and a broad ramp, never a mandatory jet gate.
	var ramp: StaticBody3D = _box("SnowRamp",Vector3(-64,0.6,-8),Vector3(7.2,0.4,12),Color("#e0e8e8"))
	ramp.rotation.x = deg_to_rad(7)
	_box("Lookout",Vector3(-64,0.5,-17),Vector3(7.2,1,6),Color("#b2ccd9"))
	_box("LookoutStep",Vector3(-59,0.25,-17),Vector3(3,0.5,6),Color("#a4bbc7"))
	_box("CourtDeck",Vector3(-48,0.02,48),Vector3(18,0.04,18),Color("#627880"))
	_box("LoadingCrate",Vector3(-54,1.2,53),Vector3(3,2.4,3),Color("#465e6a"))
	_box("TiltedCrate",Vector3(-40,0.8,54),Vector3(2.5,1.6,3.5),Color("#465e6a")).rotation_degrees.z = -12
	_box("GalleryRoof",Vector3(-32,5.7,-56),Vector3(21,0.6,18),Color("#405666"))
	for x: float in [-40,-24]:
		_box("GalleryPillar",Vector3(x,2.7,-52),Vector3(1.2,5.4,1.2),Color("#405666"))
	_light(Vector3(-32,3.5,-56),Color("#ffd2a1"),13,1.5)
	# Starting pad and a deliberately blocked direct route.
	_box("LandingPad",Vector3(0,0.01,48),Vector3(15,0.04,15),Color("#526873"))
	for x: float in [-5.5,5.5]:
		_box("PadLight",Vector3(x,0.08,48),Vector3(0.22,0.08,11),Color("#f1bc64"),false,true)
	_box("ShelterBack",Vector3(0,2.5,59.5),Vector3(15,5,0.6),Color("#354d5c"))
	_box("ShelterRoof",Vector3(0,5,55),Vector3(15,0.5,10),Color("#354d5c"))
	# Landmark rises above the ice ridge; entrance is on the east side.
	_box("TowerBase",Vector3(-5,5,-3),Vector3(4,10,4),Color("#344854"))
	_box("BrokenTower",Vector3(-5,15,-3),Vector3(1.6,12,1.6),Color("#344854"))
	_box("TowerCrossarm",Vector3(-5,19,-3),Vector3(6,0.5,0.8),Color("#344854"))
	_box("TowerBeacon",Vector3(-5,21.7,-3),Vector3(2.4,1.1,2.4),Color("#ffbb65"),false,true)
	_light(Vector3(-5,20,-3),Color("#ffad52"),16,3)
	# A roofed ruin with real walls, doorway, columns, and a side alcove.
	_box("RuinRoof",Vector3(7,5.8,0),Vector3(24,0.6,21),Color("#3b535f"))
	_box("RuinWest",Vector3(-8,2.8,0),Vector3(0.6,5.6,23),Color("#405966"))
	_box("RuinNorth",Vector3(3,2.8,-11.5),Vector3(22,5.6,0.6),Color("#405966"))
	_box("RuinFrontLeft",Vector3(-5.8,2.8,11.5),Vector3(4.4,5.6,0.6),Color("#405966"))
	_box("RuinFrontRight",Vector3(10,2.8,11.5),Vector3(12,5.6,0.6),Color("#405966"))
	_box("RuinEast",Vector3(19.5,2.8,4.7),Vector3(0.6,5.6,13.4),Color("#405966"))
	_box("EntryLintel",Vector3(19.5,5.0,-5.8),Vector3(0.6,1.6,7.6),Color("#405966"))
	for p: Vector3 in [Vector3(2,2.7,-3),Vector3(11,2.7,3)]:
		_box("RuinColumn",p,Vector3(1.2,5.4,1.2),Color("#405966"))
	_box("CollapsedBench",Vector3(6,0.5,-5),Vector3(4,1,1.2),Color("#788f97"))
	# The broken mechanism is a spatial focal point, not an objective/reward.
	_box("MechanismFoot",Vector3(-3,0.4,4),Vector3(3.2,0.8,3.2),Color("#42535d"))
	_box("MechanismLeft",Vector3(-4.3,2.2,4),Vector3(0.6,3.6,0.8),Color("#607b87"))
	_box("MechanismRight",Vector3(-1.7,2.2,4),Vector3(0.6,3.6,0.8),Color("#607b87"))
	_box("MechanismBrokenArm",Vector3(-3.3,3.8,4),Vector3(2,0.6,0.8),Color("#607b87")).rotation_degrees.z = -18
	_light(Vector3(17,3,-6),Color("#ffc986"),12,2)
	_light(Vector3(0,3,3),Color("#92dbde"),13,1.6)
	# Closed gate spans the sole southern return corridor.
	gate = _box("ShortcutDoor",Vector3(0,3.3,28),Vector3(7.8,6.6,0.65),Color("#46515c"))
	gate_panel = gate.get_child(0) as MeshInstance3D
	_box("LatchPost",Vector3(2.7,1.25,27.3),Vector3(0.35,2.5,0.5),Color("#304c5a"))
	_box("InsideLatch",Vector3(2.7,1.2,27.05),Vector3(0.65,0.9,0.18),Color("#304c5a"))
	latch_lever = _box("LatchLever",Vector3(2.7,1.2,26.85),Vector3(0.15,0.65,0.18),Color("#f5bc5c"),true,true)
	latch_lever.rotation_degrees.z = -25
	_wall_arrow(Vector3(2.7,2.3,27.6),false)
	# Heat traces only guide this layer; no melting/resource/temperature system.
	for index: int in range(1,ROUTE.size()-1):
		var p: Vector3 = Vector3(ROUTE[index].x*8,0,ROUTE[index].y*8)
		_box("WarmVent",p+Vector3(2.6,0.2,2.6),Vector3(0.7,0.4,0.7),Color("#df9a57"),true,true)
		_light(p+Vector3(2.6,1,2.6),Color("#ffbc74"),7,0.9)
		_box("WarmScuff",p+Vector3(0,0.025,0),Vector3(2,0.04,2),Color("#7e9b9f"),false)
	_wall_arrow(Vector3(-3.0,1.8,43.6),true)
	# Sparse silhouettes above the corridor walls, not traversable fake scenery.
	for p: Vector3 in [Vector3(-40,9,20),Vector3(-25,9,-25),Vector3(10,10,-35)]:
		_box("IceMass",p,Vector3(12,18,13),Color("#7399ac"))

func _box(label: String, p: Vector3, dimensions: Vector3, color: Color, solid: bool = true, glow: bool = false) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = label
	body.position = p
	body.collision_layer = 2 if solid else 0
	body.collision_mask = 0
	add_child(body)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = dimensions
	mesh.mesh = box_mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	mat.emission_enabled = glow
	mat.emission = color
	mat.emission_energy_multiplier = 0.35 if glow else 0.0
	mesh.material_override = mat
	body.add_child(mesh)
	if solid:
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = dimensions
		collision.shape = shape
		body.add_child(collision)
	return body

func _light(p: Vector3, color: Color, radius: float, energy: float) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.position = p
	light.light_color = color
	light.omni_range = radius
	light.light_energy = energy
	add_child(light)

func _frozen_window(p: Vector3) -> void:
	# Visible solid ice in a recovered steel frame: a view, never an invisible wall.
	_box("WindowSill",p+Vector3(0,-3.4,0),Vector3(0.9,1.2,8.6),Color("#405867"))
	var pane: StaticBody3D = _box("FrozenPane",p+Vector3(0,0.6,0),Vector3(0.25,6.8,8),Color("#9edce1"))
	var mat: StandardMaterial3D = (pane.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.25
	for z: float in [-3.7,0.0,3.7]:
		_box("WindowMullion",p+Vector3(0,0,z),Vector3(0.5,8,0.16),Color("#405867"))

func _wall_arrow(p: Vector3, left: bool) -> void:
	# Raised geometric arrow bolted to a backing plate, never a billboard/Label3D.
	_box("SignPlate",p,Vector3(1.9,1.2,0.12),Color("#304c5a"))
	if left:
		_box("SignPost",Vector3(p.x,0.8,p.z),Vector3(0.18,1.6,0.18),Color("#304c5a"))
	var face: float = 0.08 if left else -0.08
	_box("SignShaft",p+Vector3(0,0,face),Vector3(1,0.18,0.05),Color("#ffd28b"),false,true)
	for angle: float in [-45.0,45.0]:
		var tip: StaticBody3D = _box("SignArrow",p+Vector3(-0.5 if left else 0.5,signf(angle)*0.12,face),Vector3(0.5,0.16,0.05),Color("#ffd28b"),false,true)
		tip.rotation_degrees.z = angle

func _build_preview_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var top_back: ColorRect = ColorRect.new()
	top_back.position = Vector2(490,14)
	top_back.size = Vector2(300,40)
	top_back.color = Color(0.04,0.09,0.13,0.7)
	top_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top_back)
	var bottom_back: ColorRect = ColorRect.new()
	bottom_back.position = Vector2(290,654)
	bottom_back.size = Vector2(920,60)
	bottom_back.color = Color(0.04,0.09,0.13,0.7)
	bottom_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bottom_back)
	status = Label.new()
	status.position = Vector2(465,20)
	status.size = Vector2(350,34)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(status)
	prompt_back = ColorRect.new()
	prompt_back.position = Vector2(380,436)
	prompt_back.size = Vector2(520,42)
	prompt_back.color = Color(0.04,0.09,0.13,0.8)
	prompt_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(prompt_back)
	prompt = Label.new()
	prompt.position = Vector2(380,440)
	prompt.size = Vector2(520,34)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(prompt)
	var help: Label = Label.new()
	help.text = "WASD 移动  ·  鼠标环视  ·  空格 跳跃 / 长按推进  ·  E 操作\nTab 切栏  ·  滚轮 / 1、2 选格  ·  G 放下  ·  Esc 暂停操作  ·  F5 重来"
	help.position = Vector2(300,662)
	help.size = Vector2(900,48)
	help.add_theme_font_size_override("font_size",14)
	layer.add_child(help)
	var dot: ColorRect = ColorRect.new()
	dot.position = Vector2(638,358)
	dot.size = Vector2(4,4)
	dot.color = Color("#effaff")
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dot)
