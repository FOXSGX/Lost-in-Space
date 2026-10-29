extends Node3D
class_name MilkDragonVisual

## 奶龙外观与表演层。行为完全在 milk_dragon.gd，这里只负责模型、朝向与形变。
## 造型为程序化占位（不使用第三方奶龙模型）；材质偏哑光，避免塑料感。
## 关键表演：看见燃料转头盯着 / 被挑衅逐渐上头 / 蓄势压低 / 叼货一眼可见 /
## 扑空脸着地再抬头看人。

const CREAM := Color("#ffe6b8")
const CREAM_LIGHT := Color("#fff6dd")
const ORANGE := Color("#ff9a54")
const PINK := Color("#ffb3c4")
const MOUTH := Color("#7d2f3c")
const TONGUE := Color("#ef8fa3")
const EYE_WHITE := Color("#fffdf6")
const PUPIL := Color("#1b2523")
const HORN := Color("#f2d49b")

var _state := "待机"
var _agitation := 0.0
var _windup := 0.0
var _pounce := 0.0
var _time := 0.0
var _carrying := false
var _pounce_miss := false
var _look_target: Node3D
var _look_point := Vector3.ZERO
var _has_look_point := false
var _look_override := Vector3.ZERO
var _has_look_override := false
var _snatch := 0.0

var _body_root: Node3D
var _torso: Node3D
var _head: Node3D
var _jaw: Node3D
var _mouth_cavity: MeshInstance3D
var _left_arm: Node3D
var _right_arm: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _tail: Node3D
var _tail_tip: Node3D
var _left_wing: Node3D
var _right_wing: Node3D
var _left_brow: Node3D
var _right_brow: Node3D
var _ring: MeshInstance3D
var _mouth_anchor: Node3D
var _body_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _eye_material: StandardMaterial3D
var _pupil_material: StandardMaterial3D

var _head_yaw := 0.0
var _head_pitch := 0.0
var _crouch := 0.0
var _lean := 0.0
var _mouth_open := 0.0
var _faceplant := 0.0
var _hop := 0.0
var _recover_clock := 0.0
var ring_enabled := false


func _ready() -> void:
	_build()
	set_process(true)


func mouth_anchor() -> Node3D:
	return _mouth_anchor


func set_look_target(node: Node3D) -> void:
	_look_target = node


## 行为层直接指定视线落点（例如“盯着你手上那罐燃料”）。
func set_look_point(point: Vector3, valid: bool) -> void:
	_look_override = point
	_has_look_override = valid


## 抢货预警：0。。1，靠近时伸长脖子、张嘴。
func set_snatch(progress: float) -> void:
	_snatch = clampf(progress, 0.0, 1.0)


func set_carried_state(carrying: bool) -> void:
	_carrying = carrying


func set_behavior(state_name: String, agitation: float, windup_ratio: float, pounce_ratio: float) -> void:
	if state_name == "恢复" and _state != "恢复":
		_recover_clock = 0.0
		_faceplant = 1.0 if _pounce_miss else 0.45
	_state = state_name
	_agitation = clampf(agitation, 0.0, 1.0)
	_windup = clampf(windup_ratio, 0.0, 1.0)
	_pounce = clampf(pounce_ratio, 0.0, 1.0)


func set_pounce_result(hit: bool) -> void:
	_pounce_miss = not hit


# ------------------------------------------------------------------ 模型

