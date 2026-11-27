extends Node3D

## 腐墟星万家福超市室内：2 层。
## 1F 卖场/收银/生鲜冷柜/幸存者路障，2F 仓库/办公室/装卸口。
## 剧情任务物：民用导航模块（2F 办公室）。

const ART := preload("res://scripts/ruin_cartoon_art.gd")
const STAIR_TEMPLATE := preload("res://scripts/ruin_stair_template.gd")

const LEVELS := 2
const FLOOR_HEIGHT := 3.2
const BASE_Y := 570.0
const W := 28.0
const D := 18.0
const HALF_W := 14.0
const HALF_D := 9.0
const STAIR_X0 := -14.0
const STAIR_X1 := -9.0
const STAIR_Z := 7.0

const FLOOR_TILE := Color("#65665b")
const WALL := Color("#948f7d")
const WALL_LOW := Color("#425e58")
const CEILING := Color("#a8a291")
const METAL := Color("#4a5656")
const WOOD := Color("#785b3e")
const SHELF := Color("#526c67")
const GLASS := Color("#638889")
const RED := Color("#9b4a3e")
const TEAL := Color("#3d6c6a")
const AMBER := Color("#c99449")
const DARK := Color("#1b2929")
const PAPER := Color("#c9c2ad")
const PRODUCT_COLORS := [Color("#9b5a43"), Color("#6b8767"), Color("#b08c54"), Color("#5d7f86"), Color("#8d6f58")]

var controller: Main3D
var _flicker_lights: Array[OmniLight3D] = []
var _flicker_phase := 0.0
var _task_items: Dictionary = {}
var _task_points: Dictionary = {}
var _shelf_serial := 0
var _checkout_serial := 0
var _barricade_serial := 0


func build(owner: Main3D, parent: Node3D) -> void:
	controller = owner
	name = "RuinMarketInterior"
	position = Vector3(0.0, BASE_Y, 0.0)
	parent.add_child(self)
	for level: int in LEVELS:
		_build_level(level)
	_build_stairs()
	set_process(true)


func spawn_position() -> Vector3:
	return global_position + Vector3(0.0, 0.15, 7.2)


func exit_position() -> Vector3:
	return global_position + Vector3(0.0, 0.0, 8.1)


func level_position(level: int) -> Vector3:
	return global_position + Vector3(0.0, float(level) * FLOOR_HEIGHT, 0.0)


func level_count() -> int:
	return LEVELS


func is_inside(point: Vector3) -> bool:
	var local := point - global_position
	return local.y > -1.0 and local.y < FLOOR_HEIGHT * float(LEVELS) + 1.0 and absf(local.x) <= HALF_W + 2.0 and absf(local.z) <= HALF_D + 2.0


func task_item_positions() -> Dictionary:
	var points: Dictionary = {}
	for id: String in _task_points.keys():
		points[id] = global_position + _task_points[id]
	return points


func collect_task_item(item_id: String) -> void:
	if _task_items.has(item_id):
		var node := _task_items[item_id] as Node3D
		if node != null:
			node.visible = false


func _process(delta: float) -> void:
	_flicker_phase += delta
	for index: int in _flicker_lights.size():
		var light := _flicker_lights[index]
		if not is_instance_valid(light):
			continue
		var flicker := 0.88 + 0.12 * sin(_flicker_phase * (6.0 + float(index)) + float(index))
		light.light_energy = float(light.get_meta("base_energy", 0.8)) * flicker


# ── 楼层 ─────────────────────────────────────────────────────

func _build_level(level: int) -> void:
	var y := float(level) * FLOOR_HEIGHT
	_floor_slabs(y)
	_ceiling_slabs(y)
	_walls(y, level)
	_lights(y, level)
	if level == 0:
		_sales_floor(y)
	else:
		_warehouse(y)
	_office(y, level)
	if level == 0:
		_build_entrance_door(y)


func _floor_slabs(y: float) -> void:
	_floor_piece(Vector2(STAIR_X1, HALF_W), Vector2(-HALF_D, HALF_D), y)
	_floor_piece(Vector2(-HALF_W, STAIR_X0), Vector2(-HALF_D, HALF_D), y)
	_floor_piece(Vector2(STAIR_X0, STAIR_X1), Vector2(-HALF_D, -STAIR_Z), y)
	_floor_piece(Vector2(STAIR_X0, STAIR_X1), Vector2(STAIR_Z, HALF_D), y)


