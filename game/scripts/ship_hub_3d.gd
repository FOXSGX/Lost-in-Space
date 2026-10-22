extends Node3D
class_name ShipHub3D

const MODEL := preload("res://assets/ship-hub/ship_hub_blender_v2.glb")
const KENNEY_ART: Script = preload("res://scripts/ship_hub_kenney_art.gd")
const DEVICES: Script = preload("res://scripts/ship_devices_3d.gd")
# 42 x 33 m hull, with the equipment kept at human scale.
const WALK_BOUNDS := Vector2(19.8, 15.3)
const CAMERA_SIZE := 14.0
const CAMERA_OFFSET := Vector3(0, 12.8, 14.8)
const COCKPIT := Vector3(6.2, 0.0, -12.32)
const STORAGE := Vector3(-16.0, 0.0, 4.45)
const REPAIR := Vector3(16.6, 0.0, -2.98)
const SUPPLY := Vector3(16.75, 0.0, 10.18)
const MISSION := Vector3(-16.7, 0.0, -9.5)
const AIRLOCK := Vector3(0.0, 0.0, 14.15)


func _ready() -> void:
    var model := MODEL.instantiate() as Node3D
    model.name = "ShipHubModel"
    add_child(model)
    # 第一人称保留气闸门和门框，观察窗继续使用程序星空材质。
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        var mesh_name := String(mesh.name)
        if mesh_name.contains("panorama_glass"):
            mesh.material_override = _space_window()
        if mesh_name.begins_with("Deck_") or mesh_name.contains("central_deck"):
            mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#253d50")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#dbeaf1")
    env.ambient_light_energy = 0.36
    env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.environment = env
    add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -28, 0)
    sun.light_color = Color("#fff0dc")
    sun.light_energy = 0.25
    sun.shadow_enabled = true
    add_child(sun)
    _build_first_person_interior()
    var kenney_art: Node3D = KENNEY_ART.new() as Node3D
    kenney_art.name = "KenneyInterior"
    add_child(kenney_art)
    kenney_art.build(model)
    _solid("DeckCollision", Vector3(40.5, 0.22, 32.4), Vector3(0, -0.12, 0))
    _solid("LeftHullCollision", Vector3(0.44, 2.3, 26.4), Vector3(-20.34, 1.15, 0))
    _solid("RightHullCollision", Vector3(0.44, 1.1, 26.4), Vector3(20.34, 0.55, 0))
    _solid("ForwardHullCollision", Vector3(35.7, 2.7, 0.42), Vector3(0, 1.35, -15.9))
    _solid("NearLeftCollision", Vector3(9.9, 1.04, 0.5), Vector3(-12.9, 0.52, 15.9))
    _solid("NearRightCollision", Vector3(9.9, 1.04, 0.5), Vector3(12.9, 0.52, 15.9))
    for side_x in [-1, 1]:
        for side_z in [-1, 1]:
            var corner := _solid("CornerHull", Vector3(0.6, 1.1, 4.67), Vector3(side_x * 19.35, 0.55, side_z * 14.85))
            corner.rotation_degrees.y = -45.0 * side_x * side_z
    _solid("BridgeCollision", Vector3(15.8, 0.66, 2.95), Vector3(0, 0.27, -14.38))
    _solid("CargoShelvesCollision", Vector3(1.45, 1.8, 6.15), Vector3(-18.3, 0.9, 4.5))
    _solid("CargoCrateOneCollision", Vector3(0.86, 0.66, 0.84), Vector3(-16.88, 0.33, 3.4))
    _solid("CargoCrateTwoCollision", Vector3(0.86, 0.66, 0.84), Vector3(-16.88, 0.33, 5.45))
    _solid("RepairBenchCollision", Vector3(2.15, 1.04, 1.09), Vector3(18.08, 0.52, -2.98))
    _solid("RechargeCollision", Vector3(0.96, 1.8, 0.96), Vector3(18.51, 0.9, 10.26))
    _solid("RechargeControlCollision", Vector3(0.4, 1.03, 0.42), Vector3(17.37, 0.515, 10.25))
    _solid("MissionTerminalCollision", Vector3(0.55, 1.15, 0.6), Vector3(-17.53, 0.57, -10.09))
    _solid("StarMapCollision", Vector3(2.9, 1.1, 2.9), Vector3(0, 0.55, -0.34))
    for side in [-1, 1]:
        for seat_z in [5.2, -4.8]:
            _solid("CrewBench", Vector3(3.35, 1.35, 1.15), Vector3(side * 8.7, 0.675, seat_z))
        _solid("Planter", Vector3(1.16, 1.0, 1.16), Vector3(side * 11.7, 0.5, 0.7))
        _solid("SideTable", Vector3(1.1, 0.8, 1.1), Vector3(side * 11.3, 0.4, 5.2))
    _deck_label("归 航 号", Vector3(0, 0.03, 10.4), 58, Color("#dae6db"))
    _deck_label("01  舰 桥", Vector3(0, 0.03, -10.6), 36, Color("#c1e1d6"))
    _deck_label("02  储 物", Vector3(-14.8, 0.03, 4.45), 36, Color("#eed6ad"), 90.0)
    _deck_label("03  维 修", Vector3(15.1, 0.03, -2.98), 36, Color("#eed6ad"), -90.0)
    _deck_label("04  补 给", Vector3(15.3, 0.03, 10.18), 36, Color("#c1e1d6"), -90.0)
    _deck_label("05  任 务 记 录", Vector3(-15.2, 0.03, -9.5), 36, Color("#c4acff"), 90.0)
    _deck_label("06  训 练 舱", Vector3(0, 0.03, 12.9), 36, Color("#8de3b3"), 180.0)
    var devices: Node3D = DEVICES.new() as Node3D
    devices.name = "ShipDevices"
    add_child(devices)
    for index: int in 4:
        _deck_label("驾驶 %02d" % (index + 1), Vector3(ShipDevices3D.PILOT_X[index], 0.03, -11.8), 28, Color("#c1e1d6"))

