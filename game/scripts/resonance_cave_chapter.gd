extends ResonanceStage3D
class_name ResonanceCaveChapter3D

## 共振星第一版连续洞穴章节。
## 这是 ResonanceStage3D 的可替换章节实现：保留旧工厂流程在父类中，
## 当前场景使用手工 Blender 视觉切片和独立的三段合作任务。

const CAVE_VISUAL_V3_PATH: String = "res://assets/resonance/models/resonance_cave_vertical_slice_v3.glb"
const CAVE_VISUAL_V2_PATH: String = "res://assets/resonance/models/resonance_cave_vertical_slice_v2.glb"
const CAVE_HERO_V4_PATH: String = "res://assets/resonance/models/resonance_cave_entrance_hero_v4.glb"
const CAVE_HERO_V4_ENABLED := false
const CAVE_FEEDBACK_SCRIPT := preload("res://scripts/resonance_cave_feedback.gd")
const CAVE_ART_SCRIPT := preload("res://scripts/resonance_cave_art.gd")
const CAVE_GATE_OPEN_COLLISION_DELAY := 0.62
const CAVE_MAP_SIZE: Vector2 = Vector2(200.0, 48.0)
const CAVE_SPAWNS: Array[Vector3] = [
    Vector3(-8.0, 0.1, -2.2),
    Vector3(-8.0, 0.1, 2.2),
    Vector3(-5.0, 0.1, -2.2),
    Vector3(-5.0, 0.1, 2.2)
]
const CAVE_POWER_POSITION := Vector3(-9.0, 0.2, 0.0)
const CAVE_CLAMP_POSITION := Vector3(5.0, 0.2, 0.0)
const CAVE_RELAY_ENTRY_POSITION := Vector3(28.0, 0.2, -1.7)
const CAVE_RELAY_EXIT_POSITION := Vector3(42.0, 0.2, 1.7)
const CAVE_FREIGHT_POSITION := Vector3(65.0, 0.2, 0.0)
const CAVE_STABILIZER_POSITION := Vector3(75.0, 0.2, 4.0)
const CAVE_EXIT_POSITION := Vector3(88.0, 0.2, 0.0)
const CAVE_ROOM_FOCI: Array[Vector3] = [
    Vector3(-4.0, 8.0, 8.0),
    Vector3(32.0, 6.0, 5.0),
    Vector3(72.0, 10.0, 12.0)
]
const CAVE_OBJECTIVE_ORDER: Array[String] = [
    "power", "clamp", "shield_window", "relay_entry", "relay_exit",
    "shield_route", "scan_route", "freight", "energy_align", "shield_calibration",
    "stabilizer"
]
const CAVE_OBJECTIVE_TOOL := {
    "power": "conduit",
    "clamp": "hook",
    "relay_entry": "conduit",
    "relay_exit": "hook",
    "freight": "hook",
    "stabilizer": "scanner",
    "scan_route": "scanner",
    "shield_window": "shield",
    "shield_route": "shield",
    "shield_calibration": "shield",
    "energy_align": "conduit"
}
const CAVE_OBJECTIVE_TASK := {
    "power": 1, "clamp": 1, "shield_window": 1,
    "relay_entry": 2, "relay_exit": 2, "shield_route": 2, "scan_route": 2,
    "freight": 3, "stabilizer": 3, "energy_align": 3, "shield_calibration": 3
}
const CAVE_MANUAL_REQUIRED := {
    "power": 3, "clamp": 3, "relay_entry": 3, "relay_exit": 3,
    "freight": 3, "stabilizer": 4,
    "scan_route": 4, "shield_window": 4, "shield_route": 4,
    "shield_calibration": 4, "energy_align": 4
}
const CAVE_AUX_MIN_MODE := {
    "scan_route": 3, "shield_window": 4, "shield_route": 4,
    "shield_calibration": 4, "energy_align": 4
}
const CAVE_TOOL_REACH := {
    "conduit": 4.8, "hook": 9.0, "scanner": 6.0, "shield": 4.5
}
const CAVE_EVACUATION_DURATION := 3.0
# Camera safety volume, authored from the same cross-sections as the v3 GLB
# shell: (x, floor width, ceiling height).  The clamp is a function of the
# camera's own position, never cave_room/checkpoint, because tasks advance
# while both players are still standing in the previous space.
const CAVE_CAMERA_MIN_X := -17.0
const CAVE_CAMERA_MAX_X := 90.0
const CAVE_CAMERA_MIN_Y := 3.2
const CAVE_CAMERA_SHELL_POWER := 0.62
const CAVE_CAMERA_CLEARANCE := 0.55
const CAVE_CAMERA_ROOF_MARGIN := 0.65
const CAVE_CAMERA_MIN_HALF_WIDTH := 0.9
const CAVE_CAMERA_SECTIONS: Array[Vector3] = [
    Vector3(-18.5, 11.0, 8.6),
    Vector3(-16.0, 14.5, 9.4),
    Vector3(-12.0, 20.0, 10.2),
    Vector3(-7.0, 22.5, 10.8),
    Vector3(-1.0, 23.0, 11.0),
    Vector3(5.0, 21.5, 10.6),
    Vector3(9.5, 17.5, 9.4),
    Vector3(12.5, 13.0, 8.2),
    Vector3(15.0, 10.2, 7.2),
    Vector3(16.5, 9.6, 6.9),
    Vector3(21.0, 10.2, 7.0),
    Vector3(27.0, 10.6, 7.1),
    Vector3(33.0, 10.8, 7.2),
    Vector3(39.0, 10.4, 7.0),
    Vector3(45.0, 10.0, 6.9),
    Vector3(48.5, 9.4, 6.8),
    Vector3(51.0, 11.5, 8.0),
    Vector3(53.0, 18.0, 10.5),
    Vector3(56.0, 26.0, 14.0),
    Vector3(60.0, 31.0, 16.5),
    Vector3(66.0, 34.0, 18.0),
    Vector3(72.0, 34.5, 18.2),
    Vector3(79.0, 33.0, 17.6),
    Vector3(84.0, 29.0, 16.0),
    Vector3(87.5, 23.0, 13.0),
    Vector3(89.5, 16.0, 10.0),
    Vector3(91.0, 11.5, 8.0),
    Vector3(92.5, 8.5, 6.5)
]

