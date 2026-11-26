extends Node
class_name CampaignTravel3D

var controller: Main3D
var frost: Node3D
var _checkpoint_clock: float = 0.0
var _transitioning: bool = false
var generation: int = 0

func setup(owner_controller: Main3D) -> void:
    controller = owner_controller

func tick(delta: float) -> void:
    if frost == null or not controller.is_host:
        return
    _checkpoint_clock += delta
    if _checkpoint_clock >= 5.0:
        _checkpoint_clock = 0.0
        checkpoint()
        controller._ship_session.save_state()

func checkpoint() -> void:
    if frost == null:
        return
    var state: Dictionary = frost.snapshot()
    state.actors = {}
    state.items.bags = {}
    controller._ship_session.campaign.frost_world = state
    controller._ship_session.campaign.accept_frost(frost.campaign_result())

func active_items() -> Dictionary:
    var state: Dictionary = controller._items.snapshot()
    if frost != null:
        state.bags = frost._items.bags.duplicate(true)
    return state

func open_surface() -> void:
    var session: ShipSession3D = controller._ship_session
    if not controller.is_host or _transitioning or not session.active or not session.in_hub or not session.campaign.enabled:
        return
    if session.campaign.location != "demo" or not session.campaign.grounded or session.campaign.home_reached:
        session.show_notice("当前没有停靠在霜烬星地面 · 请先规划航线")
        return
    enter_frost.rpc(controller.connected_ids, session.snapshot(), generation + 1)

@rpc("authority", "call_local", "reliable")
func enter_frost(ids: Array, ship_state: Dictionary, epoch: int) -> void:
    if frost != null:
        return
    generation = epoch
    var session: ShipSession3D = controller._ship_session
    session.apply_state(ship_state)
    session.leave()
    controller._clear_players()
    controller.game_started = false
    controller._menu_layer.visible = false
    controller._game_layer.visible = false
    session.disable_menu_environment()
    controller._items._clear_held()
    controller._items.set_process(false)
    controller._items.set_physics_process(false)
    controller._items._layer.visible = false
    frost = load("res://previews/frost_station/adventure.gd").new() as Node3D
    frost.embedded = true
    frost.name = "FrostAdventure"
    add_child(frost)
    frost.board_requested.connect(_on_board_requested)
    frost.begin_embedded(controller.is_host, ids, session.campaign.frost_world, controller._items.snapshot())
    if not controller.is_host:
        surface_ready.rpc_id(1, generation)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    _transitioning = false

func add_peer(peer_id: int) -> void:
    if frost == null or not controller.is_host:
        return
    frost.spawn_actor(peer_id, true)
    checkpoint()
    # Establish the identical RPC node path before its first world snapshot.
    enter_frost.rpc_id(peer_id, controller.connected_ids, controller._ship_session.snapshot(), generation)

@rpc("any_peer", "call_remote", "reliable")
func surface_ready(epoch: int) -> void:
    var peer_id: int = multiplayer.get_remote_sender_id()
    if not controller.is_host or frost == null or epoch != generation or not controller.connected_ids.has(peer_id):
        return
    if not frost.embedded_ready.has(peer_id):
        frost.embedded_ready.append(peer_id)
    publish_surface(peer_id, frost.snapshot())

func publish_surface(peer_id: int, state: Dictionary) -> void:
    surface_state.rpc_id(peer_id, generation, state)

@rpc("authority", "call_remote", "reliable")
func surface_state(epoch: int, state: Dictionary) -> void:
    if frost != null and generation == epoch and not controller.is_host:
        frost.apply_frost_state(state)

func send_surface_controls(packet: Dictionary) -> void:
    surface_controls.rpc_id(1, generation, packet)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func surface_controls(epoch: int, packet: Dictionary) -> void:
    var peer_id: int = multiplayer.get_remote_sender_id()
    if controller.is_host and frost != null and epoch == generation and not _transitioning and controller.connected_ids.has(peer_id):
        frost.accept_controls(peer_id, packet)

func send_surface_action(action: String) -> void:
    surface_action.rpc_id(1, generation, action)

@rpc("any_peer", "call_remote", "reliable")
func surface_action(epoch: int, action: String) -> void:
    var peer_id: int = multiplayer.get_remote_sender_id()
    if controller.is_host and frost != null and epoch == generation and not _transitioning and controller.connected_ids.has(peer_id):
        frost.handle_action(peer_id, action)

func remove_peer(peer_id: int) -> void:
    if frost != null:
        frost.embedded_ready.erase(peer_id)
        frost._left(peer_id)
        if controller.is_host:
            checkpoint()
            controller._ship_session.save_state()

