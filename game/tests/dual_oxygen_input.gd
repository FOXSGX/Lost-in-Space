extends "res://tests/inventory_input.gd"

func run() -> void:
    output = ProjectSettings.globalize_path("res://").path_join("../work/dual-oxygen-20261023/previews").simplify_path()
    DirAccess.make_dir_recursive_absolute(output)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    var guard: ReplayInputGuard = ReplayInputGuard.new()
    root.add_child(guard)
    main.network_port = 28436
    main._ship_session.persistence_enabled = false
    main._create_host()
    await frames(10)
    var items: CrewItems3D = main._items
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    await stand(Vector3(0, 0, 5))
    items.add_item(1, "oxygen")
    items.add_item(1, "oxygen")
    await mouse(MOUSE_BUTTON_LEFT)
    await key(KEY_2)
    await mouse(MOUSE_BUTTON_LEFT)
    check(items.oxygen_count(1) == 2 and items.occupied(1) == 0, "双瓶不能同时装入两个装备位")
    check(is_equal_approx(items.jet_duration(1), 1.0), "双瓶容量不是单瓶的两倍")
    await frames(95)
    check(items.jet_reserve(1) > 0.99, "双瓶不能充满")
    check(absf(items.tank_oxygen(1, 0) - 98.0) < 0.1 and absf(items.tank_oxygen(1, 1) - 98.0) < 0.1, "双倍充气没有分别扣除两瓶氧气")
    check(items._equipment_levels[0].text == "98%" and items._equipment_levels[1].text == "98%", "双瓶 HUD 余量未分别显示")
    check(items._equipment_jets[0].visible and items._equipment_jets[1].visible, "两个装备格没有各自显示喷气条")
    await shot("01-two-full-bottles")
    var before: Array = items.real_oxygen_levels(1)
    var flight_trace: Dictionary = {"active_frames": 0}
    var sample_flight: Callable = func() -> void:
        if player.jet_active:
            flight_trace.active_frames = int(flight_trace.active_frames) + 1
    physics_frame.connect(sample_flight)
    Input.action_press("jump")
    var active_frames: int = 0
    var observed_first: bool = false
    var observed_second: bool = false
    for index: int in 140:
        await frames(1)
        if player.jet_active:
            active_frames = int(flight_trace.active_frames)
            var first: float = float(items.ensure_bag(1).equipment[0].jet_reserve)
            var second: float = float(items.ensure_bag(1).equipment[1].jet_reserve)
            if active_frames >= 15 and not observed_first:
                check(first < 0.6 and second > 0.999, "第一条未耗完时第二条提前消耗")
                observed_first = true
                root.get_texture().get_image().save_png(output.path_join("04-first-bottle-draining.png"))
            if active_frames >= 40 and not observed_second:
                check(first == 0.0 and second > 0.0 and second < 0.8, "第一条耗尽后没有切换第二条")
                observed_second = true
                root.get_texture().get_image().save_png(output.path_join("05-second-bottle-draining.png"))
    Input.action_release("jump")
    physics_frame.disconnect(sample_flight)
    active_frames = int(flight_trace.active_frames)
    check(observed_first and observed_second and active_frames >= 57 and active_frames <= 62, "双瓶满条真实喷气时间不是约 1 秒: %d" % active_frames)
    check(items.jet_reserve(1) < 0.001 and not player.jet_active, "双瓶可以无限喷气")
    check(items.real_oxygen_levels(1) == before, "喷气期间错误地自动充气")
    var refill_deadline: int = Time.get_ticks_msec() + 5000
    while items.jet_reserve(1) < 0.2 and Time.get_ticks_msec() < refill_deadline:
        await frames(1)
    var recovering: Dictionary = items.ensure_bag(1)
    check(float(recovering.equipment[0].jet_reserve) > 0.0 and absf(float(recovering.equipment[0].jet_reserve) - float(recovering.equipment[1].jet_reserve)) < 0.001, "落地后两条没有同时恢复")
    await shot("06-both-bottles-refilling")
    await frames(100)
    # Different remaining oxygen must survive drop, pickup, training and snapshots.
    items.add_item(1, "oxygen", -1, {"oxygen": 17.0})
    await key(KEY_1)
    await mouse(MOUSE_BUTTON_LEFT)
    check(items.oxygen_count(1) == 2 and absf(items.tank_oxygen(1, 1) - 17.0) < 0.1, "满装备栏换瓶替换了错误格位")
    check(items.selected(1).get("kind", "") == "oxygen", "换瓶吞掉旧瓶")
    var bag: Dictionary = items.ensure_bag(1)
    var stale: Dictionary = items.snapshot()
    var serial: int = int(bag.tank_serial)
    items.sync_jet_resources([[1, serial, int(bag.jet_revision) + 1, 42.0, 0.5, 0.0, [42.0, 13.0]]])
    items.apply_state(stale)
    check(is_equal_approx(items.tank_oxygen(1, 0), 42.0) and is_equal_approx(items.tank_oxygen(1, 1), 13.0), "旧快照覆盖了更新的双瓶余量")
    check(is_equal_approx(items.jet_reserve(1), 0.5), "旧快照覆盖双倍储备")
    await key(KEY_TAB)
    await key(KEY_G)
    check(items.oxygen_count(1) == 1 and items.has_jet(1) and is_equal_approx(items.jet_duration(1), 0.5), "卸下一瓶误关另一瓶或未恢复单瓶容量")
    check(items.drops.size() == 1 and is_equal_approx(float(items.drops[0].oxygen), 13.0), "卸下第二瓶丢失独立余量")
    check(is_equal_approx(items.jet_reserve(1), 0.5), "卸下一瓶凭空增加充气百分比")
    await frames(85)
    await shot("02-one-bottle-dropped")
    await key(KEY_E)
    check(not bool(items.ensure_bag(1).equipment_active), "拾回第二瓶没有切回手持栏")
    await key(KEY_2)
    var units: float = items.jet_reserve(1)
    await mouse(MOUSE_BUTTON_LEFT)
    check(items.oxygen_count(1) == 2 and absf(items.tank_oxygen(1, 1) - 13.0) < 0.1, "拾回第二瓶没有保留余量")
    check(items.jet_reserve(1) < (units + 0.5) * 0.5 + 0.11, "重新装瓶没有保留原有独立充气量")
    var saved_levels: Array = items.real_oxygen_levels(1)
    check(items.real_counts(1).oxygen == 3 and saved_levels.size() == 3, "归库或保存少算了第二瓶")
    var ship: ShipSession3D = main._ship_session
    var original_save_path: String = ship.save_path
    ship.save_path = "user://dual-oxygen-test.json"
    ship.persistence_enabled = true
    ship.save_state()
    var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ship.save_path))
    check(int(saved.stock.oxygen) == int(ship.stock.oxygen) + 3 and saved.oxygen_levels.any(func(value: Variant) -> bool: return absf(float(value) - 13.0) < 0.1), "存档没有保存两瓶装备与手中旧瓶")
    ship.persistence_enabled = false
    DirAccess.remove_absolute(ship.save_path)
    ship.save_path = original_save_path
    items.start_training(1)
    check(items.oxygen_count(1) == 0, "训练没有隔离正式双瓶")
    items.finish_training(1)
    check(items.oxygen_count(1) == 2 and items.real_oxygen_levels(1) == saved_levels, "训练往返丢失双瓶余量")
    # One empty bottle still allows the other to supply the combined reservoir.
    bag = items.ensure_bag(1)
    bag.equipment[0].oxygen = 0.0
    bag.equipment[1].oxygen = 0.3
    bag.jet_reserve = 0.0
    bag.equipment[0].jet_reserve = 0.0
    bag.equipment[1].jet_reserve = 0.0
    bag.jet_idle = 0.0
    player.jet_charge = 0.0
    await frames(130)
    check(items.jet_reserve(1) > 0.07 and items.jet_reserve(1) <= 0.076, "空瓶阻断另一瓶供气或余量不足仍免费充满")
    check(items.tank_oxygen(1, 0) == 0.0 and items.tank_oxygen(1, 1) < 0.001, "双瓶耗氧计算错误")
    items.refill_oxygen(1)
    check(items.tank_oxygen(1, 0) == 100.0 and items.tank_oxygen(1, 1) == 100.0 and items.jet_reserve(1) < 0.076, "补给没有补满两瓶或免费充满喷气条")
    await frames(100)
    await shot("03-dual-restored")
    # All equippable items use the same empty / same-kind / full priority.
    bag.equipment = [{"kind": "thermal_suit", "tag": "old"}, {}]
    bag.slots = [{"kind": "thermal_suit", "tag": "new"}, {}]
    bag.selected = 0
    check(items.equip_gear(1, "thermal_suit", true) and bag.equipment[0].get("tag", "") == "old" and bag.equipment[1].get("tag", "") == "new" and bag.slots[0].is_empty(), "有空位仍替换同类装备")
    bag = items.ensure_bag(1)
    bag.slots[0] = {"kind": "thermal_suit", "tag": "replacement"}
    check(items.equip_gear(1, "thermal_suit", true) and bag.equipment[1].get("tag", "") == "replacement" and bag.slots[0].get("tag", "") == "new", "满栏同类替换未保留旧装备")
    bag = items.ensure_bag(1)
    bag.slots[0] = {"kind": "oxygen", "oxygen": 21.0}
    main.handle_action(1, "item_use")
    check(items.oxygen_count(1) == 0 and bag.slots[0].get("kind", "") == "oxygen", "满栏无同类仍挤掉其他装备")
    check(main._ship_session._notice.begins_with("装备栏已满"), "无空位且无同类没有提示装备栏已满")
    print("DUAL_OXYGEN_INPUT: " + JSON.stringify({"checks": checks, "failures": failures, "active_seconds": active_frames / 60.0}))
    main._show_home()
    main.queue_free()
    await frames()
    quit(0 if failures.is_empty() else 1)
