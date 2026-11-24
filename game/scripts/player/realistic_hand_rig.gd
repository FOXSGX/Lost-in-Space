class_name RealisticHandRig
extends Node3D

## Biomechanical two-arm first-person hand rig with 2-bone IK, radioulnar
## forearm twist, independent wrist orientation, 5-finger 3-phalanx
## articulation, spring-damper inertia, and multi-phase interaction gestures.

const UPPER_LENGTH := 0.31
const FOREARM_LENGTH := 0.30
const SHOULDER_LEFT := Vector3(-0.25, -0.21, 0.06)
const SHOULDER_RIGHT := Vector3(0.25, -0.21, 0.06)
const MAX_REACH := 0.595
const MIN_REACH := 0.14

const FINGER_OFFSETS := [
	Vector3(-0.027, 0.001, -0.092), # index
	Vector3(-0.009, 0.003, -0.097), # middle
	Vector3(0.010, 0.001, -0.093),  # ring
	Vector3(0.027, -0.003, -0.085), # pinky
]
const FINGER_PROX := [0.036, 0.041, 0.037, 0.029]
const FINGER_MID := [0.024, 0.027, 0.025, 0.020]
const FINGER_DIST := [0.020, 0.022, 0.020, 0.017]
const FINGER_RADII := [0.0092, 0.0096, 0.0090, 0.0078]
const FINGER_SPLAY_WEIGHTS := [-1.0, -0.28, 0.36, 1.05]

var render_layer: int = 1
var state: String = "idle"
var left_wrist: Node3D
var right_wrist: Node3D
var left_forearm_mesh: MeshInstance3D
var right_forearm_mesh: MeshInstance3D

var _root: Node3D
var _left_arm_data: Dictionary = {}
var _right_arm_data: Dictionary = {}

var _clock: float = 0.0
var _walk_phase: float = 0.0
var _climb_phase: float = 0.0
var _crank_phase: float = 0.0
var _pump_phase: float = 0.0
var _state_time: float = 0.0

var _motion_input: Vector2 = Vector2.ZERO
var _moving: bool = false
var _sprinting: bool = false
var _speed: float = 0.0
var _velocity_3d: Vector3 = Vector3.ZERO
var _was_on_floor: bool = true
var _on_floor: bool = true
var _prev_vel_y: float = 0.0

var _operate_kind: String = ""
var _operate_axis: float = 0.0
var _operate_progress: float = 0.0
var _target_cam_pos: Vector3 = Vector3.ZERO
var _has_target_cam: bool = false
var _pull_amount: float = 0.0
var _grip_override: float = -1.0
var _forward_room: float = 4.0

var _action_kind: String = ""
var _action_timer: float = 0.0
var _action_duration: float = 0.35
var _action_intensity: float = 1.0

# Spring-damper camera & movement inertia
var _prev_cam_basis: Basis = Basis.IDENTITY
var _cam_basis_init: bool = false
var _lag_offset: Vector3 = Vector3.ZERO
var _lag_vel: Vector3 = Vector3.ZERO
var _rot_lag: Vector2 = Vector2.ZERO
var _rot_lag_vel: Vector2 = Vector2.ZERO
var _land_bob: float = 0.0
var _land_vel: float = 0.0

# Smoothed pose state per arm
var _cur_pos_l: Vector3 = Vector3(-0.21, -0.25, -0.34)
var _cur_pos_r: Vector3 = Vector3(0.21, -0.25, -0.34)
var _cur_rot_l: Quaternion = Quaternion.IDENTITY
var _cur_rot_r: Quaternion = Quaternion.IDENTITY
var _cur_curls_l: Array[float] = [0.24, 0.32, 0.40, 0.48, 0.22]
var _cur_curls_r: Array[float] = [0.24, 0.32, 0.40, 0.48, 0.22]
var _cur_splay_l: float = 0.03
var _cur_splay_r: float = 0.03
var _cur_abduct_l: float = 0.55
var _cur_abduct_r: float = 0.55

var _mat_suit: StandardMaterial3D
var _mat_suit_dark: StandardMaterial3D
var _mat_glove: StandardMaterial3D
var _mat_glove_pad: StandardMaterial3D
var _mat_plate: StandardMaterial3D
var _mat_trim: StandardMaterial3D
var _key_light: OmniLight3D


func setup(palette_preset: String = "default", p_render_layer: int = 1, add_hand_light: bool = true) -> void:
	render_layer = p_render_layer
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "ArmRigRoot"
	add_child(_root)
	_build_materials(palette_preset)
	_left_arm_data = _build_arm(-1.0, "Left")
	_right_arm_data = _build_arm(1.0, "Right")
	left_wrist = _left_arm_data["wrist"] as Node3D
	right_wrist = _right_arm_data["wrist"] as Node3D
	left_forearm_mesh = _left_arm_data["forearm_mesh"] as MeshInstance3D
	right_forearm_mesh = _right_arm_data["forearm_mesh"] as MeshInstance3D
	if add_hand_light:
		_key_light = OmniLight3D.new()
		_key_light.name = "HandFillLight"
		_key_light.position = Vector3(0.0, -0.14, -0.58)
		_key_light.light_color = Color(0.80, 0.89, 1.0)
		_key_light.light_energy = 0.32
		_key_light.omni_range = 1.15
		_key_light.omni_attenuation = 2.2
		_key_light.shadow_enabled = false
		_key_light.light_cull_mask = render_layer
		add_child(_key_light)
	set_render_layer(render_layer)
	snap_idle()


func set_render_layer(layer_value: int) -> void:
	render_layer = layer_value
	for node: Node in find_children("*", "VisualInstance3D", true, false):
		var vi: VisualInstance3D = node as VisualInstance3D
		if vi != null:
			vi.layers = render_layer
	if _key_light != null:
		_key_light.light_cull_mask = render_layer


func _build_materials(preset: String) -> void:
	if preset == "ranger":
		_mat_suit = _make_mat(Color(0.17, 0.21, 0.26), 0.84, 0.05)
		_mat_suit_dark = _make_mat(Color(0.09, 0.12, 0.16), 0.90, 0.03)
		_mat_plate = _make_mat(Color(0.46, 0.52, 0.58), 0.44, 0.48)
		_mat_glove = _make_mat(Color(0.56, 0.59, 0.60), 0.72, 0.04)
		_mat_glove_pad = _make_mat(Color(0.14, 0.17, 0.21), 0.85, 0.04)
		_mat_trim = _make_emissive(Color(0.32, 0.88, 1.0), 1.05)
	else:
		_mat_suit = _make_mat(Color(0.07, 0.12, 0.16), 0.80, 0.05)
		_mat_suit_dark = _make_mat(Color(0.04, 0.07, 0.10), 0.86, 0.06)
		_mat_plate = _make_mat(Color(0.13, 0.17, 0.22), 0.52, 0.28)
		_mat_glove = _make_mat(Color(0.20, 0.25, 0.30), 0.64, 0.06)
		_mat_glove_pad = _make_mat(Color(0.10, 0.13, 0.17), 0.82, 0.04)
		_mat_trim = _make_emissive(Color(0.24, 0.78, 0.88), 0.85)


