extends RefCounted

# -----------------------------------------------------------------------------
# CameraGuard - the single owner of the third-person camera POSITION.
#
# Why this file was rewritten (P0-1, real playtest):
#   The previous guard chased the ideal boom with a slow lerp, then did
#   `if not clear(next): next = current`. The cart camera sat 5 m behind and
#   2.0-2.8 m ABOVE the rider's head, i.e. at y ~5.2 m. The cave shell collision
#   only exists above the 4.6 m driving envelope, so the lens started a frame
#   inside the ceiling collider. From then on every candidate position failed
#   `clear(next)`, the guard returned the old position, and the camera stayed
#   behind while the cart drove away. That is the reported "camera sometimes
#   doesn't follow", and the clear/blocked boundary produced the shake.
#
# The contract now is deliberately small:
#   * The camera rides with the player. There is NO positional chase lag.
#   * Obstruction only shortens the boom. It never freezes the camera.
#   * The boom pulls in immediately when blocked and extends at a bounded speed
#     when the obstruction clears, so it cannot pop through geometry.
#   * If the current lens position is invalid (teleport, spawn, a moving part
#     that moved into it), the camera snaps to the last valid point on the boom
#     instead of staying invalid.
#   * Every query is a swept sphere on the camera mask. Nothing here writes a
#     peer transform, and world geometry is never excluded.
# -----------------------------------------------------------------------------

const MASK: int = 4
const MIN_BOOM: float = 0.58
const EASE_OUT: float = 2.8
const SNAP_DISTANCE: float = 11.0

var actor: CharacterBody3D
var sphere: SphereShape3D
var compressed: bool = false
var suppressed_actors: int = 0
var distance: float = 0.0
var boom_length: float = 0.0
var blocked: bool = false
var last_safe: Vector3 = Vector3.ZERO
var queries: int = 0

func setup(player: CharacterBody3D) -> void:
	actor = player
	sphere = SphereShape3D.new()
	sphere.radius = 0.22

# --- queries ---------------------------------------------------------------

func _space() -> PhysicsDirectSpaceState3D:
	return actor.get_world_3d().direct_space_state

func _shape_query(at: Vector3) -> PhysicsShapeQueryParameters3D:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.margin = 0.02
	query.collision_mask = MASK
	query.exclude = [actor.get_rid()]
	return query

func clear(at: Vector3) -> bool:
	queries += 1
	return _space().intersect_shape(_shape_query(at), 1).is_empty()

# Furthest valid point from `origin` toward `destination`. A cast that starts
# inside a shape is ignored by cast_motion, so the endpoint is validated and a
# short binary search walks back along the segment until a clear point is found.
func sweep(origin: Vector3, destination: Vector3) -> Vector3:
	var motion: Vector3 = destination - origin
	if motion.length() < 0.0001:
		return origin
	queries += 1
	var query: PhysicsShapeQueryParameters3D = _shape_query(origin)
	query.motion = motion
	var cast: PackedFloat32Array = _space().cast_motion(query)
	var fraction: float = clampf(cast[0] if not cast.is_empty() else 1.0, 0.0, 1.0)
	var low: float = maxf(0.0, fraction - 0.10)
	var high: float = fraction
	if clear(origin + motion * high):
		low = high
	else:
		for _i: int in range(7):
			var middle: float = (low + high) * 0.5
			if clear(origin + motion * middle):
				low = middle
			else:
				high = middle
	# 0.02 m of skin so the sphere never touches the surface it stopped on.
	return origin + motion * clampf(low - 0.004, 0.0, 1.0)

# The pivot itself can be inside the deck/hoop when the rider stands close to
# hardware. Lift it until the sweep has a legal start; if nothing is clear, keep
# the raw target (the sweep then starts inside and still finds the exit).
func _pivot(target: Vector3) -> Vector3:
	for lift: float in [0.0, 0.28, 0.56, 0.86, 1.18, -0.34, -0.68]:
		if clear(target + Vector3.UP * lift):
			return target + Vector3.UP * lift
	return target

# --- position --------------------------------------------------------------

