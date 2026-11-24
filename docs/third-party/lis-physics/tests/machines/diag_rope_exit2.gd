extends "res://tests/harness/lis_test_case.gd"
## 诊断探针：隔离缆绳退出期崩溃的触发条件（第二轮）
##
## 第一轮（A~D：只建绳 / reset / mirror / teardown）6 轮全部正常。
## 本轮加入"玩家抓握绳端并牵引"这一类操作，逐项逼近真实用例。
## 只打印结果，不做断言（expected_checks = 0 → RAN）。

func _configure() -> void:
	suite_name = "diag_rope_exit2"
	expected_checks = 0


func _run() -> void:
	make_world_with_floor(20.0, 0.0, 0.9)
	await wait_physics(6)
	# E：建绳 + 锚定 + 代理抓住自由端牵引 240 帧 + 拆除 + 释放
	await _variant("E_avatar_pull", true, false, false)
	# F：E + 复位
	await _variant("F_pull_then_reset", true, true, false)
	# G：只建绳 + 释放（无锚定、无代理）
	await _variant("G_bare_build", false, false, true)
	print("DIAG2_VARIANTS_DONE")


func _variant(nm: String, with_pull: bool, with_reset: bool, bare: bool) -> void:
	var crate: LISBody = make_body(Vector3(-3.0, 0.41, 0.0), Vector3(0.8, 0.8, 0.8), 40.0,
		Color(0.7, 0.6, 0.45), {"display_name": "crate_%s" % nm})
	await wait_physics(30)
	var rope: LISRope = LISRope.new()
	rope.name = "Rope_%s" % nm
	add_child(rope)
	await get_tree().physics_frame
	rope.build(10, 0.34, crate.global_position + Vector3(0.45, 0.60, 0.0),
		Vector3.RIGHT, true, 0.0)
	await get_tree().physics_frame
	if not bare:
		rope.anchor_first_to(crate, crate.global_position + Vector3(0.45, 0.30, 0.0))
	await wait_physics(40)

	var ad: LISFirstPersonAdapter = null
	if with_pull:
		var end_pos: Vector3 = rope.free_end.global_position
		ad = make_avatar(end_pos + Vector3(0.0, 1.3, 1.6),
			(end_pos - (end_pos + Vector3(0.0, 1.3, 1.6))).normalized(), 1, "Rope")
		await wait_physics(6)
		ad.grab(rope.free_end)
		for i in range(240):
			var t: float = float(i) * 0.012
			var eye: Vector3 = end_pos + Vector3(1.6 + t, 1.3, 1.6 - t * 0.4)
			aim_avatar(ad, eye, rope.free_end.global_position)
			await get_tree().physics_frame
	if with_reset:
		rope.reset_rope()
		await wait_physics(30)
	if ad != null:
		ad.release_held(false)
		await wait_physics(6)
	print("DIAG2_VARIANT %s pull=%s reset=%s bare=%s held=%s" % [
		nm, str(with_pull), str(with_reset), str(bare),
		str(ad.is_holding()) if ad != null else "n/a"])
	rope.teardown_joints_safely()
	await wait_physics(4)
	rope.queue_free()
	crate.queue_free()
	await wait_physics(10)
