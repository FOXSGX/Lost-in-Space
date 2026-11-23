class_name HammerRig
extends Node3D
## The mechanical resonance bell-hammer.
##
## This is a controlled physical pendulum, not a canned animation: the player
## grabs a rope at the console, leans back to raise the hammer against gravity,
## and releases it. Impact intensity comes from the swing itself, but the pass
## threshold is deliberately forgiving so this never becomes a charge-bar
## minigame.

signal struck(strength: float, impact_position: Vector3)
signal grabbed
signal released
signal weak_swing

const PIVOT_HEIGHT := 4.30
const ARM_LENGTH := 3.50
const MAX_PULL := deg_to_rad(74.0)
const IMPACT_ANGLE := deg_to_rad(-30.0)
const REST_ANGLE := deg_to_rad(2.5)
const GRAVITY := 8.8
const DAMPING := 0.32
const POST_IMPACT_DAMPING := 1.35
const PULL_RATE := 1.25
const PULL_ACCEL := 4.2
const INTERACT_RANGE := 3.0

var mode: String = "idle"
var angle: float = REST_ANGLE
var angular_velocity: float = 0.0
var pull_velocity: float = 0.0
var operator: EchoPlayer = null
var strike_count: int = 0
var last_strength: float = 0.0
var interaction_point: Vector3 = Vector3.ZERO

var _pivot: Node3D
var _head: Node3D
var _rope: MeshInstance3D
var _slack_rope: MeshInstance3D
var _rope_lower: MeshInstance3D
var _ratchet_angle: float = 0.0
var _impact_cooldown: float = 0.0
var _struck_this_swing: bool = false
var _interact_down: bool = false
var _after_impact: bool = false
var _post_impact_time: float = 0.0
var _dust: CPUParticles3D
var _console_light: OmniLight3D
var _gauge: MeshInstance3D
var _audio: Node


func build() -> void:
	name = "HammerRig"
	_audio = get_tree().get_first_node_in_group("audio_director")
	_build_frame()
	_build_pendulum()
	_build_console()
	_build_impact_fx()
	interaction_point = to_global(Vector3(2.25, 1.05, 1.45))
	add_to_group("interactable")
	set_process(true)


