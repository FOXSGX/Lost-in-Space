extends "res://tests/harness/lis_test_case.gd"
## 核心层 · 摩擦与材质
##
## 验证"物体不是同一套硬编码摩擦"：
##   * 同一坡面上，低摩擦物先滑、高摩擦物不动；
##   * rough=false 让地面材质参与合成（"冰面 vs 橡胶面"必须这样才成立）；
##   * rough=true 只用本物体摩擦（手感可预测）；
##   * bounce 真的改变回弹高度。
##
## 不用 Transform 造运动：滑移与回弹全部来自重力与接触。
## 物体落点由**坡道自身变换**推出（不用估算公式，也不靠射线 ——
## 射线会打到坡道下方的地面，导致物体被生成在地形里）。

const SLOPE_DEG := 16.0
const RAMP_SIZE := Vector3(6.0, 0.30, 6.0)
## 坡道中心高度：必须让低端顶面也高于地面，否则物体实际落在地面上。
const RAMP_CENTER_Y := 0.95


func _configure() -> void:
	suite_name = "core_friction"
	expected_checks = 9


func _run() -> void:
	make_world_with_floor(24.0)
	await wait_physics(5)

	var ramp: StaticBody3D = add_static_pad(Vector3(0.0, RAMP_CENTER_Y, -6.0),
		RAMP_SIZE, 0.85)
	ramp.rotation_degrees = Vector3(SLOPE_DEG, 0.0, 0.0)
	var ice_ramp: StaticBody3D = add_static_pad(Vector3(9.0, RAMP_CENTER_Y, -6.0),
		Vector3(5.0, 0.30, 6.0), 0.02)
	ice_ramp.rotation_degrees = Vector3(SLOPE_DEG, 0.0, 0.0)
	await wait_physics(6)

	# 坡道低端顶面必须离地（否则所有读数都在测"平地上的摩擦"）
	var low_top: Vector3 = _ramp_top(ramp, 0.0, 2.6)
	check("坡道低端顶面高于地面", low_top.y > 0.15, "低端顶面 y=%.3f m" % low_top.y)

	# tan16° ≈ 0.287 → μ=0.10 必滑，μ=0.85 静止。
	var p_slick: Vector3 = _ramp_top(ramp, -1.2, 0.4)
	var p_grip: Vector3 = _ramp_top(ramp, 1.2, 0.4)
	var slick: LISBody = make_body(p_slick + Vector3(0.0, 0.24, 0.0), Vector3(0.4, 0.4, 0.4), 8.0,
		Color(0.6, 0.8, 0.95), {"friction": 0.10, "rough": false, "handles": 0})
	var grippy: LISBody = make_body(p_grip + Vector3(0.0, 0.24, 0.0), Vector3(0.4, 0.4, 0.4), 8.0,
		Color(0.9, 0.7, 0.4), {"friction": 0.85, "rough": false, "handles": 0})
	var start_slick: Vector3 = slick.global_position
	var start_grip: Vector3 = grippy.global_position
	await wait_physics(160)

	var drift_slick: float = _xz(start_slick, slick.global_position)
	var drift_grip: float = _xz(start_grip, grippy.global_position)
	check_gt("低摩擦物（μ=0.10）在 16° 坡上滑下来", drift_slick, 0.45, " m")
	check_lt("高摩擦物（μ=0.85）在 16° 坡上保持静止", drift_grip, 0.10, " m")
	check_gt("两者滑移量差异显著", drift_slick / maxf(drift_grip, 0.001), 5.0, " 倍")

	# rough：同一 μ 的物体放到极滑冰坡上对比（冰 0.02，16° 坡度 tan≈0.287）
	var p_rough: Vector3 = _ramp_top(ice_ramp, -1.0, 0.4)
	var p_blend: Vector3 = _ramp_top(ice_ramp, 1.0, 0.4)
	var rough_on_ice: LISBody = make_body(p_rough + Vector3(0.0, 0.24, 0.0),
		Vector3(0.4, 0.4, 0.4), 8.0, Color(0.5, 0.9, 0.5),
		{"friction": 0.85, "rough": true, "handles": 0})
	var blend_on_ice: LISBody = make_body(p_blend + Vector3(0.0, 0.24, 0.0),
		Vector3(0.4, 0.4, 0.4), 8.0, Color(0.95, 0.5, 0.5),
		{"friction": 0.85, "rough": false, "handles": 0})
	var s_rough: Vector3 = rough_on_ice.global_position
	var s_blend: Vector3 = blend_on_ice.global_position
	await wait_physics(160)
	var d_rough: float = _xz(s_rough, rough_on_ice.global_position)
	var d_blend: float = _xz(s_blend, blend_on_ice.global_position)
	check_lt("rough=true 忽略地面材质（冰坡上不滑）", d_rough, 0.15, " m")
	check_gt("rough=false 让冰面参与合成（滑出去）", d_blend, 0.45, " m")

	# 弹跳：两个球**同时**投放、在同一循环里测（先后测会让后者已落地静止）。
	var hard_ball: LISBody = make_body(Vector3(-9.0, 2.2, 6.0),
		Vector3(0.30, 0.30, 0.30), 4.0, Color(0.9, 0.9, 0.4),
		{"friction": 0.5, "bounce": 0.0, "handles": 0})
	var bouncy: LISBody = make_body(Vector3(-6.0, 2.2, 6.0),
		Vector3(0.30, 0.30, 0.30), 4.0, Color(0.4, 0.9, 0.9),
		{"friction": 0.5, "bounce": 0.72, "handles": 0})
	var peaks: Vector2 = await _rebound_peaks(hard_ball, bouncy)
	check_lt("bounce=0 几乎不回弹", peaks.x, 0.30, " m")
	check_gt("bounce=0.72 明显回弹", peaks.y, 0.55, " m")

	# 参数真的写进材质
	var mat: PhysicsMaterial = slick.physics_material_override
	check("PhysicsMaterial 摩擦与参数一致",
		mat != null and is_equal_approx(mat.friction, 0.10) and not mat.rough,
		"μ=%.2f rough=%s" % [mat.friction if mat != null else -1.0,
			str(mat.rough) if mat != null else "?"])


