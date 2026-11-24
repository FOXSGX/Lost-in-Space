class_name CrystalVisual
extends Node3D
## A crystal mesh from the validated art library plus a rebuilt three-band
## material, a directional focus facet and a cheap pulse light.
##
## The source GLB keeps its material slots but lost the Blender procedural node
## colors. Bands are rebuilt from the registered material names:
##   * deep cleavage -> dark body
##   * resonant      -> main body
##   * axial/exposed -> bright emitting facet
## This is a runtime material rebuild; source GLBs stay untouched.

const CRYSTAL_SHADER: Shader = preload("res://shaders/crystal.gdshader")
const BEAM_SHADER: Shader = preload("res://shaders/beam.gdshader")

const PALETTES := {
	"cyan": {
		"deep": Color(0.025, 0.150, 0.195),
		"mid": Color(0.110, 0.620, 0.720),
		"tip": Color(0.600, 0.980, 1.000),
		"light": Color(0.36, 0.88, 1.0),
	},
	"violet": {
		"deep": Color(0.120, 0.060, 0.260),
		"mid": Color(0.430, 0.270, 0.860),
		"tip": Color(0.800, 0.640, 1.000),
		"light": Color(0.66, 0.46, 1.0),
	},
	"amber": {
		"deep": Color(0.180, 0.085, 0.025),
		"mid": Color(0.720, 0.390, 0.100),
		"tip": Color(1.000, 0.800, 0.440),
		"light": Color(1.0, 0.68, 0.32),
	},
}

var accent: String = "cyan"
var pulse: float = 0.22
var pulse_target: float = 0.22
var pulse_phase: float = 0.0
var alarm: float = 0.0
var focus_visible: bool = true
var shake_remaining: float = 0.0
var shake_strength: float = 0.0

var _materials: Array[ShaderMaterial] = []
var _base_emission: Array[float] = []
var _carry_mode: bool = false
var _light: OmniLight3D
var _focus_root: Node3D
var _focus_beam: MeshInstance3D
var _focus_ring: MeshInstance3D
var _model: Node3D
var _time: float = 0.0
var _base_position: Vector3
var _rng_phase: float = 0.0


func build(asset_path: String, palette: String = "cyan", scale_factor: float = 1.0, with_light: bool = true) -> bool:
	accent = palette if PALETTES.has(palette) else "cyan"
	_rng_phase = randf() * TAU
	var packed: PackedScene = load(asset_path) as PackedScene
	if packed == null:
		push_error("Crystal asset missing: " + asset_path)
		return false
	_model = packed.instantiate() as Node3D
	if _model == null:
		return false
	_model.scale = Vector3.ONE * scale_factor
	add_child(_model)
	_apply_materials(_model)
	_build_focus_marker()
	if with_light:
		_light = OmniLight3D.new()
		_light.name = "CrystalGlow"
		var palette_data: Dictionary = PALETTES[accent]
		_light.light_color = palette_data["light"] as Color
		_light.light_energy = 0.95
		_light.omni_range = 5.2
		_light.omni_attenuation = 1.4
		_light.shadow_enabled = false
		_light.position = Vector3(0.0, 1.25, 0.0)
		add_child(_light)
	_base_position = position
	return true


func _apply_materials(root: Node3D) -> void:
	var palette_data: Dictionary = PALETTES[accent]
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var surface_count: int = mesh_instance.mesh.get_surface_count()
		for surface: int in range(surface_count):
			var source: Material = mesh_instance.get_active_material(surface)
			var band_name: String = ""
			if source != null:
				band_name = source.resource_name.to_lower()
			if band_name.is_empty():
				band_name = mesh_instance.name.to_lower()
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = CRYSTAL_SHADER
			var deep_color: Color = palette_data["deep"] as Color
			var mid_color: Color = palette_data["mid"] as Color
			var tip_color: Color = palette_data["tip"] as Color
			var emission: float = 0.95
			var rough: float = 0.16
			var axial_gain: float = 1.0
			if band_name.contains("deep") or band_name.contains("cleavage"):
				deep_color = (palette_data["deep"] as Color).darkened(0.35)
				mid_color = (palette_data["mid"] as Color).darkened(0.15)
				tip_color = palette_data["mid"] as Color
				emission = 0.55
				rough = 0.24
				axial_gain = 0.75
			elif band_name.contains("axial") or band_name.contains("exposed") or band_name.contains("nucleus"):
				deep_color = palette_data["mid"] as Color
				mid_color = palette_data["tip"] as Color
				tip_color = (palette_data["tip"] as Color).lightened(0.20)
				emission = 1.65
				rough = 0.1
				axial_gain = 1.45
			elif band_name.contains("violet") and accent == "cyan":
				deep_color = PALETTES["violet"]["deep"] as Color
				mid_color = PALETTES["violet"]["mid"] as Color
				tip_color = PALETTES["violet"]["tip"] as Color
			material.set_shader_parameter("deep_tint", deep_color)
			material.set_shader_parameter("tint", mid_color)
			material.set_shader_parameter("tip_tint", tip_color)
			material.set_shader_parameter("emission_energy", emission)
			material.set_shader_parameter("roughness_value", rough)
			material.set_shader_parameter("axial_gain", axial_gain)
			material.set_shader_parameter("band_scale", 7.5 + randf() * 2.5)
			material.set_shader_parameter("pulse", pulse)
			material.set_shader_parameter("pulse_phase", _rng_phase)
			mesh_instance.set_surface_override_material(surface, material)
			_materials.append(material)
			_base_emission.append(emission)


