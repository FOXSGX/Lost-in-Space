class_name Act1WheelChock
extends Node3D
## MECHANICS-001D · 车轮止轮楔（真实刚体）
##
## 改造前：`WheelChockVisual` 只是一块无碰撞网格，按 E 直接 `visible=false`。
## 改造后：14 kg 楔块真实压在地面上、被 -X 挡边和上方的轮肩夹住；
## 玩家按 E 启动卷扬/撬棍执行器沿 +X 拉出，楔块真实滑出 ≥0.30 m 才算"移走"。
##
## 依据 MECHANICS-001B/001C 的经验：不用关节，力 + 静态止挡 + 实体碰撞。

const CHOCK_MASS := 14.0
const PULL_FORCE := 300.0        # N，> 14 kg × g ≈ 137 N
const PULL_SECONDS := 0.85
const REMOVED_TRAVEL := 0.30     # m
const SIZE := Vector3(0.55, 0.34, 0.85)

var body: RigidBody3D
var _home := Vector3.ZERO
var _timer := 0.0
var _pending_reset := false


func setup(host: Node, pos: Vector3) -> void:
	name = "WheelChock"
	host.add_child(self)
	_build(pos)


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


func _build(pos: Vector3) -> void:
	# 轮肩：楔块上方压着的轮子下缘（静态），让它"卡在轮下"
	_static_box("ChockWheelShoulder", Vector3(0.80, 0.34, 1.10),
		pos + Vector3(-0.10, 0.62, 0.0), Color(0.22, 0.22, 0.26))
	# -X 挡边：楔块不能被推得更深
	_static_box("ChockBackStop", Vector3(0.70, 0.40, 0.14),
		pos + Vector3(0.0, 0.20, 0.42), Color(0.30, 0.26, 0.20))

	body = RigidBody3D.new()
	body.name = "WheelChockBody"
	body.mass = CHOCK_MASS
	body.can_sleep = false
	body.gravity_scale = 1.0
	body.linear_damp = 1.6
	body.angular_damp = 2.2
	body.collision_layer = 4
	body.collision_mask = 1 | 2 | 4 | 16
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = SIZE
	cs.shape = bs
	body.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = SIZE
	mi.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.62, 0.16)
	mi.material_override = mat
	body.add_child(mi)
	# 斜面板（视觉上像楔子）
	var ramp: MeshInstance3D = MeshInstance3D.new()
	var rbm: BoxMesh = BoxMesh.new()
	rbm.size = Vector3(0.52, 0.10, 0.80)
	ramp.mesh = rbm
	ramp.position = Vector3(0.02, 0.20, 0.0)
	ramp.rotation = Vector3(0.0, 0.0, -0.42)
	var rmat: StandardMaterial3D = StandardMaterial3D.new()
	rmat.albedo_color = Color(0.88, 0.72, 0.20)
	ramp.material_override = rmat
	body.add_child(ramp)
	add_child(body)
	body.global_position = pos
	_home = pos


func pull() -> bool:
	if removed():
		return false
	_timer = PULL_SECONDS
	body.sleeping = false
	return true


func removed() -> bool:
	if body == null:
		return false
	return (_home.z - body.global_position.z) >= REMOVED_TRAVEL


func blocked() -> bool:
	# 楔块仍卡在原位（位移不足以判定移走）
	return not removed()


func _physics_process(delta: float) -> void:
	if body == null:
		return
	# 刚体传送必须在物理步内生效，否则会被上一帧的物理状态覆盖（MECHANICS-001F 实测）
	if _pending_reset:
		_pending_reset = false
		body.global_position = _home
		body.rotation = Vector3.ZERO
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	if _timer > 0.0:
		_timer = maxf(0.0, _timer - delta)
		body.sleeping = false
		body.apply_central_force(Vector3(0.0, 0.0, -PULL_FORCE))


func reset_chock() -> void:
	_timer = 0.0
	if body != null:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.global_position = _home
		body.rotation = Vector3.ZERO
		_pending_reset = true
