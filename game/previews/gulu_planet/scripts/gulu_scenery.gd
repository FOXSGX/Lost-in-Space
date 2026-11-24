extends Node3D
class_name GuluScenery

## 奶龙星场景扩展（2026-11-25 ART-SYNC-002）
##
## 目的：解决"一座空场 + 一圈远景"的单一感，在不碰玩法、碰撞、球路的前提下，
## 给场边补上可读的中景设施与第二、第三层空间：
##   1. 北侧装卸场（货架 / 托盘 / 拖车 / 油桶）
##   2. 南侧维修棚（棚屋 / 工作台 / 轮胎 / 棚下工作灯）
##   3. 西侧废轨与脱轨矿车
##   4. 东南角抬高观察台（楼梯 + 栏杆，纯装饰）
##   5. 南北两条管线走廊
##   6. 远景：风蚀拱门 + 两座信号塔 + 轨道小卫星
##
## 约束：
## - 球路 z∈[-3, 3]、x∈[-10, 12.5] 内不放任何东西；
## - 所有设施无碰撞（四面隐形墙仍是唯一边界）；
## - 远景一律不投影；近景设施（棚 / 台 / 矿车）才开阴影；
## - 重复件（油桶 / 栏杆柱 / 枕木）走 MultiMesh，控制 draw call。

const SHADER_DECAL := preload("res://shaders/gulu_contact_decal.gdshader")
const LOADING_FRAME := preload("res://assets/models/nailong/loading_frame.glb")
const ATM := preload("res://scripts/core/art_atmosphere_kit.gd")

const HULL := Color("#7f8e86")
const HULL_LIGHT := Color("#b4c1b7")
const TRIM := Color("#2f5c68")
const TRIM_DARK := Color("#1f3f49")
const AMBER := Color("#ffb347")
const CYAN := Color("#3fd8ff")
const CRATE := Color("#b98a5a")
const CRATE_DARK := Color("#8f6640")

var _kit: GuluArtKit
var _mat_frame: ShaderMaterial
var _mat_frame_dark: ShaderMaterial
var _mat_paint: ShaderMaterial
var _mat_paint_light: StandardMaterial3D
var _mat_bare: ShaderMaterial
var _mat_concrete: ShaderMaterial
var _mat_rock: ShaderMaterial
var _mat_rubber: StandardMaterial3D
var _mat_amber: StandardMaterial3D
var _mat_decal: ShaderMaterial
var _decal_spots: Array[Vector4] = []
var _glb_mats: Dictionary = {}


func _ready() -> void:
	_kit = GuluArtKit.new()
	_mat_frame = _kit.paint(TRIM, 0.52, 0.08, 1.0, 101.0)
	_mat_frame_dark = _kit.dark_metal(TRIM_DARK, 0.58, 102.0)
	_mat_paint = _kit.paint(CRATE, 0.60, 0.10, 1.0, 103.0)
	_mat_paint_light = _kit.clean_paint(HULL_LIGHT, 0.56, 0.04)
	_mat_bare = _kit.bare_metal(Color("#8b979b"), 0.34, 104.0)
	_mat_concrete = _kit.concrete(Color("#8f8778"), 0.90, 105.0)
	_mat_rock = _kit.rock(Color("#a9a091"), Color("#8b8274"), Color("#bdb4a4"), 0.30, 0.55, 106.0)
	_mat_rock.set_shader_parameter("dust_color", Color("#d3c3a4"))
	_mat_rock.set_shader_parameter("damp_color", Color("#6b5f4c"))
	_mat_rubber = _kit.rubber(Color("#20282a"))
	_mat_amber = _kit.emissive(AMBER, 0.6, 0.4)
	_mat_decal = ShaderMaterial.new()
	_mat_decal.shader = SHADER_DECAL
	_mat_decal.set_shader_parameter("tint", Color("#2b2620"))
	_mat_decal.set_shader_parameter("strength", 0.55)

	_build_loading_yard()
	_build_service_shed()
	_build_derelict_cart()
	_build_observation_deck()
	_build_pipeline_corridors()
	_build_terrace_props()
	_build_west_yard()
	_build_east_station()
	_build_far_landmarks()
	_flush_decals()


# ---------------------------------------------------------------- 工具

