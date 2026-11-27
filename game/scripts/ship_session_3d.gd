extends Node
class_name ShipSession3D

const HUB_SCENE := preload("res://scenes/ship_hub_3d.tscn")
const TRAINING_SCENE := preload("res://scenes/ship_tutorial_3d.tscn")
const ITEM_NAMES := {"medical": "医疗包", "oxygen": "氧气瓶", "parts": "维修零件"}
const ITEM_COSTS := {"medical": 10, "oxygen": 5, "parts": 10}
const TRAINING_STEPS := ["拿取架上的氧气瓶", "左键 · 安装到宇航服", "短按空格 · 跳上低台", "长按空格 · 喷气登高", "落地松开 · 耗氧充气后前往终点", "推进练习完成 · 可继续自由练习"]
const SAVE_PATH := "user://ship-cabin-save.json"
const CAMPAIGN_SAVE_PATH: String = "user://campaign-v1.json"
var campaign: CampaignNavigation = preload("res://scripts/campaign_navigation.gd").new()
const GOOFY_ITEMS := ["penguin", "bubble", "board", "hologram", "smoke"]
const GEAR_ITEMS := ["thermal_suit", "wide_scanner", "signal_stabilizer"]
const GEAR_NAMES := {"thermal_suit": "恒温外套", "wide_scanner": "广域扫描器", "signal_stabilizer": "信号稳压器"}
const GEAR_COSTS := {"thermal_suit": 45, "wide_scanner": 55, "signal_stabilizer": 65}

var controller: Main3D
var active := false
var in_hub := true
var _hub_training_arrival: bool = false
var room: Node3D
var stock := {"medical": 8, "oxygen": 8, "parts": 6}
var packs: Dictionary = {}
var ready_peers: Array[int] = []
var station_owners: Dictionary = {}
var launch_remaining: float = -1.0
var _exit_armed: Dictionary = {}
var selected_destination := "demo"
var training: Dictionary = {}
var oxygen_levels: Array = []
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
var _hint: Label
var _hint_panel: Panel
var _panel: Panel
var _title: Label
var _body: Label
var _message: Label
var _facility := ""
var _notice := ""
var _notice_remaining := 0.0
var _menu_environment: Environment
var _menu_light_energy: Dictionary = {}
var _aim_dot: Label
var _computer: ShipComputerUI
var _compass_hud: MissionCompassHUD
var _opened_computers: Dictionary = {}

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
    _aim_dot = controller._ui_label(controls, "·", Vector2.ZERO, Vector2(12, 20), 20, Color("#d8eee5"))
    controller._place_hud(_aim_dot, Control.PRESET_CENTER, Vector2(-6, -10), Vector2(12, 20))
    _aim_dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _aim_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ship_panel = controller._panel(_layer, Vector2.ZERO, Vector2(132, 34), UIStyleKit.VISOR_GLASS, UIStyleKit.VISOR_BORDER, 6)
    controller._place_hud(_ship_panel, Control.PRESET_CENTER_TOP, Vector2(-66, 14), Vector2(132, 34))
    _ship_title = controller._ui_label(_ship_panel, "主舱", Vector2(8, 3), Vector2(116, 28), 16, UIStyleKit.VISOR_CYAN)
    _ship_title.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
    _ship_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _ship_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _hint_panel = controller._panel(_layer, Vector2(225, 580), Vector2(600, 44), UIStyleKit.VISOR_GLASS, UIStyleKit.VISOR_CYAN, 6)
    _hint = controller._ui_label(_hint_panel, "", Vector2(16, 4), Vector2(568, 36), 15, UIStyleKit.VISOR_TEXT)
    _hint.add_theme_font_override("font", UIStyleKit.FONT_BOLD)
    _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _panel = controller._panel(_layer, Vector2(335, 115), Vector2(610, 500), Color(0.95, 0.93, 0.86, 0.98), Color("#79aaa7"), 20)
    _panel.visible = false
    _title = controller._ui_label(_panel, "", Vector2(28, 22), Vector2(554, 42), 29, Color("#294d5b"))
    _body = controller._ui_label(_panel, "", Vector2(28, 80), Vector2(554, 100), 17, Color("#466b74"))
    _message = controller._ui_label(_panel, "", Vector2(28, 420), Vector2(300, 66), 15, Color("#a55e37"))
    _computer = preload("res://scripts/ship_computer_ui.gd").new() as ShipComputerUI
    _layer.add_child(_computer)
    _computer.setup(self)
    _compass_hud = preload("res://scripts/mission_compass_hud.gd").new() as MissionCompassHUD
    _layer.add_child(_compass_hud)

