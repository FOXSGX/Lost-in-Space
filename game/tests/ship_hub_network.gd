extends SceneTree

class Probe extends Node:
    var main: Main3D
    var mode := ""
    var failures: Array[String] = []
    var phase := 0
    var checks := 0

    func check(condition: bool, message: String) -> void:
        checks += 1
        if not condition:
            failures.append(message)
            push_error(mode + ": " + message)

    func wait_for(predicate: Callable, seconds := 8.0) -> bool:
        var deadline := Time.get_ticks_msec() + int(seconds * 1000)
        while not predicate.call() and Time.get_ticks_msec() < deadline:
            await get_tree().create_timer(0.05).timeout
        return predicate.call()

    func run() -> void:
        var args := OS.get_cmdline_user_args()
        mode = args[0] if not args.is_empty() else "host"
        main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
        add_child(main)
        await get_tree().process_frame
        main.network_port = 24569
        main._ship_session.persistence_enabled = false
        if mode == "client":
            await get_tree().create_timer(0.4).timeout
            main._join_host()
            if not await wait_for(func(): return phase == 5):
                check(false, "等待主机测试指令超时")
                finish()
            return
        main._create_host()
        main._ship_session.switch_area(false)
        var joined := await wait_for(func(): return main.players.size() == 2)
        check(joined, "客户端未中途加入训练舱")
        if not joined:
            finish()
            return
        var client_id := int(main.connected_ids[1])
        verify_training.rpc_id(client_id)
        check(await wait_for(func(): return phase >= 1), "客户端未确认训练舱快照")
        main._ship_session.switch_area.rpc(true)
        await get_tree().create_timer(0.25).timeout
        var player := main.players[1] as SpacePlayer3D
        player.teleport_to(ShipHub3D.STORAGE)
        main._ship_session.request("take", "medical")
        main._ship_session.request("take", "oxygen")
        take_supplies.rpc_id(client_id)
        check(await wait_for(func(): return phase >= 2), "客户端领取物资超时")
        check(int(main._ship_session.stock.medical) == 6 and int(main._ship_session.stock.oxygen) == 6, "共享库存未守恒")
        check(int(main._ship_session.packs[client_id].medical) == 1, "主机未记录客户端背包")
        main._ship_session.request("ready")
        check(not main._ship_session.all_ready(), "只有主机准备时被判为全员就绪")
        verify_stock_and_ready.rpc_id(client_id)
        check(await wait_for(func(): return main._ship_session.all_ready()), "客户端准备状态未同步")
        main._confirm_land()
        await get_tree().create_timer(0.3).timeout
        verify_departure.rpc_id(client_id)
        check(await wait_for(func(): return phase >= 3), "客户端未同步登陆")
        check(main.game_started and main.players.size() == 2, "主机登陆时丢失船员")
        var client_player := main.players[client_id] as SpacePlayer3D
        client_player.health = 2
        client_player.oxygen = 15
        main.sync_vitals.rpc(main._vitals_snapshot())
        use_supplies.rpc_id(client_id)
        check(await wait_for(func(): return int(main._ship_session.packs[client_id].medical) == 0 and int(main._ship_session.packs[client_id].oxygen) == 0), "客户端用品使用未由主机结算")
        check(client_player.health == 4 and client_player.oxygen > 58, "客户端用品没有恢复状态")
        main.mission_completed = true
        main.salvage_value = 30
        main.return_to_ship.rpc("联机测试返航", main._vitals_snapshot())
        await get_tree().create_timer(0.3).timeout
        verify_return.rpc_id(client_id)
        check(await wait_for(func(): return phase >= 4), "客户端未同步返航")
        check(main.ship_active and main._ship_session.credits == 30, "主机返航结算错误")
        var before := int(main._ship_session.stock.oxygen)
        var held := int(main._ship_session.packs[client_id].oxygen)
        end_client.rpc_id(client_id)
        check(await wait_for(func(): return main.players.size() == 1), "断开船员未被移除")
        check(not main._ship_session.packs.has(client_id) and int(main._ship_session.stock.oxygen) == before + held, "断开船员物资没有回库")
        finish()

    @rpc("authority", "call_remote", "reliable")
    func verify_training() -> void:
        await get_tree().create_timer(0.2).timeout
        check(main.ship_active and not main._ship_session.in_hub and main.players.size() == 2, "中途加入训练舱的区域或船员错误")
        acknowledge.rpc_id(1, 1)

    @rpc("authority", "call_remote", "reliable")
    func take_supplies() -> void:
        var player := main.players[multiplayer.get_unique_id()] as SpacePlayer3D
        check(main._ship_session.in_hub, "客户端未切换主舱")
        player.teleport_to(ShipHub3D.STORAGE)
        player.sync_transform.rpc(player.position)
        await get_tree().create_timer(0.25).timeout
        main._ship_session.request("interact")
        main._ship_session.request("take", "medical")
        main._ship_session.request("take", "oxygen")
        await get_tree().create_timer(0.25).timeout
        check(main._ship_session._facility == "storage", "客户端未打开储物界面")
        acknowledge.rpc_id(1, 2)

    @rpc("authority", "call_remote", "reliable")
    func verify_stock_and_ready() -> void:
        check(main._ship_session.stock.medical == 6 and main._ship_session.stock.oxygen == 6, "客户端库存快照错误")
        main._ship_session.close_panel()
        main._ship_session.request("ready")

    @rpc("authority", "call_remote", "reliable")
    func verify_departure() -> void:
        check(main.game_started and not main.ship_active and main.players.size() == 2, "客户端登陆失败或丢失船员")
        check(main._ship_session.packs[multiplayer.get_unique_id()].medical == 1, "登陆后客户端背包丢失")
        acknowledge.rpc_id(1, 3)

    @rpc("authority", "call_remote", "reliable")
    func use_supplies() -> void:
        main._ship_session.request("use_medical")
        main._ship_session.request("use_oxygen")

    @rpc("authority", "call_remote", "reliable")
    func verify_return() -> void:
        check(main.ship_active and main._ship_session.in_hub and main.players.size() == 2, "客户端返航场景错误")
        check(main._ship_session.credits == 30 and main._ship_session.hull == 72, "客户端返航资源快照错误")
        check(main._ship_session.ready_peers.is_empty(), "客户端返航未清除准备状态")
        var player := main.players[multiplayer.get_unique_id()] as SpacePlayer3D
        check(player.health == 4, "客户端返航丢失生命状态")
        player.teleport_to(ShipHub3D.STORAGE)
        player.sync_transform.rpc(player.position)
        await get_tree().create_timer(0.2).timeout
        main._ship_session.request("take", "oxygen")
        await get_tree().create_timer(0.2).timeout
        acknowledge.rpc_id(1, 4)

    @rpc("any_peer", "call_remote", "reliable")
    func acknowledge(next_phase: int) -> void:
        phase = next_phase

    @rpc("authority", "call_remote", "reliable")
    func end_client() -> void:
        phase = 5
        main._show_home()
        finish()

    func finish() -> void:
        print("SHIP_HUB_NETWORK_%s: %d checks, %d failures" % [mode.to_upper(), checks, failures.size()])
        get_tree().quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
    var probe := Probe.new()
    probe.name = "NetworkProbe"
    root.add_child.call_deferred(probe)
    probe.run.call_deferred()
