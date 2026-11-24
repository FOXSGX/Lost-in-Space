class_name Act1StationBuilder
extends RefCounted

## Builds the complete Act 01 physical space: exterior landing, entry airlock,
## auxiliary power room, the giant ventilation hall and the departure station.
## Every visible floor/wall/rail surface gets a matching collision primitive.
##
## Integration note: source project class_name `StationBuilder` renamed to
## `Act1StationBuilder`; all imported rock/texture paths are module-relative.

const SPAWN := Vector3(0.0, 0.06, 22.0)
const SOCKET := Vector3(4.25, 1.34, -4.95)
const CATWALK_Y := 3.42
const PIT_Y := -3.35

var stage: Node3D
var kit: Act1WorldKit
var door: Act1EntryDoor
var power_cart: Act1PowerCart
## MECHANICS-001A：导轨上的真实电源模块刚体
var power_module: RigidBody3D = null
var vent: Act1Ventilation
var fan_interlock: Act1FanInterlock = null
var wheel_chock: Act1WheelChock = null
var parking_brake: Act1ParkingBrake = null
## MECHANICS-001F：货舱固定带系统（真实货箱刚体 + 锚点 + 张力带 + 棘轮）
var cargo_rig: Act1CargoRig = null
var mine_cart: Act1MineCartRig
var wind_crate: Act1WindCrate
var rail_obstacle: RigidBody3D
var entry_obstruction: RigidBody3D
var socket_clamp: Act1Interactable
var winch_console: Act1Interactable
var ladder_anchor: Act1Interactable
var strap_control: Act1Interactable
var _font: SystemFont
var _rock_mat: StandardMaterial3D
var _concrete_mat: StandardMaterial3D
var _steel: ShaderMaterial
var _dark: ShaderMaterial
var _paint: ShaderMaterial
var _hazard: ShaderMaterial
var _cyan: StandardMaterial3D
var _amber: StandardMaterial3D
var _red: StandardMaterial3D
var _rail_mat: ShaderMaterial


func build(p_stage: Node3D) -> void:
	stage = p_stage
	kit = Act1WorldKit.new(stage)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_font.hinting = TextServer.HINTING_LIGHT
	_make_materials()
	_build_environment()
	_build_exterior()
	_build_entry()
	_build_power_room()
	_build_ventilation_hall()
	_build_station()
	_build_lighting()
	_build_dust()
	door = Act1EntryDoor.new()
	stage.add_child(door)
	door.setup(stage)
	power_cart = Act1PowerCart.new()
	stage.add_child(power_cart)
	power_cart.setup(stage)
	_build_power_module_rail()
	vent = Act1Ventilation.new()
	stage.add_child(vent)
	vent.setup(stage)
	mine_cart = Act1MineCartRig.new()
	stage.add_child(mine_cart)
	mine_cart.setup(stage)
	# MECHANICS-001F：货舱固定带系统挂在矿车上（锚点随车运动），货物是独立真实刚体
	cargo_rig = Act1CargoRig.new()
	cargo_rig.setup(stage, mine_cart)
	# Register interactions owned by moving rigs so the host validation table can
	# resolve them as well as the raycast.
	stage.interactables["door_handle"] = door.handle
	stage.interactables["cart_push"] = power_cart.handle
	stage.interactables["launch_cart"] = mine_cart.launch_handle
	wind_crate = Act1WindCrate.new()
	stage.add_child(wind_crate)
	wind_crate.setup(stage, Vector3(2.45, CATWALK_Y + 0.51, -28.4))
	_build_controls()
	_build_obstructions()
	# Static mesh merging was prototyped for draw-call reduction but caused rare
	# mid-run engine exits in long headless sessions. It is intentionally disabled
	# in the delivery build; stability takes priority over the draw-call win.


func _make_materials() -> void:
	_steel = Act1MatLib.steel()
	_dark = Act1MatLib.dark_steel()
	_paint = Act1MatLib.painted_steel(Color(0.24, 0.34, 0.37))
	_hazard = Act1MatLib.hazard()
	_cyan = Act1MatLib.emissive(Color(0.14, 0.78, 0.92), 1.0)
	_amber = Act1MatLib.emissive(Color(1.0, 0.56, 0.17), 1.05)
	_red = Act1MatLib.emissive(Color(1.0, 0.16, 0.10), 1.15)
	_rail_mat = Act1MatLib.metal(Color(0.31, 0.32, 0.31), 0.34, 0.82, 0.58)
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.albedo_texture = load("res://act1/assets/textures/rock_color.jpg")
	_rock_mat.normal_enabled = true
	_rock_mat.normal_texture = load("res://act1/assets/textures/rock_normal.jpg")
	_rock_mat.roughness_texture = load("res://act1/assets/textures/rock_rough.jpg")
	_rock_mat.albedo_color = Color(0.60, 0.58, 0.55)
	_rock_mat.roughness = 0.92
	_rock_mat.uv1_triplanar = true
	_rock_mat.uv1_scale = Vector3(0.18, 0.18, 0.18)
	_rock_mat.uv1_triplanar_sharpness = 4.0
	_concrete_mat = StandardMaterial3D.new()
	_concrete_mat.albedo_texture = load("res://act1/assets/textures/rock_color.jpg")
	_concrete_mat.albedo_color = Color(0.30, 0.31, 0.30)
	_concrete_mat.roughness = 0.9
	_concrete_mat.uv1_triplanar = true
	_concrete_mat.uv1_scale = Vector3(0.30, 0.30, 0.30)


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.012, 0.035, 0.055)
	sky_mat.sky_horizon_color = Color(0.13, 0.12, 0.12)
	sky_mat.ground_bottom_color = Color(0.008, 0.009, 0.010)
	sky_mat.ground_horizon_color = Color(0.11, 0.085, 0.065)
	sky_mat.sun_angle_max = 18.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.47, 0.54)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.065, 0.095, 0.11)
	env.fog_light_energy = 0.7
	env.fog_density = 0.010
	env.fog_height = 6.0
	env.fog_height_density = 0.03
	world.environment = env
	stage.add_child(world)


