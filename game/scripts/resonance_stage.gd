extends Node
class_name ResonanceStage3D

## 共振星：移动式轨道工厂与反应堆甲板阶段控制器。
## 主机维护模块、路线、保险栓、核心和敌人状态；客户端只显示快照。
## 该脚本保留 Main3D 现有阶段接口，便于主舱、联机和返航系统复用。

const MAP_SIZE: Vector2 = Vector2(156.0, 96.0)
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy_3d.tscn")
const ALIEN_GROUND_TEXTURE: Texture2D = preload("res://assets/resonance/textures/alien_rock_ground.png")
const INDUSTRIAL_PANEL_TEXTURE: Texture2D = preload("res://assets/resonance/textures/industrial_panel.png")
const RESONANCE_MODULE_HERO_PATH: String = "res://assets/resonance/models/resonance_module_hero.glb"
const RESONANCE_RAIL_SYSTEM_PATH: String = "res://assets/resonance/models/resonance_rail_system.glb"
const RESONANCE_REACTOR_TOWER_PATH: String = "res://assets/resonance/models/resonance_reactor_tower.glb"
const RESONANCE_CORE_ART_PATH: String = "res://assets/resonance/models/resonance_energy_core.glb"
const RESONANCE_DRONE_DOCK_PATH: String = "res://assets/resonance/models/resonance_drone_dock.glb"
const RESONANCE_HELPER_DRONE_PATH: String = "res://assets/resonance/models/resonance_helper_drone.glb"
const RESONANCE_EXTRACTION_ART_PATH: String = "res://assets/resonance/models/resonance_extraction_platform.glb"
const RESONANCE_PROCESSING_ZONE_PATH: String = "res://assets/resonance/models/resonance_processing_zone.glb"
const RESONANCE_SURFACE_SET_PATH: String = "res://assets/resonance/models/resonance_surface_set.glb"
const RESONANCE_SUPPORT_GATE_PATH: String = "res://assets/resonance/models/resonance_support_safety_gate.glb"
const RESONANCE_MAINTENANCE_FACILITY_PATH: String = "res://assets/resonance/models/resonance_maintenance_facility.glb"
const RESONANCE_CAVERN_SHELL_PATH: String = "res://assets/resonance/models/resonance_cavern_shell.glb"
const RESONANCE_FACTORY_SPINE_PATH: String = "res://assets/resonance/models/resonance_factory_spine.glb"
const RESONANCE_MASTER_SCENE_PATH: String = "res://assets/resonance/models/resonance_master_scene.glb"
const USE_BLENDER_MASTER_VISUALS: bool = true
const USE_RESONANCE_MODULE_HERO: bool = true
const MODULE_COUNT: int = 3
const MODULE_RADIUS: float = 3.0
const CORE_RADIUS: float = 2.8
const EXTRACTION_RADIUS: float = 3.8
const OPERATOR_RADIUS: float = 2.9
const ROUTE_RADIUS: float = 3.2
const DOCK_TIME: float = 4.2
const FAST_DOCK_TIME: float = 2.6
const TRAVEL_TIME: float = 2.8
const OVERLOAD_LIMIT: float = 3.8
const STORM_INTERVAL: float = 35.0
const STORM_DURATION: float = 10.0
const DRONE_DURATION: float = 12.0
const MINIGAME_GAUGE: Script = preload("res://scripts/minigame_gauge.gd")
const DRONE_COOLDOWN: float = 8.0
const SUPPORT_RELAY_LOW_POSITION: Vector3 = Vector3(15.0, 0.0, -3.0)
const SUPPORT_RELAY_HIGH_POSITION: Vector3 = Vector3(3.0, 3.1, -3.0)
const SUPPORT_RELAY_WINDOW: float = 8.0
const CHECKPOINTS: int = MODULE_COUNT
const CORE_SPEED: float = 0.65
const START_POSITION: Vector3 = Vector3(-60.0, 0.0, 28.0)
const LAVA_MARGIN_X: float = 72.0
const LAVA_MARGIN_Z: float = 42.0
const LAVA_PIT_RECTS: Array[Rect2] = [
    Rect2(18.0, -37.0, 18.0, 8.0),
    Rect2(-20.0, 26.0, 36.0, 6.0)
]
# 熔岩覆盖洞底；只有铸造甲板、轨道连接桥和检修平台是可站立区域。
# 这些矩形与路径只负责“是否落入熔岩”的玩法判定，碰撞体仍由 Godot 世界节点维护。
const SAFE_DECK_RECTS: Array[Rect2] = [
    Rect2(-68.0, 8.0, 28.0, 24.0),   # 进料区与初始平台
    Rect2(-30.0, 22.0, 18.0, 12.0),  # 泄压阀与支援闸前平台
    Rect2(-44.0, 8.0, 18.0, 20.0),   # 第一节模块
    Rect2(-14.0, -10.0, 30.0, 24.0), # 升降分流区
    Rect2(22.0, -25.0, 27.0, 25.0),  # 第三节模块
    Rect2(40.0, -29.0, 36.0, 32.0),  # 反应堆甲板与返航台
    Rect2(14.0, 20.0, 14.0, 12.0),   # 支援安全闸
    Rect2(-69.0, -36.0, 20.0, 16.0), # 废弃维修仓
    Rect2(-53.0, -17.0, 14.0, 10.0)  # 中层观景桥西侧坡道落地平台
]
const SAFE_PATH_SEGMENTS: Array = [
    [Vector2(-24.0, 28.0), Vector2(-34.0, 18.0)],
    [Vector2(-34.0, 18.0), Vector2(0.0, 2.0)],
    [Vector2(0.0, 2.0), Vector2(34.0, -14.0)],
    [Vector2(34.0, -14.0), Vector2(55.0, -17.0)],
    [Vector2(55.0, -17.0), Vector2(66.0, -14.0)]
]
const ELEVATED_PLATFORM_POINTS: Array[Vector2] = [
    Vector2(-28.0, -12.0),
    Vector2(3.0, -3.0),
    Vector2(34.0, -12.0),
    Vector2(SUPPORT_RELAY_HIGH_POSITION.x, SUPPORT_RELAY_HIGH_POSITION.z)
]
# 中层观景桥：南侧高架走廊，连接西侧检修桥与反应堆甲板。
const OBSERVATION_BRIDGE_RECT: Rect2 = Rect2(-30.0, -13.6, 72.0, 3.2)
const OBSERVATION_BRIDGE_Y: float = 4.8
# 视觉碰撞生成阈值：只给大结构做实体碰撞，交互基座与薄装饰保持可穿过。
const VISUAL_COLLISION_MIN_HEIGHT: float = 0.45
const VISUAL_COLLISION_MIN_WIDTH: float = 0.35
const VISUAL_COLLISION_MIN_TOP: float = 0.45
const VISUAL_COLLISION_LIMIT: int = 520

var controller: Main3D
var world_root: Node3D
var core_node: Node3D
var extraction_node: Node3D
var drone_node: Node3D
var role_assignments: Dictionary = {}
var modules: Array[Dictionary] = []
var stations: Array[Dictionary] = []
var module_nodes: Dictionary = {}
var station_nodes: Dictionary = {}
var bridge_nodes: Dictionary = {}
var route_nodes: Dictionary = {}
var role_lights: Dictionary = {}
var art_asset_nodes: Dictionary = {}
var heat_valve_nodes: Dictionary = {}
var heat_valve_positions: Dictionary = {
    "left": Vector3(-49.0, 0.0, 14.0),
    "right": Vector3(-43.0, 0.0, 28.0),
    "relief": Vector3(-24.0, 0.0, 28.0)
}
var heat_valves: Dictionary = {"left": 0, "right": 0, "relief": 0}
var heat_valve_operators: Array[int] = []
var heat_chain_complete: bool = false
var lava_tide_clock: float = 0.0
var lava_tide_active: bool = false
var lava_surface_node: MeshInstance3D
var lava_pit_nodes: Array[MeshInstance3D] = []
var reactor_mechanism_nodes: Dictionary = {}
var vertical_shaft_gate_node: Node3D
var vertical_shaft_gate_body: StaticBody3D
var core_carriers: Array[int] = []
var freight_carrier: int = 0
var reactor_deck_active: bool = false
var reactor_challenge_index: int = 0
var reactor_challenges: Array[Dictionary] = []
var reactor_carrier: int = 0
var reactor_stabilizer: int = 0
var core_delivered: bool = false
var core_dropped_position: Vector3 = Vector3(52.0, 0.0, -22.0)
var extraction_enabled: bool = false
var extraction_progress: float = 0.0
var shortcut_unlocked: bool = false
var shortcut_node: Node3D
var shortcut_body: StaticBody3D
var support_relay_nodes: Dictionary = {}
var support_relay: Dictionary = {
    "phase": 0,
    "low_peer": 0,
    "high_peer": 0,
    "deadline": 0.0,
    "failures": 0
}
var support_relay_reward_active: bool = false
var objective_guide: Node3D
var objective_path_root: Node3D
var objective_path_nodes: Array[MeshInstance3D] = []
var freight_visuals: Dictionary = {}
var beam_visuals: Dictionary = {}
var chapter: int = 0
var checkpoint: int = 0
var mission_elapsed: float = 0.0
var storm_active: bool = false
var storm_remaining: float = 0.0
var storm_clock: float = 0.0
var drone_state: Dictionary = {
    "active": false,
    "owner": 0,
    "position": Vector3.ZERO,
    "remaining": 0.0,
    "cooldown": 0.0,
    "target": ""
}
var action_cooldowns: Dictionary = {}
var _sync_clock: float = 0.0
var _enemy_clock: float = 0.0
# 交互小游戏：设备类交互先开启一次校准，光标落在亮区时再按一次确认。
var minigames_enabled: bool = true
var minigame: Dictionary = {}
var minigame_layer: CanvasLayer
var minigame_label: Label
var minigame_gauge: Control
var _minigame_lever: Node3D

func setup(owner: Main3D) -> void:
    controller = owner
    name = "ResonanceStage"

func is_active() -> bool:
    return controller != null and controller.current_planet_id == "electromagnetic" and controller.game_started

func get_map_size() -> Vector2:
    return MAP_SIZE

func get_active_map_size() -> Vector2:
    return get_map_size()

func start_planet(stage_id: String) -> void:
    if stage_id == "electromagnetic":
        start_stage()

func start_stage() -> void:
    stop_stage()
    minigame = {}
    if _minigame_lever != null and is_instance_valid(_minigame_lever):
        _minigame_lever.queue_free()
    _minigame_lever = null
    if minigame_layer != null:
        minigame_layer.visible = false
    chapter = 0
    checkpoint = 0
    mission_elapsed = 0.0
    storm_clock = 0.0
    storm_active = false
    storm_remaining = 0.0
    extraction_enabled = false
    extraction_progress = 0.0
    shortcut_unlocked = false
    _reset_support_relay()
    support_relay_reward_active = false
    heat_valves = {"left": 0, "right": 0, "relief": 0}
    heat_valve_operators.clear()
    heat_chain_complete = false
    lava_tide_clock = 0.0
    lava_tide_active = false
    core_carriers.clear()
    reactor_deck_active = false
    reactor_challenge_index = 0
    reactor_carrier = 0
    reactor_stabilizer = 0
    core_delivered = false
    core_dropped_position = Vector3(52.0, 0.0, -22.0)
    drone_state = {
        "active": false,
        "owner": 0,
        "position": Vector3.ZERO,
        "remaining": 0.0,
        "cooldown": 0.0,
        "target": ""
    }
    action_cooldowns.clear()
    _sync_clock = 0.0
    _enemy_clock = 0.0
    _assign_roles()
    _build_modules_data()
    _build_reactor_challenges()
    _build_world()
    controller._set_status("共振星：轨道工厂正在移动。先完成第一节模块对接。")
    controller._record_journal("共振星登陆", "废弃能源工厂仍在沿轨道循环。三节能源模块必须重新对接，才能取出中央能源核心。")
    controller._record_journal("移动设施协议", "导能切换轨道，定场锁住对接夹具，支援携带保险栓。快线更快，但会积累过载和安保压力。")

func stop_stage() -> void:
    _release_core_carriers(core_dropped_position)
    _release_reactor_carrier()
    if world_root != null and is_instance_valid(world_root):
        world_root.queue_free()
    world_root = null
    core_node = null
    extraction_node = null
    drone_node = null
    support_relay_nodes.clear()
    _reset_support_relay()
    support_relay_reward_active = false
    modules.clear()
    stations.clear()
    module_nodes.clear()
    station_nodes.clear()
    bridge_nodes.clear()
    route_nodes.clear()
    reactor_mechanism_nodes.clear()
    vertical_shaft_gate_node = null
    vertical_shaft_gate_body = null
    role_lights.clear()
    art_asset_nodes.clear()
    heat_valve_nodes.clear()
    lava_surface_node = null
    lava_pit_nodes.clear()
    heat_valves = {"left": 0, "right": 0, "relief": 0}
    heat_valve_operators.clear()
    heat_chain_complete = false
    lava_tide_clock = 0.0
    lava_tide_active = false
    shortcut_node = null
    shortcut_body = null
    objective_guide = null
    objective_path_root = null
    objective_path_nodes.clear()
    freight_visuals.clear()
    beam_visuals.clear()
    freight_carrier = 0
    reactor_challenges.clear()
    reactor_deck_active = false
    reactor_challenge_index = 0
    reactor_carrier = 0
    reactor_stabilizer = 0
    _clear_stage_enemies()

func _assign_roles() -> void:
    role_assignments.clear()
    if controller == null:
        return
    var ids: Array = controller.connected_ids.duplicate()
    ids.sort()
    for index in ids.size():
        var peer_id: int = int(ids[index])
        role_assignments[peer_id] = "conduit" if index == 0 else ("anchor" if index == 1 else "support")
    if ids.size() == 1:
        role_assignments[ids[0]] = "conduit"

func _build_modules_data() -> void:
    modules.clear()
    stations.clear()
    var positions: Array[Vector3] = [
        Vector3(-34.0, 0.0, 18.0),
        Vector3(0.0, 0.0, 2.0),
        Vector3(34.0, 0.0, -14.0)
    ]
    var names: Array[String] = ["进料对接段", "升降分流段", "反应堆接驳段"]
    var route_labels: Array[String] = ["安全检修轨", "低位快线", "安全检修轨"]
    var mechanics: Array[String] = ["switch", "freight", "beam"]
    for index in MODULE_COUNT:
        var position: Vector3 = positions[index]
        var module: Dictionary = {
            "id": index + 1,
            "name": names[index],
            "position": position,
            "start_position": position,
            "dock_position": position + Vector3(7.0, 0.0, 0.0),
            "state": "ready" if index == 0 else "sealed",
            "phase": "ready" if index == 0 else "sealed",
            "route_choice": "safe",
            "route_label": route_labels[index],
            "mechanic": mechanics[index],
            "mechanic_progress": 0.0,
            "cargo_loaded": false,
            "freight_custom_position": false,
            "beam_step": 0,
            "beam_sequence": ["support", "route", "safety"],
            "beam_operators": [],
            "freight_position": position + Vector3(0.0, 0.0, 5.0),
            "route_locked": false,
            "rail_peer": 0,
            "clamp_peer": 0,
            "support_peer": 0,
            "safety_peer": 0,
            "progress": 0.0,
            "docking_progress": 0.0,
            "travel_progress": 0.0,
            "overload": 0.0,
            "sequence_step": 0,
            "sequence_deadline": 0.0,
            "rhythm_complete": false,
            "fast_route_used": false,
            "relay_relief": false,
            "security_spawned": false,
            "rail_position": position + Vector3(-3.4, 0.0, 0.0),
            "clamp_position": position + Vector3(3.4, 0.0, 0.0),
            "left_position": position + Vector3(-3.4, 0.0, 0.0),
            "right_position": position + Vector3(3.4, 0.0, 0.0),
            "support_position": position + Vector3(0.0, 0.0, 3.8),
            "safety_position": position + Vector3(0.0, 0.0, -3.6),
            "route_position": position + Vector3(0.0, 0.0, -7.2)
        }
        modules.append(module)
    stations = modules

func _build_reactor_challenges() -> void:
    reactor_challenges = [
        {
            "id": "lift",
            "name": "升降接力",
            "sequence": ["lower", "upper"],
            "step": 0,
            "operators": [],
            "lower_position": Vector3(44.0, 0.0, -22.0),
            "upper_position": Vector3(58.0, 3.2, -22.0)
        },
        {
            "id": "mirror",
            "name": "镜面反射",
            "sequence": ["left", "right", "center"],
            "step": 0,
            "operators": [],
            "left_position": Vector3(46.0, 0.0, -8.0),
            "right_position": Vector3(58.0, 0.0, -4.0),
            "center_position": Vector3(65.0, 0.0, -14.0)
        },
        {
            "id": "coolant",
            "name": "冷却单元护送",
            "sequence": [],
            "step": 0,
            "operators": [],
            "coolant_loaded": false,
            "coolant_position": Vector3(48.0, 0.0, -18.0),
            "coolant_socket_position": Vector3(63.0, 0.0, -14.0),
            "stabilizer_position": Vector3(58.0, 0.0, -10.0)
        }
    ]

func _build_reactor_mechanism_visuals() -> void:
    var set_root: Node3D = Node3D.new()
    set_root.name = "ReactorCoopMechanismSet"
    world_root.add_child(set_root)

    var lift_root: Node3D = Node3D.new()
    lift_root.name = "ReactorLiftPlatform"
    lift_root.position = Vector3(58.0, 0.0, -22.0)
    var lift_plate: MeshInstance3D = _add_decor_box(lift_root, Vector3(0.0, 0.22, 0.0), Vector3(8.0, 0.34, 5.2), Color("#293c68"), Color("#67a6ff"), 0.55)
    lift_plate.name = "LiftDeckPlate"
    _add_decor_box(lift_root, Vector3(-3.45, 0.9, 0.0), Vector3(0.24, 1.8, 4.6), Color("#3c4d78"), Color("#99b8ff"), 0.6)
    _add_decor_box(lift_root, Vector3(3.45, 0.9, 0.0), Vector3(0.24, 1.8, 4.6), Color("#3c4d78"), Color("#99b8ff"), 0.6)
    _add_detail_ring(lift_root, Vector3(0.0, 0.5, 0.0), 1.25, 1.42, Color("#8db9ff"))
    lift_root.add_child(_label3d("升降接力甲板\n低位 → 高位", Vector3(0.0, 2.2, 0.0), Color("#c8dbff")))
    var lift_body: StaticBody3D = StaticBody3D.new()
    lift_body.name = "ReactorLiftPlatformCollision"
    lift_body.collision_layer = 2
    lift_body.collision_mask = 1
    var lift_shape: CollisionShape3D = CollisionShape3D.new()
    var lift_box: BoxShape3D = BoxShape3D.new()
    lift_box.size = Vector3(8.0, 0.34, 5.2)
    lift_shape.shape = lift_box
    lift_shape.position.y = 0.22
    lift_body.add_child(lift_shape)
    lift_root.add_child(lift_body)
    set_root.add_child(lift_root)
    reactor_mechanism_nodes["lift_platform"] = lift_root

    var lift_hydraulic_base: Node3D = Node3D.new()
    lift_hydraulic_base.name = "ReactorLiftHydraulics"
    lift_hydraulic_base.position = Vector3(58.0, 0.0, -22.0)
    for side in [-1.0, 1.0]:
        _add_decor_pipe(Vector3(54.8, 0.12, side * 1.5 - 22.0), Vector3(54.8, 3.1, side * 1.5 - 22.0), Color("#39476a"), Color("#7fa9ff"))
        _add_decor_pipe(Vector3(61.2, 0.12, side * 1.5 - 22.0), Vector3(61.2, 3.1, side * 1.5 - 22.0), Color("#39476a"), Color("#7fa9ff"))
    set_root.add_child(lift_hydraulic_base)

    var mirror_challenge: Dictionary = reactor_challenges[1]
    for kind in ["left", "right", "center"]:
        var mirror_root: Node3D = Node3D.new()
        mirror_root.name = "ReactorMirror_%s" % kind
        mirror_root.position = Vector3(mirror_challenge["%s_position" % kind])
        var mirror_plate: MeshInstance3D = _add_decor_box(mirror_root, Vector3(0.0, 0.36, 0.0), Vector3(3.8, 0.72, 2.8), Color("#2c385d"), Color("#7d8cff"), 0.6)
        mirror_plate.name = "MirrorPlate"
        var mirror_ring: MeshInstance3D = _add_detail_ring(mirror_root, Vector3(0.0, 1.05, 0.0), 0.95, 1.2, Color("#9a83ff"))
        mirror_ring.name = "MirrorIndicator"
        mirror_root.add_child(_label3d("镜面 %s" % ("左" if kind == "left" else ("右" if kind == "right" else "中央")), Vector3(0.0, 2.05, 0.0), Color("#d8d1ff")))
        set_root.add_child(mirror_root)
        reactor_mechanism_nodes["mirror_%s" % kind] = mirror_ring

    var coolant_challenge: Dictionary = reactor_challenges[2]
    var coolant_root: Node3D = Node3D.new()
    coolant_root.name = "ReactorCoolantSocket"
    coolant_root.position = Vector3(coolant_challenge["coolant_socket_position"])
    _add_decor_box(coolant_root, Vector3(0.0, 0.36, 0.0), Vector3(4.2, 0.7, 3.2), Color("#214b51"), Color("#79e9b7"), 0.75)
    var coolant_ring: MeshInstance3D = _add_detail_ring(coolant_root, Vector3(0.0, 1.08, 0.0), 1.25, 1.55, Color("#79e9b7"))
    coolant_ring.name = "CoolantSocketIndicator"
    coolant_root.add_child(_label3d("冷却接收座\n稳定后接入", Vector3(0.0, 2.25, 0.0), Color("#b7ffe0")))
    set_root.add_child(coolant_root)
    reactor_mechanism_nodes["coolant_socket"] = coolant_ring

    var stabilizer_root: Node3D = Node3D.new()
    stabilizer_root.name = "ReactorCoolantStabilizer"
    stabilizer_root.position = Vector3(coolant_challenge["stabilizer_position"])
    _add_decor_box(stabilizer_root, Vector3(0.0, 0.28, 0.0), Vector3(3.2, 0.56, 2.6), Color("#3d365f"), Color("#c29cff"), 0.7)
    var stabilizer_ring: MeshInstance3D = _add_detail_ring(stabilizer_root, Vector3(0.0, 0.92, 0.0), 0.85, 1.1, Color("#9a83ff"))
    stabilizer_ring.name = "StabilizerIndicator"
    stabilizer_root.add_child(_label3d("接收座稳定", Vector3(0.0, 1.85, 0.0), Color("#d7c8ff")))
    set_root.add_child(stabilizer_root)
    reactor_mechanism_nodes["coolant_stabilizer"] = stabilizer_ring

    vertical_shaft_gate_node = Node3D.new()
    vertical_shaft_gate_node.name = "VerticalShaftSafetyGate"
    vertical_shaft_gate_node.position = Vector3(69.0, 0.0, -20.0)
    for side in [-1.0, 1.0]:
        _add_decor_box(vertical_shaft_gate_node, Vector3(side * 2.2, 2.6, 0.0), Vector3(0.5, 5.2, 0.7), Color("#30364f"), Color("#8a6b86"), 0.5)
    for index in 3:
        var gate_bar: MeshInstance3D = _add_decor_box(vertical_shaft_gate_node, Vector3(-1.4 + float(index) * 1.4, 2.4, 0.0), Vector3(0.9, 4.5, 0.34), Color("#593f55"), Color("#ff8f62"), 0.72)
        gate_bar.name = "GateBar_%d" % index
    _add_detail_ring(vertical_shaft_gate_node, Vector3(0.0, 1.0, -0.45), 0.72, 0.9, Color("#ffbd65"))
    vertical_shaft_gate_node.add_child(_label3d("垂直井安全闸\n反应堆稳定后开启", Vector3(0.0, 5.9, 0.0), Color("#ffd1a0")))
    vertical_shaft_gate_body = StaticBody3D.new()
    vertical_shaft_gate_body.name = "VerticalShaftSafetyGateCollision"
    vertical_shaft_gate_body.collision_layer = 2
    vertical_shaft_gate_body.collision_mask = 1
    var gate_shape: CollisionShape3D = CollisionShape3D.new()
    var gate_box: BoxShape3D = BoxShape3D.new()
    gate_box.size = Vector3(5.0, 5.2, 0.8)
    gate_shape.shape = gate_box
    gate_shape.position.y = 2.6
    vertical_shaft_gate_body.add_child(gate_shape)
    vertical_shaft_gate_node.add_child(vertical_shaft_gate_body)
    world_root.add_child(vertical_shaft_gate_node)
    _set_vertical_shaft_gate_open(false)
    _refresh_reactor_mechanism_visuals()
    if USE_BLENDER_MASTER_VISUALS:
        # The visible lift/mirror/coolant machines live in the authored master
        # scene.  Keep this Godot set for collision and state anchors only.
        set_root.visible = false

func _set_vertical_shaft_gate_open(is_open: bool) -> void:
    if vertical_shaft_gate_node == null or vertical_shaft_gate_body == null:
        return
    vertical_shaft_gate_node.visible = not is_open
    vertical_shaft_gate_body.collision_layer = 0 if is_open else 2
    vertical_shaft_gate_body.collision_mask = 0 if is_open else 1
    vertical_shaft_gate_node.set_meta("resonance_gate_open", is_open)

func _refresh_reactor_mechanism_visuals() -> void:
    if reactor_mechanism_nodes.is_empty() or reactor_challenges.size() < 3:
        return
    var lift_platform: Node3D = reactor_mechanism_nodes.get("lift_platform") as Node3D
    if lift_platform != null:
        var lift: Dictionary = reactor_challenges[0]
        var lift_target_y: float = 3.2 if int(lift.get("step", 0)) >= 1 else 0.0
        lift_platform.position.y = move_toward(lift_platform.position.y, lift_target_y, 0.45)
        if controller != null and controller.is_host and lift_target_y > 0.0:
            var lift_anchor: Vector3 = Vector3(58.0, 0.0, -22.0)
            for player_value in controller.players.values():
                var passenger: SpacePlayer3D = player_value as SpacePlayer3D
                if passenger == null or passenger.downed or passenger.lava_dead:
                    continue
                if controller._flat_distance(passenger.global_position, lift_anchor) <= 3.8 and passenger.global_position.y < lift_platform.position.y + 0.7:
                    passenger.global_position.y = lift_platform.position.y
    var mirror: Dictionary = reactor_challenges[1]
    var mirror_step: int = int(mirror.get("step", 0))
    var mirror_sequence: Array = mirror.get("sequence", ["left", "right", "center"])
    for index in mirror_sequence.size():
        var kind: String = String(mirror_sequence[index])
        var indicator: MeshInstance3D = reactor_mechanism_nodes.get("mirror_%s" % kind) as MeshInstance3D
        if indicator == null:
            continue
        var color: Color = Color("#83ffbc") if index < mirror_step else (Color("#ffe18b") if index == mirror_step else Color("#716b99"))
        indicator.material_override = _glow_material(color, 1.35 if index <= mirror_step else 0.65)
    var coolant: Dictionary = reactor_challenges[2]
    var socket: MeshInstance3D = reactor_mechanism_nodes.get("coolant_socket") as MeshInstance3D
    if socket != null:
        socket.material_override = _glow_material(Color("#8ffff1") if bool(coolant.get("coolant_loaded", false)) else Color("#79e9b7"), 1.55)
    var stabilizer: MeshInstance3D = reactor_mechanism_nodes.get("coolant_stabilizer") as MeshInstance3D
    if stabilizer != null:
        stabilizer.material_override = _glow_material(Color("#9ff5cf") if reactor_stabilizer != 0 else Color("#9a83ff"), 1.35)

func _build_world() -> void:
    world_root = Node3D.new()
    world_root.name = "ResonanceRailFactoryWorld"
    add_child(world_root)
    _build_environment()
    _build_ground()
    _build_lava_floor()
    if not USE_BLENDER_MASTER_VISUALS:
        _build_planetary_surface()
        _build_safe_deck_visuals()
        _build_cliff_edges_visuals()
        _build_cave_backdrop_visuals()
        _build_perimeter()
        _build_tracks()
    else:
        # Keep stable scene handles for diagnostics and camera tooling; the
        # actual visible rock decks and cliff faces are in the Blender master.
        var authored_cliffs: Node3D = Node3D.new()
        authored_cliffs.name = "CliffEdgesVisuals"
        authored_cliffs.set_meta("visual_authority", "Blender:resonance_master_scene.glb")
        world_root.add_child(authored_cliffs)
        var authored_decks: Node3D = Node3D.new()
        authored_decks.name = "SafeDeckVisuals"
        authored_decks.set_meta("visual_authority", "Blender:resonance_master_scene.glb")
        world_root.add_child(authored_decks)
    _build_heat_valves()
    _build_modules()
    if not USE_BLENDER_MASTER_VISUALS and not ResourceLoader.exists(RESONANCE_PROCESSING_ZONE_PATH):
        _build_depth_setpieces()
    else:
        _build_vertical_platform_collisions()
    if not USE_BLENDER_MASTER_VISUALS:
        _build_industrial_set_dressing()
    _build_art_asset_overlays()
    if not USE_BLENDER_MASTER_VISUALS:
        _build_factory_spine_visuals()
        _build_industrial_megastructure()
        _build_lava_fissure_visuals()
    # 相机不再使用遮挡代理与透明淡出：镜头保持远景高度，靠几何留白与
    # 射线收缩避让，避免整组资源被降 alpha 造成的半透明脏画面。
    _build_reactor_mechanism_visuals()
    _build_core()
    _build_extraction()
    _build_drone_visual()
    _build_support_gate()
    _build_support_relay_visuals()
    _build_objective_guide()
    # 等所有交互锚点生成后再补视觉碰撞，保证碰撞盒不会盖住玩法位置。
    _build_visual_collision()