func tick(delta: float) -> void:
    _notice_remaining = maxf(_notice_remaining - delta, 0.0)
    _layer.visible = active or controller.game_started
    _ship_panel.visible = active and controller._screen_view == "ship"
    _ship_title.text = "主舱" if in_hub else "训练舱"
    _hint_panel.visible = active and not has_panel() and controller._screen_view == "ship"
    _aim_dot.visible = active and controller._screen_view == "ship" and not controller.market_visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
    if _compass_hud != null and not active:
        _compass_hud.visible = false
    var peer_id := multiplayer.get_unique_id()
    if not active:
        return
    if _computer.visible:
        _computer.refresh()
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player != null:
        _aim_dot.visible = _aim_dot.visible and not player.downed
        _hint_panel.visible = _hint_panel.visible and not player.downed
        _hint.text = _notice if _notice_remaining > 0.0 and not _notice.is_empty() else interaction_hint(player.global_position)
        _hint_panel.visible = _hint_panel.visible and not _hint.text.is_empty()
        if _hint_panel.visible:
            var hint_width: float = clampf(_hint.get_theme_font("font").get_string_size(_hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 40.0, 180.0, 620.0)
            controller._place_hud(_hint_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-hint_width / 2.0, -148), Vector2(hint_width, 44))
            _hint.size.x = hint_width - 32.0
    if _compass_hud != null:
        _compass_hud.visible = active and in_hub and not has_panel() and controller._screen_view == "ship" and player != null and not player.downed
        if _compass_hud.visible:
            var fwd: Vector3 = -player._camera.global_basis.z if player._camera != null else -player.global_basis.z
            var stage_t: String = "归航号 · 主线指引"
            var m_title: String = ""
            var m_detail: String = ""
            var main_pt: Vector3 = Vector3(0.0, 0.0, 1.75)
            var main_lbl: String = "星图台"
            if hull < 60:
                stage_t = "主线 1 / 3 · 舰体抢修"
                m_title = "拉动右侧【舰体维修总闸】"
                m_detail = "当前舰体 %d%%（需 ≥60%% 才能起飞）。走近右侧维修总闸直接按 E 修复。" % hull
                main_pt = ShipHub3D.REPAIR
                main_lbl = "维修总闸"
            elif campaign.enabled and campaign.grounded and campaign.location == "demo" and not campaign.home_reached:
                stage_t = "主线 1 / 3 · 坠落霜烬星"
                m_title = "拉动舱尾【气闸出舱拉杆】出舱探索"
                m_detail = "起飞核心已损毁！转身前往舱尾气闸旁按 E 出舱，到霜烬星科考站寻回高能核心。"
                main_pt = ShipDevices3D.surface_device().position
                main_lbl = "气闸出舱"
            elif not ready_peers.has(peer_id):
                stage_t = "主线 2 / 3 · 星际航行准备"
                m_title = "在中央【星图台】选星，再登前方【驾驶席】"
                var dest_name: String = String(PlanetRegistry.info(selected_destination).get("title", "霜烬星"))
                m_detail = "当前航线：%s。确认后走上前排驾驶席按 E 就位，全员就位 3 秒自动起飞。" % dest_name
                main_pt = Vector3(ShipDevices3D.PILOT_X[0], 0.61, -13.8)
                main_lbl = "驾驶席"
            else:
                stage_t = "主线 3 / 3 · 点火起飞"
                m_title = "已就位 · 等待起飞倒数"
                m_detail = "保持就位，全员就位后自动点火前往下一颗星球。"
                main_pt = Vector3(0.0, 0.61, -13.8)
                main_lbl = "舰桥"
            var sides: PackedStringArray = PackedStringArray([
                "舱内功能分区（看墙面/头顶金属牌）：",
                "• 右后【工坊军械台】制作/装备/道具/换装",
                "• 左后【生命充氧站】E 一键回满血与气瓶",
                "• 右舷侧门【独立训练舱】E 练习喷气背包",
                "• 正后尾门【星球登陆气闸】降落后出舱",
            ])
            var tlist: Array = [
                {"label": main_lbl, "pos": main_pt, "color": Color("#4ef0ff"), "main": true},
                {"label": "星图台", "pos": Vector3(0.0, 0.0, 1.75), "color": Color("#86d8e8"), "main": false},
                {"label": "工坊台", "pos": Vector3(4.8, 0.0, 2.2), "color": Color("#f4b65c"), "main": false},
                {"label": "训练舱(右)", "pos": ShipHub3D.AIRLOCK, "color": Color("#7ce8b4"), "main": false},
                {"label": "出舱门(后)", "pos": Vector3(0.0, 0.0, 14.8), "color": Color("#ff8a5c"), "main": false},
            ]
            _compass_hud.update_guidance(player.global_position, fwd, stage_t, m_title, m_detail, sides, tlist)
    if controller.is_host and not in_hub:
        for id in controller.connected_ids:
            var trainee := controller.players.get(id) as SpacePlayer3D
            if trainee == null:
                continue
            var step: int = int(training.get(id, 0))
            if step < 2 or step >= 5 or not controller._items.has_jet(id):
                continue
            var target: Vector3 = ShipTutorial3D.HOP_POINT if step == 2 else (ShipTutorial3D.BOOST_POINT if step == 3 else ShipTutorial3D.FINISH_POINT)
            var landed: bool = controller._flat_distance(trainee.position, target) < 1.25 and absf(trainee.position.y - target.y) < 0.16
            if landed:
                var floor_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(trainee.position + Vector3.UP * 0.12, trainee.position - Vector3.UP * 0.18, 2)
                landed = not trainee.get_world_3d().direct_space_state.intersect_ray(floor_query).is_empty()
            if landed:
                training[id] = step + 1
                (room as ShipTutorial3D).show_step(int(training.get(multiplayer.get_unique_id(), 0)))
                _notify(id, String(TRAINING_STEPS[step + 1]))
                broadcast()
    if controller.is_host and active and in_hub:
        _tick_launch(delta)
    if controller._screen_view == "route":
        controller._land_button.disabled = not controller.is_host or not all_ready() or hull < 60
        if controller._electro_land_button != null:
            controller._electro_land_button.disabled = not controller.is_host or not all_ready() or hull < 60
        var selected_title := String(PlanetRegistry.info(selected_destination).get("title", selected_destination))
        controller._route_status.text = "已选%s · 准备 %d / %d · 舰体 %d%%（需 ≥60%%）" % [selected_title, ready_peers.size(), controller.connected_ids.size(), hull]
    elif controller._screen_view == "trade":
        controller._refresh_trade_buttons()

