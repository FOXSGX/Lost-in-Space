extends CharacterBody3D
class_name SpacePlayer3D

const VISUAL_SCENE := preload("res://scenes/protagonist_visual.tscn")
const SPEED := 5.8
const ATTACK_RANGE := 3.75
const ATTACK_INTERVAL := 0.35
var peer_id := 1
var health := 5
var oxygen := 100.0
var warmth := 1.0
var carrying := 0
var downed := false
var scan_lock_remaining := 0.0
var scan_cooldown_remaining := 0.0
var scan_origin := Vector3.ZERO
var _camera: Camera3D
var _target_position := Vector3.ZERO
var _has_target_position := false
var _attack_cooldown := 0.0
var attack_range_visual: MeshInstance3D
var _visual: ProtagonistVisual
var _last_visual_position := Vector3.ZERO

func setup(id: int, color: Color) -> void:
    peer_id = id
    name = "Player3D_%d" % id
    _build_visual(color)

func _enter_tree() -> void:
    set_multiplayer_authority(peer_id)

func _ready() -> void:
    collision_layer = 1
    collision_mask = 2
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.5
    shape.shape = capsule
    shape.position.y = 0.8
    add_child(shape)
    if peer_id == multiplayer.get_unique_id():
        _build_camera()

func _build_visual(color: Color) -> void:
    _visual = VISUAL_SCENE.instantiate() as ProtagonistVisual
    _visual.set_team_color(color)
    add_child(_visual)

func _process(delta: float) -> void:
    if _visual == null:
        return
    var motion := global_position - _last_visual_position
    if is_multiplayer_authority():
        motion = velocity
    elif delta > 0.0:
        motion /= delta
    _last_visual_position = global_position
    _visual.update_state(delta, Vector2(motion.x, motion.z), downed, scan_lock_remaining > 0.0, carrying > 0, health)

func show_attack_animation() -> void:
    if _visual != null:
        _visual.trigger_attack()

func show_rescue_animation(active: bool) -> void:
    if _visual != null:
        _visual.set_rescuing(active)

func _build_camera() -> void:
    _camera = Camera3D.new()
    _camera.name = "OrthographicCamera3D"
    _camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    _camera.size = 19.0
    _camera.position = Vector3(0.0, 16.0, 15.0)
    var controller := get_parent() as Main3D
    if controller != null and controller.ship_active:
        _camera.position.x = -position.x
    _camera.rotation_degrees = Vector3(-46.0, 0.0, 0.0)
    _camera.current = true
    add_child(_camera)
    var light := OmniLight3D.new()
    light.name = "PlayerSensorLight"
    light.omni_range = 8.0
    light.light_energy = 2.6
    light.light_color = Color("#9edfff")
    light.position.y = 2.4
    add_child(light)
    attack_range_visual = MeshInstance3D.new()
    attack_range_visual.name = "AttackRange"
    var ring := TorusMesh.new()
    ring.inner_radius = ATTACK_RANGE - 0.025
    ring.outer_radius = ATTACK_RANGE + 0.025
    ring.rings = 64
    ring.ring_segments = 8
    attack_range_visual.mesh = ring
    attack_range_visual.position.y = 0.075
    var material := _glow_material(Color("#5dd4ea"))
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_color.a = 0.42
    material.emission_energy_multiplier = 0.85
    attack_range_visual.material_override = material
    add_child(attack_range_visual)

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.62
    return material

func _glow_material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = 1.1
    material.roughness = 0.28
    material.metallic = 0.15
    return material

func begin_scan(duration: float, cooldown: float, origin: Vector3) -> void:
    scan_lock_remaining = duration
    scan_cooldown_remaining = cooldown
    scan_origin = origin
    global_position = origin
    velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
    scan_lock_remaining = maxf(scan_lock_remaining - delta, 0.0)
    scan_cooldown_remaining = maxf(scan_cooldown_remaining - delta, 0.0)
    if scan_lock_remaining > 0.0:
        velocity = Vector3.ZERO
        global_position = scan_origin
    if scan_lock_remaining <= 0.0 and not is_multiplayer_authority() and _has_target_position:
        global_position = global_position.lerp(_target_position, 1.0 - exp(-14.0 * delta))
    if not is_multiplayer_authority() or downed:
        return
    _attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
    var controller := get_parent() as Main3D
    if controller == null or (not controller.game_started and not controller.ship_active) or controller.mission_completed or controller.mission_failed:
        return
    if controller.ship_active and controller._screen_view == "route":
        velocity = Vector3.ZERO
        return
    if controller.game_started and Input.is_action_just_pressed("scan"):
        controller.start_scan_for_peer(peer_id)
        return
    var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    var move_speed := SPEED * 0.72 if carrying > 0 else SPEED
    var was_moving := velocity.length() > 0.1
    if scan_lock_remaining <= 0.0:
        velocity = Vector3(input_vector.x * move_speed, 0.0, input_vector.y * move_speed)
        move_and_slide()
        # 移动反馈 - 每隔一段时间生成脚步粒子
        if velocity.length() > 0.1 and Engine.get_physics_frames() % 15 == 0:
            _spawn_footstep_particle()
    global_position.x = clampf(global_position.x, -9.9, 9.9) if controller.ship_active else clampf(global_position.x, -18.0, 18.0)
    global_position.z = clampf(global_position.z, -6.2, 6.2) if controller.ship_active else clampf(global_position.z, -11.0, 11.0)
    if controller.ship_active:
        for ship_action in ["scan", "repair", "pickup", "deposit", "attack", "revive"]:
            if Input.is_action_just_pressed(ship_action):
                controller.handle_ship_action(peer_id, ship_action)
        if Engine.get_physics_frames() % 2 == 0:
            sync_transform.rpc(global_position)
        return
    for action in ["repair", "pickup", "deposit", "revive"]:
        if Input.is_action_just_pressed(action):
            controller.handle_action(peer_id, action)
    if Input.is_action_pressed("attack") and _attack_cooldown <= 0.0 and scan_lock_remaining <= 0.0:
        _attack_cooldown = ATTACK_INTERVAL
        controller.attack_from_peer(peer_id)
    if Engine.get_physics_frames() % 2 == 0:
        sync_transform.rpc(global_position)

func _spawn_footstep_particle() -> void:
    var particle := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = 0.05
    mesh.height = 0.1
    particle.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.7, 0.9, 0.6)
    mat.emission_enabled = true
    mat.emission = Color(0.4, 0.7, 0.9)
    mat.emission_energy_multiplier = 0.8
    particle.material_override = mat
    particle.global_position = global_position + Vector3(randf_range(-0.15, 0.15), 0.05, randf_range(-0.15, 0.15))
    get_parent().add_child(particle)
    var tween := particle.create_tween()
    tween.set_parallel(true)
    tween.tween_property(particle, "global_position:y", -0.2, 0.3)
    tween.tween_property(particle, "scale", Vector3.ZERO, 0.3)
    tween.finished.connect(func():
        if is_instance_valid(particle):
            particle.queue_free()
    )

@rpc("authority", "unreliable_ordered", "call_remote")
func sync_transform(next_position: Vector3) -> void:
    if is_multiplayer_authority() or downed or scan_lock_remaining > 0.0:
        return
    if multiplayer.is_server():
        global_position = next_position
        return
    _target_position = next_position
    _has_target_position = true

