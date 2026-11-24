class_name FreightArena
extends RefCounted
## Builds the collapsed stope, its two loading docks, the overhead rail and the
## suspended crystal freight platform.
##
## The arena is shared by Resonance 04 (integrated into the existing crystal
## cave) and by the two-instance co-op slice (a compact test room). It owns the
## spatial truth for the freight loop:
##
##   west loading dock (crystal)  ->  suspended platform  ->  east loading dock
##        far_park_x = -14.7              rail y = 8.0          near_park_x = -8.8
##
## The pit floor at y = -3.2 is the safe maintenance area. A ramp on its east
## side returns to the cave floor, and the platform's rescue winch can be
## lowered from either dock. No fall is a dead end.

const PIT_MIN_X := -15.5
const PIT_MAX_X := -8.0
const PIT_MIN_Z := -1.5
const PIT_MAX_Z := 7.5
const PIT_FLOOR_Y := -3.2
const DECK_Y := 2.6
const SERVICE_Y := 0.2
const RAIL_Y := 8.0
const CENTER_Z := 3.0
const NEAR_PARK_X := -8.8
const FAR_PARK_X := -14.7
const NEAR_DOCK_MIN_X := -8.0
const NEAR_DOCK_MAX_X := -4.2
const FAR_DOCK_MIN_X := -18.2
const FAR_DOCK_MAX_X := -15.5
const DOCK_MIN_Z := 0.0
const DOCK_MAX_Z := 5.0
const NOTCH_MIN_Z := 1.3
const NOTCH_MAX_Z := 4.7
const STAIR_LOW_X := -1.0
const STAIR_HIGH_X := -4.2
const STAIR_Z := 3.8
const STAIR_WIDTH := 1.6
const FAR_CRYSTAL_POSITION := Vector3(-17.0, 2.75, 3.0)
const ACCIDENT_TRIGGER_X := -12.2

var _ceiling_override: float = 0.0
var _rock: ShaderMaterial
var _steel: StandardMaterial3D
var _dark: StandardMaterial3D
var _rust: StandardMaterial3D
var _hazard: StandardMaterial3D
var _grid: StandardMaterial3D
var _warm: StandardMaterial3D
var _cool: StandardMaterial3D
var _font: SystemFont


func build(parent: Node3D, room_mode: bool, with_receiver: bool) -> Dictionary:
	var root: Node3D = Node3D.new()
	root.name = "FreightArena"
	parent.add_child(root)
	_make_materials()
	_ceiling_override = 9.2 if room_mode else 0.0
	if room_mode:
		_build_room(root)
	else:
		_build_cave_floor(root)
	_build_pit(root)
	_build_docks(root)
	_build_stair(root)
	_build_overhead_rail(root)
	var platform: FreightPlatform = FreightPlatform.new()
	root.add_child(platform)
	platform.configure(NEAR_PARK_X, FAR_PARK_X, CENTER_Z, DECK_Y, SERVICE_Y, RAIL_Y)
	var rail_parts: Dictionary = _build_trolley_and_cables(root)
	platform.bind_cables(rail_parts["trolley"] as Node3D, rail_parts["cables"] as Array[MeshInstance3D],
		rail_parts["tops"] as Array[Vector3], rail_parts["decks"] as Array[Vector3])
	_build_warning_fixtures(root, platform)
	_build_dock_controls(root, platform)
	_build_lights(root)
	var receiver: Node3D = null
	if with_receiver:
		receiver = _build_receiver(root, platform)
	return {
		"root": root,
		"platform": platform,
		"receiver": receiver,
		"far_crystal_position": FAR_CRYSTAL_POSITION,
		"near_park_x": NEAR_PARK_X,
		"far_park_x": FAR_PARK_X,
	}


func _make_materials() -> void:
	_rock = MaterialLibrary.rock()
	_steel = MaterialLibrary.metal(Color(0.36, 0.40, 0.44), 0.46, 0.82)
	_dark = MaterialLibrary.metal(Color(0.11, 0.13, 0.15), 0.66, 0.5)
	_rust = MaterialLibrary.metal(Color(0.44, 0.24, 0.12), 0.84, 0.25)
	_hazard = MaterialLibrary.painted(Color(0.86, 0.55, 0.10), 0.55)
	_grid = MaterialLibrary.metal(Color(0.20, 0.23, 0.26), 0.70, 0.40)
	_warm = MaterialLibrary.emissive(Color(1.0, 0.66, 0.32), 1.6)
	_cool = MaterialLibrary.emissive(Color(0.34, 0.86, 1.0), 1.4)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "SimHei", "sans-serif"])
	_font.allow_system_fallback = true


# ------------------------------------------------------------------- room

func _build_room(parent: Node3D) -> void:
	# A compact test room. The co-op slice should be readable and cheap; the
	# real cave shell is deliberately not duplicated here.
	var floor_min_x: float = -31.0
	var floor_max_x: float = 8.0
	var floor_min_z: float = -15.0
	var floor_max_z: float = 21.0
	_floor_with_hole(parent, floor_min_x, floor_max_x, floor_min_z, floor_max_z)
	BuildKit.static_box(parent, "RoomEast", Vector3(1.0, 9.0, 37.0), Vector3(8.5, 4.5, 3.0), _rock)
	BuildKit.static_box(parent, "RoomWest", Vector3(1.0, 9.0, 37.0), Vector3(-31.5, 4.5, 3.0), _rock)
	BuildKit.static_box(parent, "RoomNorth", Vector3(40.0, 9.0, 1.0), Vector3(-11.5, 4.5, -15.5), _rock)
	BuildKit.static_box(parent, "RoomSouth", Vector3(40.0, 9.0, 1.0), Vector3(-11.5, 4.5, 21.5), _rock)
	BuildKit.static_box(parent, "RoomCeiling", Vector3(40.0, 1.0, 37.0), Vector3(-11.5, 9.4, 3.0), _rock)
	for entry: Array in [
		[Vector3(-26.0, 1.1, 12.0), 2.4, 20.0], [Vector3(2.0, 1.1, 13.0), 1.8, -30.0],
		[Vector3(-27.0, 1.1, -8.0), 2.0, 55.0], [Vector3(1.0, 1.1, -9.0), 1.6, 12.0],
	]:
		BuildKit.static_cylinder(parent, "RoomRock%d" % int(absf((entry[0] as Vector3).x) * 10.0 + absf((entry[0] as Vector3).z)),
			float(entry[1]) * 0.55, 2.2, entry[0] as Vector3, _rock)
	BuildKit.box_visual(parent, "RoomPath", Vector3(9.0, 0.02, 10.0), Vector3(-2.0, 0.012, 6.0), _grid)


func _build_cave_floor(parent: Node3D) -> void:
	# Exactly the same 44 x 44 cave footprint as the original CaveFloor, but
	# split around the stope so the hole is real collision, not a floating prop.
	_floor_with_hole(parent, -22.0, 22.0, -30.0, 14.0)


