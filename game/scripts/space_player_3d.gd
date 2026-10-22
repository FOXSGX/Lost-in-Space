extends CharacterBody3D
class_name SpacePlayer3D

const VISUAL_SCENE := preload("res://scenes/protagonist_visual.tscn")
const SPEED := 5.8
const SPRINT_MULTIPLIER := 1.65
const SHIP_EYE_HEIGHT: float = 1.6
const SHIP_FIRST_PERSON_FOV: float = 74.0
const SHIP_LOOK_SENSITIVITY: float = 0.0020
const SHIP_PITCH_LIMIT: float = 1.25
const ATTACK_RANGE := 3.75
const ATTACK_INTERVAL := 0.35
const JUMP_SPEED: float = 5.5
const GRAVITY: float = 18.0
const JET_HOLD_DELAY: float = 0.22
const JET_ACCELERATION: float = 28.0
const JET_SPEED: float = 6.0
const JET_DURATION: float = 0.5
const THIRD_PERSON_DISTANCE := 15.0
const THIRD_PERSON_MIN_DISTANCE := 11.0
const THIRD_PERSON_HEIGHT := 8.6
const THIRD_PERSON_SHOULDER := 0.9
const THIRD_PERSON_COLLISION_MARGIN := 0.28
const THIRD_PERSON_MOUSE_SENSITIVITY := 0.0024
const THIRD_PERSON_ROTATION_SMOOTHNESS := 24.0
const THIRD_PERSON_CAMERA_SMOOTHNESS := 20.0
const THIRD_PERSON_PITCH_MIN := -0.58
const THIRD_PERSON_PITCH_MAX := 0.30
# 共振星洞窟安全范围：镜头超出这个盒子会穿进岩壁或洞顶。
const RESONANCE_CAMERA_BOUNDS_MIN := Vector3(-76.0, 2.4, -44.0)
const RESONANCE_CAMERA_BOUNDS_MAX := Vector3(76.0, 22.0, 44.0)
const RESONANCE_FALL_DURATION := 0.82
const RESONANCE_CHARACTER_VISUAL_SCALE := 0.78
var peer_id := 1
var health := 5
var oxygen := 100.0
var warmth := 1.0
var carrying := 0
var carrying_id := 0
var goofy_board_remaining := 0.0
var shield_remaining := 0.0
var tool_id := ""
var skin_id := "ranger"
var goofy_bubble_remaining := 0.0
var sprinting := false
var downed := false
var lava_dead := false
var falling_to_lava := false
var fall_elapsed := 0.0
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
var _goofy_board_visual: MeshInstance3D
var _resonance_camera_mode := false
var _camera_yaw := 0.0
var _camera_pitch := -0.18
var _network_view_pitch: float = 0.0
var _camera_yaw_target := 0.0
var _camera_pitch_target := -0.18
var _mouse_capture_requested := false
var _ship_first_person_mode: bool = false
var _ship_cursor_released: bool = false
var jet_active: bool = false
var jet_charge: float = 0.0
var jet_button_held: bool = false
var _jump_held: float = 0.0
var _jet_pack: Node3D
var _jet_flames: Array[MeshInstance3D] = []
var _jet_audio: AudioStreamPlayer3D

func setup(id: int, color: Color) -> void:
    peer_id = id
    name = "Player3D_%d" % id
    _build_visual(color)

func _enter_tree() -> void:
    set_multiplayer_authority(peer_id)

func _ready() -> void:
    collision_layer = 1
    collision_mask = 2 | 8
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.5
    shape.shape = capsule
    shape.position.y = 0.8
    add_child(shape)
    if peer_id == multiplayer.get_unique_id():
        _build_camera()

func _exit_tree() -> void:
    if peer_id == multiplayer.get_unique_id():
        _release_resonance_mouse()

func _build_visual(color: Color) -> void:
    _visual = VISUAL_SCENE.instantiate() as ProtagonistVisual
    _visual.set_team_color(color)
    add_child(_visual)
    if skin_id != "":
        _visual.set_skin(skin_id)
    if tool_id != "":
        _visual.set_tool_model(tool_id)

func set_skin(next_skin_id: String) -> void:
    skin_id = next_skin_id
    if _visual != null:
        _visual.set_skin(skin_id)

func set_tool(next_tool_id: String) -> void:
    tool_id = next_tool_id
    if _visual != null:
        _visual.set_tool_model(tool_id)

