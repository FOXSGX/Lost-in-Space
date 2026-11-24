class_name SwingLamp
extends Node3D

## Hanging industrial lamp. The world reacts to the core's instability by
## swinging; the player camera is never shaken.

var lamp: Node3D
var light: OmniLight3D
var tension: float = 0.0
var amplitude: float = 0.05
var phase: float = 0.0
var freq: float = 1.2
var _time: float = 0.0
var _kit: WorldKit


func build(hang_length: float = 3.2, lamp_color: Color = Color(1.0, 0.72, 0.45)) -> void:
	_kit = WorldKit.new(self)
	var segs: int = maxi(6, int(hang_length / 0.16))
	for i in range(segs):
		_kit.cylinder("Chain", 0.028, 0.15, Vector3(0, -0.08 - float(i) * 0.16, 0), MatLib.dark_steel(), Vector3.ZERO, false, 6)
	lamp = Node3D.new()
	lamp.name = "LampHead"
	lamp.position = Vector3(0, -hang_length, 0)
	add_child(lamp)
	var lk: WorldKit = WorldKit.new(lamp)
	lk.cylinder("Shade", 0.42, 0.26, Vector3.ZERO, MatLib.painted_steel(Color(0.23, 0.28, 0.25)), Vector3.ZERO, false, 16)
	lk.sphere("Bulb", 0.16, Vector3(0, -0.12, 0), MatLib.emissive(lamp_color, 3.2), 10)
	lk.torus("CageRing", 0.40, 0.018, Vector3(0, -0.08, 0), MatLib.dark_steel(), Basis(), 24, 5)
	light = OmniLight3D.new()
	light.position = Vector3(0, -0.25, 0)
	light.light_color = lamp_color
	light.light_energy = 2.2
	light.omni_range = 8.0
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	lamp.add_child(light)


func set_tension(value: float) -> void:
	tension = clampf(value, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var amp: float = amplitude * (0.25 + tension * 3.2)
	rotation.z = sin(_time * freq + phase) * amp
	rotation.x = cos(_time * freq * 0.73 + phase * 1.7) * amp * 0.7
	if light != null:
		light.light_energy = 2.0 + sin(_time * 2.1 + phase) * 0.15 + tension * 0.5
