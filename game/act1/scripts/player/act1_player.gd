class_name Act1StationPlayer
extends CharacterBody3D

## First-person station worker for Act 01. This controller owns only local
## movement, camera, interaction ray selection and avatar presentation. Every
## world-state change is requested from Act1App, which is the host-authoritative
## state machine.
##
## Input note: the original `cancel` action was Q in the Act01 project, but the
## 04-05 base project binds `cancel=Esc`. To keep "Q 松手/取消" without touching
## the unified map, this controller reads the module-specific `act1_cancel`
## action (registered by Act1App._setup_input_fallback).

signal prompt_changed(text: String)
signal target_changed(target: Node)
signal grabbed_changed(value: bool)
signal downed_changed(value: bool)

const WALK_SPEED := 4.2
const SPRINT_SPEED := 6.0
const ACCELERATION := 32.0
const AIR_ACCELERATION := 9.0
const FRICTION := 16.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 5.2
const EYE_HEIGHT := 1.62
const MOUSE_SENSITIVITY := 0.0021
const PITCH_MIN := -1.34
const PITCH_MAX := 1.30
const INTERACT_DISTANCE := 3.15
const INTERACT_MASK := 8
const OCCLUSION_MASK := 1 | 4 | 16
const LOCAL_BODY_LAYER := 2

var stage: Node = null
var player_pid := 1
var camera: Camera3D
var hands: Act1Hands
var yaw := 0.0
var pitch := 0.0
var current_target: Node = null
var current_prompt := ""
var holding_target: Node = null
var grabbing := false
var grab_anchor: Node3D = null
var grab_offset := Vector3.ZERO
var external_hold := false
var attached_to: Node3D = null
var attach_offset := Vector3.ZERO
var attach_yaw := 0.0
var attach_action_id := ""
var downed := false
var downed_time := 0.0
var wind_acceleration := Vector3.ZERO
var mouse_enabled := true
var input_enabled := true
var fall_reported := false
var _bob_time := 0.0
var _step_accum := 0.0
var _foot_player: AudioStreamPlayer
var _interact_was_down := false
var _cancel_was_down := false
var _ray := PhysicsRayQueryParameters3D.new()
var _occ := PhysicsRayQueryParameters3D.new()
var _body_visual: Node3D
var _air_time := 0.0
var _peak_y := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4 | 16
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(46.0)
	floor_stop_on_slope = true
	slide_on_ceiling = true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.78
	var col := CollisionShape3D.new()
	col.name = "PlayerCapsule"
	col.shape = shape
	col.position = Vector3(0, 0.89, 0)
	add_child(col)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0, EYE_HEIGHT, 0)
	camera.fov = 74.0
	camera.near = 0.045
	camera.far = 260.0
	camera.cull_mask = 0xFFFFF & ~LOCAL_BODY_LAYER
	camera.current = true
	add_child(camera)
	hands = Act1Hands.new()
	hands.name = "Hands"
	camera.add_child(hands)
	hands.setup()
	_build_body_visual()
	_foot_player = AudioStreamPlayer.new()
	_foot_player.name = "Footsteps"
	_foot_player.volume_db = -19.0
	add_child(_foot_player)
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.collision_mask = INTERACT_MASK
	_occ.collide_with_areas = false
	_occ.collide_with_bodies = true
	_occ.collision_mask = OCCLUSION_MASK
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_body_visual() -> void:
	_body_visual = Node3D.new()
	_body_visual.name = "LocalBodyVisual"
	add_child(_body_visual)
	var packed := load("res://act1/assets/characters/skin_ranger.glb") as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return
	_body_visual.add_child(inst)
	_set_layers(inst, LOCAL_BODY_LAYER)
	inst.rotation.y = PI
	inst.scale = Vector3.ONE * 0.92


