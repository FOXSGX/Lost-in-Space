extends Node3D
class_name ShipHubKenneyArt

# Native Kenney geometry, with explicit placement around the shared ship anchors.
const S: String = "res://assets/ship-hub/kenney/space-station/"
const M: String = "res://assets/ship-hub/kenney/modular-space/"
const INSTRUMENT_TEXTURE: Texture2D = preload("res://assets/ship-hub/ship_instrument_panel.svg")
const HOLOGRAM: Shader = preload("res://shaders/ship_hologram.gdshader")
const MODELS: Dictionary = {
    "wall": preload(S + "wall-banner.glb"),
    "pillar": preload(S + "wall-pillar.glb"),
    "window": preload(S + "wall-window.glb"),
    "detail": preload(S + "wall-detail.glb"),
    "floor": preload(S + "floor.glb"),
    "floor_detail": preload(S + "floor-detail.glb"),
    "computer": preload(S + "computer.glb"),
    "computer_wide": preload(S + "computer-wide.glb"),
    "computer_system": preload(S + "computer-system.glb"),
    "computer_screen": preload(S + "computer-screen.glb"),
    "wall_display": preload(S + "display-wall-wide.glb"),
    "chair": preload(S + "chair-armrest-headrest.glb"),
    "bed": preload(S + "bed-single.glb"),
    "blanket": preload(S + "bed-single-cover.glb"),
    "container": preload(S + "container.glb"),
    "container_wide": preload(S + "container-wide.glb"),
    "container_tall": preload(S + "container-tall.glb"),
    "table": preload(S + "table-large.glb"),
    "inset": preload(S + "table-inset.glb"),
    "star_table": preload(S + "table-display-planet.glb"),
    "pipe": preload(S + "pipe.glb"),
    "pipe_bend": preload(S + "pipe-bend.glb"),
    "panel": preload(S + "structure-panel.glb"),
    "wall_mechanical": preload(M + "template-wall-detail-a.glb"),
    "column": preload(M + "template-detail.glb"),
    "airlock": preload(M + "gate-door-window.glb"),
    "gate": preload(M + "gate.glb"),
    "cables": preload(M + "cables.glb"),
}

var _bounds_cache: Dictionary = {}
var _materials: Dictionary = {}

func build(previous_model: Node3D) -> void:
    for child: Node in previous_model.find_children("*", "MeshInstance3D", true, false):
        var mesh: MeshInstance3D = child as MeshInstance3D
        var label: String = String(mesh.name)
        var keep: bool = label.contains("panorama_glass") or label == "Decor_plant" or label == "Decor_soil"
        mesh.visible = keep
    _build_deck()
    _build_bulkheads()
    _build_pressure_structure()
    _build_bridge()
    _build_storage()
    _build_workshop()
    _build_support()
    _build_lounge()
    _build_star_chart()
    # Preserve the continuous public floor collider; only wall-facing additions
    # need extra solid geometry. Facility approaches remain outside these strips.
    for side: int in [-1, 1]:
        _solid("InteriorSideCollision", Vector3(side * 19.95, 1.65, 0), Vector3(0.9, 3.3, 30.8))
    _solid("InteriorAftCollision", Vector3(0, 1.65, 15.8), Vector3(39.0, 3.3, 0.35))
    _solid("InteriorForwardCollision", Vector3(0, 1.65, -15.65), Vector3(39.0, 3.3, 0.35))

func _build_deck() -> void:
    for ix: int in 10:
        for iz: int in 8:
            var x: float = -18.0 + ix * 4.0
            var z: float = -14.0 + iz * 4.0
            var kind: String = "floor_detail" if (ix + iz) % 3 == 0 else "floor"
            _asset("Deck_%d_%d" % [ix, iz], kind, Vector3(x, -0.09, z), Vector3(3.97, 0.09, 3.97), 0.0, true)
            if absf(x) >= 10.0:
                var ceiling_panel: Node3D = _asset("CeilingPanel", "panel", Vector3(x, 3.46, z), Vector3(3.97, 0.07, 3.97), 0.0, true)
                ceiling_panel.rotation.x = PI
    for side: int in [-1, 1]:
        _block("PromenadeGuide", Vector3(side * 3.25, 0.025, 4.2), Vector3(0.065, 0.015, 16.7), "#86c4cf", 0.35)
        for z: float in [-8.0, -4.0, 4.0, 8.0, 12.0]:
            _block("WalkwayInsert", Vector3(side * 3.05, 0.027, z), Vector3(0.34, 0.018, 0.14), "#f4ba60", 0.18)
    for entry: Array in [[Vector3(-16.0, 0.025, 7.0), Vector3(4.0, 0.018, 0.12)], [Vector3(16.5, 0.025, -0.6), Vector3(4.0, 0.018, 0.12)], [Vector3(16.5, 0.025, 12.3), Vector3(4.0, 0.018, 0.12)]]:
        _block("ServiceThreshold", entry[0], entry[1], "#e9aa48")