var cave_root: Node3D
var cave_visual: Node3D
var cave_hero_visual: Node3D
var cave_collision_bodies: Array[StaticBody3D] = []
var cave_gate_bodies: Array[StaticBody3D] = []
var cave_room: int = 0
var cave_task_one_done: bool = false
var cave_task_two_done: bool = false
var cave_task_three_done: bool = false
var cave_power_peer: int = 0
var cave_clamp_peer: int = 0
var cave_relay_entry_peer: int = 0
var cave_relay_exit_peer: int = 0
var cave_freight_peer: int = 0
var cave_stabilizer_peer: int = 0
var cave_chapter_complete: bool = false
var cave_sync_clock: float = 0.0
var cave_status_sent: Dictionary = {}
var cave_spawn_oriented: bool = false
var cave_feedback
var cave_art
var cave_feedback_event_seq: int = 0
var cave_feedback_seen: Dictionary = {}
var cave_gate_opening: Array[bool] = [false, false]
var cave_aux_peer: Dictionary = {}
var cave_manual_progress: Dictionary = {}
var cave_tool_usage: Dictionary = {}
var cave_tunnel_route: String = "standard"
var cave_evacuation_started: bool = false
var cave_evacuation_remaining: float = 0.0
var cave_scan_route_done: bool = false
var cave_shield_window_done: bool = false
var cave_energy_aligned: bool = false
var cave_cart_x: float = 24.0
var cave_cart_dir: float = 1.0

func start_stage() -> void:
    stop_stage()
    chapter = 0
    checkpoint = 0
    cave_room = 0
    cave_task_one_done = false
    cave_task_two_done = false
    cave_task_three_done = false
    cave_power_peer = 0
    cave_clamp_peer = 0
    cave_relay_entry_peer = 0
    cave_relay_exit_peer = 0
    cave_freight_peer = 0
    cave_stabilizer_peer = 0
    cave_chapter_complete = false
    cave_sync_clock = 0.0
    cave_status_sent.clear()
    cave_spawn_oriented = false
    cave_feedback = null
    cave_art = null
    cave_feedback_event_seq = 0
    cave_feedback_seen.clear()
    cave_gate_opening = [false, false]
    cave_aux_peer.clear()
    cave_manual_progress.clear()
    cave_tool_usage.clear()
    cave_tunnel_route = "standard"
    cave_evacuation_started = false
    cave_evacuation_remaining = 0.0
    cave_scan_route_done = false
    cave_shield_window_done = false
    cave_energy_aligned = false
    cave_cart_x = 24.0
    cave_cart_dir = 1.0
    _assign_roles()
    _build_cave_world()
    if controller != null:
        controller._set_status("共振星洞穴章节：%d 人工具协作。导能/钩索是入口主解法，扫描与护盾提供额外路线和安全窗口。" % cave_player_mode())
        controller._record_journal("共振星洞穴章节", "入口能源封锁、矿脉回廊转辙、晶体洞厅校准分别围绕导能枪、磁力钩索、广域扫描仪和便携护盾展开；缺少工具时可应急操作，单人可用无人机补位。")

func stop_stage() -> void:
    super.stop_stage()
    cave_root = null
    cave_visual = null
    cave_hero_visual = null
    cave_feedback = null
    cave_art = null
    cave_feedback_event_seq = 0
    cave_feedback_seen.clear()
    cave_gate_opening = [false, false]
    cave_aux_peer.clear()
    cave_manual_progress.clear()
    cave_tool_usage.clear()
    cave_evacuation_started = false
    cave_evacuation_remaining = 0.0
    cave_cart_x = 24.0
    cave_cart_dir = 1.0
    cave_collision_bodies.clear()
    cave_gate_bodies.clear()

func _build_cave_world() -> void:
    cave_root = Node3D.new()
    cave_root.name = "ResonanceCaveChapterWorld"
    world_root = cave_root
    add_child(cave_root)
    _build_cave_environment()
    _build_cave_visual()
    _build_cave_hero()
    _build_cave_collisions()
    _build_cave_feedback()
    _build_cave_art()

func _build_cave_environment() -> void:
    # Environment and the cinematic light rig are authored by the art layer
    # after the GLB has been instanced.  Keep the hook so the chapter owns the
    # same build order as the previous implementation.
    return

func update_camera_occlusion(camera_position: Vector3, target: Vector3) -> void:
    if cave_art != null:
        cave_art.update_camera_occlusion(camera_position, target)
    if cave_feedback != null:
        cave_feedback.update_camera_occlusion(camera_position, target)

func _build_cave_art() -> void:
    if cave_visual == null:
        return
    cave_art = CAVE_ART_SCRIPT.new()
    cave_art.name = "CaveArtDirection"
    cave_root.add_child(cave_art)
    cave_art.setup(cave_visual)
    if cave_hero_visual != null:
        cave_art.register_hero_occluders(cave_hero_visual)

func _build_cave_visual() -> void:
    var visual_path := CAVE_VISUAL_V3_PATH if ResourceLoader.exists(CAVE_VISUAL_V3_PATH) else CAVE_VISUAL_V2_PATH
    if not ResourceLoader.exists(visual_path):
        return
    var packed := ResourceLoader.load(visual_path) as PackedScene
    if packed == null:
        return
    cave_visual = packed.instantiate() as Node3D
    if cave_visual == null:
        return
    cave_visual.name = "BlenderCaveVerticalSlice"
    cave_visual.set_meta("visual_authority", visual_path)
    cave_root.add_child(cave_visual)

func _build_cave_hero() -> void:
    if not CAVE_HERO_V4_ENABLED:
        return
    if not ResourceLoader.exists(CAVE_HERO_V4_PATH):
        return
    var packed := ResourceLoader.load(CAVE_HERO_V4_PATH) as PackedScene
    if packed == null:
        return
    cave_hero_visual = packed.instantiate() as Node3D
    if cave_hero_visual == null:
        return
    cave_hero_visual.name = "ResonanceCaveEntranceHeroV4"
    cave_hero_visual.set_meta("visual_authority", CAVE_HERO_V4_PATH)
    cave_hero_visual.set_meta("hero_asset_version", "v4-hero-room")
    cave_root.add_child(cave_hero_visual)
    _hide_v3_entrance_meshes()

func _hide_v3_entrance_meshes() -> void:
    if cave_visual == null:
        return
    for node in cave_visual.find_children("*", "MeshInstance3D", true, false):
        var mesh := node as MeshInstance3D
        if mesh == null:
            continue
        if mesh.name == "CaveFloor_Walkable" or mesh.name == "CaveShell_ContinuousRock":
            continue
        var center: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
        if center.x < 13.8:
            mesh.visible = false