func _build_frame() -> void:
	var steel: StandardMaterial3D = MaterialLibrary.metal(Color(0.30, 0.33, 0.36), 0.46, 0.82)
	var dark: StandardMaterial3D = MaterialLibrary.metal(Color(0.12, 0.13, 0.15), 0.58, 0.65)
	var rust: StandardMaterial3D = MaterialLibrary.metal(Color(0.35, 0.20, 0.12), 0.82, 0.28)
	var warning: StandardMaterial3D = MaterialLibrary.painted(Color(0.82, 0.56, 0.10), 0.6)
	var stone: ShaderMaterial = MaterialLibrary.rock()

	var base: MeshInstance3D = BuildKit.cylinder_visual(self, "BaseDais", 2.15, 0.28, Vector3(0.0, 0.14, 0.0), stone)
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var plate: MeshInstance3D = BuildKit.cylinder_visual(self, "BasePlate", 2.30, 0.16, Vector3(0.0, 0.06, 0.0), dark)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Free-standing gantry. The legs sit at +/-1.34 m: the hammer head is 2.0 m
	# wide, so the old +/-0.92 m legs were physically inside the swing envelope
	# (the head passed through both legs on every impact). The top beam is
	# carried by these legs instead of hanging in mid-air 6 m below the roof.
	const LEG_X := 1.34
	const BEAM_Y := 5.55
	for side: int in range(2):
		var sign_value: float = -1.0 if side == 0 else 1.0
		var leg: MeshInstance3D = BuildKit.box_visual(
			self,
			"Leg%d" % side,
			Vector3(0.28, BEAM_Y + 0.15, 0.36),
			Vector3(sign_value * LEG_X, (BEAM_Y + 0.15) * 0.5, 0.0),
			steel
		)
		leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		BuildKit.box_visual(self, "Foot%d" % side, Vector3(1.0, 0.18, 1.5), Vector3(sign_value * LEG_X, 0.11, 0.0), dark)
		BuildKit.cylinder_visual(self, "Bolt%d" % side, 0.10, 0.24, Vector3(sign_value * LEG_X, 0.25, 0.52), rust)
		BuildKit.cylinder_visual(self, "BoltBack%d" % side, 0.10, 0.24, Vector3(sign_value * LEG_X, 0.25, -0.52), rust)
		# Diagonal braces in the side plane (z = +/-0.72) stay clear of the head,
		# which only sweeps inside |z| < 0.45.
		for brace_z: float in [-0.72, 0.72]:
			BuildKit.box_visual(self, "Brace%d_%d" % [side, int(brace_z * 10.0)],
				Vector3(1.05, 0.12, 0.12),
				Vector3(sign_value * 0.72, 2.35, brace_z), dark, Vector3(0.0, 0.0, sign_value * 38.0))
		# Horizontal tie at half height keeps the gantry from reading as two posts.
		BuildKit.box_visual(self, "Tie%d" % side, Vector3(0.12, 0.12, 1.3),
			Vector3(sign_value * LEG_X, 2.55, 0.0), dark)

	var crossbar: MeshInstance3D = BuildKit.box_visual(self, "Crossbar", Vector3(3.15, 0.30, 0.44), Vector3(0.0, BEAM_Y, 0.0), steel)
	crossbar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	BuildKit.box_visual(self, "CrossGusset", Vector3(2.9, 0.12, 0.20), Vector3(0.0, BEAM_Y - 0.19, 0.16), rust)
	# Hanger plates from the beam down to the axle caps: the pivot now visibly
	# hangs from something.
	for side: int in range(2):
		var sign_value: float = -1.0 if side == 0 else 1.0
		BuildKit.box_visual(self, "Hanger%d" % side, Vector3(0.12, BEAM_Y - PIVOT_HEIGHT, 0.34),
			Vector3(sign_value * 0.62, (BEAM_Y + PIVOT_HEIGHT) * 0.5, 0.0), dark)
		BuildKit.cylinder_visual(self, "HangerPin%d" % side, 0.07, 0.20,
			Vector3(sign_value * 0.62, PIVOT_HEIGHT, 0.0), rust, Vector3(0.0, 0.0, 90.0))
	for index: int in range(4):
		var stripe: MeshInstance3D = BuildKit.box_visual(self, "WarningStripe%d" % index, Vector3(0.16, 0.02, 1.30), Vector3(-0.84 + index * 0.56, 1.26, -1.42), warning, Vector3(0.0, 0.0, 18.0))
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Hanging chain links, now attached to the crossbar.
	for side: int in range(2):
		var sign_value: float = -1.0 if side == 0 else 1.0
		for link: int in range(6):
			BuildKit.cylinder_visual(
				self,
				"Chain%d_%d" % [side, link],
				0.035,
				0.20,
				Vector3(sign_value * 0.86, BEAM_Y - 0.28 - link * 0.18, 0.34),
				dark,
				Vector3(0.0, 0.0, 90.0) if link % 2 == 0 else Vector3(90.0, 0.0, 0.0)
			)
		BuildKit.cylinder_visual(self, "ChainHook%d" % side, 0.05, 0.18,
			Vector3(sign_value * 0.86, BEAM_Y - 0.28 - 6 * 0.18, 0.34), rust)

	# The anvil / bell stone the crystal sits on.
	# 高度经 tests/act4_hammer_impact.gd 实测校核：撞击帧锤头底面 y=0.672，
	# 本组铁砧顶面 y=0.805，两者重叠 0.133 m —— 锤头确实落在砧面上，
	# 没有悬空。不要再按"锤头中心 − 半高"手算，实体随摆臂旋转后 AABB 会长大。
	var anvil: MeshInstance3D = BuildKit.cylinder_visual(self, "Anvil", 0.74, 0.44, Vector3(0.0, 0.38, -1.80), stone, Vector3.ZERO, 0.62)
	anvil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var anvil_body: StaticBody3D = StaticBody3D.new()
	anvil_body.name = "AnvilCollision"
	anvil_body.collision_layer = 1
	anvil_body.collision_mask = 0
	anvil_body.position = Vector3(0.0, 0.38, -1.80)
	var anvil_shape: CollisionShape3D = CollisionShape3D.new()
	var anvil_cyl: CylinderShape3D = CylinderShape3D.new()
	anvil_cyl.radius = 0.74
	anvil_cyl.height = 0.56
	anvil_shape.shape = anvil_cyl
	anvil_body.add_child(anvil_shape)
	add_child(anvil_body)
	BuildKit.cylinder_visual(self, "AnvilBand", 0.76, 0.12, Vector3(0.0, 0.55, -1.80), rust)
	var strike_plate: MeshInstance3D = BuildKit.box_visual(self, "StrikePlate", Vector3(0.95, 0.08, 0.42), Vector3(0.0, 0.62, -1.80), steel, Vector3(0.0, 0.0, -18.0))
	strike_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _build_pendulum() -> void:
	var steel: StandardMaterial3D = MaterialLibrary.metal(Color(0.42, 0.45, 0.48), 0.48, 0.82)
	var dark: StandardMaterial3D = MaterialLibrary.metal(Color(0.10, 0.11, 0.125), 0.62, 0.7)
	var rust: StandardMaterial3D = MaterialLibrary.metal(Color(0.40, 0.23, 0.13), 0.8, 0.35)
	var brass: StandardMaterial3D = MaterialLibrary.metal(Color(0.60, 0.44, 0.20), 0.4, 0.8)

	_pivot = Node3D.new()
	_pivot.name = "PendulumPivot"
	_pivot.position = Vector3(0.0, PIVOT_HEIGHT, 0.0)
	add_child(_pivot)

	var axle: MeshInstance3D = BuildKit.cylinder_visual(_pivot, "Axle", 0.22, 1.20, Vector3.ZERO, dark, Vector3(0.0, 0.0, 90.0))
	axle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for side: int in range(2):
		var sign_value: float = -1.0 if side == 0 else 1.0
		BuildKit.cylinder_visual(_pivot, "AxleCap%d" % side, 0.30, 0.10, Vector3(sign_value * 0.62, 0.0, 0.0), brass, Vector3(0.0, 0.0, 90.0))

	# Two side arms make the hammer read as a rigid assembly.
	for side: int in range(2):
		var sign_value: float = -1.0 if side == 0 else 1.0
		var arm: MeshInstance3D = BuildKit.box_visual(
			_pivot,
			"Arm%d" % side,
			Vector3(0.22, ARM_LENGTH, 0.34),
			Vector3(sign_value * 0.24, -ARM_LENGTH * 0.5, 0.0),
			steel
		)
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		BuildKit.box_visual(_pivot, "ArmBrace%d" % side, Vector3(0.18, 0.95, 0.50), Vector3(sign_value * 0.24, -1.05, 0.0), rust, Vector3(0.0, 0.0, sign_value * 8.0))

	var head_root: Node3D = Node3D.new()
	head_root.name = "Head"
	head_root.position = Vector3(0.0, -ARM_LENGTH, 0.0)
	_pivot.add_child(head_root)
	_head = head_root

	var head_body: MeshInstance3D = BuildKit.box_visual(head_root, "HammerHead", Vector3(2.0, 0.78, 0.82), Vector3.ZERO, steel)
	head_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	BuildKit.box_visual(head_root, "HeadBandL", Vector3(0.16, 0.86, 0.90), Vector3(-0.76, 0.0, 0.0), rust)
	BuildKit.box_visual(head_root, "HeadBandR", Vector3(0.16, 0.86, 0.90), Vector3(0.76, 0.0, 0.0), rust)
	BuildKit.box_visual(head_root, "StrikerFace", Vector3(0.42, 0.70, 0.86), Vector3(0.0, -0.02, -0.62), brass)
	BuildKit.cylinder_visual(head_root, "HeadPin", 0.10, 2.10, Vector3(0.0, 0.48, 0.0), dark, Vector3(0.0, 0.0, 90.0))
	# Rope attachment ring on the back of the head.
	BuildKit.cylinder_visual(head_root, "RopeRing", 0.15, 0.10, Vector3(0.0, 0.46, 0.48), brass, Vector3(90.0, 0.0, 0.0))
	var head_probe: Area3D = Area3D.new()
	head_probe.name = "HammerHeadProbe"
	head_probe.collision_layer = 0
	head_probe.collision_mask = 2
	var probe_shape: CollisionShape3D = CollisionShape3D.new()
	var probe_box: BoxShape3D = BoxShape3D.new()
	probe_box.size = Vector3(2.0, 0.78, 0.82)
	probe_shape.shape = probe_box
	head_probe.add_child(probe_shape)
	head_probe.body_entered.connect(func(body: Node3D) -> void:
		if mode != "swinging" or angular_velocity >= -0.35 or _head == null:
			return
		if body.has_method("apply_platform_knock"):
			var push_dir: Vector3 = body.global_position - _head.global_position
			push_dir.y = 0.0
			if push_dir.length_squared() < 0.001:
				push_dir = -global_transform.basis.z
			body.call("apply_platform_knock", push_dir.normalized() * clampf(absf(angular_velocity) * 2.2, 2.0, 5.5) + Vector3(0.0, 1.4, 0.0))
	)
	head_root.add_child(head_probe)

	var rope_mesh: CylinderMesh = CylinderMesh.new()
	rope_mesh.top_radius = 0.035
	rope_mesh.bottom_radius = 0.035
	rope_mesh.height = 1.0
	rope_mesh.radial_segments = 6
	rope_mesh.rings = 1
	_rope = MeshInstance3D.new()
	_rope.name = "PullRope"
	_rope.mesh = rope_mesh
	var rope_material: StandardMaterial3D = MaterialLibrary.painted(Color(0.42, 0.31, 0.17), 0.95)
	rope_material.albedo_color = Color(0.36, 0.27, 0.16)
	_rope.material_override = rope_material
	_rope.visible = false
	add_child(_rope)

	_slack_rope = MeshInstance3D.new()
	_slack_rope.name = "SlackRope"
	var coil: TorusMesh = TorusMesh.new()
	coil.inner_radius = 0.26
	coil.outer_radius = 0.34
	coil.rings = 16
	coil.ring_segments = 6
	_slack_rope.mesh = coil
	_slack_rope.material_override = rope_material
	_slack_rope.position = Vector3(2.25, 1.02, 1.45)
	_slack_rope.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(_slack_rope)


