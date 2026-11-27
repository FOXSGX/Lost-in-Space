extends Node3D

## 腐墟星地下庇护所：能源站 1F 配电间暗门后的独立室内。
## 老工程师和年轻医生在这里靠独立维生系统活着；也是三种撤离方案的选择点。

const ART := preload("res://scripts/ruin_cartoon_art.gd")

const BASE_Y := 700.0
const W := 18.0
const D := 12.0
const HALF_W := 9.0
const HALF_D := 6.0
const FLOOR_HEIGHT := 3.0

const FLOOR_TILE := Color("#5b625b")
const WALL := Color("#8a8b7c")
const WALL_LOW := Color("#36524f")
const CEILING := Color("#989687")
const METAL := Color("#455a58")
const WOOD := Color("#715739")
const LINEN := Color("#c4c6b8")
const TEAL := Color("#3c716b")
const AMBER := Color("#c58c43")
const RED := Color("#963f35")
const DARK := Color("#182827")
const GLASS := Color("#5b8383")
const DOCTOR := Color("#9fb9b2")
const ENGINEER := Color("#8a6b4b")

var controller: Main3D
var _flicker_lights: Array[OmniLight3D] = []
var _phase := 0.0


func build(owner: Main3D, parent: Node3D) -> void:
	controller = owner
	name = "RuinShelterInterior"
	position = Vector3(0.0, BASE_Y, 0.0)
	parent.add_child(self)
	_shell()
	_furnish()
	# 庇护所不再生成工程师/医生实体；交互点保留为不可见通讯锚点，只走对话。
	set_process(true)


func spawn_position() -> Vector3:
	return global_position + Vector3(0.0, 0.15, 4.0)


func exit_position() -> Vector3:
	return global_position + Vector3(0.0, 0.0, 5.35)


func level_position(level: int) -> Vector3:
	return global_position + Vector3(0.0, float(level) * FLOOR_HEIGHT, 0.0)


func level_count() -> int:
	return 1


func is_inside(point: Vector3) -> bool:
	var local := point - global_position
	return local.y > -1.0 and local.y < FLOOR_HEIGHT + 1.0 and absf(local.x) <= HALF_W + 1.5 and absf(local.z) <= HALF_D + 1.5


func npc_positions() -> Dictionary:
	return {
		"engineer": global_position + Vector3(-3.2, 0.9, -1.2),
		"doctor": global_position + Vector3(3.2, 0.9, -1.2),
	}


func _process(delta: float) -> void:
	_phase += delta
	for index: int in _flicker_lights.size():
		var light := _flicker_lights[index]
		if is_instance_valid(light):
			light.light_energy = float(light.get_meta("base_energy", 0.45)) * (0.88 + 0.12 * sin(_phase * 5.0 + float(index)))



# ── 房间 ─────────────────────────────────────────────────────

