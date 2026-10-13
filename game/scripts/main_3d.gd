extends Node3D
class_name Main3D

const PORT := 24567
var network_port := PORT
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/player_3d.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy_3d.tscn")
const OBSTACLE_SCENE := preload("res://scenes/frost_obstacle_3d.tscn")
const JOURNAL_MAP_SCENE := preload("res://scripts/journal_map_view.gd")
const FROST_FIELD_INTERACTIONS := preload("res://scripts/frost_field_interactions.gd")
const SCAN_DURATION := 4.0
const SCAN_STARTUP := 0.8
const SCAN_COOLDOWN := 6.0
const REVIVE_TIME := 3.0
const REVIVE_RANGE := 1.8
const REVIVE_OXYGEN := 40.0
const STORM_INTERVAL := 45.0
const STORM_DURATION := 12.0
const CLEAR_SCAN_RADIUS := 14.0
const STORM_SCAN_RADIUS := 9.0
const SCAN_DEVICE_RADIUS := 14.0
const STORM_SCAN_DEVICE_RADIUS := 9.0
const RESOURCE_INTERACTION_RADIUS := 2.4
const SPRINT_OXYGEN_MULTIPLIER := 1.55
const SPRINT_WARMTH_MULTIPLIER := 1.45
const MISSION_RETURN_DELAY := 2.5
const MAP_SIZE := Vector2(384.0, 256.0)
# 地形网格比可行走范围向外多铺一圈，避免玩家在地图边缘看到黑色虚空。
const TERRAIN_MARGIN := 16.0
const ICE_CLIFF_HEIGHT := 5.2
const ICE_CLIFF_THICKNESS := 1.8
# 生存数值按 384×256 的地图尺度重算：
#   安全屋到撤离点单程约 58 秒，横穿全图约 66 秒。
#   体温 143 秒：够走完一趟单程，但走不到全程往返 —— 玩家必须用沿途 6 个地热口续命，
#   于是"路线规划"成为主要压力来源。氧气 333 秒是更宽的兜底，避免双重计时过苛。
const HEAT_RADIUS := 6.5
const OXYGEN_DRAIN_BASE := 0.12
const OXYGEN_DRAIN_COLD := 0.22
const OXYGEN_RECOVER := 8.0
const WARMTH_DRAIN := 0.007
const WARMTH_RECOVER := 0.32
# 安全屋与撤离点只以布局文件为准，避免两处坐标各写一份后失配。
const SAFEHOUSE := FrostMapLayout.SAFEHOUSE
const EXTRACTION := FrostMapLayout.EXTRACTION
const OPTIONAL_REWARD_TARGET := 30
const BATTERY_VALUE := 10
const SAMPLE_VALUE := 20
const CLUE_TRIGGER_RADIUS := 2.4
const CLUE_SCAN_RADIUS := 14.0
const THOUGHT_DURATION := 4.0
const JOURNAL_MAX_ENTRIES := 18
const LANDMARK_INTERACTION_RADIUS := 4.2
const REQUIRED_KNOWLEDGE := ["weather_station", "ice_rift", "relay"]
const THERMAL_CYCLE := 18.0
const THERMAL_COOLING_START := 12.0
const THERMAL_COOLING_END := 16.5
const SIGNAL_LURE_DURATION := 8.0
const SIGNAL_STORM_DURATION := 8.0
const SIGNAL_COOLDOWN := 10.0
const KEY_BINDINGS_PATH := "user://controls.cfg"
const KEY_BINDING_ACTIONS := ["sprint", "toggle_map", "toggle_journal"]
const KEY_BINDING_LABELS := {"sprint": "加速", "toggle_map": "地图", "toggle_journal": "日志"}
const KEY_BINDING_DEFAULTS := {"sprint": KEY_SHIFT, "toggle_map": KEY_M, "toggle_journal": KEY_TAB}
const LANDMARK_DATA := [
    {"id": "weather_station", "position": Vector2(-130.0, -88.0), "name": "旧气象站", "region": "西北·静默台地", "thought": "天线还在转，但所有记录都被人为删过。有人不想让后来者知道这里发生了什么。", "entry": "旧气象站的日志被分段擦除，只留下一个反复出现的坐标：冰层下方。"},
    {"id": "ice_rift", "position": Vector2(132.0, -94.0), "name": "冰层裂谷", "region": "东北·热脉裂谷", "thought": "裂缝里有热气，温度变化却像呼吸。这里的东西可能还活着。", "entry": "冰层裂谷下方存在规律性的热脉冲，间隔与信标失联时间一致。"},
    {"id": "transport", "position": Vector2(130.0, 74.0), "name": "坠毁运输舱", "region": "东南·残骸湾", "thought": "舱门从里面被打开过。货舱里的东西不是被抢走的，是被带走的。", "entry": "运输舱的货物被有序搬运，拖痕通向更深的雪原。"},
    {"id": "relay", "position": Vector2(-124.0, 52.0), "name": "废弃通信阵列", "region": "西南·回声峡谷", "thought": "阵列没有电，却在重复我们的呼号。回应来自地面，不是轨道。", "entry": "废弃通信阵列能回放登陆队的声音，但回放时间晚于他们失踪的时间。"}
]
const PLAYER_COLORS := [Color("#55dfff"), Color("#ffd25a"), Color("#ff6d8a"), Color("#a88cff")]
const BEACON_POSITIONS := [Vector2(-24.0, -10.0), Vector2(3.0, -14.0), Vector2(23.0, -7.0)]
const CRATE_POSITIONS := [Vector2(-27.0, 7.0), Vector2(-8.0, -17.0), Vector2(13.0, 5.0), Vector2(29.0, 14.0)]

var beacon_positions: Array = []
var crate_positions: Array = []
var sample_positions: Array = []
var exploration_clues: Array[Dictionary] = []
var clue_nodes: Dictionary = {}
var discovered_clues: Array[int] = []
var scan_revealed_clues: Array[int] = []
var map_markers: Array[Dictionary] = []
var next_marker_id := 1
var journal_entries: Array[String] = []
var discovered_regions: Array[String] = []
var route_seed := 0

var _ship_session: ShipSession3D
var ship_active: bool:
    get:
        return _ship_session != null and _ship_session.active

var is_host := false
var game_started := false
var connected_ids: Array[int] = []
var players: Dictionary = {}
var enemies: Dictionary = {}
var obstacles: Array[Node] = []
var beacons: Dictionary = {}
var crates: Dictionary = {}
var samples: Dictionary = {}
var activated_beacons: Array[int] = []
var taken_crates: Array[int] = []
var taken_samples: Array[int] = []
var deposited_resources := 0
var salvage_value := 0
var mission_elapsed := 0.0
var knowledge_flags: Dictionary = {}
var anomaly_resolved := false
var ending_choice := ""
var rift_valve_open := false
var signal_mode := "neutral"
var signal_lure_until := 0.0
var signal_lure_position := Vector3.ZERO
var signal_cooldown_until := 0.0
var contract_sync_accumulator := 0.0
var enemy_wave_index := 0
var enemy_wave_timer := 0.0
var story_elapsed := 0.0
var story_flags: Dictionary = {}
var enemy_trigger_flags: Dictionary = {}
var enemy_spawn_center := Vector2(4.0, -2.0)
var next_enemy_id := 1
var extraction_enabled := false
var extraction_progress := 0.0
var mission_completed := false
var mission_failed := false
var mission_summary := ""
var mission_return_timer := 0.0
var enemy_spawned := false
var reviving: Dictionary = {}
var revive_progress: Dictionary = {}
var storm_active := false
var storm_elapsed := 0.0
var storm_remaining := 0.0
var _vitals_accumulator := 0.0
var scan_peer_id := -1
var scan_origin := Vector3.ZERO
var scan_remaining := 0.0
var scan_cooldown := 0.0
var scan_visual: MeshInstance3D
var scan_device: Node3D
var scan_device_active := false
var scan_device_position := Vector3.ZERO

var _world_root: Node3D
var _field_interactions: FrostFieldInteractions
var _environment: WorldEnvironment
var _menu_world: Node3D
var _menu_camera: Camera3D
var _menu_ship: Node3D
var _menu_planet: Node3D
var _menu_time := 0.0
var _status_label: Label
var _game_status_label: Label
var _progress_label: Label
var _vitals_label: Label
var _hint_label: Label
var _thought_label: Label
var _thought_timer := 0.0
var _story_label: Label
var _story_timer := 0.0
var _journal_panel: Panel
var _journal_label: Label
var _journal_visible := false
var _journal_scroll: ScrollContainer
var _journal_log_view: Control
var _journal_map_view: JournalMapView
var _journal_log_button: Button
var _journal_map_button: Button
var _journal_mark_heat_button: Button
var _journal_mark_clue_button: Button
var _journal_clear_marker_button: Button
var _compass_panel: Panel
var _compass_label: Label
var _compass_target := ""
var _compass_direction := ""
var _compass_distance := 0.0
var _objective_panel: Panel
var _vitals_panel: Panel
var _interaction_panel: Panel
var _subtitle_panel: Panel
var _alert_label: Label
var _interaction_progress: ProgressBar
var _narrative_queue: Array[Dictionary] = []
var _world_labels: Array[Label3D] = []
var _interaction_label: Label
var _object_tags: Array[Dictionary] = []
var _attack_ready_at: Dictionary = {}
var _menu_layer: CanvasLayer
var _game_layer: CanvasLayer
var _address_edit: LineEdit
var _host_button: Button
var _join_button: Button
var _storm_overlay: ColorRect
var _vision_overlay: ColorRect
var _minigame_panel: Panel
var _minigame_title: Label
var _minigame_instruction: Label
var _minigame_progress: Label
var _minigame_status: Label
var minigame_active := false
var minigame_peer_id := -1
var minigame_landmark_id := ""
var minigame_mode := "sequence"
var minigame_sequence: Array[String] = []
var minigame_step := 0
var minigame_time := 0.0
var minigame_status_text := ""
var _home_group: Control
var _room_group: Control
var _feedback_label: Label
var _feedback_timer := 0.0
var _settings_layer: CanvasLayer
var _settings_backdrop: ColorRect
var _settings_panel: Panel
var _settings_status: Label
var _settings_buttons: Dictionary = {}
var _key_bindings: Dictionary = {}
var _settings_visible := false
var _rebinding_action := ""
var _settings_previous_paused := false
var _settings_previous_process_mode := Node.PROCESS_MODE_INHERIT
var _settings_child_process_modes: Dictionary = {}
var _route_group: Control
var _room_status: Label
var _route_status: Label
var _land_button: Button
var _screen_view := "home"

func _ready() -> void:
    _setup_key_bindings()
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)
    _build_menu_world()
    _build_ui()
    _field_interactions = FROST_FIELD_INTERACTIONS.new(self)
    _ship_session = ShipSession3D.new()
    _ship_session.name = "ShipSession"
    add_child(_ship_session)

func _input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    var key_event := event as InputEventKey
    if not key_event.pressed or key_event.echo:
        return
    var is_escape := key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE
    if _settings_visible:
        if _rebinding_action != "":
            _handle_rebind_input(key_event)
        elif is_escape:
            _close_settings()
        get_viewport().set_input_as_handled()
        return
    if is_escape:
        if ship_active and _ship_session.has_panel():
            _ship_session.close_panel()
        elif game_started or ship_active:
            _open_settings()
        get_viewport().set_input_as_handled()
        return
    if game_started and not minigame_active and not is_journal_visible():
        if key_event.physical_keycode == KEY_3 or key_event.keycode == KEY_3:
            _ship_session.request("use_medical")
        elif key_event.physical_keycode == KEY_4 or key_event.keycode == KEY_4:
            _ship_session.request("use_oxygen")
    if _event_matches_action(key_event, "toggle_journal"):
        if game_started:
            _toggle_journal()
            get_viewport().set_input_as_handled()
        return
    if _event_matches_action(key_event, "toggle_map"):
        if game_started:
            _toggle_map()
            get_viewport().set_input_as_handled()
        return
    if minigame_active:
        _handle_clue_minigame_input(key_event)
        get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
    if _settings_visible:
        return
    if _ship_session != null:
        _ship_session.tick(delta)
    if ship_active:
        return
    if not game_started:
        _menu_time += delta
        _animate_menu_world()
        return
    var local_peer_id := multiplayer.get_unique_id()
    for mark_action in ["mark_heat", "mark_clue", "clear_marker"]:
        if Input.is_action_just_pressed(mark_action):
            handle_action(local_peer_id, mark_action)
    if minigame_active:
        _update_clue_minigame(delta)
    _update_scan_visual(delta)
    if _field_interactions != null:
        _field_interactions.tick(delta)
    _update_storm_visual(delta)
    _update_vision_overlay()
    _update_hud()
    _update_interaction_hint()
    _register_visible_landmarks()
    _update_feedback(delta)
    _update_exploration_thought(delta)
    _update_story(delta)
    if not is_host:
        return
    if mission_completed or mission_failed:
        mission_return_timer += delta
        if mission_return_timer >= MISSION_RETURN_DELAY:
            var result_text := mission_summary if not mission_summary.is_empty() else ("任务完成，已返回飞船准备区。" if mission_completed else "登陆失败，已返回飞船准备区。")
            return_to_ship.rpc(result_text, _vitals_snapshot())
        return
    _tick_story(delta)
    _tick_storm(delta)
    _check_enemy_triggers()
    for enemy in enemies.values():
        var lure_active := mission_elapsed < signal_lure_until
        var result := (enemy as SpaceEnemy3D).server_tick(delta, players, signal_lure_position, lure_active, storm_active)
        if result.get("sync", false):
            _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot(), journal_entries, discovered_regions)
    _tick_survival(delta)
    _tick_revive(delta)
    _tick_extraction(delta)
    mission_elapsed += delta
    contract_sync_accumulator += delta
    if contract_sync_accumulator >= 0.5:
        contract_sync_accumulator = 0.0
        sync_contract_state.rpc(mission_elapsed, salvage_value, knowledge_flags.keys(), taken_samples, scan_revealed_clues)
    _vitals_accumulator += delta
    if _vitals_accumulator >= 0.1:
        _vitals_accumulator = 0.0
        sync_vitals.rpc(_vitals_snapshot())

func _build_ui() -> void:
    _menu_layer = CanvasLayer.new()
    _menu_layer.layer = 20
    add_child(_menu_layer)
    var menu_backdrop := ColorRect.new()
    menu_backdrop.color = Color(0.012, 0.035, 0.07, 0.62)
    menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    menu_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _menu_layer.add_child(menu_backdrop)
    _home_group = Control.new()
    _home_group.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _menu_layer.add_child(_home_group)
    _build_home_ui()
    _room_group = Control.new()
    _room_group.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _room_group.visible = false
    _menu_layer.add_child(_room_group)
    _build_room_ui()
    _route_group = Control.new()
    _route_group.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _route_group.visible = false
    _menu_layer.add_child(_route_group)
    _build_route_ui()

    _game_layer = CanvasLayer.new()
    _game_layer.layer = 10
    _game_layer.visible = false
    add_child(_game_layer)
    _storm_overlay = ColorRect.new()
    _storm_overlay.color = Color(0.02, 0.12, 0.20, 0.24)
    _storm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _storm_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _storm_overlay.visible = false
    _game_layer.add_child(_storm_overlay)
    _vision_overlay = ColorRect.new()
    _vision_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _vision_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var vision_shader := Shader.new()
    vision_shader.code = "shader_type canvas_item;\nuniform vec2 viewer = vec2(0.5);\nuniform vec2 scan_origin = vec2(0.5);\nuniform float view_radius = 0.28;\nuniform float scan_radius = 0.0;\nuniform float scan_active = 0.0;\nvoid fragment(){ float base_d = distance(UV, viewer); float reveal = 1.0 - smoothstep(view_radius - 0.07, view_radius, base_d); if (scan_active > 0.5) { float scan_d = distance(UV, scan_origin); reveal = max(reveal, 1.0 - smoothstep(scan_radius - 0.04, scan_radius, scan_d)); } COLOR = vec4(0.0, 0.015, 0.035, 0.84 * (1.0 - reveal)); }"
    var vision_material := ShaderMaterial.new()
    vision_material.shader = vision_shader
    _vision_overlay.material = vision_material
    _game_layer.add_child(_vision_overlay)
    _objective_panel = _panel(_game_layer, Vector2(24, 22), Vector2(410, 126), Color(0.025, 0.08, 0.13, 0.82), Color("#254d62"), 12)
    _progress_label = _ui_label(_objective_panel, "", Vector2(16, 12), Vector2(378, 102), 16, Color("#d9eef4"))
    _compass_panel = _panel(_game_layer, Vector2.ZERO, Vector2(390, 54), Color(0.025, 0.08, 0.13, 0.86), Color("#62e8dc"), 12)
    _place_hud(_compass_panel, Control.PRESET_CENTER_TOP, Vector2(-195, 22), Vector2(390, 54))
    _compass_label = _ui_label(_compass_panel, "", Vector2(12, 8), Vector2(366, 38), 16, Color("#d9eef4"))
    _compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _compass_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _vitals_panel = _panel(_game_layer, Vector2.ZERO, Vector2(350, 68), Color(0.025, 0.08, 0.13, 0.82), Color("#254d62"), 12)
    _place_hud(_vitals_panel, Control.PRESET_TOP_RIGHT, Vector2(-374, 22), Vector2(350, 68))
    _vitals_label = _ui_label(_vitals_panel, "", Vector2(16, 12), Vector2(318, 46), 16, Color("#d9eef4"))
    _hint_label = _ui_label(_game_layer, "", Vector2.ZERO, Vector2(570, 24), 14, Color("#a7c4d3"))
    _place_hud(_hint_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-594, -44), Vector2(570, 24))
    _hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _alert_label = _ui_label(_game_layer, "", Vector2.ZERO, Vector2(520, 56), 20, Color("#ffd089"))
    _place_hud(_alert_label, Control.PRESET_CENTER_TOP, Vector2(-260, 28), Vector2(520, 56))
    _alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _interaction_panel = _panel(_game_layer, Vector2.ZERO, Vector2(560, 50), Color(0.025, 0.08, 0.13, 0.92), Color("#59c8d1"), 12)
    _place_hud(_interaction_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-280, -76), Vector2(560, 50))
    _interaction_panel.visible = false
    _interaction_label = _ui_label(_interaction_panel, "", Vector2(16, 8), Vector2(528, 34), 20, Color("#f1fbff"))
    _interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _interaction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _interaction_progress = ProgressBar.new()
    _interaction_progress.show_percentage = false
    _interaction_progress.min_value = 0.0
    _interaction_progress.max_value = 1.0
    _interaction_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _place_hud(_interaction_progress, Control.PRESET_CENTER_BOTTOM, Vector2(-280, -84), Vector2(560, 6))
    var progress_background := StyleBoxFlat.new()
    progress_background.bg_color = Color(0.02, 0.08, 0.13, 0.86)
    progress_background.set_corner_radius_all(3)
    var progress_fill := StyleBoxFlat.new()
    progress_fill.bg_color = Color("#72e8dd")
    progress_fill.set_corner_radius_all(3)
    _interaction_progress.add_theme_stylebox_override("background", progress_background)
    _interaction_progress.add_theme_stylebox_override("fill", progress_fill)
    _interaction_progress.visible = false
    _game_layer.add_child(_interaction_progress)
    _subtitle_panel = _panel(_game_layer, Vector2.ZERO, Vector2(700, 92), Color(0.012, 0.035, 0.065, 0.92), Color("#254d62"), 12)
    _place_hud(_subtitle_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-350, -184), Vector2(700, 92))
    _subtitle_panel.visible = false
    _thought_label = _ui_label(_subtitle_panel, "", Vector2(22, 12), Vector2(656, 68), 19, Color("#e1f6ff"))
    _story_label = _ui_label(_subtitle_panel, "", Vector2(22, 12), Vector2(656, 68), 19, Color("#f3d7a4"))
    _thought_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _story_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _thought_label.visible = false
    _story_label.visible = false
    _journal_panel = _panel(_game_layer, Vector2(190, 92), Vector2(900, 520), Color(0.018, 0.065, 0.105, 0.97), Color("#62e8dc"), 16)
    _place_hud(_journal_panel, Control.PRESET_CENTER, Vector2(-450, -260), Vector2(900, 520))
    _journal_panel.visible = false
    var journal_title := Label.new()
    journal_title.text = "探索日志  /  FIELD NOTES"
    journal_title.position = Vector2(28, 22)
    journal_title.size = Vector2(840, 38)
    journal_title.add_theme_font_size_override("font_size", 26)
    journal_title.add_theme_color_override("font_color", Color("#f1fbff"))
    _journal_panel.add_child(journal_title)
    var journal_hint := Label.new()
    journal_hint.text = "Tab 关闭 · M 地图 · Shift 加速 · H 标记热源 · C 标记线索 · V 清除最近标记 · 阅读时世界仍在运行"
    journal_hint.position = Vector2(30, 62)
    journal_hint.size = Vector2(820, 28)
    journal_hint.add_theme_font_size_override("font_size", 14)
    journal_hint.add_theme_color_override("font_color", Color("#8fb4c4"))
    _journal_panel.add_child(journal_hint)
    _journal_log_button = _ui_button(_journal_panel, "日志", Vector2(30, 91), Vector2(90, 34), func(): _show_journal_page(false), true)
    _journal_map_button = _ui_button(_journal_panel, "地图", Vector2(128, 91), Vector2(90, 34), func(): _show_journal_page(true), false)
    _journal_mark_heat_button = _ui_button(_journal_panel, "标记热源", Vector2(230, 91), Vector2(108, 34), func(): _request_local_action("mark_heat"), false)
    _journal_mark_clue_button = _ui_button(_journal_panel, "标记线索", Vector2(346, 91), Vector2(108, 34), func(): _request_local_action("mark_clue"), false)
    _journal_clear_marker_button = _ui_button(_journal_panel, "清除最近", Vector2(462, 91), Vector2(108, 34), func(): _request_local_action("clear_marker"), false)
    _journal_scroll = ScrollContainer.new()
    _journal_scroll.position = Vector2(30, 136)
    _journal_scroll.size = Vector2(840, 348)
    _journal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _journal_panel.add_child(_journal_scroll)
    _journal_label = Label.new()
    _journal_label.custom_minimum_size.x = 812
    _journal_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _journal_label.add_theme_font_size_override("font_size", 16)
    _journal_label.add_theme_color_override("font_color", Color("#d9eef4"))
    _journal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _journal_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    _journal_scroll.add_child(_journal_label)
    _journal_log_view = _journal_scroll
    _journal_map_view = JOURNAL_MAP_SCENE.new() as JournalMapView
    _journal_map_view.position = Vector2(30, 126)
    _journal_map_view.size = Vector2(840, 358)
    _journal_map_view.visible = false
    _journal_map_view.configure(FrostMapLayout.ICE_CLIFFS, FrostMapLayout.PATHWAYS, LANDMARK_DATA, SAFEHOUSE, EXTRACTION)
    _journal_panel.add_child(_journal_map_view)
    _feedback_label = Label.new()
    _place_hud(_feedback_label, Control.PRESET_CENTER_TOP, Vector2(-300, 110), Vector2(600, 56))
    _feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _feedback_label.add_theme_font_size_override("font_size", 16)
    _feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _feedback_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
    _feedback_label.add_theme_constant_override("outline_size", 4)
    _feedback_label.visible = false
    _game_layer.add_child(_feedback_label)
    _minigame_panel = _panel(_game_layer, Vector2.ZERO, Vector2(540, 270), Color(0.018, 0.065, 0.105, 0.98), Color("#e0ae67"), 16)
    _place_hud(_minigame_panel, Control.PRESET_CENTER, Vector2(-270, -135), Vector2(540, 270))
    _minigame_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    _minigame_title = _ui_label(_minigame_panel, "线索解码", Vector2(28, 22), Vector2(484, 36), 25, Color("#ffe0a1"))
    _minigame_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _minigame_instruction = _ui_label(_minigame_panel, "", Vector2(32, 72), Vector2(476, 70), 18, Color("#d9eef4"))
    _minigame_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _minigame_instruction.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _minigame_progress = _ui_label(_minigame_panel, "", Vector2(32, 148), Vector2(476, 34), 20, Color("#72e8dd"))
    _minigame_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _minigame_status = _ui_label(_minigame_panel, "", Vector2(32, 196), Vector2(476, 42), 15, Color("#ffbd75"))
    _minigame_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _minigame_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _minigame_panel.visible = false
    _build_settings_ui()

func _setup_key_bindings() -> void:
    var config := ConfigFile.new()
    var loaded := config.load(KEY_BINDINGS_PATH) == OK
    for action in KEY_BINDING_ACTIONS:
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        var code := int(KEY_BINDING_DEFAULTS[action])
        if loaded:
            code = int(config.get_value("keys", action, code))
        if code <= 0:
            code = int(KEY_BINDING_DEFAULTS[action])
        _key_bindings[action] = code
        _apply_key_binding(action, code)

func _apply_key_binding(action: String, code: int) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    InputMap.action_erase_events(action)
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    InputMap.action_add_event(action, event)

func _save_key_bindings() -> void:
    var config := ConfigFile.new()
    for action in KEY_BINDING_ACTIONS:
        config.set_value("keys", action, int(_key_bindings.get(action, KEY_BINDING_DEFAULTS[action])))
    config.save(KEY_BINDINGS_PATH)

