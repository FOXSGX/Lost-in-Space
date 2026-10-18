extends RefCounted
class_name FrostRoamActivities

# 霜烬星的自由探索活动。它们不占用主线目标，但提供一套可反复游玩的
# “发现地点 → 持续操作 → 获得回收价值 → 下一轮地点变化”循环。
const INTERACTION_RADIUS := 2.8
const REVEAL_RADIUS := 18.0
const ACTIVITIES := [
    {
        "id": "echo_survey",
        "name": "回波追踪",
        "description": "沿着短促的地下回波校准三处监听点。",
        "reward": 12,
        "color": Color("#70d9ef"),
        "positions": [Vector2(-96.0, 44.0), Vector2(-20.0, -45.0), Vector2(106.0, 44.0)],
        "steps": [
            {"label": "接收回波", "duration": 1.8},
            {"label": "校准监听点", "duration": 2.2},
            {"label": "回传数据", "duration": 1.6}
        ]
    },
    {
        "id": "resource_cache",
        "name": "冰层资源点",
        "description": "勘测一处会移动的资源脉冲，打开临时资源舱。",
        "reward": 16,
        "color": Color("#6fe7b7"),
        "positions": [Vector2(-62.0, -24.0), Vector2(52.0, 22.0), Vector2(138.0, 90.0)],
        "steps": [
            {"label": "勘测资源脉冲", "duration": 2.0},
            {"label": "打开资源舱", "duration": 3.0}
        ]
    },
    {
        "id": "thermal_beacon",
        "name": "临时热源",
        "description": "在远离主线的路线上点亮临时热源，帮助队伍往返。",
        "reward": 10,
        "color": Color("#ffc36e"),
        "positions": [Vector2(-40.0, 62.0), Vector2(44.0, -54.0), Vector2(116.0, -62.0)],
        "steps": [
            {"label": "接回热源线路", "duration": 2.8}
        ]
    }
]

var controller: Node3D
var states: Dictionary = {}
var nodes: Dictionary = {}
var jobs: Dictionary = {}
var positions: Dictionary = {}
var _time := 0.0
var _sync_elapsed := 0.0

func _init(owner: Node3D) -> void:
    controller = owner

func build() -> void:
    reset()
    for index in ACTIVITIES.size():
        var activity: Dictionary = ACTIVITIES[index]
        var id := String(activity.id)
        var choices: Array = activity.positions
        var choice_index := (int(controller.route_seed) + index) % choices.size()
        var point := Vector2(choices[choice_index])
        positions[id] = point
        states[id] = {"revealed": false, "stage": 0, "completed_count": 0, "cooldown_until": 0.0, "heat_position": Vector2.ZERO}
        var root := Node3D.new()
        root.name = "RoamActivity_" + id
        root.position = Vector3(point.x, controller.terrain_height(point), point.y)
        controller._world_root.add_child(root)
        nodes[id] = root
        _build_visual(root, activity)
    _apply_visuals()

func reset() -> void:
    for peer_id in jobs:
        var player := controller.players.get(int(peer_id)) as SpacePlayer3D
        if player != null:
            player.show_rescue_animation(false)
    jobs.clear()
    states.clear()
    positions.clear()
    for node in nodes.values():
        if is_instance_valid(node):
            node.queue_free()
    nodes.clear()
    _time = 0.0
    _sync_elapsed = 0.0

func _build_visual(root: Node3D, activity: Dictionary) -> void:
    var color: Color = activity.color
    var base := MeshInstance3D.new()
    var base_mesh := CylinderMesh.new()
    base_mesh.top_radius = 0.34
    base_mesh.bottom_radius = 0.48
    base_mesh.height = 0.24
    base.mesh = base_mesh
    base.material_override = controller._glow_material(color, 1.2)
    base.position.y = 0.12
    root.add_child(base)
    var ring := MeshInstance3D.new()
    ring.name = "ActivityRing"
    var ring_mesh := TorusMesh.new()
    ring_mesh.inner_radius = 0.72
    ring_mesh.outer_radius = 0.79
    ring_mesh.rings = 24
    ring_mesh.ring_segments = 8
    ring.mesh = ring_mesh
    ring.material_override = controller._glow_material(color, 0.75)
    ring.position.y = 0.08
    root.add_child(ring)
    var label := Label3D.new()
    label.name = "ActivityLabel"
    label.text = "自由活动 · " + String(activity.name)
    label.position.y = 1.6
    label.font_size = 34
    label.pixel_size = 0.009
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.outline_size = 8
    label.outline_modulate = Color("#061521")
    label.modulate = color
    label.shaded = false
    root.add_child(label)

