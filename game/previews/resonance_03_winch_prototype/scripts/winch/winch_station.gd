extends Node3D

# -----------------------------------------------------------------------------
# WinchStation - the interactable drum assembly.
#
# Visuals are built here (frame, drum, flanges, control lever, brake handle,
# cable guide) so the station is self-contained and can be dropped into the real
# cave later without an artist pass.
#
# It owns no simulation. Everything it animates is read from WinchMachine, so
# the drum you see is literally the drum the solver integrated - there is no
# second, cosmetic source of truth.
# -----------------------------------------------------------------------------

@export var machine_path: NodePath

var machine: Node3D
var drum: Node3D
var lever: Node3D
var brake_handle: Node3D
var sheave: Node3D
var drum_angle: float = 0.0
var _lever_target: float = 0.0
var _brake_target: float = 0.0
var _lever_current: float = 0.0
var _brake_current: float = 0.0
var _kit: Script = preload("res://scripts/build/mesh_kit.gd")
var gauge_needle: Node3D
var lamp_power: MeshInstance3D
var lamp_tension: MeshInstance3D
var lamp_fault: MeshInstance3D
var beacon: MeshInstance3D
var _mat_green: StandardMaterial3D
var _mat_amber: StandardMaterial3D
var _mat_red: StandardMaterial3D
var _mat_off: StandardMaterial3D
var _clock: float = 0.0

func _ready() -> void:
	if machine_path != NodePath() and has_node(machine_path):
		machine = get_node(machine_path) as Node3D
	if machine == null:
		var found: Array[Node] = get_tree().get_nodes_in_group("winch_machine")
		if not found.is_empty():
			machine = found[0] as Node3D
	_build()

func _build() -> void:
	var steel: Material = _kit.material(Color(0.40, 0.43, 0.46), 0.62, 0.45)
	var dark_steel: Material = _kit.material(Color(0.21, 0.23, 0.25), 0.55, 0.55)
	var hazard: Material = _kit.material(Color(0.85, 0.58, 0.16), 0.3, 0.5)
	var amber: Material = _kit.material(Color(0.95, 0.62, 0.16), 0.2, 0.4, Color(1.0, 0.55, 0.12), 1.6)
	var cyan: Material = _kit.material(Color(0.20, 0.72, 0.86), 0.25, 0.35, Color(0.18, 0.75, 1.0), 1.4)
	var cable_mat: Material = _kit.material(Color(0.22, 0.24, 0.27), 0.8, 0.38)

	# Base plate + skid rails
	_kit.box(self, "Base", Vector3(2.6, 0.16, 2.0), Vector3(0, 0.08, 0), dark_steel)
	_kit.box(self, "SkidLeft", Vector3(0.22, 0.22, 2.0), Vector3(-1.12, 0.22, 0), hazard)
	_kit.box(self, "SkidRight", Vector3(0.22, 0.22, 2.0), Vector3(1.12, 0.22, 0), hazard)

	# Two uprights holding the drum axle
	_kit.box(self, "FrameLeft", Vector3(0.26, 1.65, 0.72), Vector3(-0.82, 0.98, 0), steel)
	_kit.box(self, "FrameRight", Vector3(0.26, 1.65, 0.72), Vector3(0.82, 0.98, 0), steel)
	_kit.box(self, "CrossBeam", Vector3(2.0, 0.20, 0.34), Vector3(0, 1.78, -0.16), steel)
	_kit.cylinder(self, "Axle", 0.10, 2.05, Vector3(0, 1.18, 0), dark_steel, "x", 18)

	# Drum: parented to its own pivot so its rotation is independent
	drum = Node3D.new()
	drum.name = "Drum"
	drum.position = Vector3(0, 1.18, 0)
	add_child(drum)
	var drum_body: MeshInstance3D = _kit.cylinder(drum, "DrumBody", 0.34, 1.30, Vector3.ZERO, steel, "x", 28)
	drum_body.material_override = _kit.material(Color(0.36, 0.38, 0.41), 0.82, 0.36)
	_kit.cylinder(drum, "FlangeLeft", 0.50, 0.10, Vector3(-0.70, 0, 0), dark_steel, "x", 28)
	_kit.cylinder(drum, "FlangeRight", 0.50, 0.10, Vector3(0.70, 0, 0), dark_steel, "x", 28)
	# Spokes make the rotation readable from a distance
	for index: int in range(6):
		var angle: float = TAU * float(index) / 6.0
		var spoke: MeshInstance3D = _kit.box(drum, "Spoke%d" % index, Vector3(0.86, 0.055, 0.10), Vector3(0, 0, 0), hazard)
		spoke.rotation = Vector3(angle, 0, 0)
		spoke.position = Vector3(0.66, sin(angle) * 0.40, cos(angle) * 0.40)
	# Wound cable layer on the drum
	_kit.cylinder(drum, "CableWrap", 0.40, 1.06, Vector3.ZERO, cable_mat, "x", 24)

	# Control pedestal in front of the drum (where the player stands)
	var pedestal: Node3D = Node3D.new()
	pedestal.name = "ControlPedestal"
	pedestal.position = Vector3(0, 0, 1.06)
	add_child(pedestal)
	_kit.box(pedestal, "PedestalBody", Vector3(0.72, 0.98, 0.44), Vector3(0, 0.49, 0), dark_steel)
	_kit.box(pedestal, "PedestalTop", Vector3(0.80, 0.10, 0.52), Vector3(0, 1.02, 0), steel)
	_kit.box(pedestal, "HazardStripe", Vector3(0.74, 0.08, 0.46), Vector3(0, 0.20, 0), hazard)
	_kit.box(pedestal, "GaugePanel", Vector3(0.30, 0.20, 0.04), Vector3(0.16, 1.02, 0.24), cyan)

	lever = Node3D.new()
	lever.name = "ControlLever"
	lever.position = Vector3(-0.16, 1.06, 0.0)
	pedestal.add_child(lever)
	_kit.cylinder(lever, "LeverShaft", 0.035, 0.46, Vector3(0, 0.23, 0), steel, "y", 12)
	_kit.sphere(lever, "LeverKnob", 0.075, Vector3(0, 0.48, 0), amber)

	brake_handle = Node3D.new()
	brake_handle.name = "BrakeHandle"
	brake_handle.position = Vector3(0.20, 1.06, 0.02)
	pedestal.add_child(brake_handle)
	_kit.cylinder(brake_handle, "BrakeShaft", 0.03, 0.34, Vector3(0, 0.17, 0), steel, "y", 12)
	_kit.box(brake_handle, "BrakeGrip", Vector3(0.20, 0.06, 0.06), Vector3(0, 0.34, 0), hazard)

	# Cable guide / sheave at the front edge - this is the cable origin
	sheave = Node3D.new()
	sheave.name = "Sheave"
	sheave.position = Vector3(0, 1.32, -0.42)
	add_child(sheave)
	_kit.cylinder(sheave, "SheaveWheel", 0.19, 0.12, Vector3.ZERO, dark_steel, "x", 20)
	_kit.box(self, "SheaveBracket", Vector3(0.34, 0.34, 0.20), Vector3(0, 1.44, -0.42), steel)

	_build_details(steel, dark_steel, hazard, amber, cyan)

