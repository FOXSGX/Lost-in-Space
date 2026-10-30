extends Node3D
class_name NailongEnvironment

## 奶龙星精修场景：装货口 / 搬运场地 / 生物窝。
##
## 只负责「看得见的东西」：地面分区、装货口框架与坡道、窝区痕迹、岩石轮廓、灯光。
## 玩法规则、控制器参数、装货判定 AABB（collector.gd 的 CATCH_MIN/MAX）都不在这里改。
##
## 风格对齐飞船（ship_hub_3d.gd）：壳体 #c4d2d0 系、结构 #375967、暖灯 #f5eddc；
## 星球侧压深为 #9aa9a6；燃料琥珀 #ffb347、提示青 #3fd8ff。
##
## 第一阶段（当前）：布局 / 主要形体 / 基础配色 / 光照。细装饰留到方向确认之后。

const HULL := Color("#9aa9a6")
const HULL_LIGHT := Color("#c4d2d0")
const HULL_DARK := Color("#7f8f8c")
const TRIM := Color("#375967")
const TRIM_DARK := Color("#28414d")
const GLASS := Color("#8fe3ff")
const AMBER := Color("#ffb347")
const CYAN := Color("#3fd8ff")
const INTAKE := Color("#0d1a20")

const GROUND := Color("#4e615e")
const GROUND_WARM := Color("#5b6b62")
const GROUND_COOL := Color("#566864")
const SCUFF := Color("#3c4b48")
const STONE := Color("#8fa29d")
const STONE_LIGHT := Color("#a5b7b1")
const STONE_DARK := Color("#6f827e")
const CRATE := Color("#b5865a")
const CRATE_DARK := Color("#8f6640")
const PACK := Color("#c9bda6")

const NEST_CENTER := Vector3(1.0, 0.0, -2.5)

var _flash := 0.0
var _clamp_arms: Array[Node3D] = []
var _strip_material: StandardMaterial3D
var _bay_light: OmniLight3D


func _ready() -> void:
	_build_ground()
	_build_perimeter()
	_build_yard()
	_build_nest()
	_build_bay_frame()
	_build_lights()
	set_process(true)


# ---------------------------------------------------------------- 装货反馈

## 装货成功：夹臂向内一夹再复位，门框灯带同步闪一下（机械 + 灯光）。
func on_loaded(_total: int) -> void:
	_flash = 1.0
	if _strip_material != null:
		_strip_material.emission_energy_multiplier = 4.0
	var hit := create_tween()
	var back := create_tween()
	back.tween_interval(0.40)
	for index in range(_clamp_arms.size()):
		var arm: Node3D = _clamp_arms[index]
		var side := -1.0 if index == 0 else 1.0
		hit.parallel().tween_property(arm, "rotation:x", -side * 0.34, 0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		back.parallel().tween_property(arm, "rotation:x", 0.0, 0.36) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - delta * 1.6)
	if _strip_material != null:
		_strip_material.emission_energy_multiplier = 0.8 + _flash * 3.2
	if _bay_light != null:
		_bay_light.light_energy = 0.30 + _flash * 0.45


# ---------------------------------------------------------------- 地面

