class_name WeightCart
extends Node3D

## A 2.4-tonne counterweight trolley on a two-rail track. Position is the
## authoritative gameplay value; motion uses velocity + acceleration so the cart
## has real inertia, and hitting an end stop hard is reported as a resonance
## shock instead of silently clamping.
##
## The cart is modelled around the track: four flanged wheels sit on two rails at
## z = +/-0.45, the frame straddles them, and the drive drum/cable runs above the
## rail so nothing intersects the sleepers or the trestles.

signal endstop_hit(side: int, speed: float)

const INNER_X := 6.3
const OUTER_X := 9.3
const RAIL_TOP_Y := 2.60
const RAIL_HALF_GAUGE := 0.45

var side_sign: float = 1.0
var p: float = 0.5
var velocity: float = 0.0
var target_velocity: float = 0.0
var wheel_nodes: Array[Node3D] = []
var lamp: MeshInstance3D
var warning_plate: MeshInstance3D
var kit: WorldKit
var _built: bool = false
var _last_end: int = 0
var _cart_body: AnimatableBody3D


func _ready() -> void:
	if not _built:
		build()


func setup(p_side_sign: float, p_initial: float) -> void:
	side_sign = p_side_sign
	p = clampf(p_initial, 0.0, 1.0)
	if not _built:
		build()
	_apply_position()


func build() -> void:
	if _built:
		return
	_built = true
	position.y = RAIL_TOP_Y
	kit = WorldKit.new(self)
	_cart_body = AnimatableBody3D.new()
	_cart_body.name = "WeightCartBody"
	_cart_body.sync_to_physics = false
	_cart_body.collision_layer = 8
	_cart_body.collision_mask = 0
	var cart_col: CollisionShape3D = CollisionShape3D.new()
	cart_col.name = "CartBodyShape"
	var cart_box: BoxShape3D = BoxShape3D.new()
	cart_box.size = Vector3(1.76, 1.45, 1.34)
	cart_col.shape = cart_box
	cart_col.position = Vector3(0.0, 1.00, 0.0)
	_cart_body.add_child(cart_col)
	add_child(_cart_body)
	var dark: Material = MatLib.dark_steel()
	var steel: Material = MatLib.steel()
	var tungsten: Material = MatLib.metal(Color(0.20, 0.21, 0.225), 0.30, 0.92, 0.35)
	var bronze: Material = MatLib.bronze()
	# running gear: four flanged wheels on the two rails
	for sx in [-0.55, 0.55]:
		for sz in [-RAIL_HALF_GAUGE, RAIL_HALF_GAUGE]:
			var wheel: Node3D = Node3D.new()
			wheel.name = "Wheel"
			wheel.position = Vector3(sx, 0.22, sz)
			add_child(wheel)
			var wheel_kit: WorldKit = WorldKit.new(wheel)
			wheel_kit.cylinder("WheelBody", 0.22, 0.13, Vector3.ZERO, MatLib.metal(Color(0.20, 0.21, 0.22), 0.42, 0.75, 0.5), Vector3(deg_to_rad(90), 0, 0), false, 20)
			wheel_kit.cylinder("WheelHub", 0.07, 0.15, Vector3.ZERO, bronze, Vector3(deg_to_rad(90), 0, 0), false, 12)
			wheel_kit.torus("WheelRim", 0.205, 0.014, Vector3.ZERO, MatLib.steel(), Basis(Vector3.RIGHT, PI * 0.5), 24, 5)
			# flange on the inboard face keeps the wheel on the rail
			wheel_kit.cylinder("Flange", 0.25, 0.03, Vector3(0, 0, -0.075 if sz > 0 else 0.075), bronze, Vector3(deg_to_rad(90), 0, 0), false, 18)
			wheel_nodes.append(wheel)
		# axle across the gauge
		kit.cylinder("Axle", 0.045, RAIL_HALF_GAUGE * 2.0, Vector3(sx, 0.22, 0), steel, Vector3(deg_to_rad(90), 0, 0), false, 10)
	# bogie / chassis: bottom edge clears the wheel tops
	kit.box("Bogie", Vector3(1.5, 0.22, 1.30), Vector3(0, 0.55, 0), dark, Vector3.ZERO, false)
	kit.box("Chassis", Vector3(1.55, 0.30, 1.18), Vector3(0, 0.80, 0), MatLib.painted_steel(Color(0.42, 0.30, 0.12)), Vector3.ZERO, false)
	kit.box("Deck", Vector3(1.72, 0.10, 1.34), Vector3(0, 0.99, 0), steel, Vector3.ZERO, false)
	for sx in [-0.80, 0.80]:
		kit.box("SideFrame", Vector3(0.09, 0.52, 1.22), Vector3(sx, 0.78, 0), dark, Vector3.ZERO, false)
	# weight stack
	for i in range(3):
		var y: float = 1.12 + float(i) * 0.17
		kit.box("WeightPlate", Vector3(1.56, 0.15, 1.06), Vector3(0, y, 0), tungsten if i % 2 == 0 else MatLib.metal(Color(0.30, 0.29, 0.26), 0.34, 0.85, 0.4), Vector3.ZERO, false)
		kit.box("WeightBand", Vector3(1.60, 0.07, 0.10), Vector3(0, y, -0.52), bronze, Vector3.ZERO, false)
		kit.box("WeightBand", Vector3(1.60, 0.07, 0.10), Vector3(0, y, 0.52), bronze, Vector3.ZERO, false)
	kit.box("TopClamp", Vector3(0.52, 0.22, 0.52), Vector3(0, 1.66, 0), MatLib.painted_steel(Color(0.55, 0.32, 0.08)), Vector3.ZERO, false)
	kit.cylinder("ClampBolt", 0.10, 0.30, Vector3(0, 1.81, 0), bronze, Vector3.ZERO, false, 10)
	# hazard faces toward the operator (+Z) and away (-Z)
	warning_plate = kit.box("HazardFace", Vector3(1.12, 0.30, 0.04), Vector3(0, 0.78, 0.62), MatLib.hazard_material(), Vector3.ZERO, false)
	kit.box("HazardFaceBack", Vector3(1.12, 0.30, 0.04), Vector3(0, 0.78, -0.62), MatLib.hazard_material(), Vector3.ZERO, false)
	# drive drum + cable over the rail
	kit.cylinder("CableDrum", 0.17, 0.36, Vector3(0, 0.52, 0), MatLib.painted_steel(Color(0.28, 0.24, 0.16)), Vector3(deg_to_rad(90), 0, 0), false, 14)
	for sz in [-0.30, 0.30]:
		kit.beam("DriveCable", Vector3(-2.0, 0.44, sz), Vector3(2.0, 0.44, sz), 0.018, MatLib.steel(), false, 6)
	# buffer beams
	for sx in [-0.92, 0.92]:
		kit.box("BufferBeam", Vector3(0.14, 0.34, 1.24), Vector3(sx, 0.64, 0), MatLib.hazard_material(), Vector3.ZERO, false)
	# position lamp
	lamp = MeshInstance3D.new()
	var lamp_mesh: SphereMesh = SphereMesh.new()
	lamp_mesh.radius = 0.08
	lamp_mesh.height = 0.16
	lamp_mesh.radial_segments = 10
	lamp.mesh = lamp_mesh
	lamp.material_override = MatLib.emissive(Color(0.2, 0.9, 1.0), 2.0)
	lamp.position = Vector3(0, 1.98, 0)
	add_child(lamp)
	# label
	var label: Label3D = Label3D.new()
	label.text = "配重 2.4t"
	label.font = kit.font
	label.font_size = 30
	label.pixel_size = 0.0026
	label.modulate = Color(0.95, 0.88, 0.6)
	label.position = Vector3(0, 1.30, 0.60)
	label.outline_size = 4
	label.outline_modulate = Color(0, 0, 0, 0.8)
	add_child(label)
	_apply_position()


