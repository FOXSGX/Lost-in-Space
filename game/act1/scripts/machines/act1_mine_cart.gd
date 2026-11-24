class_name Act1MineCartRig
extends AnimatableBody3D

## The actual V2.3 open-deck transport for Act 01, at 1.0 scale, with a walkable
## deck and real hull collision. The wrapper body moves along rails and carries
## attached riders; the visual asset is never scaled down.

signal departed()
signal handoff_reached()

const CART_ORIGIN := Vector3(0, 0, -47.0)
const TUNNEL_END_Z := -63.0
const MAX_SPEED := 6.4
const ACCEL := 1.55

var stage: Node
var visual: Node3D
var launch_handle: Act1Interactable
var speed := 0.0
var departing := false
var has_departed := false
var handoff := false
var _start_z := -47.0
var _rider_offset := Vector3(0, 1.58, 2.4)
var _wheel_nodes: Array[Node3D] = []
var _wheel_spin := 0.0
var _cart_materials: Dictionary = {}


func setup(p_stage: Node) -> void:
	stage = p_stage
	name = "V23MineCart"
	collision_layer = 16
	collision_mask = 0
	sync_to_physics = false
	global_position = CART_ORIGIN
	_start_z = CART_ORIGIN.z
	_load_visual()
	_build_collision()
	_build_launch_console()
	_build_riding_lights()


func _load_visual() -> void:
	var packed := load("res://act1/moving_cart_visual.scn") as PackedScene
	if packed == null:
		push_error("V2.3 cart visual missing")
		return
	visual = packed.instantiate() as Node3D
	visual.name = "V23_Visual_1to1"
	visual.scale = Vector3.ONE
	add_child(visual)
	_adapt_materials(visual)
	for child in visual.get_children():
		if child.name.begins_with("Wheel"):
			_wheel_nodes.append(child as Node3D)


func _adapt_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				var source := mi.mesh.surface_get_material(i)
				var mat_name := source.resource_name if source != null else ""
				mi.set_surface_override_material(i, _cart_material(mat_name))
	for child in node.get_children():
		_adapt_materials(child)


func _cart_material(mat_name: String) -> StandardMaterial3D:
	if _cart_materials.has(mat_name):
		return _cart_materials[mat_name] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.resource_name = "R01_" + mat_name
	m.metallic = 0.55
	m.roughness = 0.48
	var col := Color(0.38, 0.41, 0.43)
	var emission := Color.BLACK
	var emission_energy := 0.0
	match mat_name:
		"P11_M23_A_Deck":
			col = Color(0.18, 0.20, 0.21); m.metallic = 0.35; m.roughness = 0.72
		"P11_M23_A_Paint_Orange":
			col = Color(0.66, 0.28, 0.07); m.metallic = 0.22; m.roughness = 0.52
		"P11_M23_A_Rubber":
			col = Color(0.035, 0.038, 0.04); m.metallic = 0.0; m.roughness = 0.92
		"P11_M23_A_Steel_Dark":
			col = Color(0.10, 0.115, 0.12); m.metallic = 0.78; m.roughness = 0.42
		"P11_M23_A_Steel_Edge":
			col = Color(0.36, 0.39, 0.40); m.metallic = 0.85; m.roughness = 0.30
		"P11_M23_A_Energy_Cyan":
			col = Color(0.02, 0.16, 0.17); emission = Color(0.10, 0.82, 0.92); emission_energy = 1.15; m.roughness = 0.28
		"P11_M23_A_Paint_Cream":
			col = Color(0.62, 0.60, 0.53); m.metallic = 0.10; m.roughness = 0.58
		"P11_M23_A_Accent_Cyan":
			col = Color(0.06, 0.36, 0.40); emission = Color(0.10, 0.66, 0.76); emission_energy = 0.45
		"P11_M23_A_Coupler":
			col = Color(0.22, 0.14, 0.08); m.metallic = 0.8; m.roughness = 0.48
		"P11_M23_A_Glass":
			col = Color(0.08, 0.18, 0.22, 0.55); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.roughness = 0.12; m.metallic = 0.2
		"P11_M23_A_Lamp_Amber":
			col = Color(0.32, 0.18, 0.02); emission = Color(1.0, 0.56, 0.14); emission_energy = 1.1
		"P11_M23_A_Lamp_Red":
			col = Color(0.28, 0.03, 0.02); emission = Color(1.0, 0.10, 0.05); emission_energy = 1.0
		"P11_M23_A_Paint_Yellow":
			col = Color(0.68, 0.50, 0.08); m.roughness = 0.54
		_:
			col = Color(0.30, 0.32, 0.33)
	m.albedo_color = col
	m.emission_enabled = emission_energy > 0.0
	m.emission = emission
	m.emission_energy_multiplier = emission_energy
	_cart_materials[mat_name] = m
	return m


