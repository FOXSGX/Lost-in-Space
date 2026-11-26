class_name Act1Hands
extends Node3D

## Visible first-person gloved hands for Act 01.
## Wraps RealisticHandRig while keeping the Act1Hands public interface intact.

var left_arm: Node3D
var right_arm: Node3D
var state: String = "idle"
var rig: RealisticHandRig


func setup() -> void:
	name = "Hands"
	rig = RealisticHandRig.new()
	rig.name = "RealisticRig"
	add_child(rig)
	rig.setup("default", 1, true)
	left_arm = rig.left_wrist
	right_arm = rig.right_wrist


func set_state(new_state: String) -> void:
	state = new_state
	if rig != null:
		rig.set_state(new_state)


func set_motion(input: Vector2, moving: bool, sprinting: bool = false, vel_3d: Vector3 = Vector3.ZERO, on_floor: bool = true) -> void:
	if rig != null:
		rig.set_motion(input, moving, sprinting, vel_3d, on_floor)
		state = rig.state


func set_operate_context(kind: String, axis: float = 0.0, progress: float = 0.0, target_cam_pos: Vector3 = Vector3.ZERO, has_target: bool = false) -> void:
	if rig != null:
		rig.set_operate_context(kind, axis, progress, target_cam_pos, has_target)


func trigger_action(kind: String, intensity: float = 1.0) -> void:
	if rig != null:
		rig.trigger_action(kind, intensity)


func bob(_time: float, _moving: bool) -> void:
	if rig != null:
		var dt: float = get_physics_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		rig.update_rig(dt)


func anim_grip(amount: float) -> void:
	if rig != null:
		rig.set_grip_amount(amount)
