extends CharacterBody3D
class_name EnergyBall

## 能量球：地面滚动、平滑减速、墙面/门框/奶龙反弹。
##
## 本轮只做“地面球”：不做重力、不弹跳、不做旋转球与空气动力学。
## 踢球输入（gulu_app.gd）、球的运动（本文件）、入仓判定（collector.gd）三者分开，
## 以后要加高空球/旋转/重力，只需要换掉这里的积分方式，不用动输入与任务流程。

signal kicked(speed: float)
signal bounced(point: Vector3, speed: float)
signal reached_goal()
signal stuck(point: Vector3)

## 球半径：0.34 m。比真实足球大，第一人称更容易看见与踢中。
const RADIUS := 0.34
## 指数衰减系数：v(t) = v0 * exp(-FRICTION * t)。1.0 → 15 m/s 的球约 15 m 停下。
const FRICTION := 1.0
const STOP_SPEED := 0.30
const MAX_SPEED := 20.0
const WALL_RESTITUTION := 0.72
## 停在同一个地方太久（角落/被堵）→ 交给上层把球挪回可玩位置。
const STILL_RESCUE_TIME := 3.5

var mode := "free"          ## free / moving / scored
var collected := false
## 保留给以后多人计分（现在恒为 0）
var credit_peer := 0

var _visual: Node3D
var _goal: Node3D
var _home := Vector3.ZERO
var _still_time := 0.0
var _goal_reported := false
var _last_kick_ms := -100000
var _bounce_cooldown := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 2 | 16
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	floor_stop_on_slope = false
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	_home = global_position
	_build_visual()
	set_physics_process(true)


func setup_goal(goal: Node3D) -> void:
	_goal = goal


## 踢球：direction 只取水平分量，force 直接作为初速度。
func kick(direction: Vector3, force: float) -> void:
	if mode == "scored":
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	velocity = flat * clampf(force, 0.0, MAX_SPEED)
	mode = "moving"
	_still_time = 0.0
	_last_kick_ms = Time.get_ticks_msec()
	kicked.emit(velocity.length())


