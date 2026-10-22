extends Node3D
class_name ShipTutorial3D

const ENTRY_POINT: Vector3 = Vector3(8.1, 0, 5.1)
const ENTRY_YAW: float = 0.85
const HOP_POINT: Vector3 = Vector3(-3.8, 0.55, 3.8)
const BOOST_POINT: Vector3 = Vector3(-4.2, 2.6, -2.3)
const CROSS_POINT: Vector3 = Vector3(2.2, 4.35, -2.3)
const FINISH_POINT: Vector3 = Vector3(6.4, 5.7, 2.5)
# Old diagnostic scripts can still resolve these landmarks; the stations are gone.
const INSTALL_POINT: Vector3 = BOOST_POINT
const SCAN_POINT: Vector3 = CROSS_POINT
const TARGET_POINT: Vector3 = FINISH_POINT
const NATIVE: String = "res://assets/ship-hub/kenney/space-station/"
const TABLE: PackedScene = preload(NATIVE + "table-large.glb")
const FLOOR: PackedScene = preload(NATIVE + "floor-detail.glb")
const WALL: PackedScene = preload(NATIVE + "wall-banner.glb")
const WINDOW: PackedScene = preload(NATIVE + "wall-window.glb")
const DOOR: PackedScene = preload("res://assets/ship-hub/kenney/modular-space/gate-door-window.glb")
const POSTERS: Dictionary = {
    "equip": preload("res://assets/training-wall-posters/01-equip.png"),
    "jump": preload("res://assets/training-wall-posters/02-jump.png"),
    "boost": preload("res://assets/training-wall-posters/03-boost.png"),
    "recharge": preload("res://assets/training-wall-posters/04-recharge.png"),
    "cross": preload("res://assets/training-wall-posters/05-cross.png"),
    "exit": preload("res://assets/training-wall-posters/06-exit.png"),
}
var _markers: Array[MeshInstance3D] = []
var _step: int = 0

func _ready() -> void:
    _build_room()
    _build_course()
    show_step(_step)

func station_position(step: int) -> Vector3:
    var points: Array[Vector3] = [Vector3(-7, 0, 3.8), Vector3(-7, 0, 3.8), HOP_POINT, BOOST_POINT, FINISH_POINT, FINISH_POINT]
    return points[clampi(step, 0, points.size() - 1)]

func show_step(step: int) -> void:
    _step = step
    for index: int in _markers.size():
        _markers[index].material_override = _material(Color("#a5f1d0") if step >= mini(index + 3, 5) else Color("#eeb663"), true)

func _build_room() -> void:
    var environment: WorldEnvironment = WorldEnvironment.new()
    var env: Environment = Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#182f48")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#d2e6ec")
    env.ambient_light_energy = 0.75
    environment.environment = env
    add_child(environment)
    _solid("WalkableHull", Vector3(0, -0.12, 0), Vector3(21, 0.24, 13.5))
    _box("FloorBase", Vector3(0, -0.15, 0), Vector3(21, 0.15, 13.5), Color("#344e64"))
    _solid("ForwardWallCollision", Vector3(0, 4.6, -6.65), Vector3(21, 9.2, 0.25))
    _solid("AftWallCollision", Vector3(0, 4.6, 6.65), Vector3(21, 9.2, 0.25))
    for side: int in [-1, 1]:
        _solid("SideWallCollision", Vector3(side * 10.4, 4.6, 0), Vector3(0.25, 9.2, 13.5))
        for z: float in [-4.5, 0, 4.5]:
            _native(WINDOW, Vector3(side * 10.4, 0, z), Vector3(4.5, 3.45, 0.22), side * -PI / 2.0)
        _box("UpperSideHull", Vector3(side * 10.45, 6.3, 0), Vector3(0.2, 5.7, 13.5), Color("#355268"))
    for ix: int in 5:
        var x: float = -8.4 + ix * 4.2
        _native(WALL, Vector3(x, 0, -6.65), Vector3(4.19, 3.45, 0.22))
        if ix < 4:
            _native(WALL, Vector3(x, 0, 6.65), Vector3(4.19, 3.45, 0.22), PI)
        for iz: int in 3:
            _native(FLOOR, Vector3(x, -0.08, -4.4 + iz * 4.4), Vector3(4.17, 0.08, 4.37))
    for z: float in [-6.7, 6.7]:
        _box("UpperHull", Vector3(0, 6.3, z), Vector3(21, 5.7, 0.2), Color("#355268"))
        for y: float in [3.6, 6.6, 8.8]:
            _box("HullStripe", Vector3(0, y, z * 0.98), Vector3(20.5, 0.08, 0.08), Color("#739eaa"), true)
    _native(DOOR, Vector3(8.1, 0, 6.45), Vector3(3.65, 3.35, 0.45), PI)
    _solid("CeilingCollision", Vector3(0, 9.3, 0), Vector3(21, 0.2, 13.5))
    _box("Ceiling", Vector3(0, 9.4, 0), Vector3(21, 0.2, 13.5), Color("#263f57"))
    for x: float in [-7, 0, 7]:
        _box("CeilingLight", Vector3(x, 9.12, 0), Vector3(3.0, 0.06, 0.25), Color("#daf5ee"), true)
        var light: OmniLight3D = OmniLight3D.new()
        light.position = Vector3(x, 6.5, 0)
        light.light_color = Color("#e3f5ef")
        light.light_energy = 2.3
        light.omni_range = 14.0
        add_child(light)
    _wall_poster("exit", Vector3(8.1, 3.95, 6.55), Vector2(2.4, 1.44), PI)