func _floor_with_hole(parent: Node3D, min_x: float, max_x: float, min_z: float, max_z: float) -> void:
	var thickness: float = 0.60
	var y_center: float = -thickness * 0.5
	var west_width: float = PIT_MIN_X - min_x
	var east_width: float = max_x - PIT_MAX_X
	var north_depth: float = PIT_MIN_Z - min_z
	var south_depth: float = max_z - PIT_MAX_Z
	BuildKit.static_box(parent, "FreightFloorWest", Vector3(west_width, thickness, max_z - min_z),
		Vector3(min_x + west_width * 0.5, y_center, (min_z + max_z) * 0.5), _rock)
	BuildKit.static_box(parent, "FreightFloorEast", Vector3(east_width, thickness, max_z - min_z),
		Vector3(PIT_MAX_X + east_width * 0.5, y_center, (min_z + max_z) * 0.5), _rock)
	BuildKit.static_box(parent, "FreightFloorNorth", Vector3(PIT_MAX_X - PIT_MIN_X, thickness, north_depth),
		Vector3((PIT_MIN_X + PIT_MAX_X) * 0.5, y_center, min_z + north_depth * 0.5), _rock)
	BuildKit.static_box(parent, "FreightFloorSouth", Vector3(PIT_MAX_X - PIT_MIN_X, thickness, south_depth),
		Vector3((PIT_MIN_X + PIT_MAX_X) * 0.5, y_center, PIT_MAX_Z + south_depth * 0.5), _rock)


# -------------------------------------------------------------------- pit

