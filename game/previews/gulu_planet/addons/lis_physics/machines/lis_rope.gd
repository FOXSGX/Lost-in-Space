class_name LISRope
extends Node3D
## LIS Physics SDK · 真实多体缆绳
##
## 由 N 个带质量的 RigidBody3D 绳段串联，相邻段用球铰（Generic6DOF 线性锁死）连接。
## 球铰允许自由转动（能弯曲、能下垂），但不允许拉伸 ——
## 这是"缆绳能传拉力、不能传推力"的物理基础。
##
## 质量与绳径自洽（不是为凑稳定性填的数）：
##   A = π r² = π × 0.021² = 1.385e-3 m²
##   填充率 η ≈ 0.60（6×36 IWRC 钢丝绳典型值）
##   钢密度 ρ = 7850 kg/m³
##   线密度 λ = A·η·ρ = 6.52 kg/m ；0.34 m 段 → 2.22 kg
##
## 来源：work/final-integration-001/project/scripts/physics/phys_rope.gd
## 解耦改动：
##   * 关节创建与排序改走 LISJointKit（统一的生命周期修正）；
##   * PhysRopeEnd → LISRopeEnd；
##   * 组名 "phys_rope" → "lis_rope"；保留 "rope_end" 兼容别名由使用者自行加。
##
## 关键修正在这里（历史 Bug，必须保留）：
##   `order_joints_first()` 把关节排到所有绳段之前。否则引擎按 children 顺序
##   先释放"段{i}"、再释放引用它的"关节{i+1}"，Jolt 的约束对象持有
##   已释放刚体指针 → 第二次访问就是 access violation（实测 0xC0000005）。

signal rope_taut_changed(taut: bool)

## 绳半径（米）。42 mm 直径钢丝绳。
const SEGMENT_RADIUS := 0.021
const STEEL_FILL_FACTOR := 0.60
const STEEL_DENSITY := 7850.0
## 判定"绷紧"的阈值：两端直线距离 / 自然长度。
const TAUT_RATIO := 0.94
## 碰撞圆柱相对段长的比例（略短于视觉，避免相邻段接触抖动）。
const COLLISION_LEN_FACTOR := 0.94
const GROUP_ROPE := "lis_rope"

var segments: Array[RigidBody3D] = []
var joints: Array[PinJoint3D] = []
var segment_count: int = 8
var segment_length: float = 0.34
var anchor_a: Node3D = null
var anchor_b: Node3D = null
var free_end: LISRopeEnd = null
## 绳段碰撞层 / 掩码（默认与世界、玩家、同类碰撞）。
@export_flags_3d_physics var rope_layer: int = LISPhysics.LAYER_PROP
@export_flags_3d_physics var rope_mask: int = LISPhysics.DEFAULT_BODY_MASK
## 绳索视觉是否生成（无头测试可关掉）。
@export var build_visual: bool = true

## 每个关节的真实约束锚点，存成两端刚体的局部坐标。
var _links: Array[Dictionary] = []
var _built: bool = false
## 拆卸已开始：停止一切测量，避免解引用正在释放的节点。
var _shutting_down: bool = false
var _taut: bool = false
var _rest_length: float = 0.0


func _ready() -> void:
	add_to_group(GROUP_ROPE)


