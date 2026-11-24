extends Node3D

## 腐墟星废弃学校室内：3 层。
## 1F 大厅/食堂/校长室，2F 教室/实验室，3F 计算机房/天文台/广播站。
## 剧情任务物：天文观测数据（3F 天文台）。

const ART := preload("res://scripts/ruin_cartoon_art.gd")

const LEVELS := 3
const FLOOR_HEIGHT := 3.0
const BASE_Y := 450.0
const W := 24.0
const D := 17.0
const HALF_W := 12.0
const HALF_D := 8.5
const STAIR_X0 := -11.0
const STAIR_X1 := -7.0
const STAIR_Z := 5.0
const CORRIDOR := 1.3

const FLOOR_TILE := Color("#7a7b70")
const WALL := Color("#b5b3a4")
const WALL_LOW := Color("#3d5e58")
const CEILING := Color("#c3c1b2")
const METAL := Color("#4b5756")
const WOOD := Color("#795d3e")
const BLACKBOARD := Color("#2e4a43")
const LINEN := Color("#c8c3b4")
const GLASS := Color("#5d8384")
const RED := Color("#9a4c3f")
const TEAL := Color("#3f6d6c")
const AMBER := Color("#c6944d")
const DARK := Color("#1b2929")
const PAPER := Color("#c9c2ad")

var controller: Main3D
var _flicker_lights: Array[OmniLight3D] = []
var _flicker_phase := 0.0
var _task_items: Dictionary = {}
var _task_points: Dictionary = {}
var _telescope: Node3D
var _blackboard_serial := 0
var _computer_serial := 0


func build(owner: Main3D, parent: Node3D) -> void:
	controller = owner
	name = "RuinSchoolInterior"
	position = Vector3(0.0, BASE_Y, 0.0)
	parent.add_child(self)
	for level: int in LEVELS:
		_build_level(level)
	_build_stairs()
	set_process(true)


func spawn_position() -> Vector3:
	return global_position + Vector3(0.0, 0.15, 7.0)


func exit_position() -> Vector3:
	return global_position + Vector3(0.0, 0.0, 7.9)


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
		var flicker := 0.85 + 0.15 * sin(_flicker_phase * (6.0 + float(index)) + float(index))
		light.light_energy = float(light.get_meta("base_energy", 0.8)) * flicker
	if _telescope != null:
		_telescope.rotation_degrees.y += delta * 2.0


# ── 楼层 ─────────────────────────────────────────────────────

func _build_level(level: int) -> void:
	var y := float(level) * FLOOR_HEIGHT
	_floor_slabs(y)
	_ceiling_slabs(y)
	_walls(y, level)
	_lights(y, level)
	_furnish(level, y)


func _floor_slabs(y: float) -> void:
	_floor_piece(Vector2(-7.0, HALF_W), Vector2(-HALF_D, HALF_D), y)
	_floor_piece(Vector2(-HALF_W, -11.0), Vector2(-HALF_D, HALF_D), y)
	_floor_piece(Vector2(-11.0, -7.0), Vector2(-HALF_D, -STAIR_Z), y)
	_floor_piece(Vector2(-11.0, -7.0), Vector2(STAIR_Z, HALF_D), y)


func _floor_piece(bounds_x: Vector2, bounds_z: Vector2, y: float) -> void:
	var size := Vector3(bounds_x.y - bounds_x.x, 0.22, bounds_z.y - bounds_z.x)
	var center := Vector3((bounds_x.x + bounds_x.y) * 0.5, y - 0.11, (bounds_z.x + bounds_z.y) * 0.5)
	var slab := ART.block(self, "SchoolFloor", size, center, FLOOR_TILE, 0.04)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(size, center)
	for x in range(int(bounds_x.x) + 2, int(bounds_x.y), 3):
		ART.plane(self, "FloorSeam", Vector2(0.03, bounds_z.y - bounds_z.x), Vector3(float(x), y + 0.006, (bounds_z.x + bounds_z.y) * 0.5), Color("#5b635c")).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ceiling_slabs(y: float) -> void:
	var ceiling_y := y + FLOOR_HEIGHT
	_ceiling_piece(Vector2(-7.0, HALF_W), Vector2(-HALF_D, HALF_D), ceiling_y)
	_ceiling_piece(Vector2(-HALF_W, -11.0), Vector2(-HALF_D, HALF_D), ceiling_y)
	_ceiling_piece(Vector2(-11.0, -7.0), Vector2(-HALF_D, -STAIR_Z), ceiling_y)
	_ceiling_piece(Vector2(-11.0, -7.0), Vector2(STAIR_Z, HALF_D), ceiling_y)


