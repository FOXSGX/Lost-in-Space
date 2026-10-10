extends Node3D
class_name Main3D

const PORT := 24567
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/player_3d.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy_3d.tscn")
const OBSTACLE_SCENE := preload("res://scenes/frost_obstacle_3d.tscn")
const WAVE_INTERVAL := 15.0
const SCAN_DURATION := 4.0
const SCAN_COOLDOWN := 6.0
const SCAN_STARTUP := 0.8
const MINIMUM_BATTERIES := 3
const REVIVE_TIME := 3.0
const REVIVE_RANGE := 1.8
const REVIVE_OXYGEN := 40.0
const STORM_INTERVAL := 28.0
const STORM_DURATION := 10.0
const CLEAR_SCAN_RADIUS := 9.0
const STORM_SCAN_RADIUS := 6.5
const MISSION_RETURN_DELAY := 2.5
const HEAT_RADIUS := 3.0
const OXYGEN_DRAIN_BASE := 1.0
const OXYGEN_DRAIN_COLD := 3.0
const OXYGEN_RECOVER := 12.0
const WARMTH_DRAIN := 0.05
const WARMTH_RECOVER := 0.4
const EXTRACTION := Vector2(15.0, 8.0)
const PLAYER_COLORS := [Color("#55dfff"), Color("#ffd25a"), Color("#ff6d8a"), Color("#a88cff")]
const BEACON_POSITIONS := [Vector2(-11.0, -4.0), Vector2(1.0, 6.0), Vector2(12.0, -5.0)]
const CRATE_POSITIONS := [Vector2(-8.0, 4.0), Vector2(-2.0, -7.0), Vector2(7.0, 5.0), Vector2(11.0, 1.0)]
const OBSTACLE_LAYOUT := [
    [Vector2(-12.0, -1.0), Vector2(2.4, 1.5), 0, 1.3],
    [Vector2(-8.0, -1.0), Vector2(3.6, 1.15), 1, 1.1],
    [Vector2(-3.0, -3.5), Vector2(2.0, 1.2), 0, 1.5],
    [Vector2(3.5, -5.0), Vector2(3.3, 1.1), 1, 1.0],
    [Vector2(8.0, -2.0), Vector2(2.4, 1.5), 3, 1.2],
    [Vector2(-13.0, 7.0), Vector2(2.2, 1.8), 2, 0.75],
    [Vector2(-5.0, 7.5), Vector2(3.0, 1.3), 1, 1.0],
    [Vector2(3.0, 3.0), Vector2(2.1, 1.7), 0, 1.4],
    [Vector2(9.0, 7.0), Vector2(2.8, 1.4), 3, 1.1],
]

var beacon_positions: Array = []
var crate_positions: Array = []

var is_host := false
var game_started := false
var connected_ids: Array[int] = []
var players: Dictionary = {}
var enemies: Dictionary = {}
var obstacles: Array[Node] = []
var beacons: Dictionary = {}
var crates: Dictionary = {}
var activated_beacons: Array[int] = []
var taken_crates: Array[int] = []
var deposited_resources := 0
var enemy_wave_index := 0
var enemy_wave_timer := 0.0
var next_enemy_id := 1
var extraction_enabled := false
var extraction_progress := 0.0
var mission_completed := false
var mission_failed := false
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
var scan_active := false
var scan_visual: MeshInstance3D

var _world_root: Node3D
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
var _home_group: Control
var _room_group: Control
var _feedback_label: Label
var _feedback_timer := 0.0
var _route_group: Control
var _room_status: Label
var _route_status: Label
var _land_button: Button
var _screen_view := "home"

func _ready() -> void:
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    _build_menu_world()
    _build_ui()

