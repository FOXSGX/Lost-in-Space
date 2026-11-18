class_name LISMotorDoor
extends Node3D
## LIS Physics SDK · 电动机械门（铰链马达 + 力矩上限 + 真实碰撞）
##
## 门板是 RigidBody3D，通过 HingeJoint3D 挂在门框上；开门动力来自**铰链马达**：
##   * 只给"目标角速度"，由马达产生力矩；
##   * 力矩上限 = max_torque（N·m），通过 PARAM_MOTOR_MAX_IMPULSE 按物理帧换算；
##   * 门被箱子/人挡住时，马达只能顶到力矩上限，门停下 ——
##     不会把门推穿过障碍；
##   * 门的角度由物理求解器决定，脚本从不写 Transform、不播动画。
##
## 控制逻辑（电控，不是时间轴）：
##   开关闭合 → open_delay 后给出"开门"指令
##   开关断开 → close_delay 后给出"关门"指令（留出通过时间）→ 断电后门自由（可被推）
##
## 来源：work/final-integration-001/project/scripts/physics/phys_power_door.gd

signal door_state_changed(open: bool)
signal blocked_changed(blocked: bool)

const PANEL_W := 1.28
const PANEL_H := 2.05
const PANEL_T := 0.08
const PANEL_MASS := 55.0
const PANEL_CENTER_Y := 1.075
const GROUP_DOOR := "lis_motor_door"

## 最大开度（度）。开到 100° 时门板会扫回门框内侧（实测越界 0.157 m）；
## 90° 已经完全通行，这里取 88°。
@export var open_deg: float = 88.0
## 马达力矩上限（N·m）。
##
## 门板 55 kg、重心离铰链 0.64 m，重力矩 ≈ 345 N·m（若门轴不在竖直方向）。
## 竖直门轴下重力不产生绕轴力矩，但门自身惯性与摩擦仍需力矩。
## 被 40 kg 箱子挡住时箱子对门轴的力矩约 373 N·m。
## 取 600 N·m：空门可开，被 40 kg 箱挡住时推不动并判堵转 —— 这正是要验证的行为。
@export var max_torque: float = 600.0
## 最大角速度（rad/s）。100° 约用 1.4 s，肉眼看得见是机械在转。
@export var max_omega: float = 1.25
@export var open_delay: float = 0.15
@export var close_delay: float = 1.2
## 断电后是否允许门被自由推动（真实机械门断电后应是自由 / 或抱闸，
## 由机构决定；这里默认"释放马达、允许被推"）。
@export var free_when_unpowered: bool = true
@export_flags_3d_physics var frame_layer: int = LISPhysics.LAYER_WORLD
@export_flags_3d_physics var panel_layer: int = LISPhysics.LAYER_PROP
@export_flags_3d_physics var panel_mask: int = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PLAYER | LISPhysics.LAYER_PROP

var frame: StaticBody3D
var panel: RigidBody3D
var hinge: HingeJoint3D
var closed_angle_deg: float = 0.0

var open_requested: bool = false
var door_angle_deg: float = 0.0
var door_omega: float = 0.0
var motor_torque: float = 0.0
var blocked: bool = false
var open_count: int = 0
## 是否通电。断电 = 马达不输出力矩（门自由或抱死，取决于 free_when_unpowered）。
var powered: bool = true

var _command_open: bool = false
var _pending_since: float = -1.0
var _stall_time: float = 0.0
var _built: bool = false
var _spawn_pose: Transform3D


func _ready() -> void:
	if not _built:
		build_door()


