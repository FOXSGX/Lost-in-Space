extends Node3D

## 腐墟星能源站内部：4 层工业设施。
##
## 2F 通风/观测，1F 大厅/控制室/汽轮机，B1 泵房/冷却剂，B2 反应堆核心/应急舱。
## 与医院一样，室内放在同一世界的高处，通过大门传送进出。
## 视觉母题：深灰钢构、黄黑警示条、青绿星髓光、橙色应急灯、粗管线和格栅。

const ART := preload("res://scripts/ruin_cartoon_art.gd")
const ART_SAMPLE := preload("res://scripts/ruin_art_sample.gd")

const LEVELS := 4
const FLOOR_HEIGHT := 3.0
const BASE_Y := 320.0
const W := 30.0
const D := 20.0
const HALF_W := 15.0
const HALF_D := 10.0
const CORE_HALF := 4.0
const STAIR_X0 := -14.0
const STAIR_X1 := -10.0
const STAIR_Z := 6.0

const STEEL := Color("#3f4b4d")
const STEEL_LIGHT := Color("#6b7978")
const STEEL_DARK := Color("#253234")
const CONCRETE := Color("#6d7068")
const CONCRETE_LIGHT := Color("#8a8b80")
const RUST := Color("#84513d")
const AMBER := Color("#d08a3d")
const AMBER_LIGHT := Color("#f0b45f")
const TEAL := Color("#2c6666")
const CORE_GLOW := Color("#59e0c6")
const CORE_DEEP := Color("#1d6f67")
const HAZARD := Color("#1b2425")
const BLOOD := Color("#6f302c")
const CABLE := Color("#202b2e")

const LEVEL_NAMES := ["B2 反应堆核心", "B1 泵房与冷却", "1F 大厅与控制", "2F 通风与观测"]

var controller: Main3D
var _flicker_lights: Array[OmniLight3D] = []
var _flicker_phase := 0.0
var physics_door: LISHingeDoor
var _physics_door_local := Vector3.ZERO
var _art_crystal: Node3D
var _art_console: Node3D
var _art_press: Node3D
var _task_items: Dictionary = {}
var _task_points: Dictionary = {}


func build(owner: Main3D, parent: Node3D) -> void:
	controller = owner
	name = "RuinEnergyStationInterior"
	position = Vector3(0.0, BASE_Y, 0.0)
	parent.add_child(self)
	for level: int in LEVELS:
		_build_level(level)
	_build_core()
	_build_physics_door()
	_build_art_samples()
	_build_stairs()
	set_process(true)


func spawn_position() -> Vector3:
	return global_position + Vector3(0.0, FLOOR_HEIGHT * 2.0 + 0.15, 7.4)


func exit_position() -> Vector3:
	return global_position + Vector3(0.0, FLOOR_HEIGHT * 2.0, 8.9)


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


func secret_door_position() -> Vector3:
	return global_position + Vector3(0.0, FLOOR_HEIGHT * 2.0 + 1.0, -9.1)


func pump_console_position() -> Vector3:
	return global_position + Vector3(4.2, FLOOR_HEIGHT + 1.0, -7.9)


func reactor_console_position() -> Vector3:
	return global_position + Vector3(5.2, 1.0, 4.3)


func _process(delta: float) -> void:
	_flicker_phase += delta
	for index: int in _flicker_lights.size():
		var light := _flicker_lights[index]
		if not is_instance_valid(light):
			continue
		var flicker := 0.84 + 0.16 * sin(_flicker_phase * (6.0 + float(index)) + float(index))
		if sin(_flicker_phase * 0.31 + float(index) * 1.7) > 0.94:
			flicker *= 0.22
		light.light_energy = float(light.get_meta("base_energy", 0.9)) * flicker


# ── 楼层 ─────────────────────────────────────────────────────

func _build_level(level: int) -> void:
	var y := float(level) * FLOOR_HEIGHT
	_floor_slabs(y, level)
	_ceiling_slabs(y)
	_walls(y, level)
	_core_railings(y)
	_lights(y, level)
	_furnish(level, y)


func _floor_slabs(y: float, level: int) -> void:
	_floor_piece(Vector2(4.0, HALF_W), Vector2(-HALF_D, HALF_D), y, level)
	_floor_piece(Vector2(-10.0, -4.0), Vector2(-HALF_D, HALF_D), y, level)
	_floor_piece(Vector2(-4.0, 4.0), Vector2(-HALF_D, -CORE_HALF), y, level)
	_floor_piece(Vector2(-4.0, 4.0), Vector2(CORE_HALF, HALF_D), y, level)
	_floor_piece(Vector2(-HALF_W, STAIR_X0), Vector2(-HALF_D, HALF_D), y, level)
	_floor_piece(Vector2(STAIR_X0, STAIR_X1), Vector2(-HALF_D, -STAIR_Z), y, level)
	_floor_piece(Vector2(STAIR_X0, STAIR_X1), Vector2(STAIR_Z, HALF_D), y, level)


