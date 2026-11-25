extends CharacterBody3D

## 霜烬星 · 极地探险运输车（大盆地升级版）
## - 16.5 m/s 巡航 / 21.5 m/s Shift 涡轮增压，支持 46° 极地雪坡爬升与平滑悬架姿态倾角
## - 双前射灯（穿透极地吹雪）+ 工业防滚架 + 12 格物理货斗 + 4 人乘员位
## - 主机权威同步，掉出盆地自动回车库且保留全部货物

const ROVER_GLB: PackedScene = preload("res://assets/models/rebuild/hero_polar_rover.glb")
const CRATE_GLB: PackedScene = preload("res://assets/models/rebuild/hero_cargo_crate.glb")
const MAX_CARGO: int = 12
const CRUISE_SPEED: float = 16.5
const BOOST_SPEED: float = 21.5
const SEATS: Array[Vector3] = [
	Vector3(-0.65, 0.65, -0.75),
	Vector3(0.65, 0.65, -0.75),
	Vector3(-0.65, 0.65, 0.55),
	Vector3(0.65, 0.65, 0.55),
]

var director: Node3D
var riders: Array[int] = []
var cargo: Array = []
var speed: float = 0.0
var steer_visual: float = 0.0
var home: Vector3
var body_pivot: Node3D
var wheels: Array[MeshInstance3D] = []
var front_wheel_pivots: Array[Node3D] = []
var cargo_views: Array[Node3D] = []
var headlights: Array[SpotLight3D] = []
var booster_light: OmniLight3D

func setup(owner_director: Node3D, point: Vector3) -> void:
	director = owner_director
	home = point
	position = point
	collision_layer = 8
	collision_mask = 2 | 8
	floor_snap_length = 0.85
	floor_max_angle = deg_to_rad(46)

	var hit: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(2.6, 1.15, 4.5)
	hit.shape = shape
	hit.position.y = 0.28
	add_child(hit)

	# 悬架视觉根节点：装配 Blender 4.5 锻造的英雄极地探险车 GLB（奶油装甲车头 + 工业橙牛栏杠 + 防滚架）
	body_pivot = Node3D.new()
	body_pivot.name = "ChassisVisual"
	add_child(body_pivot)

	var pbr: ArtPbrLib = ArtPbrLib.new()
	var rover_vis: Node3D = ROVER_GLB.instantiate() as Node3D
	rover_vis.name = "HeroPolarRoverMesh"
	pbr.bind_glb(rover_vis, "frost", true)
	body_pivot.add_child(rover_vis)

	# 双前高光射灯（对齐车顶双灯罩，穿透极地吹雪）
	for x: float in [-0.64, 0.64]:
		var spot: SpotLight3D = SpotLight3D.new()
		spot.position = Vector3(x, 2.02, -1.25)
		spot.rotation_degrees = Vector3(-9.0, 0.0, 0.0)
		spot.light_color = Color("#fff1d6")
		spot.light_energy = 3.2
		spot.spot_range = 52.0
		spot.spot_angle = 38.0
		spot.spot_attenuation = 1.15
		body_pivot.add_child(spot)
		headlights.append(spot)

	# 涡轮加速尾喷光
	booster_light = OmniLight3D.new()
	booster_light.position = Vector3(0.0, 0.42, 2.45)
	booster_light.light_color = Color("#3ae0ff")
	booster_light.light_energy = 0.0
	booster_light.omni_range = 7.5
	body_pivot.add_child(booster_light)

	# 四只宽胎雪地轮（带轮毂盖，前轮带转向枢轴）
	var tire_mat: Material = pbr.build_palette("frost", false)["M_Rubber"] as Material
	var rim_mat: Material = pbr.build_palette("frost", false)["M_PaintOrange"] as Material
	for x: float in [-1.36, 1.36]:
		for z: float in [-1.42, 1.42]:
			var pivot: Node3D = Node3D.new()
			pivot.position = Vector3(x, -0.10, z)
			add_child(pivot)
			var wheel: MeshInstance3D = MeshInstance3D.new()
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = 0.48
			cyl.bottom_radius = 0.48
			cyl.height = 0.50
			cyl.radial_segments = 16
			wheel.mesh = cyl
			wheel.rotation_degrees.z = 90.0
			wheel.material_override = tire_mat
			var hub: MeshInstance3D = MeshInstance3D.new()
			var hc: CylinderMesh = CylinderMesh.new()
			hc.top_radius = 0.24
			hc.bottom_radius = 0.24
			hc.height = 0.53
			hc.radial_segments = 10
			hub.mesh = hc
			hub.material_override = rim_mat
			wheel.add_child(hub)
			pivot.add_child(wheel)
			wheels.append(wheel)
			if z < 0.0:
				front_wheel_pivots.append(pivot)

	# 12 格英雄物资箱货斗视觉位
	for i: int in MAX_CARGO:
		var col: int = i % 2
		var row: int = (i / 2) % 3
		var layer: int = i / 6
		var box_vis: Node3D = CRATE_GLB.instantiate() as Node3D
		box_vis.scale = Vector3.ONE * 0.68
		box_vis.position = Vector3((col - 0.5) * 0.92, 0.66 + float(layer) * 0.46, 0.60 + float(row) * 0.58)
		pbr.bind_glb(box_vis, "frost", true)
		box_vis.visible = false
		body_pivot.add_child(box_vis)
		cargo_views.append(box_vis)

