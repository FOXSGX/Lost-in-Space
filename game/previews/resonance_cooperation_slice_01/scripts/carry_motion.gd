extends RefCounted

# Controlled spring motion, shared by all device actors. World collision stays
# authoritative; free objects use the engine's rigid-body solver.
var core: RigidBody3D
var actor: CharacterBody3D
var velocity: Vector3 = Vector3.ZERO
var blocked_frames: int = 0
var maximum_motion: float = 0.0
var body_clearance_failures: int = 0
var _shape: CapsuleShape3D
var _place_from: Transform3D
var _place_to: Transform3D
var _place_clock: float = 0.0
var placing: bool = false
var last_safe_position: Vector3
var penetration_recoveries: int = 0

func setup(body: RigidBody3D, player: CharacterBody3D) -> void:
    core = body
    actor = player
    _shape = CapsuleShape3D.new()
    _shape.radius = 0.245
    _shape.height = 0.99

func query(at: Vector3) -> PhysicsShapeQueryParameters3D:
    var result: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
    result.shape = _shape
    result.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.495)
    result.collision_mask = 2
    result.margin = 0.008
    result.exclude = [actor.get_rid(), core.get_rid()]
    return result

func clear(at: Vector3) -> bool:
    return core.get_world_3d().direct_space_state.intersect_shape(query(at), 1).is_empty()

func target() -> Vector3:
    # Capsule radii sum to .625m. Keep the core in front of the torso, never
    # shrink the hold point into the character to bypass a railing.
    for offset: Vector2 in [Vector2(0.04, 0.67), Vector2(-0.04, 0.65), Vector2(0.14, 0.65)]:
        var at: Vector3 = actor.global_position - actor.global_basis.z * offset.y + actor.global_basis.x * offset.x + Vector3.UP * 0.34
        if clear(at):
            return at
    blocked_frames += 1
    return core.global_position

func begin_hold() -> void:
    velocity = Vector3.ZERO
    placing = false
    last_safe_position=core.global_position
    for i: int in range(10):
        var lifted: Vector3=core.global_position+Vector3.UP*float(i)*.008
        if clear(lifted):
            core.global_position=lifted;last_safe_position=lifted;break

func tick_hold(delta: float) -> void:
    if not clear(core.global_position) and clear(last_safe_position):
        core.global_position=last_safe_position;velocity=Vector3.ZERO;penetration_recoveries+=1
    var desired: Vector3 = target()
    velocity += (desired - core.global_position) * 130.0 * delta
    velocity *= exp(-17.0 * delta)
    velocity = velocity.limit_length(7.0)
    var motion: Vector3 = velocity * delta
    var next: Vector3 = core.global_position + motion
    var radial: Vector3 = next - actor.global_position
    radial.y = 0.0
    if radial.length() < 0.635 and radial.length() > 0.01:
        var safe_ring: Vector3 = actor.global_position + radial.normalized() * 0.635
        next.x = safe_ring.x
        next.z = safe_ring.z
        motion = next - core.global_position
    var sweep: PhysicsShapeQueryParameters3D = query(core.global_position)
    sweep.motion = motion
    var cast: PackedFloat32Array = core.get_world_3d().direct_space_state.cast_motion(sweep)
    var safe: float = maxf(0.0, cast[0] - 0.008) if not cast.is_empty() else 1.0
    if safe < 0.99:
        velocity *= safe
        blocked_frames += 1
    # Exact end-overlap checks complement the concave-world sweep. Keep the
    # last clear point so numerical contact at a railing cannot trap the hold.
    for _attempt: int in range(10):
        if clear(core.global_position+motion*safe):break
        safe*=.5
    if clear(core.global_position+motion*safe):
        core.global_position += motion * safe
        last_safe_position=core.global_position
    maximum_motion = maxf(maximum_motion, motion.length() * safe)
    core.global_basis = Basis(core.global_basis.get_rotation_quaternion().slerp(actor.global_basis.get_rotation_quaternion(), 1.0 - exp(-8.0 * delta)))
    actor.set("carry_obstructed", core.global_position.distance_to(desired) > 0.75)

func prepare_place(at: Vector3) -> bool:
    if not clear(at + Vector3.UP * 0.025):
        return false
    var sweep: PhysicsShapeQueryParameters3D = query(core.global_position)
    sweep.motion = at + Vector3.UP * 0.06 - core.global_position
    var cast: PackedFloat32Array = core.get_world_3d().direct_space_state.cast_motion(sweep)
    if not cast.is_empty() and cast[0] < 0.985:
        return false
    _place_from = core.global_transform
    _place_to = Transform3D(Basis(Vector3.UP, actor.rotation.y), at + Vector3.UP * 0.06)
    _place_clock = 0.0
    placing = true
    return true

func tick_place(delta: float) -> bool:
    _place_clock += delta
    var t: float = clampf(_place_clock / 0.48, 0.0, 1.0)
    var eased_t: float = t * t * (3.0 - 2.0 * t)
    var desired: Transform3D = _place_from.interpolate_with(_place_to, eased_t)
    var sweep: PhysicsShapeQueryParameters3D = query(core.global_position)
    sweep.motion = desired.origin - core.global_position
    var cast: PackedFloat32Array = core.get_world_3d().direct_space_state.cast_motion(sweep)
    var fraction: float = maxf(0.0, cast[0] - 0.002) if not cast.is_empty() else 1.0
    core.global_position += sweep.motion * fraction
    core.global_basis = desired.basis
    if t < 1.0:
        return false
    placing = false
    core.freeze = false
    core.collision_layer = 8
    core.linear_velocity = Vector3.ZERO
    core.angular_velocity = Vector3.ZERO
    core.sleeping = false
    actor.set("carry_obstructed", false)
    return true

func overlaps() -> bool:
    return not core.get_world_3d().direct_space_state.intersect_shape(query(core.global_position), 1).is_empty()
