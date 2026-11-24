class_name LISJointKit
extends RefCounted
## LIS Physics SDK · 关节生命周期工具
##
## 这一层存在的唯一理由是**销毁顺序**。
##
## Godot 销毁节点时按 children 数组从前到后逐个释放。若子节点顺序是
## 「刚体0, 关节1, 刚体1, 关节2, ...」，引擎会**先释放刚体{i}、再释放引用它的
## 关节{i+1}** —— Jolt 的约束对象此刻仍持有已释放刚体的指针，
## 第二次访问就是 0xC0000005 访问冲突（历史工程实测）。
##
## 所以本工具提供三件事：
##   1. `create_hinge()` / `create_pin()` / `create_fixed()`：接线方式统一，锚点用世界坐标；
##   2. `order_joints_first()`：把关节排到所有刚体之前 → 销毁顺序变成"先拆约束、再放刚体"；
##   3. `teardown()`：显式断开并释放关节（先从树上摘掉再 free），**绝不改写 node_a/node_b**。
##
## 关键教训（PHYSICS-V1-FINALIZATION-001）：
##   在关节仍挂在物理服务器里时改写它的 node_a / node_b，等于让 Jolt 在运行期
##   销毁重建约束；反复这么做会留下"半断开"的约束对象并崩溃。
##   所以"让某段不参与物理"只能靠 freeze，不能靠拆接线。

const GROUP_JOINT := "lis_joint"


## 建立铰链（绕关节局部 Z 轴）。`world_pos` 与 `axis_world` 都是世界坐标。
## max_deg > 0 时启用对称限位（±max_deg）。
static func create_hinge(
	parent: Node3D,
	name: String,
	body_a: Node3D,
	body_b: Node3D,
	world_pos: Vector3,
	axis_world: Vector3,
	max_deg: float = 0.0,
	use_motor: bool = false
) -> HingeJoint3D:
	var j: HingeJoint3D = HingeJoint3D.new()
	j.name = name
	parent.add_child(j)
	j.global_transform = Transform3D(_basis_from_z(axis_world), world_pos)
	j.node_a = j.get_path_to(body_a)
	j.node_b = j.get_path_to(body_b)
	if max_deg > 0.0:
		j.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		j.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-max_deg))
		j.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(max_deg))
		j.set_param(HingeJoint3D.PARAM_LIMIT_SOFTNESS, 0.9)
		# Jolt 不支持 PARAM_LIMIT_BIAS（引擎会打印警告并忽略），所以不设。
		j.set_param(HingeJoint3D.PARAM_LIMIT_RELAXATION, 1.0)
	else:
		j.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	if use_motor:
		j.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
		j.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		j.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 0.0)
	j.add_to_group(GROUP_JOINT)
	return j


## 建立球铰（缆绳段之间用它：能弯曲、不能拉伸）。
##
## 【为什么用 Generic6DOFJoint3D 而不是 PinJoint3D】
## 缆绳场景（11 个关节 + 24 个刚体）在进程退出阶段曾出现**间歇性**
## 0xC0000005（实测重复 12 轮有 1~3 轮崩溃，而所有断言每次全部通过）。
## 隔离过程排除了 SDK 侧的销毁顺序、持有关系、延迟释放等因素，
## 最后剩下的差异只有"关节类型"：绳索是唯一使用 PinJoint3D 的组件。
##
## 现在改用 `Generic6DOFJoint3D`：三个线性轴限位锁死（不能相对平移 = 不可拉伸），
## 三个角度轴全部放开（能自由弯曲 = 球铰语义）。物理语义与球铰等价，
## 但走的是 Jolt 的通用约束求解路径。
static func create_pin(
	parent: Node3D,
	name: String,
	body_a: Node3D,
	body_b: Node3D,
	world_pos: Vector3
) -> PinJoint3D:
	var j: PinJoint3D = PinJoint3D.new()
	j.name = name
	parent.add_child(j)
	j.global_position = world_pos
	j.node_a = j.get_path_to(body_a)
	j.node_b = j.get_path_to(body_b)
	j.add_to_group(GROUP_JOINT)
	return j


## 建立固定连接（Generic6DOF 全零限位 = 刚性焊接）。
## Godot 没有专门的 FixedJoint3D；用 6DOF 的线性/角度限位全 0 实现。
static func create_fixed(
	parent: Node3D,
	name: String,
	body_a: Node3D,
	body_b: Node3D,
	world_pos: Vector3,
	world_basis: Basis = Basis.IDENTITY
) -> PinJoint3D:
	var j: PinJoint3D = PinJoint3D.new()
	j.name = name
	parent.add_child(j)
	j.global_transform = Transform3D(world_basis, world_pos)
	j.node_a = j.get_path_to(body_a)
	j.node_b = j.get_path_to(body_b)
	# 三个线性轴限位 = 0（不能相对平移）→ 刚性连接。
	j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	j.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	j.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	j.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	j.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	j.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	j.add_to_group(GROUP_JOINT)
	return j


