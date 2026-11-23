extends AnimatableBody3D

# Host-owned path motor. +X is the approved cart's longitudinal axis.
# Characters remain world-space CharacterBody3D and use native platform support.
#
# Resonance 02+03 integration: the route now runs 16 m past the old arrival dock
# because the severed section sits at s = 90. The cart is governed to stop at
# FAULT_STOP until `route_clear` is set by the level flow (that is, until the
# swing rail is mechanically locked). Nothing else about the motor changed.
const LENGTH: float = 106.0
const FAULT_STOP: float = 88.0
const CRUISE: float = 1.55
const DECK_Y: float = 1.9546444

# --- MECHANICS-002B · 受轨道约束的一维纵向动力学 ----------------------------
# 位置仍由 route_pose(distance) 决定（矿车是沿轨道的 AnimatableBody3D），但
# 速度不再是"目标速度伺服"：每帧由合力积分得出
#   M_eff · dv/dt = F_traction − F_brake − F_resistance − F_grade
# F_brake 来自 cart_brake_rig 的真实闸瓦压紧力，其余量同样有明确上限。
const CART_MASS: float = 1650.0      # 矿车整备质量（车体/走台/设备，kg）
const CREW_MASS: float = 78.0        # 每名在车人员的等效质量（kg）
const GRAV: float = 9.81
const WHEEL_R: float = 0.795         # 与既有轮子转速换算一致（m）
const CRR: float = 0.008             # 滚动 + 轮缘阻力系数（钢轮/钢轨，干态）
const DRAG_C: float = 1.35           # 空气阻力系数（N·s²/m²，量级很小）
const KP_TRACTION: float = 12000.0   # 牵引速度环增益（N per m/s）
const F_TRACTION_MAX: float = 1200.0 # 牵引力上限（N，≈0.7 m/s²，保持原手感）
const GOVERNOR_BRAKE_MAX: float = 2500.0  # 电制动（调速器）上限（N）

var distance: float = 0.0
var speed: float = 0.0
var acceleration: float = 0.0
var state: String = "停靠待发"
var running: bool = false
var motor_braking: bool = false      # 调速器电制动（安全/调度停车走这条路）
var arrived: bool = false
var route_clear: bool = false
var stopped_for_fault: bool = false
# Last reason the motor was stopped, so a debug panel and a test can tell
# "the player braked" from "the level braked on purpose".
var brake_reason: String = ""
var event_active: bool = false
var bend_event: Node3D
var clock: float = 0.0
var previous_transform: Transform3D = Transform3D.IDENTITY
var world_velocity: Vector3 = Vector3.ZERO
var world_acceleration: Vector3 = Vector3.ZERO
var angular_velocity_y: float = 0.0
var revision: int = 0
var wheels: Array[Node3D] = []
var visual_node: Node3D
var stage: Node3D
var paused: bool = false
# MECHANICS-002B：前甲板机械手制动
var brake_rig: Node3D
var auto_parking: bool = true        # 调度停车后自动落闸（玩家可松开）
# 每帧力账本（测试与 HUD 读它，任何一项都不在别处被写第二次）
var forces: Dictionary = {"traction": 0.0, "brake": 0.0, "resistance": 0.0,
	"grade": 0.0, "mass": CART_MASS, "slope": 0.0}
# Client mirror. When true this body never integrates: the host publishes the
# distance and the client rebuilds the exact same route pose from it, so both
# ends can never draw two different carts.
var network_client: bool = false
var target_distance: float = 0.0
var mirror_speed: float = 0.0

static func route_slope(s: float) -> float:
	# 轨道中心线本身有起伏（route_height），所以坡度力是真实存在的：
	# 最大纵坡 ≈ 0.0065（0.37°），量级与滚动阻力相当。
	return (route_height(s + 0.05) - route_height(s - 0.05)) / 0.1

static func route_height(s: float) -> float:
	return 0.11 * (1.0 - cos(s * TAU / LENGTH))

static func bend(s: float) -> float:
	return 5.8 * smoothstep(23.0, 49.0, s) - 3.2 * smoothstep(61.0, 83.0, s)

