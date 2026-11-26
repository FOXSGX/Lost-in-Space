extends CrewItems3D

func add_item(peer_id: int, kind: String, reference: int = -1, data: Dictionary = {}, activate: bool = false) -> bool:
	if kind not in ["heater", "cell", "fuel"]:
		return super.add_item(peer_id, kind, reference, data, activate)
	var bag: Dictionary = ensure_bag(peer_id)
	for index: int in CAPACITY:
		if bag.slots[index].is_empty():
			bag.slots[index] = {"kind":kind,"charge":float(data.get("charge",180.0))}
			if activate:
				bag.equipment_active = false
				bag.selected = index
			return true
	return false

func _spawn_drop(peer_id: int, item: Dictionary) -> void:
	super._spawn_drop(peer_id,item)
	drops[-1].charge = float(item.get("charge",180.0))
	drops[-1].safe_position = drops[-1].position

func _physics_process(delta: float) -> void:
	if not controller.game_started:
		return
	# Adventure snapshots already carry poses and jet resources. Avoid the base
	# unreliable all-prop packet exceeding ENet's MTU in a large level.
	if controller.is_host:
		_tick_jet_resources(delta)
	for entry: Dictionary in drops:
		var body: RigidBody3D = _prop_bodies.get(String(entry.uid)) as RigidBody3D
		if body == null:
			continue
		if controller.is_host:
			if body.position.y < -12 or absf(body.position.x)>74 or body.position.z>25 or body.position.z < -905:
				body.position = entry.get("safe_position",Vector3(0,1,0))
				body.linear_velocity = Vector3.ZERO
			entry.position = body.position
			entry.rotation = body.rotation
		else:
			body.position = body.position.lerp(Vector3(entry.position),1-exp(-22*delta))
			body.rotation = entry.get("rotation",Vector3.ZERO)

func _process(delta: float) -> void:
	super._process(delta)
	var id: int = multiplayer.get_unique_id()
	for index: int in CAPACITY:
		var kind: String = ensure_bag(id).slots[index].get("kind", "")
		if kind in ["heater", "cell", "fuel"]:
			_icons[index].texture = load("res://previews/frost_first_playable/" + ("heat.svg" if kind == "heater" else "cell.svg"))
			_slot_levels[index].visible = true
			_slot_levels[index].text = "%d%%" % int(float(ensure_bag(id).slots[index].get("charge",0))/1.8) if kind == "heater" else ("电池" if kind == "cell" else "燃料")

func area() -> String:
	return "frost_adventure"

func move_multiplier(_peer_id: int) -> float:
	return 1.0

func world_catalog(_peer_id: int) -> Array:
	return drops

func item_name(kind: String) -> String:
	return {"heater": "便携热风机", "cell": "备用电池", "fuel": "普通燃料"}.get(kind, super.item_name(kind))

func item_hint(peer_id: int) -> String:
	var entry: Dictionary = nearby_item(peer_id)
	return "E 拾取 " + item_name(entry.kind) if not entry.is_empty() else ""

func pickup(peer_id: int, entry: Dictionary) -> bool:
	for current: Dictionary in drops:
		if current.uid == entry.get("uid", ""):
			if not add_item(peer_id, current.kind, -1, current, true):
				controller.show_notice("四格已满 · G 放下选中物品")
				return false
			drops.erase(current)
			publish()
			return true
	return false

func _use_selected(peer_id: int) -> void:
	if bool(ensure_bag(peer_id).equipment_active):
		return
	var kind: String = selected(peer_id).get("kind", "")
	if kind == "cell":
		if controller.recharge(peer_id):
			take_selected(peer_id)
			publish()
	elif kind == "medical":
		var actor: SpacePlayer3D = controller.players[peer_id]
		if actor.health < 5:
			actor.health = mini(5, actor.health + 3)
			take_selected(peer_id)
			publish()
	elif kind == "fuel":
		controller.show_notice("普通燃料 · 带回飞船核心台按 E 存入")
	elif kind != "heater":
		super._use_selected(peer_id)

