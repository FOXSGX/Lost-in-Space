extends Node3D

var manifest: Dictionary = {}
var camera: Camera3D
var current_view: String = "A_entry"
var mineral_materials: Array[StandardMaterial3D] = []
var meshes: Array[MeshInstance3D] = []
var pulse_time: float = 0.0
var frozen_pulse: float = -1.0
var title: Label
var model: Node3D
var loaded: bool = false

func _ready() -> void:
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/station_manifest.json"))
    if not raw is Dictionary:
        push_error("Missing station manifest")
        return
    manifest = raw as Dictionary
    var packed: PackedScene = load("res://assets/mining_station_01.glb") as PackedScene
    if packed == null:
        push_error("GLB import failed")
        return
    model = packed.instantiate() as Node3D
    add_child(model)
    _collect(model)
    var environment: Environment = Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.012, 0.018, 0.028)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.52, 0.60, 0.70)
    environment.ambient_light_energy = 0.42
    environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    var world: WorldEnvironment = WorldEnvironment.new()
    world.environment = environment
    add_child(world)
    # Compatibility has no Eevee-style area emitters or GI. These local runtime
    # lights approximate the same warm pools and cyan mineral bounce explicitly.
    _omni("Warm work pool west", Vector3(-5.2, 4.05, -0.85), Color(1.0, 0.75, 0.47), 3.1, 8.0, true)
    _omni("Warm work pool middle", Vector3(2.0, 4.25, -0.65), Color(1.0, 0.75, 0.48), 3.3, 8.5, true)
    _omni("Warm far pool", Vector3(8.0, 4.10, 0.1), Color(1.0, 0.74, 0.47), 2.2, 7.0, true)
    _omni("Cool rock fill", Vector3(-0.6, 3.7, 3.2), Color(0.68, 0.82, 1.0), 1.8, 10.0, false)
    _omni("Mineral reflected cyan", Vector3(4.5, 2.5, -4.0), Color(0.12, 0.64, 1.0), 1.0, 4.2, false)
    _omni("Entry around corner", Vector3(-12.3, 2.5, -1.5), Color(0.61, 0.79, 1.0), 2.1, 7.0, false)
    _omni("Distant mineral gallery", Vector3(14.5, 2.2, -0.8), Color(0.12, 0.54, 0.72), 1.5, 6.0, false)
    camera = Camera3D.new()
    camera.near = 0.04
    camera.far = 100.0
    camera.current = true
    add_child(camera)
    var ui: CanvasLayer = CanvasLayer.new()
    add_child(ui)
    title = Label.new()
    title.position = Vector2(18, 14)
    title.add_theme_font_size_override("font_size", 18)
    title.add_theme_color_override("font_shadow_color", Color.BLACK)
    title.add_theme_constant_override("shadow_offset_x", 2)
    title.add_theme_constant_override("shadow_offset_y", 2)
    ui.add_child(title)
    for index: int in range(4):
        var action: String = "view_" + str(index + 1)
        if not InputMap.has_action(action):
            InputMap.add_action(action)
            var key: InputEventKey = InputEventKey.new()
            key.physical_keycode = (KEY_1 + index) as Key
            InputMap.action_add_event(action, key)
    set_view("A_entry")
    loaded = true

func _omni(label: String, at: Vector3, color: Color, energy: float, radius: float, shadows: bool) -> void:
    var light: OmniLight3D = OmniLight3D.new()
    light.name = label
    light.position = at
    light.light_color = color
    light.light_energy = energy
    light.omni_range = radius
    light.shadow_enabled = shadows
    add_child(light)

func _collect(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh: MeshInstance3D = node as MeshInstance3D
        meshes.append(mesh)
        for index: int in range(mesh.mesh.get_surface_count()):
            var material: StandardMaterial3D = mesh.get_active_material(index) as StandardMaterial3D
            if material != null and material.albedo_texture != null:
                material.uv1_triplanar = true
                material.uv1_world_triplanar = true
                material.uv1_scale = Vector3(0.28, 0.28, 0.28)
            if material != null and ("resonant mineral" in material.resource_name or "deep cleavage" in material.resource_name):
                material.vertex_color_use_as_albedo = true
                material.vertex_color_is_srgb = false
                # glTF preserves COLOR_0 but cannot bind it to emission; use an
                # explicit native mineral tint instead of imported white emission.
                material.emission = Color(0.16, 0.065, 0.30) if "violet" in material.resource_name else Color(0.015, 0.26, 0.36)
                if not mineral_materials.has(material):
                    mineral_materials.append(material)
    for child: Node in node.get_children():
        _collect(child)

func set_view(view: String) -> void:
    var views: Dictionary = manifest.get("cameras", {}) as Dictionary
    var key: String = "PLAYER · " + view
    if not views.has(key):
        push_error("Unknown view: " + view)
        return
    var data: Dictionary = views[key] as Dictionary
    var position_data: Array = data["position"] as Array
    var direction_data: Array = data["direction"] as Array
    var up_data: Array = data["up"] as Array
    var at: Vector3 = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
    var direction: Vector3 = Vector3(float(direction_data[0]), float(direction_data[1]), float(direction_data[2]))
    var up: Vector3 = Vector3(float(up_data[0]), float(up_data[1]), float(up_data[2]))
    camera.look_at_from_position(at, at + direction, up)
    camera.fov = float(data["fov_vertical"])
    current_view = view
    title.text = "GODOT 4.7.2  |  Compatibility  |  " + view + "\n1-4: eye-height views  /  material pipeline prototype"

func _unhandled_input(event: InputEvent) -> void:
    var keys: Array[String] = ["A_entry", "B_cart_side", "C_mineral", "D_return"]
    for index: int in range(4):
        if event.is_action_pressed("view_" + str(index + 1)):
            set_view(keys[index])

func _process(delta: float) -> void:
    pulse_time += delta
    var gain: float = frozen_pulse if frozen_pulse >= 0.0 else 0.22 + 0.08 * sin(pulse_time * 1.7)
    for material: StandardMaterial3D in mineral_materials:
        material.emission_enabled = true
        material.emission_energy_multiplier = gain

func audit() -> Dictionary:
    var triangles: int = 0
    var textured_materials: int = 0
    var invalid_normals: int = 0
    var all_materials: Dictionary = {}
    var bounds: AABB = AABB()
    var first: bool = true
    for mesh: MeshInstance3D in meshes:
        triangles += int(float(mesh.mesh.get_faces().size()) / 3.0)
        var box: AABB = mesh.global_transform * mesh.get_aabb()
        bounds = box if first else bounds.merge(box)
        first = false
        for index: int in range(mesh.mesh.get_surface_count()):
            var material: StandardMaterial3D = mesh.get_active_material(index) as StandardMaterial3D
            if material != null:
                all_materials[material.resource_name] = true
                if material.albedo_texture != null:
                    textured_materials += 1
            var arrays: Array = mesh.mesh.surface_get_arrays(index)
            var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
            for normal: Vector3 in normals:
                if normal.length_squared() < 0.5:
                    invalid_normals += 1
    return {"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "mesh_nodes": meshes.size(), "triangles": triangles, "material_count": all_materials.size(), "textured_surfaces": textured_materials, "mineral_pulse_materials": mineral_materials.size(), "invalid_normals": invalid_normals, "bounds_position": [bounds.position.x, bounds.position.y, bounds.position.z], "bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z], "note": "Graphical material and scale proof; no gameplay, collision or moving-cart validation."}