func _build_pit(parent: Node3D) -> void:
	var width: float = PIT_MAX_X - PIT_MIN_X
	var depth: float = PIT_MAX_Z - PIT_MIN_Z
	var center_x: float = (PIT_MIN_X + PIT_MAX_X) * 0.5
	var center_z: float = (PIT_MIN_Z + PIT_MAX_Z) * 0.5
	# Pit floor: a maintenance deck, not a void.
	BuildKit.static_box(parent, "PitFloor", Vector3(width, 0.40, depth), Vector3(center_x, PIT_FLOOR_Y - 0.20, center_z), _rock)
	BuildKit.box_visual(parent, "PitDeckPlate", Vector3(width - 0.60, 0.06, depth - 0.60),
		Vector3(center_x, PIT_FLOOR_Y + 0.03, center_z), _grid)
	for index: int in range(8):
		var x: float = PIT_MIN_X + 0.9 + float(index) * 0.82
		BuildKit.box_visual(parent, "PitDeckRib%d" % index, Vector3(0.05, 0.015, depth - 1.2),
			Vector3(x, PIT_FLOOR_Y + 0.065, center_z), _dark)
	BuildKit.box_visual(parent, "PitHazardN", Vector3(width - 0.5, 0.02, 0.18),
		Vector3(center_x, PIT_FLOOR_Y + 0.07, PIT_MIN_Z + 0.25), _hazard)
	BuildKit.box_visual(parent, "PitHazardS", Vector3(width - 0.5, 0.02, 0.18),
		Vector3(center_x, PIT_FLOOR_Y + 0.07, PIT_MAX_Z - 0.25), _hazard)
	# Drain and a work crate.
	BuildKit.cylinder_visual(parent, "PitDrain", 0.34, 0.03, Vector3(center_x + 1.4, PIT_FLOOR_Y + 0.08, center_z + 2.4), _dark)
	BuildKit.box_visual(parent, "PitCrate", Vector3(0.8, 0.8, 0.8), Vector3(PIT_MIN_X + 1.1, PIT_FLOOR_Y + 0.40, PIT_MIN_Z + 1.0), _rust, Vector3(0.0, 18.0, 0.0))
	BuildKit.box_visual(parent, "PitCrateBand", Vector3(0.84, 0.08, 0.84), Vector3(PIT_MIN_X + 1.1, PIT_FLOOR_Y + 0.44, PIT_MIN_Z + 1.0), _dark, Vector3(0.0, 18.0, 0.0))
	# The four stope walls. Tops sit just under the floor slab so the hole edge
	# reads as a cut in the rock, not a raised curb.
	var wall_top: float = -0.05
	var wall_bottom: float = PIT_FLOOR_Y - 0.10
	var wall_height: float = wall_top - wall_bottom
	var wall_y: float = (wall_top + wall_bottom) * 0.5
	BuildKit.static_box(parent, "PitWallNorth", Vector3(width + 0.5, wall_height, 0.5),
		Vector3(center_x, wall_y, PIT_MIN_Z - 0.25), _rock)
	BuildKit.static_box(parent, "PitWallSouth", Vector3(width + 0.5, wall_height, 0.5),
		Vector3(center_x, wall_y, PIT_MAX_Z + 0.25), _rock)
	BuildKit.static_box(parent, "PitWallWest", Vector3(0.5, wall_height, depth + 0.5),
		Vector3(PIT_MIN_X - 0.25, wall_y, center_z), _rock)
	BuildKit.static_box(parent, "PitWallEast", Vector3(0.5, wall_height, depth + 0.5),
		Vector3(PIT_MAX_X + 0.25, wall_y, center_z), _rock)
	# Strata bands and sheet-pile ribs make the walls read as mined rock rather
	# than four flat slabs.
	for index: int in range(5):
		var y: float = PIT_FLOOR_Y + 0.35 + float(index) * 0.62
		BuildKit.box_visual(parent, "PitStrataN%d" % index, Vector3(width - 0.05, 0.05, 0.02),
			Vector3(center_x, y, PIT_MIN_Z + 0.01), _dark)
		BuildKit.box_visual(parent, "PitStrataS%d" % index, Vector3(width - 0.05, 0.05, 0.02),
			Vector3(center_x, y, PIT_MAX_Z - 0.01), _dark)
	for index: int in range(6):
		var z: float = PIT_MIN_Z + 0.6 + float(index) * 1.35
		BuildKit.box_visual(parent, "PitPileE%d" % index, Vector3(0.06, wall_height - 0.2, 0.16),
			Vector3(PIT_MAX_X - 0.02, wall_y, z), _steel)
		BuildKit.cylinder_visual(parent, "PitPileBoltE%d" % index, 0.05, 0.10,
			Vector3(PIT_MAX_X - 0.08, wall_top - 0.35, z), _rust, Vector3(90.0, 0.0, 0.0))
	for index: int in range(5):
		var z: float = PIT_MIN_Z + 0.8 + float(index) * 1.55
		BuildKit.box_visual(parent, "PitStrutW%d" % index, Vector3(0.10, 0.10, 0.10),
			Vector3(PIT_MIN_X + 0.05, PIT_FLOOR_Y + 1.2 + float(index % 2) * 0.9, z), _rust)
	# Exposed crystal veins in the stope walls. They are embedded, not floating.
	for entry: Array in [
		[Vector3(PIT_MIN_X + 0.18, PIT_FLOOR_Y + 0.35, 1.8), 1.1, "cyan", 86.0],
		[Vector3(PIT_MIN_X + 0.20, PIT_FLOOR_Y + 0.15, 5.7), 0.7, "violet", 92.0],
		[Vector3(center_x - 1.2, PIT_FLOOR_Y + 0.25, PIT_MIN_Z + 0.20), 0.9, "cyan", 4.0],
		[Vector3(center_x + 1.6, PIT_FLOOR_Y + 0.10, PIT_MAX_Z - 0.20), 0.75, "violet", 176.0],
	]:
		var spot: Vector3 = entry[0] as Vector3
		var crystal: CrystalVisual = CrystalVisual.new()
		crystal.name = "PitVein"
		parent.add_child(crystal)
		crystal.position = spot
		crystal.rotation_degrees = Vector3(74.0, float(entry[3]), 8.0)
		crystal.build("res://assets/crystals/" + ("res_crys_blade_cyan_a_lod0.glb" if str(entry[2]) == "cyan" else "res_crys_blade_violet_a_lod0.glb"),
			str(entry[2]), float(entry[1]), false)
		crystal.set_focus_visible(false)
		crystal.set_pulse(0.30)
	# Rim railings. The two berth gaps are where the platform parks.
	_rim_rail(parent, Vector3(PIT_MIN_X, 0.0, PIT_MIN_Z), Vector3(PIT_MAX_X, 0.0, PIT_MIN_Z), "N")
	_rim_rail(parent, Vector3(PIT_MIN_X, 0.0, PIT_MAX_Z), Vector3(PIT_MAX_X, 0.0, PIT_MAX_Z), "S")
	_rim_rail(parent, Vector3(PIT_MIN_X, 0.0, PIT_MIN_Z), Vector3(PIT_MIN_X, 0.0, NOTCH_MIN_Z), "W1")
	_rim_rail(parent, Vector3(PIT_MIN_X, 0.0, NOTCH_MAX_Z), Vector3(PIT_MIN_X, 0.0, PIT_MAX_Z), "W2")
	_rim_rail(parent, Vector3(PIT_MAX_X, 0.0, PIT_MIN_Z), Vector3(PIT_MAX_X, 0.0, NOTCH_MIN_Z), "E1")
	_rim_rail(parent, Vector3(PIT_MAX_X, 0.0, NOTCH_MAX_Z), Vector3(PIT_MAX_X, 0.0, PIT_MAX_Z), "E2")
	# Floor-level safety chain across the east berth, leaving the maintenance
	# ramp's landing (z 2.9..3.5) open. This is below the platform, so it never
	# blocks the dock; it stops a player from walking straight into the shaft.
	_rim_rail(parent, Vector3(PIT_MAX_X, 0.0, NOTCH_MIN_Z), Vector3(PIT_MAX_X, 0.0, 2.9), "EB1")
	_rim_rail(parent, Vector3(PIT_MAX_X, 0.0, 3.5), Vector3(PIT_MAX_X, 0.0, NOTCH_MAX_Z), "EB2")
	# Berth markers: yellow posts at the gap, so the opening is intentional.
	for entry: Array in [
		[Vector3(PIT_MIN_X, 0.0, NOTCH_MIN_Z), "FWN"], [Vector3(PIT_MIN_X, 0.0, NOTCH_MAX_Z), "FWS"],
		[Vector3(PIT_MAX_X, 0.0, NOTCH_MIN_Z), "FEN"], [Vector3(PIT_MAX_X, 0.0, NOTCH_MAX_Z), "FES"],
	]:
		var spot: Vector3 = entry[0] as Vector3
		BuildKit.cylinder_visual(parent, "BerthPost" + str(entry[1]), 0.07, 1.25,
			spot + Vector3(0.0, 0.625, 0.0), _hazard)
		BuildKit.sphere_visual(parent, "BerthLight" + str(entry[1]), 0.06,
			spot + Vector3(0.0, 1.30, 0.0), MaterialLibrary.emissive(Color(0.36, 0.92, 1.0), 1.1))
	# The maintenance ramp on the east wall: pit floor -> cave floor. 1.4 m wide
	# so a 0.76 m player capsule can stand on it without clipping the stope wall.
	BuildKit.ramp(parent, "PitRamp", 1.4, 3.6, 3.2, Vector3(PIT_MAX_X - 0.65, PIT_FLOOR_Y, PIT_MAX_Z - 0.3), 0.0, _steel)
	BuildKit.static_box(parent, "PitRampLanding", Vector3(1.4, 0.20, 0.80),
		Vector3(PIT_MAX_X - 0.65, -0.10, PIT_MAX_Z - 4.30), _steel)
	BuildKit.box_visual(parent, "PitRampHandrail", Vector3(0.06, 0.06, 4.82),
		Vector3(PIT_MAX_X - 1.45, PIT_FLOOR_Y + 2.10, PIT_MAX_Z - 1.80), _hazard, Vector3(41.6, 0.0, 0.0))
	for index: int in range(4):
		var t: float = 0.2 + float(index) * 0.2
		var z: float = lerpf(PIT_MAX_Z - 0.3, PIT_MAX_Z - 3.9, t)
		var y: float = lerpf(PIT_FLOOR_Y, 0.0, t)
		BuildKit.cylinder_visual(parent, "PitRampPost%d" % index, 0.035, 1.0,
			Vector3(PIT_MAX_X - 1.45, y + 0.5, z), _dark)
	# Stencils.
	_sign(parent, "断层 · 04-B", Vector3(PIT_MAX_X + 0.65, 2.05, PIT_MIN_Z + 0.3), -90.0, 0.0045, _hazard)
	_sign(parent, "安全维修层", Vector3(PIT_MAX_X - 0.10, PIT_FLOOR_Y + 1.55, PIT_MAX_Z - 0.15), 180.0, 0.004, _cool)
	# Dust in the stope.
	var dust: CPUParticles3D = CPUParticles3D.new()
	dust.name = "PitDust"
	dust.amount = 20
	dust.lifetime = 8.0
	dust.preprocess = 3.0
	dust.emitting = true
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(width * 0.4, 1.4, depth * 0.4)
	dust.direction = Vector3(0.0, 1.0, 0.0)
	dust.spread = 180.0
	dust.gravity = Vector3(0.0, 0.01, 0.0)
	dust.initial_velocity_min = 0.01
	dust.initial_velocity_max = 0.08
	dust.scale_amount_min = 0.02
	dust.scale_amount_max = 0.05
	var dust_mesh: SphereMesh = SphereMesh.new()
	dust_mesh.radius = 0.04
	dust_mesh.height = 0.08
	dust_mesh.radial_segments = 5
	dust_mesh.rings = 3
	dust.mesh = dust_mesh
	var dust_material: StandardMaterial3D = StandardMaterial3D.new()
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.albedo_color = Color(0.55, 0.78, 1.0, 0.22)
	dust_material.emission_enabled = true
	dust_material.emission = Color(0.45, 0.72, 1.0)
	dust_material.emission_energy_multiplier = 0.35
	dust.material_override = dust_material
	dust.position = Vector3(center_x, PIT_FLOOR_Y + 1.8, center_z)
	parent.add_child(dust)


