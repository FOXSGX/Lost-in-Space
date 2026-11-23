class_name R04LevelBuilder
extends RefCounted
## Builds the whole playable cave. Geometry is authored here so the project has
## one readable source of spatial truth; gameplay nodes are returned to Game.

const CRYSTAL_DIR := "res://assets/crystals/"
const ROCK_DIR := "res://assets/rocks/"

const BLADE_CYAN := "res_crys_blade_cyan_a_lod0.glb"
const BLADE_VIOLET := "res_crys_blade_violet_a_lod0.glb"
const CLUSTER_ENV02 := "res_crys_cluster_env02_a_lod0.glb"
const CLUSTER_MID := "res_crys_cluster_mid_a_lod0.glb"
const CLUSTER_WEST := "res_crys_cluster_west_a_lod0.glb"

const ROCK_THRUST := "res_rock_thrust_a_lod0.glb"
const ROCK_SHELF := "res_rock_shelf_a_lod0.glb"
const ROCK_CAP := "res_rock_cap_a_lod0.glb"
const ROCK_KNUCKLE := "res_rock_knuckle_a_lod0.glb"
const ROCK_APRON := "res_rock_apron_a_lod0.glb"
const ROCK_TONGUE := "res_rock_tongue_a_lod0.glb"
const ROCK_LIP := "res_rock_lip_a_lod0.glb"
const ROCK_FISSURE := "res_rock_fissure_host_a_lod0.glb"
const ROCK_FLANK := "res_rock_flank_a_lod0.glb"

const CRYSTAL_CENTER_HEIGHT := 0.92
const PORTABLE_CENTER_HEIGHT := 0.75

const SPAWN := Vector3(0.0, 0.05, 6.0)
const HAMMER_POSITION := Vector3(0.0, 0.2, -3.4)

const BELL_BASE := Vector3(0.0, 0.62, -5.2)
const F1_BASE := Vector3(4.6, 0.55, -7.0)
const F2_BASE := Vector3(8.8, 1.0, -9.8)
const M1_BASE := Vector3(14.5, 2.6, -13.0)
const W1_BASE := Vector3(-4.6, 0.5, -7.2)
const W2_BASE := Vector3(-8.6, 0.7, -9.6)
const W3_BASE := Vector3(-15.0, 0.9, -14.4)
const M2_BASE := Vector3(-18.2, 0.55, -17.2)
const B1_POSITION := Vector3(-11.8, 0.0, -12.0)
const B2_POSITION := Vector3(-9.6, 0.0, -15.2)
const B3_POSITION := Vector3(-12.6, 3.4, -19.8)
const B4_POSITION := Vector3(-9.8, 3.4, -19.0)
const T2_BASE := Vector3(-9.0, 3.7, -23.2)
const M3_BASE := Vector3(-3.0, 0.6, -25.5)
const EXIT_GATE_POSITION := Vector3(3.2, 0.0, -25.0)
const CRYSTAL_A_SPAWN := Vector3(-17.0, 2.75, 3.0)
const CRYSTAL_B_SPAWN := Vector3(-16.8, 0.65, -12.5)

var _rock_material: ShaderMaterial
var _gravel_material: StandardMaterial3D
var _metal: StandardMaterial3D
var _dark_metal: StandardMaterial3D
var _rust: StandardMaterial3D
var _paint_yellow: StandardMaterial3D
var _paint_cream: StandardMaterial3D
var _wood: StandardMaterial3D
var _rock_point_cache: Dictionary = {}
var _rock_instance_index: int = 0


func build(root: Node3D) -> Dictionary:
	_rock_material = MaterialLibrary.rock()
	_gravel_material = _make_gravel_material()
	_metal = MaterialLibrary.metal(Color(0.31, 0.34, 0.37), 0.5, 0.8)
	_dark_metal = MaterialLibrary.metal(Color(0.12, 0.13, 0.145), 0.6, 0.55)
	_rust = MaterialLibrary.metal(Color(0.37, 0.21, 0.12), 0.82, 0.28)
	_paint_yellow = MaterialLibrary.painted(Color(0.84, 0.56, 0.10), 0.58)
	_paint_cream = MaterialLibrary.painted(Color(0.80, 0.76, 0.65), 0.72)
	_wood = MaterialLibrary.painted(Color(0.32, 0.24, 0.16), 0.9)

	var data: Dictionary = {}
	var environment_root: Node3D = Node3D.new()
	environment_root.name = "Environment"
	root.add_child(environment_root)
	_build_shell(environment_root)
	_build_platforms(environment_root)
	_build_decor_rocks(environment_root)
	_build_industrial_dressing(environment_root)
	_build_entrance_station(environment_root)
	_build_broken_path_cue(environment_root)
	_build_guide_fixtures(environment_root)
	_build_core_vista(environment_root)
	_build_ground_relief(environment_root)
	_build_atmosphere(environment_root)
	_build_lights(environment_root)

	var crystal_root: Node3D = Node3D.new()
	crystal_root.name = "CrystalNetwork"
	root.add_child(crystal_root)

	var model: ResonanceModel = ResonanceModel.new()
	var crystals: Dictionary = {}
	var crystal_parent: Node3D = Node3D.new()
	crystal_parent.name = "FixedCrystals"
	crystal_root.add_child(crystal_parent)

	var bell: EchoCrystal = _add_echo_crystal(crystal_parent, "bell", BELL_BASE, 0.72, "cyan", 180.0, true)
	crystals["bell"] = bell
	model.add_node("bell", bell.global_position + Vector3(0.0, CRYSTAL_CENTER_HEIGHT * 0.72, 0.0), Vector3.FORWARD, "hub", "hub", 7.2, 90.0)

	var f1: EchoCrystal = _add_echo_crystal(crystal_parent, "f1", F1_BASE, 0.62, "cyan", 0.0, false)
	var f2: EchoCrystal = _add_echo_crystal(crystal_parent, "f2", F2_BASE, 0.62, "cyan", 0.0, false)
	var m1: EchoCrystal = _add_echo_crystal(crystal_parent, "m1", M1_BASE, 1.35, "cyan", 180.0, true)
	m1.make_memory(1, "cyan")
	var w1: EchoCrystal = _add_echo_crystal(crystal_parent, "w1", W1_BASE, 0.62, "cyan", 0.0, false)
	var w2: EchoCrystal = _add_echo_crystal(crystal_parent, "w2", W2_BASE, 0.62, "cyan", 0.0, false)
	var w3: EchoCrystal = _add_echo_crystal(crystal_parent, "w3", W3_BASE, 0.62, "violet", 0.0, false)
	var m2: EchoCrystal = _add_echo_crystal(crystal_parent, "m2", M2_BASE, 2.0, "violet", 0.0, true)
	m2.make_memory(2, "violet")
	var t2: EchoCrystal = _add_echo_crystal(crystal_parent, "t2", T2_BASE, 0.62, "violet", 0.0, false)
	var m3: EchoCrystal = _add_echo_crystal(crystal_parent, "m3", M3_BASE, 2.6, "violet", 0.0, true)
	m3.make_memory(3, "violet")

	# Relay nodes exist from the start but stay disabled until a crystal is
	# physically seated in their cradle. Adding them before focus derivation
	# lets every axis use a real cradle position.
	_add_relay_node(model, "b1", B1_POSITION + Vector3(0.0, 1.30, 0.0))
	_add_relay_node(model, "b2", B2_POSITION + Vector3(0.0, 1.30, 0.0))
	_add_relay_node(model, "b3", B3_POSITION + Vector3(0.0, 1.30, 0.0))
	_add_relay_node(model, "b4", B4_POSITION + Vector3(0.0, 1.30, 0.0))

	for entry: Array in [
		["f1", f1, F1_BASE, 0.62], ["f2", f2, F2_BASE, 0.62], ["m1", m1, M1_BASE, 1.35],
		["w1", w1, W1_BASE, 0.62], ["w2", w2, W2_BASE, 0.62], ["w3", w3, W3_BASE, 0.62],
		["m2", m2, M2_BASE, 2.0], ["t2", t2, T2_BASE, 0.62], ["m3", m3, M3_BASE, 2.6],
	]:
		var id: String = str(entry[0])
		var crystal: EchoCrystal = entry[1] as EchoCrystal
		var base: Vector3 = entry[2] as Vector3
		var scale_value: float = float(entry[3])
		crystals[id] = crystal
		var radius_value: float = 7.4 if id in ["f2", "m2", "t2"] else 6.8
		model.add_node(id, base + Vector3(0.0, CRYSTAL_CENTER_HEIGHT * scale_value, 0.0), Vector3.FORWARD, _channel_for(id), "memory" if crystal.is_memory else "fixed", radius_value)

	# Focus axes are derived from the actual layout, not hand-written angles.
	_set_focus(model, crystals, "f1", "f2")
	_set_focus(model, crystals, "f2", "m1")
	_set_focus(model, crystals, "w1", "w2")
	_set_focus(model, crystals, "w2", "b1")
	_set_focus(model, crystals, "w3", "m2")
	_set_focus(model, crystals, "m2", "b3")
	_set_focus(model, crystals, "t2", "m3")
	_apply_yaw(crystals["f1"], _yaw_to(model.get_position("f1"), model.get_position("f2")))
	_apply_yaw(crystals["f2"], _yaw_to(model.get_position("f2"), model.get_position("m1")))
	_apply_yaw(crystals["w1"], _yaw_to(model.get_position("w1"), model.get_position("w2")))
	_apply_yaw(crystals["w2"], _yaw_to(model.get_position("w2"), B1_POSITION + Vector3(0.0, 1.3, 0.0)))
	_apply_yaw(crystals["w3"], _yaw_to(model.get_position("w3"), model.get_position("m2")))
	_apply_yaw(crystals["m2"], _yaw_to(model.get_position("m2"), B3_POSITION + Vector3(0.0, 1.3, 0.0)))
	_apply_yaw(crystals["t2"], _yaw_to(model.get_position("t2"), model.get_position("m3")))
	model.set_focus("f1", crystals["f1"].focus_direction())
	model.set_focus("f2", crystals["f2"].focus_direction())
	model.set_focus("w1", crystals["w1"].focus_direction())
	model.set_focus("w2", crystals["w2"].focus_direction())
	model.set_focus("w3", crystals["w3"].focus_direction())
	model.set_focus("m2", crystals["m2"].focus_direction())
	model.set_focus("t2", crystals["t2"].focus_direction())

	# ---- carryable crystals and their cradles -----------------------------
	var portable_root: Node3D = Node3D.new()
	portable_root.name = "PortableCrystals"
	root.add_child(portable_root)
	var crystal_a: PortableCrystal = PortableCrystal.new()
	crystal_a.name = "CrystalA"
	crystal_a.position = CRYSTAL_A_SPAWN
	portable_root.add_child(crystal_a)
	crystal_a.build("crystal_a", CRYSTAL_DIR + CLUSTER_ENV02, "cyan", 0.58)
	crystal_a.set_spawn(CRYSTAL_A_SPAWN, 90.0)

	var crystal_b: PortableCrystal = PortableCrystal.new()
	crystal_b.name = "CrystalB"
	crystal_b.position = CRYSTAL_B_SPAWN
	portable_root.add_child(crystal_b)
	crystal_b.build("crystal_b", CRYSTAL_DIR + CLUSTER_MID, "violet", 0.66)
	crystal_b.set_spawn(CRYSTAL_B_SPAWN, 0.0)

	var cradle_root: Node3D = Node3D.new()
	cradle_root.name = "Cradles"
	root.add_child(cradle_root)
	var cradles: Dictionary = {}
	cradles["b1"] = _add_cradle(cradle_root, "b1", B1_POSITION, _yaw_to(B1_POSITION + Vector3(0.0, 1.3, 0.0), W3_BASE + Vector3(0.0, CRYSTAL_CENTER_HEIGHT * 0.9, 0.0)), "w3", model)
	cradles["b2"] = _add_cradle(cradle_root, "b2", B2_POSITION, 90.0, "w3", model)
	cradles["b3"] = _add_cradle(cradle_root, "b3", B3_POSITION, _yaw_to(B3_POSITION + Vector3(0.0, 1.3, 0.0), T2_BASE + Vector3(0.0, CRYSTAL_CENTER_HEIGHT * 0.95, 0.0)), "t2", model)
	cradles["b4"] = _add_cradle(cradle_root, "b4", B4_POSITION, _yaw_to(B4_POSITION + Vector3(0.0, 1.3, 0.0), T2_BASE + Vector3(0.0, CRYSTAL_CENTER_HEIGHT * 0.95, 0.0)), "t2", model)

	# ---- hammer ------------------------------------------------------------
	var hammer: HammerRig = HammerRig.new()
	hammer.position = HAMMER_POSITION
	root.add_child(hammer)
	hammer.build()
	data["hammer"] = hammer

	# ---- exit gate ---------------------------------------------------------
	var gate: ExitGate = ExitGate.new()
	gate.position = EXIT_GATE_POSITION
	root.add_child(gate)
	gate.build()
	data["gate"] = gate

	var bead_parent: Node3D = Node3D.new()
	bead_parent.name = "VeinBeads"
	root.add_child(bead_parent)
	var effect_parent: Node3D = Node3D.new()
	effect_parent.name = "ResonanceEffects"
	root.add_child(effect_parent)

	var network: ResonanceNetwork = ResonanceNetwork.new()
	network.name = "ResonanceNetwork"
	root.add_child(network)
	for id: Variant in crystals.keys():
		network.register_crystal(str(id), crystals[id] as EchoCrystal)
	network.setup(model, bead_parent, effect_parent)

	# ---- the collapsed stope and its suspended freight line --------------
	# Built last: it replaces the old single CaveFloor with four slabs around
	# the fault, and adds the two loading docks, the overhead rail, the platform
	# and the maintenance level. The crystal's spawn is on the far dock.
	var freight_arena: FreightArena = FreightArena.new()
	var freight_data: Dictionary = freight_arena.build(root, false, false)

	data["model"] = model
	data["crystals"] = crystals
	data["cradles"] = cradles
	data["network"] = network
	data["crystal_a"] = crystal_a
	data["crystal_b"] = crystal_b
	data["bead_parent"] = bead_parent
	data["effect_parent"] = effect_parent
	data["freight"] = freight_data
	data["platform"] = freight_data["platform"]
	return data