func _floor_piece(bounds_x: Vector2, bounds_z: Vector2, y: float, level: int) -> void:
	var size := Vector3(bounds_x.y - bounds_x.x, 0.22, bounds_z.y - bounds_z.x)
	var center := Vector3((bounds_x.x + bounds_x.y) * 0.5, y - 0.11, (bounds_z.x + bounds_z.y) * 0.5)
	var slab := ART.block(self, "EnergyFloor_%d_%d" % [level, int(bounds_x.x * 10.0)], size, center, Color("#555f5b"), 0.04)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(size, center)
	# 工业格栅线。
	if bounds_x.y - bounds_x.x > 3.0 and bounds_z.y - bounds_z.x > 3.0:
		var line_x := bounds_x.x + 1.0
		while line_x < bounds_x.y:
			ART.plane(self, "FloorGrate", Vector2(0.035, bounds_z.y - bounds_z.x), Vector3(line_x, y + 0.006, (bounds_z.x + bounds_z.y) * 0.5), Color("#2f3a38")).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			line_x += 2.0


func _ceiling_slabs(y: float) -> void:
	var ceiling_y := y + FLOOR_HEIGHT
	_ceiling_piece(Vector2(4.0, HALF_W), Vector2(-HALF_D, HALF_D), ceiling_y)
	_ceiling_piece(Vector2(-10.0, -4.0), Vector2(-HALF_D, HALF_D), ceiling_y)
	_ceiling_piece(Vector2(-4.0, 4.0), Vector2(-HALF_D, -CORE_HALF), ceiling_y)
	_ceiling_piece(Vector2(-4.0, 4.0), Vector2(CORE_HALF, HALF_D), ceiling_y)
	_ceiling_piece(Vector2(-HALF_W, STAIR_X0), Vector2(-HALF_D, HALF_D), ceiling_y)
	_ceiling_piece(Vector2(STAIR_X0, STAIR_X1), Vector2(-HALF_D, -STAIR_Z), ceiling_y)
	_ceiling_piece(Vector2(STAIR_X0, STAIR_X1), Vector2(STAIR_Z, HALF_D), ceiling_y)


func _ceiling_piece(bounds_x: Vector2, bounds_z: Vector2, y: float) -> void:
	var size := Vector3(bounds_x.y - bounds_x.x, 0.14, bounds_z.y - bounds_z.x)
	var center := Vector3((bounds_x.x + bounds_x.y) * 0.5, y + 0.07, (bounds_z.x + bounds_z.y) * 0.5)
	ART.block(self, "EnergyCeiling", size, center, Color("#333d3c"), 0.04).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ── 墙与门洞 ─────────────────────────────────────────────────

func _walls(y: float, level: int) -> void:
	var h := FLOOR_HEIGHT
	# 南墙：1F 留入口，其他层封死。
	if level == 2:
		_wall(Vector3(13.7, h, 0.3), Vector3(-8.35, y + h * 0.5, HALF_D))
		_wall(Vector3(13.7, h, 0.3), Vector3(8.35, y + h * 0.5, HALF_D))
		_door_frame(Vector3(0.0, y, HALF_D), 2.6, 2.7, AMBER)
	else:
		_wall(Vector3(W, h, 0.3), Vector3(0.0, y + h * 0.5, HALF_D))
	_wall(Vector3(W, h, 0.3), Vector3(0.0, y + h * 0.5, -HALF_D))
	_wall(Vector3(0.3, h, D), Vector3(-HALF_W, y + h * 0.5, 0.0))
	_wall(Vector3(0.3, h, D), Vector3(HALF_W, y + h * 0.5, 0.0))

	# 西侧楼梯间东墙：两个平台门。
	_wall(Vector3(0.3, h, 1.8), Vector3(STAIR_X1, y + h * 0.5, -8.2))
	_wall(Vector3(0.3, h, 10.4), Vector3(STAIR_X1, y + h * 0.5, 0.0))
	_wall(Vector3(0.3, h, 1.8), Vector3(STAIR_X1, y + h * 0.5, 8.2))
	_door_frame(Vector3(STAIR_X1, y, -6.0), 1.6, 2.4, STEEL_LIGHT)
	_door_frame(Vector3(STAIR_X1, y, 6.0), 1.6, 2.4, STEEL_LIGHT)

	# 东侧机房分隔：中间留门，北侧控制/冷却，南侧汽轮机/泵。
	_wall(Vector3(4.8, h, 0.25), Vector3(6.4, y + h * 0.5, 0.0))
	_wall(Vector3(5.4, h, 0.25), Vector3(11.3, y + h * 0.5, 0.0))
	_door_frame(Vector3(9.1, y, 0.0), 1.6, 2.4, AMBER)

	# 中央核心周边的黄黑警示带，只贴地。
	for side: float in [-1.0, 1.0]:
		ART.block(self, "CoreHazard", Vector3(8.0, 0.10, 0.12), Vector3(0.0, y + 0.06, side * CORE_HALF), HAZARD, 0.01)
		ART.block(self, "CoreHazard", Vector3(0.12, 0.10, 8.0), Vector3(side * CORE_HALF, y + 0.06, 0.0), HAZARD, 0.01)


