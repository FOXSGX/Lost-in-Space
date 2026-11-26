class_name Act1PowerCart
extends AnimatableBody3D

## Heavy auxiliary-power trolley for Act 01. It is a controlled kinematic body
## rather than a free rigid body: mass and inertia are simulated explicitly, the
## player drives it by gripping the handle, and the rails constrain it to a real
## floor route. It never teleports; the transfer to the socket is a visible
## motorised rail move.

signal module_transferred()
signal docked_changed(value: bool)

const START_X := -5.35
const DOCK_X := 4.25
const RAIL_Z := -2.55
const MAX_SPEED := 1.55
const ACCEL := 1.15
const BRAKE := 2.8

var stage: Node
var operator_pid := 0
var velocity := 0.0
var docked := false
var module_transferred_flag := false
var transfer_progress := 0.0
var path_blocked := false
var module: Node3D
## MECHANICS-001A：导轨上的真实电源模块刚体（由 builder 创建并绑定）
var power_module: RigidBody3D = null

## MECHANICS-001B-R2：实体旋转锁爪
const CLAMP_CLOSED_ANGLE := 1.00      # 臂抬到模块顶接触处的角度（rad）；自然静止为 ~1.5
var clamp_jaw: RigidBody3D = null
var clamp_hinge: HingeJoint3D = null
var clamp_axis := Vector3(0.0, 0.0, 1.0)
var clamp_start := Basis()
var clamp_angle := 0.0
var clamp_closed := false
var clamp_stalled := false
var _clamp_timer := 0.0


func bind_clamp(jaw: RigidBody3D, hinge: HingeJoint3D) -> void:
	clamp_jaw = jaw
	clamp_hinge = hinge
	if clamp_jaw != null:
		clamp_jaw.contact_monitor = true
		clamp_jaw.max_contacts_reported = maxi(clamp_jaw.max_contacts_reported, 6)
	# 实测：自由转动轴 = 关节 basis 的 Z 列（不是 X）
	clamp_axis = hinge.global_transform.basis.z.normalized()
	clamp_start = jaw.global_transform.basis
	clamp_angle = 0.0


## E 只切换电机方向；闭合由物理（电机 + 模块/止挡阻挡）决定
func set_clamp(on: bool) -> void:
	clamp_closed = on
	_clamp_timer = 0.0
	clamp_stalled = false
	if clamp_jaw != null:
		clamp_jaw.sleeping = false
	if clamp_hinge != null:
		clamp_hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, -1.25 if on else 1.25)
		clamp_hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 420.0)


## 绕真实铰链轴的有符号角
func clamp_angle_now() -> float:
	if clamp_jaw == null:
		return 0.0
	var axl: Vector3 = clamp_start.inverse() * clamp_axis
	var rel: Basis = clamp_start.inverse() * clamp_jaw.global_transform.basis
	var q: Quaternion = rel.get_rotation_quaternion()
	var s: float = q.x * axl.x + q.y * axl.y + q.z * axl.z
	return 2.0 * atan2(s, q.w)


func _update_clamp(delta: float) -> void:
	if clamp_jaw == null or clamp_hinge == null:
		return
	clamp_angle = clamp_angle_now()
	if clamp_closed:
		clamp_jaw.sleeping = false
	_clamp_timer += delta
	var at_target: bool = clamp_closed and ((_touching_module() and _clamp_timer > 0.25) \
		or (clamp_angle >= CLAMP_CLOSED_ANGLE - 0.15 and clamp_angle <= CLAMP_CLOSED_ANGLE + 0.15))
	var at_home: bool = (not clamp_closed) and clamp_angle <= 0.05
	clamp_stalled = clamp_closed and (not at_target) and _clamp_timer > 3.00 \
		and absf(clamp_jaw.angular_velocity.dot(clamp_axis)) < 0.05
	if at_target:
		# 到位后切到"保持"状态：目标速度 0 + 保留冲量 = 马达当刹车，锁爪停在锁止角
		clamp_hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		clamp_hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 420.0)
	elif at_home:
		# 打开到位后同样用马达抱死，防止重力把锁爪甩下去
		clamp_hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		clamp_hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 420.0)
	elif clamp_stalled:
		# 堵转时改用低速保压而非清零冲量，避免锁爪松脱及必须重按才能继续夹紧
		clamp_hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, -0.15)
		clamp_hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 120.0)


## 锁爪是否真的转到锁止角（供任务判据使用）
func _touching_module() -> bool:
	if clamp_jaw == null or power_module == null:
		return false
	for b in clamp_jaw.get_colliding_bodies():
		if b == power_module:
			return true
	return false


