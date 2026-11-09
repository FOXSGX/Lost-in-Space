extends Node3D
class_name MilkDragonModelVisual

## 奶龙外观（正式模型版）：assets/characters/nailong_dl.glb。
##
## 来源：Sketchfab "nailong" by RED ANGRY BIRDS，CC-BY-4.0
## （见 assets/characters/nailong_dl_LICENSE.txt）。
##
## 本文件只负责“看起来对”：接地、迈步、转身、拦球动作。
## 行为（守门/拦球）全在 milk_dragon.gd，两边通过
## set_look_point / set_locomotion / set_block 三个接口沟通。
##
## 模型自身：高 1.83 m、脚底 y=-0.072、脸朝 +Z。所以：
##   - 底下垫 0.072 让它踩地；
##   - 外面套一层绕 Y 转 180° 的节点，让脸朝 -Z（与游戏朝向一致）。

const MODEL_PATH := "res://assets/characters/nailong_dl.glb"
const GROUND_OFFSET := 0.072

const WARM := Color("#ff9a54")

var _look_point := Vector3.ZERO
var _has_look_point := false
var _speed01 := 0.0
var _lateral01 := 0.0
var _block := 0.0
var _time := 0.0
var _gait := 0.0

var _body: Node3D
var _facing: Node3D
var _model: Node3D
var _skeleton: Skeleton3D
var _head_bone := -1
var _neck_bone := -1
var _thigh_bones: Array[int] = []
var _shin_bones: Array[int] = []
var _foot_bones: Array[int] = []
var _arm_bones: Array[int] = []
var _rest := {}

var _head_yaw := 0.0
var _head_pitch := 0.0
var _lean := 0.0

var _mouth_anchor: Node3D
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _tint_materials: Array[StandardMaterial3D] = []
var _tint_base: Array[Color] = []
var ring_enabled := false


func _ready() -> void:
	_build()
	set_process(true)


# ------------------------------------------------------------------ 对外接口

func mouth_anchor() -> Node3D:
	return _mouth_anchor


func set_look_point(point: Vector3, valid: bool) -> void:
	_look_point = point
	_has_look_point = valid


func set_look_target(node: Node3D) -> void:
	if node != null and is_instance_valid(node):
		set_look_point(node.global_position + Vector3.UP * 0.35, true)


## speed01: 0..1 的移动速度；lateral01: 左右横移比例（-1..1，用来做轻微侧倾）
func set_locomotion(speed01: float, lateral01: float) -> void:
	_speed01 = clampf(speed01, 0.0, 1.0)
	_lateral01 = clampf(lateral01, -1.0, 1.0)


## 拦球动作权重 0..1（0 = 不做动作）
func set_block(weight: float) -> void:
	_block = clampf(weight, 0.0, 1.0)


# ------------------------------------------------------------------ 组装

func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	_facing = Node3D.new()
	_facing.name = "Facing"
	_facing.rotation.y = PI
	_body.add_child(_facing)

	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_warning("奶龙模型未导入，使用简单占位：%s" % MODEL_PATH)
		_model = _build_fallback()
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

	_mouth_anchor = Node3D.new()
	_mouth_anchor.name = "MouthAnchor"
	_mouth_anchor.position = Vector3(0.0, 1.31, 0.60)
	_model.add_child(_mouth_anchor)

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


## 模型缺失时的最小占位：还是保持“站得住、看得出朝向”。
func _build_fallback() -> Node3D:
	var root := Node3D.new()
	var cream := StandardMaterial3D.new()
	cream.albedo_color = Color("#f6e3b4")
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.55
	capsule.height = 1.5
	body.mesh = capsule
	body.position.y = 0.75
	body.material_override = cream
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.46
	sphere.height = 0.92
	head.mesh = sphere
	head.position = Vector3(0.0, 1.42, 0.28)
	head.material_override = cream
	root.add_child(head)
	return root


func _cache_bones() -> void:
	for index in range(_skeleton.get_bone_count()):
		var bone_name := _skeleton.get_bone_name(index)
		if bone_name.begins_with("DEF-spine.006"):
			_head_bone = index
		elif bone_name.begins_with("DEF-spine.005"):
			_neck_bone = index
		elif bone_name.begins_with("DEF-thigh.") and not bone_name.contains(".001"):
			_thigh_bones.append(index)
		elif bone_name.begins_with("DEF-shin.") and not bone_name.contains(".001"):
			_shin_bones.append(index)
		elif bone_name.begins_with("DEF-foot."):
			_foot_bones.append(index)
		elif bone_name.begins_with("DEF-upper_arm") and not bone_name.contains(".001"):
			_arm_bones.append(index)
		_rest[index] = _skeleton.get_bone_pose_rotation(index)


