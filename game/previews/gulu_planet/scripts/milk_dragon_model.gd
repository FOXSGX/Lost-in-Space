extends Node3D
class_name MilkDragonModelVisual

## 奶龙外观（正式模型版）：assets/characters/nailong_dl.glb。
##
## 来源：Sketchfab "nailong" by RED ANGRY BIRDS，CC-BY-4.0（见 assets/characters/nailong_dl_LICENSE.txt）。
## 模型在 Blender 里已经把手放下来并烘成 rest pose；这里是**外观与表演层**，
## 行为状态机、碰撞、参数全在 milk_dragon.gd，一行都没改。
##
## 模型自身：高 1.83 m、脚底 y=-0.072、脸朝 +Z。所以：
##   - 底下垫 0.072 让它踩地；
##   - 外面套一层绕 Y 转 180° 的节点，让脸朝 -Z（与占位外观一致）。
##
## 没有下颌骨（Tripo 模型只给了 Rigify 人形骨架），所以"张嘴"用
## 头部下压 + 整体挤压代替；叼货时罐子挂在嘴前，一眼能看见。

const MODEL_PATH := "res://assets/characters/nailong_dl.glb"
const GROUND_OFFSET := 0.072
const MOUTH_OFFSET := Vector3(0.0, 1.31, 0.60)

const WARM := Color("#ff9a54")

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

var _body: Node3D
var _facing: Node3D
var _model: Node3D
var _skeleton: Skeleton3D
var _head_bone := -1
var _neck_bone := -1
var _arm_bones: Array[int] = []
var _rest := {}

var _head_yaw := 0.0
var _head_pitch := 0.0
var _crouch := 0.0
var _lean := 0.0
var _mouth_open := 0.0
var _faceplant := 0.0
var _hop := 0.0
var _recover_clock := 0.0

var _mouth_anchor: Node3D
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _tint_materials: Array[StandardMaterial3D] = []
var _tint_base: Array[Color] = []
var ring_enabled := false


func _ready() -> void:
	_build()
	set_process(true)


# ------------------------------------------------------------------ 对外接口（与 milk_dragon_visual.gd 一致）

func mouth_anchor() -> Node3D:
	return _mouth_anchor


func set_look_target(node: Node3D) -> void:
	_look_target = node


func set_look_point(point: Vector3, valid: bool) -> void:
	_look_override = point
	_has_look_override = valid


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


# ------------------------------------------------------------------ 组装

func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	_facing = Node3D.new()
	_facing.name = "Facing"
	_facing.rotation.y = PI          # 模型脸朝 +Z，转过来朝 -Z
	_body.add_child(_facing)

	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("奶龙模型未导入：%s" % MODEL_PATH)
		_model = Node3D.new()
		_facing.add_child(_model)
	else:
		_model = packed.instantiate() as Node3D
		_model.position.y = GROUND_OFFSET
		_facing.add_child(_model)

	var meshes := _model.find_children("*", "MeshInstance3D", true, false)
	for node in meshes:
		var mi := node as MeshInstance3D
		mi.visible = true
		for surface in range(mi.mesh.get_surface_count()):
			var material := mi.get_active_material(surface)
			if material is StandardMaterial3D:
				var tint := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
				mi.set_surface_override_material(surface, tint)
				_tint_materials.append(tint)
				_tint_base.append(tint.albedo_color)

	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() > 0:
		_skeleton = skeletons[0] as Skeleton3D
		_cache_bones()

	# 嘴部挂点：模型空间里正对着脸的那一点
	_mouth_anchor = Node3D.new()
	_mouth_anchor.name = "MouthAnchor"
	_mouth_anchor.position = MOUTH_OFFSET
	_model.add_child(_mouth_anchor)

	# 状态环（仅调试模式）
	_ring_material = StandardMaterial3D.new()
	_ring_material.albedo_color = Color(0.5, 1.0, 0.85, 0.22)
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


func _cache_bones() -> void:
	for index in range(_skeleton.get_bone_count()):
		var name := _skeleton.get_bone_name(index)
		if name.begins_with("DEF-spine.006"):
			_head_bone = index
		elif name.begins_with("DEF-spine.005"):
			_neck_bone = index
		elif name.begins_with("DEF-upper_arm") and not name.contains(".001"):
			_arm_bones.append(index)
		_rest[index] = _skeleton.get_bone_pose_rotation(index)


# ------------------------------------------------------------------ 表演

func _process(delta: float) -> void:
	_time += delta
	_recover_clock += delta
	_animate_targets(delta)
	_apply_pose()


