extends CharacterBody3D
class_name MilkDragonKeeper

## 奶龙的唯一职责：拦球。
##
## 四个状态（就这四个）：
##   观察与站位 → 接近/拦截 → 扑空恢复 → 回防
##
## 能力是有限的：
##   - 只根据“延迟采样的球位置 + 球速”估计拦截点，不读取玩家输入、不预知、不瞬移；
##   - 有反应延迟、加速度上限、最高速度、转向角速度上限；
##   - 只有「球朝球门来 + 预计到达时间够短 + 落点在门洞附近」才出击，
##     朝远处滚的高球不会触发无意义扑救；
##   - 出击后目标锁定一小段时间（不能立刻改向），所以玩家打反方向能过；
##   - 同一次出击只拨球一次（独立冷却），不会贴着球连击。
##
## 碰撞：球是 RigidBody3D，身体接触由物理引擎统一处理；本文件只额外施加
## 「一次受限冲量」的主动拨球，绝不重复反射速度。

signal blocked(point: Vector3, speed: float)
signal state_changed(current: String)
## 真实事件：只在实际拦下/未命中/进球时发，不由距离或动画自行推断。
signal save_made
signal intercept_missed
signal goal_conceded

const STATE_OBSERVE := "观察"
const STATE_INTERCEPT := "拦截"
const STATE_RECOVER := "恢复"
const STATE_RETURN := "回防"

@export var home := Vector3(10.2, 0.0, 0.0)
## 站位区：门前一块矩形，不是一条线
@export var zone_min_x := 8.4
@export var zone_max_x := 11.4
@export var zone_half_z := 3.2
@export var walk_speed := 1.6
@export var charge_speed := 2.4
@export var max_accel := 16.0
## 真正的角速度上限（rad/s），按 delta 积分，不是“每秒 lerp 系数”
@export var max_turn_rate := 5.0
@export var react_delay := 0.24
@export var intercept_time := 0.50
@export var recover_time := 0.7
@export var intercept_cooldown := 2.2
@export var swat_range := 1.20
@export var swat_cooldown := 0.8
@export var swat_impulse := 5.4
## 碰撞帧不再额外拨球，避免双重冲量
@export var swat_guard := true
@export var gravity := 18.0

var ball: RigidBody3D
var goal: Node3D
## 玩家引用只用于“读站位”（可观察信息），不读任何输入状态。
var player: Node3D
var state := STATE_OBSERVE
var visual: Node3D

var _goal_x := 12.45
var _sample := Vector3.ZERO
var _sample_vel := Vector3.ZERO
var _think := 0.0
var _state_timer := 0.0
var _cooldown := 0.0
var _swat_ready := 0.0
var _intercept_hit := false
var _save_pending := false
var _save_timer := 0.0
var _target := Vector3.ZERO
var _time := 0.0
## --- 预判/假动作 ---
## 玩家在球哪一侧：-1 / +1 / 0。只用于“站在那里读站位”，不读输入。
var _precommit_side := 0.0
var _anticipate_timer := 0.0
var _look_player_timer := 0.0
var _look_player_delay := 0.0
var _tell_side := 0.0
const ANTICIPATE_TIME := 0.40
const TELL_RANGE := 2.9
const TELL_LEAN := 0.42


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
	_set_state(STATE_OBSERVE)


func setup_ball(next_ball: RigidBody3D) -> void:
	ball = next_ball


## 只保存引用：用来判断玩家站在球的哪边（可观察信息）。
func setup_player(node: Node3D) -> void:
	player = node


func setup_goal(next_goal: Node3D) -> void:
	goal = next_goal
	if goal != null and goal.has_method("goal_plane_x"):
		_goal_x = float(goal.call("goal_plane_x"))
	if goal != null and goal.has_signal("fuel_collected"):
		goal.connect("fuel_collected", _on_goal_conceded)


func _on_goal_conceded(_total: int, _target: int) -> void:
	_save_pending = false
	_intercept_hit = true
	goal_conceded.emit()
	if visual != null:
		visual.call("play_goal")


func state_name() -> String:
	return state


func reset_to_home() -> void:
	global_position = home
	velocity = Vector3.ZERO
	rotation.y = PI * 0.5
	_state_timer = 0.0
	_cooldown = 0.0
	_swat_ready = 0.0
	_think = 0.0
	_intercept_hit = false
	_target = home
	if visual != null:
		visual.call("set_locomotion", 0.0, 0.0)
		visual.call("set_block", 0.0)
	_set_state(STATE_OBSERVE)