func _event_matches_action(event: InputEventKey, action: String) -> bool:
    for binding in InputMap.action_get_events(action):
        if not binding is InputEventKey:
            continue
        var key_binding := binding as InputEventKey
        var physical_code := int(key_binding.physical_keycode)
        var key_code := int(key_binding.keycode)
        if physical_code != 0 and (event.physical_keycode == physical_code or event.keycode == physical_code):
            return true
        if key_code != 0 and (event.keycode == key_code or event.physical_keycode == key_code):
            return true
    return false

func _key_name(code: int) -> String:
    var name := OS.get_keycode_string(code)
    return name if not name.is_empty() else str(code)

func _build_settings_ui() -> void:
    _settings_layer = CanvasLayer.new()
    _settings_layer.name = "SettingsLayer"
    _settings_layer.layer = 100
    _settings_layer.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(_settings_layer)
    _settings_backdrop = ColorRect.new()
    _settings_backdrop.color = Color(0.005, 0.015, 0.03, 0.78)
    _settings_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _settings_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
    _settings_backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
    _settings_backdrop.visible = false
    _settings_layer.add_child(_settings_backdrop)
    _settings_panel = _panel(_settings_layer, Vector2.ZERO, Vector2(640, 430), Color(0.018, 0.065, 0.105, 0.98), Color("#62e8dc"), 16)
    _settings_panel.name = "SettingsPanel"
    _settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS
    _place_hud(_settings_panel, Control.PRESET_CENTER, Vector2(-320, -215), Vector2(640, 430))
    var title := _ui_label(_settings_panel, "设置  /  CONTROLS", Vector2(32, 24), Vector2(576, 38), 26, Color("#f1fbff"))
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var intro := _ui_label(_settings_panel, "按 Esc 暂停设置；选择按键后按下新的键位即可更改。", Vector2(32, 68), Vector2(576, 28), 15, Color("#8fb4c4"))
    intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var row_y := 122.0
    for action in KEY_BINDING_ACTIONS:
        var label := _ui_label(_settings_panel, String(KEY_BINDING_LABELS[action]), Vector2(58, row_y + 8.0), Vector2(160, 36), 20, Color("#d9eef4"))
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        var rebind_action: String = action
        var button := _ui_button(_settings_panel, "", Vector2(300, row_y), Vector2(270, 44), Callable(self, "_begin_rebind").bind(rebind_action), false)
        _settings_buttons[action] = button
        row_y += 58.0
    _settings_status = _ui_label(_settings_panel, "", Vector2(58, 298), Vector2(524, 34), 15, Color("#ffcf7a"))
    _settings_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _settings_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _ui_button(_settings_panel, "恢复默认键位", Vector2(58, 350), Vector2(210, 44), _reset_key_bindings, false)
    _ui_button(_settings_panel, "继续游戏（Esc）", Vector2(372, 350), Vector2(210, 44), _close_settings, true)
    _settings_panel.visible = false
    _refresh_settings_ui()

func _refresh_settings_ui() -> void:
    for action in KEY_BINDING_ACTIONS:
        var button := _settings_buttons.get(action) as Button
        if button != null:
            button.text = "%s：%s" % [String(KEY_BINDING_LABELS[action]), _key_name(int(_key_bindings.get(action, KEY_BINDING_DEFAULTS[action])))]
    if _settings_status != null and _rebinding_action.is_empty():
        _settings_status.text = "地图、日志和加速键可以分别设置。"

func _begin_rebind(action: String) -> void:
    if not _settings_visible or not KEY_BINDING_ACTIONS.has(action):
        return
    _rebinding_action = action
    if _settings_status != null:
        _settings_status.text = "正在设置%s：请按下一个键（Esc 取消）" % String(KEY_BINDING_LABELS[action])

func _handle_rebind_input(event: InputEventKey) -> void:
    if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
        _rebinding_action = ""
        _refresh_settings_ui()
        return
    var code := int(event.physical_keycode) if event.physical_keycode != 0 else int(event.keycode)
    if code <= 0:
        return
    for action in KEY_BINDING_ACTIONS:
        if action != _rebinding_action and int(_key_bindings.get(action, -1)) == code:
            if _settings_status != null:
                _settings_status.text = "%s 已被占用，请换一个键。" % _key_name(code)
            return
    _key_bindings[_rebinding_action] = code
    _apply_key_binding(_rebinding_action, code)
    _save_key_bindings()
    _rebinding_action = ""
    _refresh_settings_ui()

func _reset_key_bindings() -> void:
    _rebinding_action = ""
    for action in KEY_BINDING_ACTIONS:
        var code := int(KEY_BINDING_DEFAULTS[action])
        _key_bindings[action] = code
        _apply_key_binding(action, code)
    _save_key_bindings()
    _refresh_settings_ui()

func _open_settings() -> void:
    if _settings_visible or not (game_started or ship_active):
        return
    _settings_visible = true
    _rebinding_action = ""
    _settings_previous_paused = get_tree().paused
    _settings_previous_process_mode = process_mode
    _settings_child_process_modes.clear()
    for child in get_children():
        _settings_child_process_modes[child] = child.process_mode
        if child != _settings_layer:
            child.process_mode = Node.PROCESS_MODE_PAUSABLE
    process_mode = Node.PROCESS_MODE_ALWAYS
    _settings_layer.process_mode = Node.PROCESS_MODE_ALWAYS
    _settings_backdrop.visible = true
    _settings_panel.visible = true
    _refresh_settings_ui()
    get_tree().paused = true

func _close_settings() -> void:
    if not _settings_visible:
        return
    _settings_visible = false
    _rebinding_action = ""
    _settings_panel.visible = false
    _settings_backdrop.visible = false
    get_tree().paused = _settings_previous_paused
    for child in get_children():
        if _settings_child_process_modes.has(child):
            child.process_mode = int(_settings_child_process_modes[child])
    process_mode = _settings_previous_process_mode
    _settings_child_process_modes.clear()

func _place_hud(control: Control, preset: int, offset: Vector2, dimensions: Vector2) -> void:
    control.set_anchors_and_offsets_preset(preset)
    control.position = offset
    # position is absolute after anchors are set; offsets keep the widget tied to its edge.
    control.offset_left = offset.x
    control.offset_top = offset.y
    control.offset_right = offset.x + dimensions.x
    control.offset_bottom = offset.y + dimensions.y

func _panel(parent: Node, position: Vector2, size: Vector2, fill: Color, border: Color, radius := 14) -> Panel:
    var panel := Panel.new()
    panel.position = position
    panel.size = size
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    style.shadow_color = Color(0, 0, 0, 0.38)
    style.shadow_size = 12
    panel.add_theme_stylebox_override("panel", style)
    parent.add_child(panel)
    return panel

func _ui_label(parent: Node, text: String, position: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.position = position
    label.size = size
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(label)
    return label

func _ui_button(parent: Control, text: String, position: Vector2, size: Vector2, callback: Callable, primary := false) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_NONE
    button.position = position
    button.size = size
    button.add_theme_font_size_override("font_size", 17)
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color("#17334a") if not primary else Color("#4fd5cf")
    normal.border_color = Color("#3a7188") if not primary else Color("#a8fff4")
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(9)
    var hover := normal.duplicate()
    hover.bg_color = Color("#24536c") if not primary else Color("#82eee1")
    var pressed := normal.duplicate()
    pressed.bg_color = Color("#0d2335") if not primary else Color("#35aeaa")
    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", pressed)
    button.add_theme_color_override("font_color", Color("#e8faff") if not primary else Color("#07222c"))
    button.add_theme_color_override("font_hover_color", Color("#ffffff") if not primary else Color("#062027"))
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _build_home_ui() -> void:
    _panel(_home_group, Vector2(54, 54), Vector2(520, 530), Color(0.025, 0.08, 0.13, 0.92), Color("#2e6a83"), 18)
    _ui_label(_home_group, "迷失太空", Vector2(88, 84), Vector2(420, 62), 44, Color("#f1fbff"))
    _ui_label(_home_group, "LOST IN SPACE  /  3D EXPEDITION", Vector2(91, 145), Vector2(430, 28), 14, Color("#65e1e0"))
    _ui_label(_home_group, "驾驶远征舰穿过未知航域，在霜烬星追踪异常回波、调查失联设施，理解星球的规律后带着全队安全返航。", Vector2(91, 194), Vector2(420, 82), 17, Color("#a7c4d3"))
    _ui_label(_home_group, "联机 · 1—4 名船员 · 正交 3D 舰桥", Vector2(91, 292), Vector2(420, 30), 14, Color("#78aabd"))
    _address_edit = LineEdit.new()
    _address_edit.placeholder_text = "主机 IP（加入时填写）"
    _address_edit.text = "127.0.0.1"
    _address_edit.position = Vector2(91, 340)
    _address_edit.size = Vector2(410, 46)
    _address_edit.add_theme_font_size_override("font_size", 16)
    _address_edit.add_theme_color_override("font_color", Color("#dff8ff"))
    _address_edit.add_theme_stylebox_override("normal", _input_style())
    _home_group.add_child(_address_edit)
    _host_button = _ui_button(_home_group, "创建主机 · 进入飞船准备区", Vector2(91, 402), Vector2(410, 48), _create_host, true)
    _join_button = _ui_button(_home_group, "加入已有主机", Vector2(91, 462), Vector2(410, 44), _join_host)
    _status_label = _ui_label(_home_group, "状态：请创建主机或加入已有主机", Vector2(91, 525), Vector2(440, 44), 15, Color("#8ff1a0"))

func _input_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.03, 0.11, 0.17, 0.95)
    style.border_color = Color("#37677c")
    style.set_border_width_all(1)
    style.set_corner_radius_all(8)
    style.content_margin_left = 14
    return style

func _build_room_ui() -> void:
    _panel(_room_group, Vector2(70, 66), Vector2(560, 565), Color(0.025, 0.08, 0.13, 0.94), Color("#2e6a83"), 18)
    _ui_label(_room_group, "飞船准备区", Vector2(104, 96), Vector2(450, 52), 38, Color("#f1fbff"))
    _ui_label(_room_group, "STARSHIP  /  CREW BAY", Vector2(107, 148), Vector2(420, 24), 13, Color("#65e1e0"))
    _ui_label(_room_group, "全队先在舰桥集合，再选择下一段航程。", Vector2(107, 192), Vector2(430, 32), 17, Color("#a7c4d3"))
    var crew_panel := _panel(_room_group, Vector2(104, 245), Vector2(480, 128), Color(0.04, 0.13, 0.19, 0.82), Color("#254d62"), 12)
    _ui_label(crew_panel, "远征舰 · 归航号", Vector2(20, 16), Vector2(430, 28), 20, Color("#dff8ff"))
    _ui_label(crew_panel, "● 船员 1     等待其他船员加入\n● 联机端口 24567     最大 4 人", Vector2(20, 52), Vector2(430, 64), 15, Color("#8fb4c4"))
    _room_status = _ui_label(_room_group, "主机已创建，准备选择航线。", Vector2(107, 398), Vector2(440, 48), 16, Color("#8ff1a0"))
    _ui_button(_room_group, "打开星际航线图", Vector2(104, 478), Vector2(232, 50), _show_route, true)
    _ui_button(_room_group, "返回主界面", Vector2(352, 478), Vector2(232, 50), _show_home)

func _build_route_ui() -> void:
    _panel(_route_group, Vector2(54, 54), Vector2(610, 565), Color(0.025, 0.08, 0.13, 0.94), Color("#2e6a83"), 18)
    _ui_label(_route_group, "选择下一段航程", Vector2(88, 86), Vector2(500, 48), 38, Color("#f1fbff"))
    _ui_label(_route_group, "FLIGHT MAP  /  航线已锁定", Vector2(91, 136), Vector2(460, 24), 13, Color("#65e1e0"))
    _ui_label(_route_group, "由主机确认目的地，全队将同步登陆。", Vector2(91, 178), Vector2(460, 30), 17, Color("#a7c4d3"))
    var planet_card := _panel(_route_group, Vector2(91, 236), Vector2(536, 188), Color(0.04, 0.14, 0.2, 0.92), Color("#59c8d1"), 13)
    _ui_label(planet_card, "01  /  可登陆", Vector2(22, 18), Vector2(470, 25), 14, Color("#66e9df"))
    _ui_label(planet_card, "霜烬星", Vector2(22, 52), Vector2(280, 42), 30, Color("#e9fbff"))
    _ui_label(planet_card, "FROST ASH\n环境调查 · 气象信标 · 暴风雪撤离", Vector2(22, 100), Vector2(420, 52), 15, Color("#9ebdca"))
    _land_button = _ui_button(planet_card, "确认航程  →", Vector2(334, 116), Vector2(176, 48), _confirm_land, true)
    _route_status = _ui_label(_route_group, "", Vector2(91, 424), Vector2(520, 24), 14, Color("#8fb4c4"))
    _ui_label(_route_group, "02  /  尚未开放     电磁星球", Vector2(91, 454), Vector2(500, 28), 16, Color("#668392"))
    _ui_button(_route_group, "← 返回主舱", Vector2(91, 516), Vector2(240, 46), _show_room)

func _set_screen(view: String) -> void:
    _screen_view = view
    _home_group.visible = view == "home"
    _room_group.visible = view == "room"
    _route_group.visible = view == "route"

func _show_home() -> void:
    if _settings_visible:
        _close_settings()
    if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
        multiplayer.multiplayer_peer.close()
    is_host = false
    multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
    _clear_players()
    connected_ids.clear()
    if _ship_session != null:
        _ship_session.show_home()
    _menu_layer.visible = true
    _game_layer.visible = false
    _set_screen("home")

func _show_room() -> void:
    if ship_active:
        _ship_session.show_gameplay()
        return
    _set_screen("room")
    if _room_status != null:
        _room_status.text = "主机已创建，准备选择航线。"

func _show_route() -> void:
    _set_screen("route")
    _menu_layer.visible = true
    if _land_button != null:
        _land_button.disabled = not is_host
    if _route_status != null:
        _route_status.text = "由主机确认登陆" if is_host else "等待主机确认登陆"

func _build_menu_world() -> void:
    _menu_world = Node3D.new()
    _menu_world.name = "ThreeDBridgeMenu"
    add_child(_menu_world)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("#020816")
    sky_material.sky_horizon_color = Color("#173b54")
    sky_material.ground_bottom_color = Color("#020712")
    sky_material.ground_horizon_color = Color("#0c2638")
    sky_material.sun_angle_max = 12.0
    sky.sky_material = sky_material
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#73a9bb")
    env.ambient_light_energy = 0.78
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.environment = env
    _menu_world.add_child(environment)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-40.0, -28.0, 0.0)
    light.light_color = Color("#b6e9ff")
    light.light_energy = 1.35
    light.shadow_enabled = true
    _menu_world.add_child(light)
    var deck := MeshInstance3D.new()
    var deck_mesh := PlaneMesh.new()
    deck_mesh.size = Vector2(18.0, 13.0)
    deck.mesh = deck_mesh
    deck.position = Vector3(0.0, -1.25, 0.0)
    deck.material_override = _menu_material(Color("#0d2638"), Color("#103c55"), 0.18)
    _menu_world.add_child(deck)
    for ring_size in [4.5, 7.5, 10.0]:
        var ring := MeshInstance3D.new()
        var ring_mesh := TorusMesh.new()
        ring_mesh.inner_radius = ring_size
        ring_mesh.outer_radius = ring_size + 0.018
        ring.mesh = ring_mesh
        ring.position = Vector3(0.0, -1.20, 0.0)
        ring.material_override = _menu_material(Color("#173d51"), Color("#2bacc3"), 0.32)
        _menu_world.add_child(ring)
    _menu_camera = Camera3D.new()
    _menu_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    _menu_camera.size = 13.0
    _menu_camera.position = Vector3(0.0, 6.8, 14.5)
    _menu_camera.current = true
    _menu_world.add_child(_menu_camera)
    _menu_camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
    _menu_planet = Node3D.new()
    _menu_planet.name = "FrostAshPlanet"
    _menu_planet.position = Vector3(4.4, -0.9, -2.2)
    _menu_world.add_child(_menu_planet)
    var planet := MeshInstance3D.new()
    var planet_mesh := SphereMesh.new()
    planet_mesh.radius = 3.2
    planet_mesh.height = 6.4
    planet.mesh = planet_mesh
    planet.material_override = _menu_material(Color("#1e5a75"), Color("#42c7e6"), 0.55)
    _menu_planet.add_child(planet)
    var planet_glow := MeshInstance3D.new()
    var glow_mesh := SphereMesh.new()
    glow_mesh.radius = 3.34
    glow_mesh.height = 6.68
    planet_glow.mesh = glow_mesh
    var glow_material := StandardMaterial3D.new()
    glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    glow_material.albedo_color = Color(0.25, 0.82, 0.96, 0.065)
    planet_glow.material_override = glow_material
    _menu_planet.add_child(planet_glow)
    var ice_cap := MeshInstance3D.new()
    var cap_mesh := SphereMesh.new()
    cap_mesh.radius = 1.9
    cap_mesh.height = 3.8
    ice_cap.mesh = cap_mesh
    ice_cap.position = Vector3(0.0, 2.0, -2.4)
    ice_cap.scale = Vector3(1.0, 0.36, 1.0)
    ice_cap.material_override = _menu_material(Color("#b9f2f6"), Color("#9cebf0"), 0.35)
    _menu_planet.add_child(ice_cap)
    var planet_label := Label3D.new()
    planet_label.text = "霜烬星  ·  FROST ASH"
    planet_label.position = Vector3(0.0, -4.0, 0.0)
    planet_label.font_size = 32
    planet_label.modulate = Color("#b8f4ff")
    _menu_planet.add_child(planet_label)
    _menu_ship = Node3D.new()
    _menu_ship.name = "BridgeShip"
    _menu_ship.position = Vector3(-3.0, 2.6, 1.0)
    _menu_world.add_child(_menu_ship)
    var hull := MeshInstance3D.new()
    var hull_mesh := BoxMesh.new()
    hull_mesh.size = Vector3(3.8, 0.7, 1.2)
    hull.mesh = hull_mesh
    hull.material_override = _menu_material(Color("#8ca7b5"), Color("#8ce8ff"), 0.35)
    _menu_ship.add_child(hull)
    var cockpit := MeshInstance3D.new()
    var cockpit_mesh := SphereMesh.new()
    cockpit_mesh.radius = 0.55
    cockpit_mesh.height = 0.65
    cockpit.position = Vector3(1.25, 0.32, 0.0)
    cockpit.mesh = cockpit_mesh
    cockpit.material_override = _menu_material(Color("#205d78"), Color("#67e1ff"), 0.6)
    _menu_ship.add_child(cockpit)
    for wing_z in [-0.9, 0.9]:
        var wing := MeshInstance3D.new()
        var wing_mesh := BoxMesh.new()
        wing_mesh.size = Vector3(1.8, 0.16, 0.5)
        wing.position = Vector3(-0.65, -0.25, wing_z)
        wing.mesh = wing_mesh
        wing.material_override = _menu_material(Color("#386174"), Color("#55dfff"), 0.2)
        _menu_ship.add_child(wing)
    for engine_z in [-0.42, 0.42]:
        var engine := MeshInstance3D.new()
        var engine_mesh := CylinderMesh.new()
        engine_mesh.top_radius = 0.12
        engine_mesh.bottom_radius = 0.18
        engine_mesh.height = 0.42
        engine.position = Vector3(-1.95, 0.02, engine_z)
        engine.rotation_degrees.z = 90.0
        engine.mesh = engine_mesh
        engine.material_override = _menu_material(Color("#e7b85c"), Color("#ffbf5a"), 2.2)
        _menu_ship.add_child(engine)
    var ship_label := Label3D.new()
    ship_label.text = "远征舰 · LOST IN SPACE"
    ship_label.position = Vector3(0.0, 1.0, 0.0)
    ship_label.font_size = 24
    ship_label.modulate = Color("#e3faff")
    _menu_ship.add_child(ship_label)
    _add_route_segment(Vector3(-1.0, 0.1, -0.4), Vector3(2.6, 0.3, -1.3), Color("#59d6e8"))
    _add_route_segment(Vector3(2.6, 0.3, -1.3), Vector3(4.2, 0.2, -1.9), Color("#f4d278"))
    var stars := [Vector3(-6, 5, -2), Vector3(-1, 7, -5), Vector3(7, 5, -7), Vector3(8, 1, -6), Vector3(-7, 1, -4), Vector3(0, 3, -8), Vector3(6, 7, -3)]
    for star_position in stars:
        var star := MeshInstance3D.new()
        var star_mesh := SphereMesh.new()
        star_mesh.radius = 0.045
        star_mesh.height = 0.09
        star.position = star_position
        star.mesh = star_mesh
        star.material_override = _menu_material(Color("#d7f8ff"), Color("#83e9ff"), 1.5)
        _menu_world.add_child(star)

func _add_route_segment(from_point: Vector3, to_point: Vector3, color: Color) -> void:
    var segment := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    var midpoint := (from_point + to_point) * 0.5
    var length := from_point.distance_to(to_point)
    mesh.size = Vector3(length, 0.035, 0.035)
    segment.mesh = mesh
    segment.position = midpoint
    segment.material_override = _menu_material(color, color, 1.25)
    _menu_world.add_child(segment)
    segment.look_at(to_point, Vector3.UP)

