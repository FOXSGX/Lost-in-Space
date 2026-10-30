extends SceneTree

# Player-camera audit shots. This is deliberately NOT an audit camera: it uses
# the real third-person rig the player controls, so the delivered views match
# what a first-time player sees.

var app: Node3D
var player: CharacterBody3D
var rig: Node3D
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
	app = (load("resonance_03.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(40)
	player = app.get("player") as CharacterBody3D
	rig = app.get("rig") as Node3D
	player.set("paused", true)
	await shot("01_spawn")

	await place(Vector3(3.4, 0.3, 3.2), Vector3(5.8, 0.8, -1.5))
	await shot("02_rail_from_bay")
	await place(Vector3(4.6, 0.3, 1.4), Vector3(5.9, 0.7, -1.5))
	await shot("03_far_eye_close")

	await place(Vector3(-1.2, 0.3, 5.6), Vector3(-2.6, 1.1, 3.4))
	await shot("04_winch_front")
	await place(Vector3(-2.6, 0.3, 5.0), Vector3(2.5, 0.9, 0.0))
	await shot("05_console_view_to_rail")

	await place(Vector3(6.2, 0.3, 2.6), Vector3(7.05, 0.7, 1.16))
	await shot("06_lock_socket")

	# Near the far eye, with the interaction ring active.
	await place(Vector3(5.2, 0.3, 0.5), Vector3(5.9, 0.7, -1.5))
	await frames(30)
	await shot("07_near_far_eye")

	# Over-the-shoulder console view while operating.
	await place(Vector3(-1.2, 0.3, 4.7), Vector3(2.6, 0.8, 0.0))
	app.set("at_console", true)
	player.call("set_operating", app.get("winch_station"))
	await frames(40)
	player.call("update_camera", 1.0, true)
	await frames(4)
	await shot("08_console_operating")

	# Debug HUD (F3) and a real cable/rail shot for the visual quality check.
	var hud: CanvasLayer = app.get("hud") as CanvasLayer
	hud.call("toggle_debug")
	await frames(6)
	await shot("09_debug_hud")
	hud.call("toggle_debug")
	await frames(4)

	rig.call("reset_mission")
	var far_anchor: Node3D = rig.call("find_anchor", "eye_far") as Node3D
	var far_at: Vector3 = far_anchor.call("attach_point") as Vector3
	player.call("teleport_to", far_at + Vector3(0.55, 0.0, 1.45), 0.0)
	await frames(4)
	rig.call("attach_cable", "eye_far")
	await place(Vector3(-1.2, 0.3, 4.7), Vector3(2.6, 0.8, 0.0))
	app.set("at_console", true)
	player.call("set_operating", app.get("winch_station"))
	Input.action_press("winch_haul")
	for _i: int in range(600):
		await physics_frame
		var angle: float = float((rig.call("alignment_state") as Dictionary).get("angle_deg", 15.0))
		if angle <= 6.0:
			break
	Input.action_release("winch_haul")
	await frames(4)
	player.call("update_camera", 1.0, true)
	await shot("10_hauling_cable")
	app.set("at_console", false)
	player.call("set_operating", null)

	# Same debug HUD after 120 clean frames (no screenshot stalls): this is the
	# steady-state FPS reading, and the contrast with 09_debug_hud is the point.
	hud.call("toggle_debug")
	await frames(120)
	await shot("11_debug_steady")
	hud.call("toggle_debug")
	app.set("at_console", false)
	player.call("set_operating", null)

	current_scene = null
	app.queue_free()
	await frames(3)
	quit(0)

func place(at: Vector3, look: Vector3) -> void:
	var dx: float = look.x - at.x
	var dz: float = look.z - at.z
	var yaw: float = atan2(-dx, -dz)
	player.call("teleport_to", at, yaw)
	player.set("_camera_pitch", -0.24)
	player.set("_camera_pitch_target", -0.24)
	player.call("update_camera", 1.0, true)
	await frames(10)
	player.call("update_camera", 1.0, true)
	await frames(2)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image != null:
		image.save_png(output.path_join(name + ".png"))
		print("PLAYER_SHOT ", name, " ", image.get_size())
