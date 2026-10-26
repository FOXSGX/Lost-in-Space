extends SceneTree

# Standalone check of the generated corridor before it is wired into the game.

const CART := preload("res://scripts/moving_cart.gd")

var output: String
var host: Node3D
var camera: Camera3D

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	host = Node3D.new()
	root.add_child(host)
	current_scene = host
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Bright magenta background: any surviving hole is impossible to miss.
	env.background_color = Color(1.0, 0.0, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.63, 0.72)
	env.ambient_light_energy = 0.30
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = env
	host.add_child(world)
	var tunnel: Node3D = preload("res://scripts/cave_tunnel.gd").new() as Node3D
	tunnel.name = "Cave"
	host.add_child(tunnel)
	var started: int = Time.get_ticks_msec()
	tunnel.call("build", host)
	print("CAVE_BUILD_MS ", Time.get_ticks_msec() - started, " triangles=", tunnel.get("triangles"))
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 200.0
	camera.current = true
	host.add_child(camera)
	await _frames(6)
	for s: float in [0.0, 20.0, 40.0, 60.0, 90.0]:
		var route: Vector3 = CART.route_pose(s).origin + Vector3(0, 0, 2.2)
		var tag: String = "%03d" % int(s)
		_look(route + Vector3(-1.2, 3.5, -0.1), route + Vector3(14.0, 1.9, 0.0))
		await _shot(tag + "_a_deck")
		_look(route + Vector3(4.0, 2.6, 0.0), route + Vector3(22.0, 1.2, 0.0))
		await _shot(tag + "_b_forward")
		_look(route + Vector3(-2.0, 1.05, -3.4), route + Vector3(9.0, 0.15, 0.6))
		await _shot(tag + "_d_roadbed")
		_look(route + Vector3(-6.0, 7.4, -4.0), route + Vector3(8.0, 1.2, 0.4))
		await _shot(tag + "_e_overview")
		_look(route + Vector3(3.2, 3.3, 0.0), route + Vector3(-16.0, 1.6, 0.0))
		await _shot(tag + "_f_reverse")
	print("CAVE_PROBE_DONE")
	quit(0)

func _look(at: Vector3, target: Vector3) -> void:
	camera.look_at_from_position(at, target, Vector3.UP)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
