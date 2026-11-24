class_name Act1Ventilation
extends Node3D

## Giant industrial fan, two-duct damper and spatial wind fields for Act 01.
## The rotor has inertia, the damper physically rotates, and the two wind volumes
## exchange flow instead of multiplying one global number.

## Pressure-test contract. One source of truth for the machine, the HUD and the
## launch interlock, so the displayed target can never drift from the real gate.
const PRESSURE_MIN := 0.58
const PRESSURE_TEST_SECONDS := 6.0
const DAMPER_OPEN_MIN := 0.72
## The governor's three gears. `next_governor_value()` is the same selection
## the press handler uses, so the HUD's "next step" is exactly what will happen.
const GOVERNOR_LOW := 0.55
const GOVERNOR_MID := 0.78
const GOVERNOR_HIGH := 1.0

const FAN_POS := Vector3(11.15, 5.0, -27.0)
const MAIN_BOX := AABB(Vector3(-10.5, -3.2, -30.5), Vector3(20.5, 13.2, 6.0))
const BYPASS_BOX := AABB(Vector3(6.0, -0.5, -35.5), Vector3(5.0, 9.0, 8.5))
const MAIN_DIR := Vector3(-1, 0, 0)
const BYPASS_DIR := Vector3(0, 0, -1)

var stage: Node
var rotor: Node3D
var housing: Node3D
var damper_pivot: Node3D
var damper_plate: MeshInstance3D
var blades: Array[Node3D] = []
var streamers: Array[Node3D] = []
var _main_louvers: Array[Node3D] = []
var _bypass_louvers: Array[Node3D] = []
var status_lights: Array[MeshInstance3D] = []
var main_particles: CPUParticles3D
var bypass_particles: CPUParticles3D
var fan_audio: AudioStreamPlayer3D
var alarm_audio: AudioStreamPlayer3D
## True on the authority (host/solo). A client mirrors the host's 6 s test from
## the dynamic snapshot instead of running its own, so it can never display a
## pass before the host grants `vent_complete`.
var authority_test := true
var running := false
var emergency := false
var speed := 0.0
var governor := 0.62
var damper := 0.0
var damper_target := 0.0
var pressure := 0.0
var gust_factor := 1.0
var pressure_test_seconds := 0.0
var vent_complete := false
var _smooth_main := 0.0
var _smooth_bypass := 0.0
var _alarm_t := 0.0


func setup(p_stage: Node) -> void:
	stage = p_stage
	name = "VentilationSystem"
	_build_fan()
	_build_ducts()
	_build_effects()
	_build_audio()


