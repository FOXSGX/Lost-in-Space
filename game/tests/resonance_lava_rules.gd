extends SceneTree

var checks: int = 0
var failures: Array[String] = []
var main: Main3D
var stage: ResonanceStage3D

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func step(seconds: float) -> void:
    var remaining: float = seconds
    while remaining > 0.0:
        var delta: float = minf(remaining, 0.05)
        stage.stage_tick(delta)
        for player_value in main.players.values():
            var player: SpacePlayer3D = player_value as SpacePlayer3D
            if player != null and player.falling_to_lava:
                player._tick_resonance_fall(delta)
        remaining -= delta

func run() -> void:
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25190 + int(Time.get_ticks_msec() % 200)
    main._create_host()
    main.connected_ids = [1, 2]
    main.spawn_player_for_peer(2)
    main._start_planet("electromagnetic")
    await process_frame
    stage = main._resonance_stage
    main.set_process(false)
    var lava_player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var reviver: SpacePlayer3D = main.players[2] as SpacePlayer3D
    lava_player.set_physics_process(false)
    reviver.set_physics_process(false)
    check(not stage._is_lava_position(Vector3(0.0, 0.0, 2.0)), "轨道安全连接路径被错误判为熔岩")
    check(stage._is_lava_position(Vector3(-2.0, 0.0, 29.0)), "洞底内部裂隙没有判为熔岩")
    lava_player.global_position = Vector3(73.0, 0.0, 0.0)
    reviver.global_position = Vector3(71.0, 0.0, 0.0)
    step(0.2)
    check(lava_player.falling_to_lava, "悬崖边缘没有进入下坠动画")
    check(lava_player.global_position.y < 0.0, "下坠动画没有产生垂直位移")
    step(0.9)
    check(lava_player.lava_dead, "熔岩落底后没有触发阵亡")
    check(lava_player.downed, "熔岩阵亡没有进入倒地兼容状态")
    main.handle_action(2, "revive")
    step(3.4)
    check(lava_player.lava_dead, "熔岩阵亡被队友复活，违反不可复活规则")
    reviver.global_position = Vector3(-2.0, 0.0, 29.0)
    step(0.2)
    check(reviver.falling_to_lava, "裂隙边缘没有进入下坠动画")
    step(0.9)
    check(reviver.lava_dead, "洞底裂隙没有触发不可复活阵亡")
    print("RESONANCE_LAVA_RULES: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