func _build_environment() -> void:
    var environment: WorldEnvironment = WorldEnvironment.new()
    var env: Environment = Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#120d16")
    var sky: Sky = Sky.new()
    var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("#342445")
    sky_material.sky_horizon_color = Color("#e98f73")
    sky_material.ground_bottom_color = Color("#4b2f32")
    sky_material.ground_horizon_color = Color("#c96e62")
    sky_material.sky_energy_multiplier = 0.65
    sky_material.ground_energy_multiplier = 0.65
    sky.sky_material = sky_material
    env.sky = sky
    # 洞窟东侧塌陷后露出天空，背景改用程序化天空，让洞口成为远景光源。
    env.background_mode = Environment.BG_SKY
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#a98aa4")
    env.ambient_light_energy = 0.72
    env.fog_enabled = true
    env.fog_light_color = Color("#4a3040")
    env.fog_density = 0.0012
    env.glow_enabled = true
    env.glow_intensity = 1.0
    env.glow_strength = 1.15
    environment.environment = env
    world_root.add_child(environment)

    var sun: DirectionalLight3D = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    sun.light_color = Color("#ffb56c")
    sun.light_energy = 0.58
    sun.shadow_enabled = true
    world_root.add_child(sun)

    var fill: OmniLight3D = OmniLight3D.new()
    fill.position = Vector3(0.0, 12.0, 0.0)
    fill.light_color = Color("#718cff")
    fill.light_energy = 4.8
    fill.omni_range = 100.0
    world_root.add_child(fill)
    var warm_fill: OmniLight3D = OmniLight3D.new()
    warm_fill.name = "ResonanceWarmIndustrialFill"
    warm_fill.position = Vector3(-34.0, 8.0, 18.0)
    warm_fill.light_color = Color("#ff8a45")
    warm_fill.light_energy = 5.6
    warm_fill.omni_range = 28.0
    world_root.add_child(warm_fill)
    var reactor_fill: OmniLight3D = OmniLight3D.new()
    reactor_fill.name = "ResonanceReactorFill"
    reactor_fill.position = Vector3(55.0, 8.0, -17.0)
    reactor_fill.light_color = Color("#65ffbf")
    reactor_fill.light_energy = 7.2
    reactor_fill.omni_range = 34.0
    world_root.add_child(reactor_fill)
    # 东侧开口的日光溢入：只照亮洞口一侧，作为远景光源和方向提示。
    var daylight_spill: OmniLight3D = OmniLight3D.new()
    daylight_spill.name = "ResonanceDaylightSpill"
    daylight_spill.position = Vector3(110.0, 28.0, 0.0)
    daylight_spill.light_color = Color("#ffbd86")
    daylight_spill.light_energy = 2.6
    daylight_spill.omni_range = 130.0
    world_root.add_child(daylight_spill)

func _build_ground() -> void:
    var ground: MeshInstance3D = MeshInstance3D.new()
    ground.name = "ResonanceGroundVisual"
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(MAP_SIZE.x, 0.35, MAP_SIZE.y)
    ground.mesh = mesh
    ground.position.y = -0.25
    # 岩浆底盘压在岩台下方；地表本身读成深色玄武岩和工业磨损，避免
    # 一整张高饱和红色平面吞掉厂区主体。真正的熔岩河道由
    # _build_lava_fissure_visuals 和 LAVA_PIT_RECTS 单独表现。
    var ground_material: StandardMaterial3D = _material(Color("#261b21"), Color("#4a3035"), 0.08)
    # 这张贴图在顶视总览会形成规则红色扫描条，破坏岩台和机械层次；
    # 近景岩土由地表资产和洞穴墙体提供，底板只保留低对比玄武岩底色。
    ground_material.albedo_texture = null
    ground.material_override = ground_material
    # 玩法碰撞仍由 ResonanceGroundCollision 独立维护；视觉底板隐藏，
    # 由安全甲板、轨道桥和岩台围出真实的“熔岩洞底”。
    ground.visible = false
    world_root.add_child(ground)

    var body: StaticBody3D = StaticBody3D.new()
    body.name = "ResonanceGroundCollision"
    body.collision_layer = 2
    body.collision_mask = 1
    # 将底部碰撞拆成安全地块，给熔岩裂隙留下真实的物理空洞。
    var min_x: float = -MAP_SIZE.x * 0.5
    var max_x: float = MAP_SIZE.x * 0.5
    var min_z: float = -MAP_SIZE.y * 0.5
    var max_z: float = MAP_SIZE.y * 0.5
    var cursor_z: float = min_z
    for pit in LAVA_PIT_RECTS:
        var pit_min_z: float = pit.position.y
        var pit_max_z: float = pit.position.y + pit.size.y
        if pit_min_z > cursor_z:
            _add_ground_collision_box(body, Vector3(0.0, -0.25, (cursor_z + pit_min_z) * 0.5), Vector3(MAP_SIZE.x, 0.35, pit_min_z - cursor_z))
        if pit.position.x > min_x:
            _add_ground_collision_box(body, Vector3((min_x + pit.position.x) * 0.5, -0.25, (pit_min_z + pit_max_z) * 0.5), Vector3(pit.position.x - min_x, 0.35, pit.size.y))
        var pit_max_x: float = pit.position.x + pit.size.x
        if pit_max_x < max_x:
            _add_ground_collision_box(body, Vector3((pit_max_x + max_x) * 0.5, -0.25, (pit_min_z + pit_max_z) * 0.5), Vector3(max_x - pit_max_x, 0.35, pit.size.y))
        cursor_z = pit_max_z
    if cursor_z < max_z:
        _add_ground_collision_box(body, Vector3(0.0, -0.25, (cursor_z + max_z) * 0.5), Vector3(MAP_SIZE.x, 0.35, max_z - cursor_z))
    world_root.add_child(body)

func _add_ground_collision_box(parent: StaticBody3D, point: Vector3, size: Vector3) -> void:
    if size.x <= 0.05 or size.z <= 0.05:
        return
    var shape: CollisionShape3D = CollisionShape3D.new()
    var box: BoxShape3D = BoxShape3D.new()
    box.size = size
    shape.shape = box
    shape.position = point
    parent.add_child(shape)

func _build_lava_floor() -> void:
    var lava: MeshInstance3D = MeshInstance3D.new()
    lava.name = "ResonanceLavaSurface"
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(MAP_SIZE.x, 0.08, MAP_SIZE.y)
    lava.mesh = mesh
    # 熔岩海下降到悬崖底部，安全甲板和岩台之间形成可读的落差。
    lava.position.y = -4.02
    var lava_material: StandardMaterial3D = _material(Color("#080307"), Color("#35101a"), 0.22)
    lava_material.emission_enabled = true
    lava_material.emission = Color("#26070e")
    lava_material.emission_energy_multiplier = 0.22
    lava.material_override = lava_material
    lava.visible = not USE_BLENDER_MASTER_VISUALS
    world_root.add_child(lava)
    lava_surface_node = lava
    lava_pit_nodes.clear()
    for rect in LAVA_PIT_RECTS:
        var pit: MeshInstance3D = MeshInstance3D.new()
        var pit_mesh: BoxMesh = BoxMesh.new()
        pit_mesh.size = Vector3(rect.size.x, 0.12, rect.size.y)
        pit.mesh = pit_mesh
        pit.position = Vector3(rect.position.x + rect.size.x * 0.5, -3.82, rect.position.y + rect.size.y * 0.5)
        pit.material_override = _glow_material(Color("#9d241b"), 0.72)
        pit.visible = not USE_BLENDER_MASTER_VISUALS
        world_root.add_child(pit)
        lava_pit_nodes.append(pit)

func _build_heat_valves() -> void:
    for key_value in heat_valve_positions.keys():
        var key: String = String(key_value)
        var point: Vector3 = Vector3(heat_valve_positions[key])
        var valve: Node3D = Node3D.new()
        valve.name = "HeatValve_%s" % key
        valve.position = point
        if not USE_BLENDER_MASTER_VISUALS:
            _add_decor_box(valve, Vector3(0.0, 0.55, 0.0), Vector3(2.8, 1.1, 2.8), Color("#3b2430"), Color("#ff6b38"), 1.1)
            _add_detail_panel(valve, Vector3(0.0, 0.7, 1.42), Vector3(1.5, 0.55, 0.16), Color("#4b2d3a"), Color("#ffb05c"))
            _add_detail_ring(valve, Vector3(0.0, 1.35, 0.0), 0.95, 1.16, Color("#ff8a43"))
            _add_decor_box(valve, Vector3(0.0, 1.78, 0.0), Vector3(0.28, 1.45, 1.7), Color("#ff8a43"), Color("#ffb05c"), 1.0)
        valve.add_child(_label3d("热阀 %s" % ("左" if key == "left" else ("右" if key == "right" else "泄压")), Vector3(0.0, 2.8, 0.0), Color("#ffd08a")))
        world_root.add_child(valve)
        heat_valve_nodes[key] = valve

func _build_planetary_surface() -> void:
    var mesa_data: Array = [
        [Vector3(-68.0, 0.0, -30.0), Vector3(18.0, 7.0, 12.0)],
        [Vector3(-35.0, 0.0, -37.0), Vector3(24.0, 5.0, 10.0)],
        [Vector3(8.0, 0.0, -35.0), Vector3(20.0, 8.0, 14.0)],
        [Vector3(39.0, 0.0, 30.0), Vector3(28.0, 6.0, 12.0)],
        [Vector3(70.0, 0.0, 28.0), Vector3(14.0, 9.0, 18.0)]
    ]
    for entry in mesa_data:
        _build_rock_formation(Vector3(entry[0]), Vector3(entry[1]))
    var strata: Array[Vector3] = [
        Vector3(-62.0, 0.0, 37.0),
        Vector3(-17.0, 0.0, -31.0),
        Vector3(24.0, 0.0, 35.0),
        Vector3(72.0, 0.0, -34.0)
    ]
    for point in strata:
        _add_decor_box(world_root, point + Vector3(0.0, 0.22, 0.0), Vector3(13.0, 0.45, 3.2), Color("#5b3538"), Color("#9a5550"), 0.22, -12.0)
        _add_decor_box(world_root, point + Vector3(1.2, 0.56, 0.25), Vector3(8.0, 0.18, 1.4), Color("#7b4845"), Color("#b56b58"), 0.2, -12.0)

func _build_safe_deck_visuals() -> void:
    # 把 SAFE_DECK_RECTS 变成可读的岩台/钢制甲板视觉；碰撞仍由
    # _build_ground 的独立 StaticBody3D 提供，不把美术网格当成玩法地面。
    var root: Node3D = Node3D.new()
    root.name = "SafeDeckVisuals"
    world_root.add_child(root)
    var basalt: Color = Color("#24262f")
    var edge: Color = Color("#4b3c45")
    var amber: Color = Color("#e8893c")
    for index in SAFE_DECK_RECTS.size():
        var rect: Rect2 = SAFE_DECK_RECTS[index]
        var center: Vector3 = Vector3(rect.position.x + rect.size.x * 0.5, 0.02, rect.position.y + rect.size.y * 0.5)
        _add_decor_box(root, center, Vector3(rect.size.x, 0.18, rect.size.y), basalt, edge, 0.18)
        _add_decor_box(root, center + Vector3(0.0, 0.16, -rect.size.y * 0.5), Vector3(rect.size.x, 0.22, 0.24), edge, amber, 0.36)
        _add_decor_box(root, center + Vector3(0.0, 0.16, rect.size.y * 0.5), Vector3(rect.size.x, 0.22, 0.24), edge, amber, 0.36)
        _add_decor_box(root, center + Vector3(-rect.size.x * 0.5, 0.16, 0.0), Vector3(0.24, 0.22, rect.size.y), edge, amber, 0.36)
        _add_decor_box(root, center + Vector3(rect.size.x * 0.5, 0.16, 0.0), Vector3(0.24, 0.22, rect.size.y), edge, amber, 0.36)
        var bolt_step: float = maxf(3.0, rect.size.x / 5.0)
        for bolt_index in range(1, 5):
            _add_detail_bolt(root, Vector3(rect.position.x + float(bolt_index) * bolt_step, 0.19, rect.position.y + 0.42), amber)
            _add_detail_bolt(root, Vector3(rect.position.x + float(bolt_index) * bolt_step, 0.19, rect.position.y + rect.size.y - 0.42), amber)
    for segment in SAFE_PATH_SEGMENTS:
        var start: Vector2 = Vector2(segment[0])
        var finish: Vector2 = Vector2(segment[1])
        var delta: Vector2 = finish - start
        var midpoint: Vector3 = Vector3((start.x + finish.x) * 0.5, 0.15, (start.y + finish.y) * 0.5)
        var length: float = delta.length()
        var angle: float = rad_to_deg(atan2(delta.y, delta.x))
        _add_decor_box(root, midpoint, Vector3(length, 0.22, 7.2), Color("#30343f"), amber, 0.24, angle)
        _add_decor_box(root, midpoint + Vector3(0.0, 0.18, -3.05), Vector3(length, 0.14, 0.16), amber, amber, 0.58, angle)
        _add_decor_box(root, midpoint + Vector3(0.0, 0.18, 3.05), Vector3(length, 0.14, 0.16), amber, amber, 0.58, angle)

func _build_cliff_edges_visuals() -> void:
    # 每块安全甲板下方都有岩壁和分层断面；玩家从边缘离开后会在
    # 这些断面前完成受控下坠，熔岩海位于更低的 y=-4 附近。
    var root: Node3D = Node3D.new()
    root.name = "CliffEdgesVisuals"
    world_root.add_child(root)
    var basalt: Color = Color("#17151d")
    var basalt_edge: Color = Color("#4a3034")
    var magma: Color = Color("#e44722")
    for rect in SAFE_DECK_RECTS:
        var center_x: float = rect.position.x + rect.size.x * 0.5
        var center_z: float = rect.position.y + rect.size.y * 0.5
        var cliff_y: float = -1.82
        _add_decor_box(root, Vector3(center_x, cliff_y, rect.position.y - 0.20), Vector3(rect.size.x + 0.4, 3.55, 0.72), basalt, basalt_edge, 0.12)
        _add_decor_box(root, Vector3(center_x, cliff_y, rect.position.y + rect.size.y + 0.20), Vector3(rect.size.x + 0.4, 3.55, 0.72), basalt, basalt_edge, 0.12)
        _add_decor_box(root, Vector3(rect.position.x - 0.20, cliff_y, center_z), Vector3(0.72, 3.55, rect.size.y), basalt, basalt_edge, 0.12)
        _add_decor_box(root, Vector3(rect.position.x + rect.size.x + 0.20, cliff_y, center_z), Vector3(0.72, 3.55, rect.size.y), basalt, basalt_edge, 0.12)
        _add_decor_box(root, Vector3(center_x, -3.48, rect.position.y - 0.18), Vector3(rect.size.x, 0.10, 0.16), magma, magma, 0.48)
        _add_decor_box(root, Vector3(center_x, -3.48, rect.position.y + rect.size.y + 0.18), Vector3(rect.size.x, 0.10, 0.16), magma, magma, 0.48)
        for strata_index in 3:
            var strata_y: float = -0.78 - float(strata_index) * 0.88
            _add_decor_box(root, Vector3(center_x, strata_y, rect.position.y - 0.59), Vector3(rect.size.x * (0.86 - float(strata_index) * 0.10), 0.12, 0.10), basalt_edge, magma, 0.20)
        # 断面边缘使用错落的低多边形岩柱和退台，避免从玩家镜头看起来像一块
        # 规则盒子。岩柱只承担轮廓和层次，不加入玩法碰撞。
        for rock_index in range(4):
            var rock_x: float = rect.position.x + rect.size.x * (0.14 + float(rock_index) * 0.24)
            var front_height: float = 1.0 + float((rock_index + int(rect.position.x)) % 3) * 0.34
            var back_height: float = 0.92 + float((rock_index + 1) % 3) * 0.38
            _add_cliff_spire(root, Vector3(rock_x, -0.46 - front_height * 0.5, rect.position.y - 0.66), 0.42 + float(rock_index % 2) * 0.12, front_height, basalt_edge, rock_index * 11.0)
            _add_cliff_spire(root, Vector3(rock_x, -0.46 - back_height * 0.5, rect.position.y + rect.size.y + 0.66), 0.38 + float((rock_index + 1) % 2) * 0.13, back_height, basalt_edge, -rock_index * 9.0)
        for ledge_index in range(3):
            var ledge_y: float = -0.62 - float(ledge_index) * 0.96
            var ledge_width: float = rect.size.x * (0.78 - float(ledge_index) * 0.12)
            _add_decor_box(root, Vector3(center_x - 0.18, ledge_y, rect.position.y - 0.74), Vector3(ledge_width, 0.16, 0.38), basalt_edge, Color("#9e3a2d"), 0.12, float(ledge_index * 3 - 2))
            _add_decor_box(root, Vector3(center_x + 0.18, ledge_y, rect.position.y + rect.size.y + 0.74), Vector3(ledge_width, 0.16, 0.38), basalt_edge, Color("#9e3a2d"), 0.12, float(-ledge_index * 3 + 2))
        for side_index in range(2):
            var rock_z: float = rect.position.y + rect.size.y * (0.28 + float(side_index) * 0.44)
            _add_cliff_spire(root, Vector3(rect.position.x - 0.66, -0.58, rock_z), 0.40, 1.15 + float(side_index) * 0.24, basalt_edge, 7.0)
            _add_cliff_spire(root, Vector3(rect.position.x + rect.size.x + 0.66, -0.58, rock_z), 0.40, 1.02 + float(side_index) * 0.28, basalt_edge, -7.0)
    for segment in SAFE_PATH_SEGMENTS:
        var start: Vector2 = Vector2(segment[0])
        var finish: Vector2 = Vector2(segment[1])
        var delta: Vector2 = finish - start
        var midpoint: Vector3 = Vector3((start.x + finish.x) * 0.5, -1.62, (start.y + finish.y) * 0.5)
        var length: float = delta.length()
        var angle: float = rad_to_deg(atan2(delta.y, delta.x))
        _add_decor_box(root, midpoint, Vector3(length, 3.10, 0.44), basalt, basalt_edge, 0.12, angle)
        _add_decor_box(root, midpoint + Vector3(0.0, -1.70, 0.0), Vector3(length, 0.10, 0.16), magma, magma, 0.42, angle)

func _add_cliff_spire(parent: Node3D, point: Vector3, radius: float, height: float, color: Color, twist: float) -> void:
    var rock: MeshInstance3D = MeshInstance3D.new()
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = radius * 0.58
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 6
    rock.mesh = mesh
    rock.position = point
    rock.rotation_degrees = Vector3(0.0, twist, (twist * 0.37) - 4.0)
    rock.material_override = _material(color, Color("#5e2729"), 0.08)
    parent.add_child(rock)

func _build_cave_backdrop_visuals() -> void:
    # 洞穴壳体只做视觉背景，不参与玩家碰撞。墙体围住工厂，顶部拱梁与
    # 钟乳石有明确连接关系，避免上一版出现漂浮椭圆岩块的穿模观感。
    var root: Node3D = Node3D.new()
    root.name = "CaveBackdropVisuals"
    world_root.add_child(root)
    var wall: Color = Color("#1b151d")
    var wall_edge: Color = Color("#3c252a")
    var fissure: Color = Color("#b4452a")
    _add_decor_box(root, Vector3(0.0, 12.0, -49.0), Vector3(166.0, 28.0, 3.0), wall, fissure, 0.18)
    # 侧壁放在可玩地图外缘；反应堆审阅镜头位于 x=82，不能让墙体夹在
    # 镜头和地标之间，否则会得到整张黑屏。
    _add_decor_box(root, Vector3(-90.0, 12.0, 0.0), Vector3(3.0, 28.0, 112.0), wall, fissure, 0.18)
    _add_decor_box(root, Vector3(90.0, 12.0, 0.0), Vector3(3.0, 28.0, 112.0), wall, fissure, 0.18)
    # 分段岩层，让墙面不再是纯色盒子。
    for index in 8:
        var x: float = -70.0 + float(index) * 20.0
        var z: float = -47.2
        _add_decor_box(root, Vector3(x, 4.0 + float(index % 3) * 2.2, z), Vector3(13.0, 0.26, 0.24), wall_edge, fissure, 0.34, -8.0 if index % 2 == 0 else 7.0)
        _add_decor_box(root, Vector3(x + 4.0, 15.0 - float(index % 2) * 2.0, z), Vector3(8.0, 0.18, 0.22), wall_edge, fissure, 0.28, 11.0)
    # 顶部三道拱梁与两侧立柱相连，形成真实洞顶尺度。
    for index in 3:
        var x: float = -48.0 + float(index) * 48.0
        _add_decor_box(root, Vector3(x, 23.0, -25.0), Vector3(1.2, 23.0, 1.2), wall_edge, fissure, 0.20)
        _add_decor_box(root, Vector3(x, 23.0, 25.0), Vector3(1.2, 23.0, 1.2), wall_edge, fissure, 0.20)
        _add_decor_box(root, Vector3(x, 29.0, 0.0), Vector3(1.0, 1.2, 52.0), wall_edge, fissure, 0.25)
        _add_detail_bolt(root, Vector3(x, 28.2, -24.0), fissure)
        _add_detail_bolt(root, Vector3(x, 28.2, 24.0), fissure)
    # 附着在洞顶梁下方的锥形钟乳石；它们不穿过主厂区镜头高度。
    for index in 12:
        var x: float = -66.0 + float(index) * 12.0
        var z: float = -39.0 if index % 2 == 0 else 39.0
        var height: float = 3.5 + float(index % 3) * 1.2
        var stalactite: MeshInstance3D = MeshInstance3D.new()
        var stalactite_mesh: CylinderMesh = CylinderMesh.new()
        stalactite_mesh.top_radius = 1.25
        stalactite_mesh.bottom_radius = 0.16
        stalactite_mesh.height = height
        stalactite_mesh.radial_segments = 10
        stalactite.mesh = stalactite_mesh
        stalactite.position = Vector3(x, 27.0 - height * 0.5, z)
        stalactite.rotation_degrees.z = -5.0 if index % 2 == 0 else 4.0
        stalactite.material_override = _material(Color("#322126"), fissure, 0.16)
        root.add_child(stalactite)

func _build_rock_formation(center: Vector3, size: Vector3) -> void:
    var formation: Node3D = Node3D.new()
    formation.position = center
    var rock_colors: Array[Color] = [Color("#443137"), Color("#593d3b"), Color("#704641")]
    for index in 3:
        var rock: MeshInstance3D = MeshInstance3D.new()
        var rock_mesh: CylinderMesh = CylinderMesh.new()
        rock_mesh.top_radius = size.x * (0.24 - float(index) * 0.035)
        rock_mesh.bottom_radius = size.x * (0.38 - float(index) * 0.035)
        rock_mesh.height = size.y * (0.65 + float(index) * 0.16)
        rock.mesh = rock_mesh
        rock.position = Vector3((float(index) - 1.0) * size.x * 0.28, rock_mesh.height * 0.5, (float(index % 2) - 0.5) * size.z * 0.22)
        rock.rotation_degrees = Vector3(0.0, float(index * 27), float(index - 1) * 4.0)
        rock.material_override = _material(rock_colors[index], Color("#8f514b"), 0.16)
        formation.add_child(rock)
    world_root.add_child(formation)

func _build_perimeter() -> void:
    var walls: Array = [
        [Vector3(0.0, 2.0, -46.0), Vector3(150.0, 4.0, 1.2)],
        [Vector3(0.0, 2.0, 46.0), Vector3(150.0, 4.0, 1.2)],
        [Vector3(-76.0, 2.0, 0.0), Vector3(1.2, 4.0, 92.0)],
        [Vector3(76.0, 2.0, 0.0), Vector3(1.2, 4.0, 92.0)]
    ]
    for entry in walls:
        _add_box_obstacle(Vector3(entry[0]), Vector3(entry[1]), Color("#28365c"))

func _build_tracks() -> void:
    var track_points: Array[Vector3] = [
        Vector3(-54.0, 0.08, 18.0),
        Vector3(-27.0, 0.08, 18.0),
        Vector3(0.0, 0.08, 2.0),
        Vector3(27.0, 0.08, -14.0),
        Vector3(55.0, 0.08, -14.0)
    ]
    for index in track_points.size() - 1:
        var start: Vector3 = track_points[index]
        var finish: Vector3 = track_points[index + 1]
        var midpoint: Vector3 = (start + finish) * 0.5
        var length: float = Vector2(start.x, start.z).distance_to(Vector2(finish.x, finish.z))
        var rail: MeshInstance3D = MeshInstance3D.new()
        var rail_mesh: BoxMesh = BoxMesh.new()
        rail_mesh.size = Vector3(length, 0.18, 0.45)
        rail.mesh = rail_mesh
        rail.position = midpoint + Vector3(0.0, 0.12, 1.8)
        world_root.add_child(rail)
        rail.look_at(Vector3(finish.x, rail.position.y, finish.z), Vector3.UP)
        rail.material_override = _material(Color("#343b63"), Color("#6c7cff"), 0.8)
        var rail_pair: MeshInstance3D = rail.duplicate() as MeshInstance3D
        rail_pair.position = midpoint + Vector3(0.0, 0.12, -1.8)
        world_root.add_child(rail_pair)
        var sleeper: MeshInstance3D = MeshInstance3D.new()
        var sleeper_mesh: BoxMesh = BoxMesh.new()
        sleeper_mesh.size = Vector3(length, 0.1, 5.2)
        sleeper.mesh = sleeper_mesh
        sleeper.position = midpoint
        world_root.add_child(sleeper)
        sleeper.look_at(Vector3(finish.x, sleeper.position.y, finish.z), Vector3.UP)
        sleeper.material_override = _material(Color("#182342"), Color("#3155a8"), 0.3)
        for sleeper_index in 5:
            var sleeper_ratio: float = (float(sleeper_index) + 0.5) / 5.0 - 0.5
            var sleeper_point: Vector3 = midpoint + Vector3(length * sleeper_ratio, 0.2, 0.0)
            _add_detail_bolt(world_root, sleeper_point + Vector3(0.0, 0.05, 1.8), Color("#72dce9"))
            _add_detail_bolt(world_root, sleeper_point + Vector3(0.0, 0.05, -1.8), Color("#72dce9"))
        var signal_light: MeshInstance3D = MeshInstance3D.new()
        var signal_mesh: CylinderMesh = CylinderMesh.new()
        signal_mesh.top_radius = 0.18
        signal_mesh.bottom_radius = 0.25
        signal_mesh.height = 1.0
        signal_light.mesh = signal_mesh
        signal_light.position = start + Vector3(0.0, 0.55, 3.0)
        signal_light.material_override = _glow_material(Color("#ffca68"), 1.35)
        world_root.add_child(signal_light)

func _build_modules() -> void:
    for module_value in modules:
        var module: Dictionary = module_value
        var id: int = int(module["id"])
        var root: Node3D = Node3D.new()
        root.name = "MovingEnergyModule_%d" % id
        root.position = Vector3(module["position"])
        world_root.add_child(root)
        module_nodes[id] = root
        station_nodes[id] = root
        bridge_nodes[id] = root
        _create_module_platform(root)
        _create_module_mechanisms(root, module)
        _create_module_label(root, module)
        _refresh_module_visual(module)


func _build_depth_setpieces() -> void:
    var gantry_positions: Array[Vector3] = [
        Vector3(-24.0, 0.0, 6.0),
        Vector3(10.0, 0.0, -8.0),
        Vector3(45.0, 0.0, -8.0)
    ]
    for index in gantry_positions.size():
        var center: Vector3 = gantry_positions[index]
        var gantry: Node3D = Node3D.new()
        gantry.name = "DepthGantry_%d" % (index + 1)
        gantry.position = center
        var left_pillar: MeshInstance3D = MeshInstance3D.new()
        var pillar_mesh: BoxMesh = BoxMesh.new()
        pillar_mesh.size = Vector3(0.9, 7.0, 0.9)
        left_pillar.mesh = pillar_mesh
        left_pillar.position = Vector3(-5.5, 3.5, 1.8)
        left_pillar.material_override = _material(Color("#31406e"), Color("#617dce"), 0.65)
        gantry.add_child(left_pillar)
        var right_pillar: MeshInstance3D = left_pillar.duplicate() as MeshInstance3D
        right_pillar.position = Vector3(5.5, 3.5, 1.8)
        gantry.add_child(right_pillar)
        var overhead: MeshInstance3D = MeshInstance3D.new()
        var overhead_mesh: BoxMesh = BoxMesh.new()
        overhead_mesh.size = Vector3(12.0, 0.7, 1.0)
        overhead.mesh = overhead_mesh
        overhead.position = Vector3(0.0, 6.7, 1.8)
        overhead.material_override = _glow_material(Color("#5f6dd4"), 0.85)
        gantry.add_child(overhead)
        var ring: MeshInstance3D = MeshInstance3D.new()
        var ring_mesh: TorusMesh = TorusMesh.new()
        # 纵深机械门保留轮廓，但缩小到不会盖住肩后角色和当前交互设备。
        ring_mesh.inner_radius = 1.18
        ring_mesh.outer_radius = 1.32
        ring.mesh = ring_mesh
        ring.position = Vector3(0.0, 5.1, -1.0)
        ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
        ring.material_override = _glow_material(Color("#48dff0"), 0.58)
        gantry.add_child(ring)
        gantry.add_child(_label3d("纵深机械门 %d" % (index + 1), Vector3(0.0, 7.7, 1.8), Color("#b9d8ff")))
        world_root.add_child(gantry)

    for index in 3:
        var catwalk: MeshInstance3D = MeshInstance3D.new()
        var catwalk_mesh: BoxMesh = BoxMesh.new()
        catwalk_mesh.size = Vector3(18.0, 0.22, 1.8)
        catwalk.mesh = catwalk_mesh
        catwalk.position = Vector3(-28.0 + float(index) * 31.0, 3.1, -12.0 + float(index % 2) * 9.0)
        catwalk.rotation_degrees.y = -12.0 if index % 2 == 0 else 12.0
        catwalk.material_override = _material(Color("#334777"), Color("#768de7"), 0.75)
        world_root.add_child(catwalk)
        var catwalk_edge: MeshInstance3D = MeshInstance3D.new()
        var edge_mesh: BoxMesh = BoxMesh.new()
        edge_mesh.size = Vector3(18.0, 0.12, 0.12)
        catwalk_edge.mesh = edge_mesh
        catwalk_edge.position = catwalk.position + Vector3(0.0, 0.32, 0.9)
        catwalk_edge.rotation_degrees.y = catwalk.rotation_degrees.y
        catwalk_edge.material_override = _glow_material(Color("#d4a9ff"), 1.0)
        world_root.add_child(catwalk_edge)
        _add_static_platform_collision(
            "ResonanceCatwalkCollision_%d" % (index + 1),
            catwalk.position,
            Vector3(18.0, 0.22, 1.8),
            catwalk.rotation_degrees.y
        )
        # 每条高位维护桥都有一上一下两条检修坡道，避免高层只存在视觉模型。
        var ramp_center_x: float = catwalk.position.x - 13.5
        var ramp_y: float = 1.55
        _add_static_platform_collision(
            "ResonanceCatwalkRampUp_%d" % (index + 1),
            Vector3(ramp_center_x, ramp_y, catwalk.position.z),
            Vector3(9.0, 0.24, 2.8),
            catwalk.rotation_degrees.y,
            -19.0
        )
        _add_ramp_visual(Vector3(ramp_center_x, ramp_y, catwalk.position.z), Vector3(9.0, 0.24, 2.8), catwalk.rotation_degrees.y, -19.0)
        _add_static_platform_collision(
            "ResonanceCatwalkRampDown_%d" % (index + 1),
            Vector3(catwalk.position.x + 13.5, ramp_y, catwalk.position.z),
            Vector3(9.0, 0.24, 2.8),
            catwalk.rotation_degrees.y,
            19.0
        )
        _add_ramp_visual(Vector3(catwalk.position.x + 13.5, ramp_y, catwalk.position.z), Vector3(9.0, 0.24, 2.8), catwalk.rotation_degrees.y, 19.0)
        _add_hydraulic_strut(world_root, catwalk.position + Vector3(-7.0, -0.05, 0.0), catwalk.position + Vector3(-5.0, 2.1, 0.0), Color("#9a83ff"))
        _add_hydraulic_strut(world_root, catwalk.position + Vector3(7.0, -0.05, 0.0), catwalk.position + Vector3(5.0, 2.1, 0.0), Color("#9a83ff"))
        for bolt_index in 6:
            var bolt_x: float = -7.5 + float(bolt_index) * 3.0
            _add_detail_bolt(world_root, catwalk.position + Vector3(bolt_x, 0.28, 0.82), Color("#d6b0ff"))