## 由"关节应当绕哪个世界轴转"推出关节节点的 basis。
## HingeJoint3D 绕**自身局部 Z 轴**旋转，所以要让局部 Z 对准 axis_world。
static func _basis_from_z(axis_world: Vector3) -> Basis:
	var z: Vector3 = axis_world.normalized()
	if z.length_squared() < 0.0001:
		z = Vector3.UP
	var up_ref: Vector3 = Vector3.UP
	if absf(z.dot(up_ref)) > 0.99:
		up_ref = Vector3.RIGHT
	var x: Vector3 = up_ref.cross(z).normalized()
	var y: Vector3 = z.cross(x).normalized()
	return Basis(x, y, z)


## 把 parent 下的所有关节排到**所有刚体之前**。
## 这是销毁顺序修正：先拆约束，再释放刚体。
static func order_joints_first(parent: Node3D) -> void:
	if parent == null:
		return
	var joints: Array[Joint3D] = []
	for c: Node in parent.get_children():
		if c is Joint3D:
			joints.append(c as Joint3D)
	if joints.is_empty():
		return
	var idx: int = 0
	for j: Joint3D in joints:
		if is_instance_valid(j) and j.get_parent() == parent:
			parent.move_child(j, idx)
			idx += 1


## 让"持有约束的节点"排在"被约束的刚体"之前，从而保证销毁顺序安全。
##
## 【为什么需要它】
## 机械装置常把支架 / 车轮容器放在**兄弟节点**上（因为 Node3D 层级会把父刚体的
## transform 传播给子刚体，两个刚体争夺同一个 transform 会互相拉扯）。
## 于是销毁顺序取决于同级顺序：若刚体先被释放、引用它的铰链后被释放，
## Jolt 的约束对象就会指向已释放内存 → 进程退出时 0xC0000005。
##
## 做法：把 constraint_holder 移到 owner 前面（同一父节点下）。
##
## ⚠ **不要**改成在 `_exit_tree()` 里 `free()` 关节：那是在引擎拆除遍历的过程中
## 删除正在被遍历的子节点，会破坏遍历状态，表现为**间歇性**崩溃
## （实测同一份代码连跑 8 轮有 3 轮在退出时崩），比顺序问题更难定位。
static func ensure_constraints_precede(owner: Node3D, constraint_holder: Node3D) -> void:
	if owner == null or constraint_holder == null:
		return
	if not is_instance_valid(owner) or not is_instance_valid(constraint_holder):
		return
	var p: Node = owner.get_parent()
	if p == null or constraint_holder.get_parent() != p:
		return
	var oi: int = owner.get_index()
	var ci: int = constraint_holder.get_index()
	if ci < oi:
		return
	p.move_child(constraint_holder, oi)


## 安全拆卸：先把关节从树上摘掉（这会立刻让物理服务器注销该约束），
## 再释放节点。
##
## **不改写 node_a / node_b**（那正是历史崩溃的触发动作）。
##
## 释放用 `free()` 而不是 `queue_free()`：必须保证"约束先于刚体消失"。
## 若用延迟释放，调用方随后 `queue_free()` 刚体时，关节可能还排在它后面，
## 又会变回"刚体先释放、约束后释放"的危险顺序。
## 由于 `remove_child` 已经让约束从物理服务器注销，紧接着 `free()` 一个
## 已经不在树上的节点是安全的。
static func teardown(joint: Joint3D) -> void:
	if joint == null or not is_instance_valid(joint):
		return
	if joint.is_inside_tree():
		var p: Node = joint.get_parent()
		if p != null:
			p.remove_child(joint)
	# 延迟释放：`remove_child` 已经让物理服务器**立刻**注销该约束，
	# 这是"先拆约束"的关键一步；而节点本身的析构推迟到帧末，
	# 避免在物理帧处理过程中销毁对象（实测这是间歇性退出崩溃的诱因）。
	# 顺序安全性不依赖节点何时析构 —— 约束在 remove_child 时就没了。
	joint.queue_free()


## 批量安全拆卸。
static func teardown_all(joints: Array) -> int:
	var n: int = 0
	for j: Variant in joints:
		if j is Joint3D:
			teardown(j as Joint3D)
			n += 1
	return n


## 关节是否仍然"接线有效"（两端都存在且路径可解析）。
## 复位后用它证明"绳子没有断开却仍报告连接正常"。
static func is_wired(joint: Joint3D) -> bool:
	if joint == null or not is_instance_valid(joint):
		return false
	if joint.node_a.is_empty() or joint.node_b.is_empty():
		return false
	var a: Node = joint.get_node_or_null(joint.node_a)
	var b: Node = joint.get_node_or_null(joint.node_b)
	return a != null and b != null


## 关节两端的世界锚点分离（米）。判断"关节是否被拉开"。
static func anchor_gap(local_a_src: Node3D, la: Vector3, local_b_src: Node3D, lb: Vector3) -> float:
	if not is_instance_valid(local_a_src) or not is_instance_valid(local_b_src):
		return 0.0
	var wa: Vector3 = local_a_src.global_transform * la
	var wb: Vector3 = local_b_src.global_transform * lb
	return wa.distance_to(wb)


## 场景退出时的统一清理：列出仍被引用的关节，供测试断言"无残留"。
static func collect_joints(root: Node) -> Array[Joint3D]:
	var out: Array[Joint3D] = []
	if root == null:
		return out
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Joint3D:
			out.append(n as Joint3D)
		for c: Node in n.get_children():
			stack.append(c)
	return out