func _build_cave_collisions() -> void:
    # 地面顶面在 y=0，角色胶囊体可以稳定站立；墙体同时服务玩家和相机射线。
    _add_cave_collision("CaveFloor", Vector3(36.0, -0.5, 0.0), Vector3(112.0, 1.0, 42.0), false)
    # 三段空间的侧壁，主路线保持连续，不用随机岩块承担碰撞。
    _add_cave_collision("EntranceWallNorth", Vector3(-2.0, 5.5, 15.8), Vector3(36.0, 11.0, 2.0))
    _add_cave_collision("EntranceWallSouth", Vector3(-2.0, 5.5, -15.8), Vector3(36.0, 11.0, 2.0))
    _add_cave_collision("TunnelWallNorth", Vector3(33.0, 5.2, 7.8), Vector3(36.0, 10.4, 2.0))
    _add_cave_collision("TunnelWallSouth", Vector3(33.0, 5.2, -7.8), Vector3(36.0, 10.4, 2.0))
    _add_cave_collision("CathedralWallNorth", Vector3(71.0, 6.5, 19.0), Vector3(40.0, 13.0, 2.0))
    _add_cave_collision("CathedralWallSouth", Vector3(71.0, 6.5, -19.0), Vector3(40.0, 13.0, 2.0))
    _add_cave_collision("EntranceRoof", Vector3(-2.0, 18.0, 0.0), Vector3(36.0, 2.0, 34.0), true)
    _add_cave_collision("TunnelRoof", Vector3(33.0, 12.0, 0.0), Vector3(36.0, 2.0, 16.0), true)
    _add_cave_collision("CathedralRoof", Vector3(71.0, 20.0, 0.0), Vector3(40.0, 2.0, 40.0), true)
    # 两道门只负责阻挡下一空间；开门时保留 Blender 的视觉出口和照明。
    cave_gate_bodies.append(_add_cave_collision("MineGate01Collision", Vector3(14.0, 3.0, 0.0), Vector3(1.3, 6.0, 10.0)))
    cave_gate_bodies.append(_add_cave_collision("MineGate02Collision", Vector3(50.0, 3.0, 0.0), Vector3(1.3, 6.0, 10.0)))

func _build_cave_feedback() -> void:
    cave_feedback = CAVE_FEEDBACK_SCRIPT.new()
    cave_feedback.name = "CaveMechanismFeedback"
    cave_root.add_child(cave_feedback)
    var positions := {
        "power": _cave_anchor_position("RES_Task01_Power", CAVE_POWER_POSITION),
        "clamp": _cave_anchor_position("RES_Task01_Clamp", CAVE_CLAMP_POSITION),
        "relay_entry": _cave_anchor_position("RES_Tunnel01_Entry", CAVE_RELAY_ENTRY_POSITION),
        "relay_exit": _cave_anchor_position("RES_Tunnel01_Exit", CAVE_RELAY_EXIT_POSITION),
        "freight": _cave_anchor_position("RES_Task02_Freight", CAVE_FREIGHT_POSITION),
        "stabilizer": _cave_anchor_position("RES_Task02_StableSocket", CAVE_STABILIZER_POSITION)
    }
    var gate_positions: Array[Vector3] = []
    gate_positions.append(_cave_anchor_position("RES_Transition01_MineGate", Vector3(12.5, 0.2, 0.0)) + Vector3(-0.4, 0.0, 0.0))
    gate_positions.append(_cave_anchor_position("RES_Tunnel01_Exit", Vector3(48.0, 0.2, 0.0)) + Vector3(1.6, 0.0, 0.0))
    cave_feedback.build(positions, gate_positions)
    if cave_visual != null:
        cave_feedback.bind_world_props(cave_visual)
    if cave_hero_visual != null:
        cave_feedback.bind_world_props(cave_hero_visual)

func _cave_anchor_position(anchor_name: String, fallback: Vector3) -> Vector3:
    if cave_visual != null:
        var anchor := cave_visual.find_child(anchor_name, true, false) as Node3D
        if anchor != null:
            return anchor.global_position
    return fallback

func _add_cave_collision(node_name: String, at: Vector3, size: Vector3, camera_only: bool = false) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = node_name
    body.collision_layer = 4 if camera_only else 6
    body.collision_mask = 0 if camera_only else 1
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    shape.position = at
    body.add_child(shape)
    cave_root.add_child(body)
    cave_collision_bodies.append(body)
    return body

func _set_cave_gate_open(index: int, is_open: bool) -> void:
    if index < 0 or index >= cave_gate_bodies.size():
        return
    var body := cave_gate_bodies[index]
    if body == null or not is_instance_valid(body):
        return
    body.collision_layer = 0 if is_open else 6
    body.collision_mask = 0 if is_open else 1
    body.set_meta("resonance_gate_open", is_open)

func get_active_map_size() -> Vector2:
    return CAVE_MAP_SIZE

func spawn_position(peer_id: int) -> Vector3:
    return CAVE_SPAWNS[(maxi(peer_id, 1) - 1) % CAVE_SPAWNS.size()]

func zone_camera_focus() -> Vector3:
    return CAVE_ROOM_FOCI[clampi(cave_room, 0, CAVE_ROOM_FOCI.size() - 1)]

func clamp_cave_camera_position(candidate: Vector3) -> Vector3:
    # Follow-first soft boundary: x stays on the authored route, and the
    # lateral/vertical limits come from the cave cross-section at the camera's
    # own x.  There is no per-room x box, so entering the corridor can never
    # pin the camera at 26 and task-phase changes cannot move the view.
    var camera_x := clampf(candidate.x, CAVE_CAMERA_MIN_X, CAVE_CAMERA_MAX_X)
    var section := _cave_camera_section(camera_x)
    # The tunnel roof and the two gate headers are lower than the default
    # third-person height.  Keep the lens under them while it crosses either
    # doorway, then let it rise again in the cathedral.
    var roof := minf(section.y - CAVE_CAMERA_ROOF_MARGIN, _cave_camera_roof(camera_x))
    roof = maxf(CAVE_CAMERA_MIN_Y + 0.1, roof)
    var camera_y := clampf(candidate.y, CAVE_CAMERA_MIN_Y, roof)
    var half_width := _cave_camera_half_width(camera_y, section.x, section.y)
    var camera_z := clampf(candidate.z, -half_width, half_width)
    return Vector3(camera_x, camera_y, camera_z)

