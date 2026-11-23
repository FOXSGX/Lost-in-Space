class_name PlayerController
extends CharacterBody3D

## First-person controller for Resonance 05.
## Mouse look is processed exactly once per InputEventMouseMotion, the camera is
## a child of the body, and the local body is hidden from the local camera by
## render layer instead of being deleted.

signal prompt_changed(text: String)
signal operate_started(target: Node)
signal operate_stopped(target: Node)
signal request_debug()
signal request_reset()
signal request_restart()
signal request_pause()

const WALK_SPEED := 4.3
const SPRINT_SPEED := 6.0
const ACCELERATION := 30.0
const AIR_ACCELERATION := 8.0
const FRICTION := 14.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 5.6
const EYE_HEIGHT := 1.62
const MOUSE_SENSITIVITY := 0.0021
const PITCH_MIN := -1.30
const PITCH_MAX := 1.32
const INTERACT_DISTANCE := 2.9
const LOCAL_BODY_LAYER := 2

var camera: Camera3D
var hands: FirstPersonHands
var yaw: float = 0.0
var pitch: float = 0.0
var operating: bool = false
var operate_target: Node = null
var operate_anchor: Transform3D = Transform3D.IDENTITY
var operate_yaw_center: float = 0.0
var operate_yaw_limit: float = 1.15
var return_position: Vector3 = Vector3.ZERO
var current_prompt: String = ""
var current_target: Node = null
var mouse_enabled: bool = true
var footsteps_enabled: bool = true
var _step_accum: float = 0.0
var _bob_time: float = 0.0
var _body_visual: Node3D
var _foot_player: AudioStreamPlayer
var _interact_buffer: float = 0.0
var _interact_prev: bool = false
var _ray_query: PhysicsRayQueryParameters3D
# F3 collision probe: the last motion blocking contact, with enough data to
# attribute it to a specific collision shape and its visible counterpart.
var block_info: Dictionary = {}
var block_history: Array[Dictionary] = []
var block_events: int = 0
var _block_cooldown: float = 0.0

var world: World3D
var audio: AudioDirector
# --- co-op states ---------------------------------------------------------
# grabbing: holding a catwalk rail; external_hold: a winch/ladder owns the body.
var grabbing: bool = false
var grab_anchor: Node3D = null
var grab_offset: Vector3 = Vector3.ZERO
var external_hold: bool = false
var impaired_timer: float = 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 8
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(46.0)
	floor_stop_on_slope = true
	slide_on_ceiling = true
	up_direction = Vector3.UP
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.78
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "PlayerCapsule"
	col.shape = shape
	col.position = Vector3(0, 0.89, 0)
	add_child(col)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0, EYE_HEIGHT, 0)
	camera.fov = 72.0
	camera.near = 0.045
	camera.far = 240.0
	camera.cull_mask = 0xFFFFF & ~LOCAL_BODY_LAYER
	camera.current = true
	add_child(camera)
	hands = FirstPersonHands.new()
	hands.name = "Hands"
	camera.add_child(hands)
	hands.setup()
	_build_body_visual()
	_foot_player = AudioStreamPlayer.new()
	_foot_player.name = "Footsteps"
	_foot_player.volume_db = -17.0
	add_child(_foot_player)
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_areas = true
	_ray_query.collide_with_bodies = true
	set_physics_process(true)


func _build_body_visual() -> void:
	_body_visual = Node3D.new()
	_body_visual.name = "LocalBodyVisual"
	add_child(_body_visual)
	var packed: PackedScene = load("res://assets/resonance-characters/skin_ranger.glb") as PackedScene
	if packed == null:
		return
	var inst: Node3D = packed.instantiate() as Node3D
	if inst == null:
		return
	_body_visual.add_child(inst)
	_apply_local_body_layers(inst)
	inst.position = Vector3(0, 0, 0)
	inst.rotation.y = PI
	inst.scale = Vector3.ONE * 0.92


