class_name LevelBuilder
extends Node3D

## Builds the whole Resonance 05 level from code: entrance tunnel, observation
## balcony, core hall, counterweight stations, capture rig, isolation bay and
## evacuation corridor. Every visible surface has explicit collision.

signal hall_entered()
signal exit_reached()
signal core_lock_event()
signal isolation_event()
signal data_event()
signal door_event()

const HALL_CENTER := Vector3(0, 0, -2)
const HALL_RADIUS := 16.2
const TUNNEL_FLOOR_Y := 4.0
const BALCONY_Y := 4.0
const SPAWN_POSITION := Vector3(0, 4.06, 38.0)

var kit: WorldKit
var core: CoreRig
var lock_rig: LockRig
var left_cart: WeightCart
var right_cart: WeightCart
var left_station: LeverStation
var right_station: LeverStation
var push_door: PushDoor
var exit_door: ExitDoor
var isolation: IsolationRig
var memory: MemoryShard
var data_plinth: DataPlinth
var terminals: Array[StoryTerminal] = []
var lamps: Array[SwingLamp] = []
var beacons: Array[MeshInstance3D] = []
var conduit_material: ShaderMaterial
var conduit_off: ShaderMaterial
var hall_trigger: Area3D
var exit_trigger: Area3D
var spawn_marker: Node3D
var core_instability: float = 0.0
var time: float = 0.0
var built: bool = false
var audio: AudioDirector
# --- V2 co-op machinery ---------------------------------------------------
var session: CoopSession
var story: StoryDirector
var catwalk: CatwalkRig
var stabilizers: Array[StabilizerRig] = []
var brake: BrakeRig
var damper: DamperRig
var duty_board: DutyBoard
const Act5PhysicalLinks := preload("res://scripts/world/act5_physical_links.gd")
var physical_links: Act5PhysicalLinks
var alarm_on: bool = false
var warning_intensity: float = 0.0


func build(p_audio: AudioDirector, p_session: CoopSession = null) -> void:
	if built:
		return
	built = true
	audio = p_audio
	session = p_session
	kit = WorldKit.new(self)
	_build_environment()
	_build_hall_shell()
	_decorate_cave_walls()
	_build_floors()
	_build_entrance()
	_build_balcony()
	_build_core()
	_build_weight_system()
	_build_isolation()
	_build_coop_machines()
	_build_memory()
	_build_data_plinth()
	_build_exit()
	_build_props()
	_build_lights()
	_build_triggers()
	connect_core_signals()
	_apply_initial_state()


func bind_player(player: PlayerController) -> void:
	push_door.setup(player, audio)
	left_station.bind_player(player)
	right_station.bind_player(player)
	isolation.bind_player(player)
	memory.setup(player, audio)
	for terminal in terminals:
		terminal.bind_player(player)
	if catwalk != null:
		catwalk.bind_player(player)
	for stab in stabilizers:
		stab.bind_player(player)
	if brake != null:
		brake.bind_player(player)
	if damper != null:
		damper.bind_player(player)


func connect_core_signals() -> void:
	if core == null:
		return
	core.telemetry.connect(_on_core_telemetry)
	core.surge_shock.connect(_on_surge)
	core.locked_done.connect(_on_core_locked)
	lock_rig.lock_succeeded.connect(_on_lock_success)
	lock_rig.lock_attempt_failed.connect(_on_lock_fail)
	isolation.separated.connect(_on_isolation_separated)
	isolation.pin_pulled.connect(_on_pin_pulled)
	isolation.message.connect(_on_isolation_message)
	data_plinth.data_taken.connect(_on_data_taken)


func _apply_initial_state() -> void:
	core.set_weights(left_cart.get_p(), right_cart.get_p())
	core.reset_state()
	set_conduit_powered(false)
	if physical_links != null:
		physical_links.refresh(false, false)


func _on_core_telemetry(net: float, _angle: float, _omega: float, capturable: bool, locked: bool) -> void:
	core_instability = clampf(absf(net) / 0.6, 0.0, 1.0)
	for lamp in lamps:
		lamp.set_tension(core_instability)
	_pulse_beacons(capturable, locked)
	if physical_links != null:
		physical_links.refresh(capturable, locked)


func _on_surge(_strength: float) -> void:
	for lamp in lamps:
		lamp.set_tension(1.0)
	if audio != null:
		audio.play_sfx("surge", HALL_CENTER + Vector3(0, 2, 0), -2.0)
		audio.surge_pulse()
	for i in range(3):
		var p: CPUParticles3D = kit.spark_burst("SurgeSparks_%d" % i, HALL_CENTER + Vector3(randf_range(-5, 5), 1.2, randf_range(-4, 4)), 18, Color(0.6, 0.9, 1.0))
		p.emitting = true


func _on_core_locked() -> void:
	if audio != null:
		audio.play_sfx("lock_success", HALL_CENTER, 0.0)
	core_lock_event.emit()
	set_conduit_powered(true)
	lock_rig.target_extension = 1.0
	lock_rig.locked_latch = true


func _on_lock_success() -> void:
	pass


func _on_lock_fail(reason: String) -> void:
	if audio != null:
		audio.play_sfx("lock_fail", HALL_CENTER + Vector3(0, 1, 7), -2.0)
	if core != null:
		core.play_surge(0.25)


func _on_pin_pulled() -> void:
	if audio != null:
		audio.play_sfx("pin_pull", isolation.global_position, -1.0)


func _on_isolation_message(text: String) -> void:
	pass


func _on_isolation_separated() -> void:
	set_conduit_powered(false)
	isolation_event.emit()
	if audio != null:
		audio.play_sfx("separation", isolation.global_position, 0.0)
	core.play_surge(0.4)


func _on_data_taken() -> void:
	data_event.emit()
	exit_door.open_door()
	door_event.emit()


func set_conduit_powered(powered: bool) -> void:
	if conduit_material == null:
		return
	conduit_material.set_shader_parameter("energy", 2.2 if powered else 0.25)
	conduit_material.set_shader_parameter("speed", 2.4 if powered else 0.15)


func _pulse_beacons(capturable: bool, locked: bool) -> void:
	var col: Color = Color(0.95, 0.18, 0.08)
	if locked:
		col = Color(0.15, 0.9, 0.5)
	elif capturable:
		col = Color(0.35, 0.9, 0.7)
	for beacon in beacons:
		if beacon != null:
			beacon.material_override = MatLib.emissive(col, 1.2 + sin(time * 4.0) * 0.3)


func _process(delta: float) -> void:
	time += delta


# ---------------------------------------------------------------------------
# Environment and shell
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.028, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.50, 0.58)
	env.ambient_light_energy = 2.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.22
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Color(0.075, 0.13, 0.16)
	env.fog_light_energy = 0.65
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.fog_height = -4.0
	env.fog_height_density = 0.015
	world_env.environment = env
	add_child(world_env)


func _build_hall_shell() -> void:
	CaveShell.hall(kit, HALL_CENTER, HALL_RADIUS + 0.35, 12.5, 8.5, PI * 0.5, 0.205, 2.6, 9.7, PI, 0.145, 4.3)
	# Large outcrops embedded in the wall ring: their centres sit outside the
	# nominal wall radius so only the inward face protrudes into the hall.
	var outcrops: Array = [
		{"file": "rock_outcrop_b.glb", "pos": Vector3(-16.4, 0.0, -9.5), "rot": 30.0, "scale": 1.45},
		{"file": "rock_outcrop_a.glb", "pos": Vector3(16.6, 0.0, -12.4), "rot": -55.0, "scale": 1.35},
		{"file": "rock_column_a.glb", "pos": Vector3(-17.0, 0.0, 4.2), "rot": 12.0, "scale": 1.05},
		{"file": "rock_column_b.glb", "pos": Vector3(17.0, 0.0, -1.0), "rot": -100.0, "scale": 1.0},
		{"file": "rock_rubble_b.glb", "pos": Vector3(-15.4, 0.0, -14.2), "rot": 60.0, "scale": 1.05},
		{"file": "rock_rubble_c.glb", "pos": Vector3(15.6, 0.0, -5.5), "rot": -20.0, "scale": 0.95},
	]
	for o in outcrops:
		var info: Dictionary = o as Dictionary
		kit.rock("HallOutcrop", "res://assets/rocks/" + str(info["file"]), info["pos"] as Vector3, float(info["rot"]), float(info["scale"]), MatLib.rock(Color(0.36, 0.335, 0.34), Color(0.10, 0.42, 0.5), 0.28), true)


