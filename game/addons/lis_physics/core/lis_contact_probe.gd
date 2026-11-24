class_name LISContactProbe
extends RefCounted
## LIS Physics SDK · 接触与穿透测量工具
##
## 只做"按真实碰撞形状与姿态测量"这一件事，不修任何东西：
##   * box_obb()       取碰撞体的真实世界变换与尺寸
##   * sat_depth()     两个有向包围盒（OBB）的最小穿透深度（15 轴分离轴）
##   * contacts_of()   读物理服务器的真实接触点 / 法线 / 冲量
##   * plane_gap()     点沿法线到平面的有符号距离
##   * shape_size()    任意 CollisionShape3D 的外形尺寸估算
##
## 为什么用 OBB 而不是 AABB：门板转开 7.5° 时它的 AABB 必然"扫"到旁边的箱子，
## 两个 AABB 的重叠量与真实穿透无关（旧报告里 0.060 m 的假穿透就是这么来的）。
##
## 来源：work/final-integration-001/project/scripts/physics/phys_measure.gd


## 取节点上第一个 BoxShape3D 碰撞体的真实世界变换与尺寸。
static func box_obb(node: CollisionObject3D) -> Dictionary:
	if node == null:
		return {}
	for child: Node in node.get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			if cs.shape is BoxShape3D:
				return {"xform": cs.global_transform, "size": (cs.shape as BoxShape3D).size}
	return {}


## 任意碰撞体的外形尺寸（米）。盒体精确，其它形状给保守外接尺寸。
static func shape_size(node: CollisionObject3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	for child: Node in node.get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			var sh: Shape3D = cs.shape
			if sh == null:
				continue
			if sh is BoxShape3D:
				return (sh as BoxShape3D).size
			if sh is SphereShape3D:
				return Vector3.ONE * (sh as SphereShape3D).radius * 2.0
			if sh is CylinderShape3D:
				var cy: CylinderShape3D = sh as CylinderShape3D
				return Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0)
			if sh is CapsuleShape3D:
				var ca: CapsuleShape3D = sh as CapsuleShape3D
				return Vector3(ca.radius * 2.0, ca.height, ca.radius * 2.0)
	return Vector3.ZERO


## 两个 OBB 的最小穿透深度（米）。0 = 分离或仅接触。
static func sat_depth(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	var ax: Array[Vector3] = [
		(a["xform"] as Transform3D).basis.x.normalized(),
		(a["xform"] as Transform3D).basis.y.normalized(),
		(a["xform"] as Transform3D).basis.z.normalized()]
	var bx: Array[Vector3] = [
		(b["xform"] as Transform3D).basis.x.normalized(),
		(b["xform"] as Transform3D).basis.y.normalized(),
		(b["xform"] as Transform3D).basis.z.normalized()]
	var ae: Vector3 = (a["size"] as Vector3) * 0.5
	var be: Vector3 = (b["size"] as Vector3) * 0.5
	var d: Vector3 = (b["xform"] as Transform3D).origin - (a["xform"] as Transform3D).origin
	var axes: Array[Vector3] = [ax[0], ax[1], ax[2], bx[0], bx[1], bx[2]]
	for i in range(3):
		for j in range(3):
			var c: Vector3 = ax[i].cross(bx[j])
			if c.length() > 0.0001:
				axes.append(c.normalized())
	var min_overlap: float = 1.0e9
	for L: Vector3 in axes:
		var ra: float = absf(ax[0].dot(L)) * ae.x + absf(ax[1].dot(L)) * ae.y + absf(ax[2].dot(L)) * ae.z
		var rb: float = absf(bx[0].dot(L)) * be.x + absf(bx[1].dot(L)) * be.y + absf(bx[2].dot(L)) * be.z
		var dist: float = absf(d.dot(L))
		var overlap: float = ra + rb - dist
		if overlap < 0.0:
			return 0.0
		if overlap < min_overlap:
			min_overlap = overlap
	return min_overlap


## 真实接触点（位置 / 法线 / 冲量 / 对方节点名）。
static func contacts_of(body: RigidBody3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if body == null or not is_instance_valid(body):
		return out
	var st: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(body.get_rid())
	if st == null:
		return out
	for i in range(st.get_contact_count()):
		var obj: Object = st.get_contact_collider_object(i)
		var n: Node = obj as Node
		out.append({
			"name": str(n.name) if n != null else "?",
			"position": st.get_contact_local_position(i),
			"normal": st.get_contact_local_normal(i),
			"impulse": st.get_contact_impulse(i),
		})
	return out


## 点相对平面的有符号距离（沿法线）。
static func plane_gap(point: Vector3, plane_point: Vector3, plane_normal: Vector3) -> float:
	return (point - plane_point).dot(plane_normal.normalized())


## 在物体当前位置与一份"目标位姿"之间，用形状查询检查是否插入静态世界。
## 返回最深穿透（米，0 = 安全）。用于"物体靠近镜头时不穿墙"的验收。
static func probe_penetration(node: CollisionObject3D, space: PhysicsDirectSpaceState3D, mask: int) -> float:
	if node == null or space == null:
		return 0.0
	var size: Vector3 = shape_size(node)
	if size == Vector3.ZERO:
		return 0.0
	var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = size * 0.98
	q.shape = bs
	q.transform = node.global_transform
	q.collision_mask = mask
	q.exclude = [node.get_rid()]
	var hits: Array[Dictionary] = space.intersect_shape(q, 8)
	var worst: float = 0.0
	for h: Dictionary in hits:
		var other: Object = h.get("collider")
		var rb: RigidBody3D = other as RigidBody3D
		if rb != null and rb.freeze:
			continue
		worst = maxf(worst, 0.01)
	return worst