func _apply_local_body_layers(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi: GeometryInstance3D = node as GeometryInstance3D
		gi.layers = LOCAL_BODY_LAYER
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if node is VisualInstance3D and not node is GeometryInstance3D:
		(node as VisualInstance3D).layers = LOCAL_BODY_LAYER
	for child in node.get_children():
		_apply_local_body_layers(child)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_enabled:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var sens: float = MOUSE_SENSITIVITY
		yaw -= mm.relative.x * sens
		pitch += mm.relative.y * sens
		pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
		if operating:
			var offset: float = wrapf(yaw - operate_yaw_center, -PI, PI)
			offset = clampf(offset, -operate_yaw_limit, operate_yaw_limit)
			yaw = operate_yaw_center + offset
		_apply_look()
		get_viewport().set_input_as_handled()


func _apply_look() -> void:
	rotation.y = yaw
	camera.rotation.x = -pitch


func set_look(new_yaw: float, new_pitch: float) -> void:
	yaw = new_yaw
	pitch = clampf(new_pitch, PITCH_MIN, PITCH_MAX)
	_apply_look()


func toggle_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_enabled = false
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_enabled = true


func _physics_process(delta: float) -> void:
	impaired_timer = maxf(0.0, impaired_timer - delta)
	var interact_now: bool = Input.is_action_pressed("interact")
	if interact_now and not _interact_prev:
		_handle_interact()
	_interact_prev = interact_now
	if Input.is_action_just_pressed("toggle_debug"):
		request_debug.emit()
	if Input.is_action_just_pressed("reset_level"):
		request_reset.emit()
	if Input.is_action_just_pressed("restart_level"):
		request_restart.emit()
	# A rig (winch, ladder) owns the body; do not integrate gravity or input.
	if external_hold:
		velocity = Vector3.ZERO
		_update_interaction(delta)
		hands.set_motion(Vector2.ZERO, false, false, Vector3.ZERO, false)
		hands.set_operate_context("climb", Input.get_axis("move_back", "move_forward"))
		_update_body_pose_to_grab()
		hands.bob(_bob_time, false)
		return
	if grabbing:
		velocity = Vector3.ZERO
		_update_body_pose_to_grab()
		_update_interaction(delta)
		if grab_anchor != null and is_instance_valid(grab_anchor):
			var rail_cam: Vector3 = camera.to_local(grab_anchor.global_position)
			hands.set_operate_context("grab", 0.0, 0.0, rail_cam, true)
		hands.set_motion(Vector2.ZERO, false, false, Vector3.ZERO, true)
		hands.bob(_bob_time, false)
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if operating:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_record_blocks(Vector3.ZERO, delta)
		_update_interaction(delta)
		var op_axis: float = Input.get_axis("move_back", "move_forward")
		hands.set_operate_context(_operate_kind(), op_axis)
		hands.set_motion(Vector2.ZERO, false, false, Vector3.ZERO, is_on_floor())
		hands.bob(_bob_time, false)
		return
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprint: bool = Input.is_action_pressed("sprint") and impaired_timer <= 0.0
	var speed: float = SPRINT_SPEED if sprint else WALK_SPEED
	if impaired_timer > 0.0:
		speed *= 0.58
	var wish: Vector3 = (transform.basis * Vector3(input.x, 0.0, input.y))
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var target: Vector3 = wish * speed
	var accel: float = ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if is_on_floor() and wish.length() < 0.05:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
	if is_on_floor() and Input.is_action_just_pressed("jump") and impaired_timer <= 0.0:
		velocity.y = JUMP_VELOCITY
	move_and_slide()
	_record_blocks(wish.normalized() if wish.length() > 0.1 else Vector3.ZERO, delta)
	_update_footsteps(delta)
	_update_interaction(delta)
	_bob_time += delta * (1.6 + Vector2(velocity.x, velocity.z).length() * 0.6)
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.4
	hands.set_operate_context("")
	hands.set_motion(input, moving, sprint, velocity, is_on_floor())
	hands.bob(_bob_time, moving)


func _update_body_pose_to_grab() -> void:
	if grab_anchor == null or not is_instance_valid(grab_anchor):
		grabbing = false
		grab_anchor = null
		return
	global_position = grab_anchor.global_transform * grab_offset


func start_grab(anchor: Node3D, offset: Vector3) -> void:
	if operating:
		stop_operating()
	grabbing = true
	grab_anchor = anchor
	grab_offset = offset
	velocity = Vector3.ZERO
	hands.set_state("grab")
	if anchor != null and is_instance_valid(anchor):
		hands.set_operate_context("grab", 0.0, 0.0, camera.to_local(anchor.global_position), true)


func stop_grab() -> void:
	grabbing = false
	grab_anchor = null
	hands.set_operate_context("")
	hands.set_state("idle")


func set_impaired(seconds: float) -> void:
	impaired_timer = maxf(impaired_timer, seconds)


func clear_impaired() -> void:
	impaired_timer = 0.0


func _record_blocks(wish: Vector3, delta: float) -> void:
	# F3 audit support: when the player pushes into the world, remember the
	# exact contact so the HUD (and tests) can name the blocking shape and
	# whether a visible mesh exists at that point.
	_block_cooldown = maxf(0.0, _block_cooldown - delta)
	if wish.length_squared() < 0.01:
		return
	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var normal: Vector3 = collision.get_normal()
		if normal.dot(wish) > -0.15:
			continue
		var collider: Object = collision.get_collider()
		if collider == null:
			continue
		var point: Vector3 = collision.get_position()
		var shape_desc: String = _describe_shape(collider, point)
		var visible_desc: String = _nearest_visible(point)
		block_info = {
			"pos": global_position,
			"wish": wish,
			"collider": (collider as Node).get_path() if collider is Node else str(collider),
			"layer": (collider as CollisionObject3D).collision_layer if collider is CollisionObject3D else 0,
			"shape": shape_desc,
			"contact": point,
			"normal": normal,
			"visible": visible_desc,
			"airwall_candidate": visible_desc == "none",
		}
		block_events += 1
		if _block_cooldown <= 0.0:
			_block_cooldown = 0.25
			block_history.append(block_info.duplicate(true))
			if block_history.size() > 32:
				block_history.pop_front()
		return


func _describe_shape(collider: Object, point: Vector3) -> String:
	if not collider is CollisionObject3D:
		return "?"
	var best: String = "unknown"
	var best_dist: float = 999.0
	for child in (collider as Node).get_children():
		if not child is CollisionShape3D:
			continue
		var cs: CollisionShape3D = child as CollisionShape3D
		if cs.shape == null:
			continue
		var dbg: Mesh = cs.shape.get_debug_mesh()
		if dbg == null:
			continue
		var aabb: AABB = cs.global_transform * dbg.get_aabb()
		var approx: float = maxf(0.0, aabb.get_center().distance_to(point) - aabb.size.length() * 0.5)
		if approx < best_dist:
			best_dist = approx
			best = "%s/%s @%s" % [cs.name, cs.shape.get_class(), str(cs.global_position.snapped(Vector3(0.01, 0.01, 0.01)))]
	return best


func _nearest_visible(point: Vector3) -> String:
	var level: Node = get_parent()
	if level == null:
		return "none"
	var best: String = "none"
	var best_size: float = 1.0e12
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if mi.layers == LOCAL_BODY_LAYER:
			continue
		if is_ancestor_of(mi):
			continue
		var anc: Node = mi.get_parent()
		var local_visual: bool = false
		while anc != null and anc != level:
			if anc.name == "LocalBodyVisual":
				local_visual = true
				break
			anc = anc.get_parent()
		if local_visual:
			continue
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		if not aabb.grow(0.35).has_point(point):
			continue
		# Pick the most specific (smallest) visible mesh that contains the
		# contact, so a rock face wins over the whole-hall shell AABB.
		var size_len: float = aabb.size.length()
		if size_len < best_size:
			best_size = size_len
			best = str(mi.get_path())
	return best


func get_block_text() -> String:
	if block_info.is_empty():
		return "BLOCK none"
	return "BLOCK %s | shape %s | layer %d | contact %s | n %s | visible %s%s" % [
		block_info.get("collider", "?"),
		block_info.get("shape", "?"),
		int(block_info.get("layer", 0)),
		str((block_info.get("contact", Vector3.ZERO) as Vector3).snapped(Vector3(0.01, 0.01, 0.01))),
		str((block_info.get("normal", Vector3.UP) as Vector3).snapped(Vector3(0.01, 0.01, 0.01))),
		block_info.get("visible", "none"),
		"  AIRWALL?" if bool(block_info.get("airwall_candidate", false)) else "",
	]


func _update_footsteps(delta: float) -> void:
	var hspeed: float = Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or hspeed < 0.6:
		return
	_step_accum += delta * hspeed
	if _step_accum > 2.35:
		_step_accum = 0.0
		_play_footstep()


func _play_footstep() -> void:
	if not footsteps_enabled:
		return
	var stream_paths: Array[String] = ["res://assets/audio/step_1.wav", "res://assets/audio/step_2.wav", "res://assets/audio/step_3.wav", "res://assets/audio/step_4.wav"]
	var path: String = stream_paths[randi() % stream_paths.size()]
	if not ResourceLoader.exists(path):
		return
	_foot_player.stream = load(path) as AudioStream
	_foot_player.pitch_scale = randf_range(0.9, 1.08)
	_foot_player.play()


func _update_interaction(_delta: float) -> void:
	if operating:
		_set_prompt("")
		return
	if grabbing:
		_set_prompt("E 松开抓扶横杆")
		return
	var from: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var to: Vector3 = from + forward * INTERACT_DISTANCE
	_ray_query.from = from
	_ray_query.to = to
	_ray_query.exclude = [get_rid()]
	_ray_query.collision_mask = 1 | 8
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ray_query)
	var found: Node = null
	var nearest_primary: Node = _nearest_interactable(from, forward, true)
	if not hit.is_empty():
		var collider: Object = hit.get("collider") as Object
		if collider is Node:
			found = _find_interactable(collider as Node)
		if found != null and found.is_in_group("explore_prop") and nearest_primary != null:
			found = nearest_primary
		if found == null:
			found = nearest_primary if nearest_primary != null else _nearest_interactable(from, forward, false)
			if found == null:
				_set_prompt("")
				current_target = null
				return
	if found == null:
		found = nearest_primary if nearest_primary != null else _nearest_interactable(from, forward, false)
	if found != current_target:
		current_target = found
	if current_target != null and current_target.has_method("get_prompt"):
		_set_prompt(str(current_target.call("get_prompt")))
	else:
		_set_prompt("")


