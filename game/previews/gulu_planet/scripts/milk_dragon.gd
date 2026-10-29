extends CharacterBody3D
class_name MilkDragon

## 奶龙行为：待机 → 找燃料 → 叼起 → 注意到你 → 靠近 → 蓄势 → 扑击 → 恢复。
## 它不会主动帮玩家：只会抢燃料、被挑衅、朝你扑。玩家利用它的扑击把燃料送进装货口。
##
## 参数均为原型值，集中在本文件顶部，便于真人试玩后调整。

signal state_changed(previous: String, current: String)
signal pounce_finished(hit: bool)
signal fuel_grabbed(fuel: Node3D)
signal fuel_released(fuel: Node3D)

const STATE_IDLE := "idle"
const STATE_FORAGE := "forage"
const STATE_NOTICE := "notice"
const STATE_APPROACH := "approach"
const STATE_WINDUP := "windup"
const STATE_POUNCE := "pounce"
const STATE_RECOVER := "recover"
const STATE_RETURN := "return"

const STATE_NAMES := {
	STATE_IDLE: "待机",
	STATE_FORAGE: "找燃料",
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
@export var agitation_per_provoke_holding := 0.42
@export var windup_threshold := 0.95
@export var agitation_decay := 0.10
@export var notice_time := 0.55
@export var approach_speed := 2.7
@export var approach_stop_distance := 2.3
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
## 找燃料
@export var forage_range := 8.0
@export var forage_speed := 2.4
@export var grab_radius := 1.15
@export var grab_cooldown := 2.4
## 叼货扑空后燃料的抛出速度（可控，不依赖高速物理碰撞）
@export var release_speed := 7.2
@export var release_lift := 3.4

var player: CharacterBody3D
var visual: Node3D
var state := STATE_IDLE
var agitation := 0.0
var last_pounce_hit := false
var has_fuel := false
var carried_fuel: Node3D
var home_position := Vector3.ZERO
var home_yaw := 0.0

var _fuels: Array = []
var _forage_target: Node3D
var _timer := 0.0
var _interest_timer := 0.0
var _last_provoke_ms := -100000
var _pending_windup := false
var _pounce_target := Vector3.ZERO
var _los_check_accum := 0.0
var _last_los := true
var _grab_cooldown := 0.0
var _stuck_accum := 0.0
var _sidestep_timer := 0.0
var _sidestep_dir := 1.0
var _stuck_total := 0.0
var _last_position := Vector3.ZERO


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
	_last_position = global_position
	visual = get_node_or_null("Visual") as Node3D
	_set_state(STATE_IDLE, true)


func setup_player(next_player: CharacterBody3D) -> void:
	player = next_player
	if visual != null:
		visual.call("set_look_target", player)


func setup_fuels(fuels: Array) -> void:
	_fuels = fuels


func mouth_anchor() -> Node3D:
	if visual != null and visual.has_method("mouth_anchor"):
		return visual.call("mouth_anchor") as Node3D
	return null


## 让奶龙一开始就叼着一罐燃料：开场就能看到“它嘴里的就是你的货”。
func start_holding(fuel: Node3D) -> void:
	if fuel == null or has_fuel:
		return
	carried_fuel = fuel
	has_fuel = true
	fuel.call("carry_by_dragon", mouth_anchor())
	if visual != null:
		visual.call("set_carried_state", true)


func _physics_process(delta: float) -> void:
	_grab_cooldown = maxf(0.0, _grab_cooldown - delta)
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
			if not has_fuel and _grab_cooldown <= 0.0:
				var candidate := _nearest_fuel()
				if candidate != null:
					_forage_target = candidate
					_set_state(STATE_FORAGE)
		STATE_FORAGE:
			_forage_tick(delta)
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
					_move_flat(_flat_direction(player.global_position) * approach_speed)
				else:
					velocity.x = 0.0
					velocity.z = 0.0
				_decay_agitation(delta)
				if agitation >= windup_threshold:
					_begin_windup()
		STATE_WINDUP:
			velocity.x = 0.0
			velocity.z = 0.0
			_face_point(_pounce_target, delta * 1.4)
			_timer += delta
			if _timer >= windup_time:
				if not _last_los:
					_start_return()
				else:
					_timer = 0.0
					_set_state(STATE_POUNCE)
		STATE_POUNCE:
			_timer += delta
			var to_target := _pounce_target - global_position
			to_target.y = 0.0
			if to_target.length() > 0.12:
				_move_flat(to_target.normalized() * pounce_speed)
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
				_move_flat(to_home.normalized() * return_speed)

	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()

	# 扑击只被墙/玩家等非地面碰撞提前结束；地板接触不算撞墙。
	if state == STATE_POUNCE:
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			if collision.get_normal().y < 0.7:
				_finish_pounce()
				break

	_update_stuck(delta)
	_update_visual()


func _forage_tick(delta: float) -> void:
	if _forage_target == null or not is_instance_valid(_forage_target) or not bool(_forage_target.call("is_available_for_dragon")):
		_set_state(STATE_IDLE)
		return
	var target_position := _forage_target.global_position
	var distance := global_position.distance_to(target_position)
	_face_point(target_position, delta)
	if distance <= grab_radius:
		_grab(_forage_target)
		return
	if distance > forage_range * 1.6:
		_set_state(STATE_IDLE)
		return
	_move_flat(_flat_direction(target_position) * forage_speed)


func _grab(fuel: Node3D) -> void:
	if has_fuel or fuel == null or not is_instance_valid(fuel):
		_set_state(STATE_IDLE)
		return
	carried_fuel = fuel
	has_fuel = true
	fuel.call("carry_by_dragon", mouth_anchor())
	if visual != null:
		visual.call("set_carried_state", true)
	fuel_grabbed.emit(fuel)
	_set_state(STATE_IDLE)


func _nearest_fuel() -> Node3D:
	var best: Node3D = null
	var best_distance := forage_range
	for entry in _fuels:
		var fuel := entry as Node3D
		if fuel == null or not is_instance_valid(fuel):
			continue
		if not bool(fuel.call("is_available_for_dragon")):
			continue
		# 不去装货口附近捡：避免它把已经送到门口的东西又叼走。
		if fuel.global_position.x > 10.8:
			continue
		var distance := global_position.distance_to(fuel.global_position)
		if distance >= best_distance:
			continue
		if not _has_los_to(fuel.global_position + Vector3.UP * 0.4):
			continue
		best = fuel
		best_distance = distance
	return best


func _update_stuck(delta: float) -> void:
	var wants_move := (state == STATE_FORAGE or state == STATE_APPROACH or state == STATE_RETURN) and Vector2(velocity.x, velocity.z).length() > 0.2
	if not wants_move:
		_stuck_accum = 0.0
		_stuck_total = 0.0
		_last_position = global_position
		return
	# 玩家站在装货口里时它本来就靠不近，不算卡住。
	if state == STATE_APPROACH and player != null and global_position.distance_to(player.global_position) <= approach_stop_distance + 1.5:
		_stuck_accum = 0.0
		_stuck_total = 0.0
		_last_position = global_position
		return
	var moved := global_position.distance_to(_last_position)
	_last_position = global_position
	if moved < 0.02:
		_stuck_accum += delta
		_stuck_total += delta
	else:
		_stuck_accum = maxf(0.0, _stuck_accum - delta * 0.5)
		_stuck_total = 0.0
	if _stuck_accum > 0.7 and _sidestep_timer <= 0.0:
		# 侧移绕开障碍，而不是原地顶着墙。
		_sidestep_timer = 0.45
		_sidestep_dir = -_sidestep_dir
		_stuck_accum = 0.0
	if _sidestep_timer > 0.0:
		_sidestep_timer -= delta
		var right := global_transform.basis.x * _sidestep_dir
		global_position += Vector3(right.x, 0.0, right.z) * 1.4 * delta
	if _stuck_total > 3.2:
		# 最后兜底：回到出生点，避免永久卡死。
		_stuck_total = 0.0
		_stuck_accum = 0.0
		global_position = home_position
		velocity = Vector3.ZERO
		_set_state(STATE_IDLE)


func try_provoke(current_player: CharacterBody3D) -> Dictionary:
	player = current_player
	if state in [STATE_WINDUP, STATE_POUNCE, STATE_RECOVER]:
		return {"ok": false, "reason": "它现在顾不上你"}
	var distance := global_position.distance_to(player.global_position)
	if distance > provoke_range:
		return {"ok": false, "reason": "太远了（挑衅范围 %.1f m）" % provoke_range}
	if not _has_line_of_sight():
		return {"ok": false, "reason": "被挡住了，它看不见你"}
	if not _player_is_facing_me():
		return {"ok": false, "reason": "先面向奶龙再挑衅"}
	var now := Time.get_ticks_msec()
	if now - _last_provoke_ms < int(provoke_cooldown * 1000.0):
		return {"ok": false, "reason": "别按太快，它还没反应过来"}
	_last_provoke_ms = now
	_interest_timer = 0.0
	var gain := agitation_per_provoke_holding if has_fuel else agitation_per_provoke
	agitation = minf(1.0, agitation + gain)
	if state == STATE_IDLE or state == STATE_RETURN or state == STATE_FORAGE:
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
	return {"ok": true, "reason": "挑衅成功", "holding_fuel": has_fuel}


func _begin_windup() -> void:
	if state == STATE_WINDUP:
		return
	_pending_windup = false
	_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	# 目标在预兆开始时锁定：之后的侧移能真的躲开，也不会追尾转向。
	if player != null:
		_pounce_target = player.global_position
	_set_state(STATE_WINDUP)


func _finish_pounce() -> void:
	if state != STATE_POUNCE:
		return
	var distance := global_position.distance_to(player.global_position) if player != null else 999.0
	last_pounce_hit = distance <= pounce_hit_radius
	_timer = 0.0
	velocity = Vector3.ZERO
	if has_fuel:
		_release_fuel()
	if visual != null:
		visual.call("set_pounce_result", last_pounce_hit)
	_set_state(STATE_RECOVER)
	pounce_finished.emit(last_pounce_hit)


func _release_fuel() -> void:
	if not has_fuel or carried_fuel == null or not is_instance_valid(carried_fuel):
		has_fuel = false
		carried_fuel = null
		return
	var fuel := carried_fuel
	has_fuel = false
	carried_fuel = null
	if visual != null:
		visual.call("set_carried_state", false)
	var forward := -global_transform.basis.z
	fuel.call("release_from_dragon", forward, release_speed, release_lift)
	_grab_cooldown = grab_cooldown
	fuel_released.emit(fuel)


func _start_return() -> void:
	_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_set_state(STATE_RETURN)


func _decay_agitation(delta: float) -> void:
	if Time.get_ticks_msec() - _last_provoke_ms > 1200:
		agitation = maxf(0.0, agitation - agitation_decay * delta)


func _move_flat(motion: Vector3) -> void:
	velocity.x = motion.x
	velocity.z = motion.z


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


func _has_los_to(point: Vector3) -> bool:
	var from := global_position + Vector3.UP * 1.15
	var query := PhysicsRayQueryParameters3D.create(from, point, 2, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _has_line_of_sight() -> bool:
	if player == null:
		return false
	return _has_los_to(player.global_position + Vector3.UP * 1.15)


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


func set_debug_ring(enabled: bool) -> void:
	if visual != null:
		visual.set("ring_enabled", enabled)


func state_name() -> String:
	return STATE_NAMES.get(state, state)


func focus_name() -> String:
	if has_fuel:
		return "嘴里的燃料"
	return "玩家" if player != null else "无"


func debug_text() -> String:
	var distance := global_position.distance_to(player.global_position) if player != null else -1.0
	return "奶龙 %s · 关注 %s · 上头 %d%% · 距离 %.1f m · %s · 扑击 %s" % [
		state_name(),
		focus_name(),
		int(round(agitation * 100.0)),
		distance,
		"叼着货" if has_fuel else "空嘴",
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
	_grab_cooldown = 0.0
	_stuck_accum = 0.0
	_stuck_total = 0.0
	_sidestep_timer = 0.0
	_forage_target = null
	has_fuel = false
	carried_fuel = null
	if visual != null:
		visual.call("set_carried_state", false)
	state = STATE_RETURN
	_set_state(STATE_IDLE, true)
