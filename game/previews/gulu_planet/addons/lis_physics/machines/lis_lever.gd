class_name LISLever
extends LISBody
## LIS Physics SDK · 真实杠杆（配重 + 载物台 + 物理支点）
##
## 结构（build() 运行时搭建）：
##
##   LeverFrame (StaticBody3D, 静态，挂在父节点下)
##   ├── Base / Post ×2 / Bearing
##   └── Axle (HingeJoint3D, 轴沿世界 X)   ← 真实支点
##
##   Lever (LISLever ← 刚体, 120 kg)
##   ├── BeamShape      0.12 × 0.16 × 2.35
##   ├── CounterWeight  0.36 × 0.36 × 0.34 @ z=-0.62（配重，决定阈值负载）
##   └── PanPlate       0.80 × 0.05 × 1.50 @ z=+1.30（载物台）
##
## 物理要点：
##   * 质量、重心、转动惯量都显式给定（COM = (0,-0.03,-0.21)，I = (72,34,96)），
##     不是靠形状体积碰运气；
##   * 载物端力矩 = 货物重量 × 货物到支点的水平距离。阈值 ≈ 19 kg @ z=1.28，
##     所以 12 kg 压不动、24 kg 能压动 —— 全部由真实力矩决定，
##     SDK 不知道箱子的名字；
##   * 支点用 HingeJoint3D 的机械限位（±14°），没有脚本写角度。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_lever.gd

const PIVOT_HEIGHT := 1.10
const LEVER_MASS := 120.0
## 重心（局部）。z 为负 = 偏配重侧，决定"压下去需要多重的货"。
## 重力力矩 ≈ 120 × 9.81 × 0.21 ≈ 247 N·m。
const COM_LOCAL := Vector3(0.0, -0.03, -0.21)
## 转动惯量（kg·m²）。x = 绕支点轴（俯仰）。
const INERTIA_TENSOR := Vector3(72.0, 34.0, 96.0)
## 机械限位（度）。正 = 载物端抬起。
const LIMIT_DEG := 14.0
const PAN_TOP_Y := 0.125
const PAN_CENTER_Z := 1.30
const PAN_LEN := 1.50
const PAN_WIDTH := 0.80
## 触发杆：装在梁下方、靠近支点（局部 z = +0.30）的细柱。
const TRIGGER_LOCAL := Vector3(0.0, -0.146, 0.30)
const TRIGGER_SIZE := Vector3(0.08, 0.06, 0.08)
const TRIGGER_BOTTOM_Y := -0.176

var frame: StaticBody3D
var hinge: HingeJoint3D
var lever_built: bool = false
var spawn_pose: Transform3D = Transform3D.IDENTITY

var lever_angle_deg: float = 0.0
var lever_omega: float = 0.0
var pan_load_kg: float = 0.0


func _ready() -> void:
	if profile == null:
		var p: LISBodyProfile = LISBodyProfile.new()
		p.display_name = "配重杠杆"
		p.size = Vector3(0.80, 0.30, 2.35)
		p.mass_kg = LEVER_MASS
		p.friction = 0.80
		p.liftable = false
		p.can_sleep = false
		p.grip_handles = 0
		p.color = Color(0.44, 0.36, 0.24)
		p.use_custom_center_of_mass = true
		p.center_of_mass = COM_LOCAL
		p.inertia = INERTIA_TENSOR
		profile = p
	super()
	if not lever_built:
		# 支点与支架的世界坐标由**杠杆当前变换**推出，所以必须等节点进树、
		# 位置已经生效后再建（与 LISCart 同一个坑：在 _ready 里直接建会把
		# 支架与铰链放在原点，杠杆被拽住卡死，实测角度恒为 -3.24°）。
		call_deferred("_build_lever_after_transform")


func _build_lever_after_transform() -> void:
	if lever_built:
		return
	build_lever()


func build_lever() -> void:
	if lever_built:
		return
	lever_built = true
	name = "Lever"
	display_name = "配重杠杆"
	mass = LEVER_MASS
	linear_damp = 0.05
	angular_damp = 0.35
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = LISPhysics.LAYER_PROP
	collision_mask = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PLAYER | LISPhysics.LAYER_PROP
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = COM_LOCAL
	inertia = INERTIA_TENSOR
	var mat: PhysicsMaterial = PhysicsMaterial.new()
	mat.friction = 0.8
	mat.bounce = 0.0
	mat.rough = false
	physics_material_override = mat
	spawn_pose = global_transform

	_build_frame()
	_build_shapes()
	add_to_group("lis_lever")
	add_to_group(LISBody.GROUP_BODY)
	add_to_group(LISBody.GROUP_INTERACTABLE)


