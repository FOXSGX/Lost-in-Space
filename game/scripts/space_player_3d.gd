extends CharacterBody3D
class_name SpacePlayer3D

const VISUAL_SCENE := preload("res://scenes/protagonist_visual.tscn")
const SPEED := 5.8
const SPRINT_MULTIPLIER := 1.65
const SHIP_EYE_HEIGHT: float = 1.6
const SHIP_FIRST_PERSON_FOV: float = 74.0
const SHIP_LOOK_SENSITIVITY: float = 0.0020
const SHIP_PITCH_LIMIT: float = 1.25
# 腐墟星第一人称：与主舱同一套眼高/鼠标环视，但视野略宽、俯仰更大，
# 因为玩家要在街道上抬头看建筑、低头看物资。
const RUIN_EYE_HEIGHT: float = 1.62
const RUIN_FIRST_PERSON_FOV: float = 76.0
const RUIN_LOOK_SENSITIVITY: float = 0.0023
const RUIN_PITCH_LIMIT: float = 1.15
const RUIN_BOB_HEIGHT: float = 0.016
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
const RESONANCE_ZONE_CAMERA_RADIUS := 30.0
const RESONANCE_CAMERA_BOUNDS_MIN := Vector3(-76.0, 2.4, -44.0)
const RESONANCE_CAMERA_BOUNDS_MAX := Vector3(76.0, 22.0, 44.0)
const RESONANCE_FALL_DURATION := 0.82
const RESONANCE_CHARACTER_VISUAL_SCALE := 0.78
var peer_id := 1
const MAX_HEALTH: int = 5
signal health_changed(current: int)

var health: int = MAX_HEALTH:
    set(value):
        var next: int = clampi(value, 0, MAX_HEALTH)
        if health == next:
            return
        health = next
        health_changed.emit(health)
var health_revision: int = 0
var _captured_health: Vector2i = Vector2i(MAX_HEALTH, 0)
var _ship_eye_height: float = SHIP_EYE_HEIGHT
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
var _ruin_first_person_mode: bool = false
var _ruin_cursor_released: bool = false
var _ruin_viewmodel: Node3D
var _ruin_crowbar: Node3D
var _ruin_blade_pivot: Node3D
var _ruin_blade_core: MeshInstance3D
var _ruin_blade_glow: MeshInstance3D
var _ruin_blade_light: OmniLight3D
var _ruin_force_active := false
var _ruin_force_progress := 0.0
var _ruin_force_cooldown := 0.0
var _ruin_swing_remaining: float = 0.0
var _ruin_bob_phase: float = 0.0
var jet_active: bool = false
var jet_charge: float = 0.0
var jet_button_held: bool = false
var _jump_held: float = 0.0
var _jet_pack: Node3D
var _jet_flames: Array[MeshInstance3D] = []
var _jet_bottles: Array[ItemProp3D] = []
var _jet_audio: AudioStreamPlayer3D

func setup(id: int, color: Color) -> void:
    peer_id = id
    name = "Player3D_%d" % id
    _build_visual(color)

func _enter_tree() -> void:
    set_multiplayer_authority(peer_id)

func _ready() -> void:
    collision_layer = 1
    collision_mask = 2 | 4 | 8
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
    var resonance_camera: bool = false
    if _visual != null:
        if _camera != null:
            _visual.visible = not (controller != null and (controller.ship_active or _ruin_first_person_mode))
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
        if _ruin_first_person_mode:
            _update_ruin_first_person(delta)
        else:
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
    if controller != null and _ruin_first_person_mode and not controller.ship_active:
        if _ruin_ui_blocked():
            return
        if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
            _apply_ruin_mouse_look((event as InputEventMouseMotion).relative)
        elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
            # 第一次点击先把光标收回准星，不当作攻击；后续点击才交给近战。
            if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
                _ruin_cursor_released = false
                if controller._items != null:
                    controller._items.suppress_use_until = Time.get_ticks_msec() + 180
                refresh_ruin_mouse_mode()
                get_viewport().set_input_as_handled()
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
    _ship_eye_height = lerpf(_ship_eye_height, 0.55 if downed else SHIP_EYE_HEIGHT, 1.0 - exp(-8.0 * delta))
    _camera.global_position = global_position + Vector3.UP * _ship_eye_height
    _camera.global_rotation = Vector3(-_camera_pitch, _camera_yaw, -0.12 if downed else 0.0)
    refresh_ship_mouse_mode()