func _floor_piece(bounds_x: Vector2, bounds_z: Vector2, y: float) -> void:
	if bounds_x.y - bounds_x.x < 0.01 or bounds_z.y - bounds_z.x < 0.01:
		return
	var size := Vector3(bounds_x.y - bounds_x.x, 0.22, bounds_z.y - bounds_z.x)
	var center := Vector3((bounds_x.x + bounds_x.y) * 0.5, y - 0.11, (bounds_z.x + bounds_z.y) * 0.5)
	var slab := ART.block(self, "MarketFloor", size, center, FLOOR_TILE, 0.04)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(size, center)
	# 卖场耐磨地砖分缝。
	if bounds_x.y - bounds_x.x > 6.0 and bounds_z.y - bounds_z.x > 6.0:
		for x in range(int(bounds_x.x) + 2, int(bounds_x.y), 3):
			ART.plane(self, "MarketFloorSeam", Vector2(0.025, bounds_z.y - bounds_z.x), Vector3(float(x), y + 0.006, (bounds_z.x + bounds_z.y) * 0.5), Color("#5c635a")).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ceiling_slabs(y: float) -> void:
	var cy := y + FLOOR_HEIGHT
	_ceiling_piece(Vector2(STAIR_X1, HALF_W), Vector2(-HALF_D, HALF_D), cy)
	_ceiling_piece(Vector2(-HALF_W, STAIR_X0), Vector2(-HALF_D, HALF_D), cy)
	_ceiling_piece(Vector2(STAIR_X0, STAIR_X1), Vector2(-HALF_D, -STAIR_Z), cy)
	_ceiling_piece(Vector2(STAIR_X0, STAIR_X1), Vector2(STAIR_Z, HALF_D), cy)


func _ceiling_piece(bounds_x: Vector2, bounds_z: Vector2, y: float) -> void:
	if bounds_x.y - bounds_x.x < 0.01 or bounds_z.y - bounds_z.x < 0.01:
		return
	var size := Vector3(bounds_x.y - bounds_x.x, 0.14, bounds_z.y - bounds_z.x)
	var center := Vector3((bounds_x.x + bounds_x.y) * 0.5, y + 0.07, (bounds_z.x + bounds_z.y) * 0.5)
	ART.block(self, "MarketCeiling", size, center, CEILING, 0.04).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _walls(y: float, level: int) -> void:
	var h := FLOOR_HEIGHT
	# 南墙一层入口，二层封死。
	if level == 0:
		_wall(Vector3(12.7, h, 0.25), Vector3(-7.65, y + h * 0.5, HALF_D))
		_wall(Vector3(12.7, h, 0.25), Vector3(7.65, y + h * 0.5, HALF_D))
		_door_frame(Vector3(0.0, y, HALF_D), 2.6, 2.8, AMBER)
	else:
		_wall(Vector3(W, h, 0.25), Vector3(0.0, y + h * 0.5, HALF_D))
	_wall(Vector3(W, h, 0.25), Vector3(0.0, y + h * 0.5, -HALF_D))
	_wall(Vector3(0.25, h, D), Vector3(-HALF_W, y + h * 0.5, 0.0))
	_wall(Vector3(0.25, h, D), Vector3(HALF_W, y + h * 0.5, 0.0))

	# 楼梯间东墙，上下平台各一个开口。
	# 每层只在楼梯抵达侧留一个入口：1F 南 +7，2F 北 -7。
	var stair_entry := 7.0 if level % 2 == 0 else -7.0
	if stair_entry > 0.0:
		_wall(Vector3(0.25, h, 14.8), Vector3(STAIR_X1, y + h * 0.5, -1.6))
		_wall(Vector3(0.25, h, 0.8), Vector3(STAIR_X1, y + h * 0.5, 8.6))
	else:
		_wall(Vector3(0.25, h, 0.8), Vector3(STAIR_X1, y + h * 0.5, -8.6))
		_wall(Vector3(0.25, h, 14.8), Vector3(STAIR_X1, y + h * 0.5, 1.6))
	STAIR_TEMPLATE.build_door_frame(self, Vector3(STAIR_X1, y, stair_entry), 2.4, 2.5, TEAL)

	# 二层经理办公室：四面封闭，只留 1.4 m 门洞通向卖场。
	if level == 1:
		_wall(Vector3(0.20, h, 5.9), Vector3(4.0, y + h * 0.5, 6.05))
		_wall(Vector3(2.9, h, 0.20), Vector3(5.65, y + h * 0.5, 3.2))
		_wall(Vector3(0.20, h, 5.8), Vector3(8.5, y + h * 0.5, 6.1))
		_door_frame(Vector3(7.8, y, 3.2), 1.4, 2.4, TEAL)

	# 深色墙裙会横穿货架/门洞，已取消。