func _make_mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _make_emissive(col: Color, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.32
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO, mesh_scale: Vector3 = Vector3.ONE, mesh_name: String = "") -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	if not mesh_name.is_empty():
		mi.name = mesh_name
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = mesh_scale
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float, segs: int = 10) -> CapsuleMesh:
	var m: CapsuleMesh = CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = segs
	m.rings = 3
	return m


func _cyl(top_r: float, bot_r: float, h: float, segs: int = 12) -> CylinderMesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bot_r
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


func _sphere(r: float, segs: int = 10) -> SphereMesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = 6
	return m


func _box(sz: Vector3) -> BoxMesh:
	var m: BoxMesh = BoxMesh.new()
	m.size = sz
	return m


func _build_arm(side: float, tag: String) -> Dictionary:
	var shoulder: Node3D = Node3D.new()
	shoulder.name = "Shoulder" + tag
	shoulder.position = SHOULDER_LEFT if side < 0.0 else SHOULDER_RIGHT
	_root.add_child(shoulder)

	# Upper arm (stays behind/below lens normally, enters cleanly on full reaches)
	_add_mesh(shoulder, _capsule(0.052, UPPER_LENGTH + 0.02, 10), Vector3(0.0, 0.0, -UPPER_LENGTH * 0.5), _mat_suit, Vector3(90.0, 0.0, 0.0), Vector3.ONE, "UpperSleeve")
	_add_mesh(shoulder, _sphere(0.048, 10), Vector3(0.0, 0.0, -UPPER_LENGTH), _mat_suit_dark, Vector3.ZERO, Vector3(1.0, 0.92, 1.05), "ElbowPad")

	var elbow: Node3D = Node3D.new()
	elbow.name = "Elbow" + tag
	elbow.position = Vector3(0.0, 0.0, -UPPER_LENGTH)
	shoulder.add_child(elbow)

	# Tapered EVA forearm sleeve + protective plate + beveled cuff collar + wrist seal
	var fore_mesh: MeshInstance3D = _add_mesh(
		elbow,
		_cyl(0.037, 0.051, FOREARM_LENGTH * 0.88, 16),
		Vector3(0.0, 0.0, -FOREARM_LENGTH * 0.44),
		_mat_suit,
		Vector3(90.0, 0.0, 0.0),
		Vector3.ONE,
		"ForearmSleeve"
	)
	_add_mesh(elbow, _box(Vector3(0.013, 0.032, 0.13)), Vector3(0.041 * side, 0.004, -FOREARM_LENGTH * 0.45), _mat_plate, Vector3(0.0, 0.0, -8.0 * side), Vector3.ONE, "ForearmPlate")
	_add_mesh(elbow, _cyl(0.040, 0.038, 0.016, 16), Vector3(0.0, 0.0, -FOREARM_LENGTH * 0.86), _mat_suit_dark, Vector3(90.0, 0.0, 0.0), Vector3.ONE, "CuffCollar")
	_add_mesh(elbow, _cyl(0.034, 0.037, 0.040, 16), Vector3(0.0, 0.0, -FOREARM_LENGTH * 0.92), _mat_suit_dark, Vector3(90.0, 0.0, 0.0), Vector3.ONE, "WristSeal")
	_add_mesh(elbow, _cyl(0.0395, 0.0395, 0.008, 16), Vector3(0.0, 0.0, -FOREARM_LENGTH * 0.84), _mat_trim, Vector3(90.0, 0.0, 0.0), Vector3.ONE, "CuffRing")

	# Wrist / Hand pivot
	var wrist: Node3D = Node3D.new()
	wrist.name = "Wrist" + tag
	wrist.position = Vector3(0.0, 0.0, -FOREARM_LENGTH)
	elbow.add_child(wrist)

	# Carpal wrist bridge + contoured metacarpal palm + integrated grip pad
	_add_mesh(wrist, _sphere(0.033, 12), Vector3(0.0, -0.001, -0.012), _mat_glove_pad, Vector3.ZERO, Vector3(1.10, 0.50, 0.95), "WristBridge")
	_add_mesh(wrist, _box(Vector3(0.074, 0.021, 0.078)), Vector3(0.0, 0.0, -0.052), _mat_glove, Vector3.ZERO, Vector3.ONE, "PalmCore")
	_add_mesh(wrist, _box(Vector3(0.064, 0.007, 0.058)), Vector3(0.0, -0.009, -0.054), _mat_glove_pad, Vector3.ZERO, Vector3.ONE, "PalmGripPad")
	# Subtle thenar / hypothenar contours blended flush into the glove
	_add_mesh(wrist, _sphere(0.022, 10), Vector3(-0.020 * side, -0.004, -0.044), _mat_glove, Vector3.ZERO, Vector3(1.00, 0.46, 1.30), "ThenarPad")
	_add_mesh(wrist, _sphere(0.019, 10), Vector3(0.024 * side, -0.003, -0.052), _mat_glove, Vector3.ZERO, Vector3(0.92, 0.46, 1.35), "HypothenarPad")
	# Dorsal armor plate + knuckle ridge + slim status light
	_add_mesh(wrist, _box(Vector3(0.064, 0.010, 0.058)), Vector3(0.0, 0.013, -0.052), _mat_plate, Vector3(-3.0, 0.0, 0.0), Vector3.ONE, "DorsalPlate")
	_add_mesh(wrist, _capsule(0.011, 0.076, 8), Vector3(0.0, 0.005, -0.090), _mat_glove_pad, Vector3(0.0, 0.0, 90.0), Vector3.ONE, "KnuckleBar")
	_add_mesh(wrist, _box(Vector3(0.032, 0.005, 0.008)), Vector3(0.0, 0.019, -0.042), _mat_trim, Vector3.ZERO, Vector3.ONE, "HandLED")

	# Four 3-phalanx articulated fingers
	var fingers: Array = []
	for i: int in range(4):
		var base_off: Vector3 = FINGER_OFFSETS[i]
		var mcp: Node3D = Node3D.new()
		mcp.name = "Finger%dMCP" % i
		mcp.position = Vector3(base_off.x * side, base_off.y, base_off.z)
		wrist.add_child(mcp)

		var r: float = FINGER_RADII[i]
		var lp: float = FINGER_PROX[i]
		var lm: float = FINGER_MID[i]
		var ld: float = FINGER_DIST[i]
		_add_mesh(mcp, _sphere(r * 1.04, 8), Vector3.ZERO, _mat_glove_pad, Vector3.ZERO, Vector3.ONE, "Knuckle%d" % i)
		_add_mesh(mcp, _capsule(r, lp + r * 1.1, 8), Vector3(0.0, 0.0, -lp * 0.5), _mat_glove, Vector3(90.0, 0.0, 0.0), Vector3.ONE, "Prox%d" % i)

		var pip: Node3D = Node3D.new()
		pip.name = "Finger%dPIP" % i
		pip.position = Vector3(0.0, 0.0, -lp)
		mcp.add_child(pip)
		_add_mesh(pip, _capsule(r * 0.90, lm + r * 0.9, 8), Vector3(0.0, 0.0, -lm * 0.5), _mat_glove, Vector3(90.0, 0.0, 0.0), Vector3.ONE, "Mid%d" % i)

		var dip: Node3D = Node3D.new()
		dip.name = "Finger%dDIP" % i
		dip.position = Vector3(0.0, 0.0, -lm)
		pip.add_child(dip)
		_add_mesh(dip, _capsule(r * 0.80, ld + r * 0.8, 8), Vector3(0.0, 0.0, -ld * 0.5), _mat_glove_pad, Vector3(90.0, 0.0, 0.0), Vector3.ONE, "Dist%d" % i)

		fingers.append({"mcp": mcp, "pip": pip, "dip": dip, "splay_w": FINGER_SPLAY_WEIGHTS[i]})

	# Opposable 2-joint thumb on the MEDIAL (-side) edge
	var thumb_cmc: Node3D = Node3D.new()
	thumb_cmc.name = "ThumbCMC"
	thumb_cmc.position = Vector3(-0.036 * side, -0.006, -0.028)
	wrist.add_child(thumb_cmc)
	_add_mesh(thumb_cmc, _capsule(0.0125, 0.034, 8), Vector3(0.0, 0.0, -0.017), _mat_glove, Vector3(90.0, 0.0, 0.0), Vector3.ONE, "ThumbProx")

	var thumb_ip: Node3D = Node3D.new()
	thumb_ip.name = "ThumbIP"
	thumb_ip.position = Vector3(0.0, 0.0, -0.033)
	thumb_cmc.add_child(thumb_ip)
	_add_mesh(thumb_ip, _capsule(0.0110, 0.030, 8), Vector3(0.0, 0.0, -0.014), _mat_glove_pad, Vector3(90.0, 0.0, 0.0), Vector3.ONE, "ThumbDist")

	return {
		"side": side,
		"shoulder": shoulder,
		"elbow": elbow,
		"wrist": wrist,
		"forearm_mesh": fore_mesh,
		"fingers": fingers,
		"thumb_cmc": thumb_cmc,
		"thumb_ip": thumb_ip,
	}


