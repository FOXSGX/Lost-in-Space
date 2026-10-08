extends Node2D

const PORT := 24567
const SHIP_STAGE_SCENE := preload("res://scenes/ship_stage.tscn")
const FRONTEND_SCENE := preload("res://scenes/frontend.tscn")
const TRANSITION_DURATION := 2.4
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const DEMO_STAGE_SCENE := preload("res://scenes/demo_stage.tscn")
const DEMO_BEACON_SCENE := preload("res://scenes/demo_beacon.tscn")
const POWER_NODE_SCENE := preload("res://scenes/power_node.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const RESOURCE_CRATE_SCENE := preload("res://scenes/resource_crate.tscn")
const DEMO_BEACON_POSITIONS := [Vector2(185, 255), Vector2(500, 520), Vector2(790, 285)]
const POWER_NODE_POSITIONS := [Vector2(210, 235), Vector2(505, 455), Vector2(785, 260)]
const DEFAULT_SAFEHOUSE_RECT := Rect2(365, 400, 250, 205)
const DEFAULT_DANGER_RECT := Rect2(690, 175, 190, 230)
const MAP_BOUNDS := Rect2(62, 152, 850, 500)
const RESOURCE_COUNT := 4
const RESOURCE_MIN_DISTANCE := 72.0
const RESOURCE_ZONE_PADDING := 34.0
const DANGER_ENEMY_PADDING := 34.0
const PLAYER_COLORS := [
    Color("#61dafb"), Color("#ffcf5c"), Color("#ff6b8a"), Color("#a78bfa")
]

# 示范星球的环境与资源数值。全部是占位数值，等四人试玩后再调平衡。
const HEAT_RADIUS := 42.0
const OXYGEN_DRAIN_BASE := 1.0
const OXYGEN_DRAIN_COLD := 3.0
const OXYGEN_RECOVER := 12.0
const WARMTH_DRAIN := 0.05
const WARMTH_RECOVER := 0.4
const VITALS_SYNC_INTERVAL := 0.1
const CRATE_PICKUP_RANGE := 64.0
const ATTACK_RANGE := 150.0
const ENEMY_WAVE_INTERVAL := 15.0
const MAX_ENEMY_WAVES := 3
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
var _ship_stage: Node2D
var _demo_stage: Node2D
var _demo_beacons_root: Node2D
var _power_nodes_root: Node2D
var demo_beacons: Dictionary = {}
var activated_demo_beacon_ids: Array[int] = []
var power_nodes: Dictionary = {}
var activated_node_ids: Array[int] = []
var demo_safehouse_rect := DEFAULT_SAFEHOUSE_RECT
var demo_danger_rect := DEFAULT_DANGER_RECT
var demo_heat_position := DEFAULT_SAFEHOUSE_RECT.get_center()
var demo_resource_positions: Array[Vector2] = []
var demo_enemy_positions: Array[Vector2] = []
var demo_layout_ready := false
var demo_difficulty_player_count := 1
const EXTRACTION_POSITION := Vector2(845, 575)
const EXTRACTION_RADIUS := 58.0
const EXTRACTION_HOLD_TIME := 3.0
var extraction_progress := 0.0
var extraction_enabled := false
var mission_completed := false
var mission_failed := false
var mission_return_timer := 0.0
var enemies: Dictionary = {}
var enemy_spawned := false
var enemy_wave_index := 0
var enemy_wave_timer := 0.0
var next_enemy_id := 1
var _resource_crates_root: Node2D
var resource_crates: Dictionary = {}
var taken_crate_ids: Array[int] = []
var deposited_resources := 0
var vitals_label: Label
var player_status_container: VBoxContainer
var player_status_rows: Dictionary = {}
var reviving: Dictionary = {}
var revive_progress: Dictionary = {}
var _vitals_accumulator := 0.0
var frontend: SpaceFrontend
var _interface_layer: CanvasLayer
var transition_active := false
var transition_destination := "ship"
var transition_reason := ""
var transition_remaining := 0.0
var transition_token := 0
var solo_session := false

func _process(delta: float) -> void:
    _update_player_status_rows()
    if transition_active:
        if is_host:
            transition_remaining -= delta
            if transition_remaining <= 0.0:
                change_stage.rpc(transition_destination)
                finish_stage_transition.rpc(transition_token)
        return
    if not is_host or current_stage != "demo":
        return
    if mission_completed:
        mission_return_timer -= delta
        if mission_return_timer <= 0.0:
            request_stage_transition("ship", "任务完成 · 船员与物资已回收，正在离开星球轨道。")
        return
    if mission_failed:
        return
    _tick_enemy_waves(delta)
    _tick_enemies(delta)
    _tick_survival(delta)
    _tick_revive(delta)
    _tick_extraction(delta)
    _update_vitals_text()

func _tick_enemy_waves(delta: float) -> void:
    if enemy_wave_index >= MAX_ENEMY_WAVES:
        enemy_wave_timer = 0.0
        return
    enemy_wave_timer += delta
    if enemy_wave_timer < ENEMY_WAVE_INTERVAL:
        return
    enemy_wave_timer = 0.0
    _spawn_enemy_wave()

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
        var in_heat := player.position.distance_to(demo_heat_position) <= HEAT_RADIUS
        if in_heat:
            player.warmth = minf(player.warmth + WARMTH_RECOVER * delta, 1.0)
            player.oxygen = minf(player.oxygen + OXYGEN_RECOVER * delta, player.max_oxygen)
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
        _broadcast_extraction_state()
        return
    if enemy_wave_index < MAX_ENEMY_WAVES:
        extraction_progress = 0.0
        extraction_enabled = false
        _broadcast_extraction_state()
        return
    if not enemies.is_empty():
        extraction_progress = 0.0
        _broadcast_extraction_state()
        return
    if activated_demo_beacon_ids.size() < demo_beacons.size():
        extraction_progress = 0.0
        _broadcast_extraction_state()
        return
    if deposited_resources < resource_crates.size():
        extraction_progress = 0.0
        _broadcast_extraction_state()
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
    _broadcast_extraction_state()

func _broadcast_extraction_state() -> void:
    sync_extraction_state.rpc(extraction_enabled, extraction_progress, mission_completed)

func _ready() -> void:
    _build_world()
    _ship_stage = SHIP_STAGE_SCENE.instantiate()
    add_child(_ship_stage)
    _build_demo_stage()
    _build_demo_beacons()
    _build_resource_crates()
    _build_power_nodes()
    _build_ui()
    _build_frontend()
    _set_stage_visuals()
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
    _generate_demo_layout()
    _demo_stage.visible = false

func _generate_demo_layout() -> void:
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    demo_difficulty_player_count = maxi(connected_ids.size(), 1)

    var safe_size := Vector2(rng.randf_range(190.0, 245.0), rng.randf_range(155.0, 195.0))
    var danger_size := Vector2(rng.randf_range(175.0, 220.0), rng.randf_range(190.0, 240.0))
    var danger_x_min := 620.0
    var danger_x_max := MAP_BOUNDS.end.x - danger_size.x
    var danger_x := rng.randf_range(danger_x_min, danger_x_max)
    var safe_x_max := minf(500.0, danger_x - safe_size.x - 72.0)
    var safe_x := rng.randf_range(MAP_BOUNDS.position.x + 30.0, safe_x_max)
    var safe_y_max := MAP_BOUNDS.end.y - safe_size.y
    var safe_y := rng.randf_range(285.0, safe_y_max)
    var danger_y_max := minf(360.0, MAP_BOUNDS.end.y - danger_size.y)
    var danger_y := rng.randf_range(MAP_BOUNDS.position.y + 24.0, danger_y_max)

    demo_safehouse_rect = Rect2(Vector2(safe_x, safe_y), safe_size)
    demo_danger_rect = Rect2(Vector2(danger_x, danger_y), danger_size)
    demo_heat_position = demo_safehouse_rect.get_center()

    demo_resource_positions.clear()
    var resource_rng := RandomNumberGenerator.new()
    resource_rng.seed = rng.randi()
    var attempts := 0
    while demo_resource_positions.size() < RESOURCE_COUNT and attempts < 600:
        attempts += 1
        var candidate := Vector2(
            resource_rng.randf_range(MAP_BOUNDS.position.x + 22.0, MAP_BOUNDS.end.x - 22.0),
            resource_rng.randf_range(MAP_BOUNDS.position.y + 22.0, MAP_BOUNDS.end.y - 22.0)
        )
        if demo_safehouse_rect.grow(RESOURCE_ZONE_PADDING).has_point(candidate) \
                or demo_danger_rect.grow(RESOURCE_ZONE_PADDING).has_point(candidate) \
                or candidate.distance_to(EXTRACTION_POSITION) < 84.0:
            continue
        var too_close := false
        for existing in demo_resource_positions:
            if candidate.distance_to(existing) < RESOURCE_MIN_DISTANCE:
                too_close = true
                break
        if too_close:
            continue
        demo_resource_positions.append(candidate)
    while demo_resource_positions.size() < RESOURCE_COUNT:
        demo_resource_positions.append(Vector2(90.0 + demo_resource_positions.size() * 88.0, 205.0))

    demo_enemy_positions.clear()
    var enemy_rng := RandomNumberGenerator.new()
    enemy_rng.seed = rng.randi()
    var enemy_count := 3 + demo_difficulty_player_count
    for index in enemy_count:
        var enemy_position := Vector2(
            enemy_rng.randf_range(demo_danger_rect.position.x + DANGER_ENEMY_PADDING, demo_danger_rect.end.x - DANGER_ENEMY_PADDING),
            enemy_rng.randf_range(demo_danger_rect.position.y + DANGER_ENEMY_PADDING, demo_danger_rect.end.y - DANGER_ENEMY_PADDING)
        )
        demo_enemy_positions.append(enemy_position)
    _apply_demo_layout()

func _demo_layout_payload() -> Array:
    return [
        demo_safehouse_rect.position,
        demo_safehouse_rect.size,
        demo_danger_rect.position,
        demo_danger_rect.size,
        demo_resource_positions,
        demo_enemy_positions,
        demo_difficulty_player_count,
    ]

func _apply_demo_layout() -> void:
    demo_heat_position = demo_safehouse_rect.get_center()
    if is_instance_valid(_demo_stage) and _demo_stage.has_method("set_layout"):
        _demo_stage.set_layout(demo_safehouse_rect, demo_danger_rect, demo_heat_position)
    var resource_index := 0
    for crate in resource_crates.values():
        if resource_index < demo_resource_positions.size():
            (crate as ResourceCrate).position = demo_resource_positions[resource_index]
        resource_index += 1

func _apply_demo_layout_payload(payload: Array) -> void:
    if payload.size() < 6:
        return
    demo_safehouse_rect = Rect2(payload[0], payload[1])
    demo_danger_rect = Rect2(payload[2], payload[3])
    demo_resource_positions.clear()
    for raw_position in payload[4]:
        demo_resource_positions.append(raw_position)
    demo_enemy_positions.clear()
    for raw_position in payload[5]:
        demo_enemy_positions.append(raw_position)
    if payload.size() >= 7:
        demo_difficulty_player_count = maxi(int(payload[6]), 1)
    demo_layout_ready = true
    _apply_demo_layout()

@rpc("authority", "call_local", "reliable")
func sync_demo_layout(payload: Array) -> void:
    _apply_demo_layout_payload(payload)

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

func _spawn_demo_enemies(alive_ids: Array = []) -> void:
    if enemy_spawned:
        return
    enemy_spawned = true
    enemy_wave_index = 1
    enemy_wave_timer = 0.0
    next_enemy_id = demo_enemy_positions.size() + 1
    for index in demo_enemy_positions.size():
        var enemy_id := index + 1
        if not alive_ids.is_empty() and not alive_ids.has(enemy_id):
            continue
        var enemy := ENEMY_SCENE.instantiate() as DungeonEnemy
        enemy.setup(enemy_id, demo_difficulty_player_count)
        enemy.position = demo_enemy_positions[index]
        add_child(enemy)
        enemies[enemy_id] = enemy

func _generate_enemy_wave_positions(count: int) -> Array[Vector2]:
    var positions: Array[Vector2] = []
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var attempts := 0
    while positions.size() < count and attempts < 500:
        attempts += 1
        var candidate := Vector2(
            rng.randf_range(demo_danger_rect.position.x + 34.0, demo_danger_rect.end.x - 34.0),
            rng.randf_range(demo_danger_rect.position.y + 34.0, demo_danger_rect.end.y - 34.0)
        )
        var too_close := false
        for existing in positions:
            if candidate.distance_to(existing) < 54.0:
                too_close = true
                break
        if not too_close:
            positions.append(candidate)
    return positions

func _spawn_enemy_wave() -> void:
    if not is_host or current_stage != "demo" or enemy_wave_index >= MAX_ENEMY_WAVES:
        return
    var wave_size := 2 + demo_difficulty_player_count
    var positions := _generate_enemy_wave_positions(wave_size)
    for position in positions:
        var enemy := ENEMY_SCENE.instantiate() as DungeonEnemy
        enemy.setup(next_enemy_id, demo_difficulty_player_count)
        enemy.position = position
        add_child(enemy)
        enemies[next_enemy_id] = enemy
        next_enemy_id += 1
    enemy_wave_index += 1
    enemy_spawned = true
    sync_enemy_wave.rpc(_enemy_snapshot())
    _set_status("第 %d / %d 波敌人已生成。" % [enemy_wave_index, MAX_ENEMY_WAVES], Color("#ffcf5c"))

@rpc("authority", "call_local", "reliable")
func sync_enemy_wave(enemy_state: Array) -> void:
    enemy_spawned = true
    for entry in enemy_state:
        var enemy_id := int(entry[0])
        var enemy: DungeonEnemy = enemies.get(enemy_id) as DungeonEnemy
        if enemy == null:
            enemy = ENEMY_SCENE.instantiate() as DungeonEnemy
            enemy.setup(enemy_id, demo_difficulty_player_count)
            add_child(enemy)
            enemies[enemy_id] = enemy
        enemy.position = entry[1]
        enemy.health = int(entry[2])
        enemy.queue_redraw()
        next_enemy_id = maxi(next_enemy_id, enemy_id + 1)

func alive_enemy_ids() -> Array:
    var ids: Array = []
    for enemy_id in enemies.keys():
        ids.append(int(enemy_id))
    return ids

func _build_resource_crates() -> void:
    _resource_crates_root = Node2D.new()
    _resource_crates_root.name = "DemoResourceCrates"
    add_child(_resource_crates_root)
    for index in RESOURCE_COUNT:
        var crate := RESOURCE_CRATE_SCENE.instantiate() as ResourceCrate
        var crate_id := index + 1
        crate.setup(crate_id)
        crate.position = demo_resource_positions[index] if index < demo_resource_positions.size() else Vector2(100 + index * 80, 220)
        _resource_crates_root.add_child(crate)
        resource_crates[crate_id] = crate
    _resource_crates_root.visible = false
    _apply_demo_layout()

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
    _interface_layer = layer
    add_child(layer)

    stage_title = Label.new()
    stage_title.position = Vector2(52, 38)
    stage_title.add_theme_font_size_override("font_size", 27)
    stage_title.text = "迷失太空 · 归航号"
    layer.add_child(stage_title)

    stage_badge = Label.new()
    stage_badge.position = Vector2(52, 72)
    stage_badge.size = Vector2(590, 24)
    stage_badge.clip_text = true
    stage_badge.add_theme_color_override("font_color", Color("#61dafb"))
    stage_badge.add_theme_font_size_override("font_size", 17)
    layer.add_child(stage_badge)

    stage_hint = Label.new()
    stage_hint.position = Vector2(52, 101)
    stage_hint.size = Vector2(590, 24)
    stage_hint.clip_text = true
    stage_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
    stage_hint.add_theme_font_size_override("font_size", 13)
    stage_hint.add_theme_color_override("font_color", Color("#9fb4c8"))
    stage_hint.text = "连接后使用 WASD / 方向键移动；玩家会在所有实例中同步显示。"
    layer.add_child(stage_hint)

    progress_label = Label.new()
    progress_label.position = Vector2(690, 78)
    progress_label.size = Vector2(280, 42)
    progress_label.clip_text = true
    progress_label.autowrap_mode = TextServer.AUTOWRAP_OFF
    progress_label.add_theme_color_override("font_color", Color("#8be28b"))
    progress_label.add_theme_font_size_override("font_size", 13)
    layer.add_child(progress_label)

    vitals_label = Label.new()
    vitals_label.position = Vector2(690, 122)
    vitals_label.size = Vector2(280, 22)
    vitals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
    margin.add_theme_constant_override("margin_top", 12)
    margin.add_theme_constant_override("margin_bottom", 12)
    lobby_panel.add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 6)
    margin.add_child(column)

    var title := Label.new()
    title.text = "飞船 / 航行控制"
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
    status_label.clip_text = true
    status_label.custom_minimum_size.y = 46
    status_label.add_theme_color_override("font_color", Color("#ffcf5c"))
    column.add_child(status_label)

    var people_title := Label.new()
    people_title.text = "全体船员状态"
    people_title.add_theme_font_size_override("font_size", 16)
    column.add_child(people_title)

    player_status_container = VBoxContainer.new()
    player_status_container.custom_minimum_size = Vector2(0, 178)
    player_status_container.add_theme_constant_override("separation", 4)
    column.add_child(player_status_container)

    stage_button = Button.new()
    stage_button.focus_mode = Control.FOCUS_NONE
    stage_button.text = "打开星际航线图"
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
    footer.text = "端口 %d · 上限 %d 人\n航线 · 登陆 · 撤离" % [PORT, MAX_PLAYERS]
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
    _show_gameplay()
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
    _show_gameplay()
    _set_status("已加入主机，等待玩家列表…", Color("#8be28b"))