# ── 腐墟星第一人称 ─────────────────────────────────────────────

## 登陆腐墟星时把本地镜头切成第一人称。远端玩家没有相机，调用会安全返回。
func configure_ruin_camera() -> bool:
    var controller := get_parent() as Main3D
    _remove_camera_shake_offset()
    _release_resonance_mouse()
    _ruin_first_person_mode = controller != null and controller.current_planet_id == "ruin" and not controller.ship_active
    if not _ruin_first_person_mode:
        _dispose_ruin_viewmodel()
        _ruin_cursor_released = false
        if _visual != null:
            _visual.visible = true
        return false
    _ship_first_person_mode = false
    if _camera == null:
        return false
    _camera_yaw = rotation.y
    _camera_yaw_target = _camera_yaw
    _camera_pitch = -0.04
    _camera_pitch_target = _camera_pitch
    _camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    _camera.fov = RUIN_FIRST_PERSON_FOV
    _camera.near = 0.05
    _camera.far = 400.0
    if _visual != null:
        _visual.visible = false
    if attack_range_visual != null:
        # 第一人称已经有准星，地面上的攻击范围圈会变成脚下的一个突兀圆环。
        attack_range_visual.visible = false
    _ruin_cursor_released = false
    _build_ruin_viewmodel()
    _update_ruin_first_person(0.016)
    refresh_ruin_mouse_mode()
    return true


func is_ruin_first_person() -> bool:
    return _ruin_first_person_mode


func _ruin_ui_blocked() -> bool:
    var controller := get_parent() as Main3D
    if controller == null or not controller.game_started or controller.current_planet_id != "ruin":
        return true
    return controller._settings_visible \
        or controller.market_visible \
        or controller.is_journal_visible() \
        or controller.lockpick_active \
        or (controller._ship_session != null and controller._ship_session.has_panel()) \
        or (controller._items != null and controller._items.choice_open)


func refresh_ruin_mouse_mode() -> void:
    if _camera == null or not _ruin_first_person_mode:
        return
    var capture: bool = not _ruin_ui_blocked() and not _ruin_cursor_released
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
    Input.use_accumulated_input = not capture


## 设置/日志等界面开关时由 Main3D 调用，恢复或释放光标。
func refresh_first_person_mouse_mode() -> void:
    if _ruin_first_person_mode:
        refresh_ruin_mouse_mode()
    elif _ship_first_person_mode:
        refresh_ship_mouse_mode()


func _apply_ruin_mouse_look(relative: Vector2) -> void:
    _camera_yaw_target -= relative.x * RUIN_LOOK_SENSITIVITY
    _camera_pitch_target = clampf(_camera_pitch_target + relative.y * RUIN_LOOK_SENSITIVITY, -RUIN_PITCH_LIMIT, RUIN_PITCH_LIMIT)


func _update_ruin_first_person(delta: float) -> void:
    if _camera == null:
        return
    _camera_yaw = lerp_angle(_camera_yaw, _camera_yaw_target, 1.0 - exp(-26.0 * delta))
    _camera_pitch = lerpf(_camera_pitch, _camera_pitch_target, 1.0 - exp(-26.0 * delta))
    rotation.y = _camera_yaw
    var speed := Vector2(velocity.x, velocity.z).length()
    if speed > 0.25 and is_on_floor():
        _ruin_bob_phase += delta * (5.0 + speed * 1.2)
    else:
        _ruin_bob_phase = lerpf(_ruin_bob_phase, 0.0, 1.0 - exp(-5.0 * delta))
    var bob: float = sin(_ruin_bob_phase) * RUIN_BOB_HEIGHT * clampf(speed / 6.0, 0.0, 1.0)
    var eye_height: float = 0.55 if downed else RUIN_EYE_HEIGHT
    _camera.global_position = global_position + Vector3.UP * (eye_height + bob)
    _camera.global_rotation = Vector3(-_camera_pitch, _camera_yaw, -0.10 if downed else 0.0)
    _camera.fov = RUIN_FIRST_PERSON_FOV
    refresh_ruin_mouse_mode()
    _update_ruin_viewmodel(delta)


