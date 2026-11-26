extends StaticBody3D

var amount: float = 0.0
var dimensions: Vector3
var original: Vector3
var visual: MeshInstance3D
var collider: CollisionShape3D
var tint: StandardMaterial3D
var reveal_contents: bool = false

func configure(point: Vector3, size_value: Vector3) -> void:
	position = point
	original = point
	dimensions = size_value
	collision_layer = 2
	collision_mask = 0
	visual = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	tint = StandardMaterial3D.new()
	tint.albedo_color = Color("a9d9e2")
	tint.roughness = 0.28
	visual.material_override = tint
	add_child(visual)
	collider = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = dimensions
	collider.shape = shape
	add_child(collider)

func heat(seconds: float) -> void:
	apply_amount(minf(1.0, amount + seconds / (2.0 + dimensions.y * 0.7)))

func apply_amount(value: float) -> void:
	amount = clampf(value, 0, 1)
	if amount >= 0.92:
		amount = 1.0
	visible = amount < 0.98
	collision_layer = 2 if visible else 0
	if not visible:
		return
	var next: Vector3 = dimensions * Vector3(1.0 - amount * 0.25, 1.0 - amount, 1.0 - amount * 0.25)
	(visual.mesh as BoxMesh).size = next
	(collider.shape as BoxShape3D).size = next
	position = original - Vector3.UP * (dimensions.y - next.y) * 0.5
	tint.albedo_color = Color("a9d9e2").lerp(Color("488b9d"), amount)
	if reveal_contents:
		tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tint.albedo_color = Color(0.40,0.68,0.77,0.52)
