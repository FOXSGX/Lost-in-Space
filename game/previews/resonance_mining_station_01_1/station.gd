extends Node3D

var player: CharacterBody3D
var reference_camera: Camera3D
var manifest: Dictionary = {}
var profiles: Dictionary = {}
var model: Node3D
var meshes: Array[MeshInstance3D] = []
var mineral_meshes: Array[MeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var mineral_materials: Array[ShaderMaterial] = []
var runtime_lights: Array[OmniLight3D] = []
var loaded: bool = false
var title: Label
var phase: float = 0.0
var pulse_enabled: bool = true
var realtime_enabled: bool = true
var collision_triangles: int = 0
var camera_max_distance: float = 7.5

func clamp_cave_camera_position(target: Vector3,desired: Vector3) -> Vector3:
    var delta: Vector3=desired-target
    # Contract the boom before entering the narrow bent galleries, rather than
    # waiting for the camera center to hit their walls. Smooth transition.
    var gallery_weight: float=smoothstep(7.5,9.0,absf(target.x))
    var local_max: float=lerpf(camera_max_distance,3.2,gallery_weight)
    if delta.length()>local_max:delta=delta.normalized()*local_max
    var result: Vector3=target+delta
    result.y=clampf(result.y,1.1,5.75)
    return result

func _ready() -> void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/station_manifest.json")) as Dictionary
    profiles = JSON.parse_string(FileAccess.get_file_as_string("res://assets/material_profiles.json")) as Dictionary
    model = (load("res://assets/mining_station_01_1.glb") as PackedScene).instantiate() as Node3D
    add_child(model)
    _adapt_materials(model, {})
    _colliders()
    var environment: Environment = Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.015, 0.025, 0.04)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.56, 0.63, 0.72)
    environment.ambient_light_energy = 0.30
    environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
    # Static surfaces use the source AgX LUT; native Compatibility tonemapping
    # is left linear rather than claiming its Filmic switch provides HDR.
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    var world: WorldEnvironment = WorldEnvironment.new()
    world.environment = environment
    add_child(world)
    _light(Vector3(-5.2,4.05,-.85), Color(1,.78,.55),1.2,8,true)
    _light(Vector3(2,4.35,-.65), Color(1,.78,.55),1.3,8.5,true)
    _light(Vector3(8,4.1,.1), Color(1,.78,.55),.85,7,true)
    _light(Vector3(-.6,3.7,3.2), Color(.68,.82,1),.6,10,false)
    _light(Vector3(4.5,2.5,-4), Color(.12,.64,1),.45,4.2,false)
    _light(Vector3(-12.3,2.5,-1.5), Color(.61,.79,1),.6,7,false)
    _light(Vector3(14.5,2.2,-.8), Color(.12,.54,.72),.5,6,false)
    _inputs()
    player = (load("res://scripts/station_player.gd") as Script).new() as CharacterBody3D
    player.position = Vector3(-10.8, 0.1, -1.8)
    add_child(player)
    reference_camera = Camera3D.new()
    reference_camera.near = 0.04
    reference_camera.far = 100
    add_child(reference_camera)
    var canvas: CanvasLayer = CanvasLayer.new()
    add_child(canvas)
    title = Label.new()
    title.position = Vector2(16,14)
    title.add_theme_font_size_override("font_size",17)
    title.add_theme_color_override("font_shadow_color",Color.BLACK)
    title.add_theme_constant_override("shadow_offset_x",2)
    title.add_theme_constant_override("shadow_offset_y",2)
    title.text = "PROTOTYPE 01.1 | WASD/Shift | click: look | Esc: release | Tab: close | F1-F4: reference | F5: walk"
    canvas.add_child(title)
    loaded = true

func _adapt_materials(node: Node, cache: Dictionary) -> void:
    if node is MeshInstance3D:
        var mesh: MeshInstance3D = node as MeshInstance3D
        meshes.append(mesh)
        var source: Material = mesh.get_active_material(0)
        var key: String = source.resource_name.trim_prefix("P11_")
        if not cache.has(key):
            var data: Dictionary = profiles[key] as Dictionary
            var material: ShaderMaterial = ShaderMaterial.new()
            material.shader = load("res://static_surface.gdshader") as Shader
            material.set_shader_parameter("agx_lut",load("res://assets/agx_medium_high.png"))
            material.set_shader_parameter("metallic",float(data["metallic"]))
            material.set_shader_parameter("roughness",float(data["roughness"]))
            material.set_shader_parameter("sourced_roughness",bool((profiles["__encoding__"] as Dictionary).get("vertex_roughness",false)))
            material.set_shader_parameter("irradiance_scale",float((profiles["__encoding__"] as Dictionary)["irradiance_scale"]))
            material.set_shader_parameter("log_irradiance",bool((profiles["__encoding__"] as Dictionary).get("log_encoding",false)))
            if str(data["family"]) == "mineral":
                material.set_shader_parameter("emission_tint",Vector3.ONE)
                material.set_shader_parameter("emission_gain",0.18)
                mineral_materials.append(material)
            elif "energy" in key.to_lower() or "lamp" in key.to_lower() or "screen" in key.to_lower() or "axial" in key.to_lower():
                material.set_shader_parameter("emission_tint",Vector3.ONE)
                material.set_shader_parameter("emission_gain",maxf(0.15,minf(float(data["emission_strength"]),3.0)))
            if "worn mineral composite deck" in key:
                material.set_shader_parameter("panel_variation",0.10)
            cache[key] = material
            materials.append(material)
        mesh.material_override = cache[key] as ShaderMaterial
        if str((profiles[key] as Dictionary)["family"]) == "mineral" or "exposed axial" in key:
            mineral_meshes.append(mesh)
    for child: Node in node.get_children():
        _adapt_materials(child,cache)

