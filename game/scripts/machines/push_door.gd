class_name PushDoor
extends Node3D

## Jammed industrial shutter in the entrance tunnel. The player grabs the lower
## handle and physically pushes it up; it grinds, slips back if released early,
## and latches open at the top.

signal opened()
signal progress_changed(p: float)

var body: AnimatableBody3D
var panel: MeshInstance3D
var area: Area3D
var progress: float = 0.0
var is_opened: bool = false
var active: bool = false
var player: PlayerController
var anchor: Transform3D
var kit: WorldKit
var _built: bool = false
var _rattle: float = 0.0
var _audio: AudioDirector
var _door_probe_shape: BoxShape3D
var _door_probe_query: PhysicsShapeQueryParameters3D


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	kit = WorldKit.new(self)
	var steel: Material = MatLib.painted_steel(Color(0.24, 0.30, 0.30))
	var dark: Material = MatLib.dark_steel()
	# frame
	kit.box("FrameL", Vector3(0.5, 4.6, 0.9), Vector3(-3.35, 2.3, 0), steel, Vector3.ZERO, true)
	kit.box("FrameR", Vector3(0.5, 4.6, 0.9), Vector3(3.35, 2.3, 0), steel, Vector3.ZERO, true)
	kit.box("Lintel", Vector3(7.2, 0.55, 1.0), Vector3(0, 4.45, 0), steel, Vector3.ZERO, true)
	kit.box("GuideL", Vector3(0.18, 4.3, 0.3), Vector3(-3.02, 2.15, 0.32), MatLib.bronze(), Vector3.ZERO, false)
	kit.box("GuideR", Vector3(0.18, 4.3, 0.3), Vector3(3.02, 2.15, 0.32), MatLib.bronze(), Vector3.ZERO, false)
	kit.rivet_ring(Vector3(0, 4.45, 0.5), 3.0, 20, Vector3.UP, MatLib.steel())
	# door body
	body = AnimatableBody3D.new()
	body.name = "DoorBody"
	body.sync_to_physics = false
	body.position = Vector3(0, 0, 0)
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(6.1, 4.15, 0.34)
	collider.shape = shape
	collider.position = Vector3(0, 2.1, 0)
	body.add_child(collider)
	panel = MeshInstance3D.new()
	var pm: BoxMesh = BoxMesh.new()
	pm.size = Vector3(6.1, 4.15, 0.3)
	panel.mesh = pm
	panel.material_override = steel
	panel.position = Vector3(0, 2.1, 0)
	body.add_child(panel)
	# door ribs / details as children of the moving body
	for i in range(5):
		var rib: MeshInstance3D = MeshInstance3D.new()
		var rm: BoxMesh = BoxMesh.new()
		rm.size = Vector3(0.14, 4.1, 0.06)
		rib.mesh = rm
		rib.material_override = MatLib.bronze() if i % 2 == 0 else dark
		rib.position = Vector3(-2.2 + float(i) * 1.1, 2.1, 0.17)
		body.add_child(rib)
	var hazard: MeshInstance3D = MeshInstance3D.new()
	var hm: BoxMesh = BoxMesh.new()
	hm.size = Vector3(5.9, 0.7, 0.05)
	hazard.mesh = hm
	hazard.material_override = MatLib.hazard_material()
	hazard.position = Vector3(0, 0.5, 0.18)
	body.add_child(hazard)
	var handle: MeshInstance3D = MeshInstance3D.new()
	var hg: BoxMesh = BoxMesh.new()
	hg.size = Vector3(1.6, 0.12, 0.14)
	handle.mesh = hg
	handle.material_override = MatLib.steel()
	handle.position = Vector3(0, 1.25, 0.27)
	body.add_child(handle)
	for sx in [-0.8, 0.8]:
		var bracket: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(0.14, 0.32, 0.12)
		bracket.mesh = bm
		bracket.material_override = dark
		bracket.position = Vector3(sx, 1.3, 0.21)
		body.add_child(bracket)
	var label: Label3D = Label3D.new()
	label.text = "R-05 · 深层隔离闸"
	label.font = kit.font
	label.font_size = 44
	label.pixel_size = 0.0034
	label.modulate = Color(0.82, 0.86, 0.8)
	label.outline_size = 4
	label.position = Vector3(0, 2.7, 0.19)
	label.double_sided = false
	body.add_child(label)
	# handle interaction area
	area = Area3D.new()
	area.name = "DoorHandleArea"
	area.position = Vector3(0, 1.4, 0.8)
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitorable = true
	var sph: SphereShape3D = SphereShape3D.new()
	sph.radius = 1.1
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = sph
	area.add_child(col)
	add_child(area)
	add_to_group("interactable")
	# caution light
	kit.omni(Vector3(0, 4.0, 0.7), Color(1.0, 0.4, 0.15), 1.2, 6.0, false, "DoorLamp")
	anchor = Transform3D(Basis(), to_global(Vector3(0, 0, 1.65)))