func interaction_hint(point: Vector3) -> String:
    var physical_hint: String = controller._items.item_hint(multiplayer.get_unique_id()) if controller._items != null else ""
    if not physical_hint.is_empty():
        return physical_hint
    if in_hub:
        var devices: ShipDevices3D = device_room()
        var device: Dictionary = devices.nearby(multiplayer.get_unique_id()) if devices != null else {}
        if not device.is_empty():
            return devices.hint(multiplayer.get_unique_id(), device)
        var facility := nearby_facility(point)
        return "E 训练舱" if facility == "airlock" else ""
    if controller._flat_distance(point, ShipTutorial3D.ENTRY_POINT) < 1.8:
        return "E 返回主舱"
    # 训练舱非交互区不再常驻底部文字提示，保持画面干净清爽
    return ""

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
    var index: int = maxi(controller.connected_ids.find(peer_id), 0) % 4
    var doorway_offset: Vector3 = Vector3((float(index) - 1.5) * 0.72, 0, 0)
    if not in_hub:
        return ShipTutorial3D.ENTRY_POINT + doorway_offset
    if _hub_training_arrival:
        var side_offset: Vector3 = Vector3(0.0, 0.0, (float(index) - 1.5) * 0.55)
        return ShipHub3D.AIRLOCK + Vector3(-1.45, 0, 0) + side_offset
    return Vector3(-1.8 + float(index) * 1.2, 0, 3.6)

func spawn_yaw() -> float:
    return 0.0 if in_hub else ShipTutorial3D.ENTRY_YAW

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
        (room as ShipTutorial3D).show_step(int(training.get(multiplayer.get_unique_id(), 0)))

func leave() -> void:
    if active and not in_hub and controller.is_host and controller._items != null:
        for peer_id: int in controller.players:
            controller._items.finish_training(peer_id)
    active = false
    _clear_departure()
    _exit_armed.clear()
    _opened_computers.clear()
    _hub_training_arrival = false
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
    _computer.visible = false
    controller._set_screen("ship")
    controller._menu_layer.visible = false
    var focused := get_viewport().gui_get_focus_owner()
    if focused != null:
        focused.release_focus()

func close_panel(resume := true) -> void:
    if _computer.visible and active:
        request("computer_close")
    _computer.visible = false
    _panel.visible = false
    _facility = ""
    if active and resume:
        show_gameplay()

func has_panel() -> bool:
    return _computer.visible or _panel.visible or (active and controller._screen_view in ["route", "trade"])

func device_room() -> ShipDevices3D:
    return room.get_node_or_null("ShipDevices") as ShipDevices3D if room != null and in_hub else null

func _clear_departure() -> void:
    ready_peers.clear()
    station_owners.clear()
    launch_remaining = -1.0

func _release_station(peer_id: int) -> void:
    ready_peers.erase(peer_id)
    for slot: int in station_owners.keys():
        if int(station_owners[slot]) == peer_id:
            station_owners.erase(slot)
    launch_remaining = -1.0

func _toggle_station(peer_id: int, slot: int) -> void:
    if campaign.enabled and not campaign.block_reason(selected_destination).is_empty():
        _notify(peer_id, campaign.block_reason(selected_destination) if not selected_destination.is_empty() else "先在航线电脑设定目的地")
        return
    var owner: int = int(station_owners.get(slot, 0))
    if owner == peer_id:
        _release_station(peer_id)
        station_pose.rpc(peer_id, slot, false)
    elif owner != 0:
        _notify(peer_id, "驾驶台已占用")
        return
    elif hull < 60:
        _notify(peer_id, "舰体不足 60% · 先维修")
        return
    else:
        _release_station(peer_id)
        station_owners[slot] = peer_id
        ready_peers.append(peer_id)
        station_pose.rpc(peer_id, slot, true)
    _notify(peer_id, "")
    broadcast()

@rpc("authority", "call_local", "reliable")
func station_pose(peer_id: int, slot: int, engaged: bool) -> void:
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player == null or slot < 0 or slot >= 4:
        return
    player.teleport_to(Vector3(ShipDevices3D.PILOT_X[slot], 0.61 if engaged else 0.0, -13.08 if engaged else -12.2))
    player.rotation.y = 0.0
    if peer_id == multiplayer.get_unique_id():
        player._camera_yaw = 0.0
        player._camera_yaw_target = 0.0
        player._camera_pitch = 0.2 if engaged else 0.0
        player._camera_pitch_target = player._camera_pitch

