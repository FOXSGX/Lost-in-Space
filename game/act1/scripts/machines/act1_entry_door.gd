class_name Act1EntryDoor
extends AnimatableBody3D

## Heavy sliding door whose visible panel and collision are the same body. There
## is no second anonymous blocker: if the panel is open, the doorway is open.

var stage: Node
var handle: Act1Interactable
var status_light: MeshInstance3D
var open_amount := 0.0
var pusher_pid := 0
var _closed_x := 0.0
var _open_x := -5.35
var _panel: Node3D


func setup(p_stage: Node) -> void:
	stage = p_stage
	name = "IndustrialEntryDoor"
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = false
	global_position = Vector3(0, 0, 8.30)
	_closed_x = 0.0
	_build_visual()
	_build_collision()
	handle = Act1Interactable.new()
	handle.stage = stage
	handle.setup("door_handle", "按住 E 推开工业门", Vector3(1.0, 1.7, 0.8), true)
	handle.position = Vector3(1.75, 1.68, 0.38)
	handle.prompt_callable = Callable(self, "_door_prompt")
	add_child(handle)
	handle.add_focus_marker(0.24)


func _build_visual() -> void:
	_panel = Node3D.new()
	_panel.name = "DoorPanel"
	add_child(_panel)
	var dark := Act1MatLib.dark_steel()
	var yellow := Act1MatLib.painted_steel(Color(0.80, 0.57, 0.10))
	var cyan := Act1MatLib.emissive(Color(0.15, 0.78, 0.90), 1.4)
	var back := _mesh_box(Vector3(5.35, 4.65, 0.38), dark)
	back.position = Vector3(0, 2.38, 0)
	_panel.add_child(back)
	for i in range(5):
		var rib := _mesh_box(Vector3(0.16, 4.50, 0.46), Act1MatLib.steel())
		rib.position = Vector3(-2.3 + i * 1.15, 2.38, -0.03)
		_panel.add_child(rib)
	var stripe := _mesh_box(Vector3(5.30, 0.28, 0.42), Act1MatLib.hazard())
	stripe.position = Vector3(0, 0.55, 0.02)
	_panel.add_child(stripe)
	var window := _mesh_box(Vector3(1.05, 0.72, 0.03), Act1MatLib.holo(Color(0.2, 0.8, 0.95), 0.45))
	window.position = Vector3(1.45, 3.05, -0.22)
	_panel.add_child(window)
	var light := _mesh_cylinder(0.10, 0.14, 12, cyan)
	light.rotation.x = PI * 0.5
	light.position = Vector3(-1.7, 3.55, -0.24)
	_panel.add_child(light)
	# handle bar
	var bar := _mesh_cylinder(0.045, 0.74, 10, yellow)
	bar.rotation.x = PI * 0.5
	bar.position = Vector3(1.75, 1.62, 0.42)
	_panel.add_child(bar)
	# door frame / seals are static parts of the wall, not children of the moving door
	var host: Node3D = get_parent() as Node3D
	var frame_parent: Node3D = host if host != null else self
	var frame_offset: Vector3 = global_position if host != null else Vector3.ZERO
	var frame_mat := Act1MatLib.dark_steel()
	for x in [-2.90, 2.90]:
		var post := _mesh_box(Vector3(0.45, 5.1, 0.9), frame_mat)
		post.position = frame_offset + Vector3(x, 2.55, 0.0)
		frame_parent.add_child(post)
	var header := _mesh_box(Vector3(6.3, 0.55, 0.95), frame_mat)
	header.position = frame_offset + Vector3(0, 4.95, 0)
	frame_parent.add_child(header)
	var label := Label3D.new()
	label.text = "K-17  /  入口气闸  ·  ENTRY AIRLOCK"
	label.font = _font()
	label.font_size = 46
	label.pixel_size = 0.0038
	label.outline_size = 10
	label.modulate = Color(0.95, 0.74, 0.34)
	label.position = frame_offset + Vector3(0, 4.42, -0.24)
	frame_parent.add_child(label)


func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(5.35, 4.65, 0.42)
	var col := CollisionShape3D.new()
	col.name = "DoorCollision"
	col.shape = shape
	col.position = Vector3(0, 2.38, 0)
	add_child(col)


func _door_prompt(_p: Node = null) -> String:
	if open_amount > 0.96:
		return "入口已开启"
	if not bool(stage.call("get_flag", "latch_released")):
		return "门闩锁死 · 先释放右侧机械闩"
	if not bool(stage.call("get_flag", "debris_cleared")):
		return "门轨被塌落维护架压住"
	if pusher_pid != 0:
		return "E 松开 · 正在推开工业门"
	return "按住 E 推开工业门"


func begin_push(pid: int) -> bool:
	if open_amount > 0.96:
		return false
	if not bool(stage.call("get_flag", "latch_released")):
		return false
	if not bool(stage.call("get_flag", "debris_cleared")):
		return false
	pusher_pid = pid
	return true


func end_push(pid: int) -> void:
	if pusher_pid == pid:
		pusher_pid = 0


func is_open() -> bool:
	return open_amount > 0.96


func open_now() -> void:
	open_amount = 1.0
	global_position.x = _open_x
	if status_light != null:
		var m := status_light.material_override as StandardMaterial3D
		if m != null:
			m.emission = Color(0.2, 0.95, 0.45)
			m.albedo_color = Color(0.2, 0.95, 0.45) * 0.4


func _physics_process(delta: float) -> void:
	if pusher_pid != 0:
		var before := open_amount
		open_amount = move_toward(open_amount, 1.0, delta * 0.20)
		if before < 1.0 and open_amount >= 1.0:
			stage.call("on_door_opened")
	global_position.x = lerpf(_closed_x, _open_x, smoothstep(0.0, 1.0, open_amount))
	if _panel != null:
		# Reveal the movement direction as a subtle mechanical shiver.
		_panel.position.y = sin(Time.get_ticks_msec() * 0.03) * 0.003 * (1.0 - open_amount)


func snapshot() -> Dictionary:
	return {"amount": open_amount, "x": global_position.x, "pusher": pusher_pid}


func apply_snapshot(data: Dictionary) -> void:
	open_amount = float(data.get("amount", open_amount))
	global_position.x = float(data.get("x", global_position.x))
	pusher_pid = int(data.get("pusher", pusher_pid))


func reset_door() -> void:
	open_amount = 0.0
	pusher_pid = 0
	global_position.x = _closed_x


func _mesh_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


func _mesh_cylinder(radius: float, height: float, segments: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
	mi.mesh = cm
	mi.material_override = mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


func _font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return font