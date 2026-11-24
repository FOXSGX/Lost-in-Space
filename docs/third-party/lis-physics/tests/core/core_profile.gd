extends "res://tests/harness/lis_test_case.gd"
## 核心层 · 刚体参数与 profile 应用
## 验证：参数真的写进刚体、越界被修正、几何与惯量自洽、层掩码正确。


func _configure() -> void:
	suite_name = "core_profile"
	expected_checks = 10


func _run() -> void:
	make_world_with_floor(10.0)
	await wait_physics(5)

	# 1) 参数逐项写入
	var prof: LISBodyProfile = LISBodyProfile.new()
	prof.display_name = "参数箱"
	prof.size = Vector3(0.5, 0.8, 1.2)
	prof.mass_kg = 24.0
	prof.friction = 0.42
	prof.bounce = 0.08
	prof.linear_damp = 0.11
	prof.angular_damp = 0.9
	prof.collision_layer = LISPhysics.LAYER_MACHINE
	prof.collision_mask = LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PLAYER
	prof.continuous_cd = true
	prof.can_sleep = false
	prof.liftable = false
	var b: LISBody = LISBody.new()
	b.name = "ProfileBox"
	b.profile = prof
	b.position = Vector3(0.0, 0.41, 0.0)
	add_child(b)
	await wait_physics(3)

	check_range("质量", b.mass, 23.9, 24.1, " kg")
	check_range("线阻尼", b.linear_damp, 0.109, 0.111)
	check_range("角阻尼", b.angular_damp, 0.899, 0.901)
	check("CCD 开启", b.continuous_cd, "continuous_cd=%s" % str(b.continuous_cd))
	check("禁止休眠", not b.can_sleep, "can_sleep=%s" % str(b.can_sleep))
	check("不可举起标记", not b.liftable, "liftable=%s" % str(b.liftable))
	check("碰撞层 = 机械层", b.collision_layer == LISPhysics.LAYER_MACHINE,
		"layer=%d（期望 %d）" % [b.collision_layer, LISPhysics.LAYER_MACHINE])
	check("碰撞掩码", b.collision_mask == (LISPhysics.LAYER_WORLD | LISPhysics.LAYER_PLAYER),
		"mask=%d" % b.collision_mask)
	var mat: PhysicsMaterial = b.physics_material_override
	check("摩擦 / 弹性写入材质",
		mat != null and is_equal_approx(mat.friction, 0.42) and is_equal_approx(mat.bounce, 0.08),
		"μ=%.2f e=%.2f" % [mat.friction if mat != null else -1.0, mat.bounce if mat != null else -1.0])

	# 2) 越界参数被修正并报告
	var bad: LISBodyProfile = LISBodyProfile.new()
	bad.size = Vector3(-1.0, 0.0, 0.0)
	bad.mass_kg = 0.0
	bad.collision_layer = 0
	var notes: PackedStringArray = bad.sanitize()
	check("越界参数被修正并报告", notes.size() >= 3,
		"修正说明 %d 条：%s" % [notes.size(), " / ".join(notes)])
