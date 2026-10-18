extends Node
class_name ShipSession3D

const HUB_SCENE := preload("res://scenes/ship_hub_3d.tscn")
const TRAINING_SCENE := preload("res://scenes/ship_tutorial_3d.tscn")
const ITEM_NAMES := {"medical": "医疗包", "oxygen": "氧气瓶", "parts": "维修零件"}
const ITEM_COSTS := {"medical": 10, "oxygen": 5, "parts": 10}
const TRAINING_STEPS := ["先在甲板上移动", "Q 扫描", "E 维修", "F 拾取", "G 投送", "空格 攻击", "R 救援", "训练完成，可返回主舱"]
const SAVE_PATH := "user://ship-cabin-save.json"
const GOOFY_ITEMS := ["penguin", "bubble", "board", "hologram", "smoke"]
const GEAR_ITEMS := ["thermal_suit", "wide_scanner", "signal_stabilizer"]
const GEAR_NAMES := {"thermal_suit": "恒温外套", "wide_scanner": "广域扫描器", "signal_stabilizer": "信号稳压器"}
const GEAR_COSTS := {"thermal_suit": 45, "wide_scanner": 55, "signal_stabilizer": 65}

var controller: Main3D
var active := false
var in_hub := true
var room: Node3D
var stock := {"medical": 8, "oxygen": 8, "parts": 6}
var packs: Dictionary = {}
var ready_peers: Array[int] = []
var selected_destination := "demo"
var training: Dictionary = {}
var hull := 80
var credits := 0
## 团队共享的欢乐道具箱。道具是可重复使用的，不在任务内扣除数量。
var goofy_stock: Dictionary = {"penguin": 1, "bubble": 1, "board": 1, "hologram": 1, "smoke": 1}
var goofy_assignments: Dictionary = {}
var gear_stock: Dictionary = {"thermal_suit": 0, "wide_scanner": 0, "signal_stabilizer": 0}
var gear_assignments: Dictionary = {}
## 每颗星球一份长期状态：主线发现、支线成就、自然演变资源都在这里保存。
var planet_states: Dictionary = {}
var last_report := "尚未进行远征。先检查舰体、领取补给，再到驾驶台选择航程。"
var persistence_enabled := true
var save_path := SAVE_PATH
var _layer: CanvasLayer
var _ship_panel: Panel
var _ship_title: Label
var _crew_label: Label
var _hint: Label
var _hint_panel: Panel
var _ready_button: Button
var _exit_button: Button
var _market_button: Button
var _panel: Panel
var _title: Label
var _body: Label
var _message: Label
var _actions: VBoxContainer
var _pack_label: Label
var _facility := ""
var _notice := ""
var _notice_remaining := 0.0
var _menu_environment: Environment
var _menu_light_energy: Dictionary = {}

func _ready() -> void:
    controller = get_parent() as Main3D
    for child in controller._menu_world.get_children():
        if child is WorldEnvironment:
            _menu_environment = child.environment
    for light in controller._menu_world.find_children("*", "Light3D", true, false):
        _menu_light_energy[light] = light.light_energy
    _build_ui()