func _box(size: Vector3, at: Vector3, material: Material, yaw: float = 0.0,
		shadow: bool = true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.rotation.y = yaw
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _cyl(radius: float, height: float, at: Vector3, material: Material,
		shadow: bool = true, segments: int = 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _contact(x: float, z: float, radius: float, strength: float = 0.5) -> void:
	_decal_spots.append(Vector4(x, z, radius, strength))


## GLB 材质：按 GLB 里的 M_ 材质名映射到项目的 paint/mach 家族，
## 并打开 vertex_mask_valid（Blender 已烘焙 R/G/B/A 四通道）。
func _glb_materials() -> Dictionary:
	if not _glb_mats.is_empty():
		return _glb_mats
	var cream := (_kit.paint(HULL_LIGHT, 0.50, 0.10, 1.05, 301.0) as ShaderMaterial).duplicate() as ShaderMaterial
	var yellow := (_kit.paint(Color("#cc8f17"), 0.48, 0.08, 1.15, 302.0) as ShaderMaterial).duplicate() as ShaderMaterial
	var orange := (_kit.paint(Color("#b24510"), 0.48, 0.10, 1.15, 303.0) as ShaderMaterial).duplicate() as ShaderMaterial
	var deep := (_kit.dark_metal(TRIM_DARK, 0.58, 304.0) as ShaderMaterial).duplicate() as ShaderMaterial
	var bare := (_kit.bare_metal(Color("#666f72"), 0.34, 305.0) as ShaderMaterial).duplicate() as ShaderMaterial
	for m in [cream, yellow, orange, deep, bare]:
		(m as ShaderMaterial).set_shader_parameter("vertex_mask_valid", true)
	_glb_mats = {
		"M_PaintCream": cream, "M_PaintYellow": yellow, "M_PaintOrange": orange,
		"M_SteelDeep": deep, "M_BareSteel": bare,
	}
	return _glb_mats


## 实例化一个 GLB 并按材质名覆盖。
func _add_glb(res: PackedScene, at: Vector3, yaw: float, mats: Dictionary,
		shadow: bool = true) -> Node3D:
	var root := res.instantiate() as Node3D
	root.position = at
	root.rotation.y = yaw
	add_child(root)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(s)
			if src != null and mats.has(src.resource_name):
				mi.set_surface_override_material(s, mats[src.resource_name])
	return root


func _flush_decals() -> void:
	if _decal_spots.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = _decal_spots.size()
	for i in range(_decal_spots.size()):
		var spot := _decal_spots[i]
		var basis := Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(spot.z, spot.z, spot.z))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(spot.x, 0.022, spot.y)))
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, spot.w))
	var node := MultiMeshInstance3D.new()
	node.name = "SceneryContactDecals"
	node.multimesh = mm
	node.material_override = _mat_decal
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


# ---------------------------------------------------------------- 北侧装卸场