func part(point: Vector3, size_value: Vector3, tint: Color, metallic: float = 0.25, rough: float = 0.55, emission: float = 0.0) -> MeshInstance3D:
	var view: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size_value
	view.mesh = mesh
	view.position = point
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.metallic = metallic
	mat.roughness = rough
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = emission
	view.material_override = mat
	body_pivot.add_child(view)
	return view

func seat_of(id: int) -> int:
	return riders.find(id)

func board(id: int) -> bool:
	if riders.has(id) or riders.size() >= 4 or not director.players.has(id):
		return false
	var actor: CharacterBody3D = director.players[id]
	if actor.downed or not reachable(actor, global_position + Vector3(0, 1, 0), 4.8):
		return false
	riders.append(id)
	add_collision_exception_with(actor)
	actor.add_collision_exception_with(self)
	actor.velocity = Vector3.ZERO
	return true

func reachable(actor: Node3D, point: Vector3, radius: float) -> bool:
	var origin: Vector3 = actor.position + Vector3.UP * 1.2
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
	for offset: Vector3 in [Vector3(-3, 0, 0), Vector3(3, 0, 0), Vector3(0, 0, 3.6), Vector3(0, 0, -3.6)]:
		var point: Vector3 = to_global(offset) + Vector3.UP * 0.6
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
	var accel_delta: float = 0.0
	if director.is_host:
		for id: int in riders.duplicate():
			if not director.players.has(id) or director.players[id].downed:
				exit_rider(id, true)
		var controls: Dictionary = director.players[riders[0]].controls if not riders.is_empty() else {}
		var move: Vector2 = controls.get("move", Vector2.ZERO)
		var boosting: bool = bool(controls.get("sprint", false))
		var handbrake: bool = bool(controls.get("jump", false))
		steer_input = -move.x
		var max_spd: float = BOOST_SPEED if boosting else CRUISE_SPEED
		var target: float = 0.0 if handbrake else (-move.y * max_spd)
		var accel_rate: float = 18.0 if handbrake else (11.5 if absf(target) > absf(speed) else 14.0)
		var prev_speed: float = speed
		speed = move_toward(speed, target, delta * accel_rate)
		accel_delta = (speed - prev_speed) / maxf(delta, 0.001)
		var turn_factor: float = minf(absf(speed) / 2.2, 1.0)
		var turn_rate: float = 1.25 if absf(speed) < 10.0 else 0.92
		var next: Transform3D = global_transform.rotated_local(Vector3.UP, steer_input * signf(speed) * delta * turn_rate * turn_factor)
		if not test_move(next, Vector3.UP * 0.01):
			global_transform = next
		var forward: Vector3 = -global_basis.z
		velocity.x = forward.x * speed
		velocity.z = forward.z * speed
		velocity.y = maxf(velocity.y - 26.0 * delta, -34.0)

		# 低坎平滑越障，保持真实爬坡与障碍阻挡
		var motion: Vector3 = Vector3(velocity.x, 0, velocity.z) * delta
		var contact: KinematicCollision3D = KinematicCollision3D.new()
		if is_on_floor() and motion.length() > 0.001 and test_move(global_transform, motion, contact):
			var probe: Vector3 = contact.get_position() + motion.normalized() * 0.28
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 0.75, probe - Vector3.UP * 0.75, 2)
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				var rise: float = (hit.position as Vector3).y - (position.y - 0.3) + 0.03
				if rise > 0.04 and rise <= 0.48 and not test_move(global_transform, Vector3.UP * rise) and not test_move(global_transform.translated(Vector3.UP * rise), motion):
					position.y += rise
		if is_on_floor() and motion.length() > 0.001 and test_move(global_transform, motion):
			for side: float in [-1, 0, 1]:
				var probe: Vector3 = position + motion.normalized() * 2.5 + global_basis.x * side * 1.05
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 0.55, probe - Vector3.UP * 0.55, 2)
				var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
				if hit.is_empty():
					continue
				var rise: float = (hit.position as Vector3).y - (position.y - 0.3) + 0.02
				if rise > 0.04 and rise <= 0.48 and not test_move(global_transform, Vector3.UP * rise) and not test_move(global_transform.translated(Vector3.UP * rise), motion):
					position.y += rise
					break
		move_and_slide()
		if get_slide_collision_count() > 0 and Vector2(velocity.x, velocity.z).length() < absf(speed) * 0.28:
			speed *= 0.55
		# 覆盖完整 720×920m 极地盆地边界
		if position.y < -22.0 or absf(position.x) > 355.0 or position.z > 215.0 or position.z < -655.0:
			position = home
			velocity = Vector3.ZERO
			speed = 0.0

	# 悬架坡度与加减速俯仰/侧倾视觉反馈
	if body_pivot != null:
		var target_pitch: float = clampf(accel_delta * 0.004, -0.06, 0.06)
		var target_roll: float = clampf(steer_input * speed * 0.006, -0.09, 0.09)
		if is_on_floor():
			var fn: Vector3 = get_floor_normal()
			var local_n: Vector3 = global_basis.inverse() * fn
			target_pitch += clampf(-local_n.z * 0.65, -0.35, 0.35)
			target_roll += clampf(local_n.x * 0.65, -0.35, 0.35)
		body_pivot.rotation.x = lerpf(body_pivot.rotation.x, target_pitch, clampf(delta * 8.0, 0.0, 1.0))
		body_pivot.rotation.z = lerpf(body_pivot.rotation.z, target_roll, clampf(delta * 8.0, 0.0, 1.0))

	steer_visual = lerpf(steer_visual, steer_input * 0.42, clampf(delta * 10.0, 0.0, 1.0))
	for fp: Node3D in front_wheel_pivots:
		fp.rotation.y = steer_visual
	for wheel: MeshInstance3D in wheels:
		wheel.rotation.x -= speed * delta * 1.8
	for spot: SpotLight3D in headlights:
		spot.light_energy = 3.2 if not riders.is_empty() else 0.9
	if booster_light != null:
		booster_light.light_energy = 3.2 if absf(speed) > CRUISE_SPEED + 0.5 else 0.0

	for i: int in riders.size():
		var actor: Node3D = director.players.get(riders[i]) as Node3D
		if actor != null:
			actor.position = to_global(SEATS[mini(i, 3)])
	for i: int in cargo_views.size():
		cargo_views[i].visible = i < cargo.size()

