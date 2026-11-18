class_name LISHingeDoor
extends Node3D
## LIS Physics SDK · 真实铰链门（被动，可推动）
##
## 门板是真正的 RigidBody3D，通过 HingeJoint3D 约束在门框上。
## 玩家用身体推门 → 接触力产生绕竖直铰链轴的力矩 → 门自己转开。
## 没有 progress 变量、没有 lerp 到目标角度、没有预烘焙动画。
##
## 竖直铰链的门：重力沿 −Y，与竖直门轴平行，**不产生绕门轴的力矩**。
## 门能开是靠人/物推的水平力；关是靠阻尼与惯性，不是"重力自动关门"。
## 这条是本 SDK 明确处理的一个历史错误（旧实现曾把重力算成开门力矩）。
##
## 来源：work/physics-lab/physics_lab/scripts/phys_door.gd（并入 + 解耦）

signal door_pushed(speed: float)
signal door_state_changed(open: bool)

const PANEL_W := 1.05
const PANEL_H := 2.05
const PANEL_T := 0.07
const PANEL_MASS := 21.0
const OPEN_LIMIT_DEG := 104.0
const GROUP_DOOR := "lis_hinge_door"

## 推门时施加的冲量（N·s）。约等于手掌猛推一下，不无视门的质量。
@export var push_impulse: float = 26.0
@export_flags_3d_physics var frame_layer: int = LISPhysics.LAYER_WORLD
@export_flags_3d_physics var panel_layer: int = LISPhysics.LAYER_PROP
@export_flags_3d_physics var panel_mask: int = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PLAYER | LISPhysics.LAYER_PROP
## 铰链在哪一侧：-1 = 门轴在 −X 边，+1 = +X 边。
@export var hinge_side: float = -1.0

var panel: RigidBody3D
var frame: StaticBody3D
var hinge: HingeJoint3D
var door_built: bool = false

var _open_accum: float = 0.0
var _last_angle: float = 0.0
var _spawn_pose: Transform3D
var peak_speed: float = 0.0


func _ready() -> void:
	if not door_built:
		build_door()