func _build_ground() -> void:
	_box(Vector3(40.0, 0.5, 30.0), Vector3(0.0, -0.25, 0.0), GROUND, true)

	# 大块地面色差，而不是一整片同色地板；也不铺满小砖块。
	_box(Vector3(16.0, 0.02, 10.0), Vector3(-3.0, 0.012, 4.2), GROUND_WARM)
	_box(Vector3(9.0, 0.02, 11.0), Vector3(5.0, 0.013, -1.0), GROUND_COOL)
	_box(Vector3(8.0, 0.02, 9.0), Vector3(-13.0, 0.014, 4.0), Color("#53655f"))
	_box(Vector3(10.0, 0.02, 7.0), Vector3(-4.0, 0.015, -7.4), Color("#4a5c58"))

	# 常走路线的磨痕：从出生点斜向停机坪，暗示这里被搬运踩了很多次。
	for index in range(8):
		var t := float(index)
		_box(Vector3(1.5, 0.02, 0.14), Vector3(-8.6 + t * 2.1, 0.03, 4.3 - t * 0.2), SCUFF)

	# 停机坪：一块压深的圆盘 + 一圈结构色边，站在这里就是「门前 4 米」。
	var pad := CylinderMesh.new()
	pad.top_radius = 4.6
	pad.bottom_radius = 4.5
	pad.height = 0.06
	pad.radial_segments = 36
	_add(pad, Vector3(6.6, 0.0, 0.0), Color("#8fa19c"))
	_ring(4.42, 4.58, Vector3(6.6, 0.05, 0.0), TRIM)

	# 舱口前的定位短刻线（四条），让门口有一段可读的「工作区」。
	for side in [-1.0, 1.0]:
		for index in range(4):
			_box(Vector3(0.7, 0.02, 0.14), Vector3(9.0 + float(index) * 0.75, 0.07, side * 3.4), AMBER, false, 0.45)


# ---------------------------------------------------------------- 边界与地形

func _build_perimeter() -> void:
	# 碰撞仍是原来的四面隐形墙（边界与之前完全一致），
	# 视觉上换成土坡 + 岩脊，避免「只有平地加一堵围墙」。
	_solid_only(Vector3(40.0, 6.0, 0.8), Vector3(0.0, 3.0, -15.0))
	_solid_only(Vector3(40.0, 6.0, 0.8), Vector3(0.0, 3.0, 15.0))
	_solid_only(Vector3(0.8, 6.0, 30.0), Vector3(-20.0, 3.0, 0.0))
	_solid_only(Vector3(0.8, 6.0, 30.0), Vector3(20.0, 3.0, 0.0))

	# 压住地平线的土坡（低于视线，不会挡玩法）
	_box(Vector3(39.6, 1.5, 2.4), Vector3(0.0, 0.45, -14.0), STONE_DARK)
	_box(Vector3(39.6, 1.2, 2.2), Vector3(0.0, 0.30, 14.0), STONE_DARK)
	_box(Vector3(2.4, 1.3, 29.0), Vector3(-19.2, 0.35, 0.0), STONE_DARK)

	# 北/南/西三面的大轮廓岩脊：少而大，不挡中间的通路
	for spot in [
		Vector3(-17.5, 0.0, -12.4), Vector3(-10.0, 0.0, -13.4), Vector3(-2.0, 0.0, -13.0),
		Vector3(6.5, 0.0, -13.6), Vector3(14.0, 0.0, -12.8),
		Vector3(-16.5, 0.0, 12.6), Vector3(-8.5, 0.0, 13.2), Vector3(-0.5, 0.0, 12.8),
		Vector3(7.5, 0.0, 13.4),
		Vector3(-17.8, 0.0, -6.0), Vector3(-18.2, 0.0, 2.5), Vector3(-17.4, 0.0, 9.0),
	]:
		var size := Vector3(7.4, 4.6, 6.0) + Vector3(1.6 * sin(spot.x * 0.7), 1.8 * cos(spot.z * 0.5), 0.0)
		_ridge(spot, size, spot.x * 0.13 + spot.z * 0.07)

	# 墙外的远景岩层，压住地平线
	for spot in [
		Vector3(-30.0, 5.0, -24.0), Vector3(-6.0, 7.0, -32.0), Vector3(16.0, 4.0, -28.0),
		Vector3(34.0, 7.0, -8.0), Vector3(30.0, 5.0, 20.0), Vector3(4.0, 8.0, 34.0),
		Vector3(-24.0, 6.0, 26.0), Vector3(-38.0, 4.0, 4.0),
	]:
		var far := Vector3(18.0, 14.0, 13.0) + Vector3(spot.y * 1.6, spot.y * 1.2, 0.0)
		_sphere(spot, far, Color("#3f5457"), Vector3(0.0, spot.x * 0.05, 0.0))