func _build_loading_yard() -> void:
	# 工字钢门架：Blender 九步流水线资产（10,152 tri，底板+地脚螺栓+加强肋+节点板+焊道+吊钩）
	_add_glb(LOADING_FRAME, Vector3(-1.0, 0.0, 11.2), 0.0, _glb_materials(), true)
	ATM.build_ground_skirt(self, "SkirtFrame", Vector3(-1.0, 0.0, 11.2), Vector2(6.4, 2.6))
	ATM.build_gravel_cluster(self, "GravelFrame", Vector3(-1.0, 0.0, 11.2), 2.9, 20, 77)
	# 托盘与箱：上层两件、地面两件（避开立柱）
	_box(Vector3(1.10, 0.12, 1.00), Vector3(-1.4, 0.98, 10.4), _mat_paint, 0.06)
	_box(Vector3(0.95, 0.85, 0.90), Vector3(-1.4, 1.47, 10.4), _mat_paint, 0.06)
	_box(Vector3(1.05, 0.70, 0.95), Vector3(1.1, 1.30, 10.4), _mat_paint, -0.10)
	_box(Vector3(1.20, 1.00, 1.00), Vector3(-5.2, 0.50, 11.6), _mat_paint, 0.18)
	_box(Vector3(0.90, 0.90, 0.90), Vector3(-5.2, 1.45, 11.6), _mat_paint, 0.42)
	_box(Vector3(1.10, 0.75, 0.80), Vector3(3.4, 0.38, 11.8), _mat_paint, -0.22)
	_contact(-1.4, 10.4, 1.5, 0.5)
	_contact(-5.2, 11.6, 1.5, 0.5)
	_contact(3.4, 11.8, 1.2, 0.45)

	# 拖车：低平板 + 四轮 + 牵引杆
	_box(Vector3(3.6, 0.22, 1.5), Vector3(6.4, 0.78, 11.4), _mat_frame_dark, 0.0, true)
	_box(Vector3(3.2, 0.10, 1.2), Vector3(6.4, 0.94, 11.4), _mat_paint, 0.0, true)
	for x in [5.2, 7.6]:
		for z in [10.76, 12.04]:
			var wheel := _cyl(0.34, 0.22, Vector3(x, 0.34, z), _mat_rubber, true, 14)
			wheel.rotation.z = PI * 0.5
	_box(Vector3(1.0, 0.10, 0.12), Vector3(4.5, 0.62, 11.4), _mat_bare, 0.0, true)
	_contact(6.4, 11.4, 2.3, 0.5)

	# 油桶：六个一簇（MultiMesh 一个 draw call）
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.26
	barrel_mesh.bottom_radius = 0.26
	barrel_mesh.height = 0.82
	barrel_mesh.radial_segments = 14
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = barrel_mesh
	var spots := [
		Vector3(-4.6, 0.41, 11.9), Vector3(-4.0, 0.41, 12.3), Vector3(-3.4, 0.41, 11.8),
		Vector3(-4.6, 0.41, 12.9), Vector3(-4.0, 0.41, 13.0), Vector3(-2.9, 0.41, 12.6),
	]
	mm.instance_count = spots.size()
	for i in range(spots.size()):
		var basis := Basis(Vector3.UP, float(i) * 0.7)
		mm.set_instance_transform(i, Transform3D(basis, spots[i]))
	var barrels := MultiMeshInstance3D.new()
	barrels.name = "Barrels"
	barrels.multimesh = mm
	barrels.material_override = _mat_paint_light
	barrels.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(barrels)
	_contact(-3.9, 12.4, 1.6, 0.45)


# ---------------------------------------------------------------- 南侧维修棚

func _build_service_shed() -> void:
	var z := -11.8
	# 四柱 + 斜顶 + 背墙
	for x in [-2.6, 2.6]:
		for zz in [z - 1.15, z + 1.15]:
			_box(Vector3(0.18, 3.0, 0.18), Vector3(x, 1.5, zz), _mat_frame, 0.0, true)
	var roof := _box(Vector3(6.0, 0.14, 2.9), Vector3(0.0, 3.12, z), _mat_paint_light, 0.0, true)
	roof.rotation.x = deg_to_rad(-6.0)
	_box(Vector3(6.0, 2.3, 0.12), Vector3(0.0, 1.15, z - 1.15), _mat_paint, 0.0, true)
	_box(Vector3(0.12, 2.3, 2.3), Vector3(-2.6, 1.15, z), _mat_paint, 0.0, true)
	# 工作台：台面 + 台下柜 + 台钳 + 工具箱
	_box(Vector3(2.4, 0.10, 0.9), Vector3(0.4, 0.86, z + 0.65), _mat_bare, 0.0, true)
	for x in [-0.55, 1.35]:
		_box(Vector3(0.10, 0.82, 0.10), Vector3(x, 0.42, z + 0.65), _mat_frame_dark, 0.0, true)
	_box(Vector3(2.2, 0.62, 0.78), Vector3(0.4, 0.42, z + 0.65), _mat_frame_dark, 0.0, true)
	_box(Vector3(0.34, 0.26, 0.30), Vector3(-0.6, 1.02, z + 0.66), _mat_amber, 0.0, true)
	_box(Vector3(0.60, 0.24, 0.34), Vector3(1.1, 1.02, z + 0.66), _mat_paint, 0.0, true)
	# 棚下工作灯（自发光 + 一盏真光）
	_box(Vector3(0.5, 0.06, 0.22), Vector3(0.4, 2.72, z + 0.2), _mat_amber, 0.0, false)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.4, 2.55, z + 0.2)
	lamp.light_color = Color("#ffe0b8")
	lamp.light_energy = 0.65
	lamp.omni_range = 6.5
	add_child(lamp)
	_contact(0.4, z + 0.65, 1.7, 0.5)
	_contact(-2.6, z, 0.6, 0.45)
	_contact(2.6, z, 0.6, 0.45)

	# 轮胎堆：三个叠放
	for i in range(3):
		var tyre := _cyl(0.42, 0.24, Vector3(3.9, 0.12 + float(i) * 0.25, z + 1.1), _mat_rubber, true, 16)
		tyre.rotation = Vector3(0.0, float(i) * 0.8, PI * 0.5)
	_contact(3.9, z + 1.1, 0.9, 0.5)
	ATM.build_ground_skirt(self, "SkirtShed", Vector3(0.4, 0.0, z), Vector2(6.8, 3.2))
	ATM.build_gravel_cluster(self, "GravelShed", Vector3(-2.2, 0.0, z + 0.9), 2.0, 12, 91)


