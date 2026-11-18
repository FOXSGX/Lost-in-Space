extends Node3D
class_name NailongEnvironment

## 奶龙星环境美术升级（2026-11-18）
##
## 只负责「看得见的东西」：地面分区、装货口框架与坡道、窝区痕迹、岩石轮廓、灯光。
## 玩法规则、控制器参数、装货判定 AABB（collector.gd 的 CATCH_MIN/MAX）都不在这里改。
##
## 方法来源：ART-SAMPLE-002 的分层金属/岩石材质与“远看构图、中看结构、近看工艺”。
## 材质 shader 在 `shaders/aqs2_metal.gdshader` / `aqs2_rock.gdshader`，
## 不带 2K 贴图与顶点色烘焙；运行时几何没有 UV，所以金属材质 `vertex_mask_valid = false`。
##
## 关键约束：
## - 四面边界墙碰撞位置、尺寸与旧版完全一致。
## - 装货口立柱/横梁碰撞位置与旧版完全一致；新增装饰只向门口外侧长，不进入球路。
## - 地面装饰全部无碰撞、厚度 ≤ 2 cm，不改变球滚动。

const HULL_LIGHT := Color("#93a39f")
const HULL := Color("#5f6f6a")
const HULL_DARK := Color("#52625e")
const TRIM := Color("#375967")
const TRIM_DARK := Color("#263c46")
const GLASS := Color("#8fe3ff")
const AMBER := Color("#ffb347")
const CYAN := Color("#3fd8ff")
const INTAKE := Color("#0d1a20")

const GROUND := Color("#7f928b")
const GROUND_WARM := Color("#8b9c91")
const GROUND_COOL := Color("#869991")
const SCUFF := Color("#66766f")
const STONE := Color("#b0beb8")
const STONE_LIGHT := Color("#c2cec8")
const STONE_DARK := Color("#97a8a2")
const CRATE := Color("#c09468")
const CRATE_DARK := Color("#8f6640")
const PACK := Color("#c9bda6")

const NEST_CENTER := Vector3(1.0, 0.0, -2.5)

var kit: GuluArtKit
var mat_ground: ShaderMaterial
var mat_ground_warm: ShaderMaterial
var mat_ground_cool: ShaderMaterial
var mat_concrete: ShaderMaterial
var mat_hull: ShaderMaterial
var mat_hull_light: ShaderMaterial
var mat_hull_dark: ShaderMaterial
var mat_trim: ShaderMaterial
var mat_trim_dark: ShaderMaterial
var mat_bare: ShaderMaterial
var mat_dark_steel: ShaderMaterial
var mat_crate: ShaderMaterial
var mat_crate_dark: ShaderMaterial
var mat_pack: ShaderMaterial
var mat_rock_a: ShaderMaterial
var mat_rock_b: ShaderMaterial
var mat_rock_c: ShaderMaterial
var mat_amber: StandardMaterial3D
var mat_cyan: StandardMaterial3D
var mat_intake_slot: ShaderMaterial
var mat_bay_strip: StandardMaterial3D
var mat_rubber: StandardMaterial3D
var mat_lens: StandardMaterial3D
var mat_glass: StandardMaterial3D

var _flash := 0.0
var _clamp_arms: Array[Node3D] = []
var _strip_material: StandardMaterial3D
var _bay_light: OmniLight3D


func _ready() -> void:
	_build_materials()
	_build_ground()
	_build_perimeter()
	_build_yard()
	_build_nest()
	_build_bay_frame()
	_build_lights()
	set_process(true)


func _build_materials() -> void:
	kit = GuluArtKit.new()
	mat_ground = kit.concrete(GROUND, 0.90, 11.0)
	mat_ground_warm = kit.concrete(GROUND_WARM, 0.90, 12.0)
	mat_ground_cool = kit.concrete(GROUND_COOL, 0.90, 13.0)
	mat_concrete = kit.concrete(Color("#6f7f78"), 0.92, 14.0)
	mat_hull = kit.paint(HULL, 0.72, 0.0, 0.9, 21.0)
	mat_hull.set_shader_parameter("specular_level", 0.08)
	mat_hull.set_shader_parameter("edge_rim", 0.05)
	mat_hull_light = kit.paint(HULL_LIGHT, 0.68, 0.0, 0.75, 22.0)
	mat_hull_light.set_shader_parameter("specular_level", 0.08)
	mat_hull_light.set_shader_parameter("edge_rim", 0.05)
	mat_hull_dark = kit.paint(HULL_DARK, 0.54, 0.16, 1.0, 23.0)
	mat_trim = kit.paint(TRIM, 0.40, 0.22, 0.8, 24.0)
	mat_trim_dark = kit.dark_metal(TRIM_DARK, 0.50, 25.0)
	mat_bare = kit.bare_metal(Color("#8b979b"), 0.32, 26.0)
	mat_dark_steel = kit.dark_metal(Color("#2f3d3a"), 0.56, 27.0)
	mat_intake_slot = kit.dark_metal(INTAKE, 0.66, 27.5)
	mat_crate = kit.paint(CRATE, 0.58, 0.08, 1.0, 28.0)
	mat_crate_dark = kit.paint(CRATE_DARK, 0.62, 0.12, 1.0, 29.0)
	mat_pack = kit.paint(PACK, 0.72, 0.0, 0.5, 30.0)
	mat_rock_a = kit.rock(STONE, STONE_DARK, STONE_LIGHT, 0.30, 0.55, 31.0)
	mat_rock_b = kit.rock(Color("#7f948f"), Color("#5d716d"), STONE, 0.42, 0.62, 32.0)
	mat_rock_c = kit.rock(Color("#6f827e"), Color("#4f625f"), Color("#93a6a0"), 0.26, 0.48, 33.0)
	mat_amber = kit.emissive(AMBER, 0.45, 0.45)
	mat_cyan = kit.emissive(CYAN, 0.55, 0.45)
	mat_bay_strip = kit.emissive(AMBER, 0.70, 0.42)
	_strip_material = mat_bay_strip
	mat_rubber = kit.rubber(Color("#1b2423"))
	mat_lens = kit.emissive(Color("#fff0d2"), 0.55, 0.30)
	mat_glass = kit.emissive(CYAN, 0.55, 0.20, 0.1)