func _animate_targets(delta: float) -> void:
	var looking := _state in ["注意", "靠近", "蓄势", "扑击", "恢复"]
	if _has_look_override:
		_look_point = _look_override
		_has_look_point = true
	elif _look_target != null and is_instance_valid(_look_target):
		_look_point = _look_target.global_position + Vector3.UP * 1.1
		_has_look_point = true

	if looking and _has_look_point:
		var local := to_local(_look_point) - _facing.position
		var yaw := clampf(atan2(-local.x, -local.z), -0.85, 0.85)
		var pitch := clampf(atan2(local.y - 1.31, Vector2(local.x, local.z).length()), -0.40, 0.50)
		_head_yaw = lerpf(_head_yaw, yaw, 1.0 - exp(-9.0 * delta))
		_head_pitch = lerpf(_head_pitch, pitch, 1.0 - exp(-8.0 * delta))
	else:
		_head_yaw = lerpf(_head_yaw, sin(_time * 0.7) * 0.20, 1.0 - exp(-3.0 * delta))
		_head_pitch = lerpf(_head_pitch, 0.0, 1.0 - exp(-4.0 * delta))

	var target_crouch := 0.0
	var target_lean := 0.0
	var target_open := 0.0
	var target_hop := 0.0
	match _state:
		"注意":
			target_crouch = -0.04
			target_open = 0.25
		"靠近":
			target_crouch = -0.05
			target_lean = -0.12
			target_open = 0.35
		"蓄势":
			target_crouch = -0.15 - 0.05 * sin(_windup * PI)
			target_lean = -0.26
			target_open = 0.30
		"扑击":
			target_crouch = 0.05
			target_lean = -0.50
			target_open = 1.0
			target_hop = 0.20 * sin(clampf(_pounce, 0.0, 1.0) * PI)
		"恢复":
			if _pounce_miss:
				target_crouch = -0.24 * maxf(0.0, 1.0 - _recover_clock * 1.6)
				target_lean = -0.55 * maxf(0.0, 1.0 - _recover_clock * 1.5)
				target_open = 0.6 * maxf(0.0, 1.0 - _recover_clock * 1.4)
			else:
				target_crouch = -0.09
				target_lean = -0.10
		"找燃料":
			target_crouch = -0.06
			target_lean = -0.14
			target_open = 0.55
	if _carrying:
		target_open = maxf(target_open, 0.7)
		target_crouch -= 0.03

	_crouch = lerpf(_crouch, target_crouch, 1.0 - exp(-11.0 * delta))
	_lean = lerpf(_lean, target_lean, 1.0 - exp(-12.0 * delta))
	_mouth_open = lerpf(_mouth_open, target_open, 1.0 - exp(-14.0 * delta))
	_hop = lerpf(_hop, target_hop, 1.0 - exp(-18.0 * delta))


func _apply_pose() -> void:
	# 整体：呼吸 / 蹲伏 / 前倾 / 蓄势抖动 / 闪避前的挤压
	_body.position.y = _crouch + _hop + sin(_time * 2.1) * 0.012
	_body.position.x = sin(_time * 46.0) * 0.018 * _windup if _state == "蓄势" else 0.0
	_body.rotation.x = _lean
	_body.rotation.z = 0.0
	var squash := 1.0
	if _state == "蓄势":
		squash = 0.95 + 0.02 * sin(_time * 18.0)
	elif _state == "扑击":
		squash = 1.03
	_body.scale = Vector3(1.0 / maxf(squash, 0.6), squash, 1.0 / maxf(squash, 0.6))

	# 骨骼：抬头/低头、叼货点头、手臂小动作
	if _skeleton != null and _head_bone >= 0:
		var open_dip := 0.22 * _mouth_open + 0.30 * _snatch
		var yaw := _head_yaw
		var pitch := _head_pitch + open_dip
		if _carrying:
			pitch += sin(_time * 5.2) * 0.03
		_skeleton.set_bone_pose_rotation(_head_bone, Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch))
		if _neck_bone >= 0:
			_skeleton.set_bone_pose_rotation(_neck_bone, Quaternion(Vector3.UP, yaw * 0.35))
		var flail := 0.0
		if _state == "蓄势":
			flail = sin(_time * 20.0) * 0.18
		elif _state == "扑击":
			flail = -0.55
		elif _state == "找燃料" or _state == "靠近":
			flail = sin(_time * 6.0) * 0.16
		for index in range(_arm_bones.size()):
			var side := 1.0 if index == 0 else -1.0
			_skeleton.set_bone_pose_rotation(_arm_bones[index],
				Quaternion(Vector3.RIGHT, flail) * Quaternion(Vector3.UP, side * 0.10 * _agitation))

	# 上头：贴图不变，用暖色叠加
	var tint := 1.0 - _agitation * 0.18
	for index in range(_tint_materials.size()):
		var base := _tint_base[index]
		_tint_materials[index].albedo_color = Color(base.r, base.g * tint, base.b * (1.0 - _agitation * 0.35), base.a)

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
