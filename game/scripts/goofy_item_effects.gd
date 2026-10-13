extends RefCounted
class_name GoofyItemEffects

# 欢乐道具是团队共用的可重复使用玩具：没有冷却，也不消耗战斗资源。
# 主机只负责确认使用者和同步效果，客户端负责显示同一组夸张的视觉反馈。
const ITEM_DATA := {
    "penguin": {"name": "回声企鹅", "color": Color("#8de9ff"), "duration": 8.0, "label": "企鹅"},
    "bubble": {"name": "反重力泡", "color": Color("#c5a4ff"), "duration": 6.0, "label": "失重"},
    "board": {"name": "雪地滑板", "color": Color("#ffd36e"), "duration": 5.0, "label": "滑行"},
    "hologram": {"name": "全息替身", "color": Color("#ff9bd7"), "duration": 8.0, "label": "替身"},
    "smoke": {"name": "彩色信号烟", "color": Color("#ff7fd1"), "duration": 10.0, "label": "彩烟"}
}

var controller: Node3D
var active_effects: Array[Dictionary] = []
var _time := 0.0
var _next_effect_id := 1

func _init(owner: Node3D) -> void:
    controller = owner

func reset() -> void:
    for effect in active_effects:
        var node := effect.get("node") as Node3D
        if node != null and is_instance_valid(node):
            node.queue_free()
    active_effects.clear()
    _time = 0.0
    _next_effect_id = 1

func item_name(item_id: String) -> String:
    return String(ITEM_DATA.get(item_id, {}).get("name", item_id))

func hint_text() -> String:
    return "5 企鹅  6 失重泡  7 滑板  8 替身  9 彩烟"

func activate(peer_id: int, item_id: String) -> void:
    if not ITEM_DATA.has(item_id) or not controller.is_host:
        return
    var player := controller.players.get(peer_id) as SpacePlayer3D
    if player == null or player.downed or not controller.game_started or controller.mission_completed or controller.mission_failed:
        return
    var effect_id := _next_effect_id
    _next_effect_id += 1
    var duration := float(ITEM_DATA[item_id].duration)
    controller.spawn_goofy_effect_rpc.rpc(item_id, player.global_position, player.global_transform.basis.z, peer_id, effect_id, duration)
    controller.show_feedback_rpc.rpc("%s 出场 · 可继续连按" % item_name(item_id), ITEM_DATA[item_id].color, 0.75)

func spawn_local(item_id: String, origin: Vector3, direction: Vector3, caster_id: int, effect_id: int, duration: float) -> void:
    if not ITEM_DATA.has(item_id):
        return
    var data: Dictionary = ITEM_DATA[item_id]
    var effect := {"id": effect_id, "item_id": item_id, "origin": origin, "direction": direction, "caster_id": caster_id, "remaining": duration, "duration": duration, "node": null}
    if item_id == "board":
        var target := controller.players.get(caster_id) as SpacePlayer3D
        if target != null:
            target.set_goofy_state("board", duration)
    else:
        effect.node = _build_effect_node(item_id, origin, data.color)
        if effect.node != null:
            controller._world_root.add_child(effect.node)
    active_effects.append(effect)

func tick(delta: float) -> void:
    _time += delta
    for index in range(active_effects.size() - 1, -1, -1):
        var effect: Dictionary = active_effects[index]
        effect.remaining = float(effect.remaining) - delta
        var item_id := String(effect.item_id)
        var node := effect.get("node") as Node3D
        if node != null and is_instance_valid(node):
            _animate_effect(node, item_id, effect, delta)
        if item_id == "board":
            var target := controller.players.get(int(effect.caster_id)) as SpacePlayer3D
            if target != null:
                target.set_goofy_state("board", maxf(float(effect.remaining), 0.0))
        if float(effect.remaining) <= 0.0:
            if node != null and is_instance_valid(node):
                node.queue_free()
            active_effects.remove_at(index)
        else:
            active_effects[index] = effect

func lure_positions() -> Array:
    var positions: Array = []
    for effect in active_effects:
        var item_id := String(effect.item_id)
        if item_id not in ["penguin", "hologram"]:
            continue
        positions.append(effect.origin)
    return positions

func bubble_positions() -> Array:
    var positions: Array = []
    for effect in active_effects:
        if String(effect.item_id) == "bubble":
            positions.append(effect.origin)
    return positions

func snapshot() -> Array:
    var result: Array = []
    for effect in active_effects:
        result.append({
            "id": int(effect.id),
            "item_id": String(effect.item_id),
            "origin": effect.origin,
            "direction": effect.direction,
            "caster_id": int(effect.caster_id),
            "remaining": float(effect.remaining),
            "duration": float(effect.duration)
        })
    return result