func _decorate_cave_walls() -> void:
	# Detailed rock kit panels overlap in front of the procedural shell. The
	# shell stays as a continuous dark backing / collision guarantee, while every
	# reachable wall now has real, project-approved rock geometry.
	var wall_mat: ShaderMaterial = MatLib.rock(Color(0.37, 0.345, 0.34), Color(0.10, 0.46, 0.54), 0.27)
	var wall_files: Array[String] = ["rock_wall_a", "rock_wall_b", "rock_wall_c", "rock_wall_d"]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261022
	# lower ring
	for i in range(12):
		if i == 3 or i == 6:
			continue
		var a: float = TAU * float(i) / 12.0 + 0.035
		var p: Vector3 = Vector3(cos(a) * 18.1, -0.05, sin(a) * 18.1 - 2.0)
		var yaw: float = 90.0 - rad_to_deg(a) + rng.randf_range(-5.0, 5.0)
		var path: String = "res://assets/rocks/%s.glb" % wall_files[i % wall_files.size()]
		kit.rock("HallWall_%d" % i, path, p, yaw, 1.04, wall_mat, true, rng.randf_range(-2.0, 2.0), rng.randf_range(-4.0, 4.0))
		rng.randf()
	# upper ring, tilted inward to form the lower dome shoulder
	for i in range(12):
		if i == 3:
			continue
		var a2: float = TAU * float(i) / 12.0 + 0.09
		var p2: Vector3 = Vector3(cos(a2) * 17.8, 6.9, sin(a2) * 17.8 - 2.0)
		var yaw2: float = 90.0 - rad_to_deg(a2) + rng.randf_range(-6.0, 6.0)
		var path2: String = "res://assets/rocks/%s.glb" % wall_files[(i + 2) % wall_files.size()]
		kit.rock("HallWallUpper_%d" % i, path2, p2, yaw2, 0.92, wall_mat, false, rng.randf_range(-6.0, 6.0), rng.randf_range(-7.0, 7.0))
	# The tunnel shell is the visible tunnel surface. Rock panels centred 1.9 m
	# outside it were invisible, and the ceiling "shoulder" slabs poked through
	# the tunnel roof as floating planks, so both were removed.
	# a few low rubble pieces half-buried at the wall foot
	for k in range(4):
		var a4: float = TAU * float(k) / 4.0 + 0.55
		var p4: Vector3 = Vector3(cos(a4) * 15.9, -0.08, sin(a4) * 15.9 - 2.0)
		kit.rock("WallRubble_%d" % k, "res://assets/rocks/rock_rubble_%s.glb" % ["a", "b", "c"][k % 3], p4, rad_to_deg(a4) + 30.0, 0.62, MatLib.debris_rock(), true)


func _build_floors() -> void:
	var floor_mat: Material = MatLib.rock(Color(0.27, 0.265, 0.275), Color(0.08, 0.30, 0.36), 0.18)
	var floor_mesh: CylinderMesh = CylinderMesh.new()
	floor_mesh.top_radius = 16.6
	floor_mesh.bottom_radius = 16.6
	floor_mesh.height = 0.6
	floor_mesh.radial_segments = 72
	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.name = "HallFloor"
	floor_instance.mesh = floor_mesh
	floor_instance.material_override = floor_mat
	floor_instance.position = HALL_CENTER + Vector3(0, -0.3, 0)
	floor_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(floor_instance)
	kit.add_cylinder_shape(HALL_CENTER + Vector3(0, -0.3, 0), 16.6, 0.6)
	# industrial apron around the core
	kit.ring_box("CoreApron", 8.8, 4.6, 0.10, HALL_CENTER + Vector3(0, 0.05, 0), MatLib.metal(Color(0.23, 0.25, 0.26), 0.48, 0.6, 0.65), Basis(), 64, false)
	kit.ring_box("ApronHazard", 6.5, 0.34, 0.04, HALL_CENTER + Vector3(0, 0.11, 0), MatLib.hazard_material(), Basis(), 64, false)
	kit.ring_box("ApronTrim", 11.0, 0.18, 0.04, HALL_CENTER + Vector3(0, 0.11, 0), MatLib.bronze(), Basis(), 64, false)
	kit.rivet_ring(HALL_CENTER + Vector3(0, 0.12, 0), 10.9, 48, Vector3.UP, MatLib.steel())
	# floor plates / service hatches
	for i in range(8):
		var a: float = TAU * float(i) / 8.0 + 0.2
		var p: Vector3 = HALL_CENTER + Vector3(cos(a) * 12.4, 0.02, sin(a) * 12.4)
		kit.box("FloorPlate", Vector3(2.4, 0.05, 1.8), p, MatLib.metal(Color(0.18, 0.20, 0.21), 0.5, 0.55, 0.7), Vector3(0, -a, 0), false)
	# guide strips from both ramps toward the core and the console
	for sx in [-1.0, 1.0]:
		_floor_strip(Vector3(sx * 5.2, 0.02, 1.0), Vector3(sx * 1.6, 0.02, 5.4), Color(0.22, 0.7, 0.8))
		_floor_strip(Vector3(sx * 5.0, 0.02, 1.2), Vector3(sx * 10.2, 0.02, 0.0), Color(0.22, 0.7, 0.8))
	_floor_strip(Vector3(-10.8, 0.02, 1.0), Vector3(-13.8, 0.02, -1.6), Color(0.75, 0.45, 0.2))


func _floor_strip(a: Vector3, b: Vector3, color: Color) -> void:
	var length: float = Vector2(b.x - a.x, b.z - a.z).length()
	if length < 0.1:
		return
	var mid: Vector3 = (a + b) * 0.5
	var angle: float = atan2(b.x - a.x, b.z - a.z)
	kit.box("GuideStrip", Vector3(0.08, 0.012, length), mid + Vector3(0, 0.01, 0), MatLib.emissive(color, 0.55), Vector3(0, angle, 0), false)


func _build_entrance() -> void:
	CaveShell.tunnel(kit, 41.5, 13.8, 3.7, TUNNEL_FLOOR_Y, 4.5)
	kit.box("TunnelDeck", Vector3(7.4, 0.3, 27.9), Vector3(0, TUNNEL_FLOOR_Y - 0.15, 27.65), MatLib.metal(Color(0.19, 0.22, 0.22), 0.55, 0.5, 0.7), Vector3.ZERO, true)
	for z in [16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0]:
		kit.box("DeckSeam", Vector3(7.2, 0.015, 0.06), Vector3(0, TUNNEL_FLOOR_Y + 0.01, z), MatLib.dark_steel(), Vector3.ZERO, false)
	for sx in [-3.28, 3.28]:
		kit.pipe("TunnelPipe", [Vector3(sx * 0.96, TUNNEL_FLOOR_Y + 0.55, 40.5), Vector3(sx * 0.96, TUNNEL_FLOOR_Y + 0.55, 15.0)], 0.11, MatLib.copper(), false)
		kit.pipe("TunnelConduit", [Vector3(sx * 0.90, TUNNEL_FLOOR_Y + 3.3, 40.5), Vector3(sx * 0.90, TUNNEL_FLOOR_Y + 3.3, 15.0)], 0.055, MatLib.dark_steel(), false)
		# the overhead conduit is a supported line now: hangers and clamps at
		# every rib stop it reading as a stray diagonal beam.
		for z in [15.0, 18.0, 21.5, 27.0, 30.5, 34.0, 37.5, 40.5]:
			kit.box("ConduitStrap", Vector3(0.045, 0.82, 0.045), Vector3(sx * 0.90, TUNNEL_FLOOR_Y + 3.72, z), MatLib.dark_steel(), Vector3.ZERO, false)
			kit.cylinder("ConduitClamp", 0.085, 0.06, Vector3(sx * 0.90, TUNNEL_FLOOR_Y + 3.30, z), MatLib.bronze(), Vector3(PI * 0.5, 0, 0), false, 8)
		kit.box("DeckGuide", Vector3(0.05, 0.012, 25.0), Vector3(sx * 0.86, TUNNEL_FLOOR_Y + 0.012, 27.5), MatLib.emissive(Color(0.32, 0.8, 0.9), 0.7), Vector3.ZERO, false)
	# structural ribs
	for z in [18.0, 21.5, 27.0, 30.5, 34.0, 37.5]:
		_entrance_rib(z)
	# crates and industrial clutter
	kit.crate("CrateA", Vector3(-2.55, TUNNEL_FLOOR_Y + 0.55, 35.2), Vector3(1.1, 1.1, 1.1), Vector3(0, 0.25, 0))
	kit.crate("CrateB", Vector3(2.62, TUNNEL_FLOOR_Y + 0.45, 22.8), Vector3(0.9, 0.9, 0.9), Vector3(0, -0.15, 0))
	kit.crate("CrateC", Vector3(2.55, TUNNEL_FLOOR_Y + 0.4, 21.9), Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0))
	kit.cylinder("Barrel", 0.36, 0.9, Vector3(-2.7, TUNNEL_FLOOR_Y + 0.45, 23.4), MatLib.painted_steel(Color(0.42, 0.26, 0.12)), Vector3.ZERO, true, 14)
	kit.warning_sign("深层设施 · 未经许可禁止入内", Vector3(-3.05, TUNNEL_FLOOR_Y + 2.0, 26.2), PI * 0.5, 1.8, 0.5)
	kit.warning_sign("共振监测 07 · 危险", Vector3(3.05, TUNNEL_FLOOR_Y + 2.1, 29.8), -PI * 0.5, 1.8, 0.5)
	kit.label3d("R-05  ·  DEEP CORE ACCESS", Vector3(0, TUNNEL_FLOOR_Y + 3.6, 35.8), 0.004, Color(0.5, 0.82, 0.88), 42, Basis(Vector3.UP, PI))
	# maintenance terminal
	var terminal: StoryTerminal = StoryTerminal.new()
	terminal.name = "MaintenanceTerminal"
	terminal.position = Vector3(-2.75, TUNNEL_FLOOR_Y, 31.0)
	terminal.rotation.y = PI * 0.5
	add_child(terminal)
	terminal.build()
	terminal.setup(null, "维护日志 · 老宋", [
		"第 41 天：三号采掘机一开机，深处的振动就顺着轨道返上来。仪表读数比昨天高了两倍。",
		"第 44 天：不是矿石的问题。核心在把振动聚起来，又在放大。我们像在敲一口越来越薄的钟。",
		"第 46 天：老宋说，别让车下去。晶体在记账。",
	])
	terminals.append(terminal)
	# jammed shutter
	push_door = PushDoor.new()
	push_door.name = "EntranceShutter"
	push_door.position = Vector3(0, TUNNEL_FLOOR_Y, 24.0)
	add_child(push_door)
	push_door.build()
	# spawn / end cap
	CaveShell.end_cap(kit, 41.6, 3.7, TUNNEL_FLOOR_Y, 4.5)
	spawn_marker = Node3D.new()
	spawn_marker.name = "SpawnMarker"
	spawn_marker.position = SPAWN_POSITION
	add_child(spawn_marker)


