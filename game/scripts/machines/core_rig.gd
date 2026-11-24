class_name CoreRig
extends Node3D

## The hanging resonance core. A controlled dynamic model (not a rigid-body
## multibody simulation): the two counterweight positions produce a net moment,
## the core swings toward it with inertia, damping and machine forcing, and the
## hydraulic claw can only capture it inside a real, forgiving range.

signal telemetry(net: float, angle: float, omega: float, capturable: bool, locked: bool)
signal lock_failed(reason: String)
signal lock_started()
signal locked_done()
signal surge_shock(strength: float)

const NET_BIAS := 0.22
const NET_GAIN := 0.55
const CAPTURE_NET := 0.14
const CAPTURE_OMEGA := 0.32
const LOCK_DURATION := 1.55

# --- real load path to the stabiliser legs (MECHANICS-005A) ----------------
# The swing model stays a constrained 1-DOF dynamics model, but it now exposes
# the physical quantities the outriggers need:
#   * the gravity moment of the suspended assembly per unit of net imbalance,
#   * the moment arm of the pads on the outer gimbal ring,
#   * a pad damper against the swinging ring,
#   * the Coulomb friction the latched pads apply to that ring.
# Units are SI: N.m, m, N, N.m.s/rad, kg.m^2.
const TORQUE_PER_NET := 420000.0   # N.m at |net| = 1 (curved pendulum + cage)
const PAD_DAMP := 6.0e3            # N.s/m pad damper against the swinging ring
const RING_PAD_RADIUS := 4.72      # m - outer ring trim radius (pad contact)
const PAD_MU := 0.12               # pad / ring friction coefficient
const CORE_SWING_INERTIA := 5.3e5  # kg.m^2 (85 t assembly, 2.5 m CG arm)
const CLAMP_FULL := 141371.67      # N - both legs at the 160 bar relief
const CLAMP_WINDOW_GAIN := 0.11    # capture window widened by a full clamp

# --- MECHANICS-005A-R2: real contact geometry of the outer gimbal ring -----
# Measured from the authored meshes: ring body radius 4.45..4.75, trim outer
# face 4.76, ClampPad bosses 4.90. The pads press the outer cylindrical face,
# so the contact surface is a cylinder of radius RING_OUTER_RADIUS about the
# ring axis. The 8 ClampPad bosses are NOT modelled as contact faces: they
# sweep past the legs with outer_yaw and would make contact intermittent.
const RING_OUTER_RADIUS := 4.76    # m
const RING_INNER_RADIUS := 4.45    # m
const CORE_CONTACT_SUBSTEPS := 8   # contact spring is stiff vs J; substep it
const PIVOT_TO_RING := 10.9        # m, swing pivot to ring plane
## Swing envelope sized to the outrigger band (see _update_dynamics).
const SWING_LIMIT := 0.58         # rad hard envelope (R0 safety stop)
const SWING_PER_NET := 0.62       # rad per unit net imbalance (R0 magnitude)

var left_p: float = 0.88
var right_p: float = 0.12
var net: float = 0.0
var angle: float = 0.0
var omega: float = 0.0
var locked: bool = false
var locking: bool = false
var lock_elapsed: float = 0.0
var capturable: bool = false
var surge_timer: float = 0.0
var surge_strength: float = 0.0
var time: float = 0.0
var data_mode: bool = false
var telemetry_accum: float = 0.0
# --- V2 co-op machinery ----------------------------------------------------
# Two hydraulic stabiliser legs press the outer ring; both latched legs widen the
# capture window and are a hard mechanical interlock for the claw. Brake
# pressure reduces the recoil. `remote` turns local integration off on clients.
var stabilizer_states: Array[bool] = [false, false]
# Per-leg mechanical feedback (host authority publishes, clients mirror):
#   contact: the pad is touching the outer ring
#   clamp:   the pad's normal force N = p_cylinder * A_piston
var stabilizer_contact: Array[bool] = [false, false]
## Real per-pad contact normal force this frame, N (0 when the pad is in the air).
var pad_reaction: Array[float] = [0.0, 0.0]
var stabilizer_clamp: Array[float] = [0.0, 0.0]
var brake_applied: float = 0.0
var remote: bool = false
var remote_angle: float = 0.0
var remote_net: float = 0.0
var remote_omega: float = 0.0

var swing: Node3D
var crystal_pivot: Node3D
var shard_pivot: Node3D
var outer_ring: Node3D
var middle_ring: Node3D
var inner_ring: Node3D
var field_a: Node3D
var field_b: Node3D
var core_light: OmniLight3D
var fill_light: OmniLight3D
var outer_ring_kit: WorldKit
var middle_ring_kit: WorldKit
var inner_ring_kit: WorldKit
var kit: WorldKit
var crystal_material: ShaderMaterial
var ring_energy_material: ShaderMaterial
var _built: bool = false
# Ring motion is authored as three explicit scalars and rebuilt as a basis each
# frame; stacking Euler rotations made the trunnions and their brackets drift.
var outer_yaw: float = 0.0
var middle_tilt: float = 0.0
var inner_spin: float = 0.0
const CAGE_RADIUS := 5.30
const CAGE_TOP_LOCAL := 9.20
const OUTER_RING_Y := -10.90


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	name = "ResonanceCore"
	swing = Node3D.new()
	swing.name = "Swing"
	add_child(swing)
	kit = WorldKit.new(swing)
	_build_suspension()
	_build_rings()
	_build_crystal()
	_build_lights()
	_update_dynamics(0.0)