func _build_collision() -> void:
	# Deck floor at the measured V2.3 deck height (visual bounds bottom = 0.31).
	_add_box(Vector3(9.0, 0.22, 9.2), Vector3(0, 1.40, 0), "DeckFloor")
	# Underframe blocks walking through the machine from ground level.
	_add_box(Vector3(9.7, 0.85, 3.25), Vector3(0, 0.78, 0), "Underframe")
	# Front and rear bulkheads.
	_add_box(Vector3(9.2, 2.25, 0.32), Vector3(0, 2.35, -4.55), "FrontBulkhead")
	_add_box(Vector3(9.2, 2.25, 0.32), Vector3(0, 2.35, 4.55), "RearBulkhead")
	# The west side is closed; the east side has a real boarding cut-out lined up
	# with the station platform.
	_add_box(Vector3(0.30, 2.25, 9.2), Vector3(-4.75, 2.35, 0), "WestSide")
	_add_box(Vector3(0.30, 2.25, 2.8), Vector3(4.75, 2.35, -3.1), "EastSideFront")
	_add_box(Vector3(0.30, 2.25, 2.8), Vector3(4.75, 2.35, 3.1), "EastSideRear")
	# The boarding cut-out stays clear. A knee-height invisible sill here caused
	# exactly the kind of "walk-through gap but blocked by nothing" bug this
	# rebuild is meant to remove.


func _add_box(size: Vector3, pos: Vector3, name: String) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.name = name
	col.shape = shape
	col.position = pos
	add_child(col)


func _build_launch_console() -> void:
	var console := Node3D.new()
	console.name = "LaunchConsole"
	console.position = Vector3(-3.1, 1.42, -3.2)
	add_child(console)
	var body := _mesh_box(Vector3(1.1, 1.0, 0.55), Act1MatLib.dark_steel())
	body.position = Vector3(0, 0.50, 0)
	console.add_child(body)
	var screen := _mesh_box(Vector3(0.72, 0.40, 0.05), Act1MatLib.emissive(Color(0.14, 0.80, 0.92), 1.05))
	screen.position = Vector3(0, 0.72, -0.30)
	screen.rotation.x = deg_to_rad(-12)
	console.add_child(screen)
	var lever := _mesh_cylinder(0.055, 0.70, 10, Act1MatLib.painted_steel(Color(0.82, 0.58, 0.12)))
	lever.position = Vector3(0.35, 0.35, -0.25)
	lever.rotation.x = deg_to_rad(38)
	console.add_child(lever)
	launch_handle = Act1Interactable.new()
	launch_handle.stage = stage
	launch_handle.setup("launch_cart", "E 启动发车联锁", Vector3(1.3, 1.2, 0.8))
	launch_handle.position = Vector3(0, 1.0, 0)
	launch_handle.prompt_callable = Callable(self, "_launch_prompt")
	console.add_child(launch_handle)
	launch_handle.add_focus_marker(0.22)


