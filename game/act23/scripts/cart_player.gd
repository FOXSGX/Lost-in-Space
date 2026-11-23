extends "res://act23/scripts/station_player.gd"

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
	_camera_yaw = PI
	_camera_yaw_target = _camera_yaw
	_camera_pitch = 0.06
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

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)

func _physics_tick(delta: float) -> void:
	if paused: return
	# REMOVED (first-person spike): the old rule "after 1.2 s without mouse input,
	# lerp the yaw toward the cart heading". It existed to keep a 4.9 m chase boom
	# from leaving the vehicle out of frame through the bend. At eye level it is a
	# camera that steals the view while the player is reading the track, and the
	# rider can already turn with the mouse, so it is gone rather than retuned.
	# Native move_and_slide carries both free and braced riders. No parent switch,
	# fixed-centre teleport, or manual addition of cart speed to player velocity.
	if grip_id >= 0:
		input_enabled = false
		interaction_locked = true
	super._physics_tick(delta)
	if grip_id >= 0:
		var face_target: Vector3 = brace_target - global_position
		face_target.y = 0.0
		if face_target.length() > 0.1 and not use_first_person:
			# Third person only. The braced stance turns the BODY toward the rail so
			# the ranger reads as "holding on" from behind. In first person that
			# would snap the view 90 degrees to the railing, so the body keeps
			# facing where the player looks and the arms reach sideways instead -
			# the hands stay where the rail actually is.
			rotation.y = atan2(-face_target.x, -face_target.z)
		_update_core_hands(delta)
		# In third person the forced rotation has to be followed by a camera
		# re-solve; in first person the camera compensates for any body yaw, so
		# this is a no-op there and stays for the preserved third-person path.
		update_camera(delta)

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
	if use_first_person:
		# One camera implementation for the whole project: the rider inherits the
		# rigid eye-level lens from station_player.gd. The cart does NOT get its own
		# first-person variant, which is exactly how the old build ended up with two
		# behaving differently on the deck versus on foot.
		super._camera_impl(delta, snap)
		return
	var target: Vector3 = global_position + Vector3.UP * 1.45
	var forward: Vector3 = Vector3(-sin(_camera_yaw), 0, -cos(_camera_yaw))
	var right: Vector3 = Vector3(cos(_camera_yaw), 0, -sin(_camera_yaw))
	var desired: Vector3 = target - forward * (4.90 * cos(_camera_pitch)) + right * 0.42 \
		+ Vector3.UP * (0.95 + sin(_camera_pitch) * 3.0)
	# A teleport (grip snap, rescue, reset) must never drag the lens across the
	# level through every wall; snap the boom instead of interpolating it.
	var teleported: bool = camera.global_position.distance_to(target) > 10.0
	camera.global_position = camera_guard.call("position_camera", target, desired, delta, snap or teleported) as Vector3
	camera_basis_toward(target)
	camera_guard.call("suppress_near_characters")

func camera_basis_toward(target: Vector3) -> void:
	var offset: Vector3 = target - camera.global_position
	if offset.length() < 0.02:
		return
	# The narrow-space lift can put the lens almost directly above the rider;
	# looking_at() with Vector3.UP is degenerate there and would spin around Z.
	# Use the player's horizontal forward as the up reference instead.
	if Vector2(offset.x, offset.z).length() < 0.32:
		var up_ref: Vector3 = Vector3(-sin(_camera_yaw), 0.0, -cos(_camera_yaw))
		camera.basis = Basis.looking_at(offset, up_ref)
	else:
		camera.look_at(target, Vector3.UP)