func _build_fan() -> void:
	var dark := Act1MatLib.dark_steel()
	var steel := Act1MatLib.steel()
	var blade_mat := Act1MatLib.painted_steel(Color(0.58, 0.64, 0.66))
	var orange := Act1MatLib.painted_steel(Color(0.70, 0.32, 0.075))
	var yellow := Act1MatLib.painted_steel(Color(0.82, 0.60, 0.10))
	var cyan := Act1MatLib.emissive(Color(0.16, 0.78, 0.90), 1.05)
	var glow := Act1MatLib.energy(Color(0.10, 0.74, 0.88), 0.9, 0.8, 5.0)
	# wall collar and structural cradle
	var ring_basis := Basis(Vector3.BACK, PI * 0.5)
	housing = Node3D.new()
	housing.name = "FanHousing"
	add_child(housing)
	_add_ring("IntakeCollar", 4.45, 0.65, 1.05, FAN_POS + Vector3(0.65, 0, 0), dark, ring_basis, 48)
	_add_ring("HousingA", 3.92, 0.48, 2.6, FAN_POS, steel, ring_basis, 54)
	_add_ring("HousingB", 4.34, 0.22, 0.35, FAN_POS + Vector3(-0.9, 0, 0), yellow, ring_basis, 54)
	_add_ring("HousingC", 4.34, 0.22, 0.35, FAN_POS + Vector3(0.9, 0, 0), yellow, ring_basis, 54)
	# inlet bell mouth (flared torus)
	_add_torus("BellMouth", 4.32, 0.20, FAN_POS + Vector3(-1.10, 0, 0), orange, ring_basis)
	# 8 heavy blades with a real pivot and pitch
	rotor = Node3D.new()
	rotor.name = "FanRotor"
	rotor.position = FAN_POS + Vector3(0.10, 0, 0)
	add_child(rotor)
	var hub := _mesh_cylinder(0.72, 0.90, 24, dark)
	hub.rotation.z = PI * 0.5
	rotor.add_child(hub)
	var hub_cap := _mesh_cylinder(0.94, 0.16, 28, orange)
	hub_cap.rotation.z = PI * 0.5
	hub_cap.position = Vector3(-0.52, 0, 0)
	rotor.add_child(hub_cap)
	for i in range(8):
		var pivot := Node3D.new()
		pivot.name = "BladePivot_%d" % i
		pivot.rotation.x = TAU * float(i) / 8.0
		rotor.add_child(pivot)
		var blade := _mesh_box(Vector3(0.16, 3.15, 0.94), blade_mat)
		blade.name = "Blade_%d" % i
		blade.position = Vector3(0, 2.05, 0)
		blade.rotation.y = deg_to_rad(24.0)
		pivot.add_child(blade)
		var tip := _mesh_box(Vector3(0.19, 0.20, 1.0), cyan)
		tip.position = Vector3(0, 3.58, 0)
		pivot.add_child(tip)
		var root_plate := _mesh_box(Vector3(0.24, 0.62, 0.86), orange)
		root_plate.position = Vector3(0, 0.70, 0)
		pivot.add_child(root_plate)
		blades.append(pivot)
	# safety cage in front of the rotor is deliberately dark so the blades read
	for j in range(2):
		_add_torus("CageRing_%d" % j, 4.15 - j * 1.55, 0.045, FAN_POS + Vector3(-1.82 - j * 0.14, 0, 0), steel, ring_basis)
	for i in range(8):
		var bar := _mesh_box(Vector3(0.05, 8.0, 0.05), steel)
		bar.position = FAN_POS + Vector3(-2.02, 0, 0)
		bar.rotation.x = TAU * float(i) / 8.0
		add_child(bar)
	# a single amber warning ring reads as a guard without turning the fan into a wheel
	_add_torus("CageWarning", 4.38, 0.06, FAN_POS + Vector3(-1.98, 0, 0), yellow, ring_basis)
	# local work light on the rotor face
	var work := OmniLight3D.new()
	work.position = FAN_POS + Vector3(-2.7, 0.5, -1.4)
	work.light_color = Color(0.42, 0.76, 0.88)
	work.light_energy = 1.2
	work.omni_range = 7.0
	work.shadow_enabled = false
	add_child(work)
	# support frame, anchored to floor and wall
	for z in [-4.1, 4.1]:
		_beam_box(Vector3(11.0, 2.15, -27.0 + z), Vector3(0.42, 4.3, 0.42), dark)
		_beam_box(Vector3(9.8, 0.25, -27.0 + z), Vector3(2.6, 0.5, 0.5), dark)
	for y in [1.2, 8.6]:
		_beam_box(Vector3(10.6, y, -27.0), Vector3(0.5, 0.5, 8.8), dark)
	# motor gearbox on the wall side
	var motor := _mesh_cylinder(0.82, 1.7, 20, Act1MatLib.painted_steel(Color(0.22, 0.34, 0.38)))
	motor.rotation.z = PI * 0.5
	motor.position = FAN_POS + Vector3(1.85, -2.3, 0)
	add_child(motor)
	_beam_box(FAN_POS + Vector3(1.85, -3.5, 0), Vector3(1.2, 1.8, 1.8), dark)
	var motor_band := _mesh_cylinder(0.88, 0.20, 20, yellow)
	motor_band.rotation.z = PI * 0.5
	motor_band.position = FAN_POS + Vector3(1.95, -2.3, 0)
	add_child(motor_band)
	# gauge/status lights on the housing
	for i in range(3):
		var light := _mesh_box(Vector3(0.10, 0.22, 0.22), cyan)
		light.position = FAN_POS + Vector3(-0.6, 4.25, -1.5 + i * 1.5)
		housing.add_child(light)
		status_lights.append(light)
	var fan_label := Label3D.new()
	fan_label.text = "V-07  /  主通风机  ·  MAIN VENTILATION"
	fan_label.font = _font()
	fan_label.font_size = 52
	fan_label.pixel_size = 0.0055
	fan_label.outline_size = 12
	fan_label.modulate = Color(0.96, 0.78, 0.36)
	fan_label.position = Vector3(7.6, 7.5, -22.7)
	fan_label.rotation.y = -PI * 0.5
	add_child(fan_label)