static func route_pose(s: float) -> Transform3D:
	var derivative: float = (bend(s + 0.05) - bend(s - 0.05)) / 0.1
	var yaw: float = -atan(derivative)
	var tilt: float = atan((route_height(s + 0.05) - route_height(s - 0.05)) / 0.1)
	var basis_at: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, -tilt)
	var center: Vector3 = Vector3(s, route_height(s), 2.2 + bend(s))
	return Transform3D(basis_at, center - basis_at * Vector3(0, 0, 2.2))

func _ready() -> void:
	process_physics_priority = -50
	collision_layer = 34 # solid + moving platform (bits 2 and 6)
	collision_mask = 24
	sync_to_physics = false # physics tick is the sole writer; no deferred visual transform
	var physical: PhysicsMaterial = PhysicsMaterial.new()
	physical.friction = 0.10
	physical.bounce = 0.0
	physics_material_override = physical
	_box("Deck", Vector3(-0.15, 1.8646, 2.2), Vector3(6.5, 0.18, 2.66))
	# The character's collision capsule is 1.5 m tall but the ranger mesh is far
	# taller, so players could walk under the 1.77 m deck with their head through
	# it (the old repair walk did exactly that). This solid volume under the deck
	# is player-only (layer 2) and rides with the cart, so "under the cart" is no
	# longer a walkable shortcut. Boarding via the stairs arrives above it.
	var under_deck: AnimatableBody3D = AnimatableBody3D.new()
	under_deck.name = "UnderDeckBlock"
	under_deck.collision_layer = 2
	under_deck.collision_mask = 0
	under_deck.sync_to_physics = false
	var under_shape: BoxShape3D = BoxShape3D.new()
	under_shape.size = Vector3(7.70, 1.80, 2.66)
	var under_collider: CollisionShape3D = CollisionShape3D.new()
	under_collider.shape = under_shape
	under_collider.position = Vector3(0.40, 0.90, 2.20)
	under_deck.add_child(under_collider)
	add_child(under_deck)
	# No camera-solid duplicate for the ring: its collider is a solid box across
	# the whole hoop, so a duplicate sealed the opening that the chase lens has to
	# look through. HoopCameraGuard below models the actual torus tube instead.
	_box("Ring", Vector3(-2.5, 3.12, 2.2), Vector3(0.30, 2.5, 2.65), false)
	_box("Cab", Vector3(3.6, 1.6, 2.2), Vector3(1.3, 1.8, 2.5), true)
	for z: float in [0.87, 3.53]:
		# The near-side boarding gate stays open, matching the existing stairs.
		for span: Vector2 in ([Vector2(-1.7, 0.52), Vector2(1.48, 2.88)] if z < 1.0 else [Vector2(-2.1, 2.88)]):
			_box("Rail", Vector3((span.x + span.y) * 0.5, 2.53, z), Vector3(span.y - span.x, 1.17, 0.09))
	_box("RearStop", Vector3(-3.32, 2.25, 2.2), Vector3(0.10, 0.62, 2.65))
	# Camera-only guard for the resonance hoop. It is shaped like the torus, not
	# like a solid slab: the old 3.05 m slab also covered the hoop's opening, so a
	# 5 m chase boom could never pass through and was permanently shortened to
	# ~3.2 m. Sixteen tangential boxes block the tube (the lens cannot settle
	# *behind* the hoop at deck level) while the real opening stays open, which is
	# the only path that keeps the rider framed at full boom length.
	var hoop_guard: AnimatableBody3D = AnimatableBody3D.new()
	hoop_guard.name = "HoopCameraGuard"
	hoop_guard.collision_layer = 4
	hoop_guard.collision_mask = 0
	hoop_guard.sync_to_physics = false
	for index: int in range(16):
		var angle: float = TAU * float(index) / 16.0
		var guard_shape: BoxShape3D = BoxShape3D.new()
		guard_shape.size = Vector3(0.36, 0.30, 0.46)
		var guard_collider: CollisionShape3D = CollisionShape3D.new()
		guard_collider.shape = guard_shape
		guard_collider.position = Vector3(-2.5, 3.12 + cos(angle) * 1.24, 2.2 + sin(angle) * 1.24)
		guard_collider.rotation = Vector3(angle, 0.0, 0.0)
		hoop_guard.add_child(guard_collider)
	add_child(hoop_guard)
	brake_rig = preload("res://act23/scripts/cart_brake_rig.gd").new() as Node3D
	brake_rig.name = "HandBrake"
	brake_rig.set("cart", self)
	add_child(brake_rig)
	previous_transform = transform

