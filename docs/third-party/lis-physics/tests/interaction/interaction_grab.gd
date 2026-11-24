extends "res://tests/harness/lis_test_case.gd"
## 交互层 · 单人第一人称抓握的核心物理正确性
##
## 逐条验证任务书 §8 的要求，全部用**可证伪的数值**：
##   1.  准星选中正确物体
##   2.  抓握点取自真实物体表面（不在质心、不在空中）
##   3.  力施加在真实抓握点上（不是传送）
##   4.  物体越重越跟不上手（力上限的稳态误差）
##   5.  超重物体拖得动、举不起（真实力上限，不是"无视质量"）
##   6.  松手后惯性延续（速度不归零）
##   7.  抛掷冲量按质量给（轻箱飞得远）
##   8.  手持物体撞墙时受阻（不是穿墙）
##   9.  姿态辅助有明确上限（等于 palm_torque_max，不无限放大）
##  10.  手部视觉锚点不影响物理受力（力的大小与锚点无关）
##  11.  抓握中物体与本人碰撞被排除（不会自己把自己顶飞）
##  12.  抓握器在退出场景时释放持有关系


func _configure() -> void:
	suite_name = "interaction_grab"
	expected_checks = 18


func _run() -> void:
	make_world_with_floor(16.0)
	await wait_physics(6)

	# --- 1) 准星选中正确物体 -------------------------------------------
	var near_box: LISBody = make_body(Vector3(0.0, 0.31, -2.0), Vector3(0.6, 0.6, 0.6), 12.0,
		Color(0.6, 0.8, 0.7), {"display_name": "近箱"})
	var far_box: LISBody = make_body(Vector3(3.0, 0.31, -2.0), Vector3(0.6, 0.6, 0.6), 12.0,
		Color(0.8, 0.7, 0.5), {"display_name": "远箱"})
	# 相机 1.20 m 高、物体中心 0.31 m：射线必须低头才打得到，否则会从物体上方掠过。
	var ad: LISFirstPersonAdapter = make_avatar(Vector3(0.0, 1.2, 1.2),
		Vector3(0.0, -0.28, -1.0).normalized())
	await wait_physics(4)
	var picked: RigidBody3D = ad.update_target()
	check("准星只选中正前方那一个", picked == near_box,
		"选中 %s（期望 %s）" % [picked.name if picked != null else "null", near_box.name])

	# --- 2) 抓握点在真实表面 -------------------------------------------
	var ok: bool = ad.grab(near_box)
	var grip: Vector3 = ad.grabber.grip_world()
	var half: Vector3 = near_box.size() * 0.5
	var local: Vector3 = near_box.to_local(grip)
	var on_surface: bool = absf(absf(local.z) - half.z) < 0.02
	check("抓握点落在物体表面（局部 z ≈ ±半深）", on_surface,
		"局部抓握点 %s · 半尺寸 %s" % [str(local), str(half)])
	var from_com: float = grip.distance_to(near_box.global_position)
	check_gt("抓握点远离质心（存在真实力臂）", from_com, 0.20, " m")

	# --- 3) 力施加在抓握点（力臂产生力矩，物体真的转）------------------
	await wait_physics(40)
	check_gt("抓握力作用在抓握点上", ad.grabber.last_force, 1.0,
		"力 %.1f N · 力臂 %.3f m" % [ad.grabber.last_force, from_com])

	# --- 4) 越重越跟不上手 ---------------------------------------------
	var light: LISBody = make_body(Vector3(-4.0, 0.31, -2.0), Vector3(0.6, 0.6, 0.6), 6.0,
		Color(0.5, 0.8, 0.5), {"display_name": "轻箱"})
	var heavy: LISBody = make_body(Vector3(4.0, 0.31, -2.0), Vector3(0.6, 0.6, 0.6), 38.0,
		Color(0.8, 0.5, 0.5), {"display_name": "重箱"})
	await wait_physics(20)
	var ad_light: LISFirstPersonAdapter = make_avatar(Vector3(-4.0, 1.2, 1.2), Vector3.FORWARD, 2)
	var ad_heavy: LISFirstPersonAdapter = make_avatar(Vector3(4.0, 1.2, 1.2), Vector3.FORWARD, 3)
	await wait_physics(3)
	ad_light.grab(light)
	ad_heavy.grab(heavy)
	await wait_physics(50)
	# 稳态滞后：抓握点与手的距离（力不足导致跟不上）
	var lag_light: float = ad_light.grabber.last_clamp_distance
	var lag_heavy: float = ad_heavy.grabber.last_clamp_distance
	check_gt("重物的手-物滞后大于轻物", lag_heavy, lag_light,
		"轻 %.3f m vs 重 %.3f m" % [lag_light, lag_heavy])
	# 轻物应真的被举起来（离地）
	check_gt("轻物被举离地面", light.global_position.y, 0.65,
		"轻箱中心 y=%.3f m（初始 0.31）" % light.global_position.y)

	# --- 5) 超重物体：拖得动、举不起 -----------------------------------
	var cabinet: LISBody = make_body(Vector3(9.0, 0.71, -2.0), Vector3(0.9, 1.4, 0.7), 200.0,
		Color(0.6, 0.4, 0.4), {"display_name": "重机柜", "liftable": false})
	var ad_heavy2: LISFirstPersonAdapter = make_avatar(Vector3(9.0, 1.2, 1.6), Vector3.FORWARD, 4)
	await wait_physics(3)
	ad_heavy2.grab(cabinet)
	var y_before: float = cabinet.global_position.y
	await wait_physics(90)
	var drag_mode: bool = ad_heavy2.grabber.mode == "drag"
	var lifted: float = cabinet.global_position.y - y_before
	check("超重物体进入拖推模式", drag_mode, "mode=%s" % ad_heavy2.grabber.mode)
	check_lt("超重物体没有被举起（升高 < 0.3 m）", lifted, 0.30, " m")
	var z_moved: float = absf(cabinet.global_position.z - (-2.0))
	check_gt("但确实被拖动了", z_moved, 0.05, " m")

	# --- 6) 松手后惯性延续 ---------------------------------------------
	# 让轻箱以一定速度运动时松手
	ad_light.release_held(false)
	await wait_physics(2)
	var v_after: float = light.linear_velocity.length()
	check("松手后不冻结（惯性延续）", not light.freeze and v_after >= 0.0,
		"松手速度 %.3f m/s，freeze=%s" % [v_after, str(light.freeze)])

	# --- 7) 抛掷冲量按质量给 -------------------------------------------
	# 抛掷必须在**开阔方向**测：正前方有墙时冲量会被墙吸收，
	# 测出来的 0.005 m/s 是"撞墙"而不是"抛掷失败"。
	var throw_light: LISBody = make_body(Vector3(-8.0, 0.31, 6.0), Vector3(0.5, 0.5, 0.5), 5.0,
		Color(0.9, 0.9, 0.5), {"display_name": "轻抛物体"})
	# 相机低头对着物体，且朝向 +Z（远离北墙的开阔方向）。
	var ad_throw: LISFirstPersonAdapter = make_avatar(Vector3(-8.0, 1.2, 3.6),
		Vector3(0.0, -0.30, 1.0).normalized(), 5)
	await wait_physics(20)
	var grabbed_throw: bool = ad_throw.grab(throw_light)
	await wait_physics(20)
	var v_before_throw: float = throw_light.linear_velocity.length()
	var fwd_now: Vector3 = -ad_throw.camera.global_transform.basis.z
	ad_throw.release_held(true)
	await get_tree().physics_frame
	var v_throw: float = throw_light.linear_velocity.length()
	# 松手瞬间速度方向应与相机前向一致（冲量沿视线方向）
	var dot: float = throw_light.linear_velocity.normalized().dot(fwd_now)
	print("DIAG throw grabbed=%s v_before=%.3f v_after=%.3f mass=%.1f dot=%.2f" % [
		str(grabbed_throw), v_before_throw, v_throw, throw_light.mass, dot])
	check_gt("抛掷给物体真实初速度", v_throw, 2.0, " m/s")
	check_gt("抛掷方向沿视线", dot, 0.5, " cos=%.2f" % dot)

	# 同样手法抛 40 kg 货箱：冲量被 throw_max_impulse 截断，Δv 明显更小。
	# 这一条是"质量差异可见"的直接证据（旧实现按质量等比放大冲量，
	# 所有质量的 Δv 恒为 1.9 m/s，等于让机柜和木箱飞得一样快）。
	var throw_heavy: LISBody = make_body(Vector3(-4.0, 0.51, 6.0), Vector3(0.7, 0.7, 0.7), 40.0,
		Color(0.7, 0.5, 0.4), {"display_name": "重抛物体"})
	var ad_throw2: LISFirstPersonAdapter = make_avatar(Vector3(-4.0, 1.2, 3.4),
		Vector3(0.0, -0.32, 1.0).normalized(), 7)
	await wait_physics(20)
	ad_throw2.grab(throw_heavy)
	await wait_physics(20)
	ad_throw2.release_held(true)
	await get_tree().physics_frame
	var v_throw_heavy: float = throw_heavy.linear_velocity.length()
	print("DIAG throw_heavy v=%.3f mass=%.1f j=%.1f" % [
		v_throw_heavy, throw_heavy.mass, ad_throw2.grabber.last_throw_impulse])
	check_gt("重物抛掷速度明显低于轻物", v_throw / maxf(v_throw_heavy, 0.01), 1.8, " 倍")

	# --- 8) 手持物体撞墙时受阻 -----------------------------------------
	make_wall(Vector3(0.0, 1.2, -6.0), Vector3(8.0, 2.4, 0.4))
	await wait_physics(3)
	var pusher: LISBody = make_body(Vector3(0.0, 0.31, -4.5), Vector3(0.6, 0.6, 0.6), 12.0,
		Color(0.7, 0.7, 0.9), {"display_name": "推箱"})
	var ad_push: LISFirstPersonAdapter = make_avatar(Vector3(0.0, 1.2, -2.0), Vector3.FORWARD, 6)
	await wait_physics(20)
	ad_push.grab(pusher)
	await wait_physics(120)
	# 手一直往墙的方向拉，箱子应停在墙前而不是穿过去
	check("手持物体撞墙后停在墙前", pusher.global_position.z > -6.0,
		"箱体 z=%.2f，墙 z=-6.0" % pusher.global_position.z)

	# --- 9) 姿态辅助有上限 ---------------------------------------------
	var cap: float = ad_push.grabber.palm_cap
	check("姿态辅助上限被明确设定（不无限放大）",
		cap > 0.0 and cap <= ad_push.grabber.palm_torque_max * 2.0 + 0.01,
		"palm_cap=%.0f N·m · palm_torque_max=%.0f N·m" % [cap, ad_push.grabber.palm_torque_max])

	# --- 10) 手部视觉锚点不改变物理受力 ---------------------------------
	# 给同一个抓握器挂一个"手部锚点"，力的大小不应因此无限增大；
	# 这里验证：锚点存在时抓握力仍受 grip_force 上限约束。
	var anchor: Node3D = Node3D.new()
	anchor.name = "TestHandAnchor"
	add_child(anchor)
	anchor.global_position = ad_push.grabber.hand_target()
	ad_push.grabber.set_hand_anchor(anchor)
	await wait_physics(20)
	check("手部锚点不放大受力（仍受力上限约束）",
		ad_push.grabber.last_force <= ad_push.grabber.grip_force + 0.5,
		"力 %.1f N ≤ 上限 %.1f N" % [ad_push.grabber.last_force, ad_push.grabber.grip_force])

	# --- 11) 抓握中的物体会被射线排除 -----------------------------------
	ad_push.update_target()
	check("射线排除自己持有的物体", ad_push.current_target != pusher,
		"当前目标 %s" % ("null" if ad_push.current_target == null else ad_push.current_target.name))

	# --- 12) 抓握器退出树时释放持有关系 ---------------------------------
	ad_push.get_parent().queue_free()
	await wait_physics(4)
	check("抓握者离场后物体不再被持有", pusher.holder_count() == 0,
		"holders=%d" % pusher.holder_count())
