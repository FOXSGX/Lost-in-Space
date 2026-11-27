extends RefCounted
class_name RuinCartoonArt

## 腐墟星「精致卡通」美术工具。
##
## 归航号主舱已经确定了这套语言：奶油白壳体、青蓝结构、暖橙功能色、
## 低饱和鼠尾草绿点缀，轮廓清楚、表面干净、边缘有倒角。
## 本文件只负责腐墟星的视觉零件，不参与碰撞、玩法和联机同步。
##
## 场景里的建筑、路灯、花坛、长椅都由这里生成；旧版那套暗紫做旧材质
## 不再作为主视觉。所有尺寸单位是米，root 在物体底部中心。

## 表面材质库：ART-SAMPLE-002 的 2K 分族贴图 + aqs2_* shader。
const SURFACE := preload("res://scripts/ruin_surface_lib.gd")

# 调色板（十六进制按 sRGB 书写）。
# 2026-11-25 按《美术制作与 AI 协作指南》1.2 的 65–75 / 10–15 / 5–10 / ≤8 / <2 法则重配：
# 保留奶油/青蓝/暖橙/鼠尾草绿的既定色相，但把大面积基底压到低饱和暗灰/泥炭褐，
# 奶油色只留给上层立面与罩壳，橙色只给可操作件。
const CREAM := Color("#a99c84")
const CREAM_DEEP := Color("#7c705c")
const CREAM_LIGHT := Color("#bdb298")
const TEAL := Color("#2e5259")
const TEAL_DEEP := Color("#1d363c")
const TEAL_LIGHT := Color("#6b9294")
const ORANGE := Color("#a8612f")
const ORANGE_DEEP := Color("#7a431f")
const CORAL := Color("#8f493c")
const SAGE := Color("#5e6b53")
const SAGE_DEEP := Color("#46523f")
const SAND := Color("#6f6553")
const SAND_DEEP := Color("#554c3d")
const INK := Color("#1b2629")
const GLASS := Color("#4b6f72")
const GLASS_LIGHT := Color("#7f9d9c")
const LAMP := Color("#e0b478")

# 新增：大面积基底与路面色。指南要求 65–75% 画面由「与本星生态相符的低饱和基底」压住。
const BASE_DIRT := Color("#665a49")
const BASE_ASPHALT := Color("#474b49")
const BASE_ASPHALT_DARK := Color("#3f4443")
const CONCRETE := Color("#5f5a4d")
const BLOOD := Color("#6f302c")

# 本星生态（菌群/星髓）：只在菌盖、菌褶、菌丝、孢子囊上使用。
const FUNGUS_CAP := Color("#c9c0a6")
const FUNGUS_GILL := Color("#9d5a4a")
const FUNGUS_ROT := Color("#55604a")
const FUNGUS_MYCELIUM := Color("#cfc7ae")
const SPORE_GLOW := Color("#9fe8c8")

static var _shadow_material: StandardMaterial3D
static var _shadow_texture: GradientTexture2D


# ── 基础网格 ───────────────────────────────────────────────────

## 倒角方盒：六个面各向内收 b，棱边和角用斜面补上。
## 这样在低模数量下也有柔和的高光边，符合主舱设备的圆润读法。
static func chamfer_box(size: Vector3, bevel := 0.12) -> ArrayMesh:
	var h: Vector3 = size * 0.5
	var b: float = clampf(bevel, 0.001, minf(h.x, minf(h.y, h.z)) * 0.45)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 六个主面
	_quad(st, Vector3(h.x, -h.y + b, -h.z + b), Vector3(h.x, h.y - b, -h.z + b), Vector3(h.x, h.y - b, h.z - b), Vector3(h.x, -h.y + b, h.z - b), Vector3.RIGHT)
	_quad(st, Vector3(-h.x, -h.y + b, h.z - b), Vector3(-h.x, h.y - b, h.z - b), Vector3(-h.x, h.y - b, -h.z + b), Vector3(-h.x, -h.y + b, -h.z + b), Vector3.LEFT)
	_quad(st, Vector3(-h.x + b, h.y, h.z - b), Vector3(h.x - b, h.y, h.z - b), Vector3(h.x - b, h.y, -h.z + b), Vector3(-h.x + b, h.y, -h.z + b), Vector3.UP)
	_quad(st, Vector3(-h.x + b, -h.y, -h.z + b), Vector3(h.x - b, -h.y, -h.z + b), Vector3(h.x - b, -h.y, h.z - b), Vector3(-h.x + b, -h.y, h.z - b), Vector3.DOWN)
	_quad(st, Vector3(-h.x + b, -h.y + b, h.z), Vector3(h.x - b, -h.y + b, h.z), Vector3(h.x - b, h.y - b, h.z), Vector3(-h.x + b, h.y - b, h.z), Vector3.BACK)
	_quad(st, Vector3(-h.x + b, h.y - b, -h.z), Vector3(h.x - b, h.y - b, -h.z), Vector3(h.x - b, -h.y + b, -h.z), Vector3(-h.x + b, -h.y + b, -h.z), Vector3.FORWARD)

	# 十二根棱：每条棱连接两个被倒角的主面
	for axis: int in 3:
		var i: int = (axis + 1) % 3
		var j: int = (axis + 2) % 3
		for si: float in [-1.0, 1.0]:
			for sj: float in [-1.0, 1.0]:
				var a := Vector3.ZERO
				a = _axis(a, i, si * h[i])
				a = _axis(a, j, sj * (h[j] - b))
				a = _axis(a, axis, -h[axis] + b)
				var bb := _axis(a, axis, h[axis] - b)
				var c := Vector3.ZERO
				c = _axis(c, i, si * (h[i] - b))
				c = _axis(c, j, sj * h[j])
				c = _axis(c, axis, h[axis] - b)
				var d := _axis(c, axis, -h[axis] + b)
				var normal := Vector3.ZERO
				normal = _axis(normal, i, si)
				normal = _axis(normal, j, sj)
				_quad(st, a, bb, c, d, normal.normalized())

	# 八个角
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var a := Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b))
				var bb := Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b))
				var c := Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)
				_tri(st, a, bb, c, Vector3(sx, sy, sz).normalized())
	return st.commit()