func build_door() -> void:
	if _built:
		return
	_built = true
	name = "MotorDoor"
	_spawn_pose = global_transform

	frame = StaticBody3D.new()
	frame.name = "DoorFrame"
	frame.collision_layer = frame_layer
	frame.collision_mask = 0
	add_child(frame)

	var steel: StandardMaterial3D = _mat(Color(0.30, 0.33, 0.36), 0.55, 0.55)
	var panel_mat: StandardMaterial3D = _mat(Color(0.46, 0.40, 0.28), 0.60, 0.40)
	var trim: StandardMaterial3D = _mat(Color(0.74, 0.56, 0.16), 0.55, 0.10)

	# 门框（两侧立柱 + 过梁），给门一个真实的框。
	var post_w: float = 0.16
	for sx: float in [-1.0, 1.0]:
		_add_box(frame, "DoorPost", Vector3(post_w, PANEL_H + 0.25, 0.30),
			Vector3(sx * (PANEL_W * 0.5 + post_w * 0.5), (PANEL_H + 0.25) * 0.5, 0.0), steel)
	_add_box(frame, "DoorLintel", Vector3(PANEL_W + post_w * 2.0, 0.22, 0.32),
		Vector3(0.0, PANEL_H + 0.11, 0.0), steel)

	# 门板：铰链在 −X 边，门板从铰链往右展开，占满门洞（居中）。
	panel = RigidBody3D.new()
	panel.name = "Panel"
	panel.mass = PANEL_MASS
	panel.gravity_scale = 1.0
	panel.linear_damp = 0.1
	panel.angular_damp = 0.35
	panel.continuous_cd = true
	panel.can_sleep = false
	panel.collision_layer = panel_layer
	panel.collision_mask = panel_mask
	panel.contact_monitor = true
	panel.max_contacts_reported = 6
	var pmat: PhysicsMaterial = PhysicsMaterial.new()
	pmat.friction = 0.55
	pmat.bounce = 0.0
	panel.physics_material_override = pmat
	add_child(panel)
	panel.position = Vector3(0.0, PANEL_H * 0.5 + 0.05, 0.0)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = Vector3(PANEL_W, PANEL_H, PANEL_T)
	cs.shape = bs
	panel.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(PANEL_W, PANEL_H, PANEL_T)
	mi.mesh = bm
	mi.material_override = panel_mat
	panel.add_child(mi)
	# 门面加强筋与警示条（跟着真实门体动）
	for i in range(3):
		var rib: MeshInstance3D = MeshInstance3D.new()
		var rm: BoxMesh = BoxMesh.new()
		rm.size = Vector3(PANEL_W * 0.92, 0.08, PANEL_T + 0.02)
		rib.mesh = rm
		rib.material_override = trim
		rib.position = Vector3(0.0, -PANEL_H * 0.30 + float(i) * PANEL_H * 0.30, 0.0)
		panel.add_child(rib)
	# 门轴传动臂（视觉上表明"这是被电机带动的门"）
	var arm: MeshInstance3D = MeshInstance3D.new()
	var am: BoxMesh = BoxMesh.new()
	am.size = Vector3(PANEL_W * 0.94, 0.10, 0.10)
	arm.mesh = am
	arm.material_override = steel
	arm.position = Vector3(0.0, PANEL_H * 0.42, 0.0)
	panel.add_child(arm)

	# 铰链：绕自身局部 Z；绕 X 转 −90° 使局部 Z 对准世界 +Y（竖直门轴）。
	# 铰链装在门洞的**左边**（门板从左往右展开），门板中心因此在门节点原点。
	hinge = HingeJoint3D.new()
	hinge.name = "DoorHinge"
	hinge.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5),
		Vector3(-PANEL_W * 0.5, PANEL_H * 0.5 + 0.05, 0.0))
	add_child(hinge)
	hinge.node_a = hinge.get_path_to(frame)
	hinge.node_b = hinge.get_path_to(panel)
	hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-2.0))
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(open_deg))
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_SOFTNESS, 0.9)
	hinge.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 0.0)
	# 铰链必须排在门框与门板**之前**（同 LISHingeDoor 的说明）。
	LISJointKit.order_joints_first(self)

	closed_angle_deg = _raw_angle_deg()


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _add_box(parent: Node3D, label: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = label
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	parent.add_child(cs)


## 铰链角（度）：0 = 关闭，正 = 打开。
##
## 实测标定：关节参数 J 与刚体绕轴转角 φ 满足 J = −φ。
## 门绕世界 +Y 转 φ 时 basis.z = (sinφ, 0, cosφ)，所以 J = −atan2(fwd.x, fwd.z)。
func _raw_angle_deg() -> float:
	if panel == null:
		return 0.0
	var fwd: Vector3 = panel.global_transform.basis.z
	var base: Vector3 = global_transform.basis.z
	return -rad_to_deg(atan2(fwd.x, fwd.z) - atan2(base.x, base.z))


func angle_deg() -> float:
	return door_angle_deg


func is_open() -> bool:
	return door_angle_deg > 55.0


## 由开关调用：请求开/关（带延迟与去抖）。
func set_request(open_now: bool) -> void:
	if open_now == open_requested:
		return
	open_requested = open_now
	_pending_since = 0.0 if open_now else -close_delay


## 断电：马达立刻停止输出力矩，物理状态由机构决定（默认允许门被推）。
func set_powered(on: bool) -> void:
	powered = on
	if not on and hinge != null and is_instance_valid(hinge):
		hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 0.0)
		hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		motor_torque = 0.0