func _process(delta: float) -> void:
    if not game_started:
        _menu_time += delta
        _animate_menu_world()
        return
    _update_scan_visual(delta)
    _update_storm_visual(delta)
    _update_vision_overlay()
    _update_hud()
    _update_interaction_hint()
    _update_feedback(delta)
    if not is_host:
        return
    if mission_completed or mission_failed:
        mission_return_timer += delta
        if mission_return_timer >= MISSION_RETURN_DELAY:
            return_to_ship.rpc("任务完成，已返回飞船准备区。" if mission_completed else "登陆失败，已返回飞船准备区。")
        return
    _tick_storm(delta)
    enemy_wave_timer += delta
    while enemy_wave_timer >= WAVE_INTERVAL and not _objectives_ready():
        enemy_wave_timer -= WAVE_INTERVAL
        _spawn_enemy_wave()
    for enemy in enemies.values():
        var result := (enemy as SpaceEnemy3D).server_tick(delta, players)
        if result.get("sync", false):
            _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot())
    _tick_survival(delta)
    _tick_revive(delta)
    _tick_extraction(delta)
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
    _panel(_game_layer, Vector2(24, 22), Vector2(820, 112), Color(0.025, 0.08, 0.13, 0.92), Color("#2e6a83"), 14)
    var top_accent := ColorRect.new()
    top_accent.color = Color("#62e8dc")
    top_accent.position = Vector2(24, 22)
    top_accent.size = Vector2(5, 112)
    _game_layer.add_child(top_accent)
    var game_title := Label.new()
    game_title.text = "迷失太空 · 霜烬星 3D"
    game_title.position = Vector2(48, 30)
    game_title.add_theme_font_size_override("font_size", 26)
    game_title.add_theme_color_override("font_color", Color("#f2fbff"))
    _game_layer.add_child(game_title)
    _hint_label = Label.new()
    _hint_label.text = "WASD移动 · 空格攻击 · Q扫描 · E修复 · F拾取 · G投送 · R救援"
    _hint_label.position = Vector2(50, 68)
    _hint_label.size = Vector2(760, 60)
    _hint_label.add_theme_font_size_override("font_size", 15)
    _hint_label.add_theme_color_override("font_color", Color("#c2e8f5"))
    _hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _game_layer.add_child(_hint_label)
    _panel(_game_layer, Vector2(872, 22), Vector2(382, 112), Color(0.025, 0.08, 0.13, 0.92), Color("#2e6a83"), 14)
    _progress_label = Label.new()
    _progress_label.position = Vector2(890, 32)
    _progress_label.size = Vector2(350, 96)
    _progress_label.add_theme_font_size_override("font_size", 16)
    _progress_label.add_theme_color_override("font_color", Color("#8be28b"))
    _progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _game_layer.add_child(_progress_label)
    _game_status_label = Label.new()
    _game_status_label.position = Vector2(872, 145)
    _game_status_label.size = Vector2(382, 50)
    _game_status_label.add_theme_font_size_override("font_size", 13)
    _game_status_label.add_theme_color_override("font_color", Color("#9ebdca"))
    _game_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _game_layer.add_child(_game_status_label)
    _vitals_label = Label.new()
    _panel(_game_layer, Vector2(24, 642), Vector2(600, 52), Color(0.025, 0.08, 0.13, 0.88), Color("#254d62"), 12)
    _vitals_label.position = Vector2(48, 653)
    _vitals_label.size = Vector2(560, 40)
    _vitals_label.add_theme_font_size_override("font_size", 17)
    _vitals_label.add_theme_color_override("font_color", Color("#75dff5"))
    _game_layer.add_child(_vitals_label)
    var interaction_panel := _panel(_game_layer, Vector2(290, 545), Vector2(700, 76), Color(0.025, 0.08, 0.13, 0.96), Color("#59c8d1"), 12)
    _interaction_label = Label.new()
    _interaction_label.position = Vector2(18, 10)
    _interaction_label.size = Vector2(664, 60)
    _interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _interaction_label.add_theme_font_size_override("font_size", 18)
    interaction_panel.add_child(_interaction_label)
    var guide := Label.new()
    guide.position = Vector2(872, 205)
    guide.size = Vector2(380, 120)
    guide.text = "任务：修复 3 座通讯塔 → 投送至少 3 枚电池\n清除敌人 → 全队集合撤离\n\n金色天线 = E 修复    绿色电池 = F 拾取\n信标前哨 = 自动补氧回温    蓝色平台 = G 投送"
    guide.add_theme_font_size_override("font_size", 14)
    guide.add_theme_color_override("font_color", Color("#d4e8f1"))
    _game_layer.add_child(guide)
    _feedback_label = Label.new()
    _feedback_label.position = Vector2(480, 420)
    _feedback_label.size = Vector2(320, 60)
    _feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _feedback_label.add_theme_font_size_override("font_size", 20)
    _feedback_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
    _feedback_label.add_theme_constant_override("outline_size", 4)
    _feedback_label.visible = false
    _game_layer.add_child(_feedback_label)

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

