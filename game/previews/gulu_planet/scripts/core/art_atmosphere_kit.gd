class_name ArtAtmosphereKit
extends RefCounted

## Shared GL-Compatibility-safe atmospheric & grounding kit across Acts 1-5:
## - Radial contact-shadow / grime ground skirts (eliminates hard floor seams)
## - Seeded chamfered gravel/debris batches around heavy plinths
## - Smooth catenary flexible braided hoses with end ferrules (breaks boxy silhouettes)
## - Subtle drifting crystal/dust motes & pulsed steam vents (CPUParticles3D)
## - Soft volumetric-feel light shafts using walle_godray.gdshader (additive Fresnel cone)

const GODRAY_SHADER_PATH := "res://shaders/walle_godray.gdshader"

static var _skirt_tex: Texture2D = null
static var _puff_tex: Texture2D = null
static var _mote_tex: Texture2D = null
static var _godray_shader: Shader = null
static var _mat_cache: Dictionary = {}


static func _ensure_skirt_texture() -> Texture2D:
	if _skirt_tex != null:
		return _skirt_tex
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)
			var jitter := 0.08 * sin(ang * 5.0 + 1.3) + 0.05 * cos(ang * 9.0 - 0.7)
			var rn := clampf(r + jitter * clampf(r, 0.0, 1.0), 0.0, 1.4)
			var falloff := 1.0 - smoothstep(0.18, 0.96, rn)
			var alpha := pow(clampf(falloff, 0.0, 1.0), 1.45)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_skirt_tex = ImageTexture.create_from_image(img)
	return _skirt_tex


