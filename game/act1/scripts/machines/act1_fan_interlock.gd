class_name Act1FanInterlock
extends Node3D
## MECHANICS-001C · 风机机械联锁（真实刚体，力 + 静态导向 + 实体止挡，不用关节）
##
## 1. 转子锁销：8 kg 销钉**平放在静态托架上**，被 -X 挡边挡住，不会自己移动；
##    执行器沿 +X 拉出，销钉滑过托架末端后掉落 → `rotor_released()`。
## 2. 传动联轴器：12 kg 滑套**坐在导杆上**，执行器沿 +X 推入啮合位，
##    顶住实体止挡 → `coupling_engaged()`（位置容差 0.05 m）。
##
## 状态一律由**真实位置**判定；E 只启动执行器（限时推力）。

const PIN_MASS := 8.0
const PIN_PULL_FORCE := 115.0        # N，> 8 kg × g ≈ 78 N，够了但不飞
const PIN_TRAVEL := 0.30             # m，销钉沿 +X 位移即视为脱开
const PIN_DRIVE_SECONDS := 0.60

const COLLAR_MASS := 12.0
const COLLAR_PUSH_FORCE := 420.0     # N，> 12 kg × g ≈ 118 N
const COLLAR_TRAVEL := 0.30
const COLLAR_DRIVE_SECONDS := 1.10
const ENGAGE_TOLERANCE := 0.06

var pin: RigidBody3D
var collar: RigidBody3D
var _pin_home := Vector3.ZERO
var _collar_home := Vector3.ZERO
var _pin_timer := 0.0
var _collar_timer := 0.0
var _actuated_pin := false
var _actuated_collar := false


func setup(host: Node, pin_pos: Vector3, collar_pos: Vector3) -> void:
	name = "FanInterlock"
	host.add_child(self)
	_build_pin(pin_pos)
	_build_collar(collar_pos)


func _static_box(nm: String, size: Vector3, world_pos: Vector3, color: Color) -> StaticBody3D:
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
	sb.global_position = world_pos
	return sb


func _vis_box(nm: String, size: Vector3, world_pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = world_pos
	add_child(mi)
	return mi


func _build_pin(pos: Vector3) -> void:
	# 托架：销钉平放在它上面（顶面正好托住销钉底面）
	_static_box("RotorLockTray", Vector3(0.90, 0.08, 0.30),
		pos + Vector3(0.12, -0.29, 0.0), Color(0.42, 0.42, 0.46))
	# -X 挡边：销钉在未拔出前不能往回/自己滑动
	_static_box("RotorLockLug", Vector3(0.10, 0.30, 0.30),
		pos + Vector3(-0.24, -0.10, 0.0), Color(0.55, 0.30, 0.22))
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.22, 0.24, 0.27)
	steel_mat.metallic = 0.5
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.38, 0.42, 0.46)
	trim_mat.metallic = 0.65
	var tray_bottom_y := pos.y - 0.33
	_vis_box("RotorLockPedestal", Vector3(0.42, tray_bottom_y, 0.34),
		Vector3(pos.x - 0.06, tray_bottom_y * 0.5, pos.z), steel_mat)
	_vis_box("RotorLockFoot", Vector3(0.62, 0.06, 0.50),
		Vector3(pos.x - 0.06, 0.03, pos.z), trim_mat)
	_vis_box("RotorLockFanLink", Vector3(1.10, 0.14, 0.14),
		Vector3(pos.x + 1.15, pos.y - 0.16, pos.z), trim_mat)

	pin = RigidBody3D.new()
	pin.name = "RotorLockPin"
	pin.mass = PIN_MASS
	pin.can_sleep = false
	pin.gravity_scale = 1.0
	pin.linear_damp = 2.6
	pin.angular_damp = 2.0
	pin.collision_layer = 4
	pin.collision_mask = 1 | 2 | 4 | 16
	var pcs: CollisionShape3D = CollisionShape3D.new()
	var pbs: BoxShape3D = BoxShape3D.new()
	pbs.size = Vector3(0.12, 0.50, 0.12)     # 竖直销钉，平放在托架上的横杆段
	pcs.shape = pbs
	pin.add_child(pcs)
	var pmi: MeshInstance3D = MeshInstance3D.new()
	var pbm: BoxMesh = BoxMesh.new()
	pbm.size = Vector3(0.12, 0.50, 0.12)
	pmi.mesh = pbm
	var pmat: StandardMaterial3D = StandardMaterial3D.new()
	pmat.albedo_color = Color(0.85, 0.25, 0.18)
	pmi.material_override = pmat
	pin.add_child(pmi)
	# 让销钉"横躺"在托架上：绕 Z 转 90°，长度沿 X
	pin.add_child(_visual_marker())
	add_child(pin)
	pin.global_position = pos
	pin.rotation = Vector3(0.0, 0.0, PI * 0.5)
	_pin_home = pos


