extends Node3D

## FirstPersonRig - Act 2/3 realistic first-person arm & hand viewmodel.
## Wraps RealisticHandRig while keeping all public/test-inspected fields intact.

const MAX_REACH: float = 0.74

var player: CharacterBody3D
var camera: Camera3D
var rig: RealisticHandRig
var _left: Node3D
var _right: Node3D
var _left_fore: MeshInstance3D
var _right_fore: MeshInstance3D
var _state: String = "idle"
var _reach_error: float = 0.0
var _prev_carrying: int = 0
var _prev_brace: bool = false
var _prev_console: bool = false
var _prev_interact: bool = false


func setup(actor: CharacterBody3D, camera_node: Camera3D) -> void:
	player = actor
	camera = camera_node
	name = "FirstPersonRig"
	rig = RealisticHandRig.new()
	rig.name = "RealisticRig"
	add_child(rig)
	rig.setup("ranger", 1, true)
	_left = rig.left_wrist
	_right = rig.right_wrist
	_left_fore = rig.left_forearm_mesh
	_right_fore = rig.right_forearm_mesh
	rig.snap_idle()


func _state_now() -> String:
	if player == null:
		return "idle"
	if int(player.get("carrying")) > 0:
		return "carry"
	if bool(player.get("brace_active")):
		return "grip"
	if bool(player.get("fp_console")):
		return "console"
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if speed > 0.35 and player.is_on_floor():
		return "walk"
	return "idle"


func tick(delta: float) -> void:
	if rig == null or player == null:
		return
	var carrying_now: int = int(player.get("carrying"))
	var brace_now: bool = bool(player.get("brace_active"))
	var console_now: bool = bool(player.get("fp_console"))
	if carrying_now > 0 and _prev_carrying == 0:
		rig.trigger_action("pickup", 1.0)
	elif carrying_now == 0 and _prev_carrying > 0:
		rig.trigger_action("drop", 0.9)
	if console_now and not _prev_console:
		rig.trigger_action("clamp", 0.8)
	var interact_now: bool = Input.is_action_pressed("interact")
	if interact_now and not _prev_interact and not console_now and not brace_now:
		rig.trigger_action("press", 0.9)
	_prev_interact = interact_now
	_prev_carrying = carrying_now
	_prev_brace = brace_now
	_prev_console = console_now

	_state = _state_now()
	var vel_xz: Vector2 = Vector2(player.velocity.x, player.velocity.z)
	var speed: float = vel_xz.length()
	var sprinting: bool = Input.is_action_pressed("sprint") and speed > 6.2
	var moving: bool = speed > 0.35 and player.is_on_floor()

	if _state == "grip":
		var rail: Vector3 = player.get("brace_target") as Vector3
		var toward: Vector3 = camera.global_position - rail
		var stand_off: Vector3 = rail
		if toward.length() > 0.05:
			stand_off = rail + toward.normalized() * 0.09
		var target_cam: Vector3 = _to_view(stand_off)
		rig.set_state("grab")
		rig.set_operate_context("grab", 0.0, 0.0, target_cam, true)
	elif _state == "console":
		var ax: float = 0.0
		if InputMap.has_action("move_up") and InputMap.has_action("move_down"):
			ax = Input.get_axis("move_down", "move_up")
		elif InputMap.has_action("move_forward") and InputMap.has_action("move_back"):
			ax = Input.get_axis("move_back", "move_forward")
		rig.set_state("console")
		rig.set_operate_context("console", ax)
	elif _state == "carry":
		rig.set_state("carry")
		rig.set_operate_context("")
	else:
		if rig.state != "idle" and rig.state != "walk" and rig.state != "sprint":
			rig.set_state("idle")
		rig.set_operate_context("")

	rig.set_motion(Vector2.ZERO, moving, sprinting, player.velocity, player.is_on_floor())
	rig.update_rig(delta)

	_reach_error = 0.0
	if _state == "grip" and _left != null and _right != null:
		var rail_world: Vector3 = player.get("brace_target") as Vector3
		var middle: Vector3 = (_left.global_position + _right.global_position) * 0.5
		_reach_error = middle.distance_to(rail_world)


func _to_view(world: Vector3) -> Vector3:
	var local: Vector3 = camera.to_local(world)
	local.z = minf(local.z, -0.18)
	if local.length() > MAX_REACH:
		local = local.normalized() * MAX_REACH
	local.x = clampf(local.x, -0.34, 0.34)
	local.y = clampf(local.y, -0.42, 0.02)
	return local


func state() -> String:
	return _state


func reach_error() -> float:
	return _reach_error