func load_or_unload(id: int) -> void:
	var actor: Node3D = director.players[id]
	var point: Vector3 = to_global(Vector3(0, 1, 2.8))
	if not reachable(actor, point, 3.5) or absf(speed) > 0.8:
		return
	var selected: Dictionary = director._items.selected(id)
	if not selected.is_empty() and not director._items.ensure_bag(id).equipment_active:
		if cargo.size() >= MAX_CARGO:
			director.tell(id, "货斗已满（%d件）" % MAX_CARGO)
			return
		cargo.append(director._items.take_selected(id).duplicate(true))
		director.tell(id, "物件已放入运输车货斗（%d/%d）· 空手 E 卸下一件" % [cargo.size(), MAX_CARGO])
	elif not cargo.is_empty():
		var item: Dictionary = cargo[-1]
		if not director._items.add_item(id, item.kind, -1, item, true):
			director.tell(id, "手持栏已满 · 先腾出一格")
			return
		cargo.pop_back()
		director.tell(id, "已从货斗取下一件物品")
	director._items.publish()

func state() -> Dictionary:
	return {"position": position, "rotation": rotation, "speed": speed, "riders": riders.duplicate(), "cargo": cargo.duplicate(true)}

func apply_state(data: Dictionary) -> void:
	position = data.get("position", home)
	rotation = data.get("rotation", Vector3.ZERO)
	speed = float(data.get("speed", 0))
	riders.assign(data.get("riders", []))
	cargo = data.get("cargo", []).duplicate(true)