func _entrance_rib(z: float) -> void:
	var steel: Material = MatLib.painted_steel(Color(0.23, 0.27, 0.26))
	for sx in [-3.28, 3.28]:
		kit.box("RibPost", Vector3(0.22, 4.2, 0.28), Vector3(sx * 0.95, TUNNEL_FLOOR_Y + 2.1, z), steel, Vector3.ZERO, true)
		kit.box("RibFoot", Vector3(0.5, 0.16, 0.5), Vector3(sx, TUNNEL_FLOOR_Y + 0.08, z), MatLib.bronze(), Vector3.ZERO, false)
	kit.box("RibBeamTop", Vector3(6.9, 0.09, 0.34), Vector3(0, TUNNEL_FLOOR_Y + 4.23, z), steel, Vector3.ZERO, false)
	kit.box("RibBeamWeb", Vector3(6.9, 0.22, 0.12), Vector3(0, TUNNEL_FLOOR_Y + 4.10, z), MatLib.dark_steel(), Vector3.ZERO, false)
	kit.box("RibBeamBottom", Vector3(6.9, 0.09, 0.34), Vector3(0, TUNNEL_FLOOR_Y + 3.97, z), steel, Vector3.ZERO, false)
	for gx in [-3.0, 3.0]:
		kit.box("RibGusset", Vector3(0.48, 0.48, 0.44), Vector3(gx, TUNNEL_FLOOR_Y + 4.12, z), MatLib.bronze(), Vector3.ZERO, false)
	for i in range(9):
		kit.cylinder("RibBolt", 0.035, 0.05, Vector3(-3.0 + float(i) * 0.75, TUNNEL_FLOOR_Y + 3.92, z + 0.16), MatLib.steel(), Vector3(PI * 0.5, 0, 0), false, 6)
	kit.omni(Vector3(0, TUNNEL_FLOOR_Y + 3.7, z), Color(1.0, 0.68, 0.40), 2.0, 6.5, false, "TunnelLight")
	# low warm strip on the rib posts, so the tunnel has a readable rhythm
	for sx in [-3.05, 3.05]:
		kit.box("RibLampStrip", Vector3(0.035, 0.55, 0.05), Vector3(sx, TUNNEL_FLOOR_Y + 2.6, z + 0.16), MatLib.emissive(Color(1.0, 0.66, 0.34), 1.5), Vector3.ZERO, false)


func _build_balcony() -> void:
	kit.box("BalconyDeck", Vector3(12.0, 0.45, 8.0), Vector3(0, BALCONY_Y - 0.225, 14.0), MatLib.metal(Color(0.20, 0.23, 0.23), 0.52, 0.55, 0.65), Vector3.ZERO, true)
	for i in range(12):
		var x: float = -5.4 + float(i) * 0.98
		kit.box("BalconyTread", Vector3(0.07, 0.02, 8.1), Vector3(x, BALCONY_Y + 0.012, 14.0), MatLib.dark_steel(), Vector3.ZERO, false)
	# portal frame
	var steel: Material = MatLib.painted_steel(Color(0.24, 0.30, 0.31))
	for sx in [-3.75, 3.75]:
		kit.box("PortalColumn", Vector3(0.55, 5.9, 0.75), Vector3(sx, BALCONY_Y + 2.95, 14.05), steel, Vector3.ZERO, true)
		for i in range(6):
			kit.box("PortalRib", Vector3(0.62, 0.12, 0.8), Vector3(sx, BALCONY_Y + 0.5 + float(i) * 0.95, 14.05), MatLib.bronze(), Vector3.ZERO, false)
	kit.box("PortalLintel", Vector3(8.6, 0.7, 0.9), Vector3(0, BALCONY_Y + 5.55, 14.05), steel, Vector3.ZERO, true)
	kit.box("PortalHeader", Vector3(8.2, 0.28, 0.5), Vector3(0, BALCONY_Y + 5.1, 13.98), MatLib.hazard_material(), Vector3.ZERO, false)
	kit.label3d("地心共振设施 · 第五隔离层", Vector3(0, BALCONY_Y + 4.55, 13.55), 0.0042, Color(0.78, 0.95, 1.0), 52, Basis(Vector3.UP, PI))
	# underside bulkhead (seals the rock portal below the balcony)
	kit.box("Bulkhead", Vector3(13.2, 3.9, 0.5), Vector3(0, 1.95, 14.35), MatLib.metal(Color(0.17, 0.20, 0.21), 0.55, 0.55, 0.7), Vector3.ZERO, true)
	for i in range(6):
		kit.box("BulkheadRib", Vector3(0.16, 3.8, 0.12), Vector3(-5.6 + float(i) * 2.24, 1.95, 14.62), MatLib.dark_steel(), Vector3.ZERO, false)
	kit.warning_sign("核心区域 · 禁止停留", Vector3(0, 2.5, 14.64), 0.0, 2.0, 0.55)
	# supports
	for sx in [-5.6, 5.6]:
		for z in [15.8, 17.2]:
			kit.box("BalconyColumn", Vector3(0.42, 3.8, 0.42), Vector3(sx, 1.9, z), MatLib.dark_steel(), Vector3.ZERO, true)
	# railings
	kit.railing(self, Vector3(-3.7, BALCONY_Y, 10.05), Vector3(3.7, BALCONY_Y, 10.05), 1.08)
	kit.railing(self, Vector3(-6.0, BALCONY_Y, 10.05), Vector3(-6.0, BALCONY_Y, 17.7), 1.08)
	kit.railing(self, Vector3(6.0, BALCONY_Y, 10.05), Vector3(6.0, BALCONY_Y, 17.7), 1.08)
	# ramps to the hall floor. Kept inboard of the counterweight decks so the
	# ramp railings never cut across the operator's view of the track.
	for sx in [-4.2, 4.2]:
		_build_ramp(sx, 10.0, 2.0, 4.0, 0.0)
	# balcony lamps
	for sx in [-4.2, 4.2]:
		var lamp: SwingLamp = SwingLamp.new()
		lamp.name = "BalconyLamp"
		lamp.position = Vector3(sx, BALCONY_Y + 5.3, 16.4)
		add_child(lamp)
		lamp.build(3.0, Color(1.0, 0.72, 0.45))
		lamp.set_tension(0.05)
		lamps.append(lamp)