func _rim_rail(parent: Node3D, from_point: Vector3, to_point: Vector3, label: String) -> void:
	var length: float = from_point.distance_to(to_point)
	if length < 0.4:
		return
	var mid: Vector3 = (from_point + to_point) * 0.5
	var along_x: bool = absf(to_point.x - from_point.x) > absf(to_point.z - from_point.z)
	var post_count: int = maxi(2, int(ceil(length / 1.5)) + 1)
	for index: int in range(post_count):
		var t: float = float(index) / float(post_count - 1)
		var spot: Vector3 = from_point.lerp(to_point, t)
		BuildKit.cylinder_visual(parent, "RimPost%s_%d" % [label, index], 0.045, 1.08,
			spot + Vector3(0.0, 0.54, 0.0), _steel)
		BuildKit.sphere_visual(parent, "RimReflect%s_%d" % [label, index], 0.035,
			spot + Vector3(0.0, 1.10, 0.0), MaterialLibrary.emissive(Color(1.0, 0.68, 0.24), 0.7))
	var top_size: Vector3 = Vector3(length, 0.06, 0.06) if along_x else Vector3(0.06, 0.06, length)
	var low_size: Vector3 = Vector3(length, 0.04, 0.04) if along_x else Vector3(0.04, 0.04, length)
	BuildKit.box_visual(parent, "RimTop" + label, top_size, mid + Vector3(0.0, 1.06, 0.0), _hazard)
	BuildKit.box_visual(parent, "RimLow" + label, low_size, mid + Vector3(0.0, 0.58, 0.0), _steel)
	# A real collider so the player cannot walk through the visible rail. It is
	# only 1 m tall: jumping over it is possible, which is a readable risk.
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "RimBody" + label
	body.position = mid + Vector3(0.0, 0.55, 0.0)
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(length, 1.0, 0.10) if along_x else Vector3(0.10, 1.0, length)
	shape.shape = box
	body.add_child(shape)


# ------------------------------------------------------------------ docks

func _build_docks(parent: Node3D) -> void:
	_build_dock(parent, "Near", NEAR_DOCK_MIN_X, NEAR_DOCK_MAX_X, true)
	_build_dock(parent, "Far", FAR_DOCK_MIN_X, FAR_DOCK_MAX_X, false)
	# A loading stand on the far dock: the crystal's starting socket.
	var socket_x: float = FAR_CRYSTAL_POSITION.x
	var socket_z: float = FAR_CRYSTAL_POSITION.z
	BuildKit.box_visual(parent, "FarCrystalBase", Vector3(1.10, 0.10, 1.10),
		Vector3(socket_x, DECK_Y + 0.05, socket_z), _dark)
	BuildKit.box_visual(parent, "FarCrystalRing", Vector3(0.92, 0.03, 0.92),
		Vector3(socket_x, DECK_Y + 0.11, socket_z), MaterialLibrary.emissive(Color(0.95, 0.62, 0.20), 0.75))
	for index: int in range(4):
		var angle: float = TAU * float(index) / 4.0
		BuildKit.box_visual(parent, "FarSocketLip%d" % index, Vector3(0.50, 0.14, 0.07),
			Vector3(socket_x + cos(angle) * 0.45, DECK_Y + 0.17, socket_z + sin(angle) * 0.45),
			_rust, Vector3(0.0, rad_to_deg(angle) + 90.0, 0.0))
	_sign(parent, "西侧装货台", Vector3(FAR_DOCK_MIN_X + 0.5, DECK_Y + 2.0, DOCK_MAX_Z - 0.5), 180.0, 0.004, _warm)
	_sign(parent, "东侧装货台", Vector3(NEAR_DOCK_MAX_X - 0.5, DECK_Y + 2.0, DOCK_MAX_Z - 0.5), 180.0, 0.004, _warm)


