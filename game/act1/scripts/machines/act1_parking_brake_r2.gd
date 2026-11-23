class_name Act1ParkingBrake
extends Node3D
## MECHANICS-001E-R2 · 真实停车制动（径向销爪 + 齿圈制动鼓）
##
## 传力路径：鼓齿 → 销爪侧面 → **两侧静态导槽** → 支架。
## 关键：销爪滑动方向是**径向**、鼓齿推力是**切向**，两者垂直，
## 鼓齿无法把销爪沿行程方向推走（这正是 001E/R1 失败的根因）。
## 销爪伸入齿圈内侧时，齿圈从两个方向扫过都会被销爪正面挡住 → **双向锁止**。
## 状态由销爪真实行程判定；E 只启动抽出执行器。

const DRUM_MASS := 4.0
const DRUM_HALF := 0.20
const TOOTH_R := 0.34
const PIN_ENGAGED_X := -0.40      # 尖端半径 0.22：不嵌入鼓体(≤0.20)，但落在齿圈(0.28-0.40)拦截范围
const PULL_FORCE := 40.0
const PULL_MAX_SPEED := 0.9       # m/s，限速牵引：2 kg 销爪不会被弹飞
const ACTUATOR_SECONDS := 0.70
const RELEASE_TRAVEL := 0.20   # 内端必须退到齿圈(≤0.40)之外
const SPIN_TORQUE := 6.0
## MECHANICS-001F：伸入端实体止挡（齿圈内侧、半径 ≤0.267 的支承座）。
## 001E-R3 用"入位即停 + 清速度"把销爪钉在啮合位；那只是把速度清零，
## 不是机械边界。现在由这块支承座真正挡住销爪，清速度代码已删除。
const IN_STOP_MAX_FACE_X := -0.2215
const DRUM_INERTIA := 0.1067   # 4 kg · (0.4²+0.4²)/12，仅用于力矩-角加速度自检

var drum: RigidBody3D
var pin: RigidBody3D
var in_stop: StaticBody3D
var axis := Vector3(0.0, 0.0, 1.0)
## 演示/负载力矩。专项测试把它设为 0，再自行施加 ±12 N·m 的纯外力矩。
var drive_torque := SPIN_TORQUE
var _timer := 0.0
var _dir := 0.0


func setup(host: Node, pos: Vector3) -> void:
	name = "ParkingBrake"
	host.add_child(self)
	position = pos
	_build()


func _static_box(nm: String, size: Vector3, local_pos: Vector3, color: Color) -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)
	sb.position = local_pos
	return sb