func _on_connection_failed() -> void:
    _leave_network()
    frontend.show_room("连接失败：检查主机 IP，确认同一局域网以及端口 %d。" % PORT)

func _on_server_disconnected() -> void:
    _leave_network()
    frontend.show_room("主机已断开，已返回主界面。可以重新加入飞船。")

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
    if demo_layout_ready or transition_destination == "demo":
        sync_demo_layout.rpc_id(peer_id, _demo_layout_payload())
    sync_shared_state.rpc_id(peer_id, current_stage, active_state, alive_enemy_ids(), taken_crates, deposited_resources)
    if current_stage == "demo" or transition_destination == "demo":
        sync_enemy_wave.rpc_id(peer_id, _enemy_snapshot())
    sync_session_snapshot.rpc_id(peer_id, _player_snapshot(), _enemy_snapshot())
    sync_extraction_state.rpc_id(peer_id, extraction_enabled, extraction_progress, mission_completed)
    if transition_active:
        begin_stage_transition.rpc_id(peer_id, transition_destination, transition_reason, transition_token, maxf(transition_remaining, 0.1))
    _set_status("玩家 %d 已加入。" % peer_id, Color("#8be28b"))
    _update_player_list()

func _on_peer_disconnected(peer_id: int) -> void:
    _release_carried_resource(peer_id)
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
    player.teleport(_spawn_position(peer_id))
    add_child(player)
    players[peer_id] = player
    _update_vitals_text()

