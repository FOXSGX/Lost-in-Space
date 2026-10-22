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
    var routes: Array[String] = ["demo", "electromagnetic", "ruin"]
    var titles: Array[String] = ["霜烬星", "共振星", "废墟星"]
    var points: Array[Vector3] = [Vector3(-2.05, 0, 1.75), Vector3(0, 0, 1.75), Vector3(2.05, 0, 1.75)]
    for index: int in 3:
        entries.append({"id": "route_" + routes[index], "kind": "route", "item": routes[index], "position": points[index], "title": titles[index]})
    entries.append({"id": "repair", "kind": "repair", "item": "", "position": ShipHub3D.REPAIR, "title": "舰体维修"})
    entries.append({"id": "refill", "kind": "refill", "item": "", "position": ShipHub3D.SUPPLY, "title": "生命补给"})
    entries.append({"id": "store", "kind": "store", "item": "", "position": Vector3(-15.0, 0, 7.3), "title": "物资归还"})
    entries.append({"id": "mission", "kind": "mission", "item": "", "position": ShipHub3D.MISSION, "title": "航行记录"})
    entries.append({"id": "exit", "kind": "exit", "item": "", "position": Vector3(-3.8, 0, 13.7), "title": "离舰终端"})
    for index: int in 3:
        var kind: String = ["medical", "oxygen", "parts"][index]
        entries.append({"id": "craft_" + kind, "kind": "craft", "item": kind, "position": Vector3(14.4 + index * 2.0, 0, -6.2), "title": ShipSession3D.ITEM_NAMES[kind]})
        var gear: String = ShipSession3D.GEAR_ITEMS[index]
        entries.append({"id": "gear_" + gear, "kind": "gear", "item": gear, "position": Vector3(-16.5 + index * 2.1, 0, -12.0), "title": ShipSession3D.GEAR_NAMES[gear]})
    for index: int in 5:
        var toy: String = ShipSession3D.GOOFY_ITEMS[index]
        entries.append({"id": "toy_" + toy, "kind": "toy", "item": toy, "position": Vector3(14.2, 0, 1.0 + index * 1.7), "title": CrewItems3D.NAMES[toy]})
        var skin: Dictionary = Main3D.SKIN_CATALOG[index]
        entries.append({"id": "skin_" + String(skin.id), "kind": "skin", "item": skin.id, "position": Vector3(10.0 + index * 2.0, 0, 13.8), "title": String(skin.name).split(" · ")[0]})
    return entries

static func point_for(id: String) -> Vector3:
    for device: Dictionary in catalog():
        if device.id == id:
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
    if kind == "route":
        return "已选 " + String(device.title) if session.selected_destination == device.item else "E 前往 " + String(device.title)
    if kind == "gear":
        return "E 装备 " + String(device.title) if int(session.gear_stock.get(device.item, 0)) > 0 else "E 购买 %s · %d" % [device.title, int(ShipSession3D.GEAR_COSTS[device.item])]
    if kind == "craft":
        return "E 制作 %s · %d" % [device.title, int(ShipSession3D.ITEM_COSTS[device.item])]
    if kind == "skin":
        return "E 换装 " + String(device.title) if session.controller.owns_skin(device.item) else "E 购买 %s · %d 星币" % [device.title, session.controller.skin_price(device.item)]
    return {"repair": "E 维修", "refill": "E 恢复", "store": "E 存回所选物资", "mission": "E 查看记录", "exit": "E 离开房间", "toy": "E 领取 " + String(device.title)}.get(kind, "E 操作")

func _process(_delta: float) -> void:
    if session == null:
        return
    for device: Dictionary in devices:
        var state: String = "E 操作"
        var lit: bool = false
        match String(device.kind):
            "pilot":
                var owner: int = int(session.station_owners.get(int(device.item), 0))
                state = "待机" if owner == 0 else "船员 %d · 就位" % (session.controller.connected_ids.find(owner) + 1)
                lit = owner != 0
            "route":
                lit = session.selected_destination == device.item
                state = "已选择" if lit else "E 选择"
            "craft":
                state = "%d 回收点" % int(ShipSession3D.ITEM_COSTS[device.item])
            "gear":
                lit = int(session.gear_stock.get(device.item, 0)) > 0
                state = "E 装备" if lit else "%d 回收点" % int(ShipSession3D.GEAR_COSTS[device.item])
            "skin":
                lit = session.controller.owns_skin(device.item)
                state = "E 换装" if lit else "%d 星币" % session.controller.skin_price(device.item)
            "repair":
                state = "%d%% · 零件 %d" % [session.hull, session.stock.parts]
            "refill": state = "E 恢复"
            "store": state = "E 存回"
            "mission": state = "E 查看"
            "exit": state = "E 离舰"
            "toy": state = "E 领取"
        var label: Label3D = screens[device.id] as Label3D
        label.text = String(device.title) + "\n" + state
        label.modulate = Color("#9af0cc") if lit else Color("#c2e0e5")

func _build(device: Dictionary) -> void:
    var terminal: Node3D = Node3D.new()
    terminal.name = String(device.id)
    terminal.position = device.position
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
    mesh.size = Vector3(1.18, 0.54, 0.08)
    monitor.mesh = mesh
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = Color("#102733")
    monitor.material_override = material
    monitor.position = Vector3(0, 1.23, -0.45 if device.kind == "pilot" else 0.36)
    terminal.add_child(monitor)
    var label: Label3D = Label3D.new()
    label.position = monitor.position + Vector3(0, 0, 0.041)
    label.font_size = 32
    label.pixel_size = 0.004
    label.outline_size = 0
    label.no_depth_test = false
    terminal.add_child(label)
    screens[device.id] = label