func _build_first_person_interior() -> void:
    # Close the presentation model's cutaway above the existing walkable deck.
    var shell: StandardMaterial3D = StandardMaterial3D.new()
    shell.albedo_color = Color("#c4d2d0")
    shell.roughness = 0.84
    var trim: StandardMaterial3D = StandardMaterial3D.new()
    trim.albedo_color = Color("#375967")
    trim.roughness = 0.65
    var lamp: StandardMaterial3D = StandardMaterial3D.new()
    lamp.albedo_color = Color("#f6e6c6")
    lamp.emission_enabled = true
    lamp.emission = Color("#f6e6c6")
    lamp.emission_energy_multiplier = 0.8
    _interior_box("FirstPersonCeiling", Vector3(14.0, 0.18, 32.5), Vector3(0, 4.85, 0), trim)
    for end: int in [-1, 1]:
        _interior_box("RaisedHullEndCap", Vector3(16.0, 1.6, 0.2), Vector3(0, 4.1, end * 15.85), trim)
    for side: int in [-1, 1]:
        _interior_box("ServiceBayCeiling", Vector3(13.0, 0.16, 32.5), Vector3(side * 14.1, 3.5, 0), shell)
        var shoulder: MeshInstance3D = _interior_box("SlopedCeilingShoulder", Vector3(2.3, 0.18, 32.5), Vector3(side * 7.05, 4.15, 0), shell)
        shoulder.rotation_degrees.z = side * -45.0
        _interior_box("UpperSideHull", Vector3(0.18, 2.75, 26.4), Vector3(side * 20.34, 2.08, 0), shell)
        for end: int in [-1, 1]:
            var corner: MeshInstance3D = _interior_box("UpperCornerHull", Vector3(0.6, 2.75, 4.67), Vector3(side * 19.35, 2.08, end * 14.85), shell)
            corner.rotation_degrees.y = -45.0 * side * end
    _interior_box("AftPressureBulkhead", Vector3(35.7, 3.45, 0.18), Vector3(0, 1.72, 15.95), shell)
    _interior_box("ForwardUpperHull", Vector3(35.7, 0.75, 0.18), Vector3(0, 3.07, -15.95), shell)
    for x: float in [-12.0, 12.0]:
        _interior_box("CeilingRib", Vector3(0.14, 0.14, 31.0), Vector3(x, 3.36, 0), trim)
    for x: float in [-10.0, 10.0]:
        for z: float in [-10.0, 0.0, 10.0]:
            _interior_box("CeilingLuminaire", Vector3(2.8, 0.06, 0.35), Vector3(x, 3.34, z), lamp)
            var light: OmniLight3D = OmniLight3D.new()
            light.name = "InteriorCeilingLight"
            light.position = Vector3(x, 2.95, z)
            light.light_color = Color("#f5eddc")
            light.light_energy = 1.25
            light.omni_range = 11.0
            add_child(light)

