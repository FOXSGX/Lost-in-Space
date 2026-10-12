extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
    call_deferred("run_check")

func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures.append(message)

func run_check() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    var ship := main._ship_session
    ship.persistence_enabled = false
    main.network_port = 24568
    main._create_host()
    await physics_frame
    check(main.ship_active and main.players.has(1) and ship.in_hub, "主机未进入主舱")
    check(ship.room.get_node_or_null("ShipHubModel") != null, "舱室模型未加载")
    var player := main.players[1] as SpacePlayer3D
    check(player.get_node_or_null("ProtagonistVisual") != null, "角色模型未接入")
    check(player._camera.projection == Camera3D.PROJECTION_ORTHOGONAL and player._camera.size < 20, "舱内镜头错误")
    check(not player._camera.is_position_in_frustum(ShipHub3D.COCKPIT + Vector3.UP), "整舱不应在出生镜头中全部可见")
    var start_camera_x := player._camera.global_position.x
    var start_x := player.position.x
    Input.action_press("move_right")
    for frame in 8:
        await physics_frame
    Input.action_release("move_right")
    check(player.position.x > start_x, "舱内移动未生效")
    check(player._camera.global_position.x > start_camera_x, "主舱镜头未跟随角色移动")
    var space := main.get_world_3d().direct_space_state
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.5
    var shape_query := PhysicsShapeQueryParameters3D.new()
    shape_query.shape = capsule
    shape_query.collision_mask = 2
    var visited := {}
    var spawn := ship.spawn_position(1)
    var pending: Array[Vector2i] = [Vector2i(roundi(spawn.x / 0.4), roundi(spawn.z / 0.4))]
    visited[pending[0]] = true
    var reached: Array[Vector3] = []
    while not pending.is_empty():
        var grid := pending.pop_front() as Vector2i
        var point := Vector3(grid.x * 0.4, 0.8, grid.y * 0.4)
        reached.append(point)
        for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
            var next: Vector2i = grid + offset
            if visited.has(next) or abs(next.x) > 49 or abs(next.y) > 38:
                continue
            visited[next] = true
            shape_query.transform = Transform3D(Basis.IDENTITY, Vector3(next.x * 0.4, 0.8, next.y * 0.4))
            if space.intersect_shape(shape_query, 1).is_empty():
                pending.append(next)
    for anchor in [ShipHub3D.STORAGE, ShipHub3D.REPAIR, ShipHub3D.SUPPLY, ShipHub3D.COCKPIT, ShipHub3D.MISSION, ShipHub3D.AIRLOCK]:
        var accessible := false
        for point in reached:
            if Vector2(point.x, point.z).distance_to(Vector2(anchor.x, anchor.z)) < 0.7:
                accessible = true
                break
        check(accessible, "设施无法从入口步行到达：" + str(anchor))
    var query := PhysicsRayQueryParameters3D.create(ShipHub3D.STORAGE + Vector3(0, 0.5, 0), ShipHub3D.STORAGE + Vector3(-4, 0.5, 0), 2)
    check(not space.intersect_ray(query).is_empty(), "储物架缺少碰撞")
    player.teleport_to(Vector3(2.3, 0, 0))
    player.move_and_collide(Vector3(-3, 0, 0))
    check(player.position.x > 1.7, "星图碰撞失效")
    ship.request("take", "medical")
    check(int(ship.packs[1].medical) == 0, "远离储物架时不应允许领取")
    player.teleport_to(ShipHub3D.STORAGE)
    ship.request("interact")
    check(ship._facility == "storage" and ship.has_panel(), "储物界面未打开")
    var inventory_before := int(ship.stock.medical)
    ship.request("take", "medical")
    ship.request("take", "medical")
    ship.request("take", "medical")
    check(int(ship.packs[1].medical) == 2 and int(ship.stock.medical) == inventory_before - 2, "领取上限或共享库存错误")
    ship.request("store", "medical")
    check(int(ship.packs[1].medical) == 1 and int(ship.stock.medical) == inventory_before - 1, "存回物资不守恒")
    ship.request("take", "oxygen")
    ship.close_panel()
    player.teleport_to(ShipHub3D.REPAIR)
    ship.request("interact")
    var parts_before := int(ship.stock.parts)
    ship.request("repair")
    check(ship.hull == 100 and int(ship.stock.parts) == parts_before - 1, "维修未消耗零件或恢复舰体")
    ship.request("repair")
    check(int(ship.stock.parts) == parts_before - 1, "满舰体重复维修消耗了零件")
    ship.hull = 40
    ship.request("ready")
    main._confirm_land()
    check(not main.game_started, "舰体过低时不应允许起飞")
    ship.request("ready")
    ship.hull = 100
    ship.close_panel()
    player.teleport_to(ShipHub3D.SUPPLY)
    player.health = 2
    player.oxygen = 20
    player.warmth = 0.3
    ship.request("interact")
    ship.request("refill")
    check(player.health == 5 and player.oxygen == 100 and player.warmth == 1, "补给未恢复生存状态")
    ship.credits = 20
    var oxygen_before := int(ship.stock.oxygen)
    ship.request("craft", "oxygen")
    check(ship.credits == 15 and int(ship.stock.oxygen) == oxygen_before + 1, "制作未扣除点数或增加库存")
    ship.close_panel()
    player.teleport_to(ShipHub3D.MISSION)
    ship.request("interact")
    check(ship._facility == "mission", "任务终端未接入")
    ship.close_panel()
    player.teleport_to(ShipHub3D.COCKPIT)
    ship.request("interact")
    check(main._screen_view == "route", "驾驶台未打开航线图")
    main._confirm_land()
    check(not main.game_started, "未准备时不应允许起飞")
    ship.request("ready")
    main._confirm_land()
    await physics_frame
    check(main.game_started and not main.ship_active, "航线未连接霜烬星")
    player = main.players[1] as SpacePlayer3D
    player.health = 2
    player.oxygen = 15
    ship.request("use_medical")
    ship.request("use_oxygen")
    check(player.health == 4 and int(ship.packs[1].medical) == 0, "星球医疗包未消费或恢复生命")
    check(player.oxygen >= 59 and int(ship.packs[1].oxygen) == 0, "星球氧气瓶未消费或恢复氧气")
    main.salvage_value = 30
    main.mission_completed = true
    main.return_to_ship("测试远征：回收 30")
    await physics_frame
    check(main.ship_active and ship.in_hub and main.players.has(1), "返航未进入主舱")
    check(ship.credits == 45 and ship.hull == 92 and ship.ready_peers.is_empty(), "返航结算或准备状态重置错误")
    check(ship.last_report.contains("回收 30"), "任务记录未更新")
    player = main.players[1] as SpacePlayer3D
    check(player.health == 4, "返航丢失宇航员状态")
    main.sync_vitals([[1, 1, 1.0, 0.1, 0, true]])
    check(player.health == 4 and not player.downed, "延迟的星球状态覆盖了返航状态")
    player.teleport_to(ShipHub3D.AIRLOCK)
    ship.request("interact")
    await physics_frame
    check(not ship.in_hub and ship.room is ShipTutorial3D, "气闸未进入训练舱")
    player.teleport_to(Vector3(8.1, 0, 5.1))
    ship.request("interact")
    await physics_frame
    check(ship.in_hub, "无法从训练舱回到主舱")
    ship.save_path = "user://ship-cabin-integration-test.json"
    ship.persistence_enabled = true
    ship.save_state()
    var saved_medical := int(ship.stock.medical)
    ship.stock.medical = 0
    ship.load_state()
    check(ship.stock.medical == saved_medical and ship.credits == 45, "物资存档读取错误")
    DirAccess.remove_absolute(ship.save_path)
    ship.persistence_enabled = false
    main._show_home()
    check(not main.ship_active and main.players.is_empty() and main._screen_view == "home", "返回主界面未清理船舱")
    if failures.is_empty():
        print("SHIP_HUB_INTEGRATION_OK: %d checks" % checks)
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        quit(1)
