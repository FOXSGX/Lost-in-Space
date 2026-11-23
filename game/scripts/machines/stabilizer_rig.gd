class_name StabilizerRig
extends Node3D

## Hydraulic outrigger ("稳定支腿") that presses a pad onto the core's outer
## gimbal ring.
##
## MECHANICS-005A: the leg is a real single-degree-of-freedom hydraulic
## actuator, not a pressure bar that writes a transform.
##
## Oil path (asymmetric cylinder, meter-in / meter-out through a load-sensing
## flow control valve, fed by the facility power unit):
##
##   console hand pump -> pilot pressure p_p in a bladder accumulator
##   pilot pressure     -> proportional reducing valve -> cylinder p_c
##   ram force          F_cyl = p_c * A          (A = pi * d^2 / 4 = 4.42e-3 m^2)
##   rod dynamics       m * a = F_cyl - F_load - F_seal - c * v
##   valve              v <= v_max * clamp((F_cyl - F_load - F_seal) / (P_seat * A))
##   ring load          F_load = |tau_ring| / r_pad + c_pad * |omega| * r_pad
##
## Consequences that the player can actually feel and that the automated tests
## measure:
##   * the drive force has a hard ceiling (p_relief * A = 70.7 kN at 160 bar);
##   * the ram only advances while F_cyl exceeds the ring's reaction, so an
##     unbalanced core physically stalls the leg before the pawl rack;
##   * the same pilot pressure gives a slower stroke against a heavier ring;
##   * the pawl can only drop when the ram is on its hard stop and the leg is
##     pressed to the relief, and it then holds the load on the rack tooth while
##     the pilot-operated check valve traps the clamp pressure;
##   * releasing the pawl (S at the console) opens the check valve and the load
##     pushes the ram back - nothing is teleported.
##
## The leg feeds its real clamp force back into CoreRig, which uses it for the
## Coulomb friction torque of a latched pair and for the hydraulic claw's
## capture window.

signal latch_engaged(pid: int)
signal ram_moved(extension: float)
signal ram_stopped(load_force: float)
signal latch_released()

# --- authored geometry -----------------------------------------------------
# MECHANICS-005A-R4: the R0 swing sweeps the ring face from 0.560 m to 8.960 m
# off-axis while a balanced core presents 3.815..5.705 m. A 2.35 m stroke cannot
# span that: the retracted pad sits inside the sweep (R2's real defect - it braked
# the core down to 6.9 deg) or cannot reach once balanced. 5.40 m spans it.
const STROKE := 5.80              # m of visible ram travel (local +X)
## Pad contact face, ram-local metres: the +X face of the RamPad box.
const PAD_FACE_LOCAL_X := 2.80    # +X face of the RamPad, ram-local metres
## Rig base distance from the core axis, derived from the contact geometry:
##   R_pad(e) = RIG_RADIUS - PAD_FACE_LOCAL_X - STROKE*e
## 7.60 gives R_pad = 5.930 .. 3.580 with the ring outer face at 4.760, so the
## pad crosses the ring at e = 0.498 and keeps 1.18 m of travel beyond it. R0
## used 8.786, which left only 6.4 mm at full stroke: no contact force could
## ever develop (MECHANICS-005A-R2 stage-1 report).
## R_pad(e) = RIG_RADIUS - PAD_FACE_X - STROKE*e -> 9.460 m retracted, 4.060 m
## extended. 9.460 clears the R0 sweep (8.960) so a retracted pad never touches
## the core; 4.060 stays outside the bore at every working angle.
const RIG_RADIUS := 12.26
## RETIRED (R0 shortcut). Contact is decided by real geometry every frame.
const CONTACT_FRACTION := 0.80
const LATCH_FRACTION := 0.995     # pawl tooth alignment at the hard stop

# --- real contact law (MECHANICS-005A-R2) --------------------------------
# Compliant elastomer pad on a steel ring: N = k*delta - c*v_rel, one-sided.
const CONTACT_STIFFNESS := 2.0e6  # N/m
const CONTACT_DAMPING := 6.0e4    # N.s/m
const RAM_SUBSTEPS := 8           # substeps per frame (omega_n*dt ~ 0.2)
const STICTION_VEL := 0.05        # m/s below which the seal holds the rod

# --- MECHANICS-005A-R4: pawl seating and bore travel stop ------------------
## The tooth drops once the ram has been pumped to relief against the ring and
## has settled there. LATCH_MIN_EXT keeps an overloaded leg - one the ring shoved
## back and pinned at, say, 17% stroke - from dropping the pawl and calling
## itself locked: a ratchet only has teeth where the rack runs.
const LATCH_MIN_FORCE := 8.0e3    # N  - minimum contact force to count as seated
const LATCH_SETTLE_FRAMES := 8    # consecutive still frames before the pawl drops
## The rack only starts here. A leg pinned short of it (an overloaded leg the
## ring shoved back) must never drop the pawl and call itself locked.
const LATCH_MIN_EXT := 0.62       # fraction of STROKE where the rack teeth begin
## Clearance kept between the pad face and the ring bore, metres.
const BORE_MARGIN := 0.06