func _spawn_position(peer_id: int) -> Vector2:
    if current_stage == "demo" and _demo_stage:
        return _demo_stage.get_spawn_position(peer_id - 1)
    var slots := [Vector2(175, 270), Vector2(315, 270), Vector2(455, 270), Vector2(595, 270)]
    return slots[(peer_id - 1) % slots.size()]

func _toggle_stage() -> void:
    if transition_active:
        return
    if current_stage == "ship":
        frontend.show_route(is_host, connected_ids.size())
    elif is_host:
        request_stage_transition("ship", "结束本次探索 · 正在接回全体船员，未投送物资将重置。")

func _build_frontend() -> void:
    var layer := CanvasLayer.new()
    layer.name = "Navigation"
    layer.layer = 20
    add_child(layer)
    frontend = FRONTEND_SCENE.instantiate() as SpaceFrontend
    layer.add_child(frontend)
    frontend.host_requested.connect(func(solo: bool): solo_session = solo; _create_host())
    frontend.join_requested.connect(func(address: String):
        solo_session = false
        address_edit.text = address
        address_edit.release_focus()
        frontend.set_connecting(true)
        _join_host()
    )
    frontend.destination_requested.connect(func(id: String): request_stage_transition(id, "前往%s · 全队将同步进入登陆区。" % PlanetRegistry.info(id).get("title", id)))
    frontend.closed.connect(_show_gameplay)
    frontend.disconnect_requested.connect(_leave_network)
    _interface_layer.hide()

