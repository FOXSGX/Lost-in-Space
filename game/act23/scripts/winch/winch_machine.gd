extends Node3D

# -----------------------------------------------------------------------------
# WinchMachine - industrial winch: drum, motor, brake, clutch, cable length.
#
# The machine owns ONE scalar: `free_length`, the amount of cable available
# between the gantry sheave and the hook. It never touches the rail directly.
# The rail solver reads `free_length` and turns the resulting cable tension into
# torque, so the visible drum motion and the object motion always agree.
#
# Input interface (this is the whole public control surface):
#   set_haul(pressed)      haul in  (W)
#   set_payout(pressed)    pay out  (S)
#   set_creep(pressed)     fine speed modifier (Shift)
#   toggle_brake()         drum brake (Space)
#   attach_hook(anchor)    connect the cable to a WinchAnchor
#   detach_hook()          release the cable
#   reset()                restore every value to the start state
#
# Read interface:
#   snapshot() -> Dictionary  {mode, free_length, drum_angle, tension,
#                              tension_ratio, brake, overload, stalled,
#                              attached, anchor_name, drum_speed}
# -----------------------------------------------------------------------------

signal brake_changed(engaged: bool)
signal hook_connected(anchor_name: String)
signal hook_released
signal overload_started
signal overload_cleared
signal clutch_slipped
signal limit_reached(limit_name: String)

const HAUL_SPEED: float = 0.42
const CREEP_SPEED: float = 0.11
const PAYOUT_SPEED: float = 0.16
const MIN_LENGTH: float = 0.90
const MAX_LENGTH: float = 12.00
const DRUM_RADIUS: float = 0.34

# --- MECHANICS-002C: 鼓由力矩驱动，不再由"预设线速度"驱动 -------------------
# 旧实现：free_length 以 HAUL_SPEED 积分，drum_angle 是它的结果；电机上限只用来
# 截断张力，离合器"打滑"是把 free_length 往回退。那套东西没有转动惯量、没有反
# 作用力矩，也没有真堵转。现在改成：
#   I · dω/dt = τ_motor(ω) − T·r − τ_brake − τ_bearing
#   free_length += −ω · r · dt
const DRUM_INERTIA: float = 45.0          # 卷筒 + 减速箱折算惯量（kg·m²）
const MOTOR_STALL_TORQUE: float = 1088.0  # 额定：3200 N × 0.34 m
const MOTOR_FREE_SPEED: float = 1.30      # 空载收绳角速度（rad/s，≈0.44 m/s）
const PAYOUT_TORQUE: float = 220.0        # 放绳侧的电机/阻尼力矩
const PAYOUT_FREE_SPEED: float = 0.62     # 空载放绳角速度
const BRAKE_TORQUE: float = 950.0         # 鼓刹满行程摩擦容量（N·m）
const BRAKE_ENGAGE_RATE: float = 4.0      # 鼓刹行程建立速度（1/s）
const BEARING_TORQUE: float = 14.0        # 轴承静阻力矩
const VISCOUS: float = 10.0               # 粘性阻尼（N·m per rad/s）
const OMEGA_MAX: float = 3.0              # 硬上限（rad/s）

@export var max_force: float = 3200.0
@export var overload_ratio: float = 0.86
@export var start_length: float = 3.00

var free_length: float = 3.00
var drum_angle: float = 0.0
var drum_speed: float = 0.0
var drum_omega: float = 0.0
var brake: bool = true
var brake_travel: float = 1.0
var brake_slipping: bool = false
var haul_pressed: bool = false
var payout_pressed: bool = false
var creep: bool = false
var attached: bool = false
var anchor: Node3D = null
var mode: String = "idle"          # idle | haul | payout | stall | braked
var tension: float = 0.0
var overload: bool = false
var stalled: bool = false
# 每帧力矩账本（测试与 HUD 直接读，任何一项都不在别处被写第二次）
var motor_torque: float = 0.0
var cable_torque: float = 0.0
var brake_torque: float = 0.0
var net_torque: float = 0.0
var inertia: float = DRUM_INERTIA
# Set by WinchRig: 1.0 far from the receiver, tapering to 0.30 inside the last
# 7 deg so a normal key press can stop the section inside the capture window.
# MECHANICS-002C: it now scales the MOTOR TORQUE, not a prescribed speed - the
# drum slows down because it is weaker near the mark, not because a script says so.
var speed_scale: float = 1.0
var _overload_time: float = 0.0
var _hauled_this_tick: float = 0.0
var _was_overload: bool = false

func _ready() -> void:
	add_to_group("winch_machine")
	free_length = start_length