func _set_focus(model: ResonanceModel, crystals: Dictionary, from_id: String, to_id: String) -> void:
	var crystal: EchoCrystal = crystals.get(from_id) as EchoCrystal
	if crystal == null:
		return
	var target_position: Vector3 = model.get_position(to_id)
	var origin: Vector3 = model.get_position(from_id)
	model.set_focus(from_id, target_position - origin)


func _apply_yaw(crystal: EchoCrystal, yaw_degrees: float) -> void:
	crystal.rotation.y = deg_to_rad(yaw_degrees)
	crystal.base_yaw_deg = yaw_degrees


func _channel_for(id: String) -> String:
	if id.begins_with("f") or id == "m1":
		return "east"
	if id.begins_with("w") or id == "m2" or id == "t2" or id == "m3":
		return "west"
	return "west"


func _add_relay_node(model: ResonanceModel, id: String, position_value: Vector3) -> void:
	model.add_node(id, position_value, Vector3.FORWARD, "relay", "relay", 7.2, 60.0)
	model.set_enabled(id, false)


func _yaw_to(from_value: Vector3, to_value: Vector3) -> float:
	var direction: Vector3 = to_value - from_value
	return rad_to_deg(atan2(-direction.x, -direction.z))


func _add_echo_crystal(parent: Node3D, id: String, base_position: Vector3, scale_value: float, palette: String, yaw_degrees: float, with_light: bool) -> EchoCrystal:
	var crystal: EchoCrystal = EchoCrystal.new()
	crystal.name = "Crystal_" + id
	crystal.position = base_position
	parent.add_child(crystal)
	var asset: String = CLUSTER_ENV02 if palette == "cyan" else CLUSTER_MID
	if id == "m1":
		asset = CLUSTER_ENV02
	elif id == "m2":
		asset = CLUSTER_WEST
	elif id == "m3":
		asset = CLUSTER_MID
	crystal.build(id, CRYSTAL_DIR + asset, palette, scale_value, yaw_degrees, with_light)
	return crystal


func _add_cradle(parent: Node3D, id: String, position_value: Vector3, yaw_degrees: float, target_id: String, _model: ResonanceModel) -> ResonanceCradle:
	var cradle: ResonanceCradle = ResonanceCradle.new()
	cradle.name = "Cradle_" + id
	cradle.position = position_value
	parent.add_child(cradle)
	cradle.build(id, yaw_degrees, target_id)
	return cradle


func _make_ui_font() -> SystemFont:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "SimHei", "sans-serif"])
	font.allow_system_fallback = true
	return font


func _make_gravel_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/textures/gravel_ballast_base.png") as Texture2D
	material.roughness = 0.95
	material.metallic = 0.0
	material.uv1_scale = Vector3(5.0, 5.0, 1.0)
	material.albedo_color = Color(0.52, 0.52, 0.52)
	return material


func _build_shell(parent: Node3D) -> void:
	# The walking surface is now built by FreightArena at the end of build():
	# four slabs around the collapsed stope, so the fault is real collision
	# rather than a visual prop on top of a solid floor.
	BuildKit.box_visual(parent, "GravelWalk", Vector3(9.0, 0.03, 22.0), Vector3(0.0, 0.015, -2.0), _gravel_material)
	BuildKit.box_visual(parent, "GravelEast", Vector3(7.0, 0.03, 16.0), Vector3(13.5, 2.015, -11.5), _gravel_material)
	BuildKit.box_visual(parent, "GravelWest", Vector3(4.6, 0.03, 8.3), Vector3(-12.6, 0.015, -5.95), _gravel_material)
	BuildKit.box_visual(parent, "GravelFinal", Vector3(7.0, 0.03, 8.0), Vector3(-1.0, 0.015, -23.6), _gravel_material)
	# Spill patches break the perfectly straight edges of the ballast strips.
	for entry: Array in [
		[Vector3(-5.4, 0.012, 1.0), Vector3(3.2, 0.02, 9.0), 8.0],
		[Vector3(5.6, 0.012, -1.0), Vector3(3.0, 0.02, 8.0), -6.0],
		[Vector3(-1.0, 0.012, 8.0), Vector3(7.0, 0.02, 3.4), 4.0],
		[Vector3(0.0, 0.012, -12.0), Vector3(6.5, 0.02, 4.5), -10.0],
		[Vector3(-11.0, 0.012, -5.0), Vector3(3.4, 0.02, 5.0), 14.0],
	]:
		BuildKit.box_visual(parent, "GravelSpill%d" % int((entry[0] as Vector3).x * 10.0),
			entry[1] as Vector3, entry[0] as Vector3, _gravel_material, Vector3(0.0, float(entry[2]), 0.0))

	# Cave boundary: one generated, noise-displaced shell with an exact trimesh
	# collider. This replaces the six flat boxes that used to read as a black
	# void at 20 m (and made every prop look like it was floating).
	R04CaveShell.new().build(parent, MaterialLibrary.rock_shell(), "CaveShell")

	# Backstop volumes, far outside the visible rock. They exist only so a
	# physics glitch can never drop the player out of the world; they are never
	# reachable and therefore never read as invisible walls.
	BuildKit.static_box(parent, "BackstopNorth", Vector3(46.0, 18.0, 1.6), Vector3(0.0, 9.0, -30.8), _rock_material)
	BuildKit.static_box(parent, "BackstopSouth", Vector3(46.0, 18.0, 1.6), Vector3(0.0, 9.0, 14.8), _rock_material)
	BuildKit.static_box(parent, "BackstopEast", Vector3(1.6, 18.0, 46.0), Vector3(22.8, 9.0, -8.0), _rock_material)
	BuildKit.static_box(parent, "BackstopWest", Vector3(1.6, 18.0, 46.0), Vector3(-22.8, 9.0, -8.0), _rock_material)
	BuildKit.static_box(parent, "BackstopCeiling", Vector3(46.0, 1.0, 46.0), Vector3(0.0, 13.4, -8.0), _rock_material)

	# Final-chamber partition and exit corridor.
	# MECHANICS-004C：原来的整块 GateWallTop（0.7 × 2.6 × 5.4，y 4.60–7.20）
	# 把门上方封死了，真实升降门没有地方可去（旧实现只能靠「抬进岩体里 +
	# 开门瞬间关掉碰撞」糊过去）。现在按门体净宽切成南北两段，中间留出
	# 4.60 m 宽、5.20 m 高的真实岩体门袋槽；槽的四面与顶由 ExitGate 的钢制
	# 壳体封闭，所以门是真的升进门袋，不是穿墙，也不是隐形洞。
	BuildKit.static_box(parent, "GateWallTopNorth", Vector3(0.7, 5.20, 0.40),
		Vector3(3.35, 6.80, -27.50), _rock_material)
	BuildKit.static_box(parent, "GateWallTopSouth", Vector3(0.7, 5.20, 0.40),
		Vector3(3.35, 6.80, -22.50), _rock_material)
	# 门袋上方的岩帽：把槽封成真正的洞，而不是一条通向天空的缝。
	BuildKit.static_box(parent, "GatePocketCap", Vector3(0.7, 1.20, 4.60),
		Vector3(3.35, 10.00, -25.00), _rock_material)
	BuildKit.static_box(parent, "CorridorNorth", Vector3(15.0, 7.0, 0.8), Vector3(11.0, 3.5, -27.8), _rock_material)
	BuildKit.static_box(parent, "CorridorSouth", Vector3(15.0, 7.0, 0.8), Vector3(11.0, 3.5, -22.2), _rock_material)
	BuildKit.static_box(parent, "CorridorCeiling", Vector3(15.0, 0.8, 6.4), Vector3(11.0, 5.4, -25.0), _rock_material)

	# West alcove dressing. The old 2.6 x 4 m flat box was replaced with rock,
	# The old west alcove is now the far side of the stope. Its approach rocks
	# moved to the stope rim so they no longer float over the hole.
	for entry: Array in [
		[Vector3(-19.0, 0.0, 8.3), 1.00, 20.0], [Vector3(-7.0, 0.0, 8.6), 0.90, -35.0],
	]:
		_add_rock(parent, ROCK_KNUCKLE, entry[0] as Vector3, float(entry[1]), float(entry[2]), true, "floor")

	# Rock trim that visually merges the industrial partitions with the cave:
	# without it the flat partition faces read as grey slabs.
	for entry: Array in [
		[Vector3(-14.5, 0.0, -2.6), 1.5, -12.0], [Vector3(-19.0, 0.0, 3.8), 1.4, 40.0],
		[Vector3(3.35, 0.0, -20.2), 1.5, 70.0], [Vector3(3.35, 0.0, -29.0), 1.4, 20.0],
		[Vector3(10.1, 0.0, -11.5), 1.6, 5.0], [Vector3(10.1, 2.0, -15.6), 1.1, -20.0],
		# Stope-rim outcrops. They frame the fault instead of covering it.
		[Vector3(-13.0, 0.0, -2.8), 1.15, 30.0], [Vector3(-9.5, 0.0, 8.4), 1.30, -20.0],
		[Vector3(-16.8, 0.0, -2.9), 1.05, 65.0], [Vector3(-18.8, 0.0, 6.9), 1.10, 10.0],
		[Vector3(-18.9, 0.0, 8.0), 1.05, 50.0],
		# Final-chamber partition. The cladding sits on the east (dead) side:
		# the west face is the main aisle into the final chamber and must stay
		# walkable.
		[Vector3(4.15, 0.0, -18.4), 1.00, 15.0], [Vector3(4.10, 0.0, -21.6), 1.00, -35.0],
		[Vector3(4.2, 0.0, -29.4), 1.10, 70.0],
		# East retaining wall.
		[Vector3(9.9, 0.0, -8.6), 1.25, 45.0], [Vector3(9.9, 0.0, -14.6), 1.15, -15.0],
	]:
		_add_rock(parent, ROCK_APRON, entry[0] as Vector3, float(entry[1]), float(entry[2]), true, "floor")