## 中景岩石：一个主块 + 一块肩石 + 一块亮顶，位置固定，方便重复试玩。
func _rock(at: Vector3, size: Vector3, spin: float) -> void:
	_sphere(at + Vector3.UP * (size.y * 0.40), size, STONE, Vector3(0.0, spin, 0.0))
	_sphere(at + Vector3(size.x * 0.20, size.y * 0.58, -size.z * 0.14),
		size * Vector3(0.62, 0.62, 0.60), STONE_DARK, Vector3(0.0, spin + 0.35, 0.0))
	_sphere(at + Vector3(-size.x * 0.12, size.y * 0.72, size.z * 0.10),
		size * Vector3(0.52, 0.34, 0.48), STONE_LIGHT, Vector3(0.0, spin - 0.2, 0.0))
	_box_collider(size * 0.92, at + Vector3.UP * (size.y * 0.40))


func _ridge(at: Vector3, size: Vector3, spin: float) -> void:
	_sphere(at + Vector3.UP * (size.y * 0.32), size, STONE_DARK, Vector3(0.0, spin, 0.0))
	_sphere(at + Vector3(size.x * 0.24, size.y * 0.62, -size.z * 0.18),
		size * Vector3(0.68, 0.86, 0.66), STONE, Vector3(0.0, spin + 0.5, 0.08))
	_sphere(at + Vector3(-size.x * 0.26, size.y * 0.50, size.z * 0.22),
		size * Vector3(0.54, 0.62, 0.58), STONE_LIGHT, Vector3(0.0, spin - 0.4, -0.08))


# ---------------------------------------------------------------- 搬运场地

func _build_yard() -> void:
	# 中景岩石：其中 (2.2, 6.2) 那块是挑衅视线测试用的遮挡，尺寸保持原样。
	_rock(Vector3(2.2, 0.0, 6.2), Vector3(2.4, 2.2, 2.0), 0.3)
	_rock(Vector3(5.4, 0.0, -3.9), Vector3(1.9, 1.7, 1.7), -0.5)
	_rock(Vector3(-1.6, 0.0, 5.4), Vector3(2.6, 2.4, 2.0), 0.9)
	_rock(Vector3(1.0, 0.0, -8.8), Vector3(3.0, 2.0, 2.0), -0.2)
	_rock(Vector3(-11.0, 0.0, -2.0), Vector3(2.2, 2.6, 2.4), 0.6)

	# 两条搬运路线：青色＝安全绕远，琥珀＝穿过奶龙地盘。
	for index in range(9):
		var t := float(index)
		_box(Vector3(1.0, 0.02, 0.22), Vector3(-7.9 + t * 1.98, 0.055, 4.4 - t * 0.33), CYAN, false, 0.35)
	for index in range(8):
		var t := float(index)
		_box(Vector3(1.0, 0.02, 0.22), Vector3(-6.0 + t * 1.7, 0.055, -6.4 + t * 0.68), AMBER, false, 0.35)

	# 货箱堆：只放在场地边缘，不挡绕行与躲避。
	_crate(Vector3(6.2, 0.0, 5.2), 1.2, 0.10)
	_crate(Vector3(6.9, 0.0, 6.4), 0.9, -0.25)
	_crate(Vector3(5.2, 0.0, 6.5), 0.8, 0.55)
	_crate(Vector3(-8.6, 0.0, 1.2), 1.0, 0.32)
	_crate(Vector3(-7.4, 0.0, 0.6), 0.7, -0.15)

	# 两盏工作灯：给场地一个竖向参照，也让夜景有暖色支点。
	_lamp_post(Vector3(-4.6, 0.0, 7.8))
	_lamp_post(Vector3(7.4, 0.0, -7.6))

	# 场地边界的矮挡块（可跨过，不阻挡视线）
	for spot in [Vector3(-9.6, 0.0, -6.6), Vector3(-9.6, 0.0, 2.2), Vector3(8.6, 0.0, 3.0)]:
		_box(Vector3(0.5, 0.42, 0.5), spot + Vector3.UP * 0.21, TRIM)
		_box(Vector3(0.52, 0.10, 0.52), spot + Vector3.UP * 0.40, AMBER, false, 0.5)


