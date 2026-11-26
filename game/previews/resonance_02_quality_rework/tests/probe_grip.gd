extends SceneTree

# Shows what "抓扶" currently looks like: player camera, a side camera on the
# deck, and a close-up of the hands/rail. Parked at the bend so the pose is
# captured in the place where the mechanic matters.

const CART := preload("res://scripts/moving_cart.gd")

var app: Node
var scene: Node3D
var output: String
var player: CharacterBody3D
var cart: AnimatableBody3D
var camera: Camera3D

func _initialize() -> void:
	run.call_deferred()

func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name))

func _look(at: Vector3, look: Vector3) -> void:
	camera.look_at_from_position(at, look, Vector3.UP)
	await _frames(4)

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("res://resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await _frames(3)
	app.call("start_cart")
	scene = app.get("stage") as Node3D
	player = scene.get("player") as CharacterBody3D
	cart = scene.get("cart") as AnimatableBody3D
	# Park at the bend and put the player right next to grip 1.
	cart.set("distance", 34.0)
	cart.set("running", false)
	cart.global_transform = CART.route_pose(34.0)
	cart.reset_physics_interpolation()
	await _frames(30)
	player.call("restore_at", cart.call("to_global", Vector3(-0.7, 1.91, 1.44)) as Vector3)
	player.set("_camera_yaw_target", -PI * 0.5)
	await _frames(40)
	await _shot("a_before_grip_player.png")

	scene.call("request_action", "repair", 1)
	await _frames(40)
	await _shot("b_gripping_player.png")
	# Measure whether both gloves actually reach the bar.
	var vis: Node3D = player.get("visual") as Node3D
	var arm_bone: Node3D = vis.find_child("LeftArmPivot", true, false) as Node3D
	var elbow_bone: Node3D = vis.find_child("LeftElbowPivot", true, false) as Node3D
	var glove_node: Node3D = vis.find_child("LeftGlove", true, false) as Node3D
	var rail_world: Vector3 = cart.call("to_global", Vector3(-0.7, 2.905, 0.87)) as Vector3
	print("GEO shoulder=", arm_bone.global_position, " elbow=", elbow_bone.global_position, " glove=", glove_node.global_position, " goal=", rail_world)
	print("GEO reach_a=%.3f reach_b=%.3f shoulder_goal=%.3f" % [(elbow_bone.global_position-arm_bone.global_position).length(), (glove_node.global_position-elbow_bone.global_position).length(), (rail_world-arm_bone.global_position).length()])
	var pose: RefCounted = player.get("pose") as RefCounted
	print("GRIP_STATE brace=", player.get("brace_active"), " target=", player.get("brace_target"), " kind=", pose.get("pose_kind"), " weight=%.2f" % float(pose.get("weight")), " grip=", player.get("grip_id"))
	for side: String in ["left", "right"]:
		var glove: Node3D = (player.get("visual") as Node3D).find_child(side.capitalize() + "Glove", true, false) as Node3D
		if glove == null: continue
		var rail_at: Vector3 = cart.call("to_global", Vector3(-0.7, 2.905, 0.87)) as Vector3
		var sign: float = -1.0 if side == "left" else 1.0
		var want: Vector3 = rail_at + player.global_basis.x * 0.24 * sign
		print("HAND ", side, " at=", glove.global_position, " want=", want,
			" err=%.3f" % glove.global_position.distance_to(want),
			" hand_error=%.3f" % float(pose.get("hand_error")))

	# Audit cameras, HUD hidden.
	(scene.get("hud") as CanvasLayer).visible = false
	player.set("paused", true)
	(player.get("camera") as Camera3D).current = false
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 120.0
	scene.add_child(camera)
	camera.current = true
	var rail: Vector3 = cart.call("to_global", Vector3(-0.7, 2.91, 0.87)) as Vector3
	var body: Vector3 = player.global_position + Vector3.UP * 1.1
	await _look(cart.call("to_global", Vector3(-2.6, 2.8, -2.2)) as Vector3, body)
	await _shot("c_grip_side.png")
	await _look(cart.call("to_global", Vector3(2.0, 2.7, -1.6)) as Vector3, body)
	await _shot("d_grip_front.png")
	await _look(cart.call("to_global", Vector3(-0.7, 2.85, 0.15)) as Vector3, rail)
	await _shot("e_grip_closeup_hands.png")
	print("PROBE_GRIP_DONE")
	current_scene = null
	app.queue_free()
	await _frames(3)
	quit(0)