func _build_ruin_viewmodel() -> void:
    if _ruin_viewmodel != null or _camera == null:
        return
    var root := Node3D.new()
    root.name = "RuinViewmodel"
    root.position = Vector3(0.42, -0.45, -0.90)
    root.scale = Vector3.ONE * 0.65
    root.rotation_degrees = Vector3(6.0, -6.0, -4.0)
    _camera.add_child(root)
    # 手部材质单独压暗：space_player 的 _material 不做 sRGB→线性转换，
    # 直接写奶油白会在白天场景里烧成一团白球。
    var glove := _material(Color("#a9865c"))
    glove.roughness = 0.78
    var sleeve := _material(Color("#1f4d55"))
    sleeve.roughness = 0.84
    var cuff := _material(Color("#9a541f"))
    cuff.roughness = 0.72
    # space_player 的 _material 不做色彩空间转换，手部单独转一次，
    # 否则在明亮的腐墟星里会烧成白手套。
    glove.albedo_color = glove.albedo_color.srgb_to_linear()
    sleeve.albedo_color = sleeve.albedo_color.srgb_to_linear()
    cuff.albedo_color = cuff.albedo_color.srgb_to_linear()

    # 前臂：圆柱沿 Z 轴伸向镜头后方，镜头只看到袖口和手套。
    var forearm := MeshInstance3D.new()
    forearm.name = "Forearm"
    var forearm_mesh := CylinderMesh.new()
    forearm_mesh.top_radius = 0.055
    forearm_mesh.bottom_radius = 0.05
    forearm_mesh.height = 0.42
    forearm_mesh.radial_segments = 16
    forearm.mesh = forearm_mesh
    forearm.rotation_degrees.x = 90.0
    forearm.position = Vector3(0.0, 0.0, 0.18)
    forearm.material_override = sleeve
    forearm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(forearm)

    var cuff_mesh := MeshInstance3D.new()
    cuff_mesh.name = "Cuff"
    var cuff_cyl := CylinderMesh.new()
    cuff_cyl.top_radius = 0.064
    cuff_cyl.bottom_radius = 0.064
    cuff_cyl.height = 0.07
    cuff_cyl.radial_segments = 16
    cuff_mesh.mesh = cuff_cyl
    cuff_mesh.rotation_degrees.x = 90.0
    cuff_mesh.position = Vector3(0.0, 0.0, -0.03)
    cuff_mesh.material_override = cuff
    cuff_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(cuff_mesh)

    var hand := MeshInstance3D.new()
    hand.name = "Glove"
    var hand_mesh := SphereMesh.new()
    hand_mesh.radius = 0.5
    hand_mesh.height = 1.0
    hand_mesh.radial_segments = 18
    hand_mesh.rings = 10
    hand.mesh = hand_mesh
    hand.scale = Vector3(0.125, 0.11, 0.14)
    hand.position = Vector3(0.0, 0.0, -0.13)
    hand.material_override = glove
    hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(hand)

    var thumb := MeshInstance3D.new()
    thumb.name = "Thumb"
    var thumb_mesh := SphereMesh.new()
    thumb_mesh.radius = 0.5
    thumb_mesh.height = 1.0
    thumb_mesh.radial_segments = 12
    thumb_mesh.rings = 8
    thumb.mesh = thumb_mesh
    thumb.scale = Vector3(0.05, 0.045, 0.075)
    thumb.position = Vector3(-0.07, 0.025, -0.14)
    thumb.material_override = glove
    thumb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(thumb)

    # 三节指节：让手套读成握拳，而不是一颗奶油色圆球。
    var knuckle_seam := _material(Color("#6b4a2c"))
    for index: int in 3:
        var finger := MeshInstance3D.new()
        finger.name = "Finger%d" % index
        var finger_mesh := SphereMesh.new()
        finger_mesh.radius = 0.5
        finger_mesh.height = 1.0
        finger_mesh.radial_segments = 12
        finger_mesh.rings = 8
        finger.mesh = finger_mesh
        finger.scale = Vector3(0.04, 0.035, 0.05)
        finger.position = Vector3(-0.05 + float(index) * 0.05, 0.045, -0.20)
        finger.material_override = glove
        finger.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        root.add_child(finger)
        var seam := MeshInstance3D.new()
        seam.name = "FingerSeam%d" % index
        var seam_mesh := BoxMesh.new()
        seam_mesh.size = Vector3(0.012, 0.045, 0.06)
        seam.mesh = seam_mesh
        seam.position = Vector3(-0.075 + float(index) * 0.05, 0.05, -0.235)
        seam.material_override = knuckle_seam
        seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        root.add_child(seam)

    var knuckle := MeshInstance3D.new()
    knuckle.name = "KnuckleBand"
    var knuckle_mesh := BoxMesh.new()
    knuckle_mesh.size = Vector3(0.10, 0.03, 0.03)
    knuckle.mesh = knuckle_mesh
    knuckle.position = Vector3(0.0, 0.04, -0.20)
    knuckle.material_override = cuff
    knuckle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(knuckle)
    # ── 激光剑：握在现有手套里，刀刃沿 -Z 伸向镜头前方 ──
    var hilt_metal := _material(Color("#28383c"))
    hilt_metal.albedo_color = hilt_metal.albedo_color.srgb_to_linear()
    var hilt_brass := _material(Color("#c9793b"))
    hilt_brass.albedo_color = hilt_brass.albedo_color.srgb_to_linear()
    var hilt := MeshInstance3D.new()
    hilt.name = "SaberHilt"
    var hilt_mesh := CylinderMesh.new()
    hilt_mesh.top_radius = 0.032
    hilt_mesh.bottom_radius = 0.040
    hilt_mesh.height = 0.25
    hilt_mesh.radial_segments = 16
    hilt.mesh = hilt_mesh
    hilt.position = Vector3(0.0, -0.18, -0.08)
    hilt.material_override = hilt_metal
    hilt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(hilt)
    for index: int in 3:
        var grip_band := MeshInstance3D.new()
        grip_band.name = "GripBand%d" % index
        var band_mesh := CylinderMesh.new()
        band_mesh.top_radius = 0.043
        band_mesh.bottom_radius = 0.043
        band_mesh.height = 0.025
        band_mesh.radial_segments = 12
        grip_band.mesh = band_mesh
        grip_band.position = Vector3(0.0, -0.10 - float(index) * 0.07, -0.08)
        grip_band.material_override = hilt_brass
        grip_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        root.add_child(grip_band)
    var guard := MeshInstance3D.new()
    guard.name = "SaberGuard"
    var guard_mesh := BoxMesh.new()
    guard_mesh.size = Vector3(0.22, 0.05, 0.10)
    guard.mesh = guard_mesh
    guard.position = Vector3(0.0, -0.02, -0.08)
    guard.material_override = hilt_brass
    guard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(guard)

    _ruin_blade_pivot = Node3D.new()
    _ruin_blade_pivot.name = "SaberBladePivot"
    _ruin_blade_pivot.position = Vector3(0.0, 0.0, -0.08)
    root.add_child(_ruin_blade_pivot)

    var blade_glow_material := StandardMaterial3D.new()
    var blade_glow_color := Color("#2bd8c4").srgb_to_linear()
    blade_glow_color.a = 0.30
    blade_glow_material.albedo_color = blade_glow_color
    blade_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    blade_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    blade_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    blade_glow_material.emission_enabled = true
    blade_glow_material.emission = Color("#2bd8c4").srgb_to_linear()
    blade_glow_material.emission_energy_multiplier = 0.7
    _ruin_blade_glow = MeshInstance3D.new()
    _ruin_blade_glow.name = "SaberBladeGlow"
    var glow_mesh := CylinderMesh.new()
    glow_mesh.top_radius = 0.068
    glow_mesh.bottom_radius = 0.048
    glow_mesh.height = 1.18
    glow_mesh.radial_segments = 16
    _ruin_blade_glow.mesh = glow_mesh
    _ruin_blade_glow.position = Vector3(0.0, 0.59, 0.0)
    _ruin_blade_glow.material_override = blade_glow_material
    _ruin_blade_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _ruin_blade_pivot.add_child(_ruin_blade_glow)

    var blade_core_material := StandardMaterial3D.new()
    blade_core_material.albedo_color = Color("#25d9c6").srgb_to_linear()
    blade_core_material.emission_enabled = true
    blade_core_material.emission = Color("#25d9c6").srgb_to_linear()
    blade_core_material.emission_energy_multiplier = 0.35
    blade_core_material.roughness = 0.18
    blade_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _ruin_blade_core = MeshInstance3D.new()
    _ruin_blade_core.name = "SaberBladeCore"
    var core_mesh := CylinderMesh.new()
    core_mesh.top_radius = 0.012
    core_mesh.bottom_radius = 0.009
    core_mesh.height = 1.16
    core_mesh.radial_segments = 10
    _ruin_blade_core.mesh = core_mesh
    _ruin_blade_core.position = Vector3(0.0, 0.59, 0.0)
    _ruin_blade_core.material_override = blade_core_material
    _ruin_blade_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _ruin_blade_pivot.add_child(_ruin_blade_core)

    var tip := MeshInstance3D.new()
    tip.name = "SaberTip"
    var tip_mesh := SphereMesh.new()
    tip_mesh.radius = 0.026
    tip_mesh.height = 0.052
    tip_mesh.radial_segments = 10
    tip_mesh.rings = 6
    tip.mesh = tip_mesh
    tip.position = Vector3(0.0, 1.18, 0.0)
    tip.material_override = blade_core_material
    tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _ruin_blade_pivot.add_child(tip)

    _ruin_blade_light = OmniLight3D.new()
    _ruin_blade_light.name = "SaberLight"
    _ruin_blade_light.light_color = Color("#7ff5e5")
    _ruin_blade_light.light_energy = 1.0
    _ruin_blade_light.omni_range = 3.0
    _ruin_blade_light.position = Vector3(0.0, 0.62, 0.0)
    _ruin_blade_pivot.add_child(_ruin_blade_light)

    _ruin_viewmodel = root
    _build_ruin_crowbar(root)


