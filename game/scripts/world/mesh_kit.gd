class_name WorldKit
extends RefCounted

## Geometry / collision / lighting helper for the Resonance 05 level.
## Everything is built at runtime so the level stays readable as code and every
## visible surface gets an explicit, matching collision primitive.

var root: Node3D
var collision: StaticBody3D
var font: SystemFont
var stats: Dictionary = {
	"meshes": 0,
	"colliders": 0,
	"lights": 0,
	"particles": 0,
	"triangles": 0,
}

static var _scene_cache: Dictionary = {}


func _init(level_root: Node3D) -> void:
	root = level_root
	collision = StaticBody3D.new()
	collision.name = "WorldCollision"
	collision.collision_layer = 1
	collision.collision_mask = 0
	root.add_child(collision)
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_LIGHT


# ---------------------------------------------------------------------------
# Collision primitives
# ---------------------------------------------------------------------------

func add_box_shape(center: Vector3, size: Vector3, basis: Basis = Basis()) -> CollisionShape3D:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	collision.add_child(cs)
	stats["colliders"] = int(stats["colliders"]) + 1
	return cs


func add_cylinder_shape(center: Vector3, radius: float, height: float, basis: Basis = Basis()) -> CollisionShape3D:
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	collision.add_child(cs)
	stats["colliders"] = int(stats["colliders"]) + 1
	return cs


func add_trimesh_shape(mesh: Mesh, xform: Transform3D) -> CollisionShape3D:
	var source: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	var faces: PackedVector3Array = source.get_faces()
	for i in range(faces.size()):
		faces[i] = xform * faces[i]
	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	# The cavern shells are single-sided surfaces; without backface collision a
	# player inside the tunnel can walk straight through the shell into the void.
	shape.backface_collision = true
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	collision.add_child(cs)
	stats["colliders"] = int(stats["colliders"]) + 1
	return cs


# ---------------------------------------------------------------------------
# Primitive meshes
# ---------------------------------------------------------------------------

func box(node_name: String, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, collide: bool = true) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_euler(rot), pos)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi, true)
	stats["meshes"] = int(stats["meshes"]) + 1
	if collide:
		add_box_shape(pos, size, Basis.from_euler(rot))
	return mi


func cylinder(node_name: String, radius: float, height: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, collide: bool = true, segments: int = 16) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_euler(rot), pos)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi, true)
	stats["meshes"] = int(stats["meshes"]) + 1
	if collide:
		add_cylinder_shape(pos, radius, height, Basis.from_euler(rot))
	return mi


func cone(node_name: String, radius: float, height: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, collide: bool = false) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_euler(rot), pos)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi, true)
	stats["meshes"] = int(stats["meshes"]) + 1
	if collide:
		add_cylinder_shape(pos, radius, height, Basis.from_euler(rot))
	return mi


func sphere(node_name: String, radius: float, pos: Vector3, mat: Material, segments: int = 12) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = max(4, segments / 2)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi, true)
	stats["meshes"] = int(stats["meshes"]) + 1
	return mi


func wedge_ramp(node_name: String, center_x: float, width: float, z_top: float, y_top: float, z_bottom: float, y_bottom: float, thickness: float, mat: Material, collide: bool = true) -> MeshInstance3D:
	# A true wedge whose top surface runs exactly from (z_top,y_top) to
	# (z_bottom,y_bottom). No rotated-box lip at either end, so the player can
	# step on and off without an invisible 10-15 cm wall.
	var hw: float = width * 0.5
	var a: Vector3 = Vector3(center_x - hw, y_top, z_top)
	var b: Vector3 = Vector3(center_x + hw, y_top, z_top)
	var c: Vector3 = Vector3(center_x + hw, y_bottom, z_bottom)
	var d: Vector3 = Vector3(center_x - hw, y_bottom, z_bottom)
	var a2: Vector3 = a - Vector3(0, thickness, 0)
	var b2: Vector3 = b - Vector3(0, thickness, 0)
	var c2: Vector3 = c - Vector3(0, thickness, 0)
	var d2: Vector3 = d - Vector3(0, thickness, 0)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, a, b, c, d, Vector3.UP, Vector3.UP)
	_quad(st, a2, d2, c2, b2, Vector3.DOWN, Vector3.DOWN)
	_quad(st, a, d, d2, a2, Vector3.LEFT, Vector3.LEFT)
	_quad(st, b, b2, c2, c, Vector3.RIGHT, Vector3.RIGHT)
	_quad(st, b, a, a2, b2, Vector3.FORWARD, Vector3.FORWARD)
	_quad(st, d, c, c2, d2, Vector3.BACK, Vector3.BACK)
	var mesh: ArrayMesh = st.commit()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi, true)
	stats["meshes"] = int(stats["meshes"]) + 1
	stats["triangles"] = int(stats["triangles"]) + 12
	if collide:
		var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array([a, b, c, d, a2, b2, c2, d2])
		var cs: CollisionShape3D = CollisionShape3D.new()
		cs.shape = shape
		collision.add_child(cs)
		stats["colliders"] = int(stats["colliders"]) + 1
	return mi


