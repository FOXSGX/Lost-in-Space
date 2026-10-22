extends SceneTree

var checks: int = 0
var failures: Array[String] = []
var main: Main3D

func _initialize() -> void:
    run.call_deferred()

func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures.append(message)
        push_error(message)

func settle_frames(count: int = 8) -> void:
    for frame: int in count:
        await physics_frame
        await process_frame

func stand(player: SpacePlayer3D, point: Vector3, yaw: float = 0.0) -> void:
    player.teleport_to(point)
    player._camera_yaw_target = yaw
    player._camera_yaw = yaw
    player.rotation.y = yaw
    await settle_frames()

func run() -> void:
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main.network_port = 28216
    main._ship_session.persistence_enabled = false
    main._create_host()
    await settle_frames()
    var ship: ShipSession3D = main._ship_session
    var items: CrewItems3D = main._items
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    check(items.ensure_bag(1).slots.size() == 2 and items.occupied(1) == 0, "新背包必须是两个空格")
    await stand(player, ShipHub3D.STORAGE, PI / 2.0)
    ship.request("take", "medical")
    ship.request("take", "oxygen")
    check(items.occupied(1) == 2 and items.count_kind(1, "medical") == 1 and items.count_kind(1, "oxygen") == 1, "两格混合携带失败")
    var before: int = int(ship.stock.medical)
    ship.request("take", "medical")
    check(int(ship.stock.medical) == before and items.occupied(1) == 2, "满格领取扣库存或替换了物品")
    main.handle_action(1, "slot_1")
    main.handle_action(1, "item_use")
    check(items.count_kind(1, "medical") == 1, "满生命使用医疗包不应消耗")
    player.health = 3
    main.handle_action(1, "item_use")
    check(player.health == 5 and items.count_kind(1, "medical") == 0, "当前格使用医疗包没有恢复生命或清格")
    ship.request("take", "medical")
    main.handle_action(1, "slot_2")
    var oxygen_count: int = items.count_kind(1, "oxygen")
    main.handle_action(1, "item_use")
    check(oxygen_count == 1 and items.count_kind(1, "oxygen") == 0 and items.has_jet(1), "满氧时也应安装设备并释放格位")
    main.handle_action(1, "item_drop")
    check(items.occupied(1) == 1 and items.drops.size() == 1, "放下物品没有生成世界实体或清格")
    var dropped: Dictionary = items.nearby_item(1)
    check(dropped.get("kind", "") == "oxygen", "放下后未能找到眼前物品")
    main.handle_action(1, "interact")
    check(items.occupied(1) == 2 and items.drops.is_empty(), "E 再次拾取没有回收同一实体")
    check(items.count_kind(1, "oxygen") + int(ship.stock.oxygen) == 8, "拾取/放下破坏补给数量守恒")
    var real_bag: Dictionary = items.ensure_bag(1).duplicate(true)
    player.health = 4
    ship.switch_area(false)
    await settle_frames()
    check(player.position.distance_to(ShipTutorial3D.ENTRY_POINT) < 1.8 and player.is_on_floor(), "进入训练舱没有落在门内可站立位置")
    check((-player.global_transform.basis.z).dot(Vector3(-1, 0, -1).normalized()) > 0.95, "进入训练舱未面向室内")
    check(items.occupied(1) == 0 and player.health == 5, "练习未隔离背包与模拟损伤")
    check(items.real_counts(1).medical == 1 and items.real_counts(1).oxygen == 1, "练习状态覆盖了正式携带物")
    check(int(ship.training.get(1, 0)) == 0, "移动不应代替真实练习")
    main.handle_action(1, "item_scan")
    check(int(ship.training[1]) == 0, "扫描不应跳过推进练习")
    await stand(player, Vector3(-7, 0, 5.2))
    var oxygen_prop: Dictionary = items.nearby_item(1).duplicate(true)
    main.handle_action(1, "interact")
    check(items.count_kind(1, "oxygen") == 1 and int(ship.training[1]) == 1, "练习氧气瓶无法领取")
    check(not items.pickup(1, oxygen_prop) and items.count_kind(1, "oxygen") == 1, "旧领取请求复制了练习氧气瓶")
    main.handle_action(1, "item_use")
    check(items.has_jet(1) and items.occupied(1) == 0 and int(ship.training[1]) == 2, "真实安装没有启动跳跃练习")
    main.handle_action(1, "item_drop")
    check(not items.has_jet(1) and items.drops.size() == 1, "卸下练习设备未生成唯一丢落物")
    await settle_frames(10)
    main.handle_action(1, "interact")
    check(items.count_kind(1, "oxygen") == 1 and items.drops.is_empty(), "放下再拿取复制了练习氧气瓶")
    main.handle_action(1, "item_use")
    await stand(player, ShipTutorial3D.BOOST_POINT)
    check(int(ship.training[1]) == 2, "越过低台不能直接完成高台步骤")
    await stand(player, ShipTutorial3D.HOP_POINT)
    check(int(ship.training[1]) == 3, "实际低台落地未推进")
    await stand(player, ShipTutorial3D.BOOST_POINT)
    check(int(ship.training[1]) == 4, "实际高台落地未推进")
    await stand(player, ShipTutorial3D.FINISH_POINT + Vector3.UP * 0.5)
    check(int(ship.training[1]) == 4, "悬空接近终点不应完成练习")
    await stand(player, ShipTutorial3D.FINISH_POINT)
    check(int(ship.training[1]) == 5, "终点落地未完成练习")
    ship.switch_area(true)
    await settle_frames()
    check(player.position.distance_to(ShipHub3D.AIRLOCK) < 1.8 and player.is_on_floor(), "离开训练舱未回到主舱气闸内侧")
    check((-player.global_transform.basis.z).dot(Vector3.FORWARD) > 0.99, "返回主舱未面向舱内")
    check(items.ensure_bag(1) == real_bag and player.health == 4, "训练结束没有恢复原背包、选择和生命")
    check(int(ship.stock.medical) == 6 and int(ship.stock.oxygen) == 7, "练习消耗混入正式库存")
    ship.switch_area(false)
    await settle_frames()
    check(player.position.distance_to(ShipTutorial3D.ENTRY_POINT) < 1.8 and (items.training_saved[1].claimed as Array).is_empty(), "重新进入训练的位置或补给记录错误")
    await stand(player, Vector3(-7, 0, 5.2))
    main.handle_action(1, "interact")
    ship.switch_area(true)
    await settle_frames()
    check(items.ensure_bag(1) == real_bag and items.training_saved.is_empty(), "提前离开训练泄露了练习物品")
    await stand(player, Vector3(0, 0, 6.0))
    var floor_y: float = player.position.y
    Input.action_press("jump")
    await settle_frames(3)
    Input.action_release("jump")
    check(player.position.y > floor_y + 0.08, "空格没有起跳")
    var up_speed: float = player.velocity.y
    Input.action_press("jump")
    await settle_frames(2)
    Input.action_release("jump")
    check(player.velocity.y < up_speed, "空中再次按空格重新起跳了")
    await settle_frames(65)
    check(absf(player.position.y - floor_y) < 0.04 and player.is_on_floor(), "跳跃未正常落地")
    main._open_settings()
    Input.action_press("jump")
    await settle_frames(3)
    Input.action_release("jump")
    check(absf(player.position.y - floor_y) < 0.04, "设置界面内触发了跳跃")
    main._close_settings()
    ship.save_path = "user://inventory-training-test.json"
    ship.persistence_enabled = true
    ship.save_state()
    ship.load_state()
    check(ship.stock.medical == 7 and ship.stock.oxygen == 8 and items.bags.is_empty(), "正式背包回库/旧存档格式读取失败")
    DirAccess.remove_absolute(ship.save_path)
    ship.persistence_enabled = false
    player = main.players[1] as SpacePlayer3D
    await stand(player, ShipHub3D.STORAGE)
    ship.request("take", "medical")
    await stand(player, Vector3(ShipDevices3D.PILOT_X[0], 0, -12.2))
    ship.request("ready")
    main._confirm_land()
    await settle_frames(5)
    player = main.players[1] as SpacePlayer3D
    player.teleport_to((main.crates[1] as Node3D).position)
    main.handle_action(1, "pickup")
    check(items.occupied(1) == 2 and items.count_kind(1, "battery") == 1, "补给和任务电池没有共用两格容量")
    player.teleport_to((main.samples[1] as Node3D).position)
    main.handle_action(1, "pickup")
    check(items.occupied(1) == 2 and not main.taken_samples.has(1), "满背包仍可拿取星球样本")
    player.health = 3
    main.handle_action(1, "slot_1")
    main.handle_action(1, "item_use")
    main.handle_action(1, "pickup")
    check(items.occupied(1) == 2 and items.count_kind(1, "sample") == 1, "腾出一格后没有成功收纳样本")
    main.handle_action(1, "item_drop")
    check(items.occupied(1) == 1 and not main.taken_samples.has(1) and (main.samples[1] as Node3D).visible, "放下样本未同时更新实体与物品格")
    player.teleport_to((main.samples[1] as Node3D).position)
    main.handle_action(1, "pickup")
    check(items.occupied(1) == 2 and main.taken_samples.has(1), "放下后再次拾取复制或丢失了样本")
    player.teleport_to(Vector3(main.EXTRACTION.x, 0, main.EXTRACTION.y))
    main.handle_action(1, "deposit")
    main.handle_action(1, "deposit")
    check(items.occupied(1) == 0 and main.salvage_value == main.SAMPLE_VALUE + main.BATTERY_VALUE, "两件任务货物的投送清格或结算错误")
    await stand(player, Vector3(main.EXTRACTION.x, 0, main.EXTRACTION.y))
    await settle_frames(15)
    var planet_floor: float = player.position.y
    Input.action_press("jump")
    await settle_frames(3)
    Input.action_release("jump")
    check(player.position.y > planet_floor + 0.08, "星球内空格不能起跳")
    await settle_frames(65)
    check(player.is_on_floor() and absf(player.position.y - planet_floor) < 0.05, "星球跳跃没有落地")
    player.teleport_to((main.crates[2] as Node3D).position)
    main.handle_action(1, "pickup")
    player.teleport_to((main.samples[2] as Node3D).position)
    main.handle_action(1, "pickup")
    check(items.cargo_entries(1).size() == 2, "失败散落测试没有收纳两件货物")
    main.mission_failed = true
    main.return_to_ship("两格货物失败散落测试")
    check(items.cargo_entries(1).is_empty() and ship.planet_state(main.PLANET_ID).get("lost_cargo", []).size() >= 2, "失败返航遗漏第二格货物或保留了失效引用")
    main._show_home()
    main.queue_free()
    await process_frame
    print("INVENTORY_TRAINING: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