static func block(parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color, bevel := 0.12, emissive := false, energy := 0.6, family := -1) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = chamfer_box(size, bevel)
	instance.position = position
	instance.material_override = material(color, emissive, energy, family)
	parent.add_child(instance)
	return instance


static func box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color, emissive := false, energy := 0.6, family := -1) -> MeshInstance3D:
	return block(parent, node_name, size, position, color, 0.001, emissive, energy, family)


## 水平面片：法线固定 +Y，适合铺地、道路和斑马线。
## 比压扁的倒角盒更可靠，不会因为顶面绕序或倒角把整块地面压暗。
## family >= 0 时走轻量 PBR 铺装材质（2K 法线 + 粗糙度）；否则保持纯色片，
## 用于血迹、纸张、油渍这类不该带砖缝的小贴片。
static func plane(parent: Node3D, node_name: String, size: Vector2, position: Vector3, color: Color, emissive := false, energy := 0.4, family := -1, tile_m := 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := PlaneMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	if family >= 0 and not emissive:
		var tile := tile_m if tile_m > 0.0 else 3.0
		instance.material_override = SURFACE.pavement(color, Vector3(maxf(size.x, 0.001) / tile, maxf(size.y, 0.001) / tile, 1.0), _family_tex(family), 0.94)
	else:
		instance.material_override = SURFACE.flat(color, 0.92) if not emissive else material(color, true, energy, family)
	parent.add_child(instance)
	return instance


static func sphere(parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color, emissive := false, energy := 0.5, family := -1) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 18
	mesh.rings = 10
	instance.mesh = mesh
	instance.scale = size
	instance.position = position
	instance.material_override = material(color, emissive, energy, family)
	parent.add_child(instance)
	return instance


static func cylinder(parent: Node3D, node_name: String, radius: float, height: float, position: Vector3, color: Color, emissive := false, energy := 0.5, family := -1) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 18
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material(color, emissive, energy, family)
	parent.add_child(instance)
	return instance


static func cone(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position: Vector3, color: Color, family := -1) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 18
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material(color, false, 0.0, family)
	parent.add_child(instance)
	return instance


static func torus(parent: Node3D, node_name: String, inner: float, outer: float, position: Vector3, color: Color, emissive := false, energy := 0.7, family := -1) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 28
	mesh.ring_segments = 8
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material(color, emissive, energy, family)
	parent.add_child(instance)
	return instance


## 材质入口。
## - emissive=true：StandardMaterial3D + 软膝，供灯具/状态灯/晶体使用。
## - family 显式给出：按家族取 2K 贴图与磨损参数。
## - family=-1：按颜色启发式（暗色→铸件、沙灰→混凝土、其余→喷漆）。
static func material(color: Color, emissive := false, energy := 0.6, family := -1) -> Material:
	if emissive:
		return SURFACE.glow(color, energy)
	if family >= 0:
		return SURFACE.surface(color, family)
	return SURFACE.surface(color, family_for_color(color))


## 颜色 → 材质家族的保守启发式。新代码应尽量显式传 family。
static func family_for_color(color: Color) -> int:
	if color == SAND or color == SAND_DEEP or color == CONCRETE or color == BASE_DIRT:
		return SURFACE.Family.CONC
	if color == INK or color.get_luminance() < 0.16:
		return SURFACE.Family.CAST
	if color == CREAM or color == CREAM_LIGHT or color == CREAM_DEEP:
		return SURFACE.Family.PAINT_CLEAN
	return SURFACE.Family.PAINT_WORN


static func _family_tex(family: int) -> String:
	match family:
		SURFACE.Family.CAST:
			return "cast"
		SURFACE.Family.MACH:
			return "mach"
		SURFACE.Family.CONC:
			return "conc"
		SURFACE.Family.BIO:
			return "bio"
		_:
			return "conc"


## 贴地软阴影。主舱的接地点靠柔光和环境阴影，腐墟星也用同一套，
## 不再依赖会在低模大平面上出黑斑的实时投影。
static func soft_shadow(parent: Node3D, position: Vector3, radius: float, strength := 0.32) -> MeshInstance3D:
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	shadow.mesh = quad
	shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	shadow.position = position + Vector3(0.0, 0.04, 0.0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.material_override = _shadow_material_for(strength)
	parent.add_child(shadow)
	return shadow


static func _shadow_material_for(strength: float) -> StandardMaterial3D:
	if _shadow_material == null:
		_shadow_material = StandardMaterial3D.new()
		_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shadow_material.disable_receive_shadows = true
		_shadow_material.albedo_texture = _radial_fade()
	var mat := _shadow_material.duplicate() as StandardMaterial3D
	mat.albedo_color = Color(0.24, 0.20, 0.15, clampf(0.30 * strength / 0.32, 0.0, 0.55))
	return mat


static func _radial_fade() -> GradientTexture2D:
	if _shadow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		gradient.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 0.45),
			Color(1.0, 1.0, 1.0, 0.0),
		])
		_shadow_texture = GradientTexture2D.new()
		_shadow_texture.gradient = gradient
		_shadow_texture.fill = GradientTexture2D.FILL_RADIAL
		_shadow_texture.fill_from = Vector2(0.5, 0.5)
		_shadow_texture.fill_to = Vector2(1.0, 0.5)
		_shadow_texture.width = 64
		_shadow_texture.height = 64
	return _shadow_texture


# ── 街道陈设 ───────────────────────────────────────────────────