func _build_ruin_crowbar(_saber_root: Node3D) -> void:
    var root := Node3D.new()
    root.name = "RuinCrowbar"
    root.position = Vector3(0.30, -0.30, -0.52)
    root.rotation_degrees = Vector3(-14.0, 35.0, -20.0)
    root.scale = Vector3.ONE * 0.9
    root.visible = false
    _camera.add_child(root)
    var metal := _material(Color("#64777b"))
    metal.albedo_color = metal.albedo_color.srgb_to_linear()
    var rust := _material(Color("#9a541f"))
    rust.albedo_color = rust.albedo_color.srgb_to_linear()
    var glove := _material(Color("#a9865c"))
    glove.albedo_color = glove.albedo_color.srgb_to_linear()

    var shaft := MeshInstance3D.new()
    shaft.name = "CrowbarShaft"
    var shaft_mesh := CylinderMesh.new()
    shaft_mesh.top_radius = 0.022
    shaft_mesh.bottom_radius = 0.028
    shaft_mesh.height = 0.88
    shaft_mesh.radial_segments = 12
    shaft.mesh = shaft_mesh
    shaft.rotation_degrees.x = 90.0
    shaft.position = Vector3(0.0, 0.0, -0.40)
    shaft.material_override = metal
    shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(shaft)
    var hook := MeshInstance3D.new()
    hook.name = "CrowbarHook"
    var hook_mesh := BoxMesh.new()
    hook_mesh.size = Vector3(0.055, 0.05, 0.22)
    hook.mesh = hook_mesh
    hook.position = Vector3(0.0, 0.045, -0.82)
    hook.rotation_degrees.x = 34.0
    hook.material_override = metal
    hook.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(hook)
    var tip := MeshInstance3D.new()
    tip.name = "CrowbarTip"
    var tip_mesh := BoxMesh.new()
    tip_mesh.size = Vector3(0.045, 0.035, 0.10)
    tip.mesh = tip_mesh
    tip.position = Vector3(0.0, 0.115, -0.92)
    tip.rotation_degrees.x = 34.0
    tip.material_override = rust
    tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(tip)
    for index: int in 3:
        var band := MeshInstance3D.new()
        band.name = "CrowbarGrip%d" % index
        var band_mesh := CylinderMesh.new()
        band_mesh.top_radius = 0.030
        band_mesh.bottom_radius = 0.030
        band_mesh.height = 0.025
        band_mesh.radial_segments = 10
        band.mesh = band_mesh
        band.rotation_degrees.x = 90.0
        band.position = Vector3(0.0, 0.0, -0.06 - float(index) * 0.07)
        band.material_override = rust
        band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        root.add_child(band)
    var hand := MeshInstance3D.new()
    hand.name = "CrowbarHand"
    var hand_mesh := SphereMesh.new()
    hand_mesh.radius = 0.5
    hand_mesh.height = 1.0
    hand_mesh.radial_segments = 14
    hand_mesh.rings = 8
    hand.mesh = hand_mesh
    hand.scale = Vector3(0.105, 0.095, 0.12)
    hand.position = Vector3(0.0, 0.0, -0.02)
    hand.material_override = glove
    hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(hand)
    _ruin_crowbar = root


