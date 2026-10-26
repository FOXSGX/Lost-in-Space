extends CharacterBody3D

# Preview adapter. Constants and two pure camera/movement methods are appended
# verbatim from the actual SpacePlayer3D source by assemble_player.py.
var _camera_yaw: float = -PI * 0.5
var _camera_pitch: float = -0.18
var _camera_yaw_target: float = -PI * 0.5
var _camera_pitch_target: float = -0.18
var peer_id: int = 1
var carrying: int = 0
var carrying_id: int = 0
var _carry_pose_blend: float = 0.0
var camera: Camera3D
var visual: Node3D
var paused: bool = false
var camera_sweep_enabled: bool = true
var use_first_person: bool = false
var step_assist_enabled: bool = true
var step_count: int = 0
var contacts: int = 0
var input_enabled: bool = true
var _sphere: SphereShape3D
var _contact_shadow: MeshInstance3D

func _ready() -> void:
    collision_layer = 1
    collision_mask = 2
    floor_snap_length = 0.24
    var capsule: CapsuleShape3D = CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.5
    var collider: CollisionShape3D = CollisionShape3D.new()
    collider.shape = capsule
    collider.position.y = 0.8
    add_child(collider)
    visual = (load("res://scenes/protagonist_visual.tscn") as PackedScene).instantiate() as Node3D
    visual.scale = Vector3.ONE * 0.78
    add_child(visual)
    camera = Camera3D.new()
    camera.fov = 62.0
    camera.near = 0.04
    camera.far = 100.0
    camera.current = true
    add_child(camera)
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
    update_camera(1.0, true)

func _physics_process(delta: float) -> void:
    if paused:
        return
    _camera_yaw = lerp_angle(_camera_yaw, _camera_yaw_target, 1.0 - exp(-THIRD_PERSON_ROTATION_SMOOTHNESS * delta))
    _camera_pitch = lerpf(_camera_pitch, _camera_pitch_target, 1.0 - exp(-THIRD_PERSON_ROTATION_SMOOTHNESS * delta))
    rotation.y = _camera_yaw
    var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down") if input_enabled else Vector2.ZERO
    var move_speed: float = SPEED * (SPRINT_MULTIPLIER if Input.is_action_pressed("sprint") else 1.0)
    var vertical_velocity: float = 0.0 if is_on_floor() else maxf(velocity.y - 18.0 * delta, -28.0)
    var movement: Vector3 = _third_person_movement(input_vector)
    velocity = Vector3(movement.x * move_speed, vertical_velocity, movement.z * move_speed)
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

func _update_core_hands(delta: float) -> void:
    _carry_pose_blend=move_toward(_carry_pose_blend,1.0 if carrying==3 else 0.0,delta*5)
    if carrying!=3:return
    var device: Node3D=get_parent().get("device") as Node3D
    if device==null:return
    var core: RigidBody3D=device.get("core") as RigidBody3D
    if core==null:return
    for key: String in ["_left_arm","_right_arm"]:
        var arm: Node3D=visual.get(key) as Node3D
        if arm==null:continue
        var side: float=-1.0 if key=="_left_arm" else 1.0
        var grip: Vector3=core.global_position+Vector3.UP*.52+global_basis.x*side*.19
        var local_direction: Vector3=((arm.get_parent() as Node3D).global_basis.inverse()*(grip-arm.global_position)).normalized()
        var rotation_target: Quaternion=Quaternion(Vector3.DOWN,local_direction)
        arm.quaternion=arm.quaternion.slerp(rotation_target,_carry_pose_blend)

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
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        var mouse: InputEventMouseMotion = event as InputEventMouseMotion
        _camera_yaw_target -= mouse.relative.x * THIRD_PERSON_MOUSE_SENSITIVITY
        _camera_pitch_target = clampf(_camera_pitch_target + mouse.relative.y * THIRD_PERSON_MOUSE_SENSITIVITY, THIRD_PERSON_PITCH_MIN, THIRD_PERSON_PITCH_MAX)
    if event.is_action_pressed("release_mouse"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if event.is_action_pressed("capture_mouse"):
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    if event.is_action_pressed("inspect_first_person"):
        use_first_person = not use_first_person
        visual.visible = not use_first_person

func update_camera(delta: float, snap: bool = false) -> void:
    var target: Vector3 = global_position + Vector3(0, 0.9, 0)
    if use_first_person:
        camera.global_position = global_position + Vector3(0, 1.65, 0)
        camera.rotation = Vector3(_camera_pitch, _camera_yaw, 0)
        return
    var desired: Vector3 = _third_person_camera_position(target)
    # Same stage-level clamp contract used by SpacePlayer3D. This small chamber
    # constrains the 15m desired boom without changing the shared game constants.
    desired = get_parent().call("clamp_cave_camera_position",target,desired) as Vector3
    desired.y = clampf(desired.y, 1.1, 6.1)
    desired = _resolve_camera(target, desired)
    var next: Vector3 = desired if snap else camera.global_position.lerp(desired, 1.0 - exp(-THIRD_PERSON_CAMERA_SMOOTHNESS * delta))
    if camera_sweep_enabled:
        next = _resolve_camera(target, next)
    camera.global_position = next
    camera.look_at(target, Vector3.UP)

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
