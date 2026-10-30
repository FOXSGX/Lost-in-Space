extends SceneTree

## Read-only diagnostic for the Resonance planet test boundary.
## It inspects resource loading and the synthetic host setup without changing game logic.

const ENEMY_PATH := "res://scenes/enemy_3d.tscn"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_diagnostic")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func describe(value: Variant) -> String:
	if value == null:
		return "<null>"
	if value is Object:
		var object := value as Object
		return "%s (%s)" % [object.get_class(), object.get_instance_id()]
	return str(value)

func run_diagnostic() -> void:
	print("RESONANCE_DIAGNOSTIC: start")
	var exists_any := ResourceLoader.exists(ENEMY_PATH)
	var exists_scene := ResourceLoader.exists(ENEMY_PATH, "PackedScene")
	print("RESOURCE exists_any=%s exists_packed_scene=%s" % [exists_any, exists_scene])
	check(exists_any, "敌人场景路径不存在：%s" % ENEMY_PATH)
	check(exists_scene, "敌人场景不是可识别的 PackedScene：%s" % ENEMY_PATH)

	var loaded := ResourceLoader.load(ENEMY_PATH)
	print("RESOURCE loaded=%s path=%s" % [describe(loaded), loaded.resource_path if loaded is Resource else "<none>"])
	check(loaded != null, "ResourceLoader.load 返回空对象")
	check(loaded is PackedScene, "ResourceLoader.load 返回类型不是 PackedScene")
	var packed := loaded as PackedScene
	var direct_instance: Node = null
	if packed != null:
		direct_instance = packed.instantiate()
	print("RESOURCE direct_instance=%s valid=%s" % [describe(direct_instance), is_instance_valid(direct_instance)])
	check(direct_instance != null and is_instance_valid(direct_instance), "直接实例化敌人场景失败")
	check(direct_instance is SpaceEnemy3D, "敌人场景实例不是 SpaceEnemy3D")
	# 不提前释放临时实例：该诊断要排除资源缓存/释放顺序对阶段回调的干扰。

	var main_scene := ResourceLoader.load("res://scenes/main_3d.tscn") as PackedScene
	check(main_scene != null, "主场景加载失败")
	var main: Main3D = null
	if main_scene != null:
		main = main_scene.instantiate() as Main3D
	check(main != null, "主场景实例化失败")
	if main == null:
		print("RESONANCE_DIAGNOSTIC: %d checks, %d failures" % [checks, failures.size()])
		quit(1)
		return
	root.add_child(main)
	await process_frame
	check(main.ENEMY_SCENE != null, "Main3D.ENEMY_SCENE 为空")
	var main_enemy := main.ENEMY_SCENE.instantiate() as SpaceEnemy3D
	print("MAIN_CONST enemy_scene=%s instance=%s valid=%s" % [describe(main.ENEMY_SCENE), describe(main_enemy), is_instance_valid(main_enemy)])
	check(main_enemy != null and is_instance_valid(main_enemy), "Main3D.ENEMY_SCENE 实例化失败")

	main.network_port = 24700 + int(Time.get_ticks_msec() % 200)
	main._ship_session.persistence_enabled = false
	main._create_host()
	main.connected_ids = [1, 2]
	main._start_planet("electromagnetic")
	await process_frame
	var stage := main._resonance_stage
	print("HOST state is_host=%s peer=%s game_started=%s planet=%s connected_ids=%s players=%d stage=%s" % [main.is_host, describe(main.multiplayer.multiplayer_peer), main.game_started, main.current_planet_id, main.connected_ids, main.players.size(), describe(stage)])
	check(main.is_host, "诊断主机没有建立")
	check(main.game_started and main.current_planet_id == "electromagnetic", "共振星没有进入测试状态")
	check(stage != null, "共振星阶段对象为空")
	if stage != null:
		var packed_state := stage.ENEMY_SCENE.get_state()
		var state_nodes := packed_state.get_node_count() if packed_state != null else -1
		print("STAGE const enemy_scene=%s nodes=%d stations=%d enemies=%d" % [describe(stage.ENEMY_SCENE), state_nodes, stage.stations.size(), main.enemies.size()])
		var stage_enemy := stage.ENEMY_SCENE.instantiate() as SpaceEnemy3D
		print("STAGE_CONST instance=%s valid=%s" % [describe(stage_enemy), is_instance_valid(stage_enemy)])
		check(stage_enemy != null and is_instance_valid(stage_enemy), "ResonanceStage3D.ENEMY_SCENE 实例化失败")
		var enemies_before := main.enemies.size()
		stage._spawn_security_drones(1)
		await process_frame
		print("STAGE_SPAWN before=%d after=%d keys=%s" % [enemies_before, main.enemies.size(), main.enemies.keys()])
		check(main.enemies.size() > enemies_before, "共振星实际安保生成路径没有产生有效敌人")

	print("NETWORK peer_unique_id=%d connected_ids=%s has_peer_2=%s" % [main.multiplayer.get_unique_id(), main.connected_ids, main.multiplayer.has_multiplayer_peer() and main.multiplayer.get_peers().has(2)])
	print("RESONANCE_DIAGNOSTIC: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