## 锁爪是否真的转到锁止角并与模块接触
func clamp_locked() -> bool:
	return clamp_closed and ((_touching_module() and clamp_angle >= CLAMP_CLOSED_ANGLE - 0.18) \
		or (clamp_angle >= CLAMP_CLOSED_ANGLE - 0.15 and clamp_angle <= CLAMP_CLOSED_ANGLE + 0.15))
var module_target: Vector3 = Vector3.ZERO
var _winch_on := false
var _winch_spin := 0.0
var _winch_travel := 0.0
var module_home: Vector3 = Vector3.ZERO


## MECHANICS-001A：绑定导轨上的真实模块刚体，并隐藏车上的装饰性载荷，
## 避免同一台模块同时存在两份。
func bind_module(m: RigidBody3D) -> void:
	power_module = m
	module_home = m.global_position
	module_target = m.global_position
	if module != null:
		module.visible = false
	for c: Node in get_children():
		if c is CollisionShape3D and str(c.name) == "ModuleShape":
			(c as CollisionShape3D).disabled = true


## 由物理状态判定后调用（见 Act1App._update_physics_verifications）。
func mark_module_seated() -> void:
	if module_transferred_flag:
		return
	module_transferred_flag = true
	transfer_progress = 1.0
	_winch_on = false
	module_transferred.emit()
	stage.call("on_power_module_seated")
var handle: Act1Interactable
var wheels: Array[MeshInstance3D] = []
var _wheel_spin := 0.0
var _dock_approach := false
var _transfer_tween: Tween
var _home := Vector3.ZERO


func setup(p_stage: Node) -> void:
	stage = p_stage
	name = "AuxiliaryPowerCart"
	collision_layer = 16
	collision_mask = 0
	sync_to_physics = false
	_home = Vector3(START_X, 0.0, RAIL_Z)
	global_position = _home
	_build_visual()
	_build_collision()
	_register_interactions()


func _build_visual() -> void:
	var steel := Act1MatLib.dark_steel()
	var paint := Act1MatLib.painted_steel(Color(0.64, 0.34, 0.10))
	var yellow := Act1MatLib.painted_steel(Color(0.82, 0.62, 0.12))
	var cyan := Act1MatLib.emissive(Color(0.15, 0.82, 0.92), 0.85)
	var rubber := Act1MatLib.rubber()
	# chassis
	_b(mesh_box(Vector3(2.75, 0.22, 1.55), steel), Vector3(0, 0.72, 0))
	_b(mesh_box(Vector3(2.45, 0.42, 1.40), paint), Vector3(0, 0.98, 0))
	# deck plate with raised edge
	_b(mesh_box(Vector3(2.35, 0.10, 1.32), steel), Vector3(0, 1.20, 0))
	_b(mesh_box(Vector3(2.50, 0.10, 0.08), yellow), Vector3(0, 1.25, -0.67))
	_b(mesh_box(Vector3(2.50, 0.10, 0.08), yellow), Vector3(0, 1.25, 0.67))
	for x in [-1.10, 1.10]:
		for z in [-0.64, 0.64]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.30
			cyl.bottom_radius = 0.30
			cyl.height = 0.18
			cyl.radial_segments = 18
			wheel.mesh = cyl
			wheel.material_override = rubber
			wheel.rotation.x = PI * 0.5
			wheel.position = Vector3(x, 0.31, z)
			add_child(wheel)
			wheels.append(wheel)
			_b(mesh_cylinder(0.12, 0.20, 12, steel), Vector3(x, 0.31, z)).rotation.x = PI * 0.5
	# push handle at the west end
	_b(mesh_cylinder(0.035, 1.15, 8, steel), Vector3(-1.42, 1.70, 0)).rotation.x = PI * 0.5
	_b(mesh_cylinder(0.035, 0.55, 8, steel), Vector3(-1.42, 1.42, -0.54)).rotation.z = 0.28
	_b(mesh_cylinder(0.035, 0.55, 8, steel), Vector3(-1.42, 1.42, 0.54)).rotation.z = 0.28
	# power module on the deck
	module = Node3D.new()
	module.name = "AuxiliaryPowerModule"
	add_child(module)
	module.position = Vector3(0, 1.30, 0)
	var module_body := mesh_box(Vector3(1.22, 1.02, 1.10), paint)
	module.add_child(module_body)
	var module_core := mesh_box(Vector3(1.02, 0.78, 0.90), cyan)
	module_core.position = Vector3(0, 0.0, 0)
	module.add_child(module_core)
	for x in [-0.44, 0.44]:
		var strap := mesh_box(Vector3(0.07, 1.10, 1.15), steel)
		strap.position = Vector3(x, 0, 0)
		module.add_child(strap)
	var cap := mesh_cylinder(0.14, 0.20, 10, yellow)
	cap.position = Vector3(0, 0.61, 0)
	module.add_child(cap)
	for i in range(3):
		var lamp := mesh_box(Vector3(0.05, 0.05, 0.05), cyan)
		lamp.position = Vector3(-0.40 + i * 0.40, 0.33, -0.57)
		module.add_child(lamp)
	# handle for the grip interaction
	handle = Act1Interactable.new()
	handle.stage = stage
	handle.setup("cart_push", "E 握住推车把手 · W/S 推拉", Vector3(0.55, 0.90, 1.55), true)
	handle.position = Vector3(-1.55, 1.47, 0)
	add_child(handle)
	handle.add_focus_marker(0.23)
	# cable reel and status light
	var reel := mesh_cylinder(0.24, 0.16, 16, steel)
	reel.rotation.x = PI * 0.5
	reel.position = Vector3(1.10, 1.05, 0.50)
	add_child(reel)
	var status := mesh_box(Vector3(0.10, 0.10, 0.03), yellow)
	status.position = Vector3(1.22, 1.34, -0.80)
	add_child(status)