func _show_gameplay() -> void:
    frontend.hide_screen()
    _interface_layer.show()
    address_edit.release_focus()
    _set_connected_ui(_has_active_peer())

func is_gameplay_active() -> bool:
    return _has_active_peer() and not transition_active and not frontend.visible and not mission_completed and not mission_failed

func request_stage_transition(destination: String, reason: String) -> void:
    if not is_host or transition_active or not PlanetRegistry.can_land(destination):
        return
    if destination == current_stage:
        return
    if destination == "demo":
        _generate_demo_layout()
        demo_layout_ready = true
        sync_demo_layout.rpc(_demo_layout_payload())
    begin_stage_transition.rpc(destination, reason, transition_token + 1, TRANSITION_DURATION)

@rpc("authority", "call_local", "reliable")
func begin_stage_transition(destination: String, reason: String, token: int, duration: float) -> void:
    if not PlanetRegistry.can_land(destination) or token <= transition_token:
        return
    transition_token = token
    transition_active = true
    transition_destination = destination
    transition_reason = reason
    transition_remaining = duration
    for player in players.values():
        player.velocity = Vector2.ZERO
    _interface_layer.hide()
    frontend.show_transit(destination, reason, duration)

@rpc("authority", "call_local", "reliable")
func finish_stage_transition(token: int) -> void:
    if token != transition_token:
        return
    transition_active = false
    transition_remaining = 0.0
    _show_gameplay()

