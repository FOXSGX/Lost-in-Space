extends Node3D

# -----------------------------------------------------------------------------
# RepairYard - the severed-track bay that joins Resonance 02 and Resonance 03.
#
# This is NOT the Resonance 03 test room. The mechanical modules are reused
# verbatim (MisalignedRail, WinchMachine, WinchStation, WinchCable, WinchRig and
# the two lifting eyes), but every metre of geometry here is authored against the
# mine cart route, so the yard reads as a maintenance bay the miners built on the
# line:
#
#   s = 88.0          cart governor stop (moving_cart.FAULT_STOP)
#   s = 86.6 .. 90    fixed approach rail, ends in a torch-cut stub
#   s = 90 .. 96.4    swing section on a single-DOF hinge, currently 15 deg out
#   s = 96.35 .. 98.5 receiver cradle + painted reset line + lock socket
#   s = 98.5 .. 106   intact rail, then the crystal-mine dock and the way on
#
# Yard-local frame: x is the route direction, z = 0 is the track centre,
# y = 0 is the rail plane. The node is placed on route_pose(90) and shifted so
# its origin sits on the track centreline.
#
# Clearance contract (the cart passes this bay after the repair):
#   * the cart's hull is at y >= 0.70 over |z| <= 1.33 for x in 2.9 .. 4.3 (cab),
#     and the deck underside is at y = 1.77 everywhere.
#   * therefore every fixture inside |z| < 1.45 stays below y = 0.62, and
#     everything taller stands outside the hull (|z| >= 1.5) or beyond x = 7.
#   Violating this makes the repaired section clip the cart, which is exactly the
#   kind of integration bug that only shows up in motion.
# -----------------------------------------------------------------------------

const Kit := preload("res://act23/scripts/build/mesh_kit.gd")
const Mine := preload("res://act23/scripts/cart_environment.gd")
const Cart := preload("res://act23/scripts/moving_cart.gd")
const RailScript := preload("res://act23/scripts/winch/misaligned_rail.gd")
const MachineScript := preload("res://act23/scripts/winch/winch_machine.gd")
const StationScript := preload("res://act23/scripts/winch/winch_station.gd")
const CableScript := preload("res://act23/scripts/winch/winch_cable.gd")
const RigScript := preload("res://act23/scripts/winch/winch_rig.gd")

const YARD_S: float = 90.0
const TRACK_CENTRE_Z: float = 2.2
const GAUGE: float = 1.17
const SWING_LENGTH: float = 6.40
const APPROACH_START: float = -3.40
const RECEIVER_START: float = 6.35
const RECEIVER_END: float = 9.40
# The winch must stay on the south side of the hinge: the cable's pull direction
# is set by that geometry (hauling must close the 15 deg gap). What was missing
# was floor space, so the bay's south wall is cut back in cave_tunnel
# (bay_south_extra) instead of moving the machine across the line.
const WINCH_POS := Vector3(-2.60, 0.0, 3.40)
const WINCH_YAW: float = -34.0
const LOCK_POS := Vector3(7.95, 0.0, 2.45)

var stage: Node3D
var cart: AnimatableBody3D
var rail: AnimatableBody3D
var machine: Node3D
var station: Node3D
var cable: Node3D
var rig: Node3D
var lock_station: Node3D
var lock_pin_mesh: MeshInstance3D
var lock_lever: Node3D
var guide_wheel: Node3D
var guide_pedestal: Node3D
var bracket_prop: Node3D
var guide_sign: Node3D
var entrance_sign: Node3D
var entrance_light: OmniLight3D
var cut_lamps: Array[MeshInstance3D] = []
var beacon: MeshInstance3D
var beacon_light: OmniLight3D
var story_props: Array[Node3D] = []
var clock: float = 0.0
var _entrance_fade: float = 0.0
var _pin_t: float = 0.0

var m_rail: StandardMaterial3D
var m_dark: StandardMaterial3D
var m_hazard: StandardMaterial3D
var m_paint: StandardMaterial3D
var m_cut: StandardMaterial3D
var m_rust: StandardMaterial3D
var m_lamp_red: StandardMaterial3D
var m_lamp_amber: StandardMaterial3D
var m_lamp_green: StandardMaterial3D
var m_lamp_off: StandardMaterial3D
var m_paper: StandardMaterial3D

func build(controller: Node3D, cart_node: AnimatableBody3D, player: CharacterBody3D) -> void:
	stage = controller
	cart = cart_node
	transform = Cart.route_pose(YARD_S) * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, TRACK_CENTRE_Z))
	_materials()
	_build_approach()
	_build_swing()
	_build_receiver()
	_build_winch()
	_build_cable()
	_build_lock_station()
	_build_coop_fixtures()
	_build_warning()
	_build_story()
	_build_entrance()
	_build_rig(player)

