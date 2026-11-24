class_name LISPulley
extends Node3D
## LIS Physics SDK · 真实滑轮（轮轴 + 轴承摩擦 + 绳摩擦驱动）
##
## 轮子是一个真实 RigidBody3D，通过 HingeJoint3D 挂在支架上（定滑轮），
## 或吊在绳上（动滑轮，支架是自由刚体）。
## 绳对轮子的驱动来自**摩擦**：每帧按"绳速 vs 轮缘速度"的差施加一个
## 摩擦冲量，上限 μ·T·R —— 轮子有惯量、有轴承阻尼，所以重载时会打滑滞后。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_pulley.gd

const WHEEL_RADIUS := 0.16
const WHEEL_WIDTH := 0.09
const WHEEL_MASS := 6.0
const ROPE_FRICTION := 0.35
const GROUP_PULLEY := "lis_pulley"

## 必须在 add_child 之前设置：_ready 会按这个值决定建成定滑轮还是动滑轮。
@export var want_movable: bool = false
@export_flags_3d_physics var body_layer: int = LISPhysics.LAYER_PROP
@export_flags_3d_physics var body_mask: int = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PROP

var wheel: RigidBody3D
var frame: StaticBody3D
var hinge: HingeJoint3D
var pulley_built: bool = false
var is_movable: bool = false
## 动滑轮的吊架（自由刚体）；定滑轮为 null。
var yoke: RigidBody3D = null

var omega: float = 0.0
var rope_speed: float = 0.0
var friction_torque: float = 0.0
var spin_total: float = 0.0


func _ready() -> void:
	if not pulley_built:
		build_pulley(want_movable)


func build_pulley(movable: bool = false) -> void:
	if pulley_built:
		return
	pulley_built = true
	is_movable = movable
	name = "Pulley"

	var steel: StandardMaterial3D = _mat(Color(0.40, 0.42, 0.45), 0.45, 0.70)
	var dark: StandardMaterial3D = _mat(Color(0.18, 0.19, 0.21), 0.75, 0.10)

	wheel = RigidBody3D.new()
	wheel.name = "Wheel"
	wheel.mass = WHEEL_MASS
	wheel.gravity_scale = 1.0
	wheel.linear_damp = 0.1
	wheel.angular_damp = 0.35          # 轴承摩擦（真实影响转动）
	wheel.continuous_cd = true
	wheel.can_sleep = false
	wheel.collision_layer = body_layer
	wheel.collision_mask = body_mask
	var wmat: PhysicsMaterial = PhysicsMaterial.new()
	wmat.friction = 0.45
	wmat.bounce = 0.0
	wmat.rough = false
	wheel.physics_material_override = wmat
	add_child(wheel)
	wheel.position = Vector3.ZERO

	var mesh: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = WHEEL_RADIUS
	cm.bottom_radius = WHEEL_RADIUS
	cm.height = WHEEL_WIDTH
	cm.radial_segments = 24
	mesh.mesh = cm
	mesh.material_override = steel
	mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
	wheel.add_child(mesh)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = WHEEL_RADIUS
	cyl.height = WHEEL_WIDTH
	cs.shape = cyl
	cs.rotation = Vector3(0.0, 0.0, PI * 0.5)
	wheel.add_child(cs)
	# 轮辐（看得出在转）
	var spoke_mat: StandardMaterial3D = _mat(Color(0.76, 0.60, 0.20), 0.55, 0.30)
	for i in range(2):
		var spoke: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(WHEEL_WIDTH + 0.012, WHEEL_RADIUS * 1.7, 0.025)
		spoke.mesh = bm
		spoke.material_override = spoke_mat
		spoke.rotation = Vector3(0.0, 0.0, PI * 0.5 * float(i))
		wheel.add_child(spoke)

	if is_movable:
		# 动滑轮：轮子吊在一个自由刚体吊架上（靠绳索支撑）。
		yoke = RigidBody3D.new()
		yoke.name = "Yoke"
		yoke.mass = 2.5
		yoke.gravity_scale = 1.0
		yoke.linear_damp = 0.05
		yoke.angular_damp = 0.5
		yoke.can_sleep = false
		yoke.collision_layer = body_layer
		yoke.collision_mask = body_mask
		add_child(yoke)
		yoke.position = Vector3.ZERO
		frame = StaticBody3D.new()
		frame.name = "YokeVisual"
		frame.collision_layer = 0
		frame.collision_mask = 0
		yoke.add_child(frame)
		var hinge2: HingeJoint3D = HingeJoint3D.new()
		hinge2.name = "YokeAxle"
		hinge2.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		yoke.add_child(hinge2)
		hinge2.node_a = hinge2.get_path_to(yoke)
		hinge2.node_b = hinge2.get_path_to(wheel)
		var hook: MeshInstance3D = MeshInstance3D.new()
		var hm: BoxMesh = BoxMesh.new()
		hm.size = Vector3(0.08, 0.26, 0.08)
		hook.mesh = hm
		hook.material_override = dark
		hook.position = Vector3(0.0, -WHEEL_RADIUS - 0.13, 0.0)
		frame.add_child(hook)
	else:
		# 定滑轮：轮子通过铰链挂在静态支架上。
		frame = StaticBody3D.new()
		frame.name = "Bracket"
		frame.collision_layer = LISPhysics.LAYER_WORLD
		frame.collision_mask = 0
		var host: Node3D = get_parent() as Node3D
		if host != null:
			host.add_child(frame)
			frame.global_transform = global_transform
		_add_box(frame, "Brace", Vector3(0.10, 0.10, 0.30), Vector3.ZERO, dark)
		var axle_mesh: MeshInstance3D = MeshInstance3D.new()
		var am: CylinderMesh = CylinderMesh.new()
		am.top_radius = 0.035
		am.bottom_radius = 0.035
		am.height = WHEEL_WIDTH + 0.14
		am.radial_segments = 12
		axle_mesh.mesh = am
		axle_mesh.material_override = dark
		axle_mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
		wheel.add_child(axle_mesh)
		hinge = HingeJoint3D.new()
		hinge.name = "PulleyAxle"
		hinge.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		frame.add_child(hinge)
		hinge.node_a = hinge.get_path_to(frame)
		hinge.node_b = hinge.get_path_to(wheel)

	# 销毁顺序：铰链先于刚体。
	# 动滑轮：轴承铰链挂在吊架下 → 先把铰链排到吊架子节点最前。
	if yoke != null and is_instance_valid(yoke):
		LISJointKit.order_joints_first(yoke)
	# 定滑轮：支架（含轴承铰链）是**兄弟节点**，必须排在轮子所属节点之前。
	if frame != null and is_instance_valid(frame) and frame.get_parent() == get_parent():
		LISJointKit.ensure_constraints_precede(self, frame)

	add_to_group(GROUP_PULLEY)


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


