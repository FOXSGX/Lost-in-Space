class_name ResonanceNetwork
extends Node3D
## Authoritative (single-process) resonance propagation and its 3D feedback.
##
## Game state lives in ResonanceModel; this node only turns scheduled events
## into visible/audible feedback. Every client would receive the same strike
## call and replay the same deterministic event list.

signal wave_started(source_id: String, strength: float)
signal node_arrived(node_id: String, amplitude: float, kind: String)
signal memory_reached(memory_index: int, amplitude: float, node_id: String)
signal dead_end(node_id: String)
signal weak_memory(node_id: String, amplitude: float)
signal strike_completed(source_id: String)
signal edges_rebuilt

const BEAM_SHADER: Shader = preload("res://shaders/beam.gdshader")
const ECHO_DELAY := 1.15
const ECHO_AMPLITUDE := 0.92
const BEAD_COUNT := 9

var model: ResonanceModel
var crystals: Dictionary = {}
var bead_parent: Node3D
var effect_parent: Node3D
var audio: Node

var last_dead_end: String = ""
var last_memory_index: int = 0
var last_amplitudes: Dictionary = {}
var active: bool = false

var _pending: Array[Dictionary] = []
var _pending_index: int = 0
var _clock: float = 0.0
var _strike_source: String = ""
var _beads: Dictionary = {}
var _bead_tween: Tween
var _echo_timer: float = -1.0
var _echo_source: String = ""
var _orbs: Array[WaveOrb] = []


func setup(model_value: ResonanceModel, bead_parent_value: Node3D, effect_parent_value: Node3D) -> void:
	model = model_value
	bead_parent = bead_parent_value
	effect_parent = effect_parent_value
	audio = get_tree().get_first_node_in_group("audio_director")
	rebuild_edges()


func register_crystal(id: String, crystal: EchoCrystal) -> void:
	crystals[id] = crystal


func rebuild_edges() -> void:
	if model == null or bead_parent == null:
		return
	if _bead_tween != null:
		_bead_tween.kill()
	_bead_tween = null
	for child: Node in bead_parent.get_children():
		child.queue_free()
	_beads.clear()
	for edge: Dictionary in model.edges():
		var from_id: String = str(edge["from"])
		var to_id: String = str(edge["to"])
		var key: String = from_id + "|" + to_id
		if _beads.has(key):
			continue
		var from_crystal: EchoCrystal = crystals.get(from_id) as EchoCrystal
		if from_crystal == null:
			continue
		var palette: String = "cyan"
		if from_crystal.visual != null:
			palette = from_crystal.visual.accent
		var color: Color = Color(0.36, 0.88, 1.0)
		if palette == "violet":
			color = Color(0.65, 0.47, 1.0)
		elif palette == "amber":
			color = Color(1.0, 0.68, 0.30)
		var from_point: Vector3 = model.get_position(from_id) + Vector3(0.0, 0.30, 0.0)
		var to_point: Vector3 = model.get_position(to_id) + Vector3(0.0, 0.30, 0.0)
		var beads: Array[Dictionary] = []
		for index: int in range(BEAD_COUNT):
			var t: float = float(index + 1) / float(BEAD_COUNT + 1)
			var point: Vector3 = from_point.lerp(to_point, t)
			point.y += sin(t * PI) * 0.20
			var bead: MeshInstance3D = MeshInstance3D.new()
			var mesh: SphereMesh = SphereMesh.new()
			mesh.radius = 0.045
			mesh.height = 0.09
			mesh.radial_segments = 6
			mesh.rings = 3
			bead.mesh = mesh
			var material: StandardMaterial3D = StandardMaterial3D.new()
			material.albedo_color = Color(color.r, color.g, color.b, 0.55)
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 0.22
			bead.material_override = material
			bead.position = point
			bead_parent.add_child(bead)
			beads.append({"mesh": bead, "material": material})
		_beads[key] = beads
	edges_rebuilt.emit()


func strike(source_id: String, strength: float) -> void:
	if model == null:
		return
	_strike_source = source_id
	_clock = 0.0
	_pending_index = 0
	_pending = model.propagate(source_id, strength)
	active = true
	last_dead_end = ""
	last_amplitudes.clear()
	_clear_orbs()
	var source_crystal: EchoCrystal = crystals.get(source_id) as EchoCrystal
	if source_crystal != null:
		source_crystal.flash(0.8 + strength * 0.4)
		_spawn_ring(model.get_position(source_id) + Vector3(0.0, 1.0, 0.0), Color(0.4, 0.92, 1.0), 0.7 + strength * 0.4)
	_play_at("resonance_strike", model.get_position(source_id), 0.85)
	wave_started.emit(source_id, strength)
	if _pending.is_empty():
		last_dead_end = source_id
		_spawn_dead_end(source_id)
		dead_end.emit(source_id)
		active = false
		strike_completed.emit(source_id)


func strike_echo(source_id: String, amplitude: float = ECHO_AMPLITUDE) -> void:
	strike(source_id, amplitude)


func _event_time(event: Dictionary) -> float:
	if event.has("start"):
		return float(event["start"])
	return float(event.get("time", 0.0))


