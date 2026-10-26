extends RigidBody3D

var object_id: int = 0
var phase: String = "free"
var carrier_id: int = 0
var core: RigidBody3D
var system: Node3D
var cart: AnimatableBody3D
var motion: RefCounted
var clock: float = 0.0
var elapsed: float = 0.0
var dock_start: Transform3D
var slot: int = -1
var recovery_count: int = 0
var stranded: bool = false
var slip_max: float = 0.0
var contact_count: int = 0
var rail_contacts: int = 0
var initial_local: Vector3

func _ready() -> void:
	core = self
	mass = 6.0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	continuous_cd = true
	collision_layer = 8
	collision_mask = 34
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	linear_damp = 0.02
	angular_damp = 3.0
	contact_monitor = true
	max_contacts_reported = 8
	var physical: PhysicsMaterial = PhysicsMaterial.new()
	physical.friction = 0.035
	physical.bounce = 0.0
	physics_material_override = physical
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.245
	shape.height = 0.99
	collider.shape = shape
	collider.position.y = 0.495
	add_child(collider)
	body_entered.connect(_contact)

func _contact(body: Node) -> void:
	contact_count += 1
	if body == cart: rail_contacts += 1

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if phase != "free" or cart == null: return
	var local: Vector3 = cart.to_local(state.transform.origin)
	stranded = local.x < -3.6 or local.x > 3.3 or local.z < 0.55 or local.z > 3.85 or local.y < 1.4
	if stranded: return
	# Engine collisions remain authoritative. A bounded traction force supplements
	# low deck friction: restores cruise co-motion without cancelling acceleration.
	if local.y > 1.88 and local.y < 2.12:
		var platform_velocity: Vector3 = cart.call("point_velocity", state.transform.origin) as Vector3
		var relative: Vector3 = platform_velocity - state.linear_velocity
		relative.y = 0.0
		state.linear_velocity += (relative * 1.6).limit_length(0.38) * state.step
		if bool(cart.get("event_active")):
			# The unstable resonator produces a lateral force, never an animated box.
			# Strength follows the bend event's real intensity, so braking inside
			# the bend immediately reduces how hard loose cargo is pushed.
			var bend: Node3D = cart.get("bend_event") as Node3D
			var strength: float = 0.58
			if bend != null and is_instance_valid(bend):
				strength = 0.58 * clampf(float(bend.get("intensity")) * 1.6, 0.25, 1.0)
			state.linear_velocity += cart.global_basis.z * strength * state.step
		slip_max = maxf(slip_max, Vector2(local.x - initial_local.x, local.z - initial_local.z).length())
	state.linear_velocity = state.linear_velocity.limit_length(8.0)

func can_reach(actor: CharacterBody3D, at: Vector3, limit: float = 1.65) -> bool:
	return bool(system.get("stage").call("can_reach", actor, at, limit))