func _physics_process(delta: float) -> void:
	_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_swat_ready = maxf(0.0, _swat_ready - delta)
	if _save_pending:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_pending = false
			var conceded := false
			if goal != null and goal.has_method("loaded_count"):
				conceded = int(goal.get("loaded_count")) > 0
			if not conceded and ball != null and ball.global_position.x < _goal_x - 0.05:
				_intercept_hit = true
				save_made.emit()
				blocked.emit(ball.global_position, ball.linear_velocity.length())
				if visual != null:
					visual.call("play_save")

	if ball == null or not is_instance_valid(ball):
		_brake(delta)
		_apply_to_body(delta)
		return

	# 延迟采样：每隔 react_delay 才“看一眼”球在哪，模拟反应时间
	_think += delta
	if _think >= react_delay:
		_think = 0.0
		_sample = ball.global_position
		_sample_vel = ball.linear_velocity

	match state:
		STATE_OBSERVE:
			_state_timer += delta
			_update_anticipation(delta)
			_target = _stand_point() + Vector3(0.0, 0.0, 0.42 * _precommit_side)
			_face_point(_sample, delta)
			if _should_intercept() and _state_timer > 0.15:
				_begin_intercept()
		STATE_INTERCEPT:
			_state_timer += delta
			# 目标在出击瞬间就锁死；这段时间只朝那个点冲，不修正
			if _state_timer >= intercept_time:
				if not _intercept_hit and not _save_pending:
					intercept_missed.emit()
					if visual != null:
						visual.call("play_whiff")
					# 先看滚走的球，再看玩家
					_look_player_delay = 0.35
					_look_player_timer = 0.60
				_set_state(STATE_RECOVER)
		STATE_RECOVER:
			_state_timer += delta
			velocity.x = move_toward(velocity.x, 0.0, max_accel * delta)
			velocity.z = move_toward(velocity.z, 0.0, max_accel * delta)
			# 扑空后：先看滚走的球，再看一眼玩家（“你骗到我了”）。
			if _look_player_delay > 0.0:
				_look_player_delay -= delta
				if visual != null:
					visual.call("set_look_point", _sample, true)
			elif _look_player_timer > 0.0:
				_look_player_timer -= delta
				if visual != null and player != null and is_instance_valid(player):
					visual.call("set_look_target", player)
			else:
				_face_point(_sample, delta)
			if _state_timer >= recover_time:
				_look_player_timer = 0.0
				_set_state(STATE_RETURN)
		STATE_RETURN:
			_state_timer += delta
			_target = home
			_face_point(home, delta)
			if global_position.distance_to(home) < 0.4:
				_set_state(STATE_OBSERVE)

	_apply_to_body(delta)
	_try_swat()


## 站位：球远时守中路，球近了才向近角偏移；始终在门线前一点（x≈11.1）。
## 这样远射的远角是真空当，近射才会被它封住。
func _stand_point() -> Vector3:
	var closeness := clampf((_sample.x - 9.0) / 3.0, 0.0, 1.0)
	var near_side := clampf(_sample.z * 0.9, -2.6, 2.6) * closeness
	return Vector3(11.1, 0.0, near_side)


## 读“玩家站在球的哪一边”——只读位置，不读输入；玩家绕到另一边就能骗它。
func _read_player_side() -> float:
	if player == null or not is_instance_valid(player) or ball == null:
		return 0.0
	var approach := ball.global_position - player.global_position
	approach.y = 0.0
	var distance := approach.length()
	if distance > TELL_RANGE or distance < 0.2:
		return 0.0
	var to_goal := Vector3(_goal_x - ball.global_position.x, 0.0, -ball.global_position.z)
	if to_goal.length_squared() < 0.01:
		return 0.0
	to_goal = to_goal.normalized()
	# 玩家要大致处在“球和门之间”才当成准备射门
	if approach.normalized().dot(to_goal) < 0.25:
		return 0.0
	return signf(player.global_position.z - ball.global_position.z)


## 预判：站位稳定 0.4 s 才锁定；换边会重新计时，所以绕到另一边就是假动作。
func _update_anticipation(delta: float) -> void:
	var side := _read_player_side()
	if side == 0.0:
		_tell_side = 0.0
		_anticipate_timer = 0.0
		_precommit_side = 0.0
		if visual != null:
			visual.call("set_anticipation", 0.0, 0.0)
		return
	if side != _tell_side:
		_tell_side = side
		_anticipate_timer = 0.0
		_precommit_side = 0.0
	_anticipate_timer += delta
	if _anticipate_timer >= ANTICIPATE_TIME:
		_precommit_side = side
	if visual != null:
		visual.call("set_anticipation", side,
			clampf(_anticipate_timer / ANTICIPATE_TIME, 0.0, 1.0))


## 只有“球朝球门来 + 预计到达够快 + 落点在门洞附近”才出击。
func _should_intercept() -> bool:
	if _cooldown > 0.0:
		return false
	if _sample.x < 2.0:
		return false
	var vx := _sample_vel.x
	if vx <= 2.0:
		return false
	var distance := maxf(_goal_x - _sample.x, 0.2)
	var eta := distance / vx
	if eta > 1.5:
		return false
	var predicted_z := _sample.z + _sample_vel.z * eta
	if absf(predicted_z) > 3.4:
		return false
	# 还要判断它是不是真的朝门里来（而不是从门前横穿出去）
	var dir := _sample_vel.normalized()
	var to_goal := Vector3(_goal_x - _sample.x, 0.0, -_sample.z).normalized()
	if dir.dot(to_goal) < 0.35:
		return false
	return true