func _build_ui() -> void:
    _layer = CanvasLayer.new()
    _layer.layer = 30
    _layer.visible = false
    add_child(_layer)
    var controls := Control.new()
    controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _layer.add_child(controls)
    _ship_panel = controller._panel(_layer, Vector2(22, 18), Vector2(420, 82), Color(0.12, 0.24, 0.29, 0.93), Color("#93c1be"), 18)
    _ship_title = controller._ui_label(_ship_panel, "归航号 · 船员主舱", Vector2(16, 10), Vector2(386, 28), 22, Color("#f4ebd6"))
    _crew_label = controller._ui_label(_ship_panel, "", Vector2(16, 46), Vector2(386, 26), 14, Color("#c8e1d6"))
    _ready_button = controller._ui_button(controls, "准备出发", Vector2(1090, 22), Vector2(164, 46), func(): request("ready"), true)
    _exit_button = controller._ui_button(controls, "退出房间", Vector2(1090, 78), Vector2(164, 36), controller._show_home)
    _market_button = controller._ui_button(controls, "星际集市", Vector2(900, 22), Vector2(164, 46), controller._show_trade, true)
    _hint_panel = controller._panel(_layer, Vector2(225, 634), Vector2(830, 62), Color(0.12, 0.24, 0.29, 0.94), Color("#93c1be"), 18)
    _hint = controller._ui_label(_hint_panel, "", Vector2(16, 8), Vector2(800, 48), 17, Color("#e6f9ff"))
    _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _panel = controller._panel(_layer, Vector2(335, 115), Vector2(610, 500), Color(0.95, 0.93, 0.86, 0.98), Color("#79aaa7"), 20)
    _panel.visible = false
    _title = controller._ui_label(_panel, "", Vector2(28, 22), Vector2(554, 42), 29, Color("#294d5b"))
    _body = controller._ui_label(_panel, "", Vector2(28, 80), Vector2(554, 100), 17, Color("#466b74"))
    _actions = VBoxContainer.new()
    _actions.position = Vector2(28, 193)
    _actions.size = Vector2(554, 224)
    _actions.add_theme_constant_override("separation", 8)
    _panel.add_child(_actions)
    _message = controller._ui_label(_panel, "", Vector2(28, 420), Vector2(300, 66), 15, Color("#a55e37"))
    controller._ui_button(_panel, "返回舱内  ·  Esc", Vector2(340, 451), Vector2(242, 36), close_panel)
    _pack_label = controller._ui_label(_layer, "", Vector2(24, 656), Vector2(430, 38), 15, Color("#bce5e7"))

func tick(delta: float) -> void:
    _notice_remaining = maxf(_notice_remaining - delta, 0.0)
    _layer.visible = active or controller.game_started
    _pack_label.visible = controller.game_started
    _ship_panel.visible = active and controller._screen_view == "ship"
    _ship_title.text = "归航号 · 船员主舱" if in_hub else "归航号 · 操作训练舱"
    _ready_button.visible = active and not _panel.visible and controller._screen_view == "ship"
    _exit_button.visible = _ready_button.visible
    _market_button.visible = active and in_hub and controller._screen_view == "ship"
    _hint_panel.visible = active and not _panel.visible and controller._screen_view == "ship"
    var peer_id := multiplayer.get_unique_id()
    var bag: Dictionary = packs.get(peer_id, {})
    _pack_label.text = "3 医疗包 ×%d   4 氧气瓶 ×%d" % [int(bag.get("medical", 0)), int(bag.get("oxygen", 0))]
    if not active:
        return
    _crew_label.text = "舰体 %d%%   船员 %d / 4   准备 %d / %d" % [hull, controller.connected_ids.size(), ready_peers.size(), controller.connected_ids.size()]
    _ready_button.text = "取消准备" if ready_peers.has(peer_id) else "准备出发"
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player != null:
        _hint.text = _notice if _notice_remaining > 0.0 and not _notice.is_empty() else interaction_hint(player.global_position)
    if controller.is_host and not in_hub:
        for id in controller.connected_ids:
            var trainee := controller.players.get(id) as SpacePlayer3D
            if trainee != null and int(training.get(id, 0)) == 0 and controller._flat_distance(trainee.position, spawn_position(id)) > 1.25:
                training[id] = 1
                broadcast()
    if controller._screen_view == "route":
        controller._land_button.disabled = not controller.is_host or not all_ready() or hull < 60
        if controller._electro_land_button != null:
            controller._electro_land_button.disabled = not controller.is_host or not all_ready() or hull < 60
        var selected_title := String(PlanetRegistry.info(selected_destination).get("title", selected_destination))
        controller._route_status.text = "已选%s · 准备 %d / %d · 舰体 %d%%（需 ≥60%%）" % [selected_title, ready_peers.size(), controller.connected_ids.size(), hull]
    elif controller._screen_view == "trade":
        controller._refresh_trade_buttons()

func interaction_hint(point: Vector3) -> String:
    if in_hub:
        var facility := nearby_facility(point)
        var names := {"route": "驾驶台 · 选择航程", "storage": "共享储物架", "repair": "舰体维修台", "supply": "补给柱", "mission": "任务记录", "airlock": "训练舱"}
        return "E %s   ·   WASD 移动" % names[facility] if not facility.is_empty() else "↑ 驾驶台 · ← 储物架 · → 维修/补给 · ↓ 训练舱\nWASD 移动 · 设施旁按 E"
    if controller._flat_distance(point, Vector3(8.1, 0, 5.1)) < 1.8:
        return "E 返回主舱"
    var step := clampi(int(training.get(multiplayer.get_unique_id(), 0)), 0, 7)
    return "训练 %d / 7：%s · 右下气闸 E 返回主舱" % [step, TRAINING_STEPS[step]]