func _build_ramp(sx: float, z_top: float, z_bottom: float, y_top: float, y_bottom: float) -> void:
	var dz: float = absf(z_top - z_bottom)
	var dy: float = absf(y_top - y_bottom)
	var length: float = sqrt(dz * dz + dy * dy)
	var angle: float = atan2(dy, dz)
	kit.wedge_ramp("RampDeck", sx, 2.4, z_top, y_top, z_bottom, y_bottom, 0.32, MatLib.metal(Color(0.21, 0.24, 0.24), 0.5, 0.55, 0.65), true)
	# treads and edge lighting
	var steps: int = 14
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var p: Vector3 = Vector3(sx, lerpf(y_top, y_bottom, t) + 0.02, lerpf(z_top, z_bottom, t))
		kit.box("RampTread", Vector3(2.25, 0.02, 0.06), p, MatLib.dark_steel(), Vector3.ZERO, false)
		if i % 4 == 0:
			kit.box("RampEdge", Vector3(0.05, 0.012, 0.62), p + Vector3(1.13, 0, 0), MatLib.emissive(Color(0.9, 0.6, 0.2), 0.7), Vector3(-angle, 0, 0), false)
	# Railings along both sides. The railing stops roughly 1 m above the ramp
	# foot (z_bottom) so the bottom of the ramp stays an open step-off onto the
	# hall floor. The previous railing ran all the way into the floor at
	# z_bottom and, together with the innermost west-rail A-frame trestle (V2
	# mirror), sealed the walk into the left counterweight station
	# (P0 路线问题: 坡道护栏 + 西轨支架夹缝).
	var rail_bottom_t: float = clampf((z_top - (z_bottom + 1.0)) / maxf(0.001, z_top - z_bottom), 0.0, 1.0)
	for side in [-1.0, 1.0]:
		var offsets: Array = []
		for i in range(4):
			var t2: float = float(i) / 3.0
			t2 = minf(t2, rail_bottom_t)
			var p2: Vector3 = Vector3(sx + side * 1.15, lerpf(y_top, y_bottom, t2), lerpf(z_top, z_bottom, t2))
			offsets.append(p2)
		for i in range(offsets.size() - 1):
			var a: Vector3 = offsets[i] as Vector3
			var b: Vector3 = offsets[i + 1] as Vector3
			kit.beam("RampRail", a + Vector3(0, 1.05, 0), b + Vector3(0, 1.05, 0), 0.045, MatLib.steel(), true, 6)
			kit.beam("RampRailLow", a + Vector3(0, 0.55, 0), b + Vector3(0, 0.55, 0), 0.032, MatLib.steel(), false, 6)
		for p3 in offsets:
			var post: Vector3 = p3 as Vector3
			kit.box("RampPost", Vector3(0.07, 1.1, 0.07), post + Vector3(0, 0.55, 0), MatLib.steel(), Vector3.ZERO, false)
	# no landing pad: the wedge meets the hall floor directly


# ---------------------------------------------------------------------------
# Core and machinery
# ---------------------------------------------------------------------------

func _build_core() -> void:
	# ceiling anchor gantry
	var dark: Material = MatLib.dark_steel()
	kit.cylinder("AnchorPlate", 3.4, 0.6, Vector3(0, 20.1, -2), dark, Vector3.ZERO, false, 32)
	kit.cylinder("AnchorHub", 1.5, 1.4, Vector3(0, 19.2, -2), MatLib.painted_steel(Color(0.25, 0.28, 0.28)), Vector3.ZERO, false, 24)
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		var p1: Vector3 = Vector3(cos(a) * 1.4, 19.6, -2 + sin(a) * 1.4)
		var p2: Vector3 = Vector3(cos(a) * 3.6, 20.0, -2 + sin(a) * 3.6)
		kit.beam("AnchorBeam", p1, p2, 0.18, dark, false, 8)
	kit.cylinder("AnchorShaft", 0.7, 1.8, Vector3(0, 18.6, -2), MatLib.metal(Color(0.32, 0.34, 0.35), 0.35, 0.8, 0.5), Vector3.ZERO, false, 18)
	kit.ring_box("AnchorCollar", 1.4, 0.28, 0.3, Vector3(0, 18.15, -2), MatLib.bronze(), Basis(), 32, false)
	core = CoreRig.new()
	core.name = "ResonanceCore"
	core.position = Vector3(0, 18.2, -2)
	add_child(core)
	core.build()
	lock_rig = LockRig.new()
	lock_rig.name = "CaptureRig"
	lock_rig.position = HALL_CENTER
	add_child(lock_rig)
	lock_rig.build()
	lock_rig.setup(core)


func _build_weight_system() -> void:
	# rails and supports
	for sign_value in [-1.0, 1.0]:
		_build_weight_rail(sign_value)
	left_cart = WeightCart.new()
	left_cart.name = "LeftCounterweight"
	left_cart.position = Vector3(0, WeightCart.RAIL_TOP_Y, 1.2)
	add_child(left_cart)
	left_cart.setup(-1.0, 0.12)
	right_cart = WeightCart.new()
	right_cart.name = "RightCounterweight"
	right_cart.position = Vector3(0, WeightCart.RAIL_TOP_Y, 1.2)
	add_child(right_cart)
	right_cart.setup(1.0, 0.88)
	# stations
	_build_station_platform(-1.0)
	_build_station_platform(1.0)
	left_station = LeverStation.new()
	left_station.name = "LeftCounterweightStation"
	left_station.position = Vector3(-8.0, 1.6, 6.6)
	add_child(left_station)
	left_station.build()
	left_station.setup(core, left_cart, null, -1.0, -PI / 6.0)
	left_station.setup_coop(session, "cart_left")
	right_station = LeverStation.new()
	right_station.name = "RightCounterweightStation"
	right_station.position = Vector3(8.0, 1.6, 6.6)
	add_child(right_station)
	right_station.build()
	right_station.setup(core, right_cart, null, 1.0, PI / 6.0)
	right_station.setup_coop(session, "cart_right")
	left_station.cart.endstop_hit.connect(_on_cart_endstop)
	right_station.cart.endstop_hit.connect(_on_cart_endstop)


func _build_weight_rail(sign_value: float) -> void:
	# Twin-rail track at z = 1.2, mirrored for the west side. (The previous
	# build ignored sign_value for the west call, so the left cart ran on a
	# duplicate of the east track; V2 mirrors every x coordinate.)
	var sx: float = sign_value
	var z: float = 1.2
	var z_rail: float = WeightCart.RAIL_HALF_GAUGE
	var x_inner: float = WeightCart.INNER_X - 0.9
	var x_outer: float = WeightCart.OUTER_X + 0.9
	var center_x: float = (x_inner + x_outer) * 0.5
	var length: float = x_outer - x_inner
	var rail_steel: Material = MatLib.steel()
	var dark: Material = MatLib.dark_steel()
	var bronze: Material = MatLib.bronze()
	for sz in [-z_rail, z_rail]:
		kit.box("RailTop", Vector3(length, 0.10, 0.18), Vector3(sx * center_x, 2.55, z + sz), rail_steel, Vector3.ZERO, false)
		kit.box("RailWeb", Vector3(length, 0.30, 0.08), Vector3(sx * center_x, 2.37, z + sz), dark, Vector3.ZERO, false)
		kit.box("RailFoot", Vector3(length, 0.08, 0.26), Vector3(sx * center_x, 2.18, z + sz), rail_steel, Vector3.ZERO, false)
	kit.add_box_shape(Vector3(sx * center_x, 2.55, z), Vector3(length, 0.32, 1.10))
	# sleepers / cross ties
	var ties: int = 7
	for i in range(ties):
		var tx: float = lerpf(x_inner, x_outer, float(i) / float(ties - 1))
		kit.box("RailTie", Vector3(0.16, 0.14, 1.14), Vector3(sx * tx, 2.46, z), dark, Vector3.ZERO, false)
		kit.box("TieBolt", Vector3(0.10, 0.05, 0.10), Vector3(sx * tx, 2.58, z - z_rail), bronze, Vector3.ZERO, false)
		kit.box("TieBolt", Vector3(0.10, 0.05, 0.10), Vector3(sx * tx, 2.58, z + z_rail), bronze, Vector3.ZERO, false)
	# rack teeth on the far rail for the drive pinion
	for i in range(24):
		var tx2: float = lerpf(x_inner + 0.12, x_outer - 0.12, float(i) / 23.0)
		kit.box("RackTooth", Vector3(0.11, 0.07, 0.16), Vector3(sx * tx2, 2.62, z - z_rail - 0.13), bronze, Vector3.ZERO, false)
	# track fascia: the track reads as one continuous bridge girder instead of
	# two thin lines with posts disappearing behind the cart.
	for fz in [z - 0.62, z + 0.62]:
		kit.box("TrackFascia", Vector3(length, 0.30, 0.07), Vector3(sx * center_x, 2.28, fz), dark, Vector3.ZERO, false)
		kit.box("TrackFasciaTrim", Vector3(length, 0.05, 0.09), Vector3(sx * center_x, 2.45, fz), bronze, Vector3.ZERO, false)
	for i in range(9):
		var rx: float = lerpf(x_inner + 0.2, x_outer - 0.2, float(i) / 8.0)
		for fz2 in [z - 0.62, z + 0.62]:
			kit.cylinder("FasciaRivet", 0.035, 0.03, Vector3(sx * rx, 2.28, fz2), MatLib.steel(), Vector3(PI * 0.5, 0, 0), false, 6)
	# A-frame trestles: legs splay along the track axis, so the operator deck
	# sees a triangulated support rather than a solid pillar. The innermost
	# trestle (nearest the hall) has a shorter outboard splay so its foot no
	# longer crowds the walk lane between the ramp foot and the station ramp
	# (P0 路线问题: 西轨最内侧支架脚座把通道夹窄).
	for tx3 in [x_inner + 0.35, center_x, x_outer - 0.35]:
		var splay: float = 0.45 if absf(tx3 - (x_inner + 0.35)) < 0.01 else 0.70
		for sz2 in [-z_rail, z_rail]:
			for dir in [-1.0, 1.0]:
				kit.beam("TrestleLeg", Vector3(sx * (tx3 + dir * splay), 0.10, z + sz2), Vector3(sx * tx3, 2.12, z + sz2), 0.075, dark, true, 6)
				kit.box("TrestleFoot", Vector3(0.46, 0.12, 0.46), Vector3(sx * (tx3 + dir * splay), 0.06, z + sz2), bronze, Vector3.ZERO, false)
		kit.box("TrestleBeam", Vector3(0.20, 0.16, 1.32), Vector3(sx * tx3, 2.08, z), rail_steel, Vector3.ZERO, true)
		kit.beam("TrestleTie", Vector3(sx * (tx3 - 0.52), 1.35, z - z_rail), Vector3(sx * (tx3 + 0.52), 1.35, z - z_rail), 0.045, bronze, false, 6)
		kit.beam("TrestleTie", Vector3(sx * (tx3 - 0.52), 1.35, z + z_rail), Vector3(sx * (tx3 + 0.52), 1.35, z + z_rail), 0.045, bronze, false, 6)
	# end stops with buffers
	for ex in [x_inner - 0.02, x_outer + 0.02]:
		kit.box("RailStop", Vector3(0.18, 0.42, 1.10), Vector3(sx * ex, 2.64, z), MatLib.hazard_material(), Vector3.ZERO, false)
		kit.cylinder("StopSpring", 0.13, 0.34, Vector3(sx * (ex - 0.22), 2.60, z), MatLib.steel(), Vector3(0, 0, PI * 0.5), false, 10)
	# position scale facing the operator deck (+Z side)
	for i in range(5):
		var t2: float = float(i) / 4.0
		var x2: float = lerpf(WeightCart.INNER_X, WeightCart.OUTER_X, t2)
		kit.box("RailTick", Vector3(0.04, 0.16, 0.04), Vector3(sx * x2, 2.74, z + 0.62), MatLib.emissive(Color(0.6, 0.8, 0.8), 0.5), Vector3.ZERO, false)
	# stationary hydraulic supply along the back of the track, with clamps
	kit.pipe("RailSupply", [Vector3(sx * (x_inner + 0.2), 2.02, z + 0.72), Vector3(sx * (x_outer - 0.6), 2.02, z + 0.72)], 0.045, MatLib.copper(), false)
	for i in range(4):
		var cx: float = lerpf(x_inner + 0.5, x_outer - 0.8, float(i) / 3.0)
		kit.cylinder("SupplyClamp", 0.07, 0.06, Vector3(sx * cx, 2.02, z + 0.72), dark, Vector3(PI * 0.5, 0, 0), false, 8)