func _menu_material(color: Color, emission_color: Color, emission_energy: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = emission_color
    material.emission_energy_multiplier = emission_energy
    material.roughness = 0.58
    return material

func _animate_menu_world() -> void:
    if _menu_ship != null:
        _menu_ship.position.y = 2.6 + sin(_menu_time * 0.8) * 0.16
        _menu_ship.rotation.y = sin(_menu_time * 0.22) * 0.08
    if _menu_planet != null:
        _menu_planet.rotation.y += 0.0015

func _create_host() -> void:
    var peer := ENetMultiplayerPeer.new()
    var result := peer.create_server(network_port, MAX_PLAYERS)
    if result != OK:
        _set_status("创建主机失败：%s" % error_string(result))
        return
    multiplayer.multiplayer_peer = peer
    is_host = true
    connected_ids = [1]
    _ship_session.load_state()
    _ship_session.enter_ship(true, connected_ids, _ship_session.snapshot())
    _set_status("主机已创建，已进入归航号主舱。")

func _join_host() -> void:
    var peer := ENetMultiplayerPeer.new()
    var result := peer.create_client(_address_edit.text.strip_edges(), network_port)
    if result != OK:
        _set_status("加入主机失败：%s" % error_string(result))
        return
    multiplayer.multiplayer_peer = peer
    is_host = false
    _set_status("正在连接主机……")

func _on_connected_to_server() -> void:
    connected_ids = [1, multiplayer.get_unique_id()]
    if not ship_active and not game_started:
        _show_room()
    if _room_status != null:
        _room_status.text = "已连接归航号，等待同步船舱。"
    _set_status("已连接主机，等待主机选择航线……")

func _on_connection_failed() -> void:
    _set_status("连接失败，请检查主机 IP 和端口。")

func _on_peer_connected(peer_id: int) -> void:
    if not is_host:
        return
    if not connected_ids.has(peer_id):
        connected_ids.append(peer_id)
    if ship_active:
        _ship_session.add_peer(peer_id)
        return
    spawn_player_for_peer.rpc(peer_id)
    sync_full_state.rpc_id(peer_id, _world_snapshot())
    _set_status("玩家 %d 已加入 3D 霜烬星。" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
    connected_ids.erase(peer_id)
    _ship_session.remove_peer(peer_id)
    if players.has(peer_id):
        players[peer_id].queue_free()
        players.erase(peer_id)

func _on_server_disconnected() -> void:
    if game_started:
        return_to_ship("主机已断开连接。")
    _show_home()
    _set_status("主机已断开连接，请重新创建或加入房间。")

func _confirm_land() -> void:
    _ship_session.confirm_land()

func _clear_players() -> void:
    for player in players.values():
        remove_child(player)
        (player as Node).queue_free()
    players.clear()

func _start_planet() -> void:
    if game_started:
        return
    if _settings_visible:
        _close_settings()
    var departure := _vitals_snapshot() if ship_active else []
    _ship_session.leave()
    _ship_session.disable_menu_environment()
    _clear_players()
    game_started = true
    mission_completed = false
    mission_failed = false
    mission_summary = ""
    mission_return_timer = 0.0
    mission_elapsed = 0.0
    salvage_value = 0
    contract_sync_accumulator = 0.0
    knowledge_flags.clear()
    anomaly_resolved = false
    ending_choice = ""
    rift_valve_open = false
    signal_mode = "neutral"
    signal_lure_until = 0.0
    signal_lure_position = Vector3.ZERO
    signal_cooldown_until = 0.0
    extraction_enabled = false
    extraction_progress = 0.0
    storm_active = false
    storm_elapsed = 0.0
    storm_remaining = 0.0
    story_elapsed = 0.0
    story_flags.clear()
    enemy_trigger_flags.clear()
    enemy_spawn_center = Vector2(4.0, -2.0)
    reviving.clear()
    revive_progress.clear()
    _story_timer = 0.0
    discovered_clues.clear()
    scan_revealed_clues.clear()
    scan_device_active = false
    scan_device_position = Vector3.ZERO
    scan_peer_id = -1
    scan_remaining = 0.0
    scan_cooldown = 0.0
    map_markers.clear()
    next_marker_id = 1
    journal_entries.clear()
    discovered_regions.clear()
    _journal_visible = false
    _hide_clue_minigame()
    if _journal_panel != null:
        _journal_panel.visible = false
    _thought_timer = 0.0
    if is_host:
        _prepare_layout()
    elif beacon_positions.is_empty():
        beacon_positions.assign(BEACON_POSITIONS)
        crate_positions.assign(CRATE_POSITIONS)
        sample_positions.assign(FrostMapLayout.SAMPLE_CORNERS)
    if _menu_world != null:
        _menu_world.visible = false
    _build_world()
    _record_journal("登陆记录", "霜烬星的三座气象信标在十七小时前同时失联。旧气象站记录、冰层裂谷热脉和废弃通信阵列的回放，可能解释信号为何从地底返回。")
    _record_journal("当前路线", "先部署扫描器寻找第一座信标；第一座信标恢复后，回波会指向旧气象站。调查顺序会逐步打开下一条路。")
    _record_journal("地表设备", "出发前可用 E 呼叫联络终端、解冻应急补给箱。沿途的青色设备和队员遗物可以操作，靠近会显示提示；修理时留在附近，地图会登记发现过的设备。")
    _game_layer.visible = true
    _menu_layer.visible = false
    var focused := get_viewport().gui_get_focus_owner()
    if focused != null:
        focused.release_focus()
    for peer_id in connected_ids:
        if is_host:
            spawn_player_for_peer.rpc(peer_id)
        else:
            spawn_player_for_peer(peer_id)
    sync_vitals(departure)
    if is_host:
        enemy_spawned = false
        enemy_wave_index = 0
        enemy_wave_timer = 0.0
        sync_full_state.rpc(_world_snapshot())
        sync_contract_state.rpc(mission_elapsed, salvage_value, knowledge_flags.keys(), taken_samples, scan_revealed_clues)

func _prepare_layout() -> void:
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    route_seed = rng.randi()
    beacon_positions.clear()
    crate_positions.clear()
    sample_positions.clear()
    # 目标只在各区域预设的角落之间随机，保证每个目标都落在有意义的地点。
    beacon_positions = FrostMapLayout.get_random_positions(FrostMapLayout.BEACON_CORNERS, 3, rng, 3.2)
    crate_positions = FrostMapLayout.get_random_positions(FrostMapLayout.CRATE_CORNERS, 4, rng, 2.0)
    sample_positions = FrostMapLayout.get_random_positions(FrostMapLayout.SAMPLE_CORNERS, 2, rng, 1.0)
    _prepare_exploration_clues()

func _prepare_exploration_clues() -> void:
    exploration_clues.clear()
    var clue_id := 1
    var safehouse := SAFEHOUSE
    for index in beacon_positions.size():
        var target := Vector2(beacon_positions[index])
        var direction := target - safehouse
        if direction.length() < 0.1:
            direction = Vector2.RIGHT
        direction = direction.normalized()
        var side := Vector2(-direction.y, direction.x)
        exploration_clues.append({"id": clue_id, "position": target - direction * 4.2 + side * 1.1, "kind": "beacon", "target_id": index + 1})
        clue_id += 1
    for index in crate_positions.size():
        var target := Vector2(crate_positions[index])
        var direction := target - safehouse
        if direction.length() < 0.1:
            direction = Vector2.RIGHT
        direction = direction.normalized()
        var side := Vector2(-direction.y, direction.x)
        exploration_clues.append({"id": clue_id, "position": target - direction * 3.2 - side * 1.0, "kind": "crate", "target_id": index + 1})
        clue_id += 1
    for index in sample_positions.size():
        var target := Vector2(sample_positions[index])
        var direction := target - safehouse
        if direction.length() < 0.1:
            direction = Vector2.RIGHT
        direction = direction.normalized()
        var side := Vector2(-direction.y, direction.x)
        exploration_clues.append({"id": clue_id, "position": target - direction * 2.5 + side * 0.8, "kind": "sample", "target_id": index + 1})
        clue_id += 1
    for landmark in LANDMARK_DATA:
        exploration_clues.append({
            "id": clue_id,
            "position": Vector2(landmark.get("position", Vector2.ZERO)),
            "kind": "landmark",
            "landmark_id": String(landmark.get("id", "")),
            "name": String(landmark.get("name", "未知地标")),
            "region": String(landmark.get("region", "未知区域")),
            "thought": String(landmark.get("thought", "这里留下了不自然的痕迹。")),
            "entry": String(landmark.get("entry", "地标记录已加入日志。"))
        })
        clue_id += 1

func _build_world() -> void:
    _world_root = Node3D.new()
    _world_root.name = "FrostAsh3DWorld"
    add_child(_world_root)
    _object_tags.clear()
    _world_labels.clear()
    _attack_ready_at.clear()
    _build_environment()
    _build_ground()
    for raw in FrostMapLayout.OBSTACLES:
        var obstacle := OBSTACLE_SCENE.instantiate() as FrostObstacle3D
        _world_root.add_child(obstacle)
        obstacle.setup(raw[0], raw[1], float(raw[3]), int(raw[2]))
        obstacles.append(obstacle)
    _build_zone_visuals()
    _build_beacons()
    _build_crates()
    _build_samples()
    _build_exploration_clues()
    _build_extraction()
    _build_scan_visual()
    if _field_interactions == null:
        _field_interactions = FROST_FIELD_INTERACTIONS.new(self)
    _field_interactions.build()

func _build_environment() -> void:
    _environment = WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("#030914")
    sky_material.sky_horizon_color = Color("#1f4d62")
    sky_material.ground_bottom_color = Color("#02060d")
    sky_material.ground_horizon_color = Color("#0d2e44")
    sky.sky_material = sky_material
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#94c8d8")
    env.ambient_light_energy = 0.85
    env.fog_enabled = true
    env.fog_light_color = Color("#1a4a5f")
    env.fog_density = 0.005
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.glow_enabled = true
    env.glow_intensity = 0.45
    env.glow_strength = 0.85
    env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
    _environment.environment = env
    _world_root.add_child(_environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55.0, -32.0, 0.0)
    sun.light_color = Color("#d8f5ff")
    sun.light_energy = 1.45
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 80.0
    _world_root.add_child(sun)
    var fill := OmniLight3D.new()
    fill.name = "FrostBlueFill"
    fill.position = Vector3(-6.0, 5.0, 7.0)
    fill.light_color = Color("#5de4ff")
    fill.light_energy = 3.8
    fill.omni_range = 16.0
    _world_root.add_child(fill)
    var accent_fill := OmniLight3D.new()
    accent_fill.name = "AccentFill"
    accent_fill.position = Vector3(8.0, 6.0, -5.0)
    accent_fill.light_color = Color("#88d4f5")
    accent_fill.light_energy = 2.2
    accent_fill.omni_range = 12.0
    _world_root.add_child(accent_fill)

var _drift_noise: FastNoiseLite
var _ripple_noise: FastNoiseLite

func _build_ground() -> void:
    var ground_body := StaticBody3D.new()
    ground_body.name = "FrozenGround"
    ground_body.collision_layer = 2
    ground_body.collision_mask = 1
    _world_root.add_child(ground_body)
    _drift_noise = FastNoiseLite.new()
    _drift_noise.seed = 20261012
    _drift_noise.frequency = 0.055
    _drift_noise.fractal_octaves = 3
    _ripple_noise = FastNoiseLite.new()
    _ripple_noise.seed = 771
    _ripple_noise.frequency = 0.19
    _ripple_noise.fractal_octaves = 2
    var ground := MeshInstance3D.new()
    ground.name = "SnowTerrain"
    ground.mesh = _build_terrain_mesh()
    # 区域不靠贴色块表达，而是烘进顶点色：整块地是一张连续的雪面。
    var terrain_material := StandardMaterial3D.new()
    terrain_material.vertex_color_use_as_albedo = true
    terrain_material.roughness = 0.4
    terrain_material.metallic = 0.04
    ground.material_override = terrain_material
    ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    ground_body.add_child(ground)
    # 碰撞保持水平：玩家没有重力和上坡逻辑，视觉起伏不参与碰撞。
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(MAP_SIZE.x, 0.2, MAP_SIZE.y)
    shape.shape = box
    shape.position.y = -0.1
    ground_body.add_child(shape)
    var half_map := MAP_SIZE * 0.5
    for edge in [[Vector3(0, 0.8, -half_map.y), Vector3(MAP_SIZE.x, 1.6, 0.4)], [Vector3(0, 0.8, half_map.y), Vector3(MAP_SIZE.x, 1.6, 0.4)], [Vector3(-half_map.x, 0.8, 0), Vector3(0.4, 1.6, MAP_SIZE.y)], [Vector3(half_map.x, 0.8, 0), Vector3(0.4, 1.6, MAP_SIZE.y)]]:
        _add_boundary(edge[0], edge[1])
    for region_name in FrostMapLayout.REGIONS:
        var region: Dictionary = FrostMapLayout.REGIONS[region_name]
        var center := Vector2(region.get("center", Vector2.ZERO))
        var is_round := region.has("radius")
        var half := Vector2(float(region.get("radius", 8.0)), float(region.get("radius", 8.0)))
        if not is_round:
            half = Vector2(float(region.get("width", 12.0)) * 0.5, float(region.get("height", 12.0)) * 0.5)
        _scatter_region_details(_world_root, region_name, center, half, _region_color(String(region.get("kind", ""))), is_round)
    _build_ice_cliffs()

func _build_terrain_mesh() -> ArrayMesh:
    # 带噪声起伏的雪原网格。明暗来自真实法线，区域和通路靠顶点色表达，
    # 所以俯视画面既不是平板，也没有贴片接缝。
    # 网格比可行走范围更大：地图边缘之外继续有冰原，玩家在角落出生时
    # 视野里不会出现黑色虚空。
    var segments := 168
    var half := (MAP_SIZE + Vector2(TERRAIN_MARGIN, TERRAIN_MARGIN) * 2.0) * 0.5
    var span := half * 2.0
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var step := Vector2(span.x / float(segments), span.y / float(segments))
    for row in segments:
        for col in segments:
            var x0 := -half.x + float(col) * step.x
            var z0 := -half.y + float(row) * step.y
            _push_terrain_quad(st, Vector2(x0, z0), Vector2(x0 + step.x, z0), Vector2(x0 + step.x, z0 + step.y), Vector2(x0, z0 + step.y))
    st.generate_normals()
    return st.commit()

func _push_terrain_quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> void:
    for point in [a, b, c, a, c, d]:
        st.set_color(_terrain_color(point))
        st.add_vertex(Vector3(point.x, terrain_height(point), point.y))

func terrain_height(point: Vector2) -> float:
    # 振幅刻意压得比"好看"更小：碰撞面是平的，起伏太大角色会像陷进雪里。
    var large := _drift_noise.get_noise_2d(point.x, point.y) * 0.17
    var small := _ripple_noise.get_noise_2d(point.x, point.y) * 0.04
    return large + small

func _terrain_color(point: Vector2) -> Color:
    # 深处是压实的暗冰，进入区域后过渡到该区的雪色，通路再提亮一档。
    var color := Color("#1e3a4a")
    var best_weight := 0.0
    var best_tint := color
    for region_name in FrostMapLayout.REGIONS:
        var region: Dictionary = FrostMapLayout.REGIONS[region_name]
        var center := Vector2(region.get("center", Vector2.ZERO))
        var weight := 0.0
        if region.has("radius"):
            var radius := float(region["radius"])
            weight = 1.0 - clampf((point.distance_to(center) - radius * 0.72) / maxf(radius * 0.5, 0.1), 0.0, 1.0)
        else:
            var extents := Vector2(float(region.get("width", 12.0)) * 0.5, float(region.get("height", 12.0)) * 0.5)
            var inside := extents - Vector2(absf(point.x - center.x), absf(point.y - center.y))
            var margin := minf(inside.x, inside.y)
            weight = clampf(margin / 3.4 + 0.55, 0.0, 1.0)
        if weight > best_weight:
            best_weight = weight
            best_tint = _region_color(String(region.get("kind", "")))
    color = color.lerp(best_tint, best_weight)
    for pathway in FrostMapLayout.PATHWAYS:
        var corridor := _pathway_proximity(point, pathway)
        if corridor <= 0.0:
            continue
        var target := Color("#b9dce8") if bool(pathway.get("fragile", false)) else Color("#5d8296")
        color = color.lerp(target, corridor * 0.6)
    # 低频的雪面深浅。用连续噪声而不是逐点二分，避免出现织物格纹。
    var grain := _ripple_noise.get_noise_2d(point.x * 0.9, point.y * 0.9)
    color = color.lerp(color.lightened(0.16), clampf(grain, 0.0, 1.0) * 0.5)
    return color

func _pathway_proximity(point: Vector2, pathway: Dictionary) -> float:
    var a := Vector2(pathway.get("from", Vector2.ZERO))
    var b := Vector2(pathway.get("to", Vector2.ZERO))
    var span := b - a
    var length_squared := span.length_squared()
    if length_squared <= 0.0001:
        return 0.0
    var t := clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
    var distance := point.distance_to(a + span * t)
    var half_width := float(pathway.get("width", 6.0)) * 0.5
    var inside := half_width * 0.82
    if distance <= inside:
        return 1.0
    if distance >= inside + 2.2:
        return 0.0
    return 1.0 - (distance - inside) / 2.2

func _gloss_material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = 0.05
    return material

func _scatter_region_details(parent: Node3D, region_name: String, center: Vector2, half: Vector2, base_color: Color, is_round: bool) -> void:
    # 区域细节成簇分布：雪堆带碎冰，而不是均匀撒圆点。
    # 所有的碎冰统一朝向一个方向，读起来像风塑出的雪脊。
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(region_name)
    var wind := rng.randf_range(-0.5, 0.5)
    var cluster_count := clampi(int(half.x * half.y * 0.035), 4, 14)
    _scatter_multimesh_ice(parent, region_name, center, half, base_color, is_round, rng)
    for cluster in cluster_count:
        var spot := Vector2(rng.randf_range(-half.x * 0.86, half.x * 0.86), rng.randf_range(-half.y * 0.86, half.y * 0.86))
        if is_round and spot.length() > half.x * 0.84:
            continue
        var spot2 := Vector2(center.x + spot.x, center.y + spot.y)
        var spot3 := Vector3(spot2.x, terrain_height(spot2) * 0.55, spot2.y)
        # 雪堆
        var mound := MeshInstance3D.new()
        var mound_mesh := SphereMesh.new()
        mound_mesh.radius = 1.0
        mound_mesh.height = 2.0
        mound.mesh = mound_mesh
        var mound_radius := rng.randf_range(0.9, 2.4)
        var mound_height := rng.randf_range(0.28, 0.55)
        mound.position = spot3 + Vector3(0.0, mound_height * 0.5, 0.0)
        mound.rotation_degrees.y = rad_to_deg(wind)
        # 厚度必须够：贴地的扁球看起来是水洼或贴纸，不是雪包。
        mound.scale = Vector3(mound_radius * rng.randf_range(1.1, 1.7), mound_height, mound_radius)
        # 必须比雪面暗。比地面亮的话会被读成积水，而不是隆起的雪脊。
        mound.material_override = _gloss_material(base_color.darkened(0.16).lerp(Color("#2c4a5c"), 0.34), 0.72)
        parent.add_child(mound)
        # 堆上的碎冰
        for piece_index in rng.randi_range(2, 5):
            var shard := MeshInstance3D.new()
            var shard_mesh := BoxMesh.new()
            var shard_width := rng.randf_range(0.18, 0.55)
            var shard_height := rng.randf_range(0.22, 0.9)
            shard_mesh.size = Vector3(shard_width, shard_height, rng.randf_range(0.14, 0.4))
            shard.mesh = shard_mesh
            shard.position = spot3 + Vector3(
                rng.randf_range(-mound_radius, mound_radius) * 0.8,
                shard_height * 0.3,
                rng.randf_range(-mound_radius, mound_radius) * 0.8
            )
            shard.rotation_degrees = Vector3(rng.randf_range(-26.0, 26.0), rad_to_deg(wind) + rng.randf_range(-40.0, 40.0), rng.randf_range(-22.0, 22.0))
            shard.material_override = _gloss_material(Color("#cdeaf6"), 0.2)
            parent.add_child(shard)
        # 另一半簇配几道裂纹
        if rng.randf() < 0.45:
            for crack_index in rng.randi_range(1, 3):
                var crack := MeshInstance3D.new()
                var crack_mesh := BoxMesh.new()
                crack_mesh.size = Vector3(rng.randf_range(1.6, 4.2), 0.02, rng.randf_range(0.06, 0.16))
                crack.mesh = crack_mesh
                crack.position = spot3 + Vector3(rng.randf_range(-1.4, 1.4), 0.015, rng.randf_range(-1.4, 1.4))
                crack.rotation_degrees.y = rad_to_deg(wind) + rng.randf_range(-30.0, 30.0)
                crack.material_override = _material(base_color.darkened(0.6), 0.05)
                parent.add_child(crack)

func _scatter_multimesh_ice(parent: Node3D, region_name: String, center: Vector2, half: Vector2, base_color: Color, is_round: bool, rng: RandomNumberGenerator) -> void:
    # 装饰层使用 MultiMesh：每个区域一个批次，避免为几十枚碎冰各建一个绘制实例。
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.42, 0.8, 0.28)
    var material := _gloss_material(base_color.lightened(0.24), 0.3)
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_colors = false
    multimesh.mesh = mesh
    multimesh.instance_count = 28
    for index in multimesh.instance_count:
        var point := Vector2(rng.randf_range(-half.x * 0.9, half.x * 0.9), rng.randf_range(-half.y * 0.9, half.y * 0.9))
        if is_round and point.length() > half.x * 0.88:
            point = point.normalized() * half.x * 0.72
        var world := Vector3(center.x + point.x, terrain_height(center + point) + 0.38, center.y + point.y)
        var scale := Vector3(rng.randf_range(0.55, 1.4), rng.randf_range(0.65, 1.5), rng.randf_range(0.55, 1.2))
        var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(scale)
        multimesh.set_instance_transform(index, Transform3D(basis, world))
    var instance := MultiMeshInstance3D.new()
    instance.name = "DecorMultiMesh_%s" % region_name
    instance.multimesh = multimesh
    instance.material_override = material
    # 显式 AABB 防止实例在远处被错误裁剪；覆盖该区域并留出地形噪声余量。
    instance.custom_aabb = AABB(Vector3(center.x - half.x - 3.0, -1.0, center.y - half.y - 3.0), Vector3(half.x * 2.0 + 6.0, 5.0, half.y * 2.0 + 6.0))
    parent.add_child(instance)

func _region_color(kind: String) -> Color:
    # 六个区域各自有明确的明度和冷暖，玩家一眼能认出自己换了区。
    match kind:
        "start": return Color("#5c6f7a")      # 冷灰青：着陆区被压实的地面
        "canyon": return Color("#23414f")     # 深冷蓝：峡谷阴影
        "plateau": return Color("#b3cfda")    # 最亮：台地积雪
        "lake": return Color("#3d7f91")       # 青绿：冰湖
        "rift": return Color("#5c3f36")       # 暖褐：地热裂谷
        "wreckage": return Color("#5a666d")   # 中性灰：金属残骸
        "extraction": return Color("#3f6b52") # 暗绿：撤离点
        _: return Color("#1e3a4a")

func _build_ice_cliffs() -> void:
    for cliff in FrostMapLayout.ICE_CLIFFS:
        var center := Vector2(cliff[0])
        var size := Vector2(cliff[1])
        var height := ICE_CLIFF_HEIGHT
        # 冰崖视觉和碰撞共用加厚后的尺寸，避免角色贴着薄墙边缘穿模。
        var blocking_size := size + Vector2(ICE_CLIFF_THICKNESS, ICE_CLIFF_THICKNESS)
        var cliff_root := Node3D.new()
        cliff_root.name = "IceCliff"
        cliff_root.position = Vector3(center.x, 0.0, center.y)
        _world_root.add_child(cliff_root)
        # 冰体：下深上浅的三段色帯，模拟冰层受压后由深到透的变化
        var bands := [
            {"h": height * 0.42, "color": Color("#28455a")},
            {"h": height * 0.34, "color": Color("#41697f")},
            {"h": height * 0.24, "color": Color("#7fa5b6")},
        ]
        var base_y := 0.0
        for band in bands:
            var band_h := float(band["h"])
            var band_node := MeshInstance3D.new()
            var band_mesh := BoxMesh.new()
            band_mesh.size = Vector3(blocking_size.x, band_h, blocking_size.y)
            band_node.mesh = band_mesh
            band_node.position.y = base_y + band_h * 0.5
            band_node.material_override = _gloss_material(band["color"], 0.28)
            band_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
            cliff_root.add_child(band_node)
            base_y += band_h
        # 冰冠：不规则的棱柱，取代原来的纯白平板
        var rng := RandomNumberGenerator.new()
        rng.seed = int(center.x * 31.0 + center.y * 17.0 + size.x * 7.0)
        var crown_span := maxf(blocking_size.x, blocking_size.y)
        var segments := clampi(int(crown_span / 3.2), 3, 12)
        var along_x := size.x >= size.y
        var crown_length := size.x if along_x else size.y
        for index in segments:
            var segment := MeshInstance3D.new()
            var segment_mesh := CylinderMesh.new()
            var radius := rng.randf_range(0.7, 1.5)
            segment_mesh.top_radius = radius * rng.randf_range(0.35, 0.8)
            segment_mesh.bottom_radius = radius
            segment_mesh.height = rng.randf_range(0.5, 1.5)
            segment_mesh.radial_segments = rng.randi_range(5, 7)
            segment.mesh = segment_mesh
            var t := (float(index) + 0.5) / float(segments) - 0.5
            var jitter := rng.randf_range(-0.4, 0.4)
            var offset := Vector3.ZERO
            if along_x:
                offset = Vector3(t * crown_length * 0.92, 0.0, jitter)
            else:
                offset = Vector3(jitter, 0.0, t * crown_length * 0.92)
            segment.position = offset + Vector3(0.0, base_y + segment_mesh.height * 0.34, 0.0)
            segment.rotation_degrees = Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(0.0, 360.0), rng.randf_range(-9.0, 9.0))
            segment.material_override = _gloss_material(Color("#a9c6d4"), 0.24)
            segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
            cliff_root.add_child(segment)
        _add_boundary(Vector3(center.x, height * 0.5, center.y), Vector3(blocking_size.x, height, blocking_size.y))
        # Compatibility 也支持 CPU 遮挡剔除；只有项目设置打开时才创建遮挡体，
        # 这样低端设备可以关闭它而不影响地图碰撞。
        if bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false)):
            var occluder := OccluderInstance3D.new()
            var box_occluder := BoxOccluder3D.new()
            box_occluder.size = Vector3(blocking_size.x, height, blocking_size.y)
            occluder.occluder = box_occluder
            occluder.position = Vector3(center.x, height * 0.5, center.y)
            _world_root.add_child(occluder)

func _add_boundary(center: Vector3, size: Vector3) -> void:
    var body := StaticBody3D.new()
    body.name = "IceCliffBlockingLayer"
    body.set_meta("blocking_layer", "ice_cliff")
    body.collision_layer = 2
    body.collision_mask = 1
    body.position = center
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    _world_root.add_child(body)

func _build_zone_visuals() -> void:
    var safehouse := MeshInstance3D.new()
    var safe_mesh := BoxMesh.new()
    safe_mesh.size = Vector3(8.0, 0.045, 7.0)
    safehouse.mesh = safe_mesh
    safehouse.position = Vector3(SAFEHOUSE.x, 0.035, SAFEHOUSE.y)
    # 平台本身是浅钢蓝的金属板：暖色只留给热核和灯光，
    # 否则半透明的暖色面会把周围雪地染成土黄。
    safehouse.material_override = _zone_material(Color(0.72, 0.80, 0.86, 0.55), Color("#9fb8c6"))
    _world_root.add_child(safehouse)
    var heat_core := MeshInstance3D.new()
    var core_mesh := SphereMesh.new()
    core_mesh.radius = 0.68
    core_mesh.height = 1.36
    heat_core.mesh = core_mesh
    heat_core.position = Vector3(SAFEHOUSE.x, 0.86, SAFEHOUSE.y)
    heat_core.material_override = _glow_material(Color("#ffbd61"), 1.6)
    _world_root.add_child(heat_core)
    var heat_light := OmniLight3D.new()
    heat_light.position = Vector3(SAFEHOUSE.x, 1.2, SAFEHOUSE.y)
    heat_light.light_color = Color("#ffb65e")
    heat_light.light_energy = 3.0
    heat_light.omni_range = 6.0
    _world_root.add_child(heat_light)
    # 地标只用轮廓区分：倒塌天线塔、冒蒸汽的裂口、斜插的运输舱、成排阵列。
    # 名称不再写在地面上，玩家走近或扫描后才显示。
    _build_landmark("旧气象站", Vector2(-130.0, -88.0), "tower", Color("#79d8ff"))
    _build_landmark("冰层裂谷", Vector2(132.0, -94.0), "rift", Color("#a78bfa"))
    _build_landmark("坠毁运输舱", Vector2(130.0, 74.0), "wreck", Color("#8ff1a0"))
    _build_landmark("废弃通信阵列", Vector2(-124.0, 52.0), "array", Color("#f2b86b"))
    _build_thermal_vents()

