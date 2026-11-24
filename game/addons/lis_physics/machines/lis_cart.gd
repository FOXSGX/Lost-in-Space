class_name LISCart
extends LISBody
## LIS Physics SDK · 真实车轮推车（四轮独立刚体 + 轮轴铰链）
##
## 与"按车速播放车轮动画"的旧实现根本区别：
##   * 四个独立 RigidBody3D 车轮，各自通过 HingeJoint3D 约束在车身上；
##   * 车轮与地面是真实接触，滚动由接触摩擦产生；
##   * 没有一行代码设置车身或车轮的位置 / 速度 / 旋转（复位除外）。
##
## 结构（build() 运行时搭建，场景里只需一个空节点）：
##
##   Station (Node3D, 静态)
##   ├── Cart (LISCart ← 车身刚体，可被抓握/推挤)
##   └── CartWheelRig (Node3D, 静态容器)
##       ├── WheelFL/FR/RL/RR (RigidBody3D, 圆柱碰撞体)
##       └── AxleFL/FR/RL/RR (HingeJoint3D, 轴沿车身 X)
##
## 为什么车轮不能是车身的子节点：Node3D 层级会把父刚体的 transform 传播给子刚体，
## 两个刚体争夺同一个 transform 会互相拉扯。所以车轮与铰链挂在静态容器下，
## 只有铰链约束它们与车身的相对位置。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_cart.gd

const VERSION_TAG := "LIS 1.0.0-rc1"
const GROUP_CART := "lis_cart"

# --- 几何（米）-----------------------------------------------------------
const DECK_W := 1.06
const DECK_T := 0.16
const DECK_L := 1.52
const BODY_Y := 0.60
const WHEEL_RADIUS := 0.26
const WHEEL_WIDTH := 0.13
const WHEEL_X := 0.465
const WHEEL_Z := 0.55
const AXLE_Y := 0.26

# --- 质量（千克）---------------------------------------------------------
const CHASSIS_MASS := 86.0
const WHEEL_MASS := 6.0

# --- 摩擦与阻尼 ----------------------------------------------------------
## 轮胎摩擦（高于地面 0.85）：接触摩擦由轮胎一侧决定，能抓住地面滚起来。
const WHEEL_FRICTION := 1.15
const DECK_FRICTION := 0.72
## 轮轴轴承阻尼。这是"滚动阻力"的物理来源：只作用于车轮角速度，
## 车轮不转（锁死/打滑）时不会凭空消耗平动能量。
const BEARING_DAMP := 0.18
const CHASSIS_LINEAR_DAMP := 0.02
const CHASSIS_ANGULAR_DAMP := 0.25

var wheel_bodies: Array[RigidBody3D] = []
var axles: Array[HingeJoint3D] = []
var wheel_rig: Node3D
var wheel_local: Array[Vector3] = []
var wheel_names: Array[String] = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]
var base_color: Color = Color(0.52, 0.44, 0.24)
var cart_built: bool = false
var cart_mirror: bool = false

# --- 遥测（全部读自物理引擎）---------------------------------------------
var telemetry_speed: float = 0.0
var telemetry_forward_speed: float = 0.0
var telemetry_wheel_spin: float = 0.0
var telemetry_grounded_wheels: int = 0
var telemetry_tilt: float = 0.0
var telemetry_slip_ratio: float = 0.0

var _mirror_travel: float = 0.0
var _mirror_last: Vector3 = Vector3.ZERO


func _ready() -> void:
	if profile == null:
		var p: LISBodyProfile = LISBodyProfile.new()
		p.display_name = "推车"
		p.size = Vector3(DECK_W, DECK_T, DECK_L)
		p.mass_kg = CHASSIS_MASS
		p.friction = DECK_FRICTION
		p.liftable = false
		p.grip_handles = 0
		p.color = base_color
		p.can_sleep = true
		p.contact_monitor = true
		p.max_contacts = 8
		profile = p
	super()
	if not cart_built:
		# 关键：车轮的世界坐标由**车身当前变换**推出，所以必须等节点进树、
		# 位置已经生效之后才建轮子。否则轮心会落在 (0,0,0) 附近的地面以下
		# （实测轮心 y=-0.487，四个车轮全部埋进地里，推车贴地滑行且轮子不转）。
		call_deferred("_build_cart_after_transform")


## 延迟到变换生效后再建（见 _ready 的说明）。
func _build_cart_after_transform() -> void:
	if cart_built:
		return
	build_cart()


