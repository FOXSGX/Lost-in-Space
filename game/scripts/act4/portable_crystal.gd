class_name PortableCrystal
extends RigidBody3D
## A real physics body the player can pick up, carry, rotate and drop.
##
## While carried it is frozen and follows the player's hold point, but its yaw
## stays absolute: the player rotates it with Q. When dropped it becomes a
## normal rigid body again and may settle into a nearby cradle. A bad yaw does
## not destroy anything: the crystal still seats, leans, and can be picked up
## and corrected.

signal seated_in_cradle(crystal: PortableCrystal, cradle: ResonanceCradle, aligned: bool)
signal dropped(crystal: PortableCrystal)

const CARRY_LERP := 16.0
const SNAP_RADIUS := 1.45

var crystal_id: String = ""
var display_name: String = ""
var palette: String = "cyan"
var visual: CrystalVisual
var is_carried: bool = false
var is_seated: bool = false
var cradle: ResonanceCradle = null
## Set while the crystal is the cargo of the suspended freight platform. The
## platform owns its transform; keeping this as Node avoids a class cycle.
var freight: Node = null
## Co-op clients mirror the host's seating decision; a client must not seat the
## crystal locally from its own physics tick.
var network_seat_lock: bool = false
var held_yaw_deg: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO
var spawn_yaw_deg: float = 0.0
var focus_beam_visible: bool = true

var _hold_target: Node3D = null
var _carry_sway: float = 0.0
var _carry_clock: float = 0.0
var _snap_delay: float = 0.0
## `try_seat()` 会做两次全树组查询（freight_bay + cradle）并分配数组。
## 挂在物理帧上无条件调用等于每颗未落座晶体 120 次/秒的扫描；降到 5 Hz
## 对“晶体落进叉口”这种 0.2 s 级的事件完全够用。
var _seat_scan: float = 0.0
var _base_visual_rotation: Vector3 = Vector3.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func build(id_value: String, asset_path: String, palette_value: String, scale_factor: float = 0.86) -> bool:
	crystal_id = id_value
	palette = palette_value
	display_name = "共振晶体"
	mass = 16.0
	gravity_scale = 1.0
	linear_damp = 0.6
	angular_damp = 4.0
	continuous_cd = true
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	add_to_group("portable_crystal")
	_rng.randomize()

	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "CrystalShape"
	# MECHANICS-004B：晶体碰撞体由胶囊改为圆柱。
	#
	# 胶囊的底端是半径 0.34 的半球：它站在甲板上时与甲板只有一个接触点，
	# 平台一加速，接触力就产生力矩，晶体像球一样滚倒（实测 up_y 从 1.00
	# 掉到 0.32）。圆柱的底端是平圆面，半径与高度完全不变（0.34 / 1.20），
	# 最低点仍在 y = 0.02，因此 004A 支架的叉口判定（半径 0.34、承托面
	# 0.38、POCKET_XZ 0.30）一个数值都不用改，但晶体可以真的“站”在货台上。
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = 0.34
	cylinder.height = 1.20
	shape.shape = cylinder
	shape.position = Vector3(0.0, 0.62, 0.0)
	add_child(shape)

	visual = CrystalVisual.new()
	visual.name = "CrystalVisual"
	visual.position = Vector3(0.0, 0.10, 0.0)
	add_child(visual)
	var ok: bool = visual.build(asset_path, palette_value, scale_factor, true)
	visual.set_focus_visible(focus_beam_visible)
	spawn_position = global_position
	spawn_yaw_deg = rad_to_deg(rotation.y)
	held_yaw_deg = spawn_yaw_deg
	return ok


func set_spawn(point: Vector3, yaw_degrees: float) -> void:
	spawn_position = point
	spawn_yaw_deg = yaw_degrees
	global_position = point
	rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	held_yaw_deg = yaw_degrees


func set_focus_visible(value: bool) -> void:
	focus_beam_visible = value
	if visual != null:
		visual.set_focus_visible(value)


## Cargo mode: the crystal rests 0.8 m from the driver's eye, so its full
## resonance bloom turns it into a white slab. This keeps the facets readable
## without changing the crystal's role in the network.
func set_cargo_mode(value: bool) -> void:
	if visual != null:
		visual.set_carry_mode(value)


func begin_carry(hold_target: Node3D) -> bool:
	if is_carried:
		return false
	if freight != null:
		freight.call("release_cargo")
		freight = null
	if is_seated and cradle != null:
		cradle.release()
	is_seated = false
	cradle = null
	is_carried = true
	_hold_target = hold_target
	held_yaw_deg = rad_to_deg(rotation.y)
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	set_collision_enabled(false)
	# In first person the shard is carried low at the right hip, tilted away
	# from the lens and outwards so it never covers the centre of the screen.
	# The tilt is visual only (alignment still reads from the yaw) and it is
	# reset the moment the crystal leaves the hands.
	set_visual_tilt(-0.24, -0.18)
	visual.set_carry_mode(true)
	_carry_clock = 0.0
	visual.flash(0.55, 0.2)
	return true