func _interior_box(node_name: String, size: Vector3, center: Vector3, material: Material) -> MeshInstance3D:
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = center
    instance.material_override = material
    if node_name in ["FirstPersonCeiling", "RaisedHullEndCap", "ServiceBayCeiling", "SlopedCeilingShoulder", "UpperSideHull", "UpperCornerHull", "AftPressureBulkhead", "ForwardUpperHull"]:
        var body: StaticBody3D = StaticBody3D.new()
        body.name = node_name + "Collision"
        body.collision_layer = 2
        body.collision_mask = 0
        var collider: CollisionShape3D = CollisionShape3D.new()
        var shape: BoxShape3D = BoxShape3D.new()
        shape.size = size
        collider.shape = shape
        body.add_child(collider)
        instance.add_child(body)
    add_child(instance)
    return instance

func _solid(node_name: String, size: Vector3, center: Vector3) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = node_name
    body.collision_layer = 2
    body.collision_mask = 0
    body.position = center
    add_child(body)
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    return body

func _deck_label(message: String, point: Vector3, font_size: int, color: Color, yaw_degrees: float = 0.0) -> void:
    var label: Label3D = Label3D.new()
    label.name = "DeckSign"
    label.text = message
    label.position = point
    label.rotation_degrees = Vector3(-90.0, yaw_degrees, 0.0)
    label.font_size = font_size
    label.pixel_size = 0.015
    label.modulate = color
    label.outline_size = 0
    add_child(label)

func _space_window() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 local_pos;
float hash(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void vertex(){ local_pos=VERTEX; }
void fragment(){
    vec2 p=vec2(local_pos.x/22.95+0.5,(local_pos.y-1.94)/1.3+0.5);
    vec3 sky=mix(vec3(0.06,0.12,0.23),vec3(0.20,0.37,0.48),clamp(p.y,0.0,1.0));
    float cloud=exp(-pow((p.y-0.30-sin(p.x*7.0)*0.15)*6.0,2.0));
    sky+=cloud*vec3(0.04,0.09,0.09);
    vec2 grid=p*vec2(160.0,8.0);
    float star=step(0.965,hash(floor(grid)))*(1.0-smoothstep(0.03,0.13,length(fract(grid)-0.5)));
    sky+=star*vec3(0.64,0.72,0.66);
    vec2 planet=(p-vec2(0.76,0.52))*vec2(17.65,1.0);
    float d=length(planet);
    float disk=1.0-smoothstep(0.17,0.18,d);
    vec3 surface=mix(vec3(0.37,0.64,0.68),vec3(0.79,0.87,0.71),smoothstep(-0.04,0.05,sin(planet.y*57.0+planet.x*17.0)*0.06));
    sky=mix(sky,surface*(0.7+0.3*clamp(planet.x/0.18+0.5,0.0,1.0)),disk);
    sky+=exp(-pow((d-0.185)*70.0,2.0))*vec3(0.05,0.11,0.13);
    ALBEDO=sky;
}"""
    var material := ShaderMaterial.new()
    material.shader = shader
    return material
