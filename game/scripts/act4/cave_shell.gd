class_name R04CaveShell
extends RefCounted
## Procedural cave shell for Resonance 04.
##
## The prototype used six flat boxes as walls. At 20 m away, lit only by
## ambient light, those boxes read as a black void; every prop therefore looked
## like it was floating in space. This builder replaces them with a real cave
## boundary:
##
##   * a rounded, noise-displaced perimeter wall (~12 m tall) with a rock shelf,
##   * a sagging ceiling with natural dips,
##   * vertex-colour ambient occlusion so crevices read without SSAO
##     (GL Compatibility has none),
##   * one static trimesh collider built from exactly the same triangles, so
##     there is no invisible flat wall in front of the visible rock.
##
## The shell is authored in world space and uses the triplanar rock shader, so
## no UV work is needed. Cost is ~4k triangles / 1 draw call.

const SEGMENTS := 132
const RINGS: Array[float] = [0.0, 1.2, 2.4, 3.6, 4.8, 6.0, 7.2, 8.4, 9.6, 10.8, 12.0]
const HALF_X := 20.0
const Z_MIN := -28.8
const Z_MAX := 12.8
const CEILING_Y := 11.6
const CORNER_POWER := 5.0
const ROOM_CENTER := Vector3(0.0, 5.5, -8.0)

var _noise: FastNoiseLite
var _detail: FastNoiseLite
var _faces: PackedVector3Array = PackedVector3Array()
static var _shared_noise: FastNoiseLite
static var _shared_detail: FastNoiseLite


## Public height query so rocks, cables and stalactites can attach to the same
## ceiling the shell actually renders.
static func ceiling_y(x: float, z: float) -> float:
	if _shared_noise == null:
		_shared_noise = FastNoiseLite.new()
		_shared_noise.seed = 20404
		_shared_noise.frequency = 0.075
		_shared_noise.fractal_octaves = 3
		_shared_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_shared_detail = FastNoiseLite.new()
		_shared_detail.seed = 771
		_shared_detail.frequency = 0.33
		_shared_detail.fractal_octaves = 2
	var base: float = CEILING_Y + 0.35 * _shared_noise.get_noise_2d(x * 0.7, z * 0.7)
	base -= 0.9 * exp(-pow((x + 2.0) / 13.0, 2.0) - pow((z + 10.0) / 14.0, 2.0))
	base += 0.18 * _shared_detail.get_noise_2d(x * 2.3, z * 2.3)
	return base


func _init() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = 20404
	_noise.frequency = 0.075
	_noise.fractal_octaves = 3
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail = FastNoiseLite.new()
	_detail.seed = 771
	_detail.frequency = 0.33
	_detail.fractal_octaves = 2


## Returns { "body": StaticBody3D, "mesh": MeshInstance3D }.
func build(parent: Node3D, material: Material, name_prefix: String = "Cave") -> Dictionary:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_faces = PackedVector3Array()

	var columns: int = SEGMENTS
	var wall: Array[PackedVector3Array] = []
	for ring: int in range(RINGS.size()):
		var row: PackedVector3Array = PackedVector3Array()
		for index: int in range(columns + 1):
			var angle: float = TAU * float(index) / float(columns)
			row.append(_wall_point(angle, RINGS[ring]))
		wall.append(row)

	for ring: int in range(RINGS.size() - 1):
		var bottom: PackedVector3Array = wall[ring]
		var top: PackedVector3Array = wall[ring + 1]
		for index: int in range(columns):
			var a: Vector3 = bottom[index]
			var b: Vector3 = bottom[index + 1]
			var c: Vector3 = top[index + 1]
			var d: Vector3 = top[index]
			_quad(st, a, b, c, d, _wall_color(a), _wall_color(b), _wall_color(c), _wall_color(d))

	# Ceiling: a grid that sags between the walls. It overlaps the top wall ring
	# so no seam is visible from below.
	var ceiling_x: int = 26
	var ceiling_z: int = 28
	var ceiling_points: Array[PackedVector3Array] = []
	for ix: int in range(ceiling_x + 1):
		var row: PackedVector3Array = PackedVector3Array()
		var x: float = lerpf(-HALF_X - 1.5, HALF_X + 1.5, float(ix) / float(ceiling_x))
		for iz: int in range(ceiling_z + 1):
			var z: float = lerpf(Z_MIN - 1.5, Z_MAX + 1.5, float(iz) / float(ceiling_z))
			row.append(Vector3(x, _ceiling_height(x, z), z))
		ceiling_points.append(row)
	for ix: int in range(ceiling_x):
		for iz: int in range(ceiling_z):
			var a: Vector3 = ceiling_points[ix][iz]
			var b: Vector3 = ceiling_points[ix + 1][iz]
			var c: Vector3 = ceiling_points[ix + 1][iz + 1]
			var d: Vector3 = ceiling_points[ix][iz + 1]
			var colour: Color = _ceiling_color((a + c) * 0.5)
			_quad(st, a, b, c, d, colour, colour, colour, colour)

	# Rock skirt along the wall base: hides the floor/wall seam and gives the
	# decor crystals something to grow out of.
	_add_base_shelf(st)

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = name_prefix + "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)

	var body: StaticBody3D = StaticBody3D.new()
	body.name = name_prefix + "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Collision"
	var concave: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(_faces)
	shape.shape = concave
	body.add_child(shape)

	return {"body": body, "mesh": mesh_instance}