func _build_dock(parent: Node3D, prefix: String, min_x: float, max_x: float, near: bool) -> void:
	var thickness: float = 0.24
	var y: float = DECK_Y - thickness * 0.5
	# The dock is split around a berth notch so the platform can park flush.
	if near:
		# East block spans most of the dock; the west 0.8 m is the north/south lobes.
		BuildKit.static_box(parent, prefix + "DeckMain", Vector3(max_x - (min_x + 0.8), thickness, DOCK_MAX_Z - DOCK_MIN_Z),
			Vector3((min_x + 0.8 + max_x) * 0.5, y, (DOCK_MIN_Z + DOCK_MAX_Z) * 0.5), _steel)
		BuildKit.static_box(parent, prefix + "DeckLobeN", Vector3(0.8, thickness, NOTCH_MIN_Z - DOCK_MIN_Z),
			Vector3(min_x + 0.4, y, (DOCK_MIN_Z + NOTCH_MIN_Z) * 0.5), _steel)
		BuildKit.static_box(parent, prefix + "DeckLobeS", Vector3(0.8, thickness, DOCK_MAX_Z - NOTCH_MAX_Z),
			Vector3(min_x + 0.4, y, (NOTCH_MAX_Z + DOCK_MAX_Z) * 0.5), _steel)
	else:
		BuildKit.static_box(parent, prefix + "DeckMain", Vector3((max_x - 0.8) - min_x, thickness, DOCK_MAX_Z - DOCK_MIN_Z),
			Vector3((min_x + max_x - 0.8) * 0.5, y, (DOCK_MIN_Z + DOCK_MAX_Z) * 0.5), _steel)
		BuildKit.static_box(parent, prefix + "DeckLobeN", Vector3(0.8, thickness, NOTCH_MIN_Z - DOCK_MIN_Z),
			Vector3(max_x - 0.4, y, (DOCK_MIN_Z + NOTCH_MIN_Z) * 0.5), _steel)
		BuildKit.static_box(parent, prefix + "DeckLobeS", Vector3(0.8, thickness, DOCK_MAX_Z - NOTCH_MAX_Z),
			Vector3(max_x - 0.4, y, (NOTCH_MAX_Z + DOCK_MAX_Z) * 0.5), _steel)
	# Grating, frame and hazard edge.
	BuildKit.box_visual(parent, prefix + "Grate", Vector3(max_x - min_x - 0.2, 0.02, DOCK_MAX_Z - DOCK_MIN_Z - 0.2),
		Vector3((min_x + max_x) * 0.5, DECK_Y + 0.012, (DOCK_MIN_Z + DOCK_MAX_Z) * 0.5), _grid)
	for index: int in range(7):
		var x: float = min_x + 0.5 + float(index) * ((max_x - min_x - 1.0) / 6.0)
		BuildKit.box_visual(parent, prefix + "GrateRib%d" % index, Vector3(0.04, 0.012, DOCK_MAX_Z - DOCK_MIN_Z - 0.3),
			Vector3(x, DECK_Y + 0.022, (DOCK_MIN_Z + DOCK_MAX_Z) * 0.5), _dark)
	BuildKit.box_visual(parent, prefix + "EdgeStripe", Vector3(max_x - min_x - 0.2, 0.02, 0.12),
		Vector3((min_x + max_x) * 0.5, DECK_Y + 0.03, DOCK_MIN_Z + 0.08), _hazard)
	BuildKit.box_visual(parent, prefix + "EdgeStripeS", Vector3(max_x - min_x - 0.2, 0.02, 0.12),
		Vector3((min_x + max_x) * 0.5, DECK_Y + 0.03, DOCK_MAX_Z - 0.08), _hazard)
	# Support legs with cross braces. The far dock keeps both legs west of the
	# berth notch so the platform cannot collide with a column.
	var leg_xs: Array[float] = []
	leg_xs.append(min_x + 0.35)
	leg_xs.append(max_x - 0.35 if near else max_x - 1.65)
	var leg_zs: Array[float] = []
	leg_zs.append(DOCK_MIN_Z + 0.35)
	leg_zs.append(DOCK_MAX_Z - 0.35)
	for lx: float in leg_xs:
		for lz: float in leg_zs:
			BuildKit.box_visual(parent, prefix + "Leg", Vector3(0.18, DECK_Y - 0.24, 0.18),
				Vector3(lx, (DECK_Y - 0.24) * 0.5, lz), _dark)
			BuildKit.box_visual(parent, prefix + "Foot", Vector3(0.46, 0.08, 0.46),
				Vector3(lx, 0.04, lz), _rust)
	for lz: float in leg_zs:
		BuildKit.box_visual(parent, prefix + "BraceX", Vector3(max_x - min_x - 0.6, 0.08, 0.08),
			Vector3((min_x + max_x) * 0.5, 0.95, lz), _rust, Vector3(0.0, 0.0, 8.0))
	# Under-deck framing: the dock underside is a large plate visible from the
	# spawn approach. A dark soffit, spine, cross beams and a hazard edge keep it
	# from reading as one untextured grey slab.
	BuildKit.box_visual(parent, prefix + "UnderSoffit", Vector3(max_x - min_x - 0.18, 0.02, DOCK_MAX_Z - DOCK_MIN_Z - 0.18),
		Vector3((min_x + max_x) * 0.5, DECK_Y - 0.25, (DOCK_MIN_Z + DOCK_MAX_Z) * 0.5), _grid)
	BuildKit.box_visual(parent, prefix + "UnderSpine", Vector3(0.18, 0.18, DOCK_MAX_Z - DOCK_MIN_Z - 0.3),
		Vector3((min_x + max_x) * 0.5, DECK_Y - 0.34, (DOCK_MIN_Z + DOCK_MAX_Z) * 0.5), _dark)
	for index: int in range(5):
		var bz: float = DOCK_MIN_Z + 0.7 + float(index) * 0.9
		BuildKit.box_visual(parent, prefix + "UnderBeam%d" % index, Vector3(max_x - min_x - 0.4, 0.22, 0.16),
			Vector3((min_x + max_x) * 0.5, DECK_Y - 0.34, bz), _dark)
		BuildKit.box_visual(parent, prefix + "UnderGusset%d" % index, Vector3(0.10, 0.55, 0.10),
			Vector3(min_x + 0.4, DECK_Y - 0.62, bz), _rust, Vector3(0.0, 0.0, 24.0))
	BuildKit.box_visual(parent, prefix + "UnderHazard", Vector3(max_x - min_x - 0.3, 0.10, 0.08),
		Vector3((min_x + max_x) * 0.5, DECK_Y - 0.44, DOCK_MAX_Z - 0.10), _hazard)
	# Railings on the non-berth outer edges. The near dock leaves a gap at the
	# stair landing (z 2.9..4.7) on its east edge.
	if near:
		_dock_rail(parent, prefix, Vector3(max_x, DECK_Y, DOCK_MIN_Z), Vector3(max_x, DECK_Y, 2.85), "E1")
		_dock_rail(parent, prefix, Vector3(max_x, DECK_Y, 4.75), Vector3(max_x, DECK_Y, DOCK_MAX_Z), "E2")
		_dock_rail(parent, prefix, Vector3(min_x, DECK_Y, DOCK_MIN_Z), Vector3(max_x, DECK_Y, DOCK_MIN_Z), "N")
		_dock_rail(parent, prefix, Vector3(min_x, DECK_Y, DOCK_MAX_Z), Vector3(max_x, DECK_Y, DOCK_MAX_Z), "S")
	else:
		_dock_rail(parent, prefix, Vector3(min_x, DECK_Y, DOCK_MIN_Z), Vector3(min_x, DECK_Y, DOCK_MAX_Z), "W")
		_dock_rail(parent, prefix, Vector3(min_x, DECK_Y, DOCK_MIN_Z), Vector3(max_x, DECK_Y, DOCK_MIN_Z), "N")
		_dock_rail(parent, prefix, Vector3(min_x, DECK_Y, DOCK_MAX_Z), Vector3(max_x, DECK_Y, DOCK_MAX_Z), "S")


func _dock_rail(parent: Node3D, prefix: String, from_point: Vector3, to_point: Vector3, label: String) -> void:
	var length: float = from_point.distance_to(to_point)
	if length < 0.4:
		return
	var mid: Vector3 = (from_point + to_point) * 0.5
	var along_x: bool = absf(to_point.x - from_point.x) > absf(to_point.z - from_point.z)
	var count: int = maxi(2, int(ceil(length / 1.6)) + 1)
	for index: int in range(count):
		var t: float = float(index) / float(count - 1)
		var spot: Vector3 = from_point.lerp(to_point, t)
		BuildKit.cylinder_visual(parent, prefix + "RailPost" + label + str(index), 0.04, 1.05,
			spot + Vector3(0.0, 0.525, 0.0), _steel)
	BuildKit.box_visual(parent, prefix + "RailTop" + label,
		Vector3(length, 0.06, 0.06) if along_x else Vector3(0.06, 0.06, length),
		mid + Vector3(0.0, 1.02, 0.0), _hazard)
	BuildKit.box_visual(parent, prefix + "RailMid" + label,
		Vector3(length, 0.04, 0.04) if along_x else Vector3(0.04, 0.04, length),
		mid + Vector3(0.0, 0.56, 0.0), _steel)