## 构建一条缆绳。from_world 为世界坐标，dir 为单位方向。
##
## bend_deg：初始铺设的**总转角**（度）。0 = 直线；正值把绳摊成一段圆弧
## （弧长不变、弦长变短），用来得到"静置时松弛"的初始状态。
## 松弛必须在**建关节之前**摆好：关节锚点在建关节那一刻写死，
## 建完再挪绳段会被物理引擎第一帧猛地拽回直线。
func build(
	p_segment_count: int,
	p_segment_length: float,
	from_world: Vector3,
	dir: Vector3,
	with_free_end: bool = true,
	bend_deg: float = 0.0
) -> void:
	if _built:
		return
	_built = true
	segment_count = maxi(p_segment_count, 6)
	segment_length = maxf(p_segment_length, 0.10)
	_rest_length = float(segment_count) * segment_length

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.66, 0.42)
	mat.roughness = 0.85
	mat.metallic = 0.25

	var d: Vector3 = dir.normalized()
	var up_ref: Vector3 = Vector3.UP
	if absf(d.dot(up_ref)) > 0.99:
		up_ref = Vector3.RIGHT
	var axis: Vector3 = up_ref.normalized()
	var total_turn: float = deg_to_rad(bend_deg)
	var step_turn: float = total_turn / float(segment_count)

	# 初始铺设路径：从 from_world 出发、总转角 bend_deg 的等曲率折线。
	# pts[i] 是第 i 个关节的世界坐标（pts[0] = 起点，pts[count] = 末端）。
	var pts: Array[Vector3] = []
	var cur_dir: Vector3 = d.rotated(axis, -total_turn * 0.5)
	var p: Vector3 = from_world
	pts.append(p)
	for i in range(segment_count):
		cur_dir = cur_dir.rotated(axis, step_turn)
		p += cur_dir * segment_length
		pts.append(p)

	var prev: RigidBody3D = null
	for i in range(segment_count):
		var seg: RigidBody3D = RigidBody3D.new()
		seg.name = "Seg%d" % i
		seg.mass = segment_mass_for(segment_length)
		seg.gravity_scale = 1.0
		seg.linear_damp = 0.55
		seg.angular_damp = 2.2
		seg.continuous_cd = true
		seg.collision_layer = rope_layer
		seg.collision_mask = rope_mask
		# 绳段自己的摩擦：不给 PhysicsMaterial 时引擎默认 1.0，
		# 等于"橡胶绳在地上"。42 mm 钢丝绳在水泥地上滑动约 0.35–0.45，取 0.40。
		var rope_mat: PhysicsMaterial = PhysicsMaterial.new()
		rope_mat.friction = 0.40
		rope_mat.bounce = 0.0
		rope_mat.rough = true
		seg.physics_material_override = rope_mat
		seg.can_sleep = true
		# 接触监视：绳索撞障碍的查询依赖 get_colliding_bodies()，
		# 它在 contact_monitor = false 时永远是空的。
		seg.contact_monitor = true
		seg.max_contacts_reported = 4
		var span: Vector3 = pts[i + 1] - pts[i]
		var seg_basis: Basis = Basis.looking_at(span.normalized(), up_ref)
		seg.position = to_local((pts[i] + pts[i + 1]) * 0.5)

		if build_visual:
			# 视觉：长度 = 段长，首尾相接，不会出现"珠子串"式缝隙。
			var mi: MeshInstance3D = MeshInstance3D.new()
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = SEGMENT_RADIUS
			cyl.bottom_radius = SEGMENT_RADIUS
			cyl.height = segment_length
			cyl.radial_segments = 10
			cyl.rings = 1
			mi.mesh = cyl
			mi.material_override = mat
			# CylinderMesh 轴向为 Y；旋转 +90°(X) 后指向刚体局部 +Z，
			# 而 basis.looking_at 让局部 -Z 指向 d，故圆柱沿绳方向。
			mi.rotation = Vector3(PI * 0.5, 0, 0)
			seg.add_child(mi)

		# 碰撞体：略短，避免相邻段在弯折时互相挤压抖动。
		var cs: CollisionShape3D = CollisionShape3D.new()
		var cap: CylinderShape3D = CylinderShape3D.new()
		cap.radius = SEGMENT_RADIUS
		cap.height = segment_length * COLLISION_LEN_FACTOR
		cs.shape = cap
		cs.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		seg.add_child(cs)

		seg.basis = seg_basis
		add_child(seg)
		segments.append(seg)

		if prev != null:
			# 关节锚点必须落在**实际铺设路径**的端点上（pts[i]），
			# 用直线公式会在 bend ≠ 0 时把关节放到弧外，第一帧就把绳段拽回去。
			_add_joint("Joint%d" % i, prev, seg, pts[i], "seg")
		prev = seg

	if with_free_end:
		free_end = LISRopeEnd.new()
		free_end.name = "FreeEnd"
		free_end.rope = self
		add_child(free_end)
		# 必须在 setup 造成 configure() **之后**指定位置（configure 会重置位姿）。
		free_end.set_pending_position(pts[segment_count])
		if not segments.is_empty():
			_add_joint("EndJoint", segments[segments.size() - 1], free_end, pts[segment_count], "end")
	LISJointKit.order_joints_first(self)