# ------------------------------------------------------------------ geometry

func _wall_point(angle: float, height: float) -> Vector3:
	# Rounded rectangle (superellipse) so the cave is not a box.
	var cos_v: float = cos(angle)
	var sin_v: float = sin(angle)
	var x: float = signf(cos_v) * pow(absf(cos_v), 2.0 / CORNER_POWER) * HALF_X
	var z_center: float = (Z_MIN + Z_MAX) * 0.5
	var half_z: float = (Z_MAX - Z_MIN) * 0.5
	var z: float = z_center + signf(sin_v) * pow(absf(sin_v), 2.0 / CORNER_POWER) * half_z

	# Outward normal of the superellipse, normalised.
	var normal: Vector2 = Vector2(cos_v / HALF_X, sin_v / half_z)
	if normal.length_squared() < 0.0001:
		normal = Vector2(cos_v, sin_v)
	normal = normal.normalized()

	var bulge: float = 0.55 + 0.85 * (_noise.get_noise_2d(angle * 9.0, height * 0.42) * 0.5 + 0.5)
	bulge += 0.22 * _detail.get_noise_2d(angle * 31.0, height * 1.1)
	# A continuous rock shelf around 3.2-4.4 m, then an overhang higher up.
	var shelf: float = -0.55 * exp(-pow((height - 3.9) / 0.9, 2.0))
	var overhang: float = -0.30 * clampf((height - 7.0) / 4.0, 0.0, 1.0)
	var displacement: float = bulge + shelf + overhang

	return Vector3(x + normal.x * displacement, height, z + normal.y * displacement)


func _ceiling_height(x: float, z: float) -> float:
	return ceiling_y(x, z)


func _add_base_shelf(st: SurfaceTool) -> void:
	var columns: int = SEGMENTS
	var inner: PackedVector3Array = PackedVector3Array()
	var outer: PackedVector3Array = PackedVector3Array()
	var top: PackedVector3Array = PackedVector3Array()
	for index: int in range(columns + 1):
		var angle: float = TAU * float(index) / float(columns)
		var base: Vector3 = _wall_point(angle, 0.0)
		var inward: Vector3 = Vector3.ZERO - base
		inward.y = 0.0
		inward = inward.normalized()
		var spread: float = 0.55 + 0.55 * (_detail.get_noise_2d(angle * 17.0, 3.0) * 0.5 + 0.5)
		inner.append(base + inward * 0.02)
		outer.append(base + inward * spread + Vector3(0.0, -0.25, 0.0))
		top.append(base + inward * spread * 0.45 + Vector3(0.0, 0.55 + 0.35 * spread, 0.0))
	for index: int in range(columns):
		var i2: int = index + 1
		_quad(st, outer[index], outer[i2], top[i2], top[index],
			_wall_color(outer[index]), _wall_color(outer[i2]),
			_wall_color(top[i2]), _wall_color(top[index]))
		_quad(st, top[index], top[i2], inner[i2], inner[index],
			_wall_color(top[index]), _wall_color(top[i2]),
			_wall_color(inner[i2]), _wall_color(inner[index]))


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cc)
	st.add_vertex(c)
	st.set_color(cd)
	st.add_vertex(d)
	_faces.append(a)
	_faces.append(b)
	_faces.append(c)
	_faces.append(a)
	_faces.append(c)
	_faces.append(d)


func _wall_color(point: Vector3) -> Color:
	var ao: float = 0.52 + 0.48 * clampf(point.y / 2.8, 0.0, 1.0)
	var grain: float = 0.90 + 0.16 * (_detail.get_noise_2d(point.x * 1.7 + point.z * 0.9, point.y * 1.9) * 0.5 + 0.5)
	var warm: float = 0.02 * _detail.get_noise_2d(point.x * 3.1, point.z * 3.1)
	return Color(ao * grain + warm, ao * grain, ao * grain * 0.97)


func _ceiling_color(point: Vector3) -> Color:
	var grain: float = 0.82 + 0.18 * (_detail.get_noise_2d(point.x * 1.3, point.z * 1.3) * 0.5 + 0.5)
	return Color(grain * 0.95, grain * 0.98, grain)
