extends CharacterBody3D

# -----------------------------------------------------------------------------
# First-person adaption of the Resonance 02+03 ranger.
#
# What changed and why
#   * The camera is no longer a chase boom. It is a rigid child of the character
#     at the visor height and rotated by the mouse. There is no camera_guard
#     sweep, no obstruction shortening, no auto-align and no per-frame position
#     chase, so nothing except the player's own mouse can move the lens.
#   * Yaw is written to the body, pitch only to the camera: standard FPS, and the
#     character always faces where it walks.
#   * The local head (and the third-person arms) move to render layer 2, which
#     only this camera culls. The full character stays in the world for every
#     other player; nothing is deleted from the model.
#   * A temporary viewmodel (first_person_rig.gd) keeps grip / carry / winch
#     legible without re-authoring the hand animations.
#
# The third-person implementation is deliberately left intact below
# (`use_first_person == false`), because this spike has to stay comparable with
# the shipped build and the original project remains untouched.
# -----------------------------------------------------------------------------

# Visor height in world space: the ranger model is authored with the helmet at
# y 1.57 model units and rendered at 0.78 scale, i.e. ~1.22 m. 1.30 m puts the
# lens just above the visor, which keeps the body visible when looking down.
const FIRST_PERSON_EYE_HEIGHT: float = 1.30
const FIRST_PERSON_FOV: float = 74.0
# 0.0022 rad/px = 0.126 deg/px = 2856 px for a full turn. The third-person value
# (0.0014) was tuned for a 4.9 m boom; at eye level it feels sluggish.
const FIRST_PERSON_MOUSE_SENSITIVITY: float = 0.0022
# Pitch is stored as a LOOK angle: positive = down, negative = up. The camera's
# rotation.x is therefore -pitch (a Godot camera looks along -Z, so +rotation.x
# tilts it up). Storing it this way is what makes "mouse down = look down" true
# without an inverted-Y branch anywhere.
const FIRST_PERSON_PITCH_MIN: float = -1.24
const FIRST_PERSON_PITCH_MAX: float = 1.18
const FIRST_PERSON_HIDDEN_LAYER: int = 2
const STEP_SMOOTHING: float = 16.0

var _camera_yaw: float = -PI * 0.5
var _camera_pitch: float = 0.06
var _camera_yaw_target: float = -PI * 0.5
var _camera_pitch_target: float = 0.06
var peer_id: int = 1
var carrying: int = 0
var carrying_id: int = 0
var carry_obstructed: bool = false
var operating_role: String = ""
var brace_active: bool = false
var brace_target: Vector3 = Vector3.ZERO
var pose: RefCounted
var interaction_locked: bool = false
var is_local_actor: bool = true
var remote_position: Vector3 = Vector3.ZERO
var remote_yaw: float = 0.0
var remote_motion: Vector3 = Vector3.ZERO
var camera: Camera3D
var visual: Node3D
var paused: bool = false
var camera_sweep_enabled: bool = true
var use_first_person: bool = true
var step_assist_enabled: bool = true
var step_count: int = 0
var contacts: int = 0
var input_enabled: bool = true
var camera_guard: RefCounted
var mouse_sensitivity: float = 1.0
var fp_rig: Node3D
var fp_console: bool = false
var _eye_offset: float = 0.0
var _camera_world_y: float = 0.0
var _sphere: SphereShape3D
var _contact_shadow: MeshInstance3D
var perf_capture: bool = false
var perf_events: Array = []