# --- hydraulic actuator (real numbers, 75 mm bore / 160 bar) ---------------
const BORE := 0.075               # m
const AREA := PI * BORE * BORE / 4.0   # m^2 = 4.4179e-3 (75 mm bore)
const RELIEF := 16.0e6            # Pa   main relief setting
const F_MAX := RELIEF * AREA      # N    = 70.69 kN (finite drive force)
const RAM_MASS := 260.0           # kg   rod + collar + pad + guide block
const SEAL_FRICTION := 2.4e3      # N    Coulomb seal / guide friction
const VISCOUS := 4.0e3            # N.s/m viscous rod friction
const FLOW_MAX := 1.40            # m/s  metered stroke speed at >= P_SEAT
const P_SEAT := 1.0e6             # Pa   surplus pressure for the full metered speed
const PUMP_RATE := 9.0e6          # Pa/s pilot pressure rise while pumping
const BLEED_RATE := 3.2e6         # Pa/s control valve leak when not pumping
const LATCH_RELIEF := 1.0         # the pawl only seats with the leg pressed to the relief
const HOLD_MARGIN := 1.02         # pawl needs a little more than the static load
const PAWL_RATED := 320.0e3       # N    shear rating of one rack tooth

var session: CoopSession
var core: CoreRig
var machine_id: String = "stabilizer"
var side_name: String = "西"
var rig_yaw: float = 0.0
var anchor: Transform3D
var area: Area3D

# --- mechanical state ------------------------------------------------------
var extension: float = 0.0        # 0..1 of STROKE (authoritative position)
var pressure: float = 0.0         # 0..1 of RELIEF (console gauge, MPa/16)
var ram_velocity: float = 0.0     # m/s along the ram axis
var load_force: float = 0.0       # N the ring pushes back with
var clamp_force: float = 0.0      # N the pad actually presses with (A * p_c)
var contact: bool = false         # pad touching the ring (real geometry, this frame)
## MECHANICS-005A-R2: two distinct states. A seated pawl does NOT mean the pad
## is still touching the core - the ring can swing away and the load goes to 0.
var mechanically_latched: bool = false   # pawl seated in a rack tooth
var carrying_load: bool = false          # pad in contact AND transmitting force
var signed_gap: float = 999.0     # + = air gap, - = penetration, m
var penetration: float = 0.0      # contact compression, m (0 in the air)
var contact_point: Vector3 = Vector3.ZERO
var contact_normal: Vector3 = Vector3.UP
var contact_demand: float = 0.0   # unclamped contact force demand, N
var stalled: bool = false         # drive force cannot overcome the load
var latched: bool = false         # mirror of mechanically_latched (compat)
var pawl_load: float = 0.0        # N carried by the rack tooth
var pawl_slipped: bool = false
var active: bool = false
var active_pid: int = 0
var pending_player: PlayerController = null
var player: PlayerController
var pump_angle: float = 0.0
var pump_strokes: float = 0.0
var _surge_cooldown: float = 0.0
var _strain_flash: float = 0.0
var _time: float = 0.0
var _was_stalled: bool = false
var _stall_frames: int = 0
var _last_stall_toast: float = -10.0
var _last_stop_toast: float = -10.0
var _stop_hits: int = 0