## 按材料与几何推出绳段质量（kg）。段长变化时质量自动跟着变，线密度恒定。
func segment_mass_for(length_m: float) -> float:
	var area: float = PI * SEGMENT_RADIUS * SEGMENT_RADIUS
	var linear_density: float = area * STEEL_FILL_FACTOR * STEEL_DENSITY
	return maxf(0.05, linear_density * length_m)


func _add_joint(nm: String, a: Node3D, b: Node3D, world_pos: Vector3, kind: String) -> PinJoint3D:
	var pj: PinJoint3D = LISJointKit.create_pin(self, nm, a, b, world_pos)
	joints.append(pj)
	_links.append({
		"a": a,
		"b": b,
		"la": a.to_local(world_pos),
		"lb": b.to_local(world_pos),
		"kind": kind,
	})
	return pj


func get_free_end() -> LISRopeEnd:
	return free_end


## 绳尾绑住的刚体（被牵引的货物）。没绑就是 null。
func get_tied_body() -> Node3D:
	return anchor_b


## 把第一段锚定到静态锚柱或可移动物体。at 为锚点世界坐标。
func anchor_first_to(body_to_anchor: Node3D, at: Vector3 = Vector3(INF, INF, INF)) -> void:
	if body_to_anchor == null or segments.is_empty():
		return
	anchor_a = body_to_anchor
	var p: Vector3 = body_to_anchor.global_position
	if is_finite(at.x) and is_finite(at.y) and is_finite(at.z):
		p = at
	_add_joint("AnchorJoint", body_to_anchor, segments[0], p, "anchor")
	LISJointKit.order_joints_first(self)


## 把绳尾绑到被牵引物体上（锚点取物体表面而不是中心，否则绳头会埋进货物里）。
func tie_last_to(body_to_tie: Node3D, at: Vector3 = Vector3(INF, INF, INF)) -> void:
	if body_to_tie == null or segments.is_empty():
		return
	anchor_b = body_to_tie
	var p: Vector3 = body_to_tie.global_position
	if is_finite(at.x) and is_finite(at.y) and is_finite(at.z):
		p = at
	_add_joint("TieJoint", segments[segments.size() - 1], body_to_tie, p, "tie")
	LISJointKit.order_joints_first(self)


# ---------------------------------------------------------------------------
# 测量（真实锚点分离，不是刚体中心距）
# ---------------------------------------------------------------------------

func _link_gap(l: Dictionary) -> float:
	var a: Node3D = l["a"]
	var b: Node3D = l["b"]
	if not is_instance_valid(a) or not is_instance_valid(b):
		return 0.0
	var wa: Vector3 = a.global_transform * (l["la"] as Vector3)
	var wb: Vector3 = b.global_transform * (l["lb"] as Vector3)
	return wa.distance_to(wb)


## 相邻绳段之间的真实锚点分离（米）。理想值 0。
func max_joint_gap() -> float:
	var worst: float = 0.0
	for l: Dictionary in _links:
		if str(l["kind"]) != "seg":
			continue
		worst = maxf(worst, _link_gap(l))
	return worst


## 与外部物体（锚柱 / 货物 / 绳端）之间的真实锚点分离（米）。
func max_attach_gap() -> float:
	var worst: float = 0.0
	for l: Dictionary in _links:
		if str(l["kind"]) == "seg":
			continue
		worst = maxf(worst, _link_gap(l))
	return worst


func max_any_gap() -> float:
	var worst: float = 0.0
	for l: Dictionary in _links:
		worst = maxf(worst, _link_gap(l))
	return worst


## 当前链长（米）= 相邻绳段**质心之间**距离之和。
##
## 【为什么不能用"锚点分离之和"】
## 历史实现把每个关节的两端局部锚点变换回世界再求距离、然后累加。
## 但那些锚点在建关节那一刻就是同一个世界点，所以这个量测的是
## **关节被拉开多少**（理想值 0），不是绳有多长。
## 实测：`stretch_ratio()` 永远读到 −1.0000（−100%），因为分子恒为 0。
## 质心距才是链长：完全伸直时 = (N−1)·段长，与 stretch_ratio 的基准一致。
func current_length() -> float:
	var total: float = 0.0
	for i in range(segments.size() - 1):
		var a: RigidBody3D = segments[i]
		var b: RigidBody3D = segments[i + 1]
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		total += a.global_position.distance_to(b.global_position)
	return total