func _build_details(steel: Material, dark_steel: Material, hazard: Material, amber: Material, cyan: Material) -> void:
	var pedestal: Node3D = get_node_or_null("ControlPedestal") as Node3D
	_mat_green = _kit.material(Color(0.24, 0.90, 0.50), 0.1, 0.3, Color(0.18, 1.0, 0.45), 2.0)
	_mat_amber = _kit.material(Color(0.95, 0.62, 0.16), 0.1, 0.35, Color(1.0, 0.55, 0.10), 2.0)
	_mat_red = _kit.material(Color(0.95, 0.24, 0.20), 0.1, 0.35, Color(1.0, 0.15, 0.10), 2.4)
	_mat_off = _kit.material(Color(0.10, 0.12, 0.13), 0.5, 0.6)

	# Motor, gearbox and control cabinet: the drum now sits inside a machine,
	# not on a bare frame.
	_kit.box(self, "MotorBody", Vector3(0.78, 1.02, 1.0), Vector3(1.14, 0.58, 0.0), dark_steel)
	for index: int in range(5):
		_kit.box(self, "MotorFin%d" % index, Vector3(0.82, 0.05, 0.94), Vector3(1.14, 0.90 + float(index) * 0.075, 0.0), steel)
	_kit.cylinder(self, "Gearbox", 0.30, 0.52, Vector3(0.92, 1.18, 0.0), steel, "x", 16)
	_kit.cylinder(self, "Coupling", 0.17, 0.22, Vector3(1.05, 1.18, 0.0), hazard, "x", 12)
	_kit.box(self, "Cabinet", Vector3(1.45, 1.55, 0.55), Vector3(0.0, 0.82, -1.05), dark_steel)
	_kit.box(self, "CabinetTop", Vector3(1.52, 0.08, 0.62), Vector3(0.0, 1.62, -1.05), steel)
	_kit.box(self, "CabinetScreen", Vector3(0.92, 0.48, 0.04), Vector3(0.0, 1.18, -0.755), cyan)
	_kit.box(self, "CabinetStripe", Vector3(1.46, 0.10, 0.56), Vector3(0.0, 0.22, -1.05), hazard)
	# Back guard for the drum; the front stays open so the cable is visible.
	_kit.box(self, "DrumGuard", Vector3(1.62, 0.92, 0.06), Vector3(0.0, 1.34, -0.60), steel)
	_kit.box(self, "DrumGuardTop", Vector3(1.62, 0.06, 0.40), Vector3(0.0, 1.80, -0.48), steel)
	# Fairlead roller at the cable exit.
	_kit.cylinder(self, "Fairlead", 0.075, 0.30, Vector3(0.0, 1.19, -0.55), hazard, "x", 12)
	# Base bolts.
	for index: int in range(4):
		_kit.cylinder(self, "BaseBolt%d" % index, 0.04, 0.08, Vector3(-1.0 + float(index) * 0.66, 0.19, 0.86), steel, "y", 6)

	if pedestal != null:
		# A real dial with a needle, readable from the standing position.
		_kit.cylinder(pedestal, "GaugeDial", 0.17, 0.05, Vector3(0.0, 1.10, 0.255), _kit.material(Color(0.06, 0.08, 0.09), 0.4, 0.5), "z", 24)
		_kit.cylinder(pedestal, "GaugeBezel", 0.185, 0.03, Vector3(0.0, 1.10, 0.245), steel, "z", 24)
		gauge_needle = Node3D.new()
		gauge_needle.name = "GaugeNeedle"
		gauge_needle.position = Vector3(0.0, 1.10, 0.29)
		pedestal.add_child(gauge_needle)
		_kit.box(gauge_needle, "Needle", Vector3(0.018, 0.13, 0.012), Vector3(0.0, 0.055, 0.0), _mat_red)
		# Three status lamps and a console label.
		lamp_power = _kit.sphere(pedestal, "LampPower", 0.035, Vector3(-0.20, 1.09, 0.17), _mat_green)
		lamp_tension = _kit.sphere(pedestal, "LampTension", 0.035, Vector3(0.0, 1.09, 0.17), _mat_off)
		lamp_fault = _kit.sphere(pedestal, "LampFault", 0.035, Vector3(0.20, 1.09, 0.17), _mat_off)
		_kit.box(pedestal, "LampPanel", Vector3(0.56, 0.10, 0.04), Vector3(0.0, 1.09, 0.145), dark_steel)

	beacon = _kit.sphere(self, "WinchBeacon", 0.10, Vector3(0.0, 2.00, -0.16), _mat_amber)
	var beacon_light: OmniLight3D = OmniLight3D.new()
	beacon_light.name = "BeaconLight"
	beacon_light.position = Vector3(0.0, 2.05, -0.16)
	beacon_light.light_color = Color(1.0, 0.55, 0.15)
	beacon_light.light_energy = 0.8
	beacon_light.omni_range = 5.0
	add_child(beacon_light)