# ---------------------------------------------------------------- 装货反馈

## 装货成功：夹臂向内一夹再复位，门框灯带同步闪一下（机械 + 灯光）。
func on_loaded(_total: int) -> void:
	_flash = 1.0
	if _strip_material != null:
		_strip_material.emission_energy_multiplier = 3.0
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
		_strip_material.emission_energy_multiplier = 0.70 + _flash * 2.6
	if _bay_light != null:
		_bay_light.light_energy = 0.30 + _flash * 0.60


# ---------------------------------------------------------------- 地面

func _build_ground() -> void:
	# 40×30 的场地底板；碰撞与旧版完全一致。
	_box(Vector3(40.0, 0.5, 30.0), Vector3(0.0, -0.25, 0.0), GROUND, true, 0.0, Vector3.ZERO, mat_ground)

	# 大块混凝土板：只分 4 块，接缝少而长；不铺小砖。
	_box(Vector3(16.0, 0.012, 10.0), Vector3(-3.0, 0.008, 4.2), GROUND_WARM, false, 0.0, Vector3.ZERO, mat_ground_warm)
	_box(Vector3(9.0, 0.012, 11.0), Vector3(5.0, 0.009, -1.0), GROUND_COOL, false, 0.0, Vector3.ZERO, mat_ground_cool)
	_box(Vector3(8.0, 0.012, 9.0), Vector3(-13.0, 0.010, 4.0), Color("#53655f"), false, 0.0, Vector3.ZERO, mat_ground)
	_box(Vector3(10.0, 0.012, 7.0), Vector3(-4.0, 0.011, -7.4), Color("#4a5c58"), false, 0.0, Vector3.ZERO, mat_ground_cool)

	# 板缝：宽 3.5 cm、厚 8 mm，无碰撞；只出现在大块分界，不切碎踢球区。
	for x in [-16.0, -8.0, 0.0, 8.0]:
		_box(Vector3(0.035, 0.008, 29.2), Vector3(x, 0.014, 0.0), SCUFF, false)
	for z in [-7.5, 7.5]:
		_box(Vector3(39.2, 0.008, 0.035), Vector3(0.0, 0.014, z), SCUFF, false)

	# 常走路线磨痕：宽而低对比，不做密集条纹。
	for index in range(5):
		var t := float(index)
		_box(Vector3(2.6, 0.006, 0.42), Vector3(-8.6 + t * 3.2, 0.018, 4.3 - t * 0.30),
			SCUFF, false, 0.0, Vector3(0.0, 0.10, 0.0))

	# 停机坪：压深圆盘 + 金属边圈 + 四块检修盖板。
	var pad := CylinderMesh.new()
	pad.top_radius = 4.55
	pad.bottom_radius = 4.42
	pad.height = 0.035
	pad.radial_segments = 48
	_add(pad, Vector3(6.6, 0.018, 0.0), Color.WHITE, 0.0, Vector3.ZERO, Vector3.ONE, mat_bare)
	var pad_inner := CylinderMesh.new()
	pad_inner.top_radius = 3.30
	pad_inner.bottom_radius = 3.22
	pad_inner.height = 0.038
	pad_inner.radial_segments = 40
	_add(pad_inner, Vector3(6.6, 0.022, 0.0), Color.WHITE, 0.0, Vector3.ZERO, Vector3.ONE, mat_concrete)
	_ring(4.30, 4.42, Vector3(6.6, 0.038, 0.0), WHITE, Vector3.ZERO, 0.0, mat_trim)
	for index in range(4):
		var ang := TAU * float(index) / 4.0 + PI * 0.25
		var at := Vector3(6.6 + cos(ang) * 3.95, 0.040, sin(ang) * 3.95)
		_box(Vector3(0.55, 0.018, 0.42), at, Color.WHITE, false, 0.0, Vector3(0.0, -ang, 0.0), mat_dark_steel)
		_bolt(at + Vector3.UP * 0.012, ang + PI * 0.5, 0.045)

	# 门前工作区：两条暗金属导引条 + 五枚小箭头；不发光、不挡球。
	for side in [-1.0, 1.0]:
		_box(Vector3(9.6, 0.006, 0.09), Vector3(6.2, 0.020, side * 2.58), Color.WHITE,
			false, 0.0, Vector3.ZERO, mat_dark_steel)
		for index in range(3):
			var x := 8.8 + float(index) * 0.85
			_box(Vector3(0.46, 0.006, 0.08), Vector3(x, 0.022, side * 1.90), AMBER,
				false, 0.0, Vector3(0.0, side * 0.55, 0.0), mat_amber)

	# 门前磨损：两片被踩暗的区域，形状不规整但边缘柔和。
	_box(Vector3(3.6, 0.004, 1.7), Vector3(10.2, 0.017, 1.4), SCUFF, false, 0.0, Vector3(0.0, 0.12, 0.0))
	_box(Vector3(3.0, 0.004, 1.4), Vector3(9.8, 0.017, -1.7), SCUFF, false, 0.0, Vector3(0.0, -0.18, 0.0))