func _on_board_requested(_peer_id: int) -> void:
    if not controller.is_host or frost == null or _transitioning:
        return
    for actor: SpacePlayer3D in frost.players.values():
        if not actor.downed and Vector2(actor.position.x, actor.position.z - 8).length() > 24.0:
            frost.show_notice("请全员回到停机坪飞船附近，再一起进舱")
            return
    _transitioning = true
    _board_team.call_deferred()

func _board_team() -> void:
    checkpoint()
    var session: ShipSession3D = controller._ship_session
    controller._items.apply_state(active_items())
    session.last_report = "已回到霜烬星上的飞船。\n" + ("核心已修复 · 在航线电脑规划下一站，再到驾驶席就位。" if session.campaign.navigation_restored else "核心损坏 · 出舱前往科考站寻找替代能源。")
    board_team.rpc(session.snapshot(), generation + 1)

@rpc("authority", "call_local", "reliable")
func board_team(ship_state: Dictionary, epoch: int) -> void:
    generation = epoch
    stop_frost()
    controller._items.set_process(true)
    controller._items.set_physics_process(true)
    controller._items._layer.visible = true
    controller._ship_session.enter_ship(true, controller.connected_ids, ship_state)
    _transitioning = false
    if controller.is_host:
        controller._ship_session.broadcast()

func stop_frost() -> void:
    if frost == null:
        return
    frost.set_process(false)
    frost.set_physics_process(false)
    remove_child(frost)
    frost.queue_free()
    frost = null
    controller._items.set_process(true)
    controller._items.set_physics_process(true)
    controller._items._layer.visible = true

func tick_ruin(delta: float) -> void:
    var local: SpacePlayer3D = controller.players.get(multiplayer.get_unique_id()) as SpacePlayer3D
    if local != null:
        controller._compass_label.text = "腐墟星"
        controller._progress_label.text = "搜刮物资后回登陆点撤回\n已搜刮 %d / %d · 归航物资全队共享" % [controller._ruin_planet.taken_food.size(), RuinPlanet.FOOD_SITES.size()]
        controller._side_quest_panel.visible = false
        controller._vitals_label.text = "生命 %d / 5" % local.health
        controller._hint_label.text = "WASD 移动 · E 搜刮 · J 日志 · M 地图"
        controller._interaction_panel.visible = true
        var returning: bool = controller._flat_distance(local.position, Vector3(RuinPlanet.SPAWN_POSITION.x, 0, RuinPlanet.SPAWN_POSITION.y)) < 4.0
        controller._interaction_label.text = "E 返回飞船 · 带回已搜刮物资" if returning else controller._ruin_planet.prompt(local)
    if controller.is_host:
        controller._tick_revive(delta)
        var standing: bool = false
        for actor: SpacePlayer3D in controller.players.values():
            standing = standing or not actor.downed
        if not standing and not controller.players.is_empty():
            controller.mission_failed = true
            controller.return_to_ship.rpc("全队已撤回飞船 · 装备保留")

func ruin_return(peer_id: int) -> bool:
    var actor: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if actor == null or actor.downed or not controller.is_host:
        return false
    var origin: Vector3 = Vector3(RuinPlanet.SPAWN_POSITION.x, 0, RuinPlanet.SPAWN_POSITION.y)
    if controller._flat_distance(actor.position, origin) >= 4.0:
        return false
    for mate: SpacePlayer3D in controller.players.values():
        if not mate.downed and controller._flat_distance(mate.position, origin) > 8.0:
            controller._ship_session._notify(peer_id, "请全员回登陆点，再一起撤回飞船")
            return true
    controller.mission_completed = true
    controller.return_to_ship.rpc("腐墟星搜刮结束 · 已回到轨道主舱")
    return true

func begin_destination(destination: String) -> void:
    var session: ShipSession3D = controller._ship_session
    if not session.campaign.depart(destination):
        return
    session._clear_departure()
    if destination == "demo":
        enter_frost.rpc(controller.connected_ids, session.snapshot(), generation + 1)
    elif destination == "earth":
        home_arrival.rpc(session.snapshot())
    else:
        session.broadcast()
        controller.start_planet(destination)

@rpc("authority", "call_local", "reliable")
func home_arrival(ship_state: Dictionary) -> void:
    controller._ship_session.enter_ship(true, controller.connected_ids, ship_state)
    controller._ship_session.last_report = "归航完成 · 船员们带着能源、物资与星系见闻回到地球。"
    controller._ship_session.show_notice("已返回地球 · 航行完成")
    controller._ship_session.show_computer("mission")
    if controller.is_host:
        controller._ship_session.broadcast()