# --- 质量 / 手制动接口 ------------------------------------------------------

# 有效质量 = 整备质量 + 车上货物实际质量 + 在车人员。货物取 RigidBody 的
# 真实 mass（6 kg/件），不另写常量；人员按 contains_point 判定在不在甲板。
func effective_mass() -> float:
	var mass: float = CART_MASS
	if stage == null:
		return mass
	var device: Variant = stage.get("device")
	if device is Node:
		var cargo_raw: Variant = (device as Node).get("cargo")
		if cargo_raw is Array:
			for body: Variant in (cargo_raw as Array):
				if body is Node and is_instance_valid(body):
					# 只有真的在甲板上的容器才算载荷；掉在隧道里的不算。
					if contains_point((body as Node3D).global_position, 0.6):
						mass += float((body as Node).get("mass"))
	var actors_raw: Variant = stage.get("actors")
	if actors_raw is Dictionary:
		for slot: Variant in (actors_raw as Dictionary):
			var who: Variant = (actors_raw as Dictionary)[slot]
			if who is CharacterBody3D and is_instance_valid(who):
				if contains_point((who as CharacterBody3D).global_position, 0.2):
					mass += CREW_MASS
	return mass

func pull_brake() -> int:
	# B 键：释放 → 常用 → 紧急 → 释放（棘轮三档，见 cart_brake_rig.gd）
	if brake_rig == null:
		return 0
	var next: int = (int(brake_rig.get("notch")) + 1) % 3
	return apply_brake_notch(next)

func apply_brake_notch(value: int) -> int:
	if brake_rig == null:
		return 0
	var level: int = clampi(value, 0, 2)
	brake_rig.call("set_notch", level)
	auto_parking = false
	if level > 0:
		running = false
		motor_braking = false
		brake_reason = "player_brake"
	revision += 1
	return level

func release_brake() -> void:
	if brake_rig == null:
		return
	brake_rig.call("release")
	revision += 1

func brake_state() -> Dictionary:
	var out: Dictionary = {"notch": 0, "travel": 0.0, "shoe_force": 0.0,
		"brake_force": 0.0, "blocked": false, "drum_omega": 0.0}
	if brake_rig != null:
		out = brake_rig.call("state") as Dictionary
	out["force_at_rail"] = snappedf(brake_force(), 1.0)
	out["running"] = running
	out["motor_braking"] = motor_braking
	out["speed"] = snappedf(speed, 0.001)
	out["mass"] = snappedf(effective_mass(), 0.1)
	return out

func brake_force() -> float:
	if brake_rig == null:
		return 0.0
	return float(brake_rig.call("brake_force_at_rail"))

func _box(label: String, at: Vector3, dimensions: Vector3, camera_solid: bool = false) -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = dimensions
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = label
	collider.shape = shape
	collider.position = at
	add_child(collider)
	if camera_solid:
		var obstacle: AnimatableBody3D = AnimatableBody3D.new()
		obstacle.collision_layer = 4
		obstacle.collision_mask = 0
		obstacle.sync_to_physics = false
		var copy: CollisionShape3D = collider.duplicate() as CollisionShape3D
		obstacle.add_child(copy)
		add_child(obstacle)

func start() -> bool:
	if arrived or paused: return false
	if not route_clear and distance >= FAULT_STOP - 0.6: return false
	# 电机拉不动咬死的闸：发车前由控制器把棘轮松开（玩家在控制器上按 E）。
	if brake_rig != null:
		brake_rig.call("release")
	auto_parking = true
	motor_braking = false
	running = true
	revision += 1
	return true

# Why `start()` refused, so the caller can show the real reason instead of a
# generic "cannot depart" message.
func start_refusal() -> String:
	if arrived: return "已经抵达晶体矿区入口"
	if not route_clear and distance >= FAULT_STOP - 0.6:
		return "前方轨道断裂，矿车无法通过。先修复轨道并完成机械锁定。"
	return ""

