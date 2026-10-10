extends CharacterBody3D
class_name SpaceEnemy3D

var enemy_id := 0
var health := 3
var max_health := 3
var move_speed := 1.8
var attack_damage := 1
var attack_timer := 0.0
var _target_position := Vector3.ZERO
var _has_target_position := false

func setup(id: int, player_count: int = 1) -> void:
    enemy_id = id
    name = "Enemy3D_%d" % id
    max_health = 3 + maxi((player_count - 1) / 2, 0)
    health = max_health
    move_speed = 1.8 + maxi(player_count - 1, 0) * 0.12
    attack_damage = 2 if player_count >= 4 else 1
    _build_visual()

func _enter_tree() -> void:
    set_multiplayer_authority(1)

func _ready() -> void:
    collision_layer = 1
    collision_mask = 2
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.45
    capsule.height = 1.0
    shape.shape = capsule
    shape.position.y = 0.58
    add_child(shape)

func _build_visual() -> void:
    var body := MeshInstance3D.new()
    var mesh := CapsuleMesh.new()
    mesh.radius = 0.43
    mesh.height = 0.9
    body.position.y = 0.62
    body.mesh = mesh
    body.material_override = _material(Color("#ff5a62"))
    body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(body)
    var eye := MeshInstance3D.new()
    var eye_mesh := SphereMesh.new()
    eye_mesh.radius = 0.14
    eye_mesh.height = 0.28
    eye.position = Vector3(0.0, 0.85, -0.38)
    eye.mesh = eye_mesh
    eye.material_override = _glow_material(Color("#ffea5c"))
    add_child(eye)
    for side in [-1.0, 1.0]:
        var horn := MeshInstance3D.new()
        var horn_mesh := CylinderMesh.new()
        horn_mesh.top_radius = 0.02
        horn_mesh.bottom_radius = 0.12
        horn_mesh.height = 0.38
        horn_mesh.radial_segments = 6
        horn.position = Vector3(side * 0.28, 1.08, 0.0)
        horn.rotation_degrees = Vector3(0.0, 0.0, side * -24.0)
        horn.mesh = horn_mesh
        horn.material_override = _material(Color("#b8414e"))
        add_child(horn)
    var warning_ring := MeshInstance3D.new()
    var ring_mesh := TorusMesh.new()
    ring_mesh.inner_radius = 0.62
    ring_mesh.outer_radius = 0.68
    ring_mesh.rings = 20
    ring_mesh.ring_segments = 8
    warning_ring.position.y = 0.08
    warning_ring.mesh = ring_mesh
    warning_ring.material_override = _glow_material(Color("#ff4858"))
    add_child(warning_ring)
    var danger_light := OmniLight3D.new()
    danger_light.name = "EnemyGlow"
    danger_light.light_color = Color("#ff5563")
    danger_light.light_energy = 1.8
    danger_light.omni_range = 3.2
    danger_light.position.y = 0.8
    add_child(danger_light)
    var label := Label3D.new()
    label.text = "【敌人】\n空格攻击"
    label.position = Vector3(0.0, 1.85, 0.0)
    label.font_size = 46
    label.pixel_size = 0.011
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = Color("#ffe8a6")
    label.outline_size = 10
    label.outline_modulate = Color("#4a0a0f")
    label.shaded = false
    add_child(label)

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.8
    return material

func _glow_material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = 1.4
    material.roughness = 0.38
    return material

func server_tick(delta: float, players: Dictionary) -> Dictionary:
    if players.is_empty():
        return {"sync": false}
    var nearest: SpacePlayer3D
    var nearest_distance := INF
    for value in players.values():
        var player := value as SpacePlayer3D
        if player == null or player.downed:
            continue
        var distance := global_position.distance_to(player.global_position)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest = player
    if nearest == null:
        velocity = Vector3.ZERO
        return {"sync": false}
    var direction := nearest.global_position - global_position
    direction.y = 0.0
    if nearest_distance > 1.15:
        velocity = direction.normalized() * move_speed
        move_and_slide()
    else:
        velocity = Vector3.ZERO
        attack_timer -= delta
        if attack_timer <= 0.0:
            attack_timer = 1.0
            var controller := get_parent() as Main3D
            if controller != null:
                controller.damage_player(nearest.peer_id, attack_damage)
    if Engine.get_physics_frames() % 2 == 0:
        sync_transform.rpc(global_position)
        return {"sync": true}
    return {"sync": false}

func take_damage(amount: int) -> bool:
    health = maxi(health - amount, 0)
    return health <= 0

@rpc("authority", "unreliable_ordered", "call_remote")
func sync_transform(next_position: Vector3) -> void:
    if multiplayer.is_server():
        return
    _target_position = next_position
    _has_target_position = true

func _process(delta: float) -> void:
    if not multiplayer.is_server() and _has_target_position:
        global_position = global_position.lerp(_target_position, 1.0 - exp(-12.0 * delta))