func _build_platforms(parent: Node3D) -> void:
	# East production shelf.
	BuildKit.static_box(parent, "EastShelf", Vector3(9.0, 2.0, 9.0), Vector3(14.5, 1.0, -11.5), _rock_material)
	BuildKit.static_box(parent, "EastShelfFace", Vector3(1.2, 2.3, 9.0), Vector3(10.1, 1.05, -11.5), _rock_material)
	BuildKit.ramp(parent, "EastShelfRamp", 3.4, 4.4, 2.0, Vector3(11.3, 0.0, -4.0), 0.0, _rock_material)
	# The shelf has two 9 m flat faces on the walking route. Ribs, a cap beam
	# and base rocks keep them from reading as untextured slabs.
	for index: int in range(5):
		var z: float = -15.1 + float(index) * 1.75
		BuildKit.box_visual(parent, "ShelfRibW%d" % index, Vector3(0.10, 2.2, 0.16), Vector3(9.44, 1.10, z), _dark_metal)
		BuildKit.cylinder_visual(parent, "ShelfBoltW%d" % index, 0.06, 0.10, Vector3(9.38, 0.55, z), _rust, Vector3(90.0, 0.0, 0.0))
		BuildKit.cylinder_visual(parent, "ShelfBoltWT%d" % index, 0.06, 0.10, Vector3(9.38, 1.85, z), _rust, Vector3(90.0, 0.0, 0.0))
	for index: int in range(4):
		var x: float = 11.0 + float(index) * 2.3
		BuildKit.box_visual(parent, "ShelfRibN%d" % index, Vector3(0.16, 2.2, 0.10), Vector3(x, 1.10, -16.06), _dark_metal)
	BuildKit.box_visual(parent, "ShelfCapW", Vector3(0.98, 0.14, 9.2), Vector3(10.1, 2.24, -11.5), _metal)
	BuildKit.box_visual(parent, "ShelfCapN", Vector3(9.2, 0.14, 0.98), Vector3(14.5, 2.24, -16.0), _metal)
	for index: int in range(3):
		var t: float = 0.15 + float(index) * 0.35
		var post_height: float = 2.0 * t
		BuildKit.static_box(parent, "EastRampPost%d" % index, Vector3(0.16, maxf(post_height, 0.2), 0.16),
			Vector3(11.3, maxf(post_height, 0.2) * 0.5, -4.0 - 4.4 * t), _dark_metal)

	# West crystal plinths.
	BuildKit.static_cylinder(parent, "PlinthW1", 0.78, 0.50, Vector3(-4.6, 0.25, -7.2), _rock_material)
	BuildKit.static_cylinder(parent, "PlinthW2", 0.78, 0.70, Vector3(-8.6, 0.35, -9.6), _rock_material)
	BuildKit.static_cylinder(parent, "PlinthW3", 0.82, 0.90, Vector3(-15.0, 0.45, -14.4), _rock_material)
	BuildKit.static_cylinder(parent, "PlinthF1", 0.72, 0.55, Vector3(4.6, 0.275, -7.0), _rock_material)
	BuildKit.static_cylinder(parent, "PlinthF2", 0.80, 1.00, Vector3(8.8, 0.50, -9.8), _rock_material)
	BuildKit.static_cylinder(parent, "PlinthM1", 1.25, 0.60, Vector3(14.5, 2.30, -13.0), _rock_material)
	BuildKit.static_cylinder(parent, "PlinthM2", 1.45, 0.55, Vector3(-18.2, 0.275, -17.2), _rock_material)
	BuildKit.static_cylinder(parent, "PlinthT2", 0.95, 0.30, Vector3(-9.0, 3.55, -23.2), _rock_material)

	# Raised west observation ledge + long ramp.
	BuildKit.static_box(parent, "WestLedge", Vector3(6.0, 3.4, 6.5), Vector3(-11.5, 1.7, -20.75), _rock_material)
	BuildKit.static_box(parent, "WestLedgeFace", Vector3(6.4, 3.4, 0.8), Vector3(-11.5, 1.7, -17.5), _rock_material)
	BuildKit.ramp(parent, "WestRamp", 3.4, 6.5, 3.4, Vector3(-19.0, 0.0, -14.0), -51.0, _rock_material)
	# Steel sheet-pile face on the ledge: a 6.4 x 3.4 m flat rock panel read as a
	# grey slab from the west path. Ribs, a cap beam and bolts make it read as a
	# built retaining wall, and the ramp gets visible support posts.
	for index: int in range(5):
		var x: float = -14.2 + float(index) * 1.35
		BuildKit.box_visual(parent, "LedgeRib%d" % index, Vector3(0.16, 3.3, 0.10), Vector3(x, 1.65, -17.06), _dark_metal)
		BuildKit.cylinder_visual(parent, "LedgeBolt%d" % index, 0.07, 0.12, Vector3(x, 0.55, -16.98), _rust, Vector3(90.0, 0.0, 0.0))
		BuildKit.cylinder_visual(parent, "LedgeBoltTop%d" % index, 0.07, 0.12, Vector3(x, 2.85, -16.98), _rust, Vector3(90.0, 0.0, 0.0))
	BuildKit.box_visual(parent, "LedgeCap", Vector3(6.6, 0.16, 0.92), Vector3(-11.5, 3.44, -17.5), _metal)
	for index: int in range(3):
		var t: float = 0.18 + float(index) * 0.33
		var post_x: float = lerpf(-19.0, -14.0, t)
		var post_z: float = lerpf(-14.0, -18.1, t)
		var surface_y: float = 3.4 * t
		var post_height: float = maxf(surface_y - 0.10, 0.20)
		BuildKit.static_box(parent, "WestRampPost%d" % index, Vector3(0.18, post_height, 0.18),
			Vector3(post_x, post_height * 0.5, post_z), _dark_metal)

	# Final dais for the large memory crystal, with carved steps.
	BuildKit.static_cylinder(parent, "FinalDais", 2.45, 0.60, Vector3(-3.0, 0.30, -25.5), _rock_material)
	# Solid steps: each one is a full-height block from the floor. The old
	# 0.2 m thick slabs floated at 0.2 / 0.4 m with nothing underneath.
	for index: int in range(3):
		var step_height: float = 0.20 * float(index + 1)
		BuildKit.static_box(parent, "DaisStep%d" % index, Vector3(3.2, step_height, 0.55),
			Vector3(-3.0, step_height * 0.5, -22.50 - index * 0.55), _rock_material)
	BuildKit.box_visual(parent, "DaisWarning", Vector3(3.4, 0.02, 0.16), Vector3(-3.0, 0.615, -23.0), _paint_yellow)


