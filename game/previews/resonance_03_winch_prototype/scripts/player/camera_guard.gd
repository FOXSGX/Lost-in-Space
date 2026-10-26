extends RefCounted

# Presentation-only third-person camera helper.
# Sweeps a small sphere from the player's head to the desired camera position so
# the view never ends up inside a rock wall or the winch frame.
# It never moves the actor and never changes any physics state.

var actor: CharacterBody3D
var sphere: SphereShape3D
var compressed: bool = false
var distance: float = 0.0
var max_step: float = 0.0
var _mask: int = 1

func setup(player: CharacterBody3D, world_mask: int = 1) -> void:
	actor = player
	_mask = world_mask
	sphere = SphereShape3D.new()
	sphere.radius = 0.26

func sweep(origin: Vector3, destination: Vector3) -> Vector3:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.motion = destination - origin
	query.margin = 0.04
	query.collision_mask = _mask
	query.exclude = [actor.get_rid()]
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	var cast: PackedFloat32Array = space.cast_motion(query)
	var fraction: float = 1.0
	if cast.size() > 0:
		fraction = cast[0]
	var result: Vector3 = origin + query.motion * maxf(0.0, fraction - 0.02)
	query.transform.origin = result
	query.motion = Vector3.ZERO
	if not space.intersect_shape(query, 1).is_empty():
		return origin
	return result

func clear(at: Vector3) -> bool:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.margin = 0.04
	query.collision_mask = _mask
	query.exclude = [actor.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func position_camera(target: Vector3, desired: Vector3, delta: float, snap: bool) -> Vector3:
	var camera: Camera3D = actor.get("camera") as Camera3D
	if camera == null:
		return desired
	var safe: Vector3 = sweep(target, desired)
	var reach: float = safe.distance_to(target)
	compressed = reach < 1.9
	var current: Vector3 = camera.global_position
	var next: Vector3
	if snap:
		next = safe
	else:
		next = current.lerp(safe, 1.0 - exp(-13.0 * delta))
		# Speed limit keeps the camera from snapping through a wall in one frame.
		next = current.move_toward(next, 14.0 * delta)
	if not snap and clear(current) and current.distance_to(next) > 0.001:
		next = sweep(current, next)
	if not clear(next):
		next = current
	distance = next.distance_to(target)
	if not snap:
		max_step = maxf(max_step, current.distance_to(next))
	return next
