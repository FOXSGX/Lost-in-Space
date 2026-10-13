extends StaticBody3D
class_name FrostObstacle3D

const ART_UTILS := preload("res://scripts/art_utils.gd")

var obstacle_size := Vector2(3.0, 1.8)
var obstacle_height := 1.2
var obstacle_kind := 0
var ground_height := 0.0
var _visual_root: Node3D

func setup(map_position: Vector2, size: Vector2, height: float, kind: int, terrain_sample := 0.0) -> void:
    position = Vector3(map_position.x, height * 0.5, map_position.y)
    obstacle_size = size
    obstacle_height = height
    obstacle_kind = kind
    # 地表噪声振幅约 ±0.21，物件底部贴地暗斑必须知道自己脚下地面的高度，
    # 否则在雪包上会被地形吃掉一半。
    ground_height = terrain_sample
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
    # 落脚提示：俯视下冰岩靠自身的投影很难判断是"立在地上"还是"贴在地上"。
    ART_UTILS.contact_shadow(_visual_root, Vector3(0.0, -obstacle_height * 0.5 + ground_height, 0.0), maxf(obstacle_size.x, obstacle_size.y) * 0.72)
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
    # 俯视 46° 下最先被看到的是顶面，只靠一块方板的顶面读不出"冰"，
    # 只会读成一个白盒子。在顶面堆一层不规则的冰冠，靠棱角和高光给它形状。
    var rng := RandomNumberGenerator.new()
    rng.seed = int(obstacle_size.x * 977.0 + obstacle_size.y * 613.0 + float(obstacle_kind) * 41.0 + position.x)
    var crown_count := clampi(int(maxf(obstacle_size.x, obstacle_size.y) * 1.2), 2, 6)
    for crown_index in crown_count:
        var crown := MeshInstance3D.new()
        var crown_mesh := CylinderMesh.new()
        var crown_radius := rng.randf_range(0.34, 0.74)
        crown_mesh.top_radius = crown_radius * rng.randf_range(0.28, 0.68)
        crown_mesh.bottom_radius = crown_radius
        crown_mesh.height = rng.randf_range(0.18, 0.46)
        crown_mesh.radial_segments = rng.randi_range(5, 7)
        crown.mesh = crown_mesh
        crown.position = Vector3(
            rng.randf_range(-0.4, 0.4) * obstacle_size.x,
            obstacle_height * 0.5 + crown_mesh.height * 0.34,
            rng.randf_range(-0.4, 0.4) * obstacle_size.y
        )
        crown.rotation_degrees = Vector3(rng.randf_range(-15.0, 15.0), rng.randf_range(0.0, 360.0), rng.randf_range(-15.0, 15.0))
        crown.material_override = _material(_crown_color(), 0.34)
        crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        _visual_root.add_child(crown)
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

func _material(color: Color, roughness := 0.52) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    # 冰面比岩石更亮、更反光；粗糙度统一压低，让顶面有掠光，
    # 否则整块冰看起来和雪地是同一个材质。
    material.roughness = roughness
    material.metallic = 0.04
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
    # 顶面压暗、冰冠提亮，两个明度层叠在一起，俯视下才有"积雪盖着冰"的层次。
    # 原来顶面接近纯白，和雪地同色，冰岩于是消失在地面上。
    match obstacle_kind:
        1: return Color("#4a7d92")
        2: return Color("#2b5a6b")
        3: return Color("#5a7078")
        _: return Color("#4a8098")

func _crown_color() -> Color:
    match obstacle_kind:
        1: return Color("#cdf1f8")
        2: return Color("#a3d9e6")
        3: return Color("#c6d6d9")
        _: return Color("#d8f7fc")

func _front_color() -> Color:
    match obstacle_kind:
        1: return Color("#1f4055")
        2: return Color("#0b1a28")
        3: return Color("#293b45")
        _: return Color("#25485c")