## 一盏路灯：车削基座 + 锥形灯杆 + 检修门 + 悬臂 + 遮光灯罩 + 实用光。
## 灯杆不是一根等粗圆柱：底部法兰、收腰、上段收细，近看有工业节奏。
static func street_lamp(parent: Node3D, position: Vector3, height := 4.0) -> Node3D:
	var root := Node3D.new()
	root.name = "StreetLamp"
	root.position = position
	parent.add_child(root)
	lathe(root, "Footing", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.24, 0.0), Vector2(0.22, 0.10), Vector2(0.16, 0.20), Vector2(0.12, 0.28),
	]), 16, Vector3.ZERO, TEAL_DEEP, SURFACE.Family.CAST)
	lathe(root, "Pole", PackedVector2Array([
		Vector2(0.0, 0.26), Vector2(0.075, 0.28), Vector2(0.062, 0.60), Vector2(0.048, height * 0.72),
		Vector2(0.042, height), Vector2(0.0, height),
	]), 16, Vector3.ZERO, CREAM, SURFACE.Family.PAINT_CLEAN)
	block(root, "Collar", Vector3(0.15, 0.08, 0.15), Vector3(0.0, 0.58, 0.0), ORANGE, 0.015, false, 0.0, SURFACE.Family.PAINT_ACCENT)
	block(root, "AccessDoor", Vector3(0.09, 0.28, 0.02), Vector3(0.0, 1.10, 0.065), TEAL_DEEP, 0.006, false, 0.0, SURFACE.Family.MACH)
	for sx: float in [-1.0, 1.0]:
		bolt(root, "BaseBolt", Vector3(sx * 0.18, 0.03, 0.0), 0.024, INK)
	var arm := cylinder(root, "Arm", 0.042, 0.66, Vector3(0.31, height - 0.06, 0.0), CREAM, false, 0.0, SURFACE.Family.MACH)
	arm.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	block(root, "ArmBrace", Vector3(0.05, 0.05, 0.48), Vector3(0.20, height - 0.26, 0.0), CREAM_LIGHT, 0.01, false, 0.0, SURFACE.Family.MACH).rotation_degrees.z = 36.0
	sphere(root, "Lamp", Vector3(0.28, 0.22, 0.28), Vector3(0.62, height - 0.10, 0.0), LAMP, true, 1.0)
	cone(root, "LampHood", 0.07, 0.20, 0.16, Vector3(0.62, height + 0.05, 0.0), TEAL_DEEP, SURFACE.Family.PAINT_CLEAN)
	var practical := OmniLight3D.new()
	practical.name = "LampGlow"
	practical.light_color = LAMP
	practical.light_energy = 0.70
	practical.omni_range = 6.0
	practical.shadow_enabled = false
	practical.position = Vector3(0.62, height - 0.14, 0.0)
	root.add_child(practical)
	return root


## 方形花坛：混凝土槽体 + 橙色压边 + 深色土 + 三四团哑光鼠尾草绿灌木。
static func planter(parent: Node3D, position: Vector3, size := 1.5, seed_value := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Planter"
	root.position = position
	parent.add_child(root)
	block(root, "Pot", Vector3(size, 0.58, size), Vector3(0.0, 0.29, 0.0), CONCRETE, 0.08, false, 0.0, SURFACE.Family.CONC)
	block(root, "Rim", Vector3(size + 0.10, 0.10, size + 0.10), Vector3(0.0, 0.59, 0.0), ORANGE, 0.03, false, 0.0, SURFACE.Family.PAINT_ACCENT)
	box(root, "Soil", Vector3(size - 0.20, 0.05, size - 0.20), Vector3(0.0, 0.635, 0.0), INK, false, 0.0, SURFACE.Family.CONC)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index: int in 4:
		var offset := Vector3(rng.randf_range(-0.32, 0.32) * size, 0.74 + rng.randf_range(0.0, 0.16), rng.randf_range(-0.32, 0.32) * size)
		var radius := rng.randf_range(0.30, 0.44) * size
		sphere(root, "Shrub%d" % index, Vector3(radius, radius * 0.9, radius), offset, SAGE if index % 2 == 0 else SAGE_DEEP, false, 0.0, SURFACE.Family.FOLIAGE)
	return root


## 长椅：奶油座面 + 青蓝靠背 + 暖橙腿。
static func bench(parent: Node3D, position: Vector3, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Bench"
	root.position = position
	root.rotation_degrees.y = yaw
	parent.add_child(root)
	block(root, "Seat", Vector3(1.9, 0.13, 0.56), Vector3(0.0, 0.46, 0.0), CREAM, 0.05)
	block(root, "Back", Vector3(1.9, 0.52, 0.11), Vector3(0.0, 0.78, -0.23), TEAL, 0.05)
	for side: float in [-1.0, 1.0]:
		block(root, "Leg", Vector3(0.13, 0.44, 0.46), Vector3(side * 0.76, 0.22, 0.0), ORANGE, 0.04)
		block(root, "Arm", Vector3(0.09, 0.09, 0.56), Vector3(side * 0.9, 0.62, 0.0), TEAL_DEEP, 0.03)
	return root


## 一棵卡通树：车削树干 + 分节树冠 + 树池压边，冠幅不再是一颗大球。
static func tree(parent: Node3D, position: Vector3, seed_value := 1, scale_factor := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Tree"
	root.position = position
	root.scale = Vector3.ONE * scale_factor
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	lathe(root, "Trunk", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.20, 0.02), Vector2(0.17, 0.18), Vector2(0.13, 1.20),
		Vector2(0.11, 2.05), Vector2(0.0, 2.08),
	]), 12, Vector3.ZERO, Color("#8a6a46"), SURFACE.Family.PAINT_CLEAN)
	var pit := cylinder(root, "TreePit", 0.62, 0.035, Vector3(0.0, 0.018, 0.0), INK, false, 0.0, SURFACE.Family.CONC)
	pit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for index: int in 4:
		var radius := rng.randf_range(0.78, 1.18)
		var offset := Vector3(rng.randf_range(-0.42, 0.42), 2.15 + float(index) * 0.30, rng.randf_range(-0.42, 0.42))
		sphere(root, "Crown%d" % index, Vector3(radius, radius * 0.88, radius), offset, SAGE if index % 2 == 0 else SAGE_DEEP, false, 0.0, SURFACE.Family.FOLIAGE)
	return root


