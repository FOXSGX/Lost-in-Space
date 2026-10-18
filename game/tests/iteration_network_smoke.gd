extends SceneTree

class AuditPeer extends Node:
    var main: Main3D
    var mode := ""
    var port := 24931
    var output := ""
    var phase := 0
    var checks := 0
    var failures: Array[String] = []

    func check(ok: bool, message: String) -> void:
        checks += 1
        if not ok:
            failures.append(message)
            push_error(mode + ": " + message)

    func wait_for(predicate: Callable, seconds := 15.0) -> bool:
        var end := Time.get_ticks_msec() + int(seconds * 1000)
        while not predicate.call() and Time.get_ticks_msec() < end:
            await get_tree().create_timer(0.05).timeout
        return predicate.call()

    func run() -> void:
        var args := OS.get_cmdline_user_args()
        mode = args[0]
        output = args[1]
        port = int(args[2])
        main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
        add_child(main)
        await get_tree().process_frame
        main._ship_session.persistence_enabled = false
        main.network_port = port
        if mode == "client":
            if not await wait_for(func(): return FileAccess.file_exists(output.path_join("host.ready"))):
                check(false, "主机就绪握手超时")
                finish()
                return
            main._address_edit.text = "127.0.0.1"
            main._join_host()
            var connected := await wait_for(func(): return main.multiplayer.get_unique_id() != 1 and main.players.size() == 2)
            check(connected, "真实客户端未连接或没有两名船员")
            print("NETWORK_CLIENT id=%s peers=%s players=%s status=%s" % [main.multiplayer.get_unique_id(), main.multiplayer.get_peers(), main.players.keys(), main._status_label.text])
            if not connected:
                finish()
                return
            if not await wait_for(func(): return phase == 9, 30.0):
                check(false, "等待双星球联机测试结束超时")
                finish()
            return

        main._create_host()
        check(main.is_host, "主机创建失败")
        var ready := FileAccess.open(output.path_join("host.ready"), FileAccess.WRITE)
        if ready != null:
            ready.store_string(str(port))
            ready.close()
        print("NETWORK_HOST_READY port=%d" % port)
        if not await wait_for(func(): return main.players.size() == 2):
            check(false, "真实对端未加入；不能继续星球联机验证")
            print("NETWORK_HOST ids=%s peers=%s status=%s" % [main.connected_ids, main.multiplayer.get_peers(), main._status_label.text])
            finish()
            return
        var client_id := int(main.multiplayer.get_peers()[0])
        check(main.connected_ids.has(client_id), "真实客户端未登记到队伍")
        verify_phase.rpc_id(client_id, "ship", 1)
        check(await wait_for(func(): return phase == 1), "主舱真实 RPC 未确认")
        for planet in ["demo", "electromagnetic"]:
            main._ship_session.select_destination(planet)
            main._ship_session.request("ready")
            ready_client.rpc_id(client_id)
            check(await wait_for(func(): return main._ship_session.all_ready()), "客户端准备状态未同步：" + planet)
            main._confirm_land()
            check(await wait_for(func(): return main.game_started), "主机未登陆：" + planet)
            var target_phase := 2 if planet == "demo" else 4
            verify_phase.rpc_id(client_id, planet, target_phase)
            check(await wait_for(func(): return phase == target_phase), "客户端登陆快照未确认：" + planet)
            main.return_to_ship.rpc("完整检查：联机往返冒烟", main._vitals_snapshot())
            await get_tree().create_timer(0.3).timeout
            verify_phase.rpc_id(client_id, "ship", target_phase + 1)
            check(await wait_for(func(): return phase == target_phase + 1), "客户端返航快照未确认：" + planet)
        end_client.rpc_id(client_id)
        await get_tree().create_timer(0.3).timeout
        finish()

    @rpc("authority", "call_remote", "reliable")
    func ready_client() -> void:
        main._ship_session.request("ready")

    @rpc("authority", "call_remote", "reliable")
    func verify_phase(expected: String, next_phase: int) -> void:
        await get_tree().create_timer(0.25).timeout
        check(main.players.size() == 2, "船员数量不为 2：" + expected)
        if expected == "ship":
            check(main.ship_active and not main.game_started, "客户端主舱状态错误")
        else:
            check(main.game_started and main.current_planet_id == expected, "客户端星球状态错误：" + expected)
            if expected == "electromagnetic":
                check(main._resonance_stage.stations.size() == 3, "客户端三座塔未同步")
        for player in main.players.values():
            check(player.get_node_or_null("ProtagonistVisual") != null, "真实对端角色缺少外观")
        print("NETWORK_PHASE %s id=%d players=%s" % [expected, main.multiplayer.get_unique_id(), main.players.keys()])
        acknowledge.rpc_id(1, next_phase)

    @rpc("any_peer", "call_remote", "reliable")
    func acknowledge(next_phase: int) -> void:
        phase = next_phase

    @rpc("authority", "call_remote", "reliable")
    func end_client() -> void:
        phase = 9
        finish()

    func finish() -> void:
        print("ITERATION_NETWORK_%s: %d checks, %d failures" % [mode.to_upper(), checks, failures.size()])
        get_tree().quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
    var peer := AuditPeer.new()
    peer.name = "AuditPeer"
    root.add_child.call_deferred(peer)
    peer.run.call_deferred()