func _build_thermal_vents() -> void:
    # 地热口：暖色光柱加池面，是长距离移动中唯一的取暖点和方向参照。
    for vent in FrostMapLayout.THERMAL_VENTS:
        var point := Vector2(vent.get("position", Vector2.ZERO))
        var vent_root := Node3D.new()
        vent_root.name = "ThermalVent"
        vent_root.position = Vector3(point.x, 0.0, point.y)
        _world_root.add_child(vent_root)
        var pool := MeshInstance3D.new()
        var pool_mesh := CylinderMesh.new()
        pool_mesh.top_radius = 3.4
        pool_mesh.bottom_radius = 3.9
        pool_mesh.height = 0.06
        pool_mesh.radial_segments = 20
        pool.mesh = pool_mesh
        pool.position.y = terrain_height(point) + 0.04
        pool.material_override = _glow_material(Color("#ff9d4a"), 0.55)
        vent_root.add_child(pool)
        var glow := OmniLight3D.new()
        glow.light_color = Color("#ffa356")
        glow.light_energy = 3.4
        glow.omni_range = HEAT_RADIUS + 2.0
        glow.position.y = 1.6
        vent_root.add_child(glow)
        var rng := RandomNumberGenerator.new()
        rng.seed = int(point.x * 13.0 + point.y * 7.0)
        for index in 7:
            var steam := MeshInstance3D.new()
            var steam_mesh := SphereMesh.new()
            var radius := rng.randf_range(0.5, 1.3)
            steam_mesh.radius = radius
            steam_mesh.height = radius * 2.0
            steam.mesh = steam_mesh
            steam.position = Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(0.8, 3.4), rng.randf_range(-1.6, 1.6))
            var steam_material := StandardMaterial3D.new()
            steam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            steam_material.albedo_color = Color(1.0, 0.86, 0.72, 0.16)
            steam.material_override = steam_material
            vent_root.add_child(steam)
        var label := Label3D.new()
        label.name = "VentLabel"
        label.text = String(vent.get("name", "地热口"))
        label.visible = false
        label.position.y = 4.2
        label.font_size = 44
        label.pixel_size = 0.010
        label.modulate = Color("#ffc78a")
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.outline_size = 10
        label.outline_modulate = Color("#3d1e05")
        label.shaded = false
        vent_root.add_child(label)
        _world_labels.append(label)

func _build_landmark(display_name: String, position: Vector2, silhouette: String, color: Color) -> void:
    var landmark := Node3D.new()
    landmark.name = "Landmark_%s" % silhouette
    landmark.position = Vector3(position.x, 0.0, position.y)
    match silhouette:
        "tower":
            _landmark_tower(landmark, color)
        "rift":
            _landmark_rift(landmark, color)
        "wreck":
            _landmark_wreck(landmark, color)
        "array":
            _landmark_array(landmark, color)
    var label := Label3D.new()
    label.name = "LandmarkLabel"
    label.text = display_name
    label.visible = false
    label.position.y = 5.0
    label.modulate = color
    label.font_size = 44
    label.pixel_size = 0.010
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.outline_size = 10
    label.outline_modulate = Color("#061521")
    label.shaded = false
    landmark.add_child(label)
    _world_labels.append(label)
    _world_root.add_child(landmark)

func _landmark_tower(parent: Node3D, color: Color) -> void:
    # 倒塌的天线塔：倾斜的主柱加一段倒下的塔架。
    var mast := MeshInstance3D.new()
    var mast_mesh := CylinderMesh.new()
    mast_mesh.top_radius = 0.12
    mast_mesh.bottom_radius = 0.30
    mast_mesh.height = 6.4
    mast_mesh.radial_segments = 8
    mast.mesh = mast_mesh
    mast.position = Vector3(0.0, 2.6, 0.0)
    mast.rotation_degrees = Vector3(0.0, 0.0, 22.0)
    mast.material_override = _material(Color("#39566b"), 0.3)
    mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(mast)
    var fallen := MeshInstance3D.new()
    var fallen_mesh := CylinderMesh.new()
    fallen_mesh.top_radius = 0.10
    fallen_mesh.bottom_radius = 0.22
    fallen_mesh.height = 4.2
    fallen_mesh.radial_segments = 8
    fallen.mesh = fallen_mesh
    fallen.position = Vector3(2.4, 0.24, 1.1)
    fallen.rotation_degrees = Vector3(88.0, 24.0, 0.0)
    fallen.material_override = _material(Color("#2f4a5e"), 0.25)
    parent.add_child(fallen)
    var dish := MeshInstance3D.new()
    var dish_mesh := CylinderMesh.new()
    dish_mesh.top_radius = 0.86
    dish_mesh.bottom_radius = 0.86
    dish_mesh.height = 0.12
    dish_mesh.radial_segments = 16
    dish.mesh = dish_mesh
    dish.position = Vector3(-0.5, 5.4, 0.2)
    dish.rotation_degrees = Vector3(64.0, 0.0, 22.0)
    dish.material_override = _glow_material(color, 0.5)
    parent.add_child(dish)

func _landmark_rift(parent: Node3D, color: Color) -> void:
    # 冰层裂口：地缝加向上冒的蒸汽光。
    var crack := MeshInstance3D.new()
    var crack_mesh := BoxMesh.new()
    crack_mesh.size = Vector3(7.4, 0.16, 1.5)
    crack.mesh = crack_mesh
    crack.position = Vector3(0.0, 0.02, 0.0)
    crack.rotation_degrees.y = -18.0
    crack.material_override = _material(Color("#0a1420"), 0.1)
    parent.add_child(crack)
    for index in 5:
        var vent := MeshInstance3D.new()
        var vent_mesh := CylinderMesh.new()
        vent_mesh.top_radius = 0.06
        vent_mesh.bottom_radius = 0.34
        vent_mesh.height = 2.2 + float(index % 3) * 0.6
        vent_mesh.radial_segments = 8
        vent.mesh = vent_mesh
        vent.position = Vector3(-2.8 + float(index) * 1.5, 1.1, 0.0)
        vent.material_override = _glow_material(color, 0.75)
        parent.add_child(vent)
    var glow := OmniLight3D.new()
    glow.light_color = color
    glow.light_energy = 3.0
    glow.omni_range = 6.0
    glow.position.y = 1.2
    parent.add_child(glow)

func _landmark_wreck(parent: Node3D, color: Color) -> void:
    # 斜插的运输舱：半埋进冰面的舱体，可进入。
    var hull := MeshInstance3D.new()
    var hull_mesh := BoxMesh.new()
    hull_mesh.size = Vector3(5.2, 2.4, 2.6)
    hull.mesh = hull_mesh
    hull.position = Vector3(0.0, 1.0, 0.0)
    hull.rotation_degrees = Vector3(0.0, 0.0, -26.0)
    hull.material_override = _material(Color("#4d6068"), 0.35)
    hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(hull)
    var hatch := MeshInstance3D.new()
    var hatch_mesh := BoxMesh.new()
    hatch_mesh.size = Vector3(1.1, 1.5, 1.6)
    hatch.mesh = hatch_mesh
    hatch.position = Vector3(2.4, 1.1, 0.0)
    hatch.rotation_degrees = Vector3(0.0, 0.0, -12.0)
    hatch.material_override = _glow_material(color, 0.6)
    parent.add_child(hatch)
    var fin := MeshInstance3D.new()
    var fin_mesh := BoxMesh.new()
    fin_mesh.size = Vector3(0.3, 1.8, 1.4)
    fin.mesh = fin_mesh
    fin.position = Vector3(-2.6, 2.0, 0.0)
    fin.rotation_degrees = Vector3(0.0, 0.0, -30.0)
    fin.material_override = _material(Color("#3c4d55"), 0.3)
    parent.add_child(fin)

func _landmark_array(parent: Node3D, color: Color) -> void:
    # 成排的通信阵列：四根高低不一的桅杆，顶端有信号点。
    var heights := [3.2, 4.4, 2.8, 3.8]
    for index in heights.size():
        var mast := MeshInstance3D.new()
        var mast_mesh := CylinderMesh.new()
        mast_mesh.top_radius = 0.07
        mast_mesh.bottom_radius = 0.16
        mast_mesh.height = float(heights[index])
        mast_mesh.radial_segments = 6
        mast.mesh = mast_mesh
        mast.position = Vector3(-2.4 + float(index) * 1.6, float(heights[index]) * 0.5, 0.0)
        mast.material_override = _material(Color("#4a5a62"), 0.3)
        mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        parent.add_child(mast)
        var tip := MeshInstance3D.new()
        var tip_mesh := SphereMesh.new()
        tip_mesh.radius = 0.16
        tip_mesh.height = 0.32
        tip.mesh = tip_mesh
        tip.position = Vector3(-2.4 + float(index) * 1.6, float(heights[index]) + 0.1, 0.0)
        tip.material_override = _glow_material(color, 0.8)
        parent.add_child(tip)
    var base := MeshInstance3D.new()
    var base_mesh := BoxMesh.new()
    base_mesh.size = Vector3(6.4, 0.2, 2.0)
    base.mesh = base_mesh
    base.position.y = 0.1
    base.material_override = _material(Color("#2d3d45"), 0.2)
    parent.add_child(base)

func _zone_material(color: Color, emission_color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = emission_color
    material.emission_energy_multiplier = 0.45
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    return material

func _glow_material(color: Color, energy := 0.65) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = energy
    material.roughness = 0.28
    material.metallic = 0.15
    return material

func _build_beacons() -> void:
    for index in beacon_positions.size():
        var beacon := Node3D.new()
        beacon.name = "WeatherBeacon3D_%d" % (index + 1)
        beacon.position = Vector3(beacon_positions[index].x, 0.0, beacon_positions[index].y)
        _world_root.add_child(beacon)
        var base_platform := MeshInstance3D.new()
        var platform_mesh := CylinderMesh.new()
        platform_mesh.top_radius = 0.85
        platform_mesh.bottom_radius = 0.92
        platform_mesh.height = 0.15
        platform_mesh.radial_segments = 12
        base_platform.mesh = platform_mesh
        base_platform.position.y = 0.08
        base_platform.material_override = _material(Color("#2d5a6e"), 0.45)
        base_platform.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        beacon.add_child(base_platform)
        var mesh_node := MeshInstance3D.new()
        var cylinder := CylinderMesh.new()
        cylinder.top_radius = 0.32
        cylinder.bottom_radius = 0.5
        cylinder.height = 1.7
        mesh_node.mesh = cylinder
        mesh_node.position.y = 0.85
        mesh_node.material_override = _material(Color("#f0b94e"), 0.35)
        mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        beacon.add_child(mesh_node)
        var antenna := MeshInstance3D.new()
        var antenna_mesh := CylinderMesh.new()
        antenna_mesh.top_radius = 0.055
        antenna_mesh.bottom_radius = 0.09
        antenna_mesh.height = 0.9
        antenna.position.y = 2.0
        antenna.mesh = antenna_mesh
        antenna.material_override = _glow_material(Color("#ffe38c"), 1.5)
        antenna.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        beacon.add_child(antenna)
        var beacon_ring := MeshInstance3D.new()
        var beacon_ring_mesh := TorusMesh.new()
        beacon_ring_mesh.inner_radius = 0.72
        beacon_ring_mesh.outer_radius = 0.80
        beacon_ring_mesh.rings = 24
        beacon_ring_mesh.ring_segments = 8
        beacon_ring.position.y = 0.22
        beacon_ring.mesh = beacon_ring_mesh
        beacon_ring.material_override = _glow_material(Color("#ffd36b"), 1.1)
        beacon.add_child(beacon_ring)
        var light := OmniLight3D.new()
        light.light_color = Color("#ffc86b")
        light.light_energy = 3.2
        light.omni_range = 5.5
        light.position.y = 1.8
        beacon.add_child(light)
        var label := Label3D.new()
        label.text = "【气象信标 %d】\nE键修复" % (index + 1)
        label.name = "ObjectLabel"
        label.visible = false
        label.position.y = 3.2
        label.modulate = Color("#ffea91")
        label.font_size = 52
        label.pixel_size = 0.010
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.outline_size = 12
        label.outline_modulate = Color("#1a2e3d")
        label.shaded = false
        beacon.add_child(label)
        beacons[index + 1] = beacon
        _object_tags.append({"node": beacon, "kind": "beacon", "id": index + 1, "label": "E  修复通讯塔"})

func _build_crates() -> void:
    for index in crate_positions.size():
        var crate := Node3D.new()
        crate.name = "HeatBattery3D_%d" % (index + 1)
        crate.position = Vector3(crate_positions[index].x, 0.3, crate_positions[index].y)
        _world_root.add_child(crate)
        var base := MeshInstance3D.new()
        var base_mesh := CylinderMesh.new()
        base_mesh.top_radius = 0.45
        base_mesh.bottom_radius = 0.48
        base_mesh.height = 0.12
        base_mesh.radial_segments = 16
        base.mesh = base_mesh
        base.position.y = -0.24
        base.material_override = _material(Color("#3d7a68"), 0.5)
        base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        crate.add_child(base)
        var mesh_node := MeshInstance3D.new()
        var box := CylinderMesh.new()
        box.top_radius = 0.38
        box.bottom_radius = 0.38
        box.height = 0.72
        box.radial_segments = 16
        mesh_node.mesh = box
        mesh_node.material_override = _material(Color("#5ce8be"), 0.4)
        mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        crate.add_child(mesh_node)
        var battery_core := MeshInstance3D.new()
        var core_mesh := CylinderMesh.new()
        core_mesh.top_radius = 0.14
        core_mesh.bottom_radius = 0.14
        core_mesh.height = 0.82
        battery_core.mesh = core_mesh
        battery_core.position.y = 0.48
        battery_core.material_override = _glow_material(Color("#b0fff0"), 1.8)
        crate.add_child(battery_core)
        var battery_handle := MeshInstance3D.new()
        var handle_mesh := TorusMesh.new()
        handle_mesh.inner_radius = 0.18
        handle_mesh.outer_radius = 0.23
        handle_mesh.rings = 20
        handle_mesh.ring_segments = 8
        battery_handle.mesh = handle_mesh
        battery_handle.position.y = 0.90
        battery_handle.rotation_degrees.x = 90.0
        battery_handle.material_override = _glow_material(Color("#76f4dd"), 1.2)
        crate.add_child(battery_handle)
        var glow_light := OmniLight3D.new()
        glow_light.name = "BatteryGlow"
        glow_light.light_color = Color("#7effd8")
        glow_light.light_energy = 2.5
        glow_light.omni_range = 4.0
        glow_light.position.y = 0.5
        crate.add_child(glow_light)
        var label := Label3D.new()
        label.text = "【热能电池】\nF键拾取"
        label.name = "ObjectLabel"
        label.visible = false
        label.position.y = 1.65
        label.modulate = Color("#8bffd5")
        label.font_size = 52
        label.pixel_size = 0.010
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.outline_size = 12
        label.outline_modulate = Color("#0a3d32")
        label.shaded = false
        crate.add_child(label)
        crates[index + 1] = crate
        _object_tags.append({"node": crate, "kind": "crate", "id": index + 1, "label": "F  拾取热能电池"})

func _build_samples() -> void:
    for index in sample_positions.size():
        var sample := Node3D.new()
        sample.name = "IceSample3D_%d" % (index + 1)
        sample.position = Vector3(sample_positions[index].x, 0.16, sample_positions[index].y)
        _world_root.add_child(sample)
        var shard := MeshInstance3D.new()
        var shard_mesh := PrismMesh.new()
        shard_mesh.size = Vector3(0.65, 0.9, 0.65)
        shard.mesh = shard_mesh
        shard.rotation_degrees = Vector3(0.0, float(index * 31), 15.0)
        shard.position.y = 0.55
        shard.material_override = _glow_material(Color("#b8a1ff"), 1.6)
        shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        sample.add_child(shard)
        var ring := MeshInstance3D.new()
        var ring_mesh := TorusMesh.new()
        ring_mesh.inner_radius = 0.46
        ring_mesh.outer_radius = 0.54
        ring_mesh.rings = 18
        ring_mesh.ring_segments = 8
        ring.mesh = ring_mesh
        ring.position.y = 0.22
        ring.material_override = _glow_material(Color("#8ed8ff"), 1.0)
        sample.add_child(ring)
        var label := Label3D.new()
        label.text = "【异常冰样 · 可选回收】\nF拾取 / X丢下"
        label.name = "ObjectLabel"
        label.visible = false
        label.position.y = 1.55
        label.modulate = Color("#c8b6ff")
        label.font_size = 52
        label.pixel_size = 0.010
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.outline_size = 12
        label.outline_modulate = Color("#17102c")
        label.shaded = false
        sample.add_child(label)
        samples[index + 1] = sample
        _object_tags.append({"node": sample, "kind": "sample", "id": index + 1, "label": "F  拾取异常冰样"})

func _build_extraction() -> void:
    var pad := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 2.2
    cylinder.bottom_radius = 2.2
    cylinder.height = 0.20
    cylinder.radial_segments = 12
    pad.mesh = cylinder
    pad.position = Vector3(EXTRACTION.x, 0.10, EXTRACTION.y)
    pad.material_override = _material(Color("#2d6a7a"), 0.45)
    pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    _world_root.add_child(pad)
    var ring := MeshInstance3D.new()
    var ring_mesh := TorusMesh.new()
    ring_mesh.inner_radius = 2.50
    ring_mesh.outer_radius = 2.62
    ring.mesh = ring_mesh
    ring.position = Vector3(EXTRACTION.x, 0.21, EXTRACTION.y)
    ring.material_override = _glow_material(Color("#68deff"), 1.2)
    _world_root.add_child(ring)
    for side in [-1.0, 1.0]:
        var pylon := MeshInstance3D.new()
        var pylon_mesh := BoxMesh.new()
        pylon_mesh.size = Vector3(0.28, 1.5, 0.28)
        pylon.mesh = pylon_mesh
        pylon.position = Vector3(EXTRACTION.x + side * 2.0, 0.9, EXTRACTION.y - 1.6)
        pylon.material_override = _glow_material(Color("#68deff"), 0.9)
        pylon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        _world_root.add_child(pylon)
    var extraction_light := OmniLight3D.new()
    extraction_light.name = "ExtractionGlow"
    extraction_light.light_color = Color("#68deff")
    extraction_light.light_energy = 4.2
    extraction_light.omni_range = 8.0
    extraction_light.position = Vector3(EXTRACTION.x, 1.5, EXTRACTION.y)
    _world_root.add_child(extraction_light)
    var landing_mark := Label3D.new()
    landing_mark.text = "H"
    landing_mark.font_size = 130
    landing_mark.pixel_size = 0.013
    landing_mark.rotation_degrees.x = -90.0
    landing_mark.position = Vector3(EXTRACTION.x, 0.22, EXTRACTION.y)
    landing_mark.modulate = Color("#a9f3ff")
    landing_mark.outline_size = 16
    landing_mark.outline_modulate = Color("#0a2935")
    _world_root.add_child(landing_mark)
    var label := Label3D.new()
    label.text = "【投送/撤离点】\nG键投送电池"
    label.position = Vector3(EXTRACTION.x, 2.5, EXTRACTION.y)
    label.modulate = Color("#a9f3ff")
    label.font_size = 58
    label.pixel_size = 0.009
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.outline_size = 14
    label.outline_modulate = Color("#0a2935")
    label.shaded = false
    _world_root.add_child(label)
    _world_labels.append(label)
    _object_tags.append({"node": pad, "kind": "extraction", "id": 0, "label": "G  投送电池 / 集合撤离"})

func _style_world_label(label: Label3D) -> void:
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.font_size = 40
    label.pixel_size = 0.012
    label.outline_size = 8
    label.outline_modulate = Color("#04101b")
    label.shaded = false

func _build_scan_visual() -> void:
    scan_visual = MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 1.0
    cylinder.bottom_radius = 1.0
    cylinder.height = 0.035
    cylinder.radial_segments = 64
    scan_visual.mesh = cylinder
    var material := StandardMaterial3D.new()
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_color = Color(0.15, 0.85, 0.95, 0.22)
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    scan_visual.material_override = material
    scan_visual.visible = false
    _world_root.add_child(scan_visual)
    scan_device = Node3D.new()
    scan_device.name = "GroundScanner"
    scan_device.visible = false
    var base := MeshInstance3D.new()
    var base_mesh := CylinderMesh.new()
    base_mesh.top_radius = 0.28
    base_mesh.bottom_radius = 0.38
    base_mesh.height = 0.28
    base.mesh = base_mesh
    base.position.y = 0.18
    base.material_override = _glow_material(Color("#5ac8ff"), 1.4)
    scan_device.add_child(base)
    var mast := MeshInstance3D.new()
    var mast_mesh := CylinderMesh.new()
    mast_mesh.top_radius = 0.045
    mast_mesh.bottom_radius = 0.075
    mast_mesh.height = 1.15
    mast.mesh = mast_mesh
    mast.position.y = 0.82
    mast.material_override = _glow_material(Color("#b8f4ff"), 1.2)
    scan_device.add_child(mast)
    var beacon := OmniLight3D.new()
    beacon.light_color = Color("#5ac8ff")
    beacon.light_energy = 2.2
    beacon.omni_range = 4.0
    beacon.position.y = 1.35
    scan_device.add_child(beacon)
    var label := Label3D.new()
    label.name = "ScannerLabel"
    label.text = "扫描器\n扫描中"
    label.position.y = 1.9
    label.modulate = Color("#a9efff")
    label.font_size = 42
    label.pixel_size = 0.009
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.outline_size = 10
    label.outline_modulate = Color("#061521")
    label.shaded = false
    scan_device.add_child(label)
    _world_root.add_child(scan_device)

func _build_exploration_clues() -> void:
    for node in clue_nodes.values():
        if is_instance_valid(node):
            node.queue_free()
    clue_nodes.clear()
    if not is_instance_valid(_world_root):
        return
    for clue in exploration_clues:
        var marker := Node3D.new()
        marker.name = "ExplorationClue_%d" % int(clue.get("id", 0))
        marker.visible = false
        var position := Vector2(clue.get("position", Vector2.ZERO))
        marker.position = Vector3(position.x, 0.045, position.y)
        var trace := MeshInstance3D.new()
        var trace_mesh := CylinderMesh.new()
        trace_mesh.top_radius = 0.12
        trace_mesh.bottom_radius = 0.18
        trace_mesh.height = 0.025
        trace_mesh.radial_segments = 8
        trace.mesh = trace_mesh
        var clue_kind := String(clue.get("kind", ""))
        var clue_color := Color("#75dff5")
        if clue_kind == "landmark":
            clue_color = Color("#f2b86b")
        elif clue_kind == "sample":
            clue_color = Color("#b8a1ff")
        trace.material_override = _glow_material(clue_color, 0.55)
        marker.add_child(trace)
        var pulse := MeshInstance3D.new()
        var pulse_mesh := TorusMesh.new()
        pulse_mesh.inner_radius = 0.28
        pulse_mesh.outer_radius = 0.33
        pulse_mesh.rings = 16
        pulse_mesh.ring_segments = 8
        pulse.mesh = pulse_mesh
        pulse.position.y = 0.03
        pulse.material_override = _glow_material(clue_color, 0.85)
        marker.add_child(pulse)
        var label := Label3D.new()
        label.text = "信号残响" if clue_kind == "landmark" else ("热融痕迹" if clue_kind == "crate" else ("异常样本回波" if clue_kind == "sample" else "拖行痕迹"))
        label.position.y = 0.75
        label.modulate = clue_color
        label.font_size = 34
        label.pixel_size = 0.009
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.outline_size = 8
        label.outline_modulate = Color("#061521")
        label.shaded = false
        marker.add_child(label)
        _world_root.add_child(marker)
        clue_nodes[int(clue.get("id", 0))] = marker
        # 痕迹必须先被扫描捕捉；重建布局时保留本客户端已经捕捉到的状态。
        if scan_revealed_clues.has(int(clue.get("id", 0))):
            marker.visible = true

func _spawn_position(peer_id: int) -> Vector3:
    var slots := [Vector3(SAFEHOUSE.x - 2.2, 0.0, SAFEHOUSE.y + 1.8), Vector3(SAFEHOUSE.x, 0.0, SAFEHOUSE.y + 1.8), Vector3(SAFEHOUSE.x + 2.2, 0.0, SAFEHOUSE.y + 1.8), Vector3(SAFEHOUSE.x + 4.4, 0.0, SAFEHOUSE.y + 1.8)]
    return slots[(peer_id - 1) % slots.size()]

func _enemy_spawn_center_away_from_players(preferred: Vector2) -> Vector2:
    if players.is_empty():
        return preferred
    var best_point := preferred
    var best_clearance := -INF
    var map_half := MAP_SIZE * 0.5 - Vector2(12.0, 12.0)
    for radius in [16.0, 22.0, 28.0]:
        for index in 16:
            var angle := TAU * float(index) / 16.0
            var candidate: Vector2 = preferred + Vector2(cos(angle), sin(angle)) * radius
            candidate.x = clampf(candidate.x, -map_half.x, map_half.x)
            candidate.y = clampf(candidate.y, -map_half.y, map_half.y)
            var clearance := INF
            for player_value in players.values():
                var player := player_value as SpacePlayer3D
                if player == null or player.downed:
                    continue
                clearance = minf(clearance, candidate.distance_to(Vector2(player.global_position.x, player.global_position.z)))
            if clearance > best_clearance:
                best_clearance = clearance
                best_point = candidate
    return best_point

@rpc("authority", "call_local", "reliable")
func spawn_player_for_peer(peer_id: int) -> void:
    if not connected_ids.has(peer_id):
        connected_ids.append(peer_id)
    if players.has(peer_id):
        return
    var player := PLAYER_SCENE.instantiate() as SpacePlayer3D
    player.setup(peer_id, PLAYER_COLORS[(peer_id - 1) % PLAYER_COLORS.size()])
    player.position = _ship_session.spawn_position(peer_id) if ship_active else _spawn_position(peer_id)
    add_child(player)
    players[peer_id] = player

func _spawn_enemy_wave(initial := false) -> void:
    if not is_host or _objectives_ready():
        return
    if not initial:
        enemy_wave_index += 1
    else:
        enemy_wave_index = 1
    enemy_spawned = true
    enemy_spawn_center = _enemy_spawn_center_away_from_players(enemy_spawn_center)
    # 第一波就要让“修复信标”产生实际代价；后续波次再叠一只，避免清场变成无风险流程。
    var count := (2 + connected_ids.size()) if initial else (3 + connected_ids.size())
    for index in count:
        var enemy := ENEMY_SCENE.instantiate() as SpaceEnemy3D
        enemy.setup(next_enemy_id, connected_ids.size())
        var angle := TAU * float(index) / float(count)
        enemy.position = Vector3(enemy_spawn_center.x + cos(angle) * 4.5, 0.0, enemy_spawn_center.y + sin(angle) * 4.5)
        add_child(enemy)
        enemies[next_enemy_id] = enemy
        next_enemy_id += 1
    _set_status("第 %d 波敌人已在远处出现，正在高速接近；后续威胁将由信标和暴风雪触发。" % enemy_wave_index)
    if initial and not story_flags.has("first_contact"):
        story_flags["first_contact"] = true
        show_story_rpc.rpc("冰层下传来回声。它们不是被你们发现的，是被热量叫醒的。", 7.0)
    _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot(), journal_entries, discovered_regions)