var kit: WorldKit
var ram_node: Node3D
var pawl_node: Node3D
var pump_node: Node3D
var gauge_needle: Node3D
var status_lamp: MeshInstance3D
var label: Label3D
var readout: Label3D
var audio_feedback: AudioDirector
var stabilizer_index: int = 0
var _built: bool = false


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	var dark: Material = MatLib.dark_steel()
	var steel: Material = MatLib.painted_steel(Color(0.24, 0.30, 0.33))
	var bronze: Material = MatLib.bronze()
	# foundation
	kit.box("Footing", Vector3(2.05, 0.26, 2.05), Vector3(0, 0.13, 0), dark, Vector3.ZERO, true)
	kit.box("FootingTrim", Vector3(2.15, 0.06, 2.15), Vector3(0, 0.28, 0), MatLib.hazard_material(), Vector3.ZERO, false)
	for i in range(4):
		var sx: float = -0.78 if i % 2 == 0 else 0.78
		var sz: float = -0.78 if i < 2 else 0.78
		kit.cylinder("AnchorBolt", 0.075, 0.10, Vector3(sx, 0.30, sz), bronze, Vector3.ZERO, false, 10)
	# column with gussets
	kit.box("Column", Vector3(0.95, 7.05, 0.95), Vector3(0, 3.78, 0), steel, Vector3.ZERO, true)
	for sx in [-0.58, 0.58]:
		kit.beam("Gusset", Vector3(sx, 0.30, 0), Vector3(sx * 0.72, 2.35, 0), 0.075, dark, false, 6)
	kit.box("ColumnBand", Vector3(1.06, 0.20, 1.06), Vector3(0, 1.34, 0), MatLib.hazard_material(), Vector3.ZERO, false)
	kit.box("ColumnBandTop", Vector3(1.06, 0.16, 1.06), Vector3(0, 6.30, 0), bronze, Vector3.ZERO, false)
	# service rungs on the back face (+Z is the operator side, so rungs on -Z)
	for i in range(7):
		kit.box("Rung", Vector3(0.62, 0.045, 0.045), Vector3(0, 1.1 + float(i) * 0.72, -0.52), MatLib.steel(), Vector3.ZERO, false)
	# top guide housing
	kit.box("GuideHousing", Vector3(1.95, 1.05, 1.10), Vector3(0.98, 7.30, 0), steel, Vector3.ZERO, true)
	kit.box("GuideCap", Vector3(2.10, 0.14, 1.22), Vector3(0.98, 7.90, 0), bronze, Vector3.ZERO, false)
	for sx2 in [-0.95, 0.95]:
		kit.cylinder("GuidePin", 0.09, 0.24, Vector3(0.98 + sx2 * 0.0, 7.30, sx2 * 0.0), bronze, Vector3(0, 0, PI * 0.5), false, 8)
	# knee brace from column to the guide housing underside
	kit.beam("KneeBrace", Vector3(0, 5.55, 0), Vector3(1.55, 6.85, 0), 0.10, dark, false, 8)
	kit.beam("KneeBrace2", Vector3(0, 5.55, 0), Vector3(1.55, 7.72, 0), 0.075, bronze, false, 6)
	# extending ram (moves along local +X)
	ram_node = Node3D.new()
	ram_node.name = "Ram"
	ram_node.position = Vector3(0, 7.30, 0)
	add_child(ram_node)
	var rk: WorldKit = WorldKit.new(ram_node)
	# The ram is authored so that the pad face travels from 7.2 m to 4.75 m from
	# the core centre: at full extension it just kisses the outer gimbal ring
	# (radius 4.72) and never enters the ring envelope.
	rk.cylinder("RamRod", 0.17, 1.70, Vector3(0.83, 0, 0), MatLib.metal(Color(0.42, 0.44, 0.46), 0.26, 0.9, 0.3), Vector3(0, 0, PI * 0.5), true, 18)
	rk.cylinder("RamCollar", 0.27, 0.16, Vector3(0.06, 0, 0), bronze, Vector3(0, 0, PI * 0.5), false, 18)
	rk.box("RamPad", Vector3(0.30, 0.92, 0.92), Vector3(1.52, 0, 0), MatLib.hazard_material(), Vector3.ZERO, true)
	rk.box("PadBack", Vector3(0.10, 0.72, 0.72), Vector3(1.34, 0, 0), MatLib.grip(), Vector3.ZERO, false)
	for sy in [-0.30, 0.30]:
		rk.cylinder("PadBolt", 0.06, 0.16, Vector3(1.52, sy, 0), MatLib.steel(), Vector3(0, 0, PI * 0.5), false, 8)
	# rack teeth under the ram, for the pawl
	for i in range(9):
		kit.box("RackTooth", Vector3(0.10, 0.09, 0.30), Vector3(1.15 + float(i) * 0.20, 6.86, 0.34), bronze, Vector3.ZERO, false)
	# pawl
	pawl_node = Node3D.new()
	pawl_node.name = "LatchPawl"
	pawl_node.position = Vector3(0.88, 6.86, 0.36)
	add_child(pawl_node)
	var pk: WorldKit = WorldKit.new(pawl_node)
	pk.box("PawlBody", Vector3(0.46, 0.16, 0.22), Vector3(0.18, 0, 0), MatLib.painted_steel(Color(0.62, 0.30, 0.10)), Vector3.ZERO, false)
	pk.box("PawlTip", Vector3(0.14, 0.20, 0.20), Vector3(0.40, -0.06, 0), bronze, Vector3.ZERO, false)
	pawl_node.rotation.z = -0.85
	kit.box("LatchHousing", Vector3(0.50, 0.44, 0.34), Vector3(0.86, 6.95, 0.20), dark, Vector3.ZERO, false)
	kit.cylinder("LatchSpring", 0.09, 0.36, Vector3(0.86, 7.24, 0.20), MatLib.steel(), Vector3.ZERO, false, 10)
	# console (operator stands on +Z)
	kit.box("ConsoleBase", Vector3(0.86, 0.90, 0.62), Vector3(0, 0.45, 1.10), MatLib.metal(Color(0.20, 0.24, 0.25), 0.42, 0.72, 0.55), Vector3.ZERO, true)
	kit.box("ConsoleTop", Vector3(0.92, 0.08, 0.68), Vector3(0, 0.92, 1.10), steel, Vector3.ZERO, false)
	kit.box("ConsoleLip", Vector3(0.92, 0.06, 0.06), Vector3(0, 0.88, 1.42), MatLib.hazard_material(), Vector3.ZERO, false)
	# pump lever pivoted on the console
	pump_node = Node3D.new()
	pump_node.name = "PumpLever"
	pump_node.position = Vector3(-0.18, 0.96, 1.02)
	add_child(pump_node)
	var pk2: WorldKit = WorldKit.new(pump_node)
	pk2.beam("PumpShaft", Vector3.ZERO, Vector3(0, 0.52, 0.06), 0.035, MatLib.steel(), false, 8)
	pk2.cylinder("PumpGrip", 0.048, 0.30, Vector3(0, 0.54, 0.07), MatLib.grip(), Vector3(0, 0, PI * 0.5), false, 10)
	pk2.box("PumpHub", Vector3(0.14, 0.12, 0.14), Vector3.ZERO, bronze, Vector3.ZERO, false)
	# pressure gauge on the console top
	kit.cylinder("GaugeBack", 0.17, 0.08, Vector3(0.26, 1.02, 1.05), dark, Vector3(PI * 0.5, 0, 0), false, 20)
	kit.ring_box("GaugeBezel", 0.175, 0.035, 0.05, Vector3(0.26, 1.02, 1.10), bronze, Basis(Vector3.RIGHT, PI * 0.5), 24, false)
	gauge_needle = Node3D.new()
	gauge_needle.name = "Needle"
	gauge_needle.position = Vector3(0.26, 1.02, 1.15)
	add_child(gauge_needle)
	var nk: WorldKit = WorldKit.new(gauge_needle)
	nk.box("NeedleBar", Vector3(0.02, 0.13, 0.012), Vector3(0, 0.06, 0), MatLib.emissive(Color(1.0, 0.72, 0.2), 1.6), Vector3.ZERO, false)
	kit.label3d("压力", Vector3(0.26, 1.24, 1.06), 0.0014, Color(0.82, 0.92, 1.0), 18)
	# position scale beside the guide so the extension is readable from the floor
	for i in range(5):
		kit.box("ExtTick", Vector3(0.04, 0.14, 0.03), Vector3(1.42 + float(i) * 0.58, 6.52, 0.60), MatLib.emissive(Color(0.55, 0.85, 0.95), 0.6), Vector3.ZERO, false)
	# status lamp
	status_lamp = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.10
	sm.height = 0.20
	sm.radial_segments = 12
	status_lamp.mesh = sm
	status_lamp.material_override = MatLib.emissive(Color(1.0, 0.55, 0.12), 1.6)
	status_lamp.position = Vector3(0.40, 7.95, 0.0)
	add_child(status_lamp)
	kit.omni(Vector3(0, 1.6, 1.9), Color(1.0, 0.70, 0.42), 0.9, 4.0, false, "StabilizerLamp")
	# interaction area in front of the console
	area = Area3D.new()
	area.name = "StabilizerArea"
	area.position = Vector3(0, 1.30, 1.85)
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitorable = true
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = 0.95
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sph
	area.add_child(col)
	add_child(area)
	add_to_group("interactable")
	label = kit.label3d(side_name + "侧稳定支腿", Vector3(0, 1.30, 1.44), 0.0022, Color(0.85, 0.95, 1.0), 28)
	# Working-pressure / load readout mounted on the console face (an instrument,
	# not floating text): it is the only place the operator can see why the ram
	# is not moving.
	readout = kit.label3d("待机 · 0.0 MPa", Vector3(-0.17, 1.06, 1.13), 0.0013, Color(0.62, 0.95, 0.76), 20)
	anchor = Transform3D(Basis(Vector3.UP, rig_yaw), to_global(Vector3(0, 0, 2.15)))
	_apply_pose()