## 护柱：车削柱身 + 底脚法兰 + 反光带 + 顶部圆角。
static func bollard(parent: Node3D, position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Bollard"
	root.position = position
	parent.add_child(root)
	lathe(root, "Post", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.16, 0.0), Vector2(0.15, 0.05), Vector2(0.11, 0.10),
		Vector2(0.105, 0.62), Vector2(0.13, 0.68), Vector2(0.12, 0.74), Vector2(0.0, 0.76),
	]), 16, Vector3.ZERO, ORANGE, SURFACE.Family.PAINT_ACCENT)
	cylinder(root, "Band", 0.118, 0.075, Vector3(0.0, 0.50, 0.0), CREAM_LIGHT, false, 0.0, SURFACE.Family.MACH)
	cylinder(root, "Cap", 0.10, 0.035, Vector3(0.0, 0.745, 0.0), TEAL_DEEP, false, 0.0, SURFACE.Family.PAINT_WORN)
	return root


# ── 程序化工艺构件（指南方法一在 Godot 侧的等价实现）──────────────
#
# 这些函数负责「真实厚度、真实倒角、真实拼缝、承力关系」，替代裸 Box/Cylinder
# 直接当成品的做法。全部只生成视觉节点，不参与碰撞、玩法和联机同步。

## 车削：profile 是 (半径, 高度) 的剖面条带，绕 Y 轴旋转。
## 用于灯杆、护柱、信标、水箱、充电塔、阀体；根部总会得到一个可见底脚。
static func lathe(parent: Node3D, node_name: String, profile: PackedVector2Array, segments: int, position: Vector3, color: Color, family := -1, emissive := false, energy := 0.0, yaw := 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = _lathe_mesh(profile, maxi(segments, 8))
	instance.position = position
	instance.rotation_degrees.y = yaw
	instance.material_override = material(color, emissive, energy, family)
	parent.add_child(instance)
	return instance


## 挤出多边形（可上收口）：profile 是 XZ 平面的闭合多边形（逆时针）。
## 用于异形机壳、星髓晶柱；taper 让顶部收口，形成晶体尖。
static func prism(parent: Node3D, node_name: String, profile: PackedVector2Array, height: float, position: Vector3, color: Color, family := -1, taper := 0.55, yaw := 0.0, emissive := false, energy := 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = _prism_mesh(profile, height, taper)
	instance.position = position
	instance.rotation_degrees.y = yaw
	instance.material_override = material(color, emissive, energy, family)
	parent.add_child(instance)
	return instance


## 批量倒角盒：把同一建族的静态小件（立面板、窗框、肋柱、螺栓排）合并成
## 一个 MeshInstance3D 的多 surface 网格，避免细节把 draw call 拉爆。
## entries: [{size: Vector3, position: Vector3, color: Color, family: int, rotation_y: float}]
static func batch_boxes(parent: Node3D, node_name: String, entries: Array, bevel := 0.02, bake_masks := true) -> MeshInstance3D:
	var groups: Dictionary = {}
	for raw in entries:
		var entry: Dictionary = raw as Dictionary
		var size: Vector3 = entry.get("size", Vector3.ONE)
		var position: Vector3 = entry.get("position", Vector3.ZERO)
		var color: Color = entry.get("color", CREAM)
		var family: int = int(entry.get("family", -1))
		if family < 0:
			family = family_for_color(color)
		var rot_y: float = float(entry.get("rotation_y", 0.0))
		var key := "%d|%s" % [family, color.to_html(false)]
		if not groups.has(key):
			groups[key] = {"tool": SurfaceTool.new(), "color": color, "family": family}
			(groups[key].tool as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
		var st: SurfaceTool = groups[key].tool
		var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)), position)
		_append_box(st, size, bevel, xform, bake_masks)
	var out := ArrayMesh.new()
	for key in groups.keys():
		var group: Dictionary = groups[key]
		var tmp := (group.tool as SurfaceTool).commit()
		if tmp == null:
			continue
		var arrays := tmp.surface_get_arrays(0)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var overrides := {}
		if bake_masks:
			overrides["vertex_mask_valid"] = true
		out.surface_set_material(out.get_surface_count() - 1, SURFACE.surface(group.color as Color, int(group.family), overrides))
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = out
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## 立面分板：在给定朝向上铺一层带 2.4 cm 真实凹槽的墙板 + 竖向肋柱。
## origin 是立面中心在地面的投影；right/up 定义立面平面；skip 是不铺板的功能洞口
## （门洞、窗洞、招牌位），Rect2 的 x 是沿 right 的坐标，y 是离地高度。
static func panel_facade(parent: Node3D, node_name: String, origin: Vector3, right: Vector3, up: Vector3,
		width: float, height: float, panel_w: float, panel_h: float, gap: float,
		colors: Array, seed_value: int, skip: Array = []) -> Node3D:
	var normal := right.cross(up).normalized()
	var root := Node3D.new()
	root.name = node_name
	root.transform = Transform3D(Basis(right.normalized(), up.normalized(), normal), origin)
	parent.add_child(root)
	var bottom := 0.62
	var top := maxf(height - 0.42, bottom + panel_h * 0.6)
	var cols := maxi(1, roundi((width + gap) / (panel_w + gap)))
	var rows := maxi(1, roundi((top - bottom + gap) / (panel_h + gap)))
	var cell_w: float = maxf((width - gap * float(cols - 1)) / float(cols), 0.15)
	var cell_h: float = maxf((top - bottom - gap * float(rows - 1)) / float(rows), 0.15)
	var depth := 0.09
	var entries: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for row in rows:
		for col in cols:
			var u: float = -width * 0.5 + cell_w * (float(col) + 0.5) + gap * float(col)
			var v: float = bottom + cell_h * (float(row) + 0.5) + gap * float(row)
			var cell_rect := Rect2(u - cell_w * 0.5, v - cell_h * 0.5, cell_w, cell_h)
			var blocked := false
			for raw in skip:
				if cell_rect.intersects(raw as Rect2):
					blocked = true
					break
			if blocked:
				continue
			var color: Color = colors[(col + row * 2 + seed_value) % colors.size()]
			# 每块板轻微换色，避免整面墙读成一张贴图。
			color = color.lerp(CREAM_DEEP, rng.randf_range(0.0, 0.07))
			entries.append({
				"size": Vector3(cell_w - gap, cell_h - gap, depth),
				"position": Vector3(u, v, depth * 0.5 + 0.012),
				"color": color,
				"family": SURFACE.Family.PAINT_CLEAN,
			})
	# 竖向肋柱：每隔 2–3 块板一条，给长墙节奏。
	var rib_step := maxi(1, roundi(3.2 / maxf(panel_w, 0.6)))
	for col in range(1, cols):
		if col % rib_step != 0:
			continue
		var u: float = -width * 0.5 + cell_w * float(col) + gap * (float(col) - 0.5)
		entries.append({
			"size": Vector3(0.12, top - bottom, 0.10),
			"position": Vector3(u, (bottom + top) * 0.5, 0.06),
			"color": CREAM_LIGHT,
			"family": SURFACE.Family.PAINT_CLEAN,
		})
	# 勒脚压条与檐口压条。
	entries.append({"size": Vector3(width, 0.18, 0.12), "position": Vector3(0.0, bottom - 0.09, 0.07), "color": SAND_DEEP, "family": SURFACE.Family.CONC})
	entries.append({"size": Vector3(width, 0.16, 0.16), "position": Vector3(0.0, top + 0.08, 0.08), "color": CREAM_LIGHT, "family": SURFACE.Family.PAINT_CLEAN})
	batch_boxes(root, node_name + "_Batch", entries, 0.018, true)
	return root