func set_haul(pressed: bool) -> void:
	haul_pressed = pressed
	if pressed:
		payout_pressed = false
		if brake:
			brake = false
			brake_changed.emit(false)
		stalled = false

func set_payout(pressed: bool) -> void:
	payout_pressed = pressed
	if pressed:
		haul_pressed = false
		if brake:
			brake = false
			brake_changed.emit(false)
		stalled = false

func set_creep(pressed: bool) -> void:
	creep = pressed

func toggle_brake() -> void:
	brake = not brake
	if brake:
		haul_pressed = false
		payout_pressed = false
	brake_changed.emit(brake)

func attach_hook(target: Node3D) -> bool:
	if target == null:
		return false
	if attached and anchor != null:
		detach_hook()
	anchor = target
	attached = true
	hook_connected.emit(str(target.call("describe")))
	return true

func detach_hook() -> void:
	if not attached:
		return
	attached = false
	anchor = null
	haul_pressed = false
	payout_pressed = false
	stalled = false
	overload = false
	tension = 0.0
	_overload_time = 0.0
	_was_overload = false
	mode = "braked" if brake else "idle"
	hook_released.emit()

# Feed out enough cable to reach a newly hooked anchor. Only ever pays out, so a
# player who already unwound the drum is not pulled back in.
func feed_to(target_length: float) -> void:
	free_length = clampf(maxf(free_length, target_length), MIN_LENGTH, MAX_LENGTH)
	mode = "braked" if brake else "idle"

func anchor_world() -> Vector3:
	if anchor == null:
		return global_position
	return anchor.call("attach_point") as Vector3

# --- simulation -------------------------------------------------------------

# Called once per physics tick by the rig, BEFORE the rail solver runs.
#
# MECHANICS-002C: 卷筒现在是"受力矩驱动的刚体折算量"，不是一个按速度滚动的计数器：
#   * 电机有堵转力矩上限和空载角速度（力矩-转速曲线），没有无限驱动力；
#   * 缆绳张力以 T·r 的形式反作用到鼓上（上一帧求解出的真实张力，滞后 1 帧）；
#   * 鼓刹是有限容量的摩擦制动力矩，超过容量就会打滑，不是"把速度清零"；
#   * 收放绳长由 ω·r 积分得到，撞到卷筒上/下硬限位时 ω 真的被机械止挡吃掉。
func tick(delta: float) -> void:
	_hauled_this_tick = 0.0
	# 鼓刹行程（0..1）按机械速度建立/释放，制动力矩随行程线性增长。
	var brake_target: float = 1.0 if brake else 0.0
	brake_travel = move_toward(brake_travel, brake_target, BRAKE_ENGAGE_RATE * delta)
	var motor: float = _motor_torque()
	var cable: float = -tension * DRUM_RADIUS
	var drag: float = -signf(drum_omega) * BEARING_TORQUE - VISCOUS * drum_omega
	var capacity: float = BRAKE_TORQUE * brake_travel
	var brake_t: float = 0.0
	brake_slipping = false
	if capacity > 1.0:
		var drive: float = motor + cable + drag
		if absf(drive) <= capacity and absf(drum_omega) < 0.02:
			# 静摩擦保持：闸能吃掉这点力矩，鼓就真的不动。
			drum_omega = 0.0
			brake_t = -drive
			motor_torque = motor
			cable_torque = cable
			brake_torque = brake_t
			net_torque = 0.0
			drum_speed = 0.0
			mode = "braked"
			_apply_length(delta)
			return
		# 超过容量：按库仑摩擦打滑（力矩恒定、方向反对运动）。
		var slip_dir: float = signf(drum_omega) if absf(drum_omega) > 0.001 else signf(drive)
		brake_t = -slip_dir * capacity
		brake_slipping = true
	var net: float = motor + cable + drag + brake_t
	motor_torque = motor
	cable_torque = cable
	brake_torque = brake_t
	net_torque = net
	drum_omega = clampf(drum_omega + net / DRUM_INERTIA * delta, -OMEGA_MAX, OMEGA_MAX)
	drum_speed = drum_omega
	if attached and not brake and haul_pressed and not stalled and drum_omega > 0.02:
		mode = "haul"
	elif attached and not brake and payout_pressed and drum_omega < -0.02:
		mode = "payout"
	elif absf(drum_omega) < 0.02:
		mode = "stall" if haul_pressed and not brake else ("braked" if brake else "idle")
	else:
		mode = "idle"
	_apply_length(delta)