func _build_exterior() -> void:
	# uneven rock apron around a steel landing
	kit.box("ExtLanding", Vector3(18, 0.5, 19), Vector3(0, -0.25, 17.5), _concrete_mat)
	# The exterior is a rock-cut landing. The cliff faces are textured surfaces
	# with real collision, not loose imported shard meshes that can swallow spawn.
	kit.box("ExtBoundL", Vector3(0.5, 8.0, 20.0), Vector3(-9.1, 3.8, 17.5), _rock_mat)
	kit.box("ExtBoundR", Vector3(0.5, 8.0, 20.0), Vector3(9.1, 3.8, 17.5), _rock_mat)
	kit.box("ExtBoundBack", Vector3(18.7, 8.0, 0.5), Vector3(0, 3.8, 27.4), _rock_mat)
	kit.box("ExtCliffShelfL", Vector3(1.8, 3.8, 18.0), Vector3(-8.2, 5.0, 17.0), _rock_mat, Vector3(0, 0, 0.10), false)
	kit.box("ExtCliffShelfR", Vector3(1.2, 2.8, 16.0), Vector3(8.4, 4.2, 18.0), _rock_mat, Vector3(0, 0, -0.08), false)
	kit.box("ExtCliffEye", Vector3(1.5, 1.5, 1.4), Vector3(-6.8, 6.4, 10.8), _rock_mat, Vector3.ZERO, false)
	kit.box("ExtCliffEye2", Vector3(1.1, 1.2, 1.8), Vector3(7.0, 6.0, 11.8), _rock_mat, Vector3.ZERO, false)
	for x in [-9.05, 9.05]:
		for y in [2.0, 5.2]:
			kit.box("ExtRockRib", Vector3(0.55, 0.45, 17.0), Vector3(x, y, 17.5), _dark, Vector3.ZERO, false)
		kit.box("ExtRockPipe", Vector3(0.25, 7.6, 0.25), Vector3(x - 0.45 * signf(x), 3.8, 10.5), _steel, Vector3.ZERO, false)
	kit.box("ExtFacadeL", Vector3(4.5, 7.0, 0.6), Vector3(-6.85, 3.3, 9.35), _paint)
	kit.box("ExtFacadeR", Vector3(4.5, 7.0, 0.6), Vector3(6.85, 3.3, 9.35), _paint)
	kit.box("ExtDeckEdge", Vector3(8.0, 0.35, 12.0), Vector3(0, 0.05, 14.0), _dark, Vector3.ZERO, false)
	for x in [-1.15, 1.15]:
		kit.box("LegacyRail", Vector3(0.14, 0.16, 15.5), Vector3(x, 0.10, 18.2), _rail_mat, Vector3.ZERO, false)
	for i in range(18):
		kit.box("LegacySleeper_%d" % i, Vector3(3.0, 0.10, 0.22), Vector3(0, 0.02, 11.0 + i * 0.82), _dark, Vector3.ZERO, false)
	# distinctive portal
	var portal_z := 9.35
	for x in [-4.6, 4.6]:
		kit.box("PortalPylon", Vector3(1.25, 6.3, 1.65), Vector3(x, 3.15, portal_z), _paint)
		kit.box("PortalFoot", Vector3(2.2, 0.55, 2.6), Vector3(x, 0.27, portal_z), _dark)
		kit.beam("PortalBrace", Vector3(x, 1.1, portal_z - 0.8), Vector3(x, 5.7, portal_z + 0.8), 0.11, _steel)
	kit.box("PortalHeader", Vector3(10.6, 1.25, 1.75), Vector3(0, 6.05, portal_z), _paint)
	kit.box("PortalLintel", Vector3(9.3, 0.38, 1.4), Vector3(0, 5.35, portal_z), _hazard, Vector3.ZERO, false)
	kit.box("PortalSignBack", Vector3(8.9, 1.05, 0.18), Vector3(0, 6.22, portal_z + 0.92), _dark, Vector3.ZERO, false)
	kit.box("PortalSignRim", Vector3(9.1, 0.12, 0.24), Vector3(0, 6.77, portal_z + 0.92), _amber, Vector3.ZERO, false)
	_sign_label("K-17  /  沉默矿区  /  SILENT MINING STATION", Vector3(0, 6.27, portal_z + 1.02), 58, Color(1.0, 0.78, 0.38), 0.0048)
	_sign_label("AUXILIARY POWER  ·  VENTILATION  ·  TRACK 01", Vector3(0, 5.58, portal_z + 1.02), 30, Color(0.50, 0.84, 0.88), 0.0032)
	# outside work lights and abandoned equipment
	for x in [-4.2, 4.2]:
		var lamp := kit.box("EntryLamp", Vector3(0.35, 0.18, 0.65), Vector3(x, 4.7, portal_z - 0.95), _amber, Vector3.ZERO, false)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.box("AbandonedBarrier", Vector3(3.4, 0.18, 0.18), Vector3(-4.8, 1.2, 18.6), _hazard, Vector3(0, 0.22, 0), false)
	for i in range(4):
		kit.box("BarrierLeg", Vector3(0.13, 1.2, 0.13), Vector3(-6.1 + i * 1.7, 0.6, 18.6), _steel, Vector3(0, 0.22, 0), false)
	kit.crate("ExteriorCrateA", Vector3(6.7, 0.55, 14.5), Vector3(1.2, 1.1, 1.2), Vector3(0, 0.2, 0))
	kit.crate("ExteriorCrateB", Vector3(5.9, 0.35, 16.0), Vector3(0.9, 0.7, 0.9), Vector3(0, -0.3, 0))
	# rock roof over the approach, supported by actual steel beams
	_rock("ApproachRoof", "res://act1/assets/rocks/vault_slab_a.glb", Vector3(0, 10.4, 16), 0, 3.5, false)
	kit.beam("RoofTieL", Vector3(-4.6, 6.3, 14.0), Vector3(-4.6, 9.5, 11.0), 0.18, _steel)
	kit.beam("RoofTieR", Vector3(4.6, 6.3, 14.0), Vector3(4.6, 9.5, 11.0), 0.18, _steel)
	# distant track disappearing into the dark
	for i in range(5):
		kit.box("DistantSleeper_%d" % i, Vector3(3.0, 0.08, 0.2), Vector3(0, 0.04, 31.0 + i * 1.5), _dark, Vector3.ZERO, false)


func _build_entry() -> void:
	# short airlock, deliberately compressed after the wide outside apron
	kit.box("EntryFloor", Vector3(8.4, 0.5, 8.0), Vector3(0, -0.25, 5.2), _dark)
	kit.box("EntryCeil", Vector3(9.0, 0.4, 8.0), Vector3(0, 6.2, 5.2), _paint, Vector3.ZERO, false)
	kit.box("EntryWallL", Vector3(0.4, 6.4, 8.0), Vector3(-4.25, 3.2, 5.2), _paint)
	kit.box("EntryWallR", Vector3(0.4, 6.4, 8.0), Vector3(4.25, 3.2, 5.2), _paint)
	for i in range(5):
		kit.box("EntryRib", Vector3(0.16, 6.0, 0.42), Vector3(-4.0, 3.0, 2.4 + i * 1.5), _steel, Vector3.ZERO, false)
		kit.box("EntryRibR", Vector3(0.16, 6.0, 0.42), Vector3(4.0, 3.0, 2.4 + i * 1.5), _steel, Vector3.ZERO, false)
		kit.box("EntryLight", Vector3(0.10, 0.12, 1.1), Vector3(-3.96, 3.8, 2.8 + i * 1.5), _cyan, Vector3.ZERO, false)
	# pipes and cable tray above the player
	kit.pipe("EntryPipeA", [Vector3(-3.7, 5.5, 1.6), Vector3(-3.7, 5.5, 8.6)], 0.095, _steel)
	kit.pipe("EntryPipeB", [Vector3(3.7, 5.3, 1.6), Vector3(3.7, 5.3, 8.6)], 0.075, _dark)
	for z in [3.0, 6.0]:
		kit.box("EntryTray", Vector3(7.2, 0.08, 0.55), Vector3(0, 5.72, z), _dark, Vector3.ZERO, false)
	# control plate beside the door
	kit.box("LatchCabinet", Vector3(0.8, 1.6, 0.5), Vector3(2.72, 1.25, 9.25), _paint)
	kit.box("LatchHandle", Vector3(0.12, 0.62, 0.18), Vector3(2.72, 1.70, 9.55), _amber, Vector3.ZERO, false)
	var latch := stage.call("make_interactable", "release_latch", "E 释放机械门闩", Vector3(2.72, 1.55, 9.62), Vector3(0.55, 0.9, 0.35), false) as Act1Interactable
	latch.add_focus_marker(0.20)
	# powered door status panel and instructions
	kit.box("DoorStatus", Vector3(0.48, 0.32, 0.12), Vector3(-2.85, 2.0, 9.0), _red, Vector3.ZERO, false)
	_sign_label("安全门 · 清理门轨后释放门闩", Vector3(-2.45, 3.05, 9.05), 32, Color(0.85, 0.62, 0.27), 0.0031)


