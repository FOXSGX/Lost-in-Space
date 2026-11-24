class_name PhysicalLinkKit
extends RefCounted

## Shared visual kit for clear physical causal links across Acts 1-5:
## - Dynamic energy/hydraulic/signal conduit runs (red=blocked, amber=ready, cyan=active)
## - Machine-mounted status indicator bulbs
## - Non-floating schematic diagram plaques rendered onto procedural ImageTextures
##   (no Label3D / no billboard floating 3D text).

const ENERGY_SHADER := preload("res://shaders/conduit_flow.gdshader")


static func make_flow_material(col: Color = Color(0.0, 0.94, 1.0), energy: float = 1.4, speed: float = 1.2, stripes: float = 1.15) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ENERGY_SHADER
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("energy", energy)
	# Normalize legacy large stripe counts (4..10) into meters^-1 (~1.0..1.5 cycles/m)
	var freq := stripes if stripes <= 2.5 else clampf(stripes * 0.16, 0.85, 1.55)
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("stripe_scale", freq)
	mat.set_shader_parameter("pulse", 0.15)
	return mat


static func set_flow_state(mat: ShaderMaterial, state: String, custom_col: Color = Color(-1.0, 0.0, 0.0)) -> void:
	if mat == null:
		return
	var col: Color = custom_col
	match state:
		"active", "powered", "aligned", "ok":
			if col.r < 0.0:
				col = Color(0.05, 0.92, 1.0)
			mat.set_shader_parameter("color", col)
			mat.set_shader_parameter("energy", 1.85)
			mat.set_shader_parameter("speed", 1.55)
			mat.set_shader_parameter("pulse", 0.25)
		"ready", "waiting", "amber":
			if col.r < 0.0:
				col = Color(1.0, 0.62, 0.10)
			mat.set_shader_parameter("color", col)
			mat.set_shader_parameter("energy", 1.35)
			mat.set_shader_parameter("speed", 0.85)
			mat.set_shader_parameter("pulse", 0.35)
		"surge", "overload":
			if col.r < 0.0:
				col = Color(1.0, 0.28, 0.08)
			mat.set_shader_parameter("color", col)
			mat.set_shader_parameter("energy", 2.15)
			mat.set_shader_parameter("speed", 2.30)
			mat.set_shader_parameter("pulse", 0.65)
		"idle_dim":
			if col.r < 0.0:
				col = Color(0.16, 0.56, 0.66)
			mat.set_shader_parameter("color", col)
			mat.set_shader_parameter("energy", 0.65)
			mat.set_shader_parameter("speed", 0.35)
			mat.set_shader_parameter("pulse", 0.10)
		_:
			# locked / off / blocked / fault
			if col.r < 0.0:
				col = Color(0.96, 0.14, 0.10)
			mat.set_shader_parameter("color", col)
			mat.set_shader_parameter("energy", 0.85)
			mat.set_shader_parameter("speed", 0.28)
			mat.set_shader_parameter("pulse", 0.40)


static func make_lamp_material(col: Color = Color(1.0, 0.10, 0.08), energy: float = 1.2) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.22
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	return mat


static func set_lamp_state(mat: StandardMaterial3D, state: String, custom_col: Color = Color(-1.0, 0.0, 0.0)) -> void:
	if mat == null:
		return
	var col: Color = custom_col
	var energy := 1.2
	match state:
		"active", "powered", "aligned", "ok":
			if col.r < 0.0:
				col = Color(0.0, 0.95, 0.65)
			energy = 1.65
		"ready", "waiting", "amber":
			if col.r < 0.0:
				col = Color(1.0, 0.56, 0.04)
			energy = 1.45
		"off":
			if col.r < 0.0:
				col = Color(0.14, 0.16, 0.18)
			energy = 0.06
		_:
			if col.r < 0.0:
				col = Color(1.0, 0.08, 0.06)
			energy = 1.35
	mat.albedo_color = col
	mat.emission = col
	mat.emission_energy_multiplier = energy