func _build_console() -> void:
	# First-person rebuild. In third person the old console read fine from 5 m
	# away, but in first person the player stands 1.6 m from it: the 0.30 m drum
	# filled a third of the screen and hid the hammer. Everything is now scaled
	# for close inspection and the rope path is physically explained (drum →
	# sheave → hammer head).
	var steel: StandardMaterial3D = MaterialLibrary.metal(Color(0.34, 0.37, 0.40), 0.46, 0.8)
	var dark: StandardMaterial3D = MaterialLibrary.metal(Color(0.11, 0.12, 0.14), 0.6, 0.5)
	var brass: StandardMaterial3D = MaterialLibrary.metal(Color(0.62, 0.45, 0.19), 0.38, 0.82)
	var rust: StandardMaterial3D = MaterialLibrary.metal(Color(0.38, 0.21, 0.11), 0.8, 0.3)
	var warning: StandardMaterial3D = MaterialLibrary.painted(Color(0.86, 0.53, 0.10), 0.52)
	var panel: StandardMaterial3D = MaterialLibrary.painted(Color(0.15, 0.17, 0.19), 0.62)

	BuildKit.omni_light(self, "GantryFill", Vector3(0.0, 4.4, 1.4), Color(1.0, 0.82, 0.58), 2.0, 9.0, false)
	BuildKit.omni_light(self, "AnvilFill", Vector3(0.0, 1.6, -3.0), Color(1.0, 0.74, 0.46), 1.2, 5.0, false)

	# Pedestal: a real bolted cabinet, not a floating cube. Kept waist high so
	# the player looks *over* it at the hammer head instead of at a wall of steel.
	BuildKit.static_box(self, "ConsoleBase", Vector3(0.78, 0.68, 0.62), Vector3(2.25, 0.34, 1.45), steel)
	BuildKit.box_visual(self, "ConsolePlinth", Vector3(0.88, 0.10, 0.72), Vector3(2.25, 0.05, 1.45), dark)
	BuildKit.box_visual(self, "ConsoleKick", Vector3(0.80, 0.14, 0.03), Vector3(2.25, 0.12, 1.77), rust)
	BuildKit.box_visual(self, "ConsoleStripe", Vector3(0.80, 0.09, 0.02), Vector3(2.25, 0.45, 1.77), warning)
	for index: int in range(4):
		var x: float = 2.25 + (-0.30 if index % 2 == 0 else 0.30)
		var y: float = 0.16 if index < 2 else 0.58
		BuildKit.cylinder_visual(self, "ConsoleBolt%d" % index, 0.022, 0.05, Vector3(x, y, 1.77), rust, Vector3(90.0, 0.0, 0.0))
	# Sloped instrument panel with real dials.
	BuildKit.box_visual(self, "ConsolePanel", Vector3(0.84, 0.05, 0.46), Vector3(2.25, 0.705, 1.42), panel, Vector3(-14.0, 0.0, 0.0))
	for index: int in range(3):
		BuildKit.cylinder_visual(self, "PanelDial%d" % index, 0.050, 0.022,
			Vector3(2.07 + index * 0.11, 0.740, 1.32), brass, Vector3(90.0, 0.0, 0.0))
		BuildKit.cylinder_visual(self, "PanelDialFace%d" % index, 0.039, 0.006,
			Vector3(2.07 + index * 0.11, 0.740, 1.30), MaterialLibrary.emissive(Color(0.35, 0.55, 0.42), 0.35), Vector3(90.0, 0.0, 0.0))
	BuildKit.box_visual(self, "PanelPlate", Vector3(0.16, 0.09, 0.03), Vector3(2.48, 0.74, 1.30), warning, Vector3(-14.0, 0.0, 0.0))

	# Rope drum, now 0.17 m radius so the player can see the hammer behind it.
	BuildKit.cylinder_visual(self, "RopeDrum", 0.155, 0.40, Vector3(2.25, 0.80, 1.45), brass, Vector3(0.0, 0.0, 90.0))
	for side: int in range(2):
		var sign_value: float = -1.0 if side == 0 else 1.0
		BuildKit.cylinder_visual(self, "DrumFlange%d" % side, 0.195, 0.026,
			Vector3(2.25 + sign_value * 0.215, 0.80, 1.45), dark, Vector3(0.0, 0.0, 90.0))
		BuildKit.box_visual(self, "DrumCheek%d" % side, Vector3(0.050, 0.38, 0.28),
			Vector3(2.25 + sign_value * 0.285, 0.64, 1.45), steel)
	BuildKit.cylinder_visual(self, "DrumAxle", 0.030, 0.66, Vector3(2.25, 0.80, 1.45), dark, Vector3(0.0, 0.0, 90.0))
	BuildKit.box_visual(self, "CrankArm", Vector3(0.042, 0.24, 0.042), Vector3(2.57, 0.90, 1.45), warning, Vector3(0.0, 0.0, -14.0))
	var grip: MeshInstance3D = BuildKit.sphere_visual(self, "CrankGrip", 0.052, Vector3(2.59, 1.02, 1.45), warning)
	grip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Rope guide: drum → sheave → hammer. This is what makes "pulling" legible
	# in first person: the rope the player sees in hand is the same rope.
	BuildKit.box_visual(self, "GuidePost", Vector3(0.055, 0.90, 0.055), Vector3(2.02, 1.10, 1.45), dark)
	BuildKit.box_visual(self, "GuideArm", Vector3(0.24, 0.055, 0.055), Vector3(2.14, 1.55, 1.45), dark)
	BuildKit.cylinder_visual(self, "SheaveBracket", 0.070, 0.12, Vector3(2.25, 1.55, 1.53), steel, Vector3(90.0, 0.0, 0.0))
	BuildKit.cylinder_visual(self, "SheaveWheel", 0.115, 0.05, Vector3(2.25, 1.55, 1.45), brass, Vector3(0.0, 0.0, 90.0))
	BuildKit.cylinder_visual(self, "SheavePin", 0.026, 0.22, Vector3(2.25, 1.55, 1.45), dark, Vector3(0.0, 0.0, 90.0))
	BuildKit.box_visual(self, "GuideGuard", Vector3(0.15, 0.15, 0.02), Vector3(2.25, 1.55, 1.58), warning)
	BuildKit.cylinder_visual(self, "GuideFoot", 0.095, 0.06, Vector3(2.02, 0.66, 1.45), rust)

	# Lower rope segment (drum to sheave) is built once and shown only when the
	# player holds the rope.
	var lower_mesh: CylinderMesh = CylinderMesh.new()
	lower_mesh.top_radius = 0.020
	lower_mesh.bottom_radius = 0.022
	lower_mesh.height = 1.0
	lower_mesh.radial_segments = 7
	_rope_lower = MeshInstance3D.new()
	_rope_lower.name = "PullRopeLower"
	_rope_lower.mesh = lower_mesh
	_rope_lower.material_override = MaterialLibrary.painted(Color(0.34, 0.26, 0.15), 0.95)
	_rope_lower.position = Vector3(2.25, 1.175, 1.44)
	_rope_lower.scale = Vector3(1.0, 0.75, 1.0)
	_rope_lower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope_lower.visible = false
	add_child(_rope_lower)

	# Lever, gauge and lamp.
	BuildKit.cylinder_visual(self, "LeverBase", 0.070, 0.06, Vector3(2.62, 0.80, 1.62), dark)
	BuildKit.box_visual(self, "ConsoleLever", Vector3(0.055, 0.40, 0.055), Vector3(2.62, 0.95, 1.60), warning, Vector3(0.0, 0.0, 12.0))
	BuildKit.sphere_visual(self, "LeverGrip", 0.058, Vector3(2.66, 1.14, 1.59), warning)
	BuildKit.box_visual(self, "GaugePlate", Vector3(0.28, 0.20, 0.04), Vector3(2.25, 0.96, 1.14), dark, Vector3(-12.0, 0.0, 0.0))
	BuildKit.cylinder_visual(self, "GaugeRim", 0.088, 0.026, Vector3(2.25, 0.98, 1.125), brass, Vector3(90.0, 0.0, 0.0))
	_gauge = BuildKit.cylinder_visual(self, "GaugeNeedle", 0.011, 0.10, Vector3(2.25, 0.98, 1.105), MaterialLibrary.emissive(Color(1.0, 0.42, 0.14), 1.6), Vector3(0.0, 0.0, 30.0))
	_console_light = BuildKit.omni_light(self, "ConsoleLamp", Vector3(2.42, 1.18, 1.55), Color(1.0, 0.62, 0.28), 0.9, 2.6, false)
	BuildKit.box_visual(self, "ConsoleLampHood", Vector3(0.15, 0.045, 0.11), Vector3(2.42, 1.26, 1.55), dark)
	# Cable run from the cabinet into the floor: a real connection instead of a
	# prop standing on nothing.
	BuildKit.cylinder_visual(self, "ConsoleCable", 0.032, 1.10, Vector3(1.88, 0.38, 1.60), dark, Vector3(0.0, 0.0, 74.0))
	BuildKit.box_visual(self, "CableClamp", Vector3(0.15, 0.06, 0.09), Vector3(1.92, 0.06, 1.58), rust)


