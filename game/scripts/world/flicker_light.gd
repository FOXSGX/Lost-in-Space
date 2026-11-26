class_name FlickerLight
extends Node3D

var light: OmniLight3D
var base_energy: float = 2.0
var _time: float = 0.0
var seed_value: float = 0.0
var broken: bool = true


func build(color: Color = Color(1.0, 0.62, 0.3), energy: float = 2.0, light_range: float = 7.0, with_fixture: bool = true) -> void:
	var kit: WorldKit = WorldKit.new(self)
	if with_fixture:
		kit.box("Bracket", Vector3(0.5, 0.08, 0.5), Vector3(0, 0.25, 0), MatLib.dark_steel(), Vector3.ZERO, false)
		kit.box("Shade", Vector3(0.75, 0.16, 0.75), Vector3(0, 0.1, 0), MatLib.painted_steel(Color(0.2, 0.24, 0.23)), Vector3.ZERO, false)
		kit.sphere("Lens", 0.22, Vector3(0, 0.0, 0), MatLib.emissive(color, 2.8), 12)
	light = OmniLight3D.new()
	light.position = Vector3(0, -0.2, 0)
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	add_child(light)
	base_energy = energy
	seed_value = randf() * 10.0


func _process(delta: float) -> void:
	_time += delta
	if not broken:
		light.light_energy = base_energy
		return
	var n: float = sin(_time * 7.3 + seed_value) * sin(_time * 2.1 + seed_value * 0.7)
	var drop: float = 1.0
	if n > 0.35:
		drop = 0.18
	elif n > 0.1:
		drop = 0.65
	light.light_energy = base_energy * drop