func _build_station_platform(sign_value: float) -> void:
	var sx: float = sign_value * 8.0
	kit.box("StationDeck", Vector3(3.6, 0.30, 3.0), Vector3(sx, 1.45, 6.6), MatLib.metal(Color(0.19, 0.23, 0.24), 0.5, 0.55, 0.65), Vector3.ZERO, true)
	kit.box("DeckPlate", Vector3(3.64, 0.05, 3.04), Vector3(sx, 1.62, 6.6), MatLib.metal(Color(0.16, 0.185, 0.19), 0.60, 0.5, 0.5), Vector3.ZERO, false)
	for i in range(9):
		kit.box("DeckTread", Vector3(3.46, 0.014, 0.05), Vector3(sx, 1.648, 5.25 + float(i) * 0.34), MatLib.dark_steel(), Vector3.ZERO, false)
	kit.box("StationEdge", Vector3(3.66, 0.09, 0.10), Vector3(sx, 1.63, 5.12), MatLib.hazard_material(), Vector3.ZERO, false)
	kit.box("StationEdge", Vector3(0.10, 0.09, 3.06), Vector3(sx + sign_value * 1.80, 1.63, 6.6), MatLib.hazard_material(), Vector3.ZERO, false)
	for i in range(4):
		var px: float = sx + (-1.0 if i % 2 == 0 else 1.0) * 1.65
		var pz: float = 5.30 if i < 2 else 7.90
		kit.box("StationSupport", Vector3(0.22, 1.46, 0.22), Vector3(px, 0.73, pz), MatLib.dark_steel(), Vector3.ZERO, true)
		kit.box("StationFoot", Vector3(0.56, 0.10, 0.56), Vector3(px, 0.05, pz), MatLib.bronze(), Vector3.ZERO, false)
	# access ramp on the core-facing (north) edge, away from the rock wall
	var z_top: float = 4.95
	var z_bottom: float = 2.8
	var y_top: float = 1.6
	var y_bottom: float = 0.0
	kit.wedge_ramp("StationRamp", sx, 2.2, z_bottom, y_bottom, z_top, y_top, 0.26, MatLib.metal(Color(0.20, 0.23, 0.23), 0.52, 0.55, 0.65), true)
	for side in [-1.0, 1.0]:
		kit.beam("StationRail", Vector3(sx + side * 1.05, y_top + 1.0, z_top), Vector3(sx + side * 1.05, y_bottom + 1.0, z_bottom), 0.04, MatLib.steel(), false, 6)
		for t in [0.0, 0.5, 1.0]:
			var p: Vector3 = Vector3(sx + side * 1.05, lerpf(y_top, y_bottom, t) + 0.5, lerpf(z_top, z_bottom, t))
			kit.box("StationRailPost", Vector3(0.06, 1.0, 0.06), p, MatLib.steel(), Vector3.ZERO, false)
	# guard rails only on the outer and rear edges, leaving the core view open
	kit.railing(self, Vector3(sx + sign_value * 1.78, 1.62, 5.15), Vector3(sx + sign_value * 1.78, 1.62, 8.10), 1.05)
	kit.railing(self, Vector3(sx - 1.72, 1.62, 8.10), Vector3(sx + 1.72, 1.62, 8.10), 1.05)
	# work lamp at the outer rear corner, low enough not to silhouette the core
	kit.cylinder("StationLampPost", 0.055, 2.05, Vector3(sx + sign_value * 1.62, 1.62 + 1.02, 7.98), MatLib.steel(), Vector3.ZERO, false, 8)
	kit.cylinder("StationLampHead", 0.18, 0.15, Vector3(sx + sign_value * 1.62, 3.72, 7.98), MatLib.painted_steel(Color(0.22, 0.27, 0.24)), Vector3.ZERO, false, 12)
	kit.sphere("StationLampLens", 0.10, Vector3(sx + sign_value * 1.62, 3.64, 7.98), MatLib.emissive(Color(1.0, 0.72, 0.42), 3.0), 10)
	kit.omni(Vector3(sx + sign_value * 0.6, 3.0, 7.4), Color(1.0, 0.72, 0.42), 0.62, 4.0, false, "StationLamp")
	# small plate on the deck edge, kept out of the operator's sightline
	kit.box("DeckNamePlate", Vector3(0.62, 0.16, 0.02), Vector3(sx, 1.86, 5.12), MatLib.dark_steel(), Vector3.ZERO, false)


func _on_cart_endstop(_side: int, speed: float) -> void:
	if speed > 0.22:
		core.play_surge(minf(1.4, 0.5 + speed * 2.0))
		if audio != null:
			audio.play_sfx("endstop", Vector3(0, 4.2, 1.2), 0.0)


# ---------------------------------------------------------------------------
# Isolation / memory / data / exit
# ---------------------------------------------------------------------------