func _build() -> void:
	_body_root = Node3D.new()
	_body_root.name = "Body"
	add_child(_body_root)

	_body_material = _material(CREAM)
	_torso = Node3D.new()
	_torso.name = "Torso"
	_body_root.add_child(_torso)

	_sphere(_torso, Vector3(0.0, 0.86, 0.02), Vector3(0.88, 0.82, 0.80), _body_material)
	_sphere(_torso, Vector3(0.0, 0.70, -0.34), Vector3(0.58, 0.54, 0.24), _material(CREAM_LIGHT))
	# 背脊小刺，增加剪影辨识度
	for index in range(3):
		var spike := SphereMesh.new()
		spike.radius = 0.5
		spike.height = 1.0
		_sphere(_torso, Vector3(0.0, 1.02 + float(index) * 0.10, 0.30 - float(index) * 0.16), Vector3(0.10, 0.16, 0.10), _material(ORANGE))

	# 头
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 1.42, -0.04)
	_body_root.add_child(_head)
	_sphere(_head, Vector3(0.0, 0.10, 0.0), Vector3(0.80, 0.72, 0.72), _body_material)
	_sphere(_head, Vector3(0.0, 0.00, -0.40), Vector3(0.48, 0.34, 0.36), _material(CREAM_LIGHT))
	# 嘴腔（张开时可见）
	_mouth_cavity = _sphere(_head, Vector3(0.0, -0.08, -0.52), Vector3(0.30, 0.16, 0.22), _material(MOUTH))
	_mouth_cavity.scale = Vector3(0.0, 0.0, 0.0)
	_sphere(_head, Vector3(0.0, -0.10, -0.58), Vector3(0.20, 0.07, 0.14), _material(TONGUE))

	# 下颌：绕后侧铰点张合
	_jaw = Node3D.new()
	_jaw.name = "Jaw"
	_jaw.position = Vector3(0.0, -0.12, -0.18)
	_head.add_child(_jaw)
	_sphere(_jaw, Vector3(0.0, -0.06, -0.26), Vector3(0.42, 0.16, 0.34), _material(CREAM_LIGHT))

	# 眼睛
	_eye_material = _material(EYE_WHITE)
	_eye_material.emission_enabled = true
	_eye_material.emission = Color(0.9, 0.98, 0.95)
	_eye_material.emission_energy_multiplier = 0.0
	_pupil_material = _material(PUPIL)
	for side in [-1.0, 1.0]:
		_sphere(_head, Vector3(side * 0.245, 0.17, -0.335), Vector3(0.22, 0.23, 0.12), _eye_material)
		_sphere(_head, Vector3(side * 0.245, 0.17, -0.395), Vector3(0.105, 0.115, 0.07), _pupil_material)
		_sphere(_head, Vector3(side * 0.21, 0.215, -0.435), Vector3(0.038, 0.038, 0.02), _material(Color("#ffffff")))
		# 腮红
		_sphere(_head, Vector3(side * 0.36, 0.02, -0.32), Vector3(0.17, 0.11, 0.07), _material(PINK))
		# 耳朵
		var ear_node := _sphere(_head, Vector3(side * 0.34, 0.38, 0.06), Vector3(0.20, 0.34, 0.16), _material(HORN))
		ear_node.rotation.z = side * 0.34
		# 眉毛：上头时压下来
		var brow := _sphere(_head, Vector3(side * 0.245, 0.315, -0.355), Vector3(0.26, 0.055, 0.06), _material(Color("#d9a55f")))
		if side < 0.0:
			_left_brow = brow
		else:
			_right_brow = brow
		# 短手
		var arm_pivot := Node3D.new()
		arm_pivot.name = "LeftArm" if side < 0.0 else "RightArm"
		arm_pivot.position = Vector3(side * 0.44, 1.02, -0.06)
		_torso.add_child(arm_pivot)
		_sphere(arm_pivot, Vector3(0.0, -0.16, 0.0), Vector3(0.20, 0.34, 0.20), _body_material)
		_sphere(arm_pivot, Vector3(0.0, -0.32, -0.02), Vector3(0.19, 0.16, 0.19), _material(CREAM_LIGHT))
		if side < 0.0:
			_left_arm = arm_pivot
		else:
			_right_arm = arm_pivot
		# 短腿
		var leg_pivot := Node3D.new()
		leg_pivot.name = "LeftLeg" if side < 0.0 else "RightLeg"
		leg_pivot.position = Vector3(side * 0.28, 0.44, 0.02)
		_torso.add_child(leg_pivot)
		_sphere(leg_pivot, Vector3(0.0, -0.22, 0.0), Vector3(0.26, 0.40, 0.28), _body_material)
		_sphere(leg_pivot, Vector3(0.0, -0.40, -0.08), Vector3(0.30, 0.16, 0.36), _material(CREAM_LIGHT))
		if side < 0.0:
			_left_leg = leg_pivot
		else:
			_right_leg = leg_pivot
		# 小翅
		var wing := _sphere(_torso, Vector3(side * 0.52, 1.20, 0.22), Vector3(0.16, 0.42, 0.30), _material(Color("#ffd9a0")))
		wing.rotation.z = side * 0.42
		if side < 0.0:
			_left_wing = wing
		else:
			_right_wing = wing

	# 尾巴：两段，甩起来有重量
	_tail = Node3D.new()
	_tail.name = "Tail"
	_tail.position = Vector3(0.0, 0.62, 0.36)
	_torso.add_child(_tail)
	_sphere(_tail, Vector3(0.0, -0.02, 0.20), Vector3(0.30, 0.30, 0.34), _body_material)
	_tail_tip = Node3D.new()
	_tail_tip.position = Vector3(0.0, 0.06, 0.36)
	_tail.add_child(_tail_tip)
	_sphere(_tail_tip, Vector3(0.0, 0.02, 0.16), Vector3(0.20, 0.20, 0.28), _body_material)
	_sphere(_tail_tip, Vector3(0.0, 0.06, 0.32), Vector3(0.12, 0.12, 0.18), _material(ORANGE))

	# 头顶呆毛
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.01
	tuft.bottom_radius = 0.055
	tuft.height = 0.30
	var tuft_node := MeshInstance3D.new()
	tuft_node.mesh = tuft
	tuft_node.position = Vector3(0.0, 0.62, 0.02)
	tuft_node.rotation.x = 0.22
	tuft_node.material_override = _material(CREAM)
	_head.add_child(tuft_node)

	# 嘴部挂点：燃料叼在这里
	_mouth_anchor = Node3D.new()
	_mouth_anchor.name = "MouthAnchor"
	_mouth_anchor.position = Vector3(0.0, -0.10, -0.56)
	_head.add_child(_mouth_anchor)

	# 状态环（仅调试模式显示）
	_ring_material = _material(Color(0.5, 1.0, 0.85, 0.22))
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.emission_enabled = true
	_ring_material.emission = Color(0.5, 1.0, 0.85)
	_ring_material.emission_energy_multiplier = 0.7
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 0.80
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _ring_material
	_ring.position = Vector3(0.0, 0.035, 0.0)
	_ring.visible = false
	add_child(_ring)