func beam(node_name: String, a: Vector3, b: Vector3, radius: float, mat: Material, collide: bool = false, segments: int = 10) -> MeshInstance3D:
	var delta: Vector3 = b - a
	var length: float = delta.length()
	if length < 0.001:
		length = 0.001
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = segments
	mesh.rings = 1
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	var dir: Vector3 = delta / length
	var basis: Basis = Basis(Quaternion(Vector3.UP, dir))
	mi.transform = Transform3D(basis, (a + b) * 0.5)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi, true)
	stats["meshes"] = int(stats["meshes"]) + 1
	if collide:
		add_cylinder_shape((a + b) * 0.5, radius, length, basis)
	return mi


func pipe(node_name: String, points: Array[Vector3], radius: float, mat: Material, collide: bool = false) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	root.add_child(holder, true)
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var delta: Vector3 = b - a
		if delta.length() < 0.001:
			continue
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = delta.length()
		mesh.radial_segments = 10
		mesh.rings = 1
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, delta.normalized())), (a + b) * 0.5)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		holder.add_child(mi, true)
		stats["meshes"] = int(stats["meshes"]) + 1
		if collide:
			add_cylinder_shape((a + b) * 0.5, radius, delta.length(), Basis(Quaternion(Vector3.UP, delta.normalized())))
	for i in range(points.size()):
		var joint: MeshInstance3D = MeshInstance3D.new()
		var sm: SphereMesh = SphereMesh.new()
		sm.radius = radius * 1.22
		sm.height = radius * 2.44
		sm.radial_segments = 10
		sm.rings = 5
		joint.mesh = sm
		joint.material_override = mat
		joint.position = points[i]
		joint.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		holder.add_child(joint)
	return holder


# ---------------------------------------------------------------------------
# Custom structural rings / torus / crystals
# ---------------------------------------------------------------------------

func ring_box(node_name: String, radius: float, width: float, height: float, pos: Vector3, mat: Material, basis: Basis = Basis(), segments: int = 64, collide: bool = false) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_out: float = radius + width * 0.5
	var r_in: float = radius - width * 0.5
	var y_top: float = height * 0.5
	var y_bot: float = -height * 0.5
	for i in range(segments):
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		var c0: Vector3 = Vector3(cos(a0), 0, sin(a0))
		var c1: Vector3 = Vector3(cos(a1), 0, sin(a1))
		var ob0: Vector3 = c0 * r_out + Vector3(0, y_bot, 0)
		var ob1: Vector3 = c1 * r_out + Vector3(0, y_bot, 0)
		var ot0: Vector3 = c0 * r_out + Vector3(0, y_top, 0)
		var ot1: Vector3 = c1 * r_out + Vector3(0, y_top, 0)
		var ib0: Vector3 = c0 * r_in + Vector3(0, y_bot, 0)
		var ib1: Vector3 = c1 * r_in + Vector3(0, y_bot, 0)
		var it0: Vector3 = c0 * r_in + Vector3(0, y_top, 0)
		var it1: Vector3 = c1 * r_in + Vector3(0, y_top, 0)
		_quad(st, ob0, ob1, ot1, ot0, c0, c1)
		_quad(st, ib1, ib0, it0, it1, -c1, -c0)
		_quad(st, it0, it1, ot1, ot0, c0, c1, true)
		_quad(st, ob0, ob1, ib1, ib0, c0, c1, false)
	var mesh: ArrayMesh = st.commit()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi, true)
	stats["meshes"] = int(stats["meshes"]) + 1
	stats["triangles"] = int(stats["triangles"]) + segments * 8
	if collide:
		_ring_collider(radius, width, height, pos, basis, segments)
	return mi