func _ui_label(parent: Control, text: String, position: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
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
    _ui_label(_home_group, "驾驶远征舰穿过未知航域，在霜烬星搜集热能电池、修复气象信标，并带着全队安全返航。", Vector2(91, 194), Vector2(420, 82), 17, Color("#a7c4d3"))
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
    _ui_label(planet_card, "FROST ASH\n气象信标 · 热能电池 · 暴风雪撤离", Vector2(22, 100), Vector2(420, 52), 15, Color("#9ebdca"))
    _land_button = _ui_button(planet_card, "确认航程  →", Vector2(334, 116), Vector2(176, 48), _start_planet, true)
    _route_status = _ui_label(_route_group, "", Vector2(91, 424), Vector2(520, 24), 14, Color("#8fb4c4"))
    _ui_label(_route_group, "02  /  尚未开放     电磁星球", Vector2(91, 454), Vector2(500, 28), 16, Color("#668392"))
    _ui_button(_route_group, "← 返回飞船准备区", Vector2(91, 516), Vector2(240, 46), _show_room)

func _set_screen(view: String) -> void:
    _screen_view = view
    _home_group.visible = view == "home"
    _room_group.visible = view == "room"
    _route_group.visible = view == "route"

func _show_home() -> void:
    _set_screen("home")

func _show_room() -> void:
    _set_screen("room")
    if _room_status != null:
        _room_status.text = "主机已创建，准备选择航线。"

func _show_route() -> void:
    _set_screen("route")
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
    var result := peer.create_server(PORT, MAX_PLAYERS)
    if result != OK:
        _set_status("创建主机失败：%s" % error_string(result))
        return
    multiplayer.multiplayer_peer = peer
    is_host = true
    connected_ids = [1]
    _show_room()
    _set_status("主机已创建，已进入飞船准备区。")
    if DisplayServer.get_name() == "headless":
        _start_planet()

func _join_host() -> void:
    var peer := ENetMultiplayerPeer.new()
    var result := peer.create_client(_address_edit.text.strip_edges(), PORT)
    if result != OK:
        _set_status("加入主机失败：%s" % error_string(result))
        return
    multiplayer.multiplayer_peer = peer
    is_host = false
    _set_status("正在连接主机……")

func _on_connected_to_server() -> void:
    connected_ids = [1, multiplayer.get_unique_id()]
    _show_room()
    if _room_status != null:
        _room_status.text = "已连接归航号，等待主机选择航线。"
    _set_status("已连接主机，等待主机选择航线……")

func _on_connection_failed() -> void:
    _set_status("连接失败，请检查主机 IP 和端口。")

func _on_peer_connected(peer_id: int) -> void:
    if not is_host:
        return
    if not connected_ids.has(peer_id):
        connected_ids.append(peer_id)
    spawn_player_for_peer.rpc(peer_id)
    sync_full_state.rpc_id(peer_id, _world_snapshot())
    _set_status("玩家 %d 已加入 3D 霜烬星。" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
    connected_ids.erase(peer_id)
    if players.has(peer_id):
        players[peer_id].queue_free()
        players.erase(peer_id)

func _start_planet() -> void:
    if game_started:
        return
    game_started = true
    mission_completed = false
    mission_failed = false
    mission_return_timer = 0.0
    extraction_enabled = false
    extraction_progress = 0.0
    storm_active = false
    storm_elapsed = 0.0
    storm_remaining = 0.0
    reviving.clear()
    revive_progress.clear()
    if is_host:
        _prepare_layout()
    elif beacon_positions.is_empty():
        beacon_positions.assign(BEACON_POSITIONS)
        crate_positions.assign(CRATE_POSITIONS)
    if _menu_world != null:
        _menu_world.visible = false
    _build_world()
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
    if is_host:
        enemy_spawned = true
        _spawn_enemy_wave(true)
        sync_full_state.rpc(_world_snapshot())

func _prepare_layout() -> void:
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    beacon_positions.clear()
    crate_positions.clear()
    for base in BEACON_POSITIONS:
        beacon_positions.append(Vector2(base.x + rng.randf_range(-1.2, 1.2), base.y + rng.randf_range(-1.0, 1.0)))
    for base in CRATE_POSITIONS:
        crate_positions.append(Vector2(base.x + rng.randf_range(-1.5, 1.5), base.y + rng.randf_range(-1.2, 1.2)))

func _build_world() -> void:
    _world_root = Node3D.new()
    _world_root.name = "FrostAsh3DWorld"
    add_child(_world_root)
    _object_tags.clear()
    _attack_ready_at.clear()
    _build_environment()
    _build_ground()
    for raw in OBSTACLE_LAYOUT:
        var obstacle := OBSTACLE_SCENE.instantiate() as FrostObstacle3D
        _world_root.add_child(obstacle)
        obstacle.setup(raw[0], raw[1], float(raw[3]), int(raw[2]))
        obstacles.append(obstacle)
    _build_zone_visuals()
    _build_beacons()
    _build_crates()
    _build_extraction()
    _build_scan_visual()

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
    sun.directional_shadow_max_distance = 45.0
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

func _build_ground() -> void:
    var ground_body := StaticBody3D.new()
    ground_body.name = "FrozenGround"
    ground_body.collision_layer = 2
    ground_body.collision_mask = 1
    _world_root.add_child(ground_body)
    var ground := MeshInstance3D.new()
    var mesh := PlaneMesh.new()
    mesh.size = Vector2(40.0, 26.0)
    ground.mesh = mesh
    ground.material_override = _material(Color("#1a3f52"), 0.95)
    ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    ground_body.add_child(ground)
    for lane_data in [[Vector3(-8.0, 0.018, -1.0), Vector3(0.18, 0.028, 20.0), Color("#226a7d")], [Vector3(8.0, 0.02, 4.0), Vector3(0.14, 0.030, 16.0), Color("#255a6e")], [Vector3(0.0, 0.022, 9.0), Vector3(26.0, 0.030, 0.14), Color("#226474")]]:
        var lane := MeshInstance3D.new()
        var lane_mesh := BoxMesh.new()
        lane_mesh.size = lane_data[1]
        lane.mesh = lane_mesh
        lane.position = lane_data[0]
        lane.material_override = _material(lane_data[2], 0.25)
        ground_body.add_child(lane)
    for patch_data in [[Vector3(-16.0, 0.038, 8.5), 2.4], [Vector3(13.0, 0.038, -7.5), 1.9], [Vector3(1.5, 0.038, -1.0), 1.5]]:
        var ice_patch := MeshInstance3D.new()
        var patch_mesh := CylinderMesh.new()
        patch_mesh.top_radius = float(patch_data[1])
        patch_mesh.bottom_radius = float(patch_data[1]) * 1.18
        patch_mesh.height = 0.07
        patch_mesh.radial_segments = 12
        ice_patch.mesh = patch_mesh
        ice_patch.position = patch_data[0]
        ice_patch.material_override = _material(Color("#5aa5b8"), 0.18)
        ground_body.add_child(ice_patch)
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(40.0, 0.2, 26.0)
    shape.shape = box
    shape.position.y = -0.1
    ground_body.add_child(shape)
    for edge in [[Vector3(0, 0.8, -13), Vector3(40, 1.6, 0.4)], [Vector3(0, 0.8, 13), Vector3(40, 1.6, 0.4)], [Vector3(-20, 0.8, 0), Vector3(0.4, 1.6, 26)], [Vector3(20, 0.8, 0), Vector3(0.4, 1.6, 26)]]:
        _add_boundary(edge[0], edge[1])

func _add_boundary(center: Vector3, size: Vector3) -> void:
    var body := StaticBody3D.new()
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
    safe_mesh.size = Vector3(6.0, 0.045, 5.0)
    safehouse.mesh = safe_mesh
    safehouse.position = Vector3(-12.0, 0.035, -7.0)
    safehouse.material_override = _zone_material(Color(0.98, 0.65, 0.20, 0.28), Color("#ffb661"))
    _world_root.add_child(safehouse)
    var heat_core := MeshInstance3D.new()
    var core_mesh := SphereMesh.new()
    core_mesh.radius = 0.68
    core_mesh.height = 1.36
    heat_core.mesh = core_mesh
    heat_core.position = Vector3(-12.0, 0.86, -7.0)
    heat_core.material_override = _glow_material(Color("#ffbd61"), 2.2)
    _world_root.add_child(heat_core)
    var heat_light := OmniLight3D.new()
    heat_light.position = Vector3(-12.0, 1.2, -7.0)
    heat_light.light_color = Color("#ffb65e")
    heat_light.light_energy = 4.5
    heat_light.omni_range = 7.0
    _world_root.add_child(heat_light)
    var safe_label := Label3D.new()
    safe_label.text = "【安全屋/热源】\n自动回温·补氧"
    safe_label.position = Vector3(-12.0, 2.2, -7.0)
    safe_label.font_size = 56
    safe_label.pixel_size = 0.009
    safe_label.modulate = Color("#ffdb91")
    safe_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    safe_label.outline_size = 14
    safe_label.outline_modulate = Color("#2d1a06")
    safe_label.shaded = false
    _world_root.add_child(safe_label)
    var danger := MeshInstance3D.new()
    var danger_mesh := BoxMesh.new()
    danger_mesh.size = Vector3(7.0, 0.035, 7.0)
    danger.mesh = danger_mesh
    danger.position = Vector3(9.0, 0.03, 0.0)
    danger.material_override = _zone_material(Color(0.88, 0.20, 0.26, 0.18), Color("#ff6d78"))
    _world_root.add_child(danger)
    var danger_label := Label3D.new()
    danger_label.text = "【危险区/暴风雪前线】"
    danger_label.position = Vector3(9.0, 0.34, -3.8)
    danger_label.font_size = 48
    danger_label.pixel_size = 0.010
    danger_label.modulate = Color("#ff9aa0")
    danger_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    danger_label.outline_size = 12
    danger_label.outline_modulate = Color("#3d0a0f")
    danger_label.shaded = false
    _world_root.add_child(danger_label)

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

func _spawn_position(peer_id: int) -> Vector3:
    var slots := [Vector3(-14.0, 0.0, -7.5), Vector3(-11.0, 0.0, -7.5), Vector3(-8.0, 0.0, -7.5), Vector3(-5.0, 0.0, -7.5)]
    return slots[(peer_id - 1) % slots.size()]

@rpc("authority", "call_local", "reliable")
func spawn_player_for_peer(peer_id: int) -> void:
    if players.has(peer_id):
        return
    var player := PLAYER_SCENE.instantiate() as SpacePlayer3D
    player.setup(peer_id, PLAYER_COLORS[(peer_id - 1) % PLAYER_COLORS.size()])
    player.position = _spawn_position(peer_id)
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
    var count := 3 + connected_ids.size()
    for index in count:
        var enemy := ENEMY_SCENE.instantiate() as SpaceEnemy3D
        enemy.setup(next_enemy_id, connected_ids.size())
        var angle := TAU * float(index) / float(count)
        enemy.position = Vector3(9.5 + cos(angle) * 3.0, 0.0, -2.0 + sin(angle) * 3.0)
        add_child(enemy)
        enemies[next_enemy_id] = enemy
        next_enemy_id += 1
    _set_status("第 %d 波敌人已进入霜烬星，15 秒后继续增援。" % enemy_wave_index)
    _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot())

func _tick_storm(delta: float) -> void:
    storm_elapsed += delta
    if storm_active:
        storm_remaining = maxf(storm_remaining - delta, 0.0)
        if storm_remaining <= 0.0:
            storm_active = false
            storm_elapsed = 0.0
            sync_storm_state.rpc(false, 0.0)
            _set_status("暴风雪减弱，能见度与扫描范围恢复。")
        return
    if storm_elapsed >= STORM_INTERVAL:
        storm_active = true
        storm_remaining = STORM_DURATION
        sync_storm_state.rpc(true, storm_remaining)
        _set_status("暴风雪来袭：能见度下降，扫描范围缩小。")

func _update_storm_visual(_delta: float) -> void:
    if _storm_overlay == null:
        return
    _storm_overlay.visible = game_started and storm_active
    if storm_active:
        _storm_overlay.color = Color(0.02, 0.10, 0.18, 0.30)

func _update_vision_overlay() -> void:
    if _vision_overlay == null:
        return
    if not game_started:
        _vision_overlay.visible = false
        return
    var local := players.get(multiplayer.get_unique_id()) as SpacePlayer3D
    if local == null or local._camera == null:
        _vision_overlay.visible = false
        return
    _vision_overlay.visible = true
    var material := _vision_overlay.material as ShaderMaterial
    var viewport_size := Vector2(get_viewport().get_visible_rect().size)
    var viewer_screen := local._camera.unproject_position(local.global_position) / viewport_size
    var scan_screen := local._camera.unproject_position(Vector3(scan_origin.x, 0.0, scan_origin.z)) / viewport_size
    var max_radius := STORM_SCAN_RADIUS if storm_active else CLEAR_SCAN_RADIUS
    material.set_shader_parameter("viewer", viewer_screen)
    material.set_shader_parameter("scan_origin", scan_screen)
    material.set_shader_parameter("view_radius", 0.25)
    material.set_shader_parameter("scan_radius", clampf(max_radius / 22.0, 0.12, 0.42))
    material.set_shader_parameter("scan_active", 1.0 if scan_remaining > 0.0 else 0.0)

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
    scan_peer_id = peer_id
    scan_origin = player.global_position
    scan_remaining = SCAN_DURATION
    scan_active = true
    scan_cooldown = SCAN_COOLDOWN
    sync_scan_state.rpc(peer_id, scan_origin, SCAN_DURATION, SCAN_COOLDOWN)
    show_feedback_rpc.rpc("扫描脉冲启动，可继续移动", Color("#5ac8ff"), 1.2)

@rpc("any_peer", "reliable")
func request_scan(peer_id: int) -> void:
    if is_host:
        start_scan_for_peer(peer_id)

@rpc("authority", "call_local", "reliable")
func sync_scan_state(peer_id: int, origin: Vector3, duration: float, cooldown: float) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player != null:
        player.begin_scan(duration, cooldown, origin)
    scan_peer_id = peer_id
    scan_origin = origin
    scan_remaining = duration
    scan_cooldown = cooldown
    scan_active = true

func _update_scan_visual(delta: float) -> void:
    scan_remaining = maxf(scan_remaining - delta, 0.0)
    scan_cooldown = maxf(scan_cooldown - delta, 0.0)
    if scan_visual == null:
        return
    if scan_remaining <= 0.0:
        scan_active = false
        scan_visual.visible = false
        return
    scan_visual.visible = true
    scan_visual.global_position = Vector3(scan_origin.x, 0.09, scan_origin.z)
    var progress := clampf(1.0 - scan_remaining / SCAN_DURATION, 0.0, 1.0)
    var max_radius := STORM_SCAN_RADIUS if storm_active else CLEAR_SCAN_RADIUS
    var radius := lerpf(0.4, max_radius, progress)
    scan_visual.scale = Vector3(radius, 1.0, radius)

func handle_action(peer_id: int, action: String) -> void:
    if not is_host:
        request_action.rpc_id(1, peer_id, action)
        return
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return
    if action == "repair":
        for id in beacons:
            if activated_beacons.has(id):
                continue
            if _flat_distance(player.global_position, beacons[id].global_position) <= 2.0:
                activated_beacons.append(id)
                _set_status("玩家 %d 已修复气象信标 %d。" % [peer_id, id])
                _spawn_particle_burst(beacons[id].global_position + Vector3(0, 1.5, 0), Color("#ffd966"), 8)
                show_feedback_rpc.rpc("信标修复", Color("#ffd966"), 1.0)
                _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot())
                return
    elif action == "pickup":
        for id in crates:
            if taken_crates.has(id) or player.carrying > 0:
                continue
            if _flat_distance(player.global_position, crates[id].global_position) <= 1.8:
                taken_crates.append(id)
                player.carrying = 1
                crates[id].visible = false
                _set_status("玩家 %d 拾取了热能电池。" % peer_id)
                _spawn_particle_burst(crates[id].global_position + Vector3(0, 0.8, 0), Color("#6ee7b7"), 6)
                show_feedback_rpc.rpc("电池 +1", Color("#6ee7b7"), 0.8)
                _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot())
                return
    elif action == "deposit":
        if player.carrying > 0 and _flat_distance(player.global_position, Vector3(EXTRACTION.x, 0, EXTRACTION.y)) <= 2.4:
            player.carrying = 0
            deposited_resources += 1
            _set_status("已投送热能电池 %d / %d。" % [deposited_resources, crates.size()])
            _spawn_particle_burst(Vector3(EXTRACTION.x, 1.2, EXTRACTION.y), Color("#5ac8ff"), 6)
            show_feedback_rpc.rpc("投送 %d/%d" % [deposited_resources, crates.size()], Color("#5ac8ff"), 1.0)
            _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot())
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
    _sync_state.rpc(_enemy_snapshot(), enemy_wave_index, enemy_wave_timer, activated_beacons, taken_crates, deposited_resources, _vitals_snapshot())