# 收放绳：由 ω·r 积分；撞到卷筒硬限位时把 ω 吃掉（真实机械止挡，不穿模）。
func _apply_length(delta: float) -> void:
	var previous: float = free_length
	var delta_length: float = -drum_omega * DRUM_RADIUS * delta
	var target: float = clampf(previous + delta_length, MIN_LENGTH, MAX_LENGTH)
	if absf(target - (previous + delta_length)) > 0.000001:
		if delta_length > 0.0:
			limit_reached.emit("drum_full")
		else:
			limit_reached.emit("drum_empty")
		drum_omega = 0.0
		drum_speed = 0.0
		net_torque = 0.0
	free_length = target
	_hauled_this_tick = previous - free_length
	drum_angle = fposmod(drum_angle + drum_omega * delta, TAU)


func _motor_torque() -> float:
	var scale: float = clampf(speed_scale, 0.05, 1.0)
	if haul_pressed and not stalled:
		# 力矩-转速曲线：堵转时给额定力矩，空载时降到 0。
		return MOTOR_STALL_TORQUE * scale * clampf(1.0 - drum_omega / MOTOR_FREE_SPEED, 0.0, 1.0)
	if payout_pressed:
		return -PAYOUT_TORQUE * clampf(1.0 + drum_omega / PAYOUT_FREE_SPEED, 0.0, 1.0)
	return 0.0

# Called once per physics tick by the rig, AFTER the rail solver ran.
func observe_tension(value: float, delta: float) -> void:
	tension = value
	var ratio: float = tension / maxf(max_force, 1.0)
	# 真堵转：还按着收绳、张力到顶、鼓已经转不动。没有"把绳长退回去"的假打滑。
	if haul_pressed and not brake and ratio >= 0.98 and absf(drum_omega) < 0.05:
		if not stalled:
			stalled = true
			clutch_slipped.emit()
		mode = "stall"
	if ratio >= overload_ratio:
		_overload_time += delta
		if _overload_time > 0.35 and not overload:
			overload = true
			overload_started.emit()
	else:
		_overload_time = maxf(0.0, _overload_time - delta * 1.6)
		if _overload_time <= 0.0 and overload:
			overload = false
			overload_cleared.emit()
	# 张力降下来（或松开收绳）后离合器/堵转标记要能恢复。
	if stalled and (not haul_pressed or ratio < 0.5):
		stalled = false
	_was_overload = overload

func tension_ratio() -> float:
	return clampf(tension / maxf(max_force, 1.0), 0.0, 1.2)

func torque_state() -> Dictionary:
	return {
		"omega": snappedf(drum_omega, 0.001),
		"inertia": inertia,
		"motor_torque": snappedf(motor_torque, 0.1),
		"cable_torque": snappedf(cable_torque, 0.1),
		"brake_torque": snappedf(brake_torque, 0.1),
		"net_torque": snappedf(net_torque, 0.1),
		"tension": snappedf(tension, 0.1),
		"radius": DRUM_RADIUS,
		"free_length": snappedf(free_length, 0.0001),
		"brake_travel": snappedf(brake_travel, 0.001),
		"brake_slipping": brake_slipping,
		"stalled": stalled,
		"mode": mode,
		"motor_stall_torque": MOTOR_STALL_TORQUE,
		"brake_capacity": BRAKE_TORQUE,
	}

func reset() -> void:
	free_length = start_length
	drum_angle = 0.0
	drum_speed = 0.0
	drum_omega = 0.0
	brake = true
	brake_travel = 1.0
	brake_slipping = false
	haul_pressed = false
	payout_pressed = false
	creep = false
	attached = false
	anchor = null
	mode = "braked"
	tension = 0.0
	overload = false
	stalled = false
	speed_scale = 1.0
	motor_torque = 0.0
	cable_torque = 0.0
	brake_torque = 0.0
	net_torque = 0.0
	_overload_time = 0.0
	_hauled_this_tick = 0.0
	brake_changed.emit(true)

func snapshot() -> Dictionary:
	return {
		"mode": mode,
		"free_length": free_length,
		"drum_angle": drum_angle,
		"drum_speed": drum_speed,
		"drum_omega": drum_omega,
		"tension": tension,
		"tension_ratio": tension_ratio(),
		"brake": brake,
		"brake_travel": brake_travel,
		"brake_slipping": brake_slipping,
		"motor_torque": motor_torque,
		"cable_torque": cable_torque,
		"brake_torque": brake_torque,
		"net_torque": net_torque,
		"overload": overload,
		"stalled": stalled,
		"attached": attached,
		"anchor_name": str(anchor.call("describe")) if anchor != null else "",
		"creep": creep,
	}