func _find_interactable(node: Node) -> Node:
	var n: Node = node
	while n != null:
		if n.is_in_group("interactable") and n.has_method("get_prompt"):
			return n
		n = n.get_parent()
	return null


func _nearest_interactable(from: Vector3, forward: Vector3, primary_only: bool = false) -> Node:
	var best: Node = null
	var best_score: float = -1.0
	for n in get_tree().get_nodes_in_group("interactable"):
		if not n.has_method("get_prompt"):
			continue
		if primary_only and n.is_in_group("explore_prop"):
			continue
		var node3d: Node3D = n as Node3D
		if node3d == null or not node3d.is_visible_in_tree():
			continue
		var target_pos: Vector3 = node3d.global_position
		for child in node3d.get_children():
			if child is Area3D:
				target_pos = (child as Area3D).global_position
				break
		var delta: Vector3 = target_pos - from
		var dist: float = delta.length()
		if dist > 2.6:
			continue
		var dir: Vector3 = delta / maxf(dist, 0.001)
		var dot: float = dir.dot(forward)
		if dot < 0.30:
			continue
		var score: float = dot - dist * 0.12
		if score > best_score:
			best_score = score
			best = n
	return best


func _set_prompt(text: String) -> void:
	if text == current_prompt:
		return
	current_prompt = text
	prompt_changed.emit(text)