func _tick_launch(delta: float) -> void:
    var changed: bool = false
    for slot: int in station_owners.keys():
        var peer_id: int = int(station_owners[slot])
        var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
        if player == null or controller._flat_distance(player.position, ShipDevices3D.point_for("pilot_%d" % slot)) > 2.65 or player.downed:
            _release_station(peer_id)
            changed = true
    if all_ready() and hull >= 60 and (not campaign.enabled or campaign.block_reason(selected_destination).is_empty()):
        if launch_remaining < 0.0:
            launch_remaining = 3.0
            changed = true
        else:
            var previous: int = ceili(launch_remaining)
            launch_remaining = maxf(launch_remaining - delta, 0.0)
            changed = changed or previous != ceili(launch_remaining)
            if launch_remaining <= 0.0:
                confirm_land()
                return
    elif launch_remaining >= 0.0:
        launch_remaining = -1.0
        changed = true
    if changed:
        broadcast()

func _operate_device(peer_id: int, device: Dictionary) -> void:
    if String(device.kind) in ShipDevices3D.DIRECT_KINDS:
        var dr: ShipDevices3D = device_room()
        if dr != null:
            dr.pulse_lever(String(device.id))
        _execute_device(peer_id, device)
        return
    _opened_computers[peer_id] = String(device.id)
    if peer_id == 1:
        show_computer(String(device.id))
    else:
        show_computer.rpc_id(peer_id, String(device.id))

@rpc("authority", "call_remote", "reliable")
func show_computer(id: String) -> void:
    var device: Dictionary = ShipDevices3D.entry_for(id)
    if not active or not in_hub or device.is_empty() or device.kind == "pilot":
        return
    _facility = id
    _notice = ""
    _panel.visible = false
    _computer.open(device)
    controller._set_screen("facility")

func _execute_device(peer_id: int, device: Dictionary) -> void:
    var item: String = String(device.item)
    match String(device.kind):
        "pilot": _toggle_station(peer_id, int(item))
        "route":
            if campaign.enabled:
                if int(device.get("plan_revision", -1)) != campaign.revision:
                    _notify(peer_id, "航线已变化 · 请重新选择目的地后确认")
                    return
                if item == "demo" and campaign.location == "demo" and campaign.grounded and not campaign.home_reached:
                    controller._campaign_travel.open_surface.call_deferred()
                    return
                var reason: String = campaign.block_reason(item)
                if not reason.is_empty():
                    _notify(peer_id, reason)
                    return
            if selected_destination != item:
                selected_destination = item
                if campaign.enabled:
                    campaign.revision += 1
                _clear_departure()
                broadcast()
                show_notice.rpc("航线：" + String(device.title))
        "surface":
            if campaign.enabled and campaign.grounded and campaign.location == "demo" and not campaign.home_reached:
                controller._campaign_travel.open_surface.call_deferred()
            else:
                _notify(peer_id, "当前位于航行轨道 · 请前往星图台选星")
        "repair", "refill": handle_request(peer_id, String(device.kind))
        "craft": handle_request(peer_id, "craft", item)
        "toy": handle_request(peer_id, "assign_goofy", item)
        "gear":
            var held: bool = controller._items.selected(peer_id).get("kind", "") == item
            if has_gear(peer_id, item) and not held and controller._items.available_gear(item) <= 0:
                return
            if not controller._items.can_equip(peer_id, item):
                _notify(peer_id, "装备栏已满 · Tab 选择装备后 G 卸下")
                return
            if held:
                controller._items.equip_gear(peer_id, item, true)
                return
            if int(gear_stock.get(item, 0)) <= 0:
                _trade_at_market(peer_id, item)
            if controller._items.equip_gear(peer_id, item):
                _notify(peer_id, "已装备 " + String(GEAR_NAMES[item]))
            elif int(gear_stock.get(item, 0)) > 0:
                _notify(peer_id, "装备正在使用或已放在地上")
        "skin": controller.request_purchase_skin(peer_id, item)
        "store":
            if item in ["0", "1"]:
                controller._items.ensure_bag(peer_id).selected = int(item)
            var held: Dictionary = controller._items.selected(peer_id)
            var kind: String = String(held.get("kind", ""))
            if kind in ["medical", "oxygen"] or GOOFY_ITEMS.has(kind):
                var amount: float = float(held.get("oxygen", 100.0))
                controller._items.take_selected(peer_id)
                if kind in ["medical", "oxygen"]:
                    stock[kind] = int(stock[kind]) + 1
                    if kind == "oxygen":
                        keep_oxygen_levels([amount])
                broadcast()
                _notify(peer_id, "已存回 " + controller._items.item_name(kind))
            else:
                _notify(peer_id, "选中需要存回的物资")
        "mission": _show_for_peer(peer_id, "mission")
        "exit":
            if Time.get_ticks_msec() < int(_exit_armed.get(peer_id, 0)):
                _exit_armed.erase(peer_id)
                if peer_id == multiplayer.get_unique_id():
                    controller._show_home.call_deferred()
                else:
                    leave_to_menu.rpc_id(peer_id)
            else:
                _exit_armed[peer_id] = Time.get_ticks_msec() + 3000
                _notify(peer_id, "再次点击确认离开")

@rpc("authority", "call_remote", "reliable")
func leave_to_menu() -> void:
    controller._show_home()

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

func stock_oxygen_level() -> float:
    return float(oxygen_levels[0]) if not oxygen_levels.is_empty() else 100.0

func take_stock_oxygen_level() -> void:
    if not oxygen_levels.is_empty():
        oxygen_levels.pop_front()

