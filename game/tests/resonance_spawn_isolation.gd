extends SceneTree

## Minimal reproduction for the stage-owned enemy spawn path.
## No direct enemy instantiation is performed before the stage callback.

func _initialize() -> void:
	call_deferred("run_check")

func run_check() -> void:
	var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 24800 + int(Time.get_ticks_msec() % 150)
	main._create_host()
	main.connected_ids = [1, 2]
	main._start_planet("electromagnetic")
	await process_frame
	var stage := main._resonance_stage
	var constants: Dictionary = stage.get_script().get_script_constant_map()
	var script_enemy = constants.get("ENEMY_SCENE")
	var before := main.enemies.size()
	print("SPAWN_ISOLATION before=%d scene=%s state_nodes=%d script_constant=%s script_nodes=%d same=%s" % [before, stage.ENEMY_SCENE, stage.ENEMY_SCENE.get_state().get_node_count(), script_enemy, script_enemy.get_state().get_node_count() if script_enemy is PackedScene else -1, script_enemy == stage.ENEMY_SCENE])
	stage._spawn_security_drones(1)
	await process_frame
	print("SPAWN_ISOLATION after=%d keys=%s state_nodes=%d" % [main.enemies.size(), main.enemies.keys(), stage.ENEMY_SCENE.get_state().get_node_count()])
	if main.enemies.size() > before:
		print("RESONANCE_SPAWN_ISOLATION_OK")
		quit(0)
	else:
		push_error("阶段安保生成没有创建敌人")
		print("RESONANCE_SPAWN_ISOLATION_FAILED")
		quit(1)