@rpc("authority", "call_local", "reliable")
func attack_feedback(peer_id: int, target: Vector3, hit: bool) -> void:
    var player := players.get(peer_id) as SpacePlayer3D
    if player == null:
        return
    _spawn_attack_effect(player.global_position, target)
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
    show_feedback_rpc.rpc("受伤 -%d HP" % amount, Color("#ff6b6b"), 0.8)
    if player.health <= 0:
        player.downed = true
        player.velocity = Vector3.ZERO
        _set_status("玩家 %d 倒地，等待队友靠近按 R 救援。" % peer_id)
        _spawn_particle_burst(player.global_position + Vector3(0, 1.0, 0), Color("#ff3333"), 15)
        show_feedback_rpc.rpc("倒地", Color("#ff3333"), 2.0)
        _check_all_downed()

func _tick_survival(delta: float) -> void:
    for player in players.values():
        var p := player as SpacePlayer3D
        if p == null or p.downed:
            continue
        var near_heat := _flat_distance(p.global_position, Vector3(-12.0, 0.0, -7.0)) <= HEAT_RADIUS
        for beacon_id in beacons:
            var beacon := beacons[beacon_id] as Node3D
            if activated_beacons.has(int(beacon_id)) and beacon != null and _flat_distance(p.global_position, beacon.global_position) <= HEAT_RADIUS:
                near_heat = true
                break
        if near_heat:
            p.warmth = minf(p.warmth + WARMTH_RECOVER * delta, 1.0)
            p.oxygen = minf(p.oxygen + OXYGEN_RECOVER * delta, 100.0)
        else:
            p.warmth = maxf(p.warmth - WARMTH_DRAIN * delta, 0.0)
            p.oxygen = maxf(p.oxygen - delta * (OXYGEN_DRAIN_BASE + (1.0 - p.warmth) * OXYGEN_DRAIN_COLD), 0.0)
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
    _set_status("全员倒地，本次登陆失败，正在紧急返航。")

