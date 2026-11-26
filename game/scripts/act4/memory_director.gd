class_name MemoryDirector
extends Node3D
## Three short, replaceable memory performances. Each one is staged in 3D:
## work lamps, a ghost ore cart, alarm lamps and steam, a ghost miner cutting
## the rail. Subtitle lines come from assets/story/story.json.

signal memory_started(index: int)
signal memory_finished(index: int)
signal subtitle_requested(speaker: String, text: String, duration: float)
signal camera_shake(strength: float, duration: float)
signal exit_opened

const GHOST_SHADER: Shader = preload("res://shaders/ghost.gdshader")
const STORY_PATH := "res://assets/story/story.json"
const TRACK_X := 16.65
const TRACK_Y := 2.15

var memories: Dictionary = {}
var gate: ExitGate
var crystals: Dictionary = {}
var audio: Node
var playing: bool = false

var _token: int = 0
var _cart: Node3D
var _cart_material: ShaderMaterial
var _cart_wheels: Array[Node3D] = []
var _work_lamps: Array[Dictionary] = []
var _alarm_lamps: Array[Dictionary] = []
var _steam: Array[CPUParticles3D] = []
var _workers: Array[Node3D] = []
var _worker_materials: Array[ShaderMaterial] = []
var _miner: Node3D
var _miner_material: ShaderMaterial
var _sparks: CPUParticles3D
var _cut_light: OmniLight3D
var _cut_glow: MeshInstance3D
var _cut_glow_material: StandardMaterial3D
var _loose_rail: MeshInstance3D
var _gate_opened_in_memory: bool = false
var _cart_roll_started: bool = false
var _alarm_started: bool = false


func build(data: Dictionary) -> void:
	name = "MemoryDirector"
	audio = get_tree().get_first_node_in_group("audio_director")
	gate = data.get("gate") as ExitGate
	crystals = data.get("crystals", {}) as Dictionary
	_load_story()
	_build_track()
	_build_work_lamps()
	_build_cart()
	_build_alarm_and_steam()
	_build_workers()
	_build_cut_scene()
	reset_all()


func _load_story() -> void:
	var text: String = FileAccess.get_file_as_string(STORY_PATH)
	if text.is_empty():
		push_error("Story JSON missing: " + STORY_PATH)
		return
	var parsed: Dictionary = JSON.parse_string(text) as Dictionary
	if parsed == null:
		return
	var list: Array = parsed.get("memories", []) as Array
	for entry: Dictionary in list:
		memories[int(entry.get("id", 0))] = entry


func _lines_for(index: int) -> Array:
	var data: Dictionary = memories.get(index, {}) as Dictionary
	return data.get("lines", []) as Array


func _duration_for(index: int) -> float:
	var data: Dictionary = memories.get(index, {}) as Dictionary
	return float(data.get("duration", 12.0))


func _mesh_material(material: Material, node: Node3D) -> void:
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh != null:
			mesh.material_override = material


func _ghost_material(tint: Color, strength: float = 0.65) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = GHOST_SHADER
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("strength", strength)
	return material


