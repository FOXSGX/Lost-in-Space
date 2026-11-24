extends Node3D
## LIS Physics SDK · 测试运行框架（纯 GDScript，无第三方依赖）
##
## 每个测试场景把本脚本挂到根节点（或继承它），在 `_run()` 里调用 `check()`。
## 结束时打印机器可读结果行，供 tools/run_tests.ps1 独立判定：
##
##   LIS_SUITE_START <name> expected=<n>
##   PASS  <name>  |  <detail>        ← 每条断言一行
##   FAIL  <name>  |  <detail>
##   SKIP  <name>  |  <reason>
##   LIS_RESULT suite=<name> checks=<n> pass=<p> fail=<f> skip=<s> ...
##   LIS_DONE   suite=<name> failures=<f> checks=<n>
##
## 判定口径（任务书 §18.E）：
##   * 断言**实际执行数**必须等于 expected_checks（-1 = 仅诊断探针，记 RAN 不记 PASS）；
##   * 0 条断言执行却报告通过 = COUNT-MISMATCH，判失败；
##   * SKIP 单独计数，**不计入 PASS**；
##   * 运行器自己数 PASS/FAIL 行，不信测试自报的汇总。

## 套件名（应等于文件名去掉扩展名）。
@export var suite_name: String = "unnamed"
## 期望断言数。-1 = 不校验（诊断探针）。
@export var expected_checks: int = -1
## 结束后是否退出进程。
@export var quit_when_done: bool = true
## 用例超时（秒）。超时由内部计时器强制退出 2，避免运行器干等。
@export var case_timeout_s: float = 180.0

var checks: int = 0
var pass_count: int = 0
var fail_count: int = 0
var skip_count: int = 0
var failed_names: PackedStringArray = PackedStringArray()
var _started_ms: int = 0
var _timed_out: bool = false


func _ready() -> void:
	_configure()
	_started_ms = Time.get_ticks_msec()
	print("LIS_SUITE_START %s expected=%d" % [suite_name, expected_checks])
	_start_timeout()
	await get_tree().process_frame
	await get_tree().physics_frame
	await _run()
	_finish()


## 子类覆写：设置 suite_name / expected_checks（在打印 START 之前调用）。
func _configure() -> void:
	pass


func _start_timeout() -> void:
	var t: SceneTreeTimer = get_tree().create_timer(case_timeout_s, true, false, true)
	t.timeout.connect(func() -> void:
		_timed_out = true
		print("LIS_TIMEOUT suite=%s checks=%d" % [suite_name, checks])
		get_tree().quit(2))


## 子类覆写：测试主体。
func _run() -> void:
	pass


func check(name: String, ok: bool, detail: String = "") -> bool:
	checks += 1
	if ok:
		pass_count += 1
		print("PASS  %s  |  %s" % [name, detail])
	else:
		fail_count += 1
		failed_names.append(name)
		print("FAIL  %s  |  %s" % [name, detail])
	return ok


func check_range(name: String, value: float, lo: float, hi: float, unit: String = "") -> bool:
	return check(name, value >= lo and value <= hi,
		"实测 %.4f%s（期望 %.4f..%.4f）" % [value, unit, lo, hi])


func check_lt(name: String, value: float, limit: float, unit: String = "") -> bool:
	return check(name, value < limit, "实测 %.4f%s（期望 < %.4f）" % [value, unit, limit])


func check_gt(name: String, value: float, limit: float, unit: String = "") -> bool:
	return check(name, value > limit, "实测 %.4f%s（期望 > %.4f）" % [value, unit, limit])


func skip(name: String, reason: String) -> void:
	skip_count += 1
	print("SKIP  %s  |  %s" % [name, reason])