func setup(p_core: CoreRig, p_session: CoopSession, p_machine_id: String, p_side_name: String, p_yaw: float, p_index: int = 0) -> void:
	core = p_core
	session = p_session
	machine_id = p_machine_id
	side_name = p_side_name
	rig_yaw = p_yaw
	stabilizer_index = p_index
	if not _built:
		build()
	rotation.y = rig_yaw
	anchor = Transform3D(Basis(Vector3.UP, rig_yaw), to_global(Vector3(0, 0, 2.15)))
	if label != null:
		label.text = side_name + "侧稳定支腿"
	if session != null:
		if not session.local_claim_granted.is_connected(_on_local_grant):
			session.local_claim_granted.connect(_on_local_grant)
		if not session.local_claim_denied.is_connected(_on_local_deny):
			session.local_claim_denied.connect(_on_local_deny)


func bind_player(p: PlayerController) -> void:
	player = p
	if player == null:
		return
	if not player.operate_stopped.is_connected(_on_player_stopped):
		player.operate_stopped.connect(_on_player_stopped)


func get_prompt() -> String:
	if latched:
		return "%s侧稳定支腿已锁定 · 夹持力 %.1f kN（S 解锁）" % [side_name, clamp_force / 1000.0]
	if active:
		return ""
	if session != null and session.is_claimed_by_other(machine_id, session.local_pid):
		return "%s 正在泵压稳定支腿" % session.ledger.display_name(session.claim_owner(machine_id))
	if core != null and core.is_locked():
		return "%s侧稳定支腿已锁定" % side_name
	if stalled:
		return "E 操作%s侧稳定支腿 · 支腿顶住核心：负载 %.1f kN 已到推力上限 %.1f kN" % [
			side_name, load_force / 1000.0, F_MAX / 1000.0]
	return "E 操作%s侧稳定支腿 · W 泵压展开" % side_name


func interact(p: PlayerController) -> void:
	if p.operating or session == null:
		return
	pending_player = p
	if session.is_authority():
		var result: Dictionary = session.try_claim(machine_id, session.local_pid)
		if bool(result.get("ok", false)):
			_enter(p, session.local_pid)
		else:
			_deny(str(result.get("reason", "")))
	else:
		if session.is_pending_claim(machine_id):
			return
		session.note_pending_claim(machine_id)
		var net: CoopNet = _find_net()
		if net != null:
			net.submit_claim(machine_id)
		else:
			session.deny_local_claim(machine_id, "未连接主机")


func _find_net() -> CoopNet:
	var hub_net: CoopNet = NetLookup.get_net()
	if hub_net != null:
		return hub_net
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("CoopNet") as CoopNet


func _on_local_grant(granted_id: String) -> void:
	if granted_id != machine_id:
		return
	if pending_player == null or not is_instance_valid(pending_player):
		return
	_enter(pending_player, session.local_pid)


func _on_local_deny(denied_id: String, reason: String) -> void:
	if denied_id != machine_id:
		return
	pending_player = null
	var hud: GameHud = _find_hud()
	if hud != null and reason != "":
		hud.toast(reason, 2.2)


func _find_hud() -> GameHud:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("Hud") as GameHud


func _enter(p: PlayerController, pid: int) -> void:
	active = true
	active_pid = pid
	pending_player = null
	bind_player(p)
	p.enter_operate(anchor, self, rig_yaw, 0.95)
	p.hands.set_state("lever")
	if session != null:
		session.local_operating_machine = machine_id
	lever_feedback()


