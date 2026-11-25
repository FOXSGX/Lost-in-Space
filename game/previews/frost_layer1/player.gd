extends SpacePlayer3D
# Use the current shared capsule, speeds, jump and two-resource oxygen jet.
# Preview camera adapter only; no change to the official planet controller.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_yaw_target -= event.relative.x * SHIP_LOOK_SENSITIVITY
		_camera_pitch_target = clampf(_camera_pitch_target + event.relative.y * SHIP_LOOK_SENSITIVITY, -SHIP_PITCH_LIMIT, SHIP_PITCH_LIMIT)

func _update_planet_camera(_resonance: bool, delta: float = 0.016) -> void:
	_camera_yaw = lerp_angle(_camera_yaw, _camera_yaw_target, 1.0 - exp(-24.0 * delta))
	_camera_pitch = lerpf(_camera_pitch, _camera_pitch_target, 1.0 - exp(-24.0 * delta))
	rotation.y = _camera_yaw
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = SHIP_FIRST_PERSON_FOV
	_camera.near = 0.05
	_camera.global_position = global_position + Vector3.UP * SHIP_EYE_HEIGHT
	_camera.global_rotation = Vector3(-_camera_pitch, _camera_yaw, 0)
	_visual.visible = false
	attack_range_visual.visible = false

func _physics_process(delta: float) -> void:
	var controller: Main3D = get_parent() as Main3D
	jet_active = false
	if downed or controller._settings_visible:
		stop_jet()
		velocity = Vector3(0, velocity.y - GRAVITY * delta if not is_on_floor() else 0.0, 0)
		move_and_slide()
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement: Vector3 = _third_person_movement(input_vector)
	sprinting = Input.is_action_pressed("sprint")
	var speed: float = SPEED * (SPRINT_MULTIPLIER if sprinting else 1.0) * controller._items.move_multiplier(peer_id)
	velocity = Vector3(movement.x * speed, _jump_velocity(velocity.y, delta), movement.z * speed)
	move_and_slide()
	for action: String in ["interact", "item_drop", "slot_1", "slot_2", "item_use"]:
		if Input.is_action_just_pressed(action):
			controller.handle_action(peer_id, action)
