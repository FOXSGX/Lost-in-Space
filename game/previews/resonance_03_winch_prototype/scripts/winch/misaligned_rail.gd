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
const LOCK_ANGLE_LIMIT: float = deg_to_rad(1.20)
const SETTLE_SPEED: float = deg_to_rad(0.45)
const ALIGN_BAND: float = deg_to_rad(2.60)
const MAX_ANGLE: float = deg_to_rad(19.0)
const MIN_ANGLE: float = deg_to_rad(-4.5)

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
	if hinge_angle < deg_to_rad(-0.9):
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
	var settled: bool = absf(angular_velocity) <= SETTLE_SPEED
	var in_band: bool = absf(hinge_angle) <= ALIGN_BAND
	var lockable: bool = (not locked) and absf(hinge_angle) <= LOCK_ANGLE_LIMIT and settled and vertical <= 0.06
	return {
		"angle_deg": angle_deg,
		"lateral_error": lateral,
		"vertical_error": vertical,
		"end_error": end_error,
		"settled": settled,
		"in_band": in_band,
		"lockable": lockable,
		"locked": locked,
		"angular_speed": absf(angular_velocity),
		"jammed": jammed,
		"moment_arm": moment_arm,
	}

func install_lock() -> Dictionary:
	if locked:
		return {"ok": false, "reason": "锁定件已经装好"}
	if jammed:
		var jam_reason: String = "轨道还卡在碎石里，先把它拉脱"
		lock_refused.emit(jam_reason)
		return {"ok": false, "reason": jam_reason}
	var info: Dictionary = alignment()
	if not bool(info["in_band"]):
		var degrees: float = float(info["angle_deg"])
		var hint: String = "还差 %.1f°" % absf(degrees)
		if degrees > 0.0:
			hint += "，继续收缆"
		else:
			hint += "，拉过头了，反向放线"
		lock_refused.emit(hint)
		return {"ok": false, "reason": hint}
	if not bool(info["settled"]):
		var reason: String = "轨道还在晃，先稳住再上锁"
		lock_refused.emit(reason)
		return {"ok": false, "reason": reason}
	if not bool(info["lockable"]):
		var degrees2: float = float(info["angle_deg"])
		var reason2: String = "差 %.1f°，锁定销插不进去" % absf(degrees2)
		lock_refused.emit(reason2)
		return {"ok": false, "reason": reason2}
	locked = true
	lock_pin = true
	angular_velocity = 0.0
	hinge_angle = clampf(hinge_angle, -LOCK_ANGLE_LIMIT, LOCK_ANGLE_LIMIT)
	_apply_basis()
	lock_installed.emit()
	return {"ok": true, "reason": ""}

func reset() -> void:
	locked = false
	lock_pin = false
	jammed = true
	hinge_angle = start_angle
	angular_velocity = 0.0
	tension_estimate = 0.0
	stretch = 0.0
	taut = false
	applied_torque = 0.0
	_overhaul_reported = false
	_limit_reported = false
	_stall_reported = false
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