func _ready() -> void:
    perf_capture = OS.get_cmdline_user_args().has("--profile-sections")
    collision_layer = 16
    collision_mask = 18
    floor_snap_length = 0.24
    var capsule: CapsuleShape3D = CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.5
    var collider: CollisionShape3D = CollisionShape3D.new()
    collider.shape = capsule
    collider.position.y = 0.8
    add_child(collider)
    visual = (load("res://act23/scenes/protagonist_visual.tscn") as PackedScene).instantiate() as Node3D
    visual.scale = Vector3.ONE * 0.78
    add_child(visual)
    camera = Camera3D.new()
    camera.fov = FIRST_PERSON_FOV
    camera.near = 0.04
    camera.far = 100.0
    camera.current = true
    add_child(camera)
    # The lens rides the body. top_level must be false, otherwise the camera is
    # a world-space node and physics interpolation would make it lag a frame
    # behind the character it is supposed to be attached to.
    camera.top_level = false
    camera.cull_mask = 0xFFFFF ^ FIRST_PERSON_HIDDEN_LAYER
    camera.position = Vector3(0.0, FIRST_PERSON_EYE_HEIGHT, 0.0)
    _contact_shadow=MeshInstance3D.new()
    var disc: PlaneMesh=PlaneMesh.new()
    disc.size=Vector2(0.95,0.95)
    _contact_shadow.mesh=disc
    var shadow_material: ShaderMaterial=ShaderMaterial.new()
    shadow_material.shader=load("res://act23/contact_shadow.gdshader") as Shader
    _contact_shadow.material_override=shadow_material
    _contact_shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    get_parent().add_child.call_deferred(_contact_shadow)
    _sphere = SphereShape3D.new()
    _sphere.radius = 0.22
    pose=(load("res://act23/scripts/interaction_pose.gd") as Script).new() as RefCounted
    pose.call("setup",self,visual)
    camera_guard = (load("res://act23/scripts/camera_guard.gd") as Script).new() as RefCounted
    camera_guard.call("setup", self)
    fp_rig = (load("res://act23/scripts/first_person_rig.gd") as Script).new() as Node3D
    fp_rig.call("setup", self, camera)
    camera.add_child(fp_rig)
    # Only the local owner hides its own head/torso on render layer 2. A remote
    # teammate must keep the complete model, otherwise every other player sees a
    # headless ranger (the layer mask is evaluated by every camera).
    if is_local_actor:
        _mask_local_parts()
    update_camera(1.0, true)

# The local head, the third-person arms and the upper torso go to the hidden
# layer for THIS camera only. The upper body is hidden because the lens sits just
# above the shoulders: with the torso drawn, looking straight down fills the
# frame with a metre of over-exposed suit. Hips, legs and boots stay visible, so
# looking down still shows your own body standing on the deck, and every other
# player's camera keeps rendering the complete model.
func _mask_local_parts() -> void:
    if visual == null:
        return
    var hollow: Array[String] = ["HeadPivot", "LeftArmPivot", "RightArmPivot",
        "LeftElbowPivot", "RightElbowPivot"]
    var head_names: Array[String] = ["Helmet", "Visor", "Jaw", "Neck", "Ear",
        "Antenna", "Collar", "Head"]
    var torso_names: Array[String] = ["Torso", "Chest", "Coat", "Abdomen", "Hips", "Belt",
        "Backpack", "Tank", "Thruster", "PackCore", "PulseStrip", "PlayerIdentifier"]
    for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
        var mesh: MeshInstance3D = node as MeshInstance3D
        var hidden: bool = false
        for token: String in head_names:
            if str(mesh.name).find(token) >= 0:
                hidden = true
                break
        if not hidden:
            for token: String in torso_names:
                if str(mesh.name).find(token) >= 0:
                    hidden = true
                    break
        var cursor: Node = mesh.get_parent()
        while not hidden and cursor != null and cursor != visual:
            if hollow.has(str(cursor.name)):
                hidden = true
            cursor = cursor.get_parent()
        if hidden:
            mesh.layers = FIRST_PERSON_HIDDEN_LAYER

func _physics_process(delta: float) -> void:
    var begin_us: int = Time.get_ticks_usec() if perf_capture else 0
    _physics_tick(delta)
    _record_cost("player_tick",begin_us)

func _record_cost(section: String, begin_us: int) -> void:
    if begin_us == 0:return
    var cost: int = Time.get_ticks_usec()-begin_us
    if cost >= 500:perf_events.append([Time.get_ticks_usec(),section,float(cost)/1000.0])