func _build_stair(parent: Node3D) -> void:
	var rise: float = DECK_Y
	var run: float = absf(STAIR_HIGH_X - STAIR_LOW_X)
	var slope_length: float = sqrt(run * run + rise * rise)
	var stair_body: StaticBody3D = BuildKit.ramp(parent, "DockStair", STAIR_WIDTH, run, rise, Vector3(STAIR_LOW_X, 0.0, STAIR_Z), 90.0, _steel)
	# The ramp is a solid slab; from the spawn its underside is a large grey
	# plane. A dark soffit and joists turn it into a built stair underside.
	BuildKit.box_visual(stair_body, "DockStairSoffit", Vector3(STAIR_WIDTH - 0.08, 0.03, slope_length + 0.05),
		Vector3(0.0, -0.165, 0.0), _dark)
	for index: int in range(5):
		var bz: float = -slope_length * 0.42 + float(index) * slope_length * 0.21
		BuildKit.box_visual(stair_body, "DockStairJoist%d" % index, Vector3(STAIR_WIDTH - 0.12, 0.10, 0.10),
			Vector3(0.0, -0.24, bz), _rust)
	for side: int in range(2):
		var sx: float = -STAIR_WIDTH * 0.5 + 0.12 if side == 0 else STAIR_WIDTH * 0.5 - 0.12
		BuildKit.box_visual(stair_body, "DockStairUndersideRail%d" % side, Vector3(0.10, 0.10, slope_length - 0.1),
			Vector3(sx, -0.25, 0.0), _dark)
	# The smooth collider is dressed as a built stair: side stringers, ribs,
	# hazard strip, toe board and floor supports. Without this the spawn view
	# was dominated by one large untextured grey triangle.
	var slope: float = sqrt(run * run + rise * rise)
	var slope_angle: float = rad_to_deg(atan2(rise, run))
	for side: int in range(2):
		var z: float = STAIR_Z - STAIR_WIDTH * 0.5 - 0.03 if side == 0 else STAIR_Z + STAIR_WIDTH * 0.5 + 0.03
		BuildKit.box_visual(parent, "DockStairStringer%d" % side, Vector3(slope, 0.42, 0.06),
			Vector3((STAIR_LOW_X + STAIR_HIGH_X) * 0.5, rise * 0.5 - 0.08, z), _dark,
			Vector3(0.0, 0.0, -slope_angle))
		BuildKit.box_visual(parent, "DockStairStripe%d" % side, Vector3(slope, 0.06, 0.07),
			Vector3((STAIR_LOW_X + STAIR_HIGH_X) * 0.5, rise * 0.5 + 0.16, z), _hazard,
			Vector3(0.0, 0.0, -slope_angle))
		BuildKit.box_visual(parent, "DockStairToe%d" % side, Vector3(slope, 0.10, 0.035),
			Vector3((STAIR_LOW_X + STAIR_HIGH_X) * 0.5, rise * 0.5 + 0.26, z), _dark,
			Vector3(0.0, 0.0, -slope_angle))
		for index: int in range(4):
			var t: float = 0.18 + float(index) * 0.22
			var x: float = lerpf(STAIR_LOW_X, STAIR_HIGH_X, t)
			var y: float = rise * t
			BuildKit.box_visual(parent, "DockStairRib%d_%d" % [side, index], Vector3(0.10, 0.62, 0.04),
				Vector3(x, y - 0.14, z), _rust)
	# Supports to the floor under the slope.
	for index: int in range(2):
		var t: float = 0.30 + float(index) * 0.42
		var x: float = lerpf(STAIR_LOW_X, STAIR_HIGH_X, t)
		var height: float = rise * t
		BuildKit.box_visual(parent, "DockStairSupport%d" % index, Vector3(0.18, height, 0.18),
			Vector3(x, height * 0.5, STAIR_Z - STAIR_WIDTH * 0.32), _dark)
		BuildKit.box_visual(parent, "DockStairFoot%d" % index, Vector3(0.46, 0.08, 0.46),
			Vector3(x, 0.04, STAIR_Z - STAIR_WIDTH * 0.32), _rust)
	BuildKit.box_visual(parent, "DockStairBrace", Vector3(run * 0.75, 0.08, 0.08),
		Vector3((STAIR_LOW_X + STAIR_HIGH_X) * 0.5, rise * 0.35, STAIR_Z - STAIR_WIDTH * 0.32), _rust,
		Vector3(0.0, 0.0, slope_angle))
	# Visual steps over the smooth collider: reliable walking, readable stairs.
	var steps: int = 12
	for index: int in range(steps):
		var t: float = (float(index) + 0.5) / float(steps)
		var x: float = lerpf(STAIR_LOW_X, STAIR_HIGH_X, t)
		var y: float = rise * t
		BuildKit.box_visual(parent, "DockStep%d" % index, Vector3(run / float(steps) + 0.04, 0.10, STAIR_WIDTH - 0.10),
			Vector3(x, y - 0.05, STAIR_Z), _grid)
	for side: int in range(2):
		var z: float = STAIR_Z - STAIR_WIDTH * 0.5 if side == 0 else STAIR_Z + STAIR_WIDTH * 0.5
		BuildKit.box_visual(parent, "DockStairRail%d" % side, Vector3(run + 0.2, 0.06, 0.06),
			Vector3((STAIR_LOW_X + STAIR_HIGH_X) * 0.5, rise * 0.5 + 0.95, z), _hazard, Vector3(0.0, 0.0, rad_to_deg(atan2(rise, run))))
		for index: int in range(4):
			var t: float = (float(index) + 0.5) / 4.0
			var x: float = lerpf(STAIR_LOW_X, STAIR_HIGH_X, t)
			var y: float = rise * t
			BuildKit.cylinder_visual(parent, "DockStairPost%d_%d" % [side, index], 0.035, 0.95,
				Vector3(x, y + 0.475, z), _steel)
	_sign(parent, "↑ 悬吊货运", Vector3(STAIR_LOW_X + 0.2, 2.55, STAIR_Z + 1.05), 180.0, 0.0035, _warm)


# ------------------------------------------------------------------- rail

func _build_overhead_rail(parent: Node3D) -> void:
	var min_x: float = FAR_DOCK_MIN_X - 1.4
	var max_x: float = NEAR_DOCK_MAX_X + 0.6
	var length: float = max_x - min_x
	var mid_x: float = (min_x + max_x) * 0.5
	BuildKit.box_visual(parent, "FreightRailWeb", Vector3(length, 0.34, 0.16), Vector3(mid_x, RAIL_Y, CENTER_Z), _dark)
	BuildKit.box_visual(parent, "FreightRailTop", Vector3(length, 0.06, 0.36), Vector3(mid_x, RAIL_Y + 0.19, CENTER_Z), _steel)
	BuildKit.box_visual(parent, "FreightRailBottom", Vector3(length, 0.06, 0.30), Vector3(mid_x, RAIL_Y - 0.19, CENTER_Z), _steel)
	for index: int in range(11):
		var x: float = min_x + 0.6 + float(index) * ((length - 1.2) / 10.0)
		BuildKit.box_visual(parent, "RailTie%d" % index, Vector3(0.06, 0.10, 0.62), Vector3(x, RAIL_Y + 0.24, CENTER_Z), _rust)
	# Hangers from the real ceiling / room roof.
	for index: int in range(5):
		var x: float = min_x + 1.2 + float(index) * ((length - 2.4) / 4.0)
		var top: float = _ceiling_y(x, CENTER_Z) + 0.35
		var hanger_height: float = maxf(top - (RAIL_Y + 0.22), 0.5)
		BuildKit.box_visual(parent, "RailHanger%d" % index, Vector3(0.10, hanger_height, 0.10),
			Vector3(x, RAIL_Y + 0.22 + hanger_height * 0.5, CENTER_Z), _dark)
		BuildKit.box_visual(parent, "RailAnchor%d" % index, Vector3(0.52, 0.16, 0.40),
			Vector3(x, top - 0.08, CENTER_Z), _rust)
		BuildKit.cylinder_visual(parent, "RailBolt%d" % index, 0.055, 0.12,
			Vector3(x, top - 0.18, CENTER_Z), _steel)
	# Warning board where the rail crosses the fault.
	_sign(parent, "共振断层 · 减速", Vector3(mid_x, RAIL_Y - 0.55, CENTER_Z - 0.24), 180.0, 0.0035, _hazard)