func _build_suspension() -> void:
	var steel: Material = MatLib.dark_steel()
	var bronze: Material = MatLib.bronze()
	kit.cylinder("PivotBearing", 1.05, 1.7, Vector3(0, -0.9, 0), steel, Vector3.ZERO, false, 24)
	kit.ring_box("BearingCollarTop", 1.22, 0.34, 0.22, Vector3(0, -0.05, 0), bronze, Basis(), 48, false)
	kit.ring_box("BearingCollarBottom", 1.22, 0.34, 0.22, Vector3(0, -1.72, 0), bronze, Basis(), 48, false)
	kit.rivet_ring(Vector3(0, -0.08, 0), 1.22, 18, Vector3.UP, MatLib.steel())
	kit.rivet_ring(Vector3(0, -1.70, 0), 1.22, 18, Vector3.UP, MatLib.steel())
	for i in range(3):
		var a: float = TAU * float(i) / 3.0 + PI * 0.5
		var top: Vector3 = Vector3(cos(a) * 0.9, 0.4, sin(a) * 0.9)
		var hub_out: Vector3 = Vector3(cos(a) * 1.0, -1.2, sin(a) * 1.0)
		kit.beam("HangerTie", top, hub_out, 0.075, steel, false, 8)
	# Central damper, hung from the pivot's lower race. It sits ~6 m above the
	# crystal and never enters the ring envelope.
	kit.cylinder("DamperRod", 0.15, 1.0, Vector3(0, -2.15, 0), steel, Vector3.ZERO, false, 12)
	kit.cylinder("Damper", 0.36, 1.1, Vector3(0, -3.0, 0), MatLib.painted_steel(Color(0.35, 0.22, 0.12)), Vector3.ZERO, false, 16)
	kit.torus("DamperSpring", 0.42, 0.06, Vector3(0, -2.65, 0), bronze, Basis(), 24, 6)
	kit.torus("DamperSpring2", 0.42, 0.06, Vector3(0, -3.25, 0), bronze, Basis(), 24, 6)