func _build_track() -> void:
	var track: Node3D = Node3D.new()
	track.name = "EastTrack"
	add_child(track)
	var rail_metal: StandardMaterial3D = MaterialLibrary.metal(Color(0.38, 0.39, 0.40), 0.42, 0.85)
	var sleeper_wood: StandardMaterial3D = MaterialLibrary.painted(Color(0.24, 0.18, 0.12), 0.92)
	var warning: StandardMaterial3D = MaterialLibrary.painted(Color(0.82, 0.42, 0.09), 0.6)
	for side: int in range(2):
		var x: float = TRACK_X + (-0.40 if side == 0 else 0.40)
		BuildKit.box_visual(track, "RailNorth%d" % side, Vector3(0.10, 0.12, 4.6), Vector3(x, TRACK_Y, -13.9), rail_metal)
		BuildKit.box_visual(track, "RailSouth%d" % side, Vector3(0.10, 0.12, 4.4), Vector3(x, TRACK_Y, -9.1), rail_metal)
		BuildKit.box_visual(track, "RailWear%d" % side, Vector3(0.13, 0.02, 9.0), Vector3(x, TRACK_Y + 0.07, -11.5), MaterialLibrary.metal(Color(0.62, 0.64, 0.66), 0.25, 0.9))
	for index: int in range(12):
		var z: float = -16.0 + index * 0.8
		BuildKit.box_visual(track, "Sleeper%d" % index, Vector3(1.35, 0.10, 0.24), Vector3(TRACK_X, TRACK_Y - 0.10, z), sleeper_wood)
	# The deliberate gap is visible from the start.
	BuildKit.box_visual(track, "GapWarnA", Vector3(1.5, 0.04, 0.10), Vector3(TRACK_X, TRACK_Y + 0.09, -11.62), warning)
	BuildKit.box_visual(track, "GapWarnB", Vector3(1.5, 0.04, 0.10), Vector3(TRACK_X, TRACK_Y + 0.09, -11.08), warning)
	_loose_rail = BuildKit.box_visual(track, "LooseRail", Vector3(0.10, 0.12, 1.5), Vector3(17.55, TRACK_Y + 0.25, -11.35), rail_metal, Vector3(0.0, 0.0, 18.0))
	_loose_rail.visible = false

	_cut_glow = BuildKit.box_visual(track, "CutGlow", Vector3(1.7, 0.02, 0.42), Vector3(TRACK_X, TRACK_Y + 0.11, -11.35), MaterialLibrary.emissive(Color(1.0, 0.42, 0.12), 0.0))
	_cut_glow_material = (_cut_glow.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	_cut_glow.material_override = _cut_glow_material

	var cut_sign: Label3D = Label3D.new()
	cut_sign.name = "CutSign"
	cut_sign.text = "东三轨 · 封锁"
	var cut_font: SystemFont = SystemFont.new()
	cut_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "SimHei", "sans-serif"])
	cut_font.allow_system_fallback = true
	cut_sign.font = cut_font
	cut_sign.font_size = 44
	cut_sign.pixel_size = 0.0045
	cut_sign.modulate = Color(0.95, 0.55, 0.24)
	cut_sign.outline_size = 8
	cut_sign.outline_modulate = Color(0.05, 0.03, 0.02, 0.9)
	cut_sign.position = Vector3(16.65, 3.35, -10.24)
	cut_sign.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	track.add_child(cut_sign)
	# The sign used to be text floating above the track. A post and a plate make
	# it a physical object the miner actually bolted there.
	BuildKit.cylinder_visual(track, "CutSignPost", 0.045, 1.4, Vector3(16.65, 2.70, -10.26), rail_metal)
	BuildKit.box_visual(track, "CutSignPlate", Vector3(1.02, 0.42, 0.03), Vector3(16.65, 3.35, -10.28), warning)
	BuildKit.box_visual(track, "CutSignPlateBack", Vector3(1.06, 0.46, 0.02), Vector3(16.65, 3.35, -10.30), rail_metal)