## 整绳伸长率：当前链长 / 自然长度 − 1。0 = 没有伸长。
func stretch_ratio() -> float:
	var base: float = segment_length * float(maxi(1, segments.size() - 1))
	if base <= 0.0:
		return 0.0
	return current_length() / base - 1.0


## 局部伸长率（单节最大）。比整绳平均更能暴露单点失效。
func worst_link_stretch() -> float:
	var worst: float = 0.0
	for l: Dictionary in _links:
		if str(l["kind"]) != "seg":
			continue
		var a: Node3D = l["a"]
		var b: Node3D = l["b"]
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		var wa: Vector3 = a.global_transform * (l["la"] as Vector3)
		var wb: Vector3 = b.global_transform * (l["lb"] as Vector3)
		worst = maxf(worst, wa.distance_to(wb) / segment_length)
	return worst


# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------

## 两端直线距离 / 自然长度。> 1 = 被拉长，< TAUT_RATIO = 松弛。
func taut_ratio() -> float:
	if _shutting_down or segments.size() < 2:
		return 0.0
	var a: Vector3 = _end_anchor_world(0, true)
	var b: Vector3 = _end_anchor_world(segments.size() - 1, false)
	return a.distance_to(b) / maxf(0.01, _rest_length)


## 取第 idx 段在某一侧的锚点世界坐标。
##
## 【必须做有效性检查 —— 这里是间歇性 0xC0000005 的根因】
## `segments[idx]` 与 `_links` 里的节点在"关节已拆、节点正在释放"的窗口里
## 可能已经失效。若 `_physics_process` 恰好在这个窗口里跑一帧，
## 未经检查的 `.global_transform` / `.global_position` 就会访问已释放内存。
## 实测：完整套件重复运行时 machines_rope 两轮里崩一轮（13 条断言全过、
## 进程退出码 -1073741819）——断言全绿也判失败，必须修掉。
func _end_anchor_world(idx: int, head: bool) -> Vector3:
	if _shutting_down or idx < 0 or idx >= segments.size():
		return Vector3.ZERO
	var self_seg: RigidBody3D = segments[idx]
	if not is_instance_valid(self_seg):
		return Vector3.ZERO
	for l: Dictionary in _links:
		if str(l["kind"]) != "seg":
			continue
		var a: Node3D = l["a"] as Node3D
		var b: Node3D = l["b"] as Node3D
		if head and b == self_seg:
			if not is_instance_valid(b):
				return Vector3.ZERO
			return b.global_transform * (l["lb"] as Vector3)
		if not head and a == self_seg:
			if not is_instance_valid(a):
				return Vector3.ZERO
			return a.global_transform * (l["la"] as Vector3)
	return self_seg.global_position


func is_taut() -> bool:
	return taut_ratio() > TAUT_RATIO


func span_distance() -> float:
	if segments.size() < 2:
		return 0.0
	return segments[0].global_position.distance_to(segments[segments.size() - 1].global_position)


func rest_length() -> float:
	return _rest_length