# ---------------------------------------------------------------- 边界与地形

func _build_perimeter() -> void:
	# 碰撞仍是原来的四面隐形墙（位置/尺寸完全一致）。
	_solid_only(Vector3(40.0, 6.0, 0.8), Vector3(0.0, 3.0, -15.0))
	_solid_only(Vector3(40.0, 6.0, 0.8), Vector3(0.0, 3.0, 15.0))
	_solid_only(Vector3(0.8, 6.0, 30.0), Vector3(-20.0, 3.0, 0.0))
	_solid_only(Vector3(0.8, 6.0, 30.0), Vector3(20.0, 3.0, 0.0))

	# 土坡底座：低、缓，不挡视线；上方交给岩脊。
	_box(Vector3(39.4, 0.9, 2.5), Vector3(0.0, 0.42, -14.0), Color.WHITE, false, 0.0, Vector3.ZERO, mat_ground_cool)
	_box(Vector3(39.4, 0.7, 2.3), Vector3(0.0, 0.32, 14.0), Color.WHITE, false, 0.0, Vector3.ZERO, mat_ground_warm)
	_box(Vector3(2.5, 0.8, 29.0), Vector3(-19.2, 0.36, 0.0), Color.WHITE, false, 0.0, Vector3.ZERO, mat_ground_cool)

	# 北/南/西三面的大轮廓岩脊：主块 + 肩石 + 亮顶，低多边形、分层。
	for spot in [
		Vector3(-17.5, 0.0, -12.4), Vector3(-10.0, 0.0, -13.4), Vector3(-2.0, 0.0, -13.0),
		Vector3(6.5, 0.0, -13.6), Vector3(14.0, 0.0, -12.8),
		Vector3(-16.5, 0.0, 12.6), Vector3(-8.5, 0.0, 13.2), Vector3(-0.5, 0.0, 12.8),
		Vector3(7.5, 0.0, 13.4),
		Vector3(-17.8, 0.0, -6.0), Vector3(-18.2, 0.0, 2.5), Vector3(-17.4, 0.0, 9.0),
	]:
		var size := Vector3(7.4, 4.6, 6.0) + Vector3(1.6 * sin(spot.x * 0.7), 1.8 * cos(spot.z * 0.5), 0.0)
		_ridge(spot, size, spot.x * 0.13 + spot.z * 0.07)

	# 墙外远景岩层：只做剪影和层次，不堆细节。
	for spot in [
		Vector3(-30.0, 0.0, -24.0), Vector3(-6.0, 0.0, -32.0), Vector3(16.0, 0.0, -28.0),
		Vector3(34.0, 0.0, -8.0), Vector3(30.0, 0.0, 20.0), Vector3(4.0, 0.0, 34.0),
		Vector3(-24.0, 0.0, 26.0), Vector3(-38.0, 0.0, 4.0),
	]:
		var far := Vector3(18.0, 14.0, 13.0) + Vector3(spot.y * 1.6, spot.y * 1.2, 0.0)
		var node := MeshInstance3D.new()
		node.mesh = kit.rock_mesh(spot.x * 0.17 + spot.z * 0.11, far, 1)
		node.position = spot
		node.rotation.y = spot.x * 0.05
		node.material_override = mat_rock_c
		add_child(node)


## 中景岩石：主块 + 肩石 + 亮顶；碰撞尺寸/位置与旧版一致。
func _rock(at: Vector3, size: Vector3, spin: float) -> void:
	_rock_mesh(at, size * Vector3(1.0, 1.15, 1.0), spin, mat_rock_a)
	_rock_mesh(at + Vector3(size.x * 0.22, 0.0, -size.z * 0.14),
		size * Vector3(0.62, 0.78, 0.60), spin + 0.35, mat_rock_b)
	_rock_mesh(at + Vector3(-size.x * 0.12, 0.0, size.z * 0.10),
		size * Vector3(0.52, 0.44, 0.48), spin - 0.2, mat_rock_c)
	_box_collider(size * 0.92, at + Vector3.UP * (size.y * 0.40))


