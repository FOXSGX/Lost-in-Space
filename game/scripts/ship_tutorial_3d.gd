extends Node3D
class_name ShipTutorial3D

## 归航号独立训练舱 2.0 · 喷气背包零重力试飞厅
## - 保留全部精确训练点位与物理碰撞，100% 兼容任务进度判定与集成测试
## - 全面升级为科技感点阵 LED 教学屏 + 居中对称氧气展示台 + 高空双环飞行门

const ENTRY_POINT: Vector3 = Vector3(8.1, 0, 5.1)
const ENTRY_YAW: float = 0.85
const HOP_POINT: Vector3 = Vector3(-3.8, 0.55, 3.8)
const BOOST_POINT: Vector3 = Vector3(-4.2, 2.6, -2.3)
const CROSS_POINT: Vector3 = Vector3(2.2, 4.35, -2.3)
const FINISH_POINT: Vector3 = Vector3(6.4, 5.7, 2.5)
const INSTALL_POINT: Vector3 = BOOST_POINT
const SCAN_POINT: Vector3 = CROSS_POINT
const TARGET_POINT: Vector3 = FINISH_POINT

const NATIVE: String = "res://assets/ship-hub/kenney/space-station/"
const FLOOR: PackedScene = preload(NATIVE + "floor-detail.glb")
const DOOR: PackedScene = preload("res://assets/ship-hub/kenney/modular-space/gate-door-window.glb")
const TUTORIAL_ART: Script = preload("res://scripts/ship_tutorial_art.gd")
const LED_SHADER: Shader = preload("res://shaders/led_screen.gdshader")

const POSTERS: Dictionary = {
	"equip": preload("res://assets/textures/ship_signs/train_01_equip.png"),
	"jump": preload("res://assets/textures/ship_signs/train_02_jump.png"),
	"boost": preload("res://assets/textures/ship_signs/train_03_boost.png"),
	"recharge": preload("res://assets/textures/ship_signs/train_04_recharge.png"),
	"cross": preload("res://assets/textures/ship_signs/train_05_cross.png"),
	"exit": preload("res://assets/textures/ship_signs/train_06_exit.png"),
}

var _markers: Array[MeshInstance3D] = []
var _step: int = 0

func _ready() -> void:
	_build_room()
	_build_course()
	var art: ShipTutorialArt = TUTORIAL_ART.new() as ShipTutorialArt
	art.name = "ShipTutorialArt"
	add_child(art)
	art.install(self)
	show_step(_step)

func station_position(step: int) -> Vector3:
	var points: Array[Vector3] = [Vector3(-7, 0, 3.8), Vector3(-7, 0, 3.8), HOP_POINT, BOOST_POINT, FINISH_POINT, FINISH_POINT]
	return points[clampi(step, 0, points.size() - 1)]

func show_step(step: int) -> void:
	_step = step
	for index: int in _markers.size():
		_markers[index].material_override = _material(Color("#48f0b8") if step >= mini(index + 3, 5) else Color("#ffae42"), true)

func _build_room() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#08121d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#5b7c96")
	env.ambient_light_energy = 0.24
	environment.environment = env
	add_child(environment)

	_solid("WalkableHull", Vector3(0, -0.12, 0), Vector3(21, 0.24, 13.5))
	_box("FloorBase", Vector3(0, -0.15, 0), Vector3(21, 0.15, 13.5), Color("#1b2836"))
	_solid("ForwardWallCollision", Vector3(0, 4.6, -6.65), Vector3(21, 9.2, 0.25))
	_solid("AftWallCollision", Vector3(0, 4.6, 6.65), Vector3(21, 9.2, 0.25))
	_solid("CeilingCollision", Vector3(0, 9.3, 0), Vector3(21, 0.2, 13.5))

	# 干净规整的暗钢装甲墙壳与顶棚（取代旧版杂乱 Kenney 墙条）
	for side: int in [-1, 1]:
		_solid("SideWallCollision", Vector3(side * 10.4, 4.6, 0), Vector3(0.25, 9.2, 13.5))
		_box("SideWallShell", Vector3(side * 10.45, 4.6, 0), Vector3(0.22, 9.2, 13.5), Color("#253545"))
		for y_trim: float in [0.6, 3.8, 7.2]:
			_box("SideTrim", Vector3(side * 10.28, y_trim, 0), Vector3(0.10, 0.10, 13.0), Color("#385870"))
	for z: float in [-6.7, 6.7]:
		_box("EndWallShell", Vector3(0, 4.6, z), Vector3(21.0, 9.2, 0.22), Color("#253545"))
		for y: float in [0.6, 3.8, 7.2]:
			_box("HullStripe", Vector3(0, y, z * 0.98), Vector3(20.4, 0.08, 0.08), Color("#36c8e0"), true)
	for ix: int in 5:
		var x: float = -8.4 + ix * 4.2
		for iz: int in 3:
			_native(FLOOR, Vector3(x, -0.08, -4.4 + iz * 4.4), Vector3(4.17, 0.08, 4.37))

	_native(DOOR, Vector3(8.1, 0, 6.45), Vector3(3.65, 3.35, 0.45), PI)
	_box("Ceiling", Vector3(0, 9.4, 0), Vector3(21, 0.2, 13.5), Color("#182534"))
	for x: float in [-6.5, 0.0, 6.5]:
		_box("CeilingLight", Vector3(x, 9.16, 0), Vector3(3.4, 0.06, 0.28), Color("#c6f2ff"), true)
	_led_wall_screen("exit", Vector3(8.1, 4.35, 6.52), Vector2(2.6, 1.48), PI)