func _build_power_room() -> void:
	# floor and perimeter
	kit.box("PowerFloor", Vector3(15.8, 0.5, 14.4), Vector3(-1.35, -0.25, -3.9), _dark)
	kit.box("PowerCeil", Vector3(15.8, 0.4, 14.4), Vector3(-1.35, 5.15, -3.9), _paint, Vector3.ZERO, false)
	kit.box("PowerWallL", Vector3(0.4, 5.6, 14.4), Vector3(-9.25, 2.7, -3.9), _paint)
	kit.box("PowerWallBackL", Vector3(6.2, 5.6, 0.4), Vector3(-6.1, 2.7, -11.1), _rock_mat)
	kit.box("PowerWallBackR", Vector3(3.4, 5.6, 0.4), Vector3(4.3, 2.7, -11.1), _rock_mat)
	kit.box("PowerArchHeader", Vector3(5.6, 1.2, 0.4), Vector3(-0.2, 5.0, -11.1), _paint)
	kit.box("VentThreshold", Vector3(5.6, 0.5, 1.15), Vector3(-0.2, -0.25, -11.6), _dark)
	kit.box("PowerWallR", Vector3(0.4, 5.6, 5.0), Vector3(6.05, 2.7, -1.5), _paint)
	kit.box("PowerWallR2", Vector3(0.4, 5.6, 4.4), Vector3(6.05, 2.7, -8.8), _paint)
	kit.box("PowerWallR3", Vector3(0.4, 5.6, 2.8), Vector3(6.05, 2.7, -5.2), _paint)
	# the corridor from entry is cut through the south wall
	kit.box("PowerSouthL", Vector3(7.6, 5.6, 0.4), Vector3(-5.4, 2.7, 3.25), _paint)
	kit.box("PowerSouthR", Vector3(3.2, 5.6, 0.4), Vector3(4.4, 2.7, 3.25), _paint)
	kit.box("PowerHeader", Vector3(3.6, 1.7, 0.4), Vector3(0.2, 4.5, 3.25), _paint)
	# floor plates, drains and hazard borders
	for i in range(7):
		kit.box("PowerPlate_%d" % i, Vector3(2.0, 0.03, 13.4), Vector3(-8.2 + i * 2.2, 0.015, -3.9), _steel, Vector3.ZERO, false)
	kit.box("PowerHazardLine", Vector3(15.2, 0.025, 0.18), Vector3(-1.35, 0.03, -9.95), _hazard, Vector3.ZERO, false)
	for i in range(9):
		var cable := kit.beam("FloorCable_%d" % i, Vector3(-8.8, 0.06, -8.7 + i * 0.16), Vector3(4.4, 0.06, -8.4 + i * 0.1), 0.035, Act1MatLib.flat(Color(0.04, 0.05, 0.05), 0.9))
		cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# battery / transformer banks along the back and west walls
	for i in range(3):
		var x := -8.25 + i * 1.75
		kit.box("PowerBank_%d" % i, Vector3(1.55, 2.45, 1.1), Vector3(x, 1.22, -9.9), _paint)
		for j in range(5):
			kit.box("BatteryCell", Vector3(1.30, 0.16, 0.05), Vector3(x, 0.55 + j * 0.38, -9.32), _dark, Vector3.ZERO, false)
		kit.box("BankCap", Vector3(1.75, 0.22, 1.3), Vector3(x, 2.55, -9.9), _dark, Vector3.ZERO, false)
		kit.box("BankLamp", Vector3(0.18, 0.06, 0.03), Vector3(x, 2.12, -9.31), _amber, Vector3.ZERO, false)
	# one remote rack east of the maintenance opening
	kit.box("PowerBank_E", Vector3(1.55, 2.45, 1.1), Vector3(4.2, 1.22, -9.9), _paint)
	for i in range(3):
		kit.box("PowerCabinet_%d" % i, Vector3(1.25, 2.1, 0.8), Vector3(-8.55, 1.05, -7.0 + i * 2.1), _paint, Vector3(0, PI * 0.5, 0))
		kit.box("CabinetFace", Vector3(0.75, 0.60, 0.03), Vector3(-8.10, 1.35, -7.0 + i * 2.1), Act1MatLib.energy(Color(0.12, 0.62, 0.72), 0.6, 0.25, 5.0), Vector3(0, PI * 0.5, 0), false)
	# busbars and cable bridge
	for i in range(3):
		kit.box("Busbar", Vector3(12.8, 0.10, 0.10), Vector3(-1.6, 4.35 + i * 0.18, -8.8), _amber, Vector3.ZERO, false)
	for i in range(8):
		kit.box("BusbarDrop", Vector3(0.06, 2.0, 0.06), Vector3(-7.5 + i * 1.7, 3.35, -8.8), _dark, Vector3.ZERO, false)
		kit.box("CableCoil", Vector3(0.5, 0.5, 0.5), Vector3(-7.5 + i * 1.7, 4.15, -8.8), _dark, Vector3.ZERO, false)
	# work light over the cart route
	kit.box("PowerLampBar", Vector3(8.0, 0.10, 0.18), Vector3(0, 4.7, -2.2), _cyan, Vector3.ZERO, false)
	kit.box("PowerSignBack", Vector3(5.4, 0.8, 0.12), Vector3(-2.0, 3.55, -10.84), _dark, Vector3.ZERO, false)
	_sign_label("AUXILIARY POWER  /  辅助电源维修区", Vector3(-2.0, 3.57, -10.76), 45, Color(0.48, 0.86, 0.90), 0.0040)
	# power cart rails and the socket cradle
	for z in [-2.20, -2.90]:
		kit.box("CartRail", Vector3(11.2, 0.12, 0.12), Vector3(-0.1, 0.10, z), _rail_mat, Vector3.ZERO, false)
	for i in range(13):
		kit.box("CartSleeper", Vector3(0.28, 0.08, 1.25), Vector3(-5.1 + i * 0.8, 0.04, -2.55), _dark, Vector3.ZERO, false)
	kit.box("SocketBase", Vector3(2.7, 0.55, 2.8), Vector3(4.25, 0.27, -4.95), _paint)
	kit.box("SocketRailL", Vector3(0.14, 0.18, 2.35), Vector3(3.25, 0.62, -4.5), _amber, Vector3.ZERO, false)
	kit.box("SocketRailR", Vector3(0.14, 0.18, 2.35), Vector3(5.25, 0.62, -4.5), _amber, Vector3.ZERO, false)
	kit.box("SocketBack", Vector3(2.4, 2.2, 0.45), Vector3(4.25, 1.55, -6.3), _dark)
	kit.box("SocketContacts", Vector3(1.1, 0.85, 0.15), Vector3(4.25, 1.45, -6.02), _cyan, Vector3.ZERO, false)
	kit.box("SocketLampA", Vector3(0.14, 0.14, 0.05), Vector3(3.10, 2.2, -6.02), _amber, Vector3.ZERO, false)
	kit.box("SocketLampB", Vector3(0.14, 0.14, 0.05), Vector3(5.40, 2.2, -6.02), _cyan, Vector3.ZERO, false)
	kit.box("WinchBase", Vector3(0.62, 1.20, 0.72), Vector3(1.95, 0.60, -5.65), _paint)
	kit.handwheel("WinchWheel", Vector3(2.15, 1.42, -5.65), 0.38, _amber, 0.0)
	kit.box("WinchDrum", Vector3(0.40, 0.34, 0.40), Vector3(2.18, 1.45, -5.40), _dark, Vector3.ZERO, false)
	_sign_label("POWER SOCKET A-2  /  导轨容差 ±0.45 m", Vector3(4.25, 2.75, -6.18), 31, Color(0.90, 0.70, 0.30), 0.0030)
	# power cable snakes from the socket into the wall
	kit.pipe("PowerCableA", [Vector3(5.2, 0.9, -6.35), Vector3(5.6, 0.7, -7.2), Vector3(5.6, 1.2, -8.8), Vector3(5.6, 3.5, -9.8)], 0.08, Act1MatLib.flat(Color(0.03, 0.035, 0.03), 0.9))
	# a few pushable crates provide physical obstacles and readable clutter
	_spawn_pushable("PowerCrate", Vector3(-3.6, 0.5, -7.1), Vector3(0.9, 0.9, 0.9), 18.0, Color(0.35, 0.30, 0.18), false)
	_spawn_pushable("PowerCrate2", Vector3(-2.5, 0.4, -7.4), Vector3(0.75, 0.75, 0.75), 14.0, Color(0.26, 0.31, 0.25), false)