func handle_interaction(peer_id: int, kind: int, target_id: int) -> void:
    if not is_host or transition_active or mission_completed or mission_failed:
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

@rpc("any_peer", "reliable")
func request_attack() -> void:
    if is_host:
        attack_enemy_from_peer(multiplayer.get_remote_sender_id())

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

func _reset_demo_progress_local() -> void:
    activated_demo_beacon_ids.clear()
    taken_crate_ids.clear()
    deposited_resources = 0
    extraction_progress = 0.0
    extraction_enabled = false
    mission_completed = false
    mission_failed = false
    mission_return_timer = 0.0
    enemy_spawned = false
    reviving.clear()
    revive_progress.clear()
    for enemy in enemies.values():
        enemy.queue_free()
    enemies.clear()
    enemy_wave_index = 0
    enemy_wave_timer = 0.0
    next_enemy_id = 1
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
    var collected_count := taken_crate_ids.size() + 1
    set_crate_taken.rpc(crate_id, true)
    set_player_carrying.rpc(peer_id, 1, crate_id)
    _set_status("玩家 %d 已拾取资源，已收集 %d / %d。" % [peer_id, collected_count, resource_crates.size()], Color("#8be28b"))

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
func set_player_carrying(peer_id: int, amount: int, crate_id: int = -1) -> void:
    if not players.has(peer_id):
        return
    var player := players[peer_id] as NetworkPlayer
    player.carrying = amount
    player.carrying_crate_id = crate_id if amount > 0 else -1
    player.queue_redraw()