func _tick_extraction(delta: float) -> void:
    if not _objectives_ready() or not enemies.is_empty():
        extraction_enabled = false
        extraction_progress = 0.0
        return
    if not extraction_enabled:
        _set_status("目标完成且区域已清场，撤离点开放；全队进入后保持 3 秒。")
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
        _set_status("任务完成：3D 霜烬星撤离成功。")

@rpc("authority", "call_local", "reliable")
func return_to_ship(reason: String) -> void:
    game_started = false
    mission_completed = false
    mission_failed = false
    extraction_enabled = false
    extraction_progress = 0.0
    enemy_spawned = false
    enemy_wave_index = 0
    enemy_wave_timer = 0.0
    mission_return_timer = 0.0
    storm_active = false
    storm_elapsed = 0.0
    storm_remaining = 0.0
    reviving.clear()
    revive_progress.clear()
    if _world_root != null:
        _world_root.queue_free()
        _world_root = null
    for player in players.values():
        (player as Node).queue_free()
    players.clear()
    enemies.clear()
    obstacles.clear()
    beacons.clear()
    crates.clear()
    activated_beacons.clear()
    taken_crates.clear()
    deposited_resources = 0
    beacon_positions.clear()
    crate_positions.clear()
    scan_visual = null
    if _menu_world != null:
        _menu_world.visible = true
    if _game_layer != null:
        _game_layer.visible = false
    if _menu_layer != null:
        _menu_layer.visible = true
    _show_room()
    if _room_status != null:
        _room_status.text = reason