func _process(delta: float) -> void:
    shield_remaining = maxf(shield_remaining - delta, 0.0)
    if _visual != null:
        _visual.set_shield_visible(shield_remaining > 0.0)
    _remove_camera_shake_offset()
    var motion := velocity if is_multiplayer_authority() else (global_position - _last_visual_position) / maxf(delta, 0.001)
    _last_visual_position = global_position
    var controller := get_parent() as Main3D
    _update_jet_visual(controller)
    var resonance_camera: bool = controller != null and controller.game_started and not controller.ship_active and controller.current_planet_id == "electromagnetic"
    if _visual != null:
        if _camera != null:
            _visual.visible = not (controller != null and controller.ship_active)
        _visual.update_state(delta, Vector2(motion.x, motion.z), downed, scan_lock_remaining > 0.0, carrying > 0 and (controller == null or controller._items == null), health, resonance_camera or (controller != null and controller.ship_active))
        if falling_to_lava:
            _visual.rotation.x = lerpf(_visual.rotation.x, -0.18 - fall_elapsed * 0.24, minf(delta * 12.0, 1.0))
            _visual.rotation.z = sin(fall_elapsed * 17.0) * 0.16
        else:
            _visual.rotation.x = lerpf(_visual.rotation.x, 0.0, minf(delta * 10.0, 1.0))
            _visual.rotation.z = lerpf(_visual.rotation.z, 0.0, minf(delta * 10.0, 1.0))
    if _goofy_board_visual != null and is_instance_valid(_goofy_board_visual):
        _goofy_board_visual.rotation.y += delta * 4.0
        _goofy_board_visual.position.y = 0.12 + sin(Time.get_ticks_msec() * 0.008 + float(peer_id)) * 0.035
    if controller != null and controller.game_started and not controller.ship_active:
        if _visual != null:
            var visual_scale: float = RESONANCE_CHARACTER_VISUAL_SCALE if resonance_camera else 1.0
            _visual.scale = _visual.scale.lerp(Vector3.ONE * visual_scale, 1.0 - exp(-8.0 * delta))
            _visual.set_resonance_visibility_priority(resonance_camera)
        _update_planet_camera(resonance_camera, delta)
    if controller != null and controller.ship_active and _camera != null:
        _update_ship_first_person(delta)
    _apply_camera_shake(delta)

func _input(event: InputEvent) -> void:
    if peer_id != multiplayer.get_unique_id():
        return
    var controller := get_parent() as Main3D
    if controller != null and controller.ship_active:
        if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _ship_ui_blocked():
            var ship_motion: InputEventMouseMotion = event as InputEventMouseMotion
            _camera_yaw_target -= ship_motion.relative.x * SHIP_LOOK_SENSITIVITY
            _camera_pitch_target = clampf(_camera_pitch_target + ship_motion.relative.y * SHIP_LOOK_SENSITIVITY, -SHIP_PITCH_LIMIT, SHIP_PITCH_LIMIT)
        return
    if controller == null or controller.current_planet_id != "electromagnetic" or controller.ship_active:
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var motion: InputEventMouseMotion = event as InputEventMouseMotion
        _apply_mouse_look(motion.relative)
    elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        _mouse_capture_requested = true
        Input.use_accumulated_input = false
    elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
        _release_resonance_mouse()

func _unhandled_input(event: InputEvent) -> void:
    var controller: Main3D = get_parent() as Main3D
    if is_multiplayer_authority() and event is InputEventMouseButton and controller != null:
        var wheel: InputEventMouseButton = event as InputEventMouseButton
        var allowed: bool = (controller.ship_active or controller.game_started) and not controller._settings_visible and not controller.market_visible and not controller.is_journal_visible() and not controller._ship_session.has_panel() and not controller._items.choice_open
        if allowed and wheel.pressed and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
            controller.handle_action(peer_id, "slot_next" if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN else "slot_previous")
            get_viewport().set_input_as_handled()
            return
    if _camera == null or not _ship_first_person_mode or _ship_ui_blocked():
        return
    if event is InputEventMouseButton:
        var click: InputEventMouseButton = event as InputEventMouseButton
        # GUI gets the click first, so ready/market/facility buttons remain usable.
        if click.pressed and click.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
            _ship_cursor_released = false
            controller._items.suppress_use_until = Time.get_ticks_msec() + 180
            refresh_ship_mouse_mode()
            get_viewport().set_input_as_handled()

