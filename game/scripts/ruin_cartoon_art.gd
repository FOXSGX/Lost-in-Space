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

const CREAM := Color("#bda887")
const CREAM_DEEP := Color("#937c5e")
const CREAM_LIGHT := Color("#cfb999")
const TEAL := Color("#27525b")
const TEAL_DEEP := Color("#17343b")
const TEAL_LIGHT := Color("#5f8f91")
const ORANGE := Color("#a8612f")
const ORANGE_DEEP := Color("#7e441e")
const CORAL := Color("#8f493c")
const SAGE := Color("#5b7458")
const SAGE_DEEP := Color("#40573e")
const SAND := Color("#7d684b")
const SAND_DEEP := Color("#625139")
const INK := Color("#14252b")
const GLASS := Color("#527d80")
const GLASS_LIGHT := Color("#82a5a3")
const LAMP := Color("#e6b26d")

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


static func block(parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color, bevel := 0.12, emissive := false, energy := 0.6) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = chamfer_box(size, bevel)
	instance.position = position
	instance.material_override = material(color, emissive, energy)
	parent.add_child(instance)
	return instance


static func box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color, emissive := false, energy := 0.6) -> MeshInstance3D:
	return block(parent, node_name, size, position, color, 0.001, emissive, energy)


## 水平面片：法线固定 +Y，适合铺地、道路和斑马线。
## 比压扁的倒角盒更可靠，不会因为顶面绕序或倒角把整块地面压暗。
static func plane(parent: Node3D, node_name: String, size: Vector2, position: Vector3, color: Color, emissive := false, energy := 0.4) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := PlaneMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material(color, emissive, energy)
	parent.add_child(instance)
	return instance


static func sphere(parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color, emissive := false, energy := 0.5) -> MeshInstance3D:
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
	instance.material_override = material(color, emissive, energy)
	parent.add_child(instance)
	return instance


static func cylinder(parent: Node3D, node_name: String, radius: float, height: float, position: Vector3, color: Color, emissive := false, energy := 0.5) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 18
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material(color, emissive, energy)
	parent.add_child(instance)
	return instance


static func cone(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 18
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material(color, false, 0.0)
	parent.add_child(instance)
	return instance


static func torus(parent: Node3D, node_name: String, inner: float, outer: float, position: Vector3, color: Color, emissive := false, energy := 0.7) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 28
	mesh.ring_segments = 8
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material(color, emissive, energy)
	parent.add_child(instance)
	return instance


static func material(color: Color, emissive := false, energy := 0.6) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# 调色板按美术稿的 sRGB 十六进制写；渲染器把 albedo 当线性色，
	# 不转换的话中间调会被整体提亮，路面和地面会发白。
	var linear := color.srgb_to_linear()
	mat.albedo_color = Color(linear.r, linear.g, linear.b, color.a)
	mat.roughness = 0.86
	mat.metallic = 0.0
	# 倒角网格的顶点绕序由参数决定，关闭背面剔除避免个别斜面消失。
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		mat.emission_enabled = true
		mat.emission = linear
		mat.emission_energy_multiplier = energy
	return mat


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

## 一盏路灯：深青底座 + 奶油灯杆 + 暖橙灯罩。
static func street_lamp(parent: Node3D, position: Vector3, height := 4.0) -> Node3D:
	var root := Node3D.new()
	root.name = "StreetLamp"
	root.position = position
	parent.add_child(root)
	cylinder(root, "Base", 0.2, 0.26, Vector3(0.0, 0.13, 0.0), TEAL_DEEP)
	cylinder(root, "Pole", 0.055, height, Vector3(0.0, height * 0.5 + 0.2, 0.0), CREAM)
	cylinder(root, "Collar", 0.085, 0.12, Vector3(0.0, 0.3, 0.0), ORANGE)
	var arm := cylinder(root, "Arm", 0.045, 0.62, Vector3(0.31, height + 0.08, 0.0), CREAM)
	arm.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	sphere(root, "Lamp", Vector3(0.3, 0.24, 0.3), Vector3(0.62, height, 0.0), LAMP, true, 1.2)
	cone(root, "Cap", 0.06, 0.2, 0.16, Vector3(0.62, height + 0.16, 0.0), TEAL_DEEP)
	return root


## 方形花坛：奶油槽体 + 深色土 + 两三团鼠尾草绿灌木。
static func planter(parent: Node3D, position: Vector3, size := 1.5, seed_value := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Planter"
	root.position = position
	parent.add_child(root)
	block(root, "Pot", Vector3(size, 0.62, size), Vector3(0.0, 0.31, 0.0), CREAM, 0.1)
	block(root, "Rim", Vector3(size + 0.12, 0.1, size + 0.12), Vector3(0.0, 0.6, 0.0), ORANGE, 0.05)
	box(root, "Soil", Vector3(size - 0.18, 0.05, size - 0.18), Vector3(0.0, 0.65, 0.0), SAND_DEEP)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index: int in 3:
		var offset := Vector3(rng.randf_range(-0.33, 0.33) * size, 0.78 + rng.randf_range(0.0, 0.18), rng.randf_range(-0.33, 0.33) * size)
		var radius := rng.randf_range(0.28, 0.42) * size
		sphere(root, "Shrub%d" % index, Vector3(radius, radius * 0.9, radius), offset, SAGE if index % 2 == 0 else SAGE_DEEP)
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


## 一棵卡通树：暖棕树干 + 三团青绿树冠。
static func tree(parent: Node3D, position: Vector3, seed_value := 1, scale_factor := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Tree"
	root.position = position
	root.scale = Vector3.ONE * scale_factor
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	cylinder(root, "Trunk", 0.13, 2.1, Vector3(0.0, 1.05, 0.0), Color("#9c7048"))
	for index: int in 3:
		var radius := rng.randf_range(0.85, 1.2)
		var offset := Vector3(rng.randf_range(-0.35, 0.35), 2.2 + index * 0.36, rng.randf_range(-0.35, 0.35))
		sphere(root, "Crown%d" % index, Vector3(radius, radius * 0.92, radius), offset, SAGE if index != 1 else SAGE_DEEP)
	return root


static func bollard(parent: Node3D, position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Bollard"
	root.position = position
	parent.add_child(root)
	cylinder(root, "Post", 0.11, 0.72, Vector3(0.0, 0.36, 0.0), ORANGE)
	cylinder(root, "Band", 0.115, 0.08, Vector3(0.0, 0.55, 0.0), CREAM)
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
