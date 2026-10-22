extends SceneTree

var main: Main3D
var player: SpacePlayer3D
var items: CrewItems3D
var checks: int = 0
var failures: Array[String] = []
var output: String = ProjectSettings.globalize_path("res://").path_join("../work/oxygen-reserves-20261022").simplify_path()

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func frames(count: int) -> void:
    for index: int in count:
        await physics_frame
        await process_frame

func wait_charge() -> void:
    var deadline: int = Time.get_ticks_msec() + 6000
    while player.jet_charge < 0.995 and Time.get_ticks_msec() < deadline:
        await frames(1)
    check(player.jet_charge > 0.99, "等待后无法充满喷气储备")

func shot(title: String) -> void:
    if DisplayServer.get_name() == "headless":
        return
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output.path_join(title + ".png"))

func run() -> void:
    DirAccess.make_dir_recursive_absolute(output)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main.network_port = 28435
    main._ship_session.persistence_enabled = false
    main._create_host()
    await frames(8)
    player = main.players[1] as SpacePlayer3D
    items = main._items
    player.teleport_to(Vector3(0, 0, 5))
    items.add_item(1, "oxygen")
    main.handle_action(1, "item_use")
    check(items.has_jet(1) and player.jet_charge == 0.0, "安装凭空赠送喷气储备")
    await frames(10)
    check(player.jet_charge == 0.0 and items.tank_oxygen(1) == 100.0, "未等待就开始充气")
    await wait_charge()
    check(absf(items.tank_oxygen(1) - 98.0) < 0.15, "充满一条喷气储备没有消耗约2%氧气")
    check(items._equipment_icon.visible and not items._equipment_percent.text.is_empty() and items._jet_bar.get_parent() == items._equipment_panel, "装备格中的氧气瓶或喷气条没有正确显示")
    await shot("01-two-reserves-ready")
    var before: float = items.tank_oxygen(1)
    Input.action_press("jump")
    var active_frames: int = 0
    var highest: float = -100.0
    for index: int in 130:
        await frames(1)
        if player.jet_active:
            active_frames += 1
        highest = maxf(highest, player.position.y)
    check(active_frames >= 27 and active_frames <= 32, "基础喷气时间不是约0.5秒")
    check(player.jet_charge < 0.001 and not player.jet_active, "按住空格能无限续喷")
    check(absf(before - items.tank_oxygen(1)) < 0.01, "按住空格时发生了自动充气")
    check(highest < 3.3, "真实喷气穿过了中央舱顶")
    Input.action_release("jump")
    await frames(10)
    check(player.jet_charge == 0.0, "松开后没有等待就补满")
    await wait_charge()
    check(items.tank_oxygen(1) < before - 1.8, "第二次充气没有再次损耗瓶内氧气")
    var bag: Dictionary = items.ensure_bag(1)
    bag.jet_reserve = 0.0
    bag.jet_idle = 0.0
    player.jet_charge = 0.0
    player.teleport_to(Vector3(0, 2.7, 5))
    var airborne_oxygen: float = items.tank_oxygen(1)
    await frames(15)
    check(player.jet_charge == 0.0 and absf(items.tank_oxygen(1) - airborne_oxygen) < 0.01, "滞空状态能恢复喷气")
    await wait_charge()
    # Resolve against actual ceiling/side geometry, without horizontal walk clamps.
    for x: float in [-18, -12, -7, 0, 7, 12, 18]:
        for z: float in [-13, -7, 7, 13]:
            player.teleport_to(Vector3(x, 0.05, z))
            var collision: KinematicCollision3D = player.move_and_collide(Vector3.UP * 15.0)
            check(collision != null and player.position.y < 3.4, "舱顶存在可穿出区域: %s" % Vector2(x, z))
    for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
        player.teleport_to(Vector3(0, 0.15, 7))
        var collision: KinematicCollision3D = player.move_and_collide(direction * 60.0)
        check(collision != null and absf(player.position.x) < 20.5 and absf(player.position.z) < 16.5, "舱壁未阻挡角色")
    player.teleport_to(Vector3(0, 0, 5))
    await frames(10)
    await wait_charge()
    var reserve: float = items.jet_reserve(1)
    var old_oxygen: float = items.tank_oxygen(1)
    items.add_item(1, "oxygen", -1, {"oxygen": 17.0})
    main.handle_action(1, "item_use")
    check(absf(items.tank_oxygen(1) - 17.0) < 0.01 and absf(float(items.selected(1).get("oxygen", -1)) - old_oxygen) < 0.01, "换瓶没有保留新旧瓶内余量")
    check(absf(items.jet_reserve(1) - reserve) < 0.01, "换瓶免费重置喷气储备")
    main.handle_action(1, "slot_2")
    main.handle_action(1, "item_drop")
    await frames(140)
    check(items.drops.size() == 1 and absf(float(items.drops[0].oxygen) - 17.0) < 0.01, "卸下道具丢失氧气余量")
    main.handle_action(1, "interact")
    main.handle_action(1, "item_use")
    check(absf(items.tank_oxygen(1) - 17.0) < 0.01, "放下再拾取免费补满了氧气瓶")
    # Store/retrieve the other partial tank and round-trip the save file.
    player.teleport_to(ShipHub3D.STORAGE)
    var partial: float = float(items.ensure_bag(1).slots[0].get("oxygen", 0.0))
    main._ship_session.request("store", "oxygen")
    main._ship_session.request("take", "oxygen")
    check(absf(float(items.ensure_bag(1).slots[0].get("oxygen", -1.0)) - partial) < 0.01, "存回再领取免费补满氧气瓶")
    var ship: ShipSession3D = main._ship_session
    ship.save_path = "user://oxygen-reserves-test.json"
    ship.persistence_enabled = true
    ship.save_state()
    ship.load_state()
    check(ship.oxygen_levels.any(func(value: Variant) -> bool: return absf(float(value) - 17.0) < 0.001) and ship.oxygen_levels.any(func(value: Variant) -> bool: return absf(float(value) - partial) < 0.001), "存档没有保留部分氧气瓶余量")
    DirAccess.remove_absolute(ship.save_path)
    ship.persistence_enabled = false
    items.add_item(1, "oxygen", -1, {"oxygen": 0.3})
    main.handle_action(1, "item_use")
    await frames(240)
    check(items.tank_oxygen(1) == 0.0 and items.jet_reserve(1) <= 0.151, "氧气不足时免费充满了喷气条")
    check(items.has_jet(1), "空瓶被自动销毁")
    await shot("02-empty-tank")
    player.teleport_to(ShipDevices3D.point_for("refill") + Vector3(0, 0, 1.2))
    player.rotation.y = 0.0
    main._ship_session.request("refill")
    check(items.tank_oxygen(1) == 100.0 and items.jet_reserve(1) < 0.16, "补给未补满氧气瓶或免费补满了喷气储备")
    await shot("03-refuelled-tank")
    print("OXYGEN_RESERVES_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "active_seconds": active_frames / 60.0, "highest_in_hub": highest}))
    main._show_home()
    main.queue_free()
    await frames(6)
    quit(0 if failures.is_empty() else 1)
