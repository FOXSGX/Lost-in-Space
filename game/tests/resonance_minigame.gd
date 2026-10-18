extends SceneTree

## 小游戏诊断：验证设备交互必须通过校准小游戏才能生效。

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func _tick(stage: ResonanceStage3D, seconds: float) -> void:
    var remaining: float = seconds
    while remaining > 0.0:
        var delta: float = minf(remaining, 0.05)
        stage.stage_tick(delta)
        remaining -= delta

func run() -> void:
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25710 + int(Time.get_ticks_msec() % 80)
    main._create_host()
    main.connected_ids = [1]
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    await process_frame
    main.set_process(false)
    var stage: ResonanceStage3D = main._resonance_stage
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    check(stage.minigames_enabled, "小游戏默认没有开启")

    # 1. 靠近热阀按 E：应该开启小游戏，而不是直接开阀
    player.teleport_to(Vector3(stage.heat_valve_positions["left"]))
    main.handle_action(1, "repair")
    check(not stage.minigame.is_empty(), "设备交互没有开启小游戏")
    check(stage._minigame_lever != null, "校准没有生成装置拉杆")
    check(int(stage.heat_valves["left"]) == 0, "小游戏还没完成就结算了热阀")
    var game: Dictionary = stage.minigame
    check(float(game["zone_width"]) > 0.0 and float(game["zone_width"]) < 0.4, "校准亮区宽度不合理")

    # 2. 光标不在亮区时确认：失败且不结算（先过掉 0.12 秒动作冷却）
    _tick(stage, 0.2)
    stage.minigame["cursor"] = 0.02
    main.handle_action(1, "repair")
    check(stage.minigame.is_empty(), "失败后小游戏没有关闭")
    check(int(stage.heat_valves["left"]) == 0, "校准失败却推进了热阀")

    # 3. 重新开启，把光标放进亮区再确认：成功并结算
    _tick(stage, 0.2)
    main.handle_action(1, "repair")
    check(not stage.minigame.is_empty(), "再次交互没有开启小游戏")
    var start: float = float(stage.minigame["zone_start"])
    var width: float = float(stage.minigame["zone_width"])
    _tick(stage, 0.2)
    stage.minigame["cursor"] = start + width * 0.5
    main.handle_action(1, "repair")
    check(stage.minigame.is_empty(), "成功后小游戏没有关闭")
    check(int(stage.heat_valves["left"]) == 1, "校准成功没有推进热阀")

    # 4. 超时会自动关闭且不结算
    _tick(stage, 0.3)
    player.teleport_to(Vector3(stage.heat_valve_positions["right"]))
    main.handle_action(1, "repair")
    check(not stage.minigame.is_empty(), "第二个热阀没有开启小游戏")
    _tick(stage, 12.0)
    check(stage.minigame.is_empty(), "校准超时后小游戏没有关闭")
    check(int(stage.heat_valves["right"]) == 0, "校准超时却推进了热阀")

    # 5. 光束转盘（dial）：指针扫到绿弧后按 E 锁定
    stage._open_minigame(1, "repair", "beam")
    check(String(stage.minigame.get("mode", "")) == "dial", "光束节点没有使用转盘小游戏")
    _tick(stage, 0.2)
    var beam_start: float = float(stage.minigame["zone_start"])
    var beam_width: float = float(stage.minigame["zone_width"])
    stage.minigame["cursor"] = beam_start + beam_width * 0.5
    main.handle_action(1, "repair")
    check(stage.minigame.is_empty(), "光束转盘成功后没有关闭")

    # 6. 镜面角度（stepped）：光标不动，靠连按 E 转动，落进绿区自动锁定
    stage._open_minigame(1, "repair", "mirror")
    check(String(stage.minigame.get("mode", "")) == "stepped", "镜面节点没有使用步进角度小游戏")
    var presses: int = 0
    while not stage.minigame.is_empty() and presses < 14:
        _tick(stage, 0.2)
        main.handle_action(1, "repair")
        presses += 1
    check(stage.minigame.is_empty(), "镜面步进没有在 14 次按键内锁定")
    check(presses >= 2, "镜面角度一次按键就完成，步进没有生效：%d" % presses)

    print("RESONANCE_MINIGAME: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