func keep_oxygen_levels(levels: Array) -> void:
    for value: Variant in levels:
        var amount: float = clampf(float(value), 0.0, 100.0)
        if amount < 99.999:
            oxygen_levels.append(amount)

func handle_request(peer_id: int, action: String, item := "") -> void:
    if not controller.is_host:
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or not controller.connected_ids.has(peer_id):
        return
    if action.begins_with("use_"):
        _use_supply(peer_id, action.trim_prefix("use_"))
        return
    if action == "trade":
        _trade_at_market(peer_id, item)
        return
    if not active:
        return
    if action == "computer_close":
        _opened_computers.erase(peer_id)
        _exit_armed.erase(peer_id)
        return
    if action == "computer_action":
        if not in_hub or player.downed:
            return
        var opened: String = String(_opened_computers.get(peer_id, ""))
        var computers: ShipDevices3D = device_room()
        var current: Dictionary = computers.nearby(peer_id) if computers != null else {}
        if opened.is_empty() or current.get("id", "") != opened:
            _notify(peer_id, "请靠近电脑")
            return
        var option: Dictionary = {}
        var requested_id: String = item.get_slice("@", 0)
        for candidate: Dictionary in ShipDevices3D.options_for(current, campaign):
            if candidate.id == requested_id:
                option = candidate
                if current.kind == "route" and campaign.enabled:
                    option.plan_revision = int(item.get_slice("@", 1)) if item.contains("@") else -1
                break
        if current.kind == "store" and item in ["store_0", "store_1"]:
            option = current.duplicate()
            option.item = item.trim_prefix("store_")
        if not option.is_empty():
            _execute_device(peer_id, option)
        return
    if action == "training_exit" and not in_hub:
        if controller._flat_distance(player.position, ShipTutorial3D.ENTRY_POINT) < 1.8:
            switch_area.rpc(true)
        return
    if action == "ready":
        var devices: ShipDevices3D = device_room()
        var device: Dictionary = devices.nearby(peer_id) if devices != null else {}
        if device.get("kind", "") == "pilot":
            _toggle_station(peer_id, int(device.item))
        return
    if action == "interact":
        if not in_hub:
            if controller._flat_distance(player.position, ShipTutorial3D.ENTRY_POINT) < 1.8:
                switch_area.rpc(true)
            return
        var devices: ShipDevices3D = device_room()
        var device: Dictionary = devices.nearby(peer_id) if devices != null else {}
        if not device.is_empty():
            _operate_device(peer_id, device)
            return
        var facility := nearby_facility(player.position)
        if facility == "airlock":
            switch_area.rpc(false)
        return
    if not in_hub:
        return
    var near := nearby_facility(player.position)
    var devices: ShipDevices3D = device_room()
    var near_device: Dictionary = devices.nearby(peer_id) if devices != null else {}
    var result_message := ""
    if action in ["take", "store"] and near == "storage" and item in ["medical", "oxygen"]:
        var bag: Dictionary = packs.get(peer_id, {"medical": 0, "oxygen": 0})
        var held := int(bag.get(item, 0))
        if action == "take" and int(stock[item]) > 0 and controller._items.add_item(peer_id, item, -1, {"oxygen": stock_oxygen_level()}, true):
            stock[item] = int(stock[item]) - 1
            if item == "oxygen":
                take_stock_oxygen_level()
        elif action == "store" and held > 0:
            var amount: float = 100.0
            for stored: Dictionary in controller._items.ensure_bag(peer_id).slots:
                if stored.get("kind", "") == item:
                    amount = float(stored.get("oxygen", 100.0))
                    break
            if not controller._items.remove_item(peer_id, item):
                return
            stock[item] = int(stock[item]) + 1
            if item == "oxygen":
                keep_oxygen_levels([amount])
        else:
            _notify(peer_id, "库存不足、物品栏已满（共 4 格），或没有可存回的物品。")
            return
        result_message = ("已领取 1 件" if action == "take" else "已存回 1 件") + String(ITEM_NAMES[item]) + "。"
    elif action == "craft" and ITEM_COSTS.has(item) and near_device.get("kind", "") in ["craft", "workshop"]:
        var cost := int(ITEM_COSTS[item])
        if credits < cost:
            _notify(peer_id, "回收点数不足。远征投送电池或冰样，返航后可用于制作。")
            return
        credits -= cost
        stock[item] = int(stock[item]) + 1
        result_message = "已制作 1 件" + String(ITEM_NAMES[item]) + "，存入共享库存。"
    elif action == "assign_goofy" and GOOFY_ITEMS.has(item) and near_device.get("kind", "") in ["toy", "workshop"]:
        if not controller._items.add_item(peer_id, item, -1, {}, true):
            _notify(peer_id, "物品栏已满，先使用或放下一件物品。")
            return
        goofy_assignments[peer_id] = item
        result_message = "已将%s分配给玩家 %d；道具箱仍归全队共享，可随时改分配。" % [goofy_item_name(item), peer_id]
    elif action == "assign_gear" and GEAR_ITEMS.has(item) and int(gear_stock.get(item, 0)) > 0 and near_device.get("kind", "") in ["gear", "workshop"]:
        if not controller._items.equip_gear(peer_id, item):
            _notify(peer_id, "装备位不足或装备正在使用")
            return
        result_message = "已将%s分配给玩家 %d；装备属于团队共享仓。" % [GEAR_NAMES[item], peer_id]
    elif action == "repair" and near_device.get("kind", "") == "repair":
        if hull >= 100 or int(stock["parts"]) <= 0:
            _notify(peer_id, "舰体已完好。" if hull >= 100 else "没有维修零件，可在补给柱制作。")
            return
        stock["parts"] = int(stock["parts"]) - 1
        hull = mini(hull + 20, 100)
        result_message = "维修完成，舰体完整度 %d%%。" % hull
    elif action == "refill" and near_device.get("kind", "") == "refill":
        player.health = 5
        player.oxygen = 100.0
        player.warmth = 1.0
        controller._items.refill_oxygen(peer_id)
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
    if (not controller.game_started and not active) or item not in ["medical", "oxygen"] or controller.mission_completed or controller.mission_failed:
        return
    if item == "oxygen":
        var wearer: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
        if wearer != null and not wearer.downed:
            var slots: Array = controller._items.ensure_bag(peer_id).slots
            for index: int in slots.size():
                if (slots[index] as Dictionary).get("kind", "") == "oxygen":
                    controller._items.mount_oxygen(peer_id, index)
                    break
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    var bag: Dictionary = packs.get(peer_id, {})
    if player == null or player.downed or int(bag.get(item, 0)) <= 0:
        return
    if player.health >= 5:
        return
    if not controller._items.remove_item(peer_id, item):
        return
    player.health = mini(player.health + 2, 5)
    controller.sync_vitals.rpc(controller._vitals_snapshot(), active)
    broadcast()

