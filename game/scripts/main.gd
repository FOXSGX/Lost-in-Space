extends Node2D

const PORT := 24567
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const DEMO_STAGE_SCENE := preload("res://scenes/demo_stage.tscn")
const DEMO_BEACON_SCENE := preload("res://scenes/demo_beacon.tscn")
const POWER_NODE_SCENE := preload("res://scenes/power_node.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const RESOURCE_CRATE_SCENE := preload("res://scenes/resource_crate.tscn")
const DEMO_BEACON_POSITIONS := [Vector2(185, 255), Vector2(500, 520), Vector2(790, 285)]
const POWER_NODE_POSITIONS := [Vector2(210, 235), Vector2(505, 455), Vector2(785, 260)]
const ENEMY_POSITIONS := [Vector2(730, 250), Vector2(820, 330), Vector2(760, 390), Vector2(670, 300)]
const RESOURCE_CRATE_POSITIONS := [Vector2(105, 240), Vector2(145, 300), Vector2(245, 220), Vector2(275, 300)]
const PLAYER_COLORS := [
    Color("#61dafb"), Color("#ffcf5c"), Color("#ff6b8a"), Color("#a78bfa")
]

# 示范星球的环境与资源数值。全部是占位数值，等四人试玩后再调平衡。
const HEAT_POSITION := Vector2(490, 500)
const HEAT_RADIUS := 42.0
const OXYGEN_DRAIN_BASE := 1.0
const OXYGEN_DRAIN_COLD := 3.0
const WARMTH_DRAIN := 0.05
const WARMTH_RECOVER := 0.4
const VITALS_SYNC_INTERVAL := 0.1
const CRATE_PICKUP_RANGE := 64.0
const REVIVE_RANGE := 64.0
const REVIVE_TIME := 3.0
const REVIVE_OXYGEN := 40.0

# 交互类型。kind 决定 id 在哪个命名空间里解释。
const INTERACT_BEACON := 1
const INTERACT_POWER_NODE := 2
const INTERACT_CRATE := 3
const INTERACT_DEPOSIT := 4
const INTERACT_REVIVE := 5

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
const EXTRACTION_POSITION := Vector2(845, 575)
const EXTRACTION_RADIUS := 58.0
const EXTRACTION_HOLD_TIME := 3.0
var extraction_progress := 0.0
var extraction_enabled := false
var mission_completed := false
var mission_failed := false
var enemies: Dictionary = {}
var enemy_spawned := false
var _resource_crates_root: Node2D
var resource_crates: Dictionary = {}
var taken_crate_ids: Array[int] = []
var deposited_resources := 0
var vitals_label: Label
var reviving: Dictionary = {}
var revive_progress: Dictionary = {}
var _vitals_accumulator := 0.0

func _process(delta: float) -> void:
    if not is_host or current_stage != "demo" or mission_completed or mission_failed:
        return
    _tick_enemies(delta)
    _tick_survival(delta)
    _tick_revive(delta)
    _tick_extraction(delta)
    _update_vitals_text()

func _tick_enemies(delta: float) -> void:
    for enemy_id in enemies.keys():
        var enemy := enemies[enemy_id] as DungeonEnemy
        if enemy == null:
            continue
        var result := enemy.server_tick(delta, players)
        if result.get("sync", false):
            enemy.sync_timer = 0.0
            sync_enemy_transform.rpc(enemy_id, enemy.position)
        if result.has("target_id"):
            damage_player.rpc(int(result.target_id), int(result.damage))

func _tick_survival(delta: float) -> void:
    for peer_id in connected_ids:
        var player := players.get(peer_id) as NetworkPlayer
        if player == null or player.downed:
            continue
        var in_heat := player.position.distance_to(HEAT_POSITION) <= HEAT_RADIUS
        if in_heat:
            player.warmth = minf(player.warmth + WARMTH_RECOVER * delta, 1.0)
        else:
            player.warmth = maxf(player.warmth - WARMTH_DRAIN * delta, 0.0)
        var drain := OXYGEN_DRAIN_BASE + (1.0 - player.warmth) * OXYGEN_DRAIN_COLD
        player.oxygen = maxf(player.oxygen - drain * delta, 0.0)
        if player.oxygen <= 0.0:
            down_player(peer_id)
    _vitals_accumulator += delta
    if _vitals_accumulator >= VITALS_SYNC_INTERVAL:
        _vitals_accumulator = 0.0
        _broadcast_vitals()

func _broadcast_vitals() -> void:
    var snapshot: Array = []
    for peer_id in connected_ids:
        var player := players.get(peer_id) as NetworkPlayer
        if player == null:
            continue
        snapshot.append([peer_id, player.warmth, player.oxygen, player.carrying, player.downed, player.health])
    sync_vitals.rpc(snapshot)

@rpc("authority", "unreliable", "call_remote")
func sync_vitals(snapshot: Array) -> void:
    for entry in snapshot:
        var peer_id := int(entry[0])
        if not players.has(peer_id):
            continue
        var player := players[peer_id] as NetworkPlayer
        player.warmth = float(entry[1])
        player.oxygen = float(entry[2])
        player.carrying = int(entry[3])
        player.downed = bool(entry[4])
        player.health = int(entry[5])
        player.queue_redraw()
    _update_vitals_text()

func _tick_revive(delta: float) -> void:
    for reviver_id in reviving.keys():
        var target_id: int = reviving[reviver_id]
        var reviver := players.get(reviver_id) as NetworkPlayer
        var target := players.get(target_id) as NetworkPlayer
        if reviver == null or target == null or reviver.downed or not target.downed \
                or reviver.position.distance_to(target.position) > REVIVE_RANGE:
            reviving.erase(reviver_id)
            revive_progress.erase(reviver_id)
            continue
        var progress: float = float(revive_progress.get(reviver_id, 0.0)) + delta
        if progress >= REVIVE_TIME:
            reviving.erase(reviver_id)
            revive_progress.erase(reviver_id)
            revive_player.rpc(target_id, reviver_id)
        else:
            revive_progress[reviver_id] = progress

func _tick_extraction(delta: float) -> void:
    if not enemy_spawned:
        extraction_progress = 0.0
        return
    if not enemies.is_empty():
        extraction_progress = 0.0
        return
    if activated_demo_beacon_ids.size() < demo_beacons.size():
        extraction_progress = 0.0
        return
    if deposited_resources < resource_crates.size():
        extraction_progress = 0.0
        return
    if not extraction_enabled:
        extraction_enabled = true
        _set_status("信标与资源均已完成，全体队员到投送撤离点集合。", Color("#8be28b"))
    var all_at_extraction := not connected_ids.is_empty()
    for peer_id in connected_ids:
        var player := players.get(peer_id) as NetworkPlayer
        if player == null or player.downed or player.position.distance_to(EXTRACTION_POSITION) > EXTRACTION_RADIUS:
            all_at_extraction = false
            break
    if all_at_extraction:
        extraction_progress = minf(extraction_progress + delta, EXTRACTION_HOLD_TIME)
        if extraction_progress >= EXTRACTION_HOLD_TIME:
            complete_demo_mission.rpc()
    else:
        extraction_progress = 0.0

func _ready() -> void:
    _build_world()
    _build_demo_stage()
    _build_demo_beacons()
    _build_resource_crates()
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

func _spawn_demo_enemies(alive_ids: Array = [1, 2, 3, 4]) -> void:
    if enemy_spawned:
        return
    enemy_spawned = true
    for index in ENEMY_POSITIONS.size():
        var enemy_id := index + 1
        if not alive_ids.has(enemy_id):
            continue
        var enemy := ENEMY_SCENE.instantiate() as DungeonEnemy
        enemy.setup(enemy_id)
        enemy.position = ENEMY_POSITIONS[index]
        add_child(enemy)
        enemies[enemy_id] = enemy

func alive_enemy_ids() -> Array:
    var ids: Array = []
    for enemy_id in enemies.keys():
        ids.append(int(enemy_id))
    return ids

func _build_resource_crates() -> void:
    _resource_crates_root = Node2D.new()
    _resource_crates_root.name = "DemoResourceCrates"
    add_child(_resource_crates_root)
    for index in RESOURCE_CRATE_POSITIONS.size():
        var crate := RESOURCE_CRATE_SCENE.instantiate() as ResourceCrate
        var crate_id := index + 1
        crate.setup(crate_id)
        crate.position = RESOURCE_CRATE_POSITIONS[index]
        _resource_crates_root.add_child(crate)
        resource_crates[crate_id] = crate
    _resource_crates_root.visible = false

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

func get_nearest_interaction(player_position: Vector2) -> Dictionary:
    if current_stage == "demo":
        return _nearest_demo_interaction(player_position)
    if current_stage == "electromagnetic":
        var node_id := get_nearest_power_node_id(player_position)
        if node_id >= 0:
            return {"kind": INTERACT_POWER_NODE, "id": node_id}
    return {}

func _nearest_demo_interaction(player_position: Vector2) -> Dictionary:
    # 救援优先：倒地队友比其他目标更急。
    var revive_target := -1
    var revive_distance := REVIVE_RANGE
    for peer_id in connected_ids:
        var mate := players.get(peer_id) as NetworkPlayer
        if mate == null or not mate.downed:
            continue
        var distance := player_position.distance_to(mate.position)
        if distance <= revive_distance:
            revive_distance = distance
            revive_target = peer_id
    if revive_target >= 0:
        return {"kind": INTERACT_REVIVE, "id": revive_target}

    # 资源和信标取更近的一个；投送点只在两者都不在范围内时兜底。
    var best_kind := 0
    var best_id := 0
    var best_distance := INF
    for crate_id in resource_crates:
        if taken_crate_ids.has(crate_id):
            continue
        var crate = resource_crates[crate_id]
        var distance := player_position.distance_to(crate.position)
        if distance <= CRATE_PICKUP_RANGE and distance < best_distance:
            best_distance = distance
            best_kind = INTERACT_CRATE
            best_id = crate_id
    var beacon_id := get_nearest_demo_beacon_id(player_position)
    if beacon_id >= 0:
        var beacon_distance := player_position.distance_to(demo_beacons[beacon_id].position)
        if beacon_distance < best_distance:
            best_kind = INTERACT_BEACON
            best_id = beacon_id
    if best_kind != 0:
        return {"kind": best_kind, "id": best_id}
    if player_position.distance_to(EXTRACTION_POSITION) <= EXTRACTION_RADIUS:
        return {"kind": INTERACT_DEPOSIT, "id": 0}
    return {}

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

    vitals_label = Label.new()
    vitals_label.position = Vector2(690, 104)
    vitals_label.add_theme_color_override("font_color", Color("#61dafb"))
    vitals_label.add_theme_font_size_override("font_size", 14)
    layer.add_child(vitals_label)

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
    host_button.focus_mode = Control.FOCUS_NONE
    host_button.text = "创建主机"
    host_button.custom_minimum_size.y = 38
    host_button.pressed.connect(_create_host)
    column.add_child(host_button)

    join_button = Button.new()
    join_button.focus_mode = Control.FOCUS_NONE
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
    stage_button.focus_mode = Control.FOCUS_NONE
    stage_button.text = "进入示范星球"
    stage_button.disabled = true
    stage_button.pressed.connect(_toggle_stage)
    column.add_child(stage_button)

    leave_button = Button.new()
    leave_button.focus_mode = Control.FOCUS_NONE
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
    var taken_crates: Array[int] = taken_crate_ids if current_stage == "demo" else []
    sync_shared_state.rpc_id(peer_id, current_stage, active_state, alive_enemy_ids(), taken_crates, deposited_resources)
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
    _update_vitals_text()

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

func handle_interaction(peer_id: int, kind: int, target_id: int) -> void:
    if not is_host:
        return
    match kind:
        INTERACT_BEACON:
            activate_demo_beacon_from_peer(peer_id, target_id)
        INTERACT_POWER_NODE:
            activate_power_node_from_peer(peer_id, target_id)
        INTERACT_CRATE:
            pickup_crate_from_peer(peer_id, target_id)
        INTERACT_DEPOSIT:
            deposit_resources_from_peer(peer_id)
        INTERACT_REVIVE:
            start_revive_from_peer(peer_id, target_id)

@rpc("any_peer", "reliable")
func request_interaction(kind: int, target_id: int) -> void:
    if not is_host:
        return
    handle_interaction(multiplayer.get_remote_sender_id(), kind, target_id)

@rpc("any_peer", "unreliable")
func request_attack() -> void:
    if is_host:
        attack_enemy_from_peer(multiplayer.get_remote_sender_id())

func activate_demo_beacon_from_peer(peer_id: int, beacon_id: int) -> void:
    if not is_host or current_stage != "demo":
        return
    if not enemies.is_empty():
        _set_status("先清除危险区内的敌人。", Color("#ffcf5c"))
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

func _reset_demo_progress_local() -> void:
    activated_demo_beacon_ids.clear()
    taken_crate_ids.clear()
    deposited_resources = 0
    extraction_progress = 0.0
    extraction_enabled = false
    mission_completed = false
    mission_failed = false
    enemy_spawned = false
    reviving.clear()
    revive_progress.clear()
    for enemy in enemies.values():
        enemy.queue_free()
    enemies.clear()
    for beacon in demo_beacons.values():
        beacon.set_active(false)
    for crate in resource_crates.values():
        crate.set_taken(false)
    _update_progress_text()

func pickup_crate_from_peer(peer_id: int, crate_id: int) -> void:
    if not is_host or current_stage != "demo":
        return
    if not resource_crates.has(crate_id) or taken_crate_ids.has(crate_id):
        return
    var player := players.get(peer_id) as NetworkPlayer
    if player == null or player.downed or player.carrying > 0:
        return
    if player.position.distance_to(resource_crates[crate_id].position) > CRATE_PICKUP_RANGE:
        _set_status("玩家 %d 需要靠近资源箱才能拾取。" % peer_id, Color("#ffcf5c"))
        return
    set_crate_taken.rpc(crate_id, true)
    set_player_carrying.rpc(peer_id, 1)
    _set_status("玩家 %d 已拾取资源，共 %d / %d。" % [peer_id, taken_crate_ids.size() + 1, resource_crates.size()], Color("#8be28b"))

@rpc("authority", "call_local", "reliable")
func set_crate_taken(crate_id: int, value: bool) -> void:
    if not resource_crates.has(crate_id):
        return
    resource_crates[crate_id].set_taken(value)
    if value and not taken_crate_ids.has(crate_id):
        taken_crate_ids.append(crate_id)
    elif not value:
        taken_crate_ids.erase(crate_id)
    _update_progress_text()

@rpc("authority", "call_local", "reliable")
func set_player_carrying(peer_id: int, amount: int) -> void:
    if not players.has(peer_id):
        return
    var player := players[peer_id] as NetworkPlayer
    player.carrying = amount
    player.queue_redraw()

func deposit_resources_from_peer(peer_id: int) -> void:
    if not is_host or current_stage != "demo":
        return
    var player := players.get(peer_id) as NetworkPlayer
    if player == null or player.downed or player.carrying <= 0:
        return
    if player.position.distance_to(EXTRACTION_POSITION) > EXTRACTION_RADIUS:
        _set_status("玩家 %d 需要把资源带到投送撤离点。" % peer_id, Color("#ffcf5c"))
        return
    var amount := player.carrying
    set_player_carrying.rpc(peer_id, 0)
    set_deposited_resources.rpc(deposited_resources + amount)
    _set_status("玩家 %d 已投送 %d 份资源，合计 %d / %d。" % [peer_id, amount, deposited_resources + amount, resource_crates.size()], Color("#8be28b"))

@rpc("authority", "call_local", "reliable")
func set_deposited_resources(total: int) -> void:
    deposited_resources = total
    _update_progress_text()

func start_revive_from_peer(reviver_id: int, target_id: int) -> void:
    if not is_host or current_stage != "demo":
        return
    var reviver := players.get(reviver_id) as NetworkPlayer
    var target := players.get(target_id) as NetworkPlayer
    if reviver == null or target == null or reviver_id == target_id:
        return
    if reviver.downed or not target.downed:
        return
    if reviver.position.distance_to(target.position) > REVIVE_RANGE:
        _set_status("玩家 %d 需要靠近倒地的玩家 %d。" % [reviver_id, target_id], Color("#ffcf5c"))
        return
    reviving[reviver_id] = target_id
    revive_progress[reviver_id] = 0.0
    _set_status("玩家 %d 正在救援玩家 %d…" % [reviver_id, target_id], Color("#8be28b"))

func down_player(peer_id: int) -> void:
    if not is_host:
        return
    var player := players.get(peer_id) as NetworkPlayer
    if player == null or player.downed:
        return
    player.health = 0
    set_player_downed.rpc(peer_id, true)

@rpc("authority", "call_local", "reliable")
func set_player_downed(peer_id: int, value: bool) -> void:
    if not players.has(peer_id):
        return
    var player := players[peer_id] as NetworkPlayer
    player.downed = value
    player.velocity = Vector2.ZERO
    if value:
        # 倒地的玩家会掉落携带的资源，避免卡住关卡进度。
        player.carrying = 0
        _set_status("玩家 %d 倒地，等待队友靠近救援。" % peer_id, Color("#ff6b8a"))
    player.queue_redraw()
    if value and is_host:
        _check_all_downed()

@rpc("authority", "call_local", "reliable")
func revive_player(target_id: int, reviver_id: int) -> void:
    if not players.has(target_id):
        return
    var player := players[target_id] as NetworkPlayer
    player.downed = false
    player.health = maxi(player.max_health / 2, 1)
    player.oxygen = maxf(player.oxygen, REVIVE_OXYGEN)
    player.warmth = 1.0
    player.queue_redraw()
    _set_status("玩家 %d 已被玩家 %d 救起。" % [target_id, reviver_id], Color("#8be28b"))

func _check_all_downed() -> void:
    if connected_ids.is_empty():
        return
    for peer_id in connected_ids:
        var player := players.get(peer_id) as NetworkPlayer
        if player == null or not player.downed:
            return
    fail_mission.rpc()

@rpc("authority", "call_local", "reliable")
func fail_mission() -> void:
    if mission_failed:
        return
    mission_failed = true
    _set_status("全员倒地，本次登陆失败，返回飞船准备区。", Color("#ff6b8a"))
    change_stage.rpc("ship")

@rpc("authority", "call_local", "reliable")
func complete_demo_mission() -> void:
    mission_completed = true
    extraction_enabled = true
    extraction_progress = EXTRACTION_HOLD_TIME
    _set_status("示范星球任务完成：全体队员已成功撤离！", Color("#8be28b"))
    _update_progress_text()

@rpc("authority", "call_local", "reliable")
func damage_player(peer_id: int, amount: int) -> void:
    if not players.has(peer_id):
        return
    var player := players[peer_id] as NetworkPlayer
    if player.downed:
        return
    player.health = maxi(player.health - amount, 0)
    if player.health <= 0:
        down_player(peer_id)
    player.queue_redraw()

func attack_enemy_from_peer(peer_id: int) -> void:
    if not is_host or current_stage != "demo" or not players.has(peer_id):
        return
    var player := players[peer_id] as NetworkPlayer
    var nearest_id := -1
    var nearest_distance := 58.0
    for enemy_id in enemies:
        var enemy := enemies[enemy_id] as DungeonEnemy
        var distance := player.position.distance_to(enemy.position)
        if distance <= nearest_distance:
            nearest_distance = distance
            nearest_id = enemy_id
    if nearest_id < 0:
        return
    var target := enemies[nearest_id] as DungeonEnemy
    if target.take_damage(1):
        target.queue_free()
        enemies.erase(nearest_id)
    sync_enemy_state.rpc(nearest_id, target.health if is_instance_valid(target) else 0)

@rpc("authority", "call_local", "reliable")
func sync_enemy_state(enemy_id: int, health: int) -> void:
    if enemies.has(enemy_id) and health <= 0:
        enemies[enemy_id].queue_free()
        enemies.erase(enemy_id)

@rpc("authority", "unreliable", "call_remote")
func sync_enemy_transform(enemy_id: int, next_position: Vector2) -> void:
    if not multiplayer.is_server() and enemies.has(enemy_id):
        (enemies[enemy_id] as DungeonEnemy).position = next_position

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
func sync_shared_state(next_stage: String, active_node_ids: Array, surviving_enemy_ids: Array, taken_crates: Array, deposited: int) -> void:
    current_stage = next_stage
    _reset_demo_progress_local()
    _reset_power_nodes_local()
    for raw_id in active_node_ids:
        var node_id := int(raw_id)
        if current_stage == "demo" and demo_beacons.has(node_id):
            activated_demo_beacon_ids.append(node_id)
            demo_beacons[node_id].set_active(true)
        elif power_nodes.has(node_id):
            activated_node_ids.append(node_id)
            (power_nodes[node_id] as PowerNode).set_active(true)
    deposited_resources = deposited
    for raw_id in taken_crates:
        var crate_id := int(raw_id)
        if resource_crates.has(crate_id):
            taken_crate_ids.append(crate_id)
            resource_crates[crate_id].set_taken(true)
    if current_stage == "demo":
        # 敌人节点不会随阶段广播补发，中途加入的玩家必须在这里生成，
        # 否则客户端会看到空无一人的危险区，和主机判定不一致。
        _spawn_demo_enemies(surviving_enemy_ids)
    _set_stage_visuals()
    _update_stage_text()
    _update_vitals_text()

@rpc("authority", "call_local", "reliable")
func change_stage(next_stage: String) -> void:
    current_stage = next_stage
    _reset_demo_progress_local()
    _reset_power_nodes_local()
    if current_stage == "demo":
        _spawn_demo_enemies()
    _set_stage_visuals()
    for peer_id in players:
        var player := players[peer_id] as NetworkPlayer
        player.position = _spawn_position(peer_id)
        player.health = player.max_health
        player.oxygen = player.max_oxygen
        player.warmth = 1.0
        player.carrying = 0
        player.downed = false
        player.velocity = Vector2.ZERO
        player.queue_redraw()
    _update_stage_text()
    _update_vitals_text()
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
    if _resource_crates_root:
        _resource_crates_root.visible = current_stage == "demo"
    if _power_nodes_root:
        _power_nodes_root.visible = current_stage == "electromagnetic"
    queue_redraw()
    _update_progress_text()

func _update_progress_text() -> void:
    if not progress_label:
        return
    if current_stage == "demo":
        progress_label.text = "信标 %d / %d　资源 %d / %d" % [
            activated_demo_beacon_ids.size(), demo_beacons.size(),
            deposited_resources, resource_crates.size(),
        ]
    elif current_stage == "electromagnetic":
        progress_label.text = "电力节点：%d / %d" % [activated_node_ids.size(), power_nodes.size()]
    else:
        progress_label.text = "阶段进度：待出发"

func _update_vitals_text() -> void:
    if not vitals_label:
        return
    var local_id := multiplayer.get_unique_id()
    var player := players.get(local_id) as NetworkPlayer
    if player == null:
        vitals_label.text = ""
        return
    var state := "倒地" if player.downed else "正常"
    vitals_label.text = "氧气 %d%%　体温 %d%%　资源 %d　%s" % [
        int(player.oxygen), int(player.warmth * 100.0), player.carrying, state,
    ]

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
        stage_hint.text = "按 E 拾取资源、扫描信标、向倒地的队友施救；把资源送到投送撤离点。离开热源会失温并加快氧气消耗。"
        stage_button.text = "返回飞船准备区"
    else:
        stage_badge.text = "当前阶段：电磁星球测试区"
        stage_hint.text = "靠近蓝色电力节点按 E 激活；主机验证距离并同步所有玩家。"
        stage_button.text = "返回飞船准备区"



