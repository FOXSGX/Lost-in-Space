class_name LISWinchDrum
extends LISBody
## LIS Physics SDK · 真实绞盘卷筒
##
## 结构：
##   WinchFrame (StaticBody3D, 静态，兄弟节点)
##   ├── Base / Post ×2 / Bearing
##   └── Axle (HingeJoint3D, 轴沿世界 X)
##
##   Drum (LISWinchDrum ← 刚体, 38 kg)
##   ├── Barrel   圆柱 r=0.22 h=0.30（真实碰撞，绳绕在这里）
##   ├── Flange ×2 侧盘
##   └── Crank + Handle  手柄（玩家可抓握施力）
##
## 力学：
##   * 电机：目标角速度 + 力矩上限（PI 速度环 + 积分解饱和）
##   * 制动：库仑式摩擦制动（前馈抵消负载力矩 + 粘滞刹停），有上限
##   * 绳索反作用：由 LISCable 在切点施加真实力 → 力矩 τ = R × F
## 没有任何一行代码写卷筒的 transform 或角度（复位除外）。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_winch_drum.gd

const DRUM_RADIUS := 0.22
const DRUM_WIDTH := 0.30
const DRUM_MASS := 38.0
const MOTOR_TORQUE := 70.0
const MOTOR_OMEGA := 2.0
## 制动力矩上限（N·m）。要能托住 40 kg 负载：T·R = 40·9.81·0.22 ≈ 86 N·m。
const BRAKE_TORQUE := 320.0
const CRANK_ARM := 0.30
const AXLE_HEIGHT := 0.95

var frame: StaticBody3D
var axle: HingeJoint3D
var drum_built: bool = false
var spawn_pose: Transform3D = Transform3D()

# --- 遥测（全部读自引擎）-------------------------------------------------
var angle_rad: float = 0.0
var omega: float = 0.0
var angle_delta: float = 0.0
var motor_on: bool = false
var brake_on: bool = true
var motor_target_omega: float = 0.0
## 收绳方向（由缆绳 finalize 写入）：+1 = 正角速度即收绳。
var wind_sign: float = 1.0
## 力矩上限（默认 MOTOR_TORQUE；可调低以验证真实堵转）。
var torque_limit: float = MOTOR_TORQUE
var motor_output_torque: float = 0.0
var brake_output_torque: float = 0.0

# --- 能量账本（每个物理步用同一时刻的 τ 与 ω 累加，有符号）-----------------
var motor_work: float = 0.0
var motor_work_drive: float = 0.0
var motor_work_regen: float = 0.0
var brake_work: float = 0.0
var manual_work: float = 0.0

var _prev_tau: float = 0.0
var _prev_brake_tau: float = 0.0
var _prev_omega: float = 0.0
var _motor_i: float = 0.0
var _has_prev: bool = false
var _last_angle: float = 0.0
var _unwrapped: float = 0.0
var _angle_started: bool = false


func _ready() -> void:
	if profile == null:
		var p: LISBodyProfile = LISBodyProfile.new()
		p.display_name = "绞盘卷筒"
		p.size = Vector3(0.70, 0.70, 0.70)
		p.mass_kg = DRUM_MASS
		p.friction = 0.60
		p.liftable = false
		p.can_sleep = false
		p.grip_handles = 0
		p.color = Color(0.34, 0.37, 0.40)
		profile = p
	super()
	if not drum_built:
		build_drum()


func build_drum() -> void:
	if drum_built:
		return
	drum_built = true
	name = "Drum"
	display_name = "绞盘卷筒"
	mass = DRUM_MASS
	linear_damp = 0.2
	angular_damp = 0.25          # 轴承阻尼（很小，卷筒应当容易转）
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 6
	collision_layer = LISPhysics.LAYER_PROP
	collision_mask = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PLAYER | LISPhysics.LAYER_PROP
	var mat: PhysicsMaterial = PhysicsMaterial.new()
	mat.friction = 0.6
	mat.bounce = 0.0
	mat.rough = false
	physics_material_override = mat
	spawn_pose = global_transform
	_build_shapes()
	_build_frame()
	add_to_group(LISBody.GROUP_BODY)
	add_to_group(LISBody.GROUP_INTERACTABLE)