func _handle_interact() -> void:
	# An active operation always owns E: the caged ladder sets external_hold
	# while operating, and checking external_hold first used to make the climb
	# impossible to cancel with E (the body stayed pinned to the ladder).
	if operating:
		stop_operating()
		return
	if external_hold:
		return
	if grabbing:
		# Prefer the rail under the crosshair so pressing E on another rail moves
		# the hand over instead of only letting go.
		if current_target != null and current_target.has_method("interact") and current_target is GrabPoint:
			current_target.call("interact", self)
			return
		if grab_anchor != null and is_instance_valid(grab_anchor) and grab_anchor.has_method("interact"):
			grab_anchor.call("interact", self)
		else:
			stop_grab()
		return
	if current_target != null and current_target.has_method("interact"):
		var target_ref: Node = current_target
		target_ref.call("interact", self)
		if not operating and not grabbing and not external_hold and hands != null:
			if target_ref is IsolationRig or target_ref is CatwalkStation:
				hands.trigger_action("pull_pin", 1.0)
			elif target_ref is LockRig:
				hands.trigger_action("slam", 1.0)
			else:
				hands.trigger_action("press", 0.9)


func enter_operate(anchor: Transform3D, target: Node, yaw_center: float, yaw_limit: float = 1.1) -> void:
	if operating:
		return
	operating = true
	operate_target = target
	operate_anchor = anchor
	operate_yaw_center = yaw_center
	operate_yaw_limit = yaw_limit
	return_position = global_position
	global_position = anchor.origin
	velocity = Vector3.ZERO
	var offset: float = wrapf(yaw - yaw_center, -PI, PI)
	offset = clampf(offset, -yaw_limit, yaw_limit)
	yaw = yaw_center + offset
	_apply_look()
	_set_prompt("")
	hands.set_state("lever")
	operate_started.emit(target)


func stop_operating() -> void:
	if not operating:
		return
	var t: Node = operate_target
	operating = false
	operate_target = null
	hands.set_operate_context("")
	hands.set_state("idle")
	operate_stopped.emit(t)


func _operate_kind() -> String:
	if operate_target == null:
		return "lever"
	if operate_target is DamperRig or operate_target is BrakeRig:
		return "wheel"
	if operate_target is StabilizerRig:
		return "pump"
	if operate_target is PushDoor:
		return "door_push"
	if operate_target is CatwalkRig and external_hold:
		return "climb"
	return "lever"


func force_exit_operate() -> void:
	stop_operating()


func teleport(pos: Vector3, new_yaw: float, new_pitch: float = -0.08) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	set_look(new_yaw, new_pitch)


func get_eye_position() -> Vector3:
	return camera.global_position


func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.4




