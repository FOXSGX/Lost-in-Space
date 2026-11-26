extends SceneTree

# Reproduces the large white polygon seen in the recorded full run at ~73 m and
# isolates which node owns it by hiding groups one at a time.

const CART := preload("res://scripts/moving_cart.gd")

var app: Node
var scene: Node3D
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
	app = (load("res://resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	scene = app.get("stage") as Node3D
	var cart: AnimatableBody3D = scene.get("cart") as AnimatableBody3D
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	cart.set("distance", 73.0)
	cart.set("running", false)
	cart.global_transform = CART.route_pose(73.0)
	cart.reset_physics_interpolation()
	player.call("restore_at", cart.call("to_global", Vector3(1.0, 1.91, 1.6)) as Vector3)
	player.set("_camera_yaw_target", -PI * 0.5)
	await _frames(90)
	await _shot("a_before.png")

	var cart_meshes: Array[Node] = cart.find_children("*", "MeshInstance3D", true, false)
	for node: Node in cart_meshes:
		(node as MeshInstance3D).visible = false
	await _shot("b_cart_hidden.png")
	for node: Node in cart_meshes:
		(node as MeshInstance3D).visible = true

	var cave: Node3D = null
	for node: Node in scene.find_children("*", "Node3D", true, false):
		if node.has_method("nearest_s"):
			cave = node as Node3D
	if cave != null:
		cave.visible = false
	await _shot("c_cave_hidden.png")
	if cave != null:
		cave.visible = true

	print("WHITE_SLAB_PROBE_DONE")
	current_scene = null
	app.queue_free()
	await _frames(3)
	quit(0)
