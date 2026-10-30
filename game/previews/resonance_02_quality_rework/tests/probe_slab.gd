extends "res://tests/test_moving_cart.gd"

# Decisive visibility probe: paint the corridor slab magenta and report whether
# any magenta pixel reaches the frame, plus what the camera actually looks at.
func run() -> void:
	await boot()
	await travel(Vector3(1, 0, 1.55))
	await frames(20)
	var tint: StandardMaterial3D = StandardMaterial3D.new()
	tint.albedo_color = Color(1, 0, 1)
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh is BoxMesh:
			var size: Vector3 = (mesh.mesh as BoxMesh).size
			if absf(size.x - 114.0) < 0.5:
				mesh.material_override = tint
				print("TINTED_SLAB at ", mesh.global_position, " size ", size)
	await frames(10)
	await shot("magenta")
	var image: Image = root.get_texture().get_image()
	var found: int = 0
	for y: int in range(0, image.get_height(), 4):
		for x: int in range(0, image.get_width(), 4):
			var c: Color = image.get_pixel(x, y)
			if c.r > 0.35 and c.g < 0.15 and c.b > 0.35:
				found += 1
	print("MAGENTA_PIXELS ", found)
	# Report the camera pose so we know what is in frame.
	var cam: Camera3D = player.get("camera") as Camera3D
	print("CAMERA at ", cam.global_position, " forward ", -cam.global_basis.z)
	print("PLAYER at ", player.global_position)
	await finish()
