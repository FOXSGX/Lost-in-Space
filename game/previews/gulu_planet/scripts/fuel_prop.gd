extends CharacterBody3D
class_name FuelProp

## 燃料罐：可被玩家拾取/携带/放下，也可被奶龙叼住；奶龙扑空时按可控方向抛出。
## 不做高速刚体碰撞——抛出后由本脚本积分速度和重力，落地即恢复为可拾取状态。

signal loaded_into_bay(fuel: FuelProp)
signal landed(fuel: FuelProp)

const GRAVITY := 18.0
const FREE_DAMPING := 6.0
const CARRY_OFFSET := Vector3(0.66, 0.80, -0.72)
const DRAGON_MOUTH_OFFSET := Vector3(0.0, -0.06, -0.10)

var display_name := "燃料罐"
var fuel_amount := 1

## free / player / dragon / thrown / loaded
var mode := "free"
var carried := false
var collected := false
## 最近一次搬运/交付的归属（现在只有单人：peer 1；保留字段方便以后算多人贡献）
var carrier: Node3D
var credit_peer := 0

var _home_position := Vector3.ZERO
var _home_yaw := 0.0
var _carry_target: Node3D
var _mouth_anchor: Node3D
var _collector: Node3D
var _settle_timer := 0.0
var _spin := 0.0
var glow_light: OmniLight3D
## 地面拾取环：只在自由状态显示（抱着它的时候不该堵住视野）。
var base_ring: MeshInstance3D


func _ready() -> void:
	_home_position = global_position
	_home_yaw = rotation.y
	collision_layer = 1
	collision_mask = 2
	floor_snap_length = 0.2
	floor_max_angle = deg_to_rad(58.0)
	set_physics_process(true)


func setup_collector(collector: Node3D) -> void:
	_collector = collector


func can_pick_up(player: CharacterBody3D, max_distance: float = 2.4) -> bool:
	if mode != "free" or player == null:
		return false
	return global_position.distance_to(player.global_position) <= max_distance


func pick_up(player: CharacterBody3D) -> void:
	if mode != "free" or player == null:
		return
	mode = "player"
	carried = true
	_carry_target = player
	carrier = player
	if glow_light != null:
		glow_light.light_energy = 0.10
	if base_ring != null:
		base_ring.visible = false
	if player.has_method("set"):
		player.set("carrying", 1)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_sync_carried(true)


func drop_from_player(player: CharacterBody3D, forward_offset: float = 1.15) -> void:
	if mode != "player":
		return
	mode = "free"
	carried = false
	_carry_target = null
	if player != null:
		player.set("carrying", 0)
		var forward := -player.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		forward = forward.normalized()
		global_position = player.global_position + forward * forward_offset
		global_position.y = player.global_position.y + 0.02
		global_rotation = Vector3(0.0, player.global_rotation.y, 0.0)
	collision_layer = 1
	collision_mask = 2
	velocity = Vector3.ZERO
	_settle_timer = 0.0
	if glow_light != null:
		glow_light.light_energy = 0.35
	if base_ring != null:
		base_ring.visible = true


func carry_by_dragon(anchor: Node3D) -> void:
	if mode == "loaded":
		return
	# 从玩家手上被抢走时，把玩家的携带标记清掉。
	if mode == "player" and _carry_target != null and is_instance_valid(_carry_target):
		_carry_target.set("carrying", 0)
		carrier = _carry_target
	mode = "dragon"
	carried = false
	_carry_target = null
	_mouth_anchor = anchor
	if glow_light != null:
		glow_light.light_energy = 0.12
	if base_ring != null:
		base_ring.visible = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	rotation.z = PI * 0.5
	_sync_carried(true)


func release_from_dragon(direction: Vector3, speed: float, lift: float) -> void:
	if mode != "dragon":
		return
	_mouth_anchor = null
	mode = "thrown"
	carried = false
	collision_layer = 1
	collision_mask = 2
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	global_rotation = Vector3(0.0, atan2(-flat.x, -flat.z), 0.0)
	velocity = flat * speed + Vector3.UP * lift
	_spin = 2.4
	_settle_timer = 0.0


func collect() -> void:
	if collected or mode == "loaded":
		return
	collected = true
	mode = "loaded"
	carried = false
	if _carry_target != null and is_instance_valid(_carry_target):
		_carry_target.set("carrying", 0)
	_carry_target = null
	credit_peer = peer_of(carrier)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	loaded_into_bay.emit(self)


func is_free() -> bool:
	return mode == "free"


