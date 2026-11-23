class_name EchoPlayer
extends CharacterBody3D
## First-person controller for Resonance 04.
##
## Design rules (see docs/CAMERA_CONTROL_SPEC.md):
##  * the camera sits at the player's eye, inside the capsule, not on a boom;
##  * mouse look is applied once per event, in `_input()`, never multiplied by
##    delta and never smoothed a second time;
##  * the eye follows the physics body with render-frame interpolation, so there
##    is no rubber-banding, no 60 Hz stepping and no camera collision spring;
##  * the local body is drawn on its own render layer and skipped by this
##    camera; a dedicated first-person viewmodel (arms) is the only body the
##    player sees.
##
## Gameplay authority still lives in ResonanceGame; this class only owns input,
## movement, carrying and the view.

signal prompt_changed(text: String)
signal interactable_changed(target: Node)
signal view_settings_changed(sensitivity: float, invert: bool)
signal menu_toggled(open: bool)
signal carry_changed(crystal: Node)
## Co-op pickup interception: on the client, presses the pickup key with a free
## hand do not attach the crystal locally; the game forwards the request to the
## host and calls `pick_up` again only after the grant returns. Solo / host keep
## the instant local pickup.
signal pickup_requested(crystal: Node)

const SPEED := 5.2
const CARRY_SPEED := 3.9
const SPRINT_MULTIPLIER := 1.45
const JUMP_VELOCITY := 6.0
const GRAVITY := 18.0

## --- eye / mouse ----------------------------------------------------------
## Sensitivity is radians per screen pixel, applied exactly once per event.
## 0.0022 rad/px = 0.126 deg/px = ~1260 px for a full 360 turn.
const MOUSE_SENSITIVITY := 0.0022
const SENSITIVITY_MIN := 0.0007
const SENSITIVITY_MAX := 0.0080
## Eye height inside the 1.55 m capsule. The capsule top is 1.55 m, so 1.42 m
## leaves the helmet out of the near plane and keeps the lens out of the floor.
const EYE_HEIGHT := 1.42
const CAMERA_PITCH_MIN := -1.32   # ~ -75.6 deg, looking down
const CAMERA_PITCH_MAX := 1.32    # ~ +75.6 deg, looking up
const CAMERA_NEAR := 0.045
const CAMERA_FOV := 72.0
const CAMERA_AIM_RATE := 9.0
## Spawn look direction: slightly down, level horizon at eye height.
const SPAWN_PITCH := -0.06

const INTERACT_REACH := 3.1
const PICKUP_REACH := 3.2

## Player capsule: 1.55 m tall, radius 0.38. The shape centre must sit at half
## the height so the capsule bottom is exactly on the body origin; otherwise the
## feet sink 7.5 cm into the floor.
const PLAYER_CAPSULE_HEIGHT := 1.55
const PLAYER_CAPSULE_RADIUS := 0.38
const PLAYER_CAPSULE_CENTER := 0.775

## Render layers. The third-person body is kept complete for future co-op
## observers but is not drawn by this player's camera. The viewmodel is drawn
## only by the first-person camera.
const BODY_RENDER_LAYER := 16   # layer 5: local player body
const VIEWMODEL_RENDER_LAYER := 32  # layer 6: first-person viewmodel
const LOCAL_CAMERA_CULL_MASK := 1 | VIEWMODEL_RENDER_LAYER

## Carried-crystal hold: low and to the right, so a 1.45 m shard never covers
## the centre of the screen. The forward distance is swept against the world so
## the crystal cannot enter a wall.
const HOLD_RIGHT := 0.52
const HOLD_HEIGHT := 0.10
const HOLD_FORWARD := 0.85
const HOLD_MIN_FORWARD := 0.40

const SETTINGS_PATH := "user://resonance04_fp_settings.cfg"

var player_id: int = 1
var device_id: int = 0
var carrying: PortableCrystal = null
var input_enabled: bool = true
var spawn_position: Vector3 = Vector3(0.0, 0.2, 9.0)
var current_prompt: String = ""
var current_target: Node = null
var camera: Camera3D
var camera_pivot: Node3D
var camera_boom: Node3D
var hold_point: Node3D
var viewmodel: FPViewmodel
var visual: Act4ProtagonistVisual

## Co-op pickup interception: when true the caller owns the pickup decision.
var coop_pickup_gate: bool = false

## Last pickup request the game answered "pending" so a grant can find the
## crystal even if the player turned their view between press and grant.
var pending_pickup: PortableCrystal = null

