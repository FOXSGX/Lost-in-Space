extends CharacterBody3D
class_name MilkDragonKeeper

## 奶龙的唯一职责：守在装货口前拦球。
##
## 不做的事（本轮明确移除）：不抢玩家手上的东西、不追玩家、不挑衅/怒气/扑击、
## 不叼球回窝、不伤害玩家。旧实现留在 git 历史里，不与新规则混用。
##
## 设计要点：
##   - 只在球门前的一块矩形区域里活动（guard_min_x..guard_max_x，|z| ≤ guard_half_z）；
##   - 反应有延迟、加速度与最高速度有限，不能瞬移、也不会预知每一脚；
##   - 拦到球就把它小幅弹回场内（球永远可以继续争抢）；
##   - 球贴身且很慢时会被轻轻推离，避免身体把球永久压住。

signal blocked(point: Vector3, speed: float)
signal state_changed(current: String)

const STATE_IDLE := "待机"
const STATE_TRACK := "跟球"
const STATE_BLOCK := "拦球"

const STATE_NAMES := {
	STATE_IDLE: "待机",
	STATE_TRACK: "跟球",
	STATE_BLOCK: "拦球",
}

@export var home := Vector3(10.3, 0.0, 0.0)
## 守门区域：比球门口（z ±2.4）略宽一点，但仍然到不了门框外侧。
@export var guard_min_x := 8.5
@export var guard_max_x := 11.6
@export var guard_half_z := 2.7
@export var max_speed := 2.9
@export var max_accel := 14.0
## 反应延迟：每隔这么久才更新一次“球在哪”，制造可被假动作骗到的空当。
@export var react_delay := 0.24
@export var block_radius := 0.95
@export var block_cooldown := 0.55
## 看到射门后“扑向当前方向”的时间：这段时间内不再修正目标，所以打反方向能过
@export var commit_time := 0.32
@export var shot_speed := 9.0
@export var turn_speed := 6.0
@export var gravity := 18.0

var ball: Node3D
var goal: Node3D
var state := STATE_IDLE
var visual: Node3D

var _target := Vector3.ZERO
var _think := 0.0
var _block_timer := 0.0
var _block_ready := 0.0
var _commit_timer := 0.0
var _last_ball_speed := 0.0
var _time := 0.0
var _last_position := Vector3.ZERO


func _ready() -> void:
	collision_layer = 16
	collision_mask = 2 | 4 | 1
	floor_snap_length = 0.3
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.48
	capsule.height = 1.6
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.80
	add_child(shape)
	visual = get_node_or_null("Visual") as Node3D
	_target = home
	_last_position = global_position
	_set_state(STATE_IDLE)


func setup_ball(next_ball: Node3D) -> void:
	ball = next_ball


func setup_goal(next_goal: Node3D) -> void:
	goal = next_goal


func state_name() -> String:
	return STATE_NAMES.get(state, state)


func guard_center() -> Vector3:
	return home


func reset_to_home() -> void:
	global_position = home
	velocity = Vector3.ZERO
	rotation.y = PI * 0.5
	_target = home
	_block_timer = 0.0
	_block_ready = 0.0
	_think = 0.0
	_last_position = global_position
	if visual != null:
		visual.call("set_locomotion", 0.0, 0.0)
		visual.call("set_block", 0.0)
	_set_state(STATE_IDLE)


func _physics_process(delta: float) -> void:
	_time += delta
	_block_timer = maxf(0.0, _block_timer - delta)
	_block_ready = maxf(0.0, _block_ready - delta)

	if ball == null or not is_instance_valid(ball):
		_stand(delta)
		return

	_think += delta
	if _commit_timer > 0.0:
		_commit_timer = maxf(0.0, _commit_timer - delta)
	elif _think >= react_delay:
		_think = 0.0
		_update_target()
	_apply_block()

	_move_towards_target(delta)
	_face_target(delta)
	_anti_crush(delta)

	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	global_position.y = maxf(global_position.y, 0.0)
	_update_visual(delta)