## 归属标记：现在都是单人（1），以后接多人时换成真实 peer_id。
static func peer_of(actor: Node3D) -> int:
	if actor != null and is_instance_valid(actor):
		return int(actor.get("peer_id"))
	return 0


func is_available_for_dragon() -> bool:
	return mode == "free"


func reset_to_home() -> void:
	var intake_tween: Variant = get_meta("intake_tween") if has_meta("intake_tween") else null
	if intake_tween != null and intake_tween is Tween and (intake_tween as Tween).is_valid():
		(intake_tween as Tween).kill()
	set_meta("intake_tween", null)
	if _carry_target != null and is_instance_valid(_carry_target):
		_carry_target.set("carrying", 0)
	mode = "free"
	carried = false
	collected = false
	_carry_target = null
	_mouth_anchor = null
	carrier = null
	credit_peer = 0
	velocity = Vector3.ZERO
	global_position = _home_position
	global_rotation = Vector3(0.0, _home_yaw, 0.0)
	scale = Vector3.ONE
	visible = true
	if base_ring != null:
		base_ring.visible = true
	collision_layer = 1
	collision_mask = 2
	_settle_timer = 0.0
	_spin = 0.0


func _physics_process(delta: float) -> void:
	match mode:
		"player":
			_sync_carried(false)
		"dragon":
			_sync_carried(false)
		"thrown":
			_integrate_thrown(delta)
		_:
			_rest(delta)


func _sync_carried(snap: bool) -> void:
	var target: Node3D = _carry_target if mode == "player" else _mouth_anchor
	if target == null or not is_instance_valid(target):
		return
	var next_position: Vector3
	var next_rotation: Vector3
	if mode == "player":
		next_position = target.to_global(CARRY_OFFSET)
		next_rotation = Vector3(0.0, target.global_rotation.y - 0.25, 0.0)
	else:
		next_position = target.to_global(DRAGON_MOUTH_OFFSET)
		next_rotation = Vector3(0.0, target.global_rotation.y, PI * 0.5)
	if snap:
		global_position = next_position
		global_rotation = next_rotation
	else:
		global_position = global_position.lerp(next_position, 1.0 - exp(-26.0 * get_physics_process_delta_time()))
		rotation.y = lerp_angle(rotation.y, next_rotation.y, 1.0 - exp(-20.0 * get_physics_process_delta_time()))
		rotation.z = next_rotation.z
	# 自己抱着走进装货口也算装货；奶龙叼着时不自动入仓，必须靠扑击投出。
	if mode == "player":
		_try_collect()


func _integrate_thrown(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	rotation.z += _spin * delta
	var motion := velocity * delta
	var before := global_position
	move_and_slide()
	var moved := global_position.distance_to(before)
	if moved < motion.length() * 0.35 and velocity.y < 0.0:
		# 撞到斜面/墙：快速收掉水平速度，避免弹飞或卡进几何体。
		velocity.x *= 0.25
		velocity.z *= 0.25
	if is_on_floor() or global_position.y <= 0.02:
		if global_position.y < 0.02:
			global_position.y = 0.02
		velocity.x = maxf(0.0, absf(velocity.x) - FREE_DAMPING * delta) * signf(velocity.x)
		velocity.z = maxf(0.0, absf(velocity.z) - FREE_DAMPING * delta) * signf(velocity.z)
		_settle_timer += delta
		if _settle_timer > 0.22 and Vector2(velocity.x, velocity.z).length() < 0.35:
			_land()
	# 接货斜面：进了舱口范围就往中间滑，避免“差一点”变成像素级矦准。
	if global_position.x > 12.0 and global_position.x < 16.2 and absf(global_position.z) < 3.2 and global_position.y < 2.4:
		velocity.z -= signf(global_position.z) * 7.0 * delta
	_try_collect()


func _rest(delta: float) -> void:
	if mode == "loaded":
		return
	if not is_on_floor() and global_position.y > 0.03:
		velocity.y -= GRAVITY * delta
	else:
		velocity = Vector3.ZERO
		if global_position.y < 0.02:
			global_position.y = 0.02
	move_and_slide()
	_try_collect()


func _land() -> void:
	if mode != "thrown":
		return
	mode = "free"
	velocity = Vector3.ZERO
	rotation.z = 0.0
	collision_layer = 1
	collision_mask = 2
	landed.emit(self)


func _try_collect() -> void:
	if _collector == null or collected:
		return
	if _collector.call("contains_point", global_position + Vector3.UP * 0.3):
		_collector.call("consume", self)


func get_debug_text() -> String:
	return "%s · %s%s" % [display_name, mode, " · 已入仓" if collected else ""]