## Co-op / freight links. Kept as Node so this script does not form a cyclic
## class_name dependency with FreightPlatform.
var is_remote: bool = false
var freight_platform: Node = null
var platform_control: Node = null
var grab_platform: Node = null
var grab_local: Vector3 = Vector3.ZERO
var grab_point_id: String = ""

var mouse_sensitivity: float = MOUSE_SENSITIVITY
var invert_y: bool = false
var menu_open: bool = false

var _yaw: float = 0.0
var _pitch: float = SPAWN_PITCH
var _aim_yaw: float = 0.0
var _aim_pitch: float = SPAWN_PITCH
var _aim_active: bool = false
var _eye_position: Vector3 = Vector3.ZERO
var _prev_body_position: Vector3 = Vector3.ZERO
var _curr_body_position: Vector3 = Vector3.ZERO
var _interp_ready: bool = false
var _carry_probe: SphereShape3D
var _hold_forward: float = HOLD_FORWARD
var _shake_trauma: float = 0.0
var _shake_decay: float = 1.0
var _shake_clock: float = 0.0
var _mouse_captured: bool = false
## Capturing the mouse (startup, alt-tab, click-to-recapture) makes Windows warp
## the cursor to the window centre. Godot reports that warp as one huge
## MouseMotion event; without a short guard the view snaps to a random yaw.
var _motion_guard_until: int = 0
var _footstep_clock: float = 0.0
var _carry_sway: float = 0.0
var _interact_down: bool = false
var _pickup_down: bool = false
var _drop_down: bool = false
var _rotate_down: bool = false
var _reach_time: float = 0.0
var _near_wall_forward: float = 4.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	collision_layer = 2
	collision_mask = 1 | 2 | 4 | 8
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.42
	_build_body()
	if is_remote:
		# Remote co-op body: visible to everyone, owns no camera, no viewmodel
		# and no input. Its transform is set by the network adapter.
		_set_render_layer(visual, 1)
		collision_mask = 0
		spawn_position = global_position
		_prev_body_position = global_position
		_curr_body_position = global_position
		_interp_ready = true
		return
	_build_camera()
	_build_viewmodel()
	spawn_position = global_position
	_prev_body_position = global_position
	_curr_body_position = global_position
	_eye_position = global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	_interp_ready = true
	load_settings()
	# The mouse is captured from the first frame: a first-person game must
	# never require the player to guess that they have to click the viewport.
	_capture_mouse.call_deferred()


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true
	_motion_guard_until = Time.get_ticks_msec() + 160


func _build_body() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "PlayerShape"
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = PLAYER_CAPSULE_RADIUS
	capsule.height = PLAYER_CAPSULE_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0.0, PLAYER_CAPSULE_CENTER, 0.0)
	add_child(shape)

	visual = Act4ProtagonistVisual.new()
	visual.name = "ProtagonistVisual"
	visual.scale = Vector3.ONE * 0.82
	visual.set_team_color(Color("#66e0ff") if not is_remote else Color("#ffb45c"))
	add_child(visual)
	# The complete body stays in the tree (future co-op observers need it) but
	# this camera's cull mask does not include its layer, so the helmet can
	# never fill the view.
	_set_render_layer(visual, 1 if is_remote else BODY_RENDER_LAYER)

	hold_point = Node3D.new()
	hold_point.name = "HoldPoint"
	hold_point.position = Vector3(HOLD_RIGHT, HOLD_HEIGHT, -HOLD_FORWARD)
	add_child(hold_point)

	if is_remote:
		return
	# Small suit fill so the cave floor next to the player never goes fully
	# black. The directional suit lamp on the camera does the long throw.
	var suit_fill: OmniLight3D = OmniLight3D.new()
	suit_fill.name = "SuitFill"
	suit_fill.position = Vector3(0.0, 1.3, -0.2)
	suit_fill.light_color = Color(1.0, 0.82, 0.62)
	suit_fill.light_energy = 1.1
	suit_fill.omni_range = 6.0
	suit_fill.omni_attenuation = 1.4
	suit_fill.shadow_enabled = false
	# World only: the viewmodel owns its own small light so it stays readable
	# without being blown out by the suit fill behind the lens.
	suit_fill.light_cull_mask = 1
	add_child(suit_fill)