# ---------------------------------------------------------------- 西侧废轨与矿车

func _build_derelict_cart() -> void:
	# 轨道沿 z，x = -17.6 / -16.6；六根枕木合并成一个 MultiMesh
	var sleeper_mesh := BoxMesh.new()
	sleeper_mesh.size = Vector3(1.9, 0.09, 0.26)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sleeper_mesh
	var z0 := 2.0
	mm.instance_count = 7
	for i in range(7):
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(-17.1, 0.05, z0 + float(i) * 1.25)))
	var sleepers := MultiMeshInstance3D.new()
	sleepers.name = "RailSleepers"
	sleepers.multimesh = mm
	sleepers.material_override = _mat_frame_dark
	sleepers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sleepers)
	# 两根钢轨（微弯：两段小角度）
	for x in [-17.6, -16.6]:
		var rail := _box(Vector3(0.09, 0.12, 8.2), Vector3(x, 0.14, z0 + 3.9), _mat_bare, 0.0, false)
		rail.rotation.y = deg_to_rad(1.5)
	# 脱轨矿车：箱体倾斜 + 四个轮
	var cart := _box(Vector3(1.9, 1.05, 1.30), Vector3(-17.1, 0.92, 6.2), _mat_paint, 0.0, true)
	cart.rotation.z = deg_to_rad(9.0)
	cart.rotation.y = deg_to_rad(-12.0)
	_box(Vector3(2.0, 0.10, 1.40), Vector3(-17.1, 1.48, 6.2), _mat_frame_dark, -0.2, true)
	for dz in [-0.42, 0.42]:
		for dx in [-0.55, 0.55]:
			var wheel := _cyl(0.30, 0.18, Vector3(-17.1 + dx, 0.42, 6.2 + dz), _mat_frame_dark, true, 12)
			wheel.rotation.z = PI * 0.5
	# 散落的枕木/石块一小堆
	_box(Vector3(1.4, 0.12, 0.24), Vector3(-15.6, 0.10, 7.6), _mat_frame_dark, 0.6, false)
	_box(Vector3(1.2, 0.12, 0.22), Vector3(-15.2, 0.10, 8.2), _mat_frame_dark, -0.3, false)
	_contact(-17.1, 6.2, 1.7, 0.55)
	_contact(-16.0, 7.9, 1.1, 0.45)


# ---------------------------------------------------------------- 东南角观察台