# ------------------------------------------------------------------ 表演

func _process(delta: float) -> void:
	_time += delta
	_recover_clock += delta
	_animate_targets(delta)
	_apply_pose(delta)


func _animate_targets(delta: float) -> void:
	var looking_at_player := _state in ["注意", "靠近", "蓄势", "扑击", "恢复"]
	# 头部朝向：有目标就盯住，否则缓慢左右扫视
	if _has_look_override:
		_look_point = _look_override
		_has_look_point = true
	elif _look_target != null and is_instance_valid(_look_target):
		_look_point = _look_target.global_position + Vector3.UP * 1.1
		_has_look_point = true
	if looking_at_player and _has_look_point:
		var local := _head.to_local(_look_point) - _head.position
		var yaw := clampf(atan2(-local.x, -local.z), -0.95, 0.95)
		var pitch := clampf(atan2(local.y, Vector2(local.x, local.z).length()), -0.45, 0.55)
		_head_yaw = lerpf(_head_yaw, yaw, 1.0 - exp(-9.0 * delta))
		_head_pitch = lerpf(_head_pitch, pitch, 1.0 - exp(-8.0 * delta))
	else:
		_head_yaw = lerpf(_head_yaw, sin(_time * 0.7) * 0.22, 1.0 - exp(-3.0 * delta))
		_head_pitch = lerpf(_head_pitch, 0.0, 1.0 - exp(-4.0 * delta))

	var target_crouch := 0.0
	var target_lean := 0.0
	var target_open := 0.0
	var target_hop := 0.0
	match _state:
		"注意":
			target_crouch = -0.045
			target_open = 0.25
		"靠近":
			target_crouch = -0.055
			target_lean = -0.12
			target_open = 0.35
		"蓄势":
			target_crouch = -0.16 - 0.05 * sin(_windup * PI)
			target_lean = -0.26
			target_open = 0.30
		"扑击":
			target_crouch = 0.05
			target_lean = -0.55
			target_open = 1.0
			target_hop = 0.22 * sin(clampf(_pounce, 0.0, 1.0) * PI)
		"恢复":
			if _pounce_miss:
				target_crouch = -0.26 * maxf(0.0, 1.0 - _recover_clock * 1.6)
				target_lean = -0.62 * maxf(0.0, 1.0 - _recover_clock * 1.5)
				target_open = 0.7 * maxf(0.0, 1.0 - _recover_clock * 1.4)
			else:
				target_crouch = -0.10
				target_lean = -0.10
		"找燃料":
			target_crouch = -0.06
			target_lean = -0.14
			target_open = 0.55
	if _carrying:
		target_open = maxf(target_open, 0.62)
		target_crouch -= 0.03

	_crouch = lerpf(_crouch, target_crouch, 1.0 - exp(-11.0 * delta))
	_lean = lerpf(_lean, target_lean, 1.0 - exp(-12.0 * delta))
	_mouth_open = lerpf(_mouth_open, target_open, 1.0 - exp(-14.0 * delta))
	_hop = lerpf(_hop, target_hop, 1.0 - exp(-18.0 * delta))