func mesh_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


func mesh_cylinder(radius: float, height: float, segments: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
	mi.mesh = cm
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


func _b(mi: MeshInstance3D, pos: Vector3) -> MeshInstance3D:
	mi.position = pos
	add_child(mi)
	return mi


func _build_collision() -> void:
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(2.80, 1.30, 1.60)
	var body_col := CollisionShape3D.new()
	body_col.name = "CartBodyShape"
	body_col.shape = body_shape
	body_col.position = Vector3(0, 0.70, 0)
	add_child(body_col)
	var module_shape := BoxShape3D.new()
	module_shape.size = Vector3(1.24, 1.06, 1.12)
	var module_col := CollisionShape3D.new()
	module_col.name = "ModuleShape"
	module_col.shape = module_shape
	module_col.position = Vector3(0, 1.32, 0)
	add_child(module_col)


func _register_interactions() -> void:
	handle.interaction_id = "cart_push"
	handle.prompt_callable = Callable(self, "_cart_prompt")


func _cart_prompt(_player: Node = null) -> String:
	if module_transferred_flag:
		return "电源模块已接入 · 推车已卸荷"
	if docked:
		return "E 握住把手 · W/S 微调 · 对准供电导轨"
	return "E 握住推车把手 · W/S 推拉 · 重 70 kg"


func begin_push(pid: int) -> bool:
	if module_transferred_flag or _dock_approach:
		return false
	operator_pid = pid
	return true


func end_push(pid: int) -> void:
	if operator_pid == pid:
		operator_pid = 0


var _axis := 0.0
var _pending_module_state: Dictionary = {}


func set_axis(value: float) -> void:
	if operator_pid == 0:
		_axis = 0.0
		return
	_axis = clampf(value, -1.0, 1.0)


func start_dock_approach() -> void:
	if docked or _dock_approach or module_transferred_flag:
		return
	_dock_approach = true
	operator_pid = 0
	_axis = 0.0
	if _transfer_tween != null and _transfer_tween.is_valid():
		_transfer_tween.kill()
	_transfer_tween = create_tween()
	_transfer_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_transfer_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transfer_tween.tween_property(self, "global_position:x", DOCK_X, 0.85)
	_transfer_tween.tween_callback(func() -> void:
		velocity = 0.0
		docked = true
		_dock_approach = false
		_transfer_tween = null
		docked_changed.emit(true)
		stage.call("on_power_cart_docked")
	)


## MECHANICS-001A：模块不再被 Tween 送过去，而是**导轨上的真实刚体**。
## 这个函数只负责"接通绞盘"（等价于玩家扳下绞盘开关），
## 模块的实际位移由 `_drive_winch()` 施加的真实力产生，完成判定移到
## `Act1App._update_physics_verifications()`（位置 + 静止）。
func transfer_module(socket_world: Vector3) -> void:
	if not docked or module_transferred_flag:
		return
	if power_module == null:
		# 没有绑定物理模块时不假装成功（旧 Tween 行为已删除）
		push_warning("Act1PowerCart.transfer_module: power_module 未绑定，绞盘无法受力")
		return
	module_target = socket_world
	_winch_on = true


## 绞盘的真实牵引：沿导轨方向施加恒定力，直到模块进入插座容差或到达行程上限。
## 力的量级按模块质量给出（约 0.9 g），重物慢、轻物快，都走同一套刚体解算。
func _drive_winch(delta: float) -> void:
	if not _winch_on or power_module == null:
		return
	if module_transferred_flag:
		_winch_on = false
		return
	var to_target: Vector3 = module_target - power_module.global_position
	to_target.y = 0.0
	if to_target.length() < 0.28:
		_winch_on = false
		return
	var dir: Vector3 = to_target.normalized()
	var force: float = power_module.mass * 9.81 * 0.9
	power_module.apply_central_force(dir * force)
	_winch_spin += dir.dot(power_module.linear_velocity) * delta
	_winch_travel += dir.dot(power_module.linear_velocity) * delta
	var _unused: float = delta


func get_winch_travel() -> float:
	return _winch_travel


func get_transfer_progress() -> float:
	if module_transferred_flag:
		return 1.0
	return transfer_progress


func is_at_dock() -> bool:
	return absf(global_position.x - DOCK_X) < 0.48 and absf(global_position.z - RAIL_Z) < 0.25


func reset_cart() -> void:
	if _transfer_tween != null and _transfer_tween.is_valid():
		_transfer_tween.kill()
	_transfer_tween = null
	operator_pid = 0
	velocity = 0.0
	docked = false
	_dock_approach = false
	module_transferred_flag = false
	transfer_progress = 0.0
	global_position = _home
	module.position = Vector3(0, 1.30, 0)
	# MECHANICS-001A：模块与绞盘一起复位（真实刚体必须回到导轨起点）
	_winch_on = false
	_winch_spin = 0.0
	_winch_travel = 0.0
	if power_module != null:
		power_module.linear_velocity = Vector3.ZERO
		power_module.angular_velocity = Vector3.ZERO
		power_module.global_position = module_home
		power_module.rotation = Vector3.ZERO


func snapshot() -> Dictionary:
	return {
		"pos": global_position,
		"vel": velocity,
		"docked": docked,
		"transferred": module_transferred_flag,
		"module": module.position if module != null else Vector3.ZERO,
		"module_xform": power_module.global_transform if power_module != null and is_instance_valid(power_module) else Transform3D.IDENTITY,
		"module_lin": power_module.linear_velocity if power_module != null and is_instance_valid(power_module) else Vector3.ZERO,
		"module_ang": power_module.angular_velocity if power_module != null and is_instance_valid(power_module) else Vector3.ZERO,
		"has_power_module": power_module != null and is_instance_valid(power_module),
		"operator": operator_pid,
	}


func apply_snapshot(data: Dictionary) -> void:
	global_position = data.get("pos", global_position)
	velocity = float(data.get("vel", velocity))
	docked = bool(data.get("docked", docked))
	var was_transferred := module_transferred_flag
	module_transferred_flag = bool(data.get("transferred", module_transferred_flag))
	if module != null:
		module.position = data.get("module", module.position)
		if not was_transferred and module_transferred_flag:
			module_transferred.emit()
	if bool(data.get("has_power_module", false)) and data.has("module_xform"):
		_pending_module_state = {
			"xform": data.get("module_xform"),
			"lin": data.get("module_lin", Vector3.ZERO),
			"ang": data.get("module_ang", Vector3.ZERO),
		}


func _physics_process(delta: float) -> void:
	if not _pending_module_state.is_empty() and power_module != null and is_instance_valid(power_module):
		power_module.global_transform = _pending_module_state["xform"] as Transform3D
		power_module.linear_velocity = _pending_module_state["lin"] as Vector3
		power_module.angular_velocity = _pending_module_state["ang"] as Vector3
		_pending_module_state.clear()
	_drive_winch(delta)
	_update_clamp(delta)
	if not _dock_approach:
		if operator_pid != 0:
			velocity = move_toward(velocity, _axis * MAX_SPEED, ACCEL * delta)
		else:
			_axis = 0.0
			velocity = move_toward(velocity, 0.0, BRAKE * delta)
	if path_blocked and not _dock_approach:
		velocity = 0.0
	if absf(velocity) > 0.005 and not _dock_approach and not path_blocked:
		var next_x := clampf(global_position.x + velocity * delta, START_X, DOCK_X + 0.25)
		global_position.x = next_x
		if next_x >= DOCK_X - 0.40 and absf(global_position.z - RAIL_Z) < 0.30:
			start_dock_approach()
		if next_x >= DOCK_X - 0.02:
			velocity = 0.0
	if wheels.size() > 0:
		_wheel_spin += velocity * delta / 0.30
		for w in wheels:
			w.rotation.z = _wheel_spin