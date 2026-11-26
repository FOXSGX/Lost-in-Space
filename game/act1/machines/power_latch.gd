class_name Act1PowerLatch
extends Node3D
## MECHANICS-001B-R2 · 电源锁爪（独立组件）
##
## 自带：静态支架 + RigidBody3D 锁爪 + HingeJoint3D（无关节限位，靠实体止挡/模块自锁）。
## 用法：instantiate 后设 `pivot_world`（世界坐标）并调用 `set_closed(true/false)`。
##
## 已有的已知事实（本文件即为其固化）：
##   * 关节限位在重力下会把自由度钳死 → 本组件**不使用**关节限位；
##   * 铰链必须挂在**中性父节点**下、`transform` 在 add_child 之前设好；
##   * 马达按惯量与重力矩估算：臂 0.62 m、25 kg → 重力矩 ≈152 N·m，冲量取 420。

const JAW_MASS := 25.0
const ARM := 0.62
const MOTOR_IMPULSE := 420.0
const CLOSED_ANGLE := 0.30     # 压在模块顶上对应的角度（rad）
const OPEN_ANGLE := 0.02

var jaw: RigidBody3D
var hinge: HingeJoint3D
var bracket: StaticBody3D
var axis: Vector3 = Vector3(0.0, 0.0, -1.0)
var start_basis: Basis
var _closed := false
var _built := false


func setup(pivot_world: Vector3) -> void:
	global_position = pivot_world
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	bracket = StaticBody3D.new()
	bracket.name = "LatchBracket"
	bracket.collision_layer = 1
	bracket.collision_mask = 0
	var bcs: CollisionShape3D = CollisionShape3D.new()
	var bbs: BoxShape3D = BoxShape3D.new()
	bbs.size = Vector3(0.16, 0.60, 0.16)
	bcs.shape = bbs
	bracket.add_child(bcs)
	add_child(bracket)
	bracket.position = Vector3.ZERO

	jaw = RigidBody3D.new()
	jaw.name = "LatchJaw"
	jaw.mass = JAW_MASS
	jaw.gravity_scale = 1.0
	jaw.can_sleep = false
	jaw.angular_damp = 0.4
	jaw.linear_damp = 0.4
	jaw.collision_layer = 4
	jaw.collision_mask = 1 | 2 | 4 | 16
	var jcs: CollisionShape3D = CollisionShape3D.new()
	var jbs: BoxShape3D = BoxShape3D.new()
	jbs.size = Vector3(0.92, 0.20, 0.90)
	jcs.shape = jbs
	jcs.position = Vector3(-ARM, 0.0, 0.0)
	jaw.add_child(jcs)
	var jmi: MeshInstance3D = MeshInstance3D.new()
	var jbm: BoxMesh = BoxMesh.new()
	jbm.size = jbs.size
	jmi.mesh = jbm
	jmi.position = jcs.position
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.45, 0.12)
	jmi.material_override = mat
	jaw.add_child(jmi)
	add_child(jaw)
	jaw.position = Vector3.ZERO
	jaw.sleeping = false

	# 铰链：中性父节点（本组件根）、transform 前置、无关节限位
	hinge = HingeJoint3D.new()
	hinge.name = "LatchHinge"
	hinge.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	add_child(hinge)
	hinge.node_a = hinge.get_path_to(bracket)
	hinge.node_b = hinge.get_path_to(jaw)
	hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	hinge.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 0.0)
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	axis = hinge.global_transform.basis.z.normalized()
	start_basis = jaw.global_transform.basis


func set_closed(on: bool) -> void:
	_closed = on
	if jaw != null:
		jaw.sleeping = false
	if hinge != null:
		hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
		hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, -1.25 if on else 1.25)
		hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MOTOR_IMPULSE)


func stop_motor() -> void:
	if hinge != null:
		hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 0.0)
		hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)


## 绕真实铰链轴的有符号角
func angle() -> float:
	if jaw == null:
		return 0.0
	var axl: Vector3 = start_basis.inverse() * axis
	var rel: Basis = start_basis.inverse() * jaw.global_transform.basis
	var q: Quaternion = rel.get_rotation_quaternion()
	var s: float = q.x * axl.x + q.y * axl.y + q.z * axl.z
	return 2.0 * atan2(s, q.w)


func is_closed() -> bool:
	return _closed and absf(angle()) >= CLOSED_ANGLE - 0.06


func reset_latch() -> void:
	_closed = false
	stop_motor()
	if jaw != null:
		jaw.linear_velocity = Vector3.ZERO
		jaw.angular_velocity = Vector3.ZERO
		jaw.global_transform = Transform3D(start_basis, global_position)