func setup(p_player: PlayerController, p_audio: AudioDirector) -> void:
	_audio = p_audio
	anchor = Transform3D(Basis(), to_global(Vector3(0, 0, 1.65)))
	if p_player != null:
		bind_player(p_player)


func bind_player(p: PlayerController) -> void:
	player = p
	if player == null:
		return
	if not player.operate_stopped.is_connected(_on_stopped):
		player.operate_stopped.connect(_on_stopped)


func get_prompt() -> String:
	if is_opened:
		return "通道已开启"
	if active:
		return ""
	return "E 抓住闸门手柄，向上推开"


func interact(p: PlayerController) -> void:
	if is_opened or active or p.operating:
		return
	active = true
	p.enter_operate(anchor, self, 0.0, 0.55)
	p.hands.set_state("push")


func _on_stopped(target: Node) -> void:
	if target == self:
		active = false


func _player_in_doorway() -> bool:
	if not is_inside_tree() or body == null:
		return false
	if _door_probe_shape == null:
		_door_probe_shape = BoxShape3D.new()
		_door_probe_shape.size = Vector3(5.9, 2.0, 0.9)
	if _door_probe_query == null:
		_door_probe_query = PhysicsShapeQueryParameters3D.new()
		_door_probe_query.shape = _door_probe_shape
		_door_probe_query.collision_mask = 2
		_door_probe_query.collide_with_bodies = true
		_door_probe_query.collide_with_areas = false
	_door_probe_query.transform = Transform3D(Basis(), global_position + Vector3(0.0, 1.0, 0.0))
	return not get_world_3d().direct_space_state.intersect_shape(_door_probe_query, 1).is_empty()


func _physics_process(delta: float) -> void:
	if not _built:
		return
	var moving: bool = false
	var occupied: bool = _player_in_doorway()
	if active and not is_opened:
		var push: float = Input.get_axis("move_back", "move_forward")
		if push > 0.1:
			progress = clampf(progress + delta * 0.34 * push, 0.0, 1.0)
			moving = true
		elif progress > 0.0 and not occupied:
			progress = clampf(progress - delta * 0.045, 0.0, 1.0)
			moving = true
		if progress >= 0.999:
			_lock_open()
	else:
		if not is_opened and progress > 0.0 and not occupied:
			progress = clampf(progress - delta * 0.05, 0.0, 1.0)
			moving = true
	if body != null:
		var target_y: float = progress * 3.55
		if target_y < body.position.y and occupied:
			target_y = body.position.y
		body.position.y = move_toward(body.position.y, target_y, 3.6 * delta)
		if moving:
			_rattle += delta * 18.0
			body.position.x = sin(_rattle) * 0.007
		else:
			body.position.x = move_toward(body.position.x, 0.0, 0.25 * delta)
	progress_changed.emit(progress)
	if moving and _audio != null:
		_audio.tick_door_grind(delta)
	elif _audio != null:
		_audio.stop_door_grind()


func _lock_open() -> void:
	if is_opened:
		return
	is_opened = true
	progress = 1.0
	active = false
	if player != null and player.operating:
		player.stop_operating()
	opened.emit()
	if _audio != null:
		_audio.play_sfx("door_latch", global_position, -6.0)


func reset_state() -> void:
	is_opened = false
	active = false
	progress = 0.0
	if body != null:
		body.position = Vector3.ZERO
	if area != null:
		area.collision_layer = 8
	if _audio != null:
		_audio.stop_door_grind()


func force_open() -> void:
	is_opened = true
	active = false
	progress = 1.0
	if body != null:
		body.position = Vector3(0, 3.55, 0)
	if area != null:
		area.collision_layer = 0
	if _audio != null:
		_audio.stop_door_grind()


## Authoritative state for the co-op snapshot. The host is the only process that
## physically pushes this shutter, so clients need it published or they stay
## outside a closed door.
func snapshot() -> Dictionary:
	return {
		"progress": progress,
		"opened": is_opened,
	}


## Client mirror. `force_open()` is used rather than `_lock_open()` so a late
## join lands on the fully raised panel instead of replaying the animation.
func apply_snapshot(data: Dictionary) -> void:
	if data.is_empty():
		return
	if bool(data.get("opened", false)):
		if not is_opened:
			force_open()
		return
	var p: float = clampf(float(data.get("progress", 0.0)), 0.0, 1.0)
	progress = p
	if body != null and not is_opened:
		body.position.y = lerpf(0.0, 3.55, p)