func _materials() -> void:
	m_rail = Mine.material(Color("9aa9ab"), 0.55)
	m_rail.roughness = 0.42
	m_dark = Mine.material(Color("5d6d70"), 0.08)
	m_dark.roughness = 0.62
	m_hazard = Mine.material(Color("c98a3f"), 0.18)
	m_hazard.roughness = 0.55
	m_paint = Mine.material(Color("cfd8da"), 0.0)
	m_cut = Mine.material(Color("d9c6a4"), 0.62)
	m_cut.roughness = 0.34
	m_rust = Mine.material(Color("6d4a34"), 0.05)
	m_rust.roughness = 0.85
	m_lamp_red = Mine.material(Color("ff4a36"), 0.0, 2.6)
	m_lamp_amber = Mine.material(Color("ffb046"), 0.0, 1.8)
	m_lamp_green = Mine.material(Color("54ff9a"), 0.0, 2.2)
	m_lamp_off = Mine.material(Color("1a1e20"), 0.04)
	m_paper = Mine.material(Color("cbb894"), 0.0)
	m_paper.roughness = 0.92

# --- helpers ---------------------------------------------------------------

func _box(parent: Node3D, at_name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh: MeshInstance3D = Mine.box(parent, size, mat, at)
	mesh.name = at_name
	return mesh

func _solid(parent: Node3D, at_name: String, size: Vector3, at: Vector3, layer: int = 6) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = at_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = at
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)
	return body

func _collider_box(parent: StaticBody3D, at: Vector3, dimensions: Vector3) -> CollisionShape3D:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = dimensions
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	collider.position = at
	parent.add_child(collider)
	return collider