func _begin_intercept() -> void:
	var vx := maxf(_sample_vel.x, 0.5)
	var eta := clampf((_goal_x - _sample.x) / vx, 0.0, 0.45)
	var aim_z := clampf(_sample.z + _sample_vel.z * eta, -zone_half_z - 0.3, zone_half_z + 0.3)
	# 预判锁错：它按“玩家站位”先入为主，真球射向另一边时就会扑错。
	if _precommit_side != 0.0 and signf(aim_z) != _precommit_side:
		if visual != null:
			visual.call("play_whiff")
		aim_z = _precommit_side * (zone_half_z + 0.25)
	_target = Vector3(
		clampf(_sample.x + _sample_vel.x * eta, zone_min_x - 0.4, zone_max_x),
		0.0,
		aim_z
	)
	_state_timer = 0.0
	_cooldown = intercept_cooldown
	_intercept_hit = false
	_precommit_side = 0.0
	_tell_side = 0.0
	_anticipate_timer = 0.0
	_set_state(STATE_INTERCEPT)


func _apply_to_body(delta: float) -> void:
	var speed_cap := charge_speed if state == STATE_INTERCEPT else walk_speed
	var to_target := _target - global_position
	to_target.y = 0.0
	var desired := Vector3.ZERO
	if to_target.length() > 0.12 and state != STATE_RECOVER:
		desired = to_target.normalized() * minf(speed_cap, to_target.length() * 5.0)
	velocity.x = move_toward(velocity.x, desired.x, max_accel * delta)
	velocity.z = move_toward(velocity.z, desired.z, max_accel * delta)
	# 站位区约束（只是在门口一带活动，不会跑到场地另一头）
	global_position.x = clampf(global_position.x, zone_min_x - 0.8, zone_max_x)
	global_position.z = clampf(global_position.z, -zone_half_z - 0.6, zone_half_z + 0.6)

	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()

	_update_visual(delta)


func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, max_accel * delta)
	velocity.z = move_toward(velocity.z, 0.0, max_accel * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta


## 真正的角速度上限：每帧最多转 max_turn_rate * delta。
func _face_point(point: Vector3, delta: float) -> void:
	var to_point := point - global_position
	to_point.y = 0.0
	if to_point.length_squared() < 0.0004:
		return
	var want := atan2(-to_point.x, -to_point.z)
	var diff := wrapf(want - rotation.y, -PI, PI)
	var max_step := max_turn_rate * delta
	rotation.y += clampf(diff, -max_step, max_step)


## 主动拨球：独立触发 + 独立冷却；同一次接触只施加一次冲量。
func _try_swat() -> void:
	if state != STATE_INTERCEPT or _swat_ready > 0.0:
		return
	# 如果这一帧身体已经和球发生物理碰撞，就交给物理反弹；
	# 不再额外加拨球冲量，避免“先弹一次、再被推一次”。
	var to_ball := ball.global_position - global_position
	to_ball.y = 0.0
	# 身体接触已经由物理引擎反弹；这里只负责“拦下”的反馈，不再加冲量。
	if to_ball.length() <= 1.05:
		if not _intercept_hit and not _save_pending:
			_save_pending = true
			_save_timer = 0.22
		return
	# 不再额外施加拨球冲量：直接碰撞由物理引擎负责反弹，
	# 近距离只发“拦下”反馈，避免同一次接触被推两次。
	return


func _update_visual(_delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	var moving := clampf(planar / maxf(charge_speed, 0.01), 0.0, 1.0)
	# 本地坐标下的前进/横移：侧移时不要播“向前大步走”
	var forward_amount := velocity.dot(-global_transform.basis.z)
	var lateral_amount := velocity.dot(global_transform.basis.x)
	var max_speed := maxf(charge_speed, 0.01)
	var block := clampf(1.0 - _swat_ready / maxf(swat_cooldown, 0.01), 0.0, 1.0)
	if visual == null:
		return
	visual.call("set_locomotion", moving, clampf(lateral_amount / max_speed, -1.0, 1.0))
	visual.call("set_stride", clampf(forward_amount / max_speed, -1.0, 1.0), planar)
	visual.call("set_block", block if _swat_ready > 0.0 else 0.0)
	visual.call("set_ready", 1.0 if state == STATE_INTERCEPT else 0.0)
	visual.call("set_look_point", ball.global_position, true)
	if state != STATE_OBSERVE:
		visual.call("set_anticipation", 0.0, 0.0)


func _set_state(next: String) -> void:
	if next == state:
		return
	state = next
	_state_timer = 0.0
	state_changed.emit(state)


func debug_text() -> String:
	var planar := Vector2(velocity.x, velocity.z).length()
	return "%s · %.1f m/s · 目标 (%.1f, %.1f)" % [state, planar, _target.x, _target.z]







