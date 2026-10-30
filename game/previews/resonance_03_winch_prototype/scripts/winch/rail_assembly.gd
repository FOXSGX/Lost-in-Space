extends Node3D

# -----------------------------------------------------------------------------
# RailAssembly - the visible misaligned rail section and its fixed continuation.
#
# The moving part is a child "RailBody" whose transform is driven by
# MisalignedRail (an AnimatableBody3D). This node only builds geometry:
#   * the fixed approach track the mine cart would arrive on
#   * the swing section with two sleepers, two rails and three lifting eyes
#   * the fixed receiver bracket with the lock socket
#   * a pair of alignment indicators that turn amber -> green when in band
# Nothing here reads the mission state; WinchHud does that.
# -----------------------------------------------------------------------------

@export var rail_path: NodePath
@export var moving_body_path: NodePath

var rail: Node3D
var moving_body: Node3D
var indicator_left: MeshInstance3D
var indicator_right: MeshInstance3D
var socket_lamp: MeshInstance3D
var _beacon: MeshInstance3D
var _beacon_light: OmniLight3D
var _clock: float = 0.0
var _mat_amber: StandardMaterial3D
var _mat_green: StandardMaterial3D
var _mat_red: StandardMaterial3D
var _mat_off: StandardMaterial3D
var _kit: Script = preload("res://scripts/build/mesh_kit.gd")

func _ready() -> void:
	if moving_body_path != NodePath() and has_node(moving_body_path):
		moving_body = get_node(moving_body_path) as Node3D
	if moving_body == null:
		for child: Node in get_children():
			if child.is_in_group("misaligned_rail"):
				moving_body = child as Node3D
				break
	rail = moving_body
	_mat_amber = _kit.material(Color(0.95, 0.62, 0.16), 0.1, 0.35, Color(1.0, 0.55, 0.10), 2.2)
	_mat_green = _kit.material(Color(0.28, 0.92, 0.55), 0.1, 0.3, Color(0.20, 1.0, 0.45), 2.6)
	_mat_red = _kit.material(Color(0.95, 0.26, 0.22), 0.1, 0.35, Color(1.0, 0.18, 0.12), 2.6)
	_mat_off = _kit.material(Color(0.14, 0.16, 0.18), 0.5, 0.6)
	_build_fixed_track()
	_build_swing_section()
	_build_receiver()
	_build_alignment_marks()
	_build_indicators()
	_build_beacon()

func _build_fixed_track() -> void:
	var sleeper: Material = _kit.material(Color(0.20, 0.19, 0.18), 0.25, 0.85)
	var rail_steel: Material = _kit.material(Color(0.46, 0.47, 0.49), 0.9, 0.28)
	var bed: Material = _kit.material(Color(0.14, 0.14, 0.15), 0.15, 0.9)
	# Approach track from the cave mouth down to the hinge
	_kit.static_box(self, "ApproachBed", Vector3(4.4, 0.18, 2.1), Vector3(-4.2, 0.09, 0), bed)
	for index: int in range(7):
		var x: float = -6.1 + float(index) * 0.62
		_kit.static_box(self, "SleeperA%d" % index, Vector3(0.30, 0.16, 1.66), Vector3(x, 0.26, 0), sleeper)
	_kit.static_box(self, "ApproachRailL", Vector3(4.5, 0.14, 0.12), Vector3(-4.2, 0.40, -0.62), rail_steel)
	_kit.static_box(self, "ApproachRailR", Vector3(4.5, 0.14, 0.12), Vector3(-4.2, 0.40, 0.62), rail_steel)
	# Hinge post - the pivot the swing section is bolted to
	_kit.static_box(self, "HingePost", Vector3(0.46, 1.10, 0.46), Vector3(0.0, 0.55, 0), _kit.material(Color(0.30, 0.32, 0.34), 0.75, 0.45))
	_kit.cylinder(self, "HingePin", 0.13, 0.62, Vector3(0.0, 1.02, 0), _kit.material(Color(0.72, 0.52, 0.20), 0.85, 0.3), "y", 16)