func _crate(at: Vector3, size: float, yaw: float, tilt: float = 0.0) -> void:
	var body := Vector3(size, size, size)
	var node := _box(body, at + Vector3.UP * size * 0.5, CRATE, true, 0.0, Vector3(0.0, yaw, tilt))
	# 包边：让木箱有工业感，而不是一块棕色方块
	for y in [-0.30, 0.30]:
		_child(node, _box_mesh(Vector3(size * 1.02, 0.09, size * 1.02)),
			Vector3(0.0, y * size, 0.0), CRATE_DARK)
	_child(node, _box_mesh(Vector3(0.10, size * 0.55, size * 1.01)), Vector3(0.0, 0.0, 0.0), CRATE_DARK)
	_child(node, _box_mesh(Vector3(size * 0.55, 0.05, 0.01)), Vector3(0.0, 0.12 * size, size * 0.5 + 0.005), PACK)


func _lamp_post(at: Vector3) -> void:
	_cyl(0.12, 0.16, 3.1, at + Vector3.UP * 1.55, TRIM_DARK, Vector3.ZERO, 0.0, 10)
	_box(Vector3(0.46, 0.14, 0.32), at + Vector3.UP * 3.12, TRIM_DARK)
	_box(Vector3(0.30, 0.05, 0.22), at + Vector3.UP * 3.03, Color("#f5eddc"), false, 1.5)
	var light := OmniLight3D.new()
	light.position = at + Vector3.UP * 2.95
	light.light_color = Color("#f5eddc")
	light.light_energy = 0.28
	light.omni_range = 7.0
	add_child(light)


# ---------------------------------------------------------------- 生物窝

func _build_nest() -> void:
	var c := NEST_CENTER
	# 凹陷：深色底盘 + 抬起的边缘石，靠明暗和轮廓读成「被它压出来的坑」。
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 4.1
	floor_mesh.bottom_radius = 3.6
	floor_mesh.height = 0.08
	floor_mesh.radial_segments = 30
	_add(floor_mesh, c + Vector3.UP * 0.03, Color("#3f4f4b"))
	_ring(4.05, 4.32, c + Vector3.UP * 0.09, STONE_DARK)

	for index in range(11):
		var angle := TAU * float(index) / 11.0
		var radius := 4.30 + 0.30 * sin(float(index) * 2.1)
		var tone := STONE if index % 3 else STONE_LIGHT
		_sphere(c + Vector3(cos(angle) * radius, 0.05, sin(angle) * radius),
			Vector3(0.95, 0.30, 0.72), tone, Vector3(0.0, angle, 0.0))

	# 被压扁的货箱：窝后侧两块当背靠，其余平摊开，不堆成杂物山。
	_flattened_crate(c + Vector3(-2.4, 0.0, -2.2), Vector3(1.5, 0.22, 1.1), 0.5)
	_flattened_crate(c + Vector3(1.5, 0.0, -3.2), Vector3(1.7, 0.20, 1.2), -0.3)
	_flattened_crate(c + Vector3(2.9, 0.0, 0.6), Vector3(1.2, 0.18, 0.9), 1.1, false)
	_flattened_crate(c + Vector3(-1.2, 0.0, 2.4), Vector3(1.0, 0.16, 0.8), -0.9, false)

	# 拖拽痕迹：从窝口朝装货口方向拉出去，说明货是被拖进来的。
	for index in range(4):
		var offset := -1.5 + float(index) * 1.05
		_box(Vector3(4.6 + float(index) * 0.6, 0.02, 0.30),
			c + Vector3(2.9 + float(index) * 2.4, 0.075, offset), SCUFF,
			false, 0.0, Vector3(0.0, 0.14 - float(index) * 0.09, 0.0))

	# 散落包装：只撒薄片，不挡路
	for index in range(14):
		var angle := TAU * float(index) / 14.0 + 0.4
		var radius := 1.4 + 2.2 * fmod(float(index) * 0.37, 1.0)
		var spot := c + Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
		var plate := Vector3(0.34 + 0.1 * float(index % 3), 0.02, 0.24)
		_box(plate, spot, PACK, false, 0.0, Vector3(0.0, angle * 1.7, 0.0))

	# 窝后侧挡板：给它一个背靠，同时压住窝区的轮廓
	for index in range(3):
		_box(Vector3(2.2, 0.9, 0.14),
			c + Vector3(-1.6 + float(index) * 1.9, 0.5 + 0.1 * float(index), -4.9 - float(index) * 0.5),
			CRATE_DARK, false, 0.0, Vector3(0.0, 0.3 - float(index) * 0.25, 0.12))