func nearby_facility(point: Vector3) -> String:
    var positions := {"route": ShipHub3D.COCKPIT, "storage": ShipHub3D.STORAGE, "repair": ShipHub3D.REPAIR, "supply": ShipHub3D.SUPPLY, "mission": ShipHub3D.MISSION, "airlock": ShipHub3D.AIRLOCK}
    var nearest := ""
    var distance := 1.65
    for key in positions:
        var candidate := controller._flat_distance(point, positions[key])
        if candidate < distance:
            distance = candidate
            nearest = key
    return nearest

func spawn_position(peer_id: int) -> Vector3:
    return Vector3(-1.8 + float(controller.connected_ids.find(peer_id) % 4) * 1.2, 0, 3.6) if in_hub else Vector3(-8.5 + float(controller.connected_ids.find(peer_id) % 4) * 0.9, 0, 0.2)

func disable_menu_environment() -> void:
    controller._menu_world.visible = false
    for child in controller._menu_world.get_children():
        if child is WorldEnvironment:
            child.environment = null
    for light in _menu_light_energy:
        light.light_energy = 0.0

@rpc("authority", "call_local", "reliable")
func enter_ship(to_hub: bool, ids: Array, state: Dictionary, vitals: Array = []) -> void:
    leave()
    active = true
    in_hub = to_hub
    selected_destination = "demo"
    controller.connected_ids.assign(ids)
    controller.game_started = false
    apply_state(state)
    disable_menu_environment()
    _build_room()
    controller._game_layer.visible = false
    show_gameplay()
    for id in controller.connected_ids:
        controller.spawn_player_for_peer(id)
    controller.sync_vitals(vitals, true)
    # 舱内救回倒地船员，状态仍需在补给柱恢复。
    for player in controller.players.values():
        player.downed = false
        player.health = maxi(player.health, 1)
        player.oxygen = maxf(player.oxygen, 10.0)
        player.warmth = maxf(player.warmth, 0.2)
    if controller.is_host:
        for id in ids:
            if not packs.has(id):
                packs[id] = {"medical": 0, "oxygen": 0}

func _build_room() -> void:
    room = (HUB_SCENE if in_hub else TRAINING_SCENE).instantiate() as Node3D
    add_child(room)
    if not in_hub:
        var label := Label3D.new()
        label.text = "E 返回主舱"
        label.position = Vector3(8.1, 1.8, 5.15)
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.font_size = 30
        label.pixel_size = 0.01
        room.add_child(label)
        (room as ShipTutorial3D).show_step(int(training.get(multiplayer.get_unique_id(), 0)))

func leave() -> void:
    active = false
    close_panel(false)
    if room != null:
        remove_child(room)
        room.queue_free()
        room = null
    _layer.visible = false

func show_gameplay() -> void:
    if not active:
        return
    _facility = ""
    _panel.visible = false
    controller._set_screen("ship")
    controller._menu_layer.visible = false
    var focused := get_viewport().gui_get_focus_owner()
    if focused != null:
        focused.release_focus()

func close_panel(resume := true) -> void:
    _panel.visible = false
    _facility = ""
    if active and resume:
        show_gameplay()

func has_panel() -> bool:
    return _panel.visible or (active and controller._screen_view in ["route", "trade"])

func notice_text() -> String:
    return _notice if _notice_remaining > 0.0 else ""

func request(action: String, item := "") -> void:
    if controller.is_host:
        handle_request(1, action, item)
    else:
        request_action.rpc_id(1, action, item)

@rpc("any_peer", "call_remote", "reliable")
func request_action(action: String, item: String) -> void:
    if controller.is_host:
        handle_request(multiplayer.get_remote_sender_id(), action, item)

