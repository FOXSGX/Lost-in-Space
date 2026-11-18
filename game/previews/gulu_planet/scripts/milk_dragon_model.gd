extends Node3D
class_name MilkDragonModelVisual

## 奶龙外观（正式模型版）：assets/characters/nailong_dl.glb。
##
## 来源：Sketchfab "nailong" by RED ANGRY BIRDS，CC-BY-4.0
## （见 assets/characters/nailong_dl_LICENSE.txt）。
##
## 本文件只负责“看起来对”：接地、按速度迈步、平滑转身、拦球姿势。
## 行为（站位/拦截/恢复/回防）在 milk_dragon.gd，通过
## set_look_point / set_locomotion / set_stride / set_block 沟通。
##
## 模型自身：高 1.83 m、脚底 y=-0.072、脸朝 +Z。所以底下垫 0.072，外层绕 Y 转 180°。
##
## 说明：本环境看不到画面，“脚步是否自然”只能靠代码规则保证（步频由实际速度驱动、
## 停止时步态归零、支撑脚回正），最终观感需要用户看录像确认。

const MODEL_PATH := "res://assets/characters/nailong.glb"
const GROUND_OFFSET := 0.0
## 每走 1 米播放多少弧度步态（约 2.4 m 一个完整步幅）
const GAIT_PER_METER := 2.6

var _look_point := Vector3.ZERO
var _has_look_point := false
var _speed01 := 0.0
var _lateral01 := 0.0
var _forward01 := 0.0
var _planar_speed := 0.0
var _block := 0.0
var _time := 0.0
var _gait := 0.0
var _stride_blend := 0.0

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


## speed01: 0..1；lateral01: 本地横移比例（-1..1）
func set_locomotion(speed01: float, lateral01: float) -> void:
	_speed01 = clampf(speed01, 0.0, 1.0)
	_lateral01 = clampf(lateral01, -1.0, 1.0)


## forward01: 本地前向速度比例（-1..1）；planar: 实际水平速度（m/s），用来推进步态
func set_stride(forward01: float, planar: float) -> void:
	_forward01 = clampf(forward01, -1.0, 1.0)
	_planar_speed = maxf(planar, 0.0)


func set_block(weight: float) -> void:
	_block = clampf(weight, 0.0, 1.0)


# ------------------------------------------------------------------ 组装

func _build() -> void:
	# 接地阴影：静态模型没有脚部动画时，靠一块低对比圆盘把脚“压”在地面上。
	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0.03, 0.045, 0.04, 0.30)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.78
	shadow_mesh.bottom_radius = 0.78
	shadow_mesh.height = 0.006
	shadow_mesh.radial_segments = 24
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow"
	shadow.mesh = shadow_mesh
	shadow.position.y = 0.008
	shadow.material_override = shadow_material
	add_child(shadow)

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	_facing = Node3D.new()
	_facing.name = "Facing"
	_facing.rotation.y = 0.0
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
	var placeholders: Array[Node] = []
	for node in meshes:
		var mi := node as MeshInstance3D
		# Sketchfab 导出里残留了一个 2 m 的 Icosphere 占位球（LICENSE 声称已移除，
		# 但 GLB 里仍在）。它会把整只奶龙包在一个大球里；必须在运行时剔除。
		if mi.name.to_lower().begins_with("icosphere"):
			placeholders.append(mi)
			continue
		mi.visible = true
		for surface in range(mi.mesh.get_surface_count()):
			var material := mi.get_active_material(surface)
			if material is StandardMaterial3D:
				var tint := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
				mi.set_surface_override_material(surface, tint)
				_tint_materials.append(tint)
				_tint_base.append(tint.albedo_color)
	for placeholder in placeholders:
		placeholder.get_parent().remove_child(placeholder)
		placeholder.queue_free()

	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() > 0:
		_skeleton = skeletons[0] as Skeleton3D
		_cache_bones()

	_mouth_anchor = Node3D.new()
	_mouth_anchor.name = "MouthAnchor"
	_mouth_anchor.position = Vector3(0.0, 1.20, -0.42)
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
	if _has_look_point:
		var local := to_local(_look_point) - _facing.position
		var yaw := clampf(atan2(-local.x, -local.z), -0.9, 0.9)
		var pitch := clampf(atan2(local.y - 1.31, Vector2(local.x, local.z).length()), -0.35, 0.45)
		_head_yaw = lerpf(_head_yaw, yaw, 1.0 - exp(-8.0 * delta))
		_head_pitch = lerpf(_head_pitch, pitch, 1.0 - exp(-7.0 * delta))
	else:
		_head_yaw = lerpf(_head_yaw, sin(_time * 0.6) * 0.12, 1.0 - exp(-3.0 * delta))
		_head_pitch = lerpf(_head_pitch, 0.0, 1.0 - exp(-4.0 * delta))

	var target_lean := -0.10 * _speed01 - 0.16 * _block
	_lean = lerpf(_lean, target_lean, 1.0 - exp(-9.0 * delta))

	# 步态由“实际走过的距离”推进：速度为零 → 步态完全停住；
	# 停下来时用 _stride_blend 把腿收回中立位，不会定格在半步。
	var want_stride := 1.0 if _planar_speed > 0.15 else 0.0
	_stride_blend = lerpf(_stride_blend, want_stride, 1.0 - exp(-10.0 * delta))
	_gait += _planar_speed * delta * GAIT_PER_METER