func _flattened_crate(at: Vector3, size: Vector3, yaw: float, solid: bool = true) -> void:
	var node := _box(size, at + Vector3.UP * size.y * 0.5, CRATE, solid, 0.0, Vector3(0.0, yaw, 0.0))
	_child(node, _box_mesh(Vector3(size.x * 1.02, 0.05, size.z * 0.16)), Vector3(0.0, 0.02, 0.0), CRATE_DARK)
	_child(node, _box_mesh(Vector3(size.x * 0.5, 0.01, size.z * 0.3)),
		Vector3(size.x * 0.12, size.y * 0.5 + 0.005, 0.0), PACK)


# ---------------------------------------------------------------- 装货口

func _build_bay_frame() -> void:
	# 门框：两侧 0.7 m 厚的立柱，中间留 5.8 m 开口（判定 AABB 不变）
	for side in [-1.0, 1.0]:
		_box(Vector3(0.70, 3.80, 0.55), Vector3(13.92, 1.90, side * 3.02), HULL, true)
		_box(Vector3(0.78, 0.20, 0.64), Vector3(13.92, 3.82, side * 3.02), TRIM)
		# 缓冲块
		for height in [0.62, 1.74]:
			_cyl(0.17, 0.17, 0.60, Vector3(13.50, height, side * 3.02), Color("#2f3d3a"),
				Vector3(0.0, 0.0, PI * 0.5), 0.0, 12)
		# 门框内侧警示条
		_box(Vector3(0.07, 3.20, 0.16), Vector3(13.53, 1.70, side * 2.66), AMBER, false, 0.55)

	# 上沿横梁 + 收起的卷帘 + 灯带
	_box(Vector3(0.64, 0.46, 6.30), Vector3(13.90, 3.60, 0.0), HULL, true)
	_strip_material = _mat(CYAN, 0.7)
	_box(Vector3(0.10, 0.09, 6.10), Vector3(13.56, 3.42, 0.0), CYAN, false, 0.7, Vector3.ZERO, _strip_material)
	for index in range(4):
		_box(Vector3(0.26, 0.11, 5.70), Vector3(14.26, 2.86 + float(index) * 0.17, 0.0), HULL_DARK)

	# 接货坡道：防滑纹 + 侧导轨（细，不挡走位）
	for index in range(6):
		_box(Vector3(0.44, 0.03, 5.20), Vector3(11.75 + float(index) * 0.42, 0.035, 0.0), Color("#6e807c"))
	for side in [-1.0, 1.0]:
		_box(Vector3(2.4, 0.07, 0.07), Vector3(12.65, 0.72, side * 2.72), TRIM)
		for index in range(3):
			_box(Vector3(0.07, 0.70, 0.07), Vector3(11.55 + float(index) * 1.05, 0.35, side * 2.72), TRIM)

	# 夹持机构：装货成功时会向内一夹再复位（on_loaded）
	for index in range(2):
		var side := -1.0 if index == 0 else 1.0
		var pivot := Node3D.new()
		pivot.position = Vector3(13.30, 3.16, side * 2.10)
		add_child(pivot)
		_child(pivot, _box_mesh(Vector3(0.17, 0.95, 0.17)), Vector3(0.0, -0.48, 0.0), TRIM)
		_child(pivot, _box_mesh(Vector3(0.13, 0.16, 0.34)), Vector3(0.0, -0.98, -side * 0.06), AMBER)
		_clamp_arms.append(pivot)