func _build_decor_rocks(parent: Node3D) -> void:
	# Placement modes replace hand-typed Y values:
	#   floor   -> bottom sits on the cave floor
	#   east    -> bottom sits on the east production shelf (y = 2.0)
	#   ledge   -> bottom sits on the west observation ledge (y = 3.4)
	#   ceiling -> top is embedded in the cave roof
	# Every mode derives Y from the real mesh bounds, so a swapped asset can
	# never silently float or sink again.
	var rocks: Array[Array] = [
		[ROCK_THRUST, Vector3(-18.2, 0.0, -23.5), 2.4, 28.0, true, "floor"],
		[ROCK_SHELF, Vector3(-19.0, 0.0, -8.5), 2.0, -18.0, true, "floor"],
		[ROCK_KNUCKLE, Vector3(-18.8, 0.0, 5.0), 2.1, 58.0, true, "floor"],
		[ROCK_APRON, Vector3(18.6, 0.0, -19.0), 2.2, 16.0, true, "floor"],
		[ROCK_FLANK, Vector3(18.8, 0.0, -3.0), 2.0, 71.0, true, "floor"],
		[ROCK_CAP, Vector3(17.5, 0.0, 2.0), 2.1, 22.0, true, "ceiling"],
		[ROCK_CAP, Vector3(0.0, 0.0, -27.2), 3.4, 4.0, true, "ceiling"],
		[ROCK_LIP, Vector3(10.4, 0.0, -19.2), 2.0, -12.0, true, "floor"],
		[ROCK_FISSURE, Vector3(-13.8, 0.0, -4.2), 1.5, 32.0, true, "floor"],
		[ROCK_TONGUE, Vector3(8.6, 0.0, -18.6), 1.5, 45.0, true, "floor"],
		[ROCK_THRUST, Vector3(17.0, 0.0, -16.5), 1.2, -30.0, true, "east"],
		[ROCK_LIP, Vector3(-6.0, 0.0, -27.5), 1.6, 90.0, true, "floor"],
		[ROCK_THRUST, Vector3(-6.2, 0.0, -26.8), 1.7, 40.0, true, "floor"],
		[ROCK_KNUCKLE, Vector3(-8.8, 0.0, -27.5), 1.4, -20.0, true, "floor"],
		[ROCK_APRON, Vector3(-6.5, 0.0, -20.8), 1.1, 80.0, true, "floor"],
		[ROCK_LIP, Vector3(-14.0, 0.0, -23.6), 1.3, 20.0, true, "ledge"],
		[ROCK_FLANK, Vector3(18.8, 0.0, -10.5), 1.3, 30.0, true, "east"],
		[ROCK_CAP, Vector3(0.0, 0.0, 5.5), 2.4, 10.0, true, "ceiling"],
		[ROCK_SHELF, Vector3(-19.0, 0.0, -25.5), 1.8, 60.0, true, "floor"],
		[ROCK_TONGUE, Vector3(10.0, 0.0, -16.0), 1.0, 0.0, false, "east"],
		# Additional wall-base masses: the generated cave shell is visible now, so
		# it needs three-dimensional rock in front of it, not just a texture.
		[ROCK_APRON, Vector3(-18.9, 0.0, -16.0), 1.8, 12.0, true, "floor"],
		[ROCK_TONGUE, Vector3(-19.1, 0.0, -2.0), 1.4, 66.0, true, "floor"],
		[ROCK_APRON, Vector3(-18.4, 0.0, 8.6), 2.0, -28.0, true, "floor"],
		[ROCK_TONGUE, Vector3(19.0, 0.0, 6.5), 1.6, 104.0, true, "floor"],
		[ROCK_APRON, Vector3(18.6, 0.0, -24.5), 1.7, 32.0, true, "floor"],
		[ROCK_TONGUE, Vector3(5.0, 0.0, -27.9), 1.3, 15.0, true, "floor"],
		[ROCK_APRON, Vector3(15.2, 0.0, -26.9), 1.5, 80.0, true, "floor"],
		[ROCK_TONGUE, Vector3(-1.5, 0.0, 11.5), 1.5, 190.0, true, "floor"],
	]
	for entry: Array in rocks:
		_add_rock(parent, str(entry[0]), entry[1] as Vector3, float(entry[2]), float(entry[3]), bool(entry[4]), str(entry[5]))

	# The ceiling shell already has large-scale sag and bumps; a ring of cone
	# stalactites read as black triangles floating under it, so the roof shape
	# comes from the shell alone.

	# Decorative crystal growths (not part of the resonance graph). Each one
	# grows out of a rock base, never out of thin air.
	var decor: Array[Array] = [
		[CLUSTER_ENV02, Vector3(-20.0, 0.0, 9.0), 1.0, "cyan", 20.0, "floor"],
		[BLADE_CYAN, Vector3(-6.0, 0.0, 9.4), 0.8, "cyan", 70.0, "floor"],
		[CLUSTER_MID, Vector3(18.4, 0.0, -6.4), 0.9, "cyan", 180.0, "floor"],
		[BLADE_VIOLET, Vector3(19.0, 0.0, 3.2), 1.1, "violet", 210.0, "floor"],
		[BLADE_CYAN, Vector3(-19.2, 0.0, -16.2), 1.0, "cyan", 100.0, "floor"],
		[BLADE_VIOLET, Vector3(-19.0, 0.0, -20.5), 0.8, "violet", 250.0, "floor"],
		[CLUSTER_ENV02, Vector3(19.2, 0.0, -22.5), 1.0, "violet", 300.0, "floor"],
		[BLADE_CYAN, Vector3(4.0, 0.0, 11.4), 0.7, "cyan", 150.0, "floor"],
		[CLUSTER_ENV02, Vector3(18.6, 0.0, -7.2), 0.72, "cyan", 200.0, "east"],
		[CLUSTER_MID, Vector3(-18.9, 0.0, -6.0), 0.70, "cyan", 80.0, "floor"],
		[BLADE_VIOLET, Vector3(18.8, 0.0, -14.2), 0.8, "violet", 190.0, "east"],
		[CLUSTER_ENV02, Vector3(-19.0, 0.0, -25.0), 0.70, "violet", 40.0, "floor"],
		[BLADE_CYAN, Vector3(-8.2, 0.0, -22.6), 0.7, "cyan", 20.0, "ledge"],
		[BLADE_CYAN, Vector3(8.0, 0.0, -23.4), 0.7, "cyan", 15.0, "floor"],
		[CLUSTER_MID, Vector3(-19.0, 0.0, -16.0), 0.75, "cyan", 120.0, "floor"],
		[BLADE_VIOLET, Vector3(-18.4, 0.0, -11.0), 0.9, "violet", 330.0, "floor"],
		[BLADE_CYAN, Vector3(18.9, 0.0, 8.8), 0.8, "cyan", 240.0, "floor"],
	]
	for entry: Array in decor:
		var asset: String = str(entry[0])
		var position_value: Vector3 = entry[1] as Vector3
		var scale_value: float = float(entry[2])
		var palette: String = str(entry[3])
		var yaw: float = float(entry[4])
		var surface: String = str(entry[5])
		# A low rock outcrop is the growth base. Its top is used as the crystal's
		# origin, so the crystal always sits exactly on the stone.
		var outcrop: Node3D = _add_rock(parent, ROCK_APRON if palette == "cyan" else ROCK_TONGUE,
			position_value, 0.55 * scale_value + 0.30, yaw * 0.5, false, surface)
		var base_top: float = 0.0
		if outcrop != null:
			base_top = _visual_bounds(outcrop).end.y
		var crystal: CrystalVisual = CrystalVisual.new()
		crystal.name = "DecorCrystal"
		parent.add_child(crystal)
		crystal.position = Vector3(position_value.x, base_top - 0.02, position_value.z)
		crystal.rotation.y = deg_to_rad(yaw)
		crystal.build(CRYSTAL_DIR + asset, palette, scale_value, false)
		crystal.set_focus_visible(false)

	# Ground rubble. Small stones break the flat floor plane and give the eye a
	# sense of scale along every route the player actually walks.
	var rubble: Array[Vector3] = [
		Vector3(-3.0, 0.0, 4.0), Vector3(3.6, 0.0, 2.2), Vector3(-7.2, 0.0, -2.0),
		Vector3(6.2, 0.0, -3.4), Vector3(-1.0, 0.0, -14.0), Vector3(2.0, 0.0, -20.0),
		Vector3(12.5, 2.0, -8.0), Vector3(-17.0, 0.0, -10.5),
		Vector3(-9.4, 0.0, 6.8), Vector3(-11.8, 0.0, 1.0), Vector3(-5.4, 0.0, 9.2),
		Vector3(7.8, 0.0, 7.6), Vector3(1.4, 0.0, -7.8), Vector3(-4.4, 0.0, -15.8),
		Vector3(-10.0, 0.0, -17.2), Vector3(-15.6, 3.4, -19.4), Vector3(-9.6, 3.4, -22.0),
		Vector3(11.0, 2.0, -13.8), Vector3(16.4, 2.0, -9.2), Vector3(0.8, 0.0, -24.6),
		Vector3(-8.0, 0.0, -25.6), Vector3(-13.2, 0.0, -26.2), Vector3(5.2, 0.0, -21.4),
	]
	for index: int in range(rubble.size()):
		_add_rock(parent, ROCK_TONGUE if index % 2 == 0 else ROCK_APRON, rubble[index],
			0.30 + float(index % 4) * 0.09, float(index) * 47.0, false,
			"ledge" if rubble[index].y > 3.0 else ("east" if rubble[index].y > 1.5 else "floor"))

	_add_floor_variation(parent)


func _add_ceiling_spines(parent: Node3D) -> void:
	# A few large, thick spines that grow out of the roof near the walls. They
	# are embedded 0.6 m into the shell, so they read as one rock mass instead of
	# a cone pasted under a plane.
	var entries: Array[Array] = [
		[Vector3(-16.0, 0.0, -9.0), 2.4, 0.55],
		[Vector3(15.5, 0.0, 4.0), 2.8, 0.68],
		[Vector3(-8.5, 0.0, -26.0), 2.2, 0.50],
		[Vector3(12.0, 0.0, -24.0), 3.0, 0.62],
		[Vector3(-17.5, 0.0, 6.0), 2.0, 0.46],
	]
	for index: int in range(entries.size()):
		var spot: Vector3 = entries[index][0] as Vector3
		var height: float = float(entries[index][1])
		var radius: float = float(entries[index][2])
		var ceiling: float = R04CaveShell.ceiling_y(spot.x, spot.z)
		var spine: MeshInstance3D = BuildKit.cylinder_visual(parent, "CeilingSpine%d" % index,
			radius, height, Vector3(spot.x, ceiling + 0.6 - height * 0.5, spot.z),
			_rock_material, Vector3(0.0, float(index) * 31.0, 4.0), 0.05)
		spine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _add_floor_variation(parent: Node3D) -> void:
	var slabs: Array[Array] = [
		[Vector3(6.5, 0.025, -10.5), Vector3(5.5, 0.05, 4.6), 12.0, Color(0.46, 0.48, 0.54)],
		[Vector3(-7.0, 0.025, 1.5), Vector3(5.0, 0.05, 4.2), -20.0, Color(0.62, 0.55, 0.46)],
		[Vector3(14.0, 2.025, -15.0), Vector3(4.2, 0.05, 3.2), 8.0, Color(0.42, 0.46, 0.52)],
		[Vector3(-12.0, 0.025, -23.0), Vector3(4.8, 0.05, 3.6), 40.0, Color(0.52, 0.50, 0.48)],
		[Vector3(1.5, 0.025, -16.0), Vector3(4.0, 0.05, 3.0), -8.0, Color(0.58, 0.49, 0.39)],
	]
	for index: int in range(slabs.size()):
		var entry: Array = slabs[index]
		var position_value: Vector3 = entry[0] as Vector3
		var size_value: Vector3 = entry[1] as Vector3
		var yaw: float = float(entry[2])
		var tint: Color = entry[3] as Color
		var material: ShaderMaterial = _rock_material.duplicate() as ShaderMaterial
		material.set_shader_parameter("tint", tint)
		material.set_shader_parameter("uv_scale", 0.24)
		BuildKit.box_visual(parent, "FloorSlab%d" % index, size_value, position_value, material, Vector3(0.0, yaw, 0.0))


