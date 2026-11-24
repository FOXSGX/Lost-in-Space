extends "res://tests/harness/lis_test_case.gd"
## 核心层 · 真实接触检测与穿透测量
##
## 验证：接触点读得到、接触数随堆叠增加、OBB 穿透测量能区分真假穿透、
##       受阻状态来自真实接触而非猜测、CCD 真的阻止高速穿透。


func _configure() -> void:
	suite_name = "core_contacts"
	expected_checks = 12


func _run() -> void:
	make_world_with_floor(20.0)
	await wait_physics(5)

	# --- 1) 接触点读数 -------------------------------------------------
	var box: LISBody = make_body(Vector3(0.0, 0.31, 0.0), Vector3(0.6, 0.6, 0.6), 12.0)
	await wait_physics(40)
	check_gt("静置物有真实接触", box.contact_count(), 0.0, " 个接触点")
	var contacts: Array[Dictionary] = LISContactProbe.contacts_of(box)
	var sample_impulse: float = 0.0
	if not contacts.is_empty():
		var imp: Variant = contacts[0].get("impulse", Vector3.ZERO)
		sample_impulse = (imp as Vector3).length() if imp is Vector3 else 0.0
	check_gt("能读到接触点位置与冲量", contacts.size(), 0.0,
		"%d 个接触，示例冲量 %.4f N·s" % [contacts.size(), sample_impulse])
	var has_floor: bool = false
	var names: PackedStringArray = PackedStringArray()
	for c: Dictionary in contacts:
		var nm: String = str(c.get("name", ""))
		names.append(nm)
		if nm == "TestFloor":
			has_floor = true
	check("接触对象是地面", has_floor, "接触对象名：%s" % ", ".join(names))

	# --- 2) 堆叠增加接触数 ---------------------------------------------
	var b2: LISBody = make_body(Vector3(0.0, 0.93, 0.0), Vector3(0.6, 0.6, 0.6), 12.0)
	var b3: LISBody = make_body(Vector3(0.0, 1.55, 0.0), Vector3(0.6, 0.6, 0.6), 12.0)
	await wait_physics(90)
	var mid_contacts: int = b2.contact_count()
	check_gt("堆叠中间层的接触数（上下两面都接触）", mid_contacts, 1.0, " 个")
	var stack_ok: bool = b3.global_position.y > 1.35
	check("三层堆叠没有塌陷", stack_ok, "顶层中心 y=%.3f m（初始 1.55）" % b3.global_position.y)

	# --- 3) OBB 穿透测量 -----------------------------------------------
	var obb_a: Dictionary = LISContactProbe.box_obb(box)
	var obb_b: Dictionary = LISContactProbe.box_obb(b2)
	check("取到碰撞体的真实 OBB", not obb_a.is_empty() and not obb_b.is_empty(),
		"尺寸 %s" % str(obb_a.get("size", Vector3.ZERO)))
	var touching: float = LISContactProbe.sat_depth(obb_a, obb_b)
	check_lt("上下相邻（仅接触）时 OBB 穿透 ≈ 0", touching, 0.02, " m")

	# 造一个**真的重叠**：把两个碰撞体在计算上叠在一起（只看测量，不动刚体）
	var fake_a: Dictionary = {"xform": Transform3D(Basis.IDENTITY, Vector3.ZERO),
		"size": Vector3(1, 1, 1)}
	var fake_b: Dictionary = {"xform": Transform3D(Basis.IDENTITY, Vector3(0.6, 0, 0)),
		"size": Vector3(1, 1, 1)}
	var overlap: float = LISContactProbe.sat_depth(fake_a, fake_b)
	check_range("重叠 0.4 m 的 OBB 测得穿透", overlap, 0.39, 0.41, " m")

	# --- 4) 受阻状态需要"有施力需求 + 被接触挡住" ----------------------
	# 静止在地面上的箱子有接触、速度为 0，但它不"受阻"——没有人在推它。
	# 受阻必须是"有人正施力、力被接触抵消、速度被压住"。
	make_wall(Vector3(6.0, 1.0, 0.0), Vector3(0.4, 2.0, 4.0))
	await wait_physics(3)
	var blocked_box: LISBody = make_body(Vector3(5.55, 0.31, 0.0), Vector3(0.6, 0.6, 0.6), 12.0,
		Color(0.7, 0.4, 0.4))
	var free_box: LISBody = make_body(Vector3(-6.0, 0.31, 0.0), Vector3(0.6, 0.6, 0.6), 12.0,
		Color(0.4, 0.7, 0.4))
	await wait_physics(50)
	check("静止箱体不被判为受阻（无施力需求）", not free_box.is_blocked(),
		"接触 %d · 速度 %.3f m/s" % [free_box.contact_count(),
			free_box.linear_velocity.length()])
	# 向墙推：力被墙抵消，速度接近 0 → 受阻
	for i in range(40):
		blocked_box.apply_central_force(Vector3(300.0, 0.0, 0.0))
		blocked_box.note_constrained_force(300.0, Vector3.RIGHT)
		await get_tree().physics_frame
	check("推墙的箱子被判为受阻", blocked_box.is_blocked(),
		"接触 %d · 速度 %.3f m/s" % [blocked_box.contact_count(),
			blocked_box.linear_velocity.length()])
	# 同样的施力上报但方向朝上没有阻挡（只有地面接触，法线竖直但不与"水平"相反）
	free_box.note_constrained_force(300.0, Vector3.FORWARD)
	check("施力方向没有接触阻挡时不受阻", not free_box.is_blocked(),
		"接触 %d · 法线均为竖直地面" % free_box.contact_count())

	# --- 5) CCD 阻止高速穿透 -------------------------------------------
	# 0.02 m 薄墙 + 90 m/s 的薄片：无 CCD 会穿过去。
	var thin_wall: StaticBody3D = make_wall(Vector3(0.0, 1.0, -10.0), Vector3(6.0, 2.0, 0.06))
	await wait_physics(3)
	var bullet: LISBody = make_body(Vector3(0.0, 1.0, -4.0), Vector3(0.3, 0.3, 0.06), 2.0,
		Color(0.9, 0.9, 0.3), {"friction": 0.3, "no_handles": true})
	bullet.gravity_scale = 0.0
	bullet.linear_velocity = Vector3(0.0, 0.0, -90.0)
	await wait_physics(60)
	var passed: bool = bullet.global_position.z < thin_wall.global_position.z - 0.2
	check("高速薄片没有穿过 0.06 m 薄墙（CCD）", not passed,
		"子弹最终 z=%.2f，墙 z=%.2f" % [bullet.global_position.z, thin_wall.global_position.z])