func _release_carried_resource(peer_id: int) -> void:
    if not players.has(peer_id):
        return
    var player := players[peer_id] as NetworkPlayer
    if player.carrying > 0 and player.carrying_crate_id > 0:
        set_crate_taken.rpc(player.carrying_crate_id, false)
    player.carrying = 0
    player.carrying_crate_id = -1

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
    set_player_carrying.rpc(peer_id, 0, -1)
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
        # 携带的资源随玩家保留，救起后可以继续完成投送。
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
    if is_host:
        request_stage_transition("ship", "登陆失败 · 全员失去行动能力，启动紧急救援返航。")
    _set_status("全员倒地，本次登陆失败，正在紧急返航。", Color("#ff6b8a"))

@rpc("authority", "call_local", "reliable")
func complete_demo_mission() -> void:
    mission_completed = true
    extraction_enabled = true
    extraction_progress = EXTRACTION_HOLD_TIME
    mission_return_timer = 2.5
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
    player.show_damage(amount)
    if player.health <= 0:
        down_player(peer_id)
    player.queue_redraw()

func attack_enemy_from_peer(peer_id: int) -> void:
    if not is_host or transition_active or mission_completed or mission_failed or current_stage != "demo" or not players.has(peer_id):
        return
    var player := players[peer_id] as NetworkPlayer
    if player.downed:
        return
    var nearest_id := -1
    var nearest_distance := ATTACK_RANGE
    for enemy_id in enemies:
        var enemy := enemies[enemy_id] as DungeonEnemy
        var distance := player.position.distance_to(enemy.position)
        if distance <= nearest_distance:
            nearest_distance = distance
            nearest_id = enemy_id
    if nearest_id < 0:
        _set_status("攻击未命中：靠近敌人后按空格。", Color("#ffcf5c"))
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
    elif enemies.has(enemy_id):
        var enemy := enemies[enemy_id] as DungeonEnemy
        var damage := maxi(enemy.health - health, 1)
        enemy.health = health
        enemy.show_damage(damage)
        enemy.queue_redraw()

@rpc("authority", "unreliable", "call_remote")
func sync_enemy_transform(enemy_id: int, next_position: Vector2) -> void:
    if not multiplayer.is_server() and enemies.has(enemy_id):
        (enemies[enemy_id] as DungeonEnemy).apply_network_position(next_position)