func _process(delta: float) -> void:
	if machine == null:
		return
	var angle: float = float(machine.get("drum_angle"))
	# Shortest-path smoothing keeps the drum from unwinding visually at wrap.
	drum_angle = lerp_angle(drum_angle, angle, 1.0 - exp(-26.0 * delta))
	if drum != null:
		drum.rotation.x = drum_angle

	var hauling: bool = bool(machine.get("haul_pressed")) and not bool(machine.get("brake"))
	var paying: bool = bool(machine.get("payout_pressed")) and not bool(machine.get("brake"))
	_lever_target = -0.55 if hauling else (0.55 if paying else 0.0)
	_lever_current = lerpf(_lever_current, _lever_target, 1.0 - exp(-11.0 * delta))
	if lever != null:
		lever.rotation.x = _lever_current

	_brake_target = 0.0 if bool(machine.get("brake")) else -0.62
	_brake_current = lerpf(_brake_current, _brake_target, 1.0 - exp(-13.0 * delta))
	if brake_handle != null:
		brake_handle.rotation.x = _brake_current

	_clock += delta
	var ratio: float = float(machine.call("tension_ratio"))
	var stalled: bool = bool(machine.get("stalled"))
	if gauge_needle != null:
		gauge_needle.rotation.z = lerpf(gauge_needle.rotation.z, lerpf(-1.15, 1.15, clampf(ratio, 0.0, 1.0)), 1.0 - exp(-9.0 * delta))
	if lamp_tension != null:
		lamp_tension.material_override = _mat_red if (stalled or ratio >= 0.86) else (_mat_amber if ratio >= 0.60 else _mat_off)
	if lamp_fault != null:
		lamp_fault.material_override = _mat_red if stalled else _mat_off
	if beacon != null:
		beacon.material_override = _mat_red if stalled else (_mat_amber if ratio >= 0.60 else _mat_green)
		beacon.visible = not stalled or fmod(_clock, 0.7) < 0.45