func _build_shapes() -> void:
	var steel: StandardMaterial3D = _mat(Color(0.34, 0.37, 0.40), 0.50, 0.60)
	var dark: StandardMaterial3D = _mat(Color(0.16, 0.17, 0.19), 0.80, 0.10)
	var rope_mat: StandardMaterial3D = _mat(Color(0.72, 0.62, 0.38), 0.90, 0.05)
	var crank_mat: StandardMaterial3D = _mat(Color(0.74, 0.56, 0.16), 0.55, 0.30)

	var barrel: MeshInstance3D = MeshInstance3D.new()
	barrel.name = "Barrel"
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = DRUM_RADIUS
	cm.bottom_radius = DRUM_RADIUS
	cm.height = DRUM_WIDTH
	cm.radial_segments = 24
	barrel.mesh = cm
	barrel.material_override = steel
	barrel.rotation = Vector3(0.0, 0.0, PI * 0.5)
	add_child(barrel)
	var bcs: CollisionShape3D = CollisionShape3D.new()
	var cyl: CylinderShape3D = CylinderShape3D.new()
	cyl.radius = DRUM_RADIUS
	cyl.height = DRUM_WIDTH
	bcs.shape = cyl
	bcs.rotation = Vector3(0.0, 0.0, PI * 0.5)
	add_child(bcs)

	for sx: float in [-1.0, 1.0]:
		var flange: MeshInstance3D = MeshInstance3D.new()
		var fm: CylinderMesh = CylinderMesh.new()
		fm.top_radius = DRUM_RADIUS + 0.06
		fm.bottom_radius = DRUM_RADIUS + 0.06
		fm.height = 0.04
		fm.radial_segments = 24
		flange.mesh = fm
		flange.material_override = dark
		flange.rotation = Vector3(0.0, 0.0, PI * 0.5)
		flange.position = Vector3(sx * (DRUM_WIDTH * 0.5 + 0.02), 0.0, 0.0)
		add_child(flange)
		var fcs: CollisionShape3D = CollisionShape3D.new()
		var fcyl: CylinderShape3D = CylinderShape3D.new()
		fcyl.radius = DRUM_RADIUS + 0.06
		fcyl.height = 0.04
		fcs.shape = fcyl
		fcs.rotation = Vector3(0.0, 0.0, PI * 0.5)
		fcs.position = Vector3(sx * (DRUM_WIDTH * 0.5 + 0.02), 0.0, 0.0)
		add_child(fcs)

	# 手柄：曲柄臂 + 握把（玩家可抓这里手动施力）
	var arm: MeshInstance3D = MeshInstance3D.new()
	arm.name = "CrankArm"
	var am: BoxMesh = BoxMesh.new()
	am.size = Vector3(0.06, CRANK_ARM, 0.06)
	arm.mesh = am
	arm.material_override = crank_mat
	arm.position = Vector3(DRUM_WIDTH * 0.5 + 0.10, CRANK_ARM * 0.5, 0.0)
	add_child(arm)
	var acs: CollisionShape3D = CollisionShape3D.new()
	var abs_: BoxShape3D = BoxShape3D.new()
	abs_.size = Vector3(0.06, CRANK_ARM, 0.06)
	acs.shape = abs_
	acs.position = Vector3(DRUM_WIDTH * 0.5 + 0.10, CRANK_ARM * 0.5, 0.0)
	add_child(acs)

	var handle: MeshInstance3D = MeshInstance3D.new()
	handle.name = "Handle"
	var hm: CylinderMesh = CylinderMesh.new()
	hm.top_radius = 0.035
	hm.bottom_radius = 0.035
	hm.height = 0.20
	hm.radial_segments = 12
	handle.mesh = hm
	handle.material_override = dark
	handle.rotation = Vector3(0.0, 0.0, PI * 0.5)
	handle.position = Vector3(DRUM_WIDTH * 0.5 + 0.18, CRANK_ARM, 0.0)
	add_child(handle)
	var hcs: CollisionShape3D = CollisionShape3D.new()
	var hcyl: CylinderShape3D = CylinderShape3D.new()
	hcyl.radius = 0.035
	hcyl.height = 0.20
	hcs.shape = hcyl
	hcs.rotation = Vector3(0.0, 0.0, PI * 0.5)
	hcs.position = Vector3(DRUM_WIDTH * 0.5 + 0.18, CRANK_ARM, 0.0)
	add_child(hcs)

	# 卷筒上的绕绳（视觉：几圈绳，跟着卷筒转）
	var coil: MeshInstance3D = MeshInstance3D.new()
	var com: CylinderMesh = CylinderMesh.new()
	com.top_radius = DRUM_RADIUS + 0.012
	com.bottom_radius = DRUM_RADIUS + 0.012
	com.height = DRUM_WIDTH * 0.92
	com.radial_segments = 20
	coil.mesh = com
	coil.material_override = rope_mat
	coil.rotation = Vector3(0.0, 0.0, PI * 0.5)
	add_child(coil)


