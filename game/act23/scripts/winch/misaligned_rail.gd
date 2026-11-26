extends AnimatableBody3D

# -----------------------------------------------------------------------------
# MisalignedRail - one short rail section on a single-DOF hinge.
#
# The section is a real, collidable structure that swings about a slightly tilted
# vertical hinge. It is NOT a progress bar: cable length changes the hinge angle,
# the hinge angle moves the geometry, and the geometry is what the player has to
# bring back onto the receiver bracket.
#
# Physics model (1-DOF rigid body, deliberately small and bounded)
#   state      theta (hinge angle, rad), omega (rad/s)
#   inertia    INERTIA, kg*m^2 about the hinge
#   torques    cable:  T * moment_arm, direction that shortens the cable
#              sag:    SAG_TORQUE, constant, pulls the section away from the
#                      bracket (damaged hinge + its own weight)
#              damp:   -DAMP * omega
#   cable      T = clamp((|sheave - eye| - free_length) * CABLE_STIFFNESS,
#                        0, max_force * 1.05)
#              moment_arm = |d(cable length)/d(theta)|, measured at the real eye
#
# Consequences the player can learn and predict:
#   * slack cable -> no cable torque; the sag wins and the section falls back
#   * taut cable  -> the section follows the drum: paying out lowers it, hauling
#                    raises it. Cable length and angle are monotonically linked.
#   * a short moment arm (mid eye) cannot beat the jam, a long one (far eye) can
#   * over-pulling is recoverable by paying out, because the sag pulls it back
#   * once the pin is in, the body is frozen; there is no residual drift
#
# Every integration step is bounded: angular acceleration is capped, angular speed
# is capped, and the travel stops clamp hard. No step reads a value it just wrote.
# -----------------------------------------------------------------------------

signal lock_installed
signal lock_refused(reason: String)
signal overshoot
signal angle_limited(limit_name: String)
signal jam_broken
signal jam_stalled

const RAIL_LENGTH: float = 6.40
const INERTIA: float = 9000.0                 # kg*m^2 about the hinge
const CABLE_STIFFNESS: float = 26000.0        # N per metre of stretch
const SAG_TORQUE: float = 2600.0              # N*m pulling away from the bracket
const DAMP: float = 42000.0                   # N*m per rad/s
const ANGULAR_SPEED_MAX: float = 1.6          # rad/s hard cap
const ANGULAR_ACCEL_MAX: float = 6.0          # rad/s^2 hard cap
const LOCK_ANGLE_LIMIT: float = deg_to_rad(2.00)
# Real-keyboard playtest: a 2 deg window at the old haul speed was ~0.28 s of
# travel, and the pin additionally demanded 0.35 s of near-zero angular speed.
# The capture window is now the receiver's guide slot itself: within 5 deg the
# tapered pin and guide plates pull the last few centimetres home over
# GUIDE_TIME. Beyond 5 deg the section is visibly skewed and the pin refuses, so
# this is a mechanical capture, not a win button.
const CAPTURE_ANGLE: float = deg_to_rad(4.00)
const GUIDE_TIME: float = 0.55
const SETTLE_SPEED: float = deg_to_rad(0.45)
const ALIGN_BAND: float = deg_to_rad(3.00)
const MAX_ANGLE: float = deg_to_rad(19.0)
# The old -4.5 deg stop meant the whole possible overshoot was inside the new
# capture, so the pin could never refuse. -8 deg keeps the overshoot lesson:
# a small overshoot is caught by the guide slot, a real one must be paid out.
const MIN_ANGLE: float = deg_to_rad(-8.0)

@export var start_angle: float = deg_to_rad(15.0)
@export var hinge_axis: Vector3 = Vector3(0.105, 1.0, 0.028)
# N*m needed to break the section free. Tuned so the far eye (long arm) can
# beat it at ~85% of the winch rating, while the mid eye saturates and slips.
@export var jam_torque: float = 4000.0

var hinge_angle: float = 0.0
var angular_velocity: float = 0.0
var locked: bool = false
var lock_pin: bool = false
var jammed: bool = true
var tension_estimate: float = 0.0
var stretch: float = 0.0
var taut: bool = false
var moment_arm: float = 0.0
var applied_torque: float = 0.0
var _overhaul_reported: bool = false
var _limit_reported: bool = false
var _stall_reported: bool = false
var _settle_time: float = 0.0
var guiding: bool = false
var guide_progress: float = 0.0
var _guide_from: float = 0.0
var _guide_t: float = 0.0
var last_capture_angle: float = 0.0
# Co-op hardware driven by WinchRig:
#   bracket_engaged - the safety prop is planted; the section cannot rotate, so
#                     the drum just loads up (and the clutch slips).
#   capture_bonus   - extra capture angle granted while somebody holds the
#                     receiver's hand wheel. The pin still has to travel.
var bracket_engaged: bool = false
var capture_bonus: float = 0.0
# True while the drum is idle: the hand wheel then holds the section instead of
# merely assisting, which is what makes it useful as a two-person tool.
var guide_hold: bool = true