func _apply_pose(delta: float) -> void:
	# 身体：呼吸 + 上头变色 + 蓄势抖动
	_body_material.albedo_color = CREAM.lerp(ORANGE, _agitation * 0.55)
	_body_root.position.y = _crouch + _hop + sin(_time * 2.1) * 0.014
	_body_root.position.x = sin(_time * 46.0) * 0.02 * _windup if _state == "蓄势" else 0.0
	_body_root.rotation.x = _lean
	_body_root.rotation.z = 0.0
	var squash := 1.0
	if _state == "蓄势":
		squash = 0.94 + 0.02 * sin(_time * 18.0)
	elif _state == "扑击":
		squash = 1.04
	_body_root.scale = Vector3(1.0 / maxf(squash, 0.6), squash, 1.0 / maxf(squash, 0.6))

	_head.rotation.y = _head_yaw
	_head.rotation.x = _head_pitch + 0.22 * _snatch
	_head.rotation.z = sin(_time * 1.5) * 0.02
	# 叼货时轻微咀嚼/点头
	if _carrying:
		_head.rotation.x += sin(_time * 5.2) * 0.03
		_head.rotation.z += sin(_time * 2.6) * 0.03

	_jaw.rotation.x = 0.62 * _mouth_open + 0.35 * _snatch
	_mouth_cavity.scale = Vector3(0.30, 0.16, 0.22) * clampf(_mouth_open * 1.4, 0.0, 1.0)

	var alert := maxf(_agitation, 0.25 if _state in ["注意", "靠近"] else 0.0)
	if _state in ["蓄势", "扑击"]:
		alert = 1.0
	_eye_material.emission_energy_multiplier = 0.15 + alert * 1.4
	_eye_material.emission = Color(1.0, 0.92 - 0.5 * alert, 0.86 - 0.6 * alert)
	_pupil_material.albedo_color = PUPIL.lerp(Color("#7d1f1f"), alert * 0.5)

	# 眉毛：越上头越压
	var brow_angle := 0.10 + _agitation * 0.42
	if _left_brow != null:
		_left_brow.rotation.z = -brow_angle
	if _right_brow != null:
		_right_brow.rotation.z = brow_angle

	# 手脚：走路/蓄势/扑击/手舞足蹈
	var flail := 0.0
	if _state == "蓄势":
		flail = sin(_time * 20.0) * 0.22
	elif _state == "扑击":
		flail = -1.15
	elif _state == "找燃料" or _state == "靠近":
		flail = sin(_time * 6.0) * 0.22
	if _left_arm != null:
		_left_arm.rotation.x = flail
		_left_arm.rotation.z = -0.18 - _agitation * 0.25
	if _right_arm != null:
		_right_arm.rotation.x = flail
		_right_arm.rotation.z = 0.18 + _agitation * 0.25
	var step := sin(_time * 7.0) * 0.22 if _state in ["靠近", "找燃料", "回窝"] else 0.0
	if _left_leg != null:
		_left_leg.rotation.x = step
	if _right_leg != null:
		_right_leg.rotation.x = -step

	if _left_wing != null and _right_wing != null:
		var flap := sin(_time * 2.2) * 0.05 + _agitation * 0.16 + (0.25 if _state == "扑击" else 0.0)
		_left_wing.rotation.z = -0.42 - flap
		_right_wing.rotation.z = 0.42 + flap

	if _tail != null:
		_tail.rotation.y = sin(_time * 1.9) * 0.24 + _agitation * 0.2
		_tail.rotation.x = -0.25 + sin(_time * 1.3) * 0.06
	if _tail_tip != null:
		_tail_tip.rotation.y = sin(_time * 1.9 + 0.9) * 0.34

	# 状态环只在调试模式出现
	if _ring != null:
		_ring.visible = ring_enabled
		if ring_enabled:
			var ring_color := Color(0.5, 1.0, 0.85, 0.18)
			if _state == "蓄势":
				ring_color = Color(1.0, 0.28, 0.18, 0.7)
			elif _state == "扑击":
				ring_color = Color(1.0, 0.18, 0.12, 0.85)
			elif _state == "靠近":
				ring_color = Color(1.0, 0.78, 0.32, 0.5)
			_ring_material.albedo_color = ring_color
			_ring_material.emission = Color(ring_color.r, ring_color.g, ring_color.b)
			_ring_material.emission_energy_multiplier = 1.0 + _agitation * 1.6


# ------------------------------------------------------------------ 工具

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.96
	material.metallic = 0.0
	material.metallic_specular = 0.25
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _sphere(parent: Node3D, at: Vector3, scale: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.scale = scale
	instance.material_override = material
	parent.add_child(instance)
	return instance