func _ridge(at: Vector3, size: Vector3, spin: float) -> void:
	_rock_mesh(at, size * Vector3(1.0, 1.05, 1.0), spin, mat_rock_c)
	_rock_mesh(at + Vector3(size.x * 0.24, 0.0, -size.z * 0.18),
		size * Vector3(0.68, 0.86, 0.66), spin + 0.5, mat_rock_b)
	_rock_mesh(at + Vector3(-size.x * 0.26, 0.0, size.z * 0.22),
		size * Vector3(0.54, 0.62, 0.58), spin - 0.4, mat_rock_a)


func _rock_mesh(at: Vector3, size: Vector3, spin: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = kit.rock_mesh(at.x * 0.23 + at.z * 0.19 + spin, size, 2)
	node.position = at
	node.rotation.y = spin
	node.material_override = material
	add_child(node)
	return node


# ---------------------------------------------------------------- 搬运场地

func _build_yard() -> void:
	# 场地现在要踢球：中央完全留空，道具全部移到边线外。
	_rock(Vector3(-12.2, 0.0, -2.0), Vector3(2.2, 2.6, 2.4), 0.6)
	_rock(Vector3(-13.6, 0.0, 9.8), Vector3(2.0, 2.2, 1.8), -0.4)
	_rock(Vector3(2.4, 0.0, 13.4), Vector3(2.4, 2.0, 1.8), 0.9)

	# 边线货箱堆：不进场，球撞上会弹回场内（有碰撞）。
	_crate(Vector3(-5.6, 0.0, 10.6), 1.35, 0.12)
	_crate(Vector3(-6.1, 0.0, 11.8), 1.05, -0.35)
	_crate(Vector3(-5.7, 1.35, 10.7), 0.95, 0.55)
	_crate(Vector3(6.6, 0.0, 10.2), 1.2, 0.40)
	_crate(Vector3(7.4, 0.0, 11.1), 0.9, -0.20)
	_crate(Vector3(-9.0, 0.0, -12.2), 1.0, 0.32)

	# 靠边线的装货门架：只做轮廓与承力，不进入可玩区。
	_cargo_gantry(Vector3(-9.2, 0.0, 12.1))

	# 两盏工作灯：给场地一个竖向参照，也让夜景有暖色支点。
	_lamp_post(Vector3(-9.4, 0.0, 8.6))
	_lamp_post(Vector3(6.2, 0.0, -9.4))

	# 场地标线：中圈 + 门前弧，细、暗、不发光，只用来读距离。
	_ring(3.80, 3.95, Vector3(-2.0, 0.026, 1.2), TRIM, Vector3.ZERO, 0.0, mat_trim)
	_ring(5.60, 5.74, Vector3(11.6, 0.026, 0.0), TRIM, Vector3.ZERO, 0.0, mat_trim)
	_box(Vector3(0.12, 0.016, 21.0), Vector3(-2.0, 0.026, 0.0), TRIM, false, 0.0, Vector3.ZERO, mat_trim)


func _crate(at: Vector3, size: float, yaw: float, tilt: float = 0.0) -> void:
	var body := Vector3(size, size, size)
	var node := _box(body, at + Vector3.UP * size * 0.5, CRATE, true, 0.0, Vector3(0.0, yaw, tilt), mat_crate)
	# 上下包边 + 竖框：读成“有装配关系的货箱”，不是一块棕色方块。
	for y in [-0.40, 0.40]:
		_child(node, _bevel(Vector3(size * 1.03, 0.10, size * 1.03), 0.015),
			Vector3(0.0, y * size, 0.0), CRATE_DARK, mat_crate_dark)
	for x in [-0.40, 0.40]:
		for z in [-0.40, 0.40]:
			_child(node, _bevel(Vector3(0.09, size * 0.92, 0.09), 0.012),
				Vector3(x * size, 0.0, z * size), CRATE_DARK, mat_crate_dark)
	# 侧面检修板 + 标签
	_child(node, _bevel(Vector3(size * 0.52, size * 0.34, 0.02), 0.008),
		Vector3(0.0, 0.04 * size, size * 0.505), HULL_LIGHT, mat_pack)
	_child(node, _bevel(Vector3(size * 0.24, size * 0.10, 0.012), 0.004),
		Vector3(-0.18 * size, 0.04 * size, size * 0.518), AMBER, mat_amber)


func _cargo_gantry(at: Vector3) -> void:
	# 两根立柱 + 一根横梁 + 斜撑：在边线外形成“装货场”的工业轮廓。
	for side in [-1.0, 1.0]:
		_box(Vector3(0.24, 3.2, 0.24), at + Vector3(0.0, 1.6, side * 1.05), Color.WHITE, false, 0.0, Vector3.ZERO, mat_trim_dark)
		_box(Vector3(0.55, 0.12, 0.55), at + Vector3(0.0, 0.06, side * 1.05), Color.WHITE, false, 0.0, Vector3.ZERO, mat_bare)
	_box(Vector3(0.28, 0.28, 2.5), at + Vector3.UP * 3.15, Color.WHITE, false, 0.0, Vector3.ZERO, mat_trim)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.10, 0.10, 1.35), at + Vector3(0.0, 2.72, side * 0.50), Color.WHITE,
			false, 0.0, Vector3(side * 0.62, 0.0, 0.0), mat_trim_dark)
	# 顶部小警示灯，静态，不做闪烁系统。
	_cyl(0.10, 0.12, 0.16, at + Vector3(0.0, 3.36, 0.0), AMBER, Vector3.ZERO, 0.55, 12, mat_amber)