func _update_ruin_viewmodel(delta: float) -> void:
    if _ruin_viewmodel == null:
        return
    var controller := get_parent() as Main3D
    var holding: bool = controller != null and controller._items != null and not controller._items.selected(peer_id).is_empty()
    if _ruin_crowbar != null:
        _ruin_crowbar.visible = _ruin_force_active and not downed
    if _ruin_force_active:
        _ruin_viewmodel.visible = false
        if _ruin_crowbar != null:
            var progress := clampf(_ruin_force_progress, 0.0, 1.0)
            var lever := sin(progress * PI * 3.0)
            _ruin_crowbar.position = Vector3(0.30, -0.30 + lever * 0.018, -0.52 + lever * 0.035)
            _ruin_crowbar.rotation = Vector3(
                deg_to_rad(-14.0 + lever * 7.0),
                deg_to_rad(35.0),
                deg_to_rad(-20.0 + lever * 12.0)
            )
        return
    _ruin_viewmodel.visible = not downed and not holding
    if not _ruin_viewmodel.visible:
        return
    _ruin_swing_remaining = maxf(_ruin_swing_remaining - delta, 0.0)
    var swing := 0.0
    if _ruin_swing_remaining > 0.0:
        var t: float = 1.0 - _ruin_swing_remaining / 0.26
        swing = sin(clampf(t, 0.0, 1.0) * PI)
    var bob: float = sin(_ruin_bob_phase) * 0.006
    # 竖握 -> 向前下方劈砍：绕 X 轴把刀身从竖直压到接近水平。
    _ruin_viewmodel.position = Vector3(0.42, -0.45, -0.90) + Vector3(0.02 * swing, 0.06 * swing + bob, -0.10 * swing)
    _ruin_viewmodel.rotation = Vector3(
        deg_to_rad(6.0 - 105.0 * swing),
        deg_to_rad(-6.0 + 12.0 * swing),
        deg_to_rad(-4.0 + 10.0 * swing)
    )
    if _ruin_blade_pivot != null:
        _ruin_blade_pivot.rotation.x = deg_to_rad(-3.0 * swing)
    if _ruin_blade_core != null and _ruin_blade_core.material_override is StandardMaterial3D:
        var core_material := _ruin_blade_core.material_override as StandardMaterial3D
        core_material.emission_energy_multiplier = 2.25 + sin(_ruin_bob_phase * 0.7) * 0.12
    if _ruin_blade_light != null:
        _ruin_blade_light.light_energy = 0.52 + sin(_ruin_bob_phase * 0.9) * 0.05