func _visual_marker() -> Node3D:
	return Node3D.new()


func pull_rotor_lock() -> bool:
	if rotor_released():
		return false
	_actuated_pin = true
	_pin_timer = PIN_DRIVE_SECONDS
	pin.sleeping = false
	return true


func rotor_released() -> bool:
	if pin == null:
		return false
	var d: Vector3 = pin.global_position - _pin_home
	return d.x >= PIN_TRAVEL or d.y <= -0.35


func _build_collar(pos: Vector3) -> void:
	# 导杆：滑套坐在它上面，只能沿 X 滑动
	_static_box("CouplingRod", Vector3(0.95, 0.08, 0.10),
		pos + Vector3(-0.10, -0.11, 0.0), Color(0.40, 0.40, 0.44))
	# 啮合止挡：滑套推到位后顶住它
	_static_box("CouplingStop", Vector3(0.10, 0.34, 0.34),
		pos + Vector3(COLLAR_TRAVEL + 0.12, 0.0, 0.0), Color(0.55, 0.55, 0.30))
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.22, 0.24, 0.27)
	steel_mat.metallic = 0.5
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.38, 0.42, 0.46)
	trim_mat.metallic = 0.65
	var rod_bottom_y := pos.y - 0.15
	_vis_box("CouplingPedestalL", Vector3(0.24, rod_bottom_y, 0.28),
		Vector3(pos.x - 0.42, rod_bottom_y * 0.5, pos.z), steel_mat)
	_vis_box("CouplingPedestalR", Vector3(0.24, rod_bottom_y, 0.36),
		Vector3(pos.x + COLLAR_TRAVEL + 0.12, rod_bottom_y * 0.5, pos.z), steel_mat)
	_vis_box("CouplingFoot", Vector3(1.12, 0.06, 0.52),
		Vector3(pos.x - 0.06, 0.03, pos.z), trim_mat)
	_vis_box("CouplingFanShaft", Vector3(1.45, 0.16, 0.16),
		Vector3(pos.x + 1.15, pos.y, pos.z), trim_mat)

	collar = RigidBody3D.new()
	collar.name = "CouplingCollar"
	collar.mass = COLLAR_MASS
	collar.can_sleep = false
	collar.gravity_scale = 1.0
	collar.linear_damp = 1.8
	collar.angular_damp = 2.4
	collar.collision_layer = 4
	collar.collision_mask = 1 | 2 | 4 | 16
	var ccs: CollisionShape3D = CollisionShape3D.new()
	var cbs: BoxShape3D = BoxShape3D.new()
	cbs.size = Vector3(0.22, 0.22, 0.22)
	ccs.shape = cbs
	collar.add_child(ccs)
	var cmi: MeshInstance3D = MeshInstance3D.new()
	var cbm: BoxMesh = BoxMesh.new()
	cbm.size = Vector3(0.22, 0.22, 0.22)
	cmi.mesh = cbm
	var cmat: StandardMaterial3D = StandardMaterial3D.new()
	cmat.albedo_color = Color(0.30, 0.72, 0.85)
	cmi.material_override = cmat
	collar.add_child(cmi)
	add_child(collar)
	collar.global_position = pos
	_collar_home = pos


func push_coupling() -> bool:
	if coupling_engaged():
		return false
	_actuated_collar = true
	_collar_timer = COLLAR_DRIVE_SECONDS
	collar.sleeping = false
	return true


func coupling_engaged() -> bool:
	if collar == null:
		return false
	var d: Vector3 = collar.global_position - (_collar_home + Vector3(COLLAR_TRAVEL, 0.0, 0.0))
	return absf(d.x) <= ENGAGE_TOLERANCE and Vector2(d.y, d.z).length() <= ENGAGE_TOLERANCE


func machine_ready() -> bool:
	return rotor_released() and coupling_engaged()


func _physics_process(delta: float) -> void:
	if pin != null and _pin_timer > 0.0:
		_pin_timer = maxf(0.0, _pin_timer - delta)
		pin.sleeping = false
		pin.apply_central_force(Vector3(PIN_PULL_FORCE, 0.0, 0.0))
	if collar != null and _collar_timer > 0.0:
		_collar_timer = maxf(0.0, _collar_timer - delta)
		collar.sleeping = false
		collar.apply_central_force(Vector3(COLLAR_PUSH_FORCE, -60.0, 0.0))


func reset_interlock() -> void:
	_pin_timer = 0.0
	_collar_timer = 0.0
	_actuated_pin = false
	_actuated_collar = false
	if pin != null:
		pin.linear_velocity = Vector3.ZERO
		pin.angular_velocity = Vector3.ZERO
		pin.global_position = _pin_home
		pin.rotation = Vector3(0.0, 0.0, PI * 0.5)
	if collar != null:
		collar.linear_velocity = Vector3.ZERO
		collar.angular_velocity = Vector3.ZERO
		collar.global_position = _collar_home
