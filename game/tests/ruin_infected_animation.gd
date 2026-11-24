extends SceneTree

## 腐墟星感染体分件动画验收：三种形态都要有可读的步态/呼吸/受击，而不是整只滑行。

const VISUAL := preload("res://scripts/ruin_infected_visual.gd")
const ENEMY := preload("res://scripts/ruin_infected_3d.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	for form: int in [VISUAL.Form.WALKER, VISUAL.Form.BLOATER, VISUAL.Form.CRAWLER]:
		var visual := VISUAL.new() as Node3D
		root.add_child(visual)
		visual.call("configure", form, false)
		check(visual.get("_body_pivot") != null, "形态 %d 没有身体枢轴" % form)

		visual.call("animate", 0.10, 2.2, 0.0)
		var leg_name := "LegStump" if form == VISUAL.Form.CRAWLER else "LegL"
		var leg_pivot := (visual.get("_pivots") as Dictionary).get(leg_name) as Node3D
		check(leg_pivot != null, "形态 %d 缺少 %s" % [form, leg_name])
		var leg_a := leg_pivot.rotation if leg_pivot != null else Vector3.ZERO
		var body_a: Vector3 = (visual.get("_body_pivot") as Node3D).position
		visual.call("animate", 0.22, 2.2, 0.0)
		var leg_b := leg_pivot.rotation if leg_pivot != null else Vector3.ZERO
		var body_b: Vector3 = (visual.get("_body_pivot") as Node3D).position
		check(not leg_a.is_equal_approx(leg_b), "形态 %d 腿部没有摆动" % form)
		check(not body_a.is_equal_approx(body_b), "形态 %d 身体没有起伏" % form)

		if form == VISUAL.Form.WALKER:
			check((visual.get("_pivots") as Dictionary).has("KneeL") and (visual.get("_pivots") as Dictionary).has("KneeR"), "步行者缺少膝关节")
			check((visual.get("_pivots") as Dictionary).has("ArmLElbow") and (visual.get("_pivots") as Dictionary).has("ArmRElbow"), "步行者缺少肘关节")
		if form == VISUAL.Form.CRAWLER:
			check((visual.get("_pivots") as Dictionary).has("LegStump"), "爬行者缺少残肢关节")

		visual.call("animate", 0.10, 0.0, 0.0)
		visual.call("flinch")
		check(float(visual.get("_flinch_energy")) > 0.5, "形态 %d 受击没有回弹能量" % form)
		visual.call("animate", 0.10, 0.0, 1.0)
		visual.call("die")
		check(bool(visual.get("_dead")), "形态 %d 死亡没有停掉动作" % form)
		var spec: Dictionary = visual.call("stat_specs")
		check(spec.has("collision_radius") and float(spec["collision_radius"]) > 0.0, "形态 %d 碰撞尺寸无效" % form)
		visual.queue_free()
		await process_frame

	# 再走一次真实敌人节点的 server_tick 覆写，确认空玩家表不会报错、动画复用路径能跑。
	var enemy := ENEMY.new() as SpaceEnemy3D
	root.add_child(enemy)
	enemy.call("setup_form", VISUAL.Form.WALKER)
	enemy.call("setup", 1, 1)
	var tick: Dictionary = enemy.call("server_tick", 0.016, {})
	check(tick.has("sync"), "感染体 server_tick 没有返回同步字典")
	check(enemy.get("_visual_node") != null, "感染体没有生成动画节点")
	enemy.queue_free()
	await process_frame

	print("RUIN_INFECTED_ANIMATION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
