extends "res://tests/test_moving_cart.gd"

# Identify what actually occupies the dark rectangle: tint cart visual meshes,
# then the tunnel meshes, and sample the same screen point each time.
const SAMPLE: Vector2i = Vector2i(620, 540)

func tint(group: String, color: Color) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var count: int = 0
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var path: String = str(mesh.get_path())
		if group == "cart" and path.contains("MovingCart/"):
			mesh.material_override = mat
			count += 1
		elif group == "tunnel" and path.contains("StationaryCave/"):
			mesh.material_override = mat
			count += 1
	print("TINTED ", group, " meshes=", count)

func sample(label: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	print("SAMPLE ", label, " = ", image.get_pixel(SAMPLE.x, SAMPLE.y))

func run() -> void:
	await boot()
	await travel(Vector3(1, 0, 1.55))
	await frames(20)
	await sample("baseline")
	tint("cart", Color(1, 0, 1))
	await sample("cart_magenta")
	tint("tunnel", Color(0, 1, 0))
	await sample("tunnel_green")
	await shot("both_tinted")
	await finish()
