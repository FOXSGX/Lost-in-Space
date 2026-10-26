extends SceneTree

# Visual capture for the winch prototype. Renders the real scene at three
# mission states with an independent audit camera, so the mechanism can be
# judged without the player rig pushing the lens through geometry.

var app: Node3D
var rig: Node3D
var player: CharacterBody3D
var camera: Camera3D
var output: String

func _initialize() -> void:
	run.call_deferred()

func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("res://resonance_03.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(12)
	rig = app.get("rig") as Node3D
	player = app.get("player") as CharacterBody3D
	player.set("paused", true)
	(player.get("camera") as Camera3D).current = false
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.near = 0.05
	camera.far = 160.0
	app.add_child(camera)
	camera.current = true

	await shot("01_jammed", Vector3(0.0, 7.2, 6.6), Vector3(3.0, 0.6, 0.0))
	await shot("02_winch", Vector3(-4.8, 2.2, 5.0), Vector3(-2.4, 1.0, 3.2))

	# Hook the far eye through the public API.
	var far_anchor: Node3D = rig.call("find_anchor", "eye_far") as Node3D
	player.global_position = (far_anchor.call("attach_point") as Vector3) + Vector3(0, 0, 1.4)
	await frames(2)
	rig.call("attach_cable", "eye_far")
	await frames(6)
	await shot("03_hooked", Vector3(-4.2, 4.4, 6.2), Vector3(2.4, 0.7, 0.0))

	# Take the console and haul to the middle of the swing.
	var console: Vector3 = (app.get("winch_station") as Node3D).global_position
	player.global_position = console + Vector3(0, 0, 1.6)
	app.set("at_console", true)
	await frames(3)
	Input.action_press("winch_haul")
	for _i: int in range(600):
		await physics_frame
		if float((rig.call("alignment_state") as Dictionary).get("angle_deg", 15.0)) <= 7.0:
			break
	Input.action_release("winch_haul")
	await frames(6)
	await shot("04_hauling", Vector3(-2.4, 4.0, 6.4), Vector3(3.0, 0.6, 0.0))

	# Finish the haul, release, settle, then pin the rail.
	Input.action_press("winch_haul")
	for _i: int in range(600):
		await physics_frame
		if float((rig.call("alignment_state") as Dictionary).get("angle_deg", 15.0)) <= 1.4:
			break
	Input.action_release("winch_haul")
	await frames(120)
	app.set("at_console", false)
	rig.call("try_install_lock")
	await frames(30)
	await shot("05_locked", Vector3(4.0, 2.4, 4.4), Vector3(6.6, 0.6, 0.6))
	await shot("06_locked_overview", Vector3(1.0, 6.4, 6.8), Vector3(3.2, 0.6, 0.0))

	print("CAPTURE_DONE ", output)
	current_scene = null
	app.queue_free()
	await frames(3)
	quit(0)

func shot(name: String, at: Vector3, look: Vector3) -> void:
	camera.look_at_from_position(at, look, Vector3.UP)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image != null:
		image.save_png(output.path_join(name + ".png"))
		print("CAPTURE ", name, " ", image.get_size())