func _ship_ui_blocked() -> bool:
    var controller: Main3D = get_parent() as Main3D
    return controller == null or not controller.ship_active or controller._settings_visible or controller.market_visible or controller._screen_view != "ship" or controller._ship_session.has_panel()

func refresh_ship_mouse_mode() -> void:
    if _camera == null or not _ship_first_person_mode:
        return
    var capture: bool = not _ship_ui_blocked() and not _ship_cursor_released
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
    Input.use_accumulated_input = not capture

func _update_ship_first_person(delta: float) -> void:
    _camera_yaw = lerp_angle(_camera_yaw, _camera_yaw_target, 1.0 - exp(-THIRD_PERSON_ROTATION_SMOOTHNESS * delta))
    _camera_pitch = lerpf(_camera_pitch, _camera_pitch_target, 1.0 - exp(-THIRD_PERSON_ROTATION_SMOOTHNESS * delta))
    rotation.y = _camera_yaw
    _camera.global_position = global_position + Vector3.UP * SHIP_EYE_HEIGHT
    _camera.global_rotation = Vector3(-_camera_pitch, _camera_yaw, 0.0)
    refresh_ship_mouse_mode()

func _apply_mouse_look(relative: Vector2) -> void:
    # Godot 的角色前方是 -Z；rotation.y 增大时前方朝 -X，
    # 因此鼠标向右要减少 yaw，才能让屏幕前方和角色前方一起向右转。
    _camera_yaw_target -= relative.x * THIRD_PERSON_MOUSE_SENSITIVITY
    # 鼠标向上时 relative.y 为负值，降低轨道角度后视线抬高；向下则相反。
    _camera_pitch_target = clampf(_camera_pitch_target + relative.y * THIRD_PERSON_MOUSE_SENSITIVITY, THIRD_PERSON_PITCH_MIN, THIRD_PERSON_PITCH_MAX)

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
    stop_jet()
    var controller: Main3D = get_parent() as Main3D
    jet_charge = controller._items.jet_reserve(peer_id) if controller != null and controller._items != null else 0.0
    _last_visual_position = point
    _camera_shake_remaining = 0.0
    _camera_shake_duration = 0.0
    _camera_shake_strength = 0.0
    _camera_shake_clock = 0.0
    if _ship_first_person_mode and _camera != null:
        _camera.global_position = global_position + Vector3.UP * SHIP_EYE_HEIGHT

func set_goofy_state(kind: String, duration: float) -> void:
    if kind == "board":
        goofy_board_remaining = maxf(duration, 0.0)
        if goofy_board_remaining > 0.0 and (_goofy_board_visual == null or not is_instance_valid(_goofy_board_visual)):
            _goofy_board_visual = MeshInstance3D.new()
            _goofy_board_visual.name = "GoofySnowBoard"
            var mesh := BoxMesh.new()
            mesh.size = Vector3(1.35, 0.08, 0.36)
            _goofy_board_visual.mesh = mesh
            _goofy_board_visual.material_override = _glow_material(Color("#ffd36e"))
            _goofy_board_visual.position.y = 0.12
            add_child(_goofy_board_visual)
        elif goofy_board_remaining <= 0.0 and _goofy_board_visual != null and is_instance_valid(_goofy_board_visual):
            _goofy_board_visual.queue_free()
            _goofy_board_visual = null
    elif kind == "bubble":
        goofy_bubble_remaining = maxf(duration, 0.0)

func configure_ship_camera() -> void:
    var controller := get_parent() as Main3D
    _remove_camera_shake_offset()
    _resonance_camera_mode = false
    if _visual != null:
        _visual.set_resonance_visibility_priority(false)
    # Remote players must not change the local window's cursor or camera state.
    if _camera == null:
        return
    _release_resonance_mouse()
    _ship_first_person_mode = controller != null and controller.ship_active
    _ship_cursor_released = false
    if _visual != null:
        _visual.visible = not _ship_first_person_mode
    if _camera != null and controller != null and controller.ship_active:
        _camera_yaw = controller._ship_session.spawn_yaw()
        _camera_yaw_target = _camera_yaw
        _camera_pitch = 0.0
        _camera_pitch_target = 0.0
        _camera.projection = Camera3D.PROJECTION_PERSPECTIVE
        _camera.fov = SHIP_FIRST_PERSON_FOV
        _camera.near = 0.05
        _update_ship_first_person(1.0)
        var sensor := get_node_or_null("PlayerSensorLight") as OmniLight3D
        if sensor != null:
            sensor.light_energy = 0.18
            sensor.omni_range = 5.0
    if attack_range_visual != null:
        # 共振星采用完整第三人称合作视角，不显示攻击范围圆环；圆环会
        # 在肩后镜头前形成大面积遮挡，且本星球没有准星需求。
        attack_range_visual.visible = controller != null and not controller.ship_active and controller.current_planet_id != "electromagnetic"