func _process(delta: float) -> void:
	if _echo_timer > 0.0:
		_echo_timer -= delta
		if _echo_timer <= 0.0 and _echo_source != "":
			var echo_from: String = _echo_source
			_echo_source = ""
			strike_echo(echo_from, ECHO_AMPLITUDE)
	if not active:
		return
	_clock += delta
	while _pending_index < _pending.size():
		var event: Dictionary = _pending[_pending_index]
		if _event_time(event) > _clock:
			break
		_handle_event(event)
		_pending_index += 1
	if _pending_index >= _pending.size():
		active = false
		_pending.clear()
		_pending_index = 0
		strike_completed.emit(_strike_source)


func _handle_event(event: Dictionary) -> void:
	var event_type: String = str(event.get("type", ""))
	match event_type:
		"travel":
			var from_id: String = str(event["from"])
			var to_id: String = str(event["to"])
			var duration: float = float(event["end"]) - float(event["start"])
			_spawn_orb(from_id, to_id, duration, float(event["amp_to"]))
			_pulse_beads(from_id, to_id, duration)
		"arrive":
			var node_id: String = str(event["id"])
			var amplitude: float = float(event["amp"])
			var kind: String = str(event["kind"])
			last_amplitudes[node_id] = amplitude
			var crystal: EchoCrystal = crystals.get(node_id) as EchoCrystal
			if crystal != null:
				crystal.flash(0.55 + amplitude * 1.1)
			_spawn_ring(model.get_position(node_id) + Vector3(0.0, 1.0, 0.0), _color_for(node_id), 0.55 + amplitude * 0.7)
			_play_at("crystal_pulse", model.get_position(node_id), 0.42 + amplitude * 0.4)
			node_arrived.emit(node_id, amplitude, kind)
			if kind == "memory" and crystal != null and crystal.memory_index > 0:
				last_memory_index = crystal.memory_index
				memory_reached.emit(crystal.memory_index, amplitude, node_id)
				# The memory crystal stores the wave and re-emits it a moment
				# later. If the final relay is already in place the echo can
				# continue to the next memory without another hammer strike.
				# The second memory crystal is the one that keeps echoing
				# deeper into the mine. It schedules an echo even when the
				# next cradle is still empty: the visible beam then dies at
				# the gap, which is the player's clue.
				if crystal.memory_index == 2:
					_echo_timer = ECHO_DELAY
					_echo_source = node_id
		"dead_end":
			var dead_id: String = str(event["id"])
			last_dead_end = dead_id
			var dead_crystal: EchoCrystal = crystals.get(dead_id) as EchoCrystal
			if dead_crystal != null:
				dead_crystal.set_alarm(0.9)
				dead_crystal.flash(0.25)
				dead_crystal.visual.shake_strength = 0.035
				dead_crystal.visual.shake_remaining = 0.45
				# The crystal can be freed (reset / act switch) inside the 1.2 s
				# window; a lambda holding a freed node raises "previously freed".
				get_tree().create_timer(1.2).timeout.connect(func() -> void:
					if is_instance_valid(dead_crystal):
						dead_crystal.set_alarm(0.0))
			_spawn_dead_end(dead_id)
			_play_at("resonance_dead_end", model.get_position(dead_id), 0.7)
			dead_end.emit(dead_id)
		"weak":
			var weak_id: String = str(event["id"])
			var weak_amp: float = float(event["amp"])
			var weak_crystal: EchoCrystal = crystals.get(weak_id) as EchoCrystal
			if weak_crystal != null:
				weak_crystal.set_alarm(0.55)
			_play_at("resonance_weak", model.get_position(weak_id), 0.55)
			weak_memory.emit(weak_id, weak_amp)


func _color_for(node_id: String) -> Color:
	var crystal: EchoCrystal = crystals.get(node_id) as EchoCrystal
	if crystal != null and crystal.visual != null:
		if crystal.visual.accent == "violet":
			return Color(0.68, 0.50, 1.0)
		if crystal.visual.accent == "amber":
			return Color(1.0, 0.70, 0.32)
	return Color(0.40, 0.92, 1.0)


func _spawn_orb(from_id: String, to_id: String, duration: float, amplitude: float) -> void:
	var orb: WaveOrb = WaveOrb.new()
	orb.name = "WaveOrb"
	effect_parent.add_child(orb)
	orb.setup(model.get_position(from_id) + Vector3(0.0, 1.0, 0.0), model.get_position(to_id) + Vector3(0.0, 1.0, 0.0), maxf(duration, 0.12), amplitude, _color_for(to_id))
	_orbs.append(orb)
	# orb 到达终点后自己 queue_free()，但数组里会留下失效引用；一次流程要敲
	# 十几次，数组只增不裁会让 _clear_orbs() 的遍历越来越长。
	_prune_orbs()


## 丢掉已释放 / 已排队删除的 orb。开销与“还活着的 orb 数”成正比，
## 而活着的 orb 本来就只有正在飞的那几个。
func _prune_orbs() -> void:
	var alive: Array[WaveOrb] = []
	for orb: WaveOrb in _orbs:
		if is_instance_valid(orb) and not orb.is_queued_for_deletion():
			alive.append(orb)
	_orbs = alive


