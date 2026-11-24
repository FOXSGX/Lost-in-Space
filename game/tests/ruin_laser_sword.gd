extends SceneTree

## 腐墟星激光剑与撬棍视角验收：第一人称武器确实换了，攻击/撬门各自切换。

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
	var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 27850 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame

	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(player != null, "玩家没有生成")
	var viewmodel := player.get("_ruin_viewmodel") as Node3D
	check(viewmodel != null, "腐墟星第一人称视角模型没有建立")
	if viewmodel != null:
		var core := viewmodel.find_child("SaberBladeCore", true, false) as MeshInstance3D
		var glow := viewmodel.find_child("SaberBladeGlow", true, false) as MeshInstance3D
		var hilt := viewmodel.find_child("SaberHilt", true, false) as MeshInstance3D
		check(core != null and glow != null and hilt != null, "激光剑缺少刀芯/光晕/剑柄")
		if core != null:
			var material := core.material_override as StandardMaterial3D
			check(material != null and material.emission_enabled, "激光剑刀芯没有发光材质")
		check(viewmodel.find_child("SaberBladePivot", true, false) != null, "激光剑没有挥舞枢轴")

	var crowbar := player.get("_ruin_crowbar") as Node3D
	check(crowbar != null and not crowbar.visible, "撬棍模型缺失或初始可见")

	if viewmodel != null:
		var idle_rotation := viewmodel.rotation
		player.play_ruin_attack()
		player._update_ruin_viewmodel(0.12)
		check(not viewmodel.rotation.is_equal_approx(idle_rotation), "激光剑攻击没有挥动")
		check(player.get("_ruin_swing_remaining") > 0.0, "激光剑攻击计时没有启动")

	player.start_ruin_force()
	player.set_ruin_force_progress(0.5)
	player._update_ruin_viewmodel(0.05)
	check(player.get("_ruin_force_active"), "撬门状态没有启动")
	check(viewmodel == null or not viewmodel.visible, "撬门时激光剑没有收起")
	check(crowbar != null and crowbar.visible, "撬门时撬棍没有显示")
	player.stop_ruin_force()
	player._update_ruin_viewmodel(0.05)
	check(not player.get("_ruin_force_active"), "撬门结束后状态没有清掉")
	check(crowbar == null or not crowbar.visible, "撬门结束后撬棍没有收起")

	check(String(CrewItems3D.NAMES.get("lockpick", "")) == "撬锁工具", "撬锁工具没有登记到物品表")
	check(main._items.count_kind(1, "lockpick") >= 1, "登陆后没有发放撬锁工具")

	print("RUIN_LASER_SWORD: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