func set_state(new_state: String) -> void:
	if new_state == state:
		return
	state = new_state
	_state_time = 0.0


func set_motion(input: Vector2, moving: bool, sprinting: bool = false, vel_3d: Vector3 = Vector3.ZERO, on_floor: bool = true) -> void:
	_motion_input = input
	_moving = moving
	_sprinting = sprinting
	_velocity_3d = vel_3d
	_speed = Vector2(vel_3d.x, vel_3d.z).length()
	if not _moving and _speed > 0.35:
		_moving = true
	_was_on_floor = _on_floor
	_on_floor = on_floor
	if not _was_on_floor and _on_floor and _prev_vel_y < -1.5:
		_land_vel = clampf(_prev_vel_y * 0.018, -0.14, -0.015)
	_prev_vel_y = vel_3d.y
	if state == "idle" or state == "walk" or state == "sprint":
		if _moving:
			set_state("sprint" if _sprinting else "walk")
		else:
			set_state("idle")


func set_operate_context(kind: String, axis: float = 0.0, progress: float = 0.0, target_cam_pos: Vector3 = Vector3.ZERO, has_target: bool = false) -> void:
	_operate_kind = kind
	_operate_axis = axis
	_operate_progress = progress
	_target_cam_pos = target_cam_pos
	_has_target_cam = has_target


func set_pull(amount: float) -> void:
	_pull_amount = clampf(amount, 0.0, 1.0)


func set_grip_amount(amount: float) -> void:
	_grip_override = clampf(amount, 0.0, 1.0)


func set_wall_room(forward_room: float) -> void:
	_forward_room = clampf(forward_room, 0.0, 4.0)


func trigger_action(kind: String, intensity: float = 1.0) -> void:
	_action_kind = kind
	_action_timer = 0.0
	_action_intensity = clampf(intensity, 0.3, 1.5)
	match kind:
		"shove":
			_action_duration = 0.42
		"pull_pin", "latch":
			_action_duration = 0.44
		"clamp", "turn":
			_action_duration = 0.46
		"slam":
			_action_duration = 0.38
		"pickup":
			_action_duration = 0.36
		"throw":
			_action_duration = 0.34
		"drop":
			_action_duration = 0.30
		"rotate":
			_action_duration = 0.24
		"switch":
			_action_duration = 0.30
		_:
			_action_duration = 0.32


func snap_idle() -> void:
	_clock = 0.0
	_walk_phase = 0.0
	_state_time = 0.5
	_action_kind = ""
	var p_l: Dictionary = _pose_for(-1.0)
	var p_r: Dictionary = _pose_for(1.0)
	_cur_pos_l = p_l["pos"] as Vector3
	_cur_pos_r = p_r["pos"] as Vector3
	_cur_rot_l = _palm_quat(p_l["fwd"] as Vector3, p_l["up"] as Vector3)
	_cur_rot_r = _palm_quat(p_r["fwd"] as Vector3, p_r["up"] as Vector3)
	_solve_arm(_left_arm_data, SHOULDER_LEFT, _cur_pos_l, _cur_rot_l, p_l["pole"] as Vector3)
	_solve_arm(_right_arm_data, SHOULDER_RIGHT, _cur_pos_r, _cur_rot_r, p_r["pole"] as Vector3)
	_apply_fingers(_left_arm_data, _cur_curls_l, _cur_splay_l, _cur_abduct_l)
	_apply_fingers(_right_arm_data, _cur_curls_r, _cur_splay_r, _cur_abduct_r)


