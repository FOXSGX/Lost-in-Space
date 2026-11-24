class_name GhostMiner
extends Node3D
## A memory performer built from the real protagonist skin, re-materialled with
## the ghost shader and animated by hand.
##
## The old memory actors were a capsule with box limbs: fine at 15 m in third
## person, clearly "placeholder" in first person. This reuses the same validated
## character mesh as the player (correct proportions, helmet, suit details) and
## drives its pivots directly, so a miner can walk, run, ride or cut a rail
## without a skeleton or an imported animation.

const SKIN_PATH := "res://assets/resonance-characters/skins/skin_ranger.glb"
const GHOST_SHADER: Shader = preload("res://shaders/ghost.gdshader")

var _body: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_elbow: Node3D
var _right_elbow: Node3D
var _left_knee: Node3D
var _right_knee: Node3D
var _head: Node3D
var _material: ShaderMaterial
var _phase: float = 0.0
var _kind: String = "idle"
var _time: float = 0.0
var _phase_offset: float = 0.0


func build(tint: Color, strength: float = 0.65, scale_factor: float = 0.82) -> bool:
	var packed: PackedScene = load(SKIN_PATH) as PackedScene
	if packed == null:
		return false
	var root_node: Node3D = packed.instantiate() as Node3D
	if root_node == null:
		return false
	var source_body: Node3D = root_node.find_child("Body", true, false) as Node3D
	if source_body == null:
		root_node.queue_free()
		return false
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	for child: Node in source_body.get_children():
		source_body.remove_child(child)
		child.owner = null
		_body.add_child(child)
	root_node.queue_free()
	_left_arm = _body.find_child("LeftArmPivot", true, false) as Node3D
	_right_arm = _body.find_child("RightArmPivot", true, false) as Node3D
	_left_leg = _body.find_child("LeftLegPivot", true, false) as Node3D
	_right_leg = _body.find_child("RightLegPivot", true, false) as Node3D
	_left_elbow = _body.find_child("LeftElbowPivot", true, false) as Node3D
	_right_elbow = _body.find_child("RightElbowPivot", true, false) as Node3D
	_left_knee = _body.find_child("LeftKneePivot", true, false) as Node3D
	_right_knee = _body.find_child("RightKneePivot", true, false) as Node3D
	_head = _body.find_child("HeadPivot", true, false) as Node3D
	if _left_arm == null or _right_arm == null or _left_leg == null or _right_leg == null:
		return false
	_material = ShaderMaterial.new()
	_material.shader = GHOST_SHADER
	_material.set_shader_parameter("tint", tint)
	_material.set_shader_parameter("strength", strength)
	_material.set_shader_parameter("scan_density", 30.0)
	for node: Node in _body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null:
			continue
		mesh.material_override = _material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scale = Vector3.ONE * scale_factor
	_phase_offset = randf() * TAU
	return true


func set_strength(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter("strength", clampf(value, 0.0, 1.0))


func set_ghost_visible(value: bool) -> void:
	visible = value


## Attach a prop (cutter, lamp, tool) to the right hand so it follows the
## animated arm instead of floating beside the actor.
func attach_to_hand(node: Node3D, offset: Vector3 = Vector3.ZERO, rotation_degrees_value: Vector3 = Vector3.ZERO) -> void:
	if _right_arm == null or node == null:
		return
	var old_parent: Node = node.get_parent()
	if old_parent != null:
		old_parent.remove_child(node)
	node.position = offset
	node.rotation_degrees = rotation_degrees_value
	_right_arm.add_child(node)


## kind: idle / walk / run / ride / cut
func update_anim(delta: float, kind: String, rate_scale: float = 1.0) -> void:
	if _body == null:
		return
	_time += delta
	var rate: float = 8.4
	match kind:
		"run":
			rate = 12.0
		"walk":
			rate = 7.0
		"ride":
			rate = 3.0
		"cut":
			rate = 5.5
		_:
			rate = 1.6
	_phase += delta * rate * rate_scale
	var wave: float = sin(_phase + _phase_offset)
	var amplitude: float = 0.0
	match kind:
		"run":
			amplitude = 0.78
		"walk":
			amplitude = 0.50
		"cut":
			amplitude = 0.10
		_:
			amplitude = 0.0
	var hip_left: float = wave * amplitude
	var hip_right: float = sin(_phase + PI + _phase_offset) * amplitude
	_left_leg.rotation.x = lerpf(_left_leg.rotation.x, hip_left, minf(delta * 18.0, 1.0))
	_right_leg.rotation.x = lerpf(_right_leg.rotation.x, hip_right, minf(delta * 18.0, 1.0))
	if _left_knee != null:
		var bend_left: float = maxf(0.0, -sin(_phase + 0.6 + _phase_offset)) * (1.0 if kind == "run" else 0.75) * (1.0 if amplitude > 0.0 else 0.0)
		_left_knee.rotation.x = lerpf(_left_knee.rotation.x, bend_left, minf(delta * 20.0, 1.0))
	if _right_knee != null:
		var bend_right: float = maxf(0.0, -sin(_phase + PI + 0.6 + _phase_offset)) * (1.0 if kind == "run" else 0.75) * (1.0 if amplitude > 0.0 else 0.0)
		_right_knee.rotation.x = lerpf(_right_knee.rotation.x, bend_right, minf(delta * 20.0, 1.0))
	var arm_left: float = -hip_left * 0.85
	var arm_right: float = -hip_right * 0.85
	match kind:
		"cut":
			# Right arm sawing at rail height, left hand braced on the rail.
			arm_right = -0.95 + sin(_time * 8.0) * 0.35
			arm_left = -0.55
		"ride":
			arm_left = -0.75
			arm_right = -0.75
		"idle":
			arm_left = 0.12 + sin(_time * 1.3 + _phase_offset) * 0.05
			arm_right = 0.12 - sin(_time * 1.3 + _phase_offset) * 0.05
	_left_arm.rotation.x = lerpf(_left_arm.rotation.x, arm_left, minf(delta * 16.0, 1.0))
	_right_arm.rotation.x = lerpf(_right_arm.rotation.x, arm_right, minf(delta * 16.0, 1.0))
	if _left_elbow != null:
		_left_elbow.rotation.x = lerpf(_left_elbow.rotation.x, -0.40 if kind != "cut" else -0.7, minf(delta * 14.0, 1.0))
	if _right_elbow != null:
		_right_elbow.rotation.x = lerpf(_right_elbow.rotation.x, (-0.40 if kind != "cut" else -1.1) + (sin(_time * 8.0) * 0.25 if kind == "cut" else 0.0), minf(delta * 16.0, 1.0))
	# Lean, bob and head. Kept subtle: these are memories, not cartoons.
	var lean: float = 0.12 if kind == "run" else (0.06 if kind == "walk" else (0.18 if kind == "cut" else 0.0))
	_body.rotation.x = lerpf(_body.rotation.x, lean, minf(delta * 8.0, 1.0))
	var bob: float = absf(sin(_phase)) * (0.045 if amplitude > 0.0 else 0.0)
	_body.position.y = lerpf(_body.position.y, -bob, minf(delta * 12.0, 1.0))
	if _head != null:
		_head.rotation.y = lerpf(_head.rotation.y, sin(_time * 0.6 + _phase_offset) * 0.22, minf(delta * 3.0, 1.0))
		_head.rotation.x = lerpf(_head.rotation.x, -lean * 0.5, minf(delta * 6.0, 1.0))
