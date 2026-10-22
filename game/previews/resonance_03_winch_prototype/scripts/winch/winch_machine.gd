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

const HAUL_SPEED: float = 0.60
const CREEP_SPEED: float = 0.18
const PAYOUT_SPEED: float = 0.75
const MIN_LENGTH: float = 0.90
const MAX_LENGTH: float = 12.00
const DRUM_RADIUS: float = 0.34

@export var max_force: float = 3200.0
@export var overload_ratio: float = 0.86
@export var start_length: float = 3.00

var free_length: float = 3.00
var drum_angle: float = 0.0
var drum_speed: float = 0.0
var brake: bool = true
var haul_pressed: bool = false
var payout_pressed: bool = false
var creep: bool = false
var attached: bool = false
var anchor: Node3D = null
var mode: String = "idle"          # idle | haul | payout | stall | braked
var tension: float = 0.0
var overload: bool = false
var stalled: bool = false
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
func tick(delta: float) -> void:
	var speed: float = 0.0
	_hauled_this_tick = 0.0
	if attached and not brake:
		if haul_pressed and not stalled:
			speed = -(CREEP_SPEED if creep else HAUL_SPEED)
		elif payout_pressed:
			speed = PAYOUT_SPEED
	var previous: float = free_length
	free_length = clampf(free_length + speed * delta, MIN_LENGTH, MAX_LENGTH)
	_hauled_this_tick = previous - free_length
	if free_length <= MIN_LENGTH + 0.0001 and speed < 0.0:
		speed = 0.0
		if not brake:
			limit_reached.emit("drum_full")
	if free_length >= MAX_LENGTH - 0.0001 and speed > 0.0:
		speed = 0.0
		limit_reached.emit("drum_empty")
	drum_speed = -speed / DRUM_RADIUS
	drum_angle = fposmod(drum_angle + drum_speed * delta, TAU)
	if attached and not brake and haul_pressed and not stalled:
		mode = "haul"
	elif attached and not brake and payout_pressed:
		mode = "payout"
	elif brake:
		mode = "braked"
	else:
		mode = "idle"

# Called once per physics tick by the rig, AFTER the rail solver ran.
func observe_tension(value: float, delta: float) -> void:
	tension = value
	var ratio: float = tension / maxf(max_force, 1.0)
	# Clutch: if the drum cannot pull any harder, it slips back instead of
	# injecting unbounded energy into the structure.
	if haul_pressed and not brake and ratio >= 0.995 and _hauled_this_tick > 0.0:
		free_length += _hauled_this_tick
		_hauled_this_tick = 0.0
		drum_angle = fposmod(drum_angle - 0.25, TAU)
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
	if _was_overload and not overload and stalled and ratio < 0.6:
		stalled = false
	# A recovered rail can leave the clutch flag set after the load has already
	# dropped; clear it so the HUD does not report "slipping" while aligned.
	if stalled and ratio < 0.5:
		stalled = false
	_was_overload = overload

func tension_ratio() -> float:
	return clampf(tension / maxf(max_force, 1.0), 0.0, 1.2)

func reset() -> void:
	free_length = start_length
	drum_angle = 0.0
	drum_speed = 0.0
	brake = true
	haul_pressed = false
	payout_pressed = false
	creep = false
	attached = false
	anchor = null
	mode = "braked"
	tension = 0.0
	overload = false
	stalled = false
	_overload_time = 0.0
	_hauled_this_tick = 0.0
	brake_changed.emit(true)

func snapshot() -> Dictionary:
	return {
		"mode": mode,
		"free_length": free_length,
		"drum_angle": drum_angle,
		"drum_speed": drum_speed,
		"tension": tension,
		"tension_ratio": tension_ratio(),
		"brake": brake,
		"overload": overload,
		"stalled": stalled,
		"attached": attached,
		"anchor_name": str(anchor.call("describe")) if anchor != null else "",
		"creep": creep,
	}