func _ceiling_piece(bounds_x: Vector2, bounds_z: Vector2, y: float) -> void:
	var size := Vector3(bounds_x.y - bounds_x.x, 0.14, bounds_z.y - bounds_z.x)
	var center := Vector3((bounds_x.x + bounds_x.y) * 0.5, y + 0.07, (bounds_z.x + bounds_z.y) * 0.5)
	ART.block(self, "SchoolCeiling", size, center, CEILING, 0.04).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _walls(y: float, level: int) -> void:
	var h := FLOOR_HEIGHT
	if level == 0:
		_wall(Vector3(10.8, h, 0.25), Vector3(-6.4, y + h * 0.5, HALF_D))
		_wall(Vector3(10.8, h, 0.25), Vector3(6.4, y + h * 0.5, HALF_D))
		_door_frame(Vector3(0.0, y, HALF_D), 2.2, 2.7, TEAL)
	else:
		_wall(Vector3(W, h, 0.25), Vector3(0.0, y + h * 0.5, HALF_D))
	_wall(Vector3(W, h, 0.25), Vector3(0.0, y + h * 0.5, -HALF_D))
	_wall(Vector3(0.25, h, D), Vector3(-HALF_W, y + h * 0.5, 0.0))
	_wall(Vector3(0.25, h, D), Vector3(HALF_W, y + h * 0.5, 0.0))

	# 西侧楼梯间。
	_wall(Vector3(0.25, h, 1.8), Vector3(STAIR_X1, y + h * 0.5, -7.6))
	_wall(Vector3(0.25, h, 10.6), Vector3(STAIR_X1, y + h * 0.5, 0.0))
	_wall(Vector3(0.25, h, 1.8), Vector3(STAIR_X1, y + h * 0.5, 7.6))
	_door_frame(Vector3(STAIR_X1, y, -6.0), 1.4, 2.4, TEAL)
	_door_frame(Vector3(STAIR_X1, y, 6.0), 1.4, 2.4, TEAL)

	# 中央走廊两侧房间。
	_wall_line_x(CORRIDOR, y, h, [-4.6, 3.4, 7.4], 1.2)
	_wall_line_x(-CORRIDOR, y, h, [-4.6, 3.4, 7.4], 1.2)
	for x: float in [-5.0, 0.0, 5.0]:
		_wall(Vector3(0.20, h, 7.1), Vector3(x, y + h * 0.5, 5.05))
		_wall(Vector3(0.20, h, 7.1), Vector3(x, y + h * 0.5, -5.05))
	for side: float in [-1.0, 1.0]:
		ART.block(self, "Wainscot", Vector3(19.0, 0.92, 0.04), Vector3(2.5, y + 0.46, side * (CORRIDOR - 0.14)), WALL_LOW, 0.03)


func _wall(size: Vector3, center: Vector3) -> void:
	var mesh := ART.block(self, "SchoolWall", size, center, WALL, 0.05)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(size, center)
	ART.block(self, "WallBase", Vector3(size.x + 0.02, 0.14, size.z + 0.02), center + Vector3(0.0, -size.y * 0.5 + 0.07, 0.0), DARK, 0.02)