func _build_isolation() -> void:
	kit.box("IsolationApron", Vector3(5.8, 0.10, 3.9), Vector3(10.5, 0.05, -9.0), MatLib.metal(Color(0.20, 0.24, 0.24), 0.5, 0.5, 0.7), Vector3.ZERO, false)
	for i in range(4):
		kit.box("ApronTread", Vector3(5.4, 0.016, 0.07), Vector3(10.5, 0.11, -10.4 + float(i) * 0.9), MatLib.dark_steel(), Vector3.ZERO, false)
	# back-plate / wall sign on a bracket, clear of the bearing housings
	kit.box("ZoneSignBracket", Vector3(0.10, 0.10, 1.70), Vector3(12.92, 2.18, -6.35), MatLib.dark_steel(), Vector3.ZERO, false)
	kit.warning_sign("隔离区 · 高压能量回路", Vector3(12.92, 2.15, -6.05), -PI * 0.5, 1.10, 0.34)
	kit.spot(Vector3(9.4, 5.6, -5.2), Vector3(10.5, 1.2, -9.0), Color(1.0, 0.72, 0.42), 3.6, 14.0, 34.0, false)
	kit.spot(Vector3(12.2, 5.0, -11.2), Vector3(10.5, 1.1, -9.0), Color(0.55, 0.82, 1.0), 2.2, 12.0, 32.0, false)
	kit.omni(Vector3(11.0, 3.6, -8.0), Color(1.0, 0.62, 0.34), 1.8, 6.0, false, "IsolationKey")
	isolation = IsolationRig.new()
	isolation.name = "ExtractionIsolationRig"
	isolation.position = Vector3(10.5, 0, -9.0)
	add_child(isolation)
	isolation.build()
	isolation.setup(core, null, audio)
	# energy conduits leave the rig towards the back of the bay and follow the
	# floor edge; they no longer cross the operator's approach path.
	conduit_material = MatLib.energy(Color(1.0, 0.22, 0.08), 0.25, 0.15, 2.0)
	conduit_off = MatLib.energy(Color(0.18, 0.55, 0.6), 0.35, 0.3, 2.0)
	kit.box("CableTrayA", Vector3(0.44, 0.08, 8.0), Vector3(6.6, 0.10, -8.0), MatLib.dark_steel(), Vector3(0, deg_to_rad(28), 0), false)
	kit.pipe("ConduitA", [Vector3(7.9, 0.36, -10.6), Vector3(6.8, 0.36, -10.6), Vector3(5.2, 0.36, -9.8), Vector3(3.8, 0.36, -7.2), Vector3(3.4, 0.36, -3.2)], 0.14, MatLib.copper(), false)
	kit.pipe("ConduitGlow", [Vector3(7.9, 0.54, -10.6), Vector3(6.8, 0.54, -10.6), Vector3(5.2, 0.54, -9.8), Vector3(3.8, 0.54, -7.2), Vector3(3.4, 0.54, -3.2)], 0.040, conduit_material, false)
	for i in range(5):
		var cx: float = lerpf(7.4, 4.2, float(i) / 4.0)
		var cz: float = lerpf(-10.6, -8.2, float(i) / 4.0)
		kit.cylinder("ConduitClamp", 0.19, 0.12, Vector3(cx, 0.24, cz), MatLib.dark_steel(), Vector3.ZERO, false, 10)
	kit.omni(Vector3(6.4, 1.2, -9.8), Color(0.95, 0.25, 0.12), 0.7, 4.0, false, "IsolationGlow")


func _build_coop_machines() -> void:
	# --- maintenance catwalk over the west side of the hall ------------------
	catwalk = CatwalkRig.new()
	catwalk.name = "MaintenanceCatwalk"
	catwalk.position = Vector3(-14.0, 0, -4.2)
	add_child(catwalk)
	catwalk.build()
	catwalk.setup(session, audio)
	catwalk.pin_popped.connect(_on_catwalk_pin_popped)

	# --- two hydraulic stabiliser legs pressing the outer ring ---------------
	# MECHANICS-005A-R2: rig radius derived from the contact geometry so the pad
	# can PRESS the ring instead of grazing it:
	#   R_pad(e) = RIG_RADIUS - PAD_FACE_LOCAL_X - STROKE*e
	# RIG_RADIUS 7.60 -> R_pad 5.930..3.580 with the ring face at 4.760. The R0
	# layout (8.786) left 6.4 mm at full stroke, so no contact force was possible.
	var center: Vector3 = Vector3(HALL_CENTER.x, 0, HALL_CENTER.z)
	for side in [-1, 1]:
		var outward: Vector3 = Vector3(side * 6.6, 0.0, -7.8 - HALL_CENTER.z).normalized()
		var base: Vector3 = center + outward * StabilizerRig.RIG_RADIUS
		var inward: Vector3 = (center - base).normalized()
		var yaw: float = atan2(-inward.z, inward.x)
		var stab: StabilizerRig = StabilizerRig.new()
		stab.name = "StabilizerWest" if side < 0 else "StabilizerEast"
		stab.position = base
		add_child(stab)
		stab.build()
		stab.setup(core, session, "stabilizer_w" if side < 0 else "stabilizer_e", "西" if side < 0 else "东", yaw, stabilizers.size())
		stab.setup_audio(audio)
		stabilizers.append(stab)

	# --- emergency resonance brake ------------------------------------------
	brake = BrakeRig.new()
	brake.name = "EmergencyResonanceBrake"
	brake.position = Vector3(-11.8, 0, -5.2)
	add_child(brake)
	brake.build()
	brake.setup(core, session, audio)

	# --- extraction-loop damper next to the isolation bay --------------------
	damper = DamperRig.new()
	damper.name = "ExtractionDamper"
	damper.position = Vector3(6.4, 0, -4.4)
	add_child(damper)
	damper.build()
	damper.setup(session, audio)
	isolation.setup_coop(session, damper)

	# --- physical crew duty board -------------------------------------------
	duty_board = DutyBoard.new()
	duty_board.name = "CrewDutyBoard"
	duty_board.position = Vector3(4.6, 0, 4.9)
	duty_board.rotation.y = -0.42
	add_child(duty_board)
	duty_board.build()
	duty_board.setup(session)

	# --- visible causal links between the machines ---------------------------
	_build_coop_links()
	if lock_rig != null:
		lock_rig.setup_coop(session)


func _build_coop_links() -> void:
	var dark: Material = MatLib.dark_steel()
	# brake -> core pedestal
	kit.pipe("BrakeLine", [Vector3(-10.9, 0.62, -5.2), Vector3(-9.4, 0.62, -4.6), Vector3(-7.4, 0.62, -3.8), Vector3(-5.9, 0.62, -3.2)], 0.10, MatLib.copper(), false)
	for i in range(4):
		var t: float = float(i) / 3.0
		var p: Vector3 = Vector3(-10.4, 0.30, -5.0).lerp(Vector3(-6.3, 0.30, -3.4), t)
		kit.cylinder("BrakeLineClamp", 0.13, 0.24, p + Vector3(0, 0.32, 0), dark, Vector3.ZERO, false, 10)
	# stabiliser legs -> pedestal
	for side in [-1, 1]:
		kit.pipe("StabilizerLine", [Vector3(side * 6.6, 0.55, -7.8), Vector3(side * 5.4, 0.55, -6.4), Vector3(side * 3.9, 0.55, -5.3)], 0.09, MatLib.copper(), false)
	# damper -> isolation bed
	kit.pipe("DamperLineB", [Vector3(7.4, 0.50, -4.2), Vector3(8.2, 0.50, -5.6), Vector3(9.4, 0.50, -7.4)], 0.075, MatLib.copper(), false)
	# power bus from the brake along the north wall to the stabiliser towers
	kit.box("CoopCableTray", Vector3(9.0, 0.10, 0.34), Vector3(-6.4, 0.10, -9.9), dark, Vector3(0, deg_to_rad(-8), 0), false)
	kit.box("CoopCableTrayB", Vector3(7.0, 0.10, 0.34), Vector3(1.6, 0.10, -10.4), dark, Vector3.ZERO, false)
	physical_links = Act5PhysicalLinks.new()
	add_child(physical_links)
	physical_links.build(self)


func _on_catwalk_pin_popped(_remaining: int) -> void:
	if audio != null:
		audio.play_sfx("metal_clank", Vector3(-9.0, 4.0, -4.2), -2.0)
	for i in range(4):
		var p: CPUParticles3D = kit.spark_burst("PinSparks_%d" % i, Vector3(-9.0 + float(i) * 0.6, 4.0, -4.2), 14, Color(1.0, 0.65, 0.3))
		p.emitting = true


func story_stage() -> int:
	if story == null:
		return 0
	return story.stage


func stabilizers_latched() -> int:
	var count: int = 0
	for stab in stabilizers:
		if stab.latched:
			count += 1
	return count


func set_alarm(on: bool) -> void:
	alarm_on = on
	for beacon in beacons:
		if beacon != null:
			beacon.material_override = MatLib.emissive(Color(1.0, 0.15, 0.06) if on else Color(0.95, 0.18, 0.08), 2.6 if on else 1.2)
	if on and audio != null:
		audio.set_tension(1.0)


func set_warning_intensity(value: float) -> void:
	warning_intensity = clampf(value, 0.0, 1.0)
	if not alarm_on:
		return
	for lamp in lamps:
		lamp.set_tension(0.35 + warning_intensity * 0.65)


