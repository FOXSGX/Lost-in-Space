extends SceneTree

# Parameter sweep for the cart deck. The deck is authored at albedo 0.026 inside
# an open shell, and its baked irradiance is zero because the source diorama was
# baked with overhead sun. Both terms need a floor; this measures how much rather
# than guessing, so the result is a legible deck instead of a black silhouette.

const CART := preload("res://scripts/moving_cart.gd")

var app: Node
var scene: Node3D
var camera: Camera3D
var output: String

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("res://resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	scene = app.get("stage") as Node3D
	await _frames(45)
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	player.set("paused", true)
	scene.set("input_blocked", true)
	(player.get("camera") as Camera3D).current = false
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 160.0
	scene.add_child(camera)
	camera.current = true
	(scene.get("hud") as CanvasLayer).visible = false
	var route: Vector3 = CART.route_pose(0.0).origin + Vector3(0, 0, 2.2)
	# Look straight down at the deck from just above it: pure deck pixels.
	camera.look_at_from_position(route + Vector3(-1.0, 3.35, 0.1), route + Vector3(-0.2, 1.86, 1.2), Vector3.UP)
	await _frames(6)

	# Every cart material shares the M23_A_ prefix.
	var cart_materials: Array[ShaderMaterial] = []
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mat: Material = (node as MeshInstance3D).material_override
		if mat is ShaderMaterial and not cart_materials.has(mat as ShaderMaterial):
			cart_materials.append(mat as ShaderMaterial)
	print("CART_MATERIALS ", cart_materials.size())

	var combinations: Array = [
		[0.0, 0.0], [0.09, 0.0], [0.11, 0.0],
		[0.0, 0.6], [0.0, 1.2],
		[0.09, 0.6], [0.11, 0.8], [0.13, 1.0],
	]
	for combo: Array in combinations:
		var floor_value: float = float(combo[0])
		var ambient: float = float(combo[1])
		for mat: ShaderMaterial in cart_materials:
			mat.set_shader_parameter("albedo_floor", floor_value)
			mat.set_shader_parameter("ambient_floor", ambient)
		await _frames(3)
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var label: String = "floor%.2f_amb%.2f" % [floor_value, ambient]
		image.save_png(output.path_join(label + ".png"))
		var sum: float = 0.0
		var dark: int = 0
		var total: int = 0
		for y: int in range(0, image.get_height(), 8):
			for x: int in range(0, image.get_width(), 8):
				var c: Color = image.get_pixel(x, y)
				var luma: float = c.get_luminance()
				sum += luma
				if luma < 0.055: dark += 1
				total += 1
		print("  %-22s mean_luma=%.4f dark_frac=%.3f" % [label, sum / float(total), float(dark) / float(total)])
	print("SWEEP_PARAMS_DONE")
	quit(0)