## 工字钢梁柱：真实 I 形截面挤出 + 柱脚底板 + 四颗地脚螺栓。
static func i_beam(parent: Node3D, node_name: String, height: float, flange_w: float, depth: float, web: float, flange_t: float, position: Vector3, color: Color, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	root.rotation_degrees.y = yaw
	parent.add_child(root)
	var hw := flange_w * 0.5
	var hd := depth * 0.5
	var hweb := web * 0.5
	var profile := PackedVector2Array([
		Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, -hd + flange_t), Vector2(hweb, -hd + flange_t),
		Vector2(hweb, hd - flange_t), Vector2(hw, hd - flange_t), Vector2(hw, hd), Vector2(-hw, hd),
		Vector2(-hw, hd - flange_t), Vector2(-hweb, hd - flange_t), Vector2(-hweb, -hd + flange_t), Vector2(-hw, -hd + flange_t),
	])
	var shaft := MeshInstance3D.new()
	shaft.name = "Web"
	shaft.mesh = _prism_mesh(profile, height, 1.0)
	shaft.position = Vector3(0.0, height * 0.5, 0.0)
	shaft.material_override = material(color, false, 0.0, SURFACE.Family.MACH)
	root.add_child(shaft)
	var base := block(root, "BasePlate", Vector3(flange_w + 0.28, 0.06, depth + 0.28), Vector3(0.0, 0.03, 0.0), INK, 0.012, false, 0.0, SURFACE.Family.CAST)
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			bolt(root, "AnchorBolt", Vector3(sx * (flange_w * 0.5 + 0.08), 0.08, sz * (depth * 0.5 + 0.08)), 0.032, INK)
	return root


## 单颗六角螺栓：凸台 + 垫圈 + 45° 倒棱六角头；只用在真实装配/检修节点。
static func bolt(parent: Node3D, node_name: String, position: Vector3, radius := 0.03, color := INK) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	parent.add_child(root)
	var boss := cylinder(root, "Boss", radius * 1.55, radius * 0.5, Vector3(0.0, radius * 0.25, 0.0), color, false, 0.0, SURFACE.Family.CAST)
	boss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var washer := cylinder(root, "Washer", radius * 1.42, radius * 0.22, Vector3(0.0, radius * 0.58, 0.0), CREAM_DEEP, false, 0.0, SURFACE.Family.MACH)
	washer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var head := MeshInstance3D.new()
	head.name = "HexHead"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.92
	mesh.bottom_radius = radius
	mesh.height = radius * 0.72
	mesh.radial_segments = 6
	head.mesh = mesh
	head.position = Vector3(0.0, radius * 0.92, 0.0)
	head.material_override = material(color.lightened(0.12), false, 0.0, SURFACE.Family.MACH)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(head)
	return root


## 螺栓排：沿一段轴线等距布置，供法兰/检修口/柱脚使用。
static func bolt_row(parent: Node3D, node_name: String, from_point: Vector3, to_point: Vector3, count: int, radius := 0.028, color := INK) -> Node3D:
	var row := Node3D.new()
	row.name = node_name
	parent.add_child(row)
	var n := maxi(count, 2)
	for index in n:
		var t := float(index) / float(n - 1)
		bolt(row, "Bolt%d" % index, from_point.lerp(to_point, t), radius, color)
	return row


## 折线管路：圆柱段 + 弯头球 + 每 1.8–2.5 m 一个管卡/法兰。
static func pipe_run(parent: Node3D, node_name: String, points: Array, radius: float, color: Color, family := -1, collars := true) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	var collider_family := family if family >= 0 else SURFACE.Family.MACH
	for index in range(points.size() - 1):
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		var segment := _rod(root, "Pipe%d" % index, a, b, radius, color, collider_family)
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if collars:
			var length := a.distance_to(b)
			var count := maxi(1, roundi(length / 2.1))
			for k in range(1, count + 1):
				var t := float(k) / float(count + 1)
				var at := a.lerp(b, t)
				var collar := cylinder(root, "PipeCollar", radius * 1.55, 0.06, at, CREAM_DEEP, false, 0.0, SURFACE.Family.MACH)
				collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if index < points.size() - 2:
			var knob := sphere(root, "PipeElbow", Vector3.ONE * radius * 2.6, b, color, false, 0.0, collider_family)
			knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## 面化岩块：低模球体 + 8–14 刀随机平面切削 + 平直着色 + 底部埋深。
