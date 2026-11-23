class_name FPViewmodel
extends Node3D
## First-person arms with 2-bone IK, wrist orientation, and 5-finger articulation
## for Act 04, backed by RealisticHandRig.

var render_layer: int = 32
var debug_state: String = ""
var grab_point_camera: Vector3 = Vector3(0.16, -0.34, -0.46)

var rig: RealisticHandRig
var _hand_r: Node3D
var _hand_l: Node3D
var _rope_root: Node3D
var _rope: MeshInstance3D
var _time: float = 0.0
var _state: String = "idle"
var _drive_axis: float = 0.0
var _prev_state: String = "idle"


func _ready() -> void:
	name = "Viewmodel"
	rig = RealisticHandRig.new()
	rig.name = "RealisticRig"
	add_child(rig)
	rig.setup("ranger", render_layer, false)
	_hand_r = rig.right_wrist
	_hand_l = rig.left_wrist
	_build_rope()
	_apply_layers()
	snap()


func _build_rope() -> void:
	_rope_root = Node3D.new()
	_rope_root.name = "RopeGrip"
	add_child(_rope_root)
	var rope_mesh: CylinderMesh = CylinderMesh.new()
	rope_mesh.top_radius = 0.019
	rope_mesh.bottom_radius = 0.023
	rope_mesh.height = 0.95
	rope_mesh.radial_segments = 7
	rope_mesh.rings = 1
	_rope = MeshInstance3D.new()
	_rope.name = "RopeSegment"
	_rope.mesh = rope_mesh
	var rope_material: StandardMaterial3D = StandardMaterial3D.new()
	rope_material.albedo_color = Color(0.34, 0.26, 0.15)
	rope_material.roughness = 0.95
	_rope.material_override = rope_material
	_rope.position = Vector3(0.0, 0.44, 0.0)
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope_root.add_child(_rope)
	var wrap: MeshInstance3D = MeshInstance3D.new()
	wrap.name = "RopeWrap"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.028
	torus.outer_radius = 0.010
	torus.rings = 16
	torus.ring_segments = 6
	wrap.mesh = torus
	wrap.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	wrap.material_override = rope_material
	_rope_root.add_child(wrap)
	_rope_root.visible = false


func _apply_layers() -> void:
	if rig != null:
		rig.set_render_layer(render_layer)
	for node: Node in find_children("*", "VisualInstance3D", true, false):
		var instance: VisualInstance3D = node as VisualInstance3D
		if instance != null:
			instance.layers = render_layer


func snap() -> void:
	_time = 0.0
	_state = "idle"
	_prev_state = "idle"
	if rig != null:
		rig.set_state("idle")
		rig.snap_idle()
	if _rope_root != null:
		_rope_root.visible = false


func trigger_action(kind: String, intensity: float = 1.0) -> void:
	if rig != null:
		rig.trigger_action(kind, intensity)


func set_drive_axis(axis: float) -> void:
	_drive_axis = clampf(axis, -1.0, 1.0)


func update_pose(delta: float, state_name: String, speed: float, pull: float, _reach_time: float, forward_room: float) -> void:
	if rig == null:
		return
	_time += delta
	if not debug_state.is_empty():
		state_name = debug_state
		if state_name == "rope":
			pull = 0.7
	_state = state_name

	if _state == "carry" and _prev_state != "carry":
		rig.trigger_action("pickup", 1.0)
	elif _state == "reach" and _prev_state != "reach":
		rig.trigger_action("press", 0.85)
	_prev_state = _state

	rig.set_pull(pull)
	rig.set_wall_room(forward_room)

	if _state == "grab":
		var point: Vector3 = grab_point_camera
		if point.z > -0.25:
			point = Vector3(clampf(point.x, -0.32, 0.32), -0.34, -0.42)
		point.x = clampf(point.x, -0.48, 0.48)
		point.y = clampf(point.y, -0.58, 0.08)
		point.z = clampf(point.z, -0.82, -0.26)
		rig.set_state("grab")
		rig.set_operate_context("grab", 0.0, 0.0, point, true)
	elif _state == "drive":
		rig.set_state("drive")
		rig.set_operate_context("drive", _drive_axis)
	elif _state in ["carry", "rope", "reach"]:
		rig.set_state(_state)
		rig.set_operate_context("")
	else:
		if rig.state != "idle" and rig.state != "walk" and rig.state != "sprint":
			rig.set_state("idle")
		rig.set_operate_context("")

	var moving: bool = _state == "walk" or speed > 0.6
	rig.set_motion(Vector2.ZERO, moving, speed > 5.8, Vector3(0.0, 0.0, -speed), true)
	rig.update_rig(delta)

	if _rope_root != null:
		_rope_root.visible = _state == "rope"
		if _rope_root.visible and _hand_r != null:
			_rope_root.position = to_local(_hand_r.global_position) + Vector3(-0.012, 0.012, -0.015)
			_rope_root.rotation_degrees = Vector3(-10.0 - pull * 10.0, 0.0, sin(_time * 3.0) * 0.7)
			_rope.rotation_degrees.z = 2.0 + sin(_time * 2.0) * 0.6