func _clear_orbs() -> void:
	for orb: WaveOrb in _orbs:
		if is_instance_valid(orb):
			orb.queue_free()
	_orbs.clear()


func _pulse_beads(from_id: String, to_id: String, duration: float) -> void:
	var key: String = from_id + "|" + to_id
	if not _beads.has(key):
		return
	var beads: Array = _beads[key]
	var step: float = maxf(duration, 0.12) / float(beads.size())
	if _bead_tween != null:
		_bead_tween.kill()
	_reset_bead_energy()
	_bead_tween = create_tween()
	for index: int in range(beads.size()):
		var entry: Dictionary = beads[index]
		var material: StandardMaterial3D = entry["material"] as StandardMaterial3D
		if index > 0:
			_bead_tween.tween_interval(step)
		_bead_tween.tween_callback(_set_bead_energy.bind(material, 3.2))
		_bead_tween.tween_interval(0.10)
		_bead_tween.tween_callback(_set_bead_energy.bind(material, 0.38))
	_bead_tween.tween_interval(0.6)
	_bead_tween.tween_callback(_reset_bead_energy)


func _set_bead_energy(material: StandardMaterial3D, energy: float) -> void:
	if material != null:
		material.emission_energy_multiplier = energy


func _reset_bead_energy() -> void:
	for key: Variant in _beads.keys():
		var beads: Array = _beads[key]
		for entry: Dictionary in beads:
			var material: StandardMaterial3D = entry["material"] as StandardMaterial3D
			material.emission_energy_multiplier = 0.22


func _spawn_ring(position_value: Vector3, color: Color, radius: float) -> void:
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = radius * 0.9
	torus.outer_radius = radius
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.55)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = material
	ring.position = position_value
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	effect_parent.add_child(ring)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 2.6, 0.55)
	tween.tween_property(material, "albedo_color", Color(color.r, color.g, color.b, 0.0), 0.55)
	tween.tween_property(material, "emission_energy_multiplier", 0.0, 0.55)
	tween.chain().tween_callback(ring.queue_free)


func _spawn_dead_end(node_id: String) -> void:
	var position_value: Vector3 = model.get_position(node_id) + Vector3(0.0, 1.0, 0.0)
	var focus: Vector3 = model.get_focus(node_id)
	var max_range: float = float(model.get_node_data(node_id).get("radius", 6.8))
	var beam: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.11
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 1
	beam.mesh = mesh
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = BEAM_SHADER
	material.set_shader_parameter("tint", Color(0.42, 0.88, 1.0))
	material.set_shader_parameter("strength", 0.85)
	beam.material_override = material
	effect_parent.add_child(beam)
	var end_point: Vector3 = position_value + focus * maxf(max_range - 0.6, 1.0)
	var mid: Vector3 = (position_value + end_point) * 0.5
	beam.global_position = mid
	beam.look_at(end_point, Vector3.UP)
	beam.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	beam.scale = Vector3(1.0, position_value.distance_to(end_point), 1.0)
	var tween: Tween = create_tween()
	tween.tween_interval(0.25)
	tween.tween_property(beam, "scale", Vector3(0.01, 0.01, 0.01), 0.75)
	tween.tween_callback(beam.queue_free)

	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.amount = 16
	particles.lifetime = 1.1
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.direction = focus
	particles.spread = 25.0
	particles.initial_velocity_min = 0.6
	particles.initial_velocity_max = 1.9
	particles.gravity = Vector3(0.0, -1.2, 0.0)
	particles.scale_amount_min = 0.03
	particles.scale_amount_max = 0.09
	particles.color = Color(0.45, 0.85, 1.0, 0.6)
	var particle_mesh: SphereMesh = SphereMesh.new()
	particle_mesh.radius = 0.06
	particle_mesh.height = 0.12
	particle_mesh.radial_segments = 6
	particle_mesh.rings = 3
	particles.mesh = particle_mesh
	particles.material_override = MaterialLibrary.emissive(Color(0.45, 0.85, 1.0), 1.2)
	particles.position = position_value
	effect_parent.add_child(particles)
	particles.emitting = true
	# `clear_all()` may free the particle node before the timer fires.
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free())


func clear_all() -> void:
	if _bead_tween != null:
		_bead_tween.kill()
		_bead_tween = null
	_pending.clear()
	_pending_index = 0
	active = false
	_clock = 0.0
	_echo_timer = -1.0
	_echo_source = ""
	last_dead_end = ""
	last_amplitudes.clear()
	_clear_orbs()
	if bead_parent != null:
		for child: Node in bead_parent.get_children():
			child.queue_free()
	_beads.clear()
	if effect_parent != null:
		for child: Node in effect_parent.get_children():
			if child is WaveOrb:
				continue
			child.queue_free()


func _play_at(sound_name: String, position_value: Vector3, volume: float) -> void:
	if audio == null or not audio.has_method("play_at"):
		return
	audio.call("play_at", sound_name, position_value, volume)
