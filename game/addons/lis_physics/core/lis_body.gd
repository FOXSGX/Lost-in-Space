class_name LISBody
extends RigidBody3D
## LIS Physics SDK · 通用可抓握刚体
##
## 这是 SDK 最基础的物理物体。它只做三件事：
##   1. 按 LISBodyProfile 建立真实的碰撞体、质量、摩擦、阻尼与层掩码；
##   2. 记录"谁在抓我"（多持有者模型，最多 4 人）；
##   3. 提供表面抓握点几何与状态查询。
##
## 它**不做**的事（重要）：
##   * 不写自己的 transform —— 位置全部由 Jolt 积分产生；
##   * 不冻结自己、不关碰撞 —— 被抓握时仍然参与真实碰撞；
##   * 不向抓握者施力 —— 施力由 LISGrabber 在真实接触点上完成。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_prop.gd
## 解耦改动：
##   * 去掉对 "interactable" 组与 get_prompt()/interact(player) 的强依赖
##     （改为可选别名组；提示文本改由 LISInteractionPrompt 提供）；
##   * 移除对 PlayerController 的任何假设（旧版 _nearest_player 只在提示里用，
##     新版提示由抓握者自己带玩家信息）；
##   * 质量 / 摩擦 / 层掩码全部改为参数，不再硬编码 8 / 1|2|8。

signal grabbed_by(body: LISBody, grabber: Node3D)
signal released_by(body: LISBody, thrown: bool)
signal holder_count_changed(body: LISBody, count: int)

## 同一件物体最多允许多少个抓握者。任务书要求支持 4 人共同施力。
const MAX_HOLDERS := 4
const GROUP_INTERACTABLE := "lis_interactable"
const GROUP_BODY := "lis_body"

## 参数对象。为空时使用内联字段的默认值。
@export var profile: LISBodyProfile

## 内联参数（profile 为空或未使用时生效；apply_profile() 会把 profile 写进来）
@export var display_name: String = "物理物体"
@export var mass_kg: float = 12.0
@export var friction: float = 0.7
@export var bounce: float = 0.02
@export var liftable: bool = true
@export var body_size: Vector3 = Vector3(0.6, 0.6, 0.6)
@export var auto_build_visual: bool = true

## 网络镜像：true 时本地不积分，只接受快照（客户端只读镜像）。
var network_mirror: bool = false

## 多持有者登记。**只登记谁在抓，不改位姿。**
var holders: Array[Node3D] = []

var _handle_nodes: Array[MeshInstance3D] = []
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _material: PhysicsMaterial
var _built: bool = false
var _applied_profile: bool = false
## 最近一次"有人在对我施力"的需求力（N）、方向与距今时间。
var _constrain_demand: float = 0.0
var _constrain_dir: Vector3 = Vector3.ZERO
var _constrain_age: float = 999.0


func _physics_process(delta: float) -> void:
	_constrain_age += delta
	if _constrain_age > 0.25:
		_constrain_demand = 0.0


func _ready() -> void:
	if profile != null and not _applied_profile:
		apply_profile(profile)
	if not _built:
		_build_from_inline()


# ---------------------------------------------------------------------------
# 参数应用
# ---------------------------------------------------------------------------

## 应用一份参数对象并建立几何。可在运行时调用（会重建碰撞体与视觉）。
func apply_profile(p: LISBodyProfile) -> void:
	if p == null:
		return
	profile = p
	_applied_profile = true
	var notes: PackedStringArray = p.sanitize()
	for n: String in notes:
		push_warning("[LIS Physics] %s: %s" % [p.display_name, n])
	display_name = p.display_name
	mass_kg = p.mass_kg
	friction = p.friction
	bounce = p.bounce
	liftable = p.liftable
	body_size = p.size
	_clear_visual()
	_apply_body_settings(
		p.mass_kg, p.friction, p.bounce, p.rough,
		p.linear_damp, p.angular_damp, p.can_sleep, p.continuous_cd,
		p.contact_monitor, p.max_contacts,
		p.collision_layer, p.collision_mask,
		p.use_custom_center_of_mass, p.center_of_mass, p.inertia,
		p.gravity_scale
	)
	if auto_build_visual and p.color.a > 0.0:
		_build_visual(p.color, p.metallic, p.roughness, p.emission, p.emission_energy, p.grip_handles)
	# 碰撞体与视觉分离：碰撞体是物理必需品，无论是否要视觉都要建。
	_ensure_collision_shape()
	_register_groups(p.interactable, p.group_aliases)
	_built = true