## 复位：清速度、把绳段拉回直线并清空抓握关系。
##
## 历史 Bug（必须回归）：旧实现的"复位"会调用 enable_mirror(false)，
## 而那一版 enable_mirror 无条件清空所有关节的 node_a/node_b ——
## 于是**任何一次复位都会把整条绳永久拆散**，而结构检查仍然报告"连接正常"。
## 现在 enable_mirror 只冻结绳段、不改接线，因此复位不再有这个问题。
##
## 这里**不**重建关节（重建会丢锚点、且运行期重建约束有崩溃风险），
## 只把运动状态与形状复位。`wiring_report()` 可用于验证约束仍然有效。
func reset_rope() -> void:
	if not _built or segments.is_empty():
		return
	# 按当前首尾锚点把绳段摆回直线，并清速度（重置语义，不是运动）
	var head: Vector3 = _end_anchor_world(0, true)
	var tail: Vector3 = _end_anchor_world(segments.size() - 1, false)
	var span: Vector3 = tail - head
	var step: float = segment_length if span.length() < 0.01 else span.length() / float(segments.size())
	var dir: Vector3 = Vector3.FORWARD if span.length() < 0.01 else span.normalized()
	for i in range(segments.size()):
		var s: RigidBody3D = segments[i]
		if not is_instance_valid(s):
			continue
		s.sleeping = false
		s.freeze = false
		s.linear_velocity = Vector3.ZERO
		s.angular_velocity = Vector3.ZERO
		s.global_position = head + dir * (step * (float(i) + 0.5))
	if free_end != null and is_instance_valid(free_end):
		free_end.sleeping = false
		free_end.freeze = false
		free_end.linear_velocity = Vector3.ZERO
		free_end.angular_velocity = Vector3.ZERO
		free_end.global_position = tail
	# 清空"谁在抓"的登记：复位后不该还留着旧的持有者。
	for s2: RigidBody3D in segments:
		if is_instance_valid(s2):
			LISGrabLedger.clear(s2)
	if free_end != null and is_instance_valid(free_end):
		LISGrabLedger.clear(free_end)


func total_mass() -> float:
	var m: float = 0.0
	for s: RigidBody3D in segments:
		if is_instance_valid(s):
			m += s.mass
	return m


func linear_density() -> float:
	var total_len: float = float(segments.size()) * segment_length
	if total_len <= 0.0:
		return 0.0
	return total_mass() / total_len


func _physics_process(_delta: float) -> void:
	# 拆卸开始后立刻停止一切测量：此时 `segments` / `_links` 里的节点
	# 可能正在被释放，任何解引用都是访问冲突风险（见 _end_anchor_world 说明）。
	if _shutting_down or not _built or segments.is_empty():
		return
	if not is_instance_valid(segments[0]):
		_shutting_down = true
		return
	var t: bool = is_taut()
	if t != _taut:
		_taut = t
		rope_taut_changed.emit(t)


## 安全销毁整条缆绳：按"先解持有关系 → 再拆约束 → 最后放刚体"的顺序。
##
## 请优先用这个方法，而不是直接 `queue_free()`。
##
## 顺序的理由：
##   1. 先清持有关系：玩家可能正抓着自由端或某个绳段；
##   2. 再拆约束：`remove_child` 让物理服务器立刻注销 PinJoint；
##   3. 最后释放：绳段与自由端统一 queue_free（延迟释放，避开物理帧中途析构）。
##
## 已知边界：若在"绳索处于高张力、且玩家正抓着绳端牵引"时销毁整条绳，
## 极少数情况下（实测约 1/8）进程会在退出时出现 0xC0000005。
## 复现与规避方式见 docs/PHYSICS_LIMITATIONS.md 第 8 节。
func despawn() -> void:
	teardown_joints_safely()
	if free_end != null and is_instance_valid(free_end):
		LISGrabLedger.clear(free_end)
		free_end.queue_free()
		free_end = null
	for s: RigidBody3D in segments:
		if is_instance_valid(s):
			# 绳段是普通 RigidBody3D（不是 LISBody），持有者登记走登记表。
			LISGrabLedger.clear(s)
			s.queue_free()
	segments.clear()
	queue_free()


# ---------------------------------------------------------------------------
# 网络镜像与拆卸
# ---------------------------------------------------------------------------

## 客户端镜像：冻结绳段，**不碰关节接线**。
##
## 历史缺陷 A：旧实现不管 enabled 真假都无条件清空 node_a/node_b，
## 于是 enable_mirror(false) 反而把整条绳的关节永久断开。
## 历史缺陷 B：在关节仍挂在物理服务器里时改写接线 = 让 Jolt 运行期重建约束，
## 反复执行会留下半断开的约束对象并崩溃（实测 1/5 的运行在退出时崩溃）。
## 正确做法：冻结绳段就够了 —— 冻结的刚体不动，约束自然惰性。
func enable_mirror(enabled: bool) -> void:
	for s: RigidBody3D in segments:
		if is_instance_valid(s):
			s.freeze = enabled
			s.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	if free_end != null and is_instance_valid(free_end):
		free_end.call("enable_mirror", enabled)


