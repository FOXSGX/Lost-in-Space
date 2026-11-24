class_name EchoCrystal
extends Node3D
## Fixed crystal node in the level. Rotation.y defines the emitted focus axis
## (local -Z), which is also drawn by CrystalVisual's focus facet.

var node_id: String = ""
var visual: CrystalVisual
var memory_index: int = -1
var is_memory: bool = false
var base_yaw_deg: float = 0.0
var halo: MeshInstance3D
var _halo_material: StandardMaterial3D


func build(id_value: String, asset_path: String, palette: String, scale_factor: float, yaw_degrees: float, with_light: bool = true) -> bool:
	node_id = id_value
	base_yaw_deg = yaw_degrees
	rotation.y = deg_to_rad(yaw_degrees)
	visual = CrystalVisual.new()
	visual.name = "Visual"
	add_child(visual)
	var ok: bool = visual.build(asset_path, palette, scale_factor, with_light)
	add_to_group("echo_crystal")
	return ok


func make_memory(index: int, palette: String = "violet") -> void:
	memory_index = index
	is_memory = true
	visual.set_pulse(0.38)
	halo = MeshInstance3D.new()
	halo.name = "MemoryHalo"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 1.05
	torus.outer_radius = 1.12
	torus.rings = 28
	torus.ring_segments = 6
	halo.mesh = torus
	_halo_material = StandardMaterial3D.new()
	var color: Color = Color(0.42, 0.88, 1.0) if palette == "cyan" else Color(0.66, 0.48, 1.0)
	_halo_material.albedo_color = color
	_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_material.albedo_color.a = 0.28
	_halo_material.emission_enabled = true
	_halo_material.emission = color
	_halo_material.emission_energy_multiplier = 1.1
	halo.material_override = _halo_material
	halo.position = Vector3(0.0, 2.15, 0.0)
	halo.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(halo)


func set_memory_awake(awake: bool) -> void:
	if halo == null:
		return
	_halo_material.albedo_color.a = 0.55 if awake else 0.28
	_halo_material.emission_energy_multiplier = 2.2 if awake else 1.1
	visual.set_pulse(0.85 if awake else 0.38)


func flash(strength: float = 1.0) -> void:
	if visual != null:
		visual.flash(strength)


func set_alarm(value: float) -> void:
	if visual != null:
		visual.set_alarm(value)


func set_focus_visible(value: bool) -> void:
	if visual != null:
		visual.set_focus_visible(value)


func focus_direction() -> Vector3:
	return -global_transform.basis.z


func _process(delta: float) -> void:
	if halo != null:
		halo.rotation.z += delta * 0.45
		halo.position.y = 2.15 + sin(Time.get_ticks_msec() * 0.0012) * 0.06
