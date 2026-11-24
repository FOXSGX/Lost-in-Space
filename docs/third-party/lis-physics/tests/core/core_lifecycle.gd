extends "res://tests/harness/lis_test_case.gd"
## 核心层 · 安全创建、销毁、复位与场景反复进出
##
## 验证：刚体被销毁时不留悬空引用、场景反复进出不报 "previously freed"、
##       复位真能把物体搬回去、抓握中的物体被销毁时抓握器自动放手。


func _configure() -> void:
	suite_name = "core_lifecycle"
	expected_checks = 11


func _run() -> void:
	make_world_with_floor(16.0)
	await wait_physics(5)

	# --- 1) 安全销毁：持有者登记被清空 --------------------------------
	var b1: LISBody = make_body(Vector3(0.0, 0.5, 0.0), Vector3(0.5, 0.5, 0.5), 10.0)
	var ad: LISFirstPersonAdapter = make_avatar(Vector3(0.0, 1.62, 3.0), Vector3.FORWARD)
	await wait_physics(3)
	var ok: bool = ad.grab(b1)
	check("先抓住再销毁", ok and b1.holder_count() == 1, "holders=%d" % b1.holder_count())
	b1.despawn()
	await wait_physics(3)
	check("销毁后持有者不复存在", not is_instance_valid(b1) or b1.holder_count() == 0,
		"is_valid=%s" % str(is_instance_valid(b1)))
	check("抓握器不再引用已销毁物体", not ad.is_holding(), ad.grabber.describe())

	# --- 2) 抓握中物体被 queue_free（不经过 despawn）：抓握器要自己放手 ----
	var b2: LISBody = make_body(Vector3(0.0, 0.5, 0.0), Vector3(0.5, 0.5, 0.5), 10.0)
	await wait_physics(2)
	ad.grab(b2)
	await wait_physics(4)
	b2.queue_free()
	await wait_physics(4)
	check("queue_free 后抓握器自动松手", not ad.is_holding(),
		"held=%s" % ("null" if ad.grabber.held == null else "非空"))

	# --- 3) 复位：位姿与速度都被恢复 ----------------------------------
	var b3: LISBody = make_body(Vector3(-3.0, 0.5, 0.0), Vector3(0.5, 0.5, 0.5), 10.0)
	await wait_physics(20)
	var spawn: Transform3D = b3.global_transform
	b3.apply_central_impulse(Vector3(40.0, 20.0, 0.0))
	await wait_physics(30)
	var moved: float = spawn.origin.distance_to(b3.global_position)
	check_gt("先把它撞飞", moved, 0.3, " m")
	b3.reset_to(spawn)
	await wait_physics(2)
	check_lt("复位后位姿还原", spawn.origin.distance_to(b3.global_position), 0.02, " m")
	check_lt("复位后速度归零", b3.linear_velocity.length(), 0.05, " m/s")

	# --- 4) 场景反复进出（5 轮）--------------------------------------
	var rounds: int = 5
	var leaks: int = 0
	for i in range(rounds):
		var holder: Node3D = Node3D.new()
		holder.name = "RoundRoot%d" % i
		add_child(holder)
		var box: LISBody = LISBody.new()
		box.name = "RoundBox"
		box.body_size = Vector3(0.4, 0.4, 0.4)
		box.mass_kg = 5.0
		holder.add_child(box)
		box.global_position = Vector3(2.0, 0.6, 0.0)
		await wait_physics(6)
		if not is_instance_valid(box):
			leaks += 1
		holder.queue_free()
		await wait_physics(4)
		if is_instance_valid(holder) and not holder.is_queued_for_deletion():
			leaks += 1
	check("5 轮加入/退出无残留", leaks == 0, "异常轮次 %d" % leaks)

	# --- 5) 场景切换（整个测试节点被移出树）不产生访问错误 -------------
	# 这里通过"把一个包含物体的子树整体 queue_free"模拟场景退出。
	var scene_root: Node3D = Node3D.new()
	scene_root.name = "FakeScene"
	add_child(scene_root)
	for i in range(6):
		var c: LISBody = LISBody.new()
		c.name = "F%d" % i
		c.body_size = Vector3(0.3, 0.3, 0.3)
		c.mass_kg = 3.0
		scene_root.add_child(c)
		c.global_position = Vector3(-2.0 + float(i) * 0.4, 0.4, -3.0)
	await wait_physics(10)
	scene_root.queue_free()
	await wait_physics(6)
	check("整棵场景子树被释放后无异常引用", not is_instance_valid(scene_root),
		"scene_root 已释放")

	# --- 6) prune 能清掉失效持有者 ------------------------------------
	var b4: LISBody = make_body(Vector3(4.0, 0.5, 0.0), Vector3(0.5, 0.5, 0.5), 10.0)
	var temp: Node3D = Node3D.new()
	add_child(temp)
	await wait_physics(2)
	b4.add_holder(temp)
	check("临时持有者已登记", b4.holder_count() == 1, "holders=%d" % b4.holder_count())
	temp.free()
	var pruned: int = b4.prune_dead_holders()
	check("失效持有者被清理", pruned == 1 and b4.holder_count() == 0,
		"清理 %d 个，剩余 %d" % [pruned, b4.holder_count()])