func _label(parent: Node3D, text: String, at: Vector3, points: int, tint: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = stage.get("ui_font") as Font
	label.font_size = points
	label.pixel_size = 0.0024
	label.outline_size = 6
	label.outline_modulate = Color(0.02, 0.03, 0.04, 0.92)
	label.modulate = tint
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	parent.add_child(label)
	return label

func _track(parent: Node3D, prefix: String, from_x: float, to_x: float, sleeper_step: float = 0.62) -> void:
	var length: float = to_x - from_x
	var middle: float = from_x + length * 0.5
	_box(parent, prefix + "Bed", Vector3(length, 0.10, 4.30), Vector3(middle, 0.01, 0.0),
		Mine.material(Color("8a7663"), 0.0))
	var index: int = 0
	var x: float = from_x + 0.30
	while x < to_x - 0.05:
		_box(parent, "%sSleeper%d" % [prefix, index], Vector3(0.18, 0.13, 3.30),
			Vector3(x, 0.14, 0.0), m_dark)
		index += 1
		x += sleeper_step
	for side: float in [-1.0, 1.0]:
		_box(parent, "%sRail%s" % [prefix, "L" if side < 0.0 else "R"],
			Vector3(length, 0.07, 0.12), Vector3(middle, 0.275, side * GAUGE), m_rail)

# --- fixed approach --------------------------------------------------------

func _build_approach() -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "Approach"
	add_child(holder)
	_track(holder, "Approach", APPROACH_START, -0.02, 0.62)
	# The cut: both rail ends are left short and raw, with scorch on the ballast,
	# so the break reads as "someone cut this" and not "geometry is missing".
	for side: float in [-1.0, 1.0]:
		var stub: MeshInstance3D = _box(holder, "CutFace%s" % str(side),
			Vector3(0.16, 0.080, 0.13), Vector3(-0.06, 0.275, side * GAUGE), m_cut)
		stub.rotation.z = 0.22
		_box(holder, "CutScorch%s" % str(side), Vector3(0.60, 0.012, 0.52),
			Vector3(-0.10, 0.072, side * GAUGE), Mine.material(Color("241d18"), 0.0))
	# Pivot hardware. Everything inside the hull envelope stays under y = 0.62:
	# the slew bearing and its pin sit UNDER the deck, and the tall cheeks stand
	# outside the cart at |z| = 1.55.
	_box(holder, "SlewPlate", Vector3(0.94, 0.12, 0.94), Vector3(0.0, 0.10, 0.0), m_dark)
	Kit.cylinder(holder, "SlewPin", 0.17, 0.36, Vector3(0.0, 0.22, 0.0), m_rust, "y", 20)
	_box(holder, "SlewCap", Vector3(0.66, 0.06, 0.66), Vector3(0.0, 0.43, 0.0), m_hazard)
	for side: float in [-1.0, 1.0]:
		_solid(holder, "HingePost%s" % str(side), Vector3(0.34, 1.20, 0.34),
			Vector3(0.0, 0.60, side * 2.32))
		_box(holder, "HingePostMesh%s" % str(side), Vector3(0.32, 1.15, 0.32),
			Vector3(0.0, 0.58, side * 2.32), m_dark)
		_box(holder, "HingeArm%s" % str(side), Vector3(0.60, 0.18, 0.24),
			Vector3(0.0, 1.14, side * 2.06), m_rail)
	_box(holder, "HingeBeamL", Vector3(0.22, 0.22, 1.10), Vector3(0.0, 1.14, -1.78), m_rail)
	_box(holder, "HingeBeamR", Vector3(0.22, 0.22, 1.10), Vector3(0.0, 1.14, 1.78), m_rail)

# --- the moving section ----------------------------------------------------

func _build_swing() -> void:
	rail = AnimatableBody3D.new()
	rail.name = "RailBody"
	rail.set_script(RailScript)
	rail.position = Vector3.ZERO
	add_child(rail)
	# Camera-only collision: the player walks the cave floor along the whole mine
	# (the track bed has never been a collider), but the lens must not pass
	# through the swing deck.
	rail.collision_layer = 4
	rail.collision_mask = 0
	_swing_collision()

	var deck_mat: StandardMaterial3D = Mine.material(Color("4a5559"), 0.05)
	deck_mat.roughness = 0.66
	_box(rail, "SwingDeck", Vector3(SWING_LENGTH, 0.09, 3.90),
		Vector3(SWING_LENGTH * 0.5, 0.065, 0.0), deck_mat)
	for side: float in [-1.0, 1.0]:
		_box(rail, "SideGirder%s" % ("L" if side < 0.0 else "R"),
			Vector3(SWING_LENGTH - 0.10, 0.32, 0.20),
			Vector3(SWING_LENGTH * 0.5, -0.14, side * 1.85), m_rail)
	for index: int in range(5):
		_box(rail, "CrossBrace%d" % index, Vector3(0.16, 0.18, 3.70),
			Vector3(0.75 + float(index) * 1.30, -0.10, 0.0), m_dark)
	for index: int in range(9):
		var x: float = 0.55 + float(index) * 0.68
		_box(rail, "SwingSleeper%d" % index, Vector3(0.34, 0.18, 3.30), Vector3(x, 0.20, 0.0), m_dark)
	for side: float in [-1.0, 1.0]:
		_box(rail, "SwingRail%s" % ("L" if side < 0.0 else "R"),
			Vector3(SWING_LENGTH - 0.04, 0.07, 0.12),
			Vector3(SWING_LENGTH * 0.5 + 0.01, 0.275, side * GAUGE), m_rail)
		_box(rail, "NoseBlock%s" % str(side), Vector3(0.26, 0.40, 0.34),
			Vector3(SWING_LENGTH - 0.16, 0.21, side * 1.48), m_hazard)
	_box(rail, "NoseFace", Vector3(0.16, 0.58, 3.60), Vector3(SWING_LENGTH - 0.08, 0.29, 0.0), m_hazard)
	_box(rail, "NoseCutL", Vector3(0.05, 0.080, 1.10), Vector3(SWING_LENGTH - 0.01, 0.275, GAUGE), m_cut)
	_box(rail, "NoseCutR", Vector3(0.05, 0.080, 1.10), Vector3(SWING_LENGTH - 0.01, 0.275, -GAUGE), m_cut)
	# Counterweight on the hinge side: the section reads as balanced hardware.
	_box(rail, "Counterweight", Vector3(0.86, 0.50, 2.60), Vector3(-0.44, 0.14, 0.0), m_dark)
	_box(rail, "CounterweightTrim", Vector3(0.90, 0.06, 2.64), Vector3(-0.44, 0.41, 0.0), m_hazard)
	# Hinge cheeks outside the cart envelope, capped with hazard paint.
	for side: float in [-1.0, 1.0]:
		_box(rail, "HingeCheek%s" % str(side), Vector3(0.58, 1.00, 0.16),
			Vector3(0.26, 0.60, side * 1.55), m_rail)
		Kit.cylinder(rail, "HingeCap%s" % str(side), 0.13, 0.24,
			Vector3(0.26, 0.84, side * 1.55), m_hazard, "z", 12)
	# Alignment pin + pointer live outside the hull: the pin has to land inside
	# the receiver jaw before the lock pin can be driven home.
	Kit.cylinder(rail, "AlignPin", 0.05, 0.70, Vector3(SWING_LENGTH - 0.12, 0.62, 1.62), m_rail, "y", 8)
	_box(rail, "AlignPointer", Vector3(0.52, 0.030, 0.12), Vector3(SWING_LENGTH - 0.34, 0.115, 0.0), m_paint)
	_make_anchor("eye_far", "前端吊耳", "轨道前端", Vector3(SWING_LENGTH - 0.35, 0.56, 0.0))
	_make_anchor("eye_mid", "中段吊耳", "靠近铰链", Vector3(2.45, 0.56, 0.0))

func _swing_collision() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "SwingCameraBlock"
	body.collision_layer = 4
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(SWING_LENGTH, 0.55, 3.90)
	shape.shape = box_shape
	shape.position = Vector3(SWING_LENGTH * 0.5, 0.02, 0.0)
	body.add_child(shape)
	rail.add_child(body)

func _make_anchor(id: String, label_text: String, note: String, local: Vector3) -> void:
	var anchor: Node3D = Node3D.new()
	anchor.name = "Anchor_" + id
	anchor.set_script(load("res://act23/scripts/winch/winch_anchor.gd") as Script)
	anchor.position = local
	anchor.set("anchor_id", StringName(id))
	anchor.set("display_name", label_text)
	anchor.set("kind", "track")
	anchor.set("leverage_note", note)
	anchor.set("hook_local", Vector3.ZERO)
	rail.add_child(anchor)
	_box(rail, "EyePlate_" + id, Vector3(0.46, 0.34, 0.26), local + Vector3(0.0, -0.10, 0.0), m_rail)
	Kit.cylinder(rail, "EyeRing_" + id, 0.105, 0.20, local,
		Kit.material(Color(0.95, 0.68, 0.20), 0.55, 0.3, Color(1.0, 0.60, 0.12), 0.9), "z", 16)

# --- receiver --------------------------------------------------------------

func _build_receiver() -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "Receiver"
	add_child(holder)
	_track(holder, "Receiver", RECEIVER_START, RECEIVER_END, 0.62)
	# Cradle: two posts outside the rail gauge catch the nose. Nothing crosses
	# over the rails, because the cart has to drive through here afterwards.
	for side: float in [-1.0, 1.0]:
		_solid(holder, "CradlePost%s" % str(side), Vector3(0.30, 1.05, 0.28),
			Vector3(RECEIVER_START + 0.25, 0.52, side * 2.10))
		_box(holder, "CradlePostMesh%s" % str(side), Vector3(0.28, 1.00, 0.26),
			Vector3(RECEIVER_START + 0.25, 0.50, side * 2.10), m_rail)
		var jaw: MeshInstance3D = _box(holder, "CradleJaw%s" % str(side),
			Vector3(0.36, 0.14, 0.46), Vector3(RECEIVER_START + 0.25, 0.58, side * 1.80), m_hazard)
		jaw.rotation.x = 0.28 * side
		# Flared guide plates: the visible hardware that explains the +/-5 deg
		# capture. The swing nose's AlignPin enters this funnel; the pin then
		# pulls the section the last few centimetres. Purely geometry, no script.
		var funnel: MeshInstance3D = _box(holder, "GuideFunnel%s" % str(side),
			Vector3(0.62, 0.10, 0.70), Vector3(RECEIVER_START - 0.18, 0.62, side * 1.52), m_hazard)
		funnel.rotation = Vector3(side * 0.46, side * 0.22, 0.0)
		_box(holder, "CradleLamp%s" % str(side), Vector3(0.10, 0.10, 0.10),
			Vector3(RECEIVER_START + 0.25, 1.06, side * 2.10), m_lamp_off)
	# Painted reset line: physical geometry, not a UI gauge.
	_box(holder, "ResetLine", Vector3(0.10, 0.012, 4.10),
		Vector3(RECEIVER_START + 0.32, 0.065, 0.0), m_lamp_green)
	for side: float in [-1.0, 1.0]:
		_box(holder, "ResetTick%s" % str(side), Vector3(0.60, 0.012, 0.10),
			Vector3(RECEIVER_START + 0.32, 0.066, side * 1.92), m_paint)

# --- winch -----------------------------------------------------------------

func _build_winch() -> void:
	station = Node3D.new()
	station.name = "WinchStation"
	station.set_script(StationScript)
	machine = Node3D.new()
	machine.name = "Machine"
	machine.set_script(MachineScript)
	station.set("machine_path", NodePath("Machine"))
	station.position = WINCH_POS
	station.rotation.y = deg_to_rad(WINCH_YAW)
	station.add_child(machine)
	add_child(station)
	# A 2.6 x 2.0 m winch is a solid object. The old 0.55 m radius cylinder was
	# small enough that a player standing at the console was visibly INSIDE the
	# drum housing (06_rail_moving.png in the delivered build). These boxes follow
	# the real station geometry (base, drum frame, motor, cabinet, pedestal) in
	# the station's own frame, so the console stays reachable from the front while
	# the body of the machine cannot be walked through.
	var winch_body: StaticBody3D = StaticBody3D.new()
	winch_body.name = "WinchBlock"
	winch_body.collision_layer = 6
	winch_body.collision_mask = 0
	_collider_box(winch_body, Vector3(0.15, 0.50, -0.10), Vector3(2.80, 1.00, 1.30))
	_collider_box(winch_body, Vector3(0.00, 1.45, 0.00), Vector3(1.90, 0.90, 0.90))
	_collider_box(winch_body, Vector3(1.15, 0.60, 0.00), Vector3(0.90, 1.20, 1.05))
	_collider_box(winch_body, Vector3(0.00, 0.85, -1.05), Vector3(1.50, 1.70, 0.62))
	_collider_box(winch_body, Vector3(0.00, 0.55, 1.06), Vector3(0.80, 1.10, 0.50))
	station.add_child(winch_body)
	# Work platform. There is deliberately NO guard rail on the far (south) side
	# of the machine any more: the winch body reaches within 0.7 m of the cave
	# wall, so a continuous rail turned the operator stance into a 0.53 m slot -
	# narrower than the 0.76 m capsule. The old build hid that by letting the
	# player stand inside the drum. The machine itself is the barrier now, and
	# the operator approaches along the wall side.
	_box(self, "WinchPad", Vector3(3.60, 0.12, 2.90), WINCH_POS + Vector3(0.0, 0.06, 0.0), m_dark)
	_solid(self, "WinchPadBlock", Vector3(3.60, 0.12, 2.90), WINCH_POS + Vector3(0.0, 0.06, 0.0))
	# Walkway plates from the dock side round to the machine bay.
	for index: int in range(9):
		var at: Vector3 = Vector3(WINCH_POS.x - 1.20 + float(index) * 0.62, 0.02,
			-1.05 + float(index) * 0.55)
		_box(self, "WalkPlate%d" % index, Vector3(0.58, 0.05, 1.06), at,
			Mine.material(Color("4f5c60"), 0.04))
	stage.call("_light", to_global(Vector3(WINCH_POS.x, 3.05, WINCH_POS.z - 0.30)),
		Color("ffd0a0"), 4.6, 12.0, false)

func _build_cable() -> void:
	cable = Node3D.new()
	cable.name = "Cable"
	cable.set_script(CableScript)
	add_child(cable)

# --- lock station ----------------------------------------------------------

func _build_lock_station() -> void:
	lock_station = Node3D.new()
	lock_station.name = "LockStation"
	lock_station.position = LOCK_POS
	add_child(lock_station)
	_solid(lock_station, "LockPostBody", Vector3(0.26, 1.20, 0.26), Vector3(0.0, 0.60, 0.0))
	_box(lock_station, "LockPost", Vector3(0.24, 1.15, 0.24), Vector3(0.0, 0.58, 0.0), m_dark)
	_box(lock_station, "LockPlate", Vector3(0.52, 0.10, 0.52), Vector3(0.0, 1.18, 0.0), m_hazard)
	_box(lock_station, "LockGuide", Vector3(0.14, 0.30, 0.14), Vector3(0.0, 1.36, 0.0), m_rail)
	lock_pin_mesh = Kit.cylinder(lock_station, "LockPin", 0.055, 0.46, Vector3(0.0, 1.62, 0.0), m_cut, "y", 10)
	lock_lever = Node3D.new()
	lock_lever.name = "LockLever"
	lock_lever.position = Vector3(0.26, 1.02, 0.0)
	lock_station.add_child(lock_lever)
	Kit.cylinder(lock_lever, "LeverShaft", 0.035, 0.52, Vector3(0.0, 0.26, 0.0), m_rail, "y", 10)
	Kit.sphere(lock_lever, "LeverKnob", 0.075, Vector3(0.0, 0.54, 0.0),
		Kit.material(Color(0.90, 0.62, 0.18), 0.3, 0.4))
	Kit.sphere(lock_station, "LockBeacon", 0.085, Vector3(0.0, 1.86, 0.0), m_lamp_off)

# --- co-op fixtures ---------------------------------------------------------
# Two physical jobs that only make sense next to the drum and the pin:
#
#   guide wheel  - a hand wheel on a pedestal at the receiver throat. Turning it
#                  pulls the nose toward the line (bounded, see rail.apply_guide)
#                  and widens the pin's capture slot while it is held.
#   safety prop  - a hinged steel prop under the swing deck. Planted, the section
#                  cannot rotate at all; the drum just loads up. It has to be
#                  folded away again before the pin can be driven home.
#
# Both stand outside |z| = 1.5, so they never enter the cart's clearance
# envelope, and both are collidable so nobody can stand inside them.

func _build_coop_fixtures() -> void:
	guide_pedestal = Node3D.new()
	guide_pedestal.name = "GuidePedestal"
	guide_pedestal.position = Vector3(5.55, 0.0, -2.35)
	add_child(guide_pedestal)
	_box(guide_pedestal, "GuideBase", Vector3(0.46, 0.10, 0.46), Vector3(0.0, 0.05, 0.0), m_dark)
	_box(guide_pedestal, "GuideColumn", Vector3(0.16, 1.02, 0.16), Vector3(0.0, 0.56, 0.0), m_rail)
	_box(guide_pedestal, "GuideHead", Vector3(0.30, 0.16, 0.18), Vector3(0.0, 1.08, 0.0), m_hazard)
	guide_wheel = Node3D.new()
	guide_wheel.name = "GuideWheel"
	guide_wheel.position = Vector3(0.0, 1.10, 0.14)
	guide_pedestal.add_child(guide_wheel)
	Kit.cylinder(guide_wheel, "GuideShaft", 0.05, 0.16, Vector3.ZERO, m_rust, "z", 12)
	var rim: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.20
	torus.outer_radius = 0.28
	torus.rings = 18
	torus.ring_segments = 8
	rim.mesh = torus
	rim.material_override = m_hazard
	rim.rotation.x = PI * 0.5
	guide_wheel.add_child(rim)
	for spoke: int in range(4):
		var bar: MeshInstance3D = _box(guide_wheel, "GuideSpoke%d" % spoke,
			Vector3(0.40, 0.035, 0.035), Vector3.ZERO, m_paint)
		bar.rotation.z = float(spoke) * PI * 0.25
	_solid(guide_pedestal, "GuideBlock", Vector3(0.42, 1.10, 0.42), Vector3(0.0, 0.55, 0.0))

	bracket_prop = Node3D.new()
	bracket_prop.name = "SafetyProp"
	bracket_prop.position = Vector3(1.90, 0.0, -2.55)
	add_child(bracket_prop)
	_box(bracket_prop, "PropShoe", Vector3(0.36, 0.10, 0.36), Vector3(0.0, 0.05, 0.0), m_dark)
	_box(bracket_prop, "PropPivot", Vector3(0.20, 0.20, 0.20), Vector3(0.0, 0.16, 0.0), m_hazard)
	var arm: Node3D = Node3D.new()
	arm.name = "PropArm"
	arm.position = Vector3(0.0, 0.20, 0.0)
	bracket_prop.add_child(arm)
	_box(arm, "PropBeam", Vector3(0.14, 1.30, 0.14), Vector3(0.0, 0.65, 0.0), m_rail)
	_box(arm, "PropHead", Vector3(0.34, 0.16, 0.20), Vector3(0.0, 1.28, 0.0), m_hazard)
	arm.rotation.x = -0.55
	_solid(bracket_prop, "PropBlock", Vector3(0.34, 0.30, 0.34), Vector3(0.0, 0.15, 0.0))

# Read by LevelFlow's single-E resolver. Positions are WORLD so the caller does
# not have to know how the yard is oriented on the route.
func workstations() -> Array:
	var out: Array = []
	if rig == null or completion():
		return out
	out.append({"kind": "guide", "position": to_global(Vector3(5.55, 1.12, -2.35)), "range": 1.85})
	out.append({"kind": "bracket", "position": to_global(Vector3(1.90, 0.92, -2.42)), "range": 1.75})
	return out


func _build_warning() -> void:
	# --- warning hardware ---------------------------------------------------
	for side: float in [-1.0, 1.0]:
		var lamp: MeshInstance3D = Kit.sphere(self, "CutLamp%s" % str(side), 0.10,
			Vector3(-0.55, 1.62, side * 1.95), m_lamp_off)
		cut_lamps.append(lamp)
		_box(self, "CutLampArm%s" % str(side), Vector3(0.10, 0.10, 0.42),
			Vector3(-0.55, 1.62, side * 2.16), m_dark)
		_box(self, "CutLampPost%s" % str(side), Vector3(0.09, 1.60, 0.09),
			Vector3(-0.55, 0.80, side * 2.36), m_rail)
		_solid(self, "CutLampPostBlock%s" % str(side), Vector3(0.14, 1.60, 0.14),
			Vector3(-0.55, 0.80, side * 2.36))
	_box(self, "WarnBoard", Vector3(0.06, 0.52, 1.30), Vector3(-1.20, 1.74, -2.55), m_dark)
	_label(self, "紧急停车 · 轨道故障", Vector3(-1.27, 1.74, -2.55), 30, Color(1.0, 0.62, 0.30))
	beacon = Kit.sphere(self, "FaultBeacon", 0.11, Vector3(1.30, 2.30, -2.30), m_lamp_off)
	beacon_light = OmniLight3D.new()
	beacon_light.name = "FaultBeaconLight"
	beacon_light.position = Vector3(1.30, 2.40, -2.30)
	beacon_light.light_color = Color(1.0, 0.45, 0.18)
	beacon_light.light_energy = 0.0
	beacon_light.omni_range = 7.0
	add_child(beacon_light)
	_box(self, "BeaconMast", Vector3(0.10, 2.30, 0.10), Vector3(1.30, 1.15, -2.30), m_rail)
	_solid(self, "BeaconMastBlock", Vector3(0.16, 2.30, 0.16), Vector3(1.30, 1.15, -2.30))

# --- story props -----------------------------------------------------------

func _build_story() -> void:
	# 1) The cut was deliberate: a discarded industrial torch, hoses still coiled.
	var torch: Node3D = Node3D.new()
	torch.name = "CuttingTorch"
	torch.position = Vector3(-1.85, 0.12, -1.35)
	torch.rotation.y = 0.7
	add_child(torch)
	_box(torch, "TorchBody", Vector3(0.62, 0.16, 0.16), Vector3.ZERO, m_rust)
	Kit.cylinder(torch, "TorchNozzle", 0.045, 0.34, Vector3(0.40, 0.02, 0.0), m_cut, "x", 8)
	Kit.cylinder(torch, "TorchValve", 0.06, 0.12, Vector3(-0.16, 0.14, 0.0),
		Kit.material(Color(0.55, 0.16, 0.12), 0.4, 0.5), "y", 8)
	for index: int in range(3):
		var coil: MeshInstance3D = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.20 + 0.05 * float(index)
		torus.outer_radius = 0.34 + 0.05 * float(index)
		torus.rings = 14
		torus.ring_segments = 8
		coil.mesh = torus
		coil.material_override = Kit.material(Color(0.10, 0.11, 0.12), 0.15, 0.7)
		coil.position = Vector3(-0.62, 0.10, 0.10 + float(index) * 0.02)
		coil.rotation.x = PI * 0.5
		torch.add_child(coil)
	story_props.append(torch)
	# 2) Maintenance record: the official story is "rail shift"; the dates and
	#    the tool draw disagree with it.
	var board: Node3D = Node3D.new()
	board.name = "MaintenanceBoard"
	board.position = Vector3(2.30, 0.0, -2.95)
	board.rotation.y = -0.35
	add_child(board)
	_box(board, "BoardPost", Vector3(0.10, 1.30, 0.10), Vector3(0.0, 0.65, 0.0), m_rail)
	_solid(board, "BoardPostBlock", Vector3(0.16, 1.30, 0.16), Vector3(0.0, 0.65, 0.0))
	_box(board, "BoardFace", Vector3(0.05, 0.62, 0.94), Vector3(0.0, 1.32, 0.0), m_paper)
	_label(board, "维修记录 07\n10.14 轨道偏移 · 已停机\n10.16 割炬领用 2 套\n—— 无事故报告",
		Vector3(0.08, 1.32, 0.0), 22, Color(0.12, 0.10, 0.08))
	story_props.append(board)
	# 3) Miner's note left on the winch pedestal. One sentence, no exposition.
	var note: Node3D = Node3D.new()
	note.name = "MinerNote"
	note.position = WINCH_POS + Vector3(1.05, 0.12, -0.10)
	note.rotation.y = 0.5
	add_child(note)
	_box(note, "NotePaper", Vector3(0.34, 0.01, 0.26), Vector3(0.0, 0.98, 0.0), m_paper)
	_label(note, "别让车下去。\n晶体在记账。\n—— 老宋", Vector3(0.0, 1.10, 0.0), 18, Color(0.20, 0.16, 0.12))
	story_props.append(note)
	# 4) Emergency stop that was clearly used: lever down, seal broken.
	var stop: Node3D = Node3D.new()
	stop.name = "EmergencyStop"
	stop.position = Vector3(-3.05, 0.0, -1.55)
	add_child(stop)
	_box(stop, "StopPost", Vector3(0.16, 1.25, 0.16), Vector3(0.0, 0.62, 0.0), m_dark)
	_solid(stop, "StopPostBlock", Vector3(0.22, 1.25, 0.22), Vector3(0.0, 0.62, 0.0))
	_box(stop, "StopHead", Vector3(0.30, 0.34, 0.30), Vector3(0.0, 1.32, 0.0), m_hazard)
	Kit.cylinder(stop, "StopButton", 0.09, 0.10, Vector3(0.0, 1.33, -0.18),
		Kit.material(Color(0.85, 0.16, 0.12), 0.2, 0.4, Color(1.0, 0.12, 0.08), 1.2), "z", 12)
	story_props.append(stop)

# --- crystal mine entrance -------------------------------------------------

func _build_entrance() -> void:
	entrance_sign = Node3D.new()
	entrance_sign.name = "CrystalEntranceSign"
	entrance_sign.position = Vector3(11.60, 0.0, -2.60)
	add_child(entrance_sign)
	_box(entrance_sign, "SignPost", Vector3(0.14, 2.10, 0.14), Vector3(0.0, 1.05, 0.0), m_rail)
	_box(entrance_sign, "SignFace", Vector3(0.06, 0.60, 1.55), Vector3(0.0, 2.10, 0.0), m_dark)
	_label(entrance_sign, "03 · 晶体矿区  →", Vector3(0.08, 2.10, 0.0), 34, Color(0.62, 0.95, 1.0))
	Kit.sphere(entrance_sign, "SignLamp", 0.075, Vector3(0.0, 2.52, 0.70), m_lamp_off)
	entrance_light = OmniLight3D.new()
	entrance_light.name = "EntranceLight"
	entrance_light.position = Vector3(11.60, 2.40, -2.30)
	entrance_light.light_color = Color(0.42, 0.86, 1.0)
	entrance_light.light_energy = 0.0
	entrance_light.omni_range = 9.0
	add_child(entrance_light)
	for index: int in range(4):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		_box(self, "BoreRib%d" % index, Vector3(0.20, 1.30, 0.20),
			Vector3(13.40 + float(index) * 0.9, 0.65, side * 2.35), m_rust)
	entrance_sign.visible = false

# --- rig -------------------------------------------------------------------

func _build_rig(player: CharacterBody3D) -> void:
	rig = Node3D.new()
	rig.name = "WinchRig"
	rig.set_script(RigScript)
	rig.set("winch_path", NodePath("../WinchStation/Machine"))
	rig.set("rail_path", NodePath("../RailBody"))
	rig.set("cable_path", NodePath("../Cable"))
	rig.set("sheave_path", NodePath("../WinchStation/Sheave"))
	add_child(rig)
	# The player lives outside the yard, so its NodePath can only be resolved once
	# this node is inside the tree. WinchRig tolerates a null player at _ready and
	# reads this field on demand.
	if player != null:
		rig.set("player", player)
		rig.set("player_path", rig.get_path_to(player))

# --- runtime ---------------------------------------------------------------

func _process(delta: float) -> void:
	clock += delta
	if rail == null:
		return
	var info: Dictionary = rail.call("alignment") as Dictionary
	var locked: bool = bool(info.get("locked", false))
	var in_band: bool = bool(info.get("in_band", false))
	# Cut lamps: red while the line is severed, green once it is pinned.
	var cut_material: StandardMaterial3D = m_lamp_green if locked else (
		m_lamp_red if fmod(clock, 1.0) < 0.55 else m_lamp_off)
	for lamp: MeshInstance3D in cut_lamps:
		lamp.material_override = cut_material
	if beacon != null:
		beacon.material_override = m_lamp_green if locked else (m_lamp_amber if in_band else m_lamp_red)
		beacon.visible = locked or fmod(clock, 0.85) < 0.5
	if beacon_light != null:
		if locked:
			beacon_light.light_color = Color(0.32, 1.0, 0.52)
			beacon_light.light_energy = 1.1
		elif in_band:
			beacon_light.light_color = Color(0.45, 1.0, 0.60)
			beacon_light.light_energy = 0.9
		else:
			beacon_light.light_color = Color(1.0, 0.42, 0.16)
			beacon_light.light_energy = 0.5 + 0.45 * sin(clock * 5.0)
	# Pin travel + lever throw, driven by the rail's own lock flag so a refused
	# lock never shows a half-inserted pin.
	var pin_target: float = 1.0 if bool(info.get("lock_pin", false)) else 0.0
	_pin_t = move_toward(_pin_t, pin_target, delta * 3.2)
	if lock_pin_mesh != null:
		lock_pin_mesh.position.y = lerpf(1.62, 1.30, _pin_t)
	if lock_lever != null:
		lock_lever.rotation.x = lerpf(0.0, -1.15, _pin_t)
	var entrance_target: float = 1.0 if locked else 0.0
	_entrance_fade = move_toward(_entrance_fade, entrance_target, delta * 0.55)
	if entrance_sign != null:
		entrance_sign.visible = _entrance_fade > 0.02
	if entrance_light != null:
		entrance_light.light_energy = 1.35 * _entrance_fade
	# Co-op fixtures: the hand wheel spins while somebody holds it, and the
	# safety prop swings under the deck when it is planted. Both are the visible
	# consequence of another player's action, not a UI state.
	var guide_held: bool = rig != null and int(rig.get("guide_holder")) > 0
	if guide_wheel != null:
		guide_wheel.rotate_z(delta * (2.1 if guide_held else 0.0))
	if guide_sign != null:
		guide_sign.modulate = Color(0.55, 1.0, 0.72) if guide_held else Color(0.90, 0.95, 0.98)
	var bracket_held: bool = rig != null and int(rig.get("bracket_holder")) > 0
	if bracket_prop != null:
		var arm: Node3D = bracket_prop.get_node_or_null("PropArm") as Node3D
		if arm != null:
			arm.rotation.x = lerpf(arm.rotation.x, -0.10 if bracket_held else -0.55, 1.0 - exp(-6.0 * delta))

func completion() -> bool:
	if rig == null:
		return false
	return bool(rig.get("completed"))

func lock_station_position() -> Vector3:
	return lock_station.global_position

func snapshot() -> Dictionary:
	var out: Dictionary = {"completed": completion(), "entrance_fade": _entrance_fade}
	if rig != null:
		out["rig"] = rig.call("rig_snapshot")
	return out