func _physics_tick(delta: float) -> void:
    if not is_local_actor:
        _tick_remote(delta);return
    if paused:
        return
    if use_first_person:
        # No smoothing on look direction in first person: the mouse is the only
        # writer, and any lerp here would read as input lag.
        _camera_yaw = _camera_yaw_target
        _camera_pitch = _camera_pitch_target
    else:
        _camera_yaw = lerp_angle(_camera_yaw, _camera_yaw_target, 1.0 - exp(-THIRD_PERSON_ROTATION_SMOOTHNESS * delta))
        _camera_pitch = lerpf(_camera_pitch, _camera_pitch_target, 1.0 - exp(-THIRD_PERSON_ROTATION_SMOOTHNESS * delta))
    if carrying==3:
        var device: Node3D=get_parent().get("device") as Node3D
        var desired_yaw: float=_camera_yaw
        if device!=null:desired_yaw=float(device.call("carry_facing_yaw",self,desired_yaw))
        rotation.y=lerp_angle(rotation.y,desired_yaw,1.0-exp(-14.0*delta))
    else:rotation.y = _camera_yaw
    _brace()
    var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down") if input_enabled and not interaction_locked else Vector2.ZERO
    var move_speed: float = SPEED * ((1.15 if Input.is_action_pressed("sprint") else .68) if carrying==3 else (SPRINT_MULTIPLIER if Input.is_action_pressed("sprint") else 1.0))
    if carry_obstructed:move_speed*=.18
    if brace_active:move_speed*=.25
    var vertical_velocity: float = 0.0 if is_on_floor() else maxf(velocity.y - 18.0 * delta, -28.0)
    var movement: Vector3 = _third_person_movement(input_vector)
    velocity = Vector3(movement.x * move_speed, vertical_velocity, movement.z * move_speed)
    if carrying==3:
        var device: Node3D=get_parent().get("device") as Node3D
        if device!=null:
            var fraction: float=float(device.call("carrier_motion_fraction",self,Vector3(velocity.x,0,velocity.z)*delta))
            velocity.x*=fraction;velocity.z*=fraction
    move_and_slide()
    contacts += get_slide_collision_count()
    if step_assist_enabled and is_on_floor() and input_vector.length() > 0.1:
        _try_small_step(movement * move_speed * delta)
    visual.call("update_state", delta, Vector2(velocity.x, velocity.z), false, false, carrying > 0, 5, true)
    # Reuse the visual state update and arm pivots; replace its generic battery.
    var generic_battery: MeshInstance3D=visual.get("_battery") as MeshInstance3D
    if generic_battery!=null:generic_battery.visible=false
    _update_core_hands(delta)
    update_camera(delta)
    _update_contact_shadow()

func _tick_remote(delta: float) -> void:
    collision_layer=16
    global_position=remote_position if multiplayer.is_server() else global_position.lerp(remote_position,1.0-exp(-18.0*delta))
    rotation.y=lerp_angle(rotation.y,remote_yaw,1.0-exp(-20.0*delta))
    velocity=remote_motion
    visual.call("update_state",delta,Vector2(velocity.x,velocity.z),false,false,carrying>0,5,true)
    var battery: MeshInstance3D=visual.get("_battery") as MeshInstance3D
    if battery!=null:battery.visible=false
    _update_core_hands(delta);_update_contact_shadow()

func _update_core_hands(delta: float) -> void:
    var device: Node3D=get_parent().get("device") as Node3D
    if device!=null and pose!=null:pose.call("tick",delta,device)

func _brace() -> void:
    brace_active=false
    if carrying!=0 or operating_role!="" or not Input.is_action_pressed("brace"):return
    if position.y<1.65:return
    var best: float=.60
    for z: float in [.86,3.54]:
        for span: Vector2 in [Vector2(-1.4,.4),Vector2(1.6,2.65)]:
            var grip: Vector3=Vector3(clampf(position.x,span.x,span.y),2.905,z)
            var distance: float=(position+Vector3.UP*1.04).distance_to(grip)
            if distance<best:best=distance;brace_target=grip;brace_active=true

func _update_contact_shadow() -> void:
    if not _contact_shadow.is_inside_tree():return
    var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.45,global_position-Vector3.UP*.7,2,[get_rid()])
    var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
    _contact_shadow.visible=not hit.is_empty() and not use_first_person
    if not hit.is_empty():
        var normal: Vector3=hit["normal"] as Vector3
        if normal.y<0:normal=-normal
        _contact_shadow.global_transform=Transform3D(Basis(Quaternion(Vector3.UP,normal)),(hit["position"] as Vector3)+normal*.008)

func _try_small_step(motion: Vector3) -> void:
    var begin_us: int = Time.get_ticks_usec() if perf_capture else 0
    _small_step_impl(motion)
    _record_cost("step_queries",begin_us)