func _colliders() -> void:
    var collision: Node3D = (load("res://assets/station_collision.glb") as PackedScene).instantiate() as Node3D
    for child: Node in collision.find_children("*","MeshInstance3D",true,false):
        var mesh: MeshInstance3D = child as MeshInstance3D
        var shape: ConcavePolygonShape3D = mesh.mesh.create_trimesh_shape()
        shape.backface_collision = true
        var body: StaticBody3D = StaticBody3D.new()
        body.name = str(mesh.name)
        body.collision_layer = 6
        body.collision_mask = 0
        var collider: CollisionShape3D = CollisionShape3D.new()
        collider.shape = shape
        body.add_child(collider)
        add_child(body)
        body.transform = mesh.transform
        collision_triangles += int(float(mesh.mesh.get_faces().size())/3.0)
    collision.free()

func _light(at: Vector3,color: Color,energy: float,radius: float,shadow: bool) -> void:
    var light: OmniLight3D = OmniLight3D.new()
    light.position=at
    light.light_color=color
    light.light_energy=energy
    light.omni_range=radius
    light.shadow_enabled=shadow
    runtime_lights.append(light)
    add_child(light)

func _inputs() -> void:
    if not InputMap.has_action("move_left"):InputMap.add_action("move_left")
    if not InputMap.has_action("move_right"):InputMap.add_action("move_right")
    if not InputMap.has_action("move_up"):InputMap.add_action("move_up")
    if not InputMap.has_action("move_down"):InputMap.add_action("move_down")
    if not InputMap.has_action("sprint"):InputMap.add_action("sprint")
    if not InputMap.has_action("release_mouse"):InputMap.add_action("release_mouse")
    if not InputMap.has_action("inspect_first_person"):InputMap.add_action("inspect_first_person")
    var map: Dictionary = {"move_left":KEY_A,"move_right":KEY_D,"move_up":KEY_W,"move_down":KEY_S,"sprint":KEY_SHIFT,"release_mouse":KEY_ESCAPE,"inspect_first_person":KEY_TAB}
    for action: String in map:
        InputMap.action_set_deadzone(action,0.5)
        var key: InputEventKey = InputEventKey.new()
        key.physical_keycode = int(map[action]) as Key
        InputMap.action_add_event(action,key)
    if not InputMap.has_action("capture_mouse"):InputMap.add_action("capture_mouse")
    var click: InputEventMouseButton=InputEventMouseButton.new()
    click.button_index=MOUSE_BUTTON_LEFT
    InputMap.action_add_event("capture_mouse",click)

func set_reference_view(view: String) -> void:
    player.set("paused",true)
    (player.get("visual") as Node3D).visible=false
    var data: Dictionary=(manifest["cameras"] as Dictionary)["PLAYER · "+view] as Dictionary
    var at: Array=data["position"] as Array
    var direction: Array=data["direction"] as Array
    var p: Vector3=Vector3(float(at[0]),float(at[1]),float(at[2]))
    reference_camera.look_at_from_position(p,p+Vector3(float(direction[0]),float(direction[1]),float(direction[2])),Vector3.UP)
    reference_camera.fov=float(data["fov_vertical"])
    reference_camera.current=true

func resume_player() -> void:
    player.set("paused",false)
    (player.get("visual") as Node3D).visible=true
    (player.get("camera") as Camera3D).current=true

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.is_pressed() and not event.is_echo():
        var code: Key=(event as InputEventKey).keycode
        if code>=KEY_F1 and code<=KEY_F4:
            set_reference_view(["A_entry","B_cart_side","C_mineral","D_return"][int(code)-int(KEY_F1)])
        elif code==KEY_F5:resume_player()

func set_realtime(enabled: bool) -> void:
    realtime_enabled=enabled
    for light: OmniLight3D in runtime_lights:light.visible=enabled
    for material: ShaderMaterial in materials:material.set_shader_parameter("specular_gain",0.32 if enabled else 0.0)

func _process(delta: float) -> void:
    phase+=delta
    var gain: float=0.18+0.045*sin(phase*1.7) if pulse_enabled else 0.18
    for material: ShaderMaterial in mineral_materials:material.set_shader_parameter("emission_gain",gain)
