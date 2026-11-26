extends Node3D
class_name FuelCollector

## 飞船装货口：喇叭形接货斜面 + 吸入式收集仓。
## 判定用固定 AABB（有容错），不依赖高速物理碰撞；入仓只计一次。

signal fuel_collected(total: int, target: int)

const HULL := Color("#7f8e86")
const HULL_LIGHT := Color("#CFC5AE")
const HULL_DARK := Color("#6d7c74")
const TRIM := Color("#2f5c68")
const TRIM_DARK := Color("#1f3f49")
const GLASS := Color("#8fe3ff")
const AMBER := Color("#ffb347")
const CYAN := Color("#3fd8ff")
const INTAKE := Color("#0d1a20")

## 接货口在世界坐标中的容错范围（比视觉开口略大，避免像素级瞄准）。
const CATCH_MIN := Vector3(12.45, 0.0, -2.40)
const CATCH_MAX := Vector3(15.90, 2.30, 2.40)
const INTAKE_POINT := Vector3(15.15, 1.05, 0.0)

var target_count := 3
var loaded_count := 0
## 最后一次入仓的搬运者 peer（单人时 1；保留给以后多人算贡献）
var last_credit_peer := 0

## 进球判定：盯住一颗球，比较前后两帧位置。
## 规则 = 球心从场内侧越过门口平面（x = CATCH_MIN.x），且高度/横向在门洞内。
## 这样门框外侧、门顶上方、球门背面都不会误判，高速也不会漏（逐帧比 x 轴）。
var _watched: Node3D
var _prev_pos := Vector3.ZERO
var _has_prev := false

var _pips: Array[MeshInstance3D] = []
var _pulse := 0.0
var _intake_material: StandardMaterial3D
var _suction: CPUParticles3D
## 装货订单：球越过门口平面时落在哪一层（0 下 / 1 中 / 2 上）。
## 只记录，不参与判定；由 gulu_app 决定是否给 ×2。
var last_goal_zone := -1
var _order_strips: Array[MeshInstance3D] = []
var _flash := 0.0

var kit: GuluArtKit
var mat_hull: StandardMaterial3D
var mat_hull_dark: StandardMaterial3D
var mat_trim: StandardMaterial3D
var mat_glass: StandardMaterial3D
var mat_intake: ShaderMaterial
var mat_bare: ShaderMaterial
var mat_amber: StandardMaterial3D


func _ready() -> void:
	kit = GuluArtKit.new()
	mat_hull = kit.clean_paint(HULL, 0.62)
	mat_hull_dark = kit.clean_paint(HULL_DARK, 0.68)
	mat_trim = kit.clean_paint(TRIM, 0.52, 0.08)
	mat_glass = kit.emissive(GLASS, 0.42, 0.25, 0.1)
	mat_intake = kit.dark_metal(INTAKE, 0.62, 44.0)
	mat_bare = kit.bare_metal(Color("#8b979b"), 0.32, 45.0)
	mat_amber = kit.emissive(AMBER, 0.55, 0.45)
	_build_hull()
	_build_scoop()
	_build_intake()
	_build_pips()
	_update_pips()
	set_process(true)


func contains_point(point: Vector3) -> bool:
	return (
		point.x >= CATCH_MIN.x and point.x <= CATCH_MAX.x
		and point.y >= CATCH_MIN.y - 0.6 and point.y <= CATCH_MAX.y
		and point.z >= CATCH_MIN.z and point.z <= CATCH_MAX.z
	)


## 让装货口盯住一颗球（本轮只有一颗）。
func watch_ball(node: Node3D) -> void:
	_watched = node
	_has_prev = false


func _physics_process(_delta: float) -> void:
	if _watched == null or not is_instance_valid(_watched):
		return
	var point: Vector3 = _watched.global_position
	if not _has_prev:
		_prev_pos = point
		_has_prev = true
		return
	var crossed := _prev_pos.x < CATCH_MIN.x and point.x >= CATCH_MIN.x
	var inside_mouth := point.y > 0.0 and point.y < CATCH_MAX.y and absf(point.z) <= CATCH_MAX.z
	if crossed and inside_mouth and not bool(_watched.get("collected")):
		consume(_watched)
	_prev_pos = point