# Handed back by the repair mission once the swing section is pinned. The motor
# only clears its governor; the physical alignment is the rail's own state, so a
# visual-only "repair" can never open the line.
func release_route() -> void:
	route_clear = true
	stopped_for_fault = false
	state = "线路已恢复"
	revision += 1

func brake(reason: String = "") -> void:
	# 调度 / 安全停车：断电 + 调速器电制动（有限 2.5 kN），不碰玩家手制动。
	running = false
	motor_braking = true
	if reason != "":
		brake_reason = reason
	revision += 1

func reset_run() -> void:
	running = false
	motor_braking = false
	auto_parking = true
	if brake_rig != null:
		brake_rig.call("release")
	arrived = false
	route_clear = false
	stopped_for_fault = false
	distance = 0.0
	target_distance = 0.0
	speed = 0.0
	mirror_speed = 0.0
	world_velocity = Vector3.ZERO
	world_acceleration = Vector3.ZERO
	transform = route_pose(0.0)
	previous_transform = transform
	state = "停靠待发"
	revision += 1
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	if paused: return
	clock += delta
	if network_client:
		_mirror_tick(delta)
		return
	previous_transform = global_transform
	var old_speed: float = speed
	var limit: float = LENGTH if route_clear else FAULT_STOP
	var remaining: float = limit - distance
	# 调速器的目标速度（线路限速 / 断轨前的减速曲线）。它不是"预设速度曲线"：
	# 这里只算出速度目标，真正实现它的是下面有限的力与合力积分——力不够就
	# 真的停不住，货重就真的多滑一段。
	var target: float = minf(CRUISE, sqrt(maxf(0.0, 2.0 * 0.58 * remaining))) if running else 0.0
	if remaining < 0.025: target = 0.0
	var mass: float = effective_mass()
	# 手制动机构先走自己的行程（机械），再给出本帧的真实闸瓦力。
	if brake_rig != null:
		brake_rig.call("tick", delta, speed)
	var f_brake: float = brake_force()
	var notch: int = int(brake_rig.get("notch")) if brake_rig != null else 0
	var slope: float = route_slope(distance)
	var along: float = 1.0 if speed > 0.0005 else 0.0
	var f_resistance: float = (CRR * mass * GRAV + DRAG_C * speed * speed) * along
	var f_grade: float = mass * GRAV * slope
	# 手制动一拉起就断牵引接触器：电机既不驱动也不做电制动，免得和闸抢。
	var f_traction: float = 0.0
	if notch == 0 and (running or motor_braking):
		var feed_forward: float = f_grade + f_resistance
		var feedback: float = KP_TRACTION * (target - speed)
		f_traction = clampf(feed_forward + feedback, -GOVERNOR_BRAKE_MAX, F_TRACTION_MAX)
	forces = {"traction": snappedf(f_traction, 0.1), "brake": snappedf(f_brake, 0.1),
		"resistance": snappedf(f_resistance, 0.1), "grade": snappedf(f_grade, 0.1),
		"mass": snappedf(mass, 0.1), "slope": snappedf(slope, 0.00001)}
	var f_net: float = f_traction - f_brake * along - f_resistance - f_grade
	var new_speed: float = speed + (f_net / mass) * delta
	# 静止判定：闸的静摩擦（或滚动阻力）足够就真的不动；矿车没有倒车挡，
	# 速度被夹在 0，不会出现"停住后反向弹一下"。
	var static_capacity: float = maxf(f_brake, CRR * mass * GRAV)
	if speed <= 0.02 and absf(f_traction - f_grade) <= static_capacity:
		new_speed = 0.0
	speed = maxf(0.0, new_speed)
	distance = minf(LENGTH, distance + (speed + old_speed) * 0.5 * delta)
	acceleration = (speed - old_speed) / delta
	# The bend event owns the warning state; the cart only asks it whether the
	# route is currently disturbing loose cargo.
	var disturbance: float = 0.0
	if bend_event != null and is_instance_valid(bend_event):
		disturbance = float(bend_event.call("disturbs_cargo"))
	event_active = disturbance > 0.5
	var next: Transform3D = route_pose(distance)
	var prior_velocity: Vector3 = world_velocity
	world_velocity = (next.origin - global_position) / delta
	world_acceleration = (world_velocity - prior_velocity) / delta
	angular_velocity_y = angle_difference(global_rotation.y, next.basis.get_euler().y) / delta
	global_transform = next
	if visual_node != null and is_instance_valid(visual_node):
		if event_active and stage != null and not bool(stage.get("reduced_effects")):
			var envelope: float = smoothstep(29.0, 32.0, distance) * (1.0 - smoothstep(42.0, 45.0, distance))
			visual_node.position.y = sin(clock * 10.0) * 0.007 * envelope
		else:
			visual_node.position.y = 0.0
	if route_clear and remaining < 0.06 and speed < 0.03:
		arrived = true
		running = false
		motor_braking = true
		stopped_for_fault = false
		state = "已到终点"
	elif not route_clear and remaining < 0.08 and speed < 0.035 and distance > 60.0:
		# The governor, not the player, ends this leg: the line ahead is severed.
		running = false
		motor_braking = true
		stopped_for_fault = true
		state = "前方断轨 · 安全停车"
	elif f_brake > 1.0 and speed > 0.05:
		state = "手制动 · 减速"
	elif notch > 0 and speed <= 0.05:
		state = "手制动 · 已停车"
	else:
		if route_clear: stopped_for_fault = false
		state = "加速" if acceleration > 0.01 else ("制动" if acceleration < -0.01 else ("行驶" if speed > 0.01 else "已停车"))
	# 调度/安全停车后自动落闸（弹簧蓄能式驻车）：玩家仍可按 B 松开。
	if auto_parking and distance > 1.0 and not running and speed < 0.05 \
			and brake_rig != null and int(brake_rig.get("notch")) == 0:
		brake_rig.call("set_notch", 1)
	for wheel: Node3D in wheels:
		wheel.rotate_z(-speed * delta / WHEEL_R)