func _build_bulkheads() -> void:
    for side: int in [-1, 1]:
        var yaw: float = PI / 2.0 if side < 0 else -PI / 2.0
        for iz: int in 8:
            var z: float = -14.0 + iz * 4.0
            _asset("SideWall", "pillar" if iz % 3 == 0 else "wall", Vector3(side * 19.96, 0, z), Vector3(3.99, 3.35, 0.42), yaw, true)
        _asset("ServiceWall", "wall_mechanical", Vector3(side * 19.6, 0, -9.5 if side < 0 else -3.0), Vector3(3.6, 3.3, 0.65), yaw + PI, true)
    for ix: int in 10:
        var x: float = -18.0 + ix * 4.0
        _asset("ForwardWall", "window" if absf(x) < 8.0 else "wall", Vector3(x, 0, -15.66), Vector3(3.99, 3.35, 0.42), 0.0, true)
        if absf(x) > 2.5:
            _asset("AftWall", "wall", Vector3(x, 0, 15.65), Vector3(3.99, 3.35, 0.42), PI, true)
    _asset("PressureAirlock", "airlock", Vector3(0, 0, 15.6), Vector3(3.8, 3.36, 0.72), PI, true)
    for side: int in [-1, 1]:
        for end: int in [-1, 1]:
            _asset("CornerColumn", "column", Vector3(side * 19.1, 0, end * 14.8), Vector3(0.65, 3.3, 0.65), 0.0, true)
    # The existing panoramic space shader remains in front of the forward wall.
    for x: float in [-11.9, 11.9]:
        _block("WindowFrame", Vector3(x, 1.94, -14.72), Vector3(0.2, 1.68, 0.22), "#d4d9e0")
    for y: float in [1.18, 2.74]:
        _block("WindowFrame", Vector3(0, y, -14.72), Vector3(24.0, 0.16, 0.22), "#d4d9e0")

func _build_bridge() -> void:
    _block("BridgePlatform", Vector3(0, 0.27, -14.38), Vector3(15.8, 0.66, 2.95), "#344554")
    _block("BridgeLip", Vector3(0, 0.52, -12.87), Vector3(15.8, 0.12, 0.15), "#e6b052", 0.1)
    for x: float in ShipDevices3D.PILOT_X:
        _asset("FlightConsole", "computer_wide", Vector3(x, 0.61, -13.8), Vector3(1.9, 0.95, 1.1))
        _asset("FlightSeat", "chair", Vector3(x, 0.61, -13.0), Vector3(0.75, 1.05, 0.7), PI)
        _instrument_panel(Vector3(x, 1.252, -13.893))
    _asset("BridgeDiagnostic", "wall_display", Vector3(-8.6, 1.05, -15.05), Vector3(1.5, 1.2, 0.6))
    for x: float in [-8.1, -2.6, 2.6, 8.1]:
        _beam("CockpitWindowMullion", Vector3(x, 1.18, -14.65), Vector3(x * 0.88, 2.74, -14.65), 0.14, 0.2, "#344e60")
    for x: float in [-10.5, 10.5]:
        _asset("NavigationHardware", "computer_system", Vector3(x, 0, -13.6), Vector3(1.5, 1.7, 1.3), PI / 2.0 if x < 0 else -PI / 2.0)
    _task_light("BridgeWorkLight", Vector3(0, 3.4, -12.5), "#b4e7ff", 1.6, 9.0)