## 禁止「平滑球 + 噪声」当岩体。
static func rock_chunk(parent: Node3D, node_name: String, size: Vector3, seed_value: int, position: Vector3, cuts := 10, stone_a := Color("#5a5448"), stone_b := Color("#3b3933"), stone_c := Color("#6f685a")) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = _rock_mesh(size, seed_value, cuts)
	instance.position = position
	instance.material_override = SURFACE.rock(stone_a, stone_b, stone_c, 2.6, 0.34)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## 碎石/崩积：沿一个中心撒一圈面化岩块，半径和高度都有变化。
static func rubble_field(parent: Node3D, node_name: String, center: Vector3, radius: float, count: int, seed_value: int, scale_value := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = center
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in maxi(count, 1):
		var angle := rng.randf() * TAU
		var distance := radius * sqrt(rng.randf())
		var chunk_size := Vector3(rng.randf_range(0.18, 0.55), rng.randf_range(0.12, 0.34), rng.randf_range(0.18, 0.5)) * scale_value
		var at := Vector3(cos(angle) * distance, chunk_size.y * 0.32, sin(angle) * distance)
		var chunk := rock_chunk(root, "Rubble%d" % index, chunk_size, seed_value + index * 17, at, 8)
		chunk.rotation_degrees.y = rng.randf_range(0.0, 360.0)
	return root


## 菌群簇：菌柄 + 分节菌盖 + 硬箍环 + 菌褶 + 荧光孢子囊；根部埋入宿主并压碎石。
## 只用在排水口、背阴墙脚、能源站与地下；登陆艇与城市边缘保持干净。
static func fungus_cluster(parent: Node3D, node_name: String, position: Vector3, normal_dir: Vector3, scale_value: float, seed_value: int, with_glow := true) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	if normal_dir.length_squared() > 0.001:
		root.rotation.y = atan2(normal_dir.x, normal_dir.z)
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cap_count := rng.randi_range(3, 5)
	for index in cap_count:
		var angle := TAU * float(index) / float(cap_count) + rng.randf_range(-0.25, 0.25)
		var distance := rng.randf_range(0.08, 0.34) * scale_value
		var height := rng.randf_range(0.22, 0.46) * scale_value
		var cap_r := rng.randf_range(0.16, 0.30) * scale_value
		var stem_at := Vector3(cos(angle) * distance, -height * 0.22, sin(angle) * distance)
		var stem := lathe(root, "Stem%d" % index, PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(cap_r * 0.28, height * 0.12), Vector2(cap_r * 0.22, height * 0.72),
			Vector2(cap_r * 0.34, height), Vector2(0.0, height),
		]), 12, stem_at, FUNGUS_MYCELIUM, SURFACE.Family.BIO)
		stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cap_at := stem_at + Vector3(0.0, height, 0.0)
		# 菌盖：分段剖面 + 硬箍环，做出「精致卡通」的饱满分节而不是软球。
		var cap := lathe(root, "Cap%d" % index, PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(cap_r * 0.55, -0.012 * scale_value), Vector2(cap_r, -0.02 * scale_value),
			Vector2(cap_r * 0.96, 0.06 * scale_value), Vector2(cap_r * 0.78, 0.16 * scale_value),
			Vector2(cap_r * 0.42, 0.22 * scale_value), Vector2(0.0, 0.24 * scale_value),
		]), 16, cap_at, FUNGUS_CAP, SURFACE.Family.BIO)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ring := torus(root, "CapRing%d" % index, cap_r * 0.94, cap_r * 1.02, cap_at + Vector3(0.0, 0.015 * scale_value, 0.0), FUNGUS_GILL, false, 0.0, SURFACE.Family.BIO)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var gills := cylinder(root, "Gills%d" % index, cap_r * 0.92, 0.012 * scale_value, cap_at + Vector3(0.0, -0.028 * scale_value, 0.0), FUNGUS_GILL, false, 0.0, SURFACE.Family.BIO)
		gills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if with_glow:
		for index in 2:
			var pod_at := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.06, 0.2), rng.randf_range(-0.3, 0.3)) * scale_value
			var pod := sphere(root, "SporePod%d" % index, Vector3.ONE * 0.055 * scale_value, pod_at, SPORE_GLOW, true, 0.55)
			pod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 根部压边：一圈碎石，把菌簇「种」进地面，而不是摆在上面。
	rubble_field(root, "RootDebris", Vector3(0.0, 0.0, 0.0), 0.42 * scale_value, 5, seed_value + 31, 0.55 * scale_value)
	return root


## 菌丝斑：不规则低矮贴片，用于墙脚/排水口/地砖缝。
static func mycelium_patch(parent: Node3D, node_name: String, position: Vector3, radius: float, seed_value: int, rotation_degrees_value := Vector3(-90.0, 0.0, 0.0)) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = _disc_mesh(radius, seed_value)
	instance.position = position
	instance.rotation_degrees = rotation_degrees_value
	instance.material_override = SURFACE.surface(FUNGUS_ROT.lightened(0.22), SURFACE.Family.BIO)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## 星髓晶簇：不等边多边形晶柱 + 根部压裂基材 + 碎屑；必须从裂缝里长出来。