func _build_rings() -> void:
	var ring_mat: Material = MatLib.painted_steel(Color(0.30, 0.36, 0.40))
	var trim: Material = MatLib.bronze()
	# Outer gimbal ring (horizontal carousel). The suspension cage is built as a
	# child of this ring so the cage, its rollers and the ring yaw together.
	outer_ring = Node3D.new()
	outer_ring.name = "OuterRing"
	outer_ring.position = Vector3(0, OUTER_RING_Y, 0)
	swing.add_child(outer_ring)
	outer_ring_kit = WorldKit.new(outer_ring)
	outer_ring_kit.ring_box("RingBody", 4.6, 0.30, 0.30, Vector3.ZERO, ring_mat, Basis(), 72, false)
	outer_ring_kit.ring_box("TopTrim", 4.72, 0.46, 0.08, Vector3(0, 0.22, 0), trim, Basis(), 72, false)
	outer_ring_kit.ring_box("BottomTrim", 4.72, 0.46, 0.08, Vector3(0, -0.22, 0), trim, Basis(), 72, false)
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		var pad_pos: Vector3 = Vector3(cos(a) * 4.55, 0, sin(a) * 4.55)
		outer_ring_kit.box("ClampPad", Vector3(0.7, 0.5, 0.44), pad_pos, MatLib.dark_steel(), Vector3(0, -a, 0), false)
		outer_ring_kit.cylinder("PadBolt", 0.09, 0.52, pad_pos + Vector3(0, 0.3, 0), trim, Vector3.ZERO, false, 8)
	outer_ring_kit.rivet_ring(Vector3.ZERO, 4.6, 40, Vector3.UP, MatLib.steel())
	ring_energy_material = MatLib.energy(Color(0.16, 0.82, 1.0), 0.55, 0.5, 3.0)
	outer_ring_kit.torus("EnergyBandA", 4.63, 0.030, Vector3(0, 0.28, 0), ring_energy_material, Basis(), 64, 6)
	outer_ring_kit.torus("EnergyBandB", 4.63, 0.030, Vector3(0, -0.28, 0), ring_energy_material, Basis(), 64, 6)
	# Two trunnion brackets at the X axis carry the middle ring.
	for side in [-1.0, 1.0]:
		outer_ring_kit.box("TrunnionBracket", Vector3(0.36, 0.46, 0.66), Vector3(side * 4.30, -0.12, 0), MatLib.steel(), Vector3.ZERO, false)
		outer_ring_kit.cylinder("TrunnionPin", 0.11, 0.56, Vector3(side * 4.06, -0.12, 0), trim, Vector3(0, 0, PI * 0.5), false, 12)
		outer_ring_kit.box("TrunnionCap", Vector3(0.18, 0.34, 0.34), Vector3(side * 4.44, -0.12, 0), MatLib.dark_steel(), Vector3.ZERO, false)
	_build_cage()

	# Middle gimbal ring (vertical, tilts about the X trunnions).
	middle_ring = Node3D.new()
	middle_ring.name = "MiddleRing"
	middle_ring.position = Vector3(0, -11.0, 0)
	swing.add_child(middle_ring)
	middle_ring_kit = WorldKit.new(middle_ring)
	middle_ring_kit.ring_box("RingBody", 4.02, 0.26, 0.42, Vector3.ZERO, MatLib.painted_steel(Color(0.26, 0.33, 0.38)), Basis(), 64, false)
	middle_ring_kit.ring_box("Trim", 4.10, 0.44, 0.09, Vector3(0, 0.35, 0), trim, Basis(), 64, false)
	for i in range(6):
		var a2: float = TAU * float(i) / 6.0
		middle_ring_kit.box("Pad", Vector3(0.5, 0.36, 0.62), Vector3(cos(a2) * 4.0, 0, sin(a2) * 4.0), MatLib.steel(), Vector3(0, -a2, 0), false)
	middle_ring_kit.rivet_ring(Vector3.ZERO, 4.02, 32, Vector3.UP, MatLib.steel())
	middle_ring_kit.torus("EnergyBand", 4.06, 0.03, Vector3(0, 0.4, 0), ring_energy_material, Basis(), 56, 6)
	# Trunnion pins that sit inside the outer ring's brackets.
	for side in [-1.0, 1.0]:
		middle_ring_kit.cylinder("PivotPin", 0.10, 0.42, Vector3(side * 4.02, 0, 0), MatLib.bronze(), Vector3(0, 0, PI * 0.5), false, 10)
		middle_ring_kit.box("PivotBlock", Vector3(0.26, 0.30, 0.38), Vector3(side * 3.86, 0, 0), MatLib.dark_steel(), Vector3.ZERO, false)
	# Inner-hoop roller brackets at the top and bottom of this ring.
	for top in [-1.0, 1.0]:
		middle_ring_kit.box("RollerBracket", Vector3(0.26, 0.34, 0.72), Vector3(0, 0, top * 3.70), MatLib.steel(), Vector3.ZERO, false)
		middle_ring_kit.cylinder("RollerPin", 0.09, 0.42, Vector3(0, 0, top * 3.40), MatLib.bronze(), Vector3(0, 0, PI * 0.5), false, 10)

	# Inner ring (spins inside the middle hoop on the roller pins).
	inner_ring = Node3D.new()
	inner_ring.name = "InnerRing"
	inner_ring.position = Vector3(0, -11.2, 0)
	swing.add_child(inner_ring)
	inner_ring_kit = WorldKit.new(inner_ring)
	inner_ring_kit.ring_box("RingBody", 3.38, 0.24, 0.38, Vector3.ZERO, MatLib.painted_steel(Color(0.22, 0.29, 0.34)), Basis(), 56, false)
	inner_ring_kit.ring_box("Trim", 3.45, 0.38, 0.08, Vector3(0, 0.31, 0), trim, Basis(), 56, false)
	for i in range(4):
		var a3: float = TAU * float(i) / 4.0
		inner_ring_kit.box("Pad", Vector3(0.44, 0.3, 0.54), Vector3(cos(a3) * 3.36, 0, sin(a3) * 3.36), MatLib.dark_steel(), Vector3(0, -a3, 0), false)
	inner_ring_kit.rivet_ring(Vector3.ZERO, 3.38, 24, Vector3.UP, MatLib.steel())
	inner_ring_kit.torus("EnergyBand", 3.42, 0.028, Vector3(0, 0.34, 0), ring_energy_material, Basis(), 48, 6)
	for side in [-1.0, 1.0]:
		inner_ring_kit.cylinder("RollerPin", 0.085, 0.36, Vector3(side * 3.36, 0, 0), MatLib.bronze(), Vector3.ZERO, false, 10)


