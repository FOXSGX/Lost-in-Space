extends RefCounted
class_name ArtAtmosphereKit

## 接地、悬垂软管、假体积光束与蒸汽微粒套件（消除“模型展览馆摆拍感”）
## 严格适配 Godot 4.7 gl_compatibility（不依赖 SSR / SSIL / VolumetricFog）

const GODRAY_SHADER: Shader = preload("res://shaders/hub_godray.gdshader")
static var _skirt_tex: ImageTexture = null

## 在重型设备/建筑/岩脚铺径向接触暗晕贴片，消除生硬直角插地感
static func build_ground_skirt(parent: Node3D, pos: Vector3, radius: float, alpha: float = 0.42) -> MeshInstance3D:
	if _skirt_tex == null:
		var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y: int in 64:
			for x: int in 64:
				var u: float = (float(x) / 63.0 - 0.5) * 2.0
				var v: float = (float(y) / 63.0 - 0.5) * 2.0
				var d: float = clampf(sqrt(u * u + v * v), 0.0, 1.0)
				var a: float = pow(1.0 - d, 2.2)
				img.set_pixel(x, y, Color(0.03, 0.05, 0.07, a))
		_skirt_tex = ImageTexture.create_from_image(img)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = _skirt_tex
	mat.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "GroundSkirt"
	mi.mesh = quad
	mi.material_override = mat
	mi.position = pos + Vector3(0.0, 0.015, 0.0)
	mi.rotation_degrees.x = -90.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## 在两个挂点间拉自然重力悬链线软管，打破呆板横平竖直外轮廓
static func build_catenary_hose(parent: Node3D, a: Vector3, b: Vector3, sag: float = 0.45, radius: float = 0.038, color: Color = Color("#181e24")) -> MeshInstance3D:
	var segs: int = 12
	var sides: int = 7
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i: int in range(segs + 1):
		var t: float = float(i) / float(segs)
		var p: Vector3 = a.lerp(b, t)
		p.y -= sin(t * PI) * sag
		pts.append(p)
	var rings: Array = []
	for i: int in range(pts.size()):
		var tang: Vector3
		if i == 0:
			tang = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			tang = (pts[i] - pts[i - 1]).normalized()
		else:
			tang = (pts[i + 1] - pts[i - 1]).normalized()
		var up_ref: Vector3 = Vector3.UP if absf(tang.y) < 0.9 else Vector3.RIGHT
		var right: Vector3 = tang.cross(up_ref).normalized()
		var up: Vector3 = right.cross(tang).normalized()
		var ring: Array[Vector3] = []
		for s: int in sides:
			var ang: float = TAU * float(s) / float(sides)
			ring.append(pts[i] + (right * cos(ang) + up * sin(ang)) * radius)
		rings.append(ring)
	for i: int in range(segs):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for s: int in sides:
			var s2: int = (s + 1) % sides
			st.add_vertex(r0[s]); st.add_vertex(r1[s]); st.add_vertex(r1[s2])
			st.add_vertex(r0[s]); st.add_vertex(r1[s2]); st.add_vertex(r0[s2])
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "CatenaryHose"
	mi.mesh = st.commit()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.metallic = 0.12
	mi.material_override = mat
	parent.add_child(mi)
	return mi

## 克制的假体积光束（intensity 严控 <= 0.12）
static func build_godray_cone(parent: Node3D, top_pos: Vector3, height: float, top_r: float, bottom_r: float, tint: Color = Color("#bfe4ff"), energy: float = 0.10) -> MeshInstance3D:
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bottom_r
	cyl.height = height
	cyl.radial_segments = 16
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = GODRAY_SHADER
	mat.set_shader_parameter("ray_color", tint)
	mat.set_shader_parameter("intensity", clampf(energy, 0.02, 0.14))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "GodrayCone"
	mi.mesh = cyl
	mi.position = top_pos - Vector3(0.0, height * 0.5, 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## 地热喷汽 / 气闸泄压蒸汽粒子
static func build_steam_vent(parent: Node3D, pos: Vector3, tint: Color = Color(0.86, 0.94, 1.0, 0.35), strength: float = 1.0) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.name = "SteamVent"
	p.position = pos
	p.amount = int(18 * strength)
	p.lifetime = 2.4
	p.randomness = 0.45
	p.local_coords = false
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 14.0
	p.gravity = Vector3(0.18, 0.65 * strength, 0.10)
	p.initial_velocity_min = 1.4 * strength
	p.initial_velocity_max = 3.2 * strength
	p.scale_amount_min = 0.18 * strength
	p.scale_amount_max = 0.72 * strength
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 6
	sm.rings = 4
	p.mesh = sm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = mat
	parent.add_child(p)
	return p