func wait_physics(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame


func elapsed_s() -> float:
	return float(Time.get_ticks_msec() - _started_ms) / 1000.0


# ---------------------------------------------------------------------------
# 场地 / 物体构造
# ---------------------------------------------------------------------------

## 最小世界：地面 + 光。返回地面 StaticBody3D。
func make_world_with_floor(half_size: float = 12.0, y: float = 0.0, friction: float = 0.85) -> StaticBody3D:
	var f: StaticBody3D = StaticBody3D.new()
	f.name = "TestFloor"
	f.collision_layer = LISPhysics.LAYER_WORLD
	f.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = Vector3(half_size * 2.0, 0.4, half_size * 2.0)
	cs.shape = bs
	cs.position = Vector3(0.0, -0.2, 0.0)
	f.add_child(cs)
	var mat: PhysicsMaterial = PhysicsMaterial.new()
	mat.friction = friction
	mat.bounce = 0.0
	mat.rough = false
	f.physics_material_override = mat
	f.position = Vector3(0.0, y, 0.0)
	add_child(f)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "TestSun"
	sun.rotation_degrees = Vector3(-50, 40, 0)
	add_child(sun)
	return f


## 静态墙（带碰撞）。
func make_wall(pos: Vector3, size: Vector3, yaw_deg: float = 0.0) -> StaticBody3D:
	var w: StaticBody3D = StaticBody3D.new()
	w.name = "TestWall"
	w.collision_layer = LISPhysics.LAYER_WORLD
	w.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	w.add_child(cs)
	var mat: PhysicsMaterial = PhysicsMaterial.new()
	mat.friction = 0.85
	mat.rough = false
	w.physics_material_override = mat
	w.position = pos
	w.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	add_child(w)
	return w


## 静态塔台/斜坡（带摩擦，用于需要真实接触的用例）。
func add_static_pad(pos: Vector3, size: Vector3, friction: float = 0.9) -> StaticBody3D:
	var b: StaticBody3D = StaticBody3D.new()
	b.name = "TestPad"
	b.collision_layer = LISPhysics.LAYER_WORLD
	b.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var m: PhysicsMaterial = PhysicsMaterial.new()
	m.friction = friction
	m.bounce = 0.0
	m.rough = false
	b.physics_material_override = m
	b.position = pos + Vector3(0.0, size.y * 0.5, 0.0)
	add_child(b)
	return b


## 从上方垂直向下打射线，取世界坐标 (x, z) 处的地面点。没打中就返回 INF。
## 测试里用它定位真实表面，避免用公式估算导致的"生成在地形里"。
func surface_point_at(x: float, z: float, from_y: float = 12.0, mask: int = -1) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return Vector3.INF
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	q.from = Vector3(x, from_y, z)
	q.to = Vector3(x, -40.0, z)
	q.collision_mask = LISPhysics.LAYER_WORLD if mask < 0 else mask
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	return hit.get("position", Vector3.INF) as Vector3


## 造一个 SDK 刚体。
func make_body(
	pos: Vector3,
	size: Vector3,
	mass_kg: float,
	color: Color = Color(0.62, 0.52, 0.32),
	opts: Dictionary = {}
) -> LISBody:
	var prof: LISBodyProfile = LISBodyProfile.new()
	prof.display_name = str(opts.get("name", "测试物体"))
	prof.size = size
	prof.mass_kg = mass_kg
	prof.color = color
	prof.friction = float(opts.get("friction", 0.7))
	prof.bounce = float(opts.get("bounce", 0.02))
	prof.rough = bool(opts.get("rough", true))
	prof.liftable = bool(opts.get("liftable", true))
	prof.linear_damp = float(opts.get("linear_damp", 0.06))
	prof.angular_damp = float(opts.get("angular_damp", 0.35))
	prof.grip_handles = 0 if bool(opts.get("no_handles", false)) else int(opts.get("handles", 2))
	var b: LISBody = LISBody.new()
	b.name = str(opts.get("node_name", "Body%02d" % (get_child_count() + 1)))
	b.profile = prof
	b.position = pos
	b.rotation_degrees = opts.get("rot_deg", Vector3.ZERO)
	add_child(b)
	return b


## 造一个"虚拟第一人称玩家"：身体碰撞 + 相机 + 适配器（无输入）。
## 这是程序化输入代理，**不是**真人试玩。
func make_avatar(
	eye: Vector3,
	forward: Vector3 = Vector3.FORWARD,
	pid: int = 1,
	prefix: String = "Avatar"
) -> LISFirstPersonAdapter:
	var root: Node3D = Node3D.new()
	root.name = "%s%d" % [prefix, pid]
	add_child(root)
	root.global_position = eye

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = LISPhysics.LAYER_PLAYER
	body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.70
	cs.shape = cap
	body.add_child(cs)
	body.position = Vector3(0.0, -0.86, 0.0)
	root.add_child(body)

	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 72.0
	cam.near = 0.05
	root.add_child(cam)
	cam.global_position = eye
	var look: Vector3 = forward.normalized()
	if look.length() > 0.01 and absf(look.dot(Vector3.UP)) < 0.98:
		cam.look_at(eye + look, Vector3.UP)

	var ad: LISFirstPersonAdapter = LISFirstPersonAdapter.new()
	ad.name = "Adapter"
	ad.read_input = false
	ad.player_id = pid
	root.add_child(ad)
	ad.body = root
	ad.camera = cam
	return ad


## 把代理的相机移到新位置并朝向目标点（模拟玩家走近 / 抬头低头）。
func aim_avatar(ad: LISFirstPersonAdapter, eye: Vector3, look_at_point: Vector3) -> void:
	var root: Node3D = ad.get_parent() as Node3D
	if root != null:
		root.global_position = eye
	var cam: Camera3D = ad.camera
	if cam != null:
		cam.global_position = eye
		var d: Vector3 = look_at_point - eye
		if d.length() > 0.05 and absf(d.normalized().dot(Vector3.UP)) < 0.98:
			cam.look_at(look_at_point, Vector3.UP)


func _finish() -> void:
	if _timed_out:
		return
	var count_ok: bool = expected_checks < 0 or checks == expected_checks
	if not count_ok:
		fail_count += 1
		print("FAIL  COUNT-MISMATCH  |  实际执行 %d 条断言，期望 %d 条" % [checks, expected_checks])
	if checks == 0 and expected_checks != 0:
		fail_count += 1
		print("FAIL  NO-ASSERTIONS  |  一条断言都没执行，不能判通过")
	print("LIS_RESULT suite=%s checks=%d pass=%d fail=%d skip=%d elapsed_s=%.2f count_ok=%s" % [
		suite_name, checks, pass_count, fail_count, skip_count, elapsed_s(), str(count_ok)])
	print("LIS_DONE suite=%s failures=%d checks=%d" % [suite_name, fail_count, checks])
	if quit_when_done:
		await get_tree().process_frame
		get_tree().quit(1 if fail_count > 0 else 0)