func _update_planet_camera(resonance: bool, delta: float = 0.016) -> void:
    if _camera == null:
        return
    if resonance and attack_range_visual != null:
        attack_range_visual.visible = false
    if resonance:
        var entering_resonance: bool = not _resonance_camera_mode
        if entering_resonance:
            _camera_yaw = rotation.y
            _camera_yaw_target = _camera_yaw
            _camera_pitch = -0.18
            _camera_pitch_target = _camera_pitch
            _mouse_capture_requested = true
            Input.use_accumulated_input = false
        if _mouse_capture_requested and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        _resonance_camera_mode = true
        _camera_yaw = lerp_angle(_camera_yaw, _camera_yaw_target, 1.0 - exp(-THIRD_PERSON_ROTATION_SMOOTHNESS * delta))
        _camera_pitch = lerpf(_camera_pitch, _camera_pitch_target, 1.0 - exp(-THIRD_PERSON_ROTATION_SMOOTHNESS * delta))
        # 朝向与镜头绑定，角色站立、移动或执行装置动作时都保持面向前方。
        rotation.y = _camera_yaw
        _camera.projection = Camera3D.PROJECTION_PERSPECTIVE
        _camera.fov = 62.0
        var target: Vector3 = global_position + Vector3(0.0, 0.9, 0.0)
        var desired_position: Vector3 = _third_person_camera_position(target)
        desired_position = _resolve_third_person_camera_position(target, desired_position)
        desired_position = _clamp_resonance_camera(desired_position)
        _camera.global_position = _camera.global_position.lerp(desired_position, 1.0 - exp(-THIRD_PERSON_CAMERA_SMOOTHNESS * delta))
        _camera.look_at(target, Vector3.UP)
    elif _resonance_camera_mode:
        _resonance_camera_mode = false
        _camera.projection = Camera3D.PROJECTION_ORTHOGONAL
        _camera.size = 28.0
        _camera.global_position = global_position + Vector3(0.0, 16.0, 15.0)
        _camera.rotation_degrees = Vector3(-46.0, 0.0, 0.0)
        _release_resonance_mouse()
    elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or _mouse_capture_requested:
        # 处理场景切换先于相机状态更新的边界情况，避免光标卡在隐藏状态。
        _release_resonance_mouse()

func _release_resonance_mouse() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    Input.use_accumulated_input = true
    _mouse_capture_requested = false

func _third_person_camera_position(target: Vector3) -> Vector3:
    var forward: Vector3 = Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
    var right: Vector3 = Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
    var horizontal_distance: float = cos(_camera_pitch) * THIRD_PERSON_DISTANCE
    var vertical_offset: float = THIRD_PERSON_HEIGHT + sin(_camera_pitch) * THIRD_PERSON_DISTANCE
    return target - forward * horizontal_distance + right * THIRD_PERSON_SHOULDER + Vector3.UP * vertical_offset

func _clamp_resonance_camera(position: Vector3) -> Vector3:
    # 远景镜头不再依赖透明淡出，因此必须把镜头限制在洞窟体积内，
    # 否则贴着岩壁站位时相机会穿到山体外面。
    return Vector3(
        clampf(position.x, RESONANCE_CAMERA_BOUNDS_MIN.x, RESONANCE_CAMERA_BOUNDS_MAX.x),
        clampf(position.y, RESONANCE_CAMERA_BOUNDS_MIN.y, RESONANCE_CAMERA_BOUNDS_MAX.y),
        clampf(position.z, RESONANCE_CAMERA_BOUNDS_MIN.z, RESONANCE_CAMERA_BOUNDS_MAX.z)
    )

