extends CharacterBody3D
class_name SpacePlayer3D

const VISUAL_SCENE := preload("res://scenes/protagonist_visual.tscn")
const SPEED := 5.8
const SPRINT_MULTIPLIER := 1.65
const ATTACK_RANGE := 3.75
const ATTACK_INTERVAL := 0.35
var peer_id := 1
var health := 5
var oxygen := 100.0
var warmth := 1.0
var carrying := 0
var carrying_id := 0
var sprinting := false
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
var _camera_shake_remaining := 0.0
var _camera_shake_duration := 0.0
var _camera_shake_strength := 0.0
var _camera_shake_clock := 0.0
var _camera_shake_offset := Vector3.ZERO
var _camera_shake_rotation := 0.0

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
    _remove_camera_shake_offset()
    var motion := velocity if is_multiplayer_authority() else (global_position - _last_visual_position) / maxf(delta, 0.001)
    _last_visual_position = global_position
    if _visual != null:
        _visual.update_state(delta, Vector2(motion.x, motion.z), downed, scan_lock_remaining > 0.0, carrying > 0, health)
    var controller := get_parent() as Main3D
    if controller != null and controller.ship_active and _camera != null:
        if controller._ship_session.in_hub:
            # Keep the character near the centre while revealing the next cabin section.
            _camera.global_position = _camera.global_position.lerp(global_position + ShipHub3D.CAMERA_OFFSET, 1.0 - exp(-8.0 * delta))
            _camera.rotation_degrees = Vector3(-42, 0, 0)
        else:
            _camera.global_position = Vector3(0, 16, 15)
            _camera.look_at(Vector3(0, 0.6, 0), Vector3.UP)
    _apply_camera_shake(delta)

func trigger_camera_shake(strength: float = 0.08, duration: float = 0.12) -> void:
    if _camera == null:
        return
    _camera_shake_strength = maxf(_camera_shake_strength, strength)
    _camera_shake_duration = maxf(_camera_shake_duration, duration)
    _camera_shake_remaining = maxf(_camera_shake_remaining, duration)

func _apply_camera_shake(delta: float) -> void:
    if _camera == null:
        return
    if _camera_shake_remaining <= 0.0:
        return
    _camera_shake_clock += delta
    _camera_shake_remaining = maxf(_camera_shake_remaining - delta, 0.0)
    var fade := clampf(_camera_shake_remaining / maxf(_camera_shake_duration, 0.001), 0.0, 1.0)
    var wave := _camera_shake_clock * 52.0
    var offset := Vector3(sin(wave) * _camera_shake_strength, cos(wave * 1.37) * _camera_shake_strength * 0.55, 0.0) * fade
    var rotation_offset := sin(wave * 0.72) * _camera_shake_strength * 3.0 * fade
    _camera.global_position += offset
    _camera.rotation_degrees.z += rotation_offset
    _camera_shake_offset = offset
    _camera_shake_rotation = rotation_offset

func _remove_camera_shake_offset() -> void:
    if _camera == null:
        return
    _camera.global_position -= _camera_shake_offset
    _camera.rotation_degrees.z -= _camera_shake_rotation
    _camera_shake_offset = Vector3.ZERO
    _camera_shake_rotation = 0.0

func show_attack_animation() -> void:
    if _visual != null:
        _visual.trigger_attack()

func show_rescue_animation(enabled: bool) -> void:
    if _visual != null:
        _visual.set_rescuing(enabled)

func teleport_to(point: Vector3) -> void:
    _remove_camera_shake_offset()
    position = point
    _target_position = point
    _has_target_position = false
    velocity = Vector3.ZERO
    _last_visual_position = point
    _camera_shake_remaining = 0.0
    _camera_shake_duration = 0.0
    _camera_shake_strength = 0.0
    _camera_shake_clock = 0.0

func configure_ship_camera() -> void:
    var controller := get_parent() as Main3D
    _remove_camera_shake_offset()
    if _camera != null and controller != null and controller.ship_active:
        _camera.size = ShipHub3D.CAMERA_SIZE if controller._ship_session.in_hub else 21.0
        _camera.global_position = global_position + ShipHub3D.CAMERA_OFFSET if controller._ship_session.in_hub else Vector3(0, 16, 15)
        _camera.rotation_degrees = Vector3(-42, 0, 0) if controller._ship_session.in_hub else Vector3(-46, 0, 0)
        var sensor := get_node_or_null("PlayerSensorLight") as OmniLight3D
        if sensor != null:
            sensor.light_energy = 0.18
            sensor.omni_range = 5.0
    if attack_range_visual != null:
        attack_range_visual.visible = controller != null and not controller.ship_active

