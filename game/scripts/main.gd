extends Node2D

const PORT := 24567
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const DEMO_STAGE_SCENE := preload("res://scenes/demo_stage.tscn")
const DEMO_BEACON_SCENE := preload("res://scenes/demo_beacon.tscn")
const POWER_NODE_SCENE := preload("res://scenes/power_node.tscn")
const DEMO_BEACON_POSITIONS := [Vector2(185, 255), Vector2(500, 520), Vector2(790, 285)]
const POWER_NODE_POSITIONS := [Vector2(210, 235), Vector2(505, 455), Vector2(785, 260)]
const PLAYER_COLORS := [
    Color("#61dafb"), Color("#ffcf5c"), Color("#ff6b8a"), Color("#a78bfa")
]

var players: Dictionary = {}
var connected_ids: Array[int] = []
var current_stage := "ship"
var is_host := false
var lobby_panel: PanelContainer
var status_label: Label
var player_list_label: Label
var address_edit: LineEdit
var host_button: Button
var join_button: Button
var stage_button: Button
var leave_button: Button
var stage_title: Label
var stage_hint: Label
var stage_badge: Label
var progress_label: Label
var _world_bodies: Node2D
var _demo_stage: Node2D
var _demo_beacons_root: Node2D
var _power_nodes_root: Node2D
var demo_beacons: Dictionary = {}
var activated_demo_beacon_ids: Array[int] = []
var power_nodes: Dictionary = {}
var activated_node_ids: Array[int] = []