func _resolve_third_person_camera_position(target: Vector3, desired_position: Vector3) -> Vector3:
    var controller := get_parent() as Main3D
    if controller == null or controller.get_world_3d() == null:
        return desired_position
    var query := PhysicsRayQueryParameters3D.create(target, desired_position)
    query.collision_mask = 4
    query.exclude = [get_rid()]
    var hit: Dictionary = controller.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return desired_position
    var hit_position: Vector3 = hit.get("position", desired_position)
    var direction := (desired_position - target).normalized()
    var safe_distance := maxf(THIRD_PERSON_MIN_DISTANCE, target.distance_to(hit_position) - THIRD_PERSON_COLLISION_MARGIN)
    return target + direction * safe_distance

func _choose_resonance_camera_position(target: Vector3) -> Vector3:
    var offsets: Array[Vector3] = [
        Vector3(0.0, 11.5, 14.5),
        Vector3(0.0, 12.5, -14.5),
        Vector3(14.5, 10.5, 0.0),
        Vector3(-14.5, 10.5, 0.0)
    ]
    var fallback: Vector3 = target + offsets[0]
    for offset in offsets:
        var candidate: Vector3 = target + offset
        if _resonance_camera_ray_clear(candidate, target):
            return candidate
        fallback = candidate
    return fallback

func _resonance_camera_ray_clear(camera_position: Vector3, target: Vector3) -> bool:
    var controller := get_parent() as Main3D
    if controller == null or controller.get_world_3d() == null:
        return true
    var query := PhysicsRayQueryParameters3D.create(camera_position, target)
    query.collision_mask = 4
    query.exclude = [get_rid()]
    var hit: Dictionary = controller.get_world_3d().direct_space_state.intersect_ray(query)
    return hit.is_empty()

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
    if is_multiplayer_authority():
        jet_active = false
    scan_lock_remaining = maxf(scan_lock_remaining - delta, 0.0)
    scan_cooldown_remaining = maxf(scan_cooldown_remaining - delta, 0.0)
    if scan_lock_remaining > 0.0:
        velocity = Vector3.ZERO
        global_position = scan_origin
    if falling_to_lava:
        _tick_resonance_fall(delta)
        return
    if scan_lock_remaining <= 0.0 and not is_multiplayer_authority() and _has_target_position:
        global_position = global_position.lerp(_target_position, 1.0 - exp(-14.0 * delta))
    if not is_multiplayer_authority() or downed or lava_dead:
        return
    _attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
    var controller := get_parent() as Main3D
    if controller == null or (not controller.game_started and not controller.ship_active) or controller.mission_completed or controller.mission_failed:
        return
    if controller._items.choice_open or controller._settings_visible or controller.market_visible:
        stop_jet()
        velocity = Vector3(0, 0 if is_on_floor() else velocity.y - GRAVITY * delta, 0)
        move_and_slide()
        return
    if controller.ship_active:
        _tick_ship(controller)
        return
    if controller.minigame_active and controller.minigame_peer_id == peer_id:
        sprinting = false
        velocity = Vector3.ZERO
        return
    if controller.is_journal_visible():
        stop_jet()
        sprinting = false
        velocity = Vector3.ZERO
        return
    if Input.is_action_just_pressed("scan"):
        controller.handle_action(peer_id, "item_scan")
    if Input.is_action_just_pressed("resonance_drone"):
        controller.handle_action(peer_id, "resonance_drone")
        return
    var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    var resonance_surface: bool = controller.current_planet_id == "electromagnetic"
    if resonance_surface:
        # 共振星采用完整第三人称：角色始终朝向鼠标控制的镜头前方，
        # 即使没有移动输入也要立即更新朝向，保证交互、动画和联机同步一致。
        rotation.y = _camera_yaw
    sprinting = Input.is_action_pressed("sprint")
    var move_speed := SPEED * (SPRINT_MULTIPLIER if sprinting else 1.0)
    if goofy_board_remaining > 0.0:
        move_speed *= 2.05
        sprinting = true
    goofy_board_remaining = maxf(goofy_board_remaining - delta, 0.0)
    goofy_bubble_remaining = maxf(goofy_bubble_remaining - delta, 0.0)
    move_speed *= controller._items.move_multiplier(peer_id) if controller._items != null else (0.58 if carrying == 2 else (0.72 if carrying == 1 else 1.0))
    if controller.storm_active:
        move_speed *= 0.68
    var was_moving := velocity.length() > 0.1
    if scan_lock_remaining <= 0.0:
        var vertical_velocity: float = velocity.y
        vertical_velocity = _jump_velocity(vertical_velocity, delta)
        if resonance_surface:
            var movement: Vector3 = _third_person_movement(input_vector)
            velocity = Vector3(movement.x * move_speed, vertical_velocity, movement.z * move_speed)
        else:
            velocity = Vector3(input_vector.x * move_speed, vertical_velocity, input_vector.y * move_speed)
        move_and_slide()
        # 移动反馈 - 每隔一段时间生成脚步粒子
        if velocity.length() > 0.1 and Engine.get_physics_frames() % 15 == 0:
            _spawn_footstep_particle()
    var map_half := controller.get_active_map_size() * 0.5 - Vector2(1.0, 1.0)
    global_position.x = clampf(global_position.x, -map_half.x, map_half.x)
    global_position.z = clampf(global_position.z, -map_half.y, map_half.y)
    for action in ["interact", "item_drop", "slot_1", "slot_2"]:
        if Input.is_action_just_pressed(action):
            controller.handle_action(peer_id, action)
    if scan_lock_remaining <= 0.0 and Time.get_ticks_msec() >= controller._items.suppress_use_until:
        var empty_hand: bool = controller._items.selected(peer_id).is_empty()
        if (empty_hand and Input.is_action_pressed("item_use") and _attack_cooldown <= 0.0) or (not empty_hand and Input.is_action_just_pressed("item_use")):
            _attack_cooldown = ATTACK_INTERVAL
            controller.handle_action(peer_id, "item_use")
    if Engine.get_physics_frames() % 2 == 0:
        sync_transform.rpc(global_position, sprinting, rotation.y, falling_to_lava, _camera_pitch, jet_active, jet_button_held)