## 吸入点：翻空后奶龙的“发懵视线”对着这里，玩家的镜头也能对得上。
func intake_point() -> Vector3:
	return INTAKE_POINT


## 门口平面（球心越过这条线才算进门）。
func goal_plane_x() -> float:
	return CATCH_MIN.x


func consume(fuel: Node3D) -> void:
	if fuel == null or not is_instance_valid(fuel):
		return
	if bool(fuel.get("collected")):
		return
	last_goal_zone = _zone_of(fuel.global_position.y)
	fuel.call("collect")
	last_credit_peer = int(fuel.get("credit_peer"))
	loaded_count += 1
	_flash = 1.0
	_update_pips()
	_animate_intake(fuel)
	fuel_collected.emit(loaded_count, target_count)


func reset_state() -> void:
	loaded_count = 0
	last_credit_peer = 0
	last_goal_zone = -1
	_flash = 0.0
	_update_pips()


## 门口高度 → 舱层（下 / 中 / 上）。门口净空 y ∈ [0, 2.30]。
func _zone_of(y: float) -> int:
	if y < 0.78:
		return 0
	if y < 1.55:
		return 1
	return 2


## 点亮“当前订单”那一层的灯带；其余层保持熄灭，玩家从口沿就能读出该往哪踢。
func set_order_zone(zone: int) -> void:
	last_goal_zone = -1
	for index in range(_order_strips.size()):
		_order_strips[index].visible = index == zone