func _cave_camera_curve(t: float) -> float:
    t = clampf(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

func _cave_camera_roof(at_x: float) -> float:
    if at_x <= 12.0:
        return 10.0
    if at_x < 16.0:
        return lerpf(10.0, 4.9, _cave_camera_curve((at_x - 12.0) / 4.0))
    if at_x <= 54.0:
        return 4.9
    if at_x < 60.0:
        return lerpf(4.9, 9.0, _cave_camera_curve((at_x - 54.0) / 6.0))
    return 16.8

func _cave_camera_section(at_x: float) -> Vector2:
    var first := CAVE_CAMERA_SECTIONS[0]
    if at_x <= first.x:
        return Vector2(first.y, first.z)
    for index in range(CAVE_CAMERA_SECTIONS.size() - 1):
        var left := CAVE_CAMERA_SECTIONS[index]
        var right := CAVE_CAMERA_SECTIONS[index + 1]
        if at_x <= right.x:
            var t := _cave_camera_curve((at_x - left.x) / maxf(right.x - left.x, 0.001))
            return Vector2(lerpf(left.y, right.y, t), lerpf(left.z, right.z, t))
    var last := CAVE_CAMERA_SECTIONS[CAVE_CAMERA_SECTIONS.size() - 1]
    return Vector2(last.y, last.z)

func _cave_camera_half_width(at_y: float, width: float, height: float) -> float:
    var ratio := clampf(at_y / maxf(height, 0.1), 0.0, 0.985)
    var theta := asin(pow(ratio, 1.0 / CAVE_CAMERA_SHELL_POWER))
    return maxf(CAVE_CAMERA_MIN_HALF_WIDTH, 0.5 * width * cos(theta) - CAVE_CAMERA_CLEARANCE)

func stage_tick(delta: float) -> void:
    if controller == null:
        return
    _orient_cave_spawn_cameras()
    cave_sync_clock += delta
    if controller.is_host:
        if cave_evacuation_started and cave_evacuation_remaining > 0.0:
            cave_evacuation_remaining = maxf(0.0, cave_evacuation_remaining - delta)
        cave_cart_x += delta * 2.4 * cave_cart_dir
        if cave_cart_x >= 39.0:
            cave_cart_x = 39.0
            cave_cart_dir = -1.0
        elif cave_cart_x <= 24.0:
            cave_cart_x = 24.0
            cave_cart_dir = 1.0
        if cave_feedback != null:
            cave_feedback.update_cart_target(cave_cart_x, cave_task_one_done and not cave_task_two_done)
        _advance_cave_chapter()
        if cave_sync_clock >= 0.25:
            cave_sync_clock = 0.0
            sync_coop_state.rpc(stage_snapshot())

func _orient_cave_spawn_cameras() -> void:
    if cave_spawn_oriented or controller == null or controller.players.is_empty():
        return
    for player_value in controller.players.values():
        var player := player_value as SpacePlayer3D
        if player == null:
            continue
        player.rotation.y = -PI * 0.5
        player._camera_yaw = -PI * 0.5
        player._camera_yaw_target = -PI * 0.5
        player._camera_pitch = -0.18
        player._camera_pitch_target = -0.18
    cave_spawn_oriented = true

func _advance_cave_chapter() -> void:
    if cave_task_one_done and not cave_task_two_done:
        cave_room = 1
        checkpoint = 1
    elif cave_task_two_done and not cave_task_three_done:
        cave_room = 2
        checkpoint = 2
    elif cave_task_three_done:
        cave_room = 2
        checkpoint = 3
        _check_cave_exit()

func _active_peer_ids() -> Array[int]:
    var active: Array[int] = []
    if controller == null:
        return active
    for peer_value in controller.connected_ids:
        var peer_id: int = int(peer_value)
        var player := controller.players.get(peer_id) as SpacePlayer3D
        if player != null and not player.downed and not player.lava_dead:
            active.append(peer_id)
    return active

func cave_player_mode() -> int:
    if controller == null:
        return 1
    return clampi(maxi(controller.connected_ids.size(), 1), 1, 4)

func active_player_count() -> int:
    return cave_player_mode()

func _player_tool(peer_id: int) -> String:
    if controller != null:
        var kit_tool: String = String(controller.kit_tool_for(peer_id))
        if kit_tool != "":
            return kit_tool
        var player := controller.players.get(peer_id) as SpacePlayer3D
        if player != null:
            return String(player.tool_id)
    return ""

func _peer_has_tool(peer_id: int, tool: String) -> bool:
    return _player_tool(peer_id) == tool

func _team_has_tool(tool: String) -> bool:
    for peer_id in _active_peer_ids():
        if _player_tool(peer_id) == tool:
            return true
    return false

func _drone_available(peer_id: int, _tool: String) -> bool:
    if controller == null or controller.connected_ids.size() > 1:
        return false
    if not bool(drone_state.get("active", false)):
        return false
    if int(drone_state.get("owner", 0)) != peer_id:
        return false
    if float(drone_state.get("remaining", 0.0)) <= 0.0:
        return false
    return true

func _objective_tool(kind: String) -> String:
    return String(CAVE_OBJECTIVE_TOOL.get(kind, ""))

func _objective_position(kind: String) -> Vector3:
    match kind:
        "power":
            return CAVE_POWER_POSITION
        "clamp":
            return CAVE_CLAMP_POSITION
        "relay_entry":
            return CAVE_RELAY_ENTRY_POSITION
        "relay_exit":
            return CAVE_RELAY_EXIT_POSITION
        "freight":
            return CAVE_FREIGHT_POSITION
        "stabilizer":
            return CAVE_STABILIZER_POSITION
        "scan_route":
            return Vector3(33.0, 0.2, -3.6)
        "shield_window":
            return Vector3(2.0, 0.2, -6.0)
        "shield_route":
            return Vector3(32.0, 0.2, 4.2)
        "shield_calibration":
            return Vector3(68.0, 0.2, -6.0)
        "energy_align":
            return Vector3(70.0, 0.2, 6.0)
    return Vector3.ZERO

func _objective_available(kind: String) -> bool:
    var task := int(CAVE_OBJECTIVE_TASK.get(kind, 1))
    if task == 1:
        return not cave_task_one_done
    if task == 2:
        return cave_task_one_done and not cave_task_two_done
    return cave_task_two_done and not cave_task_three_done

func _objective_enabled(kind: String) -> bool:
    if not CAVE_AUX_MIN_MODE.has(kind):
        return true
    if cave_player_mode() < int(CAVE_AUX_MIN_MODE[kind]):
        return false
    return _team_has_tool(_objective_tool(kind))

func _objective_solved(kind: String) -> bool:
    if CAVE_AUX_MIN_MODE.has(kind):
        return cave_aux_peer.has(kind)
    match kind:
        "power":
            return cave_power_peer != 0
        "clamp":
            return cave_clamp_peer != 0
        "relay_entry":
            return cave_relay_entry_peer != 0
        "relay_exit":
            return cave_relay_exit_peer != 0
        "freight":
            return cave_freight_peer != 0
        "stabilizer":
            return cave_stabilizer_peer != 0
    return false

func _objective_peer(kind: String) -> int:
    if CAVE_AUX_MIN_MODE.has(kind):
        return int(cave_aux_peer.get(kind, 0))
    match kind:
        "power":
            return cave_power_peer
        "clamp":
            return cave_clamp_peer
        "relay_entry":
            return cave_relay_entry_peer
        "relay_exit":
            return cave_relay_exit_peer
        "freight":
            return cave_freight_peer
        "stabilizer":
            return cave_stabilizer_peer
    return 0

func _set_objective_solved(kind: String, peer_id: int) -> void:
    match kind:
        "power":
            cave_power_peer = peer_id
        "clamp":
            cave_clamp_peer = peer_id
        "relay_entry":
            cave_relay_entry_peer = peer_id
        "relay_exit":
            cave_relay_exit_peer = peer_id
        "freight":
            cave_freight_peer = peer_id
        "stabilizer":
            cave_stabilizer_peer = peer_id
        "scan_route":
            cave_aux_peer[kind] = peer_id
            cave_scan_route_done = true
        "shield_window":
            cave_aux_peer[kind] = peer_id
            cave_shield_window_done = true
        "shield_route":
            cave_aux_peer[kind] = peer_id
        "shield_calibration":
            cave_aux_peer[kind] = peer_id
        "energy_align":
            cave_aux_peer[kind] = peer_id
            cave_energy_aligned = true

func _check_cave_exit() -> void:
    if cave_chapter_complete or controller == null:
        return
    var active := _active_peer_ids()
    if active.is_empty():
        return
    var nearby := 0
    for peer_id in active:
        var player := controller.players.get(peer_id) as SpacePlayer3D
        if player != null and player.global_position.distance_to(CAVE_EXIT_POSITION) <= 5.0:
            nearby += 1
    if nearby >= mini(2, active.size()):
        cave_chapter_complete = true
        controller._set_status("洞穴章节完成：%d 人撤离队伍已抵达矿脉出口。" % active.size())

func get_stage_action_target(peer_id: int, action: String) -> Dictionary:
    if controller == null or not controller.connected_ids.has(peer_id):
        return {}
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return {}
    if action == "repair":
        for kind in CAVE_OBJECTIVE_ORDER:
            if not _objective_available(kind) or not _objective_enabled(kind) or _objective_solved(kind):
                continue
            var tool := _objective_tool(kind)
            var has_tool := _peer_has_tool(peer_id, tool)
            var drone := _drone_available(peer_id, tool)
            var reach: float = float(CAVE_TOOL_REACH.get(tool, 3.2)) if (has_tool or drone) else 3.2
            if not _near(player.global_position, _objective_position(kind), reach):
                continue
            return {
                "puzzle_id": "cave:%s" % kind,
                "target_id": CAVE_OBJECTIVE_ORDER.find(kind) + 1,
                "kind": kind,
                "tool": tool,
                "has_tool": has_tool,
                "drone": drone,
                "aux": CAVE_AUX_MIN_MODE.has(kind),
                "position": _objective_position(kind)
            }
    if action == "revive":
        return {"puzzle_id": "cave:revive", "target_id": 0, "kind": "revive"}
    if action == "drop":
        return {"puzzle_id": "cave:drop", "target_id": 0, "kind": "drop"}
    return {}

func handle_stage_action(peer_id: int, action: String, _target_id: int) -> void:
    if controller == null or not controller.is_host:
        return
    if action == "revive" or action == "drop":
        super.handle_stage_action(peer_id, action, _target_id)
        return
    var target := get_stage_action_target(peer_id, action)
    if target.is_empty():
        feedback_no_target(peer_id, action)
        return
    var kind := String(target.get("kind", ""))
    var tool := String(target.get("tool", ""))
    var has_tool := bool(target.get("has_tool", false))
    var drone := bool(target.get("drone", false))
    if has_tool or drone:
        _solve_cave_objective(kind, peer_id, tool, drone, false)
    else:
        _manual_cave_objective(kind, peer_id, tool)
    _complete_cave_tasks_if_ready()

func _solve_cave_objective(kind: String, peer_id: int, tool: String, drone: bool, manual: bool) -> void:
    if _objective_solved(kind):
        return
    _set_objective_solved(kind, peer_id)
    cave_manual_progress.erase(kind)
    if tool in ["conduit", "hook", "scanner", "shield"] and not manual:
        cave_tool_usage[tool] = int(cave_tool_usage.get(tool, 0)) + 1
    if drone:
        cave_tool_usage["drone"] = int(cave_tool_usage.get("drone", 0)) + 1
        drone_state["target"] = "cave:%s" % kind
    var player := controller.players.get(peer_id) as SpacePlayer3D
    var from := player.global_position if player != null else _objective_position(kind)
    if kind == "relay_exit":
        cave_tunnel_route = "hook_switch" if tool == "hook" and not manual else "manual_switch"
    if kind == "shield_window":
        for mate_value in controller.players.values():
            var mate := mate_value as SpacePlayer3D
            if mate != null and controller.connected_ids.has(mate.peer_id) and not mate.downed:
                mate.shield_remaining = maxf(mate.shield_remaining, 4.0)
    _activate_cave_mechanism(kind, peer_id, tool, drone, from)
    var label := "应急" if manual else ("无人机代理" if drone else tool)
    _feedback_peer(peer_id, "【%s】%s 已稳定。" % [label, _objective_label(kind)], _tool_color(tool), 1.2)
    if kind == "scan_route":
        _feedback_peer(peer_id, "扫描结果：隐藏安全路线已标记，回廊车轨旁可通行。", Color("#7dffc0"), 1.4)
    elif kind == "shield_window":
        _feedback_peer(peer_id, "便携护盾展开：入口危险区获得 4 秒安全窗口。", Color("#9fc4ff"), 1.4)
    elif kind == "energy_align":
        _feedback_peer(peer_id, "导能枪调整晶体能量方向：出口光路已对齐。", Color("#46e3ff"), 1.4)
    elif kind == "stabilizer":
        _feedback_peer(peer_id, "晶体顺序已锁定，货箱与接收座形成稳定闭环。", Color("#7dffc0"), 1.4)

func _manual_cave_objective(kind: String, peer_id: int, _tool: String) -> void:
    var required := int(CAVE_MANUAL_REQUIRED.get(kind, 3))
    var progress := int(cave_manual_progress.get(kind, 0)) + 1
    cave_manual_progress[kind] = progress
    var at := _objective_position(kind)
    _emit_cave_feedback_event({
        "type": "manual",
        "kind": kind,
        "peer": peer_id,
        "progress": progress,
        "required": required,
        "position": at
    })
    if progress < required:
        _feedback_peer(peer_id, "缺少对应工具 · 应急操作 %s %d/%d（继续按 E）" % [_objective_label(kind), progress, required], Color("#ffd28a"), 1.2)
        return
    _feedback_peer(peer_id, "应急操作完成：%s。这条路线更慢，但没有工具也能通过。" % _objective_label(kind), Color("#ffd28a"), 1.4)
    _solve_cave_objective(kind, peer_id, "manual", false, true)

func _objective_label(kind: String) -> String:
    match kind:
        "power":
            return "导能供能端"
        "clamp":
            return "钩索定场夹具"
        "relay_entry":
            return "导能矿脉中继"
        "relay_exit":
            return "钩索转辙器"
        "freight":
            return "钩索货箱/反射器"
        "stabilizer":
            return "扫描晶体接收座"
        "scan_route":
            return "隐藏安全路线"
        "shield_window":
            return "护盾安全窗口"
        "shield_route":
            return "护盾矿车安全区"
        "shield_calibration":
            return "护盾晶体安全区"
        "energy_align":
            return "晶体能量方向"
    return kind

func _tool_color(tool: String) -> Color:
    match tool:
        "conduit":
            return Color("#46e3ff")
        "hook":
            return Color("#ffb347")
        "scanner":
            return Color("#7dffc0")
        "shield":
            return Color("#9fc4ff")
    return Color("#ffd28a")

func _complete_cave_tasks_if_ready() -> void:
    if not cave_task_one_done and _objective_solved("power") and _objective_solved("clamp"):
        cave_task_one_done = true
        cave_room = 1
        checkpoint = 1
        _emit_cave_feedback_event({
            "type": "task_complete",
            "task": 1,
            "peers": {"power": cave_power_peer, "clamp": cave_clamp_peer}
        })
        _emit_cave_feedback_event({"type": "gate_open", "gate": 0})
        _announce_once("task_one", "入口能源封锁解除：导能/钩索/护盾路线已打开。")
        _broadcast_cave_completion(1, "入口能源封锁解除 · 矿门开启（%d 人模式）" % cave_player_mode(), Color("#7fe9ff"))
    if cave_task_one_done and not cave_task_two_done and _objective_solved("relay_entry") and _objective_solved("relay_exit"):
        cave_task_two_done = true
        cave_room = 2
        checkpoint = 2
        _emit_cave_feedback_event({
            "type": "task_complete",
            "task": 2,
            "peers": {"relay_entry": cave_relay_entry_peer, "relay_exit": cave_relay_exit_peer}
        })
        _emit_cave_feedback_event({"type": "gate_open", "gate": 1})
        _announce_once("task_two", "矿脉回廊转辙完成：车轨已导向晶体洞厅。")
        _broadcast_cave_completion(2, "矿脉转辙贯通 · 晶体洞厅开启（路线：%s）" % cave_tunnel_route, Color("#ffd166"))
    if cave_task_two_done and not cave_task_three_done and _objective_solved("freight") and _objective_solved("stabilizer"):
        cave_task_three_done = true
        checkpoint = 3
        _emit_cave_feedback_event({
            "type": "task_complete",
            "task": 3,
            "peers": {"freight": cave_freight_peer, "stabilizer": cave_stabilizer_peer}
        })
        _announce_once("task_three", "晶体洞厅校准完成：能量正在失稳，立即沿 +X 撤离。")
        _broadcast_cave_completion(3, "晶体洞厅校准完成 · 崩塌撤离开始", Color("#7dffc0"))
        _start_cave_evacuation()

func _start_cave_evacuation() -> void:
    if cave_evacuation_started:
        return
    cave_evacuation_started = true
    cave_evacuation_remaining = CAVE_EVACUATION_DURATION
    _emit_cave_feedback_event({
        "type": "evacuation",
        "position": CAVE_EXIT_POSITION,
        "duration": CAVE_EVACUATION_DURATION
    })
    if controller != null:
        controller.show_feedback_rpc.rpc("能量崩塌 · 沿 +X 光路撤离至矿脉出口", Color("#ff9d6a"), 2.0)
        for peer_value in _active_peer_ids():
            controller.camera_shake_rpc.rpc(int(peer_value), 0.05, 0.32)

func _activate_cave_mechanism(kind: String, peer_id: int, tool: String = "", drone: bool = false, from: Vector3 = Vector3.ZERO) -> void:
    if controller == null or not controller.is_host:
        return
    _emit_cave_feedback_event({
        "type": "armed",
        "kind": kind,
        "peer": peer_id,
        "tool": tool,
        "drone": drone,
        "from": from,
        "position": _objective_position(kind)
    })
    controller.camera_shake_rpc.rpc(peer_id, 0.035, 0.12)

func _emit_cave_feedback_event(event: Dictionary) -> void:
    if controller == null or not controller.is_host:
        return
    cave_feedback_event_seq += 1
    var payload: Dictionary = event.duplicate(true)
    payload["seq"] = cave_feedback_event_seq
    cave_feedback_event.rpc(payload)

@rpc("authority", "call_local", "reliable")
func cave_feedback_event(event: Dictionary) -> void:
    var event_type := str(event.get("type", ""))
    var event_key := "%s:%d:%s" % [
        event_type,
        int(event.get("seq", 0)),
        str(event.get("kind", event.get("gate", event.get("task", ""))))
    ]
    if cave_feedback_seen.has(event_key):
        return
    cave_feedback_seen[event_key] = true
    if cave_feedback == null:
        return
    match event_type:
        "armed":
            var armed_kind := str(event.get("kind", ""))
            var armed_peer := int(event.get("peer", 0))
            var armed_tool := str(event.get("tool", ""))
            var armed_from: Vector3 = event.get("from", Vector3.ZERO)
            var armed_at: Vector3 = event.get("position", _objective_position(armed_kind))
            cave_feedback.play_activation(armed_kind, armed_peer)
            if armed_tool != "" and armed_tool != "manual":
                cave_feedback.play_tool_action(armed_tool, armed_kind, armed_from, armed_at, armed_peer, bool(event.get("drone", false)))
        "manual":
            var manual_kind := str(event.get("kind", ""))
            var manual_at: Vector3 = event.get("position", _objective_position(manual_kind))
            cave_feedback.play_manual_pulse(manual_kind, int(event.get("progress", 0)), int(event.get("required", 0)), manual_at)
        "task_complete":
            var peers: Dictionary = event.get("peers", {}) as Dictionary
            cave_feedback.play_task_complete(int(event.get("task", 0)), peers)
        "gate_open":
            _begin_cave_gate_open(int(event.get("gate", 0)))
        "evacuation":
            var evacuation_at: Vector3 = event.get("position", CAVE_EXIT_POSITION)
            cave_feedback.play_evacuation(evacuation_at, float(event.get("duration", CAVE_EVACUATION_DURATION)))

func _begin_cave_gate_open(index: int) -> void:
    if index < 0 or index >= cave_gate_opening.size():
        return
    if cave_gate_opening[index]:
        return
    if index < cave_gate_bodies.size() and cave_gate_bodies[index].collision_layer == 0:
        if cave_feedback != null:
            cave_feedback.set_gate_open_instant(index)
        return
    cave_gate_opening[index] = true
    if cave_feedback != null:
        cave_feedback.play_gate_open(index)
    get_tree().create_timer(CAVE_GATE_OPEN_COLLISION_DELAY).timeout.connect(func() -> void:
        if is_inside_tree():
            _finish_cave_gate_open(index)
    )

func _finish_cave_gate_open(index: int) -> void:
    if index < 0 or index >= cave_gate_bodies.size():
        return
    _set_cave_gate_open(index, true)
    if index < cave_gate_opening.size():
        cave_gate_opening[index] = false

func _broadcast_cave_completion(task: int, message: String, color: Color) -> void:
    if controller == null:
        return
    controller.show_feedback_rpc.rpc(message, color, 1.8)
    var ids: Array = controller.connected_ids.duplicate()
    var local_id: int = controller.multiplayer.get_unique_id()
    if not ids.has(local_id):
        ids.append(local_id)
    for peer_value in ids:
        controller.camera_shake_rpc.rpc(int(peer_value), 0.045, 0.18)
    print("CAVE_FEEDBACK task=%d %s" % [task, message])

func _reconcile_cave_feedback() -> void:
    if cave_feedback == null:
        return
    var idle: int = cave_feedback.STATE_IDLE
    var armed: int = cave_feedback.STATE_ARMED
    var completed: int = cave_feedback.STATE_COMPLETED
    var states := {
        "power": completed if cave_task_one_done else (armed if cave_power_peer != 0 else idle),
        "clamp": completed if cave_task_one_done else (armed if cave_clamp_peer != 0 else idle),
        "relay_entry": completed if cave_task_two_done else (armed if cave_relay_entry_peer != 0 else idle),
        "relay_exit": completed if cave_task_two_done else (armed if cave_relay_exit_peer != 0 else idle),
        "freight": completed if cave_task_three_done else (armed if cave_freight_peer != 0 else idle),
        "stabilizer": completed if cave_task_three_done else (armed if cave_stabilizer_peer != 0 else idle)
    }
    var peers := {
        "power": cave_power_peer,
        "clamp": cave_clamp_peer,
        "relay_entry": cave_relay_entry_peer,
        "relay_exit": cave_relay_exit_peer,
        "freight": cave_freight_peer,
        "stabilizer": cave_stabilizer_peer
    }
    var gates_open: Array[bool] = [cave_task_one_done, cave_task_two_done]
    cave_feedback.apply_snapshot_state(states, peers, gates_open)
    for index in cave_gate_bodies.size():
        var should_open: bool = bool(gates_open[index]) if index < gates_open.size() else false
        if cave_gate_opening[index]:
            continue
        if should_open and cave_gate_bodies[index].collision_layer != 0:
            _set_cave_gate_open(index, true)
        elif not should_open and cave_gate_bodies[index].collision_layer == 0:
            _set_cave_gate_open(index, false)


func feedback_no_target(peer_id: int, action: String) -> void:
    if controller == null:
        return
    if action == "repair":
        var message := "靠近当前房间的高亮工具机关后再按 E；没有对应工具可连续按 E 应急。"
        if cave_task_one_done and not cave_task_two_done:
            message = "回廊：导能枪接中继、钩索扳转辙；扫描仪可显示隐藏安全路线。"
        elif cave_task_two_done and not cave_task_three_done:
            message = "晶体洞厅：钩索移动反射器、扫描仪校准顺序；导能枪可调整能量方向。"
        elif cave_evacuation_started:
            message = "崩塌开始：沿 +X 光路撤离到矿脉出口。"
        _feedback_peer(peer_id, message, Color("#ffd28a"), 1.0)

func _announce_once(key: String, message: String) -> void:
    if cave_status_sent.has(key):
        return
    cave_status_sent[key] = true
    if controller != null:
        controller._set_status(message)

func _near(a: Vector3, b: Vector3, radius: float) -> bool:
    var delta := a - b
    delta.y = 0.0
    return delta.length() <= radius

func update_hud(local: SpacePlayer3D) -> void:
    if local == null or controller == null:
        return
    var room_text := "入口洞厅" if cave_room == 0 else ("矿脉回廊" if cave_room == 1 else "晶体洞厅")
    var tunnel_text := "矿车转辙：导能中继 + 钩索转辙（扫描隐藏路线，车轨目标 x=%d）" % int(cave_cart_x)
    var task_text := "能源封锁：导能 + 钩索（护盾/扫描可支援）" if not cave_task_one_done else (tunnel_text if not cave_task_two_done else ("晶体校准：钩索反射器 + 扫描顺序（导能调向）" if not cave_task_three_done else ("崩塌撤离：沿 +X 光路到出口" if cave_evacuation_started else "沿矿脉出口前进")))
    var p1 := "✓" if cave_power_peer != 0 else "·"
    var p2 := "✓" if cave_clamp_peer != 0 else "·"
    var p3 := "✓" if cave_relay_entry_peer != 0 else "·"
    var p4 := "✓" if cave_relay_exit_peer != 0 else "·"
    var p5 := "✓" if cave_freight_peer != 0 else "·"
    var p6 := "✓" if cave_stabilizer_peer != 0 else "·"
    var progress_text := "入口 %s  %s\n当前空间：%s\n当前任务：%s\n%d 人工具位：导能%s 钩索%s 扫描%s 护盾%s\n机关：供能%s 夹具%s 中继%s/%s 货箱%s 接收%s" % [
        "完成" if cave_task_one_done else "进行中",
        "章节完成" if cave_chapter_complete else "专属工具合作章节",
        room_text,
        task_text,
        cave_player_mode(),
        "✓" if _team_has_tool("conduit") else "·",
        "✓" if _team_has_tool("hook") else "·",
        "✓" if _team_has_tool("scanner") else "·",
        "✓" if _team_has_tool("shield") else "·",
        p1, p2, p3, p4, p5, p6
    ]
    controller._progress_label.text = progress_text
    var tool_text := "你的工具：%s" % controller.kit_tool_name(local.peer_id)
    controller._vitals_label.text = "生命 %d/5   氧气 %d%%\n%s · %d 人模式" % [local.health, int(local.oxygen), tool_text, cave_player_mode()]
    controller._hint_label.text = "E 工具机关    R 救援    空格 攻击    Shift 加速"
    controller._alert_label.visible = cave_chapter_complete
    controller._alert_label.text = "洞穴撤离完成 · 队伍沿 +X 出口离开"

func update_hint(local: SpacePlayer3D) -> void:
    if local == null or controller == null:
        return
    if cave_chapter_complete:
        controller._hint_label.text = "撤离完成：沿 +X 方向离开矿脉出口"
    elif cave_evacuation_started:
        controller._hint_label.text = "能量崩塌：立即沿 +X 光路撤离到出口"
    elif not cave_task_one_done:
        controller._hint_label.text = "入口：导能枪接供能端、钩索拉夹具；没有工具可连续按 E 应急，护盾可开安全窗口"
    elif not cave_task_two_done:
        controller._hint_label.text = "回廊：导能接中继、钩索扳转辙；扫描仪会标出隐藏安全路线"
    else:
        controller._hint_label.text = "洞厅：钩索移动反射器、扫描仪校准晶体顺序；导能枪调整能量方向"

func request_scan(peer_id: int) -> void:
    _feedback_peer(peer_id, "扫描结果：青色矿脉标记通向下一洞厅；当前合作站位已在 HUD 标出。", Color("#8fdcff"), 1.4)

func attack_from_peer(peer_id: int) -> void:
    if controller == null:
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player != null:
        controller.attack_feedback.rpc(peer_id, player.global_position + Vector3(0.0, 0.0, -1.2), false)

func release_core_carrier(_peer_id: int, _drop_position: Vector3 = Vector3.INF) -> void:
    return

func _spawn_security_drones(_module_id: int) -> void:
    # 保留旧诊断入口的兼容行为；洞穴章节本身不主动生成安保波次。
    if controller == null or not controller.is_host or controller.connected_ids.is_empty():
        return
    var enemy := controller.create_space_enemy(controller.connected_ids.size(), controller.next_enemy_id) as SpaceEnemy3D
    if enemy == null:
        return
    enemy.position = Vector3(32.0, 0.0, 5.5)
    controller.add_child(enemy)
    controller.enemies[controller.next_enemy_id] = enemy
    controller.next_enemy_id += 1

func stage_snapshot() -> Dictionary:
    return {
        "chapter": chapter,
        "checkpoint": checkpoint,
        "role_assignments": role_assignments.duplicate(true),
        "cave_room": cave_room,
        "cave_task_one_done": cave_task_one_done,
        "cave_task_two_done": cave_task_two_done,
        "cave_task_three_done": cave_task_three_done,
        "cave_power_peer": cave_power_peer,
        "cave_clamp_peer": cave_clamp_peer,
        "cave_relay_entry_peer": cave_relay_entry_peer,
        "cave_relay_exit_peer": cave_relay_exit_peer,
        "cave_freight_peer": cave_freight_peer,
        "cave_stabilizer_peer": cave_stabilizer_peer,
        "cave_chapter_complete": cave_chapter_complete,
        "cave_aux_peer": cave_aux_peer.duplicate(true),
        "cave_manual_progress": cave_manual_progress.duplicate(true),
        "cave_tool_usage": cave_tool_usage.duplicate(true),
        "cave_tunnel_route": cave_tunnel_route,
        "cave_evacuation_started": cave_evacuation_started,
        "cave_evacuation_remaining": cave_evacuation_remaining,
        "cave_scan_route_done": cave_scan_route_done,
        "cave_shield_window_done": cave_shield_window_done,
        "cave_energy_aligned": cave_energy_aligned,
        "cave_cart_x": cave_cart_x,
        "cave_cart_dir": cave_cart_dir
    }

func apply_stage_snapshot(snapshot: Dictionary) -> void:
    cave_room = int(snapshot.get("cave_room", cave_room))
    cave_task_one_done = bool(snapshot.get("cave_task_one_done", cave_task_one_done))
    cave_task_two_done = bool(snapshot.get("cave_task_two_done", cave_task_two_done))
    cave_task_three_done = bool(snapshot.get("cave_task_three_done", cave_task_three_done))
    cave_power_peer = int(snapshot.get("cave_power_peer", cave_power_peer))
    cave_clamp_peer = int(snapshot.get("cave_clamp_peer", cave_clamp_peer))
    cave_relay_entry_peer = int(snapshot.get("cave_relay_entry_peer", cave_relay_entry_peer))
    cave_relay_exit_peer = int(snapshot.get("cave_relay_exit_peer", cave_relay_exit_peer))
    cave_freight_peer = int(snapshot.get("cave_freight_peer", cave_freight_peer))
    cave_stabilizer_peer = int(snapshot.get("cave_stabilizer_peer", cave_stabilizer_peer))
    cave_chapter_complete = bool(snapshot.get("cave_chapter_complete", cave_chapter_complete))
    checkpoint = int(snapshot.get("checkpoint", checkpoint))
    cave_aux_peer = (snapshot.get("cave_aux_peer", {}) as Dictionary).duplicate(true)
    cave_manual_progress = (snapshot.get("cave_manual_progress", {}) as Dictionary).duplicate(true)
    cave_tool_usage = (snapshot.get("cave_tool_usage", {}) as Dictionary).duplicate(true)
    cave_tunnel_route = String(snapshot.get("cave_tunnel_route", cave_tunnel_route))
    cave_evacuation_started = bool(snapshot.get("cave_evacuation_started", cave_evacuation_started))
    cave_evacuation_remaining = float(snapshot.get("cave_evacuation_remaining", cave_evacuation_remaining))
    cave_scan_route_done = bool(snapshot.get("cave_scan_route_done", cave_scan_route_done))
    cave_shield_window_done = bool(snapshot.get("cave_shield_window_done", cave_shield_window_done))
    cave_energy_aligned = bool(snapshot.get("cave_energy_aligned", cave_energy_aligned))
    cave_cart_x = float(snapshot.get("cave_cart_x", cave_cart_x))
    cave_cart_dir = float(snapshot.get("cave_cart_dir", cave_cart_dir))
    if cave_feedback != null:
        cave_feedback.update_cart_target(cave_cart_x, cave_task_one_done and not cave_task_two_done)
    _reconcile_cave_feedback()

@rpc("any_peer", "reliable")
func request_coop_action(peer_id: int, action: String, _puzzle_id: String, target: Dictionary) -> void:
    if controller != null and controller.is_host:
        handle_stage_action(peer_id, action, int(target.get("target_id", 0)))