func _build_memory() -> void:
	memory = MemoryShard.new()
	memory.name = "MinerMemoryCrystal"
	memory.position = Vector3(-11.8, 0, 0.6)
	add_child(memory)
	memory.build()
	# a low rock shelf under the pedestal so it grows out of the floor
	kit.rock("MemoryShelf", "res://assets/rocks/rock_outcrop_c.glb", Vector3(-11.8, 0.0, 0.6), 32.0, 0.62, MatLib.rock(Color(0.28, 0.27, 0.29), Color(0.12, 0.5, 0.6), 0.4), true)


func _build_data_plinth() -> void:
	data_plinth = DataPlinth.new()
	data_plinth.name = "NavigationDataPlinth"
	data_plinth.position = Vector3(-3.0, 0, -10.0)
	add_child(data_plinth)
	data_plinth.build()
	data_plinth.setup(audio)
	data_plinth.setup_coop(session)
	


func _build_exit() -> void:
	# corridor shell (visible boxes with matching collision)
	var mat_wall: Material = MatLib.metal(Color(0.19, 0.22, 0.22), 0.58, 0.45, 0.75)
	var mat_floor: Material = MatLib.metal(Color(0.21, 0.23, 0.23), 0.52, 0.55, 0.7)
	kit.box("ExitFloor", Vector3(14.0, 0.30, 4.5), Vector3(-22.6, -0.15, -2.0), mat_floor, Vector3.ZERO, true)
	for i in range(14):
		kit.box("ExitTread", Vector3(0.94, 0.014, 4.06), Vector3(-16.0 - float(i) * 0.98, 0.012, -2.0), MatLib.dark_steel(), Vector3.ZERO, false)
	for sz in [-2.25, 2.25]:
		kit.box("ExitWall", Vector3(14.0, 4.2, 0.40), Vector3(-22.6, 2.0, -2.0 + sz), mat_wall, Vector3.ZERO, true)
	kit.box("ExitCeiling", Vector3(14.0, 0.40, 4.9), Vector3(-22.6, 4.05, -2.0), mat_wall, Vector3.ZERO, true)
	kit.box("ExitEndWall", Vector3(0.5, 4.2, 4.9), Vector3(-29.4, 2.1, -2.0), mat_wall, Vector3.ZERO, true)
	# portal frame at the hall mouth, covering the shell edge
	# The corridor is centred on z = -2, so the portal posts must be offset from
	# that centre. Without the offset one post stood in the middle of the doorway
	# and the walkway looked split in two.
	for sz2 in [-2.15, 2.15]:
		kit.box("ExitPortalColumn", Vector3(0.55, 4.35, 0.55), Vector3(-16.05, 2.17, -2.0 + sz2), MatLib.painted_steel(Color(0.26, 0.30, 0.29)), Vector3.ZERO, true)
	kit.box("ExitPortalLintel", Vector3(0.75, 0.55, 4.85), Vector3(-16.05, 4.25, -2.0), MatLib.painted_steel(Color(0.26, 0.30, 0.29)), Vector3.ZERO, true)
	# ribs protrude into the corridor instead of hiding inside the wall boxes
	for x in [-17.2, -20.2, -23.2, -26.2, -28.5]:
		for sz3 in [-4.02, 0.02]:
			kit.box("ExitRib", Vector3(0.24, 4.0, 0.14), Vector3(x, 2.0, sz3), MatLib.steel(), Vector3.ZERO, false)
		kit.box("ExitRibTop", Vector3(0.26, 0.26, 4.16), Vector3(x, 3.80, -2.0), MatLib.steel(), Vector3.ZERO, false)
		# wall-mounted conduit with brackets, adding depth without blocking
		kit.pipe("ExitConduit", [Vector3(x - 0.6, 2.62, -4.02), Vector3(x + 0.6, 2.62, -4.02)], 0.045, MatLib.copper(), false)
		kit.box("ConduitBracket", Vector3(0.06, 0.34, 0.06), Vector3(x - 0.6, 2.45, -4.02), MatLib.dark_steel(), Vector3.ZERO, false)
	for x in [-18.0, -22.5, -27.0]:
		kit.omni(Vector3(x, 3.35, -2.0), Color(1.0, 0.72, 0.4), 2.0, 6.5, false, "ExitLamp")
		kit.box("ExitLightBar", Vector3(1.4, 0.06, 0.18), Vector3(x, 3.76, -2.0), MatLib.emissive(Color(1.0, 0.82, 0.55), 2.0), Vector3.ZERO, false)
		kit.box("ExitLightHousing", Vector3(1.55, 0.12, 0.34), Vector3(x, 3.84, -2.0), MatLib.dark_steel(), Vector3.ZERO, false)
	# floor guide strips lead the eye to the lift
	for sz4 in [-1.75, 1.75]:
		kit.box("ExitGuide", Vector3(13.0, 0.012, 0.05), Vector3(-22.8, 0.014, -2.0 + sz4), MatLib.emissive(Color(0.3, 0.85, 0.75), 0.8), Vector3.ZERO, false)
	# lift platform at the far end
	kit.box("EvacLift", Vector3(3.2, 0.3, 3.4), Vector3(-27.8, 0.15, -2.0), MatLib.metal(Color(0.25, 0.27, 0.25), 0.45, 0.7, 0.4), Vector3.ZERO, true)
	kit.box("LiftBack", Vector3(0.3, 3.2, 3.4), Vector3(-29.1, 1.6, -2.0), MatLib.painted_steel(Color(0.28, 0.32, 0.28)), Vector3.ZERO, false)
	kit.box("LiftFrameL", Vector3(0.35, 3.4, 0.3), Vector3(-28.6, 1.7, -3.35), MatLib.steel(), Vector3.ZERO, false)
	kit.box("LiftFrameR", Vector3(0.35, 3.4, 0.3), Vector3(-28.6, 1.7, -0.65), MatLib.steel(), Vector3.ZERO, false)
	kit.label3d("撤离升降机 · 上行", Vector3(-27.8, 3.05, -0.2), 0.0034, Color(0.85, 1.0, 0.9), 38)
	kit.omni(Vector3(-27.8, 2.8, -2.0), Color(0.65, 0.95, 0.85), 2.6, 8.0, false, "LiftLight")
	exit_door = ExitDoor.new()
	exit_door.name = "ExitBlastDoor"
	exit_door.position = Vector3(-15.7, 0, -2.0)
	add_child(exit_door)
	exit_door.build()
	exit_door.setup(audio)


# ---------------------------------------------------------------------------
# Props, lights, triggers
# ---------------------------------------------------------------------------

