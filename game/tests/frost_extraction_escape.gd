extends SceneTree

var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        push_error(message)

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main.network_port = 25770
    main._ship_session.persistence_enabled = false
    main._create_host()
    main._start_planet()
    main.set_process(false)
    var player := main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    player.global_position = Vector3(main.EXTRACTION.x, 0, main.EXTRACTION.y)
    main._tick_extraction(4.0)
    check(not main.mission_completed, "Unfinished objectives must block extraction")
    main.activated_beacons.assign([1, 2, 3])
    for flag in main.REQUIRED_KNOWLEDGE:
        main.knowledge_flags[flag] = true
    main.anomaly_resolved = true
    var enemy := main.create_space_enemy(1, 902)
    main.add_child(enemy)
    enemy.global_position = Vector3(100, 0, 100)
    main.enemies[902] = enemy
    main._tick_extraction(1.0)
    check(main.extraction_enabled and is_equal_approx(main.extraction_progress, 1.0), "Living enemies must not require a map-wide cleanup")
    check("起飞" in main._next_objective_text(), "Countdown should be visible in objective HUD")
    player.global_position.x += 5
    main._tick_extraction(0.1)
    check(main.extraction_progress == 0, "Leaving platform must reset countdown")
    check("0/1" in main._next_objective_text(), "HUD must explain missing teammates")
    player.global_position.x -= 5
    player.downed = true
    main._tick_extraction(4.0)
    check(not main.mission_completed, "Downed teammate must be rescued")
    player.downed = false
    main._tick_extraction(1.0)
    var state := main._world_snapshot()
    check(state.extraction_enabled and state.extraction_progress == 1.0, "Late join snapshot must carry extraction state")
    main.sync_extraction_state(true, 2.0)
    check(main.extraction_progress == 2.0, "Client handler must apply countdown")
    main._ship_session.active = true
    main.sync_extraction_state(false, 0.0)
    check(main.extraction_progress == 2.0, "Delayed surface update must not overwrite ship state")
    main._ship_session.active = false
    main._tick_extraction(1.0)
    check(main.mission_completed and not main.enemies.is_empty(), "Team must escape successfully with enemies alive")
    main.queue_free()
    await process_frame
    print("Frost extraction: %d checks, %d failures" % [checks, failures])
    quit(0 if failures == 0 else 1)