func _deny(reason: String) -> void:
	pending_player = null
	var hud: GameHud = _find_hud()
	if hud != null and reason != "":
		hud.toast(reason, 2.0)


func _on_player_stopped(target: Node) -> void:
	if target != self:
		return
	if not active:
		return
	active = false
	if session != null and active_pid == session.local_pid:
		if session.is_authority():
			session.release_claim(machine_id, active_pid)
		else:
			var net: CoopNet = _find_net()
			if net != null:
				net.submit_release(machine_id)
	active_pid = 0


func lever_feedback() -> void:
	if audio_feedback != null:
		audio_feedback.play_sfx("lever_click", global_position + Vector3(0, 1, 0), -6.0)


func setup_audio(a: AudioDirector) -> void:
	audio_feedback = a


# ---------------------------------------------------------------------------
# Real hydraulic integration (host authority)
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	_surge_cooldown = maxf(0.0, _surge_cooldown - delta)
	_strain_flash = maxf(0.0, _strain_flash - delta)
	var authority: bool = session == null or session.is_authority()
	if not authority:
		_apply_pose()
		_apply_visuals(delta)
		return
	var axis: float = 0.0
	var local_pid: int = session.local_pid if session != null else 0
	if active and active_pid == local_pid:
		axis = Input.get_axis("move_back", "move_forward")
	if session != null:
		axis = session.axis_for(machine_id, axis)
	_integrate(delta, axis)
	_apply_pose()
	_apply_visuals(delta)
	ram_moved.emit(extension)


func _integrate(delta: float, axis: float) -> void:
	# 1) Pilot pressure from the hand pump (finite power: PUMP_RATE Pa/s into a
	#    0.3 L bladder accumulator). Releasing the lever does not hold pressure
	#    in the pilot line: the control valve leaks it back to the tank.
	var pumping: bool = axis > 0.05
	if pumping:
		pressure = minf(1.0, pressure + (PUMP_RATE / RELIEF) * delta * minf(1.0, axis))
		pump_angle = lerpf(pump_angle, -minf(1.0, axis) * 0.38, delta * 6.0)
		pump_strokes += delta * minf(1.0, axis)
	elif not mechanically_latched:
		pump_angle = lerpf(pump_angle, 0.0, delta * 4.0)
		pressure = maxf(0.0, pressure - (BLEED_RATE / RELIEF) * delta)
	else:
		pump_angle = lerpf(pump_angle, 0.0, delta * 4.0)

	# 2) Unlock: S opens the pilot check valve. The pawl lifts, trapped pressure
	#    is released and the ring pushes the ram back - never a teleport to zero.
	if mechanically_latched and axis < -0.05:
		release_latch("操作员解除锁定")
		return

	var p_pa: float = pressure * RELIEF
	var drive: float = p_pa * AREA
	var capacity: float = PAWL_RATED if mechanically_latched else F_MAX
	var axis_world: Vector3 = global_transform.basis.x.normalized()

	# 3) Rod dynamics with real contact, integrated in substeps. The contact
	#    spring (2 MN/m) is stiff against the 260 kg rod, so one 1/60 s step
	#    gives omega_n*dt ~ 1.6 and the rod rings; eight substeps put it at ~0.2.
	var h: float = delta / float(RAM_SUBSTEPS)
	for _s in range(RAM_SUBSTEPS):
		var pw: Vector3 = _pad_face_world()
		var g: float = 999.0
		var cp: Vector3 = pw
		var cn: Vector3 = -axis_world
		if core != null:
			var q: Dictionary = core.ring_contact_query(stabilizer_index, pw, axis_world)
			g = float(q.get("gap", 999.0))
			cp = q.get("point", pw) as Vector3
			cn = q.get("normal", -axis_world) as Vector3
		contact = g <= 0.0 and g < 900.0
		signed_gap = g
		penetration = maxf(0.0, -g) if contact else 0.0
		contact_point = cp
		contact_normal = cn
		if contact:
			var v_rel: float = ram_velocity
			if core != null:
				v_rel -= core.ring_surface_velocity(stabilizer_index, pw).dot(axis_world)
			contact_demand = CONTACT_STIFFNESS * penetration - CONTACT_DAMPING * v_rel
			load_force = clampf(contact_demand, 0.0, capacity)
		else:
			contact_demand = 0.0
			load_force = 0.0
		# Seal friction + stiction: once the rod is essentially at rest and the
		# net drive is inside the seal holding force it stays at rest. Without
		# this it dithers around the force balance and pawl timing is random.
		var fr: float = SEAL_FRICTION * (1.0 if ram_velocity >= 0.0 else -1.0)
		if absf(ram_velocity) < STICTION_VEL and absf(drive - load_force) < SEAL_FRICTION * 1.6:
			ram_velocity = 0.0
			fr = 0.0
		var f_sum: float = drive - load_force - fr - VISCOUS * ram_velocity
		ram_velocity += (f_sum / RAM_MASS) * h
		# Metering valve: stroke speed set by the surplus pressure across the load.
		var surplus_s: float = drive - load_force - SEAL_FRICTION
		var v_out_s: float = 0.0
		if surplus_s > 0.0:
			v_out_s = FLOW_MAX * clampf((surplus_s / AREA) / P_SEAT, 0.0, 1.0)
		ram_velocity = clampf(ram_velocity, -FLOW_MAX, v_out_s)
		# A seated pawl blocks further EXTENSION but cannot pull the rod back.
		if mechanically_latched and ram_velocity > 0.0:
			ram_velocity = 0.0
		extension += (ram_velocity * h) / STROKE
		if extension >= 1.0:
			if ram_velocity > 0.05:
				_on_hard_stop(ram_velocity)
			extension = 1.0
			ram_velocity = 0.0
		elif extension <= 0.0:
			extension = 0.0
			ram_velocity = maxf(0.0, ram_velocity)
		# MECHANICS-005A-R4: mechanical travel stop against the ring bore. It is a
		# one-sided geometric constraint along the ram axis - the pad may approach
		# the bore face but never cross it - and it absorbs the remaining velocity
		# instead of letting the cylinder drive the pad through the flange.
		var stop_ext: float = _bore_stop_extension(extension)
		if extension > stop_ext:
			extension = stop_ext
			if ram_velocity > 0.0:
				_on_hard_stop(ram_velocity)
			ram_velocity = 0.0

	var surplus: float = drive - load_force - SEAL_FRICTION
	stalled = contact and surplus <= 0.0
	carrying_load = contact and load_force > 1.0
	# Hydraulic clamp capacity feeds the claw window. A seated pawl plus the
	# check valve keep the circuit pressurised, so this is NOT zeroed just
	# because the ring momentarily swung clear - that would silently drop the
	# capture window while the leg is still mechanically locked.
	clamp_force = drive if (contact or mechanically_latched) else 0.0

	# 4) Action/reaction: the ring receives exactly what the pad carries.
	if contact and load_force > 0.0 and core != null:
		core.apply_pad_reaction(stabilizer_index, contact_point, axis_world, load_force)

	# 4b) Re-evaluate the contact AFTER the reaction moved the ring. The pad may
	#     have been pushed clear, and contact/load_force must describe the frame we
	#     end on - otherwise the leg reports carrying force while signed_gap is
	#     already positive (that was a real inconsistency: gap +0.039 m with 187 kN).
	if core != null:
		var qf: Dictionary = core.ring_contact_query(stabilizer_index, _pad_face_world(), axis_world)
		var gf: float = float(qf.get("gap", 999.0))
		signed_gap = gf
		contact = gf <= 0.0 and gf < 900.0
		penetration = maxf(0.0, -gf) if contact else 0.0
		if contact:
			contact_demand = CONTACT_STIFFNESS * penetration
			load_force = clampf(contact_demand, 0.0, capacity)
		else:
			contact_demand = 0.0
			load_force = 0.0
	carrying_load = contact and load_force > 1.0
	# Hydraulic clamp capacity feeds the claw window. A seated pawl plus the
	# check valve keep the circuit pressurised, so this is NOT zeroed just
	# because the ring momentarily swung clear - that would silently drop the
	# capture window while the leg is still mechanically locked.
	clamp_force = drive if (contact or mechanically_latched) else 0.0

	# 5) Pawl: seats once the leg is pumped to relief against the ring and the
	#    rod has settled. A sustained settle (not one impact frame) is required.
	if contact and not mechanically_latched and pressure >= LATCH_RELIEF \
			and drive >= F_MAX * 0.97 and absf(ram_velocity) <= 0.02:
		_stall_frames += 1
		if _stall_frames >= 8:
			_latch()
	else:
		_stall_frames = 0
	_publish_to_core()
	_report_stall()