func _build_storage() -> void:
    _block("CargoRackBack", Vector3(-18.8, 1.0, 4.5), Vector3(0.12, 1.85, 6.1), "#344554")
    for z: float in [1.48, 7.5]:
        for x: float in [-18.88, -17.72]:
            _block("CargoRackUpright", Vector3(x, 0.95, z), Vector3(0.09, 1.9, 0.09), "#53616c")
    for y: float in [0.06, 0.97]:
        _block("CargoShelf", Vector3(-18.3, y, 4.5), Vector3(1.35, 0.09, 6.1), "#d4d9e0")
        for index: int in 4:
            var z: float = 2.1 + index * 1.55
            _asset("StoredCargo", "container_wide" if index % 2 == 0 else "container", Vector3(-18.3, y + 0.045, z), Vector3(1.12, 0.79, 1.05), PI / 2.0)
    for z: float in [3.4, 5.45]:
        _asset("LooseCargo", "container", Vector3(-16.88, 0, z), Vector3(0.84, 0.66, 0.82))

func _build_workshop() -> void:
    _asset("RepairWorkbench", "table", Vector3(18.08, 0, -2.98), Vector3(2.05, 1.0, 1.05), 0.0, true)
    _asset("RepairComputer", "computer_system", Vector3(18.08, 1.0, -3.01), Vector3(0.9, 0.66, 0.85), -PI / 2.0)
    _asset("BenchComponent", "pipe_bend", Vector3(18.45, 1.02, -2.64), Vector3(0.5, 0.42, 0.32))
    _asset("ServicePanel", "wall_display", Vector3(19.05, 1.2, -2.98), Vector3(1.5, 0.95, 0.35), -PI / 2.0)
    _task_light("EngineeringWorkLight", Vector3(17.2, 2.8, -3.0), "#ffe0b0", 1.4, 5.0)

func _build_support() -> void:
    _asset("OxygenStorage", "container_tall", Vector3(18.51, 0, 10.26), Vector3(0.94, 1.5, 0.94))
    _asset("SupportPipe", "pipe", Vector3(18.51, 1.39, 10.26), Vector3(0.56, 0.39, 0.56), 0.0, true)
    _block("SupplyConsoleStand", Vector3(17.37, 0.2, 10.25), Vector3(0.35, 0.4, 0.38), "#53616c")
    _asset("SupplyConsole", "computer", Vector3(17.37, 0.4, 10.25), Vector3(0.39, 0.64, 0.41), -PI / 2.0)
    _block("MissionPedestal", Vector3(-17.53, 0.32, -10.09), Vector3(0.5, 0.64, 0.55), "#53616c")
    _asset("MissionConsole", "computer_screen", Vector3(-17.53, 0.64, -10.09), Vector3(0.55, 0.5, 0.55), PI / 2.0)

func _build_lounge() -> void:
    for side: int in [-1, 1]:
        for z: float in [5.2, -4.8]:
            # Two compact berths occupy the previous bench collision footprint.
            for y: float in [0.02, 0.88]:
                _asset("CrewBerth", "bed", Vector3(side * 8.7, y, z), Vector3(1.05, 0.37, 2.6), PI / 2.0, true)
                _asset("CrewBlanket", "blanket", Vector3(side * 8.7 + 0.35, y + 0.28, z), Vector3(1.04, 0.055, 1.65), PI / 2.0, true)
                _block("BerthReadingLight", Vector3(side * 8.7, y + 0.35, z + 0.49), Vector3(2.45, 0.045, 0.04), "#b8e0dd", 0.65)
            for x: float in [side * 8.7 - 1.55, side * 8.7 + 1.55]:
                _block("BerthSupport", Vector3(x, 0.65, z), Vector3(0.1, 1.3, 1.0), "#344e60")
        _asset("PlanterContainer", "container_wide", Vector3(side * 11.7, 0, 0.7), Vector3(1.1, 0.95, 1.1), 0.0, true)
        _asset("CrewSideTable", "inset", Vector3(side * 11.3, 0, 5.2), Vector3(1.05, 0.75, 1.05), 0.0, true)