## 搭建车轮与轮轴。可重复调用（幂等）。
func build_cart() -> void:
	if cart_built:
		return
	cart_built = true
	name = "Cart"
	display_name = "推车"
	mass = CHASSIS_MASS
	linear_damp = CHASSIS_LINEAR_DAMP
	angular_damp = CHASSIS_ANGULAR_DAMP
	can_sleep = true
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = LISPhysics.LAYER_PROP
	collision_mask = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PLAYER | LISPhysics.LAYER_PROP
	var mat: PhysicsMaterial = PhysicsMaterial.new()
	mat.friction = DECK_FRICTION
	mat.bounce = 0.0
	mat.rough = false
	physics_material_override = mat

	# 车轮与轮轴必须在**车身位置已定**之后再建：轮心世界坐标由车身变换推出，
	# 顺序颠倒会让轮子落在地面以下（实测轮心 y=-0.487，整车陷进地里）。
	_build_chassis_shapes()
	_build_chassis_visual()
	_build_wheels()
	add_to_group(GROUP_CART)
	add_to_group(LISBody.GROUP_BODY)
	add_to_group(LISBody.GROUP_INTERACTABLE)
	_mirror_last = global_position


func _build_chassis_shapes() -> void:
	# 车身本体：货台
	var body_shape: CollisionShape3D = CollisionShape3D.new()
	body_shape.name = "ChassisShape"
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = Vector3(DECK_W, DECK_T, DECK_L)
	body_shape.shape = bs
	add_child(body_shape)
	# 侧栏：真实矮挡板，装货时挡住箱子不往两侧滑。
	# 用独立碰撞体而不是把货台做厚 —— 货台越厚重心越高、越容易侧翻。
	for sx: float in [-1.0, 1.0]:
		var rail: CollisionShape3D = CollisionShape3D.new()
		rail.name = "RailShape"
		var rbs: BoxShape3D = BoxShape3D.new()
		rbs.size = Vector3(0.04, 0.18, DECK_L * 0.92)
		rail.shape = rbs
		rail.position = Vector3(sx * (DECK_W * 0.5 - 0.02), DECK_T * 0.5 + 0.09, 0.0)
		add_child(rail)


