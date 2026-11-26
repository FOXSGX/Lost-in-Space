extends Node3D

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
var hum: AudioStreamPlayer3D
var latch: AudioStreamPlayer3D
var fx: Node3D # Kept as a settings adapter boundary for the inherited application.

func _ready() -> void:
	fx = Node3D.new()
	add_child(fx)
	var imported: Node3D = (load("res://assets/device_parts.glb") as PackedScene).instantiate() as Node3D
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
		var body: RigidBody3D = preload("res://scripts/cart_cargo.gd").new() as RigidBody3D
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
	var env: Script = preload("res://scripts/cart_environment.gd")
	for i: int in range(slots.size()):
		var at: Vector3 = slots[i]
		# No reflection probe exists under the Compatibility renderer, so a high
		# metallic value has no environment to reflect and resolves to black. The
		# cradle plate was authored at metallic 0.8 and rendered as a pure black
		# rectangle on the deck. Keep it dielectric and lighter than the deck so
		# the cargo seat reads as a machined plate.
		env.box(cart, Vector3(0.79, 0.05, 0.79), env.material(Color("6f7f83"), 0.05), at - Vector3.UP * 0.03)
		var pair: Array = []
		for side: float in [-1.0, 1.0]:
			var claw: MeshInstance3D = env.box(cart, Vector3(0.12, 0.22, 0.60), env.material(Color("d2a157"), 0.30), at + Vector3(side * 0.49, 0.10, 0))
			pair.append(claw)
		clamps.append(pair)
		slot_labels.append(stage.call("label_at", cart, "G · 固定座 %d" % (i + 1), at + Vector3(0, 0.35, 0.48), Color("d3b47c")) as Label3D)
	hum = AudioStreamPlayer3D.new()
	var loop: AudioStreamWAV = (load("res://assets/audio/hum.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hum.stream = loop
	hum.volume_db = -19
	hum.max_distance = 18
	cart.add_child(hum)
	hum.position = Vector3(-2.5, 2.8, 2.2)
	hum.play()
	latch = AudioStreamPlayer3D.new()
	latch.stream = load("res://assets/audio/latch.wav") as AudioStream
	latch.volume_db = -8
	cart.add_child(latch)
	latch.position = Vector3(0, 2, 2.2)

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
		if int(body.get("carrier_id")) == actor_id and str(body.get("phase")) in ["held", "placing", "inserting"]: return body
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

func handle_action(actor_id: int, action: String) -> bool:
	var roster: Dictionary = stage.get("actors") as Dictionary
	if not roster.has(actor_id): return false
	var actor: CharacterBody3D = roster[actor_id] as CharacterBody3D
	if int(actor.get("grip_id")) >= 0:
		stage.set("feedback", "先按 E 松开扶手，再搬运容器。")
		return false
	var held: RigidBody3D = held_by(actor_id)
	if action == "pickup" and held == null:
		var selected: RigidBody3D = null
		var best: float = 1.75
		for body: RigidBody3D in cargo:
			if str(body.get("phase")) not in ["free", "locked"]: continue
			var at: Vector3 = body.global_position + Vector3.UP * 0.48
			var distance: float = (actor.global_position + Vector3.UP * 0.8).distance_to(at)
			if distance < best and bool(stage.call("can_reach", actor, at, 1.75)):
				if str(body.get("phase")) == "locked" and float(cart.get("speed")) > 0.03: continue
				best = distance
				selected = body
		if selected == null:
			stage.set("feedback", "靠近并面向容器按 F。已固定的容器需停车才能解锁。")
			return false
		selected.freeze = true
		selected.collision_layer = 0
		selected.set("phase", "held")
		selected.set("carrier_id", actor_id)
		selected.set("slot", -1)
		var motion: RefCounted = preload("res://scripts/cart_carry_motion.gd").new() as RefCounted
		motion.set("cart", cart)
		motion.call("setup", selected, actor)
		motion.call("begin_hold")
		selected.set("motion", motion)
		actor.set("carrying", 3)
		actor.set("carrying_id", int(selected.get("object_id")))
		stage.set("feedback", "已拿起容器 · X 缓放 · 靠近固定座 G 锁定")
		record("pickup", selected, actor_id)
		return true
	if held == null: return false
	var carry: RefCounted = held.get("motion") as RefCounted
	if str(held.get("phase")) != "held": return false
	if action == "drop":
		var desired: Vector3 = actor.global_position - actor.global_basis.z * 0.82
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(desired + Vector3.UP * 1.3, desired - Vector3.UP * 0.6, 34, [actor.get_rid(), held.get_rid()])
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or not bool(carry.call("prepare_place", (hit["position"] as Vector3) + Vector3.UP * 0.015)):
			stage.set("feedback", "前方没有可安全放置的支撑。转身或移开一点再按 X。")
			return false
		held.set("phase", "placing")
		record("drop", held, actor_id)
		return true
	if action == "deposit":
		for i: int in range(slots.size()):
			if slot_taken(i): continue
			var at: Vector3 = cart.to_global(slots[i])
			if not bool(stage.call("can_reach", actor, at + Vector3.UP * 0.4, 1.75)): continue
			held.set("phase", "inserting")
			held.set("elapsed", 0.0)
			held.set("slot", i)
			held.set("dock_start", cart.global_transform.affine_inverse() * held.global_transform)
			stage.set("feedback", "导向座定位中 · 等待锁爪闭合")
			record("lock_begin", held, actor_id)
			return true
		stage.set("feedback", "靠近空固定座并面向它按 G。")
	return false

func slot_taken(index: int) -> bool:
	for body: RigidBody3D in cargo:
		if int(body.get("slot")) == index and str(body.get("phase")) in ["locked", "inserting"]: return true
	return false

func _physics_process(delta: float) -> void:
	if paused: return
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
				body.set("phase", "free")
				body.set("initial_local", cart.to_local(body.global_position))
				_release_actor(body, actor)
		elif phase in ["inserting", "locked"]:
			var index: int = int(body.get("slot"))
			var target: Transform3D = Transform3D(Basis.IDENTITY, slots[index])
			if phase == "inserting":
				var elapsed: float = float(body.get("elapsed")) + delta
				body.set("elapsed", elapsed)
				var t: float = smoothstep(0.0, 0.70, elapsed)
				var start: Transform3D = body.get("dock_start") as Transform3D
				body.global_transform = cart.global_transform * start.interpolate_with(target, t)
				if elapsed > 1.0:
					body.set("phase", "locked")
					_release_actor(body, actor)
					latch.play()
					stage.set("feedback", "固定完成 · 锁爪已闭合。停车后可 F 解锁。")
					record("locked", body, actor_id)
			else:
				body.global_transform = cart.global_transform * target
		if body.global_position.y < -4 and float(cart.get("speed")) < 0.03: _recover(body)
	for i: int in range(slots.size()):
		var amount: float = 0.0
		for body: RigidBody3D in cargo:
			if int(body.get("slot")) == i: amount = smoothstep(0.55, 1.0, float(body.get("elapsed"))) if str(body.get("phase")) == "inserting" else 1.0
		for side_index: int in range(2):
			var claw: Node3D = clamps[i][side_index] as Node3D
			claw.position.x = slots[i].x + (-1.0 if side_index == 0 else 1.0) * lerpf(0.49, 0.29, amount)
		slot_labels[i].text = ("已固定" if amount > 0.95 else "G · 固定座") + " %d" % (i + 1)
	hum.pitch_scale = 0.92 + float(cart.get("speed")) * 0.10 + (0.13 * sin(float(cart.get("clock")) * 7.0) if bool(cart.get("event_active")) else 0.0)

func _release_actor(body: RigidBody3D, actor: CharacterBody3D) -> void:
	if actor != null:
		actor.set("carrying", 0)
		actor.set("carrying_id", 0)
		actor.set("carry_obstructed", false)
	body.set("carrier_id", 0)

func recover_free() -> void:
	for body: RigidBody3D in cargo:
		if str(body.get("phase")) == "free": _recover(body)

func _recover(body: RigidBody3D) -> void:
	var index: int = cargo.find(body)
	body.freeze = true
	body.global_transform = cart.global_transform * Transform3D(Basis.IDENTITY, starts[index])
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.reset_physics_interpolation()
	body.freeze = false
	body.sleeping = false
	body.set("stranded", false)
	body.set("initial_local", starts[index])
	body.set("recovery_count", int(body.get("recovery_count")) + 1)
	record("cargo_recovered", body, 0)

func reset_all() -> void:
	for body: RigidBody3D in cargo:
		var actor: CharacterBody3D = (stage.get("actors") as Dictionary).get(int(body.get("carrier_id"))) as CharacterBody3D
		_release_actor(body, actor)
		body.set("phase", "free")
		body.set("slot", -1)
		body.set("elapsed", 0.0)
		body.set("motion", null)
		body.collision_layer = 8
		body.collision_mask = 34
		_recover(body)

func locked_count() -> int:
	var count: int = 0
	for body: RigidBody3D in cargo:
		if str(body.get("phase")) == "locked": count += 1
	return count

func record(kind: String, body: RigidBody3D, actor_id: int) -> void:
	revision += 1
	events.append({"event": kind, "object_id": body.get("object_id"), "actor_id": actor_id, "revision": revision, "distance": cart.get("distance")})