func _wall(size: Vector3, center: Vector3) -> void:
	var mesh := ART.block(self, "MarketWall", size, center, WALL, 0.05)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(size, center)
	ART.block(self, "WallBase", Vector3(size.x + 0.02, 0.14, size.z + 0.02), center + Vector3(0.0, -size.y * 0.5 + 0.07, 0.0), DARK, 0.02)


func _door_frame(at: Vector3, width: float, height: float, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DoorPost", Vector3(0.16, height, 0.38), at + Vector3(side * width * 0.5, height * 0.5, 0.0), color, 0.03)
	ART.block(self, "DoorHeader", Vector3(width + 0.32, 0.20, 0.38), at + Vector3(0.0, height, 0.0), color, 0.03)


## 1F 入口卷帘门：关着、有碰撞；回头能看到门，门洞不再通向虚空。
func _build_entrance_door(y: float) -> void:
	var door_z := HALF_D - 0.12
	var door_w := 2.6
	ART.block(self, "InteriorEntranceDoorFrameL", Vector3(0.18, 2.9, 0.30), Vector3(-door_w * 0.5, y + 1.45, door_z), METAL, 0.03)
	ART.block(self, "InteriorEntranceDoorFrameR", Vector3(0.18, 2.9, 0.30), Vector3(door_w * 0.5, y + 1.45, door_z), METAL, 0.03)
	for index: int in 10:
		ART.block(self, "InteriorEntranceDoorSlat", Vector3(door_w, 0.20, 0.06), Vector3(0.0, y + 0.18 + float(index) * 0.27, door_z - 0.04), Color("#6f7770") if index % 2 == 0 else Color("#5c6660"), 0.02)
	ART.block(self, "InteriorEntranceDoorHandle", Vector3(0.30, 0.06, 0.06), Vector3(0.0, y + 0.95, door_z - 0.10), AMBER, 0.01, true, 0.15)
	var body := StaticBody3D.new()
	body.name = "InteriorEntranceDoorCollision"
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = Vector3(0.0, y + 1.45, door_z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(door_w, 2.9, 0.14)
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _build_stairs() -> void:
	STAIR_TEMPLATE.build(self, {
		"levels": LEVELS,
		"floor_height": FLOOR_HEIGHT,
		"x0": STAIR_X0,
		"x1": STAIR_X1,
		"stair_z": STAIR_Z,
		"tread_color": Color("#a1a89b"),
		"fill_color": Color("#6b7770"),
		"rail_color": Color("#496463"),
	})


func _lights(y: float, level: int) -> void:
	var color := Color("#e0e6d8") if level == 0 else Color("#cbd8d0")
	for point: Vector2 in [Vector2(-3.0, 5.0), Vector2(6.0, 5.0), Vector2(-3.0, -5.0), Vector2(6.0, -5.0), Vector2(0.0, 0.0)]:
		_light_panel(Vector3(point.x, y + 2.86, point.y), color, 0.90, 9.2)
	_light_panel(Vector3(0.0, y + 2.86, 8.4), AMBER, 0.60, 5.2)
	_key_light(Vector3(0.0, y + 2.92, 0.0), Color("#e7f0d8"), 1.1, 14.0)
	if level == 0:
		var red_light := OmniLight3D.new()
		red_light.light_color = RED
		red_light.light_energy = 0.42
		red_light.omni_range = 4.5
		red_light.position = Vector3(-6.0, y + 2.2, 7.4)
		red_light.shadow_enabled = false
		red_light.set_meta("base_energy", 0.42)
		add_child(red_light)
		_flicker_lights.append(red_light)


func _light_panel(at: Vector3, color: Color, energy: float, range_value: float) -> void:
	ART.block(self, "MarketLight", Vector3(1.8, 0.05, 0.34), at, color, 0.02, true, 0.44).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.position = at + Vector3(0.0, -0.28, 0.0)
	light.shadow_enabled = false
	add_child(light)


func _key_light(at: Vector3, color: Color, energy: float, range_value: float) -> void:
	var light := SpotLight3D.new()
	light.name = "MarketKeyLight"
	light.light_color = color
	light.light_energy = energy
	light.spot_range = range_value
	light.spot_angle = 50.0
	light.spot_angle_attenuation = 1.3
	light.shadow_enabled = true
	light.shadow_bias = 0.08
	light.position = at
	light.rotation_degrees.x = -90.0
	add_child(light)


# ── 1F 卖场 ──────────────────────────────────────────────────

func _sales_floor(y: float) -> void:
	# 货架走道。
	for index: int in 4:
		_shelf(Vector3(-4.0 + float(index) * 3.0, y, -2.6))
		_shelf(Vector3(-4.0 + float(index) * 3.0, y, -0.6))
	for index: int in 3:
		_shelf(Vector3(-4.0 + float(index) * 3.2, y, -5.2))
	# 收银台。
	for index: int in 2:
		_checkout(Vector3(-4.5 + float(index) * 7.3, y, 6.2))
	# 入口路障与营地。
	_barricade(Vector3(-7.0, y, 7.2))
	_barricade(Vector3(-5.8, y, 6.8))
	_message_board(Vector3(5.8, y, 8.25))
	_crate(Vector3(6.4, y, 6.7), 0.7, 0.6)
	_crate(Vector3(7.5, y, 6.9), 0.5, 0.55)
	_cart(Vector3(-1.8, y, 4.8))
	_cart(Vector3(8.5, y, 1.8))
	# 冷柜与生鲜。
	for index: int in 3:
		_freezer(Vector3(10.0, y, -4.0 + float(index) * 2.2), 0.0)
	# 血痕：从入口延伸。
	_blood_trail(Vector3(1.0, y + 0.012, 8.0), Vector3(0.0, y + 0.012, 1.0), 9, 1.0)
	# 通风口污染：菌群从通风口灌入的线索。
	ART.block(self, "VentGrate", Vector3(2.2, 1.3, 0.10), Vector3(-7.0, y + 2.0, 8.25), DARK, 0.03)
	for index: int in 6:
		ART.block(self, "VentSlat", Vector3(1.8, 0.07, 0.04), Vector3(-7.0, y + 1.55 + float(index) * 0.18, 8.17), METAL, 0.01)
	ART.block(self, "VentGrowth", Vector3(0.7, 0.35, 0.06), Vector3(-6.2, y + 2.25, 8.15), Color("#558e7c"), 0.02, true, 0.2)
	# 倒地货架/散货。
	var fallen := ART.block(self, "FallenShelf", Vector3(2.6, 0.22, 0.7), Vector3(4.0, y + 0.12, -7.0), SHELF, 0.04)
	fallen.rotation_degrees.z = 8.0
	for index: int in 10:
		ART.block(self, "SpilledCan", Vector3(0.13, 0.18, 0.13), Vector3(3.2 + float(index) * 0.22, y + 0.16, -6.8 + float(index % 3) * 0.3), PRODUCT_COLORS[index % PRODUCT_COLORS.size()], 0.01)


# ── 2F 仓库/办公室 ──────────────────────────────────────────

func _warehouse(y: float) -> void:
	# 货架、托盘和装卸区。
	for index: int in 4:
		_pallet(Vector3(-3.0 + float(index) * 3.2, y, -5.8))
		_pallet(Vector3(-3.0 + float(index) * 3.2, y, 0.0))
	for index: int in 3:
		ART.block(self, "WarehouseShelf", Vector3(2.8, 0.12, 1.0), Vector3(-4.0 + float(index) * 3.6, y + 1.4, -7.8), METAL, 0.03)
		for crate: int in 2:
			_crate(Vector3(-4.0 + float(index) * 3.6, y + 1.5, -7.8), 0.55, 0.45)
	# 装卸卷帘门。
	ART.block(self, "LoadingDoor", Vector3(4.6, 2.7, 0.20), Vector3(11.0, y + 1.35, 8.8), Color("#606d69"), 0.05)
	for index: int in 8:
		ART.block(self, "LoadingSlat", Vector3(4.4, 0.08, 0.05), Vector3(11.0, y + 0.25 + float(index) * 0.30, 8.66), METAL, 0.01)
	ART.block(self, "LoadingYellow", Vector3(4.6, 0.16, 0.16), Vector3(11.0, y + 2.72, 8.7), AMBER, 0.02, true, 0.2)
	# 叉车/搬运设备。
	ART.block(self, "ForkliftBody", Vector3(1.5, 1.0, 1.9), Vector3(7.8, y + 0.55, 4.8), Color("#a9793d"), 0.05)
	ART.block(self, "ForkliftMast", Vector3(0.5, 2.2, 0.25), Vector3(7.8, y + 1.2, 6.0), METAL, 0.03)
	ART.block(self, "ForkliftFork", Vector3(1.2, 0.08, 0.9), Vector3(7.8, y + 0.25, 6.6), METAL, 0.01)


func _office(y: float, level: int) -> void:
	if level != 1:
		return
	_light_panel(Vector3(9.0, y + 2.86, 5.8), Color("#d8dfd3"), 0.85, 5.5)
	_desk(Vector3(10.0, y, 5.6), 0.0)
	_chair(Vector3(10.0, y, 4.4), PI)
	ART.block(self, "OfficeShelf", Vector3(2.4, 1.7, 0.45), Vector3(12.0, y + 0.85, 7.8), WOOD, 0.04)
	ART.block(self, "NavMonitor", Vector3(0.7, 0.46, 0.10), Vector3(10.0, y + 1.35, 5.9), DARK, 0.02)
	ART.block(self, "NavMonitorGlow", Vector3(0.52, 0.32, 0.04), Vector3(10.0, y + 1.35, 5.84), TEAL, 0.01, true, 0.38)
	ART.block(self, "OfficeMap", Vector3(2.0, 1.0, 0.05), Vector3(10.0, y + 1.8, 8.2), Color("#536762"), 0.02)
	# 民用导航模块：运输无人机保存着离开腐墟星的导航密钥。
	var nav := _register_task_item("market_navigation_module", Vector3(10.0, y + 1.02, 5.6), Color("#8fd8cc"))
	ART.block(nav, "NavModule", Vector3(0.46, 0.20, 0.34), Vector3.ZERO, Color("#4f6b68"), 0.03)
	ART.block(nav, "NavModuleScreen", Vector3(0.30, 0.10, 0.02), Vector3(0.0, 0.10, -0.18), TEAL, 0.01, true, 0.45)
	ART.cylinder(nav, "NavAntenna", 0.018, 0.26, Vector3(0.16, 0.24, 0.08), METAL)
	ART.sphere(nav, "NavLight", Vector3(0.05, 0.05, 0.05), Vector3(0.16, 0.39, 0.08), AMBER, true, 0.5)
	# 幸存者留言板，暗示这里曾撑过一阵。
	for index: int in 4:
		ART.plane(self, "SurvivorNote", Vector2(0.30, 0.22), Vector3(9.0 + float(index) * 0.48, y + 1.5, 8.16), Color("#b9af97")).rotation_degrees.y = PI


# ── 小陈设 ───────────────────────────────────────────────────

func _shelf(at: Vector3) -> void:
	_shelf_serial += 1
	_collider(Vector3(2.6, 1.8, 1.15), at + Vector3(0.0, 0.9, 0.0))
	ART.block(self, "GondolaBase_%d" % _shelf_serial, Vector3(2.6, 0.22, 1.15), at + Vector3(0.0, 0.11, 0.0), METAL, 0.03)
	ART.block(self, "GondolaBack_%d" % _shelf_serial, Vector3(2.6, 1.8, 0.12), at + Vector3(0.0, 0.95, 0.0), SHELF, 0.03)
	for row: int in 3:
		ART.block(self, "GondolaShelf_%d" % _shelf_serial, Vector3(2.5, 0.08, 0.8), at + Vector3(0.0, 0.55 + float(row) * 0.42, -0.12), Color("#7d8e83"), 0.02)
		for column: int in 7:
			ART.block(self, "GondolaProduct_%d" % _shelf_serial, Vector3(0.24, 0.22, 0.28), at + Vector3(-1.05 + float(column) * 0.34, 0.70 + float(row) * 0.42, -0.12), PRODUCT_COLORS[(row + column) % PRODUCT_COLORS.size()], 0.01)
	ART.block(self, "PriceRail_%d" % _shelf_serial, Vector3(2.5, 0.10, 0.05), at + Vector3(0.0, 1.25, 0.55), AMBER, 0.01)


func _checkout(at: Vector3) -> void:
	_checkout_serial += 1
	_collider(Vector3(2.3, 0.95, 0.9), at + Vector3(0.0, 0.48, 0.0))
	ART.block(self, "CheckoutBelt_%d" % _checkout_serial, Vector3(2.3, 0.12, 0.9), at + Vector3(0.0, 0.85, 0.0), Color("#3f4e4c"), 0.03)
	ART.block(self, "CheckoutBase_%d" % _checkout_serial, Vector3(2.3, 0.8, 0.9), at + Vector3(0.0, 0.4, 0.0), Color("#5b6a63"), 0.03)
	ART.block(self, "Register_%d" % _checkout_serial, Vector3(0.55, 0.42, 0.55), at + Vector3(0.7, 1.1, 0.0), DARK, 0.02)
	ART.block(self, "RegisterGlow_%d" % _checkout_serial, Vector3(0.38, 0.22, 0.04), at + Vector3(0.7, 1.15, -0.30), TEAL, 0.01, true, 0.35)
	ART.block(self, "CheckoutDivider_%d" % _checkout_serial, Vector3(0.06, 0.8, 0.07), at + Vector3(-0.6, 1.25, 0.0), METAL, 0.01)


func _freezer(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "Freezer"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "FreezerBody", Vector3(1.9, 2.2, 0.9), Vector3(0.0, 1.1, 0.0), Color("#5b7270"), 0.04)
	_collider(Vector3(1.9, 2.2, 0.9), at + Vector3(0.0, 1.1, 0.0), Vector3(0.0, yaw_degrees, 0.0))
	ART.block(root, "FreezerGlass", Vector3(1.55, 1.55, 0.05), Vector3(0.0, 1.2, -0.46), GLASS, 0.02, true, 0.12)
	ART.block(root, "FreezerShelf", Vector3(1.5, 0.05, 0.25), Vector3(0.0, 0.9, -0.40), Color("#aabbb4"), 0.01)
	ART.block(root, "FreezerLight", Vector3(1.4, 0.05, 0.08), Vector3(0.0, 1.9, -0.38), Color("#c9eee7"), 0.01, true, 0.3)


func _crate(at: Vector3, width: float, height: float) -> void:
	_collider(Vector3(width, height, width * 0.85), at + Vector3(0.0, height * 0.5, 0.0))
	ART.block(self, "Crate", Vector3(width, height, width * 0.85), at + Vector3(0.0, height * 0.5, 0.0), Color("#7b6448"), 0.04)
	for index: int in 2:
		ART.block(self, "CrateBand", Vector3(width * 1.02, 0.06, width * 0.87), at + Vector3(0.0, height * 0.35 + float(index) * height * 0.3, 0.0), Color("#5d4b36"), 0.01)


func _pallet(at: Vector3) -> void:
	ART.block(self, "Pallet", Vector3(1.8, 0.14, 1.4), at + Vector3(0.0, 0.07, 0.0), Color("#8b704e"), 0.03)
	for index: int in 3:
		_crate(at + Vector3(0.0, 0.14 + float(index) * 0.55, 0.0), 0.75, 0.55)


func _cart(at: Vector3) -> void:
	_collider(Vector3(0.65, 1.0, 0.9), at + Vector3(0.0, 0.5, 0.0))
	ART.block(self, "CartBasket", Vector3(0.65, 0.45, 0.9), at + Vector3(0.0, 0.65, 0.0), Color("#6f8580"), 0.03)
	for side: float in [-1.0, 1.0]:
		ART.cylinder(self, "CartPost", 0.025, 0.5, at + Vector3(side * 0.28, 0.45, 0.35), METAL)
		ART.torus(self, "CartWheel", 0.07, 0.10, at + Vector3(side * 0.28, 0.10, 0.30), DARK)


func _barricade(at: Vector3) -> void:
	_barricade_serial += 1
	ART.block(self, "BarricadePlank_%d" % _barricade_serial, Vector3(3.6, 0.30, 0.22), at + Vector3(0.0, 1.0, 0.0), Color("#8a6a46"), 0.03).rotation_degrees.z = 3.0
	ART.block(self, "BarricadeLeg_%d" % _barricade_serial, Vector3(0.16, 1.1, 0.16), at + Vector3(-1.5, 0.55, 0.0), METAL, 0.02)
	ART.block(self, "BarricadeLeg_%d" % _barricade_serial, Vector3(0.16, 1.1, 0.16), at + Vector3(1.5, 0.55, 0.0), METAL, 0.02)
	ART.block(self, "BarricadeBox_%d" % _barricade_serial, Vector3(0.9, 0.6, 0.7), at + Vector3(0.4, 0.3, 0.3), Color("#766044"), 0.03)
	ART.block(self, "BarricadeTape_%d" % _barricade_serial, Vector3(3.8, 0.10, 0.06), at + Vector3(0.0, 1.35, 0.0), AMBER, 0.01, true, 0.15)


func _message_board(at: Vector3) -> void:
	ART.block(self, "MessageBoard", Vector3(2.4, 1.5, 0.06), at + Vector3(0.0, 1.7, 0.0), Color("#6e5b43"), 0.02)
	for index: int in 5:
		ART.plane(self, "MessageNote", Vector2(0.32, 0.24), at + Vector3(-0.8 + float(index) * 0.4, 1.8 + float(index % 2) * 0.25, -0.05), Color("#c2b79f")).rotation_degrees.y = PI
	ART.block(self, "MessageText", Vector3(1.4, 0.06, 0.03), at + Vector3(0.2, 1.35, -0.05), Color("#4f4a3f"), 0.01)


func _desk(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "MarketDesk"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Top", Vector3(2.6, 0.10, 0.9), Vector3(0.0, 0.85, 0.0), WOOD, 0.03)
	ART.block(root, "Front", Vector3(2.5, 0.80, 0.16), Vector3(0.0, 0.42, -0.36), Color("#5b6d66"), 0.03)
	_collider(Vector3(2.6, 1.0, 0.9), at + Vector3(0.0, 0.5, 0.0), Vector3(0.0, yaw_degrees, 0.0))


func _chair(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "OfficeChair"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Seat", Vector3(0.55, 0.09, 0.52), Vector3(0.0, 0.46, 0.0), Color("#3e5752"), 0.03)
	ART.block(root, "Back", Vector3(0.55, 0.58, 0.09), Vector3(0.0, 0.76, 0.25), Color("#3e5752"), 0.03)


func _blood_trail(from: Vector3, to: Vector3, count: int, scale_value: float) -> void:
	for index: int in count:
		var t := float(index) / float(maxi(count - 1, 1))
		var point := from.lerp(to, t)
		ART.plane(self, "MarketBlood", Vector2(0.55, 0.32) * scale_value, point, Color("#702f2b"), true, 0.04).rotation_degrees.y = float(index) * 33.0


func _register_task_item(item_id: String, point: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "MarketTask_" + item_id
	root.position = point
	add_child(root)
	_task_items[item_id] = root
	_task_points[item_id] = point
	ART.sphere(root, "TaskGlow", Vector3(0.10, 0.10, 0.10), Vector3(0.0, 0.28, 0.0), color, true, 0.55)
	return root


func _collider(size: Vector3, center: Vector3, rotation_degrees_value := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.name = "MarketCollision"
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = center
	body.rotation_degrees = rotation_degrees_value
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