func _build_observation_deck() -> void:
	var cx := 5.4
	var cz := 12.4
	var deck_y := 2.55
	# 台面 + 四腿 + 斜撑
	_box(Vector3(4.0, 0.18, 2.4), Vector3(cx, deck_y, cz), _mat_concrete, 0.0, true)
	for dx in [-1.7, 1.7]:
		for dz in [-0.95, 0.95]:
			_box(Vector3(0.14, deck_y, 0.14), Vector3(cx + dx, deck_y * 0.5, cz + dz), _mat_frame_dark, 0.0, true)
	# 栏杆：立柱 MultiMesh + 两道横杆
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.06, 1.05, 0.06)
	var posts := [
		Vector3(cx - 1.95, deck_y + 0.61, cz),
		Vector3(cx + 1.95, deck_y + 0.61, cz),
		Vector3(cx, deck_y + 0.61, cz - 1.15),
	]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post_mesh
	mm.instance_count = posts.size()
	for i in range(posts.size()):
		mm.set_instance_transform(i, Transform3D(Basis(), posts[i]))
	var post_node := MultiMeshInstance3D.new()
	post_node.name = "DeckPosts"
	post_node.multimesh = mm
	post_node.material_override = _mat_frame
	post_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(post_node)
	_box(Vector3(4.0, 0.06, 0.06), Vector3(cx, deck_y + 1.12, cz), _mat_frame, 0.0, false)
	_box(Vector3(0.06, 0.06, 2.4), Vector3(cx - 1.95, deck_y + 1.12, cz), _mat_frame, 0.0, false)
	_box(Vector3(0.06, 0.06, 2.4), Vector3(cx + 1.95, deck_y + 1.12, cz), _mat_frame, 0.0, false)
	# 楼梯：六步 + 两侧斜梁
	for i in range(6):
		var step_y := 0.20 + float(i) * 0.40
		_box(Vector3(0.90, 0.08, 0.34), Vector3(cx - 2.55 - float(i) * 0.34, step_y, cz), _mat_bare, 0.0, true)
	_box(Vector3(2.3, 0.10, 0.10), Vector3(cx - 3.45, 1.30, cz - 0.55), _mat_frame_dark, 0.0, false)
	_box(Vector3(2.3, 0.10, 0.10), Vector3(cx - 3.45, 1.30, cz + 0.55), _mat_frame_dark, 0.0, false)
	# 台上一盏小标杆灯
	_box(Vector3(0.10, 0.60, 0.10), Vector3(cx + 1.6, deck_y + 1.45, cz + 0.9), _mat_frame_dark, 0.0, false)
	_box(Vector3(0.16, 0.16, 0.16), Vector3(cx + 1.6, deck_y + 1.80, cz + 0.9), _mat_amber, 0.0, false)
	_contact(cx, cz, 2.6, 0.5)
	_contact(cx - 3.4, cz, 1.2, 0.4)
	ATM.build_ground_skirt(self, "SkirtDeck", Vector3(cx, 0.0, cz), Vector2(4.6, 2.9))
	ATM.build_gravel_cluster(self, "GravelDeck", Vector3(cx - 3.2, 0.0, cz), 1.8, 14, 93)


# ---------------------------------------------------------------- 管线走廊

func _build_pipeline_corridors() -> void:
	# 南侧地面管线（维修棚前）。北侧改到货台顶面（见 _build_terrace_props）。
	for z in [-13.2]:
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.14, 1.30, 0.14)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = post_mesh
		var xs := [-14.0, -9.0, -4.0, 1.0, 6.0, 11.0, 15.0]
		mm.instance_count = xs.size()
		for i in range(xs.size()):
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(xs[i], 0.65, z)))
		var post_node := MultiMeshInstance3D.new()
		post_node.name = "PipePosts%d" % int(z)
		post_node.multimesh = mm
		post_node.material_override = _mat_frame_dark
		post_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(post_node)
		for i in range(2):
			var pipe := _cyl(0.17 - float(i) * 0.03, 30.0, Vector3(0.5, 1.18 - float(i) * 0.30, z), _mat_bare, false, 10)
			pipe.rotation.z = PI * 0.5
		for x in [-7.0, 4.0]:
			var valve := _cyl(0.22, 0.08, Vector3(x, 1.55, z), _mat_frame, false, 14)
			valve.rotation.x = PI * 0.5


# ---------------------------------------------------------------- 北台与坑内道具