func _objectives_ready() -> bool:
    return activated_beacons.size() >= beacon_positions.size() and deposited_resources >= MINIMUM_BATTERIES

func _flat_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _enemy_snapshot() -> Array:
    var snapshot: Array = []
    for enemy in enemies.values():
        var e := enemy as SpaceEnemy3D
        snapshot.append([e.enemy_id, e.global_position, e.health])
    return snapshot

func _world_snapshot() -> Dictionary:
    return {"wave": enemy_wave_index, "timer": enemy_wave_timer, "enemies": _enemy_snapshot(), "beacons": activated_beacons, "crates": taken_crates, "deposited": deposited_resources, "vitals": _vitals_snapshot(), "beacon_positions": beacon_positions, "crate_positions": crate_positions}

func _vitals_snapshot() -> Array:
    var snapshot: Array = []
    for id in players:
        var p := players[id] as SpacePlayer3D
        if p != null:
            snapshot.append([id, p.health, p.oxygen, p.warmth, p.carrying, p.downed])
    return snapshot

@rpc("authority", "call_local", "unreliable")
func sync_vitals(snapshot: Array) -> void:
    for entry in snapshot:
        var p := players.get(int(entry[0])) as SpacePlayer3D
        if p == null:
            continue
        p.health = int(entry[1])
        p.oxygen = float(entry[2])
        p.warmth = float(entry[3])
        p.carrying = int(entry[4])
        p.downed = bool(entry[5])