func _build_chassis_visual() -> void:
	var steel: StandardMaterial3D = _mat(base_color, 0.62, 0.35)
	var dark: StandardMaterial3D = _mat(Color(0.18, 0.19, 0.20), 0.70, 0.50)
	var accent: StandardMaterial3D = _mat(Color(0.72, 0.55, 0.16), 0.65, 0.10)
	_add_box(self, "Deck", Vector3(DECK_W, DECK_T, DECK_L), Vector3.ZERO, steel)
	_add_box(self, "DeckLine", Vector3(DECK_W * 0.88, 0.006, 0.06),
		Vector3(0.0, DECK_T * 0.5 + 0.004, 0.0), dark)
	for sx: float in [-1.0, 1.0]:
		_add_box(self, "Rail", Vector3(0.04, 0.18, DECK_L * 0.92),
			Vector3(sx * (DECK_W * 0.5 - 0.02), DECK_T * 0.5 + 0.09, 0.0), dark)
	# 后推杆：玩家用身体顶住它推车。高度低于重心翻倒临界，高于膝盖。
	_add_box(self, "PushBar", Vector3(DECK_W * 0.96, 0.05, 0.05),
		Vector3(0.0, 0.20, DECK_L * 0.5 - 0.02), accent)
	for sx: float in [-1.0, 1.0]:
		_add_box(self, "PushPost", Vector3(0.05, 0.20, 0.05),
			Vector3(sx * DECK_W * 0.44, 0.11, DECK_L * 0.5 - 0.02), dark)
	for sz: float in [-1.0, 1.0]:
		_add_box(self, "AxleBeam", Vector3(DECK_W * 0.98, 0.05, 0.06),
			Vector3(0.0, -DECK_T * 0.5 - 0.01, sz * WHEEL_Z), dark)


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _add_box(parent: Node3D, label: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = label
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_wheels() -> void:
	var host: Node3D = get_parent() as Node3D
	if host == null:
		push_error("[LIS Physics] LISCart 必须挂在一个 Node3D 下（车轮需要独立刚体）")
		return
	wheel_rig = Node3D.new()
	wheel_rig.name = "CartWheelRig"
	host.add_child(wheel_rig)
	wheel_rig.global_transform = Transform3D(global_transform.basis, global_position)

	var tire: StandardMaterial3D = _mat(Color(0.10, 0.11, 0.12), 0.92, 0.0)
	var hub: StandardMaterial3D = _mat(Color(0.62, 0.64, 0.68), 0.35, 0.85)
	var spoke: StandardMaterial3D = _mat(Color(0.80, 0.62, 0.20), 0.55, 0.30)

	var i: int = 0
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var local: Vector3 = Vector3(sx * WHEEL_X, AXLE_Y - BODY_Y, sz * WHEEL_Z)
			var wheel: RigidBody3D = RigidBody3D.new()
			wheel.name = wheel_names[i]
			wheel.mass = WHEEL_MASS
			wheel.gravity_scale = 1.0
			wheel.linear_damp = 0.01
			wheel.angular_damp = BEARING_DAMP
			wheel.continuous_cd = true
			wheel.can_sleep = true
			wheel.collision_layer = LISPhysics.LAYER_PROP
			wheel.collision_mask = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PLAYER | LISPhysics.LAYER_PROP
			var wmat: PhysicsMaterial = PhysicsMaterial.new()
			wmat.friction = WHEEL_FRICTION
			wmat.bounce = 0.0
			wmat.rough = false
			wheel.physics_material_override = wmat
			wheel_rig.add_child(wheel)
			wheel.position = local

			# 真实车轮碰撞体：圆柱，轴沿车身 X（横置），因此只能绕 X 滚。
			var cs: CollisionShape3D = CollisionShape3D.new()
			cs.name = "WheelShape"
			var cyl: CylinderShape3D = CylinderShape3D.new()
			cyl.radius = WHEEL_RADIUS
			cyl.height = WHEEL_WIDTH
			cs.shape = cyl
			cs.rotation = Vector3(0.0, 0.0, PI * 0.5)
			wheel.add_child(cs)

			# 视觉全部挂在车轮刚体上：轮子怎么转是物理转的，没有动画。
			var tire_mesh: MeshInstance3D = MeshInstance3D.new()
			tire_mesh.name = "Tire"
			var cm: CylinderMesh = CylinderMesh.new()
			cm.top_radius = WHEEL_RADIUS
			cm.bottom_radius = WHEEL_RADIUS
			cm.height = WHEEL_WIDTH
			cm.radial_segments = 24
			tire_mesh.mesh = cm
			tire_mesh.material_override = tire
			tire_mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
			wheel.add_child(tire_mesh)

			var hub_mesh: MeshInstance3D = MeshInstance3D.new()
			hub_mesh.name = "Hub"
			var hm: CylinderMesh = CylinderMesh.new()
			hm.top_radius = 0.095
			hm.bottom_radius = 0.095
			hm.height = WHEEL_WIDTH + 0.01
			hm.radial_segments = 16
			hub_mesh.mesh = hm
			hub_mesh.material_override = hub
			hub_mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
			wheel.add_child(hub_mesh)

			# 轮辐：让"车轮真的在转"在画面上可读（也是截图验证的判据）。
			for side: float in [-1.0, 1.0]:
				var z_off: float = side * (WHEEL_WIDTH * 0.5 + 0.004)
				_add_box(wheel, "Spoke", Vector3(0.018, WHEEL_RADIUS * 1.55, 0.026),
					Vector3(0.0, 0.0, z_off), spoke)
				_add_box(wheel, "Spoke", Vector3(0.018, 0.026, WHEEL_RADIUS * 1.55),
					Vector3(0.0, 0.0, z_off), spoke)

			# 车与自己的车轮之间不互相碰撞（轮子上半部藏在货台侧下方）。
			add_collision_exception_with(wheel)
			wheel.add_collision_exception_with(self)

			wheel_bodies.append(wheel)
			wheel_local.append(local)
			i += 1

	# 轮轴：HingeJoint3D 绕自身局部 Z；绕 Y 转 90° 让局部 Z 对准世界 X。
	# 不加马达、不加限位 —— 车轮完全自由转动，转速由接触摩擦决定。
	#
	# 顺序很重要：**先 add_child，再设 global_transform**。
	# 节点未进树时 global_transform 的 setter 等价于直接写 local transform，
	# 于是"轮心世界坐标"会被当成"相对 WheelRig 的局部坐标"，轴心高出 0.6 m。
	for k in range(wheel_bodies.size()):
		var wheel: RigidBody3D = wheel_bodies[k]
		var axle: HingeJoint3D = HingeJoint3D.new()
		axle.name = "Axle" + wheel_names[k].substr(5)
		wheel_rig.add_child(axle)
		var basis: Basis = global_transform.basis * Basis(Vector3.UP, PI * 0.5)
		axle.global_transform = Transform3D(basis, wheel.global_position)
		axle.node_a = axle.get_path_to(self)
		axle.node_b = axle.get_path_to(wheel)
		axle.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
		axles.append(axle)
	LISJointKit.order_joints_first(wheel_rig)
	# 车轮容器（含四个轮轴铰链）必须排在车身**之前**。
	# 引擎按同级顺序拆除：若车身先被释放、引用它的铰链后释放，
	# Jolt 的约束对象会指向已释放内存 → 进程退出时 0xC0000005。
	LISJointKit.ensure_constraints_precede(self, wheel_rig)


# ---------------------------------------------------------------------------
# 遥测
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not cart_built:
		return
	telemetry_speed = linear_velocity.length()
	var fwd: Vector3 = -global_transform.basis.z
	telemetry_forward_speed = linear_velocity.dot(fwd)
	telemetry_wheel_spin = average_wheel_spin()
	telemetry_tilt = rad_to_deg(acos(clampf(global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))
	telemetry_grounded_wheels = grounded_wheel_count()
	telemetry_slip_ratio = slip_ratio()
	if cart_mirror:
		_mirror_wheel_visual()


## 四个车轮绕各自轮轴的平均角速度（rad/s，正 = 向前滚）。
##
## 符号推导（实测校核）：车身前向是 basis 的 −Z，轮轴沿 basis 的 +X。
## 车轮向前滚时轮顶向 −Z 移动，角速度矢量必须沿 −X
## （ω×r 中 r 为轮顶 +Y，ω=(ωx,0,0) 给出 v=(0,0,ωx·r)，要 v_z<0 就得 ωx<0）。
## 所以"向前滚"对应 ω·axis 为负；这里取负号让返回值正 = 向前滚。
func average_wheel_spin() -> float:
	if wheel_bodies.is_empty():
		return 0.0
	var axis: Vector3 = global_transform.basis.x.normalized()
	var total: float = 0.0
	for w: RigidBody3D in wheel_bodies:
		if not is_instance_valid(w):
			continue
		total += -w.angular_velocity.dot(axis)
	return total / float(wheel_bodies.size())


func wheel_spin_list() -> Array[float]:
	var out: Array[float] = []
	var axis: Vector3 = global_transform.basis.x.normalized()
	for w: RigidBody3D in wheel_bodies:
		out.append(0.0 if not is_instance_valid(w) else -w.angular_velocity.dot(axis))
	return out


## 纯滚动时 ω·r 应等于前进速度：
##   ≈ 0    纯滚动
##   ≈ −1   车轮不转、车身在滑（"会滑行的箱子"）
##   > 0    车轮打滑空转（冰面上猛推）
func slip_ratio() -> float:
	var v: float = telemetry_forward_speed
	var surface: float = average_wheel_spin() * WHEEL_RADIUS
	return (surface - v) / maxf(absf(v), 0.25)


## 车轮与地面是否真实接触：从每个轮心向下打射线。
func grounded_wheel_count() -> int:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return 0
	var count: int = 0
	for w: RigidBody3D in wheel_bodies:
		if not is_instance_valid(w):
			continue
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
		q.from = w.global_position
		q.to = w.global_position + Vector3.DOWN * (WHEEL_RADIUS + 0.06)
		q.collision_mask = LISPhysics.LAYER_WORLD
		q.exclude = [w.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			var d: float = w.global_position.distance_to(hit.get("position") as Vector3)
			if d <= WHEEL_RADIUS + 0.035:
				count += 1
	return count


func is_grounded() -> bool:
	return grounded_wheel_count() >= 2


## 系统重心（车身 + 四轮 + 货台货物），世界坐标。
func system_center_of_mass(cargo: Array[Node3D] = []) -> Vector3:
	var total_mass: float = mass + WHEEL_MASS * float(wheel_bodies.size())
	var moment: Vector3 = global_position * mass
	for w: RigidBody3D in wheel_bodies:
		if is_instance_valid(w):
			moment += w.global_position * WHEEL_MASS
	for c: Node3D in cargo:
		if not is_instance_valid(c):
			continue
		var rb: RigidBody3D = c as RigidBody3D
		if rb == null:
			continue
		moment += c.global_position * rb.mass
		total_mass += rb.mass
	return moment / maxf(total_mass, 0.001)


## 货台上此刻压着哪些刚体（按真实形状查询，不按名单）。
func cargo_on_deck(space: PhysicsDirectSpaceState3D = null) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var st: PhysicsDirectSpaceState3D = space
	if st == null:
		st = get_world_3d().direct_space_state
	if st == null:
		return out
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(DECK_W * 0.94, 0.42, DECK_L * 0.94)
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = LISPhysics.LAYER_PROP
	params.exclude = [get_rid()]
	var center: Vector3 = global_transform * Vector3(0.0, DECK_T * 0.5 + 0.22, 0.0)
	params.transform = Transform3D(global_transform.basis, center)
	for hit: Dictionary in st.intersect_shape(params, 12):
		var col: Object = hit.get("collider")
		var rb: RigidBody3D = col as RigidBody3D
		if rb == null or rb == self or wheel_bodies.has(rb) or out.has(rb):
			continue
		out.append(rb)
	return out


# ---------------------------------------------------------------------------
# 复位 / 镜像 / 销毁
# ---------------------------------------------------------------------------

## 整体复位：车身、车轮、轮轴容器一起搬，保持约束几何一致。
## 只搬位姿、清速度；不改质量、不改摩擦、不冻结任何东西。
##
## 关键：车轮是独立刚体，改 wheel_rig 的 transform **不会**带走它们。
## 必须逐个显式搬，否则铰链会把两者硬拽到一起并让后续读数全部失真。
func reset_pose(world_pos: Vector3, yaw: float = 0.0) -> void:
	if not cart_built:
		return
	var basis: Basis = Basis(Vector3.UP, yaw)
	var pose: Transform3D = Transform3D(basis, world_pos)
	sleeping = false
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = pose
	if wheel_rig != null and is_instance_valid(wheel_rig):
		wheel_rig.global_transform = pose
	for i in range(wheel_bodies.size()):
		var w: RigidBody3D = wheel_bodies[i]
		if not is_instance_valid(w):
			continue
		w.freeze = false
		w.sleeping = false
		w.linear_velocity = Vector3.ZERO
		w.angular_velocity = Vector3.ZERO
		w.global_transform = Transform3D(basis, pose * wheel_local[i])
	_mirror_travel = 0.0
	_mirror_last = world_pos
	clear_holders()


func enable_mirror(enabled: bool) -> void:
	super(enabled)
	cart_mirror = enabled
	for w: RigidBody3D in wheel_bodies:
		if not is_instance_valid(w):
			continue
		w.freeze = enabled
		w.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_mirror_last = global_position


## 镜像端：车轮视觉按主机位移转动。
## 这只发生在非权威端，且方向/速度完全由主机位姿决定；
## 权威端的车轮旋转永远来自铰链 + 接触摩擦。
func _mirror_wheel_visual() -> void:
	var delta: Vector3 = global_position - _mirror_last
	_mirror_last = global_position
	var fwd: Vector3 = -global_transform.basis.z
	_mirror_travel += delta.dot(fwd) / WHEEL_RADIUS
	for i in range(wheel_bodies.size()):
		var w: RigidBody3D = wheel_bodies[i]
		if not is_instance_valid(w):
			continue
		var local: Vector3 = wheel_local[i]
		var spin: Basis = Basis(global_transform.basis.x.normalized(), _mirror_travel)
		w.global_transform = Transform3D(
			spin * global_transform.basis, global_transform * local)


## 安全销毁：先拆轮轴，再释放车轮，最后释放车身。
func despawn() -> void:
	clear_holders()
	_teardown_axles()
	for w: RigidBody3D in wheel_bodies:
		if is_instance_valid(w):
			w.queue_free()
	wheel_bodies.clear()
	if wheel_rig != null and is_instance_valid(wheel_rig):
		wheel_rig.queue_free()
		wheel_rig = null
	queue_free()


## 拆掉四个轮轴铰链（可重复调用）。
func _teardown_axles() -> void:
	for a: HingeJoint3D in axles:
		if is_instance_valid(a):
			LISJointKit.teardown(a)
	axles.clear()


## 离开场景时必须先拆轮轴。
##
## 【为什么必须在这里做】
## 轮轴铰链挂在 CartWheelRig 下，而 CartWheelRig 是车身的**兄弟节点**。
## Godot 释放父节点时按子节点顺序释放：先释放车身（刚体）→ 再释放
## CartWheelRig 里的铰链。此时 Jolt 的约束对象仍指向已释放的车身 →
## 进程退出时 **0xC0000005 访问冲突**（性能基准工具实测就在这里崩的）。
##
## 显式在 _exit_tree 里先把铰链摘掉，销毁顺序就变成"先拆约束、再放刚体"，
## 正是物理引擎要求的顺序。这不改变任何物理参数。
func _exit_tree() -> void:
	_teardown_axles()


func snapshot() -> Dictionary:
	var d: Dictionary = super()
	d["wheel_spin"] = wheel_spin_list()
	return d


func describe() -> String:
	return "推车 %.0f kg · %.1f m/s · 触地轮 %d/4" % [
		mass + WHEEL_MASS * float(wheel_bodies.size()), telemetry_speed, telemetry_grounded_wheels]