## 北侧货台（顶面 y=1.0）上的集装箱/托盘，以及下沉坑里的管线架。
func _build_terrace_props() -> void:
	var deck := 1.0
	_box(Vector3(3.0, 2.4, 1.3), Vector3(-13.4, deck + 1.20, 18.4), _mat_paint, 0.0, true)
	_box(Vector3(2.6, 2.2, 1.2), Vector3(-9.6, deck + 1.10, 19.4), _mat_paint_light, 0.06, true)
	_box(Vector3(1.1, 0.14, 1.0), Vector3(-6.6, deck + 0.07, 18.2), _mat_frame_dark, 0.0, true)
	_box(Vector3(0.95, 0.8, 0.9), Vector3(-6.6, deck + 0.54, 18.2), _mat_paint, 0.18, true)
	for x in [-17.0, -14.0, -11.0, -8.0, -5.0]:
		_box(Vector3(0.12, 0.9, 0.12), Vector3(x, deck + 0.45, 20.6), _mat_frame_dark, 0.0, false)
	var pipe := _cyl(0.16, 12.6, Vector3(-11.0, deck + 0.98, 20.6), _mat_bare, false, 10)
	pipe.rotation.z = PI * 0.5
	_contact(-13.4, 18.4, 2.0, 0.4)
	_contact(-6.6, 18.2, 1.2, 0.4)

	# 坑内：两根架管 + 一只工具箱（y 基准 -1.3）
	for x in [-9.0, -6.0]:
		_box(Vector3(0.12, 0.9, 0.12), Vector3(x, -0.85, -19.4), _mat_frame_dark, 0.0, false)
	var pit_pipe := _cyl(0.14, 3.6, Vector3(-7.5, -0.40, -19.4), _mat_bare, false, 10)
	pit_pipe.rotation.z = PI * 0.5
	_box(Vector3(0.7, 0.4, 0.45), Vector3(-4.6, -1.10, -18.2), _mat_amber, 0.0, false)
	_contact(-7.5, -19.0, 2.2, 0.45)


# ---------------------------------------------------------------- 西侧堆料区

## 地图扩到 96×64 后的西侧可漫游区域：矿堆 + 料箱 + 小型门架 + 工作灯。
func _build_west_yard() -> void:
	var rock_specs := [
		[Vector3(-33.0, 0.0, -6.0), Vector3(4.2, 2.4, 3.6), 0.0],
		[Vector3(-37.5, 0.0, 2.5), Vector3(3.4, 1.9, 3.0), 1.1],
		[Vector3(-31.5, 0.0, 7.0), Vector3(2.8, 1.6, 2.4), 2.2],
	]
	for spec in rock_specs:
		var node := MeshInstance3D.new()
		node.mesh = _kit.rock_mesh(float(spec[2]) * 3.7 + 9.0, spec[1], 2)
		node.material_override = _mat_rock
		node.position = spec[0]
		node.rotation.y = spec[2]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)
		_contact(spec[0].x, spec[0].z, spec[1].x * 0.8, 0.5)
	# 料箱两排
	for i in range(4):
		_box(Vector3(1.1, 0.9, 1.0), Vector3(-29.5 + float(i) * 1.25, 0.45, -1.6), _mat_paint, 0.1 * float(i), true)
	_box(Vector3(1.2, 1.3, 1.0), Vector3(-28.4, 0.65, 0.2), _mat_paint_light, -0.2, true)
	# 小门架（两根柱 + 横梁）
	for dx in [-1.4, 1.4]:
		_box(Vector3(0.18, 3.4, 0.18), Vector3(-35.5 + dx, 1.7, -1.0), _mat_frame_dark, 0.0, true)
	_box(Vector3(3.2, 0.16, 0.16), Vector3(-35.5, 3.3, -1.0), _mat_frame, 0.0, true)
	# 工作灯
	_box(Vector3(0.10, 0.9, 0.10), Vector3(-30.2, 0.45, 4.2), _mat_frame_dark, 0.0, false)
	_box(Vector3(0.18, 0.18, 0.18), Vector3(-30.2, 0.98, 4.2), _mat_amber, 0.0, false)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-30.2, 1.1, 4.2)
	lamp.light_color = Color("#ffe0b8")
	lamp.light_energy = 0.5
	lamp.omni_range = 8.0
	add_child(lamp)


# ---------------------------------------------------------------- 东侧场站