func _ring_collider(radius: float, width: float, height: float, pos: Vector3, basis: Basis, segments: int) -> void:
	var count: int = max(8, segments / 4)
	for i in range(count):
		var a: float = TAU * float(i) / float(count)
		var local: Vector3 = Vector3(cos(a), 0, sin(a)) * radius
		var seg_len: float = TAU * radius / float(count) * 1.12
		var seg_basis: Basis = basis * Basis(Vector3.UP, -a)
		add_box_shape(pos + basis * local, Vector3(seg_len, height, width), seg_basis)


func torus(node_name: String, radius: float, tube: float, pos: Vector3, mat: Material, basis: Basis = Basis(), segments: int = 48, sides: int = 8) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		for j in range(sides):
			var b0: float = TAU * float(j) / float(sides)
			var b1: float = TAU * float(j + 1) / float(sides)
			var p00: Vector3 = _torus_pt(radius, tube, a0, b0)
			var p01: Vector3 = _torus_pt(radius, tube, a0, b1)
			var p11: Vector3 = _torus_pt(radius, tube, a1, b1)
			var p10: Vector3 = _torus_pt(radius, tube, a1, b0)
			_tri_smooth(st, p00, p10, p11)
			_tri_smooth(st, p00, p11, p01)
	var mesh: ArrayMesh = st.commit()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi, true)
	stats["meshes"] = int(stats["meshes"]) + 1
	stats["triangles"] = int(stats["triangles"]) + segments * sides * 2
	return mi


func _torus_pt(radius: float, tube: float, a: float, b: float) -> Vector3:
	var center: Vector3 = Vector3(cos(a) * radius, 0, sin(a) * radius)
	var dir: Vector3 = Vector3(cos(a), 0, sin(a))
	return center + dir * cos(b) * tube + Vector3(0, sin(b) * tube, 0)


func crystal(node_name: String, pos: Vector3, height: float, radius: float, sides: int, mat: Material, basis: Basis = Basis(), seed: float = 0.0) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = [
		{"t": 0.0, "r": 0.04, "y": 0.0},
		{"t": 0.2, "r": 0.78, "y": 0.2},
		{"t": 0.72, "r": 1.0, "y": 0.72},
		{"t": 1.0, "r": 0.03, "y": 1.0},
	]
	var pts: Array = []
	for r in range(rings.size()):
		var ring: Array = []
		var info: Dictionary = rings[r] as Dictionary
		for i in range(sides):
			var a: float = TAU * float(i) / float(sides) + seed * 0.7
			var jitter: float = 1.0 + 0.14 * sin(seed * 3.1 + float(i) * 2.7 + float(r) * 1.9)
			var rr: float = radius * float(info["r"]) * jitter
			ring.append(Vector3(cos(a) * rr, height * float(info["y"]), sin(a) * rr))
		pts.append(ring)
	for r in range(rings.size() - 1):
		var ring_a: Array = pts[r] as Array
		var ring_b: Array = pts[r + 1] as Array
		for i in range(sides):
			var j: int = (i + 1) % sides
			var a0: Vector3 = ring_a[i] as Vector3
			var a1: Vector3 = ring_a[j] as Vector3
			var b0: Vector3 = ring_b[i] as Vector3
			var b1: Vector3 = ring_b[j] as Vector3
			_tri_flat(st, a0, b1, a1)
			_tri_flat(st, a0, b0, b1)
	var mesh: ArrayMesh = st.commit()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi, true)
	stats["meshes"] = int(stats["meshes"]) + 1
	stats["triangles"] = int(stats["triangles"]) + sides * (rings.size() - 1) * 2
	return mi


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, _ca: Vector3, _cb: Vector3, _top: bool = false) -> void:
	var n: Vector3 = (b - a).cross(d - a).normalized()
	if n.length_squared() < 0.01:
		n = Vector3.UP
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var verts: Array[Vector3] = [a, b, c, d]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])


