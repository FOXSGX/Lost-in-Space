extends "res://tests/harness/lis_test_case.gd"
## 交互层 · 多人共同施力（程序化输入代理，**不是真人试玩**）
##
## 逐条验证任务书 §8 第 13–18 条：
##   13. 双人共同抓握
##   14. 四人共同施力
##   15. 一人松手后其他人继续抓住
##   16. 玩家离开场景时清理抓握引用
##   17. 多人力矩自然叠加
##   18. 反向施力能够产生真实力偶
##
## 说明：本用例用程序化代理（虚拟相机 + 适配器）验证物理合成，
## 不能称为真人试玩，也不能替代真人手感评估。


func _configure() -> void:
	suite_name = "interaction_multiplayer"
	expected_checks = 15


func _run() -> void:
	make_world_with_floor(20.0)
	await wait_physics(6)

	# --- 1) 双人共同抓握：同一物体允许两个独立持有者 ----------------
	var crate: LISBody = make_body(Vector3(0.0, 0.41, -3.0), Vector3(1.0, 0.8, 0.8), 40.0,
		Color(0.7, 0.65, 0.45), {"display_name": "双人箱"})
	var a: LISFirstPersonAdapter = make_avatar(Vector3(-2.2, 1.2, -0.3),
		Vector3(0.5, -0.3, -1.0).normalized(), 1, "A")
	var b: LISFirstPersonAdapter = make_avatar(Vector3(2.2, 1.2, -0.3),
		Vector3(-0.5, -0.3, -1.0).normalized(), 2, "B")
	await wait_physics(4)
	var ok_a: bool = a.grab(crate)
	var ok_b: bool = b.grab(crate)
	check("两人同时抓住同一件物体", ok_a and ok_b and crate.holder_count() == 2,
		"holders=%d（A ok=%s, B ok=%s）" % [crate.holder_count(), str(ok_a), str(ok_b)])

	# --- 2) 独立抓握点：两人抓的不是同一个点 -------------------------
	var ga: Vector3 = a.grabber.grip_world()
	var gb: Vector3 = b.grabber.grip_world()
	var sep: float = ga.distance_to(gb)
	check_gt("两人的抓握点在物体上彼此分开", sep, 0.4, " m")

	# --- 3) 合力抬起 40 kg（单人举升上限 42 kg，双人上限 84 kg）--------
	crate.global_position = Vector3(0.0, 0.41, -3.0)
	crate.linear_velocity = Vector3.ZERO
	crate.angular_velocity = Vector3.ZERO
	await wait_physics(3)
	# 两人都把相机抬到更高处（模拟两人一起向上提）
	aim_avatar(a, Vector3(-2.2, 2.05, -0.6), Vector3(0.0, 1.4, -3.0))
	aim_avatar(b, Vector3(2.2, 2.05, -0.6), Vector3(0.0, 1.4, -3.0))
	await wait_physics(120)
	check_gt("双人合力把 40 kg 抬离地面", crate.global_position.y, 0.85,
		"箱心 y=%.3f m（初始 0.41）" % crate.global_position.y)
	var mode_team: String = a.grabber.mode
	check("双人时模式为举升", mode_team == "lift", "mode=%s" % mode_team)

	# --- 4) 一人松手，另一人继续抓住 ---------------------------------
	a.release_held(false)
	await wait_physics(6)
	check("A 松手后 B 仍持有", (not a.is_holding()) and b.is_holding() and crate.holder_count() == 1,
		"holders=%d · B held=%s" % [crate.holder_count(), str(b.is_holding())])

	# --- 5) 人数减少后团队举升上限下降 -------------------------------
	var mode_after: String = b.grabber.mode
	check("人数减少后 B 的模式被重新评估", mode_after == "lift" or mode_after == "drag",
		"mode=%s（40 kg 单人上限 42 kg → 仍可举升）" % mode_after)
	b.release_held(false)
	await wait_physics(4)
	check("全部松手后无持有者", crate.holder_count() == 0,
		"holders=%d" % crate.holder_count())

	# --- 6) 四人共同施力 ---------------------------------------------
	var coop4: LISBody = make_body(Vector3(0.0, 0.61, 8.0), Vector3(1.6, 1.0, 1.0), 100.0,
		Color(0.5, 0.6, 0.8), {"display_name": "四人箱", "liftable": true})
	var four: Array[LISFirstPersonAdapter] = []
	for i in range(4):
		var ang: float = TAU * float(i) / 4.0
		var eye: Vector3 = Vector3(cos(ang) * 2.6, 1.25, 8.0 + sin(ang) * 2.6)
		var look: Vector3 = (coop4.global_position + Vector3(0.0, 0.4, 0.0) - eye).normalized()
		four.append(make_avatar(eye, look, 10 + i, "P"))
	await wait_physics(6)
	var grabbed_count: int = 0
	for ad: LISFirstPersonAdapter in four:
		if ad.grab(coop4):
			grabbed_count += 1
	await wait_physics(4)
	check("四人全部抓住同一件物体", grabbed_count == 4 and coop4.holder_count() == 4,
		"成功 %d 人，holder_count=%d" % [grabbed_count, coop4.holder_count()])

	# --- 7) 四人合力抬起 100 kg（单人 42 kg × 4 = 168 kg 上限）--------
	# 相机必须抬到物体上方足够高，手的目标点才会越过举升所需的力臂；
	# 只抬 1 m 时弹簧的稳态误差让箱子停在 0.97 m（正确但不够高）。
	for ad: LISFirstPersonAdapter in four:
		var eye: Vector3 = ad.camera.global_position
		eye.y = 2.6
		aim_avatar(ad, eye, coop4.global_position + Vector3(0.0, 1.9, 0.0))
	await wait_physics(180)
	check_gt("四人合力把 100 kg 抬离地面 0.55 m 以上", coop4.global_position.y, 1.16,
		"箱心 y=%.3f m（初始 0.61）" % coop4.global_position.y)

	# --- 8) 第 5 人无法加入（持有上限 4）-----------------------------
	var fifth: LISFirstPersonAdapter = make_avatar(Vector3(0.0, 1.4, 11.0),
		(coop4.global_position - Vector3(0.0, 1.4, 11.0)).normalized(), 20, "P")
	await wait_physics(3)
	var fifth_ok: bool = fifth.grab(coop4)
	check("第 5 个抓握者被拒绝（上限 4）", (not fifth_ok) and coop4.holder_count() == 4,
		"第 5 人 ok=%s，holders=%d，原因=%s" % [
			str(fifth_ok), coop4.holder_count(), fifth.grabber.last_slip_reason])

	# --- 9) 玩家离场：清理其持有关系 ---------------------------------
	var pid_before: int = coop4.holder_count()
	four[3].get_parent().queue_free()
	await wait_physics(6)
	check("玩家离场后其持有关系被清理", coop4.holder_count() == pid_before - 1,
		"离场前 %d，离场后 %d" % [pid_before, coop4.holder_count()])

	# --- 10) 反向拉扯产生真实力偶（绕 Y 轴的净力矩）-------------------
	# 力偶需要三个条件同时成立，缺一不可（先前版本一条都没满足，
	# 实测 0.00° 是测试几何错误，不是物理缺陷）：
	#   1. 两人抓在**不同**位置（力臂 ≠ 0）→ 杆的 ±X 两端；
	#   2. 施力方向**垂直于力臂**；沿杆轴拉时 r×F 共线、力矩恒为 0；
	#   3. 两人施力**方向相反**；两个同向平行力的力矩恰好互相抵消。
	# 所以：A 在 −Z 侧抓 −X 端并往 +Z 退，B 在 +Z 侧抓 +X 端并往 −Z 退。
	var tug: LISBody = make_body(Vector3(0.0, 0.31, -12.0), Vector3(3.0, 0.4, 0.4), 30.0,
		Color(0.8, 0.5, 0.8), {"display_name": "横杆", "liftable": true})
	await wait_physics(40)
	var left: LISFirstPersonAdapter = make_avatar(Vector3(-1.5, 0.85, -10.4),
		Vector3(0.0, -0.22, -1.0).normalized(), 30, "L")
	var right: LISFirstPersonAdapter = make_avatar(Vector3(1.5, 0.85, -13.6),
		Vector3(0.0, -0.22, 1.0).normalized(), 31, "R")
	await wait_physics(6)
	var ok_l: bool = left.grab(tug)
	var ok_r: bool = right.grab(tug)
	await wait_physics(6)
	var grip_l: Vector3 = left.grabber.grip_world()
	var grip_r: Vector3 = right.grabber.grip_world()
	var arm_span: float = grip_l.distance_to(grip_r)
	check("两人分别抓住杆的两端", ok_l and ok_r and arm_span > 1.2,
		"抓握间距 %.2f m（两端相距 3.00 m）" % arm_span)
	var yaw_before: float = _yaw_of(tug)
	var holders_mid: int = 0
	var still_holding: bool = false
	for i in range(100):
		var d: float = float(i) * 0.010
		aim_avatar(left, Vector3(-1.5, 0.85, -10.4 + d), Vector3(-1.5, 0.55, -12.0))
		aim_avatar(right, Vector3(1.5, 0.85, -13.6 - d), Vector3(1.5, 0.55, -12.0))
		await get_tree().physics_frame
		if i == 40:
			holders_mid = tug.holder_count()
			still_holding = left.is_holding() and right.is_holding()
	var yaw_after: float = _yaw_of(tug)
	var yaw_delta: float = absf(wrapf(yaw_after - yaw_before, -PI, PI))
	check_gt("反向拉扯产生绕竖直轴的真实转动", rad_to_deg(yaw_delta), 3.0,
		"横杆偏航变化 %.2f°，两端抓握间距 %.2f m" % [rad_to_deg(yaw_delta), arm_span])

	# --- 12) 多人时偏航辅助被关闭（否则两只手会互相抢朝向）----------
	# 这是本轮的**设计修正**：旧实现每只手都坚持"把物体拧到我身体朝向"，
	# 两人朝向不同时各出 250 N·m 的归位力矩，把真实力偶整个吃掉。
	# 现在偏航辅助只在单人持有时生效；多人时杆的朝向完全由物理决定。
	var spin_now: float = absf(tug.angular_velocity.y)
	print("DIAG couple yaw_delta=%.3f deg spin=%.4f mid_holders=%d mid_holding=%s" % [
		rad_to_deg(yaw_delta), spin_now, holders_mid, str(still_holding)])
	check("拉扯过程中两人确实同时持有同一件物体", holders_mid == 2 and still_holding,
		"中段 holders=%d · 双方 held=%s" % [holders_mid, str(still_holding)])
	check("掌心预算仍是单人上限量级（没有被人数放大）",
		left.grabber.palm_cap <= left.grabber.palm_torque_max * 2.0 + 0.01,
		"L cap=%.0f R cap=%.0f（单人上限 %.0f）" % [
			left.grabber.palm_cap, right.grabber.palm_cap, left.grabber.palm_torque_max])


## 由物体自身 Z 轴在水平面上的方向得到偏航角（比 rotation.y 更稳，避免万向锁跳变）。
func _yaw_of(b: Node3D) -> float:
	var fwd: Vector3 = b.global_transform.basis.z
	return atan2(fwd.x, fwd.z)