# ---------------------------------------------------------------- 灯光

func _build_lights() -> void:
	# 舱口工作灯：暖色，把门框和坡道从地面里拉出来
	_bay_light = OmniLight3D.new()
	_bay_light.position = Vector3(12.4, 3.10, 0.0)
	_bay_light.light_color = Color("#ffe3b8")
	_bay_light.light_energy = 0.30
	_bay_light.omni_range = 9.0
	add_child(_bay_light)

	# 窝区冷补光：让奶龙轮廓从深色地面里分出来
	var nest_fill := OmniLight3D.new()
	nest_fill.position = NEST_CENTER + Vector3.UP * 4.4
	nest_fill.light_color = Color("#cfe9e4")
	nest_fill.light_energy = 0.22
	nest_fill.omni_range = 10.0
	add_child(nest_fill)

	# 落地信标（保留原场景的竖向参照）
	var beacon := CylinderMesh.new()
	beacon.top_radius = 0.18
	beacon.bottom_radius = 0.50
	beacon.height = 2.6
	_add(beacon, Vector3(-14.0, 1.3, -11.0), TRIM)
	var beacon_light := OmniLight3D.new()
	beacon_light.position = Vector3(-14.0, 2.9, -11.0)
	beacon_light.light_color = CYAN
	beacon_light.light_energy = 1.1
	beacon_light.omni_range = 7.0
	add_child(beacon_light)


# ---------------------------------------------------------------- 基础工具

func _mat(color: Color, emission: float = 0.0, roughness: float = 0.93) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.03
	material.metallic_specular = 0.20
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _add(mesh: Mesh, at: Vector3, color: Color, emission: float = 0.0,
		rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE,
		material: StandardMaterial3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rot
	instance.scale = scale
	instance.material_override = material if material != null else _mat(color, emission)
	add_child(instance)
	return instance


func _child(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _mat(color, emission)
	parent.add_child(instance)
	return instance


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _box(size: Vector3, at: Vector3, color: Color, solid: bool = false,
		emission: float = 0.0, rot: Vector3 = Vector3.ZERO,
		material: StandardMaterial3D = null) -> MeshInstance3D:
	var node := _add(_box_mesh(size), at, color, emission, rot, Vector3.ONE, material)
	if solid:
		_box_collider(size, at, rot)
	return node


func _sphere(at: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 7
	return _add(mesh, at, color, 0.0, rot, size)


func _cyl(r_top: float, r_bottom: float, height: float, at: Vector3, color: Color,
		rot: Vector3 = Vector3.ZERO, emission: float = 0.0, segments: int = 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = height
	mesh.radial_segments = segments
	return _add(mesh, at, color, emission, rot)


func _ring(inner: float, outer: float, at: Vector3, color: Color,
		rot: Vector3 = Vector3.ZERO, emission: float = 0.0) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 28
	mesh.ring_segments = 8
	return _add(mesh, at, color, emission, rot)


func _box_collider(size: Vector3, at: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation = rot
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _solid_only(size: Vector3, at: Vector3) -> void:
	_box_collider(size, at)
