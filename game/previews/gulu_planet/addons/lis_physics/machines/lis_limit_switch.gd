class_name LISLimitSwitch
extends Node3D
## LIS Physics SDK · 机械限位开关（顶杆 + 导向井 + 弹簧 + 真实接触）
##
## 这不是 Area3D 触发器，也不是"脚本读杠杆角度"：
##   * 顶杆是一块真实刚体，卡在四壁之间，只能上下动；
##   * 弹簧用**每帧施加的真实弹簧力**（F = k·压缩量 − c·速度）实现，不是瞬移；
##   * 杠杆压下来时，是杠杆的碰撞体真的顶住顶杆把它压下去；
##   * "开关闭合" = 顶杆被压低超过阈值 **且** 顶杆当前确实与压它的物体接触。
##
## 因此：没有东西顶住它，开关绝不可能闭合。状态带迟滞，避免阈值附近抖动。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_limit_switch.gd

signal state_changed(closed: bool)

## 闭合 / 断开的压缩量阈值（米）。
const PRESS_CLOSE := 0.020
const PRESS_OPEN := 0.008
## 弹簧刚度 / 阻尼。顶杆质量 0.5 kg，压 20 mm 约 12 N。
const SPRING_K := 600.0
const SPRING_C := 8.0
## 顶杆静止时的中心高度（米）。顶杆 0.26 m 高，顶面 = 0.75 + 0.13 = 0.88。
const PLUNGER_REST_Y := 0.75
## 导向块内净空（半宽）。必须比触发杆宽、比顶杆窄。
const WELL_HALF := 0.070

## 是否只接受特定类型的物体来压（为空则任何刚体都能压）。
## 留空 = 任何真实接触都会闭合（更通用）；填 "LISLever" 等类名可限定。
@export var pressed_by_class: String = ""
@export_flags_3d_physics var plunger_layer: int = LISPhysics.LAYER_PROP
@export_flags_3d_physics var plunger_mask: int = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PROP

var housing: StaticBody3D
var plunger: RigidBody3D
var rest_y: float = PLUNGER_REST_Y
var travel: float = 0.14

var closed: bool = false
var compression: float = 0.0
var pressed_by: String = ""
## 兼容字段：旧接口传一个 lever 进来（现在不再是必需）。
var lever: Node3D = null
var switch_built: bool = false


## 旧接口兼容：绑一个物体（仅用于提示，不用于判定）。
func setup(lever_body: Node3D = null) -> void:
	lever = lever_body
	if not switch_built:
		build_switch()


func _ready() -> void:
	if not switch_built:
		build_switch()