@rpc("authority", "call_local", "reliable")
func sync_full_state(snapshot: Dictionary) -> void:
    if not game_started:
        _start_planet()
    enemy_wave_index = int(snapshot.get("wave", 0))
    enemy_wave_timer = float(snapshot.get("timer", 0.0))
    activated_beacons.assign(snapshot.get("beacons", []))
    taken_crates.assign(snapshot.get("crates", []))
    deposited_resources = int(snapshot.get("deposited", 0))
    _apply_layout_snapshot(snapshot.get("beacon_positions", []), snapshot.get("crate_positions", []))
    sync_vitals(snapshot.get("vitals", []))
    _apply_objective_visuals()
    _apply_enemy_snapshot(snapshot.get("enemies", []))

@rpc("authority", "call_local", "reliable")
func _sync_state(enemy_state: Array, wave: int, timer: float, beacon_state: Array, crate_state: Array, deposited: int, vital_state: Array = []) -> void:
    enemy_wave_index = wave
    enemy_wave_timer = timer
    activated_beacons.assign(beacon_state)
    taken_crates.assign(crate_state)
    deposited_resources = deposited
    sync_vitals(vital_state)
    _apply_objective_visuals()
    _apply_enemy_snapshot(enemy_state)

func _apply_objective_visuals() -> void:
    for id in crates:
        crates[id].visible = not taken_crates.has(id)
    for id in beacons:
        var beacon := beacons[id] as Node3D
        if beacon == null:
            continue
        var light := beacon.get_node_or_null("OmniLight3D") as OmniLight3D
        if light != null:
            light.light_color = Color("#8ff1a0") if activated_beacons.has(id) else Color("#ffc86b")
            light.light_energy = 3.2 if activated_beacons.has(id) else 2.0

func _apply_layout_snapshot(next_beacons: Array, next_crates: Array) -> void:
    if not next_beacons.is_empty():
        beacon_positions.assign(next_beacons)
    if not next_crates.is_empty():
        crate_positions.assign(next_crates)
    for index in beacon_positions.size():
        var beacon := beacons.get(index + 1) as Node3D
        if beacon != null:
            beacon.position = Vector3(beacon_positions[index].x, 0.0, beacon_positions[index].y)
    for index in crate_positions.size():
        var crate := crates.get(index + 1) as Node3D
        if crate != null:
            crate.position = Vector3(crate_positions[index].x, 0.3, crate_positions[index].y)

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