func glossy_yellow() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.62, 0.10)
	m.metallic = 0.45
	m.roughness = 0.32
	return m


func _build_ducts() -> void:
	var steel := Act1MatLib.dark_steel()
	var yellow := Act1MatLib.painted_steel(Color(0.78, 0.55, 0.10))
	# main outlet duct frame: anchored cleanly to VentFloorEast (no pit overhang)
	_beam_box(Vector3(9.8, 9.1, -27.0), Vector3(4.8, 0.5, 6.4), steel)
	_beam_box(Vector3(10.1, 0.50, -27.0), Vector3(4.4, 1.00, 6.4), steel)
	for z_col: float in [-23.9, -30.1]:
		_beam_box(Vector3(7.9, 4.6, z_col), Vector3(0.42, 9.2, 0.42), steel)
		_beam_box(Vector3(9.8, 1.0, z_col), Vector3(4.8, 0.45, 0.40), steel)
	# Dynamic airflow louvers inside main & bypass outlet frames
	for i: int in range(4):
		var ml := Node3D.new()
		ml.name = "MainLouver_%d" % i
		ml.position = Vector3(7.9, 2.2 + float(i) * 1.45, -27.0)
		add_child(ml)
		var ml_vane := _mesh_box(Vector3(0.06, 0.72, 5.4), yellow)
		ml.add_child(ml_vane)
		_main_louvers.append(ml)

		var bl := Node3D.new()
		bl.name = "BypassLouver_%d" % i
		bl.position = Vector3(9.3, 2.2 + float(i) * 1.45, -34.6)
		add_child(bl)
		var bl_vane := _mesh_box(Vector3(2.8, 0.72, 0.06), steel)
		bl.add_child(bl_vane)
		_bypass_louvers.append(bl)
	# bypass duct rising along the east wall then turning south
	_beam_box(Vector3(9.3, 8.9, -30.5), Vector3(3.7, 0.45, 8.8), steel)
	_beam_box(Vector3(7.5, 4.6, -34.9), Vector3(0.45, 9.0, 0.45), steel)
	_beam_box(Vector3(11.1, 4.6, -34.9), Vector3(0.45, 9.0, 0.45), steel)
	# damper in the fan outlet: vertical vane that swings between west and south
	damper_pivot = Node3D.new()
	damper_pivot.name = "DamperPivot"
	damper_pivot.position = FAN_POS + Vector3(-0.9, 0, 0)
	add_child(damper_pivot)
	damper_plate = _mesh_box(Vector3(1.65, 4.0, 0.12), yellow)
	damper_plate.position = Vector3(0, 0, -1.25)
	damper_pivot.add_child(damper_plate)
	for i in range(4):
		var rib := _mesh_box(Vector3(0.07, 4.0, 0.22), steel)
		rib.position = Vector3(-0.62 + i * 0.42, 0, -1.25)
		damper_pivot.add_child(rib)
	var hub_bar := _mesh_cylinder(0.18, 4.6, 12, steel)
	hub_bar.rotation.x = 0
	damper_pivot.add_child(hub_bar)
	var damper_label := Label3D.new()
	damper_label.text = "双风道切断阀  /  DUAL DUCT DAMPER"
	damper_label.font = _font()
	damper_label.font_size = 46
	damper_label.pixel_size = 0.0055
	damper_label.outline_size = 10
	damper_label.modulate = Color(0.95, 0.70, 0.28)
	damper_label.position = Vector3(10.55, 5.8, -33.4)
	damper_label.rotation.y = -PI * 0.5
	add_child(damper_label)
	# duct support braces and rivets
	for z in [-29.9, -27.0, -24.1]:
		_beam_box(Vector3(6.8, 9.2, z), Vector3(9.0, 0.16, 0.16), steel)
	for i in range(8):
		var rivet := _mesh_cylinder(0.10, 0.055, 10, steel)
		rivet.rotation.z = PI * 0.5
		rivet.position = Vector3(8.8, 8.95, -30.0 + i * 0.86)
		add_child(rivet)