func _add_static_platform_collision(node_name: String, point: Vector3, size: Vector3, rotation_y: float = 0.0, rotation_z: float = 0.0) -> void:
    var body: StaticBody3D = StaticBody3D.new()
    body.name = node_name
    body.position = point
    body.rotation_degrees = Vector3(0.0, rotation_y, rotation_z)
    body.collision_layer = 2
    body.collision_mask = 1
    var shape: CollisionShape3D = CollisionShape3D.new()
    var box: BoxShape3D = BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    world_root.add_child(body)

func _build_vertical_platform_collisions() -> void:
    # 登高网络只有三条坡道，其余平台靠同高度直接相接：
    #   西侧检修平台 →[坡道]→ 5.4 米中层观景桥 →[东侧下坡]→ 反应堆甲板 →[坡道]→ 11.5 米竖井观察台
    # 坡道必须朝平台方向升高：rotation_z 为正时 +X 端抬高，所以西侧坡道取正、
    # 东侧坡道取负。旧的实现把两条坡道的方向写反了，玩家走不到平台。
    var catwalk_specs: Array = [
        {"index": 1, "position": Vector3(-28.0, 5.4, -12.0), "ramp_west": true},
        {"index": 2, "position": Vector3(3.0, 3.1, -3.0), "ramp_west": false},
        {"index": 3, "position": Vector3(34.0, 5.4, -12.0), "ramp_west": false},
    ]
    for spec in catwalk_specs:
        var index: int = int(spec["index"])
        var catwalk_position: Vector3 = spec["position"]
        var deck_size: Vector3 = Vector3(18.0, 0.22, 1.8)
        _add_static_platform_collision("ResonanceCatwalkCollision_%d" % index, catwalk_position, deck_size)
        _add_bridge_visual(catwalk_position, deck_size, 0.0)
        _add_deck_fences("ResonanceCatwalkCollision_%d" % index, catwalk_position, deck_size)
        if bool(spec["ramp_west"]):
            var ramp_length: float = 13.0
            # 坡道必须从平台西边缘往外接，不能从平台中心起算，
            # 否则整段坡道会钻到平台下方，玩家爬到一半撞上平台底面。
            var deck_half: float = deck_size.x * 0.5
            var ramp_center: Vector3 = Vector3(catwalk_position.x - deck_half - ramp_length * 0.5, catwalk_position.y * 0.5, catwalk_position.z)
            var ramp_size: Vector3 = Vector3(ramp_length, 0.24, 2.8)
            var ramp_tilt: float = rad_to_deg(atan2(catwalk_position.y - 0.1, ramp_length))
            _add_static_platform_collision("ResonanceCatwalkRamp_1", ramp_center, ramp_size, 0.0, ramp_tilt)
            _add_ramp_visual(ramp_center, ramp_size, 0.0, ramp_tilt)
    _build_observation_bridge()

func _add_deck_fences(prefix: String, center: Vector3, deck_size: Vector3, cap_east: bool = false) -> void:
    # 高架平台两侧加矮护栏碰撞，避免玩家走直线时直接掉进熔岩；
    # 坡道接入的一端保持开放。
    var half_z: float = deck_size.z * 0.5 - 0.1
    for side in [-1.0, 1.0]:
        _add_static_platform_collision(
            "%s_Fence_%s" % [prefix, "N" if side > 0.0 else "S"],
            center + Vector3(0.0, 0.55, side * half_z),
            Vector3(deck_size.x, 1.1, 0.16)
        )
    if cap_east:
        _add_static_platform_collision(
            "%s_Fence_E" % prefix,
            center + Vector3(deck_size.x * 0.5 - 0.1, 0.55, 0.0),
            Vector3(0.16, 1.1, deck_size.z)
        )

func _build_observation_bridge() -> void:
    var center: Vector3 = Vector3(0.0, 5.4, -12.0)
    var size: Vector3 = Vector3(56.0, 0.26, 2.2)
    _add_static_platform_collision("ResonanceObservationBridgeCollision", center, size)
    _add_bridge_visual(center, size, 0.0)
    _add_deck_fences("ResonanceObservationBridgeCollision", center, size)
    for index in 5:
        var pylon: Vector3 = Vector3(-22.0 + float(index) * 11.0, 0.0, -12.0)
        _add_hydraulic_strut(world_root, pylon, pylon + Vector3(0.0, 5.2, 0.0), Color("#7fa8ff"))
    # 西侧坡道落在熔岩上，需要一块落地检修平台承接，否则下桥即阵亡。
    var landing: Vector3 = Vector3(-46.0, 0.0, -12.0)
    _add_static_platform_collision("ResonanceBridgeLandingCollision", landing, Vector3(14.0, 0.4, 9.0))
    _add_bridge_visual(landing + Vector3(0.0, 0.2, 0.0), Vector3(14.0, 0.4, 9.0), 0.0)
    # 东侧下坡：桥在 x=28，坡道必须朝 -X 升高，所以 rotation_z 取负。
    var ramp_tilt: float = -rad_to_deg(atan2(5.3, 13.0))
    _add_static_platform_collision(
        "ResonanceObservationBridgeRamp",
        Vector3(34.5, 2.7, -12.0),
        Vector3(13.0, 0.24, 2.4),
        0.0,
        ramp_tilt
    )
    _add_ramp_visual(Vector3(34.5, 2.7, -12.0), Vector3(13.0, 0.24, 2.4), 0.0, ramp_tilt)
    world_root.add_child(_label3d("中层观景桥", Vector3(0.0, 7.0, -12.0), Color("#bcd4ff")))
    # 路线标识：入口平台上的高亮门柱与方向标牌，避免玩家找不到上楼位置。
    for side in [-1.0, 1.0]:
        var post: Vector3 = landing + Vector3(side * 3.6, 0.2, 3.6)
        _add_hydraulic_strut(world_root, post, post + Vector3(0.0, 4.2, 0.0), Color("#ffd066"))
    world_root.add_child(_label3d("↑ 中层观景桥入口", landing + Vector3(0.0, 4.8, 3.6), Color("#ffe3a3")))
    world_root.add_child(_label3d("← 上层入口", Vector3(-40.0, 3.2, -9.0), Color("#ffe3a3")))
    _build_shaft_observation_deck()

func _build_shaft_observation_deck() -> void:
    # 高位竖井观察台：从反应堆甲板经坡道登上 11.5 米平台。
    # 平台必须避开反应堆塔基础（半径约 11 米）与塔身，否则相机会钻进塔内。
    var deck: Vector3 = Vector3(70.0, 11.5, -26.0)
    var deck_size: Vector3 = Vector3(12.0, 0.4, 4.0)
    _add_static_platform_collision("ResonanceShaftDeckCollision", deck, deck_size)
    _add_bridge_visual(deck, deck_size, 0.0)
    _add_deck_fences("ResonanceShaftDeckCollision", deck, deck_size, true)
    for corner_x in [-5.0, 5.0]:
        _add_hydraulic_strut(world_root, deck + Vector3(corner_x, -11.5, 0.0), deck + Vector3(corner_x, -0.2, 0.0), Color("#9a83ff"))
    # 观察台在 x=70，坡道朝 +X 升高，因此 rotation_z 取正；
    # 低端落在 y≈0.2，避免出现 0.8 米高的台阶让玩家上不去。
    var ramp_length: float = 24.0
    var ramp_rise: float = 11.2
    var ramp_tilt: float = rad_to_deg(atan2(ramp_rise, sqrt(ramp_length * ramp_length - ramp_rise * ramp_rise)))
    var ramp_size: Vector3 = Vector3(ramp_length, 0.3, 3.2)
    var ramp_center: Vector3 = Vector3(52.5, 0.2 + ramp_rise * 0.5, -26.0)
    _add_static_platform_collision("ResonanceShaftRampCollision", ramp_center, ramp_size, 0.0, ramp_tilt)
    _add_ramp_visual(ramp_center, ramp_size, 0.0, ramp_tilt)
    world_root.add_child(_label3d("高位竖井观察台", Vector3(70.0, 13.6, -26.0), Color("#d8c4ff")))
    world_root.add_child(_label3d("↑ 高位观察台入口", Vector3(40.5, 3.0, -26.0), Color("#d8c4ff")))

func _add_bridge_visual(point: Vector3, size: Vector3, rotation_y: float) -> void:
    var deck: MeshInstance3D = MeshInstance3D.new()
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    deck.mesh = mesh
    deck.position = point
    deck.rotation_degrees = Vector3(0.0, rotation_y, 0.0)
    deck.material_override = _material(Color("#31436f"), Color("#7d95e6"), 0.62)
    world_root.add_child(deck)
    for rail_side in [-1.0, 1.0]:
        var handrail: MeshInstance3D = MeshInstance3D.new()
        var rail_mesh: BoxMesh = BoxMesh.new()
        rail_mesh.size = Vector3(size.x, 0.10, 0.10)
        handrail.mesh = rail_mesh
        handrail.position = point + Vector3(0.0, 0.62, rail_side * (size.z * 0.5 - 0.10))
        handrail.rotation_degrees = Vector3(0.0, rotation_y, 0.0)
        handrail.material_override = _glow_material(Color("#a8c4ff"), 0.85)
        world_root.add_child(handrail)

func _add_ramp_visual(point: Vector3, size: Vector3, rotation_y: float, rotation_z: float) -> void:
    var ramp: MeshInstance3D = MeshInstance3D.new()
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    ramp.mesh = mesh
    ramp.position = point
    ramp.rotation_degrees = Vector3(0.0, rotation_y, rotation_z)
    ramp.material_override = _material(Color("#384974"), Color("#6f8be1"), 0.58)
    world_root.add_child(ramp)
    for rail_side in [-1.0, 1.0]:
        var handrail: MeshInstance3D = MeshInstance3D.new()
        var handrail_mesh: BoxMesh = BoxMesh.new()
        handrail_mesh.size = Vector3(size.x, 0.12, 0.12)
        handrail.mesh = handrail_mesh
        handrail.position = point + Vector3(0.0, 0.75, rail_side * (size.z * 0.5 - 0.12))
        handrail.rotation_degrees = Vector3(0.0, rotation_y, rotation_z)
        handrail.material_override = _glow_material(Color("#d6b3ff"), 0.72)
        world_root.add_child(handrail)

func _build_industrial_set_dressing() -> void:
    _build_zone_plate(Vector3(-54.0, 0.0, 18.0), Vector3(24.0, 0.0, 18.0), Color("#17345c"), Color("#47dfff"), "进料对接区")
    _build_zone_plate(Vector3(0.0, 0.0, 2.0), Vector3(28.0, 0.0, 20.0), Color("#252454"), Color("#a37bff"), "升降分流区")
    _build_zone_plate(Vector3(36.0, 0.0, -14.0), Vector3(25.0, 0.0, 20.0), Color("#49314d"), Color("#ffca68"), "反应堆接驳区")
    _build_zone_plate(Vector3(56.0, 0.0, -17.0), Vector3(34.0, 0.0, 28.0), Color("#183f4b"), Color("#79e9b7"), "反应堆甲板")

    # The authored processing GLBs replace the former broad procedural trusses,
    # pipes and cargo racks.  Keep the zone plates as navigational ground wear.
    if ResourceLoader.exists(RESONANCE_PROCESSING_ZONE_PATH):
        return

    var truss_positions: Array[Vector3] = [
        Vector3(-48.0, 0.0, 18.0),
        Vector3(-12.0, 0.0, 7.0),
        Vector3(24.0, 0.0, -9.0),
        Vector3(52.0, 0.0, -17.0)
    ]
    for index in truss_positions.size():
        _build_overhead_truss(truss_positions[index], 14.0 if index < 3 else 18.0, 6.5 if index < 3 else 8.0)

    var pipe_segments: Array[Array] = [
        [Vector3(-72.0, 4.2, 11.0), Vector3(-35.0, 4.2, 11.0)],
        [Vector3(-25.0, 5.0, 8.0), Vector3(4.0, 5.0, -5.0)],
        [Vector3(18.0, 4.4, -5.0), Vector3(47.0, 4.4, -16.0)],
        [Vector3(45.0, 2.8, -28.0), Vector3(68.0, 2.8, -28.0)]
    ]
    for segment in pipe_segments:
        _add_decor_pipe(Vector3(segment[0]), Vector3(segment[1]), Color("#6171a8"), Color("#8fb6ff"))

    _build_cargo_rack(Vector3(-45.0, 0.0, 29.0), Color("#e68b54"), "磁力货箱仓")
    _build_cargo_rack(Vector3(7.0, 0.0, 28.0), Color("#8e76db"), "备用线圈仓")
    _build_cargo_rack(Vector3(41.0, 0.0, 12.0), Color("#5ed7b2"), "冷却单元仓")
    if not ResourceLoader.exists(RESONANCE_REACTOR_TOWER_PATH):
        _build_reactor_tower(Vector3(55.0, 0.0, -17.0))

    var hazard_positions: Array[Vector3] = [
        Vector3(-22.0, 0.0, 25.0),
        Vector3(14.0, 0.0, 15.0),
        Vector3(37.0, 0.0, -2.0),
        Vector3(68.0, 0.0, -2.0)
    ]
    for point in hazard_positions:
        _build_hazard_marker(point)

func _visual_collision_anchors() -> Array[Vector3]:
    var anchors: Array[Vector3] = []
    for key in heat_valve_positions.keys():
        anchors.append(Vector3(heat_valve_positions[key]) + Vector3.UP)
    for module in modules:
        for field in ["rail_position", "clamp_position", "support_position", "safety_position", "route_position", "freight_position"]:
            if module.has(field):
                anchors.append(Vector3(module[field]) + Vector3.UP)
    anchors.append(SUPPORT_RELAY_LOW_POSITION + Vector3.UP)
    anchors.append(SUPPORT_RELAY_HIGH_POSITION + Vector3.UP)
    for challenge in reactor_challenges:
        for field in ["lower_position", "upper_position", "left_position", "right_position", "center_position", "coolant_position", "coolant_socket_position", "stabilizer_position"]:
            if challenge.has(field):
                anchors.append(Vector3(challenge[field]) + Vector3.UP)
    if core_node != null:
        anchors.append(core_node.global_position + Vector3.UP)
    if extraction_node != null:
        anchors.append(extraction_node.position + Vector3.UP)
    return anchors

func _build_visual_collision() -> void:
    # 主场景 GLB 只有视觉网格，没有碰撞。这里为“大结构 + 交互装置本体”生成盒体：
    #   - 高度 ≥ 0.45 米：包含热阀基座、模块终端、镜面座等 0.9 米级装置
    #   - 水平最小边 ≥ 0.35 米：排除管线、光带、螺栓
    #   - 顶面高于 0.45 米
    # 交互锚点不跳过结构本身，而是检查“锚点周围是否还有可站立的空位”：
    # 只要在交互半径内存在不被任何碰撞盒覆盖的站位，装置就可以是实体。
    var solid_roots: Array = []
    for key in ["ArtResonanceMasterScene", "ArtReactorTower",
            "ArtProcessing_Infeed", "ArtProcessing_Lift", "ArtProcessing_ReactorDeck",
            "ArtMaintenanceFacility", "ArtFactorySpine"]:
        var node: Node = art_asset_nodes.get(key) as Node
        if node != null and is_instance_valid(node):
            solid_roots.append(node)
    var anchors: Array[Vector3] = _visual_collision_anchors()
    var protected: Array[AABB] = _protected_walk_volumes()
    var candidates: Array[AABB] = []
    for root_node in solid_roots:
        for child in (root_node as Node).find_children("*", "MeshInstance3D", true, false):
            var mesh: MeshInstance3D = child as MeshInstance3D
            if mesh == null or not mesh.is_visible_in_tree() or mesh.mesh == null:
                continue
            var bounds: AABB = mesh.global_transform * mesh.get_aabb()
            if bounds.size.y < VISUAL_COLLISION_MIN_HEIGHT:
                continue
            if minf(bounds.size.x, bounds.size.z) < VISUAL_COLLISION_MIN_WIDTH:
                continue
            if bounds.position.y + bounds.size.y < VISUAL_COLLISION_MIN_TOP:
                continue
            var blocks_walk: bool = false
            for volume in protected:
                if bounds.intersects(volume.grow(0.35)):
                    blocks_walk = true
                    break
            if blocks_walk:
                continue
            candidates.append(bounds)
    candidates.sort_custom(func(a: AABB, b: AABB) -> bool: return a.get_volume() > b.get_volume())
    var built: int = 0
    var placed: Array[AABB] = []
    for bounds in candidates:
        if built >= VISUAL_COLLISION_LIMIT:
            break
        var touching: Array[Vector3] = []
        for anchor in anchors:
            if bounds.grow(0.8).has_point(anchor):
                touching.append(anchor)
        if not touching.is_empty():
            var reachable: bool = false
            for anchor in touching:
                if _anchor_has_standing_room(anchor, bounds, placed):
                    reachable = true
                    break
            if not reachable:
                continue
        var body: StaticBody3D = StaticBody3D.new()
        body.name = "VisualCollider_%d" % built
        body.collision_layer = 2
        body.collision_mask = 1
        var collider: CollisionShape3D = CollisionShape3D.new()
        var box_shape: BoxShape3D = BoxShape3D.new()
        box_shape.size = bounds.size
        collider.shape = box_shape
        collider.position = bounds.get_center()
        body.add_child(collider)
        world_root.add_child(body)
        placed.append(bounds)
        built += 1
    print("RESONANCE_VISUAL_COLLISION: %d" % built)

func _protected_walk_volumes() -> Array[AABB]:
    # 登高路线（坡道、桥面、观察台、落位平台）不能被视觉碰撞盒截断。
    var volumes: Array[AABB] = []
    var prefixes: Array[String] = [
        "ResonanceCatwalk", "ResonanceObservationBridge", "ResonanceShaft",
        "ResonanceBridgeLanding"
    ]
    for child in world_root.get_children():
        if not (child is StaticBody3D):
            continue
        var node_name: String = String(child.name)
        var matched: bool = false
        for prefix in prefixes:
            if node_name.begins_with(prefix):
                matched = true
                break
        if not matched:
            continue
        var shape_node: CollisionShape3D = (child as Node).get_child(0) as CollisionShape3D
        if shape_node == null:
            continue
        var box: BoxShape3D = shape_node.shape as BoxShape3D
        if box == null:
            continue
        var body: Node3D = child as Node3D
        # 坡道带旋转，直接用未旋转的盒体会漏掉升高段，这里按变换后的包围盒计算。
        var shape_transform: Transform3D = body.global_transform * shape_node.transform
        var local_box: AABB = AABB(-box.size * 0.5, box.size)
        volumes.append(shape_transform * local_box)
    return volumes

func _anchor_has_standing_room(anchor: Vector3, candidate: AABB, placed: Array[AABB]) -> bool:
    # 以交互半径内的一圈采样点判断“玩家还能不能站到装置旁边”。
    var radius: float = 1.9
    for index in 8:
        var angle: float = TAU * float(index) / 8.0
        var probe: Vector3 = anchor + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
        var probe_point: Vector3 = Vector3(probe.x, 1.0, probe.z)
        if candidate.grow(0.35).has_point(probe_point):
            continue
        var blocked: bool = false
        for other in placed:
            if other.grow(0.35).has_point(probe_point):
                blocked = true
                break
        if not blocked:
            return true
    return false

func _instance_resonance_art(path: String, node_name: String, point: Vector3, scale_value: Vector3 = Vector3.ONE, rotation_y: float = 0.0) -> Node3D:
    if not ResourceLoader.exists(path):
        return null
    var packed: PackedScene = ResourceLoader.load(path) as PackedScene
    if packed == null:
        return null
    var instance: Node3D = packed.instantiate() as Node3D
    if instance == null:
        return null
    instance.name = node_name
    instance.position = point
    instance.scale = scale_value
    instance.rotation_degrees.y = rotation_y
    instance.set_meta("resonance_visual_asset", path)
    world_root.add_child(instance)
    if node_name == "ArtCavernShell":
        # 原始壳体的长条屋脊和椭圆钟乳石在总览中会读成悬空木杆；
        # 这里始终隐藏旧壳体，改由 Blender 主场景提供与工厂尺度一致的
        # 洞壁、拱梁和锚固岩柱。
        instance.visible = false
    elif node_name == "ArtSurfaceWest" or node_name == "ArtSurfaceEast":
        # 旧地表资产的宽面纹理在总览中会产生密集的扫描条；岩层细节已由
        # CaveBackdropVisuals 和区域地貌节点承担，保留它们的运行时注册但
        # 不让两块宽面覆盖整个熔岩底盘。
        instance.visible = false
    art_asset_nodes[node_name] = instance
    return instance

func _build_art_asset_overlays() -> void:
    # The authored GLBs supply close-up industrial geometry.  Gameplay meshes,
    # collision bodies and interaction points remain owned by this stage.
    _instance_resonance_art(RESONANCE_MASTER_SCENE_PATH, "ArtResonanceMasterScene", Vector3.ZERO, Vector3.ONE, 0.0)
    _instance_resonance_art(RESONANCE_RAIL_SYSTEM_PATH, "ArtRail_Infeed", Vector3(-40.5, 0.0, 18.0), Vector3(1.20, 1.20, 1.20), 0.0)
    _instance_resonance_art(RESONANCE_RAIL_SYSTEM_PATH, "ArtRail_Lift", Vector3(-13.5, 0.0, 8.0), Vector3(1.16, 1.16, 1.16), -4.0)
    _instance_resonance_art(RESONANCE_RAIL_SYSTEM_PATH, "ArtRail_ReactorApproach", Vector3(13.5, 0.0, -8.0), Vector3(1.16, 1.16, 1.16), -4.0)
    _instance_resonance_art(RESONANCE_RAIL_SYSTEM_PATH, "ArtRail_Extraction", Vector3(41.0, 0.0, -14.0), Vector3(1.18, 1.18, 1.18), 0.0)
    _instance_resonance_art(RESONANCE_PROCESSING_ZONE_PATH, "ArtProcessing_Infeed", Vector3(-52.0, 0.0, 18.0), Vector3(1.12, 1.12, 1.12), 0.0)
    _instance_resonance_art(RESONANCE_PROCESSING_ZONE_PATH, "ArtProcessing_Lift", Vector3(-2.0, 0.0, 4.0), Vector3(1.18, 1.18, 1.18), -5.0)
    _instance_resonance_art(RESONANCE_PROCESSING_ZONE_PATH, "ArtProcessing_ReactorDeck", Vector3(34.0, 0.0, -13.0), Vector3(1.22, 1.22, 1.22), 8.0)
    _instance_resonance_art(RESONANCE_REACTOR_TOWER_PATH, "ArtReactorTower", Vector3(55.0, 0.0, -17.0), Vector3(1.34, 1.34, 1.34), 0.0)
    _instance_resonance_art(RESONANCE_DRONE_DOCK_PATH, "ArtDroneDock", Vector3(-47.0, 0.0, 30.0), Vector3(1.12, 1.12, 1.12), 0.0)
    _instance_resonance_art(RESONANCE_EXTRACTION_ART_PATH, "ArtExtractionPlatform", Vector3(66.0, 0.0, -14.0), Vector3(1.14, 1.14, 1.14), 0.0)
    _instance_resonance_art(RESONANCE_SURFACE_SET_PATH, "ArtSurfaceWest", Vector3(-49.0, 0.0, -27.0), Vector3(1.20, 1.20, 1.20), 7.0)
    _instance_resonance_art(RESONANCE_SURFACE_SET_PATH, "ArtSurfaceEast", Vector3(49.0, 0.0, 27.0), Vector3(1.20, 1.20, 1.20), -12.0)
    _instance_resonance_art(RESONANCE_SUPPORT_GATE_PATH, "ArtSupportSafetyGate", Vector3(20.0, 0.0, 25.0), Vector3(1.12, 1.12, 1.12), 0.0)
    _instance_resonance_art(RESONANCE_MAINTENANCE_FACILITY_PATH, "ArtMaintenanceFacility", Vector3(-61.0, 0.0, -28.0), Vector3(1.16, 1.16, 1.16), -8.0)
    if not USE_BLENDER_MASTER_VISUALS:
        _instance_resonance_art(RESONANCE_FACTORY_SPINE_PATH, "ArtFactorySpine", Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0), 0.0)
    _instance_resonance_art(RESONANCE_CAVERN_SHELL_PATH, "ArtCavernShell", Vector3.ZERO, Vector3.ONE, 0.0)
    if ResourceLoader.exists(RESONANCE_CAVERN_SHELL_PATH):
        for light_data in [
            [Vector3(-45.0, 13.0, 18.0), Color("#ff7b45"), 4.5],
            [Vector3(0.0, 16.0, 2.0), Color("#6c8cff"), 5.5],
            [Vector3(45.0, 16.0, -14.0), Color("#4dffc1"), 6.0]
        ]:
            var cavern_light: OmniLight3D = OmniLight3D.new()
            cavern_light.position = Vector3(light_data[0])
            cavern_light.light_color = Color(light_data[1])
            cavern_light.light_energy = float(light_data[2]) * 1.35
            cavern_light.omni_range = 34.0
            world_root.add_child(cavern_light)

func _build_zone_plate(center: Vector3, size: Vector3, color: Color, accent: Color, title: String) -> void:
    var plate: MeshInstance3D = MeshInstance3D.new()
    var plate_mesh: BoxMesh = BoxMesh.new()
    plate_mesh.size = Vector3(size.x, 0.16, size.z)
    plate.mesh = plate_mesh
    plate.position = center + Vector3(0.0, 0.09, 0.0)
    var plate_material: StandardMaterial3D = _material(color, accent, 0.22)
    plate_material.albedo_texture = INDUSTRIAL_PANEL_TEXTURE
    plate_material.uv1_scale = Vector3(2.4, 2.4, 2.4)
    plate.material_override = plate_material
    world_root.add_child(plate)
    var edge_color: Color = accent.lightened(0.15)
    _add_decor_box(world_root, center + Vector3(0.0, 0.24, -size.z * 0.5), Vector3(size.x, 0.12, 0.16), edge_color, edge_color, 0.75)
    _add_decor_box(world_root, center + Vector3(0.0, 0.24, size.z * 0.5), Vector3(size.x, 0.12, 0.16), edge_color, edge_color, 0.75)
    _add_decor_box(world_root, center + Vector3(-size.x * 0.5, 0.24, 0.0), Vector3(0.16, 0.12, size.z), edge_color, edge_color, 0.75)
    _add_decor_box(world_root, center + Vector3(size.x * 0.5, 0.24, 0.0), Vector3(0.16, 0.12, size.z), edge_color, edge_color, 0.75)
    world_root.add_child(_label3d(title, center + Vector3(0.0, 0.55, -size.z * 0.5 + 1.0), accent.lightened(0.2)))

func _add_decor_box(parent: Node3D, point: Vector3, size: Vector3, color: Color, emission: Color, energy: float, rotation_y: float = 0.0) -> MeshInstance3D:
    var visual: MeshInstance3D = MeshInstance3D.new()
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    visual.mesh = mesh
    visual.position = point
    visual.rotation_degrees.y = rotation_y
    visual.material_override = _material(color, emission, energy)
    parent.add_child(visual)
    return visual

func _add_detail_bolt(parent: Node3D, point: Vector3, color: Color = Color("#b8c1d8")) -> MeshInstance3D:
    var bolt: MeshInstance3D = MeshInstance3D.new()
    var bolt_mesh: CylinderMesh = CylinderMesh.new()
    bolt_mesh.top_radius = 0.09
    bolt_mesh.bottom_radius = 0.12
    bolt_mesh.height = 0.12
    bolt.mesh = bolt_mesh
    bolt.position = point
    bolt.material_override = _material(color, Color("#dbe7ff"), 0.55)
    parent.add_child(bolt)
    return bolt

func _add_detail_ring(parent: Node3D, point: Vector3, inner_radius: float, outer_radius: float, color: Color, rotation: Vector3 = Vector3(90.0, 0.0, 0.0)) -> MeshInstance3D:
    var ring: MeshInstance3D = MeshInstance3D.new()
    var ring_mesh: TorusMesh = TorusMesh.new()
    ring_mesh.inner_radius = inner_radius
    ring_mesh.outer_radius = outer_radius
    ring.mesh = ring_mesh
    ring.position = point
    ring.rotation_degrees = rotation
    # 环形交互标识保持有色边缘，不在第三人称镜头前过曝成一整块白面。
    var ring_material: StandardMaterial3D = _glow_material(color, 0.30)
    ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    var ring_albedo: Color = ring_material.albedo_color
    ring_albedo.a = 0.72
    ring_material.albedo_color = ring_albedo
    ring.material_override = ring_material
    parent.add_child(ring)
    return ring