func _build() -> void:
	_static_box("BrakePost", Vector3(0.24, 0.50, 0.30), Vector3(0.0, 0.30, -0.30), Color(0.30, 0.30, 0.34))

	drum = RigidBody3D.new()
	drum.name = "BrakeDrum"
	drum.mass = DRUM_MASS
	drum.can_sleep = false
	drum.gravity_scale = 0.0
	drum.angular_damp = 0.15
	drum.linear_damp = 2.0
	drum.collision_layer = 4
	drum.collision_mask = 1 | 2 | 4 | 16
	drum.axis_lock_angular_x = true
	drum.axis_lock_angular_y = true
	drum.axis_lock_linear_y = true
	drum.axis_lock_linear_z = true
	drum.continuous_cd = true
	var dcs: CollisionShape3D = CollisionShape3D.new()
	var dbs: BoxShape3D = BoxShape3D.new()
	dbs.size = Vector3(DRUM_HALF * 2.0, DRUM_HALF * 2.0, 0.10)
	dcs.shape = dbs
	drum.add_child(dcs)
	for k in range(4):
		var ang: float = float(k) * PI * 0.5 + PI * 0.25
		var tcs: CollisionShape3D = CollisionShape3D.new()
		var tbs: BoxShape3D = BoxShape3D.new()
		tbs.size = Vector3(0.12, 0.10, 0.10)
		tcs.shape = tbs
		tcs.position = Vector3(cos(ang) * TOOTH_R, sin(ang) * TOOTH_R, 0.0)
		tcs.rotation = Vector3(0.0, 0.0, ang)
		drum.add_child(tcs)
	var dmi: MeshInstance3D = MeshInstance3D.new()
	var dbm: BoxMesh = BoxMesh.new()
	dbm.size = Vector3(DRUM_HALF * 2.0, DRUM_HALF * 2.0, 0.10)
	dmi.mesh = dbm
	var dmat: StandardMaterial3D = StandardMaterial3D.new()
	dmat.albedo_color = Color(0.58, 0.60, 0.64)
	dmi.material_override = dmat
	drum.add_child(dmi)
	var stripe: MeshInstance3D = MeshInstance3D.new()
	var sbm: BoxMesh = BoxMesh.new()
	sbm.size = Vector3(0.34, 0.05, 0.04)
	stripe.mesh = sbm
	stripe.position = Vector3(0.0, 0.0, 0.07)
	var smat: StandardMaterial3D = StandardMaterial3D.new()
	smat.albedo_color = Color(0.92, 0.64, 0.16)
	stripe.material_override = smat
	drum.add_child(stripe)
	add_child(drum)
	drum.position = Vector3(0.0, 0.0, 0.0)

	for sgn in [-1.0, 1.0]:
		_static_box("PinGuide%s" % ("Top" if sgn > 0.0 else "Bottom"),
			Vector3(0.18, 0.06, 0.14), Vector3(-0.54, sgn * 0.085, 0.0), Color(0.44, 0.44, 0.48))
	# 抽出端实体止挡：销爪最多退到这里（防止被推飞）
	_static_box("PinOutStop", Vector3(0.05, 0.16, 0.16), Vector3(-0.88, 0.0, 0.0), Color(0.36, 0.32, 0.26))
	# 伸入端实体止挡（MECHANICS-001F）：销爪肩部正面顶在这块支承座上，位置即啮合位。
	# 支承座放在齿圈平面之外（z 0.075..0.165），与鼓体(z ±0.05)和鼓齿(z ±0.05)都不接触，
	# 因此不会像"塞进齿圈内侧"那样卡住制动鼓。
	in_stop = _static_box("PinInStop", Vector3(0.05, 0.12, 0.09), Vector3(-0.1935, 0.0, 0.12), Color(0.36, 0.32, 0.26))

	pin = RigidBody3D.new()
	pin.name = "BrakePin"
	pin.mass = 2.0
	pin.can_sleep = false
	pin.gravity_scale = 0.0
	pin.linear_damp = 3.0
	pin.angular_damp = 4.0
	pin.collision_layer = 4
	pin.collision_mask = 1 | 2 | 4 | 16
	# 销爪是**轴向导向滑块**：两片导槽限制 y/z 平移，这里锁死三个转动自由度，
	# 等价于棱柱副。否则鼓齿的切向冲量会把销爪拧歪，撞进止挡与导槽。
	pin.axis_lock_angular_x = true
	pin.axis_lock_angular_y = true
	pin.axis_lock_angular_z = true
	pin.contact_monitor = true
	pin.max_contacts_reported = 6
	var pcs: CollisionShape3D = CollisionShape3D.new()
	var pbs: BoxShape3D = BoxShape3D.new()
	pbs.size = Vector3(0.36, 0.10, 0.12)
	pcs.shape = pbs
	pin.add_child(pcs)
	# 销爪肩部（伸入方向的机械止挡面）。齿圈平面之外，不与鼓齿干涉。
	var sh_cs: CollisionShape3D = CollisionShape3D.new()
	var sh_shape: BoxShape3D = BoxShape3D.new()
	sh_shape.size = Vector3(0.12, 0.10, 0.06)
	sh_cs.shape = sh_shape
	sh_cs.position = Vector3(0.12, 0.0, 0.12)
	pin.add_child(sh_cs)
	var pmi: MeshInstance3D = MeshInstance3D.new()
	var pbm: BoxMesh = BoxMesh.new()
	pbm.size = Vector3(0.36, 0.10, 0.12)
	pmi.mesh = pbm
	var pmat: StandardMaterial3D = StandardMaterial3D.new()
	pmat.albedo_color = Color(0.86, 0.46, 0.16)
	pmi.material_override = pmat
	pin.add_child(pmi)
	var smi: MeshInstance3D = MeshInstance3D.new()
	var sh_mesh: BoxMesh = BoxMesh.new()
	sh_mesh.size = Vector3(0.12, 0.10, 0.06)
	smi.mesh = sh_mesh
	smi.material_override = pmat
	smi.position = Vector3(0.12, 0.0, 0.12)
	pin.add_child(smi)
	add_child(pin)
	pin.position = Vector3(PIN_ENGAGED_X, 0.0, 0.0)


func release_brake() -> bool:
	if released():
		return false
	_dir = 1.0
	_timer = ACTUATOR_SECONDS
	pin.sleeping = false
	return true


func apply_brake() -> bool:
	if not released():
		return false
	_dir = -1.0
	_timer = ACTUATOR_SECONDS
	pin.sleeping = false
	return true


func pin_travel() -> float:
	return 0.0 if pin == null else (pin.position.x - PIN_ENGAGED_X)


func released() -> bool:
	return pin_travel() <= -RELEASE_TRAVEL   # 抽出方向为 -X，行程取负


func drum_omega() -> float:
	return 0.0 if drum == null else absf(drum.angular_velocity.dot(axis))


func pin_touching_drum() -> bool:
	if pin == null or drum == null:
		return false
	for b in pin.get_colliding_bodies():
		if b == drum:
			return true
	return false


func pin_touching_in_stop() -> bool:
	if pin == null or in_stop == null:
		return false
	for b in pin.get_colliding_bodies():
		if b == in_stop:
			return true
	return false


func pin_contacts() -> Array:
	if pin == null:
		return []
	var out: Array = []
	for b in pin.get_colliding_bodies():
		if b != null:
			out.append(str(b.name))
	out.sort()
	return out


func _physics_process(delta: float) -> void:
	if pin == null or drum == null:
		return
	if _timer > 0.0:
		_timer = maxf(0.0, _timer - delta)
		pin.sleeping = false
		var vx: float = pin.linear_velocity.x
		if absf(vx) < PULL_MAX_SPEED:
			pin.apply_central_force(Vector3(-PULL_FORCE, 0.0, 0.0) if _dir > 0.0 else Vector3(PULL_FORCE, 0.0, 0.0))
	# 只有销爪真的退出齿圈，制动鼓才被驱动旋转（演示/负载力矩）
	if released():
		drum.apply_torque(axis * drive_torque)


func reset_brake() -> void:
	_timer = 0.0
	_dir = 0.0
	if pin != null:
		pin.linear_velocity = Vector3.ZERO
		pin.angular_velocity = Vector3.ZERO
		pin.position = Vector3(PIN_ENGAGED_X, 0.0, 0.0)
		pin.rotation = Vector3.ZERO
	if drum != null:
		drum.angular_velocity = Vector3.ZERO
		drum.rotation = Vector3.ZERO
		drum.position = Vector3.ZERO