func _build_ventilation_hall() -> void:
	# shell
	kit.box("VentFloorNorth", Vector3(24, 0.5, 9.0), Vector3(0, -0.25, -16.5), _dark)
	kit.box("VentFloorSouth", Vector3(24, 0.5, 6.0), Vector3(0, -0.25, -34.0), _dark)
	kit.box("VentFloorWest", Vector3(8.0, 0.5, 10.0), Vector3(-8.0, -0.25, -26.0), _dark)
	kit.box("VentFloorEast", Vector3(7.0, 0.5, 10.0), Vector3(8.5, -0.25, -26.0), _dark)
	kit.box("PitFloor", Vector3(9.0, 0.5, 10.0), Vector3(0.5, PIT_Y - 0.25, -26.0), _dark)
	for w in [Vector3(-4.0, 0, -26), Vector3(5.0, 0, -26)]:
		kit.box("PitWall", Vector3(0.45, 3.6, 10.0), Vector3(w.x, -1.8, w.z), _concrete_mat)
	for z in [-21.0, -31.0]:
		kit.box("PitEndWall", Vector3(9.0, 3.6, 0.45), Vector3(0.5, -1.8, z), _concrete_mat)
	kit.box("VentCeil", Vector3(24.0, 0.4, 25.0), Vector3(0, 9.4, -25.5), _paint, Vector3.ZERO, false)
	kit.box("VentWallBoundL", Vector3(0.5, 9.4, 25.0), Vector3(-11.9, 4.7, -25.5), _rock_mat)
	kit.box("VentWallBoundR", Vector3(0.5, 9.4, 25.0), Vector3(11.9, 4.7, -25.5), _paint)
	kit.box("VentWallFaceL", Vector3(0.3, 9.0, 25.0), Vector3(-11.35, 4.5, -25.5), _rock_mat)
	kit.box("VentWallFaceR", Vector3(0.3, 9.0, 25.0), Vector3(11.35, 4.5, -25.5), _paint)
	# layered rock face is authored as the wall surface itself, then broken up by
	# structural ribs, cable trays and pipe runs. The imported outcrop shards are
	# kept outside the play volume so they cannot obscure the fan or cut the path.
	for z in [-14.8, -19.5, -24.0, -28.5, -33.0, -36.0]:
		for x in [-11.8, 11.8]:
			kit.box("VentRib", Vector3(0.35, 9.0, 0.5), Vector3(x, 4.5, z), _steel, Vector3.ZERO, false)
		kit.box("VentTie", Vector3(23.6, 0.32, 0.42), Vector3(0, 8.9, z), _steel, Vector3.ZERO, false)
	# safety lines and grated floor markings
	for x in [-8.8, 8.4]:
		kit.box("SafetyLine", Vector3(0.18, 0.03, 22.0), Vector3(x, 0.02, -25.5), _hazard, Vector3.ZERO, false)
	for i in range(12):
		kit.box("FloorGrate", Vector3(0.05, 0.014, 1.8), Vector3(-10.2 + i * 1.85, 0.015, -33.0), _steel, Vector3.ZERO, false)
	# wall relief: buttresses, cable trays, warning placards, pipe runs
	for z in [-17.0, -25.0, -33.0]:
		for x in [-10.9, 10.9]:
			kit.box("WallButtress", Vector3(0.50, 8.2, 0.75), Vector3(x, 4.1, z), _dark, Vector3.ZERO, false)
			kit.box("WallPlate", Vector3(0.12, 1.4, 2.2), Vector3(x - 0.35 * signf(x), 3.4, z), _paint, Vector3.ZERO, false)
			kit.box("WallLamp", Vector3(0.12, 0.18, 0.6), Vector3(x - 0.5 * signf(x), 5.6, z), _cyan, Vector3.ZERO, false)
	kit.pipe("VentPipeW", [Vector3(-10.7, 6.8, -13.0), Vector3(-10.7, 6.8, -37.0)], 0.13, _steel)
	kit.pipe("VentPipeE", [Vector3(10.7, 6.4, -13.0), Vector3(10.7, 6.4, -37.0)], 0.10, _dark)
	for i in range(6):
		kit.box("CableTrayBracket", Vector3(0.5, 0.08, 0.8), Vector3(-10.65, 7.3, -15.0 - i * 4.0), _dark, Vector3.ZERO, false)
	# non-blocking boulders on the pit floor keep the cave read without crossing
	# the catwalk or the fan intake
	_rock("VentDebrisW", "res://act1/assets/rocks/knuckle_a.glb", Vector3(-9.2, 0.15, -34.0), 32, 0.62, false)
	_rock("VentDebrisE", "res://act1/assets/rocks/shelf_a.glb", Vector3(9.3, 0.10, -21.0), -60, 0.55, false)
	# catwalk and supports
	var cat_x := 2.35
	kit.box("CatwalkDeck", Vector3(2.85, 0.22, 13.8), Vector3(cat_x, CATWALK_Y, -26.8), _steel)
	kit.box("CatwalkLipW", Vector3(0.10, 0.32, 13.8), Vector3(cat_x - 1.42, CATWALK_Y + 0.12, -26.8), _hazard, Vector3.ZERO, false)
	kit.box("CatwalkLipE", Vector3(0.10, 0.32, 13.8), Vector3(cat_x + 1.42, CATWALK_Y + 0.12, -26.8), _hazard, Vector3.ZERO, false)
	for z in [-21.0, -24.0, -28.0, -32.5]:
		for x in [cat_x - 1.1, cat_x + 1.1]:
			kit.box("CatwalkPost", Vector3(0.20, CATWALK_Y, 0.20), Vector3(x, CATWALK_Y * 0.5, z), _steel, Vector3.ZERO, false)
		kit.beam("CatwalkBraceL", Vector3(cat_x - 1.1, 0.1, z), Vector3(cat_x + 1.1, CATWALK_Y - 0.3, z), 0.075, _steel)
		kit.beam("CatwalkBraceR", Vector3(cat_x + 1.1, 0.1, z), Vector3(cat_x - 1.1, CATWALK_Y - 0.3, z), 0.075, _steel)
	# east railing complete, west railing has a deliberately missing section at the fan outflow
	kit.railing(stage, Vector3(cat_x + 1.38, CATWALK_Y + 0.12, -20.0), Vector3(cat_x + 1.38, CATWALK_Y + 0.12, -33.7), 1.08)
	kit.railing(stage, Vector3(cat_x - 1.38, CATWALK_Y + 0.12, -20.0), Vector3(cat_x - 1.38, CATWALK_Y + 0.12, -26.9), 1.08)
	kit.railing(stage, Vector3(cat_x - 1.38, CATWALK_Y + 0.12, -31.1), Vector3(cat_x - 1.38, CATWALK_Y + 0.12, -33.7), 1.08)
	# grab rails including the dangerous gap edges
	for z in [-21.2, -23.6, -25.8, -31.6, -33.4]:
		var g := Act1GrabRail.new()
		g.stage = stage
		g.setup_rail("grab_%d" % int(-z * 10.0), Vector3(cat_x - 1.27, CATWALK_Y + 1.12, z), 1.25)
		g.position = Vector3(cat_x - 0.92, CATWALK_Y + 1.05, z)
		stage.add_child(g)
		stage.interactables[g.interaction_id] = g
	# access ramp to catwalk with visible grip bars and edge lighting
	kit.wedge_ramp("CatwalkRamp", cat_x, 2.6, -20.2, CATWALK_Y + 0.12, -15.3, 0.02, 0.18, Act1MatLib.painted_steel(Color(0.33, 0.39, 0.40)), true)
	for i in range(8):
		var t := float(i) / 8.0
		var z := lerpf(-15.6, -20.0, t)
		var y := lerpf(0.10, CATWALK_Y + 0.08, t)
		kit.box("RampCrossbar", Vector3(2.5, 0.045, 0.10), Vector3(cat_x, y + 0.03, z), _steel, Vector3.ZERO, false)
	kit.box("RampEdgeL", Vector3(0.08, 0.06, 4.7), Vector3(cat_x - 1.23, 1.78, -17.8), _cyan, Vector3(-0.45, 0, 0), false)
	kit.box("RampEdgeR", Vector3(0.08, 0.06, 4.7), Vector3(cat_x + 1.23, 1.78, -17.8), _amber, Vector3(-0.45, 0, 0), false)
	kit.railing(stage, Vector3(cat_x - 1.32, 0.8, -19.9), Vector3(cat_x - 1.32, CATWALK_Y + 1.15, -20.2), 1.0)
	kit.railing(stage, Vector3(cat_x + 1.32, 0.8, -19.9), Vector3(cat_x + 1.32, CATWALK_Y + 1.15, -20.2), 1.0)
	kit.spot(Vector3(2.35, 6.0, -17.2), Vector3(2.35, 1.6, -18.2), Color(0.38, 0.68, 0.82), 3.0, 10.0, 38.0, false)
	# lower pit ladders and self-rescue route
	for z in [-22.2, -30.0]:
		for i in range(9):
			kit.box("LadderRung", Vector3(1.2, 0.07, 0.07), Vector3(4.52, PIT_Y + 0.3 + i * 0.36, z), _amber, Vector3.ZERO, false)
		for x in [3.94, 5.10]:
			kit.box("LadderRail", Vector3(0.08, 3.4, 0.08), Vector3(x, PIT_Y + 1.7, z), _steel, Vector3.ZERO, false)
	# lower pit props, safety markings and the strap post
	kit.box("PitSafetyLine", Vector3(8.7, 0.03, 0.16), Vector3(0.5, PIT_Y + 0.02, -22.0), _hazard, Vector3.ZERO, false)
	kit.box("PitSafetyLine2", Vector3(8.7, 0.03, 0.16), Vector3(0.5, PIT_Y + 0.02, -30.0), _hazard, Vector3.ZERO, false)
	kit.pipe("PitSteamPipe", [Vector3(-3.8, PIT_Y + 1.1, -23.5), Vector3(-3.8, PIT_Y + 1.1, -30.0)], 0.11, _dark)
	# fan warning rail and approach deck
	kit.box("FanSafetyBase", Vector3(3.0, 0.35, 7.2), Vector3(8.8, 0.17, -27.0), _dark, Vector3.ZERO, false)
	kit.railing(stage, Vector3(9.20, 0.32, -23.5), Vector3(9.20, 0.32, -30.5), 1.05)
	_sign_label("V-07  /  MAIN VENTILATION  /  主通风大厅", Vector3(-3.5, 5.55, -12.15), 54, Color(0.47, 0.82, 0.88), 0.0046)
	_sign_label("DANGER  ·  ROTOR  ·  KEEP CLEAR", Vector3(7.2, 3.5, -23.8), 38, Color(1.0, 0.48, 0.16), 0.0036)
	# control gallery cabinets on the safe west side
	for i in range(3):
		kit.control_cabinet("VentCabinet_%d" % i, Vector3(-8.7, 0, -20.5 - i * 2.1), PI * 0.5, Vector3(1.25, 2.0, 0.8))
	kit.box("ControlDesk", Vector3(1.35, 0.85, 0.90), Vector3(-8.75, 0.43, -19.75), _paint)
	kit.box("DeskScreen", Vector3(0.80, 0.55, 0.05), Vector3(-8.75, 0.95, -20.22), Act1MatLib.energy(Color(0.12, 0.68, 0.8), 0.7, 0.25, 4.0), Vector3.ZERO, false)
	kit.handwheel("GovernorWheel", Vector3(-8.0, 1.3, -21.65), 0.44, _amber, 0)
	# strap post on the catwalk
	kit.box("StrapPost", Vector3(0.25, 1.3, 0.25), Vector3(cat_x + 1.20, CATWALK_Y + 0.65, -29.4), _amber)
	_sign_label("STRAP  ·  CARGO", Vector3(cat_x + 1.20, CATWALK_Y + 1.5, -29.4), 28, Color(0.94, 0.65, 0.25), 0.0028)
	# rescue winch on the catwalk north end
	kit.box("RescueWinchBase", Vector3(1.2, 0.8, 1.0), Vector3(0.95, CATWALK_Y + 0.5, -22.6), _paint)
	kit.box("RescueDrum", Vector3(0.55, 0.55, 0.55), Vector3(0.95, CATWALK_Y + 1.05, -22.6), _dark, Vector3.ZERO, false)
	kit.box("RescueHandle", Vector3(0.10, 0.9, 0.10), Vector3(1.45, CATWALK_Y + 1.1, -22.6), _amber, Vector3.ZERO, false)
	_sign_label("RESCUE WINCH  /  救援卷扬", Vector3(0.95, CATWALK_Y + 1.8, -22.6), 28, Color(0.95, 0.55, 0.25), 0.0028)
	# fan controls and damper lever
	kit.control_cabinet("FanStartCabinet", Vector3(-8.55, 0, -25.2), PI * 0.5, Vector3(1.35, 2.2, 0.85))
	kit.box("EmergencyPedestal", Vector3(0.55, 1.1, 0.55), Vector3(-9.1, 0.55, -27.2), _paint)
	kit.box("EmergencyButton", Vector3(0.30, 0.16, 0.30), Vector3(-9.1, 1.18, -27.2), _red, Vector3.ZERO, false)
	kit.control_cabinet("DamperCabinet", Vector3(8.8, 0, -31.8), -PI * 0.5, Vector3(1.25, 2.1, 0.8))
	kit.handwheel("DamperWheel", Vector3(8.0, 1.35, -31.5), 0.46, _amber, PI * 0.5)
	# warm work lamps and alarm beacons
	for p in [Vector3(-9.0, 4.0, -15.0), Vector3(-9.0, 4.0, -26.0), Vector3(-9.0, 3.4, -34.0)]:
		kit.box("WorkLamp", Vector3(0.24, 0.16, 0.55), p, _amber, Vector3.ZERO, false)
	for p in [Vector3(-6.5, 6.9, -16.8), Vector3(-6.5, 6.9, -30.5)]:
		kit.box("AlarmBeacon", Vector3(0.30, 0.24, 0.24), p, _red, Vector3.ZERO, false)