func _build_work_lamps() -> void:
	var post_metal: StandardMaterial3D = MaterialLibrary.metal(Color(0.25, 0.28, 0.31), 0.55, 0.7)
	for index: int in range(4):
		var z: float = -8.0 - index * 2.55
		var root: Node3D = Node3D.new()
		root.name = "WorkLamp%d" % index
		# Against the east wall and shining west across the track: the old row at
		# x = 14.9 stood between the player and the memory performance.
		root.position = Vector3(18.15, 2.0, z)
		add_child(root)
		BuildKit.cylinder_visual(root, "Post", 0.06, 3.1, Vector3(0.0, 1.55, 0.0), post_metal)
		BuildKit.box_visual(root, "Arm", Vector3(0.08, 0.08, 1.0), Vector3(-0.48, 3.05, 0.0), post_metal)
		var shade: MeshInstance3D = BuildKit.cylinder_visual(root, "Shade", 0.30, 0.32, Vector3(-0.95, 2.92, 0.0), post_metal, Vector3.ZERO, 0.10)
		shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var bulb_material: StandardMaterial3D = (MaterialLibrary.emissive(Color(1.0, 0.62, 0.24), 0.0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		var bulb: MeshInstance3D = BuildKit.sphere_visual(root, "Bulb", 0.13, Vector3(-0.95, 2.76, 0.0), bulb_material)
		var light: OmniLight3D = BuildKit.omni_light(root, "Light", Vector3(-0.95, 2.70, 0.0), Color(1.0, 0.70, 0.38), 0.0, 6.0, false)
		_work_lamps.append({"root": root, "bulb": bulb, "material": bulb_material, "light": light, "energy": 0.0})


func _build_cart() -> void:
	_cart = Node3D.new()
	_cart.name = "GhostCart"
	_cart.position = Vector3(TRACK_X, TRACK_Y, -16.0)
	_cart.scale = Vector3.ONE * 1.30
	add_child(_cart)
	_cart_material = _ghost_material(Color(1.0, 0.70, 0.34), 0.88)
	# Open-deck ore cart: chassis, slatted sides, corner posts, rim, ore load,
	# tow bar and brake lever. The old version was one 1.25 x 0.70 x 1.95 box,
	# which read as a floating crate next to the new miner figures.
	BuildKit.box_visual(_cart, "CartChassis", Vector3(1.12, 0.13, 1.86), Vector3(0.0, 0.50, 0.0), _cart_material)
	for side: int in range(2):
		var sx: float = -0.61 if side == 0 else 0.61
		BuildKit.box_visual(_cart, "CartSlatLow%d" % side, Vector3(0.06, 0.18, 1.90), Vector3(sx, 0.68, 0.0), _cart_material)
		BuildKit.box_visual(_cart, "CartSlatHigh%d" % side, Vector3(0.06, 0.16, 1.90), Vector3(sx, 0.92, 0.0), _cart_material)
		BuildKit.box_visual(_cart, "CartSlatTop%d" % side, Vector3(0.06, 0.12, 1.90), Vector3(sx, 1.09, 0.0), _cart_material)
		for end_value: float in [-0.93, 0.93]:
			BuildKit.box_visual(_cart, "CartPost%d_%d" % [side, int(end_value * 10.0)], Vector3(0.10, 0.72, 0.10),
				Vector3(sx, 0.86, end_value), _cart_material)
	BuildKit.box_visual(_cart, "CartEndA", Vector3(1.22, 0.62, 0.06), Vector3(0.0, 0.84, -0.96), _cart_material)
	BuildKit.box_visual(_cart, "CartEndB", Vector3(1.22, 0.62, 0.06), Vector3(0.0, 0.84, 0.96), _cart_material)
	BuildKit.box_visual(_cart, "CartRimA", Vector3(1.34, 0.07, 0.10), Vector3(0.0, 1.17, -0.99), _cart_material)
	BuildKit.box_visual(_cart, "CartRimB", Vector3(1.34, 0.07, 0.10), Vector3(0.0, 1.17, 0.99), _cart_material)
	# Ore load: faceted lumps that break the cart's rectangle.
	for index: int in range(4):
		var ore: MeshInstance3D = BuildKit.sphere_visual(_cart, "Ore%d" % index, 0.30,
			Vector3(-0.24 + float(index % 2) * 0.5, 1.02 + float(index / 2) * 0.10, -0.35 + float(index / 2) * 0.62),
			_cart_material)
		ore.scale = Vector3(1.05, 0.62, 1.15)
	var wheel_mesh: CylinderMesh = CylinderMesh.new()
	wheel_mesh.top_radius = 0.32
	wheel_mesh.bottom_radius = 0.32
	wheel_mesh.height = 0.13
	wheel_mesh.radial_segments = 14
	for index: int in range(4):
		var wheel: MeshInstance3D = MeshInstance3D.new()
		wheel.name = "Wheel%d" % index
		wheel.mesh = wheel_mesh
		wheel.material_override = _cart_material
		wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		wheel.position = Vector3(-0.64 if index % 2 == 0 else 0.64, 0.33, -0.62 if index < 2 else 0.62)
		_cart.add_child(wheel)
		_cart_wheels.append(wheel)
		for spoke_index: int in range(3):
			BuildKit.box_visual(_cart, "Spoke%d_%d" % [index, spoke_index], Vector3(0.04, 0.58, 0.05),
				wheel.position, _cart_material, Vector3(float(spoke_index) * 60.0, 0.0, 0.0))
	# Tow bar and brake lever.
	BuildKit.cylinder_visual(_cart, "TowBar", 0.045, 1.10, Vector3(0.0, 0.42, -1.48), _cart_material, Vector3(90.0, 0.0, 0.0))
	BuildKit.cylinder_visual(_cart, "TowHook", 0.075, 0.10, Vector3(0.0, 0.42, -2.02), _cart_material)
	BuildKit.box_visual(_cart, "BrakeLever", Vector3(0.05, 0.52, 0.05), Vector3(0.52, 1.12, 0.86), _cart_material, Vector3(-22.0, 0.0, 6.0))
	var lamp_bulb: MeshInstance3D = BuildKit.sphere_visual(_cart, "FrontLamp", 0.09, Vector3(0.0, 1.22, -1.05), MaterialLibrary.emissive(Color(1.0, 0.80, 0.45), 1.6))
	lamp_bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cart_glow: OmniLight3D = BuildKit.omni_light(_cart, "CartGlow", Vector3(0.0, 1.15, -0.3), Color(1.0, 0.66, 0.30), 3.0, 7.5, false)
	cart_glow.light_energy = 3.0
	var driver: GhostMiner = GhostMiner.new()
	driver.name = "GhostDriver"
	driver.position = Vector3(0.0, 0.72, 0.38)
	_cart.add_child(driver)
	if driver.build(Color(0.55, 0.85, 1.0), 0.82, 0.58):
		driver.rotation.y = PI
		_worker_materials.append(driver._material)
	else:
		driver.queue_free()
	_cart.visible = false


func _build_alarm_and_steam() -> void:
	var fixture: StandardMaterial3D = MaterialLibrary.metal(Color(0.22, 0.24, 0.27), 0.55, 0.7)
	for index: int in range(2):
		var z: float = -9.6 - index * 4.4
		var root: Node3D = Node3D.new()
		root.name = "AlarmLamp%d" % index
		root.position = Vector3(12.25, 4.3, z)
		add_child(root)
		BuildKit.box_visual(root, "Bracket", Vector3(0.6, 0.12, 0.12), Vector3(0.0, 0.0, 0.0), fixture)
		# The lamp used to be a bracket and a bulb floating 4.3 m in the air.
		# A post down to the production shelf grounds it.
		BuildKit.cylinder_visual(root, "AlarmPost", 0.06, 2.30, Vector3(0.0, -1.15, 0.0), fixture)
		BuildKit.cylinder_visual(root, "AlarmFoot", 0.17, 0.08, Vector3(0.0, -2.28, 0.0), fixture)
		var bulb_material: StandardMaterial3D = (MaterialLibrary.emissive(Color(0.9, 0.12, 0.08), 0.0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		var bulb: MeshInstance3D = BuildKit.sphere_visual(root, "Bulb", 0.19, Vector3(0.25, 0.05, 0.0), bulb_material)
		var light: OmniLight3D = BuildKit.omni_light(root, "Light", Vector3(0.25, 0.05, 0.0), Color(1.0, 0.14, 0.08), 0.0, 7.0, false)
		_alarm_lamps.append({"root": root, "bulb": bulb, "material": bulb_material, "light": light})

	for index: int in range(3):
		var vent_position: Vector3 = Vector3(7.6, 1.1, -4.8) if index == 0 else (Vector3(4.2, 1.0, -1.6) if index == 1 else Vector3(-2.4, 1.2, -3.8))
		# Floor-standing steam riser: the old vents were horizontal pipes hanging
		# at chest height with nothing holding them up.
		BuildKit.cylinder_visual(self, "SteamRiser%d" % index, 0.085, vent_position.y, Vector3(vent_position.x, vent_position.y * 0.5, vent_position.z), fixture)
		BuildKit.cylinder_visual(self, "SteamFlange%d" % index, 0.16, 0.07, Vector3(vent_position.x, 0.04, vent_position.z), fixture)
		BuildKit.cylinder_visual(self, "SteamVent%d" % index, 0.11, 0.6, vent_position, fixture, Vector3(90.0, 0.0, 0.0))
		BuildKit.cylinder_visual(self, "SteamElbow%d" % index, 0.13, 0.12, Vector3(vent_position.x, vent_position.y, vent_position.z + 0.30), fixture, Vector3(90.0, 0.0, 0.0))
		var particles: CPUParticles3D = CPUParticles3D.new()
		particles.name = "Steam%d" % index
		particles.amount = 24
		particles.lifetime = 1.6
		particles.one_shot = false
		particles.emitting = false
		particles.direction = Vector3(0.2, 1.0, 0.0)
		particles.spread = 22.0
		particles.initial_velocity_min = 0.8
		particles.initial_velocity_max = 1.9
		particles.gravity = Vector3(0.0, 0.5, 0.0)
		particles.scale_amount_min = 0.16
		particles.scale_amount_max = 0.42
		particles.color = Color(0.78, 0.84, 0.90, 0.18)
		var puff: SphereMesh = SphereMesh.new()
		puff.radius = 0.18
		puff.height = 0.36
		puff.radial_segments = 6
		puff.rings = 3
		particles.mesh = puff
		var puff_material: StandardMaterial3D = StandardMaterial3D.new()
		puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff_material.albedo_color = Color(0.78, 0.84, 0.90, 0.10)
		particles.material_override = puff_material
		particles.position = vent_position + Vector3(0.0, 0.4, 0.0)
		add_child(particles)
		_steam.append(particles)


func _make_humanoid(root: Node3D, material: ShaderMaterial, helmet_color: Color) -> void:
	var body_mesh: CapsuleMesh = CapsuleMesh.new()
	body_mesh.radius = 0.26
	body_mesh.height = 1.15
	body_mesh.radial_segments = 8
	body_mesh.rings = 4
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_mesh
	body.position = Vector3(0.0, 1.03, 0.0)
	body.material_override = material
	root.add_child(body)
	var head: MeshInstance3D = BuildKit.sphere_visual(root, "Head", 0.23, Vector3(0.0, 1.75, 0.0), material)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	BuildKit.box_visual(root, "LegL", Vector3(0.17, 0.62, 0.20), Vector3(-0.14, 0.34, 0.0), material)
	BuildKit.box_visual(root, "LegR", Vector3(0.17, 0.62, 0.20), Vector3(0.14, 0.34, 0.0), material)
	BuildKit.box_visual(root, "ArmL", Vector3(0.14, 0.58, 0.16), Vector3(-0.35, 1.10, 0.0), material)
	BuildKit.box_visual(root, "ArmR", Vector3(0.14, 0.58, 0.16), Vector3(0.35, 1.10, 0.0), material)
	var helmet: MeshInstance3D = BuildKit.sphere_visual(root, "HelmetLamp", 0.07, Vector3(0.0, 1.86, -0.20), MaterialLibrary.emissive(helmet_color, 1.4))
	helmet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_workers() -> void:
	for index: int in range(3):
		var worker: GhostMiner = GhostMiner.new()
		worker.name = "GhostWorker%d" % index
		add_child(worker)
		if not worker.build(Color(0.55, 0.82, 1.0), 0.5, 0.86):
			worker.queue_free()
			continue
		worker.visible = false
		_workers.append(worker)
		_worker_materials.append(worker._material)


func _build_cut_scene() -> void:
	_miner = GhostMiner.new()
	_miner.name = "GhostMiner"
	_miner.position = Vector3(15.55, 2.0, -11.35)
	_miner.rotation.y = deg_to_rad(-90.0)
	add_child(_miner)
	if _miner.build(Color(0.62, 0.88, 1.0), 0.75, 0.84):
		_miner_material = _miner._material
		var cutter: MeshInstance3D = BuildKit.box_visual(_miner, "Cutter", Vector3(0.09, 0.62, 0.09),
			Vector3(0.0, -0.34, -0.02), _ghost_material(Color(1.0, 0.72, 0.32), 0.95))
		_miner.attach_to_hand(cutter, Vector3(0.0, -0.30, -0.06), Vector3(18.0, 0.0, -8.0))
		BuildKit.box_visual(cutter, "CutterBlade", Vector3(0.24, 0.035, 0.06), Vector3(0.0, -0.34, 0.0),
			MaterialLibrary.emissive(Color(1.0, 0.62, 0.24), 1.4))
	_miner.visible = false

	_sparks = CPUParticles3D.new()
	_sparks.name = "CutSparks"
	_sparks.amount = 64
	_sparks.lifetime = 0.9
	_sparks.one_shot = true
	_sparks.emitting = false
	_sparks.explosiveness = 0.95
	_sparks.direction = Vector3(-0.2, 0.8, 0.1)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 1.8
	_sparks.initial_velocity_max = 5.5
	_sparks.gravity = Vector3(0.0, -6.0, 0.0)
	_sparks.scale_amount_min = 0.03
	_sparks.scale_amount_max = 0.09
	_sparks.color = Color(1.0, 0.72, 0.30, 0.95)
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 5
	mesh.rings = 3
	_sparks.mesh = mesh
	_sparks.material_override = MaterialLibrary.emissive(Color(1.0, 0.66, 0.24), 3.2)
	_sparks.position = Vector3(16.55, 2.35, -11.35)
	add_child(_sparks)
	_cut_light = BuildKit.omni_light(self, "CutFlash", Vector3(16.5, 2.8, -11.35), Color(1.0, 0.50, 0.18), 0.0, 5.5, false)


func _set_lamp(index: int, energy: float) -> void:
	if index < 0 or index >= _work_lamps.size():
		return
	var entry: Dictionary = _work_lamps[index]
	var light: OmniLight3D = entry["light"] as OmniLight3D
	var material: StandardMaterial3D = entry["material"] as StandardMaterial3D
	light.light_energy = energy
	material.emission_energy_multiplier = 0.15 + energy * 1.6
	entry["energy"] = energy


func _set_alarm(index: int, energy: float) -> void:
	if index < 0 or index >= _alarm_lamps.size():
		return
	var entry: Dictionary = _alarm_lamps[index]
	var light: OmniLight3D = entry["light"] as OmniLight3D
	var material: StandardMaterial3D = entry["material"] as StandardMaterial3D
	light.light_energy = energy
	material.emission_energy_multiplier = 0.1 + energy * 2.4


func play(index: int) -> void:
	if playing:
		return
	playing = true
	_token += 1
	var token: int = _token
	memory_started.emit(index)
	var duration: float = _duration_for(index)
	var lines: Array = _lines_for(index)
	var next_line: int = 0
	var elapsed: float = 0.0
	_start_visuals(index)
	while true:
		await get_tree().process_frame
		if token != _token:
			return
		elapsed += get_process_delta_time()
		while next_line < lines.size():
			var line: Dictionary = lines[next_line] as Dictionary
			if float(line.get("t", 0.0)) > elapsed:
				break
			subtitle_requested.emit(str(line.get("speaker", "")), str(line.get("text", "")), 3.8)
			next_line += 1
		_update_visuals(index, elapsed, duration)
		if elapsed >= duration:
			break
	_finish_visuals(index)
	memory_finished.emit(index)
	playing = false


func _start_visuals(index: int) -> void:
	match index:
		1:
			_cart.visible = true
			_cart.position = Vector3(TRACK_X, TRACK_Y, -16.0)
			_cart_material.set_shader_parameter("strength", 0.0)
			for lamp_index: int in range(_work_lamps.size()):
				_set_lamp(lamp_index, 0.0)
			if audio != null and audio.has_method("start_loop"):
				audio.call("start_loop", "cart_roll", 0.46)
				_cart_roll_started = true
		2:
			_alarm_started = true
			if audio != null and audio.has_method("start_loop"):
				audio.call("start_loop", "alarm_loop", 0.34)
			for steam: CPUParticles3D in _steam:
				steam.emitting = true
			for worker: Node3D in _workers:
				worker.visible = true
			camera_shake.emit(0.22, 0.8)
		3:
			_miner.visible = true
			_miner_material.set_shader_parameter("strength", 0.0)
			_loose_rail.visible = true
			_cut_glow_material.emission_energy_multiplier = 0.0
			_gate_opened_in_memory = false


func _update_visuals(index: int, elapsed: float, duration: float) -> void:
	match index:
		1:
			var t: float = clampf(elapsed / 12.5, 0.0, 1.0)
			var z: float = lerpf(-16.0, -8.2, t)
			_cart.position = Vector3(TRACK_X, TRACK_Y, z)
			for wheel: Node3D in _cart_wheels:
				wheel.rotation.x += 0.16
			var strength: float = clampf(elapsed / 1.2, 0.0, 0.8) * clampf((duration - elapsed) / 1.4, 0.0, 1.0)
			_cart_material.set_shader_parameter("strength", strength)
			var driver: GhostMiner = _cart.get_node_or_null("GhostDriver") as GhostMiner
			if driver != null:
				driver.update_anim(get_process_delta_time(), "ride")
			for lamp_index: int in range(_work_lamps.size()):
				var threshold: float = 1.4 + float(lamp_index) * 2.6
				if elapsed >= threshold:
					_set_lamp(lamp_index, 1.15)
		2:
			var pulse: float = 0.55 + 0.45 * sin(elapsed * 8.5)
			for lamp_index: int in range(_alarm_lamps.size()):
				_set_alarm(lamp_index, pulse * 1.5)
			for worker_index: int in range(_workers.size()):
				var worker: Node3D = _workers[worker_index]
				var run_t: float = clampf((elapsed - 1.6 - float(worker_index) * 0.35) / 4.4, 0.0, 1.0)
				var start: Vector3 = Vector3(-2.0 + float(worker_index) * 0.8, 0.05, -3.0 - float(worker_index) * 0.5)
				var finish: Vector3 = Vector3(9.5, 0.05, -5.4 + float(worker_index) * 0.4)
				worker.position = start.lerp(finish, run_t)
				worker.position.y = 0.05 + absf(sin(run_t * PI * 7.0)) * 0.10
				worker.rotation.y = deg_to_rad(-90.0)
				_worker_materials[worker_index].set_shader_parameter("strength", clampf((duration - elapsed) / 2.0, 0.0, 0.55))
				var actor: GhostMiner = worker as GhostMiner
				if actor != null:
					actor.update_anim(get_process_delta_time(), "run")
			var crystal_names: Array[String] = ["m1", "m2", "w3"]
			for crystal_name: String in crystal_names:
				var crystal: EchoCrystal = crystals.get(crystal_name) as EchoCrystal
				if crystal != null:
					crystal.set_alarm(pulse * 0.8)
			if elapsed > 0.05 and elapsed < 0.2:
				camera_shake.emit(0.20, 0.5)
			if elapsed > 6.7 and elapsed < 6.9:
				camera_shake.emit(0.16, 0.4)
		3:
			_miner_material.set_shader_parameter("strength", clampf(elapsed / 1.2, 0.0, 0.8) * clampf((duration - elapsed) / 1.5, 0.0, 1.0))
			var miner_actor: GhostMiner = _miner as GhostMiner
			if miner_actor != null:
				miner_actor.update_anim(get_process_delta_time(), "cut")
			if elapsed > 6.4 and not _sparks.emitting:
				_sparks.emitting = true
				_cut_glow_material.emission_energy_multiplier = 2.4
				if audio != null and audio.has_method("play_at"):
					audio.call("play_at", "rail_cut", _sparks.position, 0.9)
				camera_shake.emit(0.18, 0.5)
			if elapsed > 6.4:
				_cut_glow_material.emission_energy_multiplier = 1.4 + 0.8 * sin(elapsed * 17.0)
				_loose_rail.rotation.z = 18.0 + clampf((elapsed - 6.4) * 18.0, 0.0, 42.0)
				if _cut_light != null:
					_cut_light.light_energy = 2.4 + sin(elapsed * 21.0) * 0.8
			if elapsed > 13.2 and not _gate_opened_in_memory:
				_gate_opened_in_memory = true
				if gate != null:
					# MECHANICS-004C：第三段记忆是「出口解锁」的剧情条件本身。
					# 这里只授予驱动许可，门是否真的升起由门体物理决定。
					gate.unlock("memory_3_setpiece")
					gate.open()
				exit_opened.emit()


func _finish_visuals(index: int) -> void:
	match index:
		1:
			_cart.visible = false
			if _cart_roll_started and audio != null and audio.has_method("stop_loop"):
				audio.call("stop_loop", "cart_roll")
				_cart_roll_started = false
			# The old work lamps stay on as a permanent environmental change.
			for lamp_index: int in range(_work_lamps.size()):
				_set_lamp(lamp_index, 0.55)
		2:
			if _alarm_started and audio != null and audio.has_method("stop_loop"):
				audio.call("stop_loop", "alarm_loop")
				_alarm_started = false
			for lamp_index: int in range(_alarm_lamps.size()):
				_set_alarm(lamp_index, 0.0)
			for steam: CPUParticles3D in _steam:
				steam.emitting = false
			for worker: Node3D in _workers:
				worker.visible = false
			for crystal_name: String in ["m1", "m2", "w3"]:
				var crystal: EchoCrystal = crystals.get(crystal_name) as EchoCrystal
				if crystal != null:
					crystal.set_alarm(0.0)
		3:
			_sparks.emitting = false
			_miner.visible = false
			_loose_rail.visible = false
			if _cut_light != null:
				_cut_light.light_energy = 0.7


func reset_all() -> void:
	_token += 1
	playing = false
	if audio != null and audio.has_method("stop_loop"):
		audio.call("stop_loop", "cart_roll")
		audio.call("stop_loop", "alarm_loop")
	_cart_roll_started = false
	_alarm_started = false
	if _cart != null:
		_cart.visible = false
		_cart.position = Vector3(TRACK_X, TRACK_Y, -16.0)
	if _cart_material != null:
		_cart_material.set_shader_parameter("strength", 0.0)
	for lamp_index: int in range(_work_lamps.size()):
		_set_lamp(lamp_index, 0.0)
	for lamp_index: int in range(_alarm_lamps.size()):
		_set_alarm(lamp_index, 0.0)
	for steam: CPUParticles3D in _steam:
		steam.emitting = false
	for worker: Node3D in _workers:
		worker.visible = false
	for material: ShaderMaterial in _worker_materials:
		material.set_shader_parameter("strength", 0.5)
	if _miner != null:
		_miner.visible = false
	if _miner_material != null:
		_miner_material.set_shader_parameter("strength", 0.75)
	if _sparks != null:
		_sparks.emitting = false
	if _cut_light != null:
		_cut_light.light_energy = 0.0
	if _loose_rail != null:
		_loose_rail.visible = false
		_loose_rail.rotation.z = 18.0
	if _cut_glow_material != null:
		_cut_glow_material.emission_energy_multiplier = 0.0
	for crystal_name: String in ["m1", "m2", "w3"]:
		var crystal: EchoCrystal = crystals.get(crystal_name) as EchoCrystal
		if crystal != null:
			crystal.set_alarm(0.0)
	if gate != null:
		gate.close_gate()
	_gate_opened_in_memory = false


func get_memory_title(index: int) -> String:
	var data: Dictionary = memories.get(index, {}) as Dictionary
	return str(data.get("title", "记忆"))