## 坡道顶面上某点（局部 x, z）的世界坐标。用坡道自身变换，不估算。
func _ramp_top(ramp: StaticBody3D, lx: float, lz: float) -> Vector3:
	var half_y: float = RAMP_SIZE.y * 0.5
	if ramp.name.contains("Pad") and size_of(ramp) != Vector3.ZERO:
		half_y = size_of(ramp).y * 0.5
	return ramp.global_transform * Vector3(lx, half_y, lz)


func size_of(b: StaticBody3D) -> Vector3:
	for c: Node in b.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return ((c as CollisionShape3D).shape as BoxShape3D).size
	return Vector3.ZERO


func _xz(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


## 同时投放两个球，返回 (硬球回弹高, 弹球回弹高)，相对各自落点。
func _rebound_peaks(a: RigidBody3D, b: RigidBody3D) -> Vector2:
	var landed_a: bool = false
	var landed_b: bool = false
	var peak_a: float = 0.0
	var peak_b: float = 0.0
	for i in range(400):
		await get_tree().physics_frame
		if not landed_a and a.global_position.y < 0.32:
			landed_a = true
		if not landed_b and b.global_position.y < 0.32:
			landed_b = true
		if landed_a:
			peak_a = maxf(peak_a, a.global_position.y)
		if landed_b:
			peak_b = maxf(peak_b, b.global_position.y)
		if landed_a and landed_b and i > 30:
			var done_a: bool = absf(a.linear_velocity.y) < 0.05 and a.global_position.y < 0.25
			var done_b: bool = absf(b.linear_velocity.y) < 0.05 and b.global_position.y < 0.25
			if done_a and done_b:
				break
	return Vector2(peak_a - 0.15, peak_b - 0.15)