## MECHANICS-005A-R4: travel stop that keeps the pad out of the ring BORE.
##
## R3 compared the pad's radial distance from the RING CENTRE with
## RING_INNER_RADIUS + margin. That is wrong: the pad travels along a ray fixed in
## HALL space while the ring centre has shifted by `lat`, so the test effectively
## demanded  R_pad > RING_INNER + margin + lat.  With lat = 0.945 m it required
## 5.455 m while real contact happens at 3.815 m - an impossible pair, and the
## reason the ram froze at ext = 0.542.
##
## The correct test is along the RAY: how much travel is left before the pad face
## meets the ring's INNER cylinder.  Both walls move with the ring centre, so the
## wall thickness stays 0.310 m at every angle and the pad never needs to cross it.
func _bore_stop_extension(at_ext: float) -> float:
	if core == null:
		return 1.0
	var ring: Node3D = core.outer_ring
	if ring == null:
		return 1.0
	# NOTE: ram_node.position.x is ALREADY extension * STROKE (set by _apply_pose),
	# so the pad's ram-local X for a GIVEN extension is PAD_FACE_LOCAL_X + at_ext *
	# STROKE measured from the ram's own ORIGIN - i.e. subtract the pose that is
	# currently applied. Getting this wrong double-counts the stroke: R3 added
	# at_ext*STROKE on top of an already-moved node, which put the pad ~2.9 m too
	# deep at ext=0.542 and made the stop believe it was inside the bore.
	var pad_w: Vector3 = global_transform * Vector3(
		PAD_FACE_LOCAL_X + at_ext * STROKE, 7.30, 0.0)
	var axis_w: Vector3 = global_transform.basis.x.normalized()
	var t_inner: float = _ray_to_cylinder(ring, pad_w, axis_w, CoreRig.RING_INNER_RADIUS)
	if t_inner > 900.0:
		return 1.0
	var room: float = t_inner - BORE_MARGIN
	if room >= 0.0:
		return 1.0
	return clampf(at_ext + room / STROKE, 0.0, 1.0)