func _build_swing_section() -> void:
	if moving_body == null:
		push_error("RailAssembly: no moving rail body")
		return
	var sleeper: Material = _kit.material(Color(0.23, 0.21, 0.19), 0.25, 0.82)
	var rail_steel: Material = _kit.material(Color(0.50, 0.51, 0.53), 0.92, 0.24)
	var deck: Material = _kit.material(Color(0.21, 0.215, 0.225), 0.2, 0.86)
	var hazard: Material = _kit.material(Color(0.80, 0.54, 0.14), 0.35, 0.5)

	# Deck slab the rails are bolted to
	var deck_mesh: MeshInstance3D = _kit.box(moving_body, "SwingDeck", Vector3(6.4, 0.20, 2.0), Vector3(3.2, 0.10, 0), deck)
	deck_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var deck_body: StaticBody3D = StaticBody3D.new()
	deck_body.name = "SwingDeckCollision"
	deck_body.collision_layer = 1
	deck_body.collision_mask = 0
	deck_body.position = Vector3(3.2, 0.10, 0)
	var deck_shape: CollisionShape3D = CollisionShape3D.new()
	var deck_box: BoxShape3D = BoxShape3D.new()
	deck_box.size = Vector3(6.4, 0.20, 2.0)
	deck_shape.shape = deck_box
	deck_body.add_child(deck_shape)
	moving_body.add_child(deck_body)

	for index: int in range(9):
		var x: float = 0.55 + float(index) * 0.68
		var s: MeshInstance3D = _kit.box(moving_body, "SwingSleeper%d" % index, Vector3(0.34, 0.18, 1.70), Vector3(x, 0.28, 0), sleeper)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_kit.box(moving_body, "SwingRailL", Vector3(6.3, 0.15, 0.13), Vector3(3.2, 0.43, -0.62), rail_steel)
	_kit.box(moving_body, "SwingRailR", Vector3(6.3, 0.15, 0.13), Vector3(3.2, 0.43, 0.62), rail_steel)
	# Hazard nose so the loose end reads clearly against the receiver
	_kit.box(moving_body, "NoseMarker", Vector3(0.34, 0.26, 1.9), Vector3(6.24, 0.28, 0), hazard)
	_build_swing_structure(rail_steel, deck, hazard)

	# Three lifting eyes. The two on the rail are real WinchAnchors; the one on
	# the hinge post is fixed and refuses the cable.
	_make_anchor(moving_body, "eye_far", "前端吊耳", "track", "轨道前端", Vector3(6.05, 0.62, 0.0))
	_make_anchor(moving_body, "eye_mid", "中段吊耳", "track", "靠近铰链", Vector3(2.45, 0.62, 0.0))

func _build_swing_structure(rail_steel: Material, deck: Material, hazard: Material) -> void:
	var dark: Material = _kit.material(Color(0.12, 0.13, 0.14), 0.5, 0.6)
	var paint: Material = _kit.material(Color(0.85, 0.88, 0.90), 0.1, 0.6)
	# Side girders carry the deck and make the swing section read as a structure.
	for side: int in range(2):
		var z: float = -1.02 if side == 0 else 1.02
		_kit.box(moving_body, "SideGirder%d" % side, Vector3(6.3, 0.34, 0.18), Vector3(3.15, 0.20, z), rail_steel)
		for index: int in range(6):
			_kit.cylinder(moving_body, "GirderBolt%d_%d" % [side, index], 0.035, 0.06, Vector3(0.55 + float(index) * 1.05, 0.38, z), dark, "y", 6)
	# Cross braces under the deck.
	for index: int in range(4):
		_kit.box(moving_body, "CrossBrace%d" % index, Vector3(0.18, 0.16, 1.9), Vector3(1.05 + float(index) * 1.45, 0.02, 0), dark)
	# Counterweight on the hinge side of the swing arm.
	_kit.box(moving_body, "Counterweight", Vector3(0.9, 0.55, 1.5), Vector3(-0.35, 0.42, 0), dark)
	_kit.box(moving_body, "CounterweightTrim", Vector3(0.96, 0.06, 1.55), Vector3(-0.35, 0.72, 0), hazard)
	# Visible hinge cheeks and pin caps around the pivot.
	for side: int in range(2):
		var z: float = -0.78 if side == 0 else 0.78
		_kit.box(moving_body, "HingeCheek%d" % side, Vector3(0.55, 0.9, 0.14), Vector3(0.28, 0.66, z), rail_steel)
		_kit.cylinder(moving_body, "HingeCap%d" % side, 0.12, 0.22, Vector3(0.28, 0.86, z), hazard, "z", 12)
	# Hazard nose face, alignment pin and a painted pointer at the loose end.
	_kit.box(moving_body, "NoseFace", Vector3(0.18, 0.55, 2.02), Vector3(6.36, 0.42, 0), hazard)
	_kit.cylinder(moving_body, "AlignPin", 0.045, 0.70, Vector3(6.30, 1.02, 0), rail_steel, "y", 8)
	_kit.box(moving_body, "AlignPointer", Vector3(0.50, 0.04, 0.12), Vector3(6.05, 0.32, 0), paint)