func _tri_flat(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(b)
	st.set_normal(n)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(c)


func _tri_smooth(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


# ---------------------------------------------------------------------------
# Imported rock / crystal prefabs with exact collision
# ---------------------------------------------------------------------------

func rock(node_name: String, path: String, pos: Vector3, rot_y_deg: float, scale: float, mat: Material, collide: bool = true, rot_x_deg: float = 0.0, rot_z_deg: float = 0.0) -> Node3D:
	var packed: PackedScene = null
	if _scene_cache.has(path):
		packed = _scene_cache[path] as PackedScene
	else:
		packed = load(path) as PackedScene
		_scene_cache[path] = packed
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	holder.position = pos
	holder.rotation = Vector3(deg_to_rad(rot_x_deg), deg_to_rad(rot_y_deg), deg_to_rad(rot_z_deg))
	holder.scale = Vector3.ONE * scale
	root.add_child(holder, true)
	if packed == null:
		push_warning("Missing rock prefab: %s" % path)
		return holder
	var inst: Node3D = packed.instantiate() as Node3D
	holder.add_child(inst)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(inst, meshes)
	for mi in meshes:
		mi.material_override = mat
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.mesh != null:
			stats["triangles"] = int(stats["triangles"]) + mi.mesh.get_faces().size() / 3
	if collide:
		for mi in meshes:
			if mi.mesh != null:
				add_trimesh_shape(mi.mesh, mi.global_transform)
	return holder


func crystal_cluster(node_name: String, pos: Vector3, rot_y_deg: float, scale: float, mat: Material, collide: bool = false) -> Node3D:
	return rock(node_name, "res://assets/rocks/crystal_cluster_a.glb", pos, rot_y_deg, scale, mat, collide)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


# ---------------------------------------------------------------------------
# MultiMesh detail
# ---------------------------------------------------------------------------

func bolt_row(node_name: String, transforms: Array[Transform3D], radius: float = 0.055, height: float = 0.05, mat: Material = null) -> MultiMeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 1
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat if mat != null else MatLib.steel()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mmi)
	return mmi


func rivet_ring(center: Vector3, radius: float, count: int, axis: Vector3 = Vector3.UP, mat: Material = null) -> void:
	var transforms: Array[Transform3D] = []
	var basis: Basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	for i in range(count):
		var a: float = TAU * float(i) / float(count)
		var local: Vector3 = Vector3(cos(a) * radius, 0, sin(a) * radius)
		transforms.append(Transform3D(basis, center + local))
	bolt_row("Rivets", transforms, 0.05, 0.04, mat)


# ---------------------------------------------------------------------------
# Text, light, particles
# ---------------------------------------------------------------------------

func label3d(text: String, pos: Vector3, pixel_size: float = 0.0032, color: Color = Color(0.9, 0.98, 1.0), font_size: int = 48, basis: Basis = Basis()) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = text
	l.font = font
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.modulate = color
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.transform = Transform3D(basis, pos)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = false
	l.no_depth_test = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(l)
	return l


func omni(pos: Vector3, color: Color, energy: float, light_range: float, shadow: bool = false, name: String = "Omni") -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = name
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.35
	light.shadow_enabled = shadow
	light.light_specular = 0.55
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 22.0
	root.add_child(light)
	stats["lights"] = int(stats["lights"]) + 1
	return light


func spot(pos: Vector3, look_at: Vector3, color: Color, energy: float, light_range: float, angle_deg: float, shadow: bool = false) -> SpotLight3D:
	var light: SpotLight3D = SpotLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.spot_range = light_range
	light.spot_angle = angle_deg
	light.spot_angle_attenuation = 0.9
	light.shadow_enabled = shadow
	var dir: Vector3 = (look_at - pos).normalized()
	var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	light.transform = Transform3D(Basis.looking_at(dir, up), pos)
	root.add_child(light)
	stats["lights"] = int(stats["lights"]) + 1
	return light


func dust(node_name: String, pos: Vector3, extents: Vector3, amount: int, color: Color = Color(0.65, 0.82, 0.9, 0.5), size: float = 0.035) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.name = node_name
	p.position = pos
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(0.2, 1.0, 0.1)
	p.spread = 180.0
	p.gravity = Vector3(0.01, -0.012, 0.0)
	p.initial_velocity_min = 0.01
	p.initial_velocity_max = 0.08
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.color = color
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = MatLib.particle_material(color, true)
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-extents.x - 2, -extents.y - 2, -extents.z - 2), Vector3(extents.x + 2, extents.y + 2, extents.z + 2) * 2.0)
	root.add_child(p)
	stats["particles"] = int(stats["particles"]) + 1
	return p


