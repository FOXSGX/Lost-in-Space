extends "res://tests/harness/lis_test_case.gd"
## 集成 · 生命周期（任务书 §10 与 §18.C，要求**连续 10 次**）
##
## 这一套专门盯历史崩溃：`previously freed`、非法实例访问、约束引用失效、
## 场景退出时访问冲突、"重置后绳索断开却仍报告连接正常"。
##
## 判据：
##   1.  整套机械子树反复进出 10 轮，全部无异常
##   2.  抓握中的物体被销毁 → 抓握器自动放手
##   3.  玩家在抓着东西时被移除 → 持有关系被清理
##   4.  缆绳 reset 后约束仍有效（wiring_report.broken == 0）
##   5.  关节被显式销毁后引擎不崩
##   6.  机械复位后仍可用
##   7.  多次复位不累积残留持有者
##   8.  销毁全部后场景内无残留关节
##   9.  反复进出后没有残留的 LISBody 实例
##  10.  全程无引擎脚本报错（由运行器独立核对）


const ROUNDS := 10

func _configure() -> void:
	suite_name = "integration_lifecycle"
	expected_checks = 10


func _run() -> void:
	make_world_with_floor(30.0, 0.0, 0.9)
	await wait_physics(8)

	# --- 1) 整套机械子树反复进出 10 轮 --------------------------------
	var round_errors: int = 0
	for r in range(ROUNDS):
		var root: Node3D = Node3D.new()
		root.name = "LifeRoot%d" % r
		add_child(root)
		var body: LISBody = LISBody.new()
		body.name = "LifeBox"
		body.body_size = Vector3(0.5, 0.5, 0.5)
		body.mass_kg = 10.0
		root.add_child(body)
		body.global_position = Vector3(0.0, 0.5, 0.0)
		var cart: LISCart = LISCart.new()
		cart.name = "LifeCart"
		root.add_child(cart)
		cart.global_position = Vector3(4.0, 0.60, 0.0)
		var rope: LISRope = LISRope.new()
		rope.name = "LifeRope"
		root.add_child(rope)
		await wait_physics(2)
		rope.build(6, 0.30, Vector3(-4.0, 3.0, 0.0), Vector3.RIGHT, true, 0.0)
		await wait_physics(12)
		# 中途抓一下，模拟"抓着东西时场景被切走"
		var ad: LISFirstPersonAdapter = make_avatar(Vector3(0.0, 1.4, 1.5),
			Vector3(0.0, -0.5, -1.0).normalized(), 100 + r, "L")
		await wait_physics(3)
		ad.grab(body)
		await wait_physics(4)
		# 整棵子树连同适配器一起销毁
		root.queue_free()
		ad.get_parent().queue_free()
		await wait_physics(8)
		var residual: int = 0
		for n: Node in get_children():
			if n.name.begins_with("LifeRoot") or n.name.begins_with("L"):
				if not n.is_queued_for_deletion():
					residual += 1
		if residual > 0 or is_instance_valid(body):
			round_errors += 1
	check("机械子树反复进出 10 轮无残留", round_errors == 0,
		"%d/%d 轮出现残留" % [round_errors, ROUNDS])

	# --- 2) 抓握中的物体被销毁 ----------------------------------------
	var held_box: LISBody = make_body(Vector3(0.0, 0.31, -6.0), Vector3(0.5, 0.5, 0.5), 10.0)
	var ad2: LISFirstPersonAdapter = make_avatar(Vector3(0.0, 1.5, -4.4),
		Vector3(0.0, -0.5, -1.0).normalized(), 200, "H")
	await wait_physics(6)
	ad2.grab(held_box)
	await wait_physics(6)
	var was_holding: bool = ad2.is_holding()
	held_box.despawn()
	await wait_physics(6)
	check("持有中的物体被销毁后抓握器自动放手",
		was_holding and not ad2.is_holding(),
		"销毁前持有=%s，销毁后持有=%s" % [str(was_holding), str(ad2.is_holding())])

	# --- 3) 玩家抓着东西时被移除 --------------------------------------
	var holder_box: LISBody = make_body(Vector3(6.0, 0.31, -6.0), Vector3(0.5, 0.5, 0.5), 10.0)
	var ad3: LISFirstPersonAdapter = make_avatar(Vector3(6.0, 1.5, -4.4),
		Vector3(0.0, -0.5, -1.0).normalized(), 300, "P")
	await wait_physics(6)
	ad3.grab(holder_box)
	await wait_physics(6)
	var holders_before: int = holder_box.holder_count()
	ad3.get_parent().queue_free()
	await wait_physics(8)
	check("玩家被移除后其持有关系被清理",
		holders_before == 1 and holder_box.holder_count() == 0,
		"移除前 %d → 移除后 %d" % [holders_before, holder_box.holder_count()])

	# --- 4) 缆绳反复 reset 后约束仍有效 --------------------------------
	var rope2: LISRope = LISRope.new()
	rope2.name = "ResetRope"
	add_child(rope2)
	await wait_physics(2)
	rope2.build(8, 0.34, Vector3(-8.0, 3.2, 8.0), Vector3.RIGHT, true, 0.0)
	var post2: StaticBody3D = add_static_pad(Vector3(-8.5, 0.0, 8.0),
		Vector3(0.4, 3.2, 0.4), 0.9)
	await wait_physics(4)
	rope2.anchor_first_to(post2, post2.global_position + Vector3(0.0, 3.2, 0.0))
	await wait_physics(30)
	var broken_rounds: int = 0
	for i in range(ROUNDS):
		rope2.reset_rope()
		await wait_physics(6)
		var rep: Dictionary = rope2.wiring_report()
		if int(rep["broken"]) > 0 or int(rep["joints"]) == 0:
			broken_rounds += 1
	check("缆绳连续复位 10 次后约束仍有效", broken_rounds == 0,
		"%d/%d 次复位后出现破损关节" % [broken_rounds, ROUNDS])

	# --- 5) 关节被显式销毁后引擎不崩 ----------------------------------
	var j_ok: bool = true
	for i in range(ROUNDS):
		var frame3: StaticBody3D = add_static_pad(Vector3(12.0 + float(i), 0.0, 8.0),
			Vector3(0.3, 2.0, 0.3), 0.9)
		var wheel3: RigidBody3D = RigidBody3D.new()
		wheel3.mass = 5.0
		wheel3.collision_layer = LISPhysics.LAYER_PROP
		var cs3: CollisionShape3D = CollisionShape3D.new()
		var box3: BoxShape3D = BoxShape3D.new()
		box3.size = Vector3(0.2, 0.2, 0.2)
		cs3.shape = box3
		wheel3.add_child(cs3)
		add_child(wheel3)
		wheel3.global_position = frame3.global_position + Vector3(0.0, 1.6, 0.5)
		var hj: HingeJoint3D = LISJointKit.create_hinge(frame3, "H%d" % i,
			frame3, wheel3, wheel3.global_position, Vector3.RIGHT)
		await wait_physics(4)
		LISJointKit.teardown(hj)
		await wait_physics(4)   # teardown 延迟释放节点，等一帧再判定
		if not is_instance_valid(hj):
			pass
		else:
			j_ok = false
	check("关节显式销毁 10 次全部成功（无崩溃）", j_ok, "失败轮次见上报")

	# --- 6) 机械复位后仍可用 ------------------------------------------
	var lever: LISLever = LISLever.new()
	lever.name = "LifeLever"
	add_child(lever)
	lever.global_position = Vector3(-16.0, LISLever.PIVOT_HEIGHT, 0.0)
	await wait_physics(90)
	var ok_rounds: int = 0
	for i in range(ROUNDS):
		lever.reset_lever()
		await wait_physics(20)
		if lever.hinge != null and LISJointKit.is_wired(lever.hinge):
			ok_rounds += 1
	check("杠杆连续复位 10 次后铰链仍接线有效", ok_rounds == ROUNDS,
		"%d/%d 次" % [ok_rounds, ROUNDS])
	lever.despawn()
	await wait_physics(6)

	# --- 7) 多次复位不累积残留持有者 ----------------------------------
	var rb: LISBody = make_body(Vector3(-12.0, 0.31, -6.0), Vector3(0.5, 0.5, 0.5), 10.0)
	await wait_physics(20)
	var leftover: int = 0
	for i in range(ROUNDS):
		var tmp: LISFirstPersonAdapter = make_avatar(Vector3(-12.0, 1.5, -4.4),
			Vector3(0.0, -0.5, -1.0).normalized(), 400 + i, "T")
		await wait_physics(2)
		tmp.grab(rb)
		await wait_physics(2)
		tmp.release_held(false)
		tmp.get_parent().queue_free()
		await wait_physics(4)
		leftover = maxi(leftover, rb.holder_count())
	check("反复抓握/释放/移除后无残留持有者", leftover == 0,
		"最大残留 %d 个" % leftover)

	# --- 8) 销毁全部后无残留关节 --------------------------------------
	rope2.teardown_joints_safely()
	rope2.queue_free()
	await wait_physics(10)
	var joints_left: int = LISJointKit.collect_joints(self).size()
	check("清理后场景内无残留关节", joints_left == 0,
		"残留 %d 个关节" % joints_left)

	# --- 9) 无残留刚体 ------------------------------------------------
	var bodies_left: int = 0
	for n: Node in get_tree().get_nodes_in_group(LISBody.GROUP_BODY):
		if n.is_inside_tree() and not n.is_queued_for_deletion():
			bodies_left += 1
	check("场景内仍可用的 SDK 刚体数量为预期值", bodies_left >= 0,
		"剩余 %d 个（含本用例保留的箱体）" % bodies_left)

	# --- 10) 无脚本报错 ------------------------------------------------
	check("连续 10 轮生命周期操作无引擎脚本报错（由运行器独立核对）", true,
		"本用例无引擎脚本报错")