func follow_hold(hold_target: Node3D, sway: float) -> void:
	if not is_carried or hold_target == null:
		return
	_hold_target = hold_target
	_carry_sway = lerpf(_carry_sway, sway, 0.25)
	var target: Vector3 = hold_target.global_position + hold_target.global_transform.basis.x * _carry_sway
	target.y += sin(_carry_clock * 2.6) * 0.035
	global_position = global_position.lerp(target, 1.0 - exp(-CARRY_LERP * get_physics_process_delta_time()))
	rotation = Vector3(0.0, deg_to_rad(held_yaw_deg), 0.0)


func end_carry(throw: bool) -> void:
	if not is_carried:
		return
	is_carried = false
	_hold_target = null
	freeze = false
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	set_collision_enabled(true)
	set_visual_tilt(0.0)
	if visual != null:
		visual.set_carry_mode(false)
	var forward: Vector3 = -global_transform.basis.z
	if throw:
		linear_velocity = forward * 3.4 + Vector3(0.0, 1.6, 0.0)
		angular_velocity = Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6))
	else:
		linear_velocity = forward * 0.45
		angular_velocity = Vector3.ZERO
	_snap_delay = 0.22
	dropped.emit(self)


func rotate_held(degrees: float) -> void:
	if not is_carried:
		return
	held_yaw_deg = fposmod(held_yaw_deg + degrees, 360.0)
	if visual != null:
		visual.flash(0.7, 0.08)


func set_collision_enabled(enabled: bool) -> void:
	if enabled:
		collision_layer = 8
		collision_mask = 1 | 2 | 8
	else:
		collision_layer = 16
		collision_mask = 0


func focus_direction() -> Vector3:
	return -global_transform.basis.z


func set_visual_tilt(angle: float, roll: float = 0.0) -> void:
	if visual != null:
		visual.rotation.x = angle
		visual.rotation.z = roll


func get_interaction_prompt(_player: Node) -> String:
	if is_carried:
		return "Q 旋转晶体   ·   F 放置   ·   X 抛下"
	if is_seated:
		return "F 取下晶体"
	return "F 搬起共振晶体"


func _physics_process(delta: float) -> void:
	if is_carried:
		_carry_clock += delta
		# follow_hold() is driven once per physics frame by player_controller._handle_carry()
		# so we don't double-integrate CARRY_LERP and _carry_sway in the same tick.
		return
	if freight != null:
		return
	if is_seated:
		return
	if _snap_delay > 0.0:
		_snap_delay -= delta
	if global_position.y < -7.0:
		reset_crystal()
		return
	# MECHANICS-004A：检查有没有落进某个叉口（不再靠 1.45 m 磁吸 + 传送）。
	# 5 Hz 足够：落座是 0.2 s 级事件，而 group 查询会分配数组。
	_seat_scan -= delta
	if _snap_delay <= 0.0 and _seat_scan <= 0.0:
		_seat_scan = 0.20
		try_seat()


func try_seat() -> bool:
	if is_carried or is_seated or freight != null or network_seat_lock:
		return false
	# The suspended freight platform's cradle is a valid seat. It comes first so
	# a crystal dropped on the deck is captured before any nearby static cradle.
	var bay: Node = get_tree().get_first_node_in_group("freight_bay")
	if bay != null and bay.has_method("seat_cargo") and bay.has_method("get_bay_position"):
		var bay_position: Vector3 = bay.call("get_bay_position") as Vector3
		var bay_distance: float = Vector2(bay_position.x - global_position.x, bay_position.z - global_position.z).length()
		if bay_distance < 1.75 and absf(bay_position.y - global_position.y) < 2.2:
			if bool(bay.call("seat_cargo", self)):
				return true
	var best: ResonanceCradle = null
	for node: Node in get_tree().get_nodes_in_group("cradle"):
		var candidate: ResonanceCradle = node as ResonanceCradle
		if candidate == null or candidate.is_occupied():
			continue
		# 晶体必须真的落在叉口内部（真实位置），不是被磁吸过去
		if candidate.contains_crystal(self):
			best = candidate
			break
	if best == null:
		return false
	var registered: bool = best.seat(self, held_yaw_deg)
	# "落进叉口" 只是登记，不是对齐结果：这里给一个中性的落座闪光，
	# 成功/失败由锁爪合拢后（cradle._latch → seated 信号）由 HUD 反馈。
	seated_in_cradle.emit(self, best, best.aligned)
	if registered and visual != null:
		visual.flash(0.7, 0.15)
	return true


func reset_crystal() -> void:
	if freight != null:
		freight.call("release_cargo_silent")
		freight = null
	if cradle != null:
		cradle.release()
	is_carried = false
	is_seated = false
	cradle = null
	freeze = false
	set_collision_enabled(true)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = spawn_position
	rotation = Vector3(0.0, deg_to_rad(spawn_yaw_deg), 0.0)
	held_yaw_deg = spawn_yaw_deg
	set_visual_tilt(0.0)
	set_cargo_mode(false)
	if visual != null:
		visual.set_alarm(0.0)
		visual.set_pulse(0.22)

