extends "res://tests/inventory_input.gd"

func filled(hud: HealthHUD3D) -> int:
    var count: int = 0
    for cell: Panel in hud.cells:
        if (cell.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == HealthHUD3D.FILLED:
            count += 1
    return count

func run() -> void:
    output = ProjectSettings.globalize_path("res://").path_join("../work/health-layer1-20261023/previews").simplify_path()
    DirAccess.make_dir_recursive_absolute(output)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    var guard: ReplayInputGuard = ReplayInputGuard.new()
    root.add_child(guard)
    main.network_port = 28441
    main._ship_session.persistence_enabled = false
    main._create_host()
    await frames(10)
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var hud: HealthHUD3D = main._health_hud
    var ship: ShipSession3D = main._ship_session
    await stand(Vector3(0, 0, 5), 0.0, 0.08)
    check(player.health == 5 and not player.downed and hud.cells.size() == 5 and filled(hud) == 5, "初始生命不是绿色五格")
    check(hud.visible and hud.panel.position == Vector2(22, 18), "生命栏没有显示在左上角")
    check(ship._ship_title.text == "主舱" and ship._ship_panel.size == Vector2(112, 40), "主舱标题未简化")
    check(absf(ship._ship_panel.get_global_rect().get_center().x - root.get_visible_rect().size.x * 0.5) < 1.0, "主舱标签没有居中")
    await shot("01-health-5")
    # Exercise the actual enemy contact -> damage -> health -> HUD chain.
    var enemy: SpaceEnemy3D = SpaceEnemy3D.new()
    enemy.setup(991, 4)
    main.add_child(enemy)
    main.enemies[991] = enemy
    enemy.position = player.position + Vector3(0.0, 0.0, -0.9)
    for child: Node in enemy.get_children():
        if child is Label3D:
            (child as Label3D).visible = false
    check(enemy.attack_damage == 1, "四人模式普通攻击不是 1 点伤害")
    main.game_started = true
    var enemy_before: int = enemy.health
    await mouse(MOUSE_BUTTON_LEFT)
    check(enemy.health == enemy_before - 1, "存活时左键攻击本身无效，无法验证倒地拦截")
    enemy.visible = false
    var stale: Array = main._vitals_snapshot().duplicate(true)
    for remaining: int in [4, 3, 2, 1, 0]:
        enemy.attack_timer = 0.0
        enemy.server_tick(0.016, main.players, Vector3.ZERO, false, true)
        await frames(5)
        check(player.health == remaining and filled(hud) == remaining, "受击后血格不一致: %d" % remaining)
        check(player.downed == (remaining == 0), "倒地时机不正确: %d" % remaining)
        await shot("health-%d" % remaining)
    check(hud.downed_panel.visible and player.velocity == Vector3.ZERO and not player.jet_active, "倒地反馈或停止推进失败")
    check(not main.mission_failed, "主舱倒地误触远征失败")
    await frames(45)
    check(player._camera.global_position.y - player.global_position.y < 0.7, "倒地镜头没有降低")
    var origin: Vector3 = player.position
    enemy_before = enemy.health
    Input.action_press("move_up")
    Input.action_press("move_right")
    Input.action_press("sprint")
    Input.action_press("jump")
    Input.action_press("item_use")
    await frames(35)
    for action: String in ["move_up", "move_right", "sprint", "jump", "item_use"]:
        Input.action_release(action)
    main.attack_from_peer(1)
    main.handle_action(1, "item_use")
    main.damage_player(1, 1)
    check(player.position.distance_to(origin) < 0.001 and player.velocity == Vector3.ZERO, "倒地后仍能移动或跳跃")
    check(enemy.health == enemy_before and player.health == 0, "倒地后仍可攻击或重复扣到负数")
    main.sync_vitals(stale, true)
    check(player.health == 0 and player.downed and filled(hud) == 0, "旧生命快照让倒地玩家复活")
    await shot("07-downed")
    root.size = Vector2i(1920, 1080)
    await frames(6)
    check(root.get_visible_rect().encloses(hud.panel.get_global_rect()) and root.get_visible_rect().encloses(hud.downed_panel.get_global_rect()), "大分辨率生命 HUD 越界")
    check(absf(ship._ship_panel.get_global_rect().get_center().x - root.get_visible_rect().size.x * 0.5) < 1.0, "大分辨率主舱标签不居中")
    check(not hud.downed_panel.get_global_rect().intersects(main._items._bar.get_global_rect()), "倒地反馈遮挡物品栏")
    await shot("08-downed-1920")
    root.size = Vector2i(1280, 720)
    await key(KEY_ESCAPE)
    check(not hud.visible, "设置遮罩中残留生命 HUD")
    await key(KEY_ESCAPE)
    check(hud.visible, "关闭设置没有恢复生命 HUD")
    main.game_started = false
    main.enemies.erase(991)
    enemy.queue_free()
    player.health = 5
    player.downed = false
    main._vitals_snapshot()
    await frames(10)
    check(filled(hud) == 5 and not hud.downed_panel.visible, "恢复已有角色状态后生命 HUD 未更新")
    ship.switch_area(false)
    await frames(10)
    check(hud.visible and filled(hud) == 5 and ship._ship_title.text == "训练舱", "训练舱未共用生命 HUD")
    ship.switch_area(true)
    await frames(6)
    check(hud.visible and ship._ship_title.text == "主舱", "返回主舱位置标签错误")
    main.damage_player(1, 0)
    main.damage_player(1, -2)
    check(player.health == 5, "零伤害或负伤害修改了生命")
    player.shield_remaining = 1.0
    main.damage_player(1, 2)
    check(player.health == 4, "已有护盾减伤失效")
    player.health = 5
    main.start_planet("demo")
    await frames(8)
    player = main.players[1] as SpacePlayer3D
    check(hud.visible and filled(hud) == 5 and not ship._ship_panel.visible, "登陆后生命 HUD 或位置标签错误")
    check(not hud.panel.get_global_rect().intersects(main._objective_panel.get_global_rect()), "星球目标面板遮挡生命栏")
    for hit: int in 5:
        main.damage_player(1, 1)
    await frames(6)
    check(player.health == 0 and player.downed and filled(hud) == 0 and hud.downed_panel.visible, "星球内受伤到倒地的闭环失败")
    check(main.mission_failed, "全员倒地未保留已有返航规则")
    await shot("09-planet-downed")
    main._show_home()
    await frames(5)
    check(not hud.visible, "首页残留生命 HUD")
    print("HEALTH_LAYER1_INPUT: %d checks, %d failures" % [checks, failures.size()])
    main.queue_free()
    await frames()
    quit(0 if failures.is_empty() else 1)