func _launch_prompt(_p: Node = null) -> String:
	if has_departed:
		return "列车已发车"
	if not bool(stage.call("get_flag", "power_ready")):
		return "发车联锁未得电 · 先恢复辅助电源与通风"
	if not bool(stage.call("get_flag", "chock_removed")):
		return "发车联锁：车轮止轮楔未移除"
	if not bool(stage.call("get_flag", "brake_released")):
		return "发车联锁：停车制动未释放"
	if not bool(stage.call("get_flag", "cargo_secured")):
		return "发车联锁：货舱固定带未锁定"
	if not bool(stage.call("all_active_aboard")):
		return "发车联锁：仍有队员未进入车厢"
	if float(stage.call("get_vent_pressure")) < Act1Ventilation.PRESSURE_MIN:
		return "发车联锁：通风压力不足（%d%% / 需要 ≥%d%%）· 用调速器升档" % [
			int(round(float(stage.call("get_vent_pressure")) * 100.0)),
			int(round(Act1Ventilation.PRESSURE_MIN * 100.0))]
	return "E 启动发车 · 列车前往深层矿区"


func _build_riding_lights() -> void:
	var light := OmniLight3D.new()
	light.position = Vector3(0, 3.6, 0)
	light.light_color = Color(0.35, 0.78, 0.95)
	light.light_energy = 1.2
	light.omni_range = 7.0
	light.shadow_enabled = false
	add_child(light)
	var amber := OmniLight3D.new()
	amber.position = Vector3(0, 2.8, -4.0)
	amber.light_color = Color(1.0, 0.55, 0.18)
	amber.light_energy = 0.8
	amber.omni_range = 4.2
	add_child(amber)


func begin_departure() -> void:
	if departing or has_departed:
		return
	if not bool(stage.call("all_active_aboard")):
		return
	departing = true
	has_departed = true
	stage.call("on_cart_departing")
	departed.emit()


func ride_offset_for(player: Node3D) -> Vector3:
	var local := to_local(player.global_position)
	local.y = _rider_offset.y
	if local.z > 4.2:
		local.z = 4.2
	if local.z < -4.2:
		local.z = -4.2
	if local.x > 4.2:
		local.x = 4.2
	if local.x < -4.2:
		local.x = -4.2
	return local


func is_player_aboard(pos: Vector3) -> bool:
	var local := to_local(pos)
	return local.x > -4.6 and local.x < 4.8 and local.y > 1.15 and local.y < 3.8 and local.z > -5.2 and local.z < 5.2


func get_deck_world() -> Vector3:
	return global_transform * Vector3(0, 1.42, 0)


func _physics_process(delta: float) -> void:
	if departing:
		speed = move_toward(speed, MAX_SPEED, ACCEL * delta)
		global_position.z -= speed * delta
		if _wheel_nodes.size() > 0:
			_wheel_spin -= speed * delta / 0.42
			for w in _wheel_nodes:
				w.rotation.x = _wheel_spin
		if global_position.z <= TUNNEL_END_Z and not handoff:
			handoff = true
			departing = false
			speed = 0.0
			global_position.z = TUNNEL_END_Z
			handoff_reached.emit()
	elif speed > 0.0:
		speed = move_toward(speed, 0.0, 4.0 * delta)


func snapshot() -> Dictionary:
	return {
		"pos": global_position,
		"speed": speed,
		"departing": departing,
		"departed": has_departed,
		"handoff": handoff,
	}


func apply_snapshot(data: Dictionary) -> void:
	global_position = data.get("pos", global_position)
	speed = float(data.get("speed", speed))
	departing = bool(data.get("departing", departing))
	has_departed = bool(data.get("departed", has_departed))
	handoff = bool(data.get("handoff", handoff))


func reset_cart() -> void:
	speed = 0.0
	departing = false
	has_departed = false
	handoff = false
	global_position = CART_ORIGIN


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