func _ready() -> void:
    _build_world()
    _build_demo_stage()
    _build_demo_beacons()
    _build_power_nodes()
    _build_ui()
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(0, 0, 1280, 720), Color("#07101f"))
    draw_rect(Rect2(24, 24, 950, 672), Color("#0d1b2e"), true)
    for x in range(48, 950, 48):
        draw_line(Vector2(x, 120), Vector2(x, 690), Color(0.15, 0.28, 0.40, 0.18), 1.0)
    for y in range(144, 690, 48):
        draw_line(Vector2(30, y), Vector2(965, y), Color(0.15, 0.28, 0.40, 0.18), 1.0)
    draw_rect(Rect2(30, 120, 915, 570), Color("#16314a"), false, 3.0)
    if current_stage == "electromagnetic":
        draw_rect(Rect2(48, 138, 879, 534), Color(0.15, 0.55, 0.75, 0.07), true)
        draw_string(ThemeDB.fallback_font, Vector2(72, 650), "电磁干扰区 · 激活全部电力节点以恢复设备", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#61dafb"))

func _build_world() -> void:
    _world_bodies = Node2D.new()
    _world_bodies.name = "WorldCollision"
    add_child(_world_bodies)
    _make_wall("TopWall", Vector2(487.5, 120.0), Vector2(915.0, 20.0))
    _make_wall("BottomWall", Vector2(487.5, 690.0), Vector2(915.0, 20.0))
    _make_wall("LeftWall", Vector2(30.0, 405.0), Vector2(20.0, 570.0))
    _make_wall("RightWall", Vector2(945.0, 405.0), Vector2(20.0, 570.0))

func _make_wall(wall_name: String, center: Vector2, size: Vector2) -> void:
    var body := StaticBody2D.new()
    body.name = wall_name
    body.collision_layer = 2
    body.collision_mask = 1
    var shape := CollisionShape2D.new()
    var rectangle := RectangleShape2D.new()
    rectangle.size = size
    shape.shape = rectangle
    body.position = center
    body.add_child(shape)
    _world_bodies.add_child(body)

func _build_demo_stage() -> void:
    _demo_stage = DEMO_STAGE_SCENE.instantiate()
    add_child(_demo_stage)
    move_child(_demo_stage, 0)
    _demo_stage.visible = false

func _build_demo_beacons() -> void:
    _demo_beacons_root = Node2D.new()
    _demo_beacons_root.name = "DemoPlanetBeacons"
    add_child(_demo_beacons_root)
    for index in DEMO_BEACON_POSITIONS.size():
        var beacon := DEMO_BEACON_SCENE.instantiate()
        var beacon_id := index + 1
        beacon.setup(beacon_id, "示范信标 %d" % beacon_id)
        beacon.position = DEMO_BEACON_POSITIONS[index]
        _demo_beacons_root.add_child(beacon)
        demo_beacons[beacon_id] = beacon
    _demo_beacons_root.visible = false

func _build_power_nodes() -> void:
    _power_nodes_root = Node2D.new()
    _power_nodes_root.name = "ElectromagneticPowerNodes"
    add_child(_power_nodes_root)
    for index in POWER_NODE_POSITIONS.size():
        var node := POWER_NODE_SCENE.instantiate() as PowerNode
        var node_id := index + 1
        node.setup(node_id, "节点 %d" % node_id)
        node.position = POWER_NODE_POSITIONS[index]
        _power_nodes_root.add_child(node)
        power_nodes[node_id] = node
    _power_nodes_root.visible = false

func get_nearest_power_node_id(player_position: Vector2) -> int:
    if current_stage != "electromagnetic":
        return -1
    var nearest_id := -1
    var nearest_distance := 96.0
    for node_id in power_nodes:
        if activated_node_ids.has(node_id):
            continue
        var node := power_nodes[node_id] as PowerNode
        var distance := player_position.distance_to(node.position)
        if distance <= nearest_distance:
            nearest_distance = distance
            nearest_id = node_id
    return nearest_id

func get_nearest_interaction_id(player_position: Vector2) -> int:
    if current_stage == "demo":
        return get_nearest_demo_beacon_id(player_position)
    if current_stage == "electromagnetic":
        return get_nearest_power_node_id(player_position)
    return -1

func get_nearest_demo_beacon_id(player_position: Vector2) -> int:
    if current_stage != "demo":
        return -1
    var nearest_id := -1
    var nearest_distance := 96.0
    for beacon_id in demo_beacons:
        if activated_demo_beacon_ids.has(beacon_id):
            continue
        var beacon = demo_beacons[beacon_id]
        var distance := player_position.distance_to(beacon.position)
        if distance <= nearest_distance:
            nearest_distance = distance
            nearest_id = beacon_id
    return nearest_id

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.name = "Interface"
    add_child(layer)

    stage_title = Label.new()
    stage_title.position = Vector2(52, 38)
    stage_title.add_theme_font_size_override("font_size", 27)
    stage_title.text = "迷失太空 · 联机工程测试"
    layer.add_child(stage_title)

    stage_badge = Label.new()
    stage_badge.position = Vector2(52, 82)
    stage_badge.add_theme_color_override("font_color", Color("#61dafb"))
    stage_badge.add_theme_font_size_override("font_size", 17)
    layer.add_child(stage_badge)

    stage_hint = Label.new()
    stage_hint.position = Vector2(52, 103)
    stage_hint.add_theme_color_override("font_color", Color("#9fb4c8"))
    stage_hint.text = "连接后使用 WASD / 方向键移动；玩家会在所有实例中同步显示。"
    layer.add_child(stage_hint)

    progress_label = Label.new()
    progress_label.position = Vector2(690, 82)
    progress_label.add_theme_color_override("font_color", Color("#8be28b"))
    progress_label.add_theme_font_size_override("font_size", 16)
    layer.add_child(progress_label)

    lobby_panel = PanelContainer.new()
    lobby_panel.position = Vector2(990, 34)
    lobby_panel.size = Vector2(266, 650)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color("#10243a")
    panel_style.border_color = Color("#2c5674")
    panel_style.set_border_width_all(2)
    panel_style.corner_radius_top_left = 10
    panel_style.corner_radius_top_right = 10
    panel_style.corner_radius_bottom_left = 10
    panel_style.corner_radius_bottom_right = 10
    lobby_panel.add_theme_stylebox_override("panel", panel_style)
    layer.add_child(lobby_panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_top", 18)
    margin.add_theme_constant_override("margin_bottom", 18)
    lobby_panel.add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    margin.add_child(column)

    var title := Label.new()
    title.text = "第一周联机大厅"
    title.add_theme_font_size_override("font_size", 20)
    column.add_child(title)

    var rule := HSeparator.new()
    column.add_child(rule)

    var ip_label := Label.new()
    ip_label.text = "主机 IP（加入时填写）"
    ip_label.add_theme_color_override("font_color", Color("#9fb4c8"))
    column.add_child(ip_label)
    address_edit = LineEdit.new()
    address_edit.placeholder_text = "127.0.0.1"
    address_edit.text = "127.0.0.1"
    column.add_child(address_edit)

    host_button = Button.new()
    host_button.text = "创建主机"
    host_button.custom_minimum_size.y = 38
    host_button.pressed.connect(_create_host)
    column.add_child(host_button)

    join_button = Button.new()
    join_button.text = "加入主机"
    join_button.custom_minimum_size.y = 38
    join_button.pressed.connect(_join_host)
    column.add_child(join_button)

    status_label = Label.new()
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status_label.custom_minimum_size.y = 62
    status_label.add_theme_color_override("font_color", Color("#ffcf5c"))
    column.add_child(status_label)

    var people_title := Label.new()
    people_title.text = "当前玩家"
    people_title.add_theme_font_size_override("font_size", 16)
    column.add_child(people_title)

    player_list_label = Label.new()
    player_list_label.custom_minimum_size.y = 100
    player_list_label.add_theme_color_override("font_color", Color("#d5e7f7"))
    column.add_child(player_list_label)

    stage_button = Button.new()
    stage_button.text = "进入示范星球"
    stage_button.disabled = true
    stage_button.pressed.connect(_toggle_stage)
    column.add_child(stage_button)

    leave_button = Button.new()
    leave_button.text = "断开并返回大厅"
    leave_button.disabled = true
    leave_button.pressed.connect(_leave_network)
    column.add_child(leave_button)

    var footer := Label.new()
    footer.text = "端口 %d · 上限 %d 人\n成员1：联机 / 架构 / 整合" % [PORT, MAX_PLAYERS]
    footer.add_theme_color_override("font_color", Color("#708ca4"))
    column.add_child(footer)

    status_label.text = "状态：尚未连接。请创建主机或加入现有主机。"
    _update_stage_text()
    _update_progress_text()
    _update_player_list()

func _has_active_peer() -> bool:
    return multiplayer.multiplayer_peer is ENetMultiplayerPeer

func _create_host() -> void:
    if _has_active_peer():
        return
    var peer := ENetMultiplayerPeer.new()
    var result := peer.create_server(PORT, MAX_PLAYERS - 1)
    if result != OK:
        _set_status("创建主机失败：%s" % error_string(result), Color("#ff6b8a"))
        return
    is_host = true
    multiplayer.multiplayer_peer = peer
    connected_ids = [1]
    _spawn_player(1)
    _set_connected_ui(true)
    _set_status("主机已创建：等待其他玩家加入。把本机局域网 IP 告诉队友。", Color("#8be28b"))
    _update_player_list()

func _join_host() -> void:
    if _has_active_peer():
        return
    var address := address_edit.text.strip_edges()
    if address.is_empty():
        address = "127.0.0.1"
    var peer := ENetMultiplayerPeer.new()
    var result := peer.create_client(address, PORT)
    if result != OK:
        _set_status("连接失败：%s" % error_string(result), Color("#ff6b8a"))
        return
    is_host = false
    multiplayer.multiplayer_peer = peer
    _set_connected_ui(true)
    _set_status("正在连接 %s:%d…" % [address, PORT], Color("#ffcf5c"))

func _on_connected_to_server() -> void:
    _set_status("已加入主机，等待玩家列表…", Color("#8be28b"))

func _on_connection_failed() -> void:
    _set_status("连接失败：请检查 IP、防火墙和端口 %d。" % PORT, Color("#ff6b8a"))
    _leave_network()

func _on_server_disconnected() -> void:
    _clear_players()
    _set_status("主机已断开，其他玩家已返回大厅。", Color("#ff6b8a"))
    _set_connected_ui(false)

func _on_peer_connected(peer_id: int) -> void:
    if not is_host:
        return
    if not connected_ids.has(peer_id):
        connected_ids.append(peer_id)
    spawn_player_for_peer.rpc(peer_id)
    var existing := connected_ids.duplicate()
    existing.erase(peer_id)
    if not existing.is_empty():
        spawn_existing_players.rpc_id(peer_id, existing)
    var active_state: Array[int] = activated_demo_beacon_ids if current_stage == "demo" else activated_node_ids
    sync_shared_state.rpc_id(peer_id, current_stage, active_state)
    _set_status("玩家 %d 已加入。" % peer_id, Color("#8be28b"))
    _update_player_list()

func _on_peer_disconnected(peer_id: int) -> void:
    connected_ids.erase(peer_id)
    despawn_player.rpc(peer_id)
    _set_status("玩家 %d 已断开。" % peer_id, Color("#ffcf5c"))
    _update_player_list()

@rpc("authority", "call_local", "reliable")
func spawn_player_for_peer(peer_id: int) -> void:
    if not connected_ids.has(peer_id):
        connected_ids.append(peer_id)
    _spawn_player(peer_id)
    _update_player_list()

@rpc("authority", "reliable")
func spawn_existing_players(peer_ids: Array) -> void:
    for peer_id in peer_ids:
        var id := int(peer_id)
        if not connected_ids.has(id):
            connected_ids.append(id)
        _spawn_player(id)
    _update_player_list()

@rpc("authority", "call_local", "reliable")
func despawn_player(peer_id: int) -> void:
    connected_ids.erase(peer_id)
    if players.has(peer_id):
        players[peer_id].queue_free()
        players.erase(peer_id)
    _update_player_list()

func _spawn_player(peer_id: int) -> void:
    if players.has(peer_id):
        return
    var player := PLAYER_SCENE.instantiate() as NetworkPlayer
    player.setup(peer_id, PLAYER_COLORS[(peer_id - 1) % PLAYER_COLORS.size()])
    player.position = _spawn_position(peer_id)
    add_child(player)
    players[peer_id] = player

func _spawn_position(peer_id: int) -> Vector2:
    if current_stage == "demo" and _demo_stage:
        return _demo_stage.get_spawn_position(peer_id - 1)
    var slots := [Vector2(175, 270), Vector2(315, 270), Vector2(455, 270), Vector2(595, 270)]
    return slots[(peer_id - 1) % slots.size()]

func _toggle_stage() -> void:
    if not is_host:
        _set_status("只有主机可以切换测试阶段。", Color("#ffcf5c"))
        return
    change_stage.rpc("demo" if current_stage == "ship" else "ship")

func activate_interaction_from_peer(peer_id: int, interaction_id: int) -> void:
    if current_stage == "demo":
        activate_demo_beacon_from_peer(peer_id, interaction_id)
    elif current_stage == "electromagnetic":
        activate_power_node_from_peer(peer_id, interaction_id)

@rpc("any_peer", "reliable")
func request_activate_interaction(interaction_id: int) -> void:
    if not is_host:
        return
    activate_interaction_from_peer(multiplayer.get_remote_sender_id(), interaction_id)

func activate_demo_beacon_from_peer(peer_id: int, beacon_id: int) -> void:
    if not is_host or current_stage != "demo":
        return
    if not demo_beacons.has(beacon_id) or activated_demo_beacon_ids.has(beacon_id):
        return
    if peer_id != 1 and not players.has(peer_id):
        return
    var player := players.get(peer_id) as NetworkPlayer
    if player == null or player.position.distance_to(demo_beacons[beacon_id].position) > 104.0:
        _set_status("玩家 %d 需要靠近示范信标才能扫描。" % peer_id, Color("#ffcf5c"))
        return
    set_demo_beacon_state.rpc(beacon_id, true, peer_id)

@rpc("authority", "call_local", "reliable")
func set_demo_beacon_state(beacon_id: int, active: bool, scanning_peer: int) -> void:
    if not demo_beacons.has(beacon_id):
        return
    var beacon = demo_beacons[beacon_id]
    beacon.set_active(active)
    if active and not activated_demo_beacon_ids.has(beacon_id):
        activated_demo_beacon_ids.append(beacon_id)
    elif not active:
        activated_demo_beacon_ids.erase(beacon_id)
    _update_progress_text()
    if activated_demo_beacon_ids.size() >= demo_beacons.size():
        _set_status("示范星球目标完成：三个信标已扫描，可以接入资源和撤离系统。", Color("#8be28b"))
    elif active:
        _set_status("玩家 %d 已扫描示范信标 %d。" % [scanning_peer, beacon_id], Color("#8be28b"))

func _reset_demo_beacons_local() -> void:
    activated_demo_beacon_ids.clear()
    for beacon in demo_beacons.values():
        beacon.set_active(false)
    _update_progress_text()

func activate_power_node_from_peer(peer_id: int, node_id: int) -> void:
    if not is_host or current_stage != "electromagnetic":
        return
    if not power_nodes.has(node_id) or activated_node_ids.has(node_id):
        return
    if peer_id != 1 and not players.has(peer_id):
        return
    var player := players.get(peer_id) as NetworkPlayer
    if player == null or player.position.distance_to((power_nodes[node_id] as PowerNode).position) > 104.0:
        _set_status("玩家 %d 需要靠近节点才能激活。" % peer_id, Color("#ffcf5c"))
        return
    set_power_node_state.rpc(node_id, true, peer_id)

@rpc("any_peer", "reliable")
func request_activate_power_node(node_id: int) -> void:
    if not is_host:
        return
    activate_power_node_from_peer(multiplayer.get_remote_sender_id(), node_id)

@rpc("authority", "call_local", "reliable")
func set_power_node_state(node_id: int, active: bool, activating_peer: int) -> void:
    if not power_nodes.has(node_id):
        return
    var node := power_nodes[node_id] as PowerNode
    node.set_active(active)
    if active and not activated_node_ids.has(node_id):
        activated_node_ids.append(node_id)
    elif not active:
        activated_node_ids.erase(node_id)
    _update_progress_text()
    if activated_node_ids.size() >= power_nodes.size():
        _set_status("全部电力节点已恢复，电磁星球测试目标完成！", Color("#8be28b"))
    elif active:
        _set_status("玩家 %d 已激活节点 %d。" % [activating_peer, node_id], Color("#8be28b"))

@rpc("authority", "reliable")
func sync_shared_state(next_stage: String, active_node_ids: Array) -> void:
    current_stage = next_stage
    _reset_demo_beacons_local()
    _reset_power_nodes_local()
    for raw_id in active_node_ids:
        var node_id := int(raw_id)
        if current_stage == "demo" and demo_beacons.has(node_id):
            activated_demo_beacon_ids.append(node_id)
            demo_beacons[node_id].set_active(true)
        elif power_nodes.has(node_id):
            activated_node_ids.append(node_id)
            (power_nodes[node_id] as PowerNode).set_active(true)
    _set_stage_visuals()
    _update_stage_text()

@rpc("authority", "call_local", "reliable")
func change_stage(next_stage: String) -> void:
    current_stage = next_stage
    if current_stage == "ship":
        _reset_demo_beacons_local()
        _reset_power_nodes_local()
    _set_stage_visuals()
    for peer_id in players:
        players[peer_id].position = _spawn_position(peer_id)
    _update_stage_text()
    var stage_name := "示范星球" if current_stage == "demo" else ("电磁星球测试区" if current_stage == "electromagnetic" else "飞船准备区")
    _set_status("已同步切换到%s。" % stage_name, Color("#8be28b"))

func _reset_power_nodes_local() -> void:
    activated_node_ids.clear()
    for node in power_nodes.values():
        (node as PowerNode).set_active(false)
    _update_progress_text()

func _set_stage_visuals() -> void:
    if _demo_stage:
        _demo_stage.visible = current_stage == "demo"
    if _demo_beacons_root:
        _demo_beacons_root.visible = current_stage == "demo"
    if _power_nodes_root:
        _power_nodes_root.visible = current_stage == "electromagnetic"
    queue_redraw()
    _update_progress_text()

func _update_progress_text() -> void:
    if not progress_label:
        return
    if current_stage == "demo":
        progress_label.text = "示范目标：%d / %d" % [activated_demo_beacon_ids.size(), demo_beacons.size()]
    elif current_stage == "electromagnetic":
        progress_label.text = "电力节点：%d / %d" % [activated_node_ids.size(), power_nodes.size()]
    else:
        progress_label.text = "阶段进度：待出发"

func _leave_network() -> void:
    if multiplayer.multiplayer_peer != null:
        multiplayer.multiplayer_peer.close()
    multiplayer.multiplayer_peer = null
    is_host = false
    connected_ids.clear()
    _clear_players()
    _set_connected_ui(false)
    _set_status("已断开。请创建主机或加入现有主机。", Color("#ffcf5c"))

func _clear_players() -> void:
    for player in players.values():
        player.queue_free()
    players.clear()
    queue_redraw()

func _set_connected_ui(connected: bool) -> void:
    host_button.disabled = connected
    join_button.disabled = connected
    address_edit.editable = not connected
    stage_button.disabled = not connected
    leave_button.disabled = not connected

func _set_status(message: String, color: Color) -> void:
    if status_label:
        status_label.text = "状态：" + message
        status_label.add_theme_color_override("font_color", color)

func _update_player_list() -> void:
    if not player_list_label:
        return
    if connected_ids.is_empty():
        player_list_label.text = "（暂无玩家）"
        return
    var rows: Array[String] = []
    connected_ids.sort()
    for peer_id in connected_ids:
        var role := "主机" if peer_id == 1 else "客户端"
        rows.append("● 玩家 %d　%s" % [peer_id, role])
    player_list_label.text = "\n".join(rows)

func _update_stage_text() -> void:
    if not stage_badge:
        return
    if current_stage == "ship":
        stage_badge.text = "当前阶段：飞船准备区"
        stage_hint.text = "连接后使用 WASD / 方向键移动；蓝框内是基础碰撞测试区。"
        stage_button.text = "进入示范星球"
    elif current_stage == "demo":
        stage_badge.text = "当前阶段：示范星球"
        stage_hint.text = "靠近示范信标按 E 扫描；此关卡提供资源、危险区和撤离点的公共接口。"
        stage_button.text = "返回飞船准备区"
    else:
        stage_badge.text = "当前阶段：电磁星球测试区"
        stage_hint.text = "靠近蓝色电力节点按 E 激活；主机验证距离并同步所有玩家。"
        stage_button.text = "返回飞船准备区"