func _build_pressure_structure() -> void:
    # A raised central pressure hull, with equipment bays behind lateral doors.
    # Openings line up with the existing facility approach paths.
    for z: float in [-12.0, -6.8, 1.2, 7.0, 13.0]:
        for side: int in [-1, 1]:
            _beam("HullRibPost", Vector3(side * 6.5, 0, z), Vector3(side * 6.5, 2.65, z), 0.3, 0.46, "#304b60")
            _beam("HullRibShoulder", Vector3(side * 6.5, 2.65, z), Vector3(side * 4.65, 4.58, z), 0.3, 0.46, "#304b60")
            _solid("HullRibCollision", Vector3(side * 6.5, 1.3, z), Vector3(0.34, 2.6, 0.5))
            _block("RibWarningBand", Vector3(side * 6.5, 0.7, z), Vector3(0.34, 0.18, 0.5), "#d99d48")
        _beam("HullRibCrown", Vector3(-4.65, 4.58, z), Vector3(4.65, 4.58, z), 0.3, 0.46, "#304b60")
    for side: int in [-1, 1]:
        for interval: Vector2 in [Vector2(-15.4, -11.6), Vector2(-8.4, -4.6), Vector2(-1.4, 2.85), Vector2(6.05, 8.58), Vector2(11.78, 15.4)]:
            var center_z: float = (interval.x + interval.y) * 0.5
            var length_z: float = interval.y - interval.x
            _asset("EquipmentBayBulkhead", "wall", Vector3(side * 6.5, 0, center_z), Vector3(length_z, 3.38, 0.3), side * -PI / 2.0, true)
            _solid("EquipmentBayCollision", Vector3(side * 6.5, 1.69, center_z), Vector3(0.32, 3.38, length_z))
        for z: float in [-10.0, -3.0, 4.45, 10.18]:
            _asset("EquipmentBayPortal", "gate", Vector3(side * 6.5, 0, z), Vector3(3.4, 3.5, 0.45), PI / 2.0, true)
            for offset: float in [-1.42, 1.42]:
                _solid("BayPortalJambCollision", Vector3(side * 6.5, 1.6, z + offset), Vector3(0.6, 3.2, 0.45))
            _block("BayPortalLight", Vector3(side * 6.5, 3.0, z), Vector3(0.5, 0.07, 1.8), "#8dd9e4", 1.1)
        # Longitudinal utility trunks are mounted above head height.
        for x_offset: float in [0.0, 0.26]:
            _beam("OverheadUtilityTrunk", Vector3(side * (5.65 + x_offset), 3.55, -15.0), Vector3(side * (5.65 + x_offset), 3.55, 15.0), 0.12, 0.12, "#9caeaf")
        for z: float in [-10.0, -3.0, 4.45, 10.18]:
            _asset("WallUtilityAssembly", "pipe_bend", Vector3(side * 19.2, 2.55, z + 1.5), Vector3(0.45, 0.55, 0.45), side * PI / 2.0)
        for z: float in [-11.0, -3.0, 5.0, 13.0]:
            _block("CentralCeilingStrip", Vector3(side * 4.0, 4.68, z), Vector3(0.13, 0.05, 3.4), "#c1e9ed", 1.5)
    for z: float in [-6.5, 4.5]:
        _task_light("CentralHullLight", Vector3(0, 3.9, z), "#c7e5ef", 1.5, 10.0)
    _task_light("LifeSupportWorkLight", Vector3(17.8, 2.6, 10.0), "#b2eed4", 1.3, 5.0)

func _build_star_chart() -> void:
    _asset("StarChartPedestal", "inset", Vector3(0, 0, -0.34), Vector3(2.6, 0.85, 2.6), 0.0, true)
    var chart: Node3D = _asset("CentralStarChart", "star_table", Vector3(0, 0.45, -0.34), Vector3(1.65, 1.32, 1.65))
    var hologram: ShaderMaterial = ShaderMaterial.new()
    hologram.shader = HOLOGRAM
    hologram.set_shader_parameter("hologram_color", Color("#62d8e6"))
    hologram.set_shader_parameter("base_alpha", 0.18)
    hologram.set_shader_parameter("fresnel_boost", 0.65)
    hologram.set_shader_parameter("scanline_count", 250.0)
    hologram.set_shader_parameter("scanline_speed", 0.12)
    hologram.set_shader_parameter("flicker_amount", 0.0)
    for child: Node in chart.find_children("*", "MeshInstance3D", true, false):
        var mesh: MeshInstance3D = child as MeshInstance3D
        if String(mesh.name).begins_with("table-display-planet"):
            # Keep the native planet and ring children; only remove its low base.
            mesh.mesh = null
        else:
            mesh.material_override = hologram

func _instrument_panel(center: Vector3) -> void:
    if not _materials.has("instrument"):
        var material: StandardMaterial3D = StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_texture = INSTRUMENT_TEXTURE
        _materials["instrument"] = material
    var panel: MeshInstance3D = MeshInstance3D.new()
    panel.name = "NavigationDisplay"
    var quad: QuadMesh = QuadMesh.new()
    quad.size = Vector2(1.24, 0.64)
    panel.mesh = quad
    panel.material_override = _materials["instrument"]
    panel.position = center
    panel.rotation_degrees.x = -56.31
    add_child(panel)