func _check_enemy_triggers() -> void:
    if _objectives_ready():
        return
    var sample_carried := false
    for player_value in players.values():
        var player := player_value as SpacePlayer3D
        if player != null and player.carrying == 2:
            sample_carried = true
            enemy_spawn_center = Vector2(player.global_position.x, player.global_position.z)
            break
    if not enemy_spawned and sample_carried:
        enemy_trigger_flags["sample_contact"] = true
        _spawn_enemy_wave(true)
        return
    if not enemy_spawned and activated_beacons.size() >= 1:
        enemy_trigger_flags["first_contact"] = true
        enemy_spawn_center = Vector2(beacon_positions[0])
        _spawn_enemy_wave(true)
        return
    if enemy_spawned and enemies.is_empty() and activated_beacons.size() >= 2 and not enemy_trigger_flags.has("second_beacon"):
        enemy_trigger_flags["second_beacon"] = true
        enemy_spawn_center = Vector2(beacon_positions[1])
        if knowledge_flags.has("relay"):
            enemy_spawn_center = Vector2(150.0, 46.0)
        show_story_rpc.rpc("第二座信标亮起时，冰层深处的回声变得清晰了。它们正在沿着热源靠近。", 6.0)
        _spawn_enemy_wave()
        return
    if enemy_spawned and enemies.is_empty() and storm_active and not enemy_trigger_flags.has("storm_front"):
        enemy_trigger_flags["storm_front"] = true
        enemy_spawn_center = Vector2(12.0, 0.0)
        if knowledge_flags.has("relay"):
            enemy_spawn_center = Vector2(120.0, -116.0)
        show_story_rpc.rpc("暴风雪遮住了天空，地下的热量却变得异常集中。有什么东西正在追踪它。", 6.0)
        _spawn_enemy_wave()

func _tick_storm(delta: float) -> void:
    if anomaly_resolved:
        return
    storm_elapsed += delta
    if storm_active:
        storm_remaining = maxf(storm_remaining - delta, 0.0)
        if storm_remaining <= 0.0:
            storm_active = false
            storm_elapsed = 0.0
            sync_storm_state.rpc(false, 0.0)
            _set_status("暴风雪减弱，能见度、移动速度和体温消耗恢复正常。")
        return
    if storm_elapsed >= STORM_INTERVAL:
        storm_active = true
        storm_remaining = STORM_DURATION
        sync_storm_state.rpc(true, storm_remaining)
        _set_status("暴风雪来袭：视野收窄、移动变慢，体温与氧气消耗加剧。")

func _tick_story(delta: float) -> void:
    story_elapsed += delta
    if story_elapsed >= 3.0 and not story_flags.has("arrival_log"):
        story_flags["arrival_log"] = true
        show_story_rpc.rpc("飞船日志：霜烬星的三座气象信标在十七小时前同时失联。没有撤离舱，只有一条反复指向冰层下方的回波。", 7.0)
    elif story_elapsed >= 10.0 and not story_flags.has("broken_voice"):
        story_flags["broken_voice"] = true
        show_story_rpc.rpc("无线电里传来一段断续的声音：‘如果你们还在天上……别相信亮着的灯。先读懂它们为何亮起。’", 7.0)

func _show_story(text: String, duration: float = 6.0) -> void:
    if _story_label == null:
        return
    _thought_timer = 0.0
    _thought_label.visible = false
    _story_label.text = text
    _story_label.visible = true
    _subtitle_panel.visible = true
    _story_timer = duration
    _record_journal("飞船记录", text)

func _update_story(delta: float) -> void:
    if _story_label == null or _story_timer <= 0.0:
        return
    _story_timer -= delta
    if _story_timer <= 0.0:
        _story_label.visible = false
        if not _thought_label.visible:
            _subtitle_panel.visible = false

@rpc("authority", "call_local", "reliable")
func show_story_rpc(text: String, duration: float = 6.0) -> void:
    _show_story(text, duration)

func _update_storm_visual(_delta: float) -> void:
    if _storm_overlay == null:
        return
    _storm_overlay.visible = storm_active
    if storm_active:
        var intensity := clampf(storm_remaining / SIGNAL_STORM_DURATION, 0.0, 1.0)
        # 风暴开始和结束时渐入渐出，边缘变暗，玩家会真的失去远处信息。
        _storm_overlay.color = Color(0.02, 0.12, 0.20, lerpf(0.18, 0.38, intensity))

func _update_vision_overlay() -> void:
    if _vision_overlay == null:
        return
    _vision_overlay.visible = storm_active
    var material := _vision_overlay.material as ShaderMaterial
    if material == null:
        return
    # 摄像机跟随玩家，中心保留一小块可见区域；扫描时仍由扫描环提供额外信息。
    material.set_shader_parameter("viewer", Vector2(0.5, 0.54))
    material.set_shader_parameter("view_radius", 0.205 if storm_active else 0.32)
    material.set_shader_parameter("scan_active", 0.0)

@rpc("authority", "call_local", "reliable")
func sync_storm_state(active: bool, remaining: float) -> void:
    storm_active = active
    storm_remaining = remaining
    if not active:
        storm_elapsed = 0.0

func start_scan_for_peer(peer_id: int) -> void:
    if not is_host:
        request_scan.rpc_id(1, peer_id)
        return
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed or player.scan_cooldown_remaining > 0.0:
        if player != null and player.scan_cooldown_remaining > 0.0:
            show_feedback_rpc.rpc("扫描冷却 %.1fs" % player.scan_cooldown_remaining, Color("#ffaa66"), 0.8)
        return
    if scan_device_active:
        show_feedback_rpc.rpc("场上已有扫描器，请靠近它按 F 回收后再部署。", Color("#ffbd75"), 1.8)
        return
    scan_peer_id = peer_id
    scan_origin = player.global_position
    scan_device_position = scan_origin
    scan_device_active = true
    scan_remaining = SCAN_DURATION
    scan_cooldown = SCAN_COOLDOWN
    sync_scan_device_state.rpc(true, scan_device_position, scan_remaining)
    sync_scan_state.rpc(peer_id, scan_origin, SCAN_DURATION, SCAN_COOLDOWN, SCAN_STARTUP)
    var scan_hint := _scan_hint_for_player(player)
    var scan_message := "扫描器已部署 · 范围 %.0fm" % SCAN_DEVICE_RADIUS
    if not scan_hint.is_empty():
        scan_message += " · " + scan_hint
    show_feedback_rpc.rpc(scan_message, Color("#5ac8ff"), 1.6)

@rpc("any_peer", "reliable")
func request_scan(peer_id: int) -> void:
    if is_host:
        start_scan_for_peer(peer_id)

@rpc("authority", "call_local", "reliable")
func sync_scan_state(peer_id: int, origin: Vector3, duration: float, cooldown: float, startup: float = SCAN_STARTUP) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player != null:
        player.begin_scan(startup, cooldown, origin)
    scan_peer_id = peer_id
    scan_origin = origin
    scan_remaining = duration
    scan_cooldown = cooldown

@rpc("authority", "call_local", "reliable")
func sync_scan_device_state(active: bool, origin: Vector3, remaining: float = 0.0) -> void:
    scan_device_active = active
    scan_device_position = origin
    scan_origin = origin
    scan_remaining = remaining
    if scan_device != null:
        scan_device.global_position = origin
        scan_device.visible = active
        var label := scan_device.get_node_or_null("ScannerLabel") as Label3D
        if label != null:
            label.text = "扫描器\n扫描中" if remaining > 0.0 else "扫描器\nF 回收"

func _scan_hint_for_player(player: SpacePlayer3D) -> String:
    var nearest: Dictionary = {}
    var nearest_distance := INF
    var nearest_any: Dictionary = {}
    var nearest_any_distance := INF
    var scan_radius := STORM_SCAN_DEVICE_RADIUS if storm_active else SCAN_DEVICE_RADIUS
    for clue in exploration_clues:
        var kind := String(clue.get("kind", ""))
        var clue_id := int(clue.get("id", 0))
        if discovered_clues.has(clue_id) or scan_revealed_clues.has(clue_id):
            continue
        var target_id := int(clue.get("target_id", 0))
        if kind == "beacon" and activated_beacons.has(target_id):
            continue
        if kind == "crate" and taken_crates.has(target_id):
            continue
        if kind == "sample" and taken_samples.has(target_id):
            continue
        var clue_position := Vector2(clue.get("position", Vector2.ZERO))
        var raw_distance := _flat_distance(player.global_position, Vector3(clue_position.x, 0.0, clue_position.y))
        if raw_distance < nearest_any_distance:
            nearest_any = clue
            nearest_any_distance = raw_distance
        var distance := raw_distance
        if (knowledge_flags.has("weather_station") or knowledge_flags.has("transport")) and kind == "sample":
            distance -= 12.0
        if distance < nearest_distance and raw_distance <= scan_radius:
            nearest = clue
            nearest_distance = distance
    if nearest.is_empty():
        if nearest_any.is_empty():
            return "暂时没有未发现的回波"
        var any_position := Vector2(nearest_any.get("position", Vector2.ZERO))
        var any_kind := String(nearest_any.get("kind", ""))
        var any_name := "地标" if any_kind == "landmark" else ("气象信标" if any_kind == "beacon" else ("热能电池" if any_kind == "crate" else "异常冰样"))
        var from := Vector2(player.global_position.x, player.global_position.z)
        return "附近没有回波；最近的%s在%s %.0fm，移动后再部署" % [any_name, _direction_hint(from, any_position), nearest_any_distance]
    var target_id := int(nearest.get("target_id", 0))
    var target_position := Vector2.ZERO
    var clue_kind := String(nearest.get("kind", ""))
    if clue_kind == "beacon":
        target_position = Vector2(beacon_positions[target_id - 1])
    elif clue_kind == "crate":
        target_position = Vector2(crate_positions[target_id - 1])
    elif clue_kind == "sample":
        target_position = Vector2(sample_positions[target_id - 1])
    else:
        target_position = Vector2(nearest.get("position", Vector2.ZERO))
        return "扫描捕捉到%s的地标回声：%s" % [_direction_hint(Vector2(player.global_position.x, player.global_position.z), target_position), String(nearest.get("name", "未知"))]
    var signal_name := "拖行回波" if clue_kind == "beacon" else ("热融回波" if clue_kind == "crate" else ("异常样本回波" if clue_kind == "sample" else "地标回声"))
    return "扫描捕捉到%s的%s" % [_direction_hint(Vector2(player.global_position.x, player.global_position.z), target_position), signal_name]

func _update_scan_visual(delta: float) -> void:
    scan_remaining = maxf(scan_remaining - delta, 0.0)
    scan_cooldown = maxf(scan_cooldown - delta, 0.0)
    if scan_visual == null:
        return
    if scan_remaining <= 0.0:
        scan_visual.visible = false
        if scan_device != null and scan_device_active:
            scan_device.visible = true
            var label := scan_device.get_node_or_null("ScannerLabel") as Label3D
            if label != null:
                label.text = "扫描器\nF 回收"
        return
    scan_visual.visible = true
    scan_visual.global_position = Vector3(scan_device_position.x, 0.09, scan_device_position.z)
    var progress := clampf(1.0 - scan_remaining / SCAN_DURATION, 0.0, 1.0)
    var max_radius := STORM_SCAN_DEVICE_RADIUS if storm_active else SCAN_DEVICE_RADIUS
    var radius := lerpf(0.4, max_radius, progress)
    scan_visual.scale = Vector3(radius, 1.0, radius)
    if scan_device != null:
        scan_device.global_position = scan_device_position
        scan_device.visible = scan_device_active
    _reveal_clues_in_scan(radius)

func _reveal_clues_in_scan(radius: float) -> void:
    if not scan_device_active:
        return
    for clue in exploration_clues:
        var clue_id := int(clue.get("id", 0))
        if scan_revealed_clues.has(clue_id) or discovered_clues.has(clue_id):
            continue
        var kind := String(clue.get("kind", ""))
        var target_id := int(clue.get("target_id", 0))
        if kind == "beacon" and activated_beacons.has(target_id):
            continue
        if kind == "crate" and taken_crates.has(target_id):
            continue
        if kind == "sample" and taken_samples.has(target_id):
            continue
        var clue_position := Vector2(clue.get("position", Vector2.ZERO))
        var distance := _flat_distance(scan_device_position, Vector3(clue_position.x, 0.0, clue_position.y))
        if distance > radius or distance > CLUE_SCAN_RADIUS:
            continue
        scan_revealed_clues.append(clue_id)
        var marker := clue_nodes.get(clue_id) as Node3D
        if marker != null:
            marker.visible = true
            _show_feedback("扫描锁定：地面出现可调查痕迹", Color("#75dff5"), 1.0)

func _retrieve_scan_device(peer_id: int) -> bool:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or not scan_device_active:
        return false
    var distance := _flat_distance(player.global_position, scan_device_position)
    if distance > RESOURCE_INTERACTION_RADIUS:
        return false
    scan_device_active = false
    scan_remaining = 0.0
    scan_cooldown = 0.0
    if scan_device != null:
        scan_device.visible = false
    if scan_visual != null:
        scan_visual.visible = false
    sync_scan_device_state.rpc(false, scan_device_position, 0.0)
    show_feedback_rpc.rpc("扫描器已回收，可以继续部署。", Color("#8be7ff"), 1.2)
    return true

func _landmark_position(landmark_id: String) -> Vector2:
    for landmark in LANDMARK_DATA:
        if String(landmark.get("id", "")) == landmark_id:
            return Vector2(landmark.get("position", Vector2.ZERO))
    return Vector2.ZERO

func _near_landmark(player: SpacePlayer3D, landmark_id: String, radius := LANDMARK_INTERACTION_RADIUS) -> bool:
    if player == null:
        return false
    var point := _landmark_position(landmark_id)
    return _flat_distance(player.global_position, Vector3(point.x, 0.0, point.y)) <= radius

func _reveal_landmark_signal(landmark_id: String) -> void:
    for clue in exploration_clues:
        if String(clue.get("kind", "")) != "landmark" or String(clue.get("landmark_id", "")) != landmark_id:
            continue
        var clue_id := int(clue.get("id", 0))
        if not scan_revealed_clues.has(clue_id) and not discovered_clues.has(clue_id):
            scan_revealed_clues.append(clue_id)
        var marker := clue_nodes.get(clue_id) as Node3D
        if marker != null:
            marker.visible = true
        return

func _reveal_next_beacon_signal() -> void:
    for index in beacon_positions.size():
        var target_id := index + 1
        if activated_beacons.has(target_id):
            continue
        for clue in exploration_clues:
            if String(clue.get("kind", "")) != "beacon" or int(clue.get("target_id", 0)) != target_id:
                continue
            var clue_id := int(clue.get("id", 0))
            if not scan_revealed_clues.has(clue_id) and not discovered_clues.has(clue_id):
                scan_revealed_clues.append(clue_id)
            var marker := clue_nodes.get(clue_id) as Node3D
            if marker != null:
                marker.visible = true
            return

func _reveal_signal_echoes(source: Vector3, max_count: int = 2) -> int:
    # 高频是“探测换风险”：只揭示信号源周边最值得追的几条回波，不直接把整张地图摊开。
    var candidates: Array = []
    for clue in exploration_clues:
        var clue_id := int(clue.get("id", 0))
        if scan_revealed_clues.has(clue_id) or discovered_clues.has(clue_id):
            continue
        var kind := String(clue.get("kind", ""))
        var target_id := int(clue.get("target_id", 0))
        if kind == "beacon" and activated_beacons.has(target_id):
            continue
        if kind == "crate" and taken_crates.has(target_id):
            continue
        if kind == "sample" and taken_samples.has(target_id):
            continue
        var point := Vector2(clue.get("position", Vector2.ZERO))
        var distance := _flat_distance(source, Vector3(point.x, 0.0, point.y))
        if distance <= CLUE_SCAN_RADIUS * 2.5:
            candidates.append({"clue": clue, "distance": distance})
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a.get("distance", INF)) < float(b.get("distance", INF))
    )
    var revealed := 0
    for candidate in candidates:
        if revealed >= max_count:
            break
        var clue: Dictionary = candidate.get("clue", {})
        var clue_id := int(clue.get("id", 0))
        scan_revealed_clues.append(clue_id)
        var marker := clue_nodes.get(clue_id) as Node3D
        if marker != null:
            marker.visible = true
        revealed += 1
    return revealed

func _missing_required_knowledge() -> Array[String]:
    var missing: Array[String] = []
    for flag in REQUIRED_KNOWLEDGE:
        if not knowledge_flags.has(flag):
            missing.append(String(flag))
    return missing

func _beacon_block_reason() -> String:
    match activated_beacons.size():
        0:
            return ""
        1:
            if not knowledge_flags.has("weather_station"):
                return "信标校准数据缺失：先调查旧气象站。"
        2:
            if not knowledge_flags.has("ice_rift"):
                return "第二座信标需要热脉资料：先调查冰层裂谷。"
            if not knowledge_flags.has("relay"):
                return "第三座信标的频段仍被遮蔽：先调查废弃通信阵列。"
    return ""

func _thermal_phase() -> float:
    return fmod(mission_elapsed, THERMAL_CYCLE)

func _rift_is_cooling() -> bool:
    var phase := _thermal_phase()
    return phase >= THERMAL_COOLING_START and phase <= THERMAL_COOLING_END

func _operate_rift_valve(peer_id: int) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or not _near_landmark(player, "ice_rift") or rift_valve_open:
        return
    if not _rift_is_cooling():
        var phase := _thermal_phase()
        var wait_time := THERMAL_COOLING_START - phase if phase < THERMAL_COOLING_START else THERMAL_CYCLE - phase + THERMAL_COOLING_START
        show_feedback_rpc.rpc("热脉仍在上升，等待 %.1f 秒进入回落期。" % wait_time, Color("#ffbd75"), 1.8)
        return
    rift_valve_open = true
    knowledge_flags["rift_valve"] = true
    _record_journal("裂谷阀门", "热脉回落时打开阀门，裂谷附近形成了稳定热流；这条规律可以作为长途路线的节拍。")
    _reveal_landmark_signal("transport")
    show_story_rpc.rpc("热脉回落的瞬间，裂谷阀门打开了。热流沿着冰层下方延伸，像一条刚刚苏醒的路。", 7.0)
    show_feedback_rpc.rpc("热脉阀已打开 · 裂谷热流稳定", Color("#ffb36b"), 2.0)
    if is_host:
        sync_contract_state.rpc(mission_elapsed, salvage_value, knowledge_flags.keys(), taken_samples, scan_revealed_clues)
        _broadcast_exploration_state()

func _signal_source(player: SpacePlayer3D) -> Vector3:
    for beacon_id in activated_beacons:
        var beacon := beacons.get(beacon_id) as Node3D
        if beacon != null and _flat_distance(player.global_position, beacon.global_position) <= 3.0:
            return beacon.global_position
    var relay_point := _landmark_position("relay")
    if knowledge_flags.has("relay") and _flat_distance(player.global_position, Vector3(relay_point.x, 0.0, relay_point.y)) <= LANDMARK_INTERACTION_RADIUS:
        return Vector3(relay_point.x, 0.0, relay_point.y)
    return Vector3.INF

func _set_signal_mode(peer_id: int, mode: String) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return
    if mission_elapsed < signal_cooldown_until:
        show_feedback_rpc.rpc("信号阵列冷却中，还需 %.1f 秒。" % (signal_cooldown_until - mission_elapsed), Color("#ffbd75"), 1.4)
        return
    var source := _signal_source(player)
    if source == Vector3.INF:
        show_feedback_rpc.rpc("靠近已启动的信标或通信阵列，才能切换信号频段。", Color("#ffbd75"), 1.8)
        return
    signal_mode = mode
    signal_cooldown_until = mission_elapsed + SIGNAL_COOLDOWN
    if mode == "low":
        signal_lure_position = source
        signal_lure_until = mission_elapsed + SIGNAL_LURE_DURATION
        _record_journal("低频信号", "低频回波会把霜噬生物吸向信号源，给队伍留出穿越冰面的窗口。")
        show_story_rpc.rpc("低频：把信号留在塔上。霜噬生物会追着回波走，但阵列冷却前不能再次切频。", 5.0)
        show_feedback_rpc.rpc("低频已发送 · 生物被引向信号源 %.0f 秒 · 冷却 %.0f 秒" % [SIGNAL_LURE_DURATION, SIGNAL_COOLDOWN], Color("#8be7ff"), 2.2)
    else:
        signal_lure_until = 0.0
        storm_active = true
        storm_remaining = SIGNAL_STORM_DURATION
        storm_elapsed = 0.0
        sync_storm_state.rpc(true, storm_remaining)
        var revealed := _reveal_signal_echoes(source)
        if not enemy_spawned:
            enemy_spawn_center = Vector2(source.x, source.z)
            _spawn_enemy_wave(true)
        elif enemies.is_empty() and not _objectives_ready():
            enemy_spawn_center = Vector2(source.x, source.z)
            _spawn_enemy_wave()
        _record_journal("高频信号", "高频回波会揭示附近的地下线索，但会把暴风雪提前拉到地表；使用后阵列进入冷却。")
        show_story_rpc.rpc("高频：让回波穿透冰层。你会看见更多线索，但风暴也会立刻回应。", 5.0)
        show_feedback_rpc.rpc("高频已发送 · 揭示 %d 条附近回波 · 风暴 %.0f 秒 · 冷却 %.0f 秒" % [revealed, SIGNAL_STORM_DURATION, SIGNAL_COOLDOWN], Color("#ffd089"), 2.2)
    _broadcast_exploration_state()

func _inspect_landmark(peer_id: int, landmark_id: String) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or not _near_landmark(player, landmark_id):
        return
    if knowledge_flags.has(landmark_id):
        return
    if landmark_id == "ice_rift" and not knowledge_flags.has("weather_station"):
        show_feedback_rpc.rpc("热脉冲没有可读的相位，先去旧气象站找观测记录。", Color("#ffbd75"), 2.2)
        return
    if landmark_id == "relay" and not knowledge_flags.has("ice_rift"):
        show_feedback_rpc.rpc("通信阵列被地下热噪声淹没，先确认冰裂谷的脉冲规律。", Color("#ffbd75"), 2.2)
        return
    _start_clue_minigame(peer_id, landmark_id)

func _clue_minigame_config(landmark_id: String) -> Dictionary:
    match landmark_id:
        "weather_station":
            return {"title": "旧气象站 · 频率校准", "mode": "sequence", "sequence": ["A", "D", "W"], "instruction": "按观测台亮起的顺序输入：A → D → W"}
        "ice_rift":
            return {"title": "冰层裂谷 · 热脉同步", "mode": "timing", "sequence": [], "instruction": "热脉进入金色区时按 SPACE，错过可以立即重来"}
        "transport":
            return {"title": "坠毁运输舱 · 货单解码", "mode": "sequence", "sequence": ["F", "G", "F"], "instruction": "按货舱指示输入：F → G → F"}
        "relay":
            return {"title": "废弃通信阵列 · 回声相位", "mode": "sequence", "sequence": ["Q", "E", "Q"], "instruction": "把回声拨回原相位：Q → E → Q"}
    return {"title": "环境线索 · 信号解码", "mode": "sequence", "sequence": ["Q", "E"], "instruction": "按提示输入 Q → E"}

func _start_clue_minigame(peer_id: int, landmark_id: String) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or not _near_landmark(player, landmark_id) or knowledge_flags.has(landmark_id):
        return
    if not is_host:
        request_action.rpc_id(1, peer_id, "repair")
        return
    start_clue_minigame_rpc.rpc(peer_id, landmark_id)

@rpc("authority", "call_local", "reliable")
func start_clue_minigame_rpc(peer_id: int, landmark_id: String) -> void:
    var config := _clue_minigame_config(landmark_id)
    minigame_active = true
    minigame_peer_id = peer_id
    minigame_landmark_id = landmark_id
    minigame_mode = String(config.get("mode", "sequence"))
    minigame_sequence.assign(config.get("sequence", []))
    minigame_step = 0
    minigame_time = 0.0
    minigame_status_text = "失败不会消耗资源，按 R 可重新开始。"
    if _minigame_title != null:
        _minigame_title.text = String(config.get("title", "线索解码"))
        _minigame_instruction.text = String(config.get("instruction", "按提示完成解码"))
        _minigame_panel.visible = true
    _update_clue_minigame(0.0)