## 东侧可漫游区域：集装箱堆 + 天线塔 + 油桶，给“往东走”一个目的地。
func _build_east_station() -> void:
	_box(Vector3(3.4, 2.5, 1.4), Vector3(34.0, 1.25, 12.0), _mat_paint, 0.0, true)
	_box(Vector3(3.0, 2.2, 1.3), Vector3(36.2, 1.10, 14.0), _mat_paint_light, 0.08, true)
	_box(Vector3(2.6, 2.0, 1.2), Vector3(33.4, 1.00, 15.6), _mat_paint, -0.12, true)
	_contact(34.0, 12.0, 2.4, 0.45)
	_contact(33.4, 15.6, 2.0, 0.45)
	# 天线塔：三根立柱 + 两道横撑 + 信标（与远处信号塔区分：更矮、有舱体）
	var at := Vector3(38.5, 0.0, 6.0)
	for dx in [-0.45, 0.45]:
		for dz in [-0.45, 0.45]:
			_box(Vector3(0.12, 5.2, 0.12), at + Vector3(dx, 2.6, dz), _mat_frame_dark, 0.0, true)
	for y in [2.0, 4.0]:
		_box(Vector3(1.0, 0.08, 0.08), at + Vector3(0.0, y, 0.0), _mat_frame_dark, 0.0, false)
		_box(Vector3(0.08, 0.08, 1.0), at + Vector3(0.0, y, 0.0), _mat_frame_dark, 0.0, false)
	_box(Vector3(0.6, 0.5, 0.6), at + Vector3(0.0, 5.4, 0.0), _mat_paint_light, 0.0, true)
	_box(Vector3(0.16, 0.16, 0.16), at + Vector3(0.0, 5.85, 0.0), _mat_amber, 0.0, false)
	# 油桶三只
	for i in range(3):
		var barrel := _cyl(0.26, 0.82, Vector3(31.6 + float(i) * 0.62, 0.41, 9.4), _mat_paint_light, true, 14)
		barrel.rotation.y = float(i) * 0.5
	_contact(32.2, 9.4, 1.2, 0.45)
	ATM.build_ground_skirt(self, "SkirtEast", Vector3(34.4, 0.0, 13.2), Vector2(6.0, 6.4))
	ATM.build_gravel_cluster(self, "GravelEast", Vector3(37.0, 0.0, 8.0), 2.4, 16, 95)


# ---------------------------------------------------------------- 远景地标

func _build_far_landmarks() -> void:
	# 风蚀拱门：两柱 + 顶板（岩材质，纯剪影）；放在北台东侧，避免与货台重叠
	_box(Vector3(1.4, 5.2, 1.6), Vector3(12.6, 2.6, 18.5), _mat_rock, 0.0, false)
	_box(Vector3(1.3, 4.4, 1.5), Vector3(16.8, 2.2, 18.9), _mat_rock, 0.0, false)
	_box(Vector3(5.6, 0.9, 1.9), Vector3(14.7, 5.1, 18.7), _mat_rock, 0.0, false)

	# 两座信号塔（格构感：三根立柱 + 两道横撑 + 信标）
	for spec in [[Vector3(-44.0, 0.0, -27.0), 8.6], [Vector3(44.0, 0.0, 25.0), 7.4]]:
		var at: Vector3 = spec[0]
		var h: float = spec[1]
		for dx in [-0.5, 0.5]:
			for dz in [-0.5, 0.5]:
				_box(Vector3(0.14, h, 0.14), at + Vector3(dx, h * 0.5, dz), _mat_frame_dark, 0.0, false)
		for y in [h * 0.35, h * 0.7]:
			_box(Vector3(1.1, 0.10, 0.10), at + Vector3(0.0, y, 0.0), _mat_frame_dark, 0.0, false)
			_box(Vector3(0.10, 0.10, 1.1), at + Vector3(0.0, y, 0.0), _mat_frame_dark, 0.0, false)
		_box(Vector3(0.30, 0.30, 0.30), at + Vector3(0.0, h + 0.15, 0.0), _mat_amber, 0.0, false)

	# 轨道小卫星：只做剪影，不受雾影响
	var sat_material := StandardMaterial3D.new()
	sat_material.albedo_color = Color("#c9d6da")
	sat_material.emission_enabled = true
	sat_material.emission = Color("#9fc4d2")
	sat_material.emission_energy_multiplier = 0.35
	sat_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sat_material.disable_fog = true
	var sphere := SphereMesh.new()
	sphere.radius = 1.15
	sphere.height = 2.3
	sphere.radial_segments = 20
	sphere.rings = 10
	var sat := MeshInstance3D.new()
	sat.name = "OrbitMoon"
	sat.mesh = sphere
	sat.material_override = sat_material
	sat.position = Vector3(-34.0, 17.0, -46.0)
	sat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sat)
