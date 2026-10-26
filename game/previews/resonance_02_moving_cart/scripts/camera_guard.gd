extends RefCounted

# Presentation only. Never changes a peer transform or excludes world geometry.
var actor: CharacterBody3D
var sphere: SphereShape3D
var compressed: bool = false
var suppressed_actors: int = 0
var distance: float = 0.0
var previous: Vector3
var max_step: float = 0.0

func setup(player: CharacterBody3D) -> void:
    actor = player
    sphere = SphereShape3D.new()
    sphere.radius = 0.24

func sweep(origin: Vector3, destination: Vector3) -> Vector3:
    var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
    query.shape = sphere
    query.transform = Transform3D(Basis.IDENTITY, origin)
    query.motion = destination - origin
    query.margin = 0.035
    query.collision_mask = 4
    query.exclude = [actor.get_rid()]
    var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
    var cast: PackedFloat32Array = space.cast_motion(query)
    var fraction: float = cast[0] if not cast.is_empty() else 1.0
    var result: Vector3 = origin + query.motion * maxf(0.0, fraction - 0.015)
    query.transform.origin = result
    query.motion = Vector3.ZERO
    # cast_motion ignores shapes already overlapping its start; validate the end.
    if not space.intersect_shape(query, 1).is_empty():
        return origin
    return result

func clear(at: Vector3) -> bool:
    var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
    query.shape = sphere
    query.transform = Transform3D(Basis.IDENTITY, at)
    query.margin = 0.035
    query.collision_mask = 4
    return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func position_camera(target: Vector3, desired: Vector3, delta: float, snap: bool) -> Vector3:
    var camera: Camera3D = actor.get("camera") as Camera3D
    var pivot_origin: Vector3 = target
    for lift: float in [0.0, 0.35, 0.7, 1.05, -0.45]:
        if clear(target + Vector3.UP * lift):
            pivot_origin = target + Vector3.UP * lift
            break
    var safe: Vector3 = sweep(pivot_origin, desired)
    distance = safe.distance_to(target)
    compressed = distance < 1.65
    if compressed:
        # Keep the viewing bearing. Try above the rail/device rather than
        # forcing a minimum radius through it. Pick the nearest useful height.
        for lift: float in [0.55, 1.05, 1.55]:
            var pivot: Vector3 = pivot_origin + Vector3.UP * lift
            if not clear(pivot) or sweep(pivot_origin, pivot).distance_to(pivot) > 0.08:
                continue
            var candidate: Vector3 = sweep(pivot, desired + Vector3.UP * lift)
            if candidate.distance_to(pivot) > distance + 0.45:
                safe = candidate
                distance = candidate.distance_to(pivot)
            if distance >= 2.0:
                break
    var current: Vector3 = camera.global_position
    var next: Vector3 = safe if snap else current.move_toward(current.lerp(safe, 1.0 - exp(-9.0 * delta)), 12.0 * delta)
    # Continuous old->new sweep stops smoothing from cutting through a wall.
    if not snap and clear(camera.global_position) and camera.global_position.distance_to(next) > 0.001:
        next = sweep(camera.global_position, next)
        if next.distance_to(current) < 0.01 and current.distance_to(safe) > 0.4:
            # Travel above a railing instead of teleporting across it. This
            # intermediate waypoint also has a swept, speed-limited path.
            var above: Vector3 = current + Vector3.UP * minf(0.8, 12.0 * delta)
            if above.y < 6.1 and clear(above):
                next = sweep(current, above)
    if not clear(next):
        next = current
    previous = camera.global_position
    max_step = maxf(max_step, previous.distance_to(next)) if not snap else max_step
    distance = next.distance_to(actor.global_position + Vector3.UP * 1.0)
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
        body.visible = not near_body and not (other == actor and bool(actor.get("use_first_person")))
        if not body.visible:
            suppressed_actors += 1