func _key_token(event: InputEventKey) -> String:
    var code := event.physical_keycode if event.physical_keycode != 0 else event.keycode
    match code:
        KEY_A: return "A"
        KEY_D: return "D"
        KEY_W: return "W"
        KEY_F: return "F"
        KEY_G: return "G"
        KEY_Q: return "Q"
        KEY_E: return "E"
        KEY_R: return "R"
        KEY_1: return "1"
        KEY_2: return "2"
        KEY_3: return "3"
        KEY_SPACE: return "SPACE"
    return ""

func _handle_clue_minigame_input(event: InputEventKey) -> void:
    if not minigame_active or minigame_peer_id != multiplayer.get_unique_id():
        return
    var token := _key_token(event)
    if token == "R":
        minigame_step = 0
        minigame_time = 0.0
        minigame_status_text = "已重置，请再试一次。"
        return
    if minigame_mode == "timing":
        if token != "SPACE":
            return
        var pulse := 0.5 + 0.5 * sin(minigame_time * 3.8)
        if absf(pulse - 0.7) <= 0.15:
            _complete_clue_minigame()
        else:
            minigame_time = 0.0
            minigame_status_text = "热脉偏离金色区，阀门没有损坏，按 SPACE 再试。"
        return
    if token.is_empty() or minigame_sequence.is_empty():
        return
    if token == minigame_sequence[minigame_step]:
        minigame_step += 1
        minigame_status_text = "输入正确 · 继续下一段"
        if minigame_step >= minigame_sequence.size():
            _complete_clue_minigame()
    else:
        minigame_step = 0
        minigame_status_text = "信号偏移，序列已重置；按提示重新输入。"

func _update_clue_minigame(delta: float) -> void:
    if not minigame_active or _minigame_panel == null:
        return
    minigame_time += delta
    if minigame_mode == "timing":
        var pulse := 0.5 + 0.5 * sin(minigame_time * 3.8)
        var percent := int(round(pulse * 100.0))
        _minigame_progress.text = "热脉位置 %d%%   ·   金色区 55—85%%   ·   SPACE" % percent
    else:
        _minigame_progress.text = "进度 %d / %d   ·   当前输入：%s" % [minigame_step, minigame_sequence.size(), "等待" if minigame_step >= minigame_sequence.size() else minigame_sequence[minigame_step]]
    _minigame_status.text = minigame_status_text

func _complete_clue_minigame() -> void:
    if not minigame_active:
        return
    var peer_id := minigame_peer_id
    var landmark_id := minigame_landmark_id
    _hide_clue_minigame()
    if is_host:
        _finish_clue_investigation(peer_id, landmark_id)
    else:
        request_clue_minigame_result.rpc_id(1, peer_id, landmark_id)

func _hide_clue_minigame() -> void:
    minigame_active = false
    minigame_peer_id = -1
    minigame_landmark_id = ""
    minigame_step = 0
    minigame_time = 0.0
    if _minigame_panel != null:
        _minigame_panel.visible = false

@rpc("any_peer", "reliable")
func request_clue_minigame_result(peer_id: int, landmark_id: String) -> void:
    if is_host and peer_id == multiplayer.get_remote_sender_id():
        finish_clue_minigame_rpc.rpc(peer_id, landmark_id)
        _finish_clue_investigation(peer_id, landmark_id)

@rpc("authority", "call_local", "reliable")
func finish_clue_minigame_rpc(peer_id: int, landmark_id: String) -> void:
    if minigame_peer_id == peer_id and minigame_landmark_id == landmark_id:
        _hide_clue_minigame()

func _finish_clue_investigation(peer_id: int, landmark_id: String) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or not _near_landmark(player, landmark_id) or knowledge_flags.has(landmark_id):
        return
    _apply_landmark_knowledge(landmark_id)
    var display_name := landmark_id
    for landmark in LANDMARK_DATA:
        if String(landmark.get("id", "")) == landmark_id:
            display_name = String(landmark.get("name", landmark_id))
            break
    _record_journal("调查完成 · " + display_name, "现场信号已解码。新的路径线索被写入扫描仪。")
    show_feedback_rpc.rpc("调查完成：%s" % display_name, Color("#ffd089"), 1.8)
    _broadcast_exploration_state()

func _resolve_anomaly(choice: String) -> void:
    if anomaly_resolved:
        return
    if activated_beacons.size() < beacon_positions.size():
        _set_status("中继站仍在等待所有信标回应。")
        return
    var missing := _missing_required_knowledge()
    if not missing.is_empty():
        _set_status("中继站无法解码：仍缺少环境调查。")
        show_feedback_rpc.rpc("先完成气象站、冰裂谷和通信阵列调查。", Color("#ffbd75"), 2.2)
        return
    anomaly_resolved = true
    ending_choice = choice
    story_flags["anomaly_resolved"] = true
    storm_active = false
    storm_remaining = 0.0
    storm_elapsed = 0.0
    sync_storm_state.rpc(false, 0.0)
    if choice == "shutdown":
        _record_journal("中继站决定", "关闭信标网络，地下回声正在衰减。星球暂时恢复安静，但真相仍被留在冰层深处。")
        show_story_rpc.rpc("你切断了信标。冰层下的回声逐渐远去，撤离航道重新变得安静。", 7.0)
    else:
        _record_journal("中继站决定", "稳定信标网络，地下回声被压回深层。气象数据开始恢复，但仍有一条信号没有停止。")
        show_story_rpc.rpc("你稳定了信标网络。暴风雪正在退去，但冰层深处仍有东西在回应。", 7.0)
    _set_status("异常状态已处理，确认撤离路线。")
    _broadcast_exploration_state()

func _broadcast_exploration_state() -> void:
    if is_host:
        sync_exploration_state.rpc(story_flags, anomaly_resolved, ending_choice, rift_valve_open, signal_mode, signal_lure_until, signal_lure_position, signal_cooldown_until, map_markers)

func _drop_carried_item(peer_id: int) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or player.carrying == 0:
        show_feedback_rpc.rpc("手上没有可丢弃的物品。", Color("#ffbd75"), 1.0)
        return
    var carrying_kind := player.carrying
    var carrying_id := player.carrying_id
    var drop_position := player.global_position + Vector3(0.0, 0.0, 0.9)
    if carrying_kind == 1 and crates.has(carrying_id):
        taken_crates.erase(carrying_id)
        crates[carrying_id].global_position = drop_position
        crates[carrying_id].visible = true
        sync_dropped_item.rpc(1, carrying_id, drop_position)
        show_feedback_rpc.rpc("已丢下热能电池，按 F 可重新拾取。", Color("#8be7ff"), 1.2)
    elif carrying_kind == 2 and samples.has(carrying_id):
        taken_samples.erase(carrying_id)
        samples[carrying_id].global_position = drop_position
        samples[carrying_id].visible = true
        sync_dropped_item.rpc(2, carrying_id, drop_position)
        show_feedback_rpc.rpc("已丢下异常冰样，按 F 可重新拾取。", Color("#c8b6ff"), 1.2)
    else:
        show_feedback_rpc.rpc("物品状态已失效，已清空手持栏。", Color("#ffbd75"), 1.2)
    player.carrying = 0
    player.carrying_id = 0
    _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot(), journal_entries, discovered_regions)
    sync_contract_state.rpc(mission_elapsed, salvage_value, knowledge_flags.keys(), taken_samples, scan_revealed_clues)

@rpc("authority", "call_local", "reliable")
func sync_dropped_item(kind: int, item_id: int, drop_position: Vector3) -> void:
    if kind == 1 and crates.has(item_id):
        crates[item_id].global_position = drop_position
        crates[item_id].visible = true
    elif kind == 2 and samples.has(item_id):
        samples[item_id].global_position = drop_position
        samples[item_id].visible = true

func handle_action(peer_id: int, action: String) -> void:
    if not is_host:
        request_action.rpc_id(1, peer_id, action)
        return
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return
    if action == "mark_heat":
        _place_map_marker(peer_id, "heat")
        return
    if action == "mark_clue":
        _place_map_marker(peer_id, "clue")
        return
    if action == "clear_marker":
        _clear_last_map_marker(peer_id)
        return
    if action == "signal_high":
        _set_signal_mode(peer_id, "high")
        return
    if action == "signal_low":
        _set_signal_mode(peer_id, "low")
        return
    if _field_interactions != null and _field_interactions.handle_action(peer_id, action):
        return
    if action == "repair":
        if _near_landmark(player, "relay") and knowledge_flags.has("relay") and activated_beacons.size() >= beacon_positions.size():
            _resolve_anomaly("stabilize")
            return
        if _near_landmark(player, "ice_rift") and knowledge_flags.has("ice_rift") and not rift_valve_open:
            _operate_rift_valve(peer_id)
            return
        for landmark in LANDMARK_DATA:
            var landmark_id := String(landmark.get("id", ""))
            if not knowledge_flags.has(landmark_id) and _near_landmark(player, landmark_id):
                _inspect_landmark(peer_id, landmark_id)
                return
        for id in beacons:
            if activated_beacons.has(id):
                continue
            if _flat_distance(player.global_position, beacons[id].global_position) <= 2.0:
                var block_reason := _beacon_block_reason()
                if not block_reason.is_empty():
                    _set_status(block_reason)
                    show_feedback_rpc.rpc(block_reason, Color("#ffbd75"), 2.2)
                    return
                activated_beacons.append(id)
                _set_status("玩家 %d 已修复气象信标 %d。" % [peer_id, id])
                _record_journal("信标 %d" % id, "通讯塔恢复供电。旧频道没有求救，而是在重复一个陌生人的呼号。")
                _spawn_particle_burst(beacons[id].global_position + Vector3(0, 1.5, 0), Color("#ffd966"), 8)
                floating_feedback_rpc.rpc(beacons[id].global_position + Vector3(0, 2.0, 0), "信标已修复", Color("#ffe08a"))
                show_feedback_rpc.rpc("信标修复", Color("#ffd966"), 1.0)
                if activated_beacons.size() == 1 and not story_flags.has("first_beacon"):
                    story_flags["first_beacon"] = true
                    _reveal_landmark_signal("weather_station")
                    show_story_rpc.rpc("信标重新亮起。旧频道自动接通：‘……你们终于来了。’ 回波把坐标指向旧气象站。", 7.0)
                    _record_journal("路线解锁", "第一座信标的回波指向旧气象站。先读取天气记录，才能校准后续信标。")
                elif activated_beacons.size() >= beacon_positions.size() and not story_flags.has("all_beacons"):
                    story_flags["all_beacons"] = true
                    _reveal_landmark_signal("relay")
                    _record_journal("路线解锁", "三座信标已经同时回应。回到废弃通信阵列，在中继站选择稳定或关闭地下异常；之后还要清掉撤离航道。")
                    show_story_rpc.rpc("三座信标同时回应。地下异常已经无法继续回避，回到通信阵列做出选择，然后清理撤离航道。", 7.0)
                _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot(), journal_entries, discovered_regions)
                _broadcast_exploration_state()
                return
    elif action == "pickup":
        if _retrieve_scan_device(peer_id):
            return
        for id in crates:
            if taken_crates.has(id) or player.carrying > 0:
                continue
            if _flat_distance(player.global_position, crates[id].global_position) <= RESOURCE_INTERACTION_RADIUS:
                taken_crates.append(id)
                player.carrying = 1
                player.carrying_id = id
                crates[id].visible = false
                _set_status("玩家 %d 拾取了热能电池。" % peer_id)
                _record_journal("热能电池", "电池仍在发热，外壳上的编号属于已经注销的科考队。")
                _spawn_particle_burst(crates[id].global_position + Vector3(0, 0.8, 0), Color("#6ee7b7"), 6)
                floating_feedback_rpc.rpc(crates[id].global_position + Vector3(0, 1.35, 0), "电池 +1", Color("#9ff5c9"))
                show_feedback_rpc.rpc("电池 +1", Color("#6ee7b7"), 0.8)
                _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot(), journal_entries, discovered_regions)
                return
        for id in samples:
            if taken_samples.has(id) or player.carrying > 0:
                continue
            if _flat_distance(player.global_position, samples[id].global_position) <= RESOURCE_INTERACTION_RADIUS:
                taken_samples.append(id)
                player.carrying = 2
                player.carrying_id = id
                samples[id].visible = false
                _set_status("玩家 %d 拾取了异常冰样。" % peer_id)
                _record_journal("异常冰样", "样本内部仍在脉动：可选回收并带回 +20 价值，携带时会提前引来敌袭。")
                _spawn_particle_burst(samples[id].global_position + Vector3(0, 0.8, 0), Color("#b8a1ff"), 8)
                floating_feedback_rpc.rpc(samples[id].global_position + Vector3(0, 1.35, 0), "样本 +1", Color("#d5c8ff"))
                show_feedback_rpc.rpc("样本 +1 · 价值 %d" % SAMPLE_VALUE, Color("#c8b6ff"), 1.0)
                sync_contract_state.rpc(mission_elapsed, salvage_value, knowledge_flags.keys(), taken_samples, scan_revealed_clues)
                return
    elif action == "drop":
        _drop_carried_item(peer_id)
    elif action == "deposit":
        if _near_landmark(player, "relay") and knowledge_flags.has("relay") and activated_beacons.size() >= beacon_positions.size():
            _resolve_anomaly("shutdown")
            return
        if player.carrying > 0 and _flat_distance(player.global_position, Vector3(EXTRACTION.x, 0, EXTRACTION.y)) <= 2.4:
            var carried_kind := player.carrying
            player.carrying = 0
            player.carrying_id = 0
            if carried_kind == 2:
                salvage_value += SAMPLE_VALUE
                _set_status("已投送异常冰样，当前可选回收价值 %d / %d。" % [salvage_value, OPTIONAL_REWARD_TARGET])
                _record_journal("安全屋记录", "样本被装入隔离舱，飞船的导航仪短暂捕捉到一条新的地下回波。")
            else:
                deposited_resources += 1
                salvage_value += BATTERY_VALUE
                _set_status("已投送热能电池 %d / %d，当前可选回收价值 %d / %d。" % [deposited_resources, crates.size(), salvage_value, OPTIONAL_REWARD_TARGET])
                _record_journal("安全屋记录", "带回的电池让安全屋恢复了短暂的热量。地下信号也随之变强。")
            _spawn_particle_burst(Vector3(EXTRACTION.x, 1.2, EXTRACTION.y), Color("#5ac8ff"), 6)
            floating_feedback_rpc.rpc(Vector3(EXTRACTION.x, 2.0, EXTRACTION.y), "投送完成", Color("#9fe8ff"))
            show_feedback_rpc.rpc("投送完成 · 可选回收价值 %d/%d" % [salvage_value, OPTIONAL_REWARD_TARGET], Color("#5ac8ff"), 1.0)
            if carried_kind == 1 and deposited_resources == 1 and not story_flags.has("first_battery"):
                story_flags["first_battery"] = true
                show_story_rpc.rpc("电池箱上的编号属于一支已经注销的科考队。它们把东西送到了这里，却没有回收。", 7.0)
            _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot(), journal_entries, discovered_regions)
            sync_contract_state.rpc(mission_elapsed, salvage_value, knowledge_flags.keys(), taken_samples, scan_revealed_clues)
    elif action == "revive":
        for mate in players.values():
            if mate.peer_id != peer_id and mate.downed and _flat_distance(player.global_position, mate.global_position) <= REVIVE_RANGE:
                reviving[peer_id] = mate.peer_id
                revive_progress[peer_id] = 0.0
                _set_status("玩家 %d 正在救援玩家 %d，需要保持 3 秒。" % [peer_id, mate.peer_id])
                show_feedback_rpc.rpc("救援中", Color("#ffdb91"), 0.5)
                return

@rpc("any_peer", "reliable")
func request_action(peer_id: int, action: String) -> void:
    if is_host:
        handle_action(peer_id, action)

@rpc("any_peer", "reliable")
func request_clue_discovery(clue_id: int) -> void:
    if not is_host:
        return
    if discovered_clues.has(clue_id):
        return
    var found: Dictionary = {}
    for clue in exploration_clues:
        if int(clue.get("id", 0)) == clue_id:
            found = clue
            break
    if found.is_empty():
        return
    discovered_clues.append(clue_id)
    var kind := String(found.get("kind", ""))
    if kind == "landmark":
        var region := String(found.get("region", "未知区域"))
        if not discovered_regions.has(region):
            discovered_regions.append(region)
        _record_journal(String(found.get("name", "未知地标")) + " · " + region, "远景地标已登记。靠近它并按 E 调查，才能读懂留下的信号。")
    elif kind == "beacon":
        _record_journal("现场痕迹", "拖痕指向一座尚未修复的气象信标。")
    elif kind == "crate":
        _record_journal("现场痕迹", "热融痕迹指向一枚热能电池，附近可能有人先来过。")
    elif kind == "sample":
        _record_journal("现场痕迹", "紫色反光藏在冰层边缘，像一枚被遗忘的异常冰样。")
    _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot(), journal_entries, discovered_regions)

func _apply_landmark_knowledge(landmark_id: String) -> void:
    if landmark_id.is_empty() or knowledge_flags.has(landmark_id):
        return
    knowledge_flags[landmark_id] = true
    match landmark_id:
        "weather_station":
            _record_journal("知识解锁", "旧气象站的观测台能标出异常冰样的频段；部署扫描器后会优先显示异常样本回波。")
            _reveal_sample_clues()
            _reveal_landmark_signal("ice_rift")
            _reveal_next_beacon_signal()
            show_story_rpc.rpc("气象记录显示：暴风雪不是天气，而是信标启动后从冰层里升起的回应。", 7.0)
            _knowledge_feedback("知识解锁：异常冰样回波已加入扫描", Color("#c8b6ff"))
        "ice_rift":
            _record_journal("知识解锁", "天气记录与裂谷脉冲完全同频。等热脉回落时按 E 开阀，稳定热流会成为穿越冰原的安全节点。")
            _reveal_landmark_signal("relay")
            _reveal_next_beacon_signal()
            show_story_rpc.rpc("裂谷的热脉与信标同频。地下回声不是从远处传来，而是在等待下一次启动；先在回落期开阀，再去通信阵列。", 7.0)
            _knowledge_feedback("知识解锁：裂谷热脉可供回温", Color("#ffb36b"))
        "transport":
            _record_journal("知识解锁", "运输舱的货单确认：样本价值很高，但带回样本会让移动和撤离更危险。")
            _reveal_sample_clues()
            _knowledge_feedback("知识解锁：异常冰样价值 +20", Color("#b8a1ff"))
        "relay":
            _record_journal("知识解锁", "通信阵列回放了失踪队伍的最后决定：第三座信标不是单纯维修，而是决定地下回声的去留。")
            show_story_rpc.rpc("通信阵列回放了失踪队伍的最后决定：第三座信标不是修复问题，而是选择。三座信标齐亮后，回到这里处理地下异常。", 7.0)
            _reveal_next_beacon_signal()
            _knowledge_feedback("知识解锁：暴风雪预报已接入日志", Color("#75dff5"))
    if is_host:
        sync_contract_state.rpc(mission_elapsed, salvage_value, knowledge_flags.keys(), taken_samples, scan_revealed_clues)

func _reveal_sample_clues() -> void:
    for clue in exploration_clues:
        if String(clue.get("kind", "")) != "sample":
            continue
        var clue_id := int(clue.get("id", 0))
        if not scan_revealed_clues.has(clue_id) and not discovered_clues.has(clue_id):
            scan_revealed_clues.append(clue_id)
        var marker := clue_nodes.get(clue_id) as Node3D
        if marker != null:
            marker.visible = true

func _knowledge_feedback(text: String, color: Color) -> void:
    if is_host:
        show_feedback_rpc.rpc(text, color, 2.0)
    else:
        _show_feedback(text, color, 2.0)

func _tick_revive(delta: float) -> void:
    for reviver_id in reviving.keys().duplicate():
        var target_id := int(reviving[reviver_id])
        var reviver := players.get(int(reviver_id)) as SpacePlayer3D
        var target := players.get(target_id) as SpacePlayer3D
        if reviver == null or target == null or reviver.downed or not target.downed or _flat_distance(reviver.global_position, target.global_position) > REVIVE_RANGE:
            reviving.erase(reviver_id)
            revive_progress.erase(reviver_id)
            continue
        var progress := float(revive_progress.get(reviver_id, 0.0)) + delta
        if progress >= REVIVE_TIME:
            reviving.erase(reviver_id)
            revive_progress.erase(reviver_id)
            target.downed = false
            target.health = 2
            target.oxygen = maxf(target.oxygen, REVIVE_OXYGEN)
            target.warmth = 1.0
            _set_status("玩家 %d 已救起玩家 %d。" % [reviver_id, target_id])
            _spawn_particle_burst(target.global_position + Vector3(0, 1.0, 0), Color("#6ee7b7"), 8)
            camera_shake_rpc.rpc(reviver_id, 0.035, 0.12)
            camera_shake_rpc.rpc(target_id, 0.08, 0.16)
            floating_feedback_rpc.rpc(target.global_position + Vector3(0, 1.65, 0), "救援成功", Color("#9ff5c9"))
            show_feedback_rpc.rpc("救援成功", Color("#6ee7b7"), 1.0)
        else:
            revive_progress[reviver_id] = progress

func attack_from_peer(peer_id: int) -> void:
    if not is_host:
        request_attack.rpc_id(1, peer_id)
        return
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed or not game_started or mission_completed or mission_failed:
        return
    var now := Time.get_ticks_msec()
    if now < int(_attack_ready_at.get(peer_id, 0)):
        return
    _attack_ready_at[peer_id] = now + int(SpacePlayer3D.ATTACK_INTERVAL * 1000.0) - 20
    var nearest: SpaceEnemy3D
    var distance_limit := SpacePlayer3D.ATTACK_RANGE
    for enemy in enemies.values():
        var candidate := enemy as SpaceEnemy3D
        var distance := _flat_distance(player.global_position, candidate.global_position)
        if distance <= distance_limit:
            distance_limit = distance
            nearest = candidate
    if nearest == null:
        attack_feedback.rpc(peer_id, player.global_position + Vector3(0, 0, -1.2), false)
        show_feedback_rpc.rpc("超出射程", Color("#ff6b6b"), 0.6)
        return
    attack_feedback.rpc(peer_id, nearest.global_position, true)
    if nearest.take_damage(1):
        enemies.erase(nearest.enemy_id)
        nearest.queue_free()
        _spawn_particle_burst(nearest.global_position + Vector3(0, 0.5, 0), Color("#ff5555"), 10)
        show_feedback_rpc.rpc("击杀", Color("#ff8888"), 1.0)
    else:
        show_feedback_rpc.rpc("命中 -1 HP", Color("#ffaa66"), 0.6)
    _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot(), journal_entries, discovered_regions)

@rpc("authority", "call_local", "reliable")
func attack_feedback(peer_id: int, target: Vector3, hit: bool) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null:
        return
    player.show_attack_animation()
    player.trigger_camera_shake(0.045 if hit else 0.025, 0.08)
    _spawn_attack_effect(player.global_position, target)
    floating_feedback_rpc(target + Vector3(0, 1.2, 0), "命中" if hit else "未命中", Color("#ffd089") if hit else Color("#ff9d9d"))
    if peer_id == multiplayer.get_unique_id():
        _set_status("命中！按住空格连续攻击范围圈内的异形。" if hit else "已开火 · 圈内没有敌人，请靠近红色异形。")

func _spawn_attack_effect(from_position: Vector3, to_position: Vector3) -> void:
    var effect := MeshInstance3D.new()
    var beam := BoxMesh.new()
    var start := from_position + Vector3(0.0, 0.86, 0.0)
    var target := to_position + Vector3(0.0, 0.62, 0.0)
    var direction := target - start
    beam.size = Vector3(0.08, 0.08, maxf(direction.length(), 0.08))
    effect.mesh = beam
    add_child(effect)
    effect.global_position = (start + target) * 0.5
    effect.look_at(target, Vector3.UP)
    effect.material_override = _glow_material(Color("#9ffcff"), 1.8)
    var beam_light := OmniLight3D.new()
    beam_light.light_color = Color("#9ffcff")
    beam_light.light_energy = 1.5
    beam_light.omni_range = 1.5
    beam_light.position = (start + target) * 0.5
    add_child(beam_light)
    get_tree().create_timer(0.12).timeout.connect(func():
        effect.queue_free()
        beam_light.queue_free()
    )

@rpc("any_peer", "reliable")
func request_attack(peer_id: int) -> void:
    if is_host and peer_id == multiplayer.get_remote_sender_id():
        attack_from_peer(peer_id)

func damage_player(peer_id: int, amount: int) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return
    player.health = maxi(player.health - amount, 0)
    _spawn_particle_burst(player.global_position + Vector3(0, 0.8, 0), Color("#ff6b6b"), 8)
    camera_shake_rpc.rpc(peer_id, 0.13, 0.18)
    floating_feedback_rpc.rpc(player.global_position + Vector3(0, 1.45, 0), "-%d HP" % amount, Color("#ff8f88"))
    show_feedback_rpc.rpc("受伤 -%d HP" % amount, Color("#ff6b6b"), 0.8)
    if player.health <= 0:
        player.downed = true
        player.velocity = Vector3.ZERO
        _set_status("玩家 %d 倒地，等待队友靠近按 R 救援。" % peer_id)
        _spawn_particle_burst(player.global_position + Vector3(0, 1.0, 0), Color("#ff3333"), 15)
        camera_shake_rpc.rpc(peer_id, 0.2, 0.28)
        show_feedback_rpc.rpc("倒地", Color("#ff3333"), 2.0)
        _check_all_downed()