func _build_frame() -> void:
	var host: Node3D = get_parent() as Node3D
	if host == null:
		push_error("[LIS Physics] LISWinchDrum 必须挂在 Node3D 下（需要静态支架）")
		return
	frame = StaticBody3D.new()
	frame.name = "WinchFrame"
	frame.collision_layer = LISPhysics.LAYER_WORLD
	frame.collision_mask = 0
	host.add_child(frame)
	frame.global_transform = spawn_pose

	var steel: StandardMaterial3D = _mat(Color(0.26, 0.29, 0.31), 0.55, 0.65)
	_add_box(frame, "Base", Vector3(1.30, 0.12, 0.80), Vector3(0.0, -AXLE_HEIGHT + 0.06, 0.0), steel)
	for sx: float in [-1.0, 1.0]:
		_add_box(frame, "Post", Vector3(0.10, AXLE_HEIGHT, 0.26),
			Vector3(sx * 0.26, -AXLE_HEIGHT * 0.5, 0.0), steel)
	_add_box(frame, "Bearing", Vector3(0.62, 0.18, 0.22), Vector3.ZERO, steel)

	axle = HingeJoint3D.new()
	axle.name = "Axle"
	axle.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	frame.add_child(axle)
	axle.node_a = axle.get_path_to(frame)
	axle.node_b = axle.get_path_to(self)
	# 卷筒必须能连续转：显式关掉铰链角度限制。
	axle.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	# 支架（含轴承铰链）必须排在卷筒刚体**之前**，保证"先拆约束、再放刚体"。
	LISJointKit.ensure_constraints_precede(self, frame)


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


func axis_world() -> Vector3:
	return global_transform.basis.x.normalized()