func _build_cage() -> void:
	# Suspension cage: a top roller collar around the fixed pivot, three radial
	# spokes, three vertical tension rods outside every ring, and three bottom
	# clamps on the outer ring. Nothing crosses the crystal or the ring envelope.
	var steel: Material = MatLib.dark_steel()
	var bronze: Material = MatLib.bronze()
	outer_ring_kit.ring_box("CageCollar", 1.18, 0.22, 0.26, Vector3(0, CAGE_TOP_LOCAL, 0), MatLib.painted_steel(Color(0.24, 0.27, 0.29)), Basis(), 40, false)
	outer_ring_kit.ring_box("CageCollarTrim", 1.30, 0.12, 0.10, Vector3(0, CAGE_TOP_LOCAL + 0.16, 0), bronze, Basis(), 40, false)
	for i in range(3):
		var a: float = TAU * float(i) / 3.0 + PI * 0.5
		var dir: Vector3 = Vector3(cos(a), 0, sin(a))
		var top: float = CAGE_TOP_LOCAL
		outer_ring_kit.beam("CageSpoke", dir * 1.20 + Vector3(0, top, 0), dir * CAGE_RADIUS + Vector3(0, top, 0), 0.11, steel, false, 8)
		outer_ring_kit.beam("CageRod", dir * CAGE_RADIUS + Vector3(0, top, 0), dir * CAGE_RADIUS + Vector3(0, 0.34, 0), 0.095, MatLib.steel(), false, 8)
		outer_ring_kit.beam("CageBrace", dir * 1.30 + Vector3(0, top + 0.70, 0), dir * CAGE_RADIUS + Vector3(0, top - 0.85, 0), 0.055, bronze, false, 6)
		outer_ring_kit.box("CageTopClamp", Vector3(0.46, 0.28, 0.30), dir * 4.10 + Vector3(0, top, 0), MatLib.dark_steel(), Vector3(0, -a, 0), false)
		outer_ring_kit.box("CageBottomClamp", Vector3(0.52, 0.34, 0.42), dir * 5.02 + Vector3(0, 0.10, 0), MatLib.dark_steel(), Vector3(0, -a, 0), false)
		outer_ring_kit.beam("CageFoot", dir * 4.74 + Vector3(0, 0.02, 0), dir * CAGE_RADIUS + Vector3(0, 0.34, 0), 0.075, bronze, false, 6)


func _build_crystal() -> void:
	crystal_pivot = Node3D.new()
	crystal_pivot.name = "CrystalPivot"
	crystal_pivot.position = Vector3(0, -11.2, 0)
	swing.add_child(crystal_pivot)
	var ckit: WorldKit = WorldKit.new(crystal_pivot)
	crystal_material = MatLib.core_crystal()
	var outer: MeshInstance3D = ckit.crystal("CoreCrystal", Vector3(0, -2.65, 0), 5.3, 1.32, 8, crystal_material, Basis(), 1.73)
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var inner: MeshInstance3D = ckit.crystal("InnerCrystal", Vector3(0, -2.2, 0), 4.2, 0.82, 8, MatLib.crystal(Color(0.65, 0.35, 1.0), Color(0.35, 0.9, 1.0), 0.7, 1.8), Basis(Vector3.UP, 0.3), 2.9)
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# capture collar the claws grab
	ckit.ring_box("CaptureCollar", 1.0, 0.34, 0.46, Vector3(0, -2.75, 0), MatLib.dark_steel(), Basis(), 32, false)
	ckit.ring_box("CollarTrim", 1.08, 0.42, 0.10, Vector3(0, -2.52, 0), MatLib.bronze(), Basis(), 32, false)
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		ckit.box("GuideLug", Vector3(0.22, 0.24, 0.5), Vector3(cos(a) * 1.2, -2.74, sin(a) * 1.2), MatLib.bronze(), Vector3(0, -a, 0), false)
	# No loose shards below the collar: the old cluster passed straight through
	# the capture collar and sat inside the closed claw jaws.
	# constraint field rings
	field_a = Node3D.new()
	field_a.name = "FieldRingA"
	field_a.position = Vector3(0, -2.1, 0)
	crystal_pivot.add_child(field_a)
	var fk: WorldKit = WorldKit.new(field_a)
	fk.torus("FieldA", 2.15, 0.028, Vector3.ZERO, MatLib.energy(Color(0.45, 0.85, 1.0), 0.65, 0.8, 4.0), Basis(), 56, 6)
	field_b = Node3D.new()
	field_b.name = "FieldRingB"
	field_b.position = Vector3(0, -2.1, 0)
	field_b.rotation = Vector3(0, 0, deg_to_rad(58))
	crystal_pivot.add_child(field_b)
	var fk2: WorldKit = WorldKit.new(field_b)
	fk2.torus("FieldB", 2.35, 0.024, Vector3.ZERO, MatLib.energy(Color(0.55, 0.55, 1.0), 0.5, -0.6, 5.0), Basis(), 56, 6)
	# orbiting data shards
	shard_pivot = Node3D.new()
	shard_pivot.name = "ShardOrbit"
	shard_pivot.position = Vector3(0, -2.25, 0)
	crystal_pivot.add_child(shard_pivot)
	for i in range(3):
		var a3: float = TAU * float(i) / 3.0
		var sh: MeshInstance3D = ckit.crystal("OrbitShard", Vector3(cos(a3) * 2.75, 0.35 * sin(float(i) * 2.0), sin(a3) * 2.75), 0.55, 0.13, 5, MatLib.crystal(Color(0.6, 0.9, 1.0), Color(0.55, 0.4, 1.0), 2.2, 2.0), Basis(Vector3.UP, a3), 4.2 + float(i))
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_lights() -> void:
	core_light = OmniLight3D.new()
	core_light.name = "CoreLight"
	core_light.position = Vector3(0, -11.2, 0)
	core_light.light_color = Color(0.28, 0.85, 1.0)
	core_light.light_energy = 3.2
	core_light.omni_range = 24.0
	core_light.omni_attenuation = 1.08
	core_light.shadow_enabled = true
	core_light.light_specular = 0.4
	swing.add_child(core_light)
	fill_light = OmniLight3D.new()
	fill_light.name = "CoreFill"
	fill_light.position = Vector3(0, -9.6, 0)
	fill_light.light_color = Color(0.55, 0.42, 1.0)
	fill_light.light_energy = 2.4
	fill_light.omni_range = 18.0
	fill_light.omni_attenuation = 1.15
	fill_light.shadow_enabled = false
	swing.add_child(fill_light)


