extends Node3D

## 腐墟星能源站内部：4 层工业设施。
##
## 2F 通风/观测，1F 大厅/控制室/汽轮机，B1 泵房/冷却剂，B2 反应堆核心/应急舱。
## 与医院一样，室内放在同一世界的高处，通过大门传送进出。
## 视觉母题：深灰钢构、黄黑警示条、青绿星髓光、橙色应急灯、粗管线和格栅。

const ART := preload("res://scripts/ruin_cartoon_art.gd")
const STAIR_TEMPLATE := preload("res://scripts/ruin_stair_template.gd")
const ART_SAMPLE := preload("res://scripts/ruin_art_sample.gd")

const LEVELS := 4
const FLOOR_HEIGHT := 3.0
const BASE_Y := 320.0
const W := 30.0
const D := 20.0
const HALF_W := 15.0
const HALF_D := 10.0
const CORE_HALF := 4.0
const STAIR_X0 := -15.0
const STAIR_X1 := -10.0
const STAIR_Z := 6.0

const STEEL := Color("#394952")
const STEEL_LIGHT := Color("#84959b")
const STEEL_DARK := Color("#232d33")
const CONCRETE := Color("#5b6264")
const CONCRETE_LIGHT := Color("#7d8587")
const RUST := Color("#7c4a38")
const AMBER := Color("#c58a3e")
const AMBER_LIGHT := Color("#e8b868")
const TEAL := Color("#2f6f73")
const CORE_GLOW := Color("#57d8d0")
const CORE_DEEP := Color("#1e6b66")
const HAZARD := Color("#1b2425")
const BLOOD := Color("#6f302c")
const CABLE := Color("#202b2e")
const RED := Color("#a8453a")
const CREAM_TRIM := Color("#c9c0aa")

const LEVEL_NAMES := ["B2 反应堆核心", "B1 泵房与冷却", "1F 大厅与控制", "2F 通风与观测"]

var controller: Main3D
var _flicker_lights: Array[OmniLight3D] = []
var _floor_y := 0.0
var _flicker_phase := 0.0
var _pump_wheel: Node3D
var _reactor_wheel: Node3D
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
	_floor_y = y
	_floor_slabs(y, level)
	_ceiling_slabs(y)
	_walls(y, level)
	_core_railings(y)
	_lights(y, level)
	_furnish(level, y)
	if level == 2:
		_build_entrance_door(y)
	_stairwell_soffit(y)


func _floor_slabs(y: float, level: int) -> void:
	_floor_piece(Vector2(4.0, HALF_W), Vector2(-HALF_D, HALF_D), y, level)
	_floor_piece(Vector2(-10.0, -4.0), Vector2(-HALF_D, HALF_D), y, level)
	_floor_piece(Vector2(-4.0, 4.0), Vector2(-HALF_D, -CORE_HALF), y, level)
	_floor_piece(Vector2(-4.0, 4.0), Vector2(CORE_HALF, HALF_D), y, level)
	_floor_piece(Vector2(-HALF_W, STAIR_X0), Vector2(-HALF_D, HALF_D), y, level)
	_floor_piece(Vector2(STAIR_X0, STAIR_X1), Vector2(-HALF_D, -STAIR_Z), y, level)
	_floor_piece(Vector2(STAIR_X0, STAIR_X1), Vector2(STAIR_Z, HALF_D), y, level)