static func crystal_cluster(parent: Node3D, node_name: String, position: Vector3, height: float, seed_value: int) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	parent.add_child(root)
	var material := SURFACE.crystal(
		Color(0.020, 0.075, 0.090), Color(0.070, 0.300, 0.320),
		Color(0.620, 0.900, 0.880), Color(0.400, 0.250, 0.720), 0.50, 0.28, 0.42)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := rng.randi_range(3, 5)
	for index in count:
		var sides := rng.randi_range(5, 7)
		var profile := PackedVector2Array()
		for k in sides:
			var angle := TAU * float(k) / float(sides)
			var r := height * rng.randf_range(0.10, 0.16)
			profile.append(Vector2(cos(angle) * r, sin(angle) * r))
		var shard := MeshInstance3D.new()
		shard.name = "Shard%d" % index
		shard.mesh = _prism_mesh(profile, height * rng.randf_range(0.55, 1.0), 0.42)
		shard.position = Vector3(rng.randf_range(-0.32, 0.32) * height, -height * 0.18, rng.randf_range(-0.32, 0.32) * height)
		shard.rotation_degrees = Vector3(rng.randf_range(-18.0, 18.0), rng.randf_range(0.0, 360.0), rng.randf_range(-18.0, 18.0))
		shard.material_override = material
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(shard)
	rubble_field(root, "CrystalDebris", Vector3.ZERO, height * 0.9, 7, seed_value + 11, 0.5)
	return root