func _build_course() -> void:
    _native(TABLE, Vector3(-7, 0, 3.8), Vector3(1.7, 0.9, 1.0))
    _solid("OxygenRack", Vector3(-7, 0.45, 3.8), Vector3(1.7, 0.9, 1.0))
    _wall_poster("equip", Vector3(-10.245, 1.95, 3.8), Vector2(3.2, 1.92), PI / 2.0)
    _platform("Hop", HOP_POINT, Vector2(2.4, 2.4), Color("#669eaa"))
    _platform("Boost", BOOST_POINT, Vector2(3.3, 3.2), Color("#64bfb1"))
    _platform("Cross", CROSS_POINT, Vector2(3.2, 3.2), Color("#77b9cb"))
    _platform("Finish", FINISH_POINT, Vector2(3.0, 2.8), Color("#dfae69"))
    _wall_poster("jump", Vector3(-3.8, 1.85, 6.49), Vector2(3.2, 1.92), PI)
    _wall_poster("boost", Vector3(-4.2, 4.45, -6.55), Vector2(3.6, 2.16))
    _wall_poster("recharge", Vector3(2.2, 6.1, -6.55), Vector2(3.6, 2.16))
    _wall_poster("cross", Vector3(10.245, 7.2, 2.5), Vector2(3.4, 2.04), -PI / 2.0)
    for pair: Array in [[Vector3(-6, 0.035, 3.8), HOP_POINT], [HOP_POINT, BOOST_POINT], [BOOST_POINT, CROSS_POINT], [CROSS_POINT, FINISH_POINT]]:
        var start: Vector3 = pair[0]
        var end: Vector3 = pair[1]
        for index: int in 7:
            var point: Vector3 = start.lerp(end, float(index) / 7.0)
            point.y = 0.02
            _box("RouteDot", point, Vector3(0.16, 0.02, 0.16), Color("#b9eedb"), true)

func _platform(title: String, top: Vector3, footprint: Vector2, color: Color) -> void:
    var thickness: float = minf(top.y, 0.28)
    var center: Vector3 = Vector3(top.x, top.y - thickness * 0.5, top.z)
    var size: Vector3 = Vector3(footprint.x, thickness, footprint.y)
    _solid(title + "PlatformCollision", center, size)
    _box(title + "Platform", center, size, color.darkened(0.25))
    _box(title + "LandingPad", top + Vector3.UP * 0.015, Vector3(footprint.x, 0.035, footprint.y), color)
    _markers.append(_box(title + "LandingStripe", top + Vector3(0, 0.04, footprint.y * 0.5 - 0.12), Vector3(footprint.x - 0.2, 0.035, 0.12), Color("#eeb663"), true))
    for x: float in [-footprint.x * 0.4, footprint.x * 0.4]:
        for z: float in [-footprint.y * 0.4, footprint.y * 0.4]:
            var leg: Vector3 = Vector3(top.x + x, (top.y - thickness) * 0.5, top.z + z)
            var leg_size: Vector3 = Vector3(0.13, maxf(0.1, top.y - thickness), 0.13)
            _box(title + "Support", leg, leg_size, color.lightened(0.15))
            _solid(title + "SupportCollision", leg, leg_size)

func _wall_poster(poster_id: String, point: Vector3, size: Vector2, yaw: float = 0.0) -> void:
    var frame: MeshInstance3D = _box("WallPoster_" + poster_id, point, Vector3(size.x + 0.12, size.y + 0.12, 0.08), Color("#243e4e"))
    frame.rotation.y = yaw
    var image: MeshInstance3D = MeshInstance3D.new()
    image.name = "PrintedImage"
    var plane: QuadMesh = QuadMesh.new()
    plane.size = size
    image.mesh = plane
    image.position.z = 0.045
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_texture = POSTERS[poster_id] as Texture2D
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    image.material_override = material
    frame.add_child(image)

func _native(scene: PackedScene, point: Vector3, size: Vector3, yaw: float = 0.0) -> void:
    var root: Node3D = Node3D.new()
    root.position = point
    root.rotation.y = yaw
    add_child(root)
    var visual: Node3D = scene.instantiate() as Node3D
    ItemProp3D.linear_materials(visual)
    var bounds: AABB = ItemProp3D._bounds(visual, Transform3D.IDENTITY)
    var fit: Vector3 = size / bounds.size
    var normalizer: Node3D = Node3D.new()
    normalizer.scale = fit
    normalizer.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * fit
    root.add_child(normalizer)
    normalizer.add_child(visual)

func _solid(node_name: String, point: Vector3, size: Vector3) -> void:
    var body: StaticBody3D = StaticBody3D.new()
    body.name = node_name
    body.position = point
    body.collision_layer = 2
    body.collision_mask = 0
    var shape: CollisionShape3D = CollisionShape3D.new()
    var box: BoxShape3D = BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    add_child(body)

func _box(node_name: String, point: Vector3, size: Vector3, color: Color, emission: bool = false) -> MeshInstance3D:
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = node_name
    instance.position = point
    var box: BoxMesh = BoxMesh.new()
    box.size = size
    instance.mesh = box
    instance.material_override = _material(color, emission)
    add_child(instance)
    return instance

func _material(color: Color, emission: bool = false) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.75
    material.emission_enabled = emission
    material.emission = color
    material.emission_energy_multiplier = 0.35
    return material