func build_switch() -> void:
	if switch_built:
		return
	switch_built = true
	name = "LimitSwitch"
	housing = StaticBody3D.new()
	housing.name = "Housing"
	housing.collision_layer = LISPhysics.LAYER_WORLD
	housing.collision_mask = 0
	add_child(housing)

	var steel: StandardMaterial3D = _mat(Color(0.22, 0.24, 0.26), 0.60, 0.55)
	var brass: StandardMaterial3D = _mat(Color(0.72, 0.56, 0.20), 0.45, 0.70)

	# 底座：只到 0.30 m 高。做高了杠杆的梁会扫到它，把杠杆顶住转不动。
	_add_box(housing, "Body", Vector3(0.30, 0.30, 0.30), Vector3(0.0, 0.15, 0.0), steel)
	# 导向块：只做半高的一对薄板，夹在触发杆两侧，并**开 Z 向的口**。
	for sx: float in [-1.0, 1.0]:
		_add_box(housing, "GuideX", Vector3(0.03, 0.34, 0.05),
			Vector3(sx * (WELL_HALF + 0.015), rest_y - 0.17, 0.085), steel)
	# 顶部挡梁：两根细横梁，只挡顶杆两侧，**不能**做成实心板
	# （实心板会横在触发杆下落路径上，让杠杆压不下去）。
	for sz: float in [-1.0, 1.0]:
		_add_box(housing, "Retainer", Vector3(0.30, 0.03, 0.03),
			Vector3(0.0, rest_y + 0.16, sz * (WELL_HALF + 0.02)), steel)

	# 顶杆（真实刚体，0.5 kg）
	plunger = RigidBody3D.new()
	plunger.name = "Plunger"
	plunger.mass = 0.5
	plunger.gravity_scale = 1.0
	plunger.linear_damp = 0.0
	plunger.angular_damp = 2.0
	plunger.lock_rotation = true
	plunger.continuous_cd = true
	plunger.can_sleep = false
	plunger.collision_layer = plunger_layer
	plunger.collision_mask = plunger_mask
	plunger.contact_monitor = true
	plunger.max_contacts_reported = 6
	var pmat: PhysicsMaterial = PhysicsMaterial.new()
	pmat.friction = 0.4
	pmat.bounce = 0.0
	plunger.physics_material_override = pmat
	add_child(plunger)
	plunger.global_position = global_position + Vector3(0.0, rest_y, 0.0)
	var pmi: MeshInstance3D = MeshInstance3D.new()
	pmi.name = "PlungerMesh"
	var pm: BoxMesh = BoxMesh.new()
	pm.size = Vector3(0.13, 0.26, 0.13)
	pmi.mesh = pm
	pmi.material_override = brass
	plunger.add_child(pmi)
	var pcs: CollisionShape3D = CollisionShape3D.new()
	var pbs: BoxShape3D = BoxShape3D.new()
	pbs.size = Vector3(0.13, 0.26, 0.13)
	pcs.shape = pbs
	plunger.add_child(pcs)
	# 与静态外壳之间不互相碰撞（否则会卡在井壁里）。
	plunger.add_collision_exception_with(housing)

	# 指示灯：纯视觉，必须**没有碰撞体**（放在杠杆运动路径上的实体灯
	# 会让杠杆卡住 —— 这是历史 Bug）。
	var lamp: MeshInstance3D = MeshInstance3D.new()
	lamp.name = "Lamp"
	var lbm: BoxMesh = BoxMesh.new()
	lbm.size = Vector3(0.08, 0.08, 0.08)
	lamp.mesh = lbm
	lamp.material_override = brass
	lamp.position = Vector3(0.22, rest_y + 0.12, 0.0)
	housing.add_child(lamp)
	add_to_group("lis_limit_switch")


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


func _physics_process(delta: float) -> void:
	if plunger == null:
		return
	var y: float = plunger.global_position.y - global_position.y
	compression = clampf(rest_y - y, 0.0, travel)
	# 弹簧：只在被压下去时回弹（F = k·压缩量 − c·速度）。
	var vy: float = plunger.linear_velocity.y
	var spring_force: float = SPRING_K * (rest_y - y) - SPRING_C * vy
	spring_force = clampf(spring_force, -80.0, 90.0)
	plunger.apply_central_force(Vector3(0.0, spring_force, 0.0))

	# 接触判定：顶杆当前是否真的被某个刚体压着。
	pressed_by = ""
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(plunger.get_rid())
	if state != null:
		for i in range(state.get_contact_count()):
			var obj: Object = state.get_contact_collider_object(i)
			var n: Node = obj as Node
			if n == null or n == housing:
				continue
			if pressed_by_class != "" and not _matches_class(n, pressed_by_class):
				continue
			pressed_by = str(n.name)
			break

	# 迟滞判定：必须"压够深 + 确实被压着"。
	var now_closed: bool = compression >= PRESS_CLOSE and pressed_by != ""
	if closed and compression < PRESS_OPEN:
		now_closed = false
	if now_closed != closed:
		closed = now_closed
		state_changed.emit(closed)
	var _unused: float = delta


func _matches_class(n: Node, cls: String) -> bool:
	if n.is_class(cls):
		return true
	var s: Script = n.get_script() as Script
	while s != null:
		var sp: Script = s.get_base_script()
		if sp != null and sp.get_global_name() == cls:
			return true
		s = sp
	return false


func is_closed() -> bool:
	return closed


func reset_switch() -> void:
	closed = false
	compression = 0.0
	pressed_by = ""
	if plunger != null:
		plunger.linear_velocity = Vector3.ZERO
		plunger.angular_velocity = Vector3.ZERO
		plunger.global_position = global_position + Vector3(0.0, rest_y, 0.0)