func _dispose_ruin_viewmodel() -> void:
    if _ruin_viewmodel != null and is_instance_valid(_ruin_viewmodel):
        _ruin_viewmodel.queue_free()
    _ruin_viewmodel = null
    if _ruin_crowbar != null and is_instance_valid(_ruin_crowbar):
        _ruin_crowbar.queue_free()
    _ruin_crowbar = null
    _ruin_blade_pivot = null
    _ruin_blade_core = null
    _ruin_blade_glow = null
    _ruin_blade_light = null
    _ruin_force_active = false
    _ruin_force_progress = 0.0
    _ruin_swing_remaining = 0.0


func start_ruin_force() -> void:
    if not _ruin_first_person_mode:
        return
    _ruin_force_active = true
    _ruin_force_progress = 0.0
    _ruin_swing_remaining = 0.0


func set_ruin_force_progress(progress: float) -> void:
    _ruin_force_progress = clampf(progress, 0.0, 1.0)


func stop_ruin_force() -> void:
    _ruin_force_active = false
    _ruin_force_progress = 0.0


## 本地近战挥拳动画。远端玩家仍然走第三人称的 show_attack_animation()。
func play_ruin_attack() -> void:
    if _ruin_first_person_mode and not _ruin_force_active:
        _ruin_swing_remaining = 0.26