func axis_world() -> Vector3:
	return wheel.global_transform.basis.x.normalized()


func radius() -> float:
	return WHEEL_RADIUS


## 绳对轮子的摩擦驱动：按"绳速 − 轮缘速度"施加受 μ·T·R 限制的摩擦冲量。
func apply_rope_friction(rope_v: float, tension: float, delta: float) -> void:
	rope_speed = rope_v
	omega = wheel.angular_velocity.dot(axis_world())
	var rim_v: float = omega * WHEEL_RADIUS
	var slip: float = rope_v - rim_v
	var inertia: float = 0.5 * WHEEL_MASS * WHEEL_RADIUS * WHEEL_RADIUS
	# 一帧内把轮缘速度拉到绳速所需的力矩 = I·Δω/dt，Δω = slip/R。
	# 上限是绳-轮摩擦能提供的力矩 μ·T·R（超过就真打滑）。
	var tau_need: float = inertia * slip / maxf(WHEEL_RADIUS, 0.0001) / maxf(delta, 0.0001)
	var max_tau: float = ROPE_FRICTION * maxf(tension, 0.0) * WHEEL_RADIUS
	var tau: float = clampf(tau_need, -max_tau, max_tau)
	friction_torque = tau
	if absf(tau) > 0.0005:
		wheel.apply_torque(axis_world() * tau)
	spin_total += omega * delta


func reset_pulley() -> void:
	if not pulley_built:
		return
	wheel.sleeping = false
	wheel.freeze = false
	wheel.linear_velocity = Vector3.ZERO
	wheel.angular_velocity = Vector3.ZERO
	omega = 0.0
	spin_total = 0.0
	friction_torque = 0.0


func despawn() -> void:
	if hinge != null and is_instance_valid(hinge):
		LISJointKit.teardown(hinge)
		hinge = null
	queue_free()
