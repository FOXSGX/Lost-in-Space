extends Node3D

# -----------------------------------------------------------------------------
# WinchCable - the visual cable between the winch sheave and the hook.
#
# Purely cosmetic, on purpose:
#   * no CollisionShape, no RigidBody, no physics body of any kind
#   * a 24-segment tube rebuilt from two points every frame
#   * the sag is proportional to the slack the solver already computed, so what
#     you see is the same number the rail feels (no separate fake state)
# A cable that cannot collide can never launch the player, which is a hard
# requirement of this prototype.
# -----------------------------------------------------------------------------

const SEGMENTS: int = 24
const SIDES: int = 6
const RADIUS: float = 0.035
const SLACK_PER_METRE: float = 0.42

var from_point: Vector3 = Vector3.ZERO
var to_point: Vector3 = Vector3.ZERO
var slack: float = 0.0
var tension_ratio: float = 0.0
var visible_cable: bool = true

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _cable_mesh: ArrayMesh
var _frames: PackedVector3Array = PackedVector3Array()
var _vertices: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _indices: PackedInt32Array = PackedInt32Array()
var _arrays: Array = []

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "CableMesh"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.20, 0.22, 0.25)
	_material.metallic = 0.75
	_material.roughness = 0.42
	_material.emission_enabled = true
	_material.emission = Color(0.12, 0.55, 0.78)
	_material.emission_energy_multiplier = 0.0
	_mesh.material_override = _material
	_init_buffers()
	_mesh.mesh = _cable_mesh
	add_child(_mesh)

func _init_buffers() -> void:
	var rings: int = SEGMENTS + 1
	_frames.resize(rings)
	_vertices.resize(rings * SIDES)
	_normals.resize(rings * SIDES)
	_indices.resize(SEGMENTS * SIDES * 6)
	var idx: int = 0
	for ring: int in range(SEGMENTS):
		for s: int in range(SIDES):
			var next_s: int = (s + 1) % SIDES
			var i0: int = ring * SIDES + s
			var i1: int = ring * SIDES + next_s
			var i2: int = (ring + 1) * SIDES + s
			var i3: int = (ring + 1) * SIDES + next_s
			_indices[idx] = i0
			_indices[idx + 1] = i2
			_indices[idx + 2] = i1
			_indices[idx + 3] = i1
			_indices[idx + 4] = i2
			_indices[idx + 5] = i3
			idx += 6
	_arrays.resize(Mesh.ARRAY_MAX)
	_arrays[Mesh.ARRAY_INDEX] = _indices
	_cable_mesh = ArrayMesh.new()

func update_cable(from_world: Vector3, to_world: Vector3, slack_metres: float, tension: float, shown: bool) -> void:
	from_point = from_world
	to_point = to_world
	slack = slack_metres
	tension_ratio = tension
	visible_cable = shown
	_mesh.visible = shown
	if not shown:
		return
	_material.emission_energy_multiplier = clampf(tension_ratio * 2.4, 0.0, 2.4)
	_material.albedo_color = Color(0.20, 0.22, 0.25).lerp(Color(0.55, 0.72, 0.78), clampf(tension_ratio, 0.0, 1.0))
	_update_tube_in_place(from_world, to_world, slack_metres)

func _update_tube_in_place(a: Vector3, b: Vector3, slack_metres: float) -> void:
	var direct: Vector3 = b - a
	var sag: float = clampf(slack_metres * SLACK_PER_METRE, 0.0, 2.4)
	var rings: int = SEGMENTS + 1
	for index: int in range(rings):
		var t: float = float(index) / float(SEGMENTS)
		var point: Vector3 = a.lerp(b, t)
		# Parabolic sag, zero at both ends, maximum in the middle.
		point.y -= sag * 4.0 * t * (1.0 - t)
		_frames[index] = point

	var up: Vector3 = Vector3.UP
	var dir_len: float = direct.length()
	if dir_len > 0.0001 and absf((direct / dir_len).dot(up)) > 0.95:
		up = Vector3.RIGHT
	var v_idx: int = 0
	for ring: int in range(rings):
		var tangent: Vector3
		if ring == 0:
			tangent = _frames[1] - _frames[0]
		elif ring == rings - 1:
			tangent = _frames[rings - 1] - _frames[rings - 2]
		else:
			tangent = _frames[ring + 1] - _frames[ring - 1]
		tangent = tangent.normalized() if tangent.length() > 0.0001 else Vector3.FORWARD
		var side: Vector3 = tangent.cross(up)
		if side.length_squared() < 0.0001:
			side = tangent.cross(Vector3.RIGHT)
		side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
		var other: Vector3 = side.cross(tangent).normalized()
		for s: int in range(SIDES):
			var angle: float = TAU * float(s) / float(SIDES)
			var normal: Vector3 = side * cos(angle) + other * sin(angle)
			_vertices[v_idx] = _frames[ring] + normal * RADIUS
			_normals[v_idx] = normal
			v_idx += 1

	_arrays[Mesh.ARRAY_VERTEX] = _vertices
	_arrays[Mesh.ARRAY_NORMAL] = _normals
	_cable_mesh.clear_surfaces()
	_cable_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