func _add_detail_panel(parent: Node3D, point: Vector3, size: Vector3, color: Color, accent: Color) -> MeshInstance3D:
    var panel: MeshInstance3D = _add_decor_box(parent, point, size, color, accent, 0.35)
    var half_x: float = size.x * 0.42
    var half_z: float = size.z * 0.42
    _add_detail_bolt(parent, point + Vector3(-half_x, size.y * 0.56, -half_z), accent)
    _add_detail_bolt(parent, point + Vector3(half_x, size.y * 0.56, -half_z), accent)
    _add_detail_bolt(parent, point + Vector3(-half_x, size.y * 0.56, half_z), accent)
    _add_detail_bolt(parent, point + Vector3(half_x, size.y * 0.56, half_z), accent)
    return panel

func _add_hydraulic_strut(parent: Node3D, start: Vector3, finish: Vector3, color: Color) -> void:
    _add_decor_pipe(start, finish, Color("#4c587c"), color)
    _add_detail_bolt(parent, start, color)
    _add_detail_bolt(parent, finish, color)

func _add_decor_pipe(start: Vector3, finish: Vector3, color: Color, emission: Color) -> void:
    var midpoint: Vector3 = (start + finish) * 0.5
    var pipe: MeshInstance3D = MeshInstance3D.new()
    var pipe_mesh: BoxMesh = BoxMesh.new()
    pipe_mesh.size = Vector3(0.42, 0.42, start.distance_to(finish))
    pipe.mesh = pipe_mesh
    pipe.position = midpoint
    pipe.material_override = _material(color, emission, 0.75)
    world_root.add_child(pipe)
    var pipe_direction: Vector3 = finish - start
    var look_up: Vector3 = Vector3.UP
    if pipe_direction.length_squared() > 0.0001 and absf(pipe_direction.normalized().dot(Vector3.UP)) > 0.98:
        look_up = Vector3.FORWARD
    pipe.look_at(finish, look_up)
    var joint: MeshInstance3D = MeshInstance3D.new()
    var joint_mesh: CylinderMesh = CylinderMesh.new()
    joint_mesh.top_radius = 0.62
    joint_mesh.bottom_radius = 0.62
    joint_mesh.height = 0.25
    joint.mesh = joint_mesh
    joint.position = start
    joint.material_override = _glow_material(emission, 1.0)
    world_root.add_child(joint)

func _build_overhead_truss(center: Vector3, width: float, height: float) -> void:
    var truss: Node3D = Node3D.new()
    truss.position = center
    var pillar_size: Vector3 = Vector3(0.7, height, 0.7)
    _add_decor_box(truss, Vector3(-width * 0.5, height * 0.5, 0.0), pillar_size, Color("#161a22"), Color("#b85a2b"), 0.52)
    _add_decor_box(truss, Vector3(width * 0.5, height * 0.5, 0.0), pillar_size, Color("#161a22"), Color("#b85a2b"), 0.52)
    _add_decor_box(truss, Vector3(0.0, height, 0.0), Vector3(width, 0.72, 0.72), Color("#29272b"), Color("#e28a3c"), 0.65)
    _add_decor_box(truss, Vector3(0.0, height * 0.62, 0.0), Vector3(width * 0.88, 0.18, 0.18), Color("#343039"), Color("#ffb34f"), 0.78, 8.0)
    _add_decor_box(truss, Vector3(0.0, height * 0.42, 0.0), Vector3(width * 0.72, 0.16, 0.16), Color("#343039"), Color("#ff7a31"), 0.52, -8.0)
    _add_detail_bolt(truss, Vector3(-width * 0.5, height * 0.24, 0.0), Color("#ffbd70"))
    _add_detail_bolt(truss, Vector3(width * 0.5, height * 0.24, 0.0), Color("#ffbd70"))
    _add_detail_ring(truss, Vector3(0.0, height * 0.78, 0.0), 0.52, 0.64, Color("#ff8b35"), Vector3(0.0, 0.0, 0.0))
    truss.add_child(_label3d("轨道吊装架", Vector3(0.0, height + 1.1, 0.0), Color("#b9d8ff")))
    world_root.add_child(truss)

func _build_factory_spine_visuals() -> void:
    # 远景主骨架：把模块、升降区和反应堆串成一条可读的工业生产线。
    # 这些视觉结构不携带玩法碰撞，只负责补足概念图中的巨大尺度和纵深轮廓。
    var truss_centers: Array[Vector3] = [
        Vector3(-55.0, 0.0, 8.0),
        Vector3(-27.0, 0.0, 4.0),
        Vector3(2.0, 0.0, 0.0),
        Vector3(31.0, 0.0, -8.0),
        Vector3(58.0, 0.0, -14.0)
    ]
    for index in truss_centers.size():
        _build_overhead_truss(truss_centers[index], 17.0 if index < 4 else 21.0, 9.5 if index < 4 else 12.0)
    var spine: Node3D = Node3D.new()
    spine.name = "FactorySpineVisuals"
    world_root.add_child(spine)
    for index in 6:
        var x: float = -62.0 + float(index) * 24.0
        var height: float = 9.5 + float(index % 2) * 2.0
        _add_decor_box(spine, Vector3(x, height * 0.5, -5.0), Vector3(0.72, height, 0.72), Color("#151922"), Color("#ff8a38"), 0.62)
        _add_decor_box(spine, Vector3(x, height * 0.5, 7.0), Vector3(0.72, height, 0.72), Color("#151922"), Color("#5bd7e8"), 0.52)
        _add_decor_box(spine, Vector3(x, height, 1.0), Vector3(8.4, 0.58, 0.58), Color("#292832"), Color("#ffad4f"), 0.72)
        _add_detail_bolt(spine, Vector3(x - 0.25, height - 0.2, -5.35), Color("#ffd18a"))
        _add_detail_bolt(spine, Vector3(x + 0.25, height - 0.2, 7.35), Color("#79eaff"))
        if index < 5:
            _add_decor_pipe(Vector3(x + 0.2, height * 0.48, 7.3), Vector3(x + 24.0 - 0.2, height * 0.48, 7.3), Color("#17232e"), Color("#5bd7e8"))
            _add_decor_pipe(Vector3(x + 0.2, height * 0.38, -5.3), Vector3(x + 24.0 - 0.2, height * 0.38, -5.3), Color("#302029"), Color("#ff7c38"))
    for bridge_index in 3:
        var bridge_x: float = -36.0 + float(bridge_index) * 39.0
        _add_decor_box(spine, Vector3(bridge_x, 5.6 + float(bridge_index) * 1.2, 1.0), Vector3(28.0, 0.26, 2.6), Color("#25262e"), Color("#a36c45"), 0.52)
        _add_decor_box(spine, Vector3(bridge_x, 6.35 + float(bridge_index) * 1.2, -0.2), Vector3(28.0, 0.16, 0.16), Color("#333039"), Color("#ffb55a"), 0.72)
        for bolt_index in 6:
            _add_detail_bolt(spine, Vector3(bridge_x - 11.0 + float(bolt_index) * 4.4, 5.82 + float(bridge_index) * 1.2, 2.15), Color("#9bdcff"))

func _add_round_pipe(parent: Node3D, start: Vector3, finish: Vector3, radius: float, color: Color, emission: Color, energy: float = 0.35) -> void:
    # 视觉专用圆管，和玩法管线分离；圆截面在近景比 BoxMesh 更像工业管道。
    var direction: Vector3 = finish - start
    if direction.length_squared() < 0.001:
        return
    var pipe: MeshInstance3D = MeshInstance3D.new()
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = direction.length()
    mesh.radial_segments = 16
    pipe.mesh = mesh
    pipe.position = (start + finish) * 0.5
    pipe.material_override = _material(color, emission, energy)
    # CylinderMesh 的长轴是本地 Y；look_at 先把本地 -Z 对准管线方向，
    # 再绕本地 X 旋转 90 度把圆柱长轴转回管线方向。
    var up_axis: Vector3 = Vector3.UP
    if absf(direction.normalized().dot(up_axis)) > 0.96:
        up_axis = Vector3.FORWARD
    pipe.look_at_from_position(pipe.position, pipe.position + direction, up_axis)
    pipe.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
    parent.add_child(pipe)

func _build_megastructure_tower(parent: Node3D, center: Vector3, height: float, accent: Color) -> void:
    var tower: Node3D = Node3D.new()
    tower.position = center
    parent.add_child(tower)
    var steel: Color = Color("#171b23")
    var edge: Color = Color("#3a414c")
    for side_x in [-1.0, 1.0]:
        for side_z in [-1.0, 1.0]:
            var leg := _add_decor_box(tower, Vector3(side_x * 2.3, height * 0.5, side_z * 2.3), Vector3(0.72, height, 0.72), steel, accent, 0.38)
            leg.name = "TowerLeg"
            _add_detail_bolt(tower, Vector3(side_x * 2.3, 1.1, side_z * 2.3), accent)
            _add_detail_bolt(tower, Vector3(side_x * 2.3, height - 0.65, side_z * 2.3), accent)
    for level in range(1, 4):
        var y: float = float(level) * height / 4.0
        _add_decor_box(tower, Vector3(0.0, y, 0.0), Vector3(5.6, 0.28, 5.6), edge, accent, 0.26)
        _add_decor_box(tower, Vector3(0.0, y + 0.20, -2.72), Vector3(4.9, 0.10, 0.10), accent, accent, 0.62)
        _add_decor_box(tower, Vector3(0.0, y + 0.20, 2.72), Vector3(4.9, 0.10, 0.10), accent, accent, 0.62)
        for bolt_x in [-2.0, 0.0, 2.0]:
            _add_detail_bolt(tower, Vector3(bolt_x, y + 0.20, -2.55), accent)
    for brace_y in [height * 0.25, height * 0.5, height * 0.75]:
        _add_decor_box(tower, Vector3(0.0, brace_y, -2.32), Vector3(5.2, 0.18, 0.18), edge, accent, 0.34, 18.0)
        _add_decor_box(tower, Vector3(0.0, brace_y, 2.32), Vector3(5.2, 0.18, 0.18), edge, accent, 0.34, -18.0)
    _add_decor_box(tower, Vector3(0.0, height + 0.35, 0.0), Vector3(6.4, 0.42, 6.4), steel, accent, 0.38)
    _add_detail_ring(tower, Vector3(0.0, height * 0.5, 0.0), 1.25, 1.42, accent, Vector3(90.0, 0.0, 0.0))

func _build_industrial_megastructure() -> void:
    # 概念图级远景骨架：三层主吊装线、跨区塔架和连接管桥。
    # 纯视觉节点，不创建碰撞，避免改动既有移动与交互空间。
    var root: Node3D = Node3D.new()
    root.name = "IndustrialMegaStructure"
    world_root.add_child(root)
    var steel: Color = Color("#151a22")
    var edge: Color = Color("#343943")
    var amber: Color = Color("#ff8d32")
    var cyan: Color = Color("#55d9e9")
    var violet: Color = Color("#b88aff")
    var green: Color = Color("#79e9b7")

    # 地面两侧立柱和三层贯通梁，构成能从远景读出的厂区屋架。
    for x in range(-64, 65, 16):
        var column_height: float = 12.0 if x % 32 == 0 else 9.0
        _add_decor_box(root, Vector3(float(x), column_height * 0.5, -18.0), Vector3(1.35, column_height, 1.35), steel, amber, 0.42)
        _add_decor_box(root, Vector3(float(x), column_height * 0.5, 18.0), Vector3(1.35, column_height, 1.35), steel, amber, 0.42)
        _add_detail_bolt(root, Vector3(float(x), 1.0, -18.7), amber)
        _add_detail_bolt(root, Vector3(float(x), 1.0, 18.7), amber)
        if x < 64:
            _add_decor_box(root, Vector3(float(x) + 8.0, column_height, -18.0), Vector3(16.0, 0.82, 1.15), edge, amber, 0.38)
            _add_decor_box(root, Vector3(float(x) + 8.0, column_height, 18.0), Vector3(16.0, 0.82, 1.15), edge, amber, 0.38)
    for y in [6.5, 10.5, 15.0]:
        _add_decor_box(root, Vector3(0.0, y, 0.0), Vector3(140.0, 0.62, 0.92), edge, amber, 0.34)
        _add_decor_box(root, Vector3(0.0, y + 0.44, -5.5), Vector3(140.0, 0.12, 0.12), amber, amber, 0.70)
        _add_decor_box(root, Vector3(0.0, y + 0.44, 5.5), Vector3(140.0, 0.12, 0.12), cyan if y < 11.0 else violet, cyan if y < 11.0 else violet, 0.70)
    # 高低错层的检修桥，强化前后、左右、上下的空间关系。
    for index in 5:
        var x: float = -48.0 + float(index) * 24.0
        var y: float = 3.8 + float(index % 3) * 2.15
        var z: float = -10.0 if index % 2 == 0 else 10.0
        _add_decor_box(root, Vector3(x, y, z), Vector3(18.0, 0.28, 2.8), steel, amber, 0.28)
        _add_decor_box(root, Vector3(x, y + 0.65, z - 1.22), Vector3(18.0, 0.14, 0.14), amber, amber, 0.60)
        _add_decor_box(root, Vector3(x, y + 0.65, z + 1.22), Vector3(18.0, 0.14, 0.14), amber, amber, 0.60)
        for bolt_index in 5:
            _add_detail_bolt(root, Vector3(x - 7.0 + float(bolt_index) * 3.5, y + 0.22, z - 1.05), amber)
    # 跨区圆管和冷却回路，避免远景只剩直线盒子。
    _add_round_pipe(root, Vector3(-68.0, 8.5, -8.0), Vector3(-24.0, 8.5, -8.0), 0.32, Color("#17202c"), cyan, 0.72)
    _add_round_pipe(root, Vector3(-24.0, 8.5, -8.0), Vector3(18.0, 10.2, -8.0), 0.32, Color("#17202c"), cyan, 0.72)
    _add_round_pipe(root, Vector3(18.0, 10.2, -8.0), Vector3(52.0, 12.0, -12.0), 0.36, Color("#17202c"), green, 0.76)
    _add_round_pipe(root, Vector3(-62.0, 5.1, 12.0), Vector3(-24.0, 5.1, 12.0), 0.25, Color("#261a24"), amber, 0.58)
    _add_round_pipe(root, Vector3(8.0, 5.1, 12.0), Vector3(42.0, 7.2, 12.0), 0.25, Color("#261a24"), violet, 0.58)
    # 三座跨层塔架作为远景节奏点，并给近景提供真实分件轮廓。
    _build_megastructure_tower(root, Vector3(-28.0, 0.0, -10.0), 11.0, violet)
    _build_megastructure_tower(root, Vector3(4.0, 0.0, 10.0), 13.5, amber)
    _build_megastructure_tower(root, Vector3(35.0, 0.0, 4.0), 15.0, green)
    # 两组悬挂货箱和吊钩，明确这里是进料工厂而不是抽象平台。
    for index in 4:
        var x: float = -52.0 + float(index) * 28.0
        var y: float = 12.0 + float(index % 2) * 2.2
        _add_round_pipe(root, Vector3(x, y, 0.0), Vector3(x, y - 2.0, 0.0), 0.12, amber, amber, 0.72)
        _add_decor_box(root, Vector3(x, y - 3.0, 0.0), Vector3(3.6, 1.7, 2.8), steel, amber, 0.34)
        _add_detail_panel(root, Vector3(x, y - 3.0, -1.46), Vector3(2.6, 0.72, 0.12), Color("#20252e"), amber)
        _add_detail_ring(root, Vector3(x, y - 3.85, 0.0), 0.42, 0.58, amber, Vector3(90.0, 0.0, 0.0))

func _build_lava_fissure_visuals() -> void:
    var root: Node3D = Node3D.new()
    root.name = "LavaFissureVisuals"
    world_root.add_child(root)
    var lava_color: Color = Color("#7f1818")
    var glow_color: Color = Color("#ff5a24")
    var fissures: Array = [
        [Vector3(-66.0, -3.94, -2.0), Vector3(18.0, -3.94, -2.0), 0.75],
        [Vector3(-22.0, -3.90, 32.0), Vector3(36.0, -3.90, 32.0), 0.56],
        [Vector3(43.0, -3.90, -38.0), Vector3(72.0, -3.90, -20.0), 0.70],
        [Vector3(-68.0, -3.90, -31.0), Vector3(-46.0, -3.90, -41.0), 0.48]
    ]
    for fissure in fissures:
        var start: Vector3 = Vector3(fissure[0])
        var finish: Vector3 = Vector3(fissure[1])
        var width: float = float(fissure[2])
        _add_decor_box(root, (start + finish) * 0.5, Vector3(start.distance_to(finish), 0.07, width), lava_color, glow_color, 0.42, rad_to_deg(atan2(finish.z - start.z, finish.x - start.x)))
        _add_round_pipe(root, start, finish, 0.08, glow_color, glow_color, 0.86)

func _build_cargo_rack(center: Vector3, accent: Color, title: String) -> void:
    var rack: Node3D = Node3D.new()
    rack.position = center
    _add_decor_box(rack, Vector3(-3.0, 2.0, 0.0), Vector3(0.45, 4.0, 2.2), Color("#27355e"), accent, 0.8)
    _add_decor_box(rack, Vector3(3.0, 2.0, 0.0), Vector3(0.45, 4.0, 2.2), Color("#27355e"), accent, 0.8)
    for level in 3:
        _add_decor_box(rack, Vector3(0.0, 0.55 + float(level) * 1.25, 0.0), Vector3(6.4, 0.22, 2.5), Color("#334777"), accent, 0.55)
        _add_decor_box(rack, Vector3(-1.55, 0.85 + float(level) * 1.25, 0.0), Vector3(1.8, 0.58, 1.35), accent.darkened(0.25), accent, 0.7)
        _add_decor_box(rack, Vector3(1.55, 0.85 + float(level) * 1.25, 0.0), Vector3(1.8, 0.58, 1.35), accent.darkened(0.25), accent, 0.7)
        _add_detail_bolt(rack, Vector3(-2.75, 0.7 + float(level) * 1.25, 1.08), accent)
        _add_detail_bolt(rack, Vector3(2.75, 0.7 + float(level) * 1.25, 1.08), accent)
        _add_decor_box(rack, Vector3(0.0, 0.64 + float(level) * 1.25, 1.18), Vector3(5.5, 0.08, 0.12), accent, accent, 0.9)
    rack.add_child(_label3d(title, Vector3(0.0, 4.8, 0.0), accent.lightened(0.2)))
    world_root.add_child(rack)

func _build_reactor_tower(center: Vector3) -> void:
    var tower: Node3D = Node3D.new()
    tower.position = center
    var foundation: MeshInstance3D = MeshInstance3D.new()
    var foundation_mesh: CylinderMesh = CylinderMesh.new()
    foundation_mesh.top_radius = 5.6
    foundation_mesh.bottom_radius = 6.4
    foundation_mesh.height = 0.9
    foundation.mesh = foundation_mesh
    foundation.position.y = 0.45
    foundation.material_override = _material(Color("#554044"), Color("#9b6057"), 0.18)
    tower.add_child(foundation)
    for index in 4:
        var anchor: MeshInstance3D = MeshInstance3D.new()
        var anchor_mesh: BoxMesh = BoxMesh.new()
        anchor_mesh.size = Vector3(1.0, 1.4, 1.0)
        anchor.mesh = anchor_mesh
        var angle: float = float(index) * PI * 0.5
        anchor.position = Vector3(cos(angle) * 5.0, 0.7, sin(angle) * 5.0)
        anchor.material_override = _material(Color("#34323c"), Color("#77708a"), 0.35)
        tower.add_child(anchor)
    var body: MeshInstance3D = MeshInstance3D.new()
    var body_mesh: CylinderMesh = CylinderMesh.new()
    body_mesh.top_radius = 3.8
    body_mesh.bottom_radius = 4.6
    body_mesh.height = 10.0
    body.mesh = body_mesh
    body.position.y = 5.0
    body.material_override = _material(Color("#202d56"), Color("#4a75ce"), 0.85)
    tower.add_child(body)
    for rib_index in 8:
        var rib: MeshInstance3D = MeshInstance3D.new()
        var rib_mesh: BoxMesh = BoxMesh.new()
        rib_mesh.size = Vector3(0.34, 8.4, 0.5)
        rib.mesh = rib_mesh
        var rib_angle: float = float(rib_index) * TAU / 8.0
        rib.position = Vector3(cos(rib_angle) * 4.15, 5.0, sin(rib_angle) * 4.15)
        rib.rotation_degrees.y = -rad_to_deg(rib_angle)
        rib.material_override = _material(Color("#34446c"), Color("#7e9be5"), 0.62)
        tower.add_child(rib)
        _add_detail_bolt(tower, Vector3(cos(rib_angle) * 4.32, 1.0, sin(rib_angle) * 4.32), Color("#b8c8ee"))
        _add_detail_bolt(tower, Vector3(cos(rib_angle) * 4.32, 8.8, sin(rib_angle) * 4.32), Color("#b8c8ee"))
    for level in 3:
        var ring: MeshInstance3D = MeshInstance3D.new()
        var ring_mesh: TorusMesh = TorusMesh.new()
        ring_mesh.inner_radius = 3.9
        ring_mesh.outer_radius = 4.15
        ring.mesh = ring_mesh
        ring.position.y = 1.4 + float(level) * 3.1
        ring.material_override = _glow_material(Color("#79e9b7") if level == 1 else Color("#5b75d8"), 1.35)
        tower.add_child(ring)
        _add_decor_box(tower, Vector3(0.0, 1.55 + float(level) * 3.1, 4.45), Vector3(1.8, 0.9, 0.16), Color("#1c2e4e"), Color("#79e9b7"), 1.0)
    var cap: MeshInstance3D = MeshInstance3D.new()
    var cap_mesh: CylinderMesh = CylinderMesh.new()
    cap_mesh.top_radius = 2.5
    cap_mesh.bottom_radius = 3.1
    cap_mesh.height = 0.7
    cap.mesh = cap_mesh
    cap.position.y = 10.35
    cap.material_override = _glow_material(Color("#ffca68"), 1.55)
    tower.add_child(cap)
    tower.add_child(_label3d("反应堆稳定塔", Vector3(0.0, 12.0, 0.0), Color("#e6f0ff")))
    world_root.add_child(tower)

func _build_hazard_marker(point: Vector3) -> void:
    var marker: Node3D = Node3D.new()
    marker.position = point
    for index in 4:
        var stripe: MeshInstance3D = _add_decor_box(marker, Vector3(-1.8 + float(index) * 1.2, 0.16, 0.0), Vector3(0.65, 0.08, 2.4), Color("#d69b4b") if index % 2 == 0 else Color("#25213d"), Color("#ffca68"), 0.8, -25.0)
        stripe.name = "HazardStripe_%d" % index
    marker.add_child(_label3d("高压轨道", Vector3(0.0, 0.65, 0.0), Color("#ffd78e")))
    world_root.add_child(marker)

func _build_objective_guide() -> void:
    objective_path_root = Node3D.new()
    objective_path_root.name = "ResonanceObjectivePath"
    world_root.add_child(objective_path_root)
    for index in 9:
        var path_node: MeshInstance3D = MeshInstance3D.new()
        var path_mesh: SphereMesh = SphereMesh.new()
        path_mesh.radius = 0.12
        path_mesh.height = 0.24
        path_node.mesh = path_mesh
        path_node.material_override = _glow_material(Color("#48dff0"), 1.3)
        objective_path_root.add_child(path_node)
        objective_path_nodes.append(path_node)
    objective_guide = Node3D.new()
    objective_guide.name = "ResonanceObjectiveGuide"
    var beacon: MeshInstance3D = MeshInstance3D.new()
    var beacon_mesh: CylinderMesh = CylinderMesh.new()
    beacon_mesh.top_radius = 0.3
    beacon_mesh.bottom_radius = 0.62
    beacon_mesh.height = 3.5
    beacon.mesh = beacon_mesh
    beacon.position.y = 1.75
    beacon.material_override = _glow_material(Color("#48dff0"), 2.4)
    objective_guide.add_child(beacon)
    var halo: MeshInstance3D = MeshInstance3D.new()
    var halo_mesh: TorusMesh = TorusMesh.new()
    halo_mesh.inner_radius = 1.15
    halo_mesh.outer_radius = 1.38
    halo.mesh = halo_mesh
    halo.position.y = 3.55
    halo.rotation_degrees = Vector3(90.0, 0.0, 0.0)
    halo.material_override = _glow_material(Color("#ffd36e"), 1.7)
    objective_guide.add_child(halo)
    objective_guide.add_child(_label3d("下一步", Vector3(0.0, 4.7, 0.0), Color("#fff0b0")))
    world_root.add_child(objective_guide)
    _refresh_objective_guide()

func _refresh_objective_guide() -> void:
    if objective_guide == null:
        return
    var target: Vector3 = Vector3.ZERO
    var guide_text: String = "中央能源核心"
    var guide_color: Color = Color("#9ff5ff")
    var module: Dictionary = _current_module()
    if not heat_chain_complete:
        var next_valve: String = "left"
        if int(heat_valves.get("left", 0)) == 1:
            next_valve = "right"
        if int(heat_valves.get("right", 0)) == 1:
            next_valve = "relief"
        target = Vector3(heat_valve_positions[next_valve])
        guide_text = "洞底热阀链：开启%s阀" % ("左" if next_valve == "left" else ("右" if next_valve == "right" else "泄压"))
        guide_color = Color("#ff8a43")
    elif checkpoint == 1 and not shortcut_unlocked:
        var relay_phase: int = int(support_relay.get("phase", 0))
        if relay_phase == 0:
            target = SUPPORT_RELAY_LOW_POSITION
            guide_text = "支援回路：低位发送端"
        else:
            target = SUPPORT_RELAY_HIGH_POSITION
            guide_text = "支援回路：高位接收端"
        guide_color = Color("#8f9dff")
    elif reactor_deck_active:
        var challenge: Dictionary = _current_reactor_challenge()
        if not challenge.is_empty():
            var challenge_id: String = String(challenge.get("id", ""))
            if challenge_id == "coolant" and reactor_carrier != 0:
                target = Vector3(challenge["coolant_socket_position"])
                guide_text = "反应堆：把冷却单元送到接收座"
                guide_color = Color("#79e9b7")
            elif challenge_id == "coolant" and reactor_stabilizer == 0 and controller.connected_ids.size() > 1:
                target = Vector3(challenge["stabilizer_position"])
                guide_text = "反应堆：队友稳定冷却接收座"
                guide_color = Color("#77f0b7")
            else:
                var sequence: Array = challenge.get("sequence", [])
                var step: int = int(challenge.get("step", 0))
                if not sequence.is_empty() and step < sequence.size():
                    var expected_kind: String = String(sequence[step])
                    target = _reactor_target_position(challenge, expected_kind)
                    guide_text = "反应堆：%s · 节点 %d/%d" % [String(challenge.get("name", "任务")), step + 1, sequence.size()]
                    guide_color = Color("#c5b4ff")
                elif challenge_id == "coolant":
                    target = Vector3(challenge["coolant_position"])
                    guide_text = "反应堆：接入冷却单元"
                    guide_color = Color("#ffd28a")
    elif checkpoint < MODULE_COUNT and not module.is_empty():
        var mechanic: String = String(module.get("mechanic", "switch"))
        if mechanic == "freight" and not bool(module.get("cargo_loaded", false)):
            target = Vector3(module["freight_position"])
            guide_text = "模块 %d：搬运磁力货箱" % int(module["id"])
            guide_color = Color("#ffd28a")
        elif mechanic == "beam" and int(module.get("beam_step", 0)) < 3:
            var beam_sequence: Array = module.get("beam_sequence", ["support", "route", "safety"])
            var beam_step: int = int(module.get("beam_step", 0))
            var beam_kind: String = String(beam_sequence[beam_step])
            target = Vector3(module["%s_position" % beam_kind])
            guide_text = "模块 %d：按顺序校准光束节点 %s" % [int(module["id"]), _beam_node_name(beam_kind)]
            guide_color = Color("#c5b4ff")
        elif int(module.get("rail_peer", 0)) == 0:
            target = Vector3(module["rail_position"])
            guide_text = "模块 %d：蓝色供能端" % int(module["id"])
            guide_color = Color("#48dff0")
        elif int(module.get("clamp_peer", 0)) == 0:
            target = Vector3(module["clamp_position"])
            guide_text = "模块 %d：金色对接夹具" % int(module["id"])
            guide_color = Color("#ffca68")
        elif String(module.get("route_choice", "safe")) == "fast" and int(module.get("support_peer", 0)) == 0:
            target = Vector3(module["support_position"])
            guide_text = "模块 %d：绿色保险栓" % int(module["id"])
            guide_color = Color("#77f0b7")
        else:
            target = Vector3(module["position"])
            guide_text = "模块 %d：保持两端接入" % int(module["id"])
            guide_color = Color("#fff0b0")
    elif core_node != null:
        target = core_node.global_position
        guide_text = "中央能源核心：两人搬运"
        guide_color = Color("#9ff5ff")
    if objective_guide.get_child_count() >= 3:
        var label: Label3D = objective_guide.get_child(2) as Label3D
        if label != null:
            label.text = "下一步\n" + guide_text
            label.modulate = guide_color
    if objective_path_root != null:
        var start: Vector3 = START_POSITION
        var end: Vector3 = target
        for index in objective_path_nodes.size():
            var ratio: float = float(index) / float(maxi(objective_path_nodes.size() - 1, 1))
            objective_path_nodes[index].global_position = start.lerp(end, ratio) + Vector3(0.0, 0.12, 0.0)
    objective_guide.global_position = target + Vector3(0.0, 5.0, 0.0)
    objective_guide.visible = reactor_deck_active or checkpoint < MODULE_COUNT or (core_node != null and core_node.visible and not core_delivered)