func _build_frame() -> void:
	# 支架必须是**静止**的：不能挂在杠杆刚体下（那样支架会跟着杠杆动，支点就不存在）。
	var host: Node3D = get_parent() as Node3D
	if host == null:
		host = Node3D.new()
		host.name = "LeverFrameHost"
		add_child(host)
	frame = StaticBody3D.new()
	frame.name = "LeverFrame"
	frame.collision_layer = LISPhysics.LAYER_WORLD
	frame.collision_mask = 0
	host.add_child(frame)
	frame.global_transform = Transform3D(global_transform.basis, global_position)

	var steel: StandardMaterial3D = _mat(Color(0.26, 0.29, 0.31), 0.55, 0.65)
	_add_box(frame, "Base", Vector3(1.5, 0.14, 0.9), Vector3(0.0, -PIVOT_HEIGHT + 0.07, 0.0), steel)
	for sx: float in [-1.0, 1.0]:
		_add_box(frame, "Post", Vector3(0.12, PIVOT_HEIGHT, 0.30),
			Vector3(sx * 0.23, -PIVOT_HEIGHT * 0.5, 0.0), steel)
	_add_box(frame, "Bearing", Vector3(0.62, 0.22, 0.26), Vector3.ZERO, steel)
	# 支架不能和杠杆碰撞：轴承座是套在杠杆外面的。
	# 历史上两者互相碰撞，导致杠杆卡死在轴承里根本转不动（实测载 24 kg 也不动）。
	frame.add_collision_exception_with(self)

	# 支点：铰链绕自身局部 Z；绕 Y 转 90° 让局部 Z 对准世界 X。
	#
	# 铰链角符号（实测标定）：关节参数 J 与刚体绕轴转角 φ 的关系是 J = −φ，
	# 刚体绕 X 转 φ 时 basis.z.y = −sin φ，所以 basis.z.y = sin J。
	# 局部 +Z 是载物端 → J = +14° 时载物端抬起。
	# 因此 lower = −LIMIT_DEG（压到底）、upper = +LIMIT_DEG（抬到底）。
	hinge = HingeJoint3D.new()
	hinge.name = "LeverAxle"
	hinge.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	frame.add_child(hinge)
	hinge.node_a = hinge.get_path_to(frame)
	hinge.node_b = hinge.get_path_to(self)
	hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-LIMIT_DEG))
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(LIMIT_DEG))
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_SOFTNESS, 0.9)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_RELAXATION, 1.0)
	# 支架（含支点铰链）必须排在杠杆刚体**之前**，保证"先拆约束、再放刚体"。
	LISJointKit.ensure_constraints_precede(self, frame)


func _build_shapes() -> void:
	var iron: StandardMaterial3D = _mat(Color(0.44, 0.36, 0.24), 0.62, 0.35)
	var dark: StandardMaterial3D = _mat(Color(0.20, 0.21, 0.23), 0.70, 0.50)
	var warn: StandardMaterial3D = _mat(Color(0.74, 0.56, 0.16), 0.60, 0.10)
	_add_box(self, "Beam", Vector3(0.12, 0.16, 2.35), Vector3(0.0, 0.0, 0.40), iron)
	_add_box(self, "CounterWeight", Vector3(0.36, 0.36, 0.34), Vector3(0.0, -0.05, -0.62), dark)
	# 载物台：顶面 = PAN_TOP_Y = 0.125（板心 0.10 + 半厚 0.025）。
	_add_box(self, "PanPlate", Vector3(PAN_WIDTH, 0.05, PAN_LEN), Vector3(0.0, 0.10, PAN_CENTER_Z), dark)
	_add_box(self, "PanRimFar", Vector3(PAN_WIDTH, 0.12, 0.04),
		Vector3(0.0, 0.18, PAN_CENTER_Z + PAN_LEN * 0.5), warn)
	for sx: float in [-1.0, 1.0]:
		_add_box(self, "PanRimSide", Vector3(0.04, 0.12, PAN_LEN),
			Vector3(sx * (PAN_WIDTH * 0.5 - 0.02), 0.18, PAN_CENTER_Z), warn)
	_add_box(self, "PanNeck", Vector3(0.16, 0.10, 0.16), Vector3(0.0, 0.03, PAN_CENTER_Z), dark)
	_add_box(self, "TriggerRod", TRIGGER_SIZE, TRIGGER_LOCAL, warn)


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


