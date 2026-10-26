extends SceneTree

class Probe extends Node:
    var main: Main3D
    var role: String = "host"
    var phase: int = 0
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
            await get_tree().create_timer(0.04).timeout
        return predicate.call()

    @rpc("any_peer", "call_remote", "reliable")
    func acknowledge(value: int) -> void:
        phase = value

    @rpc("authority", "call_remote", "reliable")
    func exercise() -> void:
        var id: int = multiplayer.get_unique_id()
        var items: CrewItems3D = main._items
        check(await wait_for(func(): return items.has_jet(id) and main._ship_session.has_gear(id, "thermal_suit")), "双装备初始快照未同步")
        main.handle_action(id, "toggle_equipment")
        check(await wait_for(func(): return bool(items.ensure_bag(id).equipment_active)), "客户端 Tab 动作未同步")
        main.handle_action(id, "slot_previous")
        check(await wait_for(func(): return int(items.ensure_bag(id).equipment_selected) == 0), "客户端装备选格未同步")
        main.handle_action(id, "item_drop")
        check(await wait_for(func(): return not items.has_jet(id) and items.drops.size() == 1), "客户端卸装未生成唯一地面物品")
        check(main._ship_session.has_gear(id, "thermal_suit") and items.occupied(id) == 0, "客户端卸下错误装备或挤入手持栏")
        var amount: float = float(items.drops[0].oxygen)
        check(amount > 28.5 and amount <= 31.0, "客户端卸下氧气瓶余量错误")
        var uid: String = String(items.drops[0].uid)
        check(await wait_for(func(): return is_instance_valid(items._prop_bodies.get(uid))), "客户端没有地面装备模型")
        var body: RigidBody3D = items._prop_bodies.get(uid) as RigidBody3D
        check(body != null and body.freeze, "客户端擅自模拟卸下物理")
        main.handle_action(id, "item_drop")
        await get_tree().create_timer(0.2).timeout
        check(items.drops.size() == 1, "客户端重复 G 复制了装备")
        main.handle_action(id, "interact")
        check(await wait_for(func(): return items.count_kind(id, "oxygen") == 1), "客户端不能拾回卸下装备")
        check(await wait_for(func(): return not bool(items.ensure_bag(id).equipment_active) and items.selected(id).get("kind", "") == "oxygen"), "客户端拾取后没有同步切回手持栏并选中新物品")
        main.handle_action(id, "item_use")
        check(await wait_for(func(): return items.has_jet(id)), "客户端不能重新装备")
        check(absf(items.tank_oxygen(id) - amount) < 0.1, "客户端重新装备补满或丢失余量")
        main.handle_action(id, "toggle_equipment")
        main.handle_action(id, "slot_next")
        main.handle_action(id, "item_drop")
        check(await wait_for(func(): return not main._ship_session.has_gear(id, "thermal_suit") and items.drops.size() == 1), "客户端外套卸下效果未同步")
        check(items.has_jet(id) and items.drops[0].kind == "thermal_suit", "客户端外套卸下影响氧气瓶")
        acknowledge.rpc_id(1, 1)

    @rpc("authority", "call_remote", "reliable")
    func reconnect() -> void:
        main._show_home()
        await get_tree().create_timer(0.6).timeout
        main._join_host()
        check(await wait_for(func(): return main.ship_active and main.players.size() == 2), "装备卸下后无法重连")
        var id: int = multiplayer.get_unique_id()
        check(await wait_for(func(): return main._items.ensure_bag(id).equipment.size() == 2 and main._ship_session.has_gear(1, "wide_scanner") and main._ship_session.has_gear(1, "signal_stabilizer")), "重连未获得主机双装备快照")
        check(not main._items.has_jet(id) and main._items.equipment_index(id, "thermal_suit") < 0, "重连复制了原装备")
        check(main._items.drops.size() == 1 and main._items.drops[0].kind == "thermal_suit", "重连丢失地面装备")
        acknowledge.rpc_id(1, 2)

    @rpc("authority", "call_remote", "reliable")
    func stop() -> void:
        main._show_home()
        finish()

    func finish() -> void:
        print("EQUIPMENT_BAR_NETWORK_%s: %d checks, %d failures" % [role, checks, failures.size()])
        get_tree().quit(0 if failures.is_empty() else 1)

    func run() -> void:
        var args: PackedStringArray = OS.get_cmdline_user_args()
        role = args[0] if not args.is_empty() else "host"
        main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
        add_child(main)
        await get_tree().process_frame
        main.network_port = 28329
        main._ship_session.persistence_enabled = false
        if role == "client":
            await get_tree().create_timer(0.5).timeout
            main._join_host()
            check(await wait_for(func(): return main.ship_active), "客户端无法加入")
            return
        main._create_host()
        check(await wait_for(func(): return main.players.size() == 2), "客户端没有连接")
        if main.players.size() != 2:
            finish()
            return
        var id: int = int(main.connected_ids[1])
        var items: CrewItems3D = main._items
        var ship: ShipSession3D = main._ship_session
        ship.gear_stock = {"thermal_suit": 1, "wide_scanner": 1, "signal_stabilizer": 1}
        check(items.equip_gear(1, "wide_scanner") and items.equip_gear(1, "signal_stabilizer"), "无法同时装备两件普通装备")
        check(ship.has_gear(1, "wide_scanner") and ship.has_gear(1, "signal_stabilizer"), "两件装备效果未同时启用")
        items.add_item(1, "oxygen")
        main.handle_action(1, "item_use")
        check(not items.has_jet(1) and items.count_kind(1, "oxygen") == 1, "装备满位仍安装或消耗氧气瓶")
        ship.credits = 100
        ship._execute_device(1, {"kind": "gear", "item": "thermal_suit"})
        check(ship.credits == 100, "装备满位仍扣款")
        items.add_item(id, "oxygen", -1, {"oxygen": 31.0})
        items.mount_oxygen(id)
        check(items.equip_gear(id, "thermal_suit"), "客户端第二件装备无法安装")
        ship.broadcast()
        exercise.rpc_id(id)
        check(await wait_for(func(): return phase == 1), "客户端装备操作超时")
        check(items.has_jet(id) and not ship.has_gear(id, "thermal_suit") and items.drops.size() == 1, "主机未保留客户端卸装结果")
        check(items.available_gear("thermal_suit") == 0 and items.available_gear("wide_scanner") == 0, "地面或已装备的物件仍可重复领取")
        var before: int = int(ship.stock.oxygen)
        reconnect.rpc_id(id)
        check(await wait_for(func(): return main.players.size() == 1), "客户端离线未清理")
        check(ship.stock.oxygen == before + 1 and ship.stock_oxygen_level() < 31.1, "离线未归库装备瓶及其余量")
        check(await wait_for(func(): return phase == 2), "客户端重连检查超时")
        id = int(main.connected_ids[1])
        stop.rpc_id(id)
        check(await wait_for(func(): return main.players.size() == 1), "客户端退出未清理")
        main._show_home()
        finish()

func _initialize() -> void:
    var probe: Probe = Probe.new()
    root.add_child(probe)
    probe.run.call_deferred()