func _create_module_platform(root: Node3D) -> void:
    if USE_BLENDER_MASTER_VISUALS:
        if not USE_RESONANCE_MODULE_HERO or DisplayServer.get_name() == "headless":
            return
        var authored_scene: PackedScene = ResourceLoader.load(RESONANCE_MODULE_HERO_PATH) as PackedScene
        if authored_scene != null:
            var authored: Node3D = authored_scene.instantiate() as Node3D
            if authored != null:
                authored.name = "BlenderHeroModel"
                authored.position = Vector3(0.0, 0.04, 0.0)
                authored.scale = Vector3(1.02, 1.02, 1.02)
                authored.set_meta("asset_id", "resonance_module_hero")
                root.add_child(authored)
        return
    _add_decor_box(root, Vector3(-4.8, 0.08, -3.2), Vector3(2.6, 0.8, 2.4), Color("#5a3b3b"), Color("#8f514b"), 0.2)
    _add_decor_box(root, Vector3(4.8, 0.08, -3.2), Vector3(2.6, 0.8, 2.4), Color("#5a3b3b"), Color("#8f514b"), 0.2)
    _add_detail_panel(root, Vector3(-5.1, 0.62, 0.0), Vector3(1.0, 0.16, 5.8), Color("#273755"), Color("#6688c9"))
    _add_detail_panel(root, Vector3(5.1, 0.62, 0.0), Vector3(1.0, 0.16, 5.8), Color("#273755"), Color("#6688c9"))
    var base: MeshInstance3D = MeshInstance3D.new()
    var base_mesh: BoxMesh = BoxMesh.new()
    base_mesh.size = Vector3(14.0, 0.5, 10.0)
    base.mesh = base_mesh
    base.position.y = 0.25
    var base_material: StandardMaterial3D = _material(Color("#293753"), Color("#5b7cec"), 0.55)
    base_material.albedo_texture = INDUSTRIAL_PANEL_TEXTURE
    base_material.uv1_scale = Vector3(2.0, 2.0, 2.0)
    base.material_override = base_material
    root.add_child(base)

    var deck: MeshInstance3D = MeshInstance3D.new()
    var deck_mesh: BoxMesh = BoxMesh.new()
    deck_mesh.size = Vector3(12.8, 0.16, 8.6)
    deck.mesh = deck_mesh
    deck.position.y = 0.58
    var deck_material: StandardMaterial3D = _material(Color("#46506d"), Color("#7b8cff"), 0.32)
    deck_material.albedo_texture = INDUSTRIAL_PANEL_TEXTURE
    deck_material.uv1_scale = Vector3(2.8, 2.8, 2.8)
    deck.material_override = deck_material
    root.add_child(deck)

    for index in 5:
        _add_decor_box(root, Vector3(-4.8 + float(index) * 2.4, 0.72, 4.18), Vector3(1.55, 0.08, 0.16), Color("#202d4b"), Color("#8e9fd7"), 0.4)
        _add_detail_bolt(root, Vector3(-5.1 + float(index) * 2.4, 0.82, 4.18), Color("#d7a45e"))

    for x in [-5.0, 5.0]:
        var piston: MeshInstance3D = MeshInstance3D.new()
        var piston_mesh: CylinderMesh = CylinderMesh.new()
        piston_mesh.top_radius = 0.20
        piston_mesh.bottom_radius = 0.27
        piston_mesh.height = 1.85
        piston.mesh = piston_mesh
        piston.position = Vector3(x, 1.35, 3.2)
        piston.material_override = _material(Color("#313b58"), Color("#7182bd"), 0.38)
        root.add_child(piston)
        _add_hydraulic_strut(root, Vector3(x, 0.72, 2.6), Vector3(x * 0.78, 1.1, 1.8), Color("#70d9e8"))

    # The first Blender hero asset sits on the procedural foundation. Keeping the
    # foundation and interaction devices in Godot means the visual model can be
    # iterated without coupling art meshes to route, carry, lock or network state.
    if not USE_RESONANCE_MODULE_HERO or DisplayServer.get_name() == "headless":
        return
    var hero_scene: PackedScene = ResourceLoader.load(RESONANCE_MODULE_HERO_PATH) as PackedScene
    if hero_scene != null:
        var hero_instance: Node3D = hero_scene.instantiate() as Node3D
        if hero_instance != null:
            hero_instance.name = "BlenderHeroModel"
            hero_instance.position = Vector3(0.0, 0.04, 0.0)
            hero_instance.scale = Vector3(1.02, 1.02, 1.02)
            hero_instance.set_meta("asset_id", "resonance_module_hero")
            root.add_child(hero_instance)

func _create_module_mechanisms(root: Node3D, module: Dictionary) -> void:
    if USE_BLENDER_MASTER_VISUALS:
        return
    var rail_light: MeshInstance3D = _create_indicator(Vector3(-3.4, 1.25, 0.0), Color("#47dfff"), "轨道供能")
    var clamp_light: MeshInstance3D = _create_indicator(Vector3(3.4, 1.25, 0.0), Color("#ffca68"), "对接锁止")
    var bolt_light: MeshInstance3D = _create_indicator(Vector3(0.0, 1.25, 3.8), Color("#77f0b7"), "保险栓")
    var safety_light: MeshInstance3D = _create_indicator(Vector3(0.0, 1.25, -3.8), Color("#c28cff"), "安全锚点")
    root.add_child(rail_light)
    root.add_child(clamp_light)
    root.add_child(bolt_light)
    root.add_child(safety_light)

    var switch_root: Node3D = Node3D.new()
    switch_root.name = "RouteSwitch"
    switch_root.position = Vector3(0.0, 0.0, -7.2)
    var switch_base: MeshInstance3D = MeshInstance3D.new()
    var switch_mesh: BoxMesh = BoxMesh.new()
    switch_mesh.size = Vector3(2.3, 0.6, 1.2)
    switch_base.mesh = switch_mesh
    switch_base.position.y = 0.32
    switch_base.material_override = _material(Color("#4d3c76"), Color("#b178ff"), 0.8)
    switch_root.add_child(switch_base)
    var dial: MeshInstance3D = MeshInstance3D.new()
    var dial_mesh: TorusMesh = TorusMesh.new()
    dial_mesh.inner_radius = 0.65
    dial_mesh.outer_radius = 0.85
    dial.mesh = dial_mesh
    dial.position.y = 1.0
    dial.material_override = _glow_material(Color("#ffca68"), 1.4)
    switch_root.add_child(dial)
    switch_root.add_child(_label3d("路线切换\nE 快/稳", Vector3(0.0, 1.9, 0.0), Color("#ffdca0")))
    root.add_child(switch_root)
    route_nodes[int(module["id"])] = switch_root

    var mechanic: String = String(module.get("mechanic", "switch"))
    var module_id: int = int(module["id"])
    if mechanic == "freight":
        var freight_root: Node3D = Node3D.new()
        freight_root.name = "MagneticFreightBox"
        freight_root.position = Vector3(0.0, 0.0, 5.0)
        var freight_box: MeshInstance3D = MeshInstance3D.new()
        var freight_mesh: BoxMesh = BoxMesh.new()
        freight_mesh.size = Vector3(1.8, 1.4, 1.8)
        freight_box.mesh = freight_mesh
        freight_box.position.y = 0.8
        var freight_material: StandardMaterial3D = _glow_material(Color("#ff8e5c"), 1.15)
        freight_material.albedo_texture = INDUSTRIAL_PANEL_TEXTURE
        freight_material.uv1_scale = Vector3(1.2, 1.2, 1.2)
        freight_box.material_override = freight_material
        freight_root.add_child(freight_box)
        _add_detail_bolt(freight_root, Vector3(-0.72, 1.5, -0.72), Color("#ffe0a6"))
        _add_detail_bolt(freight_root, Vector3(0.72, 1.5, 0.72), Color("#ffe0a6"))
        var freight_ring: MeshInstance3D = MeshInstance3D.new()
        var freight_ring_mesh: TorusMesh = TorusMesh.new()
        freight_ring_mesh.inner_radius = 1.05
        freight_ring_mesh.outer_radius = 1.16
        freight_ring.mesh = freight_ring_mesh
        freight_ring.position.y = 0.82
        freight_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
        freight_ring.material_override = _glow_material(Color("#ffd36e"), 1.5)
        freight_root.add_child(freight_ring)
        freight_root.add_child(_label3d("磁力货箱\nF 搬到绿色插槽", Vector3(0.0, 2.25, 0.0), Color("#ffd7a3")))
        root.add_child(freight_root)
        freight_visuals[module_id] = freight_root
    elif mechanic == "beam":
        var beam_root: Node3D = Node3D.new()
        beam_root.name = "BeamCalibrationNodes"
        var beam_points: Array[Vector3] = [
            Vector3(0.0, 0.9, 3.8),
            Vector3(0.0, 0.9, -7.2),
            Vector3(0.0, 0.9, -3.6)
        ]
        var beam_nodes: Array[MeshInstance3D] = []
        var beam_labels: Array[String] = ["A", "B", "C"]
        for index in beam_points.size():
            var beam_node: MeshInstance3D = MeshInstance3D.new()
            var beam_mesh: CylinderMesh = CylinderMesh.new()
            beam_mesh.top_radius = 0.52
            beam_mesh.bottom_radius = 0.68
            beam_mesh.height = 0.42
            beam_node.mesh = beam_mesh
            beam_node.position = beam_points[index]
            beam_node.material_override = _glow_material(Color("#9a83ff"), 1.3)
            _add_detail_ring(beam_node, Vector3(0.0, 0.26, 0.0), 0.82, 1.04, Color("#c5b4ff"))
            _add_decor_box(beam_node, Vector3(-0.82, 0.28, 0.0), Vector3(0.3, 0.56, 0.3), Color("#3e356e"), Color("#a98bff"), 0.8)
            _add_decor_box(beam_node, Vector3(0.82, 0.28, 0.0), Vector3(0.3, 0.56, 0.3), Color("#3e356e"), Color("#a98bff"), 0.8)
            beam_node.add_child(_label3d("光束节点 %s" % beam_labels[index], Vector3(0.0, 1.7, 0.0), Color("#d9cfff")))
            beam_root.add_child(beam_node)
            beam_nodes.append(beam_node)
        root.add_child(beam_root)
        beam_visuals[module_id] = beam_nodes

    for point in [Vector3(-3.4, 0.78, 0.0), Vector3(3.4, 0.78, 0.0)]:
        var terminal: MeshInstance3D = MeshInstance3D.new()
        var terminal_mesh: BoxMesh = BoxMesh.new()
        terminal_mesh.size = Vector3(1.15, 0.22, 1.4)
        terminal.mesh = terminal_mesh
        terminal.position = point
        terminal.material_override = _material(Color("#1d284d"), Color("#607fff"), 0.9)
        root.add_child(terminal)
        _add_detail_bolt(root, point + Vector3(-0.38, 0.16, -0.48), Color("#9fb8e8"))
        _add_detail_bolt(root, point + Vector3(0.38, 0.16, 0.48), Color("#9fb8e8"))
    _add_decor_box(root, Vector3(0.0, 0.55, -7.15), Vector3(3.0, 0.12, 0.22), Color("#1b2440"), Color("#a178e8"), 0.8)
    # 路线切换点用灯座和标签表达，避免环形提示在肩后镜头前形成遮挡。
    var route_ring: MeshInstance3D = _add_detail_ring(root, Vector3(0.0, 0.7, -7.15), 0.38, 0.46, Color("#ffca68"))
    route_ring.visible = false

func _create_indicator(point: Vector3, color: Color, title: String) -> MeshInstance3D:
    var indicator: MeshInstance3D = MeshInstance3D.new()
    var mesh: CylinderMesh = CylinderMesh.new()
    # 交互提示必须醒目但不能成为镜头前的白色遮挡体；英雄模块本身
    # 承担大尺度识别，指示器只保留紧凑的灯座和细环。
    mesh.top_radius = 0.50
    mesh.bottom_radius = 0.62
    mesh.height = 0.40
    indicator.mesh = mesh
    indicator.position = point
    indicator.material_override = _glow_material(color, 0.82)
    var interaction_ring: MeshInstance3D = _add_detail_ring(indicator, Vector3(0.0, 0.24, 0.0), 0.32, 0.38, color)
    interaction_ring.visible = false
    indicator.add_child(_label3d(title, Vector3(0.0, 1.28, 0.0), color))
    # 交互设备本体已经有独立英雄网格；隐藏旧的近景灯座，避免相机
    # 靠近时把小型发光体放大成白色前景遮挡。
    indicator.visible = false
    return indicator

func _create_module_label(root: Node3D, module: Dictionary) -> void:
    var id: int = int(module["id"])
    var title: String = String(module["name"])
    var label: Label3D = _label3d("模块 %d · %s" % [id, title], Vector3(0.0, 3.3, 0.0), Color("#ecf0ff"))
    root.add_child(label)

func _build_core() -> void:
    core_node = Node3D.new()
    core_node.name = "MovingFactoryEnergyCore"
    core_node.position = core_dropped_position
    var cage: MeshInstance3D = MeshInstance3D.new()
    var cage_mesh: BoxMesh = BoxMesh.new()
    cage_mesh.size = Vector3(4.6, 3.0, 4.6)
    cage.mesh = cage_mesh
    cage.position.y = 1.2
    cage.material_override = _material(Color("#303967"), Color("#6f85ff"), 0.8)
    core_node.add_child(cage)
    for side in [-1.0, 1.0]:
        _add_decor_box(core_node, Vector3(side * 2.0, 1.2, 0.0), Vector3(0.24, 2.6, 4.2), Color("#48547f"), Color("#91a8ff"), 0.65)
        _add_decor_box(core_node, Vector3(0.0, 1.2, side * 2.0), Vector3(4.2, 2.6, 0.24), Color("#48547f"), Color("#91a8ff"), 0.65)
    _add_detail_bolt(core_node, Vector3(-2.1, 2.55, -2.1), Color("#ffd078"))
    _add_detail_bolt(core_node, Vector3(2.1, 2.55, 2.1), Color("#ffd078"))
    var mesh_node: MeshInstance3D = MeshInstance3D.new()
    var mesh: SphereMesh = SphereMesh.new()
    mesh.radius = 1.1
    mesh.height = 2.2
    mesh_node.mesh = mesh
    mesh_node.material_override = _glow_material(Color("#63efff"), 2.2)
    core_node.add_child(mesh_node)
    var ring: MeshInstance3D = MeshInstance3D.new()
    var ring_mesh: TorusMesh = TorusMesh.new()
    ring_mesh.inner_radius = 1.45
    ring_mesh.outer_radius = 1.54
    ring.mesh = ring_mesh
    ring.material_override = _glow_material(Color("#ffbd65"), 1.4)
    core_node.add_child(ring)
    _add_detail_ring(core_node, Vector3(0.0, 1.2, 0.0), 1.72, 1.84, Color("#8edfff"))
    _add_decor_box(core_node, Vector3(-1.45, 0.52, -1.45), Vector3(0.22, 0.22, 2.0), Color("#4c587c"), Color("#72dce9"), 0.8, -45.0)
    _add_decor_box(core_node, Vector3(1.45, 0.52, 1.45), Vector3(0.22, 0.22, 2.0), Color("#4c587c"), Color("#72dce9"), 0.8, -45.0)
    core_node.add_child(_label3d("中央能源核心\n两人同步搬运", Vector3(0.0, 3.2, 0.0), Color("#b9f7ff")))
    if ResourceLoader.exists(RESONANCE_CORE_ART_PATH):
        var core_scene: PackedScene = ResourceLoader.load(RESONANCE_CORE_ART_PATH) as PackedScene
        var core_art: Node3D = core_scene.instantiate() as Node3D if core_scene != null else null
        if core_art != null:
            core_art.name = "AuthoredEnergyCore"
            core_art.position = Vector3.ZERO
            core_art.set_meta("resonance_visual_asset", RESONANCE_CORE_ART_PATH)
            core_node.add_child(core_art)
            for child in core_node.get_children():
                if child != core_art and child is Node3D:
                    (child as Node3D).visible = false
    core_node.visible = false
    world_root.add_child(core_node)

func _build_extraction() -> void:
    extraction_node = Node3D.new()
    extraction_node.name = "RailFactoryExtraction"
    extraction_node.position = Vector3(66.0, 0.0, -14.0)
    var platform: MeshInstance3D = MeshInstance3D.new()
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = 4.0
    mesh.bottom_radius = 4.0
    mesh.height = 0.18
    platform.mesh = mesh
    platform.material_override = _glow_material(Color("#79e9b7"), 1.4)
    extraction_node.add_child(platform)
    _add_detail_ring(extraction_node, Vector3(0.0, 0.14, 0.0), 3.2, 3.45, Color("#b2f5cf"))
    for arm_index in 4:
        var arm_angle: float = float(arm_index) * PI * 0.5
        _add_decor_box(extraction_node, Vector3(cos(arm_angle) * 3.2, 0.55, sin(arm_angle) * 3.2), Vector3(0.5, 1.1, 1.8), Color("#334b5d"), Color("#79e9b7"), 0.8, -rad_to_deg(arm_angle))
        _add_detail_bolt(extraction_node, Vector3(cos(arm_angle) * 3.2, 1.1, sin(arm_angle) * 3.2), Color("#d6f4cf"))
    extraction_node.add_child(_label3d("返航对接平台", Vector3(0.0, 1.7, 0.0), Color("#9ff5cf")))
    if ResourceLoader.exists(RESONANCE_EXTRACTION_ART_PATH):
        var extraction_scene: PackedScene = ResourceLoader.load(RESONANCE_EXTRACTION_ART_PATH) as PackedScene
        if extraction_scene != null:
            var extraction_art: Node3D = extraction_scene.instantiate() as Node3D
            if extraction_art != null:
                extraction_art.name = "AuthoredExtractionPlatform"
                extraction_art.set_meta("resonance_visual_asset", RESONANCE_EXTRACTION_ART_PATH)
                extraction_node.add_child(extraction_art)
                for child in extraction_node.get_children():
                    if child != extraction_art and child is Node3D:
                        (child as Node3D).visible = false
    world_root.add_child(extraction_node)

func _build_drone_visual() -> void:
    drone_node = Node3D.new()
    drone_node.name = "ResonanceHelperDrone"
    if USE_BLENDER_MASTER_VISUALS and ResourceLoader.exists(RESONANCE_HELPER_DRONE_PATH):
        var authored_scene: PackedScene = ResourceLoader.load(RESONANCE_HELPER_DRONE_PATH) as PackedScene
        var authored: Node3D = authored_scene.instantiate() as Node3D if authored_scene != null else null
        if authored != null:
            authored.name = "BlenderHelperDroneModel"
            authored.set_meta("resonance_visual_asset", RESONANCE_HELPER_DRONE_PATH)
            drone_node.add_child(authored)
    else:
        _build_procedural_helper_drone_visual()
    drone_node.visible = false
    world_root.add_child(drone_node)

func _build_procedural_helper_drone_visual() -> void:
    var body: MeshInstance3D = MeshInstance3D.new()
    var mesh: SphereMesh = SphereMesh.new()
    mesh.radius = 0.48
    mesh.height = 0.96
    body.mesh = mesh
    body.material_override = _glow_material(Color("#8fe8ff"), 2.0)
    drone_node.add_child(body)
    for arm_index in 4:
        var arm_angle: float = float(arm_index) * PI * 0.5
        _add_decor_box(drone_node, Vector3(cos(arm_angle) * 0.55, 0.0, sin(arm_angle) * 0.55), Vector3(0.18, 0.18, 0.72), Color("#50648e"), Color("#8fe8ff"), 1.0, -rad_to_deg(arm_angle))
        _add_detail_bolt(drone_node, Vector3(cos(arm_angle) * 0.82, 0.0, sin(arm_angle) * 0.82), Color("#d4f6ff"))
    var ring: MeshInstance3D = MeshInstance3D.new()
    var ring_mesh: TorusMesh = TorusMesh.new()
    ring_mesh.inner_radius = 0.65
    ring_mesh.outer_radius = 0.72
    ring.mesh = ring_mesh
    ring.material_override = _glow_material(Color("#b4f6ff"), 1.5)
    drone_node.add_child(ring)
    _add_detail_ring(drone_node, Vector3(0.0, -0.2, 0.0), 0.28, 0.38, Color("#5bdcff"))
    var light: OmniLight3D = OmniLight3D.new()
    light.light_color = Color("#5bdcff")
    light.light_energy = 2.8
    light.omni_range = 5.5
    drone_node.add_child(light)
    drone_node.add_child(_label3d("辅助无人机", Vector3(0.0, 1.25, 0.0), Color("#b8f4ff")))

func _build_support_gate() -> void:
    shortcut_node = Node3D.new()
    shortcut_node.name = "SupportSafetyGate"
    shortcut_node.position = Vector3(20.0, 0.0, 25.0)
    if not USE_BLENDER_MASTER_VISUALS:
        var gate: MeshInstance3D = MeshInstance3D.new()
        var mesh: BoxMesh = BoxMesh.new()
        mesh.size = Vector3(5.0, 2.5, 0.5)
        gate.mesh = mesh
        gate.material_override = _glow_material(Color("#c28cff"), 1.4)
        shortcut_node.add_child(gate)
        _add_detail_panel(shortcut_node, Vector3(-1.7, 0.0, -0.32), Vector3(1.2, 1.7, 0.12), Color("#4a3e75"), Color("#d6b3ff"))
        _add_detail_panel(shortcut_node, Vector3(1.7, 0.0, -0.32), Vector3(1.2, 1.7, 0.12), Color("#4a3e75"), Color("#d6b3ff"))
        _add_detail_ring(shortcut_node, Vector3(0.0, 0.0, -0.36), 0.62, 0.78, Color("#d6b3ff"))
        shortcut_node.add_child(_label3d("支援安全闸\n额外玩家开启", Vector3(0.0, 2.0, 0.0), Color("#dfc5ff")))
    shortcut_body = StaticBody3D.new()
    shortcut_body.name = "SupportSafetyGateCollision"
    shortcut_body.collision_layer = 2
    shortcut_body.collision_mask = 1
    var shape: CollisionShape3D = CollisionShape3D.new()
    var box: BoxShape3D = BoxShape3D.new()
    box.size = Vector3(5.0, 2.5, 0.5)
    shape.shape = box
    shortcut_body.add_child(shape)
    shortcut_node.add_child(shortcut_body)
    world_root.add_child(shortcut_node)

func _reset_support_relay() -> void:
    support_relay = {
        "phase": 0,
        "low_peer": 0,
        "high_peer": 0,
        "deadline": 0.0,
        "failures": 0
    }

func _build_support_relay_visuals() -> void:
    var root: Node3D = Node3D.new()
    root.name = "SupportResonanceRelay"
    world_root.add_child(root)
    var low_root: Node3D = Node3D.new()
    low_root.name = "RelayLowSender"
    low_root.position = SUPPORT_RELAY_LOW_POSITION
    _add_decor_box(low_root, Vector3(0.0, 0.34, 0.0), Vector3(3.0, 0.68, 2.2), Color("#25334f"), Color("#ff9b4b"), 0.48)
    var low_ring: MeshInstance3D = _add_detail_ring(low_root, Vector3(0.0, 0.82, 0.0), 0.82, 1.02, Color("#ff9b4b"))
    low_ring.name = "RelayLowIndicator"
    low_root.add_child(_label3d("共振发送端\n先按 E", Vector3(0.0, 2.05, 0.0), Color("#ffd09a")))
    root.add_child(low_root)
    support_relay_nodes["low"] = low_ring

    var high_root: Node3D = Node3D.new()
    high_root.name = "RelayHighReceiver"
    high_root.position = SUPPORT_RELAY_HIGH_POSITION
    _add_decor_box(high_root, Vector3(0.0, 0.34, 0.0), Vector3(3.0, 0.68, 2.2), Color("#2a385b"), Color("#8f9dff"), 0.5)
    var high_ring: MeshInstance3D = _add_detail_ring(high_root, Vector3(0.0, 0.82, 0.0), 0.82, 1.02, Color("#8f9dff"))
    high_ring.name = "RelayHighIndicator"
    high_root.add_child(_label3d("高位接收端\n队友接力", Vector3(0.0, 2.05, 0.0), Color("#cbd0ff")))
    root.add_child(high_root)
    support_relay_nodes["high"] = high_ring

    # 这条斜向维护桥复用第三条高位检修桥的碰撞链；额外的脉冲灯带让玩家
    # 一眼看出低位发送端和高位接收端属于同一段合作机关。
    var bridge_mid: Vector3 = (SUPPORT_RELAY_LOW_POSITION + SUPPORT_RELAY_HIGH_POSITION) * 0.5 + Vector3(0.0, 0.18, 0.0)
    var bridge_length: float = Vector2(SUPPORT_RELAY_HIGH_POSITION.x, SUPPORT_RELAY_HIGH_POSITION.z).distance_to(Vector2(SUPPORT_RELAY_LOW_POSITION.x, SUPPORT_RELAY_LOW_POSITION.z))
    var bridge_angle: float = rad_to_deg(atan2(SUPPORT_RELAY_HIGH_POSITION.z - SUPPORT_RELAY_LOW_POSITION.z, SUPPORT_RELAY_HIGH_POSITION.x - SUPPORT_RELAY_LOW_POSITION.x))
    _add_decor_box(root, bridge_mid, Vector3(bridge_length, 0.12, 2.1), Color("#252b42"), Color("#8f9dff"), 0.32, bridge_angle)
    for pulse_index in 5:
        var ratio: float = (float(pulse_index) + 0.5) / 5.0
        var pulse_point: Vector3 = SUPPORT_RELAY_LOW_POSITION.lerp(SUPPORT_RELAY_HIGH_POSITION, ratio) + Vector3(0.0, 0.34, 0.0)
        _add_decor_box(root, pulse_point, Vector3(0.72, 0.08, 0.12), Color("#283451"), Color("#8f9dff"), 0.62, bridge_angle)
    if USE_BLENDER_MASTER_VISUALS:
        # The authored master scene owns the relay silhouette; this hidden set
        # remains available for state-driven indicators and compatibility.
        root.visible = false
    _refresh_support_relay_visuals()

func _refresh_support_relay_visuals() -> void:
    var phase: int = int(support_relay.get("phase", 0))
    var low_ring: MeshInstance3D = support_relay_nodes.get("low") as MeshInstance3D
    var high_ring: MeshInstance3D = support_relay_nodes.get("high") as MeshInstance3D
    if low_ring != null:
        low_ring.material_override = _glow_material(Color("#6dffbd") if phase >= 1 else Color("#ff9b4b"), 1.55 if phase >= 1 else 0.9)
    if high_ring != null:
        high_ring.material_override = _glow_material(Color("#6dffbd") if phase >= 2 or shortcut_unlocked else Color("#8f9dff"), 1.55 if phase >= 2 or shortcut_unlocked else 0.85)

func _add_box_obstacle(point: Vector3, size: Vector3, color: Color) -> void:
    var visual: MeshInstance3D = MeshInstance3D.new()
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    visual.mesh = mesh
    visual.position = point
    visual.material_override = _material(color, Color("#6a7fd0"), 0.45)
    world_root.add_child(visual)
    var body: StaticBody3D = StaticBody3D.new()
    body.collision_layer = 2
    body.collision_mask = 1
    var shape: CollisionShape3D = CollisionShape3D.new()
    var box: BoxShape3D = BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    body.position = point
    world_root.add_child(body)

func _label3d(text: String, point: Vector3, color: Color) -> Label3D:
    var label: Label3D = Label3D.new()
    label.text = text
    label.position = point
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.font_size = 34
    label.pixel_size = 0.010
    label.modulate = color
    label.outline_size = 8
    label.outline_modulate = Color("#05081d")
    label.shaded = false
    return label

