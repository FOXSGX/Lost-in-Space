extends CharacterBody3D
class_name MilkDragon

## 奶龙最小互动：待机 → 注意 → 靠近 → 蓄势 → 扑击 → 恢复 → 回窝。
## 本轮不实现真实抢夺燃料、伤害、道具、结算或联网；燃料只是场景占位。
##
## 参数均为原型值，集中在本文件顶部，便于下一轮真人试玩后调整。

signal state_changed(previous: String, current: String)
signal pounce_finished(hit: bool)

const STATE_IDLE := "idle"
const STATE_NOTICE := "notice"
const STATE_APPROACH := "approach"
const STATE_WINDUP := "windup"
const STATE_POUNCE := "pounce"
const STATE_RECOVER := "recover"
const STATE_RETURN := "return"

const STATE_NAMES := {
	STATE_IDLE: "待机",
	STATE_NOTICE: "注意",
	STATE_APPROACH: "靠近",
	STATE_WINDUP: "蓄势",
	STATE_POUNCE: "扑击",
	STATE_RECOVER: "恢复",
	STATE_RETURN: "回窝",
}

# ---- 原型参数（不是最终数值） ----
@export var provoke_range := 9.0
@export var provoke_half_angle_deg := 55.0
@export var provoke_cooldown := 0.7
@export var agitation_per_provoke := 0.34
@export var windup_threshold := 0.95
@export var agitation_decay := 0.10
@export var notice_time := 0.55
@export var approach_speed := 2.6
@export var approach_stop_distance := 2.4
@export var give_up_distance := 13.0
@export var interest_timeout := 9.0
@export var windup_time := 1.0
@export var pounce_speed := 11.0
@export var pounce_time := 0.42
@export var pounce_hit_radius := 1.25
@export var recover_time := 1.5
@export var return_speed := 2.2
@export var turn_speed := 10.0
@export var gravity := 18.0

var player: CharacterBody3D
var visual: Node3D
var state := STATE_IDLE
var agitation := 0.0
var last_pounce_hit := false
var home_position := Vector3.ZERO
var home_yaw := 0.0

var _timer := 0.0
var _interest_timer := 0.0
var _last_provoke_ms := -100000
var _pending_windup := false
var _pounce_target := Vector3.ZERO
var _lost_los_time := 0.0
var _los_check_accum := 0.0
var _last_los := true
var _player_inside := false


func _ready() -> void:
	collision_layer = 16
	collision_mask = 2 | 4 | 16
	floor_snap_length = 0.3
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.48
	capsule.height = 1.6
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.80
	add_child(shape)
	home_position = global_position
	home_yaw = rotation.y
	visual = get_node_or_null("Visual") as Node3D
	_set_state(STATE_IDLE, true)


func setup_player(next_player: CharacterBody3D) -> void:
	player = next_player


func _physics_process(delta: float) -> void:
	if player == null:
		_update_visual()
		return

	var distance := global_position.distance_to(player.global_position)
	_los_check_accum += delta
	if _los_check_accum >= 0.12:
		_los_check_accum = 0.0
		_last_los = _has_line_of_sight()

	match state:
		STATE_IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			_decay_agitation(delta)
		STATE_NOTICE:
			velocity.x = 0.0
			velocity.z = 0.0
			_face_point(player.global_position, delta)
			_timer += delta
			if _timer >= notice_time:
				if _pending_windup or agitation >= windup_threshold:
					_begin_windup()
				else:
					_set_state(STATE_APPROACH)
		STATE_APPROACH:
			_interest_timer += delta
			if not _last_los or distance > give_up_distance:
				_start_return()
			elif _interest_timer > interest_timeout:
				_start_return()
			else:
				_face_point(player.global_position, delta)
				if distance > approach_stop_distance:
					var dir := _flat_direction(player.global_position)
					velocity.x = dir.x * approach_speed
					velocity.z = dir.z * approach_speed
				else:
					velocity.x = 0.0
					velocity.z = 0.0
				_decay_agitation(delta)
				if agitation >= windup_threshold:
					_begin_windup()
		STATE_WINDUP:
			velocity.x = 0.0
			velocity.z = 0.0
			_face_point(player.global_position, delta * 0.55)
			_timer += delta
			if _timer >= windup_time:
				if not _last_los:
					_start_return()
				else:
					_pounce_target = player.global_position
					_timer = 0.0
					_set_state(STATE_POUNCE)
		STATE_POUNCE:
			_timer += delta
			var to_target := _pounce_target - global_position
			to_target.y = 0.0
			if to_target.length() > 0.12:
				var dir := to_target.normalized()
				velocity.x = dir.x * pounce_speed
				velocity.z = dir.z * pounce_speed
				_face_point(_pounce_target, delta * 1.6)
			else:
				velocity.x = 0.0
				velocity.z = 0.0
			if _timer >= pounce_time:
				_finish_pounce()
		STATE_RECOVER:
			velocity.x = 0.0
			velocity.z = 0.0
			_timer += delta
			if _timer >= recover_time:
				agitation = 0.0
				_pending_windup = false
				_set_state(STATE_IDLE)
		STATE_RETURN:
			_face_point(home_position, delta)
			var to_home := home_position - global_position
			to_home.y = 0.0
			if to_home.length() <= 0.25:
				velocity.x = 0.0
				velocity.z = 0.0
				agitation = 0.0
				_set_state(STATE_IDLE)
			else:
				var dir := to_home.normalized()
				velocity.x = dir.x * return_speed
				velocity.z = dir.z * return_speed

	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()

	# 扑击撞到墙或玩家就提前结束，绝不穿过碰撞体。
	if state == STATE_POUNCE and get_slide_collision_count() > 0:
		_finish_pounce()

	_update_visual()


