extends Node
## MECHANICS-004C · 探针：Godot 4.7.2 + Jolt 对 SliderJoint3D 的实际行为
##
## 这个探针不是验收测试，它只回答三个工程问题：
##   1. SliderJoint3D 的滑动轴在本引擎里到底是局部哪个轴（identity basis 下）。
##   2. linear_limit 的上下限是否真的形成硬止挡（重力压住时不穿透）。
##   3. 施加真实力能否推动刚体，且横向误差（joint_error）是否可控。
##
## 每个子实验都在一个独立的子场景里跑，互不干扰。结果只打印。

const MASS := 420.0
const TRAVEL := 4.35
const FORCE := 3000.0

var results: Array[String] = []


func _ready() -> void:
	print("ENGINE ", Engine.get_version_info()["string"], " physics=",
		ProjectSettings.get_setting("physics/3d/physics_engine"))
	await _axis_probe(Vector3.RIGHT, "X")
	await _axis_probe(Vector3.UP, "Y")
	await _axis_probe(Vector3.BACK, "Z")
	print("PROBE_DONE")
	get_tree().quit(0)


## 在 identity 关节基下，分别沿 +X/+Y/+Z 施力，看刚体到底沿哪根轴动。
func _axis_probe(dir: Vector3, label: String) -> void:
	var holder: Node3D = Node3D.new()
	add_child(holder)

	var anchor: StaticBody3D = StaticBody3D.new()
	anchor.name = "Anchor"
	anchor.collision_layer = 1
	anchor.collision_mask = 0
	var a_shape: CollisionShape3D = CollisionShape3D.new()
	var a_box: BoxShape3D = BoxShape3D.new()
	a_box.size = Vector3(0.4, 0.4, 0.4)
	a_shape.shape = a_box
	anchor.add_child(a_shape)
	holder.add_child(anchor)

	var body: RigidBody3D = RigidBody3D.new()
	body.name = "Body"
	body.mass = MASS
	body.gravity_scale = 1.0
	body.collision_layer = 1
	body.collision_mask = 1
	body.can_sleep = true
	body.position = Vector3(0.0, 0.0, 0.0)
	var b_shape: CollisionShape3D = CollisionShape3D.new()
	var b_box: BoxShape3D = BoxShape3D.new()
	b_box.size = Vector3(0.45, 4.2, 4.3)
	b_shape.shape = b_box
	body.add_child(b_shape)
	holder.add_child(body)

	var joint: SliderJoint3D = SliderJoint3D.new()
	joint.name = "Slider"
	joint.position = Vector3.ZERO
	joint.set("linear_limit/upper_distance", TRAVEL)
	joint.set("linear_limit/lower_distance", 0.0)
	joint.set("linear_limit/softness", 1.0)
	joint.set("linear_limit/restitution", 0.0)
	joint.set("linear_limit/damping", 1.0)
	holder.add_child(joint)
	joint.node_a = joint.get_path_to(anchor)
	joint.node_b = joint.get_path_to(body)

	# 让关节初始化
	for _i in range(20):
		await get_tree().physics_frame
	var start: Vector3 = body.global_position

	# 阶段 1：只受重力（应该在止挡处停住，不继续掉）
	for _i in range(90):
		await get_tree().physics_frame
	var under_gravity: Vector3 = body.global_position

	# 阶段 2：沿候选轴施力
	for _i in range(90):
		body.apply_central_force(dir * FORCE)
		await get_tree().physics_frame
	var after_force: Vector3 = body.global_position

	var d_grav: Vector3 = under_gravity - start
	var d_force: Vector3 = after_force - under_gravity
	var line := "%s | gravityΔ=%s | forceΔ=%s | axis_moved=%s" % [
		label, str(d_grav.snapped(Vector3(0.001, 0.001, 0.001))),
		str(d_force.snapped(Vector3(0.001, 0.001, 0.001))),
		str(_dominant(d_force))]
	results.append(line)
	print("AXIS ", line)
	holder.queue_free()
	for _i in range(4):
		await get_tree().physics_frame


func _dominant(v: Vector3) -> String:
	var ax := absf(v.x)
	var ay := absf(v.y)
	var az := absf(v.z)
	if ax >= ay and ax >= az:
		return "X(%.3f)" % v.x
	if ay >= az:
		return "Y(%.3f)" % v.y
	return "Z(%.3f)" % v.z