func spark_burst(node_name: String, pos: Vector3, amount: int, color: Color, one_shot: bool = true) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.name = node_name
	p.position = pos
	p.amount = amount
	p.lifetime = 1.1
	p.one_shot = one_shot
	p.explosiveness = 0.92
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.gravity = Vector3(0, -9.0, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.5
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	p.color = color
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = MatLib.particle_material(color, true)
	p.mesh = quad
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	return p


# ---------------------------------------------------------------------------
# Composite industrial props
# ---------------------------------------------------------------------------

func deck(node_name: String, center: Vector3, size: Vector3, mat_top: Material = null, rail_sides: Array = []) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	root.add_child(holder, true)
	var top: Material = mat_top if mat_top != null else MatLib.dark_steel()
	var slab: MeshInstance3D = box("DeckSlab", size, center, top, Vector3.ZERO, true)
	slab.reparent(holder)
	var step_count: int = int(maxf(2.0, size.z / 0.9))
	for i in range(step_count):
		var z: float = center.z - size.z * 0.5 + (float(i) + 0.5) * size.z / float(step_count)
		var strip: MeshInstance3D = box("Tread", Vector3(size.x * 0.94, 0.012, 0.06), Vector3(center.x, center.y + size.y * 0.5 + 0.012, z), MatLib.steel(), Vector3.ZERO, false)
		strip.reparent(holder)
	var edge_y: float = center.y + size.y * 0.5
	for side in rail_sides:
		var sx: float = -1.0 if str(side) == "left" else 1.0
		railing(holder, Vector3(center.x + sx * (size.x * 0.5 - 0.12), edge_y, center.z - size.z * 0.5), Vector3(center.x + sx * (size.x * 0.5 - 0.12), edge_y, center.z + size.z * 0.5), 1.05)
	return holder


func railing(parent: Node3D, a: Vector3, b: Vector3, height: float) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = "Railing"
	parent.add_child(holder)
	var delta: Vector3 = b - a
	var length: float = delta.length()
	if length < 0.2:
		return holder
	var posts: int = int(maxf(2.0, round(length / 1.4)))
	for i in range(posts + 1):
		var t: float = float(i) / float(posts)
		var p: Vector3 = a.lerp(b, t)
		var post: MeshInstance3D = box("Post", Vector3(0.07, height, 0.07), p + Vector3(0, height * 0.5, 0), MatLib.steel(), Vector3.ZERO, false)
		post.reparent(holder)
		var foot: MeshInstance3D = box("Foot", Vector3(0.2, 0.03, 0.2), p + Vector3(0, 0.015, 0), MatLib.dark_steel(), Vector3.ZERO, false)
		foot.reparent(holder)
	var mid: Vector3 = (a + b) * 0.5
	var dir: Vector3 = delta.normalized()
	var basis: Basis = Basis(Quaternion(Vector3.RIGHT, dir))
	for hy in [height, height * 0.55]:
		var rail: MeshInstance3D = box("Rail", Vector3(length, 0.055, 0.055), mid + Vector3(0, hy, 0), MatLib.steel(), Vector3.ZERO, false)
		rail.reparent(holder)
		rail.transform = Transform3D(basis, mid + Vector3(0, hy, 0))
	# A railing is a physical barrier, but only where it is actually visible:
	# the top and mid rails plus the posts. A full-height invisible panel made
	# the player stop at knee height between two open rails.
	add_box_shape(mid + Vector3(0, height, 0), Vector3(length, 0.10, 0.07), basis)
	add_box_shape(mid + Vector3(0, height * 0.55, 0), Vector3(length, 0.07, 0.07), basis)
	for i in range(posts + 1):
		var t2: float = float(i) / float(posts)
		var post_pos: Vector3 = a.lerp(b, t2)
		add_box_shape(post_pos + Vector3(0, height * 0.5, 0), Vector3(0.09, height, 0.09), basis)
	return holder


func handwheel(node_name: String, pos: Vector3, radius: float, mat: Material, yaw: float = 0.0) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	root.add_child(holder, true)
	var wheel_basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
	torus("WheelRim", radius, 0.035, pos, mat, wheel_basis, 32, 6)
	cylinder("WheelHub", radius * 0.16, 0.16, pos, mat, Vector3(0, yaw, PI * 0.5), false, 12)
	for i in range(4):
		var a: float = TAU * float(i) / 4.0
		var local: Vector3 = Vector3(cos(a), 0, sin(a)) * radius * 0.45
		var spoke_dir: Vector3 = Basis(Vector3.UP, yaw) * Vector3(cos(a), 0, sin(a))
		beam("Spoke", pos - spoke_dir * radius * 0.9, pos + spoke_dir * radius * 0.9, 0.022, mat, false, 6)
	return holder


func control_cabinet(node_name: String, pos: Vector3, yaw: float = 0.0, size: Vector3 = Vector3(1.2, 1.9, 0.7)) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	root.add_child(holder, true)
	var basis: Basis = Basis(Vector3.UP, yaw)
	var body_pos: Vector3 = pos + Vector3(0, size.y * 0.5, 0)
	box("Cabinet", size, body_pos, MatLib.painted_steel(Color(0.20, 0.30, 0.33)), Vector3(0, yaw, 0), true)
	var face_local: Vector3 = Vector3(0, size.y * 0.72, size.z * 0.5 + 0.01)
	var screen_pos: Vector3 = pos + basis * face_local
	box("Screen", Vector3(size.x * 0.72, size.y * 0.26, 0.02), screen_pos, MatLib.energy(Color(0.18, 0.7, 0.8), 0.8, 0.4, 4.0), Vector3(0, yaw, 0), false)
	var frame_pos: Vector3 = pos + basis * (face_local - Vector3(0, 0, 0.03))
	box("Frame", Vector3(size.x * 0.8, size.y * 0.32, 0.05), frame_pos, MatLib.dark_steel(), Vector3(0, yaw, 0), false)
	for i in range(4):
		var local: Vector3 = Vector3(-size.x * 0.25 + float(i) * size.x * 0.16, size.y * 0.44, size.z * 0.5 + 0.03)
		var col: Color = Color(0.9, 0.55, 0.15) if i != 2 else Color(0.2, 0.85, 0.55)
		box("Button", Vector3(0.09, 0.09, 0.03), pos + basis * local, MatLib.emissive(col, 1.6), Vector3(0, yaw, 0), false)
	return holder


func warning_sign(text: String, pos: Vector3, yaw: float, width: float = 1.2, height: float = 0.5) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = "WarningSign"
	root.add_child(holder, true)
	box("Plate", Vector3(width, height, 0.04), pos, MatLib.hazard_material(), Vector3(0, yaw, 0), false)
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = font
	label.font_size = 40
	label.pixel_size = 0.0034
	label.modulate = Color(0.06, 0.05, 0.04)
	label.outline_size = 0
	var offset: Vector3 = Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.035)
	label.transform = Transform3D(Basis(Vector3.UP, yaw), pos + offset)
	label.double_sided = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	holder.add_child(label)
	return holder


func crate(node_name: String, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	root.add_child(holder, true)
	var basis: Basis = Basis.from_euler(rot)
	box("Crate", size, pos, MatLib.painted_steel(Color(0.33, 0.30, 0.22)), rot, true)
	for sy in [-0.28, 0.28]:
		box("Band", Vector3(size.x * 1.01, size.y * 0.09, size.z * 1.01), pos + basis * Vector3(0, size.y * sy, 0), MatLib.dark_steel(), rot, false)
	var label: Label3D = Label3D.new()
	label.text = "R-05"
	label.font = font
	label.font_size = 36
	label.pixel_size = 0.003
	label.modulate = Color(0.75, 0.64, 0.42)
	label.transform = Transform3D(basis, pos + basis * Vector3(0, 0, size.z * 0.5 + 0.005))
	label.double_sided = false
	holder.add_child(label)
	return holder