func apply_snapshot(data: Array) -> void:
    reset()
    for raw in data:
        var effect: Dictionary = raw
        var effect_id := int(effect.get("id", 0))
        var item_id := String(effect.get("item_id", ""))
        if effect_id <= 0 or not ITEM_DATA.has(item_id):
            continue
        _next_effect_id = maxi(_next_effect_id, effect_id + 1)
        spawn_local(item_id, Vector3(effect.get("origin", Vector3.ZERO)), Vector3(effect.get("direction", Vector3.FORWARD)), int(effect.get("caster_id", 1)), effect_id, float(effect.get("remaining", 0.0)))

func _build_effect_node(item_id: String, origin: Vector3, color: Color) -> Node3D:
    var root := Node3D.new()
    root.name = "GoofyEffect_%s" % item_id
    # 先设置本地坐标再挂入场景树，避免测试/联机瞬间读取未入树节点的 global_transform。
    root.position = origin + Vector3(0.0, 0.08, 0.0)
    match item_id:
        "penguin":
            _sphere(root, "PenguinBody", 0.42, Vector3(0, 0.48, 0), color, true)
            _sphere(root, "PenguinBelly", 0.28, Vector3(0, 0.43, -0.3), Color("#eafaff"), false)
            for side in [-1.0, 1.0]:
                _sphere(root, "PenguinWing", 0.16, Vector3(side * 0.4, 0.45, 0), Color("#45778f"), false)
            var label := _label(root, "叽！", Vector3(0, 1.25, 0), color)
            label.font_size = 42
        "bubble":
            var bubble := _sphere(root, "GravityBubble", 1.9, Vector3(0, 1.1, 0), color, true)
            var material := bubble.material_override as StandardMaterial3D
            material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            material.albedo_color = Color(color.r, color.g, color.b, 0.12)
            var ring := _torus(root, "GravityRing", 1.75, 1.82, Vector3(0, 0.08, 0), color)
            ring.rotation_degrees.x = 90.0
            _label(root, "失重！", Vector3(0, 3.0, 0), color)
        "hologram":
            var body := _box(root, "HologramBody", Vector3(0.7, 1.2, 0.46), Vector3(0, 0.75, 0), color, true)
            var body_material := body.material_override as StandardMaterial3D
            body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            body_material.albedo_color = Color(color.r, color.g, color.b, 0.48)
            _sphere(root, "HologramHead", 0.34, Vector3(0, 1.6, 0), color, true)
            _label(root, "我是本人", Vector3(0, 2.25, 0), color)
        "smoke":
            for index in 9:
                var angle := TAU * float(index) / 9.0
                var radius := 0.4 + float(index % 3) * 0.24
                _sphere(root, "Smoke_%d" % index, 0.28 + float(index % 2) * 0.08, Vector3(cos(angle) * radius, 0.4 + float(index % 4) * 0.42, sin(angle) * radius), color, true)
            _label(root, "集合！", Vector3(0, 2.45, 0), color)
    return root

func _animate_effect(node: Node3D, item_id: String, effect: Dictionary, _delta: float) -> void:
    var progress := 1.0 - float(effect.remaining) / maxf(float(effect.duration), 0.01)
    match item_id:
        "penguin":
            node.position.y = effect.origin.y + 0.08 + sin(_time * 7.0 + float(effect.id)) * 0.12
            node.rotation.y += 0.045
        "bubble":
            var pulse := 1.0 + sin(_time * 5.5 + float(effect.id)) * 0.08
            node.scale = Vector3.ONE * pulse
            node.rotation.y += 0.02
        "hologram":
            node.position.y = effect.origin.y + 0.08 + sin(_time * 4.0 + float(effect.id)) * 0.1
            node.rotation.y += 0.055
            node.scale = Vector3.ONE * (0.94 + sin(_time * 9.0) * 0.08)
        "smoke":
            node.position.y = effect.origin.y + 0.08 + progress * 1.2
            node.rotation.y += 0.018
            node.scale = Vector3.ONE * (0.8 + progress * 0.6)

func _sphere(parent: Node3D, node_name: String, radius: float, position: Vector3, color: Color, glow: bool) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    instance.material_override = controller._glow_material(color, 1.0) if glow else controller._material(color)
    parent.add_child(instance)
    return instance

func _box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color, glow: bool) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    instance.material_override = controller._glow_material(color, 0.8) if glow else controller._material(color)
    parent.add_child(instance)
    return instance

func _torus(parent: Node3D, node_name: String, inner_radius: float, outer_radius: float, position: Vector3, color: Color) -> MeshInstance3D:
    var mesh := TorusMesh.new()
    mesh.inner_radius = inner_radius
    mesh.outer_radius = outer_radius
    mesh.rings = 32
    mesh.ring_segments = 8
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    instance.material_override = controller._glow_material(color, 1.2)
    parent.add_child(instance)
    return instance

func _label(parent: Node3D, text: String, position: Vector3, color: Color) -> Label3D:
    var label := Label3D.new()
    label.text = text
    label.position = position
    label.font_size = 32
    label.pixel_size = 0.01
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = color
    label.outline_size = 8
    label.outline_modulate = Color("#071421")
    label.shaded = false
    parent.add_child(label)
    return label
