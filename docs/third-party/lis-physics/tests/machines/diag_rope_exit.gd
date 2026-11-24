extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：定位缆绳退出期崩溃的触发条件
##
## 每个变体跑若干轮，只打印结果，不做断言（expected_checks = 0 → RAN）。
## 目的：找出"哪一步操作会让进程在退出时 0xC0000005"。

func _configure() -> void:
	suite_name = "diag_rope_exit"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(20.0, 0.0, 0.9)
	await wait_physics(6)
	# 变体 A：建绳 → 锚定 → 直接 queue_free（不显式拆关节）
	await _variant("A_no_teardown", false, false, false)
	# 变体 B：建绳 → 锚定 → 显式 teardown → queue_free
	await _variant("B_explicit_teardown", true, false, false)
	# 变体 C：建绳 → 锚定 → reset_rope → queue_free
	await _variant("C_with_reset", false, true, false)
	# 变体 D：建绳 → 锚定 → 镜像开关 → queue_free
	await _variant("D_with_mirror", false, false, true)
	print("DIAG_VARIANTS_DONE")


func _variant(nm: String, do_teardown: bool, do_reset: bool, do_mirror: bool) -> void:
	var crate: LISBody = make_body(Vector3(-3.0, 0.41, 0.0), Vector3(0.8, 0.8, 0.8), 40.0,
		Color(0.7, 0.6, 0.45), {"display_name": "crate_%s" % nm})
	var post: StaticBody3D = add_static_pad(Vector3(-4.4, 0.0, 0.0), Vector3(0.4, 3.0, 0.4), 0.9)
	await wait_physics(20)
	var rope: LISRope = LISRope.new()
	rope.name = "Rope_%s" % nm
	add_child(rope)
	await get_tree().physics_frame
	rope.build(10, 0.34, crate.global_position + Vector3(0.45, 0.20, 0.0),
		Vector3.RIGHT, true, 0.0)
	await get_tree().physics_frame
	rope.anchor_first_to(crate, crate.global_position + Vector3(0.45, 0.20, 0.0))
	rope.anchor_first_to(post, post.global_position + Vector3(0.0, 3.0, 0.0))
	await wait_physics(40)
	if do_mirror:
		rope.enable_mirror(true)
		await wait_physics(4)
		rope.enable_mirror(false)
		await wait_physics(4)
	if do_reset:
		rope.reset_rope()
		await wait_physics(20)
	if do_teardown:
		rope.teardown_joints_safely()
		await wait_physics(4)
	print("DIAG_VARIANT %s teardown=%s reset=%s mirror=%s joints=%d" % [
		nm, str(do_teardown), str(do_reset), str(do_mirror), rope.joints.size()])
	rope.queue_free()
	crate.queue_free()
	post.queue_free()
	await wait_physics(10)