func _build_atmosphere(parent: Node3D) -> void:
	# Thin cables hanging from the roof. The top ends inside the generated
	# ceiling: the old build had them stop 1.2 m short of it, which is exactly
	# the kind of floating prop that was reported.
	var cable_positions: Array[Vector3] = [
		Vector3(-3.2, 0.0, 2.4), Vector3(5.4, 0.0, 5.2), Vector3(-11.5, 0.0, -12.5),
		Vector3(12.4, 0.0, -5.0), Vector3(-1.5, 0.0, -19.0), Vector3(8.5, 0.0, -25.0),
	]
	for index: int in range(cable_positions.size()):
		var spot: Vector3 = cable_positions[index]
		var ceiling: float = R04CaveShell.ceiling_y(spot.x, spot.z)
		var length: float = 5.2 + 0.8 * float(index % 3)
		var cable: MeshInstance3D = BuildKit.cylinder_visual(parent, "HangingCable%d" % index, 0.025, length,
			Vector3(spot.x, ceiling + 0.30 - length * 0.5, spot.z), _dark_metal,
			Vector3(0.0, 0.0, 3.0 if index % 2 == 0 else -4.0))
		cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A small shackle where the cable meets the rock, so the attachment reads.
		BuildKit.cylinder_visual(parent, "CableShackle%d" % index, 0.09, 0.16,
			Vector3(spot.x, ceiling - 0.05, spot.z), _rust)

	_add_dust(parent, "DustHammer", Vector3(0.0, 4.4, -3.0), Vector3(6.0, 3.0, 5.0), 28)
	_add_dust(parent, "DustFinal", Vector3(-3.0, 3.2, -24.5), Vector3(4.5, 2.2, 3.8), 22)
	_add_dust(parent, "DustShelf", Vector3(14.0, 3.6, -11.0), Vector3(4.0, 2.0, 4.5), 18)


func _add_dust(parent: Node3D, dust_name: String, position_value: Vector3, extents: Vector3, amount: int) -> void:
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = dust_name
	particles.amount = amount
	particles.lifetime = 9.0
	particles.preprocess = 4.0
	particles.emitting = true
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 180.0
	particles.gravity = Vector3(0.0, 0.01, 0.0)
	particles.initial_velocity_min = 0.01
	particles.initial_velocity_max = 0.09
	particles.scale_amount_min = 0.015
	particles.scale_amount_max = 0.045
	particles.color = Color(0.62, 0.82, 1.0, 0.28)
	var dust_mesh: SphereMesh = SphereMesh.new()
	dust_mesh.radius = 0.04
	dust_mesh.height = 0.08
	dust_mesh.radial_segments = 5
	dust_mesh.rings = 3
	particles.mesh = dust_mesh
	var dust_material: StandardMaterial3D = StandardMaterial3D.new()
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.vertex_color_use_as_albedo = true
	dust_material.albedo_color = Color(0.62, 0.82, 1.0, 0.28)
	dust_material.emission_enabled = true
	dust_material.emission = Color(0.50, 0.76, 1.0)
	dust_material.emission_energy_multiplier = 0.4
	particles.material_override = dust_material
	particles.position = position_value
	parent.add_child(particles)


func _add_rock(parent: Node3D, asset: String, position_value: Vector3, scale_value: float, yaw: float, shadow: bool, mode: String = "floor") -> Node3D:
	var packed: PackedScene = load(ROCK_DIR + asset) as PackedScene
	if packed == null:
		push_error("Rock asset missing: " + asset)
		return null
	var instance: Node3D = packed.instantiate() as Node3D
	instance.name = "Rock_" + asset.get_basename().replace("res_rock_", "").replace("_a_lod0", "") + "_%d" % _rock_instance_index
	_rock_instance_index += 1
	parent.add_child(instance)
	instance.position = Vector3(position_value.x, 0.0, position_value.z)
	instance.rotation.y = deg_to_rad(yaw)
	instance.scale = Vector3.ONE * scale_value

	# Derive Y from the real mesh bounds so an asset swap can never silently
	# float or sink. This is the root fix for the "random floating boulders".
	var bounds: AABB = _visual_bounds(instance)
	match mode:
		"floor":
			instance.position.y = -bounds.position.y - 0.05
		"east":
			instance.position.y = 2.0 - bounds.position.y - 0.05
		"ledge":
			instance.position.y = 3.4 - bounds.position.y - 0.05
		"ceiling":
			instance.position.y = R04CaveShell.ceiling_y(position_value.x, position_value.z) + 0.55 - bounds.end.y
		_:
			instance.position.y = position_value.y

	var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
	for child: Node in meshes:
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh != null:
			mesh.material_override = _rock_material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Player and camera must stop on the visible rock. Both use one convex proxy
	# generated from this asset's own vertices (cached per asset, ~900 points),
	# which is cheap for a static body and close to the silhouette.
	if mode != "ceiling" and scale_value >= 0.9:
		_add_rock_collision(instance, asset)
	return instance


func _visual_bounds(root: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _add_rock_collision(instance: Node3D, asset: String) -> void:
	var points: PackedVector3Array = _rock_points(instance, asset)
	if points.size() < 8:
		return
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "RockCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	instance.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Collision"
	var convex: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	convex.points = points
	shape.shape = convex
	body.add_child(shape)


## Decimated vertex soup in the rock instance's local space, cached per asset.
func _rock_points(instance: Node3D, asset: String) -> PackedVector3Array:
	if _rock_point_cache.has(asset):
		return _rock_point_cache[asset] as PackedVector3Array
	var total: int = 0
	var meshes: Array[MeshInstance3D] = []
	for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		meshes.append(mesh_instance)
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface)
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
				total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var stride: int = maxi(1, int(ceil(float(total) / 900.0)))
	var inverse: Transform3D = instance.global_transform.affine_inverse()
	var points: PackedVector3Array = PackedVector3Array()
	for mesh_instance: MeshInstance3D in meshes:
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var to_local: Transform3D = inverse * mesh_instance.global_transform
			for index: int in range(0, vertices.size(), stride):
				points.append(to_local * vertices[index])
	_rock_point_cache[asset] = points
	return points


func _build_industrial_dressing(parent: Node3D) -> void:
	# Hammer sign board. Moved off the sight line to the hammer head: in first
	# person the old 2.2 x 0.75 m plate sat exactly where the head should be.
	BuildKit.static_box(parent, "HammerSignPost", Vector3(0.15, 2.5, 0.15), Vector3(3.95, 1.25, -4.55), _dark_metal)
	BuildKit.box_visual(parent, "HammerSignPlate", Vector3(1.7, 0.60, 0.08), Vector3(3.95, 2.38, -4.55), _paint_cream)
	var sign_label: Label3D = Label3D.new()
	sign_label.name = "HammerSignLabel"
	sign_label.text = "07 · 共振撞钟"
	sign_label.font = _make_ui_font()
	sign_label.font_size = 44
	sign_label.pixel_size = 0.0045
	sign_label.modulate = Color(0.16, 0.12, 0.06)
	sign_label.position = Vector3(3.95, 2.38, -4.49)
	parent.add_child(sign_label)

	# Safety line around the hammer.
	for index: int in range(3):
		BuildKit.box_visual(parent, "SafetyLine%d" % index, Vector3(1.4, 0.02, 0.16), Vector3(-3.2 + index * 3.2, 0.02, 2.0), _paint_yellow, Vector3(0.0, 0.0, 0.0))

	# Crates near spawn and the west alcove.
	var crates: Array[Array] = [
		[Vector3(-4.2, 0.35, 7.2), 0.7, 12.0], [Vector3(-3.3, 0.25, 7.6), 0.5, -8.0],
		[Vector3(-7.0, 2.95, 4.7), 0.9, 22.0], [Vector3(-18.0, 0.30, -11.8), 0.6, -14.0],
		[Vector3(9.2, 2.25, -15.6), 0.5, 4.0],
	]
	for index: int in range(crates.size()):
		var entry: Array = crates[index]
		var position_value: Vector3 = entry[0] as Vector3
		var size_value: float = float(entry[1])
		var yaw: float = float(entry[2])
		var crate: MeshInstance3D = BuildKit.box_visual(parent, "Crate%d" % index, Vector3(size_value, size_value, size_value), position_value, _wood, Vector3(0.0, yaw, 0.0))
		crate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		BuildKit.box_visual(parent, "CrateBand%d" % index, Vector3(size_value * 1.03, size_value * 0.10, size_value * 1.03), position_value, _rust, Vector3(0.0, yaw, 0.0))

	# Wall pipes. Brackets make them read as a pipe run fixed to the wall, not
	# as bars floating in front of it.
	for index: int in range(4):
		BuildKit.cylinder_visual(parent, "Pipe%d" % index, 0.10, 12.0, Vector3(19.2, 2.2 + index * 0.42, -12.0), _rust, Vector3(90.0, 0.0, 0.0))
	for index: int in range(3):
		BuildKit.cylinder_visual(parent, "PipeW%d" % index, 0.08, 8.0, Vector3(-19.2, 1.8 + index * 0.36, -8.0), _rust, Vector3(90.0, 0.0, 0.0))
	for z: float in [-11.4, -8.0, -4.6]:
		BuildKit.cylinder_visual(parent, "PipeBracketW%s" % str(z), 0.045, 2.9, Vector3(-19.16, 1.45, z), _dark_metal)
		BuildKit.box_visual(parent, "PipePlateW%s" % str(z), Vector3(0.10, 0.30, 0.34), Vector3(-19.10, 0.20, z), _rust)
	for z: float in [-15.0, -12.0, -9.0]:
		BuildKit.cylinder_visual(parent, "PipeBracketE%s" % str(z), 0.045, 3.4, Vector3(19.16, 1.70, z), _dark_metal)

	# Cable reels and a dead cargo loader near crystal B.
	BuildKit.cylinder_visual(parent, "CableReel", 0.62, 0.20, Vector3(-17.8, 0.62, -14.6), _wood, Vector3(0.0, 0.0, 90.0))
	BuildKit.cylinder_visual(parent, "CableReelHub", 0.18, 1.10, Vector3(-17.8, 0.62, -14.6), _dark_metal, Vector3(0.0, 0.0, 90.0))
	BuildKit.static_box(parent, "CargoRack", Vector3(2.6, 0.25, 1.2), Vector3(-16.8, 0.42, -12.5), _metal)
	for index: int in range(4):
		var ox: float = -1.15 if index % 2 == 0 else 1.15
		var oz: float = -0.45 if index < 2 else 0.45
		BuildKit.box_visual(parent, "CargoRackLeg%d" % index, Vector3(0.09, 0.32, 0.09),
			Vector3(-16.8 + ox, 0.16, -12.5 + oz), _dark_metal)
	BuildKit.box_visual(parent, "CargoRackStripe", Vector3(2.6, 0.06, 0.10), Vector3(-16.8, 0.56, -11.95), _paint_yellow)

	# Observation ledge rail (only on the south side, east edge stays open).
	for index: int in range(4):
		var x: float = -14.0 + index * 1.5
		BuildKit.cylinder_visual(parent, "LedgePost%d" % index, 0.05, 1.05, Vector3(x, 3.92, -17.8), _metal)
	BuildKit.box_visual(parent, "LedgeRail", Vector3(4.8, 0.07, 0.07), Vector3(-11.75, 4.40, -17.8), _paint_yellow)
	# Lower rail + toe board: a railing you would actually trust at 3.4 m.
	BuildKit.box_visual(parent, "LedgeRailLow", Vector3(4.8, 0.05, 0.05), Vector3(-11.75, 4.02, -17.8), _metal)
	BuildKit.box_visual(parent, "LedgeToe", Vector3(4.8, 0.12, 0.03), Vector3(-11.75, 3.47, -17.82), _dark_metal)


