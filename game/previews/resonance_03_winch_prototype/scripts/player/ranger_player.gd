extends CharacterBody3D

# Resonance 03 player controller.
#
# Derived from the proven Resonance 02 preview controller (station_player.gd /
# cart_player.gd), reduced to what this prototype needs: free third-person
# movement, mouse look, swept camera, small-step assist, contact shadow.
# Removed on purpose: networking, carrying, platform riding, multiplayer roster.
# Those belong to the integration step, not to the winch prototype.
#
# Collision layers (project convention):
#   layer 1 (value 1)  = world geometry / floor / props
#   layer 4 (value 8)  = camera blockers (same solids, separate mask bit)
#   layer 5 (value 16) = the player capsule
# The cable is visual-only and has no collider, so it can never launch the player.

const SPEED: float = 4.6
const SPRINT_MULTIPLIER: float = 1.55
const GRAVITY: float = 18.0
const TERMINAL_FALL: float = 26.0
const THIRD_PERSON_DISTANCE: float = 4.9
const THIRD_PERSON_HEIGHT: float = 2.55
const THIRD_PERSON_SHOULDER: float = 0.60
const MOUSE_SENSITIVITY: float = 0.0024
const ROTATION_SMOOTHNESS: float = 22.0
const PITCH_MIN: float = -0.62
const PITCH_MAX: float = 0.34

var camera: Camera3D
var visual: Node3D
var camera_guard: RefCounted
var input_enabled: bool = true
var paused: bool = false
var mouse_sensitivity: float = 1.0
var use_first_person: bool = false
var step_count: int = 0
var spawn_transform: Transform3D
var operating_station: Node = null
# Extra right-shoulder offset while standing at the winch console, so the drum
# does not sit exactly on the sightline to the rail.
var camera_shoulder_offset: float = 0.0

var _camera_yaw: float = PI * 0.5
var _camera_pitch: float = -0.16
var _camera_yaw_target: float = PI * 0.5
var _camera_pitch_target: float = -0.16
var _shoulder_current: float = THIRD_PERSON_SHOULDER
var _contact_shadow: MeshInstance3D
var _sphere: SphereShape3D

func _ready() -> void:
	collision_layer = 16
	collision_mask = 1
	floor_snap_length = 0.28
	floor_max_angle = deg_to_rad(52.0)
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.62
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = 0.86
	add_child(collider)

	visual = (load("res://scenes/protagonist_visual.tscn") as PackedScene).instantiate() as Node3D
	visual.scale = Vector3.ONE * 0.78
	add_child(visual)

	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 160.0
	camera.current = true
	camera.top_level = true
	add_child(camera)

	_sphere = SphereShape3D.new()
	_sphere.radius = 0.24

	camera_guard = (load("res://scripts/player/camera_guard.gd") as Script).new() as RefCounted
	camera_guard.call("setup", self, 9)

	_build_contact_shadow()
	spawn_transform = global_transform
	update_camera(1.0, true)

func _build_contact_shadow() -> void:
	_contact_shadow = MeshInstance3D.new()
	_contact_shadow.name = "ContactShadow"
	var disc: PlaneMesh = PlaneMesh.new()
	disc.size = Vector2(0.92, 0.92)
	_contact_shadow.mesh = disc
	var shadow_material: ShaderMaterial = ShaderMaterial.new()
	shadow_material.shader = load("res://contact_shadow.gdshader") as Shader
	_contact_shadow.material_override = shadow_material
	_contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_contact_shadow.top_level = true
	add_child(_contact_shadow)

func _physics_process(delta: float) -> void:
	if paused:
		return
	_camera_yaw = lerp_angle(_camera_yaw, _camera_yaw_target, 1.0 - exp(-ROTATION_SMOOTHNESS * delta))
	_camera_pitch = lerpf(_camera_pitch, _camera_pitch_target, 1.0 - exp(-ROTATION_SMOOTHNESS * delta))
	_shoulder_current = lerpf(_shoulder_current, THIRD_PERSON_SHOULDER + camera_shoulder_offset, 1.0 - exp(-7.0 * delta))
	rotation.y = _camera_yaw

	var input_vector: Vector2 = Vector2.ZERO
	if input_enabled and operating_station == null:
		input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var move_speed: float = SPEED
	if Input.is_action_pressed("sprint") and input_vector.length() > 0.1:
		move_speed *= SPRINT_MULTIPLIER
	var vertical_velocity: float = 0.0 if is_on_floor() else maxf(velocity.y - GRAVITY * delta, -TERMINAL_FALL)
	var direction: Vector3 = _third_person_movement(input_vector)
	velocity = Vector3(direction.x * move_speed, vertical_velocity, direction.z * move_speed)
	move_and_slide()

	if input_vector.length() > 0.12 and is_on_floor():
		_try_small_step(direction * move_speed * delta)

	if visual != null and visual.has_method("update_state"):
		visual.call("update_state", delta, Vector2(velocity.x, velocity.z), false, false, false, 5, true)

	update_camera(delta)
	_update_contact_shadow()