func _build_camera() -> void:
    _camera = Camera3D.new()
    _camera.name = "OrthographicCamera3D"
    _camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    _camera.size = 28.0
    _camera.position = Vector3(0.0, 16.0, 15.0)
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
    configure_ship_camera()

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

func begin_scan(startup: float, cooldown: float, origin: Vector3) -> void:
    scan_lock_remaining = startup
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
    if controller.ship_active:
        _tick_ship(controller)
        return
    if controller.minigame_active and controller.minigame_peer_id == peer_id:
        sprinting = false
        velocity = Vector3.ZERO
        return
    if controller.is_journal_visible():
        sprinting = false
        velocity = Vector3.ZERO
        return
    if Input.is_action_just_pressed("scan"):
        controller.start_scan_for_peer(peer_id)
        return
    var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    sprinting = Input.is_action_pressed("sprint")
    var move_speed := SPEED * (SPRINT_MULTIPLIER if sprinting else 1.0)
    if carrying == 1:
        move_speed *= 0.72
    elif carrying == 2:
        move_speed *= 0.58
    if controller.storm_active:
        move_speed *= 0.68
    var was_moving := velocity.length() > 0.1
    if scan_lock_remaining <= 0.0:
        velocity = Vector3(input_vector.x * move_speed, 0.0, input_vector.y * move_speed)
        move_and_slide()
        # 移动反馈 - 每隔一段时间生成脚步粒子
        if velocity.length() > 0.1 and Engine.get_physics_frames() % 15 == 0:
            _spawn_footstep_particle()
    var map_half := controller.MAP_SIZE * 0.5 - Vector2(1.0, 1.0)
    global_position.x = clampf(global_position.x, -map_half.x, map_half.x)
    global_position.z = clampf(global_position.z, -map_half.y, map_half.y)
    for action in ["repair", "pickup", "drop", "deposit", "revive"]:
        if Input.is_action_just_pressed(action):
            controller.handle_action(peer_id, action)
    for action in ["signal_high", "signal_low"]:
        if Input.is_action_just_pressed(action):
            controller.handle_action(peer_id, action)
    if Input.is_action_pressed("attack") and _attack_cooldown <= 0.0 and scan_lock_remaining <= 0.0:
        _attack_cooldown = ATTACK_INTERVAL
        controller.attack_from_peer(peer_id)
    if Engine.get_physics_frames() % 2 == 0:
        sync_transform.rpc(global_position, sprinting)

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
    get_parent().add_child(particle)
    particle.global_position = global_position + Vector3(randf_range(-0.15, 0.15), 0.05, randf_range(-0.15, 0.15))
    var tween := particle.create_tween()
    tween.set_parallel(true)
    tween.tween_property(particle, "global_position:y", -0.2, 0.3)
    tween.tween_property(particle, "scale", Vector3.ZERO, 0.3)
    tween.finished.connect(func(): particle.queue_free())

@rpc("authority", "unreliable_ordered", "call_remote")
func sync_transform(next_position: Vector3, next_sprinting: bool = false) -> void:
    sprinting = next_sprinting
    if is_multiplayer_authority() or downed or scan_lock_remaining > 0.0:
        return
    if multiplayer.is_server():
        global_position = next_position
        return
    _target_position = next_position
    _has_target_position = true

func _tick_ship(controller: Main3D) -> void:
    var ship := controller._ship_session
    if ship.has_panel():
        velocity = Vector3.ZERO
        return
    var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    sprinting = Input.is_action_pressed("sprint")
    var move_speed := SPEED * (SPRINT_MULTIPLIER if sprinting else 1.0)
    velocity = Vector3(movement.x * move_speed, 0, movement.y * move_speed)
    move_and_slide()
    var bounds := ShipHub3D.WALK_BOUNDS if ship.in_hub else Vector2(9.9, 6.2)
    global_position.x = clampf(global_position.x, -bounds.x, bounds.x)
    global_position.z = clampf(global_position.z, -bounds.y, bounds.y)
    if Input.is_action_just_pressed("repair"):
        ship.request("interact")
    if not ship.in_hub:
        for action in ["scan", "repair", "pickup", "drop", "deposit", "attack", "revive"]:
            if Input.is_action_just_pressed(action):
                ship.request("train_" + action)
    if Engine.get_physics_frames() % 2 == 0:
        sync_transform.rpc(global_position, sprinting)