func _build_focus_marker() -> void:
	_focus_root = Node3D.new()
	_focus_root.name = "FocusFacet"
	add_child(_focus_root)
	var beam_mesh: CylinderMesh = CylinderMesh.new()
	beam_mesh.top_radius = 0.012
	beam_mesh.bottom_radius = 0.085
	beam_mesh.height = 1.05
	beam_mesh.radial_segments = 10
	beam_mesh.rings = 1
	_focus_beam = MeshInstance3D.new()
	_focus_beam.name = "FocusBeam"
	_focus_beam.mesh = beam_mesh
	var beam_material: ShaderMaterial = ShaderMaterial.new()
	beam_material.shader = BEAM_SHADER
	var palette_data: Dictionary = PALETTES[accent]
	beam_material.set_shader_parameter("tint", palette_data["tip"] as Color)
	beam_material.set_shader_parameter("strength", 0.38)
	_focus_beam.material_override = beam_material
	# Cylinder points along +Y; rotate so it points along local -Z.
	_focus_beam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_focus_beam.position = Vector3(0.0, 0.72, -0.56)
	_focus_root.add_child(_focus_beam)

	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.19
	ring_mesh.outer_radius = 0.23
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 6
	_focus_ring = MeshInstance3D.new()
	_focus_ring.name = "FocusRing"
	_focus_ring.mesh = ring_mesh
	var ring_material: StandardMaterial3D = StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = palette_data["tip"] as Color
	ring_material.emission_enabled = true
	ring_material.emission = palette_data["tip"] as Color
	ring_material.emission_energy_multiplier = 1.0
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color.a = 0.30
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_focus_ring.material_override = ring_material
	# A flat halo lying under the crystal, not a hoop floating in the air beside
	# it. The focus direction is carried by the beam, which is readable.
	_focus_ring.rotation_degrees = Vector3.ZERO
	_focus_ring.position = Vector3(0.0, 0.06, 0.0)
	_focus_root.add_child(_focus_ring)
	_focus_root.visible = focus_visible


func set_focus_visible(value: bool) -> void:
	focus_visible = value
	if _focus_root != null:
		_focus_root.visible = value


func set_palette(palette: String) -> void:
	if not PALETTES.has(palette) or palette == accent:
		return
	accent = palette
	var palette_data: Dictionary = PALETTES[accent]
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("tint", palette_data["mid"] as Color)
		material.set_shader_parameter("tip_tint", palette_data["tip"] as Color)
	if _light != null:
		_light.light_color = palette_data["light"] as Color


func flash(strength: float = 1.0, hold: float = 0.0) -> void:
	pulse_target = maxf(pulse_target, clampf(strength, 0.0, 1.6))
	if hold > 0.0:
		pulse = pulse_target
	shake_strength = maxf(shake_strength, strength * 0.035)
	shake_remaining = maxf(shake_remaining, 0.18 + hold)


func set_pulse(value: float) -> void:
	pulse = clampf(value, 0.0, 1.6)
	pulse_target = pulse


func set_alarm(value: float) -> void:
	alarm = clampf(value, 0.0, 1.0)


func set_light_energy(value: float) -> void:
	if _light != null:
		_light.light_energy = value


## Held-in-hand mode: the shard is 0.9 m from the lens, so its full emission
## bloomed into a white slab and hid the facets the player needs to read the
## orientation. While carried the glow is dimmed and the target ring hidden.
func set_carry_mode(value: bool) -> void:
	_carry_mode = value
	set_focus_visible(not value)
	if not value:
		for index: int in range(_materials.size()):
			_materials[index].set_shader_parameter("emission_energy", _base_emission[index])


func _process(delta: float) -> void:
	_time += delta
	pulse_phase += delta * (1.6 + pulse * 4.0)
	pulse = move_toward(pulse, pulse_target, delta * 2.2)
	pulse_target = move_toward(pulse_target, 0.22, delta * 1.1)
	var emission_scale: float = 0.24 if _carry_mode else 1.0
	for index: int in range(_materials.size()):
		var material: ShaderMaterial = _materials[index]
		material.set_shader_parameter("pulse", pulse)
		material.set_shader_parameter("pulse_phase", pulse_phase)
		material.set_shader_parameter("alarm", alarm)
		if index < _base_emission.size():
			material.set_shader_parameter("emission_energy", _base_emission[index] * emission_scale)
	if _light != null:
		_light.light_energy = (0.80 + pulse * 2.1 + alarm * 0.4) * (0.18 if _carry_mode else 1.0)
	if _focus_ring != null:
		_focus_ring.rotation_degrees.y += delta * 24.0
	if shake_remaining > 0.0:
		shake_remaining -= delta
		var decay: float = clampf(shake_remaining / 0.22, 0.0, 1.0)
		position = _base_position + Vector3(
			sin(_time * 71.0) * shake_strength * decay,
			0.0,
			cos(_time * 63.0) * shake_strength * decay
		)
	else:
		position = _base_position