func _lamp_post(at: Vector3) -> void:
	_cyl(0.11, 0.15, 3.1, at + Vector3.UP * 1.55, TRIM_DARK, Vector3.ZERO, 0.0, 12, mat_trim_dark)
	_box(Vector3(0.20, 0.10, 0.20), at + Vector3.UP * 0.16, Color.WHITE, false, 0.0, Vector3.ZERO, mat_bare)
	_box(Vector3(0.52, 0.16, 0.34), at + Vector3.UP * 3.14, Color.WHITE, false, 0.0, Vector3.ZERO, mat_trim)
	_box(Vector3(0.34, 0.05, 0.24), at + Vector3.UP * 3.03, Color.WHITE, false, 0.0, Vector3.ZERO, mat_lens)
	var light := OmniLight3D.new()
	light.position = at + Vector3.UP * 2.95
	light.light_color = Color("#ffe0b0")
	light.light_energy = 0.42
	light.omni_range = 7.5
	add_child(light)


# ---------------------------------------------------------------- 生物窝

func _build_nest() -> void:
	var c := NEST_CENTER
	# 凹陷：深色底盘 + 抬起的边缘石，靠明暗和轮廓读成「被它压出来的坑」。
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 4.1
	floor_mesh.bottom_radius = 3.6
	floor_mesh.height = 0.08
	floor_mesh.radial_segments = 36
	_add(floor_mesh, c + Vector3.UP * 0.03, Color.WHITE, 0.0, Vector3.ZERO, Vector3.ONE, mat_dark_steel)
	_ring(4.05, 4.32, c + Vector3.UP * 0.09, STONE_DARK, Vector3.ZERO, 0.0, mat_rock_b)

	for index in range(11):
		var angle := TAU * float(index) / 11.0
		var radius := 4.30 + 0.30 * sin(float(index) * 2.1)
		var tone := mat_rock_a if index % 3 else mat_rock_b
		_rock_mesh(c + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius),
			Vector3(0.95, 0.34, 0.72), angle, tone)

	# 被压扁的货箱：窝后侧两块当背靠，其余平摊开，不堆成杂物山。
	_flattened_crate(c + Vector3(-2.4, 0.0, -2.2), Vector3(1.5, 0.22, 1.1), 0.5)
	_flattened_crate(c + Vector3(1.5, 0.0, -3.2), Vector3(1.7, 0.20, 1.2), -0.3)
	_flattened_crate(c + Vector3(2.9, 0.0, 0.6), Vector3(1.2, 0.18, 0.9), 1.1, false)
	_flattened_crate(c + Vector3(-1.2, 0.0, 2.4), Vector3(1.0, 0.16, 0.8), -0.9, false)

	# 窝里躺着几罐被压瘪的燃料：证明它真的抢过东西。
	_crushed_can(c + Vector3(-1.4, 0.0, 0.9), 0.7)
	_crushed_can(c + Vector3(-0.6, 0.0, 1.7), -0.4)
	_crushed_can(c + Vector3(1.9, 0.0, -0.6), 1.4)

	# 拖拽痕迹：从窝口朝装货口方向拉出去。
	for index in range(4):
		var offset := -1.5 + float(index) * 1.05
		_box(Vector3(4.6 + float(index) * 0.6, 0.006, 0.30),
			c + Vector3(2.9 + float(index) * 2.4, 0.075, offset), SCUFF,
			false, 0.0, Vector3(0.0, 0.14 - float(index) * 0.09, 0.0))

	# 散落包装：只撒薄片，不挡路。
	for index in range(14):
		var angle := TAU * float(index) / 14.0 + 0.4
		var radius := 1.4 + 2.2 * fmod(float(index) * 0.37, 1.0)
		var spot := c + Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
		var plate := Vector3(0.34 + 0.1 * float(index % 3), 0.02, 0.24)
		_box(plate, spot, PACK, false, 0.0, Vector3(0.0, angle * 1.7, 0.0), mat_pack)

	# 窝后侧挡板：给它一个背靠，同时压住窝区的轮廓。
	for index in range(3):
		_box(Vector3(2.2, 0.9, 0.14),
			c + Vector3(-1.6 + float(index) * 1.9, 0.5 + 0.1 * float(index), -4.9 - float(index) * 0.5),
			CRATE_DARK, false, 0.0, Vector3(0.0, 0.3 - float(index) * 0.25, 0.12), mat_crate_dark)