func point_velocity(world_point: Vector3) -> Vector3:
	return world_velocity + Vector3.UP.cross(world_point - global_position) * angular_velocity_y

func contains_point(world_point: Vector3, margin: float = 0.0) -> bool:
	var local: Vector3 = to_local(world_point)
	return local.x > -3.4 - margin and local.x < 3.1 + margin and local.z > 0.87 - margin and local.z < 3.53 + margin and local.y > 1.65 and local.y < 3.8

# --- client mirror ---------------------------------------------------------

func _mirror_tick(delta: float) -> void:
	previous_transform = global_transform
	var before: Vector3 = global_position
	# Snapshots arrive at 20 Hz while frames run at 60+: close the gap at the
	# host's own speed instead of teleporting every snapshot. The deck therefore
	# remains a believable moving platform for the rider standing on it.
	var gap: float = target_distance - distance
	var catchup_speed: float = maxf(absf(mirror_speed), minf(absf(gap) * 4.0, 12.0))
	var limit: float = catchup_speed * delta + 0.004
	distance = clampf(distance + clampf(gap, -limit, limit), 0.0, LENGTH)
	var next: Transform3D = route_pose(distance)
	world_velocity = (next.origin - before) / maxf(delta, 0.0001)
	global_transform = next
	for wheel: Node3D in wheels:
		wheel.rotate_z(-mirror_speed * delta / WHEEL_R)

func apply_net_state(rows: Array) -> void:
	# [distance, speed, running, arrived, route_clear, stopped_for_fault,
	#  brake_reason, state]
	if rows.size() < 8:
		return
	target_distance = float(rows[0])
	mirror_speed = float(rows[1])
	running = bool(rows[2])
	arrived = bool(rows[3])
	route_clear = bool(rows[4])
	stopped_for_fault = bool(rows[5])
	brake_reason = str(rows[6])
	state = str(rows[7])
	if absf(target_distance - distance) > 6.0 and (target_distance < 0.5 or distance < 0.5):
		# Only snap on genuine reset / start-of-run; mid-run stalls catch up
		# smoothly via _mirror_tick instead of teleporting 6+ m through geometry.
		distance = target_distance
		global_transform = route_pose(distance)
		reset_physics_interpolation()

# Used by the 02->03 hand-off path: place the cart exactly at a distance without
# waiting for the mirror to crawl there.
func snap_to_distance(value: float) -> void:
	distance = clampf(value, 0.0, LENGTH)
	target_distance = distance
	global_transform = route_pose(distance)
	previous_transform = global_transform
	reset_physics_interpolation()