func begin_resonance_fall() -> void:
    if falling_to_lava or lava_dead or downed:
        return
    falling_to_lava = true
    fall_elapsed = 0.0
    velocity = Vector3(0.0, -2.2, 0.0)
    sprinting = false

func _tick_resonance_fall(delta: float) -> void:
    fall_elapsed += delta
    var ratio: float = clampf(fall_elapsed / RESONANCE_FALL_DURATION, 0.0, 1.0)
    velocity = Vector3(0.0, lerpf(-2.2, -10.5, ratio), 0.0)
    global_position += velocity * delta
    rotation.x = lerpf(rotation.x, -0.22 - ratio * 0.35, minf(delta * 10.0, 1.0))
    rotation.z = sin(fall_elapsed * 13.0) * 0.12
    if ratio >= 1.0:
        var controller := get_parent() as Main3D
        if controller != null and (is_multiplayer_authority() or controller.is_host):
            controller.kill_player_in_lava(peer_id)

func _third_person_movement(input_vector: Vector2) -> Vector3:
    var camera_forward: Vector3 = Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
    var camera_right: Vector3 = Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
    return camera_right * input_vector.x + camera_forward * -input_vector.y

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
func sync_transform(next_position: Vector3, next_sprinting: bool = false, next_rotation_y: float = -999.0, next_falling: bool = false, view_pitch: float = 0.0, next_jet: bool = false, next_jet_held: bool = false) -> void:
    var controller: Main3D = get_parent() as Main3D
    jet_button_held = next_jet_held
    jet_active = next_jet and jet_charge > 0.0 and not downed and not lava_dead and controller != null and controller._items.has_jet(peer_id)
    _network_view_pitch = clampf(view_pitch, -SHIP_PITCH_LIMIT, SHIP_PITCH_LIMIT)
    sprinting = next_sprinting
    if next_rotation_y > -900.0:
        rotation.y = next_rotation_y
    falling_to_lava = next_falling and not lava_dead
    if is_multiplayer_authority() or downed or scan_lock_remaining > 0.0:
        return
    if multiplayer.is_server():
        global_position = next_position
        return
    _target_position = next_position
    _has_target_position = true

