extends "res://scripts/station_player.gd"

var grip_id: int = -1
var grip_stand: Vector3 = Vector3.ZERO
var cart: AnimatableBody3D
var moving_stage: Node3D
var recovery_count: int = 0

func _ready() -> void:
	super._ready()
	collision_mask = 50 # static ground, peers, and moving deck; cargo handled by pickup
	platform_floor_layers = 32
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	floor_snap_length = 0.35
	step_assist_enabled = true
	_camera_yaw = PI * 0.5
	_camera_yaw_target = _camera_yaw
	_camera_pitch = -0.18
	_camera_pitch_target = _camera_pitch

func _brace() -> void:
	brace_active = grip_id >= 0
	if brace_active and moving_stage != null:
		brace_target = cart.to_global((moving_stage.get("grips") as Array[Vector3])[grip_id])

func _try_small_step(motion_vector: Vector3) -> void:
	if cart != null and bool(cart.call("contains_point", global_position)): return
	super._try_small_step(motion_vector)

func _third_person_movement(input_vector: Vector2) -> Vector3:
	var movement: Vector3 = super._third_person_movement(input_vector)
	if cart != null and grip_id < 0 and bool(cart.get("event_active")) and is_on_floor():
		movement += cart.global_basis.z * sin(float(cart.get("clock")) * 3.0) * 0.009
	return movement

func _physics_tick(delta: float) -> void:
	if paused: return
	# Native move_and_slide carries both free and braced riders. No parent switch,
	# fixed-centre teleport, or manual addition of cart speed to player velocity.
	if grip_id >= 0:
		input_enabled = false
		interaction_locked = true
	super._physics_tick(delta)
	if grip_id >= 0:
		var face_target: Vector3 = brace_target - global_position
		face_target.y = 0.0
		if face_target.length() > 0.1:
			rotation.y = atan2(-face_target.x, -face_target.z)
		_update_core_hands(delta)

func release_grip() -> void:
	grip_id = -1
	brace_active = false
	interaction_locked = false
	input_enabled = true
	velocity = Vector3.ZERO

func _update_core_hands(delta: float) -> void:
	if moving_stage == null or pose == null: return
	var system: Node3D = moving_stage.get("device") as Node3D
	if system == null: return
	var target: Node3D = system.call("pose_target", peer_id) as Node3D
	if target != null: pose.call("tick", delta, target)

func restore_at(world_at: Vector3) -> void:
	release_grip()
	global_position = world_at
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	if camera_guard != null:
		camera_guard.set("max_step", 0.0)
	update_camera(1.0, true)
	camera.reset_physics_interpolation()

func _camera_impl(delta: float, snap: bool = false) -> void:
	if camera_guard == null or camera == null: return
	var target: Vector3 = global_position + Vector3.UP * 1.2
	var forward: Vector3 = Vector3(-sin(_camera_yaw), 0, -cos(_camera_yaw))
	var right: Vector3 = Vector3(cos(_camera_yaw), 0, -sin(_camera_yaw))
	var desired: Vector3 = target - forward * 5.0 * cos(_camera_pitch) + right * 0.4 + Vector3.UP * (2.5 + sin(_camera_pitch) * 4.0)
	camera.global_position = camera_guard.call("position_camera", target, desired, delta, snap) as Vector3
	if camera.global_position.distance_to(target) > 0.02: camera.look_at(target, Vector3.UP)
	camera_guard.call("suppress_near_characters")