func set_drive(new_target_velocity: float, delta: float) -> void:
	target_velocity = clampf(new_target_velocity, -0.30, 0.30)
	var accel: float = 0.62 if absf(target_velocity) > 0.001 else 0.42
	velocity = move_toward(velocity, target_velocity, accel * delta)
	if absf(velocity) < 0.0005 and absf(target_velocity) < 0.0005:
		velocity = 0.0
	var old: float = p
	p = clampf(p + velocity * delta, 0.0, 1.0)
	if p <= 0.001 or p >= 0.999:
		var end: int = 0 if p <= 0.001 else 1
		if end != _last_end and absf(velocity) > 0.16:
			endstop_hit.emit(end, absf(velocity))
			velocity = 0.0
		_last_end = end
	elif p > 0.05 and p < 0.95:
		_last_end = -1
	if not is_equal_approx(old, p):
		_apply_position()
	var spin: float = (p - old) * 26.0
	for wheel in wheel_nodes:
		wheel.rotation.z -= spin * side_sign


func set_p(new_p: float) -> void:
	p = clampf(new_p, 0.0, 1.0)
	velocity = 0.0
	target_velocity = 0.0
	_apply_position()


func get_p() -> float:
	return p


func _apply_position() -> void:
	position.x = side_sign * (INNER_X + p * (OUTER_X - INNER_X))


func reset_state(new_p: float) -> void:
	set_p(new_p)
	_last_end = -1


func set_lamp_color(col: Color, energy: float = 2.0) -> void:
	if lamp != null:
		lamp.material_override = MatLib.emissive(col, energy)