func _shell() -> void:
	ART.block(self, "ShelterFloor", Vector3(W, 0.22, D), Vector3(0.0, -0.11, 0.0), FLOOR_TILE, 0.04).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(Vector3(W, 0.22, D), Vector3(0.0, -0.11, 0.0))
	ART.block(self, "ShelterCeiling", Vector3(W, 0.14, D), Vector3(0.0, FLOOR_HEIGHT + 0.07, 0.0), CEILING, 0.04).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_wall(Vector3(W, FLOOR_HEIGHT, 0.25), Vector3(0.0, FLOOR_HEIGHT * 0.5, -HALF_D))
	_wall(Vector3(0.25, FLOOR_HEIGHT, D), Vector3(-HALF_W, FLOOR_HEIGHT * 0.5, 0.0))
	_wall(Vector3(0.25, FLOOR_HEIGHT, D), Vector3(HALF_W, FLOOR_HEIGHT * 0.5, 0.0))
	# 南墙：中间是通往能源站的暗门，门洞左右各一段。
	_wall(Vector3(7.6, FLOOR_HEIGHT, 0.25), Vector3(-5.2, FLOOR_HEIGHT * 0.5, HALF_D))
	_wall(Vector3(7.6, FLOOR_HEIGHT, 0.25), Vector3(5.2, FLOOR_HEIGHT * 0.5, HALF_D))
	_door_frame(Vector3(0.0, 0.0, HALF_D), 2.8, 2.8, AMBER)
	for side: float in [-1.0, 1.0]:
		_collider(Vector3(0.30, FLOOR_HEIGHT, 0.44), Vector3(side * 1.45, FLOOR_HEIGHT * 0.5, HALF_D))
	ART.block(self, "ShelterDoor", Vector3(2.4, 2.4, 0.10), Vector3(0.0, 1.2, HALF_D - 0.12), METAL, 0.05)
	ART.block(self, "ShelterDoorGlow", Vector3(1.9, 0.07, 0.04), Vector3(0.0, 2.25, HALF_D - 0.20), AMBER, 0.01, true, 0.4)
	ART.block(self, "ShelterExitSign", Vector3(0.8, 0.24, 0.06), Vector3(0.0, 2.6, HALF_D - 0.24), TEAL, 0.02, true, 0.45)
	var door_body := StaticBody3D.new()
	door_body.name = "InteriorEntranceDoorCollision"
	door_body.collision_layer = 2
	door_body.collision_mask = 0
	door_body.position = Vector3(0.0, 1.2, HALF_D - 0.12)
	var door_shape := CollisionShape3D.new()
	var door_box := BoxShape3D.new()
	door_box.size = Vector3(2.4, 2.4, 0.14)
	door_shape.shape = door_box
	door_body.add_child(door_shape)
	add_child(door_body)

	for side: float in [-1.0, 1.0]:
		ART.block(self, "ShelterWainscot", Vector3(W - 0.4, 0.9, 0.05), Vector3(0.0, 0.45, side * (HALF_D - 0.13)), WALL_LOW, 0.03)
	for x: float in [-6.0, -2.0, 2.0, 6.0]:
		ART.block(self, "ShelterBeam", Vector3(0.16, 0.16, D - 0.4), Vector3(x, FLOOR_HEIGHT - 0.15, 0.0), Color("#8c8069"), 0.02)

	_light(Vector3(-4.0, FLOOR_HEIGHT - 0.16, 0.0), Color("#f0ddbb"), 1.35, 9.0)
	_light(Vector3(4.0, FLOOR_HEIGHT - 0.16, 0.0), Color("#d7e2d5"), 1.1, 8.0)
	_light(Vector3(0.0, FLOOR_HEIGHT - 0.16, -4.0), AMBER, 0.55, 5.0)
	_light(Vector3(0.0, 2.55, 4.6), TEAL, 0.45, 3.5)
	var red := OmniLight3D.new()
	red.light_color = RED
	red.light_energy = 0.42
	red.omni_range = 4.0
	red.position = Vector3(6.5, 2.2, -4.0)
	red.shadow_enabled = false
	red.set_meta("base_energy", 0.42)
	add_child(red)
	_flicker_lights.append(red)


func _wall(size: Vector3, center: Vector3) -> void:
	ART.block(self, "ShelterWall", size, center, WALL, 0.05).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(size, center)
	ART.block(self, "ShelterBase", Vector3(size.x + 0.02, 0.14, size.z + 0.02), center + Vector3(0.0, -size.y * 0.5 + 0.07, 0.0), DARK, 0.02)