func _set_render_layer(root: Node, layer_value: int) -> void:
	# Render layers only exist on VisualInstance3D; walk the whole visual tree so
	# a skin swapped in later is covered as well.
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		var instance: VisualInstance3D = node as VisualInstance3D
		if instance != null:
			instance.layers = layer_value
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = layer_value


func _build_camera() -> void:
	# Yaw pivot. top_level keeps the body rotation out of the camera transform,
	# so turning the character can never add to the camera yaw.
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.top_level = true
	camera_pivot.position = global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	add_child(camera_pivot)

	# Pitch node. rotation.x > 0 looks up (verified in probe_camera).
	camera_boom = Node3D.new()
	camera_boom.name = "CameraBoom"
	camera_pivot.add_child(camera_boom)

	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.fov = CAMERA_FOV
	camera.near = CAMERA_NEAR
	camera.far = 180.0
	camera.current = true
	camera.position = Vector3.ZERO
	camera.cull_mask = LOCAL_CAMERA_CULL_MASK
	camera_boom.add_child(camera)

	# Suit lamp: the cave is deliberately dark, so the player carries the light
	# that makes the next crystal readable.
	var suit_lamp: SpotLight3D = SpotLight3D.new()
	suit_lamp.name = "SuitLamp"
	suit_lamp.position = Vector3(0.18, -0.04, 0.0)
	suit_lamp.light_color = Color(1.0, 0.88, 0.72)
	suit_lamp.light_energy = 4.2
	suit_lamp.spot_range = 24.0
	suit_lamp.spot_angle = 46.0
	suit_lamp.spot_angle_attenuation = 1.35
	suit_lamp.shadow_enabled = false
	suit_lamp.light_cull_mask = 1
	camera.add_child(suit_lamp)
	_apply_view()


func _build_viewmodel() -> void:
	viewmodel = FPViewmodel.new()
	viewmodel.name = "Viewmodel"
	viewmodel.render_layer = VIEWMODEL_RENDER_LAYER
	camera.add_child(viewmodel)
	# Dedicated, very small key + cyan rim for the arms. light_cull_mask keeps
	# them from touching the world, so the cave lighting stays unchanged.
	var key: OmniLight3D = OmniLight3D.new()
	key.name = "ViewmodelKey"
	key.position = Vector3(0.12, 0.18, 0.10)
	key.light_color = Color(1.0, 0.86, 0.70)
	key.light_energy = 0.72
	key.omni_range = 1.45
	key.omni_attenuation = 1.1
	key.shadow_enabled = false
	key.light_cull_mask = VIEWMODEL_RENDER_LAYER
	camera.add_child(key)
	var rim: OmniLight3D = OmniLight3D.new()
	rim.name = "ViewmodelRim"
	rim.position = Vector3(-0.30, 0.10, 0.06)
	rim.light_color = Color(0.42, 0.82, 1.0)
	rim.light_energy = 0.65
	rim.omni_range = 1.3
	rim.omni_attenuation = 1.2
	rim.shadow_enabled = false
	rim.light_cull_mask = VIEWMODEL_RENDER_LAYER
	camera.add_child(rim)


func _apply_view() -> void:
	if camera_pivot == null:
		return
	camera_pivot.rotation = Vector3(0.0, _yaw, 0.0)
	if camera_boom != null:
		camera_boom.rotation = Vector3(_pitch, 0.0, 0.0)