func _build_station() -> void:
	# tunnel and departure hall
	kit.box("StationFloor", Vector3(20.0, 0.5, 23.0), Vector3(0, -0.25, -49.0), _dark)
	kit.box("StationThreshold", Vector3(10.0, 0.5, 1.2), Vector3(0, -0.25, -37.2), _dark)
	kit.box("StationArchL", Vector3(1.0, 7.4, 0.8), Vector3(-5.2, 3.7, -37.5), _paint)
	kit.box("StationArchR", Vector3(1.0, 7.4, 0.8), Vector3(5.2, 3.7, -37.5), _paint)
	kit.box("StationArchTop", Vector3(11.4, 1.2, 0.8), Vector3(0, 6.9, -37.5), _paint)
	kit.box("StationArchHazard", Vector3(10.4, 0.35, 0.3), Vector3(0, 6.15, -37.0), _hazard, Vector3.ZERO, false)
	kit.box("StationCeil", Vector3(20.0, 0.4, 23.0), Vector3(0, 8.4, -49.0), _paint, Vector3.ZERO, false)
	kit.box("StationWallL", Vector3(0.45, 8.6, 23.0), Vector3(-10.0, 4.2, -49.0), _rock_mat)
	kit.box("StationWallR", Vector3(0.45, 8.6, 23.0), Vector3(10.0, 4.2, -49.0), _paint)
	kit.box("StationEndL", Vector3(4.4, 8.6, 0.45), Vector3(-7.6, 4.2, -60.5), _rock_mat)
	kit.box("StationEndR", Vector3(4.4, 8.6, 0.45), Vector3(7.6, 4.2, -60.5), _rock_mat)
	kit.box("StationEndTop", Vector3(10.8, 3.0, 0.45), Vector3(0, 7.1, -60.5), _rock_mat)
	kit.box("TunnelFloor", Vector3(11.2, 0.5, 27.0), Vector3(0, -0.25, -72.0), _dark)
	kit.box("TunnelWallL", Vector3(0.45, 6.2, 27.0), Vector3(-5.5, 3.1, -72.0), _rock_mat)
	kit.box("TunnelWallR", Vector3(0.45, 6.2, 27.0), Vector3(5.5, 3.1, -72.0), _paint)
	kit.box("TunnelCeil", Vector3(11.2, 0.4, 27.0), Vector3(0, 6.4, -72.0), _paint, Vector3.ZERO, false)
	for z in [-39.6, -43.0, -47.0, -51.0, -55.0]:
		kit.box("StationRib", Vector3(19.4, 0.32, 0.42), Vector3(0, 8.1, z), _steel, Vector3.ZERO, false)
		for x in [-9.4, 9.4]:
			kit.box("StationPost", Vector3(0.35, 8.0, 0.5), Vector3(x, 4.0, z), _steel, Vector3.ZERO, false)
	# rail pair, sleepers and tunnel portal
	for x in [-1.15, 1.15]:
		kit.box("StationRail", Vector3(0.14, 0.18, 46.0), Vector3(x, 0.21, -60.0), _rail_mat, Vector3.ZERO, false)
	for i in range(52):
		kit.box("StationSleeper", Vector3(3.1, 0.11, 0.22), Vector3(0, 0.06, -38.0 - i * 0.82), _dark, Vector3.ZERO, false)
	kit.box("TunnelLintel", Vector3(11.8, 1.2, 1.2), Vector3(0, 6.2, -58.7), _paint)
	kit.box("TunnelHazard", Vector3(11.4, 0.45, 0.35), Vector3(0, 5.35, -58.1), _hazard, Vector3.ZERO, false)
	for x in [-5.9, 5.9]:
		kit.box("TunnelJamb", Vector3(0.9, 6.8, 1.3), Vector3(x, 3.4, -58.7), _paint)
	_sign_label("TRACK 01  /  DEEP MINE  /  深层矿区", Vector3(0, 7.0, -58.0), 46, Color(0.92, 0.66, 0.26), 0.0042)
	# boarding platform aligned with the V2.3 deck (1.42 m)
	kit.box("Platform", Vector3(4.7, 1.52, 12.0), Vector3(7.2, 0.76, -47.2), _dark)
	kit.box("PlatformEdge", Vector3(0.20, 0.20, 12.0), Vector3(4.85, 1.56, -47.2), _hazard, Vector3.ZERO, false)
	kit.box("PlatformLip", Vector3(0.7, 0.35, 12.0), Vector3(4.55, 1.42, -47.2), _steel, Vector3.ZERO, false)
	kit.wedge_ramp("PlatformRamp", 7.2, 3.2, -38.45, 0.02, -41.20, 1.52, 0.18, _steel, true)
	kit.railing(stage, Vector3(9.55, 1.62, -41.2), Vector3(9.55, 1.62, -53.0), 1.05)
	kit.railing(stage, Vector3(4.92, 1.62, -41.2), Vector3(4.92, 1.62, -43.2), 1.05)
	kit.railing(stage, Vector3(4.92, 1.62, -50.8), Vector3(4.92, 1.62, -53.0), 1.05)
	# warm platform lighting
	for z in [-42.0, -47.0, -52.0]:
		kit.box("PlatformLamp", Vector3(2.2, 0.09, 0.22), Vector3(7.3, 7.5, z), _amber, Vector3.ZERO, false)
	_sign_label("DEPARTURE PLATFORM  /  发车站台", Vector3(7.4, 4.1, -40.0), 38, Color(0.92, 0.65, 0.28), 0.0036)
	# control pedestals on platform
	for i in range(2):
		kit.box("PlatformCabinet_%d" % i, Vector3(0.8, 1.2, 0.55), Vector3(7.5, 2.12, -50.0 - i * 4.2), _paint)
		kit.box("PlatformScreen_%d" % i, Vector3(0.52, 0.36, 0.04), Vector3(7.5, 2.42, -50.27 - i * 4.2), _cyan, Vector3.ZERO, false)
	# wheel chock and brake visuals (the chock is a real interaction body, the
	# wedge itself is non-colliding so removing it never leaves an invisible step)
	# MECHANICS-001D：止轮楔改为真实刚体（原先是无碰撞网格，按 E 直接隐藏）
	wheel_chock = Act1WheelChock.new()
	wheel_chock.setup(stage, Vector3(-5.62, 0.17, -46.8))
	kit.box("BrakePedestal", Vector3(0.6, 1.25, 0.55), Vector3(6.4, 2.15, -49.8), _paint)
	kit.box("BrakeLever", Vector3(0.10, 0.75, 0.10), Vector3(6.4, 2.75, -50.05), _amber, Vector3(0, 0, -0.35), false)
	# MECHANICS-001F：原先这里是两块装饰用的 "CargoStrapBox/CargoStrap" 网格
	# （货箱摆在站台上、固定带只是一根悬空细条）。本轮删除，改为矿车上的真实
	# 货箱刚体 + 四点锚点 + 两条交叉张力带（见 Act1CargoRig）。
	# lamps into the tunnel
	for i in range(7):
		var z := -54.0 - i * 5.0
		kit.box("TunnelLamp", Vector3(0.22, 0.18, 0.7), Vector3(-4.3 if i % 2 == 0 else 4.3, 4.8, z), _cyan, Vector3.ZERO, false)
		kit.box("TunnelTie", Vector3(0.18, 4.2, 0.18), Vector3(-4.3 if i % 2 == 0 else 4.3, 2.4, z), _steel, Vector3.ZERO, false)
	# rock edges framing the tunnel mouth
	_rock("TunnelRockL", "res://act1/assets/rocks/thrust_a.glb", Vector3(-10.2, 2.0, -58.5), 5, 1.7, true)
	_rock("TunnelRockR", "res://act1/assets/rocks/knuckle_a.glb", Vector3(10.0, 2.5, -58.5), 176, 1.8, true)


