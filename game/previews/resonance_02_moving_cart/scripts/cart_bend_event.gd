extends Node3D

# M4 · Resonance Bend Event
# The event is a state machine driven by the cart's real distance and speed.
# It never runs on a fixed animation timeline: if the player brakes or reverses
# the state machine, the crystals, hum and warning all follow the actual cart.
signal phase_changed(phase: String, previous: String)

const ENTER_START: float = 29.0
const ENTER_FULL: float = 32.5
const PEAK_START: float = 38.0
const EXIT_START: float = 42.5
const EXIT_END: float = 46.0
# Above this speed the bend actually disturbs loose cargo.
const DISTURB_SPEED: float = 0.35

var stage: Node3D
var cart: AnimatableBody3D
var crystals: Array[MeshInstance3D] = []
var crystal_materials: Array[StandardMaterial3D] = []
var alarm: AudioStreamPlayer3D
var phase: String = "idle"
var intensity: float = 0.0
var clock: float = 0.0
var warning_cooldown: float = 0.0
var phase_log: Array[Dictionary] = []

func _ready() -> void:
	_build_crystals()
	_build_alarm()

func _build_crystals() -> void:
	var route: GDScript = preload("res://scripts/moving_cart.gd")
	# Crystals line the unstable bend so the effect is visible from the deck.
	for s: float in [30.5, 34.0, 37.5, 41.0, 44.5]:
		var z_offset: float = 2.2 + float(route.bend(s))
		for side: float in [-1.0, 1.0]:
			var mesh: MeshInstance3D = MeshInstance3D.new()
			var crystal: PrismMesh = PrismMesh.new()
			crystal.size = Vector3(0.55, 1.5, 0.55)
			mesh.mesh = crystal
			var material: StandardMaterial3D = StandardMaterial3D.new()
			material.albedo_color = Color("3fd6e0")
			material.emission_enabled = true
			material.emission = Color("59e6f0")
			material.emission_energy_multiplier = 0.35
			material.roughness = 0.22
			material.metallic = 0.1
			mesh.material_override = material
			mesh.position = Vector3(s, 1.35, z_offset + side * 3.35)
			mesh.rotation.z = side * 0.22
			add_child(mesh)
			crystals.append(mesh)
			crystal_materials.append(material)

func _build_alarm() -> void:
	alarm = AudioStreamPlayer3D.new()
	alarm.stream = load("res://assets/audio/error.wav") as AudioStream
	alarm.volume_db = -14.0
	alarm.max_distance = 26.0
	alarm.position = Vector3(38.0, 2.6, 2.2 + float(preload("res://scripts/moving_cart.gd").bend(38.0)))
	add_child(alarm)

func _physics_process(delta: float) -> void:
	if cart == null: return
	clock += delta
	warning_cooldown = maxf(0.0, warning_cooldown - delta)
	var distance: float = float(cart.get("distance"))
	var speed: float = float(cart.get("speed"))
	var previous: String = phase
	if distance < ENTER_START or speed < 0.05:
		phase = "idle"
	elif distance < ENTER_FULL:
		phase = "approaching"
	elif distance < PEAK_START:
		phase = "entering"
	elif distance < EXIT_START:
		phase = "peak"
	elif distance < EXIT_END:
		phase = "leaving"
	else:
		phase = "cleared"
	if phase != previous:
		_enter(previous)
	# Intensity follows the actual position inside the bend, not wall-clock time.
	var envelope: float = smoothstep(ENTER_START, ENTER_FULL, distance) * (1.0 - smoothstep(EXIT_START, EXIT_END, distance))
	intensity = envelope if speed > 0.05 else 0.0
	_apply_crystals()
	_apply_alarm()

func _enter(previous: String) -> void:
	phase_log.append({"phase": phase, "previous": previous, "distance": float(cart.get("distance")), "time": clock})
	phase_changed.emit(phase, previous)
	if phase == "approaching":
		stage.set("feedback", "前方共振矿脉不稳定 · 未固定货物会被甩动。可 B 制动，或走到扶手按 E 抓扶。")
	elif phase == "peak":
		stage.set("feedback", "共振峰值 · 未固定容器正在滑动。抓扶可稳住身体，或立即 B 制动停车处理。")
	elif phase == "cleared":
		stage.set("feedback", "已通过共振弯道 · 检查货物状态，继续前往终点。")

func _apply_crystals() -> void:
	var pulse: float = 0.5 + 0.5 * sin(clock * (3.0 + 5.0 * intensity))
	for i: int in range(crystal_materials.size()):
		var offset: float = float(i) * 0.7
		var local_pulse: float = 0.5 + 0.5 * sin(clock * (3.0 + 5.0 * intensity) + offset)
		crystal_materials[i].emission_energy_multiplier = 0.30 + 2.6 * intensity * local_pulse
		crystal_materials[i].emission = Color("59e6f0").lerp(Color("ffb35c"), intensity * 0.65)
	for mesh: MeshInstance3D in crystals:
		mesh.scale = Vector3.ONE * (1.0 + 0.06 * intensity * pulse)

func _apply_alarm() -> void:
	if alarm == null: return
	alarm.volume_db = -30.0 + 16.0 * intensity
	alarm.pitch_scale = 0.85 + 0.5 * intensity
	if intensity > 0.45 and not alarm.playing:
		alarm.play()
	elif intensity <= 0.05 and alarm.playing:
		alarm.stop()

func disturbs_cargo() -> bool:
	return intensity > 0.15 and float(cart.get("speed")) > DISTURB_SPEED