func _floor_piece(bounds_x: Vector2, bounds_z: Vector2, y: float, level: int) -> void:
	if bounds_x.y - bounds_x.x < 0.01 or bounds_z.y - bounds_z.x < 0.01:
		return
	var size := Vector3(bounds_x.y - bounds_x.x, 0.22, bounds_z.y - bounds_z.x)
	var center := Vector3((bounds_x.x + bounds_x.y) * 0.5, y - 0.11, (bounds_z.x + bounds_z.y) * 0.5)
	var slab := ART.block(self, "EnergyFloor_%d_%d" % [level, int(bounds_x.x * 10.0)], size, center, Color("#555f5b"), 0.04)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_texture = load("res://assets/ruin/textures/floor_metal.png") as Texture2D
	floor_mat.albedo_color = Color.WHITE
	floor_mat.roughness = 0.82
	floor_mat.metallic = 0.25
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_world_triplanar = true
	floor_mat.uv1_scale = Vector3.ONE / 2.8
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slab.material_override = floor_mat
	var floor_overlay := MeshInstance3D.new()
	floor_overlay.name = "EnergyFloorTexture_%d_%d_%d" % [int(y * 10.0), int(bounds_x.x * 10.0), int(bounds_z.x * 10.0)]
	var overlay_mesh := BoxMesh.new()
	overlay_mesh.size = Vector3(size.x, 0.012, size.z)
	floor_overlay.mesh = overlay_mesh
	var overlay_mat := StandardMaterial3D.new()
	overlay_mat.albedo_texture = floor_mat.albedo_texture
	overlay_mat.albedo_color = Color.WHITE
	overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	overlay_mat.uv1_scale = Vector3(maxf(size.x / 2.8, 1.0), maxf(size.z / 2.8, 1.0), 1.0)
	floor_overlay.material_override = overlay_mat
	floor_overlay.position = Vector3(center.x, y + 0.012, center.z)
	floor_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_overlay)
	var step := 2.0
	var gx := bounds_x.x + step
	while gx < bounds_x.y:
		ART.block(self, "FloorPlateSeam_X_%d_%d" % [int(gx * 10.0), int(y * 10.0)], Vector3(0.09, 0.012, size.z), Vector3(gx, y + 0.042, center.z), STEEL_DARK, 0.0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gx += step
	var gz := bounds_z.x + step
	while gz < bounds_z.y:
		ART.block(self, "FloorPlateSeam_Z_%d_%d" % [int(gz * 10.0), int(y * 10.0)], Vector3(size.x, 0.012, 0.09), Vector3(center.x, y + 0.042, gz), STEEL_DARK, 0.0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gz += step
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
	if bounds_x.y - bounds_x.x < 0.01 or bounds_z.y - bounds_z.x < 0.01:
		return
	var size := Vector3(bounds_x.y - bounds_x.x, 0.14, bounds_z.y - bounds_z.x)
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_texture = load("res://assets/ruin/textures/ceiling_metal.png") as Texture2D
	skin_mat.albedo_color = Color.WHITE
	skin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	skin_mat.uv1_scale = Vector3(maxf(size.x / 2.0, 1.0), maxf(size.z / 2.0, 1.0), 1.0)
	var skin := MeshInstance3D.new()
	skin.name = "EnergyCeiling"
	var skin_mesh := BoxMesh.new()
	skin_mesh.size = Vector3(size.x, 0.05, size.z)
	skin.mesh = skin_mesh
	skin.material_override = skin_mat
	skin.position = Vector3((bounds_x.x + bounds_x.y) * 0.5, y - 0.28, (bounds_z.x + bounds_z.y) * 0.5)
	skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skin)

	var center := Vector3((bounds_x.x + bounds_x.y) * 0.5, y - 0.32, (bounds_z.x + bounds_z.y) * 0.5)
	ART.block(self, "CeilingSoffit", Vector3(size.x + 0.32, 0.18, 0.16), Vector3(center.x, y - 0.32, bounds_z.x - 0.08), STEEL_DARK, 0.02)
	ART.block(self, "CeilingSoffit", Vector3(size.x + 0.32, 0.18, 0.16), Vector3(center.x, y - 0.32, bounds_z.y + 0.08), STEEL_DARK, 0.02)
	ART.block(self, "CeilingSoffit", Vector3(0.16, 0.18, size.z), Vector3(bounds_x.x - 0.08, y - 0.32, center.z), STEEL_DARK, 0.02)
	ART.block(self, "CeilingSoffit", Vector3(0.16, 0.18, size.z), Vector3(bounds_x.y + 0.08, y - 0.32, center.z), STEEL_DARK, 0.02)


# ── 墙与门洞 ─────────────────────────────────────────────────

func _walls(y: float, level: int) -> void:
	var h := FLOOR_HEIGHT
	# 南墙：1F 留入口，其他层封死。
	if level == 2:
		# 门洞净宽 2.6 m；墙段从门框外缘 x=±1.3 开始，不能留下 0.2 m 竖缝。
		_wall(Vector3(13.7, h, 0.3), Vector3(-8.15, y + h * 0.5, HALF_D))
		_wall(Vector3(13.7, h, 0.3), Vector3(8.15, y + h * 0.5, HALF_D))
		_door_frame(Vector3(0.0, y, HALF_D), 2.6, 2.7, AMBER)
		# 门框封边：即使墙段/门框视觉有偏差，玩家也不能从门边挤出去。
		for side: float in [-1.0, 1.0]:
			_collider(Vector3(0.30, h, 0.44), Vector3(side * 1.36, y + h * 0.5, HALF_D))
	else:
		_wall(Vector3(W, h, 0.3), Vector3(0.0, y + h * 0.5, HALF_D))
	_wall(Vector3(W, h, 0.3), Vector3(0.0, y + h * 0.5, -HALF_D))
	_wall(Vector3(0.3, h, D), Vector3(-HALF_W, y + h * 0.5, 0.0))
	_wall(Vector3(0.3, h, D), Vector3(HALF_W, y + h * 0.5, 0.0))

	# 西侧楼梯间东墙：两个平台门。
	# 每层只在梯段抵达侧留一个入口：0/2 层南 +6，1/3 层北 -6。
	var stair_entry := 6.0 if level % 2 == 0 else -6.0
	if stair_entry > 0.0:
		_wall(Vector3(0.3, h, 14.8), Vector3(STAIR_X1, y + h * 0.5, -2.6))
		_wall(Vector3(0.3, h, 2.8), Vector3(STAIR_X1, y + h * 0.5, 8.6))
	else:
		_wall(Vector3(0.3, h, 2.8), Vector3(STAIR_X1, y + h * 0.5, -8.6))
		_wall(Vector3(0.3, h, 14.8), Vector3(STAIR_X1, y + h * 0.5, 2.6))
	STAIR_TEMPLATE.build_door_frame(self, Vector3(STAIR_X1, y, stair_entry), 2.4, 2.4, STEEL_LIGHT)

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
	ART.block(self, "WallCap", Vector3(size.x + 0.02, 0.06, size.z + 0.02), center + Vector3(0.0, size.y * 0.5 - 0.03, 0.0), STEEL_LIGHT, 0.012)
	ART.block(self, "WallBase", Vector3(size.x + 0.02, 0.16, size.z + 0.02), center + Vector3(0.0, -size.y * 0.5 + 0.08, 0.0), HAZARD, 0.02)


func _door_frame(at: Vector3, width: float, height: float, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DoorPost", Vector3(0.16, height, 0.38), at + Vector3(side * width * 0.5, height * 0.5, 0.0), color, 0.03)
	ART.block(self, "DoorHeader", Vector3(width + 0.36, 0.22, 0.38), at + Vector3(0.0, height, 0.0), color, 0.03)
	# 工业门不用开合，留门洞；门板做成贴墙的警示条。
	ART.block(self, "DoorHazard", Vector3(width, 0.16, 0.06), at + Vector3(0.0, 1.2, 0.22), HAZARD, 0.01)
	for index: int in 4:
		ART.block(self, "DoorHazardStripe", Vector3(0.28, 0.16, 0.02), at + Vector3(-width * 0.35 + float(index) * width * 0.23, 1.2, 0.26), AMBER, 0.01, true, 0.15)


## 沿 X 方向墙面的门框（门洞沿 Z 展开），用于西侧楼梯间。
func _door_frame_z(at: Vector3, width: float, height: float, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DoorPost", Vector3(0.38, height, 0.16), at + Vector3(0.0, height * 0.5, side * width * 0.5), color, 0.03)
	ART.block(self, "DoorHeader", Vector3(0.38, 0.22, width + 0.36), at + Vector3(0.0, height, 0.0), color, 0.03)
	ART.block(self, "DoorHazard", Vector3(0.06, 0.16, width), at + Vector3(0.22, 1.2, 0.0), HAZARD, 0.01)


func _core_railings(y: float) -> void:
	for side: float in [-1.0, 1.0]:
		ART.block(self, "CoreRail", Vector3(8.0, 0.10, 0.10), Vector3(0.0, y + 0.95, side * CORE_HALF), AMBER, 0.02)
		ART.block(self, "CoreRail", Vector3(0.10, 0.10, 8.0), Vector3(side * CORE_HALF, y + 0.95, 0.0), AMBER, 0.02)
		for post: int in 5:
			var offset := -4.0 + float(post) * 2.0
			ART.cylinder(self, "CoreRailPost", 0.035, 0.95, Vector3(offset, y + 0.48, side * CORE_HALF), STEEL_LIGHT)
			ART.cylinder(self, "CoreRailPost", 0.035, 0.95, Vector3(side * CORE_HALF, y + 0.48, offset), STEEL_LIGHT)
		# 视觉栏杆只有 0.95 m，而且没有碰撞；补 1.6 m 高的隐形护栏，
		# 防止玩家走进核心井或跳过栏杆掉到下层。
		_collider(Vector3(8.0, 1.6, 0.14), Vector3(0.0, y + 0.8, side * CORE_HALF))
		_collider(Vector3(0.14, 1.6, 8.0), Vector3(side * CORE_HALF, y + 0.8, 0.0))


# ── 反应堆核心 ───────────────────────────────────────────────

func _build_core() -> void:
	ART.cylinder(self, "ReactorBase", 4.4, 0.55, Vector3(0.0, 0.28, 0.0), STEEL_DARK)
	ART.torus(self, "ReactorBaseRing", 3.9, 4.15, Vector3(0.0, 0.58, 0.0), AMBER, true, 0.35)
	# 反应堆外壁做成开放式笼架，让内部青绿核心可见。
	for rib: int in 8:
		var angle := TAU * float(rib) / 8.0
		ART.cylinder(self, "ReactorRib%d" % rib, 0.16, 8.8, Vector3(cos(angle) * 3.0, 4.5, sin(angle) * 3.0), STEEL_LIGHT)
	ART.cylinder(self, "ReactorGlow", 2.55, 8.4, Vector3(0.0, 4.4, 0.0), CORE_GLOW, true, 0.12)
	ART.cylinder(self, "ReactorInner", 1.7, 8.0, Vector3(0.0, 4.3, 0.0), CORE_DEEP, true, 0.06)
	ART.cylinder(self, "ReactorCap", 3.25, 0.55, Vector3(0.0, 9.05, 0.0), STEEL_DARK)
	for ring_index: int in 4:
		ART.torus(self, "CoreRing%d" % ring_index, 2.95, 3.20, Vector3(0.0, 1.2 + float(ring_index) * 2.6, 0.0), AMBER, true, 0.45)
	ART.block(self, "CoreHazardBand", Vector3(7.4, 0.18, 0.18), Vector3(0.0, 0.95, 3.8), AMBER, 0.02, true, 0.18)
	var core_light := OmniLight3D.new()
	core_light.name = "ReactorGlowLight"
	core_light.light_color = CORE_GLOW
	core_light.light_energy = 0.60
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

## 1F 入口气闸门：关着、有碰撞。气闸拱是开放的，门在 9.7 m 处；
## 回头能看到门，门洞不再通向虚空。
func _build_entrance_door(y: float) -> void:
	var door_z := HALF_D - 0.12
	var door_w := 2.6
	for side: float in [-1.0, 1.0]:
		ART.block(self, "InteriorEntranceDoorLeaf", Vector3(door_w * 0.5 - 0.04, 2.62, 0.12), Vector3(side * door_w * 0.25, y + 1.31, door_z), STEEL_LIGHT, 0.03)
		ART.block(self, "InteriorEntranceDoorWindow", Vector3(door_w * 0.30, 0.48, 0.04), Vector3(side * door_w * 0.25, y + 1.95, door_z - 0.08), Color("#4f7f7c"), 0.01, true, 0.10)
		ART.block(self, "InteriorEntranceDoorHandle", Vector3(0.08, 0.30, 0.08), Vector3(side * 0.10, y + 1.16, door_z - 0.12), AMBER, 0.01, true, 0.18)
		ART.block(self, "InteriorEntranceDoorStripe", Vector3(door_w * 0.42, 0.10, 0.03), Vector3(side * door_w * 0.25, y + 1.72, door_z - 0.08), HAZARD, 0.01)
	var body := StaticBody3D.new()
	body.name = "InteriorEntranceDoorCollision"
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = Vector3(0.0, y + 1.35, door_z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(door_w, 2.7, 0.16)
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _stairwell_soffit(y: float) -> void:
	var edge_y := y + FLOOR_HEIGHT - 0.06
	ART.block(self, "StairSoffit", Vector3(4.2, 0.20, 0.16), Vector3(-12.0, edge_y, -STAIR_Z), STEEL_LIGHT, 0.02)
	ART.block(self, "StairSoffit", Vector3(4.2, 0.20, 0.16), Vector3(-12.0, edge_y, STAIR_Z), STEEL_LIGHT, 0.02)
	ART.block(self, "StairSoffit", Vector3(0.16, 0.20, 12.2), Vector3(-14.0, edge_y, 0.0), STEEL_LIGHT, 0.02)
	ART.block(self, "StairSoffit", Vector3(0.16, 0.20, 12.2), Vector3(-10.0, edge_y, 0.0), STEEL_LIGHT, 0.02)


func _build_stairs() -> void:
	STAIR_TEMPLATE.build(self, {
		"levels": LEVELS,
		"floor_height": FLOOR_HEIGHT,
		"x0": STAIR_X0,
		"x1": STAIR_X1,
		"stair_z": STAIR_Z,
		"tread_color": Color("#aeb6b3"),
		"fill_color": Color("#778487"),
		"rail_color": Color("#6b7a78"),
	})


func _lights(y: float, level: int) -> void:
	var color := Color("#d1ddd6") if level >= 1 else Color("#c0d8d0")
	for point: Vector2 in [Vector2(9.0, 5.0), Vector2(9.0, -5.0), Vector2(-6.5, 5.0), Vector2(-6.5, -5.0)]:
		_light_panel(Vector3(point.x, y + 2.86, point.y), color, 1.15, 7.4)
	ART.block(self, "FarWallCove", Vector3(23.0, 0.05, 0.05), Vector3(0.0, y + 2.82, -9.84), Color("#d8c9a8"), 0.01, true, 0.35)
	for side: float in [-1.0, 1.0]:
		ART.block(self, "FarWallLightHousing", Vector3(1.2, 0.18, 0.10), Vector3(side * 5.0, y + 1.88, -9.86), STEEL_DARK, 0.02)
		ART.block(self, "FarWallLightTube", Vector3(1.0, 0.05, 0.04), Vector3(side * 5.0, y + 1.88, -9.79), Color("#d8e4e2"), 0.01, true, 0.45)
		var wall_light := OmniLight3D.new()
		wall_light.light_color = Color("#d8e4e2")
		wall_light.light_energy = 0.55
		wall_light.omni_range = 4.5
		wall_light.position = Vector3(side * 5.0, y + 1.8, -9.4)
		wall_light.shadow_enabled = false
		add_child(wall_light)
	_light_panel(Vector3(0.0, y + 2.86, 8.4), AMBER, 1.2, 6.0)
	_light_panel(Vector3(0.0, y + 2.86, -7.2), color, 0.92, 5.8)
	if level == 2:
		# 控制室原来靠一排屏幕自发光，南墙和东墙发黑；补两盏洗墙灯。
		_light_panel(Vector3(9.8, y + 2.86, 6.8), Color("#d8e4e2"), 1.8, 8.0)
		_light_panel(Vector3(13.6, y + 2.86, 4.2), CORE_GLOW, 0.65, 5.2)
	# 楼梯间补光：壁灯固定在楼梯间东墙，不悬在井口上方。
	_wall_light(Vector3(-10.12, y + 1.92, 6.2), Color("#c6e5df"), 0.82, 5.2)
	_wall_light(Vector3(-10.12, y + 1.92, -6.2), Color("#c6e5df"), 0.82, 5.2)
	_wall_light(Vector3(-10.12, y + 1.92, 0.0), Color("#d7e5e1"), 0.62, 4.6)
	_stair_floor_sign(level, y)
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
	var fixed_at := Vector3(at.x, minf(at.y, _floor_y + 2.60), at.z)
	ART.block(self, "EnergyLightMount", Vector3(1.62, 0.18, 0.44), fixed_at + Vector3(0.0, 0.08, 0.0), STEEL_LIGHT, 0.02)
	var panel := ART.block(self, "EnergyLight", Vector3(1.4, 0.06, 0.28), fixed_at, color, 0.02, true, 0.5)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.position = fixed_at + Vector3(0.0, -0.20, 0.0)
	light.shadow_enabled = false
	light.set_meta("fixture", "ceiling")
	add_child(light)


func _wall_light(at: Vector3, color: Color, energy: float, range_value: float) -> void:
	ART.block(self, "WallLightBracket", Vector3(0.18, 0.08, 0.18), at + Vector3(0.10, 0.0, 0.0), STEEL_DARK, 0.012)
	ART.block(self, "WallLightHousing", Vector3(0.10, 0.22, 1.0), at + Vector3(0.04, 0.0, 0.0), STEEL_DARK, 0.02)
	var tube := ART.block(self, "WallLightTube", Vector3(0.035, 0.10, 0.82), at + Vector3(-0.02, 0.0, 0.0), color, 0.01, true, 0.55)
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.position = at + Vector3(-0.20, -0.04, 0.0)
	light.shadow_enabled = false
	light.set_meta("fixture", "wall")
	add_child(light)


func _sign_plate(texture_path: String, at: Vector3, size: Vector2, yaw: float) -> MeshInstance3D:
	var texture := load(texture_path) as Texture2D
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var quad := QuadMesh.new()
	quad.size = size
	var sign := MeshInstance3D.new()
	sign.name = "WallSign_%s_%d" % [texture_path.get_file().get_basename(), get_child_count()]
	sign.mesh = quad
	sign.material_override = material
	sign.position = at
	sign.rotation.y = yaw
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sign)
	return sign


func _floor_route(from_point: Vector3, to_point: Vector3, width: float) -> void:
	var delta := to_point - from_point
	var length := delta.length()
	if length < 0.01:
		return
	var center := (from_point + to_point) * 0.5
	var guide := ART.plane(self, "DistributionGuide", Vector2(length, width), center, CORE_GLOW, true, 0.18)
	guide.rotation_degrees = Vector3(0.0, PI * 0.5 if absf(delta.z) > absf(delta.x) else 0.0, 0.0)


func _stair_floor_sign(level: int, y: float) -> void:
	var names := ["b2", "b1", "1f", "2f"]
	var colors := [RED, Color("#6ba7b8"), Color("#78a88a"), Color("#d59a5b")]
	var side := 1.0 if level % 2 == 0 else -1.0
	_sign_plate("res://assets/ruin/signs/energy_floor_%s.png" % names[level], Vector3(-9.84, y + 1.78, side * 7.25), Vector2(0.56, 0.28), PI * 0.5)
	_sign_plate("res://assets/ruin/signs/energy_dir_%s.png" % names[level], Vector3(-12.0, y + 1.62, side * 9.83), Vector2(1.65, 0.62), PI if side > 0.0 else 0.0)


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
	for side: float in [-1.0, 1.0]:
		ART.block(self, "AirlockPost", Vector3(0.30, 2.8, 0.36), Vector3(side * 2.0, y + 1.4, 8.3), STEEL_DARK, 0.05)
	ART.block(self, "AirlockTop", Vector3(4.3, 0.26, 0.36), Vector3(0.0, y + 2.78, 8.3), STEEL_DARK, 0.05)
	ART.block(self, "AirlockGlow", Vector3(3.3, 0.08, 0.1), Vector3(0.0, y + 2.62, 8.15), CORE_GLOW, 0.02, true, 0.6)
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DeconPost", Vector3(0.18, 2.5, 0.18), Vector3(side * 1.8, y + 1.25, 7.3), AMBER, 0.03)
	ART.block(self, "DeconTop", Vector3(4.0, 0.18, 0.18), Vector3(0.0, y + 2.5, 7.3), STEEL_LIGHT, 0.03)
	_locker(Vector3(-3.4, y, 8.6), 0.0)
	_locker(Vector3(3.4, y, 8.6), 0.0)
	ART.plane(self, "LobbyHazard", Vector2(6.0, 0.9), Vector3(0.0, y + 0.02, 6.8), HAZARD).rotation_degrees.y = 0.0
	_chair(Vector3(-2.8, y, 6.0), 0.0)
	_chair(Vector3(2.8, y, 6.0), 0.0)
	_entrance_directory(y)


func _entrance_directory(y: float) -> void:
	# 入口旁的实体楼层导视牌：玩家一进门就能看到配电间方向。
	ART.block(self, "DirectoryPost", Vector3(0.12, 1.35, 0.12), Vector3(-2.8, y + 0.68, 6.4), STEEL_DARK, 0.02)
	_sign_plate("res://assets/ruin/signs/energy_directory.png", Vector3(-2.8, y + 1.55, 6.345), Vector2(1.9, 0.78), PI)


func _control_room(y: float) -> void:
	_console(Vector3(8.8, y, 6.0), 0.0)
	_console(Vector3(12.2, y, 3.4), -PI * 0.5)
	ART.block(self, "ControlWallPanel", Vector3(5.6, 2.6, 0.08), Vector3(9.8, y + 1.45, HALF_D - 0.18), Color("#aeb9b9"), 0.025)
	ART.block(self, "ControlWallGlow", Vector3(4.4, 0.05, 0.04), Vector3(9.8, y + 1.92, HALF_D - 0.24), CORE_GLOW, 0.01, true, 0.45)
	ART.block(self, "ControlBoard", Vector3(4.8, 1.4, 0.12), Vector3(9.8, y + 2.1, 7.9), STEEL, 0.03)
	_collider(Vector3(4.8, 1.4, 0.12), Vector3(9.8, y + 2.1, 7.9))
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
		ART.cylinder(self, "TurbinePipe", 0.10, 1.6, Vector3(6.4, y + 1.8 + float(index) * 0.18, -5.0), STEEL_LIGHT).rotation_degrees.x = 90.0
	ART.block(self, "TurbineGauge", Vector3(0.8, 0.8, 0.12), Vector3(12.8, y + 2.0, -8.5), STEEL_DARK, 0.02)
	ART.torus(self, "TurbineGaugeRing", 0.24, 0.32, Vector3(12.8, y + 2.0, -8.43), AMBER, true, 0.4)
	_collider(Vector3(3.4, 2.0, 5.6), Vector3(10.0, y + 1.0, -5.0))


func _distribution_room(y: float) -> void:
	# 伪装成配电柜的暗门；靠近按 E 进入地下庇护所。
	# 先做一个浅凹龛和门头，让玩家能看出“这里是一间房”，但门本身仍是配电柜伪装。
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DistributionAlcove", Vector3(0.28, 2.8, 0.9), Vector3(side * 1.55, y + 1.4, -9.35), STEEL, 0.03)
	ART.block(self, "DistributionAlcoveHeader", Vector3(3.4, 0.28, 0.9), Vector3(0.0, y + 2.72, -9.35), STEEL, 0.03)
	ART.block(self, "DisguisedDistributionDoor", Vector3(2.6, 2.6, 0.17), Vector3(0.0, y + 1.3, -9.75), Color("#414e4d"), 0.04)
	for stripe: int in 7:
		ART.block(self, "DistributionHazard", Vector3(0.25, 0.75, 0.02), Vector3(-1.0 + float(stripe) * 0.34, y + 0.55, -9.64), AMBER, 0.01, true, 0.12).rotation_degrees.z = 28.0
	ART.block(self, "DistributionHandle", Vector3(0.16, 0.06, 0.08), Vector3(0.9, y + 1.15, -9.62), STEEL_LIGHT, 0.02)
	ART.block(self, "DistributionLabel", Vector3(0.6, 0.18, 0.03), Vector3(-0.8, y + 2.1, -9.64), Color("#9a7d4a"), 0.01)
	# 实体门牌固定在门头，给“暗门”一个可读名称，但不改交互。
	var distribution_sign := _sign_plate("res://assets/ruin/signs/energy_distribution_fixed.png", Vector3(0.0, y + 2.12, -9.60), Vector2(1.15, 0.30), 0.0)
	var distribution_mat := distribution_sign.material_override as StandardMaterial3D
	distribution_mat.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	# 门禁通讯：玩家不进庇护所，只在门外和里面的人通话。
	ART.block(self, "IntercomHousing", Vector3(0.40, 0.56, 0.10), Vector3(1.15, y + 1.34, -9.56), STEEL_DARK, 0.02)
	ART.block(self, "IntercomGrille", Vector3(0.26, 0.14, 0.03), Vector3(1.15, y + 1.47, -9.50), STEEL, 0.01)
	ART.block(self, "IntercomButton", Vector3(0.11, 0.11, 0.04), Vector3(1.15, y + 1.25, -9.50), CORE_GLOW, 0.01, true, 0.35)
	ART.block(self, "IntercomLabel", Vector3(0.26, 0.08, 0.02), Vector3(1.15, y + 1.34, -9.50), Color("#b6c4bd"), 0.01)
	var intercom_light := OmniLight3D.new()
	intercom_light.light_color = CORE_GLOW
	intercom_light.light_energy = 0.22
	intercom_light.omni_range = 1.8
	intercom_light.position = Vector3(1.15, y + 1.3, -9.4)
	intercom_light.shadow_enabled = false
	add_child(intercom_light)
	var door_body := StaticBody3D.new()
	door_body.name = "ShelterDoorCollision"
	door_body.collision_layer = 2
	door_body.collision_mask = 0
	door_body.position = Vector3(0.0, y + 1.3, -9.66)
	var door_shape := CollisionShape3D.new()
	var door_box := BoxShape3D.new()
	door_box.size = Vector3(2.7, 2.7, 0.22)
	door_shape.shape = door_box
	door_body.add_child(door_shape)
	add_child(door_body)
	for side: float in [-1.0, 1.0]:
		ART.block(self, "DistributionSeamLight", Vector3(0.045, 2.35, 0.035), Vector3(side * 1.31, y + 1.28, -9.66), CORE_GLOW, 0.01, true, 0.38)
	ART.block(self, "DistributionSeamLight", Vector3(2.64, 0.045, 0.035), Vector3(0.0, y + 2.47, -9.66), CORE_GLOW, 0.01, true, 0.38)
	for index: int in 3:
		ART.block(self, "DistributionCabinet", Vector3(1.1, 1.8, 0.55), Vector3(10.8 + float(index) * 1.2, y + 0.9, -9.2), STEEL_DARK, 0.04)
		_collider(Vector3(1.1, 1.8, 0.55), Vector3(10.8 + float(index) * 1.2, y + 0.9, -9.2))
		ART.block(self, "CabinetGauge", Vector3(0.16, 0.16, 0.03), Vector3(10.8 + float(index) * 1.2, y + 1.2, -8.90), AMBER, 0.01, true, 0.3)
	# 从入口沿核心井西侧到配电间的贴地导向线。
	_floor_route(Vector3(-5.2, y + 0.018, 7.2), Vector3(-5.2, y + 0.018, -8.8), 0.16)
	_floor_route(Vector3(-5.2, y + 0.018, -8.8), Vector3(-0.2, y + 0.018, -8.8), 0.16)
	_floor_route(Vector3(-0.2, y + 0.018, -8.8), Vector3(-0.2, y + 0.018, -9.25), 0.16)


func _wheel(parent: Node3D, node_name: String, at: Vector3, color: Color) -> Node3D:
	var mount := Node3D.new()
	mount.name = node_name + "Mount"
	mount.position = at
	mount.rotation_degrees.x = 90.0
	parent.add_child(mount)
	var spinner := Node3D.new()
	spinner.name = node_name
	mount.add_child(spinner)
	ART.torus(spinner, node_name + "Rim", 0.42, 0.50, Vector3.ZERO, color, true, 0.25)
	ART.cylinder(spinner, node_name + "Hub", 0.10, 0.14, Vector3.ZERO, STEEL_DARK)
	for index: int in 6:
		var spoke := ART.block(spinner, node_name + "Spoke%d" % index, Vector3(0.07, 0.78, 0.07), Vector3.ZERO, color, 0.01)
		spoke.rotation_degrees.z = float(index) * 30.0
	ART.block(spinner, node_name + "Handle", Vector3(0.10, 0.20, 0.10), Vector3(0.0, 0.50, 0.0), AMBER, 0.01, true, 0.3)
	return spinner


func turn_energy_wheel(kind: String, progress: float) -> void:
	var wheel: Node3D = _pump_wheel if kind == "pump" else _reactor_wheel
	if wheel != null:
		wheel.rotation_degrees.z = clampf(progress, 0.0, 1.0) * 720.0


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
	_pump_wheel = _wheel(self, "PumpWheel", Vector3(4.2, y + 1.15, -8.38), AMBER)


func _coolant_room(y: float) -> void:
	for index: int in 3:
		var tank_x := 9.0 + float(index) * 2.0
		var tank_radius := 0.95 + float(index) * 0.1
		_tank(Vector3(tank_x, y, 5.0), tank_radius)
		_collider(Vector3(tank_radius * 2.0, 2.5, tank_radius * 2.0), Vector3(tank_x, y + 1.25, 5.0))
		ART.cylinder(self, "CoolantPipe", 0.10, 1.5, Vector3(8.2 + float(index) * 2.0, y + 1.6, 2.8), TEAL).rotation_degrees.x = 90.0
	ART.block(self, "CoolantConsole", Vector3(2.4, 1.0, 0.65), Vector3(12.4, y + 0.7, 7.8), STEEL_DARK, 0.04)
	_collider(Vector3(2.4, 1.0, 0.65), Vector3(12.4, y + 0.5, 7.8))
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
	_reactor_wheel = _wheel(self, "ReactorWheel", Vector3(5.2, y + 1.15, 3.80), CORE_GLOW)


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
	_collider(Vector3(0.9, 2.0, 0.55), at + Vector3(0.0, 1.0, 0.0), Vector3(0.0, yaw_degrees, 0.0))
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
		ART.cylinder(self, "TankPipe", 0.08, 0.45, at + Vector3(-0.36 + float(index) * 0.36, 2.72, 0.0), STEEL_LIGHT)


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