func _trade_at_market(peer_id: int, item: String) -> void:
    if not active or not in_hub:
        return
    var devices: ShipDevices3D = device_room()
    var device: Dictionary = devices.nearby(peer_id) if devices != null else {}
    if device.get("kind", "") not in ["gear", "workshop"] or not GEAR_COSTS.has(item):
        return
    if GEAR_COSTS.has(item):
        var cost := int(GEAR_COSTS[item])
        if credits < cost:
            _notify(peer_id, "团队回收点数不足：%s 需要 %d 点。" % [GEAR_NAMES[item], cost])
            return
        credits -= cost
        gear_stock[item] = int(gear_stock.get(item, 0)) + 1
        _notify(peer_id, "星际集市交易完成：%s 已加入共享装备仓。" % GEAR_NAMES[item])
    broadcast()

func _show_for_peer(peer_id: int, facility: String) -> void:
    if peer_id == 1:
        show_facility(facility)
    else:
        show_facility.rpc_id(peer_id, facility)

@rpc("authority", "call_remote", "reliable")
func show_facility(facility: String) -> void:
    if not active or facility != "mission":
        return
    show_computer("mission")

func _refresh_panel() -> void:
    if _computer != null and _computer.visible:
        _computer.refresh()
    if not _panel.visible:
        return
    _title.text = "航行记录"
    _body.text = last_report
    _body.size.y = 310
    _body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _message.text = "Esc 返回"

func _notify(peer_id: int, message: String) -> void:
    if peer_id == 1:
        show_notice(message)
    else:
        show_notice.rpc_id(peer_id, message)

@rpc("authority", "call_remote", "reliable")
func show_notice(message: String) -> void:
    _notice = message
    _notice_remaining = 4.0 if not message.is_empty() else 0.0
    _message.text = message
    if controller._screen_view == "trade":
        controller._refresh_trade_buttons()

@rpc("authority", "call_local", "reliable")
func switch_area(to_hub: bool) -> void:
    if not active or in_hub == to_hub:
        return
    _clear_departure()
    if controller.is_host:
        for peer_id: int in controller.players:
            if to_hub:
                controller._items.finish_training(peer_id)
            else:
                controller._items.start_training(peer_id)
    in_hub = to_hub
    _opened_computers.clear()
    _hub_training_arrival = to_hub
    _notice = ""
    _notice_remaining = 0.0
    remove_child(room)
    room.queue_free()
    _build_room()
    for id in controller.players:
        var player := controller.players[id] as SpacePlayer3D
        player.teleport_to(spawn_position(id))
        player.configure_ship_camera()
    show_gameplay()
    if controller.is_host:
        broadcast()
        controller.sync_vitals.rpc(controller._vitals_snapshot(), true)

func all_ready() -> bool:
    if controller.connected_ids.is_empty():
        return false
    for id in controller.connected_ids:
        if not ready_peers.has(id) or not station_owners.values().has(id):
            return false
    return true

func confirm_land() -> void:
    if controller.is_host and active and in_hub and hull >= 60 and all_ready():
        for slot: int in station_owners:
            var player: SpacePlayer3D = controller.players.get(int(station_owners[slot])) as SpacePlayer3D
            if player == null or controller._flat_distance(player.position, ShipDevices3D.point_for("pilot_%d" % slot)) > 2.65:
                return
        if campaign.enabled:
            controller._campaign_travel.begin_destination(selected_destination)
        else:
            controller.start_planet(selected_destination)

func select_destination(destination: String) -> void:
    if not controller.is_host or destination not in ["demo", "electromagnetic", "ruin", "earth"]:
        return
    if campaign.enabled and not campaign.debug_free_destination and not campaign.block_reason(destination).is_empty():
        return
    selected_destination = destination
    if campaign.enabled:
        campaign.revision += 1
    _clear_departure()
    broadcast()