## 雨水篦子：凹框 + 一排扁钢条。
static func drain_grate(parent: Node3D, node_name: String, position: Vector3, size: Vector2, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	root.rotation_degrees.y = yaw
	parent.add_child(root)
	var frame := block(root, "GrateFrame", Vector3(size.x + 0.16, 0.05, size.y + 0.16), Vector3(0.0, 0.025, 0.0), SAND_DEEP, 0.012, false, 0.0, SURFACE.Family.CONC)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var entries: Array = []
	var bars := maxi(4, int(size.y / 0.12))
	for index in bars:
		var z: float = -size.y * 0.5 + (float(index) + 0.5) * size.y / float(bars)
		entries.append({"size": Vector3(size.x, 0.03, 0.035), "position": Vector3(0.0, 0.045, z), "color": INK, "family": SURFACE.Family.MACH})
	batch_boxes(root, "GrateBars", entries, 0.006, false)
	return root


## 危险边界警示带：只在真实危险边界（站台边、设备检修口）出现。
static func hazard_band(parent: Node3D, node_name: String, position: Vector3, size: Vector2, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	root.rotation_degrees.y = yaw
	parent.add_child(root)
	var base := block(root, "HazardBase", Vector3(size.x, 0.02, size.y), Vector3(0.0, 0.01, 0.0), INK, 0.004, false, 0.0, SURFACE.Family.CAST)
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var marks := maxi(3, int(size.x / 0.42))
	for index in marks:
		var x: float = -size.x * 0.5 + (float(index) + 0.5) * size.x / float(marks)
		var mark := block(root, "HazardMark", Vector3(size.x / float(marks) * 0.55, 0.022, size.y * 0.82), Vector3(x, 0.022, 0.0), ORANGE, 0.004, false, 0.0, SURFACE.Family.PAINT_ACCENT)
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


# ── 网格辅助 ───────────────────────────────────────────────────

static func _axis(vector: Vector3, axis: int, value: float) -> Vector3:
	var result := vector
	match axis:
		0:
			result.x = value
		1:
			result.y = value
		_:
			result.z = value
	return result


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_tri(st, a, b, c, normal)
	_tri(st, a, c, d, normal)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(b)
	st.set_normal(normal)
	st.add_vertex(c)


# ── 生成器内部 ─────────────────────────────────────────────────

static func _lathe_mesh(profile: PackedVector2Array, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := profile.size()
	for j in segments:
		var a0 := TAU * float(j) / float(segments)
		var a1 := TAU * float(j + 1) / float(segments)
		for i in range(rings - 1):
			var p0 := profile[i]
			var p1 := profile[i + 1]
			var n0 := _profile_normal(profile, i)
			var n1 := _profile_normal(profile, i + 1)
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v10 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var nx0 := Vector3(cos(a0) * n0.x, n0.y, sin(a0) * n0.x)
			var nx1 := Vector3(cos(a1) * n1.x, n1.y, sin(a1) * n1.x)
			_tri_n(st, v00, v01, v11, nx0, nx1, nx1)
			_tri_n(st, v00, v11, v10, nx0, nx1, nx0)
	# 上下封口：半径大于 0 的剖面端点补扇形，保证车削体不是空壳。
	_cap(st, profile[0], segments, false)
	_cap(st, profile[rings - 1], segments, true)
	return st.commit()


static func _cap(st: SurfaceTool, point: Vector2, segments: int, top: bool) -> void:
	if point.x <= 0.0001:
		return
	var normal := Vector3.DOWN if not top else Vector3.UP
	var center := Vector3(0.0, point.y, 0.0)
	for j in segments:
		var a0 := TAU * float(j) / float(segments)
		var a1 := TAU * float(j + 1) / float(segments)
		var p0 := Vector3(cos(a0) * point.x, point.y, sin(a0) * point.x)
		var p1 := Vector3(cos(a1) * point.x, point.y, sin(a1) * point.x)
		if top:
			_tri(st, center, p0, p1, normal)
		else:
			_tri(st, center, p1, p0, normal)


static func _profile_normal(profile: PackedVector2Array, index: int) -> Vector2:
	var prev := profile[maxi(index - 1, 0)]
	var next := profile[mini(index + 1, profile.size() - 1)]
	var tangent := next - prev
	if tangent.length_squared() < 1e-8:
		tangent = Vector2(0.0, 1.0)
	tangent = tangent.normalized()
	# 剖面按“底→顶”书写，外法线是切线顺时针旋转 90°。
	return Vector2(tangent.y, -tangent.x)


static func _prism_mesh(profile: PackedVector2Array, height: float, taper: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := profile.size()
	if count < 3:
		return st.commit()
	var center := Vector2.ZERO
	for p in profile:
		center += p
	center /= float(count)
	var top_scale := clampf(taper, 0.05, 1.0)
	var top_y := height
	# 侧面：底面多边形 → 顶面收口多边形。
	for i in count:
		var j := (i + 1) % count
		var b0 := Vector3(profile[i].x, 0.0, profile[i].y)
		var b1 := Vector3(profile[j].x, 0.0, profile[j].y)
		var t0 := Vector3(profile[i].x * top_scale, top_y, profile[i].y * top_scale)
		var t1 := Vector3(profile[j].x * top_scale, top_y, profile[j].y * top_scale)
		var edge := b1 - b0
		var up := t0 - b0
		var n := edge.cross(up).normalized()
		var mid := (b0 + b1 + t0 + t1) * 0.25
		var outward := Vector3(mid.x, mid.y, mid.z) * 0.5
		if n.dot(outward) < 0.0:
			n = -n
		_tri_n(st, b0, t0, t1, n, n, n)
		_tri_n(st, b0, t1, b1, n, n, n)
	# 顶盖。
	var top_center := Vector3(0.0, top_y, 0.0)
	for i in count:
		var j := (i + 1) % count
		var t0 := Vector3(profile[i].x * top_scale, top_y, profile[i].y * top_scale)
		var t1 := Vector3(profile[j].x * top_scale, top_y, profile[j].y * top_scale)
		_tri(st, top_center, t1, t0, Vector3.UP)
	# 底盖。
	var bottom_center := Vector3(0.0, 0.0, 0.0)
	for i in count:
		var j := (i + 1) % count
		var b0 := Vector3(profile[i].x, 0.0, profile[i].y)
		var b1 := Vector3(profile[j].x, 0.0, profile[j].y)
		_tri(st, bottom_center, b0, b1, Vector3.DOWN)
	return st.commit()


static func _tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


static func _append_box(st: SurfaceTool, size: Vector3, bevel: float, xform: Transform3D, bake_masks: bool) -> void:
	var mesh := chamfer_box(size, bevel)
	_append_mesh(st, mesh, xform, bake_masks)


static func _append_mesh(st: SurfaceTool, mesh: Mesh, xform: Transform3D, bake_masks: bool) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var raw_indices: Variant = arrays[Mesh.ARRAY_INDEX]
	var indices := PackedInt32Array()
	if raw_indices != null:
		indices = raw_indices as PackedInt32Array
	var count := indices.size() if indices.size() > 0 else verts.size()
	for k in count:
		var index: int = indices[k] if indices.size() > 0 else k
		var n := (xform.basis * normals[index]).normalized()
		st.set_normal(n)
		if bake_masks:
			var edge := 1.0 - maxf(absf(n.x), maxf(absf(n.y), absf(n.z)))
			var chip := 0.5 + 0.5 * sin(float(index) * 12.9898 + size_hash(xform.origin))
			st.set_color(Color(clampf(edge * 1.8, 0.0, 1.0), 0.0, chip, clampf(n.y, 0.0, 1.0)))
		st.add_vertex(xform * verts[index])


static func size_hash(point: Vector3) -> float:
	return fmod(absf(point.x * 17.0 + point.y * 29.0 + point.z * 41.0), 6.2831853)


static func _rod(parent: Node3D, node_name: String, from_point: Vector3, to_point: Vector3, radius: float, color: Color, family: int) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = maxf(from_point.distance_to(to_point), 0.01)
	mesh.radial_segments = 12
	instance.mesh = mesh
	var direction := (to_point - from_point).normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var right := direction.cross(up).normalized()
	var back := right.cross(direction).normalized()
	instance.transform = Transform3D(Basis(right, direction, back), (from_point + to_point) * 0.5)
	instance.material_override = material(color, false, 0.0, family)
	parent.add_child(instance)
	return instance


static func _rock_mesh(size: Vector3, seed_value: int, cuts: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 6
	var base := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
	var raw_indices: Variant = base[Mesh.ARRAY_INDEX]
	var indices := PackedInt32Array()
	if raw_indices != null:
		indices = raw_indices as PackedInt32Array
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var planes: Array = []
	var radius: float = maxf(size.x, maxf(size.y, size.z)) * 0.5
	for i in maxi(cuts, 4):
		var n := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.45, 0.65), rng.randf_range(-1.0, 1.0)).normalized()
		var d := radius * rng.randf_range(0.52, 0.92)
		planes.append({"normal": n, "d": d})
	var shaped := PackedVector3Array()
	for v in verts:
		var p := Vector3(v.x * size.x, v.y * size.y, v.z * size.z)
		# 先加一点各向异性扰动，避免“完美球”读法。
		p += Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.02, 0.04), rng.randf_range(-0.04, 0.04)) * size
		for plane in planes:
			var n: Vector3 = plane.normal
			var d: float = plane.d
			var dist := p.dot(n)
			if dist > d:
				p -= n * (dist - d)
		shaped.append(p)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := indices.size() if indices.size() > 0 else shaped.size()
	for k in range(0, count, 3):
		var ia: int = indices[k] if indices.size() > 0 else k
		var ib: int = indices[k + 1] if indices.size() > 0 else k + 1
		var ic: int = indices[k + 2] if indices.size() > 0 else k + 2
		var a := shaped[ia]
		var b := shaped[ib]
		var c := shaped[ic]
		var n := (b - a).cross(c - a).normalized()
		if n.length_squared() < 0.1:
			continue
		var center := (a + b + c) / 3.0
		if n.dot(center) < 0.0:
			n = -n
		var edge := 1.0 - maxf(absf(n.x), maxf(absf(n.y), absf(n.z)))
		var chip := 0.5 + 0.5 * sin(float(k) * 7.13 + float(seed_value))
		for p in [a, b, c]:
			st.set_normal(n)
			st.set_color(Color(clampf(0.18 + edge * 0.9, 0.0, 1.0), 0.0, chip, clampf(n.y, 0.0, 1.0)))
			st.add_vertex(p)
	return st.commit()


static func _disc_mesh(radius: float, seed_value: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var segments := 20
	var points: Array[Vector3] = []
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		var r := radius * rng.randf_range(0.78, 1.08)
		points.append(Vector3(cos(angle) * r, 0.0, sin(angle) * r))
	for i in segments:
		var j := (i + 1) % segments
		_tri(st, Vector3.ZERO, points[i], points[j], Vector3.UP)
	return st.commit()
