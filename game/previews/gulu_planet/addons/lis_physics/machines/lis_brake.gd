class_name LISBrake
extends Node
## LIS Physics SDK · 通用有限制动力机械制动器
##
## 作用对象可以是任意刚体（车轮、卷筒、推车）或铰链关节。
## **不冻结物体**、直接把速度清零 —— 那是伪装制动。
##
## 物理模型（库仑摩擦制动）：
##   * 制动容量：capacity_Nm（力矩）或 capacity_N（线性力），有硬上限；
##   * 接合度 engage 0..1 按 engage_time 线性建立（真实刹车有建立行程）；
##   * 保持力矩：抵消外部负载力矩（摩擦制动器的静摩擦段）；
##   * 刹停力矩：只给到"这一帧刚好把转速归零"的量
##     —— 给满会过冲成反向转动，然后每帧来回打（实测 ±2.5 rad/s 抖动）；
##   * 速度响应：可配置低速释放（避免零速抖振）与高温衰减（可选）。
##
## 能量耗散：制动功按每步 τ·ω·dt 累加（恒定正），可用于核对"制动没有凭空造能量"。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_winch_drum.gd 的制动段，
## 抽出来做成可复用的独立组件（任务书 §11.E 要求通用化）。

signal engaged_changed(engaged: bool)
signal overheated(heat: float)

## 制动力矩上限（N·m，用于 axis 模式）。
@export var max_torque: float = 320.0
## 最大制动力（N，用于 linear 模式）。
@export var max_force: float = 2000.0
## 建立 / 释放行程时间（s）。
@export var engage_time: float = 0.08
@export var release_time: float = 0.12
## 速度响应：低于该角速度时不再追加"刹停"力矩（只保留保持力矩），
## 避免零速附近的抖振。
@export var stop_omega_floor: float = 0.02
## 速度响应：高于该角速度时制动容量按比例下降（模拟摩擦片发热衰退）。
## 0 = 不衰减。
@export var fade_omega: float = 0.0
@export var fade_ratio: float = 0.5
## 连续制动时热积累（0..1）。达到 1.0 时容量下降 hot_capacity_ratio。
@export var heat_per_joule: float = 0.0
@export var cool_per_second: float = 0.35
@export var hot_capacity_ratio: float = 0.5

var target_engage: float = 0.0
var engage: float = 0.0
var heat: float = 0.0
var dissipated_joules: float = 0.0
var last_torque: float = 0.0
var last_force: float = 0.0
var powered: bool = true

var _axis: Vector3 = Vector3.UP
var _body: RigidBody3D = null
var _joint: Joint3D = null
var _engaged: bool = false
var _prev_engage: float = 0.0


## 绑定到一个"绕轴转动的刚体"（车轮 / 卷筒 / 配重轮）。
func bind_body_axis(body: RigidBody3D, axis_world: Vector3) -> void:
	_body = body
	_axis = axis_world.normalized() if axis_world.length_squared() > 0.0001 else Vector3.UP
	_joint = null


## 绑定到一个铰链关节（制动的是关节自由度）。
func bind_hinge(joint: HingeJoint3D) -> void:
	_joint = joint
	_body = _resolve_joint_body(joint)
	if _body != null:
		_axis = joint.global_transform.basis.z.normalized()


func _resolve_joint_body(joint: HingeJoint3D) -> RigidBody3D:
	if joint == null or not is_instance_valid(joint):
		return null
	if joint.node_b.is_empty():
		return null
	var n: Node = joint.get_node_or_null(joint.node_b)
	return n as RigidBody3D


## 接合 / 释放。
func set_engaged(on: bool) -> void:
	target_engage = 1.0 if on else 0.0


## 断电：制动器立刻失去容量（真实机械制动断电后看机构：弹簧制动会抱死，
## 电磁释放型会松开。这里默认"断电 = 失去容量"，需要抱死请显式设 engaged）。
func set_powered(on: bool) -> void:
	powered = on


func is_engaged() -> bool:
	return engage > 0.5


func _physics_process(delta: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	# 建立 / 释放行程
	var rate: float = 1.0 / maxf(engage_time, 0.001) if target_engage > engage \
		else 1.0 / maxf(release_time, 0.001)
	_prev_engage = engage
	engage = move_toward(engage, target_engage, rate * delta)
	var active: bool = engage > 0.001 and powered
	if active != _engaged:
		_engaged = active
		engaged_changed.emit(_engaged)
	if not active:
		last_torque = 0.0
		last_force = 0.0
		_cool(delta)
		return

	var capacity: float = max_torque * engage * _capacity_factor()
	var omega: float = _body.angular_velocity.dot(_axis)
	# 刹停力矩：只给到"这一帧刚好归零"。低于阈值时不追加，避免抖振。
	var stop: float = 0.0
	if absf(omega) > stop_omega_floor:
		var inertia: float = _axis_inertia(_body, _axis)
		stop = clampf(-omega * inertia / maxf(delta, 0.0001), -capacity, capacity)
	var tau: float = stop
	last_torque = tau
	if absf(tau) > 0.01:
		_body.apply_torque(_axis * tau)
		dissipated_joules += absf(tau * omega) * delta
		heat = clampf(heat + absf(tau * omega) * delta * heat_per_joule, 0.0, 1.0)
		_cool(delta)


## 线性制动（推车 / 滑块）。force_dir 由运动方向自动决定。
func apply_linear_brake(delta: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var active: bool = engage > 0.001 and powered
	if not active:
		last_force = 0.0
		return
	var v: Vector3 = _body.linear_velocity
	var speed: float = v.length()
	if speed < 0.01:
		last_force = 0.0
		return
	var capacity: float = max_force * engage * _capacity_factor()
	var stop_force: float = clampf(-_body.mass * speed / maxf(delta, 0.0001), -capacity, capacity)
	last_force = absf(stop_force)
	_body.apply_central_force(v.normalized() * stop_force)
	dissipated_joules += absf(stop_force) * speed * delta
	heat = clampf(heat + absf(stop_force) * speed * delta * heat_per_joule, 0.0, 1.0)
	_cool(delta)


func _capacity_factor() -> float:
	var f: float = 1.0
	if fade_omega > 0.0 and _body != null:
		var w: float = absf(_body.angular_velocity.dot(_axis))
		if w > fade_omega:
			f = maxf(fade_ratio, 1.0 - (1.0 - fade_ratio) * clampf((w - fade_omega) / fade_omega, 0.0, 1.0))
	if heat > 0.6:
		f *= lerpf(1.0, hot_capacity_ratio, (heat - 0.6) / 0.4)
	return maxf(f, 0.05)


func _cool(delta: float) -> void:
	heat = maxf(0.0, heat - cool_per_second * delta)
	if heat >= 0.999:
		overheated.emit(heat)


func _axis_inertia(body: RigidBody3D, axis: Vector3) -> float:
	var inv: Basis = body.get_inverse_inertia_tensor()
	var ii: float = absf(axis.dot(inv * axis))
	return 1.0 / maxf(ii, 0.000001)


## 断电线（热遥测）：供 HUD / 测试读。
func telemetry() -> Dictionary:
	return {
		"engaged": is_engaged(),
		"engage": engage,
		"torque": last_torque,
		"force": last_force,
		"heat": heat,
		"dissipated_j": dissipated_joules,
		"powered": powered,
	}