## Mouse look lives in _input, not _unhandled_input: HUD panels must never be
## able to swallow a mouse-motion event and make the view stutter.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if menu_open or not _mouse_captured:
			return
		# screen_relative is in physical screen pixels, so the sensitivity does
		# not change with the window scale / stretch mode. Never multiply by
		# delta: mouse motion is already a displacement, not a rate.
		var delta_px: Vector2 = motion.screen_relative
		if delta_px == Vector2.ZERO:
			delta_px = motion.relative
		if delta_px == Vector2.ZERO:
			return
		if Time.get_ticks_msec() < _motion_guard_until:
			# Swallow the synthetic warp produced by the capture itself.
			return
		_aim_active = false
		_yaw = wrapf(_yaw - delta_px.x * mouse_sensitivity, -PI, PI)
		var pitch_direction: float = delta_px.y
		if invert_y:
			pitch_direction = -pitch_direction
		_pitch = clampf(_pitch - pitch_direction * mouse_sensitivity, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
		_apply_view()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key: int = (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			toggle_menu()
			get_viewport().set_input_as_handled()
		elif menu_open and key == KEY_BRACKETLEFT:
			set_sensitivity(mouse_sensitivity / 1.15)
		elif menu_open and key == KEY_BRACKETRIGHT:
			set_sensitivity(mouse_sensitivity * 1.15)
		elif menu_open and key == KEY_Y:
			set_invert_y(not invert_y)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not _mouse_captured and not menu_open:
			_capture_mouse()


func _notification(what: int) -> void:
	# Windows can drop the capture when the window loses focus. If the player
	# never asked for the settings menu (Esc), restore capture when we come back.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _mouse_captured and not menu_open:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if camera_pivot == null:
		return
	if _aim_active:
		var blend: float = 1.0 - exp(-CAMERA_AIM_RATE * delta)
		_yaw = lerp_angle(_yaw, _aim_yaw, blend)
		_pitch = lerpf(_pitch, _aim_pitch, blend)
		if absf(angle_difference(_yaw, _aim_yaw)) < 0.004 and absf(_pitch - _aim_pitch) < 0.004:
			_yaw = _aim_yaw
			_pitch = _aim_pitch
			_aim_active = false
	_update_eye(delta)
	_apply_view()
	_apply_shake(delta)
	_update_viewmodel(delta)


## First person: the eye sits at a fixed offset from the body and is
## interpolated between physics ticks on the render frame. That is what makes a
## 60 Hz body look smooth on a 144 Hz screen without any follow damping (which
## would rubber-band and, worse, drag the lens through walls).
func _update_eye(_delta: float) -> void:
	var target: Vector3
	if Engine.get_physics_frames() > 0:
		var fraction: float = Engine.get_physics_interpolation_fraction()
		target = _prev_body_position.lerp(_curr_body_position, clampf(fraction, 0.0, 1.0))
	else:
		target = global_position
	target.y += EYE_HEIGHT
	_eye_position = target
	camera_pivot.global_position = _eye_position


func _apply_shake(delta: float) -> void:
	if camera == null:
		return
	_shake_clock += delta
	_shake_trauma = maxf(_shake_trauma - delta * _shake_decay, 0.0)
	if _shake_trauma <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		return
	# First person: same trauma model, smaller amplitude. Big offsets at 1.4 m
	# from the floor read as the whole room sliding, not as an impact.
	var amplitude: float = _shake_trauma * _shake_trauma
	camera.h_offset = sin(_shake_clock * 43.0) * 0.045 * amplitude
	camera.v_offset = sin(_shake_clock * 57.0 + 1.3) * 0.032 * amplitude


func shake(strength: float = 0.12, duration: float = 0.28) -> void:
	_shake_trauma = clampf(maxf(_shake_trauma, strength * 1.9), 0.0, 1.0)
	_shake_decay = 1.0 / maxf(duration, 0.05)


func _physics_process(delta: float) -> void:
	_prev_body_position = _curr_body_position
	if is_remote:
		_curr_body_position = global_position
		return
	_update_look_target()
	if menu_open:
		velocity = Vector3.ZERO
		_curr_body_position = global_position
		return
	if not input_enabled:
		velocity.x = 0.0
		velocity.z = 0.0
		_visual_tick(delta)
		_curr_body_position = global_position
		return

	# --- grabbed rail -----------------------------------------------------
	# The platform owns the stand position and the velocity. The body is
	# pinned to the deck, so a tilt cannot throw the player; the camera stays
	# free and upright.
	if grab_platform != null:
		var grab_node: Node3D = grab_platform as Node3D
		if grab_node == null or not is_instance_valid(grab_node):
			grab_platform = null
			grab_point_id = ""
		else:
			global_position = grab_node.to_global(grab_local)
			velocity = grab_platform.call("get_ride_velocity") as Vector3
			rotation.y = _yaw
			_curr_body_position = global_position
			_handle_actions()
			_update_prompt()
			_visual_tick(delta)
			return

	# --- driving the platform --------------------------------------------
	if platform_control != null:
		var control_node: Node3D = platform_control as Node3D
		if control_node == null or not is_instance_valid(control_node):
			platform_control = null
		else:
			var drive: float = Input.get_axis("move_forward", "move_back")
			platform_control.call("set_drive_input", drive)
			# Stand still relative to the deck and let move_and_slide apply the
			# moving platform's velocity. A small downward bias keeps contact.
			velocity = Vector3(0.0, -0.35, 0.0)
			rotation.y = _yaw
			move_and_slide()
			_curr_body_position = global_position
			_handle_actions()
			_update_prompt()
			_visual_tick(delta)
			return

	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = Vector3(input_vector.x, 0.0, input_vector.y).rotated(Vector3.UP, _yaw)
	var sprinting: bool = Input.is_action_pressed("sprint") and carrying == null
	var speed: float = SPEED * (SPRINT_MULTIPLIER if sprinting else 1.0)
	if carrying != null:
		speed = CARRY_SPEED
	# A tilted deck pushes the feet downhill; a sudden start or stop makes the
	# player stumble a step. Both come from the real platform transform.
	var slide: Vector3 = Vector3.ZERO
	if freight_platform != null and is_on_floor() and is_instance_valid(freight_platform):
		var push: Vector3 = freight_platform.call("get_ride_push", global_position) as Vector3
		slide = Vector3(push.x, 0.0, push.z) * 0.60
	if direction.length_squared() > 0.01:
		velocity.x = direction.x * speed + slide.x
		velocity.z = direction.z * speed + slide.z
	else:
		velocity.x = move_toward(velocity.x, slide.x, delta * 9.0)
		velocity.z = move_toward(velocity.z, slide.z, delta * 9.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	else:
		velocity.y = 0.0

	# In first person the body follows the view. The hidden third-person model
	# still turns with it, so a future observer sees a correctly facing body.
	rotation.y = _yaw
	move_and_slide()
	if global_position.y < -8.0:
		teleport(spawn_position)
	_curr_body_position = global_position

	_handle_carry(delta)
	_handle_actions()
	_update_prompt()
	_footsteps(delta, direction.length_squared() > 0.01 and is_on_floor())
	_visual_tick(delta)


func _visual_tick(delta: float) -> void:
	if visual == null:
		return
	var flat_velocity: Vector2 = Vector2(velocity.x, velocity.z)
	visual.update_state(delta, flat_velocity, false, false, carrying != null, 5, true)


func _footsteps(delta: float, moving: bool) -> void:
	if not moving:
		_footstep_clock = 0.0
		return
	_footstep_clock -= delta
	if _footstep_clock <= 0.0:
		_footstep_clock = 0.38 if carrying != null else 0.31
		var audio: Node = get_tree().get_first_node_in_group("audio_director")
		if audio != null and audio.has_method("play_footstep"):
			audio.call("play_footstep", global_position, 0.36 if carrying != null else 0.26)


func _update_look_target() -> void:
	var best_primary: Node = null
	var best_primary_score: float = -1.0
	var best_explore: Node = null
	var best_explore_score: float = -1.0
	var origin: Vector3 = camera.global_position if camera != null else global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	var forward: Vector3 = -camera.global_transform.basis.z
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not node is Node3D:
			continue
		var target: Node3D = node as Node3D
		var target_position: Vector3 = target.global_position
		if node.has_method("get_interaction_position"):
			target_position = target.call("get_interaction_position") as Vector3
		var reach: float = INTERACT_REACH + 0.4
		if node.has_method("get_interaction_reach"):
			reach = float(node.call("get_interaction_reach"))
		var to_target: Vector3 = target_position - origin
		var distance: float = to_target.length()
		if distance > reach:
			continue
		var facing: float = forward.dot(to_target.normalized()) if distance > 0.01 else 1.0
		if facing < -0.05:
			continue
		if not _has_line_of_sight(origin, target_position, node):
			continue
		var score: float = facing * 2.0 - distance * 0.15
		if node.is_in_group("explore_prop"):
			if score > best_explore_score:
				best_explore_score = score
				best_explore = node
		elif score > best_primary_score:
			best_primary_score = score
			best_primary = node
	var best: Node = best_primary if best_primary != null else best_explore
	if best != current_target:
		current_target = best
		interactable_changed.emit(best)


## In third person a wall between the camera and the console was obvious; in
## first person the prompt must not appear through rock.
func _has_line_of_sight(from_point: Vector3, to_point: Vector3, target: Node = null) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.from = from_point
	query.to = to_point
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return true
	# The console / cradle owns a static body too: accept a hit on the target's
	# own collision as visible.
	var collider: Node = hit.get("collider") as Node
	if collider == null:
		return true
	# A freight control is a child of the platform, and its ray may legitimately
	# hit the platform deck/rail. That is still a visible target.
	if target != null:
		var walk: Node = target
		for _index: int in range(5):
			if walk == collider:
				return true
			walk = walk.get_parent()
			if walk == null:
				break
	var owner_node: Node = collider
	for _index: int in range(4):
		owner_node = owner_node.get_parent()
		if owner_node == null:
			return true
		if owner_node.has_method("get_interaction_prompt"):
			return true
	return false


func _update_prompt() -> void:
	var text: String = ""
	if grab_platform != null:
		text = "E 松手   ·   抓稳扶手，平台倾斜时不会被甩出去"
	elif platform_control != null:
		text = "W 向对岸   ·   S 倒退   ·   E 松开操纵杆   ·   安全制动在船尾"
	elif carrying != null:
		text = "Q 旋转晶体   ·   F/鼠标左键 放置   ·   X 抛下"
	elif current_target != null and current_target.has_method("get_interaction_prompt"):
		text = str(current_target.call("get_interaction_prompt", self))
	elif _nearest_crystal() != null:
		text = "F 搬起共振晶体"
	if text != current_prompt:
		current_prompt = text
		prompt_changed.emit(text)


func _nearest_crystal() -> PortableCrystal:
	var best: PortableCrystal = null
	var best_distance: float = PICKUP_REACH
	var origin: Vector3 = global_position + Vector3(0.0, 1.0, 0.0)
	var forward: Vector3 = -camera.global_transform.basis.z if camera != null else -global_transform.basis.z
	for node: Node in get_tree().get_nodes_in_group("portable_crystal"):
		var crystal: PortableCrystal = node as PortableCrystal
		if crystal == null or crystal.is_carried:
			continue
		var to_crystal: Vector3 = crystal.global_position - origin
		var distance: float = to_crystal.length()
		if distance >= best_distance:
			continue
		# The player must be looking at the shard (or standing next to it).
		if distance > 0.9 and forward.dot(to_crystal.normalized()) < 0.10:
			continue
		if not _has_line_of_sight(camera.global_position if camera != null else origin, crystal.global_position + Vector3(0.0, 0.6, 0.0)):
			continue
		best_distance = distance
		best = crystal
	return best


func _handle_actions() -> void:
	var interact_pressed: bool = Input.is_action_pressed("interact")
	var pickup_pressed: bool = Input.is_action_pressed("pickup") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var drop_pressed: bool = Input.is_action_pressed("drop")
	var rotate_pressed: bool = Input.is_action_pressed("rotate_crystal")
	var interact_edge: bool = interact_pressed and not _interact_down
	var pickup_edge: bool = pickup_pressed and not _pickup_down
	var drop_edge: bool = drop_pressed and not _drop_down
	var rotate_edge: bool = rotate_pressed and not _rotate_down
	_interact_down = interact_pressed
	_pickup_down = pickup_pressed
	_drop_down = drop_pressed
	_rotate_down = rotate_pressed

	# Grabbing / driving consume E first. Everything else waits until the
	# player lets go, so a stray E can never both release and re-grab.
	if grab_platform != null or platform_control != null:
		if interact_edge:
			if grab_platform != null:
				grab_platform.call("handle_control", "grab", self, grab_point_id)
			if platform_control != null:
				platform_control.call("handle_control", "drive", self, "")
			_reach_time = 0.22
		return

	if interact_edge:
		if carrying == null and current_target != null and current_target.has_method("interact"):
			current_target.call("interact", self)
			_reach_time = 0.32
	if pickup_edge:
		if carrying == null:
			var crystal: PortableCrystal = _nearest_crystal()
			if crystal != null:
				if coop_pickup_gate:
					pending_pickup = crystal
					pickup_requested.emit(crystal)
				else:
					pick_up(crystal)
		else:
			drop_carried(false)
	if drop_edge and carrying != null:
		drop_carried(true)
	if rotate_edge and carrying != null:
		carrying.rotate_held(45.0)
		if viewmodel != null:
			viewmodel.trigger_action("rotate", 1.0)
		var audio: Node = get_tree().get_first_node_in_group("audio_director")
		if audio != null and audio.has_method("play_ui"):
			audio.call("play_ui", "rotate")


func pick_up(crystal: PortableCrystal) -> void:
	if crystal == null or carrying != null:
		return
	if not crystal.begin_carry(hold_point):
		return
	carrying = crystal
	_reach_time = 0.34
	carry_changed.emit(crystal)
	var audio: Node = get_tree().get_first_node_in_group("audio_director")
	if audio != null and audio.has_method("play_at"):
		audio.call("play_at", "crystal_lift", crystal.global_position, 0.7)
	prompt_changed.emit("")


func drop_carried(throw: bool) -> void:
	if carrying == null:
		return
	var crystal: PortableCrystal = carrying
	carrying = null
	crystal.end_carry(throw)
	carry_changed.emit(null)
	if viewmodel != null:
		viewmodel.trigger_action("throw" if throw else "drop", 1.0)
	_reach_time = 0.28
	_update_prompt()


func _handle_carry(delta: float) -> void:
	if carrying == null:
		_hold_forward = HOLD_FORWARD
		hold_point.position = Vector3(HOLD_RIGHT, HOLD_HEIGHT, -HOLD_FORWARD)
		return
	_carry_sway = lerpf(_carry_sway, -velocity.dot(global_transform.basis.x) * 0.010, minf(delta * 6.0, 1.0))
	var safe_forward: float = _safe_hold_forward()
	if safe_forward < _hold_forward:
		_hold_forward = safe_forward
	else:
		_hold_forward = lerpf(_hold_forward, safe_forward, 1.0 - exp(-6.0 * delta))
	hold_point.position = Vector3(HOLD_RIGHT, HOLD_HEIGHT, -_hold_forward)
	carrying.follow_hold(hold_point, _carry_sway)


## Sweeps the real hold axis (forward and slightly right) at two heights. The
## carried shard is 1.45 m tall, so a clear chest does not mean a clear tip.
func _safe_hold_forward() -> float:
	if _carry_probe == null:
		_carry_probe = SphereShape3D.new()
		_carry_probe.radius = 0.33
	var direction: Vector3 = (global_transform.basis.x * HOLD_RIGHT - global_transform.basis.z * HOLD_FORWARD).normalized()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var best: float = HOLD_FORWARD
	for offset: float in [0.55, 1.15]:
		var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		params.shape = _carry_probe
		params.transform = Transform3D(Basis(), global_position + Vector3(0.0, offset, 0.0))
		params.motion = direction * HOLD_FORWARD
		params.collision_mask = 1
		params.collide_with_bodies = true
		params.exclude = [get_rid()]
		var result: Array = space.cast_motion(params)
		if result.size() == 2:
			best = minf(best, HOLD_FORWARD * float(result[0]) - 0.08)
	return clampf(best, HOLD_MIN_FORWARD, HOLD_FORWARD)


# ---------------------------------------------------------------- viewmodel

func _update_viewmodel(delta: float) -> void:
	if viewmodel == null:
		return
	_reach_time = maxf(_reach_time - delta, 0.0)
	_near_wall_forward = _measure_forward_room()
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var pull: float = 0.0
	var hammer_mode: String = ""
	if current_target is HammerRig:
		hammer_mode = (current_target as HammerRig).mode
	var state: String = "idle"
	if grab_platform != null:
		state = "grab"
		var rail_world: Vector3 = global_position + Vector3(0.0, 1.05, 0.0)
		if grab_platform.has_method("get_grab_position"):
			rail_world = grab_platform.call("get_grab_position", grab_point_id) as Vector3
		viewmodel.grab_point_camera = camera.to_local(rail_world)
	elif platform_control != null:
		state = "drive"
		viewmodel.set_drive_axis(Input.get_axis("move_back", "move_forward"))
	elif carrying != null:
		state = "carry"
	elif current_target is HammerRig and hammer_mode == "held":
		state = "rope"
		pull = clampf((current_target as HammerRig).angle / HammerRig.MAX_PULL, 0.0, 1.0)
	elif _reach_time > 0.0:
		state = "reach"
	elif speed > 0.6:
		state = "walk"
	viewmodel.update_pose(delta, state, speed, pull, _reach_time, _near_wall_forward)


## A short ray in front of the eye. The viewmodel is pulled towards the camera
## (and hidden when the player is pressed against rock) instead of drawing arms
## through the wall.
func _measure_forward_room() -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = camera.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin - camera.global_transform.basis.z * 0.75
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return 4.0
	return origin.distance_to(hit.get("position") as Vector3)


# ------------------------------------------------------------------ settings

func set_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	_save_settings()
	view_settings_changed.emit(mouse_sensitivity, invert_y)


func set_invert_y(value: bool) -> void:
	invert_y = value
	_save_settings()
	view_settings_changed.emit(mouse_sensitivity, invert_y)


func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("input", "sensitivity", mouse_sensitivity)
	config.set_value("input", "invert_y", invert_y)
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		# user:// is not writable on every machine (see KNOWN_ISSUES); the
		# settings still apply for this session.
		pass


func load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	mouse_sensitivity = clampf(float(config.get_value("input", "sensitivity", MOUSE_SENSITIVITY)), SENSITIVITY_MIN, SENSITIVITY_MAX)
	invert_y = bool(config.get_value("input", "invert_y", false))
	view_settings_changed.emit(mouse_sensitivity, invert_y)


func toggle_menu() -> void:
	menu_open = not menu_open
	if menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_captured = false
		get_tree().paused = true
	else:
		get_tree().paused = false
		_capture_mouse()
	menu_toggled.emit(menu_open)


func close_menu() -> void:
	if not menu_open:
		return
	toggle_menu()


func is_mouse_captured() -> bool:
	return _mouse_captured


func is_menu_open() -> bool:
	return menu_open


# -------------------------------------------------------------- public utils

func teleport(target: Vector3, yaw_degrees: float = 0.0) -> void:
	if grab_platform != null:
		grab_platform.call("end_grab", self)
		grab_platform = null
		grab_point_id = ""
	if platform_control != null:
		platform_control.call("release_control", self)
		platform_control = null
	freight_platform = null
	global_position = target
	velocity = Vector3.ZERO
	_yaw = wrapf(deg_to_rad(yaw_degrees), -PI, PI)
	_pitch = SPAWN_PITCH
	_aim_active = false
	rotation.y = _yaw
	_prev_body_position = target
	_curr_body_position = target
	_eye_position = target + Vector3(0.0, EYE_HEIGHT, 0.0)
	_interp_ready = true
	_hold_forward = HOLD_FORWARD
	if camera_pivot != null:
		camera_pivot.global_position = _eye_position
		camera_pivot.rotation = Vector3(0.0, _yaw, 0.0)
	if camera_boom != null:
		camera_boom.rotation = Vector3(_pitch, 0.0, 0.0)
	if viewmodel != null:
		viewmodel.snap()


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		if grab_platform != null:
			grab_platform.call("end_grab", self)
			grab_platform = null
		if platform_control != null:
			platform_control.call("release_control", self)
			platform_control = null
		velocity = Vector3.ZERO


## A resonance shock pushes a standing player. The camera is not shaken to fake
## this: the body gets a real velocity, the rails decide whether they stay on.
func apply_platform_knock(impulse: Vector3) -> void:
	if grab_platform != null or not input_enabled:
		return
	velocity += impulse
	if velocity.y < 0.45:
		velocity.y = 0.45


## Remote co-op body update. The network adapter calls this with the host's
## authoritative transform; the local player never uses it.
func update_remote_state(world_position: Vector3, yaw: float, remote_velocity: Vector3, grabbing: bool, carrying_flag: bool) -> void:
	if not world_position.is_finite() or not remote_velocity.is_finite() or not is_finite(yaw):
		return
	var error: float = global_position.distance_to(world_position)
	if error > 4.0:
		global_position = world_position
		velocity = Vector3.ZERO
	else:
		var dt: float = maxf(get_physics_process_delta_time(), 0.001)
		var step: float = minf(error * (1.0 - exp(-12.0 * dt)), 0.35)
		global_position = global_position.move_toward(world_position, step)
		velocity = remote_velocity
	rotation.y = yaw
	if visual != null:
		visual.update_state(0.016, Vector2(remote_velocity.x, remote_velocity.z), false, false, carrying_flag, 5, true)
		visual.set_rescuing(grabbing)


## Camera-only aim used by the recording/autopilot. It eases the look direction
## over a few frames (a cut would be jarring in the recording), but it never
## touches gameplay state and it is cancelled by any real mouse motion.
## Pass `pitch = -99.0` to look exactly at the point (first-person tests use it).
func aim_camera_at(point: Vector3, pitch: float = -0.14) -> void:
	var origin: Vector3 = camera.global_position if camera != null else global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	var direction: Vector3 = point - origin
	if direction.length_squared() < 0.0001:
		return
	_aim_yaw = wrapf(atan2(-direction.x, -direction.z), -PI, PI)
	var computed: float = atan2(direction.y, Vector2(direction.x, direction.z).length())
	_aim_pitch = clampf(computed if pitch == -99.0 else pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
	_aim_active = true


## Body-facing helper for placing a carried crystal without moving.
func face_toward(point: Vector3) -> void:
	var direction: Vector3 = point - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	_yaw = wrapf(atan2(-direction.x, -direction.z), -PI, PI)
	rotation.y = _yaw
	_aim_active = false
	_apply_view()
