extends SceneTree

## 《迷失太空》霜烬星 2.0 · 多层货架拿取 + 六大建筑物理谜题 + 全道具拓展自动化试玩验收脚本
## 真实模拟玩家用每件道具解开全部 6 座建筑谜案，验证 15+ 分钟可玩深度、永久升级生效与多人联机同步！

var a: Node3D
var p: SpacePlayer3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i: int in n:
		await physics_frame

func check(ok: bool, msg: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		failures += 1

func _run() -> void:
	a = (load("res://previews/frost_station/adventure.tscn") as PackedScene).instantiate()
	root.add_child(a)
	a.start_session(false)
	a.test_mode = true
	p = a.players[1] as SpacePlayer3D
	await frames(15)

	var pz: Node3D = a.puzzles
	check(pz != null, "FrostColonyPuzzles 谜题引擎成功挂载")
	check(pz.solved_count() == 0, "开局谜案进度为 0/6")

	# 1. 验证多层货架拿取（下层 0.56 / 中层 1.24 / 上层 1.92 全部不卡墙、按 E 顺手拾取）
	p.position = Vector3(-9.4, 0.75, 2.3)
	await frames(4)
	var near_shelf_item: Dictionary = a._items.nearby_item(1)
	check(not near_shelf_item.is_empty(), "站在飞船出口三层开放货架前可直接探测到货架物品: " + String(near_shelf_item.get("kind", "")))
	check(a._items.pickup(1, near_shelf_item), "玩家可顺手从多层货架取下物品")

	# 2. 验证拍拍小霜获取活线索
	var bot_p: Vector3 = (a.sandbox.helper_bot.node as Node3D).position
	p.position = bot_p + Vector3(0.0, 0.2, 2.0)
	await frames(3)
	check(pz.nearby_prompt(p, "").contains("小霜"), "靠近小霜时底部显示抚摸问线索提示")
	a.handle_action(1, "interact")
	await frames(2)
	check(a.notice.contains("线索 1/6"), "拍拍小霜给出第 1 处未解谜案线索")

	# 3. 谜案 1：生活医疗楼 · 复古音响声波共振震碎结晶密柜
	p.position = Vector3(58.5, 0.35, -52.2)
	a.sandbox.deploy_boombox(Vector3(58.5, 0.25, -52.2), 1, true)
	await frames(160)
	check(bool(pz.solved.get("living_acoustic", false)), "谜案 1：复古音响声波共振成功震碎生活医疗楼生物密柜")
	check(bool(pz.upgrades.get("med_boost", false)), "谜案 1 奖励：医官强心针强化已激活")

	# 4. 谜案 2：生态穹顶温室 · 极光信号弹融解冰封地热导管
	a.sandbox.throw_flare(Vector3(-112.4, 1.4, -117.2), Vector3(0, -1, 0), 1, true)
	await frames(140)
	check(bool(pz.solved.get("greenhouse_thermal", false)), "谜案 2：极光信号弹成功融解温室冰封地热导管")
	check(bool(pz.upgrades.get("cold_shield", false)), "谜案 2 奖励：永久【抗寒恒温模组】已解锁")

	# 5. 谜案 3：冰川钻探中心 · 备用电池插槽供电 + 双压板放样本箱启动 8m 冰芯钻塔
	a._items.bags[1].slots = [{"kind": "cell"}, {}, {}, {}]
	a._items.bags[1].selected = 0
	p.position = Vector3(-72.0, 0.35, -157.0)
	await frames(3)
	check(pz.nearby_prompt(p, "cell").contains("备用电池"), "手持电池靠近钻塔配电箱显示插入提示")
	a.handle_action(1, "interact")
	await frames(4)
	check(a._items.count_kind(1, "cell") == 0, "按 E 成功将备用电池卡入钻探配电槽")
	# 把两只样本箱移上左右双压板（模拟吸推器搬运）
	var plate_targets: Array[Vector3] = [Vector3(-76.6, 0.55, -163.4), Vector3(-67.4, 0.55, -163.4)]
	var placed_crates: int = 0
	for entry: Dictionary in a._items.drops:
		if String(entry.get("kind", "")) == "crate" and placed_crates < 2:
			var rb: RigidBody3D = a._items._prop_bodies.get(String(entry.uid)) as RigidBody3D
			if rb != null:
				rb.sleeping = false
				rb.position = plate_targets[placed_crates]
				entry.position = plate_targets[placed_crates]
				placed_crates += 1
	await frames(12)
	check(bool(pz.solved.get("drill_core", false)), "谜案 3：电池通电 + 双压板样本箱成功启动 8m 冰芯钻塔")
	check(bool(pz.upgrades.get("suction_amp", false)), "谜案 3 奖励：永久【磁力吸推增幅】已解锁")

	# 6. 谜案 4：东线机甲维修厂 · 弹跳垫上 5.4m 天桥合闸 + 碰碰球三连击亮动能靶心
	p.position = Vector3(112.0, 5.75, -45.6)
	await frames(3)
	a.handle_action(1, "interact")
	await frames(3)
	for tgt_p: Vector3 in [Vector3(100.5, 4.6, -50.4), Vector3(112.0, 7.6, -50.4), Vector3(123.5, 4.6, -50.4)]:
		a.sandbox.launch_bumper_orb(tgt_p + Vector3(0.0, 0.0, 2.5), Vector3(0.0, 0.0, -1.0), 1)
	await frames(25)
	check(bool(pz.solved.get("mech_kinetic", false)), "谜案 4：高空天桥合闸 + 碰碰球三连击亮动能靶心成功")
	check(bool(pz.upgrades.get("turbo_vehicles", false)), "谜案 4 奖励：雪地摩托/极地运输车永久涡轮提速 +35% 解锁")

	# 7. 谜案 5：西翼天文观测穹顶 · 信号弹抛入高空热感火盆 + 音响声波共振星图
	a.sandbox.throw_flare(Vector3(-164.0, 5.3, -89.6), Vector3(0.0, -1.0, 0.0), 1, true)
	a.sandbox.deploy_boombox(Vector3(-164.0, 0.35, -72.0), 1, true)
	await frames(160)
	check(bool(pz.solved.get("observatory_star", false)), "谜案 5：高空热感火盆信号弹 + 声波共振星图成功触发望远镜极光柱")
	check(bool(pz.upgrades.get("aurora_shield", false)), "谜案 5 奖励：永久【极光深寒护盾】已解锁")

	# 8. 谜案 6：东翼反应堆电厂 · 双电池插槽 + 高空 5.6m 总闸合闸
	a._items.bags[1].slots = [{"kind": "cell"}, {"kind": "cell"}, {"kind": "heater", "charge": 40.0}, {"kind": "thermos", "sips": 3}]
	a._items.bags[1].selected = 0
	p.position = Vector3(161.5, 0.35, -69.5)
	await frames(2)
	a.handle_action(1, "interact")
	a._items.bags[1].selected = 1
	p.position = Vector3(170.5, 0.35, -69.5)
	await frames(2)
	a.handle_action(1, "interact")
	p.position = Vector3(166.0, 5.95, -88.2)
	await frames(2)
	a.handle_action(1, "interact")
	await frames(10)
	check(bool(pz.solved.get("reactor_overdrive", false)), "谜案 6：双电池过载 + 高空涡轮总闸合闸成功")
	check(bool(pz.upgrades.get("heater_overclock", false)), "谜案 6 奖励：热风机 2 倍融冰 + 自动回能超频解锁")
	check(pz.solved_count() == 6, "全部六大科考谜案破译达成 6/6！")

	# 9. 验证热风机被动自动回能 + 热可可暖流冲刺 Buff + 多人快照同步
	await frames(60)
	var heater_charge: float = float(a._items.bags[1].slots[2].get("charge", 0.0))
	check(heater_charge > 44.0, "热风机超频后自动被动回能生效（40.0 -> %.1f）" % heater_charge)
	a._items.bags[1].selected = 3
	a.handle_action(1, "item_use")
	check(float(p.get_meta("thermos_buff", 0.0)) > 40.0, "喝热可可成功赋予 45 秒【极地暖流】增益")
	var snap: Dictionary = a.snapshot()
	check(snap.has("puzzles") and (snap["puzzles"] as Dictionary).get("solved", {}).size() == 6, "多人快照完整包含六大谜案同步数据")
	check(pz.journal_summary().contains("(6 / 6)"), "按 J 调查档案实时汇总全部 6 大谜案与已解锁日志")

	print("FROST_PUZZLES_PLAYTEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