func _tick_survival(delta: float) -> void:
    for player in players.values():
        var p := player as SpacePlayer3D
        if p == null or p.downed:
            continue
        var near_heat := _flat_distance(p.global_position, Vector3(SAFEHOUSE.x, 0.0, SAFEHOUSE.y)) <= HEAT_RADIUS
        if not near_heat:
            # 地热口是中段的续命点：把长距离移动切成几段，同时是显眼的地标。
            for vent in FrostMapLayout.THERMAL_VENTS:
                var vent_point := Vector2(vent.get("position", Vector2.ZERO))
                if _flat_distance(p.global_position, Vector3(vent_point.x, 0.0, vent_point.y)) <= HEAT_RADIUS:
                    near_heat = true
                    break
        if not near_heat:
            for beacon_id in activated_beacons:
                var beacon := beacons.get(beacon_id) as Node3D
                if beacon != null and _flat_distance(p.global_position, beacon.global_position) <= HEAT_RADIUS:
                    near_heat = true
                    break
        if not near_heat and rift_valve_open:
            near_heat = _flat_distance(p.global_position, Vector3(132.0, 0.0, -94.0)) <= HEAT_RADIUS * 1.35
        if not near_heat and _field_interactions != null:
            for source in _field_interactions.heat_sources():
                var source_point := Vector2(source.get("position", Vector2.ZERO))
                var source_radius := float(source.get("radius", HEAT_RADIUS))
                if _flat_distance(p.global_position, Vector3(source_point.x, 0.0, source_point.y)) <= source_radius:
                    near_heat = true
                    break
        var sprint_oxygen_scale := SPRINT_OXYGEN_MULTIPLIER if p.sprinting else 1.0
        var sprint_warmth_scale := SPRINT_WARMTH_MULTIPLIER if p.sprinting else 1.0
        if near_heat and not p.sprinting:
            var heat_recovery_scale := 0.42 if storm_active else 1.0
            p.warmth = minf(p.warmth + WARMTH_RECOVER * heat_recovery_scale * delta, 1.0)
            p.oxygen = minf(p.oxygen + OXYGEN_RECOVER * heat_recovery_scale * delta, 100.0)
        elif near_heat:
            # 加速时仍可以经过热源，但体温和氧气会按加速消耗，避免“站在热源里无限冲刺”。
            var heat_sprint_scale := 0.35 if not storm_active else 0.6
            p.warmth = maxf(p.warmth - WARMTH_DRAIN * heat_sprint_scale * sprint_warmth_scale * delta, 0.0)
            p.oxygen = maxf(p.oxygen - OXYGEN_DRAIN_BASE * heat_sprint_scale * sprint_oxygen_scale * delta, 0.0)
        else:
            var storm_cold_scale := 2.15 if storm_active else 1.0
            var storm_oxygen_scale := 1.45 if storm_active else 1.0
            p.warmth = maxf(p.warmth - WARMTH_DRAIN * storm_cold_scale * sprint_warmth_scale * delta, 0.0)
            p.oxygen = maxf(p.oxygen - delta * (OXYGEN_DRAIN_BASE + (1.0 - p.warmth) * OXYGEN_DRAIN_COLD) * storm_oxygen_scale * sprint_oxygen_scale, 0.0)
            if p.oxygen <= 0.0:
                p.downed = true
                p.health = 0
                _set_status("玩家 %d 因氧气耗尽倒地。" % p.peer_id)
                _check_all_downed()

func _check_all_downed() -> void:
    if players.is_empty():
        return
    for player in players.values():
        var p := player as SpacePlayer3D
        if p != null and not p.downed:
            return
    fail_mission()

func fail_mission() -> void:
    if mission_failed or mission_completed:
        return
    mission_failed = true
    mission_return_timer = 0.0
    mission_summary = "全员倒地：回收价值 %d，发现区域 %d，样本 %d。" % [salvage_value, discovered_regions.size(), taken_samples.size()]
    _set_status(mission_summary)

func _tick_extraction(delta: float) -> void:
    if not _objectives_ready() or not enemies.is_empty():
        extraction_enabled = false
        extraction_progress = 0.0
        return
    if not extraction_enabled:
        _set_status("地下异常已处理且区域已清场，撤离点开放；携带物资属于额外回收。")
    extraction_enabled = true
    var all_ready := true
    for player in players.values():
        var p := player as SpacePlayer3D
        if p.downed or _flat_distance(p.global_position, Vector3(EXTRACTION.x, 0, EXTRACTION.y)) > 2.5:
            all_ready = false
            break
    extraction_progress = minf(extraction_progress + delta, 3.0) if all_ready else 0.0
    if extraction_progress >= 3.0:
        mission_completed = true
        mission_return_timer = 0.0
        var ending_name := "关闭信标" if ending_choice == "shutdown" else "稳定信标"
        mission_summary = "撤离成功：%s；回收价值 %d，发现区域 %d，样本 %d。" % [ending_name, salvage_value, discovered_regions.size(), taken_samples.size()]
        if story_flags.has("crew_message_returned"):
            mission_summary += " 岑夏与陆衡的留言已送回归航号。"
        _set_status(mission_summary)

@rpc("authority", "call_local", "reliable")
func return_to_ship(reason: String, final_vitals: Array = []) -> void:
    var returning_vitals := final_vitals if not final_vitals.is_empty() else _vitals_snapshot()
    if is_host:
        _ship_session.settle(mission_completed, salvage_value, reason)
    game_started = false
    mission_completed = false
    mission_failed = false
    mission_summary = ""
    extraction_enabled = false
    extraction_progress = 0.0
    enemy_spawned = false
    enemy_wave_index = 0
    enemy_wave_timer = 0.0
    mission_return_timer = 0.0
    mission_elapsed = 0.0
    salvage_value = 0
    contract_sync_accumulator = 0.0
    knowledge_flags.clear()
    anomaly_resolved = false
    ending_choice = ""
    rift_valve_open = false
    signal_mode = "neutral"
    signal_lure_until = 0.0
    signal_lure_position = Vector3.ZERO
    signal_cooldown_until = 0.0
    storm_active = false
    storm_elapsed = 0.0
    storm_remaining = 0.0
    story_elapsed = 0.0
    story_flags.clear()
    enemy_trigger_flags.clear()
    enemy_spawn_center = Vector2(4.0, -2.0)
    reviving.clear()
    revive_progress.clear()
    if _world_root != null:
        if _field_interactions != null:
            _field_interactions.reset()
        remove_child(_world_root)
        _world_root.queue_free()
        _world_root = null
    _clear_players()
    for enemy in enemies.values():
        remove_child(enemy)
        (enemy as Node).queue_free()
    enemies.clear()
    obstacles.clear()
    beacons.clear()
    crates.clear()
    samples.clear()
    exploration_clues.clear()
    clue_nodes.clear()
    discovered_clues.clear()
    scan_revealed_clues.clear()
    map_markers.clear()
    next_marker_id = 1
    journal_entries.clear()
    discovered_regions.clear()
    activated_beacons.clear()
    taken_crates.clear()
    taken_samples.clear()
    deposited_resources = 0
    sample_positions.clear()
    beacon_positions.clear()
    crate_positions.clear()
    scan_visual = null
    scan_device = null
    scan_device_active = false
    scan_device_position = Vector3.ZERO
    scan_peer_id = -1
    scan_remaining = 0.0
    scan_cooldown = 0.0
    _thought_timer = 0.0
    if _thought_label != null:
        _thought_label.visible = false
    _story_timer = 0.0
    if _story_label != null:
        _story_label.visible = false
    _journal_visible = false
    _hide_clue_minigame()
    if _journal_panel != null:
        _journal_panel.visible = false
    if _menu_world != null:
        _menu_world.visible = true
    if _game_layer != null:
        _game_layer.visible = false
    if _menu_layer != null:
        _menu_layer.visible = true
    _ship_session.enter_ship(true, connected_ids, _ship_session.snapshot(), returning_vitals)
    _ship_session.show_notice(reason)
    if is_host:
        _ship_session.broadcast()

func _objectives_ready() -> bool:
    return activated_beacons.size() >= beacon_positions.size() and anomaly_resolved and _missing_required_knowledge().is_empty()

func _flat_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _enemy_snapshot() -> Array:
    var snapshot: Array = []
    for enemy in enemies.values():
        var e := enemy as SpaceEnemy3D
        snapshot.append([e.enemy_id, e.global_position, e.health])
    return snapshot

func _world_snapshot() -> Dictionary:
    return {"ship_state": _ship_session.snapshot(), "wave": enemy_wave_index, "timer": enemy_wave_timer, "enemies": _enemy_snapshot(), "beacons": activated_beacons, "crates": taken_crates, "samples": taken_samples, "deposited": deposited_resources, "salvage": salvage_value, "mission_elapsed": mission_elapsed, "knowledge": knowledge_flags.keys(), "anomaly_resolved": anomaly_resolved, "ending_choice": ending_choice, "story_flags": story_flags, "rift_valve_open": rift_valve_open, "signal_mode": signal_mode, "signal_lure_until": signal_lure_until, "signal_lure_position": signal_lure_position, "signal_cooldown_until": signal_cooldown_until, "map_markers": map_markers, "vitals": _vitals_snapshot(), "beacon_positions": beacon_positions, "crate_positions": crate_positions, "sample_positions": sample_positions, "journal": journal_entries, "regions": discovered_regions, "clues": discovered_clues, "scan_clues": scan_revealed_clues, "scan_device_active": scan_device_active, "scan_device_position": scan_device_position, "scan_remaining": scan_remaining, "field_state": _field_interactions.snapshot() if _field_interactions != null else {}}

func _vitals_snapshot() -> Array:
    var snapshot: Array = []
    for id in players:
        var p := players[id] as SpacePlayer3D
        if p != null:
            snapshot.append([id, p.health, p.oxygen, p.warmth, p.carrying, p.downed, p.carrying_id, p.sprinting])
    return snapshot

@rpc("authority", "call_local", "unreliable")
func sync_vitals(snapshot: Array, in_ship := false) -> void:
    # 地表的延迟数据不能覆盖返航后已恢复的舱内状态。
    if in_ship != ship_active:
        return
    for entry in snapshot:
        var p := players.get(int(entry[0])) as SpacePlayer3D
        if p == null:
            continue
        p.health = int(entry[1])
        p.oxygen = float(entry[2])
        p.warmth = float(entry[3])
        p.carrying = int(entry[4])
        p.downed = bool(entry[5])
        p.carrying_id = int(entry[6]) if entry.size() > 6 else 0
        p.sprinting = bool(entry[7]) if entry.size() > 7 else false

@rpc("authority", "call_local", "reliable")
func sync_full_state(snapshot: Dictionary) -> void:
    _ship_session.apply_state(snapshot.get("ship_state", {}))
    if not game_started:
        _start_planet()
    enemy_wave_index = int(snapshot.get("wave", 0))
    enemy_wave_timer = float(snapshot.get("timer", 0.0))
    activated_beacons.assign(snapshot.get("beacons", []))
    taken_crates.assign(snapshot.get("crates", []))
    taken_samples.assign(snapshot.get("samples", []))
    deposited_resources = int(snapshot.get("deposited", 0))
    salvage_value = int(snapshot.get("salvage", deposited_resources * BATTERY_VALUE))
    mission_elapsed = float(snapshot.get("mission_elapsed", 0.0))
    anomaly_resolved = bool(snapshot.get("anomaly_resolved", false))
    ending_choice = String(snapshot.get("ending_choice", ""))
    rift_valve_open = bool(snapshot.get("rift_valve_open", false))
    signal_mode = String(snapshot.get("signal_mode", "neutral"))
    signal_lure_until = float(snapshot.get("signal_lure_until", 0.0))
    signal_lure_position = Vector3(snapshot.get("signal_lure_position", Vector3.ZERO))
    signal_cooldown_until = float(snapshot.get("signal_cooldown_until", 0.0))
    var saved_story_flags: Dictionary = snapshot.get("story_flags", {})
    story_flags.clear()
    for flag in saved_story_flags.keys():
        story_flags[String(flag)] = saved_story_flags[flag]
    knowledge_flags.clear()
    for flag in snapshot.get("knowledge", []):
        knowledge_flags[String(flag)] = true
    journal_entries.assign(snapshot.get("journal", []))
    discovered_regions.assign(snapshot.get("regions", []))
    discovered_clues.assign(snapshot.get("clues", []))
    scan_revealed_clues.assign(snapshot.get("scan_clues", []))
    map_markers.assign(snapshot.get("map_markers", []))
    next_marker_id = 1
    for marker in map_markers:
        next_marker_id = maxi(next_marker_id, int(marker.get("id", 0)) + 1)
    _apply_layout_snapshot(snapshot.get("beacon_positions", []), snapshot.get("crate_positions", []), snapshot.get("sample_positions", []))
    if _field_interactions != null:
        _field_interactions.apply_snapshot(snapshot.get("field_state", {}))
    if knowledge_flags.has("weather_station") or knowledge_flags.has("transport"):
        _reveal_sample_clues()
    if bool(snapshot.get("scan_device_active", false)):
        sync_scan_device_state(true, Vector3(snapshot.get("scan_device_position", Vector3.ZERO)), float(snapshot.get("scan_remaining", 0.0)))
    sync_vitals(snapshot.get("vitals", []))
    _apply_objective_visuals()
    _apply_enemy_snapshot(snapshot.get("enemies", []))

@rpc("authority", "call_local", "reliable")
func sync_contract_state(elapsed: float, value: int, knowledge: Array, samples_state: Array, scan_state: Array = []) -> void:
    mission_elapsed = elapsed
    salvage_value = value
    knowledge_flags.clear()
    for flag in knowledge:
        knowledge_flags[String(flag)] = true
    if knowledge_flags.has("weather_station"):
        _reveal_sample_clues()
    taken_samples.assign(samples_state)
    if not scan_state.is_empty():
        scan_revealed_clues.assign(scan_state)
    _apply_objective_visuals()
    _refresh_journal()

@rpc("authority", "call_local", "reliable")
func sync_field_state(data: Dictionary) -> void:
    if _field_interactions != null:
        _field_interactions.apply_snapshot(data)
        _refresh_journal()

@rpc("authority", "call_local", "reliable")
func sync_exploration_state(next_story_flags: Dictionary, next_anomaly_resolved: bool, next_ending_choice: String, next_rift_valve_open: bool, next_signal_mode: String, next_signal_lure_until: float, next_signal_lure_position: Vector3, next_signal_cooldown_until: float, next_map_markers: Array = []) -> void:
    story_flags = next_story_flags.duplicate(true)
    anomaly_resolved = next_anomaly_resolved
    ending_choice = next_ending_choice
    rift_valve_open = next_rift_valve_open
    signal_mode = next_signal_mode
    signal_lure_until = next_signal_lure_until
    signal_lure_position = next_signal_lure_position
    signal_cooldown_until = next_signal_cooldown_until
    map_markers.assign(next_map_markers)
    _refresh_journal()

@rpc("authority", "call_local", "reliable")
func _sync_state(enemy_state: Array, wave: int, timer: float, beacon_state: Array, crate_state: Array, deposited: int, vital_state: Array = [], journal_state: Array = [], region_state: Array = []) -> void:
    enemy_wave_index = wave
    enemy_wave_timer = timer
    activated_beacons.assign(beacon_state)
    taken_crates.assign(crate_state)
    deposited_resources = deposited
    if not journal_state.is_empty():
        journal_entries.assign(journal_state)
    if not region_state.is_empty():
        discovered_regions.assign(region_state)
    sync_vitals(vital_state)
    _apply_objective_visuals()
    _refresh_journal()
    _apply_enemy_snapshot(enemy_state)

func _apply_objective_visuals() -> void:
    for id in crates:
        crates[id].visible = not taken_crates.has(id)
    for id in samples:
        samples[id].visible = not taken_samples.has(id)
    for id in beacons:
        var beacon := beacons[id] as Node3D
        if beacon == null:
            continue
        var light := beacon.get_node_or_null("OmniLight3D") as OmniLight3D
        if light != null:
            light.light_color = Color("#8ff1a0") if activated_beacons.has(id) else Color("#ffc86b")
            light.light_energy = 3.2 if activated_beacons.has(id) else 2.0
    _refresh_journal()

func _apply_layout_snapshot(next_beacons: Array, next_crates: Array, next_samples: Array = []) -> void:
    if not next_beacons.is_empty():
        beacon_positions.assign(next_beacons)
    if not next_crates.is_empty():
        crate_positions.assign(next_crates)
    if not next_samples.is_empty():
        sample_positions.assign(next_samples)
    for index in beacon_positions.size():
        var beacon := beacons.get(index + 1) as Node3D
        if beacon != null:
            beacon.position = Vector3(beacon_positions[index].x, 0.0, beacon_positions[index].y)
    for index in crate_positions.size():
        var crate := crates.get(index + 1) as Node3D
        if crate != null:
            crate.position = Vector3(crate_positions[index].x, 0.3, crate_positions[index].y)
    for index in sample_positions.size():
        var sample := samples.get(index + 1) as Node3D
        if sample != null:
            sample.position = Vector3(sample_positions[index].x, 0.16, sample_positions[index].y)
    _prepare_exploration_clues()
    _build_exploration_clues()

func _apply_enemy_snapshot(snapshot: Array) -> void:
    var incoming: Array[int] = []
    for entry in snapshot:
        var id := int(entry[0])
        incoming.append(id)
        var enemy := enemies.get(id) as SpaceEnemy3D
        if enemy == null:
            enemy = ENEMY_SCENE.instantiate() as SpaceEnemy3D
            enemy.setup(id, connected_ids.size())
            add_child(enemy)
            enemies[id] = enemy
        enemy.global_position = entry[1]
        enemy.health = int(entry[2])
    for id in enemies.keys().duplicate():
        if not incoming.has(int(id)):
            enemies[id].queue_free()
            enemies.erase(id)

func _next_objective_text() -> String:
    if mission_completed:
        return "撤离成功，正在返回飞船"
    if mission_failed:
        return "全队倒地，正在返航"
    if extraction_enabled:
        return "全队进入蓝色撤离平台并保持 3 秒"
    if not knowledge_flags.has("weather_station"):
        if activated_beacons.is_empty():
            return "部署扫描器寻找第一座气象信标"
        return "前往旧气象站调查，取得下一座信标的校准资料"
    if not knowledge_flags.has("ice_rift"):
        return "前往冰层裂谷，观察热脉回落并开启阀门"
    if not knowledge_flags.has("relay"):
        return "前往废弃通信阵列，解码地下回波"
    if activated_beacons.size() < beacon_positions.size():
        return "修复剩余气象信标（%d/%d）" % [activated_beacons.size(), beacon_positions.size()]
    if not anomaly_resolved:
        return "回到通信阵列，按 E 稳定或按 G 关闭地下异常"
    if not enemies.is_empty():
        return "清除撤离航道上的剩余敌人"
    return "前往撤离平台集合"

func _update_hud() -> void:
    if not game_started:
        return
    _objective_panel.visible = not _journal_visible
    _vitals_panel.visible = not _journal_visible
    _hint_label.visible = not _journal_visible
    _compass_panel.visible = not _journal_visible
    var phase := "探索霜烬星"
    if extraction_enabled:
        phase = "前往撤离平台"
    elif _objectives_ready():
        phase = "撤离前清理航道"
    elif anomaly_resolved:
        phase = "确认撤离路线"
    var local := players.get(multiplayer.get_unique_id()) as SpacePlayer3D
    if local != null:
        var carry_text := "背包空"
        if local.carrying == 1:
            carry_text = "携带电池 · 可选回收价值 +%d" % BATTERY_VALUE
        elif local.carrying == 2:
            carry_text = "携带异常冰样 · 可选回收价值 +%d" % SAMPLE_VALUE
        var knowledge_count := 0
        for flag in REQUIRED_KNOWLEDGE:
            if knowledge_flags.has(flag):
                knowledge_count += 1
        var anomaly_text := "异常待处理" if not anomaly_resolved else ("异常已处理 · %s" % ("关闭信标" if ending_choice == "shutdown" else "稳定信标"))
        var signal_text := "中性"
        if signal_mode == "high":
            signal_text = "高频 · 探测/风暴"
        elif signal_mode == "low":
            signal_text = "低频 · 诱导"
        _progress_label.text = "%s · %s\n调查 %d/%d   信标 %d/%d\n%s   信号：%s   %.0fs\n下一步：%s" % [phase, _region_hint(local.global_position), knowledge_count, REQUIRED_KNOWLEDGE.size(), activated_beacons.size(), beacon_positions.size(), anomaly_text, signal_text, mission_elapsed, _next_objective_text()]
        _vitals_label.text = "生命 %d/5   氧气 %d%%   体温 %d%%\n%s" % [local.health, int(local.oxygen), int(local.warmth * 100.0), carry_text]
        var vital_color := Color("#ffad9f") if local.oxygen <= 25.0 or local.health <= 2 else Color("#d9eef4")
        _vitals_label.add_theme_color_override("font_color", vital_color)
        var cooldown := local.scan_cooldown_remaining
        var scan_tip := "Q  扫描 %.0fs" % ceilf(cooldown) if cooldown > 0.0 else "Q  扫描"
        _hint_label.text = scan_tip + "    Shift  加速（更耗氧/体温）    F  拾取/回收    X  丢下    Tab  日志    M  地图"
        _update_compass(local)
        if _journal_map_view != null:
            _journal_map_view.update_state(Vector2(local.global_position.x, local.global_position.z), discovered_regions, true)
            _journal_map_view.update_objectives(_known_map_positions("beacon", beacon_positions, activated_beacons), _known_map_positions("crate", crate_positions, taken_crates), activated_beacons, taken_crates)
            _journal_map_view.update_heat_sources(_known_heat_sources())
            _journal_map_view.update_field_sites(_field_interactions.map_sites() if _field_interactions != null else [])
            _journal_map_view.update_markers(map_markers)
        var warning := ""
        if mission_failed:
            warning = "远征失败 · 正在紧急返航"
        elif mission_completed:
            warning = "撤离成功 · 正在返航"
        elif local.downed:
            warning = "你已倒地 · 等待队友救援"
        elif local.oxygen <= 25.0:
            warning = "氧气不足 · 返回热源补氧"
        elif _nearest_threat_distance(local) <= 5.0:
            warning = "霜噬生物正在靠近"
        elif mission_elapsed < signal_lure_until:
            warning = "低频诱导生效 · 生物正在远离队伍"
        elif storm_active:
            warning = "暴风雪 · 视野收窄 / 移动变慢 / 失温加剧"
        elif knowledge_flags.has("relay") and not anomaly_resolved:
            warning = "通信阵列预报 · 距离风暴 %.0fs" % maxf(STORM_INTERVAL - storm_elapsed, 0.0)
        elif extraction_enabled:
            warning = "撤离开放 · 全队集合"
        _alert_label.text = warning
        _alert_label.visible = not warning.is_empty()
        _alert_label.add_theme_color_override("font_color", Color("#ffad9f") if local.downed or local.oxygen <= 25.0 else Color("#ffd089"))

func _update_compass(local: SpacePlayer3D) -> void:
    if _compass_label == null:
        return
    if scan_device_active:
        var scanner_from := Vector2(local.global_position.x, local.global_position.z)
        var scanner_to := Vector2(scan_device_position.x, scan_device_position.z)
        var scanner_distance := scanner_from.distance_to(scanner_to)
        if scanner_distance > RESOURCE_INTERACTION_RADIUS:
            _compass_label.text = "扫描器   ◈ %s   %.0f m · 靠近后按 F 回收" % [_direction_hint(scanner_from, scanner_to), scanner_distance]
            return
    if extraction_enabled:
        var extraction_from := Vector2(local.global_position.x, local.global_position.z)
        _compass_label.text = "撤离罗盘   ◈ %s   %.0f m" % [_direction_hint(extraction_from, EXTRACTION), extraction_from.distance_to(EXTRACTION)]
        return
    var from := Vector2(local.global_position.x, local.global_position.z)
    var best_clue: Dictionary = {}
    var best_distance := INF
    for clue in exploration_clues:
        var clue_id := int(clue.get("id", 0))
        if not scan_revealed_clues.has(clue_id) or discovered_clues.has(clue_id):
            continue
        var kind := String(clue.get("kind", ""))
        var target_id := int(clue.get("target_id", 0))
        if (kind == "beacon" and activated_beacons.has(target_id)) or (kind == "crate" and taken_crates.has(target_id)) or (kind == "sample" and taken_samples.has(target_id)):
            continue
        var point := Vector2(clue.get("position", Vector2.ZERO))
        var distance := from.distance_to(point)
        if distance < best_distance:
            best_distance = distance
            best_clue = clue
    if best_clue.is_empty():
        var next_target := _next_navigation_target()
        if not next_target.is_empty():
            var target_point := Vector2(next_target.get("position", Vector2.ZERO))
            _compass_label.text = "下一步   %s   ◈ %s   %.0f m" % [String(next_target.get("label", "目标")), _direction_hint(from, target_point), from.distance_to(target_point)]
        else:
            _compass_label.text = "信号罗盘   ·   Q 部署扫描器，F 回收"
        return
    var clue_point := Vector2(best_clue.get("position", Vector2.ZERO))
    var clue_kind := String(best_clue.get("kind", ""))
    var signal_name := "拖行回波" if clue_kind == "beacon" else ("热融回波" if clue_kind == "crate" else "异常样本回波")
    _compass_distance = from.distance_to(clue_point)
    _compass_direction = _direction_hint(from, clue_point)
    _compass_target = signal_name
    _compass_label.text = "信号罗盘   %s   ◈ %s   %.0f m" % [signal_name, _compass_direction, _compass_distance]