func handle_request(peer_id: int, action: String, item := "") -> void:
    if not controller.is_host:
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null:
        return
    if action.begins_with("use_"):
        _use_supply(peer_id, action.trim_prefix("use_"))
        return
    if action == "trade":
        _trade_at_market(peer_id, item)
        return
    if not active:
        return
    if action == "ready":
        if ready_peers.has(peer_id):
            ready_peers.erase(peer_id)
        else:
            ready_peers.append(peer_id)
        broadcast()
        return
    if action == "interact":
        if not in_hub:
            if controller._flat_distance(player.position, Vector3(8.1, 0, 5.1)) < 1.8:
                switch_area.rpc(true)
            return
        var facility := nearby_facility(player.position)
        if facility == "airlock":
            switch_area.rpc(false)
        elif not facility.is_empty():
            _show_for_peer(peer_id, facility)
        return
    if action.begins_with("train_") and not in_hub:
        var step := int(training.get(peer_id, 0))
        var expected := ["", "scan", "repair", "pickup", "deposit", "attack", "revive"]
        if step > 0 and step < 7 and action == "train_" + expected[step] and controller._flat_distance(player.position, (room as ShipTutorial3D).station_position(step)) < 2.0:
            training[peer_id] = step + 1
            player.carrying = 1 if step + 1 == 4 else 0
            if step == 5:
                controller.show_attack_visual.rpc(peer_id)
            broadcast()
        return
    if not in_hub:
        return
    var near := nearby_facility(player.position)
    var result_message := ""
    if action in ["take", "store"] and near in ["storage", "supply"] and item in ["medical", "oxygen"]:
        var bag: Dictionary = packs.get(peer_id, {"medical": 0, "oxygen": 0})
        var held := int(bag.get(item, 0))
        if action == "take" and held < 2 and int(stock[item]) > 0:
            stock[item] = int(stock[item]) - 1
            bag[item] = held + 1
        elif action == "store" and held > 0:
            stock[item] = int(stock[item]) + 1
            bag[item] = held - 1
        else:
            _notify(peer_id, "库存不足或已达到携带上限（每种 2 件）。")
            return
        packs[peer_id] = bag
        result_message = ("已领取 1 件" if action == "take" else "已存回 1 件") + String(ITEM_NAMES[item]) + "。"
    elif action == "craft" and near == "supply" and ITEM_COSTS.has(item):
        var cost := int(ITEM_COSTS[item])
        if credits < cost:
            _notify(peer_id, "回收点数不足。远征投送电池或冰样，返航后可用于制作。")
            return
        credits -= cost
        stock[item] = int(stock[item]) + 1
        result_message = "已制作 1 件" + String(ITEM_NAMES[item]) + "，存入共享库存。"
    elif action == "assign_goofy" and near == "supply" and GOOFY_ITEMS.has(item):
        goofy_assignments[peer_id] = item
        result_message = "已将%s分配给玩家 %d；道具箱仍归全队共享，可随时改分配。" % [goofy_item_name(item), peer_id]
    elif action == "assign_gear" and GEAR_ITEMS.has(item) and int(gear_stock.get(item, 0)) > 0:
        gear_assignments[peer_id] = item
        result_message = "已将%s分配给玩家 %d；装备属于团队共享仓。" % [GEAR_NAMES[item], peer_id]
    elif action == "repair" and near == "repair":
        if hull >= 100 or int(stock["parts"]) <= 0:
            _notify(peer_id, "舰体已完好。" if hull >= 100 else "没有维修零件，可在补给柱制作。")
            return
        stock["parts"] = int(stock["parts"]) - 1
        hull = mini(hull + 20, 100)
        result_message = "维修完成，舰体完整度 %d%%。" % hull
    elif action == "refill" and near == "supply":
        player.health = 5
        player.oxygen = 100.0
        player.warmth = 1.0
        player.downed = false
        controller.sync_vitals.rpc(controller._vitals_snapshot(), true)
        _notify(peer_id, "生命、氧气与体温已恢复，可以准备下一次远征。")
    else:
        _notify(peer_id, "请靠近对应设施再操作。")
        return
    broadcast()
    if not result_message.is_empty():
        _notify(peer_id, result_message)

func _use_supply(peer_id: int, item: String) -> void:
    if not controller.game_started or item not in ["medical", "oxygen"] or controller.mission_completed or controller.mission_failed:
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    var bag: Dictionary = packs.get(peer_id, {})
    if player == null or player.downed or int(bag.get(item, 0)) <= 0:
        return
    if (item == "medical" and player.health >= 5) or (item == "oxygen" and player.oxygen >= 100.0):
        return
    bag[item] = int(bag[item]) - 1
    packs[peer_id] = bag
    if item == "medical":
        player.health = mini(player.health + 2, 5)
    else:
        player.oxygen = minf(player.oxygen + 45.0, 100.0)
    controller.sync_vitals.rpc(controller._vitals_snapshot())
    broadcast()

