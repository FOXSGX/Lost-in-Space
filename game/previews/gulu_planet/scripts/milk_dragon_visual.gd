extends Node3D
class_name MilkDragonVisual

## 奶龙占位外观。行为完全在 milk_dragon.gd，本脚本只负责模型与状态表现。
## 造型是程序化占位，不是最终奶龙模型；后续可直接替换为带骨骼的 GLB。

const CREAM := Color("#ffe3a0")
const ORANGE := Color("#ff9a54")
const BELLY := Color("#fff4d2")
const HORN := Color("#8fd3e8")
const CHEEK := Color("#ff9fb5")
const EYE_WHITE := Color("#f8fff9")
const PUPIL := Color("#1b2523")

var _state := "待机"
var _agitation := 0.0
var _windup := 0.0
var _pounce := 0.0
var _time := 0.0

var _body_root: Node3D
var _head: Node3D
var _left_wing: Node3D
var _right_wing: Node3D
var _ring: MeshInstance3D
var _body_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _eye_material: StandardMaterial3D
var _eye_alert := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	_body_root = Node3D.new()
	_body_root.name = "Body"
	add_child(_body_root)

	_body_material = _material(CREAM, 0.0)
	# 身体、脑袋、四肢共用一份材质，上头时统一变色。
	_sphere(_body_root, Vector3(0.0, 0.78, 0.0), Vector3(0.62, 0.60, 0.58), _body_material)
	_sphere(_body_root, Vector3(0.0, 0.58, -0.30), Vector3(0.42, 0.38, 0.20), _material(BELLY, 0.0))

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 1.40, -0.02)
	_body_root.add_child(_head)
	_sphere(_head, Vector3.ZERO, Vector3(0.64, 0.58, 0.58), _body_material)
	_sphere(_head, Vector3(0.0, -0.08, -0.50), Vector3(0.34, 0.24, 0.22), _material(BELLY, 0.0))
	_sphere(_head, Vector3(-0.20, 0.10, -0.54), Vector3(0.075, 0.075, 0.05), _material(PUPIL, 0.0))
	_sphere(_head, Vector3(0.20, 0.10, -0.54), Vector3(0.075, 0.075, 0.05), _material(PUPIL, 0.0))
	_sphere(_head, Vector3(-0.28, -0.07, -0.52), Vector3(0.10, 0.06, 0.05), _material(CHEEK, 0.0))
	_sphere(_head, Vector3(0.28, -0.07, -0.52), Vector3(0.10, 0.06, 0.05), _material(CHEEK, 0.0))

	# 眼睛：白色巩膜 + 发光虹膜，注意/蓄势时变亮。
	_eye_material = _material(EYE_WHITE, 0.0)
	_eye_material.emission_enabled = true
	_eye_material.emission = Color(0.45, 0.95, 0.9)
	_eye_material.emission_energy_multiplier = 0.0
	for side in [-1.0, 1.0]:
		_sphere(_head, Vector3(side * 0.20, 0.10, -0.56), Vector3(0.105, 0.11, 0.05), _eye_material)
		_sphere(_head, Vector3(side * 0.20, 0.10, -0.60), Vector3(0.045, 0.05, 0.03), _material(PUPIL, 0.0))
		# 小角
		var horn := CylinderMesh.new()
		horn.top_radius = 0.015
		horn.bottom_radius = 0.075
		horn.height = 0.28
		_add_mesh(_head, horn, Vector3(side * 0.30, 0.52, 0.02), Color(HORN.r, HORN.g, HORN.b, 1.0), Vector3.ONE, Vector3(0, 0, side * -0.32))
		# 耳朵/小翅
		var wing := SphereMesh.new()
		wing.radius = 0.20
		wing.height = 0.4
		var wing_node := _add_mesh(_body_root, wing, Vector3(side * 0.58, 1.02, 0.22), HORN, Vector3(0.55, 1.15, 0.26), Vector3(0, 0, side * 0.35))
		if side < 0.0:
			_left_wing = wing_node
		else:
			_right_wing = wing_node
		# 短手短脚
		_sphere(_body_root, Vector3(side * 0.52, 0.70, -0.10), Vector3(0.17, 0.30, 0.16), _body_material)
		_sphere(_body_root, Vector3(side * 0.24, 0.16, -0.10), Vector3(0.20, 0.16, 0.26), _body_material)

	# 尾巴
	var tail := CapsuleMesh.new()
	tail.radius = 0.13
	tail.height = 0.62
	_add_mesh(_body_root, tail, Vector3(0.0, 0.42, 0.52), CREAM, Vector3(1.0, 1.0, 1.0), Vector3(1.0, 0.0, 0.0))

	# 头顶呆毛
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.01
	tuft.bottom_radius = 0.06
	tuft.height = 0.30
	_add_mesh(_head, tuft, Vector3(0.0, 0.67, 0.05), CREAM, Vector3.ONE, Vector3(0.18, 0.0, 0.0))

	# 状态环：地面实体反馈，不是文字。
	_ring_material = _material(Color(0.5, 1.0, 0.85, 0.22), 0.0)
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
	_ring.rotation.x = PI * 0.5
	add_child(_ring)