func _build_from_inline() -> void:
	if not body_size.is_equal_approx(Vector3.ONE) and _has_visual_child():
		# 使用者在场景里自己搭了 Mesh + CollisionShape：只应用数值参数，不重建几何。
		_apply_body_settings(
			mass_kg, friction, bounce, true, 0.06, 0.35, true, true, true, 4,
			LISPhysics.DEFAULT_BODY_LAYER, LISPhysics.DEFAULT_BODY_MASK,
			false, Vector3.ZERO, Vector3.ZERO, 1.0)
	else:
		_clear_visual()
		_apply_body_settings(
			mass_kg, friction, bounce, true, 0.06, 0.35, true, true, true, 4,
			LISPhysics.DEFAULT_BODY_LAYER, LISPhysics.DEFAULT_BODY_MASK,
			false, Vector3.ZERO, Vector3.ZERO, 1.0)
		if auto_build_visual:
			_build_visual(Color(0.62, 0.52, 0.32), 0.15, 0.72, false, 0.35, 2)
		_ensure_collision_shape()
	_register_groups(true, PackedStringArray())
	_built = true


func _has_visual_child() -> bool:
	for c: Node in get_children():
		if c is CollisionShape3D:
			return true
	return false


func _apply_body_settings(
	p_mass: float, p_friction: float, p_bounce: float, p_rough: bool,
	p_lin_damp: float, p_ang_damp: float, p_can_sleep: bool, p_ccd: bool,
	p_contact_monitor: bool, p_max_contacts: int,
	p_layer: int, p_mask: int,
	p_custom_com: bool, p_com: Vector3, p_inertia: Vector3,
	p_gravity_scale: float
) -> void:
	mass = maxf(p_mass, 0.05)
	gravity_scale = p_gravity_scale
	linear_damp = p_lin_damp
	angular_damp = p_ang_damp
	can_sleep = p_can_sleep
	continuous_cd = p_ccd
	collision_layer = p_layer
	collision_mask = p_mask
	contact_monitor = p_contact_monitor
	max_contacts_reported = p_max_contacts
	if p_custom_com:
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = p_com
	else:
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_AUTO
	if p_inertia != Vector3.ZERO:
		inertia = p_inertia
	_material = PhysicsMaterial.new()
	_material.friction = p_friction
	_material.bounce = p_bounce
	_material.rough = p_rough
	physics_material_override = _material


func _register_groups(enabled: bool, aliases: PackedStringArray) -> void:
	if enabled:
		add_to_group(GROUP_BODY)
		add_to_group(GROUP_INTERACTABLE)
	else:
		remove_from_group(GROUP_BODY)
		remove_from_group(GROUP_INTERACTABLE)
	for a: String in aliases:
		if a.strip_edges() != "":
			add_to_group(a)


# ---------------------------------------------------------------------------
# 几何
# ---------------------------------------------------------------------------

## 立即摘掉并释放几何子节点。
##
## 为什么用 remove_child + free 而不是 queue_free：`_has_visual_child()` 靠
## "有没有 CollisionShape3D 子节点"判断，而 queue_free 的节点要到帧末才消失。
## 若用 queue_free，紧随其后的 `_ensure_collision_shape()` 会看到"旧的还在"，
## 于是既不建新碰撞体、旧的又在本帧末消失 —— 物体变成没有碰撞体的幽灵。
func _clear_visual() -> void:
	_detach_and_free(_mesh)
	_mesh = null
	_detach_and_free(_shape)
	_shape = null
	for h: MeshInstance3D in _handle_nodes:
		_detach_and_free(h)
	_handle_nodes.clear()


