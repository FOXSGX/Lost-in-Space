extends SceneTree

class Probe extends Node:
    var main: Main3D
    var role: String = "host"
    var phase: int = -1
    var checks: int = 0
    var failures: Array[String] = []

    func check(ok: bool, message: String) -> void:
        checks += 1
        if not ok:
            failures.append(message)
            push_error(role + ": " + message)

    func wait_for(predicate: Callable) -> bool:
        var deadline: int = Time.get_ticks_msec() + 10000
        while not predicate.call() and Time.get_ticks_msec() < deadline:
            await get_tree().create_timer(0.03).timeout
        return predicate.call()

    func filled() -> int:
        var count: int = 0
        for cell: Panel in main._health_hud.cells:
            if (cell.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == HealthHUD3D.FILLED:
                count += 1
        return count

    @rpc("any_peer", "call_remote", "reliable")
    func acknowledge(value: int) -> void:
        phase = value

    @rpc("authority", "call_remote", "reliable")
    func inspect(remaining: int) -> void:
        var id: int = multiplayer.get_unique_id()
        var p: SpacePlayer3D = main.players[id] as SpacePlayer3D
        check(await wait_for(func(): return p.health == remaining and filled() == remaining), "客户端生命与血格未同步: %d" % remaining)
        check(p.downed == (remaining == 0), "客户端倒地状态错误")
        check((main.players[1] as SpacePlayer3D).health == 3, "其他船员的部分生命未同步")
        if remaining == 4:
            main.damage_player(id, 1)
            check(p.health == 4, "客户端可以擅自修改生命")
        if remaining == 0:
            var position_before: Vector3 = p.position
            Input.action_press("move_up")
            Input.action_press("jump")
            Input.action_press("sprint")
            main.handle_action(id, "item_use")
            p.sync_transform.rpc_id(1, position_before + Vector3(4, 0, 0), true)
            await get_tree().create_timer(0.3).timeout
            Input.action_release("move_up")
            Input.action_release("jump")
            Input.action_release("sprint")
            check(p.position.distance_to(position_before) < 0.001 and not p.jet_active and not p.sprinting, "客户端倒地后仍在移动或喷气")
            check(main._health_hud.downed_panel.visible, "客户端没有倒地 HUD")
            var old: Array = [[id, 5, 100.0, 1.0, 0, false, 0, false, false, false, 0]]
            main.sync_vitals(old, true)
            check(p.health == 0 and p.downed and filled() == 0, "旧消息让客户端恢复生命")
        acknowledge.rpc_id(1, remaining)

    @rpc("authority", "call_remote", "reliable")
    func inspect_recovery() -> void:
        var id: int = multiplayer.get_unique_id()
        check(await wait_for(func(): return (main.players[id] as SpacePlayer3D).health == 2 and not (main.players[id] as SpacePlayer3D).downed and filled() == 2), "已有恢复流程未更新生命 HUD")
        acknowledge.rpc_id(1, 6)

    @rpc("authority", "call_remote", "reliable")
    func finish_remote() -> void:
        main._show_home()
        finish()

    func finish() -> void:
        print("HEALTH_LAYER1_NETWORK_%s: %d checks, %d failures" % [role, checks, failures.size()])
        get_tree().quit(0 if failures.is_empty() else 1)

    func run() -> void:
        var args: PackedStringArray = OS.get_cmdline_user_args()
        role = args[0] if not args.is_empty() else "host"
        main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
        add_child(main)
        await get_tree().process_frame
        main.network_port = 28442
        main._ship_session.persistence_enabled = false
        if role == "client":
            await get_tree().create_timer(0.5).timeout
            main._join_host()
            check(await wait_for(func(): return main.ship_active), "无法加入主舱")
            return
        main._create_host()
        check(await wait_for(func(): return main.players.size() == 2), "客户端没有连接")
        if main.players.size() != 2:
            finish()
            return
        var id: int = int(main.connected_ids[1])
        var p: SpacePlayer3D = main.players[id] as SpacePlayer3D
        main._items.add_item(id, "medical")
        main._items.publish()
        main.damage_player(1, 1)
        main.damage_player(1, 1)
        for remaining: int in [4, 3, 2, 1, 0]:
            main.damage_player(id, 1)
            inspect.rpc_id(id, remaining)
            check(await wait_for(func(): return phase == remaining), "客户端血格检查超时: %d" % remaining)
            check(p.health == remaining and p.downed == (remaining == 0), "主机生命结算不正确")
        check(main._items.count_kind(id, "medical") == 1, "倒地仍能使用医疗包")
        check(p.position.x < 2.0 and not p.sprinting, "主机接受了倒地移动请求")
        p.health = 2
        p.downed = false
        main.sync_health_state.rpc(main._vitals_snapshot(), true)
        inspect_recovery.rpc_id(id)
        check(await wait_for(func(): return phase == 6), "恢复同步检查超时")
        finish_remote.rpc_id(id)
        check(await wait_for(func(): return main.players.size() == 1), "客户端退出未清理")
        main._show_home()
        finish()

func _initialize() -> void:
    var probe: Probe = Probe.new()
    probe.name = "HealthLayer1Probe"
    root.add_child(probe)
    probe.run.call_deferred()