func set_behavior(state_name: String, agitation: float, windup_ratio: float, pounce_ratio: float) -> void:
	_state = state_name
	_agitation = clampf(agitation, 0.0, 1.0)
	_windup = clampf(windup_ratio, 0.0, 1.0)
	_pounce = clampf(pounce_ratio, 0.0, 1.0)

	_body_material.albedo_color = CREAM.lerp(ORANGE, _agitation * 0.62)
	var alert := _agitation
	if state_name == "注意":
		alert = maxf(alert, 0.35)
	elif state_name == "蓄势" or state_name == "扑击":
		alert = 1.0
	_eye_alert = alert
	_eye_material.emission_energy_multiplier = 0.35 + alert * 2.2
	_eye_material.emission = Color(1.0, 0.35 + 0.55 * (1.0 - alert), 0.18)

	var squash := 0.0
	if state_name == "蓄势":
		squash = sin(_windup * PI) * 0.16
	elif state_name == "扑击":
		squash = -0.10
	elif state_name == "恢复":
		squash = 0.04
	_body_root.scale = Vector3(1.0 + squash, 1.0 - squash * 1.2, 1.0 + squash)
	_body_root.rotation.x = -0.07 if state_name == "靠近" else (-0.20 if state_name == "蓄势" else (-0.34 if state_name == "扑击" else 0.0))
	_body_root.rotation.z = 0.12 if state_name == "恢复" else 0.0
	_head.rotation.z = sin(_time * 1.6) * 0.03
	_head.rotation.x = -0.10 if state_name == "注意" else 0.0

	var ring_color := Color(0.5, 1.0, 0.85, 0.18)
	var ring_energy := 0.5
	if state_name == "注意":
		ring_color = Color(0.55, 1.0, 0.95, 0.55)
		ring_energy = 1.2
	elif state_name == "靠近":
		ring_color = Color(1.0, 0.78, 0.32, 0.55)
		ring_energy = 1.1
	elif state_name == "蓄势":
		ring_color = Color(1.0, 0.28, 0.18, 0.75)
		ring_energy = 2.4
	elif state_name == "扑击":
		ring_color = Color(1.0, 0.18, 0.12, 0.85)
		ring_energy = 2.8
	elif state_name == "恢复":
		ring_color = Color(0.55, 0.65, 0.65, 0.22)
	_ring_material.albedo_color = ring_color
	_ring_material.emission = Color(ring_color.r, ring_color.g, ring_color.b)
	_ring_material.emission_energy_multiplier = ring_energy
	var ring_scale := 1.0
	if state_name == "蓄势":
		ring_scale = 1.0 + sin(_time * 16.0) * 0.08
	elif state_name == "扑击":
		ring_scale = 1.2
	_ring.scale = Vector3.ONE * ring_scale


func _process(delta: float) -> void:
	_time += delta
	_body_root.position.y = sin(_time * 2.2) * 0.018
	if _left_wing != null and _right_wing != null:
		var flap := sin(_time * 2.0) * 0.06 + _agitation * 0.14
		_left_wing.rotation.z = -0.35 - flap
		_right_wing.rotation.z = 0.35 + flap
	# 蓄势时轻微抖动，强化“要扑了”的预警。
	if _state == "蓄势":
		_body_root.position.x = sin(_time * 46.0) * 0.018
	else:
		_body_root.position.x = 0.0


func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.80
	material.metallic = 0.02
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material


func _sphere(parent: Node3D, at: Vector3, scale: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	return _add_mesh(parent, mesh, at, Color.WHITE, scale, Vector3.ZERO, material)


func _add_mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, scale: Vector3 = Vector3.ONE, rotation: Vector3 = Vector3.ZERO, material: StandardMaterial3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.scale = scale
	instance.rotation = rotation
	if material == null:
		material = _material(color, 0.0)
	instance.material_override = material
	parent.add_child(instance)
	return instance
