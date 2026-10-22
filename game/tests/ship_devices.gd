extends SceneTree

var main: Main3D
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func stand(id: String) -> void:
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var point: Vector3 = ShipDevices3D.point_for(id)
    point.y = 0
    point.z += 1.6 if id.begins_with("pilot_") else 1.3
    player.teleport_to(point)
    player._camera_yaw = 0.0
    player._camera_yaw_target = 0.0
    player.rotation.y = 0.0
    await physics_frame
    await physics_frame

func run() -> void:
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 28231
    main._create_host()
    await physics_frame
    var ship: ShipSession3D = main._ship_session
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var devices: ShipDevices3D = ship.device_room()
    check(devices != null and devices.screens.size() == 28, "实体设备或屏幕缺失")
    check(ship._layer.find_children("*", "BaseButton", true, false).is_empty(), "主舱仍依赖鼠标按钮")
    var count: int = 0
    for device: Dictionary in devices.devices:
        if device.kind == "pilot":
            count += 1
        await stand(device.id)
        check(devices.nearby(1).get("id", "") == device.id, "设备不能从正面操作：" + String(device.id))
    check(count == 4, "驾驶台不是四个")
    player.teleport_to(Vector3(0, 0, 6))
    ship.request("ready")
    check(ship.ready_peers.is_empty(), "能在远处就位")
    await stand("pilot_0")
    ship.hull = 40
    main.handle_action(1, "interact")
    check(ship.ready_peers.is_empty(), "低舰体允许就位")
    ship.hull = 80
    main.handle_action(1, "interact")
    check(ship.station_owners.get(0, 0) == 1 and ship.all_ready(), "实体驾驶台未就位")
    ship.tick(0.0)
    check(ship.launch_remaining > 0.0 and not main.game_started, "没有开始可取消的倒数")
    main.handle_action(1, "interact")
    check(ship.ready_peers.is_empty() and ship.launch_remaining < 0.0, "E 没有取消就位")
    main.handle_action(1, "interact")
    player.teleport_to(Vector3(0, 0, -7))
    ship.tick(0.0)
    check(ship.station_owners.is_empty(), "离开驾驶台仍保持就位")
    await stand("pilot_1")
    main.handle_action(1, "interact")
    await stand("route_electromagnetic")
    main.handle_action(1, "interact")
    check(ship.selected_destination == "electromagnetic" and ship.station_owners.is_empty(), "换航线未取消旧就位")
    await stand("route_demo")
    main.handle_action(1, "interact")
    ship.credits = 100
    await stand("craft_oxygen")
    var stock: int = int(ship.stock.oxygen)
    main.handle_action(1, "interact")
    check(ship.credits == 95 and ship.stock.oxygen == stock + 1, "实体制作机未按原费用入库")
    await stand("gear_thermal_suit")
    main.handle_action(1, "interact")
    check(ship.credits == 50 and ship.gear_assignments.get(1, "") == "thermal_suit", "实体集市未购买并装备")
    main.handle_action(1, "interact")
    check(ship.credits == 50, "已购装备重复扣费")
    await stand("refill")
    player.health = 2
    player.oxygen = 20.0
    main.handle_action(1, "interact")
    check(player.health == 5 and player.oxygen == 100.0 and not ship.has_panel(), "补给设备没有直接恢复")
    await stand("repair")
    var parts: int = int(ship.stock.parts)
    main.handle_action(1, "interact")
    check(ship.hull == 100 and ship.stock.parts == parts - 1 and not ship.has_panel(), "维修设备未直接执行")
    await stand("pilot_3")
    main.handle_action(1, "interact")
    ship.tick(0.0)
    ship.tick(3.1)
    check(main.game_started and not main.ship_active, "全部就位后没有自动登陆")
    main._show_home()
    main.queue_free()
    await process_frame
    print("SHIP_DEVICES: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