func update_rig(delta: float) -> void:
	if _root == null:
		return
	var dt: float = clampf(delta, 0.0001, 0.05)
	_clock += dt
	_state_time += dt

	# Advance locomotion & mechanical phases smoothly
	var walk_speed_factor: float = maxf(_speed / 4.2, 1.0 if _moving else 0.0)
	if _moving:
		_walk_phase += dt * (9.8 if _sprinting else 7.2) * clampf(walk_speed_factor, 0.65, 1.6)
	if state == "climb":
		var climb_dir: float = _operate_axis if absf(_operate_axis) > 0.05 else 0.75
		_climb_phase += dt * 4.4 * climb_dir
	if state == "wheel" or _operate_kind == "wheel":
		if absf(_operate_axis) > 0.05:
			_crank_phase += dt * 4.5 * _operate_axis
	if _operate_kind == "pump" and _operate_axis > 0.05:
		_pump_phase += dt * 6.5 * _operate_axis

	# Update camera-rotation inertia + landing compression spring
	_update_inertia(dt)

	# Compute target anatomical poses
	var target_l: Dictionary = _pose_for(-1.0)
	var target_r: Dictionary = _pose_for(1.0)

	# Layer active one-shot action gesture arc on top
	if not _action_kind.is_empty():
		_action_timer += dt
		if _action_timer >= _action_duration:
			_action_kind = ""
		else:
			var u: float = clampf(_action_timer / _action_duration, 0.0, 1.0)
			_apply_action_gesture(u, target_l, target_r)

	# Add subtle spring-damped camera/movement inertia
	var inertia_pos_l: Vector3 = _lag_offset + Vector3(0.0, _land_bob, 0.0)
	var inertia_pos_r: Vector3 = _lag_offset + Vector3(0.0, _land_bob, 0.0)
	if state in ["grab", "climb", "push", "lever", "wheel", "console", "drive", "rope"]:
		inertia_pos_l *= 0.25
		inertia_pos_r *= 0.25

	var want_pos_l: Vector3 = _clamp_reach(SHOULDER_LEFT, (target_l["pos"] as Vector3) + inertia_pos_l)
	var want_pos_r: Vector3 = _clamp_reach(SHOULDER_RIGHT, (target_r["pos"] as Vector3) + inertia_pos_r)
	var want_rot_l: Quaternion = _palm_quat(target_l["fwd"] as Vector3, target_l["up"] as Vector3)
	var want_rot_r: Quaternion = _palm_quat(target_r["fwd"] as Vector3, target_r["up"] as Vector3)

	var pos_rate: float = 22.0 if not _action_kind.is_empty() else (18.0 if state != "idle" else 13.0)
	var rot_rate: float = 20.0 if not _action_kind.is_empty() else 15.0
	var pos_blend: float = 1.0 - exp(-pos_rate * dt)
	var rot_blend: float = 1.0 - exp(-rot_rate * dt)

	_cur_pos_l = _cur_pos_l.lerp(want_pos_l, pos_blend)
	_cur_pos_r = _cur_pos_r.lerp(want_pos_r, pos_blend)
	_cur_rot_l = _cur_rot_l.slerp(want_rot_l, rot_blend)
	_cur_rot_r = _cur_rot_r.slerp(want_rot_r, rot_blend)

	_solve_arm(_left_arm_data, SHOULDER_LEFT, _cur_pos_l, _cur_rot_l, target_l["pole"] as Vector3)
	_solve_arm(_right_arm_data, SHOULDER_RIGHT, _cur_pos_r, _cur_rot_r, target_r["pole"] as Vector3)

	# Smooth finger curls & splay
	var f_blend: float = 1.0 - exp(-22.0 * dt)
	var want_curls_l: Array = target_l["curls"] as Array
	var want_curls_r: Array = target_r["curls"] as Array
	for i: int in range(5):
		var cl: float = float(want_curls_l[i])
		var cr: float = float(want_curls_r[i])
		if _grip_override >= 0.0:
			cl = lerpf(cl, _grip_override, 0.75)
			cr = lerpf(cr, _grip_override, 0.75)
		_cur_curls_l[i] = lerpf(_cur_curls_l[i], cl, f_blend)
		_cur_curls_r[i] = lerpf(_cur_curls_r[i], cr, f_blend)
	_cur_splay_l = lerpf(_cur_splay_l, float(target_l["splay"]), f_blend)
	_cur_splay_r = lerpf(_cur_splay_r, float(target_r["splay"]), f_blend)
	_cur_abduct_l = lerpf(_cur_abduct_l, float(target_l["abduct"]), f_blend)
	_cur_abduct_r = lerpf(_cur_abduct_r, float(target_r["abduct"]), f_blend)

	_apply_fingers(_left_arm_data, _cur_curls_l, _cur_splay_l, _cur_abduct_l)
	_apply_fingers(_right_arm_data, _cur_curls_r, _cur_splay_r, _cur_abduct_r)

	# Wall proximity pull-in so hands never clip through solid walls
	var push_back: float = 0.0
	if _forward_room < 0.78:
		push_back = (0.78 - _forward_room) * 0.75
	_root.position.z = lerpf(_root.position.z, push_back, 1.0 - exp(-18.0 * dt))
	_root.visible = _forward_room >= 0.26


func _update_inertia(dt: float) -> void:
	var cam: Camera3D = get_parent() as Camera3D
	var yaw_rate: float = 0.0
	var pitch_rate: float = 0.0
	if cam != null:
		var b: Basis = cam.global_transform.basis.orthonormalized()
		if _cam_basis_init:
			var delta_b: Basis = _prev_cam_basis.inverse() * b
			var eul: Vector3 = delta_b.get_euler()
			yaw_rate = clampf(eul.y / dt, -8.0, 8.0)
			pitch_rate = clampf(eul.x / dt, -8.0, 8.0)
		_prev_cam_basis = b
		_cam_basis_init = true

	var target_lag: Vector3 = Vector3(
		clampf(yaw_rate * 0.008 - _motion_input.x * 0.016, -0.045, 0.045),
		clampf(-pitch_rate * 0.007 - clampf(_velocity_3d.y * 0.004, -0.025, 0.025), -0.040, 0.040),
		clampf(_motion_input.y * 0.014, -0.025, 0.025)
	)
	var stiffness: float = 150.0
	var damping: float = 19.0
	var force: Vector3 = (target_lag - _lag_offset) * stiffness - _lag_vel * damping
	_lag_vel += force * dt
	_lag_offset += _lag_vel * dt

	var land_force: float = -_land_bob * 170.0 - _land_vel * 20.0
	_land_vel += land_force * dt
	_land_bob += _land_vel * dt


func _clamp_reach(shoulder: Vector3, target: Vector3) -> Vector3:
	var delta_v: Vector3 = target - shoulder
	var d: float = delta_v.length()
	if d < 0.0001:
		return shoulder + Vector3(0.0, 0.0, -MIN_REACH)
	if d > MAX_REACH:
		return shoulder + delta_v * (MAX_REACH / d)
	if d < MIN_REACH:
		return shoulder + delta_v * (MIN_REACH / d)
	return target


func _palm_quat(fwd: Vector3, up: Vector3) -> Quaternion:
	var f: Vector3 = fwd.normalized()
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	var u: Vector3 = up - f * up.dot(f)
	if u.length_squared() < 0.0004:
		u = Vector3.UP - f * f.y
	if u.length_squared() < 0.0004:
		u = Vector3.RIGHT
	u = u.normalized()
	return Basis.looking_at(f, u).get_rotation_quaternion()


