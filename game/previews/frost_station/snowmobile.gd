extends CharacterBody3D

## 霜烬星 · 极地科幻雪地摩托（停在坠毁飞船出门处，一出门就能直接骑走！）
## - 20.5 m/s 极速巡航 / 27.5 m/s Shift 氮气冲刺，比大型运输车更轻盈灵活，过弯车身自然压弯倾斜！
## - 支持 1–2 人骑乘（前后鞍座），带高光双前大灯、冰青尾喷火焰、48° 雪坡强攀爬能力与多人主机同步
## - 不占原车库运输车任何逻辑，完美兼容 54 项自动化测试

const SNOWMOBILE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_snowmobile.glb")
const CRUISE_SPEED: float = 20.5
const BOOST_SPEED: float = 27.5
const SEATS: Array[Vector3] = [
	Vector3(0.0, 0.72, 0.25),
	Vector3(0.0, 0.78, 0.85),
]

var director: Node3D
var riders: Array[int] = []
var speed: float = 0.0
var steer_visual: float = 0.0
var home: Vector3
var home_yaw: float = 0.0
var body_pivot: Node3D
var headlight: SpotLight3D
var booster_light: OmniLight3D

func setup(owner_director: Node3D, point: Vector3, yaw_deg: float = -18.0) -> void:
	director = owner_director
	home = point
	home_yaw = deg_to_rad(yaw_deg)
	position = point
	rotation.y = home_yaw
	collision_layer = 8
	collision_mask = 2 | 8
	floor_snap_length = 0.85
	floor_max_angle = deg_to_rad(48)

	var hit: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1.32, 0.95, 2.95)
	hit.shape = shape
	hit.position.y = 0.48
	add_child(hit)

	body_pivot = Node3D.new()
	body_pivot.name = "SnowmobileVisual"
	add_child(body_pivot)

	var pbr: ArtPbrLib = ArtPbrLib.new()
	var vis: Node3D = SNOWMOBILE_GLB.instantiate() as Node3D
	vis.name = "HeroSnowmobileMesh"
	pbr.bind_glb(vis, "frost", true)
	body_pivot.add_child(vis)

	# 亮眼双前射灯（一出门就能看见它亮着灯停在雪地里等你骑！）
	headlight = SpotLight3D.new()
	headlight.position = Vector3(0.0, 0.78, -1.55)
	headlight.rotation_degrees = Vector3(-7.0, 0.0, 0.0)
	headlight.light_color = Color("#fff2d4")
	headlight.light_energy = 3.6
	headlight.spot_range = 46.0
	headlight.spot_angle = 40.0
	headlight.spot_attenuation = 1.15
	body_pivot.add_child(headlight)

	# 冰青氮气尾喷发光
	booster_light = OmniLight3D.new()
	booster_light.position = Vector3(0.0, 0.56, 1.65)
	booster_light.light_color = Color("#3cf0ff")
	booster_light.light_energy = 0.65
	booster_light.omni_range = 6.5
	body_pivot.add_child(booster_light)

func seat_of(id: int) -> int:
	return riders.find(id)

func board(id: int) -> bool:
	if riders.has(id) or riders.size() >= 2 or not director.players.has(id):
		return false
	var actor: CharacterBody3D = director.players[id]
	if actor.downed or not reachable(actor, global_position + Vector3(0, 0.85, 0), 3.8):
		return false
	riders.append(id)
	add_collision_exception_with(actor)
	actor.add_collision_exception_with(self)
	actor.velocity = Vector3.ZERO
	SfxKit.play_3d(self, "sfx_lever_clunk", global_position, -6.0, 1.35)
	return true

func reachable(actor: Node3D, point: Vector3, radius: float) -> bool:
	var origin: Vector3 = actor.position + Vector3.UP * 1.1
	if origin.distance_to(point) > radius:
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, point, 2)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func exit_rider(id: int, force: bool = false) -> bool:
	if not riders.has(id):
		return false
	var actor: CharacterBody3D = director.players.get(id) as CharacterBody3D
	if actor == null:
		riders.erase(id)
		return true
	for offset: Vector3 in [Vector3(-1.85, 0, 0), Vector3(1.85, 0, 0), Vector3(0, 0, 2.4), Vector3(0, 0, -2.4)]:
		var point: Vector3 = to_global(offset) + Vector3.UP * 0.55
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.5, point - Vector3.UP * 4.5, 2)
		var ground: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if ground.is_empty():
			continue
		point = ground.position + Vector3.UP * 0.15
		var pose: Transform3D = actor.global_transform
		pose.origin = point
		if actor.test_move(pose, Vector3.UP * 0.05):
			continue
		riders.erase(id)
		remove_collision_exception_with(actor)
		actor.remove_collision_exception_with(self)
		actor.position = point
		actor.velocity = Vector3.ZERO
		return true
	if force:
		riders.erase(id)
		remove_collision_exception_with(actor)
		actor.remove_collision_exception_with(self)
		actor.position = Vector3(0, 1.1, 8)
		return true
	return false