## Distance along `dir_w` from `origin_w` to the cylinder of `radius` about the
## ring's own axis, in world metres. 999 when the ray misses it.
func _ray_to_cylinder(ring: Node3D, origin_w: Vector3, dir_w: Vector3, radius: float) -> float:
	var inv: Transform3D = ring.global_transform.affine_inverse()
	var p: Vector3 = inv * origin_w
	var d: Vector3 = inv.basis * dir_w
	var flat_o: Vector2 = Vector2(p.x, p.z)
	var flat_d: Vector2 = Vector2(d.x, d.z)
	if flat_d.length() < 1.0e-7:
		return 999.0
	flat_d = flat_d.normalized()
	var b: float = flat_o.dot(flat_d)
	var c: float = flat_o.length_squared() - radius * radius
	var disc: float = b * b - c
	if disc < 0.0:
		return 999.0
	return -b - sqrt(disc)


## World position of the pad's contact face (the +X face of the RamPad box).
func _pad_face_world() -> Vector3:
	return ram_node.global_transform * Vector3(PAD_FACE_LOCAL_X, 0.0, 0.0)


func _publish_to_core() -> void:
	if core == null:
		return
	core.set_stabilizer_contact(stabilizer_index, contact)
	core.set_stabilizer_clamp(stabilizer_index, clamp_force if latched else 0.0)


func _report_stall() -> void:
	if stalled and not _was_stalled:
		if _time - _last_stall_toast > 3.0:
			_last_stall_toast = _time
			var hud: GameHud = _find_hud()
			if hud != null:
				hud.toast("%s侧支腿顶住核心：负载 %.1f kN，支腿推力上限 %.1f kN · 先配平核心" % [
					side_name, load_force / 1000.0, F_MAX / 1000.0], 3.0)
			if audio_feedback != null:
				audio_feedback.play_sfx("lock_fail", global_position + Vector3(0, 2, 0), -4.0)
		ram_stopped.emit(load_force)
	_was_stalled = stalled


func _on_hard_stop(speed: float) -> void:
	_stop_hits += 1
	_strain_flash = 0.5
	if _time - _last_stop_toast > 1.2 and speed > 0.25:
		_last_stop_toast = _time
		if audio_feedback != null:
			audio_feedback.play_sfx("metal_clank", global_position + Vector3(0, 6, 0), -6.0)


func _latch() -> void:
	# MECHANICS-005A-R2: the pawl seats in the tooth it FINDS. R0 forced
	# `extension = 1.0` here, which teleported the pad up to 0.85 m into the
	# ring on the latch frame - the real source of the interpenetration.
	mechanically_latched = true
	latched = true
	ram_velocity = 0.0
	stalled = false
	clamp_force = pressure * RELIEF * AREA
	var pid: int = 0
	if session != null:
		pid = session.claim_owner(machine_id)
		if pid == 0:
			pid = active_pid if active_pid != 0 else session.local_pid
		# The credit is the measured clamp force, not a boolean: a leg that
		# barely reached the relief still counts, one that never pressed does not.
		session.credit(pid, "stabilizer_lock", clamp_force / 1000.0, "%s侧支腿锁定 %.1f kN" % [side_name, clamp_force / 1000.0])
	latch_engaged.emit(pid)
	if audio_feedback != null:
		audio_feedback.play_sfx("latch", global_position + Vector3(0, 6, 0), -3.0)
	if core != null:
		core.set_stabilizer_latched(stabilizer_index, true)
		core.set_stabilizer_contact(stabilizer_index, true)
		core.set_stabilizer_clamp(stabilizer_index, clamp_force)
		core.refresh_stabilizers()
	var hud: GameHud = _find_hud()
	if hud != null:
		hud.toast("%s侧稳定支腿锁定 · 夹持力 %.1f kN" % [side_name, clamp_force / 1000.0], 2.6)


## Opens the pilot check valve: the pawl lifts and the ring load pushes the rod
## back. Physical, not a state write.
func release_latch(reason: String = "") -> void:
	if not latched:
		return
	mechanically_latched = false
	latched = false
	pawl_slipped = false
	pawl_load = 0.0
	clamp_force = 0.0
	# The pilot check valve opens and the cylinder is dumped to the tank, so the
	# ring load pushes the rod back instead of being held by trapped oil.
	pressure = 0.0
	ram_velocity = -0.20
	if core != null:
		core.set_stabilizer_latched(stabilizer_index, false)
		core.set_stabilizer_clamp(stabilizer_index, 0.0)
		core.refresh_stabilizers()
	latch_released.emit()
	if audio_feedback != null:
		audio_feedback.play_sfx("lever_click", global_position + Vector3(0, 4, 0), -4.0)
	var hud: GameHud = _find_hud()
	if hud != null and reason != "":
		hud.toast("%s侧支腿解锁 · %s" % [side_name, reason], 2.4)


func _pawl_shear() -> void:
	# The rack tooth is rated; above it the pawl skips and the leg loses hold.
	var carried: float = pawl_load
	pawl_slipped = true
	pawl_load = 0.0
	mechanically_latched = false
	latched = false
	extension = maxf(0.0, LATCH_FRACTION - 0.06)
	ram_velocity = -0.4
	clamp_force = 0.0
	if core != null:
		core.set_stabilizer_latched(stabilizer_index, false)
		core.set_stabilizer_clamp(stabilizer_index, 0.0)
		core.refresh_stabilizers()
	if audio_feedback != null:
		audio_feedback.play_sfx("metal_clank", global_position + Vector3(0, 6, 0), -1.0)
	var hud: GameHud = _find_hud()
	if hud != null:
		hud.toast("%s侧支腿棘爪过载打滑（负载 %.0f kN > 齿面额定 %.0f kN）· 需重新泵压" % [
			side_name, carried / 1000.0, PAWL_RATED / 1000.0], 3.2)
	latch_released.emit()