func _solve_arm(arm: Dictionary, shoulder_pos: Vector3, wrist_target: Vector3, wrist_rot: Quaternion, pole: Vector3) -> void:
	var shoulder: Node3D = arm["shoulder"] as Node3D
	var elbow: Node3D = arm["elbow"] as Node3D
	var wrist: Node3D = arm["wrist"] as Node3D
	if shoulder == null or elbow == null or wrist == null:
		return
	var to_target: Vector3 = wrist_target - shoulder_pos
	var dist: float = clampf(to_target.length(), MIN_REACH, UPPER_LENGTH + FOREARM_LENGTH - 0.004)
	var dir: Vector3 = to_target.normalized()
	var along: float = (UPPER_LENGTH * UPPER_LENGTH - FOREARM_LENGTH * FOREARM_LENGTH + dist * dist) / (2.0 * dist)
	var height: float = sqrt(maxf(UPPER_LENGTH * UPPER_LENGTH - along * along, 0.0))
	var pole_dir: Vector3 = pole - dir * pole.dot(dir)
	if pole_dir.length_squared() < 0.0004:
		pole_dir = Vector3.DOWN - dir * dir.y
	if pole_dir.length_squared() < 0.0004:
		pole_dir = Vector3.RIGHT
	pole_dir = pole_dir.normalized()
	var elbow_pos: Vector3 = shoulder_pos + dir * along + pole_dir * height

	var upper_dir: Vector3 = (elbow_pos - shoulder_pos).normalized()
	var fore_dir: Vector3 = (wrist_target - elbow_pos).normalized()
	var palm_basis: Basis = Basis(wrist_rot)
	var palm_up: Vector3 = palm_basis.y
	# Radioulnar twist: forearm shares ~45% of the wrist's pronation/supination roll
	var natural_up: Vector3 = (pole_dir * -0.35 + Vector3.UP * 0.94).normalized()
	var upper_up: Vector3 = _safe_up(upper_dir, natural_up)
	var fore_up: Vector3 = _safe_up(fore_dir, palm_up.lerp(natural_up, 0.45))

	var upper_basis: Basis = Basis.looking_at(upper_dir, upper_up)
	var fore_basis: Basis = Basis.looking_at(fore_dir, fore_up)

	shoulder.basis = upper_basis
	elbow.basis = upper_basis.inverse() * fore_basis
	wrist.basis = (fore_basis.inverse() * palm_basis).orthonormalized()


func _safe_up(forward_dir: Vector3, hint: Vector3) -> Vector3:
	var u: Vector3 = hint - forward_dir * hint.dot(forward_dir)
	if u.length_squared() < 0.0004:
		u = Vector3.UP - forward_dir * forward_dir.y
	if u.length_squared() < 0.0004:
		u = Vector3.RIGHT - forward_dir * forward_dir.x
	return u.normalized()


func _apply_fingers(arm: Dictionary, curls: Array[float], splay: float, abduct: float) -> void:
	var side: float = float(arm["side"])
	var fingers: Array = arm["fingers"] as Array
	for i: int in range(4):
		var f: Dictionary = fingers[i] as Dictionary
		var mcp: Node3D = f["mcp"] as Node3D
		var pip: Node3D = f["pip"] as Node3D
		var dip: Node3D = f["dip"] as Node3D
		var c: float = clampf(curls[i], -0.15, 1.10)
		var sw: float = float(f["splay_w"])
		if c >= 0.0:
			mcp.rotation = Vector3(-c * 1.10, -sw * side * splay, 0.0)
			pip.rotation = Vector3(-c * 1.38, 0.0, 0.0)
			dip.rotation = Vector3(-c * 0.92, 0.0, 0.0)
		else:
			# Slight hyperextension when pressing flat against heavy surfaces
			mcp.rotation = Vector3(-c * 0.70, -sw * side * splay, 0.0)
			pip.rotation = Vector3(0.02, 0.0, 0.0)
			dip.rotation = Vector3(0.02, 0.0, 0.0)

	var tc: float = clampf(curls[4], -0.10, 1.05)
	var thumb_cmc: Node3D = arm["thumb_cmc"] as Node3D
	var thumb_ip: Node3D = arm["thumb_ip"] as Node3D
	if thumb_cmc != null:
		thumb_cmc.rotation = Vector3(
			-0.24 - tc * 0.44,
			side * (0.42 + abduct * 0.34 - tc * 0.16),
			side * (0.36 + tc * 0.48)
		)
	if thumb_ip != null:
		thumb_ip.rotation = Vector3(-0.14 - tc * 0.88, 0.0, 0.0)


