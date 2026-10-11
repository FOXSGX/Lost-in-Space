extends StaticBody3D
class_name FrostObstacle3D

var obstacle_size := Vector2(3.0, 1.8)
var obstacle_height := 1.2
var obstacle_kind := 0
var _visual_root: Node3D

func setup(map_position: Vector2, size: Vector2, height: float, kind: int) -> void:
    position = Vector3(map_position.x, height * 0.5, map_position.y)
    obstacle_size = size
    obstacle_height = height
    obstacle_kind = kind
    collision_layer = 2
    collision_mask = 1
    _build_visual()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(size.x, height, size.y)
    shape.shape = box
    add_child(shape)

func set_active(active: bool) -> void:
    visible = active
    collision_layer = 2 if active else 0
    collision_mask = 1 if active else 0

func _build_visual() -> void:
    _visual_root = Node3D.new()
    _visual_root.name = "IceBlockVisual"
    add_child(_visual_root)
    var body := MeshInstance3D.new()
    var body_mesh := BoxMesh.new()
    body_mesh.size = Vector3(obstacle_size.x, obstacle_height, obstacle_size.y)
    body.mesh = body_mesh
    body.material_override = _material(_body_color())
    _visual_root.add_child(body)
    var top := MeshInstance3D.new()
    var top_mesh := BoxMesh.new()
    top_mesh.size = Vector3(obstacle_size.x * 0.96, 0.08, obstacle_size.y * 0.96)
    top.position.y = obstacle_height * 0.5 + 0.05
    top.mesh = top_mesh
    top.material_override = _material(_top_color())
    _visual_root.add_child(top)
    var front := MeshInstance3D.new()
    var front_mesh := BoxMesh.new()
    front_mesh.size = Vector3(obstacle_size.x * 0.96, obstacle_height * 0.62, 0.08)
    front.position = Vector3(0.0, -obstacle_height * 0.12, obstacle_size.y * 0.5 + 0.04)
    front.mesh = front_mesh
    front.material_override = _material(_front_color())
    _visual_root.add_child(front)
    var spike_count := 3 if obstacle_kind != 2 else 2
    for index in spike_count:
        var spike := MeshInstance3D.new()
        var spike_mesh := CylinderMesh.new()
        spike_mesh.top_radius = 0.02
        spike_mesh.bottom_radius = 0.16 if obstacle_kind != 3 else 0.12
        spike_mesh.height = obstacle_height * (0.42 + float(index % 2) * 0.16)
        spike_mesh.radial_segments = 6
        spike.mesh = spike_mesh
        var offset_x := (-0.34 + float(index) * 0.34) * obstacle_size.x
        spike.position = Vector3(offset_x, obstacle_height + spike_mesh.height * 0.42, 0.0)
        spike.material_override = _accent_material()
        _visual_root.add_child(spike)
    if obstacle_kind == 2:
        var crack := MeshInstance3D.new()
        var crack_mesh := BoxMesh.new()
        crack_mesh.size = Vector3(obstacle_size.x * 0.72, 0.04, obstacle_size.y * 0.12)
        crack.position = Vector3(0.0, obstacle_height * 0.5 + 0.1, 0.0)
        crack.mesh = crack_mesh
        crack.material_override = _material(Color("#07121e"))
        _visual_root.add_child(crack)

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.72
    return material

func _accent_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#a9f6f1") if obstacle_kind != 2 else Color("#7bc5d6")
    material.emission_enabled = true
    material.emission = Color("#5ee6eb")
    material.emission_energy_multiplier = 0.32
    material.roughness = 0.38
    return material

func _body_color() -> Color:
    match obstacle_kind:
        1: return Color("#315d73")
        2: return Color("#152c3b")
        3: return Color("#465a63")
        _: return Color("#3a7188")

func _top_color() -> Color:
    match obstacle_kind:
        1: return Color("#a6e9f1")
        2: return Color("#6fb7c7")
        3: return Color("#91a9ad")
        _: return Color("#bceff5")

func _front_color() -> Color:
    match obstacle_kind:
        1: return Color("#1f4055")
        2: return Color("#0b1a28")
        3: return Color("#293b45")
        _: return Color("#25485c")