func _trade_at_market(peer_id: int, item: String) -> void:
    if not active or not in_hub:
        return
    if GEAR_COSTS.has(item):
        var cost := int(GEAR_COSTS[item])
        if credits < cost:
            _notify(peer_id, "团队回收点数不足：%s 需要 %d 点。" % [GEAR_NAMES[item], cost])
            return
        credits -= cost
        gear_stock[item] = int(gear_stock.get(item, 0)) + 1
        _notify(peer_id, "星际集市交易完成：%s 已加入共享装备仓。" % GEAR_NAMES[item])
    elif GOOFY_ITEMS.has(item):
        goofy_stock[item] = int(goofy_stock.get(item, 0)) + 1
        _notify(peer_id, "星际集市补充了%s；它可以在星球内无限连按。" % goofy_item_name(item))
    broadcast()

func _show_for_peer(peer_id: int, facility: String) -> void:
    if peer_id == 1:
        show_facility(facility)
    else:
        show_facility.rpc_id(peer_id, facility)

@rpc("authority", "call_remote", "reliable")
func show_facility(facility: String) -> void:
    if not active:
        return
    if facility == "route":
        close_panel(false)
        controller._show_route()
        return
    _facility = facility
    _panel.visible = true
    _notice = ""
    controller._set_screen("facility")
    _refresh_panel()

func _refresh_panel() -> void:
    if not _panel.visible:
        return
    for child in _actions.get_children():
        _actions.remove_child(child)
        child.queue_free()
    var bag: Dictionary = packs.get(multiplayer.get_unique_id(), {"medical": 0, "oxygen": 0})
    _message.text = _notice
    match _facility:
        "storage":
            _title.text = "共享储物架"
            _body.text = "团队库存：医疗包 %d · 氧气瓶 %d · 零件 %d\n你的背包：医疗包 %d / 2 · 氧气瓶 %d / 2\n物资由全队共享，领取后随你进入星球。" % [stock.medical, stock.oxygen, stock.parts, int(bag.get("medical", 0)), int(bag.get("oxygen", 0))]
            _action_button("领取医疗包", "take", "medical", stock.medical <= 0 or int(bag.get("medical", 0)) >= 2)
            _action_button("存回医疗包", "store", "medical", int(bag.get("medical", 0)) == 0)
            _action_button("领取氧气瓶", "take", "oxygen", stock.oxygen <= 0 or int(bag.get("oxygen", 0)) >= 2)
            _action_button("存回氧气瓶", "store", "oxygen", int(bag.get("oxygen", 0)) == 0)
        "repair":
            _title.text = "舰体维修台"
            _body.text = "舰体完整度：%d%%\n维修零件：%d · 每次消耗 1 件，恢复 20%%\n远征返航会留下损耗；低于 60%% 时需先维修。" % [hull, stock.parts]
            _action_button("维修舰体  ·  1 件零件", "repair", "", hull >= 100 or stock.parts <= 0)
        "supply":
            _title.text = "补给柱"
            var player := controller.players.get(multiplayer.get_unique_id()) as SpacePlayer3D
            _body.text = "生命 %d / 5 · 氧气 %d%% · 体温 %d%%\n团队回收点数：%d\n共享装备仓：%s\n共享欢乐道具箱：%s\n道具没有冷却，可连续触发；5-9 直接使用。" % [player.health, int(player.oxygen), int(player.warmth * 100), credits, gear_inventory_text(), goofy_inventory_text()]
            _action_button("恢复生命、氧气与体温  ·  免费", "refill")
            for item in ["medical", "oxygen", "parts"]:
                _action_button("制作%s  ·  %d 回收点数" % [ITEM_NAMES[item], ITEM_COSTS[item]], "craft", item, credits < int(ITEM_COSTS[item]))
        "mission":
            _title.text = "远征记录"
            _body.text = last_report + "\n\n下一目的地：霜烬星\n调查地标、校准信标、处理地下异常并撤离。"
            _body.size.y = 230
    if _facility != "mission":
        _body.size.y = 100

