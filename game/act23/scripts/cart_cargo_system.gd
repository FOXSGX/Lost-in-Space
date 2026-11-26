extends Node3D

# -----------------------------------------------------------------------------
# CartCargoSystem - the two loose containers on the mine cart's rear deck.
#
# MECHANICS-002A (this round):
#   The old "G 固定" was a fake mechanism: pressing G lerped the frozen body into
#   the cradle over 0.7 s and then re-pinned its transform every frame, while the
#   two "claws" were decorative meshes. The feedback claimed "锁爪已闭合" although
#   no clamp existed.
#
#   Now:
#     * the cradle is real hardware on the cart: a plate, two side rails and two
#       steel jaws, each with a collision body (layer 32, which the containers'
#       mask 34 already collides with);
#     * G only *puts the container down*: the carry solver sweeps it to just above
#       the cradle and lets go - the container then falls and settles under the
#       engine's own rigid-body solver (no freeze, no transform pin);
#     * E ("repair", the on-deck action key) runs the clamp screw: both jaws
#       advance at a bounded rate and are stopped by the container's real surface
#       (never more than PEN_ALLOW of squeeze), or by their hard stop;
#     * a container only counts as secured when the jaws are actually pressing it,
#       it is inside the cradle pocket and it is resting on the cradle plate.
#
# The container is never frozen once placed. What holds it during the ride is the
# closed jaw pair (longitudinal) plus the two side rails (lateral), i.e. contact.
# -----------------------------------------------------------------------------

var stage: Node3D
var cart: AnimatableBody3D
var cargo: Array[RigidBody3D] = []
var slots: Array[Vector3] = [Vector3(-1.10, 2.005, 2.92), Vector3(0.65, 2.005, 2.92)]
var starts: Array[Vector3] = [Vector3(-0.45, 1.99, 2.05), Vector3(0.90, 1.99, 2.22)]
var clamps: Array[Array] = []
var slot_labels: Array[Label3D] = []
var events: Array[Dictionary] = []
var revision: int = 0
var paused: bool = false
# Client mirror: the host integrates the containers, the client only draws them.
var network_client: bool = false
var hum: AudioStreamPlayer3D
var latch: AudioStreamPlayer3D
var fx: Node3D # Kept as a settings adapter boundary for the inherited application.

# --- MECHANICS-002A cargo clamp hardware -------------------------------------
const CRATE_R: float = 0.245          # container capsule radius
const JAW_HALF_X: float = 0.06        # half thickness of one jaw
const JAW_OPEN_X: float = 0.490       # jaw centre offset from the slot centre
const JAW_STOP_X: float = 0.290       # hard stop (jaw centre)
const RAIL_Z: float = 0.360           # side-rail centre offset from the slot centre
const PEN_ALLOW: float = 0.002        # mechanical clearance left between jaw and container
const CRANK_RATE: float = 0.11        # m/s jaw travel while the screw turns
const CRANK_SECONDS: float = 3.20     # bounded actuator stroke time
const POCKET_TOL_X: float = 0.12
const POCKET_TOL_Z: float = 0.16
const SEAT_TOL_Y: float = 0.14

var jaw_x: Array[float] = [JAW_OPEN_X, JAW_OPEN_X]
var jaw_floor: Array[float] = [JAW_STOP_X, JAW_STOP_X]
var jaw_motor: Array[bool] = [false, false]
var jaw_clock: Array[float] = [0.0, 0.0]
var jaw_stalled: Array[bool] = [false, false]
var jaw_pressing: Array[bool] = [false, false]
var slot_cradle: Array[Dictionary] = []
var seat_contacts: Array[int] = [0, 0]

