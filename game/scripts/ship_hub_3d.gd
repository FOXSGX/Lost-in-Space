extends Node3D
class_name ShipHub3D

const MODEL := preload("res://assets/ship-hub/ship_hub.glb")
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
    # 游戏镜头从 +Z 看入舱室，切掉近侧门扇和门楣以免遮住船员。
    for mesh in model.find_children("*", "MeshInstance3D", true, false):
        var mesh_name := String(mesh.name)
        if mesh_name.contains("Airlock") and (mesh_name.contains("door") or mesh_name.contains("top_lintel") or mesh_name.contains("pillar")):
            mesh.visible = false
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
    env.ambient_light_energy = 0.32
    env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.environment = env
    add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -28, 0)
    sun.light_color = Color("#fff0dc")
    sun.light_energy = 0.45
    sun.shadow_enabled = true
    add_child(sun)
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
    _marker("驾驶台", COCKPIT, Color("#67e4e9"))
    _marker("储物架", STORAGE, Color("#f3bb70"))
    _marker("训练舱", AIRLOCK, Color("#8de3b3"))
    _marker("维修台", REPAIR, Color("#ffc474"))
    _marker("补给柱", SUPPLY, Color("#82efc1"))
    _marker("任务记录", MISSION, Color("#c4acff"))
    _deck_label("归 航 号", Vector3(0, 0.03, 10.4), 58, Color("#dae6db"))
    _deck_label("01  舰 桥", Vector3(0, 0.03, -10.6), 36, Color("#c1e1d6"))
    _deck_label("02  储 物", Vector3(-15.8, 0.03, 7.5), 32, Color("#eed6ad"))
    _deck_label("03  维 修", Vector3(16.4, 0.03, -0.3), 32, Color("#eed6ad"))
    _deck_label("04  补 给", Vector3(16.3, 0.03, 12.6), 32, Color("#c1e1d6"))

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

func _marker(message: String, point: Vector3, color: Color) -> void:
    var label := Label3D.new()
    label.text = message
    label.position = point + Vector3(0, 2.8, 0)
    label.font_size = 28
    label.pixel_size = 0.012
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = color
    label.outline_size = 3
    add_child(label)

func _deck_label(message: String, point: Vector3, font_size: int, color: Color) -> void:
    var label := Label3D.new()
    label.text = message
    label.position = point
    label.rotation_degrees.x = -90
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