func add_peer(peer_id: int) -> void:
    if not packs.has(peer_id):
        packs[peer_id] = {"medical": 0, "oxygen": 0}
    _clear_departure()
    controller._items.ensure_bag(peer_id)
    if not in_hub:
        controller._items.start_training(peer_id)
    enter_ship.rpc_id(peer_id, in_hub, controller.connected_ids, snapshot(), controller._vitals_snapshot())
    controller.spawn_player_for_peer.rpc(peer_id)
    if not in_hub and controller.players.has(peer_id):
        (controller.players[peer_id] as SpacePlayer3D).health = 5
        controller.sync_vitals.rpc(controller._vitals_snapshot(), true)
    broadcast()

func remove_peer(peer_id: int) -> void:
    if controller.is_host:
        var bag: Dictionary = controller._items.real_counts(peer_id)
        keep_oxygen_levels(controller._items.real_oxygen_levels(peer_id))
        for item in ["medical", "oxygen"]:
            stock[item] = int(stock[item]) + int(bag.get(item, 0))
        packs.erase(peer_id)
        controller._items.remove_peer(peer_id)
        packs.erase(peer_id)
        training.erase(peer_id)
        _clear_departure()
        _exit_armed.erase(peer_id)
        _opened_computers.erase(peer_id)
        broadcast()

func settle(success: bool, value: int, report: String) -> void:
    credits += maxi(value, 0)
    hull = maxi(hull - (8 if success else 20), 40)
    # 应急零件避免库存耗尽后无法再出发；正常维修仍消耗共享库存。
    stock.parts = maxi(int(stock.parts), 1)
    last_report = report + "\n本次入库：%d 回收点数。" % maxi(value, 0)
    _clear_departure()
    save_state()

func snapshot() -> Dictionary:
    return {"campaign": campaign.snapshot(), "oxygen_levels": oxygen_levels.duplicate(), "items": controller._items.snapshot() if controller._items != null else {}, "stock": stock.duplicate(true), "packs": packs.duplicate(true), "ready": ready_peers.duplicate(), "station_owners": station_owners.duplicate(), "launch_remaining": launch_remaining, "training": training.duplicate(true), "hull": hull, "credits": credits, "last_report": last_report, "goofy_stock": goofy_stock.duplicate(true), "goofy_assignments": goofy_assignments.duplicate(true), "gear_stock": gear_stock.duplicate(true), "gear_assignments": gear_assignments.duplicate(true), "planet_states": planet_states.duplicate(true), "selected_destination": selected_destination}

func apply_state(state: Dictionary) -> void:
    if state.has("campaign"):
        campaign.apply(state.campaign)
    oxygen_levels = state.get("oxygen_levels", oxygen_levels).duplicate()
    stock = state.get("stock", stock).duplicate(true)
    packs = state.get("packs", packs).duplicate(true)
    ready_peers.assign(state.get("ready", []))
    station_owners = state.get("station_owners", {}).duplicate()
    launch_remaining = float(state.get("launch_remaining", -1.0))
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
    if controller._items != null and state.has("items"):
        controller._items.apply_state(state.items)
    _refresh_panel()
    if active and not in_hub and room != null:
        (room as ShipTutorial3D).show_step(int(training.get(multiplayer.get_unique_id(), 0)))

@rpc("authority", "call_local", "reliable")
func sync_state(state: Dictionary) -> void:
    apply_state(state)

func broadcast() -> void:
    if not controller.is_host:
        return
    var state: Dictionary = snapshot()
    apply_state(state)
    if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
        var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
        for peer_id: int in multiplayer.get_peers():
            var peer: ENetPacketPeer = enet.get_peer(peer_id)
            if peer != null and peer.get_state() == ENetPacketPeer.STATE_CONNECTED and peer.get_channels() > 0:
                sync_state.rpc_id(peer_id, state)
    save_state()

func close_room() -> void:
    if campaign.enabled:
        save_state()
        controller._items.clear_session()
        return
    for peer_id: int in controller._items.bags:
        var counts: Dictionary = controller._items.real_counts(peer_id)
        keep_oxygen_levels(controller._items.real_oxygen_levels(peer_id))
        for kind: String in ["medical", "oxygen"]:
            stock[kind] = int(stock[kind]) + int(counts[kind])
    for entry: Dictionary in controller._items.drops:
        var kind: String = String(entry.get("kind", ""))
        if entry.get("area", "") != "training" and kind in ["medical", "oxygen"]:
            stock[kind] = int(stock[kind]) + 1
            if kind == "oxygen":
                keep_oxygen_levels([float(entry.get("oxygen", 100.0))])
    packs.clear()
    controller._items.clear_session()
    save_state()

