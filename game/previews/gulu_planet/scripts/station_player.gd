extends CharacterBody3D

# Preview adapter. Constants and two pure camera/movement methods are appended
# verbatim from the actual SpacePlayer3D source by assemble_player.py.
var _camera_yaw: float = -PI * 0.5
var _camera_pitch: float = 0.0
var _camera_yaw_target: float = -PI * 0.5
var _camera_pitch_target: float = 0.0
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
var use_first_person: bool = false
var step_assist_enabled: bool = true
var step_count: int = 0
var contacts: int = 0
var input_enabled: bool = true
var camera_guard: RefCounted
var mouse_sensitivity: float = 1.0
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
    visual = (load("res://scenes/protagonist_visual.tscn") as PackedScene).instantiate() as Node3D
    # 与飞船/其他星球一致：主角模型 1.0 比例（共振星洞穴缩放 0.78 是那一关的特例）。
    visual.scale = Vector3.ONE
    add_child(visual)
    camera = Camera3D.new()
    camera.fov = SHIP_FIRST_PERSON_FOV
    camera.near = SHIP_CAMERA_NEAR
    camera.far = 100.0
    camera.current = true
    add_child(camera)
    camera.top_level = true
    _contact_shadow=MeshInstance3D.new()
    var disc: PlaneMesh=PlaneMesh.new()
    disc.size=Vector2(0.95,0.95)
    _contact_shadow.mesh=disc
    var shadow_material: ShaderMaterial=ShaderMaterial.new()
    shadow_material.shader=load("res://contact_shadow.gdshader") as Shader
    _contact_shadow.material_override=shadow_material
    _contact_shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    get_parent().add_child.call_deferred(_contact_shadow)
    _sphere = SphereShape3D.new()
    _sphere.radius = 0.22
    pose=(load("res://scripts/interaction_pose.gd") as Script).new() as RefCounted
    pose.call("setup",self,visual)
    camera_guard = (load("res://scripts/camera_guard.gd") as Script).new() as RefCounted
    camera_guard.call("setup", self)
    update_camera(1.0, true)

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

func _unhandled_input(event: InputEvent) -> void:
    if not is_local_actor or paused:return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var mouse: InputEventMouseMotion = event as InputEventMouseMotion
        var look_sensitivity: float = SHIP_LOOK_SENSITIVITY if use_first_person else THIRD_PERSON_MOUSE_SENSITIVITY
        var pitch_min: float = -SHIP_PITCH_LIMIT if use_first_person else THIRD_PERSON_PITCH_MIN
        var pitch_max: float = SHIP_PITCH_LIMIT if use_first_person else THIRD_PERSON_PITCH_MAX
        _camera_yaw_target -= mouse.relative.x * look_sensitivity * mouse_sensitivity
        _camera_pitch_target = clampf(_camera_pitch_target + mouse.relative.y * look_sensitivity * mouse_sensitivity, pitch_min, pitch_max)
    if event.is_action_pressed("release_mouse"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if event.is_action_pressed("capture_mouse"):
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    if event.is_action_pressed("inspect_first_person"):
        use_first_person = not use_first_person
        visual.visible = not use_first_person
        camera.fov = SHIP_FIRST_PERSON_FOV if use_first_person else 62.0
        camera.near = SHIP_CAMERA_NEAR if use_first_person else 0.04
        _camera_pitch_target = clampf(_camera_pitch_target, -SHIP_PITCH_LIMIT, SHIP_PITCH_LIMIT) if use_first_person else clampf(_camera_pitch_target, THIRD_PERSON_PITCH_MIN, THIRD_PERSON_PITCH_MAX)

func update_camera(delta: float, snap: bool = false) -> void:
    var begin_us: int = Time.get_ticks_usec() if perf_capture else 0
    _camera_impl(delta,snap)
    _record_cost("camera_queries",begin_us)

func _camera_impl(delta: float, snap: bool = false) -> void:
    var target: Vector3 = global_position + Vector3(0, 1.35, 0)
    if use_first_person:
        # 与 space_player_3d.gd 的飞船第一人称完全一致：眼高 1.6 m、FOV 74、俯仰 ±1.25 rad。
        camera.global_position = global_position + Vector3(0, SHIP_EYE_HEIGHT, 0)
        camera.global_rotation = Vector3(-_camera_pitch, _camera_yaw, 0)
        return
    var desired: Vector3 = _third_person_camera_position(target)
    desired = get_parent().call("clamp_cave_camera_position", target, desired) as Vector3
    desired.y = clampf(desired.y, 1.35, 6.1)
    camera.global_position = camera_guard.call("position_camera", target, desired, delta, snap) as Vector3
    if camera.global_position.distance_to(target) > 0.01:
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

# ---- 飞船第一人称（逐值对齐 game/scripts/space_player_3d.gd @ 42519ff） ----
const SHIP_EYE_HEIGHT : float = 1.6
const SHIP_FIRST_PERSON_FOV : float = 74.0
const SHIP_LOOK_SENSITIVITY : float = 0.0020
const SHIP_PITCH_LIMIT : float = 1.25
const SHIP_CAMERA_NEAR : float = 0.05

const SPEED : float = 5.8
const SPRINT_MULTIPLIER : float = 1.65
const THIRD_PERSON_DISTANCE : float = 15.0
const THIRD_PERSON_HEIGHT : float = 8.6
const THIRD_PERSON_SHOULDER : float = 0.9
const THIRD_PERSON_COLLISION_MARGIN : float = 0.28
const THIRD_PERSON_MOUSE_SENSITIVITY : float = 0.0024
const THIRD_PERSON_ROTATION_SMOOTHNESS : float = 24.0
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