func _material(color: Color, emission: Color, energy: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = emission
    material.emission_energy_multiplier = energy
    material.roughness = 0.5
    return material

func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
    return _material(color, color, energy)

func _current_module() -> Dictionary:
    if checkpoint < 0 or checkpoint >= modules.size():
        return {}
    return modules[checkpoint]

func _current_reactor_challenge() -> Dictionary:
    if reactor_challenge_index < 0 or reactor_challenge_index >= reactor_challenges.size():
        return {}
    return reactor_challenges[reactor_challenge_index]

func _reactor_target_position(challenge: Dictionary, kind: String) -> Vector3:
    if challenge.is_empty():
        return Vector3.ZERO
    var key: String = "%s_position" % kind
    return Vector3(challenge.get(key, Vector3.ZERO))

func _reactor_target_at(point: Vector3) -> Dictionary:
    if not reactor_deck_active:
        return {}
    var challenge: Dictionary = _current_reactor_challenge()
    if challenge.is_empty():
        return {}
    var challenge_id: String = String(challenge.get("id", ""))
    if challenge_id == "coolant":
        if not bool(challenge.get("coolant_loaded", false)):
            var coolant_position: Vector3 = Vector3(challenge["coolant_position"])
            if controller._flat_distance(point, coolant_position) <= MODULE_RADIUS:
                return {"kind": "coolant", "challenge_id": challenge_id}
            var stabilizer_position: Vector3 = Vector3(challenge["stabilizer_position"])
            if controller._flat_distance(point, stabilizer_position) <= MODULE_RADIUS:
                return {"kind": "stabilizer", "challenge_id": challenge_id}
        if reactor_carrier != 0:
            var socket_position: Vector3 = Vector3(challenge["coolant_socket_position"])
            if controller._flat_distance(point, socket_position) <= MODULE_RADIUS:
                return {"kind": "coolant_socket", "challenge_id": challenge_id}
        return {}
    var sequence: Array = challenge.get("sequence", [])
    var step: int = int(challenge.get("step", 0))
    if step >= sequence.size():
        return {}
    for raw_kind in sequence:
        var node_kind: String = String(raw_kind)
        var node_position: Vector3 = _reactor_target_position(challenge, node_kind)
        if controller._flat_distance(point, node_position) <= MODULE_RADIUS:
            return {"kind": node_kind, "challenge_id": challenge_id}
    return {}

func _reactor_operator_token(peer_id: int, step: int) -> int:
    if controller.connected_ids.size() == 1 and step > 0 and bool(drone_state.get("active", false)):
        return -peer_id
    return peer_id

func _module_target_at(point: Vector3) -> Dictionary:
    var module: Dictionary = _current_module()
    if module.is_empty():
        return {}
    if checkpoint == 1 and not shortcut_unlocked:
        return {}
    if String(module.get("mechanic", "switch")) == "freight" and not bool(module.get("cargo_loaded", false)):
        var freight_position: Vector3 = Vector3(module["freight_position"])
        var support_position: Vector3 = Vector3(module["support_position"])
        var freight_distance: float = controller._flat_distance(point, freight_position)
        var support_distance: float = controller._flat_distance(point, support_position)
        if freight_distance <= 2.0 and freight_distance <= support_distance:
            return {"kind": "freight", "module_id": int(module["id"])}
    var rail_position: Vector3 = Vector3(module["rail_position"])
    if controller._flat_distance(point, rail_position) <= MODULE_RADIUS:
        return {"kind": "rail", "module_id": int(module["id"])}
    var clamp_position: Vector3 = Vector3(module["clamp_position"])
    if controller._flat_distance(point, clamp_position) <= MODULE_RADIUS:
        return {"kind": "clamp", "module_id": int(module["id"])}
    var support_position: Vector3 = Vector3(module["support_position"])
    if controller._flat_distance(point, support_position) <= MODULE_RADIUS:
        return {"kind": "support", "module_id": int(module["id"])}
    var safety_position: Vector3 = Vector3(module["safety_position"])
    if controller._flat_distance(point, safety_position) <= MODULE_RADIUS:
        return {"kind": "safety", "module_id": int(module["id"])}
    var route_position: Vector3 = Vector3(module["route_position"])
    if controller._flat_distance(point, route_position) <= ROUTE_RADIUS:
        return {"kind": "route", "module_id": int(module["id"])}
    return {}

func _support_relay_target_at(point: Vector3) -> Dictionary:
    if shortcut_unlocked or not heat_chain_complete or checkpoint < 1:
        return {}
    if controller._flat_distance(point, SUPPORT_RELAY_LOW_POSITION) <= MODULE_RADIUS:
        return {"kind": "low", "position": SUPPORT_RELAY_LOW_POSITION}
    if controller._flat_distance(point, SUPPORT_RELAY_HIGH_POSITION) <= MODULE_RADIUS and absf(point.y - SUPPORT_RELAY_HIGH_POSITION.y) <= 1.8:
        return {"kind": "high", "position": SUPPORT_RELAY_HIGH_POSITION}
    return {}

func _handle_support_relay_action(peer_id: int, player: SpacePlayer3D) -> bool:
    var target: Dictionary = _support_relay_target_at(player.global_position)
    if target.is_empty():
        return false
    var kind: String = String(target["kind"])
    var phase: int = int(support_relay.get("phase", 0))
    if phase == 1 and mission_elapsed > float(support_relay.get("deadline", 0.0)):
        support_relay["phase"] = 0
        support_relay["low_peer"] = 0
        support_relay["high_peer"] = 0
        support_relay["deadline"] = 0.0
        support_relay["failures"] = int(support_relay.get("failures", 0)) + 1
        _refresh_support_relay_visuals()
        controller.show_feedback_rpc.rpc("共振接力超时 · 低位发送端已复位", Color("#ffbd75"), 1.1)
        phase = 0
    if kind == "high":
        if phase == 0:
            _feedback_peer(peer_id, "先由队友在低位启动共振发送端", Color("#ffd28a"), 1.1)
            return true
        var drone_ready: bool = controller.connected_ids.size() == 1 and bool(drone_state.get("active", false)) and int(drone_state.get("owner", 0)) == peer_id and String(drone_state.get("target", "")) == "support_relay_high"
        if drone_ready:
            support_relay["high_peer"] = -peer_id
            support_relay["phase"] = 2
            _complete_support_relay()
            return true
        if int(support_relay.get("low_peer", 0)) == peer_id:
            _feedback_peer(peer_id, "高位接收端需要另一名玩家接力；单人请先部署无人机", Color("#ffd28a"), 1.1)
            return true
        support_relay["high_peer"] = peer_id
        support_relay["phase"] = 2
        _complete_support_relay()
        return true
    if phase == 0:
        support_relay["phase"] = 1
        support_relay["low_peer"] = peer_id
        support_relay["high_peer"] = 0
        support_relay["deadline"] = mission_elapsed + SUPPORT_RELAY_WINDOW
        _refresh_support_relay_visuals()
        controller.show_feedback_rpc.rpc("低位发送端已启动 · 队友在 %.1f 秒内接入高位端" % SUPPORT_RELAY_WINDOW, Color("#9ff5cf"), 1.4)
        _sync_now()
        return true
    if phase == 1:
        _feedback_peer(peer_id, "发送端已锁定 · 让另一名玩家接入高位接收端", Color("#b9c9ff"), 1.0)
        return true
    return true

func _complete_support_relay() -> void:
    support_relay["phase"] = 3
    support_relay["deadline"] = 0.0
    shortcut_unlocked = true
    support_relay_reward_active = true
    if shortcut_node != null:
        shortcut_node.visible = false
    if shortcut_body != null:
        shortcut_body.collision_layer = 0
        shortcut_body.collision_mask = 0
    _refresh_support_relay_visuals()
    controller.show_feedback_rpc.rpc("支援回路已接通 · 安全闸开启，下一条快线过载降低", Color("#9ff5cf"), 1.8)
    controller._record_journal("支援回路接通", "两端共振端在不同高度完成接力，维护桥和安全闸重新获得同步供能。")
    _refresh_objective_guide()
    _sync_now()

func get_stage_action_target(peer_id: int, action: String) -> Dictionary:
    if controller == null:
        return {}
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player == null:
        return {}
    if action == "repair":
        if not heat_chain_complete:
            var heat_key: String = _heat_valve_at(player.global_position)
            if heat_key != "":
                return {"puzzle_id": "heat_valve:%s" % heat_key, "target_id": 0, "kind": heat_key}
            return {}
        var reactor_target: Dictionary = _reactor_target_at(player.global_position)
        if not reactor_target.is_empty():
            return {
                "puzzle_id": "reactor:%s:%s" % [String(reactor_target["challenge_id"]), String(reactor_target["kind"])],
                "target_id": reactor_challenge_index,
                "kind": String(reactor_target["kind"])
            }
        var relay_target: Dictionary = _support_relay_target_at(player.global_position)
        if not relay_target.is_empty():
            return {"puzzle_id": "support_relay:%s" % String(relay_target["kind"]), "target_id": 0, "kind": String(relay_target["kind"])}
        var target: Dictionary = _module_target_at(player.global_position)
        if not target.is_empty():
            var module_id: int = int(target["module_id"])
            return {
                "puzzle_id": "module:%d:%s" % [module_id, String(target["kind"])],
                "target_id": module_id,
                "kind": String(target["kind"])
            }
        if _role_for_peer(peer_id) == "support" and controller._flat_distance(player.global_position, Vector3(20.0, 0.0, 25.0)) <= 4.0:
            return {"puzzle_id": "support_gate", "target_id": 0, "kind": "support_gate"}
    if action == "pickup":
        var reactor_target: Dictionary = _reactor_target_at(player.global_position)
        if String(reactor_target.get("kind", "")) == "coolant" or String(reactor_target.get("kind", "")) == "coolant_socket":
            return {"puzzle_id": "reactor:coolant:%s" % String(reactor_target["kind"]), "target_id": reactor_challenge_index, "kind": String(reactor_target["kind"])}
        var active_module: Dictionary = _current_module()
        if not active_module.is_empty() and String(active_module.get("mechanic", "switch")) == "freight" and not bool(active_module.get("cargo_loaded", false)):
            var freight_distance: float = controller._flat_distance(player.global_position, Vector3(active_module["freight_position"]))
            if freight_carrier == peer_id or freight_distance <= MODULE_RADIUS or controller._flat_distance(player.global_position, Vector3(active_module["support_position"])) <= MODULE_RADIUS:
                return {"puzzle_id": "freight:%d" % int(active_module["id"]), "target_id": int(active_module["id"]), "kind": "freight", "distance": freight_distance}
        if core_node != null:
            return {"puzzle_id": "energy_core", "target_id": 1, "distance": controller._flat_distance(player.global_position, core_node.global_position)}
    if action == "resonance_drone":
        return {"puzzle_id": "drone", "target_id": 0}
    if action == "drop":
        return {"puzzle_id": "carry", "target_id": 0}
    if action == "revive":
        return {"puzzle_id": "revive", "target_id": 0}
    return {}

func handle_stage_action(peer_id: int, action: String, target_id: int) -> void:
    handle_action(peer_id, action)

func feedback_no_target(peer_id: int, action: String) -> void:
    if action == "repair":
        if not heat_chain_complete:
            _feedback_peer(peer_id, "请靠近当前高亮热阀后再按 E", Color("#ffd28a"), 1.0)
        elif checkpoint == 1 and not shortcut_unlocked:
            _feedback_peer(peer_id, "请先完成低位发送端 → 高位接收端支援接力", Color("#d6b3ff"), 1.0)
        elif reactor_deck_active:
            _feedback_peer(peer_id, "请靠近当前高亮反应堆节点后再按 E", Color("#ffd28a"), 1.0)
        else:
            _feedback_peer(peer_id, "请靠近当前高亮模块接口后再按 E", Color("#ffd28a"), 1.0)
    elif action == "pickup":
        _feedback_peer(peer_id, "请靠近黄色货箱、冷却单元或中央核心后再按 F", Color("#ffd28a"), 1.0)

func stage_tick(delta: float) -> void:
    tick(delta)

func stage_return_to_ship(reason: String) -> void:
    if controller != null and is_active():
        controller.return_to_ship(reason)

func spawn_position(peer_id: int) -> Vector3:
    var slots: Array[Vector3] = [
        START_POSITION,
        START_POSITION + Vector3(4.0, 0.0, 0.0),
        START_POSITION + Vector3(8.0, 0.0, 0.0),
        START_POSITION + Vector3(12.0, 0.0, 0.0)
    ]
    return slots[(peer_id - 1) % slots.size()]

func _role_for_peer(peer_id: int) -> String:
    return String(role_assignments.get(peer_id, "support"))

func _role_name(role: String) -> String:
    if role == "conduit":
        return "导能"
    if role == "anchor":
        return "定场"
    return "支援"

func _feedback_peer(peer_id: int, message: String, color: Color, duration: float) -> void:
    if controller == null:
        return
    var peers: PackedInt32Array = controller.multiplayer.get_peers()
    if peer_id == controller.multiplayer.get_unique_id() or peers.has(peer_id):
        controller.show_feedback_rpc.rpc_id(peer_id, message, color, duration)
    else:
        controller.show_feedback_rpc.rpc(message, color, duration)

func _expected_role_for_kind(kind: String) -> String:
    if kind == "rail":
        return "conduit"
    if kind == "clamp":
        return "anchor"
    return "support"

func handle_action(peer_id: int, action: String) -> void:
    if controller == null or not controller.is_host or not is_active():
        return
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed or player.lava_dead:
        return
    var cooldown_key: String = "%d:%s" % [peer_id, action]
    if float(action_cooldowns.get(cooldown_key, 0.0)) > mission_elapsed:
        return
    action_cooldowns[cooldown_key] = mission_elapsed + 0.12
    # 设备类交互改成小游戏：第一次按键开启校准，第二次按键确认。
    if minigames_enabled and (action == "repair" or action == "pickup"):
        if not minigame.is_empty():
            if int(minigame["peer"]) == peer_id:
                _minigame_confirm(peer_id)
            return
        var kind: String = _minigame_kind_for(peer_id, action)
        if kind != "":
            _open_minigame(peer_id, action, kind)
            return
    _apply_stage_action(peer_id, action)

func _apply_stage_action(peer_id: int, action: String) -> void:
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player == null:
        return
    match action:
        "repair":
            if not reactor_deck_active or not _handle_reactor_repair(peer_id, player):
                _handle_repair(peer_id, player)
        "pickup":
            if not reactor_deck_active or not _try_reactor_coolant_action(peer_id, player):
                if not _try_freight_action(peer_id, player):
                    _toggle_core_carrier(peer_id, player)
        "drop":
            if core_carriers.has(peer_id):
                _drop_core(peer_id)
            elif freight_carrier == peer_id:
                _release_freight_carrier(player.global_position)
            elif reactor_carrier == peer_id:
                _release_reactor_carrier(player.global_position)
        "resonance_drone":
            _toggle_drone(peer_id, player)
        "revive":
            _start_revive(peer_id, player)

func _kit_overload_relief_active() -> bool:
    if controller == null or String(controller.kit_mod_for_current_planet()) != "overload_resist":
        return false
    for peer_id in controller.players.keys():
        if String(controller.kit_tool_for(int(peer_id))) == "conduit":
            return true
    return false

func _minigame_kind_for(peer_id: int, action: String) -> String:
    var target: Dictionary = get_stage_action_target(peer_id, action)
    if target.is_empty():
        return ""
    var puzzle: String = String(target.get("puzzle_id", ""))
    if puzzle.begins_with("heat_valve"):
        return "heat_valve"
    if puzzle.begins_with("module:"):
        var module: Dictionary = _current_module()
        var station_kind: String = String(target.get("kind", ""))
        var tool: String = String(controller.kit_tool_for(peer_id))
        # 专属工具直接接管对应接口：导能枪接管供能端，钩索接管夹具，不再走校准。
        if tool == "conduit" and station_kind == "rail":
            return ""
        if tool == "hook" and station_kind == "clamp":
            return ""
        if String(module.get("mechanic", "switch")) == "beam":
            return "beam"
        return "module"
    if puzzle.begins_with("support_relay"):
        return "relay"
    if puzzle.begins_with("reactor:"):
        var challenge: Dictionary = _current_reactor_challenge()
        if String(challenge.get("id", "")) == "mirror":
            return "mirror"
        return "reactor"
    return ""

func _minigame_profile(kind: String) -> Dictionary:
    match kind:
        "heat_valve":
            return {"width": 0.24, "speed": 0.85, "duration": 9.0, "zone": 0.34, "title": "热阀压力校准", "mode": "bar"}
        "module":
            return {"width": 0.20, "speed": 1.05, "duration": 8.0, "zone": 0.46, "title": "接口信号调谐", "mode": "bar"}
        "relay":
            return {"width": 0.18, "speed": 1.20, "duration": 8.0, "zone": 0.55, "title": "共振频率对齐", "mode": "bar"}
        "beam":
            # 光束转盘：窄弧区 + 快速转动的指针，读的是圆盘刻度。
            return {"width": 0.10, "speed": 1.15, "duration": 9.0, "zone": 0.46, "title": "光束转盘对准", "mode": "dial"}
        "mirror":
            # 镜面角度：每次按键转一格，落进目标角度区间即锁定。
            return {"width": 0.11, "speed": 0.0, "duration": 14.0, "zone": 0.42, "title": "镜面角度校准", "mode": "stepped"}
        "reactor":
            return {"width": 0.17, "speed": 1.30, "duration": 7.5, "zone": 0.40, "title": "反应堆相位校准", "mode": "bar"}
    return {"width": 0.20, "speed": 1.00, "duration": 8.0, "zone": 0.45, "title": "设备校准", "mode": "bar"}

func _open_minigame(peer_id: int, action: String, kind: String) -> void:
    var profile: Dictionary = _minigame_profile(kind)
    minigame = {
        "peer": peer_id,
        "action": action,
        "kind": kind,
        "mode": String(profile.get("mode", "bar")),
        "cursor": 0.0,
        "dir": 1.0,
        "speed": float(profile["speed"]),
        "zone_start": float(profile["zone"]),
        "zone_width": float(profile["width"]),
        "remaining": float(profile["duration"]),
        "title": String(profile["title"])
    }
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player != null:
        # 把拉杆装到最近的交互装置上：贴着装置朝向玩家的一侧。
        var anchor_point: Vector3 = _nearest_device_anchor(player.global_position)
        var to_player: Vector3 = player.global_position - anchor_point
        to_player.y = 0.0
        var facing: Vector3 = to_player.normalized() if to_player.length() > 0.05 else Vector3.FORWARD
        var mount: Vector3 = anchor_point + facing * 0.85
        mount.y = anchor_point.y - 0.15
        _minigame_lever = _ensure_device_lever(kind, mount)
        _minigame_lever.look_at(Vector3(player.global_position.x, mount.y, player.global_position.z), Vector3.UP)
    _refresh_minigame_ui()
    var hint: String = "光标进入绿区时按 E 确认"
    if String(minigame["mode"]) == "stepped":
        hint = "连按 E 转动镜面，指针对准绿区后自动锁定"
    elif String(minigame["mode"]) == "dial":
        hint = "指针扫到绿弧时按 E 锁定"
    controller.show_feedback_rpc.rpc("%s · %s" % [String(profile["title"]), hint], Color("#9fe8ff"), 2.0)

func _nearest_device_anchor(point: Vector3) -> Vector3:
    var best: Vector3 = point
    var best_distance: float = 1e9
    for anchor in _visual_collision_anchors():
        var distance: float = point.distance_to(anchor)
        if distance < best_distance:
            best_distance = distance
            best = anchor
    return best

func _ensure_device_lever(kind: String, position: Vector3) -> Node3D:
    # 装置上的可动拉杆：底座 + 可旋转把手，操作过程中跟随光标转动。
    var root: Node3D = Node3D.new()
    root.name = "ResonanceDeviceLever"
    root.position = position
    var base: MeshInstance3D = MeshInstance3D.new()
    var base_mesh: CylinderMesh = CylinderMesh.new()
    base_mesh.top_radius = 0.34
    base_mesh.bottom_radius = 0.42
    base_mesh.height = 0.30
    base.mesh = base_mesh
    base.material_override = _material(Color("#2c3a52"), Color("#5f7fbf"), 0.35)
    root.add_child(base)
    var ring: MeshInstance3D = MeshInstance3D.new()
    var ring_mesh: TorusMesh = TorusMesh.new()
    ring_mesh.inner_radius = 0.44
    ring_mesh.outer_radius = 0.52
    ring.mesh = ring_mesh
    ring.position.y = 0.02
    ring.rotation_degrees.x = 90.0
    ring.material_override = _glow_material(Color("#8fe8ff"), 1.6)
    root.add_child(ring)
    var pivot: Node3D = Node3D.new()
    pivot.name = "HandlePivot"
    pivot.position.y = 0.14
    root.add_child(pivot)
    var handle: MeshInstance3D = MeshInstance3D.new()
    var handle_mesh: BoxMesh = BoxMesh.new()
    handle_mesh.size = Vector3(0.12, 1.05, 0.12)
    handle.mesh = handle_mesh
    handle.position.y = 0.52
    handle.material_override = _glow_material(Color("#ffd979"), 1.1)
    pivot.add_child(handle)
    var knob: MeshInstance3D = MeshInstance3D.new()
    var knob_mesh: SphereMesh = SphereMesh.new()
    knob_mesh.radius = 0.17
    knob_mesh.height = 0.34
    knob.mesh = knob_mesh
    knob.position.y = 1.06
    knob.material_override = _glow_material(Color("#ffe9a8"), 1.6)
    pivot.add_child(knob)
    world_root.add_child(root)
    return root

func _animate_device_lever() -> void:
    if _minigame_lever == null or not is_instance_valid(_minigame_lever):
        return
    var pivot: Node3D = _minigame_lever.get_node_or_null("HandlePivot") as Node3D
    if pivot == null:
        return
    var target_angle: float = lerpf(-0.75, 0.75, clampf(float(minigame.get("cursor", 0.0)), 0.0, 1.0))
    pivot.rotation.x = lerpf(pivot.rotation.x, target_angle, 0.35)

func _tick_minigame(delta: float) -> void:
    if minigame.is_empty():
        return
    minigame["remaining"] = float(minigame["remaining"]) - delta
    var mode: String = String(minigame.get("mode", "bar"))
    if mode != "stepped":
        var speed: float = float(minigame["speed"])
        var direction: float = float(minigame["dir"])
        var cursor: float = float(minigame["cursor"]) + direction * speed * delta
        if cursor >= 1.0:
            cursor = 2.0 - cursor
            direction = -1.0
        elif cursor <= 0.0:
            cursor = -cursor
            direction = 1.0
        minigame["cursor"] = clampf(cursor, 0.0, 1.0)
        minigame["dir"] = direction
    _animate_device_lever()
    if float(minigame["remaining"]) <= 0.0:
        var peer: int = int(minigame["peer"])
        _close_device_lever(false)
        minigame = {}
        _refresh_minigame_ui()
        _feedback_peer(peer, "校准超时 · 重新对准", Color("#ffbd75"), 1.2)
        return
    _refresh_minigame_ui()

func _minigame_confirm(peer_id: int) -> void:
    if minigame.is_empty() or int(minigame["peer"]) != peer_id:
        return
    var mode: String = String(minigame.get("mode", "bar"))
    var cursor: float = float(minigame["cursor"])
    if mode == "stepped":
        # 镜面：每次按键转 1/12 圈，越过 100% 后回到 0。
        cursor = fmod(cursor + 1.0 / 12.0, 1.0)
        minigame["cursor"] = cursor
        _animate_device_lever()
    var start: float = float(minigame["zone_start"])
    var width: float = float(minigame["zone_width"])
    var hit: bool = cursor >= start and cursor <= start + width
    if mode == "stepped" and not hit:
        # 没对准不关闭，可以继续转。
        _refresh_minigame_ui()
        _feedback_peer(peer_id, "镜面角度偏离 · 继续按 E 转动", Color("#ffd28a"), 0.8)
        return
    var action: String = String(minigame["action"])
    _close_device_lever(hit)
    minigame = {}
    _refresh_minigame_ui()
    if not hit:
        _feedback_peer(peer_id, "校准偏差过大 · 重新对准", Color("#ff9a6a"), 1.2)
        return
    _feedback_peer(peer_id, "校准成功", Color("#9ff5cf"), 1.0)
    _apply_stage_action(peer_id, action)

func _close_device_lever(success: bool) -> void:
    if _minigame_lever == null or not is_instance_valid(_minigame_lever):
        _minigame_lever = null
        return
    var pivot: Node3D = _minigame_lever.get_node_or_null("HandlePivot") as Node3D
    if pivot != null:
        pivot.rotation.x = 0.75 if success else -0.75
    _minigame_lever.queue_free()
    _minigame_lever = null

func _build_minigame_ui() -> void:
    minigame_layer = CanvasLayer.new()
    minigame_layer.name = "ResonanceMinigameLayer"
    minigame_layer.layer = 20
    add_child(minigame_layer)
    var panel: Panel = Panel.new()
    panel.position = Vector2(330, 380)
    panel.size = Vector2(620, 210)
    var style: StyleBoxFlat = StyleBoxFlat.new()
    style.bg_color = Color(0.05, 0.09, 0.14, 0.92)
    style.border_color = Color("#4fd8ff")
    style.set_border_width_all(2)
    style.set_corner_radius_all(10)
    panel.add_theme_stylebox_override("panel", style)
    minigame_layer.add_child(panel)
    minigame_label = Label.new()
    minigame_label.position = Vector2(20, 14)
    minigame_label.size = Vector2(580, 28)
    minigame_label.add_theme_font_size_override("font_size", 20)
    minigame_label.add_theme_color_override("font_color", Color("#bfe9ff"))
    panel.add_child(minigame_label)
    # 三种形状共用一块自绘仪表：bar 画计时条，dial/stepped 画圆盘刻度。
    minigame_gauge = Control.new()
    minigame_gauge.set_script(MINIGAME_GAUGE)
    minigame_gauge.position = Vector2(20, 52)
    minigame_gauge.size = Vector2(580, 148)
    panel.add_child(minigame_gauge)

func _refresh_minigame_ui() -> void:
    if minigame.is_empty():
        if minigame_layer != null:
            minigame_layer.visible = false
        return
    if minigame_layer == null:
        _build_minigame_ui()
    minigame_layer.visible = true
    var mode: String = String(minigame.get("mode", "bar"))
    var cursor: float = float(minigame["cursor"])
    if minigame_gauge != null:
        minigame_gauge.mode = mode
        minigame_gauge.cursor = cursor
        minigame_gauge.zone_start = float(minigame["zone_start"])
        minigame_gauge.zone_width = float(minigame["zone_width"])
        minigame_gauge.accent = Color("#7ef2c8") if mode == "stepped" else Color("#ffe27a")
        minigame_gauge.queue_redraw()
    if mode == "stepped":
        minigame_label.text = "%s · 角度 %d° · 剩余 %.1f 秒 · 按 E 转动" % [
            String(minigame["title"]), int(round(cursor * 360.0)), float(minigame["remaining"])]
    elif mode == "dial":
        minigame_label.text = "%s · 剩余 %.1f 秒 · 指针进绿弧按 E" % [String(minigame["title"]), float(minigame["remaining"])]
    else:
        minigame_label.text = "%s · 剩余 %.1f 秒 · 光标进绿区按 E" % [String(minigame["title"]), float(minigame["remaining"])]

func _handle_reactor_repair(peer_id: int, player: SpacePlayer3D) -> bool:
    var target: Dictionary = _reactor_target_at(player.global_position)
    if target.is_empty():
        return false
    var challenge: Dictionary = _current_reactor_challenge()
    var challenge_id: String = String(target["challenge_id"])
    var kind: String = String(target["kind"])
    if challenge_id == "coolant" and (kind == "coolant" or kind == "coolant_socket"):
        _feedback_peer(peer_id, "这里使用 F 搬运冷却单元", Color("#ffd28a"), 0.9)
        return true
    if challenge_id == "coolant" and kind == "stabilizer":
        if reactor_carrier == peer_id:
            _feedback_peer(peer_id, "携带冷却单元时不能稳定接收座", Color("#ffbd75"), 1.0)
            return true
        reactor_stabilizer = peer_id
        controller.show_feedback_rpc.rpc("冷却接收座已稳定 · 搬运者可以靠近", Color("#9ff5cf"), 1.0)
        _sync_now()
        return true
    var sequence: Array = challenge.get("sequence", [])
    var step: int = int(challenge.get("step", 0))
    var expected: String = String(sequence[step]) if step < sequence.size() else ""
    var operators: Array = challenge.get("operators", [])
    if kind != expected:
        challenge["step"] = 0
        challenge["operators"] = []
        controller.show_feedback_rpc.rpc("反应堆校准顺序错误 · 回到第一个节点", Color("#ffbd75"), 1.1)
        _sync_now()
        return true
    if controller.connected_ids.size() > 1 and not operators.is_empty() and int(operators.back()) == peer_id:
        _feedback_peer(peer_id, "这个反应堆任务需要队友接力操作", Color("#ffd28a"), 1.0)
        return true
    operators.append(_reactor_operator_token(peer_id, step))
    step += 1
    challenge["step"] = step
    challenge["operators"] = operators
    controller.show_feedback_rpc.rpc("反应堆 %s：%s 已完成" % [String(challenge["name"]), _reactor_kind_name(kind)], Color("#bca8ff"), 0.9)
    if step >= sequence.size():
        _complete_reactor_challenge()
    else:
        _sync_now()
    return true

func _reactor_kind_name(kind: String) -> String:
    if kind == "lower":
        return "低位控制"
    if kind == "upper":
        return "高位控制"
    if kind == "left":
        return "左侧反射"
    if kind == "right":
        return "右侧反射"
    return "中央反射"

func _try_reactor_coolant_action(peer_id: int, player: SpacePlayer3D) -> bool:
    var challenge: Dictionary = _current_reactor_challenge()
    if challenge.is_empty() or String(challenge.get("id", "")) != "coolant" or bool(challenge.get("coolant_loaded", false)):
        return false
    var coolant_position: Vector3 = Vector3(challenge["coolant_position"])
    var socket_position: Vector3 = Vector3(challenge["coolant_socket_position"])
    if reactor_carrier == peer_id:
        if controller._flat_distance(player.global_position, socket_position) > MODULE_RADIUS:
            _feedback_peer(peer_id, "把冷却单元护送到反应堆接收座再按 F", Color("#ffd28a"), 1.0)
            return true
        var stabilizer_ready: bool = false
        if controller.connected_ids.size() == 1:
            stabilizer_ready = bool(drone_state.get("active", false))
        else:
            stabilizer_ready = reactor_stabilizer != 0 and reactor_stabilizer != peer_id
        if not stabilizer_ready:
            _feedback_peer(peer_id, "需要队友先稳定冷却接收座，再按 F 放入单元", Color("#ffd28a"), 1.2)
            return true
        challenge["coolant_loaded"] = true
        player.carrying = 0
        player.carrying_id = 0
        reactor_carrier = 0
        controller.show_feedback_rpc.rpc("冷却单元已接入 · 反应堆温度下降", Color("#9ff5cf"), 1.4)
        _complete_reactor_challenge()
        return true
    if reactor_carrier != 0:
        _feedback_peer(peer_id, "冷却单元正在由队友护送", Color("#ffbd75"), 0.9)
        return true
    if controller._flat_distance(player.global_position, coolant_position) > MODULE_RADIUS:
        return false
    reactor_carrier = peer_id
    player.carrying = 5
    player.carrying_id = reactor_challenge_index
    controller.show_feedback_rpc.rpc("冷却单元已接入 · 搬运者不能攻击", Color("#ffd28a"), 1.3)
    _sync_now()
    return true

func _complete_reactor_challenge() -> void:
    var finished: Dictionary = _current_reactor_challenge()
    if finished.is_empty():
        return
    controller.show_feedback_rpc.rpc("反应堆甲板：%s 完成" % String(finished.get("name", "任务")), Color("#9ff5cf"), 1.3)
    reactor_challenge_index += 1
    reactor_stabilizer = 0
    reactor_carrier = 0
    if reactor_challenge_index >= reactor_challenges.size():
        reactor_deck_active = false
        _set_vertical_shaft_gate_open(true)
        if core_node != null:
            core_node.visible = not core_delivered
        chapter = 4
        controller.show_feedback_rpc.rpc("反应堆甲板全部稳定 · 中央能源核心开放", Color("#9ff5ff"), 2.0)
    else:
        _set_vertical_shaft_gate_open(false)
        var next_challenge: Dictionary = _current_reactor_challenge()
        controller.show_feedback_rpc.rpc("下一段：%s" % String(next_challenge.get("name", "反应堆任务")), Color("#b9c9ff"), 1.1)
    _refresh_objective_guide()
    _refresh_reactor_mechanism_visuals()
    _sync_now()

func _release_reactor_carrier(drop_position: Vector3 = Vector3.INF) -> void:
    if reactor_carrier == 0:
        return
    var carrier: SpacePlayer3D = controller.players.get(reactor_carrier) as SpacePlayer3D
    if carrier != null:
        carrier.carrying = 0
        carrier.carrying_id = 0
    reactor_carrier = 0
    _feedback_peer(0, "冷却单元掉落 · 回到反应堆甲板重新接入", Color("#ffbd75"), 1.2)
    _sync_now()

func _legacy_handle_action_marker() -> void:
    pass

func _is_lava_position(point: Vector3) -> bool:
    if absf(point.x) >= LAVA_MARGIN_X or absf(point.z) >= LAVA_MARGIN_Z:
        return true
    var flat: Vector2 = Vector2(point.x, point.z)
    # 中层观景桥是高架安全面：只有在桥面高度才豁免熔岩判定。
    if point.y >= OBSERVATION_BRIDGE_Y and OBSERVATION_BRIDGE_RECT.has_point(flat):
        return false
    for rect in LAVA_PIT_RECTS:
        if rect.has_point(flat):
            return true
    for rect in SAFE_DECK_RECTS:
        if rect.has_point(flat):
            return false
    for raw_segment in SAFE_PATH_SEGMENTS:
        var segment: Array = raw_segment
        if _point_near_safe_segment(flat, Vector2(segment[0]), Vector2(segment[1]), 3.6):
            return false
    # 高位维护桥与升降平台是第二层安全地面；其地面判定只在桥面高度生效。
    if point.y >= 2.0:
        for elevated_point in ELEVATED_PLATFORM_POINTS:
            if flat.distance_to(elevated_point) <= 9.5:
                return false
    return true

func _point_near_safe_segment(point: Vector2, start: Vector2, finish: Vector2, radius: float) -> bool:
    var direction: Vector2 = finish - start
    var length_squared: float = direction.length_squared()
    if length_squared <= 0.0001:
        return point.distance_to(start) <= radius
    var ratio: float = clampf((point - start).dot(direction) / length_squared, 0.0, 1.0)
    return point.distance_to(start + direction * ratio) <= radius

func _heat_valve_at(point: Vector3) -> String:
    for key_value in heat_valve_positions.keys():
        var key: String = String(key_value)
        if controller._flat_distance(point, Vector3(heat_valve_positions[key])) <= 2.8:
            return key
    return ""

func _heat_valves_complete() -> bool:
    return int(heat_valves.get("left", 0)) == 1 and int(heat_valves.get("right", 0)) == 1 and int(heat_valves.get("relief", 0)) == 1

func _toggle_heat_valve(peer_id: int, key: String) -> void:
    var expected: String = "left"
    if int(heat_valves.get("left", 0)) == 1:
        expected = "right"
    if int(heat_valves.get("right", 0)) == 1:
        expected = "relief"
    if key != expected:
        _feedback_peer(peer_id, "热阀必须按左阀 → 右阀 → 泄压阀顺序开启", Color("#ffbd75"), 1.2)
        return
    if controller.connected_ids.size() > 1 and not heat_valve_operators.is_empty() and heat_valve_operators.back() == peer_id:
        _feedback_peer(peer_id, "洞底热阀需要交替操作 · 换另一名队友接力", Color("#ffd28a"), 1.1)
        return
    heat_valves[key] = 1
    heat_valve_operators.append(peer_id)
    if _heat_valves_complete():
        heat_chain_complete = true
        controller.show_feedback_rpc.rpc("三段热阀已同步 · 低位快线和升降桥联动开启", Color("#9ff5cf"), 1.5)
    else:
        controller.show_feedback_rpc.rpc("热阀 %s 已开启 · 下一段阀门已解锁" % ("左" if key == "left" else ("右" if key == "right" else "泄压")), Color("#ffd28a"), 1.0)
    _refresh_objective_guide()
    _sync_now()

func _handle_repair(peer_id: int, player: SpacePlayer3D) -> void:
    var valve_key: String = _heat_valve_at(player.global_position)
    if not heat_chain_complete:
        if valve_key != "":
            _toggle_heat_valve(peer_id, valve_key)
        else:
            _feedback_peer(peer_id, "先完成洞底热阀链：左阀 → 右阀 → 泄压阀", Color("#ffbd75"), 1.1)
        return
    if _handle_support_relay_action(peer_id, player):
        return
    var target: Dictionary = _module_target_at(player.global_position)
    if target.is_empty():
        if _role_for_peer(peer_id) == "support" and controller._flat_distance(player.global_position, Vector3(20.0, 0.0, 25.0)) <= 4.0:
            _feedback_peer(peer_id, "支援闸已锁定 · 先完成低位发送端与高位接收端接力", Color("#d6b3ff"), 1.3)
        elif checkpoint == 1 and not shortcut_unlocked:
            _feedback_peer(peer_id, "第二节模块尚未开放 · 先完成上下层支援接力", Color("#d6b3ff"), 1.3)
        return
    var module_id: int = int(target["module_id"])
    var kind: String = String(target["kind"])
    var module: Dictionary = modules[module_id - 1]
    if String(module["state"]) == "sealed" or String(module["state"]) == "docked":
        controller.show_feedback_rpc.rpc("模块 %d 尚未开放，请先完成前一段轨道任务" % module_id, Color("#ffd28a"), 1.0)
        return
    if kind == "freight":
        _feedback_peer(peer_id, "按 F 接入磁力货箱，再搬到绿色插槽", Color("#ffd28a"), 1.0)
        return
    if kind == "route":
        if String(module.get("mechanic", "switch")) == "beam":
            _handle_beam_node(module, kind, peer_id)
            return
        _toggle_route(module)
        return
    if String(module.get("mechanic", "switch")) == "beam" and (kind == "support" or kind == "safety"):
        _handle_beam_node(module, kind, peer_id)
        return
    var expected_role: String = _expected_role_for_kind(kind)
    var role: String = _role_for_peer(peer_id)
    var is_drone: bool = bool(drone_state["active"]) and int(drone_state["owner"]) == peer_id and role != expected_role
    var freight_stabilizer: bool = String(module.get("mechanic", "switch")) == "freight" and kind == "support"
    if role != expected_role and not is_drone and not freight_stabilizer:
        _feedback_peer(peer_id, "这个设备需要%s" % _role_name(expected_role), Color("#ffcf75"), 1.3)
        return
    var slot_key: String = "rail_peer" if kind == "rail" else ("clamp_peer" if kind == "clamp" else ("support_peer" if kind == "support" else "safety_peer"))
    var current_peer: int = int(module[slot_key])
    if current_peer == peer_id or current_peer == -peer_id:
        module[slot_key] = 0
        if String(drone_state.get("target", "")) == "module:%d:%s" % [module_id, kind]:
            drone_state["target"] = ""
        controller.show_feedback_rpc.rpc("模块 %d 已解除%s" % [module_id, _slot_name(kind)], Color("#b9c9ff"), 0.8)
    elif current_peer == 0:
        module[slot_key] = -peer_id if is_drone else peer_id
        if is_drone:
            drone_state["target"] = "module:%d:%s" % [module_id, kind]
        controller.show_feedback_rpc.rpc("模块 %d %s已锁定" % [module_id, _slot_name(kind)], _slot_color(kind), 0.9)
    else:
        _feedback_peer(peer_id, "这个接口已有队友占用", Color("#ffbd75"), 0.9)
    _try_begin_docking(module)
    _refresh_module_visual(module)
    _sync_now()

func _slot_name(kind: String) -> String:
    if kind == "rail":
        return "轨道供能"
    if kind == "clamp":
        return "对接夹具"
    if kind == "support":
        return "保险栓"
    return "安全锚点"

func _slot_color(kind: String) -> Color:
    if kind == "rail":
        return Color("#47dfff")
    if kind == "clamp":
        return Color("#ffca68")
    if kind == "support":
        return Color("#77f0b7")
    return Color("#c28cff")

func _toggle_route(module: Dictionary) -> void:
    if String(module["state"]) != "ready":
        return
    var choice: String = "fast" if String(module["route_choice"]) == "safe" else "safe"
    module["route_choice"] = choice
    module["fast_route_used"] = choice == "fast"
    controller.show_feedback_rpc.rpc("模块 %d 已切换%s" % [int(module["id"]), "低位快线" if choice == "fast" else "安全检修轨"], Color("#ffdca0"), 1.1)
    _refresh_module_visual(module)
    _sync_now()

func _handle_beam_node(module: Dictionary, kind: String, peer_id: int) -> void:
    var sequence: Array = module.get("beam_sequence", ["support", "route", "safety"])
    var step: int = int(module.get("beam_step", 0))
    var expected: String = String(sequence[step]) if step < sequence.size() else ""
    var operators: Array = module.get("beam_operators", [])
    if controller.connected_ids.size() > 1 and not operators.is_empty() and int(operators.back()) == peer_id:
        controller.show_feedback_rpc.rpc("光束需要交替操作 · 换另一名队友激活下一个节点", Color("#ffd28a"), 1.1)
        return
    if kind != expected:
        module["beam_step"] = 0
        module["mechanic_progress"] = 0.0
        module["beam_operators"] = []
        controller.show_feedback_rpc.rpc("光束顺序错误 · 回到节点 A 重新校准", Color("#ffbd75"), 1.2)
    else:
        step += 1
        module["beam_step"] = step
        module["mechanic_progress"] = float(step) / float(sequence.size())
        operators.append(peer_id)
        module["beam_operators"] = operators
        controller.show_feedback_rpc.rpc("光束节点 %s 校准完成 · 下一节点已点亮" % _beam_node_name(kind), Color("#bca8ff"), 0.95)
        if step >= sequence.size():
            controller.show_feedback_rpc.rpc("三节点光束已同步 · 可以接入供能和夹具", Color("#9ff5cf"), 1.3)
    _refresh_module_visual(module)
    _sync_now()

func _beam_node_name(kind: String) -> String:
    if kind == "support":
        return "A"
    if kind == "route":
        return "B"
    return "C"

func _try_begin_docking(module: Dictionary) -> void:
    if String(module["state"]) != "ready":
        return
    var mechanic: String = String(module.get("mechanic", "switch"))
    if mechanic == "freight" and not bool(module.get("cargo_loaded", false)):
        return
    if mechanic == "beam" and int(module.get("beam_step", 0)) < 3:
        return
    var rail_peer: int = int(module["rail_peer"])
    var clamp_peer: int = int(module["clamp_peer"])
    if rail_peer == 0 or clamp_peer == 0:
        return
    module["state"] = "docking"
    module["phase"] = "docking"
    module["docking_progress"] = 0.0
    module["overload"] = 0.0
    module["route_locked"] = true
    module["relay_relief"] = support_relay_reward_active
    if support_relay_reward_active:
        support_relay_reward_active = false
        controller.show_feedback_rpc.rpc("支援回路效果生效 · 当前快线过载增长降低", Color("#9ff5cf"), 1.1)
    controller.show_feedback_rpc.rpc("模块 %d 开始移动对接 · 保持轨道供能和夹具锁止" % int(module["id"]), Color("#9ff5cf"), 1.5)

func _operator_valid(module: Dictionary, slot_key: String, point: Vector3) -> bool:
    var peer_id: int = int(module.get(slot_key, 0))
    if peer_id == 0:
        return false
    if peer_id < 0:
        var owner: SpacePlayer3D = controller.players.get(-peer_id) as SpacePlayer3D
        return bool(drone_state["active"]) and int(drone_state["owner"]) == -peer_id and owner != null and controller._flat_distance(Vector3(drone_state["position"]), point) <= OPERATOR_RADIUS
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return false
    if controller.connected_ids.size() == 1 and bool(drone_state["active"]) and int(drone_state["owner"]) == peer_id:
        var other_slot: String = "clamp_peer" if slot_key == "rail_peer" else "rail_peer"
        if int(module.get(other_slot, 0)) == -peer_id:
            return true
    return controller._flat_distance(player.global_position, point) <= OPERATOR_RADIUS

func _refresh_module_points(module: Dictionary) -> void:
    var position: Vector3 = Vector3(module["position"])
    module["rail_position"] = position + Vector3(-3.4, 0.0, 0.0)
    module["clamp_position"] = position + Vector3(3.4, 0.0, 0.0)
    module["left_position"] = module["rail_position"]
    module["right_position"] = module["clamp_position"]
    module["support_position"] = position + Vector3(0.0, 0.0, 3.8)
    module["safety_position"] = position + Vector3(0.0, 0.0, -3.6)
    module["route_position"] = position + Vector3(0.0, 0.0, -7.2)
    if not bool(module.get("freight_custom_position", false)):
        module["freight_position"] = position + Vector3(0.0, 0.0, 5.0)

func _tick_modules(delta: float) -> void:
    if checkpoint >= modules.size():
        return
    var module: Dictionary = modules[checkpoint]
    _refresh_module_points(module)
    if freight_carrier != 0:
        var freight_player: SpacePlayer3D = controller.players.get(freight_carrier) as SpacePlayer3D
        if freight_player == null or freight_player.downed:
            _release_freight_carrier(freight_player.global_position if freight_player != null else Vector3.INF)
    var state: String = String(module["state"])
    if state == "ready":
        if int(module["rail_peer"]) != 0 and not _operator_valid(module, "rail_peer", Vector3(module["rail_position"])):
            module["rail_peer"] = 0
        if int(module["clamp_peer"]) != 0 and not _operator_valid(module, "clamp_peer", Vector3(module["clamp_position"])):
            module["clamp_peer"] = 0
    if state == "docking":
        var rail_ok: bool = _operator_valid(module, "rail_peer", Vector3(module["rail_position"]))
        var clamp_ok: bool = _operator_valid(module, "clamp_peer", Vector3(module["clamp_position"]))
        if not rail_ok or not clamp_ok:
            module["docking_progress"] = maxf(float(module["docking_progress"]) - delta * 0.75, 0.0)
            module["overload"] = maxf(float(module["overload"]) - delta * 0.2, 0.0)
            return
        var support_bonus: float = 0.75 if int(module["support_peer"]) != 0 else 0.0
        var safety_bonus: float = 0.35 if int(module["safety_peer"]) != 0 else 0.0
        var fast_route: bool = String(module["route_choice"]) == "fast"
        var rate: float = 1.0 / (FAST_DOCK_TIME if fast_route else DOCK_TIME)
        rate += support_bonus * 0.08 + safety_bonus * 0.04
        module["docking_progress"] = minf(float(module["docking_progress"]) + delta * rate, 1.0)
        if fast_route and int(module["support_peer"]) == 0:
            var relay_relief: float = 0.35 if bool(module.get("relay_relief", false)) else 0.0
            var overload_gain: float = maxf((1.0 if storm_active else 0.65) - relay_relief, 0.18)
            # 共振星改装「抗过载」：队伍里有人带导能枪时，快线压力减半。
            if _kit_overload_relief_active():
                overload_gain *= 0.5
            module["overload"] = float(module["overload"]) + delta * overload_gain
        else:
            module["overload"] = maxf(float(module["overload"]) - delta * 0.15, 0.0)
        if float(module["overload"]) >= OVERLOAD_LIMIT:
            _reset_module(module, "快线过载 · 当前模块退回站台")
            return
        if float(module["docking_progress"]) >= 1.0:
            module["state"] = "traveling"
            module["phase"] = "traveling"
            module["travel_progress"] = 0.0
            controller.show_feedback_rpc.rpc("模块 %d 已脱离站台 · 正在沿轨道移动" % int(module["id"]), Color("#9ff5cf"), 1.5)
    elif state == "traveling":
        var travel_progress: float = minf(float(module["travel_progress"]) + delta / TRAVEL_TIME, 1.0)
        module["travel_progress"] = travel_progress
        var start_position: Vector3 = Vector3(module["start_position"])
        var dock_position: Vector3 = Vector3(module["dock_position"])
        var current_position: Vector3 = start_position.lerp(dock_position, travel_progress)
        module["position"] = current_position
        _refresh_module_points(module)
        var node: Node3D = module_nodes.get(int(module["id"])) as Node3D
        if node != null:
            node.position = current_position
        if travel_progress >= 1.0:
            module["state"] = "docked"
            module["phase"] = "docked"
            module["progress"] = 1.0
            checkpoint = maxi(checkpoint, int(module["id"]))
            chapter = checkpoint
            var next_index: int = checkpoint
            if next_index < modules.size():
                modules[next_index]["state"] = "ready"
                modules[next_index]["phase"] = "ready"
            _on_module_docked(int(module["id"]))
            _refresh_module_visual(module)
            _sync_now()

func _reset_module(module: Dictionary, reason: String) -> void:
    module["state"] = "ready"
    module["phase"] = "ready"
    module["route_locked"] = false
    module["rail_peer"] = 0
    module["clamp_peer"] = 0
    module["support_peer"] = 0
    module["safety_peer"] = 0
    module["docking_progress"] = 0.0
    module["overload"] = 0.0
    module["travel_progress"] = 0.0
    module["relay_relief"] = false
    module["beam_step"] = 0
    module["beam_operators"] = []
    module["mechanic_progress"] = 0.0
    controller.show_feedback_rpc.rpc(reason, Color("#ffbd75"), 1.4)
    _refresh_module_visual(module)
    _sync_now()

func _on_module_docked(module_id: int) -> void:
    var module: Dictionary = modules[module_id - 1]
    if String(drone_state.get("target", "")).begins_with("module:%d:" % module_id):
        drone_state["target"] = ""
    controller._record_journal("轨道模块 %d 对接" % module_id, "模块沿能源轨道完成移动，对接夹具锁住了下一段设施。")
    controller.show_feedback_rpc.rpc("模块 %d 已对接 · 下一段轨道开放" % module_id, Color("#9ff5cf"), 1.8)
    _spawn_security_drones(module_id)
    if module_id >= MODULE_COUNT:
        reactor_deck_active = true
        reactor_challenge_index = 0
        reactor_stabilizer = 0
        reactor_carrier = 0
        core_node.visible = false
        _refresh_objective_guide()
        controller.show_feedback_rpc.rpc("反应堆甲板开放 · 先完成三段稳定任务", Color("#9ff5ff"), 2.0)
    _sync_now()

func _try_freight_action(peer_id: int, player: SpacePlayer3D) -> bool:
    var module: Dictionary = _current_module()
    if module.is_empty() or String(module.get("mechanic", "switch")) != "freight" or bool(module.get("cargo_loaded", false)):
        return false
    if checkpoint == 1 and not shortcut_unlocked:
        _feedback_peer(peer_id, "第二节模块尚未开放 · 先完成上下层支援接力", Color("#d6b3ff"), 1.0)
        return true
    var freight_position: Vector3 = Vector3(module["freight_position"])
    var support_position: Vector3 = Vector3(module["support_position"])
    if freight_carrier == peer_id:
        if controller._flat_distance(player.global_position, support_position) > MODULE_RADIUS:
            _feedback_peer(peer_id, "把磁力货箱带到绿色插槽再按 F", Color("#ffd28a"), 1.0)
            return true
        var stabilizer_ready: bool = false
        if controller.connected_ids.size() == 1:
            stabilizer_ready = bool(drone_state.get("active", false))
        else:
            var stabilizer_peer: int = int(module.get("support_peer", 0))
            stabilizer_ready = stabilizer_peer != 0 and stabilizer_peer != peer_id and _operator_valid(module, "support_peer", support_position)
        if not stabilizer_ready:
            _feedback_peer(peer_id, "需要队友先按 E 稳住绿色插槽，再按 F 放入货箱", Color("#ffd28a"), 1.2)
            return true
        module["cargo_loaded"] = true
        module["mechanic_progress"] = 1.0
        freight_carrier = 0
        player.carrying = 0
        player.carrying_id = 0
        controller.show_feedback_rpc.rpc("磁力货箱已接入绿色插槽 · 模块获得分流供能", Color("#9ff5cf"), 1.4)
        _refresh_module_visual(module)
        _sync_now()
        return true
    if freight_carrier != 0:
        _feedback_peer(peer_id, "磁力货箱正在由队友搬运", Color("#ffbd75"), 0.9)
        return true
    if controller._flat_distance(player.global_position, freight_position) > MODULE_RADIUS:
        return false
    freight_carrier = peer_id
    module["mechanic_progress"] = 0.5
    player.carrying = 4
    player.carrying_id = int(module["id"])
    controller.show_feedback_rpc.rpc("磁力货箱已接入 · 搬到模块绿色插槽", Color("#ffd28a"), 1.3)
    _refresh_module_visual(module)
    _sync_now()
    return true

func _release_freight_carrier(drop_position: Vector3 = Vector3.INF) -> void:
    if freight_carrier == 0:
        return
    var carrier: SpacePlayer3D = controller.players.get(freight_carrier) as SpacePlayer3D
    if carrier != null:
        if drop_position == Vector3.INF:
            drop_position = carrier.global_position
        carrier.carrying = 0
        carrier.carrying_id = 0
    var module: Dictionary = _current_module()
    if not module.is_empty() and String(module.get("mechanic", "switch")) == "freight" and not bool(module.get("cargo_loaded", false)):
        module["mechanic_progress"] = 0.0
        module["freight_position"] = drop_position if drop_position != Vector3.INF else Vector3(module["position"]) + Vector3(0.0, 0.0, 5.0)
        module["freight_custom_position"] = drop_position != Vector3.INF
        _refresh_module_visual(module)
    freight_carrier = 0
    _sync_now()

func _spawn_security_drones(module_id: int) -> void:
    var module: Dictionary = modules[module_id - 1]
    if bool(module["security_spawned"]):
        return
    module["security_spawned"] = true
    var count: int = 1 if controller.connected_ids.size() <= 2 else 2
    if String(module["route_choice"]) == "fast":
        count += 1
    if int(module["support_peer"]) != 0:
        count = maxi(count - 1, 1)
    if bool(module.get("relay_relief", false)):
        count = maxi(count - 1, 0)
    for index in count:
        var enemy: SpaceEnemy3D = controller.create_space_enemy(controller.connected_ids.size(), controller.next_enemy_id) as SpaceEnemy3D
        if enemy == null:
            continue
        var center: Vector3 = Vector3(module["position"])
        enemy.position = center + Vector3(float(index * 2 - count), 0.0, 7.5)
        controller.add_child(enemy)
        controller.enemies[controller.next_enemy_id] = enemy
        controller.next_enemy_id += 1
        for label_value in enemy.find_children("*", "Label3D", true, false):
            var label: Label3D = label_value as Label3D
            if label != null:
                label.text = "【轨道安保】\n守卫移动模块"

func _toggle_core_carrier(peer_id: int, player: SpacePlayer3D) -> void:
    if core_delivered or checkpoint < CHECKPOINTS or core_node == null or not core_node.visible:
        return
    if controller._flat_distance(player.global_position, core_node.global_position) > CORE_RADIUS and not core_carriers.has(peer_id):
        return
    if core_carriers.has(peer_id):
        if controller.connected_ids.size() == 1 and bool(drone_state["active"]) and int(drone_state["owner"]) == peer_id and not core_carriers.has(-peer_id):
            core_carriers.append(-peer_id)
            drone_state["target"] = "energy_core"
            controller.show_feedback_rpc.rpc("辅助无人机已接入核心第二握把 · 保持两人距离", Color("#9ff5ff"), 1.2)
            _sync_now()
            return
        _drop_core(peer_id)
        return
    if core_carriers.size() >= 2:
        return
    core_carriers.append(peer_id)
    player.carrying = 3
    player.carrying_id = 0
    controller.show_feedback_rpc.rpc("玩家 %d 接入能源核心 · 还需要另一名搬运者" % peer_id, Color("#9ff5ff"), 1.2)
    if core_carriers.size() == 2:
        controller.show_feedback_rpc.rpc("能源核心已稳定 · 两名搬运者保持距离", Color("#9ff5cf"), 1.6)
    _sync_now()

func _drop_core(peer_id: int) -> void:
    var index: int = core_carriers.find(peer_id)
    if index < 0:
        return
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    _release_core_carriers(player.global_position if player != null else Vector3.INF)

func release_core_carrier(peer_id: int, drop_position: Vector3 = Vector3.INF) -> void:
    if not core_carriers.has(peer_id) and not core_carriers.has(-peer_id):
        return
    _release_core_carriers(drop_position)

func _release_core_carriers(drop_position: Vector3 = Vector3.INF) -> void:
    if core_carriers.is_empty():
        return
    var release_position: Vector3 = drop_position
    var carrier_ids: Array[int] = core_carriers.duplicate()
    core_carriers.clear()
    for raw_id in carrier_ids:
        var carrier_id: int = int(raw_id)
        var owner_id: int = carrier_id if carrier_id > 0 else -carrier_id
        var carrier: SpacePlayer3D = controller.players.get(owner_id) as SpacePlayer3D
        if carrier != null:
            if release_position == Vector3.INF:
                release_position = carrier.global_position
            carrier.carrying = 0
            carrier.carrying_id = 0
    if release_position == Vector3.INF:
        release_position = core_dropped_position
    core_dropped_position = release_position
    if core_node != null:
        core_node.global_position = core_dropped_position
    if String(drone_state.get("target", "")) == "energy_core":
        drone_state["target"] = ""
    controller.show_feedback_rpc.rpc("能源核心掉落 · 回到最近轨道平台重新接入", Color("#ffbd75"), 1.6)
    _sync_now()

func _toggle_drone(peer_id: int, player: SpacePlayer3D) -> void:
    if controller.connected_ids.size() > 1:
        _feedback_peer(peer_id, "辅助无人机只在单人航行中可用", Color("#ffbd75"), 1.2)
        return
    if bool(drone_state["active"]):
        if int(drone_state["owner"]) == peer_id:
            drone_state["active"] = false
            drone_state["remaining"] = 0.0
            drone_state["target"] = ""
            controller.show_feedback_rpc.rpc("辅助无人机已回到挂架", Color("#b9c9ff"), 0.8)
            _sync_now()
        return
    if float(drone_state["cooldown"]) > 0.0:
        _feedback_peer(peer_id, "无人机冷却 %.1f 秒" % float(drone_state["cooldown"]), Color("#ffbd75"), 1.0)
        return
    drone_state["active"] = true
    drone_state["owner"] = peer_id
    drone_state["position"] = player.global_position + Vector3(1.2, 1.0, 0.0)
    drone_state["remaining"] = DRONE_DURATION
    drone_state["target"] = ""
    if controller.connected_ids.size() == 1 and int(support_relay.get("phase", 0)) == 1 and not shortcut_unlocked:
        drone_state["target"] = "support_relay_high"
        controller.show_feedback_rpc.rpc("辅助无人机已部署 · 自动前往高位共振接收端", Color("#8fdcff"), 1.6)
    else:
        controller.show_feedback_rpc.rpc("辅助无人机已部署 · 它只能锁住一个轨道接口", Color("#8fdcff"), 1.6)
    _sync_now()

func _start_revive(peer_id: int, player: SpacePlayer3D) -> void:
    for mate_value in controller.players.values():
        var target: SpacePlayer3D = mate_value as SpacePlayer3D
        if target == null or target.peer_id == peer_id or not target.downed or target.lava_dead:
            continue
        if controller._flat_distance(player.global_position, target.global_position) <= controller.REVIVE_RANGE:
            controller.reviving[peer_id] = target.peer_id
            controller.revive_progress[peer_id] = 0.0
            controller.show_feedback_rpc.rpc("救援中 · 保持靠近", Color("#ffdb91"), 0.8)
            return

func _tick_drone(delta: float) -> void:
    drone_state["cooldown"] = maxf(float(drone_state["cooldown"]) - delta, 0.0)
    if not bool(drone_state["active"]):
        return
    drone_state["remaining"] = maxf(float(drone_state["remaining"]) - delta, 0.0)
    var owner: SpacePlayer3D = controller.players.get(int(drone_state["owner"])) as SpacePlayer3D
    if owner == null or owner.downed or float(drone_state["remaining"]) <= 0.0:
        drone_state["active"] = false
        drone_state["cooldown"] = DRONE_COOLDOWN
        drone_state["target"] = ""
        if drone_node != null:
            drone_node.visible = false
        _sync_now()
        return
    var target: String = String(drone_state.get("target", ""))
    if target == "energy_core" and core_node != null:
        drone_state["position"] = core_node.global_position + Vector3(0.0, 1.0, 0.0)
    elif target == "support_relay_high":
        drone_state["position"] = SUPPORT_RELAY_HIGH_POSITION + Vector3(0.0, 0.8, 0.0)
    elif target.begins_with("module:"):
        var parts: PackedStringArray = target.split(":")
        if parts.size() == 3:
            var module_id: int = int(parts[1])
            var kind: String = String(parts[2])
            if module_id >= 1 and module_id <= modules.size():
                var module: Dictionary = modules[module_id - 1]
                drone_state["position"] = Vector3(module["%s_position" % kind]) + Vector3(0.0, 1.0, 0.0)
    else:
        drone_state["position"] = owner.global_position + Vector3(1.25, 1.0, 0.0)
    if drone_node != null:
        drone_node.visible = true
        drone_node.global_position = Vector3(drone_state["position"])

func _tick_support_relay() -> void:
    if int(support_relay.get("phase", 0)) != 1:
        return
    if mission_elapsed < float(support_relay.get("deadline", 0.0)):
        return
    support_relay["phase"] = 0
    support_relay["low_peer"] = 0
    support_relay["high_peer"] = 0
    support_relay["deadline"] = 0.0
    support_relay["failures"] = int(support_relay.get("failures", 0)) + 1
    _refresh_support_relay_visuals()
    controller.show_feedback_rpc.rpc("共振接力超时 · 回到低位发送端重新开始", Color("#ffbd75"), 1.1)
    _refresh_objective_guide()
    _sync_now()

func _tick_reactor(_delta: float) -> void:
    if not reactor_deck_active or reactor_carrier == 0:
        return
    var carrier: SpacePlayer3D = controller.players.get(reactor_carrier) as SpacePlayer3D
    if carrier == null or carrier.downed:
        _release_reactor_carrier(carrier.global_position if carrier != null else Vector3.INF)

func _tick_storm(delta: float) -> void:
    storm_clock += delta
    if storm_active:
        storm_remaining = maxf(storm_remaining - delta, 0.0)
        if storm_remaining <= 0.0:
            storm_active = false
            controller.storm_active = false
        controller.show_feedback_rpc.rpc("轨道压力结束 · 系统恢复稳定", Color("#9ff5cf"), 1.2)
    elif storm_clock >= STORM_INTERVAL:
        storm_clock = 0.0
        storm_active = true
        storm_remaining = STORM_DURATION
        controller.storm_active = true
        controller.show_feedback_rpc.rpc("轨道压力来袭 · 快线过载速度提高（视线保持清晰）", Color("#ffbd75"), 1.8)

func _tick_lava(delta: float) -> void:
    lava_tide_clock += delta
    var tide_phase: float = fmod(lava_tide_clock, 24.0)
    var next_active: bool = tide_phase >= 16.0
    if next_active != lava_tide_active:
        lava_tide_active = next_active
        if lava_tide_active:
            controller.show_feedback_rpc.rpc("熔岩潮汐上涨 · 低位快线风险扩大", Color("#ff795d"), 1.4)
        else:
            controller.show_feedback_rpc.rpc("熔岩潮汐回落 · 检修路线恢复", Color("#9ff5cf"), 1.1)
    var tide_rise: float = 0.035 if lava_tide_active else 0.0
    var tide_wave: float = sin(lava_tide_clock * 2.4) * 0.012
    if lava_surface_node != null:
        lava_surface_node.position.y = -4.02 + tide_rise + tide_wave
        var surface_material: StandardMaterial3D = lava_surface_node.material_override as StandardMaterial3D
        if surface_material != null:
            surface_material.emission_energy_multiplier = 3.0 if lava_tide_active else 2.2
    for pit in lava_pit_nodes:
        if pit == null or not is_instance_valid(pit):
            continue
        pit.position.y = -3.82 + tide_rise * 1.35 + tide_wave
    for player_value in controller.players.values():
        var player: SpacePlayer3D = player_value as SpacePlayer3D
        if player == null or player.lava_dead:
            continue
        if _is_lava_position(player.global_position):
            # 先让玩家离开安全岩台并播放下坠，再由 SpacePlayer3D 在
            # 动画结束时调用 kill_player_in_lava；这样不会瞬间消失。
            if not player.falling_to_lava:
                player.begin_resonance_fall()

func _tick_core(delta: float) -> void:
    if core_delivered or core_node == null or not core_node.visible:
        return
    if core_carriers.size() == 2:
        var first: SpacePlayer3D = _carrier_player(core_carriers[0])
        var second: SpacePlayer3D = _carrier_player(core_carriers[1])
        if first == null or second == null or first.downed or second.downed:
            _release_core_carriers(first.global_position if first != null else (second.global_position if second != null else Vector3.INF))
            return
        if controller._flat_distance(first.global_position, second.global_position) > 4.0:
            _release_core_carriers(first.global_position)
            return
        var midpoint: Vector3 = (first.global_position + second.global_position) * 0.5
        core_node.global_position = midpoint + Vector3(0.0, 1.5, 0.0)
        if controller._flat_distance(midpoint, extraction_node.global_position) <= EXTRACTION_RADIUS:
            core_delivered = true
            _clear_core_carrier_state()
            core_node.visible = false
            extraction_enabled = true
            _refresh_objective_guide()
            controller.show_feedback_rpc.rpc("能源核心已送达 · 全队前往返航对接平台", Color("#9ff5cf"), 2.0)
            _sync_now()
    else:
        core_node.global_position = core_dropped_position

func _carrier_player(carrier_id: int) -> SpacePlayer3D:
    var owner_id: int = carrier_id if carrier_id > 0 else -carrier_id
    return controller.players.get(owner_id) as SpacePlayer3D

func _clear_core_carrier_state() -> void:
    for raw_id in core_carriers:
        var carrier_id: int = int(raw_id)
        var owner_id: int = carrier_id if carrier_id > 0 else -carrier_id
        var carrier: SpacePlayer3D = controller.players.get(owner_id) as SpacePlayer3D
        if carrier != null:
            carrier.carrying = 0
            carrier.carrying_id = 0
    core_carriers.clear()

func _tick_extraction(delta: float) -> void:
    if not extraction_enabled:
        return
    var all_ready: bool = true
    for player_value in controller.players.values():
        var player: SpacePlayer3D = player_value as SpacePlayer3D
        if player == null or player.downed or controller._flat_distance(player.global_position, extraction_node.global_position) > EXTRACTION_RADIUS:
            all_ready = false
            break
    extraction_progress = minf(extraction_progress + delta, 3.0) if all_ready else 0.0
    if extraction_progress >= 3.0:
        controller.mission_completed = true
        controller.mission_summary = "共振星撤离成功：三节移动模块完成对接，中央能源核心已回收。"
        controller._set_status(controller.mission_summary)

func _tick_enemies(delta: float) -> void:
    _enemy_clock += delta
    for enemy_value in controller.enemies.values():
        var enemy: SpaceEnemy3D = enemy_value as SpaceEnemy3D
        if enemy == null or not is_instance_valid(enemy):
            continue
        var result: Dictionary = enemy.server_tick(delta, controller.players, Vector3.ZERO, false, storm_active)
        if bool(result.get("sync", false)):
            enemy.sync_transform.rpc(enemy.global_position)

func tick(delta: float) -> void:
    if not is_active():
        return
    if controller.is_host:
        mission_elapsed += delta
        _tick_lava(delta)
        _tick_storm(delta)
        _tick_drone(delta)
        _tick_minigame(delta)
        _tick_support_relay()
        _tick_reactor(delta)
        _refresh_reactor_mechanism_visuals()
        _tick_modules(delta)
        _tick_core(delta)
        _tick_enemies(delta)
        controller._tick_revive(delta)
        controller._check_all_downed()
        _tick_extraction(delta)
        _sync_clock += delta
        if _sync_clock >= 0.2:
            _sync_clock = 0.0
            _sync_now()

func _refresh_module_visual(module: Dictionary) -> void:
    var id: int = int(module["id"])
    var route_root: Node3D = route_nodes.get(id) as Node3D
    if route_root != null:
        route_root.rotation_degrees.y = 22.0 if String(module["route_choice"]) == "fast" else -22.0
    var node: Node3D = module_nodes.get(id) as Node3D
    if node != null:
        node.scale = Vector3(1.04, 1.04, 1.04) if String(module["state"]) == "docking" else Vector3.ONE
    var state: String = String(module["state"])
    if bridge_nodes.has(id):
        var bridge: Node3D = bridge_nodes[id] as Node3D
        bridge.visible = state != "sealed"
    var mechanic: String = String(module.get("mechanic", "switch"))
    var freight_root: Node3D = freight_visuals.get(id) as Node3D
    if freight_root != null:
        freight_root.visible = mechanic == "freight" and not bool(module.get("cargo_loaded", false)) and state != "sealed"
        if freight_root.visible:
            freight_root.global_position = Vector3(module.get("freight_position", Vector3(module["position"])))
            freight_root.rotation_degrees.y = mission_elapsed * 18.0
    var beam_nodes: Array = beam_visuals.get(id, [])
    if not beam_nodes.is_empty():
        var beam_step: int = int(module.get("beam_step", 0))
        var beam_sequence: Array = module.get("beam_sequence", ["support", "route", "safety"])
        for index in beam_nodes.size():
            var beam_node: MeshInstance3D = beam_nodes[index] as MeshInstance3D
            if beam_node == null:
                continue
            beam_node.visible = mechanic == "beam" and state != "sealed"
            if index < beam_step:
                beam_node.material_override = _glow_material(Color("#8dffbd"), 1.6)
            elif index == beam_step and beam_step < beam_sequence.size():
                beam_node.material_override = _glow_material(Color("#ffe08a"), 1.8)
            else:
                beam_node.material_override = _glow_material(Color("#8076a8"), 0.7)
    _refresh_role_light(module, "rail_peer", "rail")
    _refresh_role_light(module, "clamp_peer", "clamp")
    _refresh_role_light(module, "support_peer", "support")
    _refresh_role_light(module, "safety_peer", "safety")
    _refresh_objective_guide()

func _refresh_role_light(module: Dictionary, key: String, kind: String) -> void:
    var id: int = int(module["id"])
    var slot_id: String = "%d:%s" % [id, kind]
    var light: MeshInstance3D = role_lights.get(slot_id) as MeshInstance3D
    if light == null:
        return
    var active: bool = int(module.get(key, 0)) != 0
    light.modulate = Color("#ffffff") if active else Color("#747da4")

func get_hint(local: SpacePlayer3D) -> String:
    if local == null:
        return ""
    if local.downed:
        return "你已倒地 · 等待队友按 R 救援"
    if extraction_enabled:
        return "全队进入绿色返航对接平台 · 保持 %.1f / 3 秒" % extraction_progress
    if checkpoint == 1 and not shortcut_unlocked:
        var relay_target: Dictionary = _support_relay_target_at(local.global_position)
        if not relay_target.is_empty():
            if String(relay_target["kind"]) == "low":
                return "[E] 启动低位共振发送端 · 队友前往高位接收端"
            return "[E] 接入高位共振接收端 · 必须由另一名玩家完成"
        if int(support_relay.get("phase", 0)) == 1:
            return "支援回路接力中 · 队友在 %.1f 秒内到达高位端" % maxf(float(support_relay.get("deadline", 0.0)) - mission_elapsed, 0.0)
        return "支线：沿高位检修桥接通支援回路 · 可降低下一条快线风险"
    if reactor_deck_active:
        var challenge: Dictionary = _current_reactor_challenge()
        if challenge.is_empty():
            return "反应堆甲板正在同步 · 等待下一段"
        var challenge_id: String = String(challenge.get("id", ""))
        if challenge_id == "coolant":
            if reactor_carrier == local.peer_id:
                if controller._flat_distance(local.global_position, Vector3(challenge["coolant_socket_position"])) <= MODULE_RADIUS:
                    if controller.connected_ids.size() > 1 and reactor_stabilizer == 0:
                        return "队友先按 E 稳定冷却接收座，再由你按 F"
                    return "[F] 将冷却单元放入接收座"
                return "携带冷却单元 · 护送到反应堆接收座"
            if reactor_carrier != 0:
                return "冷却单元由队友护送 · 负责清理安保"
            if controller.connected_ids.size() > 1 and reactor_stabilizer == 0:
                return "[E] 稳定冷却接收座 · 等待搬运者"
            return "[F] 接入冷却单元 · 搬到接收座"
        var sequence: Array = challenge.get("sequence", [])
        var step: int = int(challenge.get("step", 0))
        var expected_kind: String = String(sequence[step]) if step < sequence.size() else ""
        return "[E] 反应堆%s · 节点 %d/%d" % [_reactor_kind_name(expected_kind), step + 1, sequence.size()]
    if core_node != null and core_node.visible and controller._flat_distance(local.global_position, core_node.global_position) <= CORE_RADIUS:
        return "[F] 接入中央能源核心 · 需要两名搬运者"
    var module: Dictionary = _current_module()
    if module.is_empty():
        return "轨道模块全部对接 · " + ("完成反应堆甲板任务" if reactor_deck_active else "前往中央能源核心")
    if String(module.get("mechanic", "switch")) == "freight" and not bool(module.get("cargo_loaded", false)):
        if freight_carrier == local.peer_id:
            if controller._flat_distance(local.global_position, Vector3(module["support_position"])) <= MODULE_RADIUS:
                if controller.connected_ids.size() > 1 and int(module.get("support_peer", 0)) == 0:
                    return "队友先按 E 稳住绿色插槽，再由你按 F 放入货箱"
                return "[F] 将磁力货箱插入绿色插槽"
            return "携带磁力货箱 · 沿黄色标记前往绿色插槽"
        if freight_carrier != 0:
            return "磁力货箱由队友搬运 · 负责护送到绿色插槽"
    var target: Dictionary = _module_target_at(local.global_position)
    if not target.is_empty():
        var kind: String = String(target["kind"])
        if kind == "freight":
            return "[F] 接入磁力货箱 · 搬到绿色插槽"
        if String(module.get("mechanic", "switch")) == "beam" and (kind == "support" or kind == "route" or kind == "safety"):
            return "[E] 激活光束节点 %s · 必须按顺序" % _beam_node_name(kind)
        if kind == "route":
            return "[E] 切换模块路线 · 当前%s" % ("低位快线" if String(module["route_choice"]) == "fast" else "安全检修轨")
        if kind == "rail":
            return "[E] 接入轨道供能 · 导能设备"
        if kind == "clamp":
            return "[E] 锁住对接夹具 · 定场设备"
        if kind == "support":
            return "[E] 插入保险栓 · 支援可降低过载"
        return "[E] 布置安全锚点 · 支援可增加容错"
    if String(module["state"]) == "traveling":
        return "模块正在移动 · 保持队伍在轨道平台附近"
    var role: String = _role_for_peer(local.peer_id)
    var drone_text: String = " · Z 部署无人机" if controller.connected_ids.size() == 1 else ""
    return "%s · 你的职责：%s%s" % [_guide_step(module), _role_name(role), drone_text]

func update_hint(local: SpacePlayer3D) -> void:
    controller._interaction_panel.visible = not controller._journal_visible
    if controller._journal_visible:
        return
    var hint: String = get_hint(local)
    controller._interaction_label.text = hint
    controller._interaction_label.visible = not hint.is_empty()
    controller._interaction_progress.visible = false

func update_hud(local: SpacePlayer3D) -> void:
    if local == null:
        return
    var module: Dictionary = _current_module()
    var role: String = _role_for_peer(local.peer_id)
    var route_text: String = "无"
    var state_text: String = "模块全部对接"
    var lock_text: String = ""
    var mechanic_text: String = ""
    if not module.is_empty():
        route_text = "低位快线" if String(module["route_choice"]) == "fast" else "安全检修轨"
        state_text = String(module["state"])
        var mechanic: String = String(module.get("mechanic", "switch"))
        if mechanic == "freight":
            mechanic_text = "磁力货箱 %s" % ("已接入" if bool(module.get("cargo_loaded", false)) else ("搬运中" if freight_carrier != 0 else "待搬运"))
        elif mechanic == "beam":
            mechanic_text = "光束校准 %d/3" % int(module.get("beam_step", 0))
        else:
            mechanic_text = "路线切换"
        lock_text = "供能%s 夹具%s 保险%s 锚点%s" % [
            "✓" if int(module["rail_peer"]) != 0 else "·",
            "✓" if int(module["clamp_peer"]) != 0 else "·",
            "✓" if int(module["support_peer"]) != 0 else "·",
            "✓" if int(module["safety_peer"]) != 0 else "·"
        ]
    var storm_text: String = "轨道压力 %.0fs" % storm_remaining if storm_active else "视野稳定 · 轨道压力待机"
    var core_text: String = "核心搬运者 %d/2" % core_carriers.size() if not core_delivered else "核心已送达"
    var phase_text: String = "轨道模块 %d/%d" % [checkpoint, MODULE_COUNT] if checkpoint < MODULE_COUNT else "反应堆已开放"
    if reactor_deck_active:
        var reactor_challenge: Dictionary = _current_reactor_challenge()
        phase_text = "反应堆甲板 %d/%d" % [reactor_challenge_index, reactor_challenges.size()]
        state_text = "协作任务进行中"
        route_text = "甲板接力"
        mechanic_text = String(reactor_challenge.get("name", "反应堆校准"))
        var reactor_sequence: Array = reactor_challenge.get("sequence", [])
        lock_text = "当前任务节点 %d/%d" % [int(reactor_challenge.get("step", 0)), maxi(reactor_sequence.size(), 1)]
    controller._progress_label.text = "探索共振星 · 移动式轨道工厂\n%s   %s\n当前模块：%s · %s\n路线：%s   %s\n机制：%s\n%s\n%s\n%s\n下一步：%s" % [
        phase_text,
        _role_name(role),
        String(module.get("name", "中央反应堆")),
        state_text,
        route_text,
        lock_text,
        mechanic_text,
        storm_text,
        core_text,
        _guide_step(module),
        _next_objective()
    ]
    controller._vitals_label.text = "生命 %d/5   氧气 %d%%\n%s" % [
        local.health,
        int(local.oxygen),
        "辅助无人机 %.0fs" % float(drone_state["remaining"]) if bool(drone_state["active"]) else "E 设备/稳定 · F 货箱/核心 · R 救援"
    ]
    controller._hint_label.text = "E 设备/路线/稳定    F 搬运货箱/连接核心    Z 无人机    空格 攻击    R 救援    Shift 加速"
    var warning: String = ""
    if storm_active:
        warning = "轨道压力中 · 低位快线过载更快 · 视线稳定"
    elif reactor_deck_active:
        warning = "反应堆甲板任务中 · 先完成当前协作机制"
    elif not core_delivered and checkpoint >= MODULE_COUNT:
        warning = "中央核心开放 · 两名搬运者前往反应堆"
    elif extraction_enabled:
        warning = "核心已送达 · 全队集合返航"
    elif not module.is_empty() and String(module["state"]) == "traveling":
        warning = "模块移动中 · 不要离开轨道平台"
    controller._alert_label.text = warning
    controller._alert_label.visible = not warning.is_empty()

func _guide_step(module: Dictionary) -> String:
    if reactor_deck_active:
        var challenge: Dictionary = _current_reactor_challenge()
        if challenge.is_empty():
            return "反应堆甲板同步中"
        var challenge_id: String = String(challenge.get("id", ""))
        if challenge_id == "coolant":
            if reactor_carrier != 0:
                return "反应堆第 3 段：护送冷却单元到接收座"
            if controller.connected_ids.size() > 1 and reactor_stabilizer == 0:
                return "反应堆第 3 段：队友先稳定接收座"
            return "反应堆第 3 段：接入并护送冷却单元"
        var sequence: Array = challenge.get("sequence", [])
        var step: int = int(challenge.get("step", 0))
        return "反应堆第 %d 段：%s 节点 %d/%d" % [reactor_challenge_index + 1, String(challenge.get("name", "校准")), step + 1, sequence.size()]
    if module.is_empty():
        return "最后一步：两人接入中央核心，再去绿色返航平台"
    var mechanic: String = String(module.get("mechanic", "switch"))
    if mechanic == "freight" and not bool(module.get("cargo_loaded", false)):
        if freight_carrier != 0:
            if controller.connected_ids.size() > 1 and int(module.get("support_peer", 0)) == 0:
                return "第 1 步：队友先按 E 稳住绿色插槽，搬运者再按 F"
            return "第 1 步：把磁力货箱搬到绿色插槽"
        return "第 1 步：先到橙色货箱按 F，再搬到绿色插槽"
    if mechanic == "beam" and int(module.get("beam_step", 0)) < 3:
        var beam_step: int = int(module.get("beam_step", 0))
        var beam_labels: Array[String] = ["A", "B", "C"]
        return "第 %d 步：按顺序激活光束节点 %s" % [beam_step + 1, beam_labels[beam_step]]
    if int(module.get("rail_peer", 0)) == 0:
        return "第 1 步：先去蓝色供能端按 E"
    if int(module.get("clamp_peer", 0)) == 0:
        return "第 2 步：队友去金色对接夹具按 E"
    if String(module.get("route_choice", "safe")) == "fast" and int(module.get("support_peer", 0)) == 0:
        return "第 3 步：绿色保险栓可降低快线过载"
    if String(module.get("state", "ready")) == "traveling":
        return "第 4 步：模块移动中，跟随轨道平台"
    return "第 3 步：保持蓝色供能端和金色夹具，等待模块对接"

func _next_objective() -> String:
    if reactor_deck_active:
        var challenge: Dictionary = _current_reactor_challenge()
        return "完成反应堆甲板：%s（%d/%d）" % [String(challenge.get("name", "协作任务")), reactor_challenge_index, reactor_challenges.size()]
    if checkpoint < MODULE_COUNT:
        var module: Dictionary = modules[checkpoint]
        var route_text: String = "低位快线" if String(module["route_choice"]) == "fast" else "安全检修轨"
        var mechanic_text: String = "路线双端锁止"
        if String(module.get("mechanic", "switch")) == "freight":
            mechanic_text = "磁力货箱护送"
        elif String(module.get("mechanic", "switch")) == "beam":
            mechanic_text = "交替光束校准"
        return "完成模块 %d 对接 · %s · 当前选择：%s" % [checkpoint + 1, mechanic_text, route_text]
    if not core_delivered:
        return "两名玩家接入中央能源核心并护送到返航平台"
    return "全队进入返航对接平台并保持 3 秒"

func attack_from_peer(peer_id: int) -> void:
    if controller == null or not controller.is_host:
        return
    var player: SpacePlayer3D = controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return
    if player.carrying == 3 or core_carriers.has(peer_id):
        _feedback_peer(peer_id, "能源核心搬运中不能攻击", Color("#ffbd75"), 0.9)
        return
    if player.carrying == 4 or freight_carrier == peer_id:
        _feedback_peer(peer_id, "磁力货箱搬运中不能攻击", Color("#ffbd75"), 0.9)
        return
    if player.carrying == 5 or reactor_carrier == peer_id:
        _feedback_peer(peer_id, "冷却单元搬运中不能攻击", Color("#ffbd75"), 0.9)
        return
    var nearest: SpaceEnemy3D = null
    var limit: float = SpacePlayer3D.ATTACK_RANGE
    for enemy_value in controller.enemies.values():
        var candidate: SpaceEnemy3D = enemy_value as SpaceEnemy3D
        if candidate == null or not is_instance_valid(candidate):
            continue
        var distance: float = controller._flat_distance(player.global_position, candidate.global_position)
        if distance <= limit:
            limit = distance
            nearest = candidate
    if nearest == null:
        controller.attack_feedback.rpc(peer_id, player.global_position + Vector3(0.0, 0.0, -1.2), false)
        return
    controller.attack_feedback.rpc(peer_id, nearest.global_position, true)
    if nearest.take_damage(1):
        controller.enemies.erase(nearest.enemy_id)
        nearest.queue_free()
        controller.show_feedback_rpc.rpc("轨道安保已击毁", Color("#9ff5cf"), 1.0)

func request_scan(peer_id: int) -> void:
    _feedback_peer(peer_id, "扫描器显示模块移动方向、快慢路线和保险栓缺口", Color("#8fdcff"), 1.4)

func stage_snapshot() -> Dictionary:
    return {
        "chapter": chapter,
        "checkpoint": checkpoint,
        "role_assignments": role_assignments.duplicate(true),
        "modules": modules.duplicate(true),
        "stations": modules.duplicate(true),
        "puzzles": modules.duplicate(true),
        "core_carriers": core_carriers.duplicate(),
        "freight_carrier": freight_carrier,
        "reactor_deck_active": reactor_deck_active,
        "reactor_challenge_index": reactor_challenge_index,
        "reactor_challenges": reactor_challenges.duplicate(true),
        "reactor_carrier": reactor_carrier,
        "reactor_stabilizer": reactor_stabilizer,
        "core_delivered": core_delivered,
        "core_position": core_node.global_position if core_node != null else core_dropped_position,
        "storm_active": storm_active,
        "storm_remaining": storm_remaining,
        "storm_clock": storm_clock,
        "security_drones": _enemy_snapshot(),
        "drone_state": drone_state.duplicate(true),
        "extraction_enabled": extraction_enabled,
        "extraction_progress": extraction_progress,
        "shortcut_unlocked": shortcut_unlocked,
        "support_relay": support_relay.duplicate(true),
        "support_relay_reward_active": support_relay_reward_active,
        "heat_valves": heat_valves.duplicate(true),
        "heat_valve_operators": heat_valve_operators.duplicate(),
        "heat_chain_complete": heat_chain_complete,
        "lava_tide_clock": lava_tide_clock,
        "lava_tide_active": lava_tide_active
    }

func _enemy_snapshot() -> Array:
    var snapshot: Array = []
    for enemy_value in controller.enemies.values():
        var enemy: SpaceEnemy3D = enemy_value as SpaceEnemy3D
        if enemy != null and is_instance_valid(enemy):
            snapshot.append([enemy.enemy_id, enemy.global_position, enemy.health])
    return snapshot

func _sync_now() -> void:
    if controller != null and controller.is_host:
        sync_coop_state.rpc(stage_snapshot())

@rpc("authority", "call_local", "reliable")
func sync_coop_state(snapshot: Dictionary) -> void:
    apply_stage_snapshot(snapshot)

func apply_stage_snapshot(snapshot: Dictionary) -> void:
    chapter = int(snapshot.get("chapter", chapter))
    checkpoint = int(snapshot.get("checkpoint", checkpoint))
    var saved_roles: Variant = snapshot.get("role_assignments", role_assignments)
    if saved_roles is Dictionary:
        role_assignments = (saved_roles as Dictionary).duplicate(true)
    var raw_modules: Variant = snapshot.get("modules", snapshot.get("stations", []))
    if raw_modules is Array and not modules.is_empty():
        for index in mini(modules.size(), (raw_modules as Array).size()):
            var raw_module: Variant = (raw_modules as Array)[index]
            if raw_module is Dictionary:
                var live_module: Dictionary = modules[index]
                live_module.clear()
                for key_value in (raw_module as Dictionary).keys():
                    live_module[key_value] = (raw_module as Dictionary)[key_value]
        stations = modules
    core_carriers.assign(snapshot.get("core_carriers", []))
    freight_carrier = int(snapshot.get("freight_carrier", freight_carrier))
    for player_value in controller.players.values():
        var synced_player: SpacePlayer3D = player_value as SpacePlayer3D
        if synced_player != null and synced_player.carrying == 4:
            synced_player.carrying = 0
            synced_player.carrying_id = 0
    if freight_carrier != 0:
        var synced_freight_player: SpacePlayer3D = controller.players.get(freight_carrier) as SpacePlayer3D
        if synced_freight_player != null:
            synced_freight_player.carrying = 4
            synced_freight_player.carrying_id = int(_current_module().get("id", 0))
    reactor_deck_active = bool(snapshot.get("reactor_deck_active", reactor_deck_active))
    reactor_challenge_index = int(snapshot.get("reactor_challenge_index", reactor_challenge_index))
    reactor_carrier = int(snapshot.get("reactor_carrier", reactor_carrier))
    reactor_stabilizer = int(snapshot.get("reactor_stabilizer", reactor_stabilizer))
    for player_value in controller.players.values():
        var synced_reactor_state: SpacePlayer3D = player_value as SpacePlayer3D
        if synced_reactor_state != null and synced_reactor_state.carrying == 5:
            synced_reactor_state.carrying = 0
            synced_reactor_state.carrying_id = 0
    var saved_reactor: Variant = snapshot.get("reactor_challenges", reactor_challenges)
    if saved_reactor is Array and not reactor_challenges.is_empty():
        for index in mini(reactor_challenges.size(), (saved_reactor as Array).size()):
            var raw_challenge: Variant = (saved_reactor as Array)[index]
            if raw_challenge is Dictionary:
                var live_challenge: Dictionary = reactor_challenges[index]
                live_challenge.clear()
                for key_value in (raw_challenge as Dictionary).keys():
                    live_challenge[key_value] = (raw_challenge as Dictionary)[key_value]
    if reactor_carrier != 0:
        var synced_reactor_player: SpacePlayer3D = controller.players.get(reactor_carrier) as SpacePlayer3D
        if synced_reactor_player != null:
            synced_reactor_player.carrying = 5
            synced_reactor_player.carrying_id = reactor_challenge_index
    core_delivered = bool(snapshot.get("core_delivered", core_delivered))
    core_dropped_position = Vector3(snapshot.get("core_position", core_dropped_position))
    storm_active = bool(snapshot.get("storm_active", storm_active))
    storm_remaining = float(snapshot.get("storm_remaining", storm_remaining))
    storm_clock = float(snapshot.get("storm_clock", storm_clock))
    controller.storm_active = storm_active
    var saved_drone: Variant = snapshot.get("drone_state", drone_state)
    if saved_drone is Dictionary:
        drone_state = (saved_drone as Dictionary).duplicate(true)
    extraction_enabled = bool(snapshot.get("extraction_enabled", extraction_enabled))
    extraction_progress = float(snapshot.get("extraction_progress", extraction_progress))
    shortcut_unlocked = bool(snapshot.get("shortcut_unlocked", shortcut_unlocked))
    var saved_relay: Variant = snapshot.get("support_relay", support_relay)
    if saved_relay is Dictionary:
        support_relay = (saved_relay as Dictionary).duplicate(true)
    support_relay_reward_active = bool(snapshot.get("support_relay_reward_active", support_relay_reward_active))
    var saved_heat: Variant = snapshot.get("heat_valves", heat_valves)
    if saved_heat is Dictionary:
        heat_valves = (saved_heat as Dictionary).duplicate(true)
    var saved_heat_operators: Variant = snapshot.get("heat_valve_operators", heat_valve_operators)
    if saved_heat_operators is Array:
        heat_valve_operators.assign(saved_heat_operators)
    heat_chain_complete = bool(snapshot.get("heat_chain_complete", heat_chain_complete))
    lava_tide_clock = float(snapshot.get("lava_tide_clock", lava_tide_clock))
    lava_tide_active = bool(snapshot.get("lava_tide_active", lava_tide_active))
    if shortcut_node != null:
        shortcut_node.visible = not shortcut_unlocked
        shortcut_body.collision_layer = 0 if shortcut_unlocked else 2
        shortcut_body.collision_mask = 0 if shortcut_unlocked else 1
    _refresh_support_relay_visuals()
    if core_node != null:
        core_node.visible = not core_delivered and checkpoint >= CHECKPOINTS and not reactor_deck_active
        core_node.global_position = core_dropped_position
    for module_value in modules:
        var module: Dictionary = module_value
        _refresh_module_points(module)
        _refresh_module_visual(module)
        var node: Node3D = module_nodes.get(int(module["id"])) as Node3D
        if node != null:
            node.position = Vector3(module["position"])
    if drone_node != null:
        drone_node.visible = bool(drone_state.get("active", false))
        drone_node.global_position = Vector3(drone_state.get("position", Vector3.ZERO))
    _set_vertical_shaft_gate_open(checkpoint >= CHECKPOINTS and not reactor_deck_active and reactor_challenge_index >= reactor_challenges.size())
    _refresh_reactor_mechanism_visuals()
    _apply_enemy_snapshot(snapshot.get("security_drones", []))

func _apply_enemy_snapshot(snapshot: Array) -> void:
    var seen: Dictionary = {}
    for raw_value in snapshot:
        if raw_value is Array and (raw_value as Array).size() >= 3:
            var raw: Array = raw_value as Array
            var id: int = int(raw[0])
            seen[id] = true
            var enemy: SpaceEnemy3D = controller.enemies.get(id) as SpaceEnemy3D
            if enemy == null:
                enemy = controller.create_space_enemy(controller.connected_ids.size(), id) as SpaceEnemy3D
                if enemy == null:
                    continue
                controller.add_child(enemy)
                controller.enemies[id] = enemy
            enemy.global_position = Vector3(raw[1])
            enemy.health = int(raw[2])
    for id_value in controller.enemies.keys().duplicate():
        var id: int = int(id_value)
        if not seen.has(id):
            var enemy: SpaceEnemy3D = controller.enemies[id] as SpaceEnemy3D
            if is_instance_valid(enemy):
                enemy.queue_free()
            controller.enemies.erase(id)

func _clear_stage_enemies() -> void:
    if controller == null:
        return
    for id_value in controller.enemies.keys().duplicate():
        var id: int = int(id_value)
        var enemy: SpaceEnemy3D = controller.enemies[id] as SpaceEnemy3D
        if is_instance_valid(enemy):
            enemy.queue_free()
        controller.enemies.erase(id)
