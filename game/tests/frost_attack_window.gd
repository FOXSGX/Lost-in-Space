extends SceneTree

var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main.network_port = 25769
    main._ship_session.persistence_enabled = false
    main._create_host()
    main._start_planet()
    main.set_process(false)
    var player := main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    var enemy := main.create_space_enemy(1, 901)
    main.add_child(enemy)
    enemy.global_position = Vector3(0, 50, 0)
    player.global_position = Vector3(2, 50, 0)
    player.health = 5
    enemy.server_tick(0.1, main.players, Vector3.ZERO, false, false, [], true)
    check(player.health == 5 and enemy.frost_windup > 0, "Attack must warn before damage")
    check(enemy._strike_marker.visible, "Warning ring must be visible")
    var locked := enemy.frost_strike_position
    player.global_position = Vector3(8, 50, 0)
    enemy.server_tick(0.3, main.players, Vector3.ZERO, false, false, [], true)
    check(enemy.frost_strike_position == locked, "Windup must not track dodge")
    enemy.server_tick(0.5, main.players, Vector3.ZERO, false, false, [], true)
    check(player.health == 5 and enemy.frost_recovery > 0, "Dodging must avoid damage and open recovery")
    check(not enemy._strike_marker.visible, "Warning must clear after impact")
    player.global_position = enemy.global_position
    enemy.server_tick(0.2, main.players, Vector3.ZERO, false, false, [], true)
    check(player.health == 5, "Recovery must allow a safe counterattack")
    enemy.server_tick(2.0, main.players, Vector3.ZERO, false, false, [], true)
    enemy.server_tick(0.1, main.players, Vector3.ZERO, false, true, [], true)
    enemy.server_tick(0.8, main.players, Vector3.ZERO, false, true, [], true)
    check(player.health == 4, "Standing in impact must take exactly one hit, even in storm")
    enemy.frost_recovery = 0
    enemy.server_tick(0.1, main.players, Vector3(15, 50, 0), true, false, [], true)
    check(enemy.frost_windup == 0, "Low-frequency lure must still divert enemies")
    player.global_position = enemy.global_position
    enemy.attack_timer = 0
    enemy.server_tick(0.1, main.players)
    check(player.health == 3 and enemy.frost_windup == 0, "Other planets must retain their existing attack rules")
    enemy.queue_free()
    main.queue_free()
    await process_frame
    print("Frost attack window: %d failures" % failures)
    quit(0 if failures == 0 else 1)
