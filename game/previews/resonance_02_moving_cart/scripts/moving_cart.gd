extends AnimatableBody3D

# Host-owned path motor. +X is the approved cart's longitudinal axis.
# Characters remain world-space CharacterBody3D and use native platform support.
const LENGTH: float = 90.0
const CRUISE: float = 1.55
const DECK_Y: float = 1.9546444
var distance: float = 0.0
var speed: float = 0.0
var acceleration: float = 0.0
var state: String = "停靠待发"
var running: bool = false
var arrived: bool = false
var event_active: bool = false
var bend_event: Node3D
var clock: float = 0.0
var previous_transform: Transform3D = Transform3D.IDENTITY
var world_velocity: Vector3 = Vector3.ZERO
var world_acceleration: Vector3 = Vector3.ZERO
var angular_velocity_y: float = 0.0
var revision: int = 0
var wheels: Array[Node3D] = []
var stage: Node3D
var paused: bool = false

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
	_box("Ring", Vector3(-2.5, 3.12, 2.2), Vector3(0.30, 2.5, 2.65), true)
	_box("Cab", Vector3(3.6, 1.6, 2.2), Vector3(1.3, 1.8, 2.5), true)
	for z: float in [0.87, 3.53]:
		# The near-side boarding gate stays open, matching the existing stairs.
		for span: Vector2 in ([Vector2(-1.7, 0.52), Vector2(1.48, 2.88)] if z < 1.0 else [Vector2(-2.1, 2.88)]):
			_box("Rail", Vector3((span.x + span.y) * 0.5, 2.53, z), Vector3(span.y - span.x, 1.17, 0.09))
	_box("RearStop", Vector3(-3.32, 2.25, 2.2), Vector3(0.10, 0.62, 2.65))
	previous_transform = transform

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
	running = true
	revision += 1
	return true

func brake() -> void:
	running = false
	revision += 1

func reset_run() -> void:
	running = false
	arrived = false
	distance = 0.0
	speed = 0.0
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
	previous_transform = global_transform
	var old_speed: float = speed
	var remaining: float = LENGTH - distance
	var target: float = minf(CRUISE, sqrt(maxf(0.0, 2.0 * 0.58 * remaining))) if running else 0.0
	# A natural final deceleration has a short settling zone instead of a hard snap.
	if remaining < 0.025: target = 0.0
	speed = move_toward(speed, target, (0.62 if target > speed else 1.02) * delta)
	distance = minf(LENGTH, distance + (speed + old_speed) * 0.5 * delta)
	acceleration = (speed - old_speed) / delta
	# The bend event owns the warning state; the cart only asks it whether the
	# route is currently disturbing loose cargo.
	var disturbance: float = 0.0
	if bend_event != null and is_instance_valid(bend_event):
		disturbance = float(bend_event.call("disturbs_cargo"))
	event_active = disturbance > 0.5
	var next: Transform3D = route_pose(distance)
	if event_active and stage != null and not bool(stage.get("reduced_effects")):
		var envelope: float = smoothstep(29.0, 32.0, distance) * (1.0 - smoothstep(42.0, 45.0, distance))
		next.origin.y += sin(clock * 10.0) * 0.007 * envelope
	var prior_velocity: Vector3 = world_velocity
	world_velocity = (next.origin - global_position) / delta
	world_acceleration = (world_velocity - prior_velocity) / delta
	angular_velocity_y = angle_difference(global_rotation.y, next.basis.get_euler().y) / delta
	global_transform = next
	if remaining < 0.04 and speed < 0.025:
		arrived = true
		running = false
		state = "已到终点"
	else:
		state = "加速" if acceleration > 0.01 else ("制动" if acceleration < -0.01 else ("行驶" if speed > 0.01 else "已停车"))
	for wheel: Node3D in wheels:
		wheel.rotate_z(-speed * delta / 0.795)

func point_velocity(world_point: Vector3) -> Vector3:
	return world_velocity + Vector3.UP.cross(world_point - global_position) * angular_velocity_y

func contains_point(world_point: Vector3, margin: float = 0.0) -> bool:
	var local: Vector3 = to_local(world_point)
	return local.x > -3.4 - margin and local.x < 3.1 + margin and local.z > 0.87 - margin and local.z < 3.53 + margin and local.y > 1.65 and local.y < 3.8