func build_door() -> void:
	if door_built:
		return
	door_built = true
	name = "HingeDoor"
	add_to_group(GROUP_DOOR)

	var steel: StandardMaterial3D = _mat(Color(0.36, 0.42, 0.44), 0.55, 0.45)
	var frame_mat: StandardMaterial3D = _mat(Color(0.24, 0.27, 0.28), 0.80, 0.10)
	var rib_mat: StandardMaterial3D = _mat(Color(0.20, 0.23, 0.24), 0.60, 0.30)

	# --- 门框（静态）-----------------------------------------------------
	frame = StaticBody3D.new()
	frame.name = "Frame"
	frame.collision_layer = frame_layer
	frame.collision_mask = 0
	add_child(frame)
	var post_w: float = 0.16
	var clear_w: float = PANEL_W + 0.06
	for sx: float in [-1.0, 1.0]:
		_add_box(frame, "Post", Vector3(post_w, PANEL_H + 0.30, 0.22),
			Vector3(sx * (clear_w * 0.5 + post_w * 0.5), (PANEL_H + 0.30) * 0.5, 0.0), frame_mat)
	_add_box(frame, "Lintel", Vector3(clear_w + post_w * 2.0, 0.20, 0.24),
		Vector3(0.0, PANEL_H + 0.10, 0.0), frame_mat)

	# --- 门板（真实刚体）-------------------------------------------------
	panel = RigidBody3D.new()
	panel.name = "Panel"
	panel.mass = PANEL_MASS
	panel.gravity_scale = 1.0
	panel.linear_damp = 0.15
	panel.angular_damp = 0.85          # 门轴摩擦，靠阻尼近似
	panel.continuous_cd = true
	panel.collision_layer = panel_layer
	panel.collision_mask = panel_mask
	panel.can_sleep = false
	var pmat: PhysicsMaterial = PhysicsMaterial.new()
	pmat.friction = 0.55
	pmat.bounce = 0.02
	panel.physics_material_override = pmat
	add_child(panel)

	var hinge_x: float = hinge_side * (PANEL_W * 0.5 + 0.03)
	panel.position = Vector3(hinge_x - hinge_side * PANEL_W * 0.5, PANEL_H * 0.5 + 0.03, 0.0)

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(PANEL_W, PANEL_H, PANEL_T)
	shape.shape = box
	panel.add_child(shape)

	var panel_mesh: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(PANEL_W, PANEL_H, PANEL_T)
	panel_mesh.mesh = bm
	panel_mesh.material_override = steel
	panel.add_child(panel_mesh)

	# 门板上的横筋与把手，都是门板的子节点，跟着真实刚体一起动。
	for i in range(3):
		var y: float = -PANEL_H * 0.32 + float(i) * PANEL_H * 0.32
		var rib: MeshInstance3D = MeshInstance3D.new()
		var rm: BoxMesh = BoxMesh.new()
		rm.size = Vector3(PANEL_W * 0.94, 0.09, 0.02)
		rib.mesh = rm
		rib.material_override = rib_mat
		rib.position = Vector3(0.0, y, PANEL_T * 0.5 + 0.01)
		panel.add_child(rib)
	var handle: MeshInstance3D = MeshInstance3D.new()
	var hm: BoxMesh = BoxMesh.new()
	hm.size = Vector3(0.10, 0.34, 0.06)
	handle.mesh = hm
	handle.material_override = rib_mat
	handle.position = Vector3(-hinge_side * PANEL_W * 0.38, -0.05, PANEL_T * 0.5 + 0.05)
	panel.add_child(handle)

	# --- 铰链 ------------------------------------------------------------
	# HingeJoint3D 绕自身局部 Z 轴旋转；绕 X 转 −90° 后局部 Z 对准世界 +Y（竖直门轴）。
	hinge = HingeJoint3D.new()
	hinge.name = "Hinge"
	hinge.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5),
		Vector3(hinge_x, PANEL_H * 0.5 + 0.03, 0.0))
	hinge.node_a = frame.get_path()
	hinge.node_b = panel.get_path()
	hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-OPEN_LIMIT_DEG))
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(OPEN_LIMIT_DEG))
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_SOFTNESS, 0.9)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_RELAXATION, 1.0)
	add_child(hinge)
	# 铰链必须排在门框与门板**之前**：引擎按子节点顺序拆除，
	# 否则门板（刚体）先被释放、引用它的铰链后释放 → 退出时访问冲突。
	LISJointKit.order_joints_first(self)
	_spawn_pose = panel.global_transform
	_last_angle = _hinge_angle()


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _add_box(parent: Node3D, label: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	parent.add_child(cs)


# ---------------------------------------------------------------------------
# 交互：一次有限冲量（约等于手掌猛推），不无视门的质量
# ---------------------------------------------------------------------------

## 沿 from_world_point → 门板方向推一下。
func push_from(world_point: Vector3, strength: float = -1.0) -> void:
	if panel == null:
		return
	var dir: Vector3 = panel.global_position - world_point
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var imp: float = push_impulse if strength < 0.0 else strength
	var contact: Vector3 = panel.global_position + Vector3(0.0, 0.15, 0.0)
	panel.apply_impulse(dir * imp, contact - panel.global_position)
	door_pushed.emit(panel.angular_velocity.length())


## 沿世界方向推（供适配器/测试使用）。
func push_along(dir_world: Vector3, strength: float = -1.0) -> void:
	if panel == null:
		return
	var d: Vector3 = dir_world
	d.y = 0.0
	if d.length() < 0.01:
		return
	d = d.normalized()
	var imp: float = push_impulse if strength < 0.0 else strength
	var contact: Vector3 = panel.global_position + Vector3(0.0, 0.15, 0.0)
	panel.apply_impulse(d * imp, contact - panel.global_position)
	door_pushed.emit(panel.angular_velocity.length())


func _physics_process(delta: float) -> void:
	if not door_built or panel == null:
		return
	var angle: float = _hinge_angle()
	peak_speed = maxf(peak_speed, absf(angle - _last_angle) / maxf(delta, 0.0001))
	_last_angle = angle


## 门板相对门框的开合角（弧度）。正值 = 向 +X 侧推开。
func _hinge_angle() -> float:
	if panel == null:
		return 0.0
	var fwd: Vector3 = panel.global_transform.basis.z
	return atan2(fwd.x, fwd.z)


func get_open_degrees() -> float:
	return rad_to_deg(_hinge_angle())


func is_open() -> bool:
	return absf(get_open_degrees()) > 45.0


## 复位：门板搬回关闭位并清速度（门框与铰链不动，约束几何一致）。
func reset_door() -> void:
	if panel == null:
		return
	panel.sleeping = false
	panel.freeze = false
	panel.linear_velocity = Vector3.ZERO
	panel.angular_velocity = Vector3.ZERO
	panel.global_transform = _spawn_pose
	_last_angle = _hinge_angle()
	peak_speed = 0.0


func enable_mirror(enabled: bool) -> void:
	if panel == null:
		return
	panel.freeze = enabled
	panel.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


## 安全销毁：先拆铰链再释放门板。
func despawn() -> void:
	if hinge != null and is_instance_valid(hinge):
		LISJointKit.teardown(hinge)
		hinge = null
	queue_free()


func snapshot() -> Dictionary:
	if panel == null:
		return {}
	return {
		"pos": panel.global_position,
		"rot": panel.rotation,
		"lin": panel.linear_velocity,
		"ang": panel.angular_velocity,
	}


func apply_snapshot(data: Dictionary) -> void:
	if data.is_empty() or panel == null:
		return
	panel.global_position = data.get("pos", panel.global_position) as Vector3
	panel.rotation = data.get("rot", panel.rotation) as Vector3
	panel.linear_velocity = data.get("lin", Vector3.ZERO) as Vector3
	panel.angular_velocity = data.get("ang", Vector3.ZERO) as Vector3
