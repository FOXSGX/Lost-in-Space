extends SceneTree

# Grip-in-motion evidence: the player holds the rail while the cart accelerates,
# enters the resonance bend, brakes and is released. Records frames for a clip
# and prints the glove-to-bar error every 30 frames, so "the grip follows the
# cart" is a number, not an impression.

const CART := preload("res://scripts/moving_cart.gd")
const GRIP_LOCAL := Vector3(-0.7, 2.905, 0.87)

var app: Node
var scene: Node3D
var player: CharacterBody3D
var cart: AnimatableBody3D
var output: String
var frame_index: int = 0
var worst: float = 0.0
var samples: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func _capture() -> void:
	frame_index += 1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("motion_%04d.png" % frame_index))

func _glove(side: String) -> Node3D:
	return (player.get("visual") as Node3D).find_child(side + "Glove", true, false) as Node3D

func _measure(tag: String) -> void:
	var bar: Vector3 = cart.call("to_global", GRIP_LOCAL) as Vector3
	var left: Node3D = _glove("Left")
	var right: Node3D = _glove("Right")
	var err: float = maxf(left.global_position.distance_to(bar - player.global_basis.x * 0.24),
		right.global_position.distance_to(bar + player.global_basis.x * 0.24))
	if samples.size() == 0:
		var pose_probe: RefCounted = player.get("pose") as RefCounted
		print("GRIP_STATE_MOTION brace=", player.get("brace_active"), " kind=", pose_probe.get("pose_kind"), " weight=%.2f" % float(pose_probe.get("weight")), " arms_ik=", (player.get("visual") as Node3D).get("arms_ik"))
	worst = maxf(worst, err)
	samples.append({"tag": tag, "distance": float(cart.get("distance")), "error": err,
		"grip": int(player.get("grip_id"))})
	print("GRIP_MOTION ", tag, " dist=%.1f err=%.3f grip=%d" % [float(cart.get("distance")), err, int(player.get("grip_id"))])

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	scene = app.get("stage") as Node3D
	player = scene.get("player") as CharacterBody3D
	cart = scene.get("cart") as AnimatableBody3D
	# Park just before the bend, board the rail and start the drive.
	cart.set("distance", 26.0)
	cart.global_transform = CART.route_pose(26.0)
	cart.reset_physics_interpolation()
	await _frames(20)
	player.global_position = cart.call("to_global", Vector3(-0.7, 1.91, 1.44)) as Vector3
	player.set("_camera_yaw_target", -PI * 0.5)
	await _frames(20)
	scene.call("request_action", "repair", 1)
	print("GRIP_ACQUIRED ", int(player.get("grip_id")))
	cart.call("start")
	await _frames(10)
	for step: int in range(150):
		await _frames(3)
		await _capture()
		if step % 9 == 0:
			_measure("ride")
	# Brake while still holding the rail, then release.
	scene.call("request_action", "cart_brake", 1)
	await _frames(30)
	_measure("braked")
	for i: int in range(30):
		await _frames(3)
		await _capture()
	scene.call("request_action", "repair", 1)
	await _frames(20)
	_measure("released")
	print("GRIP_WORST %.3f frames=%d" % [worst, frame_index])
	var f: FileAccess = FileAccess.open(output.path_join("grip-motion.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"worst": worst, "samples": samples}, "  "))
	f.close()
	print("PROBE_GRIP_MOTION_DONE")
	current_scene = null
	app.queue_free()
	await _frames(3)
	quit(0)