func _build_impact_fx() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "ImpactDust"
	_dust.emitting = false
	_dust.amount = 24
	_dust.lifetime = 1.4
	_dust.one_shot = true
	_dust.explosiveness = 0.9
	_dust.direction = Vector3(0.0, 1.0, 0.0)
	_dust.spread = 70.0
	_dust.initial_velocity_min = 1.2
	_dust.initial_velocity_max = 3.4
	_dust.gravity = Vector3(0.0, -4.2, 0.0)
	_dust.scale_amount_min = 0.04
	_dust.scale_amount_max = 0.14
	_dust.color = Color(0.62, 0.66, 0.72, 0.55)
	var dust_mesh: SphereMesh = SphereMesh.new()
	dust_mesh.radius = 0.10
	dust_mesh.height = 0.20
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 3
	_dust.mesh = dust_mesh
	_dust.material_override = MaterialLibrary.emissive(Color(0.55, 0.62, 0.72), 0.2)
	_dust.position = Vector3(0.0, 0.95, -1.80)
	add_child(_dust)


func set_operator(player: EchoPlayer) -> void:
	operator = player


func get_interaction_position() -> Vector3:
	return to_global(Vector3(2.25, 1.15, 1.45))


func get_interaction_prompt(_player: Node) -> String:
	if mode == "held":
		return "按住 W 拉索   ·   E 松开撞锤   ·   S 放回"
	if mode != "idle":
		return ""
	return "E 握住撞锤拉索"