func _wall(size: Vector3, center: Vector3) -> void:
	var mesh := ART.block(self, "EnergyWall", size, center, STEEL, 0.05)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(size, center)
	ART.block(self, "WallBase", Vector3(size.x + 0.02, 0.16, size.z + 0.02), center + Vector3(0.0, -size.y * 0.5 + 0.08, 0.0), HAZARD, 0.02)


func _door_frame(at: Vector3, width: float, height: float, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DoorPost", Vector3(0.16, height, 0.38), at + Vector3(side * width * 0.5, height * 0.5, 0.0), color, 0.03)
	ART.block(self, "DoorHeader", Vector3(width + 0.36, 0.22, 0.38), at + Vector3(0.0, height, 0.0), color, 0.03)
	# 工业门不用开合，留门洞；门板做成贴墙的警示条。
	ART.block(self, "DoorHazard", Vector3(width, 0.16, 0.06), at + Vector3(0.0, 1.2, 0.22), HAZARD, 0.01)
	for index: int in 4:
		ART.block(self, "DoorHazardStripe", Vector3(0.28, 0.16, 0.02), at + Vector3(-width * 0.35 + float(index) * width * 0.23, 1.2, 0.26), AMBER, 0.01, true, 0.15)


func _core_railings(y: float) -> void:
	for side: float in [-1.0, 1.0]:
		ART.block(self, "CoreRail", Vector3(8.0, 0.10, 0.10), Vector3(0.0, y + 0.95, side * CORE_HALF), AMBER, 0.02)
		ART.block(self, "CoreRail", Vector3(0.10, 0.10, 8.0), Vector3(side * CORE_HALF, y + 0.95, 0.0), AMBER, 0.02)
		for post: int in 5:
			var offset := -4.0 + float(post) * 2.0
			ART.cylinder(self, "CoreRailPost", 0.035, 0.95, Vector3(offset, y + 0.48, side * CORE_HALF), STEEL_LIGHT)
			ART.cylinder(self, "CoreRailPost", 0.035, 0.95, Vector3(side * CORE_HALF, y + 0.48, offset), STEEL_LIGHT)


# ── 反应堆核心 ───────────────────────────────────────────────

func _build_core() -> void:
	ART.cylinder(self, "ReactorBase", 4.4, 0.55, Vector3(0.0, 0.28, 0.0), STEEL_DARK)
	ART.torus(self, "ReactorBaseRing", 3.9, 4.15, Vector3(0.0, 0.58, 0.0), AMBER, true, 0.35)
	# 反应堆外壁做成开放式笼架，让内部青绿核心可见。
	for rib: int in 8:
		var angle := TAU * float(rib) / 8.0
		ART.cylinder(self, "ReactorRib%d" % rib, 0.16, 8.8, Vector3(cos(angle) * 3.0, 4.5, sin(angle) * 3.0), STEEL_LIGHT)
	ART.cylinder(self, "ReactorGlow", 2.55, 8.4, Vector3(0.0, 4.4, 0.0), CORE_GLOW, true, 0.55)
	ART.cylinder(self, "ReactorInner", 1.7, 8.0, Vector3(0.0, 4.3, 0.0), CORE_DEEP, true, 0.30)
	ART.cylinder(self, "ReactorCap", 3.25, 0.55, Vector3(0.0, 9.05, 0.0), STEEL_DARK)
	for ring_index: int in 4:
		ART.torus(self, "CoreRing%d" % ring_index, 2.95, 3.20, Vector3(0.0, 1.2 + float(ring_index) * 2.6, 0.0), AMBER, true, 0.45)
	for pipe_index: int in 4:
		var angle := TAU * float(pipe_index) / 4.0
		var x := cos(angle) * 3.55
		var z := sin(angle) * 3.55
		ART.cylinder(self, "CorePipe%d" % pipe_index, 0.12, 8.8, Vector3(x, 4.5, z), STEEL_LIGHT)
	ART.block(self, "CoreHazardBand", Vector3(7.4, 0.18, 0.18), Vector3(0.0, 0.95, 3.8), AMBER, 0.02, true, 0.18)
	var core_light := OmniLight3D.new()
	core_light.name = "ReactorGlowLight"
	core_light.light_color = CORE_GLOW
	core_light.light_energy = 1.35
	core_light.omni_range = 13.0
	core_light.position = Vector3(0.0, 4.4, 0.0)
	core_light.shadow_enabled = false
	add_child(core_light)


# ── 物理门与美术样片 ─────────────────────────────────────────

func _build_physics_door() -> void:
	# LIS Physics 的真实铰链门：玩家按 E 推，门是 RigidBody3D + HingeJoint3D。
	physics_door = LISHingeDoor.new()
	physics_door.name = "MaintenanceHingeDoor"
	physics_door.hinge_side = -1.0
	physics_door.frame_layer = 2
	physics_door.panel_layer = 4
	physics_door.panel_mask = 1 | 2 | 4
	physics_door.push_impulse = 34.0
	physics_door.position = Vector3(9.1, FLOOR_HEIGHT * 2.0, 0.0)
	add_child(physics_door)
	physics_door.add_to_group("energy_physics_door")
	_physics_door_local = Vector3(9.1, FLOOR_HEIGHT * 2.0 + 1.0, 0.35)


func physics_door_position() -> Vector3:
	return global_position + _physics_door_local


func push_physics_door(from_world: Vector3) -> void:
	if physics_door == null:
		return
	physics_door.push_from(from_world, 34.0)


func physics_door_angle() -> float:
	return physics_door._hinge_angle() if physics_door != null else 0.0


func _build_art_samples() -> void:
	# ART-SAMPLE-002 的游戏可用 GLB；材质通过项目内 hero_lib 覆盖。
	_art_crystal = ART_SAMPLE.attach(self, "res://assets/art-sample-002/models/aqs002_bell_crystal.glb",
		Vector3(-7.0, 0.12, 0.0), Vector3(0.0, 24.0, 0.0), Vector3.ONE * 1.05)
	_art_console = ART_SAMPLE.attach(self, "res://assets/art-sample-002/models/aqs002_console.glb",
		Vector3(6.0, FLOOR_HEIGHT * 2.0, 4.2), Vector3(0.0, 0.0, 0.0), Vector3.ONE * 0.80)
	_art_press = ART_SAMPLE.attach(self, "res://assets/art-sample-002/models/aqs002_press_static.glb",
		Vector3(12.0, FLOOR_HEIGHT, -7.0), Vector3(0.0, -90.0, 0.0), Vector3.ONE * 0.44)


# ── 楼梯 ─────────────────────────────────────────────────────

func _build_stairs() -> void:
	for interval: int in LEVELS - 1:
		var lower_y := float(interval) * FLOOR_HEIGHT
		var rises_north := interval % 2 == 0
		var angle := atan(3.0 / 10.0)
		var rotation := angle if rises_north else -angle
		var center := Vector3(-12.0, lower_y + 1.5, 0.0)
		var ramp := ART.block(self, "StairRamp", Vector3(3.0, 0.18, 10.44), center, Color("#66706b"), 0.04)
		ramp.rotation_degrees.x = rad_to_deg(rotation)
		ramp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_collider(Vector3(3.0, 0.18, 10.44), center, Vector3(rad_to_deg(rotation), 0.0, 0.0))
		for step: int in 14:
			var fraction := (float(step) + 0.5) / 14.0
			var z := 5.0 - fraction * 10.0 if rises_north else -5.0 + fraction * 10.0
			var y := lower_y + fraction * 3.0 + 0.105
			ART.block(self, "StairTread", Vector3(2.9, 0.025, 0.58), Vector3(-12.0, y, z), Color("#89938c"), 0.02).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for side: float in [-1.0, 1.0]:
			var rail_center := Vector3(-12.0 + side * 1.55, lower_y + 1.5, 0.0)
			var rail := ART.block(self, "StairRail", Vector3(0.12, 1.05, 10.2), rail_center, STEEL_LIGHT, 0.03)
			rail.rotation_degrees.x = rad_to_deg(rotation)
			rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_collider(Vector3(0.12, 1.05, 10.2), rail_center, Vector3(rad_to_deg(rotation), 0.0, 0.0))


# ── 灯光 ─────────────────────────────────────────────────────

func _lights(y: float, level: int) -> void:
	var color := Color("#d1ddd6") if level >= 1 else Color("#c0d8d0")
	for point: Vector2 in [Vector2(9.0, 5.0), Vector2(9.0, -5.0), Vector2(-6.5, 5.0), Vector2(-6.5, -5.0)]:
		_light_panel(Vector3(point.x, y + 2.86, point.y), color, 1.15, 7.4)
	_light_panel(Vector3(0.0, y + 2.86, 8.4), AMBER, 1.2, 6.0)
	_light_panel(Vector3(0.0, y + 2.86, -7.2), color, 0.92, 5.8)
	# 每层一盏橙色应急灯，单独闪烁。
	var emergency := OmniLight3D.new()
	emergency.name = "EmergencyLight"
	emergency.light_color = AMBER
	emergency.light_energy = 0.65
	emergency.omni_range = 5.5
	emergency.position = Vector3(-8.5, y + 2.45, 0.0)
	emergency.shadow_enabled = false
	emergency.set_meta("base_energy", 0.65)
	add_child(emergency)
	_flicker_lights.append(emergency)


func _light_panel(at: Vector3, color: Color, energy: float, range_value: float) -> void:
	var panel := ART.block(self, "EnergyLight", Vector3(1.4, 0.06, 0.28), at, color, 0.02, true, 0.5)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.position = at + Vector3(0.0, -0.28, 0.0)
	light.shadow_enabled = false
	add_child(light)


# ── 陈设 ─────────────────────────────────────────────────────

func _furnish(level: int, y: float) -> void:
	match level:
		0:
			_crystal_growth(y)
			_emergency_bay(y)
			_reactor_console(y)
		1:
			_pump_hall(y)
			_coolant_room(y)
		2:
			_lobby(y)
			_control_room(y)
			_turbine_hall(y)
			_distribution_room(y)
		3:
			_ventilation(y)
			_observation(y)
	_debris(y, level)


func _lobby(y: float) -> void:
	# 入口气闸和去污区。
	ART.block(self, "AirlockFrame", Vector3(4.2, 2.8, 0.25), Vector3(0.0, y + 1.4, 8.3), STEEL_DARK, 0.05)
	ART.block(self, "AirlockGlow", Vector3(3.3, 0.08, 0.1), Vector3(0.0, y + 2.7, 8.15), CORE_GLOW, 0.02, true, 0.6)
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DeconPost", Vector3(0.18, 2.5, 0.18), Vector3(side * 1.8, y + 1.25, 7.3), AMBER, 0.03)
	ART.block(self, "DeconTop", Vector3(4.0, 0.18, 0.18), Vector3(0.0, y + 2.5, 7.3), STEEL_LIGHT, 0.03)
	_locker(Vector3(-3.4, y, 8.6), 0.0)
	_locker(Vector3(3.4, y, 8.6), 0.0)
	ART.plane(self, "LobbyHazard", Vector2(6.0, 0.9), Vector3(0.0, y + 0.02, 6.8), HAZARD).rotation_degrees.y = 0.0
	_chair(Vector3(-1.2, y, 6.0), 0.0)
	_chair(Vector3(1.2, y, 6.0), 0.0)


func _control_room(y: float) -> void:
	_console(Vector3(8.8, y, 6.0), 0.0)
	_console(Vector3(12.2, y, 3.4), -PI * 0.5)
	ART.block(self, "ControlBoard", Vector3(4.8, 1.4, 0.12), Vector3(9.8, y + 2.1, 7.9), STEEL_DARK, 0.03)
	for index: int in 4:
		ART.block(self, "ControlScreen", Vector3(0.85, 0.62, 0.05), Vector3(7.8 + float(index) * 1.25, y + 2.1, 7.82), Color("#4f9f92"), 0.02, true, 0.35)
	_chair(Vector3(8.8, y, 4.9), PI)
	_chair(Vector3(12.2, y, 5.1), -PI * 0.5)


func _turbine_hall(y: float) -> void:
	# 汽轮机：横置大圆柱 + 发电机 + 管线。
	var turbine := ART.cylinder(self, "TurbineBody", 1.35, 5.2, Vector3(10.0, y + 1.35, -5.0), STEEL_LIGHT)
	turbine.rotation_degrees.x = 90.0
	ART.block(self, "TurbineBase", Vector3(3.4, 0.42, 5.6), Vector3(10.0, y + 0.21, -5.0), STEEL_DARK, 0.05)
	ART.cylinder(self, "Generator", 1.1, 2.6, Vector3(10.0, y + 1.15, -2.6), Color("#596964"))
	ART.block(self, "TurbineHazard", Vector3(3.4, 0.18, 0.12), Vector3(10.0, y + 0.6, -8.1), AMBER, 0.02, true, 0.2)
	for index: int in 3:
		ART.cylinder(self, "TurbinePipe", 0.10, 6.0, Vector3(6.4, y + 2.4 + float(index) * 0.18, -5.0), STEEL_LIGHT)
	ART.block(self, "TurbineGauge", Vector3(0.8, 0.8, 0.12), Vector3(12.8, y + 2.0, -8.5), STEEL_DARK, 0.02)
	ART.torus(self, "TurbineGaugeRing", 0.24, 0.32, Vector3(12.8, y + 2.0, -8.43), AMBER, true, 0.4)
	_collider(Vector3(3.4, 2.0, 5.6), Vector3(10.0, y + 1.0, -5.0))


func _distribution_room(y: float) -> void:
	# 伪装成配电柜的暗门；靠近按 E 进入地下庇护所。
	ART.block(self, "DisguisedDistributionDoor", Vector3(2.6, 2.6, 0.17), Vector3(0.0, y + 1.3, -9.75), Color("#414e4d"), 0.04)
	for stripe: int in 7:
		ART.block(self, "DistributionHazard", Vector3(0.25, 0.75, 0.02), Vector3(-1.0 + float(stripe) * 0.34, y + 0.55, -9.64), AMBER, 0.01, true, 0.12).rotation_degrees.z = 28.0
	ART.block(self, "DistributionHandle", Vector3(0.16, 0.06, 0.08), Vector3(0.9, y + 1.15, -9.62), STEEL_LIGHT, 0.02)
	ART.block(self, "DistributionLabel", Vector3(0.6, 0.18, 0.03), Vector3(-0.8, y + 2.1, -9.64), Color("#9a7d4a"), 0.01)
	for index: int in 3:
		ART.block(self, "DistributionCabinet", Vector3(1.1, 1.8, 0.55), Vector3(10.8 + float(index) * 1.2, y + 0.9, -9.2), STEEL_DARK, 0.04)
		ART.block(self, "CabinetGauge", Vector3(0.16, 0.16, 0.03), Vector3(10.8 + float(index) * 1.2, y + 1.2, -8.90), AMBER, 0.01, true, 0.3)


func _pump_hall(y: float) -> void:
	for index: int in 3:
		_pump(Vector3(7.5 + float(index) * 2.4, y, -5.5), float(index) * 0.7)
	ART.block(self, "PumpManifold", Vector3(7.4, 0.35, 0.35), Vector3(9.5, y + 1.5, -8.6), STEEL_LIGHT, 0.03)
	for index: int in 5:
		ART.cylinder(self, "ManifoldPipe", 0.09, 2.8, Vector3(6.5 + float(index) * 1.5, y + 1.5, -8.6), STEEL_LIGHT)
	ART.block(self, "PumpGaugeWall", Vector3(3.2, 1.2, 0.12), Vector3(11.5, y + 1.7, -9.6), STEEL_DARK, 0.03)
	for index: int in 3:
		ART.torus(self, "PumpGauge", 0.20, 0.27, Vector3(10.5 + float(index) * 0.8, y + 1.7, -9.5), AMBER, true, 0.45)
	_collider(Vector3(7.2, 1.2, 1.2), Vector3(9.8, y + 0.6, -5.5))
	# B1 菌群泵控制台：医生方案里手动关闭菌群泵的地方。
	ART.block(self, "ColonyPumpConsole", Vector3(2.2, 1.1, 0.8), Vector3(4.2, y + 0.55, -7.9), STEEL_DARK, 0.04)
	ART.block(self, "ColonyPumpScreen", Vector3(1.4, 0.55, 0.07), Vector3(4.2, y + 1.0, -8.34), Color("#8e4a3a"), 0.02, true, 0.4)
	for index: int in 3:
		ART.torus(self, "ColonyPumpGauge", 0.16, 0.22, Vector3(3.5 + float(index) * 0.7, y + 1.0, -8.36), AMBER, true, 0.35)
	_collider(Vector3(2.2, 1.1, 0.8), Vector3(4.2, y + 0.55, -7.9))


func _coolant_room(y: float) -> void:
	for index: int in 3:
		_tank(Vector3(9.0 + float(index) * 2.0, y, 5.0), 0.95 + float(index) * 0.1)
		ART.cylinder(self, "CoolantPipe", 0.10, 3.0, Vector3(8.2 + float(index) * 2.0, y + 1.8, 2.8), TEAL)
	ART.block(self, "CoolantConsole", Vector3(2.4, 1.0, 0.65), Vector3(12.4, y + 0.7, 7.8), STEEL_DARK, 0.04)
	ART.block(self, "CoolantScreen", Vector3(1.2, 0.45, 0.05), Vector3(12.4, y + 1.05, 7.45), CORE_GLOW, 0.02, true, 0.45)


func _crystal_growth(y: float) -> void:
	# 星髓结晶：被钻探击穿的菌群代谢物，不是普通矿石。
	for index: int in 7:
		var angle := TAU * float(index) / 7.0
		var radius := 5.5 + float(index % 3) * 1.2
		var point := Vector3(cos(angle) * radius, y, sin(angle) * radius)
		var height := 1.2 + float(index % 4) * 0.55
		var crystal := ART.cone(self, "StarMarrowCrystal%d" % index, 0.05, 0.42 + float(index % 2) * 0.18, height, point + Vector3(0.0, height * 0.5, 0.0), CORE_GLOW)
		crystal.rotation_degrees.y = float(index) * 37.0
		crystal.rotation_degrees.z = -8.0 + float(index % 3) * 8.0
	ART.cylinder(self, "MarrowPool", 2.8, 0.03, Vector3(0.0, y + 0.02, 0.0), Color("#266d64"), true, 0.35)
	ART.block(self, "CrystalWarning", Vector3(4.4, 0.16, 0.12), Vector3(0.0, y + 0.1, 5.4), AMBER, 0.02, true, 0.2)


func _emergency_bay(y: float) -> void:
	# 反应堆点火核心的应急弹射舱；核心登记为剧情任务物。	ART.block(self, "EmergencyBayFloor", Vector3(6.0, 0.1, 5.0), Vector3(10.5, y + 0.06, 4.6), Color("#4e5854"), 0.02)
	ART.cylinder(self, "EjectionCapsule", 1.1, 2.4, Vector3(10.5, y + 1.25, 4.6), Color("#7b6c52"))
	ART.cone(self, "EjectionNose", 0.1, 1.1, 1.0, Vector3(10.5, y + 2.95, 4.6), AMBER)
	ART.torus(self, "CapsuleClamp", 1.15, 1.3, Vector3(10.5, y + 0.75, 4.6), AMBER, true, 0.4)
	ART.block(self, "EjectionConsole", Vector3(2.2, 1.1, 0.7), Vector3(7.0, y + 0.7, 4.6), STEEL_DARK, 0.04)
	ART.block(self, "EjectionScreen", Vector3(0.9, 0.4, 0.05), Vector3(7.0, y + 1.05, 4.25), AMBER, 0.02, true, 0.45)
	_collider(Vector3(2.4, 2.8, 2.4), Vector3(10.5, y + 1.4, 4.6))
	var core := _register_task_item("reactor_core", Vector3(7.0, y + 1.05, 5.25), AMBER)
	ART.cylinder(core, "CoreCasing", 0.24, 0.52, Vector3(0.0, 0.10, 0.0), Color("#6c6253"), 0.02)
	ART.cylinder(core, "CoreCell", 0.16, 0.38, Vector3(0.0, 0.14, 0.0), Color("#ffd184"), true, 0.6)
	ART.torus(core, "CoreBand", 0.24, 0.30, Vector3(0.0, 0.10, 0.0), AMBER, true, 0.35)
	ART.block(core, "CoreHandle", Vector3(0.10, 0.06, 0.34), Vector3(0.0, 0.36, 0.0), STEEL_LIGHT, 0.02)


func _reactor_console(y: float) -> void:
	ART.block(self, "ReactorRestartConsole", Vector3(2.4, 1.1, 0.8), Vector3(5.2, y + 0.55, 4.3), STEEL_DARK, 0.04)
	ART.block(self, "ReactorRestartPanel", Vector3(1.6, 0.55, 0.08), Vector3(5.2, y + 1.0, 3.84), CORE_GLOW, 0.02, true, 0.35)
	for index: int in 3:
		ART.block(self, "ReactorRestartButton", Vector3(0.18, 0.10, 0.05), Vector3(4.7 + float(index) * 0.5, y + 0.82, 3.78), AMBER if index == 2 else STEEL_LIGHT, 0.01, index == 2, 0.3)
	_collider(Vector3(2.4, 1.1, 0.8), Vector3(5.2, y + 0.55, 4.3))


func _ventilation(y: float) -> void:
	# 2F 通风：大风扇和风管。
	_fan(Vector3(10.5, y + 1.8, 5.0), 1.9)
	for index: int in 3:
		ART.block(self, "Duct", Vector3(5.5, 0.7, 0.7), Vector3(9.0, y + 2.4, -2.0 + float(index) * 1.0), STEEL_LIGHT, 0.04)
	ART.block(self, "VentConsole", Vector3(2.2, 1.0, 0.7), Vector3(12.2, y + 0.65, 7.8), STEEL_DARK, 0.04)
	ART.block(self, "VentScreen", Vector3(1.0, 0.4, 0.05), Vector3(12.2, y + 1.0, 7.45), CORE_GLOW, 0.02, true, 0.3)


func _observation(y: float) -> void:
	# 2F 北侧观测台，面向反应堆。
	for index: int in 3:
		_console(Vector3(-2.4 + float(index) * 2.4, y, -6.4), PI)
	ART.block(self, "ObservationGlass", Vector3(7.0, 1.8, 0.08), Vector3(0.0, y + 1.6, -8.0), Color("#6f9a96"), 0.02, true, 0.08)
	for index: int in 4:
		ART.block(self, "ObservationFrame", Vector3(0.10, 1.9, 0.12), Vector3(-3.5 + float(index) * 2.33, y + 1.6, -7.92), STEEL_LIGHT, 0.02)


# ── 小部件 ───────────────────────────────────────────────────

func _console(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "EnergyConsole"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Desk", Vector3(2.2, 0.82, 0.8), Vector3(0.0, 0.41, 0.0), STEEL_DARK, 0.04)
	ART.block(root, "Panel", Vector3(1.8, 0.12, 0.5), Vector3(0.0, 0.9, 0.0), STEEL_LIGHT, 0.03).rotation_degrees.x = -12.0
	for index: int in 2:
		ART.block(root, "Screen", Vector3(0.65, 0.42, 0.05), Vector3(-0.42 + float(index) * 0.84, 1.09, 0.05), Color("#4b9b8e"), 0.02, true, 0.5)
	_collider(Vector3(2.2, 0.95, 0.8), at + Vector3(0.0, 0.48, 0.0), Vector3(0.0, yaw_degrees, 0.0))


func _chair(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "ControlChair"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Seat", Vector3(0.55, 0.10, 0.52), Vector3(0.0, 0.46, 0.0), Color("#3d5352"), 0.03)
	ART.block(root, "Back", Vector3(0.55, 0.58, 0.10), Vector3(0.0, 0.75, 0.25), Color("#3d5352"), 0.03)
	for side: float in [-1.0, 1.0]:
		ART.cylinder(root, "Leg", 0.025, 0.45, Vector3(side * 0.22, 0.22, 0.18), STEEL_LIGHT)


func _locker(at: Vector3, yaw_degrees: float) -> void:
	ART.block(self, "Locker", Vector3(0.9, 2.0, 0.55), at + Vector3(0.0, 1.0, 0.0), Color("#3f5654"), 0.04)
	for index: int in 3:
		ART.block(self, "LockerDoor", Vector3(0.72, 0.52, 0.04), at + Vector3(0.0, 0.45 + float(index) * 0.58, 0.29), Color("#526e69"), 0.02)
		ART.block(self, "LockerVent", Vector3(0.42, 0.04, 0.02), at + Vector3(0.0, 0.68 + float(index) * 0.58, 0.32), HAZARD, 0.01)


func _pump(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "CoolantPump"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Base", Vector3(1.5, 0.22, 1.3), Vector3(0.0, 0.11, 0.0), STEEL_DARK, 0.03)
	ART.cylinder(root, "Motor", 0.48, 1.0, Vector3(0.0, 0.7, 0.0), STEEL_LIGHT)
	ART.cylinder(root, "PumpHead", 0.38, 0.55, Vector3(0.0, 1.3, 0.0), Color("#5b8b83"))
	ART.torus(root, "PumpFlange", 0.50, 0.60, Vector3(0.0, 1.48, 0.0), AMBER, true, 0.3)
	ART.cylinder(root, "PipeOut", 0.10, 1.6, Vector3(0.0, 1.35, -1.1), STEEL_LIGHT).rotation_degrees.x = 90.0


func _tank(at: Vector3, radius: float) -> void:
	ART.cylinder(self, "CoolantTank", radius, 2.5, at + Vector3(0.0, 1.25, 0.0), Color("#5d7773"))
	ART.cylinder(self, "CoolantTankBand", radius + 0.03, 0.15, at + Vector3(0.0, 0.8, 0.0), AMBER)
	ART.cylinder(self, "CoolantTankBand", radius + 0.03, 0.10, at + Vector3(0.0, 1.9, 0.0), HAZARD)
	for index: int in 3:
		ART.cylinder(self, "TankPipe", 0.08, 1.2, at + Vector3(-0.36 + float(index) * 0.36, 2.8, 0.0), STEEL_LIGHT)


func _fan(at: Vector3, radius: float) -> void:
	ART.torus(self, "FanHousing", radius, radius + 0.25, at, STEEL_LIGHT, true, 0.15)
	ART.cylinder(self, "FanHub", 0.22, 0.3, at, STEEL_DARK).rotation_degrees.x = 90.0
	for index: int in 5:
		var blade := ART.block(self, "FanBlade", Vector3(1.3, 0.08, 0.34), at + Vector3(0.0, 0.0, 0.0), STEEL_LIGHT, 0.02)
		blade.rotation_degrees.z = float(index) * 72.0
		blade.position += Vector3(0.0, 0.0, 0.0)


func _crystal(at: Vector3, height: float) -> void:
	var crystal := ART.cone(self, "StarMarrowShard", 0.04, 0.35, height, at + Vector3(0.0, height * 0.5, 0.0), CORE_GLOW)
	crystal.rotation_degrees = Vector3(0.0, float(int(at.x * 7.0) % 360), -10.0)


func _debris(y: float, level: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 901 + level * 71
	for index: int in 7:
		var x := rng.randf_range(-7.0, 12.0)
		var z := rng.randf_range(-8.5, 8.5)
		if absf(x) < 4.5 and absf(z) < 4.5:
			continue
		ART.block(self, "EnergyDebris", Vector3(rng.randf_range(0.12, 0.3), 0.04, rng.randf_range(0.15, 0.3)), Vector3(x, y + 0.03, z), Color("#8a816e"), 0.01).rotation_degrees.y = rng.randf_range(0.0, 180.0)
	ART.plane(self, "OilStain", Vector2(1.4, 0.8), Vector3(7.0, y + 0.02, -2.0), Color("#242b2b")).rotation_degrees.y = 20.0
	ART.plane(self, "BloodStain", Vector2(0.8, 0.5), Vector3(-3.0, y + 0.02, 3.0), BLOOD, true, 0.03).rotation_degrees.y = 40.0


func _register_task_item(item_id: String, point: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "EnergyTask_" + item_id
	root.position = point
	add_child(root)
	_task_items[item_id] = root
	_task_points[item_id] = point
	ART.sphere(root, "TaskGlow", Vector3(0.10, 0.10, 0.10), Vector3(0.0, 0.28, 0.0), color, true, 0.55)
	return root


func _collider(size: Vector3, center: Vector3, rotation_degrees_value := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.name = "EnergyCollision"
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