## MECHANICS-001A：电源模块改成**导轨上的真实刚体**。
## 导轨从推车停放位（RAIL_Z）通向插座（SOCKET），模块沿它被绞盘真实牵引进插座。
## 原来模块是被 Tween 从车面直接插值到插座的（纯动画），本轮删除该行为。
## 坡面正交基：Y = 坡面法线（朝上）、Z = 行进方向、X = 宽度
func _ramp_basis(seg: Vector3) -> Basis:
	var z_ax: Vector3 = seg.normalized()
	var n: Vector3 = z_ax.cross(Vector3.RIGHT).normalized()
	if n.y < 0.0:
		n = -n
	return Basis(n.cross(z_ax).normalized(), n, z_ax)


func _build_power_module_rail() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.35, 0.38)
	mat.roughness = 0.62
	mat.metallic = 0.35
	var core_mat: StandardMaterial3D = StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.30, 0.72, 0.78)
	core_mat.roughness = 0.45
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.20, 0.55, 0.60)
	core_mat.emission_energy_multiplier = 0.6

	var z_from: float = Act1PowerCart.RAIL_Z
	var z_mid: float = (z_from + SOCKET.z) * 0.5
	var span: float = absf(SOCKET.z - z_from) + 1.1
	var shelf_y: float = SOCKET.y - 0.55

	# 导轨台面（静态）
	var shelf: StaticBody3D = StaticBody3D.new()
	shelf.name = "PowerModuleRail"
	shelf.collision_layer = 1
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = Vector3(1.5, 0.10, span)
	cs.shape = bs
	shelf.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = mat
	shelf.add_child(mi)
	shelf.position = Vector3(SOCKET.x, shelf_y, z_mid)
	stage.add_child(shelf)

	# 两侧护栏，防止模块滑偏
	for sx: float in [-1.0, 1.0]:
		var rail: StaticBody3D = StaticBody3D.new()
		rail.name = "PowerModuleRailSide"
		rail.collision_layer = 1
		var rcs: CollisionShape3D = CollisionShape3D.new()
		var rbs: BoxShape3D = BoxShape3D.new()
		rbs.size = Vector3(0.08, 0.34, span)
		rcs.shape = rbs
		rail.add_child(rcs)
		var rmi: MeshInstance3D = MeshInstance3D.new()
		var rbm: BoxMesh = BoxMesh.new()
		rbm.size = rbs.size
		rmi.mesh = rbm
		rmi.material_override = mat
		rail.add_child(rmi)
		rail.position = Vector3(SOCKET.x + sx * 0.78, shelf_y + 0.17, z_mid)
		stage.add_child(rail)

	# 插座端挡块：模块滑到位后靠它停住
	var stop: StaticBody3D = StaticBody3D.new()
	stop.name = "PowerSocketStop"
	stop.collision_layer = 1
	var scs: CollisionShape3D = CollisionShape3D.new()
	var sbs: BoxShape3D = BoxShape3D.new()
	sbs.size = Vector3(1.5, 0.9, 0.12)
	scs.shape = sbs
	stop.add_child(scs)
	stop.position = Vector3(SOCKET.x, shelf_y + 0.5, SOCKET.z - 0.62)
	stage.add_child(stop)

	# 真实模块刚体（60 kg）
	var mod: RigidBody3D = RigidBody3D.new()
	mod.name = "PowerModuleBody"
	mod.mass = 60.0
	mod.gravity_scale = 1.0
	mod.linear_damp = 0.30
	mod.angular_damp = 0.8
	mod.continuous_cd = true
	mod.collision_layer = 4
	mod.collision_mask = 0xFFFFFFFF   # 必须含推车层(16)与玩家/世界层
	# 导轨面摩擦要低于绞盘牵引力，否则 60 kg 模块推不动
	var mmat: PhysicsMaterial = PhysicsMaterial.new()
	mmat.friction = 0.22
	mmat.bounce = 0.0
	mod.physics_material_override = mmat
	var mcs: CollisionShape3D = CollisionShape3D.new()
	var mbs: BoxShape3D = BoxShape3D.new()
	mbs.size = Vector3(1.10, 1.00, 1.02)
	mcs.shape = mbs
	mod.add_child(mcs)
	var mmi: MeshInstance3D = MeshInstance3D.new()
	var mbm: BoxMesh = BoxMesh.new()
	mbm.size = Vector3(1.22, 1.02, 1.10)
	mmi.mesh = mbm
	mmi.material_override = mat
	mod.add_child(mmi)
	var mmc: MeshInstance3D = MeshInstance3D.new()
	var mcm: BoxMesh = BoxMesh.new()
	mcm.size = Vector3(1.02, 0.78, 0.90)
	mmc.mesh = mcm
	mmc.material_override = core_mat
	mod.add_child(mmc)
	stage.add_child(mod)
	# MECHANICS-001B：同一件模块初始停在推车货台上，随车运到对接口
	mod.global_position = power_cart.global_transform * Vector3(0.0, 1.86, 0.0)

	# 滑槽：从货台面接到导轨面（正交基：Y=法线、Z=行进、X=宽度）
	var chute: StaticBody3D = StaticBody3D.new()
	chute.name = "PowerModuleChute"
	chute.collision_layer = 1
	chute.collision_mask = 0
	var ch_a: Vector3 = Vector3(SOCKET.x, 1.33, -3.00)
	var ch_b: Vector3 = Vector3(SOCKET.x, 0.78, -4.10)
	var ch_seg: Vector3 = ch_b - ch_a
	var ch_cs: CollisionShape3D = CollisionShape3D.new()
	var ch_bs: BoxShape3D = BoxShape3D.new()
	ch_bs.size = Vector3(1.45, 0.10, ch_seg.length() + 0.12)
	ch_cs.shape = ch_bs
	chute.add_child(ch_cs)
	stage.add_child(chute)
	chute.transform = Transform3D(_ramp_basis(ch_seg), (ch_a + ch_b) * 0.5)
	power_module = mod
	power_cart.bind_module(mod)

	# MECHANICS-001B-R2 实体旋转锁爪。
	# 实测结论：Godot 4.7.2 + Jolt 下 HingeJoint3D 的自由转动轴是关节 basis 的 **Z 列**
	# （绕 basis.x 加冲量毫无响应、绕 basis.z 加冲量立刻得到 ω），因此用单位基，
	# 自由轴 = 世界 +Z（水平），锁爪臂绕它向下摆、压在模块顶上。
	var bracket: StaticBody3D = StaticBody3D.new()
	bracket.name = "ClampBracket"
	bracket.collision_layer = 1
	bracket.collision_mask = 0
	var bcs: CollisionShape3D = CollisionShape3D.new()
	var bbs: BoxShape3D = BoxShape3D.new()
	bbs.size = Vector3(0.16, 0.62, 0.16)
	bcs.shape = bbs
	bracket.add_child(bcs)
	stage.add_child(bracket)
	bracket.global_position = Vector3(SOCKET.x + 1.02, SOCKET.y + 1.08, SOCKET.z)

	var jaw: RigidBody3D = RigidBody3D.new()
	jaw.name = "ClampJaw"
	jaw.mass = 25.0
	jaw.can_sleep = false
	jaw.angular_damp = 1.4
	jaw.linear_damp = 0.6
	jaw.collision_layer = 4
	jaw.collision_mask = 1 | 2 | 4
	var jcs: CollisionShape3D = CollisionShape3D.new()
	var jbs: BoxShape3D = BoxShape3D.new()
	jbs.size = Vector3(0.92, 0.20, 0.90)
	jcs.shape = jbs
	jcs.position = Vector3(-0.62, 0.0, 0.0)
	jaw.add_child(jcs)

	var jmi: MeshInstance3D = MeshInstance3D.new()
	var jbm: BoxMesh = BoxMesh.new()
	jbm.size = jbs.size
	jmi.mesh = jbm
	jmi.position = jcs.position
	var jmat: StandardMaterial3D = StandardMaterial3D.new()
	jmat.albedo_color = Color(0.72, 0.44, 0.12)
	jmi.material_override = jmat
	jaw.add_child(jmi)

	# 下挂钩：挂在臂的 +Z 边缘**外侧**（世界 z≈−4.45，模块后侧面在 −4.51），
	# 高度覆盖模块上部。闭合时落到该位置，模块沿 +Z 一移动就被实体挡住 —— 几何阻挡，不靠摩擦。
	var hcs: CollisionShape3D = CollisionShape3D.new()
	var hbs: BoxShape3D = BoxShape3D.new()
	hbs.size = Vector3(0.46, 0.72, 0.10)
	hcs.shape = hbs
	hcs.position = Vector3(-0.66, -0.36, 0.52)
	jaw.add_child(hcs)
	var hmi: MeshInstance3D = MeshInstance3D.new()
	var hbm: BoxMesh = BoxMesh.new()
	hbm.size = hbs.size
	hmi.mesh = hbm
	hmi.position = hcs.position
	var hmat: StandardMaterial3D = StandardMaterial3D.new()
	hmat.albedo_color = Color(0.88, 0.58, 0.16)
	hmi.material_override = hmat
	jaw.add_child(hmi)

	stage.add_child(jaw)
	jaw.global_position = bracket.global_position
	# 打开位预先抬到 −0.34 rad：此时挂钩抬到模块顶面以上，完全让开
	jaw.rotation = Vector3(0.0, 0.0, -1.00)   # 打开位抬到 57°，保证 1 m 高的模块能从下方通过
	jaw.sleeping = false
	jaw.contact_monitor = true
	jaw.max_contacts_reported = 4
	jaw.add_collision_exception_with(bracket)

	var hinge: HingeJoint3D = HingeJoint3D.new()
	hinge.name = "ClampHinge"
	hinge.transform = Transform3D(Basis(), stage.to_local(bracket.global_position))
	stage.add_child(hinge)
	hinge.node_a = hinge.get_path_to(bracket)
	hinge.node_b = hinge.get_path_to(jaw)
	hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	hinge.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	# 初始即由马达保持水平（0 rad）：重力会把它拉下去，必须通电抱死
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 420.0)
	power_cart.bind_clamp(jaw, hinge)