func _refresh_held() -> void:
	super._refresh_held()
	var id: int = multiplayer.get_unique_id()
	var record: Dictionary = _held.get(id, {})
	var model: Node3D = record.get("node") as Node3D
	var actor: SpacePlayer3D = controller.players.get(id) as SpacePlayer3D
	if model != null and actor != null and actor._camera != null and model.get_parent() != actor._camera:
		model.reparent(actor._camera)
		model.position = Vector3(0.32, -0.38, -0.65)
		model.rotation = Vector3.ZERO
		model.scale = Vector3.ONE * 0.65

func _refresh_world() -> void:
	super._refresh_world()
	for entry: Dictionary in drops:
		var body: RigidBody3D = _prop_bodies.get(String(entry.uid)) as RigidBody3D
		if body != null and entry.kind in ["heater","cell","fuel"] and not body.has_meta("custom"):
			body.set_meta("custom", true)
			if entry.kind == "heater":
				add_heater_model(body)
			else:
				add_supply_model(body,entry.kind)
	for id: int in _held:
		if not is_instance_valid(_held[id].get("node")):
			continue
		var model: Node3D = _held[id].node
		var kind: String = selected(id).get("kind", "")
		if kind in ["heater","cell","fuel"] and not model.has_meta("custom"):
			model.set_meta("custom", true)
			if kind == "heater":
				add_heater_model(model)
			else:
				add_supply_model(model,kind)

func supply_part(parent: Node3D, point: Vector3, size_value: Vector3, color: Color) -> void:
	var view: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size_value
	view.mesh = mesh
	view.position = point
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color.srgb_to_linear()
	material.roughness = 0.65
	view.material_override = material
	parent.add_child(view)

func add_supply_model(parent: Node3D, kind: String) -> void:
	for child: Node in parent.get_children():
		if child is Node3D and not child is CollisionShape3D:
			child.visible = false
	var battery: bool = kind == "cell"
	supply_part(parent,Vector3.ZERO,Vector3(0.30,0.34,0.22),Color("6c9dad") if battery else Color("a58b57"))
	supply_part(parent,Vector3(0,0.18,0),Vector3(0.14,0.06,0.13),Color("d4c4a0"))
	for z: float in [-0.116,0.116]:
		supply_part(parent,Vector3(0,0,z),Vector3(0.22,0.09,0.014),Color("dfbd76"))
		if battery:
			supply_part(parent,Vector3(0,0,z*1.04),Vector3(0.06,0.20,0.012),Color("dfbd76"))
	if not battery:
		for x: float in [-0.10,0.10]:
			supply_part(parent,Vector3(x,0.23,0),Vector3(0.04,0.14,0.07),Color("424f53"))
		supply_part(parent,Vector3(0,0.29,0),Vector3(0.24,0.04,0.07),Color("424f53"))

func add_heater_model(parent: Node3D) -> void:
	for child: Node in parent.get_children():
		if child is Node3D and not child is CollisionShape3D:
			child.visible = false
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var barrel: CylinderMesh = CylinderMesh.new()
	barrel.top_radius = 0.13
	barrel.bottom_radius = 0.18
	barrel.height = 0.65
	mesh.mesh = barrel
	mesh.rotation.x = PI / 2
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("ecad57").srgb_to_linear()
	mesh.material_override = material
	parent.add_child(mesh)
	var handle: MeshInstance3D = MeshInstance3D.new()
	var grip: BoxMesh = BoxMesh.new()
	grip.size = Vector3(0.14,0.32,0.15)
	handle.mesh = grip
	handle.position = Vector3(0,-0.2,0.15)
	var rubber: StandardMaterial3D = StandardMaterial3D.new()
	rubber.albedo_color = Color("29414e")
	handle.material_override = rubber
	parent.add_child(handle)