func _physics_process(delta: float) -> void:
	if not _built:
		return
	time += delta
	if remote:
		angle = lerpf(angle, remote_angle, minf(1.0, delta * 12.0))
		net = remote_net
		omega = remote_omega
		capturable = (not locked) and absf(net) <= capture_net_limit() and absf(omega) <= CAPTURE_OMEGA
	else:
		_update_dynamics(delta)
	_update_visuals(delta)
	telemetry_accum += delta
	if telemetry_accum >= 0.08:
		telemetry_accum = 0.0
		telemetry.emit(net, angle, omega, capturable, locked)


func _update_dynamics(delta: float) -> void:
	if delta <= 0.0:
		net = NET_GAIN * (right_p - left_p) + NET_BIAS
		return
	net = NET_GAIN * (right_p - left_p) + NET_BIAS
	# MECHANICS-005A-R2: the swing amplitude is sized to the outrigger's reachable
	# band, not chosen for looks. The ring hangs PIVOT_TO_RING below the pivot, so the
	# ring centre moves PIVOT_TO_RING*sin(angle) sideways. The pads sweep
	# R_pad = 5.930..3.580 with the ring face at 4.760, so they can follow a ring
	# offset of about +-1.13 m. SWING_PER_NET 0.15 keeps a balanced core (net 0.14)
	# comfortably inside that band while an unbalanced one (net 0.64) sits at the
	# edge - which is what forces the player to trim the counterweights first.
	var target: float = clampf(net, -0.95, 0.95) * SWING_PER_NET
	if not locked:
		var k: float = 1.75
		var damp: float = 0.78
		omega += (target - angle) * k * delta
		omega -= omega * damp * delta
		var drive: float = 0.26 * (0.35 + absf(net))
		omega += sin(time * 2.28) * drive * delta
		omega += sin(time * 3.71 + 1.2) * 0.06 * delta
		if surge_timer > 0.0:
			omega += sin(time * 12.0) * 1.4 * surge_strength * delta
		# A latched pad pair presses the ring with N = p * A and resists the
		# swing with Coulomb friction tau = mu * N * r_pad. It damps the swing
		# but can never reverse it, so the counterweights remain the only way to
		# remove the imbalance moment.
		var tau_f: float = stabilizer_friction_torque()
		if tau_f > 0.0:
			omega = move_toward(omega, 0.0, (tau_f / CORE_SWING_INERTIA) * delta)
		angle += omega * delta
		angle = clampf(angle, -SWING_LIMIT, SWING_LIMIT)
		# MECHANICS-005A-R2: the pads are a one-sided constraint on the swing. If any
		# pad is carrying load, the ring cannot travel further INTO it: remove the
		# velocity component that would drive it deeper. Without this the spring drive
		# buries the ring in the pad every frame while the pad only pushes back on
		# penetration, so the two never agree and the ring sinks in.
		_resolve_pad_constraint()
	else:
		angle = move_toward(angle, 0.0, delta * 0.55)
		omega = move_toward(omega, 0.0, delta * 0.9)
	if surge_timer > 0.0:
		surge_timer = maxf(0.0, surge_timer - delta)
		if surge_timer <= 0.0:
			surge_strength = 0.0
	capturable = (not locked) and absf(net) <= capture_net_limit() and absf(omega) <= CAPTURE_OMEGA
	if locking:
		lock_elapsed += delta
		if lock_elapsed >= LOCK_DURATION:
			locking = false
			locked = true
			locked_done.emit()


