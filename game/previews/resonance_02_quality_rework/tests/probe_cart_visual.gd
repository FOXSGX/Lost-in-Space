extends SceneTree

# Prints the cart visual hierarchy and the meshes near the player camera, so a
# giant pale tube filling the third-person view can be identified by name
# instead of guessed at.

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
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	player.call("restore_at", cart.call("to_global", Vector3(1.0, 1.91, 1.6)) as Vector3)
	await _frames(60)
	var visual: Node3D = null
	for child: Node in cart.get_children():
		if child is Node3D and not (child is CollisionShape3D) and str(child.name) != "WheelSound":
			if child.get_child_count() > 0:
				visual = child as Node3D
	print("--- cart children ---")
	for child: Node in cart.get_children():
		print("  ", child.name, " ", child.get_class())
	if visual != null:
		print("--- visual top level (", visual.name, ") ---")
		for child: Node in visual.get_children():
			var node3d: Node3D = child as Node3D
			print("  ", child.name, " ", child.get_class(), " pos=", node3d.position if node3d else "")
			for grand: Node in child.get_children():
				var g3: Node3D = grand as Node3D
				print("     ", grand.name, " ", grand.get_class(), " pos=", g3.position if g3 else "")
			var mesh_node: MeshInstance3D = child as MeshInstance3D
			if mesh_node != null:
				var local_aabb: AABB = mesh_node.get_aabb()
				print("     AABB local=", local_aabb, " global=", mesh_node.global_transform * local_aabb)
	var camera: Camera3D = player.get("camera") as Camera3D
	print("--- meshes within 1.6 m of camera ", camera.global_position, " ---")
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var aabb: AABB = mesh.global_transform * mesh.get_aabb()
		var near: bool = aabb.grow(0.2).has_point(camera.global_position)
		if near:
			print("  NEAR ", mesh.get_path(), " aabb=", aabb)
	print("PROBE_DONE")
	current_scene = null
	app.queue_free()
	await _frames(3)
	quit(0)