## The entrance: an abandoned loading station behind the spawn, so the act
## reads as "we just came off the mine cart" instead of starting in a vacuum.
## Everything here is visual only and sits off the critical walking route.
func _build_entrance_station(parent: Node3D) -> void:
	var sleeper: StandardMaterial3D = MaterialLibrary.painted(Color(0.22, 0.16, 0.11), 0.92)
	var rail_metal: StandardMaterial3D = MaterialLibrary.metal(Color(0.36, 0.38, 0.40), 0.40, 0.86)
	var rail_wear: StandardMaterial3D = MaterialLibrary.metal(Color(0.64, 0.66, 0.68), 0.24, 0.9)
	var cart_body: StandardMaterial3D = MaterialLibrary.metal(Color(0.44, 0.46, 0.48), 0.58, 0.6)
	var cart_rust: StandardMaterial3D = MaterialLibrary.metal(Color(0.52, 0.30, 0.16), 0.82, 0.25)
	var lamp_glow: StandardMaterial3D = MaterialLibrary.emissive(Color(1.0, 0.72, 0.36), 1.8)

	# Tail track on the east side of the spawn, running north to south.
	const X := 5.9
	for side: int in range(2):
		var offset: float = -0.42 if side == 0 else 0.42
		BuildKit.box_visual(parent, "ArrivalRail%d" % side, Vector3(0.09, 0.10, 9.4),
			Vector3(X + offset, 0.09, 8.6), rail_metal)
		BuildKit.box_visual(parent, "ArrivalRailWear%d" % side, Vector3(0.12, 0.015, 9.4),
			Vector3(X + offset, 0.145, 8.6), rail_wear)
	for index: int in range(12):
		BuildKit.box_visual(parent, "ArrivalSleeper%d" % index, Vector3(1.30, 0.10, 0.22),
			Vector3(X, 0.025, 13.3 - float(index) * 0.78), sleeper)
	# Buffer stop at the end, so the track has a destination.
	BuildKit.box_visual(parent, "BufferBeam", Vector3(1.7, 0.30, 0.26), Vector3(X, 0.55, 4.02), cart_rust)
	BuildKit.box_visual(parent, "BufferStripe", Vector3(1.7, 0.10, 0.04), Vector3(X, 0.55, 3.88), _paint_yellow)
	var buffer_body: StaticBody3D = StaticBody3D.new()
	buffer_body.name = "BufferStopBody"
	buffer_body.position = Vector3(X, 0.42, 4.06)
	buffer_body.collision_layer = 1
	buffer_body.collision_mask = 0
	parent.add_child(buffer_body)
	var buffer_shape: CollisionShape3D = CollisionShape3D.new()
	var buffer_box: BoxShape3D = BoxShape3D.new()
	buffer_box.size = Vector3(1.8, 0.7, 0.3)
	buffer_shape.shape = buffer_box
	buffer_body.add_child(buffer_shape)
	for side: int in range(2):
		BuildKit.box_visual(parent, "BufferLeg%d" % side, Vector3(0.16, 0.55, 0.55),
			Vector3(X + (-0.62 if side == 0 else 0.62), 0.27, 4.22), _dark_metal, Vector3(-18.0, 0.0, 0.0))

	# The derelict cart: visible silhouette (body, ribs, four wheels, ore), not
	# a plain box. It is tipped 7 degrees as if it was shunted off the rails.
	var cart: Node3D = Node3D.new()
	cart.name = "DerelictCart"
	cart.position = Vector3(X, 0.0, 10.6)
	cart.rotation = Vector3(0.0, deg_to_rad(-6.0), deg_to_rad(7.0))
	parent.add_child(cart)
	# Collision-only proxy: BuildKit.static_box would add a visible dark box that
	# swallowed the whole cart.
	var cart_collider: StaticBody3D = StaticBody3D.new()
	cart_collider.name = "CartCollision"
	cart_collider.position = Vector3(X, 0.9, 10.6)
	cart_collider.collision_layer = 1
	cart_collider.collision_mask = 0
	parent.add_child(cart_collider)
	var cart_shape: CollisionShape3D = CollisionShape3D.new()
	var cart_box: BoxShape3D = BoxShape3D.new()
	cart_box.size = Vector3(1.4, 1.7, 2.2)
	cart_shape.shape = cart_box
	cart_collider.add_child(cart_shape)
	BuildKit.box_visual(cart, "CartBody", Vector3(1.24, 0.78, 2.05), Vector3(0.0, 0.92, 0.0), cart_body)
	BuildKit.box_visual(cart, "CartLip", Vector3(1.34, 0.09, 2.15), Vector3(0.0, 1.30, 0.0), cart_rust)
	for index: int in range(3):
		BuildKit.box_visual(cart, "CartRib%d" % index, Vector3(1.30, 0.80, 0.07),
			Vector3(0.0, 0.92, -0.72 + float(index) * 0.72), cart_rust)
	BuildKit.box_visual(cart, "CartUnder", Vector3(1.05, 0.16, 1.70), Vector3(0.0, 0.48, 0.0), _dark_metal)
	for index: int in range(2):
		BuildKit.cylinder_visual(cart, "CartAxle%d" % index, 0.055, 1.34,
			Vector3(0.0, 0.36, -0.62 if index == 0 else 0.62), _dark_metal, Vector3(0.0, 0.0, 90.0))
	for index: int in range(4):
		var wx: float = -0.63 if index % 2 == 0 else 0.63
		var wz: float = -0.62 if index < 2 else 0.62
		BuildKit.cylinder_visual(cart, "CartWheel%d" % index, 0.30, 0.13,
			Vector3(wx, 0.34, wz), cart_rust, Vector3(0.0, 0.0, 90.0))
		BuildKit.cylinder_visual(cart, "CartHub%d" % index, 0.09, 0.16,
			Vector3(wx, 0.34, wz), _dark_metal, Vector3(0.0, 0.0, 90.0))
	# Ore load: three faceted lumps, the reason the cart exists.
	for index: int in range(3):
		var ore: MeshInstance3D = BuildKit.sphere_visual(cart, "CartOre%d" % index, 0.24,
			Vector3(-0.22 + float(index) * 0.24, 1.30, -0.4 + float(index) * 0.4), _rock_material)
		ore.scale = Vector3(1.0, 0.62, 1.15)
	BuildKit.box_visual(cart, "CartLamp", Vector3(0.16, 0.12, 0.08), Vector3(0.0, 1.18, -1.06), lamp_glow)
	BuildKit.omni_light(cart, "CartLampLight", Vector3(0.0, 1.22, -1.12), Color(1.0, 0.68, 0.34), 1.4, 4.5, false)

	# Loading platform with a stair, edge stripe, posts and a work lamp.
	var deck: StandardMaterial3D = MaterialLibrary.painted(Color(0.44, 0.36, 0.25), 0.86)
	BuildKit.static_box(parent, "ArrivalPlatform", Vector3(3.2, 0.38, 3.6), Vector3(8.9, 0.19, 9.0), deck)
	BuildKit.box_visual(parent, "PlatformStripe", Vector3(0.10, 0.02, 3.6), Vector3(7.32, 0.39, 9.0), _paint_yellow)
	for index: int in range(3):
		BuildKit.box_visual(parent, "PlatformEdge%d" % index, Vector3(0.06, 0.05, 3.4),
			Vector3(7.34, 0.30 - float(index) * 0.05, 9.0), _rust)
	for index: int in range(4):
		BuildKit.box_visual(parent, "PlatformPost%d" % index, Vector3(0.10, 0.38, 0.10),
			Vector3(7.6 + float(index % 2) * 2.6, 0.19, 7.5 + float(index / 2) * 3.0), _dark_metal)
	BuildKit.box_visual(parent, "PlatformStepA", Vector3(1.6, 0.20, 0.7), Vector3(8.9, 0.10, 6.95), deck)
	BuildKit.box_visual(parent, "PlatformStepB", Vector3(1.6, 0.10, 0.5), Vector3(8.9, 0.05, 6.35), deck)
	# Timber portal over the tail track: the way in from the previous act.
	for side: int in range(2):
		var x: float = X + (-1.15 if side == 0 else 1.15)
		BuildKit.static_box(parent, "PortalPost%d" % side, Vector3(0.34, 4.3, 0.34),
			Vector3(x, 2.15, 12.6), _wood)
		BuildKit.box_visual(parent, "PortalBrace%d" % side, Vector3(0.20, 1.2, 0.20),
			Vector3(x + (-0.45 if side == 0 else 0.45), 3.6, 12.6), _wood, Vector3(0.0, 0.0, 32.0 if side == 0 else -32.0))
	BuildKit.box_visual(parent, "PortalLintel", Vector3(2.9, 0.40, 0.45), Vector3(X, 4.45, 12.6), _wood)
	BuildKit.box_visual(parent, "PortalLamp", Vector3(0.30, 0.10, 0.14), Vector3(X, 4.18, 12.42), lamp_glow)
	BuildKit.omni_light(parent, "PortalLampLight", Vector3(X, 4.05, 12.35), Color(1.0, 0.70, 0.38), 3.0, 8.0, false)
	BuildKit.omni_light(parent, "ArrivalWarm", Vector3(8.6, 2.8, 9.2), Color(1.0, 0.76, 0.48), 3.0, 11.0, false)
	BuildKit.omni_light(parent, "ArrivalCool", Vector3(6.0, 2.2, 11.8), Color(0.32, 0.62, 0.92), 1.6, 7.0, false)
	BuildKit.omni_light(parent, "ArrivalCartLight", Vector3(4.6, 2.2, 9.9), Color(1.0, 0.78, 0.50), 2.4, 7.0, false)

	# A stencilled plate on the portal: the wing number, no HUD arrow needed.
	var plate: Label3D = Label3D.new()
	plate.name = "ArrivalPlate"
	plate.text = "04  ·  晶体采掘段"
	plate.font = _make_ui_font()
	plate.font_size = 40
	plate.pixel_size = 0.005
	plate.modulate = Color(0.98, 0.80, 0.48)
	plate.outline_size = 8
	plate.outline_modulate = Color(0.06, 0.04, 0.02, 0.9)
	plate.position = Vector3(X, 4.02, 12.36)
	parent.add_child(plate)