func _build_course() -> void:
	# 氧气瓶展示台碰撞盒（正对中心，美观模型由 ShipTutorialArt 装配居中对称英雄基座）
	_solid("OxygenRack", Vector3(-7.0, 0.46, 3.8), Vector3(1.55, 0.92, 1.55))

	# 4 座悬空科技试飞平台（精准对齐 HOP / BOOST / CROSS / FINISH 坐标）
	_platform("Hop", HOP_POINT, Vector2(2.4, 2.4), Color("#46b2c6"))
	_platform("Boost", BOOST_POINT, Vector2(3.3, 3.2), Color("#3cd4b8"))
	_platform("Cross", CROSS_POINT, Vector2(3.2, 3.2), Color("#58b6dc"))
	_platform("Finish", FINISH_POINT, Vector2(3.0, 2.8), Color("#ef9d42"))

	# 5 块无遮挡壁挂 LED 教学大屏（位置避开所有立柱和平台腿，一眼清晰！）
	_led_wall_screen("equip", Vector3(-10.22, 2.35, 3.8), Vector2(3.2, 1.82), PI * 0.5)
	_led_wall_screen("jump", Vector3(-3.8, 2.25, 6.50), Vector2(3.0, 1.70), PI)
	_led_wall_screen("boost", Vector3(-4.4, 5.25, -6.50), Vector2(3.4, 1.92), 0.0)
	_led_wall_screen("recharge", Vector3(2.2, 6.75, -6.50), Vector2(3.4, 1.92), 0.0)
	_led_wall_screen("cross", Vector3(10.22, 7.25, 2.5), Vector2(3.2, 1.82), -PI * 0.5)

func _platform(title: String, top: Vector3, footprint: Vector2, color: Color) -> void:
	var thickness: float = minf(top.y, 0.30)
	var center: Vector3 = Vector3(top.x, top.y - thickness * 0.5, top.z)
	var size: Vector3 = Vector3(footprint.x, thickness, footprint.y)
	_solid(title + "PlatformCollision", center, size)
	# 深钢倒角平台机身 + 奶油灰防滑甲板面 + 四周发光状态灯条
	_box(title + "Platform", center, size, Color("#243342"))
	_box(title + "LandingPad", top + Vector3.UP * 0.015, Vector3(footprint.x - 0.12, 0.035, footprint.y - 0.12), Color("#c2ccd2"))
	_markers.append(_box(title + "LandingStripe", top + Vector3(0, 0.04, footprint.y * 0.5 - 0.12), Vector3(footprint.x - 0.24, 0.04, 0.12), color, true))
	# 细长深钢承重支柱（不笨重不挡视线）
	for x: float in [-footprint.x * 0.42, footprint.x * 0.42]:
		for z: float in [-footprint.y * 0.42, footprint.y * 0.42]:
			var leg_h: float = maxf(0.1, top.y - thickness)
			var leg: Vector3 = Vector3(top.x + x, leg_h * 0.5, top.z + z)
			var leg_size: Vector3 = Vector3(0.11, leg_h, 0.11)
			_box(title + "Support", leg, leg_size, Color("#1f2c38"))
			_solid(title + "SupportCollision", leg, leg_size)

func _led_wall_screen(poster_id: String, point: Vector3, size: Vector2, yaw: float = 0.0) -> void:
	# 深钢加厚显示器外框 + 顶部状态灯条 + 点阵 LED 发光屏
	var frame: MeshInstance3D = _box("LedWallScreen_" + poster_id, point, Vector3(size.x + 0.18, size.y + 0.18, 0.10), Color("#14202c"))
	frame.rotation.y = yaw
	var image: MeshInstance3D = MeshInstance3D.new()
	image.name = "LedDisplayFace"
	var plane: QuadMesh = QuadMesh.new()
	plane.size = size
	image.mesh = plane
	image.position.z = 0.056
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = LED_SHADER
	mat.set_shader_parameter("screen_tex", POSTERS[poster_id] as Texture2D)
	mat.set_shader_parameter("emit_strength", 1.18)
	mat.set_shader_parameter("pixel_density_x", 240.0)
	mat.set_shader_parameter("pixel_density_y", 136.0)
	image.material_override = mat
	frame.add_child(image)

func _native(scene: PackedScene, point: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var root: Node3D = Node3D.new()
	root.position = point
	root.rotation.y = yaw
	add_child(root)
	var visual: Node3D = scene.instantiate() as Node3D
	ItemProp3D.linear_materials(visual)
	var bounds: AABB = ItemProp3D._bounds(visual, Transform3D.IDENTITY)
	var fit: Vector3 = size / bounds.size
	var normalizer: Node3D = Node3D.new()
	normalizer.scale = fit
	normalizer.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * fit
	root.add_child(normalizer)
	normalizer.add_child(visual)

func _solid(node_name: String, point: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = point
	body.collision_layer = 2
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)

func _box(node_name: String, point: Vector3, size: Vector3, color: Color, emission: bool = false) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.position = point
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = _material(color, emission)
	add_child(instance)
	return instance

func _material(color: Color, emission: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	material.emission_enabled = emission
	material.emission = color
	material.emission_energy_multiplier = 0.85 if emission else 0.0
	return material
