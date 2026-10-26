extends SceneTree

# Two-question obstruction probe:
#   1. hide every mesh under the cart, re-render -> is the obstruction the cart?
#   2. hide every mesh outside the cart, re-render -> is it the cave?
# It also prints the meshes nearest to the camera, with distance, so the object
# can be named without another round trip.

var app: Node
var output: String

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name))

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	var scene: Node3D = app.get("stage") as Node3D
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	var cart: AnimatableBody3D = scene.get("cart") as AnimatableBody3D
	player.call("restore_at", cart.call("to_global", Vector3(1.0, 1.91, 1.6)) as Vector3)
	cart.call("start")
	await _frames(200)
	var camera: Camera3D = player.get("camera") as Camera3D
	await _shot("a_before.png")

	var cart_meshes: Array[Node] = cart.find_children("*", "MeshInstance3D", true, false)
	for node: Node in cart_meshes:
		(node as MeshInstance3D).visible = false
	await _shot("b_cart_hidden.png")
	for node: Node in cart_meshes:
		(node as MeshInstance3D).visible = true

	var others: Array[Node] = []
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		if node.is_ancestor_of(cart) or cart.is_ancestor_of(node):
			continue
		others.append(node)
		(node as MeshInstance3D).visible = false
	await _shot("c_cave_hidden.png")
	for node: Node in others:
		(node as MeshInstance3D).visible = true

	var ranked: Array = []
	for node: Node in cart.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		ranked.append({"name": str(mesh.name), "dist": box.get_center().distance_to(camera.global_position), "size": box.size})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	for i: int in range(mini(10, ranked.size())):
		print("NEAREST ", ranked[i]["name"], " dist=%.2f size=%s" % [float(ranked[i]["dist"]), str(ranked[i]["size"])])
	print("PROBE_OBSTRUCTION_DONE")
	current_scene = null
	app.queue_free()
	await _frames(3)
	quit(0)