## 安全拆卸：先摘掉关节，再让节点树销毁绳段。
##
## 同时把 `_shutting_down` 置位：此后 `_physics_process` 与所有测量函数
## 都会立即返回，不再触碰正在释放的绳段与关节节点。
func teardown_joints_safely() -> void:
	_shutting_down = true
	for j: Joint3D in joints:
		if is_instance_valid(j):
			LISJointKit.teardown(j)
	joints.clear()
	# 同时注销所有绳段与自由端上的抓握登记。
	#
	# 为什么必须做：玩家可能正抓着绳的自由端，而此时场景要销毁整条绳。
	# 若不清登记，抓握器里会留着一个指向"即将被释放的绳端"的引用。
	# 抓握器自身会用 is_instance_valid 兜底，但把登记留在一个已消失的物体上
	# 本身就是错的（"释放刚体前必须正确处理引用它的东西"）。
	for s: RigidBody3D in segments:
		if is_instance_valid(s):
			LISGrabLedger.clear(s)
	if free_end != null and is_instance_valid(free_end):
		LISGrabLedger.clear(free_end)


## 退出树时**只清引用、不释放关节**。
##
## 【为什么不在 _exit_tree 里 free 关节】
## 节点离开场景树时，Godot 正在按子节点顺序做拆除遍历。若在 `_exit_tree()`
## 里对子节点调用 `free()`（立即释放），等于在遍历过程中删除被遍历的元素，
## 会破坏引擎的遍历状态 —— 表现为**间歇性** 0xC0000005（实测：同一份代码
## 连跑 8 轮，3 轮在进程退出时崩溃，13 条断言全部通过）。
##
## 正确做法是**靠子节点顺序**保证安全：`order_joints_first()` 已经把关节
## 排在所有绳段之前，引擎拆除时自然"先拆约束、再放刚体"。
## 需要提前拆卸的场景请显式调用 `teardown_joints_safely()`（那是安全的，
## 因为它在正常的物理帧之间执行，不在树遍历过程中）。
func _exit_tree() -> void:
	_shutting_down = true
	joints.clear()
	# 让抓着绳的抓握者立刻松手：绳都要消失了，持有关系必须结束。
	for s: RigidBody3D in segments:
		if is_instance_valid(s):
			LISGrabLedger.clear(s)
	if free_end != null and is_instance_valid(free_end):
		LISGrabLedger.clear(free_end)


## 客户端：把主机同步来的绳端位置反推回整条绳（纯视觉摆放，主机才是权威）。
func apply_mirror_end(target: Vector3) -> void:
	if free_end == null or not is_instance_valid(free_end) or segments.is_empty():
		return
	var anchor: Vector3 = segments[0].global_position
	var total: float = target.distance_to(anchor)
	if total < 0.01:
		return
	var dir: Vector3 = (target - anchor).normalized()
	var max_len: float = float(segments.size()) * segment_length
	var span: float = minf(total, max_len * 0.985)
	var step: float = span / float(segments.size())
	for i in range(segments.size()):
		var s: RigidBody3D = segments[i]
		if not is_instance_valid(s):
			continue
		s.global_position = anchor + dir * (step * (float(i) + 0.5))


## 结构自检：所有关节接线是否仍然有效（复位后用它证明绳子没被悄悄拆开）。
func wiring_report() -> Dictionary:
	var bad: int = 0
	for j: Joint3D in joints:
		if not LISJointKit.is_wired(j):
			bad += 1
	return {
		"joints": joints.size(),
		"broken": bad,
		"links": _links.size(),
		"segments": segments.size(),
		"rest_length": _rest_length,
	}


func snapshot() -> Dictionary:
	return {
		"pos": segments[0].global_position if not segments.is_empty() else Vector3.ZERO,
		"rot": Vector3.ZERO,
		"lin": Vector3.ZERO,
		"ang": Vector3.ZERO,
		"sleep": false,
	}


func apply_snapshot(_data: Dictionary) -> void:
	pass