func _flattened_crate(at: Vector3, size: Vector3, yaw: float, solid: bool = true) -> void:
	var node := _box(size, at + Vector3.UP * size.y * 0.5, CRATE, solid, 0.0, Vector3(0.0, yaw, 0.0), mat_crate)
	_child(node, _bevel(Vector3(size.x * 1.02, 0.05, size.z * 0.16), 0.01), Vector3(0.0, 0.02, 0.0), CRATE_DARK, mat_crate_dark)
	_child(node, _bevel(Vector3(size.x * 0.5, 0.01, size.z * 0.3), 0.004),
		Vector3(size.x * 0.12, size.y * 0.5 + 0.005, 0.0), PACK, mat_pack)


## 窝里被压瘪的燃料罐：只有形体和一块能量窗，不抢眼。
func _crushed_can(at: Vector3, yaw: float) -> void:
	var node := _box(Vector3(0.46, 0.15, 0.34), at + Vector3.UP * 0.075, AMBER, false, 0.0, Vector3(0.0, yaw, 0.0), mat_amber)
	_child(node, _bevel(Vector3(0.48, 0.03, 0.36), 0.006), Vector3(0.0, 0.085, 0.0), TRIM, mat_trim)
	_child(node, _bevel(Vector3(0.26, 0.02, 0.02), 0.004), Vector3(0.0, 0.02, 0.17), CYAN, mat_cyan)


# ---------------------------------------------------------------- 装货口