## 目标点：站在球与球门中心之间，且不离开守门区；带一点判断误差与滞后。
func _update_target() -> void:
	var ball_pos := ball.global_position
	var ball_vel := Vector3.ZERO
	if ball is CharacterBody3D:
		ball_vel = (ball as CharacterBody3D).velocity
	# 刚被射门：扑向当前方向，短时间内不再修正（所以打反方向有效）
	var speed_now := ball_vel.length()
	if speed_now > shot_speed and _last_ball_speed <= shot_speed:
		_commit_timer = commit_time
	_last_ball_speed = speed_now
	var threat := ball_pos.x > 2.0 and absf(ball_pos.z) < 9.0
	if not threat:
		_target = home
		return
	var lead := clampf(ball_vel.z * 0.12, -1.0, 1.0)
	var wobble := sin(_time * 1.7) * 0.22
	var target_x := clampf(ball_pos.x + 0.9, guard_min_x, guard_max_x)
	var target_z := clampf(ball_pos.z + lead + wobble, -guard_half_z + 0.35, guard_half_z - 0.35)
	_target = Vector3(target_x, 0.0, target_z)


func _move_towards_target(delta: float) -> void:
	var to_target := _target - global_position
	to_target.y = 0.0
	var desired := Vector3.ZERO
	if to_target.length() > 0.18:
		desired = to_target.normalized() * minf(max_speed, to_target.length() * 4.0)
	velocity.x = move_toward(velocity.x, desired.x, max_accel * delta)
	velocity.z = move_toward(velocity.z, desired.z, max_accel * delta)
	global_position.x = clampf(global_position.x, guard_min_x - 0.6, guard_max_x)
	global_position.z = clampf(global_position.z, -guard_half_z - 0.4, guard_half_z + 0.4)


func _face_target(delta: float) -> void:
	var focus: Vector3 = ball.global_position if ball != null else (_target + Vector3.UP)
	var to_focus := focus - global_position
	to_focus.y = 0.0
	if to_focus.length_squared() < 0.0004:
		return
	var want := atan2(-to_focus.x, -to_focus.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-turn_speed * delta))


## 拦球：球以一定速度朝球门来、进入拦截面时，往场内弹回去。
func _apply_block() -> void:
	if ball == null:
		return
	if _block_ready > 0.0:
		return
	var to_ball := ball.global_position - global_position
	to_ball.y = 0.0
	var distance := to_ball.length()
	if distance > block_radius:
		return
	var incoming := Vector3.ZERO
	if ball is CharacterBody3D:
		incoming = (ball as CharacterBody3D).velocity
	if incoming.x <= 1.2:
		return
	var side := 1.0 if to_ball.z >= 0.0 else -1.0
	var away := Vector3(-1.0, 0.0, side * 0.55 + incoming.z * 0.04)
	var speed := maxf(4.2, incoming.length() * 0.55)
	ball.call("rebound", away, speed)
	_block_ready = block_cooldown
	_block_timer = 0.42
	_set_state(STATE_BLOCK)
	blocked.emit(ball.global_position, speed)


## 球被身体贴住且几乎不动时，轻轻把它推离，避免“堵死在脚下”。
func _anti_crush(delta: float) -> void:
	if ball == null:
		return
	var to_ball := ball.global_position - global_position
	to_ball.y = 0.0
	if to_ball.length() > 0.86:
		return
	if float(ball.call("speed")) > 0.8:
		return
	var push := to_ball.normalized() if to_ball.length() > 0.01 else Vector3.FORWARD
	ball.global_position += push * 1.1 * delta
	# 只轻轻推，不给速度，避免变成“自动送球”
	if ball is CharacterBody3D:
		(ball as CharacterBody3D).velocity = push * 0.35


func _stand(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, max_accel * delta)
	velocity.z = move_toward(velocity.z, 0.0, max_accel * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	_update_visual(delta)


func _update_visual(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	var moving := clampf(planar / maxf(max_speed, 0.01), 0.0, 1.0)
	var new_state := STATE_IDLE
	if _block_timer > 0.0:
		new_state = STATE_BLOCK
	elif planar > 0.25:
		new_state = STATE_TRACK
	_set_state(new_state)
	if visual == null:
		return
	var forward := -global_transform.basis.z
	var lateral := velocity.dot(global_transform.basis.x)
	visual.call("set_locomotion", moving, lateral / maxf(max_speed, 0.01))
	visual.call("set_block", clampf(_block_timer / 0.42, 0.0, 1.0))
	if ball != null and is_instance_valid(ball):
		visual.call("set_look_point", ball.global_position, true)
	_last_position = global_position


func _set_state(next: String) -> void:
	if next == state:
		return
	state = next
	state_changed.emit(state)


func debug_text() -> String:
	var planar := Vector2(velocity.x, velocity.z).length()
	return "%s · 速度 %.1f · 目标 (%.1f, %.1f)" % [state_name(), planar, _target.x, _target.z]