func can_grab(player: EchoPlayer) -> bool:
	if mode != "idle":
		return false
	if player == null or player.carrying != null:
		return false
	var anchor: Vector3 = get_interaction_position()
	return player.global_position.distance_to(anchor) <= INTERACT_RANGE


func interact(player: EchoPlayer) -> void:
	if not can_grab(player):
		return
	grab(player)


func grab(player: EchoPlayer) -> void:
	if player == null:
		return
	operator = player
	player.set_input_enabled(false)
	mode = "held"
	angular_velocity = 0.0
	pull_velocity = 0.0
	_struck_this_swing = false
	_after_impact = false
	_post_impact_time = 0.0
	_interact_down = Input.is_action_pressed("interact")
	_ratchet_angle = angle
	_rope.visible = true
	if _rope_lower != null:
		_rope_lower.visible = true
	_slack_rope.visible = false
	if _audio != null and _audio.has_method("start_loop"):
		_audio.call("start_loop", "hammer_creak", 0.35)
	grabbed.emit()


func release_hammer() -> void:
	if mode != "held":
		return
	mode = "swing"
	angular_velocity = 0.0
	_struck_this_swing = false
	_after_impact = false
	_post_impact_time = 0.0
	if _audio != null and _audio.has_method("stop_loop"):
		_audio.call("stop_loop", "hammer_creak")
	released.emit()
	if is_instance_valid(operator):
		operator.set_input_enabled(true)
	_rope.visible = false
	if _rope_lower != null:
		_rope_lower.visible = false
	_slack_rope.visible = true
	if angle < deg_to_rad(16.0):
		if _audio != null and _audio.has_method("play_ui"):
			_audio.call("play_ui", "weak_release")
		weak_swing.emit()