func _build_props() -> void:
	# crystal growths around the hall: every cluster has a rock host that is
	# visibly rooted in the floor or wall, so nothing reads as a floating prop.
	var crystal_specs: Array = [
		{"pos": Vector3(-15.0, 0.0, -7.0), "rot": 30.0, "scale": 0.90},
		{"pos": Vector3(14.8, 0.0, 7.8), "rot": -50.0, "scale": 0.62},
		{"pos": Vector3(-9.6, 0.0, -13.4), "rot": 75.0, "scale": 1.00},
		{"pos": Vector3(14.8, 0.0, -15.5), "rot": -25.0, "scale": 0.8},
		{"pos": Vector3(-14.6, 0.0, 6.4), "rot": -70.0, "scale": 0.8},
	]
	for spec in crystal_specs:
		var info: Dictionary = spec as Dictionary
		kit.rock("CrystalHost", "res://assets/rocks/rock_outcrop_a.glb", (info["pos"] as Vector3) + Vector3(0, 0.1, 0), float(info["rot"]) + 20.0, 0.72, MatLib.rock(Color(0.27, 0.255, 0.27), Color(0.10, 0.45, 0.55), 0.35), true)
		kit.crystal_cluster("CrystalCluster", (info["pos"] as Vector3) + Vector3(0, 0.35, 0), float(info["rot"]), float(info["scale"]), MatLib.cave_crystal(), true)
	# stalactites hang from the dome: the asset already points down, so the old
	# 180-degree flip (which produced plate-like "UFO" slabs) is gone.
	var stalactite_positions: Array[Vector3] = [
		Vector3(-9.0, 19.3, -9.0), Vector3(-4.0, 19.7, -12.0), Vector3(7.0, 19.5, -10.0),
		Vector3(10.0, 19.0, 5.0), Vector3(-10.0, 19.4, 6.0), Vector3(2.0, 19.9, 8.0),
	]
	for p2 in stalactite_positions:
		kit.rock("Stalactite", "res://assets/rocks/rock_stalactite_a.glb", p2, randf_range(0.0, 360.0), 1.35, MatLib.rock(Color(0.31, 0.29, 0.29), Color(0.1, 0.4, 0.46), 0.25), false, 0.0, 0.0)
	# hanging lamps and swaying equipment
	var lamp_positions: Array[Vector3] = [
		Vector3(-10.0, 13.0, 6.0), Vector3(10.4, 13.4, 5.4),
		Vector3(-7.0, 14.0, -10.0), Vector3(8.0, 13.6, -11.0),
	]
	for i in range(lamp_positions.size()):
		var lamp: SwingLamp = SwingLamp.new()
		lamp.name = "HallLamp_%d" % i
		lamp.position = lamp_positions[i]
		add_child(lamp)
		lamp.build(4.2, Color(1.0, 0.68, 0.38))
		lamp.phase = float(i) * 1.7
		lamp.freq = 0.8 + float(i) * 0.11
		lamps.append(lamp)
	# pipes along the east wall
	kit.pipe("HallPipeA", [Vector3(14.2, 0.4, 8.0), Vector3(14.2, 5.5, 8.0), Vector3(14.2, 5.5, -8.0), Vector3(14.2, 0.6, -12.0)], 0.16, MatLib.copper(), false)
	for pz in [7.5, 4.0, 0.0, -4.0, -7.5, -10.5]:
		kit.box("PipeBracket", Vector3(0.5, 0.08, 0.12), Vector3(13.98, 5.35 if pz > -8.0 else 2.3, pz), MatLib.dark_steel(), Vector3.ZERO, false)
	kit.pipe("HallPipeB", [Vector3(-14.6, 0.4, 7.0), Vector3(-14.6, 6.0, 7.0), Vector3(-14.6, 6.0, -10.0)], 0.12, MatLib.steel(), false)
	# crates / tools near the stations
	kit.crate("HallCrate", Vector3(-11.8, 0.55, 7.0), Vector3(1.0, 1.1, 1.1), Vector3(0, 0.3, 0))
	kit.crate("HallCrate2", Vector3(12.0, 0.45, 6.4), Vector3(0.9, 0.9, 0.9), Vector3(0, -0.2, 0))
	kit.box("ToolBench", Vector3(2.2, 0.8, 0.8), Vector3(14.4, 0.4, 4.6), MatLib.dark_steel(), Vector3.ZERO, true)
	for i in range(3):
		kit.cylinder("ToolCase", 0.16, 0.5, Vector3(13.8 + float(i) * 0.35, 0.95, 4.6), MatLib.painted_steel(Color(0.32, 0.24, 0.12)), Vector3(0, 0, deg_to_rad(90)), false, 10)
	# floor dust and ceiling dust
	kit.dust("HallDustA", HALL_CENTER + Vector3(-6, 4, 3), Vector3(4, 3, 4), 34, Color(0.45, 0.65, 0.7, 0.35))
	kit.dust("HallDustB", HALL_CENTER + Vector3(6, 6, -5), Vector3(5, 4, 5), 30, Color(0.4, 0.6, 0.65, 0.3))
	kit.dust("TunnelDust", Vector3(0, 6.2, 30), Vector3(3, 1.6, 8), 26, Color(0.55, 0.66, 0.66, 0.28))
	# beacons on the walls
	for i in range(8):
		var a: float = TAU * float(i) / 8.0 + 0.2
		var p3: Vector3 = HALL_CENTER + Vector3(cos(a) * 15.2, 6.8 + 1.6 * sin(float(i) * 1.3), sin(a) * 15.2)
		var beacon: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(0.26, 0.52, 0.2)
		beacon.mesh = bm
		beacon.material_override = MatLib.emissive(Color(0.95, 0.18, 0.08), 1.2)
		beacon.position = p3
		add_child(beacon)
		beacon.look_at(HALL_CENTER + Vector3(0, 5, 0), Vector3.UP)
		beacon.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		beacons.append(beacon)
	# resonance floor rings (subtle visual rhythm)
	for i in range(3):
		var ring_mat: ShaderMaterial = MatLib.energy(Color(0.18, 0.65, 0.85), 0.35, 0.25 + float(i) * 0.1, 4.0)
		kit.torus("ResonanceRing", 10.0 + float(i) * 2.0, 0.018, HALL_CENTER + Vector3(0, 0.14, 0), ring_mat, Basis(), 72, 4)


func _build_lights() -> void:
	# broad, soft fill so the hall is readable without flattening the core
	kit.omni(Vector3(0, 9.5, 3.0), Color(0.50, 0.66, 0.78), 9.0, 34.0, false, "HallFill")
	kit.omni(Vector3(0, 5.5, -8.0), Color(0.36, 0.50, 0.60), 4.2, 22.0, false, "HallFillRear")
	kit.omni(Vector3(0, 2.8, 5.0), Color(0.95, 0.66, 0.40), 4.0, 15.0, false, "FloorFill")
	kit.omni(Vector3(0, 3.2, -6.5), Color(0.40, 0.62, 0.75), 2.8, 13.0, false, "CoreUnderFill")
	kit.omni(Vector3(-7.5, 13.0, -2.0), Color(0.42, 0.58, 0.70), 4.0, 24.0, false, "DomeFillA")
	kit.omni(Vector3(7.5, 13.0, -2.0), Color(0.42, 0.58, 0.70), 4.0, 24.0, false, "DomeFillB")
	kit.omni(Vector3(0, 15.0, 2.0), Color(0.38, 0.52, 0.66), 3.5, 22.0, false, "DomeFillC")
	# warm safety lighting around the hall
	kit.omni(Vector3(-11.5, 5.2, 7.5), Color(1.0, 0.62, 0.32), 6.8, 18.0, false, "HallWarmA")
	kit.omni(Vector3(11.5, 5.2, 7.5), Color(1.0, 0.62, 0.32), 6.8, 18.0, false, "HallWarmB")
	kit.omni(Vector3(-12.0, 4.0, -8.0), Color(0.55, 0.75, 0.85), 3.0, 13.0, false, "HallCoolA")
	kit.omni(Vector3(12.0, 4.6, -11.0), Color(0.9, 0.45, 0.22), 2.6, 12.0, false, "HallCoolB")
	kit.omni(Vector3(0, 7.0, 12.0), Color(1.0, 0.7, 0.4), 3.4, 12.0, false, "BalconyLamp")
	# spotlights from the balcony onto the core
	kit.spot(Vector3(-4.4, 10.0, 11.0), Vector3(0, 8.5, -2), Color(0.45, 0.82, 1.0), 0.95, 30.0, 26.0, false)
	kit.spot(Vector3(4.4, 10.0, 11.0), Vector3(0, 8.5, -2), Color(0.55, 0.45, 1.0), 0.8, 30.0, 26.0, false)
	kit.omni(Vector3(0, 6.0, 4.0), Color(0.45, 0.75, 0.95), 2.0, 12.0, false, "RingFillA")
	kit.omni(Vector3(0, 6.0, -8.0), Color(0.55, 0.45, 0.95), 1.8, 12.0, false, "RingFillB")
	# entrance
	var flicker: FlickerLight = FlickerLight.new()
	flicker.name = "BrokenLamp"
	flicker.position = Vector3(0, TUNNEL_FLOOR_Y + 4.1, 28.5)
	add_child(flicker)
	flicker.build(Color(1.0, 0.6, 0.3), 3.2, 10.0)
	kit.omni(Vector3(0, TUNNEL_FLOOR_Y + 3.9, 35.5), Color(1.0, 0.7, 0.42), 3.0, 10.0, false, "TunnelWarm")
	kit.omni(Vector3(0, TUNNEL_FLOOR_Y + 3.0, 20.0), Color(0.75, 0.85, 0.9), 2.0, 9.0, false, "TunnelCool")
	# isolation warning
	kit.omni(Vector3(10.5, 2.8, -9.0), Color(0.95, 0.3, 0.15), 1.8, 9.0, false, "IsolationWarm")
	# fill light on the exit side
	kit.omni(Vector3(-13.0, 4.0, -2.0), Color(0.4, 0.65, 0.7), 2.0, 10.0, false, "ExitFill")


func _build_triggers() -> void:
	hall_trigger = _make_trigger("HallEnterTrigger", Vector3(0, BALCONY_Y + 0.9, 12.2), Vector3(10.0, 3.0, 2.0))
	hall_trigger.body_entered.connect(_on_hall_trigger)
	exit_trigger = _make_trigger("ExitTrigger", Vector3(-25.5, 1.3, -2.0), Vector3(3.2, 2.8, 3.6))
	exit_trigger.body_entered.connect(_on_exit_trigger)
	# checkpoint trigger at the isolation bay is derived from the rig event


func _make_trigger(node_name: String, pos: Vector3, size: Vector3) -> Area3D:
	var area: Area3D = Area3D.new()
	area.name = node_name
	area.position = pos
	area.collision_layer = 16
	area.collision_mask = 2
	area.monitoring = true
	area.monitorable = true
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	area.add_child(col)
	add_child(area)
	return area


func _on_hall_trigger(body: Node) -> void:
	if body is PlayerController:
		hall_entered.emit()


func _on_exit_trigger(body: Node) -> void:
	if body is PlayerController:
		exit_reached.emit()


