func _action_button(label: String, action: String, item := "", disabled := false) -> void:
    var button := controller._ui_button(_actions, label, Vector2.ZERO, Vector2(554, 42), func(): request(action, item))
    button.custom_minimum_size = Vector2(554, 42)
    button.disabled = disabled

func _notify(peer_id: int, message: String) -> void:
    if peer_id == 1:
        show_notice(message)
    else:
        show_notice.rpc_id(peer_id, message)

@rpc("authority", "call_remote", "reliable")
func show_notice(message: String) -> void:
    _notice = message
    _notice_remaining = 4.0
    _message.text = message
    if controller._screen_view == "trade":
        controller._refresh_trade_buttons()

@rpc("authority", "call_local", "reliable")
func switch_area(to_hub: bool) -> void:
    if not active or in_hub == to_hub:
        return
    in_hub = to_hub
    remove_child(room)
    room.queue_free()
    _build_room()
    for id in controller.players:
        var player := controller.players[id] as SpacePlayer3D
        player.teleport_to(spawn_position(id))
        player.carrying = 0
        player.configure_ship_camera()
    show_gameplay()

func all_ready() -> bool:
    if controller.connected_ids.is_empty():
        return false
    for id in controller.connected_ids:
        if not ready_peers.has(id):
            return false
    return true

func confirm_land() -> void:
    if controller.is_host and active and hull >= 60 and all_ready():
        controller.start_planet(selected_destination)

func select_destination(destination: String) -> void:
    if destination not in ["demo", "electromagnetic", "ruin"]:
        return
    selected_destination = destination
    controller._show_route()

func add_peer(peer_id: int) -> void:
    if not packs.has(peer_id):
        packs[peer_id] = {"medical": 0, "oxygen": 0}
    ready_peers.clear()
    enter_ship.rpc_id(peer_id, in_hub, controller.connected_ids, snapshot(), controller._vitals_snapshot())
    controller.spawn_player_for_peer.rpc(peer_id)
    broadcast()

func remove_peer(peer_id: int) -> void:
    if controller.is_host:
        var bag: Dictionary = packs.get(peer_id, {})
        for item in ["medical", "oxygen"]:
            stock[item] = int(stock[item]) + int(bag.get(item, 0))
        packs.erase(peer_id)
        training.erase(peer_id)
        ready_peers.erase(peer_id)
        broadcast()

func settle(success: bool, value: int, report: String) -> void:
    credits += maxi(value, 0)
    hull = maxi(hull - (8 if success else 20), 40)
    # 应急零件避免库存耗尽后无法再出发；正常维修仍消耗共享库存。
    stock.parts = maxi(int(stock.parts), 1)
    last_report = report + "\n本次入库：%d 回收点数。" % maxi(value, 0)
    ready_peers.clear()
    save_state()

func snapshot() -> Dictionary:
    return {"stock": stock.duplicate(true), "packs": packs.duplicate(true), "ready": ready_peers.duplicate(), "training": training.duplicate(true), "hull": hull, "credits": credits, "last_report": last_report, "goofy_stock": goofy_stock.duplicate(true), "goofy_assignments": goofy_assignments.duplicate(true), "gear_stock": gear_stock.duplicate(true), "gear_assignments": gear_assignments.duplicate(true), "planet_states": planet_states.duplicate(true), "selected_destination": selected_destination}

func apply_state(state: Dictionary) -> void:
    stock = state.get("stock", stock).duplicate(true)
    packs = state.get("packs", packs).duplicate(true)
    ready_peers.assign(state.get("ready", []))
    training = state.get("training", training).duplicate(true)
    hull = int(state.get("hull", hull))
    credits = int(state.get("credits", credits))
    last_report = String(state.get("last_report", last_report))
    goofy_stock = state.get("goofy_stock", goofy_stock).duplicate(true)
    goofy_assignments = state.get("goofy_assignments", goofy_assignments).duplicate(true)
    gear_stock = state.get("gear_stock", gear_stock).duplicate(true)
    gear_assignments = state.get("gear_assignments", gear_assignments).duplicate(true)
    planet_states = state.get("planet_states", planet_states).duplicate(true)
    selected_destination = String(state.get("selected_destination", selected_destination))
    _refresh_panel()
    if active and not in_hub and room != null:
        (room as ShipTutorial3D).show_step(int(training.get(multiplayer.get_unique_id(), 0)))