## One-sided contact constraint on the swing (velocity level).
##
## A pad can only PUSH the ring, so while any pad carries load the ring must not
## travel further along that pad's push direction. Rather than let the spring
## drive bury the ring in a pad and hope the penalty force pushes it back out,
## the swing velocity that would drive it deeper is removed. The reaction torque
## itself still comes from the legs via apply_pad_reaction(), so the force chain
## stays pad -> ring and is driven by real contact geometry.
func _resolve_pad_constraint() -> void:
	var load_total: float = 0.0
	for f in pad_reaction:
		load_total += f
	if load_total <= 1.0:
		return
	# Which pad is loaded tells us which way the ring is being held. Index 0 is
	# the west leg (pushes the ring toward +angle), index 1 the east leg.
	var held_pos: bool = pad_reaction.size() > 0 and pad_reaction[0] > 1.0
	var held_neg: bool = pad_reaction.size() > 1 and pad_reaction[1] > 1.0
	if held_pos and omega > 0.0:
		omega = 0.0
	elif held_neg and omega < 0.0:
		omega = 0.0


func _update_visuals(delta: float) -> void:
	var instability: float = clampf(absf(net) / 0.6 + absf(omega) * 0.35, 0.0, 1.0)
	swing.rotation.z = angle
	swing.rotation.x = sin(time * 0.7) * 0.012 + angle * 0.16
	if not locked:
		outer_yaw += delta * (0.10 + instability * 0.10)
		middle_tilt = lerpf(middle_tilt, sin(time * 0.55) * 0.22 + angle * 0.10, 0.04)
		inner_spin += delta * (0.26 + instability * 0.34)
		crystal_pivot.rotation.y += delta * (0.14 + instability * 0.15)
		shard_pivot.rotation.y -= delta * (0.5 + instability * 0.6)
		field_a.rotation = Vector3(time * 0.4, time * 0.7, 0.2)
		field_b.rotation = Vector3(0, time * -0.5, deg_to_rad(58) + time * 0.3)
	else:
		outer_yaw = move_toward(outer_yaw, 0.0, delta * 0.2)
		middle_tilt = move_toward(middle_tilt, 0.0, delta * 0.22)
		inner_spin += delta * 0.05
		crystal_pivot.rotation.y += delta * 0.04
		shard_pivot.rotation.y += delta * 0.06
		field_a.rotation = Vector3(0, time * 0.12, 0)
		field_b.rotation = Vector3(0, 0, deg_to_rad(58) + time * 0.08)
	_apply_ring_pose()
	var base_energy: float = 3.4 if not locked else 2.3
	if data_mode:
		base_energy = 5.6
	core_light.light_energy = lerpf(core_light.light_energy, base_energy + sin(time * 2.2) * 0.32 * (0.4 + instability), 0.1)
	fill_light.light_energy = lerpf(fill_light.light_energy, (1.25 if not locked else 1.0) + instability * 1.1 + (1.9 if data_mode else 0.0), 0.1)
	if surge_timer > 0.0:
		core_light.light_color = Color(1.0, 0.35, 0.18)
		fill_light.light_color = Color(1.0, 0.55, 0.2)
	else:
		core_light.light_color = Color(0.28, 0.85, 1.0) if not data_mode else Color(0.7, 0.95, 1.0)
		fill_light.light_color = Color(0.55, 0.42, 1.0) if not data_mode else Color(0.7, 0.6, 1.0)
	if crystal_material != null:
		crystal_material.set_shader_parameter("emission_energy", 0.24 + instability * 0.30 + (0.55 if data_mode else 0.0) + (0.25 if surge_timer > 0.0 else 0.0))
		crystal_material.set_shader_parameter("pulse_speed", 1.05 + instability * 1.7)
	if ring_energy_material != null:
		ring_energy_material.set_shader_parameter("pulse", instability * 1.5 + (1.0 if surge_timer > 0.0 else 0.0))


func _apply_ring_pose() -> void:
	# The outer ring yaws; the middle ring is carried by that yaw and tilts on
	# its X trunnions; the inner hoop is carried by both and spins on its rollers.
	var yaw: Basis = Basis(Vector3.UP, outer_yaw)
	outer_ring.basis = yaw
	middle_ring.basis = yaw * Basis(Vector3.RIGHT, PI * 0.5 + middle_tilt)
	inner_ring.basis = yaw * Basis(Vector3.RIGHT, middle_tilt + inner_spin) * Basis(Vector3.BACK, PI * 0.5)


func set_weights(new_left: float, new_right: float) -> void:
	left_p = clampf(new_left, 0.0, 1.0)
	right_p = clampf(new_right, 0.0, 1.0)


func get_net() -> float:
	return net


func get_angle() -> float:
	return angle


func get_omega() -> float:
	return omega


func is_capturable() -> bool:
	return capturable


func is_locked() -> bool:
	return locked


func is_locking() -> bool:
	return locking


func get_time() -> float:
	return time


func get_stability() -> float:
	return clampf(1.0 - absf(net) / 0.55, 0.0, 1.0)


