extends SceneTree

## 星币经济与星际集市：购买、余额不足、装备、换肤。

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func run() -> void:
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 27010 + int(Time.get_ticks_msec() % 60)
    main._create_host()
    main.connected_ids = [1]
    main.spawn_player_for_peer(1)
    await process_frame
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D

    # 1. 默认皮肤
    check(main.skin_for(1) == "ranger", "默认皮肤不是 ranger")
    check(main.owned_skins.has("ranger"), "默认皮肤没有进入已拥有列表")
    check(player._visual != null and player._visual.skin_id == "ranger", "角色没有加载默认皮肤")

    # 2. 余额不足买不了
    main.credits = 0
    main.purchase_or_equip("gala")
    check(not main.owned_skins.has("gala"), "余额不足却买到了皮肤")
    check(main.credits == 0, "购买的失败分支扣了钱")

    # 3. 赚星币 → 购买成功并自动装备
    main.credits = 2000
    main.purchase_or_equip("gala")
    check(main.owned_skins.has("gala"), "星币充足却没有买到皮肤")
    check(main.credits == 800, "购买没有正确扣费：%d" % main.credits)
    check(main.skin_for(1) == "gala", "购买后没有自动装备")
    await process_frame
    check(player._visual != null and player._visual.skin_id == "gala", "角色模型没有切换到新皮肤")

    # 4. 重复购买不重复扣费
    main.purchase_or_equip("gala")
    check(main.credits == 800, "已拥有的皮肤被重复扣费：%d" % main.credits)

    # 5. 换回默认皮肤
    main.equip_skin(1, "ranger")
    await process_frame
    check(main.skin_for(1) == "ranger", "装备切换失败")
    check(player._visual.skin_id == "ranger", "模型没有换回默认皮肤")

    # 6. 沙雕皮肤价格与购买
    main.purchase_or_equip("duck")
    check(main.owned_skins.has("duck"), "没有买到沙雕皮肤")
    check(main.credits == 200, "沙雕皮肤扣费不对：%d" % main.credits)

    # 7. 快照包含经济与皮肤
    var snapshot: Dictionary = main._world_snapshot()
    check(snapshot.has("credits"), "快照缺少星币")
    check(snapshot.has("player_skins"), "快照缺少玩家皮肤")
    check(int(snapshot.get("credits", -1)) == 200, "快照星币不一致")

    # 8. 集市面板
    main.open_market()
    check(main.market_visible, "集市没有打开")
    check(main.market_label != null and main.market_label.text.contains("星际集市"), "集市面板没有内容")
    main.market_move(1)
    check(main.market_selection == 1, "集市选择没有移动")
    main.close_market()
    check(not main.market_visible, "集市没有关闭")

    print("MARKET_TEST: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