## 绕铰链轴的转角（弧度，右手绕 axis_world 正向）。
##
## 不能用 atan2(up.z, up.y)：卷筒整体被转过 90°、轴指向世界 −Z，
## 此时局部 Y 是在世界 XY 平面里转的，up.z 恒为 0 —— 角度永远读 0，
## 可用绳长不变，绳子被无限拉长、张力顶到上限、卷筒自己飞转。
func axis_angle() -> float:
	var axis: Vector3 = axis_world()
	var u: Vector3 = Vector3.UP - axis * Vector3.UP.dot(axis)
	if u.length() < 0.01:
		u = Vector3.RIGHT - axis * Vector3.RIGHT.dot(axis)
	u = u.normalized()
	var v: Vector3 = axis.cross(u)
	var ref: Vector3 = (global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	return atan2(ref.dot(v), ref.dot(u))


## 卷筒转角（弧度，已展开多圈）。
func update_telemetry() -> void:
	var raw: float = axis_angle()
	if not _angle_started:
		# 第一帧只记录参考角：否则开局就凭空放出 0.35 m 绳长，绳子直接松掉。
		_angle_started = true
		_last_angle = raw
	_unwrapped += wrapf(raw - _last_angle, -PI, PI)
	_last_angle = raw
	angle_rad = _unwrapped
	omega = angular_velocity.dot(axis_world())


func set_motor(on: bool, target_omega: float = MOTOR_OMEGA) -> void:
	motor_on = on
	motor_target_omega = clampf(target_omega, -MOTOR_OMEGA, MOTOR_OMEGA) if on else 0.0


func set_brake(on: bool) -> void:
	brake_on = on


## 每物理帧由场景调用（在 LISCable 求解之后，才能用上最新张力与转速）。
## load_torque = 缆绳刚作用到卷筒上的力矩（N·m）。制动器用它做前馈：
## 真正的摩擦制动器能提供"静态保持力矩"，纯粘性阻尼在 ω=0 时一点力矩都没有，
## 托不住负载 —— 这正是第一次实测里 24 kg 负载把卷筒拖着反向转的原因。
func drive(delta: float, load_torque: float = 0.0) -> void:
	update_telemetry()
	# 用**上一物理步**的功按中点角速度结算：电机 P 增益很大，
	# 一帧内 ω 可变化 ~1 rad/s，用步首 ω 积分会产生 25% 的系统性偏差。
	if _has_prev:
		var w_mid: float = 0.5 * (_prev_omega + omega)
		var dw_m: float = _prev_tau * w_mid * delta
		motor_work += dw_m
		if dw_m >= 0.0:
			motor_work_drive += dw_m
		else:
			motor_work_regen += -dw_m
		brake_work += maxf(0.0, -_prev_brake_tau * w_mid * delta)
	_prev_omega = omega
	_has_prev = true
	var axis: Vector3 = axis_world()

	# 电机：限速 + 限矩
	motor_output_torque = 0.0
	_prev_tau = 0.0
	if not motor_on:
		_motor_i = 0.0
	if motor_on:
		var err: float = motor_target_omega * wind_sign - omega
		# 速度环 = PI。Kp 取 I/dt 的 0.9 倍（临界增益，不在目标转速附近打摆），
		# Ki 用 Ti=0.5 s 积分时间，积分项带抗饱和夹紧。
		var kp: float = _axis_inertia() / maxf(delta, 0.0001) * 0.9
		var ki: float = kp / 0.5
		_motor_i = clampf(_motor_i + err * ki * delta, -torque_limit * 0.8, torque_limit * 0.8)
		var tau: float = clampf(err * kp + _motor_i, -torque_limit, torque_limit)
		# 超过目标转速时进入发电制动（力矩反向），这才是真正的限速。
		if (omega - motor_target_omega * wind_sign) * wind_sign > 0.0:
			tau = clampf(err * 120.0, -torque_limit, 0.0)
			tau = minf(tau, 0.0)
		motor_output_torque = tau
		if absf(tau) > 0.01:
			apply_torque(axis * tau)
		_prev_tau = tau

	# 制动：库仑式（前馈抵消负载力矩 + 粘滞刹停），总力矩不超过 brake_limit。
	brake_output_torque = 0.0
	_prev_brake_tau = 0.0
	if brake_on:
		var hold: float = clampf(-load_torque, -brake_limit(), brake_limit())
		# 刹停力矩只给到"这一帧刚好把转速归零"的量。给满会过冲成反转，
		# 然后每帧来回打（实测 ±2.5 rad/s 抖动）。
		var i_axis: float = _axis_inertia()
		var stop: float = clampf(-omega * i_axis / maxf(delta, 0.0001), -brake_limit(), brake_limit())
		var tau_b: float = clampf(hold + stop, -brake_limit(), brake_limit())
		brake_output_torque = tau_b
		_prev_brake_tau = tau_b
		if absf(tau_b) > 0.01:
			apply_torque(axis * tau_b)


## 制动力矩上限（N·m）。可被场景覆盖为更小的值。
func brake_limit() -> float:
	return BRAKE_TORQUE


func reset_work() -> void:
	motor_work = 0.0
	motor_work_drive = 0.0
	motor_work_regen = 0.0
	brake_work = 0.0
	manual_work = 0.0
	_prev_tau = 0.0
	_prev_brake_tau = 0.0
	_has_prev = false


func _axis_inertia() -> float:
	var axis: Vector3 = axis_world()
	var inv: Basis = get_inverse_inertia_tensor()
	var ii: float = absf(axis.dot(inv * axis))
	return 1.0 / maxf(ii, 0.000001)


func reset_drum() -> void:
	if not drum_built:
		return
	sleeping = false
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = spawn_pose
	angle_rad = 0.0
	_unwrapped = 0.0
	_last_angle = 0.0
	_angle_started = false
	omega = 0.0
	motor_on = false
	brake_on = true
	motor_output_torque = 0.0
	brake_output_torque = 0.0
	reset_work()


func despawn() -> void:
	clear_holders()
	if axle != null and is_instance_valid(axle):
		LISJointKit.teardown(axle)
		axle = null
	if frame != null and is_instance_valid(frame):
		frame.queue_free()
		frame = null
	queue_free()