func _apply_visuals() -> void:
    for activity in ACTIVITIES:
        var id := String(activity.id)
        var root := nodes.get(id) as Node3D
        if root == null:
            continue
        var state: Dictionary = states.get(id, {})
        var cooldown := float(state.get("cooldown_until", 0.0))
        root.visible = cooldown <= float(controller.mission_elapsed) or bool(state.get("revealed", false))
        var label := root.get_node_or_null("ActivityLabel") as Label3D
        if label != null:
            label.visible = bool(state.get("revealed", false))
            label.text = "自由活动 · " + String(activity.name) if int(state.get("stage", 0)) == 0 else "活动进行中 · " + String(activity.name)
        var ring := root.get_node_or_null("ActivityRing") as MeshInstance3D
        if ring != null:
            ring.visible = bool(state.get("revealed", false))

func _activity(id: String) -> Dictionary:
    for activity in ACTIVITIES:
        if String(activity.id) == id:
            return activity
    return {}

func _nearest(player: SpacePlayer3D) -> Dictionary:
    var nearest: Dictionary = {}
    var best := INTERACTION_RADIUS
    for activity in ACTIVITIES:
        var id := String(activity.id)
        var root := nodes.get(id) as Node3D
        if root == null or not root.visible:
            continue
        var state: Dictionary = states.get(id, {})
        if float(state.get("cooldown_until", 0.0)) > float(controller.mission_elapsed):
            continue
        var distance: float = float(controller._flat_distance(player.global_position, root.global_position))
        if distance <= best:
            best = distance
            nearest = activity.duplicate(true)
            nearest["distance"] = distance
    return nearest

func prompt(player: SpacePlayer3D) -> String:
    if jobs.has(player.peer_id):
        var job: Dictionary = jobs[player.peer_id]
        return "%s · %.1f / %.1f 秒 · 离开或再按 E 中止" % [String(job.get("label", "自由活动")), float(job.get("elapsed", 0.0)), float(job.get("duration", 1.0))]
    var activity := _nearest(player)
    if activity.is_empty():
        return ""
    var id := String(activity.id)
    var state: Dictionary = states[id]
    var steps: Array = activity.steps
    var stage := clampi(int(state.get("stage", 0)), 0, steps.size() - 1)
    return "[E]  %s · %s · 完成可得 +%d 回收价值" % [String(activity.name), String(steps[stage].get("label", "开始活动")), int(activity.reward)]

func interaction_progress(peer_id: int) -> float:
    if not jobs.has(peer_id):
        return 0.0
    var job: Dictionary = jobs[peer_id]
    return clampf(float(job.get("elapsed", 0.0)) / maxf(float(job.get("duration", 1.0)), 0.01), 0.0, 1.0)

func has_interaction_job(peer_id: int) -> bool:
    return jobs.has(peer_id)

func handle_action(peer_id: int, action: String) -> bool:
    if action != "repair":
        return false
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed:
        return false
    if jobs.has(peer_id):
        jobs.erase(peer_id)
        player.show_rescue_animation(false)
        controller.show_feedback_rpc.rpc("自由活动已中止", Color("#ffbd75"), 1.0)
        return true
    var activity := _nearest(player)
    if activity.is_empty():
        return false
    var id := String(activity.id)
    var state: Dictionary = states[id]
    state["revealed"] = true
    var steps: Array = activity.steps
    var stage := clampi(int(state.get("stage", 0)), 0, steps.size() - 1)
    var step: Dictionary = steps[stage]
    jobs[peer_id] = {"activity_id": id, "label": String(step.get("label", "操作自由活动")), "duration": float(step.get("duration", 2.0)), "elapsed": 0.0}
    player.show_rescue_animation(true)
    controller.show_feedback_rpc.rpc(String(step.get("label", "自由活动")) + " · 留在活动点附近", Color("#9fe8cf"), 1.3)
    return true