func _tick_ship(controller: Main3D) -> void:
    var ship := controller._ship_session
    if _ship_ui_blocked() or _ship_cursor_released:
        stop_jet()
        velocity = Vector3(0, 0 if is_on_floor() else velocity.y - GRAVITY * get_physics_process_delta_time(), 0)
        move_and_slide()
        sprinting = false
        return
    var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
    var movement: Vector3 = _third_person_movement(input_vector)
    rotation.y = _camera_yaw
    sprinting = Input.is_action_pressed("sprint")
    var move_speed := SPEED * (SPRINT_MULTIPLIER if sprinting else 1.0)
    move_speed *= controller._items.move_multiplier(peer_id)
    if goofy_board_remaining > 0.0:
        move_speed *= 2.05
    goofy_board_remaining = maxf(goofy_board_remaining - get_physics_process_delta_time(), 0.0)
    goofy_bubble_remaining = maxf(goofy_bubble_remaining - get_physics_process_delta_time(), 0.0)
    velocity = Vector3(movement.x * move_speed, _jump_velocity(velocity.y, get_physics_process_delta_time()), movement.z * move_speed)
    move_and_slide()
    var bounds := ShipHub3D.WALK_BOUNDS if ship.in_hub else Vector2(9.9, 6.2)
    global_position.x = clampf(global_position.x, -bounds.x, bounds.x)
    global_position.z = clampf(global_position.z, -bounds.y, bounds.y)
    for action: String in ["interact", "item_drop", "slot_1", "slot_2"]:
        if Input.is_action_just_pressed(action):
            controller.handle_action(peer_id, action)
    if Input.is_action_just_pressed("scan"):
        controller.handle_action(peer_id, "item_scan")
    if Input.is_action_just_pressed("item_use") and Time.get_ticks_msec() >= controller._items.suppress_use_until:
        controller.handle_action(peer_id, "item_use")
    if Engine.get_physics_frames() % 2 == 0:
        sync_transform.rpc(global_position, sprinting, rotation.y, false, _camera_pitch, jet_active, jet_button_held)

func aim_direction() -> Vector3:
    var pitch: float = _camera_pitch if is_multiplayer_authority() else _network_view_pitch
    return (-global_transform.basis.z * cos(pitch) + Vector3.DOWN * sin(pitch)).normalized()

func _jump_velocity(current: float, delta: float) -> float:
    var held: bool = Input.is_action_pressed("jump")
    jet_button_held = held
    _jump_held = _jump_held + delta if held else 0.0
    var next: float = (JUMP_SPEED if Input.is_action_just_pressed("jump") else 0.0) if is_on_floor() else maxf(current - GRAVITY * delta, -28.0)
    var controller: Main3D = get_parent() as Main3D
    var equipped: bool = controller != null and controller._items != null and controller._items.has_jet(peer_id)
    jet_active = equipped and held and _jump_held >= JET_HOLD_DELAY and jet_charge > 0.0
    if jet_active:
        next = minf(next + JET_ACCELERATION * delta, JET_SPEED)
        if not controller.is_host:
            jet_charge = maxf(jet_charge - delta / JET_DURATION, 0.0)
    return next

func stop_jet() -> void:
    jet_active = false
    jet_button_held = false
    _jump_held = 0.0

func _update_jet_visual(controller: Main3D) -> void:
    var mounted: bool = controller != null and controller._items != null and controller._items.has_jet(peer_id)
    if mounted and not is_instance_valid(_jet_pack):
        _jet_pack = Node3D.new()
        _jet_pack.name = "SuitOxygenPack"
        _jet_pack.position = Vector3(0, 0.55, 0.4)
        add_child(_jet_pack)
        var bottle: ItemProp3D = ItemProp3D.create("oxygen")
        _jet_pack.add_child(bottle)
        for side: float in [-0.13, 0.13]:
            var flame: MeshInstance3D = MeshInstance3D.new()
            var cone: CylinderMesh = CylinderMesh.new()
            cone.top_radius = 0.07
            cone.bottom_radius = 0.015
            cone.height = 0.55
            flame.mesh = cone
            flame.material_override = _glow_material(Color("#8bf3ff"))
            flame.position = Vector3(side, -0.26, 0.0)
            _jet_pack.add_child(flame)
            _jet_flames.append(flame)
        _jet_audio = AudioStreamPlayer3D.new()
        _jet_audio.stream = load("res://assets/audio/oxygen-jet.wav") as AudioStream
        _jet_audio.volume_db = -30.0
        _jet_audio.max_distance = 18.0
        _jet_pack.add_child(_jet_audio)
    if is_instance_valid(_jet_pack):
        _jet_pack.visible = mounted
        var firing: bool = mounted and jet_active and not downed and not lava_dead
        for flame: MeshInstance3D in _jet_flames:
            flame.visible = firing
            flame.scale.y = 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.07)
        if firing and not _jet_audio.playing:
            _jet_audio.play()
        elif not firing and _jet_audio.playing:
            _jet_audio.stop()