func try_provoke(current_player: CharacterBody3D) -> Dictionary:
	player = current_player
	if state in [STATE_WINDUP, STATE_POUNCE, STATE_RECOVER]:
		return {"ok": false, "reason": "它现在顾不上你"}
	var distance := global_position.distance_to(player.global_position)
	if distance > provoke_range:
		return {"ok": false, "reason": "太远了（挑衅范围 %.1f m）" % provoke_range}
	if not _has_line_of_sight():
		return {"ok": false, "reason": "被墙挡住了"}
	if not _player_is_facing_me():
		return {"ok": false, "reason": "先面向奶龙再挑衅"}
	var now := Time.get_ticks_msec()
	if now - _last_provoke_ms < int(provoke_cooldown * 1000.0):
		return {"ok": false, "reason": "别按太快，它还没反应"}
	_last_provoke_ms = now
	_interest_timer = 0.0
	_lost_los_time = 0.0
	agitation = minf(1.0, agitation + agitation_per_provoke)
	if state == STATE_IDLE or state == STATE_RETURN:
		_pending_windup = false
		_timer = 0.0
		_set_state(STATE_NOTICE)
	elif state == STATE_APPROACH or state == STATE_NOTICE:
		pass
	if agitation >= windup_threshold:
		if state == STATE_APPROACH:
			_begin_windup()
		elif state == STATE_NOTICE:
			_pending_windup = true
	return {"ok": true, "reason": "挑衅成功"}


func _begin_windup() -> void:
	if state == STATE_WINDUP:
		return
	_pending_windup = false
	_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_set_state(STATE_WINDUP)


func _finish_pounce() -> void:
	if state != STATE_POUNCE:
		return
	var distance := global_position.distance_to(player.global_position) if player != null else 999.0
	last_pounce_hit = distance <= pounce_hit_radius
	_timer = 0.0
	velocity = Vector3.ZERO
	_set_state(STATE_RECOVER)
	pounce_finished.emit(last_pounce_hit)


func _start_return() -> void:
	_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_set_state(STATE_RETURN)


func _decay_agitation(delta: float) -> void:
	if Time.get_ticks_msec() - _last_provoke_ms > 1200:
		agitation = maxf(0.0, agitation - agitation_decay * delta)


func _flat_direction(target: Vector3) -> Vector3:
	var direction := target - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	return direction.normalized()


func _face_point(target: Vector3, delta: float) -> void:
	var direction := target - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var desired_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, 1.0 - exp(-turn_speed * delta))


func _has_line_of_sight() -> bool:
	if player == null:
		return false
	var from := global_position + Vector3.UP * 1.15
	var to := player.global_position + Vector3.UP * 1.15
	var query := PhysicsRayQueryParameters3D.create(from, to, 2, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _player_is_facing_me() -> bool:
	var camera := player.get("camera") as Camera3D
	if camera == null:
		return false
	var forward := -camera.global_transform.basis.z
	var to_me := (global_position + Vector3.UP * 1.15) - camera.global_position
	to_me.y = 0.0
	if to_me.length_squared() < 0.0001:
		return true
	return forward.dot(to_me.normalized()) >= cos(deg_to_rad(provoke_half_angle_deg))


func _set_state(next_state: String, force: bool = false) -> void:
	if state == next_state and not force:
		return
	var previous := state
	state = next_state
	_timer = 0.0
	state_changed.emit(previous, next_state)
	_update_visual()


func _update_visual() -> void:
	if visual == null:
		return
	var windup_ratio := 0.0
	var pounce_ratio := 0.0
	if state == STATE_WINDUP:
		windup_ratio = clampf(_timer / maxf(windup_time, 0.01), 0.0, 1.0)
	elif state == STATE_POUNCE:
		pounce_ratio = clampf(_timer / maxf(pounce_time, 0.01), 0.0, 1.0)
	visual.call("set_behavior", state_name(), agitation, windup_ratio, pounce_ratio)


func state_name() -> String:
	return STATE_NAMES.get(state, state)


func focus_name() -> String:
	return "玩家" if player != null else "无"


func debug_text() -> String:
	var distance := global_position.distance_to(player.global_position) if player != null else -1.0
	return "奶龙 %s · 关注 %s · 上头 %d%% · 距离 %.1f m · 扑击 %s" % [
		state_name(),
		focus_name(),
		int(round(agitation * 100.0)),
		distance,
		"命中" if last_pounce_hit else "未命中",
	]


func reset_to_home() -> void:
	global_position = home_position
	rotation.y = home_yaw
	velocity = Vector3.ZERO
	agitation = 0.0
	_last_provoke_ms = -100000
	_pending_windup = false
	last_pounce_hit = false
	_interest_timer = 0.0
	_timer = 0.0
	_lost_los_time = 0.0
	state = STATE_RETURN
	_set_state(STATE_IDLE, true)