func _detach_and_free(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n.get_parent() == self:
		remove_child(n)
	n.free()


func _build_visual(
	color: Color, metallic: float, roughness: float,
	emission: bool, emission_energy: float, handle_count: int
) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_energy

	_mesh = MeshInstance3D.new()
	_mesh.name = "BodyMesh"
	var box: BoxMesh = BoxMesh.new()
	box.size = body_size
	_mesh.mesh = box
	_mesh.material_override = mat
	add_child(_mesh)

	# 抓握把手：贴在物体表面的实体几何（不是悬浮提示文字）。
	if handle_count > 0:
		var hmat: StandardMaterial3D = StandardMaterial3D.new()
		hmat.albedo_color = color.darkened(0.35)
		hmat.roughness = 0.45
		hmat.metallic = 0.65
		for i in range(handle_count):
			var t: float = (float(i) + 0.5) / float(handle_count)
			var handle: MeshInstance3D = MeshInstance3D.new()
			handle.name = "Grip"
			var hm: BoxMesh = BoxMesh.new()
			hm.size = Vector3(body_size.x * 0.34, 0.055, 0.05)
			handle.mesh = hm
			handle.material_override = hmat
			handle.position = Vector3(0.0, body_size.y * (t - 0.5) * 0.7, body_size.z * 0.5 + 0.03)
			add_child(handle)
			_handle_nodes.append(handle)


## 确保存在碰撞体。
##
## 【为什么必须与视觉分开】
## 历史实现把"建网格"和"建碰撞体"写在同一处，并且只由 auto_build_visual 控制。
## 于是 `auto_build_visual = false` 的物体（无头性能测试、纯逻辑刚体、
## 已经有美术资源的物体）**完全没有碰撞体**：它会直接穿过地面无限下落。
## 实测：性能基准里 20/50/100/200 个刚体全部 below_floor，物理接触数为 0。
##
## 正确语义：碰撞体是物理必需品，**总是**建；视觉才是可选的。
## 使用者若在场景里自带 CollisionShape3D，则不重复添加。
func _ensure_collision_shape() -> void:
	if _has_visual_child():
		return
	_shape = CollisionShape3D.new()
	_shape.name = "BodyShape"
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = body_size
	_shape.shape = bs
	add_child(_shape)


## 现存碰撞体的外形尺寸（米）。有自定义几何时优先返回碰撞体的真实尺寸。
func size() -> Vector3:
	if _shape != null and is_instance_valid(_shape) and _shape.shape is BoxShape3D:
		return (_shape.shape as BoxShape3D).size
	for c: Node in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return ((c as CollisionShape3D).shape as BoxShape3D).size
	return body_size


func extent_along(dir: Vector3) -> float:
	return LISPhysics.extent_along(size(), dir)


func half_extent() -> float:
	return size().length() * 0.5


## 从 from（世界坐标）看向本物体时，物体表面上最近的一点。
## 抓握点由几何决定，不由脚本指定 —— 这是"真实接触点"的最低要求。
func grab_point_toward(from: Vector3) -> Vector3:
	var s: Vector3 = size()
	var local_from: Vector3 = to_local(from)
	var half: Vector3 = s * 0.5
	var clamped: Vector3 = Vector3(
		clampf(local_from.x, -half.x, half.x),
		clampf(local_from.y, -half.y, half.y),
		clampf(local_from.z, -half.z, half.z)
	)
	if clamped.distance_to(local_from) < 0.001:
		# 起点在盒内：推向最近的一个面
		var dx: float = half.x - absf(local_from.x)
		var dy: float = half.y - absf(local_from.y)
		var dz: float = half.z - absf(local_from.z)
		if dx <= dy and dx <= dz:
			clamped.x = signf(local_from.x) * half.x if absf(local_from.x) > 0.001 else half.x
		elif dy <= dz:
			clamped.y = signf(local_from.y) * half.y if absf(local_from.y) > 0.001 else half.y
		else:
			clamped.z = signf(local_from.z) * half.z if absf(local_from.z) > 0.001 else half.z
	return to_global(clamped)


# ---------------------------------------------------------------------------
# 多持有者（独立抓握点，力在物理世界里合成）
# ---------------------------------------------------------------------------

func add_holder(grabber: Node3D, pid: int = 0) -> bool:
	if grabber == null or not is_instance_valid(grabber):
		return false
	if holders.has(grabber):
		return true
	if holders.size() >= MAX_HOLDERS:
		return false
	holders.append(grabber)
	sleeping = false
	grabbed_by.emit(self, grabber)
	holder_count_changed.emit(self, holders.size())
	return true


func remove_holder(grabber: Node3D) -> void:
	var idx: int = holders.find(grabber)
	if idx < 0:
		return
	holders.remove_at(idx)
	holder_count_changed.emit(self, holders.size())


func holder_count() -> int:
	return holders.size()


func is_held_by(grabber: Node3D) -> bool:
	return holders.has(grabber)


func is_held() -> bool:
	return not holders.is_empty()


## 仍在树中的有效抓握者。
func live_holders() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for h: Node3D in holders:
		if is_instance_valid(h) and h.is_inside_tree():
			out.append(h)
	return out


## 清理已失效的抓握者（玩家离场、节点被销毁）。返回清理数量。
func prune_dead_holders() -> int:
	var keep: Array[Node3D] = []
	var removed: int = 0
	for h: Node3D in holders:
		if is_instance_valid(h) and h.is_inside_tree():
			keep.append(h)
		else:
			removed += 1
	if removed > 0:
		holders = keep
		holder_count_changed.emit(self, holders.size())
	return removed


func clear_holders() -> void:
	var copy: Array[Node3D] = holders.duplicate()
	for h: Node3D in copy:
		remove_holder(h)


# ---------------------------------------------------------------------------
# 状态查询（受阻 / 安全复位 / 销毁）
# ---------------------------------------------------------------------------

## 受阻：**有外部施力需求**却被接触挡住，且挡住的方向与施力方向相反。
##
## 关键语义：静止在地面上的箱子有接触、速度也是 0，但它不"受阻" ——
## 没有人在推它；就算有人水平推，地面接触的法线是竖直的，不构成"阻挡"。
## 所以判定要求三件事同时成立：
##   1. 施力方（抓握器 / 身体推挤 / 场景脚本）上报了需求力与方向；
##   2. 真实接触里存在一条法线**反对外施力方向**的接触（法线·方向 < −0.3）；
##   3. 该方向上的速度被压住。
func note_constrained_force(demand: float, dir_world: Vector3 = Vector3.ZERO) -> void:
	_constrain_demand = maxf(demand, 0.0)
	_constrain_dir = dir_world.normalized() if dir_world.length_squared() > 1.0e-6 else Vector3.ZERO
	_constrain_age = 0.0


## 受阻：真实接触方向反对外施力 + 该方向速度被压住。
func is_blocked() -> bool:
	if not contact_monitor or _constrain_demand <= 0.0:
		return false
	if _constrain_age > 0.25:
		return false
	if get_contact_count() <= 0:
		return false
	var dir: Vector3 = _constrain_dir
	if dir == Vector3.ZERO:
		# 没给方向时退化为"任意接触 + 速度很低"，但要求角速度也低。
		return linear_velocity.length() < 0.35 and angular_velocity.length() < 1.2
	# 找一条法线反对外施力方向的接触
	var opposed: bool = false
	var st: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(get_rid())
	if st != null:
		for i in range(st.get_contact_count()):
			var n: Vector3 = st.get_contact_local_normal(i)
			if n.dot(dir) < -0.30:
				opposed = true
				break
	if not opposed:
		return false
	# 该方向上的速度被压住（沿施力方向几乎不动）
	return absf(linear_velocity.dot(dir)) < 0.35


## 有效质量（kg），按 gravity_scale 折算。用于"是否举得动"的判断与 HUD 显示。
func effective_weight() -> float:
	return mass * 9.81 * gravity_scale


## 真实接触数量（需要 contact_monitor）。
func contact_count() -> int:
	return get_contact_count() if contact_monitor else 0


## 唤醒刚体。
##
## 为什么单独提供：Godot 的 `apply_force()` / `apply_central_force()`
## **不会唤醒休眠刚体**。一台停稳在地面上的推车会进入 sleep，
## 之后每帧施加的推力一点效果都没有（实测位移 0.0007 m）——
## 这是引擎的优化行为，不是物理错误，但会让"推不动的车"看起来像 bug。
## 任何对静止物体持续施力的代码都应先调用本方法（或用下面的 push* 系列）。
func wake() -> void:
	sleeping = false


## 施力并确保物体是醒着的（推荐用这个，而不是裸的 apply_force）。
func push_force(force: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	if sleeping:
		sleeping = false
	apply_force(force, offset)


## 施加中心力并唤醒。
func push_force_centered(force: Vector3) -> void:
	if sleeping:
		sleeping = false
	apply_central_force(force)


## 施加冲量并唤醒。
func push_impulse(impulse: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	if sleeping:
		sleeping = false
	apply_impulse(impulse, offset)


## 安全复位：搬回位姿并清速度。
##
## 注意：这里是**重置**语义，不是运动。调用方（复位按钮 / 测试）显式要求
## 物体回到初始位姿时才允许写 transform；正常玩法路径绝不调用它。
func reset_to(pose: Transform3D) -> void:
	if not is_inside_tree():
		return
	sleeping = false
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = pose
	clear_holders()


## 安全销毁：先清持有关系，避免任何抓握者持有已释放引用。
func despawn() -> void:
	clear_holders()
	queue_free()


## 被删除时通知所有抓握者立刻松手。
##
## 【为什么需要它】
## "释放刚体之前，必须正确处理引用它的东西"这条规则不只适用于**关节**，
## 同样适用于**持有关系**：玩家完全可能正抓着一件物体，而场景把物体销毁了
## （关卡切换、机关被拆除、程序化生成的物体被回收）。
##
## 如果只在抓握器一侧用 `is_instance_valid()` 兜底，抓握器内部仍会短暂持有一个
## 指向已释放对象的引用；在"删除发生在物理帧之间"的时序里，这个窗口足以
## 产生间歇性的访问冲突（实测：缆绳用例重复 10 轮有 3 轮在退出时 0xC0000005，
## 而 14 条断言全部通过）。
##
## 因此这里在删除**之前**主动断开：让每一名持有者立刻把 `held` 置空。
## 这不改变任何物理参数，只是把清理提前到对象仍然有效的时刻。
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	var copy: Array[Node3D] = holders.duplicate()
	holders.clear()
	for h: Node3D in copy:
		if h != null and is_instance_valid(h) and h.has_method("on_body_predelete"):
			h.call("on_body_predelete", self)


# ---------------------------------------------------------------------------
# 网络镜像（客户端只读）
# ---------------------------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"pos": global_position,
		"rot": rotation,
		"lin": linear_velocity,
		"ang": angular_velocity,
		"sleep": sleeping,
		"held": is_held(),
		"holders": holder_count(),
	}


func apply_snapshot(data: Dictionary) -> void:
	if data.is_empty():
		return
	global_position = data.get("pos", global_position) as Vector3
	rotation = data.get("rot", rotation) as Vector3
	linear_velocity = data.get("lin", Vector3.ZERO) as Vector3
	angular_velocity = data.get("ang", Vector3.ZERO) as Vector3


## 客户端镜像：本地停止物理积分，避免出现第二个物理权威。
func enable_mirror(enabled: bool) -> void:
	network_mirror = enabled
	freeze = enabled
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func describe() -> String:
	return "%s · %.2f kg · %s" % [display_name, mass, str(size())]
