extends Node3D
class_name ShipDevices3D

const CONSOLE: PackedScene = preload("res://assets/ship-hub/kenney/space-station/computer-system.glb")
const PILOT_X: Array[float] = [-4.8, -1.6, 1.6, 4.8]
var devices: Array = []
var screens: Dictionary = {}
var session: ShipSession3D

static func catalog() -> Array:
    var entries: Array = []
    for index: int in 4:
        entries.append({"id": "pilot_%d" % index, "kind": "pilot", "item": str(index), "position": Vector3(PILOT_X[index], 0.61, -13.8), "title": "驾驶 %02d" % (index + 1), "existing": true, "radius": 2.35})
    entries.append({"id": "routes", "kind": "route", "item": "", "position": Vector3(0, 0, 1.75), "title": "航线"})
    entries.append({"id": "repair", "kind": "repair", "item": "", "position": ShipHub3D.REPAIR, "title": "舰体维修"})
    entries.append({"id": "refill", "kind": "refill", "item": "", "position": ShipHub3D.SUPPLY, "title": "生命补给"})
    entries.append({"id": "store", "kind": "store", "item": "", "position": Vector3(-18.85, 0, 8.8), "yaw": PI / 2.0, "title": "物资归还"})
    entries.append({"id": "mission", "kind": "mission", "item": "", "position": ShipHub3D.MISSION, "title": "航行记录"})
    entries.append({"id": "exit", "kind": "exit", "item": "", "position": Vector3(-3.8, 0, 13.7), "title": "离舰终端"})
    entries.append({"id": "craft", "kind": "craft", "item": "", "position": Vector3(16.4, 0, -6.2), "title": "制作"})
    entries.append({"id": "gear", "kind": "gear", "item": "", "position": Vector3(-14.4, 0, -12.0), "title": "装备"})
    entries.append({"id": "toy", "kind": "toy", "item": "", "position": Vector3(14.2, 0, 4.4), "title": "道具"})
    entries.append({"id": "skin", "kind": "skin", "item": "", "position": Vector3(14.0, 0, 13.8), "title": "换装"})
    return entries

static func options_for(device: Dictionary) -> Array:
    var result: Array = []
    var kind: String = String(device.kind)
    var items: Array = []
    match kind:
        "route": items = ["demo", "electromagnetic", "ruin"]
        "craft": items = ["medical", "oxygen", "parts"]
        "gear": items = ShipSession3D.GEAR_ITEMS
        "toy": items = ShipSession3D.GOOFY_ITEMS
        "skin":
            for skin: Dictionary in Main3D.SKIN_CATALOG:
                result.append({"id": "skin_" + String(skin.id), "kind": kind, "item": skin.id, "title": String(skin.name).split(" · ")[0]})
            return result
        _: return [device.duplicate()]
    for value: String in items:
        var title: String = String({"demo": "霜烬星", "electromagnetic": "共振星", "ruin": "废墟星"}.get(value, ShipSession3D.ITEM_NAMES.get(value, ShipSession3D.GEAR_NAMES.get(value, CrewItems3D.NAMES.get(value, value)))))
        result.append({"id": kind + "_" + value, "kind": kind, "item": value, "title": title})
    return result

static func entry_for(id: String) -> Dictionary:
    for device: Dictionary in catalog():
        if device.id == id:
            return device
    return {}

static func point_for(id: String) -> Vector3:
    for device: Dictionary in catalog():
        if device.id == id:
            return device.position
        for option: Dictionary in options_for(device):
            if option.id == id:
                return device.position
    return Vector3.INF

func _ready() -> void:
    session = get_parent().get_parent() as ShipSession3D
    devices = catalog()
    for device: Dictionary in devices:
        _build(device)

func nearby(peer_id: int) -> Dictionary:
    var player: SpacePlayer3D = session.controller.players.get(peer_id) as SpacePlayer3D
    if player == null:
        return {}
    var best: Dictionary = {}
    var distance: float = INF
    for device: Dictionary in devices:
        var next_distance: float = session.controller._flat_distance(player.position, device.position)
        if next_distance < distance and session.controller._items.can_reach(player, device.position, float(device.get("radius", 1.85))):
            distance = next_distance
            best = device
    return best

func hint(peer_id: int, device: Dictionary) -> String:
    var kind: String = device.kind
    if kind == "pilot":
        var owner: int = int(session.station_owners.get(int(device.item), 0))
        if owner == peer_id:
            return "E 取消就位" if session.launch_remaining < 0 else "出发 %d · E 取消" % ceili(session.launch_remaining)
        return "已占用" if owner != 0 else "E 就位"
    return "E 打开 · " + String(device.title)

func _process(_delta: float) -> void:
    if session == null:
        return
    for device: Dictionary in devices:
        if device.kind != "pilot":
            continue
        var owner: int = int(session.station_owners.get(int(device.item), 0))
        var state: String = "待机" if owner == 0 else "船员 %d · 就位" % (session.controller.connected_ids.find(owner) + 1)
        var label: Label3D = screens[device.id] as Label3D
        label.text = String(device.title) + "\n" + state
        label.modulate = Color("#9af0cc") if owner != 0 else Color("#c2e0e5")

func _build(device: Dictionary) -> void:
    var terminal: Node3D = Node3D.new()
    terminal.name = String(device.id)
    terminal.position = device.position
    terminal.rotation.y = float(device.get("yaw", 0.0))
    add_child(terminal)
    if not bool(device.get("existing", false)):
        var model: Node3D = CONSOLE.instantiate() as Node3D
        ItemProp3D.linear_materials(model)
        var bounds: AABB = ItemProp3D._bounds(model, Transform3D.IDENTITY)
        var fit: Vector3 = Vector3(0.85, 1.12, 0.65) / bounds.size
        model.scale = fit
        model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * fit
        terminal.add_child(model)
        var body: StaticBody3D = StaticBody3D.new()
        body.collision_layer = 2
        body.collision_mask = 0
        body.position.y = 0.5
        var shape: CollisionShape3D = CollisionShape3D.new()
        var box: BoxShape3D = BoxShape3D.new()
        box.size = Vector3(0.8, 1.0, 0.6)
        shape.shape = box
        body.add_child(shape)
        terminal.add_child(body)
    var monitor: MeshInstance3D = MeshInstance3D.new()
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(1.18, 0.54, 0.08) if device.kind == "pilot" else Vector3(0.86, 0.62, 0.10)
    monitor.mesh = mesh
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = Color("#102733")
    monitor.material_override = material
    monitor.position = Vector3(0, 1.23, -0.45 if device.kind == "pilot" else 0.36)
    terminal.add_child(monitor)
    if device.kind != "pilot":
        var display: MeshInstance3D = MeshInstance3D.new()
        var face: QuadMesh = QuadMesh.new()
        face.size = Vector2(0.50, 0.50)
        display.mesh = face
        var picture: StandardMaterial3D = StandardMaterial3D.new()
        picture.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        picture.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        picture.albedo_texture = load("res://assets/ship-hub/computer-icons/" + String(device.kind) + ".svg") as Texture2D
        display.material_override = picture
        display.position = monitor.position + Vector3(0, 0, 0.052)
        terminal.add_child(display)
        screens[device.id] = display
        return
    var label: Label3D = Label3D.new()
    label.position = monitor.position + Vector3(0, 0, 0.041)
    label.font_size = 32
    label.pixel_size = 0.004
    label.outline_size = 0
    label.no_depth_test = false
    terminal.add_child(label)
    screens[device.id] = label