@rpc("authority", "unreliable", "call_remote")
func sync_extraction_state(enabled: bool, progress: float, completed: bool) -> void:
    extraction_enabled = enabled
    extraction_progress = progress
    mission_completed = completed
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

func _player_snapshot() -> Array:
    var snapshot: Array = []
    for id in players:
        var player := players[id] as NetworkPlayer
        snapshot.append([id, player.position, player.health, player.oxygen, player.warmth, player.carrying, player.carrying_crate_id, player.downed])
    return snapshot

func _enemy_snapshot() -> Array:
    var snapshot: Array = []
    for id in enemies:
        var enemy := enemies[id] as DungeonEnemy
        snapshot.append([id, enemy.position, enemy.health])
    return snapshot

@rpc("authority", "reliable")
func sync_session_snapshot(player_state: Array, enemy_state: Array) -> void:
    for entry in player_state:
        if not players.has(int(entry[0])):
            continue
        var player := players[int(entry[0])] as NetworkPlayer
        player.teleport(entry[1])
        player.health = int(entry[2])
        player.oxygen = float(entry[3])
        player.warmth = float(entry[4])
        player.carrying = int(entry[5])
        player.carrying_crate_id = int(entry[6])
        player.downed = bool(entry[7])
    for entry in enemy_state:
        if enemies.has(int(entry[0])):
            var enemy := enemies[int(entry[0])] as DungeonEnemy
            enemy.position = entry[1]
            enemy.apply_network_position(entry[1])
            enemy.health = int(entry[2])
            enemy.queue_redraw()
    _update_vitals_text()

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
        _apply_demo_layout()
    _set_stage_visuals()
    _update_stage_text()
    _update_vitals_text()

@rpc("authority", "call_local", "reliable")
func change_stage(next_stage: String) -> void:
    current_stage = next_stage
    _reset_demo_progress_local()
    _reset_power_nodes_local()
    if current_stage == "demo":
        _apply_demo_layout()
        _spawn_demo_enemies()
    _set_stage_visuals()
    for peer_id in players:
        var player := players[peer_id] as NetworkPlayer
        player.teleport(_spawn_position(peer_id))
        player.health = player.max_health
        player.oxygen = player.max_oxygen
        player.warmth = 1.0
        player.carrying = 0
        player.carrying_crate_id = -1
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
    if is_instance_valid(_ship_stage):
        _ship_stage.visible = current_stage == "ship"
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
        var extraction_text := "撤离 -"
        if extraction_enabled:
            extraction_text = "撤离 %.1f/%.1f" % [extraction_progress, EXTRACTION_HOLD_TIME]
        progress_label.text = "信标 %d/%d · 资源 %d/%d · 投送 %d/%d\n%s" % [
            activated_demo_beacon_ids.size(), demo_beacons.size(),
            taken_crate_ids.size(), resource_crates.size(),
            deposited_resources, resource_crates.size(),
            extraction_text,
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
    transition_active = false
    transition_remaining = 0.0
    transition_token = 0
    current_stage = "ship"
    _reset_demo_progress_local()
    _set_stage_visuals()
    _interface_layer.hide()
    frontend.show_home()
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
    stage_button.disabled = not connected or transition_active or (current_stage != "ship" and not is_host)
    leave_button.disabled = not connected

func _set_status(message: String, color: Color) -> void:
    if is_instance_valid(frontend):
        frontend.set_notice(message)
        if "失败" in message:
            frontend.set_connecting(false)
    if status_label:
        status_label.text = "状态：" + message
        status_label.add_theme_color_override("font_color", color)

func _make_status_bar(fill_color: Color) -> ProgressBar:
    var bar := ProgressBar.new()
    bar.custom_minimum_size = Vector2(54, 8)
    bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.show_percentage = false
    var background := StyleBoxFlat.new()
    background.bg_color = Color("#081523")
    background.set_corner_radius_all(3)
    var fill := StyleBoxFlat.new()
    fill.bg_color = fill_color
    fill.set_corner_radius_all(3)
    bar.add_theme_stylebox_override("background", background)
    bar.add_theme_stylebox_override("fill", fill)
    return bar

func _make_status_metric(title: String, color: Color) -> Dictionary:
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 1)
    var label := Label.new()
    label.text = title
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", 10)
    label.add_theme_color_override("font_color", Color("#91a8bb"))
    column.add_child(label)
    var bar := _make_status_bar(color)
    column.add_child(bar)
    return {"root": column, "bar": bar}