func _physics_process(delta: float) -> void:
	if panel == null:
		return
	door_angle_deg = _raw_angle_deg()
	var axis: Vector3 = global_transform.basis.y.normalized()
	door_omega = panel.angular_velocity.dot(axis)

	# 指令延迟：开门 open_delay，关门 close_delay。
	var target_open: bool = _command_open
	if powered:
		if _pending_since >= -0.001 and open_requested:
			_pending_since += delta
			if _pending_since >= open_delay:
				target_open = true
		elif not open_requested:
			_pending_since += delta
			if _pending_since >= 0.0:
				target_open = false
	if target_open != _command_open:
		_command_open = target_open
		if _command_open:
			open_count += 1
		door_state_changed.emit(_command_open)

	# 执行器：目标角速度 + 力矩上限
	var target_deg: float = open_deg if _command_open else 0.0
	var err: float = target_deg - door_angle_deg
	var want_omega: float = 0.0
	if absf(err) > 1.5:
		want_omega = clampf(err * 0.09, -max_omega, max_omega)
	_drive_motor(want_omega, delta)

	# 堵转检测：有指令、误差大、几乎不转 → 认为被挡住（只用于显示，不放大扭矩）。
	var want_move: bool = absf(err) > 8.0
	var was_blocked: bool = blocked
	if want_move and absf(door_omega) < 0.08:
		_stall_time += delta
	else:
		_stall_time = maxf(0.0, _stall_time - delta * 2.0)
	blocked = _stall_time > 0.7
	if blocked != was_blocked:
		blocked_changed.emit(blocked)


func _drive_motor(want_omega: float, delta: float) -> void:
	if hinge == null or not is_instance_valid(hinge):
		return
	if not powered:
		motor_torque = 0.0
		hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 0.0)
		return
	var running: bool = absf(want_omega) > 0.001
	var impulse: float = max_torque * delta if running else 0.0
	motor_torque = max_torque if running else 0.0
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, want_omega)
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, impulse)


## 复位：门板搬回关闭位、清速度（门框与铰链不动，约束几何一致）。
##
## 必须同时把控制器的"上次指令"与开关真实状态重新对齐，否则会出现
## "开关还闭着、门却停在关闭位"的死锁：set_request() 只在**状态变化**时发指令。
func reset_door() -> void:
	if panel == null:
		return
	panel.sleeping = false
	panel.freeze = false
	panel.linear_velocity = Vector3.ZERO
	panel.angular_velocity = Vector3.ZERO
	panel.global_transform = Transform3D(global_transform.basis,
		global_transform * Vector3(0.0, PANEL_H * 0.5 + 0.05, 0.0))
	open_requested = false
	_command_open = false
	_pending_since = -1.0
	_stall_time = 0.0
	blocked = false
	door_angle_deg = 0.0
	door_omega = 0.0
	powered = true
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 0.0)


## 按开关**当前是否处于触发状态**重新下发指令（复位后调用，
## 避免控制器与物理开关的实际状态脱节）。
##
## 参数语义：`open_now = true` 表示"开关被压下 → 请求开门"；
## 本方法内部就是转调 set_request(open_now)。
##
## 命名修正：历史实现的形参叫 `closed_now`，与真实语义**相反**
## （它被原样传给 set_request(open_now)）。那个名字会让调用方把"关"传成"开"，
## 实测后果是复位后的门立刻自己开到 88°，后续的阻挡测试测到的其实是
## "门早就开了"。这里改名为 open_now 并把语义写清楚。
func rearm(open_now: bool) -> void:
	if open_now != open_requested:
		open_requested = open_now
		_pending_since = 0.0 if open_now else -close_delay


func enable_mirror(enabled: bool) -> void:
	if panel == null:
		return
	panel.freeze = enabled
	panel.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func despawn() -> void:
	if hinge != null and is_instance_valid(hinge):
		LISJointKit.teardown(hinge)
		hinge = null
	queue_free()


func snapshot() -> Dictionary:
	if panel == null:
		return {}
	return {"pos": panel.global_position, "rot": panel.rotation,
		"lin": panel.linear_velocity, "ang": panel.angular_velocity}


func apply_snapshot(data: Dictionary) -> void:
	if data.is_empty() or panel == null:
		return
	panel.global_position = data.get("pos", panel.global_position) as Vector3
	panel.rotation = data.get("rot", panel.rotation) as Vector3
	panel.linear_velocity = data.get("lin", Vector3.ZERO) as Vector3
	panel.angular_velocity = data.get("ang", Vector3.ZERO) as Vector3
