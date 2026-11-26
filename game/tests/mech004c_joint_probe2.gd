extends Node
## MECHANICS-004C · 探针 2：竖直滑动轴（局部 X 旋转到世界 Y）
##
## 目标：证明「重力真实参与运动」是可能的——门必须靠电机托住才不会掉。
## 同时测：硬止挡、横向漂移、障碍阻挡、可动刚体接触。

const MASS := 850.0
const TRAVEL := 4.35
const F_MOTOR := 12000.0
const G := 9.8

var _fail := 0


func _ready() -> void:
	print("ENGINE ", Engine.get_version_info()["string"])
	await _t1_gravity_holds()
	await _t2_motor_lifts()
	await _t3_blocked_by_static()
	await _t4_pushes_rigidbox()
	print("PROBE2_DONE failures=", _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _rig() -> Dictionary:
	var holder: Node3D = Node3D.new()
	add_child(holder)
	var anchor: StaticBody3D = StaticBody3D.new()
	anchor.collision_layer = 1
	anchor.collision_mask = 0
	var a_shape: CollisionShape3D = CollisionShape3D.new()
	var a_box: BoxShape3D = BoxShape3D.new()
	a_box.size = Vector3(0.3, 0.3, 0.3)
	a_shape.shape = a_box
	anchor.add_child(a_shape)
	holder.add_child(anchor)

	var body: RigidBody3D = RigidBody3D.new()
	body.mass = MASS
	body.gravity_scale = 1.0
	body.collision_layer = 4
	body.collision_mask = 1 | 2 | 4
	body.can_sleep = false
	var b_shape: CollisionShape3D = CollisionShape3D.new()
	var b_box: BoxShape3D = BoxShape3D.new()
	b_box.size = Vector3(0.45, 4.2, 4.3)
	b_shape.shape = b_box
	b_shape.position = Vector3(0.0, 2.1, 0.0)
	body.add_child(b_shape)
	holder.add_child(body)

	var joint: SliderJoint3D = SliderJoint3D.new()
	# 把滑动轴（局部 X）转到世界 +Y：这样重力就沿滑动轴，真实参与运动。
	joint.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	joint.set("linear_limit/upper_distance", TRAVEL)
	joint.set("linear_limit/lower_distance", 0.0)
	joint.set("linear_limit/softness", 1.0)
	joint.set("linear_limit/damping", 1.0)
	holder.add_child(joint)
	joint.node_a = joint.get_path_to(anchor)
	joint.node_b = joint.get_path_to(body)
	return {"holder": holder, "anchor": anchor, "body": body, "joint": joint}


func _t1_gravity_holds() -> void:
	var r: Dictionary = _rig()
	var body: RigidBody3D = r["body"] as RigidBody3D
	var joint: SliderJoint3D = r["joint"] as SliderJoint3D
	for _i in range(20):
		await get_tree().physics_frame
	var y0: float = body.global_position.y
	# 只受重力，不施力
	for _i in range(120):
		await get_tree().physics_frame
	var y1: float = body.global_position.y
	var axis: Vector3 = joint.global_transform.basis.x.normalized()
	var drifted: float = Vector2(body.global_position.x, body.global_position.z).length()
	var tilt: float = body.global_transform.basis.y.dot(Vector3.UP)
	var ok: bool = absf(y1 - y0) < 0.02 and drifted < 0.02 and tilt > 0.999
	_line("T1 竖直滑轴下只受重力：门停在关闭位不自由落体，无横向漂移",
		ok, "y %.3f→%.3f drift=%.4f tilt=%.4f joint_axis=%s" % [y0, y1, drifted, tilt, str(axis.snapped(Vector3(0.001, 0.001, 0.001)))])
	(r["holder"] as Node).queue_free()
	await _w(4)


func _t2_motor_lifts() -> void:
	var r: Dictionary = _rig()
	var body: RigidBody3D = r["body"] as RigidBody3D
	for _i in range(20):
		await get_tree().physics_frame
	var y0: float = body.global_position.y
	var mass_g: float = MASS * G
	# 用小于重力的力：应当纹丝不动（证明重力真的参与）
	for _i in range(60):
		body.apply_central_force(Vector3.UP * (mass_g * 0.7))
		await get_tree().physics_frame
	var y_underpowered: float = body.global_position.y
	# 用满推力：应当上升
	var peak := 0.0
	for _i in range(150):
		body.apply_central_force(Vector3.UP * F_MOTOR)
		await get_tree().physics_frame
		peak = maxf(peak, body.global_position.y - y0)
	var y1: float = body.global_position.y
	var top_ok: bool = absf((y1 - y0) - TRAVEL) < 0.06
	var accel_expected: float = (F_MOTOR - mass_g) / MASS
	_line("T2 电机托举：0.7×Mg 托不动（重力真实参与），满推力升到上止挡",
		absf(y_underpowered - y0) < 0.03 and y1 - y0 > 3.0 and top_ok,
		"under=%.3f rise=%.3f peak=%.3f 期望a=%.2f m/s² travel=%.2f" % [
			y_underpowered - y0, y1 - y0, peak, accel_expected, TRAVEL])
	(r["holder"] as Node).queue_free()
	await _w(4)


func _t3_blocked_by_static() -> void:
	var r: Dictionary = _rig()
	var body: RigidBody3D = r["body"] as RigidBody3D
	var holder: Node3D = r["holder"] as Node3D
	# 在门的上方路径里放一块真实静态障碍。门关闭时顶面在 y=4.2，
	# 障碍下表面放在 y=5.3（中心 5.5），门只有 1.1 m 的上升余地。
	var blocker: StaticBody3D = StaticBody3D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var s: CollisionShape3D = CollisionShape3D.new()
	var sb: BoxShape3D = BoxShape3D.new()
	sb.size = Vector3(1.2, 0.4, 5.2)
	s.shape = sb
	blocker.add_child(s)
	blocker.position = Vector3(0.0, 5.5, 0.0)
	holder.add_child(blocker)
	for _i in range(20):
		await get_tree().physics_frame
	var y0: float = body.global_position.y
	for _i in range(180):
		body.apply_central_force(Vector3.UP * F_MOTOR)
		await get_tree().physics_frame
	var y_stalled: float = body.global_position.y
	var rise: float = y_stalled - y0
	var lateral: float = Vector2(body.global_position.x, body.global_position.z).length()
	var y_after: float = 0.0
	# 移走障碍后应当继续上升
	blocker.queue_free()
	for _i in range(6):
		await get_tree().physics_frame
	for _i in range(200):
		body.apply_central_force(Vector3.UP * F_MOTOR)
		await get_tree().physics_frame
	y_after = body.global_position.y
	_line("T3 静态障碍真实阻挡：满推力被挡住不穿透，移走障碍后继续上升",
		rise > 0.6 and rise < 1.4 and lateral < 0.10 and (y_after - y0) > rise + 1.0,
		"stalled_rise=%.3f lateral=%.4f after=%.3f" % [rise, lateral, y_after - y0])
	holder.queue_free()
	await _w(4)


func _t4_pushes_rigidbox() -> void:
	var r: Dictionary = _rig()
	var body: RigidBody3D = r["body"] as RigidBody3D
	var holder: Node3D = r["holder"] as Node3D
	var crate: RigidBody3D = RigidBody3D.new()
	crate.mass = 40.0
	crate.collision_layer = 4
	crate.collision_mask = 1 | 4
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cb: BoxShape3D = BoxShape3D.new()
	cb.size = Vector3(0.6, 0.6, 0.6)
	cs.shape = cb
	crate.add_child(cs)
	crate.position = Vector3(0.0, 4.55, 0.0)
	holder.add_child(crate)
	for _i in range(20):
		await get_tree().physics_frame
	var crate_y0: float = crate.global_position.y
	var body_y0: float = body.global_position.y
	for _i in range(220):
		body.apply_central_force(Vector3.UP * F_MOTOR)
		await get_tree().physics_frame
	var crate_rise: float = crate.global_position.y - crate_y0
	var body_rise: float = body.global_position.y - body_y0
	_line("T4 可动刚体真实接触：门推起 40 kg 箱子（箱子自己受碰撞上升，脚本没动它）",
		crate_rise > 0.3 and body_rise > 0.2,
		"crate_rise=%.3f body_rise=%.3f crate_v=%s" % [crate_rise, body_rise,
			str(crate.linear_velocity.snapped(Vector3(0.01, 0.01, 0.01)))])
	holder.queue_free()
	await _w(4)


func _line(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_fail += 1
	print("%s  %s  |  %s" % ["PASS" if ok else "FAIL", label, detail])


func _w(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