func _style_native(visual: Node3D, key: String) -> void:
    var deck: bool = key == "floor" or key == "floor_detail"
    for child: Node in visual.find_children("*", "MeshInstance3D", true, false):
        var mesh: MeshInstance3D = child as MeshInstance3D
        for surface: int in mesh.mesh.get_surface_count():
            var source: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
            if source == null:
                continue
            var cache_key: String = "native_%d_%s" % [source.get_instance_id(), str(deck)]
            if not _materials.has(cache_key):
                var material: StandardMaterial3D = source.duplicate() as StandardMaterial3D
                # The source palette contains gradients: linear sampling avoids
                # visible nearest-sampled bands on large first-person surfaces.
                material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
                if deck:
                    material.albedo_color = Color("#71869e")
                _materials[cache_key] = material
            mesh.set_surface_override_material(surface, _materials[cache_key])

func _asset(node_name: String, key: String, bottom_center: Vector3, target: Vector3, yaw: float = 0.0, exact: bool = false) -> Node3D:
    var visual: Node3D = (MODELS[key] as PackedScene).instantiate() as Node3D
    _style_native(visual, key)
    var bounds: AABB
    if _bounds_cache.has(key):
        bounds = _bounds_cache[key]
    else:
        bounds = _branch_bounds(visual, Transform3D.IDENTITY)
        _bounds_cache[key] = bounds
    var ratios: Vector3 = Vector3(target.x / maxf(bounds.size.x, 0.001), target.y / maxf(bounds.size.y, 0.001), target.z / maxf(bounds.size.z, 0.001))
    var fit: Vector3 = ratios if exact else Vector3.ONE * minf(ratios.x, minf(ratios.y, ratios.z))
    var holder: Node3D = Node3D.new()
    holder.name = node_name
    holder.position = bottom_center
    holder.rotation.y = yaw
    holder.set_meta("kenney_asset", key)
    add_child(holder)
    var normalizer: Node3D = Node3D.new()
    normalizer.scale = fit
    normalizer.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * fit
    holder.add_child(normalizer)
    normalizer.add_child(visual)
    return holder

func _branch_bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
    var transform_here: Transform3D = parent_transform * node.transform
    var result: AABB = AABB()
    if node is MeshInstance3D:
        result = transform_here * (node as MeshInstance3D).get_aabb()
    for child: Node in node.get_children():
        if child is Node3D:
            var child_bounds: AABB = _branch_bounds(child as Node3D, transform_here)
            if child_bounds.size.length_squared() > 0.0:
                result = result.merge(child_bounds) if result.size.length_squared() > 0.0 else child_bounds
    return result

func _beam(node_name: String, start: Vector3, end: Vector3, width: float, depth: float, color: String) -> void:
    var direction: Vector3 = end - start
    var instance: MeshInstance3D = _block(node_name, (start + end) * 0.5, Vector3(width, direction.length(), depth), color)
    instance.quaternion = Quaternion(Vector3.UP, direction.normalized())

func _task_light(node_name: String, point: Vector3, color: String, energy: float, radius: float) -> void:
    var light: OmniLight3D = OmniLight3D.new()
    light.name = node_name
    light.position = point
    light.light_color = Color(color)
    light.light_energy = energy
    light.omni_range = radius
    add_child(light)

func _block(node_name: String, center: Vector3, size: Vector3, color: String, emission: float = 0.0) -> MeshInstance3D:
    var cache_key: String = color + str(emission)
    if not _materials.has(cache_key):
        var material: StandardMaterial3D = StandardMaterial3D.new()
        material.albedo_color = Color(color)
        material.roughness = 0.7
        material.emission_enabled = emission > 0.0
        material.emission = Color(color)
        material.emission_energy_multiplier = emission
        _materials[cache_key] = material
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.material_override = _materials[cache_key]
    instance.position = center
    add_child(instance)
    return instance

func _solid(node_name: String, center: Vector3, size: Vector3) -> void:
    var body: StaticBody3D = StaticBody3D.new()
    body.name = node_name
    body.position = center
    body.collision_layer = 2
    body.collision_mask = 0
    var shape: CollisionShape3D = CollisionShape3D.new()
    var box: BoxShape3D = BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    add_child(body)