func _ready() -> void:
	fx = Node3D.new()
	add_child(fx)
	var imported: Node3D = (load("res://act23/assets/device_parts.glb") as PackedScene).instantiate() as Node3D
	stage.call("_adapt_materials", imported, {})
	var core_palette: Node3D = Node3D.new()
	for node: Node in imported.get_children():
		if str(node.name).begins_with("DYN_core"):
			node.owner = null
			node.reparent(core_palette, false)
	cart.add_child(imported)
	# The previously verified calibration can be skipped in this independent slice.
	var installed: Node3D = core_palette.duplicate() as Node3D
	installed.position = Vector3(-2.5, 1.965, 2.2)
	installed.scale = Vector3.ONE * 0.72
	cart.add_child(installed)
	for i: int in range(2):
		var body: RigidBody3D = preload("res://act23/scripts/cart_cargo.gd").new() as RigidBody3D
		body.name = "Cargo_%d" % (801 + i)
		body.set("object_id", 801 + i)
		body.set("system", self)
		body.set("cart", cart)
		body.set("initial_local", starts[i])
		body.position = cart.to_global(starts[i])
		add_child(body)
		var visual: Node3D = core_palette.duplicate() as Node3D
		visual.scale = Vector3.ONE * 0.72
		body.add_child(visual)
		cargo.append(body)
		stage.call("label_at", body, "F · 容器 %d" % (i + 1), Vector3(0, 1.08, 0), Color("9be5e9"))
	core_palette.free()
	var env: Script = preload("res://act23/scripts/cart_environment.gd")
	for i: int in range(slots.size()):
		var at: Vector3 = slots[i]
		_build_cradle(i, at, env)
		# One plate label per cradle, not a second floating prompt: the text is the
		# cradle's own state line (see _update_decor) and only says "E" when a
		# container is actually sitting in the pocket waiting for the jaws.
		slot_labels.append(stage.call("label_at", cart, "G · 放置 %d" % (i + 1), at + Vector3(0, 0.35, 0.52), Color("d3b47c")) as Label3D)
	hum = AudioStreamPlayer3D.new()
	var loop: AudioStreamWAV = (load("res://act23/assets/audio/hum.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hum.stream = loop
	hum.volume_db = -19
	hum.max_distance = 18
	cart.add_child(hum)
	hum.position = Vector3(-2.5, 2.8, 2.2)
	hum.play()
	latch = AudioStreamPlayer3D.new()
	latch.stream = load("res://act23/assets/audio/latch.wav") as AudioStream
	latch.volume_db = -8
	cart.add_child(latch)
	latch.position = Vector3(0, 2, 2.2)

# Real cradle hardware: a machined plate the container rests on, two side rails
# that stop it sliding off sideways, and a pair of steel jaws that close along
# the cart's longitudinal axis (the direction the authored claws already faced).
func _build_cradle(i: int, at: Vector3, env: Script) -> void:
	var plate_top: float = at.y
	var holder: Dictionary = {}
	# Deck plate (collidable). The mesh is the one the old build drew; the body is
	# new so the container can actually rest on it.
	env.box(cart, Vector3(0.79, 0.05, 0.79), env.material(Color("6f7f83"), 0.05), at - Vector3.UP * 0.03)
	var plate: StaticBody3D = _solid(cart, "CradlePlate_%d" % (i + 1),
		Vector3(0.79, 0.05, 0.79), Vector3(at.x, plate_top - 0.025, at.z))
	holder["plate"] = plate
	var rails: Array = []
	for side: float in [-1.0, 1.0]:
		var rail: StaticBody3D = _solid(cart, "CradleRail_%d_%d" % [i + 1, 1 if side > 0.0 else 0],
			Vector3(0.86, 0.17, 0.06), Vector3(at.x, plate_top + 0.075, at.z + side * RAIL_Z))
		env.box(cart, Vector3(0.86, 0.17, 0.06), env.material(Color("8a8f92"), 0.2),
			Vector3(at.x, plate_top + 0.075, at.z + side * RAIL_Z))
		rails.append(rail)
	holder["rails"] = rails
	# Jaw pair. Each jaw is a cart-space pivot holding the authored claw mesh plus
	# a real collision body; the screw moves the pivot's x.
	#
	# MECHANICS-002B: the jaws used to sit at plate + 0.10 m, i.e. against the
	# capsule's LOWER hemisphere, where the container radius is already shrinking
	# (0.19 m at that height instead of 0.245 m). The jaws therefore closed on air
	# 45 mm away from the real surface, and a clamped container could slide 25 mm
	# into them under 0.7 m/s² acceleration (measured). The jaw now spans
	# 2.05–2.55 m, i.e. the capsule's full-radius band, so "jaw face = surface"
	# is geometrically true and the 2 mm squeeze is real contact.
	var jaws: Array = []
	var meshes: Array = []
	for side: float in [-1.0, 1.0]:
		var pivot: Node3D = Node3D.new()
		pivot.name = "Jaw_%d_%d" % [i + 1, 1 if side > 0.0 else 0]
		pivot.position = Vector3(at.x + side * JAW_OPEN_X, at.y + 0.305, at.z)
		cart.add_child(pivot)
		var mesh: MeshInstance3D = env.box(pivot, Vector3(0.12, 0.50, 0.60),
			env.material(Color("d2a157"), 0.30), Vector3.ZERO)
		meshes.append(mesh)
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "JawBody"
		# Layer 2 (solid): the container's mask 34 already includes it, the carry
		# sweep (mask 2) then refuses to lower a container through a jaw, and the
		# player's mask 50 also sees the steel.
		body.collision_layer = 2
		body.collision_mask = 0
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(0.12, 0.50, 0.60)
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		pivot.add_child(body)
		jaws.append({"pivot": pivot, "body": body, "side": side})
	holder["jaws"] = jaws
	holder["meshes"] = meshes
	holder["plate_top"] = plate_top
	slot_cradle.append(holder)
	clamps.append(meshes)

func _solid(parent: Node3D, nm: String, size: Vector3, at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = nm
	body.collision_layer = 2
	body.collision_mask = 0
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	body.position = at
	return body

func _exit_tree() -> void:
	if is_instance_valid(hum):
		hum.stop()
		hum.stream = null
	if is_instance_valid(latch):
		latch.stop()
		latch.stream = null

func pose_target(actor_id: int) -> Node3D:
	for body: RigidBody3D in cargo:
		if int(body.get("carrier_id")) == actor_id: return body
	return cargo[0]

func held_by(actor_id: int) -> RigidBody3D:
	for body: RigidBody3D in cargo:
		if int(body.get("carrier_id")) == actor_id and str(body.get("phase")) in ["held", "placing"]: return body
	return null

func carrier_motion_fraction(actor: CharacterBody3D, motion_vector: Vector3) -> float:
	var body: RigidBody3D = held_by(int(actor.get("peer_id")))
	if body == null: return 1.0
	var motion: RefCounted = body.get("motion") as RefCounted
	var query: PhysicsShapeQueryParameters3D = motion.call("query", body.global_position) as PhysicsShapeQueryParameters3D
	query.motion = motion_vector
	var cast: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	return maxf(0.0, cast[0] - 0.008) if not cast.is_empty() else 1.0

func carry_facing_yaw(_actor: CharacterBody3D, desired_yaw: float) -> float:
	return desired_yaw

# --- interaction -------------------------------------------------------------

func handle_action(actor_id: int, action: String) -> bool:
	if not multiplayer.is_server(): return false
	var roster: Dictionary = stage.get("actors") as Dictionary
	if not roster.has(actor_id): return false
	var actor: CharacterBody3D = roster[actor_id] as CharacterBody3D
	var held: RigidBody3D = held_by(actor_id)
	if action == "repair":
		return _operate_clamp(actor)
	if int(actor.get("grip_id")) >= 0 and action == "pickup":
		stage.set("feedback", "先按 E 松开扶手，再搬运容器。")
		return false
	if action == "pickup" and held == null:
		var selected: RigidBody3D = null
		var best: float = 1.75
		for body: RigidBody3D in cargo:
			if str(body.get("phase")) not in ["free", "seated"]: continue
			var at: Vector3 = body.global_position + Vector3.UP * 0.48
			var distance: float = (actor.global_position + Vector3.UP * 0.8).distance_to(at)
			if distance < best and bool(stage.call("can_reach", actor, at, 1.75)):
				# A clamped container must be released with the clamp first, and the
				# cart has to be stopped - the same rule the old build had.
				if slot_secured(int(body.get("slot"))) and float(cart.get("speed")) > 0.03: continue
				if slot_secured(int(body.get("slot"))):
					stage.set("feedback", "容器被锁爪夹住 · 先按 E 松开锁爪，再按 F 搬运。")
					return false
				best = distance
				selected = body
		if selected == null:
			stage.set("feedback", "靠近并面向容器按 F。被锁爪夹住的容器要先松开锁爪。")
			return false
		selected.freeze = true
		selected.collision_layer = 0
		_lift_off_deck(selected, actor)
		selected.set("phase", "held")
		selected.set("carrier_id", actor_id)
		selected.set("slot", -1)
		var motion: RefCounted = preload("res://act23/scripts/cart_carry_motion.gd").new() as RefCounted
		motion.set("cart", cart)
		motion.call("setup", selected, actor)
		motion.call("begin_hold")
		selected.set("motion", motion)
		actor.set("carrying", 3)
		actor.set("carrying_id", int(selected.get("object_id")))
		stage.set("feedback", "已拿起容器 · 走到固定座按 G 放下 · 再按 E 合拢锁爪")
		record("pickup", selected, actor_id)
		return true
	if held == null: return false
	var carry: RefCounted = held.get("motion") as RefCounted
	if str(held.get("phase")) != "held": return false
	if action == "drop":
		var desired: Vector3 = actor.global_position - actor.global_basis.z * 0.82
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			desired + Vector3.UP * 1.3, desired - Vector3.UP * 0.6, 34, [actor.get_rid(), held.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or not bool(carry.call("prepare_place", (hit["position"] as Vector3) + Vector3.UP * 0.015)):
			stage.set("feedback", "前方没有可安全放置的支撑。转身或移开一点再按 X。")
			return false
		held.set("phase", "placing")
		record("drop", held, actor_id)
		return true
	if action == "deposit":
		# G = lower the container onto a cradle mouth. The carry solver sweeps it
		# down with a real shape cast; then the body is released and the engine's
		# solver settles it. Nothing is teleported into the slot and nothing is
		# pinned afterwards.
		for i: int in range(slots.size()):
			if slot_taken(i): continue
			var at: Vector3 = cart.to_global(slots[i])
			if not bool(stage.call("can_reach", actor, at + Vector3.UP * 0.4, 1.75)): continue
			var mouth: Vector3 = at + Vector3.UP * 0.16
			if not bool(carry.call("prepare_place", mouth)):
				stage.set("feedback", "固定座上方被挡住 · 换个角度把容器放下来")
				return false
			held.set("phase", "placing")
			held.set("slot", i)
			record("place_begin", held, actor_id)
			stage.set("feedback", "容器正在下放到固定座 · 落稳后按 E 合拢锁爪")
			return true
		stage.set("feedback", "靠近空固定座并面向它按 G。")
	return false

# E on a cradle: run the clamp screw, or release it when the cart is stopped.
func _operate_clamp(actor: CharacterBody3D) -> bool:
	var best: int = -1
	var best_d: float = 1.85
	for i: int in range(slots.size()):
		var at: Vector3 = cart.to_global(slots[i] + Vector3(0, 0.35, 0))
		var d: float = actor.global_position.distance_to(at)
		if d < best_d:
			best = i
			best_d = d
	if best < 0:
		return false
	var actor_id: int = int(actor.get("peer_id"))
	if jaw_motor[best]:
		stage.set("feedback", "锁爪正在合拢 · 等它走到位")
		return true
	if _clamp_closed(best):
		if float(cart.get("speed")) > 0.03:
			stage.set("feedback", "行驶中不能松开锁爪 · 先按 B 制动")
			return false
		open_clamp(best)
		stage.set("feedback", "锁爪已松开 · 容器回到可搬运状态")
		record("clamp_open", cargo[_occupant(best)] if _occupant(best) >= 0 else cargo[0], actor_id)
		return true
	# Start the screw. It is a bounded actuator: it advances the jaws until they
	# press the container (or hit the hard stop) and gives up after CRANK_SECONDS.
	jaw_motor[best] = true
	jaw_clock[best] = 0.0
	jaw_stalled[best] = false
	record("clamp_begin", cargo[_occupant(best)] if _occupant(best) >= 0 else cargo[0], actor_id)
	stage.set("feedback", "锁爪电机启动 · 夹钳正在合拢")
	return true

# A container lying against a cradle rail cannot be dragged forward: the carry
# solver moves along the straight line to the hold point and a sweep that starts
# in contact returns zero, so it would stay pinned to the deck forever (measured:
# crate 2 starts 0.065 m in front of rail 2's inner face and the hold point is
# behind that rail, so the straight-line carry could not lift it at all).
# A player lifts first, so do the same: a clear vertical sweep to hold height,
# then the normal carry solver takes over.
func _lift_off_deck(body: RigidBody3D, actor: CharacterBody3D) -> void:
	var rise: float = actor.global_position.y + 0.34 - body.global_position.y
	if rise <= 0.01: return
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = CRATE_R
	shape.height = 0.99
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, body.global_position + Vector3.UP * 0.495)
	query.collision_mask = 2
	query.margin = 0.008
	query.exclude = [actor.get_rid(), body.get_rid()]
	query.motion = Vector3.UP * rise
	var cast: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	var fraction: float = maxf(0.0, cast[0] - 0.002) if not cast.is_empty() else 1.0
	body.global_position += query.motion * fraction
	body.reset_physics_interpolation()

func open_clamp(index: int) -> void:
	if index < 0 or index >= jaw_x.size():
		return
	jaw_motor[index] = false
	jaw_clock[index] = 0.0
	jaw_stalled[index] = false
	jaw_pressing[index] = false
	jaw_x[index] = JAW_OPEN_X

func _clamp_closed(index: int) -> bool:
	if jaw_stalled[index]:
		return false
	if jaw_pressing[index]:
		return true
	return jaw_x[index] <= JAW_STOP_X + 0.004

func slot_taken(index: int) -> bool:
	for body: RigidBody3D in cargo:
		if int(body.get("slot")) == index and str(body.get("phase")) in ["seated", "locked", "placing"]: return true
	return false

func _occupant(index: int) -> int:
	# Assigned first, then by geometry: a container that is physically inside the
	# cradle counts even if it has not been re-assigned a slot yet, otherwise the
	# jaws would close through it.
	for k: int in range(cargo.size()):
		var body: RigidBody3D = cargo[k]
		if int(body.get("slot")) == index and str(body.get("phase")) in ["seated", "locked", "placing"]:
			return k
	var best: int = -1
	var best_d: float = 0.30
	for k: int in range(cargo.size()):
		var body: RigidBody3D = cargo[k]
		var phase: String = str(body.get("phase"))
		if phase != "free" and phase != "seated":
			continue
		var local: Vector3 = cart.to_local(body.global_position)
		var d: float = Vector2(local.x - slots[index].x, local.z - slots[index].z).length()
		if d < best_d:
			best_d = d
			best = k
	return best

# Real seat test: the container must be inside the cradle pocket, resting on the
# plate, and the jaws must be pressing it. Nothing here reads a task flag.
func slot_secured(index: int) -> bool:
	if index < 0 or index >= slots.size():
		return false
	if not _clamp_closed(index):
		return false
	var k: int = _occupant(index)
	if k < 0:
		return false
	var body: RigidBody3D = cargo[k]
	if str(body.get("phase")) == "placing":
		return false
	var local: Vector3 = cart.to_local(body.global_position)
	if absf(local.x - slots[index].x) > POCKET_TOL_X: return false
	if absf(local.z - slots[index].z) > POCKET_TOL_Z: return false
	if absf(local.y - slots[index].y) > SEAT_TOL_Y: return false
	if body.global_position.y < cart.global_position.y + 0.6: return false
	return seat_contacts[index] > 0

# --- physics -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if paused: return
	if network_client:
		_apply_jaw_visuals()
		_update_decor(delta)
		return
	_advance_clamps(delta)
	for body: RigidBody3D in cargo:
		body.set("clock", float(body.get("clock")) + delta)
		var phase: String = str(body.get("phase"))
		var actor_id: int = int(body.get("carrier_id"))
		var roster: Dictionary = stage.get("actors") as Dictionary
		var actor: CharacterBody3D = roster.get(actor_id) as CharacterBody3D
		var motion: RefCounted = body.get("motion") as RefCounted
		if phase == "held" and actor != null:
			motion.call("tick_hold", delta)
		elif phase == "placing":
			if bool(motion.call("tick_place", delta)):
				_settle_after_place(body, actor)
		_seat_test(body)
		if body.global_position.y < -4 and float(cart.get("speed")) < 0.03: _recover(body)
	_apply_jaw_visuals()
	_update_decor(delta)

# The container has just been let go above the cradle: it is now a free rigid
# body. If it is inside a cradle pocket, it becomes "seated" (still free, still
# physics), otherwise it stays "free" on the deck.
func _settle_after_place(body: RigidBody3D, actor: CharacterBody3D) -> void:
	body.set("phase", "seated")
	body.set("elapsed", 0.0)
	body.set("initial_local", cart.to_local(body.global_position))
	_release_actor(body, actor)

func _seat_test(body: RigidBody3D) -> void:
	var phase: String = str(body.get("phase"))
	if phase != "seated" and phase != "locked": return
	var index: int = int(body.get("slot"))
	if index < 0 or index >= slots.size():
		# Not assigned yet: pick the cradle it is sitting in, if any.
		index = _nearest_slot(body)
		if index >= 0:
			body.set("slot", index)
		else:
			return
	var local: Vector3 = cart.to_local(body.global_position)
	var inside: bool = absf(local.x - slots[index].x) <= POCKET_TOL_X \
		and absf(local.z - slots[index].z) <= POCKET_TOL_Z \
		and absf(local.y - slots[index].y) <= SEAT_TOL_Y
	var touching: bool = _touches_cradle(body, index)
	seat_contacts[index] = 1 if (inside and touching) else 0
	if phase == "seated":
		body.set("elapsed", float(body.get("elapsed")) + get_physics_process_delta_time())
	if phase == "seated" and not inside and float(body.get("elapsed")) > 2.0:
		# It slid out of the pocket and stayed out: loose cargo again.
		body.set("slot", -1)
		body.set("phase", "free")
		body.set("initial_local", local)
		if _clamp_closed(index):
			open_clamp(index)
	# "locked" is derived every frame from the clamp + pocket + contact, never
	# latched by the key press.
	if phase == "seated" and slot_secured(index):
		body.set("phase", "locked")
		latch.play()
		stage.set("feedback", "固定完成 · 锁爪合拢到位，容器被夹钳与边轨夹住")
		record("locked", body, 0)
	elif phase == "locked" and not slot_secured(index):
		body.set("phase", "seated")
		stage.set("feedback", "锁爪失去夹持 · 容器不在固定座里了")

func _nearest_slot(body: RigidBody3D) -> int:
	var local: Vector3 = cart.to_local(body.global_position)
	var best: int = -1
	var best_d: float = 0.55
	for i: int in range(slots.size()):
		var d: float = Vector2(local.x - slots[i].x, local.z - slots[i].z).length()
		if d < best_d:
			best_d = d
			best = i
	return best

func _touches_cradle(body: RigidBody3D, index: int) -> bool:
	if index >= slot_cradle.size(): return false
	var plate: Node = slot_cradle[index].get("plate") as Node
	for hit: Node in body.get_colliding_bodies():
		if hit == plate: return true
		if hit == cart: return true
	return false

func _advance_clamps(delta: float) -> void:
	for i: int in range(slots.size()):
		var k: int = _occupant(i)
		var floor_x: float = JAW_STOP_X
		if k >= 0:
			var body: RigidBody3D = cargo[k]
			var local: Vector3 = cart.to_local(body.global_position)
			var off_x: float = local.x - slots[i].x
			# Both jaws are driven by one screw, so the pair stops at whichever side
			# the container reaches first. The jaw can never pass the container's
			# surface by more than PEN_ALLOW; the resulting 2 mm overlap is what the
			# engine turns into the squeeze that slides an off-centre container back
			# over the cradle centre (a real vise).
			var plus_surface: float = off_x + CRATE_R
			var minus_surface: float = CRATE_R - off_x
			floor_x = maxf(JAW_STOP_X, maxf(plus_surface, minus_surface) + JAW_HALF_X - PEN_ALLOW)
			jaw_floor[i] = floor_x
			# "Pressing" is a geometric fact, not a motor state: the jaw is sitting
			# at the container-limited position.
			jaw_pressing[i] = jaw_x[i] <= floor_x + 0.004
		else:
			jaw_pressing[i] = false
			jaw_floor[i] = JAW_STOP_X
		if not jaw_motor[i]:
			continue
		jaw_clock[i] += delta
		# The screw advances the pair at CRANK_RATE, but the jaw can never be inside
		# the container: if the container shifts into the jaw, the jaw follows its
		# surface back out (a spring-loaded clamp, not a teleport through steel).
		if jaw_x[i] - floor_x > 0.0005:
			jaw_x[i] = maxf(floor_x, jaw_x[i] - CRANK_RATE * delta)
		elif floor_x > jaw_x[i]:
			jaw_x[i] = minf(floor_x, jaw_x[i] + CRANK_RATE * delta)
		var centered: bool = k >= 0 and absf(cart.to_local((cargo[k] as Node3D).global_position).x - slots[i].x) <= POCKET_TOL_X
		if jaw_x[i] <= JAW_STOP_X + 0.002:
			jaw_x[i] = JAW_STOP_X
			jaw_motor[i] = false
			jaw_clock[i] = 0.0
		elif jaw_pressing[i] and centered:
			# The screw is at its rated push on a seated container: that is
			# "closed", not an obstruction.
			jaw_motor[i] = false
			jaw_clock[i] = 0.0
			if k >= 0:
				var b: RigidBody3D = cargo[k]
				if int(b.get("slot")) != i:
					b.set("slot", i)
		elif jaw_clock[i] > CRANK_SECONDS:
			jaw_motor[i] = false
			jaw_stalled[i] = true
			stage.set("feedback", "锁爪行程卡住 · 容器没摆正在固定座里，重新放一次")
			record("clamp_stall", cargo[k] if k >= 0 else cargo[0], 0)

func _apply_jaw_visuals() -> void:
	for i: int in range(slot_cradle.size()):
		var jaws: Array = slot_cradle[i]["jaws"] as Array
		for entry: Dictionary in jaws:
			var pivot: Node3D = entry["pivot"] as Node3D
			var side: float = float(entry["side"])
			pivot.position.x = slots[i].x + side * jaw_x[i]
		# The old decorative slide is gone: the authored claw meshes ARE the jaws.

func _update_decor(delta: float) -> void:
	for i: int in range(slots.size()):
		var body: RigidBody3D = null
		var k: int = _occupant(i)
		if k >= 0:
			body = cargo[k]
		var text: String = "G · 放置 %d" % (i + 1)
		if slot_secured(i):
			text = "已锁紧 %d" % (i + 1)
		elif jaw_motor[i]:
			text = "锁爪合拢中 %d" % (i + 1)
		elif _clamp_closed(i):
			text = "锁爪已合拢 · 无容器 %d" % (i + 1)
		elif _occupant(i) >= 0:
			text = "E · 合拢锁爪 %d" % (i + 1)
		slot_labels[i].text = text
	hum.pitch_scale = 0.92 + float(cart.get("speed")) * 0.10 + (0.13 * sin(float(cart.get("clock")) * 7.0) if bool(cart.get("event_active")) else 0.0)

# --- network mirror --------------------------------------------------------

func net_rows() -> Array:
	var rows: Array = []
	for body: RigidBody3D in cargo:
		var local: Transform3D = cart.global_transform.affine_inverse() * body.global_transform
		rows.append([int(body.get("object_id")), str(body.get("phase")), int(body.get("slot")),
			int(body.get("carrier_id")), local])
	# MECHANICS-002A: the jaws are host-owned mechanism state; a client needs them
	# to draw the same clamp. Appended so older readers keep working.
	for i: int in range(jaw_x.size()):
		rows.append([-1 - i, "clamp", i, 0, jaw_x[i]])
	return rows

func apply_net_rows(rows: Array) -> void:
	network_client = true
	for row: Array in rows:
		if row.size() < 5:
			continue
		var object_id: int = int(row[0])
		if object_id < 0:
			var idx: int = -1 - object_id
			if idx >= 0 and idx < jaw_x.size():
				jaw_x[idx] = float(row[4])
				_apply_jaw_visuals()
			continue
		var body: RigidBody3D = null
		for candidate: RigidBody3D in cargo:
			if int(candidate.get("object_id")) == object_id:
				body = candidate
				break
		if body == null:
			continue
		body.set("phase", str(row[1]))
		body.set("slot", int(row[2]))
		body.set("carrier_id", int(row[3]))
		var local: Transform3D = row[4] as Transform3D
		var target: Transform3D = cart.global_transform * local
		if not body.freeze:
			body.freeze = true
			body.collision_layer = 0
			body.collision_mask = 0
		body.global_transform = body.global_transform.interpolate_with(target, 0.55)
		body.reset_physics_interpolation()

func _release_actor(body: RigidBody3D, actor: CharacterBody3D) -> void:
	if actor != null:
		actor.set("carrying", 0)
		actor.set("carrying_id", 0)
		actor.set("carry_obstructed", false)
	body.set("carrier_id", 0)

func recover_free() -> void:
	for body: RigidBody3D in cargo:
		if str(body.get("phase")) in ["free", "seated"]: _recover(body)

func _recover(body: RigidBody3D) -> void:
	var index: int = cargo.find(body)
	if str(body.get("phase")) == "locked":
		open_clamp(int(body.get("slot")))
	if str(body.get("phase")) == "held":
		_release_actor(body, (stage.get("actors") as Dictionary).get(int(body.get("carrier_id"))) as CharacterBody3D)
	body.freeze = true
	body.global_transform = cart.global_transform * Transform3D(Basis.IDENTITY, starts[index])
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.reset_physics_interpolation()
	body.freeze = false
	body.sleeping = false
	body.set("stranded", false)
	body.set("phase", "free")
	body.set("slot", -1)
	body.set("initial_local", starts[index])
	body.set("recovery_count", int(body.get("recovery_count")) + 1)
	record("cargo_recovered", body, 0)

func reset_all() -> void:
	for i: int in range(slots.size()):
		open_clamp(i)
		seat_contacts[i] = 0
	for body: RigidBody3D in cargo:
		var actor: CharacterBody3D = (stage.get("actors") as Dictionary).get(int(body.get("carrier_id"))) as CharacterBody3D
		_release_actor(body, actor)
		body.set("motion", null)
		body.collision_layer = 8
		body.collision_mask = 34
		body.set("slot", -1)
		body.set("elapsed", 0.0)
		_recover(body)

func locked_count() -> int:
	var count: int = 0
	for i: int in range(slots.size()):
		if slot_secured(i): count += 1
	return count

## 机械规格（供专项测试读取，避免测试里复写常量）
func clamp_spec() -> Dictionary:
	return {
		"crate_r": CRATE_R, "jaw_half": JAW_HALF_X, "jaw_open": JAW_OPEN_X,
		"jaw_stop": JAW_STOP_X, "pen": PEN_ALLOW, "crank_rate": CRANK_RATE,
		"pocket_x": POCKET_TOL_X, "pocket_z": POCKET_TOL_Z, "seat_y": SEAT_TOL_Y,
	}


# Snapshot for tests / HUD: every value is read from the live mechanism.
func clamp_state() -> Dictionary:
	var out: Dictionary = {"jaws": [], "pressing": [], "stalled": [], "motor": [], "secured": []}
	for i: int in range(slots.size()):
		out["jaws"].append(snappedf(jaw_x[i], 0.001))
		out["pressing"].append(jaw_pressing[i])
		out["stalled"].append(jaw_stalled[i])
		out["motor"].append(jaw_motor[i])
		out["secured"].append(slot_secured(i))
	out["locked_count"] = locked_count()
	return out

func record(kind: String, body: RigidBody3D, actor_id: int) -> void:
	revision += 1
	events.append({"event": kind, "object_id": body.get("object_id") if body != null else 0,
		"actor_id": actor_id, "revision": revision, "distance": cart.get("distance")})