static func build_status_lamp(parent: Node3D, base_name: String, pos: Vector3, radius: float = 0.085, housing_mat: Material = null) -> StandardMaterial3D:
	var holder := Node3D.new()
	holder.name = base_name + "_Lamp"
	holder.position = pos
	parent.add_child(holder)

	var h_mat: Material = housing_mat
	if h_mat == null:
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.14, 0.15, 0.17)
		hm.metallic = 0.65
		hm.roughness = 0.45
		h_mat = hm

	var bezel := MeshInstance3D.new()
	bezel.name = base_name + "_LampBezel"
	var bm := CylinderMesh.new()
	bm.top_radius = radius * 1.30
	bm.bottom_radius = radius * 1.44
	bm.height = radius * 0.62
	bm.radial_segments = 14
	bezel.mesh = bm
	bezel.material_override = h_mat
	bezel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(bezel)

	# Slotted protective hood collar around lower bulb rim for contrast in bright rooms
	var hood := MeshInstance3D.new()
	hood.name = base_name + "_LampHood"
	var hdm := CylinderMesh.new()
	hdm.top_radius = radius * 1.18
	hdm.bottom_radius = radius * 1.24
	hdm.height = radius * 0.36
	hdm.radial_segments = 14
	hood.mesh = hdm
	hood.material_override = h_mat
	hood.position = Vector3(0.0, radius * 0.42, 0.0)
	hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(hood)

	var bulb := MeshInstance3D.new()
	bulb.name = base_name + "_LampGlow"
	var sm := SphereMesh.new()
	sm.radius = radius * 0.96
	sm.height = radius * 1.72
	sm.radial_segments = 14
	sm.rings = 8
	bulb.mesh = sm
	var mat := make_lamp_material()
	bulb.material_override = mat
	bulb.position = Vector3(0.0, radius * 0.48, 0.0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(bulb)
	return mat


static func build_conduit_run(
	parent: Node3D,
	base_name: String,
	points: Array[Vector3],
	radius: float,
	jacket_mat: Material,
	flow_mat: ShaderMaterial,
	glow_offset: Vector3 = Vector3(0.0, 0.04, 0.0),
	add_collars: bool = true
) -> Node3D:
	var group := Node3D.new()
	group.name = base_name + "_WireRun"
	parent.add_child(group)
	if points.size() < 2:
		return group

	var has_armor: bool = radius > 0.001 and jacket_mat != null
	var eff_radius: float = radius if has_armor else 0.030
	var raw_pts: Array[Vector3] = []
	for p: Vector3 in points:
		raw_pts.append(p if has_armor else (p + glow_offset))

	var path: Array[Vector3] = _fillet_polyline(raw_pts, clampf(eff_radius * 4.5, 0.12, 0.28))
	if path.size() < 2:
		return group

	var frames: Array[Dictionary] = _compute_path_frames(path)

	# 1. Continuous smooth plasma/glass core (UV.y authored in meters for seamless pulse travel)
	if flow_mat != null:
		var core_r: float = maxf(eff_radius * 0.64, 0.020) if has_armor else eff_radius
		var core_mi := MeshInstance3D.new()
		core_mi.name = base_name + "_Core"
		core_mi.mesh = _build_swept_tube(frames, core_r, 12, Vector3.ZERO)
		core_mi.material_override = flow_mat
		core_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(core_mi)

	# 2. Triple armored containment rails cradling the glowing core (left/right/bottom)
	if has_armor:
		var armor_st := SurfaceTool.new()
		armor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rail_r: float = maxf(eff_radius * 0.30, 0.010)
		_append_swept_tube(armor_st, frames, rail_r, 8, Vector3(eff_radius * 0.72, 0.0, 0.0))
		_append_swept_tube(armor_st, frames, rail_r, 8, Vector3(-eff_radius * 0.72, 0.0, 0.0))
		_append_swept_tube(armor_st, frames, rail_r * 1.08, 8, Vector3(0.0, -eff_radius * 0.66, 0.0))
		var armor_mi := MeshInstance3D.new()
		armor_mi.name = base_name + "_Armor"
		armor_mi.mesh = armor_st.commit()
		armor_mi.material_override = jacket_mat
		armor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(armor_mi)

		# 3. Machined coupling collars, end socket flanges, & floor saddle brackets
		if add_collars or eff_radius >= 0.032:
			_add_machined_collars(group, base_name, frames, eff_radius, jacket_mat, flow_mat)

	return group


static func _fillet_polyline(points: Array[Vector3], corner_r: float) -> Array[Vector3]:
	var clean: Array[Vector3] = []
	for p: Vector3 in points:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.018:
			clean.append(p)
	if clean.size() < 2:
		return clean

	var out: Array[Vector3] = [clean[0]]
	for i: int in range(1, clean.size() - 1):
		var prev_p: Vector3 = clean[i - 1]
		var curr_p: Vector3 = clean[i]
		var next_p: Vector3 = clean[i + 1]
		var in_seg: Vector3 = curr_p - prev_p
		var out_seg: Vector3 = next_p - curr_p
		var len_in: float = in_seg.length()
		var len_out: float = out_seg.length()
		var d_in: Vector3 = in_seg / len_in
		var d_out: Vector3 = out_seg / len_out
		if d_in.dot(d_out) > 0.996:
			out.append(curr_p)
			continue
		var trim: float = minf(corner_r, minf(len_in * 0.42, len_out * 0.42))
		var a: Vector3 = curr_p - d_in * trim
		var b: Vector3 = curr_p + d_out * trim
		for s: int in range(5):
			var u: float = float(s) / 4.0
			var q: Vector3 = a.lerp(curr_p, u).lerp(curr_p.lerp(b, u), u)
			if out[out.size() - 1].distance_to(q) > 0.008:
				out.append(q)
	if out[out.size() - 1].distance_to(clean[clean.size() - 1]) > 0.008:
		out.append(clean[clean.size() - 1])
	return out


static func _compute_path_frames(path: Array[Vector3]) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var n_pts: int = path.size()
	var prev_tan: Vector3 = (path[1] - path[0]).normalized()
	var ref_up: Vector3 = Vector3.UP if absf(prev_tan.dot(Vector3.UP)) < 0.92 else Vector3.FORWARD
	var side: Vector3 = prev_tan.cross(ref_up).normalized()
	var up_dir: Vector3 = side.cross(prev_tan).normalized()
	var dist: float = 0.0

	for i: int in range(n_pts):
		if i > 0:
			dist += path[i].distance_to(path[i - 1])
		var tan_dir: Vector3
		if i == 0:
			tan_dir = (path[1] - path[0]).normalized()
		elif i == n_pts - 1:
			tan_dir = (path[n_pts - 1] - path[n_pts - 2]).normalized()
		else:
			var t0: Vector3 = (path[i] - path[i - 1]).normalized()
			var t1: Vector3 = (path[i + 1] - path[i]).normalized()
			var sum_t: Vector3 = t0 + t1
			tan_dir = sum_t.normalized() if sum_t.length_squared() > 1e-5 else t1

		# Prefer keeping side horizontal on horizontal/sloped spans so armor rails stay left/right
		var proj_up: Vector3 = Vector3.UP - tan_dir * tan_dir.dot(Vector3.UP)
		if proj_up.length() > 0.25:
			up_dir = proj_up.normalized()
			side = tan_dir.cross(up_dir).normalized()
		else:
			if i > 0:
				var rot: Quaternion = Quaternion(prev_tan, tan_dir)
				side = (rot * side).normalized()
				side = (side - tan_dir * side.dot(tan_dir)).normalized()
			up_dir = side.cross(tan_dir).normalized()

		prev_tan = tan_dir
		frames.append({
			"pos": path[i],
			"tan": tan_dir,
			"side": side,
			"up": up_dir,
			"dist": dist,
		})
	return frames


static func _build_swept_tube(frames: Array[Dictionary], radius: float, sides: int, local_offset: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_swept_tube(st, frames, radius, sides, local_offset)
	return st.commit()


static func _append_swept_tube(st: SurfaceTool, frames: Array[Dictionary], radius: float, sides: int, local_offset: Vector3) -> void:
	var n_frames: int = frames.size()
	if n_frames < 2:
		return

	var rings: Array[Array] = []
	for f_idx: int in range(n_frames):
		var f: Dictionary = frames[f_idx]
		var center: Vector3 = (f["pos"] as Vector3) + (f["side"] as Vector3) * local_offset.x + (f["up"] as Vector3) * local_offset.y
		var side: Vector3 = f["side"] as Vector3
		var up: Vector3 = f["up"] as Vector3
		var ring_pts: Array[Vector3] = []
		var ring_nrms: Array[Vector3] = []
		for s: int in range(sides):
			var ang: float = TAU * float(s) / float(sides)
			var nrm: Vector3 = (side * cos(ang) + up * sin(ang)).normalized()
			ring_pts.append(center + nrm * radius)
			ring_nrms.append(nrm)
		rings.append([ring_pts, ring_nrms, float(f["dist"])])

	for i: int in range(n_frames - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var p0: Array = r0[0] as Array
		var n0: Array = r0[1] as Array
		var d0: float = float(r0[2])
		var p1: Array = r1[0] as Array
		var n1: Array = r1[1] as Array
		var d1: float = float(r1[2])

		for s: int in range(sides):
			var sn: int = (s + 1) % sides
			var u0: float = float(s) / float(sides)
			var u1: float = float(s + 1) / float(sides)
			var v00: Vector3 = p0[s] as Vector3
			var v01: Vector3 = p0[sn] as Vector3
			var v10: Vector3 = p1[s] as Vector3
			var v11: Vector3 = p1[sn] as Vector3
			var nm00: Vector3 = n0[s] as Vector3
			var nm01: Vector3 = n0[sn] as Vector3
			var nm10: Vector3 = n1[s] as Vector3
			var nm11: Vector3 = n1[sn] as Vector3

			st.set_normal(nm00)
			st.set_uv(Vector2(u0, d0))
			st.add_vertex(v00)
			st.set_normal(nm10)
			st.set_uv(Vector2(u0, d1))
			st.add_vertex(v10)
			st.set_normal(nm11)
			st.set_uv(Vector2(u1, d1))
			st.add_vertex(v11)

			st.set_normal(nm00)
			st.set_uv(Vector2(u0, d0))
			st.add_vertex(v00)
			st.set_normal(nm11)
			st.set_uv(Vector2(u1, d1))
			st.add_vertex(v11)
			st.set_normal(nm01)
			st.set_uv(Vector2(u1, d0))
			st.add_vertex(v01)


static func _add_machined_collars(group: Node3D, base_name: String, frames: Array[Dictionary], eff_radius: float, collar_mat: Material, glow_mat: ShaderMaterial = null) -> void:
	var n: int = frames.size()
	if n < 2:
		return
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = eff_radius * 1.18
	ring_mesh.bottom_radius = eff_radius * 1.18
	ring_mesh.height = maxf(eff_radius * 1.75, 0.072)
	ring_mesh.radial_segments = 14

	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = eff_radius * 1.24
	band_mesh.bottom_radius = eff_radius * 1.24
	band_mesh.height = maxf(eff_radius * 0.42, 0.020)
	band_mesh.radial_segments = 14

	var flange_mesh := CylinderMesh.new()
	flange_mesh.top_radius = eff_radius * 1.56
	flange_mesh.bottom_radius = eff_radius * 1.62
	flange_mesh.height = maxf(eff_radius * 1.20, 0.048)
	flange_mesh.radial_segments = 12

	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(eff_radius * 2.9, maxf(eff_radius * 0.75, 0.030), maxf(eff_radius * 1.4, 0.055))

	var last_dist: float = -10.0
	var collar_idx: int = 0
	for i: int in range(n):
		var f: Dictionary = frames[i]
		var dist: float = float(f["dist"])
		var tan_dir: Vector3 = f["tan"] as Vector3
		var prev_tan: Vector3 = frames[maxi(i - 1, 0)]["tan"] as Vector3
		var corner_change: bool = i > 0 and tan_dir.dot(prev_tan) < 0.965
		var is_end: bool = (i == 0 or i == n - 1)
		if not is_end and not corner_change and (dist - last_dist) < 2.2:
			continue
		if not is_end and (dist - last_dist) < 0.45:
			continue
		last_dist = dist

		var pos: Vector3 = f["pos"] as Vector3
		var side: Vector3 = f["side"] as Vector3
		var up: Vector3 = f["up"] as Vector3
		var xform := Transform3D(Basis(side, tan_dir, side.cross(tan_dir).normalized()), pos)

		var collar := MeshInstance3D.new()
		collar.name = "%s_WireClamp_%d" % [base_name, collar_idx]
		collar.mesh = flange_mesh if is_end else ring_mesh
		collar.material_override = collar_mat
		collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		collar.transform = xform
		group.add_child(collar)

		# Embedded state tracer band inside collar
		if glow_mat != null:
			var band := MeshInstance3D.new()
			band.name = "%s_WireClampBand_%d" % [base_name, collar_idx]
			band.mesh = band_mesh
			band.material_override = glow_mat
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			band.transform = xform
			group.add_child(band)

		# Floor saddle clamp for grounded horizontal runs
		if not is_end and absf(tan_dir.y) < 0.25 and pos.y < 0.25:
			var foot := MeshInstance3D.new()
			foot.name = "%s_WireClampFoot_%d" % [base_name, collar_idx]
			foot.mesh = foot_mesh
			foot.material_override = collar_mat
			foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			foot.transform = Transform3D(Basis(side, up, tan_dir), pos - up * (eff_radius * 0.55))
			group.add_child(foot)

		collar_idx += 1


static func build_live_dial(
	parent: Node3D,
	base_name: String,
	pos: Vector3,
	rot_deg: Vector3,
	radius: float = 0.16,
	green_min: float = 0.58,
	green_max: float = 1.0
) -> Node3D:
	## Builds a physical industrial analog gauge with a green target arc and
	## returns its NeedlePivot Node3D (drive via set_dial_value(pivot, ratio)).
	var root := Node3D.new()
	root.name = base_name + "_Dial"
	root.position = pos
	root.rotation_degrees = rot_deg
	parent.add_child(root)

	var casing := MeshInstance3D.new()
	casing.name = base_name + "_DialCase"
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 1.12
	cm.bottom_radius = radius * 1.16
	cm.height = 0.055
	cm.radial_segments = 18
	casing.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.14, 0.16, 0.18)
	cmat.metallic = 0.72
	cmat.roughness = 0.42
	casing.material_override = cmat
	casing.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	casing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(casing)

	var face_tex := _render_dial_texture(green_min, green_max)
	var face := MeshInstance3D.new()
	face.name = base_name + "_DialFace"
	var fm := QuadMesh.new()
	fm.size = Vector2(radius * 1.92, radius * 1.92)
	face.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_texture = face_tex
	fmat.emission_enabled = true
	fmat.emission_texture = face_tex
	fmat.emission_energy_multiplier = 0.65
	fmat.roughness = 0.40
	face.material_override = fmat
	face.position = Vector3(0.0, 0.0, 0.030)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(face)

	var pivot := Node3D.new()
	pivot.name = base_name + "_NeedlePivot"
	pivot.position = Vector3(0.0, 0.0, 0.036)
	root.add_child(pivot)

	var hand := MeshInstance3D.new()
	hand.name = base_name + "_Needle"
	var hm := BoxMesh.new()
	hm.size = Vector3(radius * 0.08, radius * 0.78, 0.008)
	hand.mesh = hm
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(1.0, 0.36, 0.12)
	nmat.emission_enabled = true
	nmat.emission = Color(1.0, 0.36, 0.12)
	nmat.emission_energy_multiplier = 1.2
	hand.material_override = nmat
	hand.position = Vector3(0.0, radius * 0.30, 0.0)
	hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(hand)

	var hub := MeshInstance3D.new()
	hub.name = base_name + "_Hub"
	var hbm := CylinderMesh.new()
	hbm.top_radius = radius * 0.14
	hbm.bottom_radius = radius * 0.14
	hbm.height = 0.016
	hbm.radial_segments = 12
	hub.mesh = hbm
	hub.material_override = cmat
	hub.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	hub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(hub)

	set_dial_value(pivot, 0.0)
	return pivot


static func set_dial_value(pivot: Node3D, ratio: float) -> void:
	if pivot == null:
		return
	var r: float = clampf(ratio, 0.0, 1.0)
	# Sweeps clockwise from +120 deg (bottom-left) through 0 deg (top) to -120 deg (bottom-right)
	pivot.rotation_degrees.z = lerpf(120.0, -120.0, r)


static func _render_dial_texture(green_min: float, green_max: float) -> ImageTexture:
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var cx: float = float(sz) * 0.5
	var cy: float = float(sz) * 0.5
	for py: int in range(sz):
		for px: int in range(sz):
			var dx: float = float(px) - cx
			var dy: float = float(py) - cy
			var r: float = sqrt(dx * dx + dy * dy)
			if r > 60.0:
				continue
			img.set_pixel(px, py, Color(0.07, 0.09, 0.11, 1.0))
			if r >= 40.0 and r <= 54.0:
				var ang: float = atan2(dx, -dy)
				var deg: float = rad_to_deg(ang)
				if deg >= -124.0 and deg <= 124.0:
					var t: float = (deg + 120.0) / 240.0
					if t >= green_min and t <= green_max:
						img.set_pixel(px, py, Color(0.10, 0.92, 0.56, 1.0))
					elif t < green_min * 0.65 or t > minf(1.0, green_max + 0.15):
						img.set_pixel(px, py, Color(0.92, 0.22, 0.14, 1.0))
					else:
						img.set_pixel(px, py, Color(0.96, 0.64, 0.16, 1.0))
	# Radial tick marks
	for k: int in range(9):
		var deg_t: float = lerpf(-120.0, 120.0, float(k) / 8.0)
		var rad_t: float = deg_to_rad(deg_t)
		var x0: int = roundi(cx + sin(rad_t) * 34.0)
		var y0: int = roundi(cy - cos(rad_t) * 34.0)
		var x1: int = roundi(cx + sin(rad_t) * 56.0)
		var y1: int = roundi(cy - cos(rad_t) * 56.0)
		_line(img, x0, y0, x1, y1, 2, Color(0.82, 0.88, 0.92, 1.0))
	return ImageTexture.create_from_image(img)


static func build_diagram_plaque(
	parent: Node3D,
	base_name: String,
	pos: Vector3,
	rot_deg: Vector3,
	size: Vector2,
	steps: Array,
	accent: Color = Color(0.26, 0.88, 1.0)
) -> Node3D:
	## Mounts a solid steel schematic plaque with a procedural vector-icon ImageTexture
	## depicting numbered causal steps (e.g. [{"num":1,"icon":"plug","col":...}, ...]).
	var root := Node3D.new()
	root.name = base_name + "_Plaque"
	root.position = pos
	root.rotation_degrees = rot_deg
	parent.add_child(root)

	var frame := MeshInstance3D.new()
	frame.name = base_name + "_PlaqueFrame"
	var fm := BoxMesh.new()
	fm.size = Vector3(size.x + 0.08, size.y + 0.08, 0.03)
	frame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.11, 0.125, 0.14)
	fmat.metallic = 0.65
	fmat.roughness = 0.55
	frame.material_override = fmat
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(frame)

	var tex := _render_diagram_texture(steps, accent)
	var face := MeshInstance3D.new()
	face.name = base_name + "_PlaqueFace"
	var qm := QuadMesh.new()
	qm.size = size
	face.mesh = qm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_texture = tex
	pmat.emission_enabled = true
	pmat.emission_texture = tex
	pmat.emission_energy_multiplier = 0.65
	pmat.roughness = 0.45
	face.material_override = pmat
	face.position = Vector3(0.0, 0.0, 0.018)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(face)
	return root


static func _render_diagram_texture(steps: Array, accent: Color) -> ImageTexture:
	var w := 320
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg := Color(0.06, 0.08, 0.10, 1.0)
	var panel := Color(0.10, 0.13, 0.16, 1.0)
	var border := accent
	img.fill(bg)
	_rect_outline(img, 4, 4, w - 8, h - 8, 2, border)
	_rect_fill(img, 10, 10, w - 20, h - 20, panel)

	var n := maxi(steps.size(), 1)
	var pad_x := 16
	var usable_w := w - pad_x * 2
	var step_w := usable_w / n
	for i: int in range(n):
		var st: Dictionary = steps[i] as Dictionary
		var cx := pad_x + int((float(i) + 0.5) * float(step_w))
		var cy := h / 2 + 6
		var scol: Color = st.get("col", accent)
		var box_w := mini(step_w - 18, 66)
		var box_h := 72
		_rect_outline(img, cx - box_w / 2, cy - box_h / 2, box_w, box_h, 2, scol)
		# Number badge at top of box
		var num := int(st.get("num", i + 1))
		_draw_digit(img, cx - 5, cy - box_h / 2 + 6, num, scol)
		# Geometric silhouette icon in center
		_draw_icon(img, cx, cy + 8, str(st.get("icon", "gear")), scol)
		# Arrow to next step
		if i < n - 1:
			var ax0 := cx + box_w / 2 + 2
			var ax1 := cx + step_w - box_w / 2 - 2
			if ax1 > ax0 + 4:
				_draw_arrow(img, ax0, cy, ax1, cy, Color(0.95, 0.78, 0.30))

	return ImageTexture.create_from_image(img)


static func _rect_fill(img: Image, x0: int, y0: int, rw: int, rh: int, c: Color) -> void:
	for y in range(maxi(0, y0), mini(img.get_height(), y0 + rh)):
		for x in range(maxi(0, x0), mini(img.get_width(), x0 + rw)):
			img.set_pixel(x, y, c)


static func _rect_outline(img: Image, x0: int, y0: int, rw: int, rh: int, t: int, c: Color) -> void:
	_rect_fill(img, x0, y0, rw, t, c)
	_rect_fill(img, x0, y0 + rh - t, rw, t, c)
	_rect_fill(img, x0, y0, t, rh, c)
	_rect_fill(img, x0 + rw - t, y0, t, rh, c)


static func _line(img: Image, x0: int, y0: int, x1: int, y1: int, t: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var steps := maxi(maxi(dx, dy), 1)
	for s in range(steps + 1):
		var px := roundi(lerpf(float(x0), float(x1), float(s) / float(steps)))
		var py := roundi(lerpf(float(y0), float(y1), float(s) / float(steps)))
		_rect_fill(img, px - t / 2, py - t / 2, t, t, c)


static func _circle(img: Image, cx: int, cy: int, r: int, t: int, c: Color) -> void:
	for y in range(-r - 1, r + 2):
		for x in range(-r - 1, r + 2):
			var d := sqrt(float(x * x + y * y))
			if d <= float(r) and d >= float(r - t):
				var px := cx + x
				var py := cy + y
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(px, py, c)


static func _draw_arrow(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	_line(img, x0, y0, x1 - 4, y1, 3, c)
	_line(img, x1 - 7, y1 - 5, x1, y1, 2, c)
	_line(img, x1 - 7, y1 + 5, x1, y1, 2, c)


static func _draw_digit(img: Image, x: int, y: int, num: int, c: Color) -> void:
	# 5x7 crisp bitmap digits 1..9
	const GLYPHS := {
		1: ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
		2: [".###.", "#...#", "....#", "..##.", ".#...", "#....", "#####"],
		3: [".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."],
		4: ["#...#", "#...#", "#...#", "#####", "....#", "....#", "....#"],
		5: ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
		6: [".###.", "#....", "####.", "#...#", "#...#", "#...#", ".###."],
	}
	var rows: Array = GLYPHS.get(clampi(num, 1, 6), GLYPHS[1])
	for ry in range(rows.size()):
		var row: String = rows[ry]
		for rx in range(row.length()):
			if row[rx] == "#":
				_rect_fill(img, x + rx * 2, y + ry * 2, 2, 2, c)


static func _draw_icon(img: Image, cx: int, cy: int, kind: String, c: Color) -> void:
	match kind:
		"bell", "hammer":
			_line(img, cx - 12, cy - 14, cx + 10, cy - 14, 3, c)
			_line(img, cx - 4, cy - 14, cx - 10, cy + 4, 2, c)
			_rect_fill(img, cx - 16, cy + 2, 12, 8, c)
			_line(img, cx + 8, cy - 6, cx + 14, cy + 12, 3, c)
			_line(img, cx + 4, cy + 12, cx + 16, cy + 12, 3, c)
		"crystal", "cradle":
			_line(img, cx, cy - 14, cx - 8, cy - 2, 2, c)
			_line(img, cx, cy - 14, cx + 8, cy - 2, 2, c)
			_line(img, cx - 8, cy - 2, cx - 6, cy + 10, 2, c)
			_line(img, cx + 8, cy - 2, cx + 6, cy + 10, 2, c)
			_rect_fill(img, cx - 12, cy + 10, 24, 5, c)
		"platform", "cart":
			_line(img, cx - 16, cy - 12, cx + 16, cy - 12, 2, c)
			_line(img, cx - 8, cy - 12, cx - 8, cy + 4, 2, c)
			_line(img, cx + 8, cy - 12, cx + 8, cy + 4, 2, c)
			_rect_fill(img, cx - 15, cy + 4, 30, 6, c)
			_circle(img, cx - 9, cy + 13, 3, 2, c)
			_circle(img, cx + 9, cy + 13, 3, 2, c)
		"gate", "door":
			_rect_outline(img, cx - 13, cy - 14, 26, 28, 3, c)
			_rect_fill(img, cx - 9, cy - 10, 18, 12, c)
			_line(img, cx, cy + 2, cx, cy - 8, 2, Color(0.08, 0.1, 0.12))
		"plug", "clamp":
			_rect_fill(img, cx - 12, cy - 6, 12, 12, c)
			_line(img, cx, cy - 3, cx + 10, cy - 3, 3, c)
			_line(img, cx, cy + 3, cx + 10, cy + 3, 3, c)
			_rect_outline(img, cx + 8, cy - 9, 8, 18, 2, c)
		"pin", "lock":
			_rect_outline(img, cx - 10, cy - 4, 20, 16, 2, c)
			_circle(img, cx, cy - 8, 7, 2, c)
			_rect_fill(img, cx - 2, cy, 4, 8, c)
		"fan":
			_circle(img, cx, cy, 13, 2, c)
			_line(img, cx - 9, cy - 9, cx + 9, cy + 9, 3, c)
			_line(img, cx - 9, cy + 9, cx + 9, cy - 9, 3, c)
		"damper", "gauge", "balance":
			_circle(img, cx, cy + 2, 13, 2, c)
			_line(img, cx, cy + 2, cx + 7, cy - 8, 2, Color(1.0, 0.72, 0.22))
			_rect_fill(img, cx - 10, cy + 12, 20, 3, c)
		"winch":
			_circle(img, cx - 6, cy, 9, 2, c)
			_line(img, cx + 3, cy, cx + 15, cy, 2, c)
			_rect_fill(img, cx + 12, cy - 4, 5, 8, c)
		"lever":
			_rect_fill(img, cx - 12, cy + 8, 24, 5, c)
			_line(img, cx, cy + 8, cx + 10, cy - 12, 3, c)
			_circle(img, cx + 10, cy - 12, 3, 3, Color(1.0, 0.68, 0.18))
		_:
			# generic gear/module
			_circle(img, cx, cy, 11, 3, c)
			_rect_fill(img, cx - 3, cy - 3, 6, 6, c)