func _build_bay_frame() -> void:
	# 门框碰撞：与旧版逐值一致（立柱 0.70×3.80×0.55 @ x13.92 z±3.02；横梁 0.64×0.46×6.30 @ y3.60）。
	for side in [-1.0, 1.0]:
		_box(Vector3(0.70, 3.80, 0.55), Vector3(13.92, 1.90, side * 3.02), HULL, true, 0.0, Vector3.ZERO, mat_hull)
		_box(Vector3(0.74, 0.18, 0.60), Vector3(13.90, 3.82, side * 3.02), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
		# 立柱外侧的检修面板 + 四颗螺栓，说明“这块可以拆”。
		_panel(Vector3(0.02, 1.05, 0.44), Vector3(13.555, 2.25, side * 3.02), TRIM, 0.0)
		for y in [1.82, 2.68]:
			_bolt(Vector3(13.535, y, side * 3.02 - 0.17), 0.0, 0.035)
			_bolt(Vector3(13.535, y, side * 3.02 + 0.17), 0.0, 0.035)
		# 底部防撞块（橡胶），贴地，不进入门洞。
		_box(Vector3(0.20, 0.55, 0.28), Vector3(13.53, 0.28, side * 3.24), Color.WHITE, false, 0.0, Vector3.ZERO, mat_rubber)
		# 竖向缓冲条：在门洞外侧 z=±3.38，球路在 ±2.4，不碰。
		var bumper := CapsuleMesh.new()
		bumper.radius = 0.07
		bumper.height = 2.60
		bumper.radial_segments = 12
		bumper.rings = 4
		_add(bumper, Vector3(13.24, 1.62, side * 3.40), Color.WHITE, 0.0, Vector3.ZERO, Vector3.ONE, mat_rubber)
	# 横梁
	_box(Vector3(0.64, 0.46, 6.30), Vector3(13.90, 3.60, 0.0), HULL, true, 0.0, Vector3.ZERO, mat_hull)
	# 横梁与船体之间的连接座（承力路径）
	_box(Vector3(0.50, 0.92, 4.20), Vector3(14.15, 4.10, 0.0), Color.WHITE, false, 0.0, Vector3.ZERO, mat_hull_light)
	for z in [-2.0, 0.0, 2.0]:
		_box(Vector3(0.58, 0.10, 0.26), Vector3(13.98, 3.92, z), TRIM, false, 0.0, Vector3.ZERO, mat_trim)

	# 圆角门拱：内沿严格等于旧门口（5.34 m 宽 × 3.37 m 高），只向外长。
	var arch := MeshInstance3D.new()
	arch.mesh = kit.arch(7.00, 4.05, 5.34, 3.37, 0.38, 0.42, 0.16)
	arch.position = Vector3(13.30, 0.0, 0.0)
	arch.material_override = mat_hull_light
	add_child(arch)
	# 拱背与立柱/横梁之间的垫块，避免“悬浮面板”。
	for z in [-3.24, -2.92, 2.92, 3.24]:
		_box(Vector3(0.30, 0.16, 0.16), Vector3(13.52, 3.60, z), Color.WHITE, false, 0.0, Vector3.ZERO, mat_trim_dark)
	for z in [-3.24, 3.24]:
		for y in [0.60, 1.60, 2.60]:
			_box(Vector3(0.26, 0.14, 0.14), Vector3(13.52, y, z), Color.WHITE, false, 0.0, Vector3.ZERO, mat_trim_dark)

	# 内沿深色密封条：内尺寸与门洞一致，只贴在拱的前表面，不缩口。
	var liner := MeshInstance3D.new()
	liner.mesh = kit.arch(5.48, 3.49, 5.34, 3.37, 0.055, 0.10, 0.05)
	liner.position = Vector3(13.105, 0.0, 0.0)
	liner.material_override = mat_rubber
	add_child(liner)

	# 门拱上的六角螺栓：只在需要装配的节点出现。
	for y in [0.55, 1.55, 2.55]:
		for side in [-1.0, 1.0]:
			_bolt(Vector3(13.085, y, side * 3.26), 0.0, 0.048)
	for z in [-2.35, -1.18, 0.0, 1.18, 2.35]:
		_bolt(Vector3(13.085, 3.965, z), 0.0, 0.042)

	# 顶檐：向玩家方向出挑 0.55 m，底面装两盏工作灯。
	_box(Vector3(0.62, 0.18, 6.55), Vector3(13.05, 3.50, 0.0), Color.WHITE, false, 0.0, Vector3.ZERO, mat_hull_light)
	var lip := CylinderMesh.new()
	lip.top_radius = 0.085
	lip.bottom_radius = 0.085
	lip.height = 6.55
	lip.radial_segments = 16
	_add(lip, Vector3(12.75, 3.50, 0.0), Color.WHITE, 0.0, Vector3(PI * 0.5, 0.0, 0.0), Vector3.ONE, mat_bare)
	for side in [-1.0, 1.0]:
		_work_lamp(Vector3(13.02, 3.38, side * 1.86))

	# 状态灯箱：三格指示灯放在横梁正面，背板做凹槽。
	_box(Vector3(0.07, 0.56, 2.75), Vector3(13.035, 3.66, 0.0), INTAKE, false, 0.0, Vector3.ZERO, mat_dark_steel)
	_box(Vector3(0.03, 0.44, 2.55), Vector3(12.995, 3.66, 0.0), Color.WHITE, false, 0.0, Vector3.ZERO, mat_trim_dark)
	for index in range(3):
		var z := -0.9 + float(index) * 0.9
		_box(Vector3(0.02, 0.32, 0.32), Vector3(12.985, 3.66, z), INTAKE, false, 0.0, Vector3.ZERO, mat_intake_slot)
		_box(Vector3(0.015, 0.36, 0.36), Vector3(12.995, 3.66, z), TRIM, false, 0.0, Vector3.ZERO, mat_trim)

	# 门框内侧警示条：贴在立柱内侧面，宽 7 cm，球门内沿仍为 z=±2.67。
	for side in [-1.0, 1.0]:
		_box(Vector3(0.045, 2.95, 0.075), Vector3(13.555, 1.55, side * 2.705), AMBER, false, 0.0, Vector3.ZERO, mat_bay_strip)

	# 侧向导轮/线缆：从门框下角沿地面走向平台，说明供电与检修。
	for side in [-1.0, 1.0]:
		_cyl(0.055, 0.055, 2.2, Vector3(13.30, 0.24, side * 3.52), TRIM_DARK,
			Vector3(0.0, 0.0, PI * 0.5), 0.0, 10, mat_trim_dark)
		for x in [12.55, 13.15]:
			_box(Vector3(0.10, 0.22, 0.16), Vector3(x, 0.20, side * 3.52), Color.WHITE, false, 0.0, Vector3.ZERO, mat_bare)

	# 接货平台内的金属底板 + 入口压条（无碰撞，保持球直接滚入）。
	_box(Vector3(4.10, 0.02, 5.20), Vector3(13.55, 0.020, 0.0), Color.WHITE, false, 0.0, Vector3.ZERO, mat_bare)
	_box(Vector3(0.06, 0.03, 5.20), Vector3(11.52, 0.030, 0.0), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
	for side in [-1.0, 1.0]:
		_box(Vector3(2.4, 0.07, 0.07), Vector3(12.65, 0.72, side * 2.72), TRIM, false, 0.0, Vector3.ZERO, mat_trim)
		for index in range(3):
			_box(Vector3(0.07, 0.70, 0.07), Vector3(11.55 + float(index) * 1.05, 0.35, side * 2.72), TRIM, false, 0.0, Vector3.ZERO, mat_trim)

	# 夹持机构：装货成功时向内一夹再复位（on_loaded）。
	for index in range(2):
		var side := -1.0 if index == 0 else 1.0
		var pivot := Node3D.new()
		pivot.position = Vector3(13.30, 3.16, side * 2.10)
		add_child(pivot)
		_child(pivot, _bevel(Vector3(0.17, 0.95, 0.17), 0.02), Vector3(0.0, -0.48, 0.0), TRIM, mat_trim)
		_child(pivot, _bevel(Vector3(0.13, 0.16, 0.34), 0.015), Vector3(0.0, -0.98, -side * 0.06), AMBER, mat_amber)
		_clamp_arms.append(pivot)


func _panel(size: Vector3, at: Vector3, color: Color, yaw: float) -> void:
	_box(size, at, color, false, 0.0, Vector3(0.0, yaw, 0.0), mat_trim)
	# 面板四周的压条
	_box(Vector3(size.x, 0.03, 0.03), at + Vector3(0.0, size.y * 0.5, 0.0), TRIM_DARK, false,
		0.0, Vector3(0.0, yaw, 0.0), mat_trim_dark)
	_box(Vector3(size.x, 0.03, 0.03), at - Vector3(0.0, size.y * 0.5, 0.0), TRIM_DARK, false,
		0.0, Vector3(0.0, yaw, 0.0), mat_trim_dark)


func _work_lamp(at: Vector3) -> void:
	# 灯具本体 + 透镜 + 聚光：灯有可见来源，不是凭空亮。
	_cyl(0.16, 0.20, 0.18, at, TRIM_DARK, Vector3.ZERO, 0.0, 14, mat_trim_dark)
	_cyl(0.14, 0.14, 0.04, at - Vector3.UP * 0.09, Color.WHITE, Vector3.ZERO, 0.0, 14, mat_lens)
	var spot := SpotLight3D.new()
	spot.position = at - Vector3.UP * 0.12
	spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	spot.light_color = Color("#ffe3b8")
	spot.light_energy = 1.0
	spot.spot_range = 11.0
	spot.spot_angle = 48.0
	spot.spot_attenuation = 0.9
	spot.shadow_enabled = false
	add_child(spot)


# ---------------------------------------------------------------- 灯光

func _build_lights() -> void:
	# 舱口工作灯（暖）：把门框、坡道和奶龙从地面里拉出来。
	_bay_light = OmniLight3D.new()
	_bay_light.position = Vector3(12.2, 3.05, 0.0)
	_bay_light.light_color = Color("#ffe3b8")
	_bay_light.light_energy = 0.30
	_bay_light.omni_range = 9.5
	add_child(_bay_light)

	# 窝区冷补光：让奶龙轮廓从深色地面里分出来。
	var nest_fill := OmniLight3D.new()
	nest_fill.position = NEST_CENTER + Vector3.UP * 4.4
	nest_fill.light_color = Color("#cfe9e4")
	nest_fill.light_energy = 0.34
	nest_fill.omni_range = 10.5
	add_child(nest_fill)

	# 落地信标（保留原场景的竖向参照）。
	var beacon := CylinderMesh.new()
	beacon.top_radius = 0.18
	beacon.bottom_radius = 0.50
	beacon.height = 2.6
	_add(beacon, Vector3(-14.0, 1.3, -11.0), TRIM, 0.0, Vector3.ZERO, Vector3.ONE, mat_trim)
	var beacon_light := OmniLight3D.new()
	beacon_light.position = Vector3(-14.0, 2.9, -11.0)
	beacon_light.light_color = CYAN
	beacon_light.light_energy = 1.0
	beacon_light.omni_range = 7.0
	add_child(beacon_light)


# ---------------------------------------------------------------- 基础工具

const WHITE := Color(1.0, 1.0, 1.0, 1.0)

func _mat(color: Color, emission: float = 0.0, roughness: float = 0.93) -> StandardMaterial3D:
	# 旧接口保留：只给不需要分层材质的极小件用。
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
		material: Material = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rot
	instance.scale = scale
	instance.material_override = material if material != null else _mat(color, emission)
	add_child(instance)
	return instance


func _child(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _bevel(size: Vector3, bevel: float = 0.025) -> ArrayMesh:
	return kit.beveled_box(size, bevel)


func _box(size: Vector3, at: Vector3, color: Color, solid: bool = false,
		emission: float = 0.0, rot: Vector3 = Vector3.ZERO,
		material: Material = null) -> MeshInstance3D:
	var mesh: Mesh = kit.beveled_box(size, minf(0.04, minf(size.x, minf(size.y, size.z)) * 0.18))
	var node := _add(mesh, at, color, emission, rot, Vector3.ONE, material)
	if solid:
		_box_collider(size, at, rot)
	return node


func _sphere(at: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	# 旧接口保留：只用于极小装饰，不再用于岩石。
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return _add(mesh, at, color, 0.0, rot, size, mat_rock_b)


func _cyl(r_top: float, r_bottom: float, height: float, at: Vector3, color: Color,
		rot: Vector3 = Vector3.ZERO, emission: float = 0.0, segments: int = 16,
		material: Material = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = height
	mesh.radial_segments = segments
	return _add(mesh, at, color, emission, rot, Vector3.ONE, material)


func _ring(inner: float, outer: float, at: Vector3, color: Color,
		rot: Vector3 = Vector3.ZERO, emission: float = 0.0,
		material: Material = null) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 40
	mesh.ring_segments = 10
	return _add(mesh, at, color, emission, rot, Vector3.ONE, material)


func _bolt(at: Vector3, yaw: float, radius: float = 0.04) -> void:
	# 六角头 + 垫圈：yaw 只用于货箱表面，门框用轴 X。
	var head := CylinderMesh.new()
	head.top_radius = radius
	head.bottom_radius = radius
	head.height = radius * 0.9
	head.radial_segments = 6
	var node := MeshInstance3D.new()
	node.mesh = head
	node.position = at
	node.rotation = Vector3(0.0, 0.0, PI * 0.5)
	node.material_override = mat_bare
	add_child(node)
	var washer := CylinderMesh.new()
	washer.top_radius = radius * 1.55
	washer.bottom_radius = radius * 1.55
	washer.height = radius * 0.25
	washer.radial_segments = 12
	var w := MeshInstance3D.new()
	w.mesh = washer
	w.position = at
	w.rotation = Vector3(0.0, 0.0, PI * 0.5)
	w.material_override = mat_trim_dark
	add_child(w)


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












