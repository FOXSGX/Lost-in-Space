extends Node3D
class_name ItemProp3D

# Runtime props reuse the selected CC0 Kenney meshes; markers are physical details.
const CASE: PackedScene = preload("res://assets/ship-hub/kenney/space-station/container.glb")
const TANK: PackedScene = preload("res://assets/ship-hub/kenney/space-station/pipe.glb")
const WIDE_CASE: PackedScene = preload("res://assets/ship-hub/kenney/space-station/container-wide.glb")
const COLORS: Dictionary = {"medical": "#ed777a", "oxygen": "#77d7f3", "battery": "#79edce", "sample": "#b49cff", "penguin": "#8de9ff", "bubble": "#c5a4ff", "board": "#ffd36e", "hologram": "#ff9bd7", "smoke": "#ff7fd1"}
static var _filtered_materials: Dictionary = {}

static func create(kind: String) -> ItemProp3D:
    var prop: ItemProp3D = ItemProp3D.new()
    prop.name = "Item_" + kind
    prop._build(kind)
    return prop

func _build(kind: String) -> void:
    var color: Color = Color(COLORS.get(kind, "#ffc779"))
    if kind == "oxygen":
        _native(TANK, Vector3(0.29, 0.58, 0.29))
        _detail(Vector3(0, 0.33, 0), Vector3(0.3, 0.19, 0.3), color)
        _detail(Vector3(0, 0.6, 0), Vector3(0.22, 0.07, 0.08), Color("#dfe8de"))
    else:
        _native(WIDE_CASE if kind == "battery" else CASE, Vector3(0.42, 0.38, 0.3))
        _detail(Vector3(0, 0.24, 0.155), Vector3(0.28, 0.2, 0.025), color)
        if kind == "medical":
            _detail(Vector3(0, 0.24, 0.174), Vector3(0.17, 0.045, 0.018), Color.WHITE)
            _detail(Vector3(0, 0.24, 0.174), Vector3(0.045, 0.15, 0.018), Color.WHITE)
        elif kind == "battery":
            for x: float in [-0.09, 0.0, 0.09]:
                _detail(Vector3(x, 0.25, 0.174), Vector3(0.045, 0.12, 0.018), Color("#e0fff0"))
        elif kind == "sample":
            var crystal: MeshInstance3D = MeshInstance3D.new()
            var shape: PrismMesh = PrismMesh.new()
            shape.size = Vector3(0.16, 0.3, 0.16)
            crystal.mesh = shape
            crystal.position.y = 0.45
            crystal.material_override = _material(color)
            add_child(crystal)

func _native(scene: PackedScene, target: Vector3) -> void:
    var model: Node3D = scene.instantiate() as Node3D
    var bounds: AABB = _bounds(model, Transform3D.IDENTITY)
    var fit: Vector3 = target / bounds.size
    var wrapper: Node3D = Node3D.new()
    wrapper.scale = fit
    wrapper.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * fit
    add_child(wrapper)
    wrapper.add_child(model)
    linear_materials(model)
    for child: Node in model.find_children("*", "MeshInstance3D", true, false):
        var mesh: MeshInstance3D = child as MeshInstance3D
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func linear_materials(model: Node3D) -> void:
    for child: Node in model.find_children("*", "MeshInstance3D", true, false):
        var instance: MeshInstance3D = child as MeshInstance3D
        for surface: int in instance.mesh.get_surface_count():
            var source: StandardMaterial3D = instance.get_active_material(surface) as StandardMaterial3D
            if source == null:
                continue
            var key: int = source.get_instance_id()
            if not _filtered_materials.has(key):
                var filtered: StandardMaterial3D = source.duplicate() as StandardMaterial3D
                filtered.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
                _filtered_materials[key] = filtered
            instance.set_surface_override_material(surface, _filtered_materials[key])

static func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
    var here: Transform3D = parent_transform * node.transform
    var result: AABB = here * (node as MeshInstance3D).get_aabb() if node is MeshInstance3D else AABB()
    for child: Node in node.get_children():
        if child is Node3D:
            var next: AABB = _bounds(child as Node3D, here)
            if next.size.length_squared() > 0.0:
                result = result.merge(next) if result.size.length_squared() > 0.0 else next
    return result

func _detail(point: Vector3, size: Vector3, color: Color) -> void:
    var instance: MeshInstance3D = MeshInstance3D.new()
    var box: BoxMesh = BoxMesh.new()
    box.size = size
    instance.mesh = box
    instance.position = point
    instance.material_override = _material(color)
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(instance)

static func _material(color: Color) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.68
    return material