func _build_effects() -> void:
	main_particles = _make_wind_particles("MainWind", Vector3(7.0, 5.0, -27.0), Vector3(1.0, 4.3, 2.7), MAIN_DIR, 72)
	bypass_particles = _make_wind_particles("BypassWind", Vector3(8.6, 4.4, -31.0), Vector3(1.3, 3.8, 4.0), BYPASS_DIR, 48)
	for i in range(10):
		var z := -20.7 + float(i) * 1.35
		var streamer := Node3D.new()
		streamer.name = "WindStreamer_%d" % i
		streamer.position = Vector3(3.92, 4.12, z)
		add_child(streamer)
		var strip := _mesh_box(Vector3(0.06, 1.0, 0.16), Act1MatLib.flat(Color(0.74, 0.65, 0.45), 0.95, 0.0))
		strip.position = Vector3(0, -0.5, 0)
		streamer.add_child(strip)
		streamers.append(streamer)


func _make_wind_particles(name: String, pos: Vector3, extents: Vector3, dir: Vector3, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = name
	p.amount = amount
	p.lifetime = 1.6
	p.preprocess = 1.4
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = dir
	p.spread = 9.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color = Color(0.55, 0.78, 0.88, 0.22)
	p.mesh = QuadMesh.new()
	(p.mesh as QuadMesh).size = Vector2(0.08, 0.42)
	p.material_override = Act1MatLib.particle_material(Color(0.45, 0.78, 0.90, 0.35), true)
	p.position = pos
	add_child(p)
	return p


func _build_audio() -> void:
	fan_audio = AudioStreamPlayer3D.new()
	fan_audio.name = "FanLoop"
	fan_audio.position = FAN_POS
	fan_audio.unit_size = 12.0
	fan_audio.max_distance = 42.0
	fan_audio.volume_db = -80.0
	add_child(fan_audio)
	var stream := load("res://act1/assets/audio/tunnel_wind.wav") as AudioStream
	if stream != null:
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(stream as AudioStreamWAV).loop_end = int((stream as AudioStreamWAV).get_length() * 44100.0)
		fan_audio.stream = stream
		fan_audio.play()
	alarm_audio = AudioStreamPlayer3D.new()
	alarm_audio.name = "AlarmLoop"
	alarm_audio.position = FAN_POS + Vector3(-2.0, 0, 0)
	alarm_audio.unit_size = 8.0
	alarm_audio.max_distance = 30.0
	alarm_audio.volume_db = -80.0
	add_child(alarm_audio)
	var alarm := load("res://act1/assets/audio/alarm.wav") as AudioStream
	if alarm != null:
		if alarm is AudioStreamWAV:
			(alarm as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(alarm as AudioStreamWAV).loop_end = int((alarm as AudioStreamWAV).get_length() * 44100.0)
		alarm_audio.stream = alarm
		alarm_audio.play()


func set_running(value: bool) -> void:
	running = value


func set_governor(value: float) -> void:
	governor = clampf(value, 0.0, 1.0)


## The next gear a governor press will select. Kept static so the HUD, the press
## handler and the tests all read the same cycle (62% default -> 100% -> 55% ->
## 78% -> 100% ...).
static func next_governor_value(value: float) -> float:
	if value < 0.60:
		return GOVERNOR_MID
	if value < 0.85:
		return GOVERNOR_HIGH
	return GOVERNOR_LOW


func set_damper_target(value: float) -> void:
	damper_target = clampf(value, 0.0, 1.0)


func set_emergency(value: bool) -> void:
	emergency = value


func get_pressure() -> float:
	return pressure


func main_flow() -> float:
	return _smooth_main


func bypass_flow() -> float:
	return _smooth_bypass


func _box_weight(box: AABB, at: Vector3, edge_margin: float = 1.25) -> float:
	if not box.has_point(at):
		return 0.0
	var dx: float = minf(at.x - box.position.x, box.position.x + box.size.x - at.x)
	var dz: float = minf(at.z - box.position.z, box.position.z + box.size.z - at.z)
	var dy: float = minf(at.y - box.position.y, box.position.y + box.size.y - at.y)
	var d: float = minf(dx, minf(dz, dy))
	return smoothstep(0.0, edge_margin, d)


func get_wind_acceleration(at: Vector3, grabbing: bool = false) -> Vector3:
	if not running or emergency:
		return Vector3.ZERO
	var main_w: float = _box_weight(MAIN_BOX, at)
	var byp_w: float = _box_weight(BYPASS_BOX, at)
	var main_acc: Vector3 = MAIN_DIR * _smooth_main * main_w * 4.35
	var byp_acc: Vector3 = BYPASS_DIR * _smooth_bypass * byp_w * 3.25
	var acc: Vector3 = byp_acc if byp_acc.length_squared() > main_acc.length_squared() else main_acc
	if grabbing:
		acc *= 0.08
	return acc * gust_factor


func get_wind_strength_at(at: Vector3) -> float:
	return get_wind_acceleration(at, false).length()


func _physics_process(delta: float) -> void:
	var target_speed := governor if running and not emergency else 0.0
	var inertia := 0.38 if target_speed > speed else 0.28
	speed = move_toward(speed, target_speed, inertia * delta)
	damper = move_toward(damper, damper_target, 0.42 * delta)
	pressure = speed * (0.28 + 0.72 * damper)
	_smooth_main = lerpf(_smooth_main, speed * (0.12 + 0.88 * damper), 1.0 - exp(-3.0 * delta))
	_smooth_bypass = lerpf(_smooth_bypass, speed * (0.16 + 0.84 * (1.0 - damper)), 1.0 - exp(-3.0 * delta))
	if rotor != null:
		rotor.rotation.x += speed * delta * 7.2
	if damper_pivot != null:
		damper_pivot.rotation.y = lerp_angle(damper_pivot.rotation.y, -PI * 0.5 * damper, 0.08)
	var main_tilt: float = lerpf(0.08, 1.18, damper) * clampf(0.25 + speed * 0.85, 0.25, 1.1)
	for lv: Node3D in _main_louvers:
		lv.rotation.z = lerpf(lv.rotation.z, main_tilt, 0.14)
	var byp_tilt: float = lerpf(1.18, 0.08, damper) * clampf(0.25 + speed * 0.85, 0.25, 1.1)
	for lv2: Node3D in _bypass_louvers:
		lv2.rotation.x = lerpf(lv2.rotation.x, -byp_tilt, 0.14)
	if main_particles != null:
		main_particles.emitting = speed > 0.02 and _smooth_main > 0.02
		main_particles.amount = maxi(8, int(72.0 * clampf(_smooth_main / 0.9, 0.0, 1.0)))
	if bypass_particles != null:
		bypass_particles.emitting = speed > 0.02 and _smooth_bypass > 0.02
		bypass_particles.amount = maxi(6, int(48.0 * clampf(_smooth_bypass / 0.9, 0.0, 1.0)))
	for i in range(streamers.size()):
		var s := streamers[i]
		var flutter := sin(Time.get_ticks_msec() * 0.006 + float(i) * 0.8) * 0.10
		var angle := -PI * 0.5 * clampf(_smooth_main * 1.5, 0.0, 1.0) + flutter * _smooth_main
		s.rotation.z = lerp_angle(s.rotation.z, angle, 0.18)
		s.rotation.x = lerp_angle(s.rotation.x, flutter * 0.5, 0.12)
	# audio follows the machine, with a mechanical low band under the wind
	if fan_audio != null:
		var target_db := -60.0 if speed < 0.01 else lerpf(-26.0, -7.0, speed)
		fan_audio.volume_db = lerpf(fan_audio.volume_db, target_db, 0.08)
		fan_audio.pitch_scale = 0.72 + speed * 0.52
	if alarm_audio != null:
		var alarm_on := gust_factor > 1.15 or (running and pressure > 0.78)
		alarm_audio.volume_db = lerpf(alarm_audio.volume_db, -8.0 if alarm_on else -80.0, 0.06)
	if status_lights.size() > 0:
		for i in range(status_lights.size()):
			var m := status_lights[i].material_override as StandardMaterial3D
			if m != null:
				m.emission_energy_multiplier = 0.3 + 1.8 * speed + sin(Time.get_ticks_msec() * 0.008 + i) * 0.15
	if authority_test:
		if running and not emergency and damper > DAMPER_OPEN_MIN and pressure > PRESSURE_MIN:
			pressure_test_seconds += delta
			if pressure_test_seconds >= PRESSURE_TEST_SECONDS:
				vent_complete = true
		else:
			pressure_test_seconds = maxf(0.0, pressure_test_seconds - delta * 0.5)


func snapshot() -> Dictionary:
	return {
		"running": running,
		"emergency": emergency,
		"speed": speed,
		"governor": governor,
		"damper": damper,
		"damper_target": damper_target,
		"pressure": pressure,
		"gust": gust_factor,
		"test": pressure_test_seconds,
		"complete": vent_complete,
	}


func apply_snapshot(data: Dictionary) -> void:
	running = bool(data.get("running", running))
	emergency = bool(data.get("emergency", emergency))
	speed = float(data.get("speed", speed))
	governor = float(data.get("governor", governor))
	damper = float(data.get("damper", damper))
	damper_target = float(data.get("damper_target", damper_target))
	pressure = float(data.get("pressure", pressure))
	gust_factor = float(data.get("gust", gust_factor))
	pressure_test_seconds = float(data.get("test", pressure_test_seconds))
	vent_complete = bool(data.get("complete", vent_complete))
	_smooth_main = speed * (0.12 + 0.88 * damper)
	_smooth_bypass = speed * (0.16 + 0.84 * (1.0 - damper))


func reset_vent() -> void:
	running = false
	emergency = false
	speed = 0.0
	governor = 0.62
	damper = 0.0
	damper_target = 0.0
	pressure = 0.0
	gust_factor = 1.0
	pressure_test_seconds = 0.0
	vent_complete = false
	_smooth_main = 0.0
	_smooth_bypass = 0.0
	if damper_pivot != null:
		damper_pivot.rotation.y = 0.0


func _mesh_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


func _mesh_cylinder(radius: float, height: float, segments: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
	mi.mesh = cm
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


func _beam_box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := _mesh_box(size, mat)
	mi.position = pos
	add_child(mi)
	return mi


func _add_torus(name: String, radius: float, tube: float, pos: Vector3, mat: Material, basis: Basis) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 48
	var sides := 8
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		for j in range(sides):
			var b0 := TAU * float(j) / float(sides)
			var b1 := TAU * float(j + 1) / float(sides)
			var p00 := _torus_pt(radius, tube, a0, b0)
			var p01 := _torus_pt(radius, tube, a0, b1)
			var p11 := _torus_pt(radius, tube, a1, b1)
			var p10 := _torus_pt(radius, tube, a1, b0)
			_st_tri(st, p00, p10, p11)
			_st_tri(st, p00, p11, p01)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)


func _add_ring(name: String, radius: float, width: float, height: float, pos: Vector3, mat: Material, basis: Basis, segments: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ro := radius + width * 0.5
	var ri := radius - width * 0.5
	var yt := height * 0.5
	var yb := -height * 0.5
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var c0 := Vector3(cos(a0), 0, sin(a0))
		var c1 := Vector3(cos(a1), 0, sin(a1))
		_st_quad(st, c0 * ro + Vector3(0, yb, 0), c1 * ro + Vector3(0, yb, 0), c1 * ro + Vector3(0, yt, 0), c0 * ro + Vector3(0, yt, 0), c0, c1)
		_st_quad(st, c1 * ri + Vector3(0, yb, 0), c0 * ri + Vector3(0, yb, 0), c0 * ri + Vector3(0, yt, 0), c1 * ri + Vector3(0, yt, 0), -c1, -c0)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)


func _torus_pt(radius: float, tube: float, a: float, b: float) -> Vector3:
	var center := Vector3(cos(a) * radius, sin(b) * tube, sin(a) * radius)
	var dir := Vector3(cos(a), 0, sin(a))
	return center + dir * cos(b) * tube


func _st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_normal((b - a).cross(c - a).normalized())
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _st_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, _na: Vector3, _nb: Vector3) -> void:
	_st_tri(st, a, b, c)
	_st_tri(st, a, c, d)


func _font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return font