## 被奶龙拦下：从 contact 点往 away 方向弹回场内。
func rebound(away: Vector3, speed: float) -> void:
	if mode == "scored":
		return
	var flat := Vector3(away.x, 0.0, away.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.LEFT
	velocity = flat.normalized() * clampf(speed, 1.5, MAX_SPEED)
	mode = "moving"
	_still_time = 0.0
	_bounce_cooldown = 0.0
	bounced.emit(global_position, velocity.length())


func speed() -> float:
	return velocity.length()


func is_moving() -> bool:
	return velocity.length() > STOP_SPEED


func reset_to(at: Vector3) -> void:
	var old_tween: Variant = get_meta("intake_tween") if has_meta("intake_tween") else null
	if old_tween != null and old_tween is Tween and (old_tween as Tween).is_valid():
		(old_tween as Tween).kill()
	set_meta("intake_tween", null)
	global_position = Vector3(at.x, RADIUS + 0.02, at.z)
	velocity = Vector3.ZERO
	mode = "free"
	collected = false
	_goal_reported = false
	_still_time = 0.0
	_bounce_cooldown = 0.0
	visible = true
	scale = Vector3.ONE
	if _visual != null:
		_visual.rotation = Vector3.ZERO


func home_position() -> Vector3:
	return _home


func settle(at: Vector3) -> void:
	global_position = Vector3(at.x, RADIUS + 0.02, at.z)
	velocity = Vector3.ZERO
	if mode != "scored":
		mode = "free"


func _physics_process(delta: float) -> void:
	_bounce_cooldown = maxf(0.0, _bounce_cooldown - delta)
	if mode == "scored":
		return

	var before := global_position
	if velocity.length() > 0.001:
		velocity *= exp(-FRICTION * delta)
		if velocity.length() <= STOP_SPEED:
			velocity = Vector3.ZERO
	velocity.y = 0.0

	move_and_slide()
	_resolve_collisions()
	global_position.y = RADIUS + 0.02
	_roll(before)
	_check_goal()
	_check_still(delta)


func _resolve_collisions() -> void:
	for index in range(get_slide_collision_count()):
		var hit := get_slide_collision(index)
		var normal := hit.get_normal()
		if normal.y > 0.7:
			continue
		# 撞墙 / 门框 / 奶龙：按法线反射，速度打折（不无限加速、不抖动）。
		if velocity.length() > 0.2:
			velocity = velocity.bounce(normal).normalized() * velocity.length() * WALL_RESTITUTION
			if _bounce_cooldown <= 0.0:
				_bounce_cooldown = 0.12
				bounced.emit(global_position, velocity.length())
		else:
			velocity = velocity.slide(normal)


func _roll(before: Vector3) -> void:
	if _visual == null:
		return
	var moved := global_position - before
	moved.y = 0.0
	var distance := moved.length()
	if distance < 0.0005:
		return
	var axis := Vector3.UP.cross(moved.normalized())
	if axis.length_squared() < 0.0001:
		return
	# 滚动而不是贴地滑行：转过的角度 = 位移 / 半径。
	_visual.rotate(axis.normalized(), distance / RADIUS)


func _check_goal() -> void:
	if _goal == null or _goal_reported:
		return
	if bool(_goal.call("contains_point", global_position)):
		_goal_reported = true
		mode = "scored"
		velocity = Vector3.ZERO
		reached_goal.emit()


## 由装货口调用（collector.consume）：真正记入仓。
func collect() -> void:
	if collected:
		return
	collected = true
	mode = "scored"
	velocity = Vector3.ZERO


func _check_still(delta: float) -> void:
	if velocity.length() > 0.05:
		_still_time = 0.0
		return
	_still_time += delta
	if _still_time < STILL_RESCUE_TIME:
		return
	# 只救“真的拿不回来”的位置：角落、门框外侧、装货口侧袋。
	var near_edge := absf(global_position.x) > 18.0 or absf(global_position.z) > 13.0
	var in_bay_pocket := global_position.x > 11.4 and absf(global_position.z) > 2.5
	if near_edge or in_bay_pocket:
		_still_time = 0.0
		stuck.emit(global_position)


# ------------------------------------------------------------------ 外观

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "BallVisual"
	add_child(_visual)

	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = Color("#d8e3e6")
	shell_material.roughness = 0.38
	shell_material.metallic = 0.35
	shell_material.metallic_specular = 0.65

	var shell := SphereMesh.new()
	shell.radius = RADIUS
	shell.height = RADIUS * 2.0
	shell.radial_segments = 24
	shell.rings = 12
	var shell_node := MeshInstance3D.new()
	shell_node.mesh = shell
	shell_node.material_override = shell_material
	_visual.add_child(shell_node)

	# 能量核心：半透明外壳里的一颗发光球
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color("#ffb347")
	core_material.emission_enabled = true
	core_material.emission = Color("#ffb347")
	core_material.emission_energy_multiplier = 2.2
	var core := SphereMesh.new()
	core.radius = RADIUS * 0.62
	core.height = RADIUS * 1.24
	core.radial_segments = 16
	core.rings = 8
	var core_node := MeshInstance3D.new()
	core_node.mesh = core
	core_node.material_override = core_material
	_visual.add_child(core_node)

	# 外壳上的三条经线框：滚动时能明显看出自转，不是贴地滑
	var rib_material := StandardMaterial3D.new()
	rib_material.albedo_color = Color("#375967")
	rib_material.roughness = 0.5
	rib_material.metallic = 0.4
	for index in range(3):
		var rib := TorusMesh.new()
		rib.inner_radius = RADIUS * 0.97
		rib.outer_radius = RADIUS * 1.02
		rib.rings = 24
		rib.ring_segments = 6
		var rib_node := MeshInstance3D.new()
		rib_node.mesh = rib
		rib_node.material_override = rib_material
		rib_node.rotation.y = float(index) * PI / 3.0
		_visual.add_child(rib_node)

	# 赤道一圈琥珀灯带，远景也能读出球在哪
	var band := TorusMesh.new()
	band.inner_radius = RADIUS * 1.01
	band.outer_radius = RADIUS * 1.09
	band.rings = 28
	band.ring_segments = 6
	var band_material := StandardMaterial3D.new()
	band_material.albedo_color = Color("#ffb347")
	band_material.emission_enabled = true
	band_material.emission = Color("#ffb347")
	band_material.emission_energy_multiplier = 1.6
	var band_node := MeshInstance3D.new()
	band_node.mesh = band
	band_node.material_override = band_material
	_visual.add_child(band_node)

	var glow := OmniLight3D.new()
	glow.position = Vector3.ZERO
	glow.light_color = Color("#ffb347")
	glow.light_energy = 0.35
	glow.omni_range = 2.2
	add_child(glow)
