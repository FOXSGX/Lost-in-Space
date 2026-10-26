extends SceneTree

# Diagnostic renders from outside the set. The point is to see the actual shell
# of the generated tunnel, which no in-corridor camera can show.

const CART := preload("res://scripts/moving_cart.gd")

var output: String

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var root3d: Node3D = Node3D.new()
	root.add_child(root3d)
	current_scene = root3d
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.45, 0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = env
	root3d.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.6
	root3d.add_child(sun)
	var tunnel: Node3D = (load("res://assets/moving_tunnel.scn") as PackedScene).instantiate() as Node3D
	root3d.add_child(tunnel)
	# Plain grey so the silhouette, not the baked look, is what we judge.
	var grey: StandardMaterial3D = StandardMaterial3D.new()
	grey.albedo_color = Color(0.72, 0.74, 0.78)
	grey.roughness = 0.9
	for node: Node in tunnel.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = grey
	var camera: Camera3D = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 400.0
	camera.current = true
	root3d.add_child(camera)
	await _frames(4)
	var views: Dictionary = {
		"top": [Vector3(45, 90, 2), Vector3(45, 0, 2)],
		"front": [Vector3(45, 14, -70), Vector3(45, 2, 2)],
		"back": [Vector3(45, 14, 70), Vector3(45, 2, 2)],
		"iso": [Vector3(-40, 45, -45), Vector3(40, 2, 2)],
		"low_front": [Vector3(45, 3.5, -46), Vector3(45, 2, 2)],
	}
	for name: String in views:
		var v: Array = views[name]
		camera.look_at_from_position(v[0] as Vector3, v[1] as Vector3, Vector3.UP)
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("shell_" + name + ".png"))
	print("SHELL_DONE")
	quit(0)

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame
