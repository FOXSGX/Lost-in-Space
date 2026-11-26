extends SceneTree

# Visual audit sweep. Drives the real scene, parks the cart at 10 stations along
# the 90 m route and renders 5 fixed inspection angles at each one. Nothing here
# asserts; it only produces frames a human (or the dark-coverage analyser) can
# actually judge. An independent audit camera is used so the player rig's
# collision-avoidance cannot hide a wall by pushing the lens through it.

const CART := preload("res://scripts/moving_cart.gd")
const STATIONS: Array[float] = [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0]

var app: Node
var scene: Node3D
var cart: AnimatableBody3D
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
	cart = scene.get("cart") as AnimatableBody3D
	var player: CharacterBody3D = scene.get("player") as CharacterBody3D
	await _frames(45)
	# The player rig would otherwise steal the viewport every physics tick.
	player.set("paused", true)
	scene.set("input_blocked", true)
	(player.get("camera") as Camera3D).current = false
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 160.0
	scene.add_child(camera)
	camera.current = true
	# Hide the HUD so it cannot mask the geometry being judged.
	(scene.get("hud") as CanvasLayer).visible = false

	for s: float in STATIONS:
		_park(s)
		await _frames(6)
		var tag: String = "%03d" % int(s)
		await _shot(tag + "_a_deck")
		await _shot(tag + "_b_forward")
		await _shot(tag + "_c_side")
		await _shot(tag + "_d_roadbed")
		await _shot(tag + "_e_overview")
		await _shot(tag + "_f_reverse")

	print("SWEEP_DONE frames=", STATIONS.size() * 6)
	scene = null
	current_scene = null
	app.queue_free()
	await _frames(4)
	quit(0)

func _park(s: float) -> void:
	cart.set("distance", s)
	cart.set("speed", 0.0)
	cart.set("running", false)
	cart.set("arrived", s >= 90.0)
	cart.global_transform = CART.route_pose(s)
	cart.reset_physics_interpolation()

func _pose(at: Vector3, look: Vector3) -> void:
	if at.distance_to(look) < 0.05:
		look = at + Vector3(1, 0, 0)
	camera.look_at_from_position(at, look, Vector3.UP)

func _shot(name: String) -> void:
	var s: float = float(name.to_int())
	var route: Vector3 = CART.route_pose(s).origin + Vector3(0, 0, 2.2)
	match name.get_slice("_", 1):
		"a":  # eye height on the deck, looking down the track
			_pose(route + Vector3(-1.2, 3.5, -0.1), route + Vector3(14.0, 1.9, 0.0))
		"b":  # track ahead from just above the deck
			_pose(route + Vector3(4.0, 2.6, 0.0), route + Vector3(22.0, 1.2, 0.0))
		"c":  # side elevation of the cart against the near wall
			_pose(route + Vector3(1.0, 2.7, -4.0), route + Vector3(1.0, 1.9, 0.0))
		"d":  # low angle on the roadbed and rail feet
			_pose(route + Vector3(-2.0, 1.05, -3.4), route + Vector3(9.0, 0.15, 0.6))
		"e":  # high overview of the whole cross-section, still under the roof
			_pose(route + Vector3(-4.6, 4.6, -3.0), route + Vector3(8.0, 1.2, 0.4))
		"f":  # reverse view back down the track
			_pose(route + Vector3(3.2, 3.3, 0.0), route + Vector3(-16.0, 1.6, 0.0))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