## The severed resonance path between w2 and B1: the single most important
## piece of level storytelling, made visible in the world instead of a toast.
func _build_broken_path_cue(parent: Node3D) -> void:
	var scorch: StandardMaterial3D = StandardMaterial3D.new()
	scorch.albedo_color = Color(0.06, 0.07, 0.08)
	scorch.roughness = 1.0
	BuildKit.cylinder_visual(parent, "BreakScorch", 1.15, 0.012, Vector3(-10.0, 0.012, -11.2), scorch, Vector3.ZERO, 1.15)
	# Fallen shards: the top half of a snapped crystal, lying where it fell.
	for entry: Array in [
		[Vector3(-10.35, 0.18, -11.35), 26.0, 0.52, 96.0],
		[Vector3(-9.55, 0.12, -10.7), -14.0, 0.34, 128.0],
		[Vector3(-11.05, 0.10, -10.5), 8.0, 0.28, 152.0],
	]:
		var shard: CrystalVisual = CrystalVisual.new()
		shard.name = "BrokenShard"
		shard.position = entry[0] as Vector3
		shard.rotation_degrees = Vector3(74.0, float(entry[3]), float(entry[1]))
		parent.add_child(shard)
		shard.build(CRYSTAL_DIR + BLADE_CYAN, "cyan", float(entry[2]), false)
		shard.set_focus_visible(false)
		shard.set_pulse(0.05)
	# Two leaning marker posts with barrier tape facing the gap.
	for side: int in range(2):
		var x: float = -9.3 if side == 0 else -12.4
		BuildKit.cylinder_visual(parent, "BreakPost%d" % side, 0.035, 1.15,
			Vector3(x, 0.56, -13.0), _paint_yellow, Vector3(0.0, 0.0, 9.0 if side == 0 else -9.0))
		BuildKit.box_visual(parent, "BreakTape%d" % side, Vector3(0.10, 0.02, 0.5),
			Vector3(x, 0.95, -12.72), _paint_yellow, Vector3(18.0, 0.0, 0.0))
	BuildKit.box_visual(parent, "BreakTapeLine", Vector3(3.1, 0.02, 0.06),
		Vector3(-10.85, 0.92, -12.85), _paint_yellow, Vector3(0.0, 0.0, -7.0))
	# A short, dead-ended energy trace left in the floor: it shows where the
	# resonance *should* continue, and stops exactly at the missing relay.
	var trace: StandardMaterial3D = MaterialLibrary.emissive(Color(0.35, 0.86, 1.0), 0.55)
	for index: int in range(5):
		BuildKit.box_visual(parent, "BreakTrace%d" % index, Vector3(0.10, 0.008, 0.52),
			Vector3(-9.15 - float(index) * 0.42, 0.012, -10.1 - float(index) * 0.24), trace,
			Vector3(0.0, 30.0, 0.0))
	for index: int in range(3):
		BuildKit.box_visual(parent, "BreakTraceDead%d" % index, Vector3(0.08, 0.006, 0.38),
			Vector3(-11.55 + float(index) * 0.20, 0.013, -12.05 - float(index) * 0.16),
			MaterialLibrary.emissive(Color(1.0, 0.42, 0.16), 0.5), Vector3(0.0, -14.0, 0.0))


## Physical fixtures for the three scripted guide lights. Without a visible
## lamp the scripted light changes read as the cave randomly getting brighter.
func _build_guide_fixtures(parent: Node3D) -> void:
	var fixture: StandardMaterial3D = MaterialLibrary.metal(Color(0.24, 0.27, 0.30), 0.55, 0.72)
	for entry: Array in [
		["Alcove", Vector3(-7.2, 3.60, -1.2), Color(1.0, 0.70, 0.38)],
		["CrystalB", Vector3(-17.9, 2.40, -13.8), Color(1.0, 0.70, 0.38)],
		["Ledge", Vector3(-11.2, 5.60, -20.2), Color(0.42, 0.90, 1.0)],
	]:
		var key: String = str(entry[0])
		var spot: Vector3 = entry[1] as Vector3
		var color: Color = entry[2] as Color
		BuildKit.cylinder_visual(parent, "Guide%sPost" % key, 0.05, spot.y, Vector3(spot.x, spot.y * 0.5, spot.z), fixture)
		BuildKit.box_visual(parent, "Guide%sArm" % key, Vector3(0.5, 0.06, 0.06), Vector3(spot.x + 0.22, spot.y - 0.02, spot.z), fixture)
		BuildKit.cylinder_visual(parent, "Guide%sShade" % key, 0.17, 0.16, Vector3(spot.x + 0.44, spot.y - 0.10, spot.z),
			fixture, Vector3.ZERO, 0.06)
		BuildKit.sphere_visual(parent, "Guide%sBulb" % key, 0.075, Vector3(spot.x + 0.44, spot.y - 0.20, spot.z),
			MaterialLibrary.emissive(color, 1.2))
		BuildKit.cylinder_visual(parent, "Guide%sFoot" % key, 0.12, 0.05, Vector3(spot.x, 0.025, spot.z), fixture)


## The exit vista: beyond the gate the player sees the core corridor with a
## huge crystal silhouette. Deliberately unresolved (Act 5 is not built).
func _build_core_vista(parent: Node3D) -> void:
	var arch_metal: StandardMaterial3D = MaterialLibrary.metal(Color(0.20, 0.23, 0.26), 0.6, 0.7)
	var core_light: StandardMaterial3D = MaterialLibrary.emissive(Color(0.58, 0.42, 1.0), 2.0)
	for index: int in range(2):
		var x: float = 9.4 + float(index) * 3.4
		for side: int in range(2):
			BuildKit.static_box(parent, "CoreArchPost%d_%d" % [index, side], Vector3(0.34, 5.2, 0.34),
				Vector3(x, 2.6, -27.3 if side == 0 else -22.7), arch_metal)
		BuildKit.box_visual(parent, "CoreArchBeam%d" % index, Vector3(0.40, 0.34, 5.0), Vector3(x, 5.05, -25.0), arch_metal)
		BuildKit.box_visual(parent, "CoreArchGlow%d" % index, Vector3(0.42, 0.06, 4.4), Vector3(x, 4.85, -25.0), core_light)
	# Large crystal mass at the end of the corridor, outside the completion
	# trigger but clearly readable through the open door.
	var core: EchoCrystal = EchoCrystal.new()
	core.name = "CoreSilhouette"
	core.position = Vector3(15.6, 0.2, -25.0)
	core.rotation.y = deg_to_rad(-90.0)
	parent.add_child(core)
	core.build("core_vista", CRYSTAL_DIR + CLUSTER_WEST, "violet", 2.4, -90.0, true)
	core.set_memory_awake(false)
	BuildKit.omni_light(parent, "CoreGlow", Vector3(14.4, 3.2, -25.0), Color(0.55, 0.38, 1.0), 4.5, 12.0, false)
	BuildKit.omni_light(parent, "CoreFloorGlow", Vector3(12.0, 0.6, -25.0), Color(0.36, 0.24, 0.72), 2.0, 7.0, false)
	# Floor grating and hazard edge in the corridor: the industrial path to the
	# core, not a bare rock tube.
	for index: int in range(5):
		BuildKit.box_visual(parent, "CorridorGrate%d" % index, Vector3(1.9, 0.03, 1.05),
			Vector3(6.8 + float(index) * 2.0, 0.015, -25.0), MaterialLibrary.metal(Color(0.16, 0.18, 0.20), 0.7, 0.4))
	for side: int in range(2):
		BuildKit.box_visual(parent, "CorridorHazard%d" % side, Vector3(15.0, 0.02, 0.22),
			Vector3(11.0, 0.02, -22.65 if side == 0 else -27.35), _paint_yellow)
	# Low-frequency rumble particles: dust drifting down in the core light.
	_add_dust(parent, "CoreDust", Vector3(13.5, 2.4, -25.0), Vector3(3.8, 2.4, 2.2), 26)