func _apply_mouse_look(relative: Vector2) -> void:    # Godot 的角色前方是 -Z；rotation.y 增大时前方朝 -X，
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
    elif _ruin_first_person_mode and _camera != null:
        _camera.global_position = global_position + Vector3.UP * RUIN_EYE_HEIGHT
        _camera.global_rotation = Vector3(-_camera_pitch, _camera_yaw, 0.0)

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
    _ruin_first_person_mode = false
    _ruin_cursor_released = false
    _dispose_ruin_viewmodel()
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
        attack_range_visual.visible = controller != null and not controller.ship_active

func _update_planet_camera(resonance: bool, _delta: float = 0.016) -> void:
    if _camera == null:
        return
    if attack_range_visual != null and resonance:
        attack_range_visual.visible = false

func _release_resonance_mouse() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    Input.use_accumulated_input = true
    _mouse_capture_requested = false

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
    if downed or lava_dead:
        stop_jet()
        sprinting = false
        velocity = Vector3.ZERO
        _has_target_position = false
        return
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
    _ruin_force_cooldown = maxf(_ruin_force_cooldown - delta, 0.0)
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
    if controller.lockpick_active:
        sprinting = false
        velocity = Vector3.ZERO
        return
    if _ruin_force_active:
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
    var ruin_surface: bool = controller.current_planet_id == "ruin" and _ruin_first_person_mode
    if resonance_surface or ruin_surface:
        # 共振星与腐墟星都让角色始终朝向镜头前方；腐墟星第一人称下
        # 这保证攻击锥、交互朝向和联机同步的旋转是同一个方向。
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
        if resonance_surface or ruin_surface:
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
    # 腐墟星第一人称近战：F 是"始终可打"的近战键，手里拿着物资也能挥拳。
    # 左键空手攻击仍然保留，给只用鼠标的玩家。
    if ruin_surface and Input.is_physical_key_pressed(KEY_F) and _attack_cooldown <= 0.0 and scan_lock_remaining <= 0.0 and not _ruin_force_active:
        _attack_cooldown = ATTACK_INTERVAL
        controller.handle_action(peer_id, "ruin_melee")
    # R：不需要撬锁工具，直接用撬棍暴力撬门；主机计时，玩家要留在门口。
    if ruin_surface and Input.is_physical_key_pressed(KEY_R) and _ruin_force_cooldown <= 0.0 and not _ruin_force_active:
        _ruin_force_cooldown = 2.8
        controller.handle_action(peer_id, "ruin_force_door")
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
    if downed or lava_dead:
        stop_jet()
        sprinting = false
        velocity = Vector3.ZERO
        _has_target_position = false
        return
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
            jet_charge = controller._items.spend_jet_reserve(peer_id, delta)
    return next

func stop_jet() -> void:
    jet_active = false
    jet_button_held = false
    _jump_held = 0.0

func capture_health_revision() -> int:
    var state: Vector2i = Vector2i(health, int(downed))
    if state != _captured_health:
        health_revision += 1
        _captured_health = state
    return health_revision

func _update_jet_visual(controller: Main3D) -> void:
    var mounted: bool = controller != null and controller._items != null and controller._items.has_jet(peer_id)
    if mounted and not is_instance_valid(_jet_pack):
        _jet_pack = Node3D.new()
        _jet_pack.name = "SuitOxygenPack"
        _jet_pack.position = Vector3(0, 0.55, 0.4)
        add_child(_jet_pack)
        for index: int in CrewItems3D.EQUIPMENT_CAPACITY:
            var bottle: ItemProp3D = ItemProp3D.create("oxygen")
            _jet_pack.add_child(bottle)
            _jet_bottles.append(bottle)
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
        var count: int = controller._items.oxygen_count(peer_id) if mounted else 0
        for index: int in _jet_bottles.size():
            _jet_bottles[index].visible = index < count
            _jet_bottles[index].position.x = (index - 0.5) * 0.31 if count == 2 else 0.0
        var firing: bool = mounted and jet_active and not downed and not lava_dead
        for flame: MeshInstance3D in _jet_flames:
            flame.visible = firing
            flame.scale.y = 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.07)
        if firing and not _jet_audio.playing:
            _jet_audio.play()
        elif not firing and _jet_audio.playing:
            _jet_audio.stop()
