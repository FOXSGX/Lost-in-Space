extends "res://tests/test_cart_interactions.gd"

# Real gameplay recording for the deliverable.
# Captures the actual rendered viewport at a fixed cadence while driving the
# cart with the same input path a player uses. One clip per required topic.
var clip: String = ""
var clip_dir: String = ""
var frame_index: int = 0
var record_every: int = 3

func save_frame() -> void:
	if DisplayServer.get_name() == "headless": return
	frame_index += 1
	if frame_index % record_every != 0: return
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(clip_dir.path_join("%s_%04d.png" % [clip, frame_index / record_every]))

func spin(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await frames(1)
		await save_frame()

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	clip = args[1]
	# boot() reads args[0] for the output root and would otherwise treat the clip
	# name as the legacy mode argument, so resolve the directory up front.
	await boot()
	clip_dir = output.path_join("frames_" + clip)
	DirAccess.make_dir_recursive_absolute(clip_dir)
	await frames(30)
	await save_frame()
	match clip:
		"01_full_run":
			await record_full_run()
		"02_platform":
			await record_platform()
		"03_cargo":
			await record_cargo()
		"04_event":
			await record_event()
	await finish()

func record_full_run() -> void:
	# Board, prepare nothing, drive, pass the bend, arrive at the terminus.
	await travel(Vector3(1,0,1.55))
	await spin(1.5)
	await start_from_console()
	await spin(2.0)
	while float(cart.get("distance")) < 30.0:
		await frames(1)
		await save_frame()
	await spin(1.0)
	while float(cart.get("distance")) < 46.0:
		await frames(1)
		await save_frame()
	await spin(1.0)
	while not bool(cart.get("arrived")):
		await frames(1)
		await save_frame()
	await spin(2.0)
	await travel(Vector3(1,0,1.55))
	await travel(Vector3(1,0,-2.0))
	await spin(2.0)

func record_platform() -> void:
	# Standing, walking, turning and gripping while the cart is moving.
	await travel(Vector3(1,0,1.55))
	await start_from_console()
	await spin(2.0)
	Input.action_press("move_right")
	await spin(1.4)
	Input.action_release("move_right")
	await spin(0.6)
	Input.action_press("move_left")
	await spin(1.4)
	Input.action_release("move_left")
	await spin(0.5)
	# Fast turn while standing still on the moving deck.
	for step: int in range(60):
		player.set("_camera_yaw_target", PI * 0.5 + float(step) * 0.055)
		await frames(1)
		await save_frame()
	await travel(Vector3(-0.7,1.91,1.44))
	await face(Vector3(-0.7,2.91,0.87))
	await press("repair")
	await spin(2.5)
	await press("repair")
	await spin(1.5)

func record_cargo() -> void:
	# Sliding, picking up, carrying, locking and the locked result.
	await travel(Vector3(1,0,1.55))
	await start_from_console()
	await spin(1.0)
	while float(cart.get("distance")) < 26.0:
		await frames(1)
		await save_frame()
	await spin(1.5)
	await press("cart_brake")
	await spin(1.5)
	await frames(60)
	var bodies: Array[RigidBody3D] = cargo.get("cargo") as Array[RigidBody3D]
	await pick_body(bodies[0])
	await spin(2.0)
	await lock_body(bodies[0], 0)
	await spin(2.0)
	await pick_body(bodies[1])
	await spin(1.0)
	await lock_body(bodies[1], 1)
	await spin(2.0)
	await start_from_console()
	await spin(3.0)

func record_event() -> void:
	# Loose cargo reaches the bend, slides, player brakes, locks, resumes.
	await travel(Vector3(1,0,1.55))
	await start_from_console()
	while float(cart.get("distance")) < 28.0:
		await frames(1)
		await save_frame()
	await spin(1.0)
	while float(cart.get("distance")) < 40.0:
		await frames(1)
		await save_frame()
	await spin(1.0)
	await press("cart_brake")
	await spin(2.5)
	var bodies: Array[RigidBody3D] = cargo.get("cargo") as Array[RigidBody3D]
	await pick_body(bodies[0])
	await lock_body(bodies[0], 0)
	await pick_body(bodies[1])
	await lock_body(bodies[1], 1)
	await spin(1.5)
	await start_from_console()
	await spin(3.0)
