extends Node3D
class_name ShipTutorial3D

const STATION_POSITIONS := [
    Vector3(-7.0, 0.0, -3.3), # 扫描
    Vector3(-2.8, 0.0, -3.3), # 修复
    Vector3(1.4, 0.0, -3.3), # 拾取
    Vector3(5.7, 0.0, -3.3), # 投送
    Vector3(5.7, 0.0, 2.8), # 攻击
    Vector3(1.4, 0.0, 2.8), # 救援
    Vector3(-6.2, 0.0, 2.8), # 航线
]
const STATION_NAMES := ["Q 扫描", "E 修复", "F 拾取", "G 投送", "空格 攻击", "R 救援", "E 航线"]
const STATION_COLORS := [
    Color("#62d9f3"), Color("#f3c76a"), Color("#73e0a3"),
    Color("#69bfff"), Color("#ff8a8e"), Color("#f0a7ff"), Color("#7be8dc")
]

var _station_lights: Array[OmniLight3D] = []
var _station_labels: Array[Label3D] = []
var _battery: MeshInstance3D
var _target: MeshInstance3D
var _rescue_light: OmniLight3D

func _ready() -> void:
    _build_room()
    _build_stations()
    show_step(0)

func station_position(step: int) -> Vector3:
    return STATION_POSITIONS[clampi(step - 1, 0, STATION_POSITIONS.size() - 1)]

func show_step(step: int) -> void:
    for index in _station_lights.size():
        var active := index == step - 1 or (step >= 7 and index == 6)
        _station_lights[index].light_energy = 2.4 if active else 0.55
        _station_labels[index].modulate = Color.WHITE if active else Color("#7896a5")
    if _battery != null:
        _battery.visible = step < 4
    if _target != null:
        _target.visible = step < 6
    if _rescue_light != null:
        _rescue_light.light_color = Color("#79e5a9") if step >= 7 else Color("#f0a7ff")

func _build_room() -> void:
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#030b17")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#89b7ce")
    env.ambient_light_energy = 0.55
    environment.environment = env
    add_child(environment)

    var ceiling_light := DirectionalLight3D.new()
    ceiling_light.rotation_degrees = Vector3(-58.0, -24.0, 0.0)
    ceiling_light.light_color = Color("#b5dfff")
    ceiling_light.light_energy = 0.9
    ceiling_light.shadow_enabled = true
    add_child(ceiling_light)

    var hull := StaticBody3D.new()
    hull.name = "WalkableHull"
    hull.collision_layer = 2
    add_child(hull)
    _box(hull, "Deck", Vector3(21.0, 0.25, 13.5), Vector3(0.0, -0.17, 0.0), Color("#193548"))
    var floor_shape := CollisionShape3D.new()
    var floor_box := BoxShape3D.new()
    floor_box.size = Vector3(21.0, 0.25, 13.5)
    floor_shape.shape = floor_box
    floor_shape.position.y = -0.17
    hull.add_child(floor_shape)
    for wall in [
        [Vector3(-10.5, 1.0, 0.0), Vector3(0.35, 2.0, 13.5)],
        [Vector3(10.5, 1.0, 0.0), Vector3(0.35, 2.0, 13.5)],
        [Vector3(0.0, 1.0, -6.75), Vector3(21.0, 2.0, 0.35)],
        [Vector3(0.0, 1.0, 6.75), Vector3(21.0, 2.0, 0.35)],
    ]:
        _box(hull, "HullWall", wall[1], wall[0], Color("#315367"))
        var wall_shape := CollisionShape3D.new()
        var wall_box := BoxShape3D.new()
        wall_box.size = wall[1]
        wall_shape.shape = wall_box
        wall_shape.position = wall[0]
        hull.add_child(wall_shape)

    for x in [-8.4, -4.2, 0.0, 4.2, 8.4]:
        _box(self, "DeckStripe", Vector3(0.055, 0.012, 10.8), Vector3(x, 0.01, 0.0), Color("#31556a"))
    _box(self, "CenterWalkway", Vector3(18.0, 0.018, 1.55), Vector3(0.0, 0.02, 0.0), Color("#274c60"))
    for z in [-5.9, 5.9]:
        for x in [-8.0, -3.0, 2.0, 7.0]:
            _box(self, "ObservationWindow", Vector3(2.7, 0.8, 0.08), Vector3(x, 1.2, z), Color("#28708b"), Color("#3089aa"))
    for x in [-8.6, 8.6]:
        var lamp := OmniLight3D.new()
        lamp.position = Vector3(x, 3.0, 0.0)
        lamp.light_color = Color("#6dd8e6")
        lamp.light_energy = 1.3
        lamp.omni_range = 8.0
        add_child(lamp)

func _build_stations() -> void:
    for index in STATION_POSITIONS.size():
        var station := Node3D.new()
        station.name = "TrainingStation_%d" % (index + 1)
        station.position = STATION_POSITIONS[index]
        add_child(station)
        _box(station, "StationBase", Vector3(1.4, 0.24, 1.25), Vector3(0, 0.12, 0), Color("#416078"))
        _box(station, "ControlPanel", Vector3(0.9, 0.7, 0.55), Vector3(0, 0.62, -0.15), STATION_COLORS[index], STATION_COLORS[index])
        var light := OmniLight3D.new()
        light.position = Vector3(0, 1.4, 0)
        light.light_color = STATION_COLORS[index]
        light.omni_range = 3.3
        station.add_child(light)
        _station_lights.append(light)
        var label := Label3D.new()
        label.text = STATION_NAMES[index]
        label.position = Vector3(0, 1.65, 0)
        label.font_size = 36
        label.pixel_size = 0.011
        label.outline_size = 8
        label.outline_modulate = Color("#06111b")
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        station.add_child(label)
        _station_labels.append(label)
        if index == 2:
            _battery = _box(station, "PracticeBattery", Vector3(0.44, 0.55, 0.4), Vector3(0, 1.18, 0.22), Color("#6fe6a1"), Color("#55db8e"))
        elif index == 4:
            _target = _box(station, "TargetHologram", Vector3(0.55, 1.1, 0.55), Vector3(0, 1.15, 0.2), Color("#ff858b"), Color("#ef4d64"))
        elif index == 5:
            _rescue_light = light

func _box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color, emission: Color = Color.BLACK) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = node_name
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.position = position
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.68
    if emission != Color.BLACK:
        material.emission_enabled = true
        material.emission = emission
        material.emission_energy_multiplier = 0.45
    node.material_override = material
    parent.add_child(node)
    return node