func _pose_for(side: float) -> Dictionary:
	var breath_phase: float = _clock * 1.48 + (0.38 if side < 0.0 else 0.0)
	var breath: float = sin(breath_phase) * 0.005
	var breath_roll: float = cos(breath_phase) * 0.04
	var pole: Vector3 = Vector3(0.52 * side, -0.58, 0.14)
	var eff_state: String = state
	if eff_state == "lever" and (_operate_kind == "wheel" or _operate_kind == "damper" or _operate_kind == "brake"):
		eff_state = "wheel"
	elif eff_state == "lever" and _operate_kind == "climb":
		eff_state = "climb"

	match eff_state:
		"walk":
			var ph: float = _walk_phase + (PI if side < 0.0 else 0.0)
			var sw: float = sin(ph)
			var lift: float = maxf(0.0, sw) * 0.028 + absf(cos(ph)) * 0.008
			var amt: float = clampf(_speed / 4.5, 0.55, 1.15)
			var pos: Vector3 = Vector3(
				0.21 * side - sw * 0.018 * side * amt,
				-0.245 + lift * amt + breath * 0.5,
				-0.34 - sw * 0.048 * amt
			)
			var fwd: Vector3 = Vector3(-0.18 * side, -0.05 + sw * 0.14 * amt, -0.96).normalized()
			var up: Vector3 = Vector3(-0.52 * side, 0.84, 0.12 - sw * 0.08).normalized()
			return _pose(pos, fwd, up, pole, [0.30, 0.38, 0.45, 0.52, 0.28], 0.02, 0.45)

		"sprint":
			var ph: float = _walk_phase + (PI if side < 0.0 else 0.0)
			var sw: float = sin(ph)
			var lift: float = maxf(0.0, sw) * 0.042 + absf(cos(ph)) * 0.012
			var pos: Vector3 = Vector3(
				0.185 * side - sw * 0.032 * side,
				-0.205 + lift,
				-0.37 - sw * 0.068
			)
			var fwd: Vector3 = Vector3(-0.34 * side, 0.12 + sw * 0.20, -0.92).normalized()
			var up: Vector3 = Vector3(-0.62 * side, 0.76, 0.14).normalized()
			return _pose(pos, fwd, up, Vector3(0.58 * side, -0.52, 0.10), [0.50, 0.56, 0.62, 0.68, 0.44], 0.01, 0.38)

		"grab", "grip":
			var snap_t: float = clampf(_state_time / 0.14, 0.0, 1.0)
			var grip_close: float = smoothstep(0.25, 1.0, snap_t)
			var sway: float = sin(_clock * 6.5) * 0.0025
			var target: Vector3 = Vector3(0.0, -0.18, -0.44)
			if _has_target_cam:
				target = _target_cam_pos
				target.z = clampf(target.z, -0.56, -0.24)
				target.x = clampf(target.x, -0.28, 0.28)
				target.y = clampf(target.y, -0.36, 0.05)
			var pos: Vector3 = target + Vector3(0.165 * side, 0.018 + (1.0 - snap_t) * 0.03 + sway, 0.045)
			var fwd: Vector3 = Vector3(-0.08 * side, -0.48, -0.87).normalized()
			var up: Vector3 = Vector3(0.16 * side, 0.87, -0.46).normalized()
			var c_base: float = lerpf(0.22, 0.90, grip_close)
			return _pose(pos, fwd, up, Vector3(0.60 * side, -0.50, 0.12), [c_base, c_base + 0.03, c_base + 0.05, c_base + 0.06, lerpf(0.20, 0.78, grip_close)], lerpf(0.08, 0.01, grip_close), 0.52)

		"lever":
			var ax: float = clampf(_operate_axis, -1.0, 1.0)
			var pump_off: Vector3 = Vector3.ZERO
			if _operate_kind == "pump" and ax > 0.05:
				var p_wave: float = sin(_pump_phase)
				pump_off = Vector3(0.0, -p_wave * 0.050 - 0.015, p_wave * 0.035)
			var strain: float = sin(_clock * 22.0) * 0.002 * absf(ax)
			var pos: Vector3 = Vector3(
				0.135 * side + strain,
				-0.180 - absf(ax) * 0.022 + breath * 0.4,
				-0.425 - ax * 0.085
			) + pump_off
			var pitch_f: float = -0.22 - ax * 0.24
			var fwd: Vector3 = Vector3(-0.12 * side, pitch_f, -0.94).normalized()
			var up: Vector3 = Vector3(0.22 * side, 0.92, pitch_f * 0.85).normalized()
			var c_tight: float = 0.86 + absf(ax) * 0.10
			return _pose(pos, fwd, up, Vector3(0.58 * side, -0.46, 0.12), [c_tight, c_tight + 0.02, c_tight + 0.04, c_tight + 0.05, 0.78], 0.01, 0.45)

		"wheel":
			var ph: float = _crank_phase + (PI if side < 0.0 else 0.0)
			var r_wheel: float = 0.13
			var turning: bool = absf(_operate_axis) > 0.05
			var orb_x: float = cos(ph) * r_wheel if turning else 0.145 * side
			var orb_y: float = sin(ph) * r_wheel * 0.75 if turning else 0.0
			var regrip: float = maxf(0.0, -sin(ph)) if turning else 0.0
			var pos: Vector3 = Vector3(
				orb_x * 0.85 + 0.04 * side,
				-0.20 + orb_y,
				-0.42 - regrip * 0.035
			)
			var fwd: Vector3 = Vector3(-0.22 * side, -0.18, -0.95).normalized()
			var up: Vector3 = Vector3(0.68 * side, 0.68, -0.26).normalized()
			var c_w: float = lerpf(0.88, 0.36, regrip * 0.75)
			return _pose(pos, fwd, up, Vector3(0.62 * side, -0.48, 0.12), [c_w, c_w + 0.03, c_w + 0.05, c_w + 0.06, 0.72], 0.03, 0.55)

		"push":
			var pushing: bool = _operate_axis > 0.05 or _operate_kind == "door_push"
			var heave: float = sin(_clock * 5.2) * 0.012 if pushing else 0.0
			var tremor: float = sin(_clock * 28.0) * 0.0025 if pushing else 0.0
			var drive_z: float = -0.055 - maxf(0.0, _operate_axis) * 0.035 if pushing else 0.0
			var pos: Vector3 = Vector3(
				0.165 * side + tremor,
				-0.155 + breath * 0.5 + heave * 0.35,
				-0.415 + drive_z + heave
			)
			# Palms face forward (-Z) onto the door/cart; fingers point UP (+Y)
			var fwd: Vector3 = Vector3(-0.14 * side, 0.93, -0.33).normalized()
			var up: Vector3 = Vector3(0.10 * side, 0.33, 0.94).normalized()
			return _pose(pos, fwd, up, Vector3(0.64 * side, -0.44, 0.16), [-0.04, -0.02, 0.02, 0.06, 0.04], 0.11, 0.82)

		"climb":
			var ph: float = _climb_phase + (PI if side < 0.0 else 0.0)
			var cyc: float = wrapf(ph, 0.0, TAU) / TAU
			# 0.0..0.38: reach up & off rung; 0.38..0.50: snap onto rung; 0.50..1.0: pull body up (hand travels down)
			var y_off: float
			var z_off: float
			var grip_c: float
			if cyc < 0.38:
				var k: float = smoothstep(0.0, 0.38, cyc)
				y_off = lerpf(-0.33, -0.02, k)
				z_off = -0.36 - sin(k * PI) * 0.05
				grip_c = lerpf(0.28, 0.20, k)
			elif cyc < 0.52:
				var k2: float = smoothstep(0.38, 0.52, cyc)
				y_off = -0.02
				z_off = lerpf(-0.38, -0.46, k2)
				grip_c = lerpf(0.22, 0.92, k2)
			else:
				var k3: float = smoothstep(0.52, 1.0, cyc)
				y_off = lerpf(-0.02, -0.33, k3)
				z_off = -0.46 + k3 * 0.04
				grip_c = 0.94
			var pos: Vector3 = Vector3(0.150 * side, y_off, z_off)
			var fwd: Vector3 = Vector3(-0.08 * side, 0.36, -0.93).normalized()
			var up: Vector3 = Vector3(0.16 * side, 0.92, 0.36).normalized()
			return _pose(pos, fwd, up, Vector3(0.62 * side, -0.46, 0.10), [grip_c, grip_c + 0.02, grip_c + 0.04, grip_c + 0.05, grip_c * 0.84], 0.03, 0.50)

		"carry":
			var walk_sway: float = sin(_walk_phase) * 0.012 * clampf(_speed / 4.0, 0.0, 1.0)
			var walk_bob: float = absf(cos(_walk_phase)) * 0.008 * clampf(_speed / 4.0, 0.0, 1.0)
			if side > 0.0:
				# Right hand holds upper/outer side
				var pos_r: Vector3 = Vector3(0.195 + walk_sway, -0.185 - walk_bob + breath, -0.435)
				var fwd_r: Vector3 = Vector3(-0.42, 0.16, -0.89).normalized()
				var up_r: Vector3 = Vector3(0.76, 0.46, -0.45).normalized()
				return _pose(pos_r, fwd_r, up_r, pole, [0.58, 0.64, 0.70, 0.74, 0.56], 0.04, 0.62)
			else:
				# Left hand cradles from underneath (supinated palm facing up-right)
				var pos_l: Vector3 = Vector3(-0.135 + walk_sway, -0.245 - walk_bob + breath, -0.445)
				var fwd_l: Vector3 = Vector3(0.46, 0.24, -0.85).normalized()
				var up_l: Vector3 = Vector3(-0.56, -0.76, -0.32).normalized()
				return _pose(pos_l, fwd_l, up_l, Vector3(-0.58, -0.52, 0.12), [0.52, 0.58, 0.64, 0.68, 0.50], 0.05, 0.68)

		"rope":
			var tremor: float = sin(_clock * 26.0) * 0.003 * _pull_amount
			var y_base: float = -0.145 if side > 0.0 else -0.255
			var x_base: float = 0.065 if side > 0.0 else -0.045
			var pos: Vector3 = Vector3(
				x_base + tremor,
				y_base + _pull_amount * 0.02 + breath * 0.4,
				-0.44 + _pull_amount * 0.065
			)
			var fwd: Vector3 = Vector3(-0.34 * side, 0.22, -0.91).normalized()
			var up: Vector3 = Vector3(0.84 * side, 0.38, -0.38).normalized()
			return _pose(pos, fwd, up, Vector3(0.62 * side, -0.42, 0.10), [0.92, 0.95, 0.97, 0.98, 0.84], 0.01, 0.42)

		"console", "drive":
			var ax: float = clampf(_operate_axis, -1.0, 1.0)
			if side > 0.0:
				# Right hand works control lever / drum handle
				var pos_r: Vector3 = Vector3(0.145, -0.22 + breath * 0.4, -0.415 - ax * 0.065)
				var fwd_r: Vector3 = Vector3(-0.14, -0.36 - ax * 0.22, -0.92).normalized()
				var up_r: Vector3 = Vector3(0.18, 0.91, -0.36).normalized()
				return _pose(pos_r, fwd_r, up_r, pole, [0.78, 0.84, 0.88, 0.90, 0.72], 0.02, 0.48)
			else:
				# Left hand rests on console rim / brake handle
				var pos_l: Vector3 = Vector3(-0.155, -0.235 + breath * 0.4, -0.41 + ax * 0.015)
				var fwd_l: Vector3 = Vector3(0.14, -0.32, -0.94).normalized()
				var up_l: Vector3 = Vector3(-0.20, 0.92, -0.33).normalized()
				return _pose(pos_l, fwd_l, up_l, pole, [0.56, 0.62, 0.68, 0.72, 0.48], 0.03, 0.55)

		"reach":
			if side > 0.0:
				var pos_r: Vector3 = Vector3(0.09, -0.175 + breath * 0.4, -0.495)
				var fwd_r: Vector3 = Vector3(-0.18, -0.10, -0.98).normalized()
				var up_r: Vector3 = Vector3(0.28, 0.94, -0.18).normalized()
				return _pose(pos_r, fwd_r, up_r, pole, [0.16, 0.20, 0.26, 0.32, 0.18], 0.07, 0.68)
			else:
				var pos_l: Vector3 = Vector3(-0.22, -0.255 + breath, -0.33)
				var fwd_l: Vector3 = Vector3(0.22, -0.06, -0.97).normalized()
				var up_l: Vector3 = Vector3(0.52, 0.84, 0.14).normalized()
				return _pose(pos_l, fwd_l, up_l, pole, [0.24, 0.32, 0.40, 0.48, 0.22], 0.03, 0.55)

		"pin":
			if side > 0.0:
				var pos_r: Vector3 = Vector3(0.10, -0.19 + breath * 0.5, -0.46)
				var fwd_r: Vector3 = Vector3(-0.15, -0.18, -0.97).normalized()
				var up_r: Vector3 = Vector3(0.32, 0.92, -0.22).normalized()
				return _pose(pos_r, fwd_r, up_r, pole, [0.68, 0.84, 0.90, 0.94, 0.74], 0.01, 0.35)
			else:
				var pos_l: Vector3 = Vector3(-0.18, -0.23 + breath, -0.38)
				var fwd_l: Vector3 = Vector3(0.24, -0.12, -0.96).normalized()
				var up_l: Vector3 = Vector3(0.45, 0.88, 0.12).normalized()
				return _pose(pos_l, fwd_l, up_l, pole, [0.42, 0.50, 0.58, 0.64, 0.38], 0.03, 0.50)

		"data":
			if side > 0.0:
				var tap: float = maxf(0.0, sin(_clock * 5.2)) * 0.012
				var pos_r: Vector3 = Vector3(0.08, -0.19 - tap, -0.45 - tap * 1.4)
				var fwd_r: Vector3 = Vector3(-0.20, -0.32, -0.92).normalized()
				var up_r: Vector3 = Vector3(0.20, 0.93, -0.30).normalized()
				return _pose(pos_r, fwd_r, up_r, pole, [0.10, 0.82, 0.88, 0.92, 0.58], 0.02, 0.40)
			else:
				var pos_l: Vector3 = Vector3(-0.14, -0.22 + breath, -0.42)
				var fwd_l: Vector3 = Vector3(0.32, -0.10, -0.94).normalized()
				var up_l: Vector3 = Vector3(-0.48, -0.78, -0.38).normalized()
				return _pose(pos_l, fwd_l, up_l, pole, [0.44, 0.50, 0.56, 0.60, 0.42], 0.03, 0.58)

		_: # "idle"
			var pos: Vector3 = Vector3(
				0.215 * side,
				-0.250 + breath,
				-0.335
			)
			var fwd: Vector3 = Vector3(-0.20 * side, -0.05, -0.98).normalized()
			var up: Vector3 = Vector3((-0.55 + breath_roll) * side, 0.82, 0.14).normalized()
			return _pose(pos, fwd, up, pole, [0.24, 0.32, 0.40, 0.48, 0.22], 0.03, 0.55)