func _update_hud() -> void:
    if not game_started:
        return
    var wave_status := "✓ 撤离开放" if extraction_enabled else "⏱ 增援 %.1fs" % maxf(WAVE_INTERVAL - enemy_wave_timer, 0.0)
    var storm_status := " · 🌨 暴风雪 %.1fs" % storm_remaining if storm_active else ""
    _progress_label.text = "信标 %d/3 · 电池 %d/4 · 投送 %d/%d（可选多收集）\n第 %d 波 · %s%s" % [activated_beacons.size(), taken_crates.size(), deposited_resources, MINIMUM_BATTERIES, enemy_wave_index, wave_status, storm_status]
    var local := players.get(multiplayer.get_unique_id()) as SpacePlayer3D
    if local != null:
        var health_bar := "❤".repeat(local.health) + "♡".repeat(5 - local.health)
        _vitals_label.text = "%s  氧气 %d%%  体温 %d%%  携带 %d" % [health_bar, int(local.oxygen), int(local.warmth * 100.0), local.carrying]
    if scan_remaining > 0.0:
        _hint_label.text = "【扫描脉冲】范围 %.1fm · 可移动" % [STORM_SCAN_RADIUS if storm_active else CLEAR_SCAN_RADIUS]
    else:
        var scan_tip := " · Q扫描(冷却)" if scan_cooldown > 0.0 else " · Q扫描"
        _hint_label.text = "WASD移动 · 空格攻击%s · E修复 · F拾取 · G投送 · R救援%s" % [scan_tip, " · ⚠暴风雪" if storm_active else ""]

func _update_interaction_hint() -> void:
    if _interaction_label == null or not game_started:
        return
    var local := players.get(multiplayer.get_unique_id()) as SpacePlayer3D
    if local == null:
        _interaction_label.text = "等待宇航员同步……"
        return
    if local.downed:
        _interaction_label.text = "你已倒地，无法行动\n队友靠近按 R，留在身边 3 秒即可救援"
        return
    var prompts: Array[Dictionary] = []
    for entry in _object_tags:
        var node := entry.get("node") as Node3D
        if not is_instance_valid(node) or not node.visible:
            continue
        var kind := String(entry.get("kind", ""))
        var id := int(entry.get("id", 0))
        if kind == "crate" and taken_crates.has(id):
            continue
        var distance := _flat_distance(local.global_position, node.global_position)
        if distance > 4.0:
            continue
        var text := ""
        match kind:
            "beacon":
                    text = "气象信标已修复 · 前哨可补氧回温" if activated_beacons.has(id) else ("[E] 修复气象信标 · 建立前哨" if distance <= 2.0 else "气象信标 · 再靠近后按 E 修复")
            "crate":
                text = "热能电池 · 背包已满，先到蓝色平台按 G 投送" if local.carrying > 0 else ("[F] 拾取热能电池 · 一次携带一枚" if distance <= 1.8 else "热能电池 · 再靠近后按 F 拾取")
            "extraction":
                if local.carrying > 0:
                    text = "[G] 投送携带的热能电池" if distance <= 2.4 else "投送 / 撤离平台 · 再靠近后按 G 投送"
                elif extraction_enabled:
                    text = "撤离已开放 · 全体船员进入圆圈，保持 3 秒" if distance <= 2.5 else "撤离已开放 · 进入蓝色平台圆圈"
                else:
                    text = "投送 / 撤离平台 · 修复信标并投送至少 %d 枚电池" % MINIMUM_BATTERIES
        if not text.is_empty():
            prompts.append({"distance": distance, "text": text})
    var heat_distance := _flat_distance(local.global_position, Vector3(-12.0, 0.0, -7.0))
    if heat_distance <= HEAT_RADIUS:
        prompts.append({"distance": heat_distance, "text": "供暖装置 · 自动补氧、回温，无需按键"})
    for mate_value in players.values():
        var mate := mate_value as SpacePlayer3D
        if mate.peer_id != local.peer_id and mate.downed and _flat_distance(local.global_position, mate.global_position) <= REVIVE_RANGE:
            prompts.append({"distance": -1.0, "text": "[R] 救援倒地队友 · 留在身边 3 秒"})
    prompts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
    var lines := PackedStringArray()
    if not prompts.is_empty():
        lines.append(String(prompts[0].text))
    else:
        lines.append("已携带电池 → 寻找蓝色平台，靠近按 G 投送" if local.carrying > 0 else "寻找金色天线塔 [E] / 绿色电池罐 [F]，按 Q 扫描周围")
    var enemy_distance := INF
    for enemy_value in enemies.values():
        var enemy := enemy_value as SpaceEnemy3D
        if enemy == null:
            continue
        var current_distance := _flat_distance(local.global_position, enemy.global_position)
        if current_distance < enemy_distance:
            enemy_distance = current_distance
    if enemy_distance <= SpacePlayer3D.ATTACK_RANGE:
        lines.append("[空格] 按住连续攻击 · 异形已进入攻击范围")
    elif prompts.size() > 1:
        lines.append(String(prompts[1].text))
    else:
        lines.append("浅蓝圈为攻击范围 · 空格开火 · 冰岩和残骸是障碍，请绕行")
    _interaction_label.text = "\n".join(lines)

func _set_status(message: String) -> void:
    if _status_label != null:
        _status_label.text = "状态：" + message
    if _game_status_label != null:
        _game_status_label.text = message

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