func _apply_pose() -> void:
	var bob := 0.0
	_body.position.y = bob
	_body.position.x = sin(_gait * 0.5) * 0.012 * absf(_lateral01) * _stride_blend
	# 静态模型的步态只走整体节点：轻微上下、前后俯仰、左右摆，不改骨骼/网格。
	_body.rotation.x = _lean + sin(_gait) * 0.022 * _speed01
	_body.rotation.z = lerpf(_body.rotation.z, -0.030 * _lateral01 * _speed01 + sin(_gait * 0.5) * 0.018 * _speed01, 0.12)
	_body.scale = Vector3.ONE

	if _skeleton == null:
		return

	var head_animation := false
	if head_animation and _head_bone >= 0:
		var yaw := _head_yaw
		var pitch := _head_pitch - 0.10 * _block
		_skeleton.set_bone_pose_rotation(_head_bone,
			_rest[_head_bone] * Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch))
		if head_animation and _neck_bone >= 0:
			_skeleton.set_bone_pose_rotation(_neck_bone,
				_rest[_neck_bone] * Quaternion(Vector3.UP, yaw * 0.35))

	# 四肢骨骼的局部轴没有在 glTF 里验证过；按世界 X 轴旋转会把腿/手臂拧进身体，
	# 造成“人物完全变形”。本轮先关闭四肢骨骼动画，只保留整体位移/前倾/转头；
	# 宁可少一点步态细节，也不能让模型变形。
	var limb_animation := false
	if limb_animation:
		# 迈步幅度：前进速度与“确实在走”两个因子
		var amplitude := 0.34 * absf(_forward01) * _stride_blend
		var swing := sin(_gait) * amplitude
		for index in range(_thigh_bones.size()):
			var phase := 1.0 if index == 0 else -1.0
			var thigh := swing * phase
			_skeleton.set_bone_pose_rotation(_thigh_bones[index],
				_rest[_thigh_bones[index]] * Quaternion(Vector3.RIGHT, thigh))
			var knee := 0.0
			if index < _shin_bones.size():
				knee = maxf(0.0, sin(_gait) * phase) * 0.50 * absf(_forward01) * _stride_blend
				_skeleton.set_bone_pose_rotation(_shin_bones[index],
					_rest[_shin_bones[index]] * Quaternion(Vector3.RIGHT, knee))
			if index < _foot_bones.size():
				var foot := -(thigh * 0.85) - knee * 0.45
				_skeleton.set_bone_pose_rotation(_foot_bones[index],
					_rest[_foot_bones[index]] * Quaternion(Vector3.RIGHT, foot))

		var arm_swing := -swing * 0.45
		for index in range(_arm_bones.size()):
			var side := 1.0 if index == 0 else -1.0
			var spread := 0.10 + 0.45 * _block
			_skeleton.set_bone_pose_rotation(_arm_bones[index],
				_rest[_arm_bones[index]]
				* Quaternion(Vector3.RIGHT, arm_swing * side)
				* Quaternion(Vector3.UP, side * spread))
	else:
		# 回到 glTF 的静置姿态；只允许整体节点动。
		for index in _thigh_bones:
			_skeleton.set_bone_pose_rotation(index, _rest[index])
		for index in _shin_bones:
			_skeleton.set_bone_pose_rotation(index, _rest[index])
		for index in _foot_bones:
			_skeleton.set_bone_pose_rotation(index, _rest[index])
		for index in _arm_bones:
			_skeleton.set_bone_pose_rotation(index, _rest[index])

	if _ring != null:
		_ring.visible = ring_enabled