## 摆动积分必须跑在物理帧上：`last_strength = 0.58 + 0.42·|ω|` 直接来自这里的
## `angular_velocity`，而 `angle < IMPACT_ANGLE` 的撞击判据也是离散采样。
## 放在 `_process` 时，同一操作在 30 fps 与 60 fps 下会打出不同强度，卡顿还会
## 让判据窗口被跳过。表现（视觉/绳子）留在 `_process`。
func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)
	if mode == "held":
		_update_held(delta)
	elif mode == "swing":
		_update_swing(delta)


func _process(_delta: float) -> void:
	_update_visuals()
	if _rope.visible:
		_update_rope()


func _update_held(delta: float) -> void:
	var pull_input: float = 0.0
	if Input.is_action_pressed("move_forward"):
		pull_input += 1.0
	if Input.is_action_pressed("move_back"):
		pull_input -= 1.0
	var target_velocity: float = pull_input * PULL_RATE
	pull_velocity = move_toward(pull_velocity, target_velocity, PULL_ACCEL * delta)
	angle += pull_velocity * delta
	if angle > MAX_PULL:
		angle = MAX_PULL
		pull_velocity = 0.0
	if angle < REST_ANGLE:
		angle = REST_ANGLE
		pull_velocity = maxf(pull_velocity, 0.0)
	if absf(angle - _ratchet_angle) > deg_to_rad(10.0):
		_ratchet_angle = angle
		if _audio != null and _audio.has_method("play_at"):
			_audio.call("play_at", "hammer_ratchet", get_interaction_position(), 0.32)
	if is_instance_valid(operator):
		var interact_pressed: bool = Input.is_action_pressed("interact")
		var interact_edge: bool = interact_pressed and not _interact_down
		_interact_down = interact_pressed
		if interact_edge:
			release_hammer()
		elif operator.global_position.distance_to(get_interaction_position()) > INTERACT_RANGE + 0.6:
			release_hammer()


