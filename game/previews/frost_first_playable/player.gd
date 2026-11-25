extends SpacePlayer3D

var controls: Dictionary = {}
var launch_velocity: Vector3 = Vector3.ZERO
var launch_time: float = 0.0
var previous_jump: bool = false
var impact_speed: float = 0.0

func configure_ship_camera() -> void:
	# The shared camera constructor calls this hook. Its default planet branch
	# releases the cursor after start_session captured it; frost is always FPS.
	if _camera == null:
		return
	_camera_yaw = 0.0
	_camera_yaw_target = 0.0
	_camera_pitch = 0.0
	_camera_pitch_target = 0.0
	_update_planet_camera(false)
	var director: Node = get_parent()
	if director.game_started and not director._settings_visible and not director._journal_visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	super._ready()
	var sensor: OmniLight3D = get_node_or_null("PlayerSensorLight") as OmniLight3D
	if sensor != null:
		sensor.light_energy = 0.15
		sensor.omni_range = 6

func _input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_yaw_target -= event.relative.x * SHIP_LOOK_SENSITIVITY
		_camera_pitch_target = clampf(_camera_pitch_target + event.relative.y * SHIP_LOOK_SENSITIVITY, -SHIP_PITCH_LIMIT, SHIP_PITCH_LIMIT)

func _update_planet_camera(_resonance: bool, delta: float = 0.016) -> void:
	if _camera == null:
		return
	_camera_yaw = lerp_angle(_camera_yaw, _camera_yaw_target, 1 - exp(-24 * delta))
	_camera_pitch = lerpf(_camera_pitch, _camera_pitch_target, 1 - exp(-24 * delta))
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = SHIP_FIRST_PERSON_FOV
	_camera.far = 1400
	_camera.near = 0.05
	_camera.global_position = global_position + Vector3.UP * SHIP_EYE_HEIGHT
	_camera.global_rotation = Vector3(-_camera_pitch, _camera_yaw, 0)
	_visual.visible = false
	attack_range_visual.visible = false

func _physics_process(_delta: float) -> void:
	# Movement is simulated by the adventure host, including its local player.
	pass

func simulate(delta: float) -> void:
	var director: Node = get_parent()
	var move: Vector2 = controls.get("move", Vector2.ZERO)
	rotation.y = float(controls.get("yaw", rotation.y))
	_network_view_pitch = float(controls.get("pitch", 0.0))
	var held: bool = bool(controls.get("jump", false)) and not downed
	var rising: bool = held and not previous_jump
	previous_jump = held
	jet_button_held = held
	_jump_held = _jump_held + delta if held else 0.0
	var direction: Vector3 = Basis(Vector3.UP, rotation.y) * Vector3(move.x, 0, move.y)
	sprinting = bool(controls.get("sprint", false))
	var speed: float = SPEED * (SPRINT_MULTIPLIER if sprinting else 1.0)
	velocity.x = direction.x * speed if not downed else 0.0
	velocity.z = direction.z * speed if not downed else 0.0
	velocity.y = maxf(velocity.y - GRAVITY * delta, -42)
	if is_on_floor() and rising:
		velocity.y = JUMP_SPEED
	jet_charge = director._items.jet_reserve(peer_id)
	jet_active = held and _jump_held >= JET_HOLD_DELAY and jet_charge > 0 and director._items.has_jet(peer_id)
	if jet_active:
		velocity.y = minf(velocity.y + JET_ACCELERATION * delta, JET_SPEED)
	if launch_time > 0:
		velocity.x += launch_velocity.x
		velocity.z += launch_velocity.z
		launch_time = maxf(0, launch_time - delta)
	impact_speed = minf(impact_speed, velocity.y)
	var horizontal: Vector3 = Vector3(velocity.x,0,velocity.z)*delta
	if is_on_floor() and horizontal.length()>0.001 and test_move(global_transform,horizontal):
		var probe: Vector3 = position+horizontal.normalized()*0.55
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(probe+Vector3.UP*0.46,probe-Vector3.UP*0.05,2)
		var step: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not step.is_empty():
			var rise: float = (step.position as Vector3).y-position.y+0.01
			if rise>0.05 and rise<=0.46 and not test_move(global_transform,Vector3.UP*rise) and not test_move(global_transform.translated(Vector3.UP*rise),horizontal):
				position.y += rise
	move_and_slide()
	if is_on_floor():
		if impact_speed < -13:
			director.hurt(peer_id, maxi(1, int((-impact_speed - 10) / 5)))
		impact_speed = 0
	if position.y < -18:
		director.hurt(peer_id, 5)
		position.y = 0.5

func launch() -> void:
	velocity.y = 15.5
	launch_velocity = Vector3(0, 0, -6)
	launch_time = 1.4
	impact_speed = 0