func _build_controls() -> void:	# entry latch and door handle are created by their rigs; other controls here
	socket_clamp = stage.call("make_interactable", "power_clamp", "E 锁定电源模块机械夹", Vector3(3.15, 1.72, -4.75), Vector3(0.55, 0.70, 0.60), false) as Act1Interactable
	socket_clamp.prompt_callable = Callable(stage, "_power_clamp_prompt")
	socket_clamp.add_focus_marker(0.22)
	var transfer := stage.call("make_interactable", "power_winch", "E 操作导轨绞盘 · 将模块移入插座", Vector3(2.15, 1.50, -5.65), Vector3(0.70, 1.0, 0.70), false) as Act1Interactable
	transfer.add_focus_marker(0.22)
	# fan machine interlocks
	var lock := stage.call("make_interactable", "rotor_lock", "E 拔出转子机械锁销", Vector3(7.65, 1.15, -23.55), Vector3(0.7, 1.15, 0.65), false) as Act1Interactable
	lock.prompt_callable = Callable(stage, "_rotor_lock_prompt")
	lock.add_focus_marker(0.22)
	var coupling := stage.call("make_interactable", "coupling", "E 接合风机传动联轴器", Vector3(8.15, 1.40, -29.05), Vector3(0.65, 1.25, 0.65), false) as Act1Interactable
	coupling.prompt_callable = Callable(stage, "_coupling_prompt")
	coupling.add_focus_marker(0.22)

	# MECHANICS-001C：转子锁销与传动联轴器改为真实刚体（真实位置决定状态）
	fan_interlock = Act1FanInterlock.new()
	fan_interlock.setup(stage, Vector3(6.85, 1.15, -23.55), Vector3(6.85, 1.40, -29.05))
	var start := stage.call("make_interactable", "start_fan", "E 拉动主启动手柄", Vector3(-7.82, 1.55, -25.2), Vector3(0.75, 1.1, 0.55), false) as Act1Interactable
	start.prompt_callable = Callable(stage, "_start_fan_prompt")
	start.add_focus_marker(0.22)
	var gov := stage.call("make_interactable", "governor", "E 调整风机调速器", Vector3(-8.0, 1.45, -21.65), Vector3(0.85, 0.9, 0.55), false) as Act1Interactable
	gov.prompt_callable = Callable(stage, "_governor_prompt")
	gov.add_focus_marker(0.22)
	var estop := stage.call("make_interactable", "emergency_stop", "X/E 紧急停机 · 立即卸掉风机力矩", Vector3(-9.1, 1.25, -27.2), Vector3(0.65, 0.55, 0.65), false) as Act1Interactable
	estop.add_focus_marker(0.22)
	var damper := stage.call("make_interactable", "damper", "E 切换双风道风门", Vector3(8.0, 1.45, -31.5), Vector3(0.85, 0.95, 0.55), false) as Act1Interactable
	damper.add_focus_marker(0.22)
	strap_control = stage.call("make_interactable", "secure_crate", "E 用固定带锁住仪器箱", Vector3(3.72, CATWALK_Y + 1.25, -29.4), Vector3(0.55, 0.8, 0.55), false) as Act1Interactable
	strap_control.add_focus_marker(0.20)
	ladder_anchor = stage.call("make_interactable", "self_rescue", "E 沿维护梯自救返回栈桥", Vector3(4.50, PIT_Y + 1.25, -22.2), Vector3(1.4, 2.4, 1.1), false) as Act1Interactable
	ladder_anchor.add_focus_marker(0.22)
	winch_console = stage.call("make_interactable", "rescue_winch", "E 操作救援卷扬 · 拉起倒下的队友", Vector3(1.45, CATWALK_Y + 1.13, -22.4), Vector3(0.55, 1.0, 0.7), false) as Act1Interactable
	winch_console.add_focus_marker(0.22)
	var chock := stage.call("make_interactable", "chock", "E 移走车轮止轮楔", Vector3(-5.62, 0.98, -46.55), Vector3(0.85, 0.7, 1.1), false) as Act1Interactable
	chock.prompt_callable = Callable(stage, "_chock_prompt")
	chock.add_focus_marker(0.20)
	var brake := stage.call("make_interactable", "parking_brake", "E 释放机械停车制动", Vector3(6.4, 2.45, -49.28), Vector3(0.7, 1.0, 0.55), false) as Act1Interactable
	brake.prompt_callable = Callable(stage, "_parking_brake_prompt")
	brake.add_focus_marker(0.20)

	# MECHANICS-001E-R2：真实停车制动（径向销爪 + 齿圈鼓），置于交互点后方
	parking_brake = Act1ParkingBrake.new()
	parking_brake.setup(stage, Vector3(6.9, 2.4, -48.9))   # 经形状查询确认的净空位置
	# MECHANICS-001F：货舱交互点（cargo / cargo_latch）由 Act1CargoRig 自己建在
	# 矿车货台棘轮上并注册进 stage.interactables，这里不再创建。