func _set_layers(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer
	for child in node.get_children():
		_set_layers(child, layer)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * MOUSE_SENSITIVITY
		pitch = clampf(pitch + mm.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		_apply_look()
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_enabled = true
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_enabled = false


func _apply_look() -> void:
	rotation.y = yaw
	camera.rotation.x = -pitch


func set_look(new_yaw: float, new_pitch: float = -0.04) -> void:
	yaw = new_yaw
	pitch = clampf(new_pitch, PITCH_MIN, PITCH_MAX)
	_apply_look()


func look_at_point(point: Vector3) -> void:
	var eye := camera.global_position
	var d := point - eye
	if d.length_squared() < 0.001:
		return
	set_look(atan2(-d.x, -d.z), -atan2(d.y, Vector2(d.x, d.z).length()))


func teleport(pos: Vector3, new_yaw := 0.0, new_pitch := -0.04) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	set_look(new_yaw, new_pitch)
	fall_reported = false
	_air_time = 0.0
	_peak_y = pos.y


func _physics_process(delta: float) -> void:
	if not input_enabled:
		return
	if external_hold:
		_follow_attachment()
		_handle_buttons()
		_update_interaction()
		if attached_to != null and is_instance_valid(attached_to) and attached_to.name == "ClimbAnchor":
			hands.set_state("climb")
			hands.set_operate_context("climb", 1.0)
		elif attach_action_id == "cart_push":
			hands.set_state("push")
			hands.set_operate_context("door_push", Input.get_axis("move_back", "move_forward"))
		elif attached_to != null and is_instance_valid(attached_to) and attached_to.name.contains("MineCart"):
			hands.set_state("grab")
			hands.set_operate_context("grab")
		else:
			hands.set_operate_context("")
		hands.set_motion(Vector2.ZERO, false, false, Vector3.ZERO, true)
		hands.bob(_bob_time, false)
		return
	if grabbing and grab_anchor != null and is_instance_valid(grab_anchor):
		global_position = grab_anchor.global_transform * grab_offset
		velocity = Vector3.ZERO
		_handle_buttons()
		_update_interaction()
		hands.set_state("grab")
		hands.set_operate_context("grab", 0.0, 0.0, camera.to_local(grab_anchor.global_position), true)
		hands.set_motion(Vector2.ZERO, false, false, Vector3.ZERO, true)
		hands.bob(_bob_time, false)
		return
	if downed:
		downed_time = maxf(0.0, downed_time - delta)
		wind_acceleration *= 0.25
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprint := Input.is_action_pressed("sprint") and not downed
	var speed := (SPRINT_SPEED if sprint else WALK_SPEED)
	if downed:
		speed = 1.65
	var wish := transform.basis * Vector3(input.x, 0.0, input.y)
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	# Wind acts as external force/acceleration + quadratic/linear drag rather than
	# overwriting the player's target speed directly, matching the crate model.
	wind_acceleration = stage.call("get_wind_acceleration", global_position, grabbing) if stage != null else Vector3.ZERO
	var wind_push := wind_acceleration * 0.72
	wind_push.y = 0.0
	var target := wish * speed
	var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	velocity.x += wind_push.x * delta * 2.2
	velocity.z += wind_push.z * delta * 2.2
	if wind_push.length_squared() > 0.001:
		var wind_drag := clampf(1.35 * delta, 0.0, 1.0)
		velocity.x *= (1.0 - wind_drag)
		velocity.z *= (1.0 - wind_drag)
	if is_on_floor() and wish.length() < 0.05:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
	if is_on_floor() and Input.is_action_just_pressed("jump") and not downed:
		velocity.y = JUMP_VELOCITY
	_handle_buttons()
	var was_air := not is_on_floor()
	move_and_slide()
	if not is_on_floor():
		_air_time += delta
		_peak_y = maxf(_peak_y, global_position.y)
	elif was_air and _air_time > 0.45 and (_peak_y - global_position.y) > 1.5 and global_position.y < 0.2:
		if not downed:
			stage.call("report_player_fall", self)
		_air_time = 0.0
		_peak_y = global_position.y
	else:
		_air_time = 0.0
		_peak_y = global_position.y
	_push_contacts(wish)
	_update_footsteps(delta)
	_update_interaction()
	_bob_time += delta * (1.6 + Vector2(velocity.x, velocity.z).length() * 0.45)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.4
	if holding_target != null and is_instance_valid(holding_target):
		hands.set_state("push")
		hands.set_operate_context("door_push", 1.0)
	else:
		if hands.state == "push":
			hands.set_state("idle")
		hands.set_operate_context("")
	hands.set_motion(input, moving, sprint, velocity, is_on_floor())
	hands.bob(_bob_time, moving)
	if global_position.y < -7.0 and not fall_reported:
		fall_reported = true
		stage.call("report_out_of_bounds", self)


func _handle_buttons() -> void:
	var down := Input.is_action_pressed("interact")
	if down and not _interact_was_down:
		_interact_press()
	elif not down and _interact_was_down:
		_interact_release()
	_interact_was_down = down
	var cancel := Input.is_action_pressed("act1_cancel")
	if cancel and not _cancel_was_down:
		if external_hold:
			stage.call("request_interaction", "cart_push", self, "end")
		if grabbing:
			release_grab()
	_cancel_was_down = cancel


func _interact_press() -> void:
	if external_hold:
		if attach_action_id != "":
			stage.call("request_interaction", attach_action_id, self, "end")
		return
	if grabbing:
		var rail_id := ""
		if grab_anchor is Act1Interactable:
			rail_id = (grab_anchor as Act1Interactable).interaction_id
		if rail_id != "":
			stage.call("request_interaction", rail_id, self, "grab_end")
		release_grab()
		return
	if current_target != null and is_instance_valid(current_target):
		if bool(current_target.get("hold_mode")):
			holding_target = current_target
			current_target.call("begin_hold", self)
			hands.set_state("push")
			hands.set_operate_context("door_push", 1.0)
		elif current_target.has_method("interact"):
			var iid: String = str(current_target.get("interaction_id")) if current_target is Act1Interactable else ""
			current_target.call("interact", self)
			if not grabbing and not external_hold:
				_trigger_act1_gesture(iid)


func _trigger_act1_gesture(interaction_id: String) -> void:
	if interaction_id in ["shove_gantry", "rail_shove"]:
		hands.trigger_action("shove", 1.0)
	elif interaction_id in ["release_latch", "rotor_lock", "chock", "parking_brake", "secure_crate"]:
		hands.trigger_action("pull_pin", 1.0)
	elif interaction_id in ["power_clamp", "coupling", "governor", "damper"]:
		hands.trigger_action("clamp", 1.0)
	elif interaction_id in ["power_winch", "start_fan", "emergency_stop", "rescue_winch"]:
		hands.trigger_action("switch", 1.0)
	elif not interaction_id.begins_with("grab_"):
		hands.trigger_action("press", 0.9)


func _interact_release() -> void:
	if holding_target != null and is_instance_valid(holding_target):
		holding_target.call("end_hold", self)
	holding_target = null


func _update_interaction() -> void:
	if external_hold or grabbing:
		if grabbing:
			_set_prompt("E 松开抓扶 · 风力已被身体吸收")
		elif attach_action_id != "":
			_set_prompt("E 松开 · WASD 推拉 · Q 取消")
		else:
			_set_prompt("被机械带动中 · 鼠标观察")
		return
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z
	var to := from + forward * INTERACT_DISTANCE
	_ray.from = from
	_ray.to = to
	_ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	var found: Node = null
	if not hit.is_empty():
		var collider := hit.get("collider") as Node
		if collider is Act1Interactable and collider.is_in_group("explore_prop"):
			_ray.exclude = [get_rid(), (collider as CollisionObject3D).get_rid()]
			var retry := get_world_3d().direct_space_state.intersect_ray(_ray)
			if not retry.is_empty():
				var retry_col := retry.get("collider") as Node
				if retry_col is Act1Interactable and (retry_col as Act1Interactable).enabled:
					hit = retry
					collider = retry_col
		if collider is Act1Interactable and (collider as Act1Interactable).enabled:
			var point: Vector3 = hit.get("position", to)
			_occ.from = from
			_occ.to = point - forward * 0.03
			_occ.exclude = [get_rid()]
			var blocker := get_world_3d().direct_space_state.intersect_ray(_occ)
			if blocker.is_empty() or float(blocker.get("position", from).distance_to(from)) > point.distance_to(from) - 0.02:
				found = collider
	if found != current_target:
		if current_target != null and is_instance_valid(current_target) and current_target.has_method("set_focused"):
			current_target.call("set_focused", false)
		current_target = found
		if current_target != null and current_target.has_method("set_focused"):
			current_target.call("set_focused", true)
		target_changed.emit(current_target)
	if current_target != null and current_target.has_method("get_prompt"):
		_set_prompt(str(current_target.call("get_prompt", self)))
	else:
		_set_prompt("")


func _set_prompt(text: String) -> void:
	if text == current_prompt:
		return
	current_prompt = text
	prompt_changed.emit(text)


func _push_contacts(wish: Vector3) -> void:
	if wish.length_squared() < 0.05:
		return
	for i in range(get_slide_collision_count()):
		var c := get_slide_collision(i)
		var obj := c.get_collider()
		if obj is RigidBody3D and (obj as Node).is_in_group("pushable"):
			var rb := obj as RigidBody3D
			var dir := -c.get_normal()
			dir.y = 0.0
			if dir.length_squared() < 0.01:
				continue
			var mass := maxf(1.0, rb.mass)
			var force := minf(1100.0, mass * 24.0)
			rb.sleeping = false
			rb.apply_central_force(dir.normalized() * force + Vector3.UP * mass * 0.3)


func _update_footsteps(delta: float) -> void:
	var hs := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or hs < 0.6 or downed:
		return
	_step_accum += delta * hs
	if _step_accum > 2.2:
		_step_accum = 0.0
		var idx := 1 + (randi() % 4)
		var path := "res://act1/assets/audio/step_%d.wav" % idx
		if ResourceLoader.exists(path):
			_foot_player.stream = load(path) as AudioStream
			_foot_player.pitch_scale = randf_range(0.92, 1.06)
			_foot_player.play()


func attach_to(node: Node3D, offset: Vector3, face_yaw: float, action_id := "") -> void:
	external_hold = true
	attached_to = node
	attach_offset = offset
	attach_yaw = face_yaw
	attach_action_id = action_id
	holding_target = null
	if node != null and is_instance_valid(node) and node.name == "ClimbAnchor":
		hands.set_state("climb")
	elif node != null and is_instance_valid(node) and node.name.contains("MineCart"):
		hands.set_state("grab")
	else:
		hands.set_state("push")
	velocity = Vector3.ZERO


func detach() -> void:
	external_hold = false
	attached_to = null
	attach_action_id = ""
	hands.set_operate_context("")
	hands.set_state("idle")


func _follow_attachment() -> void:
	if attached_to == null or not is_instance_valid(attached_to):
		detach()
		return
	global_position = attached_to.global_transform * attach_offset
	velocity = Vector3.ZERO


func start_grab(anchor: Node3D, offset: Vector3) -> void:
	grabbing = true
	grab_anchor = anchor
	grab_offset = offset
	velocity = Vector3.ZERO
	hands.set_state("grab")
	if anchor != null and is_instance_valid(anchor):
		hands.set_operate_context("grab", 0.0, 0.0, camera.to_local(anchor.global_position), true)
	grabbed_changed.emit(true)


func release_grab() -> void:
	if not grabbing:
		return
	grabbing = false
	grab_anchor = null
	hands.set_operate_context("")
	hands.set_state("idle")
	grabbed_changed.emit(false)


func set_downed(value: bool) -> void:
	if downed == value:
		return
	downed = value
	if value:
		downed_time = 20.0
		release_grab()
		hands.set_state("idle")
	downed_changed.emit(value)


func get_state_packet() -> Dictionary:
	return {
		"pos": global_position,
		"yaw": yaw,
		"pitch": pitch,
		"grab": grabbing,
		"downed": downed,
		"hold": holding_target != null,
		"external": external_hold,
	}


func apply_remote_state(data: Dictionary) -> void:
	var pos: Vector3 = data.get("pos", global_position)
	global_position = pos
	yaw = float(data.get("yaw", 0.0))
	rotation.y = yaw


func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.4