func request_lock() -> Dictionary:
	if locked:
		return {"ok": false, "reason": "核心已经锁定"}
	if locking:
		return {"ok": false, "reason": "锁爪正在动作"}
	var interlock: String = lock_interlock_reason()
	if interlock != "":
		lock_failed.emit(interlock)
		return {"ok": false, "reason": interlock}
	if not capturable:
		var reason: String = "核心摆幅仍然过大" if absf(omega) > CAPTURE_OMEGA else "配重偏差超出捕获范围"
		lock_failed.emit(reason)
		return {"ok": false, "reason": reason}
	locking = true
	lock_elapsed = 0.0
	lock_started.emit()
	return {"ok": true, "reason": "锁爪闭合中"}


func stabilized_count() -> int:
	var count: int = 0
	for state in stabilizer_states:
		if state:
			count += 1
	return count


## Both legs are a real interlock: the claw hydraulics are fed through them.
func lock_interlock_reason() -> String:
	var count: int = stabilized_count()
	if count >= stabilizer_states.size():
		return ""
	return "稳定支腿未全部锁定（%d/%d）· 锁爪液压压力不足" % [count, stabilizer_states.size()]


# ---------------------------------------------------------------------------
# Stabiliser load path (MECHANICS-005A)
# ---------------------------------------------------------------------------

## Registers that a pad is touching the outer ring (host authority only).
func set_stabilizer_contact(index: int, touching: bool) -> void:
	if index < 0:
		return
	while stabilizer_contact.size() <= index:
		stabilizer_contact.append(false)
	stabilizer_contact[index] = touching


## Registers the pad's normal force in newtons (N = p_cylinder * A_piston).
func set_stabilizer_clamp(index: int, newtons: float) -> void:
	if index < 0:
		return
	while stabilizer_clamp.size() <= index:
		stabilizer_clamp.append(0.0)
	stabilizer_clamp[index] = maxf(0.0, newtons)


func stabilizer_contact_count() -> int:
	var count: int = 0
	for state in stabilizer_contact:
		if state:
			count += 1
	return count


## The ring's reaction on one pad, in newtons.
##
## Static part: the imbalance moment divided by the pad's moment arm.
## Dynamic part: the pad damper has to follow the swinging ring, so the axial
## force rises with the ring's rim speed (c * |omega| * r).
##
## Two pads on opposite sides clamp the ring as a couple, so each carries half.
## MECHANICS-005A-R2: GEOMETRY QUERY, not a load estimate.
##
## Where is the ring's outer surface along the pad's approach ray? The leg uses
## this to decide for itself whether it is touching. The R0 "imbalance moment /
## r_pad" number was an estimate of the moment to be resisted; it must never be
## reported as a force the pad already carries while the pad is still in the air.
##
## gap    : signed distance along the ram axis to the ring surface, m
##          (+ = air, - = penetration); 999 when the ray misses the ring
## point  : world contact point on the ring surface
## normal : unit normal there, pointing out of the ring
## inside : pad is radially inside the ring bore (degenerate geometry)
func ring_contact_query(index: int, pad_world: Vector3, axis_world: Vector3) -> Dictionary:
	var out: Dictionary = {
		"gap": 999.0, "point": pad_world,
		"normal": -axis_world.normalized(), "inside": false,
	}
	if index < 0 or outer_ring == null:
		return out
	var inv: Transform3D = outer_ring.global_transform.affine_inverse()
	var p: Vector3 = inv * pad_world
	var n_local: Vector3 = inv.basis * axis_world
	var flat: Vector2 = Vector2(n_local.x, n_local.z)
	if flat.length() < 1.0e-6:
		return out
	flat = flat.normalized()
	var a: Vector2 = Vector2(p.x, p.z)
	var b: float = a.dot(flat)
	var c: float = a.length_squared() - RING_OUTER_RADIUS * RING_OUTER_RADIUS
	var disc: float = b * b - c
	if disc < 0.0:
		out["gap"] = 999.0
		return out
	var t_hit: float = -b - sqrt(disc)
	out["gap"] = t_hit
	out["inside"] = a.length() < RING_INNER_RADIUS
	var hit_local: Vector3 = p + n_local.normalized() * t_hit
	var radial: Vector3 = Vector3(hit_local.x, 0.0, hit_local.z)
	if radial.length() > 1.0e-4:
		radial = radial.normalized()
	out["point"] = outer_ring.global_transform * hit_local
	out["normal"] = (outer_ring.global_transform.basis * radial).normalized()
	return out


## World velocity of the ring surface at `pad_world`, from the swing rotation.
func ring_surface_velocity(index: int, pad_world: Vector3) -> Vector3:
	var r: Vector3 = pad_world - global_transform.origin
	return Vector3(-omega * r.y, omega * r.x, 0.0)


## Moment the swing must be resisted with, N.m (demand estimate, HUD only).
func ring_demand_torque() -> float:
	return absf(TORQUE_PER_NET * net)