func _ceiling_y(x: float, z: float) -> float:
	if _ceiling_override > 0.0:
		return _ceiling_override
	return R04CaveShell.ceiling_y(x, z)


func _build_trolley_and_cables(parent: Node3D) -> Dictionary:
	var trolley: Node3D = Node3D.new()
	trolley.name = "FreightTrolley"
	trolley.position = Vector3(NEAR_PARK_X, RAIL_Y, CENTER_Z)
	parent.add_child(trolley)
	BuildKit.box_visual(trolley, "TrolleyBody", Vector3(1.10, 0.34, 0.46), Vector3(0.0, -0.30, 0.0), _steel)
	BuildKit.box_visual(trolley, "TrolleyStripe", Vector3(1.12, 0.06, 0.48), Vector3(0.0, -0.46, 0.0), _hazard)
	for index: int in range(4):
		var x: float = -0.42 if index % 2 == 0 else 0.42
		var z: float = -0.20 if index < 2 else 0.20
		BuildKit.cylinder_visual(trolley, "TrolleyWheel%d" % index, 0.11, 0.08,
			Vector3(x, 0.19, z), _rust, Vector3(90.0, 0.0, 0.0))
	# Four cable lugs at the trolley corners.
	var tops: Array[Vector3] = []
	var decks: Array[Vector3] = []
	var cables: Array[MeshInstance3D] = []
	var positions: Array[Vector2] = [Vector2(-0.46, -0.16), Vector2(-0.46, 0.16), Vector2(0.46, -0.16), Vector2(0.46, 0.16)]
	for index: int in range(4):
		var offset: Vector2 = positions[index]
		var top: Vector3 = Vector3(offset.x, -0.34, offset.y)
		tops.append(top)
		BuildKit.cylinder_visual(trolley, "CableLugTop%d" % index, 0.055, 0.14,
			top + Vector3(0.0, 0.03, 0.0), _rust)
		var cable: MeshInstance3D = MeshInstance3D.new()
		cable.name = "FreightCable%d" % index
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = 0.035
		mesh.bottom_radius = 0.035
		mesh.height = 1.0
		mesh.radial_segments = 8
		mesh.rings = 1
		cable.mesh = mesh
		cable.material_override = _dark
		cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(cable)
		cables.append(cable)
	# Deck anchors match the four cable lugs on the platform.
	decks.append(Vector3(-1.42, 0.22, -1.42))
	decks.append(Vector3(-1.42, 0.22, 1.42))
	decks.append(Vector3(1.42, 0.22, -1.42))
	decks.append(Vector3(1.42, 0.22, 1.42))
	return {"trolley": trolley, "cables": cables, "tops": tops, "decks": decks}


func _build_warning_fixtures(parent: Node3D, platform: FreightPlatform) -> void:
	# Three resonance pylons: near rim, far dock, pit floor. They brighten
	# together during the pre-shock warning, so the cause is spatial and visible.
	var pylon_data: Array[Array] = [
		[Vector3(PIT_MAX_X + 0.75, 0.0, PIT_MIN_Z + 0.45), 2.35, "近侧"],
		[Vector3(FAR_DOCK_MIN_X + 0.45, DECK_Y, 0.35), 1.45, "远侧"],
		[Vector3(PIT_MIN_X + 1.0, PIT_FLOOR_Y, PIT_MAX_Z - 0.9), 2.85, "底层"],
	]
	for entry: Array in pylon_data:
		var spot: Vector3 = entry[0] as Vector3
		var height: float = float(entry[1])
		var label: String = str(entry[2])
		BuildKit.static_cylinder(parent, "PylonBase" + label, 0.34, 0.16, spot + Vector3(0.0, 0.08, 0.0), _dark)
		BuildKit.cylinder_visual(parent, "PylonPost" + label, 0.075, height,
			spot + Vector3(0.0, height * 0.5 + 0.16, 0.0), _steel)
		for index: int in range(4):
			var angle: float = TAU * float(index) / 4.0
			BuildKit.cylinder_visual(parent, "PylonBrace" + label + str(index), 0.025, 0.7,
				spot + Vector3(cos(angle) * 0.22, 0.50, sin(angle) * 0.22),
				_rust, Vector3(rad_to_deg(angle) * 0.0, 0.0, 18.0))
		var rod: MeshInstance3D = BuildKit.box_visual(parent, "PylonRod" + label,
			Vector3(0.16, height * 0.52, 0.16), spot + Vector3(0.0, height * 0.66 + 0.16, 0.0),
			MaterialLibrary.emissive(Color(0.45, 0.82, 1.0), 0.35))
		var crystal: CrystalVisual = CrystalVisual.new()
		crystal.name = "PylonCrystal" + label
		parent.add_child(crystal)
		crystal.position = spot + Vector3(0.0, height + 0.18, 0.0)
		crystal.rotation_degrees = Vector3(0.0, float(pylon_data.find(entry)) * 47.0, 0.0)
		crystal.build("res://assets/crystals/res_crys_cluster_env02_a_lod0.glb", "cyan", 0.62, false)
		crystal.set_focus_visible(false)
		crystal.set_pulse(0.15)
		BuildKit.omni_light(parent, "PylonLight" + label,
			spot + Vector3(0.0, height * 0.8 + 0.2, 0.0), Color(0.36, 0.86, 1.0), 0.65, 4.2, false)
		platform.register_warning_pylon(rod, 0.35)


func _build_dock_controls(parent: Node3D, platform: FreightPlatform) -> void:
	# Near dock.
	_build_pedestal(parent, "Near", Vector3(-5.05, DECK_Y, 0.55), platform, "call", "near", "呼叫平台")
	_build_pedestal(parent, "NearW", Vector3(-5.05, DECK_Y, 4.45), platform, "winch", "near", "救援绞盘")
	# Far dock.
	_build_pedestal(parent, "Far", Vector3(-17.15, DECK_Y, 0.55), platform, "call", "far", "呼叫平台")
	_build_pedestal(parent, "FarW", Vector3(-17.15, DECK_Y, 4.45), platform, "winch", "far", "救援绞盘")
	# Alcove floor (under the far dock): a self-rescue pedestal.
	_build_floor_pedestal(parent, "AlcoveCall", Vector3(-17.45, 0.0, 6.55), platform, "call", "far", "呼叫平台")
	_build_floor_pedestal(parent, "AlcoveWinch", Vector3(-16.55, 0.0, 6.55), platform, "winch", "far", "放下绞盘")