func _ready() -> void:
	add_to_group("misaligned_rail")
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	hinge_axis = hinge_axis.normalized()
	hinge_angle = start_angle
	_apply_basis()

func _apply_basis() -> void:
	basis = Basis(hinge_axis, hinge_angle)

func far_point() -> Vector3:
	return to_global(Vector3(RAIL_LENGTH, 0.0, 0.0))

func rest_far_point() -> Vector3:
	return _point_at(0.0, Vector3(RAIL_LENGTH, 0.0, 0.0))

func attach_world(anchor_local: Vector3) -> Vector3:
	return to_global(anchor_local)

# World position of a local point when the hinge sits at `angle`. The body is
# already rotated by hinge_angle, so only the difference is applied on top:
# applying Basis(axis, angle) through to_global() as well would rotate twice.
func _point_at(angle: float, local: Vector3) -> Vector3:
	return to_global(Basis(hinge_axis, angle - hinge_angle) * local)

# Moment arm of the cable about the hinge, measured at the real attachment point.
func cable_moment_arm(anchor_local: Vector3, sheave: Vector3) -> float:
	var epsilon: float = 0.004
	var plus: float = _point_at(hinge_angle + epsilon, anchor_local).distance_to(sheave)
	var minus: float = _point_at(hinge_angle - epsilon, anchor_local).distance_to(sheave)
	return absf(plus - minus) / (2.0 * epsilon)