static func _ensure_soft_disc(is_mote: bool) -> Texture2D:
	if is_mote and _mote_tex != null:
		return _mote_tex
	if not is_mote and _puff_tex != null:
		return _puff_tex
	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var r := clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
			var a := pow(1.0 - r, 2.2 if is_mote else 1.75)
			if not is_mote:
				var ang := atan2(dy, dx)
				a *= clampf(0.84 + 0.16 * sin(ang * 4.0 + r * 5.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	if is_mote:
		_mote_tex = tex
	else:
		_puff_tex = tex
	return tex


static func _default_hose_mat() -> StandardMaterial3D:
	if _mat_cache.has("hose"):
		return _mat_cache["hose"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.09, 0.10)
	m.metallic = 0.18
	m.roughness = 0.72
	_mat_cache["hose"] = m
	return m


static func _default_ferrule_mat() -> StandardMaterial3D:
	if _mat_cache.has("ferrule"):
		return _mat_cache["ferrule"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.56, 0.44, 0.24)
	m.metallic = 0.78
	m.roughness = 0.34
	_mat_cache["ferrule"] = m
	return m


static func _default_gravel_mat() -> StandardMaterial3D:
	if _mat_cache.has("gravel"):
		return _mat_cache["gravel"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.24, 0.21, 0.18)
	m.metallic = 0.04
	m.roughness = 0.92
	_mat_cache["gravel"] = m
	return m


static func build_ground_skirt(parent: Node3D, base_name: String, center_pos: Vector3,
		size_xz: Vector2, tint: Color = Color(0.055, 0.050, 0.048), opacity: float = 0.58) -> MeshInstance3D:
	var key := "skirt_%s_%.2f" % [tint.to_html(false), opacity]
	var mat: StandardMaterial3D
	if _mat_cache.has(key):
		mat = _mat_cache[key] as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = _ensure_skirt_texture()
		mat.albedo_color = Color(tint.r, tint.g, tint.b, clampf(opacity, 0.05, 0.85))
		_mat_cache[key] = mat

	var mi := MeshInstance3D.new()
	mi.name = base_name
	var pm := PlaneMesh.new()
	pm.size = size_xz
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3(center_pos.x, center_pos.y + 0.012, center_pos.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func build_gravel_cluster(parent: Node3D, base_name: String, center: Vector3,
		radius: float, count: int = 12, seed_id: int = 1, mat: Material = null) -> MeshInstance3D:
	var use_mat := mat if mat != null else _default_gravel_mat()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_id
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(maxi(1, count)):
		var ang := (TAU * float(i) / float(maxi(1, count))) + rng.randf_range(-0.22, 0.22)
		var dist := radius * rng.randf_range(0.68, 1.08)
		var p := Vector3(center.x + cos(ang) * dist, center.y + 0.018, center.z + sin(ang) * dist)
		var sx := rng.randf_range(0.055, 0.145)
		var sy := rng.randf_range(0.024, 0.058)
		var sz := rng.randf_range(0.050, 0.130)
		var yaw := rng.randf_range(0.0, TAU)
		var tilt_x := rng.randf_range(-0.18, 0.18)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt_x)
		var xf := Transform3D(b, p)
		_append_chamfer_chip(st, xf, sx, sy, sz)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = base_name
	mi.mesh = st.commit()
	mi.material_override = use_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _append_chamfer_chip(st: SurfaceTool, xf: Transform3D, sx: float, sy: float, sz: float) -> void:
	var hx := sx * 0.5
	var hy := sy * 0.5
	var hz := sz * 0.5
	var tx := hx * 0.72
	var tz := hz * 0.72
	var v: Array[Vector3] = [
		xf * Vector3(-hx, -hy * 0.4, -hz),
		xf * Vector3(hx, -hy * 0.4, -hz),
		xf * Vector3(hx, -hy * 0.4, hz),
		xf * Vector3(-hx, -hy * 0.4, hz),
		xf * Vector3(-tx, hy, -tz),
		xf * Vector3(tx, hy, -tz),
		xf * Vector3(tx, hy, tz),
		xf * Vector3(-tx, hy, tz),
	]
	var tris := [
		[4, 5, 6], [4, 6, 7],
		[0, 1, 5], [0, 5, 4],
		[1, 2, 6], [1, 6, 5],
		[2, 3, 7], [2, 7, 6],
		[3, 0, 4], [3, 4, 7],
	]
	for t: Array in tris:
		st.add_vertex(v[int(t[0])])
		st.add_vertex(v[int(t[1])])
		st.add_vertex(v[int(t[2])])


static func build_catenary_hose(parent: Node3D, base_name: String, p0: Vector3, p1: Vector3,
		sag: float = 0.28, radius: float = 0.026, mat: Material = null) -> Node3D:
	var root := Node3D.new()
	root.name = base_name
	parent.add_child(root)

	var mid := (p0 + p1) * 0.5 - Vector3(0.0, sag, 0.0)
	var steps := 12
	var sides := 8
	var pts: Array[Vector3] = []
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var omt := 1.0 - t
		pts.append(omt * omt * p0 + 2.0 * omt * t * mid + t * t * p1)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[Array] = []
	for i in range(pts.size()):
		var tang: Vector3
		if i == 0:
			tang = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			tang = (pts[i] - pts[i - 1]).normalized()
		else:
			tang = (pts[i + 1] - pts[i - 1]).normalized()
		if tang.length_squared() < 0.0001:
			tang = Vector3.FORWARD
		var ref := Vector3.UP if absf(tang.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
		var side := tang.cross(ref).normalized()
		var up := side.cross(tang).normalized()
		var ring: Array[Vector3] = []
		for s in range(sides):
			var a := TAU * float(s) / float(sides)
			ring.append(pts[i] + (side * cos(a) + up * sin(a)) * radius)
		rings.append(ring)

	for i in range(rings.size() - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for s in range(sides):
			var sn := (s + 1) % sides
			var a := r0[s] as Vector3
			var b := r0[sn] as Vector3
			var c := r1[sn] as Vector3
			var d := r1[s] as Vector3
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)

	st.generate_normals()
	var hose_mi := MeshInstance3D.new()
	hose_mi.name = "HoseTube"
	hose_mi.mesh = st.commit()
	hose_mi.material_override = mat if mat != null else _default_hose_mat()
	hose_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hose_mi)

	var f_mat := _default_ferrule_mat()
	for idx in range(2):
		var end_p := p0 if idx == 0 else p1
		var end_dir := (pts[1] - pts[0]).normalized() if idx == 0 else (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
		if end_dir.length_squared() < 0.0001:
			end_dir = Vector3.FORWARD
		var fer := MeshInstance3D.new()
		fer.name = "Ferrule_%d" % idx
		var cm := CylinderMesh.new()
		cm.top_radius = radius * 1.48
		cm.bottom_radius = radius * 1.48
		cm.height = radius * 3.2
		cm.radial_segments = 10
		fer.mesh = cm
		fer.material_override = f_mat
		var up_ref := Vector3.UP if absf(end_dir.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
		var x_ax := up_ref.cross(end_dir).normalized()
		var z_ax := x_ax.cross(end_dir).normalized()
		fer.transform = Transform3D(Basis(x_ax, end_dir, z_ax), end_p)
		fer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fer)

	return root


static func build_ambient_motes(parent: Node3D, base_name: String, center: Vector3,
		box_extents: Vector3, color: Color = Color(0.32, 0.88, 1.0),
		amount: int = 20, mote_size: float = 0.055) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = base_name
	p.position = center
	p.amount = maxi(4, amount)
	p.lifetime = 4.6
	p.preprocess = 2.0
	p.randomness = 0.55
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box_extents
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 35.0
	p.initial_velocity_min = 0.04
	p.initial_velocity_max = 0.14
	p.gravity = Vector3(0.0, 0.02, 0.0)
	p.damping_min = 0.04
	p.damping_max = 0.08
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.25

	var qm := QuadMesh.new()
	qm.size = Vector2(mote_size, mote_size)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _ensure_soft_disc(true)
	mat.albedo_color = Color(color.r, color.g, color.b, 0.52)
	qm.material = mat
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


static func build_steam_vent(parent: Node3D, base_name: String, origin: Vector3,
		dir: Vector3 = Vector3.UP, color: Color = Color(0.84, 0.89, 0.94),
		amount: int = 12, puff_size: float = 0.24) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = base_name
	p.position = origin
	p.amount = maxi(4, amount)
	p.lifetime = 2.4
	p.preprocess = 1.0
	p.explosiveness = 0.32
	p.randomness = 0.45
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.06
	var d := dir.normalized() if dir.length_squared() > 0.001 else Vector3.UP
	p.direction = d
	p.spread = 18.0
	p.initial_velocity_min = 0.45
	p.initial_velocity_max = 0.95
	p.gravity = Vector3(0.0, 0.28, 0.0)
	p.damping_min = 0.30
	p.damping_max = 0.55
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.65

	var qm := QuadMesh.new()
	qm.size = Vector2(puff_size, puff_size)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _ensure_soft_disc(false)
	mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	qm.material = mat
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


static func build_godray_cone(parent: Node3D, base_name: String, apex: Vector3,
		dir: Vector3, length: float, top_r: float, bot_r: float,
		color: Color, intensity: float = 0.14) -> MeshInstance3D:
	if _godray_shader == null:
		_godray_shader = load(GODRAY_SHADER_PATH) as Shader
	var d := dir.normalized() if dir.length_squared() > 0.001 else Vector3.DOWN
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = maxf(0.4, length)
	cm.radial_segments = 16
	cm.rings = 2
	cm.cap_top = false
	cm.cap_bottom = false

	var mi := MeshInstance3D.new()
	mi.name = base_name
	mi.mesh = cm
	if _godray_shader != null:
		var sm := ShaderMaterial.new()
		sm.shader = _godray_shader
		sm.set_shader_parameter("beam_color", Color(color.r, color.g, color.b, 1.0))
		sm.set_shader_parameter("intensity", clampf(intensity, 0.02, 0.40))
		sm.set_shader_parameter("soft_power", 2.2)
		mi.material_override = sm
	# CylinderMesh +Y runs bottom -> top; align -Y along beam direction d
	var y_ax := -d
	var up_ref := Vector3.FORWARD if absf(y_ax.dot(Vector3.FORWARD)) < 0.92 else Vector3.RIGHT
	var x_ax := up_ref.cross(y_ax).normalized()
	var z_ax := x_ax.cross(y_ax).normalized()
	mi.transform = Transform3D(Basis(x_ax, y_ax, z_ax), apex + d * (length * 0.5))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