func tick(delta: float) -> void:
    _time += delta
    if states.is_empty():
        return
    var changed := false
    for activity in ACTIVITIES:
        var id := String(activity.id)
        var state: Dictionary = states[id]
        if not bool(state.get("revealed", false)):
            var point: Vector2 = positions[id]
            for value in controller.players.values():
                var player := value as SpacePlayer3D
                if player != null and not player.downed and Vector2(player.global_position.x, player.global_position.z).distance_to(point) <= REVEAL_RADIUS:
                    state["revealed"] = true
                    if controller.is_host:
                        controller._record_journal("发现自由活动 · " + String(activity.name), String(activity.description) + " 靠近后按 E 开始操作。")
                        controller.show_feedback_rpc.rpc("发现自由活动 · " + String(activity.name), activity.color, 1.8)
                        changed = true
                    break
    # 只有主机推进持续操作和发放奖励；客户端只接收快照，避免联机时重复结算。
    if not controller.is_host:
        _apply_visuals()
        return
    for raw_peer_id in jobs.keys().duplicate():
        var peer_id := int(raw_peer_id)
        var job: Dictionary = jobs[peer_id]
        var player := controller.players.get(peer_id) as SpacePlayer3D
        var id := String(job.get("activity_id", ""))
        var root := nodes.get(id) as Node3D
        if player == null or player.downed or root == null or controller._flat_distance(player.global_position, root.global_position) > INTERACTION_RADIUS:
            jobs.erase(peer_id)
            if player != null:
                player.show_rescue_animation(false)
            changed = true
            continue
        job["elapsed"] = float(job.get("elapsed", 0.0)) + delta
        if float(job.elapsed) >= float(job.duration):
            jobs.erase(peer_id)
            player.show_rescue_animation(false)
            _finish(id, player)
            changed = true
        else:
            jobs[peer_id] = job
    _apply_visuals()
    _sync_elapsed += delta
    if controller.is_host and (changed or (not jobs.is_empty() and _sync_elapsed >= 0.2)):
        _sync_elapsed = 0.0
        controller.sync_roam_activity_state.rpc(snapshot())

func _finish(id: String, player: SpacePlayer3D) -> void:
    var activity := _activity(id)
    if activity.is_empty():
        return
    var state: Dictionary = states[id]
    var steps: Array = activity.steps
    var next_stage := int(state.get("stage", 0)) + 1
    if next_stage < steps.size():
        state["stage"] = next_stage
        controller._record_journal("自由活动推进 · " + String(activity.name), "下一步：" + String(steps[next_stage].get("label", "继续操作")) + "。")
        controller.show_feedback_rpc.rpc("自由活动推进：" + String(activity.name), activity.color, 1.6)
        return
    var completed_count := int(state.get("completed_count", 0)) + 1
    state["completed_count"] = completed_count
    state["stage"] = 0
    state["cooldown_until"] = float(controller.mission_elapsed) + 12.0
    if id == "thermal_beacon":
        state["heat_position"] = Vector2(positions[id])
    controller.salvage_value += int(activity.reward)
    controller.world_flags["roam_" + id + "_count"] = completed_count
    controller._record_journal("自由活动完成 · " + String(activity.name), String(activity.description) + " 回收价值 +%d；下一次活动会在另一处出现。" % int(activity.reward))
    controller.show_feedback_rpc.rpc("自由活动完成 · 回收价值 +%d" % int(activity.reward), activity.color, 2.2)
    var choices: Array = activity.positions
    var activity_index := 0
    for index in ACTIVITIES.size():
        if String(ACTIVITIES[index].id) == id:
            activity_index = index
            break
    var next_index := (completed_count + activity_index + int(controller.route_seed)) % choices.size()
    positions[id] = Vector2(choices[next_index])
    var root := nodes.get(id) as Node3D
    if root != null:
        var point: Vector2 = positions[id]
        root.position = Vector3(point.x, controller.terrain_height(point), point.y)

func snapshot() -> Dictionary:
    return {"states": states.duplicate(true), "positions": positions.duplicate(true), "jobs": jobs.duplicate(true)}

func apply_snapshot(data: Dictionary) -> void:
    if data.is_empty():
        return
    states = data.get("states", states).duplicate(true)
    positions = data.get("positions", positions).duplicate(true)
    jobs = data.get("jobs", jobs).duplicate(true)
    for id in positions:
        var root := nodes.get(String(id)) as Node3D
        if root == null:
            continue
        var point := Vector2(positions[id])
        root.position = Vector3(point.x, controller.terrain_height(point), point.y)
    _apply_visuals()

func map_sites() -> Array:
    var result: Array = []
    for activity in ACTIVITIES:
        var id := String(activity.id)
        var state: Dictionary = states.get(id, {})
        if not bool(state.get("revealed", false)):
            continue
        result.append({"position": Vector2(positions.get(id, Vector2.ZERO)), "label": String(activity.name), "kind": "roam", "count": int(state.get("completed_count", 0))})
    return result

func heat_sources() -> Array:
    var result: Array = []
    var state: Dictionary = states.get("thermal_beacon", {})
    if int(state.get("completed_count", 0)) > 0:
        result.append({"position": Vector2(state.get("heat_position", positions.get("thermal_beacon", Vector2.ZERO))), "label": "临时热源"})
    return result

