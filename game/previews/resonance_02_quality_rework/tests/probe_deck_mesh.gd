extends SceneTree

# Lists the cart meshes whose bounding box sits at cargo-bay deck height, with
# the shader parameters actually applied. The player still reports a black deck
# surface, so this identifies which material it is instead of raising every
# material in the cart.

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func run() -> void:
	var app: Node = (load("res://resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	var scene: Node3D = app.get("stage") as Node3D
	var cart: AnimatableBody3D = scene.get("cart") as AnimatableBody3D
	await _frames(30)
	var origin: Vector3 = cart.global_position
	for node: Node in cart.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		var centre: Vector3 = box.get_center()
		var local: Vector3 = cart.to_local(centre)
		if local.y < 1.7 or local.y > 2.4 or absf(local.x) > 3.5:
			continue
		var mat: Material = mesh.material_override
		var info: String = ""
		if mat is ShaderMaterial:
			var sm: ShaderMaterial = mat as ShaderMaterial
			info = " albedo_floor=%.3f ambient_floor=%.3f metallic=%.2f" % [
				float(sm.get_shader_parameter("albedo_floor")),
				float(sm.get_shader_parameter("ambient_floor")),
				float(sm.get_shader_parameter("metallic"))]
		print("DECK_MESH ", mesh.name, " local=", local, " size=", box.size, info)
	print("PROBE_DECK_DONE")
	current_scene = null
	app.queue_free()
	await _frames(3)
	quit(0)
