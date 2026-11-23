class_name Act1WindCrate
extends CharacterBody3D

## A light instrument crate that really slides, tips over the catwalk edge and
## falls under the fan's spatial wind. This is server-simulated; clients receive
## transforms from the host.

var stage: Node
var secured := false
var base_position := Vector3.ZERO
var _home := Vector3.ZERO
var _mesh: MeshInstance3D
var _strap: Node3D
var _last_wind := Vector3.ZERO


func setup(p_stage: Node, pos: Vector3) -> void:
	stage = p_stage
	name = "LooseInstrumentCrate"
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 16
	floor_snap_length = 0.2
	_home = pos
	global_position = pos
	_build_visual()
	_build_collision()


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.92, 0.78, 0.68)
	_mesh.mesh = bm
	_mesh.material_override = Act1MatLib.painted_steel(Color(0.39, 0.35, 0.21))
	add_child(_mesh)
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(0.94, 0.09, 0.70)
	band.mesh = band_mesh
	band.material_override = Act1MatLib.hazard()
	band.position.y = 0.22
	add_child(band)
	var label := Label3D.new()
	label.text = "SAMPLE 7"
	label.font = _font()
	label.font_size = 30
	label.pixel_size = 0.0024
	label.modulate = Color(0.90, 0.78, 0.45)
	label.position = Vector3(0, 0.03, 0.36)
	add_child(label)
	_strap = Node3D.new()
	_strap.name = "RetentionStrap"
	add_child(_strap)


func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.92, 0.78, 0.68)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.39, 0)
	add_child(col)


func set_secured(value: bool) -> void:
	secured = value
	if value:
		velocity = Vector3.ZERO
		if _strap != null:
			_strap.visible = true


func _physics_process(delta: float) -> void:
	if stage == null:
		return
	if secured:
		velocity = Vector3.ZERO
		return
	if not bool(stage.call("is_host_authority")):
		return
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.4
	var wind := stage.call("get_wind_acceleration", global_position, false) as Vector3
	_last_wind = wind
	velocity.x += wind.x * delta * 1.35
	velocity.z += wind.z * delta * 1.35
	var damp := 3.4 if is_on_floor() else 0.35
	velocity.x = move_toward(velocity.x, 0.0, damp * delta)
	velocity.z = move_toward(velocity.z, 0.0, damp * delta)
	move_and_slide()
	if global_position.y < -5.0:
		global_position = _home
		velocity = Vector3.ZERO


func reset_crate() -> void:
	secured = false
	global_position = _home
	velocity = Vector3.ZERO


func snapshot() -> Dictionary:
	return {"pos": global_position, "vel": velocity, "secured": secured}


func apply_snapshot(data: Dictionary) -> void:
	global_position = data.get("pos", global_position)
	velocity = data.get("vel", velocity)
	secured = bool(data.get("secured", secured))


func _font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return font