func _door_frame(at: Vector3, width: float, height: float, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		ART.block(self, "ShelterDoorPost", Vector3(0.16, height, 0.4), at + Vector3(side * width * 0.5, height * 0.5, 0.0), color, 0.03)
	ART.block(self, "ShelterDoorHeader", Vector3(width + 0.3, 0.20, 0.4), at + Vector3(0.0, height, 0.0), color, 0.03)


func _light(at: Vector3, color: Color, energy: float, range_value: float) -> void:
	ART.block(self, "ShelterLamp", Vector3(1.5, 0.06, 0.32), at, color, 0.02, true, 0.4).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.position = at + Vector3(0.0, -0.22, 0.0)
	light.shadow_enabled = false
	add_child(light)


# ── 陈设 ─────────────────────────────────────────────────────

func _furnish() -> void:
	# 西侧：工程师工作台、工具、配电/维生控制。
	_workbench(Vector3(-6.6, 0.0, -2.4), 0.0)
	for index: int in 3:
		ART.block(self, "EngineerTool", Vector3(0.32, 0.08, 0.16), Vector3(-6.9 + float(index) * 0.32, 1.0, -2.2), METAL, 0.01)
	ART.block(self, "LifeSupport", Vector3(2.0, 2.2, 0.8), Vector3(-7.4, 1.1, 3.6), Color("#4c6461"), 0.05)
	for index: int in 4:
		ART.block(self, "LifeSupportLight", Vector3(0.12, 0.05, 0.03), Vector3(-7.4, 0.5 + float(index) * 0.4, 3.98), TEAL if index < 3 else AMBER, 0.01, true, 0.35)
	ART.block(self, "EngineerShelf", Vector3(1.8, 1.5, 0.4), Vector3(-7.2, 1.8, -5.2), WOOD, 0.03)
	ART.block(self, "EngineerRadio", Vector3(1.4, 0.5, 0.5), Vector3(-6.2, 1.1, -2.4), DARK, 0.02)
	ART.block(self, "EngineerRadioLight", Vector3(0.25, 0.08, 0.03), Vector3(-6.6, 1.2, -2.14), AMBER, 0.01, true, 0.5)

	# 东侧：医生诊疗台、样本冷柜、药箱、病床。
	ART.block(self, "MedTable", Vector3(2.6, 0.9, 1.0), Vector3(6.4, 0.45, -2.2), Color("#72827c"), 0.04)
	for index: int in 3:
		ART.cylinder(self, "MedVial", 0.05, 0.18, Vector3(5.4 + float(index) * 0.25, 1.0, -2.2), Color("#8ec1b6"), true, 0.15)
	ART.block(self, "SampleFridge", Vector3(1.6, 2.0, 0.9), Vector3(7.4, 1.0, 2.4), Color("#526c68"), 0.05)
	ART.block(self, "SampleFridgeDoor", Vector3(1.2, 1.55, 0.05), Vector3(7.4, 1.1, 2.88), GLASS, 0.02, true, 0.12)
	for index: int in 3:
		ART.cylinder(self, "MarrowSample", 0.10, 0.22, Vector3(7.0 + float(index) * 0.35, 0.7 + float(index) * 0.28, 2.86), Color("#7fd9c6"), true, 0.4)
	ART.block(self, "MedCot", Vector3(1.0, 0.55, 2.4), Vector3(5.6, 0.30, 3.5), LINEN, 0.04)
	ART.block(self, "MedCotPillow", Vector3(0.7, 0.14, 0.4), Vector3(5.6, 0.65, 2.6), Color("#d5d2c0"), 0.03)
	ART.cylinder(self, "IVStand", 0.035, 1.8, Vector3(4.8, 0.9, 4.2), METAL)
	ART.sphere(self, "IVBag", Vector3(0.22, 0.32, 0.18), Vector3(4.8, 1.75, 4.2), Color("#c9dfd4"))
	ART.block(self, "MedCabinet", Vector3(1.4, 1.7, 0.5), Vector3(8.2, 0.85, -4.8), Color("#9aa89d"), 0.04)

	# 中央：无线电/地图桌，剧情对话常在这里汇合。
	ART.block(self, "MapTable", Vector3(3.2, 0.9, 1.8), Vector3(0.0, 0.45, -0.5), WOOD, 0.04)
	ART.block(self, "MapSurface", Vector3(2.8, 0.04, 1.4), Vector3(0.0, 0.92, -0.5), Color("#a9a68d"), 0.01)
	ART.block(self, "MapRedLine", Vector3(2.0, 0.02, 0.08), Vector3(-0.2, 0.95, -0.4), RED, 0.005, true, 0.2)
	ART.block(self, "MapBlueLine", Vector3(1.6, 0.02, 0.06), Vector3(0.4, 0.95, -0.8), TEAL, 0.005, true, 0.2)
	ART.block(self, "ShelterRadio", Vector3(1.8, 0.6, 0.8), Vector3(0.0, 1.2, -0.5), DARK, 0.03)
	ART.block(self, "ShelterRadioGlow", Vector3(0.7, 0.18, 0.04), Vector3(0.0, 1.3, -0.08), AMBER, 0.01, true, 0.4)
	ART.cylinder(self, "RadioAntenna", 0.02, 1.3, Vector3(0.6, 2.05, -0.5), METAL)

	# 生活区：上下铺、储物柜、水桶和撤离包。
	for index: int in 2:
		_bunk(Vector3(-5.6 + float(index) * 1.6, 0.0, 4.2))
	for index: int in 2:
		_bunk(Vector3(3.8 + float(index) * 1.5, 0.0, 4.2))
	ART.block(self, "ShelterLocker", Vector3(1.2, 1.9, 0.5), Vector3(-1.8, 0.95, 5.4), Color("#4c625f"), 0.03)
	ART.block(self, "ShelterCrate", Vector3(0.9, 0.7, 0.7), Vector3(1.9, 0.35, 5.2), Color("#755e43"), 0.03)
	ART.block(self, "EvacPack", Vector3(0.7, 0.5, 0.4), Vector3(2.8, 0.25, 5.3), Color("#8d6d45"), 0.03)

	# 墙面：区域图、管线图、手写值班表，全做实体板，不用悬浮字。
	ART.block(self, "ShelterMapBoard", Vector3(3.4, 1.8, 0.06), Vector3(-1.8, 1.9, -5.85), Color("#59665b"), 0.02)
	ART.block(self, "ShelterMapRed", Vector3(2.6, 0.06, 0.03), Vector3(-1.8, 2.0, -5.76), RED, 0.01, true, 0.2).rotation_degrees.z = 9.0
	for index: int in 4:
		ART.block(self, "ShelterDutyCard", Vector3(0.38, 0.5, 0.03), Vector3(3.4 + float(index) * 0.55, 1.7, 5.84), Color("#b8ad94"), 0.01)
	ART.block(self, "ShelterPipe", Vector3(7.0, 0.12, 0.12), Vector3(-2.0, 2.65, -5.75), METAL, 0.02)
	for index: int in 3:
		ART.cylinder(self, "ShelterValve", 0.09, 0.12, Vector3(-4.2 + float(index) * 2.2, 2.65, -5.68), AMBER)
	_debris()


func _workbench(at: Vector3, yaw_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "ShelterWorkbench"
	root.position = at
	root.rotation_degrees.y = yaw_degrees
	add_child(root)
	ART.block(root, "Top", Vector3(2.8, 0.10, 1.0), Vector3(0.0, 0.9, 0.0), WOOD, 0.03)
	ART.block(root, "Frame", Vector3(2.6, 0.8, 0.12), Vector3(0.0, 0.45, 0.38), METAL, 0.03)
	ART.block(root, "Shelf", Vector3(2.4, 0.08, 0.5), Vector3(0.0, 0.42, 0.2), METAL, 0.02)
	_collider(Vector3(2.8, 1.0, 1.0), at + Vector3(0.0, 0.5, 0.0), Vector3(0.0, yaw_degrees, 0.0))


func _bunk(at: Vector3) -> void:
	ART.block(self, "BunkFrame", Vector3(1.1, 1.9, 2.2), at + Vector3(0.0, 0.95, 0.0), METAL, 0.04)
	ART.block(self, "BunkMattress", Vector3(0.95, 0.18, 2.0), at + Vector3(0.0, 1.05, 0.0), LINEN, 0.03)
	ART.block(self, "BunkPillow", Vector3(0.55, 0.12, 0.36), at + Vector3(0.0, 1.18, -0.72), Color("#d0cec0"), 0.02)
	ART.block(self, "BunkBlanket", Vector3(0.9, 0.08, 1.1), at + Vector3(0.0, 1.16, 0.45), Color("#6d8279"), 0.02)


func _debris() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4417
	for index: int in 10:
		ART.block(self, "ShelterPaper", Vector3(rng.randf_range(0.18, 0.30), 0.012, rng.randf_range(0.16, 0.26)), Vector3(rng.randf_range(-7.0, 7.0), 0.02, rng.randf_range(-4.0, 4.5)), Color("#b4ab95"), 0.005).rotation_degrees.y = rng.randf_range(0.0, 180.0)
	ART.plane(self, "ShelterStain", Vector2(1.4, 0.8), Vector3(2.0, 0.02, 2.0), Color("#5b5548")).rotation_degrees.y = 18.0


# ── NPC ──────────────────────────────────────────────────────

func _collider(size: Vector3, center: Vector3, rotation_degrees_value := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.name = "ShelterCollision"
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