func _next_navigation_target() -> Dictionary:
    if not knowledge_flags.has("weather_station") and not activated_beacons.is_empty():
        return {"label": "旧气象站", "position": _landmark_position("weather_station")}
    if not knowledge_flags.has("ice_rift") and knowledge_flags.has("weather_station"):
        return {"label": "冰层裂谷", "position": _landmark_position("ice_rift")}
    if not knowledge_flags.has("relay") and knowledge_flags.has("ice_rift"):
        return {"label": "废弃通信阵列", "position": _landmark_position("relay")}
    if activated_beacons.size() < beacon_positions.size() and knowledge_flags.has("relay"):
        for index in beacon_positions.size():
            if not activated_beacons.has(index + 1):
                return {"label": "未修复气象信标", "position": Vector2(beacon_positions[index])}
    if not anomaly_resolved and activated_beacons.size() >= beacon_positions.size() and knowledge_flags.has("relay"):
        return {"label": "通信阵列中继站", "position": _landmark_position("relay")}
    if extraction_enabled:
        return {"label": "蓝色撤离平台", "position": EXTRACTION}
    return {}

func _known_map_positions(kind: String, positions: Array, completed: Array[int]) -> Array:
    var known: Array = []
    for index in positions.size():
        var target_id := index + 1
        if completed.has(target_id):
            known.append(Vector2(positions[index]))
            continue
        for clue in exploration_clues:
            if String(clue.get("kind", "")) != kind or int(clue.get("target_id", 0)) != target_id:
                continue
            var clue_id := int(clue.get("id", 0))
            if scan_revealed_clues.has(clue_id) or discovered_clues.has(clue_id):
                known.append(Vector2(positions[index]))
                break
    return known

func _register_visible_landmarks() -> void:
    var local := players.get(multiplayer.get_unique_id()) as SpacePlayer3D
    if local == null or local._camera == null:
        return
    for clue in exploration_clues:
        if String(clue.get("kind", "")) != "landmark":
            continue
        var clue_id := int(clue.get("id", 0))
        if discovered_clues.has(clue_id):
            continue
        var point := Vector2(clue.get("position", Vector2.ZERO))
        var world_point := Vector3(point.x, 1.5, point.y)
        if not local._camera.is_position_in_frustum(world_point):
            continue
        # 远景地标进入玩家镜头时立即登记，不要求玩家走到模型脚边。
        if is_host:
            request_clue_discovery(clue_id)
        else:
            request_clue_discovery.rpc_id(1, clue_id)

func _region_hint(position: Vector3) -> String:
    # 直接由区域数据算，不再写死阈值：改地图时不需要同步改这里。
    var point := Vector2(position.x, position.z)
    var best_name := "外环冰原"
    var best_score := 0.0
    for region_name in FrostMapLayout.REGIONS:
        var region: Dictionary = FrostMapLayout.REGIONS[region_name]
        var center := Vector2(region.get("center", Vector2.ZERO))
        var score := 0.0
        if region.has("radius"):
            var radius := float(region["radius"])
            score = 1.0 - clampf(point.distance_to(center) / radius, 0.0, 1.0)
        else:
            var extents := Vector2(float(region.get("width", 12.0)) * 0.5, float(region.get("height", 12.0)) * 0.5)
            var inside := extents - Vector2(absf(point.x - center.x), absf(point.y - center.y))
            var margin := minf(inside.x, inside.y)
            if margin <= 0.0:
                continue
            score = clampf(margin / 12.0 + 0.5, 0.0, 1.0)
        if score > best_score:
            best_score = score
            best_name = region_name
    return best_name

func _nearest_threat_distance(local: SpacePlayer3D) -> float:
    var nearest := INF
    for enemy_value in enemies.values():
        var enemy := enemy_value as SpaceEnemy3D
        if is_instance_valid(enemy):
            nearest = minf(nearest, _flat_distance(local.global_position, enemy.global_position))
    return nearest

func _update_interaction_hint() -> void:
    if _interaction_label == null or not game_started:
        return
    if _interaction_progress != null:
        _interaction_progress.visible = false
    var local := players.get(multiplayer.get_unique_id()) as SpacePlayer3D
    if local == null:
        _interaction_panel.visible = false
        return
    _update_nearby_object_labels(local)
    var threat_distance := _nearest_threat_distance(local)
    if is_instance_valid(local.attack_range_visual):
        local.attack_range_visual.visible = not _journal_visible and not local.downed and threat_distance <= 6.0
    if local.downed or _journal_visible or minigame_active or mission_completed or mission_failed:
        _interaction_panel.visible = false
        return
    var prompts: Array[Dictionary] = []
    if _field_interactions != null:
        var field_prompt := _field_interactions.prompt(local)
        if not field_prompt.is_empty():
            prompts.append({"distance": -0.2, "priority": 96, "text": field_prompt})
        var field_progress := _field_interactions.interaction_progress(local.peer_id)
        if _field_interactions.has_interaction_job(local.peer_id) and _interaction_progress != null:
            _interaction_progress.value = field_progress
            _interaction_progress.visible = true
    if scan_device_active:
        var scanner_distance := _flat_distance(local.global_position, scan_device_position)
        if scanner_distance <= RESOURCE_INTERACTION_RADIUS:
            prompts.append({"distance": scanner_distance, "priority": 95, "text": "[F]  回收扫描器 · 扫描器会保留已锁定线索"})
    if local.carrying > 0:
        prompts.append({"distance": -0.5, "priority": 92, "text": "[X]  丢下携带物 · 之后可继续加速和拾取"})
    for entry in _object_tags:
        var node := entry.get("node") as Node3D
        if not is_instance_valid(node) or not node.visible:
            continue
        var kind := String(entry.get("kind", ""))
        var id := int(entry.get("id", 0))
        if kind == "crate" and taken_crates.has(id):
            continue
        if kind == "sample" and taken_samples.has(id):
            continue
        var distance := _flat_distance(local.global_position, node.global_position)
        if distance > 2.5:
            continue
        var text := ""
        match kind:
            "beacon":
                if not activated_beacons.has(id) and distance <= 2.0:
                    var block_reason := _beacon_block_reason()
                    text = "[E]  修复信标" if block_reason.is_empty() else "[E]  信标需要新的环境资料"
            "crate":
                if local.carrying == 0 and distance <= RESOURCE_INTERACTION_RADIUS:
                    text = "[F]  拾取热能电池"
            "sample":
                if local.carrying == 0 and distance <= RESOURCE_INTERACTION_RADIUS:
                    text = "[F]  拾取异常冰样（可选）"
            "extraction":
                if local.carrying > 0 and distance <= 2.4:
                    text = "[G]  投送携带物"
                elif extraction_enabled:
                    text = "全队留在平台 · 撤离 %.1f / 3 秒" % extraction_progress
        if not text.is_empty():
            prompts.append({"distance": distance, "priority": 50, "text": text})
    for landmark in LANDMARK_DATA:
        var landmark_id := String(landmark.get("id", ""))
        var landmark_point := Vector2(landmark.get("position", Vector2.ZERO))
        var landmark_distance := _flat_distance(local.global_position, Vector3(landmark_point.x, 0.0, landmark_point.y))
        if landmark_distance > LANDMARK_INTERACTION_RADIUS:
            continue
        var landmark_text := ""
        if landmark_id == "relay" and knowledge_flags.has("relay") and activated_beacons.size() >= beacon_positions.size() and not anomaly_resolved:
            landmark_text = "[E] 稳定共振：保留网络数据    [G] 关闭网络：切断地下回声"
        elif not knowledge_flags.has(landmark_id):
            landmark_text = "[E] 调查" + String(landmark.get("name", "地标"))
        if not landmark_text.is_empty():
            prompts.append({"distance": landmark_distance, "priority": 70, "text": landmark_text})
    if knowledge_flags.has("ice_rift") and not rift_valve_open:
        var rift_point := _landmark_position("ice_rift")
        var rift_distance := _flat_distance(local.global_position, Vector3(rift_point.x, 0.0, rift_point.y))
        if rift_distance <= LANDMARK_INTERACTION_RADIUS:
            var rift_prompt := "[E] 开启热脉阀 · 当前为回落期" if _rift_is_cooling() else "热脉上升中 · 等待回落期再按 E"
            prompts.append({"distance": rift_distance, "priority": 85, "text": rift_prompt})
    var signal_source := _signal_source(local)
    if signal_source != Vector3.INF:
        var signal_prompt := "[1] 高频探测：揭示附近回波，但立刻引发风暴   [2] 低频诱导：把生物引向信号源"
        if mission_elapsed < signal_cooldown_until:
            signal_prompt = "信号阵列冷却中 · %.1f 秒后可再次切频" % (signal_cooldown_until - mission_elapsed)
        prompts.append({"distance": 0.0, "priority": 65, "text": signal_prompt})
    var nearest_heat_distance := INF
    for source in _known_heat_sources():
        var source_point := Vector2(source.get("position", Vector2.ZERO))
        nearest_heat_distance = minf(nearest_heat_distance, local.global_position.distance_to(Vector3(source_point.x, local.global_position.y, source_point.y)))
    if nearest_heat_distance <= HEAT_RADIUS:
        if local.oxygen < 98.0 or local.warmth < 0.98:
            prompts.append({"distance": nearest_heat_distance, "priority": 10, "text": "热源正在补氧、回温"})
    for mate_value in players.values():
        var mate := mate_value as SpacePlayer3D
        if mate != null and mate.peer_id != local.peer_id and mate.downed and _flat_distance(local.global_position, mate.global_position) <= REVIVE_RANGE:
            prompts.append({"distance": -1.0, "priority": 100, "text": "[R]  救援队友 · 保持 3 秒"})
    if threat_distance <= SpacePlayer3D.ATTACK_RANGE:
        prompts.append({"distance": threat_distance, "priority": 80, "text": "[空格]  按住攻击"})
    prompts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if int(a.priority) == int(b.priority):
            return float(a.distance) < float(b.distance)
        return int(a.priority) > int(b.priority))
    _interaction_panel.visible = not prompts.is_empty()
    _interaction_label.text = String(prompts[0].text) if not prompts.is_empty() else ""

func _update_nearby_object_labels(local: SpacePlayer3D) -> void:
    for world_label in _world_labels:
        if not is_instance_valid(world_label):
            continue
        var label_distance := _flat_distance(local.global_position, world_label.global_position)
        world_label.visible = label_distance <= 9.0
    for id in beacons:
        var beacon := beacons[id] as Node3D
        var label: Label3D = null
        if beacon != null:
            label = beacon.get_node_or_null("ObjectLabel") as Label3D
        if label != null:
            label.visible = not activated_beacons.has(id) and _flat_distance(local.global_position, beacon.global_position) <= 5.0
    for id in crates:
        var crate := crates[id] as Node3D
        var label: Label3D = null
        if crate != null:
            label = crate.get_node_or_null("ObjectLabel") as Label3D
        if label != null:
            label.visible = not taken_crates.has(id) and _flat_distance(local.global_position, crate.global_position) <= 5.0
    for id in samples:
        var sample := samples[id] as Node3D
        var label: Label3D = null
        if sample != null:
            label = sample.get_node_or_null("ObjectLabel") as Label3D
        if label != null:
            label.visible = not taken_samples.has(id) and _flat_distance(local.global_position, sample.global_position) <= 5.0

func _set_status(message: String) -> void:
    if _status_label != null:
        _status_label.text = "状态：" + message
    if _game_status_label != null:
        _game_status_label.text = message

func _record_journal(title: String, text: String) -> void:
    var entry := "【%s】 %s" % [title, text]
    if journal_entries.has(entry):
        return
    journal_entries.push_front(entry)
    while journal_entries.size() > JOURNAL_MAX_ENTRIES:
        journal_entries.pop_back()
    _refresh_journal()

func _refresh_journal() -> void:
    if _journal_label == null:
        return
    var lines := PackedStringArray()
    lines.append("已发现区域：%d / %d" % [discovered_regions.size(), LANDMARK_DATA.size()])
    var knowledge_count := 0
    for flag in REQUIRED_KNOWLEDGE:
        if knowledge_flags.has(flag):
            knowledge_count += 1
    lines.append("调查：%d / %d    信标：%d / %d" % [knowledge_count, REQUIRED_KNOWLEDGE.size(), activated_beacons.size(), beacon_positions.size()])
    lines.append("异常：%s    电池：可选回收 +10    异常冰样：可选回收 +20" % ("已处理" if anomaly_resolved else "未处理"))
    lines.append("异常冰样会提前引来敌袭；携带不便时按 X 丢下，靠近后按 F 重新拾取")
    lines.append("热脉阀：%s    信号频段：%s" % ["已开启" if rift_valve_open else "未开启", "高频" if signal_mode == "high" else ("低频" if signal_mode == "low" else "中性")])
    lines.append("地图标记：%d / 12    H 热源 · C 线索 · V 清除最近" % map_markers.size())
    lines.append("回收价值：%d    样本：%d / %d" % [salvage_value, taken_samples.size(), sample_positions.size()])
    lines.append("探索时间：%.0f 秒    热脉周期：%.1f 秒" % [mission_elapsed, THERMAL_CYCLE])
    lines.append("")
    if journal_entries.is_empty():
        lines.append("暂时没有记录。先部署扫描器（Q），扫描器固定扫描附近区域；扫描结束后靠近设备按 F 回收。")
    else:
        for entry in journal_entries:
            lines.append("· " + entry)
    _journal_label.text = "\n".join(lines)

func _toggle_journal() -> void:
    if not game_started or _journal_panel == null:
        return
    _journal_visible = not _journal_visible
    _journal_panel.visible = _journal_visible
    if _journal_visible:
        _show_journal_page(false)
        _refresh_journal()

func _toggle_map() -> void:
    if not game_started or _journal_panel == null or _journal_map_view == null:
        return
    var map_is_open := _journal_visible and _journal_map_view.visible
    _journal_visible = not map_is_open
    _journal_panel.visible = _journal_visible
    if _journal_visible:
        _show_journal_page(true)
        _refresh_journal()
    else:
        _journal_map_view.visible = false

func _show_journal_page(show_map: bool) -> void:
    if _journal_log_view == null or _journal_map_view == null:
        return
    _journal_log_view.visible = not show_map
    _journal_map_view.visible = show_map
    if _journal_log_button != null:
        _journal_log_button.modulate = Color("#ffffff") if not show_map else Color("#7da0ad")
    if _journal_map_button != null:
        _journal_map_button.modulate = Color("#ffffff") if show_map else Color("#7da0ad")

func _request_local_action(action: String) -> void:
    handle_action(multiplayer.get_unique_id(), action)

func _known_heat_sources() -> Array:
    var sources: Array = [{"position": SAFEHOUSE, "label": "安全屋"}]
    for vent in FrostMapLayout.THERMAL_VENTS:
        sources.append({"position": Vector2(vent.get("position", Vector2.ZERO)), "label": "地热口"})
    for beacon_id in activated_beacons:
        var beacon := beacons.get(beacon_id) as Node3D
        if beacon != null:
            sources.append({"position": Vector2(beacon.global_position.x, beacon.global_position.z), "label": "信标热源"})
    if rift_valve_open:
        sources.append({"position": Vector2(132.0, -94.0), "label": "稳定裂谷热源"})
    if _field_interactions != null:
        sources.append_array(_field_interactions.heat_sources())
    return sources

func _clue_position(clue: Dictionary) -> Vector2:
    var kind := String(clue.get("kind", ""))
    var target_id := int(clue.get("target_id", 0))
    if kind == "beacon" and target_id > 0 and target_id <= beacon_positions.size():
        return Vector2(beacon_positions[target_id - 1])
    if kind == "crate" and target_id > 0 and target_id <= crate_positions.size():
        return Vector2(crate_positions[target_id - 1])
    if kind == "sample" and target_id > 0 and target_id <= sample_positions.size():
        return Vector2(sample_positions[target_id - 1])
    return Vector2(clue.get("position", Vector2.ZERO))

func _place_map_marker(peer_id: int, marker_kind: String) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return
    var player_point := Vector2(player.global_position.x, player.global_position.z)
    var marker_point := player_point
    var marker_label := "临时标记"
    if marker_kind == "heat":
        var nearest_distance := INF
        for source in _known_heat_sources():
            var source_point := Vector2(source.get("position", Vector2.ZERO))
            var distance := player_point.distance_to(source_point)
            if distance < nearest_distance:
                nearest_distance = distance
                marker_point = source_point
                marker_label = String(source.get("label", "热源"))
        if nearest_distance > HEAT_RADIUS * 2.4:
            marker_point = player_point
            marker_label = "临时热源"
    else:
        var nearest_distance := INF
        for clue in exploration_clues:
            var clue_id := int(clue.get("id", 0))
            if not discovered_clues.has(clue_id) and not scan_revealed_clues.has(clue_id):
                continue
            var clue_point := _clue_position(clue)
            var distance := player_point.distance_to(clue_point)
            if distance < nearest_distance:
                nearest_distance = distance
                marker_point = clue_point
                marker_label = String(clue.get("name", "已探索线索"))
        if nearest_distance == INF:
            show_feedback_rpc.rpc("附近还没有已探索线索，先按 Q 扫描或进入地标视野。", Color("#ffbd75"), 1.8)
            return
    map_markers.append({"id": next_marker_id, "kind": marker_kind, "position": marker_point, "label": marker_label})
    next_marker_id += 1
    while map_markers.size() > 12:
        map_markers.pop_front()
    _record_journal("地图标点", "%s：%s" % ["热源" if marker_kind == "heat" else "线索", marker_label])
    show_feedback_rpc.rpc("已标记地图：%s" % marker_label, Color("#ffd27e") if marker_kind == "heat" else Color("#ff9eb4"), 1.4)
    _broadcast_exploration_state()

func _clear_last_map_marker(peer_id: int) -> void:
    if map_markers.is_empty():
        show_feedback_rpc.rpc("地图上还没有手动标记。", Color("#ffbd75"), 1.3)
        return
    var removed: Dictionary = map_markers.pop_back()
    show_feedback_rpc.rpc("已清除标记：%s" % String(removed.get("label", "标记")), Color("#8fb4c4"), 1.2)
    _broadcast_exploration_state()

func is_journal_visible() -> bool:
    return _journal_visible

func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.metallic = metallic
    material.roughness = 0.72
    return material

func _show_feedback(text: String, color: Color = Color("#ffffff"), duration: float = 1.5) -> void:
    if _feedback_label == null:
        return
    _feedback_label.text = text
    _feedback_label.add_theme_color_override("font_color", color)
    _feedback_label.visible = true
    _feedback_timer = duration

func _update_feedback(delta: float) -> void:
    if _feedback_timer > 0.0:
        _feedback_timer -= delta
        if _feedback_timer <= 0.0:
            _feedback_label.visible = false

func _update_exploration_thought(delta: float) -> void:
    if _thought_label == null:
        return
    if _thought_timer > 0.0:
        _thought_timer -= delta
        if _thought_timer <= 0.0:
            _thought_label.visible = false
            if _story_timer <= 0.0:
                _subtitle_panel.visible = false
        return
    if _story_timer > 0.0:
        return
    var local := players.get(multiplayer.get_unique_id()) as SpacePlayer3D
    if local == null or local.downed:
        return
    var best_clue: Dictionary = {}
    var best_distance := CLUE_TRIGGER_RADIUS
    for clue in exploration_clues:
        var clue_id := int(clue.get("id", 0))
        if discovered_clues.has(clue_id):
            continue
        var kind := String(clue.get("kind", ""))
        var target_id := int(clue.get("target_id", 0))
        if kind == "beacon" and activated_beacons.has(target_id):
            continue
        if kind == "crate" and taken_crates.has(target_id):
            continue
        if kind == "sample" and taken_samples.has(target_id):
            continue
        # A beacon or crate never produces a thought just because the player
        # crossed its hidden trigger radius. The player must first scan it and
        # then walk up to the revealed physical trace.
        if kind != "landmark" and not scan_revealed_clues.has(clue_id):
            continue
        if kind != "landmark":
            var marker := clue_nodes.get(clue_id) as Node3D
            if marker == null or not marker.visible:
                continue
        var clue_position := Vector2(clue.get("position", Vector2.ZERO))
        var distance := _flat_distance(local.global_position, Vector3(clue_position.x, 0.0, clue_position.y))
        if distance <= best_distance:
            best_distance = distance
            best_clue = clue
    if best_clue.is_empty():
        return
    var kind := String(best_clue.get("kind", ""))
    var target_id := int(best_clue.get("target_id", 0))
    var target_position := Vector2.ZERO
    var thought := ""
    if kind == "beacon":
        target_position = Vector2(beacon_positions[target_id - 1])
        thought = "雪地有新鲜的拖痕，像是有人把设备拖向%s。" % _direction_hint(Vector2(local.global_position.x, local.global_position.z), target_position)
    elif kind == "crate":
        target_position = Vector2(crate_positions[target_id - 1])
        thought = "冰面有热融痕迹，%s 似乎有东西刚被搬过。" % _direction_hint(Vector2(local.global_position.x, local.global_position.z), target_position)
    elif kind == "sample":
        target_position = Vector2(sample_positions[target_id - 1])
        thought = "冰层下有紫色反光，%s 藏着一枚异常冰样。" % _direction_hint(Vector2(local.global_position.x, local.global_position.z), target_position)
    else:
        thought = String(best_clue.get("thought", "这里留下了不自然的痕迹。"))
        var region := String(best_clue.get("region", "未知区域"))
        var landmark_name := String(best_clue.get("name", "未知地标"))
        if not discovered_regions.has(region):
            discovered_regions.append(region)
            _record_journal(landmark_name + " · " + region, "远景地标已登记。靠近它并按 E 调查，才能读懂留下的信号。")
    discovered_clues.append(int(best_clue.get("id", 0)))
    if kind == "beacon":
        _record_journal("现场痕迹", "拖痕指向一座尚未修复的气象信标，方向：%s。" % _direction_hint(Vector2(local.global_position.x, local.global_position.z), target_position))
    elif kind == "crate":
        _record_journal("现场痕迹", "热融痕迹指向一枚热能电池，附近可能有人先来过。")
    elif kind == "sample":
        _record_journal("现场痕迹", "冰层下有不自然的紫色反光，扫描回波指向一枚异常冰样。")
    if not is_host:
        request_clue_discovery.rpc_id(1, int(best_clue.get("id", 0)))
    _thought_label.text = "“%s”" % thought
    _thought_label.visible = true
    _subtitle_panel.visible = true
    _thought_timer = THOUGHT_DURATION

func _direction_hint(from: Vector2, to: Vector2) -> String:
    var delta := to - from
    var horizontal := ""
    var vertical := ""
    if absf(delta.x) > 1.0:
        horizontal = "东" if delta.x > 0.0 else "西"
    if absf(delta.y) > 1.0:
        vertical = "南" if delta.y > 0.0 else "北"
    if horizontal.is_empty() and vertical.is_empty():
        return "前方"
    return vertical + horizontal

@rpc("authority", "call_local", "reliable")
func show_feedback_rpc(text: String, color: Color, duration: float) -> void:
    _show_feedback(text, color, duration)

func _spawn_particle_burst(position: Vector3, color: Color, count: int = 12) -> void:
    if not is_instance_valid(_world_root):
        return
    for i in count:
        var particle := MeshInstance3D.new()
        var mesh := SphereMesh.new()
        mesh.radius = 0.05
        mesh.height = 0.10
        particle.mesh = mesh
        particle.material_override = _glow_material(color, 1.2)
        _world_root.add_child(particle)
        particle.global_position = position + Vector3(randf_range(-0.15, 0.15), randf_range(0.05, 0.2), randf_range(-0.15, 0.15))
        var direction := Vector3(randf_range(-1, 1), randf_range(0.5, 1.2), randf_range(-1, 1)).normalized()
        var speed := randf_range(0.8, 1.8)
        var lifetime := randf_range(0.3, 0.5)
        var tween := create_tween()
        tween.set_parallel(true)
        tween.tween_property(particle, "global_position", particle.global_position + direction * speed, lifetime)
        tween.tween_property(particle, "scale", Vector3.ZERO, lifetime)
        tween.finished.connect(func(): particle.queue_free())

@rpc("authority", "call_local", "reliable")
func camera_shake_rpc(peer_id: int, strength: float = 0.08, duration: float = 0.12) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player != null:
        player.trigger_camera_shake(strength, duration)

@rpc("authority", "call_local", "reliable")
func floating_feedback_rpc(position: Vector3, text: String, color: Color) -> void:
    _spawn_floating_feedback(position, text, color)

func _spawn_floating_feedback(position: Vector3, text: String, color: Color) -> void:
    if not is_instance_valid(_world_root):
        return
    var label := Label3D.new()
    label.text = text
    label.position = position
    label.font_size = 42
    label.pixel_size = 0.010
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = color
    label.outline_size = 9
    label.outline_modulate = Color("#061521")
    label.shaded = false
    _world_root.add_child(label)
    var lifetime := 0.9
    var end_color := Color(color.r, color.g, color.b, 0.0)
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(label, "position:y", position.y + 1.0, lifetime)
    tween.tween_property(label, "modulate", end_color, lifetime)
    tween.finished.connect(func(): label.queue_free())

@rpc("authority", "call_local", "reliable")
func show_attack_visual(peer_id: int) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player != null:
        player.show_attack_animation()

@rpc("authority", "call_local", "reliable")
func set_revive_visual(peer_id: int, enabled: bool) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player != null:
        player.show_rescue_animation(enabled)