func save_state() -> void:
    if not persistence_enabled or not controller.is_host:
        return
    if campaign.enabled:
        _save_campaign()
        return
    var saved_stock: Dictionary = stock.duplicate(true)
    var saved_levels: Array = oxygen_levels.duplicate()
    # 关闭房间时，携带物资归还库存，下一次房间不依赖临时网络 ID。
    for peer_id: int in packs:
        var bag: Dictionary = controller._items.real_counts(peer_id) if controller._items != null else packs[peer_id]
        if controller._items != null:
            for amount: Variant in controller._items.real_oxygen_levels(peer_id):
                if float(amount) < 99.999:
                    saved_levels.append(float(amount))
        for item in ["medical", "oxygen"]:
            saved_stock[item] = int(saved_stock[item]) + int(bag.get(item, 0))
    if controller._items != null:
        for entry: Dictionary in controller._items.drops:
            if entry.get("area", "") != "training" and entry.get("kind", "") in ["medical", "oxygen"]:
                var kind: String = String(entry.kind)
                saved_stock[kind] = int(saved_stock[kind]) + 1
                if kind == "oxygen" and float(entry.get("oxygen", 100.0)) < 99.999:
                    saved_levels.append(float(entry.get("oxygen", 100.0)))
    var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify({"version": 4, "oxygen_levels": saved_levels, "stock": saved_stock, "hull": hull, "credits": credits, "last_report": last_report, "goofy_stock": goofy_stock, "goofy_assignments": goofy_assignments, "gear_stock": gear_stock, "gear_assignments": gear_assignments, "planet_states": planet_states}, "  "))
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
    if not data is Dictionary or int(data.get("version", 0)) not in [1, 2, 3, 4]:
        return
    var saved_stock = data.get("stock", {})
    if not saved_stock is Dictionary:
        return
    for item in ITEM_NAMES:
        stock[item] = clampi(int(saved_stock.get(item, stock[item])), 0, 9999)
    oxygen_levels.clear()
    var loaded_levels: Variant = data.get("oxygen_levels", [])
    if loaded_levels is Array:
        for amount: Variant in loaded_levels:
            if typeof(amount) in [TYPE_FLOAT, TYPE_INT] and oxygen_levels.size() < int(stock.oxygen):
                var level: float = clampf(float(amount), 0.0, 100.0)
                if level < 99.999:
                    oxygen_levels.append(level)
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
    if controller._items != null:
        controller._items.clear_session()
    training.clear()
    _clear_departure()

func reset_campaign() -> void:
    campaign.start_new()
    save_path = CAMPAIGN_SAVE_PATH
    stock = {"medical": 8, "oxygen": 8, "parts": 6}
    oxygen_levels.clear()
    packs.clear()
    planet_states.clear()
    gear_stock = {"thermal_suit": 0, "wide_scanner": 0, "signal_stabilizer": 0}
    gear_assignments.clear()
    goofy_assignments.clear()
    hull = 80
    credits = 0
    selected_destination = ""
    training.clear()
    _clear_departure()
    controller._items.clear_session()
    last_report = "飞船紧急坠落在霜烬星 · 核心损坏，普通燃料尚有储备。\n出舱探索科考站与冰下遗迹，寻找替代能源。"

func _save_campaign() -> void:
    var state: Dictionary = snapshot()
    if controller._campaign_travel != null:
        state.items = controller._campaign_travel.active_items()
    for peer_id: int in state.items.training_saved:
        state.items.bags[peer_id] = state.items.training_saved[peer_id].bag.duplicate(true)
    state.items.training_saved = {}
    state.ready = []
    state.station_owners = {}
    state.launch_remaining = -1.0
    var encoded: String = Marshalls.raw_to_base64(var_to_bytes(state))
    var file: FileAccess = FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
    if file == null:
        return
    file.store_string(JSON.stringify({"version": 1, "payload": encoded, "checksum": encoded.sha256_text()}))
    file.close()
    var error: Error = DirAccess.rename_absolute(save_path + ".tmp", save_path)
    if error != OK:
        show_notice("航程未能保存 · 请检查存储空间")

func load_campaign() -> bool:
    if not FileAccess.file_exists(save_path):
        return false
    var parser: JSON = JSON.new()
    if parser.parse(FileAccess.get_file_as_string(save_path)) != OK:
        return false
    var data: Variant = parser.data
    if not data is Dictionary or data.get("version", 0) != 1 or not data.get("payload", "") is String:
        return false
    var encoded: String = data.payload
    if encoded.is_empty() or encoded.sha256_text() != data.get("checksum", ""):
        return false
    var raw: PackedByteArray = Marshalls.base64_to_raw(encoded)
    if raw.size() < 4:
        return false
    var state: Variant = bytes_to_var(raw)
    if not state is Dictionary or not state.get("campaign", {}) is Dictionary or not state.campaign.get("enabled", false) or not state.get("items", {}) is Dictionary:
        return false
    apply_state(state)
    # Network peer IDs change between rooms. Preserve the host's loadout and
    # return other saved crew loadouts as physical items in the shared cabin.
    for peer_id: int in controller._items.bags.keys():
        if peer_id == 1:
            continue
        var bag: Dictionary = controller._items.bags[peer_id]
        for item: Dictionary in bag.slots + bag.get("equipment", []):
            if item.is_empty():
                continue
            var entry: Dictionary = item.duplicate(true)
            entry.uid = "restored_%d" % controller._items.next_uid
            controller._items.next_uid += 1
            entry.area = "hub"
            entry.position = Vector3(-15, 1.2, 8)
            entry.rotation = Vector3.ZERO
            controller._items.drops.append(entry)
        controller._items.bags.erase(peer_id)
    packs.clear()
    training.clear()
    _clear_departure()
    return true

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
    return controller._items.equipment_index(peer_id, item_id) >= 0 if controller._items != null else false

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
