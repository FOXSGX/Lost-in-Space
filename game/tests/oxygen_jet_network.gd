extends SceneTree

class Probe extends Node:
    var main: Main3D
    var mode: String = "host"
    var phase: int = 0
    var checks: int = 0
    var failures: Array[String] = []

    func check(ok: bool, message: String) -> void:
        checks += 1
        if not ok:
            failures.append(message)
            push_error(mode + ": " + message)

    func wait_for(predicate: Callable, seconds: float = 10.0) -> bool:
        var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
        while not predicate.call() and Time.get_ticks_msec() < deadline:
            await get_tree().create_timer(0.04).timeout
        return predicate.call()

    @rpc("any_peer", "call_remote", "reliable")
    func acknowledge(next: int) -> void:
        phase = next

    @rpc("authority", "call_remote", "reliable")
    func inspect_and_fly(uid: String, point: Vector3, euler: Vector3) -> void:
        var id: int = multiplayer.get_unique_id()
        check(await wait_for(func(): return main._items.has_jet(1)), "主机装备没有同步")
        check(await wait_for(func(): return is_instance_valid(main._items._prop_bodies.get(uid))), "丢落物没有同步")
        var bottle: RigidBody3D = main._items._prop_bodies.get(uid) as RigidBody3D
        await get_tree().create_timer(0.3).timeout
        if bottle != null:
            check(bottle.freeze, "客户端独立模拟了权威道具")
            check(bottle.position.distance_to(point) < 0.15, "主机与客户端落点不一致")
            check(absf(bottle.global_basis.y.dot(Vector3.UP)) < 0.4, "客户端没有看见倒地姿态")
            check(bottle.quaternion.angle_to(Quaternion.from_euler(euler)) < 0.3, "完整旋转没有同步")
        main.handle_action(id, "item_use")
        check(await wait_for(func(): return main._items.has_jet(id)), "客户端装配请求未由主机确认")
        var player: SpacePlayer3D = main.players[id] as SpacePlayer3D
        check(await wait_for(func(): return player.jet_charge >= 0.995), "客户端没有收到充气资源同步")
        check(main._items.tank_oxygen(id) < 98.1, "客户端充气没有消耗瓶内氧气")
        var oxygen_before: float = main._items.tank_oxygen(id)
        player.teleport_to(Vector3(3, 0, 4))
        await get_tree().create_timer(0.3).timeout
        Input.action_press("jump")
        await get_tree().create_timer(0.48).timeout
        check(player.jet_active and player.position.y > 1.0, "客户端不能推进")
        acknowledge.rpc_id(1, 1)
        await get_tree().create_timer(0.35).timeout
        Input.action_release("jump")
        check(await wait_for(func(): return player.jet_charge >= 0.995), "客户端喷气后无法在地面重新充气")
        check(main._items.tank_oxygen(id) < oxygen_before - 1.9, "客户端第二次充气没有持续扣减瓶内氧气")
        var before_stale: float = main._items.tank_oxygen(id)
        var bag: Dictionary = main._items.ensure_bag(id)
        main._items.sync_jet_resources([[id, int(bag.tank_serial), 0, 100.0, 1.0, 2.0]])
        check(is_equal_approx(main._items.tank_oxygen(id), before_stale), "过时资源消息让氧气回涨")
        acknowledge.rpc_id(1, 3)

    @rpc("authority", "call_remote", "reliable")
    func reconnect_and_inspect(uid: String) -> void:
        main._show_home()
        await get_tree().create_timer(0.8).timeout
        main._join_host()
        check(await wait_for(func(): return main.ship_active and main.players.size() == 2), "中途重连失败")
        check(await wait_for(func(): return main._items.has_jet(1) and is_instance_valid(main._items._prop_bodies.get(uid))), "重连没有获得设备和落地物快照")
        check(main._ship_session.stock_oxygen_level() < 97.0, "离队归库或重连丢失了部分氧气瓶余量")
        var body: RigidBody3D = main._items._prop_bodies.get(uid) as RigidBody3D
        if body != null:
            check(absf(body.global_basis.y.dot(Vector3.UP)) < 0.4, "重连后瓶子姿态重置")
        acknowledge.rpc_id(1, 2)

    @rpc("authority", "call_remote", "reliable")
    func stop() -> void:
        main._show_home()
        finish()

    func run() -> void:
        var args: PackedStringArray = OS.get_cmdline_user_args()
        mode = args[0] if not args.is_empty() else "host"
        main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
        add_child(main)
        await get_tree().process_frame
        main.network_port = 28432
        main._ship_session.persistence_enabled = false
        if mode == "client":
            await get_tree().create_timer(0.5).timeout
            main._join_host()
            if not await wait_for(func(): return main.ship_active, 15.0):
                check(false, "没有进入主舱")
                finish()
            return
        main._create_host()
        if not await wait_for(func(): return main.players.size() == 2):
            check(false, "客户端没有连接")
            finish()
            return
        var id: int = int(main.connected_ids[1])
        var items: CrewItems3D = main._items
        items.add_item(1, "oxygen")
        main.handle_action(1, "item_use")
        items.add_item(id, "oxygen")
        items.add_item(1, "oxygen")
        var host_player: SpacePlayer3D = main.players[1] as SpacePlayer3D
        host_player.teleport_to(Vector3(0, 0, 5))
        main.handle_action(1, "item_drop")
        await get_tree().create_timer(3.5).timeout
        check(items.has_jet(1) and items.drops.size() == 1, "主机没有保留装备和放下的第二瓶")
        var uid: String = String(items.drops[0].uid)
        var body: RigidBody3D = items._prop_bodies.get(uid) as RigidBody3D
        check(body != null and not body.freeze, "主机没有真实物理模拟")
        inspect_and_fly.rpc_id(id, uid, body.position, body.rotation)
        check(await wait_for(func(): return phase == 1), "客户端检查超时")
        var remote: SpacePlayer3D = main.players[id] as SpacePlayer3D
        check(items.has_jet(id) and items.occupied(id) == 0, "客户端装配没有释放格位")
        check(remote.jet_active and remote.position.y > 1.0, "客户端推进动作未同步给主机")
        check(is_instance_valid(remote._jet_pack) and remote._jet_pack.visible, "远端设备模型不可见")
        await get_tree().create_timer(0.7).timeout
        check(not remote.jet_active, "松开后远端仍喷气")
        check(await wait_for(func(): return phase == 3), "客户端资源递减检查超时")
        var before: int = int(main._ship_session.stock.oxygen)
        reconnect_and_inspect.rpc_id(id, uid)
        check(await wait_for(func(): return main.players.size() == 1), "离队没有清理角色")
        check(int(main._ship_session.stock.oxygen) == before + 1, "离队时已安装氧气瓶没有归库")
        check(await wait_for(func(): return phase == 2), "重连快照检查超时")
        id = int(main.connected_ids[1])
        stop.rpc_id(id)
        check(await wait_for(func(): return main.players.size() == 1), "退出后没有清理连接")
        main._show_home()
        finish()

    func finish() -> void:
        print("OXYGEN_JET_NETWORK_" + mode.to_upper() + " " + JSON.stringify({"checks": checks, "failures": failures}))
        get_tree().quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
    var probe: Probe = Probe.new()
    probe.name = "JetNetworkProbe"
    root.add_child.call_deferred(probe)
    probe.run.call_deferred()