## Gentle floor relief and wall skirts for the eye. Visual only: the walkable
## slab keeps its exact collision, so no new air walls or snag points.
func _build_ground_relief(parent: Node3D) -> void:
	# Low outcrops against the walls, where the player never needs to walk.
	for entry: Array in [
		[Vector3(-20.2, 0.0, 1.0), 0.9, 20.0], [Vector3(-20.4, 0.0, -7.0), 1.0, -15.0],
		[Vector3(20.4, 0.0, -6.0), 1.0, 45.0], [Vector3(20.2, 0.0, -18.0), 1.1, 70.0],
		[Vector3(-17.5, 0.0, -28.0), 0.9, 10.0], [Vector3(15.8, 0.0, -28.2), 0.9, -20.0],
	]:
		_add_rock(parent, ROCK_APRON, entry[0] as Vector3, float(entry[1]), float(entry[2]), true, "floor")
	# Narrow gravel aprons along the wall base tie the shell to the floor.
	var apron: StandardMaterial3D = StandardMaterial3D.new()
	apron.albedo_texture = load("res://assets/textures/gravel_ballast_base.png") as Texture2D
	apron.albedo_color = Color(0.34, 0.34, 0.36)
	apron.roughness = 0.98
	apron.uv1_scale = Vector3(6.0, 6.0, 1.0)
	for entry: Array in [
		[Vector3(-19.4, 0.014, -6.0), Vector3(1.6, 0.02, 12.0), 4.0],
		[Vector3(19.4, 0.014, -8.0), Vector3(1.6, 0.02, 14.0), -3.0],
		[Vector3(-7.0, 0.014, -27.4), Vector3(12.0, 0.02, 1.5), 2.0],
		[Vector3(6.0, 0.014, 12.4), Vector3(10.0, 0.02, 1.4), 0.0],
	]:
		BuildKit.box_visual(parent, "WallApron%d" % int((entry[0] as Vector3).x * 10.0 + (entry[0] as Vector3).z),
			entry[1] as Vector3, entry[0] as Vector3, apron, Vector3(0.0, float(entry[2]), 0.0))
	# A few flat paving stones create a worn path from spawn to the hammer
	# without raising the collision surface.
	for index: int in range(7):
		var z: float = 4.4 - float(index) * 1.35
		BuildKit.box_visual(parent, "PathStone%d" % index, Vector3(1.5, 0.018, 1.0),
			Vector3(0.15 + sin(float(index) * 1.7) * 0.45, 0.012, z), _slab_material(Color(0.46, 0.47, 0.50), 0.24),
			Vector3(0.0, float(index) * 17.0, 0.0))
	# Spawn-side dressing: the first view was a large empty brown floor. Small
	# rubble, two planks and a cable coil break it up without adding collision.
	for entry: Array in [
		[Vector3(0.2, 0.0, 4.55), 0.34, 20.0], [Vector3(1.9, 0.0, 4.15), 0.40, -35.0],
		[Vector3(-1.8, 0.0, 3.75), 0.31, 70.0], [Vector3(2.7, 0.0, 5.3), 0.28, 15.0],
		[Vector3(-2.6, 0.0, 5.1), 0.36, 110.0], [Vector3(-3.1, 0.0, 3.1), 0.30, -60.0],
	]:
		_add_rock(parent, ROCK_TONGUE if int(float(entry[1]) * 100.0) % 2 == 0 else ROCK_APRON,
			entry[0] as Vector3, float(entry[1]), float(entry[2]), false, "floor")
	BuildKit.box_visual(parent, "SpawnPlankA", Vector3(1.5, 0.035, 0.24), Vector3(1.1, 0.02, 4.9), _wood, Vector3(0.0, 26.0, 0.0))
	BuildKit.box_visual(parent, "SpawnPlankB", Vector3(1.2, 0.03, 0.20), Vector3(-1.6, 0.018, 5.6), _wood, Vector3(0.0, -18.0, 0.0))
	# Cable coil and a floor grate at the spawn threshold.
	var coil: MeshInstance3D = MeshInstance3D.new()
	coil.name = "SpawnCableCoil"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.31
	torus.rings = 18
	torus.ring_segments = 6
	coil.mesh = torus
	coil.material_override = _dark_metal
	coil.position = Vector3(3.0, 0.05, 4.0)
	coil.rotation_degrees = Vector3(82.0, 0.0, 12.0)
	parent.add_child(coil)
	BuildKit.box_visual(parent, "SpawnGrate", Vector3(1.6, 0.025, 0.9), Vector3(-0.6, 0.014, 4.2),
		MaterialLibrary.metal(Color(0.18, 0.20, 0.22), 0.7, 0.3))
	for index: int in range(4):
		BuildKit.box_visual(parent, "SpawnGrateSlot%d" % index, Vector3(1.4, 0.005, 0.05),
			Vector3(-0.6, 0.028, 3.92 + float(index) * 0.19), _rock_material)


func _slab_material(tint: Color, uv_scale: float) -> ShaderMaterial:
	var material: ShaderMaterial = _rock_material.duplicate() as ShaderMaterial
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("uv_scale", uv_scale)
	return material


func _build_lights(parent: Node3D) -> void:
	# Key lighting: warm industrial work lights against cyan crystal fill.
	BuildKit.omni_light(parent, "SpawnLamp", Vector3(-1.0, 3.6, 8.0), Color(1.0, 0.72, 0.42), 3.2, 12.0, false)
	BuildKit.spot_light(parent, "HammerKey", Vector3(0.8, 9.2, -2.8), Vector3(0.0, 0.2, -3.4), Color(1.0, 0.76, 0.48), 7.5, 22.0, 40.0, true)
	BuildKit.omni_light(parent, "BellCyan", Vector3(0.0, 2.4, -5.2), Color(0.30, 0.82, 1.0), 3.0, 7.0, false)
	BuildKit.omni_light(parent, "EastWorkLamp", Vector3(12.0, 4.8, -11.5), Color(1.0, 0.74, 0.44), 4.2, 15.0, false)
	BuildKit.omni_light(parent, "EastCyan", Vector3(16.0, 4.0, -14.0), Color(0.26, 0.76, 1.0), 3.0, 9.0, false)
	BuildKit.omni_light(parent, "TrackFill", Vector3(16.0, 3.4, -9.5), Color(1.0, 0.72, 0.40), 2.2, 8.0, false)
	BuildKit.omni_light(parent, "WestLamp", Vector3(-9.0, 3.2, -7.0), Color(1.0, 0.70, 0.40), 2.8, 10.0, false)
	BuildKit.omni_light(parent, "WestPathLamp", Vector3(-5.6, 4.6, 3.6), Color(1.0, 0.68, 0.38), 2.4, 9.0, false)
	BuildKit.omni_light(parent, "WestPathCool", Vector3(-9.0, 3.2, -2.6), Color(0.30, 0.62, 0.90), 1.6, 8.0, false)
	BuildKit.spot_light(parent, "WestShaft", Vector3(-12.0, 9.5, 1.0), Vector3(-15.0, 0.5, 1.0), Color(0.52, 0.72, 1.0), 3.0, 14.0, 34.0, false)
	BuildKit.omni_light(parent, "WestViolet", Vector3(-17.5, 3.0, -16.0), Color(0.62, 0.40, 1.0), 3.4, 9.5, false)
	BuildKit.omni_light(parent, "AlcoveLamp", Vector3(-17.7, 4.0, 2.5), Color(1.0, 0.66, 0.34), 0.85, 7.0, false)
	BuildKit.omni_light(parent, "AlcoveFill", Vector3(-17.8, 3.4, 1.2), Color(1.0, 0.68, 0.40), 2.0, 7.5, false)
	BuildKit.omni_light(parent, "AlcoveFill2", Vector3(-7.6, 4.4, 5.4), Color(0.42, 0.66, 0.92), 1.4, 6.5, false)
	BuildKit.omni_light(parent, "CrystalBLamp", Vector3(-16.8, 2.4, -12.5), Color(1.0, 0.66, 0.34), 0.0, 6.0, false)
	BuildKit.omni_light(parent, "LedgeLamp", Vector3(-11.2, 5.6, -20.2), Color(0.40, 0.90, 1.0), 0.0, 8.0, false)
	BuildKit.omni_light(parent, "FinalKey", Vector3(-3.0, 6.4, -24.0), Color(0.48, 0.82, 1.0), 4.5, 12.0, true)
	BuildKit.omni_light(parent, "GateWarm", Vector3(2.4, 3.0, -24.6), Color(1.0, 0.62, 0.28), 2.0, 6.5, false)
	BuildKit.spot_light(parent, "GateKey", Vector3(0.0, 4.8, -25.0), Vector3(3.2, 2.0, -25.0), Color(1.0, 0.80, 0.55), 3.4, 9.0, 36.0, false)
	BuildKit.spot_light(parent, "FinalShaft", Vector3(-2.0, 11.0, -25.0), Vector3(-3.0, 0.6, -25.5), Color(0.50, 0.86, 1.0), 5.0, 16.0, 32.0, false)
	BuildKit.spot_light(parent, "ShelfShaft", Vector3(14.0, 10.5, -9.0), Vector3(15.0, 2.0, -12.0), Color(0.62, 0.80, 1.0), 4.0, 17.0, 36.0, false)
	BuildKit.omni_light(parent, "WestPathFill", Vector3(-7.0, 6.0, -13.0), Color(0.30, 0.44, 0.66), 1.8, 14.0, false)
	BuildKit.omni_light(parent, "FinalFill", Vector3(0.0, 7.5, -20.0), Color(0.30, 0.46, 0.68), 1.6, 12.0, false)
	BuildKit.omni_light(parent, "LedgeFill", Vector3(-11.0, 6.0, -19.0), Color(0.36, 0.52, 0.72), 1.6, 10.0, false)
	BuildKit.omni_light(parent, "FinalWallFill", Vector3(-4.0, 4.5, -25.0), Color(0.38, 0.58, 0.80), 2.2, 11.0, false)
	BuildKit.omni_light(parent, "SpawnBack", Vector3(0.0, 3.2, 6.6), Color(1.0, 0.70, 0.42), 2.2, 9.0, false)
	BuildKit.omni_light(parent, "HammerFill", Vector3(0.0, 3.4, -2.4), Color(1.0, 0.80, 0.55), 2.0, 9.5, false)
	BuildKit.omni_light(parent, "EntranceFill", Vector3(0.0, 3.2, 3.5), Color(0.55, 0.72, 1.0), 2.0, 10.0, false)
	BuildKit.omni_light(parent, "CenterFloorFill", Vector3(0.0, 2.4, 1.4), Color(1.0, 0.80, 0.55), 1.6, 8.0, false)
	BuildKit.omni_light(parent, "CenterRim", Vector3(0.0, 5.0, -8.0), Color(0.28, 0.44, 0.68), 1.5, 18.0, false)

	# Small cold fill from the side galleries.
	BuildKit.omni_light(parent, "FillA", Vector3(-12.0, 6.0, 6.0), Color(0.22, 0.34, 0.55), 1.8, 18.0, false)
	BuildKit.omni_light(parent, "FillB", Vector3(10.0, 7.0, 8.0), Color(0.22, 0.34, 0.55), 1.6, 18.0, false)

	# Broad, shadowless bounce. Without these the generated cave walls were lit
	# only by ambient and read as a black void beyond the spot-light pools.
	BuildKit.omni_light(parent, "CaveBounceNorth", Vector3(0.0, 5.5, -17.0), Color(0.30, 0.42, 0.62), 1.7, 32.0, false)
	BuildKit.omni_light(parent, "CaveBounceSouth", Vector3(0.0, 5.2, 4.0), Color(0.34, 0.30, 0.44), 1.4, 28.0, false)
	BuildKit.omni_light(parent, "CaveBounceWest", Vector3(-14.0, 5.0, -14.0), Color(0.26, 0.36, 0.54), 1.4, 24.0, false)
	BuildKit.omni_light(parent, "CaveBounceEast", Vector3(14.0, 6.0, -18.0), Color(0.28, 0.40, 0.56), 1.3, 24.0, false)
	BuildKit.omni_light(parent, "CeilingWash", Vector3(-2.0, 9.4, -11.0), Color(0.26, 0.34, 0.50), 1.2, 36.0, false)
	BuildKit.omni_light(parent, "NorthEastWash", Vector3(13.0, 7.6, -22.0), Color(0.30, 0.42, 0.62), 1.6, 24.0, false)
	BuildKit.omni_light(parent, "NorthWestWash", Vector3(-14.0, 7.2, -25.0), Color(0.28, 0.38, 0.60), 1.5, 22.0, false)
	BuildKit.omni_light(parent, "SouthWash", Vector3(8.0, 6.4, 9.0), Color(0.30, 0.34, 0.50), 1.3, 22.0, false)