func _make_anchor(parent: Node3D, id: String, label: String, kind: String, note: String, local: Vector3) -> void:
	var anchor: Node3D = Node3D.new()
	anchor.name = "Anchor_" + id
	anchor.set_script(load("res://scripts/winch/winch_anchor.gd") as Script)
	anchor.position = local
	anchor.set("anchor_id", StringName(id))
	anchor.set("display_name", label)
	anchor.set("kind", kind)
	anchor.set("leverage_note", note)
	anchor.set("hook_local", Vector3.ZERO)
	parent.add_child(anchor)
	# Eye plate + ring. The plate is deliberately larger than the cable end so
	# the two connection points are readable from the walkway.
	var plate: Material = _kit.material(Color(0.55, 0.57, 0.60), 0.9, 0.28)
	_kit.box(parent, "EyePlate_" + id, Vector3(0.44, 0.46, 0.24), local + Vector3(0, -0.12, 0), plate)
	_kit.cylinder(parent, "EyeRing_" + id, 0.11, 0.18, local, _kit.material(Color(0.95, 0.68, 0.20), 0.6, 0.3, Color(1.0, 0.60, 0.12), 1.1), "z", 16)
	# World-space label. It states where the eye is, not whether it is the right
	# choice; the player still has to read the mechanics.
	var name_label: Label3D = Label3D.new()
	name_label.name = "Label_" + id
	name_label.text = label
	name_label.font_size = 38
	name_label.pixel_size = 0.0029
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.outline_size = 7
	name_label.outline_modulate = Color(0.02, 0.03, 0.04, 0.9)
	name_label.modulate = Color(0.98, 0.86, 0.55, 1.0)
	name_label.position = local + Vector3(0.0, 0.72, 0.0)
	parent.add_child(name_label)

func _build_receiver() -> void:
	var bracket: Material = _kit.material(Color(0.34, 0.36, 0.39), 0.82, 0.38)
	var hazard: Material = _kit.material(Color(0.82, 0.56, 0.15), 0.4, 0.5)
	# The fixed receiver the swing section has to land on
	_kit.static_box(self, "ReceiverBed", Vector3(2.0, 0.18, 2.1), Vector3(7.35, 0.09, 0), _kit.material(Color(0.13, 0.13, 0.14), 0.15, 0.9))
	_kit.static_box(self, "ReceiverRailL", Vector3(2.0, 0.14, 0.12), Vector3(7.35, 0.40, -0.62), _kit.material(Color(0.48, 0.49, 0.51), 0.9, 0.26))
	_kit.static_box(self, "ReceiverRailR", Vector3(2.0, 0.14, 0.12), Vector3(7.35, 0.40, 0.62), _kit.material(Color(0.48, 0.49, 0.51), 0.9, 0.26))
	for index: int in range(3):
		_kit.static_box(self, "ReceiverSleeper%d" % index, Vector3(0.30, 0.16, 1.66), Vector3(6.75 + float(index) * 0.62, 0.26, 0), _kit.material(Color(0.21, 0.20, 0.19), 0.25, 0.85))
	# Alignment cradle: two uprights that visually "catch" the rail nose
	_kit.static_box(self, "CradleLeft", Vector3(0.28, 0.78, 0.24), Vector3(6.62, 0.62, -0.95), bracket)
	_kit.static_box(self, "CradleRight", Vector3(0.28, 0.78, 0.24), Vector3(6.62, 0.62, 0.95), bracket)
	_kit.static_box(self, "CradleTop", Vector3(0.28, 0.22, 2.14), Vector3(6.62, 1.06, 0), bracket)
	# Angled jaws and a sight gate: the nose pin has to arrive under the crossbar.
	for side: int in range(2):
		var z: float = -0.55 if side == 0 else 0.55
		var jaw: MeshInstance3D = _kit.box(self, "CradleJaw%d" % side, Vector3(0.18, 0.50, 0.46), Vector3(6.48, 0.55, z), bracket)
		jaw.rotation.y = -0.45 if side == 0 else 0.45
		_kit.box(self, "SightPost%d" % side, Vector3(0.08, 0.55, 0.08), Vector3(6.62, 0.85, z), hazard)
	# Lock socket
	_kit.static_box(self, "SocketBody", Vector3(0.36, 0.30, 0.36), Vector3(7.05, 0.62, 1.16), bracket)
	_kit.cylinder(self, "SocketRing", 0.11, 0.30, Vector3(7.05, 0.84, 1.16), hazard, "y", 14)
	_kit.box(self, "SocketPinHole", Vector3(0.16, 0.10, 0.16), Vector3(7.05, 0.80, 1.16), _kit.material(Color(0.06, 0.06, 0.07), 0.3, 0.8))