func _rebuild_player_status_rows() -> void:
    if not is_instance_valid(player_status_container):
        return
    for child in player_status_container.get_children():
        child.queue_free()
    player_status_rows.clear()
    if connected_ids.is_empty():
        var empty_label := Label.new()
        empty_label.text = "（暂无玩家）"
        empty_label.add_theme_color_override("font_color", Color("#708ca4"))
        player_status_container.add_child(empty_label)
        return
    connected_ids.sort()
    for peer_id in connected_ids:
        var card := PanelContainer.new()
        card.custom_minimum_size = Vector2(0, 39)
        var card_style := StyleBoxFlat.new()
        card_style.bg_color = Color("#0d2033")
        card_style.border_color = Color("#24445c")
        card_style.set_border_width_all(1)
        card_style.set_corner_radius_all(5)
        card.add_theme_stylebox_override("panel", card_style)
        player_status_container.add_child(card)

        var card_column := VBoxContainer.new()
        card_column.add_theme_constant_override("separation", 1)
        card.add_child(card_column)
        var caption := Label.new()
        caption.add_theme_font_size_override("font_size", 11)
        caption.add_theme_color_override("font_color", Color("#d5e7f7"))
        card_column.add_child(caption)
        var metric_row := HBoxContainer.new()
        metric_row.add_theme_constant_override("separation", 4)
        card_column.add_child(metric_row)
        var health_metric := _make_status_metric("生命", Color("#ff6b8a"))
        var oxygen_metric := _make_status_metric("氧气", Color("#61dafb"))
        var warmth_metric := _make_status_metric("体温", Color("#ffcf5c"))
        metric_row.add_child(health_metric["root"])
        metric_row.add_child(oxygen_metric["root"])
        metric_row.add_child(warmth_metric["root"])
        player_status_rows[peer_id] = {
            "caption": caption,
            "health": health_metric["bar"],
            "oxygen": oxygen_metric["bar"],
            "warmth": warmth_metric["bar"],
        }

func _update_player_status_rows() -> void:
    if not is_instance_valid(player_status_container):
        return
    if player_status_rows.size() != connected_ids.size():
        _rebuild_player_status_rows()
    for peer_id in connected_ids:
        if not player_status_rows.has(peer_id):
            continue
        var row: Dictionary = player_status_rows[peer_id]
        var player := players.get(peer_id) as NetworkPlayer
        if player == null:
            row["caption"].text = "玩家 %d · 连接中" % peer_id
            row["health"].value = 0.0
            row["oxygen"].value = 0.0
            row["warmth"].value = 0.0
            continue
        var state := "倒地" if player.downed else ("主机" if peer_id == 1 else "在线")
        row["caption"].text = "玩家 %d · %s · 生命 %d/%d" % [peer_id, state, player.health, player.max_health]
        row["caption"].add_theme_color_override("font_color", Color("#ff6b8a") if player.downed else Color("#d5e7f7"))
        row["health"].value = float(player.health) / player.max_health * 100.0
        row["oxygen"].value = player.oxygen / player.max_oxygen * 100.0
        row["warmth"].value = player.warmth * 100.0
        row["health"].tooltip_text = "生命 %d / %d" % [player.health, player.max_health]
        row["oxygen"].tooltip_text = "氧气 %d%%" % int(player.oxygen)
        row["warmth"].tooltip_text = "体温 %d%%" % int(player.warmth * 100.0)

func _update_player_list() -> void:
    _rebuild_player_status_rows()
    _update_player_status_rows()

func _update_stage_text() -> void:
    if not stage_badge:
        return
    if current_stage == "ship":
        stage_badge.text = "当前阶段：飞船准备区"
        stage_hint.text = "WASD / 方向键移动 · 打开航线图选择目的地 · 主机确认后全队登陆"
        stage_button.text = "打开星际航线图"
    elif current_stage == "demo":
        stage_badge.text = "当前阶段：示范星球"
        stage_hint.text = "空格攻击 · E 扫描/搬运/救援 · 热源补氧回温 · 撤离点停留 3 秒"
        stage_button.text = "返回飞船准备区"
    else:
        stage_badge.text = "当前阶段：电磁星球测试区"
        stage_hint.text = "靠近蓝色电力节点按 E 激活 · 主机验证距离并同步全队"
        stage_button.text = "返回飞船准备区"
