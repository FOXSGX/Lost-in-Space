class_name WaveOrb
extends Node3D
## Short-lived travelling resonance pulse between two crystals.

var from_point: Vector3 = Vector3.ZERO
var to_point: Vector3 = Vector3.ZERO
var duration: float = 1.0
var strength: float = 1.0
var elapsed: float = 0.0
var arc_height: float = 0.55
var color: Color = Color(0.36, 0.90, 1.0)

var _core: MeshInstance3D
var _halo: MeshInstance3D
var _trail: Array[MeshInstance3D] = []


func setup(from_value: Vector3, to_value: Vector3, duration_value: float, strength_value: float, tint: Color) -> void:
	from_point = from_value
	to_point = to_value
	duration = maxf(duration_value, 0.05)
	strength = clampf(strength_value, 0.0, 1.5)
	color = tint
	arc_height = clampf(from_point.distance_to(to_point) * 0.10, 0.22, 0.9)
	_build()


func _build() -> void:
	_core = MeshInstance3D.new()
	var core_mesh: SphereMesh = SphereMesh.new()
	core_mesh.radius = 0.11 + strength * 0.05
	core_mesh.height = core_mesh.radius * 2.0
	core_mesh.radial_segments = 10
	core_mesh.rings = 6
	_core.mesh = core_mesh
	_core.material_override = MaterialLibrary.emissive(color.lightened(0.25), 4.0)
	add_child(_core)

	_halo = MeshInstance3D.new()
	var halo_mesh: SphereMesh = SphereMesh.new()
	halo_mesh.radius = 0.28 + strength * 0.12
	halo_mesh.height = halo_mesh.radius * 2.0
	halo_mesh.radial_segments = 10
	halo_mesh.rings = 6
	_halo.mesh = halo_mesh
	var halo_material: StandardMaterial3D = StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.albedo_color = Color(color.r, color.g, color.b, 0.18)
	halo_material.emission_enabled = true
	halo_material.emission = color
	halo_material.emission_energy_multiplier = 0.7
	halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo.material_override = halo_material
	add_child(_halo)

	for index: int in range(3):
		var trail: MeshInstance3D = MeshInstance3D.new()
		var trail_mesh: SphereMesh = SphereMesh.new()
		trail_mesh.radius = 0.06 - index * 0.012
		trail_mesh.height = trail_mesh.radius * 2.0
		trail_mesh.radial_segments = 8
		trail_mesh.rings = 4
		trail.mesh = trail_mesh
		trail.material_override = MaterialLibrary.emissive(color, 1.4 - index * 0.3)
		add_child(trail)
		_trail.append(trail)
	update_pose()


func _process(delta: float) -> void:
	elapsed += delta
	update_pose()
	if elapsed >= duration:
		queue_free()


func update_pose() -> void:
	var t: float = clampf(elapsed / duration, 0.0, 1.0)
	var base: Vector3 = from_point.lerp(to_point, t)
	base.y += sin(t * PI) * arc_height + 0.18
	global_position = base
	for index: int in range(_trail.size()):
		var delayed_t: float = clampf(t - (index + 1) * 0.045, 0.0, 1.0)
		var trail_pos: Vector3 = from_point.lerp(to_point, delayed_t)
		trail_pos.y += sin(delayed_t * PI) * arc_height + 0.18
		_trail[index].global_position = trail_pos
	var pulsing: float = 1.0 + 0.18 * sin(elapsed * 34.0)
	_core.scale = Vector3.ONE * pulsing
	_halo.scale = Vector3.ONE * (0.92 + 0.08 * sin(elapsed * 20.0))