func _animate_intake(fuel: Node3D) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(fuel, "global_position", INTAKE_POINT, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(fuel, "scale", Vector3.ONE * 0.15, 0.45)
	tween.chain().tween_callback(func() -> void: fuel.visible = false)
	# 重开时由燃料自己 kill，避免动画把已重置的燃料又拉回仓里。
	fuel.set_meta("intake_tween", tween)


# ------------------------------------------------------------------ 几何

func _build_hull() -> void:
	# 船体：左右两侧船身夹出中间的装货口，口朝 -X。
	for side in [-1.0, 1.0]:
		_box(Vector3(6.0, 5.0, 3.6), Vector3(16.9, 2.5, side * 4.7), HULL, true, 0.0, Vector3.ZERO, mat_hull)
		_box(Vector3(0.9, 0.5, 3.7), Vector3(13.55, 4.55, side * 4.7), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
		_box(Vector3(3.2, 0.22, 3.4), Vector3(16.4, 5.05, side * 4.7), HULL_DARK, false, 0.0, Vector3.ZERO, mat_hull_dark)
		# 前脸分层：大面板 + 深色凹槽 + 铭牌，交代“外壳是装上去的”。
		_box(Vector3(0.06, 3.1, 2.65), Vector3(13.86, 2.35, side * 4.7), HULL, false, 0.0, Vector3.ZERO, mat_hull)
		_box(Vector3(0.035, 0.07, 2.35), Vector3(13.825, 3.52, side * 4.7), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
		_box(Vector3(0.035, 0.07, 2.35), Vector3(13.825, 1.18, side * 4.7), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
		_box(Vector3(0.025, 0.55, 0.72), Vector3(13.815, 2.55, side * 4.70), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
		for index in range(3):
			_box(Vector3(0.16, 1.0, 1.3), Vector3(13.88, 3.15, side * 4.7 - 1.15 + float(index) * 1.15), GLASS, false, 1.0, Vector3.ZERO, mat_glass)
		# 侧鳍：让船在远景里有方向感
		_box(Vector3(2.4, 0.9, 0.18), Vector3(17.9, 3.0, side * 6.55), TRIM, false, 0.0, Vector3(side * 0.3, 0.0, 0.0), mat_trim)
	# 背板与顶部
	_box(Vector3(3.2, 5.0, 13.0), Vector3(18.4, 2.5, 0.0), HULL, true, 0.0, Vector3.ZERO, mat_hull)
	_box(Vector3(6.0, 1.4, 13.0), Vector3(16.9, 4.7, 0.0), HULL, true, 0.0, Vector3.ZERO, mat_hull)
	_box(Vector3(0.24, 0.16, 12.6), Vector3(13.9, 4.02, 0.0), CYAN, false, 1.0, Vector3.ZERO, mat_glass)
	_box(Vector3(0.6, 0.7, 13.4), Vector3(17.0, 5.6, 0.0), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
	# 顶部面板缝与检修盖
	for z in [-5.2, -2.6, 0.0, 2.6, 5.2]:
		_box(Vector3(4.2, 0.02, 0.05), Vector3(16.9, 5.405, z), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
	for z in [-3.9, 3.9]:
		_box(Vector3(1.6, 0.03, 1.2), Vector3(16.3, 5.415, z), HULL_LIGHT, false, 0.0, Vector3.ZERO, mat_hull)
	# 尾部引擎
	_box(Vector3(0.3, 2.6, 9.0), Vector3(19.9, 2.4, 0.0), HULL_DARK, false, 0.0, Vector3.ZERO, mat_hull_dark)
	for side in [-1.0, 1.0]:
		var nozzle := CylinderMesh.new()
		nozzle.top_radius = 0.85
		nozzle.bottom_radius = 1.05
		nozzle.height = 1.5
		var nozzle_node := MeshInstance3D.new()
		nozzle_node.mesh = nozzle
		nozzle_node.position = Vector3(20.1, 2.2, side * 3.4)
		nozzle_node.rotation.z = PI * 0.5
		nozzle_node.material_override = mat_trim
		add_child(nozzle_node)
		_box(Vector3(0.10, 1.5, 1.5), Vector3(20.78, 2.2, side * 3.4), CYAN, false, 0.55, Vector3.ZERO, mat_glass)
	# 起落架
	for side in [-1.0, 1.0]:
		for x in [15.4, 18.8]:
			_leg(Vector3(x, 0.5, side * 5.6))


func _build_scoop() -> void:
	# 接货平台（与地面齐平，可走进去）
	_box(Vector3(4.6, 0.3, 5.8), Vector3(13.55, -0.15, 0.0), HULL_DARK, true, 0.0, Vector3.ZERO, mat_hull_dark)
	# 平台面：金属底板 + 两条压条，读得出“这里是落货面”。
	_box(Vector3(4.05, 0.02, 5.15), Vector3(13.55, 0.012, 0.0), TRIM, false, 0.0, Vector3.ZERO, mat_bare)
	for z in [-2.2, 2.2]:
		_box(Vector3(3.7, 0.025, 0.08), Vector3(13.55, 0.026, z), TRIM_DARK, false, 0.0, Vector3.ZERO, mat_trim)
	# 入口标线：贴地、无碰撞，球可以直接滚进装货口。
	_box(Vector3(0.42, 0.02, 5.8), Vector3(11.5, 0.014, 0.0), AMBER, false, 0.55, Vector3.ZERO, mat_amber)
	# 地面导引条
	for side in [-1.0, 1.0]:
		_box(Vector3(4.2, 0.02, 0.20), Vector3(13.6, 0.015, side * 1.45), AMBER, false, 0.5, Vector3(0, side * 0.10, 0), mat_amber)
	# 两侧接货斜面（漏斗），碰撞跟着一起旋转
	for side in [-1.0, 1.0]:
		_box(Vector3(3.9, 1.10, 0.34), Vector3(13.5, 0.55, side * 2.95), HULL, true, 0.0, Vector3(0, side * 0.42, 0), mat_hull)
		_box(Vector3(3.9, 0.14, 0.44), Vector3(13.5, 1.16, side * 2.95), AMBER, false, 0.7, Vector3(0, side * 0.42, 0), mat_amber)
		# 斜面上的橡胶防撞唇
		_box(Vector3(3.55, 0.05, 0.10), Vector3(13.5, 1.09, side * 2.95), INTAKE, false, 0.0, Vector3(0, side * 0.42, 0), mat_intake)
	# 平台边缘灯
	_box(Vector3(0.12, 0.10, 5.6), Vector3(11.36, 0.03, 0.0), AMBER, false, 1.0, Vector3.ZERO, mat_amber)


func _build_intake() -> void:
	# 装货口 = 一个有深度的舱口，不是靶心。
	# 口沿（x≈15.02）比舱底（x≈16.16）大，四面内壁向内收，靠透视与光照读出“能塞进去”；
	# 舱底三根发光栅读作能源接收线圈，口沿一圈琥珀内唇读作“入口”。
	var mouth_x := 15.02
	var back_x := 16.16
	# 1) 口沿外框：四条倒角压条，把开口从船体上“切”出来。
	_box(Vector3(0.16, 0.16, 3.44), Vector3(mouth_x, 2.22, 0.0), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
	_box(Vector3(0.16, 0.16, 3.44), Vector3(mouth_x, -0.02, 0.0), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.16, 2.24, 0.16), Vector3(mouth_x, 1.10, side * 1.72), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
	# 2) 琥珀内唇：比外框小 6 cm 的一圈，交代“这里是入口”。
	_box(Vector3(0.05, 0.06, 3.10), Vector3(mouth_x + 0.09, 2.10, 0.0), AMBER, false, 0.0, Vector3.ZERO, mat_amber)
	_box(Vector3(0.05, 0.06, 3.10), Vector3(mouth_x + 0.09, 0.10, 0.0), AMBER, false, 0.0, Vector3.ZERO, mat_amber)
	# 3) 四面内壁：从口沿斜收到舱底，形成漏斗。
	var wall_len: float = back_x - mouth_x + 0.12
	var mid_x: float = (mouth_x + back_x) * 0.5
	_box(Vector3(wall_len, 0.05, 3.05), Vector3(mid_x, 1.88, 0.0), HULL_DARK, false, 0.0, Vector3(0.0, 0.0, -0.22), mat_hull_dark)
	_box(Vector3(wall_len, 0.05, 3.05), Vector3(mid_x, 0.32, 0.0), HULL_DARK, false, 0.0, Vector3(0.0, 0.0, 0.22), mat_hull_dark)
	for side in [-1.0, 1.0]:
		_box(Vector3(wall_len, 1.95, 0.05), Vector3(mid_x, 1.10, side * 1.45), HULL_DARK, false,
			0.0, Vector3(0.0, side * 0.28, 0.0), mat_hull_dark)
	# 4) 舱底：深色底板 + 三道竖向发光栅（代替同心圆靶）。
	_box(Vector3(0.06, 1.70, 2.55), Vector3(back_x, 1.10, 0.0), INTAKE, false, 0.0, Vector3.ZERO, mat_intake)
	_intake_material = kit.emissive(CYAN, 0.90, 0.42)
	for z in [-0.60, 0.0, 0.60]:
		_box(Vector3(0.05, 0.62, 0.06), Vector3(back_x - 0.05, 1.10, z), CYAN, false, 0.0, Vector3.ZERO, _intake_material)
	# 舱内补光：没有它四面内壁会全黑，纵深读不出来。
	var cavity := OmniLight3D.new()
	cavity.position = Vector3(15.72, 1.10, 0.0)
	cavity.light_color = CYAN
	cavity.light_energy = 0.55
	cavity.omni_range = 2.4
	add_child(cavity)
	# 5) 底部导流坡：视觉上把球“接住”，不参与物理。
	_box(Vector3(1.05, 0.08, 1.45), Vector3(15.55, 0.06, 0.0), TRIM_DARK, false,
		0.0, Vector3(0.0, 0.0, -0.08), mat_bare)
	for z in [-0.48, 0.48]:
		_box(Vector3(1.0, 0.012, 0.06), Vector3(15.55, 0.106, z), AMBER, false, 0.0, Vector3.ZERO, mat_amber)
	# 6) 吸力粒子 + 口沿灯条。
	_build_suction()
	# 7) 订单灯带：三层各一条，只有当前订单那层亮（默认中舱）。
	var order_material := kit.emissive(AMBER, 0.85, 0.40)
	for index in range(3):
		var band_y: float = 0.45 + float(index) * 0.71
		var strip := _box(Vector3(0.03, 0.06, 2.80), Vector3(15.14, band_y, 0.0), AMBER, false,
			0.0, Vector3.ZERO, order_material)
		strip.visible = index == 1
		_order_strips.append(strip)
	_box(Vector3(0.10, 0.08, 2.95), Vector3(15.04, 2.25, 0.0), CYAN, false, 0.0, Vector3.ZERO, _intake_material)
	_box(Vector3(0.10, 0.08, 2.95), Vector3(15.04, 0.10, 0.0), CYAN, false, 0.0, Vector3.ZERO, _intake_material)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.10, 2.2, 0.08), Vector3(15.04, 1.12, side * 1.58), CYAN, false, 0.0, Vector3.ZERO, _intake_material)
	var glow := OmniLight3D.new()
	glow.position = Vector3(15.15, 1.2, 0.0)
	glow.light_color = CYAN
	glow.light_energy = 0.60
	glow.omni_range = 4.5
	add_child(glow)
	var amber := OmniLight3D.new()
	amber.position = Vector3(12.4, 0.9, 0.0)
	amber.light_color = AMBER
	amber.light_energy = 0.35
	amber.omni_range = 4.5
	add_child(amber)


## 吸力粒子：从口沿沿 +X 往舱内流，读作“在吸货”，而不是靶心。
func _build_suction() -> void:
	_suction = CPUParticles3D.new()
	_suction.name = "IntakeSuction"
	_suction.amount = 18
	_suction.lifetime = 0.85
	_suction.preprocess = 0.8
	_suction.local_coords = false
	_suction.emitting = true
	_suction.position = Vector3(15.10, 1.10, 0.0)
	_suction.direction = Vector3(1.0, 0.0, 0.0)
	_suction.spread = 12.0
	_suction.initial_velocity_min = 1.6
	_suction.initial_velocity_max = 2.8
	_suction.gravity = Vector3.ZERO
	_suction.scale_amount_min = 1.0
	_suction.scale_amount_max = 1.0
	_suction.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_suction.emission_box_extents = Vector3(0.05, 1.05, 1.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_suction.material_override = mat
	_suction.color = Color("#7fe6ff")
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	_suction.mesh = quad
	add_child(_suction)


func _build_pips() -> void:
	# 三格装货指示灯：装在横梁正面的凹槽里，远处靠“亮了几格”读数。
	for index in range(3):
		var z := -0.9 + float(index) * 0.9
		_box(Vector3(0.035, 0.36, 0.36), Vector3(13.005, 3.66, z), INTAKE, false, 0.0, Vector3.ZERO, mat_intake)
		var lens := _box(Vector3(0.025, 0.28, 0.28), Vector3(12.982, 3.66, z), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
		_pips.append(lens)


func _update_pips() -> void:
	for index in range(_pips.size()):
		var lit: bool = index < loaded_count
		var mat := StandardMaterial3D.new()
		mat.albedo_color = AMBER if lit else TRIM
		mat.roughness = 0.7
		if lit:
			mat.emission_enabled = true
			mat.emission = AMBER
			mat.emission_energy_multiplier = 1.0
		_pips[index].material_override = mat


func _process(delta: float) -> void:
	_pulse += delta
	_flash = maxf(0.0, _flash - delta * 2.2)
	if _intake_material != null:
		_intake_material.emission_energy_multiplier = 1.2 + 0.35 * sin(_pulse * 2.4) + _flash * 1.6


func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.metallic = 0.05
	material.metallic_specular = 0.22
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _leg(at: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.26
	mesh.bottom_radius = 0.34
	mesh.height = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(Color("#8fa3a1"), 0.0)
	add_child(instance)


func _box(size: Vector3, at: Vector3, color: Color, solid: bool, emission: float = 0.0, rotation: Vector3 = Vector3.ZERO, material: Material = null) -> MeshInstance3D:
	var mesh: Mesh = kit.beveled_box(size, minf(0.04, minf(size.x, minf(size.y, size.z)) * 0.18))
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rotation
	instance.material_override = material if material != null else _material(color, emission)
	add_child(instance)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		body.position = at
		body.rotation = rotation
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		add_child(body)
	return instance


func _mesh_node(mesh: Mesh, at: Vector3, rotation: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rotation
	instance.material_override = material
	add_child(instance)
	return instance


func _torus(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 32
	mesh.ring_segments = 8
	return mesh