func _wall_line_x(z: float, y: float, h: float, door_starts: Array, door_width: float) -> void:
	var cursor := STAIR_X1
	var x_end := HALF_W
	for start: float in door_starts:
		if start > cursor:
			var length := start - cursor
			_wall(Vector3(length, h, 0.20), Vector3((cursor + start) * 0.5, y + h * 0.5, z))
		_door_frame(Vector3(start + door_width * 0.5, y, z), door_width, 2.4, TEAL)
		cursor = start + door_width
	if x_end > cursor:
		_wall(Vector3(x_end - cursor, h, 0.20), Vector3((cursor + x_end) * 0.5, y + h * 0.5, z))


func _door_frame(at: Vector3, width: float, height: float, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DoorPost", Vector3(0.14, height, 0.34), at + Vector3(side * width * 0.5, height * 0.5, 0.0), color, 0.03)
	ART.block(self, "DoorHeader", Vector3(width + 0.28, 0.18, 0.34), at + Vector3(0.0, height, 0.0), color, 0.03)


func _build_stairs() -> void:
	for interval: int in LEVELS - 1:
		var lower_y := float(interval) * FLOOR_HEIGHT
		var rises_north := interval % 2 == 0
		var angle := atan(3.0 / 10.0)
		var rotation := angle if rises_north else -angle
		var center := Vector3(-9.0, lower_y + 1.5, 0.0)
		var ramp := ART.block(self, "StairRamp", Vector3(2.8, 0.18, 10.44), center, Color("#8a938c"), 0.04)
		ramp.rotation_degrees.x = rad_to_deg(rotation)
		ramp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_collider(Vector3(2.8, 0.18, 10.44), center, Vector3(rad_to_deg(rotation), 0.0, 0.0))
		for step: int in 14:
			var fraction := (float(step) + 0.5) / 14.0
			var z := 5.0 - fraction * 10.0 if rises_north else -5.0 + fraction * 10.0
			var y := lower_y + fraction * 3.0 + 0.105
			ART.block(self, "StairTread", Vector3(2.7, 0.025, 0.58), Vector3(-9.0, y, z), Color("#a2aaa0"), 0.02).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for side: float in [-1.0, 1.0]:
			var rail_center := Vector3(-9.0 + side * 1.48, lower_y + 1.5, 0.0)
			var rail := ART.block(self, "StairRail", Vector3(0.12, 1.05, 10.2), rail_center, Color("#496463"), 0.03)
			rail.rotation_degrees.x = rad_to_deg(rotation)
			rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_collider(Vector3(0.12, 1.05, 10.2), rail_center, Vector3(rad_to_deg(rotation), 0.0, 0.0))


func _lights(y: float, level: int) -> void:
	for point: Vector2 in [Vector2(-3.5, 5.0), Vector2(4.0, 5.0), Vector2(-3.5, -5.0), Vector2(4.0, -5.0), Vector2(0.0, 0.0)]:
		_light_panel(Vector3(point.x, y + 2.86, point.y), Color("#d9ddd0"), 1.80, 9.0)
	_light_panel(Vector3(0.0, y + 2.86, 7.9), TEAL, 1.10, 5.0)
	_exit_sign(Vector3(0.0, y + 2.45, HALF_D - 0.15))
	if level == 2:
		var red_light := OmniLight3D.new()
		red_light.light_color = RED
		red_light.light_energy = 0.55
		red_light.omni_range = 5.0
		red_light.position = Vector3(2.0, y + 2.2, -5.0)
		red_light.shadow_enabled = false
		red_light.set_meta("base_energy", 0.55)
		add_child(red_light)
		_flicker_lights.append(red_light)


func _light_panel(at: Vector3, color: Color, energy: float, range_value: float) -> void:
	ART.block(self, "SchoolLight", Vector3(1.5, 0.05, 0.34), at, color, 0.02, true, 0.44).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.position = at + Vector3(0.0, -0.28, 0.0)
	light.shadow_enabled = false
	add_child(light)


func _exit_sign(at: Vector3) -> void:
	ART.block(self, "ExitSign", Vector3(0.62, 0.22, 0.08), at, TEAL, 0.02, true, 0.5)
	ART.block(self, "ExitArrow", Vector3(0.22, 0.07, 0.04), at + Vector3(0.0, 0.0, -0.06), Color("#d7f0e0"), 0.01, true, 0.35)


# ── 陈设 ─────────────────────────────────────────────────────

func _furnish(level: int, y: float) -> void:
	match level:
		0:
			_lobby(y)
			_cafeteria(y)
			_principal_office(y)
		1:
			_classrooms(y)
			_science_lab(y)
		2:
			_computer_room(y)
			_astronomy_room(y)
			_broadcast_room(y)
	_corridor_details(y, level)
	_debris(y, level)


func _lobby(y: float) -> void:
	_desk(Vector3(3.0, y, 4.2), 0.0)
	ART.block(self, "TrophyCase", Vector3(2.2, 1.4, 0.25), Vector3(-3.8, y + 1.3, 2.0), GLASS, 0.03, true, 0.08)
	for index: int in 3:
		ART.cylinder(self, "Trophy", 0.10, 0.40, Vector3(-4.4 + float(index) * 0.6, y + 0.9, 2.0), AMBER, true, 0.2)
		ART.block(self, "TrophyBase", Vector3(0.28, 0.12, 0.28), Vector3(-4.4 + float(index) * 0.6, y + 0.66, 2.0), DARK, 0.02)
	ART.block(self, "SchoolBoard", Vector3(4.6, 1.8, 0.06), Vector3(3.0, y + 1.8, 8.25), Color("#4d5a52"), 0.02)
	for index: int in 5:
		ART.plane(self, "SchoolNotice", Vector2(0.45, 0.52), Vector3(1.4 + float(index) * 0.8, y + 1.9, 8.20), Color("#b8ad93")).rotation_degrees.y = PI
	for index: int in 3:
		_chair(Vector3(-2.0 + float(index) * 1.2, y, 6.4), 0.0)
	_locker(Vector3(-6.4, y, 7.1))


func _cafeteria(y: float) -> void:
	for index: int in 3:
		_table(Vector3(-3.2 + float(index) * 2.2, y, -5.0))
		for side: float in [-1.0, 1.0]:
			_chair(Vector3(-3.2 + float(index) * 2.2, y, -6.1 + side * 0.0), 0.0 if side > 0.0 else PI)
	ART.block(self, "ServingCounter", Vector3(3.4, 1.0, 0.9), Vector3(8.0, y + 0.5, -7.1), Color("#5b6f68"), 0.04)
	ART.block(self, "MenuBoard", Vector3(3.2, 1.2, 0.06), Vector3(8.0, y + 1.9, -8.2), DARK, 0.02)
	ART.block(self, "TrayStack", Vector3(0.8, 0.16, 0.55), Vector3(6.8, y + 1.02, -7.1), METAL, 0.02)


func _principal_office(y: float) -> void:
	_desk(Vector3(8.0, y, 5.0), 0.0)
	_cabinet(Vector3(11.0, y, 7.1), 1.0)
	_chair(Vector3(8.0, y, 3.8), PI)
	ART.block(self, "PrincipalShelf", Vector3(2.2, 2.0, 0.45), Vector3(6.2, y + 1.0, 7.7), WOOD, 0.04)
	for index: int in 8:
		ART.block(self, "Book", Vector3(0.14, 0.34, 0.24), Vector3(5.6 + float(index) * 0.16, y + 1.4, 7.42), Color("#7d6350"), 0.01)
	ART.block(self, "PrincipalFrame", Vector3(0.9, 0.65, 0.04), Vector3(9.8, y + 1.9, 7.8), Color("#6d5b44"), 0.02)


func _classrooms(y: float) -> void:
	for room_x: float in [-4.0, 2.0, 8.0]:
		_blackboard(Vector3(room_x, y, 7.9))
		for row: int in 3:
			for column: int in 3:
				_desk(Vector3(room_x - 1.1 + float(column) * 1.1, y, 3.4 + float(row) * 1.3), 0.0)
		ART.block(self, "TeacherDesk", Vector3(1.8, 0.8, 0.8), Vector3(room_x, y + 0.4, 5.9), WOOD, 0.04)
		_cabinet(Vector3(room_x + 2.0, y, 7.1), 0.6)
	# 南侧科学教室/美术教室。
	_blackboard(Vector3(2.0, y, -7.9))
	for index: int in 3:
		_table(Vector3(-2.5 + float(index) * 2.2, y, -5.0))


func _science_lab(y: float) -> void:
	ART.block(self, "LabBench", Vector3(3.6, 0.9, 0.9), Vector3(8.0, y + 0.45, -5.0), Color("#7c8b83"), 0.04)
	for index: int in 4:
		ART.cylinder(self, "Beaker", 0.09, 0.24, Vector3(6.9 + float(index) * 0.65, y + 1.02, -5.0), Color("#84b5aa"), true, 0.15)
	ART.block(self, "LabShelf", Vector3(2.2, 1.6, 0.45), Vector3(8.0, y + 1.0, -7.7), METAL, 0.04)
	ART.block(self, "LabSink", Vector3(1.0, 0.18, 0.55), Vector3(10.5, y + 0.9, -4.0), Color("#b9c4bf"), 0.03)
	ART.block(self, "LabTeacher", Vector3(1.7, 0.8, 0.75), Vector3(8.0, y + 0.4, -8.0), WOOD, 0.04)


func _computer_room(y: float) -> void:
	for row: int in 2:
		for column: int in 3:
			_computer(Vector3(6.5 + float(column) * 1.5, y, 4.4 + float(row) * 1.5), 0.0)
	ART.block(self, "ServerRack", Vector3(0.8, 2.0, 0.7), Vector3(11.0, y + 1.0, 7.6), DARK, 0.04)
	for index: int in 4:
		ART.block(self, "ServerLight", Vector3(0.45, 0.05, 0.02), Vector3(11.0, y + 0.6 + float(index) * 0.35, 7.23), TEAL, 0.01, true, 0.4)
	ART.block(self, "ComputerBoard", Vector3(3.6, 1.6, 0.06), Vector3(8.5, y + 1.9, 8.2), Color("#364e49"), 0.02)


func _astronomy_room(y: float) -> void:
	ART.block(self, "StarMapTable", Vector3(2.2, 0.9, 1.3), Vector3(2.0, y + 0.45, 5.0), Color("#405a56"), 0.04)
	ART.torus(self, "StarMapRing", 0.65, 0.78, Vector3(2.0, y + 0.98, 5.0), TEAL, true, 0.4)
	for index: int in 8:
		var angle := TAU * float(index) / 8.0
		ART.sphere(self, "StarMapStar", Vector3(0.08, 0.08, 0.08), Vector3(2.0 + cos(angle) * 0.45, y + 1.0, 5.0 + sin(angle) * 0.45), Color("#d7e4ce"), true, 0.35)
	_telescope = Node3D.new()
	_telescope.name = "Telescope"
	_telescope.position = Vector3(4.0, y, 5.4)
	add_child(_telescope)
	ART.cylinder(_telescope, "TelescopeBase", 0.45, 0.25, Vector3(0.0, 0.12, 0.0), METAL)
	ART.cylinder(_telescope, "TelescopeTube", 0.16, 2.0, Vector3(0.0, 1.1, 0.0), Color("#8a9b94")).rotation_degrees.x = -28.0
	ART.cylinder(_telescope, "TelescopeLens", 0.20, 0.18, Vector3(0.0, 1.95, -0.45), GLASS, true, 0.2).rotation_degrees.x = -28.0
	_desk(Vector3(9.6, y, 5.0), 0.0)
	ART.block(self, "StarChart", Vector3(1.6, 0.03, 1.0), Vector3(9.6, y + 1.0, 5.0), Color("#8b9c8b"), 0.01)
	for index: int in 7:
		ART.sphere(self, "ChartStar", Vector3(0.06, 0.06, 0.06), Vector3(9.0 + float(index) * 0.18, y + 1.02, 4.8 + float(index % 3) * 0.15), Color("#dce6d3"), true, 0.3)
	var data_root := _register_task_item("school_observation_data", Vector3(9.6, y + 1.01, 5.6), Color("#d8cfb8"))
	ART.block(data_root, "ObservationFolder", Vector3(0.50, 0.06, 0.34), Vector3.ZERO, Color("#b9ac8c"), 0.01)
	ART.block(data_root, "ObservationPrintout", Vector3(0.42, 0.015, 0.28), Vector3(0.02, 0.04, 0.0), PAPER, 0.005)
	ART.block(data_root, "ObservationDisk", Vector3(0.14, 0.02, 0.14), Vector3(0.18, 0.05, -0.04), DARK, 0.005)
	ART.block(self, "AstronomyPoster", Vector3(2.4, 1.6, 0.05), Vector3(8.0, y + 1.8, 8.2), Color("#3c554f"), 0.02)


func _broadcast_room(y: float) -> void:
	_desk(Vector3(2.0, y, -5.2), 0.0)
	ART.block(self, "BroadcastConsole", Vector3(2.4, 0.9, 0.8), Vector3(2.0, y + 0.45, -5.2), Color("#3f5651"), 0.04)
	ART.cylinder(self, "MicrophoneStand", 0.035, 1.2, Vector3(2.0, y + 0.6, -5.8), METAL)
	ART.sphere(self, "Microphone", Vector3(0.18, 0.22, 0.18), Vector3(2.0, y + 1.24, -5.8), Color("#8e9992"))
	ART.block(self, "OnAirLight", Vector3(0.9, 0.28, 0.08), Vector3(2.0, y + 2.25, -8.2), RED, 0.02, true, 0.65)
	ART.block(self, "BroadcastBoard", Vector3(3.0, 1.2, 0.06), Vector3(2.0, y + 1.7, -8.2), Color("#5b5242"), 0.02)
	_chair(Vector3(2.0, y, -4.0), PI)
	_cabinet(Vector3(5.0, y, -7.2), 0.7)


func _corridor_details(y: float, level: int) -> void:
	var color: Color = [TEAL, Color("#7d9b8f"), AMBER][level]
	for x: float in [-3.0, 2.0, 7.0]:
		for side: float in [-1.0, 1.0]:
			var z := side * (CORRIDOR - 0.13)
			ART.block(self, "SchoolSign", Vector3(0.72, 0.30, 0.05), Vector3(x, y + 1.9, z), color, 0.02, true, 0.2)
	ART.cylinder(self, "CorridorPipe", 0.06, 18.0, Vector3(2.5, y + 2.72, 0.95), METAL).rotation_degrees.z = 90.0
	for x: float in [-3.0, 1.0, 5.0, 9.0]:
		ART.block(self, "CeilingBeam", Vector3(0.16, 0.14, 2.5), Vector3(x, y + 2.92, 0.0), Color("#b9ae98"), 0.02)


func _debris(y: float, level: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1201 + level * 89
	for index: int in 8:
		ART.block(self, "SchoolPaper", Vector3(rng.randf_range(0.20, 0.36), 0.012, rng.randf_range(0.16, 0.30)), Vector3(rng.randf_range(-6.0, 10.0), y + 0.02, rng.randf_range(-7.0, 7.0)), Color("#b6ae99"), 0.005).rotation_degrees.y = rng.randf_range(0.0, 180.0)
	ART.plane(self, "SchoolStain", Vector2(1.2, 0.7), Vector3(-2.0, y + 0.02, 3.0), Color("#655d4e")).rotation_degrees.y = 22.0


# ── 小陈设 ───────────────────────────────────────────────────

func _desk(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "SchoolDesk"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Top", Vector3(1.15, 0.08, 0.62), Vector3(0.0, 0.78, 0.0), WOOD, 0.02)
	ART.block(root, "Body", Vector3(1.05, 0.65, 0.55), Vector3(0.0, 0.40, 0.0), Color("#6b5a44"), 0.03)
	for side: float in [-1.0, 1.0]:
		ART.cylinder(root, "Leg", 0.025, 0.55, Vector3(side * 0.45, 0.27, 0.22), METAL)


func _chair(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "SchoolChair"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Seat", Vector3(0.50, 0.08, 0.48), Vector3(0.0, 0.45, 0.0), Color("#496c65"), 0.03)
	ART.block(root, "Back", Vector3(0.50, 0.48, 0.08), Vector3(0.0, 0.70, 0.22), Color("#496c65"), 0.03)
	for side: float in [-1.0, 1.0]:
		ART.cylinder(root, "Leg", 0.025, 0.44, Vector3(side * 0.20, 0.22, 0.16), METAL)


func _table(at: Vector3) -> void:
	ART.block(self, "CafeteriaTable", Vector3(1.7, 0.10, 0.9), at + Vector3(0.0, 0.75, 0.0), Color("#8c7658"), 0.03)
	ART.cylinder(self, "TableLeg", 0.05, 0.72, at + Vector3(0.0, 0.36, 0.0), METAL)


func _blackboard(at: Vector3) -> void:
	_blackboard_serial += 1
	ART.block(self, "Blackboard_%d" % _blackboard_serial, Vector3(3.4, 1.7, 0.06), at + Vector3(0.0, 1.7, 0.0), BLACKBOARD, 0.02)
	ART.block(self, "BlackboardFrame_%d" % _blackboard_serial, Vector3(3.7, 1.9, 0.04), at + Vector3(0.0, 1.7, 0.05), WOOD, 0.02)
	ART.block(self, "ChalkTray_%d" % _blackboard_serial, Vector3(3.3, 0.08, 0.18), at + Vector3(0.0, 0.78, 0.12), WOOD, 0.01)


func _locker(at: Vector3) -> void:
	ART.block(self, "SchoolLocker", Vector3(0.8, 1.9, 0.5), at + Vector3(0.0, 0.95, 0.0), Color("#4e6661"), 0.03)
	for index: int in 3:
		ART.block(self, "LockerDoor", Vector3(0.68, 0.50, 0.03), at + Vector3(0.0, 0.4 + float(index) * 0.56, 0.27), Color("#627b75"), 0.02)


func _cabinet(at: Vector3, width: float) -> void:
	ART.block(self, "SchoolCabinet", Vector3(width, 1.6, 0.55), at + Vector3(0.0, 0.8, 0.0), Color("#667d76"), 0.04)
	ART.block(self, "CabinetDoor", Vector3(width * 0.84, 1.3, 0.04), at + Vector3(0.0, 0.8, 0.29), Color("#4b6560"), 0.02)


func _computer(at: Vector3, yaw_degrees: float) -> void:
	_computer_serial += 1
	var root := Node3D.new()
	root.name = "SchoolComputer_%d" % _computer_serial
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Desk", Vector3(1.2, 0.74, 0.6), Vector3(0.0, 0.37, 0.0), Color("#5f6f68"), 0.03)
	ART.block(root, "Monitor", Vector3(0.55, 0.42, 0.08), Vector3(0.0, 0.95, -0.1), DARK, 0.02)
	ART.block(root, "MonitorGlow", Vector3(0.40, 0.28, 0.03), Vector3(0.0, 0.95, -0.16), TEAL, 0.01, true, 0.4)
	ART.block(root, "Keyboard", Vector3(0.45, 0.04, 0.18), Vector3(0.0, 0.78, 0.15), Color("#9aa59c"), 0.01)


func _register_task_item(item_id: String, point: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "SchoolTask_" + item_id
	root.position = point
	add_child(root)
	_task_items[item_id] = root
	_task_points[item_id] = point
	ART.sphere(root, "TaskGlow", Vector3(0.10, 0.10, 0.10), Vector3(0.0, 0.26, 0.0), color, true, 0.55)
	return root


func _collider(size: Vector3, center: Vector3, rotation_degrees_value := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.name = "SchoolCollision"
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