func _build_obstructions() -> void:
	entry_obstruction = _spawn_pushable("EntryObstruction", Vector3(0.0, 0.72, 9.05), Vector3(3.6, 1.4, 0.9), 54.0, Color(0.36, 0.25, 0.14), true)
	entry_obstruction.name = "CollapsedMaintenanceGantry"
	var lever := Act1Interactable.new()
	lever.setup("shove_gantry", "E 用力推开压住门轨的维护架", Vector3(3.0, 0.55, 0.7))
	lever.stage = stage
	lever.position = Vector3(0, 0.62, 0.76)
	entry_obstruction.add_child(lever)
	lever.add_focus_marker(0.25)
	stage.interactables[lever.interaction_id] = lever
	rail_obstacle = _spawn_pushable("RailObstacle", Vector3(-1.0, 0.46, -2.55), Vector3(1.8, 0.85, 1.1), 22.0, Color(0.34, 0.28, 0.16), false)
	rail_obstacle.name = "FallenRailBracket"
	var kick := Act1Interactable.new()
	kick.setup("rail_shove", "E 把断裂导轨支架踢出推车轨道", Vector3(1.8, 0.8, 0.7))
	kick.stage = stage
	kick.position = Vector3(0, 0.4, 0.62)
	rail_obstacle.add_child(kick)
	kick.add_focus_marker(0.22)
	stage.interactables[kick.interaction_id] = kick


func _spawn_pushable(name: String, pos: Vector3, size: Vector3, mass: float, color: Color, lock_rotation: bool) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = name
	body.position = pos
	body.mass = mass
	body.collision_layer = 4
	body.collision_mask = 1 | 2 | 4 | 16
	body.lock_rotation = lock_rotation
	body.linear_damp = 6.0
	body.angular_damp = 6.0
	body.add_to_group("pushable")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Act1MatLib.painted_steel(color)
	body.add_child(mi)
	for side in [-1, 1]:
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(size.x * 1.002, 0.12, size.z * 1.01)
		stripe.mesh = sm
		stripe.material_override = _hazard
		stripe.position.y = side * size.y * 0.28
		body.add_child(stripe)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	stage.add_child(body)
	return body


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "MoonSun"
	sun.rotation_degrees = Vector3(-32, -28, 0)
	sun.light_color = Color(0.53, 0.65, 0.82)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	sun.directional_shadow_max_distance = 30.0
	stage.add_child(sun)
	# Practicals are deliberately limited: GL Compatibility pays a per-light pass
	# over the dense station geometry. Emissive strips carry the rest of the read.
	# exterior
	kit.spot(Vector3(-4.2, 5.0, 10.4), Vector3(0, 1.3, 18), Color(0.95, 0.64, 0.32), 5.0, 22.0, 50.0, false)
	# entry
	kit.omni(Vector3(0, 5.2, 6.3), Color(0.40, 0.72, 0.85), 3.8, 11.0, false)
	kit.omni(Vector3(2.8, 2.4, 9.0), Color(1.0, 0.50, 0.18), 2.1, 5.5, false)
	# power room
	kit.omni(Vector3(0, 4.1, -3.2), Color(0.30, 0.72, 0.84), 5.2, 15.0, false)
	kit.omni(Vector3(-6.8, 2.3, -8.9), Color(1.0, 0.47, 0.18), 2.8, 7.0, false)
	kit.omni(Vector3(4.2, 2.8, -5.1), Color(0.22, 0.78, 0.88), 2.8, 7.0, false)
	# ventilation hall: one shadow source for the gantry, rest is practical spill
	kit.spot(Vector3(5.8, 8.6, -22.0), Vector3(1.8, 0.0, -27.0), Color(0.45, 0.70, 0.88), 6.0, 30.0, 58.0, true)
	kit.omni(Vector3(-8.0, 3.3, -22.0), Color(1.0, 0.54, 0.22), 4.0, 12.0, false)
	kit.spot(Vector3(4.2, 5.2, -24.0), Vector3(11.15, 5.0, -27.0), Color(0.40, 0.72, 0.88), 6.5, 22.0, 52.0, false)
	kit.omni(Vector3(1.5, PIT_Y + 2.0, -26.0), Color(0.25, 0.60, 0.70), 2.0, 10.0, false)
	# departure station
	kit.spot(Vector3(0, 7.6, -44.0), Vector3(0, 0.0, -50.0), Color(0.92, 0.58, 0.28), 6.2, 30.0, 55.0, false)
	kit.omni(Vector3(7.0, 3.3, -45.0), Color(1.0, 0.60, 0.28), 4.0, 11.0, false)


func _build_dust() -> void:
	kit.dust("EntryDust", Vector3(0, 2.4, 14.0), Vector3(8, 3, 10), 50, Color(0.64, 0.74, 0.82, 0.25), 0.025)
	kit.dust("VentDust", Vector3(0, 4.0, -25.0), Vector3(11, 4, 11), 110, Color(0.58, 0.73, 0.82, 0.22), 0.028)
	kit.dust("PitDust", Vector3(1.0, PIT_Y + 1.8, -26.0), Vector3(4, 2, 8), 40, Color(0.50, 0.64, 0.68, 0.18), 0.022)
	kit.dust("StationDust", Vector3(0, 4.0, -48.0), Vector3(9, 4, 10), 80, Color(0.72, 0.66, 0.55, 0.18), 0.024)


func _rock(name: String, path: String, pos: Vector3, yaw: float, scale: float, collide: bool) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return Node3D.new()
	var n := packed.instantiate() as Node3D
	n.name = name
	n.position = pos
	n.rotation_degrees.y = yaw
	n.scale = Vector3.ONE * scale
	stage.add_child(n)
	_apply_rock_material(n)
	# Rock GLBs are large outcrop shells, not collision primitives. Their world
	# AABBs can swallow the spawn or the catwalk, so the station uses authored
	# retaining-wall / floor colliders and keeps the rock as cladding.
	return n


func _apply_rock_material(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_override = _rock_mat
		m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _sign_label(text: String, pos: Vector3, size: int, color: Color, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = _font
	label.font_size = size
	label.pixel_size = pixel * 1.15
	label.outline_size = 12
	label.modulate = color
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	stage.add_child(label)
	return label


func reset_static_obstacles() -> void:
	if entry_obstruction != null:
		entry_obstruction.global_position = Vector3(0.0, 0.72, 9.05)
		entry_obstruction.linear_velocity = Vector3.ZERO
		entry_obstruction.angular_velocity = Vector3.ZERO
	if rail_obstacle != null:
		rail_obstacle.global_position = Vector3(-1.0, 0.46, -2.55)
		rail_obstacle.linear_velocity = Vector3.ZERO
		rail_obstacle.angular_velocity = Vector3.ZERO