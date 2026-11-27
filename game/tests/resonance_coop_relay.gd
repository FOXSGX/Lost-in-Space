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
        remaining -= delta

func prepare_two_player_stage() -> void:
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25420 + int(Time.get_ticks_msec() % 80)
    main._create_host()
    main.connected_ids = [1, 2]
    main._start_planet("electromagnetic")
    await process_frame
    stage = main._resonance_stage
    stage.minigames_enabled = false
    for player_value in main.players.values():
        var player: SpacePlayer3D = player_value as SpacePlayer3D
        if player != null:
            player.set_physics_process(false)
    stage.heat_chain_complete = true
    stage.checkpoint = 1
    stage.modules[0]["state"] = "docked"
    stage.modules[0]["phase"] = "docked"
    stage.modules[1]["state"] = "ready"
    stage.modules[1]["phase"] = "ready"
    stage._refresh_objective_guide()

func run() -> void:
    await prepare_two_player_stage()
    var first: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var second: SpacePlayer3D = main.players[2] as SpacePlayer3D
    first.global_position = stage.SUPPORT_RELAY_HIGH_POSITION
    main.handle_action(1, "repair")
    step(0.2)
    check(int(stage.support_relay["phase"]) == 0, "高位接收端在低位未启动时错误推进")
    first.global_position = stage.SUPPORT_RELAY_LOW_POSITION
    main.handle_action(1, "repair")
    step(0.2)
    check(int(stage.support_relay["phase"]) == 1, "低位发送端没有启动接力窗口")
    first.global_position = stage.SUPPORT_RELAY_HIGH_POSITION
    main.handle_action(1, "repair")
    step(0.2)
    check(not stage.shortcut_unlocked and int(stage.support_relay["phase"]) == 1, "同一玩家连续操作高位端错误完成接力")
    second.global_position = stage.SUPPORT_RELAY_HIGH_POSITION
    main.handle_action(2, "repair")
    step(0.2)
    check(stage.shortcut_unlocked, "不同玩家没有完成高位接力并开启安全闸")
    check(stage.support_relay_reward_active, "接力完成后没有留下快线奖励")
    check(stage.shortcut_body.collision_layer == 0, "接力完成后安全闸碰撞没有关闭")
    var relay_snapshot: Dictionary = stage.stage_snapshot()
    check(relay_snapshot.has("support_relay") and relay_snapshot.has("support_relay_reward_active"), "支援接力状态没有进入主机快照")

    stage.shortcut_unlocked = false
    stage.support_relay_reward_active = false
    stage._reset_support_relay()
    first.global_position = stage.SUPPORT_RELAY_LOW_POSITION
    main.handle_action(1, "repair")
    step(0.2)
    step(stage.SUPPORT_RELAY_WINDOW + 0.2)
    check(int(stage.support_relay["phase"]) == 0 and int(stage.support_relay["failures"]) == 1, "接力超时没有恢复到待机")

    main.connected_ids = [1]
    stage.shortcut_unlocked = false
    stage.support_relay_reward_active = false
    stage._reset_support_relay()
    first.global_position = stage.SUPPORT_RELAY_LOW_POSITION
    main.handle_action(1, "repair")
    step(0.2)
    main.handle_action(1, "resonance_drone")
    step(0.2)
    check(String(stage.drone_state["target"]) == "support_relay_high", "单人接力没有让无人机前往高位端")
    first.global_position = stage.SUPPORT_RELAY_HIGH_POSITION
    main.handle_action(1, "repair")
    step(0.2)
    check(stage.shortcut_unlocked and int(stage.support_relay["high_peer"]) == -1, "单人无人机没有替代高位接收端")
    check(String(stage.drone_state["target"]) == "support_relay_high", "单人接力完成后无人机目标状态丢失")

    print("RESONANCE_COOP_RELAY: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