func _update_swing(delta: float) -> void:
	var damping: float = POST_IMPACT_DAMPING if _after_impact else DAMPING
	var acceleration: float = -(GRAVITY / ARM_LENGTH) * sin(angle) - damping * angular_velocity
	angular_velocity += acceleration * delta
	angle += angular_velocity * delta
	if _after_impact:
		_post_impact_time += delta
	if angle > MAX_PULL + 0.06:
		angle = MAX_PULL + 0.06
		angular_velocity = minf(angular_velocity, 0.0)
	if angle < IMPACT_ANGLE and angular_velocity < 0.0 and _impact_cooldown <= 0.0 and not _struck_this_swing:
		_do_impact()
	if (absf(angle) < REST_ANGLE + 0.10 and absf(angular_velocity) < 0.35) or _post_impact_time > 4.0:
		angle = REST_ANGLE
		angular_velocity = 0.0
		_after_impact = false
		_post_impact_time = 0.0
		mode = "idle"
		if is_instance_valid(operator):
			operator.set_input_enabled(true)
			operator = null


func _do_impact() -> void:
	var impact_speed: float = absf(angular_velocity)
	last_strength = clampf(0.58 + impact_speed * 0.42, 0.58, 1.20)
	strike_count += 1
	_impact_cooldown = 0.65
	_struck_this_swing = true
	_after_impact = true
	_post_impact_time = 0.0
	angular_velocity = impact_speed * 0.24
	angle = IMPACT_ANGLE + 0.015
	_dust.restart()
	_dust.emitting = true
	var impact_position: Vector3 = to_global(Vector3(0.0, 1.05, -1.80))
	if is_instance_valid(operator):
		operator.shake(0.16, 0.32)
	struck.emit(last_strength, impact_position)
	if _audio != null and _audio.has_method("play_at"):
		_audio.call("play_at", "hammer_impact", impact_position, 0.95)