@rpc("authority", "call_local", "reliable")
func sync_state(state: Dictionary) -> void:
    apply_state(state)

func broadcast() -> void:
    sync_state.rpc(snapshot())
    save_state()

func save_state() -> void:
    if not persistence_enabled or not controller.is_host:
        return
    var saved_stock: Dictionary = stock.duplicate(true)
    # 关闭房间时，携带物资归还库存，下一次房间不依赖临时网络 ID。
    for bag in packs.values():
        for item in ["medical", "oxygen"]:
            saved_stock[item] = int(saved_stock[item]) + int(bag.get(item, 0))
    var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify({"version": 3, "stock": saved_stock, "hull": hull, "credits": credits, "last_report": last_report, "goofy_stock": goofy_stock, "goofy_assignments": goofy_assignments, "gear_stock": gear_stock, "gear_assignments": gear_assignments, "planet_states": planet_states}, "  "))
        file.close()
        var result := DirAccess.rename_absolute(save_path + ".tmp", save_path)
        if result != OK:
            push_warning("船舱物资存档未保存：" + error_string(result))

func load_state() -> void:
    if not persistence_enabled or not FileAccess.file_exists(save_path):
        return
    var file := FileAccess.open(save_path, FileAccess.READ)
    if file == null:
        return
    var data = JSON.parse_string(file.get_as_text())
    if not data is Dictionary or int(data.get("version", 0)) not in [1, 2, 3]:
        return
    var saved_stock = data.get("stock", {})
    if not saved_stock is Dictionary:
        return
    for item in ITEM_NAMES:
        stock[item] = clampi(int(saved_stock.get(item, stock[item])), 0, 9999)
    hull = clampi(int(data.get("hull", 80)), 40, 100)
    stock.parts = maxi(int(stock.parts), 1)
    credits = clampi(int(data.get("credits", 0)), 0, 999999)
    last_report = String(data.get("last_report", last_report))
    if data.has("goofy_stock"):
        goofy_stock = data.get("goofy_stock", goofy_stock).duplicate(true)
    if data.has("goofy_assignments"):
        goofy_assignments = data.get("goofy_assignments", goofy_assignments).duplicate(true)
    if data.has("planet_states"):
        planet_states = data.get("planet_states", planet_states).duplicate(true)
    if data.has("gear_stock"):
        gear_stock = data.get("gear_stock", gear_stock).duplicate(true)
    if data.has("gear_assignments"):
        gear_assignments = data.get("gear_assignments", gear_assignments).duplicate(true)
    packs.clear()
    training.clear()
    ready_peers.clear()

func goofy_item_name(item_id: String) -> String:
    return {"penguin": "回声企鹅", "bubble": "反重力泡", "board": "雪地滑板", "hologram": "全息替身", "smoke": "彩色信号烟"}.get(item_id, item_id)

func goofy_inventory_text() -> String:
    var labels: Array[String] = []
    for item_id in GOOFY_ITEMS:
        labels.append("%s×%d" % [goofy_item_name(item_id), int(goofy_stock.get(item_id, 0))])
    return "、".join(labels)

func gear_inventory_text() -> String:
    var labels: Array[String] = []
    for item_id in GEAR_ITEMS:
        labels.append("%s×%d" % [String(GEAR_NAMES[item_id]), int(gear_stock.get(item_id, 0))])
    return "、".join(labels)

func has_gear(peer_id: int, item_id: String) -> bool:
    return String(gear_assignments.get(peer_id, "")) == item_id

func planet_state(planet_id: String) -> Dictionary:
    var raw: Dictionary = planet_states.get(planet_id, {})
    if raw.is_empty():
        raw = {"story_flags": {}, "side_quest_states": {}, "achievements": {}, "world_flags": {}, "resource_epoch": 0, "lost_cargo": []}
        planet_states[planet_id] = raw
    return raw

func set_planet_state(planet_id: String, state: Dictionary) -> void:
    planet_states[planet_id] = state.duplicate(true)

func show_home() -> void:
    leave()
    controller._menu_world.visible = true
    for child in controller._menu_world.get_children():
        if child is WorldEnvironment:
            child.environment = _menu_environment
    controller._menu_camera.current = true
    for light in _menu_light_energy:
        light.light_energy = _menu_light_energy[light]
