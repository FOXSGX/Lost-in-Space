extends SceneTree

## 角色专属工具诊断：分配、跨星球效果、可视化、主机快照。

var checks: int = 0
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
    main.network_port = 25910 + int(Time.get_ticks_msec() % 80)
    main._create_host()
    main.connected_ids = [1]
    for peer_id in [2, 3, 4]:
        main.connected_ids.append(peer_id)
        main.spawn_player_for_peer(peer_id)
    main.spawn_player_for_peer(1)
    await process_frame

    # 1. 四名玩家拿到四件不同工具
    var tools: Array = []
    for peer_id in [1, 2, 3, 4]:
        var tool: String = main.kit_tool_for(peer_id)
        check(tool != "", "玩家 %d 没有分配专属工具" % peer_id)
        check(not tools.has(tool), "玩家 %d 的工具与队友重复：%s" % [peer_id, tool])
        tools.append(tool)
    check(tools.size() == 4, "工具分配数量不正确：%d" % tools.size())
    check(String(main.kit_tool_for(1)) == "conduit", "首位玩家没有拿到导能枪")

    # 2. 霜烬星：导能枪拉长修复距离，钩索拉长拾取距离，扫描仪扩大扫描半径
    main.kit_assignments[1] = "conduit"
    main.kit_assignments[2] = "hook"
    main.kit_assignments[3] = "scanner"
    main.kit_assignments[4] = "shield"
    check(main._repair_reach(1) > 4.0, "导能枪没有延长修复距离：%.1f" % main._repair_reach(1))
    check(main._repair_reach(2) <= 2.0, "非导能角色的修复距离被错误放大")
    check(main._pickup_reach(2) > 10.0, "钩索没有延长拾取距离：%.1f" % main._pickup_reach(2))
    check(main._pickup_reach(1) <= 3.0, "非钩索角色的拾取距离被错误放大")
    var base_radius: float = main.SCAN_DEVICE_RADIUS
    check(main._scan_radius_for(3) > base_radius * 1.4, "扫描仪没有扩大扫描半径")
    check(main._scan_radius_for(1) <= base_radius + 0.01, "非扫描角色的扫描半径被错误放大")

    # 3. 护盾：举盾后减伤
    var shield_player: SpacePlayer3D = main.players[4] as SpacePlayer3D
    main._raise_kit_shield(4)
    check(shield_player.shield_remaining > 0.0, "护盾没有展开")
    var before: int = shield_player.health
    main.damage_player(4, 2)
    var taken: int = before - shield_player.health
    check(taken < 2, "护盾没有减免伤害：实际扣 %d" % taken)
    check(taken >= 1, "护盾把伤害减到 0，规则被破坏")
    check(shield_player.shield_remaining <= 0.0, "护盾吸收后没有消耗")

    # 4. 工具模型挂到角色身上（此时四名玩家都还在场）
    var conduit_player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    check(conduit_player._visual != null, "玩家没有视觉模型")
    if conduit_player._visual != null:
        check(conduit_player._visual._tool_node != null, "导能枪没有挂到角色身上")
    conduit_player.set_tool("scanner")
    await process_frame
    if conduit_player._visual != null:
        check(conduit_player._visual._tool_node != null, "换装后扫描仪没有挂上")
    conduit_player.set_tool("conduit")
    await process_frame

    # 5. 护盾可视化
    shield_player.shield_remaining = 1.2
    await process_frame
    await process_frame
    if shield_player._visual != null:
        check(shield_player._visual._shield_dome != null, "护盾没有生成可视化模型")
        if shield_player._visual._shield_dome != null:
            check(shield_player._visual._shield_dome.visible, "护盾模型没有显示")
    shield_player.shield_remaining = 0.0
    await process_frame
    await process_frame
    if shield_player._visual != null and shield_player._visual._shield_dome != null:
        check(not shield_player._visual._shield_dome.visible, "护盾结束后模型没有隐藏")

    # 6. 共振星：导能枪接管供能端、钩索接管夹具，不再走校准
    main.connected_ids = [1, 2]
    main._ship_session.enter_ship(true, [1, 2], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1, 2]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    await process_frame
    var stage: ResonanceStage3D = main._resonance_stage
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    stage.heat_chain_complete = true
    var module: Dictionary = stage.modules[0]
    player.teleport_to(Vector3(module["rail_position"]))
    await process_frame
    check(stage._minigame_kind_for(1, "repair") == "", "导能枪没有接管轨道供能端")
    var hook_player: SpacePlayer3D = main.players[2] as SpacePlayer3D
    hook_player.set_physics_process(false)
    hook_player.teleport_to(Vector3(module["clamp_position"]))
    await process_frame
    check(stage._minigame_kind_for(2, "repair") == "", "钩索没有接管对接夹具")
    hook_player.teleport_to(Vector3(module["rail_position"]))
    await process_frame
    check(stage._minigame_kind_for(2, "repair") != "", "钩索错误地接管了供能端")

    # 7. 快照包含工具分配
    var snapshot: Dictionary = main._world_snapshot()
    check(snapshot.has("kit"), "主机快照没有包含工具分配")
    var saved: Dictionary = snapshot.get("kit", {})
    check(saved.size() >= 2, "快照里的工具分配不完整")

    print("RESONANCE_CHARACTER_KIT: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
