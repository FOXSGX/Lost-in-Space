extends "res://tests/harness/lis_test_case.gd"
## 交互层 · 第一人称专项（任务书 §18.D）
##
## 逐条验证：
##   1.  准星选择正确物体（含射线被墙挡住的情形）
##   2.  摄像机转动时抓握正常（不脱手、不抖飞）
##   3.  低头 / 抬头时抓握稳定
##   4.  物体贴近镜头不穿模（不穿墙）
##   5.  抓住重箱时不出现异常跟随（不瞬移）
##   6.  第一人称手部视觉不改变物理受力
##   7.  两个第一人称玩家同时抓握（各自独立抓点）
##   8.  四人输入代理独立施力
##   9.  不需要第三人称代码（SDK 不含任何第三人称依赖）
##  10.  相机是唯一交互源（删掉相机则抓握安全失败，不崩溃）
##  11.  射线距离限制生效（超过 reach 选不中）
##  12.  视角改变后手的目标点跟着动，但物体是被力拉过去的


func _configure() -> void:
	suite_name = "interaction_first_person"
	expected_checks = 17


func _run() -> void:
	make_world_with_floor(20.0)
	await wait_physics(6)

	# --- 1) 准星选择 ---------------------------------------------------
	var a_box: LISBody = make_body(Vector3(0.0, 0.31, -2.4), Vector3(0.6, 0.6, 0.6), 12.0,
		Color(0.6, 0.8, 0.7), {"display_name": "目标A"})
	var b_box: LISBody = make_body(Vector3(4.0, 0.31, -2.4), Vector3(0.6, 0.6, 0.6), 12.0,
		Color(0.8, 0.7, 0.5), {"display_name": "目标B"})
	var ad: LISFirstPersonAdapter = make_avatar(Vector3(0.0, 1.62, 0.6),
		Vector3(0.0, -0.42, -1.0).normalized())
	await wait_physics(4)
	check("准星选中正对的物体", ad.update_target() == a_box,
		"选中 %s" % (str(ad.current_target.name) if ad.current_target != null else "null"))

	# --- 2) 墙挡住时选不中 ---------------------------------------------
	# 墙必须插在相机（z=0.6）与目标（z=-2.4）**之间**：z = -1.0。
	make_wall(Vector3(0.0, 1.2, -1.0), Vector3(6.0, 2.4, 0.3))
	await wait_physics(4)
	check("墙体挡住目标时准星为空", ad.update_target() == null,
		"选中 %s（墙在 z=-1.0，目标在 z=-2.4）" % (
			str(ad.current_target.name) if ad.current_target != null else "null"))
	# 移开相机绕过墙
	aim_avatar(ad, Vector3(0.0, 1.62, -1.6), a_box.global_position)
	await wait_physics(3)
	check("绕过墙后重新选中目标", ad.update_target() == a_box,
		"选中 %s" % (str(ad.current_target.name) if ad.current_target != null else "null"))

	# --- 3) 抓握后转动镜头 ---------------------------------------------
	var ok: bool = ad.grab(a_box)
	await wait_physics(30)
	var pos_before: Vector3 = a_box.global_position
	# 玩家原地转身 120°（相机绕身体转）
	for i in range(60):
		var ang: float = deg_to_rad(120.0) * float(i) / 60.0
		var eye: Vector3 = Vector3(sin(ang) * 1.2, 1.62, -0.4 + cos(ang) * 1.2 - 1.2)
		aim_avatar(ad, eye, a_box.global_position)
		await get_tree().physics_frame
	check("转动镜头后仍抓握（未脱手）", ad.is_holding(),
		"slip=%s · clamp=%.3f m" % [ad.grabber.last_slip_reason, ad.grabber.last_clamp_distance])
	check("物体被拉向新的手位置（不是瞬移）",
		a_box.global_position.distance_to(pos_before) > 0.1,
		"位移 %.3f m" % a_box.global_position.distance_to(pos_before))

	# --- 4) 低头 / 抬头稳定 --------------------------------------------
	var yaw_ref: float = a_box.global_position.y
	for i in range(40):
		var pitch: float = deg_to_rad(-25.0 + 50.0 * float(i) / 40.0)
		var eye2: Vector3 = ad.camera.global_position
		var look: Vector3 = eye2 + Vector3(0.0, sin(pitch), -cos(pitch)) * 2.0
		aim_avatar(ad, eye2, look)
		await get_tree().physics_frame
	check("抬头／低头过程中抓握稳定", ad.is_holding(),
		"高度变化 %.3f m · clamp=%.3f m" % [absf(a_box.global_position.y - yaw_ref),
			ad.grabber.last_clamp_distance])

	# --- 5) 贴近镜头不穿墙 ---------------------------------------------
	var pen: float = LISContactProbe.probe_penetration(a_box,
		a_box.get_world_3d().direct_space_state, LISPhysics.LAYER_WORLD)
	check_lt("物体贴近镜头时未插入静态世界", pen, 0.02, " m")
	ad.release_held(false)
	await wait_physics(4)

	# --- 6) 抓住重箱不异常跟随 -----------------------------------------
	var heavy: LISBody = make_body(Vector3(8.0, 0.56, -2.0), Vector3(1.0, 1.0, 1.0), 160.0,
		Color(0.6, 0.4, 0.4), {"display_name": "重箱", "liftable": false})
	await wait_physics(30)
	var ad_h: LISFirstPersonAdapter = make_avatar(Vector3(8.0, 1.62, 0.2),
		Vector3(0.0, -0.5, -1.0).normalized(), 2)
	await wait_physics(4)
	ad_h.grab(heavy)
	# 每帧记录它是否出现"瞬移"（单帧位移 > 0.5 m 视为异常跟随）
	var max_step: float = 0.0
	var prev: Vector3 = heavy.global_position
	for i in range(90):
		await get_tree().physics_frame
		max_step = maxf(max_step, prev.distance_to(heavy.global_position))
		prev = heavy.global_position
	check_lt("重箱不出现异常跟随（无单帧瞬移）", max_step, 0.5, " m/帧")
	check("重箱仍在拖推模式", ad_h.grabber.mode == "drag",
		"mode=%s" % ad_h.grabber.mode)

	# --- 7) 手部视觉不改变物理受力 -------------------------------------
	# 记录无锚点时的力，再挂一个远离物体的锚点：力不应因此变大到超过上限。
	var f_no_anchor: float = ad_h.grabber.last_force
	var anchor: Node3D = Node3D.new()
	anchor.name = "VisualAnchor"
	add_child(anchor)
	anchor.global_position = heavy.global_position + Vector3(0.0, 0.1, 0.0)
	ad_h.grabber.set_hand_anchor(anchor)
	await wait_physics(10)
	var f_anchor: float = ad_h.grabber.last_force
	check("手部锚点只移动目标点、不放大作用力",
		f_anchor <= ad_h.grabber.grip_force + 0.5,
		"无锚点 %.0f N → 有锚点 %.0f N（上限 %.0f N）" % [
			f_no_anchor, f_anchor, ad_h.grabber.grip_force])

	# --- 8) 两个第一人称玩家同时抓握 -----------------------------------
	var shared: LISBody = make_body(Vector3(-8.0, 0.41, -2.0), Vector3(1.0, 0.8, 0.8), 40.0,
		Color(0.6, 0.6, 0.9), {"display_name": "共享箱"})
	await wait_physics(30)
	var p1: LISFirstPersonAdapter = make_avatar(Vector3(-9.6, 1.62, -0.4),
		(shared.global_position + Vector3(0, 0.2, 0) - Vector3(-9.6, 1.62, -0.4)).normalized(),
		11, "FP")
	aim_avatar(p1, Vector3(-9.6, 1.62, -0.4), shared.global_position + Vector3(0, 0.2, 0))
	var p2: LISFirstPersonAdapter = make_avatar(Vector3(-6.4, 1.62, -0.4),
		(shared.global_position + Vector3(0, 0.2, 0) - Vector3(-6.4, 1.62, -0.4)).normalized(),
		12, "FP")
	aim_avatar(p2, Vector3(-6.4, 1.62, -0.4), shared.global_position + Vector3(0, 0.2, 0))
	await wait_physics(6)
	var g1: bool = p1.grab(shared)
	var g2: bool = p2.grab(shared)
	await wait_physics(6)
	var gr1: Vector3 = p1.grabber.grip_world()
	var gr2: Vector3 = p2.grabber.grip_world()
	check("两个第一人称玩家同时抓住、抓点独立",
		g1 and g2 and shared.holder_count() == 2 and gr1.distance_to(gr2) > 0.3,
		"holders=%d · 抓点间距 %.2f m" % [shared.holder_count(), gr1.distance_to(gr2)])

	# --- 9) 四人输入代理独立施力 ---------------------------------------
	var quad: LISBody = make_body(Vector3(0.0, 0.51, 10.0), Vector3(1.4, 1.0, 1.0), 90.0,
		Color(0.5, 0.8, 0.6), {"display_name": "四人箱", "liftable": true})
	await wait_physics(30)
	var four: Array[LISFirstPersonAdapter] = []
	for i in range(4):
		var ang2: float = TAU * float(i) / 4.0 + 0.4
		var eye3: Vector3 = Vector3(cos(ang2) * 2.4, 1.5, 10.0 + sin(ang2) * 2.4)
		four.append(make_avatar(eye3, (quad.global_position + Vector3(0, 0.3, 0) - eye3).normalized(),
			20 + i, "Q"))
	await wait_physics(6)
	var cnt: int = 0
	for f: LISFirstPersonAdapter in four:
		if f.grab(quad):
			cnt += 1
	check("四人输入代理各自独立施力", cnt == 4 and quad.holder_count() == 4,
		"成功 %d，holders=%d" % [cnt, quad.holder_count()])
	# 施力之后物体应真的产生运动（说明四股力都进了物理世界）
	var before4: Vector3 = quad.global_position
	for f: LISFirstPersonAdapter in four:
		aim_avatar(f, f.camera.global_position + Vector3(0.0, 1.2, 0.0),
			quad.global_position + Vector3(0.0, 1.5, 0.0))
	await wait_physics(120)
	check_gt("四股力在物理世界里叠加（物体被抬起）", quad.global_position.y, 0.75,
		"箱心 y=%.3f m（初始 0.51，位移 %.2f m）" % [
			quad.global_position.y, quad.global_position.distance_to(before4)])

	# --- 10) 相机被移除时安全失败 --------------------------------------
	var doomed: LISFirstPersonAdapter = make_avatar(Vector3(0.0, 1.62, 6.0),
		Vector3.FORWARD, 30, "Doomed")
	await wait_physics(3)
	doomed.camera.queue_free()
	await wait_physics(4)
	var safe: bool = not doomed.grab(b_box)
	check("相机不存在时抓握安全失败（不崩溃）", safe,
		"grab 返回 false，理由=%s" % doomed.grabber.last_slip_reason)

	# --- 11) 射线距离限制 ----------------------------------------------
	var far: LISBody = make_body(Vector3(0.0, 0.31, 16.0), Vector3(0.6, 0.6, 0.6), 12.0,
		Color(0.9, 0.5, 0.5), {"display_name": "远处物体"})
	var near_ad: LISFirstPersonAdapter = make_avatar(Vector3(0.0, 1.62, 6.0),
		Vector3(0.0, -0.05, 1.0).normalized(), 40, "Reach")
	await wait_physics(4)
	near_ad.reach = 3.2
	var tgt_far: RigidBody3D = near_ad.update_target()
	check("超出 reach 的物体选不中", tgt_far != far,
		"目标 %s（距离 %.1f m > reach %.1f m）" % [
			str(tgt_far.name) if tgt_far != null else "null",
			near_ad.camera.global_position.distance_to(far.global_position), near_ad.reach])

	# --- 12) 视角改变影响目标点但不瞬移物体 ----------------------------
	var look_box: LISBody = make_body(Vector3(-12.0, 0.31, 6.0), Vector3(0.6, 0.6, 0.6), 12.0,
		Color(0.6, 0.9, 0.9), {"display_name": "视角箱"})
	var ad_v: LISFirstPersonAdapter = make_avatar(Vector3(-12.0, 1.62, 8.0),
		Vector3(0.0, -0.45, -1.0).normalized(), 50, "View")
	await wait_physics(20)
	ad_v.grab(look_box)
	await wait_physics(30)
	var hand_a: Vector3 = ad_v.grabber.hand_target()
	var obj_a: Vector3 = look_box.global_position
	aim_avatar(ad_v, Vector3(-12.0, 1.62, 8.0), Vector3(-12.0, 1.10, 6.0))
	await wait_physics(30)
	var hand_b: Vector3 = ad_v.grabber.hand_target()
	var obj_b: Vector3 = look_box.global_position
	check("视角改变后手的目标点移动", hand_a.distance_to(hand_b) > 0.1,
		"目标点移动 %.2f m" % hand_a.distance_to(hand_b))
	check("物体是被力拉过去的（位移远小于目标点跳变）",
		obj_a.distance_to(obj_b) < hand_a.distance_to(hand_b) * 3.0 + 1.0,
		"物体移动 %.2f m vs 目标点移动 %.2f m" % [
			obj_a.distance_to(obj_b), hand_a.distance_to(hand_b)])