func _build_pedestal(parent: Node3D, prefix: String, base: Vector3, platform: FreightPlatform, kind: String, dock_id: String, label_text: String) -> void:
	BuildKit.box_visual(parent, "Pedestal" + prefix, Vector3(0.34, 1.02, 0.34), base + Vector3(0.0, 0.51, 0.0), _dark)
	BuildKit.box_visual(parent, "PedestalFace" + prefix, Vector3(0.30, 0.20, 0.06),
		base + Vector3(0.0, 0.92, 0.16), MaterialLibrary.emissive(
			Color(0.32, 0.88, 1.0) if kind == "call" else Color(1.0, 0.66, 0.24), 0.9), Vector3(22.0, 0.0, 0.0))
	BuildKit.cylinder_visual(parent, "PedestalLever" + prefix, 0.028, 0.34,
		base + Vector3(0.0, 1.10, 0.0), _hazard, Vector3(18.0, 0.0, 0.0))
	var control: FreightControl = FreightControl.new()
	control.name = "Control_" + prefix
	control.position = base + Vector3(0.0, 1.18, 0.0)
	parent.add_child(control)
	control.setup(platform, kind, dock_id, 2.3)
	_sign(parent, label_text, base + Vector3(0.0, 1.48, 0.0), 0.0, 0.0028,
		MaterialLibrary.emissive(Color(0.85, 0.92, 1.0), 0.7), 26.0)


func _build_floor_pedestal(parent: Node3D, prefix: String, base: Vector3, platform: FreightPlatform, kind: String, dock_id: String, label_text: String) -> void:
	BuildKit.box_visual(parent, "Pedestal" + prefix, Vector3(0.30, 1.00, 0.30), base + Vector3(0.0, 0.50, 0.0), _dark)
	BuildKit.box_visual(parent, "PedestalFace" + prefix, Vector3(0.26, 0.18, 0.06),
		base + Vector3(0.0, 0.88, 0.14), MaterialLibrary.emissive(
			Color(0.32, 0.88, 1.0) if kind == "call" else Color(1.0, 0.66, 0.24), 0.9), Vector3(22.0, 0.0, 0.0))
	var control: FreightControl = FreightControl.new()
	control.name = "Control_" + prefix
	control.position = base + Vector3(0.0, 1.10, 0.0)
	parent.add_child(control)
	control.setup(platform, kind, dock_id, 3.0)
	_sign(parent, label_text, base + Vector3(0.0, 1.42, 0.0), 0.0, 0.0026,
		MaterialLibrary.emissive(Color(0.85, 0.92, 1.0), 0.7), 22.0)


func _build_receiver(parent: Node3D, platform: FreightPlatform) -> Node3D:
	var receiver: Node3D = Node3D.new()
	receiver.name = "FreightReceiver"
	receiver.position = Vector3(-5.05, DECK_Y, 2.5)
	parent.add_child(receiver)
	BuildKit.box_visual(receiver, "ReceiverBase", Vector3(1.30, 0.10, 1.30), Vector3(0.0, 0.05, 0.0), _dark)
	BuildKit.box_visual(receiver, "ReceiverRing", Vector3(1.10, 0.03, 1.10), Vector3(0.0, 0.11, 0.0),
		MaterialLibrary.emissive(Color(0.95, 0.62, 0.20), 0.75))
	for index: int in range(4):
		var angle: float = TAU * float(index) / 4.0
		BuildKit.box_visual(receiver, "ReceiverLip%d" % index, Vector3(0.62, 0.18, 0.08),
			Vector3(cos(angle) * 0.56, 0.18, sin(angle) * 0.56), _rust, Vector3(0.0, rad_to_deg(angle) + 90.0, 0.0))
	BuildKit.cylinder_visual(receiver, "ReceiverPost", 0.045, 1.15, Vector3(0.55, 0.575, 0.55), _steel)
	var lamp: MeshInstance3D = BuildKit.sphere_visual(receiver, "ReceiverLamp", 0.09,
		Vector3(0.55, 1.20, 0.55), MaterialLibrary.emissive(Color(0.34, 1.0, 0.68), 0.6))
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sign(receiver, "卸货 · 交付", Vector3(0.0, 1.55, 0.62), 180.0, 0.003, MaterialLibrary.emissive(Color(0.55, 1.0, 0.74), 0.8), 30.0)
	var area: Area3D = Area3D.new()
	area.name = "ReceiverArea"
	area.collision_layer = 0
	area.collision_mask = 8
	area.monitoring = true
	receiver.add_child(area)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.8, 1.6, 1.8)
	shape.shape = box
	shape.position = Vector3(0.0, 0.8, 0.0)
	area.add_child(shape)
	area.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group("portable_crystal"):
			platform.mark_delivered(true)
	)
	return receiver


# ----------------------------------------------------------------- lights

func _build_lights(parent: Node3D) -> void:
	BuildKit.omni_light(parent, "FreightNearWarm", Vector3(-5.4, DECK_Y + 3.0, 2.6), Color(1.0, 0.72, 0.42), 3.2, 9.0, false)
	BuildKit.omni_light(parent, "FreightFarWarm", Vector3(-17.0, DECK_Y + 3.0, 2.6), Color(1.0, 0.72, 0.42), 2.8, 8.0, false)
	BuildKit.spot_light(parent, "FreightShaft", Vector3(-11.5, 10.4, 0.4), Vector3(-11.5, DECK_Y, 3.0), Color(0.52, 0.78, 1.0), 3.8, 20.0, 36.0, false)
	BuildKit.omni_light(parent, "FreightPitFill", Vector3(-11.5, PIT_FLOOR_Y + 1.4, 3.0), Color(0.28, 0.62, 0.92), 2.2, 8.0, false)
	BuildKit.omni_light(parent, "FreightPitWarm", Vector3(-9.2, PIT_FLOOR_Y + 2.2, 6.2), Color(1.0, 0.60, 0.30), 1.6, 6.0, false)
	BuildKit.omni_light(parent, "FreightRailFill", Vector3(-11.5, RAIL_Y - 1.2, 3.0), Color(0.30, 0.46, 0.68), 1.4, 10.0, false)
	BuildKit.omni_light(parent, "FreightFarCool", Vector3(-18.0, 4.2, 5.6), Color(0.34, 0.62, 0.92), 1.2, 6.0, false)
	BuildKit.omni_light(parent, "FreightStairWarm", Vector3(-2.5, 3.0, 4.0), Color(1.0, 0.68, 0.38), 1.8, 6.0, false)


# ------------------------------------------------------------------ signs

func _sign(parent: Node3D, text_value: String, position_value: Vector3, yaw_degrees: float, pixel_size: float, material: Material, font_size: float = 44.0) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "Sign"
	label.text = text_value
	label.font = _font
	label.font_size = int(font_size)
	label.pixel_size = pixel_size
	label.modulate = Color(0.96, 0.92, 0.82) if material is StandardMaterial3D and (material as StandardMaterial3D).emission_energy_multiplier < 1.0 else Color(1.0, 0.95, 0.86)
	label.outline_size = 6
	label.outline_modulate = Color(0.05, 0.04, 0.03, 0.9)
	label.position = position_value
	label.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	parent.add_child(label)
	return label