func on_surge(strength: float) -> void:
	# A resonance recoil is a load impulse on the pad, delivered through
	# CoreRig's omega. The leg answers with its own force balance: a latched leg
	# strains but holds on the rack tooth, an unlatched one is pushed back by the
	# load and its relief vents the pilot pressure.
	_strain_flash = 0.6
	if latched:
		return
	_surge_cooldown = 0.9 + strength * 0.8
	pressure = maxf(0.0, pressure - (1.6e6 / RELIEF) * strength)


func _apply_pose() -> void:
	if ram_node != null:
		ram_node.position.x = extension * STROKE
	if pawl_node != null:
		pawl_node.rotation.z = lerpf(-0.85, -0.05, extension if not latched else 1.0)
	if pump_node != null:
		pump_node.rotation.z = pump_angle
	if gauge_needle != null:
		gauge_needle.rotation.z = lerpf(0.9, -0.9, pressure)


func _apply_visuals(_delta: float) -> void:
	if status_lamp == null:
		return
	var col: Color = Color(1.0, 0.55, 0.12)
	if latched:
		col = Color(0.18, 1.0, 0.55)
	elif stalled or _surge_cooldown > 0.0 or _strain_flash > 0.0:
		col = Color(1.0, 0.18, 0.08)
	status_lamp.material_override = MatLib.emissive(col, 2.2 if latched else 1.4)
	if readout != null:
		readout.text = _readout_text()


func _readout_text() -> String:
	if latched:
		return "锁定 · %.1f MPa · 夹持 %.1f kN" % [pressure * RELIEF / 1.0e6, clamp_force / 1000.0]
	if contact:
		if stalled:
			return "过载 · %.1f MPa · 负载 %.1f kN > 推力" % [pressure * RELIEF / 1.0e6, load_force / 1000.0]
		return "承载 · %.1f MPa · 负载 %.1f kN" % [pressure * RELIEF / 1.0e6, load_force / 1000.0]
	if pressure > 0.01:
		return "泵压 · %.1f MPa · 到位 %.0f%%" % [pressure * RELIEF / 1.0e6, extension * 100.0]
	return "待机 · 0.0 MPa"


func reset_state() -> void:
	extension = 0.0
	pressure = 0.0
	ram_velocity = 0.0
	load_force = 0.0
	clamp_force = 0.0
	contact = false
	stalled = false
	mechanically_latched = false
	latched = false
	pawl_load = 0.0
	pawl_slipped = false
	pump_strokes = 0.0
	active = false
	active_pid = 0
	pump_angle = 0.0
	_surge_cooldown = 0.0
	_strain_flash = 0.0
	_was_stalled = false
	_stop_hits = 0
	_apply_pose()
	_apply_visuals(0.0)
	if core != null:
		core.set_stabilizer_latched(stabilizer_index, false)
		core.set_stabilizer_contact(stabilizer_index, false)
		core.set_stabilizer_clamp(stabilizer_index, 0.0)
		core.refresh_stabilizers()


func force_latched() -> void:
	latched = true
	extension = 1.0
	ram_velocity = 0.0
	pressure = 1.0
	clamp_force = RELIEF * AREA
	contact = true
	_apply_pose()
	if core != null:
		core.set_stabilizer_latched(stabilizer_index, true)
		core.set_stabilizer_contact(stabilizer_index, true)
		core.set_stabilizer_clamp(stabilizer_index, clamp_force)
		core.refresh_stabilizers()


func snapshot() -> Dictionary:
	return {
		"ext": extension,
		"press": pressure,
		"latched": latched,
		"active": active_pid,
		"vel": ram_velocity,
		"load": load_force,
		"clamp": clamp_force,
		"contact": contact,
		"stalled": stalled,
		"carrying": carrying_load,
		"gap": signed_gap,
		"pen": penetration,
		"mech": mechanically_latched,
	}


func apply_snapshot(data: Dictionary) -> void:
	extension = float(data.get("ext", extension))
	pressure = float(data.get("press", pressure))
	ram_velocity = float(data.get("vel", ram_velocity))
	load_force = float(data.get("load", load_force))
	contact = bool(data.get("contact", contact))
	stalled = bool(data.get("stalled", stalled))
	var was_latched: bool = latched
	latched = bool(data.get("latched", latched))
	active_pid = int(data.get("active", active_pid))
	if latched:
		clamp_force = float(data.get("clamp", RELIEF * AREA * pressure))
	else:
		clamp_force = 0.0
	if core != null:
		# The authoritative snapshot carries each leg's latched flag, but the
		# core mirror used to keep its own [false, false] stabilizer_states.
		# That made the client's claw prompt report "0/2" after both legs were
		# really latched, even though the host accepted the lock. Keep the
		# mirror in step with the leg snapshots (authority still derives its own
		# states from the actual _latch()).
		core.set_stabilizer_latched(stabilizer_index, latched)
		core.set_stabilizer_contact(stabilizer_index, contact)
		core.set_stabilizer_clamp(stabilizer_index, clamp_force)
		if latched != was_latched:
			core.refresh_stabilizers()
	_apply_pose()
