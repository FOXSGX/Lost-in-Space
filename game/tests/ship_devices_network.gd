extends SceneTree

class Probe extends Node:
    var main: Main3D
    var role: int = 0
    var peers: Dictionary = {}
    var acknowledgements: Dictionary = {}
    var checks: int = 0
    var failures: Array[String] = []

    func check(ok: bool, message: String) -> void:
        checks += 1
        if not ok:
            failures.append(message)
            push_error("role %d: %s" % [role, message])

    func wait_for(predicate: Callable, seconds: float = 10.0) -> bool:
        var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
        while not predicate.call() and Time.get_ticks_msec() < deadline:
            await get_tree().create_timer(0.04).timeout
        return predicate.call()

    @rpc("any_peer", "call_remote", "reliable")
    func register(index: int) -> void:
        peers[index] = multiplayer.get_remote_sender_id()

    @rpc("any_peer", "call_remote", "reliable")
    func acknowledge(index: int, step: String) -> void:
        acknowledgements[step + str(index)] = true

    @rpc("authority", "call_local", "reliable")
    func operate(id: String, step: String) -> void:
        var peer_id: int = multiplayer.get_unique_id()
        var player: SpacePlayer3D = main.players[peer_id] as SpacePlayer3D
        var point: Vector3 = ShipDevices3D.point_for(id)
        point.y = 0
        point.z += 1.6 if id.begins_with("pilot_") else 1.3
        player.teleport_to(point)
        player._camera_yaw = 0.0
        player._camera_yaw_target = 0.0
        player.rotation.y = 0.0
        if role != 0:
            player.sync_transform.rpc(player.position, false, 0.0)
        await get_tree().create_timer(0.18).timeout
        main.handle_action(peer_id, "interact")
        await get_tree().create_timer(0.18).timeout
        if role == 0:
            acknowledgements[step + "0"] = true
        else:
            acknowledge.rpc_id(1, role, step)

    func send(index: int, id: String, step: String) -> void:
        if index == 0:
            await operate(id, step)
        else:
            operate.rpc_id(int(peers[index]), id, step)
            check(await wait_for(func(): return acknowledgements.has(step + str(index))), "设备操作超时：" + step)

    @rpc("authority", "call_remote", "reliable")
    func reconnect() -> void:
        main._show_home()
        await get_tree().create_timer(2.0).timeout
        main._join_host()
        check(await wait_for(func(): return main.ship_active and main.players.size() == 4), "重新加入失败")
        register.rpc_id(1, role)

    @rpc("authority", "call_remote", "reliable")
    func verify_departure() -> void:
        check(await wait_for(func(): return main.game_started), "四人客户端没有自动登陆")
        check(main.players.size() == 4 and main.current_planet_id == "demo", "四人客户端登陆快照错误")
        check(main._ship_session._layer.find_children("*", "BaseButton", true, false).is_empty(), "客户端仍有主舱按钮")
        acknowledge.rpc_id(1, role, "departed")

    @rpc("authority", "call_remote", "reliable")
    func stop() -> void:
        main._show_home()
        finish()

    func run() -> void:
        var args: PackedStringArray = OS.get_cmdline_user_args()
        role = int(args[0]) if not args.is_empty() else 0
        main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
        add_child(main)
        await get_tree().process_frame
        main.network_port = 28234
        main._ship_session.persistence_enabled = false
        if role != 0:
            await get_tree().create_timer(0.5 + role * 0.15).timeout
            main._join_host()
            check(await wait_for(func(): return main.ship_active and main.players.size() == 4), "加入四人房间失败")
            register.rpc_id(1, role)
            if not await wait_for(func(): return false, 45.0):
                check(false, "四人测试等待超时")
                finish()
            return
        main._create_host()
        check(await wait_for(func(): return main.players.size() == 4 and peers.size() == 3), "四个真实进程没有连接")
        if peers.size() != 3:
            finish()
            return
        await send(0, "pilot_0", "first")
        await send(1, "pilot_0", "occupied")
        check(main._ship_session.station_owners.get(0, 0) == 1 and main._ship_session.ready_peers.size() == 1, "他人抢占驾驶台")
        await send(1, "pilot_1", "second")
        check(main._ship_session.ready_peers.size() == 2 and main._ship_session.launch_remaining < 0, "未全员就位就开始出发")
        await send(2, "route_electromagnetic", "route")
        check(main._ship_session.selected_destination == "electromagnetic" and main._ship_session.station_owners.is_empty(), "客户端换航线未取消旧就位")
        await send(2, "route_demo", "routeback")
        for index: int in 4:
            await send(index, "pilot_%d" % index, "ready")
        check(main._ship_session.station_owners.size() == 4 and main._ship_session.all_ready(), "四人无法各用一台驾驶台")
        var old_id: int = int(peers[3])
        reconnect.rpc_id(old_id)
        check(await wait_for(func(): return main.players.size() == 3), "真实掉线没有移除船员")
        check(main._ship_session.station_owners.is_empty() and main._ship_session.launch_remaining < 0 and not main.game_started, "掉线没有中止倒数并清除就位")
        for index: int in 3:
            await send(index, "pilot_%d" % index, "waitingjoin")
        check(main._ship_session.all_ready() and main._ship_session.launch_remaining > 0, "三人就位未开始倒数")
        check(await wait_for(func(): return main.players.size() == 4 and int(peers[3]) != old_id), "第四名玩家未重新加入")
        check(main._ship_session.ready_peers.is_empty(), "重连保留了旧就位")
        for index: int in 4:
            await send(index, "pilot_%d" % index, "again")
        check(main._ship_session.station_owners.size() == 4, "重连后驾驶台占用不完整")
        check(await wait_for(func(): return main.game_started), "四人就位后没有自动出发")
        verify_departure.rpc()
        check(await wait_for(func(): return acknowledgements.has("departed1") and acknowledgements.has("departed2") and acknowledgements.has("departed3")), "四个客户端没有确认登陆")
        check(main.players.size() == 4, "自动出发丢失船员")
        for index: int in [3, 2, 1]:
            stop.rpc_id(int(peers[index]))
            check(await wait_for(func(): return main.players.size() == index), "退出房间后船员未清理")
        await get_tree().create_timer(0.2).timeout
        main._show_home()
        finish()

    func finish() -> void:
        print("SHIP_DEVICES_NETWORK_ROLE_%d: %d checks, %d failures" % [role, checks, failures.size()])
        get_tree().quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
    var probe: Probe = Probe.new()
    probe.name = "DevicesNetworkProbe"
    root.add_child.call_deferred(probe)
    probe.run.call_deferred()