func pivot_world() -> Vector3:
	return global_position


func pan_world() -> Vector3:
	return global_transform * Vector3(0.0, PAN_TOP_Y, PAN_CENTER_Z)


## 力的作用点到支点的水平力臂（米）。用于 HUD 显示"这次压的是多长的力臂"。
func arm_length(world_point: Vector3) -> float:
	return global_position.distance_to(Vector3(world_point.x, global_position.y, world_point.z))


## 杠杆角度（度）。正 = 载物端抬起，负 = 载物端压下。
## 实测标定：刚体绕 X 转 φ 时 basis.z.y = −sin φ，铰链参数 J = −φ，
## 所以 basis.z.y = sin J → J = asin(basis.z.y)。
func angle_deg() -> float:
	var fwd: Vector3 = global_transform.basis.z
	return rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))


func omega() -> float:
	var axis: Vector3 = global_transform.basis.x.normalized()
	return angular_velocity.dot(axis)


func _physics_process(_delta: float) -> void:
	if not lever_built:
		return
	lever_angle_deg = angle_deg()
	lever_omega = omega()
	_measure_pan_load()


func _measure_pan_load() -> void:
	pan_load_kg = 0.0
	for rb: RigidBody3D in pan_cargo():
		pan_load_kg += rb.mass


## 载物台上此刻压着的刚体（按真实形状查询判定，不按名单、不吸附）。
## 查询框必须覆盖**整块台面**：只盖中心会让放在近端/远端的箱子查不到。
func pan_cargo() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return out
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(PAN_WIDTH * 0.96, 0.60, PAN_LEN * 0.96)
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = LISPhysics.LAYER_PROP
	params.exclude = [get_rid()]
	params.transform = Transform3D(global_transform.basis,
		global_transform * Vector3(0.0, PAN_TOP_Y + 0.30, PAN_CENTER_Z))
	for hit: Dictionary in space.intersect_shape(params, 12):
		var rb: RigidBody3D = hit.get("collider") as RigidBody3D
		if rb == null or rb == self:
			continue
		if rb is LISCart:
			continue
		if out.has(rb):
			continue
		out.append(rb)
	return out


## 绕支点的重力力矩（N·m）。符号约定：**正 = 把载物端压下**。
## 重心在配重侧（局部 z < 0），所以杠杆自重把载物端抬起 → 重力力矩为负；
## 货物力矩为正。合力矩 > 0 就压得动。
func gravity_torque() -> float:
	var com_world: Vector3 = global_transform * center_of_mass
	var r: Vector3 = com_world - global_position
	var weight: Vector3 = Vector3(0.0, -mass * 9.81 * gravity_scale, 0.0)
	var t: Vector3 = r.cross(weight)
	var axis: Vector3 = global_transform.basis.x.normalized()
	return t.dot(axis)


## 货物对支点的力矩（N·m）。正 = 把载物端压下。
func load_torque(cargo: Array) -> float:
	var total: float = 0.0
	var axis: Vector3 = global_transform.basis.x.normalized()
	for c: Variant in cargo:
		var rb: RigidBody3D = c as RigidBody3D
		if rb == null:
			continue
		var r: Vector3 = rb.global_position - global_position
		var weight: Vector3 = Vector3(0.0, -rb.mass * 9.81, 0.0)
		total += r.cross(weight).dot(axis)
	return total


## 复位：把杠杆搬回支点原始位姿。支架不动，约束几何自动一致。
func reset_lever() -> void:
	if not lever_built:
		return
	sleeping = false
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = spawn_pose
	clear_holders()


## 安全销毁：先拆铰链再释放刚体。
func despawn() -> void:
	clear_holders()
	if hinge != null and is_instance_valid(hinge):
		LISJointKit.teardown(hinge)
		hinge = null
	if frame != null and is_instance_valid(frame):
		frame.queue_free()
		frame = null
	queue_free()


func snapshot() -> Dictionary:
	var d: Dictionary = super()
	d["angle"] = lever_angle_deg
	return d