func solve_cable(delta: float, sheave: Vector3, free_length: float, max_force: float, anchor_local: Vector3) -> Dictionary:
	if locked:
		angular_velocity = 0.0
		stretch = 0.0
		tension_estimate = 0.0
		applied_torque = 0.0
		taut = false
		return {"moved": 0.0, "tension": 0.0, "taut": false, "moment_arm": 0.0}
	if delta <= 0.0:
		return {"moved": 0.0, "tension": tension_estimate, "taut": taut, "moment_arm": moment_arm}
	# Safety prop: the section is mechanically held. Load still builds in the
	# cable (so the player can feel they are pulling against a prop), but the
	# geometry does not move until somebody folds it away.
	if bracket_engaged:
		var attach_b: Vector3 = to_global(anchor_local)
		var distance_b: float = attach_b.distance_to(sheave)
		stretch = maxf(0.0, distance_b - free_length)
		taut = stretch > 0.0005
		moment_arm = cable_moment_arm(anchor_local, sheave)
		tension_estimate = clampf(stretch * CABLE_STIFFNESS, 0.0, max_force * 1.05)
		angular_velocity = 0.0
		applied_torque = 0.0
		_apply_basis()
		return {"moved": 0.0, "tension": tension_estimate, "taut": taut, "moment_arm": moment_arm}
	# The pin has entered the receiver's guide slot. From here the slot - not the
	# drum - owns the last few centimetres: a bounded, visible pull to 0 deg.
	# The cable is slack during this (the player has already stopped the drum),
	# so no tension is invented by the guide.
	if guiding:
		var guided_from: float = hinge_angle
		_guide_t = minf(_guide_t + delta, GUIDE_TIME)
		var t: float = _guide_t / GUIDE_TIME
		guide_progress = t
		var eased: float = t * t * (3.0 - 2.0 * t)
		hinge_angle = lerpf(_guide_from, 0.0, eased)
		angular_velocity = 0.0
		stretch = 0.0
		taut = false
		tension_estimate = 0.0
		applied_torque = 0.0
		_apply_basis()
		if t >= 1.0:
			_finish_lock()
		return {"moved": hinge_angle - guided_from, "tension": 0.0, "taut": false,
			"moment_arm": moment_arm, "guiding": t}

	var attach: Vector3 = to_global(anchor_local)
	var distance: float = attach.distance_to(sheave)
	stretch = maxf(0.0, distance - free_length)
	taut = stretch > 0.0005
	moment_arm = cable_moment_arm(anchor_local, sheave)

	# Cable spring, saturated at the machine rating.
	tension_estimate = clampf(stretch * CABLE_STIFFNESS, 0.0, max_force * 1.05)
	applied_torque = tension_estimate * moment_arm

	var cable_torque: float = 0.0
	if taut:
		# Sign: pulling the eye toward the sheave shortens the cable.
		var epsilon: float = 0.01
		var plus: float = _point_at(hinge_angle + epsilon, anchor_local).distance_to(sheave)
		var minus: float = _point_at(hinge_angle - epsilon, anchor_local).distance_to(sheave)
		var gradient: float = (plus - minus) / (2.0 * epsilon)
		var direction: float = -1.0 if gradient > 0.0 else 1.0
		cable_torque = applied_torque * direction

	# Jam: the section does not budge until the machine can beat the debris.
	if jammed:
		if taut and absf(cable_torque) >= jam_torque:
			jammed = false
			_stall_reported = false
			jam_broken.emit()
		else:
			angular_velocity = 0.0
			# Only complain about leverage when the machine is actually at its
			# rating: the far eye passes through 80% of the jam torque on its way
			# to breaking it, and must not be told its arm is too short.
			if taut and tension_estimate >= max_force * 0.98 and not _stall_reported:
				_stall_reported = true
				jam_stalled.emit()
			_apply_basis()
			return {"moved": 0.0, "tension": tension_estimate, "taut": taut, "moment_arm": moment_arm}

	# Sag always pulls the section away from the bracket (toward +angle).
	var torque: float = cable_torque + SAG_TORQUE - DAMP * angular_velocity
	var acceleration: float = clampf(torque / INERTIA, -ANGULAR_ACCEL_MAX, ANGULAR_ACCEL_MAX)
	angular_velocity = clampf(angular_velocity + acceleration * delta, -ANGULAR_SPEED_MAX, ANGULAR_SPEED_MAX)

	# Deadband: without it the section would creep forever under the sag torque.
	if absf(angular_velocity) < 0.0015 and not taut:
		angular_velocity = 0.0

	# "Settled" has to mean "has been still for a while", not "is still for one
	# frame": the section drifts up under its own sag whenever the cable goes
	# slack, and a one-frame reading would let the pin in during that drift.
	if absf(angular_velocity) <= SETTLE_SPEED:
		_settle_time += delta
	else:
		_settle_time = 0.0

	var before: float = hinge_angle
	hinge_angle += angular_velocity * delta

	if hinge_angle > MAX_ANGLE:
		hinge_angle = MAX_ANGLE
		angular_velocity = minf(angular_velocity, 0.0)
		if not _limit_reported:
			_limit_reported = true
			angle_limited.emit("far_stop")
	elif hinge_angle < MIN_ANGLE:
		hinge_angle = MIN_ANGLE
		angular_velocity = maxf(angular_velocity, 0.0)
		if not _limit_reported:
			_limit_reported = true
			angle_limited.emit("near_stop")
	else:
		_limit_reported = false

	# Overshoot: the section crossed the bracket line the wrong way.
	if hinge_angle < deg_to_rad(-2.60):
		if not _overhaul_reported:
			_overhaul_reported = true
			overshoot.emit()
	elif hinge_angle > deg_to_rad(0.5):
		_overhaul_reported = false

	_apply_basis()
	return {"moved": hinge_angle - before, "tension": tension_estimate, "taut": taut, "moment_arm": moment_arm}

func alignment() -> Dictionary:
	var angle_deg: float = rad_to_deg(hinge_angle)
	var actual: Vector3 = far_point()
	var rest: Vector3 = rest_far_point()
	var lateral: float = absf(actual.z - rest.z)
	var vertical: float = absf(actual.y - rest.y)
	var end_error: float = actual.distance_to(rest)
	var settled: bool = absf(angular_velocity) <= SETTLE_SPEED and _settle_time >= 0.35
	var in_band: bool = absf(hinge_angle) <= ALIGN_BAND
	var capture: float = CAPTURE_ANGLE + capture_bonus
	var lockable: bool = (not locked) and absf(hinge_angle) <= LOCK_ANGLE_LIMIT and settled and vertical <= 0.06
	# The guide slot's actual capture range. This is what the HUD paints as the
	# green band and what install_lock() accepts for the mechanical final pull.
	# Holding the receiver's hand wheel widens it by 2.5 deg.
	var captureable: bool = (not locked) and (not guiding) and (not jammed) \
		and (not bracket_engaged) and absf(hinge_angle) <= capture
	return {
		"angle_deg": angle_deg,
		"lateral_error": lateral,
		"vertical_error": vertical,
		"end_error": end_error,
		"settled": settled,
		"in_band": in_band,
		"lockable": lockable,
		"captureable": captureable,
		"capture_deg": rad_to_deg(capture),
		"guiding": guiding,
		"guide_progress": guide_progress,
		"lock_pin": lock_pin,
		"locked": locked,
		"angular_speed": absf(angular_velocity),
		"jammed": jammed,
		"moment_arm": moment_arm,
		"bracket": bracket_engaged,
	}