func _pose(pos: Vector3, fwd: Vector3, up: Vector3, pole: Vector3, curls: Array, splay: float, abduct: float) -> Dictionary:
	return {
		"pos": pos,
		"fwd": fwd,
		"up": up,
		"pole": pole,
		"curls": curls,
		"splay": splay,
		"abduct": abduct,
	}


func _apply_action_gesture(u: float, target_l: Dictionary, target_r: Dictionary) -> void:
	var amp: float = _action_intensity
	match _action_kind:
		"press":
			# Dominant right hand rises in an arc, extends index finger, presses & retracts
			var lift: float = sin(PI * clampf(u / 0.85, 0.0, 1.0))
			var poke: float = sin(PI * clampf((u - 0.18) / 0.58, 0.0, 1.0)) if u > 0.18 and u < 0.76 else 0.0
			var want_pos: Vector3 = Vector3(0.04, -0.135 + lift * 0.035, -0.44 - poke * 0.095 * amp)
			var cur_p: Vector3 = target_r["pos"] as Vector3
			target_r["pos"] = cur_p.lerp(want_pos, lift)
			target_r["fwd"] = (target_r["fwd"] as Vector3).lerp(Vector3(-0.10, -0.06, -0.99).normalized(), lift)
			target_r["up"] = (target_r["up"] as Vector3).lerp(Vector3(0.22, 0.96, -0.12).normalized(), lift)
			_blend_curls(target_r["curls"] as Array, [0.06, 0.84, 0.90, 0.94, 0.56], lift)

		"switch":
			# Thumb + index flick upward/forward
			var w: float = sin(PI * u)
			var flick: float = smoothstep(0.35, 0.65, u) * (1.0 - smoothstep(0.65, 1.0, u))
			target_r["pos"] = (target_r["pos"] as Vector3).lerp(Vector3(0.08, -0.16 + flick * 0.055, -0.48), w)
			target_r["fwd"] = (target_r["fwd"] as Vector3).lerp(Vector3(-0.14, 0.12 * flick - 0.12, -0.97).normalized(), w)
			target_r["up"] = (target_r["up"] as Vector3).lerp(Vector3(0.28, 0.94, -0.18).normalized(), w)
			_blend_curls(target_r["curls"] as Array, [0.58, 0.78, 0.86, 0.90, 0.65], w)

		"pull_pin", "latch":
			# Reach open -> hook/pinch -> yank sharply back toward chest -> settle
			if u < 0.36:
				var k: float = smoothstep(0.0, 0.36, u)
				target_r["pos"] = (target_r["pos"] as Vector3).lerp(Vector3(0.08, -0.17, -0.50), k)
				target_r["fwd"] = (target_r["fwd"] as Vector3).lerp(Vector3(-0.12, -0.14, -0.98).normalized(), k)
				target_r["up"] = (target_r["up"] as Vector3).lerp(Vector3(0.36, 0.91, -0.18).normalized(), k)
				_blend_curls(target_r["curls"] as Array, [0.35, 0.45, 0.52, 0.58, 0.35], k)
			elif u < 0.76:
				var k2: float = smoothstep(0.36, 0.68, u)
				var pull_pos: Vector3 = Vector3(0.14, -0.21, -0.50 + k2 * 0.18 * amp)
				target_r["pos"] = pull_pos
				target_r["fwd"] = Vector3(-0.22, -0.05 + k2 * 0.22, -0.95).normalized()
				target_r["up"] = Vector3(0.54, 0.82, 0.18).normalized()
				_blend_curls(target_r["curls"] as Array, [0.88, 0.92, 0.95, 0.96, 0.80], 0.95)
			else:
				var k3: float = smoothstep(0.76, 1.0, u)
				var end_pos: Vector3 = Vector3(0.14, -0.21, -0.32)
				target_r["pos"] = end_pos.lerp(target_r["pos"] as Vector3, k3)
				_blend_curls(target_r["curls"] as Array, [0.88, 0.92, 0.95, 0.96, 0.80], 1.0 - k3)

		"shove":
			# Two-hand anticipation pullback -> explosive forward thrust -> recoil settle
			var thrust: float
			if u < 0.20:
				thrust = -smoothstep(0.0, 0.20, u) * 0.35
			elif u < 0.52:
				thrust = lerpf(-0.35, 1.0, smoothstep(0.20, 0.48, u))
			else:
				thrust = 1.0 - smoothstep(0.52, 1.0, u)
			var w: float = sin(PI * clampf(u, 0.0, 1.0))
			for idx: int in range(2):
				var s: float = -1.0 if idx == 0 else 1.0
				var tgt: Dictionary = target_l if idx == 0 else target_r
				var shove_pos: Vector3 = Vector3(0.16 * s, -0.14 + maxf(0.0, thrust) * 0.03, -0.34 - thrust * 0.19 * amp)
				tgt["pos"] = (tgt["pos"] as Vector3).lerp(shove_pos, maxf(w, absf(thrust)))
				tgt["fwd"] = (tgt["fwd"] as Vector3).lerp(Vector3(-0.15 * s, 0.92, -0.36).normalized(), w)
				tgt["up"] = (tgt["up"] as Vector3).lerp(Vector3(0.12 * s, 0.36, 0.92).normalized(), w)
				tgt["splay"] = lerpf(float(tgt["splay"]), 0.13, w)
				_blend_curls(tgt["curls"] as Array, [-0.06, -0.04, 0.0, 0.04, 0.02], w)

		"clamp", "turn":
			# Reach -> grasp -> pronation/supination wrist torque twist -> release
			var w: float = sin(PI * u)
			var twist: float = sin(PI * clampf((u - 0.22) / 0.56, 0.0, 1.0)) * 0.85
			target_r["pos"] = (target_r["pos"] as Vector3).lerp(Vector3(0.10, -0.18, -0.47), w)
			target_r["fwd"] = Vector3(-0.14, -0.20, -0.97).normalized()
			target_r["up"] = Vector3(sin(twist), cos(twist), -0.15).normalized()
			var grip_w: float = smoothstep(0.15, 0.35, u) * (1.0 - smoothstep(0.75, 1.0, u))
			_blend_curls(target_r["curls"] as Array, [0.88, 0.92, 0.95, 0.96, 0.80], grip_w)

		"slam":
			# Raise hand slightly -> slam downward decisively onto lever/lock -> settle
			var slam_y: float = 0.07 * sin(PI * clampf(u / 0.35, 0.0, 1.0)) if u < 0.35 else -0.075 * sin(PI * clampf((u - 0.35) / 0.65, 0.0, 1.0))
			var w: float = sin(PI * u)
			target_r["pos"] = (target_r["pos"] as Vector3).lerp(Vector3(0.12, -0.18 + slam_y * amp, -0.46), w)
			target_r["fwd"] = (target_r["fwd"] as Vector3).lerp(Vector3(-0.10, -0.35 + slam_y * 2.0, -0.93).normalized(), w)
			target_r["up"] = (target_r["up"] as Vector3).lerp(Vector3(0.18, 0.92, -0.34).normalized(), w)
			_blend_curls(target_r["curls"] as Array, [0.92, 0.96, 0.98, 1.00, 0.84], w)

		"pickup":
			var w: float = sin(PI * u)
			var dip: float = sin(PI * clampf(u / 0.55, 0.0, 1.0)) * 0.06
			target_l["pos"] = (target_l["pos"] as Vector3) + Vector3(-0.04 * w, -dip, -0.06 * w)
			target_r["pos"] = (target_r["pos"] as Vector3) + Vector3(0.04 * w, -dip, -0.06 * w)
			if u < 0.45:
				_blend_curls(target_l["curls"] as Array, [0.15, 0.18, 0.22, 0.26, 0.16], w)
				_blend_curls(target_r["curls"] as Array, [0.15, 0.18, 0.22, 0.26, 0.16], w)

		"drop", "throw":
			var w: float = sin(PI * u)
			var fwd_amt: float = 0.14 * amp if _action_kind == "throw" else 0.05
			var drop_y: float = 0.02 if _action_kind == "throw" else -0.05
			target_l["pos"] = (target_l["pos"] as Vector3) + Vector3(-0.03 * w, drop_y * w, -fwd_amt * w)
			target_r["pos"] = (target_r["pos"] as Vector3) + Vector3(0.03 * w, drop_y * w, -fwd_amt * w)
			target_l["splay"] = lerpf(float(target_l["splay"]), 0.11, w)
			target_r["splay"] = lerpf(float(target_r["splay"]), 0.11, w)
			_blend_curls(target_l["curls"] as Array, [0.04, 0.06, 0.08, 0.12, 0.06], w)
			_blend_curls(target_r["curls"] as Array, [0.04, 0.06, 0.08, 0.12, 0.06], w)

		"rotate":
			# Crisp wrist pronation/supination twist when rotating carried item
			var w: float = sin(PI * u)
			target_r["pos"] = (target_r["pos"] as Vector3) + Vector3(-0.02 * w, 0.025 * w, -0.02 * w)
			var u_v: Vector3 = target_r["up"] as Vector3
			target_r["up"] = (u_v + Vector3(0.0, -0.65 * w, 0.45 * w)).normalized()
			_blend_curls(target_r["curls"] as Array, [0.78, 0.84, 0.88, 0.90, 0.74], w * 0.7)


func _blend_curls(dst: Array, src: Array, weight: float) -> void:
	for i: int in range(5):
		dst[i] = lerpf(float(dst[i]), float(src[i]), clampf(weight, 0.0, 1.0))