# ------------------------------------------------------------------ 表演

func _process(delta: float) -> void:
	_time += delta
	_animate(delta)
	_apply_pose()


func _animate(delta: float) -> void:
	# 头：盯着球（拦球时也看得见它在看哪儿）
	if _has_look_point:
		var local := to_local(_look_point) - _facing.position
		var yaw := clampf(atan2(-local.x, -local.z), -0.9, 0.9)
		var pitch := clampf(atan2(local.y - 1.31, Vector2(local.x, local.z).length()), -0.35, 0.45)
		_head_yaw = lerpf(_head_yaw, yaw, 1.0 - exp(-8.0 * delta))
		_head_pitch = lerpf(_head_pitch, pitch, 1.0 - exp(-7.0 * delta))
	else:
		_head_yaw = lerpf(_head_yaw, sin(_time * 0.6) * 0.12, 1.0 - exp(-3.0 * delta))
		_head_pitch = lerpf(_head_pitch, 0.0, 1.0 - exp(-4.0 * delta))

	# 前倾：移动越快越前倾，拦球时再压一点（不用整体挤压，保留模型轮廓）
	var target_lean := -0.10 * _speed01 - 0.16 * _block
	_lean = lerpf(_lean, target_lean, 1.0 - exp(-9.0 * delta))

	# 步频与速度绑定：速度翻倍，步频也差不多翻倍
	_gait += delta * (3.0 + 5.0 * _speed01)


func _apply_pose() -> void:
	# 只做小幅起伏，脚始终踩地（模型已垫 0.072）
	var bob := absf(sin(_gait)) * 0.010 * _speed01
	_body.position.y = bob
	_body.position.x = 0.0
	_body.rotation.x = _lean
	# 侧移时轻微侧倾，幅度很小，避免“身体扭成麻花”
	_body.rotation.z = lerpf(_body.rotation.z, -0.035 * _lateral01 * _speed01, 0.15)
	_body.scale = Vector3.ONE

	if _skeleton == null:
		return

	# 头/脖子
	if _head_bone >= 0:
		var yaw := _head_yaw
		var pitch := _head_pitch - 0.10 * _block
		_skeleton.set_bone_pose_rotation(_head_bone,
			_rest[_head_bone] * Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch))
		if _neck_bone >= 0:
			_skeleton.set_bone_pose_rotation(_neck_bone,
				_rest[_neck_bone] * Quaternion(Vector3.UP, yaw * 0.35))

	# 迈步：大腿前后摆 + 膝盖弯曲 + 脚掌回正
	var swing := sin(_gait) * (0.34 * _speed01)
	for index in range(_thigh_bones.size()):
		var phase := 1.0 if index == 0 else -1.0
		var thigh := swing * phase
		_skeleton.set_bone_pose_rotation(_thigh_bones[index],
			_rest[_thigh_bones[index]] * Quaternion(Vector3.RIGHT, thigh))
		if index < _shin_bones.size():
			var knee := maxf(0.0, -sin(_gait) * phase) * 0.45 * _speed01
			_skeleton.set_bone_pose_rotation(_shin_bones[index],
				_rest[_shin_bones[index]] * Quaternion(Vector3.RIGHT, knee))
		if index < _foot_bones.size():
			_skeleton.set_bone_pose_rotation(_foot_bones[index],
				_rest[_foot_bones[index]] * Quaternion(Vector3.RIGHT, -thigh * 0.55))

	# 手臂：走路时反向摆；拦球时张开一点
	var arm_swing := -swing * 0.5
	for index in range(_arm_bones.size()):
		var side := 1.0 if index == 0 else -1.0
		var spread := 0.10 + 0.45 * _block
		_skeleton.set_bone_pose_rotation(_arm_bones[index],
			_rest[_arm_bones[index]]
			* Quaternion(Vector3.RIGHT, arm_swing * side)
			* Quaternion(Vector3.UP, side * spread))

	if _ring != null:
		_ring.visible = ring_enabled
		if ring_enabled:
			_ring_material.albedo_color = Color(0.5, 1.0, 0.85, 0.18)