func install_lock() -> Dictionary:
	if locked:
		return {"ok": false, "reason": "锁定件已经装好"}
	if guiding:
		return {"ok": false, "reason": "导向销正在把轨道拉回线路", "guiding": true}
	if bracket_engaged:
		var bracket_reason: String = "安全支架还撑着轨道，先收起支架再插销"
		lock_refused.emit(bracket_reason)
		return {"ok": false, "reason": bracket_reason}
	if jammed:
		var jam_reason: String = "轨道还卡在碎石里，先把它拉脱"
		lock_refused.emit(jam_reason)
		return {"ok": false, "reason": jam_reason}
	var info: Dictionary = alignment()
	var degrees: float = float(info["angle_deg"])
	var capture: float = CAPTURE_ANGLE + capture_bonus
	if absf(hinge_angle) > capture:
		# Outside the guide slot the pin physically cannot start: the nose and
		# receiver jaws are 5 deg apart by construction, so this is not a UI
		# rule. Tell the player which way to correct.
		var hint: String = "还差 %.1f°（导向槽只吃 ±%.1f°）" % [absf(degrees), rad_to_deg(capture)]
		if degrees > 0.0:
			hint += "，继续收缆"
		else:
			hint += "，拉过头了，反向放线"
		lock_refused.emit(hint)
		return {"ok": false, "reason": hint, "capture_deg": rad_to_deg(capture)}
	# Inside 2 deg and already still: drive the pin straight home.
	if bool(info["lockable"]):
		_finish_lock()
		return {"ok": true, "reason": "", "mode": "direct"}
	# Inside the guide slot: the tapered pin and the receiver's guide plates
	# complete the last short segment over GUIDE_TIME. The rail is not snapped:
	# it rotates, the pin travels, and the lock is only reported when it lands.
	last_capture_angle = hinge_angle
	_guide_from = hinge_angle
	_guide_t = 0.0
	guide_progress = 0.0
	guiding = true
	lock_pin = true
	angular_velocity = 0.0
	_settle_time = 0.0
	return {"ok": true, "reason": "", "mode": "guided",
		"from_deg": rad_to_deg(last_capture_angle), "guide_time": GUIDE_TIME}

func _finish_lock() -> void:
	if locked:
		return
	locked = true
	lock_pin = true
	guiding = false
	guide_progress = 1.0
	angular_velocity = 0.0
	# The tapered pin pulls the section home: once locked, the swing rails are
	# exactly in line with the approach and receiver rails rather than "within
	# tolerance". Everything downstream (cart clearance, the painted reset line,
	# the receiver cradle) assumes the repaired line is straight.
	hinge_angle = 0.0
	_apply_basis()
	lock_installed.emit()

func reset() -> void:
	locked = false
	lock_pin = false
	jammed = true
	bracket_engaged = false
	capture_bonus = 0.0
	hinge_angle = start_angle
	angular_velocity = 0.0
	tension_estimate = 0.0
	stretch = 0.0
	taut = false
	applied_torque = 0.0
	_overhaul_reported = false
	_limit_reported = false
	_stall_reported = false
	_settle_time = 0.0
	guiding = false
	guide_progress = 0.0
	_guide_t = 0.0
	last_capture_angle = 0.0
	_apply_basis()

func snapshot() -> Dictionary:
	var info: Dictionary = alignment()
	info["lock_pin"] = lock_pin
	info["tension"] = tension_estimate
	info["stretch"] = stretch
	info["hinge_angle"] = hinge_angle
	info["angular_velocity"] = angular_velocity
	info["taut"] = taut
	info["torque"] = applied_torque
	return info

# The receiver's hand wheel. It is a worm-drive wheel on the receiving jaws: it
# only has authority once the nose is inside the jaw range (6 deg), it pulls the
# nose TOWARD the line, and while it is held it holds the section (the worm gear
# cannot be back-driven by the sag). It can never replace the winch: outside the
# jaw range it does nothing.
func apply_guide(delta: float, max_rate: float) -> float:
	if locked or guiding or jammed or bracket_engaged:
		return 0.0
	if absf(hinge_angle) > deg_to_rad(8.0):
		return 0.0
	var before: float = hinge_angle
	var step: float = clampf(-hinge_angle, -max_rate * delta, max_rate * delta)
	hinge_angle += step
	# Worm gear: with the drum idle the wheel owns the position. While the drum
	# is hauling the drum wins and the wheel only assists, so one player holding
	# the wheel can never silently disable the winch for everybody.
	if guide_hold:
		angular_velocity = 0.0
	else:
		angular_velocity *= 0.65
	_apply_basis()
	return hinge_angle - before