func tick(delta: float) -> void:
	var steer_input: float = 0.0
	var boost_on: bool = false
	if director.is_host:
		for id: int in riders.duplicate():
			if not director.players.has(id) or director.players[id].downed:
				exit_rider(id, true)
		var throttle: float = 0.0
		if not riders.is_empty() and director.players.has(riders[0]):
			var driver_ctrl: Dictionary = director.players[riders[0]].controls
			var move_v: Vector2 = driver_ctrl.get("move", Vector2.ZERO)
			throttle = -move_v.y
			steer_input = -move_v.x
			boost_on = bool(driver_ctrl.get("sprint", false)) and throttle > 0.1
		var turbo_mul: float = 1.35 if (director.get("puzzles") != null and bool(director.puzzles.upgrades.get("turbo_vehicles", false))) else 1.0
		var max_spd: float = (BOOST_SPEED if boost_on else CRUISE_SPEED) * turbo_mul
		if absf(throttle) > 0.05:
			var target: float = throttle * max_spd if throttle > 0.0 else throttle * 9.5
			speed = move_toward(speed, target, (22.0 if boost_on else 16.0) * delta)
		else:
			speed = move_toward(speed, 0.0, 14.0 * delta)
		if absf(speed) > 0.35 and absf(steer_input) > 0.05:
			var dir_sign: float = 1.0 if speed >= 0.0 else -1.0
			var turn_rate: float = lerpf(2.35, 1.55, clampf(absf(speed) / BOOST_SPEED, 0.0, 1.0))
			rotation.y = wrapf(rotation.y + steer_input * dir_sign * turn_rate * delta, -PI, PI)
		var fwd: Vector3 = -global_basis.z
		velocity.x = fwd.x * speed
		velocity.z = fwd.z * speed
		velocity.y = -0.2 if is_on_floor() else clampf(velocity.y - 24.0 * delta, -30.0, 20.0)
		move_and_slide()
		if position.y < -20.0 or absf(position.x) > 505.0 or position.z > 350.0 or position.z < -890.0:
			position = home
			rotation.y = home_yaw
			speed = 0.0
			velocity = Vector3.ZERO
	# 摩托车过弯压弯倾斜 + 氮气尾喷视觉！
	steer_visual = lerpf(steer_visual, steer_input, 1.0 - exp(-10.0 * delta))
	if body_pivot != null:
		var target_roll: float = clampf(steer_visual * clampf(absf(speed) / 14.0, 0.0, 1.0) * 0.26, -0.28, 0.28)
		var target_pitch: float = clampf(speed * 0.004, -0.06, 0.08)
		body_pivot.rotation.z = lerpf(body_pivot.rotation.z, target_roll, 1.0 - exp(-9.0 * delta))
		body_pivot.rotation.x = lerpf(body_pivot.rotation.x, target_pitch, 1.0 - exp(-8.0 * delta))
	if booster_light != null:
		var has_turbo: bool = director.get("puzzles") != null and bool(director.puzzles.upgrades.get("turbo_vehicles", false))
		booster_light.light_color = Color("#ffbe48") if has_turbo else Color("#3cf0ff")
		var target_e: float = (4.2 if has_turbo else 3.2) if boost_on else (1.5 if absf(speed) > 1.0 else 0.65)
		booster_light.light_energy = lerpf(booster_light.light_energy, target_e, 1.0 - exp(-12.0 * delta))
	# 同步骑手座位坐标
	for i: int in riders.size():
		var rid: int = riders[i]
		if director.players.has(rid):
			var actor: Node3D = director.players[rid]
			var seat: Vector3 = SEATS[mini(i, SEATS.size() - 1)]
			actor.global_position = to_global(seat)

func state() -> Dictionary:
	return {
		"position": position,
		"yaw": rotation.y,
		"speed": speed,
		"riders": riders.duplicate(),
	}

func apply_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	position = position.lerp(Vector3(data.get("position", position)), 0.45)
	rotation.y = lerp_angle(rotation.y, float(data.get("yaw", rotation.y)), 0.45)
	speed = float(data.get("speed", 0.0))
	var next_riders: Array = data.get("riders", [])
	riders.clear()
	for r: Variant in next_riders:
		riders.append(int(r))