func _third_person_movement(input_vector: Vector2) -> Vector3:
	var camera_forward: Vector3 = Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
	var camera_right: Vector3 = Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
	return camera_right * input_vector.x + camera_forward * -input_vector.y

func _third_person_camera_position(target: Vector3) -> Vector3:
	var forward: Vector3 = Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
	var right: Vector3 = Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
	var horizontal_distance: float = cos(_camera_pitch) * THIRD_PERSON_DISTANCE
	var vertical_offset: float = THIRD_PERSON_HEIGHT + sin(_camera_pitch) * THIRD_PERSON_DISTANCE
	return target - forward * horizontal_distance + right * _shoulder_current + Vector3.UP * vertical_offset

func update_camera(delta: float, snap: bool = false) -> void:
	if camera == null:
		return
	var target: Vector3 = global_position + Vector3(0.0, 1.32, 0.0)
	if use_first_person:
		camera.global_position = global_position + Vector3(0.0, 1.62, 0.0)
		camera.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)
		return
	var desired: Vector3 = _third_person_camera_position(target)
	desired.y = maxf(desired.y, 0.75)
	var safe: Vector3 = camera_guard.call("position_camera", target, desired, delta, snap) as Vector3
	camera.global_position = safe
	if safe.distance_to(target) > 0.05:
		camera.look_at(target, Vector3.UP)

func _update_contact_shadow() -> void:
	if _contact_shadow == null:
		return
	var from: Vector3 = global_position + Vector3.UP * 0.5
	var to: Vector3 = global_position - Vector3.UP * 0.8
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	_contact_shadow.visible = not hit.is_empty() and not use_first_person
	if hit.is_empty():
		return
	var normal: Vector3 = hit.get("normal", Vector3.UP) as Vector3
	if normal.y < 0.0:
		normal = -normal
	var at: Vector3 = hit.get("position", global_position) as Vector3
	_contact_shadow.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, normal)), at + normal * 0.01)

func _try_small_step(motion: Vector3) -> void:
	if not test_move(global_transform, motion):
		return
	if test_move(global_transform, Vector3.UP * 0.36):
		return
	var raised: Transform3D = global_transform.translated(Vector3.UP * 0.36)
	if test_move(raised, motion):
		return
	var probe: Vector3 = motion.normalized() * 0.34 + motion
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(raised.origin + probe, raised.origin + probe - Vector3.UP * 0.5, 1, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return
	var at: Vector3 = hit.get("position", raised.origin) as Vector3
	var rise: float = at.y - (global_position.y + 0.05)
	if rise > 0.04 and rise <= 0.34:
		global_position += Vector3.UP * (rise + 0.01)
		step_count += 1

func _unhandled_input(event: InputEvent) -> void:
	if paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_camera_yaw_target -= motion.relative.x * MOUSE_SENSITIVITY * mouse_sensitivity
		_camera_pitch_target = clampf(_camera_pitch_target + motion.relative.y * MOUSE_SENSITIVITY * mouse_sensitivity, PITCH_MIN, PITCH_MAX)
	if event.is_action_pressed("pause_menu"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("interact"):
		pass

func teleport_to(at: Vector3, yaw: float = PI * 0.5) -> void:
	global_position = at
	velocity = Vector3.ZERO
	_camera_yaw = yaw
	_camera_yaw_target = yaw
	_camera_pitch = -0.16
	_camera_pitch_target = -0.16
	reset_physics_interpolation()
	update_camera(1.0, true)
	if camera != null:
		camera.reset_physics_interpolation()

func set_operating(station: Node) -> void:
	operating_station = station
	input_enabled = station == null
	if station == null:
		velocity = Vector3.ZERO