func _small_step_impl(motion: Vector3) -> void:
    if not test_move(global_transform, motion):
        return
    if test_move(global_transform,Vector3.UP*0.38):
        return
    var raised: Transform3D = global_transform.translated(Vector3.UP * 0.38)
    if test_move(raised, motion):
        return
    var probe: Vector3=motion.normalized()*0.38+motion
    var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(raised.origin + probe, raised.origin + probe - Vector3.UP * 0.50, 2, [get_rid()])
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
    if hit.is_empty():
        return
    var at: Vector3 = hit["position"] as Vector3
    # Existing capsule bottom is origin + 0.05m (0.8 - 1.5/2).
    var rise: float = at.y - (global_position.y+0.05)
    if rise > 0.035 and rise <= 0.36:
        global_position += Vector3.UP * (rise + 0.01)
        step_count += 1
        # The capsule has to move instantly (physics), but the eye must not pop.
        # The offset is paid back over ~0.12 s, which is the same trick an FPS
        # uses for stairs; it is invisible on flat ground because rise is 0.
        _eye_offset = clampf(_eye_offset - (rise + 0.01), -0.42, 0.42)

func _unhandled_input(event: InputEvent) -> void:
    if not is_local_actor or paused:return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var mouse: InputEventMouseMotion = event as InputEventMouseMotion
        # One conversion for both the applied and the asserted value. The event's
        # own `relative` is already a pixel delta, so it is never multiplied by a
        # frame delta (that was the old frame-rate dependency).
        var radians_per_pixel: float = mouse_radians_per_pixel()
        _camera_yaw_target -= mouse.relative.x * radians_per_pixel
        _camera_pitch_target = clampf(_camera_pitch_target + mouse.relative.y * radians_per_pixel,
            pitch_min(), pitch_max())
    if event.is_action_pressed("release_mouse"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if event.is_action_pressed("capture_mouse"):
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func pitch_min() -> float:
    return FIRST_PERSON_PITCH_MIN if use_first_person else THIRD_PERSON_PITCH_MIN

func pitch_max() -> float:
    return FIRST_PERSON_PITCH_MAX if use_first_person else THIRD_PERSON_PITCH_MAX

# Single source of truth for "how far does one mouse pixel turn the view".
# Tests assert the observed input against this, and the settings slider scales
# it, so a duplicated event or a delta-multiplied value cannot hide.
func mouse_radians_per_pixel() -> float:
    var base: float = FIRST_PERSON_MOUSE_SENSITIVITY if use_first_person else THIRD_PERSON_MOUSE_SENSITIVITY
    return base * mouse_sensitivity

func update_camera(delta: float, snap: bool = false) -> void:
    var begin_us: int = Time.get_ticks_usec() if perf_capture else 0
    _camera_impl(delta,snap)
    _record_cost("camera_queries",begin_us)

func _camera_impl(delta: float, snap: bool = false) -> void:
    var target: Vector3 = global_position + Vector3(0, 1.35, 0)
    if use_first_person:
        # Rigid attachment: position comes from the body transform, orientation
        # only from the mouse. Nothing here reads geometry, so no wall can push
        # the lens and no state can steal the view.
        #
        # The one deliberate exception is vertical, and it has to be solved in
        # WORLD space: the camera is a child of the body, so smoothing its local
        # y does nothing when the body itself jumps. The capsule steps 0.27 m per
        # stair instantly (it must, or move_and_slide would not climb), the eye
        # follows at a bounded 4 m/s, and the difference is carried as a local
        # offset. Clamping the offset alone was not enough: six stairs in half a
        # second saturated it and the lens ended up glued to the body again.
        _eye_offset = lerpf(_eye_offset, 0.0, 1.0 - exp(-STEP_SMOOTHING * delta))
        var wanted_world: float = global_position.y + FIRST_PERSON_EYE_HEIGHT + _eye_offset
        if snap or _camera_world_y == 0.0:
            _camera_world_y = wanted_world
            _eye_offset = 0.0
            wanted_world = global_position.y + FIRST_PERSON_EYE_HEIGHT
        var max_travel: float = 4.0 * delta
        _camera_world_y = clampf(wanted_world, _camera_world_y - max_travel, _camera_world_y + max_travel)
        camera.position = Vector3(0.0, _camera_world_y - global_position.y, 0.0)
        _eye_offset = clampf(camera.position.y - FIRST_PERSON_EYE_HEIGHT, -0.65, 0.30)
        camera.rotation = Vector3(-_camera_pitch, wrapf(_camera_yaw - rotation.y, -PI, PI), 0.0)
        if fp_rig != null:
            fp_rig.call("tick", delta)
        return
    var desired: Vector3 = _third_person_camera_position(target)
    desired = get_parent().call("clamp_cave_camera_position", target, desired) as Vector3
    desired.y = clampf(desired.y, 1.35, 6.1)
    camera.global_position = camera_guard.call("position_camera", target, desired, delta, snap) as Vector3
    var offset: Vector3 = target - camera.global_position
    if offset.length() > 0.01:
        if Vector2(offset.x, offset.z).length() < 0.32:
            camera.basis = Basis.looking_at(offset, Vector3(-sin(_camera_yaw), 0, -cos(_camera_yaw)))
        else:
            camera.look_at(target, Vector3.UP)
    camera_guard.call("suppress_near_characters")

func _resolve_camera(target: Vector3, desired: Vector3) -> Vector3:
    var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
    if camera_sweep_enabled:
        var shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
        shape_query.shape = _sphere
        shape_query.transform = Transform3D(Basis.IDENTITY, target)
        shape_query.motion = desired - target
        shape_query.margin = 0.035
        shape_query.collision_mask = 4
        shape_query.exclude = [get_rid()]
        var result: PackedFloat32Array = space.cast_motion(shape_query)
        var fraction: float = result[0] if not result.is_empty() else 1.0
        return target + shape_query.motion * maxf(0.0, fraction - 0.012)
    # Baseline project algorithm: a center ray and a 0.8m minimum.
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(target, desired, 4, [get_rid()])
    var hit: Dictionary = space.intersect_ray(query)
    if hit.is_empty():
        return desired
    var hit_position: Vector3 = hit["position"] as Vector3
    var direction: Vector3 = (desired - target).normalized()
    return target + direction * minf(target.distance_to(desired), maxf(0.8, target.distance_to(hit_position) - THIRD_PERSON_COLLISION_MARGIN))

func camera_overlap() -> bool:
    var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
    query.shape = _sphere
    query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
    query.collision_mask = 4
    query.exclude = [get_rid()]
    return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

const SPEED : float = 5.8
const SPRINT_MULTIPLIER : float = 1.65
const THIRD_PERSON_DISTANCE : float = 15.0
const THIRD_PERSON_HEIGHT : float = 8.6
const THIRD_PERSON_SHOULDER : float = 0.9
const THIRD_PERSON_COLLISION_MARGIN : float = 0.28
# 0.0014 rad/px = 0.080 deg/px = 4500 px for a full turn. The old 0.0024
# (0.138 deg/px) was measured to be applied exactly once, so it was not a
# duplicated-event bug - it was simply 70% too fast for a 4.9 m chase camera.
# The settings slider still scales this by 0.4..2.0.
const THIRD_PERSON_MOUSE_SENSITIVITY : float = 0.0014
const THIRD_PERSON_ROTATION_SMOOTHNESS : float = 18.0
const THIRD_PERSON_CAMERA_SMOOTHNESS : float = 20.0
const THIRD_PERSON_PITCH_MIN : float = -0.58
const THIRD_PERSON_PITCH_MAX : float = 0.30

func _third_person_camera_position(target: Vector3) -> Vector3:
    var forward: Vector3 = Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
    var right: Vector3 = Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
    var horizontal_distance: float = cos(_camera_pitch) * THIRD_PERSON_DISTANCE
    var vertical_offset: float = THIRD_PERSON_HEIGHT + sin(_camera_pitch) * THIRD_PERSON_DISTANCE
    return target - forward * horizontal_distance + right * THIRD_PERSON_SHOULDER + Vector3.UP * vertical_offset

func _third_person_movement(input_vector: Vector2) -> Vector3:
    var camera_forward: Vector3 = Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
    var camera_right: Vector3 = Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
    return camera_right * input_vector.x + camera_forward * -input_vector.y