func _update_visuals() -> void:
	if _pivot != null:
		_pivot.rotation.x = -angle
	if _gauge != null:
		_gauge.rotation.z = lerpf(_gauge.rotation.z, -angle * 1.5, 0.18)
	if _console_light != null:
		_console_light.light_energy = 0.65 + (0.45 if mode == "held" else 0.0)


func _update_rope() -> void:
	if _rope == null or _pivot == null:
		return
	var head_point: Vector3 = to_global(Vector3(0.0, PIVOT_HEIGHT - ARM_LENGTH * cos(angle) + 0.46, ARM_LENGTH * sin(angle) + 0.48))
	var anchor_point: Vector3 = to_global(Vector3(2.25, 1.55, 1.45))
	var mid: Vector3 = (head_point + anchor_point) * 0.5
	var direction: Vector3 = anchor_point - head_point
	var length: float = direction.length()
	if length < 0.05:
		return
	_rope.global_position = mid
	_rope.look_at(anchor_point, Vector3.UP)
	_rope.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	_rope.scale = Vector3(1.0, length, 1.0)


func reset_hammer() -> void:
	mode = "idle"
	angle = REST_ANGLE
	angular_velocity = 0.0
	pull_velocity = 0.0
	if is_instance_valid(operator):
		operator.set_input_enabled(true)
		operator = null
	if _rope != null:
		_rope.visible = false
	if _rope_lower != null:
		_rope_lower.visible = false
	if _slack_rope != null:
		_slack_rope.visible = true
	if _audio != null and _audio.has_method("stop_loop"):
		_audio.call("stop_loop", "hammer_creak")
	_update_visuals()
