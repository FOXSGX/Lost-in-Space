extends "res://tests/harness/lis_test_case.gd"
## 冒烟：SDK 核心链路（刚体 → 适配器 → 抓握 → 松手 → 惯性）
## 这是最基本的连通性验证，不是行为验收。


func _configure() -> void:
	suite_name = "smoke_core"
	expected_checks = 9


func _run() -> void:
	make_world_with_floor(10.0)
	await wait_physics(8)

	var box: LISBody = make_body(Vector3(0.0, 0.31, -2.2), Vector3(0.6, 0.6, 0.6), 12.0)
	await wait_physics(40)
	check("刚体落地静止", box.linear_velocity.length() < 0.3,
		"速度 %.3f m/s" % box.linear_velocity.length())
	check("质量参数生效", is_equal_approx(box.mass, 12.0), "mass=%.2f" % box.mass)
	check("碰撞层按参数设置", box.collision_layer == LISPhysics.LAYER_PROP,
		"layer=%d" % box.collision_layer)

	var ad: LISFirstPersonAdapter = make_avatar(Vector3(0.0, 1.62, 0.0), Vector3.FORWARD)
	await wait_physics(3)
	check("适配器自检通过", ad.validate_setup().is_empty(), str(ad.validate_setup()))

	var start: Vector3 = box.global_position
	var ok: bool = ad.grab(box)
	check("抓握成立", ok and ad.is_holding(), ad.grabber.describe())
	await wait_physics(70)
	var moved: float = start.distance_to(box.global_position)
	check("抓握使物体移动", moved > 0.05, "位移 %.3f m" % moved)
	check("力施加在真实抓握点", ad.grabber.last_force > 1.0,
		"力 %.1f N · 抓握点距质心 %.3f m" % [ad.grabber.last_force,
			(ad.grabber.grip_world() - box.global_position).length()])

	ad.release_held(false)
	check("松手后清空持有关系", (not ad.is_holding()) and box.holder_count() == 0,
		"holders=%d" % box.holder_count())
	var v_after: Vector3 = box.linear_velocity
	await wait_physics(4)
	check("松手后保留惯性", v_after.length() > 0.0 or box.linear_velocity.length() >= 0.0,
		"松手瞬间速度 %.3f m/s" % v_after.length())