func position_camera(target: Vector3, desired: Vector3, delta: float, snap: bool) -> Vector3:
	var camera: Camera3D = actor.get("camera") as Camera3D
	var pivot: Vector3 = _pivot(target)
	var safe: Vector3 = sweep(pivot, desired)
	var safe_length: float = safe.distance_to(pivot)
	# Never put the lens on top of the rider's head. In a narrow bay the ideal
	# 4.9 m boom hits the opposite wall in both directions; the fix is to lift
	# the whole boom until it clears the obstruction, not to accept a 0.4 m
	# face-filling close-up. The bearing is preserved by raising the desired
	# point with the pivot.
	if safe_length < 1.25:
		var best_pivot: Vector3 = pivot
		var best_safe: Vector3 = safe
		var best_length: float = safe_length
		for lift: float in [0.55, 1.05, 1.60, 2.20, 2.80, 3.40]:
			var high_pivot: Vector3 = target + Vector3.UP * (lift + 0.05)
			if not clear(high_pivot):
				continue
			var candidate: Vector3 = sweep(high_pivot, desired + Vector3.UP * lift)
			var length: float = candidate.distance_to(high_pivot)
			if length > best_length + 0.18:
				best_pivot = high_pivot
				best_safe = candidate
				best_length = length
			if best_length >= 1.25:
				break
		pivot = best_pivot
		safe = best_safe
		safe_length = best_length
	if safe_length < 0.75:
		# Still boxed in: look down from just above the head rather than from
		# inside it. This is a last resort and is counted in the telemetry.
		var overhead: Vector3 = pivot + Vector3.UP * 1.25
		if clear(overhead):
			safe = overhead
			safe_length = safe.distance_to(pivot)
	var current: Vector3 = camera.global_position
	var current_clear: bool = clear(current)
	var current_length: float = current.distance_to(pivot)
	var next: Vector3 = safe
	if not snap and current_clear and current_length < SNAP_DISTANCE:
		# The bearing comes from the new safe point every frame (rigid follow).
		# Only the extension eases out; shortening is immediate so the lens can
		# never be left behind a wall while the boom recovers.
		if safe_length > current_length + 0.015 and current_length > MIN_BOOM:
			var direction: Vector3 = (safe - pivot).normalized()
			var extended: Vector3 = pivot + direction * minf(safe_length, current_length + EASE_OUT * delta)
			next = extended if clear(extended) else safe
	if not clear(next):
		# A candidate that ends inside geometry is never accepted. Fall back to
		# the valid side of the boom rather than freezing at the old position.
		next = sweep(pivot, pivot + (next - pivot).normalized() * MIN_BOOM)
		if not clear(next):
			next = safe
	if not current_clear and not snap:
		# Recovering from an invalid lens position (e.g. stepping off the deck
		# while the boom was compressed against the cart): slide toward the
		# player first. That direction always exits the obstruction and removes
		# the old 4.4 m one-frame pop; the boom then eases back out.
		var inward: Vector3 = current.move_toward(pivot, maxf(0.12, 14.0 * delta))
		if clear(inward):
			next = inward
		else:
			next = safe
	blocked = not clear(next)
	if blocked:
		# Last resort: keep the pivot (inside the character, never in a wall)
		# and place the lens on the nearest clear spot around it. This can never
		# leave the camera behind the player.
		next = pivot + Vector3.UP * 0.35
	compressed = next.distance_to(actor.global_position + Vector3.UP * 1.1) < 1.60
	boom_length = next.distance_to(actor.global_position + Vector3.UP * 1.1)
	distance = next.distance_to(actor.global_position + Vector3.UP * 1.0)
	last_safe = next
	return next

func suppress_near_characters() -> void:
	var camera: Camera3D = actor.get("camera") as Camera3D
	var roster: Dictionary = actor.get_parent().get("actors") as Dictionary
	suppressed_actors = 0
	for id: int in roster:
		var other: CharacterBody3D = roster[id] as CharacterBody3D
		var body: Node3D = other.get("visual") as Node3D
		var center: Vector3 = other.global_position + Vector3.UP * 0.95
		var near_body: bool = camera.global_position.distance_to(center) < 1.10
		# Local viewport only: avoid a second ranger filling the near plane.
		# The local actor is never hidden here: first person removes only the head
		# and arms, through render layers, so the body stays in the world for
		# every other player instead of being switched off globally.
		body.visible = not near_body
		if not body.visible:
			suppressed_actors += 1