## Applies one pad's contact reaction to the core swing (action/reaction).
func apply_pad_reaction(index: int, point: Vector3, push_dir: Vector3, force: float) -> void:
	if index < 0 or force <= 0.0:
		return
	while pad_reaction.size() <= index:
		pad_reaction.append(0.0)
	pad_reaction[index] = force
	if locked:
		return
	var r: Vector3 = point - global_transform.origin
	var f: Vector3 = push_dir.normalized() * force
	var tau_z: float = r.x * f.y - r.y * f.x
	var h: float = get_physics_process_delta_time() / float(CORE_CONTACT_SUBSTEPS)
	for _s in range(CORE_CONTACT_SUBSTEPS):
		omega += (tau_z / CORE_SWING_INERTIA) * h
	# Coulomb friction: at most mu*N at the pad radius - it can stop the swing
	# but can never reverse it.
	var dw: float = (PAD_MU * force * RING_PAD_RADIUS / CORE_SWING_INERTIA) * get_physics_process_delta_time()
	omega = move_toward(omega, 0.0, dw)

func stabilizer_friction_torque() -> float:
	var total: float = 0.0
	for i in range(stabilizer_states.size()):
		if not stabilizer_states[i]:
			continue
		if i >= stabilizer_clamp.size():
			continue
		total += PAD_MU * float(stabilizer_clamp[i]) * RING_PAD_RADIUS
	return total


func capture_clamp_force() -> float:
	var total: float = 0.0
	for i in range(stabilizer_states.size()):
		if not stabilizer_states[i]:
			continue
		if i >= stabilizer_clamp.size():
			continue
		total += float(stabilizer_clamp[i])
	return total


func capture_net_limit() -> float:
	# The claw is fed through the leg hydraulics: the window widens with the
	# clamp force the legs really hold, not with a count of booleans.
	# Two legs at the 160 bar relief give exactly the accepted 0.25.
	var fraction: float = clampf(capture_clamp_force() / CLAMP_FULL, 0.0, 1.0)
	return CAPTURE_NET + CLAMP_WINDOW_GAIN * fraction


func set_stabilizer_latched(index: int, latched: bool) -> void:
	if index < 0:
		return
	while stabilizer_states.size() <= index:
		stabilizer_states.append(false)
	stabilizer_states[index] = latched
	if not latched:
		set_stabilizer_clamp(index, 0.0)


func refresh_stabilizers() -> void:
	# Called by the legs when a pawl drops; keeps capturable in sync immediately.
	capturable = (not locked) and absf(net) <= capture_net_limit() and absf(omega) <= CAPTURE_OMEGA


func set_brake_state(applied: float) -> void:
	brake_applied = clampf(applied, 0.0, 1.0)


func play_surge(strength: float = 1.0) -> void:
	surge_timer = 3.2
	surge_strength = clampf(strength, 0.3, 1.6)
	surge_shock.emit(surge_strength)


func set_data_mode(enabled: bool) -> void:
	data_mode = enabled


func force_locked_state() -> void:
	locking = false
	locked = true
	angle = 0.0
	omega = 0.0
	capturable = false
	lock_elapsed = LOCK_DURATION
	swing.rotation = Vector3.ZERO
	outer_yaw = 0.0
	middle_tilt = 0.0
	inner_spin = 0.0
	_apply_ring_pose()
	crystal_pivot.rotation = Vector3.ZERO


func reset_state() -> void:
	locked = false
	locking = false
	lock_elapsed = 0.0
	angle = 0.0
	omega = 0.0
	net = NET_GAIN * (right_p - left_p) + NET_BIAS
	surge_timer = 0.0
	surge_strength = 0.0
	data_mode = false
	brake_applied = 0.0
	stabilizer_states = [false, false]
	stabilizer_contact = [false, false]
	stabilizer_clamp = [0.0, 0.0]
	swing.rotation = Vector3.ZERO
	outer_yaw = 0.0
	middle_tilt = 0.0
	inner_spin = 0.0
	_apply_ring_pose()
	crystal_pivot.rotation = Vector3.ZERO


func network_snapshot() -> Dictionary:
	return {
		"net": net,
		"angle": angle,
		"omega": omega,
		"locked": locked,
		"locking": locking,
		"capturable": capturable,
		"left_p": left_p,
		"right_p": right_p,
		"surge_timer": surge_timer,
		"surge_strength": surge_strength,
		"data_mode": data_mode,
	}


func apply_network_snapshot(data: Dictionary) -> void:
	remote = true
	remote_net = float(data.get("net", remote_net))
	remote_angle = float(data.get("angle", remote_angle))
	remote_omega = float(data.get("omega", remote_omega))
	left_p = float(data.get("left_p", left_p))
	right_p = float(data.get("right_p", right_p))
	locked = bool(data.get("locked", locked))
	locking = bool(data.get("locking", locking))
	capturable = bool(data.get("capturable", capturable))
	surge_timer = float(data.get("surge_timer", 0.0))
	surge_strength = float(data.get("surge_strength", 0.0))
	data_mode = bool(data.get("data_mode", data_mode))


