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
const RADIUS: float = 0.035
const SLACK_PER_METRE: float = 0.42

var from_point: Vector3 = Vector3.ZERO
var to_point: Vector3 = Vector3.ZERO
var slack: float = 0.0
var tension_ratio: float = 0.0
var visible_cable: bool = true

var _mesh: MeshInstance3D
var _material: StandardMaterial3D

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
	add_child(_mesh)

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
	_mesh.mesh = _build_tube(from_world, to_world, slack_metres)

func _build_tube(a: Vector3, b: Vector3, slack_metres: float) -> ArrayMesh:
	var direct: Vector3 = b - a
	var length: float = maxf(direct.length(), 0.05)
	var sag: float = clampf(slack_metres * SLACK_PER_METRE, 0.0, 2.4)
	var frames: Array[Vector3] = []
	frames.resize(SEGMENTS + 1)
	for index: int in range(SEGMENTS + 1):
		var t: float = float(index) / float(SEGMENTS)
		var point: Vector3 = a.lerp(b, t)
		# Parabolic sag, zero at both ends, maximum in the middle.
		point.y -= sag * 4.0 * t * (1.0 - t)
		frames[index] = point

	var rings: int = SEGMENTS + 1
	var sides: int = 6
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var up: Vector3 = Vector3.UP
	if absf(direct.normalized().dot(up)) > 0.95:
		up = Vector3.RIGHT
	for ring: int in range(rings):
		var tangent: Vector3
		if ring == 0:
			tangent = frames[1] - frames[0]
		elif ring == rings - 1:
			tangent = frames[rings - 1] - frames[rings - 2]
		else:
			tangent = frames[ring + 1] - frames[ring - 1]
		tangent = tangent.normalized() if tangent.length() > 0.0001 else Vector3.FORWARD
		var side: Vector3 = tangent.cross(up).normalized()
		if side.length() < 0.01:
			side = tangent.cross(Vector3.RIGHT).normalized()
		var other: Vector3 = side.cross(tangent).normalized()
		for s: int in range(sides):
			var angle: float = TAU * float(s) / float(sides)
			var normal: Vector3 = side * cos(angle) + other * sin(angle)
			vertices.append(frames[ring] + normal * RADIUS)
			normals.append(normal)
	for ring: int in range(rings - 1):
		for s: int in range(sides):
			var next_s: int = (s + 1) % sides
			var i0: int = ring * sides + s
			var i1: int = ring * sides + next_s
			var i2: int = (ring + 1) * sides + s
			var i3: int = (ring + 1) * sides + next_s
			indices.append(i0)
			indices.append(i2)
			indices.append(i1)
			indices.append(i1)
			indices.append(i2)
			indices.append(i3)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