func _build_alignment_marks() -> void:
	var paint: Material = _kit.material(Color(0.82, 0.86, 0.88), 0.1, 0.7)
	var target: Material = _kit.material(Color(0.22, 0.90, 0.52), 0.05, 0.4, Color(0.16, 1.0, 0.45), 1.8)
	# Painted target on the receiver deck. The nose pointer has to arrive on this
	# line; the marks are physical geometry, not a UI gauge.
	_kit.box(self, "ReceiverTargetLine", Vector3(0.10, 0.02, 2.05), Vector3(6.62, 0.20, 0.0), target)
	_kit.box(self, "ReceiverTargetTickL", Vector3(0.55, 0.02, 0.08), Vector3(6.62, 0.205, -0.95), paint)
	_kit.box(self, "ReceiverTargetTickR", Vector3(0.55, 0.02, 0.08), Vector3(6.62, 0.205, 0.95), paint)
	_kit.box(self, "CradleTarget", Vector3(0.30, 0.06, 0.14), Vector3(6.62, 1.18, 0.0), target)
	var sign_label: Label3D = Label3D.new()
	sign_label.text = "复位线"
	sign_label.font_size = 38
	sign_label.pixel_size = 0.0030
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.outline_size = 6
	sign_label.outline_modulate = Color(0.02, 0.04, 0.03, 0.9)
	sign_label.modulate = Color(0.55, 1.0, 0.72)
	sign_label.position = Vector3(6.62, 1.42, 0.0)
	add_child(sign_label)

func _build_beacon() -> void:
	_beacon = _kit.sphere(self, "HingeBeacon", 0.13, Vector3(0.0, 1.42, 0.0), _mat_amber)
	_beacon_light = OmniLight3D.new()
	_beacon_light.name = "HingeBeaconLight"
	_beacon_light.position = Vector3(0.0, 1.55, 0.0)
	_beacon_light.omni_range = 6.0
	_beacon_light.light_energy = 0.9
	_beacon_light.light_color = Color(1.0, 0.55, 0.15)
	add_child(_beacon_light)

func _build_indicators() -> void:
	# Two lamps either side of the receiver show the alignment band.
	indicator_left = _kit.sphere(self, "AlignLampL", 0.10, Vector3(6.62, 1.22, -0.95), _mat_off)
	indicator_right = _kit.sphere(self, "AlignLampR", 0.10, Vector3(6.62, 1.22, 0.95), _mat_off)
	socket_lamp = _kit.sphere(self, "SocketLamp", 0.08, Vector3(7.05, 1.02, 1.16), _mat_off)

func _process(delta: float) -> void:
	if rail == null:
		return
	_clock += delta
	var info: Dictionary = rail.call("alignment") as Dictionary
	var locked: bool = bool(info.get("locked", false))
	var in_band: bool = bool(info.get("in_band", false))
	var jam: bool = bool(info.get("jammed", false))
	var lamp: StandardMaterial3D = _mat_off
	if locked:
		lamp = _mat_green
	elif in_band:
		lamp = _mat_green
	elif jam:
		lamp = _mat_amber
	else:
		lamp = _mat_red
	if indicator_left != null:
		indicator_left.material_override = lamp
	if indicator_right != null:
		indicator_right.material_override = lamp
	if socket_lamp != null:
		socket_lamp.material_override = _mat_green if locked else (_mat_amber if in_band else _mat_off)
	if _beacon != null:
		var ready: bool = locked or in_band
		_beacon.material_override = _mat_green if ready else (_mat_amber if jam else _mat_red)
		_beacon.visible = ready or fmod(_clock, 0.9) < 0.58
	if _beacon_light != null:
		_beacon_light.light_color = Color(0.30, 1.0, 0.50) if (locked or in_band) else Color(1.0, 0.55, 0.15)
		_beacon_light.light_energy = 1.0 if (locked or in_band) else (0.55 + 0.35 * sin(_clock * 4.0))
